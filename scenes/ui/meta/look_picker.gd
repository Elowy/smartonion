class_name LookPicker
extends PanelContainer
## The Look picker of one hero (M9 WARDROBE, design_m9 section 7): what the onion WEARS for show. Per visible armour slot (Head,
## Shoulders, Chest) "Worn gear" (the default: the item's own model, the class starter piece while the slot is empty) or any look
## the profile has collected (cross-armour allowed: a transmog, cosmetic only), plus a Tabard, a Hat, a Glow and a Dye out of the
## cosmetics the profile owns. A live preview of the onion shows the result.
##
## Standalone: [code]var p := LookPicker.create(slot); add_child(p)[/code] – it drives itself from [member PlayerSlot.input] (D-pad /
## stick, A, B, X, Y) and emits [signal closed] when the player presses B. A host that routes the player's input itself (the
## Loadout screen) sets [member self_driven] = false and calls [method handle_input] every frame; both ways read each rendered
## frame's input once (a frame the host fed is not read again by the picker's own _process, and the other way round).
##
## Controls: ▲ ▼ pick a row; ◀ ▶ step through the row's options right away; A opens the row's list (a grid: move, A takes it,
## B puts the old one back); X clears the row (Worn gear / None); Y clears every row; B closes.
## It edits [member PlayerSlot.looks] / [member PlayerSlot.cosmetics] and remembers them for the class
## ([method Meta.remember_loadout]; the file is saved once when the picker closes). Nothing here touches a stat.

## The picker was closed (B). The selections are on the slot and remembered in the profile.
signal closed
## A selection changed ([param row_key] is "head" .. "dye", [param id] &"" = cleared).
signal changed(row_key: StringName, id: StringName)

enum Mode { ROWS, LIST }

## The rows in order: key (looks: Profile.LOOK_SLOTS, cosmetics: CosmeticData.KINDS), caption, the label of "nothing chosen".
const ROW_DEFS: Array[Dictionary] = [
	{"key": &"head", "caption": "Head", "none": "Worn gear"},
	{"key": &"shoulders", "caption": "Shoulders", "none": "Worn gear"},
	{"key": &"chest", "caption": "Chest", "none": "Worn gear"},
	{"key": &"tabard", "caption": "Tabard", "none": "None"},
	{"key": &"hat", "caption": "Hat", "none": "None"},
	{"key": &"glow", "caption": "Glow", "none": "None"},
	{"key": &"dye", "caption": "Dye", "none": "None"},
]
const ROW_HEIGHT := 56.0
const SWATCH := 48.0

var slot: PlayerSlot
## True: the picker reads [member PlayerSlot.input] itself. A host that calls [method handle_input] sets it false.
var self_driven := true
var mode := Mode.ROWS
## The row under the cursor (index into [constant ROW_DEFS]).
var row := 0
var preview: OnionPreview
var grid: WardrobeGrid
## The row panels (for tests), in the order of [constant ROW_DEFS].
var row_panels: Array[PanelContainer] = []

var _options: Array[Array] = []
var _before_id: StringName = &""
var _list_row := -1
var _title: Label
var _who: Label
var _rows_box: VBoxContainer
var _list_box: VBoxContainer
var _list_title: Label
var _detail_name: Label
var _detail_line: Label
var _detail_hint: Label
var _prompts: CenterContainer
var _value_labels: Array[Label] = []
var _swatches: Array[_Swatch] = []
## The rendered frame the host last fed ([method handle_input]) / the picker read itself: the two sources never read the same frame.
var _fed_frame := -1
var _own_frame := -1
## The press that opened the picker (still held) is not read: this many frames and a held direction are skipped.
var skip_frames := 1
var _wait_neutral := false
var _dirty := true


## Builds the picker for [param p_slot] (a joined player with a class). It is visible and active at once.
static func create(p_slot: PlayerSlot) -> LookPicker:
	var p := LookPicker.new()
	p.name = "LookPicker"
	p.slot = p_slot
	p._build()
	p.open(p_slot)
	return p


func _build() -> void:
	UiTheme.setup_root(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(760, 560)
	add_theme_stylebox_override(&"panel", _frame_style(UiTheme.GOLD_BORDER))
	var col := UiTheme.vbox(6)
	add_child(col)
	var head := UiTheme.hbox(8)
	_title = UiTheme.label("LOOK", UiTheme.HEADING, 30, UiTheme.GOLD)
	head.add_child(_title)
	head.add_child(UiTheme.spacer())
	_who = UiTheme.label("", UiTheme.DIM, UiTheme.FONT_SMALL)
	head.add_child(_who)
	col.add_child(head)
	col.add_child(UiTheme.divider())
	var body := UiTheme.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	# Left: the live preview.
	var stage := UiTheme.panel(UiTheme.INSET_PANEL)
	stage.custom_minimum_size = Vector2(250, 0)
	body.add_child(stage)
	preview = OnionPreview.create()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.frame_tall()
	stage.add_child(preview)
	# Right: the rows, or the list of one row.
	var right := UiTheme.vbox(4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_rows_box = UiTheme.vbox(4)
	right.add_child(_rows_box)
	for i in ROW_DEFS.size():
		_rows_box.add_child(_make_row(i))
	_list_box = UiTheme.vbox(4)
	_list_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_title = UiTheme.label("", UiTheme.GOLD_LABEL, UiTheme.FONT_SMALL + 2)
	_list_box.add_child(_list_title)
	grid = WardrobeGrid.new()
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.show_marked = true
	grid.cursor_changed.connect(_on_cursor_changed)
	_list_box.add_child(grid)
	right.add_child(_list_box)
	_list_box.visible = false
	# Detail line and prompts.
	var detail := UiTheme.panel(UiTheme.INSET_PANEL)
	col.add_child(detail)
	var dbox := UiTheme.vbox(1)
	detail.add_child(dbox)
	_detail_name = UiTheme.label("", UiTheme.HEADING, 22, UiTheme.GOLD_BRIGHT)
	_detail_name.clip_text = true
	dbox.add_child(_detail_name)
	_detail_line = UiTheme.label("", UiTheme.DIM, UiTheme.FONT_SMALL - 2)
	_detail_line.clip_text = true
	dbox.add_child(_detail_line)
	_detail_hint = UiTheme.label("", UiTheme.DIM, UiTheme.FONT_SMALL - 2, UiTheme.TEXT_DIM)
	_detail_hint.clip_text = true
	dbox.add_child(_detail_hint)
	_prompts = CenterContainer.new()
	_prompts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompts.custom_minimum_size = Vector2(0, 32)
	col.add_child(_prompts)


static func _frame_style(border: Color) -> UiFrameStyle:
	var s := UiTheme.card_style(border, Color(0.085, 0.073, 0.066, 0.98))
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s.rebuild()


func _make_row(i: int) -> PanelContainer:
	var def := ROW_DEFS[i]
	var panel := PanelContainer.new()
	panel.name = "Row_%s" % def["key"]
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row_panels.append(panel)
	var line := UiTheme.hbox(8)
	panel.add_child(line)
	var caption := UiTheme.label(String(def["caption"]), &"", UiTheme.FONT_SMALL + 2, UiTheme.TEXT)
	caption.custom_minimum_size.x = 104
	line.add_child(caption)
	var swatch := _Swatch.new()
	swatch.custom_minimum_size = Vector2(SWATCH, SWATCH)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(swatch)
	_swatches.append(swatch)
	line.add_child(UiIcon.create(UiIcon.Kind.ARROW_LEFT, Vector2(18, 24), UiTheme.GOLD_BORDER))
	var value := UiTheme.label("", &"", UiTheme.FONT_SMALL + 1, UiTheme.TEXT)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.clip_text = true
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_child(value)
	_value_labels.append(value)
	line.add_child(UiIcon.create(UiIcon.Kind.ARROW_RIGHT, Vector2(18, 24), UiTheme.GOLD_BORDER))
	return panel


# --- State ------------------------------------------------------------------------------------

## (Re)opens the picker for [param p_slot]; false for a slot without a class.
func open(p_slot: PlayerSlot) -> bool:
	if p_slot == null or p_slot.class_data == null:
		return false
	slot = p_slot
	mode = Mode.ROWS
	row = 0
	_list_row = -1
	visible = true
	skip_frames = 1
	var inp := slot.input
	_wait_neutral = inp != null and inp.nav_held() != Vector2i.ZERO
	preview.show_class(slot.class_data, slot.color)
	preview.model.set_tag("")
	_rebuild_options()
	refresh()
	return true


func is_open() -> bool:
	return visible


## Closes the picker: the choices are remembered for the class and saved once (a real profile), then [signal closed].
func close() -> void:
	if not visible:
		return
	if mode == Mode.LIST:
		_end_list(false)
	visible = false
	Meta.remember_loadout(slot)
	Meta.save()
	closed.emit()


func _rebuild_options() -> void:
	_options.clear()
	for def in ROW_DEFS:
		var key: StringName = def["key"]
		var list: Array[WardrobeEntry] = [WardrobeEntry.none(key, String(def["none"]))]
		if key in Profile.LOOK_SLOTS:
			list.append_array(WardrobeEntry.looks_of(key, true))
		else:
			list.append_array(WardrobeEntry.cosmetics_of(key, true))
		_options.append(list)


## The options of a row (the "nothing" entry first, then what the profile owns).
func options_of(row_index: int) -> Array[WardrobeEntry]:
	var out: Array[WardrobeEntry] = []
	out.assign(_options[row_index])
	return out


## The id chosen in a row ([constant ROW_DEFS] index); &"" = Worn gear / None.
func chosen_id(row_index: int) -> StringName:
	var key: StringName = ROW_DEFS[row_index]["key"]
	if key in Profile.LOOK_SLOTS:
		return slot.looks.get(key, &"")
	return slot.cosmetics.get(key, &"")


func _current_index(row_index: int) -> int:
	var id := chosen_id(row_index)
	var list := _options[row_index]
	for i in list.size():
		if (list[i] as WardrobeEntry).id == id:
			return i
	return 0


# --- Editing ----------------------------------------------------------------------------------

## Chooses [param id] (&"" clears) in the row [param row_index]; the slot, the profile's memory and the preview follow.
func choose(row_index: int, id: StringName) -> void:
	var key: StringName = ROW_DEFS[row_index]["key"]
	if key in Profile.LOOK_SLOTS:
		if id == &"":
			slot.looks.erase(key)
		else:
			slot.looks[key] = id
	else:
		if id == &"":
			slot.cosmetics.erase(key)
		else:
			slot.cosmetics[key] = id
	Meta.remember_loadout(slot)
	_dirty = true
	refresh()
	changed.emit(key, id)


## Steps the row's choice [param step] options forward / back (wraps).
func step_row(row_index: int, step: int) -> void:
	var list := _options[row_index]
	if list.size() <= 1:
		Audio.play_ui(&"ui_error")
		return
	var at := wrapi(_current_index(row_index) + step, 0, list.size())
	choose(row_index, (list[at] as WardrobeEntry).id)
	Audio.play_ui(&"ui_move")


## Clears the row (Worn gear / None).
func clear_row(row_index: int) -> void:
	if chosen_id(row_index) != &"":
		choose(row_index, &"")
		Audio.play_ui(&"ui_back")


## Clears every row.
func clear_all() -> void:
	var any := false
	for i in ROW_DEFS.size():
		if chosen_id(i) != &"":
			var key: StringName = ROW_DEFS[i]["key"]
			if key in Profile.LOOK_SLOTS:
				slot.looks.erase(key)
			else:
				slot.cosmetics.erase(key)
			any = true
	if any:
		Meta.remember_loadout(slot)
		Audio.play_ui(&"ui_back")
		_dirty = true
		refresh()
		changed.emit(&"", &"")


func _begin_list() -> void:
	var list := _options[row]
	if list.size() <= 1:
		Audio.play_ui(&"ui_error")
		return
	mode = Mode.LIST
	_list_row = row
	_before_id = chosen_id(row)
	var entries: Array[WardrobeEntry] = []
	entries.assign(list)
	grid.marked_id = _before_id
	grid.set_entries(entries, _before_id)
	grid.select_index(_current_index(row))
	Audio.play_ui(&"ui_open")
	refresh()


## Ends the list: [param keep] takes the entry under the cursor (it is already on the slot: moving the cursor chose it), else the old choice returns.
func _end_list(keep: bool) -> void:
	if mode != Mode.LIST:
		return
	var which := _list_row
	mode = Mode.ROWS
	_list_row = -1
	if not keep and chosen_id(which) != _before_id:
		choose(which, _before_id)
	Audio.play_ui(&"ui_confirm" if keep else &"ui_back")
	refresh()


func _on_cursor_changed(entry: WardrobeEntry) -> void:
	if mode != Mode.LIST or entry == null or _list_row < 0:
		return
	if chosen_id(_list_row) != entry.id:
		choose(_list_row, entry.id)
	else:
		refresh()


# --- Input ------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not self_driven or not visible or slot == null or slot.input == null:
		return
	var frame := Engine.get_process_frames()
	if _fed_frame == frame:
		return  # (a host fed this frame: do not read it twice)
	_own_frame = frame
	process_input(slot.input)


## One frame of the owner's input, fed by a host that routes it (set [member self_driven] = false). A frame the picker already
## read itself is skipped, so a host that forgot to switch [member self_driven] off still gets every press once.
func handle_input(inp: PlayerInput) -> void:
	if inp == null or not visible:
		return
	var frame := Engine.get_process_frames()
	if _own_frame == frame:
		return
	_fed_frame = frame
	process_input(inp)


## Reads one frame of [param inp] (skips the opening press first). Public for tests, which feed several steps in one engine frame.
func process_input(inp: PlayerInput) -> void:
	if inp == null or not visible:
		return
	if skip_frames > 0:
		skip_frames -= 1
		return
	if _wait_neutral:
		if inp.nav_held() == Vector2i.ZERO:
			_wait_neutral = false
		return
	var nav := inp.nav_just_pressed()
	if mode == Mode.LIST:
		_input_list(inp, nav)
	else:
		_input_rows(inp, nav)


func _input_rows(inp: PlayerInput, nav: Vector2i) -> void:
	if nav.y != 0:
		row = wrapi(row + nav.y, 0, ROW_DEFS.size())
		Audio.play_ui(&"ui_move")
		refresh()
	elif nav.x != 0:
		step_row(row, nav.x)
	if inp.just_pressed(PlayerInput.Pad.A):
		_begin_list()
	elif inp.just_pressed(PlayerInput.Pad.X):
		clear_row(row)
	elif inp.just_pressed(PlayerInput.Pad.Y):
		clear_all()
	elif inp.just_pressed(PlayerInput.Pad.B):
		Audio.play_ui(&"ui_back")
		close()


func _input_list(inp: PlayerInput, nav: Vector2i) -> void:
	if nav != Vector2i.ZERO and grid.move(nav):
		Audio.play_ui(&"ui_move")
	if inp.just_pressed(PlayerInput.Pad.A):
		_end_list(true)
	elif inp.just_pressed(PlayerInput.Pad.B):
		_end_list(false)


# --- Drawing ----------------------------------------------------------------------------------

## Rebuilds the rows, the preview and the detail line from the slot's current choices.
func refresh() -> void:
	if slot == null or slot.class_data == null:
		return
	_who.text = "%s · %s" % [slot.label(), slot.class_data.display_name]
	_who.add_theme_color_override(&"font_color", slot.color.lightened(0.35))
	add_theme_stylebox_override(&"panel", _frame_style(slot.color.lightened(0.15)))
	for i in ROW_DEFS.size():
		var list := _options[i]
		var entry := list[_current_index(i)] as WardrobeEntry
		_value_labels[i].text = entry.title
		var dim := entry.kind == WardrobeEntry.Kind.NONE
		_value_labels[i].add_theme_color_override(&"font_color", UiTheme.TEXT_DIM if dim else UiTheme.TEXT)
		_swatches[i].entry = entry
		_swatches[i].queue_redraw()
		row_panels[i].add_theme_stylebox_override(&"panel", _row_style(i == row and mode == Mode.ROWS))
	_rows_box.visible = mode == Mode.ROWS
	_list_box.visible = mode == Mode.LIST
	if mode == Mode.LIST:
		_list_title.text = "%s – choose" % ROW_DEFS[_list_row]["caption"]
	_dress_preview()
	_fill_detail()
	_fill_prompts()


func _dress_preview() -> void:
	if preview != null:
		preview.set_dress(OnionDress.for_slot(slot))


func _row_style(selected_row: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.17, 0.11, 0.95) if selected_row else Color(0.1, 0.09, 0.08, 0.9)
	style.border_color = UiTheme.GOLD if selected_row else Color(0.2, 0.17, 0.13)
	style.set_border_width_all(2 if selected_row else 1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


func _fill_detail() -> void:
	var entry: WardrobeEntry
	var key: StringName = ROW_DEFS[row]["key"]
	if mode == Mode.LIST and grid.selected() != null:
		entry = grid.selected()
	else:
		entry = _options[row][_current_index(row)] as WardrobeEntry
	var caption: String = ROW_DEFS[_list_row if mode == Mode.LIST else row]["caption"]
	_detail_name.text = entry.title
	if entry.kind == WardrobeEntry.Kind.NONE:
		if key in Profile.LOOK_SLOTS:
			_detail_line.text = "%s: shows the item you wear, or your class's own piece while the slot is empty." % caption
		else:
			_detail_line.text = "%s: nothing extra." % caption
		var have := _options[row].size() - 1
		_detail_hint.text = "%d to choose from." % have if have > 0 else _empty_hint(key)
	else:
		_detail_line.text = entry.detail
		_detail_hint.text = "Only for show: no stat changes."


func _empty_hint(key: StringName) -> String:
	if key in Profile.LOOK_SLOTS:
		return "Wear gear in a run to collect its looks."
	match key:
		&"dye":
			return "Buy dyes in The Onion Patch."
	return "Earn it with a Class Level or an achievement."


func _fill_prompts() -> void:
	for c in _prompts.get_children():
		_prompts.remove_child(c)
		c.queue_free()
	var inp := slot.input if slot != null else null
	var glyph := func(button: PlayerInput.Pad) -> UiGlyph:
		return UiGlyph.for_input(inp, button, 26.0) if inp != null else UiGlyph.pad(button, 26.0)
	var items: Array
	if mode == Mode.LIST:
		items = [[UiGlyph.nav(26.0, false), "Browse"], [glyph.call(PlayerInput.Pad.A), "Choose"], [glyph.call(PlayerInput.Pad.B), "Back"]]
	else:
		items = [[UiGlyph.nav(26.0, true), "Row"], [UiGlyph.nav(26.0, false), "Change"], [glyph.call(PlayerInput.Pad.A), "List"],
				[glyph.call(PlayerInput.Pad.X), "Clear"], [glyph.call(PlayerInput.Pad.B), "Done"]]
	var line := UiTheme.prompt_row(items, UiTheme.FONT_SMALL - 2)
	line.add_theme_constant_override(&"separation", 12)
	_prompts.add_child(line)


## A small picture of the row's current choice.
class _Swatch extends Control:
	var entry: WardrobeEntry

	func _draw() -> void:
		if entry != null:
			WardrobeIcon.draw_cell(self, Rect2(Vector2.ZERO, size), entry, false, false, false)
