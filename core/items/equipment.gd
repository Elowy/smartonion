class_name Equipment
extends RefCounted
## One player's equipped items + 10-slot backpack (GDD 5.1, 5.6). Pure data + rules;
## Player turns it into stat sources and weapons (Player.apply_equipment).
##
## A hero never ends up without an attacking weapon (shields and tomes do not attack):
## equip() refuses an off-hand item that would push the only weapon (a two-hander) out,
## unequip() refuses the last equipped attacking weapon, and remove_from_backpack() (sell,
## trade) refuses the last usable attacking weapon of a hero who has none equipped
## (is_last_weapon / equip_disarms; the UI shows NEED_WEAPON). take() is not guarded.

signal changed

const ARMOR_SPEC_BONUS := 0.10
## Message of the "never without an attacking weapon" guard.
const NEED_WEAPON := "You need a weapon"

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


## Takes [param item] out of the backpack (sell, trade). False when it is not there or it is
## the hero's last usable attacking weapon while none is equipped (is_last_weapon).
func remove_from_backpack(item: ItemInstance) -> bool:
	var i := backpack.find(item)
	if i < 0 or is_last_weapon(item):
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
## The off hand next to an equipped two-hander does not count as empty (a one-hander takes
## the two-hander's place in the main hand).
func default_slot(item: ItemInstance) -> int:
	var targets := target_slots(item)
	if targets.is_empty():
		return -1
	var main := get_item(Items.EquipSlot.MAIN_HAND)
	var beside_two_hander := main != null and main.is_two_handed()
	for s in targets:
		if not slots.has(s) and not (s == Items.EquipSlot.OFF_HAND and beside_two_hander):
			return s
	return targets[0]


## The equipped items equip([param item], [param equip_slot]) would move to the backpack
## (-1 = default_slot): what sits in that position, plus the off hand for a two-hander, plus
## an equipped two-hander for anything going into the off hand. Empty for an invalid slot.
func displaced_by(item: ItemInstance, equip_slot: int = -1) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	if item == null:
		return out
	if equip_slot < 0:
		equip_slot = default_slot(item)
	if equip_slot not in target_slots(item):
		return out
	if slots.has(equip_slot) and slots[equip_slot] != item:
		out.append(slots[equip_slot])
	# Two-handers clear the off hand; an off-hand item next to a two-hander clears the main hand.
	var off := get_item(Items.EquipSlot.OFF_HAND)
	if item.is_two_handed() and off != null and off not in out:
		out.append(off)
	if equip_slot == Items.EquipSlot.OFF_HAND:
		var main := get_item(Items.EquipSlot.MAIN_HAND)
		if main != null and main.is_two_handed() and main not in out:
			out.append(main)
	return out


## Whether an attacking weapon (not a shield / tome) is equipped in either hand.
func is_armed() -> bool:
	return is_attacking_weapon(get_item(Items.EquipSlot.MAIN_HAND)) \
		or is_attacking_weapon(get_item(Items.EquipSlot.OFF_HAND))


static func is_attacking_weapon(item: ItemInstance) -> bool:
	return item != null and item.is_weapon() and item.weapon.attacks()


## Whether equipping [param item] at [param equip_slot] (-1 = default) would leave the hero
## without an attacking weapon while one is equipped now – e.g. a shield or tome next to a
## two-hander, which pushes the two-hander out.
func equip_disarms(item: ItemInstance, equip_slot: int = -1) -> bool:
	if item == null or is_attacking_weapon(item) or not is_armed():
		return false
	var gone := displaced_by(item, equip_slot)
	for s in [Items.EquipSlot.MAIN_HAND, Items.EquipSlot.OFF_HAND]:
		var held := get_item(s)
		if is_attacking_weapon(held) and held not in gone:
			return false
	return true


## Whether taking [param item] away (unequip, sell, trade) would leave the hero without an
## attacking weapon: it is the only attacking weapon equipped, or – while none is equipped –
## the last attacking weapon in the backpack this class can use.
func is_last_weapon(item: ItemInstance) -> bool:
	if not is_attacking_weapon(item):
		return false
	var hands: Array[ItemInstance] = [get_item(Items.EquipSlot.MAIN_HAND), get_item(Items.EquipSlot.OFF_HAND)]
	if item in hands:
		for held in hands:
			if held != item and is_attacking_weapon(held):
				return false
		return true
	if is_armed() or not backpack.has(item) or (class_data != null and not item.can_be_used_by(class_data)):
		return false
	for other in backpack:
		if other != item and is_attacking_weapon(other) and (class_data == null or other.can_be_used_by(class_data)):
			return false
	return true


## Equips [param item] (taking it out of the backpack if it is there). Displaced items go to
## the backpack (displaced_by). Returns false and changes nothing when the item cannot be
## used, the slot is not valid for it, the backpack has no room for what would be displaced,
## or it would leave the hero without an attacking weapon (equip_disarms).
func equip(item: ItemInstance, equip_slot: int = -1) -> bool:
	if not can_equip(item):
		return false
	if equip_slot < 0:
		equip_slot = default_slot(item)
	if equip_slot not in target_slots(item):
		return false
	if equip_disarms(item, equip_slot):
		return false
	var displaced := displaced_by(item, equip_slot)
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


## Moves the item in [param equip_slot] to the backpack. False if empty, no room, or it is the
## last equipped attacking weapon (is_last_weapon).
func unequip(equip_slot: Items.EquipSlot) -> bool:
	if not slots.has(equip_slot) or not has_space() or is_last_weapon(slots[equip_slot]):
		return false
	backpack.append(slots[equip_slot])
	slots.erase(equip_slot)
	changed.emit()
	return true


## Removes [param item] wherever it is (backpack or equipped). Returns true if found.
## Not guarded by is_last_weapon (internal moves such as forging).
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
