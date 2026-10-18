class_name BossData
extends EnemyData
## A boss definition (GDD chapter 8 "Bossok", M6). Instances live in res://data/bosses/ (loaded
## by Db into Db.bosses, not into Db.enemies: the wave director never picks a boss from the pool).
## A BossData is an EnemyData whose [member EnemyData.is_boss] is true by default, so everything
## that reads an EnemyData (Enemy.setup, hp_at_wave, the model) works unchanged:
## [member EnemyData.max_hp] is the base HP, [member EnemyData.contact_damage] the base contact
## damage (the abilities' "N x contact" multiples).
##
## - [member boss_wave]: the wave it appears in ([method for_wave]); RunState.BOSS_WAVES lists them.
##   0 = a boss of no wave (the Dungeon Warden, M6b: the Dungeon spawns it, see [Dungeon]).
## - Phase 2 at [member phase_hp_ratio] of its HP; [member phase_cooldown_mult] shortens every
##   ability interval that has no own phase-2 value (BossAbility.interval_at).
## - [member abilities]: the scripted attacks ([BossAbility]).
## - Enrage: after [member enrage_time] seconds damage x [member enrage_damage_mult] and speed
##   x [member enrage_speed_mult]; every further [member enrage_step_time] seconds the damage
##   multiplier grows by [member enrage_step_damage] ([method enrage_level_at],
##   [method enrage_damage_at]).
## - Reward: [member reward_gold] (the items are the generator's BOSS source, see Boss).
##   Vor'thalax's death on wave 25 ends the wave, i.e. the run (Main: the last wave won).
## - Crowd control: the data only sets knockback_resist 1 (immune); [Boss] itself enforces the
##   rest in code (stun lasts x0.25 [constant Boss.STUN_SHARE], slows land halved, taunt and fear
##   are ignored). Leave stun_resist at 0: Enemy.apply_stun would apply it on top of the x0.25.

## The endless mode's boss rotation (M6b MODES): the bosses of wave 30, 35, 40 ... in turn
## ([method endless_boss]) – Morvain, Vor'thalax, Morvain ... – with the usual HP / damage growth of
## the wave they appear in.
const ENDLESS_ROTATION: Array[StringName] = [&"lich_commander_morvain", &"vorthalax"]

## --boss-hp=X (LaunchOptions.boss_hp): multiplies every boss's max HP. 1 = off. Reset to 1 by
## RunState.start_run and re-applied by Main.start_run; [method max_hp_for] reads it.
static var hp_mult := 1.0

@export_group("Boss")
## The wave this boss appears in.
@export var boss_wave := 10
## HUD banner when it arrives (empty = display_name).
@export var intro := ""
## Phase 2 starts at or below this share of the max HP.
@export var phase_hp_ratio := 0.5
## Factor on every ability interval in phase 2 (an ability's own interval_p2 wins).
@export var phase_cooldown_mult := 1.0
@export var abilities: Array[BossAbility] = []
## Extra max HP per additional player (GDD 9: x(1 + 0.75 (n - 1)), the boss's own co-op factor
## instead of the normal +20% per player).
@export var coop_hp_per_player := 0.75

@export_group("Enrage")
## Seconds after its arrival until it enrages (GDD 8: 90).
@export var enrage_time := 90.0
@export var enrage_damage_mult := 1.5
@export var enrage_speed_mult := 1.3
## Every further this many seconds the damage multiplier grows by enrage_step_damage.
@export var enrage_step_time := 30.0
@export var enrage_step_damage := 0.25

@export_group("Rewards")
@export var reward_gold := 50


func _init() -> void:
	is_boss = true


## The boss of wave [param wave] from Db.bosses (the lowest id when two share a wave; null when
## there is none – the wave then runs as a normal one). Past the normal run, the endless mode's boss
## waves (RunState.is_endless_boss_wave: 30, 35, 40 ...) take [method endless_boss].
static func for_wave(wave: int) -> BossData:
	if wave <= 0:
		return null
	var best: BossData = null
	for id in Db.bosses:
		var b := Db.bosses[id] as BossData
		if b == null or b.boss_wave != wave:
			continue
		if best == null or String(b.id) < String(best.id):
			best = b
	if best == null and RunState.is_endless_boss_wave(wave):
		return endless_boss(wave)
	return best


## The boss of the endless boss wave [param wave] (30, 35, 40 ...): [constant ENDLESS_ROTATION] in turn,
## Morvain on 30, 40, 50 ..., Vor'thalax on 35, 45, 55 ... (null for any other wave).
static func endless_boss(wave: int) -> BossData:
	if not RunState.is_endless_boss_wave(wave):
		return null
	var turn := floori(float(wave - RunState.ENDLESS_BOSS_FIRST_WAVE) / float(RunState.ENDLESS_BOSS_EVERY))
	return Db.get_boss(ENDLESS_ROTATION[turn % ENDLESS_ROTATION.size()])


## Max HP at [param wave] for [param players] heroes: base x the wave's usual HP growth x
## (1 + [member coop_hp_per_player] (players - 1)) x [member hp_mult] (--boss-hp), at least 1.
func max_hp_for(wave: int, players: int) -> float:
	var party := 1.0 + coop_hp_per_player * float(maxi(1, players) - 1)
	return maxf(1.0, hp_at_wave(wave) * party * hp_mult)


## Enrage level after [param age] seconds: 0 before [member enrage_time], 1 from it on, +1 for
## every full [member enrage_step_time] after that.
func enrage_level_at(age: float) -> int:
	if age < enrage_time:
		return 0
	return 1 + floori((age - enrage_time) / maxf(0.001, enrage_step_time))


## Damage multiplier at enrage [param level] (1 before the enrage, then
## [member enrage_damage_mult] + [member enrage_step_damage] per further level).
func enrage_damage_at(level: int) -> float:
	if level <= 0:
		return 1.0
	return enrage_damage_mult + enrage_step_damage * float(level - 1)


## The banner text of its arrival.
func intro_text() -> String:
	return intro if intro != "" else display_name
