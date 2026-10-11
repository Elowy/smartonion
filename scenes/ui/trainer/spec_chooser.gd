class_name SpecChooser
extends Control
## Rank V specialisation choice (GDD 6.3) over the Trainer tab: the ability's icon and name, its
## two AbilityData.specs side by side as cards (name in orange, what it changes), the picked card
## outlined in the player's colour; left / right picks, A confirms, B decides later (the Trainer
## row then reads "Choose"; the panel's prompt row shows the buttons). Only draws – TrainerTab
## drives it.

const CARD_GAP := 12
const SPEC_COLOR := AbilityIcon.RANK_SPEC_COLOR

var ability: AbilityData
## Index of the highlighted card (0 / 1).
var choice := 0
var accent := UiTheme.GOLD
var cards: Array[PanelContainer] = []
var title_label: Label
var name_labels: Array[Label] = []
var text_labels: Array[Label] = []

var _icon: AbilityIcon
var _ability_label: Label
var _cards_row: HBoxContainer


static func create() -> SpecChooser:
	var c := SpecChooser.new()
	c.name = "SpecChooser"
	c._build()
	return c


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 8
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.015, 0.01, 0.78)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fs := UiTheme.stone_style(SPEC_COLOR.darkened(0.2), Color(0.08, 0.065, 0.05, 0.97))
	fs.content_margin_left = 14
	fs.content_margin_right = 14
	fs.content_margin_top = 8
	fs.content_margin_bottom = 8
	frame.add_theme_stylebox_override(&"panel", fs.rebuild())
	add_child(frame)
	var col := UiTheme.vbox(6)
	frame.add_child(col)
	var head := UiTheme.hbox(10)
	_icon = AbilityIcon.create(44.0, false)
	_icon.show_prompt = false
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_icon)
	var titles := UiTheme.vbox(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label = UiTheme.label("Rank V: choose a specialization", &"", 20, SPEC_COLOR)
	title_label.add_theme_font_override(&"font", UiTheme.bold_font())
	titles.add_child(title_label)
	_ability_label = UiTheme.label("", UiTheme.GOLD_LABEL, 24)
	titles.add_child(_ability_label)
	head.add_child(titles)
	col.add_child(head)
	_cards_row = UiTheme.hbox(CARD_GAP)
	_cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_cards_row)
	for i in 2:
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_stretch_ratio = 1.0
		var box := UiTheme.vbox(4)
		card.add_child(box)
		var n := UiTheme.label("", &"", 21, SPEC_COLOR)
		n.add_theme_font_override(&"font", UiTheme.bold_font())
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.custom_minimum_size.x = 60
		box.add_child(n)
		var t := UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL, UiTheme.TEXT)
		t.max_lines_visible = 6
		box.add_child(t)
		_cards_row.add_child(card)
		cards.append(card)
		name_labels.append(n)
		text_labels.append(t)
	visible = false


## Shows the two specialisations of [param a], outlined in [param color].
func open(a: AbilityData, color: Color) -> void:
	ability = a
	accent = color
	choice = 0
	_icon.set_ability(a)
	_icon.set_rank(AbilityRanks.MAX_RANK)
	_ability_label.text = a.display_name if a != null else ""
	for i in 2:
		var spec: Dictionary = a.specs[i] if a != null and i < a.specs.size() else {}
		name_labels[i].text = str(spec.get("name", "Specialization %d" % (i + 1)))
		text_labels[i].text = str(spec.get("text", ""))
	visible = true
	_update_cards()


func close() -> void:
	visible = false
	ability = null


func is_open() -> bool:
	return visible and ability != null


func set_choice(index: int) -> void:
	choice = clampi(index, 0, 1)
	_update_cards()


func _update_cards() -> void:
	for i in cards.size():
		var on := i == choice
		var s := UiTheme.card_style(accent.lightened(0.25) if on else Color(0.3, 0.26, 0.21), Color(0.3, 0.19, 0.08, 0.98) if on else Color(0.06, 0.05, 0.045, 0.95))
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 8
		s.content_margin_bottom = 8
		if on:
			s.border_width = 3
			s.glow = Color(accent, 0.45)
			s.glow_size = 10
		cards[i].add_theme_stylebox_override(&"panel", s.rebuild())
		name_labels[i].add_theme_color_override(&"font_color", SPEC_COLOR.lightened(0.15) if on else SPEC_COLOR.darkened(0.3))
		text_labels[i].add_theme_color_override(&"font_color", UiTheme.TEXT if on else UiTheme.TEXT_DIM.darkened(0.15))
