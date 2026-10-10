class_name UiGlyph
extends Control
## Button prompt glyph drawn in code (GDD 11: Xbox naming): coloured face buttons (A B X Y),
## a START / BACK pill, keyboard key caps ("Enter", "Esc") and a left / right navigation pair.
## for_input() picks the right look for a player's device (keyboard -> key caps).

enum Style { PAD, PILL, KEY, NAV, NAV_VERTICAL }

const DARK := Color(0.06, 0.04, 0.03)

var text := "A"
var style := Style.PAD
var color := UiTheme.PAD_A
var glyph_height := 30.0
## 0..1 brightness pulse (animated prompts); set by the owner.
var pulse := 0.0


static func pad(button: PlayerInput.Pad, height: float = 30.0) -> UiGlyph:
	var g := _make(height)
	match button:
		PlayerInput.Pad.A:
			g.text = "A"
			g.color = UiTheme.PAD_A
		PlayerInput.Pad.B:
			g.text = "B"
			g.color = UiTheme.PAD_B
		PlayerInput.Pad.X:
			g.text = "X"
			g.color = UiTheme.PAD_X
		PlayerInput.Pad.Y:
			g.text = "Y"
			g.color = UiTheme.PAD_Y
		PlayerInput.Pad.START, PlayerInput.Pad.SELECT:
			g.style = Style.PILL
			g.text = "START" if button == PlayerInput.Pad.START else "BACK"
			g.color = Color(0.32, 0.31, 0.3)
		PlayerInput.Pad.LB, PlayerInput.Pad.RB, PlayerInput.Pad.LT, PlayerInput.Pad.RT:
			g.style = Style.PILL
			g.text = String(PlayerInput.Pad.keys()[button])
			g.color = Color(0.32, 0.31, 0.3)
		_:
			g.style = Style.NAV
	g._update_size()
	return g


## A keyboard key cap with [param key_text] on it.
static func key(key_text: String, height: float = 30.0) -> UiGlyph:
	var g := _make(height)
	g.style = Style.KEY
	g.text = key_text
	g.color = Color(0.82, 0.78, 0.7)
	g._update_size()
	return g


## ◀ ▶ (or ▲ ▼ with [param vertical]) – stick / d-pad / arrow keys.
static func nav(height: float = 30.0, vertical: bool = false) -> UiGlyph:
	var g := _make(height)
	g.style = Style.NAV_VERTICAL if vertical else Style.NAV
	g.text = ""
	g.color = UiTheme.GOLD
	g._update_size()
	return g


## The glyph for [param button] on [param input]'s device: key caps for the keyboard,
## coloured buttons for controllers (and bots / tests).
static func for_input(input: PlayerInput, button: PlayerInput.Pad, height: float = 30.0) -> UiGlyph:
	if input is KeyboardInput:
		return key(keyboard_name(button), height)
	return pad(button, height)


## Key that maps to [param button] for KeyboardInput (see core/input/keyboard_input.gd).
static func keyboard_name(button: PlayerInput.Pad) -> String:
	match button:
		PlayerInput.Pad.A:
			return "Enter"
		PlayerInput.Pad.B:
			return "Esc"
		PlayerInput.Pad.X:
			return "R"
		PlayerInput.Pad.Y:
			return "C"
		PlayerInput.Pad.LB:
			return "Q"
		PlayerInput.Pad.RB:
			return "E"
		PlayerInput.Pad.START:
			return "P"
		PlayerInput.Pad.SELECT, PlayerInput.Pad.R3:
			return "Tab"
	return "?"


static func _make(height: float) -> UiGlyph:
	var g := UiGlyph.new()
	g.glyph_height = height
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return g


func set_pulse(value: float) -> void:
	if not is_equal_approx(value, pulse):
		pulse = value
		queue_redraw()


func _font_size() -> int:
	match style:
		Style.PAD:
			return int(glyph_height * 0.62)
		Style.PILL:
			return int(glyph_height * 0.4)
		_:
			return int(glyph_height * 0.5)


func _update_size() -> void:
	var h := glyph_height
	match style:
		Style.PAD:
			custom_minimum_size = Vector2(h, h)
		Style.NAV:
			custom_minimum_size = Vector2(h * 1.5, h)
		Style.NAV_VERTICAL:
			custom_minimum_size = Vector2(h * 0.75, h)
		_:
			var w := UiTheme.bold_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x
			custom_minimum_size = Vector2(maxf(h, w + h * 0.6), h)
	update_minimum_size()
	queue_redraw()


func _draw() -> void:
	var h := glyph_height
	var c := size * 0.5
	var lit := color.lerp(Color.WHITE, pulse * 0.35)
	match style:
		Style.PAD:
			var r := h * 0.5 - 1.0
			draw_circle(c + Vector2(0, 1.5), r, Color(0, 0, 0, 0.5))
			draw_circle(c, r, DARK)
			draw_circle(c, r - 2.0, lit.darkened(0.3))
			draw_circle(c + Vector2(0, -1.0), r - 3.0, lit)
			draw_arc(c + Vector2(0, -1.0), r - 5.0, PI * 1.1, PI * 1.9, 12, Color(1, 1, 1, 0.35), maxf(1.0, h * 0.06), true)
			_text(c + Vector2(0, -0.5), Color.WHITE)
		Style.PILL, Style.KEY:
			var rect := Rect2(Vector2(0, (size.y - h) * 0.5), Vector2(size.x, h)).grow(-1.0)
			var radius := int(h * 0.5) if style == Style.PILL else 5
			var face := StyleBoxFlat.new()
			face.set_corner_radius_all(radius)
			face.bg_color = lit if style == Style.KEY else lit.darkened(0.1)
			face.border_color = DARK
			face.set_border_width_all(2)
			face.border_width_bottom = 4 if style == Style.KEY else 2
			face.anti_aliasing = true
			face.shadow_color = Color(0, 0, 0, 0.45)
			face.shadow_size = 2
			face.shadow_offset = Vector2(0, 1.5)
			draw_style_box(face, rect)
			draw_rect(Rect2(rect.position + Vector2(4, 3), Vector2(rect.size.x - 8, rect.size.y * 0.3)), Color(1, 1, 1, 0.16))
			_text(c + Vector2(0, -1.0 if style == Style.KEY else 0.0), DARK if style == Style.KEY else Color.WHITE)
		Style.NAV:
			_triangle(Vector2(h * 0.38, c.y), -1.0, h * 0.36, lit)
			_triangle(Vector2(size.x - h * 0.38, c.y), 1.0, h * 0.36, lit)
		Style.NAV_VERTICAL:
			_triangle_v(Vector2(c.x, h * 0.25), -1.0, h * 0.26, lit)
			_triangle_v(Vector2(c.x, size.y - h * 0.25), 1.0, h * 0.26, lit)


func _text(center: Vector2, col: Color) -> void:
	var font := UiTheme.bold_font()
	var fs := _font_size()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(center.x - w * 0.5, center.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	if col != DARK:
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.6))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _triangle(center: Vector2, dir: float, s: float, col: Color) -> void:
	var tip := center + Vector2(dir * s * 0.55, 0)
	var top := center + Vector2(-dir * s * 0.45, -s * 0.62)
	var bottom := center + Vector2(-dir * s * 0.45, s * 0.62)
	var grow := 2.5
	draw_colored_polygon(PackedVector2Array([tip + Vector2(dir * grow * 1.6, 0), top + Vector2(-dir * grow, -grow * 1.4),
		bottom + Vector2(-dir * grow, grow * 1.4)]), DARK)
	draw_polygon(PackedVector2Array([tip, top, bottom]), PackedColorArray([col.lightened(0.2), col.lightened(0.3), col.darkened(0.3)]))


func _triangle_v(center: Vector2, dir: float, s: float, col: Color) -> void:
	var tip := center + Vector2(0, dir * s * 0.55)
	var left := center + Vector2(-s * 0.62, -dir * s * 0.45)
	var right := center + Vector2(s * 0.62, -dir * s * 0.45)
	var grow := 2.5
	draw_colored_polygon(PackedVector2Array([tip + Vector2(0, dir * grow * 1.6), left + Vector2(-grow * 1.4, -dir * grow),
		right + Vector2(grow * 1.4, -dir * grow)]), DARK)
	draw_polygon(PackedVector2Array([tip, left, right]), PackedColorArray([col.darkened(0.2), col.lightened(0.3), col]))
