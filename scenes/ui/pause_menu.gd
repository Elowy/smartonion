class_name PauseMenu
extends Control
## Pause overlay (GDD 11): dimmed game, "Paused by P2", Resume / Quit to Menu.
## Only the player who paused navigates (their own input: stick / d-pad, A selects);
## that player's B or ANY player's START resumes. process_mode is ALWAYS, Main pauses the tree.
## With no pausing slot (null, or the pausing player's controller got unplugged) the keyboard
## ui_* actions and any controller drive it.
## - The press / stick push that opened the menu is ignored: navigation waits until the stick
##   / d-pad has been neutral once (the stick the player was steering with in the game).
## - "Quit to Menu" asks for a second press ("Are you sure?"); moving the highlight cancels.
## - While a joined player's controller is unplugged the game cannot be resumed (START / B /
##   Resume do nothing); the menu offers "Continue without Pn" for each of them instead
##   (drop_player_requested – Main removes that player and goes on).
## See docs/ARCHITECTURE.md.

signal resume_requested
signal quit_to_menu_requested
## "Continue without Pn" was chosen for the player whose controller is unplugged.
signal drop_player_requested(slot: PlayerSlot)

enum Item { RESUME, QUIT }

## Entry codes of the "Continue without Pn" buttons are DROP_BASE + the player's slot index.
const DROP_BASE := 10
const QUIT_TEXT := "Quit to Menu"
const QUIT_CONFIRM_TEXT := "Are you sure?  Press again"

var slot: PlayerSlot
## Code of the highlighted entry: an Item, or DROP_BASE + slot index.
var selected: int = Item.RESUME
## Entry codes in display order: Resume, one "Continue without Pn" per unplugged player, Quit.
var entries: Array[int] = []
## One button per entry (same order as [member entries]).
var buttons: Array[Button] = []
## "Quit to Menu" was pressed once; the next press quits.
var quit_armed := false
## Controller edges for the slot-less fallback. Public for tests.
var pads := UiPads.new()

var _by_label: Label
var _missing_label: Label
var _list: VBoxContainer
var _prompts: CenterContainer
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
	selected = Item.RESUME
	quit_armed = false
	_skip_frames = 1
	_wait_neutral = slot != null and slot.input != null and slot.input.nav_held() != Vector2i.ZERO
	_entries_key = ""
	_header_key = ""
	_refresh()
	_fill_prompts()
	show()


## Moves the highlight by [param step] (wraps) and cancels a pending quit confirmation.
func move_selection(step: int) -> void:
	var i := entries.find(selected)
	selected = entries[wrapi(maxi(i, 0) + step, 0, entries.size())]
	quit_armed = false
	_update_selection()


## What A / a click does: like [method activate_selected], but "Quit to Menu" first asks
## "Are you sure?" and only quits on the second press.
func press_selected() -> void:
	if selected == Item.QUIT and not quit_armed:
		quit_armed = true
		_update_selection()
		return
	activate_selected()


## Runs the highlighted entry at once (no confirmation).
func activate_selected() -> void:
	if selected == Item.QUIT:
		_quit()
	elif selected == Item.RESUME:
		_try_resume()
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
	_prompts.add_child(UiTheme.prompt_row([
		[UiGlyph.nav(28.0, true), "Choose"],
		[a, "Select"],
		[b, "/", UiGlyph.pad(PlayerInput.Pad.START, 28.0), "Resume"],
	], UiTheme.FONT_BODY - 1, UiTheme.TEXT_DIM))


func _update_selection() -> void:
	for i in buttons.size():
		var b := buttons[i]
		var code := entries[i]
		var on := code == selected
		b.add_theme_stylebox_override(&"normal", _styles["selected"] if on else _styles["normal"])
		b.add_theme_color_override(&"font_color", UiTheme.GOLD_BRIGHT if on else UiTheme.TEXT)
		if code == Item.QUIT:
			b.text = QUIT_CONFIRM_TEXT if quit_armed else QUIT_TEXT


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


func _refresh_entries() -> void:
	var missing := PlayerManager.disconnected_slots()
	var key := ""
	for m in missing:
		key += "%d," % m.index
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
		_add_entry(DROP_BASE + m.index, "Continue without %s" % m.label())
		names.append(m.label())
	_add_entry(Item.QUIT, QUIT_TEXT)
	if not entries.has(selected):
		selected = Item.RESUME
	quit_armed = false
	_missing_label.visible = not names.is_empty()
	if not names.is_empty():
		_missing_label.text = "%s: controller%s unplugged.\nPlug %s back in to resume – or continue without." % [
			", ".join(names), "s" if names.size() > 1 else "", "them" if names.size() > 1 else "it"]
	_update_selection()


func _add_entry(code: int, text: String) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(420, 72)
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

func _process(_delta: float) -> void:
	pads.poll()
	if not visible:
		return
	_refresh()
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
			press_selected()
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
	if Input.is_action_just_pressed(&"ui_accept") or pads.any_just_pressed(JOY_BUTTON_A):
		press_selected()


## Resumes unless a joined player's controller is unplugged (then the game stays paused).
func _try_resume() -> void:
	if not PlayerManager.disconnected_slots().is_empty():
		return
	_resume()


func _resume() -> void:
	if not visible:
		return
	hide()
	resume_requested.emit()


func _quit() -> void:
	if not visible:
		return
	hide()
	quit_to_menu_requested.emit()


func _drop(slot_index: int) -> void:
	var target := PlayerManager.get_slot(slot_index)
	if visible and target != null and not target.input.is_connected_device():
		drop_player_requested.emit(target)
