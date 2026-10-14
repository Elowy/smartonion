extends TestCase
## The shared purse (GDD 10 "Coordination tools", M5 PURSE): the PurseBoard in the Intermission
## header – the shared gold, the ready pips, this round's spend ticker (every spender, newest
## first, at most two lines, "+N more"), the wants line merging shop pings and Trainer pings –
## a new round clearing it, the "★N" talent badge on the ready chips, the hold rule cross-check
## (shop and Trainer hold above half the wallet, rerolls never), simultaneous buys (slot order:
## the lower index wins, the other reads "Not enough gold", one log entry) and the header /
## footer layout (nothing overlaps the stall or the corner panels at 1920 x 1080).
## Trainer pings themselves (R3 on a row) are tested in test_ui_trainer.gd.

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0
## Layout: the merchant's top hat pokes this far above the stall's rect (ShopMerchant: head
## centre AWNING_BOTTOM - 12, crown 66 above it, a 1.5 px bob) and the clearance kept to it.
const HAT_RISE := 14.5
const CLEARANCE := 3.0

var world: Node3D
var screen: Intermission
var holder: Control
var _async := false


func is_async() -> bool:
	return _async


func before_each() -> void:
	_async = false
	UiFakes.reset_players()
	RunState.start_run(2, 11)
	world = MarketFakes.make_world(tree)
	screen = Intermission.create()
	tree.root.add_child(screen)


func after_each() -> void:
	Intermission.auto_continue_time = Intermission.AUTO_CONTINUE_TIME
	UiFakes.free_node(screen)
	UiFakes.free_node(holder)
	UiFakes.free_node(world)
	screen = null
	holder = null
	world = null
	RunState.start_run(1, 1)
	UiFakes.reset_players()


# --- Helpers ---------------------------------------------------------------------------------

func _step(delta: float = DT) -> void:
	MarketFakes.poll_all(delta)
	screen._process(delta)


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


## Opens the market and gets past the opening frame and the A / X lockout.
func _open_market(wave: int = 3) -> void:
	screen.open(wave, 0)
	_step()
	_step(Intermission.MARKET_INPUT_LOCKOUT)


## Replaces the real stall's offers with [param items] at [param prices] (after the round opened).
func _stock(items: Array[ItemInstance], prices: Array[int]) -> void:
	var shop := RunState.shop
	shop.offers.clear()
	for i in items.size():
		var o := Shop.Offer.new()
		o.item = items[i]
		o.price = prices[i]
		o.item.buy_price = prices[i]
		shop.offers.append(o)
	shop.changed.emit()


static func _ring(display_name: String, rarity: int = Items.Rarity.RARE) -> ItemInstance:
	return MarketFakes.make_item(display_name, Items.SlotType.RING, Items.NO_ARMOR, rarity)


func _board() -> PurseBoard:
	return screen.purse_board


func _entry(slot: int, kind: StringName, label: String, amount: int) -> Dictionary:
	return {"slot": slot, "kind": kind, "label": label, "amount": amount, "wave": RunState.wave}


# --- The wallet and an empty round -----------------------------------------------------------

func test_board_shows_the_wallet_and_an_empty_round() -> void:
	_two_humans()
	RunState.add_gold(1234)
	_open_market()
	var board := _board()
	check(board != null and board.get_parent() == screen.header, "the purse board sits in the header")
	check(screen.gold_value == board.gold_value, "the header's gold is the board's")
	check_eq(board.gold_value.text, "1,234", "the shared gold")
	check_eq(board.ticker_lines(), [PurseBoard.EMPTY_TICKER] as Array[String], "nothing spent yet")
	check_eq(board.wants_text(), "", "no wants")
	check(PurseBoard.EMPTY_WANTS in board.wants_label.text, "the wants line explains the ping")
	RunState.add_gold(6)
	check_eq(board.gold_value.text, "1,240", "the gold follows the wallet")


# --- The spend ticker ------------------------------------------------------------------------

func test_every_spend_kind_reads_who_what_how_much() -> void:
	check_eq(PurseBoard.entry_text(_entry(0, &"shop", "Rare Dagger", 62)), "P1 [Rare Dagger] 62", "shop buy")
	check_eq(PurseBoard.entry_text(_entry(1, &"shop_forge", "Rare Dagger (forged)", 62)), "P2 [Rare Dagger] (forged) 62", "auto-forge")
	check_eq(PurseBoard.entry_text(_entry(-1, &"shop_reroll", "Stall reroll", 12)), "Team Stall reroll 12", "stall reroll: the team")
	check_eq(PurseBoard.entry_text(_entry(1, &"trainer", "Fireball Rank III", 45)), "P2 Fireball Rank III 45", "Trainer rank")
	check_eq(PurseBoard.entry_text(_entry(2, &"level_reroll", "Level-up reroll", 10)), "P3 Level-up reroll 10", "level-up reroll")
	check_eq(PurseBoard.entry_text(_entry(3, &"talent_reset", "Reset Talents", 1280)), "P4 Reset Talents 1,280", "talent reset")


func test_the_ticker_logs_the_real_spenders_newest_first() -> void:
	_two_humans()
	RunState.add_gold(5000)
	_open_market(4)
	var board := _board()
	var shop := RunState.shop
	var items: Array[ItemInstance] = [_ring("Opal Ring"), _ring("Jade Band"), _ring("Iron Loop")]
	_stock(items, [30, 40, 50] as Array[int])
	var p1 := PlayerManager.get_slot(0)
	var p2 := PlayerManager.get_slot(1)
	# Shop buy (P1), stall reroll (the team), Trainer rank (P2), talent reset (P1), level-up
	# reroll (P2) – each through its real spender.
	check(screen.shop_panel.try_buy(p1, 0), "P1 buys the Opal Ring")
	check(not shop.vote_reroll(0, [0, 1] as Array[int], RunState.rng), "P1 votes")
	var reroll_cost := shop.reroll_cost()
	check(shop.vote_reroll(1, [0, 1] as Array[int], RunState.rng), "P2's vote rerolls")
	var mage := p2.player as Player
	var core := mage.abilities.slots[0]
	var rank_price := mage.abilities.trainer_price(core.id)
	check(Trainer.try_buy_rank(mage, core.id), "P2 trains")
	var warrior := p1.player as Player
	warrior.talents.ranks[&"zz_purse_talent"] = 2
	check(warrior.talents.try_reset(p1.index), "P1 resets talents")
	var level_panel := LevelUpPanel.create(p2)
	level_panel.begin(1, 2, 4, RunState.rng)
	var reroll_price := level_panel.reroll_price()
	check(level_panel.try_reroll(), "P2 rerolls the level-up cards")
	level_panel.free()
	check_eq(RunState.spend_log.size(), 5, "five spends logged")
	check(board.is_dirty(), "the spends marked the board")
	_step()
	check(not board.is_dirty(), "rebuilt in the MARKET frame")
	var expected: Array[String] = [
		"P2 Level-up reroll %d" % reroll_price,
		"P1 Reset Talents 20",
		"P2 %s Rank II %d" % [core.display_name, rank_price],
		"Team Stall reroll %d" % reroll_cost,
		"P1 [Opal Ring] 30",
	]
	var shown := PurseBoard.SEPARATOR.join(board.ticker_lines())
	check_eq(shown, " · ".join(expected), "newest first, every spender")
	check(board.ticker_labels[1].text.contains("#%s" % ShopOfferCard.rarity_color(items[0]).to_html(false)),
		"the bought item in its rarity colour: %s" % board.ticker_labels[1].text)
	check(board.ticker_labels[0].text.contains("#%s" % p2.color.lightened(0.25).to_html(false)), "P2 in their colour")


func test_the_ticker_packs_two_lines_and_sums_up_the_rest() -> void:
	_two_humans()
	_open_market()
	var board := _board()
	for i in 12:
		RunState.spend_log.append(_entry(i % 2, &"trainer", "Fireball Rank III", 45))
	RunState.spend_log.append(_entry(0, &"trainer", "Frost Nova Rank V", 300))
	board.refresh()
	var lines := board.ticker_lines()
	check_eq(lines.size(), PurseBoard.TICKER_LINES, "two lines")
	check(lines[0].begins_with("P1 Frost Nova Rank V 300"), "the newest entry first: %s" % lines[0])
	var shown := 0
	for l in lines:
		check(board.text_width(l) <= PurseBoard.line_width() + 0.5, "the line fits the board: %s" % l)
		shown += l.split(PurseBoard.SEPARATOR).size()
	shown -= 1  # the "+N more" tag
	check(lines[1].ends_with(PurseBoard.more_text(13 - shown)), "the rest summed up: %s (%d shown)" % [lines[1], shown])
	check(shown >= 4, "the lines are used: %d entries shown" % shown)
	# A short round fits without a summary.
	screen.open(4, 0)
	RunState.spend_log.append(_entry(0, &"shop", "Opal Ring", 30))
	RunState.spend_log.append(_entry(-1, &"shop_reroll", "Stall reroll", 10))
	board.refresh()
	check_eq(board.ticker_lines(), ["Team Stall reroll 10 · P1 [Opal Ring] 30"] as Array[String], "one line, no +N more")


func test_pack_fills_lines_and_takes_back_room_for_the_summary() -> void:
	var more := func(_n: int) -> float: return 50.0
	var five: Array[float] = [100.0, 100.0, 100.0, 100.0, 100.0]
	check_eq(PurseBoard.pack(five, 10.0, more, 330.0, 2), [3, 2] as Array[int], "3 + 2 fit")
	var seven: Array[float] = [100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0]
	check_eq(PurseBoard.pack(seven, 10.0, more, 330.0, 2), [3, 2] as Array[int], "the last line gives one back for +2 more")
	var huge: Array[float] = [500.0, 50.0]
	check_eq(PurseBoard.pack(huge, 10.0, more, 330.0, 2), [1, 1] as Array[int], "an oversized entry gets its own line")
	var two: Array[float] = [100.0, 100.0]
	check_eq(PurseBoard.pack(two, 10.0, more, 150.0, 1), [0] as Array[int], "only the summary fits")
	check_eq(PurseBoard.pack([] as Array[float], 10.0, more, 330.0, 2), [] as Array[int], "nothing to pack")


func test_a_new_round_clears_the_ticker_and_the_wants() -> void:
	_two_humans()
	RunState.add_gold(500)
	_open_market()
	RunState.try_spend_for(25, 0, &"trainer", "Charge Rank II")
	RunState.toggle_want(1, "trainer:fireball", "Fireball Rank II", 25)
	_step()
	check_eq(_board().ticker_lines(), ["P1 Charge Rank II 25"] as Array[String], "logged")
	check_eq(_board().wants_text(), "P2 Fireball Rank II 25 g", "wanted")
	screen.open(4, 0)
	check_eq(_board().ticker_lines(), [PurseBoard.EMPTY_TICKER] as Array[String], "a new round starts empty")
	check_eq(_board().wants_text(), "", "and without wants")


# --- Wants -----------------------------------------------------------------------------------

func test_wants_merge_shop_and_trainer_pings_in_slot_order() -> void:
	_two_humans()
	RunState.add_gold(500)
	_open_market()
	var shop := RunState.shop
	var items: Array[ItemInstance] = [_ring("Runed Signet", Items.Rarity.EPIC), _ring("Silk Band", Items.Rarity.UNCOMMON)]
	_stock(items, [62, 30] as Array[int])
	shop.toggle_ping(0, 1)
	shop.toggle_ping(1, 0)
	RunState.toggle_want(0, "trainer:charge", "Charge Rank II", 25)
	_step()
	check_eq(_board().wants_text(), "P1 [Silk Band] 30 g · P1 Charge Rank II 25 g · P2 [Runed Signet] 62 g",
		"per player: shop pings, then Trainer pings")
	check(_board().wants_label.text.contains("#%s" % ShopOfferCard.rarity_color(items[0]).to_html(false)), "the Epic in its colour")
	# Buying a pinged offer clears its ping (Shop.try_buy) and so its want.
	check(screen.shop_panel.try_buy(PlayerManager.get_slot(1), 0), "P2 buys what P2 wanted")
	_step()
	check_eq(_board().wants_text(), "P1 [Silk Band] 30 g · P1 Charge Rank II 25 g", "bought: gone")
	# A player who leaves takes their Trainer pings along.
	PlayerManager.leave(0)
	_step()
	check(not RunState.has_want(0, "trainer:charge"), "P1's Trainer ping is cleared")
	check_eq(_board().wants_text(), "", "P1's wants are off the board")


func test_a_player_who_leaves_takes_their_shop_pings_along() -> void:
	_two_humans()
	RunState.add_gold(500)
	_open_market()
	var shop := RunState.shop
	var items: Array[ItemInstance] = [_ring("Runed Signet", Items.Rarity.EPIC), _ring("Silk Band")]
	_stock(items, [62, 30] as Array[int])
	shop.toggle_ping(0, 1)
	_step()
	check_eq(_board().wants_text(), "P2 [Runed Signet] 62 g", "P2 wants the signet")
	check(RunState.wants.is_empty(), "a shop ping only, no Trainer ping")
	check(0 not in shop.rerollable_positions(), "the pinged offer is kept out of a reroll")
	PlayerManager.leave(1)
	_step()
	_step()
	check_eq(_board().wants_text(), "", "P2's shop ping is off the board")
	check(not _board().is_dirty(), "rebuilt")
	check(shop.offers[0].pinged_by.is_empty(), "and off the offer (no 'P2 wants' left on the card)")
	check(0 in shop.rerollable_positions(), "a reroll may take it again")


func test_the_board_drops_the_wants_of_a_player_who_left() -> void:
	# The board on its own, with a stall nobody prunes: the change in the players rebuilds the
	# wants line although neither the wallet nor the stall signalled anything.
	_two_humans()
	holder = Control.new()
	tree.root.add_child(holder)
	var board := PurseBoard.create()
	holder.add_child(board)
	var stall := Shop.new()
	var o := Shop.Offer.new()
	o.item = _ring("Runed Signet", Items.Rarity.EPIC)
	o.price = 62
	o.pinged_by.append(1)
	stall.offers.append(o)
	board.set_shop(stall)
	board.update(PlayerManager.get_slots())
	check_eq(board.wants_text(), "P2 [Runed Signet] 62 g", "P2's ping")
	PlayerManager.leave(1)
	board.update(PlayerManager.get_slots())
	check_eq(board.wants_text(), "", "P2 left: off the line")
	check(not board.is_dirty(), "rebuilt by update()")
	check_eq(o.pinged_by, [1] as Array[int], "with the ping still stored (no signal)")


## Shown entries of [param lines] (plain board lines) and the "+N more" count at the end.
static func _shown_and_more(lines: Array[String]) -> Array[int]:
	var shown := 0
	for l in lines:
		shown += l.split(PurseBoard.SEPARATOR).size()
	var more := 0
	var last := lines[-1].split(PurseBoard.SEPARATOR)
	if last[-1].begins_with("+") and last[-1].ends_with(" more"):
		more = last[-1].trim_prefix("+").trim_suffix(" more").to_int()
		shown -= 1
	return [shown, more]


func test_many_wants_fit_their_lines() -> void:
	_two_humans()
	_open_market()
	var board := _board()
	for i in 9:
		RunState.toggle_want(i % 2, "trainer:x%d" % i, "Arcane Missiles Rank IV", 120)
	_step()
	# Nothing spent: the ticker needs one line, so the wants take the second one too.
	check_eq(board.ticker_lines(), [PurseBoard.EMPTY_TICKER] as Array[String], "an empty round")
	var lines := board.wants_lines()
	check_eq(lines.size(), 2, "the wants use the ticker's free line: %s" % [lines])
	for l in lines:
		check(board.text_width(l) <= PurseBoard.line_width() + 0.5, "fits the line: %s" % l)
	var counts := _shown_and_more(lines)
	check_eq(counts[0] + counts[1], 9, "every want shown or in +N more: %s" % [lines])
	check(counts[0] >= 3, "more than one line's worth shown: %d" % counts[0])
	check_eq(board.wants_text(), PurseBoard.SEPARATOR.join(lines), "wants_text joins the lines")
	check(board.row_labels[1].text.contains("Arcane Missiles Rank IV"), "the second row holds wants")
	check(board.wants_label.text.contains(PurseBoard.more_text(counts[1])), "the bottom row ends in +N more")
	check_eq([board.caption_labels[0].text, board.caption_labels[1].text, board.caption_labels[2].text],
		["Spent", "Wants", ""], "the Wants caption moved up a row")
	# A two-line ticker: the wants are back to one line on the bottom row.
	for i in 13:
		RunState.spend_log.append(_entry(i % 2, &"trainer", "Fireball Rank III", 45))
	board.refresh()
	check_eq(board.ticker_lines().size(), PurseBoard.TICKER_LINES, "the ticker takes two lines")
	lines = board.wants_lines()
	check_eq(lines.size(), 1, "one wants line")
	check(board.text_width(lines[0]) <= PurseBoard.line_width() + 0.5, "it fits")
	counts = _shown_and_more(lines)
	check_eq(counts[0] + counts[1], 9, "the rest summed up: %s" % lines[0])
	check(board.row_labels[1].text.contains("Fireball Rank III"), "row 2 is the ticker's again")
	check_eq([board.caption_labels[0].text, board.caption_labels[1].text, board.caption_labels[2].text],
		["Spent", "", "Wants"], "the Wants caption on the bottom row")
	# Few wants and an empty round: they stay on the bottom row, the second row stays empty.
	RunState.spend_log.clear()
	RunState.wants.clear()
	RunState.toggle_want(0, "trainer:y", "Charge Rank II", 25)
	board.refresh()
	check_eq(board.wants_lines(), ["P1 Charge Rank II 25 g"] as Array[String], "one short want")
	check(board.row_labels[1].text == "" and board.wants_label.text.contains("Charge Rank II"), "on the bottom row")
	check_eq(board.caption_labels[2].text, "Wants", "with its caption")


# --- Ready pips ------------------------------------------------------------------------------

func test_update_tells_ready_changes_from_player_changes() -> void:
	_two_humans()
	holder = Control.new()
	tree.root.add_child(holder)
	var board := PurseBoard.create()
	holder.add_child(board)
	var slots := PlayerManager.get_slots()
	board.update(slots)
	check(not board.is_dirty(), "the first update builds the texts")
	check_eq(board.ready_label.text, "0/2 ready", "two players")
	board.update(slots)
	check(not board.is_dirty(), "nothing changed: nothing to rebuild")
	slots[1].ready = true
	board.update(slots)
	check(board.pips.states[1]["ready"] and board.ready_label.text == "1/2 ready", "a ready toggle redraws the pips")
	board._dirty = false
	slots[1].ready = false
	board.update(slots)
	check(not board.pips.states[1]["ready"], "and back")
	check(not board.is_dirty(), "the texts do not depend on ready flags")
	RunState.toggle_want(0, "trainer:z", "Charge Rank II", 25)
	board.update(slots)
	var old_color := slots[0].color
	check(board.wants_label.text.contains(old_color.lightened(0.25).to_html(false)), "P1's tag in their colour")
	var green := Color(0.1, 0.9, 0.2)
	slots[0].color = green
	board.update(slots)
	check_eq(board.pips.states[0]["color"], green, "a colour change reaches the pips")
	check(board.wants_label.text.contains(green.lightened(0.25).to_html(false)), "and rebuilt the texts (the tags carry the colours)")
	slots[0].color = old_color
	var fewer: Array[PlayerSlot] = [slots[0]]
	board.update(fewer)
	check_eq(board.pips.states.size(), 1, "a player left: one pip")
	check_eq(board.ready_label.text, "0/1 ready", "count follows")

func test_ready_pips_follow_the_players() -> void:
	var inputs := _two_humans()
	MarketFakes.bot_with_hero(world, "bot:2", &"paladin")
	_open_market()
	var board := _board()
	check_eq(board.pips.states.size(), 3, "one pip per player")
	check_eq(board.pips.states[0]["color"], PlayerManager.get_slot(0).color, "in the player's colour")
	check(not board.pips.states[0]["ready"] and not board.pips.states[1]["ready"], "humans not ready")
	check(board.pips.states[2]["ready"], "the bot is ready")
	check_eq(board.ready_label.text, "1/3 ready", "count")
	_tap(inputs[0], PlayerInput.Pad.START)
	check(board.pips.states[0]["ready"], "P1 readied: filled")
	check_eq(board.ready_label.text, "2/3 ready", "count follows")
	_tap(inputs[0], PlayerInput.Pad.B)
	check(not board.pips.states[0]["ready"], "B unreadies: hollow again")


# --- Talent badge on the chips ----------------------------------------------------------------

func _badge(slot_index: int) -> Intermission.TalentBadge:
	var chip := screen._chips.get(slot_index) as PanelContainer
	if chip == null:
		return null
	var found := chip.find_children("TalentBadge", "", true, false)
	return found[0] as Intermission.TalentBadge if not found.is_empty() else null


func test_ready_chips_show_unspent_talent_points() -> void:
	_two_humans()
	RunState.set_start_level(9)
	_open_market()
	check(_badge(0) == null, "level 9: no talent points, no badge")
	RunState.set_start_level(12)
	_step()
	var badge := _badge(0)
	check(badge != null, "level 12: a badge")
	check_eq(badge.text() if badge != null else "", "★3", "three points to spend")
	check(badge != null and badge.get_parent() is UiPortrait, "on the portrait (the chip keeps its size)")
	var warrior := PlayerManager.get_slot(0).player as Player
	warrior.talents.ranks[&"zz_purse_talent"] = 3
	_step()
	check(_badge(0) == null, "every point spent: the badge goes")
	check_eq(_badge(1).text() if _badge(1) != null else "", "★3", "P2 still has three")
	check_eq(Intermission.talent_points_free(null), 0, "no slot: no points")


# --- Hold rule and simultaneous buys ---------------------------------------------------------

func test_shop_and_trainer_share_the_hold_rule_and_rerolls_never_hold() -> void:
	check_eq(TrainerTab.HOLD_TIME, ShopPanel.HOLD_TIME, "same hold time")
	check_eq(TrainerTab.HOLD_SHARE, ShopPanel.HOLD_SHARE, "same share")
	check_eq(TalentTab.HOLD_TIME, ShopPanel.HOLD_TIME, "talent reset: same hold time")
	check_eq(TalentTab.HOLD_SHARE, ShopPanel.HOLD_SHARE, "talent reset: same share")
	check_eq(ShopPanel.HOLD_SHARE, 0.5, "GDD 10: more than half the wallet")
	for gold: int in [0, 10, 99, 100, 1001]:
		RunState.gold = gold
		for price: int in [1, gold / 2, gold / 2 + 1, gold]:
			var expect := price > gold * 0.5
			check_eq(screen.shop_panel.needs_hold(price), expect, "shop: %d of %d" % [price, gold])
			check_eq(TrainerTab.needs_hold(price), expect, "Trainer: %d of %d" % [price, gold])
			check_eq(TalentTab.needs_hold(price), expect, "talent reset: %d of %d" % [price, gold])
	# The stall reroll: the last vote pays at once, even all of the wallet.
	var inputs := _two_humans()
	RunState.gold = 0
	_open_market(2)
	var cost := RunState.shop.reroll_cost()
	RunState.add_gold(cost)
	_tap(inputs[0], PlayerInput.Pad.Y)
	_tap(inputs[1], PlayerInput.Pad.Y)
	check_eq(RunState.gold, 0, "a reroll takes the whole wallet without a hold")
	check_eq(RunState.spend_log.size(), 1, "logged")
	# The level-up reroll: one press, all of the wallet.
	var panel := LevelUpPanel.create(PlayerManager.get_slot(0))
	panel.begin(1, 2, 2, RunState.rng)
	RunState.add_gold(panel.reroll_price())
	panel.input_delay = 0.0
	var input := inputs[0]
	input.press(PlayerInput.Pad.Y)
	input.poll(DT)
	panel.handle_input(input)
	input.release(PlayerInput.Pad.Y)
	check_eq(RunState.gold, 0, "a level-up reroll never holds")
	panel.free()


func test_simultaneous_buys_go_in_slot_order() -> void:
	var inputs := _two_humans()
	RunState.add_gold(100)
	_open_market()
	var items: Array[ItemInstance] = [_ring("Opal Ring"), _ring("Jade Band")]
	_stock(items, [60, 60] as Array[int])
	# Gold for one: each price is more than half the wallet, so both hold A – and both holds end
	# in the same frame. P2 aims at the first offer, P1 at the second: slot order, not offers.
	screen.shop_panel.set_cursor(0, 1)
	screen.shop_panel.set_cursor(1, 0)
	inputs[0].press(PlayerInput.Pad.A)
	inputs[1].press(PlayerInput.Pad.A)
	for i in int(ceilf(ShopPanel.HOLD_TIME / DT)) + 2:
		_step()
	inputs[0].release(PlayerInput.Pad.A)
	inputs[1].release(PlayerInput.Pad.A)
	_step()
	check(RunState.shop.offers[1].sold, "P1 got the Jade Band")
	check(not RunState.shop.offers[0].sold, "P2's Opal Ring is still for sale")
	check_eq(RunState.gold, 40, "one purchase paid")
	check_eq(RunState.spend_log.size(), 1, "one log entry")
	check_eq(int(RunState.spend_log[0]["slot"]), 0, "P1's")
	check(screen.shop_panel.feedback_lines().has("P2: Not enough gold"), "P2 reads why: %s" % [screen.shop_panel.feedback_lines()])
	check_eq(ShopPanel.equipment_of(PlayerManager.get_slot(1)).backpack.size(), 0, "P2 got nothing")
	check_eq(_board().ticker_lines(), ["P1 [Jade Band] 60"] as Array[String], "the board shows the one buy")


# --- Layout ----------------------------------------------------------------------------------

## The header (title, summary, purse board) and the ready chips stay clear of the stall (and its
## merchant's hat) and of the corner panels at the 1920 x 1080 design size – with four players,
## full lines and talent badges. 1280 x 720 is the same canvas scaled (stretch mode
## canvas_items).
func test_header_and_chips_clear_the_stall_and_the_panels() -> void:
	_async = true
	UiFakes.free_node(screen)
	holder = Control.new()
	holder.size = Vector2(1920, 1080)
	tree.root.add_child(holder)
	screen = Intermission.create()
	holder.add_child(screen)
	for i in 4:
		MarketFakes.human_with_hero(world, "pad:%d" % i, Db.class_ids[i % Db.class_ids.size()])
	RunState.set_start_level(30)
	RunState.add_gold(123456)
	screen.open(19, 0)
	for i in 6:
		RunState.spend_log.append(_entry(i % 4, &"shop", "Legendary Greatsword of the Endless Night", 9999))
	for i in 4:
		RunState.toggle_want(i, "trainer:x%d" % i, "Shadow Bolt Rank IV", 999)
	PlayerManager.get_slot(3).ready = true
	_step()
	_step()
	await tree.process_frame
	await tree.process_frame
	var stall := screen.shop_panel.get_global_rect()
	var head := screen.header.get_global_rect()
	var board := screen.purse_board.get_global_rect()
	check(head.encloses(board), "the board is part of the header")
	check(head.end.y + CLEARANCE <= stall.position.y - HAT_RISE,
		"the header (bottom %.1f) clears the merchant's hat (%.1f)" % [head.end.y, stall.position.y - HAT_RISE])
	check(head.position.y >= 0.0, "the header starts on screen")
	var chips := screen.chips_row.get_global_rect()
	check(chips.position.y >= stall.end.y + CLEARANCE, "the chips (top %.1f) clear the stall (bottom %.1f)" % [chips.position.y, stall.end.y])
	var footer := (screen.chips_row.get_parent() as Control).get_global_rect()
	check(footer.end.y <= 1080.0, "the footer stays on screen (%.1f)" % footer.end.y)
	for i in 4:
		var p := screen.panels[i]
		var r := p.get_global_rect()
		var visual := Rect2(r.position, r.size * p.scale)
		check(not visual.intersects(head), "P%d's panel and the header (%s / %s)" % [i + 1, visual, head])
		check(not visual.intersects(chips), "P%d's panel and the chips (%s / %s)" % [i + 1, visual, chips])
	for l in screen.purse_board.ticker_labels:
		check_eq(l.get_global_rect().size.x, PurseBoard.text_column_width(), "the ticker lines keep their width")
	check(_badge(0) != null, "with talent badges")
	# The widest chips: every player in their own panel, then every pad unplugged.
	for i in 4:
		screen.set_panel_focus(i, true)
	_step()
	await tree.process_frame
	_check_chips_clear("in panel")
	for s in PlayerManager.get_slots():
		(s.input as UiFakes.HumanInput).connected = false
	_step()
	await tree.process_frame
	_check_chips_clear("disconnected")
	finished.emit()


func _check_chips_clear(what: String) -> void:
	var chips := screen.chips_row.get_global_rect()
	var stall := screen.shop_panel.get_global_rect()
	check(chips.position.y >= stall.end.y + CLEARANCE, "%s: the chips clear the stall" % what)
	for i in [2, 3]:
		var p := screen.panels[i]
		var r := p.get_global_rect()
		check(not Rect2(r.position, r.size * p.scale).intersects(chips), "%s: P%d's panel and the chips (%s)" % [what, i + 1, chips])
