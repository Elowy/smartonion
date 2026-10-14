class_name DustIcon
extends Control
## The Arcane Dust mark (GDD 5.7): a small four-pointed violet sparkle, drawn in code like the
## coin (the UI font has no star glyph, so the "✦" of the tab label and the purse board is this).
## [constant COLOR] / [constant COLOR_BRIGHT] are also the colour of every Dust number and the
## "Dust" word in the Enchanter tab, the purse board and the loot messages.

const COLOR := Color(0.7, 0.58, 1.0)
const COLOR_BRIGHT := Color(0.85, 0.77, 1.0)
const COLOR_DARK := Color(0.28, 0.17, 0.5)
const OUTLINE := Color(0.1, 0.05, 0.18)
## Inner radius of the sparkle's waist, as a share of its outer radius.
const WAIST := 0.3

## Whether the sparkle is dimmed (nothing to spend).
var dim := false


static func create(p_size: float = 20.0) -> DustIcon:
	var icon := DustIcon.new()
	icon.custom_minimum_size = Vector2(p_size, p_size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.name = "DustIcon"
	return icon


func set_dim(on: bool) -> void:
	if on != dim:
		dim = on
		queue_redraw()


## "12 Dust" for plain texts.
static func text(amount: int) -> String:
	return "%d Dust" % amount


## "12 Dust" in the Dust colour, for RichTextLabels.
static func bbcode(amount: int) -> String:
	return "[color=#%s]%d Dust[/color]" % [COLOR_BRIGHT.to_html(false), amount]


## The sparkle's outline points around [param c]: [param r] outer radius, waist at r x WAIST.
static func star(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 8:
		var a := -PI * 0.5 + i * PI / 4.0
		var rad := r if i % 2 == 0 else r * WAIST
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	return pts


func _draw() -> void:
	var s := minf(size.x, size.y)
	if s < 4.0:
		return
	var c := size * 0.5
	var main := COLOR.darkened(0.45) if dim else COLOR
	var bright := COLOR_BRIGHT.darkened(0.45) if dim else COLOR_BRIGHT
	draw_colored_polygon(star(c + Vector2(0, 0.8), s * 0.5), Color(OUTLINE, 0.8))
	draw_colored_polygon(star(c, s * 0.47), COLOR_DARK)
	draw_colored_polygon(star(c, s * 0.4), main)
	draw_colored_polygon(star(c, s * 0.2), bright)
	# A small second sparkle, up and to the right.
	var c2 := c + Vector2(s * 0.3, -s * 0.28)
	draw_colored_polygon(star(c2, s * 0.15), bright)
