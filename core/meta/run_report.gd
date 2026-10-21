class_name RunReport
extends RefCounted
## What a finished run tells the meta-progression (M9): plain data built once at the run's end from the stats the
## game already keeps ([method collect]) and handed to [method Meta.record_run], which passes it to the listeners
## (Class XP, Seeds, achievements, Wardrobe ...). Nothing in it is the engine's state, so tests build their own
## ([method make]) and the listeners can be unit tested without a run.
##
## Fields:
##   victory / abandoned     - the run was won / given up (quit to the menu, the last hero dropped out)
##   mode, hardcore, endless - the run settings (RunState); environment: the arena's id
##   difficulty              - the difficulty tier id (RunState.difficulty; &"normal" for a report made without one)
##   party                   - the class ids as the run started, in slot order (duplicates when two heroes share one)
##   wave / waves_cleared    - the wave the run ended on / waves cleared this run
##   stats                   - run-wide numbers, see [method collect] for the list (stat id -> float)
##   heroes                  - per hero of the run (one who left mid-run included, see [method hero_entry]): {"slot", "class_id", "alive", "damage", "healing", "absorbed",
##                             "taken", "kills", "bosses", "revives", "downs", "need_wins", "capstones" (capstone talents
##                             taken), "rank5" (abilities at Rank V), "sets_active" (set bonuses active), "companion",
##                             "equipped": [item summaries: {"source_id", "slot_type", "equip_slot", "armor_type",
##                             "rarity", "wave", "item_level", "unique", "set_id", "look": {EquipLook fields} or {}}]}
##   flags                   - named run facts the achievement conditions test ([method flag]): victory, abandoned,
##                             hardcore, endless, solo, full_party, no_downs, final_boss_down ("a win": the run was
##                             won, or in the endless mode the wave-25 boss died) (+ mode, environment, difficulty as text)

## The stat ids [method collect] fills (all numbers; run-wide).
const STAT_IDS: Array[StringName] = [
	&"party_size", &"wave", &"waves_cleared", &"level", &"run_time", &"kills", &"elites_spawned", &"elites_killed",
	&"goblins_spawned", &"goblins_killed", &"goblins_escaped", &"bosses_killed", &"artifacts_dropped",
	&"weapons_forged", &"talent_resets", &"consumables_bought", &"black_market_bought", &"enchants_done",
	&"dust_earned", &"dust_spent", &"gold_earned", &"gold_spent", &"need_wins", &"greed_gold",
	&"events_spawned", &"events_completed", &"shrines_offered", &"shrines_accepted", &"dungeons_entered",
	&"dungeons_completed", &"dungeons_failed", &"dungeon_rooms_cleared", &"downs", &"revives", &"damage",
	&"healing", &"absorbed", &"damage_taken", &"items_bought", &"items_looted", &"loot_rolls", &"level_cards",
	&"ranks_trained", &"shop_rerolls", &"legendaries_held", &"boss_wave_down", &"need_legendary_wins",
]

var victory := false
var abandoned := false
var mode: StringName = RunState.MODE_NORMAL
var hardcore := false
var endless := false
var environment: StringName = &""
var difficulty: StringName = &"normal"
var party: Array[StringName] = []
var wave := 0
var waves_cleared := 0
var stats: Dictionary[StringName, float] = {}
var heroes: Array[Dictionary] = []
var flags: Dictionary[StringName, Variant] = {}
## [method Meta.record_run] handled this report (it records a report once).
var recorded := false
## [method AchievementEngine.update_counters] added this report to the profile's counters (so a "lifetime total"
## condition does not count the run twice).
var counted := false


## A report from plain values (tests, scripts): [param p_party] the class ids in slot order, [param p_stats] the run
## stats, [param p_flags] extra flags (victory / abandoned / hardcore ... are set from the parameters).
static func make(p_party: Array[StringName], p_victory: bool, p_stats: Dictionary = {}, p_flags: Dictionary = {},
		p_heroes: Array[Dictionary] = []) -> RunReport:
	var r := RunReport.new()
	r.party = p_party.duplicate()
	r.victory = p_victory
	for key: Variant in p_stats:
		r.stats[StringName(str(key))] = float(p_stats[key])
	r.heroes = p_heroes.duplicate(true)
	r.wave = int(r.stat(&"wave"))
	r.waves_cleared = int(r.stat(&"waves_cleared"))
	if not r.stats.has(&"party_size"):
		r.stats[&"party_size"] = float(p_party.size())
	r._build_flags()
	for key: Variant in p_flags:
		r.flags[StringName(str(key))] = p_flags[key]
	return r


## The report of the run that just ended, from RunState and the joined slots. [param p_extras] carries what Main
## counts itself: "wave", "waves_cleared", "classes" (the party as the run started), "items_bought", "items_looted",
## "loot_rolls", "level_cards", "ranks_trained", "shop_rerolls", "difficulty", "departed_heroes" (the [method hero_entry]
## snapshots of the heroes who left mid-run: their slots are gone, but they stay in [member heroes]). The run-wide
## totals (downs, revives, damage, healing, absorbed, damage taken, need wins) count every hero of the run, a departed
## one too (RunState keeps the per-player numbers until the next run). Draws no random number and changes nothing.
static func collect(p_victory: bool, p_abandoned: bool, p_extras: Dictionary = {}) -> RunReport:
	var r := RunReport.new()
	r.victory = p_victory
	r.abandoned = p_abandoned
	r.mode = RunState.mode
	r.hardcore = RunState.hardcore
	r.endless = RunState.is_endless()
	r.environment = RunState.environment
	r.difficulty = StringName(str(p_extras.get("difficulty", "normal")))
	var classes: Variant = p_extras.get("classes", [])
	if classes is Array:
		for id: Variant in classes:
			r.party.append(StringName(str(id)))
	r.wave = int(p_extras.get("wave", RunState.wave))
	r.waves_cleared = int(p_extras.get("waves_cleared", 0))
	var slots := PlayerManager.get_slots()
	var legendaries := 0
	for slot in slots:
		r.heroes.append(hero_entry(slot))
		legendaries += _legendaries_held(slot)
	_add_departed(r, p_extras.get("departed_heroes", []), slots)
	var downs := int(_total(RunState.downs_by_player))
	var revives := int(_total(RunState.revives_by_player))
	var damage := _total(RunState.damage_by_player)
	var healing := _total(RunState.healing_by_player)
	var absorbed := _total(RunState.absorbed_by_player)
	var taken := _total(RunState.damage_taken_by_player)
	var need_wins := int(_total(RunState.need_wins_by_player))
	if r.party.is_empty():
		for slot in slots:
			r.party.append(slot.class_data.id if slot.class_data != null else &"")
	r.stats = {
		&"party_size": float(maxi(r.party.size(), slots.size())),
		&"wave": float(r.wave),
		&"waves_cleared": float(r.waves_cleared),
		&"level": float(RunState.level),
		&"run_time": RunState.run_time,
		&"kills": float(RunState.kills),
		&"elites_spawned": float(RunState.elites_spawned),
		&"elites_killed": float(RunState.elites_killed),
		&"goblins_spawned": float(RunState.goblins_spawned),
		&"goblins_killed": float(RunState.goblins_killed),
		&"goblins_escaped": float(RunState.goblins_escaped),
		&"bosses_killed": float(RunState.bosses_killed),
		&"artifacts_dropped": float(RunState.artifacts_dropped),
		&"weapons_forged": float(RunState.weapons_forged),
		&"talent_resets": float(RunState.talent_resets),
		&"consumables_bought": float(RunState.consumables_bought),
		&"black_market_bought": float(RunState.black_market_bought),
		&"enchants_done": float(RunState.enchants_done),
		&"dust_earned": float(RunState.dust_earned),
		&"dust_spent": float(RunState.dust_spent),
		&"gold_earned": float(RunState.gold_earned),
		&"gold_spent": float(RunState.gold_spent),
		&"need_wins": float(need_wins),
		&"greed_gold": float(RunState.greed_gold),
		&"events_spawned": float(RunState.events_spawned),
		&"events_completed": float(RunState.events_completed),
		&"shrines_offered": float(RunState.shrines_offered),
		&"shrines_accepted": float(RunState.shrines_accepted),
		&"dungeons_entered": float(RunState.dungeons_entered),
		&"dungeons_completed": float(RunState.dungeons_completed),
		&"dungeons_failed": float(RunState.dungeons_failed),
		&"dungeon_rooms_cleared": float(RunState.dungeon_rooms_cleared),
		&"downs": float(downs),
		&"revives": float(revives),
		&"damage": damage,
		&"healing": healing,
		&"absorbed": absorbed,
		&"damage_taken": taken,
		&"items_bought": float(int(p_extras.get("items_bought", 0))),
		&"items_looted": float(int(p_extras.get("items_looted", 0))),
		&"loot_rolls": float(int(p_extras.get("loot_rolls", 0))),
		&"level_cards": float(int(p_extras.get("level_cards", 0))),
		&"ranks_trained": float(int(p_extras.get("ranks_trained", 0))),
		&"shop_rerolls": float(int(p_extras.get("shop_rerolls", 0))),
		&"legendaries_held": float(legendaries),
		&"boss_wave_down": float(RunState.boss_wave_down),
		&"need_legendary_wins": float(RunState.need_legendary_wins),
	}
	r._build_flags()
	return r


# --- Reading ------------------------------------------------------------------------------------

## The run-wide stat [param id] (0 when the report has none).
func stat(id: StringName) -> float:
	return stats.get(id, 0.0)


## The named run fact [param id] (null when unknown); booleans for the yes / no facts, text for mode, environment
## and difficulty.
func flag(id: StringName) -> Variant:
	return flags.get(id)


## The run counts as a win: it was won, or (endless mode) the final boss died ([constant RunState.TOTAL_WAVES]).
func won() -> bool:
	return bool(flags.get(&"final_boss_down", victory))


## The classes in the party, each once, in slot order.
func classes_played() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in party:
		if id != &"" and id not in out:
			out.append(id)
	return out


## Heroes of [param class_id] the party started with.
func hero_count_of(class_id: StringName) -> int:
	return party.count(class_id)


## True when a hero of [param class_id] was in the party.
func has_class(class_id: StringName) -> bool:
	return class_id in party


## The hero entries whose class is [param class_id] ("" = all).
func heroes_of(class_id: StringName = &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h in heroes:
		if class_id == &"" or StringName(str(h.get("class_id", ""))) == class_id:
			out.append(h)
	return out


## A plain copy for logs and tests.
func to_dict() -> Dictionary:
	var stat_data := {}
	for id in stats:
		stat_data[String(id)] = stats[id]
	var party_data: Array[String] = []
	for id in party:
		party_data.append(String(id))
	var flag_data := {}
	for id in flags:
		flag_data[String(id)] = flags[id]
	return {
		"victory": victory, "abandoned": abandoned, "mode": String(mode), "hardcore": hardcore, "endless": endless,
		"environment": String(environment), "difficulty": String(difficulty), "party": party_data,
		"wave": wave, "waves_cleared": waves_cleared, "stats": stat_data, "flags": flag_data, "heroes": heroes.duplicate(true),
	}


# --- Internals ----------------------------------------------------------------------------------

func _build_flags() -> void:
	var downs := int(stat(&"downs"))
	var heroes_in_party := int(stat(&"party_size"))
	flags = {
		&"victory": victory,
		&"abandoned": abandoned,
		&"hardcore": hardcore,
		&"endless": endless,
		&"solo": heroes_in_party == 1,
		&"full_party": heroes_in_party >= PlayerManager.MAX_PLAYERS,
		&"no_downs": downs == 0,
		&"final_boss_down": victory or int(stat(&"boss_wave_down")) >= RunState.TOTAL_WAVES,
		&"mode": String(mode),
		&"environment": String(environment),
		&"difficulty": String(difficulty),
	}


## The hero entry of [param slot] (see the class doc). Main takes one of a hero who is about to leave the run
## (before the hero is freed), so the report still has the hero: [method collect]'s "departed_heroes".
static func hero_entry(slot: PlayerSlot) -> Dictionary:
	var i := slot.index
	var alive := true
	if RunState.hero_results.has(i):
		alive = bool(RunState.hero_results[i].get("alive", true))
	else:
		var hero := slot.player as Player
		if hero != null and is_instance_valid(hero):
			alive = hero.is_alive()
	var entry := {
		"slot": i,
		"class_id": String(slot.class_data.id) if slot.class_data != null else "",
		"alive": alive,
		"capstones": _capstones_taken(slot),
		"rank5": _rank5_abilities(slot),
		"sets_active": _sets_active(slot),
		"companion": String(slot.companion_id()),
		"equipped": _equipped_summaries(slot),
	}
	entry.merge(_counters(i))
	return entry


## RunState's per-player numbers of the hero in slot [param i] (the number fields of a hero entry).
static func _counters(i: int) -> Dictionary:
	return {
		"damage": float(RunState.damage_by_player.get(i, 0.0)),
		"healing": float(RunState.healing_by_player.get(i, 0.0)),
		"absorbed": float(RunState.absorbed_by_player.get(i, 0.0)),
		"taken": float(RunState.damage_taken_by_player.get(i, 0.0)),
		"kills": int(RunState.kills_by_player.get(i, 0)),
		"bosses": int(RunState.bosses_by_player.get(i, 0)),
		"revives": int(RunState.revives_by_player.get(i, 0)),
		"downs": int(RunState.downs_by_player.get(i, 0)),
		"need_wins": int(RunState.need_wins_by_player.get(i, 0)),
	}


## The sum of the numbers in a RunState per-player dictionary (every hero of the run, one who left included).
static func _total(per_player: Dictionary) -> float:
	var sum := 0.0
	for value: Variant in per_player.values():
		sum += float(value)
	return sum


## Adds the snapshots of the heroes who left mid-run to [param r].heroes (slot order). Their numbers are read again
## from RunState (a totem or a burn of theirs may still score after they left); a slot that is back in the party is
## the party's entry already.
static func _add_departed(r: RunReport, departed: Variant, slots: Array[PlayerSlot]) -> void:
	if not departed is Array or (departed as Array).is_empty():
		return
	var joined: Array[int] = []
	for slot in slots:
		joined.append(slot.index)
	for snapshot: Variant in departed:
		if not snapshot is Dictionary:
			continue
		var entry: Dictionary = (snapshot as Dictionary).duplicate(true)
		var i := int(entry.get("slot", -1))
		if i < 0 or i in joined:
			continue
		entry.merge(_counters(i), true)
		r.heroes.append(entry)
	r.heroes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("slot", 0)) < int(b.get("slot", 0)))


## Capstone talents [param slot]'s hero has taken (0 once the hero is gone).
static func _capstones_taken(slot: PlayerSlot) -> int:
	var hero := slot.player as Player
	if hero == null or not is_instance_valid(hero) or hero.talents == null:
		return 0
	var n := 0
	for id: StringName in hero.talents.ranks:
		var t := Db.get_talent(id)
		if t != null and t.is_capstone() and hero.talents.ranks[id] > 0:
			n += 1
	return n


## Abilities at Rank V on [param slot]'s hero.
static func _rank5_abilities(slot: PlayerSlot) -> int:
	var hero := slot.player as Player
	if hero == null or not is_instance_valid(hero) or hero.abilities == null:
		return 0
	var n := 0
	for id: StringName in hero.abilities.ranks:
		if hero.abilities.knows(id) and hero.abilities.rank_of(id) >= AbilityRanks.MAX_RANK:
			n += 1
	return n


## Set bonuses active on [param slot]'s hero (a 4-piece set counts 2: SetBonuses.active_count).
static func _sets_active(slot: PlayerSlot) -> int:
	var hero := slot.player as Player
	if hero == null or not is_instance_valid(hero) or hero.equipment == null:
		return 0
	return SetBonuses.active_count(hero.equipment)


## What [param slot]'s hero wears now, one summary per equipped item (weapons included).
static func _equipped_summaries(slot: PlayerSlot) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hero := slot.player as Player
	if hero == null or not is_instance_valid(hero) or hero.equipment == null:
		return out
	for item in hero.equipment.equipped_items():
		var look := EquipLook.from_item(item)
		out.append({
			"source_id": String(item.source_id),
			"slot_type": int(item.slot_type),
			"equip_slot": hero.equipment.slot_of(item),
			"armor_type": item.armor_type,
			"rarity": item.rarity,
			"wave": item.wave,
			"item_level": item.item_level,
			"unique": item.unique,
			"set_id": String(item.set_id),
			"look": {} if look == null else {
				"slot": int(look.slot), "armor": look.armor, "tier": look.tier, "rarity": look.rarity,
				"set_id": String(look.set_id), "unique_id": String(look.unique_id)},
		})
	return out


## Legendary (or better) items [param slot]'s hero wears or carries.
static func _legendaries_held(slot: PlayerSlot) -> int:
	var hero := slot.player as Player
	if hero == null or not is_instance_valid(hero) or hero.equipment == null:
		return 0
	var n := 0
	for item in hero.equipment.equipped_items():
		if item.rarity >= Items.Rarity.LEGENDARY:
			n += 1
	for item in hero.equipment.backpack:
		if item.rarity >= Items.Rarity.LEGENDARY:
			n += 1
	return n
