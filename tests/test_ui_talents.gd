extends TestCase
## Talents tab (GDD 7, 12; PlayerPanel tab 3 / TalentTab, architecture §2.2): the three trees
## (TalentTreeView / TalentNode: layout, states, rank pills, prerequisite arrows, locked tiers,
## glyphs), the header and the "Talents (N)" tab label, spatial navigation over the 6 x 5 grid
## and the Reset row, A / X / Y with their block reasons, the reset confirm and hold rule, the
## "You haven't learned X" hint, the empty and before-level-10 states and no refreshes while
## hidden – driven through PlayerPanel.handle_input like a real pad.
## Fixture trees are built in code (TalentState.create(class, trees)) and put on the hero; no
## shipped talent content is needed.

const UiFakes := preload("res://tests/ui_fakes.gd")
const DT := 1.0 / 60.0
## Stat ids the M5 talent designs use as icons (talents_<class>.md): each has its own glyph.
const DESIGN_STAT_ICONS: Array[StringName] = [
	&"dodge", &"resource_regen", &"crit", &"damage_pct", &"crit_damage", &"mastery", &"haste",
	&"leech", &"armor", &"block_value", &"parry", &"stamina", &"extra_attack", &"strength",
	&"healing_done", &"block_chance", &"avoidance", &"intellect", &"cooldown_reduction",
	&"executioner", &"speed", &"spirit",
]

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


# --- Fixtures ----------------------------------------------------------------------------------

static func _talent(tree: String, short: String, tier: int, column: int, max_rank: int,
		kind: TalentData.Kind = TalentData.Kind.TALENT, prereq: String = "", icon: StringName = &"") -> TalentData:
	var t := TalentData.new()
	t.id = StringName("warrior_%s_%s" % [tree, short])
	t.display_name = "%s %s" % [tree.capitalize(), short.to_upper()]
	t.description = "Raises dodge by {dodge}%."
	t.values = {"dodge": 2.0}
	t.tier = tier
	t.column = column
	t.max_rank = max_rank
	t.kind = kind
	t.icon = icon
	if prereq != "":
		t.prerequisite = StringName("warrior_%s_%s" % [tree, prereq])
	return t


## A full-shape tree: t1a / t1b, t2a / t2b, t3a (max 2) + t3m (modifier of [param modifier_of]),
## t4a (prerequisite t2a, same column) / t4b (prerequisite t1b, skips tiers), t5 (capstone).
static func _tree(short: String, index: int, modifier_of: StringName = &"whirlwind") -> TalentTreeData:
	var t1a := _talent(short, "t1a", 1, 0, 3, TalentData.Kind.TALENT, "", &"dodge")
	t1a.display_name = "%s Deflection" % short.capitalize()
	var t3m := _talent(short, "t3m", 3, 1, 1, TalentData.Kind.MODIFIER)
	t3m.ability = modifier_of
	t3m.description = "Changes the ability."
	t3m.values = {}
	var talents: Array[TalentData] = [
		t1a, _talent(short, "t1b", 1, 1, 3, TalentData.Kind.TALENT, "", &"crit"),
		_talent(short, "t2a", 2, 0, 3, TalentData.Kind.TALENT, "", &"charge"),
		_talent(short, "t2b", 2, 1, 3),
		_talent(short, "t3a", 3, 0, 2, TalentData.Kind.TALENT, "", &"fire_damage"), t3m,
		_talent(short, "t4a", 4, 0, 3, TalentData.Kind.TALENT, "t2a"),
		_talent(short, "t4b", 4, 1, 3, TalentData.Kind.TALENT, "t1b"),
		_talent(short, "t5", 5, 0, 1, TalentData.Kind.CAPSTONE),
	]
	var tree_data := TalentTreeData.new()
	tree_data.id = StringName("warrior_" + short)
	tree_data.class_id = &"warrior"
	tree_data.display_name = short.capitalize()
	tree_data.description = "The %s build." % short
	tree_data.index = index
	tree_data.color = [Color(0.75, 0.55, 0.35), Color(0.85, 0.22, 0.15), Color(0.45, 0.6, 0.85)][index]
	tree_data.talents = talents
	return tree_data


## Arms / Fury / Protection, given out of order (TalentState sorts by index); Fury's modifier
## changes Execute (a learned ability, not slotted by default).
static func _trees() -> Array[TalentTreeData]:
	return [_tree("protection", 2), _tree("arms", 0), _tree("fury", 1, &"execute")]


static func _id(tree: String, short: String) -> StringName:
	return StringName("warrior_%s_%s" % [tree, short])


## A warrior at team level [param level] with the fixture trees.
func _hero(level: int = 31) -> PlayerSlot:
	RunState.set_start_level(level)
	var slot := PlayerManager.join(ScriptedInput.new("talents:%d" % PlayerManager.count()), Db.get_class_data(&"warrior"))
	var p := Player.create(slot)
	players.append(p)
	p.talents = TalentState.create(&"warrior", _trees())
	p.talents.changed.connect(p._on_talents_changed)
	return slot


func _talents(slot: PlayerSlot) -> TalentState:
	return (slot.player as Player).talents


func _panel(slot: PlayerSlot, open_talents: bool = true) -> PlayerPanel:
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	panel.set_input_focus(true)
	if open_talents:
		panel.set_tab(PlayerPanel.TALENTS_TAB)
	panels.append(panel)
	return panel


## One frame with [param button] pressed, then one with it released.
func _tap(panel: PlayerPanel, slot: PlayerSlot, button: PlayerInput.Pad) -> void:
	var input := slot.input as ScriptedInput
	input.press(button)
	input.poll(DT)
	panel.handle_input(input, DT)
	input.release(button)
	input.poll(0.0)
	panel.handle_input(input, 0.0)


## Holds [param button] for [param seconds] of 60 Hz frames (not released).
func _hold(panel: PlayerPanel, slot: PlayerSlot, button: PlayerInput.Pad, seconds: float) -> void:
	var input := slot.input as ScriptedInput
	input.press(button)
	for i in int(roundf(seconds * 60.0)):
		input.poll(DT)
		panel.handle_input(input, DT)


func _release(panel: PlayerPanel, slot: PlayerSlot, button: PlayerInput.Pad) -> void:
	var input := slot.input as ScriptedInput
	input.release(button)
	input.poll(DT)
	panel.handle_input(input, DT)


## [param seconds] of idle 60 Hz frames.
func _idle(panel: PlayerPanel, slot: PlayerSlot, seconds: float) -> void:
	var input := slot.input as ScriptedInput
	for i in int(roundf(seconds * 60.0)):
		input.poll(DT)
		panel.handle_input(input, DT)


func _select(panel: PlayerPanel, tree_short: String, short: String) -> void:
	panel.talents.select_talent(_id(tree_short, short))
	check_eq(panel.talents.selected_id, _id(tree_short, short), "selected %s %s" % [tree_short, short])


static func _prompt_texts(spec: Array) -> Array[String]:
	var out: Array[String] = []
	for pair: Array in spec:
		out.append(str(pair[1]))
	return out


# --- Layout -------------------------------------------------------------------------------------

func test_three_trees_side_by_side_with_capstones_centred() -> void:
	var slot := _hero()
	var panel := _panel(slot)
	var tab := panel.talents
	check(tab.visible and not panel._body.visible and not panel.trainer.visible, "the Talents tab replaces the paper doll")
	check_eq(tab.tree_views.size(), 3, "three trees")
	var names: Array[String] = []
	for v in tab.tree_views:
		names.append(v.name_label.text)
		check_eq(v.nodes.size(), 9, "%s: nine talents" % v.tree.display_name)
	check_eq(names, ["Arms", "Fury", "Protection"] as Array[String], "GDD order (TalentTreeData.index)")
	var arms := tab.tree_views[0]
	var cap := arms.node_for(_id("arms", "t5"))
	var cap_rect := TalentTreeView.node_rect(cap.talent)
	check_near(cap_rect.get_center().x, TalentTreeView.WIDTH * 0.5, 0.01, "the capstone is centred")
	check_eq(cap.side(), TalentNode.CAPSTONE_SIZE, "and bigger")
	var a := TalentTreeView.node_rect(arms.node_for(_id("arms", "t2a")).talent)
	var b := TalentTreeView.node_rect(arms.node_for(_id("arms", "t2b")).talent)
	check(a.position.x < b.position.x and is_equal_approx(a.position.y, b.position.y), "column 0 left of column 1, same row")
	var t1 := TalentTreeView.node_rect(arms.node_for(_id("arms", "t1a")).talent)
	check(t1.end.y < a.position.y and a.end.y < cap_rect.position.y, "tier 1 on top, the capstone at the bottom")
	# The nav points follow the trees left to right.
	check(tab.nav_point(_id("arms", "t1b")).x < tab.nav_point(_id("fury", "t1a")).x, "Fury right of Arms")
	check(tab.nav_point(_id("fury", "t1b")).x < tab.nav_point(_id("protection", "t1a")).x, "Protection right of Fury")
	check_eq(tab.header_label.text, "Talent points: 22 free · 0 spent", "header at level 31")
	check_eq(arms.points_label.text, "0", "points in the tree")


func test_the_tab_fits_the_panel() -> void:
	_async = true
	var slot := _hero()
	var s := _talents(slot)
	# A long name and a capstone-sized text must not grow the panel.
	var cap := s.talent(_id("arms", "t5"))
	cap.display_name = "An Extremely Long Capstone Name For Testing"
	cap.description = "A very long capstone description that keeps going. ".repeat(12)
	s.tree_of(cap.id).display_name = "Assassination"
	var panel := _panel(slot)
	panel.talents.select_talent(cap.id)
	panel.size = PlayerPanel.DESIGN_SIZE
	panel.refresh()
	var min_size := panel.get_combined_minimum_size()
	check(min_size.x <= PlayerPanel.DESIGN_SIZE.x + 0.5 and min_size.y <= PlayerPanel.DESIGN_SIZE.y + 0.5,
		"the panel keeps its design size: %s" % min_size)
	var frame_min := panel.get_child(0).get_combined_minimum_size() as Vector2
	check(frame_min.x <= PlayerPanel.DESIGN_SIZE.x + 0.5 and frame_min.y <= PlayerPanel.DESIGN_SIZE.y + 0.5,
		"the frame's content fits the design size: %s" % frame_min)
	# TalentTab is a plain Control with an anchored Body (its own minimum size is zero, so the
	# frame check above does not see it): after a layout pass the Body's minimum must fit the
	# area the panel's column gives the tab, and the Body must stay above the prompt row.
	await tree.process_frame
	await tree.process_frame
	var tab := panel.talents
	var body := tab.get_node("Body") as Control
	var body_min := body.get_combined_minimum_size()
	check(tab.size.x > 0.0 and tab.size.y > 0.0, "laid out: %s" % tab.size)
	check(body_min.x <= tab.size.x + 0.5 and body_min.y <= tab.size.y + 0.5,
		"the tab's content fits its area: needs %s, gets %s" % [body_min, tab.size])
	var prompt_row := panel._prompt_holder.get_parent() as Control
	check(body.get_global_rect().end.y <= prompt_row.get_global_rect().position.y + 0.5,
		"the Body ends above the prompt row (%s / %s)" % [body.get_global_rect(), prompt_row.get_global_rect()])
	check(body.get_global_rect().end.x <= tab.get_global_rect().end.x + 0.5, "and inside the tab's width")
	var arms := tab.tree_views[0]
	check(TalentTreeView.fitted_name_size("Assassination", arms.name_label.size.x) >= TalentTreeView.MIN_NAME_FONT,
		"the longest tree name fits")
	check(UiTheme.bold_font().get_string_size("Assassination", HORIZONTAL_ALIGNMENT_LEFT, -1,
		TalentTreeView.fitted_name_size("Assassination", arms.name_label.size.x)).x <= arms.name_label.size.x,
		"at the fitted size")
	# The small texts (sized to stay legible at 720p) stay inside their spots: the widest gate
	# number in the rail, the capstone's rank pill and the points caption in the tree view.
	var gate_w := UiTheme.bold_font().get_string_size(TalentTreeView.TierRail.gate_text(5), HORIZONTAL_ALIGNMENT_LEFT, -1,
		TalentTreeView.TierRail.FONT).x
	check(gate_w <= TalentTreeView.TierRail.WIDTH, "gate number %.1f px in a %.1f px rail" % [gate_w, TalentTreeView.TierRail.WIDTH])
	var cap_node := arms.node_for(cap.id)
	check(cap_node.position.y + cap_node.side() + TalentNode.PILL_HEIGHT * 0.5 <= TalentTreeView.HEIGHT,
		"the capstone's rank pill ends inside the tree")
	var caption := arms.get_node("PointsCaption") as Label
	check(caption.position.y + caption.size.y <= TalentTreeView.HEIGHT + 0.5 and caption.size.x >= caption.get_minimum_size().x,
		"the points caption fits (%s at %s)" % [caption.size, caption.position])
	finished.emit()


## The detail's one-line kind ("Talent · Tier 2", "Modifier · Rain of Fire", "Capstone") fits
## the column whole for every shipped talent – the tree's name is on the prompt row instead.
func test_every_kind_line_fits_the_detail_column() -> void:
	_async = true
	var slot := _hero()
	var panel := _panel(slot)
	panel.size = PlayerPanel.DESIGN_SIZE
	var tab := panel.talents
	_select(panel, "arms", "t3m")
	await tree.process_frame
	await tree.process_frame
	var label := tab.detail_kind
	var width := label.size.x
	check(width > 100.0, "laid out: %.1f" % width)
	var font := label.get_theme_font(&"font")
	var fs := label.get_theme_font_size(&"font_size")
	var count := 0
	for class_id: StringName in Db.classes:
		for tree_data in Db.talent_trees_for(class_id):
			for t in tree_data.talents:
				var text := TalentTab.kind_text(t)
				var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				check(w <= width, "%s: '%s' is %.1f of %.1f px" % [t.id, text, w, width])
				check(not text.begins_with(tree_data.display_name), "%s: no tree name in '%s'" % [t.id, text])
				count += 1
	check_eq(count, 135, "15 trees x 9 talents")
	check_eq(TalentTab.kind_text(_talents(slot).talent(_id("arms", "t5"))), "Capstone", "capstone")
	check_eq(TalentTab.kind_text(_talents(slot).talent(_id("arms", "t2a"))), "Talent · Tier 2", "talent")
	finished.emit()


func test_long_descriptions_shrink_before_they_are_cut() -> void:
	_async = true
	var slot := _hero()
	var cap := _talents(slot).talent(_id("arms", "t5"))
	var panel := _panel(slot)
	panel.size = PlayerPanel.DESIGN_SIZE
	var tab := panel.talents
	tab.select_talent(_id("arms", "t1a"))
	await tree.process_frame
	await tree.process_frame
	check_eq(tab.detail_text.get_theme_font_size(&"font_size"), TalentTab.DETAIL_FONT, "a short text keeps the detail font")
	check(tab.detail_tree.visible, "room left: the tree's identity line shows")
	# A text that overflows at 16 px but fits at 14 px (measured in the real column).
	var room := tab._texts_holder.size.y
	var width := tab._texts.size.x
	var label := tab.detail_text
	var font := label.get_theme_font(&"font")
	var words := PackedStringArray()
	var found := false
	for i in 200:
		words.append("strike")
		label.text = " ".join(words)
		var h16 := TalentTab._wrapped_lines(label, width, TalentTab.DETAIL_FONT) * font.get_height(TalentTab.DETAIL_FONT)
		var h14 := TalentTab._wrapped_lines(label, width, TalentTab.MIN_DETAIL_FONT) * font.get_height(TalentTab.MIN_DETAIL_FONT)
		if h16 > room and h14 <= room:
			found = true
			break
	check(found, "a probe text exists (room %s, width %s)" % [room, width])
	cap.description = label.text
	tab.select_talent(cap.id)
	await tree.process_frame
	await tree.process_frame
	check(label.get_theme_font_size(&"font_size") < TalentTab.DETAIL_FONT, "the long text steps its font down")
	check_eq(label.get_visible_line_count(), label.get_line_count(), "and shows whole")
	tab.select_talent(_id("arms", "t1a"))
	await tree.process_frame
	await tree.process_frame
	check_eq(label.get_theme_font_size(&"font_size"), TalentTab.DETAIL_FONT, "back to the detail font")
	# The identity line shows whole or not at all: a long one is left out, never cut.
	_talents(slot).tree_of(cap.id).description = "A build identity that is far too long. ".repeat(6)
	tab.refresh()
	await tree.process_frame
	await tree.process_frame
	check(not tab.detail_tree.visible, "too long for MAX_TREE_LINES: hidden")
	finished.emit()


# --- Header, tab label, level gate --------------------------------------------------------------

func test_before_level_10_the_header_says_when_points_come() -> void:
	var slot := _hero(7)
	var panel := _panel(slot)
	var tab := panel.talents
	check_eq(tab.header_label.text, "Talent points from level 10 (level 7)", "pre-level-10 header (GDD 7.1)")
	check_eq(panel.tab_text(PlayerPanel.TALENTS_TAB), "Talents", "no points: plain label")
	var node := tab.node_for(_id("arms", "t1a"))
	check_eq(node.state, TalentNode.State.LOCKED, "every talent locked")
	check_eq(tab.detail_reason.text, "Talent points from level 10", "the reason in the detail")
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(panel.last_message, "Talent points from level 10", "A says why")
	check_eq(_talents(slot).points_spent(), 0, "nothing spent")
	# The level arrives (RunState.xp_changed): the shown tab updates at once, the label too.
	RunState.set_start_level(10)
	check_eq(tab.header_label.text, "Talent points: 1 free · 0 spent", "one point at level 10")
	check_eq(panel._tab_labels[PlayerPanel.TALENTS_TAB].text, "Talents (1)", "the tab label shows the free point")
	check_eq(node.state, TalentNode.State.AVAILABLE, "tier 1 opens")


func test_tab_label_follows_spending_even_from_another_tab() -> void:
	var slot := _hero(12)
	var panel := _panel(slot, false)
	check_eq(panel._tab_labels[PlayerPanel.TALENTS_TAB].text, "Talents (3)", "3 free points at level 12")
	_talents(slot).add(_id("arms", "t1a"))
	check_eq(panel._tab_labels[PlayerPanel.TALENTS_TAB].text, "Talents (2)", "relabelled on the change")
	_talents(slot).add(_id("arms", "t1a"))
	_talents(slot).add(_id("arms", "t1a"))
	check_eq(panel._tab_labels[PlayerPanel.TALENTS_TAB].text, "Talents", "no free points: plain")
	panel.set_tab(PlayerPanel.TALENTS_TAB)
	check_eq(panel._tab_labels[PlayerPanel.TALENTS_TAB].text, "Talents", "the active tab keeps its label")


## The value the Character tab's stat list shows for [param stat] ("" when the row is missing).
static func _stat_shown(panel: PlayerPanel, stat: StringName) -> String:
	for cell in panel._stats_grid.get_children():
		if cell.get_child_count() < 2:
			continue
		if (cell.get_child(0) as Label).text == PlayerPanel._stat_name(stat):
			return (cell.get_child(1) as Label).text
	return ""


func test_character_tab_shows_the_talent_stats() -> void:
	# GDD 7.2 / spec 2.2 Flow: after spending, the Character tab shows the new numbers. Talent
	# stats reach the hero through stats.set_source (T-CORE-A's bonus engine; the stand-in here
	# sets the source on TalentState.changed right after the Player's own handler, as the
	# engine does), which fires no Equipment.changed.
	var slot := _hero()
	var hero := slot.player as Player
	var s := _talents(slot)
	var t1a := _id("arms", "t1a")
	# (The lambda reads the state through the hero: capturing s itself would be a reference cycle.)
	s.changed.connect(func() -> void: hero.stats.set_source(&"talents", {Stats.DODGE: 2.0 * hero.talents.rank_of(t1a)}))
	RunState.add_gold(100)
	var panel := _panel(slot, false)
	check_eq(_stat_shown(panel, Stats.DODGE), PlayerPanel._stat_text(Stats.DODGE, 0.0), "no dodge before")
	panel.set_tab(PlayerPanel.TALENTS_TAB)
	panel.talents.select_talent(t1a)
	for i in 3:
		_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(s.rank_of(t1a), 3, "three points in Deflection")
	check_near(hero.stats.get_stat(Stats.DODGE), 6.0, 0.001, "the hero has 6% dodge")
	_tap(panel, slot, PlayerInput.Pad.RT)
	check_eq(panel.active_tab, PlayerPanel.CHARACTER_TAB, "RT: the Character tab")
	check_eq(_stat_shown(panel, Stats.DODGE), PlayerPanel._stat_text(Stats.DODGE, 6.0), "the stat list shows the talent dodge")
	# X takes a point back: the Character tab follows.
	_tap(panel, slot, PlayerInput.Pad.LT)
	check_eq(panel.active_tab, PlayerPanel.TALENTS_TAB, "LT: back to Talents")
	_tap(panel, slot, PlayerInput.Pad.X)
	check_eq(s.rank_of(t1a), 2, "one point taken back")
	_tap(panel, slot, PlayerInput.Pad.RT)
	check_eq(_stat_shown(panel, Stats.DODGE), PlayerPanel._stat_text(Stats.DODGE, 4.0), "after the take-back")
	# A change while the Character tab is shown (a bot's spending) updates it at once.
	s.add(t1a)
	check_eq(_stat_shown(panel, Stats.DODGE), PlayerPanel._stat_text(Stats.DODGE, 6.0), "rebuilt on the change")
	# The reset: the Character tab follows.
	_tap(panel, slot, PlayerInput.Pad.LT)
	panel.talents.select_reset()
	_tap(panel, slot, PlayerInput.Pad.A)
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(s.points_spent(), 0, "reset")
	_tap(panel, slot, PlayerInput.Pad.RT)
	check_eq(panel.active_tab, PlayerPanel.CHARACTER_TAB, "the Character tab again")
	check_eq(_stat_shown(panel, Stats.DODGE), PlayerPanel._stat_text(Stats.DODGE, 0.0), "after the reset")


# --- Navigation ----------------------------------------------------------------------------------

func test_navigation_moves_over_the_grid_and_onto_the_reset_row() -> void:
	var slot := _hero()
	var panel := _panel(slot)
	var tab := panel.talents
	check_eq(tab.selected_id, _id("arms", "t1a"), "starts on the first tree's first talent")
	check(tab.node_for(_id("arms", "t1a")).selected, "selection outline (focused)")
	var input := slot.input as ScriptedInput
	input.press(PlayerInput.Pad.DPAD_RIGHT)
	input.poll(DT)
	panel.handle_input(input, DT)
	check(panel.last_input_consumed, "navigation is used input")
	input.release(PlayerInput.Pad.DPAD_RIGHT)
	input.poll(0.0)
	panel.handle_input(input, 0.0)
	check_eq(tab.selected_id, _id("arms", "t1b"), "right: column 1")
	_tap(panel, slot, PlayerInput.Pad.DPAD_RIGHT)
	check_eq(tab.selected_id, _id("fury", "t1a"), "right: into the next tree")
	_tap(panel, slot, PlayerInput.Pad.DPAD_LEFT)
	check_eq(tab.selected_id, _id("arms", "t1b"), "left: back")
	for expected: String in ["t2b", "t3m", "t4b", "t5"]:
		_tap(panel, slot, PlayerInput.Pad.DPAD_DOWN)
		check_eq(tab.selected_id, _id("arms", expected), "down: %s" % expected)
	_tap(panel, slot, PlayerInput.Pad.DPAD_RIGHT)
	check_eq(tab.selected_id, _id("fury", "t5"), "capstone to capstone")
	_tap(panel, slot, PlayerInput.Pad.DPAD_DOWN)
	check(tab.reset_selected, "down from the bottom row: the Reset row")
	check(tab.reset_row.selected, "the row is outlined")
	check(not tab.node_for(_id("fury", "t5")).selected, "no talent outlined")
	check_eq(tab.detail_name.text, "Reset Talents", "the detail explains the reset")
	_tap(panel, slot, PlayerInput.Pad.DPAD_RIGHT)
	check(tab.reset_selected, "nothing right of the Reset row")
	_tap(panel, slot, PlayerInput.Pad.DPAD_UP)
	check(not tab.reset_selected, "up leaves the Reset row")
	check_eq(tab.selected_id, _id("fury", "t5"), "back where it came from")
	tab.select_talent(_id("protection", "t1b"))
	_tap(panel, slot, PlayerInput.Pad.DPAD_RIGHT)
	check_eq(tab.selected_id, _id("protection", "t1b"), "the right edge: no wrap, no jump to the Reset row")
	panel.set_input_focus(false)
	check(not tab.node_for(_id("protection", "t1b")).selected, "no outline without the focus")


# --- A / X / Y -----------------------------------------------------------------------------------

func test_a_adds_points_and_refusals_show_the_reason() -> void:
	var slot := _hero()
	var s := _talents(slot)
	var panel := _panel(slot)
	var tab := panel.talents
	var node := tab.node_for(_id("arms", "t1a"))
	check_eq(node.state, TalentNode.State.AVAILABLE, "tier 1 is open")
	check_eq(node.rank_text(), "0/3", "rank pill")
	check(_prompt_texts(tab.prompt_spec()).has("Add point"), "A prompt")
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(s.rank_of(_id("arms", "t1a")), 1, "a point went in")
	check_eq(panel.last_message, "Arms Deflection 1/3", "feedback")
	check_eq(node.rank_text(), "1/3", "the pill follows")
	check_eq(node.state, TalentNode.State.PARTIAL, "partial")
	check_eq(node.pending, 1, "a pending point (X can take it back)")
	check_eq(tab.detail_rank.text, "Rank 1/3", "detail rank")
	check_eq(tab.detail_state.text, "+1 this round", "pending in the detail")
	check_eq(tab.header_label.text, "Talent points: 21 free · 1 spent", "header")
	check_eq(panel._tab_labels[PlayerPanel.TALENTS_TAB].text, "Talents (21)", "tab label")
	check_eq(tab.tree_views[0].points_label.text, "1", "points in Arms")
	# A locked tier: the gate reason, nothing spent.
	_select(panel, "arms", "t2a")
	check_eq(tab.node_for(_id("arms", "t2a")).state, TalentNode.State.LOCKED, "tier 2 locked")
	check_eq(tab.detail_reason.text, "Needs 3 points in Arms", "the gate in the detail (red)")
	check(not _prompt_texts(tab.prompt_spec()).has("Add point"), "no A prompt on a locked talent")
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(panel.last_message, "Needs 3 points in Arms", "A says why")
	check_eq(s.rank_of(_id("arms", "t2a")), 0, "refused")
	_select(panel, "arms", "t1a")
	_tap(panel, slot, PlayerInput.Pad.A)
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(node.state, TalentNode.State.MAXED, "3/3: maxed")
	check_eq(tab.detail_reason.text, "", "no reason shown at max rank")
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(panel.last_message, "Max rank", "A at max rank")
	check(not tab.tree_views[0].is_tier_locked(2), "3 points open tier 2")
	check_eq(tab.node_for(_id("arms", "t2a")).state, TalentNode.State.AVAILABLE, "tier 2 available")
	# The prerequisite: t4a needs t2a at 3/3.
	_select(panel, "arms", "t4a")
	s.add(_id("arms", "t2b"))
	s.add(_id("arms", "t2b"))
	s.add(_id("arms", "t2b"))
	s.add(_id("arms", "t3a"))
	s.add(_id("arms", "t3a"))
	s.add(_id("arms", "t3m"))
	check_eq(tab.detail_reason.text, "Requires Arms T2A", "the prerequisite in the detail")
	check_eq(tab.node_for(_id("arms", "t4a")).state, TalentNode.State.LOCKED, "locked by its prerequisite")


func test_no_free_points_leave_open_talents_unavailable() -> void:
	var slot := _hero(10)
	var panel := _panel(slot)
	var tab := panel.talents
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(tab.node_for(_id("arms", "t1b")).state, TalentNode.State.UNAVAILABLE, "open, but no point left")
	check_eq(tab.node_for(_id("arms", "t2a")).state, TalentNode.State.LOCKED, "still gated")
	_select(panel, "arms", "t1b")
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(panel.last_message, "No talent points", "A says why")


func test_x_takes_back_pending_points_only() -> void:
	var slot := _hero()
	var s := _talents(slot)
	var panel := _panel(slot)
	var tab := panel.talents
	for i in 3:
		_tap(panel, slot, PlayerInput.Pad.A)
	_select(panel, "arms", "t2a")
	_tap(panel, slot, PlayerInput.Pad.A)
	check(_prompt_texts(tab.prompt_spec()).has("Take back"), "X prompt on a pending point")
	_select(panel, "arms", "t1a")
	_tap(panel, slot, PlayerInput.Pad.X)
	check_eq(panel.last_message, "Arms T2A needs those points", "a gate break is refused")
	check_eq(s.rank_of(_id("arms", "t1a")), 3, "nothing taken back")
	_select(panel, "arms", "t2a")
	_tap(panel, slot, PlayerInput.Pad.X)
	check_eq(panel.last_message, "Arms T2A back to 0/3", "taken back")
	check_eq(s.rank_of(_id("arms", "t2a")), 0, "rank 0")
	check_eq(tab.node_for(_id("arms", "t2a")).rank_text(), "0/3", "the pill follows")
	_select(panel, "arms", "t1a")
	_tap(panel, slot, PlayerInput.Pad.X)
	check_eq(s.rank_of(_id("arms", "t1a")), 2, "now the tier-1 point can go")
	# Wave start commits: nothing left to take back.
	s.commit()
	panel.refresh()
	check_eq(tab.node_for(_id("arms", "t1a")).pending, 0, "no pending ring after the commit")
	check(not _prompt_texts(tab.prompt_spec()).has("Take back"), "no X prompt")
	_tap(panel, slot, PlayerInput.Pad.X)
	check_eq(panel.last_message, "Only points spent since the last wave can be taken back", "X says why")
	check_eq(s.rank_of(_id("arms", "t1a")), 2, "committed points stay")


func test_y_previews_the_next_rank() -> void:
	var slot := _hero()
	var panel := _panel(slot)
	var tab := panel.talents
	check_eq(tab.detail_text.text, "Raises dodge by 2%.", "rank 0 shows the rank-1 numbers")
	check(not tab.detail_next.visible, "no next-rank line before the first point")
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(tab.detail_text.text, "Raises dodge by 2%.", "rank 1")
	check_eq(tab.detail_next.text, "Next rank: Raises dodge by 4%.", "next rank in green")
	check(tab.detail_next.visible, "shown")
	check(_prompt_texts(tab.prompt_spec()).has("Next rank"), "Y prompt")
	_tap(panel, slot, PlayerInput.Pad.Y)
	check(tab.preview_next, "preview on")
	check_eq(tab.detail_text.text, "Raises dodge by 4%.", "the description at the next rank")
	check_eq(tab.detail_rank.text, "Rank 2/3", "the next rank")
	check_eq(tab.detail_rank.get_theme_color(&"font_color"), UiTheme.GREEN, "in green")
	check(not tab.detail_next.visible, "no separate next line while previewing")
	check(_prompt_texts(tab.prompt_spec()).has("Now"), "Y goes back")
	_tap(panel, slot, PlayerInput.Pad.Y)
	check_eq(tab.detail_text.text, "Raises dodge by 2%.", "back to the current rank")
	_tap(panel, slot, PlayerInput.Pad.Y)
	check(tab.preview_next, "preview on again")
	_select(panel, "arms", "t3m")
	check(not tab.preview_next, "another talent selected: the preview ends")
	check_eq(tab.detail_rank.get_theme_color(&"font_color"), UiTheme.GOLD, "its own rank, not a green preview")


func test_modifier_of_an_unlearned_ability_says_so() -> void:
	var slot := _hero()
	var panel := _panel(slot)
	var tab := panel.talents
	_select(panel, "arms", "t3m")
	check_eq(tab.detail_kind.text, "Modifier · Whirlwind", "kind line names the ability")
	check_eq(tab.detail_hint.text, "", "Whirlwind is a core ability: learned")
	_select(panel, "fury", "t3m")
	check_eq(tab.detail_hint.text, "You haven't learned Execute", "the hint (GDD 7.2)")
	check(tab.detail_hint.visible, "shown")
	var runner := (slot.player as Player).abilities
	check(runner.learn(Db.get_ability(&"execute")) >= 0, "learn Execute")
	check_eq(tab.detail_hint.text, "", "gone once slotted (slots_changed)")


# --- Reset ---------------------------------------------------------------------------------------

func _spend_two(slot: PlayerSlot) -> void:
	_talents(slot).add(_id("arms", "t1a"))
	_talents(slot).add(_id("fury", "t1a"))


func test_reset_needs_a_second_a_and_pays_from_the_wallet() -> void:
	var slot := _hero()
	_spend_two(slot)
	RunState.add_gold(100)
	var panel := _panel(slot)
	var tab := panel.talents
	tab.select_reset()
	check_eq(tab.reset_row.label.text, "Reset Talents – 20 g", "row text (GDD 7.3)")
	check(_prompt_texts(tab.prompt_spec()).has("Reset Talents"), "A prompt")
	_tap(panel, slot, PlayerInput.Pad.A)
	check(tab.is_confirming() and tab.is_modal(), "the first A asks")
	check_eq(tab.reset_row.label.text, "Press A again to reset (20 g)", "the row asks (GDD 7.3)")
	check_eq(tab.detail_hint.text, "Press A again to reset (20 g)", "the detail repeats it")
	check(tab.reset_row.confirm_left > 0.9, "the countdown bar starts full")
	check_eq(_talents(slot).points_spent(), 2, "nothing reset yet")
	_tap(panel, slot, PlayerInput.Pad.RT)
	check_eq(panel.active_tab, PlayerPanel.TALENTS_TAB, "RT does not switch tabs while the confirm is open")
	_tap(panel, slot, PlayerInput.Pad.A)
	check(not tab.is_confirming(), "closed")
	check_eq(_talents(slot).points_spent(), 0, "every point back")
	check_eq(RunState.gold, 80, "20 g from the shared wallet")
	check_eq(RunState.spend_log.size(), 1, "one spend logged")
	if not RunState.spend_log.is_empty():
		var e := RunState.spend_log.back() as Dictionary
		check(e["kind"] == &"talent_reset" and e["slot"] == slot.index and e["amount"] == 20, "logged: %s" % str(e))
	check_eq(panel.last_message, "Talents reset", "feedback")
	check_eq(tab.reset_row.label.text, "Reset Talents – 40 g", "the price doubles")
	check_eq(tab.node_for(_id("arms", "t1a")).rank_text(), "0/3", "the trees follow")


func test_reset_confirm_expires_and_b_cancels_it() -> void:
	var slot := _hero()
	_spend_two(slot)
	RunState.add_gold(100)
	var panel := _panel(slot)
	var tab := panel.talents
	tab.select_reset()
	_tap(panel, slot, PlayerInput.Pad.A)
	_idle(panel, slot, TalentTab.CONFIRM_TIME + 0.1)
	check(not tab.is_confirming(), "the confirm closes after 2 s")
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(_talents(slot).points_spent(), 2, "a late A only reopens it")
	check(tab.is_confirming(), "reopened")
	var input := slot.input as ScriptedInput
	input.press(PlayerInput.Pad.B)
	input.poll(DT)
	panel.handle_input(input, DT)
	check(not tab.is_confirming(), "B cancels")
	check(panel.last_input_consumed, "B was used (no unready)")
	input.release(PlayerInput.Pad.B)
	input.poll(DT)
	panel.handle_input(input, DT)
	input.press(PlayerInput.Pad.B)
	input.poll(DT)
	panel.handle_input(input, DT)
	check(not panel.last_input_consumed, "B without a confirm is left to the Intermission (unready)")
	input.release(PlayerInput.Pad.B)
	input.poll(DT)
	_tap(panel, slot, PlayerInput.Pad.A)
	_tap(panel, slot, PlayerInput.Pad.DPAD_UP)
	check(not tab.is_confirming() and not tab.reset_selected, "moving away cancels")
	check_eq(_talents(slot).points_spent(), 2, "nothing reset")
	check_eq(RunState.gold, 100, "nothing paid")


func test_expensive_reset_needs_a_hold() -> void:
	var slot := _hero()
	_spend_two(slot)
	RunState.add_gold(30)
	var panel := _panel(slot)
	var tab := panel.talents
	tab.select_reset()
	check(TalentTab.needs_hold(20), "20 g is more than half of 30 g")
	_tap(panel, slot, PlayerInput.Pad.A)
	check(_prompt_texts(tab.prompt_spec()).has("Hold to reset"), "the confirm asks for a hold")
	_hold(panel, slot, PlayerInput.Pad.A, 0.5)
	check(tab.is_holding(), "holding")
	check(tab.hold_progress() > 0.3 and tab.hold_progress() < 0.7, "progress %s" % tab.hold_progress())
	check_eq(tab.reset_row.label.text, "Hold A to reset (20 g)", "row text while holding")
	check(tab.reset_row.hold_progress > 0.0, "the row fills")
	_release(panel, slot, PlayerInput.Pad.A)
	check(not tab.is_holding() and not tab.is_confirming(), "letting go cancels")
	check_eq(RunState.gold, 30, "nothing paid")
	_tap(panel, slot, PlayerInput.Pad.A)
	_hold(panel, slot, PlayerInput.Pad.A, ShopPanel.HOLD_TIME + 0.05)
	check_eq(_talents(slot).points_spent(), 0, "held long enough: reset")
	check_eq(RunState.gold, 10, "paid")
	check(not tab.is_holding(), "done")
	_release(panel, slot, PlayerInput.Pad.A)


func test_reset_refusals() -> void:
	var slot := _hero()
	var panel := _panel(slot)
	var tab := panel.talents
	tab.select_reset()
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(panel.last_message, "Nothing to reset", "nothing spent")
	check(not tab.is_confirming(), "no confirm")
	check_eq(tab.detail_reason.text, "Nothing to reset", "the reason in the detail")
	_spend_two(slot)
	RunState.add_gold(5)
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(panel.last_message, "Not enough gold (20 g)", "broke")
	check_eq(tab.reset_row.label.get_theme_color(&"font_color"), UiTheme.RED, "the row in red")
	RunState.add_gold(100)
	check_eq(tab.reset_row.label.get_theme_color(&"font_color"), UiTheme.TEXT, "gold arrived: affordable (gold_changed)")


# --- Nodes, arrows, glyphs -------------------------------------------------------------------------

func test_locked_tiers_rail_and_prerequisite_arrows() -> void:
	var slot := _hero()
	var s := _talents(slot)
	var panel := _panel(slot)
	var tab := panel.talents
	var arms := tab.tree_views[0]
	check(not arms.is_tier_locked(1) and arms.is_tier_locked(2) and arms.is_tier_locked(5), "only tier 1 open")
	check_eq(tab.rail.open, [true, false, false, false, false] as Array[bool], "the rail shows the selected tree's gates")
	check_eq(TalentTreeView.TierRail.gate_text(3), "6", "gate numbers")
	check_eq(TalentTreeView.TierRail.gate_text(1), "", "tier 1 has none")
	var links := arms.links()
	check_eq(links.size(), 2, "two prerequisite arrows")
	var by_to := {}
	for l in links:
		by_to[l["to"]] = l
	check_eq(by_to[_id("arms", "t4a")]["from"], _id("arms", "t2a"), "t4a <- t2a")
	check(not by_to[_id("arms", "t4a")]["met"], "unmet: grey")
	for i in 3:
		s.add(_id("arms", "t1a"))
	for i in 3:
		s.add(_id("arms", "t2a"))
	links = arms.links()
	for l in links:
		if l["to"] == _id("arms", "t4a"):
			check(l["met"], "t2a at 3/3: the arrow lights up")
	check(not arms.is_tier_locked(3), "6 points open tier 3")
	check_eq(tab.rail.open, [true, true, true, false, false] as Array[bool], "the rail follows")
	tab.select_talent(_id("fury", "t1a"))
	check_eq(tab.rail.open, [true, false, false, false, false] as Array[bool], "the rail shows Fury's gates")


func test_glyph_sources() -> void:
	var t := TalentData.new()
	t.icon = &"whirlwind"
	check_eq(TalentNode.source_for(t), "ability:whirlwind", "an ability id: its AbilityIcon glyph")
	var ability_glyph := TalentNode.make_glyph(t, 40.0)
	check(ability_glyph is AbilityIcon, "drawn by AbilityIcon")
	ability_glyph.free()
	t.icon = &"crit"
	check_eq(TalentNode.source_for(t), "stat:crit", "a stat id")
	var g := TalentNode.make_glyph(t, 40.0)
	check(g is TalentGlyph and (g as TalentGlyph).glyph == TalentGlyph.Glyph.CRIT, "a stat glyph")
	g.free()
	t.icon = &"fire_damage"
	check_eq(TalentNode.source_for(t), "school:fire", "a school damage stat")
	var school_icon := TalentNode.make_glyph(t, 40.0) as AbilityIcon
	check(school_icon != null and school_icon.glyph == AbilityIcon.Glyph.FIRE, "AbilityIcon's fire glyph")
	school_icon.free()
	t.icon = &""
	t.kind = TalentData.Kind.MODIFIER
	t.ability = &"execute"
	check_eq(TalentNode.source_for(t), "ability:execute", "a modifier without an icon: its ability")
	t.ability = &""
	check_eq(TalentNode.source_for(t), "kind:modifier", "nothing named: the kind")
	t.kind = TalentData.Kind.CAPSTONE
	check_eq(TalentNode.source_for(t), "kind:capstone", "capstone glyph")
	t.kind = TalentData.Kind.TALENT
	t.icon = &"zz_not_an_id"
	check_eq(TalentNode.source_for(t), "kind:talent", "an unknown id: the kind")
	for stat in DESIGN_STAT_ICONS:
		check(TalentGlyph.is_stat(stat), "%s is a stat" % stat)
		check(TalentGlyph.for_stat(stat) != TalentGlyph.Glyph.STAT, "%s has its own glyph" % stat)
	check_eq(TalentGlyph.for_stat(&"fortune"), TalentGlyph.Glyph.STAT, "other stats: the generic stat glyph")


func test_every_glyph_draws() -> void:
	# Each glyph renders without errors (headless draws run the code paths).
	_async = true
	var holder := Control.new()
	tree.root.add_child(holder)
	for g in TalentGlyph.Glyph.values():
		var glyph := TalentGlyph.create(g, 48.0)
		holder.add_child(glyph)
	var slot := _hero()
	var panel := _panel(slot)
	panel.talents.select_talent(_id("arms", "t3m"))
	await tree.process_frame
	await tree.process_frame
	check_eq(holder.get_child_count(), TalentGlyph.Glyph.size(), "every glyph built")
	holder.queue_free()
	finished.emit()


# --- Empty / hidden ------------------------------------------------------------------------------

func test_class_without_trees_and_no_hero() -> void:
	var slot := _hero()
	(slot.player as Player).talents = TalentState.create(&"zz_test")
	var panel := _panel(slot)
	var tab := panel.talents
	check(tab.tree_views.is_empty(), "no trees")
	check(tab.empty_label.visible, "the empty text")
	check_eq(tab.empty_label.text, "No talents for this class yet", "says so")
	check(not tab.reset_row.visible, "no Reset row")
	check_eq(panel.tab_text(PlayerPanel.TALENTS_TAB), "Talents", "no tree to spend in: no count on the tab")
	check(tab.prompt_spec().is_empty(), "no prompts")
	_tap(panel, slot, PlayerInput.Pad.A)
	_tap(panel, slot, PlayerInput.Pad.X)
	_tap(panel, slot, PlayerInput.Pad.DPAD_DOWN)
	check_eq(tab.selected_id, &"", "nothing selected")
	var lone := TalentTab.create(null)
	lone.refresh()
	check(lone.player() == null and lone.state() == null, "no slot, no hero")
	check(not lone.handle_input(null, DT), "no input")
	check(lone.prompt_spec().is_empty() and lone.context_text() == "", "no prompts")
	check_eq(lone.tab_label(), "Talents", "plain label")
	lone.free()


func test_hidden_tab_catches_up_when_shown() -> void:
	var slot := _hero()
	var panel := _panel(slot, false)
	var tab := panel.talents
	panel.set_tab(PlayerPanel.TALENTS_TAB)
	panel.set_tab(PlayerPanel.CHARACTER_TAB)
	check(not tab.is_visible_in_tree(), "hidden")
	_talents(slot).add(_id("arms", "t1a"))
	check_eq(tab.node_for(_id("arms", "t1a")).rank, 0, "a hidden tab does not rebuild")
	check(tab._stale, "but is stale")
	check_eq(panel._tab_labels[PlayerPanel.TALENTS_TAB].text, "Talents (21)", "the label still follows")
	panel.set_tab(PlayerPanel.TALENTS_TAB)
	check_eq(tab.node_for(_id("arms", "t1a")).rank, 1, "shown: up to date")
	check(not tab._stale, "caught up")


func test_talent_tab_is_wired_like_the_trainer() -> void:
	var slot := _hero()
	var panel := _panel(slot)
	var tab := panel.talents
	check(tab.prompt_spec().size() >= 2, "prompts")
	check_eq(tab.context_text(), "Arms · Tier 1", "context text")
	check_eq(panel._context_label.text, "Arms · Tier 1", "shown by the panel")
	_tap(panel, slot, PlayerInput.Pad.RT)
	check_eq(panel.active_tab, PlayerPanel.CHARACTER_TAB, "RT wraps to the Character tab when nothing is open")
	_tap(panel, slot, PlayerInput.Pad.LT)
	check_eq(panel.active_tab, PlayerPanel.TALENTS_TAB, "LT back to Talents")
