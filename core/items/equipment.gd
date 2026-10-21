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
## Tier-set pieces worn are counted by [method set_counts] (SetBonuses turns them into bonuses).
## A pair Artifact (M6, Fangs of the Shadow: ItemInstance.companion) is ONE item of the
## backpack (its main-hand piece) that equips into the main hand together with its off-hand piece
## (target_slots = [MAIN_HAND], like a two-hander that also fills the off hand); unequip() of
## either piece takes the pair back as the one backpack item, and anything that displaces one
## piece displaces both (displaced_by). The off-hand piece never sits in the backpack.
## A one-hander in the off hand needs the dual_wield proficiency (the class's or a granted one). Losing a
## grant (a talent respec or undo) puts the weapon away (settle_off_hand); with the backpack full and the
## main hand taken it STAYS in the slot but is inert (stranded_off_hand: off_weapon() and stat_sources() leave
## it out, so it neither attacks nor adds stats, and the weapon requirement dual_wield turns off with it)
## until a backpack slot frees up (remove_from_backpack, take, equip settle it again) or the grant returns.

signal changed

const ARMOR_SPEC_BONUS := 0.10
## Message of the "never without an attacking weapon" guard.
const NEED_WEAPON := "You need a weapon"

var class_data: ClassData
var slots: Dictionary[int, ItemInstance] = {}
var backpack: Array[ItemInstance] = []
## Proficiencies the hero has besides ClassData.proficiencies, granted at runtime by a talent or
## set bonus ("proficiency" entries, PlayerBonuses.granted_proficiencies; Player forwards them on
## every rebuild). Today only &"dual_wield" is grantable (BonusVocabulary.GRANTABLE_PROFICIENCIES).
var granted_proficiencies: Array[StringName] = []
## The hero's backpack capacity: Items.BACKPACK_SIZE, plus the Class Level 14 slot (M9 LEVELS, Player.create sets it
## for a profile with raw power).
var backpack_size := Items.BACKPACK_SIZE


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
	return backpack.size() + count <= backpack_size


func add_to_backpack(item: ItemInstance) -> bool:
	if item == null or not has_space():
		return false
	backpack.append(item)
	changed.emit()
	return true


## Takes [param item] out of the backpack (sell, trade, disenchant). False when it is not there, it is bound (an
## Heirloom) or it is the hero's last usable attacking weapon while none is equipped (is_last_weapon).
func remove_from_backpack(item: ItemInstance) -> bool:
	var i := backpack.find(item)
	if i < 0 or is_last_weapon(item) or item.is_bound():  # (M9 PATCH: an Heirloom never leaves its hero this way)
		return false
	backpack.remove_at(i)
	settle_off_hand()
	changed.emit()
	return true


## Whether the hero may wield one-handers in both hands: the class's dual_wield proficiency or a
## granted one (a Warspirit talent for the Shaman).
func can_dual_wield() -> bool:
	return class_data != null and (class_data.can_dual_wield() or &"dual_wield" in granted_proficiencies)


## Replaces the granted proficiencies. Losing dual wield (a talent respec) takes a one-hander out
## of the off hand ([method settle_off_hand]): into the backpack, or into the main hand when that is
## empty; with neither possible (a full backpack) it stays where it is but is inert
## ([method stranded_off_hand]) until room appears. [signal changed] fires when the weapon moved or
## a one-hander sits in the off hand (its attack switches on / off with the grant: Player rebuilds).
## (A pair Artifact needs a class with dual_wield of its own, so a grant never matters for one.)
func set_granted_proficiencies(ids: Array[StringName]) -> void:
	if ids == granted_proficiencies:
		return
	granted_proficiencies = ids.duplicate()
	var moved := settle_off_hand()
	if moved or _off_hand_one_hander() != null:
		changed.emit()


## The one-hander in the off hand (null: none; a shield, a tome and the off-hand piece of a pair do not count).
func _off_hand_one_hander() -> ItemInstance:
	var off := get_item(Items.EquipSlot.OFF_HAND)
	if off == null or not off.is_weapon() or off.is_off_hand_only() or off.pair_off:
		return null
	return off


## The off-hand one-hander of a hero who cannot dual-wield (the grant was lost and settle_off_hand found no
## room): it is inert while it sits there, see off_weapon() / stat_sources(). Null otherwise.
func stranded_off_hand() -> ItemInstance:
	if class_data == null or can_dual_wield():
		return null
	return _off_hand_one_hander()


## Puts a stranded off-hand one-hander away: into the main hand when that is empty, else into the backpack
## when it has room. True when it moved (the caller emits [signal changed]); false when nothing is stranded or
## there is still no room. Runs whenever a backpack slot may have freed up.
func settle_off_hand() -> bool:
	var off := stranded_off_hand()
	if off == null:
		return false
	if get_item(Items.EquipSlot.MAIN_HAND) == null:
		slots.erase(Items.EquipSlot.OFF_HAND)
		slots[Items.EquipSlot.MAIN_HAND] = off
	elif has_space():
		slots.erase(Items.EquipSlot.OFF_HAND)
		backpack.append(off)
	else:
		return false
	return true


func can_equip(item: ItemInstance) -> bool:
	return item != null and item.can_be_used_by(class_data) and not target_slots(item).is_empty()


## Positions [param item] may go to for this class (weapons: by hand + dual wield).
func target_slots(item: ItemInstance) -> Array[Items.EquipSlot]:
	if item == null:
		return []
	if not item.is_weapon():
		return Items.equip_slots_for(item.slot_type)
	if item.pair_off:
		return []  # only ever equipped with its main-hand piece
	if item.companion != null:
		# A pair needs both hands: a class that can wield the off-hand piece too.
		if class_data == null or not can_dual_wield() or not class_data.can_use(item.companion.weapon):
			return []
		return [Items.EquipSlot.MAIN_HAND]
	if item.is_off_hand_only():
		return [Items.EquipSlot.OFF_HAND]
	if item.is_two_handed():
		return [Items.EquipSlot.MAIN_HAND]
	if can_dual_wield():
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
	# Two-handers (and pairs) clear the off hand; an off-hand item next to a two-hander clears
	# the main hand.
	var off := get_item(Items.EquipSlot.OFF_HAND)
	if (item.is_two_handed() or item.companion != null) and off != null and off not in out \
			and off != item.companion:
		out.append(off)
	if equip_slot == Items.EquipSlot.OFF_HAND:
		var main := get_item(Items.EquipSlot.MAIN_HAND)
		if main != null and main.is_two_handed() and main not in out:
			out.append(main)
	# The two pieces of a pair always leave together.
	var i := 0
	while i < out.size():
		var gone := out[i]
		i += 1
		var partner: ItemInstance = null
		if gone.companion != null and is_equipped(gone.companion):
			partner = gone.companion
		elif gone.pair_off:
			partner = pair_main_of(gone)
		if partner != null and partner not in out and partner != item:
			out.append(partner)
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
	if item.pair_off and pair_main_of(item) != null:
		item = pair_main_of(item)  # the pair is one weapon
	var hands: Array[ItemInstance] = [get_item(Items.EquipSlot.MAIN_HAND), get_item(Items.EquipSlot.OFF_HAND)]
	if item in hands:
		for held in hands:
			if held != item and held != item.companion and is_attacking_weapon(held):
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
	# What goes to the backpack: everything but the off-hand piece of a pair (it travels as the
	# main-hand piece's companion).
	var to_backpack: Array[ItemInstance] = []
	for old in displaced:
		if not old.pair_off:
			to_backpack.append(old)
	var in_backpack := backpack.has(item)
	var free := backpack_size - backpack.size() + (1 if in_backpack else 0)
	if to_backpack.size() > free:
		return false
	if in_backpack:
		backpack.erase(item)
	for old in displaced:
		for s in slots.keys():
			if slots[s] == old:
				slots.erase(s)
	backpack.append_array(to_backpack)
	slots[equip_slot] = item
	if item.companion != null:
		slots[Items.EquipSlot.OFF_HAND] = item.companion
	settle_off_hand()
	changed.emit()
	return true


## Moves the item in [param equip_slot] to the backpack. False if empty, no room, or it is the
## last equipped attacking weapon (is_last_weapon).
func unequip(equip_slot: Items.EquipSlot) -> bool:
	if not slots.has(equip_slot):
		return false
	var item := slots[equip_slot]
	if item.pair_off:
		# Either piece of a pair unequips the pair (as its main-hand piece).
		var main := pair_main_of(item)
		if main != null:
			return unequip(slot_of(main) as Items.EquipSlot)
	if not has_space() or is_last_weapon(item):
		return false
	backpack.append(item)
	slots.erase(equip_slot)
	_drop_companion(item)
	changed.emit()
	return true


## Removes [param item] wherever it is (backpack or equipped). Returns true if found.
## Not guarded by is_last_weapon (internal moves such as forging).
func take(item: ItemInstance) -> bool:
	if backpack.has(item):
		backpack.erase(item)
		settle_off_hand()
		changed.emit()
		return true
	for s in slots.keys():
		if slots[s] == item:
			slots.erase(s)
			_drop_companion(item)
			settle_off_hand()  # a stranded off-hand weapon steps into a main hand that was just emptied
			changed.emit()
			return true
	return false


## The EquipSlot [param item] sits in (-1 = not equipped).
func slot_of(item: ItemInstance) -> int:
	for s in slots:
		if slots[s] == item:
			return s
	return -1


## Whether [param item] is in an equipment slot (not in the backpack).
func is_equipped(item: ItemInstance) -> bool:
	return item != null and slot_of(item) >= 0


## The equipped main-hand piece of the pair whose off-hand piece is [param off] (null when
## [param off] is no equipped off-hand piece).
func pair_main_of(off: ItemInstance) -> ItemInstance:
	var main := get_item(Items.EquipSlot.MAIN_HAND)
	return main if main != null and off != null and main.companion == off else null


## A pair's off-hand piece leaves its slot together with [param main] (it stays attached to
## the main-hand piece as ItemInstance.companion).
func _drop_companion(main: ItemInstance) -> void:
	if main == null or main.companion == null:
		return
	var s := slot_of(main.companion)
	if s >= 0:
		slots.erase(s)


func main_weapon() -> WeaponData:
	var item := get_item(Items.EquipSlot.MAIN_HAND)
	return item.weapon if item != null and item.is_weapon() else null


## The off-hand weapon that is in use: a stranded one-hander (stranded_off_hand) is not.
func off_weapon() -> WeaponData:
	var item := get_item(Items.EquipSlot.OFF_HAND)
	if item == null or not item.is_weapon() or item == stranded_off_hand():
		return null
	return item.weapon


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


## Tier sets (GDD 5.5, SetBonuses): set id -> pieces of that set equipped (distinct pieces).
func set_counts() -> Dictionary[StringName, int]:
	return count_sets(equipped_items())


## Set id -> distinct set pieces (by source id) among [param items]; items without a set_id
## are ignored. A duplicate of a piece counts once.
static func count_sets(items: Array[ItemInstance]) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	var seen: Array[StringName] = []
	for item in items:
		if item == null or item.set_id == &"" or item.source_id in seen:
			continue
		seen.append(item.source_id)
		out[item.set_id] = out.get(item.set_id, 0) + 1
	return out


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
	var stranded := stranded_off_hand()
	for s in slots:
		if slots[s] != stranded:
			out[Items.source_for(s)] = slots[s].equip_stats()
	return out


## Starting loadout: the class's starting weapons as Common items (GDD 5.1). [param alt]: the class's alternative
## starting weapons instead (M9 Class Level 12, ClassPathData; a class without one starts as usual).
func equip_starting_weapons(alt: bool = false) -> void:
	if class_data == null:
		return
	var main := ClassLevels.start_main_hand(class_data, alt)
	var off := ClassLevels.start_off_hand(class_data, alt)
	if main != null:
		slots[Items.EquipSlot.MAIN_HAND] = ItemInstance.from_weapon(main)
	if off != null:
		slots[Items.EquipSlot.OFF_HAND] = ItemInstance.from_weapon(off)
	changed.emit()
