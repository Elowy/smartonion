class_name WardrobeGrid
extends Control
## A scrolling grid of [WardrobeEntry] cells (M9 WARDROBE), one custom-drawn Control (only the visible rows are drawn, so the 85 looks of
## a slot cost nothing). The owner moves the cursor with [method move] (D-pad steps) and reads [method selected]; the grid
## scrolls to keep the cursor in view. Drawing is [WardrobeIcon].

## The cursor moved to another entry (also on [method set_entries] when the entry under it changed).
signal cursor_changed(entry: WardrobeEntry)

const CELL := Vector2(88.0, 88.0)
const GAP := 8.0

var entries: Array[WardrobeEntry] = []
var cursor := 0
## The grid has the focus (a dimmer cursor frame otherwise).
var focused := true:
	set(value):
		focused = value
		queue_redraw()
## 0 = as many columns as fit; > 0 = exactly that many.
var fixed_columns := 0
## The id of the entry drawn with a green tick (the current choice), &"" = none; the NONE entry matches an empty id.
var marked_id: StringName = &""
var show_marked := false

var _scroll := 0.0


func _init() -> void:
	name = "WardrobeGrid"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(CELL.x * 3.0 + GAP * 2.0, CELL.y * 2.0 + GAP)
	resized.connect(_on_resized)


## Replaces the entries. The cursor goes to the entry with [param keep_id], else stays on the id that was selected when it is still
## there, else to the first entry (the NONE entry of a picker row has the empty id and is first).
func set_entries(list: Array[WardrobeEntry], keep_id: StringName = &"") -> void:
	var wanted := keep_id
	if wanted == &"" and selected() != null:
		wanted = selected().id
	entries = list
	cursor = 0
	if wanted != &"":
		for i in entries.size():
			if entries[i].id == wanted:
				cursor = i
				break
	_scroll = 0.0
	_ensure_visible()
	queue_redraw()
	cursor_changed.emit(selected())


func selected() -> WardrobeEntry:
	return entries[cursor] if cursor >= 0 and cursor < entries.size() else null


## Columns in use.
func columns() -> int:
	if fixed_columns > 0:
		return fixed_columns
	return maxi(1, int(floor((size.x + GAP) / (CELL.x + GAP))))


func rows() -> int:
	return int(ceil(float(entries.size()) / float(columns())))


## Puts the cursor on entry [param index] (clamped); emits [signal cursor_changed] on a change.
func select_index(index: int) -> void:
	if entries.is_empty():
		return
	var next := clampi(index, 0, entries.size() - 1)
	if next == cursor:
		return
	cursor = next
	_ensure_visible()
	queue_redraw()
	cursor_changed.emit(selected())


## Puts the cursor on the entry with [param id]; false when there is none.
func select_id(id: StringName) -> bool:
	for i in entries.size():
		if entries[i].id == id:
			select_index(i)
			return true
	return false


## One D-pad step ([param dir] a unit direction). Returns false when the cursor is at that edge (the owner may move the focus on).
## Down from a column the last, shorter row does not reach goes to the last entry.
func move(dir: Vector2i) -> bool:
	if entries.is_empty() or dir == Vector2i.ZERO:
		return false
	var cols := columns()
	var col := cursor % cols
	var row := cursor / cols
	var next := cursor
	if dir.x != 0:
		var c := col + dir.x
		if c < 0 or c >= cols or row * cols + c >= entries.size():
			return false
		next = row * cols + c
	else:
		var r := row + dir.y
		if r < 0 or r * cols >= entries.size():
			return false
		next = mini(r * cols + col, entries.size() - 1)
	select_index(next)
	return true


## Moves the cursor [param step] pages of rows (a page = the rows that fit).
func page(step: int) -> void:
	var visible_rows := maxi(1, int(floor((size.y + GAP) / (CELL.y + GAP))))
	select_index(cursor + step * visible_rows * columns())


func _row_height() -> float:
	return CELL.y + GAP


func _ensure_visible() -> void:
	var cols := columns()
	var row := cursor / cols
	var top := float(row) * _row_height()
	var bottom := top + CELL.y
	var view := maxf(size.y, CELL.y)
	if top < _scroll:
		_scroll = top
	elif bottom > _scroll + view:
		_scroll = bottom - view
	var content := float(rows()) * _row_height() - GAP
	_scroll = clampf(_scroll, 0.0, maxf(0.0, content - view))


func _on_resized() -> void:
	_ensure_visible()
	queue_redraw()


func _draw() -> void:
	var cols := columns()
	# Centre the columns that fit.
	var used := float(cols) * (CELL.x + GAP) - GAP
	var x0 := maxf(0.0, (size.x - used) * 0.5) if fixed_columns == 0 else 0.0
	var first := maxi(0, int(floor(_scroll / _row_height())))
	var last := mini(rows() - 1, int(ceil((_scroll + size.y) / _row_height())))
	for row in range(first, last + 1):
		for col in cols:
			var i := row * cols + col
			if i >= entries.size():
				break
			var rect := Rect2(Vector2(x0 + float(col) * (CELL.x + GAP), float(row) * _row_height() - _scroll), CELL)
			var e := entries[i]
			var marked := show_marked and e.id == marked_id
			WardrobeIcon.draw_cell(self, rect, e, i == cursor, focused, marked)
	# Scroll hint.
	var content := float(rows()) * _row_height() - GAP
	if content > size.y:
		var track := Rect2(size.x - 5.0, 0.0, 4.0, size.y)
		draw_rect(track, Color(0.2, 0.17, 0.12, 0.6), true)
		var h := maxf(24.0, size.y * size.y / content)
		var y := (size.y - h) * (_scroll / maxf(content - size.y, 1.0))
		draw_rect(Rect2(track.position.x, y, 4.0, h), UiTheme.GOLD_BORDER, true)
