class_name WarriorRavagerAxe
extends WarriorFx
## Bladestorm's "Ravager": a double-bladed axe that flies from the hero to the target spot and
## whirls there above a blade storm (WarriorSpinVfx child). The node's own position is the
## storm's centre from the start (gameplay reads it); only the axe model flies in. Lives in
## the arena's effect root, group &"ability_areas" (WaveDirector.stop frees it), frees itself
## after its life.

const FLY_TIME := 0.18
const HOVER := 0.75
const TURNS_PER_SECOND := 3.5
const AXE_COLOR := Color(1.0, 1.0, 1.0, 0.95)

var _axe: Node3D
var _from_offset := Vector3.ZERO


## An axe whirling at [param center] for [param seconds], thrown from [param from].
static func spawn(owner: Player, from: Vector3, center: Vector3, seconds: float) -> WarriorRavagerAxe:
	var parent := WeaponRunner.effects_parent(owner)
	if parent == null:
		return null
	var fx := WarriorRavagerAxe.new()
	fx.name = "RavagerAxe"
	fx.life = maxf(0.1, seconds) + 0.25
	fx.fade_in = 0.05
	fx.fade_out = 0.25
	fx.add_to_group(&"ability_areas")
	parent.add_child(fx)
	fx.global_position = Vector3(center.x, 0.0, center.z)
	fx._from_offset = Vector3(from.x - center.x, 0.0, from.z - center.z)
	return fx


## Two crescent blades on a short haft, lying flat (spins around Y), vertex coloured.
static func axe_mesh() -> Mesh:
	return MeshKit.cached("warrior:ravager_axe", func() -> Mesh:
		var k := MeshKit.new()
		var steel := Color(0.85, 0.88, 0.95)
		var edge := Color(1.0, 1.0, 1.0)
		var haft := Color(0.45, 0.28, 0.16)
		k.add_cylinder(0.05, 0.05, 1.3, MeshKit.xf(Vector3.ZERO, Vector3(90.0, 0.0, 0.0)), haft, 8)
		for side: float in [-1.0, 1.0]:
			k.add_arc(0.18, 0.62, 120.0, MeshKit.xf(Vector3(0.0, 0.0, 0.42 * side), Vector3(0.0, 90.0 * side, 0.0)), steel, 12)
			k.add_arc(0.56, 0.66, 120.0, MeshKit.xf(Vector3(0.0, 0.01, 0.42 * side), Vector3(0.0, 90.0 * side, 0.0)), edge, 12)
		k.add_sphere(0.1, Transform3D.IDENTITY, Color(0.95, 0.75, 0.3), 8, 4)
		return k.build())


func _ready() -> void:
	_axe = Node3D.new()
	_axe.name = "Axe"
	add_child(_axe)
	add_part(axe_mesh(), AXE_COLOR, _axe, true)
	_animate(0.0)


func _animate(delta: float) -> void:
	var fly := clampf(age / FLY_TIME, 0.0, 1.0)
	var arc := 4.0 * fly * (1.0 - fly)
	_axe.position = _from_offset * (1.0 - fly) + Vector3.UP * (HOVER + arc * 1.2)
	_axe.rotation.y -= delta * TAU * TURNS_PER_SECOND
	_axe.rotation.z = 0.25 * sin(age * 3.0)
