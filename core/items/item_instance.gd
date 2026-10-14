class_name ItemInstance
extends RefCounted
## A concrete item in a run (bought, looted or a starting weapon). Built by ItemGenerator
## (or from_weapon / from_unique). Plain data – UI and gameplay read it, nobody mutates it
## after creation (forging, M5, consumes two instances and builds a new one – see Forge).

static var _next_uid := 1

var uid := 0
## Id of the ItemBase / UniqueItemData / WeaponData it was made from (stable, for saves).
var source_id: StringName
var unique := false
var display_name := ""
var slot_type: Items.SlotType = Items.SlotType.TRINKET
var armor_type := Items.NO_ARMOR
var rarity := 0
## Wave the item was generated for (drives material tier, enchant rank, Item Level).
var wave := 1
var item_level := 0
## Came from loot (GDD 10.1): +25% budget, shown as "Looted".
var looted := false
## Weapons only: a private copy of the base WeaponData with rarity scaling applied,
## so WeaponRunner can use it unchanged.
var weapon: WeaponData
## Flat stats (incl. implicit armor). Equip enchants are separate (see equip_stats()).
var stats: Dictionary[StringName, float] = {}
var enchants: Array[EnchantRoll] = []
## &"" = any class, else only that class may use it ("Classes: Mage").
var class_restriction: StringName
var unique_effect: StringName
var unique_params: Dictionary = {}
var unique_text := ""
var flavor := ""
var set_id: StringName
## Shop price at the wave it was generated (sell / greed values derive from it).
var buy_price := 0
## Enchanter actions done on this item (M6 ENCHANTER): the n-th action costs 2^n times the
## base price. The one counter the Enchanter mutates (together with [member enchants]).
var enchant_uses := 0


func _init() -> void:
	uid = _next_uid
	_next_uid += 1


func is_weapon() -> bool:
	return slot_type == Items.SlotType.WEAPON and weapon != null


func is_two_handed() -> bool:
	return is_weapon() and weapon.is_two_handed()


func is_off_hand_only() -> bool:
	return is_weapon() and weapon.is_off_hand_only()


func rarity_name() -> String:
	return Items.RARITY_NAMES[clampi(rarity, 0, Items.RARITY_NAMES.size() - 1)]


## Strict WoW-like proficiency (GDD 5.3): weapon types from ClassData.proficiencies, armor of
## the class's own type or lighter, class-restricted items only for that class.
func can_be_used_by(class_data: ClassData) -> bool:
	if class_data == null:
		return false
	if class_restriction != &"" and class_restriction != class_data.id:
		return false
	if is_weapon():
		return class_data.can_use(weapon)
	if armor_type != Items.NO_ARMOR and armor_type > class_data.armor_type:
		return false
	return true


## Why [param class_data] cannot use it ("" if it can) – for greyed-out Need buttons / tooltips.
func unusable_reason(class_data: ClassData) -> String:
	if class_data == null:
		return "No class"
	if class_restriction != &"" and class_restriction != class_data.id:
		return "Classes: %s" % String(class_restriction).capitalize()
	if is_weapon() and not class_data.can_use(weapon):
		return "Cannot use %s" % String(weapon.weapon_type).capitalize()
	if armor_type != Items.NO_ARMOR and armor_type > class_data.armor_type:
		return "Cannot wear %s" % Items.ARMOR_TYPE_NAMES.get(armor_type, "this armor")
	return ""


## Flat stats this item grants while equipped: its rolled stats + EQUIP enchants.
## A weapon's own WeaponData.bonus_stats (shield armor, tome intellect) are NOT included –
## Player.equip_weapons applies them as the &"weapon:main" / &"weapon:off" sources.
## Tooltips show both (all_stats()).
func equip_stats() -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = stats.duplicate()
	for roll in enchants:
		var extra := roll.equip_stats()
		for stat in extra:
			out[stat] = out.get(stat, 0.0) + extra[stat]
	return out


## Everything shown as white stat lines in the tooltip: weapon bonus stats + rolled stats.
func all_stats() -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	if is_weapon():
		for stat in weapon.bonus_stats:
			out[stat] = weapon.bonus_stats[stat]
	for stat in stats:
		out[stat] = out.get(stat, 0.0) + stats[stat]
	return out


## Enchants that trigger (ON_HIT / ON_KILL / WHEN_STRUCK) – read by ProcSystem.
func proc_enchants() -> Array[EnchantRoll]:
	var out: Array[EnchantRoll] = []
	for roll in enchants:
		if roll.enchant != null and roll.enchant.is_proc():
			out.append(roll)
	return out


func sell_value() -> int:
	return maxi(1, roundi(buy_price * Items.SELL_SHARE))


## Gold for the shared wallet when the item goes to Greed (GDD 10.1).
func greed_value() -> int:
	return maxi(1, roundi(buy_price * Items.GREED_SHARE))


## A common-quality weapon item, e.g. a class's starting weapon.
static func from_weapon(base: WeaponData, p_rarity: int = Items.Rarity.COMMON, p_wave: int = 1,
		p_looted: bool = false) -> ItemInstance:
	var item := ItemInstance.new()
	item.source_id = base.id
	item.slot_type = Items.SlotType.WEAPON
	item.rarity = p_rarity
	item.wave = p_wave
	item.looted = p_looted
	item.item_level = Items.item_level(p_wave, p_rarity, p_looted)
	item.weapon = scaled_weapon(base, p_rarity)
	item.display_name = base.display_name
	item.buy_price = base.base_price
	return item


## A copy of [param base] with the rarity damage multiplier applied (GDD 4.1).
static func scaled_weapon(base: WeaponData, p_rarity: int) -> WeaponData:
	var w := base.duplicate() as WeaponData
	w.rarity = p_rarity
	w.base_damage = base.base_damage * Items.WEAPON_RARITY_DAMAGE[clampi(p_rarity, 0, 5)]
	w.bonus_stats = base.bonus_stats.duplicate()
	return w
