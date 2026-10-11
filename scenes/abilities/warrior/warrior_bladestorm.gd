class_name WarriorBladestorm
extends AbilityEffect
## Bladestorm (GDD 6.4, Warrior Auto-cast): the hero becomes a whirling storm of steel for
## [code]duration[/code] seconds – every [code]tick_interval[/code] every enemy within
## [code]radius[/code] takes a share of [code]damage_pct[/code] % weapon damage (total per enemy
## over the BASE duration, times "power"; a longer storm hits more often). The hero keeps
## moving and is Unstoppable meanwhile: nothing slows it – the stat source UNSTOPPABLE_SOURCE
## cancels any negative Speed (the Warrior's -5 %, item penalties) for the storm.
##
## Params (AbilityData.params; items and ranks change them):
##   damage_pct, duration (Rank III +1 s), tick_interval, radius (Area Size scales it)
##   leech      Rank V "Bloodstorm": the hero heals this % of the damage dealt
##   ravager    Rank V "Ravager": the storm is a thrown axe whirling on the densest group within
##              cast range (DENSEST_CLUSTER target) instead of around the hero (no Unstoppable)
##
## Auto-cast: at least AUTO_MIN_ENEMIES enemies (or an elite / boss) within reach of the storm.

const UNSTOPPABLE_SOURCE := &"bladestorm"
const DEFAULT_RADIUS := 3.0
const DEFAULT_INTERVAL := 0.25
const AUTO_MIN_ENEMIES := 3
const SPIN_ARCS := 4
const SPIN_TURNS := 3.5
## Turns per second of the hero's model while it storms.
const MODEL_TURNS := 2.5
const SPARK_COLOR := Color(0.9, 0.93, 1.0)
const TEXT_COLOR := Color(0.85, 0.9, 1.0)

var _player: Player
var _spin := WarriorSpin.new()
var _ravager := false
var _unstoppable := false
var _turn := 0.0


func is_storming() -> bool:
	return _spin.is_running()


## True while the hero itself storms (not a Ravager axe): no slows.
func is_unstoppable() -> bool:
	return _unstoppable


## The running / last storm (tests).
func spin() -> WarriorSpin:
	return _spin


func can_cast(_ctx: AbilityContext) -> bool:
	return not is_storming()


## Storm radius in metres, with Area Size.
func reach_of(ctx: AbilityContext) -> float:
	return ctx.num("radius", DEFAULT_RADIUS) * CombatMath.area_mult(ctx.player.stats)


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var reach := reach_of(ctx)
	if ctx.flag("ravager"):
		var target := ctx.target as Enemy
		if target == null:
			return false
		return WarriorKit.is_big(target) \
				or EnemyGrid.count_around(p.get_tree(), target.global_position, reach) >= AUTO_MIN_ENEMIES
	var close := WarriorKit.enemies_within(p, reach)
	if close.size() >= AUTO_MIN_ENEMIES:
		return true
	for e in close:
		if e.is_elite():
			return true
	return false


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or is_storming():
		return false
	var ravager := ctx.flag("ravager")
	if ravager and ctx.target == null:
		return false
	_player = p
	_ravager = ravager
	var interval := maxf(0.05, ctx.num("tick_interval", DEFAULT_INTERVAL))
	var duration := maxf(interval, ctx.num("duration", 3.0))
	var base_duration := maxf(interval, float(ctx.ability.params.get("duration", duration)))
	var base_ticks := maxi(1, roundi(base_duration / interval))
	_spin.interval = interval
	_spin.radius = reach_of(ctx)
	_spin.hit_pct = ctx.num("damage_pct", 300.0) * ctx.num("power", 1.0) / float(base_ticks)
	_spin.school = ctx.ability.school
	_spin.slow = 0.0
	_spin.leech = ctx.num("leech")
	_spin.spark_color = SPARK_COLOR
	var anchor: Node3D = p
	if _ravager:
		var axe := WarriorRavagerAxe.spawn(p, p.global_position, ctx.target.global_position, duration)
		if axe == null:
			return false
		anchor = axe
		_spin.look = axe
		WarriorSpinVfx.spawn(axe, _spin.radius, duration, ctx.ability.color, SPIN_ARCS, SPIN_TURNS, "BladestormSpin")
	else:
		_spin.look = WarriorSpinVfx.spawn(p, _spin.radius, duration, ctx.ability.color, SPIN_ARCS, SPIN_TURNS,
				"BladestormSpin", true)
		_set_unstoppable(p)
		_turn = OnionModel.yaw_for(p.facing)
	if not p.downed_changed.is_connected(_on_downed_changed):
		p.downed_changed.connect(_on_downed_changed)
	WarriorKit.shout_text(p, ctx.ability.display_name, TEXT_COLOR)
	_spin.start(p, anchor, duration)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if not _spin.is_running():
		return
	_spin.tick(delta)
	if not _spin.is_running():
		_clear_unstoppable()
	elif _unstoppable and is_instance_valid(_player) and _player.model != null:
		# The onion spins with its blades (the walk sets the facing every frame before this).
		_turn += delta * TAU * MODEL_TURNS
		_player.model.set_facing(Vector3(-sin(_turn), 0.0, -cos(_turn)))


func begin_wave(_ctx: AbilityContext) -> void:
	stop()


## The market shows no storm (also when the ability is forgotten).
func end_wave(_ctx: AbilityContext) -> void:
	stop()


## Ends the storm now (its look, the Ravager axe and Unstoppable too).
func stop() -> void:
	_spin.stop()
	_clear_unstoppable()


func _set_unstoppable(p: Player) -> void:
	p.stats.remove_source(UNSTOPPABLE_SOURCE)
	var speed := p.stats.get_raw(Stats.SPEED)
	p.stats.set_source(UNSTOPPABLE_SOURCE, {Stats.SPEED: maxf(0.0, -speed)})
	_unstoppable = true


func _clear_unstoppable() -> void:
	if _unstoppable and is_instance_valid(_player):
		_player.stats.remove_source(UNSTOPPABLE_SOURCE)
	_unstoppable = false


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		stop()
