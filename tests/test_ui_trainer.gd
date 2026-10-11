extends TestCase
## Trainer tab (GDD 6.3, PlayerPanel tab 2 / TrainerTab): the slot list (core, learned Active,
## learned Auto-cast, empty slots), buying ranks from the shared wallet (price escalation with
## the wave, max rank, the hold-to-buy rule), the Rank V specialisation prompt, the detail area
## and the tab navigation – driven through PlayerPanel.handle_input like a real pad.
## Test abilities are built in code (no dependency on the ability .tres content).

const UiFakes := preload("res://tests/ui_fakes.gd")
const Fakes := preload("res://tests/test_ui_m3_fakes.gd")

var players: Array[Player] = []
var panels: Array[PlayerPanel] = []


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, 4)
	RunState.wave = 1
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


# --- Helpers ---------------------------------------------------------------------------------

## A learned ability of [param kind] with a description and two Rank V specialisations.
static func learned(id: StringName, kind: AbilityData.Kind, cooldown: float = 6.0) -> AbilityData:
	var a := Fakes.ability(id, &"", 0.0, cooldown)
	a.kind = kind
	a.school = &"fire"
	a.description = "Hurls a bolt for {damage} damage ({power}x) every {cooldown} sec."
	a.params = {"damage": 10.0}
	a.rank3 = {"damage_add": 5.0}
	a.rank3_text = "+5 damage"
	a.specs = [
		{"name": "Bouncing %s" % a.display_name, "text": "Bounces to 2 more enemies.", "mods": {"bounces": 2}},
		{"name": "Exploding %s" % a.display_name, "text": "Explodes on impact.", "mods": {"explode_radius": 3.0}},
	]
	return a


func _hero(class_id: StringName = &"mage") -> PlayerSlot:
	var input := ScriptedInput.new("trainer:%d" % PlayerManager.count())
	var slot := PlayerManager.join(input, Db.get_class_data(class_id))
	players.append(Player.create(slot))
	return slot


func _runner(slot: PlayerSlot) -> AbilityRunner:
	return (slot.player as Player).abilities


func _panel(slot: PlayerSlot, open_trainer: bool = true) -> PlayerPanel:
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	panel.set_input_focus(true)
	if open_trainer:
		panel.set_tab(PlayerPanel.TRAINER_TAB)
	panels.append(panel)
	return panel


## One frame with [param button] pressed, then one with it released.
func _tap(panel: PlayerPanel, slot: PlayerSlot, button: PlayerInput.Pad) -> void:
	var input := slot.input as ScriptedInput
	input.press(button)
	input.poll(1.0 / 60.0)
	panel.handle_input(input, 1.0 / 60.0)
	input.release(button)
	input.poll(0.0)
	panel.handle_input(input, 0.0)


## Holds [param button] for [param seconds] of 60 Hz frames (not released).
func _hold(panel: PlayerPanel, slot: PlayerSlot, button: PlayerInput.Pad, seconds: float) -> void:
	var input := slot.input as ScriptedInput
	input.press(button)
	for i in int(roundf(seconds * 60.0)):
		input.poll(1.0 / 60.0)
		panel.handle_input(input, 1.0 / 60.0)


func _release(panel: PlayerPanel, slot: PlayerSlot, button: PlayerInput.Pad) -> void:
	var input := slot.input as ScriptedInput
	input.release(button)
	input.poll(1.0 / 60.0)
	panel.handle_input(input, 1.0 / 60.0)


## A mage with Fireball on RB and Frost Nova in the first auto-cast slot.
func _mage_with_learned() -> PlayerSlot:
	var slot := _hero()
	var r := _runner(slot)
	check_eq(r.learn(learned(&"fireball", AbilityData.Kind.ACTIVE)), 2, "Fireball learned on RB")
	check_eq(r.learn(learned(&"frost_nova", AbilityData.Kind.AUTO)), 4, "Frost Nova learned in auto-cast slot 1")
	return slot


# --- The list ----------------------------------------------------------------------------------

func test_lists_core_learned_and_empty_slots() -> void:
	var slot := _mage_with_learned()
	var r := _runner(slot)
	RunState.add_gold(100)
	var panel := _panel(slot)
	var tab := panel.trainer
	check(tab.visible and not panel._body.visible, "the Trainer replaces the paper doll")
	check_eq(tab.rows.size(), AbilityRunner.MAX_SLOTS, "one row per ability slot")
	for i in AbilityRunner.CORE_SLOTS:
		var core := r.slots[i]
		check_eq(tab.row_for(i).name_label.text, core.display_name, "core slot %d: %s" % [i, core.display_name])
		check_eq(tab.row_for(i).rank_label.text, "I", "core abilities start at Rank I")
		check(tab.row_for(i).icon.ability == core, "with its icon")
	check_eq(tab.row_for(2).name_label.text, "Fireball", "RB: the learned Active ability")
	check_eq(tab.row_for(4).name_label.text, "Frost Nova", "auto-cast 1")
	check_eq(tab.row_for(2).price_label.text, "25", "Rank II costs 25 g at wave 1")
	check_eq(tab.row_for(2).icon.rank, 1, "rank pips on the icon")
	for i: int in [3, 5, 6, 7]:
		check(tab.row_for(i).is_empty(), "slot %d empty" % i)
		check_eq(tab.row_for(i).name_label.text, "Learn abilities on level-up", "slot %d hint" % i)
		check_eq(tab.row_for(i).price_label.text, "", "no price on an empty slot")
	check_eq(TrainerRow.kind_name(0), "Core", "kind of RT")
	check_eq(TrainerRow.kind_name(3), "Active", "kind of LB")
	check_eq(TrainerRow.kind_name(6), "Auto-cast", "kind of auto 3")
	# Slot tags: the pad's own buttons, a gear for the auto-cast slots.
	check(tab.row_for(0)._tag_holder.get_child(0) is TrainerRow.PromptTag, "RT tag")
	check_eq((tab.row_for(0)._tag_holder.get_child(0) as TrainerRow.PromptTag).text, "RT", "RT")
	check_eq((tab.row_for(3)._tag_holder.get_child(0) as TrainerRow.PromptTag).text, "LB", "LB")
	check(tab.row_for(5)._tag_holder.get_child(0) is TrainerRow.GearTag, "auto-cast tag")


func test_navigation_skips_empty_slots_and_shows_the_detail() -> void:
	var slot := _mage_with_learned()
	var panel := _panel(slot)
	var tab := panel.trainer
	check_eq(tab.selected, 0, "starts on RT")
	check(tab.row_for(0).selected, "the row is outlined")
	_tap(panel, slot, PlayerInput.Pad.DPAD_DOWN)
	check_eq(tab.selected, 1, "LT")
	_tap(panel, slot, PlayerInput.Pad.DPAD_DOWN)
	check_eq(tab.selected, 2, "RB (Fireball)")
	_tap(panel, slot, PlayerInput.Pad.DPAD_DOWN)
	check_eq(tab.selected, 4, "the empty LB is skipped: auto-cast 1")
	_tap(panel, slot, PlayerInput.Pad.DPAD_DOWN)
	check_eq(tab.selected, 0, "wraps to RT past the empty auto-cast slots")
	var input := slot.input as ScriptedInput
	input.press(PlayerInput.Pad.DPAD_UP)
	input.poll(1.0 / 60.0)
	panel.handle_input(input, 1.0 / 60.0)
	check(panel.last_input_consumed, "navigation is used")
	input.release(PlayerInput.Pad.DPAD_UP)
	input.poll(0.0)
	check_eq(tab.selected, 4, "and back up")
	check_eq(tab.detail_name.text, "Frost Nova", "detail: name")
	check_eq(tab.detail_kind.text, "Auto-cast · Fire", "detail: kind and school")
	check_eq(tab.detail_rank.text, "Rank I of V", "detail: rank")
	check_eq(tab.detail_description.text, "Hurls a bolt for 10 damage (1x) every 6 sec.", "description from params_for")
	check_eq(tab.detail_next.text, "Next: Rank II – " + AbilityRanks.rank_text(tab.selected_ability(), 2), "what Rank II adds")
	check_eq(tab.detail_price.text, "25", "price")
	check_eq(panel._context_label.text, "Auto-cast 1", "context line")
	# Y previews the next rank's numbers (AbilityRunner.params_at_rank).
	_tap(panel, slot, PlayerInput.Pad.Y)
	check(tab.preview_next, "Y: preview")
	check_eq(tab.detail_rank.text, "Rank II of V (preview)", "the previewed rank")
	check_eq(tab.detail_description.text, "Hurls a bolt for 10 damage (1.25x) every 5.4 sec.", "Rank II's numbers")
	check_eq(_runner(slot).rank_of(&"frost_nova"), 1, "a preview buys nothing")
	_tap(panel, slot, PlayerInput.Pad.Y)
	check_eq(tab.detail_description.text, "Hurls a bolt for 10 damage (1x) every 6 sec.", "Y again: back to now")


func test_buying_ranks_spends_the_shared_wallet() -> void:
	var slot := _mage_with_learned()
	var r := _runner(slot)
	RunState.add_gold(200)
	var panel := _panel(slot)
	panel.trainer.select_slot(2)
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(r.rank_of(&"fireball"), 2, "A trains Rank II")
	check_eq(RunState.gold, 175, "25 g paid")
	check(panel.last_message.contains("Fireball is now Rank II"), "feedback: %s" % panel.last_message)
	check_eq(panel.trainer.row_for(2).rank_label.text, "II", "the row follows")
	check_eq(panel.trainer.row_for(2).price_label.text, "50", "Rank III costs 25 x 2")
	check_eq(panel.trainer.row_for(2).icon.rank, 2, "two pips")
	check_eq(panel.trainer.detail_description.text, "Hurls a bolt for 10 damage (1.25x) every 5.4 sec.", "the description reads the ranked params")
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(r.rank_of(&"fireball"), 3, "Rank III")
	check_eq(RunState.gold, 125, "50 g paid")
	check_eq(panel.trainer.detail_description.text, "Hurls a bolt for 15 damage (1.25x) every 5.4 sec.", "Rank III's extra effect")
	# Core abilities train too.
	panel.trainer.select_slot(0)
	var core := r.slots[0]
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(r.rank_of(core.id), 2, "the core RT ability trains")
	check_eq(RunState.gold, 100, "25 g")


func test_price_grows_with_the_wave_and_turns_red_when_unaffordable() -> void:
	var slot := _mage_with_learned()
	var r := _runner(slot)
	RunState.wave = 11
	RunState.add_gold(40)
	var panel := _panel(slot)
	var row := panel.trainer.row_for(2)
	check_eq(row.price_label.text, "45", "25 x 1 x (1 + 0.08 x 10)")
	check(row.price_label.get_theme_color(&"font_color").is_equal_approx(UiTheme.RED), "red: 40 g cannot pay 45")
	panel.trainer.select_slot(2)
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(r.rank_of(&"fireball"), 1, "nothing bought")
	check_eq(RunState.gold, 40, "nothing paid")
	check_eq(panel.last_message, "Not enough gold", "reason")
	RunState.add_gold(60)
	check(row.price_label.get_theme_color(&"font_color").is_equal_approx(UiTheme.GOLD), "gold arrived: the price turns gold (RunState.gold_changed)")
	r.ranks[&"fireball"] = 3
	r.invalidate_params()
	panel.refresh()
	check_eq(row.price_label.text, "135", "25 x 3 x 1.8")


func test_expensive_rank_needs_a_hold() -> void:
	var slot := _mage_with_learned()
	var r := _runner(slot)
	RunState.add_gold(40)
	var panel := _panel(slot)
	var tab := panel.trainer
	tab.select_slot(2)
	check(TrainerTab.needs_hold(25), "25 g is more than half of 40 g")
	check(not TrainerTab.needs_hold(20), "20 g is not")
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(r.rank_of(&"fireball"), 1, "a tap does not buy")
	check(not tab.is_holding(), "letting go cancels")
	_hold(panel, slot, PlayerInput.Pad.A, 0.5)
	check(tab.is_holding(), "holding")
	check_near(tab.hold_progress(), 0.5, 0.03, "half way")
	check(tab.row_for(2).hold_progress > 0.4, "the row fills up")
	check_eq(r.rank_of(&"fireball"), 1, "not yet")
	_hold(panel, slot, PlayerInput.Pad.A, 0.55)
	check_eq(r.rank_of(&"fireball"), 2, "held for a second: bought")
	check_eq(RunState.gold, 15, "paid")
	check(not tab.is_holding(), "hold done")
	_release(panel, slot, PlayerInput.Pad.A)
	# A cheap rank (at most half the wallet) is bought on the press.
	RunState.add_gold(85)
	tab.select_slot(4)
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(r.rank_of(&"frost_nova"), 2, "25 of 100 g: bought at once")


func test_hold_is_cancelled_by_b_and_by_moving() -> void:
	var slot := _mage_with_learned()
	var r := _runner(slot)
	RunState.add_gold(30)
	var panel := _panel(slot)
	var tab := panel.trainer
	tab.select_slot(2)
	_hold(panel, slot, PlayerInput.Pad.A, 0.4)
	check(tab.is_holding(), "holding")
	var input := slot.input as ScriptedInput
	input.press(PlayerInput.Pad.B)
	input.poll(1.0 / 60.0)
	panel.handle_input(input, 1.0 / 60.0)
	check(not tab.is_holding(), "B cancels")
	check(panel.last_input_consumed, "B was used (the Intermission must not also unready)")
	input.release(PlayerInput.Pad.B)
	_release(panel, slot, PlayerInput.Pad.A)
	_hold(panel, slot, PlayerInput.Pad.A, 0.4)
	check(tab.is_holding(), "holding again")
	input.press(PlayerInput.Pad.DPAD_DOWN)
	input.poll(1.0 / 60.0)
	panel.handle_input(input, 1.0 / 60.0)
	check(not tab.is_holding(), "moving cancels")
	input.release(PlayerInput.Pad.DPAD_DOWN)
	_hold(panel, slot, PlayerInput.Pad.A, 1.2)
	check_eq(r.rank_of(&"fireball"), 1, "the cancelled hold never buys")
	_release(panel, slot, PlayerInput.Pad.A)
	# Plain B on the list is not used (it unreadies in the market).
	_tap(panel, slot, PlayerInput.Pad.B)
	check(not panel.last_input_consumed, "B with nothing to cancel is left to the Intermission")


func test_max_rank_shows_max_and_refuses() -> void:
	var slot := _mage_with_learned()
	var r := _runner(slot)
	r.ranks[&"fireball"] = 5
	r.set_spec(&"fireball", 0)
	RunState.add_gold(500)
	var panel := _panel(slot)
	var row := panel.trainer.row_for(2)
	check_eq(row.price_label.text, TrainerRow.MAX_TEXT, "MAX")
	check_eq(row.rank_label.text, "V", "Rank V")
	check(row.icon.rank_spec, "orange pips: specialised")
	panel.trainer.select_slot(2)
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(RunState.gold, 500, "nothing paid")
	check_eq(panel.last_message, "Fireball is at Rank V", "reason")
	check(not panel.trainer.detail_next.visible, "no next rank")
	check_eq(panel.trainer.detail_spec.text, "Bouncing Fireball: Bounces to 2 more enemies.", "the chosen specialisation")
	check_eq(panel.trainer.detail_price.text, "Max rank", "detail price")


func test_rank_v_asks_for_a_specialisation() -> void:
	var slot := _mage_with_learned()
	var r := _runner(slot)
	r.ranks[&"fireball"] = 4
	r.invalidate_params()
	RunState.add_gold(1000)
	var panel := _panel(slot)
	var tab := panel.trainer
	tab.select_slot(2)
	check_eq(tab.detail_next.text, "Next: Rank V – Specialization: choose 1 of 2", "Rank V's text")
	check_eq(tab.detail_spec.text, "Bouncing Fireball or Exploding Fireball", "the two choices are previewed")
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(r.rank_of(&"fireball"), 5, "Rank V bought (100 g)")
	check(r.needs_spec(&"fireball"), "needs a specialisation")
	check(tab.is_choosing_spec(), "the choice opens by itself")
	check_eq(tab.chooser.name_labels[0].text, "Bouncing Fireball", "first card")
	check_eq(tab.chooser.name_labels[1].text, "Exploding Fireball", "second card")
	check_eq(tab.chooser.text_labels[1].text, "Explodes on impact.", "what it does")
	check_eq(str(tab.prompt_spec()), str([[TrainerTab.NAV_PROMPT_SIDEWAYS, "Pick"], [PlayerInput.Pad.A, "Learn"], [PlayerInput.Pad.B, "Later"]]), "the chooser's prompts")
	# LT / RT do not leave the tab while choosing; B decides later.
	_tap(panel, slot, PlayerInput.Pad.RT)
	check_eq(panel.active_tab, PlayerPanel.TRAINER_TAB, "still on the Trainer")
	var input := slot.input as ScriptedInput
	input.press(PlayerInput.Pad.B)
	input.poll(1.0 / 60.0)
	panel.handle_input(input, 1.0 / 60.0)
	check(not tab.is_choosing_spec(), "B closes the choice")
	check(panel.last_input_consumed, "B was used (it does not also unready)")
	input.release(PlayerInput.Pad.B)
	input.poll(0.0)
	check_eq(tab.row_for(2).price_label.text, TrainerRow.SPEC_TEXT, "the row asks to choose")
	check(r.needs_spec(&"fireball"), "still open")
	_tap(panel, slot, PlayerInput.Pad.A)
	check(tab.is_choosing_spec(), "A reopens it")
	_tap(panel, slot, PlayerInput.Pad.DPAD_RIGHT)
	check_eq(tab.chooser.choice, 1, "right picks the second")
	_tap(panel, slot, PlayerInput.Pad.A)
	check(not tab.is_choosing_spec(), "learned")
	check_eq(r.spec_of(&"fireball"), 1, "Exploding")
	check_eq(r.params_for(r.slots[2]).get("explode_radius"), 3.0, "the spec's mods are live")
	check(panel.last_message.contains("Exploding Fireball"), "feedback: %s" % panel.last_message)
	check_eq(tab.row_for(2).price_label.text, TrainerRow.MAX_TEXT, "maxed")
	check(tab.row_for(2).icon.rank_spec, "orange pips")


func test_tabs_switch_with_lt_and_rt() -> void:
	var slot := _mage_with_learned()
	var panel := _panel(slot, false)
	check_eq(panel.active_tab, PlayerPanel.CHARACTER_TAB, "opens on Character")
	check(not panel.trainer.visible, "Trainer hidden")
	_tap(panel, slot, PlayerInput.Pad.RT)
	check_eq(panel.active_tab, PlayerPanel.TRAINER_TAB, "RT: Trainer")
	check(panel.trainer.visible and not panel._body.visible, "Trainer shown")
	check(panel.trainer.row_for(0).selected, "the Trainer has the focus outline")
	_tap(panel, slot, PlayerInput.Pad.RT)
	check_eq(panel.last_message, "Talents: coming soon", "Talents stays locked")
	check_eq(panel.active_tab, PlayerPanel.TRAINER_TAB, "still the Trainer")
	_tap(panel, slot, PlayerInput.Pad.LT)
	check_eq(panel.active_tab, PlayerPanel.CHARACTER_TAB, "LT: back to Character")
	check(panel._body.visible and not panel.trainer.visible, "paper doll back")
	# Losing the focus (LB / RB to the shop) drops the outline and any hold.
	panel.set_tab(PlayerPanel.TRAINER_TAB)
	panel.set_input_focus(false)
	check(not panel.trainer.row_for(0).selected, "no outline without focus")


func test_trainer_fits_the_panel_size() -> void:
	var slot := _mage_with_learned()
	var r := _runner(slot)
	r.learn(learned(&"pyroblast", AbilityData.Kind.ACTIVE))
	for id: StringName in [&"arcane_missiles", &"ice_barrier", &"meteor_storm"]:
		r.learn(learned(id, AbilityData.Kind.AUTO))
	var long := r.slots[5]
	long.display_name = "An Extremely Long Ability Name For Testing"
	long.description = "A very long description. ".repeat(20)
	r.invalidate_params()
	var panel := _panel(slot)
	panel.trainer.select_slot(5)
	panel.size = PlayerPanel.DESIGN_SIZE
	panel.refresh()
	check(panel.get_combined_minimum_size().x <= PlayerPanel.DESIGN_SIZE.x + 0.5 and panel.get_combined_minimum_size().y <= PlayerPanel.DESIGN_SIZE.y + 0.5,
		"the panel keeps its design size: %s" % panel.get_combined_minimum_size())
	var frame_min := panel.get_child(0).get_combined_minimum_size() as Vector2
	check(frame_min.x <= PlayerPanel.DESIGN_SIZE.x + 0.5 and frame_min.y <= PlayerPanel.DESIGN_SIZE.y + 0.5,
		"the frame's content fits the design size: %s" % frame_min)
	var list_h := (panel.trainer.rows[0].get_parent() as Control).get_combined_minimum_size().y
	# The body area of the Character tab is what the Trainer gets.
	check(list_h <= 336.0, "8 rows fit the body height (%s px)" % list_h)


func test_detail_area_for_an_empty_selection_and_no_hero() -> void:
	var slot := _hero(&"warrior")
	var panel := _panel(slot)
	check_eq(panel.trainer.selected, 0, "RT")
	check(panel.trainer.detail_name.visible, "detail shown for the core ability")
	panel.trainer.selected = 3
	panel.trainer.refresh()
	check_eq(panel.trainer.selected, 0, "an empty selection moves to the first learned slot")
	# A panel without a hero shows empty rows and does not crash.
	var orphan := PlayerSlot.new(3, ScriptedInput.new("x"), PlayerManager.PLAYER_COLORS[3])
	var p2 := PlayerPanel.create(orphan)
	tree.root.add_child(p2)
	panels.append(p2)
	p2.set_tab(PlayerPanel.TRAINER_TAB)
	check(p2.trainer.row_for(0).is_empty(), "no hero: empty rows")
	p2.trainer.press_train()
	check_eq(p2.last_message, "Learn abilities on level-up", "nothing to train")
