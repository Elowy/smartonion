class_name MageMeteorStrike
extends Node3D
## One falling meteor of Meteor: a burning rock drops out of the sky (screen up-right) onto
## its spot while a ring on the ground fills as the warning, and lands after
## [member fall_time] seconds (physics ticks – deterministic): [member damage] Fire damage
## (caster's ProcSystem.deal_raw(..., &"ability")) to every enemy within [member radius],
## an optional stun, then burning ground – an [AbilityArea] of [member ground_radius] m
## (Area Size is applied by the area) for [member ground_duration] seconds.
## Group &"ability_areas": a wave end removes a meteor that has not landed yet; a freed
## caster lands nothing.

## Emitted when it lands (after the impact, with [member ground] set).
signal landed_at(strike: MageMeteorStrike)

const FALL_HEIGHT := 7.0
const FALL_SLANT := Vector3(2.4, 0.0, -1.6)
const EPSILON := 0.0001
const GROUND_COLOR := Color(1.0, 0.36, 0.06, 0.32)
const WARN_COLOR := Color(1.0, 0.45, 0.1, 0.9)

var caster: Player
var radius := 3.0
var damage := 0.0
var stun := 0.0
var fall_time := 0.9
var ground_radius := 3.0
var ground_duration := 4.0
var ground_tick := 0.5
var ground_damage := 0.0
var landed := false
## Enemies the impact damaged and the burning ground it left (tests, bots).
var hits := 0
var ground: AbilityArea

var _left := 0.9
var _age := 0.0
var _rock: Node3D
var _warn: MeshInstance3D


## A meteor of [param p_caster] landing on [param center] in [param p_fall] seconds, under
## the arena's entities (or next to the caster). Configure it before the next physics tick.
static func spawn(p_caster: Player, center: Vector3, p_fall: float) -> MageMeteorStrike:
	var m := MageMeteorStrike.new()
	m.name = "MeteorStrike"
	m.caster = p_caster
	m.fall_time = maxf(0.05, p_fall)
	m._left = m.fall_time
	var parent := WeaponRunner.effects_parent(p_caster)
	if parent == null:
		return m
	parent.add_child(m)
	m.global_position = Vector3(center.x, 0.0, center.z)
	return m


func _ready() -> void:
	add_to_group(&"ability_areas")
	_build()


## Seconds until it lands.
func time_left() -> float:
	return maxf(0.0, _left)


func _physics_process(delta: float) -> void:
	if landed:
		return
	_left -= delta
	if _left <= EPSILON:
		land()


## Lands now: impact damage, stun, burning ground, VFX; then frees itself.
func land() -> void:
	if landed:
		return
	landed = true
	set_physics_process(false)
	if is_inside_tree() and caster != null and is_instance_valid(caster) and caster.procs != null:
		var center := global_position
		for e in MageSpell.enemies_in(get_tree(), center, radius):
			if caster.procs.deal_raw(e, damage, MageSpell.FIRE, true, &"ability") > 0.0:
				hits += 1
			if stun > 0.0 and MageSpell.is_live(e):
				e.apply_stun(stun)
		_spawn_ground(center)
		MageFx.impact(center, radius)
	landed_at.emit(self)
	queue_free()


func _spawn_ground(center: Vector3) -> void:
	if ground_duration <= 0.0 or ground_radius <= 0.0:
		return
	var area := AbilityArea.spawn(caster, center, ground_radius, ground_duration, GROUND_COLOR)
	if not area.is_inside_tree():
		area.free()
		return
	area.school = MageSpell.FIRE
	area.tick_interval = maxf(0.1, ground_tick)
	area.damage_per_tick = ground_damage
	MageFx.ground_fire(area)
	ground = area


func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / fall_time, 0.0, 1.0)
	if _rock != null:
		_rock.position = (FALL_SLANT + Vector3.UP * FALL_HEIGHT).lerp(Vector3.UP * 0.4, t * t)
		_rock.rotation = Vector3(_age * 5.0, _age * 3.0, 0.0)
	if _warn != null:
		_warn.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
		var pulse := 0.8 + 0.2 * sin(_age * 16.0)
		Mats.set_ring(_warn, Color(WARN_COLOR, WARN_COLOR.a * pulse), 0.88, 0.99, 0.12 * t, t)


func _build() -> void:
	_warn = MeshInstance3D.new()
	_warn.name = "Warning"
	_warn.mesh = MeshKit.cached("mage:quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)
	_warn.material_override = Mats.ring()
	_warn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warn.position.y = 0.08
	_warn.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	Mats.set_ring(_warn, WARN_COLOR, 0.88, 0.99, 0.0, 0.0)
	add_child(_warn)
	_rock = Node3D.new()
	_rock.name = "Rock"
	_rock.position = FALL_SLANT + Vector3.UP * FALL_HEIGHT
	add_child(_rock)
	var stone := MeshInstance3D.new()
	stone.mesh = MeshKit.cached("mage:meteor_rock", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.55
		s.height = 1.0
		s.radial_segments = 7
		s.rings = 4
		return s)
	stone.material_override = Mats.toon_emissive(MageFx.ROCK, Color(0.9, 0.28, 0.04), 0.35)
	stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rock.add_child(stone)
	var halo := MeshInstance3D.new()
	halo.mesh = MeshKit.cached("mage:meteor_halo", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.75
		s.height = 1.5
		s.radial_segments = 12
		s.rings = 6
		return s)
	halo.material_override = Mats.unshaded(Color(1.0, 0.55, 0.12, 0.3))
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rock.add_child(halo)
	var trail := MageFx.trail(MageSpell.FIRE_COLOR, 3.5)
	trail.emission_sphere_radius = 0.45
	trail.lifetime = 0.45
	_rock.add_child(trail)
