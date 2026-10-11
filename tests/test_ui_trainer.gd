extends TestCase
## Trainer tab (GDD 6.3, PlayerPanel tab 2 / TrainerTab): the slot list (core, learned Active,
## learned Auto-cast, empty slots), buying ranks from the shared wallet (price escalation with
## the wave, max rank, the hold-to-buy rule), the Rank V specialisation prompt, the detail area
## (stats beside the rank, description fitted to the room left), Trainer pings (GDD 10: R3 / Tab
## toggles a RunState want, the row's "Wants" tag, cleared by the purchase and the next round)
## and the tab navigation – driven through PlayerPanel.handle_input like a real pad – and no
## refreshes while hidden (one deferred catch-up when shown).
## Test abilities are built in code; the fit test also walks the shipped Db.abilities.

const UiFakes := preload("res://tests/ui_fakes.gd")
const Fakes := preload("res://tests/test_ui_m3_fakes.gd")
## Shipped descriptions still shortened (ellipsis) at Ranks I / II / IV / V in the design-size
## panel: 44 while the stats had a line of their own, 11 since they share the rank's row.
const MAX_CUT_DESCRIPTIONS := 11

var players: Array[Player] = []
var panels: Array[PlayerPanel] = []
var _async := false


## A TrainerTab that counts its rebuilds.
class CountingTrainer extends TrainerTab:
	var refreshes := 0

	func refresh() -> void:
		refreshes += 1
		super()


func is_async() -> bool:
	return _async


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
	check_eq(tab.row_for(2).rank_label.text, "I", "the rank column")
	check_eq(tab.row_for(2).icon.rank, 0, "no rank mark on the row icon (the column shows it)")
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
	check_eq(tab.detail_rank.text, "Rank I", "detail: rank")
	check_eq(tab.detail_description.text, "Hurls a bolt for 10 damage (1x) every 6 sec.", "description from params_for")
	check_eq(tab.detail_next.text, "Next: Rank II – " + AbilityRanks.rank_text(tab.selected_ability(), 2), "what Rank II adds")
	check_eq(tab.detail_price.text, "25", "price")
	check_eq(panel._context_label.text, "Auto-cast 1", "context line")
	# Y previews the next rank's numbers (AbilityRunner.params_at_rank).
	_tap(panel, slot, PlayerInput.Pad.Y)
	check(tab.preview_next, "Y: preview")
	check_eq(tab.detail_rank.text, "Rank II", "the previewed rank")
	check(tab.detail_rank.get_theme_color(&"font_color").is_equal_approx(UiTheme.GREEN), "in green (the preview mark)")
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
	check(row.rank_label.get_theme_color(&"font_color").is_equal_approx(AbilityIcon.RANK_SPEC_COLOR), "orange: specialised")
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
	check(tab.row_for(2).rank_label.get_theme_color(&"font_color").is_equal_approx(AbilityIcon.RANK_SPEC_COLOR), "orange rank")


# --- Pings (GDD 10) ----------------------------------------------------------------------------

func test_r3_pings_the_selected_rank_for_the_team() -> void:
	var slot := _mage_with_learned()
	var panel := _panel(slot)
	var tab := panel.trainer
	tab.select_slot(2)
	var row := tab.row_for(2)
	check(not row.want_tag.visible, "no marker before the ping")
	check(str(tab.prompt_spec()).contains(str([PlayerInput.Pad.R3, "Ping"])), "the prompt row offers the ping: %s" % str(tab.prompt_spec()))
	_tap(panel, slot, PlayerInput.Pad.R3)
	var key := Trainer.want_key(&"fireball")
	check_eq(key, "trainer:fireball", "the want key")
	check(RunState.has_want(slot.index, key), "R3 pings it – without any gold in the wallet")
	check_eq(RunState.wants.size(), 1, "one want")
	check_eq(RunState.wants[0], {"slot": slot.index, "key": key, "label": "Fireball Rank II", "price": 25}, "who, what, how much")
	check(row.pinged and row.want_tag.visible, "the row shows the Wants tag")
	check(row.want_tag.color.is_equal_approx(slot.color.lightened(0.15)), "in the player's colour")
	check(not tab.row_for(4).want_tag.visible, "only on the pinged row")
	check_eq(panel.last_message, "P1 wants: Fireball Rank II – 25 g", "feedback")
	_tap(panel, slot, PlayerInput.Pad.R3)
	check(not RunState.has_want(slot.index, key), "R3 again takes it back")
	check(not row.want_tag.visible, "marker gone")
	check(panel.last_message.contains("Ping removed"), "feedback: %s" % panel.last_message)


## The glyphs of [param panel]'s prompt row (rebuilt now), left to right.
func _prompt_glyphs(panel: PlayerPanel) -> Array[UiGlyph]:
	panel._update_prompts()
	var out: Array[UiGlyph] = []
	_collect_glyphs(panel._prompt_holder, out)
	return out


static func _collect_glyphs(node: Node, out: Array[UiGlyph]) -> void:
	for c in node.get_children():
		if c is UiGlyph:
			out.append(c)
		_collect_glyphs(c, out)


func test_the_ping_prompt_reads_r3_on_a_pad_and_tab_on_the_keyboard() -> void:
	var slot := _mage_with_learned()
	var panel := _panel(slot)
	panel.trainer.select_slot(2)
	var glyphs := _prompt_glyphs(panel)
	var r3 := glyphs.filter(func(g: UiGlyph) -> bool: return g.text == "R3")
	check_eq(r3.size(), 1, "one R3 glyph in the controller's prompt row")
	if r3.size() == 1:
		check_eq((r3[0] as UiGlyph).style, UiGlyph.Style.PILL, "a stick click is a pill like LB / RB")
	check(glyphs.all(func(g: UiGlyph) -> bool: return g.style != UiGlyph.Style.NAV),
		"no left / right pair: the ping is no sideways move")
	var l3 := UiGlyph.pad(PlayerInput.Pad.L3)
	check(l3.style == UiGlyph.Style.PILL and l3.text == "L3", "L3 likewise")
	var key := UiGlyph.for_input(KeyboardInput.new(), PlayerInput.Pad.R3)
	check(key.style == UiGlyph.Style.KEY and key.text == "Tab", "the keyboard pings with Tab")
	for g: UiGlyph in [l3, key]:
		g.free()


func test_buying_a_pinged_rank_clears_only_that_ping() -> void:
	var slot := _mage_with_learned()
	var r := _runner(slot)
	var panel := _panel(slot)
	var tab := panel.trainer
	tab.select_slot(2)
	_tap(panel, slot, PlayerInput.Pad.R3)
	tab.select_slot(4)
	_tap(panel, slot, PlayerInput.Pad.R3)
	# Another player with the same ability pinged it too (their own hero's rank).
	RunState.toggle_want(3, Trainer.want_key(&"fireball"), "Fireball Rank IV", 75)
	RunState.add_gold(200)
	tab.select_slot(2)
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(r.rank_of(&"fireball"), 2, "bought")
	check(not RunState.has_want(slot.index, Trainer.want_key(&"fireball")), "the purchase cleared the ping")
	check(not tab.row_for(2).want_tag.visible, "and its marker")
	check(RunState.has_want(slot.index, Trainer.want_key(&"frost_nova")), "the other ping stays")
	check(tab.row_for(4).want_tag.visible, "with its marker")
	check(RunState.has_want(3, Trainer.want_key(&"fireball")), "P4's ping on their own Fireball stays")
	check_eq(RunState.spend_log[-1]["label"], "Fireball Rank II", "logged")


func test_max_rank_and_an_open_specialisation_cannot_be_pinged() -> void:
	var slot := _mage_with_learned()
	var r := _runner(slot)
	r.ranks[&"fireball"] = 5
	r.ranks[&"frost_nova"] = 5
	r.set_spec(&"fireball", 0)
	r.invalidate_params()
	var panel := _panel(slot)
	var tab := panel.trainer
	tab.select_slot(2)
	check(not str(tab.prompt_spec()).contains("Ping"), "no ping prompt at Rank V")
	_tap(panel, slot, PlayerInput.Pad.R3)
	check(RunState.wants.is_empty(), "nothing to save gold for")
	check_eq(panel.last_message, "Fireball is at Rank V", "reason")
	tab.select_slot(4)
	check(r.needs_spec(&"frost_nova"), "Frost Nova waits for its specialisation")
	check_eq(tab.ping_block_reason(4), "Choose a specialization – it is free", "the free choice is not pinged")
	check(not tab.toggle_ping(4), "refused")
	check(RunState.wants.is_empty(), "still nothing")


func test_a_new_round_clears_the_ping_marker() -> void:
	var slot := _mage_with_learned()
	var panel := _panel(slot)
	var tab := panel.trainer
	tab.select_slot(2)
	_tap(panel, slot, PlayerInput.Pad.R3)
	check(tab.row_for(2).want_tag.visible, "pinged")
	RunState.begin_spend_round()
	check(not RunState.has_want(slot.index, Trainer.want_key(&"fireball")), "a new round clears the wants")
	check(not tab.row_for(2).want_tag.visible, "the marker follows (RunState.wants_changed)")


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
	check_eq(panel.active_tab, PlayerPanel.TALENTS_TAB, "RT: the Talents tab opens (M5)")
	check(panel.talents.visible and not panel.trainer.visible, "Talents shown")
	check(not panel.trainer.row_for(0).selected, "the hidden Trainer lost the focus outline")
	_tap(panel, slot, PlayerInput.Pad.LT)
	check_eq(panel.active_tab, PlayerPanel.TRAINER_TAB, "LT: back to the Trainer")
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


func test_hidden_trainer_skips_gold_refreshes_until_shown() -> void:
	# The Intermission and its panels stay in the tree, hidden, for the whole wave: a gold pickup
	# must not rebuild the hidden Trainer; it catches up as soon as it is shown again (at the
	# end of that frame).
	_async = true
	var slot := _mage_with_learned()
	RunState.wave = 11
	RunState.add_gold(40)
	var panel := _panel(slot)
	var tab := panel.trainer
	var row := tab.row_for(2)
	check(row.price_label.get_theme_color(&"font_color").is_equal_approx(UiTheme.RED), "40 g cannot pay 45")
	var refreshes: Array[int] = [0]
	tab.prompts_changed.connect(func() -> void: refreshes[0] += 1)
	panel.hide()
	for i in 20:
		RunState.add_gold(5)
	check_eq(refreshes[0], 0, "no refresh while the panel is hidden")
	panel.show()
	await tree.process_frame
	check(refreshes[0] > 0, "shown again: refreshed")
	check(row.price_label.get_theme_color(&"font_color").is_equal_approx(UiTheme.GOLD), "the price follows the wallet once shown")
	refreshes[0] = 0
	RunState.add_gold(1)
	check(refreshes[0] > 0, "visible: every gold change refreshes")
	# The Character tab hides the Trainer too; switching to it refreshes.
	panel.set_tab(PlayerPanel.CHARACTER_TAB)
	refreshes[0] = 0
	RunState.try_spend(RunState.gold - 10)
	check_eq(refreshes[0], 0, "no refresh behind the Character tab")
	panel.set_tab(PlayerPanel.TRAINER_TAB)
	check(row.price_label.get_theme_color(&"font_color").is_equal_approx(UiTheme.RED), "back on the Trainer: 10 g is red again")
	finished.emit()


func test_catch_up_on_show_is_deferred_and_skipped_after_a_refresh() -> void:
	# Regression: the catch-up ran synchronously on NOTIFICATION_VISIBILITY_CHANGED, so showing a
	# stale tab rebuilt it twice (the catch-up, then PlayerPanel.set_tab's / the market start's
	# own refresh), and Intermission.open's momentary show of the market rebuilt it for nothing.
	_async = true
	var slot := _mage_with_learned()
	var holder := Control.new()
	tree.root.add_child(holder)
	var tab := CountingTrainer.new()
	tab.slot = slot
	tab._build()
	holder.add_child(tab)
	tab.refresh()
	holder.hide()
	RunState.add_gold(5)
	check(tab._stale, "hidden: a wallet change only marks the tab stale")
	# Shown, then refreshed explicitly in the same frame (PlayerPanel.set_tab, _start_market).
	tab.refreshes = 0
	holder.show()
	check_eq(tab.refreshes, 0, "not rebuilt inside the visibility notification")
	tab.refresh()
	await tree.process_frame
	check_eq(tab.refreshes, 1, "one rebuild: the explicit refresh cancels the catch-up")
	# Shown and hidden again within one frame (Intermission.open, then the loot roll).
	holder.hide()
	RunState.add_gold(5)
	tab.refreshes = 0
	holder.show()
	holder.hide()
	await tree.process_frame
	check_eq(tab.refreshes, 0, "a momentary show does not rebuild the hidden tab")
	check(tab._stale, "it stays stale")
	# Shown and left alone: caught up once at the end of the frame.
	holder.show()
	await tree.process_frame
	check_eq(tab.refreshes, 1, "caught up once")
	check(not tab._stale, "and fresh")
	UiFakes.free_node(holder)
	finished.emit()


func test_detail_stats_show_cooldown_and_power_and_follow_the_preview() -> void:
	var slot := _mage_with_learned()
	var panel := _panel(slot)
	var tab := panel.trainer
	tab.select_slot(2)
	check_eq(tab.detail_stats.text, "CD 6 s · Power 100%", "Rank I")
	check(tab.detail_stats.get_theme_color(&"font_color").is_equal_approx(UiTheme.TEXT_DIM), "dim while not previewing")
	_tap(panel, slot, PlayerInput.Pad.Y)
	check_eq(tab.detail_stats.text, "CD 5.4 s · Power 125%", "Y: Rank II's cooldown and power")
	check(tab.detail_stats.get_theme_color(&"font_color").is_equal_approx(UiTheme.GREEN), "green in the preview")
	_tap(panel, slot, PlayerInput.Pad.Y)
	# A shipped ability whose description has no {power} / {cooldown}: Y still shows the change.
	var r := _runner(slot)
	var shipped: AbilityData = Db.abilities[&"pyroblast"]
	r.forget(2)
	check_eq(r.learn(shipped), 2, "Pyroblast (Active) on RB")
	tab.select_slot(2)
	var now_text := tab.detail_description.text
	var now_stats := tab.detail_stats.text
	_tap(panel, slot, PlayerInput.Pad.Y)
	check_eq(tab.detail_description.text, now_text, "the description has no rank II numbers")
	check(tab.detail_stats.text != now_stats, "but the stats line changes: %s -> %s" % [now_stats, tab.detail_stats.text])
	check(tab.detail_stats.text.ends_with("Power 125%"), "Rank II power: %s" % tab.detail_stats.text)
	# Haste / Cooldown Reduction are in the shown cooldown (AbilityRunner.cooldown_from_params).
	var params := r.params_at_rank(shipped, 2)
	check_eq(TrainerTab.stats_text(r, shipped, params), "CD %s s · Power 125%%" % AbilityIcon.format_number(snappedf(r.cooldown_from_params(shipped, params), 0.1)), "stats_text")
	# Passives (no cooldown) show the power only.
	var passive := learned(&"passive", AbilityData.Kind.AUTO, 0.0)
	check_eq(TrainerTab.stats_text(r, passive, r.params_at_rank(passive, 4)), "Power 150%", "no cooldown part")


func test_detail_texts_fit_for_every_shipped_ability() -> void:
	# Every shipped ability at Ranks I–V in the design-size panel: the description gets the lines
	# the clip holder has left under the next-rank / specialisation lines (nothing is clipped
	# half-way) and a cut description ends in an ellipsis. The cooldown / power stats sit beside
	# the rank, in full, instead of taking a line from the description.
	_async = true
	var slot := _hero(&"mage")
	var r := _runner(slot)
	var panel := _panel(slot)
	panel.size = PlayerPanel.DESIGN_SIZE
	var tab := panel.trainer
	var holder := tab.detail_description.get_parent().get_parent() as Control
	var texts := tab.detail_description.get_parent() as Control
	for l: Label in [tab.detail_description, tab.detail_next, tab.detail_spec]:
		check_eq(l.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "%s: a cut text ends in an ellipsis" % l.name)
	check(tab.detail_stats.get_parent() == tab.detail_rank.get_parent(), "the stats share the rank's row")
	var stats := tab.detail_stats
	var stats_font := stats.get_theme_font(&"font")
	var cut := 0
	for id: StringName in Db.abilities:
		var a: AbilityData = Db.abilities[id]
		r.set_slot(2, a)
		for rank: int in [1, 2, 4, 5]:
			r.ranks[a.id] = rank
			r.specs.erase(a.id)
			if rank == AbilityRanks.MAX_RANK and not a.specs.is_empty():
				r.specs[a.id] = 0
			r.invalidate_params()
			tab.selected = 2
			tab.refresh()
			await tree.process_frame
			await tree.process_frame
			var what := "%s Rank %s" % [id, AbilityIcon.roman(rank)]
			var room := holder.size.y
			var used := texts.get_combined_minimum_size().y
			check(used <= room + 0.5, "%s: the texts (%s px) fit the holder (%s px)" % [what, used, room])
			for l: Label in [tab.detail_description, tab.detail_next, tab.detail_spec]:
				if l.visible:
					check(l.position.y + l.size.y <= room + 0.5, "%s: %s laid out inside the holder (%s)" % [what, l.text.left(20), l.get_rect()])
			var stats_w := stats_font.get_string_size(stats.text, HORIZONTAL_ALIGNMENT_LEFT, -1, stats.get_theme_font_size(&"font_size")).x
			check(stats_w <= stats.size.x + 0.5, "%s: '%s' (%s px) shown in full beside the rank (%s px)" % [what, stats.text, stats_w, stats.size.x])
			var desc := tab.detail_description
			check(desc.max_lines_visible >= TrainerTab.MIN_DESCRIPTION_LINES, "%s: at least %d description lines" % [what, TrainerTab.MIN_DESCRIPTION_LINES])
			if desc.get_line_count() > desc.max_lines_visible:
				cut += 1
				var line_h := desc.get_line_height() + desc.get_theme_constant(&"line_spacing")
				check(used + line_h > room, "%s: cut although another line fits (%s + %s <= %s)" % [what, used, line_h, room])
	check(cut <= MAX_CUT_DESCRIPTIONS, "the descriptions keep their room: %d of %d cut (at most %d)" % [cut, Db.abilities.size() * 4, MAX_CUT_DESCRIPTIONS])
	finished.emit()
