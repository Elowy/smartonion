class_name LoadoutScreen
extends PanelContainer
## The per-hero Loadout of the lobby (M9 PATCH): the panel LT opens over a hero's card, with three tabs –
## Seasonings (the [SeasoningPicker], embedded), Heirloom ([LoadoutHeirloomTab]) and Look (WARDROBE's LookPicker when
## its script exists, else a "Coming soon" note). The hero's own input drives it while it is open (the Lobby routes
## PlayerSlot.input here and nowhere else): LB / RB (Q / E) or ◀ ▶ switch tabs, ▲ ▼ A work inside the tab, B or LT
## closes. Every pick is remembered per class by the tabs ([method Seasonings.toggle], [method Heirlooms.toggle] ->
## Meta.remember_loadout). The screen holds no selection: that is [member PlayerSlot.seasonings] / [member
## PlayerSlot.heirloom] / [member PlayerSlot.looks].
##
## The Look tab embeds [code]res://scenes/ui/meta/look_picker.gd[/code] (class LookPicker: [code]LookPicker.create(slot)[/code],
## signal [code]closed[/code]; it is loaded with [code]ResourceLoader.exists[/code] + [code]load[/code], so this package builds
## without it). Input reaches it through its optional [code]handle_input(inp: PlayerInput)[/code]; its [code]closed[/code]
## closes the whole Loadout.

signal closed
signal tab_changed(tab: int)

enum Tab { SEASONINGS, HEIRLOOM, LOOK }

const TAB_NAMES: Array[String] = ["Seasonings", "Heirloom", "Look"]
const LOOK_PICKER_PATH := "res://scenes/ui/meta/look_picker.gd"
const COMING_SOON_TEXT := "Coming soon"
const TAB_FONT := 20

## Where the Look tab looks for the LookPicker script (tests point it at a fake).
static var look_picker_path := LOOK_PICKER_PATH

var slot: PlayerSlot
var tab: Tab = Tab.SEASONINGS
var picker: SeasoningPicker
var heirloom_tab: LoadoutHeirloomTab
## The Look tab's holder, the embedded LookPicker (null until the tab is shown, and without the script) and the
## "Coming soon" label (shown without the script).
var look_holder: VBoxContainer
var look_picker: Control
var coming_soon: Label

var _open := false
var _closing := false
var _tab_labels: Array[Label] = []
var _tab_bar: HBoxContainer
var _tab_left: HBoxContainer
var _tab_right: HBoxContainer
var _body: MarginContainer
var _prompts: CenterContainer


static func create() -> LoadoutScreen:
	var s := LoadoutScreen.new()
	s.name = "LoadoutScreen"
	s._build()
	s.visible = false
	return s


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	add_theme_stylebox_override(&"panel", _frame_style(UiTheme.GOLD_BORDER))
	var col := UiTheme.vbox(4)
	add_child(col)
	_tab_bar = UiTheme.hbox(10)
	_tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_tab_bar)
	_tab_left = UiTheme.hbox(0)
	_tab_bar.add_child(_tab_left)
	for i in TAB_NAMES.size():
		var label := UiTheme.label(TAB_NAMES[i].to_upper(), UiTheme.HEADING, TAB_FONT, UiTheme.TEXT_DIM)
		label.name = "Tab_%s" % TAB_NAMES[i]
		_tab_bar.add_child(label)
		_tab_labels.append(label)
	_tab_right = UiTheme.hbox(0)
	_tab_bar.add_child(_tab_right)
	col.add_child(UiTheme.divider())
	_body = MarginContainer.new()  # (its minimum size is the tallest visible tab: the screen must fit the card)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.clip_contents = true
	col.add_child(_body)
	picker = SeasoningPicker.create()
	picker.set_embedded(true)
	picker.closed.connect(_on_picker_closed)
	_body.add_child(picker)
	heirloom_tab = LoadoutHeirloomTab.create()
	_body.add_child(heirloom_tab)
	look_holder = UiTheme.vbox(6)
	look_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(look_holder)
	coming_soon = UiTheme.centered_label("Look\n%s" % COMING_SOON_TEXT, UiTheme.DIM, UiTheme.FONT_LARGE)
	coming_soon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	look_holder.add_child(coming_soon)
	_prompts = CenterContainer.new()
	_prompts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompts.custom_minimum_size = Vector2(0, 32)
	col.add_child(_prompts)
	custom_minimum_size = Vector2.ZERO


static func _frame_style(border: Color) -> UiFrameStyle:
	var s := UiTheme.card_style(border, Color(0.085, 0.073, 0.066, 1.0))
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s.rebuild()


# --- State ---------------------------------------------------------------------------------------

func is_open() -> bool:
	return _open


## Opens the Loadout for [param p_slot] (a joined player with a class) on [param first_tab]. False when it cannot open.
func open(p_slot: PlayerSlot, first_tab: Tab = Tab.SEASONINGS) -> bool:
	if p_slot == null or p_slot.class_data == null:
		return false
	slot = p_slot
	if not picker.open(p_slot):
		slot = null
		return false
	heirloom_tab.open(p_slot)
	_open = true
	visible = true
	add_theme_stylebox_override(&"panel", _frame_style(p_slot.color.lightened(0.15)))
	tab = first_tab
	_apply_tab()
	return true


func close() -> void:
	if not _open:
		return
	_closing = true
	if picker.is_open():
		picker.close()
	_closing = false
	_finish_close()


func _on_picker_closed() -> void:
	if _closing or not _open:
		return
	_finish_close()


func _finish_close() -> void:
	_open = false
	visible = false
	_drop_look_picker()
	closed.emit()


## Shows [param value] (wraps nothing: out of range is ignored).
func set_tab(value: Tab) -> void:
	if value < 0 or value >= TAB_NAMES.size() or not _open:
		return
	tab = value
	_apply_tab()


## Moves to the next / previous tab (wraps).
func switch_tab(step: int) -> void:
	if not _open or step == 0:
		return
	tab = wrapi(tab + step, 0, TAB_NAMES.size()) as Tab
	Audio.play_ui(&"ui_move")
	_apply_tab()


## One frame of the owner's input (the Lobby calls it while the screen is open): LB / RB switch tabs, the rest goes to
## the tab on show; B / LT close.
func handle_input(inp: PlayerInput) -> void:
	if inp == null or not _open:
		return
	if inp.just_pressed(PlayerInput.Pad.LB):
		switch_tab(-1)
		return
	if inp.just_pressed(PlayerInput.Pad.RB):
		switch_tab(1)
		return
	match tab:
		Tab.SEASONINGS:
			var nav := inp.nav_just_pressed()
			if nav.x != 0:
				switch_tab(nav.x)
				return
			picker.handle_input(inp)
			if _open:
				_fill_prompts()
		Tab.HEIRLOOM:
			var nav := inp.nav_just_pressed()
			if nav.x != 0:
				switch_tab(nav.x)
				return
			if inp.just_pressed(PlayerInput.Pad.B) or inp.just_pressed(PlayerInput.Pad.LT):
				Audio.play_ui(&"ui_back")
				close()
				return
			heirloom_tab.handle_input(inp)
			if _open:
				_fill_prompts()
		Tab.LOOK:
			if look_picker != null and is_instance_valid(look_picker) and inp.just_pressed(PlayerInput.Pad.LT):
				# LT closes the Loadout from every tab; the picker's own close remembers and saves the choices.
				Audio.play_ui(&"ui_back")
				look_picker.call(&"close")
				if _open:
					close()
				return
			if look_picker != null and is_instance_valid(look_picker) and look_picker.has_method(&"handle_input"):
				look_picker.call(&"handle_input", inp)
			elif inp.just_pressed(PlayerInput.Pad.B) or inp.just_pressed(PlayerInput.Pad.LT):
				Audio.play_ui(&"ui_back")
				close()
				return
			else:
				var nav := inp.nav_just_pressed()
				if nav.x != 0:
					switch_tab(nav.x)


# --- Tabs ------------------------------------------------------------------------------------------

func _apply_tab() -> void:
	picker.visible = tab == Tab.SEASONINGS
	heirloom_tab.visible = tab == Tab.HEIRLOOM
	look_holder.visible = tab == Tab.LOOK
	if tab == Tab.SEASONINGS:
		picker.refresh()
	elif tab == Tab.HEIRLOOM:
		heirloom_tab.refresh()
	if tab == Tab.LOOK:
		_show_look()
	else:
		_drop_look_picker()
	for i in _tab_labels.size():
		var on := i == tab
		_tab_labels[i].add_theme_color_override(&"font_color", UiTheme.GOLD_BRIGHT if on else UiTheme.TEXT_DIM)
		_tab_labels[i].add_theme_constant_override(&"outline_size", 5 if on else 0)
	_fill_tab_glyphs()
	_fill_prompts()
	tab_changed.emit(tab)


## Whether WARDROBE's LookPicker script is there ([member look_picker_path]).
static func look_picker_available() -> bool:
	return ResourceLoader.exists(look_picker_path)


## The Look tab: the embedded LookPicker, or the "Coming soon" note without the script.
func _show_look() -> void:
	_drop_look_picker()
	coming_soon.visible = true
	if not look_picker_available():
		return
	var script: Variant = load(look_picker_path)
	if script == null or not (script as Object).has_method(&"create"):
		return
	var created: Variant = (script as Object).call(&"create", slot)
	if not (created is Control):
		return
	look_picker = created as Control
	# The Loadout routes the owner's input (handle_input below), so the picker must not read it a second time.
	if &"self_driven" in look_picker:
		look_picker.set(&"self_driven", false)
	look_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	look_holder.add_child(look_picker)
	coming_soon.visible = false
	if look_picker.has_signal(&"closed"):
		look_picker.connect(&"closed", _on_look_closed)
	if look_picker.has_method(&"open"):
		look_picker.call(&"open", slot)


func _on_look_closed() -> void:
	if _open:
		close()


func _drop_look_picker() -> void:
	if look_picker != null and is_instance_valid(look_picker):
		# A pick is remembered at once (Meta.remember_loadout) but written only when the picker closes itself:
		# leaving the Look tab another way still saves it.
		Meta.save()
		if look_holder != null and look_picker.get_parent() == look_holder:
			look_holder.remove_child(look_picker)
		look_picker.queue_free()
	look_picker = null
	if coming_soon != null:
		coming_soon.visible = true


## The LB / RB glyphs on both sides of the tab names.
func _fill_tab_glyphs() -> void:
	for box in [_tab_left, _tab_right]:
		for c in (box as Control).get_children():
			(box as Control).remove_child(c)
			c.queue_free()
	var inp := slot.input if slot != null else null
	_tab_left.add_child(UiGlyph.for_input(inp, PlayerInput.Pad.LB, 24.0) if inp != null else UiGlyph.pad(PlayerInput.Pad.LB, 24.0))
	_tab_right.add_child(UiGlyph.for_input(inp, PlayerInput.Pad.RB, 24.0) if inp != null else UiGlyph.pad(PlayerInput.Pad.RB, 24.0))


func _fill_prompts() -> void:
	for c in _prompts.get_children():
		_prompts.remove_child(c)
		c.queue_free()
	var inp := slot.input if slot != null else null
	var a_label := ""
	match tab:
		Tab.SEASONINGS:
			a_label = picker.action_label()
		Tab.HEIRLOOM:
			a_label = heirloom_tab.action_label()
	var items: Array = [[UiGlyph.nav(26.0, true), "Move"]]
	if a_label != "":
		items.append([UiGlyph.for_input(inp, PlayerInput.Pad.A, 26.0) if inp != null else UiGlyph.pad(PlayerInput.Pad.A, 26.0), a_label])
	items.append([UiGlyph.for_input(inp, PlayerInput.Pad.B, 26.0) if inp != null else UiGlyph.pad(PlayerInput.Pad.B, 26.0), "Back"])
	var row := UiTheme.prompt_row(items, UiTheme.FONT_SMALL)
	row.add_theme_constant_override(&"separation", 14)
	_prompts.add_child(row)
