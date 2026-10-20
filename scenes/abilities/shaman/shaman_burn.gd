class_name ShamanBurn
extends Node3D
## A burn of the Magma Lash (M8): [member rate] x [member left] Fire damage still to come, dealt every
## [constant TICK] seconds through the Shaman's ProcSystem.deal_raw(..., &"dot") (kill credit, damage meter,
## Mastery multipliers; no crits, no on-hit procs, never Storm Echo eligible). Child of the burning enemy
## (freed with it) with a few flames on its body. A new burn of the same Shaman on the same enemy adds its
## damage to what is still burning and restarts the clock (one burn per caster per enemy). Keeps burning
## while the Shaman is downed; ends when it is freed.
##
## Spread: a burn that may spread ([member spreads] with [member spread_targets] > 0) passes its fire on when
## it burns out with the enemy alive or when the enemy dies while burning (Enemy.died; the corpse already left
## the enemies group, so only its neighbours are hit): up to spread_targets enemies within spread_radius m
## (Area Size counts) that do not burn from this Shaman yet start a burn of spread_pct % of this burn's
## starting damage over the same time. Spread burns never spread again. The spread happens once.

const TICK := 0.5
const EPSILON := 0.0001
const FLAME_HIGH := Color(1.0, 0.7, 0.2, 0.95)
const FLAME_LOW := Color(0.9, 0.2, 0.04, 0.0)

var caster: Player
var enemy: Enemy
var school: StringName = &"fire"
## Damage per second still to come, seconds left, the damage it started with, the damage dealt so far.
var rate := 0.0
var left := 0.0
var total := 0.0
var dealt := 0.0
var ticks := 0
## Whether this burn passes its fire on, to how many enemies, how far, and at what share.
var spreads := false
var spread_targets := 0
var spread_radius := 3.0
var spread_pct := 50.0
## The burn has spread already (tests: it happens once).
var spread_done := false
var spread_hits := 0

var _tick_left := TICK
var _owed := 0.0
var _duration := 4.0


## Sets [param e] burning for [param p_total] damage over [param duration] seconds (added to a running
## burn of the same [param p_caster]). Null when nothing burns. [param spread_count] > 0 lets the burn
## spread when it ends ([param p_radius] m, [param p_pct] % strength).
static func apply(e: Enemy, p_caster: Player, p_total: float, duration: float, spread_count: int = 0,
		p_radius: float = 3.0, p_pct: float = 50.0) -> ShamanBurn:
	if not ShamanKit.is_live(e) or p_caster == null or p_total <= 0.0 or duration <= 0.0:
		return null
	var burn := find(e, p_caster)
	if burn != null:
		p_total += burn.remaining()
		burn._owed = 0.0
	else:
		burn = ShamanBurn.new()
		burn.name = _key(p_caster)
		burn.caster = p_caster
		burn.enemy = e
		e.add_child(burn)
		burn.position = Vector3.UP * Enemy.BODY_CENTER_HEIGHT
		burn._build_flames(e.radius)
	burn.left = duration
	burn._duration = duration
	burn.total = p_total
	burn.rate = p_total / duration
	if spread_count > 0:
		burn.spreads = true
		burn.spread_targets = maxi(burn.spread_targets, spread_count)
		burn.spread_radius = p_radius
		burn.spread_pct = p_pct
		if not e.died.is_connected(burn._on_enemy_died):
			e.died.connect(burn._on_enemy_died, CONNECT_ONE_SHOT)
	return burn


## The running burn of [param p_caster] on [param e] (null = none).
static func find(e: Enemy, p_caster: Player) -> ShamanBurn:
	if not is_instance_valid(e) or p_caster == null:
		return null
	var burn := e.get_node_or_null(NodePath(_key(p_caster))) as ShamanBurn
	if burn == null or burn.is_queued_for_deletion() or burn.left <= EPSILON:
		return null
	return burn


## Damage still to come (incl. what burnt since the last tick).
func remaining() -> float:
	return rate * maxf(0.0, left) + _owed


func _physics_process(delta: float) -> void:
	if is_queued_for_deletion():
		return
	if not ShamanKit.is_live(enemy) or not is_instance_valid(caster):
		_end()
		return
	_owed += rate * clampf(left, 0.0, delta)
	left -= delta
	_tick_left -= delta
	if _tick_left > EPSILON and left > EPSILON:
		return
	_tick_left += TICK
	var amount := _owed
	_owed = 0.0
	if amount > 0.0 and caster.procs != null:
		ticks += 1
		dealt += caster.procs.deal_raw(enemy, amount, school, true, &"dot")
	if left <= EPSILON and ShamanKit.is_live(enemy) and is_instance_valid(caster):
		_spread(enemy.global_position)  # burnt out: the fire jumps on
	if left <= EPSILON or not ShamanKit.is_live(enemy):
		_end()


## The enemy died while this burn was on it (Enemy.died, after it left the enemies group).
func _on_enemy_died(dead: Enemy, _killer_index: int) -> void:
	if is_queued_for_deletion() or not is_instance_valid(caster) or not is_instance_valid(dead) \
			or not dead.is_inside_tree():
		return
	_spread(dead.global_position)


## Passes the fire on to the nearest not-yet-burning enemies around [param at] (once).
func _spread(at: Vector3) -> void:
	if not spreads or spread_done or spread_targets <= 0 or not is_inside_tree() or caster.procs == null:
		return
	spread_done = true
	var strength := total * spread_pct / 100.0
	if strength <= 0.0:
		return
	var radius := spread_radius * CombatMath.area_mult(caster.stats)
	var near := ShamanKit.enemies_around(get_tree(), at, radius)
	near.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return ShamanKit.flat_distance(a.global_position, at) < ShamanKit.flat_distance(b.global_position, at))
	var started := 0
	for e in near:
		if started >= spread_targets:
			break
		if e == enemy or find(e, caster) != null:
			continue
		if apply(e, caster, strength, _duration) != null:
			started += 1
			spread_hits += 1


func _end() -> void:
	set_physics_process(false)
	# Free the name at once so a new burn can take it while this one waits for deletion.
	name = "SpentBurn"
	queue_free()


static func _key(p_caster: Player) -> String:
	return "ShamanBurn%d" % p_caster.get_instance_id()


## Small flames licking up the body (world-space particles: they trail a walking enemy).
func _build_flames(body_radius: float) -> void:
	var p := CPUParticles3D.new()
	p.name = "Flames"
	p.amount = 10
	p.lifetime = 0.5
	p.local_coords = false
	p.mesh = MeshKit.cached("shaman:flame", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.1
		s.height = 0.24
		s.radial_segments = 6
		s.rings = 3
		return s)
	p.material_override = Mats.particle(false)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(0.15, body_radius * 0.6)
	p.direction = Vector3.UP
	p.spread = 18.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0.0, 1.5, 0.0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	var g := Gradient.new()
	g.set_color(0, FLAME_HIGH)
	g.set_color(1, FLAME_LOW)
	p.color_ramp = g
	p.emitting = true
	add_child(p)
