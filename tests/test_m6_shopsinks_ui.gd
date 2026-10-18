extends TestCase
## M6 SHOPSINKS, the screen side: the consumables row and the Black Market card in the ShopPanel
## (cards, geometry, the cursor space, buying with A / the hold rule, lock / ping, tooltips), the
## 4-player stall fitting the 1920 x 1080 canvas (and its 1280 x 720 window), the unit frame's
## consumable icons, the purse board's new spends and the bots' shopping.

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var shop: Shop
var panel: ShopPanel
var p1: UiFakes.HumanInput
var p2: UiFakes.HumanInput
var rng := RandomNumberGenerator.new()
var nodes: Array[Node] = []
var bought_items: Array[ItemInstance] = []
var bought_consumables: Array[ConsumableData] = []
var screen: Intermission
var _root_size := Vector2i.ZERO
var _async := false


func is_async() -> bool:
	return _async


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(2, 11)
	rng.seed = 5
	world = MarketFakes.make_world(tree)
	p1 = MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	p2 = MarketFakes.human_with_hero(world, "pad:b", &"mage")
	_root_size = tree.root.size


func after_each() -> void:
	tree.root.size = _root_size
	Intermission.auto_continue_time = Intermission.AUTO_CONTINUE_TIME
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()
	UiFakes.free_node(panel)
	UiFakes.free_node(screen)
	UiFakes.free_node(world)
	panel = null
	screen = null
	world = null
	_async = false
	RunState.start_run(1, 1)
	UiFakes.reset_players()


## A real stall opened for [param wave] with the joined players, shown in a ShopPanel.
func _open(wave: int) -> void:
	RunState.set_wave(wave)
	shop = Shop.new()
	shop.open_round(wave, PlayerManager.get_slots(), rng)
	panel = ShopPanel.create(shop)
	panel.position = Vector2(568, 140)
	panel.item_bought.connect(func(_i: int, item: ItemInstance) -> void: bought_items.append(item))
	panel.consumable_bought.connect(func(_i: int, data: ConsumableData) -> void: bought_consumables.append(data))
	tree.root.add_child(panel)
	panel.refresh(PlayerManager.get_slots())


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


func _hero(i: int) -> Player:
	return PlayerManager.get_slot(i).player as Player


## Cursor position of the consumables card [param j].
func _cons(j: int) -> int:
	return panel.offer_count() + j


func _layout(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child in node.get_children():
		_layout(child)


# --- The cards ---------------------------------------------------------------------------------

func test_the_row_shows_the_shops_consumables_and_the_black_market_from_wave_15() -> void:
	_open(14)
	check_eq(panel.consumable_count(), 4, "four cards")
	check_eq(panel.consumable_cards.size(), 4, "four card nodes")
	check(not panel.has_black_market() and panel.black_market_card == null, "no Black Market at wave 14")
	check_eq(panel.slot_count(), panel.offer_count() + 4, "the cursor space: offers + the row")
	for j in 4:
		var card := panel.consumable_cards[j]
		var offer := shop.consumables[j]
		check(card.offer == offer and card.icon.data == offer.data, "card %d shows its consumable" % j)
		check_eq(card.name_label.text, offer.data.display_name, "name")
		check_eq(card.price_label.text, UiTheme.format_int(offer.price), "price")
	RunState.add_gold(500)
	panel.refresh(PlayerManager.get_slots())
	check_eq(panel.consumable_cards[0].price_label.get_theme_color(&"font_color"), UiTheme.GOLD, "affordable: gold")
	RunState.gold = 0
	panel._on_gold_changed(0, 0)
	check_eq(panel.consumable_cards[0].price_label.get_theme_color(&"font_color"), UiTheme.RED, "unaffordable: red")
	# Wave 15: the Black Market card appears at the end of the row.
	shop.open_round(15, PlayerManager.get_slots(), rng)
	check(panel.has_black_market() and panel.black_market_card != null, "Black Market card at wave 15")
	check(panel.black_market_card.wide and panel.black_market_card.gold_frame, "wide and gold-framed")
	check_eq(panel.slot_count(), panel.offer_count() + 4 + 1, "one more cursor position")
	check_eq(panel.black_market_index(), panel.offer_count() + 4, "it is the last position")
	check(panel.black_market_card.offer == shop.black_market, "shows the offer")
	check_eq(panel.black_market_card.price_label.text, str(BlackMarket.price(15)), "at the Black Market price")
	check(panel.card_at(panel.black_market_index()) == panel.black_market_card, "card_at")
	check(panel.card_at(_cons(2)) == panel.consumable_cards[2], "card_at the row")
	check(panel.card_at(3) == panel.cards[3] and panel.card_at(-1) == null and panel.card_at(99) == null, "card_at the grid / out of range")
	shop.open_round(16, PlayerManager.get_slots(), rng)
	check(panel.black_market_card.offer == shop.black_market, "a new round: the card follows")
	shop.open_round(5, PlayerManager.get_slots(), rng)
	check(panel.black_market_card == null and not panel.has_black_market(), "gone again below wave 15")
	check(panel.consumable_cards[0].offer == shop.consumables[0], "the row follows too")


func test_a_stall_without_extras_keeps_the_old_shape() -> void:
	# The FakeShop of the older tests has neither: no row, nothing hidden or moved.
	var fake := MarketFakes.FakeShop.new()
	var items: Array[ItemInstance] = [MarketFakes.make_item("A", Items.SlotType.RING), MarketFakes.make_item("B", Items.SlotType.RING)]
	fake.stock(items, [5, 6] as Array[int])
	shop = fake
	panel = ShopPanel.create(fake)
	tree.root.add_child(panel)
	panel.refresh(PlayerManager.get_slots())
	check_eq(panel.slot_count(), 2, "just the offers")
	check(not panel._extras.visible, "the row is hidden")
	check(panel.consumable_cards.is_empty() and panel.black_market_card == null, "no extra cards")
	check_eq(panel.black_market_index(), -1, "no Black Market position")


func test_extras_geometry_fits_the_row_without_overlap() -> void:
	for bm in [false, true]:
		var rects := ShopPanel.extras_layout(4, bm)
		check_eq(rects.size(), 5 if bm else 4, "cards (Black Market %s)" % bm)
		var right := 0.0
		for i in rects.size():
			var r := rects[i]
			check(r.position.x >= 0.0 and r.end.x <= ShopPanel.ROW_WIDTH + 0.01, "inside the row: %s" % r)
			check_eq(r.size.y <= ConsumableCard.HEIGHT + 0.01, true, "no taller than the row")
			if i > 0:
				check(r.position.x >= rects[i - 1].end.x + ShopPanel.CARD_GAP - 0.01, "gap between cards %d and %d" % [i - 1, i])
			right = maxf(right, r.end.x)
		if bm:
			check_eq(rects[4].size, ShopOfferCard.WIDE_SIZE, "the Black Market card keeps its size")
			check_near(rects[4].end.x, ShopPanel.ROW_WIDTH, 0.01, "at the right end")
		else:
			check_near(rects[3].end.x, ShopPanel.ROW_WIDTH, 4.0, "the cards use the row's width")
	check_eq(ShopPanel.extras_layout(0, true).size(), 1, "the Black Market card alone")
	check(ShopPanel.extras_layout(0, false).is_empty(), "nothing")


# --- The cursor space --------------------------------------------------------------------------

func test_the_cursor_walks_from_the_grid_into_the_row_and_back() -> void:
	_open(15)
	check_eq(panel.columns, 3, "6 offers: 3 columns")
	var n := panel.offer_count()
	check_eq(n, 6, "two players, six offers")
	# P1 starts top-left; two steps down reach the bottom row, a third goes into the row.
	_nudge(p1, Vector2.DOWN)
	check_eq(panel.cursor_of(0), 3, "second grid row")
	_nudge(p1, Vector2.DOWN)
	check(panel.is_consumable_index(panel.cursor_of(0)), "below the grid: the consumables row")
	# The card nearest in x: the left grid column (x = -132 from the middle) is closest to the second
	# of five row cells (centres -274, -161, -48, 65, 226 from the middle with the Black Market).
	check_eq(panel.cursor_of(0), _cons(1), "the left column goes to the nearest card")
	_nudge(p1, Vector2.DOWN)
	check_eq(panel.cursor_of(0), _cons(1), "the row is the bottom: down stays")
	_nudge(p1, Vector2.LEFT)
	check_eq(panel.cursor_of(0), _cons(0), "left inside the row")
	_nudge(p1, Vector2.RIGHT)
	_nudge(p1, Vector2.RIGHT)
	_nudge(p1, Vector2.RIGHT)
	check_eq(panel.cursor_of(0), _cons(3), "the last consumables card")
	_nudge(p1, Vector2.RIGHT)
	check(panel.is_black_market_index(panel.cursor_of(0)), "then the Black Market card")
	_nudge(p1, Vector2.RIGHT)
	check(panel.is_black_market_index(panel.cursor_of(0)), "the end of the row: stays")
	_nudge(p1, Vector2.UP)
	check(panel.cursor_of(0) < n, "up from the Black Market: back into the grid")
	check_eq(panel.cursor_of(0), 5, "the card above it (right column of the bottom row)")
	_nudge(p1, Vector2.UP)
	check_eq(panel.cursor_of(0), 2, "the grid goes on up")
	# From the middle column the nearest consumables card is under it.
	panel.set_cursor(0, 4)
	_nudge(p1, Vector2.DOWN)
	var below := panel.cursor_of(0)
	check(panel.is_consumable_index(below), "the middle column: into the row")
	_nudge(p1, Vector2.UP)
	check_eq(panel.cursor_of(0), 4, "and back up to the same column")
	# The left edge of the row stays.
	panel.set_cursor(0, _cons(0))
	_nudge(p1, Vector2.LEFT)
	check_eq(panel.cursor_of(0), _cons(0), "left edge: stays")
	# Before wave 15 the row ends with the last consumables card.
	shop.open_round(8, PlayerManager.get_slots(), rng)
	panel.set_cursor(0, _cons(3))
	_nudge(p1, Vector2.RIGHT)
	check_eq(panel.cursor_of(0), _cons(3), "no Black Market: the row ends")
	check_eq(panel.slot_count(), n + 4, "the cursor space shrank with it")


func test_a_cursor_on_a_vanished_card_is_clamped() -> void:
	_open(15)
	panel.set_cursor(0, _cons(2))
	panel.refresh(PlayerManager.get_slots())
	check_eq(panel.cursor_of(0), _cons(2), "a cursor on the row survives a refresh")
	panel.set_cursor(0, panel.black_market_index())
	shop.open_round(9, PlayerManager.get_slots(), rng)
	panel.refresh(PlayerManager.get_slots())
	check(panel.cursor_of(0) <= panel.slot_count() - 1, "the Black Market is gone: the cursor stays on a card")
	check(panel.card_at(panel.cursor_of(0)) != null, "on a real card")


# --- Buying consumables ------------------------------------------------------------------------

func test_a_buys_a_consumable_for_the_players_own_hero() -> void:
	_open(8)
	RunState.begin_spend_round()
	RunState.add_gold(300)
	panel.set_cursor(1, _cons(2))
	var card := shop.consumables[2]
	_tap(p2, PlayerInput.Pad.A)
	check_eq(RunState.gold, 300 - card.price, "paid from the shared wallet")
	check(Consumables.of_kind(_hero(1).consumables_pending, card.data.kind) == card.data, "P2's hero holds it")
	check(_hero(0).consumables_pending.is_empty(), "P1's hero does not")
	check_eq(bought_consumables, [card.data] as Array[ConsumableData], "consumable_bought")
	check(bought_items.is_empty(), "not an item purchase")
	check_eq(RunState.spend_log[0]["kind"], &"consumable", "logged as a consumable")
	check_eq(RunState.consumables_bought, 1, "counted")
	check_eq(panel.feedback_lines()[-1], "P2 bought [%s] – %d g" % [card.data.display_name, card.price], "feedback")
	check(panel.consumable_cards[2].offer == card, "the card stays: unlimited stock")
	_tap(p2, PlayerInput.Pad.A)
	check_eq(RunState.gold, 300 - 2 * card.price, "the same card can be bought again")
	check(panel.feedback_lines()[-1].ends_with("(replaces [%s])" % card.data.display_name), "the pending copy was replaced: %s" % [panel.feedback_lines()])


func test_a_newer_potion_replaces_the_pending_one_with_a_note() -> void:
	_open(8)
	RunState.add_gold(300)
	var potions: Array[int] = []
	for j in shop.consumables.size():
		if shop.consumables[j].data.is_potion():
			potions.append(j)
	check(potions.size() >= 2, "the row has two potions (it always has at least one; fill the rest)")
	if potions.size() < 2:
		return
	panel.set_cursor(0, _cons(potions[0]))
	_tap(p1, PlayerInput.Pad.A)
	panel.set_cursor(0, _cons(potions[1]))
	_tap(p1, PlayerInput.Pad.A)
	check_eq(_hero(0).consumables_pending.size(), 1, "still one potion")
	check(_hero(0).consumables_pending[0] == shop.consumables[potions[1]].data, "the newer one")
	check("(replaces [%s])" % shop.consumables[potions[0]].data.display_name in panel.feedback_lines()[-1], "the note names the old one")


func test_consumable_purchases_say_why_not() -> void:
	_open(8)
	panel.set_cursor(0, _cons(0))
	_tap(p1, PlayerInput.Pad.A)
	check("P1: Not enough gold" in panel.feedback_lines(), "poor: %s" % [panel.feedback_lines()])
	check(_hero(0).consumables_pending.is_empty(), "nothing given")
	check_eq(RunState.consumables_bought, 0, "nothing counted")
	check_eq(panel.buy_block_reason(PlayerManager.get_slot(0), _cons(0)), "Not enough gold", "buy_block_reason")
	RunState.add_gold(200)
	check_eq(panel.buy_block_reason(PlayerManager.get_slot(0), _cons(0)), "", "affordable")
	check_eq(panel.buy_block_reason(null, _cons(0)), "No hero to carry it", "no slot")


func test_a_consumable_over_half_the_wallet_needs_a_held_a() -> void:
	_open(8)
	var card := shop.consumables[0]
	RunState.add_gold(card.price + 2)  # the price is far more than half
	panel.set_cursor(0, _cons(0))
	p1.press(PlayerInput.Pad.A)
	_step()
	check(_hero(0).consumables_pending.is_empty(), "not on the press")
	for i in 30:
		_step()
	check_near(panel.hold_progress(0), 0.5, 0.03, "half-way")
	p1.release(PlayerInput.Pad.A)
	_step()
	check_eq(panel.hold_progress(0), 0.0, "released early: cancelled")
	check(_hero(0).consumables_pending.is_empty(), "no purchase")
	p1.press(PlayerInput.Pad.A)
	_step()
	for i in 62:
		_step()
	p1.release(PlayerInput.Pad.A)
	_step()
	check(Consumables.of_kind(_hero(0).consumables_pending, card.data.kind) == card.data, "held for a second: bought")
	check_eq(RunState.gold, 2, "paid")


func test_a_reroll_cancels_a_consumable_hold() -> void:
	_open(8)
	RunState.add_gold(shop.consumables[0].price + 2)
	panel.set_cursor(0, _cons(0))
	p1.press(PlayerInput.Pad.A)
	_step()
	for i in 20:
		_step()
	check(panel.hold_progress(0) > 0.2, "holding")
	RunState.add_gold(200)
	shop.reroll_votes = {0: true, 1: true}
	check(shop.try_reroll([0, 1] as Array[int], rng), "the stall was rerolled")
	_step()
	check_eq(panel.hold_progress(0), 0.0, "the row changed under the hold: cancelled")


# --- Black Market through the panel --------------------------------------------------------------

func test_a_buys_the_black_market_offer() -> void:
	_open(16)
	var o := shop.black_market
	RunState.begin_spend_round()
	RunState.add_gold(o.price + 5)  # the price is more than half the wallet
	panel.set_cursor(0, panel.black_market_index())
	var eq := ShopPanel.equipment_of(PlayerManager.get_slot(0))
	if o.item.is_weapon() or not eq.has_space():
		o.item = ItemGenerator.generate(ItemGenerator.Source.LOOT, 16, rng, {&"rarity": Items.Rarity.EPIC, &"slot_type": Items.SlotType.HEAD})
		panel.refresh(PlayerManager.get_slots())
	p1.press(PlayerInput.Pad.A)
	_step()
	check(not o.sold, "it costs more than half the wallet: a held A")
	for i in 62:
		_step()
	p1.release(PlayerInput.Pad.A)
	_step()
	check(o.sold, "sold after the hold")
	check(eq.backpack.has(o.item), "in P1's backpack")
	check_eq(bought_items.size(), 1, "item_bought")
	check_eq(RunState.spend_log[0]["kind"], &"black_market", "spend kind black_market")
	check_eq(RunState.black_market_bought, 1, "counted")
	check("at the Black Market" in panel.feedback_lines()[-1], "feedback names it: %s" % [panel.feedback_lines()])
	check(panel.black_market_card._content.modulate.a < 0.5, "the card is dimmed (SOLD)")


func test_x_and_r3_work_on_the_black_market_but_not_on_consumables() -> void:
	_open(16)
	panel.set_cursor(0, panel.black_market_index())
	_tap(p1, PlayerInput.Pad.X)
	check(shop.black_market.locked_by == 0 and panel.black_market_card._lock.visible, "P1 locked the Black Market offer")
	check("locked" in panel.feedback_lines()[-1], "feedback: %s" % [panel.feedback_lines()])
	_tap(p2, PlayerInput.Pad.X)  # P2's cursor is on an item: nothing to do with the Black Market
	check(shop.black_market.locked_by == 0, "P2's lock went to its own card")
	panel.set_cursor(1, panel.black_market_index())
	_tap(p2, PlayerInput.Pad.R3)
	check(1 in shop.black_market.pinged_by, "P2 pinged it")
	check("P2 wants:" in panel.feedback_lines()[-1], "ping feedback")
	var lines := panel.feedback_lines().size()
	panel.set_cursor(0, _cons(0))
	_tap(p1, PlayerInput.Pad.X)
	_tap(p1, PlayerInput.Pad.R3)
	check_eq(panel.feedback_lines().size(), lines, "consumables cannot be locked or pinged: silent")
	check(shop.black_market.locked_by == 0, "nothing changed")


## [param node]'s rectangle in [param card]'s coordinates (after a layout pass).
func _local(card: Control, node: Control) -> Rect2:
	return Rect2(node.get_global_rect().position - card.get_global_rect().position, node.size)


func test_the_black_market_lock_badge_does_not_cover_the_name() -> void:
	_open(16)
	var card := panel.black_market_card
	var slots := PlayerManager.get_slots()
	for display in ["Ring", "Stormforged Dreadplate of the Eternal Vigil"]:
		card.offer.item.display_name = display
		card.set_offer(card.offer, slots)
		shop.black_market.locked_by = 0
		panel.refresh(slots)
		_layout(panel)
		check(card._lock.visible, "locked")
		var badge := card.lock_badge_rect()
		var name_rect := _local(card, card.name_label)
		check(badge.size.x > 0.0 and Rect2(Vector2.ZERO, card.size).encloses(badge), "the badge is on the card: %s" % badge)
		check(not name_rect.intersects(badge), "the name %s does not reach the padlock %s (%s)" % [name_rect, badge, display])
		check(name_rect.end.x <= badge.position.x, "the name ends left of the badge")
		check(not _local(card, card.icon).intersects(badge), "the icon is clear of the badge")
		shop.black_market.locked_by = -1
		panel.refresh(slots)
		_layout(panel)
		check(not card._lock.visible, "unlocked")
		check(not _local(card, card.name_label).intersects(badge), "the width stays reserved while unlocked (no re-wrap)")


func test_black_market_ping_tags_stay_off_the_icon_and_the_name() -> void:
	_open(16)
	var card := panel.black_market_card
	var slots := PlayerManager.get_slots()
	card.offer.item.display_name = "Stormforged Dreadplate of the Eternal Vigil"
	shop.black_market.locked_by = 0
	var card_rect := Rect2(Vector2.ZERO, card.size)
	var pips_top := card.size.y - 23.0
	for n in [1, 2, 3, 4]:
		shop.black_market.pinged_by.clear()
		for slot_index in n:
			shop.black_market.pinged_by.append(slot_index)
		panel.refresh(slots)
		_layout(panel)
		var tags := card.ping_tags()
		check_eq(tags.size(), n, "%d tags" % n)
		var covered: Array[Rect2] = [_local(card, card.icon), _local(card, card.name_label), card.lock_badge_rect(),
				_local(card, card._coin), _local(card, card.price_label)]
		var seen: Array[Rect2] = []
		for entry in tags:
			var r: Rect2 = entry["rect"]
			check(card_rect.encloses(r), "%d pings: %s is inside the card" % [n, r])
			check(r.position.x >= card.icon.size.x + 6.0, "%d pings: %s starts right of the icon" % [n, r])
			check(r.end.y <= pips_top, "%d pings: %s is above the pip strip" % [n, r])
			for c in covered:
				check(not r.intersects(c), "%d pings: %s covers %s" % [n, r, c])
			for other in seen:
				check(not r.intersects(other), "%d pings: tags overlap each other" % n)
			seen.append(r)
		check_eq(tags[0]["text"], "P1 wants" if n == 1 else "P1", "%d pings: the full text only while it fits" % n)
		var last: Rect2 = tags[n - 1]["rect"]
		check(last.end.x <= card.size.x - 6.0 + 0.01, "%d pings: the row fits the card (ends at %.1f)" % [n, last.end.x])
	# The stacked card keeps its column under the cursor corner tags.
	var stacked := panel.cards[0]
	shop.offers[0].pinged_by.clear()
	shop.offers[0].pinged_by.append(0)
	shop.offers[0].pinged_by.append(1)
	panel.refresh(slots)
	var column := stacked.ping_tags()
	check_eq(column.size(), 2, "two stacked tags")
	check_eq((column[0]["rect"] as Rect2).position, Vector2(4, 14), "the first tag, as before")
	check_eq((column[1]["rect"] as Rect2).position, Vector2(4, 37), "the second one below it")
	check_eq(column[1]["text"], "P2 wants", "the full text")


# --- Tooltips ----------------------------------------------------------------------------------

func test_a_consumable_gets_its_own_tooltip_and_the_black_market_the_item_tooltip() -> void:
	_open(16)
	_layout(panel)
	var card := shop.consumables[1]
	panel.set_cursor(0, _cons(1))
	panel._process(DT)
	var ctip := panel._cons_tooltips[0]
	check(ctip.visible and not panel.tooltip_of(0).visible, "the consumable tooltip replaces the item tooltip")
	check(ctip.find_line(card.data.display_name, true) != null, "name")
	for line in Consumables.effect_lines(card.data):
		check(ctip.find_line(line, true) != null, "effect line '%s'" % line)
	check(ctip.find_line("Price:") != null, "price")
	check(ctip.find_line("Replaces:") == null, "nothing pending: no replace note")
	check(ctip.find_line("P1", true) != null, "owner tag")
	# With a pending consumable of that kind the tooltip says what it replaces.
	var other := Db.get_consumable(&"elixir_of_swiftness" if card.data.id != &"elixir_of_swiftness" else &"flask_of_fury")
	if other.kind == card.data.kind:
		Consumables.give(_hero(0), other)
		panel._tooltip_keys.clear()
		panel._process(DT)
		check(ctip.find_line("Replaces: %s" % other.display_name, true) != null, "Replaces: <the pending one>")
	var r := Rect2(ctip.global_position, ctip.get_combined_minimum_size().max(ctip.size) * ctip.scale)
	var inside := false
	for a in panel.tooltip_areas():
		inside = inside or a.grow(1.0).encloses(r)
	check(inside, "placed on the stall or in a free band: %s" % r)
	check(not r.intersects(panel.card_at(_cons(1)).get_global_rect()), "does not cover its own card")
	# The Black Market card: the normal item tooltip with the Black Market price.
	panel.set_cursor(0, panel.black_market_index())
	panel._process(DT)
	var tip := panel.tooltip_of(0)
	check(tip.visible and not ctip.visible, "the item tooltip is back")
	check(tip.item == shop.black_market.item, "shows the Black Market item")
	check_eq(tip.price, shop.black_market.price, "at the Black Market price")
	check(tip.find_line("Price:") != null, "price line")


func test_consumable_tooltip_fills_the_kind_colours() -> void:
	var tip := ConsumableTooltip.create_consumable()
	nodes.append(tip)
	tree.root.add_child(tip)
	tip.show_consumable(Db.get_consumable(&"hearty_onion_stew"), 17, Db.get_consumable(&"smoked_boar_ribs"))
	check(tip.visible and tip.consumable == Db.get_consumable(&"hearty_onion_stew"), "shown")
	check(tip.find_line("Food – lasts one wave") != null, "kind line")
	check(tip.find_line("+15% Max HP", true) != null and tip.find_line("+5 Spirit", true) != null, "effects")
	check(tip.find_line("Replaces: Smoked Boar Ribs", true) != null, "replace note")
	check(tip.find_line("17") != null, "price")
	tip.show_consumable(null, 0)
	check(not tip.visible, "null hides it")


# --- Unit frame ---------------------------------------------------------------------------------

func test_the_unit_frame_shows_the_active_consumables_as_small_icons() -> void:
	var hero := _hero(0)
	var frame := UnitFrame.create(0)
	nodes.append(frame)
	tree.root.add_child(frame)
	frame.bind(hero)
	check(frame.shown_consumables().is_empty(), "none at first")
	Consumables.give(hero, Db.get_consumable(&"flask_of_fury"))
	Consumables.give(hero, Db.get_consumable(&"smoked_boar_ribs"))
	check(frame.shown_consumables().is_empty(), "pending ones are not on the frame (the market covers it)")
	hero.begin_wave()
	var shown := frame.shown_consumables()
	check_eq(shown.size(), 2, "both active ones")
	check(shown[0] == Db.get_consumable(&"flask_of_fury") and shown[1] == Db.get_consumable(&"smoked_boar_ribs"), "potion first")
	for c in frame.consumable_icons.get_children():
		check(c is ConsumableIcon and (c as ConsumableIcon).custom_minimum_size == Vector2(UnitFrame.CONSUMABLE_ICON_SIZE, UnitFrame.CONSUMABLE_ICON_SIZE), "small icons")
	hero.end_wave()
	check(frame.shown_consumables().is_empty(), "gone with the wave")
	var mirrored := UnitFrame.create(1, true)
	nodes.append(mirrored)
	tree.root.add_child(mirrored)
	mirrored.bind(_hero(1))
	Consumables.give(_hero(1), Db.get_consumable(&"elixir_of_fortune"))
	_hero(1).begin_wave()
	check_eq(mirrored.shown_consumables().size(), 1, "right-hand frames too")
	mirrored.unbind()
	check(mirrored.shown_consumables().is_empty(), "unbinding clears the icons")


# --- Purse board ----------------------------------------------------------------------------------

func test_the_purse_board_names_the_new_spends() -> void:
	check_eq(PurseBoard.spend_label({"kind": &"black_market", "label": "Robes of the Arcane"}), "[Robes of the Arcane]", "Black Market item in brackets")
	check_eq(PurseBoard.spend_label({"kind": &"black_market", "label": "Axe (forged)"}), "[Axe] (forged)", "forged")
	check_eq(PurseBoard.spend_label({"kind": &"consumable", "label": "Flask of Fury"}), "Flask of Fury", "a consumable as it is")
	_open(16)
	panel.set_cursor(0, panel.black_market_index())
	shop.toggle_ping(Shop.BLACK_MARKET, 0)
	var wants := PurseBoard.merged_wants(shop, [] as Array[Dictionary])
	var found := false
	for w in wants:
		if w["item"] == shop.black_market.item and int(w["slot"]) == 0 and int(w["price"]) == shop.black_market.price:
			found = true
	check(found, "a Black Market ping is a want")
	Intermission.drop_shop_pings(shop, 0)
	check(not shop.black_market.is_pinged(), "a leaving player's Black Market ping is dropped")
	check(PurseBoard.merged_wants(shop, [] as Array[Dictionary]).is_empty(), "no wants left")


# --- The 4-player stall at both window sizes -------------------------------------------------------

## Frees whatever the test already built (the two heroes of before_each included: leftover
## heroes would stay in the "players" group and disturb every later test).
func _free_scene() -> void:
	UiFakes.free_node(panel)
	UiFakes.free_node(screen)
	UiFakes.free_node(world)
	panel = null
	screen = null
	world = null


func _four_player_screen() -> void:
	_free_scene()
	UiFakes.reset_players()
	RunState.start_run(4, 9)
	RunState.set_wave(15)
	world = MarketFakes.make_world(tree)
	var classes: Array[StringName] = [&"warrior", &"warlock", &"paladin", &"mage"]
	for i in 4:
		MarketFakes.human_with_hero(world, "pad:%d" % i, classes[i])
	screen = Intermission.create()
	tree.root.add_child(screen)


## The market for 4 players: the 5 x 2 grid, the consumables row and the Black Market card sit
## inside the stall body, never overlap each other, the shop's cursor positions all have a card, and
## the counter is big enough for its content (it did not have to grow past the stall). Checked at the
## 1920 x 1080 root and the 1280 x 720 window (the same canvas, scaled).
func test_the_four_player_stall_fits_both_window_sizes() -> void:
	_async = true
	for size in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		_four_player_screen()
		tree.root.size = size
		screen.open(15, 0)
		await tree.process_frame
		await tree.process_frame
		var label := "%dx%d" % [size.x, size.y]
		check_eq(screen.phase, Intermission.Phase.MARKET, "%s: market" % label)
		check_eq(screen.get_viewport_rect().size, Vector2(1920, 1080), "%s: the canvas is 1920 x 1080" % label)
		var sp := screen.shop_panel
		check_eq(sp.offer_count(), 10, "%s: ten offers" % label)
		check_eq(sp.columns, 5, "%s: 5 columns" % label)
		check_eq(sp.consumable_cards.size(), 4, "%s: four consumables" % label)
		check(sp.black_market_card != null, "%s: Black Market card" % label)
		var col := sp._body.get_child(0)
		var counter: Control = col.get_child(1)
		check(counter.get_combined_minimum_size().y <= counter.size.y + 0.5,
			"%s: the counter holds its content (%s <= %s)" % [label, counter.get_combined_minimum_size().y, counter.size.y])
		var body := sp._body.get_global_rect()
		var stall := sp.get_global_rect()
		check(stall.position.y >= screen.header.get_global_rect().end.y - 1.0, "%s: the stall starts under the header" % label)
		check(stall.end.y <= screen.chips_row.get_global_rect().position.y + 6.0, "%s: and ends above the ready chips" % label)
		check(body.end.y <= stall.end.y + 0.5, "%s: the body ends inside the stall (%s vs %s)" % [label, body.end.y, stall.end.y])
		var rects: Array[Rect2] = []
		for i in sp.slot_count():
			var c := sp.card_at(i)
			check(c != null and c.is_visible_in_tree(), "%s: card %d exists" % [label, i])
			var r := c.get_global_rect()
			check(counter.get_global_rect().grow(0.5).encloses(r), "%s: card %d inside the counter: %s" % [label, i, r])
			for other in rects:
				check(not other.intersects(r), "%s: card %d overlaps another: %s vs %s" % [label, i, r, other])
			rects.append(r)
		check_eq(rects.size(), 10 + 4 + 1, "%s: 15 cursor positions" % label)
		# The stall stays clear of the corner panels in the middle column.
		for panel_node: PlayerPanel in screen.panels.values():
			var pr := panel_node.get_global_transform() * Rect2(Vector2.ZERO, panel_node.size)
			check(not pr.intersects(Rect2(stall.position + Vector2(10, 0), stall.size - Vector2(20, 0))), "%s: the corner panel %s is clear of the stall" % [label, pr])
		_free_scene()
	finished.emit()


func test_the_four_player_cursors_reach_every_card_and_tooltips_stay_inside() -> void:
	_async = true
	_four_player_screen()
	tree.root.size = Vector2i(1920, 1080)
	screen.open(15, 0)
	await tree.process_frame
	await tree.process_frame
	var sp := screen.shop_panel
	var areas := sp.tooltip_areas()
	for i in sp.slot_count():
		for slot_index in 4:
			sp.set_cursor(slot_index, i)
		sp._process(DT)
		for slot_index in 4:
			var tip: ItemTooltip = sp._shown_tooltip(slot_index)
			check(tip != null and tip.visible, "P%d has a tooltip on position %d" % [slot_index + 1, i])
			if tip == null:
				continue
			var r := Rect2(tip.global_position, tip.get_combined_minimum_size().max(tip.size) * tip.scale)
			var inside := false
			for a in areas:
				inside = inside or a.grow(1.0).encloses(r)
			check(inside, "P%d tooltip on position %d inside the stall or a free band: %s" % [slot_index + 1, i, r])
	finished.emit()


# --- Bots ------------------------------------------------------------------------------------------

func _bot_market(cleared_wave: int, gold: int, classes: Array[StringName]) -> void:
	_free_scene()
	UiFakes.reset_players()
	RunState.start_run(classes.size(), 7)
	RunState.set_wave(cleared_wave)
	RunState.add_gold(gold)
	world = MarketFakes.make_world(tree)
	for i in classes.size():
		MarketFakes.bot_with_hero(world, "bot:%d" % i, classes[i])
	screen = Intermission.create()
	screen.bot_shopping = true
	tree.root.add_child(screen)
	screen.open(cleared_wave, 0)


func test_bots_buy_no_consumables_before_wave_6() -> void:
	_bot_market(5, 5000, [&"warrior", &"mage"] as Array[StringName])
	check_eq(screen.shop_panel.consumable_count(), 4, "the row is there")
	check_eq(screen._bots_consumables(), 0, "wave 5: nothing")
	check_eq(RunState.consumables_bought, 0, "none counted")
	for s in PlayerManager.get_slots():
		check((s.player as Player).consumables_pending.is_empty(), "no pending consumable")


func test_bots_buy_a_potion_and_a_food_each_from_wave_6() -> void:
	_bot_market(6, 5000, [&"warrior", &"mage"] as Array[StringName])
	var gold := RunState.gold
	var n := screen._bots_consumables()
	var expected := 0
	for kind in [ConsumableData.Kind.POTION, ConsumableData.Kind.FOOD]:
		if Intermission.bot_consumable_choice(screen.shop_panel.shop, kind) >= 0:
			expected += 2
	check(n > 0 and n == RunState.consumables_bought, "bought %d (counted %d)" % [n, RunState.consumables_bought])
	check(RunState.gold < gold, "paid")
	for s in PlayerManager.get_slots():
		var hero := s.player as Player
		check(hero.consumables_pending.size() <= 2, "at most a potion and a food")
		check(Consumables.of_kind(hero.consumables_pending, ConsumableData.Kind.POTION) != null, "%s holds a potion" % s.label())
	# The stock is unlimited, so both bots take the row's best of each kind (see
	# test_every_bot_takes_the_same_best_potion_and_food); a row without any food leaves the foods out.
	check(n >= 2 and n <= expected + 2, "one potion each at least")
	check_eq(screen._bots_consumables(), 0, "a second pass buys nothing: everybody holds one of each kind")


func test_every_bot_takes_the_same_best_potion_and_food() -> void:
	# Unlimited stock + a choice that does not depend on the bot: four bots, one row, one potion and
	# one food for all of them (the _bots_consumables doc says so; the wallet is the only limit).
	_bot_market(10, 20000, [&"warrior", &"mage", &"paladin", &"rogue"] as Array[StringName])
	var stall := screen.shop_panel.shop
	stall.consumables.clear()
	for id in [&"elixir_of_fortune", &"smoked_boar_ribs", &"flask_of_fury", &"hearty_onion_stew"]:
		var c := Shop.ConsumableOffer.new()
		c.data = Db.get_consumable(id)
		c.price = Consumables.price(c.data, 10)
		stall.consumables.append(c)
	screen.shop_panel.refresh(PlayerManager.get_slots())
	check_eq(screen._bots_consumables(), 8, "a potion and a food for each of the four bots")
	for s in PlayerManager.get_slots():
		var hero := s.player as Player
		var ids: Array[StringName] = []
		for c in hero.consumables_pending:
			ids.append(c.id)
		check_eq(ids, [&"flask_of_fury", &"hearty_onion_stew"] as Array[StringName], "%s: the best potion and the best food, as everybody else" % s.label())


func test_bots_pick_by_priority_and_only_with_the_reserve() -> void:
	_bot_market(8, 5000, [&"warrior"] as Array[StringName])
	var stall := screen.shop_panel.shop
	# A row we control: the potion priority is Fury > Ironskin > Swiftness > Fortune, foods Stew > Ribs > Rings.
	stall.consumables.clear()
	for id in [&"elixir_of_fortune", &"elixir_of_ironskin", &"spiced_onion_rings", &"smoked_boar_ribs"]:
		var c := Shop.ConsumableOffer.new()
		c.data = Db.get_consumable(id)
		c.price = Consumables.price(c.data, 8)
		stall.consumables.append(c)
	check_eq(stall.consumables[Intermission.bot_consumable_choice(stall, ConsumableData.Kind.POTION)].data.id, &"elixir_of_ironskin", "Ironskin beats Fortune")
	check_eq(stall.consumables[Intermission.bot_consumable_choice(stall, ConsumableData.Kind.FOOD)].data.id, &"smoked_boar_ribs", "Ribs beat Rings")
	check_eq(Intermission.bot_consumable_choice(stall, ConsumableData.Kind.FOOD), 3, "row index")
	check_eq(Intermission.bot_consumable_choice(null, ConsumableData.Kind.FOOD), -1, "no stall")
	screen.shop_panel.refresh(PlayerManager.get_slots())
	RunState.gold = 0
	RunState.add_gold(Intermission.bot_train_reserve(8, 1) + 3)  # cannot pay one and keep the reserve
	check_eq(screen._bots_consumables(), 0, "the reserve is kept: nothing bought")
	RunState.gold = 0
	RunState.add_gold(Intermission.bot_train_reserve(8, 1) + 200)
	check_eq(screen._bots_consumables(), 2, "with gold above the reserve: a potion and a food")
	var hero := PlayerManager.get_slot(0).player as Player
	check(Consumables.of_kind(hero.consumables_pending, ConsumableData.Kind.POTION).id == &"elixir_of_ironskin", "the potion it chose")
	check(Consumables.of_kind(hero.consumables_pending, ConsumableData.Kind.FOOD).id == &"smoked_boar_ribs", "the food it chose")
	check(RunState.gold >= Intermission.bot_train_reserve(8, 1), "the reserve is still there")


func test_bots_buy_the_black_market_offer_only_when_it_is_an_upgrade_and_affordable() -> void:
	_bot_market(16, 20000, [&"warrior"] as Array[StringName])
	var stall := screen.shop_panel.shop
	var hero := PlayerManager.get_slot(0).player as Player
	var eq := hero.equipment
	# Make the offer a clear upgrade: a rich Epic head piece the empty slot welcomes.
	var item := ItemGenerator.generate(ItemGenerator.Source.LOOT, 16, rng, {&"rarity": Items.Rarity.EPIC, &"slot_type": Items.SlotType.HEAD, &"usable_by": hero.class_data})
	stall.black_market.item = item
	screen.shop_panel.refresh(PlayerManager.get_slots())
	var price := stall.black_market.price
	check(Intermission.is_bot_upgrade(item, PlayerManager.get_slot(0), eq), "an upgrade for the warrior")
	# Too poor to keep the reserve afterwards.
	RunState.gold = 0
	RunState.add_gold(price + 5)
	check_eq(screen._bots_black_market(), 0, "not affordable after the reserve")
	check(not stall.black_market.sold, "still for sale")
	# Not an upgrade: nobody wants it.
	RunState.gold = 0
	RunState.add_gold(20000)
	var junk := ItemGenerator.generate(ItemGenerator.Source.SHOP, 3, rng, {&"rarity": Items.Rarity.COMMON, &"slot_type": Items.SlotType.HEAD, &"usable_by": hero.class_data})
	var worn := ItemGenerator.generate(ItemGenerator.Source.LOOT, 16, rng, {&"rarity": Items.Rarity.EPIC, &"slot_type": Items.SlotType.HEAD, &"usable_by": hero.class_data})
	eq.slots[Items.EquipSlot.HEAD] = worn
	stall.black_market.item = junk
	screen.shop_panel.refresh(PlayerManager.get_slots())
	check(not Intermission.is_bot_upgrade(junk, PlayerManager.get_slot(0), eq), "junk is no upgrade")
	check_eq(screen._bots_black_market(), 0, "not an upgrade: not bought")
	check(not stall.black_market.sold, "still for sale")
	# An upgrade the bot can afford: bought and worn.
	eq.slots.erase(Items.EquipSlot.HEAD)
	stall.black_market.item = item
	screen.shop_panel.refresh(PlayerManager.get_slots())
	var gold := RunState.gold
	check_eq(screen._bots_black_market(), 1, "bought")
	check(stall.black_market.sold, "sold")
	check_eq(RunState.gold, gold - price, "paid the Black Market price")
	check(eq.get_item(Items.EquipSlot.HEAD) == item, "and worn at once")
	check_eq(RunState.black_market_bought, 1, "counted")
	check_eq(screen._bots_black_market(), 0, "a sold offer is not bought again")


func test_the_bot_pass_runs_both_new_steps_in_the_market() -> void:
	# The whole _bots_shop with real offers: from wave 6 consumables, from wave 15 the Black Market.
	_bot_market(16, 20000, [&"warrior", &"mage"] as Array[StringName])
	screen._bots_shop()
	check(RunState.consumables_bought > 0, "consumables bought in the bot pass")
	check(RunState.spend_log.any(func(e: Dictionary) -> bool: return e["kind"] == &"consumable"), "and logged")
