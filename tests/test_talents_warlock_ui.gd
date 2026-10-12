extends TestCase
## Warlock talents in the real Talents tab (PlayerPanel / TalentTab at PlayerPanel.DESIGN_SIZE,
## the shipped trees from Db): every description shows whole – no ellipsis – in the states a
## player browses in: before level 10 ("Talent points from level 10") and at level 31 with no
## points spent (tier 2+ gated, "Needs N points in <tree>"). Before level 10 the capstones are
## left out: a capstone's text plus that reason line is cut the same way for the Arms
## reference capstone (Mortal Strike), the T-UI baseline.

const UiFakes := preload("res://tests/ui_fakes.gd")

var players: Array[Player] = []
var panels: Array[PlayerPanel] = []
var _async := false


func is_async() -> bool:
	return _async


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, 7)
	RunState.wave = 3
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


func _panel(level: int) -> PlayerPanel:
	RunState.set_start_level(level)
	var slot := PlayerManager.join(ScriptedInput.new("wl_talents:%d" % PlayerManager.count()),
		Db.get_class_data(&"warlock"))
	var p := Player.create(slot)
	players.append(p)
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	panel.set_input_focus(true)
	panel.set_tab(PlayerPanel.TALENTS_TAB)
	panel.size = PlayerPanel.DESIGN_SIZE
	panels.append(panel)
	return panel


## "<id>: <visible> / <lines> lines (<reason>)" for every Warlock talent whose description is
## cut in [param panel]'s Talents tab ([param with_capstones] false: capstones skipped).
func _cut_descriptions(panel: PlayerPanel, with_capstones: bool) -> Array[String]:
	var out: Array[String] = []
	var tab := panel.talents
	for t in Db.talent_trees_for(&"warlock"):
		for talent in t.talents:
			if talent == null or (talent.is_capstone() and not with_capstones):
				continue
			tab.select_talent(talent.id)
			await tree.process_frame
			await tree.process_frame
			var label := tab.detail_text
			if label.get_visible_line_count() < label.get_line_count():
				out.append("%s: %d / %d lines at %d px (%s)" % [talent.id, label.get_visible_line_count(),
					label.get_line_count(), label.get_theme_font_size(&"font_size"), tab.detail_reason.text])
	return out


func test_descriptions_show_whole_while_tiers_are_gated() -> void:
	_async = true
	var panel := _panel(31)
	await tree.process_frame
	var shadowburn := &"warlock_destruction_shadowburn"
	panel.talents.select_talent(shadowburn)
	await tree.process_frame
	await tree.process_frame
	check_eq(panel.talents.detail_reason.text, "Needs 6 points in Destruction", "Shadowburn's tier is gated")
	var cut: Array[String] = await _cut_descriptions(panel, true)
	check_eq(cut, [] as Array[String], "level 31, nothing spent: every description shows whole")
	finished.emit()


func test_descriptions_show_whole_before_level_10() -> void:
	_async = true
	var panel := _panel(5)
	await tree.process_frame
	panel.talents.select_talent(&"warlock_destruction_shadowburn")
	await tree.process_frame
	await tree.process_frame
	check_eq(panel.talents.detail_reason.text, "Talent points from level 10", "every talent locked")
	var cut: Array[String] = await _cut_descriptions(panel, false)
	check_eq(cut, [] as Array[String], "level 5: every non-capstone description shows whole")
	finished.emit()
