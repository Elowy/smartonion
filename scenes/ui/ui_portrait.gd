class_name UiPortrait
extends Control
## Circular unit-frame portrait (GDD 12): a ring in the player's colour inside a gold rim,
## the class onion's face on a dark backdrop, and a badge with the class initial.
## Downed: greyed out with a red tint.

var player_color := Color(0.25, 0.55, 1.0)
var skin_color := Color(0.72, 0.4, 0.62)
var initial := "W"
var downed := false
## 0..1 red flash when hit.
var hit_flash := 0.0


static func create(p_size: float = 96.0) -> UiPortrait:
	var p := UiPortrait.new()
	p.custom_minimum_size = Vector2(p_size, p_size)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


func setup(p_player_color: Color, data: ClassData) -> void:
	player_color = p_player_color
	if data != null:
		skin_color = data.onion_color
		initial = data.display_name.substr(0, 1).to_upper() if data.display_name != "" else "?"
	queue_redraw()


func set_downed(value: bool) -> void:
	if downed != value:
		downed = value
		queue_redraw()


func flash_hit() -> void:
	hit_flash = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	if hit_flash > 0.0:
		hit_flash = maxf(0.0, hit_flash - delta * 3.0)
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 2.0
	var ring := player_color if not downed else player_color.lerp(Color(0.4, 0.4, 0.4), 0.6)
	draw_circle(c + Vector2(0, 3), r + 1.0, Color(0, 0, 0, 0.5))
	draw_circle(c, r, UiTheme.OUTLINE)
	draw_circle(c, r - 1.5, UiTheme.GOLD_BORDER)
	draw_circle(c, r - 4.0, UiTheme.OUTLINE)
	draw_circle(c, r - 5.5, ring.darkened(0.15))
	var inner_r := r - 10.0
	draw_circle(c, inner_r, Color(0.07, 0.06, 0.07))
	# Radial backdrop glow in the player colour.
	for i in 6:
		var t := float(i) / 6.0
		draw_circle(c + Vector2(0, -inner_r * 0.15 * t), inner_r * (1.0 - t * 0.55), Color(ring.darkened(0.55), 0.18 + t * 0.06))
	var skin := skin_color if not downed else Color(0.55, 0.6, 0.7)
	var onion_rect := Rect2(c - Vector2(inner_r * 0.82, inner_r * 0.62), Vector2(inner_r * 1.64, inner_r * 1.72))
	UiIcon.draw_onion(self, onion_rect, skin, false, true)
	if downed:
		draw_circle(c, inner_r, Color(0.35, 0.05, 0.05, 0.45))
	if hit_flash > 0.0:
		draw_circle(c, inner_r, Color(1.0, 0.15, 0.1, hit_flash * 0.45))
	# Clean the rim (the onion may poke over the inner circle).
	draw_arc(c, inner_r + 2.5, 0.0, TAU, 48, ring.darkened(0.15), 5.0, true)
	draw_arc(c, r - 4.0, 0.0, TAU, 48, UiTheme.OUTLINE, 1.5, true)
	# Class initial badge.
	var badge_r := r * 0.27
	var b := c + Vector2(r * 0.68, r * 0.68)
	draw_circle(b, badge_r + 2.0, UiTheme.OUTLINE)
	draw_circle(b, badge_r, UiTheme.GOLD_BORDER)
	draw_circle(b, badge_r - 2.5, Color(0.16, 0.11, 0.07))
	var font := UiTheme.title_font()
	var fs := int(badge_r * 1.3)
	var w := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(b.x - w * 0.5, b.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	draw_string_outline(font, pos, initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, UiTheme.OUTLINE)
	draw_string(font, pos, initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.GOLD)
