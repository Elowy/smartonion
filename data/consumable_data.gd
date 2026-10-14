class_name ConsumableData
extends Resource
## A shop consumable (GDD 10, M6 SHOPSINKS): a flask / elixir (POTION) or a food (FOOD). Instances
## live in res://data/consumables/ (loaded by Db into Db.consumables).
##
## Bought in the market for one hero, applied at the next wave start and gone at that wave's
## end. At most one POTION and one FOOD are pending per hero; a new one replaces the pending
## one. The effects are BonusVocabulary entries (core/bonus/bonus_vocabulary.gd) so they go
## through PlayerBonuses.set_effects(&"consumable", ...) like talent and set bonuses.

enum Kind { POTION, FOOD }

@export var id: StringName
@export var display_name: String
@export var kind: Kind = Kind.POTION
## BonusVocabulary entries, e.g. {"kind": "damage", "pct": 15.0}; see PlayerBonuses.
@export var effects: Array[Dictionary] = []
## Gold at the shop price multiplier 1 (the stall scales it with the wave).
@export var base_price := 10
## Icon id for the card and the unit frame (UiIcon / ItemArt looks it up).
@export var icon_id: StringName
@export_multiline var description := ""


func is_potion() -> bool:
	return kind == Kind.POTION


func is_food() -> bool:
	return kind == Kind.FOOD
