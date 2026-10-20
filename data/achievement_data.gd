class_name AchievementData
extends Resource
## One achievement (GDD 17.5, M9 meta-progression). Instances live in res://data/achievements/ (loaded by Db
## into [member Db.achievements]); the evaluator is [AchievementEngine], the condition vocabulary is documented
## there. An achievement is checked when a run ends (against the [RunReport] and the profile's counters), and
## again whenever [method Meta.check_achievements] is called; once unlocked it stays unlocked.
##
## The condition is a [member condition_kind] plus its [member condition_params] (see
## [method condition]); compound kinds (all_of / any_of / not) nest further condition dictionaries. The rewards
## are unlocks recorded in the profile when the achievement unlocks: [code]{"kind": "seasoning", "id": "..."}[/code]
## (kind: one of Profile.KINDS; a class-scoped kind such as "difficulty" also needs [code]"class_id"[/code]).

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
## Achievement points (the profile's achievement score is the sum of its unlocked achievements).
@export var points := 0
## Hidden achievements show their name and text only once unlocked.
@export var hidden := false
## One of AchievementEngine.CONDITION_KINDS.
@export var condition_kind: StringName
## The parameters of the condition kind (stat, value, class_id ...).
@export var condition_params: Dictionary = {}
## Unlocks granted with the achievement: [{"kind": StringName, "id": StringName, "class_id"?: StringName}].
@export var rewards: Array[Dictionary] = []


## The whole condition as one flat dictionary: [code]{"kind": condition_kind, ...condition_params}[/code].
func condition() -> Dictionary:
	var out: Dictionary = condition_params.duplicate(true)
	out["kind"] = condition_kind
	return out
