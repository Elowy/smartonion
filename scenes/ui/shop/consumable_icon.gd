class_name ConsumableIcon
extends Control
## Square icon of a consumable (the stall's consumables row, the unit frame's small icons, the
## tooltip): a dark slot with a border in the kind's colour (blue for flasks / elixirs, orange for
## food) and the picture of ConsumableData.icon_id – the game-icons.net silhouette of
## data/icons/icon_map.tres ([GameIcons]) tinted with the item's own colour, or, when the map has
## none, a procedural picture (a round flask, a tall vial, a conical flask, a bowl of stew, onion
## rings, smoked ribs). Unknown ids get a plain round flask in the kind's colour. No RNG.

const BACKGROUND := Color(0.07, 0.06, 0.055)
const POTION_BORDER := Color(0.45, 0.72, 1.0)
const FOOD_BORDER := Color(1.0, 0.72, 0.3)
const GLASS := Color(0.78, 0.9, 1.0, 0.55)
const CORK := Color(0.62, 0.42, 0.22)
const OUTLINE := Color(0.05, 0.03, 0.02, 0.95)
## Side of a game-icons picture as a share of the slot.
const PICTURE_SCALE := 0.78

## Liquid / main colour per icon id.
const COLORS := {
	&"flask_of_fury": Color(0.9, 0.16, 0.12),
	&"elixir_of_ironskin": Color(0.62, 0.68, 0.76),
	&"elixir_of_swiftness": Color(0.25, 0.85, 0.95),
	&"elixir_of_fortune": Color(0.55, 0.9, 0.25),
	&"hearty_onion_stew": Color(0.85, 0.6, 0.3),
	&"spiced_onion_rings": Color(0.88, 0.62, 0.22),
	&"smoked_boar_ribs": Color(0.62, 0.3, 0.16),
}

var data: ConsumableData


static func create(p_data: ConsumableData = null, p_size: float = 40.0) -> ConsumableIcon:
	var icon := ConsumableIcon.new()
	icon.name = "ConsumableIcon"
	icon.custom_minimum_size = Vector2(p_size, p_size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = GameIcons.FILTER
	icon.data = p_data
	return icon


func set_data(p_data: ConsumableData) -> void:
	if p_data == data:
		return
	data = p_data
	queue_redraw()


## Border colour of [param p_data]'s kind (potion blue, food orange).
static func border_color(p_data: ConsumableData) -> Color:
	if p_data == null:
		return Color(0.32, 0.26, 0.18)
	return POTION_BORDER if p_data.is_potion() else FOOD_BORDER


## The main colour of [param p_data]'s picture.
static func main_color(p_data: ConsumableData) -> Color:
	if p_data == null:
		return Color(0.4, 0.4, 0.4)
	return COLORS.get(p_data.icon_id, border_color(p_data))


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, BACKGROUND)
	var border := border_color(data)
	if data != null:
		draw_rect(r.grow(-2.0), Color(border, 0.1))
		var picture := GameIcons.for_consumable(data)
		if picture != null:
			_draw_silhouette(picture, main_color(data))
		else:
			_draw_picture(data.icon_id, main_color(data))
	draw_rect(r, border.darkened(0.15) if data != null else border, false, 2.0)


## The game-icons picture, tinted with the item's colour, in the middle of the slot.
func _draw_silhouette(picture: Texture2D, c: Color) -> void:
	var m := minf(size.x, size.y)
	var side := m * PICTURE_SCALE
	var rect := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	GameIcons.draw_silhouette(self, picture, rect, GameIcons.gradient_top(c), GameIcons.gradient_bottom(c), maxf(1.0, m / 38.0))


func _draw_picture(id: StringName, c: Color) -> void:
	match id:
		&"flask_of_fury":
			_round_flask(c, 0.26)
			_flame(c.lightened(0.45))
		&"elixir_of_ironskin":
			_vial(c)
		&"elixir_of_swiftness":
			_conical_flask(c)
		&"elixir_of_fortune":
			_round_flask(c, 0.24)
			_sparkle(Vector2(0.5, 0.64), 0.11, Color(1.0, 0.92, 0.45))
		&"hearty_onion_stew":
			_bowl(c)
		&"spiced_onion_rings":
			_rings(c)
		&"smoked_boar_ribs":
			_ribs(c)
		_:
			_round_flask(c, 0.26)


# --- Pictures (unit coordinates, 0..1 over the icon) ----------------------------------------------

func _p(x: float, y: float) -> Vector2:
	return Vector2(x * size.x, y * size.y)


func _lw(thickness: float) -> float:
	return maxf(1.0, thickness * minf(size.x, size.y))


func _cork(x0: float, x1: float, y0: float, y1: float) -> void:
	var cr := Rect2(_p(x0, y0), _p(x1, y1) - _p(x0, y0))
	draw_rect(cr, CORK)
	draw_rect(cr, OUTLINE, false, _lw(0.04))


## A round-bottomed flask: glass neck, cork, a body of [param c] with a highlight.
func _round_flask(c: Color, radius: float) -> void:
	var centre := _p(0.5, 0.64)
	var rad := radius * minf(size.x, size.y)
	draw_rect(Rect2(_p(0.43, 0.2), _p(0.57, 0.42) - _p(0.43, 0.2)), GLASS)
	draw_rect(Rect2(_p(0.43, 0.2), _p(0.57, 0.42) - _p(0.43, 0.2)), OUTLINE, false, _lw(0.04))
	draw_circle(centre, rad, c.darkened(0.15))
	draw_circle(centre + Vector2(0.0, rad * 0.12), rad * 0.88, c)
	draw_arc(centre, rad, 0.0, TAU, 28, OUTLINE, _lw(0.05), true)
	draw_arc(centre, rad * 0.62, PI * 1.05, PI * 1.45, 8, Color(1, 1, 1, 0.55), _lw(0.05), true)
	_cork(0.41, 0.59, 0.1, 0.21)


## A tall straight vial with two bands (steel).
func _vial(c: Color) -> void:
	var body := Rect2(_p(0.32, 0.3), _p(0.68, 0.88) - _p(0.32, 0.3))
	draw_rect(Rect2(_p(0.42, 0.16), _p(0.58, 0.32) - _p(0.42, 0.16)), GLASS)
	draw_rect(Rect2(_p(0.42, 0.16), _p(0.58, 0.32) - _p(0.42, 0.16)), OUTLINE, false, _lw(0.04))
	draw_rect(body, c.darkened(0.2))
	draw_rect(Rect2(body.position + Vector2(0, body.size.y * 0.12), body.size * Vector2(1, 0.88)), c)
	draw_rect(body, OUTLINE, false, _lw(0.05))
	for y in [0.5, 0.7]:
		draw_line(_p(0.32, y), _p(0.68, y), c.darkened(0.45), _lw(0.05))
	draw_line(_p(0.4, 0.36), _p(0.4, 0.82), Color(1, 1, 1, 0.5), _lw(0.05))
	_cork(0.4, 0.6, 0.07, 0.17)


## A conical (Erlenmeyer) flask with two speed lines.
func _conical_flask(c: Color) -> void:
	var pts := PackedVector2Array([_p(0.43, 0.22), _p(0.57, 0.22), _p(0.8, 0.84), _p(0.2, 0.84)])
	draw_rect(Rect2(_p(0.43, 0.14), _p(0.57, 0.3) - _p(0.43, 0.14)), GLASS)
	draw_colored_polygon(pts, c.darkened(0.15))
	draw_colored_polygon(PackedVector2Array([_p(0.34, 0.5), _p(0.66, 0.5), _p(0.8, 0.84), _p(0.2, 0.84)]), c)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, OUTLINE, _lw(0.05), true)
	draw_line(_p(0.3, 0.66), _p(0.52, 0.66), Color(1, 1, 1, 0.7), _lw(0.05))
	draw_line(_p(0.4, 0.75), _p(0.64, 0.75), Color(1, 1, 1, 0.5), _lw(0.04))
	_cork(0.41, 0.59, 0.07, 0.17)


## A little flame on the flask's belly (Fury).
func _flame(c: Color) -> void:
	var pts := PackedVector2Array([_p(0.5, 0.48), _p(0.58, 0.62), _p(0.55, 0.74), _p(0.5, 0.78),
		_p(0.45, 0.74), _p(0.42, 0.62)])
	draw_colored_polygon(pts, c)


## A four-point sparkle centred on [param at] (unit coordinates) – Fortune.
func _sparkle(at: Vector2, radius: float, c: Color) -> void:
	var ctr := _p(at.x, at.y)
	var r1 := radius * minf(size.x, size.y)
	var r2 := r1 * 0.3
	var pts := PackedVector2Array()
	for i in 8:
		var a := -PI * 0.5 + i * PI / 4.0
		var rad := r1 if i % 2 == 0 else r2
		pts.append(ctr + Vector2(cos(a), sin(a)) * rad)
	draw_colored_polygon(pts, c)


## A bowl of stew with steam.
func _bowl(c: Color) -> void:
	var bowl := PackedVector2Array()
	for k in 13:
		var a := PI * k / 12.0
		bowl.append(_p(0.5 + cos(a) * 0.34, 0.54 + sin(a) * 0.3))
	draw_colored_polygon(bowl, Color(0.55, 0.38, 0.24))
	var rim := bowl.duplicate()
	rim.append(bowl[0])
	draw_polyline(rim, OUTLINE, _lw(0.05), true)
	# The stew's surface.
	var surface := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		surface.append(_p(0.5 + cos(a) * 0.33, 0.54 + sin(a) * 0.08))
	draw_colored_polygon(surface, c)
	draw_polyline(surface + PackedVector2Array([surface[0]]), OUTLINE, _lw(0.03), true)
	draw_circle(_p(0.42, 0.54), _lw(0.05), c.lightened(0.45))
	draw_circle(_p(0.58, 0.55), _lw(0.045), c.darkened(0.2))
	for x in [0.4, 0.5, 0.6]:
		draw_arc(_p(x, 0.3), _lw(0.06), PI * 0.4, PI * 1.6, 8, Color(1, 1, 1, 0.6), _lw(0.035), true)


## Three crispy onion rings.
func _rings(c: Color) -> void:
	for ring: Array in [[0.36, 0.36, 0.2], [0.64, 0.4, 0.2], [0.5, 0.66, 0.22]]:
		var ctr := _p(ring[0], ring[1])
		var rad := float(ring[2]) * minf(size.x, size.y)
		draw_arc(ctr, rad, 0.0, TAU, 24, OUTLINE, _lw(0.17), true)
		draw_arc(ctr, rad, 0.0, TAU, 24, c, _lw(0.12), true)
		draw_arc(ctr, rad, PI * 1.1, PI * 1.5, 8, c.lightened(0.4), _lw(0.05), true)
	for spot: Vector2 in [Vector2(0.3, 0.3), Vector2(0.7, 0.45), Vector2(0.46, 0.76), Vector2(0.58, 0.58)]:
		draw_circle(_p(spot.x, spot.y), _lw(0.03), Color(0.85, 0.15, 0.1))


## A slab of smoked ribs with bone ends.
func _ribs(c: Color) -> void:
	draw_set_transform(_p(0.5, 0.5), -0.35, Vector2.ONE)
	var slab := Rect2(Vector2(-0.3 * size.x, -0.18 * size.y), Vector2(0.6 * size.x, 0.36 * size.y))
	draw_rect(slab, c.darkened(0.2))
	draw_rect(Rect2(slab.position, slab.size * Vector2(1, 0.7)), c)
	for i in 3:
		var x := slab.position.x + slab.size.x * (0.22 + 0.28 * i)
		draw_line(Vector2(x, slab.position.y + slab.size.y * 0.08), Vector2(x, slab.end.y - slab.size.y * 0.08), c.darkened(0.45), _lw(0.045))
	draw_rect(slab, OUTLINE, false, _lw(0.05))
	for sx in [-1.0, 1.0]:
		var knob := Vector2(slab.get_center().x + sx * slab.size.x * 0.58, slab.get_center().y)
		draw_circle(knob + Vector2(0, -slab.size.y * 0.16), _lw(0.075), Color(0.94, 0.9, 0.78))
		draw_circle(knob + Vector2(0, slab.size.y * 0.16), _lw(0.075), Color(0.94, 0.9, 0.78))
		draw_line(knob - Vector2(sx * slab.size.x * 0.08, 0), Vector2(slab.get_center().x + sx * slab.size.x * 0.5, knob.y), Color(0.94, 0.9, 0.78), _lw(0.09))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
