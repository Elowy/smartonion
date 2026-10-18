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
## First wave this base can be generated at (GDD 5.4 / 5.8, M6b). Armour bases of one slot x armour
## type are material tiers of each other: min_wave 1 (tier I, the original 32 bases), 9 (tier II)
## and 17 (tier III), at most one base per tier (Items.material_tier's thresholds). Among the
## tiers available at the wave the generator takes the highest 70% of the time and one of the
## lower ones 30% (ItemGenerator.pick_base). Jewellery bases are variety, not tiers: min_wave 1.
@export var min_wave: int = 1
