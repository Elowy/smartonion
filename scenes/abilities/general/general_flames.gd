class_name GeneralFlames
extends Node3D
## Licking flames over a burning [AbilityArea] (Incendiary Bomb): one CPUParticles3D emitting
## small additive fire blobs from a disc of the area's radius. A child of the area, so it moves
## and dies with it; it stops emitting shortly before the area runs out. Purely visual.

const FLAME := Color(1.0, 0.62, 0.18)
const FLAME_TIP := Color(1.0, 0.25, 0.05)
const LEAD_OUT := 0.4

var _area: AbilityArea
var _particles: CPUParticles3D
var _age := 0.0


static func attach(area: AbilityArea) -> GeneralFlames:
	if area == null:
		return null
	var fx := GeneralFlames.new()
	fx.name = "Flames"
	fx._area = area
	area.add_child(fx)
	return fx


func _ready() -> void:
	var r := _area.radius if _area != null else 2.0
	_particles = CPUParticles3D.new()
	_particles.amount = clampi(roundi(r * r * 6.0), 10, 48)
	_particles.lifetime = 0.6
	_particles.mesh = MeshKit.cached("general:flame", func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = 0.09
		m.height = 0.26
		m.radial_segments = 6
		m.rings = 3
		return m)
	_particles.material_override = Mats.particle(true)
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_particles.emission_ring_axis = Vector3.UP
	_particles.emission_ring_radius = r * 0.9
	_particles.emission_ring_inner_radius = 0.0
	_particles.emission_ring_height = 0.05
	_particles.direction = Vector3.UP
	_particles.spread = 8.0
	_particles.gravity = Vector3(0, 1.2, 0)
	_particles.initial_velocity_min = 0.6
	_particles.initial_velocity_max = 1.4
	_particles.scale_amount_min = 0.8
	_particles.scale_amount_max = 1.6
	var g := Gradient.new()
	g.set_color(0, Color(FLAME.r, FLAME.g, FLAME.b, 0.9))
	g.set_color(1, Color(FLAME_TIP.r, FLAME_TIP.g, FLAME_TIP.b, 0.0))
	_particles.color_ramp = g
	_particles.position.y = 0.1
	add_child(_particles)


func _process(delta: float) -> void:
	_age += delta
	if _particles != null and _area != null and is_instance_valid(_area) \
			and _age >= _area.duration - LEAD_OUT:
		_particles.emitting = false
