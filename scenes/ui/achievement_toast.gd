class_name AchievementToast
extends Control
## The HUD toast of a new achievement (M9): a small stone plaque on the right edge – a crown, "ACHIEVEMENT UNLOCKED",
## the name and what it brings (its first reward, else the points) – that slides in, stays [constant HOLD_TIME] seconds
## and slides out. Several achievements in a row queue up and show one after the other ([method push]). It runs on
## the HUD's own clock (it freezes with the game, like the HUD).

const WIDTH := 430.0
## Seconds sliding in, holding, sliding out.
const SLIDE_TIME := 0.28
const HOLD_TIME := 3.4
## The plaque's vertical place (share of the screen height) and the gap to the screen edge.
const ANCHOR_Y := 0.56
const EDGE_GAP := 22.0
## The most that may wait: an overflow keeps the newest.
const MAX_QUEUE := 8

## The achievement on show (null = none) and the ones waiting.
var current: AchievementData
var queue: Array[AchievementData] = []

var name_label: Label
var detail_label: Label
var caption_label: Label

var _panel: PanelContainer
var _age := 0.0


static func create() -> AchievementToast:
	var t := AchievementToast.new()
	t.name = "AchievementToast"
	t._build()
	return t


## Shows [param data] (right away when nothing is on show, else after the ones before it).
func push(data: AchievementData) -> void:
	if data == null:
		return
	queue.append(data)
	while queue.size() > MAX_QUEUE:
		queue.pop_front()
	if current == null:
		_next()


func is_showing() -> bool:
	return current != null


## The achievements still to come, on show first.
func pending_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	if current != null:
		out.append(current.id)
	for d in queue:
		out.append(d.id)
	return out


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = UiTheme.panel()
	var style := UiTheme.stone_style(UiTheme.GOLD_BORDER, Color(0.1, 0.085, 0.075, 0.94))
	style.content_margin_left = 16
	style.content_margin_right = 20
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override(&"panel", style.rebuild())
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = ANCHOR_Y
	_panel.anchor_bottom = ANCHOR_Y
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	var row := UiTheme.hbox(14)
	_panel.add_child(row)
	var crown := UiIcon.create(UiIcon.Kind.CROWN, Vector2(54, 46))
	crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(crown)
	var col := UiTheme.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	caption_label = UiTheme.label("ACHIEVEMENT UNLOCKED", UiTheme.SMALL, UiTheme.FONT_SMALL - 3)
	col.add_child(caption_label)
	name_label = UiTheme.label("", UiTheme.GOLD_LABEL, UiTheme.FONT_LARGE - 2)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(name_label)
	detail_label = UiTheme.label("", UiTheme.DIM, UiTheme.FONT_SMALL)
	detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(detail_label)
	_panel.visible = false
	_place(1.0)


func _next() -> void:
	if queue.is_empty():
		current = null
		_panel.visible = false
		return
	current = queue.pop_front()
	_age = 0.0
	name_label.text = current.display_name
	detail_label.text = AchievementTexts.toast_detail(current)
	_panel.visible = true
	_place(1.0)


func _process(delta: float) -> void:
	if current == null:
		return
	_age += delta
	var total := SLIDE_TIME * 2.0 + HOLD_TIME
	if _age >= total:
		_next()
		return
	var out := clampf((_age - SLIDE_TIME - HOLD_TIME) / SLIDE_TIME, 0.0, 1.0)
	var into := clampf(_age / SLIDE_TIME, 0.0, 1.0)
	_place(1.0 - ease(into, -2.0) if out <= 0.0 else ease(out, 2.0))


## [param hidden] 0 = fully on screen, 1 = fully off the right edge.
func _place(hidden: float) -> void:
	_panel.offset_right = -EDGE_GAP + hidden * (WIDTH + EDGE_GAP * 2.0)
	_panel.offset_left = _panel.offset_right - WIDTH
	_panel.modulate.a = 1.0 - 0.5 * hidden
