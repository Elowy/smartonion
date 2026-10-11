class_name StatCards
extends RefCounted
## Stat level-up cards (GDD 6.1): a rarity, then 1–3 stats drawn from a weighted table with a
## per-stat unit amount ("Common: +3 Stamina", "Rare: +3% Crit and +2 Agility").
##   Common   1 stat  x 1.0      Uncommon 1 stat x 2.0
##   Rare     2 stats x 1.5, 1.0 Epic     3 stats x 1.5
## Primary stats: only the class's own. Randomness: the caller's rng (RunState.rng).

const RARITY_WEIGHTS: Array[float] = [50.0, 30.0, 15.0, 5.0]  # Common .. Epic
const RARITY_MULTS: Array = [[1.0], [2.0], [1.5, 1.0], [1.5, 1.5, 1.5]]
## Stat -> [unit amount, weight]. The class primary stat is added separately.
const TABLE := {
	Stats.STAMINA: [3.0, 14.0],
	Stats.CRIT: [2.0, 8.0],
	Stats.HASTE: [3.0, 8.0],
	Stats.MASTERY: [3.0, 6.0],
	Stats.VERSATILITY: [2.0, 6.0],
	Stats.ARMOR: [2.0, 7.0],
	Stats.DODGE: [2.0, 5.0],
	Stats.SPEED: [3.0, 4.0],
	Stats.DAMAGE_PCT: [5.0, 10.0],
	Stats.SPIRIT: [2.0, 5.0],
	Stats.LEECH: [1.0, 3.0],
	Stats.CRIT_DAMAGE: [8.0, 3.0],
	Stats.AREA_SIZE: [6.0, 3.0],
	Stats.COOLDOWN_REDUCTION: [3.0, 3.0],
	Stats.RESOURCE_REGEN: [8.0, 3.0],
	Stats.PICKUP_RANGE: [15.0, 2.0],
}
const PRIMARY_UNIT := 2.0
const PRIMARY_WEIGHT := 14.0


static func roll_rarity(rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in RARITY_WEIGHTS:
		total += w
	var r := rng.randf() * total
	for i in RARITY_WEIGHTS.size():
		r -= RARITY_WEIGHTS[i]
		if r < 0.0:
			return i
	return 0


## A card's stats for [param rarity] (0..3) and [param class_data] (primary stat).
static func roll_stats(rng: RandomNumberGenerator, rarity: int, class_data: ClassData) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	var table := _table_for(class_data)
	var mults: Array = RARITY_MULTS[clampi(rarity, 0, RARITY_MULTS.size() - 1)]
	for m: float in mults:
		var stat := _pick(rng, table, out)
		if stat == &"":
			break
		out[stat] = _amount(table[stat][0] * m)
	return out


static func _table_for(class_data: ClassData) -> Dictionary:
	var table := TABLE.duplicate()
	if class_data != null and class_data.primary_stat != &"":
		table[class_data.primary_stat] = [PRIMARY_UNIT, PRIMARY_WEIGHT]
	return table


## Weighted pick of a stat not in [param taken] (table order: deterministic).
static func _pick(rng: RandomNumberGenerator, table: Dictionary, taken: Dictionary) -> StringName:
	var total := 0.0
	for stat: StringName in table:
		if not taken.has(stat):
			total += float(table[stat][1])
	if total <= 0.0:
		return &""
	var r := rng.randf() * total
	for stat: StringName in table:
		if taken.has(stat):
			continue
		r -= float(table[stat][1])
		if r < 0.0:
			return stat
	return &""


## Whole numbers (rounded half up), at least 1.
static func _amount(v: float) -> float:
	return maxf(1.0, floorf(v + 0.5))
