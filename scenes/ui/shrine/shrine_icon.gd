class_name ShrineIcon
extends Control
## Square icon of a shrine (the vote card, the HUD's running-shrine row): a dark slot with a border in the
## shrine's colour and the picture of ShrineData.icon_id – the game-icons.net silhouette of
## data/icons/icon_map.tres ([GameIcons]) in the shrine's colour, or, when the map has none, a procedural
## picture: coins (Greed), a lightning bolt (Haste), an open book (Learning), a drop (Blood), a clover
## (Fortune), a die (the Gambler). Unknown ids get a plain altar diamond. With [member badge] > 0 a round
## number badge sits in the bottom-right corner (the waves a running shrine has left). No RNG.

const BACKGROUND := Color(0.07, 0.06, 0.055)
const OUTLINE := Color(0.05, 0.03, 0.02, 0.95)
const BADGE_FILL := Color(0.1, 0.07, 0.04, 0.96)
## Side of a game-icons picture as a share of the slot.
const PICTURE_SCALE := 0.78

var data: ShrineData
## Waves left of a running shrine; 0 = no badge.
var badge := 0


static func create(p_data: ShrineData = null, p_size: float = 40.0, p_badge: int = 0) -> ShrineIcon:
	var icon := ShrineIcon.new()
	icon.name = "ShrineIcon"
	icon.custom_minimum_size = Vector2(p_size, p_size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = GameIcons.FILTER
	icon.data = p_data
	icon.badge = p_badge
	return icon


func set_data(p_data: ShrineData) -> void:
	if p_data != data:
		data = p_data
		queue_redraw()


func set_badge(p_badge: int) -> void:
	if p_badge != badge:
		badge = p_badge
		queue_redraw()


## The shrine's colour (grey without data).
func main_color() -> Color:
	return data.color if data != null else Color(0.5, 0.5, 0.5)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, BACKGROUND)
	var c := main_color()
	if data != null:
		draw_rect(r.grow(-2.0), Color(c, 0.12))
		var picture := GameIcons.for_shrine(data)
		if picture != null:
			var m := minf(size.x, size.y)
			var side := m * PICTURE_SCALE
			GameIcons.draw_silhouette(self, picture, Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)),
					GameIcons.gradient_top(c), GameIcons.gradient_bottom(c), maxf(1.0, m / 38.0))
		else:
			_draw_picture(data.icon_id, c)
	draw_rect(r, c.darkened(0.15), false, 2.0)
	if badge > 0:
		_draw_badge()


func _draw_badge() -> void:
	var m := minf(size.x, size.y)
	var rad := m * 0.24
	var at := Vector2(size.x - rad * 0.5, size.y - rad * 0.5)
	draw_circle(at, rad + 1.5, OUTLINE)
	draw_circle(at, rad, BADGE_FILL)
	draw_arc(at, rad, 0.0, TAU, 20, UiTheme.GOLD_BORDER, maxf(1.0, m * 0.04), true)
	var font := UiTheme.bold_font()
	var fs := maxi(10, int(rad * 1.5))
	var text := str(badge)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(at.x - w * 0.5, at.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.GOLD_BRIGHT)


func _draw_picture(id: StringName, c: Color) -> void:
	match id:
		&"greed":
			_coins(c)
		&"haste":
			_bolt(c)
		&"learning":
			_book(c)
		&"blood":
			_drop(c)
		&"fortune":
			_clover(c)
		&"gambler":
			_die(c)
		_:
			_altar(c)


# --- Pictures (unit coordinates, 0..1 over the icon) ----------------------------------------------

func _p(x: float, y: float) -> Vector2:
	return Vector2(x * size.x, y * size.y)


func _lw(thickness: float) -> float:
	return maxf(1.0, thickness * minf(size.x, size.y))


func _ring(at: Vector2, rad: float, fill: Color, width: float) -> void:
	draw_circle(at, rad + _lw(0.03), OUTLINE)
	draw_circle(at, rad, fill.darkened(0.3))
	draw_circle(at + Vector2(-rad * 0.06, -rad * 0.08), rad * 0.82, fill)
	draw_arc(at, rad * 0.58, 0.0, TAU, 18, fill.darkened(0.35), width, true)


## Three coins in a heap.
func _coins(c: Color) -> void:
	var rad := 0.2 * minf(size.x, size.y)
	_ring(_p(0.36, 0.64), rad, c, _lw(0.035))
	_ring(_p(0.64, 0.64), rad, c, _lw(0.035))
	_ring(_p(0.5, 0.4), rad, c.lightened(0.1), _lw(0.035))
	draw_circle(_p(0.44, 0.32), _lw(0.035), Color(1, 1, 0.9, 0.85))


## A lightning bolt.
func _bolt(c: Color) -> void:
	var pts := PackedVector2Array([_p(0.6, 0.1), _p(0.28, 0.54), _p(0.47, 0.54), _p(0.38, 0.9),
		_p(0.74, 0.4), _p(0.54, 0.4), _p(0.68, 0.1)])
	draw_colored_polygon(pts, c)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, OUTLINE, _lw(0.045), true)
	draw_line(_p(0.58, 0.18), _p(0.4, 0.46), Color(1, 1, 1, 0.55), _lw(0.04))


## An open book with text lines and a spark above it.
func _book(c: Color) -> void:
	var left := PackedVector2Array([_p(0.12, 0.34), _p(0.48, 0.42), _p(0.48, 0.84), _p(0.12, 0.76)])
	var right := PackedVector2Array([_p(0.88, 0.34), _p(0.52, 0.42), _p(0.52, 0.84), _p(0.88, 0.76)])
	for page: PackedVector2Array in [left, right]:
		draw_colored_polygon(page, Color(0.93, 0.88, 0.76))
		var o := page.duplicate()
		o.append(page[0])
		draw_polyline(o, OUTLINE, _lw(0.04), true)
	for y in [0.52, 0.6, 0.68]:
		draw_line(_p(0.18, y), _p(0.42, y + 0.05), c.darkened(0.2), _lw(0.03))
		draw_line(_p(0.58, y + 0.05), _p(0.82, y), c.darkened(0.2), _lw(0.03))
	var ctr := _p(0.5, 0.2)
	var r1 := 0.14 * minf(size.x, size.y)
	var spark := PackedVector2Array()
	for i in 8:
		var a := -PI * 0.5 + i * PI / 4.0
		var rad := r1 if i % 2 == 0 else r1 * 0.32
		spark.append(ctr + Vector2(cos(a), sin(a)) * rad)
	draw_colored_polygon(spark, c.lightened(0.25))


## A blood drop.
func _drop(c: Color) -> void:
	var centre := _p(0.5, 0.62)
	var rad := 0.24 * minf(size.x, size.y)
	var tip := _p(0.5, 0.1)
	var side := rad * 0.96
	var pts := PackedVector2Array([tip, centre + Vector2(-side, -rad * 0.28), centre + Vector2(side, -rad * 0.28)])
	draw_circle(centre, rad + _lw(0.035), OUTLINE)
	draw_colored_polygon(pts, c.darkened(0.2))
	draw_circle(centre, rad, c.darkened(0.2))
	draw_circle(centre + Vector2(0.0, rad * 0.1), rad * 0.84, c)
	draw_polyline(PackedVector2Array([centre + Vector2(-side, -rad * 0.28), tip, centre + Vector2(side, -rad * 0.28)]),
			OUTLINE, _lw(0.04), true)
	draw_arc(centre, rad * 0.62, PI * 0.95, PI * 1.35, 8, Color(1, 1, 1, 0.6), _lw(0.05), true)


## A four-leaf clover on a stem.
func _clover(c: Color) -> void:
	var rad := 0.17 * minf(size.x, size.y)
	var centre := _p(0.5, 0.42)
	draw_line(centre, _p(0.58, 0.9), c.darkened(0.45), _lw(0.06))
	for off: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		var at := centre + off * rad * 0.95
		draw_circle(at, rad + _lw(0.03), OUTLINE)
		draw_circle(at, rad, c.darkened(0.15))
		draw_circle(at + Vector2(-rad * 0.12, -rad * 0.14), rad * 0.62, c.lightened(0.1))
	draw_circle(centre, rad * 0.42, c.darkened(0.3))


## A die showing five.
func _die(c: Color) -> void:
	var body := Rect2(_p(0.2, 0.2), _p(0.8, 0.8) - _p(0.2, 0.2))
	draw_rect(body.grow(_lw(0.03)), OUTLINE)
	draw_rect(body, c.darkened(0.1))
	draw_rect(Rect2(body.position, Vector2(body.size.x, body.size.y * 0.45)), Color(1, 1, 1, 0.14))
	var pip := _lw(0.06)
	for spot: Vector2 in [Vector2(0.3, 0.3), Vector2(0.7, 0.3), Vector2(0.5, 0.5), Vector2(0.3, 0.7), Vector2(0.7, 0.7)]:
		draw_circle(_p(spot.x, spot.y), pip, Color(0.98, 0.95, 0.9))


## A plain altar: a diamond on a base (unknown ids).
func _altar(c: Color) -> void:
	var pts := PackedVector2Array([_p(0.5, 0.15), _p(0.78, 0.5), _p(0.5, 0.85), _p(0.22, 0.5)])
	draw_colored_polygon(pts, c)
	var o := pts.duplicate()
	o.append(pts[0])
	draw_polyline(o, OUTLINE, _lw(0.05), true)
