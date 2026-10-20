class_name OnionCosmetics
extends RefCounted
## The procedural shapes of the Wardrobe cosmetics (M9 WARDROBE; the visuals module, next to OnionArmor): a Tabard (a coloured
## cloth overlay on the chest), a Hat variant (a head piece) and a Glow (an unshaded ring of light). Each is keyed by the
## [member CosmeticData.style] and built from MeshKit primitives, once per style / colour, cached.
##
## They are parts like the armour's ([OnionArmor.Part]): the Tabard's cloth and trim join the Gear meshes, a Hat replaces the
## Head part, a Glow is its own unshaded mesh that OnionModel turns slowly. Body coordinates as in OnionModel: y up, the face
## looks to -Z, lathe angle 0 = front.

## Parts built so far, by key.
static var _parts: Dictionary[String, OnionArmor.Part] = {}

# --- Tabard ---------------------------------------------------------------------------------

## Lowest / highest height of the tabard panel (the face starts above it) and its half-width in degrees. The panel hangs from the
## chest like a cloth: it hugs the bulb at the top and flares out below, over the belt and the class starter tabard.
const TABARD_Y0 := 0.1
const TABARD_Y1 := 0.43
const TABARD_HALF_DEG := 30.0
## Radius of the panel at the hem and at the shoulder line (the top follows the bulb, TABARD_TOP_LIFT off its skin).
const TABARD_HEM_RADIUS := 0.475
const TABARD_TOP_LIFT := 0.04


## The Tabard [param c] as a part: the panel and its trim in the cloth channel, the emblem and fringe in the solid channel.
## [param dye] (alpha > 0) replaces the cloth colour; the trim keeps its own.
static func tabard_part(c: CosmeticData, dye: Color = Color(0, 0, 0, 0)) -> OnionArmor.Part:
	var cloth_color := dye if dye.a > 0.0 else c.color
	var key := "tabard.%s.%s" % [c.id, cloth_color.to_html(false)]
	if _parts.has(key):
		return _parts[key]
	var solid := MeshKit.new()
	var cloth := MeshKit.new()
	_tabard(solid, cloth, c, cloth_color)
	var p := OnionArmor.Part.new()
	_parts[key] = OnionArmor._finish(p, key, solid, cloth, null)
	return p


static func _tabard(k: MeshKit, cloth: MeshKit, c: CosmeticData, main: Color) -> void:
	var trim := c.trim
	var half := TABARD_HALF_DEG
	# The panel: hugs the bulb at the top, swings out to the hem; a lighter fold down the middle.
	var prof := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		var y := lerpf(TABARD_Y0, TABARD_Y1, t)
		prof.append(Vector2(lerpf(TABARD_HEM_RADIUS, OnionModel.bulb_radius(TABARD_Y1) + TABARD_TOP_LIFT, t * t), y))
	cloth.add_lathe(prof, Transform3D(), main, 8, -half, half, true)
	cloth.add_lathe(_offset(prof, 0.004), Transform3D(), main.lightened(0.14), 2, -4.0, 4.0, true)
	# Trim: two edge stripes and a hem band.
	for side: float in [-1.0, 1.0]:
		cloth.add_lathe(_offset(prof, 0.006), Transform3D(), trim, 1, half * side - 2.2 * side, half * side + 0.6 * side, true)
	var hem := PackedVector2Array([Vector2(TABARD_HEM_RADIUS + 0.008, TABARD_Y0), Vector2(TABARD_HEM_RADIUS + 0.008, TABARD_Y0 + 0.045)])
	cloth.add_lathe(hem, Transform3D(), trim, 8, -half - 0.6, half + 0.6, true)
	# A row of small beads on the hem.
	for i in 5:
		var a := deg_to_rad(lerpf(-half * 0.8, half * 0.8, float(i) / 4.0))
		k.add_sphere(0.02, MeshKit.xf(Vector3(sin(a), 0.0, -cos(a)) * (TABARD_HEM_RADIUS + 0.012) + Vector3(0, TABARD_Y0 - 0.008, 0)), trim, 6, 3)
	# The emblem on the front, leaning with the cloth's slope.
	var ey := 0.27
	var r_at := lerpf(TABARD_HEM_RADIUS, OnionModel.bulb_radius(TABARD_Y1) + TABARD_TOP_LIFT, pow((ey - TABARD_Y0) / (TABARD_Y1 - TABARD_Y0), 2.0))
	var slope := rad_to_deg(atan2(TABARD_HEM_RADIUS - (OnionModel.bulb_radius(TABARD_Y1) + TABARD_TOP_LIFT), TABARD_Y1 - TABARD_Y0)) * 0.9
	var xform := MeshKit.xf(Vector3(0, ey, -(r_at + 0.014)), Vector3(slope, 0, 0))
	for shape: Dictionary in _emblem(c.style, trim, main):
		k.add_extrusion(shape["outline"], shape.get("depth", 0.022), Transform3D(xform.basis, xform * Vector3(shape.get("at", Vector3.ZERO))),
				shape["color"], 0.9)


## The profile moved outwards by [param d].
static func _offset(prof: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in prof:
		out.append(Vector2(p.x + d, p.y))
	return out


## The shapes of a tabard emblem: [{outline, color, at?, depth?}] in the panel's plane (x right, y up, about 0.2 across).
static func _emblem(style: StringName, trim: Color, main: Color) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match style:
		&"star":
			out.append({"outline": _star(5, 0.1, 0.045), "color": trim})
		&"sun":
			out.append({"outline": _star(12, 0.105, 0.065), "color": trim})
			out.append({"outline": _star(16, 0.045, 0.042), "color": main.darkened(0.12), "at": Vector3(0, 0, -0.012), "depth": 0.02})
		&"chevron":
			out.append({"outline": PackedVector2Array([Vector2(-0.1, 0.1), Vector2(-0.1, 0.045), Vector2(0, -0.035), Vector2(0.1, 0.045),
					Vector2(0.1, 0.1), Vector2(0, 0.02)]), "color": trim})
			out.append({"outline": PackedVector2Array([Vector2(-0.1, 0.0), Vector2(-0.1, -0.055), Vector2(0, -0.135), Vector2(0.1, -0.055),
					Vector2(0.1, 0.0), Vector2(0, -0.08)]), "color": trim.darkened(0.15)})
		&"dagger":
			out.append({"outline": PackedVector2Array([Vector2(0, 0.13), Vector2(0.03, 0.04), Vector2(0.02, -0.07), Vector2(0, -0.11),
					Vector2(-0.02, -0.07), Vector2(-0.03, 0.04)]), "color": trim})
			out.append({"outline": PackedVector2Array([Vector2(-0.075, -0.045), Vector2(0.075, -0.045), Vector2(0.075, -0.07),
					Vector2(-0.075, -0.07)]), "color": trim.darkened(0.2)})
		&"rune":
			out.append({"outline": PackedVector2Array([Vector2(-0.1, 0.09), Vector2(0.1, 0.09), Vector2(0.0, -0.11)]), "color": trim})
			out.append({"outline": PackedVector2Array([Vector2(-0.055, 0.06), Vector2(0.055, 0.06), Vector2(0.0, -0.045)]),
					"color": main.darkened(0.2), "at": Vector3(0, 0, -0.012), "depth": 0.02})
		&"leaf":
			out.append({"outline": PackedVector2Array([Vector2(0, 0.13), Vector2(0.07, 0.07), Vector2(0.09, -0.01), Vector2(0.05, -0.08),
					Vector2(0, -0.11), Vector2(-0.05, -0.08), Vector2(-0.09, -0.01), Vector2(-0.07, 0.07)]), "color": trim})
			out.append({"outline": PackedVector2Array([Vector2(-0.008, 0.1), Vector2(0.008, 0.1), Vector2(0.008, -0.12), Vector2(-0.008, -0.12)]),
					"color": main.darkened(0.25), "at": Vector3(0, 0, -0.012), "depth": 0.02})
		&"bolt":
			out.append({"outline": PackedVector2Array([Vector2(0.03, 0.14), Vector2(-0.07, -0.01), Vector2(-0.01, -0.01), Vector2(-0.04, -0.14),
					Vector2(0.08, 0.02), Vector2(0.01, 0.02), Vector2(0.06, 0.14)]), "color": trim})
		&"gem":
			out.append({"outline": PackedVector2Array([Vector2(0, 0.12), Vector2(0.075, 0.03), Vector2(0.0, -0.1), Vector2(-0.075, 0.03)]), "color": trim})
			out.append({"outline": PackedVector2Array([Vector2(0, 0.075), Vector2(0.04, 0.025), Vector2(0.0, -0.045), Vector2(-0.04, 0.025)]),
					"color": Color(0.95, 0.25, 0.35), "at": Vector3(0, 0, -0.012), "depth": 0.02})
		_:
			out.append({"outline": _star(4, 0.09, 0.04), "color": trim})
	return out


## A star outline with [param points] tips (outer / inner radius), one tip up.
static func _star(points: int, outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := PI * float(i) / float(points)
		var r := outer if i % 2 == 0 else inner
		pts.append(Vector2(sin(a), cos(a)) * r)
	return pts


# --- Hat variants ---------------------------------------------------------------------------

## The Hat variant [param c] as the head part (replaces the look / starter head piece). Self-contained: it looks the same on
## every class (the class only decides the face: brows, sprout, mouth follow the hat).
static func hat_part(c: CosmeticData) -> OnionArmor.Part:
	var key := "hat.%s" % c.id
	if _parts.has(key):
		return _parts[key]
	var solid := MeshKit.new()
	var cloth := MeshKit.new()
	var p := OnionArmor.Part.new()
	p.brows = true
	match c.style:
		&"bullhorn":
			p.brows = false
			_hat_bullhorn(solid, c)
		&"moonpeak":
			p.hides_sprout = true
			_hat_moonpeak(solid, c)
		&"crowned":
			p.brows = false
			_hat_crowned(solid, c)
		&"cutpurse":
			p.hides_sprout = true
			p.hides_mouth = true
			_hat_cutpurse(solid, cloth, c)
		&"imp_horn":
			p.hides_sprout = true
			_hat_imp_horn(solid, cloth, c)
		&"feathered":
			p.hides_sprout = true
			_hat_feathered(solid, cloth, c)
		&"thunder_mask":
			_hat_thunder_mask(solid, cloth, c)
		_:
			OnionArmor._head_plain(solid, _stand_in(c))
	_parts[key] = OnionArmor._finish(p, key, solid, cloth, null)
	return p


## A throw-away ClassData that carries [param c]'s colour as its accent: the starter head builders read the class's accent colour.
static func _stand_in(c: CosmeticData, accent: Color = Color.TRANSPARENT) -> ClassData:
	var cd := ClassData.new()
	cd.accent_color = accent if accent.a > 0.0 else c.color
	return cd


## Bullhorn Helm: a steel dome with two thick ivory bull horns sweeping out and forward, bronze rings at their roots.
static func _hat_bullhorn(k: MeshKit, c: CosmeticData) -> void:
	OnionArmor._helm_dome(k, c.color, c.trim.darkened(0.2))
	for side: float in [-1.0, 1.0]:
		var horn := PackedVector3Array([Vector3(0.3 * side, 0.78, 0.04), Vector3(0.47 * side, 0.74, -0.04), Vector3(0.6 * side, 0.8, -0.2),
				Vector3(0.62 * side, 0.93, -0.36), Vector3(0.54 * side, 1.06, -0.44)])
		k.add_tube(horn, 0.1, 0.014, OnionModel.IVORY, 8)
		k.add_torus(0.07, 0.125, Transform3D(MeshKit.basis_from_y(Vector3(side, -0.1, -0.1)), Vector3(0.33 * side, 0.77, 0.02)), c.trim, 10, 4)
	# A bronze brow band across the front of the dome.
	k.add_box(Vector3(0.22, 0.05, 0.03), MeshKit.xf(OnionModel.bulb_point(0.8, 0.0, 0.02)), c.trim)


## Moonpeak Hat: a deep blue wizard hat whose tip is bent over, a pale crescent moon on the front and a ring of silver stars.
static func _hat_moonpeak(k: MeshKit, c: CosmeticData) -> void:
	var hat := c.color
	k.add_cylinder(0.52, 0.52, 0.035, MeshKit.xf(Vector3(0, 0.77, 0), Vector3(-6, 0, 0)), hat.darkened(0.15), 24)
	var cone := PackedVector3Array([Vector3(0, 0.77, 0.0), Vector3(0, 0.98, 0.0), Vector3(0, 1.2, 0.03), Vector3(0, 1.4, 0.12),
			Vector3(0, 1.52, 0.3), Vector3(0, 1.5, 0.48)])
	k.add_tube(cone, 0.3, 0.02, hat, 16)
	k.add_torus(0.27, 0.33, MeshKit.xf(Vector3(0, 0.83, 0.006), Vector3(-6, 0, 0), Vector3(1, 1.4, 1)), c.trim.darkened(0.25), 24, 5)
	k.add_extrusion(OnionArmor._crescent(0.17), 0.04, MeshKit.xf(Vector3(0, 1.0, -0.3), Vector3(-14, 0, 0)), c.trim, 0.8)
	for i in 3:
		var a := lerpf(-40.0, 40.0, float(i) / 2.0)
		k.add_extrusion(_star(5, 0.045, 0.02), 0.014, MeshKit.xf(OnionModel.bulb_point(0.9, a, 0.14) + Vector3(0, 0.0, -0.1),
				Vector3(-10, 0, 0)), Color(0.9, 0.93, 1.0), 0.9)
	k.add_sphere(0.04, MeshKit.xf(Vector3(0, 1.5, 0.5)), c.trim, 8, 4)


## Crowned Helm: a pale dome with a gold crown (seven points, red gems) round it.
static func _hat_crowned(k: MeshKit, c: CosmeticData) -> void:
	OnionArmor._helm_dome(k, c.color, c.trim)
	var y := 0.84
	k.add_torus(0.3, 0.37, MeshKit.xf(Vector3(0, y, 0), Vector3.ZERO, Vector3(1, 1.1, 1)), c.trim, 28, 5)
	for i in 7:
		var a := TAU * float(i) / 7.0
		var r := 0.335
		var base := Vector3(sin(a) * r, y, cos(a) * r)
		k.add_segment(base, base + Vector3(0, 0.17, 0), 0.052, 0.0, c.trim, 8)
		k.add_sphere(0.028, MeshKit.xf(base + Vector3(0, 0.185, 0)), Color(0.9, 0.2, 0.28) if i % 2 == 0 else c.trim.lightened(0.3), 6, 3)
	k.add_sphere(0.04, MeshKit.xf(OnionModel.bulb_point(y, 0.0, 0.04)), Color(0.35, 0.65, 1.0), 8, 4)


## Cutpurse Hood: a dark hood with a long tail, a leather band across the brow and a copper coin pinned to the front.
static func _hat_cutpurse(k: MeshKit, cloth: MeshKit, c: CosmeticData) -> void:
	OnionArmor._hood_cap(k, c.color)
	OnionArmor._hood_sides(cloth, c.color)
	# The long tail drooping behind.
	var tail := PackedVector3Array([Vector3(0, 0.95, 0.33), Vector3(0, 0.82, 0.48), Vector3(0, 0.62, 0.55), Vector3(0, 0.42, 0.56)])
	k.add_tube(tail, 0.065, 0.015, c.color.lightened(0.05), 8)
	var r := OnionModel.bulb_radius(0.72) * 1.1 + 0.02
	k.add_torus(r - 0.02, r + 0.03, MeshKit.xf(Vector3(0, 0.74, 0), Vector3.ZERO, Vector3(1, 0.9, 1)), OnionModel.LEATHER, 26, 4)
	k.add_cylinder(0.05, 0.05, 0.02, MeshKit.xf(OnionModel.bulb_point(0.76, 0.0, 0.06), Vector3(78, 0, 0)), c.trim, 12)
	k.add_cylinder(0.03, 0.03, 0.025, MeshKit.xf(OnionModel.bulb_point(0.76, 0.0, 0.065), Vector3(78, 0, 0)), c.trim.darkened(0.25), 10)


## Imp-Horn Hood: a violet hood with two short curled imp horns, two pointed ears and a pale rim.
static func _hat_imp_horn(k: MeshKit, cloth: MeshKit, c: CosmeticData) -> void:
	OnionArmor._hood_cap(k, c.color)
	OnionArmor._hood_sides(cloth, c.color)
	for side: float in [-1.0, 1.0]:
		var horn := PackedVector3Array([Vector3(0.2 * side, 0.9, -0.1), Vector3(0.27 * side, 1.0, -0.15), Vector3(0.27 * side, 1.12, -0.12),
				Vector3(0.2 * side, 1.18, -0.06)])
		k.add_tube(horn, 0.058, 0.01, c.trim, 8)
		k.add_torus(0.045, 0.082, Transform3D(MeshKit.basis_from_y(Vector3(0.7 * side, 1.0, -0.5)), horn[0]), c.trim.lightened(0.2), 10, 4)
		# A pointed ear sticking out sideways.
		var ear := PackedVector2Array([Vector2(0, 0.08), Vector2(0.22 * side, 0.2), Vector2(0.03 * side, -0.05)])
		k.add_extrusion(ear, 0.03, MeshKit.xf(Vector3(0.36 * side, 0.7, 0.05), Vector3(0, -20.0 * side, 0)), c.color.lightened(0.1), 0.8)
	var rim := OnionModel.bulb_radius(0.69) * 1.1 + 0.02
	k.add_torus(rim - 0.02, rim + 0.02, MeshKit.xf(Vector3(0, 0.72, 0)), c.trim.lightened(0.25), 26, 4)


## Feathered Hat: the hunter's felt hat in autumn brown with three long feathers (one red) swept back.
static func _hat_feathered(k: MeshKit, cloth: MeshKit, c: CosmeticData) -> void:
	OnionArmor._head_hunter_hat(k, cloth, _stand_in(c))
	var root := Vector3(-0.2, 0.92, 0.14)
	var vane := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.07, 0.1), Vector2(0.1, 0.28), Vector2(0.07, 0.46),
			Vector2(0.0, 0.62), Vector2(-0.05, 0.4), Vector2(-0.06, 0.18)])
	k.add_extrusion(vane, 0.02, MeshKit.xf(root, Vector3(-38, 14, -6)), c.trim, 0.9)
	var vane2 := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.05, 0.08), Vector2(0.07, 0.22), Vector2(0.0, 0.46),
			Vector2(-0.04, 0.2)])
	k.add_extrusion(vane2, 0.016, MeshKit.xf(root + Vector3(0.03, 0, 0.02), Vector3(-22, 26, 10)), Color(0.96, 0.9, 0.7), 0.9)


## Thunder Mask: the shaman's carved mask in electric blue paint with a crest of two lightning bolts.
static func _hat_thunder_mask(k: MeshKit, cloth: MeshKit, c: CosmeticData) -> void:
	OnionArmor._head_tribal_mask(k, cloth, _stand_in(c, c.trim))
	var bolt := PackedVector2Array([Vector2(0.03, 0.2), Vector2(-0.06, 0.04), Vector2(-0.01, 0.04), Vector2(-0.05, -0.1),
			Vector2(0.07, 0.07), Vector2(0.01, 0.07), Vector2(0.07, 0.2)])
	for side: float in [-1.0, 1.0]:
		k.add_extrusion(bolt, 0.03, MeshKit.xf(Vector3(0.14 * side, 0.96, -0.2), Vector3(-30, 0, 18.0 * side)), c.trim.lightened(0.25), 0.9)


# --- Glow -----------------------------------------------------------------------------------

## The Glow [param c] as one mesh (white vertices: the light colour is the material's). Everything sits inside a 0.8 m radius
## round the onion, rings low or high, the rest orbiting; OnionModel turns the node.
static func glow_mesh(c: CosmeticData) -> Mesh:
	var key := "onion:glow:%s" % c.style
	return MeshKit.cached(key, func() -> Mesh:
		var k := MeshKit.new()
		_glow(k, c.style)
		return k.build())


static func _glow(k: MeshKit, style: StringName) -> void:
	var white := Color.WHITE
	match style:
		&"embers":
			_floor_ring(k, 0.56, 0.02)
			for i in 9:
				var a := TAU * float(i) / 9.0 + float(i) * 0.4
				var r := 0.62 + 0.1 * float(i % 3)
				k.add_sphere(0.032 + 0.012 * float(i % 3), MeshKit.xf(Vector3(sin(a) * r, 0.1 + 0.055 * float(i), cos(a) * r)), white, 6, 3)
		&"halo_star":
			_halo(k, 0.3, 1.38, 0.014)
			for i in 6:
				var a := TAU * float(i) / 6.0
				k.add_extrusion(_star(5, 0.06, 0.026), 0.012, MeshKit.xf(Vector3(sin(a) * 0.3, 1.38, cos(a) * 0.3), Vector3(90, 0, 0)), white, 0.9)
			_floor_ring(k, 0.56, 0.012)
		&"halo_sun":
			_halo(k, 0.33, 1.38, 0.022)
			for i in 12:
				var a := TAU * float(i) / 12.0
				var dir := Vector3(sin(a), 0, cos(a))
				k.add_segment(dir * 0.37 + Vector3(0, 1.38, 0), dir * 0.5 + Vector3(0, 1.38, 0), 0.026, 0.0, white, 6)
		&"wisp":
			# Three curls of smoke rising from the ground round the feet.
			for w in 3:
				var pts := PackedVector3Array()
				for step in 9:
					var t := float(step) / 8.0
					var a := TAU * (0.3 * t + float(w) / 3.0)
					var r := 0.58 + 0.1 * t
					pts.append(Vector3(sin(a) * r, 0.05 + t * 0.32, cos(a) * r))
				k.add_tube(pts, 0.05, 0.008, white, 6)
			_floor_ring(k, 0.5, 0.012)
		&"flames":
			_floor_ring(k, 0.55, 0.014)
			for i in 8:
				var a := TAU * float(i) / 8.0
				var base := Vector3(sin(a) * 0.58, 0.05, cos(a) * 0.58)
				k.add_segment(base, base + Vector3(0, 0.26 + 0.07 * float(i % 2), 0), 0.055, 0.0, white, 6)
				k.add_sphere(0.045, MeshKit.xf(base + Vector3(0, 0.05, 0)), white, 6, 3)
		&"leaves":
			var leaf := PackedVector2Array([Vector2(0, 0.0), Vector2(0.06, 0.07), Vector2(0.05, 0.16), Vector2(0, 0.24), Vector2(-0.05, 0.16),
					Vector2(-0.06, 0.07)])
			for i in 7:
				var a := TAU * float(i) / 7.0
				var pos := Vector3(sin(a) * 0.64, 0.08 + 0.1 * float(i % 4), cos(a) * 0.64)
				k.add_extrusion(leaf, 0.012, Transform3D(Basis.from_euler(Vector3(deg_to_rad(-70.0), a + PI, 0.0)), pos), white, 0.9)
		&"sparks":
			_floor_ring(k, 0.56, 0.012)
			for i in 6:
				var a := TAU * float(i) / 6.0 + 0.3
				var dir := Vector3(sin(a), 0, cos(a))
				var side := Vector3(dir.z, 0, -dir.x)
				var pts := PackedVector3Array()
				for step in 5:
					var off := 0.06 * (1.0 if step % 2 == 0 else -1.0)
					pts.append(dir * (0.56 + 0.05 * float(step)) + side * off + Vector3(0, 0.05 + 0.09 * float(step) + 0.03 * float(i % 3), 0))
				k.add_tube(pts, 0.02, 0.012, white, 5)
		&"crystals":
			_floor_ring(k, 0.5, 0.012)
			for i in 8:
				var a := TAU * float(i) / 8.0 + 0.2
				var h := 0.28 + 0.12 * float(i % 3)
				var base := Vector3(sin(a) * 0.6, 0.04, cos(a) * 0.6)
				var lean := Vector3(sin(a) * 0.07, 0, cos(a) * 0.07)
				k.add_segment(base, base + Vector3(0, h * 0.65, 0) + lean * 0.6, 0.05, 0.05, white, 6)
				k.add_segment(base + Vector3(0, h * 0.65, 0) + lean * 0.6, base + Vector3(0, h, 0) + lean, 0.05, 0.0, white, 6)
		_:
			_floor_ring(k, 0.56, 0.02)


## A flat thin ring of light on the ground, [param radius] to the middle of the band.
static func _floor_ring(k: MeshKit, radius: float, half_width: float) -> void:
	k.add_torus(radius - half_width, radius + half_width, MeshKit.xf(Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 0.5, 1)), Color.WHITE, 40, 5)


## A ring of light floating at [param y] above the head.
static func _halo(k: MeshKit, radius: float, y: float, half_width: float) -> void:
	k.add_torus(radius - half_width, radius + half_width, MeshKit.xf(Vector3(0, y, 0)), Color.WHITE, 36, 6)
