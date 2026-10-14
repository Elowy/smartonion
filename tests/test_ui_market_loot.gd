extends TestCase
## LootRollScreen (GDD 10.1 / 12): items one after another, hidden choices until everyone
## decided, A Need / X Greed / B Pass / Y Greed all remaining per player, 15 s timer
## (undecided = Pass), bots via LootRoll.bot_choice, unplugged players pass, the winner line
## for RESULT_TIME, finished once at the end, solo Take / Sell / Leave, statistics counted
## once. Rolls are FakeLootRolls (test_ui_market_fakes.gd) with scripted 1-100 results.

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var screen: LootRollScreen
var rolls: Array[MarketFakes.FakeLootRoll] = []
var resolved: Array[LootRoll] = []
var finishes := 0
## Scripted 1-100 results per slot index for every roll.
var forced: Dictionary[int, int] = {}
var need_ok := true
var _async := false


func is_async() -> bool:
	return _async


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(2, 5)
	world = MarketFakes.make_world(tree)
	screen = LootRollScreen.create()
	screen.make_roll = func(item: ItemInstance) -> LootRoll:
		var r := MarketFakes.FakeLootRoll.new()
		r.item = item
		r.forced_rolls = forced.duplicate()
		r.need_ok = need_ok
		rolls.append(r)
		return r
	screen.finished.connect(func() -> void: finishes += 1)
	screen.roll_resolved.connect(func(r: LootRoll) -> void: resolved.append(r))
	tree.root.add_child(screen)


func after_each() -> void:
	UiFakes.free_node(screen)
	UiFakes.free_node(world)
	screen = null
	world = null
	UiFakes.reset_players()


func _items(n: int) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for i in n:
		out.append(MarketFakes.make_item("Stormcaller %d" % (i + 1), Items.SlotType.NECK, Items.NO_ARMOR, Items.Rarity.RARE, 40))
	return out


func _open(n: int) -> Array[ItemInstance]:
	var items := _items(n)
	screen.open(items, PlayerManager.get_slots())
	return items


func _step(delta: float = DT) -> void:
	MarketFakes.poll_all(delta)
	screen._process(delta)


func _tap(input: UiFakes.HumanInput, button: PlayerInput.Pad) -> void:
	input.press(button)
	_step()
	input.release(button)
	_step(0.0)


## Lets the opening frame and the per-item input delay pass.
func _settle() -> void:
	_step()
	_step(LootRollScreen.ITEM_INPUT_DELAY)


func test_bots_roll_every_item_and_finish_once() -> void:
	MarketFakes.bot_with_hero(world, "bot:a", &"warrior")
	MarketFakes.bot_with_hero(world, "bot:b", &"mage")
	_open(3)
	check(screen.visible and screen.is_rolling(), "rolling")
	check_eq(screen.counter_label.text, "Items: 1 / 3", "counter")
	check_eq(screen.title_label.text, "Loot Roll", "group roll")
	_step()
	check_eq(screen.phase, LootRollScreen.Phase.RESULT, "bots decide at once -> resolved")
	check_eq(resolved.size(), 1, "roll_resolved")
	check_eq(rolls[0].apply_calls, 1, "applied once")
	check(screen.choice_of(0) != LootRoll.Choice.UNDECIDED and screen.choice_of(1) != LootRoll.Choice.UNDECIDED, "both bots chose")
	_step(LootRollScreen.RESULT_TIME * 0.5)
	check_eq(screen.current, 0, "the winner line stays for a moment")
	_step(LootRollScreen.RESULT_TIME * 0.6)
	check_eq(screen.current, 1, "next item")
	check_eq(screen.counter_label.text, "Items: 2 / 3", "counter follows")
	for i in 10:
		_step(0.5)
	check_eq(finishes, 1, "finished once")
	check_eq(resolved.size(), 3, "every item rolled")
	check_eq(screen.phase, LootRollScreen.Phase.DONE, "done")
	for r in rolls:
		check_eq(r.apply_calls, 1, "each roll applied once")


func test_choices_stay_hidden_until_everyone_decided() -> void:
	var a := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	var b := MarketFakes.human_with_hero(world, "pad:b", &"mage")
	forced = {0: 77, 1: 31}
	var items := _open(1)
	_settle()
	_tap(a, PlayerInput.Pad.A)
	check_eq(screen.choice_of(0), LootRoll.Choice.NEED, "P1 needs")
	check_eq(screen.phase, LootRollScreen.Phase.CHOOSING, "waiting for P2")
	check_eq(rolls[0].resolve_calls, 0, "nothing rolled yet")
	check(not screen.result_label.visible, "no result yet")
	_tap(a, PlayerInput.Pad.B)
	check_eq(screen.choice_of(0), LootRoll.Choice.NEED, "a decision is final")
	_tap(b, PlayerInput.Pad.X)
	check_eq(screen.phase, LootRollScreen.Phase.RESULT, "everyone decided -> resolved")
	var lines := screen.log_lines()
	check("P1 rolls 77 (Need) for [%s]" % items[0].display_name in lines, "roll line: %s" % [lines])
	check("P2 chose Greed for [%s]" % items[0].display_name in lines, "a Greed does not roll against a Need: %s" % [lines])
	check_eq(screen.result_text, "P1 wins [%s]" % items[0].display_name, "winner line")
	check(screen.result_label.visible, "winner shown")


func test_time_out_counts_as_pass() -> void:
	var a := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	MarketFakes.human_with_hero(world, "pad:b", &"mage")
	var items := _open(1)
	_settle()
	_tap(a, PlayerInput.Pad.X)
	for i in 14:
		_step(1.0)
	check_eq(screen.phase, LootRollScreen.Phase.CHOOSING, "still choosing before 15 s")
	check(screen.time_left > 0.0 and screen.time_left < 1.0, "almost out: %.2f" % screen.time_left)
	_step(1.0)
	check_eq(screen.phase, LootRollScreen.Phase.RESULT, "time is up")
	check_eq(screen.choice_of(1), LootRoll.Choice.PASS, "P2 passed")
	check_eq(rolls[0].choices.get(1), LootRoll.Choice.PASS, "the roll got the Pass too")
	check("P2 passed on [%s] (time)" % items[0].display_name in screen.log_lines(), "%s" % [screen.log_lines()])
	check_eq(rolls[0].outcome, &"greed", "P1's Greed wins")


func test_y_greeds_all_remaining_items() -> void:
	var a := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	var b := MarketFakes.human_with_hero(world, "pad:b", &"mage")
	_open(3)
	_settle()
	_tap(a, PlayerInput.Pad.Y)
	check_eq(screen.choice_of(0), LootRoll.Choice.GREED, "greed now")
	check(screen.greed_all.get(0, false), "and for the rest")
	_tap(b, PlayerInput.Pad.B)
	_step(LootRollScreen.RESULT_TIME + 0.01)
	check_eq(screen.current, 1, "second item")
	check_eq(screen.choice_of(0), LootRoll.Choice.GREED, "P1 greeds automatically")
	check_eq(screen.choice_of(1), LootRoll.Choice.UNDECIDED, "P2 still chooses")
	_settle()
	_tap(b, PlayerInput.Pad.A)
	_step(LootRollScreen.RESULT_TIME + 0.01)
	check_eq(screen.current, 2, "third item")
	check_eq(rolls[1].outcome, &"need", "P2's Need beat the auto Greed")


func test_need_greyed_out_when_not_allowed() -> void:
	var a := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	MarketFakes.human_with_hero(world, "pad:b", &"mage")
	need_ok = false
	_open(1)
	_settle()
	_tap(a, PlayerInput.Pad.A)
	check_eq(screen.choice_of(0), LootRoll.Choice.UNDECIDED, "Need refused")
	check(screen.need_reason(PlayerManager.get_slot(0)) != "", "with a reason")
	_tap(a, PlayerInput.Pad.B)
	check_eq(screen.choice_of(0), LootRoll.Choice.PASS, "Pass still works")


func test_unplugged_player_passes_and_bots_use_bot_choice() -> void:
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	var b := MarketFakes.human_with_hero(world, "pad:b", &"mage")
	var bot := MarketFakes.bot_with_hero(world, "bot:c", &"rogue")
	b.connected = false
	var items := _open(1)
	check_eq(screen.choice_of(1), LootRoll.Choice.PASS, "unplugged: Pass at once")
	_step()
	var expected := LootRoll.bot_choice(bot, items[0])
	if expected == LootRoll.Choice.NEED and not rolls[0].can_need(bot):
		expected = LootRoll.Choice.GREED
	check_eq(screen.choice_of(2), expected, "the bot decided like LootRoll.bot_choice")
	check_eq(screen.phase, LootRollScreen.Phase.CHOOSING, "P1 still decides")


func test_press_held_when_opened_is_ignored() -> void:
	var a := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	MarketFakes.human_with_hero(world, "pad:b", &"mage")
	a.press(PlayerInput.Pad.A)
	a.poll(DT)
	_open(1)
	screen._process(DT)
	_step(LootRollScreen.ITEM_INPUT_DELAY)
	check_eq(screen.choice_of(0), LootRoll.Choice.UNDECIDED, "the held A is not a Need")


func test_solo_take_sell_leave() -> void:
	var a := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	var items := _open(3)
	check(screen.is_solo(), "solo")
	check_eq(screen.title_label.text, "Loot", "no roll in solo")
	_settle()
	_tap(a, PlayerInput.Pad.A)
	check_eq(screen.result_text, "P1 takes [%s]" % items[0].display_name, "take")
	_step(LootRollScreen.RESULT_TIME + 0.01)
	_settle()
	_tap(a, PlayerInput.Pad.X)
	check_eq(screen.result_text, "Sold [%s] for %d g" % [items[1].display_name, items[1].greed_value()], "sell")
	_step(LootRollScreen.RESULT_TIME + 0.01)
	_settle()
	_tap(a, PlayerInput.Pad.B)
	check_eq(screen.result_text, "Left [%s] behind" % items[2].display_name, "leave")
	_step(LootRollScreen.RESULT_TIME + 0.01)
	check_eq(finishes, 1, "done")


## M6: a real LootRoll everybody passed on is disenchanted; the result line says how much Dust.
func test_a_passed_item_becomes_dust_and_the_line_says_so() -> void:
	screen.make_roll = func(_item: ItemInstance) -> LootRoll:
		return null  # the screen builds a plain LootRoll
	var a := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	var items := _open(2)
	items[0].rarity = Items.Rarity.EPIC
	items[1].rarity = Items.Rarity.EPIC
	_settle()
	_tap(a, PlayerInput.Pad.B)
	check_eq(screen.result_text, "Disenchanted [%s] into 8 Dust" % items[0].display_name, "solo leave")
	check_eq(RunState.arcane_dust, 8, "into the team pile")
	check(screen.result_label.text.contains("8 Dust"), "the result label shows the Dust: %s" % screen.result_label.text)
	_step(LootRollScreen.RESULT_TIME + 0.01)
	_settle()
	_tap(a, PlayerInput.Pad.A)
	check_eq(RunState.arcane_dust, 8, "taking an item makes no Dust")


func test_everybody_passing_in_a_party_disenchants_too() -> void:
	screen.make_roll = func(_item: ItemInstance) -> LootRoll:
		return null
	var a := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	var b := MarketFakes.human_with_hero(world, "pad:b", &"mage")
	var items := _open(1)
	items[0].rarity = Items.Rarity.RARE
	_settle()
	_tap(a, PlayerInput.Pad.B)
	_tap(b, PlayerInput.Pad.B)
	check_eq(screen.result_text, "Everyone passed on [%s] – disenchanted into 4 Dust" % items[0].display_name, "party pass")
	check_eq(RunState.arcane_dust, 4, "Rare = 4")


func test_statistics_are_counted_once() -> void:
	var a := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	var b := MarketFakes.human_with_hero(world, "pad:b", &"mage")
	var items := _open(2)
	_settle()
	_tap(a, PlayerInput.Pad.A)
	_tap(b, PlayerInput.Pad.X)
	check_eq(RunState.need_wins_by_player.get(0, 0), 1, "the screen books the Need win when the roll did not")
	_step(LootRollScreen.RESULT_TIME + 0.01)
	rolls[1].books_stats = true
	_settle()
	_tap(a, PlayerInput.Pad.X)
	_tap(b, PlayerInput.Pad.X)
	check_eq(RunState.greed_gold, items[1].greed_value(), "a roll that books its own Greed gold is not counted twice")


func test_empty_loot_finishes_on_the_next_frame() -> void:
	_async = true
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	screen.open([] as Array[ItemInstance], PlayerManager.get_slots())
	check_eq(finishes, 0, "deferred")
	await tree.process_frame
	check_eq(finishes, 1, "finished")
	finished.emit()


## Tier sets (M5): the loot roll is everyone's window, so its tooltip has no viewer equipment –
## the set block shows "(5 pieces)", every piece and every bonus grey.
func test_set_piece_tooltip_in_the_loot_roll() -> void:
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	MarketFakes.human_with_hero(world, "pad:b", &"rogue")
	var piece := ItemGenerator.from_unique(Db.get_unique(&"set_rogue_hands"), 9, true, RandomNumberGenerator.new())
	screen.open([piece] as Array[ItemInstance], PlayerManager.get_slots())
	_settle()
	check(screen.tooltip.viewer_equipment == null, "nobody's equipment")
	check(screen.tooltip.find_line("Shadowstitch Garb (5 pieces)", true) != null, "(5 pieces): %s" % screen.tooltip.line_texts())
	var bonus := screen.tooltip.find_line("(2) Set: Increases your critical strike chance by 5%.", true)
	check(bonus != null and bonus.get_theme_color(&"font_color").is_equal_approx(ItemTooltip.DIM), "bonuses grey")
	check(screen.tooltip.find_line("Shadowstitch Leggings", true) != null, "piece list")
