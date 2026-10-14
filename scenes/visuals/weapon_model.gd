class_name WeaponModel
extends RefCounted
## Procedural weapon meshes (owned by the "visuals" module). Chunky, WoW-like proportions.
## Every weapon is ONE cached vertex-coloured mesh (+ an optional glowing gem / orb), so
## many onions holding the same weapon share the Mesh resources.

const GOLD := Color(0.95, 0.74, 0.28)
const DARK_GOLD := Color(0.72, 0.5, 0.18)
const LEATHER := Color(0.36, 0.22, 0.13)
const WOOD := Color(0.5, 0.32, 0.17)
const IRON := Color(0.38, 0.38, 0.42)
const BONE := Color(0.93, 0.89, 0.76)
const RARITY_COLORS: Array[Color] = [
	Color(0.9, 0.9, 0.9),     # common
	Color(0.12, 1.0, 0.0),    # uncommon
	Color(0.0, 0.44, 0.87),   # rare
	Color(0.64, 0.21, 0.93),  # epic
	Color(1.0, 0.5, 0.0),     # legendary
	Color(1.0, 0.84, 0.4),    # artifact (M6)
]
## Rarity from which a weapon glows faintly (GDD 13: epic and legendary).
const GLOW_RARITY := 3
const TYPES: Array[StringName] = [&"sword", &"axe", &"mace", &"dagger", &"bow", &"gun", &"wand",
	&"staff", &"shield", &"tome"]


## Builds a small primitive mesh for [param weapon] (by weapon_type, coloured by weapon.color).
## The handle is at the origin, the blade / head points along +Y.
static func build(weapon: WeaponData) -> Node3D:
	var root := Node3D.new()
	if weapon == null:
		return root
	var type := weapon.weapon_type
	root.name = "Weapon_%s" % type
	var key := "weapon:%s:%s" % [type, weapon.color.to_html()]
	var mesh := MeshKit.cached(key, func() -> Mesh: return _build_mesh(type, weapon.color))
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = _body_material(weapon.rarity)
	root.add_child(mi)
	var gem := _gem_info(type, weapon.color)
	if not gem.is_empty():
		var g := MeshInstance3D.new()
		g.name = "Glow"
		g.mesh = MeshKit.cached("weapon_gem:%s" % type, func() -> Mesh: return _gem_mesh(type))
		g.material_override = Mats.glow(gem["color"], 2.2)
		g.position = gem["pos"]
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(g)
	return root


## Approximate length of the weapon along +Y from the handle (pose helpers, VFX).
static func reach(weapon_type: StringName) -> float:
	match weapon_type:
		&"sword": return 0.86
		&"axe": return 0.85
		&"mace": return 0.58
		&"dagger": return 0.45
		&"bow": return 0.5
		&"gun": return 0.72
		&"wand": return 0.44
		&"staff": return 0.9
		&"shield": return 0.3
		&"tome": return 0.18
	return 0.5


static func rarity_color(rarity: int) -> Color:
	return RARITY_COLORS[clampi(rarity, 0, RARITY_COLORS.size() - 1)]


# --- Internals ---------------------------------------------------------------

static func _body_material(rarity: int) -> Material:
	if rarity < GLOW_RARITY:
		return Mats.toon_vc()
	return Mats.toon_vc_glow(rarity_color(rarity), 0.55)


static func _gem_info(type: StringName, color: Color) -> Dictionary:
	match type:
		&"wand":
			return {"color": color.lightened(0.25), "pos": Vector3(0, 0.40, 0)}
		&"staff":
			return {"color": Color(0.72, 0.38, 1.0), "pos": Vector3(0, 0.84, 0)}
		&"tome":
			return {"color": Color(0.55, 0.85, 1.0), "pos": Vector3(0, 0.02, -0.04)}
		&"sword":
			return {"color": Color(1.0, 0.25, 0.2), "pos": Vector3(0, 0.17, -0.04)}
	return {}


static func _gem_mesh(type: StringName) -> Mesh:
	var kit := MeshKit.new()
	match type:
		&"staff":
			kit.add_sphere(0.085, Transform3D(), Color.WHITE, 12, 6)
		&"tome":
			kit.add_extrusion(PackedVector2Array([Vector2(0, 0.07), Vector2(0.045, 0), Vector2(0, -0.07),
				Vector2(-0.045, 0)]), 0.012, Transform3D(), Color.WHITE)
		&"sword":
			kit.add_sphere(0.028, Transform3D(), Color.WHITE, 8, 4)
		_:
			# Faceted gem: a squashed octahedron.
			kit.add_sphere(0.05, MeshKit.xf(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.4, 1)), Color.WHITE, 4, 2)
	return kit.build()


static func _build_mesh(type: StringName, c: Color) -> Mesh:
	var k := MeshKit.new()
	match type:
		&"sword": _sword(k, c)
		&"axe": _axe(k, c)
		&"mace": _mace(k, c)
		&"dagger": _dagger(k, c)
		&"bow": _bow(k, c)
		&"gun": _gun(k, c)
		&"wand": _wand(k, c)
		&"staff": _staff(k, c)
		&"shield": _shield(k, c)
		&"tome": _tome(k, c)
		_: _generic(k, c)
	return k.build()


static func _sword(k: MeshKit, c: Color) -> void:
	k.add_sphere(0.045, MeshKit.xf(Vector3(0, -0.05, 0)), GOLD, 10, 5)
	k.add_cylinder(0.028, 0.03, 0.2, MeshKit.xf(Vector3(0, 0.06, 0)), LEATHER, 8)
	k.add_box(Vector3(0.3, 0.055, 0.075), MeshKit.xf(Vector3(0, 0.17, 0)), GOLD)
	k.add_sphere(0.04, MeshKit.xf(Vector3(0.155, 0.19, 0)), GOLD, 8, 4)
	k.add_sphere(0.04, MeshKit.xf(Vector3(-0.155, 0.19, 0)), GOLD, 8, 4)
	var blade := PackedVector2Array([Vector2(-0.065, 0.19), Vector2(0.065, 0.19), Vector2(0.058, 0.72),
		Vector2(0.0, 0.87), Vector2(-0.058, 0.72)])
	k.add_extrusion(blade, 0.03, Transform3D(), c, 0.8)
	k.add_box(Vector3(0.02, 0.44, 0.034), MeshKit.xf(Vector3(0, 0.44, 0)), c.darkened(0.3))


static func _axe(k: MeshKit, c: Color) -> void:
	k.add_cylinder(0.032, 0.036, 1.18, MeshKit.xf(Vector3(0, 0.22, 0)), WOOD, 8)
	k.add_cylinder(0.042, 0.042, 0.16, MeshKit.xf(Vector3(0, 0.0, 0)), LEATHER, 8)
	k.add_sphere(0.045, MeshKit.xf(Vector3(0, -0.38, 0)), IRON, 8, 4)
	k.add_box(Vector3(0.1, 0.2, 0.09), MeshKit.xf(Vector3(0, 0.62, 0)), IRON)
	var blade := PackedVector2Array([Vector2(0.04, 0.54), Vector2(0.14, 0.49), Vector2(0.25, 0.41),
		Vector2(0.33, 0.5), Vector2(0.37, 0.62), Vector2(0.33, 0.74), Vector2(0.25, 0.83),
		Vector2(0.14, 0.75), Vector2(0.04, 0.7)])
	k.add_extrusion(blade, 0.035, Transform3D(), c, 0.85)
	var mirrored := PackedVector2Array()
	for p in blade:
		mirrored.append(Vector2(-p.x * 0.8, p.y))
	k.add_extrusion(mirrored, 0.035, Transform3D(), c, 0.85)
	k.add_cylinder(0.0, 0.035, 0.14, MeshKit.xf(Vector3(0, 0.79, 0)), IRON, 6)


static func _mace(k: MeshKit, c: Color) -> void:
	k.add_sphere(0.04, MeshKit.xf(Vector3(0, -0.05, 0)), GOLD, 8, 4)
	k.add_cylinder(0.028, 0.03, 0.4, MeshKit.xf(Vector3(0, 0.16, 0)), LEATHER, 8)
	k.add_torus(0.025, 0.05, MeshKit.xf(Vector3(0, 0.36, 0)), GOLD, 10, 5)
	k.add_sphere(0.1, MeshKit.xf(Vector3(0, 0.47, 0)), c, 12, 6)
	for i in 6:
		var a := TAU * i / 6.0
		var dir := Vector3(sin(a), 0, cos(a))
		k.add_box(Vector3(0.025, 0.17, 0.08), Transform3D(Basis(Vector3.UP, a), Vector3(0, 0.47, 0) + dir * 0.09), c.darkened(0.15))
	k.add_cylinder(0.0, 0.03, 0.09, MeshKit.xf(Vector3(0, 0.6, 0)), GOLD, 6)


static func _dagger(k: MeshKit, c: Color) -> void:
	k.add_sphere(0.032, MeshKit.xf(Vector3(0, -0.04, 0)), GOLD, 8, 4)
	k.add_cylinder(0.022, 0.024, 0.13, MeshKit.xf(Vector3(0, 0.03, 0)), LEATHER, 8)
	k.add_box(Vector3(0.17, 0.035, 0.05), MeshKit.xf(Vector3(0, 0.11, 0), Vector3(0, 0, 0)), DARK_GOLD)
	var blade := PackedVector2Array([Vector2(-0.042, 0.125), Vector2(0.042, 0.125), Vector2(0.05, 0.25),
		Vector2(0.025, 0.38), Vector2(0.0, 0.46), Vector2(-0.03, 0.33)])
	k.add_extrusion(blade, 0.022, Transform3D(), c, 0.75)


static func _bow(k: MeshKit, c: Color) -> void:
	var pts := PackedVector3Array()
	for i in 9:
		var t := lerpf(-1.0, 1.0, i / 8.0)
		var z := -0.13 * (1.0 - t * t) + 0.04 * pow(absf(t), 4.0)
		pts.append(Vector3(0, t * 0.52, z))
	var top := PackedVector3Array()
	var bottom := PackedVector3Array()
	for i in 5:
		bottom.append(pts[4 - i])
		top.append(pts[4 + i])
	k.add_tube(top, 0.032, 0.014, c, 7)
	k.add_tube(bottom, 0.032, 0.014, c, 7)
	k.add_cylinder(0.04, 0.04, 0.16, MeshKit.xf(Vector3(0, 0, -0.13)), LEATHER, 8)
	k.add_sphere(0.022, MeshKit.xf(pts[0]), GOLD, 6, 3)
	k.add_sphere(0.022, MeshKit.xf(pts[8]), GOLD, 6, 3)
	k.add_segment(pts[0], pts[8], 0.006, 0.006, Color(0.95, 0.92, 0.82), 4, false)


static func _gun(k: MeshKit, c: Color) -> void:
	# Stock and grip below the handle, barrel along +Y.
	var stock := PackedVector2Array([Vector2(-0.03, 0.12), Vector2(0.03, 0.12), Vector2(0.035, -0.05),
		Vector2(0.06, -0.24), Vector2(-0.07, -0.26), Vector2(-0.045, -0.05)])
	k.add_extrusion(stock, 0.07, MeshKit.xf(Vector3.ZERO, Vector3(0, 90, 0)), WOOD, 0.9)
	k.add_cylinder(0.034, 0.038, 0.56, MeshKit.xf(Vector3(0, 0.36, 0)), c, 10)
	k.add_cylinder(0.065, 0.038, 0.1, MeshKit.xf(Vector3(0, 0.68, 0)), GOLD, 10)
	k.add_torus(0.032, 0.05, MeshKit.xf(Vector3(0, 0.2, 0)), GOLD, 10, 4)
	k.add_torus(0.032, 0.05, MeshKit.xf(Vector3(0, 0.46, 0)), GOLD, 10, 4)
	k.add_box(Vector3(0.025, 0.06, 0.04), MeshKit.xf(Vector3(0, 0.09, 0.05)), IRON)


static func _wand(k: MeshKit, c: Color) -> void:
	k.add_cylinder(0.016, 0.024, 0.36, MeshKit.xf(Vector3(0, 0.15, 0)), BONE.lerp(c, 0.25), 8)
	k.add_torus(0.018, 0.035, MeshKit.xf(Vector3(0, 0.05, 0)), GOLD, 8, 4)
	k.add_torus(0.016, 0.034, MeshKit.xf(Vector3(0, 0.31, 0)), GOLD, 8, 4)
	for i in 3:
		var a := TAU * i / 3.0
		var base := Vector3(sin(a) * 0.02, 0.33, cos(a) * 0.02)
		var tip := Vector3(sin(a) * 0.045, 0.43, cos(a) * 0.045)
		k.add_segment(base, tip, 0.011, 0.004, GOLD, 5)


static func _staff(k: MeshKit, c: Color) -> void:
	var shaft := PackedVector3Array([Vector3(0, -0.56, 0), Vector3(0.015, -0.15, 0.01),
		Vector3(-0.012, 0.3, -0.01), Vector3(0, 0.7, 0)])
	k.add_tube(shaft, 0.03, 0.037, c, 8)
	k.add_cylinder(0.045, 0.045, 0.18, MeshKit.xf(Vector3(0, 0.0, 0)), LEATHER, 8)
	k.add_torus(0.035, 0.06, MeshKit.xf(Vector3(0, 0.7, 0)), GOLD, 10, 5)
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		var d := Vector3(sin(a), 0, cos(a))
		var claw := PackedVector3Array([Vector3(0, 0.7, 0) + d * 0.03, Vector3(0, 0.78, 0) + d * 0.1,
			Vector3(0, 0.9, 0) + d * 0.1, Vector3(0, 0.96, 0) + d * 0.04])
		k.add_tube(claw, 0.022, 0.008, c.darkened(0.15), 6)
	k.add_cylinder(0.025, 0.0, 0.1, MeshKit.xf(Vector3(0, -0.6, 0)), IRON, 6)


static func _shield(k: MeshKit, c: Color) -> void:
	var outline := PackedVector2Array([Vector2(-0.25, 0.24), Vector2(0.0, 0.28), Vector2(0.25, 0.24),
		Vector2(0.25, 0.02), Vector2(0.18, -0.17), Vector2(0.0, -0.31), Vector2(-0.18, -0.17), Vector2(-0.25, 0.02)])
	var rim := PackedVector2Array()
	var field := PackedVector2Array()
	for p in outline:
		rim.append(p * 1.1)
		field.append(p * 0.72 + Vector2(0, 0.01))
	k.add_extrusion(rim, 0.05, MeshKit.xf(Vector3(0, 0, 0.012)), GOLD, 0.95)
	k.add_extrusion(outline, 0.06, Transform3D(), c, 0.95)
	k.add_extrusion(field, 0.02, MeshKit.xf(Vector3(0, 0, -0.03)), Color(0.16, 0.27, 0.62))
	k.add_sphere(0.075, MeshKit.xf(Vector3(0, 0.0, -0.035), Vector3.ZERO, Vector3(1, 1, 0.55)), GOLD, 10, 5)
	var star := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0
		var r := 0.17 if i % 2 == 0 else 0.05
		star.append(Vector2(sin(a), cos(a)) * r)
	k.add_extrusion(star, 0.015, MeshKit.xf(Vector3(0, 0.0, -0.042)), GOLD)
	k.add_box(Vector3(0.05, 0.14, 0.04), MeshKit.xf(Vector3(0, 0, 0.05)), LEATHER)


static func _tome(k: MeshKit, c: Color) -> void:
	k.add_box(Vector3(0.26, 0.33, 0.075), Transform3D(), c)
	k.add_box(Vector3(0.24, 0.31, 0.06), MeshKit.xf(Vector3(0.018, 0, 0)), Color(0.97, 0.93, 0.8))
	k.add_cylinder(0.04, 0.04, 0.33, MeshKit.xf(Vector3(-0.13, 0, 0)), c.darkened(0.2), 8)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			k.add_box(Vector3(0.05, 0.05, 0.085), MeshKit.xf(Vector3(0.11 * sx, 0.145 * sy, 0)), GOLD)
	k.add_torus(0.05, 0.075, MeshKit.xf(Vector3(0, 0.02, -0.038), Vector3(90, 0, 0), Vector3(1, 1, 0.3)), GOLD, 12, 4)


static func _generic(k: MeshKit, c: Color) -> void:
	k.add_cylinder(0.025, 0.03, 0.5, MeshKit.xf(Vector3(0, 0.2, 0)), WOOD, 8)
	k.add_sphere(0.06, MeshKit.xf(Vector3(0, 0.48, 0)), c, 10, 5)
