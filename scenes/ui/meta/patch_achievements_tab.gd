class_name PatchAchievementsTab
extends PatchTab
## The Achievements tab of The Onion Patch: all achievements as scrolling rows (name, what it asks, a progress bar from
## the profile's counters where the condition has one, points, the reward) and the title picker on the right. ▲ ▼ move,
## ▶ moves to the titles and ◀ back; A on a title puts it next to your name (A on the chosen one clears it). A hidden
## achievement shows "???" until it is unlocked; the reward of a locked Legendary stays hidden too.

const ROW_HEIGHT := 60.0
const TITLE_ROW_HEIGHT := 34.0
const LIST_WIDTH := 1180.0
const HIDDEN_NAME := "???"
const HIDDEN_TEXT := "A hidden achievement."

## Which pane the cursor is in.
enum Pane { ACHIEVEMENTS, TITLES }

var pane: Pane = Pane.ACHIEVEMENTS
var cursor := 0
var title_cursor := 0
var entries: Array[AchievementData] = []
## The title ids shown (&"" first = no title) in order.
var title_ids: Array[StringName] = []
var rows: Array[PanelContainer] = []
var title_rows: Array[PanelContainer] = []

var _scroll: ScrollContainer
var _list: VBoxContainer
var _title_scroll: ScrollContainer
var _title_list: VBoxContainer
var _summary: Label
var _detail: Label


static func create() -> PatchAchievementsTab:
	var t := PatchAchievementsTab.new()
	t.name = "AchievementsTab"
	t._build()
	return t


func tab_name() -> String:
	return "Achievements"


func _build() -> void:
	var body := UiTheme.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(body)
	var left := UiTheme.vbox(6)
	left.custom_minimum_size.x = LIST_WIDTH
	body.add_child(left)
	_summary = UiTheme.label("", &"", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	left.add_child(_summary)
	_scroll = _make_scroll()
	left.add_child(_scroll)
	_detail = UiTheme.wrapped_label("", &"", UiTheme.FONT_SMALL - 2, UiTheme.TEXT)
	_detail.custom_minimum_size.y = 46
	_detail.max_lines_visible = 2
	left.add_child(_detail)
	_list = UiTheme.vbox(4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	var right := UiTheme.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(UiTheme.label("Titles", UiTheme.GOLD_LABEL, UiTheme.FONT_BODY))
	_title_scroll = _make_scroll()
	right.add_child(_title_scroll)
	_title_list = UiTheme.vbox(3)
	_title_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_scroll.add_child(_title_list)


static func _make_scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 100)
	return s


# --- State -----------------------------------------------------------------------------------------

func on_open() -> void:
	pane = Pane.ACHIEVEMENTS
	cursor = clampi(cursor, 0, maxi(Db.achievement_list().size() - 1, 0))
	refresh()


func selected() -> AchievementData:
	return entries[cursor] if cursor >= 0 and cursor < entries.size() else null


func selected_title() -> StringName:
	return title_ids[title_cursor] if title_cursor >= 0 and title_cursor < title_ids.size() else &""


func on_nav(dir: Vector2i) -> void:
	if dir.x > 0 and pane == Pane.ACHIEVEMENTS:
		pane = Pane.TITLES
		Audio.play_ui(&"ui_move")
	elif dir.x < 0 and pane == Pane.TITLES:
		pane = Pane.ACHIEVEMENTS
		Audio.play_ui(&"ui_move")
	elif dir.y != 0:
		if pane == Pane.ACHIEVEMENTS:
			cursor = wrap_index(cursor, dir.y, entries.size())
		else:
			title_cursor = wrap_index(title_cursor, dir.y, title_ids.size())
		Audio.play_ui(&"ui_move")
	else:
		return
	refresh()


func action_text() -> String:
	if pane != Pane.TITLES or selected_title() == &"":
		return "" if pane == Pane.ACHIEVEMENTS else "No title"
	return "Clear" if Meta.profile != null and Meta.profile.selected_title == selected_title() else "Wear"


func on_accept() -> void:
	if pane != Pane.TITLES:
		return
	var id := selected_title()
	if id == &"":
		Meta.select_title(&"")
		Audio.play_ui(&"ui_back")
		post("No title")
	elif Meta.profile != null and Meta.profile.selected_title == id:
		Meta.select_title(&"")
		Audio.play_ui(&"ui_back")
		post("No title")
	elif Meta.select_title(id):
		Audio.play_ui(&"ui_confirm")
		post("You are %s now" % PlayerTitles.name_of(id))
	else:
		Audio.play_ui(&"ui_error")
		post("You have not earned %s yet" % PlayerTitles.name_of(id), false)
	refresh()


## Whether [param data]'s name and text are shown (not hidden, or unlocked).
func revealed(data: AchievementData) -> bool:
	return not data.hidden or (Meta.profile != null and Meta.profile.has_achievement(data.id))


# --- Drawing ---------------------------------------------------------------------------------------

func refresh() -> void:
	entries = Db.achievement_list().duplicate()
	entries.sort_custom(func(a: AchievementData, b: AchievementData) -> bool:
		return a.points < b.points if a.points != b.points else a.display_name < b.display_name)
	title_ids.clear()
	title_ids.append(&"")
	title_ids.append_array(PlayerTitles.all_ids())
	cursor = clampi(cursor, 0, maxi(entries.size() - 1, 0))
	title_cursor = clampi(title_cursor, 0, maxi(title_ids.size() - 1, 0))
	_fill_detail()
	var done := 0
	var total_points := 0
	for a in entries:
		total_points += a.points
		if Meta.profile != null and Meta.profile.has_achievement(a.id):
			done += 1
	_summary.text = "%d of %d unlocked  ·  %d of %d points" % [done, entries.size(), Meta.achievement_points(), total_points]
	clear(_list)
	rows.clear()
	for i in entries.size():
		var row := _make_row(entries[i], pane == Pane.ACHIEVEMENTS and i == cursor)
		_list.add_child(row)
		rows.append(row)
	clear(_title_list)
	title_rows.clear()
	for i in title_ids.size():
		var row := _make_title_row(title_ids[i], pane == Pane.TITLES and i == title_cursor)
		_title_list.add_child(row)
		title_rows.append(row)
	_keep_in_view.call_deferred()


## The full text of the achievement under the cursor (the rows clip long descriptions).
func _fill_detail() -> void:
	var a := selected()
	if a == null or pane != Pane.ACHIEVEMENTS:
		_detail.text = ""
		return
	var done := Meta.profile != null and Meta.profile.has_achievement(a.id)
	if revealed(a):
		_detail.text = "%s – %s  (%s)" % [a.display_name, a.description, _reward_text(a, done)]
	else:
		_detail.text = "%s – %s" % [HIDDEN_NAME, HIDDEN_TEXT]


## Scrolls so the row under the cursor is visible (deferred: the rows have no size before the next layout pass).
func _keep_in_view() -> void:
	if not is_inside_tree():
		return
	if pane == Pane.ACHIEVEMENTS and cursor < rows.size() and is_instance_valid(rows[cursor]):
		_scroll.ensure_control_visible(rows[cursor])
	elif pane == Pane.TITLES and title_cursor < title_rows.size() and is_instance_valid(title_rows[title_cursor]):
		_title_scroll.ensure_control_visible(title_rows[title_cursor])


func _make_row(a: AchievementData, selected_row: bool) -> PanelContainer:
	var done := Meta.profile != null and Meta.profile.has_achievement(a.id)
	var shown := revealed(a)
	var panel := row_panel(selected_row, ROW_HEIGHT)
	panel.name = "Row_%s" % a.id
	var line := UiTheme.hbox(12)
	panel.add_child(line)
	if done:
		line.add_child(UiIcon.create(UiIcon.Kind.CHECK, Vector2(26, 26)))
	else:
		line.add_child(UiIcon.create(UiIcon.Kind.LOCK, Vector2(24, 24), Color(0.6, 0.55, 0.5)))
	var texts := UiTheme.vbox(0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_label := clipped_label(a.display_name if shown else HIDDEN_NAME, UiTheme.FONT_BODY - 2, OWNED_COLOR if done else UiTheme.TEXT)
	name_label.name = "Name"
	texts.add_child(name_label)
	var info := clipped_label(a.description if shown else HIDDEN_TEXT, UiTheme.FONT_SMALL - 3, UiTheme.TEXT_DIM)
	texts.add_child(info)
	line.add_child(texts)
	var progress := AchievementProgress.of(a, Meta.profile) if Meta.profile != null else {"known": false}
	var right := UiTheme.vbox(0)
	right.custom_minimum_size.x = 290
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if bool(progress["known"]) and shown and int(progress["goal"]) > 1:
		var bar := UiBar.create(UiTheme.XP_PURPLE if not done else UiTheme.HP_GREEN, 16.0, UiTheme.FONT_SMALL - 6)
		bar.animated = false
		bar.set_values(float(progress["value"]), float(progress["goal"]), "%d / %d" % [int(progress["value"]), int(progress["goal"])])
		right.add_child(bar)
	right.add_child(clipped_label(_reward_text(a, done), UiTheme.FONT_SMALL - 4, UiTheme.GOLD if done else UiTheme.TEXT_DIM))
	line.add_child(right)
	var points := UiTheme.label("%d pts" % a.points, &"", UiTheme.FONT_SMALL, UiTheme.GOLD if done else UiTheme.TEXT_DIM)
	points.custom_minimum_size.x = 64
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(points)
	return panel


## The reward column: the first reward line (and how many more), "Seeds only" for none; a hidden achievement keeps it secret.
func _reward_text(a: AchievementData, done: bool) -> String:
	if not done and (a.hidden or _gives_legendary(a)):
		return "Reward: ???"
	var lines := AchievementTexts.reward_lines(a)
	if lines.is_empty():
		return "+%d Seeds" % (a.points * Meta.SEEDS_PER_POINT)
	return lines[0] if lines.size() == 1 else "%s (+%d)" % [lines[0], lines.size() - 1]


## A Legendary reward stays a surprise until the achievement is earned.
static func _gives_legendary(a: AchievementData) -> bool:
	for r in a.rewards:
		if StringName(str(r.get("kind", ""))) == Profile.KIND_LEGENDARY:
			return true
	return false


func _make_title_row(id: StringName, selected_row: bool) -> PanelContainer:
	var owned := id == &"" or (Meta.profile != null and Meta.profile.has_unlock(Profile.KIND_TITLE, id))
	var worn := Meta.profile != null and Meta.profile.selected_title == id
	var panel := row_panel(selected_row, TITLE_ROW_HEIGHT)
	panel.name = "Title_%s" % (id if id != &"" else &"none")
	var line := UiTheme.hbox(10)
	panel.add_child(line)
	var text := "No title" if id == &"" else PlayerTitles.name_of(id)
	var color := UiTheme.TEXT if owned else LOCKED_COLOR
	if worn:
		color = OWNED_COLOR
	var label := clipped_label(text, UiTheme.FONT_SMALL, color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(label)
	if worn:
		line.add_child(UiIcon.create(UiIcon.Kind.CHECK, Vector2(20, 20)))
	elif not owned:
		line.add_child(UiIcon.create(UiIcon.Kind.LOCK, Vector2(18, 18), Color(0.6, 0.55, 0.5)))
	return panel
