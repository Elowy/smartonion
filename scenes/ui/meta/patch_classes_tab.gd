class_name PatchClassesTab
extends PatchTab
## The Classes tab of The Onion Patch: one row per class – portrait, Class Level, the XP bar with the XP to the next level,
## the next three rewards, the best wave and the wins per difficulty tier (N / P / T), or why the class is locked (Hunter
## and Shaman). ▲ ▼ move over the rows; A flips the default alternative starting weapon of a class that has unlocked
## it (Class Level 12; the lobby starts that class's heroes with it).

const ROW_HEIGHT := 80.0
const NEXT_REWARDS := 3

var cursor := 0
## The row panels (tests), in the order of Db.class_ids.
var rows: Array[PanelContainer] = []
## Per row: the labels tests read ("name", "level", "xp", "next", "best", "wins", "alt", "lock").
var cells: Array[Dictionary] = []

var _list: VBoxContainer


static func create() -> PatchClassesTab:
	var t := PatchClassesTab.new()
	t.name = "ClassesTab"
	t._list = UiTheme.vbox(4)
	t.add_child(t._list)
	return t


func tab_name() -> String:
	return "Classes"


func on_open() -> void:
	cursor = clampi(cursor, 0, maxi(Db.class_ids.size() - 1, 0))
	refresh()


func on_nav(dir: Vector2i) -> void:
	if dir.y != 0:
		cursor = wrap_index(cursor, dir.y, Db.class_ids.size())
		Audio.play_ui(&"ui_move")
		refresh()


func selected_class() -> StringName:
	return Db.class_ids[cursor] if cursor >= 0 and cursor < Db.class_ids.size() else &""


func action_text() -> String:
	var id := selected_class()
	if id != &"" and Meta.alt_weapon_unlocked(id) and not Meta.is_dev():
		return "Alt weapon"
	return ""


func on_accept() -> void:
	var id := selected_class()
	if id == &"":
		return
	if Meta.is_dev() or not Meta.alt_weapon_unlocked(id):
		Audio.play_ui(&"ui_error")
		post("The alternative weapon opens at Class Level %d" % ClassLevels.alt_weapon_level(), false)
		return
	var on := Meta.toggle_default_alt_weapon(id)
	Audio.play_ui(&"ui_confirm")
	post("%s starts with %s" % [Db.get_class_data(id).display_name, ClassLevels.alt_weapon_name(id) if on else "its usual weapons"])
	refresh()


func refresh() -> void:
	clear(_list)
	rows.clear()
	cells.clear()
	for i in Db.class_ids.size():
		_list.add_child(_make_row(Db.class_ids[i], i == cursor))


func _make_row(id: StringName, selected: bool) -> PanelContainer:
	var data := Db.get_class_data(id)
	var unlocked := Meta.is_class_unlocked(id)
	var progress := Meta.class_progress(id)
	var level := int(progress["level"])
	var panel := row_panel(selected, ROW_HEIGHT)
	panel.name = "Row_%s" % id
	if not unlocked:
		panel.modulate = Color(0.78, 0.76, 0.74)
	var line := UiTheme.hbox(14)
	panel.add_child(line)
	rows.append(panel)
	var cell: Dictionary = {}
	cells.append(cell)

	var portrait := UiPortrait.create(60.0)
	portrait.setup(data.onion_color if data != null else Color.WHITE, data)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(portrait)

	var who := UiTheme.vbox(0)
	who.custom_minimum_size.x = 250
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_label := clipped_label(data.display_name if data != null else String(id), 28, UiTheme.GOLD if unlocked else LOCKED_COLOR, UiTheme.HEADING)
	who.add_child(name_label)
	cell["name"] = name_label
	var level_text := "Class Level %d" % level if unlocked else "Locked"
	if unlocked and bool(progress["max"]):
		level_text += "  ·  MAX"
	var level_label := UiTheme.label(level_text, &"", UiTheme.FONT_SMALL, UiTheme.TEXT if unlocked else ERROR_COLOR)
	who.add_child(level_label)
	cell["level"] = level_label
	line.add_child(who)

	if unlocked:
		var xp := UiTheme.vbox(2)
		xp.custom_minimum_size.x = 300
		xp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bar := UiBar.create(UiTheme.XP_PURPLE, 20.0, UiTheme.FONT_SMALL - 4)
		bar.animated = false
		var max_level := bool(progress["max"])
		if max_level:
			bar.set_values(1.0, 1.0, "MAX LEVEL")
		else:
			bar.set_values(float(progress["into"]), maxf(float(progress["needed"]), 1.0),
					"%s / %s XP" % [UiTheme.format_int(int(progress["into"])), UiTheme.format_int(int(progress["needed"]))])
		xp.add_child(bar)
		var to_next := UiTheme.label("" if max_level else "%s XP to level %d" % [UiTheme.format_int(int(progress["needed"]) - int(progress["into"])), level + 1],
				&"", UiTheme.FONT_SMALL - 3, UiTheme.TEXT_DIM)
		xp.add_child(to_next)
		cell["xp"] = to_next
		line.add_child(xp)
	else:
		var hint := UiTheme.wrapped_label(Meta.unlock_hint(Profile.KIND_CLASS, id), &"", UiTheme.FONT_SMALL, ERROR_COLOR)
		hint.custom_minimum_size.x = 300
		hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hint.max_lines_visible = 2
		line.add_child(hint)
		cell["lock"] = hint

	var next_box := UiTheme.vbox(0)
	next_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var next_lines: Array[String] = []
	if unlocked:
		for r in ClassLevels.next_rewards(id, level, NEXT_REWARDS):
			next_lines.append("Lv %d   %s" % [int(r["level"]), str(r["text"])])
	if unlocked and next_lines.is_empty():
		next_lines.append("Every reward earned")
	var next_label := UiTheme.label("\n".join(PackedStringArray(next_lines)), &"", UiTheme.FONT_SMALL - 3, UiTheme.TEXT if unlocked else LOCKED_COLOR)
	next_label.clip_text = true
	next_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	next_box.add_child(next_label)
	cell["next"] = next_label
	line.add_child(next_box)

	var stats := UiTheme.vbox(0)
	stats.custom_minimum_size.x = 250
	stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var best := Meta.profile.counter(StringName(AchievementEngine.COUNTER_BEST_WAVE + String(id))) if Meta.profile != null else 0
	var best_label := UiTheme.label("Best wave: %s" % (str(best) if best > 0 else "–"), &"", UiTheme.FONT_SMALL, UiTheme.TEXT)
	stats.add_child(best_label)
	cell["best"] = best_label
	var wins := _wins_line(id)
	stats.add_child(wins)
	cell["wins"] = wins
	var alt := UiTheme.label(_alt_text(id), &"", UiTheme.FONT_SMALL - 3, UiTheme.TEXT_DIM)
	stats.add_child(alt)
	cell["alt"] = alt
	line.add_child(stats)
	return panel


## "Wins  N 3  P 1  T 0" with the tier letters in their colours.
func _wins_line(id: StringName) -> Control:
	var box := UiTheme.hbox(6)
	box.add_child(UiTheme.label("Wins", &"", UiTheme.FONT_SMALL - 3, UiTheme.TEXT_DIM))
	for tier in Difficulty.ids():
		var n := Meta.profile.counter(StringName("%s:%s:%s" % [AchievementEngine.COUNTER_WINS, id, tier])) if Meta.profile != null else 0
		var d := Db.get_difficulty(tier)
		var color := d.color if d != null else UiTheme.TEXT
		box.add_child(UiTheme.label(Difficulty.name_of(tier).substr(0, 1), UiTheme.HEADING, UiTheme.FONT_SMALL - 2, color))
		box.add_child(UiTheme.label(str(n), &"", UiTheme.FONT_SMALL - 2, UiTheme.TEXT if n > 0 else UiTheme.TEXT_DIM))
	return box


func _alt_text(id: StringName) -> String:
	if not Meta.alt_weapon_unlocked(id):
		return ""
	var l := Meta.remembered_loadout(id)
	return "Starts with the alternative weapon" if bool(l["alt_weapon"]) else "Starts with the usual weapons"
