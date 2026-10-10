class_name MainMenu
extends Control
## Title screen: gold "SmartOnion" title over an onion hero in a horned helm, Play / Quit.
## Nobody has joined yet, so any device may drive it: keyboard and d-pad / left stick through
## Godot's ui_* focus navigation, controller A / B through UiPads (ui_accept has no pad
## buttons). See docs/ARCHITECTURE.md.

signal play_pressed
signal quit_pressed

const VERSION_TEXT := "First playable build"

var play_button: Button
var quit_button: Button
var emblem: UiIcon
var title_label: Label

var _pads := UiPads.new()
var _t := 0.0
var _backdrop: TextureRect
var _embers: _Embers


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
	var subtitle := UiTheme.centered_label("Onion heroes in shining armour  ·  1–4 player local co-op", &"", UiTheme.FONT_LARGE, UiTheme.TEXT_DIM)
	col.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	col.add_child(gap)
	col.add_child(UiTheme.divider(560))
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 26)
	col.add_child(gap2)

	var buttons := UiTheme.vbox(18)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(buttons)
	play_button = _make_button("Play", buttons)
	quit_button = _make_button("Quit", buttons)
	play_button.focus_neighbor_top = play_button.get_path_to(quit_button)
	quit_button.focus_neighbor_bottom = quit_button.get_path_to(play_button)
	play_button.pressed.connect(_on_play)
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
	b.custom_minimum_size = Vector2(420, 74)
	b.focus_mode = Control.FOCUS_ALL
	parent.add_child(b)
	return b


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _on_visibility_changed() -> void:
	if is_visible_in_tree() and play_button != null and play_button.is_inside_tree():
		play_button.grab_focus.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	_pads.poll()
	if not is_visible_in_tree():
		return
	emblem.position.y = sin(_t * 1.6) * 6.0
	emblem.rotation = sin(_t * 0.9) * 0.025
	emblem.pivot_offset = emblem.size * Vector2(0.5, 1.0)
	if _pads.any_just_pressed(JOY_BUTTON_A) or _pads.any_just_pressed(JOY_BUTTON_START):
		activate_focused()
	elif _pads.any_just_pressed(JOY_BUTTON_B):
		quit_button.grab_focus()


## Presses the focused button (Play when nothing is focused). Controllers' A lands here.
func activate_focused() -> void:
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus == quit_button:
		_on_quit()
	else:
		_on_play()


func _on_play() -> void:
	play_pressed.emit()


func _on_quit() -> void:
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
