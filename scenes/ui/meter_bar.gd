class_name MeterBar
extends Control
## One bar of the Damage Meter (end screen, M6 METER): a recessed trough, a fill in the hero's
## class colour as long as value / best value, a slim swatch in the player's colour on the left,
## the hero's name on the left and the value on the right (outlined text over the fill). Drawn in
## code like [UiBar]; static (no easing), a value of 0 is drawn dimmed.

var label_text := ""
var value_text := ""
## 0..1 – the fill's share of the bar (value / the best value of the stat).
var ratio := 0.0
var fill_color := Color(0.6, 0.6, 0.65)
var swatch_color := Color.WHITE
var font_size := UiTheme.FONT_SMALL
## The value is 0: the bar is empty and its text dimmed.
var dimmed := false

const SWATCH_WIDTH := 6.0
const TEXT_MARGIN := 10.0
## A bar with a value shows at least this much fill (so a small number still reads).
const MIN_FILL := 6.0


static func create(p_height: float = 30.0, p_font_size: int = UiTheme.FONT_SMALL) -> MeterBar:
	var bar := MeterBar.new()
	bar.font_size = p_font_size
	bar.custom_minimum_size = Vector2(60.0, p_height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return bar


## Sets everything at once and redraws.
func setup(p_label: String, p_value_text: String, p_ratio: float, p_fill: Color, p_swatch: Color,
		p_dimmed: bool = false) -> void:
	label_text = p_label
	value_text = p_value_text
	ratio = clampf(p_ratio, 0.0, 1.0)
	fill_color = p_fill
	swatch_color = p_swatch
	dimmed = p_dimmed
	queue_redraw()


## Width in pixels of the filled part for a bar [param width] wide.
func fill_width(width: float) -> float:
	var inner := width - 2.0 - SWATCH_WIDTH
	if dimmed or ratio <= 0.0 or inner <= 0.0:
		return 0.0
	return clampf(inner * ratio, minf(MIN_FILL, inner), inner)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var trough := StyleBoxFlat.new()
	trough.bg_color = Color(0.03, 0.025, 0.02, 0.92)
	trough.border_color = Color(0.0, 0.0, 0.0, 0.9)
	trough.set_border_width_all(1)
	trough.set_corner_radius_all(3)
	draw_style_box(trough, rect)
	var inner := rect.grow(-1.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var alpha := 0.45 if dimmed else 1.0
	draw_rect(Rect2(inner.position, Vector2(SWATCH_WIDTH, inner.size.y)), Color(swatch_color, alpha))
	var w := fill_width(size.x)
	if w > 0.5:
		var fill := Rect2(inner.position + Vector2(SWATCH_WIDTH, 0.0), Vector2(w, inner.size.y))
		var top := fill_color.lightened(0.2)
		var bottom := fill_color.darkened(0.35)
		draw_polygon(PackedVector2Array([fill.position, Vector2(fill.end.x, fill.position.y), fill.end,
				Vector2(fill.position.x, fill.end.y)]), PackedColorArray([top, top, bottom, bottom]))
		draw_rect(Rect2(fill.position + Vector2(0, 1), Vector2(fill.size.x, maxf(1.0, fill.size.y * 0.3))),
				Color(1, 1, 1, 0.16))
		draw_rect(Rect2(Vector2(fill.end.x - 1.5, fill.position.y), Vector2(1.5, fill.size.y)), Color(1, 1, 1, 0.3))
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.border_color = Color(UiTheme.GOLD_DARK, 0.8)
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(3)
	draw_style_box(frame, rect)
	var font := UiTheme.bold_font()
	var base_y := size.y * 0.5 + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var color := UiTheme.TEXT_DIM if dimmed else UiTheme.TEXT
	if label_text != "":
		var pos := Vector2(SWATCH_WIDTH + TEXT_MARGIN, base_y)
		draw_string_outline(font, pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, UiTheme.OUTLINE)
		draw_string(font, pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	if value_text != "":
		var tw := font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var pos := Vector2(size.x - TEXT_MARGIN - tw, base_y)
		draw_string_outline(font, pos, value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, UiTheme.OUTLINE)
		draw_string(font, pos, value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
