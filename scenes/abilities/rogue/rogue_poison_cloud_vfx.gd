class_name RoguePoisonCloudVfx
extends Node3D
## Poison Bomb cloud (placeholder art): a sickly green rim on the ground and slow, swelling
## gas puffs drifting up inside it, plus a few bubbles. Child of the cloud's AbilityArea (it
## moves and dies with it); purely visual.

const GAS := Color(0.55, 0.78, 0.16)
## Puffs are darker than the gas rim so they read over the bright grass.
const PUFF := Color(0.36, 0.52, 0.12)
const RIM_ALPHA := 0.7

var radius := 2.5
var duration := 4.0

var _elapsed := 0.0
var _rim: MeshInstance3D
var _gas: CPUParticles3D
var _bubbles: CPUParticles3D


static func create(p_radius: float, p_duration: float) -> RoguePoisonCloudVfx:
	var fx := RoguePoisonCloudVfx.new()
	fx.name = "PoisonCloudVfx"
	fx.radius = p_radius
	fx.duration = p_duration
	return fx


func _ready() -> void:
	_rim = MeshInstance3D.new()
	_rim.name = "Rim"
	_rim.mesh = MeshKit.cached("rogue:ground_quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)
	_rim.material_override = Mats.ring()
	_rim.scale = Vector3.ONE * radius * 2.0
	_rim.position.y = 0.07
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rim)
	Mats.set_ring(_rim, Color(GAS, 0.0), 0.86, 0.97, 0.0)

	_gas = CPUParticles3D.new()
	_gas.name = "Gas"
	_gas.amount = clampi(roundi(radius * 7.0), 10, 40)
	_gas.lifetime = 1.6
	_gas.mesh = MeshKit.cached("rogue:gas_puff", func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = 0.32
		m.height = 0.5
		m.radial_segments = 8
		m.rings = 4
		return m)
	_gas.material_override = Mats.particle(false)
	_gas.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_gas.emission_ring_axis = Vector3.UP
	_gas.emission_ring_radius = radius * 0.85
	_gas.emission_ring_inner_radius = 0.0
	_gas.emission_ring_height = 0.1
	_gas.direction = Vector3.UP
	_gas.spread = 25.0
	_gas.gravity = Vector3(0.0, 0.25, 0.0)
	_gas.initial_velocity_min = 0.15
	_gas.initial_velocity_max = 0.5
	_gas.scale_amount_min = 0.8
	_gas.scale_amount_max = 1.7
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.0))
	_gas.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(PUFF, 0.0))
	ramp.add_point(0.25, Color(PUFF, 0.5))
	ramp.set_color(ramp.get_point_count() - 1, Color(PUFF.darkened(0.3), 0.0))
	_gas.color_ramp = ramp
	_gas.position.y = 0.25
	_gas.local_coords = false
	_gas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_gas)
	_gas.emitting = true

	_bubbles = CPUParticles3D.new()
	_bubbles.name = "Bubbles"
	_bubbles.amount = clampi(roundi(radius * 3.0), 5, 14)
	_bubbles.lifetime = 0.8
	_bubbles.mesh = MeshKit.cached("rogue:gas_bubble", func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = 0.06
		m.height = 0.12
		m.radial_segments = 6
		m.rings = 3
		return m)
	_bubbles.material_override = Mats.particle(false, true)
	_bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_bubbles.emission_ring_axis = Vector3.UP
	_bubbles.emission_ring_radius = radius * 0.8
	_bubbles.emission_ring_inner_radius = 0.0
	_bubbles.emission_ring_height = 0.05
	_bubbles.direction = Vector3.UP
	_bubbles.spread = 10.0
	_bubbles.gravity = Vector3(0.0, 0.0, 0.0)
	_bubbles.initial_velocity_min = 0.6
	_bubbles.initial_velocity_max = 1.2
	var bramp := Gradient.new()
	bramp.set_color(0, Color(0.75, 0.95, 0.25, 0.85))
	bramp.set_color(1, Color(0.45, 0.7, 0.1, 0.0))
	_bubbles.color_ramp = bramp
	_bubbles.position.y = 0.1
	_bubbles.local_coords = false
	_bubbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bubbles)
	_bubbles.emitting = true


func _process(delta: float) -> void:
	_elapsed += delta
	var fade := clampf(minf(_elapsed / 0.2, (duration - _elapsed) / 0.4), 0.0, 1.0)
	var pulse := 0.8 + 0.2 * sin(_elapsed * 4.0)
	Mats.set_ring(_rim, Color(GAS, RIM_ALPHA * fade * pulse), 0.86, 0.97, 0.0)
	if _elapsed >= duration - 0.6:
		if _gas.emitting:
			_gas.emitting = false
		if _bubbles.emitting:
			_bubbles.emitting = false
