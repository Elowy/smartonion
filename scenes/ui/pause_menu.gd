class_name PauseMenu
extends Control
## Pause overlay (GDD 11): dimmed game, "Paused by P2", Resume / Settings / Quit to Menu.
## Only the player who paused navigates (their own input: stick / d-pad, A selects);
## that player's B or ANY player's START resumes. process_mode is ALWAYS, Main pauses the tree.
## With no pausing slot (null, or the pausing player's controller got unplugged) the keyboard
## ui_* actions and any controller drive it.
## - The press / stick push that opened the menu is ignored: navigation waits until the stick
##   / d-pad has been neutral once (the stick the player was steering with in the game).
## - "Settings" opens the [SettingsPage] over the menu, driven by the same player (or by anyone in the slot-less
##   case); the menu waits meanwhile (START does not resume) and B / Back return to it.
## - "Quit to Menu" asks for a second press ("Are you sure?"); moving the highlight cancels.
## - While a joined player's controller is unplugged the game cannot be resumed (START / B /
##   Resume do nothing); the menu says "P3 disconnected – press A on any free controller to take over" (the
##   take-over itself is PlayerManager's: a pad nobody plays presses A) and offers "Continue without Pn" for each of
##   them (asks "Are you sure?" first; drop_player_requested – Main removes that player and goes on).
## - Host rules (HostRules): a Remote Play guest's slot, a guest's pad and a pad nobody plays cannot Quit to Menu or
##   drop a player; the menu says "Only the host can do that".
## See docs/ARCHITECTURE.md.

signal resume_requested
signal quit_to_menu_requested
## "Continue without Pn" was chosen for the player whose controller is unplugged.
signal drop_player_requested(slot: PlayerSlot)

## Entry codes (display order: Resume, the "Continue without" offers, Settings, Quit).
enum Item { RESUME, QUIT, SETTINGS }

## Entry codes of the "Continue without Pn" buttons are DROP_BASE + the player's slot index.
const DROP_BASE := 10
const SETTINGS_TEXT := "Settings"
const QUIT_TEXT := "Quit to Menu"
const QUIT_CONFIRM_TEXT := "Are you sure?  Press again"
const DROP_CONFIRM_TEXT := QUIT_CONFIRM_TEXT
## Seconds the "Only the host can do that" line stays.
const REFUSAL_TIME := 2.5

var slot: PlayerSlot
## Code of the highlighted entry: an Item, or DROP_BASE + slot index.
var selected: int = Item.RESUME
## Entry codes in display order: Resume, one "Continue without Pn" per unplugged player, Settings, Quit.
var entries: Array[int] = []
## One button per entry (same order as [member entries]).
var buttons: Array[Button] = []
## "Quit to Menu" was pressed once; the next press quits.
var quit_armed := false
## The "Continue without Pn" entry (DROP_BASE + index) that was pressed once; the next press drops the player. -1 = none.
var drop_armed := -1
## Controller edges for the slot-less fallback. Public for tests.
var pads := UiPads.new()
## The Settings page, created the first time it is opened.
var settings_page: SettingsPage

var _by_label: Label
var _missing_label: Label
var _refusal_label: Label
var _refusal_left := 0.0
var _list: VBoxContainer
var _prompts: CenterContainer
## The panel with the entries: hidden while the Settings page is open.
var _center: Control
## The press that opened the menu must not also close it (first frame is skipped).
var _skip_frames := 0
## The stick / d-pad was held when the menu opened: no navigation until it is neutral once.
var _wait_neutral := false
var _entries_key := ""
var _header_key := ""
var _styles: Dictionary[String, StyleBox] = {}


static func create() -> PauseMenu:
	var m := PauseMenu.new()
	m.name = "PauseMenu"
	m.process_mode = Node.PROCESS_MODE_ALWAYS
	m._build()
	return m


## [param p_slot] is the player who paused (only they can navigate; any START resumes).
func open(p_slot: PlayerSlot) -> void:
	slot = p_slot
	_close_settings()
	selected = Item.RESUME
	quit_armed = false
	drop_armed = -1
	_refusal_left = 0.0
	_skip_frames = 1
	_wait_neutral = slot != null and slot.input != null and slot.input.nav_held() != Vector2i.ZERO
	_entries_key = ""
	_header_key = ""
	_refresh()
	_fill_prompts()
	Audio.play_ui(&"ui_open")
	show()


## Moves the highlight by [param step] (wraps) and cancels a pending quit confirmation.
func move_selection(step: int) -> void:
	var i := entries.find(selected)
	selected = entries[wrapi(maxi(i, 0) + step, 0, entries.size())]
	quit_armed = false
	drop_armed = -1
	Audio.play_ui(&"ui_move")
	_update_selection()


## The button of entry [param code] (an Item or DROP_BASE + slot index); null when it is not listed.
func button_for(code: int) -> Button:
	var i := entries.find(code)
	return buttons[i] if i >= 0 else null


## True while the Settings page covers the menu.
func is_settings_open() -> bool:
	return settings_page != null and settings_page.visible


## What A / a click does: like [method activate_selected], but "Quit to Menu" and "Continue without Pn" first ask
## "Are you sure?" and only act on the second press. [param allowed] false: the presser may not do destructive things
## (HostRules) – Quit and Continue-without are refused with a line of text instead.
func press_selected(allowed: bool = true) -> void:
	var destructive := selected == Item.QUIT or selected >= DROP_BASE
	if destructive and not allowed:
		_refuse()
		return
	if selected == Item.QUIT and not quit_armed:
		quit_armed = true
		Audio.play_ui(&"ui_confirm")
		_update_selection()
		return
	if selected >= DROP_BASE and drop_armed != selected:
		drop_armed = selected
		Audio.play_ui(&"ui_confirm")
		_update_selection()
		return
	activate_selected()


func _refuse() -> void:
	Audio.play_ui(&"ui_error")
	_refusal_left = REFUSAL_TIME
	_refusal_label.visible = true


## Runs the highlighted entry at once (no confirmation).
func activate_selected() -> void:
	if selected == Item.QUIT:
		_quit()
	elif selected == Item.RESUME:
		_try_resume()
	elif selected == Item.SETTINGS:
		_open_settings()
	else:
		_drop(selected - DROP_BASE)


# --- Build ---------------------------------------------------------------------------

func _build() -> void:
	UiTheme.setup_root(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.02, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_center = center
	var panel := UiTheme.panel()
	var style := UiTheme.stone_style()
	style.content_margin_left = 54
	style.content_margin_right = 54
	style.content_margin_top = 26
	style.content_margin_bottom = 30
	panel.add_theme_stylebox_override(&"panel", style.rebuild())
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var col := UiTheme.vbox(14)
	panel.add_child(col)
	col.add_child(UiTheme.centered_label("Paused", UiTheme.TITLE, 84))
	_by_label = UiTheme.centered_label("Paused by P1", UiTheme.GOLD_LABEL, 26)
	col.add_child(_by_label)
	col.add_child(UiTheme.divider(380))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	col.add_child(gap)
	_styles["selected"] = UiTheme.button_style("selected")
	_styles["normal"] = UiTheme.button_style("normal")
	_missing_label = UiTheme.wrapped_label("", UiTheme.DIM, UiTheme.FONT_BODY)
	_missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_missing_label.add_theme_color_override(&"font_color", UiTheme.RED.lightened(0.25))
	_missing_label.visible = false
	col.add_child(_missing_label)
	_list = UiTheme.vbox(14)
	col.add_child(_list)
	_refusal_label = UiTheme.centered_label(HostRules.REFUSED_TEXT, UiTheme.DIM, UiTheme.FONT_BODY)
	_refusal_label.add_theme_color_override(&"font_color", UiTheme.RED.lightened(0.25))
	_refusal_label.visible = false
	col.add_child(_refusal_label)
	_refresh_entries()
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 4)
	col.add_child(gap2)
	_prompts = CenterContainer.new()
	_prompts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_prompts)
	visible = false


func _fill_prompts() -> void:
	for c in _prompts.get_children():
		_prompts.remove_child(c)
		c.queue_free()
	var inp: PlayerInput = slot.input if slot != null else null
	var a := UiGlyph.for_input(inp, PlayerInput.Pad.A, 28.0) if inp != null else UiGlyph.pad(PlayerInput.Pad.A, 28.0)
	var b := UiGlyph.for_input(inp, PlayerInput.Pad.B, 28.0) if inp != null else UiGlyph.pad(PlayerInput.Pad.B, 28.0)
	var items: Array = [
		[UiGlyph.nav(28.0, true), "Choose"],
		[a, "Select"],
		[b, "/", UiGlyph.pad(PlayerInput.Pad.START, 28.0), "Resume"],
	]
	if not PlayerManager.disconnected_slots().is_empty():
		items.append([UiGlyph.pad(PlayerInput.Pad.A, 28.0), "Free controller: take over"])
	_prompts.add_child(UiTheme.prompt_row(items, UiTheme.FONT_BODY - 1, UiTheme.TEXT_DIM))


func _update_selection() -> void:
	for i in buttons.size():
		var b := buttons[i]
		var code := entries[i]
		var on := code == selected
		b.add_theme_stylebox_override(&"normal", _styles["selected"] if on else _styles["normal"])
		b.add_theme_color_override(&"font_color", UiTheme.GOLD_BRIGHT if on else UiTheme.TEXT)
		if code == Item.QUIT:
			b.text = QUIT_CONFIRM_TEXT if quit_armed else QUIT_TEXT
		elif code >= DROP_BASE:
			b.text = DROP_CONFIRM_TEXT if drop_armed == code else _drop_text(code - DROP_BASE)


## Rebuilds the entry list when the set of unplugged players changed, and the header line.
func _refresh() -> void:
	_refresh_entries()
	var driver := _driver()
	var key := str(driver.index if driver != null else -1)
	if key == _header_key:
		return
	_header_key = key
	if driver != null:
		_by_label.text = "Paused by %s" % driver.label()
		_by_label.add_theme_color_override(&"font_color", driver.color.lightened(0.3))
	else:
		_by_label.text = "Game paused"
		_by_label.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)


func _drop_text(slot_index: int) -> String:
	var target := PlayerManager.get_slot(slot_index)
	return "Continue without %s" % (RemotePlay.slot_label(target) if target != null else "P%d" % (slot_index + 1))


func _refresh_entries() -> void:
	var missing := PlayerManager.disconnected_slots()
	var key := ""
	for m in missing:
		key += "%d:%s," % [m.index, RemotePlay.slot_name(m)]
	if key == _entries_key and not buttons.is_empty():
		return
	_entries_key = key
	for b in buttons:
		_list.remove_child(b)
		b.queue_free()
	buttons.clear()
	entries.clear()
	_add_entry(Item.RESUME, "Resume")
	var names: Array[String] = []
	for m in missing:
		_add_entry(DROP_BASE + m.index, _drop_text(m.index))
		names.append(RemotePlay.slot_label(m))
	_add_entry(Item.SETTINGS, SETTINGS_TEXT)
	_add_entry(Item.QUIT, QUIT_TEXT)
	if not entries.has(selected):
		selected = Item.RESUME
	quit_armed = false
	drop_armed = -1
	_missing_label.visible = not names.is_empty()
	if not names.is_empty():
		_missing_label.text = "%s disconnected – press A on any free controller to take over,\nor wait for %s to come back." % [
			", ".join(names), "them" if names.size() > 1 else ("them" if missing[0].is_remote() else "the controller")]
	_update_selection()
	if _prompts != null and visible:
		_fill_prompts()


func _add_entry(code: int, text: String) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(420, 68)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_list.add_child(b)
	buttons.append(b)
	entries.append(code)
	b.mouse_entered.connect(func() -> void:
		if selected != code:
			selected = code
			quit_armed = false
			_update_selection())
	b.pressed.connect(func() -> void:
		selected = code
		press_selected())


## The player whose own input navigates: the one who paused, while they are still joined and
## their controller works. Null = the slot-less fallback (keyboard actions, any controller).
func _driver() -> PlayerSlot:
	if slot != null and slot.input != null and PlayerManager.get_slot(slot.index) == slot \
			and slot.input.is_connected_device():
		return slot
	return null


# --- Frame ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	pads.poll()
	if not visible:
		return
	_refresh()
	if _refusal_left > 0.0:
		_refusal_left -= delta
		_refusal_label.visible = _refusal_left > 0.0
	if PlayerManager.consume_takeover():
		_header_key = ""  # (a free pad just took a missing slot over: its A is not a press of this menu)
		return
	if is_settings_open():
		return  # (the page reads its driver's input itself)
	if _skip_frames > 0:
		_skip_frames -= 1
		return
	for s in PlayerManager.get_slots():
		if s.input != null and s.input.just_pressed(PlayerInput.Pad.START):
			_try_resume()
			return
	var driver := _driver()
	if driver != null:
		var inp := driver.input
		if inp.just_pressed(PlayerInput.Pad.B):
			_try_resume()
			return
		if _wait_neutral:
			if inp.nav_held() == Vector2i.ZERO:
				_wait_neutral = false
		else:
			var nav := inp.nav_just_pressed()
			if nav.y != 0:
				move_selection(nav.y)
		if inp.just_pressed(PlayerInput.Pad.A):
			press_selected(HostRules.may(_selected_action(), driver))
		return
	# Fallback without a (working) pausing player: keyboard actions and any controller.
	if Input.is_action_just_pressed(&"ui_cancel") or pads.any_just_pressed(JOY_BUTTON_B) \
			or pads.any_just_pressed(JOY_BUTTON_START):
		_try_resume()
		return
	if Input.is_action_just_pressed(&"ui_up"):
		move_selection(-1)
	elif Input.is_action_just_pressed(&"ui_down"):
		move_selection(1)
	var kb_accept := Input.is_action_just_pressed(&"ui_accept")
	if kb_accept or pads.any_just_pressed(JOY_BUTTON_A):
		# (Pads: a guest's or a free pad's A cannot Quit / drop – the keyboard and the mouse are the host's.)
		press_selected(kb_accept or HostRules.may_any_device(_selected_action(), pads.just_pressed_devices(JOY_BUTTON_A),
				PlayerManager.count() > 0))


## The host rule of the highlighted entry (only destructive ones are checked).
func _selected_action() -> HostRules.Action:
	return HostRules.Action.QUIT_TO_MENU if selected == Item.QUIT else HostRules.Action.DROP_PLAYER


## Shows the Settings page over the menu, driven by the player who paused (anyone without a working one).
func _open_settings() -> void:
	if is_settings_open():
		return
	if settings_page == null:
		settings_page = SettingsPage.create(0.5)
		settings_page.closed.connect(_on_settings_closed)
		add_child(settings_page)
	_center.visible = false
	settings_page.open(_driver())


func _on_settings_closed() -> void:
	_center.visible = true
	_skip_frames = 1  # (the B that closed the page must not also resume)
	_header_key = ""
	_refresh()
	_update_selection()


## Hides the Settings page without a trace (the menu is being opened again).
func _close_settings() -> void:
	if settings_page != null and settings_page.visible:
		settings_page.hide()
	if _center != null:
		_center.visible = true


## Resumes unless a joined player's controller is unplugged (then the game stays paused).
func _try_resume() -> void:
	if not PlayerManager.disconnected_slots().is_empty():
		Audio.play_ui(&"ui_error")
		return
	_resume()


func _resume() -> void:
	if not visible:
		return
	Audio.play_ui(&"ui_back")
	hide()
	resume_requested.emit()


func _quit() -> void:
	if not visible:
		return
	Audio.play_ui(&"ui_confirm")
	hide()
	quit_to_menu_requested.emit()


func _drop(slot_index: int) -> void:
	var target := PlayerManager.get_slot(slot_index)
	if visible and target != null and not target.input.is_connected_device():
		drop_player_requested.emit(target)
