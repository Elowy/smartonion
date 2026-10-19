class_name Items
extends RefCounted
## Shared item enums and constants (GDD chapter 5).

## What kind of item it is (where it can go).
enum SlotType { HEAD, NECK, SHOULDERS, CHEST, WRIST, HANDS, WAIST, LEGS, FEET, RING, TRINKET, WEAPON }
## Equipment positions on the character panel.
enum EquipSlot {
	HEAD, NECK, SHOULDERS, CHEST, WRIST, HANDS, WAIST, LEGS, FEET,
	RING_1, RING_2, TRINKET_1, TRINKET_2, MAIN_HAND, OFF_HAND,
}
## WoW item quality. Matches UiTheme.RARITY_COLORS / RARITY_NAMES.
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY, ARTIFACT }

## Armor type of jewellery, trinkets and weapons.
const NO_ARMOR := -1
const BACKPACK_SIZE := 10

## The 8 slots that carry an armor type (Armor Specialization needs all of them).
const ARMOR_SLOTS: Array[SlotType] = [
	SlotType.HEAD, SlotType.SHOULDERS, SlotType.CHEST, SlotType.WRIST,
	SlotType.HANDS, SlotType.WAIST, SlotType.LEGS, SlotType.FEET,
]

const SLOT_NAMES := {
	SlotType.HEAD: "Head", SlotType.NECK: "Neck", SlotType.SHOULDERS: "Shoulders",
	SlotType.CHEST: "Chest", SlotType.WRIST: "Wrist", SlotType.HANDS: "Hands",
	SlotType.WAIST: "Waist", SlotType.LEGS: "Legs", SlotType.FEET: "Feet",
	SlotType.RING: "Finger", SlotType.TRINKET: "Trinket", SlotType.WEAPON: "Weapon",
}
const EQUIP_SLOT_NAMES := {
	EquipSlot.HEAD: "Head", EquipSlot.NECK: "Neck", EquipSlot.SHOULDERS: "Shoulders",
	EquipSlot.CHEST: "Chest", EquipSlot.WRIST: "Wrist", EquipSlot.HANDS: "Hands",
	EquipSlot.WAIST: "Waist", EquipSlot.LEGS: "Legs", EquipSlot.FEET: "Feet",
	EquipSlot.RING_1: "Ring 1", EquipSlot.RING_2: "Ring 2",
	EquipSlot.TRINKET_1: "Trinket 1", EquipSlot.TRINKET_2: "Trinket 2",
	EquipSlot.MAIN_HAND: "Main Hand", EquipSlot.OFF_HAND: "Off Hand",
}
const ARMOR_TYPE_NAMES := {
	ClassData.ArmorType.CLOTH: "Cloth", ClassData.ArmorType.LEATHER: "Leather",
	ClassData.ArmorType.MAIL: "Mail", ClassData.ArmorType.PLATE: "Plate",
}
## Material tier names per armor type (GDD 5.4): tier I (waves 1-8), II (9-16), III (17+).
const MATERIAL_NAMES := {
	ClassData.ArmorType.CLOTH: ["Linen", "Silk", "Moonweave"],
	ClassData.ArmorType.LEATHER: ["Rugged", "Thick", "Shadowhide"],
	ClassData.ArmorType.MAIL: ["Chain", "Scaled", "Stormforged"],
	ClassData.ArmorType.PLATE: ["Iron", "Steel", "Runed"],
}
const RARITY_NAMES: Array[String] = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact"]
## Base damage multiplier of weapons by rarity (GDD 4.1).
const WEAPON_RARITY_DAMAGE: Array[float] = [1.0, 1.3, 1.7, 2.2, 3.0, 3.0]
## Attack speed bonus (percent, WeaponData.attack_speed_pct) of attacking weapons by rarity
## (GDD 4.1: Epic +10%; the other rows have none).
const WEAPON_RARITY_ATTACK_SPEED: Array[float] = [0.0, 0.0, 0.0, 10.0, 0.0, 0.0]
## Sell value share of the buy price (GDD 5.6) and the Greed sale share (GDD 10.1).
const SELL_SHARE := 0.35
const GREED_SHARE := 0.5


## Equipment positions an item of [param slot_type] may occupy (weapons: decided by Equipment).
static func equip_slots_for(slot_type: SlotType) -> Array[EquipSlot]:
	match slot_type:
		SlotType.HEAD: return [EquipSlot.HEAD]
		SlotType.NECK: return [EquipSlot.NECK]
		SlotType.SHOULDERS: return [EquipSlot.SHOULDERS]
		SlotType.CHEST: return [EquipSlot.CHEST]
		SlotType.WRIST: return [EquipSlot.WRIST]
		SlotType.HANDS: return [EquipSlot.HANDS]
		SlotType.WAIST: return [EquipSlot.WAIST]
		SlotType.LEGS: return [EquipSlot.LEGS]
		SlotType.FEET: return [EquipSlot.FEET]
		SlotType.RING: return [EquipSlot.RING_1, EquipSlot.RING_2]
		SlotType.TRINKET: return [EquipSlot.TRINKET_1, EquipSlot.TRINKET_2]
		SlotType.WEAPON: return [EquipSlot.MAIN_HAND, EquipSlot.OFF_HAND]
	return []


## Material tier (0..2) for items generated at [param wave].
static func material_tier(wave: int) -> int:
	if wave >= 17:
		return 2
	if wave >= 9:
		return 1
	return 0


## Item Level (GDD 5.6.1): 10 + 3 x wave + rarity bonus (+6 when looted).
static func item_level(wave: int, rarity: int, looted: bool) -> int:
	const RARITY_BONUS: Array[int] = [0, 4, 8, 13, 20, 25]
	return 10 + 3 * maxi(1, wave) + RARITY_BONUS[clampi(rarity, 0, 5)] + (6 if looted else 0)


## Stable StatBlock source name for an equipment position.
static func source_for(equip_slot: EquipSlot) -> StringName:
	return StringName("item:%s" % String(EquipSlot.keys()[equip_slot]).to_lower())
