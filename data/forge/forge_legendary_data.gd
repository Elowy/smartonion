class_name ForgeLegendaryData
extends Resource
## The Legendary effect of one weapon type (GDD 4.1, M5): forging two Epic weapons of that base
## gives a Legendary that carries this name, effect and text (Forge.make_result). One file per
## base weapon: res://data/forge/legendary_<weapon_id>.tres, loaded lazily by Forge (not by Db).
##
## The effect is an ordinary ProcSystem effect (unique_effect = block id, unique_params = its
## params dict, header of core/items/proc_system.gd); it must also be a valid BonusVocabulary
## proc dict (tests/test_forge.gd), so it may use the M5 keys "every" (every Nth hit instead of
## a chance roll) and "hit_pct" (a share of the triggering hit's base damage). Names must not be
## WoW items (GDD 14).

## WeaponData id of the base weapon (&"dagger", &"two_hand_axe" ...).
@export var weapon_id: StringName
## Replaces the generated name of the forged Legendary ("Nettlefang").
@export var display_name: String
## ProcSystem block id (&"bolt", &"nova" ...).
@export var unique_effect: StringName
## ProcSystem params: "trigger", "every" / "chance", "hit_pct" / "damage", riders ...
@export var unique_params: Dictionary = {}
## Tooltip line of the effect (green).
@export_multiline var unique_text: String
@export_multiline var flavor: String
