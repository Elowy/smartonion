extends TestCase
## Co-op input / UX regressions of the between-wave screens (loot roll + shared market), found
## by the M2 review. Real Shop and LootRoll (RunState.start_run builds the run's Shop), humans
## are HumanInput fakes:
##   - A / X (buy / lock) are ignored for MARKET_INPUT_LOCKOUT after the market opens
##   - a stick held while the screen opens (or the loot roll ends) does not drift the cursor
##   - standing reroll votes are evaluated every frame (voter unplugged / gold arrives later);
##     votes of players who are no longer voters are dropped
##   - a replugged pad is un-readied
##   - a hold-to-buy never survives a reroll / an offer change; B cancels it without unreadying
##   - Y (Greed all remaining) also counts while the result line shows
##   - PlayerManager.player_left updates the open market; an unplugged pad has no cursor / tooltip

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var screen: Intermission
var continues := 0


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(2, 9)
	world = MarketFakes.make_world(tree)
	screen = Intermission.create()
	screen.continue_requested.connect(func() -> void: continues += 1)
	tree.root.add_child(screen)


func after_each() -> void:
	Intermission.auto_continue_time = Intermission.AUTO_CONTINUE_TIME
	UiFakes.free_node(screen)
	UiFakes.free_node(world)
	screen = null
	world = null
	RunState.start_run(1, 1)
	UiFakes.reset_players()


## One frame: inputs polled, the intermission runs, and the loot screen while it is up.
func _step(delta: float = DT) -> void:
	MarketFakes.poll_all(delta)
	screen._process(delta)
	if screen.loot_screen.visible:
		screen.loot_screen._process(delta)


func _tap(input: UiFakes.HumanInput, button: PlayerInput.Pad) -> void:
	input.press(button)
	_step()
	input.release(button)
	_step(0.0)


func _two_humans() -> Array[UiFakes.HumanInput]:
	var out: Array[UiFakes.HumanInput] = []
	out.append(MarketFakes.human_with_hero(world, "pad:a", &"warrior"))
	out.append(MarketFakes.human_with_hero(world, "pad:b", &"mage"))
	return out


func _loot(n: int) -> void:
	for i in n:
		RunState.add_team_loot(MarketFakes.make_item("Looted Charm %d" % i, Items.SlotType.TRINKET, Items.NO_ARMOR, Items.Rarity.RARE))


## Opens the market without loot and gets past the opening frame and the A / X lockout.
func _open_market(wave: int = 1) -> void:
	screen.open(wave, 0)
	_step()
	_step(Intermission.MARKET_INPUT_LOCKOUT)


## Rolls [param n] trinkets for the two humans (both Pass) until the market opens.
func _roll_loot_until_market(a: UiFakes.HumanInput, b: UiFakes.HumanInput, n: int = 1) -> void:
	_loot(n)
	screen.open(1, 0)
	for k in n:
		_step()
		_step(LootRollScreen.ITEM_INPUT_DELAY)
		_tap(a, PlayerInput.Pad.B)
		_tap(b, PlayerInput.Pad.B)
		if k < n - 1:
			_step(LootRollScreen.RESULT_TIME + 0.01)
	_step(LootRollScreen.RESULT_TIME + 0.01)


# --- 1. A / X lockout -----------------------------------------------------------------

func test_a_and_x_are_ignored_right_after_the_market_opens() -> void:
	var inputs := _two_humans()
	var a := inputs[0]
	RunState.add_gold(5000)
	screen.open(1, 0)
	_step()
	var shop := RunState.shop
	var eq := ShopPanel.equipment_of(PlayerManager.get_slot(0))
	var gold := RunState.gold
	_tap(a, PlayerInput.Pad.A)
	_tap(a, PlayerInput.Pad.X)
	check_eq(RunState.gold, gold, "no purchase inside the lockout")
	check_eq(eq.backpack.size(), 0, "nothing bought")
	check(not shop.offers[0].is_locked(), "no lock inside the lockout")
	check(screen.shop_panel.is_input_locked(), "still locked")
	_step(Intermission.MARKET_INPUT_LOCKOUT)
	check(not screen.shop_panel.is_input_locked(), "the lockout ran out")
	_tap(a, PlayerInput.Pad.X)
	check(shop.offers[0].is_locked(), "X locks afterwards")
	_tap(a, PlayerInput.Pad.A)
	check(RunState.gold < gold, "A buys afterwards")
	check_eq(eq.backpack.size(), 1, "in the backpack")


func test_a_held_through_the_lockout_does_not_buy_when_it_ends() -> void:
	var a := _two_humans()[0]
	RunState.add_gold(5000)
	screen.open(1, 0)
	_step()
	var gold := RunState.gold
	a.press(PlayerInput.Pad.A)
	for i in 60:  # one second, well past the lockout
		_step()
	a.release(PlayerInput.Pad.A)
	_step()
	check_eq(RunState.gold, gold, "a press that started inside the lockout never buys")


func test_the_lockout_restarts_when_the_market_follows_the_loot_roll() -> void:
	var inputs := _two_humans()
	var a := inputs[0]
	RunState.add_gold(5000)
	_roll_loot_until_market(a, inputs[1])
	check_eq(screen.phase, Intermission.Phase.MARKET, "market")
	var gold := RunState.gold
	var eq := ShopPanel.equipment_of(PlayerManager.get_slot(0))
	var size := eq.backpack.size()
	# Somebody keeps mashing A as the roll ends: ~0.1 s of presses must not buy.
	for i in 3:
		_tap(a, PlayerInput.Pad.A)
	check_eq(RunState.gold, gold, "no Buy from the roll's last presses")
	check_eq(eq.backpack.size(), size, "nothing bought")
	_step(Intermission.MARKET_INPUT_LOCKOUT)
	_tap(a, PlayerInput.Pad.A)
	check(RunState.gold < gold, "Buy works after the lockout")


func test_the_lockout_does_not_run_down_during_the_loot_roll() -> void:
	var inputs := _two_humans()
	RunState.add_gold(5000)
	_loot(1)
	screen.open(1, 0)
	_step()
	_step(LootRollScreen.ITEM_INPUT_DELAY)
	_step(1.0)
	check_eq(screen.phase, Intermission.Phase.LOOT, "still rolling")
	_tap(inputs[0], PlayerInput.Pad.B)
	_tap(inputs[1], PlayerInput.Pad.B)
	_step(LootRollScreen.RESULT_TIME + 0.01)
	check_eq(screen.phase, Intermission.Phase.MARKET, "market")
	check(screen.shop_panel.is_input_locked(), "a fresh lockout at the start of the market")


# --- 2. Held stick -------------------------------------------------------------------

func test_a_stick_held_while_the_screen_opens_does_not_move_the_cursor() -> void:
	var a := _two_humans()[0]
	a.move = Vector2.RIGHT
	for i in 60:
		MarketFakes.poll_all(DT)  # gameplay frames with the stick held
	screen.open(1, 0)
	var start := screen.shop_panel.cursor_of(0)
	for i in 120:
		_step()
	check_eq(screen.shop_panel.cursor_of(0), start, "the held stick did not run the cursor")
	a.move = Vector2.ZERO
	_step()
	a.move = Vector2.RIGHT
	_step()
	check_eq(screen.shop_panel.cursor_of(0), start + 1, "after one neutral frame the stick navigates")


func test_a_stick_pushed_during_the_loot_roll_does_not_run_the_cursor_in_the_market() -> void:
	var inputs := _two_humans()
	var a := inputs[0]
	_loot(1)
	screen.open(1, 0)
	_step()
	_step(LootRollScreen.ITEM_INPUT_DELAY)
	_tap(a, PlayerInput.Pad.B)
	_tap(inputs[1], PlayerInput.Pad.B)
	a.move = Vector2.RIGHT  # steering while the result line shows
	_step(LootRollScreen.RESULT_TIME + 0.01)
	check_eq(screen.phase, Intermission.Phase.MARKET, "market")
	var start := screen.shop_panel.cursor_of(0)
	for i in 120:
		_step()
	check_eq(screen.shop_panel.cursor_of(0), start, "the stick held since the loot roll does not run the cursor")
	a.move = Vector2.ZERO
	_step()
	a.move = Vector2.RIGHT
	_step()
	check_eq(screen.shop_panel.cursor_of(0), start + 1, "after one neutral frame it navigates")


func test_opening_the_market_swallows_what_is_held() -> void:
	var a := _two_humans()[0]
	a.press(PlayerInput.Pad.A)
	a.move = Vector2.DOWN
	MarketFakes.poll_all(DT)
	check(a.just_pressed(PlayerInput.Pad.A) and a.nav_just_pressed() == Vector2i.DOWN, "fresh edges before the screen opens")
	screen.open(1, 0)
	check(not a.just_pressed(PlayerInput.Pad.A), "A: swallowed by open()")
	check_eq(a.nav_just_pressed(), Vector2i.ZERO, "no navigation edge either")
	check_eq(a.nav_held(), Vector2i.DOWN, "the stick is still held")


func test_the_loot_roll_swallows_what_is_held_when_it_opens() -> void:
	var a := _two_humans()[0]
	a.press(PlayerInput.Pad.A)
	MarketFakes.poll_all(DT)
	check(a.just_pressed(PlayerInput.Pad.A), "a fresh edge before the roll opens")
	_loot(1)
	screen.open(1, 0)
	check_eq(screen.phase, Intermission.Phase.LOOT, "loot roll")
	check(not a.just_pressed(PlayerInput.Pad.A), "swallowed when the roll opens")


func test_the_market_swallows_what_is_held_when_it_starts_after_the_loot() -> void:
	var inputs := _two_humans()
	_loot(1)
	screen.open(1, 0)
	_step()
	_step(LootRollScreen.ITEM_INPUT_DELAY)
	_tap(inputs[0], PlayerInput.Pad.B)
	_tap(inputs[1], PlayerInput.Pad.B)
	inputs[0].press(PlayerInput.Pad.A)
	inputs[0].move = Vector2.DOWN
	_step(LootRollScreen.RESULT_TIME + 0.01)  # the market starts in this frame
	check_eq(screen.phase, Intermission.Phase.MARKET, "market")
	check(not inputs[0].just_pressed(PlayerInput.Pad.A), "the A pressed as the roll ended is gone")
	check_eq(inputs[0].nav_just_pressed(), Vector2i.ZERO, "and the stick push")


# --- 3. Reroll votes -----------------------------------------------------------------

func test_shop_try_reroll_is_separate_from_vote_toggling() -> void:
	_two_humans()
	var shop := Shop.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	shop.open_round(1, PlayerManager.get_slots(), rng)
	var changes := [0]
	shop.changed.connect(func() -> void: changes[0] += 1)
	RunState.gold = 100
	var both: Array[int] = [0, 1]
	shop.reroll_votes[0] = true
	check(not shop.try_reroll(both, rng), "P2 has not voted")
	check_eq(changes[0], 0, "a failed try_reroll emits nothing (it runs every frame)")
	check_eq(shop.rerolls_this_round, 0, "no reroll")
	shop.reroll_votes[1] = true
	var cost := shop.reroll_cost()
	check(shop.try_reroll(both, rng), "everybody voted: rerolls")
	check_eq(shop.rerolls_this_round, 1, "counted")
	check_eq(RunState.gold, 100 - cost, "paid")
	check(shop.reroll_votes.is_empty(), "votes consumed")
	# vote_reroll still toggles and rerolls through try_reroll.
	check(not shop.vote_reroll(0, both, rng), "one vote of two")
	check(shop.reroll_votes.get(0, false), "voted")
	check(not shop.vote_reroll(0, both, rng), "toggled off")
	check(shop.reroll_votes.is_empty(), "unvoted")
	shop.vote_reroll(0, both, rng)
	check(shop.vote_reroll(1, both, rng), "the second vote completes it")
	check_eq(shop.rerolls_this_round, 2, "second reroll")


func test_shop_prune_votes_drops_non_voters() -> void:
	var shop := Shop.new()
	shop.reroll_votes = {0: true, 1: true, 3: true}
	var changes := [0]
	shop.changed.connect(func() -> void: changes[0] += 1)
	var joined: Array[int] = [0, 1]
	check(shop.prune_votes(joined), "dropped one")
	check_eq(shop.reroll_votes.keys(), [0, 1], "P4's vote is gone")
	check_eq(changes[0], 1, "changed once")
	check(not shop.prune_votes(joined), "nothing more to drop")
	check_eq(changes[0], 1, "and no signal")


func test_reroll_fires_when_the_last_missing_voter_unplugs() -> void:
	var inputs := _two_humans()
	var a := inputs[0]
	var b := inputs[1]
	RunState.add_gold(500)
	_open_market()
	var shop := RunState.shop
	var before := shop.rerolls_this_round
	_tap(a, PlayerInput.Pad.Y)
	check(shop.reroll_votes.get(0, false), "P1 voted")
	check_eq(shop.rerolls_this_round, before, "P2 is still missing")
	b.connected = false
	_step()
	check_eq(shop.rerolls_this_round, before + 1, "P2 unplugged: P1's vote now completes the reroll")
	check(shop.reroll_votes.is_empty(), "votes consumed")
	check("Rerolled" in " ".join(screen.shop_panel.feedback_lines()), "the stall says so")


func test_reroll_waits_for_gold_that_arrives_after_the_last_vote() -> void:
	var inputs := _two_humans()
	RunState.gold = 0
	_open_market(8)
	var shop := RunState.shop
	_tap(inputs[0], PlayerInput.Pad.Y)
	_tap(inputs[1], PlayerInput.Pad.Y)
	check_eq(shop.rerolls_this_round, 0, "no gold: no reroll")
	check_eq(shop.reroll_votes.size(), 2, "the votes stand")
	for i in 30:
		_step()
	check_eq(shop.rerolls_this_round, 0, "still waiting")
	RunState.add_gold(200)
	_step()
	check_eq(shop.rerolls_this_round, 1, "the gold arrived: the standing votes reroll")
	check(shop.reroll_votes.is_empty(), "consumed")


func test_votes_of_unplugged_players_are_dropped() -> void:
	var inputs := _two_humans()
	RunState.add_gold(500)
	_open_market()
	var shop := RunState.shop
	_tap(inputs[1], PlayerInput.Pad.Y)
	check(shop.reroll_votes.get(1, false), "P2 voted")
	inputs[1].connected = false
	_step()
	check(shop.reroll_votes.is_empty(), "the vote of the unplugged pad is dropped")
	check_eq(shop.rerolls_this_round, 0, "and P1 never voted")
	inputs[1].connected = true
	for i in 10:
		_step()
	check(shop.reroll_votes.is_empty(), "a replug does not bring it back")


func test_standing_votes_do_not_reroll_with_nothing_to_redraw() -> void:
	var inputs := _two_humans()
	RunState.add_gold(500)
	_open_market()
	var shop := RunState.shop
	for o in shop.offers:
		o.locked_by = 0
	_tap(inputs[0], PlayerInput.Pad.Y)
	_tap(inputs[1], PlayerInput.Pad.Y)
	var gold := RunState.gold
	for i in 30:
		_step()
	check_eq(shop.rerolls_this_round, 0, "every offer is locked: nothing changes")
	check_eq(RunState.gold, gold, "and nothing is charged")


# --- 4. Unplug / replug --------------------------------------------------------------

func test_a_replugged_player_is_not_ready() -> void:
	var inputs := _two_humans()
	_open_market()
	inputs[1].connected = false
	_step()
	check(PlayerManager.get_slot(1).ready, "unplugged: auto-ready")
	inputs[1].connected = true
	_step()
	check(not PlayerManager.get_slot(1).ready, "replugged: ready up again")
	_tap(inputs[0], PlayerInput.Pad.START)
	check_eq(continues, 0, "P1 alone does not continue")
	_tap(inputs[1], PlayerInput.Pad.START)
	check_eq(continues, 1, "both ready")


func test_a_pad_unplugged_from_the_start_comes_back_unready() -> void:
	var inputs := _two_humans()
	inputs[1].connected = false
	screen.open(1, 0)
	_step()
	_step(Intermission.MARKET_INPUT_LOCKOUT)
	check(PlayerManager.get_slot(1).ready, "unplugged at open: ready")
	inputs[1].connected = true
	_step()
	check(not PlayerManager.get_slot(1).ready, "back: not ready")


func test_bots_stay_ready_and_a_ready_human_stays_ready() -> void:
	var a := _two_humans()[0]
	MarketFakes.bot_with_hero(world, "bot:a", &"rogue")
	_open_market()
	_tap(a, PlayerInput.Pad.START)
	for i in 10:
		_step()
	check(PlayerManager.get_slot(0).ready, "a human who readied stays ready")
	check(PlayerManager.get_slot(2).ready, "the bot is ready")


# --- 5. Hold-to-buy -------------------------------------------------------------------

## The offer under P1's cursor made expensive: price 100 with 150 gold needs the hold.
func _arm_hold(price: int = 100, gold: int = 150) -> Shop.Offer:
	var o := RunState.shop.offers[screen.shop_panel.cursor_of(0)]
	o.price = price
	o.item.buy_price = price
	RunState.gold = gold
	return o


func test_a_hold_to_buy_does_not_survive_a_reroll() -> void:
	var inputs := _two_humans()
	var a := inputs[0]
	var b := inputs[1]
	_open_market()
	var shop := RunState.shop
	var sp := screen.shop_panel
	_tap(a, PlayerInput.Pad.Y)  # P1 votes first
	var idx := sp.cursor_of(0)
	var old := _arm_hold()
	var old_item := old.item
	a.press(PlayerInput.Pad.A)
	_step()
	for i in 20:
		_step()
	check(sp.hold_progress(0) > 0.0, "the hold is running")
	_tap(b, PlayerInput.Pad.Y)  # P2 completes the vote: the stall is rerolled under P1's finger
	check_eq(shop.rerolls_this_round, 1, "rerolled")
	check(shop.offers[idx].item != old_item, "a new item under the cursor")
	check_eq(sp.hold_progress(0), 0.0, "the hold is cancelled")
	var new_offer := shop.offers[idx]
	var gold := RunState.gold
	for i in 90:  # A is still held way past HOLD_TIME
		_step()
	a.release(PlayerInput.Pad.A)
	_step()
	check_eq(RunState.gold, gold, "nothing was bought")
	check(not new_offer.sold, "the new item is still on offer")
	check_eq(ShopPanel.equipment_of(PlayerManager.get_slot(0)).backpack.size(), 0, "backpack untouched")


func test_a_hold_to_buy_is_cancelled_when_the_offer_changes() -> void:
	var a := _two_humans()[0]
	_open_market()
	var shop := RunState.shop
	var sp := screen.shop_panel
	var idx := sp.cursor_of(0)
	var o := _arm_hold()
	a.press(PlayerInput.Pad.A)
	for i in 10:
		_step()
	check(sp.hold_progress(0) > 0.0, "holding")
	# Another item takes the place without any signal (the hold re-checks the item itself).
	var other := Shop.Offer.new()
	other.item = MarketFakes.make_item("Swapped Band", Items.SlotType.RING)
	other.price = 100
	shop.offers[idx] = other
	_step()
	check_eq(sp.hold_progress(0), 0.0, "a different item: hold cancelled")
	for i in 90:
		_step()
	check(not other.sold, "the swapped item was not bought")
	a.release(PlayerInput.Pad.A)
	_step()
	# A price change under the finger cancels it too.
	shop.offers[idx] = o
	o.price = 100
	a.press(PlayerInput.Pad.A)
	_step()
	for i in 10:
		_step()
	check(sp.hold_progress(0) > 0.0, "holding again")
	o.price = 40
	_step()
	check_eq(sp.hold_progress(0), 0.0, "a different price: hold cancelled")
	a.release(PlayerInput.Pad.A)
	_step()


func test_an_unaffected_hold_still_buys() -> void:
	var a := _two_humans()[0]
	_open_market()
	var sp := screen.shop_panel
	var o := _arm_hold()
	var item := o.item
	a.press(PlayerInput.Pad.A)
	for i in int(ShopPanel.HOLD_TIME * 60.0) + 10:
		_step()
	a.release(PlayerInput.Pad.A)
	_step()
	check(o.sold, "the held purchase went through")
	check_eq(RunState.gold, 50, "paid the price")
	check(item in ShopPanel.equipment_of(PlayerManager.get_slot(0)).backpack, "in the backpack")
	check_eq(sp.hold_progress(0), 0.0, "hold over")


func test_b_cancels_a_hold_without_unreadying() -> void:
	var a := _two_humans()[0]
	_open_market()
	var sp := screen.shop_panel
	var slot := PlayerManager.get_slot(0)
	_arm_hold()
	_tap(a, PlayerInput.Pad.START)
	check(slot.ready, "ready")
	a.press(PlayerInput.Pad.A)
	for i in 10:
		_step()
	check(sp.hold_progress(0) > 0.0, "holding")
	_tap(a, PlayerInput.Pad.B)
	check_eq(sp.hold_progress(0), 0.0, "B cancelled the hold")
	check(slot.ready, "and did not also unready")
	a.release(PlayerInput.Pad.A)
	_step()
	_tap(a, PlayerInput.Pad.B)
	check(not slot.ready, "the next B unreadies as before")


# --- 6. Y during the result line --------------------------------------------------------

func _start_three_item_roll() -> Array[UiFakes.HumanInput]:
	var inputs := _two_humans()
	_loot(3)
	screen.open(1, 0)
	_step()
	_step(LootRollScreen.ITEM_INPUT_DELAY)
	return inputs


func test_y_during_the_result_line_sets_greed_all() -> void:
	var inputs := _start_three_item_roll()
	var ls := screen.loot_screen
	_tap(inputs[0], PlayerInput.Pad.X)
	_tap(inputs[1], PlayerInput.Pad.B)
	check_eq(ls.phase, LootRollScreen.Phase.RESULT, "the result line shows")
	_step(0.3)
	_tap(inputs[0], PlayerInput.Pad.Y)
	check(ls.greed_all.get(0, false), "Y during the result counts")
	check(not ls.greed_all.get(1, false), "only for P1")
	check("P1 will greed all remaining items" in ls.log_lines(), "and says so")
	_step(LootRollScreen.RESULT_TIME)
	check_eq(ls.phase, LootRollScreen.Phase.CHOOSING, "the next item")
	check_eq(ls.current, 1, "second item")
	check_eq(ls.choice_of(0), LootRoll.Choice.GREED, "P1's Greed is already in")
	check_eq(ls.choice_of(1), LootRoll.Choice.UNDECIDED, "P2 still decides")


func test_y_in_the_first_moments_of_an_item_counts() -> void:
	var inputs := _start_three_item_roll()
	var ls := screen.loot_screen
	_tap(inputs[0], PlayerInput.Pad.B)
	_tap(inputs[1], PlayerInput.Pad.B)
	_step(LootRollScreen.RESULT_TIME + 0.01)
	check_eq(ls.current, 1, "second item")
	_tap(inputs[1], PlayerInput.Pad.A)  # inside ITEM_INPUT_DELAY: not taken as a choice
	check_eq(ls.choice_of(1), LootRoll.Choice.UNDECIDED, "an A that early is ignored as before")
	_tap(inputs[1], PlayerInput.Pad.Y)
	check(ls.greed_all.get(1, false), "Y is remembered")
	check_eq(ls.choice_of(1), LootRoll.Choice.GREED, "and greeds this item")


func test_y_after_the_last_item_changes_nothing() -> void:
	var inputs := _two_humans()
	_loot(1)
	screen.open(1, 0)
	_step()
	_step(LootRollScreen.ITEM_INPUT_DELAY)
	_tap(inputs[0], PlayerInput.Pad.B)
	_tap(inputs[1], PlayerInput.Pad.B)
	var ls := screen.loot_screen
	check_eq(ls.phase, LootRollScreen.Phase.RESULT, "last result")
	_tap(inputs[0], PlayerInput.Pad.Y)
	check(ls.greed_all.is_empty(), "nothing left to greed")


# --- 7. A player leaves ---------------------------------------------------------------

## What Main.drop_player does to a slot.
func _drop_player(index: int, input: UiFakes.HumanInput) -> void:
	var slot := PlayerManager.get_slot(index)
	input.connected = false
	var hero := slot.player as Node
	slot.player = null
	if hero != null:
		hero.free()
	PlayerManager.leave(index)


func test_a_player_leaving_updates_the_open_market() -> void:
	var inputs := _two_humans()
	_open_market()
	check(screen.panels.has(1), "P2's panel")
	check_eq(screen.chips_row.get_child_count(), 2, "two chips")
	_drop_player(1, inputs[1])
	check(not screen.panels.has(1), "the panel is gone")
	check(screen.panels.has(0), "P1's stays")
	check_eq(screen.shop_panel.cursor_of(1), -1, "no shop cursor")
	check(screen.shop_panel.tooltip_of(1) == null, "no tooltip")
	check_eq(screen.chips_row.get_child_count(), 1, "one chip")
	for i in 5:
		_step()
	check_eq(continues, 0, "P1 still has to ready")
	_tap(inputs[0], PlayerInput.Pad.START)
	check_eq(continues, 1, "the one who stayed decides")


func test_a_leaving_voter_takes_their_vote_along() -> void:
	var inputs := _two_humans()
	RunState.add_gold(500)
	_open_market()
	var shop := RunState.shop
	_tap(inputs[1], PlayerInput.Pad.Y)
	check(shop.reroll_votes.get(1, false), "P2 voted")
	_drop_player(1, inputs[1])
	check(shop.reroll_votes.is_empty(), "P2's vote left with P2")
	for i in 5:
		_step()
	check_eq(shop.rerolls_this_round, 0, "P1 never voted: no reroll")


func test_the_remaining_voter_completes_a_reroll_after_the_other_left() -> void:
	var inputs := _two_humans()
	RunState.add_gold(500)
	_open_market()
	var shop := RunState.shop
	_tap(inputs[0], PlayerInput.Pad.Y)
	check_eq(shop.rerolls_this_round, 0, "waiting for P2")
	_drop_player(1, inputs[1])
	_step()
	check_eq(shop.rerolls_this_round, 1, "P1 was the only voter left")


func test_a_player_leaving_during_a_hold_does_not_leave_a_ring() -> void:
	var inputs := _two_humans()
	_open_market()
	var sp := screen.shop_panel
	_arm_hold()
	inputs[0].press(PlayerInput.Pad.A)
	for i in 10:
		_step()
	check(sp.hold_progress(0) > 0.0, "P1 holds")
	_drop_player(0, inputs[0])
	_step()
	check_eq(sp.hold_progress(0), 0.0, "the leaver's hold is gone")


func test_an_unplugged_pad_has_no_cursor_and_no_tooltip() -> void:
	var inputs := _two_humans()
	_open_market()
	var sp := screen.shop_panel
	sp._process(DT)
	check(sp.tooltip_of(0).visible and sp.tooltip_of(1).visible, "both players' tooltips show")
	check(not ShopPanel.is_unplugged(PlayerManager.get_slot(1)), "plugged in")
	inputs[1].connected = false
	_step()
	sp._process(DT)
	check(ShopPanel.is_unplugged(PlayerManager.get_slot(1)), "unplugged")
	check(not sp.tooltip_of(1).visible, "the unplugged player's tooltip is hidden")
	check(sp.tooltip_of(0).visible, "the others' stay")
	inputs[1].connected = true
	_step()
	sp._process(DT)
	check(sp.tooltip_of(1).visible, "back with the pad")
	var bot := MarketFakes.bot_with_hero(world, "bot:z", &"rogue")
	check(not ShopPanel.is_unplugged(bot), "a bot is never 'unplugged'")
