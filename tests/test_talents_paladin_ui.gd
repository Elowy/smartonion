extends TestCase
## Paladin talents in the Talents tab (M5 Wave 2): every description of the three Paladin trees
## shows whole – no ellipsis – in a real Paladin's PlayerPanel at PlayerPanel.DESIGN_SIZE (the
## panel scales from this size at every resolution). Checked at rank 0 with the tier-gate
## reason under it (the tightest rank-0 layout: capstones show "Needs 12 points in …") and at
## max rank (the largest numbers). The in-between ranks are left out on purpose: there the
## never-cut "Next rank: …" line takes the room and TalentTab gives the description only what is
## left (MIN_DESCRIPTION_LINES) – the Arms reference trees do the same.

const UiFakes := preload("res://tests/ui_fakes.gd")

var players: Array[Player] = []
var panels: Array[PlayerPanel] = []


func is_async() -> bool:
	return true


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, 7)
	RunState.wave = 3


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


func _paladin_panel() -> PlayerPanel:
	RunState.set_start_level(31)
	var slot := PlayerManager.join(ScriptedInput.new("paladin_ui"), Db.get_class_data(&"paladin"))
	players.append(Player.create(slot))
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	panels.append(panel)
	panel.set_input_focus(true)
	panel.set_tab(PlayerPanel.TALENTS_TAB)
	panel.size = PlayerPanel.DESIGN_SIZE
	return panel


## Selects [param id] after another talent (so the detail is rebuilt) and lets the layout settle.
func _show(tab: TalentTab, id: StringName, other: StringName) -> void:
	tab.select_talent(other)
	await tree.process_frame
	tab.select_talent(id)
	await tree.process_frame
	await tree.process_frame


func _check_whole(tab: TalentTab, what: String) -> void:
	var l := tab.detail_text
	check(l.visible and l.text != "", "%s: the description shows" % what)
	check(l.get_visible_line_count() == l.get_line_count(),
		"%s: shows whole (%d of %d lines at %d px): %s" % [what, l.get_visible_line_count(), l.get_line_count(),
			l.get_theme_font_size(&"font_size"), l.text])


func test_every_paladin_description_shows_whole_in_the_talents_tab() -> void:
	var panel := _paladin_panel()
	var tab := panel.talents
	var s := tab.state()
	var trees := Db.talent_trees_for(&"paladin")
	check_eq(trees.size(), 3, "three trees")
	var other := &"paladin_holy_healing_light"
	var count := 0
	for t in trees:
		for d in t.talents:
			s.from_dict({"version": 1, "ranks": {}})
			tab.refresh()
			await _show(tab, d.id, other if d.id != other else &"paladin_holy_aura_mastery")
			if d.tier > 1:
				check(tab.detail_reason.visible, "%s rank 0: the tier-gate reason shows too" % d.id)
			_check_whole(tab, "%s rank 0" % d.id)
			s.from_dict({"version": 1, "ranks": {String(d.id): d.max_rank}})
			tab.refresh()
			await _show(tab, d.id, other if d.id != other else &"paladin_holy_aura_mastery")
			check_eq(tab.detail_rank.text, "Rank %d/%d" % [d.max_rank, d.max_rank], "%s at max rank" % d.id)
			_check_whole(tab, "%s rank %d" % [d.id, d.max_rank])
			count += 1
	check_eq(count, 27, "every Paladin talent")
	finished.emit()
