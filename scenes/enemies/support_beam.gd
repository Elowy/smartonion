class_name SupportBeam
extends Node3D
## The channel beam of the Cultist Acolyte (M6, GDD 8): a thin pulsing beam from the Acolyte's
## staff to the enemy it heals (violet) or shields (blue-violet), with a glowing orb where it
## lands. A child of the Acolyte ([method Enemy._start_channel]), freed with it or when the
## channel ends / is interrupted; it lives in world coordinates ([code]top_level[/code]), so
## the Acolyte's own movement does not drag it and [method set_ends] is called every tick.
## Visual only: no RNG, no gameplay state.

const HEAL_COLOR := Color(0.8, 0.36, 1.0)
const SHIELD_COLOR := Color(0.42, 0.62, 1.0)
const OUTER_RADIUS := 0.1
const INNER_RADIUS := 0.035
const ORB_RADIUS := 0.2

## The ends of the beam as last set (world).
var from_point := Vector3.ZERO
var to_point := Vector3.ZERO
var color := HEAL_COLOR

var _outer: MeshInstance3D
var _inner: MeshInstance3D
var _orb: MeshInstance3D
var _outer_material: StandardMaterial3D
var _time := 0.0


## A beam of [param p_color] (HEAL_COLOR / SHIELD_COLOR), not in the tree yet.
static func create(p_color: Color) -> SupportBeam:
	var b := SupportBeam.new()
	b.name = "SupportBeam"
	b.color = p_color
	b.top_level = true
	b._build()
	return b


## Points the beam from [param from] to [param to] (world positions).
func set_ends(from: Vector3, to: Vector3) -> void:
	from_point = from
	to_point = to
	var span := to - from
	var length := span.length()
	if length < 0.01:
		visible = false
		return
	visible = true
	var basis := MeshKit.basis_from_y(span / length)
	var stretched := Basis(basis.x, basis.y * length, basis.z)
	transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	_outer.transform = Transform3D(stretched, (from + to) * 0.5)
	_inner.transform = _outer.transform
	_orb.position = to


func _process(delta: float) -> void:
	_time += delta
	var pulse := 0.75 + 0.25 * sin(_time * 24.0)
	if _outer_material != null:
		_outer_material.albedo_color.a = 0.4 * pulse
	if _orb != null:
		_orb.scale = Vector3.ONE * (0.85 + 0.3 * sin(_time * 17.0))


func _build() -> void:
	var tube := CylinderMesh.new()
	tube.top_radius = 1.0
	tube.bottom_radius = 1.0
	tube.height = 1.0
	tube.radial_segments = 6
	tube.rings = 0
	_outer = MeshInstance3D.new()
	_outer.name = "Outer"
	var outer_mesh := tube.duplicate() as CylinderMesh
	outer_mesh.top_radius = OUTER_RADIUS
	outer_mesh.bottom_radius = OUTER_RADIUS
	_outer.mesh = outer_mesh
	_outer_material = StandardMaterial3D.new()
	_outer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outer_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_outer_material.albedo_color = Color(color.r, color.g, color.b, 0.4)
	_outer_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_outer.material_override = _outer_material
	_outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_outer)
	_inner = MeshInstance3D.new()
	_inner.name = "Inner"
	var inner_mesh := tube.duplicate() as CylinderMesh
	inner_mesh.top_radius = INNER_RADIUS
	inner_mesh.bottom_radius = INNER_RADIUS
	_inner.mesh = inner_mesh
	_inner.material_override = Mats.glow(color.lerp(Color.WHITE, 0.55), 2.2)
	_inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_inner)
	_orb = MeshInstance3D.new()
	_orb.name = "Orb"
	var sphere := SphereMesh.new()
	sphere.radius = ORB_RADIUS
	sphere.height = ORB_RADIUS * 2.0
	sphere.radial_segments = 10
	sphere.rings = 5
	_orb.mesh = sphere
	_orb.material_override = Mats.glow(color, 1.8)
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_orb)
