class_name GeneralWarStomp
extends AbilityEffect
## War Stomp (GDD 6.4, general Auto-cast): when enemies crowd the hero it stomps the ground –
## every enemy touching the radius m circle takes damage_pct % weapon damage (Physical,
## GeneralKit.weapon_damage: the main-hand hit normalised to a 1 s swing, x power) and is
## stunned for stun seconds (stun resistance applies; the stun is NOT scaled by power – ranks
## make it hit harder, not lock enemies down longer).
## Auto-cast: at least min_enemies enemies in reach, or one while the hero is below auto_hp %.
##
## Params (rank / spec / item mods change them):
##   damage_pct, radius (Area Size scales it), stun, min_enemies, auto_hp
##   aftershocks, aftershock_delay      Aftershock (spec): further stomps around the hero
##   tremor_duration, tremor_slow, tremor_pct   Tremor Field (spec): the ground keeps shaking –
##                    an AbilityArea that slows (x power), stuns newcomers once and deals
##                    tremor_pct % weapon damage every TREMOR_TICK s

const DEFAULT_RADIUS := 2.5
const TREMOR_TICK := 0.5
const TREMOR_COLOR := Color(0.7, 0.55, 0.32, 0.28)
const SPARK_COLOR := Color(0.95, 0.82, 0.55)
const MAX_SPARKS := 5

var _player: Player
var _aftershocks_left := 0
var _aftershock_timer := 0.0
var _aftershock_delay := 1.0
var _damage := 0.0
var _radius := DEFAULT_RADIUS
var _stun := 1.0
var _school: StringName = &"physical"
## Enemies hit by the last stomp (tests).
var last_victims: Array[Enemy] = []
## The last Tremor Field (tests; may be freed).
var tremor: AbilityArea


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_alive():
		return false
	var count := GeneralKit.enemies_near(player, reach_of(ctx)).size()
	if count >= maxi(1, roundi(ctx.num("min_enemies", 2.0))):
		return true
	return count >= 1 and GeneralKit.hp_ratio(player) < ctx.num("auto_hp", 50.0) / 100.0


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_alive() or not player.is_inside_tree():
		return false
	_player = player
	_school = ctx.ability.school
	_radius = reach_of(ctx)
	_stun = maxf(0.0, ctx.num("stun", 1.0))
	_damage = stomp_damage(ctx)
	stomp()
	_aftershocks_left = maxi(0, roundi(ctx.num("aftershocks")))
	_aftershock_delay = maxf(0.1, ctx.num("aftershock_delay", 1.0))
	_aftershock_timer = _aftershock_delay
	if not player.downed_changed.is_connected(_on_downed_changed):
		player.downed_changed.connect(_on_downed_changed)
	var tremor_time := ctx.num("tremor_duration")
	if tremor_time > 0.0:
		_tremor(ctx, tremor_time)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _aftershocks_left <= 0:
		return
	_aftershock_timer -= delta
	if _aftershock_timer <= GeneralKit.TIME_EPSILON:
		_aftershocks_left -= 1
		_aftershock_timer += _aftershock_delay
		stomp()


func begin_wave(_ctx: AbilityContext) -> void:
	_reset()


func end_wave(_ctx: AbilityContext) -> void:
	_reset()


func pending_aftershocks() -> int:
	return _aftershocks_left


## Reach around the hero in metres (Area Size included).
static func reach_of(ctx: AbilityContext) -> float:
	return ctx.num("radius", DEFAULT_RADIUS) * CombatMath.area_mult(ctx.player.stats)


## Damage of one stomp per enemy (x power), before target bonuses.
static func stomp_damage(ctx: AbilityContext) -> float:
	return GeneralKit.weapon_damage(ctx.player, ctx.ability.school) * ctx.num("damage_pct", 60.0) / 100.0 \
			* ctx.num("power", 1.0)


## One stomp around the hero (damage, stun, shockwave).
func stomp() -> void:
	last_victims.clear()
	if _player == null or not is_instance_valid(_player) or not _player.is_alive() or not _player.is_inside_tree():
		return
	var center := _player.global_position
	var sparks := 0
	for e in GeneralKit.enemies_around(_player.get_tree(), center, _radius):
		last_victims.append(e)
		var spot := e.global_position + Vector3.UP * 0.6
		if _player.procs != null and _damage > 0.0:
			_player.procs.deal_raw(e, _damage, _school, true, &"ability")
		if is_instance_valid(e) and not e.is_dead() and _stun > 0.0:
			e.apply_stun(_stun)
		if sparks < MAX_SPARKS:
			sparks += 1
			Vfx.hit_spark(spot, SPARK_COLOR)
	GeneralStompVfx.spawn(center, _radius)


func _tremor(ctx: AbilityContext, seconds: float) -> void:
	var area := AbilityArea.spawn(_player, _player.global_position, ctx.num("radius", DEFAULT_RADIUS), seconds, TREMOR_COLOR)
	if not area.is_inside_tree():
		area.free()
		return
	area.school = _school
	area.tick_interval = TREMOR_TICK
	area.slow_pct = clampf(ctx.num("tremor_slow", 50.0) * ctx.num("power", 1.0), 0.0, 90.0)
	area.stun = _stun
	area.damage_per_tick = GeneralKit.weapon_damage(_player, _school) * ctx.num("tremor_pct", 10.0) / 100.0 \
			* ctx.num("power", 1.0)
	GeneralTremorVfx.attach(area)
	tremor = area


func _reset() -> void:
	_aftershocks_left = 0
	if tremor != null and is_instance_valid(tremor) and not tremor.is_queued_for_deletion():
		tremor.queue_free()
	tremor = null


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		_aftershocks_left = 0
