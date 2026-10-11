class_name WarriorWhirlwind
extends AbilityEffect
## Whirlwind (GDD 3.1): a short spin that hits every enemy around the hero for weapon damage.
## The hero keeps moving and can use Charge meanwhile; the spin cannot be recast while it runs.
##
## Params (AbilityData.params, items change them through ability_mod):
##   damage_pct     total weapon damage per enemy over the BASE duration (150 = 150%)
##   duration       spin length in seconds (item: duration_add)
##   tick_interval  seconds between two hits; each hit is damage_pct / base ticks, so a longer
##                  spin hits more often (and harder in total)
##   radius         reach around the hero in metres (Area Size scales it)
##   slow, slow_duration   % movement slow on every hit enemy (0 = none)

## Bots spin when at least this many enemies are within reach ...
const AUTO_MIN_ENEMIES := 3
## ... or one enemy when the Rage bar is full (do not waste Rage).
const AUTO_FULL_RAGE_ENEMIES := 1
const DEFAULT_RADIUS := 3.0
const DEFAULT_INTERVAL := 0.25
const DEFAULT_SLOW_DURATION := 1.5
## Hit sparks per pulse (the damage numbers already show every hit).
const MAX_SPARKS := 4
const SPARK_HEIGHT := 0.6
const SPARK_COLOR := Color(1.0, 0.55, 0.3)

var _player: Player
var _left := 0.0
var _tick_left := 0.0
var _ticks_done := 0
var _ticks_total := 0
var _interval := DEFAULT_INTERVAL
var _radius := DEFAULT_RADIUS
var _tick_pct := 0.0
var _school: StringName = &"physical"
var _slow := 0.0
var _slow_duration := DEFAULT_SLOW_DURATION


func is_spinning() -> bool:
	return _left > 0.0


func can_cast(_ctx: AbilityContext) -> bool:
	return not is_spinning()


func wants_auto_cast(ctx: AbilityContext) -> bool:
	if ctx.player == null:
		return false
	var count := WarriorKit.enemies_within(ctx.player, reach_of(ctx)).size()
	if count >= AUTO_MIN_ENEMIES:
		return true
	var rage := ctx.player.abilities.primary_resource() if ctx.player.abilities != null else null
	return count >= AUTO_FULL_RAGE_ENEMIES and rage != null and rage.is_full()


## Reach around the hero in metres, with Area Size.
func reach_of(ctx: AbilityContext) -> float:
	return ctx.num("radius", DEFAULT_RADIUS) * CombatMath.area_mult(ctx.player.stats)


func cast(ctx: AbilityContext) -> bool:
	if ctx.player == null or is_spinning():
		return false
	_player = ctx.player
	_school = ctx.ability.school
	_interval = maxf(0.05, ctx.num("tick_interval", DEFAULT_INTERVAL))
	_radius = reach_of(ctx)
	var duration := maxf(_interval, ctx.num("duration", 1.0))
	var base_duration := maxf(_interval, float(ctx.ability.params.get("duration", duration)))
	var base_ticks := maxi(1, roundi(base_duration / _interval))
	_ticks_total = maxi(1, roundi(duration / _interval))
	_tick_pct = ctx.num("damage_pct", 150.0) / float(base_ticks)
	_slow = ctx.num("slow")
	_slow_duration = ctx.num("slow_duration", DEFAULT_SLOW_DURATION)
	_left = duration
	_ticks_done = 0
	_tick_left = 0.0
	WarriorSpinVfx.spawn(_player, _radius, duration, ctx.ability.color)
	if not _player.downed_changed.is_connected(_on_downed_changed):
		_player.downed_changed.connect(_on_downed_changed)
	# The first hit lands with the cast, the rest follow every interval.
	_pulse()
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _left <= 0.0:
		return
	_left = maxf(0.0, _left - delta)
	_tick_left -= delta
	while _tick_left <= 0.0 and _ticks_done < _ticks_total:
		_pulse()
	if _ticks_done >= _ticks_total and _left <= 0.0:
		_player = null


## One hit of the spin on everything in reach.
func _pulse() -> void:
	_ticks_done += 1
	_tick_left += _interval
	if _player == null or not is_instance_valid(_player) or _player.procs == null:
		return
	var damage := WarriorKit.weapon_damage(_player) * _tick_pct / 100.0
	var sparks := 0
	for e in WarriorKit.enemies_within(_player, _radius):
		if not is_instance_valid(e) or e.is_dead():
			continue
		var spot := e.global_position + Vector3.UP * SPARK_HEIGHT
		_player.procs.deal_raw(e, damage, _school, true, &"ability")
		if _slow > 0.0 and is_instance_valid(e):
			e.apply_slow(_slow, _slow_duration)
		if sparks < MAX_SPARKS:
			sparks += 1
			Vfx.hit_spark(spot, SPARK_COLOR)


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		_left = 0.0
