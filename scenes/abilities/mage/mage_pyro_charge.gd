class_name MagePyroCharge
extends Node3D
## Look of Pyroblast's wind-up: a fireball swelling in front of the Mage (on the side it
## faces) with embers spiralling into it, and a ring at the feet that fills like a cast bar.
## Child of the hero; the effect frees it on release / cancel ([method finish]). Purely visual.

const ORB_HEIGHT := 1.25
## How far in front of the hero the fireball grows.
const ORB_REACH := 0.85
const RING_COLOR := Color(1.0, 0.55, 0.15, 0.95)

var player: Player
var duration := 1.0
var age := 0.0
var _orb: Node3D
var _ring: MeshInstance3D
var _embers: CPUParticles3D


static func attach(p_player: Player, p_duration: float) -> MagePyroCharge:
	if p_player == null:
		return null
	var c := MagePyroCharge.new()
	c.name = "PyroCharge"
	c.duration = maxf(0.05, p_duration)
	c.player = p_player
	c._build()
	p_player.add_child(c)
	return c


## 0..1 share of the wind-up done.
func progress() -> float:
	return clampf(age / duration, 0.0, 1.0)


func finish() -> void:
	name = "SpentCharge"
	queue_free()


func _process(delta: float) -> void:
	age += delta
	var p := progress()
	if _orb != null:
		var wobble := 1.0 + 0.06 * sin(age * 22.0)
		_orb.scale = Vector3.ONE * lerpf(0.6, 2.0, p * p) * wobble
		_orb.rotation.y = age * 4.0
		if player != null and is_instance_valid(player):
			var f := Vector3(player.facing.x, 0.0, player.facing.z)
			if f.length_squared() > 0.0001:
				_orb.position = f.normalized() * ORB_REACH + Vector3.UP * ORB_HEIGHT
				if _embers != null:
					_embers.position = _orb.position
	if _ring != null:
		Mats.set_ring(_ring, RING_COLOR, 0.8, 0.96, 0.06, p)


func _build() -> void:
	_orb = Node3D.new()
	_orb.name = "Orb"
	_orb.position.y = ORB_HEIGHT
	_orb.scale = Vector3.ONE * 0.35
	add_child(_orb)
	var core := MeshInstance3D.new()
	core.mesh = _sphere("mage:pyro_core", 0.16)
	core.material_override = Mats.glow(Color(1.0, 0.9, 0.55), 3.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orb.add_child(core)
	var shell := MeshInstance3D.new()
	shell.mesh = _sphere("mage:pyro_shell", 0.3)
	shell.material_override = Mats.unshaded(Color(MageSpell.FIRE_COLOR, 0.7))
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orb.add_child(shell)
	_embers = CPUParticles3D.new()
	_embers.name = "Embers"
	_embers.amount = 16
	_embers.lifetime = 0.4
	_embers.local_coords = true
	_embers.mesh = MageFx._ball()
	_embers.material_override = Mats.particle(false)
	_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	_embers.emission_sphere_radius = 1.0
	_embers.gravity = Vector3.ZERO
	# Pulled into the orb.
	_embers.radial_accel_min = -9.0
	_embers.radial_accel_max = -6.0
	_embers.scale_amount_min = 0.5
	_embers.scale_amount_max = 0.9
	_embers.color_ramp = MageFx._gradient(Color(1.0, 0.8, 0.3, 0.0), Color(1.0, 0.45, 0.08, 0.95))
	_embers.position.y = ORB_HEIGHT
	_embers.emitting = true
	add_child(_embers)
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = MeshKit.cached("mage:quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)
	_ring.material_override = Mats.ring()
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = 0.06
	_ring.scale = Vector3(2.0, 1.0, 2.0)
	Mats.set_ring(_ring, RING_COLOR, 0.8, 0.96, 0.06, 0.0)
	add_child(_ring)


static func _sphere(key: String, r: float) -> Mesh:
	return MeshKit.cached(key, func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 10
		s.rings = 5
		return s)
