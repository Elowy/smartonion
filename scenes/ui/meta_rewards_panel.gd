class_name MetaRewardsPanel
extends PanelContainer
## The end screen's block of what the run earned in the main profile (M9): the achievements that unlocked, each with
## what it brings (a class, a Legendary, a difficulty tier, a title ...), and the Seeds and points they paid. It reads the
## result of Meta.record_run ([method fill]) and hides itself when the run unlocked nothing (every automated run: the dev
## profile records nothing). One line per achievement, at most [constant MAX_ROWS]; the rest is a "+N more" line.

const MAX_ROWS := 3

var title_label: Label
var summary_label: Label
## The achievement lines on show (name + reward text each), for tests.
var row_texts: Array[String] = []

var _rows: VBoxContainer


static func create() -> MetaRewardsPanel:
	var p := MetaRewardsPanel.new()
	p.name = "MetaRewardsPanel"
	p._build()
	return p


## Shows the achievements of [param result] (Meta.record_run's dictionary: "achievements" ids, "achievement_seeds",
## "point_titles"); hides the block when there are none.
func fill(result: Dictionary) -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	row_texts.clear()
	var ids: Array = result.get("achievements", [])
	var shown := 0
	var points := 0
	for raw: Variant in ids:
		var data := Db.get_achievement(StringName(str(raw)))
		if data == null:
			continue
		points += data.points
		if shown < MAX_ROWS:
			_rows.add_child(_row(data))
			row_texts.append("%s – %s" % [data.display_name, AchievementTexts.toast_detail(data)])
		shown += 1
	if shown > MAX_ROWS:
		_rows.add_child(UiTheme.label("+%d more in The Onion Patch" % (shown - MAX_ROWS), UiTheme.SMALL))
	var titles: Array = result.get("point_titles", [])
	for t: Variant in titles:
		var line := "Title: %s" % PlayerTitles.name_of(StringName(str(t)))
		_rows.add_child(UiTheme.label(line, UiTheme.GOLD_LABEL, UiTheme.FONT_SMALL, UiTheme.GREEN))
		row_texts.append(line)
	visible = shown > 0
	title_label.text = "Achievement unlocked" if shown == 1 else "%d achievements unlocked" % shown
	summary_label.text = "%d points  ·  +%s Seeds" % [points, UiTheme.format_int(int(result.get("achievement_seeds", points * Meta.SEEDS_PER_POINT)))]


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override(&"panel", UiTheme.stone_style(UiTheme.GOLD_BORDER, Color(0.14, 0.11, 0.07, 0.9)).rebuild())
	var col := UiTheme.vbox(4)
	add_child(col)
	var head := UiTheme.hbox(12)
	col.add_child(head)
	head.add_child(UiIcon.create(UiIcon.Kind.CROWN, Vector2(30, 26)))
	title_label = UiTheme.label("", UiTheme.GOLD_LABEL, UiTheme.FONT_BODY)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	summary_label = UiTheme.label("", UiTheme.SMALL, UiTheme.FONT_SMALL)
	head.add_child(summary_label)
	_rows = UiTheme.vbox(2)
	col.add_child(_rows)
	visible = false


func _row(data: AchievementData) -> Control:
	var row := UiTheme.hbox(10)
	var name_label := UiTheme.label(data.display_name, UiTheme.GOLD_LABEL, UiTheme.FONT_BODY - 2)
	name_label.custom_minimum_size.x = 260.0
	row.add_child(name_label)
	var detail := UiTheme.label(AchievementTexts.toast_detail(data), UiTheme.DIM, UiTheme.FONT_SMALL)
	detail.add_theme_color_override(&"font_color", UiTheme.GREEN.darkened(0.15))
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(detail)
	return row
