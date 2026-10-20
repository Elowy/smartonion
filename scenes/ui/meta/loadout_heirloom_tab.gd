class_name LoadoutHeirloomTab
extends VBoxContainer
## The Heirloom tab of the lobby Loadout screen ([LoadoutScreen]): the ten Heirlooms as rows (slot, name, rank dots
## or a lock), a detail panel with the numbers for this hero's class at the profile's rank (waves 1 / 10 / 25), the
## rank 3 / rank 5 perks and how it is obtained. ▲ ▼ move, A takes the Heirloom into the hero's one slot (or takes it
## out again, [method Heirlooms.toggle]). Ranks are bought in The Onion Patch. Holds no state besides the cursor: the
## choice is [member PlayerSlot.heirloom].

## The pick changed ([param result] is a Heirlooms.RESULT_ constant, [param id] the Heirloom).
signal picked(result: StringName, id: StringName)

const ROW_HEIGHT := 32.0
const ICON_SIZE := 28.0
const EQUIPPED_COLOR := Color(0.55, 1.0, 0.5)
const LOCKED_COLOR := Color(0.62, 0.58, 0.55)
const ERROR_COLOR := Color(1.0, 0.45, 0.35)
## Slot name shown on a row's second line.
const SLOT_COLORS := {
	Items.SlotType.WEAPON: Color(0.86, 0.62, 0.3), Items.SlotType.RING: Color(0.9, 0.78, 0.3),
	Items.SlotType.NECK: Color(0.9, 0.78, 0.3), Items.SlotType.TRINKET: Color(0.9, 0.78, 0.3),
}

var slot: PlayerSlot
var entries: Array[HeirloomData] = []
var cursor := 0
## The row panels (tests), in the order of [member entries].
var rows: Array[PanelContainer] = []
## The last [method activate] result (&"" before the first).
var last_result: StringName = &""

var _note: Label
var _list: VBoxContainer
var _detail_name: Label
var _detail_sub: Label
var _detail_preview: Label
var _perk3_label: Label
var _perk5_label: Label
var _detail_status: Label


static func create() -> LoadoutHeirloomTab:
	var t := LoadoutHeirloomTab.new()
	t.name = "HeirloomTab"
	t._build()
	return t


func _build() -> void:
	add_theme_constant_override(&"separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note = UiTheme.label("", UiTheme.DIM, UiTheme.FONT_SMALL - 2)
	_note.clip_text = true
	_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_note)
	add_child(UiTheme.divider())
	_list = UiTheme.vbox(2)
	add_child(_list)
	add_child(UiTheme.spacer(true))
	var detail := UiTheme.panel(UiTheme.INSET_PANEL)
	var style := UiTheme.inset_style()
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	detail.add_theme_stylebox_override(&"panel", style.rebuild())
	add_child(detail)
	var box := UiTheme.vbox(2)
	detail.add_child(box)
	_detail_name = UiTheme.label("", UiTheme.HEADING, 24, UiTheme.GOLD_BRIGHT)
	_detail_name.clip_text = true
	box.add_child(_detail_name)
	_detail_sub = UiTheme.label("", UiTheme.DIM, UiTheme.FONT_SMALL - 2)
	_detail_sub.clip_text = true
	_detail_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_detail_sub)
	# Fixed room for every text, so the tab never changes height with the Heirloom under the cursor.
	_detail_preview = UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL - 3, UiTheme.TEXT)
	_detail_preview.custom_minimum_size.y = 58
	_detail_preview.max_lines_visible = 3
	box.add_child(_detail_preview)
	_perk3_label = UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL - 3, UiTheme.TEXT_DIM)
	_perk3_label.custom_minimum_size.y = 22
	_perk3_label.max_lines_visible = 1
	box.add_child(_perk3_label)
	_perk5_label = UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL - 3, UiTheme.TEXT_DIM)
	_perk5_label.custom_minimum_size.y = 42
	_perk5_label.max_lines_visible = 2
	box.add_child(_perk5_label)
	_detail_status = UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL - 3, UiTheme.TEXT_DIM)
	_detail_status.custom_minimum_size.y = 36
	_detail_status.max_lines_visible = 2
	box.add_child(_detail_status)


# --- State -----------------------------------------------------------------------------------------

## Starts on the hero's pick (else the top) for [param p_slot].
func open(p_slot: PlayerSlot) -> void:
	slot = p_slot
	entries.clear()
	for id in Db.heirloom_ids:
		entries.append(Db.heirlooms[id])
	cursor = 0
	for i in entries.size():
		if slot != null and entries[i].id == slot.heirloom:
			cursor = i
			break
	last_result = &""
	refresh()


func selected() -> HeirloomData:
	return entries[cursor] if cursor >= 0 and cursor < entries.size() else null


func move(step: int) -> void:
	if entries.is_empty() or step == 0:
		return
	cursor = wrapi(cursor + step, 0, entries.size())
	last_result = &""
	refresh()


## A on the row under the cursor: puts the Heirloom in the slot or takes it out. Returns the Heirlooms.RESULT_ constant.
func activate() -> StringName:
	var h := selected()
	if h == null or slot == null:
		return Heirlooms.RESULT_INVALID
	last_result = Heirlooms.toggle(slot, h.id)
	match last_result:
		Heirlooms.RESULT_ADDED:
			Audio.play_ui(&"ui_confirm")
		Heirlooms.RESULT_REMOVED:
			Audio.play_ui(&"ui_back")
		_:
			Audio.play_ui(&"ui_error")
	refresh()
	picked.emit(last_result, h.id)
	return last_result


## One frame of the owner's input: ▲ ▼ move, A picks. (The screen handles tabs and closing.)
func handle_input(inp: PlayerInput) -> void:
	if inp == null:
		return
	var nav := inp.nav_just_pressed()
	if nav.y != 0:
		move(nav.y)
		Audio.play_ui(&"ui_move")
	if inp.just_pressed(PlayerInput.Pad.A):
		activate()


## "Equipped", "Locked", "" for [param h] on the shown slot.
func state_of(h: HeirloomData) -> String:
	if slot != null and slot.heirloom == h.id:
		return "Equipped"
	return "" if _owned(h) else "Locked"


## The button label of A for the row under the cursor ("Remove" / "Take").
func action_label() -> String:
	var h := selected()
	return "Remove" if h != null and slot != null and slot.heirloom == h.id else "Take"


func _owned(h: HeirloomData) -> bool:
	return slot != null and slot.class_data != null and Meta.is_unlocked(Profile.KIND_HEIRLOOM, h.id, slot.class_data.id)


func _slots() -> int:
	return Meta.heirloom_slots(slot.class_data.id) if slot != null and slot.class_data != null else 0


# --- Drawing ---------------------------------------------------------------------------------------

func refresh() -> void:
	if slot == null or slot.class_data == null:
		return
	var who := "%s · %s" % [slot.label(), slot.class_data.display_name]
	if _slots() <= 0:
		_note.text = "%s: the Heirloom slot opens at Class Level 5" % who
		_note.add_theme_color_override(&"font_color", ERROR_COLOR)
	else:
		_note.text = "%s · Heirloom slot: %s" % [who, "taken" if slot.heirloom != &"" else "free"]
		_note.add_theme_color_override(&"font_color", slot.color.lightened(0.35))
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	rows.clear()
	for i in entries.size():
		var row := _make_row(entries[i], i == cursor)
		_list.add_child(row)
		rows.append(row)
	_fill_detail()


func _make_row(h: HeirloomData, selected_row: bool) -> PanelContainer:
	var state := state_of(h)
	var locked := state == "Locked"
	var panel := PanelContainer.new()
	panel.name = "Row_%s" % h.id
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
	line.add_child(_slot_badge(h, locked))
	var texts := UiTheme.vbox(0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_color := EQUIPPED_COLOR if state == "Equipped" else (LOCKED_COLOR if locked else UiTheme.TEXT)
	var name_label := UiTheme.label(h.display_name, &"", UiTheme.FONT_SMALL - 1, name_color)
	name_label.name = "Name"
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(name_label)
	line.add_child(texts)
	if state == "Equipped":
		line.add_child(UiIcon.create(UiIcon.Kind.CHECK, Vector2(22, 22)))
	if locked:
		line.add_child(UiIcon.create(UiIcon.Kind.LOCK, Vector2(20, 20), Color(0.6, 0.55, 0.5)))
	else:
		var dots := RankDots.create(Meta.heirloom_rank(h.id), HeirloomData.MAX_RANK, 5.0)
		dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(dots)
	return panel


## A small square with the slot's first letters ("HEAD", "RING") – the picture of the row.
func _slot_badge(h: HeirloomData, locked: bool) -> Control:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size = Vector2(ICON_SIZE + 38.0, ICON_SIZE - 6.0)
	var style := StyleBoxFlat.new()
	var tint: Color = SLOT_COLORS.get(h.slot_type, Color(0.55, 0.62, 0.78))
	style.bg_color = (tint * Color(1, 1, 1, 0.35)) if not locked else Color(0.15, 0.14, 0.13)
	style.border_color = tint if not locked else Color(0.3, 0.28, 0.26)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	badge.add_theme_stylebox_override(&"panel", style)
	var label := UiTheme.centered_label(String(Items.SLOT_NAMES.get(h.slot_type, "")).to_upper(), &"", 10, tint if not locked else LOCKED_COLOR)
	label.clip_text = true
	badge.add_child(label)
	return badge


func _fill_detail() -> void:
	var h := selected()
	if h == null:
		return
	var cls := slot.class_data
	var rank := maxi(1, Meta.heirloom_rank(h.id))
	var state := state_of(h)
	_detail_name.text = h.display_name
	var armor := ""
	if h.armor_rule == HeirloomData.RULE_HERO:
		armor = " · %s armor" % Items.ARMOR_TYPE_NAMES.get(cls.armor_type, "")
	_detail_sub.text = "%s%s · Rank %d" % [Items.SLOT_NAMES.get(h.slot_type, ""), armor, rank]
	var lines: Array[String] = []
	for w in Heirlooms.PREVIEW_WAVES:
		lines.append("Wave %d: %s" % [w, Heirlooms.preview_text(h, cls, w, rank, true)])
	_detail_preview.text = "\n".join(PackedStringArray(lines))
	for which: int in [HeirloomData.PERK3_RANK, HeirloomData.PERK5_RANK]:
		var label := _perk3_label if which == HeirloomData.PERK3_RANK else _perk5_label
		label.text = "Rank %d: %s" % [which, Heirlooms.perk_text(h, which)]
		label.add_theme_color_override(&"font_color", UiTheme.GREEN if Heirlooms.perk_active(rank, which) else UiTheme.TEXT_DIM)
	var status := ""
	var color := UiTheme.TEXT_DIM
	if state == "Equipped":
		status = "Equipped – press A to remove it."
		color = EQUIPPED_COLOR
	elif state == "Locked":
		status = "Locked: %s" % Heirlooms.obtain_text(h)
		color = ERROR_COLOR
	elif _slots() <= 0:
		status = "No Heirloom slot yet (Class Level 5)."
		color = ERROR_COLOR
	else:
		status = "Press A to take it into your slot." if slot.heirloom == &"" else "Press A to swap it in for %s." % _name_of(slot.heirloom)
		color = UiTheme.GOLD
	_detail_status.text = status
	_detail_status.add_theme_color_override(&"font_color", color)


static func _name_of(id: StringName) -> String:
	var h := Db.get_heirloom(id)
	return h.display_name if h != null else String(id)
