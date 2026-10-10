class_name ProjectileVisual
extends RefCounted
## Procedural looks for Projectile styles (placeholder art built from primitives).
## The returned node faces -Z (the flight direction); a descendant named "Spinner" (axe) is
## rotated around Y by the Projectile every frame.
##
## Enemy projectiles ([param enemy] = true) are a different hue family from the heroes'
## (class-coloured bolts: arcane blue, fel green ...): bigger, with a red-orange emissive
## halo and a short hot trail, so a thrown axe reads as a threat at a glance.

## Enemy projectiles are drawn this much bigger.
const ENEMY_SCALE := 1.6
const ENEMY_HALO := Color(1.0, 0.3, 0.08)
const ENEMY_CORE := Color(1.0, 0.62, 0.2)

static var _meshes: Dictionary[String, Mesh] = {}


## [param style]: &"bolt", &"fireball", &"arrow", &"bullet", &"axe" (anything else = bolt).
static func build(style: StringName, color: Color, is_crit: bool = false, enemy: bool = false) -> Node3D:
	var root := Node3D.new()
	var s := 1.25 if is_crit else 1.0
	var body := root
	if enemy:
		body = Node3D.new()
		body.name = "Body"
		body.scale = Vector3.ONE * ENEMY_SCALE
		root.add_child(body)
	match style:
		&"fireball":
			_build_fireball(body, color, s)
		&"arrow":
			_build_arrow(body, color, s)
		&"bullet":
			_build_bullet(body, color, s)
		&"axe":
			_build_axe(body, color, enemy)
		_:
			_build_bolt(body, color, s)
	if enemy:
		_build_threat_glow(root)
	return root


## Red-orange halo disc under the projectile + a short tapered trail behind it.
static func _build_threat_glow(root: Node3D) -> void:
	var halo := _add(root, _cylinder(0.62, 0.62, 0.01, 24), Mats.unshaded(Color(ENEMY_HALO, 0.42)), Vector3(0, -0.05, 0))
	halo.name = "Halo"
	var rim := _add(root, _cylinder(0.36, 0.36, 0.012, 20), Mats.glow(Color(ENEMY_CORE, 0.55), 1.8), Vector3(0, -0.04, 0))
	rim.name = "HaloCore"
	var trail := _add(root, _cylinder(0.04, 0.3, 1.1, 10), Mats.unshaded(Color(ENEMY_HALO, 0.36)), Vector3(0, 0, 0.75))
	trail.name = "Trail"
	# Narrow end far behind (+Z), wide end at the projectile.
	trail.rotation_degrees = Vector3(90, 0, 0)


static func _build_bolt(root: Node3D, color: Color, s: float) -> void:
	_add(root, _sphere(0.11 * s), Mats.glow(color.lightened(0.55), 3.0), Vector3.ZERO)
	_add(root, _sphere(0.24 * s), Mats.unshaded(Color(color, 0.55)), Vector3.ZERO)
	_add(root, _sphere(0.13 * s), Mats.unshaded(Color(color, 0.3)), Vector3(0, 0, 0.3 * s), Vector3(1, 1, 2.6))


static func _build_fireball(root: Node3D, color: Color, s: float) -> void:
	var core := color.lerp(Color(1.0, 0.97, 0.75), 0.6)
	_add(root, _sphere(0.13 * s), Mats.glow(core, 3.0), Vector3.ZERO)
	_add(root, _sphere(0.25 * s), Mats.unshaded(Color(color, 0.7)), Vector3.ZERO)
	_add(root, _sphere(0.17 * s), Mats.unshaded(Color(color.darkened(0.15), 0.3)), Vector3(0, 0, 0.36 * s), Vector3(1, 1, 2.5))


static func _build_arrow(root: Node3D, color: Color, s: float) -> void:
	var shaft := _add(root, _cylinder(0.025, 0.025, 0.7), Mats.toon(Color(0.55, 0.38, 0.22)), Vector3(0, 0, 0.05))
	shaft.rotation_degrees = Vector3(90, 0, 0)
	var head := _add(root, _cylinder(0.0, 0.065, 0.16), Mats.toon(Color(0.78, 0.8, 0.85)), Vector3(0, 0, -0.36))
	head.rotation_degrees = Vector3(-90, 0, 0)
	var fletch_mat := Mats.unshaded(color)
	_add(root, _box(Vector3(0.16, 0.01, 0.14)), fletch_mat, Vector3(0, 0, 0.36))
	_add(root, _box(Vector3(0.01, 0.16, 0.14)), fletch_mat, Vector3(0, 0, 0.36))
	# Faint streak so arrows read from the top-down camera.
	_add(root, _box(Vector3(0.05, 0.02, 0.9)), Mats.unshaded(Color(color, 0.25)), Vector3(0, 0, 0.45))
	root.scale = Vector3.ONE * 1.3 * s


static func _build_bullet(root: Node3D, color: Color, s: float) -> void:
	_add(root, _sphere(0.08 * s), Mats.glow(color.lightened(0.4), 3.0), Vector3.ZERO, Vector3(1, 1, 2.2))
	_add(root, _sphere(0.05 * s), Mats.unshaded(Color(color, 0.45)), Vector3(0, 0, 0.35 * s), Vector3(1, 1, 7.0))


static func _build_axe(root: Node3D, color: Color, enemy: bool = false) -> void:
	var tilt := Node3D.new()
	tilt.name = "Tilt"
	tilt.rotation_degrees = Vector3(25, 0, 0)
	root.add_child(tilt)
	var spinner := Node3D.new()
	spinner.name = "Spinner"
	tilt.add_child(spinner)
	# Handle lies flat; the axe spins around Y like a disc seen from above.
	var handle := _add(spinner, _cylinder(0.035, 0.035, 0.62), Mats.toon(Color(0.45, 0.3, 0.18)), Vector3.ZERO)
	handle.rotation_degrees = Vector3(90, 0, 0)
	var metal := Mats.toon(color.lerp(Color(0.72, 0.74, 0.78), 0.6))
	_add(spinner, _box(Vector3(0.3, 0.05, 0.2)), metal, Vector3(0.13, 0, -0.24))
	# Cutting edge: white-hot on enemy throws, plain bright steel otherwise.
	var edge := Mats.glow(ENEMY_CORE.lerp(Color.WHITE, 0.35), 2.2) if enemy else Mats.unshaded(Color(1.0, 0.95, 0.85))
	_add(spinner, _box(Vector3(0.06, 0.055, 0.26)), edge, Vector3(0.3, 0, -0.24))
	_add(spinner, _box(Vector3(0.08, 0.07, 0.07)), Mats.toon(Color(0.35, 0.22, 0.12)), Vector3(0, 0, 0.3))
	# Motion blur disc (the enemy halo replaces it).
	if not enemy:
		_add(root, _cylinder(0.42, 0.42, 0.01, 20), Mats.unshaded(Color(0.85, 0.85, 0.9, 0.16)), Vector3.ZERO)


static func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _sphere(radius: float) -> Mesh:
	var key := "s%.3f" % radius
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = 12
		m.rings = 6
		_meshes[key] = m
	return _meshes[key]


static func _cylinder(top: float, bottom: float, height: float, segments: int = 8) -> Mesh:
	var key := "c%.3f_%.3f_%.3f_%d" % [top, bottom, height, segments]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = segments
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func _box(size: Vector3) -> Mesh:
	var key := "b%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]
