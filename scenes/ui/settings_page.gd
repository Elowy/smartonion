class_name SettingsPage
extends MenuPage
## The Settings page (M7a), opened from the main menu and the pause menu: the sections Audio / Video /
## Gameplay with one row per [SettingOption] (GameSettings.options()), then "Reset to Defaults" and "Back".
## Up / down move the highlight, left / right change the highlighted value (volumes in steps of 10 %, choices
## and toggles wrap around), A flips a toggle / cycles a choice / presses a button row, B goes back. The mouse
## works too: hover highlights a row, the arrows (or a click on the left / right half of the value) change it.
## Every change goes through the Settings autoload (applied and saved at once); the page just shows it.
## Input rules (driver, swallowed opening press): MenuPage.
## Host rules (HostRules): the Video rows are the host's window – a Remote Play guest cannot change them, and while
## guests are connected neither can the pads of a page nobody in particular drives (the keyboard and the mouse still can).

enum RowKind { OPTION, RESET, BACK }

const PANEL_WIDTH := 980.0
const ROW_HEIGHT := 42.0
const VALUE_WIDTH := 400.0
const ARROW_SIZE := 38.0
const SEGMENTS := 10
const RESET_TEXT := "Reset to Defaults"
const BACK_TEXT := "Back"

## The selectable rows in display order: one per option, then Reset and Back.
var rows: Array[Row] = []
## Index into [member rows] of the highlighted row.
var selected := 0

var _refusal_left := 0.0
var _selected_style: StyleBoxFlat
var _plain_style: StyleBoxFlat
var _last_mouse := Vector2(-1.0, -1.0)


## [param dim_alpha]: how much the screen behind is darkened (the pause menu's game, the title backdrop).
static func create(dim_alpha: float = 0.55) -> SettingsPage:
	var p := SettingsPage.new()
	p.name = "SettingsPage"
	p._build(dim_alpha)
	return p


func _build(dim_alpha: float) -> void:
	_selected_style = _row_style(true)
	_plain_style = _row_style(false)
	_build_frame("Settings", PANEL_WIDTH, dim_alpha)
	column.add_theme_constant_override(&"separation", 4)
	var section := ""
	for o in GameSettings.options():
		if o.section != section:
			section = o.section
			_add_section(section)
		_add_option_row(o)
	column.add_child(_gap(6.0))
	_add_button_row(RowKind.RESET, RESET_TEXT)
	_add_button_row(RowKind.BACK, BACK_TEXT)
	column.add_child(_gap(4.0))
	_finish_frame()
	Settings.changed.connect(_on_setting_changed)
	refresh()


func _gap(height: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, height)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _add_section(title: String) -> void:
	column.add_child(_gap(6.0))
	var head := UiTheme.label(title, UiTheme.GOLD_LABEL, 26)
	head.add_theme_constant_override(&"outline_size", 5)
	column.add_child(head)
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)


func _add_option_row(o: SettingOption) -> void:
	var row := Row.new()
	row.kind = RowKind.OPTION
	row.key = o.key
	row.panel = _row_panel(row)
	var line := UiTheme.hbox(10)
	row.panel.add_child(line)
	row.name_label = UiTheme.label(o.label, &"", UiTheme.FONT_BODY + 2)
	row.name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(row.name_label)
	row.value_box = UiTheme.hbox(8)
	row.value_box.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
	row.value_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(row.value_box)
	row.left = _Arrow.new(-1)
	row.right = _Arrow.new(1)
	row.left.pressed.connect(_on_arrow.bind(row, -1))
	row.right.pressed.connect(_on_arrow.bind(row, 1))
	var middle := UiTheme.hbox(10)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	if o.kind == SettingOption.Kind.PERCENT:
		row.segments = _Segments.new(SEGMENTS)
		middle.add_child(row.segments)
	row.value_label = UiTheme.label("", &"", UiTheme.FONT_BODY + 2)
	row.value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if o.kind == SettingOption.Kind.PERCENT:
		row.value_label.custom_minimum_size.x = 64.0
		row.value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		row.value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(row.value_label)
	row.value_box.add_child(row.left)
	row.value_box.add_child(middle)
	row.value_box.add_child(row.right)
	_register(row)


func _add_button_row(kind: RowKind, text: String) -> void:
	var row := Row.new()
	row.kind = kind
	row.panel = _row_panel(row)
	row.name_label = UiTheme.centered_label(text, &"", UiTheme.FONT_BODY + 2)
	row.name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.panel.add_child(row.name_label)
	_register(row)


func _row_panel(row: Row) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(_on_row_input.bind(row))
	column.add_child(p)
	return p


func _register(row: Row) -> void:
	rows.append(row)


static func _row_style(on: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.32, 0.21, 0.1, 0.92) if on else Color(0, 0, 0, 0)
	s.border_color = UiTheme.GOLD_BRIGHT if on else Color(0, 0, 0, 0)
	s.set_border_width_all(2)
	s.set_corner_radius_all(5)
	s.anti_aliasing = true
	s.content_margin_left = 18
	s.content_margin_right = 12
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	return s


# --- Reading -------------------------------------------------------------------------------

## The row of option [param key]; null for an unknown key.
func row_for(key: StringName) -> Row:
	for r in rows:
		if r.kind == RowKind.OPTION and r.key == key:
			return r
	return null


func selected_row() -> Row:
	return rows[selected]


## The text shown as the value of option [param key] ("70%", "Windowed", "On").
func value_text(key: StringName) -> String:
	var r := row_for(key)
	return r.value_label.text if r != null else ""


# --- Actions -------------------------------------------------------------------------------

## Highlights row [param index] (clamped).
func select(index: int) -> void:
	var i := clampi(index, 0, rows.size() - 1)
	if i == selected:
		return
	selected = i
	Audio.play_ui(&"ui_move")
	refresh()


## Moves the highlight by [param step] rows (wraps).
func move_selection(step: int) -> void:
	selected = wrapi(selected + step, 0, rows.size())
	Audio.play_ui(&"ui_move")
	refresh()


## Left / right on the highlighted row: changes an option's value one step ([param direction] -1 / 1).
## [param by_mouse]: a click (the host's mouse), not a controller / key.
func change_selected(direction: int, by_mouse: bool = false) -> void:
	var row := rows[selected]
	if row.kind == RowKind.OPTION and direction != 0:
		if _video_locked(row, by_mouse):
			_refuse()
			return
		Settings.step_value(row.key, direction)
		Audio.play_ui(&"ui_toggle")


## True when the presser may not change [param row]: a Video row (the host's window) of a guest's page, or of a page
## nobody in particular drives while guests are connected (a controller could be a guest's).
func _video_locked(row: Row, by_mouse: bool) -> bool:
	if by_mouse or row.kind != RowKind.OPTION or not HostRules.is_video_key(row.key):
		return false
	var driver := driver_slot()
	if driver != null:
		return not HostRules.may(HostRules.Action.VIDEO_SETTINGS, driver)
	return RemotePlay.has_guests()


func _refuse() -> void:
	Audio.play_ui(&"ui_error")
	_refusal_left = 2.5
	title_label.text = HostRules.REFUSED_TEXT
	title_label.add_theme_color_override(&"font_color", UiTheme.RED.lightened(0.25))


## A on the highlighted row: flips a toggle, cycles a choice, presses Reset / Back (volumes: nothing).
func activate_selected() -> void:
	var row := rows[selected]
	match row.kind:
		RowKind.RESET:
			Settings.reset_to_defaults()
			Audio.play_ui(&"ui_confirm")
		RowKind.BACK:
			close()
		_:
			if GameSettings.option(row.key).kind != SettingOption.Kind.PERCENT:
				if _video_locked(row, false):
					_refuse()
					return
				Settings.step_value(row.key, 1)
				Audio.play_ui(&"ui_toggle")


## Redraws every row from the Settings values and the highlight.
func refresh() -> void:
	for i in rows.size():
		var row := rows[i]
		var on := i == selected
		row.panel.add_theme_stylebox_override(&"panel", _selected_style if on else _plain_style)
		var color := UiTheme.GOLD_BRIGHT if on else UiTheme.TEXT
		row.name_label.add_theme_color_override(&"font_color", color)
		if row.kind == RowKind.RESET:
			row.name_label.add_theme_color_override(&"font_color",
					color if not Settings.data.is_default() else UiTheme.TEXT_DIM)
		if row.kind != RowKind.OPTION:
			continue
		var o := GameSettings.option(row.key)
		var value: Variant = Settings.get_value(row.key)
		row.value_label.text = o.text(value)
		row.value_label.add_theme_color_override(&"font_color", UiTheme.GOLD if on else UiTheme.TEXT)
		if row.segments != null:
			row.segments.set_filled(roundi(float(value) / float(o.step)))
		row.left.set_state(on, _can_step(o, value, -1))
		row.right.set_state(on, _can_step(o, value, 1))


## True when stepping [param value] in [param direction] would change it (volumes stop at 0 and 100).
static func _can_step(o: SettingOption, value: Variant, direction: int) -> bool:
	return o.stepped(value, direction) != value


func _on_setting_changed(_key: StringName) -> void:
	refresh()


# --- Input hooks ---------------------------------------------------------------------------

func _on_open() -> void:
	selected = 0
	_refusal_left = 0.0
	title_label.text = "Settings"
	title_label.remove_theme_color_override(&"font_color")
	# (a mouse resting on the page does not take the highlight: only moving it does)
	_last_mouse = get_viewport().get_mouse_position() if is_inside_tree() else Vector2(-1.0, -1.0)
	refresh()


func _on_nav(dir: Vector2i) -> void:
	if dir.y != 0:
		move_selection(dir.y)
	elif dir.x != 0:
		change_selected(dir.x)


func _on_accept() -> void:
	activate_selected()


func _prompt_items() -> Array:
	return [
		[UiGlyph.nav(28.0, true), "Choose"],
		[UiGlyph.nav(28.0), "Change"],
		_glyphs(PlayerInput.Pad.A) + ["Select"],
		_glyphs(PlayerInput.Pad.B) + ["Back"],
	]


func _process(delta: float) -> void:
	super(delta)
	if not is_visible_in_tree():
		return
	if _refusal_left > 0.0:
		_refusal_left -= delta
		if _refusal_left <= 0.0:
			title_label.text = "Settings"
			title_label.remove_theme_color_override(&"font_color")
	# The highlight follows the mouse only while it moves (a controller keeps the highlight otherwise).
	var mouse := get_viewport().get_mouse_position()
	if mouse != _last_mouse:
		_last_mouse = mouse
		var global_mouse := get_global_mouse_position()
		for i in rows.size():
			if rows[i].panel.get_global_rect().has_point(global_mouse):
				select(i)
				break


func _on_arrow(row: Row, direction: int) -> void:
	select(rows.find(row))
	change_selected(direction, true)


func _on_row_input(event: InputEvent, row: Row) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	select(rows.find(row))
	if row.kind != RowKind.OPTION:
		activate_selected()
		return
	var o := GameSettings.option(row.key)
	var at := row.panel.get_global_transform() * click.position
	var box := row.value_box.get_global_rect()
	if o.kind == SettingOption.Kind.PERCENT:
		if box.has_point(at):
			change_selected(1 if at.x > box.get_center().x else -1, true)
	else:
		change_selected(1 if not box.has_point(at) or at.x > box.get_center().x else -1, true)


# --- Widgets -------------------------------------------------------------------------------

## One selectable row of the page.
class Row extends RefCounted:
	var kind := RowKind.OPTION
	## The option's key (OPTION rows).
	var key: StringName = &""
	var panel: PanelContainer
	var name_label: Label
	var value_box: HBoxContainer
	var value_label: Label
	var segments: _Segments
	var left: _Arrow
	var right: _Arrow


## A row of blocks, the first [member filled] of them lit (volume 0 .. 100 % in tens).
class _Segments extends Control:
	const BLOCK_W := 14.0
	const BLOCK_H := 20.0
	const GAP := 4.0

	var total := 10
	var filled := 0

	func _init(p_total: int) -> void:
		total = p_total
		custom_minimum_size = Vector2(total * (BLOCK_W + GAP) - GAP, BLOCK_H + 4.0)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_filled(count: int) -> void:
		if count != filled:
			filled = count
			queue_redraw()

	func _draw() -> void:
		var top := (size.y - BLOCK_H) * 0.5
		for i in total:
			var r := Rect2(i * (BLOCK_W + GAP), top, BLOCK_W, BLOCK_H)
			if i < filled:
				draw_rect(r, UiTheme.GOLD_BORDER)
				draw_rect(r.grow(-2.0), UiTheme.GOLD)
				draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4.0, 4.0)), Color(1, 1, 1, 0.3))
			else:
				draw_rect(r, Color(0.3, 0.24, 0.15))
				draw_rect(r.grow(-2.0), Color(0.08, 0.065, 0.05))


## A clickable triangle pointing left (-1) or right (1).
class _Arrow extends Control:
	signal pressed

	var direction := 1
	var enabled := true
	var lit := false
	var hot := false

	func _init(p_direction: int) -> void:
		direction = p_direction
		custom_minimum_size = Vector2(ARROW_SIZE, ARROW_SIZE)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(_set_hot.bind(true))
		mouse_exited.connect(_set_hot.bind(false))

	## [param p_lit]: the row is highlighted; [param p_enabled]: the value can move this way.
	func set_state(p_lit: bool, p_enabled: bool) -> void:
		if p_lit != lit or p_enabled != enabled:
			lit = p_lit
			enabled = p_enabled
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
			queue_redraw()

	func _set_hot(value: bool) -> void:
		hot = value
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if enabled:
				pressed.emit()

	func _draw() -> void:
		var color := UiTheme.GOLD if lit else UiTheme.GOLD_BORDER
		if hot and enabled:
			color = UiTheme.GOLD_BRIGHT
		if not enabled:
			color = Color(0.3, 0.26, 0.2)
		var c := size * 0.5
		var s := size.x * 0.3
		var d := float(direction)
		var tip := c + Vector2(d * s, 0.0)
		var top := c + Vector2(-d * s * 0.7, -s * 1.05)
		var bottom := c + Vector2(-d * s * 0.7, s * 1.05)
		draw_colored_polygon(PackedVector2Array([tip, top, bottom]), color)
