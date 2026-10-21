class_name WardrobePage
extends VBoxContainer
## The Wardrobe tab of The Onion Patch (M9 WARDROBE, design_m9 section 8): the collection browser. A header with the collected counter
## ("37 / 256 looks") and the Seeds wallet; the filters Head / Shoulders / Chest / Cosmetics (Tabards, Hats, Glows) / Dyes with
## their own counts; a grid of every look or cosmetic of the filter (collected ones in colour, the others dimmed with a lock); a
## 3D preview of the selected one worn by an onion, its name, what it is and how to get it; and the purchase of a Dye for 100 Seeds.
## Read-only otherwise: what a hero wears is chosen in the [LookPicker].
##
## The page is a plain Control: the host (the Onion Patch) adds it to its tab area and feeds it the input of whoever drives the menu:
## [code]if page.handle_input(slot.input): return[/code] every frame. Controls: ◀ ▶ ▲ ▼ move (the filter row, then the grid), A
## buys the selected Dye, X turns the preview. [method handle_input] returns true when it used the input; it leaves B, LB / RB
## (the host's back / tab keys) and Up on the filter row (the host's tab bar) alone and returns false for them.
## A host that routes the buttons itself (the Onion Patch: nobody has joined at the title screen, so no PlayerInput) calls
## [method handle_nav] / [method handle_accept] / [method handle_turn], hides the page's own prompt row
## ([method set_prompts_visible]) and shows [method action_text] / [method x_text] in its own, with the glyphs of its driver.

## A Dye was bought ([param id] is the CosmeticData id).
signal purchased(id: StringName)

enum Focus { FILTERS, GRID }

## The filters: key, caption. Looks are filtered by slot; "cosmetics" = Tabards, Hats and Glows; "dyes" = the Dyes.
const FILTERS: Array[Dictionary] = [
	{"key": &"head", "caption": "Head"},
	{"key": &"shoulders", "caption": "Shoulders"},
	{"key": &"chest", "caption": "Chest"},
	{"key": &"cosmetics", "caption": "Cosmetics"},
	{"key": &"dyes", "caption": "Dyes"},
]
const PREVIEW_SIZE := Vector2(340, 300)
## One X press turns the preview this far.
const TURN_DEGREES := 60.0

var filter := 0
var focus := Focus.FILTERS
var grid: WardrobeGrid
var preview: OnionPreview
## The class (and ring colour) the preview onion is dressed as: the Patch may set the class the player cares about.
var preview_class: ClassData
var preview_color := Color(0.4, 0.7, 1.0)

var _counter: Label
var _seeds: Label
var _chips: Array[PanelContainer] = []
var _chip_labels: Array[Label] = []
var _name: Label
var _detail: Label
var _status: Label
var _prompts: CenterContainer
var _last_buy: StringName = &""


static func create() -> WardrobePage:
	var page := WardrobePage.new()
	page.name = "WardrobePage"
	page._build()
	page.refresh()
	return page


func _build() -> void:
	add_theme_constant_override(&"separation", 8)
	custom_minimum_size = Vector2(1000, 520)
	# Header: title, the collected counter, the wallet.
	var head := UiTheme.hbox(14)
	add_child(head)
	head.add_child(UiTheme.label("WARDROBE", UiTheme.HEADING, 30, UiTheme.GOLD))
	head.add_child(UiTheme.spacer())
	_counter = UiTheme.label("", UiTheme.GOLD_LABEL, UiTheme.FONT_BODY)
	head.add_child(_counter)
	_seeds = UiTheme.label("", &"", UiTheme.FONT_BODY, UiTheme.TEXT)
	head.add_child(_seeds)
	# Filter chips.
	var chips := UiTheme.hbox(8)
	add_child(chips)
	for i in FILTERS.size():
		var chip := PanelContainer.new()
		chip.name = "Filter_%s" % FILTERS[i]["key"]
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := UiTheme.centered_label("", &"", UiTheme.FONT_SMALL + 2, UiTheme.TEXT)
		chip.add_child(label)
		chips.add_child(chip)
		_chips.append(chip)
		_chip_labels.append(label)
	# Body: the grid and the detail panel.
	var body := UiTheme.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var grid_panel := UiTheme.panel(UiTheme.INSET_PANEL)
	grid_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid_panel)
	grid = WardrobeGrid.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.cursor_changed.connect(_on_cursor_changed)
	grid_panel.add_child(grid)
	var side := UiTheme.panel(UiTheme.INSET_PANEL)
	side.custom_minimum_size = Vector2(PREVIEW_SIZE.x + 24.0, 0)
	body.add_child(side)
	var sbox := UiTheme.vbox(4)
	side.add_child(sbox)
	preview = OnionPreview.create()
	preview.custom_minimum_size = PREVIEW_SIZE
	preview.frame_tall()
	sbox.add_child(preview)
	_name = UiTheme.label("", UiTheme.HEADING, 24, UiTheme.GOLD_BRIGHT)
	_name.clip_text = true
	sbox.add_child(_name)
	_detail = UiTheme.label("", UiTheme.DIM, UiTheme.FONT_SMALL - 1)
	_detail.clip_text = true
	sbox.add_child(_detail)
	_status = UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL - 1, UiTheme.TEXT_DIM)
	_status.custom_minimum_size.y = 58
	_status.max_lines_visible = 3
	sbox.add_child(_status)
	_prompts = CenterContainer.new()
	_prompts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompts.custom_minimum_size = Vector2(0, 32)
	add_child(_prompts)


func _enter_tree() -> void:
	if not Meta.seeds_changed.is_connected(_on_seeds_changed):
		Meta.seeds_changed.connect(_on_seeds_changed)
	if not Meta.profile_replaced.is_connected(refresh):
		Meta.profile_replaced.connect(refresh)


func _exit_tree() -> void:
	if Meta.seeds_changed.is_connected(_on_seeds_changed):
		Meta.seeds_changed.disconnect(_on_seeds_changed)
	if Meta.profile_replaced.is_connected(refresh):
		Meta.profile_replaced.disconnect(refresh)


# --- Content ----------------------------------------------------------------------------------

## The entries of filter [param index]: all the looks of a slot (collected first is NOT applied: collection order keeps the grid stable),
## or the cosmetics (every kind but dyes) / the dyes.
func entries_for(index: int) -> Array[WardrobeEntry]:
	var key: StringName = FILTERS[index]["key"]
	match key:
		&"cosmetics":
			var out: Array[WardrobeEntry] = []
			for kind: StringName in [CosmeticData.KIND_TABARD, CosmeticData.KIND_HAT, CosmeticData.KIND_GLOW]:
				out.append_array(WardrobeEntry.cosmetics_of(kind))
			return out
		&"dyes":
			return WardrobeEntry.cosmetics_of(CosmeticData.KIND_DYE)
	return WardrobeEntry.looks_of(key)


## "owned / total" of the filter [param index].
func counts_for(index: int) -> Vector2i:
	var list := entries_for(index)
	var owned := 0
	for e in list:
		if e.owned:
			owned += 1
	return Vector2i(owned, list.size())


## Rebuilds everything from the profile (after a purchase, a profile change, or a run that collected looks).
func refresh() -> void:
	if grid == null:
		return
	var keep := grid.selected().id if grid.selected() != null else &""
	grid.set_entries(entries_for(filter), keep)
	grid.focused = focus == Focus.GRID
	_counter.text = "%d / %d looks" % [Wardrobe.collected_count(), Wardrobe.total_count()]
	_seeds.text = "   %s Seeds" % UiTheme.format_int(Meta.seeds())
	for i in FILTERS.size():
		var c := counts_for(i)
		_chip_labels[i].text = "%s  %d/%d" % [FILTERS[i]["caption"], c.x, c.y]
		_chips[i].add_theme_stylebox_override(&"panel", _chip_style(i == filter, focus == Focus.FILTERS))
	_update_detail(grid.selected())
	_fill_prompts()


func _chip_style(selected_chip: bool, has_focus: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.24, 0.19, 0.1, 0.96) if selected_chip else Color(0.1, 0.09, 0.08, 0.9)
	style.border_color = (UiTheme.GOLD if has_focus else UiTheme.GOLD_DARK) if selected_chip else Color(0.2, 0.17, 0.13)
	style.set_border_width_all(3 if selected_chip and has_focus else (2 if selected_chip else 1))
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


## Switches the filter (wraps).
func set_filter(index: int) -> void:
	filter = wrapi(index, 0, FILTERS.size())
	grid.set_entries(entries_for(filter))
	refresh()


## Sets the onion of the preview (a class and its ring colour).
func set_preview_class(cd: ClassData, color: Color = Color(0.4, 0.7, 1.0)) -> void:
	preview_class = cd
	preview_color = color
	_update_detail(grid.selected() if grid != null else null)


# --- Detail and preview -----------------------------------------------------------------------

func _on_cursor_changed(entry: WardrobeEntry) -> void:
	_update_detail(entry)
	_fill_prompts()


func _on_seeds_changed(_total: int, _delta: int) -> void:
	refresh()


## The entry the page shows (the grid's cursor).
func selected() -> WardrobeEntry:
	return grid.selected() if grid != null else null


func _update_detail(entry: WardrobeEntry) -> void:
	if entry == null:
		_name.text = ""
		_detail.text = ""
		_status.text = ""
		return
	_name.text = entry.title
	_detail.text = entry.detail
	if entry.owned:
		_status.text = "Collected." if entry.kind == WardrobeEntry.Kind.LOOK else "Yours."
		_status.add_theme_color_override(&"font_color", UiTheme.GREEN)
	else:
		_status.text = entry.hint
		_status.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
		if entry.price > 0:
			var short := entry.price - Meta.seeds()
			_status.text += "\nA: buy for %d Seeds." % entry.price if short <= 0 else "\nNeeds %d more Seeds." % short
			_status.add_theme_color_override(&"font_color", UiTheme.GOLD if short <= 0 else UiTheme.RED)
	_dress_preview(entry)


func _dress_preview(entry: WardrobeEntry) -> void:
	var cd := preview_class if preview_class != null else Meta.default_class()
	if cd == null or preview == null:
		return
	preview.show_class(cd, preview_color)
	preview.model.set_tag("")
	var dress := OnionDress.new()
	if entry.kind == WardrobeEntry.Kind.LOOK and entry.look != null:
		dress.looks[entry.look.slot] = entry.look
	elif entry.kind == WardrobeEntry.Kind.COSMETIC and entry.cosmetic != null:
		var c := entry.cosmetic
		match c.kind:
			CosmeticData.KIND_TABARD: dress.tabard = c
			CosmeticData.KIND_HAT: dress.hat = c
			CosmeticData.KIND_GLOW: dress.glow = c
			CosmeticData.KIND_DYE:
				# A Dye is shown on a Tabard and a Glow.
				dress.dye = c
				dress.tabard = Db.get_cosmetic(&"cos_gala_tabard")
				dress.glow = Db.get_cosmetic(&"cos_salt_crystal_glow")
	preview.set_dress(dress)


# --- Input ------------------------------------------------------------------------------------

## One frame of the driver's input (see the class doc). Returns true when it used the input. Call it once per rendered frame.
func handle_input(inp: PlayerInput) -> bool:
	if inp == null or not is_visible_in_tree():
		return false
	var used := handle_nav(inp.nav_just_pressed())
	if inp.just_pressed(PlayerInput.Pad.A):
		handle_accept()
		used = true
	if inp.just_pressed(PlayerInput.Pad.X):
		handle_turn()
		used = true
	return used


## The X press: turns the preview onion.
func handle_turn() -> void:
	if preview != null:
		preview.turn(TURN_DEGREES)


## One navigation step (a host such as The Onion Patch, which drives pages without a [PlayerInput], calls it directly).
## Returns true when it used the step; Up on the filter row is left to the host.
func handle_nav(nav: Vector2i) -> bool:
	if nav == Vector2i.ZERO or not is_visible_in_tree():
		return false
	if focus == Focus.FILTERS:
		if nav.x != 0:
			set_filter(filter + nav.x)
			Audio.play_ui(&"ui_move")
			return true
		if nav.y > 0 and not grid.entries.is_empty():
			_set_focus(Focus.GRID)
			Audio.play_ui(&"ui_move")
			return true
		return false
	if grid.move(nav):
		Audio.play_ui(&"ui_move")
	elif nav.y < 0:
		_set_focus(Focus.FILTERS)
		Audio.play_ui(&"ui_move")
	return true


## The A press: [method activate] on the selected entry.
func handle_accept() -> void:
	if is_visible_in_tree():
		activate()


func _set_focus(f: Focus) -> void:
	focus = f
	refresh()


## The A action on the selected entry: buys a Dye. Returns the Wardrobe.RESULT_ of the purchase (&"" for an entry that is not for sale).
func activate() -> StringName:
	var e := grid.selected()
	_last_buy = &""
	if e == null or e.kind != WardrobeEntry.Kind.COSMETIC or e.price <= 0:
		return &""
	_last_buy = Wardrobe.buy_cosmetic(e.id)
	match _last_buy:
		Wardrobe.RESULT_BOUGHT:
			Audio.play_ui(&"ui_confirm")
			refresh()
			purchased.emit(e.id)
		Wardrobe.RESULT_OWNED, Wardrobe.RESULT_POOR, Wardrobe.RESULT_INVALID:
			Audio.play_ui(&"ui_error")
	return _last_buy


## The result of the last [method activate] (&"" before one).
func last_result() -> StringName:
	return _last_buy


## What A does on the selected entry ("Buy" for a Dye that is for sale and not yet owned, else "").
func action_text() -> String:
	var e := grid.selected() if grid != null else null
	if e != null and e.kind == WardrobeEntry.Kind.COSMETIC and e.price > 0 and not e.owned:
		return "Buy"
	return ""


## What X does ("Turn": the preview).
func x_text() -> String:
	return "Turn"


## Shows or hides the page's own prompt row (a host that has its own row hides it).
func set_prompts_visible(shown: bool) -> void:
	if _prompts != null:
		_prompts.visible = shown


func _fill_prompts() -> void:
	if _prompts == null:
		return
	for c in _prompts.get_children():
		_prompts.remove_child(c)
		c.queue_free()
	var items: Array = [[UiGlyph.nav(26.0, false), "Move"]]
	if action_text() != "":
		items.append([UiGlyph.pad(PlayerInput.Pad.A, 26.0), action_text()])
	items.append([UiGlyph.pad(PlayerInput.Pad.X, 26.0), x_text()])
	var line := UiTheme.prompt_row(items, UiTheme.FONT_SMALL - 2)
	line.add_theme_constant_override(&"separation", 14)
	_prompts.add_child(line)
