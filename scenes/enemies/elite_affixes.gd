class_name EliteAffixes
extends RefCounted
## Elites (GDD 8, M5, architecture §2.5): how many per wave, when they spawn and their affix.
## WaveDirector schedules them at wave start; Enemy.make_elite applies the affix.
##
## P0 stub: the constants and [member rate_mult] exist; nothing spawns – expected_count /
## roll_count return 0, schedule returns [] and no roll draws from the rng. ELITES implements it.

const SHIELDING := &"shielding"
const ENRAGED := &"enraged"
const FRENZIED := &"frenzied"
const VAMPIRIC := &"vampiric"
const ALL: Array[StringName] = [SHIELDING, ENRAGED, FRENZIED, VAMPIRIC]
const NAMES := {SHIELDING: "Shielding", ENRAGED: "Enraged", FRENZIED: "Frenzied", VAMPIRIC: "Vampiric"}
## Elites appear from this wave on.
const FIRST_WAVE := 5
const HP_MULT := 3.0
## Gold an elite drops instead of EnemyData.gold (GDD 10).
const GOLD := 10
const XP_MULT := 5
const MODEL_SCALE := 1.3

## --elite-mult: multiplies the expected count. RunState.start_run resets it to 1.0, then Main
## applies the launch option.
static var rate_mult := 1.0


## Expected elites in wave [param _wave] for [param _players] heroes (fraction = chance of one
## more): (0.4 + 0.06 (w − 5)) × (1 + 0.35 (n − 1)) × rate_mult, 0 below FIRST_WAVE.
static func expected_count(_wave: int, _players: int) -> float:
	return 0.0


## Whole elites of the wave: floor + the chance of one more (one rng draw).
static func roll_count(_wave: int, _players: int, _rng: RandomNumberGenerator) -> int:
	return 0


## Sorted spawn times (seconds into the wave, within 15–70% of [param _duration]).
static func schedule(_wave: int, _duration: float, _players: int, _rng: RandomNumberGenerator) -> Array[float]:
	var out: Array[float] = []
	return out


## A random affix of ALL (one draw).
static func roll_affix(_rng: RandomNumberGenerator) -> StringName:
	return &""
