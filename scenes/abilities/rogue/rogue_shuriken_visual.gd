class_name RogueShurikenVisual
extends RefCounted
## Placeholder art of a thrown shuriken (primitives + Mats): a flat four-pointed steel star with
## a dark hub, lying on the ground plane. Its "Spinner" child is spun by Projectile._process;
## a faint streak behind it (along +Z, the flight runs along -Z) keeps it readable from the
## top-down camera.

const STEEL := Color(0.86, 0.9, 0.96)
const HUB := Color(0.18, 0.16, 0.22)

static var _meshes: Dictionary[String, Mesh] = {}


static func build(color: Color, is_crit: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var spinner := Node3D.new()
	spinner.name = "Spinner"
	root.add_child(spinner)
	var steel := Mats.toon(STEEL)
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.y = TAU * float(i) / 4.0
		spinner.add_child(arm)
		# A flat blade: a 4-sided cone lying along -Z, squashed vertically.
		var point := _add(arm, _point_mesh(), steel, Vector3(0, 0, -0.12))
		point.rotation_degrees = Vector3(-90, 0, 0)
		point.scale = Vector3(1.0, 1.0, 0.3)
	_add(spinner, _hub_mesh(), Mats.toon(HUB), Vector3.ZERO)
	var trail := _add(root, _trail_mesh(), Mats.unshaded(Color(color, 0.25)), Vector3(0, 0, 0.32))
	trail.name = "Trail"
	root.scale = Vector3.ONE * (1.6 if is_crit else 1.3)
	return root


static func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _point_mesh() -> Mesh:
	if not _meshes.has("point"):
		var m := CylinderMesh.new()
		m.top_radius = 0.0
		m.bottom_radius = 0.07
		m.height = 0.2
		m.radial_segments = 4
		m.rings = 1
		_meshes["point"] = m
	return _meshes["point"]


static func _hub_mesh() -> Mesh:
	if not _meshes.has("hub"):
		var m := CylinderMesh.new()
		m.top_radius = 0.055
		m.bottom_radius = 0.055
		m.height = 0.035
		m.radial_segments = 10
		m.rings = 1
		_meshes["hub"] = m
	return _meshes["hub"]


static func _trail_mesh() -> Mesh:
	if not _meshes.has("trail"):
		var m := BoxMesh.new()
		m.size = Vector3(0.06, 0.015, 0.45)
		_meshes["trail"] = m
	return _meshes["trail"]
