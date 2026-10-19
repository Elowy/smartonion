class_name UiTheme
extends RefCounted
## WoW-like UI look (GDD 12): dark stone / leather panels with gold borders, parchment
## tooltips, item-quality colours. Built in code so it needs no imported assets.
##
## get_theme() returns one cached Theme for every screen. Besides the default control types
## it defines type variations (use Control.theme_type_variation):
##   Labels: TitleLabel, HeadingLabel, GoldLabel, DimLabel, SmallLabel, InkLabel, BigNumber
##   Panels: StonePanel (= default), InsetPanel, ParchmentPanel, CardPanel, PlainPanel
## Static helpers build the common widgets (labels, panels, prompts, backdrops).

const GOLD := Color(1.0, 0.82, 0.25)
const TEXT := Color(0.95, 0.92, 0.85)
const TEXT_DIM := Color(0.7, 0.66, 0.6)
const HP_GREEN := Color(0.2, 0.8, 0.25)
const XP_PURPLE := Color(0.58, 0.3, 0.85)
## WoW item quality colours, indexed by rarity (0 Common .. 5 Artifact).
const RARITY_COLORS: Array[Color] = [
	Color(1, 1, 1), Color(0.12, 1.0, 0.0), Color(0.0, 0.44, 0.87),
	Color(0.64, 0.21, 0.93), Color(1.0, 0.5, 0.0), Color(0.9, 0.8, 0.5),
]
const RARITY_NAMES: Array[String] = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact"]

# --- Palette -------------------------------------------------------------------
const GOLD_BRIGHT := Color(1.0, 0.92, 0.6)
const GOLD_BORDER := Color(0.8, 0.62, 0.27)
const GOLD_DARK := Color(0.47, 0.35, 0.15)
const STONE := Color(0.115, 0.1, 0.09, 0.96)
const STONE_LIGHT := Color(0.22, 0.19, 0.165, 0.97)
const STONE_DARK := Color(0.055, 0.047, 0.042, 0.97)
const OUTLINE := Color(0.05, 0.03, 0.015)
const PARCHMENT := Color(0.89, 0.81, 0.63)
const PARCHMENT_EDGE := Color(0.55, 0.4, 0.22)
const INK := Color(0.24, 0.15, 0.07)
const RED := Color(0.96, 0.27, 0.22)
const GREEN := Color(0.42, 0.92, 0.36)
const BACKDROP := Color(0.035, 0.028, 0.03)
## Controller face-button colours (Xbox layout).
const PAD_A := Color(0.36, 0.72, 0.22)
const PAD_B := Color(0.86, 0.22, 0.18)
const PAD_X := Color(0.2, 0.46, 0.92)
const PAD_Y := Color(0.95, 0.74, 0.12)

# --- Font sizes (1920x1080 canvas) ----------------------------------------------
const FONT_SMALL := 18
const FONT_BODY := 22
const FONT_LARGE := 28
const FONT_HEADING := 40
const FONT_TITLE := 72
const FONT_HUGE := 132

# --- Type variations -------------------------------------------------------------
const TITLE := &"TitleLabel"
const HEADING := &"HeadingLabel"
const GOLD_LABEL := &"GoldLabel"
const DIM := &"DimLabel"
const SMALL := &"SmallLabel"
const INK_LABEL := &"InkLabel"
const BIG_NUMBER := &"BigNumber"
const STONE_PANEL := &"StonePanel"
const INSET_PANEL := &"InsetPanel"
const PARCHMENT_PANEL := &"ParchmentPanel"
const CARD_PANEL := &"CardPanel"
const PLAIN_PANEL := &"PlainPanel"

const RESOURCE_NAMES := {
	&"rage": "Rage", &"mana": "Mana", &"energy": "Energy",
	&"holy_power": "Resolve", &"soul_shard": "Pact Shards",
}

static var _theme: Theme
static var _title_font: FontVariation
static var _bold_font: FontVariation


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build_theme()
	return _theme


## The default font, emboldened and slightly spaced – used for titles and numbers.
static func title_font() -> Font:
	if _title_font == null:
		_title_font = FontVariation.new()
		_title_font.base_font = ThemeDB.fallback_font
		_title_font.variation_embolden = 0.75
		_title_font.spacing_glyph = 2
	return _title_font


## The default font, a little bolder – used for names and buttons.
static func bold_font() -> Font:
	if _bold_font == null:
		_bold_font = FontVariation.new()
		_bold_font.base_font = ThemeDB.fallback_font
		_bold_font.variation_embolden = 0.4
	return _bold_font


# --- Styles ----------------------------------------------------------------------

## Dark stone panel with a gold border (the standard WoW frame).
static func stone_style(border: Color = GOLD_BORDER, fill: Color = STONE) -> UiFrameStyle:
	var s := UiFrameStyle.new()
	s.fill = fill
	s.border = border
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	return s.rebuild()


## Darker recessed area inside a panel (bars, lists, stat blocks).
static func inset_style() -> UiFrameStyle:
	var s := UiFrameStyle.new()
	s.fill = STONE_DARK
	s.border = Color(0.3, 0.24, 0.16)
	s.border_width = 1
	s.corner_radius = 4
	s.shadow_size = 0
	s.inner_shadow = 8
	s.inner_shadow_color = Color(0, 0, 0, 0.6)
	s.sheen = 0.0
	s.studs = false
	s.keyline = false
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s.rebuild()


## Parchment (tooltips, the wave-cleared scroll).
static func parchment_style() -> UiFrameStyle:
	var s := UiFrameStyle.new()
	s.fill = PARCHMENT
	s.border = PARCHMENT_EDGE
	s.border_width = 2
	s.corner_radius = 4
	s.shadow_size = 8
	s.inner_shadow = 18
	s.inner_shadow_color = Color(0.45, 0.28, 0.1, 0.45)
	s.sheen = 0.05
	s.studs = false
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s.rebuild()


## Lobby / unit-frame card: stone with an optional coloured border.
static func card_style(border: Color = GOLD_BORDER, fill: Color = STONE) -> UiFrameStyle:
	var s := stone_style(border, fill)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s.rebuild()


static func button_style(state: String) -> UiFrameStyle:
	var s := UiFrameStyle.new()
	s.corner_radius = 5
	s.shadow_size = 6
	s.inner_shadow = 10
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 10
	s.content_margin_bottom = 12
	s.studs = false
	match state:
		"hover":
			s.fill = Color(0.3, 0.2, 0.1, 0.98)
			s.border = GOLD_BRIGHT
			s.sheen = 0.07
		"pressed":
			s.fill = Color(0.07, 0.05, 0.04, 0.98)
			s.border = GOLD
			s.inner_shadow = 16
			s.sheen = 0.0
		"disabled":
			s.fill = Color(0.1, 0.095, 0.09, 0.8)
			s.border = Color(0.32, 0.29, 0.26)
			s.sheen = 0.0
		"focus":
			s.fill = Color(0, 0, 0, 0)
			s.border = GOLD_BRIGHT
			s.border_width = 3
			s.inner_shadow = 0
			s.shadow_size = 0
			s.sheen = 0.0
			s.keyline = false
			s.studs = true
			s.glow = Color(1.0, 0.75, 0.25, 0.55)
			s.glow_size = 14
		"selected":
			# Like hover + focus combined: used by menus driven by one player's input.
			s.fill = Color(0.32, 0.21, 0.1, 0.98)
			s.border = GOLD_BRIGHT
			s.border_width = 3
			s.sheen = 0.08
			s.studs = true
			s.glow = Color(1.0, 0.75, 0.25, 0.5)
			s.glow_size = 14
		_:
			s.fill = Color(0.19, 0.13, 0.08, 0.97)
			s.border = GOLD_BORDER
			s.sheen = 0.05
	return s.rebuild()


static func _flat(bg: Color, border: Color = Color(0, 0, 0, 0), width: int = 0, radius: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


static func _build_theme() -> Theme:
	var t := Theme.new()
	var font := ThemeDB.fallback_font
	t.default_font = font
	t.default_font_size = FONT_BODY

	# Labels: light text with a dark outline and a soft drop shadow.
	t.set_color(&"font_color", &"Label", TEXT)
	t.set_color(&"font_outline_color", &"Label", OUTLINE)
	t.set_color(&"font_shadow_color", &"Label", Color(0, 0, 0, 0.55))
	t.set_constant(&"outline_size", &"Label", 5)
	t.set_constant(&"shadow_offset_x", &"Label", 1)
	t.set_constant(&"shadow_offset_y", &"Label", 2)
	t.set_constant(&"shadow_outline_size", &"Label", 5)
	t.set_font_size(&"font_size", &"Label", FONT_BODY)

	_label_variation(t, TITLE, GOLD, FONT_TITLE, 14, title_font())
	t.set_constant(&"shadow_offset_y", TITLE, 5)
	t.set_constant(&"shadow_outline_size", TITLE, 14)
	t.set_color(&"font_shadow_color", TITLE, Color(0, 0, 0, 0.7))
	_label_variation(t, HEADING, GOLD, FONT_HEADING, 9, title_font())
	_label_variation(t, GOLD_LABEL, GOLD, FONT_LARGE, 6, bold_font())
	_label_variation(t, DIM, TEXT_DIM, FONT_BODY, 4, null)
	_label_variation(t, SMALL, TEXT_DIM, FONT_SMALL, 4, null)
	_label_variation(t, BIG_NUMBER, TEXT, 64, 10, title_font())
	_label_variation(t, INK_LABEL, INK, FONT_BODY, 0, bold_font())
	t.set_color(&"font_shadow_color", INK_LABEL, Color(1, 1, 1, 0.25))
	t.set_constant(&"shadow_outline_size", INK_LABEL, 0)
	t.set_constant(&"shadow_offset_y", INK_LABEL, 1)

	# RichTextLabel (descriptions).
	t.set_color(&"default_color", &"RichTextLabel", TEXT)
	t.set_color(&"font_outline_color", &"RichTextLabel", OUTLINE)
	t.set_constant(&"outline_size", &"RichTextLabel", 4)
	t.set_font_size(&"normal_font_size", &"RichTextLabel", FONT_BODY)
	t.set_font_size(&"bold_font_size", &"RichTextLabel", FONT_BODY)
	t.set_font(&"bold_font", &"RichTextLabel", bold_font())

	# Panels.
	var stone := stone_style()
	t.set_stylebox(&"panel", &"Panel", stone)
	t.set_stylebox(&"panel", &"PanelContainer", stone)
	_panel_variation(t, STONE_PANEL, stone)
	_panel_variation(t, INSET_PANEL, inset_style())
	_panel_variation(t, PARCHMENT_PANEL, parchment_style())
	_panel_variation(t, CARD_PANEL, card_style())
	_panel_variation(t, PLAIN_PANEL, StyleBoxEmpty.new())

	# Buttons.
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(StringName(state), &"Button", button_style(state))
	t.set_stylebox(&"hover_pressed", &"Button", button_style("pressed"))
	t.set_font(&"font", &"Button", title_font())
	t.set_font_size(&"font_size", &"Button", 30)
	t.set_color(&"font_color", &"Button", TEXT)
	t.set_color(&"font_hover_color", &"Button", GOLD_BRIGHT)
	t.set_color(&"font_focus_color", &"Button", GOLD_BRIGHT)
	t.set_color(&"font_pressed_color", &"Button", GOLD)
	t.set_color(&"font_hover_pressed_color", &"Button", GOLD)
	t.set_color(&"font_disabled_color", &"Button", Color(0.45, 0.42, 0.38))
	t.set_color(&"font_outline_color", &"Button", OUTLINE)
	t.set_constant(&"outline_size", &"Button", 7)
	t.set_constant(&"h_separation", &"Button", 10)

	# Progress bars: dark recessed trough, flat coloured fill.
	t.set_stylebox(&"background", &"ProgressBar", _flat(Color(0.04, 0.035, 0.03, 0.92), Color(0.32, 0.25, 0.14), 1, 3))
	t.set_stylebox(&"fill", &"ProgressBar", _flat(HP_GREEN, Color(0, 0, 0, 0), 0, 2))
	t.set_color(&"font_color", &"ProgressBar", TEXT)
	t.set_color(&"font_outline_color", &"ProgressBar", OUTLINE)
	t.set_constant(&"outline_size", &"ProgressBar", 4)
	t.set_font_size(&"font_size", &"ProgressBar", FONT_SMALL)

	# Parchment tooltips with dark ink.
	t.set_stylebox(&"panel", &"TooltipPanel", parchment_style())
	t.set_color(&"font_color", &"TooltipLabel", INK)
	t.set_color(&"font_outline_color", &"TooltipLabel", Color(0, 0, 0, 0))
	t.set_constant(&"outline_size", &"TooltipLabel", 0)
	t.set_font_size(&"font_size", &"TooltipLabel", FONT_SMALL)

	# Separators: thin gold rule.
	var rule := StyleBoxLine.new()
	rule.color = Color(GOLD_BORDER, 0.55)
	rule.thickness = 2
	t.set_stylebox(&"separator", &"HSeparator", rule)
	t.set_constant(&"separation", &"HSeparator", 10)

	t.set_constant(&"separation", &"VBoxContainer", 8)
	t.set_constant(&"separation", &"HBoxContainer", 10)
	return t


static func _label_variation(t: Theme, type: StringName, color: Color, size: int, outline: int, font: Font) -> void:
	t.set_type_variation(type, &"Label")
	t.set_color(&"font_color", type, color)
	t.set_font_size(&"font_size", type, size)
	t.set_constant(&"outline_size", type, outline)
	if font != null:
		t.set_font(&"font", type, font)


static func _panel_variation(t: Theme, type: StringName, style: StyleBox) -> void:
	t.set_type_variation(type, &"PanelContainer")
	t.set_stylebox(&"panel", type, style)


# --- Widget helpers ------------------------------------------------------------------

## A Label using one of the label type variations ([constant TITLE], [constant DIM] ...).
## [param size] > 0 and a non-transparent [param color] override the variation.
static func label(text: String, variation: StringName = &"", size: int = 0, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size > 0:
		l.add_theme_font_size_override(&"font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override(&"font_color", color)
	return l


## A centred label (horizontal and vertical).
static func centered_label(text: String, variation: StringName = &"", size: int = 0, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := label(text, variation, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## A word-wrapping label (descriptions).
static func wrapped_label(text: String, variation: StringName = &"", size: int = 0, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := label(text, variation, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 40
	return l


static func panel(variation: StringName = STONE_PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func vbox(separation: int = 8) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override(&"separation", separation)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func hbox(separation: int = 10) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override(&"separation", separation)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## A flexible empty control that pushes its siblings apart.
static func spacer(vertical: bool = false) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## A decorative gold rule with a diamond in the middle.
static func divider(width: float = 0.0) -> UiIcon:
	var d := UiIcon.create(UiIcon.Kind.DIVIDER, Vector2(maxf(width, 40.0), 16.0))
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL if width <= 0.0 else Control.SIZE_SHRINK_CENTER
	return d


## A row of button prompts, e.g. prompt_row([[UiGlyph.pad(A), "Ready"], [UiGlyph.pad(B), "Leave"]]).
static func prompt_row(items: Array, font_size: int = FONT_BODY, color: Color = TEXT) -> HBoxContainer:
	var row := hbox(22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for item: Array in items:
		var pair := hbox(8)
		for part: Variant in item:
			if part is Control:
				var c := part as Control
				c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				pair.add_child(c)
			else:
				pair.add_child(label(str(part), &"", font_size, color))
		row.add_child(pair)
	return row


## Full-rect dark backdrop with a vignette. [param alpha] < 1 lets the game show through.
static func backdrop(alpha: float = 1.0, glow: Color = Color(0.32, 0.2, 0.1)) -> TextureRect:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.42)
	tex.fill_to = Vector2(1.15, 1.1)
	tex.width = 256
	tex.height = 256
	var g := Gradient.new()
	g.set_color(0, Color(glow.lerp(BACKDROP, 0.35), alpha * 0.92))
	g.set_color(1, Color(BACKDROP, alpha))
	g.add_point(0.55, Color(glow.lerp(BACKDROP, 0.75), alpha * 0.96))
	tex.gradient = g
	var r := TextureRect.new()
	r.name = "Backdrop"
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return r


## Makes [param c] a full-rect root control that uses the shared theme.
static func setup_root(c: Control) -> void:
	c.theme = get_theme()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


# --- Text helpers ------------------------------------------------------------------

static func resource_name(resource_type: StringName) -> String:
	return RESOURCE_NAMES.get(resource_type, String(resource_type).capitalize())


## 12345 -> "12,345"
static func format_int(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


## HP-style number: whole numbers without decimals.
static func format_amount(value: float) -> String:
	return str(int(ceilf(value - 0.001))) if value > 0.0 else "0"


## Seconds left -> "42" (or "1:05" from a minute up).
static func format_time(seconds: float) -> String:
	var s := int(ceilf(maxf(seconds, 0.0) - 0.001))
	return "%d:%02d" % [int(s / 60.0), s % 60] if s >= 60 else str(s)


## Short device name for prompts and cards.
static func device_label(input: PlayerInput) -> String:
	return input.get_device_name() if input != null else ""
