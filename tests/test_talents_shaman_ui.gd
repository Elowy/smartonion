extends TestCase
## Shaman talents in the real Talents tab (PlayerPanel / TalentTab at PlayerPanel.DESIGN_SIZE, the shipped trees
## from Db): the three trees are shown in tab order with their emblem and nine nodes each, every node draws its own
## picture, the header counts the points, a point can be spent and taken back with the pad, and every description
## shows whole - no ellipsis - in the states a player browses in: before level 10 ("Talent points from level 10";
## capstones left out, as for the other classes: their text plus the reason line is cut the same way for the
## Arms reference capstone) and at level 31 with no points spent (tier 2+ gated, "Needs N points in <tree>").

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
	var slot := PlayerManager.join(ScriptedInput.new("sh_talents:%d" % PlayerManager.count()), Db.get_class_data(&"shaman"))
	var p := Player.create(slot)
	players.append(p)
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	panel.set_input_focus(true)
	panel.set_tab(PlayerPanel.TALENTS_TAB)
	panel.size = PlayerPanel.DESIGN_SIZE
	panels.append(panel)
	return panel


## "<id>: <visible> / <lines> lines (<reason>)" for every Shaman talent whose description is cut in [param panel]'s
## Talents tab ([param with_capstones] false: capstones skipped).
func _cut_descriptions(panel: PlayerPanel, with_capstones: bool) -> Array[String]:
	var out: Array[String] = []
	var tab := panel.talents
	for t in Db.talent_trees_for(&"shaman"):
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


func test_the_tab_shows_the_three_shaman_trees_with_their_emblems_and_pictures() -> void:
	_async = true
	var panel := _panel(31)
	await tree.process_frame
	await tree.process_frame
	var tab := panel.talents
	check_eq(tab.tree_views.size(), 3, "three trees")
	if tab.tree_views.size() == 3:
		var names: Array[String] = []
		for v in tab.tree_views:
			names.append(v.name_label.text)
			check_eq(v.nodes.size(), 9, "%s: nine nodes" % v.tree.id)
			check(v._emblem != null and v._emblem == GameIcons.for_tree(v.tree), "%s shows its emblem" % v.tree.id)
			check(TalentTreeView.fitted_name_size(v.name_label.text, v.name_label.size.x) >= TalentTreeView.MIN_NAME_FONT,
				"%s: the name fits next to the emblem" % v.tree.id)
			for id in v.nodes:
				var g := v.nodes[id].glyph_control()
				var texture: Texture2D = (g as AbilityIcon).icon_texture if g is AbilityIcon else (g as TalentGlyph).texture
				check(texture != null and texture == GameIcons.for_talent(v.nodes[id].talent), "%s draws its own picture" % id)
		check_eq(names, ["Stormweaving", "Warspirit", "Wellspring"] as Array[String], "names in tab order")
	check_eq(tab.tab_label(), "Talents (22)", "22 points to spend at level 31")
	check_eq(tab.header_text(), "Talent points: 22 free · 0 spent", "header")
	check(not tab.empty_label.visible, "the 'no talents' note is gone")
	# The same pad presses that work for every class: take a point in Livewire, then give it back (pending).
	var p := players[0]
	tab.select_talent(&"shaman_stormweaving_livewire")
	check(tab.press_add(), "a point goes into Livewire")
	check_eq(p.talents.rank_of(&"shaman_stormweaving_livewire"), 1, "rank 1")
	check_eq(tab.header_text(), "Talent points: 21 free · 1 spent", "header follows")
	check(tab.press_take_back(), "and comes back")
	check_eq(p.talents.rank_of(&"shaman_stormweaving_livewire"), 0, "rank 0")
	finished.emit()


func test_the_gate_reasons_name_the_shaman_trees() -> void:
	_async = true
	var panel := _panel(31)
	await tree.process_frame
	var cases := {
		&"shaman_stormweaving_charged_mind": "Needs 3 points in Stormweaving",
		&"shaman_warspirit_flame_tempering": "Needs 6 points in Warspirit",
		&"shaman_wellspring_blessed_rite": "Needs 9 points in Wellspring",
		&"shaman_wellspring_bond_totem": "Needs 12 points in Wellspring",
	}
	for id: StringName in cases:
		panel.talents.select_talent(id)
		await tree.process_frame
		await tree.process_frame
		check_eq(panel.talents.detail_reason.text, cases[id], "%s: the gate" % id)
	# A modifier of an ability the hero has not learned says so.
	panel.talents.select_talent(&"shaman_warspirit_molten_trail")
	await tree.process_frame
	check_eq(panel.talents.not_learned_text(Db.get_talent(&"shaman_warspirit_molten_trail")), "You haven't learned Magma Lash", "hint")
	finished.emit()


func test_descriptions_show_whole_while_tiers_are_gated() -> void:
	_async = true
	var panel := _panel(31)
	await tree.process_frame
	var cut: Array[String] = await _cut_descriptions(panel, true)
	check_eq(cut, [] as Array[String], "level 31, nothing spent: every description shows whole")
	finished.emit()


func test_descriptions_show_whole_before_level_10() -> void:
	_async = true
	var panel := _panel(5)
	await tree.process_frame
	panel.talents.select_talent(&"shaman_wellspring_deepening_rain")
	await tree.process_frame
	await tree.process_frame
	check_eq(panel.talents.detail_reason.text, "Talent points from level 10", "every talent locked")
	var cut: Array[String] = await _cut_descriptions(panel, false)
	check_eq(cut, [] as Array[String], "level 5: every non-capstone description shows whole")
	finished.emit()
