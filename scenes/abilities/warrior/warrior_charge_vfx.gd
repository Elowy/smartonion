class_name WarriorChargeVfx
extends Node3D
## Charge effect: a red speed streak along the dash path that fades away and a shock ring
## where the hero lands. Frees itself. Purely visual.

const LIFE := 0.4
const WIDTH := 0.9
const STREAK_ALPHA := 0.45
const GROUND_Y := 0.07
const RING_COLOR := Color(1.0, 0.45, 0.25)
const STREAK_COLOR := Color(1.0, 0.4, 0.25)

var _age := 0.0
var _material: StandardMaterial3D


## [param from] / [param to] are world positions; [param ring_radius] the landing ring.
static func spawn(from: Vector3, to: Vector3, ring_radius: float) -> void:
	var parent := Vfx.effect_parent()
	if parent == null:
		return
	var fx := WarriorChargeVfx.new()
	fx.name = "ChargeStreak"
	parent.add_child(fx)
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length := flat.length()
	fx.global_position = Vector3((from.x + to.x) * 0.5, GROUND_Y, (from.z + to.z) * 0.5)
	if length > 0.05:
		fx.rotation.y = atan2(-flat.x, -flat.z)
	fx._build(length)
	Vfx.explosion(Vector3(to.x, 0.0, to.z), maxf(0.5, ring_radius * 0.8), RING_COLOR)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	if _material != null:
		_material.albedo_color.a = STREAK_ALPHA * (1.0 - _age / LIFE)


func _build(length: float) -> void:
	if length <= 0.05:
		return
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = Color(STREAK_COLOR.r, STREAK_COLOR.g, STREAK_COLOR.b, STREAK_ALPHA)
	var quad := PlaneMesh.new()
	quad.size = Vector2(WIDTH, length)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
