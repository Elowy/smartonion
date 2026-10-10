class_name AbilityData
extends Resource
## An active ability (GDD 3, 6). Instances live in res://data/abilities/.
## The behaviour is an AbilityEffect script; numbers live in [member params] so items
## (ability_mod), ranks (M4) and talents (M5) can change them without code.

## Where the ability goes. All targeting is automatic (GDD decision: no manual aim).
enum Targeting { SELF, NEAREST_ENEMY, DENSEST_CLUSTER, MOVE_DIRECTION, ALLY }

@export var id: StringName
@export var display_name: String
## Tooltip text with {param} placeholders filled from params (after mods).
@export_multiline var description: String
## Class that owns it (&"" = any class, for the M4 general pool).
@export var class_id: StringName
## physical, fire, frost, arcane, holy, shadow, nature (talents / school % use it).
@export var school: StringName = &"physical"
## Resource id it spends (&"rage", &"mana", ...; &"" = free).
@export var resource: StringName
@export var cost: float = 0.0
## Seconds at Haste 0 / Cooldown Reduction 0 (0 = only limited by the resource).
@export var cooldown: float = 0.0
@export var targeting: Targeting = Targeting.NEAREST_ENEMY
## Metres: targets / clusters further than this are ignored.
@export var cast_range: float = 10.0
## Behaviour script, must extend AbilityEffect.
@export var effect: Script
@export var params: Dictionary = {}
## Icon style id for the HUD (drawn procedurally).
@export var icon: StringName
@export var color: Color = Color.WHITE
