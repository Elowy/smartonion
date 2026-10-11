extends TestCase
## Forging in the UI (GDD 4.1): the character panel's Forge entry through the P0 wiring
## (enabled with "→ Rare", forges, "Forged [..]!", selects the result; Legendary greyed out),
## the shop's auto-forge with a full backpack (no "Backpack full", "P1 bought and forged [..]"
## in the log, the forged weapon reported), anvil pips per player on the offer cards, and the
## Intermission bots: they forge before buying (Forge.bot_forge_all) and never reach the
## shop's auto-forge (they make room first).

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0


## A real Shop whose rounds always show the given stock (no random offers).
class StockedShop extends Shop:
	var stock_items: Array[ItemInstance] = []
	var stock_prices: Array[int] = []

	func stock(items: Array[ItemInstance], prices: Array[int]) -> void:
		stock_items = items
		stock_prices = prices
		offers.clear()
		for i in items.size():
			var o := Shop.Offer.new()
			o.item = items[i]
			o.price = prices[i]
			o.item.buy_price = o.price
			offers.append(o)
		changed.emit()

	func open_round(p_wave: int, _slots: Array[PlayerSlot], _rng: RandomNumberGenerator) -> void:
		wave = p_wave
		reroll_votes.clear()
		rerolls_this_round = 0
		stock(stock_items, stock_prices)


var world: Node3D
var nodes: Array[Node] = []


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(2, 13)
	world = MarketFakes.make_world(tree)
	nodes.clear()


func after_each() -> void:
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()
	UiFakes.free_node(world)
	world = null
	RunState.start_run(1, 1)
	UiFakes.reset_players()


func _hero(slot: PlayerSlot) -> Player:
	return slot.player as Player


## Junk only a Mage may use (a warrior / paladin bot never wears it, so it sells it first).
static func _mage_junk(i: int) -> ItemInstance:
	var it := MarketFakes.make_item("Mage Robe %d" % i, Items.SlotType.CHEST, ClassData.ArmorType.CLOTH)
	it.class_restriction = &"mage"
	return it


static func _fill(eq: Equipment) -> void:
	var i := 0
	while eq.has_space():
		eq.add_to_backpack(_mage_junk(i))
		i += 1


# --- Character panel -----------------------------------------------------------------------

func _panel(slot: PlayerSlot) -> PlayerPanel:
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	nodes.append(panel)
	panel.set_input_focus(true)
	return panel


func _press_a(panel: PlayerPanel, slot: PlayerSlot) -> void:
	var input := slot.input as UiFakes.HumanInput
	input.press(PlayerInput.Pad.A)
	input.poll(DT)
	panel.handle_input(input)
	input.release(PlayerInput.Pad.A)
	input.poll(0.0)
	panel.handle_input(input)


func test_panel_forge_entry_forges_and_selects_the_result() -> void:
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	var slot := PlayerManager.get_slot(0)
	var hero := _hero(slot)
	var eq := hero.equipment
	var sword := eq.get_item(Items.EquipSlot.MAIN_HAND)
	var spare := ItemInstance.from_weapon(Db.get_weapon(&"sword"))
	eq.add_to_backpack(spare)
	var panel := _panel(slot)
	panel.select_backpack(0)
	panel.open_menu()
	check(Array(panel.menu_labels()).has("Forge"), "Forge entry")
	check(panel.menu_entry_enabled("Forge"), "enabled: the equipped sword is a partner")
	check_eq(panel.menu_entry_detail("Forge"), "→ Uncommon", "the result's rarity as the detail")
	check(panel.select_menu_entry("Forge"), "cursor on Forge")
	_press_a(panel, slot)
	var result := eq.get_item(Items.EquipSlot.MAIN_HAND)
	check(result != sword and result.rarity == Items.Rarity.UNCOMMON, "an Uncommon sword in the main hand")
	check(eq.backpack.is_empty(), "both Common swords are gone")
	check_eq(panel.last_message, "Forged %s!" % result.display_name, "the success message")
	check_eq(panel.selected_equip_slot(), Items.EquipSlot.MAIN_HAND, "the result is selected")
	check(not panel.is_menu_open(), "the menu closed")
	check(hero.main_hand == result.weapon, "the hero swings the new sword")
	check_eq(RunState.weapons_forged, 1, "counted")


func test_panel_forge_of_a_backpack_pair_selects_it_in_the_backpack() -> void:
	MarketFakes.human_with_hero(world, "pad:a", &"mage")
	var slot := PlayerManager.get_slot(0)
	var eq := _hero(slot).equipment
	var helm := MarketFakes.make_item("Silk Hood", Items.SlotType.HEAD, ClassData.ArmorType.CLOTH)
	eq.add_to_backpack(MarketFakes.make_weapon(&"dagger", Items.Rarity.RARE))
	eq.add_to_backpack(helm)
	eq.add_to_backpack(MarketFakes.make_weapon(&"dagger", Items.Rarity.RARE))
	var panel := _panel(slot)
	panel.select_backpack(2)
	panel.open_menu()
	check_eq(panel.menu_entry_detail("Forge"), "→ Epic", "Rare -> Epic")
	panel.select_menu_entry("Forge")
	_press_a(panel, slot)
	check_eq(eq.backpack.size(), 2, "helm + the Epic dagger")
	check(eq.backpack[1].rarity == Items.Rarity.EPIC, "appended")
	check_eq(panel.selected_bag_index(), 1, "the result is selected in the backpack")


func test_panel_greys_out_forge_for_a_legendary() -> void:
	MarketFakes.human_with_hero(world, "pad:a", &"rogue")
	var slot := PlayerManager.get_slot(0)
	var eq := _hero(slot).equipment
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var legendary := Forge.make_result(MarketFakes.make_weapon(&"dagger", Items.Rarity.EPIC),
			MarketFakes.make_weapon(&"dagger", Items.Rarity.EPIC), rng)
	eq.add_to_backpack(legendary)
	eq.add_to_backpack(MarketFakes.make_weapon(&"dagger", Items.Rarity.EPIC))
	var panel := _panel(slot)
	panel.select_backpack(0)
	panel.open_menu()
	check(not panel.menu_entry_enabled("Forge"), "greyed out")
	check_eq(panel.menu_entry_detail("Forge"), "", "no result rarity")
	panel.select_menu_entry("Forge")
	_press_a(panel, slot)
	check_eq(panel.last_message, "Legendary is the highest rarity", "the reason")
	check(eq.backpack[0] == legendary and eq.backpack.size() == 2, "nothing forged")


# --- Shop ----------------------------------------------------------------------------------

func _stall(items: Array[ItemInstance], prices: Array[int]) -> Array:
	var shop := StockedShop.new()
	shop.stock(items, prices)
	var panel := ShopPanel.create(shop)
	panel.position = Vector2(568, 140)
	tree.root.add_child(panel)
	nodes.append(panel)
	panel.refresh(PlayerManager.get_slots())
	return [shop, panel]


func test_full_backpack_buys_and_forges_at_once() -> void:
	var input := MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	MarketFakes.human_with_hero(world, "pad:b", &"mage")
	var warrior := PlayerManager.get_slot(0)
	var eq := _hero(warrior).equipment
	var spare := ItemInstance.from_weapon(Db.get_weapon(&"sword"))
	eq.add_to_backpack(spare)
	_fill(eq)
	var offer_sword := ItemInstance.from_weapon(Db.get_weapon(&"sword"), Items.Rarity.COMMON, 3)
	var helm := MarketFakes.make_item("Runed Plate Helm", Items.SlotType.HEAD, ClassData.ArmorType.PLATE)
	var stall := _stall([offer_sword, helm] as Array[ItemInstance], [30, 20] as Array[int])
	var shop: StockedShop = stall[0]
	var panel: ShopPanel = stall[1]
	var bought: Array[ItemInstance] = []
	panel.item_bought.connect(func(_i: int, it: ItemInstance) -> void: bought.append(it))
	RunState.add_gold(200)
	check_eq(panel.buy_block_reason(warrior, 1), "Backpack full", "nothing to forge the helm with")
	check_eq(panel.buy_block_reason(warrior, 0), "", "the sword forges: no Backpack full")
	# A press on the sword (the cursor of P1 starts on offer 0).
	panel.set_cursor(warrior.index, 0)
	input.press(PlayerInput.Pad.A)
	MarketFakes.poll_all(DT)
	panel.begin_frame(DT)
	panel.handle_input(warrior)
	input.release(PlayerInput.Pad.A)
	MarketFakes.poll_all(0.0)
	check(shop.offers[0].sold, "sold")
	var forged := shop.last_forged
	check(forged != null and forged.rarity == Items.Rarity.UNCOMMON, "an Uncommon sword")
	check(not eq.backpack.has(offer_sword) and not eq.backpack.has(spare), "neither Common sword is in the backpack")
	check(eq.backpack.has(forged) and eq.backpack.size() == Items.BACKPACK_SIZE, "the result took the partner's place")
	check_eq(RunState.gold, 170, "the price was paid")
	check_eq(panel.feedback_lines()[-1], "P1 bought and forged [%s] – 30 g" % forged.display_name, "the log line")
	check_eq(bought, [forged] as Array[ItemInstance], "the forged weapon is reported")
	var entry: Dictionary = RunState.spend_log[-1]
	check_eq(entry["kind"], &"shop_forge", "spend kind")
	check_eq(entry["label"], "%s (forged)" % offer_sword.display_name, "spend label")
	check_eq(int(entry["slot"]), warrior.index, "who")
	check_eq(RunState.weapons_forged, 1, "counted")
	# The helm is still refused.
	check(not panel.try_buy(warrior, 1), "helm refused")
	check_eq(panel.feedback_lines()[-1], "P1: Backpack full", "with the reason")


func test_with_room_the_weapon_goes_to_the_backpack() -> void:
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	var warrior := PlayerManager.get_slot(0)
	var eq := _hero(warrior).equipment
	var offer_sword := ItemInstance.from_weapon(Db.get_weapon(&"sword"))
	var stall := _stall([offer_sword] as Array[ItemInstance], [25] as Array[int])
	var shop: StockedShop = stall[0]
	var panel: ShopPanel = stall[1]
	RunState.add_gold(100)
	check(panel.try_buy(warrior, 0), "bought")
	check(shop.last_forged == null, "no forge")
	check(eq.backpack.has(offer_sword), "into the backpack")
	check_eq(panel.feedback_lines()[-1], "P1 bought [%s] – 25 g" % offer_sword.display_name, "the plain log line")
	check_eq(RunState.weapons_forged, 0, "nothing forged")
	check_eq(RunState.spend_log[-1]["kind"], &"shop", "a plain shop spend")


func test_anvil_pips_show_who_could_forge_an_offer() -> void:
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	MarketFakes.human_with_hero(world, "pad:b", &"mage")
	var mage := PlayerManager.get_slot(1)
	var items: Array[ItemInstance] = [
		ItemInstance.from_weapon(Db.get_weapon(&"sword")),
		MarketFakes.make_item("Runed Plate Helm", Items.SlotType.HEAD, ClassData.ArmorType.PLATE),
		ItemInstance.from_weapon(Db.get_weapon(&"wand")),
		ItemInstance.from_weapon(Db.get_weapon(&"sword"), Items.Rarity.RARE),
	]
	var stall := _stall(items, [10, 10, 10, 10] as Array[int])
	var panel: ShopPanel = stall[1]
	check_eq(panel.cards[0].anvil_slots(), [0] as Array[int], "the warrior's starting sword")
	check_eq(panel.cards[1].anvil_slots(), [] as Array[int], "not a weapon")
	check_eq(panel.cards[2].anvil_slots(), [1] as Array[int], "the mage's starting wand")
	check_eq(panel.cards[3].anvil_slots(), [] as Array[int], "a Rare sword pairs with nobody")
	# The mage picks up a Common sword: the sword card shows both players after the next frame.
	_hero(mage).equipment.add_to_backpack(ItemInstance.from_weapon(Db.get_weapon(&"sword")))
	panel._process(DT)
	check_eq(panel.cards[0].anvil_slots(), [0, 1] as Array[int], "both can forge it now")
	check(panel.cards[0].has_anvil(1) and not panel.cards[1].has_anvil(1), "has_anvil per card")


# --- Intermission bots ---------------------------------------------------------------------

func _market_with_bots(shop: Shop) -> Intermission:
	RunState.shop = shop
	var screen := Intermission.create()
	tree.root.add_child(screen)
	nodes.append(screen)
	screen.bot_shopping = true
	screen.bot_buy_chance = 1.0
	screen.bot_market_time = 0.0
	return screen


func _run_market(screen: Intermission) -> void:
	screen.open(2, 0)
	for i in 3:
		MarketFakes.poll_all(DT)
		screen._process(DT)


func test_bots_forge_before_buying() -> void:
	var paladin := MarketFakes.bot_with_hero(world, "bot:a", &"paladin")
	var eq := _hero(paladin).equipment
	var shield := eq.get_item(Items.EquipSlot.OFF_HAND)
	eq.add_to_backpack(ItemInstance.from_weapon(Db.get_weapon(&"shield")))
	var shop := StockedShop.new()
	shop.stock([MarketFakes.make_item("Band", Items.SlotType.RING)] as Array[ItemInstance], [999] as Array[int])
	var screen := _market_with_bots(shop)
	_run_market(screen)
	check_eq(RunState.weapons_forged, 1, "the bot forged its two Common shields")
	var forged := eq.get_item(Items.EquipSlot.OFF_HAND)
	check(forged != shield and forged.rarity == Items.Rarity.UNCOMMON, "the Uncommon shield is worn")
	check(eq.backpack.is_empty(), "nothing left in the backpack")


func test_bots_never_reach_the_shops_auto_forge() -> void:
	# A full backpack and a forge partner (the equipped Epic mace) for the offered Epic mace:
	# a human's purchase would forge, a bot sells junk first and buys it plainly.
	var paladin := MarketFakes.bot_with_hero(world, "bot:a", &"paladin")
	var eq := _hero(paladin).equipment
	var worn := MarketFakes.make_weapon(&"mace", Items.Rarity.EPIC)
	check(eq.equip(worn, Items.EquipSlot.MAIN_HAND), "an Epic mace in the main hand")
	eq.take(eq.backpack[0])  # the Common mace it replaced
	_fill(eq)
	var better := MarketFakes.make_weapon(&"mace", Items.Rarity.EPIC)
	better.stats = {Stats.STRENGTH: 12.0, Stats.STAMINA: 8.0}
	var shop := StockedShop.new()
	shop.stock([better] as Array[ItemInstance], [30] as Array[int])
	check(shop.forges_on_buy(0, paladin), "a buy would forge right now")
	RunState.add_gold(30)
	var screen := _market_with_bots(shop)
	_run_market(screen)
	check(shop.offers[0].sold, "the bot bought the mace")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == better, "and wears it")
	check_eq(RunState.weapons_forged, 0, "no forge")
	var kinds: Array[StringName] = []
	for entry in RunState.spend_log:
		kinds.append(entry["kind"])
	check_eq(kinds, [&"shop"] as Array[StringName], "a plain shop purchase, never shop_forge")
