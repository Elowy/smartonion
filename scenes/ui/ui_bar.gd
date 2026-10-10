class_name UiBar
extends Control
## WoW-style status bar drawn in code: recessed trough, glossy coloured fill, a pale "lost"
## chunk that trails behind when the value drops, optional segment ticks (XP bar) and
## centred outlined text.

var value := 1.0
var max_value := 1.0
var fill_color := UiTheme.HP_GREEN
var text := ""
var font_size := UiTheme.FONT_SMALL
## > 1 draws that many segments (WoW XP bar has 20).
var segments := 0
## false = jump straight to the value (no easing).
var animated := true
## 0..1 white flash over the fill (level up, heal).
var flash := 0.0

var _shown := 1.0
var _trail := 1.0
var _trail_hold := 0.0


static func create(p_fill: Color, p_height: float = 24.0, p_font_size: int = UiTheme.FONT_SMALL) -> UiBar:
	var bar := UiBar.new()
	bar.fill_color = p_fill
	bar.font_size = p_font_size
	bar.custom_minimum_size = Vector2(60, p_height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return bar


func ratio() -> float:
	return clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0


## Sets value / max and the label. Drops leave a trailing chunk; rises ease in.
func set_values(p_value: float, p_max: float, p_text: String = "") -> void:
	var old := ratio()
	value = p_value
	max_value = p_max
	text = p_text
	var r := ratio()
	if not animated or not is_inside_tree():
		_shown = r
		_trail = r
	elif r < old:
		_shown = r
		_trail = maxf(_trail, old)
		_trail_hold = 0.35
	queue_redraw()


func set_text(p_text: String) -> void:
	if p_text != text:
		text = p_text
		queue_redraw()


func set_fill_color(c: Color) -> void:
	fill_color = c
	queue_redraw()


## Displayed fill (0..1) after easing.
func shown_ratio() -> float:
	return _shown


func _process(delta: float) -> void:
	var r := ratio()
	var dirty := false
	if not is_equal_approx(_shown, r):
		_shown = move_toward(_shown, r, maxf(0.6 * delta, absf(r - _shown) * minf(1.0, 8.0 * delta)))
		dirty = true
	if _trail > _shown:
		_trail_hold -= delta
		if _trail_hold <= 0.0:
			_trail = maxf(_shown, _trail - delta * 0.9)
		dirty = true
	elif _trail < _shown:
		_trail = _shown
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 2.0)
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	# Trough.
	var trough := StyleBoxFlat.new()
	trough.bg_color = Color(0.03, 0.025, 0.02, 0.92)
	trough.border_color = Color(0.0, 0.0, 0.0, 0.9)
	trough.set_border_width_all(1)
	trough.set_corner_radius_all(3)
	trough.shadow_color = Color(0, 0, 0, 0.35)
	trough.shadow_size = 3
	draw_style_box(trough, rect)
	var inner := rect.grow(-2.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	# Faint empty-bar tint so the colour reads even when empty.
	draw_rect(inner, Color(fill_color.darkened(0.75), 0.6))
	if _trail > _shown:
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * _trail, inner.size.y)), Color(1.0, 0.95, 0.8, 0.55))
	var w := inner.size.x * _shown
	if w > 0.5:
		var fill := Rect2(inner.position, Vector2(w, inner.size.y))
		var top := fill_color.lightened(0.25)
		var bottom := fill_color.darkened(0.3)
		draw_polygon(PackedVector2Array([fill.position, Vector2(fill.end.x, fill.position.y), fill.end, Vector2(fill.position.x, fill.end.y)]),
			PackedColorArray([top, top, bottom, bottom]))
		draw_rect(Rect2(fill.position + Vector2(0, 1), Vector2(fill.size.x, maxf(1.0, fill.size.y * 0.32))), Color(1, 1, 1, 0.2))
		draw_rect(Rect2(Vector2(fill.end.x - 1.5, fill.position.y), Vector2(1.5, fill.size.y)), Color(1, 1, 1, 0.35))
		if flash > 0.0:
			draw_rect(fill, Color(1, 1, 1, flash * 0.6))
	if segments > 1:
		for i in range(1, segments):
			var x := inner.position.x + inner.size.x * float(i) / float(segments)
			draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(0, 0, 0, 0.55), 2.0)
			draw_line(Vector2(x + 1.5, inner.position.y), Vector2(x + 1.5, inner.end.y), Color(1, 1, 1, 0.06), 1.0)
	# Frame line on top.
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.border_color = Color(UiTheme.GOLD_DARK, 0.9)
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(3)
	draw_style_box(frame, rect)
	if text != "":
		var font := UiTheme.bold_font()
		var fs := font_size
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2((size.x - tw) * 0.5, size.y * 0.5 + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, UiTheme.OUTLINE)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT)
