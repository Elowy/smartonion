class_name UiFrameStyle
extends StyleBox
## WoW-like layered frame (GDD 12) drawn in code: drop shadow, dark stone / leather fill with a
## soft vertical sheen, an inner shadow, a thin gold border with a dark keyline inside it and
## small gold studs on the corners. Built by UiTheme for panels, buttons and cards.

var fill := Color(0.115, 0.1, 0.09, 0.96)
var border := Color(0.82, 0.64, 0.28)
var border_width := 2
var corner_radius := 6
var shadow_size := 10
var shadow_color := Color(0, 0, 0, 0.55)
## Width (px) of the dark gradient along the inner edge of the border; 0 = none.
var inner_shadow := 14
var inner_shadow_color := Color(0, 0, 0, 0.5)
## Top-to-bottom sheen: added on the top half, subtracted on the bottom half.
var sheen := 0.035
var studs := true
var stud_color := Color(1.0, 0.85, 0.45)
## Thin dark line just inside the gold border (WoW frames have a double edge).
var keyline := true
## Soft coloured glow around the frame (focus / selection); alpha 0 = none.
var glow := Color(0, 0, 0, 0)
var glow_size := 12

var _base: StyleBoxFlat
var _inner: StyleBoxFlat
var _key: StyleBoxFlat
var _glow: StyleBoxFlat


func _init() -> void:
	content_margin_left = 14
	content_margin_right = 14
	content_margin_top = 12
	content_margin_bottom = 12


## Call after changing any property (rebuilds the cached layers).
func rebuild() -> UiFrameStyle:
	_base = StyleBoxFlat.new()
	_base.bg_color = fill
	_base.border_color = border
	_base.set_border_width_all(border_width)
	_base.set_corner_radius_all(corner_radius)
	_base.shadow_color = shadow_color
	_base.shadow_size = shadow_size
	_base.shadow_offset = Vector2(0, shadow_size * 0.3)
	_base.anti_aliasing = true
	_inner = null
	if inner_shadow > 0:
		_inner = StyleBoxFlat.new()
		_inner.draw_center = false
		_inner.bg_color = Color(inner_shadow_color.r, inner_shadow_color.g, inner_shadow_color.b, 0.0)
		_inner.border_color = inner_shadow_color
		_inner.set_border_width_all(inner_shadow)
		_inner.border_blend = true
		_inner.set_corner_radius_all(maxi(0, corner_radius - border_width))
	_key = null
	if keyline:
		_key = StyleBoxFlat.new()
		_key.draw_center = false
		_key.border_color = Color(0, 0, 0, 0.6)
		_key.set_border_width_all(1)
		_key.set_corner_radius_all(maxi(0, corner_radius - border_width))
	_glow = null
	if glow.a > 0.0:
		_glow = StyleBoxFlat.new()
		_glow.draw_center = false
		_glow.bg_color = Color(glow.r, glow.g, glow.b, 0.0)
		_glow.shadow_color = glow
		_glow.shadow_size = glow_size
		_glow.set_corner_radius_all(corner_radius)
	emit_changed()
	return self


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if _base == null:
		rebuild()
	if _glow != null:
		_glow.draw(to_canvas_item, rect)
	_base.draw(to_canvas_item, rect)
	var inner := rect.grow(-border_width)
	if inner.size.x <= 2.0 or inner.size.y <= 2.0:
		return
	if sheen > 0.0 and fill.a > 0.0:
		var inset := maxf(float(border_width), corner_radius * 0.5 + 1.0)
		var r := rect.grow(-inset)
		if r.size.x > 0.0 and r.size.y > 0.0:
			var mid := r.position.y + r.size.y * 0.5
			var top := Color(1, 1, 1, sheen)
			var clear := Color(1, 1, 1, 0.0)
			var dark := Color(0, 0, 0, sheen * 2.5)
			var dark_clear := Color(0, 0, 0, 0.0)
			RenderingServer.canvas_item_add_polygon(to_canvas_item, PackedVector2Array([
				r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x, mid), Vector2(r.position.x, mid)]),
				PackedColorArray([top, top, clear, clear]))
			RenderingServer.canvas_item_add_polygon(to_canvas_item, PackedVector2Array([
				Vector2(r.position.x, mid), Vector2(r.end.x, mid), r.end, Vector2(r.position.x, r.end.y)]),
				PackedColorArray([dark_clear, dark_clear, dark, dark]))
	if _inner != null:
		_inner.draw(to_canvas_item, inner)
	if _key != null:
		_key.draw(to_canvas_item, inner)
	if studs and rect.size.x > 40.0 and rect.size.y > 30.0:
		var s := 4.0 + border_width
		var o := float(border_width) * 0.5
		for c in [rect.position + Vector2(o, o), Vector2(rect.end.x - o, rect.position.y + o),
				Vector2(rect.position.x + o, rect.end.y - o), rect.end - Vector2(o, o)]:
			_draw_stud(to_canvas_item, c, s)


func _draw_stud(ci: RID, c: Vector2, s: float) -> void:
	var outer := PackedVector2Array([c + Vector2(0, -s - 1.5), c + Vector2(s + 1.5, 0), c + Vector2(0, s + 1.5), c + Vector2(-s - 1.5, 0)])
	RenderingServer.canvas_item_add_polygon(ci, outer, PackedColorArray([Color(0.08, 0.05, 0.02, 0.9)]))
	var inner := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)])
	var lit := stud_color
	var shade := stud_color.darkened(0.45)
	RenderingServer.canvas_item_add_polygon(ci, inner, PackedColorArray([lit.lightened(0.3), lit, shade, lit]))


func _get_draw_rect(rect: Rect2) -> Rect2:
	var grow := float(maxi(shadow_size, glow_size if glow.a > 0.0 else 0)) + 2.0
	return rect.grow(grow)
