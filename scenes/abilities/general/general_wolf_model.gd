class_name GeneralWolfModel
extends Node3D
## Procedural look of the Spirit Wolf: a lean, translucent pale-blue wolf (the downed-ghost
## shader, Mats.ghost – fresnel glow, see-through) with glowing eyes and a wispy tail. Faces -Z.
## Body + head are one cached MeshKit mesh; the four legs and the tail are separate (cached)
## meshes swung in _process (trot cycle, wagging); bites lunge the body forward. Spirit motes
## drift up from it. Only nodes move – materials are shared (cached per colour).

const SPIRIT := Color(0.42, 0.78, 1.0, 0.74)
const RING := Color(0.45, 0.85, 1.0, 0.55)
const EYE := Color(0.75, 1.0, 1.0)
const TURN_SPEED := 12.0
const TROT_SPEED := 13.0
const BITE_TIME := 0.25
const HIP_Y := 0.42
## Hip positions (pivot space): front left, front right, hind left, hind right.
const HIPS: Array[Vector3] = [Vector3(-0.1, HIP_Y, -0.24), Vector3(0.1, HIP_Y, -0.24),
		Vector3(-0.1, HIP_Y, 0.22), Vector3(0.1, HIP_Y, 0.22)]

var tint := SPIRIT
var model_scale := 1.35

var _pivot: Node3D
var _body: MeshInstance3D
var _legs: Array[Node3D] = []
var _tail: Node3D
var _ring: MeshInstance3D
var _time := 0.0
var _yaw := 0.0
var _target_yaw := 0.0
var _moving := 0.0
var _bite := 1.0


func _init() -> void:
	name = "WolfModel"


func _ready() -> void:
	if _pivot == null:
		_build()


func set_facing(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length_squared() < 0.0001:
		return
	_target_yaw = atan2(-direction.x, -direction.z)


## 0..1 trot strength (legs swing, body bobs).
func set_moving(ratio: float) -> void:
	_moving = clampf(ratio, 0.0, 1.0)


func play_bite() -> void:
	_bite = 0.0


func _build() -> void:
	var ghost := Mats.ghost(tint)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_pivot.scale = Vector3.ONE * model_scale
	add_child(_pivot)
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.mesh = MeshKit.cached("general:wolf_body", func() -> Mesh: return _body_mesh())
	_body.material_override = ghost
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(_body)
	var leg_mesh := MeshKit.cached("general:wolf_leg", func() -> Mesh: return _leg_mesh())
	for hip in HIPS:
		var leg := Node3D.new()
		leg.position = hip
		_pivot.add_child(leg)
		var mi := MeshInstance3D.new()
		mi.mesh = leg_mesh
		mi.material_override = ghost
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		leg.add_child(mi)
		_legs.append(leg)
	_tail = Node3D.new()
	_tail.name = "Tail"
	_tail.position = Vector3(0.0, 0.55, 0.34)
	_pivot.add_child(_tail)
	var tail := MeshInstance3D.new()
	tail.mesh = MeshKit.cached("general:wolf_tail", func() -> Mesh: return _tail_mesh())
	tail.material_override = ghost
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tail.add_child(tail)
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = MeshKit.cached("general:wolf_eye", func() -> Mesh:
			var m := SphereMesh.new()
			m.radius = 0.028
			m.height = 0.05
			m.radial_segments = 8
			m.rings = 4
			return m)
		eye.material_override = Mats.glow(EYE, 3.0)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.position = Vector3(0.06 * side, 0.74, -0.47)
		_pivot.add_child(eye)
	var motes := CPUParticles3D.new()
	motes.name = "Motes"
	motes.amount = 6
	motes.lifetime = 0.9
	motes.local_coords = false
	motes.mesh = MeshKit.cached("general:ball", func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = 0.06
		m.height = 0.12
		m.radial_segments = 8
		m.rings = 4
		return m)
	motes.material_override = Mats.particle(true)
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(0.12, 0.12, 0.3)
	motes.position.y = 0.55
	motes.direction = Vector3.UP
	motes.spread = 25.0
	motes.gravity = Vector3(0, 0.8, 0)
	motes.initial_velocity_min = 0.2
	motes.initial_velocity_max = 0.5
	motes.scale_amount_min = 0.4
	motes.scale_amount_max = 0.8
	var g := Gradient.new()
	g.set_color(0, Color(tint.r, tint.g, tint.b, 0.8))
	g.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	motes.color_ramp = g
	_pivot.add_child(motes)
	# A soft spirit glow on the ground keeps it readable on any floor.
	_ring = MeshInstance3D.new()
	_ring.name = "Glow"
	_ring.mesh = MeshKit.cached("general:aura_quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(2.0, 2.0)
		return q)
	_ring.material_override = Mats.ring()
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = 0.04
	_ring.scale = Vector3(0.55, 1.0, 0.75) * model_scale
	add_child(_ring)
	Mats.set_ring(_ring, RING, 0.55, 0.95, 0.35)
	_yaw = _target_yaw
	_pivot.rotation.y = _yaw
	_ring.rotation.y = _yaw


func _process(delta: float) -> void:
	if _pivot == null:
		return
	_time += delta
	_yaw = lerp_angle(_yaw, _target_yaw, 1.0 - exp(-TURN_SPEED * delta))
	_bite = minf(1.0, _bite + delta / BITE_TIME)
	var lunge := sin(_bite * PI) if _bite < 1.0 else 0.0
	var trot := _time * TROT_SPEED
	_pivot.rotation = Vector3(-0.25 * lunge, _yaw, 0.0)
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	_pivot.position = forward * 0.22 * lunge * model_scale \
			+ Vector3.UP * (absf(sin(trot)) * 0.05 * _moving + 0.02 * sin(_time * 2.0)) * model_scale
	for i in _legs.size():
		# Diagonal pairs move together (trot): FL + HR, FR + HL.
		var phase := 0.0 if i == 0 or i == 3 else PI
		_legs[i].rotation.x = sin(trot + phase) * 0.6 * _moving
	if _ring != null:
		_ring.rotation.y = _yaw
	if _tail != null:
		_tail.rotation = Vector3(0.35 + 0.15 * sin(_time * 3.0), 0.0, sin(_time * (6.0 + 6.0 * _moving)) * 0.35)


# --- Meshes (shared, cached) ------------------------------------------------------------------

static func _xf(pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	return MeshKit.xf(pos, rot, scl)


static func _body_mesh() -> Mesh:
	var k := MeshKit.new()
	var white := Color.WHITE
	# Deep chest, lean belly, haunches.
	k.add_sphere(0.17, _xf(Vector3(0, 0.52, -0.17), Vector3.ZERO, Vector3(1.0, 1.1, 1.2)), white, 12, 6)
	k.add_capsule(0.12, 0.5, _xf(Vector3(0, 0.53, 0.02), Vector3(90, 0, 0)), white, 10, 4)
	k.add_sphere(0.14, _xf(Vector3(0, 0.53, 0.2), Vector3.ZERO, Vector3(1.0, 1.0, 1.1)), white, 12, 6)
	# Neck and head.
	k.add_segment(Vector3(0, 0.58, -0.25), Vector3(0, 0.72, -0.38), 0.11, 0.09, white, 10)
	var head := Vector3(0, 0.74, -0.42)
	k.add_sphere(0.11, _xf(head, Vector3.ZERO, Vector3(1.0, 0.95, 1.1)), white, 12, 6)
	# Long snout and nose.
	k.add_segment(head + Vector3(0, -0.02, -0.06), head + Vector3(0, -0.05, -0.24), 0.065, 0.035, white, 8)
	k.add_sphere(0.03, _xf(head + Vector3(0, -0.04, -0.25)), white, 6, 3)
	# Pointed ears.
	for side: float in [-1.0, 1.0]:
		k.add_segment(head + Vector3(0.055 * side, 0.07, 0.02), head + Vector3(0.08 * side, 0.2, 0.04), 0.04, 0.0, white, 6)
	# Ruff of fur round the neck.
	k.add_torus(0.1, 0.17, _xf(Vector3(0, 0.6, -0.27), Vector3(70, 0, 0)), white, 12, 6)
	return k.build()


## One leg hanging down from its hip (origin), paw at the bottom.
static func _leg_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_segment(Vector3(0, 0.02, 0), Vector3(0, -0.22, 0.02), 0.05, 0.035, Color.WHITE, 8)
	k.add_segment(Vector3(0, -0.22, 0.02), Vector3(0, -0.4, -0.01), 0.035, 0.03, Color.WHITE, 8)
	k.add_sphere(0.04, _xf(Vector3(0, -0.41, -0.03), Vector3.ZERO, Vector3(1.0, 0.6, 1.4)), Color.WHITE, 8, 4)
	return k.build()


## A bushy tail curving back from its root (origin).
static func _tail_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.02, 0.15), Vector3(0, -0.08, 0.3),
			Vector3(0, -0.06, 0.42)]), 0.05, 0.02, Color.WHITE, 8)
	k.add_sphere(0.07, _xf(Vector3(0, -0.06, 0.28), Vector3.ZERO, Vector3(0.9, 0.9, 1.6)), Color.WHITE, 8, 4)
	return k.build()
