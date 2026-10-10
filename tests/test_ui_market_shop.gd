extends TestCase
## ShopPanel (GDD 10 / 12): offer cards, one cursor per player (starts near the player's corner,
## moves on the grid), A buys (hold A when the price is more than half the wallet), X locks,
## R3 pings, Y votes for a reroll (humans only), feedback lines, tooltips beside the stall on
## the player's own side, bot helpers. Uses a recording FakeShop (test_ui_market_fakes.gd).

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var shop: MarketFakes.FakeShop
var panel: ShopPanel
var p1: UiFakes.HumanInput
var p2: UiFakes.HumanInput
var bought: Array[Array] = []


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(2, 11)
	world = MarketFakes.make_world(tree)
	p1 = MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	p2 = MarketFakes.human_with_hero(world, "pad:b", &"mage")
	shop = MarketFakes.FakeShop.new()
	_stock(6)
	panel = ShopPanel.create(shop)
	panel.position = Vector2(568, 140)
	panel.item_bought.connect(func(i: int, item: ItemInstance) -> void: bought.append([i, item]))
	tree.root.add_child(panel)
	panel.refresh(PlayerManager.get_slots())


func after_each() -> void:
	UiFakes.free_node(panel)
	UiFakes.free_node(world)
	panel = null
	world = null
	UiFakes.reset_players()


## [param n] offers: plate helms / cloth robes / rings, prices 10, 20, 30 ...
func _stock(n: int) -> void:
	var items: Array[ItemInstance] = []
	var prices: Array[int] = []
	for i in n:
		var item: ItemInstance
		match i % 3:
			0:
				item = MarketFakes.make_item("Runed Plate Helm %d" % i, Items.SlotType.HEAD, ClassData.ArmorType.PLATE)
			1:
				item = MarketFakes.make_item("Silk Robe %d" % i, Items.SlotType.CHEST, ClassData.ArmorType.CLOTH)
			_:
				item = MarketFakes.make_item("Band %d" % i, Items.SlotType.RING)
		items.append(item)
		prices.append(10 * (i + 1))
	shop.stock(items, prices)


## One frame: inputs polled, then the panel handles every slot (what the Intermission does).
func _step(delta: float = DT) -> void:
	MarketFakes.poll_all(delta)
	panel.begin_frame(delta)
	for s in PlayerManager.get_slots():
		panel.handle_input(s)


func _tap(input: UiFakes.HumanInput, button: PlayerInput.Pad) -> void:
	input.press(button)
	_step()
	input.release(button)
	_step(0.0)


func _nudge(input: UiFakes.HumanInput, dir: Vector2) -> void:
	input.move = dir
	_step()
	input.move = Vector2.ZERO
	_step(0.0)


# --- Cards ------------------------------------------------------------------------------

func test_cards_and_grid_columns() -> void:
	check_eq(panel.cards.size(), 6, "one card per offer")
	check_eq(panel.columns, 3, "6 offers -> 3 x 2")
	check_eq(panel.cards[0].name_label.text, "Runed Plate Helm 0", "name")
	check_eq(panel.cards[0].name_label.get_theme_color(&"font_color"), UiTheme.RARITY_COLORS[Items.Rarity.UNCOMMON], "rarity colour")
	check_eq(panel.cards[0].type_label.text, "Plate Head", "type line")
	check_eq(panel.cards[2].type_label.text, "Finger", "ring")
	check_eq(panel.cards[1].price_label.text, "20", "price")
	check_eq(panel.cards[1].price_label.get_theme_color(&"font_color"), UiTheme.RED, "unaffordable price is red")
	RunState.add_gold(25)
	check_eq(panel.cards[1].price_label.get_theme_color(&"font_color"), UiTheme.GOLD, "affordable after gold came in")
	_stock(10)
	check_eq(panel.cards.size(), 10, "restocked")
	check_eq(panel.columns, 5, "10 offers -> 5 x 2")
	_stock(4)
	check_eq(panel.columns, 4, "4 offers in one row")


func test_sold_lock_and_ping_markers() -> void:
	shop.offers[1].sold = true
	shop.offers[2].locked_by = 1
	shop.offers[3].pinged_by.append(0)
	shop.changed.emit()
	check(panel.cards[1]._content.modulate.a < 0.5, "sold card dimmed")
	check(panel.cards[2]._lock.visible, "lock shown")
	check_eq(panel.cards[2]._lock.color, PlayerManager.get_slot(1).color.lightened(0.15), "lock in the locker's colour")
	check(not panel.cards[0]._lock.visible, "no lock elsewhere")


# --- Cursors ----------------------------------------------------------------------------

func test_cursors_start_near_the_player_corners_and_move_on_the_grid() -> void:
	check_eq(panel.cursor_of(0), 0, "P1 top-left")
	check_eq(panel.cursor_of(1), 2, "P2 top-right (3 columns)")
	_nudge(p1, Vector2.RIGHT)
	check_eq(panel.cursor_of(0), 1, "right")
	_nudge(p1, Vector2.DOWN)
	check_eq(panel.cursor_of(0), 4, "down one row")
	_nudge(p1, Vector2.DOWN)
	check_eq(panel.cursor_of(0), 4, "bottom row: stays")
	_nudge(p2, Vector2.RIGHT)
	check_eq(panel.cursor_of(1), 2, "right edge: stays")
	_nudge(p2, Vector2.LEFT)
	_nudge(p2, Vector2.LEFT)
	_nudge(p2, Vector2.LEFT)
	check_eq(panel.cursor_of(1), 0, "left edge: stays")
	check_eq(panel.cursor_of(0), 4, "P1 did not move with P2")


# --- Buying -----------------------------------------------------------------------------

func test_a_buys_a_cheap_offer() -> void:
	RunState.add_gold(100)
	_tap(p1, PlayerInput.Pad.A)
	check_eq(shop.buy_calls, [[0, 0]] as Array[Array], "shop.buy(cursor, P1)")
	check(shop.offers[0].sold, "sold")
	check_eq(RunState.gold, 90, "paid from the shared wallet")
	check_eq(bought.size(), 1, "item_bought")
	check_eq(bought[0][0], 0, "by P1")
	check("P1 bought [Runed Plate Helm 0] – 10 g" in panel.feedback_lines(), "spending log: %s" % [panel.feedback_lines()])
	_tap(p1, PlayerInput.Pad.A)
	check_eq(shop.buy_calls.size(), 1, "a sold offer is not bought again")
	check("P1: Already sold" in panel.feedback_lines(), "told so")


func test_expensive_offer_needs_a_held_a() -> void:
	RunState.add_gold(100)
	panel.set_cursor(0, 5)  # 60 g > 50% of 100 g
	check(panel.needs_hold(60), "more than half the wallet")
	check(not panel.needs_hold(50), "exactly half is fine")
	p1.press(PlayerInput.Pad.A)
	_step()
	check_eq(shop.buy_calls.size(), 0, "not on the press")
	for i in 30:
		_step()
	check_near(panel.hold_progress(0), 0.5, 0.03, "half-way")
	check_eq(shop.buy_calls.size(), 0, "not yet")
	p1.release(PlayerInput.Pad.A)
	_step()
	check_eq(panel.hold_progress(0), 0.0, "released early: cancelled")
	p1.press(PlayerInput.Pad.A)
	_step()
	for i in 62:
		_step()
	p1.release(PlayerInput.Pad.A)
	_step()
	check_eq(shop.buy_calls, [[5, 0]] as Array[Array], "held for a second: bought")
	check_eq(RunState.gold, 40, "paid")


func test_moving_away_cancels_the_hold() -> void:
	RunState.add_gold(100)
	panel.set_cursor(0, 5)
	p1.press(PlayerInput.Pad.A)
	_step()
	for i in 20:
		_step()
	p1.move = Vector2.LEFT
	_step()
	p1.move = Vector2.ZERO
	for i in 70:
		_step()
	check_eq(shop.buy_calls.size(), 0, "the cursor left the offer: no purchase")


func test_not_enough_gold_and_full_backpack() -> void:
	RunState.add_gold(5)
	_tap(p1, PlayerInput.Pad.A)
	check("P1: Not enough gold" in panel.feedback_lines(), "poor: %s" % [panel.feedback_lines()])
	RunState.add_gold(100)
	var eq := ShopPanel.equipment_of(PlayerManager.get_slot(0))
	for i in Items.BACKPACK_SIZE:
		eq.add_to_backpack(MarketFakes.make_item("Junk %d" % i, Items.SlotType.NECK))
	_tap(p1, PlayerInput.Pad.A)
	check("P1: Backpack full" in panel.feedback_lines(), "full: %s" % [panel.feedback_lines()])
	check_eq(shop.buy_calls.size(), 0, "the shop is never asked")
	check_eq(panel.feedback_lines().size(), 2, "both messages kept")


# --- Lock / ping / reroll ----------------------------------------------------------------

func test_x_locks_r3_pings_y_votes() -> void:
	_tap(p1, PlayerInput.Pad.X)
	check_eq(shop.lock_calls, [[0, 0]] as Array[Array], "lock P1's offer")
	check(panel.cards[0]._lock.visible, "lock icon")
	_tap(p2, PlayerInput.Pad.R3)
	check_eq(shop.ping_calls, [[2, 1]] as Array[Array], "P2 pings its offer")
	check("P2 wants: [Band 2] – 30 g" in panel.feedback_lines(), "ping line: %s" % [panel.feedback_lines()])
	_tap(p1, PlayerInput.Pad.Y)
	check_eq(shop.vote_calls.size(), 1, "vote")
	check_eq(shop.vote_calls[0][1], [0, 1] as Array[int], "both humans must vote")
	check(shop.reroll_votes.has(0), "P1 voted")
	RunState.add_gold(100)
	_tap(p2, PlayerInput.Pad.Y)
	check_eq(shop.rerolls_this_round, 1, "everyone voted -> reroll")
	check("Rerolled for 8 g" in panel.feedback_lines(), "reroll line: %s" % [panel.feedback_lines()])


func test_reroll_without_gold_says_so() -> void:
	_tap(p1, PlayerInput.Pad.Y)
	_tap(p2, PlayerInput.Pad.Y)
	check_eq(shop.rerolls_this_round, 0, "no reroll")
	check("P2: Not enough gold to reroll" in panel.feedback_lines(), "%s" % [panel.feedback_lines()])


func test_bots_and_unplugged_players_never_block_a_reroll() -> void:
	var bot := MarketFakes.bot_with_hero(world, "bot:x", &"rogue")
	p2.connected = false
	panel.refresh(PlayerManager.get_slots())
	check_eq(panel.voter_indices(), [0] as Array[int], "only the connected human votes")
	check(bot.index == 2, "bot slot")


# --- Tooltips ---------------------------------------------------------------------------

func test_tooltips_beside_the_stall_on_the_player_side() -> void:
	panel._process(DT)
	var t1 := panel.tooltip_of(0)
	var t2 := panel.tooltip_of(1)
	check(t1 != null and t2 != null, "one tooltip per player")
	check(t1.visible and t2.visible, "shown for the hovered offers")
	var stall_mid := panel.global_position.x + panel.size.x * 0.5
	check(t1.global_position.x + t1.size.x * 0.5 < stall_mid, "P1's tooltip on the left")
	check(t2.global_position.x + t2.size.x * 0.5 > stall_mid, "P2's tooltip on the right")
	check(t2.position.x >= panel.size.x, "P2's tooltip does not cover the stall")
	panel.set_cursor_active(0, false)
	panel._process(DT)
	check(not t1.visible, "hidden while P1's focus is the own panel")
	shop.offers[2].sold = true
	shop.changed.emit()
	panel._process(DT)
	check(not t2.visible, "no tooltip on a sold offer")


# --- Bot helpers ------------------------------------------------------------------------

func test_cheapest_usable_affordable_offer() -> void:
	var warrior := PlayerManager.get_slot(0)
	var mage := PlayerManager.get_slot(1)
	check_eq(panel.cheapest_offer_for(warrior), -1, "nothing affordable")
	RunState.add_gold(35)
	check_eq(panel.cheapest_offer_for(warrior), 0, "plate helm 10 g")
	check_eq(panel.cheapest_offer_for(mage), 1, "the mage cannot wear plate: robe 20 g")
	shop.offers[0].sold = true
	check_eq(panel.cheapest_offer_for(warrior), 1, "sold offers skipped (the warrior can wear cloth)")
	check(panel.try_buy(mage, 2), "buy helper")
	check_eq(RunState.gold, 5, "paid")
