class_name RogueKnifeVisual
extends RefCounted
## Placeholder art of a thrown knife (primitives + Mats): a steel blade with a leather grip,
## pointing along -Z like every projectile visual. [method attach] swaps it into a freshly
## created Projectile in place of the style's default model.

const STEEL := Color(0.82, 0.86, 0.92)
const GRIP := Color(0.3, 0.2, 0.12)

static var _meshes: Dictionary[String, Mesh] = {}


static func build(color: Color, is_crit: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var steel := Mats.toon(STEEL)
	_add(root, _box(Vector3(0.07, 0.02, 0.2)), steel, Vector3(0, 0, -0.04))
	var tip := _add(root, _cone(0.035, 0.12), steel, Vector3(0, 0, -0.2))
	tip.rotation_degrees = Vector3(-90, 0, 0)
	tip.scale = Vector3(1.0, 1.0, 0.35)
	_add(root, _box(Vector3(0.15, 0.03, 0.03)), Mats.toon(color.darkened(0.2)), Vector3(0, 0, 0.07))
	_add(root, _box(Vector3(0.04, 0.04, 0.13)), Mats.toon(GRIP), Vector3(0, 0, 0.16))
	# Faint streak so the knives read from the top-down camera.
	_add(root, _box(Vector3(0.04, 0.015, 0.6)), Mats.unshaded(Color(color, 0.22)), Vector3(0, 0, 0.45))
	root.scale = Vector3.ONE * (1.7 if is_crit else 1.45)
	return root


## Replaces the default visual of [param proj] (created, not yet in the tree) by a knife.
static func attach(proj: Projectile, color: Color, is_crit: bool = false) -> void:
	var old := proj.get_node_or_null("Visual")
	if old != null:
		proj.remove_child(old)
		old.free()
	var visual := build(color, is_crit)
	visual.basis = Basis.looking_at(proj.direction, Vector3.UP) * Basis.from_scale(visual.scale)
	proj.add_child(visual)


static func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> Mesh:
	var key := "b%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func _cone(radius: float, height: float) -> Mesh:
	var key := "c%.3f_%.3f" % [radius, height]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = 0.0
		m.bottom_radius = radius
		m.height = height
		m.radial_segments = 4
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]
