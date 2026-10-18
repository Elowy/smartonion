class_name CombatMath
extends RefCounted
## Pure combat formulas (GDD 2.5). No scene access – unit tested in tests/test_combat_math.gd.

## Damage kinds used for Avoidance (only AOE and PROJECTILE are reduced by it).
const KIND_MELEE := &"melee"
const KIND_PROJECTILE := &"projectile"
const KIND_AOE := &"aoe"

const ARMOR_CONSTANT := 15.0
const MIN_DAMAGE := 1.0

const SCHOOL_PHYSICAL := &"physical"
## Attack Power / Spell Power on weapon hits is normalised to the weapon's speed (GDD 2.4.1):
## a hit gains power x (weapon cooldown / this), so every weapon gains the same DPS per point.
const POWER_REFERENCE_COOLDOWN := 1.0
## Proc damage gains this much per point of Spell Power (spell schools) / Attack Power
## (physical procs) – "20 Fire damage (+Spell Power)" (GDD 5.7).
const PROC_POWER_SCALE := 1.0
## Executioner applies to targets below this HP fraction (GDD 2.4.1).
const EXECUTE_THRESHOLD := 0.3
## Parry chance cap (percent) – like Dodge, never a guaranteed negation.
const PARRY_CAP := 50.0
## A block absorbs this fraction of the hit before Block Value (Player.BLOCK_DAMAGE_MULT).
const BASE_BLOCK_ABSORB := 0.5
## A block never absorbs more than this fraction, whatever the Block Value (M5: block chance
## from talents / sets must not turn blocks into immunity).
const BLOCK_ABSORB_CAP := 0.85


## Flat damage of one weapon hit before the % multipliers: base damage + stat scaling +
## speed-normalised Attack Power (physical weapons) or Spell Power (magic weapons).
static func weapon_base_damage(weapon: WeaponData, stats: StatBlock) -> float:
	var base := weapon.base_damage
	for stat in weapon.scaling:
		base += stats.get_raw(stat) * weapon.scaling[stat]
	return base + weapon_power_bonus(weapon, stats)


## Attack Power (physical) / Spell Power (magic weapons) added to each hit of [param weapon],
## normalised by its base cooldown (Haste does not shrink it).
static func weapon_power_bonus(weapon: WeaponData, stats: StatBlock) -> float:
	var power := stats.get_raw(Stats.SPELL_POWER if weapon.is_magic() else Stats.ATTACK_POWER)
	if power == 0.0:
		return 0.0
	return power * weapon.cooldown / POWER_REFERENCE_COOLDOWN


## Damage of one weapon hit before crit, with stat scaling, power and the damage multiplier
## (Versatility + Damage % + the weapon's school %, GDD 2.5). Target-dependent bonuses
## (Executioner, Slayer) come from [method target_damage_mult].
static func weapon_hit_damage(weapon: WeaponData, stats: StatBlock) -> float:
	return maxf(MIN_DAMAGE, weapon_base_damage(weapon, stats) * damage_mult_for(stats, weapon.school))


## School damage % of [param school] (0 for an unknown school).
static func school_pct(stats: StatBlock, school: StringName) -> float:
	var stat: StringName = Stats.SCHOOL_STATS.get(school, &"")
	return stats.get_raw(stat) if stat != &"" else 0.0


## 1 + (Versatility + Damage % + school %) / 100 – the additive "other %" of GDD 2.5.
static func damage_mult_for(stats: StatBlock, school: StringName) -> float:
	return maxf(0.0, stats.damage_mult() + school_pct(stats, school) / 100.0)


## Crit multiplier of [param weapon]: its own (x2, dagger x2.5) + Critical Damage % (additive:
## +15% turns x2 into x2.15). Never below 1.
static func crit_multiplier(weapon: WeaponData, stats: StatBlock) -> float:
	var base := weapon.crit_mult if weapon != null else 2.0
	return maxf(1.0, base + stats.get_raw(Stats.CRIT_DAMAGE) / 100.0)


## Multiplier against one target: Executioner below EXECUTE_THRESHOLD of its HP, Slayer vs
## elites / bosses (these two multiply – they depend on the target, not on the hit).
static func target_damage_mult(stats: StatBlock, target_hp_ratio: float, target_is_elite: bool) -> float:
	var m := 1.0
	if target_hp_ratio < EXECUTE_THRESHOLD:
		m *= 1.0 + stats.get_raw(Stats.EXECUTIONER) / 100.0
	if target_is_elite:
		m *= 1.0 + stats.get_raw(Stats.SLAYER) / 100.0
	return maxf(0.0, m)


## Damage of a proc of [param school] with base [param base] (GDD 5.7): + Spell Power for
## spell schools / + Attack Power for physical ones (PROC_POWER_SCALE), times Versatility +
## Damage % + school %. Procs never crit. 0 stays 0.
static func proc_damage(base: float, school: StringName, stats: StatBlock) -> float:
	if base <= 0.0:
		return 0.0
	var power_stat := Stats.ATTACK_POWER if school == SCHOOL_PHYSICAL or school == &"" else Stats.SPELL_POWER
	var flat := base + maxf(0.0, stats.get_raw(power_stat)) * PROC_POWER_SCALE
	return maxf(MIN_DAMAGE, flat * damage_mult_for(stats, school))


## Chance (0..1) that a PPM proc fires on one hit of a weapon with [param weapon_cooldown]
## seconds between attacks: ppm x cooldown / 60 (GDD 5.7).
static func ppm_chance(ppm: float, weapon_cooldown: float) -> float:
	return clampf(ppm * maxf(0.0, weapon_cooldown) / 60.0, 0.0, 1.0)


## Extra projectiles fired in a fan (whole part of the stat).
static func extra_projectiles(stats: StatBlock) -> int:
	return maxi(0, floori(stats.get_raw(Stats.EXTRA_PROJECTILE) + 0.000001))


## Extra pierce of projectiles (whole part of the stat).
static func extra_pierce(stats: StatBlock) -> int:
	return maxi(0, floori(stats.get_raw(Stats.PIERCE) + 0.000001))


## AoE radius multiplier from Area Size % (weapon explosions and proc AoEs).
static func area_mult(stats: StatBlock) -> float:
	return maxf(0.1, 1.0 + stats.get_raw(Stats.AREA_SIZE) / 100.0)


## Fraction (0..BLOCK_ABSORB_CAP) of a blocked hit that is absorbed: half, + Block Value %.
static func block_absorb(block_value_pct: float) -> float:
	return clampf(BASE_BLOCK_ABSORB * (1.0 + block_value_pct / 100.0), 0.0, BLOCK_ABSORB_CAP)


## Exact XP for picking up [param amount] with [param xp_gain_pct] percent XP Gain.
static func xp_with_gain(amount: float, xp_gain_pct: float) -> float:
	return maxf(0.0, amount * (1.0 + xp_gain_pct / 100.0))


## Seconds between attacks, after Haste and the weapon's own attack speed bonus (Epic +10%,
## GDD 4.1 – multiplies with Haste; the Attack / Spell Power normalisation and PPM chances keep
## the base cooldown, so the bonus is a real attack speed gain like Haste).
static func weapon_cooldown(weapon: WeaponData, stats: StatBlock) -> float:
	return maxf(0.08, weapon.cooldown / maxf(0.2, stats.attack_speed_mult() * weapon.attack_speed_mult()))


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


## Extra Attack: % chance that a weapon attack strikes again at once.
static func roll_extra_attack(stats: StatBlock, rng: RandomNumberGenerator) -> bool:
	return rng.randf() * 100.0 < stats.get_raw(Stats.EXTRA_ATTACK)


## Parry: % chance (capped at PARRY_CAP) to negate a melee hit.
static func roll_parry(stats: StatBlock, rng: RandomNumberGenerator) -> bool:
	return rng.randf() * 100.0 < minf(stats.get_raw(Stats.PARRY), PARRY_CAP)


## Life on Kill: % chance to heal 1 HP per kill.
static func roll_life_on_kill(stats: StatBlock, rng: RandomNumberGenerator) -> bool:
	return rng.randf() * 100.0 < stats.get_raw(Stats.LIFE_ON_KILL)


## Exact (fractional) gold a player with [param stats] gains for picking up [param amount].
## Not rounded: RunState.add_gold_for keeps the fraction per player slot, so small Gold Find
## values add up over many pickups instead of being rounded away on every 1-gold coin.
static func gold_with_find(amount: int, stats: StatBlock) -> float:
	return gold_with_find_pct(amount, stats.get_stat(Stats.GOLD_FIND))


## [param amount] gold with [param gold_find_pct] percent Gold Find (never negative).
static func gold_with_find_pct(amount: float, gold_find_pct: float) -> float:
	return maxf(0.0, amount * (1.0 + gold_find_pct / 100.0))
