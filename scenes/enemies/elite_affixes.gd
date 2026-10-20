class_name EliteAffixes
extends RefCounted
## Elites (GDD 8, M5, architecture §2.5): how many per wave, when they spawn and their affix.
## WaveDirector schedules them at wave start; [method Enemy.make_elite] applies the affix (the
## affix numbers below are read by Enemy).
##
## - Count: from FIRST_WAVE, (0.4 + 0.06 (w − 5)) × (1 + 0.35 (players − 1)) × [member rate_mult]
##   expected elites per wave; the fraction is the chance of one more (solo: w5 0.4, w15 1.0,
##   w25 1.6; 4 players ×2.05). Wave 20 (RunState.ELITE_WAVES) doubles it
##   ([constant ELITE_WAVE_COUNT_MULT]) and gives every other enemy a lite affix; the boss waves
##   10 / 25 have no elites (the boss is the elite).
## - Times: each elite gets one random time in [WINDOW_START, WINDOW_END] × the wave duration;
##   the first enemy of the next group that spawns after it becomes the elite.
## - Affix (one, uniform): Shielding, Enraged, Frenzied, Vampiric.
## - Elite wave 20 (M6, GDD 8): [method Enemy.make_elite] with lite = true for every enemy that is
##   not a real elite: the affix with HP ×[constant LITE_HP_MULT], normal size and rewards.
##
## RunState.rng draw points (all deterministic for a seed):
## - [method roll_count]: one draw when the expected count is > 0, none below FIRST_WAVE (or
##   with rate_mult 0), so waves 1–4 draw exactly what they drew before M5.
## - [method schedule]: roll_count, then one draw per elite (its time), in that order –
##   inside WaveDirector.start_wave, after the eligible list and before the first group pick.
## - [method roll_affix]: one draw per elite, in WaveDirector._spawn_group right after the
##   enemy is created (group order).

const SHIELDING := &"shielding"
const ENRAGED := &"enraged"
const FRENZIED := &"frenzied"
const VAMPIRIC := &"vampiric"
const ALL: Array[StringName] = [SHIELDING, ENRAGED, FRENZIED, VAMPIRIC]
const NAMES: Dictionary[StringName, String] = {
	SHIELDING: "Shielding", ENRAGED: "Enraged", FRENZIED: "Frenzied", VAMPIRIC: "Vampiric",
}
## Accent colour per affix (the nameplate's gem; the name itself is silver).
const COLORS: Dictionary[StringName, Color] = {
	SHIELDING: Color(0.45, 0.75, 1.0),
	ENRAGED: Color(1.0, 0.3, 0.2),
	FRENZIED: Color(1.0, 0.78, 0.2),
	VAMPIRIC: Color(0.78, 0.2, 0.55),
}
## Elites appear from this wave on.
const FIRST_WAVE := 5
const HP_MULT := 3.0
## Elite wave 20: the HP factor of the lite affix every ordinary enemy gets, and the factor on
## the expected number of real elites.
const LITE_HP_MULT := 1.5
const ELITE_WAVE_COUNT_MULT := 2.0
## Gold an elite drops instead of EnemyData.gold (GDD 10).
const GOLD := 10
const XP_MULT := 5
## Model and body (collision radius) size of an elite.
const MODEL_SCALE := 1.3

## Expected elites per wave: (BASE_COUNT + COUNT_PER_WAVE (w − FIRST_WAVE)) × (1 + COUNT_PER_PLAYER (n − 1)).
const BASE_COUNT := 0.4
const COUNT_PER_WAVE := 0.06
const COUNT_PER_PLAYER := 0.35
## Spawn window, as fractions of the wave duration.
const WINDOW_START := 0.15
const WINDOW_END := 0.7

## Shielding: absorb shield of this fraction of max HP at spawn, and again SHIELD_REGROW
## seconds after the previous one broke.
const SHIELD_PCT := 0.3
const SHIELD_REGROW := 8.0
## Enraged: once, at or below this HP fraction – damage ×ENRAGE_DAMAGE_MULT, speed
## ×ENRAGE_SPEED_MULT, immune to slows (stuns, freezes and fear still work).
const ENRAGE_HP_RATIO := 0.5
const ENRAGE_DAMAGE_MULT := 1.5
const ENRAGE_SPEED_MULT := 1.3
## Frenzied: speed ×FRENZY_SPEED_MULT; contact, lunge and throw cooldowns ×FRENZY_COOLDOWN_MULT.
const FRENZY_SPEED_MULT := 1.25
const FRENZY_COOLDOWN_MULT := 0.6
## Vampiric: every hit it lands on a hero heals it for this fraction of its max HP
## (Enemy.heal – healing reduction such as Mortal Wound applies).
const VAMPIRIC_HEAL_PCT := 0.1

## --elite-mult: multiplies the expected count. RunState.start_run resets it to 1.0, then Main
## applies the launch option.
static var rate_mult := 1.0


## Expected elites in wave [param wave] for [param players] heroes (fraction = chance of one
## more): (0.4 + 0.06 (w − 5)) × (1 + 0.35 (n − 1)) × rate_mult (× 2 on the elite wave), 0 below
## FIRST_WAVE.
static func expected_count(wave: int, players: int) -> float:
	if wave < FIRST_WAVE or rate_mult <= 0.0:
		return 0.0
	var per_wave := BASE_COUNT + COUNT_PER_WAVE * float(wave - FIRST_WAVE)
	var party := 1.0 + COUNT_PER_PLAYER * float(maxi(1, players) - 1)
	var wave_mult := ELITE_WAVE_COUNT_MULT if RunState.is_elite_wave(wave) else 1.0
	return maxf(0.0, per_wave * party * wave_mult * rate_mult * Pressure.elite_mult())


## Whole elites of the wave: the whole part of [method expected_count] plus one more with the
## fraction as chance (one rng draw; no draw when nothing can spawn).
static func roll_count(wave: int, players: int, rng: RandomNumberGenerator) -> int:
	var expected := expected_count(wave, players)
	if expected <= 0.0:
		return 0
	# The epsilon keeps 1.0 computed as 0.99999… a whole elite.
	var whole := floori(expected + 0.000001)
	var fraction := maxf(0.0, expected - float(whole))
	return whole + (1 if rng.randf() < fraction else 0)


## Sorted spawn times (seconds into the wave, within WINDOW_START–WINDOW_END of
## [param duration]): [method roll_count], then one draw per elite.
static func schedule(wave: int, duration: float, players: int, rng: RandomNumberGenerator) -> Array[float]:
	var out: Array[float] = []
	var count := roll_count(wave, players, rng)
	var lo := WINDOW_START * maxf(0.0, duration)
	var hi := WINDOW_END * maxf(0.0, duration)
	for _i in count:
		out.append(rng.randf_range(lo, hi))
	out.sort()
	return out


## A random affix of ALL (one draw).
static func roll_affix(rng: RandomNumberGenerator) -> StringName:
	return ALL[rng.randi_range(0, ALL.size() - 1)]


## "Shielding" for &"shielding" ("" for an unknown affix).
static func affix_name(affix: StringName) -> String:
	return String(NAMES.get(affix, ""))


## The nameplate text: "<Affix> <enemy name>".
static func display_name(affix: StringName, enemy_name: String) -> String:
	var a := affix_name(affix)
	if a == "":
		return enemy_name
	return "%s %s" % [a, enemy_name] if enemy_name != "" else a


## Accent colour of [param affix] (silver for an unknown one).
static func color_of(affix: StringName) -> Color:
	var c: Color = COLORS.get(affix, Color(0.82, 0.85, 0.9))
	return c
