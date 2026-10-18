class_name HardcoreBadge
extends PanelContainer
## The HARDCORE badge (M6b MODES): a small red pill – dark red fill, red border, bright red lettering – that
## marks a hardcore run (no Spirit Healer, only a teammate can revive). The lobby header, the HUD plaque
## and the end screen show it next to the mode; it is built hidden-agnostic: the owner sets [member visible].

const TEXT := "HARDCORE"
const FILL := Color(0.3, 0.05, 0.04, 0.94)
const BORDER := Color(0.88, 0.22, 0.16)
const TEXT_COLOR := Color(1.0, 0.52, 0.44)

var label: Label


## A badge with its text at [param font_size] (the HUD one is small, the lobby's larger).
static func create(font_size: int = UiTheme.FONT_SMALL) -> HardcoreBadge:
	var b := HardcoreBadge.new()
	b.name = "HardcoreBadge"
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = FILL
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(maxi(4, roundi(font_size / 3.0)))
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 3.0
	style.anti_aliasing = true
	b.add_theme_stylebox_override(&"panel", style)
	b.label = UiTheme.centered_label(TEXT, UiTheme.HEADING, font_size, TEXT_COLOR)
	b.add_child(b.label)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b
