class_name SetData
extends Resource
## A tier set (GDD 5.5, M5): data/sets/<set_id>.tres, loaded by Db (Db.sets). Five Epic,
## class-restricted pieces (UniqueItemData with this [member id] as set_id; none for a
## class-independent set, see [member class_id]) and cumulative 2- /
## 4-piece bonuses in the bonus vocabulary (BonusVocabulary). SetBonuses counts the worn pieces
## and turns the active bonuses into PlayerBonuses entries (source &"set_bonus").

## &"battlegear_of_fury" (= UniqueItemData.set_id of its pieces).
@export var id: StringName
@export var display_name: String
## The class the set belongs to (its pieces are restricted to it), or &"" = class-independent (M8):
## its pieces carry no class_restriction and have no primary stat; any class that can wear them may
## equip and Need them, but only the classes of its [member armor_type] (the "native" ones) roll it
## as loot or find it in the shop (Db.sets_for_class, ItemGenerator.independent_sets_for).
@export var class_id: StringName
## ClassData.ArmorType of all five pieces of a class-independent set (0..3); -1 for a class set, whose
## pieces take the armour of the class.
@export var armor_type: int = -1
## UniqueItemData ids of the pieces (Head, Shoulders, Chest, Hands, Legs).
@export var piece_ids: Array[StringName] = []
## [{"pieces": 2, "text": "...", "effects": [entries]}, {"pieces": 4, ...}] – bonuses add up
## (4 pieces = the 2-piece and the 4-piece bonus).
@export var bonuses: Array[Dictionary] = []


## Whether the set belongs to no class (SetData.class_id empty).
func is_independent() -> bool:
	return class_id == &""
