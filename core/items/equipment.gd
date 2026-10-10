class_name Equipment
extends RefCounted
## One player's equipped items + 10-slot backpack (GDD 5.1, 5.6). Pure data + rules;
## Player turns it into stat sources and weapons (Player.apply_equipment).

signal changed

const ARMOR_SPEC_BONUS := 0.10

var class_data: ClassData
var slots: Dictionary[int, ItemInstance] = {}
var backpack: Array[ItemInstance] = []


func _init(p_class: ClassData = null) -> void:
	class_data = p_class


func get_item(equip_slot: Items.EquipSlot) -> ItemInstance:
	return slots.get(equip_slot)


func equipped_items() -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for s in Items.EquipSlot.values():
		if slots.has(s):
			out.append(slots[s])
	return out


func has_space(count: int = 1) -> bool:
	return backpack.size() + count <= Items.BACKPACK_SIZE


func add_to_backpack(item: ItemInstance) -> bool:
	if item == null or not has_space():
		return false
	backpack.append(item)
	changed.emit()
	return true


func remove_from_backpack(item: ItemInstance) -> bool:
	var i := backpack.find(item)
	if i < 0:
		return false
	backpack.remove_at(i)
	changed.emit()
	return true


func can_equip(item: ItemInstance) -> bool:
	return item != null and item.can_be_used_by(class_data) and not target_slots(item).is_empty()


## Positions [param item] may go to for this class (weapons: by hand + dual wield).
func target_slots(item: ItemInstance) -> Array[Items.EquipSlot]:
	if item == null:
		return []
	if not item.is_weapon():
		return Items.equip_slots_for(item.slot_type)
	if item.is_off_hand_only():
		return [Items.EquipSlot.OFF_HAND]
	if item.is_two_handed():
		return [Items.EquipSlot.MAIN_HAND]
	if class_data != null and class_data.can_dual_wield():
		return [Items.EquipSlot.MAIN_HAND, Items.EquipSlot.OFF_HAND]
	return [Items.EquipSlot.MAIN_HAND]


## The position equip(item) would use when none is given: the first empty one, else the first.
func default_slot(item: ItemInstance) -> int:
	var targets := target_slots(item)
	if targets.is_empty():
		return -1
	for s in targets:
		if not slots.has(s):
			return s
	return targets[0]


## Equips [param item] (taking it out of the backpack if it is there). Displaced items go to
## the backpack. Returns false and changes nothing when the item cannot be used, the slot is
## not valid for it, or the backpack has no room for what would be displaced.
func equip(item: ItemInstance, equip_slot: int = -1) -> bool:
	if not can_equip(item):
		return false
	if equip_slot < 0:
		equip_slot = default_slot(item)
	if equip_slot not in target_slots(item):
		return false
	var displaced: Array[ItemInstance] = []
	if slots.has(equip_slot):
		displaced.append(slots[equip_slot])
	# Two-handers clear the off hand; an off-hand item next to a two-hander clears the main hand.
	if item.is_two_handed() and slots.has(Items.EquipSlot.OFF_HAND):
		displaced.append(slots[Items.EquipSlot.OFF_HAND])
	if equip_slot == Items.EquipSlot.OFF_HAND:
		var main := get_item(Items.EquipSlot.MAIN_HAND)
		if main != null and main.is_two_handed():
			displaced.append(main)
	var in_backpack := backpack.has(item)
	var free := Items.BACKPACK_SIZE - backpack.size() + (1 if in_backpack else 0)
	if displaced.size() > free:
		return false
	if in_backpack:
		backpack.erase(item)
	for old in displaced:
		for s in slots.keys():
			if slots[s] == old:
				slots.erase(s)
		backpack.append(old)
	slots[equip_slot] = item
	changed.emit()
	return true


## Moves the item in [param equip_slot] to the backpack. False if empty or no room.
func unequip(equip_slot: Items.EquipSlot) -> bool:
	if not slots.has(equip_slot) or not has_space():
		return false
	backpack.append(slots[equip_slot])
	slots.erase(equip_slot)
	changed.emit()
	return true


## Removes [param item] wherever it is (backpack or equipped). Returns true if found.
func take(item: ItemInstance) -> bool:
	if backpack.has(item):
		backpack.erase(item)
		changed.emit()
		return true
	for s in slots.keys():
		if slots[s] == item:
			slots.erase(s)
			changed.emit()
			return true
	return false


func main_weapon() -> WeaponData:
	var item := get_item(Items.EquipSlot.MAIN_HAND)
	return item.weapon if item != null and item.is_weapon() else null


func off_weapon() -> WeaponData:
	var item := get_item(Items.EquipSlot.OFF_HAND)
	return item.weapon if item != null and item.is_weapon() else null


## Armor Specialization (GDD 5.3): all 8 armor slots hold the class's own armor type.
func armor_spec_active() -> bool:
	if class_data == null:
		return false
	for s in [Items.EquipSlot.HEAD, Items.EquipSlot.SHOULDERS, Items.EquipSlot.CHEST,
			Items.EquipSlot.WRIST, Items.EquipSlot.HANDS, Items.EquipSlot.WAIST,
			Items.EquipSlot.LEGS, Items.EquipSlot.FEET]:
		var item := get_item(s)
		if item == null or item.armor_type != class_data.armor_type:
			return false
	return true


## Average Item Level of the equipped items (character panel header).
func average_item_level() -> float:
	var items := equipped_items()
	if items.is_empty():
		return 0.0
	var total := 0
	for item in items:
		total += item.item_level
	return float(total) / items.size()


## Stat source name -> stats for every equipped position (see Items.source_for).
func stat_sources() -> Dictionary[StringName, Dictionary]:
	var out: Dictionary[StringName, Dictionary] = {}
	for s in slots:
		out[Items.source_for(s)] = slots[s].equip_stats()
	return out


## Starting loadout: the class's starting weapons as Common items (GDD 5.1).
func equip_starting_weapons() -> void:
	if class_data == null:
		return
	if class_data.main_hand != null:
		slots[Items.EquipSlot.MAIN_HAND] = ItemInstance.from_weapon(class_data.main_hand)
	if class_data.off_hand != null:
		slots[Items.EquipSlot.OFF_HAND] = ItemInstance.from_weapon(class_data.off_hand)
	changed.emit()
