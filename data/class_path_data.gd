class_name ClassPathData
extends Resource
## What is special about one class's path through the Class Levels (M9 LEVELS, design 1.3): the learnable abilities
## that start locked, the capstone trees in the order they open, the alternative starting weapon, the gift Heirloom,
## the level cosmetics and the title. Instances live in res://data/meta/class_paths/ (one per class, loaded by Db,
## [method Db.class_path]); the reward list that says WHICH level gives what is the [ClassLevelTable].

@export var class_id: StringName
## Learnable abilities locked at the start, in the order the table's "ability" rewards open them (level 2, 4).
@export var deck_abilities: Array[StringName] = []
## Talent tree ids whose capstone opens, in the order of the table's "capstone" rewards (level 8, 16, 24).
@export var capstone_trees: Array[StringName] = []
## The alternative starting weapon (replaces the class's main hand; the off hand too: null = none).
@export var alt_main_hand: WeaponData
@export var alt_off_hand: WeaponData
## The Heirloom the class gives at level 5 (HeirloomData id) and its display name (the Heirloom data is another
## package's; this is the line shown in the reward list until it is looked up).
@export var gift_heirloom: StringName
@export var gift_heirloom_name := ""
## Level cosmetics: [{"slot": "tabard" | "hat" | "glow", "id": "cos_warrior_tabard", "name": "Ironhide Tabard"}].
@export var cosmetics: Array[Dictionary] = []
@export var title_id: StringName
@export var title_name := ""


## The cosmetic entry of [param slot] ({} = none).
func cosmetic(slot: StringName) -> Dictionary:
	for c in cosmetics:
		if StringName(str(c.get("slot", ""))) == slot:
			return c
	return {}


## True when the class has an alternative starting weapon.
func has_alt_weapon() -> bool:
	return alt_main_hand != null


## The ids of every learnable ability this path locks.
func locked_abilities() -> Array[StringName]:
	return deck_abilities.duplicate()
