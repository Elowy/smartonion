class_name ItemGenerator
extends RefCounted
## STUB – owned by the "items-gen" agent. Random item creation (GDD 5.2, 5.4, 5.6.1, 10.1).

enum Source { SHOP, LOOT, ELITE, GOBLIN, BOSS }


## Rarity for [param source] at [param wave] (shop / loot tables of GDD 5.2, interpolated
## between the listed waves; Fortune shifts towards higher rarities; shop max Epic).
static func roll_rarity(source: Source, wave: int, fortune: float, rng: RandomNumberGenerator) -> int:
	return Items.Rarity.COMMON


## A new random item. [param options] (all optional):
##   &"class_data": ClassData – bias the base / weapon / stats towards what this class can use
##   &"usable_by": ClassData – only items this class can use
##   &"slot_type": Items.SlotType – force the slot
##   &"rarity": int – force the rarity
##   &"fortune": float
static func generate(source: Source, wave: int, rng: RandomNumberGenerator, options: Dictionary = {}) -> ItemInstance:
	return ItemInstance.from_weapon(Db.get_weapon(&"sword"))


## A weapon item of [param base] (rarity damage multiplier, bonus stats, enchants).
static func generate_weapon(base: WeaponData, rarity: int, wave: int, looted: bool, rng: RandomNumberGenerator) -> ItemInstance:
	return ItemInstance.from_weapon(base, rarity, wave, looted)


## A hand-designed item instance.
static func from_unique(data: UniqueItemData, wave: int, looted: bool, rng: RandomNumberGenerator) -> ItemInstance:
	return ItemInstance.new()


## Shop price: rarity base price x (1 + 0.08 x (wave - 1)) (GDD 10).
static func price_for(rarity: int, wave: int) -> int:
	return 15
