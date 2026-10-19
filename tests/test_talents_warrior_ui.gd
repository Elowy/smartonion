extends TestCase
## Warrior talent texts in the real Talents tab (M5 Wave 2, talents_warrior.md): every shipped
## Arms / Fury / Protection description shows whole in TalentTab's detail panel at
## PlayerPanel.DESIGN_SIZE (the 1280 x 720 layout is the same, scaled) before it is bought –
## the tightest case is a locked capstone with its "Needs 12 points" reason under the text.

const UiFakes := preload("res://tests/ui_fakes.gd")

var players: Array[Player] = []
var panels: Array[PlayerPanel] = []


func is_async() -> bool:
	return true


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


## A Warrior with the shipped trees at team level [param level], its panel on the Talents tab.
func _panel(level: int = 31) -> PlayerPanel:
	RunState.set_start_level(level)
	var slot := PlayerManager.join(ScriptedInput.new("warrior_ui:%d" % PlayerManager.count()), Db.get_class_data(&"warrior"))
	var p := Player.create(slot)
	players.append(p)
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	panel.set_input_focus(true)
	panel.set_tab(PlayerPanel.TALENTS_TAB)
	panel.size = PlayerPanel.DESIGN_SIZE
	panels.append(panel)
	return panel


static func _shipped() -> Array[TalentData]:
	var out: Array[TalentData] = []
	for tree_data in Db.talent_trees_for(&"warrior"):
		for t in tree_data.talents:
			if t != null:
				out.append(t)
	return out


## [param l] shows every line it wraps into and ends inside the clipping holder.
func _check_whole(tab: TalentTab, l: Label, what: String) -> void:
	if not l.visible:
		return
	check_eq(l.get_visible_line_count(), l.get_line_count(), "%s: every line shows (%d px)" % [what, l.get_theme_font_size(&"font_size")])
	check(l.get_global_rect().end.y <= tab._texts_holder.get_global_rect().end.y + 0.5,
		"%s: ends inside the detail panel (%s / %s)" % [what, l.get_global_rect(), tab._texts_holder.get_global_rect()])


func _select_and_check(tab: TalentTab, t: TalentData) -> void:
	tab.select_talent(t.id)
	tab.refresh()
	await tree.process_frame
	await tree.process_frame
	var what := t.display_name
	check(tab.detail_text.visible and tab.detail_text.text != "", "%s: has a text" % what)
	check(tab.detail_text.text.find("{") < 0, "%s: every placeholder filled: %s" % [what, tab.detail_text.text])
	_check_whole(tab, tab.detail_text, what)


func test_every_warrior_talent_text_shows_whole_in_the_talents_tab() -> void:
	var talents := _shipped()
	check(talents.size() >= 27, "Arms, Fury and Protection shipped: %d talents" % talents.size())
	var panel := _panel()
	var tab := panel.talents
	await tree.process_frame
	await tree.process_frame
	check(tab._texts_holder.size.y > 0.0 and tab._texts.size.x > 0.0, "the detail panel is laid out")
	# Nothing spent: tier 1 talents are addable, tier 2+ ones locked with their "Needs N points"
	# reason (one line less for the text), modifiers may add "You haven't learned X".
	for t in talents:
		await _select_and_check(tab, t)
	check_eq(tab.detail_reason.text, "Needs 12 points in Ironwall", "the capstone's lock reason shows (last talent)")
	finished.emit()
