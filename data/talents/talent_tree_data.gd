class_name TalentTreeData
extends Resource
## One talent tree of a class (GDD 7.2, M5): data/talents/<class>/<tree>.tres, its talents as
## sub-resources of the same file. Three trees per class (index 0..2 in GDD order), five tiers,
## 22 points fill a tree. Loaded by Db (Db.talent_trees_for); TalentState applies the rules.

## &"warrior_arms" – stable (future saves / meta-progression).
@export var id: StringName
@export var class_id: StringName
## "Arms".
@export var display_name: String
## 0..2: column order in the Talents tab (GDD 7.2 order).
@export var index: int = 0
## One line: the build identity.
@export_multiline var description: String
## Glyph of the tree: an ability id.
@export var icon: StringName
@export var color: Color = Color.WHITE
## Sub-resources of the same .tres.
@export var talents: Array[TalentData] = []


## The talent [param talent_id] of this tree (null when it has none).
func get_talent(talent_id: StringName) -> TalentData:
	for t in talents:
		if t != null and t.id == talent_id:
			return t
	return null


## The talents of [param tier] (1..5), sorted by column.
func talents_in_tier(tier: int) -> Array[TalentData]:
	var out: Array[TalentData] = []
	for t in talents:
		if t != null and t.tier == tier:
			out.append(t)
	out.sort_custom(func(a: TalentData, b: TalentData) -> bool: return a.column < b.column)
	return out
