class_name ClassData
extends Resource
## A playable class (GDD chapter 3). Instances live in res://data/classes/.
## Adding a class = adding a new .tres here (abilities come in milestone M3).

enum ArmorType { CLOTH, LEATHER, MAIL, PLATE }

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## Short line shown in the lobby, e.g. "Melee bruiser".
@export var role: String
@export var armor_type: ArmorType = ArmorType.CLOTH
@export var primary_stat: StringName = Stats.STRENGTH
## Flat stat changes applied at run start (class identity + drawback).
@export var base_stats: Dictionary[StringName, float] = {}
@export var main_hand: WeaponData
@export var off_hand: WeaponData
## weapon_type ids the class may equip; &"dual_wield" allows one-handers in the off hand.
@export var proficiencies: Array[StringName] = []
## rage, mana, energy, holy_power, soul_shard (used from M3).
@export var resource_type: StringName
@export var resource_color: Color = Color.WHITE

@export_group("Look")
## Onion skin colour (GDD 13: Warrior red onion, Mage purple, ...).
@export var onion_color: Color = Color(0.85, 0.55, 0.3)
## Accent colour for armour trim / cloth.
@export var accent_color: Color = Color(0.9, 0.75, 0.3)
## helm_horned, wizard_hat, paladin_helm, hood, horned_hood
@export var headgear: StringName
## true -> oversized shoulder pads
@export var big_shoulders: bool = false


func can_use(weapon: WeaponData) -> bool:
	return weapon != null and weapon.weapon_type in proficiencies


func can_dual_wield() -> bool:
	return &"dual_wield" in proficiencies
