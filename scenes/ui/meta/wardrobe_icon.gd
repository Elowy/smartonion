class_name WardrobeIcon
extends RefCounted
## Draws the little pictures of the Wardrobe grid (M9 WARDROBE): an item look as the silhouette of its piece in the colours of its
## armour (material tier, rarity trim, the set's kit), a Tabard / Hat / Glow / Dye as a swatch of what it is, and the "nothing
## chosen" cells. All plain 2D drawing on a [CanvasItem] (call it from its _draw), no textures: [method draw_cell].

const CELL_BACK := Color(0.1, 0.088, 0.078, 0.96)
const CELL_BACK_SELECTED := Color(0.21, 0.175, 0.105, 0.98)
const CELL_BORDER := Color(0.24, 0.2, 0.15)
const LOCKED_TINT := Color(0.18, 0.17, 0.17)
const MARK_COLOR := Color(0.55, 1.0, 0.5)


## One grid cell: the frame, the picture of [param entry] in [param rect], a lock when it is not owned. [param selected]: the
## cursor is on it ([param focused]: the grid has the focus, else the frame is dimmer); [param marked]: it is the current choice
## (a green tick in the corner).
static func draw_cell(ci: CanvasItem, rect: Rect2, entry: WardrobeEntry, selected: bool, focused: bool, marked: bool) -> void:
	var back := CELL_BACK_SELECTED if selected else CELL_BACK
	ci.draw_rect(rect, back, true)
	var border := CELL_BORDER
	var border_width := 1.0
	if entry.kind == WardrobeEntry.Kind.LOOK and entry.look != null and entry.owned:
		border = WeaponModel.rarity_color(entry.look.rarity).darkened(0.35)
	if selected:
		border = UiTheme.GOLD if focused else UiTheme.GOLD_DARK
		border_width = 3.0 if focused else 2.0
	ci.draw_rect(rect, border, false, border_width)
	var area := rect.grow(-rect.size.x * 0.12)
	match entry.kind:
		WardrobeEntry.Kind.NONE:
			_draw_none(ci, area, entry)
		WardrobeEntry.Kind.LOOK:
			_draw_look(ci, area, entry.look, not entry.owned)
		_:
			_draw_cosmetic(ci, area, entry.cosmetic, not entry.owned)
	if not entry.owned:
		_draw_lock(ci, Rect2(rect.position + Vector2(rect.size.x - 24.0, rect.size.y - 26.0), Vector2(18, 20)))
	if marked:
		_draw_tick(ci, Rect2(rect.position + Vector2(4, 4), Vector2(18, 18)))
	if entry.kind == WardrobeEntry.Kind.LOOK and entry.look != null:
		_draw_corner_mark(ci, rect, entry)


# --- Looks ----------------------------------------------------------------------------------

## The silhouette of [param look] in [param area]: head / shoulders / chest per armour family, tier pips under it.
static func _draw_look(ci: CanvasItem, area: Rect2, look: EquipLook, locked: bool) -> void:
	if look == null:
		return
	var pal := OnionArmor.palette(look)
	var main := pal.main
	var dark := pal.dark
	var light := pal.light
	var trim := pal.trim
	if locked:
		main = LOCKED_TINT.lightened(0.04)
		dark = LOCKED_TINT.darkened(0.3)
		light = LOCKED_TINT.lightened(0.16)
		trim = LOCKED_TINT.lightened(0.25)
	var c := area.get_center() + Vector2(0, -area.size.y * 0.06)
	var s := minf(area.size.x, area.size.y) * 0.5
	var at := func(p: Vector2) -> Vector2: return c + p * s
	match look.slot:
		EquipLook.Slot.HEAD:
			_head(ci, at, look.armor, main, dark, light, trim)
		EquipLook.Slot.SHOULDERS:
			_shoulders(ci, at, look.armor, main, dark, light, trim)
		_:
			_chest(ci, at, look.armor, main, dark, light, trim)
	# Tier pips (material detail 1..3).
	var tier := look.detail()
	for i in tier + 1:
		var p := Vector2(area.get_center().x + (float(i) - float(tier) * 0.5) * 9.0, area.end.y - 1.0)
		ci.draw_circle(p, 3.0, trim if not locked else dark)


static func _poly(ci: CanvasItem, at: Callable, pts: Array, color: Color) -> void:
	var out := PackedVector2Array()
	for p: Vector2 in pts:
		out.append(at.call(p) as Vector2)
	ci.draw_colored_polygon(out, color)


static func _line(ci: CanvasItem, at: Callable, a: Vector2, b: Vector2, color: Color, width: float) -> void:
	ci.draw_line(at.call(a) as Vector2, at.call(b) as Vector2, color, width, true)


static func _ellipse(ci: CanvasItem, at: Callable, centre: Vector2, radii: Vector2, color: Color, steps: int = 20) -> void:
	var pts: Array = []
	for i in steps:
		var a := TAU * float(i) / float(steps)
		pts.append(centre + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	_poly(ci, at, pts, color)


static func _head(ci: CanvasItem, at: Callable, armor: int, main: Color, dark: Color, light: Color, trim: Color) -> void:
	match armor:
		ClassData.ArmorType.CLOTH:
			# A pointed cowl with a dark face opening.
			_poly(ci, at, [Vector2(0.0, -0.95), Vector2(0.5, -0.1), Vector2(0.62, 0.65), Vector2(-0.62, 0.65), Vector2(-0.5, -0.1)], main)
			_poly(ci, at, [Vector2(0.0, -0.95), Vector2(0.18, -0.2), Vector2(-0.35, 0.65), Vector2(-0.62, 0.65), Vector2(-0.5, -0.1)], light)
			_ellipse(ci, at, Vector2(0, 0.22), Vector2(0.3, 0.3), dark.darkened(0.5))
			_line(ci, at, Vector2(-0.62, 0.65), Vector2(0.62, 0.65), trim, 2.0)
		ClassData.ArmorType.LEATHER:
			# A round cap with a brim.
			_ellipse(ci, at, Vector2(0, -0.1), Vector2(0.62, 0.62), main)
			_poly(ci, at, [Vector2(-0.8, 0.28), Vector2(0.8, 0.28), Vector2(0.66, 0.5), Vector2(-0.66, 0.5)], dark)
			_line(ci, at, Vector2(-0.45, -0.3), Vector2(0.45, -0.3), light, 3.0)
			_line(ci, at, Vector2(-0.8, 0.28), Vector2(0.8, 0.28), trim, 2.0)
		ClassData.ArmorType.MAIL:
			# A coif: dome, ring-mail flaps down both sides.
			_poly(ci, at, [Vector2(-0.62, 0.7), Vector2(-0.7, -0.1), Vector2(-0.35, -0.75), Vector2(0.35, -0.75), Vector2(0.7, -0.1),
					Vector2(0.62, 0.7), Vector2(0.38, 0.45), Vector2(-0.38, 0.45)], main)
			_ellipse(ci, at, Vector2(0, 0.08), Vector2(0.3, 0.34), dark.darkened(0.5))
			for i in 3:
				for side: float in [-1.0, 1.0]:
					ci.draw_circle(at.call(Vector2(side * (0.48 + 0.0 * float(i)), -0.3 + 0.28 * float(i))) as Vector2, 2.5, light)
			_line(ci, at, Vector2(-0.35, -0.75), Vector2(0.35, -0.75), trim, 2.0)
		_:
			# A great helm: tall barrel, a visor slit, a crest.
			_poly(ci, at, [Vector2(-0.55, 0.8), Vector2(-0.6, -0.4), Vector2(-0.3, -0.85), Vector2(0.3, -0.85), Vector2(0.6, -0.4), Vector2(0.55, 0.8)], main)
			_poly(ci, at, [Vector2(-0.55, 0.8), Vector2(-0.6, -0.4), Vector2(-0.3, -0.85), Vector2(-0.15, -0.85), Vector2(-0.2, 0.8)], light)
			_poly(ci, at, [Vector2(-0.45, -0.18), Vector2(0.45, -0.18), Vector2(0.45, 0.0), Vector2(-0.45, 0.0)], dark.darkened(0.55))
			_line(ci, at, Vector2(0.0, -0.18), Vector2(0.0, 0.8), dark, 2.0)
			_line(ci, at, Vector2(0.0, -1.0), Vector2(0.0, -0.85), trim, 4.0)


static func _shoulders(ci: CanvasItem, at: Callable, armor: int, main: Color, dark: Color, light: Color, trim: Color) -> void:
	for side: float in [-1.0, 1.0]:
		var cx := side * 0.5
		match armor:
			ClassData.ArmorType.CLOTH:
				_poly(ci, at, [Vector2(cx - 0.4 * side, -0.35), Vector2(cx + 0.4 * side, -0.1), Vector2(cx + 0.3 * side, 0.75), Vector2(cx - 0.15 * side, 0.55)], main)
				_line(ci, at, Vector2(cx - 0.4 * side, -0.35), Vector2(cx + 0.3 * side, 0.75), light, 2.0)
				_line(ci, at, Vector2(cx - 0.15 * side, 0.55), Vector2(cx + 0.3 * side, 0.75), trim, 2.0)
			ClassData.ArmorType.LEATHER:
				_ellipse(ci, at, Vector2(cx, 0.0), Vector2(0.42, 0.34), main)
				_ellipse(ci, at, Vector2(cx, -0.05), Vector2(0.3, 0.22), light)
				for i in 3:
					ci.draw_circle(at.call(Vector2(cx + (float(i) - 1.0) * 0.17, 0.2)) as Vector2, 2.5, trim)
			ClassData.ArmorType.MAIL:
				_ellipse(ci, at, Vector2(cx, 0.05), Vector2(0.45, 0.5), main)
				for r in 3:
					for i in 3:
						ci.draw_circle(at.call(Vector2(cx + (float(i) - 1.0) * 0.22, -0.2 + 0.25 * float(r))) as Vector2, 3.0, light)
				_line(ci, at, Vector2(cx - 0.45, 0.5), Vector2(cx + 0.45, 0.5), trim, 2.5)
			_:
				_ellipse(ci, at, Vector2(cx, 0.0), Vector2(0.5, 0.62), main)
				_ellipse(ci, at, Vector2(cx - 0.1 * side, -0.14), Vector2(0.3, 0.4), light)
				_line(ci, at, Vector2(cx - 0.5 * side, 0.22), Vector2(cx + 0.5 * side, 0.22), trim, 3.0)
				_poly(ci, at, [Vector2(cx - 0.1, -0.6), Vector2(cx + 0.1, -0.6), Vector2(cx, -0.95)], trim)


static func _chest(ci: CanvasItem, at: Callable, armor: int, main: Color, dark: Color, light: Color, trim: Color) -> void:
	match armor:
		ClassData.ArmorType.CLOTH:
			# A robe: wide sleeves, a long skirt, a belt.
			_poly(ci, at, [Vector2(-0.45, -0.8), Vector2(0.45, -0.8), Vector2(0.9, -0.1), Vector2(0.7, 0.2), Vector2(0.55, 0.95), Vector2(-0.55, 0.95),
					Vector2(-0.7, 0.2), Vector2(-0.9, -0.1)], main)
			_poly(ci, at, [Vector2(-0.15, -0.8), Vector2(0.15, -0.8), Vector2(0.0, -0.45)], dark.darkened(0.4))
			_line(ci, at, Vector2(-0.62, 0.15), Vector2(0.62, 0.15), trim, 3.0)
			_line(ci, at, Vector2(0.0, -0.45), Vector2(0.0, 0.95), light, 2.0)
		ClassData.ArmorType.LEATHER:
			# A tunic: laces down the front.
			_poly(ci, at, [Vector2(-0.5, -0.8), Vector2(0.5, -0.8), Vector2(0.85, -0.45), Vector2(0.62, -0.1), Vector2(0.55, 0.85), Vector2(-0.55, 0.85),
					Vector2(-0.62, -0.1), Vector2(-0.85, -0.45)], main)
			for i in 4:
				var y := -0.55 + 0.3 * float(i)
				_line(ci, at, Vector2(-0.15, y), Vector2(0.15, y + 0.18), trim, 2.0)
				_line(ci, at, Vector2(0.15, y), Vector2(-0.15, y + 0.18), trim, 2.0)
			_line(ci, at, Vector2(-0.55, 0.5), Vector2(0.55, 0.5), dark, 4.0)
		ClassData.ArmorType.MAIL:
			# A hauberk: ring-mail rows.
			_poly(ci, at, [Vector2(-0.5, -0.8), Vector2(0.5, -0.8), Vector2(0.88, -0.45), Vector2(0.66, -0.05), Vector2(0.62, 0.9), Vector2(-0.62, 0.9),
					Vector2(-0.66, -0.05), Vector2(-0.88, -0.45)], main)
			for r in 5:
				for i in 4:
					var x := (float(i) - 1.5) * 0.28 + (0.14 if r % 2 == 1 else 0.0)
					ci.draw_circle(at.call(Vector2(x, -0.55 + 0.33 * float(r))) as Vector2, 2.6, light)
			_line(ci, at, Vector2(-0.62, 0.9), Vector2(0.62, 0.9), trim, 3.0)
		_:
			# A breastplate: two plates with a ridge and rivets.
			_poly(ci, at, [Vector2(-0.55, -0.85), Vector2(0.55, -0.85), Vector2(0.92, -0.5), Vector2(0.7, 0.0), Vector2(0.45, 0.9), Vector2(-0.45, 0.9),
					Vector2(-0.7, 0.0), Vector2(-0.92, -0.5)], main)
			_poly(ci, at, [Vector2(-0.55, -0.85), Vector2(-0.05, -0.85), Vector2(-0.05, 0.9), Vector2(-0.45, 0.9), Vector2(-0.7, 0.0), Vector2(-0.92, -0.5)], light)
			_line(ci, at, Vector2(0.0, -0.85), Vector2(0.0, 0.9), dark, 3.0)
			_line(ci, at, Vector2(-0.62, 0.3), Vector2(0.62, 0.3), trim, 3.0)
			for side: float in [-1.0, 1.0]:
				ci.draw_circle(at.call(Vector2(side * 0.3, -0.45)) as Vector2, 2.4, trim)


## A small mark in the lower-left corner: a gold star for a tier set piece, a violet gem for a hand-made unique.
static func _draw_corner_mark(ci: CanvasItem, rect: Rect2, entry: WardrobeEntry) -> void:
	var p := rect.position + Vector2(10, rect.size.y - 10)
	if entry.look.is_set():
		var pts := PackedVector2Array()
		for i in 10:
			var a := PI * float(i) / 5.0
			pts.append(p + Vector2(sin(a), -cos(a)) * (6.5 if i % 2 == 0 else 3.0))
		ci.draw_colored_polygon(pts, UiTheme.GOLD if entry.owned else UiTheme.GOLD_DARK)
	elif String(entry.id).begins_with("u."):
		var pts := PackedVector2Array([p + Vector2(0, -6), p + Vector2(5, 0), p + Vector2(0, 6), p + Vector2(-5, 0)])
		ci.draw_colored_polygon(pts, Color(0.75, 0.45, 1.0) if entry.owned else Color(0.35, 0.25, 0.45))


# --- Cosmetics ------------------------------------------------------------------------------

static func _draw_cosmetic(ci: CanvasItem, area: Rect2, c: CosmeticData, locked: bool) -> void:
	if c == null:
		return
	var col := c.color
	var trim := c.trim
	if locked:
		col = LOCKED_TINT.lightened(0.08)
		trim = LOCKED_TINT.lightened(0.28)
	var ctr := area.get_center()
	var s := minf(area.size.x, area.size.y) * 0.5
	var at := func(p: Vector2) -> Vector2: return ctr + p * s
	match c.kind:
		CosmeticData.KIND_TABARD:
			_poly(ci, at, [Vector2(-0.6, -0.9), Vector2(0.6, -0.9), Vector2(0.6, 0.75), Vector2(0.0, 0.95), Vector2(-0.6, 0.75)], col)
			_line(ci, at, Vector2(-0.6, -0.9), Vector2(-0.6, 0.75), trim, 3.0)
			_line(ci, at, Vector2(0.6, -0.9), Vector2(0.6, 0.75), trim, 3.0)
			_line(ci, at, Vector2(-0.6, -0.9), Vector2(0.6, -0.9), trim, 3.0)
			for shape: Dictionary in OnionCosmetics._emblem(c.style, trim, col):
				var pts: Array = []
				for p: Vector2 in shape["outline"]:
					pts.append(Vector2(p.x, -p.y) * 4.0 + Vector2(0, -0.05))
				var tint: Color = shape["color"]
				if locked:
					tint = trim
				_poly(ci, at, pts, tint)
		CosmeticData.KIND_HAT:
			_draw_hat(ci, at, c.style, col, trim)
		CosmeticData.KIND_GLOW:
			ci.draw_arc(ctr, s * 0.62, 0.0, TAU, 32, col, 4.0, true)
			ci.draw_arc(ctr, s * 0.38, 0.0, TAU, 32, Color(col, 0.55), 2.0, true)
			for i in 6:
				var a := TAU * float(i) / 6.0 + 0.4
				ci.draw_circle(ctr + Vector2(cos(a), sin(a)) * s * 0.85, 3.0, col)
			if c.style in [&"halo_star", &"halo_sun"]:
				ci.draw_arc(ctr, s * 0.85, 0.0, TAU, 32, Color(col, 0.6), 2.0, true)
		CosmeticData.KIND_DYE:
			# A drop of dye.
			_poly(ci, at, [Vector2(0.0, -0.95), Vector2(0.5, 0.0), Vector2(0.0, 0.0), Vector2(-0.5, 0.0)], col)
			_ellipse(ci, at, Vector2(0, 0.2), Vector2(0.62, 0.62), col)
			_ellipse(ci, at, Vector2(-0.22, 0.05), Vector2(0.14, 0.2), Color(1, 1, 1, 0.35 if not locked else 0.1))


static func _draw_hat(ci: CanvasItem, at: Callable, style: StringName, col: Color, trim: Color) -> void:
	match style:
		&"bullhorn":
			_ellipse(ci, at, Vector2(0, 0.1), Vector2(0.55, 0.5), col)
			_line(ci, at, Vector2(-0.55, 0.15), Vector2(0.55, 0.15), trim, 3.0)
			for side: float in [-1.0, 1.0]:
				_poly(ci, at, [Vector2(side * 0.45, 0.15), Vector2(side * 0.85, 0.05), Vector2(side * 0.98, -0.4), Vector2(side * 0.9, -0.8), Vector2(side * 0.78, -0.4), Vector2(side * 0.6, -0.12), Vector2(side * 0.45, -0.05)], OnionModel.IVORY)
		&"moonpeak":
			_poly(ci, at, [Vector2(-0.9, 0.6), Vector2(-0.3, 0.45), Vector2(-0.1, -0.5), Vector2(0.3, -0.95), Vector2(0.4, -0.5), Vector2(0.35, 0.45), Vector2(0.9, 0.6), Vector2(0.0, 0.85)], col)
			_ellipse(ci, at, Vector2(0.0, 0.1), Vector2(0.14, 0.14), trim)
		&"crowned":
			_ellipse(ci, at, Vector2(0, 0.15), Vector2(0.55, 0.5), col)
			_poly(ci, at, [Vector2(-0.6, 0.0), Vector2(-0.6, -0.55), Vector2(-0.3, -0.2), Vector2(0.0, -0.7), Vector2(0.3, -0.2), Vector2(0.6, -0.55), Vector2(0.6, 0.0)], trim)
		&"cutpurse":
			_poly(ci, at, [Vector2(0.0, -0.8), Vector2(0.55, -0.1), Vector2(0.5, 0.6), Vector2(-0.5, 0.6), Vector2(-0.55, -0.1)], col)
			_poly(ci, at, [Vector2(0.4, 0.3), Vector2(0.95, 0.75), Vector2(0.55, 0.55)], col.lightened(0.1))
			_ellipse(ci, at, Vector2(0.0, 0.2), Vector2(0.14, 0.14), trim)
		&"imp_horn":
			_poly(ci, at, [Vector2(0.0, -0.7), Vector2(0.55, -0.05), Vector2(0.5, 0.6), Vector2(-0.5, 0.6), Vector2(-0.55, -0.05)], col)
			for side: float in [-1.0, 1.0]:
				_poly(ci, at, [Vector2(side * 0.3, -0.3), Vector2(side * 0.75, -0.9), Vector2(side * 0.55, -0.15)], trim)
		&"feathered":
			_ellipse(ci, at, Vector2(0, 0.2), Vector2(0.95, 0.28), col.darkened(0.1))
			_ellipse(ci, at, Vector2(0, -0.1), Vector2(0.5, 0.45), col)
			_poly(ci, at, [Vector2(0.3, -0.2), Vector2(0.95, -0.95), Vector2(0.55, -0.1)], trim)
		&"thunder_mask":
			_poly(ci, at, [Vector2(-0.55, -0.6), Vector2(0.55, -0.6), Vector2(0.5, 0.2), Vector2(0.0, 0.85), Vector2(-0.5, 0.2)], col)
			_poly(ci, at, [Vector2(0.1, -0.5), Vector2(-0.25, 0.05), Vector2(0.0, 0.05), Vector2(-0.12, 0.5), Vector2(0.3, -0.1), Vector2(0.05, -0.1)], trim)
		_:
			_ellipse(ci, at, Vector2(0, 0.1), Vector2(0.55, 0.5), col)


# --- Other cells ----------------------------------------------------------------------------

static func _draw_none(ci: CanvasItem, area: Rect2, entry: WardrobeEntry) -> void:
	var c := area.get_center()
	var s := minf(area.size.x, area.size.y) * 0.5
	if entry.slot in Profile.LOOK_SLOTS:
		# "Worn gear": the bare onion.
		UiIcon.draw_onion(ci, area.grow(-area.size.x * 0.06), Color(0.86, 0.62, 0.3), false, true)
		return
	ci.draw_arc(c, s * 0.6, 0.0, TAU, 28, UiTheme.TEXT_DIM, 3.0, true)
	ci.draw_line(c + Vector2(-0.42, 0.42) * s, c + Vector2(0.42, -0.42) * s, UiTheme.TEXT_DIM, 3.0, true)


static func _draw_lock(ci: CanvasItem, r: Rect2) -> void:
	var col := Color(0.72, 0.66, 0.58)
	ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.42), Vector2(r.size.x, r.size.y * 0.58)), col, true)
	ci.draw_arc(r.position + Vector2(r.size.x * 0.5, r.size.y * 0.42), r.size.x * 0.32, PI, TAU, 12, col, 2.5, true)
	ci.draw_circle(r.position + Vector2(r.size.x * 0.5, r.size.y * 0.72), 2.0, Color(0.15, 0.12, 0.1))


static func _draw_tick(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_circle(r.get_center(), r.size.x * 0.5, Color(0.08, 0.2, 0.08, 0.95))
	var pts := PackedVector2Array([r.position + Vector2(r.size.x * 0.22, r.size.y * 0.52), r.position + Vector2(r.size.x * 0.42, r.size.y * 0.72),
			r.position + Vector2(r.size.x * 0.78, r.size.y * 0.3)])
	ci.draw_polyline(pts, MARK_COLOR, 2.5, true)
