extends TestCase
## Level-up phase in the game flow: Main opens the intermission with
## RunState.pending_level_ups (cards for the bots, counted in SMOKE_RESULT, cleared at the next
## wave), demo bots think before they pick, and smoke / demo bots buy Trainer ranks after their
## market shopping while a reserve stays in the shared wallet (Intermission._bots_train).

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0

var main: Main
var world: Node3D
var screen: Intermission
var shop: MarketFakes.FakeShop
var trained: Array[Array] = []


func before_each() -> void:
	UiFakes.reset_players()
	tree.paused = false
	trained.clear()


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


func _market(gold: int) -> void:
	RunState.start_run(2, 5)
	RunState.wave = 3
	shop = MarketFakes.FakeShop.new()
	RunState.shop = shop
	var items: Array[ItemInstance] = [
		MarketFakes.make_item("Runed Plate Helm", Items.SlotType.HEAD, ClassData.ArmorType.PLATE),
		MarketFakes.make_item("Silk Robe", Items.SlotType.CHEST, ClassData.ArmorType.CLOTH),
	]
	shop.stock(items, [12, 14] as Array[int])
	RunState.add_gold(gold)
	world = MarketFakes.make_world(tree)
	screen = Intermission.create()
	screen.bot_shopping = true
	screen.bot_buy_chance = 1.0
	screen.ranks_trained.connect(func(i: int, n: int) -> void: trained.append([i, n]))
	tree.root.add_child(screen)


func _step(delta: float = DT) -> void:
	MarketFakes.poll_all(delta)
	screen._process(delta)


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
