extends TestCase
## Shared fakes for the M2 market UI tests (ShopPanel, LootRollScreen, Intermission phases):
## a Shop and a LootRoll that follow the real classes' contracts but record every call and
## behave predictably, plus item / hero builders. Preload it:
##   const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
## (It is a test file itself only to check that the fakes keep following the contracts.)

const UiFakes := preload("res://tests/ui_fakes.gd")


## Records every call; offers are whatever the test stocks (stock()).
class FakeShop extends Shop:
	var open_calls: Array[Dictionary] = []
	var buy_calls: Array[Array] = []
	var lock_calls: Array[Array] = []
	var ping_calls: Array[Array] = []
	var vote_calls: Array[Array] = []
	## false = buy() always refuses.
	var allow_buy := true

	func stock(items: Array[ItemInstance], prices: Array[int]) -> void:
		offers.clear()
		for i in items.size():
			var o := Shop.Offer.new()
			o.item = items[i]
			o.price = prices[i] if i < prices.size() else 10
			offers.append(o)
		changed.emit()

	func open_round(p_wave: int, slots: Array[PlayerSlot], _rng: RandomNumberGenerator) -> void:
		open_calls.append({"wave": p_wave, "slots": slots.duplicate()})
		wave = p_wave
		reroll_votes.clear()
		rerolls_this_round = 0
		changed.emit()

	func buy(index: int, slot: PlayerSlot) -> bool:
		buy_calls.append([index, slot.index if slot != null else -1])
		if not allow_buy or index < 0 or index >= offers.size():
			return false
		var o := offers[index]
		var eq := ShopPanel.equipment_of(slot)
		if o.sold or eq == null or not eq.has_space() or not RunState.try_spend(o.price):
			return false
		eq.add_to_backpack(o.item)
		o.sold = true
		o.locked_by = -1
		o.pinged_by.clear()
		changed.emit()
		return true

	func toggle_lock(index: int, slot_index: int) -> void:
		lock_calls.append([index, slot_index])
		var o := offers[index]
		o.locked_by = -1 if o.locked_by >= 0 else slot_index
		changed.emit()

	func toggle_ping(index: int, slot_index: int) -> void:
		ping_calls.append([index, slot_index])
		var o := offers[index]
		if slot_index in o.pinged_by:
			o.pinged_by.erase(slot_index)
		else:
			o.pinged_by.append(slot_index)
		changed.emit()

	func vote_reroll(slot_index: int, joined: Array[int], _rng: RandomNumberGenerator) -> bool:
		vote_calls.append([slot_index, joined.duplicate()])
		if reroll_votes.has(slot_index):
			reroll_votes.erase(slot_index)
		else:
			reroll_votes[slot_index] = true
		for i in joined:
			if not reroll_votes.get(i, false):
				changed.emit()
				return false
		if joined.is_empty() or not RunState.try_spend(reroll_cost()):
			changed.emit()
			return false
		reroll_votes.clear()
		rerolls_this_round += 1
		changed.emit()
		return true


## Need allowed per [member need_ok]; rolls come from [member forced_rolls] (default 50);
## apply() only counts (it touches neither backpacks nor the wallet unless [member pay]).
class FakeLootRoll extends LootRoll:
	var need_ok := true
	var forced_rolls: Dictionary[int, int] = {}
	var resolve_calls := 0
	var apply_calls := 0
	## apply() also books the statistics like a full LootRoll would.
	var books_stats := false

	func can_need(_slot: PlayerSlot) -> bool:
		return need_ok

	func choose(slot_index: int, choice: LootRoll.Choice) -> void:
		choices[slot_index] = choice

	func all_decided(slot_indices: Array[int]) -> bool:
		for i in slot_indices:
			if choices.get(i, LootRoll.Choice.UNDECIDED) == LootRoll.Choice.UNDECIDED:
				return false
		return true

	func resolve(_rng: RandomNumberGenerator) -> void:
		resolve_calls += 1
		var needers: Array[int] = []
		var greeders: Array[int] = []
		for i: int in choices:
			if choices[i] == LootRoll.Choice.NEED:
				needers.append(i)
			elif choices[i] == LootRoll.Choice.GREED:
				greeders.append(i)
		var pool := needers if not needers.is_empty() else greeders
		outcome = &"need" if not needers.is_empty() else (&"greed" if not greeders.is_empty() else &"pass")
		winner = -1
		var best := -1
		pool.sort()
		for i in pool:
			var r: int = forced_rolls.get(i, 50)
			rolls[i] = r
			if r > best:
				best = r
				winner = i

	func apply(_slots: Array[PlayerSlot]) -> void:
		apply_calls += 1
		if not books_stats:
			return
		if outcome == &"need":
			RunState.need_wins_by_player[winner] = RunState.need_wins_by_player.get(winner, 0) + 1
		elif outcome == &"greed":
			RunState.greed_gold += item.greed_value()


## An armor / jewellery item without the generator.
static func make_item(display_name: String, slot_type: Items.SlotType, armor_type: int = Items.NO_ARMOR,
		rarity: int = Items.Rarity.UNCOMMON, price: int = 30) -> ItemInstance:
	var item := ItemInstance.new()
	item.source_id = StringName(display_name.to_snake_case())
	item.display_name = display_name
	item.slot_type = slot_type
	item.armor_type = armor_type
	item.rarity = rarity
	item.wave = 3
	item.item_level = Items.item_level(3, rarity, false)
	item.stats = {Stats.STAMINA: 3.0}
	item.buy_price = price
	return item


static func make_weapon(weapon_id: StringName, rarity: int = Items.Rarity.RARE, price: int = 40) -> ItemInstance:
	var item := ItemInstance.from_weapon(Db.get_weapon(weapon_id), rarity, 3)
	item.buy_price = price
	return item


## A joined human (HumanInput) of [param class_id] with a hero in [param world].
static func human_with_hero(world: Node3D, key: String, class_id: StringName) -> UiFakes.HumanInput:
	var input := UiFakes.HumanInput.new(key)
	var slot := PlayerManager.join(input, Db.get_class_data(class_id))
	world.add_child(Player.create(slot))
	return input


## A joined bot (ScriptedInput) of [param class_id] with a hero in [param world].
static func bot_with_hero(world: Node3D, key: String, class_id: StringName) -> PlayerSlot:
	var slot := PlayerManager.join(ScriptedInput.new(key), Db.get_class_data(class_id))
	world.add_child(Player.create(slot))
	return slot


static func make_world(tree: SceneTree) -> Node3D:
	var world := Node3D.new()
	world.name = "MarketTestWorld"
	tree.root.add_child(world)
	return world


## Polls every slot's input (what PlayerManager does once per frame).
static func poll_all(delta: float = 1.0 / 60.0) -> void:
	for slot in PlayerManager.get_slots():
		slot.input.poll(delta)


# --- The fakes follow the contracts -----------------------------------------------------

func test_fake_shop_follows_the_contract() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, 3)
	var world := make_world(tree)
	human_with_hero(world, "pad:a", &"warrior")
	var slot := PlayerManager.get_slot(0)
	var shop := FakeShop.new()
	var items: Array[ItemInstance] = [make_item("Iron Helm", Items.SlotType.HEAD, ClassData.ArmorType.PLATE)]
	shop.stock(items, [12] as Array[int])
	check(shop is Shop, "a Shop")
	check(not shop.buy(0, slot), "no gold")
	RunState.add_gold(20)
	check(shop.buy(0, slot), "bought")
	check(shop.offers[0].sold and RunState.gold == 8, "sold, paid")
	check_eq(ShopPanel.equipment_of(slot).backpack.size(), 1, "in the backpack")
	var roll := FakeLootRoll.new()
	roll.item = items[0]
	check(roll is LootRoll, "a LootRoll")
	roll.choose(0, LootRoll.Choice.NEED)
	roll.resolve(RunState.rng)
	check_eq(roll.outcome, &"need", "need wins")
	check_eq(roll.winner, 0, "winner")
	world.free()
	UiFakes.reset_players()
