class_name HunterAimCharge
extends Node3D
## Look of Long Shot's aiming time: an amber ring at the Hunter's feet that fills like a cast bar
## and a glowing arrow head tightening in front of the bow (on the side it faces). A child of the
## hero; the effect frees it on release / cancel ([method finish]). Purely visual.

const RING_COLOR := Color(1.0, 0.62, 0.2, 0.95)
const NOCK_HEIGHT := 0.95
const NOCK_REACH := 0.75

var player: Player
var duration := 0.7
var age := 0.0
var _nock: MeshInstance3D
var _ring: MeshInstance3D


static func attach(p_player: Player, p_duration: float) -> HunterAimCharge:
	if p_player == null:
		return null
	var c := HunterAimCharge.new()
	c.name = "AimCharge"
	c.duration = maxf(0.05, p_duration)
	c.player = p_player
	c._build()
	p_player.add_child(c)
	return c


## 0..1 share of the aiming time done.
func progress() -> float:
	return clampf(age / duration, 0.0, 1.0)


func finish() -> void:
	name = "SpentAim"
	queue_free()


func _process(delta: float) -> void:
	age += delta
	var p := progress()
	if _nock != null:
		_nock.scale = Vector3.ONE * lerpf(2.2, 0.8, p) * (1.0 + 0.1 * sin(age * 30.0))
		if player != null and is_instance_valid(player):
			var f := WeaponRunner.flat(player.facing)
			if f.length_squared() > 0.0001:
				_nock.position = f.normalized() * NOCK_REACH + Vector3.UP * NOCK_HEIGHT
	if _ring != null:
		Mats.set_ring(_ring, RING_COLOR, 0.8, 0.96, 0.06, p)


func _build() -> void:
	_nock = MeshInstance3D.new()
	_nock.name = "Nock"
	_nock.mesh = MeshKit.cached("hunter:aim_nock", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.1
		s.height = 0.2
		s.radial_segments = 10
		s.rings = 5
		return s)
	_nock.material_override = Mats.glow(Color(1.0, 0.85, 0.5), 3.0)
	_nock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_nock.position = Vector3(0, NOCK_HEIGHT, -NOCK_REACH)
	add_child(_nock)
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = MeshKit.cached("hunter:quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)
	_ring.material_override = Mats.ring()
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = 0.06
	_ring.scale = Vector3(2.0, 1.0, 2.0)
	Mats.set_ring(_ring, RING_COLOR, 0.8, 0.96, 0.06, 0.0)
	add_child(_ring)
