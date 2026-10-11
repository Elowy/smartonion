class_name TalentData
extends Resource
## One talent of a TalentTreeData (GDD 7.2, M5): a sub-resource of its tree's .tres
## (data/talents/<class>/<tree>.tres). Its [member effects] are bonus-vocabulary entries
## (BonusVocabulary, talent_vocabulary.md) with every amount written for rank 1 – the engine
## scales them by the rank (BonusVocabulary.resolve). TalentState holds the ranks a hero has.

## TALENT: tiers 1–4, max 3 (tier 3: max 2); MODIFIER: tier 3, max 1, changes [member ability];
## CAPSTONE: tier 5, max 1.
enum Kind { TALENT, MODIFIER, CAPSTONE }

## Globally unique, prefixed with the tree id: &"warrior_arms_deflection". Never renamed.
@export var id: StringName
@export var display_name: String
## "{key}" placeholders are filled from [member values] x the rank ([method text_for_rank]).
@export_multiline var description: String
## Per-rank numbers for the text ({"dodge": 2.0}); keys ending in "_fixed" are not multiplied.
@export var values: Dictionary = {}
@export var kind: Kind = Kind.TALENT
## 1..5 (gates: TalentState.TIER_POINTS).
@export var tier: int = 1
## 0 / 1 (a capstone is centred; ignored).
@export var column: int = 0
@export var max_rank: int = 3
## Another talent of the same tree, in a lower tier, that must be at its max rank first ("" =
## none). Not the entry key "requires" of the bonus vocabulary, which is a condition dict.
@export var prerequisite: StringName
## MODIFIER: the ability it changes (icon, "You haven't learned X" hint, bots defer it).
@export var ability: StringName
## Glyph: an ability id, a stat id or "" (the kind's default glyph).
@export var icon: StringName
## Bonus-vocabulary entries, amounts per rank (see BonusVocabulary).
@export var effects: Array[Dictionary] = []


## [member description] with the numbers of [param rank] (rank 0 – not taken yet – shows the
## rank-1 numbers). Whole numbers print without decimals, others with up to two.
func text_for_rank(rank: int) -> String:
	var r := maxi(1, rank)
	var filled := {}
	for key: Variant in values:
		var name := String(key)
		var v: Variant = values[key]
		if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
			filled[name] = format_number(float(v) if name.ends_with("_fixed") else float(v) * r)
		else:
			filled[name] = str(v)
	return description.format(filled)


func is_capstone() -> bool:
	return kind == Kind.CAPSTONE


func is_modifier() -> bool:
	return kind == Kind.MODIFIER


## "6", "0.9", "1.25": no trailing zeros, at most two decimals.
static func format_number(v: float) -> String:
	var rounded := snappedf(v, 0.01)
	if is_equal_approx(rounded, roundf(rounded)):
		return str(int(roundf(rounded)))
	var text := "%.2f" % rounded
	while text.ends_with("0"):
		text = text.left(text.length() - 1)
	return text.trim_suffix(".")
