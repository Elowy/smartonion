class_name BossAbility
extends Resource
## One scripted ability of a boss (GDD 8 "Bossok", M6). A [BossData] lists them in
## [member BossData.abilities]; [Boss] runs one cooldown timer per entry and casts it through
## its [member kind]. Damage numbers are multiples of the boss's contact damage at the wave
## (already scaled by the wave and the party size), enrage included.
##
## Which fields a kind reads:
##   FROST_CIRCLES – interval, telegraph, radius, damage_mult, slow_pct, slow_time: one ice
##                   circle under every living hero.
##   FROST_BREATH  – interval, telegraph, angle, range, damage_mult: a cone towards the nearest
##                   hero.
##   SUMMON        – interval, count, summon_id (an EnemyData id of Db.enemies): adds around
##                   the boss, through the WaveDirector.
##   FIRE_FIELDS   – interval, count, telegraph, radius, duration, tick_interval, damage_mult
##                   (per tick): burning patches on the heroes' positions.
##   METEOR        – interval, telegraph, radius, damage_mult (the TOTAL, shared among the
##                   heroes inside), fallback_damage_mult (everybody when nobody is inside).
## Phase 2 ([member BossData.phase_hp_ratio]): [method interval_at] / [method count_at].

enum Kind { FROST_CIRCLES, FROST_BREATH, SUMMON, FIRE_FIELDS, METEOR }

@export var id: StringName
@export var display_name: String
@export var kind: Kind = Kind.FROST_CIRCLES
## Seconds between two casts in phase 1.
@export var interval := 8.0
## Phase 2 interval (0 = [member interval] x BossData.phase_cooldown_mult).
@export var interval_p2 := 0.0
## Seconds until the first cast (0 = [member interval] x FIRST_CAST_SHARE).
@export var first_delay := 0.0
## Warning time (s) between the marker appearing and the strike.
@export var telegraph := 1.0
## Circle radius (m).
@export var radius := 2.0
## Cone angle (degrees) and length (m).
@export var angle := 60.0
@export var range := 7.0
## Damage as a multiple of the boss's contact damage (per tick for a persistent field, the
## shared total for the meteor).
@export var damage_mult := 1.0
## METEOR only: the multiple every living hero takes when nobody stands in the circle.
@export var fallback_damage_mult := 0.0
## Circles / patches / adds per cast in phase 1 and in phase 2 (0 = the same).
@export var count := 1
@export var count_p2 := 0
## Seconds a persistent hazard (fire field) burns after its telegraph.
@export var duration := 0.0
## Seconds between the damage ticks of a persistent hazard.
@export var tick_interval := 1.0
## Slow on the heroes hit (percent, seconds).
@export var slow_pct := 0.0
@export var slow_time := 0.0
## SUMMON: the EnemyData id (Db.enemies) of the adds.
@export var summon_id: StringName

## The first cast comes after this share of the interval when first_delay is 0 (the boss does
## not open with all its abilities at once).
const FIRST_CAST_SHARE := 0.6


## Seconds between two casts in [param phase] (1 or 2); [param phase_mult] =
## BossData.phase_cooldown_mult applies in phase 2 when no explicit interval_p2 is set.
func interval_at(phase: int, phase_mult: float = 1.0) -> float:
	if phase >= 2:
		return interval_p2 if interval_p2 > 0.0 else interval * phase_mult
	return interval


## Circles / patches / adds of a cast in [param phase].
func count_at(phase: int) -> int:
	return count_p2 if phase >= 2 and count_p2 > 0 else count


## Seconds until the first cast.
func first_cast_delay() -> float:
	return first_delay if first_delay > 0.0 else interval * FIRST_CAST_SHARE
