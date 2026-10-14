class_name WarriorWhirlwind
extends AbilityEffect
## Whirlwind (GDD 3.1): a short spin that hits every enemy around the hero for weapon damage.
## The hero keeps moving and can use Charge meanwhile; the spin cannot be recast while it runs.
##
## Params (AbilityData.params; items and ranks change them):
##   damage_pct     total weapon damage per enemy over the BASE duration (150 = 150%), times
##                  "power" (Rank II / IV)
##   duration       spin length in seconds (item: duration_add)
##   tick_interval  seconds between two hits; each hit is damage_pct / base ticks, so a longer
##                  spin hits more often (and harder in total)
##   radius         reach around the hero in metres (Area Size scales it; Rank III +1 m)
##   slow, slow_duration   % movement slow on every hit enemy (0 = none)
##   leech          % of the damage dealt healed to the hero (Rank V "Bloodbath")
##   rage_per_enemy Rage refunded the first time the spin strikes each enemy (0 = none; Fury
##                  talent "Meat Cleaver" adds 3; not "power"-scaled, Resource Regen applies)
##   rage_per_enemy_max  at most this much refund per spin (before Resource Regen; 12)
## Rank V "Unrelenting" lowers the Rage cost (cost_add).
## Artifact (Earthsplitter, "Earthquake"): quake_duration (s, 0 = off) / quake_pct (% weapon
## damage per tick) / quake_tick (s): the cast also leaves an earthquake zone of the spin's base
## radius at the hero's feet for quake_duration seconds (an AbilityArea: it ticks weapon damage
## on every enemy inside and is swept at the wave end like any ground effect).
##
## Meat Cleaver: a spin never refunds more Rage than this cast paid
## (AbilityRunner.last_paid – 0 for a free cast, so a free spin refunds nothing); the Rage
## actually gained per spin, Resource Regen included, stays within that payment too. Refunds
## earned by the first hit (inside cast(), before the runner spends the cost) are paid once the
## cast is settled (ability_cast, or the next tick), so a full Rage bar does not swallow them.

## Bots spin when at least this many enemies are within reach ...
const AUTO_MIN_ENEMIES := 3
## ... or one enemy when the Rage bar is full (do not waste Rage).
const AUTO_FULL_RAGE_ENEMIES := 1
const DEFAULT_RADIUS := 3.0
const DEFAULT_INTERVAL := 0.25
const DEFAULT_SLOW_DURATION := 1.5
const SPARK_COLOR := Color(1.0, 0.55, 0.3)
const DEFAULT_RAGE_PER_ENEMY_MAX := 12.0
const DEFAULT_QUAKE_TICK := 0.5
const QUAKE_COLOR := Color(0.78, 0.5, 0.25, 0.4)

var _player: Player
var _spin := WarriorSpin.new()
## Meat Cleaver state of the current spin: Rage per newly struck enemy, the refund cap in
## refund units (min(rage_per_enemy_max, paid)), the Rage this cast paid, the refund units
## granted, the Rage gained (Resource Regen included) and the Rage owed until the cast settles.
var _refund_per_enemy := 0.0
var _refund_cap := 0.0
var _paid := 0.0
var _refunded := 0.0
var _refund_gained := 0.0
var _refund_owed := 0.0
var _casting := false
var _ability_id: StringName = &""


## Rage this spin refunded so far (Resource Regen included; tests, balancing).
func refund_gained() -> float:
	return _refund_gained


func is_spinning() -> bool:
	return _spin.is_running()


## The running spin (tests: totals of the last spin).
func spin() -> WarriorSpin:
	return _spin


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
	var interval := maxf(0.05, ctx.num("tick_interval", DEFAULT_INTERVAL))
	var duration := maxf(interval, ctx.num("duration", 1.0))
	var base_duration := maxf(interval, float(ctx.ability.params.get("duration", duration)))
	var base_ticks := maxi(1, roundi(base_duration / interval))
	_spin.interval = interval
	_spin.radius = reach_of(ctx)
	_spin.hit_pct = ctx.num("damage_pct", 150.0) * ctx.num("power", 1.0) / float(base_ticks)
	_spin.school = ctx.ability.school
	_spin.slow = ctx.num("slow")
	_spin.slow_duration = ctx.num("slow_duration", DEFAULT_SLOW_DURATION)
	_spin.leech = ctx.num("leech")
	_spin.spark_color = SPARK_COLOR
	_setup_refund(ctx)
	_spin.look = WarriorSpinVfx.spawn(_player, _spin.radius, duration, ctx.ability.color)
	if not _player.downed_changed.is_connected(_on_downed_changed):
		_player.downed_changed.connect(_on_downed_changed)
	# The first hit lands with the cast, the rest follow every interval.
	_casting = true
	_spin.start(_player, _player, duration)
	_casting = false
	_spawn_quake(ctx)
	return true


## Earthsplitter's "Earthquake": a ground zone at the hero's feet that ticks weapon damage.
func _spawn_quake(ctx: AbilityContext) -> void:
	var quake := ctx.num("quake_duration")
	var pct := ctx.num("quake_pct")
	if quake <= 0.0 or pct <= 0.0 or not _player.is_inside_tree():
		return
	var area := AbilityArea.spawn(_player, _player.global_position, ctx.num("radius", DEFAULT_RADIUS),
			quake, QUAKE_COLOR)
	if not area.is_inside_tree():
		area.free()
		return
	area.school = ctx.ability.school
	area.tick_interval = maxf(0.1, ctx.num("quake_tick", DEFAULT_QUAKE_TICK))
	area.damage_per_tick = WarriorKit.weapon_damage(_player) * pct / 100.0
	WarriorClapVfx.spawn(area.global_position, area.radius, true)


func tick(_ctx: AbilityContext, delta: float) -> void:
	_pay_owed()
	_spin.tick(delta)


func begin_wave(_ctx: AbilityContext) -> void:
	_stop()


## The market shows no spin (also when the ability is forgotten).
func end_wave(_ctx: AbilityContext) -> void:
	_stop()


func _stop() -> void:
	_spin.stop()
	_refund_owed = 0.0


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		_stop()


## Meat Cleaver: reads rage_per_enemy / rage_per_enemy_max and this cast's payment.
func _setup_refund(ctx: AbilityContext) -> void:
	_ability_id = ctx.ability.id
	_refund_per_enemy = maxf(0.0, ctx.num("rage_per_enemy"))
	_paid = _player.abilities.last_paid(ctx.ability) if _player.abilities != null else 0.0
	_refund_cap = minf(maxf(0.0, ctx.num("rage_per_enemy_max", DEFAULT_RAGE_PER_ENEMY_MAX)), _paid)
	_refunded = 0.0
	_refund_gained = 0.0
	_refund_owed = 0.0
	if _refund_per_enemy > 0.0 and _refund_cap > 0.0:
		_spin.on_first_strike = _on_first_strike
		if _player.abilities != null and not _player.abilities.ability_cast.is_connected(_on_ability_cast):
			_player.abilities.ability_cast.connect(_on_ability_cast)
	else:
		_spin.on_first_strike = Callable()


## WarriorSpin.on_first_strike: one refund per newly struck enemy, clipped to the spin's cap.
func _on_first_strike(_enemy: Enemy) -> void:
	var units := minf(_refund_per_enemy, _refund_cap - _refunded)
	if units <= 0.0 or _player == null or not is_instance_valid(_player) or _player.abilities == null:
		return
	_refunded += units
	var rage := _player.abilities.get_resource(WarriorKit.RAGE)
	if rage == null:
		return
	# Resource Regen scales the refund like any Rage gain; never more than the cast paid.
	var gain := minf(units * rage.gain_mult, _paid - _refund_gained)
	if gain <= 0.0:
		return
	_refund_gained += gain
	if _casting:
		_refund_owed += gain
	else:
		rage.add(gain, false)


## The runner spent the cast's cost: the refunds of the first hit are paid now.
func _on_ability_cast(_slot_index: int, ability: AbilityData) -> void:
	if ability != null and ability.id == _ability_id:
		_pay_owed()


func _pay_owed() -> void:
	if _refund_owed <= 0.0:
		return
	var owed := _refund_owed
	_refund_owed = 0.0
	if _player != null and is_instance_valid(_player) and _player.abilities != null:
		var rage := _player.abilities.get_resource(WarriorKit.RAGE)
		if rage != null:
			rage.add(owed, false)
