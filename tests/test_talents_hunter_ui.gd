extends TestCase
## Hunter talents in the real Talents tab (M8 TALENTS-H; PlayerPanel / TalentTab at PlayerPanel.DESIGN_SIZE, the
## shipped trees from Db): the tab shows Packlord, Sharpshot and Wildcraft with their pictures and names that
## fit, every talent has its node and picture, and every description of the 27 talents shows whole – no
## ellipsis – at rank 0 (with the tier-gate reason under it, the tightest rank-0 layout) and at max rank
## (the largest numbers), in the states a player browses in: level 31 with nothing spent and before level 10
## ("Talent points from level 10"; capstones left out there, as in the Warlock test).

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
	var slot := PlayerManager.join(ScriptedInput.new("hunter_talents:%d" % PlayerManager.count()),
		Db.get_class_data(&"hunter"))
	players.append(Player.create(slot))
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	panel.set_input_focus(true)
	panel.set_tab(PlayerPanel.TALENTS_TAB)
	panel.size = PlayerPanel.DESIGN_SIZE
	panels.append(panel)
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


func test_the_tab_shows_the_three_hunter_trees() -> void:
	_async = true
	var panel := _panel(31)
	await tree.process_frame
	var tab := panel.talents
	check_eq(tab.tree_views.size(), 3, "three trees side by side")
	var names: Array[String] = []
	var talents := 0
	for view in tab.tree_views:
		names.append(view.tree.display_name)
		check_eq(view.tree.class_id, &"hunter", "%s is a Hunter tree" % view.tree.id)
		check(GameIcons.for_tree(view.tree) != null, "%s: an emblem" % view.tree.id)
		var width := view.name_label.size.x
		var font := view.name_label.get_theme_font(&"font")
		var fs := view.name_label.get_theme_font_size(&"font_size")
		check(font.get_string_size(view.name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width,
			"%s: the name fits the title (%d px font)" % [view.tree.display_name, fs])
		check(fs >= TalentTreeView.MIN_NAME_FONT, "%s: not below the smallest name size" % view.tree.display_name)
		for t in view.tree.talents:
			check(view.node_for(t.id) != null, "%s has its node" % t.id)
			check(GameIcons.for_talent(t) != null, "%s has its picture" % t.id)
			talents += 1
	check_eq(names, ["Packlord", "Sharpshot", "Wildcraft"] as Array[String], "the three tabs in the design's order")
	check_eq(talents, 27, "27 nodes")
	check_eq(tab.header_text(), "Talent points: 22 free · 0 spent", "level 31: 22 points to spend")
	check_eq(panel.tab_text(PlayerPanel.TALENTS_TAB), "Talents (22)", "the tab label counts them")
	finished.emit()


func test_the_capstones_and_modifiers_say_what_they_are() -> void:
	_async = true
	var panel := _panel(31)
	await tree.process_frame
	var tab := panel.talents
	for id in [&"hunter_packlord_pack_frenzy", &"hunter_sharpshot_steady_aura", &"hunter_wildcraft_firebug_bombs"]:
		tab.select_talent(id)
		await tree.process_frame
		await tree.process_frame
		check_eq(tab.detail_kind.text, "Capstone", "%s: a capstone" % id)
		check_eq(tab.detail_reason.text, "Needs 12 points in %s" % Db.get_talent_tree(StringName(String(id).get_slice("_", 0) + "_" + String(id).get_slice("_", 1))).display_name,
			"%s: gated by the tier" % id)
	var cases := {
		&"hunter_packlord_open_wound": "Modifier · Hunt Signal",
		&"hunter_sharpshot_finishing_arrow": "Modifier · Long Shot",
		&"hunter_wildcraft_brace_of_snares": "Modifier · Blast Snare",
	}
	for id: StringName in cases:
		tab.select_talent(id)
		await tree.process_frame
		await tree.process_frame
		check_eq(tab.detail_kind.text, cases[id], "%s: the modifier line" % id)
		check(tab.detail_hint.visible and "haven't learned" in tab.detail_hint.text, "%s: a Hunter without the ability is told so" % id)
	finished.emit()


func test_descriptions_show_whole_while_tiers_are_gated() -> void:
	_async = true
	var panel := _panel(31)
	await tree.process_frame
	var tab := panel.talents
	var s := tab.state()
	var other := &"hunter_packlord_keen_companion"
	var count := 0
	for t in Db.talent_trees_for(&"hunter"):
		for d in t.talents:
			s.from_dict({"version": 1, "ranks": {}})
			tab.refresh()
			await _show(tab, d.id, other if d.id != other else &"hunter_sharpshot_keen_eyes")
			if d.tier > 1:
				check(tab.detail_reason.visible, "%s rank 0: the tier-gate reason shows too" % d.id)
			_check_whole(tab, "%s rank 0" % d.id)
			s.from_dict({"version": 1, "ranks": {String(d.id): d.max_rank}})
			tab.refresh()
			await _show(tab, d.id, other if d.id != other else &"hunter_sharpshot_keen_eyes")
			check_eq(tab.detail_rank.text, "Rank %d/%d" % [d.max_rank, d.max_rank], "%s at max rank" % d.id)
			_check_whole(tab, "%s rank %d" % [d.id, d.max_rank])
			count += 1
	check_eq(count, 27, "every Hunter talent")
	finished.emit()


func test_descriptions_show_whole_before_level_10() -> void:
	_async = true
	var panel := _panel(5)
	await tree.process_frame
	var tab := panel.talents
	check_eq(tab.header_text(), "Talent points from level 10 (level 5)", "no points yet")
	var count := 0
	for t in Db.talent_trees_for(&"hunter"):
		for d in t.talents:
			if d.is_capstone():
				continue
			tab.select_talent(d.id)
			await tree.process_frame
			await tree.process_frame
			check_eq(tab.detail_reason.text, "Talent points from level 10", "%s: locked" % d.id)
			_check_whole(tab, "%s at level 5" % d.id)
			count += 1
	check_eq(count, 24, "every non-capstone Hunter talent")
	finished.emit()
