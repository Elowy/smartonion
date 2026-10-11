class_name WarriorHeroicLeap
extends AbilityEffect
## Heroic Leap (GDD 6.4, Warrior Active): the hero leaps onto the densest group of enemies
## within cast range (DENSEST_CLUSTER targeting) and lands with an impact: every enemy whose
## body touches the circle of [code]radius[/code] around the landing spot takes
## [code]damage_pct[/code] % weapon damage (times "power"). The hero flies over props, is
## invulnerable in the air and never lands inside a prop or off the shared screen.
##
## Params (AbilityData.params; items and ranks change them):
##   damage_pct, radius (Area Size scales it), height (peak of the jump, m)
##   stun           seconds of stun on everything hit (Rank III)
##   crater, crater_duration, crater_pct, crater_slow   Rank V "Crater": the landing leaves
##                  broken ground (AbilityArea) for crater_duration s that slows by crater_slow %
##                  and deals crater_pct % weapon damage per second (times "power")
##   knockback      Rank V "Shockwave": enemies hit are hurled away (weapon knockback units)
##
## Bots leap onto a group of at least AUTO_MIN_GROUP enemies (or an elite), not while reviving
## a teammate and not when badly hurt.

const DEFAULT_RADIUS := 3.0
const DEFAULT_HEIGHT := 2.2
## Air time: base + per metre of distance, clamped.
const AIR_TIME_BASE := 0.32
const AIR_TIME_PER_METRE := 0.035
const AIR_TIME_MAX := 0.7
## Invulnerability that outlasts the landing (s).
const INVULNERABLE_PAD := 0.15
const AUTO_MIN_GROUP := 3
const AUTO_MIN_HP := 0.3
const CRATER_COLOR := Color(0.55, 0.4, 0.25, 0.35)
const CRATER_TICK := 0.5
const DUST_COLOR := Color(0.75, 0.65, 0.5)
const IMPACT_SHAKE := 0.35

var _player: Player
var _flying := false
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _air_time := 0.5
var _t := 0.0
var _height := DEFAULT_HEIGHT
var _radius := DEFAULT_RADIUS
## The radius param before Area Size (AbilityArea applies Area Size itself).
var _base_radius := DEFAULT_RADIUS
var _damage_pct := 0.0
var _stun := 0.0
var _knockback := 0.0
var _crater_duration := 0.0
var _crater_pct := 0.0
var _crater_slow := 0.0
var _school: StringName = &"physical"
var _yaw: Node3D
var _marker: WarriorLeapVfx
## Enemies hit by the last landing (tests).
var last_hits := 0
## The last crater (tests).
var last_crater: AbilityArea


func is_flying() -> bool:
	return _flying


## Where the current / last leap lands.
func landing_point() -> Vector3:
	return _to


func can_cast(_ctx: AbilityContext) -> bool:
	return not _flying


## Impact radius in metres, with Area Size.
func reach_of(ctx: AbilityContext) -> float:
	return ctx.num("radius", DEFAULT_RADIUS) * CombatMath.area_mult(ctx.player.stats)


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or p.is_reviving() or ctx.target == null:
		return false
	if p.max_hp() > 0.0 and p.hp / p.max_hp() < AUTO_MIN_HP:
		return false
	var target := ctx.target as Enemy
	if WarriorKit.is_big(target):
		return true
	return EnemyGrid.count_around(p.get_tree(), ctx.target.global_position, reach_of(ctx)) >= AUTO_MIN_GROUP


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or _flying or ctx.target == null:
		return false
	_player = p
	_from = p.global_position
	_to = WarriorKit.landing_spot(p, _from, ctx.target.global_position)
	var distance := Vector2(_to.x - _from.x, _to.z - _from.z).length()
	_air_time = clampf(AIR_TIME_BASE + distance * AIR_TIME_PER_METRE, AIR_TIME_BASE, AIR_TIME_MAX)
	_t = 0.0
	_height = maxf(0.3, ctx.num("height", DEFAULT_HEIGHT))
	_radius = reach_of(ctx)
	_base_radius = ctx.num("radius", DEFAULT_RADIUS)
	_damage_pct = ctx.num("damage_pct", 200.0) * ctx.num("power", 1.0)
	_stun = ctx.num("stun")
	_knockback = ctx.num("knockback")
	_crater_duration = ctx.num("crater_duration", 3.0) if ctx.flag("crater") else 0.0
	_crater_pct = ctx.num("crater_pct", 40.0) * ctx.num("power", 1.0)
	_crater_slow = ctx.num("crater_slow", 50.0)
	_school = ctx.ability.school
	_flying = true
	if not p.downed_changed.is_connected(_on_downed_changed):
		p.downed_changed.connect(_on_downed_changed)
	p.velocity = Vector3.ZERO
	p.invulnerable_left = maxf(p.invulnerable_left, _air_time + INVULNERABLE_PAD)
	var d := Vector3(_to.x - _from.x, 0.0, _to.z - _from.z)
	if d.length_squared() > 0.0001:
		p.facing = d.normalized()
	_yaw = p.model.get_node_or_null("Yaw") as Node3D if p.model != null else null
	Vfx.death_puff(_from + Vector3.UP * 0.2, DUST_COLOR, 0.8)
	_marker = WarriorLeapVfx.spawn_marker(_to, _radius, _air_time)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if not _flying:
		return
	var p := _player
	if p == null or not is_instance_valid(p):
		_flying = false
		return
	_t += delta
	var f := clampf(_t / _air_time, 0.0, 1.0)
	var pos := _from.lerp(_to, f)
	if p.is_inside_tree():
		p.global_position = Vector3(pos.x, _from.y, pos.z)
	else:
		p.position = Vector3(pos.x, _from.y, pos.z)
	p.velocity = Vector3.ZERO
	p.invulnerable_left = maxf(p.invulnerable_left, INVULNERABLE_PAD)
	_lift(4.0 * _height * f * (1.0 - f))
	if f >= 1.0:
		_land(p)


func begin_wave(_ctx: AbilityContext) -> void:
	_abort()


## The market shows the hero on the ground (also when the ability is forgotten).
func end_wave(_ctx: AbilityContext) -> void:
	_abort()


## The impact: damage, stun, knockback, crater.
func _land(p: Player) -> void:
	_flying = false
	_lift(0.0)
	_marker = null
	last_hits = 0
	if not p.is_inside_tree():
		return
	var here := p.global_position
	var damage := WarriorKit.weapon_damage(p) * _damage_pct / 100.0
	for e in WarriorKit.enemies_within(p, _radius):
		if not is_instance_valid(e) or e.is_dead():
			continue
		last_hits += 1
		if p.procs != null:
			p.procs.deal_raw(e, damage, _school, true, &"ability")
		if _stun > 0.0:
			e.apply_stun(_stun)
		if _knockback > 0.0:
			WarriorKit.knock_back(e, here, _knockback)
	WarriorLeapVfx.spawn_impact(here, _radius)
	Vfx.death_puff(here + Vector3.UP * 0.3, DUST_COLOR, 1.4)
	WarriorKit.shake(IMPACT_SHAKE)
	if _crater_duration > 0.0:
		var area := AbilityArea.spawn(p, here, _base_radius, _crater_duration, CRATER_COLOR)
		if area.is_inside_tree():
			area.school = _school
			area.tick_interval = CRATER_TICK
			area.damage_per_tick = WarriorKit.weapon_damage(p) * _crater_pct / 100.0 * CRATER_TICK
			area.slow_pct = _crater_slow
			last_crater = area
		else:
			area.free()


## Stops a leap in the air: the hero stays where it is, back on the ground.
func _abort() -> void:
	_flying = false
	_lift(0.0)
	if is_instance_valid(_marker) and not _marker.is_queued_for_deletion():
		_marker.queue_free()
	_marker = null


## Raises the hero's model (not the body) [param height] metres for the jump arc.
func _lift(height: float) -> void:
	if is_instance_valid(_yaw):
		_yaw.position.y = height


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		_abort()
