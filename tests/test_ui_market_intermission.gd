extends TestCase
## Intermission M2 phases (GDD 10, 10.1, 12): LOOT (only with team loot: the loot roll takes
## RunState.team_loot) -> MARKET (Shop.open_round once per open, ShopPanel in the middle, one
## PlayerPanel per hero in its corner). Input routing per slot: LB / RB switch between the
## shop cursor and the own panel, A buys, START readies; the auto-continue countdown only runs
## in MARKET; smoke / demo bots buy and equip upgrades. Uses the FakeShop of
## test_ui_market_fakes.gd as RunState.shop.

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var screen: Intermission
var shop: MarketFakes.FakeShop
var continues := 0
var bought := 0


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(2, 9)
	shop = MarketFakes.FakeShop.new()
	RunState.shop = shop
	_stock()
	world = MarketFakes.make_world(tree)
	screen = Intermission.create()
	screen.continue_requested.connect(func() -> void: continues += 1)
	screen.item_bought.connect(func(_i: int, _item: ItemInstance) -> void: bought += 1)
	tree.root.add_child(screen)


func after_each() -> void:
	Intermission.auto_continue_time = Intermission.AUTO_CONTINUE_TIME
	UiFakes.free_node(screen)
	UiFakes.free_node(world)
	screen = null
	world = null
	RunState.start_run(1, 1)
	UiFakes.reset_players()


func _stock() -> void:
	var items: Array[ItemInstance] = [
		MarketFakes.make_item("Runed Plate Helm", Items.SlotType.HEAD, ClassData.ArmorType.PLATE),
		MarketFakes.make_item("Silk Robe", Items.SlotType.CHEST, ClassData.ArmorType.CLOTH),
		MarketFakes.make_item("Band of Thorns", Items.SlotType.RING),
		MarketFakes.make_weapon(&"sword"),
		MarketFakes.make_weapon(&"staff"),
		MarketFakes.make_item("Steel Greaves", Items.SlotType.LEGS, ClassData.ArmorType.PLATE),
	]
	shop.stock(items, [12, 14, 16, 30, 32, 40] as Array[int])


func _loot(n: int) -> void:
	for i in n:
		RunState.add_team_loot(MarketFakes.make_item("Looted Charm %d" % i, Items.SlotType.TRINKET, Items.NO_ARMOR, Items.Rarity.RARE))


## Steps the intermission and, while it rolls loot, the loot screen (both run every frame).
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


func test_without_loot_the_market_opens_at_once() -> void:
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	MarketFakes.human_with_hero(world, "pad:b", &"mage")
	screen.open(3, 1)
	check_eq(screen.phase, Intermission.Phase.MARKET, "market")
	check(not screen.loot_screen.visible, "no loot roll")
	check_eq(shop.open_calls.size(), 1, "Shop.open_round once")
	check_eq(shop.open_calls[0]["wave"], 3, "for the cleared wave")
	check_eq((shop.open_calls[0]["slots"] as Array).size(), 2, "with the joined slots")
	check(screen.shop_panel.shop == shop, "the panel shows RunState.shop")
	check_eq(screen.shop_panel.cards.size(), 6, "offer cards")
	check(screen.panels.has(0) and screen.panels.has(1), "one personal panel per hero")
	var p1 := screen.panels[0]
	var p2 := screen.panels[1]
	check(p1.anchor_left == 0.0 and p1.anchor_top == 0.0, "P1 top-left")
	check(p2.anchor_left == 1.0 and p2.anchor_top == 0.0, "P2 top-right")
	check_eq(p1.slot, PlayerManager.get_slot(0), "P1's panel shows P1")
	check(screen.countdown_label.visible, "countdown")
	for i in 30:
		_step()
	check_eq(shop.open_calls.size(), 1, "never again while it is open")
	screen.open(4, 0)
	check_eq(shop.open_calls.size(), 2, "next intermission, next round")
	check(screen.panels[0] == p1, "panels are kept between intermissions")


func test_panels_follow_the_screen_corners() -> void:
	for i in 4:
		MarketFakes.human_with_hero(world, "pad:%d" % i, Db.class_ids[i % Db.class_ids.size()])
	screen.open(2, 0)
	var expect := [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0], [1.0, 1.0]]
	for i in 4:
		var p := screen.panels[i]
		check(p.anchor_left == expect[i][0] and p.anchor_top == expect[i][1], "P%d corner" % (i + 1))
		var shown := (p.offset_right - p.offset_left) * p.scale.x
		check(shown <= Intermission.PANEL_AREA.x + 0.5, "P%d fits its corner area: %.1f" % [i + 1, shown])
		var r := p.get_global_rect()
		var visual := Rect2(r.position, r.size * p.scale)
		check(not visual.intersects(screen.shop_panel.get_global_rect()), "P%d's panel does not cover the stall" % (i + 1))
	check_eq(screen.chips_row.get_child_count(), 4, "four ready chips")


func test_loot_roll_comes_first_and_the_countdown_waits() -> void:
	var a := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	var b := MarketFakes.human_with_hero(world, "pad:b", &"mage")
	_loot(2)
	screen.open(3, 0)
	check_eq(screen.phase, Intermission.Phase.LOOT, "loot roll first")
	check(screen.loot_screen.visible and screen.loot_screen.is_rolling(), "roll window")
	check(not screen._market_root.visible, "market hidden meanwhile")
	check(RunState.team_loot.is_empty(), "the team loot was taken")
	check_eq(screen.loot_screen.items.size(), 2, "both items")
	check_eq(shop.open_calls.size(), 0, "no shop round yet")
	screen._process(10.0)
	check_eq(screen.time_left, Intermission.AUTO_CONTINUE_TIME, "no countdown during the loot roll")
	_step()
	_step(LootRollScreen.ITEM_INPUT_DELAY)
	_tap(a, PlayerInput.Pad.X)
	_tap(b, PlayerInput.Pad.Y)
	_step(LootRollScreen.RESULT_TIME + 0.01)
	_step(LootRollScreen.ITEM_INPUT_DELAY)
	_tap(a, PlayerInput.Pad.B)
	check_eq(screen.phase, Intermission.Phase.LOOT, "showing the last result")
	_step(LootRollScreen.RESULT_TIME + 0.01)
	check_eq(screen.phase, Intermission.Phase.MARKET, "then the market")
	check(not screen.loot_screen.visible and screen._market_root.visible, "market shown")
	check_eq(shop.open_calls.size(), 1, "shop round opened after the loot")
	check_eq(screen.time_left, Intermission.AUTO_CONTINUE_TIME, "a full minute for the market")
	_step(5.0)
	check_eq(screen.time_left, Intermission.AUTO_CONTINUE_TIME - 5.0, "counting now")


func test_lb_rb_switch_between_the_shop_and_the_own_panel() -> void:
	var a := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	MarketFakes.human_with_hero(world, "pad:b", &"mage")
	screen.open(1, 0)
	_step()
	check(not screen.has_panel_focus(0), "starts at the shop")
	a.move = Vector2.RIGHT
	_step()
	a.move = Vector2.ZERO
	_step(0.0)
	check_eq(screen.shop_panel.cursor_of(0), 1, "the stick moves the shop cursor")
	_tap(a, PlayerInput.Pad.RB)
	check(screen.has_panel_focus(0), "RB: own panel")
	check(not screen.shop_panel.is_cursor_active(0), "shop cursor dimmed")
	a.move = Vector2.RIGHT
	_step()
	a.move = Vector2.ZERO
	_step(0.0)
	check_eq(screen.shop_panel.cursor_of(0), 1, "the shop cursor stays while the panel has the focus")
	RunState.add_gold(100)
	_tap(a, PlayerInput.Pad.A)
	check_eq(shop.buy_calls.size(), 0, "A goes to the panel, not the shop")
	_tap(a, PlayerInput.Pad.START)
	check(PlayerManager.get_slot(0).ready, "START readies from the panel too")
	_tap(a, PlayerInput.Pad.LB)
	check(not screen.has_panel_focus(0), "LB: back to the shop")
	check(screen.shop_panel.is_cursor_active(0), "cursor active again")
	check(not screen.has_panel_focus(1), "P2 untouched")


func test_a_buys_and_start_readies_in_the_market() -> void:
	var a := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	var b := MarketFakes.human_with_hero(world, "pad:b", &"mage")
	RunState.add_gold(100)
	screen.open(1, 0)
	_step()
	_tap(a, PlayerInput.Pad.A)
	check_eq(shop.buy_calls, [[0, 0]] as Array[Array], "P1 bought the helm")
	check_eq(bought, 1, "item_bought forwarded")
	check(not PlayerManager.get_slot(0).ready, "buying does not ready")
	check_eq(ShopPanel.equipment_of(PlayerManager.get_slot(0)).backpack.size(), 1, "in P1's backpack")
	_tap(a, PlayerInput.Pad.START)
	_tap(b, PlayerInput.Pad.START)
	check_eq(continues, 1, "all ready")


func test_players_without_a_hero_get_no_panel() -> void:
	var input := UiFakes.HumanInput.new("pad:x")
	PlayerManager.join(input, Db.get_class_data(&"rogue"))
	screen.open(1, 0)
	check(screen.panels.is_empty(), "no hero, no panel")
	_step()
	_tap(input, PlayerInput.Pad.RB)
	check(not screen.has_panel_focus(0), "the focus stays at the shop")


func test_smoke_bots_buy_and_equip_upgrades() -> void:
	var warrior := MarketFakes.bot_with_hero(world, "bot:a", &"warrior")
	var mage := MarketFakes.bot_with_hero(world, "bot:b", &"mage")
	RunState.add_gold(100)
	screen.bot_shopping = true
	screen.bot_buy_chance = 1.0
	screen.open(2, 0)
	_step()
	check_eq(continues, 0, "the first frame is skipped")
	_step()
	check_eq(shop.buy_calls.size(), 2, "every bot bought once")
	check_eq(shop.buy_calls[0], [0, 0], "the warrior: the cheapest offer it can use")
	check_eq(shop.buy_calls[1], [1, 1], "the mage cannot wear plate: the robe")
	check_eq(bought, 2, "counted")
	check_eq(continues, 1, "bots are ready")
	for s in [warrior, mage]:
		var eq := ShopPanel.equipment_of(s)
		for item in eq.backpack:
			var current := ItemTooltip.equipped_for_compare(item, eq)
			check(not eq.can_equip(item) or ItemTooltip.upgrade_direction(item, current, s.class_data) <= 0,
				"%s left an upgrade in the backpack: %s" % [s.label(), item.display_name])


func test_bots_do_not_shop_outside_smoke_and_demo() -> void:
	MarketFakes.bot_with_hero(world, "bot:a", &"warrior")
	RunState.add_gold(100)
	screen.open(2, 0)
	_step()
	_step()
	check_eq(shop.buy_calls.size(), 0, "no bot shopping")
	check_eq(continues, 1, "bots continue by themselves")


func test_demo_bots_keep_the_market_open_a_while() -> void:
	MarketFakes.bot_with_hero(world, "bot:a", &"warrior")
	RunState.add_gold(100)
	screen.bot_shopping = true
	screen.bot_buy_chance = 1.0
	screen.bot_market_time = 4.0
	screen.open(2, 0)
	_step()
	_step()
	check_eq(shop.buy_calls.size(), 0, "not at once")
	_step(2.0)
	check_eq(shop.buy_calls.size(), 1, "half-way: the bot shops")
	check_eq(screen.shop_panel.cursor_of(0), 0, "its cursor shows what it bought")
	check_eq(continues, 0, "still open")
	_step(2.1)
	check_eq(continues, 1, "then the next wave")


func test_disconnected_human_is_ready_in_the_market() -> void:
	var a := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	var b := MarketFakes.human_with_hero(world, "pad:b", &"mage")
	b.connected = false
	screen.open(1, 0)
	_step()
	check(PlayerManager.get_slot(1).ready, "unplugged: ready")
	_tap(a, PlayerInput.Pad.START)
	check_eq(continues, 1, "continues without them")


func test_bots_in_the_loot_roll_then_market() -> void:
	MarketFakes.bot_with_hero(world, "bot:a", &"warrior")
	MarketFakes.bot_with_hero(world, "bot:b", &"mage")
	var rolled: Array[LootRoll] = []
	screen.loot_rolled.connect(func(r: LootRoll) -> void: rolled.append(r))
	_loot(2)
	screen.open(5, 0)
	for i in 10:
		_step(0.5)
	check_eq(rolled.size(), 2, "both items rolled by the bots")
	check_eq(screen.phase, Intermission.Phase.MARKET, "market after the loot")
	check_eq(continues, 1, "and the bots move on")


func test_b_in_the_own_panel_unreadies_unless_it_closed_a_menu() -> void:
	var a := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	MarketFakes.human_with_hero(world, "pad:b", &"mage")
	screen.open(1, 0)
	_step()
	_tap(a, PlayerInput.Pad.RB)
	check(screen.has_panel_focus(0), "own panel")
	var slot := PlayerManager.get_slot(0)
	_tap(a, PlayerInput.Pad.START)
	check(slot.ready, "ready")
	_tap(a, PlayerInput.Pad.B)
	check(not slot.ready, "B with no menu open unreadies")
	_tap(a, PlayerInput.Pad.START)
	var panel := screen.panels[0]
	# Select an equipped weapon (the warrior starts with one) and open its menu with A.
	for i in 12:
		if panel.selected_item() != null:
			break
		_tap(a, PlayerInput.Pad.DPAD_DOWN)
	_tap(a, PlayerInput.Pad.A)
	var menu := panel.is_menu_open()
	_tap(a, PlayerInput.Pad.B)
	if menu:
		check(slot.ready, "B closed the panel's menu: still ready")
		check(not panel.is_menu_open(), "menu closed")
	else:
		check(not slot.ready, "no menu opened: B unreadies")
