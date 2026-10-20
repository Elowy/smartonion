class_name EquipLook
extends RefCounted
## What one worn Head / Shoulders / Chest item looks like on the onion (GDD 13, M7b VIS-HERO).
##
## A small value object digested from an [ItemInstance] (or made by hand for the showcase and the
## tests): armour type, material tier, rarity, tier set and hand-made unique id. OnionModel keeps one
## per slot and rebuilds its gear only when their [method key]s change; OnionArmor turns a look
## into meshes. Nothing here touches the scene tree.
##
## The visual rule (documented once, used everywhere):
##  - the silhouette family comes from the slot and the armour type ([method family]);
##  - the detail level is the material tier of the wave the item was made for (Items.material_tier:
##    tier I / II / III = Iron / Steel / Runed, Linen / Silk / Moonweave ...), so the model matches
##    the material word in the item's name; set pieces always use the richest detail;
##  - the trim colour is the weapon rarity colour (WeaponModel.rarity_color), Epic and better glow;
##  - a tier set piece wears the set's class-coloured kit; a Legendary adds a glow accent.

## Which of the three visible armour slots (index into OnionModel's gear arrays).
enum Slot { HEAD, SHOULDERS, CHEST }

const SLOT_COUNT := 3
## Rarity from which a worn piece glows faintly (same as the weapons, GDD 13).
const GLOW_RARITY := WeaponModel.GLOW_RARITY
## Rarity of a Legendary (stronger glow accent).
const LEGENDARY_RARITY := 4
const MAX_TIER := 2

var slot: Slot = Slot.HEAD
## ClassData.ArmorType.
var armor: int = ClassData.ArmorType.CLOTH
## Material tier 0..2 (Items.material_tier).
var tier := 0
var rarity := 0
## Tier set id ("" = none); set pieces are Epic pieces of a SetData (class-restricted, or free of
## any class for a class-independent set).
var set_id: StringName
## Source id of a hand-made item (unique / set piece / Legendary); "" for a generated one.
var unique_id: StringName


## A look made by hand (showcase, tests).
static func make(p_slot: Slot, p_armor: int, p_tier: int = 0, p_rarity: int = 0, p_set_id: StringName = &"",
		p_unique_id: StringName = &"") -> EquipLook:
	var look := EquipLook.new()
	look.slot = p_slot
	look.armor = clampi(p_armor, ClassData.ArmorType.CLOTH, ClassData.ArmorType.PLATE)
	look.tier = clampi(p_tier, 0, MAX_TIER)
	look.rarity = clampi(p_rarity, 0, WeaponModel.RARITY_COLORS.size() - 1)
	look.set_id = p_set_id
	look.unique_id = p_unique_id
	return look


## The look of [param item] worn in its slot; null for no item, a weapon, or anything that is
## not a Head / Shoulders / Chest piece (those have no model part).
static func from_item(item: ItemInstance) -> EquipLook:
	if item == null or item.is_weapon():
		return null
	var p_slot := slot_for_type(item.slot_type)
	if p_slot < 0:
		return null
	var armor_type := item.armor_type if item.armor_type != Items.NO_ARMOR else ClassData.ArmorType.CLOTH
	return make(p_slot as Slot, armor_type, Items.material_tier(item.wave), item.rarity, item.set_id,
			item.source_id if item.unique else &"")


## Slot index of an item type (-1 = the type has no model part).
static func slot_for_type(slot_type: Items.SlotType) -> int:
	match slot_type:
		Items.SlotType.HEAD: return Slot.HEAD
		Items.SlotType.SHOULDERS: return Slot.SHOULDERS
		Items.SlotType.CHEST: return Slot.CHEST
	return -1


func is_set() -> bool:
	return set_id != &""


## Legendaries and tier sets add a glow accent on top of the faint Epic glow.
func has_accent() -> bool:
	return is_set() or rarity >= LEGENDARY_RARITY


func glows() -> bool:
	return rarity >= GLOW_RARITY or is_set()


## Detail level 0..2 that the geometry follows: the material tier, always the richest for a set.
func detail() -> int:
	return MAX_TIER if is_set() else tier


## Silhouette family id; the same words as ItemBase.look ("plate_helm", "cloth_mantle" ...).
func family() -> StringName:
	return family_of(slot, armor)


static func family_of(p_slot: int, p_armor: int) -> StringName:
	var prefix: String = ["cloth", "leather", "mail", "plate"][clampi(p_armor, 0, 3)]
	var piece: String = ""
	match p_slot:
		Slot.HEAD: piece = ["cowl", "cap", "coif", "helm"][clampi(p_armor, 0, 3)]
		Slot.SHOULDERS: piece = ["mantle", "shoulderpads", "spaulders", "pauldrons"][clampi(p_armor, 0, 3)]
		_: piece = ["robe", "tunic", "hauberk", "breastplate"][clampi(p_armor, 0, 3)]
	return StringName("%s_%s" % [prefix, piece])


## Everything that changes what the piece looks like, as a string (cache key and change check).
func key() -> String:
	return "%d.%d.%d.%d.%s.%s" % [slot, armor, tier, rarity, set_id, unique_id]


## Rarity (trim) colour of the piece.
func trim_color() -> Color:
	return WeaponModel.rarity_color(rarity)
