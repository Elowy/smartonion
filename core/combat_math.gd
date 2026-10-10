class_name CombatMath
extends RefCounted
## Pure combat formulas (GDD 2.5). No scene access – unit tested in tests/test_combat_math.gd.

## Damage kinds used for Avoidance (only AOE and PROJECTILE are reduced by it).
const KIND_MELEE := &"melee"
const KIND_PROJECTILE := &"projectile"
const KIND_AOE := &"aoe"

const ARMOR_CONSTANT := 15.0
const MIN_DAMAGE := 1.0


## Damage of one weapon hit before crit, with stat scaling and the damage multiplier.
static func weapon_hit_damage(weapon: WeaponData, stats: StatBlock) -> float:
	var base := weapon.base_damage
	for stat in weapon.scaling:
		base += stats.get_raw(stat) * weapon.scaling[stat]
	return maxf(MIN_DAMAGE, base * stats.damage_mult())


## Seconds between attacks, after Haste.
static func weapon_cooldown(weapon: WeaponData, stats: StatBlock) -> float:
	return maxf(0.08, weapon.cooldown / maxf(0.2, stats.attack_speed_mult()))


static func roll_crit(stats: StatBlock, rng: RandomNumberGenerator) -> bool:
	return rng.randf() * 100.0 < stats.get_stat(Stats.CRIT)


## Fraction of damage removed by armour. Negative armour makes it negative (= more damage).
static func armor_reduction(armor: float) -> float:
	if armor >= 0.0:
		return armor / (armor + ARMOR_CONSTANT)
	return armor / (ARMOR_CONSTANT - armor)


## Damage a player actually takes from a raw enemy hit (dodge / block are rolled separately).
## Not rounded – fractional reductions from small Armor / Versatility / Avoidance values
## count; only the displayed numbers are rounded. At least MIN_DAMAGE.
static func incoming_damage(raw: float, stats: StatBlock, kind: StringName = KIND_MELEE) -> float:
	var dmg := raw * (1.0 - armor_reduction(stats.get_stat(Stats.ARMOR)))
	var vers_reduction := minf(stats.get_stat(Stats.VERSATILITY) / 2.0, Stats.VERSATILITY_REDUCTION_CAP)
	dmg *= 1.0 - maxf(0.0, vers_reduction) / 100.0
	if kind == KIND_AOE or kind == KIND_PROJECTILE:
		dmg *= 1.0 - stats.get_stat(Stats.AVOIDANCE) / 100.0
	return maxf(MIN_DAMAGE, dmg)


static func roll_dodge(stats: StatBlock, rng: RandomNumberGenerator) -> bool:
	return rng.randf() * 100.0 < stats.get_stat(Stats.DODGE)


static func roll_leech(stats: StatBlock, rng: RandomNumberGenerator) -> bool:
	return rng.randf() * 100.0 < stats.get_stat(Stats.LEECH)


static func roll_block(block_chance: float, rng: RandomNumberGenerator) -> bool:
	return rng.randf() * 100.0 < block_chance


## Exact (fractional) gold a player with [param stats] gains for picking up [param amount].
## Not rounded: RunState.add_gold_for keeps the fraction per player slot, so small Gold Find
## values add up over many pickups instead of being rounded away on every 1-gold coin.
static func gold_with_find(amount: int, stats: StatBlock) -> float:
	return gold_with_find_pct(amount, stats.get_stat(Stats.GOLD_FIND))


## [param amount] gold with [param gold_find_pct] percent Gold Find (never negative).
static func gold_with_find_pct(amount: float, gold_find_pct: float) -> float:
	return maxf(0.0, amount * (1.0 + gold_find_pct / 100.0))
