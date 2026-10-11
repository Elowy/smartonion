class_name AbilityRanks
extends RefCounted
## Ability ranks I–V (GDD 6.3): what each rank changes and what the Trainer charges.
##   Rank II and IV: +25 % damage / effect ("power" param) and −10 % cooldown each.
##   Rank III: the ability's own [member AbilityData.rank3] mods (+1 extra effect).
##   Rank V: the chosen specialisation's mods ([member AbilityData.specs]), applied as a pass
##   of their own on top of Ranks II–IV ([method spec_mods]), so a spec's "_pct" key scales
##   the Rank IV value ("cooldown 30% shorter" = ×0.7 of the Rank IV cooldown).
## Effects read the result through AbilityRunner.params_for: multiply damage / heal / shield
## amounts by ctx.num("power", 1.0).

const MAX_RANK := 5
const POWER_PCT_PER_STEP := 25.0
const COOLDOWN_PCT_PER_STEP := -10.0
## Trainer: 25 g × current rank × (1 + 8 % per wave after the first).
const TRAINER_BASE_PRICE := 25.0
const TRAINER_WAVE_GROWTH := 0.08
## Share of the ranks' gold value refunded when a learned ability is replaced (GDD 6.2).
const REPLACE_REFUND := 0.5


## Item-mod style changes for [param ability] at [param rank] (1..5): the Rank II / IV steps
## and Rank III's mods. With Rank V specialisation [param spec] (-1 = none chosen yet) its mods
## are merged in too (numbers summed) – a one-dict summary; AbilityRunner.params_at_rank
## applies [method spec_mods] as a separate pass instead.
static func mods_for(ability: AbilityData, rank: int, spec: int = -1) -> Dictionary:
	var out: Dictionary = {}
	if ability == null:
		return out
	var steps := (1 if rank >= 2 else 0) + (1 if rank >= 4 else 0)
	if steps > 0:
		out["power_pct"] = POWER_PCT_PER_STEP * steps
		out["cooldown_pct"] = COOLDOWN_PCT_PER_STEP * steps
	if rank >= 3:
		_merge(out, ability.rank3)
	_merge(out, spec_mods(ability, rank, spec))
	return out


## The mods of Rank V specialisation [param spec] (empty below Rank V or without a valid spec).
## Applied after [method mods_for] (rank only), so "_pct" keys compound with the rank steps.
static func spec_mods(ability: AbilityData, rank: int, spec: int) -> Dictionary:
	if ability == null or rank < MAX_RANK or spec < 0 or spec >= ability.specs.size():
		return {}
	return ability.specs[spec].get("mods", {})


## Gold for the next rank (from [param rank] to rank + 1) at [param wave]; 0 at Rank V.
static func trainer_price(rank: int, wave: int) -> int:
	if rank < 1 or rank >= MAX_RANK:
		return 0
	return roundi(TRAINER_BASE_PRICE * rank * (1.0 + TRAINER_WAVE_GROWTH * float(maxi(1, wave) - 1)))


## What ranks above I are worth in gold at [param wave] (the Trainer prices to get there).
static func gold_value(rank: int, wave: int) -> int:
	var total := 0
	for r in range(1, mini(rank, MAX_RANK)):
		total += trainer_price(r, wave)
	return total


## Gold back when an ability at [param rank] is replaced (50 % of its ranks' value).
static func replace_refund(rank: int, wave: int) -> int:
	return floori(gold_value(rank, wave) * REPLACE_REFUND)


## Short text of what reaching [param rank] adds (Trainer / rank-up cards).
static func rank_text(ability: AbilityData, rank: int) -> String:
	match rank:
		2, 4:
			return "+25% damage and effect, -10% cooldown"
		3:
			return ability.rank3_text if ability != null and ability.rank3_text != "" else "+1 extra effect"
		5:
			return "Specialization: choose 1 of 2"
	return ""


## Sums numbers, replaces anything else ([param extra] wins).
static func _merge(into: Dictionary, extra: Dictionary) -> void:
	for key: Variant in extra:
		var v: Variant = extra[key]
		var old: Variant = into.get(key)
		if old != null and typeof(old) in [TYPE_INT, TYPE_FLOAT] and typeof(v) in [TYPE_INT, TYPE_FLOAT]:
			into[key] = float(old) + float(v)
		else:
			into[key] = v
