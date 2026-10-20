extends Node
## Autoload "RunState": state of the current run shared by the whole team (GDD 1, 9, 10).
##
## - One shared wallet (gold) – anyone can spend it.
## - One shared XP bar – the whole team levels up together.
## - Wave counter and the wave / co-op scaling formulas.
## - M5: the spend log of the shared wallet (try_spend_for: who spent what this round), the
##   players' "wants" (Trainer pings), elite / goblin / forge / talent-reset counters, the
##   special-kill record and the run serial that per-run statics compare against.
## - M6 foundation: Arcane Dust (the second team currency, [method add_dust] /
##   [method try_spend_dust_for]), the damage-meter record (per-slot healing, absorbed, damage
##   taken, revives, downs + [member run_time]), boss / artifact / consumable / enchant counters.
## - M6b foundation: the run's [member mode] (normal / endless) and [member hardcore] flag, its
##   [member environment], [method total_waves] (the run length every wave-count display and the
##   victory check read; 0 = endless), the run seed with the sub-RNGs derived from it (environment,
##   events, shrines, dungeon), the event / shrine / dungeon counters and the debug overrides.

signal run_started
signal run_ended(victory: bool)
signal wave_changed(wave: int)
signal gold_changed(gold: int, delta: int)
signal xp_changed(xp: int, needed: int)
signal leveled_up(level: int)
## Team loot changed (an item bag was picked up / banked, or the loot roll consumed items).
signal team_loot_changed
## The wallet paid [param entry] ({"slot", "kind", "label", "amount", "wave"}, see try_spend_for).
signal spent(entry: Dictionary)
## [member wants] changed (toggle_want / clear_want / begin_spend_round).
signal wants_changed
## An elite, the Loot Goblin or a boss died ([param kind] &"elite" / &"goblin" / &"boss");
## [param killer_index] = the killer's slot index (-1 = none).
signal special_killed(kind: StringName, killer_index: int)
## Arcane Dust (the team's second currency) changed by [param delta] (add_dust,
## try_spend_dust_for; start_run emits it with delta 0).
signal dust_changed(dust: int, delta: int)
## The running shrine effects changed (a shrine was accepted, a wave ended, a run started): the HUD icons.
signal shrines_changed
## An Artifact dropped (LootDrops.roll_artifact hit): the new [param item] and the id of the kill's
## source (ItemGenerator.SOURCE_IDS: &"boss", &"goblin", &"elite", &"loot"). Main logs it.
signal artifact_dropped(item: ItemInstance, source: StringName)

## The normal mode's length (what [method total_waves] returns in it). Gameplay and UI code reads
## [method total_waves], never this constant (the endless mode has no last wave).
const TOTAL_WAVES := 25
## [method total_waves] of the endless mode: no last wave.
const ENDLESS_WAVES := 0
## Run modes ([member mode]).
const MODE_NORMAL: StringName = &"normal"
const MODE_ENDLESS: StringName = &"endless"
const MODES: Array[StringName] = [MODE_NORMAL, MODE_ENDLESS]
## The environment a run gets when nothing else is chosen (data/environments/forest_ruin.tres).
const DEFAULT_ENVIRONMENT: StringName = &"forest_ruin"
## Salts of the sub-RNGs ([method sub_rng]): each M6b feature that rolls on its own draws from a
## generator seeded from [member run_seed] and its salt, so it never moves [member rng].
const SALT_ENVIRONMENT := 0x454E56
const SALT_EVENTS := 0x455654
const SALT_SHRINES := 0x534852
const SALT_DUNGEON := 0x44554E
## The normal run's boss waves and elite wave (the endless mode adds its own beyond wave 25, see the
## ENDLESS_* constants and [method is_boss_wave] / [method is_elite_wave]).
const BOSS_WAVES: Array[int] = [10, 25]
const ELITE_WAVES: Array[int] = [20]
## Endless waves (M6b MODES): past the 25th wave every 5th wave from the 30th is a boss wave (the bosses
## alternate, BossData.endless_boss) and the elite-wave rule of wave 20 comes back every 10th wave from
## the 33rd (33, 43, 53 ...). The waves are also capped at [constant MAX_WAVE_DURATION] seconds.
const ENDLESS_BOSS_FIRST_WAVE := 30
const ENDLESS_BOSS_EVERY := 5
const ENDLESS_ELITE_FIRST_WAVE := 33
const ENDLESS_ELITE_EVERY := 10
## The longest wave (s): wave 25's length; endless waves above it stay this long.
const MAX_WAVE_DURATION := 210.0
## The team starts at level 1 (WoW style); the XP curve counts level-ups from here.
const START_LEVEL := 1
## Talent points come from this level on (GDD 7.1: one per level from level 10).
const TALENT_START_LEVEL := 10
## Enemy damage multiplier by party size (index = players - 1; [method coop_damage_mult],
## GDD 9). Smaller parties take softer hits: the fewer heroes, the fewer can revive a downed
## one (alone, the first down ends the run) and the more enemies each faces (the +60% count
## per extra player is less than one more share). About x1.3 per extra player. Final balance: the
## full party went from 0.95 to 1.05 after the Flesh Golem was softened (at 0.95 the bots' first downs moved
## from wave ~11 to wave ~20 and six of six full parties cleared; at 1.15 two of six cleared, the early waves and
## the first dungeon already cost downs). The trio was only interpolated (0.75, then 0.8) until it was measured:
## at 0.8 twelve of twelve trios cleared with barely a down (5.6 downs per run on waves 20-25 against 26 for the
## full party, 0.7 for a duo), so it is 0.9.
const COOP_DAMAGE_MULTS: Array[float] = [0.45, 0.6, 0.9, 1.05]

var active := false
var victory := false
var wave := 0
var gold := 0
var xp := 0
var level := START_LEVEL
## Level-ups gained during the current wave, resolved on the between-wave screen.
var pending_level_ups := 0
var player_count := 1
var rng := RandomNumberGenerator.new()

# M6b: what kind of run this is. Set by start_run (parameters), read everywhere through the helpers.
## The run mode: MODE_NORMAL (25 waves, the final boss ends it) or MODE_ENDLESS (no last wave).
var mode: StringName = MODE_NORMAL
## Hardcore: no Spirit Healer, only a teammate can revive a downed hero (MODES package). Solo
## hardcore is the normal solo run (the first down ends it).
var hardcore := false
## The id of the arena's environment (Db.environments; ENV package).
var environment: StringName = DEFAULT_ENVIRONMENT
## The seed this run's [member rng] started from (the given one, else the random one it drew).
var run_seed := 0
## Own generators of the M6b features, seeded once per run from [member run_seed] ([method sub_rng]):
## the environment roll, the mid-wave events, the shrine roll at a break, the dungeon encounters. Their
## draws never touch [member rng], so a seeded run without the feature plays as it did before.
var environment_rng := RandomNumberGenerator.new()
var event_rng := RandomNumberGenerator.new()
var shrine_rng := RandomNumberGenerator.new()
var dungeon_rng := RandomNumberGenerator.new()

# M6b debug overrides (reset by start_run, applied by Main from the launch options).
## --shrine-chance: the chance of a shrine at every break (0..1; < 0 = the normal chance).
var shrine_chance_override := -1.0
## --event: the mid-wave event every eligible wave gets (&"" = rolled; EventSpawner.EVENT_IDS).
var event_override: StringName = &""
## --dungeon: the dungeon portal opens after the next wave (DUNGEON package clears it when it does).
var dungeon_forced := false

# Run statistics (end screen).
var kills := 0
var gold_earned := 0
## Free stall rerolls left this run (M9 LEVELS: Class Level 11 gives each hero one; Meta.apply_run_start sets them,
## Shop.try_reroll uses them up before it takes gold). 0 in every automated run.
var free_rerolls := 0
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

# M5: the shared purse (GDD 10) and the new run statistics.
## Every wallet spend of this round (shop, auto-forge, stall reroll, Trainer, level-up reroll,
## talent reset), oldest first: {"slot": int (-1 = the team), "kind": StringName,
## "label": String, "amount": int, "wave": int}. Cleared by [method begin_spend_round].
var spend_log: Array[Dictionary] = []
## Gold spent through [method try_spend_for] this run.
var gold_spent := 0
## What players asked the team to buy for them this round (Trainer pings):
## {"slot": int, "key": String ("trainer:<ability_id>"), "label": String, "price": int}.
var wants: Array[Dictionary] = []
var elites_spawned := 0
var elites_killed := 0
var goblins_spawned := 0
var goblins_killed := 0
var goblins_escaped := 0
var weapons_forged := 0
## Talent resets bought by every hero this run.
var talent_resets := 0
## Counts the runs started; per-run statics of kits (e.g. MageFrozen) store it and clear
## themselves when it changed.
var run_serial := 0

# M6: Arcane Dust, the second shared currency (GDD 5.7). Earned by disenchanting items, spent
# at the Enchanter. Gold's spend log and Dust's are separate: the purse board lists gold.
## The team's Arcane Dust.
var arcane_dust := 0
## Dust added through [method add_dust] this run.
var dust_earned := 0
## Dust spent through [method try_spend_dust_for] this run.
var dust_spent := 0
## Every Dust spend of this round, oldest first (same entry shape as [member spend_log]);
## cleared by [method begin_spend_round].
var dust_spend_log: Array[Dictionary] = []
## Every Dust gain of this round, oldest first: {"slot": int (-1 = the team), "label": String,
## "amount": int, "wave": int}; cleared by [method begin_spend_round].
var dust_gain_log: Array[Dictionary] = []

# M6 damage meter (per player slot index, like kills_by_player / damage_by_player): written
# by the recorders below, read by the end screen. Wired in by the METER package.
## Effective healing done (credited to the healer; regen / leech count as self-healing).
var healing_by_player: Dictionary[int, float] = {}
## Damage absorbed by the shields a player cast (on anyone) and their own block.
var absorbed_by_player: Dictionary[int, float] = {}
## Damage a player took (after mitigation).
var damage_taken_by_player: Dictionary[int, float] = {}
## Balance diagnostics: the same damage by what dealt it, {source id (an EnemyData id,
## &"environment" for the poison puddles, ...): {wave: float}} (see [method record_damage_taken]).
var damage_taken_by_source: Dictionary = {}
## Balance diagnostics: the part of [member damage_by_player] that hit a boss (Morvain, Vor'thalax, the
## Dungeon Warden), SMOKE_RESULT "boss_damage": it shows which class can hurt a boss at all.
var boss_damage_by_player: Dictionary[int, float] = {}
## Balance diagnostics: the highest total absorb shield a hero ever carried, as a multiple of its Max HP
## (SMOKE_RESULT "shield_peak"): it shows whether the shield sources stack out of hand.
var shield_peak_by_player: Dictionary[int, float] = {}
## Revives a player took part in (teammate channel, Word of Glory).
var revives_by_player: Dictionary[int, int] = {}
## Times a player went down.
var downs_by_player: Dictionary[int, int] = {}
## Bosses a player landed the killing blow on ([method record_special_kill] &"boss").
var bosses_by_player: Dictionary[int, int] = {}
## How each hero ended the run, filled by [method record_hero_result] when the run is over (the
## heroes are freed afterwards): slot index -> {"alive": bool, "best_item": ItemInstance or null}.
var hero_results: Dictionary[int, Dictionary] = {}
## Seconds of wave play this run ([method tick_run_time]; the market, the loot roll and pauses
## do not count).
var run_time := 0.0

# M6 counters (SMOKE_RESULT, end screen).
var bosses_killed := 0
var artifacts_dropped := 0
var consumables_bought := 0
var black_market_bought := 0
var enchants_done := 0
## Artifact drop pity: the extra chance added to the next boss's Artifact roll, grown by every
## boss without a drop and reset on a drop (ARTIFACTS package).
var artifact_pity := 0.0
## Classes that already dropped their Artifact this run (max one per class, ARTIFACTS package).
var artifact_classes: Array[StringName] = []

# M6b counters (SMOKE_RESULT, end screen). The feature packages bump them.
## Mid-wave events that appeared (EventSpawner.start_event) / were won by the party.
var events_spawned := 0
var events_completed := 0
## Shrines offered at a break / accepted by the whole party (SHRINES package).
var shrines_offered := 0
var shrines_accepted := 0
## Dungeon portals the party walked into / cleared / failed (DUNGEON package).
var dungeons_entered := 0
var dungeons_completed := 0
var dungeons_failed := 0
## The shrine waiting for the break's SHRINE phase (a shrine id; &"" = none). The SHRINES package
## sets it when the break roll hits; Intermission.wants_shrine() reads it.
var pending_shrine: StringName = &""
## Shrine effects running over the next waves: {"id": StringName, "waves_left": int} (SHRINES package).
var shrine_effects: Array[Dictionary] = []
## The shrine effects work only while a wave is on (Shrines.begin_wave .. Shrines.end_wave): the multipliers
## of pickups and enemies read 1 outside, so the market, a dungeon or a test never sees them.
var shrine_effects_live := false
## The fraction of an XP point the shrine's XP bonus has not paid out yet ([method scale_xp]).
var shrine_xp_remainder := 0.0
## Every gold gain that was logged by name this round (the shrines' wins; [method add_gold_logged]): {"slot":
## int (-1 = the team), "label": String, "amount": int, "wave": int}. Cleared by [method begin_spend_round].
var gold_gain_log: Array[Dictionary] = []
## The dungeon portal is open for this break (DUNGEON package sets it at the wave end;
## Intermission.wants_portal() reads it).
var portal_pending := false
## This break's portal was opened by --dungeon (the bots then enter whatever the wave was) / the heroes
## downed during the wave just cleared (the bots' rule after waves 12 and 15). Set by Main at the
## wave's end, read by the PortalScreen.
var portal_forced := false
var last_wave_downs := 0
## Seconds the party spent in dungeons this run, and the rooms it cleared there (SMOKE_RESULT).
var dungeon_time := 0.0
var dungeon_rooms_cleared := 0


## The environment roll (ENV package): a run started with an empty environment takes
## [method roll_environment] (the seed-derived roll). [member environment_roller] stands in for the
## roll body when set (tests and the ENV package's own hooks).
static var environment_roller: Callable

## [param p_mode] (MODE_NORMAL / MODE_ENDLESS; anything else plays as normal), [param p_hardcore]
## and [param p_environment] (an id of Db.environments, or &"" = rolled by [method roll_environment]
## once the run seed and [member environment_rng] are set) are the M6b run settings.
func start_run(p_player_count: int, seed_value: int = -1, p_mode: StringName = MODE_NORMAL,
		p_hardcore: bool = false, p_environment: StringName = &"") -> void:
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
	run_seed = rng.seed
	mode = p_mode if p_mode in MODES else MODE_NORMAL
	hardcore = p_hardcore
	environment_rng = sub_rng(SALT_ENVIRONMENT)
	event_rng = sub_rng(SALT_EVENTS)
	shrine_rng = sub_rng(SALT_SHRINES)
	dungeon_rng = sub_rng(SALT_DUNGEON)
	environment = p_environment if p_environment != &"" else roll_environment()
	shrine_chance_override = -1.0
	event_override = &""
	dungeon_forced = false
	events_spawned = 0
	events_completed = 0
	shrines_offered = 0
	shrines_accepted = 0
	dungeons_entered = 0
	dungeons_completed = 0
	dungeons_failed = 0
	pending_shrine = &""
	shrine_effects.clear()
	shrine_effects_live = false
	shrine_xp_remainder = 0.0
	gold_gain_log.clear()
	portal_pending = false
	portal_forced = false
	last_wave_downs = 0
	dungeon_time = 0.0
	dungeon_rooms_cleared = 0
	kills = 0
	gold_earned = 0
	free_rerolls = 0
	kills_by_player.clear()
	damage_by_player.clear()
	_gold_remainder.clear()
	team_loot.clear()
	loot_drops_this_wave = 0
	shop = Shop.new()
	need_wins_by_player.clear()
	greed_gold = 0
	spend_log.clear()
	gold_spent = 0
	wants.clear()
	elites_spawned = 0
	elites_killed = 0
	goblins_spawned = 0
	goblins_killed = 0
	goblins_escaped = 0
	weapons_forged = 0
	talent_resets = 0
	arcane_dust = 0
	dust_earned = 0
	dust_spent = 0
	dust_spend_log.clear()
	dust_gain_log.clear()
	healing_by_player.clear()
	absorbed_by_player.clear()
	damage_taken_by_player.clear()
	damage_taken_by_source.clear()
	boss_damage_by_player.clear()
	shield_peak_by_player.clear()
	revives_by_player.clear()
	downs_by_player.clear()
	bosses_by_player.clear()
	hero_results.clear()
	run_time = 0.0
	bosses_killed = 0
	artifacts_dropped = 0
	consumables_bought = 0
	black_market_bought = 0
	enchants_done = 0
	artifact_pity = 0.0
	artifact_classes.clear()
	run_serial += 1
	# Launch-option statics back to their defaults (Main applies --elite-mult / --goblin-chance /
	# --boss-hp / --artifact-chance after this; tests that change them restore them).
	EliteAffixes.rate_mult = 1.0
	GoblinSpawner.chance_override = -1.0
	BossData.hp_mult = 1.0
	LootDrops.artifact_chance_override = -1.0
	run_started.emit()
	gold_changed.emit(gold, 0)
	dust_changed.emit(arcane_dust, 0)
	xp_changed.emit(xp, xp_to_next_level())
	shrines_changed.emit()


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


## True while the current [member wave] is the run's last one (never in the endless mode).
func is_last_wave() -> bool:
	return is_final_wave(wave)


# --- Run length (M6b: modes) --------------------------------------------------------------------

## Waves of a [param p_mode] run: TOTAL_WAVES (25) in the normal mode, ENDLESS_WAVES (0 = unbounded)
## in the endless mode.
static func waves_for_mode(p_mode: StringName) -> int:
	return ENDLESS_WAVES if p_mode == MODE_ENDLESS else TOTAL_WAVES


## The length of the current run: 25 (normal) or 0 (endless: no last wave). Every wave count in the
## game – the clamp of the wave number, the "Final Wave" banner, the victory check, the "Wave n / 25"
## texts, the end screen – reads this, never a literal 25.
func total_waves() -> int:
	return waves_for_mode(mode)


func is_endless() -> bool:
	return mode == MODE_ENDLESS


## Wave [param w] ends the run when it is won: the last wave of a normal run; never in the endless mode.
func is_final_wave(w: int) -> bool:
	var total := total_waves()
	return total > 0 and w >= total


## [param w] as a valid wave number of this run: at least 1, at most total_waves() (no upper bound
## in the endless mode).
func clamp_wave(w: int) -> int:
	var total := total_waves()
	return maxi(w, 1) if total <= 0 else clampi(w, 1, total)


## "12 / 25" for a wave count in a normal run, just "12" in the endless mode.
func count_text(n: int) -> String:
	var total := total_waves()
	return "%d / %d" % [n, total] if total > 0 else str(n)


## "Wave 12 / 25" (normal) or "Wave 12" (endless): the HUD plaque.
func wave_progress_text(w: int) -> String:
	return "Wave %s" % count_text(w)


## "Normal", "Endless", "Normal · Hardcore" ... ([param p_mode] capitalised, empty = Normal, plus
## " · Hardcore"; the lobby header, the end screen and the run card use the same words).
static func mode_text(p_mode: StringName, p_hardcore: bool = false) -> String:
	var text := "Normal" if p_mode == &"" else String(p_mode).capitalize()
	return text + " · Hardcore" if p_hardcore else text


# --- Own random generators (M6b) -----------------------------------------------------------------

## A well-mixed seed from [param base_seed] and [param salt] (SplitMix64): the same inputs always give
## the same seed, different salts give unrelated ones.
static func derived_seed(base_seed: int, salt: int) -> int:
	var z := base_seed + salt * -7046029254386353131
	z = (z ^ (z >> 30)) * -4658895280553007687
	z = (z ^ (z >> 27)) * -7723592293110705685
	return (z ^ (z >> 31)) & 0x7FFFFFFFFFFFFFFF


## A fresh generator seeded from [member run_seed] and [param salt] (SALT_*). Calling it twice gives
## two generators with the same stream; it never touches [member rng].
func sub_rng(salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = derived_seed(run_seed, salt)
	return r


## The environment of a run that was started without one (start_run calls it after run_seed and
## environment_rng are set): ONE draw from [member environment_rng] ([method pick_environment]), never
## from [member rng] – so the roll is a function of the run seed alone and
## [method environment_for_seed] tells it before the run exists (the "Rolling the arena..." screen).
## [member environment_roller] replaces the body when set (tests).
func roll_environment() -> StringName:
	if environment_roller.is_valid():
		return environment_roller.call() as StringName
	return pick_environment(environment_rng)


## The environment a run with seed [param seed_value] rolls (what [method roll_environment] returns
## for it): the first draw of a generator seeded like environment_rng.
static func environment_for_seed(seed_value: int) -> StringName:
	var r := RandomNumberGenerator.new()
	r.seed = derived_seed(seed_value, SALT_ENVIRONMENT)
	return pick_environment(r)


## One weighted draw (by EnvironmentData.roll_weight; a weight of 0 never wins) over
## Db.environment_ids, in that order. The default environment when nothing can be drawn.
static func pick_environment(r: RandomNumberGenerator) -> StringName:
	var ids: Array[StringName] = []
	var total := 0.0
	for id in Db.environment_ids:
		var env := Db.get_environment(id)
		if env != null and env.roll_weight > 0.0:
			ids.append(id)
			total += env.roll_weight
	if ids.is_empty():
		return DEFAULT_ENVIRONMENT
	var pick := r.randf() * total
	for id in ids:
		pick -= Db.get_environment(id).roll_weight
		if pick < 0.0:
			return id
	return ids[ids.size() - 1]


# --- Shared wallet -----------------------------------------------------------

func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold += amount
	if amount > 0:
		gold_earned += amount
	gold_changed.emit(gold, amount)


## Puts [param amount] of starting gold into the shared wallet (M9 LEVELS: the Class Level bonus, Meta.apply_run_start). Not
## earned gold: the run's gold_earned stays as it is.
func grant_starting_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
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


## [method add_gold] that also logs where the gold came from (the Gambler's win): player slot
## [param slot_index] (-1 = the team), a display [param label]. Non-positive amounts do nothing. The gold
## twin of [method add_dust]'s gain log.
func add_gold_logged(amount: int, slot_index: int = -1, label: String = "") -> void:
	if amount <= 0:
		return
	add_gold(amount)
	gold_gain_log.append({"slot": slot_index, "label": label, "amount": amount, "wave": wave})


func can_afford(amount: int) -> bool:
	return gold >= amount


## Spends from the shared wallet. Returns false (and changes nothing) if too poor.
## Game code goes through [method try_spend_for] (the spend log); this one stays for tests.
func try_spend(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold, -amount)
	return true


## [method try_spend] that also logs who spent what (GDD 10, the purse board): player slot
## [param slot_index] (-1 = the team, e.g. a stall reroll), [param kind] (&"shop",
## &"shop_forge", &"shop_reroll", &"trainer", &"level_reroll", &"talent_reset") and a display
## [param label] ("Rare Dagger", "Fireball Rank III"). M6 adds the kinds &"consumable" (a
## consumables-row card), &"black_market" (the Black Market offer) and &"enchant" (an Enchanter
## action; its Dust part goes through [method try_spend_dust_for] with the same kind). M6b adds
## &"shrine" (the purse a Shrine of Fortune / of the Gambler takes at once; slot -1 = the team). On
## success the entry goes to [member spend_log], the amount to [member gold_spent], and
## [signal spent] fires.
func try_spend_for(amount: int, slot_index: int, kind: StringName, label: String) -> bool:
	if not try_spend(amount):
		return false
	var entry := {"slot": slot_index, "kind": kind, "label": label, "amount": amount, "wave": wave}
	spend_log.append(entry)
	gold_spent += amount
	spent.emit(entry)
	return true


## Adds [param amount] Arcane Dust to the team's pile (Disenchant, an item nobody wanted),
## earned by player slot [param slot_index] (-1 = the team) for [param label] ("Epic Sword").
## Non-positive amounts do nothing. Emits [signal dust_changed].
func add_dust(amount: int, slot_index: int = -1, label: String = "") -> void:
	if amount <= 0:
		return
	arcane_dust += amount
	dust_earned += amount
	dust_gain_log.append({"slot": slot_index, "label": label, "amount": amount, "wave": wave})
	dust_changed.emit(arcane_dust, amount)


func can_afford_dust(amount: int) -> bool:
	return arcane_dust >= amount


## Spends [param amount] Arcane Dust for player slot [param slot_index] (-1 = the team) on
## [param kind] (&"enchant") with a display [param label]; the Dust twin of
## [method try_spend_for]. Returns false (and changes nothing) if the pile is too small or the
## amount is negative. On success the entry goes to [member dust_spend_log], the amount to
## [member dust_spent], and [signal dust_changed] fires.
func try_spend_dust_for(amount: int, slot_index: int, kind: StringName, label: String) -> bool:
	if amount < 0 or arcane_dust < amount:
		return false
	arcane_dust -= amount
	dust_spent += amount
	var entry := {"slot": slot_index, "kind": kind, "label": label, "amount": amount, "wave": wave}
	dust_spend_log.append(entry)
	dust_changed.emit(arcane_dust, -amount)
	return true


## A new market round (Intermission.open): clears this round's spend logs and the wants.
func begin_spend_round() -> void:
	spend_log.clear()
	dust_spend_log.clear()
	dust_gain_log.clear()
	gold_gain_log.clear()
	if not wants.is_empty():
		wants.clear()
		wants_changed.emit()


## Adds (returns true) or removes (false) [param slot_index]'s want [param key]
## ("trainer:<ability_id>") with its [param label] and [param price].
func toggle_want(slot_index: int, key: String, label: String, price: int) -> bool:
	var at := _want_index(slot_index, key)
	if at >= 0:
		wants.remove_at(at)
		wants_changed.emit()
		return false
	wants.append({"slot": slot_index, "key": key, "label": label, "price": price})
	wants_changed.emit()
	return true


## Removes [param slot_index]'s want [param key] (bought, or the reason went away).
func clear_want(slot_index: int, key: String) -> void:
	var at := _want_index(slot_index, key)
	if at >= 0:
		wants.remove_at(at)
		wants_changed.emit()


func has_want(slot_index: int, key: String) -> bool:
	return _want_index(slot_index, key) >= 0


func _want_index(slot_index: int, key: String) -> int:
	for i in wants.size():
		if int(wants[i].get("slot", -2)) == slot_index and String(wants[i].get("key", "")) == key:
			return i
	return -1


# --- Shrine effects (M6b, SHRINES package; the rules live in Shrines) -----------------------------

## True while shrine [param id] runs.
func has_shrine_effect(id: StringName) -> bool:
	return shrine_waves_left(id) > 0


## Waves the running shrine [param id] has left (0 = not running).
func shrine_waves_left(id: StringName) -> int:
	for e in shrine_effects:
		if StringName(e.get("id", &"")) == id:
			return int(e.get("waves_left", 0))
	return 0


## Starts shrine [param id] for [param waves] waves (it restarts when it already runs).
func add_shrine_effect(id: StringName, waves: int) -> void:
	if id == &"" or waves <= 0:
		return
	for e in shrine_effects:
		if StringName(e.get("id", &"")) == id:
			e["waves_left"] = waves
			shrines_changed.emit()
			return
	shrine_effects.append({"id": id, "waves_left": waves})
	shrines_changed.emit()


## A wave is over: every running shrine has one wave less; the ones that reach 0 are removed and returned
## (oldest first).
func tick_shrine_effects() -> Array[StringName]:
	var expired: Array[StringName] = []
	for i in range(shrine_effects.size() - 1, -1, -1):
		var left := int(shrine_effects[i].get("waves_left", 0)) - 1
		if left <= 0:
			expired.push_front(StringName(shrine_effects[i].get("id", &"")))
			shrine_effects.remove_at(i)
		else:
			shrine_effects[i]["waves_left"] = left
	if not shrine_effects.is_empty() or not expired.is_empty():
		shrines_changed.emit()
	return expired


## [param amount] pickup XP times the running shrines' XP bonus ([method Shrines.xp_mult]), whole points: the
## fraction a pickup could not pay is kept for the next one. Plain [param amount] while no shrine boosts XP.
func scale_xp(amount: int) -> int:
	var mult := Shrines.xp_mult()
	if amount <= 0 or is_equal_approx(mult, 1.0):
		return amount
	var exact := amount * mult + shrine_xp_remainder
	var whole := floori(exact + 0.000001)
	shrine_xp_remainder = maxf(0.0, exact - whole)
	return whole


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
## Every hero has this many (TalentState).
func talent_points_earned() -> int:
	return maxi(0, level - TALENT_START_LEVEL + 1)


## Test hook (--start-level): the team starts at [param p_level] (at least START_LEVEL) with no
## XP and no pending level-ups. Call it after start_run and before the heroes are created.
func set_start_level(p_level: int) -> void:
	level = maxi(START_LEVEL, p_level)
	xp = 0
	pending_level_ups = 0
	xp_changed.emit(xp, xp_to_next_level())


# --- Statistics --------------------------------------------------------------

func record_kill(player_index: int) -> void:
	kills += 1
	if player_index >= 0:
		kills_by_player[player_index] = kills_by_player.get(player_index, 0) + 1


## The total shield of slot [param player_index] reached [param ratio] x its Max HP (keeps the highest).
func record_shield_peak(player_index: int, ratio: float) -> void:
	if player_index >= 0 and ratio > shield_peak_by_player.get(player_index, 0.0):
		shield_peak_by_player[player_index] = ratio


## [param amount] damage slot [param player_index] dealt; [param on_boss] = the target was a boss (also
## counted in [member boss_damage_by_player]).
func record_damage(player_index: int, amount: float, on_boss: bool = false) -> void:
	if player_index >= 0:
		damage_by_player[player_index] = damage_by_player.get(player_index, 0.0) + amount
		if on_boss:
			boss_damage_by_player[player_index] = boss_damage_by_player.get(player_index, 0.0) + amount


## An elite (&"elite"), the Loot Goblin (&"goblin") or a boss (&"boss") died, killed by slot
## [param killer_index] (-1 = none): counts it and emits [signal special_killed] (meta
## statistics).
func record_special_kill(kind: StringName, killer_index: int) -> void:
	match kind:
		&"elite":
			elites_killed += 1
		&"goblin":
			goblins_killed += 1
		&"boss":
			bosses_killed += 1
			if killer_index >= 0:
				bosses_by_player[killer_index] = bosses_by_player.get(killer_index, 0) + 1
	special_killed.emit(kind, killer_index)


# M6 damage-meter recorders (the METER package calls them; a slot index < 0 = nobody, ignored).

## [param amount] HP healed by slot [param player_index] (the effective gain, after the max-HP clamp).
func record_heal(player_index: int, amount: float) -> void:
	if player_index >= 0 and amount > 0.0:
		healing_by_player[player_index] = healing_by_player.get(player_index, 0.0) + amount


## [param amount] damage absorbed by a shield / block of slot [param player_index].
func record_absorb(player_index: int, amount: float) -> void:
	if player_index >= 0 and amount > 0.0:
		absorbed_by_player[player_index] = absorbed_by_player.get(player_index, 0.0) + amount


## [param amount] damage slot [param player_index] took after mitigation. With a
## [param source_id] (the dealer: an enemy's data id, &"environment" ...) it is also added to
## [member damage_taken_by_source] under the current wave (balance diagnostics, SMOKE_RESULT).
func record_damage_taken(player_index: int, amount: float, source_id: StringName = &"") -> void:
	if player_index >= 0 and amount > 0.0:
		damage_taken_by_player[player_index] = damage_taken_by_player.get(player_index, 0.0) + amount
		if source_id != &"":
			var per_wave: Dictionary = damage_taken_by_source.get(source_id, {})
			per_wave[wave] = float(per_wave.get(wave, 0.0)) + amount
			damage_taken_by_source[source_id] = per_wave


## Slot [param player_index] took part in a revive (credited to every reviver).
func record_revive(player_index: int) -> void:
	if player_index >= 0:
		revives_by_player[player_index] = revives_by_player.get(player_index, 0) + 1


## Slot [param player_index] went down.
func record_down(player_index: int) -> void:
	if player_index >= 0:
		downs_by_player[player_index] = downs_by_player.get(player_index, 0) + 1


## How slot [param player_index]'s hero ended the run: [param alive] (standing, not downed) and its
## [param best_item] (an [ItemInstance], null = none; see RunSummary.best_item). Main records it
## for every hero when the run ends, before the end screen opens.
func record_hero_result(player_index: int, alive: bool, best_item: ItemInstance = null) -> void:
	if player_index >= 0:
		hero_results[player_index] = {"alive": alive, "best_item": best_item}


## Adds [param delta] seconds of wave play to [member run_time] (Main, state WAVE, every
## physics tick; non-positive values are ignored).
func tick_run_time(delta: float) -> void:
	if delta > 0.0:
		run_time += delta


# --- Wave / co-op scaling (GDD 9) -------------------------------------------

## Seconds of wave [param w] (GDD 1): waves 1-10 last 20 + 5 * (w - 1) s, at most 60 s
## (waves 9 and 10 are 60 s); every wave above 10 adds 10 s (11 = 70 s ... 25 = 210 s). The endless
## waves above 25 stay at [constant MAX_WAVE_DURATION] (210 s).
static func wave_duration(w: int) -> float:
	if w > 10:
		return minf(MAX_WAVE_DURATION, 60.0 + 10.0 * (w - 10))
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


## Wave [param w] is a boss wave: 10 and 25, and in the endless mode (the only way to reach them) every
## 5th wave from the 30th ([method is_endless_boss_wave]).
static func is_boss_wave(w: int) -> bool:
	return w in BOSS_WAVES or is_endless_boss_wave(w)


## Wave [param w] is an elite wave: 20, and in the endless mode the 33rd and every 10th wave after it
## ([method is_endless_elite_wave]).
static func is_elite_wave(w: int) -> bool:
	return w in ELITE_WAVES or is_endless_elite_wave(w)


## One of the endless mode's extra boss waves: 30, 35, 40 ... (waves above 25 exist only in the endless mode).
static func is_endless_boss_wave(w: int) -> bool:
	return w >= ENDLESS_BOSS_FIRST_WAVE and (w - ENDLESS_BOSS_FIRST_WAVE) % ENDLESS_BOSS_EVERY == 0


## One of the endless mode's extra elite waves: 33, 43, 53 ...
static func is_endless_elite_wave(w: int) -> bool:
	return w >= ENDLESS_ELITE_FIRST_WAVE and (w - ENDLESS_ELITE_FIRST_WAVE) % ENDLESS_ELITE_EVERY == 0


## Clearing wave [param w] opens the endless part of the run: the endless mode's wave 25 (the normal run's
## last wave) does not end the run, it shows the "Endless begins!" banner and wave 26 follows.
func begins_endless(w: int) -> bool:
	return is_endless() and w == TOTAL_WAVES
