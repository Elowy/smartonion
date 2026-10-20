class_name TrailerGear
extends RefCounted
## Dev tool (tools/trailer/): dresses the bots' heroes for the camera through the game's own item API (the item
## generator and Equipment.equip, i.e. what a loot roll or the market does) – the armour shows on the onions, the
## weapons in their hands. Nothing here changes how items or heroes behave.


## Wears the five pieces of [param p]'s class tier set (Head, Shoulders, Chest, Hands, Legs) as items of [param wave].
## Returns how many pieces were equipped.
static func wear_class_set(p: Player, wave: int, rng: RandomNumberGenerator) -> int:
	if p == null or p.class_data == null:
		return 0
	var set_data := Db.set_for_class(p.class_data.id)
	if set_data == null:
		return 0
	return wear_set(p, set_data, wave, rng)


## Wears the pieces of [param set_data] that [param p] may wear.
static func wear_set(p: Player, set_data: SetData, wave: int, rng: RandomNumberGenerator) -> int:
	var worn := 0
	for id in set_data.piece_ids:
		var data := Db.get_unique(id)
		if data == null:
			continue
		var item := ItemGenerator.from_unique(data, wave, true, rng, p.class_data)
		if item.can_be_used_by(p.class_data) and p.equipment.equip(item):
			worn += 1
	return worn


## A generated weapon of [param rarity] that [param p]'s class can use, wielded at once (main hand).
static func wield_weapon(p: Player, rarity: int, wave: int, rng: RandomNumberGenerator) -> ItemInstance:
	var options := {&"usable_by": p.class_data, &"class_data": p.class_data, &"slot_type": Items.SlotType.WEAPON,
		&"rarity": rarity}
	var item := ItemGenerator.generate(ItemGenerator.Source.LOOT, wave, rng, options)
	if item != null and item.can_be_used_by(p.class_data):
		p.equipment.equip(item)
		return item
	return null


## Wields the class's Artifact (null when it has none).
static func wield_artifact(p: Player, wave: int) -> ItemInstance:
	var item := ItemGenerator.generate_artifact(p.class_data.id, wave)
	if item != null and p.equipment.equip(item):
		return item
	return null


## Dresses a hero for a close-up: the class set, then a weapon the class can wield ([param weapon_rarity], or its
## Artifact).
static func dress(p: Player, wave: int, rng: RandomNumberGenerator, weapon_rarity: int = Items.Rarity.LEGENDARY,
		artifact: bool = false) -> void:
	wear_class_set(p, wave, rng)
	if artifact:
		if wield_artifact(p, wave) != null:
			return
	wield_weapon(p, weapon_rarity, wave, rng)
