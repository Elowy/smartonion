class_name SetBonuses
extends RefCounted
## Tier-set counting and bonuses (GDD 5.5, M5, architecture §2.4): the set pieces a hero wears
## and the active 2- / 4-piece bonuses as PlayerBonuses entries (source &"set_bonus" –
## Player.apply_equipment sets them), plus the tooltip rows.
##
## P0 stub: no sets are counted; every result is empty / 0. SETS implements it.


## Set id -> pieces of that set equipped in [param _eq].
static func counts(_eq: Equipment) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	return out


## The active bonus entries of [param _eq] ("rank": 1, "id": "<set>:<n>", "label").
static func effects_for(_eq: Equipment) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	return out


## Active set bonuses of [param _eq] (SMOKE_RESULT "set_bonuses").
static func active_count(_eq: Equipment) -> int:
	return 0


## Tooltip rows for the set of [param _item] as worn in [param _eq] (may be null).
static func describe(_item: ItemInstance, _eq: Equipment) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	return out
