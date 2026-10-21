class_name SeasoningPicker
extends PanelContainer
## The lobby's Seasoning picker (M9): a panel that covers one hero's lobby card and lists the Seasonings of the hero's
## class – name, the ability it changes (with that ability's icon and a spice badge), what it gives and costs.
## Owned ones can be equipped (A) up to the class's slots; the others stay greyed with how to get them. The hero's
## own input drives it (the Lobby routes PlayerSlot.input here while it is open): ▲ ▼ move, A equips / removes,
## B or LT closes. Every change goes through [method Seasonings.toggle], which remembers the choice per class.
##
## The picker holds no state of its own besides the cursor: the choice is [member PlayerSlot.seasonings].
## M9 PATCH: the lobby embeds it as the Seasonings tab of the Loadout screen ([LoadoutScreen], [method set_embedded]):
## then the screen draws the frame, the title and the button prompts, and the picker is only the list and the detail.

## The selection changed ([param result] is a Seasonings.RESULT_ constant, [param id] the Seasoning).
signal picked(result: StringName, id: StringName)
signal closed

const ICON_SIZE := 36.0
const ROW_HEIGHT := 44.0
const EQUIPPED_COLOR := Color(0.55, 1.0, 0.5)
const LOCKED_COLOR := Color(0.62, 0.58, 0.55)
const ERROR_COLOR := Color(1.0, 0.45, 0.35)

var slot: PlayerSlot
## The Seasonings of the slot's class, in list order.
var entries: Array[SeasoningData] = []
var cursor := 0
## The row panels (for tests), in the order of [member entries].
var rows: Array[PanelContainer] = []
## The last [method activate] result (&"" before the first).
var last_result: StringName = &""

var _title: Label
var _pips: _Pips
var _head: HBoxContainer
var _note_row: HBoxContainer
var _divider: Control
var _note: Label
var _list: VBoxContainer
var _detail_name: Label
var _detail_target: Label
var _detail_text: Label
var _detail_status: Label
var _prompts: CenterContainer
var _open := false
## True inside the Loadout screen (no frame, title or prompt row of its own).
var embedded := false


static func create() -> SeasoningPicker:
	var p := SeasoningPicker.new()
	p.name = "SeasoningPicker"
	p._build()
	p.visible = false
	return p


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	add_theme_stylebox_override(&"panel", _frame_style(UiTheme.GOLD_BORDER))
	var col := UiTheme.vbox(4)
	add_child(col)
	_head = UiTheme.hbox(8)
	_title = UiTheme.label("SEASONINGS", UiTheme.HEADING, 30, UiTheme.GOLD)
	_head.add_child(_title)
	_head.add_child(UiTheme.spacer())
	_pips = _Pips.new()
	_pips.custom_minimum_size = Vector2(96, 26)
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head.add_child(_pips)
	col.add_child(_head)
	_note_row = UiTheme.hbox(8)
	_note = UiTheme.label("", UiTheme.DIM, UiTheme.FONT_SMALL - 2)
	_note.clip_text = true
	_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note_row.add_child(_note)
	col.add_child(_note_row)
	_divider = UiTheme.divider()
	col.add_child(_divider)
	_list = UiTheme.vbox(3)
	col.add_child(_list)
	col.add_child(UiTheme.spacer(true))
	var detail := UiTheme.panel(UiTheme.INSET_PANEL)
	var detail_style := UiTheme.inset_style()
	detail_style.content_margin_left = 12
	detail_style.content_margin_right = 12
	detail_style.content_margin_top = 6
	detail_style.content_margin_bottom = 6
	detail.add_theme_stylebox_override(&"panel", detail_style.rebuild())
	col.add_child(detail)
	var dbox := UiTheme.vbox(3)
	detail.add_child(dbox)
	_detail_name = UiTheme.label("", UiTheme.HEADING, 24, UiTheme.GOLD_BRIGHT)
	dbox.add_child(_detail_name)
	_detail_target = UiTheme.label("", UiTheme.DIM, UiTheme.FONT_SMALL - 2)
	_detail_target.clip_text = true
	_detail_target.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dbox.add_child(_detail_target)
	# The text (up to three lines) and the status (up to two) keep their room, so the picker never changes height.
	_detail_text = UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL, UiTheme.TEXT)
	_detail_text.custom_minimum_size.y = 66
	_detail_text.max_lines_visible = 3
	dbox.add_child(_detail_text)
	_detail_status = UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL - 2, UiTheme.TEXT_DIM)
	_detail_status.custom_minimum_size.y = 40
	_detail_status.max_lines_visible = 2
	dbox.add_child(_detail_status)
	_prompts = CenterContainer.new()
	_prompts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompts.custom_minimum_size = Vector2(0, 32)
	col.add_child(_prompts)


## Inside the Loadout screen (true): no frame, no title and no prompt row – the screen draws them.
func set_embedded(on: bool) -> void:
	embedded = on
	_head.visible = not on
	_divider.visible = not on
	_prompts.visible = not on
	# The slot pips move next to the player's name, so the tab needs no row of its own.
	_pips.reparent(_note_row if on else _head)
	if on:
		add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	else:
		add_theme_stylebox_override(&"panel", _frame_style(UiTheme.GOLD_BORDER))


## The button label of A for the row under the cursor ("Remove" / "Equip").
func action_label() -> String:
	var s := selected()
	return "Remove" if s != null and slot != null and s.id in slot.seasonings else "Equip"


static func _frame_style(border: Color) -> UiFrameStyle:
	var s := UiTheme.card_style(border, Color(0.085, 0.073, 0.066, 0.98))
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s.rebuild()


# --- State -----------------------------------------------------------------------------------------

func is_open() -> bool:
	return _open


## Opens the picker for [param p_slot] (a joined player with a class). False when it cannot be opened.
func open(p_slot: PlayerSlot) -> bool:
	if p_slot == null or p_slot.class_data == null:
		return false
	slot = p_slot
	entries = Db.seasonings_for_class(p_slot.class_data.id)
	if entries.is_empty():
		return false
	cursor = 0
	# Start on the first equipped Seasoning, else on the first owned one, else on the top.
	for i in entries.size():
		if entries[i].id in slot.seasonings:
			cursor = i
			break
	last_result = &""
	_open = true
	visible = true
	refresh()
	return true


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


## Moves the cursor [param step] rows (wraps).
func move(step: int) -> void:
	if entries.is_empty() or step == 0:
		return
	cursor = wrapi(cursor + step, 0, entries.size())
	last_result = &""
	refresh()


func selected() -> SeasoningData:
	return entries[cursor] if cursor >= 0 and cursor < entries.size() else null


## Equips or removes the Seasoning under the cursor. Returns the Seasonings.RESULT_ constant.
func activate() -> StringName:
	var s := selected()
	if s == null or slot == null:
		return Seasonings.RESULT_INVALID
	last_result = Seasonings.toggle(slot, s.id)
	match last_result:
		Seasonings.RESULT_ADDED:
			Audio.play_ui(&"ui_confirm")
		Seasonings.RESULT_REMOVED:
			Audio.play_ui(&"ui_back")
		_:
			Audio.play_ui(&"ui_error")
	refresh()
	picked.emit(last_result, s.id)
	return last_result


## One frame of the owner's input: ▲ ▼ move, A equips / removes, B / LT closes.
func handle_input(inp: PlayerInput) -> void:
	if inp == null:
		return
	var nav := inp.nav_just_pressed()
	if nav.y != 0:
		move(nav.y)
		Audio.play_ui(&"ui_move")
	if inp.just_pressed(PlayerInput.Pad.A):
		activate()
	elif inp.just_pressed(PlayerInput.Pad.B) or inp.just_pressed(PlayerInput.Pad.LT):
		Audio.play_ui(&"ui_back")
		close()


## Slots the shown class has (Seasonings.slot_count).
func slot_total() -> int:
	return Seasonings.slot_count(slot.class_data.id) if slot != null and slot.class_data != null else 0


## "Equipped", "Locked" or "" for [param s] on the shown slot.
func state_of(s: SeasoningData) -> String:
	if slot != null and s.id in slot.seasonings:
		return "Equipped"
	return "" if Seasonings.owned(s) else "Locked"


# --- Drawing ---------------------------------------------------------------------------------------

## Rebuilds the list and the detail panel from the slot's current choice.
func refresh() -> void:
	if slot == null or slot.class_data == null:
		return
	var total := slot_total()
	_title.text = "SEASONINGS"
	_pips.set_counts(slot.seasonings.size(), total)
	var who := "%s · %s" % [slot.label(), slot.class_data.display_name]
	if total <= 0:
		_note.text = "%s: first slot at Class Level %d" % [who, Seasonings.SLOT_LEVELS[0]]
		_note.add_theme_color_override(&"font_color", ERROR_COLOR)
	else:
		_note.text = who
		_note.add_theme_color_override(&"font_color", slot.color.lightened(0.35))
	if not embedded:
		add_theme_stylebox_override(&"panel", _frame_style(slot.color.lightened(0.15)))
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	rows.clear()
	for i in entries.size():
		var row := _make_row(entries[i], i == cursor)
		_list.add_child(row)
		rows.append(row)
	_fill_detail()
	_fill_prompts()


func _make_row(s: SeasoningData, selected_row: bool) -> PanelContainer:
	var state := state_of(s)
	var locked := state == "Locked"
	var panel := PanelContainer.new()
	panel.name = "Row_%s" % s.id
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.17, 0.11, 0.95) if selected_row else Color(0.1, 0.09, 0.08, 0.9)
	style.border_color = UiTheme.GOLD if selected_row else Color(0.2, 0.17, 0.13)
	style.set_border_width_all(2 if selected_row else 1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 8
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	panel.add_theme_stylebox_override(&"panel", style)
	var line := UiTheme.hbox(8)
	panel.add_child(line)
	var icon := SeasoningIcon.create(s, ICON_SIZE)
	icon.set_state(locked)
	line.add_child(icon)
	var texts := UiTheme.vbox(0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_color := EQUIPPED_COLOR if state == "Equipped" else (LOCKED_COLOR if locked else UiTheme.TEXT)
	var name_label := UiTheme.label(s.display_name, &"", UiTheme.FONT_SMALL + 1, name_color)
	name_label.name = "Name"
	name_label.clip_text = true
	texts.add_child(name_label)
	var target := UiTheme.label(s.target_name(), &"", UiTheme.FONT_SMALL - 4, UiTheme.TEXT_DIM if not locked else Color(0.5, 0.47, 0.44))
	texts.add_child(target)
	line.add_child(texts)
	if state == "Equipped":
		line.add_child(UiIcon.create(UiIcon.Kind.CHECK, Vector2(24, 24)))
	elif locked:
		line.add_child(UiIcon.create(UiIcon.Kind.LOCK, Vector2(22, 22), Color(0.6, 0.55, 0.5)))
	return panel


func _fill_detail() -> void:
	var s := selected()
	if s == null:
		return
	var state := state_of(s)
	_detail_name.text = s.display_name
	var target := "Changes: %s" % s.target_name()
	if s.is_dormant_until_learned():
		target += " · once learned"
	_detail_target.text = target
	_detail_text.text = s.text
	var total := slot_total()
	var status := ""
	var color := UiTheme.TEXT_DIM
	if state == "Equipped":
		status = "Equipped – press A to remove it."
		color = EQUIPPED_COLOR
	elif state == "Locked":
		status = "Locked: %s" % s.unlock_hint()
		color = ERROR_COLOR
	elif slot != null and slot.seasonings.size() >= total:
		if total <= 0:
			status = "No slot yet."
		elif total == 1:
			status = "Your only slot is taken – remove it first."
		else:
			status = "All %d slots are taken – remove one first." % total
		color = ERROR_COLOR
	else:
		status = "Press A to equip."
		color = UiTheme.GOLD
	_detail_status.text = status
	_detail_status.add_theme_color_override(&"font_color", color)


func _fill_prompts() -> void:
	for c in _prompts.get_children():
		_prompts.remove_child(c)
		c.queue_free()
	var inp := slot.input if slot != null else null
	var a_label := action_label()
	var items: Array = [
		[UiGlyph.nav(26.0, true), "Move"],
		[UiGlyph.for_input(inp, PlayerInput.Pad.A, 26.0) if inp != null else UiGlyph.pad(PlayerInput.Pad.A, 26.0), a_label],
		[UiGlyph.for_input(inp, PlayerInput.Pad.B, 26.0) if inp != null else UiGlyph.pad(PlayerInput.Pad.B, 26.0), "Back"],
	]
	var row := UiTheme.prompt_row(items, UiTheme.FONT_SMALL)
	row.add_theme_constant_override(&"separation", 14)
	_prompts.add_child(row)


## Three pips: filled = a Seasoning in the slot, open ring = a free slot, dim dashed ring = a slot not yet unlocked.
class _Pips extends Control:
	var used := 0
	var total := 0

	func set_counts(p_used: int, p_total: int) -> void:
		used = p_used
		total = p_total
		queue_redraw()

	func _draw() -> void:
		var r := 9.0
		for i in Seasonings.MAX_SLOTS:
			var c := Vector2(r + 1.0 + float(i) * (r * 2.0 + 10.0), size.y * 0.5)
			if i < used:
				draw_circle(c, r, UiTheme.GOLD_DARK)
				draw_circle(c, r - 2.0, UiTheme.GOLD)
			elif i < total:
				draw_arc(c, r - 1.0, 0.0, TAU, 24, UiTheme.GOLD, 2.0)
			else:
				draw_arc(c, r - 1.0, 0.0, TAU, 24, Color(0.45, 0.4, 0.35, 0.6), 1.5)
