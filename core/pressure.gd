class_name Pressure
extends RefCounted
## Tear-Jerker pressure (GDD 9.1, M9 ACHIEVE-DIFF): on a Tear-Jerker run most waves carry ONE rotating modifier
## ([PressureData], data/pressure/ – Salt Rain, Hardened Peel, Paring Knives, Wilting Heat, Weeping Fog, Bitter
## Harvest). The rotation is a pure function of the run seed.
##
## Rotation: waves 1 and 2 are calm ([constant FIRST_WAVE]); from wave 3 every wave except the boss waves and the elite
## waves gets one, picked uniformly among the modifiers without repeating the previous wave's. The pick for wave n+1
## is rolled when wave n ends ([method end_wave], RunState.pressure_next – the break screen announces it) from
## RunState.pressure_rng, a generator of its own (sub_rng(SALT_PRESSURE)): it never touches RunState.rng, so the
## pressure changes no other roll of the run. A run that starts on a later wave rolls its first one at the wave's start.
##
## Life of a wave (the same seams as the shrines): Main.start_wave -> [method begin_wave] (the modifier goes live and the
## heroes get their side of it, PlayerBonuses source [constant SOURCE]); Main's break path -> [method end_wave] (the
## effects stop, the next modifier is rolled). The multipliers below are 1.0 outside a wave, so the market, a dungeon
## (its rooms ignore pressure) and the unit tests never see them.
## Read by: Difficulty (enemy HP / damage, spawn rate), Enemy.setup (speed), EliteAffixes.expected_count, Shrines
## (gold / XP of the pickups), the HUD chip, the wave banner and the break screen.

## PlayerBonuses source of the heroes' pressure effects.
const SOURCE := &"pressure"
## The first wave that can carry a modifier.
const FIRST_WAVE := 3


# --- The rotation -------------------------------------------------------------------------------

## True when [param wave] of the run in progress carries a modifier: a pressure tier, wave 3 or later, no boss
## wave, no elite wave.
static func is_pressure_wave(wave: int) -> bool:
	return Difficulty.current().pressure and wave >= FIRST_WAVE and not RunState.is_boss_wave(wave) \
			and not RunState.is_elite_wave(wave)


## The modifier of a wave that follows one carrying [param previous]: one draw from RunState.pressure_rng among the
## ids except [param previous]. &"" (no draw) when nothing is defined.
static func pick(previous: StringName) -> StringName:
	var candidates: Array[StringName] = []
	for id in Db.pressure_ids:
		if id != previous:
			candidates.append(id)
	if candidates.is_empty():
		return &""
	return candidates[RunState.pressure_rng.randi_range(0, candidates.size() - 1)]


## The modifier for [param wave] ([param previous]: the one of the wave before it): &"" for a calm wave (no draw),
## else [method pick].
static func roll_for(wave: int, previous: StringName) -> StringName:
	return pick(previous) if is_pressure_wave(wave) else &""


## Wave [param wave] starts (Main.start_wave, before the director starts the wave): the planned modifier of the
## wave - or one rolled now when none was planned - goes live and the heroes get their effects.
static func begin_wave(wave: int, players: Array) -> void:
	var picked: StringName
	if RunState.pressure_next_wave == wave:
		picked = RunState.pressure_next
	else:
		picked = roll_for(wave, RunState.pressure_current)
	RunState.pressure_next = &""
	RunState.pressure_next_wave = 0
	RunState.pressure_current = picked
	RunState.pressure_live = picked != &""
	for p: Variant in players:
		apply_to_hero(p as Player)
	RunState.pressure_changed.emit()


## Wave [param wave] is over (Main's break path): the effects stop, the heroes lose them, and the modifier of the next
## wave is rolled (RunState.pressure_next, for the break screen).
static func end_wave(wave: int, players: Array) -> void:
	var previous := RunState.pressure_current
	RunState.pressure_live = false
	RunState.pressure_current = &""
	for p: Variant in players:
		clear_hero(p as Player)
	RunState.pressure_next_wave = wave + 1
	RunState.pressure_next = roll_for(wave + 1, previous)
	RunState.pressure_changed.emit()


## The modifier of the wave being played (&"" = none).
static func current_id() -> StringName:
	return RunState.pressure_current if RunState.pressure_live else &""


static func current() -> PressureData:
	return Db.get_pressure(current_id())


# --- Multipliers (1.0 outside a wave) -----------------------------------------------------------

static func _product(field: StringName) -> float:
	if not RunState.pressure_live:
		return 1.0
	var data := Db.get_pressure(RunState.pressure_current)
	if data == null:
		return 1.0
	return maxf(0.0, 1.0 + float(data.get(field)) / 100.0)


static func enemy_hp_mult() -> float:
	return _product(&"enemy_hp_pct")


static func enemy_damage_mult() -> float:
	return _product(&"enemy_damage_pct")


static func enemy_speed_mult() -> float:
	return _product(&"enemy_speed_pct")


## The WaveDirector's spawn budget.
static func spawn_mult() -> float:
	return _product(&"spawn_rate_pct")


## The elites of the wave (EliteAffixes.expected_count).
static func elite_mult() -> float:
	return _product(&"elite_rate_pct")


## Gold / XP of the pickups (folded into Shrines.gold_mult / xp_mult).
static func gold_mult() -> float:
	return _product(&"gold_pct")


static func xp_mult() -> float:
	return _product(&"xp_pct")


# --- Heroes --------------------------------------------------------------------------------------

## Puts the hero side of the live modifier into [param player]'s bonuses (PlayerBonuses source [constant SOURCE]).
static func apply_to_hero(player: Player) -> void:
	if player == null or not is_instance_valid(player) or player.bonuses == null:
		return
	var entries: Array[Dictionary] = []
	var data := current()
	if data != null and not data.hero_effects.is_empty():
		entries.append_array(Consumables.resolve_effects(_shim(data), player))
	if entries.is_empty() and player.bonuses.effects_of(SOURCE).is_empty():
		return
	player.bonuses.set_effects(SOURCE, entries)


## Takes the pressure's effects off [param player].
static func clear_hero(player: Player) -> void:
	if player == null or not is_instance_valid(player) or player.bonuses == null:
		return
	if player.bonuses.effects_of(SOURCE).is_empty():
		return
	player.bonuses.set_effects(SOURCE, [] as Array[Dictionary])


## The hero-effect entries of [param data] as a ConsumableData: the consumables' resolver turns "stats_pct" into plain
## stats against the hero's current numbers (not cached: a static Resource would still be alive at exit).
static func _shim(data: PressureData) -> ConsumableData:
	var shim := ConsumableData.new()
	shim.id = data.id
	shim.display_name = data.display_name
	shim.effects = data.hero_effects
	return shim


# --- Texts ---------------------------------------------------------------------------------------

## "Weeping Fog" for the HUD chip ("" = none live).
static func chip_text() -> String:
	var data := current()
	return data.display_name if data != null else ""


## The wave banner's sub-line: "Pressure – Weeping Fog: Your Speed -12, enemy speed +10%." ("" = none).
static func banner_line() -> String:
	var data := current()
	if data == null:
		return ""
	return "Pressure – %s: %s" % [data.display_name, data.text]


## What the break screen adds to the "Next up" line: "  ·  Pressure: Weeping Fog" ("" when the next wave is calm).
static func next_wave_suffix(next_wave: int) -> String:
	if RunState.pressure_next_wave != next_wave or RunState.pressure_next == &"":
		return ""
	var data := Db.get_pressure(RunState.pressure_next)
	return "  ·  Pressure: %s" % data.display_name if data != null else ""
