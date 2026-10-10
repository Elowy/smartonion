class_name GameOverScreen
extends Control
## End-of-run summary (GDD 1): "Victory!" (gold) or "Defeat" (red), waves cleared, total kills,
## gold earned, team level and one row per player (class, kills, damage; the top damage
## dealer gets a crown). After INPUT_DELAY, A / START on any player's device, any controller's
## A or ui_accept -> back_to_menu_requested (once per open). See docs/ARCHITECTURE.md.

signal back_to_menu_requested

## Seconds before input is accepted (players are usually still mashing buttons).
const INPUT_DELAY := 1.0

var victory := false
var title_label: Label
var subtitle_label: Label
var waves_value: Label
var kills_value: Label
var gold_value: Label
var level_value: Label
var rows_box: VBoxContainer
## Controller edges (A on any pad). Public for tests.
var pads := UiPads.new()

var _t := 0.0
var _done := true
var _prompt: Control
var _backdrop: TextureRect


static func create() -> GameOverScreen:
	var g := GameOverScreen.new()
	g.name = "GameOverScreen"
	g._build()
	return g


## Fills in the end-of-run summary from RunState (victory / defeat, waves, kills, gold).
func open(p_victory: bool) -> void:
	victory = p_victory
	_t = 0.0
	_done = false
	_fill()
	show()


## Number of waves the team survived.
static func waves_cleared(p_victory: bool) -> int:
	return RunState.TOTAL_WAVES if p_victory else clampi(RunState.wave - 1, 0, RunState.TOTAL_WAVES)


func set_backdrop_opacity(alpha: float) -> void:
	_backdrop.modulate.a = alpha


# --- Build ---------------------------------------------------------------------------

func _build() -> void:
	UiTheme.setup_root(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backdrop = UiTheme.backdrop(0.9, Color(0.3, 0.18, 0.1))
	add_child(_backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := UiTheme.panel()
	var style := UiTheme.stone_style()
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 26
	style.content_margin_bottom = 30
	panel.add_theme_stylebox_override(&"panel", style.rebuild())
	panel.custom_minimum_size = Vector2(1140, 0)
	center.add_child(panel)
	var col := UiTheme.vbox(12)
	panel.add_child(col)

	title_label = UiTheme.centered_label("Victory!", UiTheme.TITLE, 110)
	title_label.add_theme_constant_override(&"outline_size", 18)
	col.add_child(title_label)
	subtitle_label = UiTheme.centered_label("", UiTheme.DIM, UiTheme.FONT_LARGE)
	col.add_child(subtitle_label)
	col.add_child(UiTheme.divider(700))

	var stats := UiTheme.hbox(16)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(stats)
	waves_value = _stat_tile(stats, "Waves cleared", null)
	kills_value = _stat_tile(stats, "Enemies slain", UiIcon.create(UiIcon.Kind.SWORDS, Vector2(36, 36), Color(0.85, 0.87, 0.92)))
	gold_value = _stat_tile(stats, "Gold earned", UiIcon.create(UiIcon.Kind.COIN, Vector2(36, 36)))
	level_value = _stat_tile(stats, "Team level", null)

	var table := UiTheme.panel(UiTheme.INSET_PANEL)
	col.add_child(table)
	var tcol := UiTheme.vbox(6)
	table.add_child(tcol)
	tcol.add_child(_row_layout([UiTheme.label("Hero", UiTheme.SMALL), UiTheme.label("Class", UiTheme.SMALL),
		UiTheme.label("Kills", UiTheme.SMALL), UiTheme.label("Damage", UiTheme.SMALL), Control.new()]))
	rows_box = UiTheme.vbox(6)
	tcol.add_child(rows_box)

	_prompt = UiTheme.prompt_row([[UiGlyph.pad(PlayerInput.Pad.A), "/", UiGlyph.key("Enter"), "Back to Lobby"]],
		UiTheme.FONT_LARGE - 2, UiTheme.TEXT)
	col.add_child(_prompt)
	visible = false


func _stat_tile(parent: Control, caption: String, icon: Control) -> Label:
	var tile := UiTheme.panel(UiTheme.INSET_PANEL)
	tile.custom_minimum_size = Vector2(246, 106)
	parent.add_child(tile)
	var box := UiTheme.vbox(0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(box)
	var row := UiTheme.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if icon != null:
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
	var value := UiTheme.label("0", UiTheme.BIG_NUMBER, 46)
	row.add_child(value)
	box.add_child(row)
	box.add_child(UiTheme.centered_label(caption, UiTheme.SMALL, UiTheme.FONT_SMALL + 1))
	return value


## [hero, class, kills, damage, badge] with fixed column widths.
func _row_layout(cells: Array) -> HBoxContainer:
	var widths: Array[float] = [230.0, 300.0, 170.0, 200.0, 60.0]
	var row := UiTheme.hbox(12)
	for i in cells.size():
		var c := cells[i] as Control
		c.custom_minimum_size.x = widths[i]
		if i == 1:
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if c is Label and (i == 2 or i == 3):
			(c as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(c)
	return row


func _fill() -> void:
	if victory:
		title_label.text = "Victory!"
		title_label.add_theme_color_override(&"font_color", UiTheme.GOLD)
		subtitle_label.text = "All %d waves survived – the onions prevail!" % RunState.TOTAL_WAVES
	else:
		title_label.text = "Defeat"
		title_label.add_theme_color_override(&"font_color", UiTheme.RED)
		subtitle_label.text = "The party was peeled on wave %d. Dry your tears and try again." % maxi(RunState.wave, 1)
	waves_value.text = "%d / %d" % [waves_cleared(victory), RunState.TOTAL_WAVES]
	kills_value.text = UiTheme.format_int(RunState.kills)
	gold_value.text = UiTheme.format_int(RunState.gold_earned)
	gold_value.add_theme_color_override(&"font_color", UiTheme.GOLD)
	level_value.text = str(RunState.level)

	for c in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()
	var slots := PlayerManager.get_slots()
	var best := -1
	var best_damage := 0.0
	for s in slots:
		var dmg: float = RunState.damage_by_player.get(s.index, 0.0)
		if dmg > best_damage:
			best_damage = dmg
			best = s.index
	for s in slots:
		rows_box.add_child(_player_row(s, s.index == best and slots.size() > 1))
	if slots.is_empty():
		rows_box.add_child(UiTheme.centered_label("No heroes", UiTheme.DIM))


func _player_row(s: PlayerSlot, mvp: bool) -> Control:
	var hero := UiTheme.hbox(10)
	var swatch := ColorRect.new()
	swatch.color = s.color
	swatch.custom_minimum_size = Vector2(8, 34)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(swatch)
	var data := s.class_data
	var portrait := UiPortrait.create(44.0)
	portrait.setup(s.color, data)
	hero.add_child(portrait)
	hero.add_child(UiTheme.label(s.label(), UiTheme.GOLD_LABEL, 28, s.color.lightened(0.3)))
	var cls := UiTheme.label(data.display_name if data != null else "?", UiTheme.GOLD_LABEL, 28)
	var kills: int = RunState.kills_by_player.get(s.index, 0)
	var dmg: float = RunState.damage_by_player.get(s.index, 0.0)
	var kill_label := UiTheme.label(UiTheme.format_int(kills), &"", UiTheme.FONT_LARGE)
	var dmg_label := UiTheme.label(UiTheme.format_int(roundi(dmg)), &"", UiTheme.FONT_LARGE)
	var badge: Control = UiIcon.create(UiIcon.Kind.CROWN, Vector2(34, 30)) if mvp else Control.new()
	return _row_layout([hero, cls, kill_label, dmg_label, badge])


# --- Frame ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	pads.poll()
	if not visible or _done:
		return
	_t += delta
	var accepting := _t >= INPUT_DELAY
	_prompt.modulate.a = clampf((_t - INPUT_DELAY + 0.4) / 0.4, 0.0, 1.0)
	if not accepting:
		return
	var go := Input.is_action_just_pressed(&"ui_accept") or pads.any_just_pressed(JOY_BUTTON_A) \
		or pads.any_just_pressed(JOY_BUTTON_START)
	for s in PlayerManager.get_slots():
		if s.input != null and (s.input.just_pressed(PlayerInput.Pad.A) or s.input.just_pressed(PlayerInput.Pad.START)):
			go = true
	if go:
		_done = true
		back_to_menu_requested.emit()
