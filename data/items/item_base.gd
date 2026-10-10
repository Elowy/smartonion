class_name ItemBase
extends Resource
## A generated item's base type, e.g. "Plate Helm" (GDD 5.4). Instances in res://data/item_bases/.
## Weapons are not ItemBases – weapon items come from res://data/weapons/ (WeaponData).

@export var id: StringName
## Base name without material, e.g. "Helm" -> "Runed Plate Helm" / "Silk Cowl".
@export var display_name: String
@export var slot_type: Items.SlotType = Items.SlotType.HEAD
## ClassData.ArmorType, or Items.NO_ARMOR for neck / ring / trinket.
@export var armor_type: int = Items.NO_ARMOR
@export var weight: float = 1.0
## Visual piece for the onion model (head / shoulders / chest pieces; M7).
@export var look: StringName
