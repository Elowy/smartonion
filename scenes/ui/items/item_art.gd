class_name ItemArt
extends RefCounted
## Procedural item silhouettes drawn in code (no image assets yet), used by ItemIcon:
## one shape per Items.SlotType (helm / hood, amulet, pauldrons, breastplate / robe, bracer,
## gauntlet, belt, legguards, boot, ring, trinket) and one per weapon_type (sword, axe, mace,
## dagger, bow, gun, wand, staff, shield, tome, two_hand_sword, two_hand_mace, orb, crossbow, polearm,
## fist_weapon). Armour is coloured by its material (cloth,
## leather, mail, plate), gems by the item's rarity. Empty equipment slots use the same shapes
## as flat, faint silhouettes. Shapes are authored in a unit square (y down).

const OUTLINE := Color(0.06, 0.04, 0.03)
const GOLD := Color(0.95, 0.74, 0.3)
const BRONZE := Color(0.72, 0.5, 0.26)
const STEEL := Color(0.8, 0.82, 0.88)
const WOOD := Color(0.56, 0.36, 0.19)
const GRIP := Color(0.33, 0.2, 0.11)
const PAPER := Color(0.93, 0.87, 0.7)
## Common items carry a plain quartz gem instead of a white one.
const COMMON_GEM := Color(0.66, 0.74, 0.82)

## Main material colour per ClassData.ArmorType (cloth, leather, mail, plate).
const ARMOR_COLORS: Array[Color] = [
	Color(0.5, 0.38, 0.72), Color(0.6, 0.39, 0.22), Color(0.56, 0.6, 0.66), Color(0.8, 0.82, 0.88),
]

## Shape id per Items.SlotType (weapons use their weapon_type instead).
const SLOT_SHAPES := {
	Items.SlotType.HEAD: &"head", Items.SlotType.NECK: &"neck",
	Items.SlotType.SHOULDERS: &"shoulders", Items.SlotType.CHEST: &"chest",
	Items.SlotType.WRIST: &"wrist", Items.SlotType.HANDS: &"hands",
	Items.SlotType.WAIST: &"waist", Items.SlotType.LEGS: &"legs",
	Items.SlotType.FEET: &"feet", Items.SlotType.RING: &"ring",
	Items.SlotType.TRINKET: &"trinket", Items.SlotType.WEAPON: &"sword",
}
## Faint placeholder shape per empty equipment position (Items.EquipSlot).
const EMPTY_SHAPES := {
	Items.EquipSlot.HEAD: &"head", Items.EquipSlot.NECK: &"neck",
	Items.EquipSlot.SHOULDERS: &"shoulders", Items.EquipSlot.CHEST: &"chest",
	Items.EquipSlot.WRIST: &"wrist", Items.EquipSlot.HANDS: &"hands",
	Items.EquipSlot.WAIST: &"waist", Items.EquipSlot.LEGS: &"legs",
	Items.EquipSlot.FEET: &"feet", Items.EquipSlot.RING_1: &"ring",
	Items.EquipSlot.RING_2: &"ring", Items.EquipSlot.TRINKET_1: &"trinket",
	Items.EquipSlot.TRINKET_2: &"trinket", Items.EquipSlot.MAIN_HAND: &"sword",
	Items.EquipSlot.OFF_HAND: &"shield",
}
## Every weapon_type with its own silhouette.
const WEAPON_SHAPES: Array[StringName] = [
	&"sword", &"axe", &"mace", &"dagger", &"bow", &"gun", &"wand", &"staff", &"shield", &"tome",
	&"two_hand_sword", &"two_hand_mace", &"orb", &"crossbow", &"polearm", &"fist_weapon",
]


## Colours one silhouette is painted with.
class Palette:
	var main := STEEL
	var trim := GOLD
	var gem := COMMON_GEM
	var wood := WOOD
	var grip := GRIP
	var armor_type := Items.NO_ARMOR


## Unit-square drawing helper: unit -> pixel mapping, outlined / shaded primitives and a
## "flat" mode that paints everything in one colour (empty-slot silhouettes).
class Pen:
	var ci: CanvasItem
	var origin := Vector2.ZERO
	var k := 64.0
	var w := 1.5
	var flat := false
	var flat_color := Color.WHITE

	func p(v: Vector2) -> Vector2:
		return origin + v * k

	func pts(arr: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for v: Vector2 in arr:
			out.append(p(v))
		return out

	func c(col: Color) -> Color:
		return flat_color if flat else col

	## Filled polygon with a soft top-lit gradient and a dark outline.
	func poly(arr: Array, col: Color, outline: bool = true, shade: float = 0.28) -> void:
		var pp := pts(arr)
		if pp.size() < 3:
			return
		if flat:
			ci.draw_colored_polygon(pp, flat_color)
			return
		var y0 := INF
		var y1 := -INF
		for v in pp:
			y0 = minf(y0, v.y)
			y1 = maxf(y1, v.y)
		var span := maxf(1.0, y1 - y0)
		var cols := PackedColorArray()
		for v in pp:
			var t := (v.y - y0) / span
			cols.append(col.lightened(shade * (1.0 - t)).lerp(col.darkened(shade), t * t))
		ci.draw_polygon(pp, cols)
		if outline:
			var closed := PackedVector2Array(pp)
			closed.append(pp[0])
			ci.draw_polyline(closed, OUTLINE, w, true)

	## Thick rounded stroke (hafts, fingers, chains) with an outline.
	func capsule(a: Vector2, b: Vector2, r: float, col: Color, outline: bool = true) -> void:
		var pa := p(a)
		var pb := p(b)
		var rr := r * k
		if outline and not flat:
			ci.draw_line(pa, pb, OUTLINE, rr * 2.0 + w * 2.0, true)
			ci.draw_circle(pa, rr + w, OUTLINE)
			ci.draw_circle(pb, rr + w, OUTLINE)
		var fill := c(col)
		ci.draw_line(pa, pb, fill, rr * 2.0, true)
		ci.draw_circle(pa, rr, fill)
		ci.draw_circle(pb, rr, fill)
		if not flat and rr > 2.0:
			var n := (pb - pa).normalized().orthogonal() * rr * 0.45
			ci.draw_line(pa - n, pb - n, Color(1, 1, 1, 0.22), maxf(1.0, rr * 0.45), true)

	func circle(center: Vector2, r: float, col: Color, outline: bool = true) -> void:
		var pc := p(center)
		if outline and not flat:
			ci.draw_circle(pc, r * k + w, OUTLINE)
		ci.draw_circle(pc, r * k, c(col))

	## A faceted gem: rarity colour with a highlight (and a soft glow for bright colours).
	func gem(center: Vector2, r: float, col: Color, glow: bool = false) -> void:
		var pc := p(center)
		if flat:
			ci.draw_circle(pc, r * k, flat_color)
			return
		if glow:
			for i in 4:
				ci.draw_circle(pc, r * k * (2.1 - i * 0.28), Color(col, 0.07 + i * 0.03))
		ci.draw_circle(pc, r * k + w, OUTLINE)
		ci.draw_circle(pc, r * k, col.darkened(0.35))
		ci.draw_circle(pc + Vector2(-0.12, -0.12) * r * k, r * k * 0.72, col)
		ci.draw_circle(pc + Vector2(-0.35, -0.35) * r * k, r * k * 0.24, Color(1, 1, 1, 0.85))

	func line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
		if flat:
			return
		ci.draw_line(p(a), p(b), col, maxf(1.0, width * k), true)

	func dot(center: Vector2, r: float, col: Color) -> void:
		if flat:
			return
		ci.draw_circle(p(center), maxf(0.8, r * k), col)

	## Point at distance [param a] along axis [param u] and [param b] across it from [param o].
	static func along(o: Vector2, u: Vector2, a: float, b: float) -> Vector2:
		return o + u * a + u.orthogonal() * b


# --- Public API --------------------------------------------------------------------------

## Draws [param item]'s silhouette into [param rect] of [param ci].
static func draw_item(ci: CanvasItem, rect: Rect2, item: ItemInstance) -> void:
	if item == null:
		return
	draw_shape(ci, rect, shape_for(item), palette_for(item))


## Faint flat silhouette of an empty equipment position (Items.EquipSlot).
static func draw_empty_slot(ci: CanvasItem, rect: Rect2, equip_slot: int, color: Color) -> void:
	var shape: StringName = EMPTY_SHAPES.get(equip_slot, &"trinket")
	draw_shape(ci, rect, shape, Palette.new(), true, color)


## Shape id for [param item]: its weapon_type for weapons, else the slot's shape.
static func shape_for(item: ItemInstance) -> StringName:
	if item.is_weapon():
		var t := item.weapon.weapon_type
		if t in WEAPON_SHAPES:
			return t
		match item.weapon.hand:
			WeaponData.Hand.OFF_HAND:
				return &"shield"
			WeaponData.Hand.TWO_HAND:
				return &"axe"
		return &"sword"
	if item.slot_type == Items.SlotType.HEAD and item.armor_type == ClassData.ArmorType.CLOTH:
		return &"hood"
	return SLOT_SHAPES.get(item.slot_type, &"trinket")


static func palette_for(item: ItemInstance) -> Palette:
	var pal := Palette.new()
	var rarity := clampi(item.rarity, 0, UiTheme.RARITY_COLORS.size() - 1)
	pal.gem = COMMON_GEM if rarity == 0 else UiTheme.RARITY_COLORS[rarity]
	pal.trim = BRONZE if rarity <= Items.Rarity.UNCOMMON else GOLD
	pal.armor_type = item.armor_type
	if item.is_weapon():
		pal.main = STEEL.lerp(item.weapon.color, 0.35) if item.weapon.color.a > 0.0 else STEEL
		if rarity >= Items.Rarity.EPIC:
			pal.main = pal.main.lerp(pal.gem.lightened(0.4), 0.18)
	elif item.armor_type >= 0 and item.armor_type < ARMOR_COLORS.size():
		pal.main = ARMOR_COLORS[item.armor_type]
		if item.armor_type == ClassData.ArmorType.LEATHER:
			pal.trim = Color(0.36, 0.22, 0.12) if rarity <= Items.Rarity.UNCOMMON else GOLD
	else:
		pal.main = GOLD if rarity >= Items.Rarity.RARE else Color(0.82, 0.68, 0.42)
		pal.trim = GOLD.darkened(0.25)
	return pal


## Draws shape [param shape] into the square centred in [param rect] (with a small margin).
## [param flat] paints a one-colour silhouette in [param flat_color].
static func draw_shape(ci: CanvasItem, rect: Rect2, shape: StringName, pal: Palette,
		flat: bool = false, flat_color: Color = Color.WHITE) -> void:
	var side := minf(rect.size.x, rect.size.y)
	var pen := Pen.new()
	pen.ci = ci
	pen.k = side
	pen.origin = rect.position + (rect.size - Vector2(side, side)) * 0.5
	pen.w = clampf(side * 0.035, 1.0, 2.5)
	pen.flat = flat
	pen.flat_color = flat_color
	match shape:
		&"head": _helm(pen, pal)
		&"hood": _hood(pen, pal)
		&"neck": _amulet(pen, pal)
		&"shoulders": _pauldrons(pen, pal)
		&"chest": _chest(pen, pal)
		&"wrist": _bracer(pen, pal)
		&"hands": _glove(pen, pal)
		&"waist": _belt(pen, pal)
		&"legs": _legs(pen, pal)
		&"feet": _boot(pen, pal)
		&"ring": _ring(pen, pal)
		&"trinket": _trinket(pen, pal)
		&"sword": _sword(pen, pal, 1.0)
		&"dagger": _sword(pen, pal, 0.68)
		&"axe": _axe(pen, pal)
		&"mace": _mace(pen, pal)
		&"bow": _bow(pen, pal)
		&"gun": _gun(pen, pal)
		&"wand": _wand(pen, pal)
		&"staff": _staff(pen, pal)
		&"shield": _shield(pen, pal)
		&"tome": _tome(pen, pal)
		&"two_hand_sword": _greatsword(pen, pal)
		&"two_hand_mace": _maul(pen, pal)
		&"orb": _orb(pen, pal)
		&"crossbow": _crossbow(pen, pal)
		&"polearm": _polearm(pen, pal)
		&"fist_weapon": _fist(pen, pal)
		_: _trinket(pen, pal)


# --- Helpers -----------------------------------------------------------------------------

static func _arc(center: Vector2, radii: Vector2, from_deg: float, to_deg: float, steps: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in steps + 1:
		var a := deg_to_rad(lerpf(from_deg, to_deg, float(i) / steps))
		out.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return out


## Material detail on armour: chain rings (mail), stitches (leather), rivets (plate).
static func _material_marks(pen: Pen, pal: Palette, points: Array) -> void:
	match pal.armor_type:
		ClassData.ArmorType.MAIL:
			for v: Vector2 in points:
				pen.dot(v, 0.018, Color(0.25, 0.27, 0.3, 0.8))
		ClassData.ArmorType.LEATHER:
			for v: Vector2 in points:
				pen.line(v, v + Vector2(0.03, 0.0), Color(0.95, 0.8, 0.55, 0.75), 0.012)
		ClassData.ArmorType.PLATE:
			for v: Vector2 in points:
				pen.dot(v, 0.016, pal.trim.lightened(0.3))


static func _grid(x0: float, x1: float, y0: float, y1: float, step: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var y := y0
	var row := 0
	while y <= y1:
		var x := x0 + (step * 0.5 if row % 2 == 1 else 0.0)
		while x <= x1:
			out.append(Vector2(x, y))
			x += step
		y += step * 0.8
		row += 1
	return out


# --- Armour --------------------------------------------------------------------------------

static func _helm(pen: Pen, pal: Palette) -> void:
	var shape: Array = _arc(Vector2(0.5, 0.56), Vector2(0.34, 0.42), 180.0, 360.0, 14)
	shape.append_array([Vector2(0.84, 0.82), Vector2(0.72, 0.92), Vector2(0.62, 0.92), Vector2(0.6, 0.64),
		Vector2(0.4, 0.64), Vector2(0.38, 0.92), Vector2(0.28, 0.92), Vector2(0.16, 0.82)])
	pen.poly(shape, pen.c(pal.main))
	# Eye slit and nose guard.
	pen.poly([Vector2(0.26, 0.5), Vector2(0.74, 0.5), Vector2(0.72, 0.57), Vector2(0.28, 0.57)], pen.c(OUTLINE.lightened(0.08)), false)
	pen.poly([Vector2(0.46, 0.44), Vector2(0.54, 0.44), Vector2(0.53, 0.8), Vector2(0.47, 0.8)], pen.c(pal.trim))
	# Brow band and crest.
	pen.line(Vector2(0.17, 0.44), Vector2(0.83, 0.44), pal.trim, 0.045)
	if pal.armor_type == ClassData.ArmorType.PLATE:
		pen.line(Vector2(0.5, 0.15), Vector2(0.5, 0.42), pal.trim.lightened(0.15), 0.05)
		pen.poly([Vector2(0.14, 0.42), Vector2(0.03, 0.2), Vector2(0.22, 0.32)], pen.c(Color(0.95, 0.9, 0.78)))
		pen.poly([Vector2(0.86, 0.42), Vector2(0.97, 0.2), Vector2(0.78, 0.32)], pen.c(Color(0.95, 0.9, 0.78)))
	_material_marks(pen, pal, _grid(0.28, 0.72, 0.24, 0.38, 0.09) if pal.armor_type == ClassData.ArmorType.MAIL
		else [Vector2(0.22, 0.7), Vector2(0.78, 0.7)])
	pen.line(Vector2(0.3, 0.26), Vector2(0.42, 0.19), Color(1, 1, 1, 0.45), 0.03)


static func _hood(pen: Pen, pal: Palette) -> void:
	pen.poly([Vector2(0.5, 0.06), Vector2(0.66, 0.2), Vector2(0.8, 0.46), Vector2(0.88, 0.92),
		Vector2(0.12, 0.92), Vector2(0.2, 0.46), Vector2(0.34, 0.2)], pen.c(pal.main))
	var face: Array = _arc(Vector2(0.5, 0.6), Vector2(0.2, 0.24), 0.0, 360.0, 18)
	face.pop_back()
	pen.poly(face, pen.c(Color(0.08, 0.06, 0.09)), false, 0.0)
	pen.line(Vector2(0.3, 0.44), Vector2(0.5, 0.33), pal.trim, 0.04)
	pen.line(Vector2(0.5, 0.33), Vector2(0.7, 0.44), pal.trim, 0.04)
	pen.line(Vector2(0.14, 0.88), Vector2(0.86, 0.88), pal.trim, 0.05)
	# Glowing eyes in the dark.
	pen.dot(Vector2(0.43, 0.6), 0.03, Color(pal.gem, 0.9))
	pen.dot(Vector2(0.57, 0.6), 0.03, Color(pal.gem, 0.9))


static func _amulet(pen: Pen, pal: Palette) -> void:
	var chain := _arc(Vector2(0.5, 0.1), Vector2(0.3, 0.5), 0.0, 180.0, 16)
	for i in chain.size():
		var v := chain[i]
		if v.y > 0.52 and absf(v.x - 0.5) < 0.12:
			continue
		pen.circle(v, 0.028, pal.trim.lightened(0.1) if i % 2 == 0 else pal.trim)
	pen.poly([Vector2(0.5, 0.52), Vector2(0.66, 0.66), Vector2(0.5, 0.94), Vector2(0.34, 0.66)], pen.c(pal.trim))
	pen.gem(Vector2(0.5, 0.69), 0.1, pal.gem, true)


static func _pauldrons(pen: Pen, pal: Palette) -> void:
	for cx: float in [0.29, 0.71]:
		var shape: Array = _arc(Vector2(cx, 0.6), Vector2(0.25, 0.36), 180.0, 360.0, 12)
		shape.append_array([Vector2(cx + 0.25, 0.68), Vector2(cx, 0.76), Vector2(cx - 0.25, 0.68)])
		if pal.armor_type == ClassData.ArmorType.PLATE:
			pen.poly([Vector2(cx - 0.06, 0.3), Vector2(cx, 0.08), Vector2(cx + 0.06, 0.3)], pen.c(pal.trim.lightened(0.2)))
		pen.poly(shape, pen.c(pal.main))
		pen.line(Vector2(cx - 0.24, 0.66), Vector2(cx, 0.73), pal.trim, 0.05)
		pen.line(Vector2(cx, 0.73), Vector2(cx + 0.24, 0.66), pal.trim, 0.05)
		pen.line(Vector2(cx - 0.12, 0.36), Vector2(cx - 0.02, 0.3), Color(1, 1, 1, 0.4), 0.03)
		_material_marks(pen, pal, [Vector2(cx - 0.14, 0.52), Vector2(cx, 0.46), Vector2(cx + 0.14, 0.52)])


static func _chest(pen: Pen, pal: Palette) -> void:
	var robe := pal.armor_type == ClassData.ArmorType.CLOTH
	var bottom := 0.95 if robe else 0.9
	var hem := 0.12 if robe else 0.0
	pen.poly([Vector2(0.38, 0.1), Vector2(0.5, 0.24), Vector2(0.62, 0.1), Vector2(0.86, 0.18),
		Vector2(0.94, 0.42), Vector2(0.77, 0.47), Vector2(0.75 + hem, bottom), Vector2(0.5, bottom + 0.02),
		Vector2(0.25 - hem, bottom), Vector2(0.23, 0.47), Vector2(0.06, 0.42), Vector2(0.14, 0.18)], pen.c(pal.main))
	pen.line(Vector2(0.5, 0.25), Vector2(0.5, bottom - 0.02), Color(0, 0, 0, 0.3), 0.025)
	if robe:
		pen.line(Vector2(0.5, 0.26), Vector2(0.5, bottom - 0.02), pal.trim, 0.06)
		pen.line(Vector2(0.24, 0.6), Vector2(0.76, 0.6), pal.trim, 0.05)
	else:
		pen.line(Vector2(0.24, 0.68), Vector2(0.76, 0.68), pal.trim, 0.055)
		pen.dot(Vector2(0.5, 0.68), 0.04, pal.trim.lightened(0.3))
		if pal.armor_type == ClassData.ArmorType.PLATE:
			for side: float in [-1.0, 1.0]:
				var arc: Array = _arc(Vector2(0.5 + side * 0.13, 0.38), Vector2(0.12, 0.1), 20.0, 160.0, 8)
				for i in arc.size() - 1:
					pen.line(arc[i], arc[i + 1], Color(0, 0, 0, 0.35), 0.02)
	pen.line(Vector2(0.38, 0.11), Vector2(0.5, 0.25), pal.trim, 0.035)
	pen.line(Vector2(0.5, 0.25), Vector2(0.62, 0.11), pal.trim, 0.035)
	_material_marks(pen, pal, _grid(0.3, 0.7, 0.32, 0.56, 0.1) if pal.armor_type == ClassData.ArmorType.MAIL
		else [Vector2(0.3, 0.3), Vector2(0.7, 0.3), Vector2(0.3, 0.8), Vector2(0.7, 0.8)])


static func _bracer(pen: Pen, pal: Palette) -> void:
	# A forearm guard lying diagonally: narrow wrist end bottom-left, flared elbow end top-right.
	var o := Vector2(0.2, 0.8)
	var u := DIAG
	var shape: Array = [Pen.along(o, u, 0.0, -0.13), Pen.along(o, u, 0.0, 0.13)]
	for i in 7:
		var t := float(i) / 6.0
		shape.append(Pen.along(o, u, 0.84 + sin(t * PI) * 0.06, lerpf(0.21, -0.21, t)))
	pen.poly(shape, pen.c(pal.main), true, 0.22)
	for a: float in [0.16, 0.62]:
		var hw := lerpf(0.13, 0.21, a / 0.84) + 0.01
		pen.poly([Pen.along(o, u, a - 0.04, -hw), Pen.along(o, u, a + 0.04, -hw), Pen.along(o, u, a + 0.04, hw),
			Pen.along(o, u, a - 0.04, hw)], pen.c(pal.trim))
	pen.line(Pen.along(o, u, 0.06, -0.08), Pen.along(o, u, 0.8, -0.13), Color(1, 1, 1, 0.4), 0.025)
	pen.gem(Pen.along(o, u, 0.39, 0.0), 0.065, pal.gem)
	_material_marks(pen, pal, [Pen.along(o, u, 0.3, 0.1), Pen.along(o, u, 0.5, 0.12), Pen.along(o, u, 0.3, -0.1),
		Pen.along(o, u, 0.5, -0.12)])


static func _glove(pen: Pen, pal: Palette) -> void:
	var fingers: Array[Vector2] = [Vector2(0.36, 0.2), Vector2(0.47, 0.13), Vector2(0.58, 0.15), Vector2(0.68, 0.24)]
	for i in fingers.size():
		pen.capsule(fingers[i], Vector2(fingers[i].x - 0.01 + i * 0.005, 0.5), 0.052, pal.main)
	pen.capsule(Vector2(0.18, 0.4), Vector2(0.33, 0.6), 0.058, pal.main)
	pen.poly([Vector2(0.29, 0.42), Vector2(0.74, 0.42), Vector2(0.72, 0.68), Vector2(0.32, 0.68)], pen.c(pal.main), true, 0.18)
	pen.poly([Vector2(0.26, 0.66), Vector2(0.76, 0.66), Vector2(0.82, 0.92), Vector2(0.2, 0.92)], pen.c(pal.trim))
	pen.line(Vector2(0.24, 0.78), Vector2(0.78, 0.78), Color(0, 0, 0, 0.3), 0.025)
	_material_marks(pen, pal, [Vector2(0.42, 0.55), Vector2(0.52, 0.55), Vector2(0.62, 0.55)])


static func _belt(pen: Pen, pal: Palette) -> void:
	var band: Array = []
	for i in 9:
		var t := float(i) / 8.0
		band.append(Vector2(lerpf(0.04, 0.96, t), 0.34 + sin(t * PI) * 0.08))
	for i in 9:
		var t := 1.0 - float(i) / 8.0
		band.append(Vector2(lerpf(0.04, 0.96, t), 0.58 + sin(t * PI) * 0.08))
	pen.poly(band, pen.c(pal.main if pal.armor_type != ClassData.ArmorType.PLATE else pal.main.darkened(0.1)), true, 0.2)
	pen.line(Vector2(0.06, 0.4), Vector2(0.3, 0.44), Color(1, 1, 1, 0.3), 0.02)
	_material_marks(pen, pal, [Vector2(0.14, 0.47), Vector2(0.24, 0.5), Vector2(0.76, 0.5), Vector2(0.86, 0.47)])
	# Hanging strap end, then the big buckle.
	pen.poly([Vector2(0.62, 0.6), Vector2(0.7, 0.6), Vector2(0.72, 0.9), Vector2(0.64, 0.92)], pen.c(pal.main.darkened(0.15)))
	pen.poly([Vector2(0.35, 0.28), Vector2(0.65, 0.28), Vector2(0.65, 0.76), Vector2(0.35, 0.76)], pen.c(pal.trim))
	pen.poly([Vector2(0.42, 0.37), Vector2(0.58, 0.37), Vector2(0.58, 0.67), Vector2(0.42, 0.67)], pen.c(OUTLINE.lightened(0.1)), false)
	pen.line(Vector2(0.5, 0.4), Vector2(0.5, 0.64), pal.trim.lightened(0.2), 0.03)
	pen.gem(Vector2(0.5, 0.52), 0.045, pal.gem)


static func _legs(pen: Pen, pal: Palette) -> void:
	pen.poly([Vector2(0.24, 0.1), Vector2(0.76, 0.1), Vector2(0.82, 0.9), Vector2(0.58, 0.92),
		Vector2(0.5, 0.42), Vector2(0.42, 0.92), Vector2(0.18, 0.9)], pen.c(pal.main))
	pen.poly([Vector2(0.23, 0.08), Vector2(0.77, 0.08), Vector2(0.78, 0.2), Vector2(0.22, 0.2)], pen.c(pal.trim))
	if pal.armor_type == ClassData.ArmorType.PLATE or pal.armor_type == ClassData.ArmorType.MAIL:
		pen.circle(Vector2(0.32, 0.6), 0.075, pal.trim)
		pen.circle(Vector2(0.68, 0.6), 0.075, pal.trim)
	else:
		pen.line(Vector2(0.3, 0.3), Vector2(0.28, 0.86), Color(0, 0, 0, 0.25), 0.02)
		pen.line(Vector2(0.7, 0.3), Vector2(0.72, 0.86), Color(0, 0, 0, 0.25), 0.02)
	_material_marks(pen, pal, [Vector2(0.3, 0.4), Vector2(0.7, 0.4), Vector2(0.3, 0.78), Vector2(0.7, 0.78)])


static func _boot(pen: Pen, pal: Palette) -> void:
	pen.poly([Vector2(0.28, 0.1), Vector2(0.62, 0.1), Vector2(0.62, 0.56), Vector2(0.84, 0.66),
		Vector2(0.92, 0.8), Vector2(0.9, 0.9), Vector2(0.22, 0.9), Vector2(0.24, 0.62)], pen.c(pal.main))
	pen.poly([Vector2(0.21, 0.86), Vector2(0.92, 0.86), Vector2(0.9, 0.94), Vector2(0.2, 0.94)], pen.c(Color(0.2, 0.13, 0.08)), false)
	pen.poly([Vector2(0.25, 0.06), Vector2(0.65, 0.06), Vector2(0.66, 0.2), Vector2(0.24, 0.2)], pen.c(pal.trim))
	pen.line(Vector2(0.62, 0.58), Vector2(0.4, 0.62), Color(0, 0, 0, 0.3), 0.025)
	if pal.armor_type == ClassData.ArmorType.PLATE:
		pen.poly([Vector2(0.62, 0.6), Vector2(0.82, 0.68), Vector2(0.86, 0.8), Vector2(0.62, 0.8)], pen.c(pal.main.lightened(0.15)))
	_material_marks(pen, pal, [Vector2(0.36, 0.32), Vector2(0.5, 0.32), Vector2(0.36, 0.46), Vector2(0.5, 0.46)])


# --- Jewellery ------------------------------------------------------------------------------

static func _ring(pen: Pen, pal: Palette) -> void:
	var center := pen.p(Vector2(0.5, 0.62))
	var r := 0.25 * pen.k
	var band := 0.1 * pen.k
	if pen.flat:
		pen.ci.draw_arc(center, r, 0.0, TAU, 32, pen.flat_color, band, true)
	else:
		pen.ci.draw_arc(center, r, 0.0, TAU, 32, OUTLINE, band + pen.w * 2.0, true)
		pen.ci.draw_arc(center, r, 0.0, TAU, 32, pal.main.darkened(0.25), band, true)
		pen.ci.draw_arc(center, r + band * 0.12, PI * 1.05, PI * 1.95, 16, pal.main.lightened(0.25), band * 0.5, true)
	pen.poly([Vector2(0.36, 0.38), Vector2(0.64, 0.38), Vector2(0.58, 0.26), Vector2(0.42, 0.26)], pen.c(pal.main))
	pen.gem(Vector2(0.5, 0.24), 0.12, pal.gem, true)


static func _trinket(pen: Pen, pal: Palette) -> void:
	pen.poly([Vector2(0.34, 0.92), Vector2(0.66, 0.92), Vector2(0.6, 0.78), Vector2(0.4, 0.78)], pen.c(pal.trim))
	for side: float in [-1.0, 0.0, 1.0]:
		pen.capsule(Vector2(0.5 + side * 0.08, 0.8), Vector2(0.5 + side * 0.25, 0.5 - absf(side) * 0.02), 0.03, pal.trim)
	pen.gem(Vector2(0.5, 0.44), 0.25, pal.gem, true)
	if not pen.flat:
		# Rune star inside the orb.
		var c := Vector2(0.5, 0.46)
		for i in 4:
			var a := TAU * i / 4.0 + PI * 0.25
			pen.line(c, c + Vector2(cos(a), sin(a)) * 0.12, Color(1, 1, 1, 0.55), 0.02)


# --- Weapons (diagonal, hilt bottom-left, like WoW icons) ------------------------------------

const DIAG := Vector2(0.70710678, -0.70710678)


static func _sword(pen: Pen, pal: Palette, length: float) -> void:
	var o := Vector2(0.16, 0.84) if length >= 1.0 else Vector2(0.24, 0.76)
	var u := DIAG
	var guard := 0.22
	var tip := 0.96 * length
	var hw := 0.085 if length >= 1.0 else 0.1
	pen.capsule(Pen.along(o, u, 0.03, 0.0), Pen.along(o, u, guard, 0.0), 0.05, pal.grip)
	pen.circle(Pen.along(o, u, 0.02, 0.0), 0.065, pal.trim)
	pen.poly([Pen.along(o, u, guard, -hw), Pen.along(o, u, tip - 0.14 * length, -hw),
		Pen.along(o, u, tip, 0.0), Pen.along(o, u, tip - 0.14 * length, hw), Pen.along(o, u, guard, hw)], pen.c(pal.main), true, 0.2)
	pen.line(Pen.along(o, u, guard + 0.04, 0.0), Pen.along(o, u, tip - 0.16 * length, 0.0), Color(0, 0, 0, 0.3), 0.022)
	pen.line(Pen.along(o, u, guard + 0.04, -hw * 0.55), Pen.along(o, u, tip - 0.18 * length, -hw * 0.55), Color(1, 1, 1, 0.5), 0.015)
	pen.poly([Pen.along(o, u, guard - 0.04, -0.19), Pen.along(o, u, guard + 0.04, -0.19),
		Pen.along(o, u, guard + 0.04, 0.19), Pen.along(o, u, guard - 0.04, 0.19)], pen.c(pal.trim))
	pen.gem(Pen.along(o, u, guard, 0.0), 0.035, pal.gem)


## The two-handed sword: the sword with a longer grip, a broader blade and a wider guard.
static func _greatsword(pen: Pen, pal: Palette) -> void:
	var o := Vector2(0.1, 0.9)
	var u := DIAG
	var guard := 0.3
	var tip := 1.04
	var hw := 0.105
	pen.capsule(Pen.along(o, u, 0.03, 0.0), Pen.along(o, u, guard, 0.0), 0.05, pal.grip)
	pen.circle(Pen.along(o, u, 0.02, 0.0), 0.07, pal.trim)
	pen.capsule(Pen.along(o, u, 0.17, -0.06), Pen.along(o, u, 0.17, 0.06), 0.028, pal.trim)
	pen.poly([Pen.along(o, u, guard, -hw), Pen.along(o, u, tip - 0.16, -hw),
		Pen.along(o, u, tip, 0.0), Pen.along(o, u, tip - 0.16, hw), Pen.along(o, u, guard, hw)], pen.c(pal.main), true, 0.2)
	pen.line(Pen.along(o, u, guard + 0.04, 0.0), Pen.along(o, u, tip - 0.18, 0.0), Color(0, 0, 0, 0.3), 0.026)
	pen.line(Pen.along(o, u, guard + 0.04, -hw * 0.55), Pen.along(o, u, tip - 0.2, -hw * 0.55), Color(1, 1, 1, 0.5), 0.015)
	pen.poly([Pen.along(o, u, guard - 0.045, -0.24), Pen.along(o, u, guard + 0.045, -0.24),
		Pen.along(o, u, guard + 0.045, 0.24), Pen.along(o, u, guard - 0.045, 0.24)], pen.c(pal.trim))
	pen.gem(Pen.along(o, u, guard, 0.0), 0.04, pal.gem)


static func _axe(pen: Pen, pal: Palette) -> void:
	var o := Vector2(0.14, 0.86)
	var u := DIAG
	pen.capsule(Pen.along(o, u, 0.0, 0.0), Pen.along(o, u, 0.98, 0.0), 0.046, pal.wood)
	pen.capsule(Pen.along(o, u, 0.04, 0.0), Pen.along(o, u, 0.24, 0.0), 0.044, pal.grip)
	var blade: Array = [Pen.along(o, u, 0.62, 0.03)]
	for i in 9:
		var a := lerpf(-70.0, 70.0, i / 8.0)
		blade.append(Pen.along(o, u, 0.76 + sin(deg_to_rad(a)) * 0.2, 0.18 + cos(deg_to_rad(a)) * 0.2))
	blade.append(Pen.along(o, u, 0.9, 0.03))
	pen.poly(blade, pen.c(pal.main), true, 0.2)
	pen.line(Pen.along(o, u, 0.62, 0.32), Pen.along(o, u, 0.9, 0.32), Color(1, 1, 1, 0.5), 0.02)
	pen.poly([Pen.along(o, u, 0.7, -0.03), Pen.along(o, u, 0.76, -0.17), Pen.along(o, u, 0.82, -0.03)], pen.c(pal.main.darkened(0.1)))
	pen.poly([Pen.along(o, u, 0.66, -0.05), Pen.along(o, u, 0.86, -0.05), Pen.along(o, u, 0.86, 0.05),
		Pen.along(o, u, 0.66, 0.05)], pen.c(pal.trim))
	pen.gem(Pen.along(o, u, 0.76, 0.0), 0.03, pal.gem)


static func _mace(pen: Pen, pal: Palette) -> void:
	var o := Vector2(0.18, 0.82)
	var u := DIAG
	pen.capsule(Pen.along(o, u, 0.0, 0.0), Pen.along(o, u, 0.66, 0.0), 0.046, pal.wood)
	pen.capsule(Pen.along(o, u, 0.03, 0.0), Pen.along(o, u, 0.22, 0.0), 0.045, pal.grip)
	var head := Pen.along(o, u, 0.76, 0.0)
	for i in 8:
		var a := TAU * i / 8.0
		var d := Vector2(cos(a), sin(a))
		pen.poly([head + d.orthogonal() * 0.06, head + d * 0.25, head - d.orthogonal() * 0.06], pen.c(pal.main.darkened(0.08)))
	pen.circle(head, 0.15, pal.main)
	pen.dot(head + Vector2(-0.05, -0.05), 0.04, Color(1, 1, 1, 0.5))
	pen.capsule(Pen.along(o, u, 0.6, -0.07), Pen.along(o, u, 0.6, 0.07), 0.03, pal.trim)
	pen.gem(head, 0.05, pal.gem)


## The two-handed mace (a maul): a long haft and a heavy block head with iron caps.
static func _maul(pen: Pen, pal: Palette) -> void:
	var o := Vector2(0.12, 0.88)
	var u := DIAG
	pen.capsule(Pen.along(o, u, 0.0, 0.0), Pen.along(o, u, 0.96, 0.0), 0.046, pal.wood)
	pen.capsule(Pen.along(o, u, 0.03, 0.0), Pen.along(o, u, 0.26, 0.0), 0.045, pal.grip)
	pen.capsule(Pen.along(o, u, 0.5, -0.07), Pen.along(o, u, 0.5, 0.07), 0.03, pal.trim)
	pen.poly([Pen.along(o, u, 0.68, -0.18), Pen.along(o, u, 0.94, -0.18), Pen.along(o, u, 0.94, 0.18),
		Pen.along(o, u, 0.68, 0.18)], pen.c(pal.main), true, 0.2)
	for a: float in [0.66, 0.92]:
		pen.poly([Pen.along(o, u, a - 0.025, -0.2), Pen.along(o, u, a + 0.025, -0.2),
			Pen.along(o, u, a + 0.025, 0.2), Pen.along(o, u, a - 0.025, 0.2)], pen.c(pal.trim))
	pen.dot(Pen.along(o, u, 0.76, -0.1), 0.035, Color(1, 1, 1, 0.45))
	pen.gem(Pen.along(o, u, 0.8, 0.0), 0.045, pal.gem)


static func _bow(pen: Pen, pal: Palette) -> void:
	var top := Vector2(0.66, 0.08)
	var bottom := Vector2(0.66, 0.92)
	var limb: Array[Vector2] = []
	for i in 13:
		var t := i / 12.0
		var x := 0.66 - sin(t * PI) * 0.44
		limb.append(Vector2(x, lerpf(top.y, bottom.y, t)))
	if not pen.flat:
		pen.line(top, bottom, Color(0.95, 0.92, 0.82), 0.014)
	for i in limb.size() - 1:
		pen.capsule(limb[i], limb[i + 1], 0.034 if i in [5, 6] else 0.028, pal.wood, true)
	for i in limb.size() - 1:
		pen.line(limb[i], limb[i + 1], pal.wood.lightened(0.15), 0.03)
	pen.capsule(limb[5], limb[7], 0.042, pal.grip)
	pen.circle(top, 0.035, pal.trim)
	pen.circle(bottom, 0.035, pal.trim)
	# Nocked arrow.
	pen.capsule(Vector2(0.12, 0.5), Vector2(0.86, 0.5), 0.014, pal.wood.lightened(0.2))
	pen.poly([Vector2(0.84, 0.44), Vector2(0.96, 0.5), Vector2(0.84, 0.56)], pen.c(pal.main))
	pen.poly([Vector2(0.62, 0.5), Vector2(0.56, 0.42), Vector2(0.66, 0.42)], pen.c(pal.gem), false)
	pen.poly([Vector2(0.62, 0.5), Vector2(0.56, 0.58), Vector2(0.66, 0.58)], pen.c(pal.gem), false)


static func _gun(pen: Pen, pal: Palette) -> void:
	var o := Vector2(0.1, 0.78)
	var u := Vector2(0.94, -0.34).normalized()
	pen.poly([Pen.along(o, u, 0.0, -0.02), Pen.along(o, u, 0.44, -0.04), Pen.along(o, u, 0.44, 0.06),
		Pen.along(o, u, 0.2, 0.08), Pen.along(o, u, 0.04, 0.2), Pen.along(o, u, -0.04, 0.16)], pen.c(pal.wood))
	pen.poly([Pen.along(o, u, 0.36, -0.06), Pen.along(o, u, 0.86, -0.05), Pen.along(o, u, 0.95, -0.09),
		Pen.along(o, u, 0.97, 0.05), Pen.along(o, u, 0.86, 0.02), Pen.along(o, u, 0.36, 0.04)], pen.c(pal.main), true, 0.22)
	pen.line(Pen.along(o, u, 0.4, -0.035), Pen.along(o, u, 0.86, -0.03), Color(1, 1, 1, 0.45), 0.014)
	for a: float in [0.52, 0.74]:
		pen.poly([Pen.along(o, u, a - 0.02, -0.07), Pen.along(o, u, a + 0.02, -0.07), Pen.along(o, u, a + 0.02, 0.05),
			Pen.along(o, u, a - 0.02, 0.05)], pen.c(pal.trim), false)
	pen.capsule(Pen.along(o, u, 0.36, -0.06), Pen.along(o, u, 0.33, -0.15), 0.022, pal.main.darkened(0.2))
	var guard_c := pen.p(Pen.along(o, u, 0.32, 0.09))
	if not pen.flat:
		pen.ci.draw_arc(guard_c, 0.06 * pen.k, 0.0, PI, 10, OUTLINE, maxf(1.5, 0.03 * pen.k), true)
	pen.gem(Pen.along(o, u, 0.24, 0.05), 0.03, pal.gem)


## The crossbow: a stock with a pistol grip, a wide bowed prod across the front, a drawn string and a
## bolt on the rail (hilt bottom-left, the bolt points to the top right).
static func _crossbow(pen: Pen, pal: Palette) -> void:
	var o := Vector2(0.14, 0.86)
	var u := DIAG
	pen.poly([Pen.along(o, u, 0.0, 0.045), Pen.along(o, u, 0.74, 0.045), Pen.along(o, u, 0.74, -0.045),
		Pen.along(o, u, 0.32, -0.045), Pen.along(o, u, 0.3, -0.17), Pen.along(o, u, 0.18, -0.17),
		Pen.along(o, u, 0.16, -0.045), Pen.along(o, u, 0.0, -0.045)], pen.c(pal.wood))
	var limb: Array[Vector2] = []
	for i in 9:
		var t := lerpf(-1.0, 1.0, i / 8.0)
		limb.append(Pen.along(o, u, 0.58 + 0.12 * t * t, t * 0.34))
	if not pen.flat:
		pen.line(limb[0], Pen.along(o, u, 0.34, 0.0), Color(0.95, 0.92, 0.82), 0.014)
		pen.line(limb[8], Pen.along(o, u, 0.34, 0.0), Color(0.95, 0.92, 0.82), 0.014)
	for i in limb.size() - 1:
		pen.capsule(limb[i], limb[i + 1], 0.036 if i in [3, 4] else 0.03, pal.wood.darkened(0.1))
	pen.circle(limb[0], 0.03, pal.trim)
	pen.circle(limb[8], 0.03, pal.trim)
	pen.capsule(Pen.along(o, u, 0.58, -0.05), Pen.along(o, u, 0.58, 0.05), 0.035, pal.trim)
	# The bolt on its rail: shaft, steel head, fletching.
	pen.capsule(Pen.along(o, u, 0.3, 0.0), Pen.along(o, u, 0.88, 0.0), 0.016, pal.wood.lightened(0.2))
	pen.poly([Pen.along(o, u, 1.0, 0.0), Pen.along(o, u, 0.86, 0.055), Pen.along(o, u, 0.86, -0.055)], pen.c(pal.main), true, 0.2)
	pen.poly([Pen.along(o, u, 0.3, 0.0), Pen.along(o, u, 0.24, 0.05), Pen.along(o, u, 0.36, 0.05)], pen.c(pal.gem), false)
	pen.poly([Pen.along(o, u, 0.3, 0.0), Pen.along(o, u, 0.24, -0.05), Pen.along(o, u, 0.36, -0.05)], pen.c(pal.gem), false)
	pen.gem(Pen.along(o, u, 0.46, 0.0), 0.032, pal.gem)


## The polearm: the longest haft of the weapons, a leaf-shaped head with one wing, an iron collar and a
## small pennant.
static func _polearm(pen: Pen, pal: Palette) -> void:
	var o := Vector2(0.08, 0.94)
	var u := DIAG
	pen.capsule(Pen.along(o, u, 0.0, 0.0), Pen.along(o, u, 0.9, 0.0), 0.036, pal.wood)
	pen.capsule(Pen.along(o, u, 0.14, 0.0), Pen.along(o, u, 0.42, 0.0), 0.04, pal.grip)
	pen.circle(Pen.along(o, u, 0.0, 0.0), 0.05, pal.trim)
	pen.poly([Pen.along(o, u, 0.62, 0.0), Pen.along(o, u, 0.78, -0.2), Pen.along(o, u, 0.72, 0.0)], pen.c(pal.trim.darkened(0.1)))
	pen.poly([Pen.along(o, u, 0.9, 0.05), Pen.along(o, u, 0.88, 0.2), Pen.along(o, u, 1.0, 0.22), Pen.along(o, u, 1.06, 0.08)],
			pen.c(pal.main.darkened(0.08)), true, 0.2)
	pen.poly([Pen.along(o, u, 1.22, 0.0), Pen.along(o, u, 1.12, 0.07), Pen.along(o, u, 0.99, 0.09), Pen.along(o, u, 0.88, 0.05),
		Pen.along(o, u, 0.88, -0.05), Pen.along(o, u, 0.99, -0.09), Pen.along(o, u, 1.12, -0.07)], pen.c(pal.main), true, 0.2)
	pen.line(Pen.along(o, u, 0.92, 0.0), Pen.along(o, u, 1.14, 0.0), Color(0, 0, 0, 0.3), 0.02)
	pen.capsule(Pen.along(o, u, 0.87, -0.065), Pen.along(o, u, 0.87, 0.065), 0.026, pal.trim)
	pen.gem(Pen.along(o, u, 0.87, 0.0), 0.03, pal.gem)


## The fist weapon: a knuckle plate over a grip bar, three claw spikes with bone tips and a wrist strap.
static func _fist(pen: Pen, pal: Palette) -> void:
	var o := Vector2(0.2, 0.8)
	var u := DIAG
	pen.capsule(Pen.along(o, u, -0.04, -0.2), Pen.along(o, u, -0.04, 0.2), 0.05, pal.grip)
	pen.capsule(Pen.along(o, u, 0.12, -0.2), Pen.along(o, u, 0.12, 0.2), 0.035, pal.grip.lightened(0.1))
	for b: float in [-0.15, 0.0, 0.15]:
		pen.poly([Pen.along(o, u, 0.4, b - 0.065), Pen.along(o, u, 0.72, b * 1.35), Pen.along(o, u, 0.4, b + 0.065)],
				pen.c(pal.main), true, 0.2)
		pen.poly([Pen.along(o, u, 0.6, b * 1.25 - 0.026), Pen.along(o, u, 0.72, b * 1.35), Pen.along(o, u, 0.6, b * 1.25 + 0.026)],
				pen.c(PAPER), false)
	var plate: Array = []
	for i in 9:
		var a := PI * i / 8.0
		plate.append(Pen.along(o, u, 0.2 + sin(a) * 0.2, cos(a) * 0.3))
	pen.poly(plate, pen.c(pal.main.darkened(0.12)), true, 0.25)
	pen.line(Pen.along(o, u, 0.24, -0.2), Pen.along(o, u, 0.36, -0.16), Color(1, 1, 1, 0.45), 0.02)
	pen.gem(Pen.along(o, u, 0.26, 0.0), 0.04, pal.gem)


static func _wand(pen: Pen, pal: Palette) -> void:
	var o := Vector2(0.18, 0.82)
	var u := DIAG
	pen.capsule(Pen.along(o, u, 0.0, 0.0), Pen.along(o, u, 0.7, 0.0), 0.04, Color(0.9, 0.85, 0.72))
	for a: float in [0.08, 0.22, 0.6]:
		pen.capsule(Pen.along(o, u, a, -0.045), Pen.along(o, u, a, 0.045), 0.02, pal.trim)
	var tip := Pen.along(o, u, 0.8, 0.0)
	if not pen.flat:
		for i in 4:
			pen.ci.draw_circle(pen.p(tip), pen.k * (0.2 - i * 0.035), Color(pal.gem, 0.08 + i * 0.05))
	var star: Array = []
	for i in 8:
		var a := TAU * i / 8.0 - PI * 0.5
		var r := 0.15 if i % 2 == 0 else 0.055
		star.append(tip + Vector2(cos(a), sin(a)) * r)
	pen.poly(star, pen.c(pal.gem.lightened(0.25)), true, 0.15)
	pen.dot(tip, 0.03, Color(1, 1, 1, 0.9))


static func _staff(pen: Pen, pal: Palette) -> void:
	var o := Vector2(0.12, 0.9)
	var u := DIAG
	pen.capsule(Pen.along(o, u, 0.0, 0.0), Pen.along(o, u, 0.84, 0.0), 0.046, pal.wood)
	pen.capsule(Pen.along(o, u, 0.36, 0.0), Pen.along(o, u, 0.5, 0.0), 0.042, pal.grip)
	var head := Pen.along(o, u, 0.97, 0.0)
	var cp := pen.p(head)
	if not pen.flat:
		pen.ci.draw_arc(cp, 0.13 * pen.k, 0.0, TAU, 24, OUTLINE, 0.06 * pen.k + pen.w * 2.0, true)
		pen.ci.draw_arc(cp, 0.13 * pen.k, 0.0, TAU, 24, pal.trim, 0.06 * pen.k, true)
	else:
		pen.ci.draw_arc(cp, 0.13 * pen.k, 0.0, TAU, 24, pen.flat_color, 0.06 * pen.k, true)
	pen.gem(head, 0.085, pal.gem, true)
	for b: float in [-1.0, 1.0]:
		pen.capsule(Pen.along(o, u, 0.84, b * 0.03), Pen.along(o, u, 0.88, b * 0.12), 0.02, pal.trim)


static func _shield(pen: Pen, pal: Palette) -> void:
	var outer: Array = [Vector2(0.14, 0.12), Vector2(0.5, 0.07), Vector2(0.86, 0.12), Vector2(0.86, 0.46),
		Vector2(0.78, 0.66), Vector2(0.64, 0.82), Vector2(0.5, 0.94), Vector2(0.36, 0.82), Vector2(0.22, 0.66),
		Vector2(0.14, 0.46)]
	pen.poly(outer, pen.c(pal.trim))
	var inner: Array = []
	for v: Vector2 in outer:
		inner.append(Vector2(0.5, 0.48) + (v - Vector2(0.5, 0.48)) * 0.82)
	pen.poly(inner, pen.c(pal.main.darkened(0.12)), false, 0.2)
	# Heraldic band and boss.
	pen.poly([Vector2(0.44, 0.15), Vector2(0.56, 0.15), Vector2(0.56, 0.84), Vector2(0.5, 0.88), Vector2(0.44, 0.84)],
		pen.c(Color(0.2, 0.3, 0.6) if pal.gem == COMMON_GEM else pal.gem.darkened(0.25)), false)
	pen.circle(Vector2(0.5, 0.44), 0.11, pal.trim)
	pen.gem(Vector2(0.5, 0.44), 0.06, pal.gem)
	pen.line(Vector2(0.24, 0.2), Vector2(0.4, 0.16), Color(1, 1, 1, 0.4), 0.025)


## The orb: a glowing sphere in a three-pronged golden cradle.
static func _orb(pen: Pen, pal: Palette) -> void:
	var core := Vector2(0.5, 0.42)
	pen.poly([Vector2(0.36, 0.86), Vector2(0.64, 0.86), Vector2(0.58, 0.74), Vector2(0.42, 0.74)], pen.c(pal.trim))
	pen.capsule(Vector2(0.5, 0.74), Vector2(0.5, 0.66), 0.05, pal.grip)
	pen.circle(core, 0.27, pal.main.darkened(0.2))
	pen.gem(core, 0.22, pal.gem, true)
	pen.dot(core + Vector2(-0.08, -0.09), 0.05, Color(1, 1, 1, 0.55))
	for side: float in [-1.0, 1.0]:
		pen.capsule(Vector2(0.5 + side * 0.12, 0.72), Vector2(0.5 + side * 0.3, 0.46), 0.022, pal.trim)
		pen.capsule(Vector2(0.5 + side * 0.3, 0.46), Vector2(0.5 + side * 0.22, 0.2), 0.022, pal.trim)


static func _tome(pen: Pen, pal: Palette) -> void:
	pen.poly([Vector2(0.24, 0.16), Vector2(0.82, 0.12), Vector2(0.84, 0.86), Vector2(0.26, 0.9)], pen.c(PAPER), true, 0.1)
	pen.poly([Vector2(0.18, 0.12), Vector2(0.76, 0.1), Vector2(0.78, 0.84), Vector2(0.2, 0.86)],
		pen.c(Color(0.45, 0.16, 0.14) if pal.gem == COMMON_GEM else pal.gem.darkened(0.45)), true, 0.18)
	pen.poly([Vector2(0.18, 0.12), Vector2(0.26, 0.12), Vector2(0.28, 0.86), Vector2(0.2, 0.86)], pen.c(Color(0.2, 0.08, 0.06)), false)
	for v: Vector2 in [Vector2(0.72, 0.15), Vector2(0.74, 0.8)]:
		pen.poly([v + Vector2(-0.06, -0.04), v + Vector2(0.05, -0.05), v + Vector2(0.05, 0.05)], pen.c(pal.trim), false)
	pen.circle(Vector2(0.5, 0.47), 0.13, pal.trim)
	pen.gem(Vector2(0.5, 0.47), 0.08, pal.gem, true)
	pen.poly([Vector2(0.74, 0.42), Vector2(0.86, 0.42), Vector2(0.86, 0.52), Vector2(0.74, 0.52)], pen.c(pal.trim))
