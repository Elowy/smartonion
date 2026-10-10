class_name AffixData
extends Resource
## A stat suffix such as "of the Bear" (GDD 5.4). Instances live in res://data/affixes/.

@export var id: StringName
## e.g. "of the Bear"
@export var suffix: String
## Stats this suffix spends the item's budget on.
@export var stats: Array[StringName] = []
## Share of the budget per stat (same order as stats; normalised by the generator).
@export var shares: Array[float] = []
@export var weight: float = 1.0
## Items.SlotType values this suffix may roll on (empty = any).
@export var slot_types: Array[int] = []
