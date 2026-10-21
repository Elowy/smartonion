class_name MainMenu
extends Control
## Title screen: gold "SmartOnion" title over an onion hero in a horned helm, Play / The Onion Patch / Settings /
## Credits / Quit. Nobody has joined yet, so any device may drive it: keyboard and d-pad / left stick through
## Godot's ui_* focus navigation, controller A / B through UiPads (ui_accept has no pad
## buttons). Settings, Credits and The Onion Patch (M9 PATCH: the meta page: Seasonings, Heirlooms, achievements ...) open a
## [MenuPage] over the title (the menu's own content is hidden
## meanwhile and the page is driven by "anyone"); closing it gives the focus back to the button that
## opened it. Host rules (HostRules): a Remote Play guest's pad cannot press Quit ("Only the host can do that").
## See docs/ARCHITECTURE.md.

signal play_pressed
signal quit_pressed

const VERSION_TEXT := "First playable build"

var play_button: Button
var onion_patch_button: Button
var settings_button: Button
var credits_button: Button
var quit_button: Button
## The five buttons top to bottom (focus wraps around).
var buttons: Array[Button] = []
var emblem: UiIcon
var title_label: Label
## The pages, created the first time they are opened.
var settings_page: SettingsPage
var credits_page: CreditsPage
var onion_patch_page: OnionPatchPage

var _pads := UiPads.new()
var _t := 0.0
var _refusal_label: Label
var _refusal_left := 0.0
var _backdrop: TextureRect
var _embers: _Embers
## The title column and the prompts: hidden while a page is open.
var _content: Control
var _hints: Control
## The press that closed a page must not also act on the menu (first frame is skipped).
var _skip_frames := 0


static func create() -> MainMenu:
	var m := MainMenu.new()
	m.name = "MainMenu"
	m._build()
	return m


## Opacity of the dark backdrop (lower it to let a 3D scene show through).
func set_backdrop_opacity(alpha: float) -> void:
	_backdrop.modulate.a = alpha


func _build() -> void:
	UiTheme.setup_root(self)
	_backdrop = UiTheme.backdrop(1.0, Color(0.42, 0.24, 0.1))
	add_child(_backdrop)
	_embers = _Embers.new()
	_embers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_embers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_embers)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -60
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_content = center
	var col := UiTheme.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(320, 260)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(holder)
	emblem = UiIcon.create(UiIcon.Kind.ONION, Vector2(320, 260), Color(0.74, 0.3, 0.52))
	emblem.helm = true
	emblem.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(emblem)

	title_label = UiTheme.centered_label("SmartOnion", UiTheme.TITLE, UiTheme.FONT_HUGE)
	title_label.add_theme_constant_override(&"outline_size", 20)
	title_label.add_theme_constant_override(&"shadow_outline_size", 22)
	title_label.add_theme_constant_override(&"shadow_offset_y", 8)
	col.add_child(title_label)
	var subtitle := UiTheme.centered_label("Onion heroes in shining armor  ·  1–4 player local co-op", &"", UiTheme.FONT_LARGE, UiTheme.TEXT_DIM)
	col.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	col.add_child(gap)
	col.add_child(UiTheme.divider(560))
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 26)
	col.add_child(gap2)

	var button_column := UiTheme.vbox(12)
	button_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(button_column)
	play_button = _make_button("Play", button_column)
	onion_patch_button = _make_button("The Onion Patch", button_column)
	settings_button = _make_button("Settings", button_column)
	credits_button = _make_button("Credits", button_column)
	quit_button = _make_button("Quit", button_column)
	for i in buttons.size():
		var b := buttons[i]
		b.focus_neighbor_top = b.get_path_to(buttons[wrapi(i - 1, 0, buttons.size())])
		b.focus_neighbor_bottom = b.get_path_to(buttons[wrapi(i + 1, 0, buttons.size())])
	play_button.pressed.connect(_on_play)
	onion_patch_button.pressed.connect(open_onion_patch)
	settings_button.pressed.connect(open_settings)
	credits_button.pressed.connect(open_credits)
	quit_button.pressed.connect(_on_quit)

	var hints := UiTheme.prompt_row([
		[UiGlyph.pad(PlayerInput.Pad.A), "/", UiGlyph.key("Enter"), "Select"],
		[UiGlyph.nav(30.0, true), "Navigate"],
	], UiTheme.FONT_BODY, UiTheme.TEXT_DIM)
	hints.add_theme_constant_override(&"separation", 48)
	hints.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hints.offset_top = -78
	hints.offset_bottom = -40
	hints.offset_left = -400
	hints.offset_right = 400
	add_child(hints)
	_hints = hints
	_refusal_label = UiTheme.centered_label(HostRules.REFUSED_TEXT, &"", UiTheme.FONT_BODY, UiTheme.RED.lightened(0.25))
	_refusal_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_refusal_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_refusal_label.offset_top = -124
	_refusal_label.offset_bottom = -90
	_refusal_label.offset_left = -400
	_refusal_label.offset_right = 400
	_refusal_label.visible = false
	add_child(_refusal_label)

	var version := UiTheme.label(VERSION_TEXT, UiTheme.SMALL)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -28
	version.offset_bottom = -20
	version.offset_left = -400
	version.offset_top = -50
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(version)


func _make_button(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 64)
	b.focus_mode = Control.FOCUS_ALL
	b.focus_entered.connect(_on_button_focused)
	parent.add_child(b)
	buttons.append(b)
	return b


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _on_visibility_changed() -> void:
	if is_visible_in_tree() and play_button != null and play_button.is_inside_tree():
		_focus_play.call_deferred()


## A button got the focus: the move click (not the first focus, which the menu grabs by itself).
func _on_button_focused() -> void:
	if _t > 0.3:
		Audio.play_ui(&"ui_move")


## Deferred: the menu may already have left the tree (Main switched screens this frame).
func _focus_play() -> void:
	if play_button != null and play_button.is_inside_tree() and play_button.is_visible_in_tree():
		play_button.grab_focus()


func _process(delta: float) -> void:
	_t += delta
	_pads.poll()
	if not is_visible_in_tree():
		return
	emblem.position.y = sin(_t * 1.6) * 6.0
	emblem.rotation = sin(_t * 0.9) * 0.025
	emblem.pivot_offset = emblem.size * Vector2(0.5, 1.0)
	if _refusal_left > 0.0:
		_refusal_left -= delta
		_refusal_label.visible = _refusal_left > 0.0
	if is_page_open():
		return  # (the page reads the controllers itself)
	if _skip_frames > 0:
		_skip_frames -= 1
		return
	if _pads.any_just_pressed(JOY_BUTTON_A) or _pads.any_just_pressed(JOY_BUTTON_START):
		var devices := _pads.just_pressed_devices(JOY_BUTTON_A)
		devices.append_array(_pads.just_pressed_devices(JOY_BUTTON_START))
		activate_focused(devices)
	elif _pads.any_just_pressed(JOY_BUTTON_B):
		quit_button.grab_focus()


## Presses the focused button (Play when nothing is focused). Controllers' A lands here: [param devices] are the pads
## that pressed (none = the keyboard / the mouse / a test: the host). Quit is the host's: a guest's pad cannot press it.
func activate_focused(devices: Array[int] = []) -> void:
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus == quit_button:
		if not HostRules.may_any_device(HostRules.Action.QUIT_GAME, devices):
			_refusal_left = PauseMenu.REFUSAL_TIME
			_refusal_label.visible = true
			Audio.play_ui(&"ui_error")
			return
		_on_quit()
	elif focus == onion_patch_button:
		open_onion_patch()
	elif focus == settings_button:
		open_settings()
	elif focus == credits_button:
		open_credits()
	else:
		_on_play()


## True while the Settings, Credits or Onion Patch page covers the menu.
func is_page_open() -> bool:
	return (settings_page != null and settings_page.visible) or (credits_page != null and credits_page.visible) \
			or (onion_patch_page != null and onion_patch_page.visible)


## Opens the Settings page (anyone may drive it: nobody has joined yet).
func open_settings() -> void:
	if is_page_open():
		return
	if settings_page == null:
		settings_page = SettingsPage.create(0.4)
		settings_page.closed.connect(_on_page_closed.bind(settings_button))
		add_child(settings_page)
	_show_content(false)
	settings_page.open(null)


## Opens The Onion Patch (anyone may drive it: nobody has joined yet).
func open_onion_patch() -> void:
	if is_page_open():
		return
	if onion_patch_page == null:
		onion_patch_page = OnionPatchPage.create(0.5)
		onion_patch_page.closed.connect(_on_page_closed.bind(onion_patch_button))
		add_child(onion_patch_page)
	_show_content(false)
	onion_patch_page.open(null)


## Opens the Credits page.
func open_credits() -> void:
	if is_page_open():
		return
	if credits_page == null:
		credits_page = CreditsPage.create(0.35)
		credits_page.closed.connect(_on_page_closed.bind(credits_button))
		add_child(credits_page)
	_show_content(false)
	credits_page.open(null)


func _show_content(value: bool) -> void:
	_content.visible = value
	_hints.visible = value


## A page was closed: the menu is back, [param opener] (the button that opened it) is focused again.
func _on_page_closed(opener: Button) -> void:
	_show_content(true)
	_skip_frames = 1
	if is_inside_tree():
		_focus_button.call_deferred(opener)


## Deferred: the menu may already have left the tree (Main switched screens this frame).
func _focus_button(button: Button) -> void:
	if button != null and button.is_inside_tree() and button.is_visible_in_tree():
		button.grab_focus()


func _on_play() -> void:
	Audio.play_ui(&"ui_confirm")
	play_pressed.emit()


func _on_quit() -> void:
	Audio.play_ui(&"ui_back")
	quit_pressed.emit()


## Slowly rising embers behind the title (cosmetic only).
class _Embers extends Control:
	const COUNT := 46
	var _items: Array[Vector4] = []  # x (0..1), y (0..1), speed, size
	var _rng := RandomNumberGenerator.new()

	func _init() -> void:
		_rng.seed = 7
		for i in COUNT:
			_items.append(Vector4(_rng.randf(), _rng.randf(), _rng.randf_range(0.015, 0.05), _rng.randf_range(1.5, 4.0)))

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		for i in _items.size():
			var e := _items[i]
			e.y -= e.z * delta
			e.x += sin(e.y * 9.0 + float(i)) * 0.0006
			if e.y < -0.02:
				e = Vector4(_rng.randf(), 1.02, _rng.randf_range(0.015, 0.05), _rng.randf_range(1.5, 4.0))
			_items[i] = e
		queue_redraw()

	func _draw() -> void:
		for e in _items:
			var p := Vector2(e.x * size.x, e.y * size.y)
			var a := clampf(e.y * 1.2, 0.0, 1.0) * 0.7
			draw_circle(p, e.w * 2.2, Color(1.0, 0.55, 0.15, a * 0.18))
			draw_circle(p, e.w, Color(1.0, 0.78, 0.35, a))
