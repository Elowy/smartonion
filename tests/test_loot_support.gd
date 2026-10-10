extends TestCase
## Shared helpers for the shop / loot tests (test_shop*.gd, test_loot*.gd). Not a test itself
## (no test_ methods). Preload it:
##   const Support := preload("res://tests/test_loot_support.gd")

const EFakes := preload("res://tests/enemies_fakes.gd")


## A joined slot whose player is a FakePlayer (outside the tree) with an empty Equipment of
## the class. Free with [method free_slots].
static func make_slot(index: int, class_id: StringName) -> PlayerSlot:
	var slot := PlayerSlot.new(index, ScriptedInput.new("test:%d" % index), PlayerManager.PLAYER_COLORS[index])
	slot.class_data = Db.get_class_data(class_id)
	var p := EFakes.FakePlayer.new()
	p.slot = slot
	p.equipment = Equipment.new(slot.class_data)
	slot.player = p
	return slot


static func make_slots(class_ids: Array[StringName]) -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	for i in class_ids.size():
		out.append(make_slot(i, class_ids[i]))
	return out


static func free_slots(slots: Array[PlayerSlot]) -> void:
	for s in slots:
		if s.player != null and is_instance_valid(s.player) and not s.player.is_inside_tree():
			s.player.free()
		s.player = null


static func equipment_of(slot: PlayerSlot) -> Equipment:
	return (slot.player as Player).equipment


## A hand-made item (no generator): a chest piece of [param armor_type].
static func make_armor(item_level: int, armor_type: int = ClassData.ArmorType.CLOTH,
		price: int = 20, rarity: int = Items.Rarity.COMMON, slot_type: Items.SlotType = Items.SlotType.CHEST) -> ItemInstance:
	var item := ItemInstance.new()
	item.display_name = "Test Chest %d" % item_level
	item.slot_type = slot_type
	item.armor_type = armor_type
	item.rarity = rarity
	item.item_level = item_level
	item.buy_price = price
	return item


## A weapon item of Db weapon [param weapon_id].
static func make_weapon(weapon_id: StringName, rarity: int = Items.Rarity.COMMON, price: int = 20) -> ItemInstance:
	var item := ItemInstance.from_weapon(Db.get_weapon(weapon_id), rarity, 1, false)
	item.buy_price = price
	return item


static func fill_backpack(slot: PlayerSlot) -> void:
	var eq := equipment_of(slot)
	while eq.has_space():
		eq.add_to_backpack(make_armor(1))


## Counts the emissions of the argument-less signal [param sig] in a one-element array.
static func count_signal(sig: Signal) -> Array[int]:
	var counter: Array[int] = [0]
	sig.connect(func() -> void: counter[0] += 1)
	return counter
