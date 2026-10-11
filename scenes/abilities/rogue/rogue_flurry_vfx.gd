class_name RogueFlurryVfx
extends Node3D
## Blade Flurry look (placeholder art): three steel blades circling the Rogue at waist height
## with a faint ring on the ground. Child of the Player while the flurry lasts (the effect frees
## it); purely visual.

const BLADES := 3
const ORBIT_RADIUS := 0.95
const HEIGHT := 0.55
const SPIN_SPEED := 9.0
const RING_COLOR := Color(0.85, 0.9, 1.0)

var _spin: Node3D
var _ring: MeshInstance3D
var _age := 0.0


static func attach(player: Node3D) -> RogueFlurryVfx:
	var fx := RogueFlurryVfx.new()
	fx.name = "BladeFlurryVfx"
	if player != null:
		player.add_child(fx)
	return fx


func _ready() -> void:
	_spin = Node3D.new()
	_spin.name = "Spin"
	_spin.position.y = HEIGHT
	add_child(_spin)
	for i in BLADES:
		var arm := Node3D.new()
		arm.rotation.y = TAU * float(i) / float(BLADES)
		_spin.add_child(arm)
		var blade := RogueKnifeVisual.build(RING_COLOR)
		# Tangential, tip first in the spin direction.
		blade.position = Vector3(ORBIT_RADIUS, 0.0, 0.0)
		blade.rotation.y = PI
		blade.scale = Vector3.ONE * 1.2
		arm.add_child(blade)
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	var quad := PlaneMesh.new()
	quad.size = Vector2(1, 1)
	_ring.mesh = quad
	_ring.material_override = Mats.ring()
	_ring.scale = Vector3.ONE * (ORBIT_RADIUS * 2.0 + 0.5)
	_ring.position.y = 0.05
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	Mats.set_ring(_ring, Color(RING_COLOR, 0.0), 0.8, 0.95, 0.0)


func _process(delta: float) -> void:
	_age += delta
	if _spin != null:
		_spin.rotate_y(-SPIN_SPEED * delta)
	if _ring != null:
		var fade := clampf(_age / 0.2, 0.0, 1.0)
		Mats.set_ring(_ring, Color(RING_COLOR, 0.35 * fade * (0.8 + 0.2 * sin(_age * 10.0))), 0.8, 0.95, 0.0)
