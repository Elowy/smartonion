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
## anyone who can wear the pieces may roll and collect it (Db.sets_for_class); its pieces carry no
## class_restriction and have no primary stat.
@export var class_id: StringName
## UniqueItemData ids of the pieces (Head, Shoulders, Chest, Hands, Legs).
@export var piece_ids: Array[StringName] = []
## [{"pieces": 2, "text": "...", "effects": [entries]}, {"pieces": 4, ...}] – bonuses add up
## (4 pieces = the 2-piece and the 4-piece bonus).
@export var bonuses: Array[Dictionary] = []
