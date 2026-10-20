class_name PatchSeasoningsTab
extends PatchTab
## The Seasonings tab of The Onion Patch: a class selector on top (◀ ▶), the eight Seasonings of that class below (▲ ▼) –
## icon, name, the ability it changes and its state (Locked + the reason, the price in Seeds, or Owned) – and a detail
## pane. A buys the Seasoning under the cursor with Seeds ([method Meta.buy_seasoning], saved at once); on an owned one it
## puts the Seasoning into / out of the loadout remembered for the class (up to the slots the Class Level opened; the
## lobby can change it per hero).

const ROW_HEIGHT := 58.0
const ICON_SIZE := 44.0

var class_index := 0
var cursor := 0
## The class chips and Seasoning rows (tests).
var chips: Array[PanelContainer] = []
var rows: Array[PanelContainer] = []
var entries: Array[SeasoningData] = []

var _chip_row: HBoxContainer
var _list: VBoxContainer
var _detail: PanelContainer
var _d_icon_slot: HBoxContainer
var _d_name: Label
var _d_target: Label
var _d_text: Label
var _d_state: Label
var _d_slots: Label
var _d_price: Label


static func create() -> PatchSeasoningsTab:
	var t := PatchSeasoningsTab.new()
	t.name = "SeasoningsTab"
	t._build()
	return t


func tab_name() -> String:
	return "Seasonings"


func _build() -> void:
	add_theme_constant_override(&"separation", 10)
	_chip_row = UiTheme.hbox(8)
	_chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_chip_row)
	var body := UiTheme.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	_list = UiTheme.vbox(4)
	_list.custom_minimum_size.x = 820
	body.add_child(_list)
	_detail = inset_panel()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_detail)
	var box := UiTheme.vbox(6)
	_detail.add_child(box)
	var head := UiTheme.hbox(14)
	box.add_child(head)
	_d_icon_slot = UiTheme.hbox(0)
	head.add_child(_d_icon_slot)
	var names := UiTheme.vbox(2)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	_d_name = clipped_label("", 34, UiTheme.GOLD_BRIGHT, UiTheme.HEADING)
	names.add_child(_d_name)
	_d_target = clipped_label("", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	names.add_child(_d_target)
	_d_text = UiTheme.wrapped_label("", &"", UiTheme.FONT_BODY - 1, UiTheme.TEXT)
	_d_text.custom_minimum_size.y = 96
	_d_text.max_lines_visible = 4
	_d_state = UiTheme.wrapped_label("", &"", UiTheme.FONT_BODY - 1, UiTheme.TEXT)
	_d_state.custom_minimum_size.y = 56
	_d_state.max_lines_visible = 2
	_d_price = UiTheme.label("", &"", UiTheme.FONT_BODY, SEEDS_COLOR)
	_d_slots = UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	_d_slots.max_lines_visible = 2
	box.add_child(_d_text)
	box.add_child(_d_state)
	box.add_child(_d_price)
	box.add_child(UiTheme.spacer(true))
	box.add_child(_d_slots)


# --- State -----------------------------------------------------------------------------------------

func on_open() -> void:
	refresh()


func current_class() -> StringName:
	return Db.class_ids[class_index] if class_index >= 0 and class_index < Db.class_ids.size() else &""


func selected() -> SeasoningData:
	return entries[cursor] if cursor >= 0 and cursor < entries.size() else null


## Moves to the class [param id] (tests / the page).
func select_class(id: StringName) -> void:
	var i := Db.class_ids.find(id)
	if i >= 0:
		class_index = i
		cursor = 0
		refresh()


func on_nav(dir: Vector2i) -> void:
	if dir.x != 0:
		class_index = wrap_index(class_index, dir.x, Db.class_ids.size())
		cursor = 0
		Audio.play_ui(&"ui_move")
		refresh()
	elif dir.y != 0:
		cursor = wrap_index(cursor, dir.y, entries.size())
		Audio.play_ui(&"ui_move")
		refresh()


func action_text() -> String:
	var s := selected()
	if s == null:
		return ""
	match Meta.seasoning_state(s):
		&"owned":
			return "Loadout" if not Meta.is_dev() else ""
		&"buyable", &"poor":
			return "Buy"
	return ""


func on_accept() -> void:
	var s := selected()
	if s == null:
		return
	match Meta.seasoning_state(s):
		&"owned":
			_toggle_default(s)
		&"buyable":
			if Meta.buy_seasoning(s.id):
				Audio.play_ui(&"ui_confirm")
				post("Bought %s for %d Seeds" % [s.display_name, s.price()])
			else:
				Audio.play_ui(&"ui_error")
				post("Could not buy %s" % s.display_name, false)
		&"poor":
			Audio.play_ui(&"ui_error")
			post("Not enough Seeds for %s (%d needed)" % [s.display_name, s.price()], false)
		_:
			Audio.play_ui(&"ui_error")
			post("%s: %s" % [s.display_name, Meta.seasoning_lock_reason(s)], false)
	refresh()


func _toggle_default(s: SeasoningData) -> void:
	if Meta.is_dev():
		Audio.play_ui(&"ui_error")
		post("Nothing is saved in this session", false)
		return
	match Meta.toggle_default_seasoning(s.id):
		Seasonings.RESULT_ADDED:
			Audio.play_ui(&"ui_confirm")
			post("%s joins the %s loadout" % [s.display_name, _class_name()])
		Seasonings.RESULT_REMOVED:
			Audio.play_ui(&"ui_back")
			post("%s leaves the %s loadout" % [s.display_name, _class_name()])
		Seasonings.RESULT_FULL:
			Audio.play_ui(&"ui_error")
			post("Every %s slot is taken – remove one first" % _class_name(), false)
		_:
			Audio.play_ui(&"ui_error")
			post("%s cannot be carried yet" % s.display_name, false)


func _class_name() -> String:
	var c := Db.get_class_data(current_class())
	return c.display_name if c != null else ""


## Whether [param s] sits in the loadout remembered for its class.
func in_default_loadout(s: SeasoningData) -> bool:
	return s != null and Meta.remembered_loadout(s.class_id)["seasonings"].has(s.id)


# --- Drawing ---------------------------------------------------------------------------------------

func refresh() -> void:
	entries = Db.seasonings_for_class(current_class())
	cursor = clampi(cursor, 0, maxi(entries.size() - 1, 0))
	clear(_chip_row)
	chips.clear()
	_chip_row.add_child(UiGlyph.nav(26.0))
	for i in Db.class_ids.size():
		_chip_row.add_child(_make_chip(Db.class_ids[i], i == class_index))
	clear(_list)
	rows.clear()
	for i in entries.size():
		var row := _make_row(entries[i], i == cursor)
		_list.add_child(row)
		rows.append(row)
	_fill_detail()


func _make_chip(id: StringName, selected: bool) -> PanelContainer:
	var data := Db.get_class_data(id)
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.custom_minimum_size = Vector2(176, 40)
	chip.add_theme_stylebox_override(&"panel", row_style(selected))
	var owned := 0
	for s in Db.seasonings_for_class(id):
		if Meta.is_unlocked(Profile.KIND_SEASONING, s.id, id):
			owned += 1
	var label := UiTheme.centered_label("%s  %d/%d" % [data.display_name if data != null else String(id), owned, Db.seasonings_for_class(id).size()],
			UiTheme.HEADING, UiTheme.FONT_SMALL, UiTheme.GOLD_BRIGHT if selected else UiTheme.TEXT_DIM)
	label.clip_text = true
	chip.add_child(label)
	chips.append(chip)
	return chip


func _make_row(s: SeasoningData, selected: bool) -> PanelContainer:
	var state := Meta.seasoning_state(s)
	var locked := state == &"locked"
	var panel := row_panel(selected, ROW_HEIGHT)
	panel.name = "Row_%s" % s.id
	var line := UiTheme.hbox(12)
	panel.add_child(line)
	var icon := SeasoningIcon.create(s, ICON_SIZE)
	icon.set_state(locked)
	line.add_child(icon)
	var texts := UiTheme.vbox(0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_color := UiTheme.TEXT
	if state == &"owned":
		name_color = OWNED_COLOR
	elif locked:
		name_color = LOCKED_COLOR
	var name_label := clipped_label(s.display_name, UiTheme.FONT_BODY, name_color)
	name_label.name = "Name"
	texts.add_child(name_label)
	texts.add_child(clipped_label("Changes %s" % s.target_name(), UiTheme.FONT_SMALL - 3, UiTheme.TEXT_DIM))
	line.add_child(texts)
	var status := UiTheme.label("", &"", UiTheme.FONT_SMALL, UiTheme.TEXT)
	status.name = "State"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.custom_minimum_size.x = 210
	match state:
		&"owned":
			status.text = "In loadout" if in_default_loadout(s) else "Owned"
			status.add_theme_color_override(&"font_color", OWNED_COLOR)
		&"buyable":
			status.text = "%d Seeds" % s.price()
			status.add_theme_color_override(&"font_color", SEEDS_COLOR)
		&"poor":
			status.text = "%d Seeds" % s.price()
			status.add_theme_color_override(&"font_color", ERROR_COLOR)
		_:
			status.text = Meta.seasoning_lock_reason(s)
			status.add_theme_color_override(&"font_color", LOCKED_COLOR)
			status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			status.custom_minimum_size.x = 210
			status.add_theme_font_size_override(&"font_size", UiTheme.FONT_SMALL - 3)
	line.add_child(status)
	if state == &"owned":
		line.add_child(UiIcon.create(UiIcon.Kind.CHECK, Vector2(24, 24)))
	elif locked:
		line.add_child(UiIcon.create(UiIcon.Kind.LOCK, Vector2(22, 22), Color(0.6, 0.55, 0.5)))
	return panel


func _fill_detail() -> void:
	clear(_d_icon_slot)
	var s := selected()
	if s == null:
		return
	var state := Meta.seasoning_state(s)
	var icon := SeasoningIcon.create(s, 72.0)
	icon.set_state(state == &"locked")
	_d_icon_slot.add_child(icon)
	_d_name.text = s.display_name
	var target := "Changes %s" % s.target_name()
	if s.is_dormant_until_learned():
		target += " · once learned"
	_d_target.text = target
	_d_text.text = s.text
	var status := ""
	var color := UiTheme.TEXT
	match state:
		&"owned":
			status = "Owned. A adds it to your %s loadout (the lobby can change it per hero)." % _class_name() if not Meta.is_dev() else "Owned."
			color = OWNED_COLOR
		&"buyable":
			status = "Press A to buy it."
			color = UiTheme.GOLD
		&"poor":
			status = "You need %d more Seeds." % (s.price() - Meta.seeds())
			color = ERROR_COLOR
		_:
			status = "Locked: %s" % Meta.seasoning_lock_reason(s)
			color = ERROR_COLOR
	_d_state.text = status
	_d_state.add_theme_color_override(&"font_color", color)
	_d_price.text = "Price: %d Seeds" % s.price() if state != &"owned" else "Tier %s · %d Seeds" % [String(s.tier).to_upper(), s.price()]
	var slots := Meta.seasoning_slots(current_class())
	var level_note := "" if Meta.is_dev() else "  ·  %s level %d" % [_class_name(), Meta.class_level(current_class())]
	_d_slots.text = "Slots for %s: %d of %d%s" % [_class_name(), slots, Seasonings.MAX_SLOTS, level_note]
