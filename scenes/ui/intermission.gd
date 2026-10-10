class_name Intermission
extends Control
## Between-wave screen (GDD 1, 12) – milestone M1 version: "Wave N cleared!", the shared gold,
## team level and level-ups of the wave, a preview of the next wave, the coming tabs (Shop |
## Trainer | Talents | Character) as locked headers, and one ready chip per player.
## Every joined player presses A (or START) to ready, B to unready; bots and players whose
## controller is unplugged count as ready. Everyone ready -> continue_requested (once per open).
## See docs/ARCHITECTURE.md.

signal continue_requested

const TABS: Array[String] = ["Shop", "Trainer", "Talents", "Character"]

var cleared_wave := 0
var level_ups := 0

var title_label: Label
var next_label: Label
var gold_value: Label
var level_value: Label
var level_ups_value: Label
var chips_row: HBoxContainer

var _done := true
## Input is ignored on the first frame after open() (the press that ended the wave).
var _skip_frames := 0
var _chips: Dictionary[int, PanelContainer] = {}
var _chip_keys: Dictionary[int, String] = {}
var _chip_ids := ""
var _backdrop: TextureRect
var _t := 0.0


static func create() -> Intermission:
	var im := Intermission.new()
	im.name = "Intermission"
	im._build()
	return im


## Shows the screen for the wave that was just cleared. Players ready up with A.
func open(p_cleared_wave: int, p_level_ups: int) -> void:
	cleared_wave = p_cleared_wave
	level_ups = p_level_ups
	_done = false
	_skip_frames = 1
	for slot in PlayerManager.get_slots():
		slot.ready = is_auto_ready(slot)
	_fill()
	_refresh_chips(true)
	show()


## Bots and players whose device is unplugged never block the next wave.
static func is_auto_ready(slot: PlayerSlot) -> bool:
	return slot.is_bot() or slot.input == null or not slot.input.is_connected_device()


func is_open() -> bool:
	return visible and not _done


## Opacity of the dark backdrop (the frozen arena shows through by default).
func set_backdrop_opacity(alpha: float) -> void:
	_backdrop.modulate.a = alpha


# --- Build ---------------------------------------------------------------------------

func _build() -> void:
	UiTheme.setup_root(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backdrop = UiTheme.backdrop(0.82, Color(0.25, 0.17, 0.1))
	add_child(_backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := UiTheme.panel()
	var style := UiTheme.stone_style()
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 30
	style.content_margin_bottom = 30
	panel.add_theme_stylebox_override(&"panel", style.rebuild())
	panel.custom_minimum_size = Vector2(1180, 0)
	center.add_child(panel)
	var col := UiTheme.vbox(14)
	panel.add_child(col)

	title_label = UiTheme.centered_label("Wave 1 cleared!", UiTheme.TITLE, 76)
	col.add_child(title_label)
	next_label = UiTheme.centered_label("", UiTheme.DIM, UiTheme.FONT_LARGE)
	col.add_child(next_label)
	col.add_child(UiTheme.divider(700))

	# Shared stats.
	var stats := UiTheme.hbox(20)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(stats)
	gold_value = _stat_tile(stats, "Shared gold", UiIcon.create(UiIcon.Kind.COIN, Vector2(40, 40)))
	level_value = _stat_tile(stats, "Team level", null)
	level_ups_value = _stat_tile(stats, "Level-ups this wave", null)

	# Coming-soon tabs on a parchment note.
	var tab_block := UiTheme.vbox(0)
	col.add_child(tab_block)
	var tabs := UiTheme.hbox(8)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	for t in TABS:
		tabs.add_child(_locked_tab(t))
	tab_block.add_child(tabs)
	var note := UiTheme.panel(UiTheme.PARCHMENT_PANEL)
	note.custom_minimum_size = Vector2(0, 0)
	var note_label := UiTheme.wrapped_label(
		"Level-up choices, the Shop, the Trainer, Talents and the Character panel arrive in the next update. "
		+ "For now your heroes rest, count their gold and march on.", UiTheme.INK_LABEL, UiTheme.FONT_BODY)
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_child(note_label)
	tab_block.add_child(note)

	col.add_child(UiTheme.centered_label("Ready check", UiTheme.HEADING, 32))
	chips_row = UiTheme.hbox(16)
	chips_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chips_row.custom_minimum_size = Vector2(0, 74)
	col.add_child(chips_row)

	col.add_child(UiTheme.prompt_row([
		[UiGlyph.pad(PlayerInput.Pad.A), "Ready"],
		[UiGlyph.pad(PlayerInput.Pad.B), "Not ready"],
		[UiTheme.label("Keyboard:", UiTheme.SMALL), UiGlyph.key("Enter"), "/", UiGlyph.key("Esc")],
	], UiTheme.FONT_BODY, UiTheme.TEXT_DIM))
	visible = false


func _stat_tile(parent: Control, caption: String, icon: Control) -> Label:
	var tile := UiTheme.panel(UiTheme.INSET_PANEL)
	tile.custom_minimum_size = Vector2(330, 112)
	parent.add_child(tile)
	var box := UiTheme.vbox(0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(box)
	var row := UiTheme.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if icon != null:
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
	var value := UiTheme.label("0", UiTheme.BIG_NUMBER, 50)
	row.add_child(value)
	box.add_child(row)
	box.add_child(UiTheme.centered_label(caption, UiTheme.SMALL, UiTheme.FONT_SMALL + 1))
	return value


func _locked_tab(text: String) -> PanelContainer:
	var tab := PanelContainer.new()
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.13, 0.115, 0.1, 0.95)
	s.border_color = Color(0.36, 0.3, 0.22)
	s.set_border_width_all(2)
	s.border_width_bottom = 0
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	tab.add_theme_stylebox_override(&"panel", s)
	var row := UiTheme.hbox(8)
	row.add_child(UiIcon.create(UiIcon.Kind.LOCK, Vector2(22, 22), Color(0.55, 0.5, 0.42)))
	row.add_child(UiTheme.label(text, UiTheme.GOLD_LABEL, 24, Color(0.55, 0.5, 0.42)))
	tab.add_child(row)
	tab.custom_minimum_size = Vector2(200, 0)
	return tab


# --- Content -------------------------------------------------------------------------

func _fill() -> void:
	title_label.text = "Wave %d cleared!" % cleared_wave
	var next := cleared_wave + 1
	var tag := ""
	if RunState.is_boss_wave(next):
		tag = "  –  Boss wave!"
	elif RunState.is_elite_wave(next):
		tag = "  –  Elite wave!"
	if next > RunState.TOTAL_WAVES:
		next_label.text = "The final battle is won"
	else:
		next_label.text = "Next up: Wave %d of %d  ·  %d seconds%s" % [next, RunState.TOTAL_WAVES, int(RunState.wave_duration(next)), tag]
	next_label.add_theme_color_override(&"font_color", UiTheme.RED.lightened(0.2) if tag != "" else UiTheme.TEXT_DIM)
	gold_value.text = UiTheme.format_int(RunState.gold)
	gold_value.add_theme_color_override(&"font_color", UiTheme.GOLD)
	level_value.text = str(RunState.level)
	level_ups_value.text = "+%d" % level_ups if level_ups > 0 else "–"
	level_ups_value.add_theme_color_override(&"font_color", UiTheme.GREEN if level_ups > 0 else UiTheme.TEXT_DIM)


func _refresh_chips(force: bool = false) -> void:
	var slots := PlayerManager.get_slots()
	var ids := ""
	for s in slots:
		ids += "%d," % s.index
	if force or ids != _chip_ids:
		_chip_ids = ids
		for c in chips_row.get_children():
			chips_row.remove_child(c)
			c.queue_free()
		_chips.clear()
		_chip_keys.clear()
		for s in slots:
			var chip := PanelContainer.new()
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chips_row.add_child(chip)
			_chips[s.index] = chip
	for s in slots:
		var key := "%s:%s:%s" % [s.ready, is_auto_ready(s), s.class_data.id if s.class_data != null else &""]
		if _chip_keys.get(s.index, "") != key:
			_chip_keys[s.index] = key
			_fill_chip(_chips[s.index], s)


func _fill_chip(chip: PanelContainer, s: PlayerSlot) -> void:
	for c in chip.get_children():
		chip.remove_child(c)
		c.queue_free()
	var style := UiTheme.inset_style()
	style.border = UiTheme.GREEN if s.ready else Color(0.38, 0.3, 0.2)
	style.border_width = 2
	style.fill = Color(0.07, 0.13, 0.06, 0.97) if s.ready else UiTheme.STONE_DARK
	style.content_margin_left = 10
	style.content_margin_right = 18
	chip.add_theme_stylebox_override(&"panel", style.rebuild())
	chip.custom_minimum_size = Vector2(250, 70)
	var row := UiTheme.hbox(12)
	chip.add_child(row)
	var portrait := UiPortrait.create(54.0)
	portrait.setup(s.color, s.class_data)
	row.add_child(portrait)
	var box := UiTheme.vbox(0)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	var name_row := UiTheme.hbox(6)
	name_row.add_child(UiTheme.label(s.label(), UiTheme.GOLD_LABEL, 22, s.color.lightened(0.3)))
	name_row.add_child(UiTheme.label(s.class_data.display_name if s.class_data != null else "", UiTheme.GOLD_LABEL, 22))
	box.add_child(name_row)
	var status := UiTheme.hbox(6)
	if s.ready:
		status.add_child(UiIcon.create(UiIcon.Kind.CHECK, Vector2(20, 20)))
		var text := "Ready"
		if s.is_bot():
			text = "Ready (bot)"
		elif not s.input.is_connected_device():
			text = "Disconnected"
		status.add_child(UiTheme.label(text, &"", UiTheme.FONT_SMALL + 1, UiTheme.GREEN))
	else:
		status.add_child(UiGlyph.for_input(s.input, PlayerInput.Pad.A, 22.0))
		status.add_child(UiTheme.label("to ready up", &"", UiTheme.FONT_SMALL + 1, UiTheme.TEXT_DIM))
	box.add_child(status)


# --- Frame ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if not visible or _done:
		return
	if _skip_frames > 0:
		_skip_frames -= 1
		return
	var slots := PlayerManager.get_slots()
	for s in slots:
		if is_auto_ready(s):
			s.ready = true
			continue
		var inp := s.input
		if inp.just_pressed(PlayerInput.Pad.A):
			s.ready = not s.ready
		elif inp.just_pressed(PlayerInput.Pad.START):
			s.ready = true
		elif inp.just_pressed(PlayerInput.Pad.B):
			s.ready = false
	_refresh_chips()
	if slots.is_empty() or PlayerManager.all_ready():
		_done = true
		continue_requested.emit()
