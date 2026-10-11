class_name WarriorExecuteVfx
extends WarriorFx
## Execute: a giant spectral greatsword drops point-first onto the target, stabs into the
## ground with a blood-red flash ring and fades. An executed (killed) target gets a bigger,
## darker ring. Parented to the arena's effect root; frees itself.

const LIFE := 0.55
const DROP_TIME := 0.12
const DROP_HEIGHT := 3.2
const BLADE_COLOR := Color(1.0, 0.92, 0.88, 0.85)
const RING_COLOR := Color(0.85, 0.12, 0.08, 0.7)
const EXECUTE_RING_COLOR := Color(0.55, 0.02, 0.02, 0.85)

var executed := false
var ring_radius := 1.2

var _sword: Node3D
var _ring: MeshInstance3D


static func spawn(target_pos: Vector3, p_executed: bool) -> WarriorExecuteVfx:
	var parent := Vfx.effect_parent()
	if parent == null:
		return null
	var fx := WarriorExecuteVfx.new()
	fx.name = "ExecuteBlade"
	fx.executed = p_executed
	fx.ring_radius = 1.6 if p_executed else 1.1
	fx.life = LIFE
	fx.fade_in = 0.02
	fx.fade_out = 0.25
	parent.add_child(fx)
	fx.global_position = Vector3(target_pos.x, 0.0, target_pos.z)
	return fx


## Blade (steel, pointing down), cross-guard and grip (gold / leather): one vertex-coloured mesh.
static func sword_mesh() -> Mesh:
	return MeshKit.cached("warrior:execute_sword", func() -> Mesh:
		var k := MeshKit.new()
		var steel := Color(0.86, 0.9, 1.0)
		k.add_box(Vector3(0.26, 1.7, 0.06), MeshKit.xf(Vector3(0.0, 1.05, 0.0)), steel)
		k.add_cylinder(0.0, 0.13, 0.32, MeshKit.xf(Vector3(0.0, 0.04, 0.0), Vector3(180.0, 0.0, 0.0)), steel, 4)
		k.add_box(Vector3(0.75, 0.1, 0.12), MeshKit.xf(Vector3(0.0, 1.95, 0.0)), Color(0.95, 0.75, 0.3))
		k.add_box(Vector3(0.09, 0.5, 0.09), MeshKit.xf(Vector3(0.0, 2.25, 0.0)), Color(0.4, 0.25, 0.15))
		k.add_sphere(0.09, MeshKit.xf(Vector3(0.0, 2.52, 0.0)), Color(0.95, 0.75, 0.3), 8, 4)
		return k.build())


func _ready() -> void:
	_ring = add_part(ring_mesh(0.62), EXECUTE_RING_COLOR if executed else RING_COLOR)
	_ring.position.y = 0.05
	_sword = Node3D.new()
	_sword.name = "Sword"
	add_child(_sword)
	var scale_f := 1.25 if executed else 1.0
	_sword.scale = Vector3.ONE * scale_f
	add_part(sword_mesh(), BLADE_COLOR, _sword, true)
	# Tilted a little towards the camera (screen-up is -Z) so the blade reads from above.
	_sword.rotation.x = deg_to_rad(-18.0)
	_animate(0.0)


func _animate(_delta: float) -> void:
	var drop := clampf(age / DROP_TIME, 0.0, 1.0)
	_sword.position.y = lerpf(DROP_HEIGHT, -0.25, drop * drop)
	var t := clampf((age - DROP_TIME) / (LIFE - DROP_TIME), 0.0, 1.0)
	var r := ring_radius * (0.35 + 0.65 * (1.0 - pow(1.0 - t, 2.0))) if age >= DROP_TIME else 0.01
	_ring.scale = Vector3(r, 1.0, r)
