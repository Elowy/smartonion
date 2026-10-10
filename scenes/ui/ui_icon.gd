class_name UiIcon
extends Control
## Small vector icons drawn in code (no image assets yet): coin, check mark, padlock, onion
## hero (optionally wearing a horned helm), gold divider rule, arrows, crown, warning sign.

enum Kind { COIN, CHECK, LOCK, ONION, DIVIDER, ARROW_LEFT, ARROW_RIGHT, CROWN, WARNING, SWORDS }

## Onion silhouette, (half width, height) from the root (0) to the tip (1).
const ONION_PROFILE: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(0.16, 0.015), Vector2(0.31, 0.07), Vector2(0.42, 0.17),
	Vector2(0.48, 0.3), Vector2(0.485, 0.42), Vector2(0.45, 0.54), Vector2(0.37, 0.66),
	Vector2(0.26, 0.77), Vector2(0.15, 0.87), Vector2(0.08, 0.94), Vector2(0.035, 1.0),
]
const DARK := Color(0.08, 0.05, 0.03)

var kind := Kind.COIN
## Main colour (onion skin, check, arrow ...).
var color := Color.WHITE
## ONION only: draw a horned helm on top.
var helm := false
## ONION only: friendly face.
var face := true


static func create(p_kind: Kind, p_size: Vector2 = Vector2(32, 32), p_color: Color = Color(0, 0, 0, 0)) -> UiIcon:
	var icon := UiIcon.new()
	icon.kind = p_kind
	icon.custom_minimum_size = p_size
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if p_color.a > 0.0:
		icon.color = p_color
	else:
		match p_kind:
			Kind.COIN, Kind.DIVIDER, Kind.CROWN:
				icon.color = UiTheme.GOLD
			Kind.CHECK:
				icon.color = UiTheme.GREEN
			Kind.ONION:
				icon.color = Color(0.72, 0.4, 0.62)
			Kind.WARNING:
				icon.color = Color(1.0, 0.72, 0.2)
			_:
				icon.color = UiTheme.TEXT
	return icon


func set_color(c: Color) -> void:
	color = c
	queue_redraw()


func _draw() -> void:
	match kind:
		Kind.COIN:
			_draw_coin()
		Kind.CHECK:
			_draw_check()
		Kind.LOCK:
			_draw_lock()
		Kind.ONION:
			draw_onion(self, Rect2(Vector2.ZERO, size), color, helm, face)
		Kind.DIVIDER:
			_draw_divider()
		Kind.ARROW_LEFT:
			_draw_arrow(-1.0)
		Kind.ARROW_RIGHT:
			_draw_arrow(1.0)
		Kind.CROWN:
			_draw_crown()
		Kind.WARNING:
			_draw_warning()
		Kind.SWORDS:
			_draw_swords()


func _draw_coin() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 1.0
	draw_circle(c + Vector2(0, 1.5), r, Color(0, 0, 0, 0.45))
	draw_circle(c, r, DARK)
	draw_circle(c, r - 1.5, color.darkened(0.35))
	draw_circle(c + Vector2(-r * 0.06, -r * 0.08), r * 0.8, color)
	draw_arc(c, r * 0.62, 0.0, TAU, 28, color.darkened(0.3), maxf(1.0, r * 0.1), true)
	draw_arc(c, r * 0.8, PI * 1.05, PI * 1.55, 10, Color(1, 1, 0.85, 0.85), maxf(1.0, r * 0.13), true)
	draw_circle(c + Vector2(-r * 0.38, -r * 0.38), r * 0.12, Color(1, 1, 0.9, 0.9))


func _draw_check() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var pts := PackedVector2Array([o + Vector2(0.14, 0.52) * s, o + Vector2(0.4, 0.78) * s, o + Vector2(0.88, 0.22) * s])
	draw_polyline(pts, DARK, s * 0.26, true)
	draw_polyline(pts, color, s * 0.15, true)


func _draw_lock() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var body := Rect2(o + Vector2(0.18, 0.44) * s, Vector2(0.64, 0.48) * s)
	draw_arc(o + Vector2(0.5, 0.44) * s, s * 0.22, PI, TAU, 16, DARK, s * 0.16, true)
	draw_arc(o + Vector2(0.5, 0.44) * s, s * 0.22, PI, TAU, 16, color.darkened(0.2), s * 0.09, true)
	draw_rect(body.grow(s * 0.05), DARK)
	draw_rect(body, color)
	draw_rect(Rect2(body.position, Vector2(body.size.x, body.size.y * 0.35)), Color(1, 1, 1, 0.18))
	draw_circle(body.get_center(), s * 0.07, DARK)


func _draw_divider() -> void:
	var y := size.y * 0.5
	var w := size.x
	var dim := Color(color, 0.0)
	var pts := PackedVector2Array([Vector2(0, y - 1), Vector2(w * 0.5, y - 1.5), Vector2(w, y - 1),
		Vector2(w, y + 1), Vector2(w * 0.5, y + 1.5), Vector2(0, y + 1)])
	draw_polygon(pts, PackedColorArray([dim, color, dim, dim, color, dim]))
	var d := minf(size.y * 0.42, 7.0)
	var c := Vector2(w * 0.5, y)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d - 2), c + Vector2(d + 2, 0), c + Vector2(0, d + 2), c + Vector2(-d - 2, 0)]), DARK)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), color)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d * 0.45), c + Vector2(d * 0.45, 0), c + Vector2(0, d * 0.45), c + Vector2(-d * 0.45, 0)]), color.lightened(0.5))


func _draw_arrow(dir: float) -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var tip := c + Vector2(dir * s * 0.36, 0)
	var back_top := c + Vector2(-dir * s * 0.3, -s * 0.4)
	var back_bottom := c + Vector2(-dir * s * 0.3, s * 0.4)
	var outline := PackedVector2Array([tip + Vector2(dir * 3, 0), back_top + Vector2(-dir * 2, -3), back_bottom + Vector2(-dir * 2, 3)])
	draw_colored_polygon(outline, DARK)
	draw_polygon(PackedVector2Array([tip, back_top, back_bottom]), PackedColorArray([color.lightened(0.25), color, color.darkened(0.3)]))


func _draw_crown() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var p := PackedVector2Array()
	for v in [Vector2(0.1, 0.8), Vector2(0.06, 0.28), Vector2(0.3, 0.52), Vector2(0.5, 0.16),
			Vector2(0.7, 0.52), Vector2(0.94, 0.28), Vector2(0.9, 0.8)]:
		p.append(o + v * s)
	var outline := PackedVector2Array(p)
	outline.append(p[0])
	draw_colored_polygon(p, color)
	draw_polyline(outline, DARK, maxf(1.5, s * 0.07), true)
	draw_rect(Rect2(o + Vector2(0.1, 0.72) * s, Vector2(0.8, 0.1) * s), color.darkened(0.3))
	for v in [Vector2(0.06, 0.28), Vector2(0.5, 0.16), Vector2(0.94, 0.28)]:
		draw_circle(o + v * s, s * 0.07, Color(0.95, 0.3, 0.3))


func _draw_warning() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var tri := PackedVector2Array([o + Vector2(0.5, 0.06) * s, o + Vector2(0.96, 0.9) * s, o + Vector2(0.04, 0.9) * s])
	var outline := PackedVector2Array(tri)
	outline.append(tri[0])
	draw_colored_polygon(tri, color)
	draw_polyline(outline, DARK, s * 0.08, true)
	draw_line(o + Vector2(0.5, 0.34) * s, o + Vector2(0.5, 0.6) * s, DARK, s * 0.11)
	draw_circle(o + Vector2(0.5, 0.75) * s, s * 0.065, DARK)


func _draw_swords() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	for side in [-1.0, 1.0]:
		var a := o + Vector2(0.5 - side * 0.36, 0.86) * s
		var b := o + Vector2(0.5 + side * 0.34, 0.12) * s
		draw_line(a, b, DARK, s * 0.16, true)
		draw_line(a.lerp(b, 0.22), b, color, s * 0.08, true)
		var g := a.lerp(b, 0.22)
		var n := (b - a).normalized().orthogonal() * s * 0.14
		draw_line(g - n, g + n, DARK, s * 0.12, true)
		draw_line(g - n * 0.85, g + n * 0.85, UiTheme.GOLD, s * 0.06, true)


# --- Onion hero ------------------------------------------------------------------------

## Draws a cartoon onion hero into [param rect] of [param ci] (also used by portraits).
static func draw_onion(ci: CanvasItem, rect: Rect2, skin: Color, with_helm: bool = false, with_face: bool = true) -> void:
	var units := Vector2(1.5 if with_helm else 1.08, 1.3)
	var k := minf(rect.size.x / units.x, rect.size.y / units.y)
	var base := Vector2(rect.get_center().x, rect.position.y + (rect.size.y + units.y * k) * 0.5 - 0.04 * k)
	draw_onion_at(ci, base, k, skin, with_helm, with_face)


## Draws the onion with its root at [param base]; [param k] = pixels per bulb height.
## [param sprout] scales the leaves on top (portraits use short ones).
static func draw_onion_at(ci: CanvasItem, base: Vector2, k: float, skin: Color, with_helm: bool = false,
		with_face: bool = true, sprout: float = 1.0) -> void:
	var to_screen := func(v: Vector2) -> Vector2: return base + Vector2(v.x, -v.y) * k
	var outline_w := maxf(1.5, k * 0.035)

	# Sprout leaves.
	var leaf := Color(0.4, 0.72, 0.24)
	for leaf_def: Array in [[Vector2(0.0, 0.97), Vector2(-0.2, 1.24), 0.07], [Vector2(0.0, 0.97), Vector2(0.14, 1.27), 0.06],
			[Vector2(0.0, 0.97), Vector2(0.03, 1.29), 0.05]]:
		var root: Vector2 = leaf_def[0]
		var a: Vector2 = to_screen.call(root)
		var b: Vector2 = to_screen.call(root + (Vector2(leaf_def[1]) - root) * sprout)
		var w: float = leaf_def[2] * k
		var n := (b - a).normalized().orthogonal() * w
		var mid := a.lerp(b, 0.45)
		var poly := PackedVector2Array([a - n * 0.5, mid - n, b, mid + n, a + n * 0.5])
		var closed := PackedVector2Array(poly)
		closed.append(poly[0])
		ci.draw_colored_polygon(poly, leaf)
		ci.draw_polyline(closed, DARK, outline_w * 0.8, true)

	# Bulb.
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var light := skin.lightened(0.28)
	var shade := skin.darkened(0.35)
	for i in ONION_PROFILE.size():
		var p := ONION_PROFILE[i]
		pts.append(to_screen.call(Vector2(-p.x, p.y)))
		cols.append(light.lerp(skin, p.y * 0.4))
	for i in range(ONION_PROFILE.size() - 2, 0, -1):
		var p := ONION_PROFILE[i]
		pts.append(to_screen.call(Vector2(p.x, p.y)))
		cols.append(skin.lerp(shade, 0.7 - p.y * 0.5))
	ci.draw_polygon(pts, cols)
	# Layer lines (the onion's skins).
	for f in [0.62, 0.28]:
		var line := PackedVector2Array()
		for i in range(1, ONION_PROFILE.size() - 1):
			var p := ONION_PROFILE[i]
			line.append(to_screen.call(Vector2(p.x * f, p.y)))
		ci.draw_polyline(line, Color(shade, 0.55), maxf(1.0, k * 0.018), true)
	# Sheen.
	var sheen_pts := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		var a := lerpf(PI * 0.62, PI * 1.05, t)
		sheen_pts.append(to_screen.call(Vector2(-0.02, 0.44) + Vector2(cos(a) * 0.36, sin(a) * 0.3)))
	ci.draw_polyline(sheen_pts, Color(1, 1, 1, 0.35), maxf(1.5, k * 0.045), true)
	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	ci.draw_polyline(outline, DARK, outline_w, true)

	if with_helm:
		_draw_helm(ci, to_screen, k, outline_w)
	if with_face:
		var eye_y := 0.4 if with_helm else 0.47
		for side in [-1.0, 1.0]:
			var e: Vector2 = to_screen.call(Vector2(side * 0.14, eye_y))
			var eye_r := Vector2(0.075, 0.095) * k
			_ellipse(ci, e, eye_r + Vector2.ONE * outline_w * 0.6, DARK)
			_ellipse(ci, e, eye_r, Color(1, 1, 1))
			ci.draw_circle(e + Vector2(side * 0.012, 0.02) * k, 0.05 * k, Color(0.08, 0.06, 0.08))
			ci.draw_circle(e + Vector2(-0.02, -0.025) * k, 0.02 * k, Color(1, 1, 1))
		var m: Vector2 = to_screen.call(Vector2(0.0, eye_y - 0.15))
		ci.draw_arc(m, 0.07 * k, PI * 0.15, PI * 0.85, 10, DARK, maxf(1.5, k * 0.025), true)
		for side in [-1.0, 1.0]:
			ci.draw_circle(to_screen.call(Vector2(side * 0.27, eye_y - 0.1)), 0.05 * k, Color(1.0, 0.45, 0.45, 0.35))


static func _draw_helm(ci: CanvasItem, to_screen: Callable, k: float, w: float) -> void:
	var metal := Color(0.66, 0.68, 0.74)
	var gold := Color(0.93, 0.72, 0.28)
	var ivory := Color(0.95, 0.9, 0.76)
	# Horns.
	for side in [-1.0, 1.0]:
		var horn := PackedVector2Array()
		var outer: Array[Vector2] = []
		var inner: Array[Vector2] = []
		for i in 9:
			var t := float(i) / 8.0
			var root := Vector2(side * 0.36, 0.7)
			var tip := Vector2(side * 0.74, 1.12)
			var ctrl := Vector2(side * 0.78, 0.66)
			var p := root.lerp(ctrl, t).lerp(ctrl.lerp(tip, t), t)
			var thick := lerpf(0.09, 0.0, t)
			outer.append(p + Vector2(0, -thick))
			inner.append(p + Vector2(-side * thick * 0.4, thick))
		for p in outer:
			horn.append(to_screen.call(p))
		for i in range(inner.size() - 1, -1, -1):
			horn.append(to_screen.call(inner[i]))
		var closed := PackedVector2Array(horn)
		closed.append(horn[0])
		ci.draw_colored_polygon(horn, ivory)
		ci.draw_polyline(closed, DARK, w, true)
	# Dome.
	var dome := PackedVector2Array()
	var center := Vector2(0.0, 0.6)
	for i in 17:
		var a := PI * float(i) / 16.0
		dome.append(to_screen.call(center + Vector2(cos(a) * 0.47, sin(a) * 0.38)))
	var dome_cols := PackedColorArray()
	for i in dome.size():
		dome_cols.append(metal.lightened(0.25).lerp(metal.darkened(0.25), float(i) / 16.0))
	ci.draw_polygon(dome, dome_cols)
	var dome_line := PackedVector2Array(dome)
	dome_line.append(dome[0])
	ci.draw_polyline(dome_line, DARK, w, true)
	# Ridge and band.
	ci.draw_line(to_screen.call(Vector2(0.0, 0.6)), to_screen.call(Vector2(0.0, 0.98)), Color(gold, 0.95), k * 0.05, true)
	var band := PackedVector2Array([to_screen.call(Vector2(-0.5, 0.64)), to_screen.call(Vector2(0.5, 0.64)),
		to_screen.call(Vector2(0.48, 0.55)), to_screen.call(Vector2(-0.48, 0.55))])
	ci.draw_colored_polygon(band, gold)
	var band_line := PackedVector2Array(band)
	band_line.append(band[0])
	ci.draw_polyline(band_line, DARK, w, true)
	for x in [-0.33, -0.11, 0.11, 0.33]:
		ci.draw_circle(to_screen.call(Vector2(x, 0.595)), k * 0.022, gold.lightened(0.5))
	# Sprout pokes out through the helm top.
	ci.draw_line(to_screen.call(Vector2(0.0, 0.96)), to_screen.call(Vector2(0.0, 1.05)), Color(0.4, 0.72, 0.24), k * 0.05, true)


static func _ellipse(ci: CanvasItem, center: Vector2, radii: Vector2, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	ci.draw_colored_polygon(pts, c)
