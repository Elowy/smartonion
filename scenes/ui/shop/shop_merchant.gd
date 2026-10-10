class_name ShopMerchant
extends Control
## The top of the goblin's stall (ShopPanel, GDD 10 / 12), drawn in code: a wooden beam with a
## striped, scalloped awning, a hanging wooden sign "The Goblin's Goods", a lantern on the left
## and the goblin merchant himself (big ears, top hat, gold tooth) peeking out on the right.

const SIGN_TEXT := "The Goblin's Goods"
const STRIPE_WIDTH := 52.0
const AWNING_TOP := 14.0
const AWNING_BOTTOM := 66.0
const SCALLOP_RADIUS := 26.0
const SIGN_SIZE := Vector2(360, 54)
const SIGN_TOP := 60.0

const AWNING_RED := Color(0.55, 0.12, 0.09)
const AWNING_CREAM := Color(0.86, 0.76, 0.55)
const WOOD := Color(0.36, 0.22, 0.11)
const WOOD_DARK := Color(0.2, 0.12, 0.06)
const WOOD_LIGHT := Color(0.52, 0.34, 0.17)
const GOBLIN_SKIN := Color(0.42, 0.66, 0.24)
const GOBLIN_SHADE := Color(0.27, 0.46, 0.15)
const LINE := Color(0.07, 0.04, 0.02)

## 0..1 bob of the goblin (animated while visible) and the lantern flicker.
var _t := 0.0


static func create() -> ShopMerchant:
	var m := ShopMerchant.new()
	m.name = "Merchant"
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.custom_minimum_size = Vector2(0, SIGN_TOP + SIGN_SIZE.y + 8.0)
	return m


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	_draw_awning(w)
	_draw_lantern(Vector2(64.0, AWNING_BOTTOM + 8.0))
	_draw_sign(Vector2(w * 0.5, SIGN_TOP))
	_draw_goblin(Vector2(w - 92.0, AWNING_BOTTOM - 12.0 + sin(_t * 1.7) * 1.5))


# --- Awning ------------------------------------------------------------------------

func _draw_awning(w: float) -> void:
	var stripes := maxi(1, ceili(w / STRIPE_WIDTH))
	var sw := w / stripes
	# Shadow under the scallops onto the stall.
	for i in stripes:
		var cx := sw * (i + 0.5)
		draw_circle(Vector2(cx, AWNING_BOTTOM + 6.0), sw * 0.5, Color(0, 0, 0, 0.28))
	for i in stripes:
		var x0 := sw * i
		var c := AWNING_RED if i % 2 == 0 else AWNING_CREAM
		var top := c.lightened(0.12)
		var bottom := c.darkened(0.25)
		draw_polygon(PackedVector2Array([
			Vector2(x0, AWNING_TOP), Vector2(x0 + sw, AWNING_TOP),
			Vector2(x0 + sw, AWNING_BOTTOM), Vector2(x0, AWNING_BOTTOM)]),
			PackedColorArray([top, top, bottom, bottom]))
		# Scallop: a half disc hanging below the stripe.
		var pts := PackedVector2Array()
		var cx := x0 + sw * 0.5
		for k in 13:
			var a := PI * k / 12.0
			pts.append(Vector2(cx + cos(a) * sw * 0.5, AWNING_BOTTOM + sin(a) * minf(SCALLOP_RADIUS, sw * 0.5) * 0.7))
		draw_colored_polygon(pts, bottom)
		pts.append(pts[0])
		draw_polyline(pts, LINE, 1.5, true)
	# Folds: thin darker lines in the middle of every stripe.
	for i in stripes:
		var cx := sw * (i + 0.5)
		draw_line(Vector2(cx, AWNING_TOP + 4.0), Vector2(cx, AWNING_BOTTOM - 2.0), Color(0, 0, 0, 0.12), 2.0)
	# Wooden beam on top.
	draw_rect(Rect2(-6.0, AWNING_TOP - 12.0, w + 12.0, 14.0), WOOD)
	draw_rect(Rect2(-6.0, AWNING_TOP - 12.0, w + 12.0, 3.0), WOOD_LIGHT)
	draw_rect(Rect2(-6.0, AWNING_TOP - 12.0, w + 12.0, 14.0), LINE, false, 2.0)
	for x in [10.0, w - 10.0]:
		draw_circle(Vector2(x, AWNING_TOP - 5.0), 3.5, UiTheme.GOLD_BORDER)


# --- Sign -------------------------------------------------------------------------

func _draw_sign(top_center: Vector2) -> void:
	var r := Rect2(top_center - Vector2(SIGN_SIZE.x * 0.5, 0.0), SIGN_SIZE)
	# Ropes from the beam.
	for x in [r.position.x + 40.0, r.end.x - 40.0]:
		draw_line(Vector2(x, AWNING_TOP - 4.0), Vector2(x, r.position.y + 6.0), Color(0.62, 0.5, 0.3), 3.0)
	draw_rect(Rect2(r.position + Vector2(3, 5), r.size), Color(0, 0, 0, 0.45))
	draw_rect(r, WOOD)
	# Planks.
	var plank_h := r.size.y / 3.0
	for i in 3:
		var pr := Rect2(r.position.x, r.position.y + plank_h * i, r.size.x, plank_h)
		draw_rect(pr, WOOD.lerp(WOOD_LIGHT, 0.18 * (i % 2)))
		draw_line(pr.position + Vector2(0, plank_h), pr.position + Vector2(r.size.x, plank_h), WOOD_DARK, 1.5)
	draw_rect(r, UiTheme.GOLD_DARK, false, 3.0)
	draw_rect(r.grow(-4.0), Color(0, 0, 0, 0.35), false, 1.0)
	for c in [r.position + Vector2(9, 9), Vector2(r.end.x - 9, r.position.y + 9),
			Vector2(r.position.x + 9, r.end.y - 9), r.end - Vector2(9, 9)]:
		draw_circle(c, 3.0, UiTheme.GOLD_BORDER)
	var font := UiTheme.title_font()
	var fs := 30
	var text_w := font.get_string_size(SIGN_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(r.position.x + (r.size.x - text_w) * 0.5, r.position.y + r.size.y * 0.5 + fs * 0.36)
	draw_string_outline(font, base + Vector2(0, 2), SIGN_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0, 0, 0, 0.5))
	draw_string_outline(font, base, SIGN_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, LINE)
	draw_string(font, base, SIGN_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.GOLD)


# --- Lantern ----------------------------------------------------------------------

func _draw_lantern(top: Vector2) -> void:
	var flicker := 0.85 + 0.15 * sin(_t * 9.0) * sin(_t * 3.3)
	draw_line(top + Vector2(0, -24), top, Color(0.25, 0.2, 0.15), 2.0)
	draw_circle(top + Vector2(0, 22), 30.0, Color(1.0, 0.7, 0.25, 0.10 * flicker))
	draw_circle(top + Vector2(0, 22), 18.0, Color(1.0, 0.75, 0.3, 0.16 * flicker))
	var body := Rect2(top + Vector2(-10, 6), Vector2(20, 28))
	draw_rect(body, Color(1.0, 0.78, 0.35, 0.9 * flicker))
	draw_rect(body, LINE, false, 2.0)
	draw_line(body.position + Vector2(10, 0), body.position + Vector2(10, 28), Color(0.2, 0.12, 0.05, 0.8), 2.0)
	draw_rect(Rect2(top + Vector2(-13, 0), Vector2(26, 7)), Color(0.2, 0.15, 0.1))
	draw_rect(Rect2(top + Vector2(-12, 34), Vector2(24, 5)), Color(0.2, 0.15, 0.1))


# --- Goblin -----------------------------------------------------------------------

## The merchant's head and shoulders (kept above the stall body, which starts at
## ShopPanel.BODY_TOP); [param c] is the centre of the head.
func _draw_goblin(c: Vector2) -> void:
	# Shoulders / vest behind the head.
	var vest := PackedVector2Array([c + Vector2(-40, 22), c + Vector2(40, 22), c + Vector2(50, 40), c + Vector2(-50, 40)])
	draw_colored_polygon(vest, Color(0.4, 0.17, 0.32))
	draw_polyline(_closed(vest), LINE, 2.0, true)
	draw_line(c + Vector2(0, 26), c + Vector2(0, 40), UiTheme.GOLD_BORDER, 2.0)
	# Ears: long and pointy, slightly drooping.
	for side in [-1.0, 1.0]:
		var ear := PackedVector2Array([
			c + Vector2(side * 22, -10), c + Vector2(side * 70, -22), c + Vector2(side * 58, -6),
			c + Vector2(side * 26, 8)])
		draw_colored_polygon(ear, GOBLIN_SKIN)
		draw_polyline(_closed(ear), LINE, 2.0, true)
		var inner := PackedVector2Array([c + Vector2(side * 28, -6), c + Vector2(side * 60, -16), c + Vector2(side * 30, 3)])
		draw_colored_polygon(inner, GOBLIN_SHADE.lerp(Color(0.75, 0.4, 0.35), 0.35))
	# Head.
	var head := _ellipse_points(c, Vector2(30, 30))
	draw_colored_polygon(head, GOBLIN_SKIN)
	draw_colored_polygon(_ellipse_points(c + Vector2(0, 10), Vector2(24, 17)), GOBLIN_SHADE.lerp(GOBLIN_SKIN, 0.5))
	draw_polyline(_closed(head), LINE, 2.0, true)
	# Eyes (yellow, shifty) with heavy brows.
	var look := sin(_t * 0.9) * 2.0
	for side in [-1.0, 1.0]:
		var e := c + Vector2(side * 11, -5)
		draw_colored_polygon(_ellipse_points(e, Vector2(7, 5.5)), Color(1.0, 0.86, 0.3))
		draw_circle(e + Vector2(look, 0.5), 2.6, LINE)
		draw_line(e + Vector2(-side * 8, -9), e + Vector2(side * 7, -6), LINE, 3.0)
	# Long nose.
	var nose := PackedVector2Array([c + Vector2(-4, -2), c + Vector2(4, -2), c + Vector2(3, 12), c + Vector2(-9, 13)])
	draw_colored_polygon(nose, GOBLIN_SKIN.darkened(0.12))
	draw_polyline(_closed(nose), LINE, 1.5, true)
	# Grin with a gold tooth.
	var grin := PackedVector2Array()
	for k in 9:
		var a := lerpf(0.15 * PI, 0.85 * PI, k / 8.0)
		grin.append(c + Vector2(cos(a) * 16.0, 14.0 + sin(a) * 6.0))
	draw_polyline(grin, LINE, 2.5, true)
	draw_rect(Rect2(c + Vector2(3, 15), Vector2(5, 5)), UiTheme.GOLD)
	draw_rect(Rect2(c + Vector2(3, 15), Vector2(5, 5)), LINE, false, 1.0)
	# Top hat.
	var brim := Rect2(c + Vector2(-30, -34), Vector2(60, 7))
	var crown := Rect2(c + Vector2(-19, -66), Vector2(38, 33))
	draw_rect(crown, Color(0.14, 0.11, 0.1))
	draw_rect(Rect2(crown.position + Vector2(0, 22), Vector2(crown.size.x, 6)), Color(0.55, 0.12, 0.09))
	draw_rect(crown, LINE, false, 2.0)
	draw_rect(brim, Color(0.12, 0.1, 0.09))
	draw_rect(brim, LINE, false, 2.0)
	draw_circle(crown.position + Vector2(crown.size.x - 8, 25), 3.0, UiTheme.GOLD)
	# A coin flipped in the left hand.
	var coin_y := -6.0 + absf(sin(_t * 2.6)) * -14.0
	var coin := c + Vector2(-64, 18 + coin_y)
	var squash := absf(cos(_t * 5.2))
	draw_colored_polygon(_ellipse_points(coin, Vector2(8.0 * maxf(squash, 0.15), 8.0)), UiTheme.GOLD)
	draw_polyline(_closed(_ellipse_points(coin, Vector2(8.0 * maxf(squash, 0.15), 8.0))), LINE, 1.5, true)
	var hand := _ellipse_points(c + Vector2(-60, 32), Vector2(10, 7))
	draw_colored_polygon(hand, GOBLIN_SKIN)
	draw_polyline(_closed(hand), LINE, 1.5, true)


static func _ellipse_points(center: Vector2, radii: Vector2, steps: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var a := TAU * i / steps
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out
