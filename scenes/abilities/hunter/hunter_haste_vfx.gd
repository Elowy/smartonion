class_name HunterHasteVfx
extends Node3D
## The look of Quick Draw on a hero: a pulsing golden ring at the feet and bright motes whirling up
## round the body. A child of the [GeneralBuff] (so of the hero), freed with it. Purely visual.

const COLOR := Color(1.0, 0.8, 0.3)
const RING_RADIUS := 0.85

var _age := 0.0
var _ring: MeshInstance3D


func _ready() -> void:
	name = "QuickDrawLook"
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = MeshKit.cached("hunter:look_quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(2.0, 2.0)
		return q)
	_ring.material_override = Mats.ring()
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.scale = Vector3(RING_RADIUS, 1.0, RING_RADIUS)
	_ring.position.y = 0.05
	Mats.set_ring(_ring, Color(COLOR, 0.7), 0.72, 0.95, 0.18)
	add_child(_ring)
	var motes := CPUParticles3D.new()
	motes.name = "Motes"
	motes.amount = 14
	motes.lifetime = 0.7
	motes.mesh = MeshKit.cached("hunter:look_mote", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.05
		s.height = 0.1
		s.radial_segments = 6
		s.rings = 3
		return s)
	motes.material_override = Mats.particle(true)
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	motes.position.y = 0.15
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	motes.emission_ring_axis = Vector3.UP
	motes.emission_ring_radius = 0.6
	motes.emission_ring_inner_radius = 0.35
	motes.emission_ring_height = 0.1
	motes.direction = Vector3.UP
	motes.spread = 12.0
	motes.gravity = Vector3(0, 1.2, 0)
	motes.initial_velocity_min = 1.0
	motes.initial_velocity_max = 1.8
	motes.scale_amount_min = 0.6
	motes.scale_amount_max = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(COLOR, 1.0))
	g.set_color(1, Color(COLOR, 0.0))
	motes.color_ramp = g
	motes.emitting = true
	add_child(motes)


func _process(delta: float) -> void:
	_age += delta
	if _ring != null:
		Mats.set_ring(_ring, Color(COLOR, 0.55 + 0.25 * sin(_age * 10.0)), 0.72, 0.95, 0.18)
