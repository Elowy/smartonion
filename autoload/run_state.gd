extends Node
## Autoload "RunState": state of the current run shared by the whole team (GDD 1, 9, 10).
##
## - One shared wallet (gold) – anyone can spend it.
## - One shared XP bar – the whole team levels up together.
## - Wave counter and the wave / co-op scaling formulas.

signal run_started
signal run_ended(victory: bool)
signal wave_changed(wave: int)
signal gold_changed(gold: int, delta: int)
signal xp_changed(xp: int, needed: int)
signal leveled_up(level: int)
## Team loot changed (an item bag was picked up / banked, or the loot roll consumed items).
signal team_loot_changed

const TOTAL_WAVES := 25
const BOSS_WAVES: Array[int] = [10, 25]
const ELITE_WAVES: Array[int] = [20]
## The team starts at level 1 (WoW style); the XP curve counts level-ups from here.
const START_LEVEL := 1
## Talent points come from this level on (GDD 7.1: one per level from level 10).
const TALENT_START_LEVEL := 10
## Enemy damage multiplier by party size (index = players - 1; [method coop_damage_mult],
## GDD 9). Smaller parties take softer hits: the fewer heroes, the fewer can revive a downed
## one (alone, the first down ends the run) and the more enemies each faces (the +60% count
## per extra player is less than one more share). About x1.3 per extra player; even a full
## party stays below the plain EnemyData curve.
const COOP_DAMAGE_MULTS: Array[float] = [0.35, 0.45, 0.6, 0.8]

var active := false
var victory := false
var wave := 0
var gold := 0
var xp := 0
var level := START_LEVEL
## Level-ups gained during the current wave, resolved on the between-wave screen.
var pending_level_ups := 0
var player_count := 1
var difficulty: StringName = &"normal"
var rng := RandomNumberGenerator.new()

# Run statistics (end screen).
var kills := 0
var gold_earned := 0
var kills_by_player: Dictionary[int, int] = {}
var damage_by_player: Dictionary[int, float] = {}

# Items (M2): loot collected this wave waits here for the Need / Greed / Pass roll (GDD 10.1);
# the shared shop persists through the run (locked offers carry over).
var team_loot: Array[ItemInstance] = []
## Item drops from normal enemies this wave (capped at 1 + players, GDD 10.1).
var loot_drops_this_wave := 0
var shop := Shop.new()
## Statistics for the end screen / meta-progression: items won by Need per slot, Greed gold.
var need_wins_by_player: Dictionary[int, int] = {}
var greed_gold := 0

## Fraction of a gold coin each player slot has earned through Gold Find but not yet
## received (see add_gold_for). Keyed by slot index (-1 = no slot).
var _gold_remainder: Dictionary[int, float] = {}


func start_run(p_player_count: int, seed_value: int = -1) -> void:
	active = true
	victory = false
	wave = 0
	gold = 0
	xp = 0
	level = START_LEVEL
	pending_level_ups = 0
	player_count = clampi(p_player_count, 1, 4)
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	kills = 0
	gold_earned = 0
	kills_by_player.clear()
	damage_by_player.clear()
	_gold_remainder.clear()
	team_loot.clear()
	loot_drops_this_wave = 0
	shop = Shop.new()
	need_wins_by_player.clear()
	greed_gold = 0
	run_started.emit()
	gold_changed.emit(gold, 0)
	xp_changed.emit(xp, xp_to_next_level())


func end_run(p_victory: bool) -> void:
	if not active:
		return
	active = false
	victory = p_victory
	run_ended.emit(p_victory)


func set_wave(value: int) -> void:
	wave = value
	loot_drops_this_wave = 0
	wave_changed.emit(wave)


## Adds a looted item to the team loot (waits for the Need / Greed / Pass roll).
func add_team_loot(item: ItemInstance) -> void:
	if item == null:
		return
	team_loot.append(item)
	team_loot_changed.emit()


## Takes all collected loot out (the loot roll screen consumes it).
func take_team_loot() -> Array[ItemInstance]:
	var out := team_loot.duplicate()
	team_loot.clear()
	team_loot_changed.emit()
	return out


func is_last_wave() -> bool:
	return wave >= TOTAL_WAVES


# --- Shared wallet -----------------------------------------------------------

func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold += amount
	if amount > 0:
		gold_earned += amount
	gold_changed.emit(gold, amount)


## Gold picked up by player slot [param slot_index] with [param gold_find_pct] percent Gold
## Find: the exact value (CombatMath.gold_with_find_pct) plus the slot's stored fraction;
## the whole part goes to the shared wallet, the rest is kept for the slot's next pickup.
## Returns the whole gold added.
func add_gold_for(slot_index: int, amount: int, gold_find_pct: float) -> int:
	if amount <= 0:
		return 0
	var carried: float = _gold_remainder.get(slot_index, 0.0)
	var exact := CombatMath.gold_with_find_pct(amount, gold_find_pct) + carried
	# The epsilon keeps float sums like 10 x 0.1 from landing just below a whole coin.
	var whole := floori(exact + 0.000001)
	_gold_remainder[slot_index] = maxf(0.0, exact - whole)
	add_gold(whole)
	return whole


## Gold Find fraction player slot [param slot_index] carries towards its next coin (0..1).
func gold_remainder(slot_index: int) -> float:
	return _gold_remainder.get(slot_index, 0.0)


func can_afford(amount: int) -> bool:
	return gold >= amount


## Spends from the shared wallet. Returns false (and changes nothing) if too poor.
func try_spend(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold, -amount)
	return true


# --- Shared XP ---------------------------------------------------------------

## XP needed to go from [member level] to level + 1 (see [method xp_needed_for_level]).
func xp_to_next_level() -> int:
	return xp_needed_for_level(level + 1, player_count)


## XP needed to reach [param target_level]: (n + 3)^2 for the n-th level-up of the run
## (GDD 6.1, Brotato formula; n = target_level - START_LEVEL, so level 1 -> 2 needs
## (1 + 3)^2), scaled by the player count.
static func xp_needed_for_level(target_level: int, players: int) -> int:
	var n := maxi(1, target_level - START_LEVEL)
	var base := pow(n + 3, 2)
	return int(ceil(base * (1.0 + 0.6 * (players - 1))))


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	var needed := xp_to_next_level()
	while xp >= needed:
		xp -= needed
		level += 1
		pending_level_ups += 1
		leveled_up.emit(level)
		needed = xp_to_next_level()
	xp_changed.emit(xp, needed)


## Talent points become available from level 10 (GDD 7.1): one at 10, one per level after.
## Used from M5.
func talent_points_earned() -> int:
	return maxi(0, level - TALENT_START_LEVEL + 1)


# --- Statistics --------------------------------------------------------------

func record_kill(player_index: int) -> void:
	kills += 1
	if player_index >= 0:
		kills_by_player[player_index] = kills_by_player.get(player_index, 0) + 1


func record_damage(player_index: int, amount: float) -> void:
	if player_index >= 0:
		damage_by_player[player_index] = damage_by_player.get(player_index, 0.0) + amount


# --- Wave / co-op scaling (GDD 9) -------------------------------------------

## Seconds of wave [param w] (GDD 1): waves 1-10 last 20 + 5 * (w - 1) s, at most 60 s
## (waves 9 and 10 are 60 s); every wave above 10 adds 10 s (11 = 70 s ... 25 = 210 s).
static func wave_duration(w: int) -> float:
	if w > 10:
		return 60.0 + 10.0 * (w - 10)
	return minf(60.0, 20.0 + 5.0 * (w - 1))


## Spawn budget multiplier for additional players (+60% per extra player).
func coop_count_mult() -> float:
	return 1.0 + 0.6 * (player_count - 1)


## Enemy HP multiplier for additional players (+20% per extra player).
func coop_hp_mult() -> float:
	return 1.0 + 0.2 * (player_count - 1)


## Enemy contact / projectile damage multiplier for the party size (GDD 9), see
## [constant COOP_DAMAGE_MULTS].
func coop_damage_mult() -> float:
	return COOP_DAMAGE_MULTS[clampi(player_count, 1, COOP_DAMAGE_MULTS.size()) - 1]


static func is_boss_wave(w: int) -> bool:
	return w in BOSS_WAVES


static func is_elite_wave(w: int) -> bool:
	return w in ELITE_WAVES
