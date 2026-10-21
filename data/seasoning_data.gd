class_name SeasoningData
extends Resource
## One Seasoning (M9; GDD 17, design_m9 §3): a per-class ability side-grade chosen in the lobby – a bonus that
## gives something and takes something from ONE ability of the hero's class (Smoked Paprika: Whirlwind slows,
## costs more Rage). Instances live in res://data/seasonings/ (loaded by Db into [member Db.seasonings]).
##
## The effect is data: [member entries] holds BonusVocabulary entries (kind "ability", the mods are
## AbilityRunner.apply_mods keys: "k" replaces, "k_add" adds, "k_pct" scales an existing param, "power_pct" /
## "cooldown_pct" / "cost_add" are generic), which the hero applies as the PlayerBonuses source
## [constant Seasonings.SOURCE] when the run starts ([method Seasonings.apply]). An entry of a learnable
## ability carries {"requires": {"knows": <ability>}}: the Seasoning is dormant until the hero has learned it.
## The target [member ability] is an AbilityData id, or one of BonusVocabulary.PSEUDO_IDS (the Hunter's
## companion, the Shaman's Storm Echo – numbers that live in the kit code, not in an AbilityData).
##
## Ownership is the profile's: a Seasoning is locked until the profile owns it (Meta.is_unlocked(&"seasoning", id));
## [member tier] says how it is earned (class level + Seeds, or an achievement + Seeds, design_m9 §3).

## Tiers in unlock order: T1..T5 come with the class level, "a" / "aa" with an achievement.
const TIERS: Array[StringName] = [&"t1", &"t2", &"t3", &"t4", &"t5", &"a", &"aa"]
## Class Level a T1..T5 Seasoning becomes buyable at (design_m9 §3).
const TIER_LEVELS: Dictionary[StringName, int] = {&"t1": 3, &"t2": 6, &"t3": 9, &"t4": 13, &"t5": 17}
## Seeds price per tier (design_m9 §2).
const TIER_PRICES: Dictionary[StringName, int] = {&"t1": 60, &"t2": 80, &"t3": 100, &"t4": 140, &"t5": 180, &"a": 160, &"aa": 240}
## The id prefix every Seasoning id carries.
const ID_PREFIX := "ssn_"
## Stand-in ability icons of the pseudo targets (no AbilityData to draw): the companion shows the Phantom
## Wolf's picture, Storm Echo the Thunderbolt's.
const PSEUDO_ICONS: Dictionary[StringName, StringName] = {&"hunter_companion": &"spirit_wolf", &"shaman_echo": &"thunderbolt"}
## Player-visible names of the pseudo targets.
const PSEUDO_NAMES: Dictionary[StringName, String] = {&"hunter_companion": "Companion", &"shaman_echo": "Storm Echo"}

## Permanent id ("ssn_smoked_paprika").
@export var id: StringName
## The class that can carry it.
@export var class_id: StringName
## The ability (or BonusVocabulary pseudo id) it changes.
@export var ability: StringName
@export var display_name: String
## Tooltip: what it gives and what it costs, in plain numbers.
@export_multiline var text: String
## One of [constant TIERS].
@export var tier: StringName = &"t1"
## BonusVocabulary "ability" entries (normally exactly one).
@export var entries: Array[Dictionary] = []


## Index of [member tier] in [constant TIERS] (-1 = unknown).
func tier_index() -> int:
	return TIERS.find(tier)


## The Class Level it becomes buyable at (0 for the achievement tiers).
func unlock_level() -> int:
	return TIER_LEVELS.get(tier, 0)


## The Seeds price in The Onion Patch.
func price() -> int:
	return TIER_PRICES.get(tier, 0)


## The achievement id that opens the tier ("" for the class-level tiers): ach_clear_<class> / ach_pungent_<class>.
func unlock_achievement() -> StringName:
	match tier:
		&"a":
			return StringName("ach_clear_%s" % class_id)
		&"aa":
			return StringName("ach_pungent_%s" % class_id)
	return &""


## True when the target is a pseudo id (BonusVocabulary.PSEUDO_IDS), not an AbilityData.
func is_pseudo() -> bool:
	return BonusVocabulary.PSEUDO_IDS.has(ability)


## True when the entry waits for the hero to learn the ability ("requires": {"knows": ...}).
func is_dormant_until_learned() -> bool:
	for e in entries:
		var req: Variant = e.get("requires")
		if typeof(req) == TYPE_DICTIONARY and (req as Dictionary).has("knows"):
			return true
	return false


## The AbilityData the Seasoning changes (null for a pseudo target).
func target_ability() -> AbilityData:
	return Db.get_ability(ability)


## The ability whose picture stands for it in the UI (the target; a pseudo target uses [constant PSEUDO_ICONS]).
func icon_ability() -> AbilityData:
	return Db.get_ability(PSEUDO_ICONS.get(ability, ability))


## The target's player-visible name ("Whirlwind", "Companion").
func target_name() -> String:
	var a := target_ability()
	if a != null:
		return a.display_name
	return PSEUDO_NAMES.get(ability, String(ability).capitalize())


## How the Seasoning is earned, for the places where it is locked ("Class Level 6 · 80 Seeds").
func unlock_hint() -> String:
	var cls := Db.get_class_data(class_id)
	var who := cls.display_name if cls != null else String(class_id).capitalize()
	match tier:
		&"a":
			return "Win a run with the %s · %d Seeds" % [who, price()]
		&"aa":
			return "Win a Pungent run with the %s · %d Seeds" % [who, price()]
	return "%s Level %d · %d Seeds" % [who, unlock_level(), price()]


## The problems of one Seasoning ("" list = valid): id shape, class, target ability of that class, tier, text and
## entries that BonusVocabulary accepts (mods that name existing params). [param seen_ids] / [param seen_names] are
## the ids / names of the Seasonings checked before, so duplicates are reported (pass the same dictionaries for
## every call of one pass; the checked one is added to them).
func problems(seen_ids: Dictionary = {}, seen_names: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	var who := String(id)
	if not String(id).begins_with(ID_PREFIX) or String(id).length() <= ID_PREFIX.length():
		out.append("%s: the id must start with %s" % [who, ID_PREFIX])
	if seen_ids.has(id):
		out.append("%s: duplicate id" % who)
	seen_ids[id] = true
	if display_name.strip_edges() == "":
		out.append("%s: no display name" % who)
	elif seen_names.has(display_name):
		out.append("%s: duplicate name '%s'" % [who, display_name])
	seen_names[display_name] = true
	if text.strip_edges() == "":
		out.append("%s: no text" % who)
	if Db.get_class_data(class_id) == null:
		out.append("%s: unknown class '%s'" % [who, class_id])
	if tier_index() < 0:
		out.append("%s: unknown tier '%s'" % [who, tier])
	var a := Db.get_ability(ability)
	if a != null:
		if a.class_id != &"" and a.class_id != class_id:
			out.append("%s: ability '%s' belongs to the %s class" % [who, ability, a.class_id])
	elif is_pseudo():
		if BonusVocabulary.PSEUDO_IDS[ability] != class_id:
			out.append("%s: pseudo target '%s' belongs to the %s class" % [who, ability, BonusVocabulary.PSEUDO_IDS[ability]])
	else:
		out.append("%s: unknown ability '%s'" % [who, ability])
	if entries.is_empty():
		out.append("%s: no entries" % who)
	for e in entries:
		var problem := BonusVocabulary.validate(e, class_id)
		if problem != "":
			out.append("%s: %s" % [who, problem])
		if StringName(str(e.get("kind", ""))) != &"ability":
			out.append("%s: only ability entries are allowed" % who)
			continue
		var match_dict: Variant = e.get("match")
		if typeof(match_dict) != TYPE_DICTIONARY or StringName(str((match_dict as Dictionary).get("id", ""))) != ability:
			out.append("%s: the entry must match the ability '%s' by id" % [who, ability])
		var req: Variant = e.get("requires")
		if a != null and a.is_learned_kind() and not (typeof(req) == TYPE_DICTIONARY and StringName(str((req as Dictionary).get("knows", ""))) == ability):
			out.append("%s: a learnable ability needs requires.knows" % who)
	return out
