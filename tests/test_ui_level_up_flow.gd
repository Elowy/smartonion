extends TestCase
## Level-up phase in the game flow: Main opens the intermission with
## RunState.pending_level_ups (cards for the bots, counted in SMOKE_RESULT, cleared at the next
## wave), demo bots think before they pick, smoke / demo bots buy Trainer ranks after their
## market shopping while a reserve stays in the shared wallet (Intermission._bots_train) and
## spend gold nothing else took on a few stall rerolls (Intermission._bots_reroll).

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0

var main: Main
var world: Node3D
var screen: Intermission
var shop: MarketFakes.FakeShop
var trained: Array[Array] = []
var rerolled: Array[Array] = []


## A FakeShop whose next successful reroll puts [member restock] on the stall.
class RestockShop extends MarketFakes.FakeShop:
	var restock: Array[ItemInstance] = []

	func vote_reroll(slot_index: int, joined: Array[int], rng: RandomNumberGenerator) -> bool:
		if not super(slot_index, joined, rng):
			return false
		if not restock.is_empty():
			var prices: Array[int] = []
			for item in restock:
				prices.append(12)
			stock(restock, prices)
			restock = []
		return true


func before_each() -> void:
	UiFakes.reset_players()
	tree.paused = false
	trained.clear()
	rerolled.clear()


func after_each() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	UiFakes.free_node(screen)
	UiFakes.free_node(world)
	screen = null
	world = null
	tree.paused = false
	RunState.start_run(1, 1)
	UiFakes.reset_players()
	Enemy.invalidate_player_cache()


## A market after wave 3 with [param gold] in the wallet; the stall holds [param items] (default:
## a plate helm and a silk robe) for 12, 14, ... gold.
func _market(gold: int, p_shop: MarketFakes.FakeShop = null, items: Array[ItemInstance] = []) -> void:
	RunState.start_run(2, 5)
	RunState.wave = 3
	shop = p_shop if p_shop != null else MarketFakes.FakeShop.new()
	RunState.shop = shop
	if items.is_empty():
		items = [
			MarketFakes.make_item("Runed Plate Helm", Items.SlotType.HEAD, ClassData.ArmorType.PLATE),
			MarketFakes.make_item("Silk Robe", Items.SlotType.CHEST, ClassData.ArmorType.CLOTH),
		]
	var prices: Array[int] = []
	for i in items.size():
		prices.append(12 + 2 * i)
	shop.stock(items, prices)
	RunState.add_gold(gold)
	world = MarketFakes.make_world(tree)
	screen = Intermission.create()
	screen.bot_shopping = true
	screen.bot_buy_chance = 1.0
	screen.ranks_trained.connect(func(i: int, n: int) -> void: trained.append([i, n]))
	screen.bot_rerolled.connect(func(i: int, cost: int) -> void: rerolled.append([i, cost]))
	tree.root.add_child(screen)


func _step(delta: float = DT) -> void:
	MarketFakes.poll_all(delta)
	screen._process(delta)


## Every ability of [param slot]'s hero at Rank V (nothing left to train – the late game).
func _max_ranks(slot: PlayerSlot) -> void:
	var r := (slot.player as Player).abilities
	for a in r.slots:
		while a != null and r.can_rank_up(a.id):
			r.rank_up(a.id)
			if r.needs_spec(a.id):
				r.set_spec(a.id, 0)


## Offers neither a warrior nor a mage can use (rogue-only trinkets): never an upgrade.
func _useless_items(count: int) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for i in count:
		var item := MarketFakes.make_item("Rogue Charm %d" % i, Items.SlotType.TRINKET)
		item.class_restriction = &"rogue"
		out.append(item)
	return out


func _ranks(slot: PlayerSlot) -> int:
	var r := (slot.player as Player).abilities
	var n := 0
	for a in r.slots:
		if a != null:
			n += r.rank_of(a.id) - 1
	return n


# --- Trainer bots ----------------------------------------------------------------------------

func test_bots_train_after_shopping_and_keep_a_reserve() -> void:
	_market(400)
	var warrior := MarketFakes.bot_with_hero(world, "bot:a", &"warrior")
	var mage := MarketFakes.bot_with_hero(world, "bot:b", &"mage")
	screen.open(3, 0)
	_step()
	_step()
	check_eq(shop.buy_calls.size(), 2, "the bots bought their upgrades first")
	var reserve := Intermission.bot_train_reserve(3, 2)
	check_eq(reserve, ItemGenerator.price_for(Items.Rarity.UNCOMMON, 4), "one Uncommon item at the next wave's price per two bots")
	check(_ranks(warrior) > 0 and _ranks(mage) > 0, "both bots bought ranks: %d / %d" % [_ranks(warrior), _ranks(mage)])
	check(RunState.gold >= reserve, "the reserve stays in the wallet: %d >= %d" % [RunState.gold, reserve])
	var total := 0
	for t in trained:
		total += int(t[1])
	check_eq(total, _ranks(warrior) + _ranks(mage), "ranks_trained reports every rank")
	var cheapest := 0
	for s in [warrior, mage]:
		var r := ((s as PlayerSlot).player as Player).abilities
		for a in r.slots:
			if a != null and r.can_rank_up(a.id):
				var price := r.trainer_price(a.id)
				cheapest = price if cheapest == 0 else mini(cheapest, price)
	check(RunState.gold - cheapest < reserve or cheapest == 0, "they stopped only when the next rank would dip into the reserve")


func test_poor_bots_do_not_train() -> void:
	_market(30)
	var bot := MarketFakes.bot_with_hero(world, "bot:a", &"warrior")
	screen.open(3, 0)
	_step()
	_step()
	check_eq(_ranks(bot), 0, "no gold above the reserve: no ranks")
	check(trained.is_empty(), "nothing reported")


func test_bots_do_not_train_outside_smoke_and_demo() -> void:
	_market(400)
	screen.bot_shopping = false
	var bot := MarketFakes.bot_with_hero(world, "bot:a", &"warrior")
	screen.open(3, 0)
	_step()
	_step()
	check_eq(_ranks(bot), 0, "no Trainer without bot shopping")
	check_eq(RunState.gold, 400, "wallet untouched")


# --- Rerolling bots -------------------------------------------------------------------------

func test_rich_bots_reroll_the_stall_and_shop_again() -> void:
	var stall := RestockShop.new()
	stall.restock = _useless_items(2)
	stall.restock.push_front(MarketFakes.make_item("Runed Plate Helm", Items.SlotType.HEAD, ClassData.ArmorType.PLATE))
	_market(1000, stall, _useless_items(3))
	var warrior := MarketFakes.bot_with_hero(world, "bot:a", &"warrior")
	var mage := MarketFakes.bot_with_hero(world, "bot:b", &"mage")
	_max_ranks(warrior)
	_max_ranks(mage)
	screen.open(3, 0)
	_step()
	_step()
	check(trained.is_empty(), "nothing left to train")
	check_eq(shop.rerolls_this_round, Intermission.BOT_MAX_REROLLS, "rerolled up to the cap")
	check_eq(rerolled.size(), Intermission.BOT_MAX_REROLLS, "every reroll reported")
	check_eq(rerolled[0], [warrior.index, 8], "the first bot pays the first reroll: wave 3 x 2 + 2")
	check_eq(rerolled[1], [mage.index, 10], "the next bot the next one, 2 g more")
	check_eq(shop.buy_calls, [[0, warrior.index]], "after the reroll the warrior bought the new helm")
	check(ShopPanel.equipment_of(warrior).get_item(Items.EquipSlot.HEAD) != null, "and wears it")
	check_eq(RunState.gold, 1000 - 8 - 12 - 10 - 12, "rerolls and the helm paid from the shared wallet")
	check(shop.reroll_votes.is_empty(), "no bot vote left standing")


## The production path end to end: a real Shop (vote_reroll -> try_reroll with the one bot's
## vote, reroll_cost paid, offers redrawn from RunState.rng), the bots buying the redrawn
## offers and the loop stopping once nothing is left to reroll.
func test_bots_reroll_a_real_stall_and_buy_the_redraw() -> void:
	RunState.start_run(2, 5)
	RunState.wave = 20
	var real := Shop.new()
	RunState.shop = real
	RunState.add_gold(1000)
	world = MarketFakes.make_world(tree)
	screen = Intermission.create()
	screen.bot_shopping = true
	screen.bot_buy_chance = 1.0
	screen.bot_rerolled.connect(func(i: int, cost: int) -> void: rerolled.append([i, cost]))
	tree.root.add_child(screen)
	var warrior := MarketFakes.bot_with_hero(world, "bot:a", &"warrior")
	var mage := MarketFakes.bot_with_hero(world, "bot:b", &"mage")
	_max_ranks(warrior)
	_max_ranks(mage)
	screen.open(20, 0)
	check(not real.offers.is_empty(), "the stall is stocked")
	# Nothing on the stall is an upgrade: only a reroll can give the bots something to buy.
	var useless := _useless_items(real.offers.size())
	for i in real.offers.size():
		real.offers[i].item = useless[i]
	var start := RunState.gold
	_step()
	_step()
	check(not rerolled.is_empty(), "the bots rerolled the stall")
	check_eq(real.rerolls_this_round, rerolled.size(), "every reroll went through the real shop")
	check_eq(rerolled[0][1], 42, "the first reroll costs wave 20 x 2 + 2")
	var redrawn := 0
	var spent_on_items := 0
	for o in real.offers:
		if not useless.has(o.item):
			redrawn += 1
		if o.sold:
			spent_on_items += o.price
	check(redrawn > 0, "the reroll redrew the offers")
	check(spent_on_items > 0, "and the bots bought from the redraw")
	var spent_on_rerolls := 0
	for r in rerolled:
		spent_on_rerolls += int(r[1])
	check_eq(RunState.gold, start - spent_on_rerolls - spent_on_items, "rerolls and items paid from the wallet")
	check(real.reroll_votes.is_empty(), "no bot vote left standing")
	check(rerolled.size() <= Intermission.BOT_MAX_REROLLS, "within the cap")


func test_bots_reroll_only_with_gold_well_above_the_reserve() -> void:
	var keep := Intermission.BOT_REROLL_RESERVE_MULT * Intermission.bot_train_reserve(3, 2)
	_market(keep + 8 + 9, null, _useless_items(3))
	var warrior := MarketFakes.bot_with_hero(world, "bot:a", &"warrior")
	var mage := MarketFakes.bot_with_hero(world, "bot:b", &"mage")
	_max_ranks(warrior)
	_max_ranks(mage)
	screen.open(3, 0)
	_step()
	_step()
	check_eq(rerolled.size(), 1, "one reroll: a second (10 g) would dip below %d g" % keep)
	check_eq(RunState.gold, keep + 9, "the wallet keeps twice the training reserve")


func test_bots_train_before_they_reroll() -> void:
	_market(1000, null, _useless_items(3))
	var warrior := MarketFakes.bot_with_hero(world, "bot:a", &"warrior")
	var mage := MarketFakes.bot_with_hero(world, "bot:b", &"mage")
	screen.open(3, 0)
	_step()
	_step()
	check(_ranks(warrior) > 0 and _ranks(mage) > 0, "the Trainer got the gold first")
	var keep := Intermission.BOT_REROLL_RESERVE_MULT * Intermission.bot_train_reserve(3, 2)
	check(RunState.gold < keep + shop.reroll_cost(), "training left %d g, too little for a reroll" % RunState.gold)
	check(rerolled.is_empty(), "no reroll while ranks can still be bought")


func test_bots_never_reroll_over_a_human() -> void:
	_market(1000, null, _useless_items(3))
	MarketFakes.human_with_hero(world, "pad:a", &"rogue")
	var warrior := MarketFakes.bot_with_hero(world, "bot:b", &"warrior")
	_max_ranks(warrior)
	screen.open(3, 0)
	_step()
	_step()
	check(rerolled.is_empty(), "a human votes on rerolls: the bots leave it to them")
	check_eq(shop.rerolls_this_round, 0, "no reroll")
	check(shop.vote_calls.is_empty(), "no bot vote")


# --- Main ------------------------------------------------------------------------------------

func _make_main(opts: LaunchOptions = null) -> Main:
	main = Main.create(opts if opts != null else LaunchOptions.new())
	tree.root.add_child(main)
	return main


func test_main_opens_the_cards_for_pending_level_ups() -> void:
	_make_main()
	for i in 2:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)
	main.start_run()
	RunState.pending_level_ups = 2
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	main._physics_process(Main.WAVE_END_DELAY + 0.01)
	check_eq(main.state, Main.State.INTERMISSION, "intermission")
	check_eq(main.intermission.level_ups, 2, "with the pending level-ups")
	check_eq(main.intermission.phase, Intermission.Phase.LEVEL_UP, "the cards come first (no loot)")
	for slot in PlayerManager.get_slots():
		slot.input.poll(0.25)
	main.intermission._process(0.25)
	check_eq(main.intermission.phase, Intermission.Phase.MARKET, "the bots picked at once")
	check_eq(main.level_cards, 4, "two bots x two levels counted")
	var data := main.smoke_result("completed")
	for key in ["level_cards", "abilities_learned", "ranks_trained"]:
		check(data.has(key), "SMOKE_RESULT has %s" % key)
	check_eq(data["level_cards"], 4, "level cards in SMOKE_RESULT")
	check_eq(data["abilities_learned"], main.abilities_learned(), "learned abilities counted")
	main._on_intermission_continue()
	check_eq(RunState.pending_level_ups, 0, "cleared at the next wave")
	check_eq(main.state, Main.State.WAVE, "next wave")


## SMOKE_RESULT "gold_at_last_shop": the wallet when the last market closed – the final gold
## also holds the last wave's haul, which no shop follows. "shop_rerolls" counts bot rerolls.
func test_smoke_result_has_the_gold_at_the_last_shop() -> void:
	_make_main()
	PlayerManager.add_bot(&"warrior", 1)
	main.start_run()
	var start_gold := RunState.gold
	check_eq(main.smoke_result("completed")["gold_at_last_shop"], start_gold, "before any market: the starting wallet")
	RunState.add_gold(120)
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	main._physics_process(Main.WAVE_END_DELAY + 0.01)
	check_eq(main.state, Main.State.INTERMISSION, "intermission")
	main.intermission.bot_rerolled.emit(0, 8)
	check(RunState.try_spend(30), "spent in the market")
	main._on_intermission_continue()
	check_eq(main.state, Main.State.WAVE, "next wave")
	var at_close := RunState.gold
	check_eq(at_close, start_gold + 90, "the wallet when the market closed")
	RunState.add_gold(500)  # the next (last) wave's haul
	var data := main.smoke_result("completed")
	check_eq(data["gold"], at_close + 500, "the final gold holds the haul")
	check_eq(data["gold_at_last_shop"], at_close, "the last shop's wallet does not")
	check_eq(data["shop_rerolls"], 1, "bot rerolls counted")
	main.start_run()
	check_eq(main.smoke_result("completed")["shop_rerolls"], 0, "a new run starts the count again")


func test_demo_bots_think_over_their_cards() -> void:
	var opts := LaunchOptions.new()
	opts.demo = true
	opts.players = 2
	opts.seed_value = 4
	_make_main(opts)
	check_eq(main.intermission.level_up_screen.bot_think_time, Main.DEMO_LEVEL_UP_THINK_TIME, "demo: bots think")
	main.free()
	main = null
	UiFakes.reset_players()
	_make_main()
	PlayerManager.add_bot(&"warrior", 1)
	main.start_run()
	check_eq(main.intermission.level_up_screen.bot_think_time, 0.0, "plain runs: at once")
