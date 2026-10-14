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
## An Artifact dropped (LootDrops.roll_artifact hit): the new [param item] and the id of the kill's
## source (ItemGenerator.SOURCE_IDS: &"boss", &"goblin", &"elite", &"loot"). Main logs it.
signal artifact_dropped(item: ItemInstance, source: StringName)

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
const COOP_DAMAGE_MULTS: Array[float] = [0.45, 0.6, 0.75, 0.95]

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
## Revives a player took part in (teammate channel, Word of Glory).
var revives_by_player: Dictionary[int, int] = {}
## Times a player went down.
var downs_by_player: Dictionary[int, int] = {}
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
	revives_by_player.clear()
	downs_by_player.clear()
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
## action; its Dust part goes through [method try_spend_dust_for] with the same kind). On
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


func record_damage(player_index: int, amount: float) -> void:
	if player_index >= 0:
		damage_by_player[player_index] = damage_by_player.get(player_index, 0.0) + amount


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


## [param amount] damage slot [param player_index] took after mitigation.
func record_damage_taken(player_index: int, amount: float) -> void:
	if player_index >= 0 and amount > 0.0:
		damage_taken_by_player[player_index] = damage_taken_by_player.get(player_index, 0.0) + amount


## Slot [param player_index] took part in a revive (credited to every reviver).
func record_revive(player_index: int) -> void:
	if player_index >= 0:
		revives_by_player[player_index] = revives_by_player.get(player_index, 0) + 1


## Slot [param player_index] went down.
func record_down(player_index: int) -> void:
	if player_index >= 0:
		downs_by_player[player_index] = downs_by_player.get(player_index, 0) + 1


## Adds [param delta] seconds of wave play to [member run_time] (Main, state WAVE, every
## physics tick; non-positive values are ignored).
func tick_run_time(delta: float) -> void:
	if delta > 0.0:
		run_time += delta


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
