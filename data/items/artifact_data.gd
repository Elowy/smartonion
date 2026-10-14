class_name ArtifactData
extends UniqueItemData
## A class Artifact (GDD 5.5 "Artifact fegyverek", M6 ARTIFACTS): the one weapon a class can
## find per run. A UniqueItemData (rarity Artifact, weapon = the main-hand weapon, stats,
## fixed enchants, class_restriction = the class) plus the two special properties that awaken
## while the hero holds it, and an optional off-hand piece (Fangs of the Shadow). Instances live
## in res://data/artifacts/ and are loaded by Db into [member Db.artifacts] (NOT into
## Db.uniques: the normal item pools never see them – an Artifact only comes from
## LootDrops.roll_artifact through ItemGenerator.generate_artifact).
##
## A property is a Dictionary:
##   "name"     the title shown in the tooltip ("Earthquake")
##   "text"     the tooltip line, golden once awake ("Whirlwind leaves an earthquake zone ...")
##   "needs"    optional ability id the hero must have learned for it to work ("whirlwind"); the
##              tooltip greys the line with "(needs Whirlwind)" while the hero lacks it (the
##              engine entries also carry {"requires": {"knows": ...}})
##   "effects"  Array of BonusVocabulary entries (BonusVocabulary.validate with the class id):
##              applied through PlayerBonuses.set_effects(&"artifact", ...) while the Artifact is
##              equipped and the property is awake (Artifacts.effects_for)
## properties[0] awakens after unlock_waves[0] wave ends held, properties[1] after unlock_waves[1].

## The Artifact's class id (&"warrior" ...), also the item's class_restriction.
@export var class_id: StringName
## Wave ends held before property 1 / property 2 awaken (GDD: 3 and 6).
@export var unlock_waves: Array[int] = [3, 6]
@export var properties: Array[Dictionary] = []
## Tint of the weapon model / icon (alpha 0 = the base weapon's colour).
@export var weapon_color: Color = Color(0, 0, 0, 0)

@export_group("Pair (Fangs of the Shadow)")
## The off-hand piece of a pair: equips / unequips together with the main hand and counts as
## the same Artifact. Null for a single weapon.
@export var pair_weapon: WeaponData
@export var pair_name: String
## Stats of the off-hand piece (scaled like [member stats]).
@export var pair_stats: Dictionary[StringName, float] = {}
## Fixed enchants of the off-hand piece (ids and ranks, like [member enchant_ids]).
@export var pair_enchant_ids: Array[StringName] = []
@export var pair_enchant_ranks: Array[int] = []


func is_pair() -> bool:
	return pair_weapon != null


## Wave ends held before property [param index] (0 / 1) awakens.
func unlock_after(index: int) -> int:
	if index < 0 or index >= properties.size():
		return 0
	return unlock_waves[index] if index < unlock_waves.size() else 3 * (index + 1)
