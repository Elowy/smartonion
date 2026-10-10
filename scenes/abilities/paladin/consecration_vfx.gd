class_name ConsecrationVfx
extends Node3D
## Golden consecrated ground (placeholder art): a glowing rim, an inner holy ring and rising
## motes of light. Child of the Consecration AbilityArea (it moves and dies with it).

const GOLD := Color(1.0, 0.85, 0.35)
const RIM_ALPHA := 0.75
const INNER_ALPHA := 0.45

var radius := 3.0
var duration := 4.0

var _elapsed := 0.0
var _rim: MeshInstance3D
var _inner: MeshInstance3D
var _motes: CPUParticles3D


static func create(p_radius: float, p_duration: float) -> ConsecrationVfx:
	var fx := ConsecrationVfx.new()
	fx.name = "ConsecrationVfx"
	fx.radius = p_radius
	fx.duration = p_duration
	return fx


func _ready() -> void:
	var d := radius * 2.0
	_rim = _ring_quad("Rim", d, 0.07)
	Mats.set_ring(_rim, Color(GOLD.r, GOLD.g, GOLD.b, 0.0), 0.88, 0.98, 0.0)
	_inner = _ring_quad("Inner", d * 0.55, 0.075)
	Mats.set_ring(_inner, Color(GOLD.r, GOLD.g, GOLD.b, 0.0), 0.8, 0.9, 0.0)
	_motes = CPUParticles3D.new()
	_motes.name = "Motes"
	_motes.amount = clampi(roundi(radius * 6.0), 8, 32)
	_motes.lifetime = 1.1
	_motes.mesh = _mote_mesh()
	_motes.material_override = Mats.particle(true, true)
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_motes.emission_ring_axis = Vector3.UP
	_motes.emission_ring_radius = radius * 0.9
	_motes.emission_ring_inner_radius = 0.0
	_motes.emission_ring_height = 0.05
	_motes.direction = Vector3.UP
	_motes.spread = 8.0
	_motes.gravity = Vector3(0.0, 0.4, 0.0)
	_motes.initial_velocity_min = 0.6
	_motes.initial_velocity_max = 1.4
	_motes.scale_amount_min = 0.6
	_motes.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.7, 0.9))
	ramp.set_color(1, Color(1.0, 0.75, 0.25, 0.0))
	_motes.color_ramp = ramp
	_motes.position.y = 0.1
	_motes.local_coords = false
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_motes)
	_motes.emitting = true


func _process(delta: float) -> void:
	_elapsed += delta
	var fade := clampf(minf(_elapsed / 0.2, (duration - _elapsed) / 0.35), 0.0, 1.0)
	var pulse := 0.8 + 0.2 * sin(_elapsed * 5.0)
	Mats.set_ring(_rim, Color(GOLD.r, GOLD.g, GOLD.b, RIM_ALPHA * fade * pulse), 0.88, 0.98, 0.0)
	Mats.set_ring(_inner, Color(GOLD.r, GOLD.g, GOLD.b, INNER_ALPHA * fade), 0.8, 0.9, 0.0)
	_inner.rotation.y += delta * 0.6
	if _elapsed >= duration - 0.4 and _motes.emitting:
		_motes.emitting = false


func _ring_quad(node_name: String, size: float, height: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = node_name
	m.mesh = MeshKit.cached("paladin:ground_quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)
	m.material_override = Mats.ring()
	m.scale = Vector3(size, 1.0, size)
	m.position.y = height
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


static func _mote_mesh() -> Mesh:
	return MeshKit.cached("paladin:holy_mote", func() -> Mesh:
		var q := QuadMesh.new()
		q.size = Vector2(0.12, 0.12)
		return q)
