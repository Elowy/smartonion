class_name DifficultyBadge
extends PanelContainer
## A small pill in a tier's colour (M9): "PUNGENT" / "TEAR-JERKER" on the lobby header, the HUD plaque, the end screen
## and the run card; the same pill shows the wave's Tear-Jerker pressure on the HUD ([method show_text]). Like the
## HARDCORE badge it is hidden-agnostic: the owner sets [member visible]. Normal has no badge of its own (the default
## run shows nothing extra): [method show_tier] hides it.

var label: Label
var tier_id: StringName = &""

var _font_size := UiTheme.FONT_SMALL


## A badge with its text at [param font_size].
static func create(font_size: int = UiTheme.FONT_SMALL) -> DifficultyBadge:
	var b := DifficultyBadge.new()
	b.name = "DifficultyBadge"
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b._font_size = font_size
	b.label = UiTheme.centered_label("", UiTheme.HEADING, font_size, UiTheme.TEXT)
	b.add_child(b.label)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.visible = false
	return b


## Shows tier [param id] ("PUNGENT" in amber ...); Normal and unknown ids hide the badge. Returns true when it shows.
func show_tier(id: StringName) -> bool:
	tier_id = id
	if Difficulty.tier_index(id) <= 0:
		visible = false
		return false
	show_text(Difficulty.name_of(id), Difficulty.color_of(id))
	return true


## Shows [param text] in [param color] (the pressure chip).
func show_text(text: String, color: Color) -> void:
	label.text = text.to_upper()
	label.add_theme_color_override(&"font_color", color.lightened(0.3))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.darkened(0.78), 0.94)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(maxi(4, roundi(_font_size / 3.0)))
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 3.0
	style.anti_aliasing = true
	add_theme_stylebox_override(&"panel", style)
	visible = true
