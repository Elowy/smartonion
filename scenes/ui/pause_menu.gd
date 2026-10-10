class_name PauseMenu
extends Control
## Pause overlay (GDD 11): dimmed game, "Paused by P2", Resume / Quit to Menu.
## Only the player who paused navigates (their own input: stick / d-pad, A selects);
## that player's B or ANY player's START resumes. process_mode is ALWAYS, Main pauses the tree.
## With no pausing slot (null) the keyboard ui_* actions and any controller drive it.
## See docs/ARCHITECTURE.md.

signal resume_requested
signal quit_to_menu_requested

enum Item { RESUME, QUIT }

var slot: PlayerSlot
var selected := Item.RESUME
var buttons: Array[Button] = []
## Controller edges for the slot-less fallback. Public for tests.
var pads := UiPads.new()

var _by_label: Label
var _prompts: CenterContainer
## The press that opened the menu must not also close it (first frame is skipped).
var _skip_frames := 0
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
	_skip_frames = 1
	if slot != null:
		_by_label.text = "Paused by %s" % slot.label()
		_by_label.add_theme_color_override(&"font_color", slot.color.lightened(0.3))
	else:
		_by_label.text = "Game paused"
		_by_label.add_theme_color_override(&"font_color", UiTheme.TEXT_DIM)
	_fill_prompts()
	_update_selection()
	show()


## Moves the highlight by [param step] (wraps).
func move_selection(step: int) -> void:
	selected = wrapi(selected + step, 0, buttons.size()) as Item
	_update_selection()


## Runs the highlighted entry.
func activate_selected() -> void:
	if selected == Item.QUIT:
		_quit()
	else:
		_resume()


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
	for text in ["Resume", "Quit to Menu"]:
		var b := Button.new()
		b.text = text
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(420, 72)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(b)
		buttons.append(b)
		var item := buttons.size() - 1
		b.mouse_entered.connect(func() -> void:
			selected = item as Item
			_update_selection())
	buttons[Item.RESUME].pressed.connect(_resume)
	buttons[Item.QUIT].pressed.connect(_quit)
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
		var on := i == selected
		b.add_theme_stylebox_override(&"normal", _styles["selected"] if on else _styles["normal"])
		b.add_theme_color_override(&"font_color", UiTheme.GOLD_BRIGHT if on else UiTheme.TEXT)


# --- Frame ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	pads.poll()
	if not visible:
		return
	if _skip_frames > 0:
		_skip_frames -= 1
		return
	for s in PlayerManager.get_slots():
		if s.input != null and s.input.just_pressed(PlayerInput.Pad.START):
			_resume()
			return
	if slot != null and slot.input != null and PlayerManager.get_slot(slot.index) == slot:
		var inp := slot.input
		if inp.just_pressed(PlayerInput.Pad.B):
			_resume()
			return
		var nav := inp.nav_just_pressed()
		if nav.y != 0:
			move_selection(nav.y)
		if inp.just_pressed(PlayerInput.Pad.A):
			activate_selected()
		return
	# Fallback without a (valid) pausing player: keyboard actions and any controller.
	if Input.is_action_just_pressed(&"ui_cancel") or pads.any_just_pressed(JOY_BUTTON_B) \
			or pads.any_just_pressed(JOY_BUTTON_START):
		_resume()
		return
	if Input.is_action_just_pressed(&"ui_up"):
		move_selection(-1)
	elif Input.is_action_just_pressed(&"ui_down"):
		move_selection(1)
	if Input.is_action_just_pressed(&"ui_accept") or pads.any_just_pressed(JOY_BUTTON_A):
		activate_selected()


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
