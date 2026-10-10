class_name LootBag
extends Node3D
## STUB – owned by the "shop-loot" agent. An item on the ground: a small bag with a light beam
## in the item's rarity colour. Any living player walking over it sends it to the team loot
## (RunState.team_loot); at wave end the remaining bags are banked too. Group &"loot_bags".

var item: ItemInstance


static func create(p_item: ItemInstance) -> LootBag:
	var b := LootBag.new()
	b.item = p_item
	return b


## Wave end: moves the item to RunState.team_loot and frees the bag.
func collect_to_bank() -> void:
	queue_free()
