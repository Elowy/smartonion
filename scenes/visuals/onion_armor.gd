class_name OnionArmor
extends RefCounted
## Procedural armour pieces of the onion hero (GDD 13, owned by the "visuals" module).
##
## Three slots are visible on the model: Head, Shoulders and Chest ([enum EquipLook.Slot]). Each slot
## shows either the class starter piece (slot empty: the horned helm, pointy hat, hood ... the classes
## had before equipment became visible) or the piece of the worn item ([EquipLook]): a silhouette
## family per armour type (cloth hood / mantle / robe, leather cap / pads / tunic, mail coif /
## spaulders / hauberk, plate great helm / pauldrons / breastplate), detail by material tier
## (I: plain + trim, II: crest / studs / lames, III: wings / spikes / gems), trim in the rarity
## colour, a faint glow for Epic and better, a glow accent for Legendaries and a class-coloured kit for
## tier sets. An equipped item replaces the slot's starter piece entirely.
##
## One [Part] = one slot's meshes in up to three channels that OnionModel merges by material:
##  - [member Part.solid]  vertex-coloured toon (outlined), plain or with a faint rarity glow;
##  - [member Part.cloth]  double-sided cloth without outline (capes, robes, hood sides);
##  - [member Part.accent] unshaded glowing details (gems, glow rings) of Legendaries and sets.
## Parts and their meshes are built once per look and cached (MeshKit.cached / [method part]).
##
## Body coordinates as in OnionModel: y up, the face looks to -Z, lathe angle 0 = front.

## Faint emission of a worn Epic piece / of a Legendary or set piece (see Mats.toon_vc_glow).
const GLOW_ENERGY := 0.14
const LEGENDARY_GLOW_ENERGY := 0.24
## Energy of the unshaded accent gems and rings (Mats.glow).
const ACCENT_ENERGY := 2.0

## Tier sets (data/sets): the kit a set piece wears – the class sets in their class colour, the
## class-independent sets (M8) in a colour of their own (kept apart from the class kits). main / dark /
## light are the armour colours, trim the ornament colour, glow the emission and accent colour. A set
## without an entry uses [constant GENERIC_SET].
const SET_STYLES := {
	&"battlegear_of_fury": {"main": Color(0.74, 0.17, 0.19), "dark": Color(0.42, 0.08, 0.1),
		"light": Color(0.93, 0.36, 0.28), "trim": Color(1.0, 0.8, 0.32), "glow": Color(1.0, 0.45, 0.2)},
	&"dawnforged_plate": {"main": Color(0.97, 0.93, 0.78), "dark": Color(0.78, 0.62, 0.28),
		"light": Color(1.0, 0.99, 0.92), "trim": Color(1.0, 0.8, 0.3), "glow": Color(1.0, 0.9, 0.5)},
	&"regalia_of_the_arcane": {"main": Color(0.3, 0.38, 0.9), "dark": Color(0.16, 0.2, 0.55),
		"light": Color(0.62, 0.8, 1.0), "trim": Color(0.88, 0.95, 1.0), "glow": Color(0.45, 0.78, 1.0)},
	&"shadowstitch_garb": {"main": Color(0.22, 0.2, 0.3), "dark": Color(0.1, 0.09, 0.15),
		"light": Color(0.42, 0.36, 0.55), "trim": Color(0.6, 0.92, 0.3), "glow": Color(0.55, 0.95, 0.3)},
	&"felfire_raiment": {"main": Color(0.4, 0.17, 0.5), "dark": Color(0.2, 0.08, 0.28),
		"light": Color(0.62, 0.34, 0.75), "trim": Color(0.5, 1.0, 0.3), "glow": Color(0.5, 1.0, 0.3)},
	# Class-independent sets: rose silk, oiled grey-blue leather, copper scale, thorn crimson, bark brown.
	&"mendweave_attire": {"main": Color(0.93, 0.62, 0.72), "dark": Color(0.62, 0.3, 0.42),
		"light": Color(1.0, 0.85, 0.9), "trim": Color(1.0, 0.95, 0.75), "glow": Color(1.0, 0.7, 0.8)},
	&"slipskin_leathers": {"main": Color(0.74, 0.8, 0.86), "dark": Color(0.42, 0.5, 0.6),
		"light": Color(0.92, 0.96, 1.0), "trim": Color(0.35, 0.9, 0.85), "glow": Color(0.5, 0.95, 0.95)},
	&"hoardscale_mail": {"main": Color(0.86, 0.52, 0.2), "dark": Color(0.5, 0.28, 0.1),
		"light": Color(1.0, 0.78, 0.4), "trim": Color(1.0, 0.9, 0.35), "glow": Color(1.0, 0.8, 0.3)},
	&"redthorn_mail": {"main": Color(0.5, 0.1, 0.2), "dark": Color(0.26, 0.05, 0.1),
		"light": Color(0.78, 0.28, 0.38), "trim": Color(0.9, 0.85, 0.8), "glow": Color(1.0, 0.35, 0.35)},
	&"stonebark_plate": {"main": Color(0.5, 0.4, 0.32), "dark": Color(0.28, 0.21, 0.16),
		"light": Color(0.72, 0.62, 0.5), "trim": Color(0.7, 0.8, 0.55), "glow": Color(0.75, 0.9, 0.5)},
}
const GENERIC_SET := {"main": Color(0.9, 0.76, 0.35), "dark": Color(0.55, 0.4, 0.15),
	"light": Color(1.0, 0.92, 0.65), "trim": Color(0.8, 0.5, 1.0), "glow": Color(0.8, 0.5, 1.0)}

## Armour colours (main, dark, light) per armour type and material tier (Items.MATERIAL_NAMES:
## Linen / Silk / Moonweave, Rugged / Thick / Shadowhide, Chain / Scaled / Stormforged,
## Iron / Steel / Runed).
const PALETTES := [
	[[Color(0.86, 0.78, 0.62), Color(0.58, 0.46, 0.32), Color(0.96, 0.92, 0.8)],
		[Color(0.3, 0.58, 0.88), Color(0.16, 0.34, 0.62), Color(0.66, 0.82, 0.98)],
		[Color(0.46, 0.3, 0.82), Color(0.25, 0.15, 0.52), Color(0.72, 0.66, 0.95)]],
	[[Color(0.58, 0.4, 0.23), Color(0.35, 0.22, 0.12), Color(0.74, 0.56, 0.35)],
		[Color(0.44, 0.29, 0.17), Color(0.26, 0.16, 0.1), Color(0.78, 0.6, 0.32)],
		[Color(0.26, 0.2, 0.32), Color(0.14, 0.11, 0.18), Color(0.55, 0.42, 0.66)]],
	[[Color(0.62, 0.66, 0.72), Color(0.38, 0.41, 0.47), Color(0.72, 0.75, 0.82)],
		[Color(0.66, 0.52, 0.32), Color(0.42, 0.31, 0.18), Color(0.8, 0.64, 0.38)],
		[Color(0.4, 0.55, 0.82), Color(0.22, 0.3, 0.5), Color(0.58, 0.74, 0.95)]],
	[[Color(0.5, 0.52, 0.56), Color(0.28, 0.29, 0.33), Color(0.68, 0.7, 0.75)],
		[Color(0.5, 0.56, 0.7), Color(0.3, 0.34, 0.46), Color(0.64, 0.7, 0.84)],
		[Color(0.36, 0.41, 0.56), Color(0.2, 0.22, 0.32), Color(0.58, 0.66, 0.86)]],
]

## Lathe angle range (degrees) of the chest shells: they wrap the sides and the back and leave the face
## open (the eyes sit mid-body), so the onion's own skin colour still shows (class readability).
const OPEN_FRONT := Vector2(52.0, 308.0)

static var _parts: Dictionary[String, Part] = {}


## One slot's meshes (see the class doc). Built once per key, immutable afterwards.
class Part:
	extends RefCounted
	var key := ""
	var solid: Mesh
	var cloth: Mesh
	var accent: Mesh
	## Emission colour of the solid mesh (alpha 0 = plain toon, no glow) and its energy.
	var glow := Color(0, 0, 0, 0)
	var glow_energy := 0.0
	var accent_color := Color.WHITE
	## Head parts: what they do to the face / sprout of the onion body.
	var brows := true
	var hides_sprout := false
	var hides_mouth := false
	## Starter parts: extra animated / glowing nodes OnionModel adds (&"hat_star", &"horn_flames",
	## &"fel_trim").
	var extras: Array[StringName] = []

	func is_starter() -> bool:
		return key.begins_with("starter")

	## Key of the material the solid mesh is drawn with ("" = plain toon).
	func material_key() -> String:
		return "" if glow.a <= 0.0 else "%s:%.2f" % [glow.to_html(false), glow_energy]


## Palette of one worn piece.
class Pal:
	extends RefCounted
	var main := Color.WHITE
	var dark := Color.GRAY
	var light := Color.WHITE
	var trim := Color.WHITE
	var glow := Color.WHITE
	## The wearer's class colour (onion skin): crests, tabard strips, mantle drapes – generic armour
	## still tells the classes apart.
	var tint := Color.WHITE


# --- Parts ---------------------------------------------------------------------

## The part for [param slot] (EquipLook.Slot): the worn [param look], or the starter piece of
## [param cd] when [param look] is null. Cached; null when there is nothing to show.
static func part(slot: int, look: EquipLook, cd: ClassData) -> Part:
	if look != null:
		var key := "item.%s.%s" % [look.key(), cd.id if cd != null else &""]
		if not _parts.has(key):
			_parts[key] = _build_item(key, look, cd.onion_color if cd != null else Color(0.85, 0.55, 0.3))
		return _parts[key]
	if cd == null:
		return null
	var skey := "starter.%d.%s.%s.%s" % [slot, cd.headgear, cd.accent_color.to_html(), cd.big_shoulders]
	if not _parts.has(skey):
		_parts[skey] = _build_starter(skey, slot, cd)
	return _parts[skey]


## Merges [param meshes] (vertex-coloured, single surface) into one cached mesh under [param key].
static func merged(key: String, meshes: Array[Mesh]) -> Mesh:
	return MeshKit.cached(key, func() -> Mesh: return _merge(meshes))


static func _merge(meshes: Array[Mesh]) -> Mesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for mesh in meshes:
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var base := verts.size()
			verts.append_array(v)
			normals.append_array(arrays[Mesh.ARRAY_NORMAL])
			colors.append_array(arrays[Mesh.ARRAY_COLOR])
			uvs.append_array(arrays[Mesh.ARRAY_TEX_UV])
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in idx:
				indices.append(base + i)
	var out := ArrayMesh.new()
	if verts.is_empty():
		return out
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## Colours of a worn piece: armour palette by type and tier, the set kit for a set piece.
static func palette(look: EquipLook, class_color: Color = Color.WHITE) -> Pal:
	var p := Pal.new()
	p.tint = class_color.lightened(0.08)
	if look.is_set():
		var s: Dictionary = SET_STYLES.get(look.set_id, GENERIC_SET)
		p.main = s["main"]
		p.dark = s["dark"]
		p.light = s["light"]
		p.trim = s["trim"]
		p.glow = s["glow"]
		p.tint = p.main
		return p
	var row: Array = PALETTES[clampi(look.armor, 0, 3)][clampi(look.tier, 0, 2)]
	p.main = row[0]
	p.dark = row[1]
	p.light = row[2]
	p.trim = look.trim_color()
	p.glow = look.trim_color()
	return p


static func _finish(p: Part, key: String, solid: MeshKit, cloth: MeshKit, accent: MeshKit) -> Part:
	p.key = key
	p.solid = _cached_or_null(key + ":solid", solid)
	p.cloth = _cached_or_null(key + ":cloth", cloth)
	p.accent = _cached_or_null(key + ":accent", accent)
	return p


static func _cached_or_null(key: String, kit: MeshKit) -> Mesh:
	if kit == null or kit.is_empty():
		return null
	return MeshKit.cached("onion:armor:" + key, func() -> Mesh: return kit.build())


# --- Worn items ----------------------------------------------------------------

static func _build_item(key: String, look: EquipLook, class_color: Color) -> Part:
	var p := Part.new()
	var solid := MeshKit.new()
	var cloth := MeshKit.new()
	var accent := MeshKit.new()
	var pal := palette(look, class_color)
	match look.slot:
		EquipLook.Slot.HEAD:
			p.brows = false
			_head(solid, cloth, accent, look, pal, p)
		EquipLook.Slot.SHOULDERS:
			_shoulders(solid, cloth, accent, look, pal)
		_:
			_chest(solid, cloth, accent, look, pal)
	if look.glows():
		p.glow = pal.glow
		p.glow_energy = LEGENDARY_GLOW_ENERGY if look.rarity >= EquipLook.LEGENDARY_RARITY else GLOW_ENERGY
	p.accent_color = pal.glow
	return _finish(p, key, solid, cloth, accent)


## Adds a gem of [param pos] / [param radius]: glowing (accent mesh) on a Legendary or set piece,
## a plain trim-coloured stone otherwise.
static func _gem(solid: MeshKit, accent: MeshKit, look: EquipLook, pal: Pal, pos: Vector3, radius: float) -> void:
	var xform := MeshKit.xf(pos, Vector3.ZERO, Vector3(1.0, 1.3, 1.0))
	if look.has_accent():
		accent.add_sphere(radius, xform, Color.WHITE, 8, 4)
	else:
		solid.add_sphere(radius, xform, pal.trim, 8, 4)


## A glowing ring (accent) – only Legendaries and sets have one.
static func _glow_ring(accent: MeshKit, look: EquipLook, inner: float, outer: float, xform: Transform3D) -> void:
	if look.has_accent():
		accent.add_torus(inner, outer, xform, Color.WHITE, 24, 4)


# --- Shared shapes ---------------------------------------------------------------

## Lathe shell hugging the bulb between y0 and y1, pushed out by [param extra] metres.
static func _shell(k: MeshKit, y0: float, y1: float, extra: float, color: Color, from_deg: float = 0.0,
		to_deg: float = 360.0, scale: float = 1.0, segments: int = 24, steps: int = 4) -> void:
	var prof := PackedVector2Array()
	for i in steps + 1:
		var y := lerpf(y0, y1, float(i) / float(steps))
		prof.append(Vector2(OnionModel.bulb_radius(y) * scale + extra, y))
	k.add_lathe(prof, Transform3D(), color, segments, from_deg, to_deg)


## Stacked rings of alternating shade, every other one a little proud (ring / scale mail look).
static func _bands(k: MeshKit, y0: float, y1: float, count: int, extra: float, color_a: Color, color_b: Color,
		from_deg: float = 0.0, to_deg: float = 360.0, scale: float = 1.0, segments: int = 22) -> void:
	for i in count:
		var ya := lerpf(y0, y1, float(i) / float(count))
		var yb := lerpf(y0, y1, float(i + 1) / float(count))
		var odd := i % 2 == 1
		_shell(k, ya, yb, extra + (0.014 if odd else 0.0), color_b if odd else color_a, from_deg, to_deg, scale,
			segments, 1)


## A ridge over the head running front to back: half ellipse of [param half] x [param height],
## [param base] is the centre of its bottom edge.
static func _fin(k: MeshKit, base: Vector3, half: float, height: float, depth: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 11:
		var a := PI * i / 10.0
		pts.append(Vector2(cos(a) * half, sin(a) * height))
	k.add_extrusion(pts, depth, MeshKit.xf(base, Vector3(0, 90, 0)), color, 0.85)


## A cone from [param a] to the tip [param b].
static func _spike(k: MeshKit, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	k.add_segment(a, b, radius, 0.0, color, 7)


static func _angled(angle_deg: float) -> Basis:
	return Basis.from_euler(Vector3(0, deg_to_rad(-angle_deg), 0))


## A flat plate on the bulb at ([param y], [param angle_deg]): outline in (across, up) metres.
static func _plate(k: MeshKit, outline: PackedVector2Array, y: float, angle_deg: float, out: float, depth: float,
		color: Color, bevel: float = 0.9) -> void:
	var p := OnionModel.bulb_point(y, angle_deg, out)
	k.add_extrusion(outline, depth, Transform3D(_angled(angle_deg), p), color, bevel)


## A dome-and-rim pauldron on the shoulder; [param layers] stacked plates, each smaller.
static func _pauldron(k: MeshKit, side: float, radius: float, layers: int, main: Color, light: Color, trim: Color,
		dark: Color, centre: Vector3 = Vector3(0.335, 0.6, 0.03), tilt: float = 48.0) -> Basis:
	var b := Basis.from_euler(Vector3(0, 0, deg_to_rad(-tilt * side)))
	var c := Vector3(centre.x * side, centre.y, centre.z)
	for i in layers:
		var r := radius * (1.0 - 0.2 * i)
		var cc := c + b * Vector3(0, radius * 0.36 * i, 0)
		var col := main.lerp(light, 0.16 * i)
		k.add_sphere(r, Transform3D(b * Basis.from_scale(Vector3(1.05, 1.0, 1.0)), cc), col, 16, 8, true)
		k.add_torus(r * 0.86, r * 1.16, Transform3D(b * Basis.from_scale(Vector3(1.05, 0.6, 1.0)), cc),
			trim if i == 0 else dark, 18, 5)
	return b


# --- Head ---------------------------------------------------------------------

static func _head(k: MeshKit, cloth: MeshKit, acc: MeshKit, look: EquipLook, pal: Pal, p: Part) -> void:
	var d := look.detail()
	match look.armor:
		ClassData.ArmorType.PLATE: _plate_head(k, acc, look, pal, d)
		ClassData.ArmorType.MAIL: _mail_head(k, acc, look, pal, d)
		ClassData.ArmorType.LEATHER: _leather_head(k, cloth, acc, look, pal, d, p)
		_: _cloth_head(k, cloth, acc, look, pal, d)


## Plate: a tall bucket helm; II adds a crest fin, cheek plates and rivets, III swept wings.
static func _plate_head(k: MeshKit, acc: MeshKit, look: EquipLook, pal: Pal, d: int) -> void:
	var prof := PackedVector2Array([Vector2(0.352, 0.655), Vector2(0.362, 0.72), Vector2(0.358, 0.82),
		Vector2(0.335, 0.92), Vector2(0.27, 0.995), Vector2(0.15, 1.035), Vector2(0.0, 1.05)])
	k.add_lathe(prof, Transform3D(), pal.main, 28)
	k.add_torus(0.335, 0.398, MeshKit.xf(Vector3(0, 0.672, 0), Vector3.ZERO, Vector3(1, 0.7, 1)), pal.trim, 28, 5)
	# Brow band: a darker strap across the helm.
	k.add_torus(0.352, 0.378, MeshKit.xf(Vector3(0, 0.82, 0), Vector3.ZERO, Vector3(1, 1.1, 1)), pal.dark, 28, 4)
	_glow_ring(acc, look, 0.34, 0.405, MeshKit.xf(Vector3(0, 0.672, 0), Vector3.ZERO, Vector3(1, 0.7, 1)))
	if d >= 1:
		_fin(k, Vector3(0, 0.9, 0), 0.31, 0.2 + 0.04 * d, 0.05, pal.tint)
		for side: float in [-1.0, 1.0]:
			var cheek := PackedVector2Array([Vector2(-0.07, 0.0), Vector2(0.07, 0.0), Vector2(0.06, -0.2),
				Vector2(0.0, -0.27), Vector2(-0.06, -0.2)])
			_plate(k, cheek, 0.66, 78.0 * side, 0.03, 0.03, pal.main.lerp(pal.light, 0.3))
			for i in 3:
				k.add_sphere(0.022, MeshKit.xf(OnionModel.bulb_point(0.75 + 0.04 * i, 62.0 * side, 0.05)), pal.light, 6, 3)
	if d >= 2:
		for side: float in [-1.0, 1.0]:
			var wing: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.05, 0.14), Vector2(0.16, 0.3), Vector2(0.3, 0.47),
				Vector2(0.29, 0.3), Vector2(0.37, 0.31), Vector2(0.31, 0.16), Vector2(0.38, 0.12), Vector2(0.25, 0.03),
				Vector2(0.1, -0.03)]
			var outline := PackedVector2Array()
			for v in wing:
				outline.append(Vector2(v.x * side, v.y))
			var xf := MeshKit.xf(Vector3(0.31 * side, 0.78, 0.05), Vector3(0, -34.0 * side, 0))
			k.add_extrusion(outline, 0.035, xf, pal.light, 0.9)
			k.add_extrusion(outline, 0.05, xf * Transform3D(Basis.from_scale(Vector3(0.55, 0.45, 1.0)), Vector3(0.02 * side, 0.02, 0)),
				pal.trim, 0.9)
		_gem(k, acc, look, pal, Vector3(0, 0.78, -0.372), 0.04)


## Mail: a ring-mail coif framing the face; II adds a steel skull cap and brow band, III a crest.
static func _mail_head(k: MeshKit, acc: MeshKit, look: EquipLook, pal: Pal, d: int) -> void:
	_bands(k, 0.72, 1.0, 6, 0.03, pal.main, pal.dark, 0.0, 360.0, 1.1)
	_bands(k, 0.42, 0.74, 5, 0.03, pal.main, pal.dark, 52.0, 308.0, 1.1)
	k.add_torus(0.31, 0.39, MeshKit.xf(Vector3(0, 0.72, 0), Vector3.ZERO, Vector3(1, 0.6, 1)), pal.trim, 26, 4)
	_glow_ring(acc, look, 0.31, 0.395, MeshKit.xf(Vector3(0, 0.72, 0), Vector3.ZERO, Vector3(1, 0.6, 1)))
	if d >= 1:
		k.add_sphere(0.345, MeshKit.xf(Vector3(0, 0.76, 0), Vector3.ZERO, Vector3(1.0, 0.9, 1.0)), pal.main.lerp(pal.light, 0.4), 24, 9, true)
		k.add_torus(0.33, 0.385, MeshKit.xf(Vector3(0, 0.77, 0), Vector3.ZERO, Vector3(1, 0.7, 1)), pal.dark, 26, 4)
		for side: float in [-1.0, 1.0]:
			var flap := PackedVector2Array([Vector2(-0.06, 0.0), Vector2(0.06, 0.0), Vector2(0.05, -0.16),
				Vector2(-0.04, -0.15)])
			_plate(k, flap, 0.7, 84.0 * side, 0.04, 0.03, pal.light)
	if d >= 2:
		_fin(k, Vector3(0, 0.95, 0), 0.3, 0.2, 0.045, pal.tint)
		for side: float in [-1.0, 1.0]:
			var fin := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.14, 0.1), Vector2(0.3, 0.3), Vector2(0.2, 0.12),
				Vector2(0.34, 0.1), Vector2(0.14, -0.02)])
			var outline := PackedVector2Array()
			for v in fin:
				outline.append(Vector2(v.x * side, v.y))
			k.add_extrusion(outline, 0.03, MeshKit.xf(Vector3(0.32 * side, 0.82, 0.04), Vector3(0, -30.0 * side, 0)), pal.light, 0.9)
		_gem(k, acc, look, pal, Vector3(0, 0.795, -0.358), 0.036)


## Leather: I a skull cap, II a bandana with a face mask, III a pointed hood with feathers.
static func _leather_head(k: MeshKit, cloth: MeshKit, acc: MeshKit, look: EquipLook, pal: Pal, d: int, p: Part) -> void:
	if d <= 1:
		k.add_sphere(0.348, MeshKit.xf(Vector3(0, 0.69, 0), Vector3.ZERO, Vector3(1.0, 0.95, 1.0)), pal.main, 24, 9, true)
		k.add_torus(0.33, 0.385, MeshKit.xf(Vector3(0, 0.7, 0), Vector3.ZERO, Vector3(1, 0.7, 1)), pal.trim, 26, 4)
		_glow_ring(acc, look, 0.335, 0.39, MeshKit.xf(Vector3(0, 0.7, 0), Vector3.ZERO, Vector3(1, 0.7, 1)))
		# Stitch seam over the crown.
		_fin(k, Vector3(0, 0.78, 0), 0.34, 0.27, 0.02, pal.dark)
	if d == 1:
		# Bandana tails knotted at the back, and a dark mask over the lower face.
		var knot := OnionModel.bulb_point(0.72, 180.0, 0.05)
		k.add_sphere(0.05, MeshKit.xf(knot, Vector3.ZERO, Vector3(1.2, 0.9, 0.9)), pal.dark, 8, 4)
		for i in 2:
			var side := -1.0 if i == 0 else 1.0
			var tail := PackedVector2Array([Vector2(-0.04, 0.0), Vector2(0.04, 0.0), Vector2(0.035, -0.2),
				Vector2(0.0, -0.15), Vector2(-0.035, -0.2)])
			cloth.add_extrusion(tail, 0.02, MeshKit.xf(knot + Vector3(0.03 * side, -0.02, 0.02), Vector3(-20, 12.0 * side, 0)),
				pal.tint, 0.9)
		_shell(k, 0.36, 0.45, 0.03, pal.dark, -42.0, 42.0)
		k.add_torus(0.4, 0.43, MeshKit.xf(Vector3(0, 0.455, 0), Vector3.ZERO, Vector3(1, 0.8, 1)), pal.trim, 26, 4)
		p.hides_mouth = true
	if d >= 2:
		var prof := PackedVector2Array()
		for q in OnionModel.bulb_profile():
			if q.y >= 0.66:
				prof.append(Vector2(q.x * 1.1 + 0.02, q.y + 0.03))
		k.add_lathe(prof, Transform3D(), pal.main, 28)
		var tip := PackedVector3Array([Vector3(0, 0.98, 0.04), Vector3(0, 1.08, 0.12), Vector3(0, 1.1, 0.26),
			Vector3(0, 1.02, 0.34)])
		k.add_tube(tip, 0.075, 0.015, pal.main, 8)
		k.add_torus(0.33, 0.4, MeshKit.xf(Vector3(0, 0.7, 0), Vector3.ZERO, Vector3(1, 0.7, 1)), pal.trim, 28, 4)
		_glow_ring(acc, look, 0.335, 0.405, MeshKit.xf(Vector3(0, 0.7, 0), Vector3.ZERO, Vector3(1, 0.7, 1)))
		# Mask and two long feathers sweeping back.
		_shell(k, 0.36, 0.45, 0.03, pal.dark, -44.0, 44.0)
		for side: float in [-1.0, 1.0]:
			var feather := PackedVector3Array([Vector3(0.14 * side, 0.98, 0.12), Vector3(0.24 * side, 1.12, 0.2),
				Vector3(0.3 * side, 1.22, 0.34), Vector3(0.3 * side, 1.24, 0.5)])
			k.add_tube(feather, 0.03, 0.006, pal.tint, 6)
		p.hides_mouth = true
		_gem(k, acc, look, pal, Vector3(0, 0.82, -0.37), 0.034)


## Cloth: I a hood, II a silk cowl with a brooch and lappets, III a hood with a circlet and a
## crescent crest.
static func _cloth_head(k: MeshKit, cloth: MeshKit, acc: MeshKit, look: EquipLook, pal: Pal, d: int) -> void:
	var prof := PackedVector2Array()
	for q in OnionModel.bulb_profile():
		if q.y >= 0.66:
			prof.append(Vector2(q.x * 1.1 + 0.02, q.y + 0.03))
	k.add_lathe(prof, Transform3D(), pal.main, 28)
	var tip := PackedVector3Array([Vector3(0, 0.98, 0.04), Vector3(0, 1.06, 0.14), Vector3(0, 1.03, 0.27),
		Vector3(0, 0.94, 0.33 + 0.04 * d)])
	k.add_tube(tip, 0.075, 0.015, pal.main, 8)
	k.add_torus(0.335, 0.4, MeshKit.xf(Vector3(0, 0.7, 0), Vector3.ZERO, Vector3(1, 0.65, 1)), pal.trim, 28, 4)
	_glow_ring(acc, look, 0.34, 0.405, MeshKit.xf(Vector3(0, 0.7, 0), Vector3.ZERO, Vector3(1, 0.65, 1)))
	if d >= 1:
		var side_prof := PackedVector2Array()
		for q in OnionModel.bulb_profile():
			if q.y >= 0.42 and q.y <= 0.72:
				side_prof.append(Vector2(q.x * 1.1 + 0.02, q.y + 0.03))
		cloth.add_lathe(side_prof, Transform3D(), pal.dark, 18, 58.0, 302.0)
		_gem(k, acc, look, pal, Vector3(0, 0.76, -0.385), 0.04)
	if d >= 2:
		# Gold circlet round the hood and a crescent moon standing on its front.
		k.add_torus(0.31, 0.352, MeshKit.xf(Vector3(0, 0.77, 0), Vector3(-6, 0, 0)), OnionModel.GOLD, 26, 4)
		k.add_extrusion(_crescent(0.19), 0.04, MeshKit.xf(Vector3(0, 0.94, -0.22), Vector3(-12, 0, 0)), OnionModel.GOLD, 0.8)
		if look.has_accent():
			acc.add_sphere(0.036, MeshKit.xf(Vector3(0, 1.02, -0.22)), Color.WHITE, 8, 4)


## A crescent moon of outer [param radius] standing upright with its horns up (outline for an extrusion).
static func _crescent(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cut := radius * 0.46
	var e1 := Vector2(cos(deg_to_rad(60.0)), sin(deg_to_rad(60.0))) * radius
	var e2 := Vector2(e1.x, -e1.y)
	var centre := Vector2(cut, 0.0)
	var inner_r := e2.distance_to(centre)
	for i in 13:
		var t := deg_to_rad(60.0 + 240.0 * i / 12.0)
		pts.append(Vector2(cos(t), sin(t)) * radius)
	var t_start := (e2 - centre).angle() + TAU
	var t_end := (e1 - centre).angle()
	for i in range(1, 12):
		var t := lerpf(t_start, t_end, float(i) / 12.0)
		pts.append(centre + Vector2(cos(t), sin(t)) * inner_r)
	var out := PackedVector2Array()
	for v in pts:
		out.append(Vector2(-v.y, v.x))
	return out


# --- Shoulders ---------------------------------------------------------------------

static func _shoulders(k: MeshKit, cloth: MeshKit, acc: MeshKit, look: EquipLook, pal: Pal) -> void:
	var d := look.detail()
	match look.armor:
		ClassData.ArmorType.PLATE: _plate_shoulders(k, acc, look, pal, d)
		ClassData.ArmorType.MAIL: _mail_shoulders(k, acc, look, pal, d)
		ClassData.ArmorType.LEATHER: _leather_shoulders(k, acc, look, pal, d)
		_: _cloth_shoulders(k, cloth, acc, look, pal, d)


## Plate: the biggest pads (WoW-oversized); II adds a second plate and rivets, III big spikes.
static func _plate_shoulders(k: MeshKit, acc: MeshKit, look: EquipLook, pal: Pal, d: int) -> void:
	for side: float in [-1.0, 1.0]:
		var b := _pauldron(k, side, 0.26, 2 if d >= 1 else 1, pal.main, pal.tint, pal.trim, pal.dark)
		var c := Vector3(0.335 * side, 0.6, 0.03)
		# Lower lames hanging off the dome.
		k.add_torus(0.2, 0.29, Transform3D(b * Basis.from_scale(Vector3(1.05, 0.5, 1.0)), c + b * Vector3(0, -0.05, 0)),
			pal.dark, 18, 5)
		_glow_ring(acc, look, 0.22, 0.29, Transform3D(b * Basis.from_scale(Vector3(1.05, 0.6, 1.0)), c))
		if d >= 1:
			for i in 6:
				var a := TAU * i / 6.0
				k.add_sphere(0.02, Transform3D(b, c + b * Vector3(sin(a) * 0.235, 0.025, cos(a) * 0.235)), pal.light, 6, 3)
		if d == 1:
			_spike(k, c + b * Vector3(0, 0.22, 0), c + b * Vector3(0, 0.36, 0), 0.04, pal.light)
		if d >= 2:
			for s in 3:
				var dir := b * Vector3((s - 1) * 0.5, 1.0, 0).normalized()
				var base := c + b * Vector3((s - 1) * 0.1, 0.2, 0)
				_spike(k, base, base + dir * (0.22 if s == 1 else 0.17), 0.05, pal.light)
			_gem(k, acc, look, pal, c + b * Vector3(0, 0.1, -0.2), 0.045)


## Mail: segmented spaulders of stacked rings; II adds a trim ring and a third layer, III fins.
static func _mail_shoulders(k: MeshKit, acc: MeshKit, look: EquipLook, pal: Pal, d: int) -> void:
	for side: float in [-1.0, 1.0]:
		var b := Basis.from_euler(Vector3(0, 0, deg_to_rad(-48.0 * side)))
		var c := Vector3(0.33 * side, 0.6, 0.03)
		var layers := 3 + (1 if d >= 1 else 0)
		for i in layers:
			var r := 0.215 - 0.03 * i
			var cc := c + b * Vector3(0, 0.045 * i, 0)
			k.add_sphere(r, Transform3D(b * Basis.from_scale(Vector3(1.05, 0.8, 1.0)), cc),
				(pal.main if i % 2 == 0 else pal.dark) if i < layers - 1 else pal.tint, 16, 7, true)
			k.add_torus(r * 0.9, r * 1.12, Transform3D(b * Basis.from_scale(Vector3(1.05, 0.5, 1.0)), cc),
				pal.trim if i == 0 else pal.light, 18, 4)
		_glow_ring(acc, look, 0.19, 0.245, Transform3D(b * Basis.from_scale(Vector3(1.05, 0.5, 1.0)), c))
		if d >= 2:
			for s in 3:
				var base := c + b * Vector3((s - 1) * 0.1, 0.17, 0)
				_spike(k, base, base + b * Vector3((s - 1) * 0.06, 0.15, 0), 0.04, pal.light)
			_gem(k, acc, look, pal, c + b * Vector3(0, 0.17, -0.1), 0.04)


## Leather: two stitched layers with a strap; II adds brass studs, III spikes.
static func _leather_shoulders(k: MeshKit, acc: MeshKit, look: EquipLook, pal: Pal, d: int) -> void:
	for side: float in [-1.0, 1.0]:
		var b := _pauldron(k, side, 0.18, 2, pal.main, pal.tint, pal.trim, pal.dark, Vector3(0.325, 0.6, 0.03))
		var c := Vector3(0.325 * side, 0.6, 0.03)
		_glow_ring(acc, look, 0.16, 0.21, Transform3D(b * Basis.from_scale(Vector3(1.05, 0.6, 1.0)), c))
		if d >= 1:
			for i in 5:
				var a := TAU * i / 5.0
				k.add_sphere(0.018, Transform3D(b, c + b * Vector3(sin(a) * 0.17, 0.03, cos(a) * 0.17)), pal.light, 6, 3)
		if d >= 2:
			for s in 2:
				var base := c + b * Vector3((s - 0.5) * 0.14, 0.15, 0)
				_spike(k, base, base + b * Vector3((s - 0.5) * 0.1, 0.16, 0), 0.04, pal.dark)
			_gem(k, acc, look, pal, c + b * Vector3(0, 0.13, -0.12), 0.032)


## Cloth: a small mantle with a hanging drape; II adds trim, III a tassel and a gem.
static func _cloth_shoulders(k: MeshKit, cloth: MeshKit, acc: MeshKit, look: EquipLook, pal: Pal, d: int) -> void:
	for side: float in [-1.0, 1.0]:
		var b := Basis.from_euler(Vector3(0, 0, deg_to_rad(-44.0 * side)))
		var c := Vector3(0.31 * side, 0.62, 0.03)
		k.add_sphere(0.14, Transform3D(b * Basis.from_scale(Vector3(1.05, 0.9, 1.0)), c), pal.main, 14, 7, true)
		k.add_torus(0.12, 0.165, Transform3D(b * Basis.from_scale(Vector3(1.05, 0.6, 1.0)), c), pal.trim, 16, 4)
		_glow_ring(acc, look, 0.13, 0.17, Transform3D(b * Basis.from_scale(Vector3(1.05, 0.6, 1.0)), c))
		var drape := PackedVector2Array([Vector2(-0.12, 0.0), Vector2(0.12, 0.0), Vector2(0.15, -0.14), Vector2(0.06, -0.2),
			Vector2(-0.06, -0.2), Vector2(-0.15, -0.14)])
		cloth.add_extrusion(drape, 0.02, Transform3D(b, c + b * Vector3(0.06 * side, -0.04, 0)), pal.tint, 0.9)
		if d >= 1:
			k.add_sphere(0.08, Transform3D(b * Basis.from_scale(Vector3(1.0, 0.8, 1.0)), c + b * Vector3(0, 0.07, 0)), pal.light, 12, 6, true)
		if d >= 2:
			_gem(k, acc, look, pal, c + b * Vector3(0, 0.15, 0), 0.032)
			var tassel := PackedVector3Array([c + b * Vector3(0.16 * side, -0.02, 0), c + b * Vector3(0.2 * side, -0.14, 0)])
			k.add_tube(tassel, 0.018, 0.03, pal.trim, 6)


# --- Chest --------------------------------------------------------------------------

static func _chest(k: MeshKit, cloth: MeshKit, acc: MeshKit, look: EquipLook, pal: Pal) -> void:
	var d := look.detail()
	match look.armor:
		ClassData.ArmorType.PLATE: _plate_chest(k, cloth, acc, look, pal, d)
		ClassData.ArmorType.MAIL: _mail_chest(k, cloth, acc, look, pal, d)
		ClassData.ArmorType.LEATHER: _leather_chest(k, cloth, acc, look, pal, d)
		_: _cloth_chest(k, cloth, acc, look, pal, d)


## Belt ring round the waist, proud of the skirt band under it.
static func _belt_ring(k: MeshKit, color: Color, buckle: Color) -> void:
	k.add_torus(0.395, 0.445, MeshKit.xf(Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1, 0.65, 1)), color, 28, 5)
	k.add_box(Vector3(0.1, 0.08, 0.04), MeshKit.xf(OnionModel.bulb_point(0.3, 0.0, 0.075)), buckle)


## A strip of cloth in the wearer's class colour hanging down the back (the chest's "cloak").
static func _tabard_back(cloth: MeshKit, pal: Pal) -> void:
	var prof := PackedVector2Array()
	for i in 9:
		var y := lerpf(0.1, 0.8, float(i) / 8.0)
		prof.append(Vector2(OnionModel.bulb_radius(y) + 0.075 + (0.03 if y < 0.3 else 0.0), y))
	cloth.add_lathe(prof, Transform3D(), pal.tint, 6, 154.0, 206.0)


## Vertical trim stripes along the two edges of an open-front shell.
static func _edge_stripes(k: MeshKit, y0: float, y1: float, extra: float, color: Color) -> void:
	_shell(k, y0, y1, extra, color, OPEN_FRONT.x - 3.0, OPEN_FRONT.x + 1.0, 1.0, 3, 3)
	_shell(k, y0, y1, extra, color, OPEN_FRONT.y - 1.0, OPEN_FRONT.y + 3.0, 1.0, 3, 3)


## Plate: a cuirass that wraps the sides and back and leaves the face open, a skirt of belly guards;
## II adds tasset lames, III spine spikes and a belt gem.
static func _plate_chest(k: MeshKit, cloth: MeshKit, acc: MeshKit, look: EquipLook, pal: Pal, d: int) -> void:
	_shell(k, 0.39, 0.82, 0.038, pal.main, OPEN_FRONT.x, OPEN_FRONT.y)
	_shell(k, 0.79, 0.82, 0.05, pal.trim, OPEN_FRONT.x, OPEN_FRONT.y)
	_edge_stripes(k, 0.39, 0.82, 0.05, pal.light)
	k.add_segment(OnionModel.bulb_point(0.42, 180.0, 0.065), OnionModel.bulb_point(0.78, 180.0, 0.05), 0.022, 0.02, pal.light, 7)
	_shell(k, 0.12, 0.375, 0.04, pal.main.lerp(pal.dark, 0.25), 0.0, 360.0, 1.0, 26)
	_shell(k, 0.12, 0.15, 0.05, pal.trim, 0.0, 360.0, 1.0, 26, 1)
	_belt_ring(k, pal.dark, pal.trim)
	_tabard_back(cloth, pal)
	if d >= 1:
		_shell(k, 0.05, 0.19, 0.085, pal.light, 0.0, 360.0, 1.0, 26, 2)
		_shell(k, 0.05, 0.075, 0.095, pal.dark, 0.0, 360.0, 1.0, 26, 1)
	if d >= 2:
		for i in 3:
			var y := 0.5 + 0.12 * i
			_spike(k, OnionModel.bulb_point(y, 180.0, 0.05), OnionModel.bulb_point(y + 0.05, 180.0, 0.2), 0.04, pal.light)
		_gem(k, acc, look, pal, OnionModel.bulb_point(0.3, 0.0, 0.105), 0.05)
	_glow_ring(acc, look, 0.4, 0.45, MeshKit.xf(Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1, 0.65, 1)))


## Mail: a ring-mail hauberk (alternating ring bands) over the sides and back with a mail skirt; II
## adds a tabard over the belly, III spine spikes and a belt gem.
static func _mail_chest(k: MeshKit, cloth: MeshKit, acc: MeshKit, look: EquipLook, pal: Pal, d: int) -> void:
	_bands(k, 0.39, 0.82, 6, 0.032, pal.main, pal.dark, OPEN_FRONT.x, OPEN_FRONT.y)
	_shell(k, 0.8, 0.83, 0.05, pal.trim, OPEN_FRONT.x, OPEN_FRONT.y)
	_bands(k, 0.12, 0.375, 4, 0.04, pal.main, pal.dark, 0.0, 360.0, 1.0, 26)
	_shell(k, 0.12, 0.145, 0.056, pal.trim, 0.0, 360.0, 1.0, 26, 1)
	_belt_ring(k, pal.dark, pal.trim)
	_tabard_back(cloth, pal)
	if d >= 1:
		var panel := PackedVector2Array()
		for q in OnionModel.bulb_profile():
			if q.y >= 0.1 and q.y <= 0.375:
				panel.append(Vector2(q.x + 0.1, q.y))
		cloth.add_lathe(panel, Transform3D(), pal.tint, 8, -22.0, 22.0)
		cloth.add_lathe(PackedVector2Array([Vector2(0.482, 0.1), Vector2(0.478, 0.13)]), Transform3D(), pal.trim, 8, -22.0, 22.0)
	if d >= 2:
		for i in 3:
			var y := 0.5 + 0.12 * i
			_spike(k, OnionModel.bulb_point(y, 180.0, 0.05), OnionModel.bulb_point(y + 0.05, 180.0, 0.19), 0.036, pal.light)
		_gem(k, acc, look, pal, OnionModel.bulb_point(0.3, 0.0, 0.105), 0.046)
	_glow_ring(acc, look, 0.4, 0.45, MeshKit.xf(Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1, 0.65, 1)))


## Leather: a vest over the sides and back, a tunic skirt, a cross strap and belt pouches; II adds
## brass studs, III a short cloak and a strap gem.
static func _leather_chest(k: MeshKit, cloth: MeshKit, acc: MeshKit, look: EquipLook, pal: Pal, d: int) -> void:
	_shell(k, 0.39, 0.8, 0.03, pal.main, OPEN_FRONT.x, OPEN_FRONT.y)
	_shell(k, 0.77, 0.8, 0.042, pal.trim, OPEN_FRONT.x, OPEN_FRONT.y)
	_edge_stripes(k, 0.39, 0.8, 0.04, pal.dark)
	_shell(k, 0.12, 0.375, 0.036, pal.main.lerp(pal.dark, 0.2), 0.0, 360.0, 1.0, 26)
	_shell(k, 0.12, 0.15, 0.046, pal.dark, 0.0, 360.0, 1.0, 26, 1)
	var strap := Transform3D(Basis.from_euler(Vector3(0, 0, deg_to_rad(-34))) * Basis.from_scale(Vector3(1, 0.5, 1)), Vector3(0, 0.3, 0))
	k.add_torus(0.39, 0.435, strap, pal.dark, 28, 4)
	_belt_ring(k, pal.dark, pal.trim)
	_tabard_back(cloth, pal)
	for side: float in [-1.0, 1.0]:
		k.add_box(Vector3(0.1, 0.11, 0.07), MeshKit.xf(OnionModel.bulb_point(0.25, 78.0 * side, 0.07), Vector3(0, -78.0 * side, 0)), pal.dark)
	if d >= 1:
		for i in 7:
			k.add_sphere(0.017, MeshKit.xf(OnionModel.bulb_point(0.45 + 0.05 * i, OPEN_FRONT.x + 2.0, 0.055)), pal.light, 6, 3)
			k.add_sphere(0.017, MeshKit.xf(OnionModel.bulb_point(0.45 + 0.05 * i, OPEN_FRONT.y - 2.0, 0.055)), pal.light, 6, 3)
	if d >= 2:
		var cloak := PackedVector2Array([Vector2(0.45, 0.2), Vector2(0.43, 0.4), Vector2(0.38, 0.62), Vector2(0.27, 0.78)])
		cloth.add_lathe(MeshKit.smooth_profile(cloak, 3), Transform3D(), pal.main.lerp(pal.dark, 0.45), 16, 105.0, 255.0)
		_gem(k, acc, look, pal, OnionModel.bulb_point(0.3, 0.0, 0.105), 0.042)
	_glow_ring(acc, look, 0.4, 0.45, MeshKit.xf(Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1, 0.65, 1)))


## Cloth: a robe – flared skirt, open-front bodice with a collar, sash with tails; II adds a trimmed
## stole down the belly, III scalloped hem and a star gem.
static func _cloth_chest(k: MeshKit, cloth: MeshKit, acc: MeshKit, look: EquipLook, pal: Pal, d: int) -> void:
	var skirt := PackedVector2Array([Vector2(0.49, 0.065), Vector2(0.46, 0.14), Vector2(0.435, 0.22), Vector2(0.41, 0.3)])
	var robe := pal.main.lerp(pal.dark, 0.35)
	cloth.add_lathe(MeshKit.smooth_profile(skirt, 3), Transform3D(), robe, 24)
	cloth.add_lathe(PackedVector2Array([Vector2(0.492, 0.062), Vector2(0.488, 0.1)]), Transform3D(), pal.trim, 24)
	_shell(cloth, 0.3, 0.8, 0.03, robe, OPEN_FRONT.x, OPEN_FRONT.y)
	_shell(cloth, 0.76, 0.84, 0.045, pal.light, 90.0, 270.0)
	_edge_stripes(cloth, 0.3, 0.8, 0.04, pal.light)
	# Sash with two tails.
	k.add_torus(0.38, 0.425, MeshKit.xf(Vector3(0, 0.31, 0), Vector3.ZERO, Vector3(1, 0.8, 1)), pal.trim, 28, 5)
	var knot := OnionModel.bulb_point(0.3, -32.0, 0.06)
	k.add_sphere(0.045, MeshKit.xf(knot, Vector3.ZERO, Vector3(1.2, 1, 0.8)), pal.trim, 8, 4)
	for i in 2:
		var tail := PackedVector2Array([Vector2(-0.04, 0.0), Vector2(0.04, 0.0), Vector2(0.045, -0.2 - 0.05 * i),
			Vector2(0.0, -0.15 - 0.05 * i), Vector2(-0.045, -0.2 - 0.05 * i)])
		cloth.add_extrusion(tail, 0.02, MeshKit.xf(knot + Vector3(0.025 * (i * 2 - 1), -0.02, -0.01), Vector3(-8, -20.0 + 40.0 * i, 0)),
			pal.tint, 0.9)
	_tabard_back(cloth, pal)
	if d >= 1:
		var stole := PackedVector2Array()
		for q in OnionModel.bulb_profile():
			if q.y >= 0.08 and q.y <= 0.375:
				stole.append(Vector2(q.x + 0.1, q.y))
		cloth.add_lathe(stole, Transform3D(), pal.light, 8, -9.0, 9.0)
	if d >= 2:
		for i in 7:
			var a := -70.0 + 140.0 * i / 6.0
			var p0 := Vector3(sin(deg_to_rad(a)) * 0.49, 0.065, -cos(deg_to_rad(a)) * 0.49)
			cloth.add_extrusion(PackedVector2Array([Vector2(-0.06, 0.0), Vector2(0.06, 0.0), Vector2(0.0, -0.09)]), 0.012,
				Transform3D(_angled(a), p0), pal.trim, 0.9)
		_gem(k, acc, look, pal, OnionModel.bulb_point(0.31, 0.0, 0.09), 0.045)
	_glow_ring(acc, look, 0.385, 0.43, MeshKit.xf(Vector3(0, 0.31, 0), Vector3.ZERO, Vector3(1, 0.8, 1)))


# --- Class starter pieces ---------------------------------------------------------------

## The class's own look of one slot (the horned helm and huge pauldrons of the warrior, the pointy hat
## and cape of the mage ...) – shown while the slot is empty. Plain toon, nothing glows.
static func _build_starter(key: String, slot: int, cd: ClassData) -> Part:
	var p := Part.new()
	var solid := MeshKit.new()
	var cloth := MeshKit.new()
	match slot:
		EquipLook.Slot.HEAD:
			_starter_head(solid, cloth, cd)
			# Part flags per headgear. hunter_hat / tribal_mask (M8) keep the defaults (brows on,
			# sprout and mouth shown, no extras) until their class package changes them here.
			p.brows = cd.headgear not in [&"helm_horned", &"paladin_helm"]
			p.hides_sprout = cd.headgear == &"wizard_hat"
			p.hides_mouth = cd.headgear == &"hood"
			if cd.headgear == &"wizard_hat":
				p.extras = [&"hat_star"]
			elif cd.headgear == &"horned_hood":
				p.extras = [&"horn_flames"]
		EquipLook.Slot.SHOULDERS:
			_starter_shoulders(solid, cd)
		_:
			_starter_chest(solid, cloth, cd)
			if cd.headgear == &"horned_hood":
				p.extras = [&"fel_trim"]
	return _finish(p, key, solid, cloth, null)


static func _starter_head(k: MeshKit, cloth: MeshKit, cd: ClassData) -> void:
	var acc := cd.accent_color
	match cd.headgear:
		&"helm_horned":
			_helm_dome(k, acc, acc.darkened(0.35))
			for side: float in [-1.0, 1.0]:
				var horn := PackedVector3Array([Vector3(0.28 * side, 0.8, 0.02), Vector3(0.42 * side, 0.85, 0.0),
					Vector3(0.53 * side, 0.96, -0.03), Vector3(0.57 * side, 1.1, -0.06), Vector3(0.53 * side, 1.2, -0.08)])
				k.add_tube(horn, 0.08, 0.012, OnionModel.IVORY, 8)
				k.add_torus(0.06, 0.1, Transform3D(MeshKit.basis_from_y(Vector3(side, 0.35, 0)), Vector3(0.3 * side, 0.81, 0.02)), acc.darkened(0.35), 10, 4)
		&"paladin_helm":
			var silver := acc.lerp(Color(0.8, 0.82, 0.88), 0.35)
			_helm_dome(k, OnionModel.GOLD, silver)
			for side: float in [-1.0, 1.0]:
				_helm_wing(k, side, Vector3(0.3 * side, 0.74, 0.06))
				k.add_sphere(0.065, MeshKit.xf(Vector3(0.33 * side, 0.76, 0.03)), silver, 8, 4)
		&"wizard_hat":
			var hat := acc
			k.add_cylinder(0.5, 0.5, 0.035, MeshKit.xf(Vector3(0, 0.77, 0), Vector3(-6, 0, 0)), hat.darkened(0.15), 24)
			var cone := PackedVector3Array([Vector3(0, 0.77, 0.0), Vector3(0, 0.98, 0.04), Vector3(0, 1.16, 0.12),
				Vector3(0, 1.3, 0.25), Vector3(0, 1.36, 0.38)])
			k.add_tube(cone, 0.29, 0.02, hat, 16)
			k.add_torus(0.26, 0.32, MeshKit.xf(Vector3(0, 0.83, 0.006), Vector3(-6, 0, 0), Vector3(1, 1.4, 1)), OnionModel.GOLD, 24, 5)
		&"hood":
			# Open-topped leather cowl: the pale spring-onion neck and its long green stalk
			# stay visible from the top-down camera (GDD 13), pale trim on both edges.
			_hood_cap(k, acc, OnionModel.ROGUE_COWL_TOP)
			_cowl_trim(k, OnionModel.ROGUE_TRIM)
			_hood_sides(cloth, acc)
			# Dark domino mask across the eyes (GDD 13: "hood and mask"): the white eyes pop
			# out of it, so the rogue reads as a masked rogue, not as a dark blob.
			var mask := PackedVector2Array()
			for q in OnionModel.bulb_profile():
				if q.y >= OnionModel.EYE_Y - 0.085 and q.y <= OnionModel.EYE_Y + 0.075:
					mask.append(Vector2(q.x + 0.014, q.y))
			cloth.add_lathe(mask, Transform3D(), OnionModel.ROGUE_MASK, 18, -66.0, 66.0)
		&"horned_hood":
			var dark := OnionModel.WARLOCK_HOOD
			_hood_cap(k, dark)
			_hood_sides(cloth, dark)
			for side: float in [-1.0, 1.0]:
				var horn := warlock_horn(side)
				k.add_tube(horn, 0.07, 0.012, OnionModel.WARLOCK_HORN, 8)
				# Pale bone rim where the horn leaves the hood (reads against the dark hood).
				k.add_torus(0.055, 0.095, Transform3D(MeshKit.basis_from_y((horn[1] - horn[0]).normalized()), horn[0]),
					OnionModel.WARLOCK_HORN.lightened(0.25), 10, 4)
		&"hunter_hat":
			_head_hunter_hat(k, cloth, cd)
		&"tribal_mask":
			_head_tribal_mask(k, cloth, cd)
		_:
			# Any other id (a class whose look is not drawn yet): a plain circlet, never a bare head.
			_head_plain(k, cd)


## The default head piece (an unknown headgear id): a plain circlet in the accent colour around the
## head. It sits in the single "Solid" mesh (no extra draw call), leaves the face, brows and sprout
## alone and carries no extras.
static func _head_plain(k: MeshKit, cd: ClassData) -> void:
	var acc := cd.accent_color
	var y := 0.74
	var r := OnionModel.bulb_radius(y) + 0.02
	k.add_torus(r - 0.028, r + 0.028, MeshKit.xf(Vector3(0, y, 0)), acc.darkened(0.2), 28, 6)
	k.add_sphere(0.045, MeshKit.xf(OnionModel.bulb_point(y, 0.0, 0.035)), acc.lightened(0.25), 8, 4)


## HUNTER package hook: the feathered hunter hat (class headgear id hunter_hat). Until the class
## package draws it the plain circlet shows. Part flags (brows, sprout, extras) go in _build_starter.
static func _head_hunter_hat(k: MeshKit, _cloth: MeshKit, cd: ClassData) -> void:
	_head_plain(k, cd)


## The Shaman's head piece (class headgear id tribal_mask): a woven band with bone beads, a big carved wooden
## mask worn on the forehead (teal war paint, white eyes, bone fangs) and three feathers fanned out behind.
## All in the single Solid mesh. Part flags (brows, mouth, extras) go in _build_starter.
static func _head_tribal_mask(k: MeshKit, _cloth: MeshKit, cd: ClassData) -> void:
	var acc := cd.accent_color
	var wood := Color(0.56, 0.38, 0.22)
	var dark := Color(0.27, 0.16, 0.1)
	var bone := OnionModel.IVORY
	# Band around the head, bone beads on it.
	var by := 0.78
	var br := OnionModel.bulb_radius(by)
	k.add_torus(br + 0.0, br + 0.06, MeshKit.xf(Vector3(0, by, 0)), dark, 26, 5)
	for i in 12:
		var a := 360.0 * float(i) / 12.0 + 15.0
		k.add_sphere(0.032, MeshKit.xf(OnionModel.bulb_point(by, a, 0.062)), bone, 8, 4)
	# The mask: a carved plate lying on the forehead, tilted up with the bulb.
	var centre := OnionModel.bulb_point(0.865, 0.0, 0.05)
	var tilt := MeshKit.xf(centre, Vector3(46.0, 0.0, 0.0))
	var outline := PackedVector2Array([Vector2(-0.16, 0.13), Vector2(-0.12, 0.17), Vector2(0.12, 0.17), Vector2(0.16, 0.13),
		Vector2(0.15, 0.0), Vector2(0.1, -0.11), Vector2(0.0, -0.16), Vector2(-0.1, -0.11), Vector2(-0.15, 0.0)])
	k.add_extrusion(outline, 0.045, tilt, wood, 0.9)
	# Relief on the plate (local x across, y up, z -0.03 = towards the viewer).
	var front := Vector3(0, 0, -0.03)
	var relief := func(size: Vector3, at: Vector3, color: Color) -> void:
		k.add_box(size, tilt * Transform3D(Basis(), front + at), color)
	relief.call(Vector3(0.28, 0.035, 0.025), Vector3(0.0, 0.115, 0.0), acc)
	relief.call(Vector3(0.2, 0.02, 0.025), Vector3(0.0, 0.085, 0.0), acc.darkened(0.3))
	for side: float in [-1.0, 1.0]:
		relief.call(Vector3(0.075, 0.04, 0.028), Vector3(0.062 * side, 0.035, 0.0), dark)
		relief.call(Vector3(0.045, 0.022, 0.03), Vector3(0.062 * side, 0.035, 0.004), Color(0.98, 0.98, 0.96))
		relief.call(Vector3(0.02, 0.07, 0.025), Vector3(0.105 * side, -0.05, 0.0), acc)
		relief.call(Vector3(0.022, 0.05, 0.03), Vector3(0.04 * side, -0.115, 0.0), bone)
	relief.call(Vector3(0.035, 0.11, 0.035), Vector3(0.0, -0.0, 0.0), wood.darkened(0.2))
	relief.call(Vector3(0.1, 0.03, 0.028), Vector3(0.0, -0.085, 0.0), dark)
	# Three feathers fanned out behind the head.
	var leaf := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.05, 0.08), Vector2(0.045, 0.2), Vector2(0.0, 0.32),
		Vector2(-0.045, 0.2), Vector2(-0.05, 0.08)])
	var feathers := [[150.0, 38.0, acc], [180.0, 28.0, Color(0.96, 0.94, 0.98)], [210.0, 38.0, acc.lightened(0.2)]]
	for f in feathers:
		var angle: float = f[0]
		var lean: float = f[1]
		var basis := _angled(angle) * Basis.from_euler(Vector3(deg_to_rad(-lean), 0, 0))
		k.add_extrusion(leaf, 0.014, Transform3D(basis, OnionModel.bulb_point(0.82, angle, 0.04)), f[2] as Color, 0.9)


static func _starter_shoulders(k: MeshKit, cd: ClassData) -> void:
	if not cd.big_shoulders:
		return
	var acc := cd.accent_color
	var main := acc if cd.headgear != &"paladin_helm" else Color(0.96, 0.96, 0.93)
	var trim := acc.darkened(0.4) if cd.headgear != &"paladin_helm" else OnionModel.GOLD
	for side: float in [-1.0, 1.0]:
		var b := Basis.from_euler(Vector3(0, 0, deg_to_rad(-48.0 * side)))
		var c := Vector3(0.33 * side, 0.6, 0.03)
		k.add_sphere(0.22, Transform3D(b * Basis.from_scale(Vector3(1.05, 1.0, 1.0)), c), main, 16, 8, true)
		k.add_torus(0.19, 0.25, Transform3D(b * Basis.from_scale(Vector3(1.05, 0.6, 1.0)), c), trim, 18, 5)
		k.add_sphere(0.16, Transform3D(b * Basis.from_scale(Vector3(1.0, 0.75, 0.95)), c + b * Vector3(0, 0.08, 0)), main.lightened(0.08), 14, 7, true)
		if cd.headgear == &"helm_horned":
			for s in 3:
				var dir := b * Vector3((s - 1) * 0.45, 1.0, 0).normalized()
				var base := c + b * Vector3((s - 1) * 0.09, 0.17, 0)
				k.add_segment(base, base + dir * 0.17, 0.045, 0.0, OnionModel.IVORY, 8)
		elif cd.headgear == &"tribal_mask":
			# A bone fang on each pauldron.
			k.add_segment(c + b * Vector3(0, 0.17, 0), c + b * Vector3(0, 0.36, 0), 0.05, 0.0, OnionModel.IVORY, 8)
		else:
			k.add_sphere(0.05, Transform3D(b, c + b * Vector3(0, 0.2, 0)), Color(0.3, 0.6, 1.0), 8, 4)


static func _starter_chest(k: MeshKit, cloth: MeshKit, cd: ClassData) -> void:
	var acc := cd.accent_color
	match cd.headgear:
		&"helm_horned":
			_belt(k, OnionModel.LEATHER, acc)
		&"paladin_helm":
			_belt(k, OnionModel.GOLD, Color(0.9, 0.2, 0.15))
			var tabard := PackedVector2Array([Vector2(0.43, 0.07), Vector2(0.415, 0.18), Vector2(0.395, 0.28)])
			cloth.add_lathe(tabard, Transform3D(), OnionModel.TABARD_BLUE, 6, -30.0, 30.0)
			var trim := PackedVector2Array([Vector2(0.435, 0.055), Vector2(0.433, 0.075)])
			cloth.add_lathe(trim, Transform3D(), OnionModel.GOLD, 6, -30.0, 30.0)
		&"wizard_hat":
			_belt(k, OnionModel.GOLD, acc)
			_cape(cloth, acc.darkened(0.1))
		&"hood":
			_belt(k, OnionModel.LEATHER, Color(0.7, 0.7, 0.72))
			k.add_box(Vector3(0.12, 0.12, 0.08), MeshKit.xf(OnionModel.bulb_point(0.25, 125.0, 0.04), Vector3(0, 125, 0)), OnionModel.LEATHER.darkened(0.2))
			var strap := Transform3D(Basis.from_euler(Vector3(0, 0, deg_to_rad(32))) * Basis.from_scale(Vector3(1, 0.55, 1)), Vector3(0, 0.45, 0))
			k.add_torus(0.385, 0.425, strap, OnionModel.LEATHER.darkened(0.1), 28, 4)
			# Crimson scarf: a band along the hood's lower edge and two tails flapping behind,
			# so the rogue reads from behind / above too.
			var band := PackedVector2Array()
			for q in OnionModel.bulb_profile():
				if q.y >= 0.4 and q.y <= 0.5:
					band.append(Vector2(q.x * 1.1 + 0.035, q.y + 0.03))
			k.add_lathe(band, Transform3D(), OnionModel.SCARF_RED, 22, 54.0, 306.0)
			var knot := OnionModel.bulb_point(0.47, 180.0, 0.06)
			k.add_sphere(0.055, MeshKit.xf(knot, Vector3.ZERO, Vector3(1.3, 0.9, 0.8)), OnionModel.SCARF_RED.darkened(0.1), 8, 4)
			for i in 2:
				var side := -1.0 if i == 0 else 1.0
				var length := 0.34 if i == 0 else 0.27
				var ribbon := PackedVector2Array([Vector2(-0.045, 0.0), Vector2(0.045, 0.0), Vector2(0.04, length),
					Vector2(0.0, length - 0.06), Vector2(-0.04, length)])
				k.add_extrusion(ribbon, 0.022, MeshKit.xf(knot + Vector3(0.03 * side, -0.01, 0.0),
					Vector3(112.0 + 10.0 * i, 18.0 * side, 0.0)), OnionModel.SCARF_RED.darkened(0.06 * i), 0.9)
		&"horned_hood":
			var dark := OnionModel.WARLOCK_HOOD
			_belt(k, dark.lightened(0.1), acc)
			_cape(cloth, OnionModel.WARLOCK_HOOD.lightened(0.06))
		&"hunter_hat":
			_chest_hunter(k, cloth, cd)
		&"tribal_mask":
			_chest_tribal(k, cloth, cd)
		_:
			_belt(k, OnionModel.LEATHER, OnionModel.GOLD)


## HUNTER package hook: the starter chest (fur trim, quiver strap). The default leather belt until then.
static func _chest_hunter(k: MeshKit, _cloth: MeshKit, _cd: ClassData) -> void:
	_belt(k, OnionModel.LEATHER, OnionModel.GOLD)


## The Shaman's starter chest: a dark leather belt with a teal buckle, a ring of bone beads on it and three
## strands of beads hanging down each side. (The small totem on the back is part of the body, not of this slot:
## OnionModel._back_totem_mesh.)
static func _chest_tribal(k: MeshKit, _cloth: MeshKit, cd: ClassData) -> void:
	_belt(k, OnionModel.LEATHER.darkened(0.12), cd.accent_color)
	var bone := OnionModel.IVORY
	for i in 16:
		var a := 360.0 * float(i) / 16.0 + 11.0
		k.add_sphere(0.027, MeshKit.xf(OnionModel.bulb_point(0.33, a, 0.045)), bone, 7, 4)
	for side: float in [-1.0, 1.0]:
		for strand in 3:
			var a := side * (34.0 + 24.0 * strand)
			var top := OnionModel.bulb_point(0.3, a, 0.055)
			var tip := OnionModel.bulb_point(0.16 - 0.015 * strand, a, 0.05)
			k.add_segment(top, tip, 0.007, 0.007, OnionModel.LEATHER.darkened(0.2), 5)
			for b in 3:
				var at := top.lerp(tip, 0.3 + 0.35 * float(b))
				k.add_sphere(0.03 if b < 2 else 0.036, MeshKit.xf(at), bone if b < 2 else cd.accent_color.lightened(0.15), 7, 4)


static func _helm_dome(k: MeshKit, metal: Color, trim: Color) -> void:
	k.add_sphere(0.36, MeshKit.xf(Vector3(0, 0.665, 0), Vector3.ZERO, Vector3(1.0, 0.98, 1.0)), metal, 24, 10, true)
	k.add_torus(0.33, 0.4, MeshKit.xf(Vector3(0, 0.68, 0), Vector3.ZERO, Vector3(1, 0.75, 1)), trim, 28, 6)
	var crest := PackedVector2Array()
	for i in 13:
		var a := PI * i / 12.0
		crest.append(Vector2(cos(a), sin(a)) * 0.375)
	k.add_extrusion(crest, 0.05, MeshKit.xf(Vector3(0, 0.67, 0), Vector3(0, 90, 0)), trim)
	for i in 10:
		var a := TAU * i / 10.0
		k.add_sphere(0.022, MeshKit.xf(Vector3(sin(a) * 0.392, 0.69, cos(a) * 0.392)), trim.lightened(0.3), 6, 3)


## One swept-back feathered wing on the paladin helm (white feathers, golden root).
static func _helm_wing(k: MeshKit, side: float, root: Vector3) -> void:
	# Outline in (outwards, up) with a scalloped trailing edge.
	var pts: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.03, 0.13), Vector2(0.11, 0.28), Vector2(0.23, 0.39),
		Vector2(0.38, 0.46), Vector2(0.36, 0.34), Vector2(0.3, 0.35), Vector2(0.29, 0.23), Vector2(0.22, 0.25),
		Vector2(0.2, 0.13), Vector2(0.13, 0.15), Vector2(0.1, 0.04), Vector2(0.04, 0.02)]
	var wing := PackedVector2Array()
	for p in pts:
		wing.append(Vector2(p.x * side, p.y))
	var xform := MeshKit.xf(root, Vector3(0, -34.0 * side, 0))
	k.add_extrusion(wing, 0.035, xform, Color(0.98, 0.97, 0.94), 0.92)
	var base := PackedVector2Array()
	for p: Vector2 in [Vector2(-0.03, -0.03), Vector2(0.03, 0.13), Vector2(0.11, 0.2), Vector2(0.13, 0.1), Vector2(0.07, 0.0)]:
		base.append(Vector2(p.x * side, p.y))
	k.add_extrusion(base, 0.06, xform, OnionModel.GOLD, 0.9)


static func _belt(k: MeshKit, belt: Color, buckle: Color) -> void:
	k.add_torus(0.365, 0.41, MeshKit.xf(Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1, 0.65, 1)), belt, 28, 5)
	k.add_box(Vector3(0.1, 0.08, 0.04), MeshKit.xf(OnionModel.bulb_point(0.3, 0.0, 0.035)), buckle)


## Hood over the top of the bulb. [param top] < the neck height leaves the top open (cowl,
## no pointed tip).
static func _hood_cap(k: MeshKit, color: Color, top: float = 2.0) -> void:
	var prof := PackedVector2Array()
	for p in OnionModel.bulb_profile():
		if p.y >= 0.66 and p.y <= top:
			prof.append(Vector2(p.x * 1.1 + 0.02, p.y + 0.03))
	k.add_lathe(prof, Transform3D(), color, 28)
	if top < 1.0:
		return
	var tip := PackedVector3Array([Vector3(0, 0.98, 0.04), Vector3(0, 1.05, 0.14), Vector3(0, 1.02, 0.27),
		Vector3(0, 0.95, 0.33)])
	k.add_tube(tip, 0.075, 0.015, color, 8)


## Pale trim rings on the rogue cowl: its open top and its lower (brow) edge.
static func _cowl_trim(k: MeshKit, color: Color) -> void:
	var top_r := OnionModel.bulb_radius(OnionModel.ROGUE_COWL_TOP) * 1.1 + 0.02
	k.add_torus(top_r - 0.022, top_r + 0.018, MeshKit.xf(Vector3(0, OnionModel.ROGUE_COWL_TOP + 0.03, 0)), color, 22, 4)
	var low_r := OnionModel.bulb_radius(0.68) * 1.1 + 0.02
	k.add_torus(low_r - 0.02, low_r + 0.02, MeshKit.xf(Vector3(0, 0.71, 0)), color, 26, 4)


## Centre line of a warlock horn (root on the hood, curling backwards).
static func warlock_horn(side: float) -> PackedVector3Array:
	return PackedVector3Array([Vector3(0.26 * side, 0.86, 0.04), Vector3(0.4 * side, 0.95, 0.1),
		Vector3(0.47 * side, 1.07, 0.2), Vector3(0.43 * side, 1.14, 0.33), Vector3(0.35 * side, 1.1, 0.4)])


static func _cape(k: MeshKit, color: Color) -> void:
	var cape := PackedVector2Array([Vector2(0.5, 0.06), Vector2(0.46, 0.25), Vector2(0.44, 0.45),
		Vector2(0.38, 0.6), Vector2(0.27, 0.72)])
	k.add_lathe(MeshKit.smooth_profile(cape, 3), Transform3D(), color, 18, 70.0, 290.0)


static func _hood_sides(k: MeshKit, color: Color) -> void:
	var prof := PackedVector2Array()
	for p in OnionModel.bulb_profile():
		if p.y >= 0.4 and p.y <= 0.72:
			prof.append(Vector2(p.x * 1.1 + 0.02, p.y + 0.03))
	k.add_lathe(prof, Transform3D(), color, 18, 58.0, 302.0)
