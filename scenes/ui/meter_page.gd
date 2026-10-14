class_name MeterPage
extends VBoxContainer
## The "Damage Meter" page of the end screen (M6 METER): one panel per stat (Damage, Healing,
## Absorbed, Taken, Revives, Downs, Kills, Bosses) in a 4 x 2 grid, each with one [MeterBar] per
## hero in the class colour, the best on top (RunSummary.rank), and – in co-op – the Awards below.
## Pure view of a [RunSummary] dictionary: [method fill] rebuilds everything.

const COLUMNS := 4
const GAP := 12
const BAR_HEIGHT := 28.0
const BAR_GAP := 3
const AWARD_COLUMNS := 4
## The class colour of a name on the dark panel is lightened by this much (the bars keep the colour).
const TEXT_LIGHTEN := 0.35

## Stat id -> the VBoxContainer holding its bars (tests, screenshots).
var rows: Dictionary[StringName, VBoxContainer] = {}
## Stat id -> the team total shown beside the title.
var totals: Dictionary[StringName, Label] = {}
var grid: GridContainer
var awards_title: Label
var awards_grid: GridContainer


static func create() -> MeterPage:
	var page := MeterPage.new()
	page.name = "MeterPage"
	page._build()
	return page


func _build() -> void:
	add_theme_constant_override(&"separation", 10)
	grid = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override(&"h_separation", GAP)
	grid.add_theme_constant_override(&"v_separation", GAP)
	add_child(grid)
	for id in RunSummary.STAT_IDS:
		var panel := UiTheme.panel(UiTheme.INSET_PANEL)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(panel)
		var col := UiTheme.vbox(BAR_GAP)
		panel.add_child(col)
		var head := UiTheme.hbox(6)
		col.add_child(head)
		var title := UiTheme.label(RunSummary.STAT_LABELS[id], UiTheme.GOLD_LABEL, 22)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var total := UiTheme.label("", UiTheme.SMALL, UiTheme.FONT_SMALL)
		head.add_child(total)
		totals[id] = total
		var box := UiTheme.vbox(BAR_GAP)
		col.add_child(box)
		rows[id] = box
	awards_title = UiTheme.label("Awards", UiTheme.GOLD_LABEL, 22)
	add_child(awards_title)
	awards_grid = GridContainer.new()
	awards_grid.columns = AWARD_COLUMNS
	awards_grid.add_theme_constant_override(&"h_separation", GAP)
	awards_grid.add_theme_constant_override(&"v_separation", 8)
	add_child(awards_grid)


## Rebuilds the bars and the awards from [param summary] ([method RunSummary.build]).
func fill(summary: Dictionary) -> void:
	var heroes: Array = summary.get("heroes", [])
	for id in RunSummary.STAT_IDS:
		var box := rows[id]
		_clear(box)
		var ranked := RunSummary.rank(heroes, id)
		var best := 0.0
		var sum := 0.0
		for h in ranked:
			var v := float((h["stats"] as Dictionary).get(id, 0.0))
			best = maxf(best, v)
			sum += v
		totals[id].text = RunSummary.format_value(id, sum) if heroes.size() > 1 else ""
		for h in ranked:
			var v := float((h["stats"] as Dictionary).get(id, 0.0))
			var bar := MeterBar.create(BAR_HEIGHT, UiTheme.FONT_SMALL)
			bar.setup("%s %s" % [h["label"], h["class_name"]], RunSummary.format_value(id, v),
					v / best if best > 0.0 else 0.0, h["class_color"], h["color"], RunSummary.shown_value(v) <= 0.0)
			box.add_child(bar)
		if heroes.is_empty():
			box.add_child(UiTheme.centered_label("No heroes", UiTheme.DIM))
	_clear(awards_grid)
	var winners: Array = summary.get("awards", [])
	var show_awards := bool(summary.get("coop", false))
	awards_title.visible = show_awards
	awards_grid.visible = show_awards
	if not show_awards:
		return
	if winners.is_empty():
		awards_grid.add_child(UiTheme.label("Nobody earned an award this time.", UiTheme.DIM, UiTheme.FONT_SMALL))
	for w: Dictionary in winners:
		awards_grid.add_child(_award_chip(w, _hero_of(heroes, int(w["slot"]))))


## One award: its name in gold and the winner under it in the winner's class colour.
func _award_chip(award: Dictionary, hero: Dictionary) -> Control:
	var chip := UiTheme.panel(UiTheme.INSET_PANEL)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.name = "Award_%s" % award["id"]
	var col := UiTheme.vbox(0)
	chip.add_child(col)
	var name_label := UiTheme.centered_label(award["name"], UiTheme.GOLD_LABEL, 21)
	col.add_child(name_label)
	var winner := "%s %s" % [hero.get("label", "?"), hero.get("class_name", "")]
	var who := UiTheme.centered_label(winner, UiTheme.SMALL, UiTheme.FONT_SMALL)
	who.add_theme_color_override(&"font_color", Color(hero.get("class_color", UiTheme.TEXT)).lightened(TEXT_LIGHTEN))
	col.add_child(who)
	return chip


static func _hero_of(heroes: Array, slot_index: int) -> Dictionary:
	for h: Dictionary in heroes:
		if int(h["slot"]) == slot_index:
			return h
	return {}


static func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
