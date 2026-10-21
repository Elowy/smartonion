class_name RunCardView
extends Control
## The run card as a picture (M6 METER): a fixed 1200 x 630 layout of the [RunCard] model – game
## title and mode, the result (Victory gold / Defeat red) with the waves cleared and the run time,
## and one card per hero: portrait, name and class, best item (rarity colour), award and the
## damage / healing line. Plain Controls with the shared theme, so [method RunCard.render] can draw
## it through a SubViewport.

const CARD_SIZE := Vector2(1200.0, 630.0)
const MARGIN_X := 36
const MARGIN_Y := 26
const HERO_WIDTH := 270.0
const HERO_HEIGHT := 322.0
const HERO_GAP := 16
## Two lines of the item name (so the cards line up whether the name wraps or not).
const ITEM_NAME_HEIGHT := 68.0

var card_model: Dictionary = {}
## The hero cards in model order (tests).
var hero_cards: Array[Control] = []
var result_label: Label


static func create(p_model: Dictionary) -> RunCardView:
	var view := RunCardView.new()
	view.name = "RunCardView"
	view.card_model = p_model
	view._build()
	return view


func _build() -> void:
	UiTheme.setup_root(self)
	custom_minimum_size = CARD_SIZE
	var victory := bool(card_model.get("victory", false))
	var backdrop := UiTheme.backdrop(1.0, Color(0.42, 0.3, 0.1) if victory else Color(0.38, 0.1, 0.08))
	add_child(backdrop)
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiTheme.stone_style(UiTheme.GOLD_BORDER, Color(0.0, 0.0, 0.0, 0.0))
	frame.add_theme_stylebox_override(&"panel", style)
	add_child(frame)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", MARGIN_X)
	margin.add_theme_constant_override(&"margin_right", MARGIN_X)
	margin.add_theme_constant_override(&"margin_top", MARGIN_Y)
	margin.add_theme_constant_override(&"margin_bottom", MARGIN_Y)
	add_child(margin)
	var col := UiTheme.vbox(10)
	margin.add_child(col)

	var top := UiTheme.hbox(10)
	col.add_child(top)
	var title := UiTheme.label(String(card_model.get("title", RunCard.GAME_TITLE)).to_upper(), UiTheme.GOLD_LABEL, 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var mode_line := "%s mode" % card_model.get("mode", "Normal")
	var difficulty_name := String(card_model.get("difficulty", "Normal"))
	if difficulty_name not in ["", "Normal"]:  # (a Normal card keeps its line as it was)
		mode_line += "  ·  %s" % difficulty_name
	if String(card_model.get("environment", "")) != "":
		mode_line += "  ·  %s" % card_model["environment"]
	top.add_child(UiTheme.label(mode_line, UiTheme.DIM, 26))

	var headline := UiTheme.hbox(24)
	col.add_child(headline)
	result_label = UiTheme.label(String(card_model.get("result", "")).to_upper(), UiTheme.TITLE, 96,
			UiTheme.GOLD if victory else UiTheme.RED)
	result_label.add_theme_constant_override(&"outline_size", 14)
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headline.add_child(result_label)
	var facts := UiTheme.vbox(0)
	facts.alignment = BoxContainer.ALIGNMENT_CENTER
	headline.add_child(facts)
	facts.add_child(_fact(String(card_model.get("waves_text", "")), UiTheme.TEXT))
	facts.add_child(_fact("Time %s" % card_model.get("time_text", "0:00"), UiTheme.TEXT_DIM))

	var heroes := UiTheme.hbox(HERO_GAP)
	heroes.alignment = BoxContainer.ALIGNMENT_CENTER
	heroes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(heroes)
	for h: Dictionary in card_model.get("heroes", []):
		var card := _hero_card(h)
		hero_cards.append(card)
		heroes.add_child(card)


func _fact(text: String, color: Color) -> Label:
	var l := UiTheme.label(text, &"", 38, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _hero_card(h: Dictionary) -> Control:
	var panel := UiTheme.panel(UiTheme.INSET_PANEL)
	panel.custom_minimum_size = Vector2(HERO_WIDTH, HERO_HEIGHT)
	panel.name = "Hero_%s" % h.get("label", "?")
	var col := UiTheme.vbox(3)
	panel.add_child(col)
	var band := ColorRect.new()
	band.color = h.get("color", Color.WHITE)
	band.custom_minimum_size = Vector2(0, 6)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(band)
	var portrait := UiPortrait.create(100.0)
	portrait.setup(h.get("color", Color.WHITE), Db.get_class_data(h.get("class_id", &"")))
	portrait.set_downed(not bool(h.get("alive", true)))
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(portrait)
	col.add_child(UiTheme.centered_label("%s  %s" % [h.get("label", "?"), h.get("class_name", "?")],
			UiTheme.GOLD_LABEL, 26, Color(h.get("class_color", UiTheme.TEXT)).lightened(MeterPage.TEXT_LIGHTEN)))
	col.add_child(UiTheme.centered_label("Best item", UiTheme.SMALL, 17))
	var rarity := int(h.get("item_rarity", -1))
	var item_color := UiTheme.TEXT_DIM
	if rarity >= 0:
		item_color = UiTheme.RARITY_COLORS[clampi(rarity, 0, UiTheme.RARITY_COLORS.size() - 1)]
	var item := UiTheme.centered_label(String(h.get("item_name", "")) if rarity >= 0 else "None", UiTheme.GOLD_LABEL, 20, item_color)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.max_lines_visible = 2  # a long name ends in "..." instead of pushing the card
	item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	item.custom_minimum_size = Vector2(HERO_WIDTH - 36.0, ITEM_NAME_HEIGHT)
	col.add_child(item)
	col.add_child(UiTheme.centered_label(String(h.get("item_line", "")), UiTheme.SMALL, 17))
	var award_text := String(h.get("award_line", ""))
	var award := UiTheme.centered_label(award_text if award_text != "" else " ", UiTheme.GOLD_LABEL, 24)
	col.add_child(award)
	col.add_child(UiTheme.centered_label(String(h.get("stat_line", "")), UiTheme.SMALL, 17))
	return panel
