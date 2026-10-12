extends TestCase
## Mage talent texts in the real Talents tab (M5, talents_mage.md; TalentTab._fit_description):
## every shipped Mage talent's description and its Next rank / hint / reason lines show whole
## (no ellipsis) in the panel's design size (PlayerPanel.DESIGN_SIZE; the panel is laid out
## there and then scaled, so this holds at every resolution).
## The header wraps to two lines before level 10 ("Talent points from level 10 (level 9)") and
## whenever both counts have two digits ("12 free · 10 spent"), which takes one text line from
## the column. Each talent is shown in the tightest states it reaches:
## - rank 0 under a two-line header: before level 10 (reason "Talent points from level 10")
##   and at level 31 with 10+ points spent in the other trees (its tier gate / prerequisite
##   reason, if any); a modifier whose ability is not learned also shows its hint;
## - every partial rank (+ the Next rank line) with one point still free (one-line header);
## - its max rank under a two-line header.
## Not covered (TalentTab layout, the same for every class): a partial rank under a two-line
## header or with every point spent ("No talent points" under Next rank) leaves a 3-line
## description only MIN_DESCRIPTION_LINES lines.

const UiFakes := preload("res://tests/ui_fakes.gd")

var players: Array[Player] = []
var panels: Array[PlayerPanel] = []


func is_async() -> bool:
	return true


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, 7)
	RunState.set_start_level(31)
	players.clear()
	panels.clear()


func after_each() -> void:
	for panel in panels:
		UiFakes.free_node(panel)
	for p in players:
		if is_instance_valid(p):
			p.free()
	panels.clear()
	players.clear()
	UiFakes.reset_players()
	RunState.start_run(1, 7)


func test_every_mage_talent_text_shows_whole_in_the_talents_tab() -> void:
	var slot := PlayerManager.join(ScriptedInput.new("mage_text"), Db.get_class_data(&"mage"))
	var p := Player.create(slot)
	players.append(p)
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	panels.append(panel)
	panel.set_input_focus(true)
	panel.set_tab(PlayerPanel.TALENTS_TAB)
	panel.size = PlayerPanel.DESIGN_SIZE
	var tab := panel.talents
	var s := p.talents
	var count := 0
	for tree_data in s.trees():
		for t in tree_data.talents:
			count += 1
			await _show(tab, s, t, {}, 9, 2, "rank 0, level 9")
			var others := _filler(s, tree_data)
			await _show(tab, s, t, others, _spent(others) + 19, 2, "rank 0, 10+ points elsewhere")
			if t.tier > 1:
				check(tab.detail_reason.visible, "%s: locked at rank 0 (%s)" % [t.display_name, tab.detail_reason.text])
			var opened := _opened(s, tree_data, t)
			for r in range(1, t.max_rank):
				var ranks := opened.duplicate()
				ranks[t.id] = r
				await _show(tab, s, t, ranks, _spent(ranks) + 10, 1, "rank %d, 1 point free" % r)
			var maxed := opened.duplicate()
			maxed.merge(others)
			maxed[t.id] = t.max_rank
			await _show(tab, s, t, maxed, _spent(maxed) + 19, 2, "max rank")
	check_eq(count, 27, "three Mage trees of nine talents")
	finished.emit()


## Shows [param t] in [param tab] with exactly [param ranks] at team level [param level] (the
## header then takes [param header_lines] lines), then checks that no detail text is cut.
func _show(tab: TalentTab, s: TalentState, t: TalentData, ranks: Dictionary, level: int,
		header_lines: int, what: String) -> void:
	RunState.set_start_level(level)
	s.ranks.clear()
	s.pending.clear()
	for id: StringName in ranks:
		s.ranks[id] = int(ranks[id])
	tab.select_talent(t.id)
	tab.refresh()
	await tree.process_frame
	await tree.process_frame
	var label := "%s (%s)" % [t.display_name, what]
	check_eq(tab.selected_id, t.id, "%s selected" % label)
	check_eq(tab.header_label.get_line_count(), header_lines, "%s: header \"%s\"" % [label, tab.header_label.text])
	check(tab.detail_text.visible and tab.detail_text.text != "", "%s: a description" % label)
	for l: Label in [tab.detail_text, tab.detail_next, tab.detail_hint, tab.detail_reason]:
		if l.visible:
			check_eq(l.get_visible_line_count(), l.get_line_count(),
				"%s, font %d: \"%s\" shows whole" % [label, l.get_theme_font_size(&"font_size"), l.text])


## Ranks that open [param t] the way a player gets there: its prerequisite at max rank, then
## lower-tier talents of its tree at max rank until the tier gate is met.
static func _opened(s: TalentState, tree_data: TalentTreeData, t: TalentData) -> Dictionary:
	var ranks := {}
	if t.prerequisite != &"":
		ranks[t.prerequisite] = s.talent(t.prerequisite).max_rank
	var gate := TalentState.gate_points(t.tier)
	for tier in range(1, t.tier):
		for other in tree_data.talents:
			if _spent(ranks) >= gate:
				return ranks
			if other.tier == tier and not ranks.has(other.id):
				ranks[other.id] = other.max_rank
	return ranks


## 10+ points in the first other tree (its lowest tiers at max rank): spent has two digits.
static func _filler(s: TalentState, tree_data: TalentTreeData) -> Dictionary:
	var ranks := {}
	for other_tree in s.trees():
		if other_tree == tree_data:
			continue
		for tier in range(1, 6):
			for other in other_tree.talents:
				if _spent(ranks) >= 10:
					return ranks
				if other.tier == tier:
					ranks[other.id] = other.max_rank
	return ranks


static func _spent(ranks: Dictionary) -> int:
	var n := 0
	for id: StringName in ranks:
		n += int(ranks[id])
	return n
