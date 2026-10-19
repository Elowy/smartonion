class_name MenuPage
extends Control
## Base of the full-screen pages the main menu and the pause menu open (SettingsPage, CreditsPage): a dimmed
## screen with one stone panel (title, content, a row of button prompts) and the shared input rules.
##
## - [method open] takes the slot that drives the page: the pausing player (their own PlayerInput: stick /
##   d-pad navigate, A selects, B goes back), or null for "anyone" – the main menu, where nobody has joined
##   yet, and the pause menu when the pausing player's controller is gone: the keyboard's ui_* actions and
##   every controller (UiPads), like the slot-less PauseMenu.
## - The press that opened the page is ignored (first frame skipped) and so is a stick / d-pad that was
##   still held; B (or Esc) closes the page: [signal closed].
## - process_mode is ALWAYS (the pause menu runs it while the tree is paused).
## Subclasses build their content into [member column] between [method _build_frame] and
## [method _finish_frame] and override the three input hooks below. See docs/ARCHITECTURE.md.

signal closed

var slot: PlayerSlot
## Controller edges for the slot-less fallback. Public for tests.
var pads := UiPads.new()
var panel: PanelContainer
var title_label: Label
## Content goes here (below the title, above the prompts).
var column: VBoxContainer

var _prompts: CenterContainer
## The press that opened the page must not also act in it (first frame is skipped).
var _skip_frames := 0
## The stick / d-pad was held when the page opened: no navigation until it is neutral once.
var _wait_neutral := false
var _fallback_dir := Vector2i.ZERO
var _fallback_timer := 0.0


func _build_frame(title: String, panel_width: float, dim_alpha: float) -> void:
	UiTheme.setup_root(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.02, dim_alpha)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = UiTheme.panel()
	var style := UiTheme.stone_style()
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 22
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override(&"panel", style.rebuild())
	panel.custom_minimum_size = Vector2(panel_width, 0)
	center.add_child(panel)
	column = UiTheme.vbox(8)
	panel.add_child(column)
	title_label = UiTheme.centered_label(title, UiTheme.TITLE, 60)
	column.add_child(title_label)
	column.add_child(UiTheme.divider(420))
	visible = false


## Adds the prompt row under the content (call last).
func _finish_frame() -> void:
	_prompts = CenterContainer.new()
	_prompts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_prompts)


## Shows the page, driven by [param p_slot] (null = anyone, see the class comment).
func open(p_slot: PlayerSlot) -> void:
	slot = p_slot
	_skip_frames = 1
	var driver := driver_slot()
	_wait_neutral = driver != null and driver.input.nav_held() != Vector2i.ZERO
	_fallback_dir = Vector2i.ZERO
	_fallback_timer = 0.0
	_on_open()
	_fill_prompts()
	show()


## Hides the page and tells the menu below ([signal closed]).
func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


## The player whose own input drives the page: [member slot] while still joined and their controller works.
## Null = the slot-less fallback.
func driver_slot() -> PlayerSlot:
	if slot != null and slot.input != null and PlayerManager.get_slot(slot.index) == slot \
			and slot.input.is_connected_device():
		return slot
	return null


# --- Hooks for the pages -------------------------------------------------------------------

## The page is about to be shown (reset the selection / scroll).
func _on_open() -> void:
	pass


## A navigation step: one unit direction per push, with key-repeat while held.
func _on_nav(_dir: Vector2i) -> void:
	pass


## The direction held right now (no repeat), every frame: for smooth scrolling.
func _on_held(_dir: Vector2i, _delta: float) -> void:
	pass


## A / Enter.
func _on_accept() -> void:
	pass


## The prompt row: one [glyphs..., "text"] list per prompt (build the glyphs with [method _glyphs]; only
## the ones that are returned may be created, a glyph that is not added to the tree is never freed).
func _prompt_items() -> Array:
	return []


# --- Prompts -------------------------------------------------------------------------------

func _fill_prompts() -> void:
	if _prompts == null:
		return
	for c in _prompts.get_children():
		_prompts.remove_child(c)
		c.queue_free()
	_prompts.add_child(UiTheme.prompt_row(_prompt_items(), UiTheme.FONT_BODY - 1, UiTheme.TEXT_DIM))


## The glyph(s) naming [param button]: the driver's own device, or a controller button plus the key that does
## the same on the keyboard when anyone may drive the page.
func _glyphs(button: PlayerInput.Pad) -> Array:
	var driver := driver_slot()
	if driver != null:
		return [UiGlyph.for_input(driver.input, button, 28.0)]
	var key_name := UiGlyph.keyboard_name(button)
	return [UiGlyph.pad(button, 28.0), "/", UiGlyph.key(key_name, 28.0)]


# --- Frame ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	pads.poll()
	if not is_visible_in_tree():
		return
	if _skip_frames > 0:
		_skip_frames -= 1
		return
	var driver := driver_slot()
	if driver != null:
		var inp := driver.input
		if inp.just_pressed(PlayerInput.Pad.B):
			close()
			return
		var held := inp.nav_held()
		if _wait_neutral:
			if held == Vector2i.ZERO:
				_wait_neutral = false
			held = Vector2i.ZERO
		else:
			var nav := inp.nav_just_pressed()
			if nav != Vector2i.ZERO:
				_on_nav(nav)
		_on_held(held, delta)
		if inp.just_pressed(PlayerInput.Pad.A):
			_on_accept()
		return
	# Nobody drives it (main menu, or the pausing player's controller is gone): keyboard actions, any controller.
	if Input.is_action_just_pressed(&"ui_cancel") or pads.any_just_pressed(JOY_BUTTON_B):
		close()
		return
	var fallback_held := _fallback_held()
	var edge := _fallback_edge(fallback_held, delta)
	if edge != Vector2i.ZERO:
		_on_nav(edge)
	_on_held(fallback_held, delta)
	if Input.is_action_just_pressed(&"ui_accept") or pads.any_just_pressed(JOY_BUTTON_A):
		_on_accept()


## The ui_* direction held (arrows, d-pad, left stick), one axis at a time.
func _fallback_held() -> Vector2i:
	var x := int(Input.is_action_pressed(&"ui_right")) - int(Input.is_action_pressed(&"ui_left"))
	var y := int(Input.is_action_pressed(&"ui_down")) - int(Input.is_action_pressed(&"ui_up"))
	if x != 0 and (y == 0 or _fallback_dir.x != 0):
		return Vector2i(x, 0)
	return Vector2i(0, y)


## [param held] as navigation steps: the push itself, then repeats (PlayerInput's delay and rate).
func _fallback_edge(held: Vector2i, delta: float) -> Vector2i:
	if held == Vector2i.ZERO:
		_fallback_dir = Vector2i.ZERO
		_fallback_timer = 0.0
		return Vector2i.ZERO
	if held != _fallback_dir:
		_fallback_dir = held
		_fallback_timer = PlayerInput.NAV_REPEAT_DELAY
		return held
	_fallback_timer -= delta
	if _fallback_timer <= 0.0:
		_fallback_timer = PlayerInput.NAV_REPEAT_RATE
		return held
	return Vector2i.ZERO
