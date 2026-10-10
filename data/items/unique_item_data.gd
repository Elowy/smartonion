class_name UniqueItemData
extends Resource
## A hand-designed item: trinket, Legendary, named Rare/Epic, class-specific item or set piece
## (GDD 5.5). Instances live in res://data/uniques/.

@export var id: StringName
@export var display_name: String
@export_multiline var flavor: String
@export var slot_type: Items.SlotType = Items.SlotType.TRINKET
@export var armor_type: int = Items.NO_ARMOR
@export var rarity: int = Items.Rarity.RARE
## Weapons: the base weapon (rarity scaling is applied on top).
@export var weapon: WeaponData
@export var stats: Dictionary[StringName, float] = {}
## Fixed enchantments: ids from res://data/enchants/ and their ranks (0..2).
@export var enchant_ids: Array[StringName] = []
@export var enchant_ranks: Array[int] = []
## Only this class may use it (&"" = any class). Shown as "Classes: Mage".
@export var class_restriction: StringName
## Special behaviour handled by ProcSystem (legendary procs, class ability modifiers ...).
@export var unique_effect: StringName
@export var unique_params: Dictionary = {}
## Tooltip line for the unique effect (green "Equip:" / "Chance on hit:" line).
@export_multiline var unique_text: String
@export var set_id: StringName
## Where it can appear: &"shop", &"loot", &"elite", &"goblin", &"boss".
@export var sources: Array[StringName] = [&"loot"]
@export var min_wave: int = 1
@export var weight: float = 1.0
