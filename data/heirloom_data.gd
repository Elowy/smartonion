class_name HeirloomData
extends Resource
## One Heirloom (M9 PATCH, design_m9 §4): a persistent item a hero starts a run with (one slot per hero from Class
## Level 5, chosen in the lobby Loadout). It is made as an [ItemInstance] that starts equipped, is bound to its hero
## (never sold, traded, disenchanted, forged, enchanted or put into the team loot), and is re-scaled at every wave
## start by [Heirlooms] (budget by wave and rank, see there). Instances live in res://data/heirlooms/ (loaded by Db
## into [member Db.heirlooms]); the profile keeps what is owned and the rank ([method Profile.heirloom_rank]).
##
## The rank perks are plain BonusVocabulary entries (validated by [method problems]): [member perk3] from rank 3,
## [member perk5] from rank 5; they run as the PlayerBonuses source [constant Heirlooms.SOURCE] while the item is worn.

## The id prefix every Heirloom id carries.
const ID_PREFIX := "heir_"
const MAX_RANK := 5
## Seeds to reach rank 2 / 3 / 4 / 5 (design_m9 §2; rank 1 is free once the Heirloom is obtained).
const RANK_PRICES: Dictionary[int, int] = {2: 60, 3: 120, 4: 240, 5: 480}
const PERK3_RANK := 3
const PERK5_RANK := 5
## [member armor_rule] values: armour pieces take the hero's armour type, jewellery / trinkets have none, the weapon
## takes the weapon type of the hero's starting weapon.
const RULE_HERO := &"hero"
const RULE_ANY := &"any"
const RULE_WEAPON := &"weapon"
## [member weights] key for the hero's primary stat (Strength / Agility / Intellect by class).
const PRIMARY := &"primary"

## Permanent id ("heir_sprout_cap").
@export var id: StringName
@export var display_name: String
@export var slot_type: Items.SlotType = Items.SlotType.HEAD
## One of RULE_HERO / RULE_ANY / RULE_WEAPON.
@export var armor_rule: StringName = RULE_HERO
## Share of the budget per stat (the shares add up to 1); [constant PRIMARY] = the hero's primary stat. Empty for a
## weapon (its damage formula has no stats).
@export var weights: Dictionary[StringName, float] = {}
## BonusVocabulary entries that switch on at rank 3 / rank 5 and their one-line texts.
@export var perk3: Array[Dictionary] = []
@export var perk3_text := ""
@export var perk5: Array[Dictionary] = []
@export var perk5_text := ""
## How it is obtained, for The Onion Patch ("Reach Mage level 5", "Win a run on Pungent or higher").
@export var source_text := ""
## The class whose level 5 gives it (&"" = an achievement gives it) and the achievement id (&"" = a class gives it).
@export var gift_class: StringName
@export var achievement: StringName
@export_multiline var flavor := ""


func is_weapon() -> bool:
	return slot_type == Items.SlotType.WEAPON


## Price in Seeds of the step that reaches [param rank] (0 for rank 1 or an unknown rank).
static func price_for_rank(rank: int) -> int:
	return RANK_PRICES.get(rank, 0)


## What is wrong with this data ("" per problem = none): the prefix, a name, a valid slot and rule, shares that add
## up, perks that are valid vocabulary entries with a text, an obtain hint. [param seen_ids] / [param seen_names]
## (optional) collect the ids and names to catch duplicates across a list.
func problems(seen_ids: Dictionary = {}, seen_names: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	if not String(id).begins_with(ID_PREFIX):
		out.append("%s: the id needs the %s prefix" % [id, ID_PREFIX])
	if seen_ids.has(id):
		out.append("%s: duplicate id" % id)
	seen_ids[id] = true
	if display_name.strip_edges() == "":
		out.append("%s: no name" % id)
	if seen_names.has(display_name):
		out.append("%s: duplicate name '%s'" % [id, display_name])
	seen_names[display_name] = true
	if armor_rule not in [RULE_HERO, RULE_ANY, RULE_WEAPON]:
		out.append("%s: unknown armor rule '%s'" % [id, armor_rule])
	if is_weapon() != (armor_rule == RULE_WEAPON):
		out.append("%s: the weapon rule goes with the weapon slot (and only with it)" % id)
	if (slot_type in Items.ARMOR_SLOTS) != (armor_rule == RULE_HERO):
		out.append("%s: armour pieces take the hero's armour, jewellery and trinkets have none" % id)
	if is_weapon():
		if not weights.is_empty():
			out.append("%s: a weapon has no stat shares" % id)
	else:
		var total := 0.0
		for stat in weights:
			total += weights[stat]
			if stat != PRIMARY and stat not in Stats.ALL:
				out.append("%s: unknown stat '%s'" % [id, stat])
			if weights[stat] <= 0.0:
				out.append("%s: the share of '%s' must be positive" % [id, stat])
		if not is_equal_approx(total, 1.0):
			out.append("%s: the shares add up to %s, not 1" % [id, total])
	for perk: Array in [[perk3, perk3_text, "perk3"], [perk5, perk5_text, "perk5"]]:
		var entries: Array[Dictionary] = perk[0]
		if entries.is_empty():
			out.append("%s: %s has no entry" % [id, perk[2]])
		if String(perk[1]).strip_edges() == "":
			out.append("%s: %s has no text" % [id, perk[2]])
		for e in entries:
			var error := BonusVocabulary.validate(e)
			if error != "":
				out.append("%s: %s: %s" % [id, perk[2], error])
	if source_text.strip_edges() == "":
		out.append("%s: no obtain hint" % id)
	if (gift_class == &"") == (achievement == &""):
		out.append("%s: exactly one of gift_class / achievement says where it comes from" % id)
	return out
