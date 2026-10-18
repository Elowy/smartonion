class_name LeaderboardPage
extends VBoxContainer
## The "Leaderboard" page of the end screen (M6b MODES): the local top 10 of the run's category (mode,
## hardcore, party size) – rank, result, time, party and date – with the entry of the run that just ended
## highlighted in gold and marked "This run". Pure view of a [method Leaderboard.screen_model] dictionary:
## [method fill] rebuilds the rows (always [constant Leaderboard.MAX_ENTRIES] of them, empty places
## dashed, so the page keeps its height). An empty model ({}: the leaderboard file is not in use, as in
## the unit tests) shows a note instead of the places.

const ROW_FONT := 21
const ROW_HEIGHT := 31.0
const ROW_GAP := 3
## Widths of the columns: rank, result, time, party (0 = takes the rest), date, "This run".
const COLUMN_WIDTHS: Array[float] = [60.0, 230.0, 110.0, 0.0, 140.0, 120.0]
const HEADERS: Array[String] = ["#", "Result", "Time", "Party", "Date", ""]
const HIGHLIGHT_FILL := Color(0.5, 0.36, 0.08, 0.5)
const HIGHLIGHT_BORDER := Color(0.95, 0.78, 0.3)
const EMPTY_ROW_TEXT := "–"

## The category line ("Endless · Hardcore · 4 players") and the note line under the table.
var category_label: Label
var note_label: Label
## One panel per place, best first; [member highlighted] is the place of the run (-1 = none).
var rows: Array[PanelContainer] = []
var highlighted := -1
var table: PanelContainer
var rows_box: VBoxContainer


static func create() -> LeaderboardPage:
	var page := LeaderboardPage.new()
	page.name = "LeaderboardPage"
	page._build()
	return page


func _build() -> void:
	add_theme_constant_override(&"separation", 8)
	category_label = UiTheme.centered_label("Leaderboard", UiTheme.GOLD_LABEL, UiTheme.FONT_LARGE - 2)
	add_child(category_label)
	table = UiTheme.panel(UiTheme.INSET_PANEL)
	add_child(table)
	var col := UiTheme.vbox(ROW_GAP)
	table.add_child(col)
	var head_cells: Array = []
	for text in HEADERS:
		head_cells.append(UiTheme.label(text, UiTheme.SMALL, UiTheme.FONT_SMALL))
	var head := PanelContainer.new()  # (the same margins as the rows, so the columns line up)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_stylebox_override(&"panel", _row_style(false))
	head.add_child(_row_layout(head_cells))
	col.add_child(head)
	rows_box = UiTheme.vbox(ROW_GAP)
	col.add_child(rows_box)
	note_label = UiTheme.centered_label(" ", UiTheme.DIM, UiTheme.FONT_SMALL)
	add_child(note_label)
	_fill_rows([], -1, RunState.MODE_NORMAL)


## Rebuilds the page from [param board] ([method Leaderboard.screen_model]; {} = no board).
func fill(board: Dictionary) -> void:
	var mode: StringName = board.get("mode", RunState.MODE_NORMAL)
	var entries: Array = board.get("entries", [])
	var rank := int(board.get("rank", -1))
	category_label.text = String(board.get("category_text", "Leaderboard"))
	_fill_rows(entries, rank, mode)
	if board.is_empty():
		note_label.text = "The leaderboard is not recorded in this session."
	elif String(board.get("error", "")) != "":
		note_label.text = "The leaderboard file could not be used (%s)." % board["error"]
	elif rank >= 0:
		note_label.text = "New entry: place %d of %d." % [rank + 1, Leaderboard.MAX_ENTRIES]
	elif entries.is_empty():
		note_label.text = "No runs recorded in this category yet."
	else:
		note_label.text = "This run did not reach the top %d." % Leaderboard.MAX_ENTRIES
	note_label.add_theme_color_override(&"font_color", UiTheme.GOLD if rank >= 0 else UiTheme.TEXT_DIM)


func _fill_rows(entries: Array, rank: int, mode: StringName) -> void:
	for c in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()
	rows.clear()
	highlighted = -1
	for i in Leaderboard.MAX_ENTRIES:
		var filled := i < entries.size()
		var cells: Array = []
		var texts: Array[String] = ["", EMPTY_ROW_TEXT, "", "", "", ""]
		if filled:
			var r := Leaderboard.row_texts(i, entries[i], mode)
			texts = ["#%s" % r["rank"], r["result"], r["time"], r["party"], r["date"], "This run" if i == rank else ""]
		else:
			texts[0] = "#%d" % (i + 1)
		for k in texts.size():
			var color := UiTheme.TEXT if filled else UiTheme.TEXT_DIM
			if i == rank:
				color = UiTheme.GOLD_BRIGHT
			var l := UiTheme.label(texts[k], &"", ROW_FONT, color)
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			if k == 5:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cells.append(l)
		var row := PanelContainer.new()
		row.name = "Place%d" % (i + 1)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
		row.add_theme_stylebox_override(&"panel", _row_style(i == rank))
		row.add_child(_row_layout(cells))
		rows_box.add_child(row)
		rows.append(row)
		if i == rank:
			highlighted = i


## The text of column [param column] (0 rank, 1 result, 2 time, 3 party, 4 date, 5 "This run") of place
## [param place] (0 = the first); "" outside the table (tests).
func cell_text(place: int, column: int) -> String:
	if place < 0 or place >= rows.size():
		return ""
	var cells := (rows[place].get_child(0) as HBoxContainer).get_children()
	return (cells[column] as Label).text if column >= 0 and column < cells.size() else ""


## Fixed columns: [param cells] are the controls of one row.
func _row_layout(cells: Array) -> HBoxContainer:
	var row := UiTheme.hbox(10)
	for i in cells.size():
		var c := cells[i] as Control
		if COLUMN_WIDTHS[i] > 0.0:
			c.custom_minimum_size.x = COLUMN_WIDTHS[i]
		else:
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(c)
	return row


static func _row_style(highlight: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = HIGHLIGHT_FILL if highlight else Color(0, 0, 0, 0)
	s.border_color = HIGHLIGHT_BORDER if highlight else Color(0, 0, 0, 0)
	s.set_border_width_all(2 if highlight else 0)
	s.set_corner_radius_all(4)
	s.content_margin_left = 8.0
	s.content_margin_right = 8.0
	s.content_margin_top = 0.0
	s.content_margin_bottom = 0.0
	return s
