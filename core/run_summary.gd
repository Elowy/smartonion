class_name RunSummary
extends RefCounted
## The data model of the end screen (M6 METER): the per-hero damage meter, the Awards and the
## summary the Game Over / Victory screen and the run card show. Everything that decides something
## is a pure static function of plain dictionaries ([method awards_for], [method build],
## [method rank], the formatters), so it is unit tested without a scene; [method collect] is the one
## function that reads RunState / PlayerManager.
##
## A hero entry (input of [method build]):
##   {"slot": int, "label": "P1", "color": Color (the player colour), "class_id": StringName,
##    "class_name": "Warrior", "class_color": Color, "alive": bool (standing at the end),
##    "best_item": ItemInstance or null, "stats": {stat id: float}}
## The summary [method build] returns:
##   {"victory", "waves_cleared", "total_waves" (0 = endless), "wave", "mode" (RunState.mode_text:
##    "Endless · Hardcore"), "endless", "hardcore", "environment" (display name), "time", "time_text",
##    "kills", "gold_earned", "level", "coop", "heroes": [hero entries + "awards": Array[StringName]],
##    "awards": [{"id", "name", "slot"} in AWARDS order, only the ones somebody won]}

## The meter's stats in display order (the keys of a hero's "stats").
const STAT_IDS: Array[StringName] = [&"damage", &"healing", &"absorbed", &"taken", &"revives",
		&"downs", &"kills", &"bosses"]
const STAT_LABELS := {
	&"damage": "Damage", &"healing": "Healing", &"absorbed": "Absorbed", &"taken": "Taken",
	&"revives": "Revives", &"downs": "Downs", &"kills": "Kills", &"bosses": "Bosses",
}
## One line under each meter title (what the stat counts).
const STAT_HINTS := {
	&"damage": "Damage dealt", &"healing": "Healing done", &"absorbed": "Damage soaked by shields and blocks",
	&"taken": "Damage taken", &"revives": "Allies raised", &"downs": "Times down",
	&"kills": "Enemies slain", &"bosses": "Bosses slain",
}
## Stats that are plain counts (no "k" / "M" shortening).
const COUNT_STATS: Array[StringName] = [&"revives", &"downs", &"kills", &"bosses"]

## Awards, in the order the screen lists them. [code]rule[/code]: &"most" = the highest value wins
## (and it must be above 0), &"least_alive" = the lowest value among the heroes standing at the end.
const AWARDS: Array[Dictionary] = [
	{"id": &"most_damage", "name": "Most Damage", "stat": &"damage", "rule": &"most"},
	{"id": &"most_healing", "name": "Most Healing", "stat": &"healing", "rule": &"most"},
	{"id": &"most_absorbed", "name": "Most Absorbed", "stat": &"absorbed", "rule": &"most"},
	{"id": &"guardian_angel", "name": "Guardian Angel", "stat": &"revives", "rule": &"most"},
	{"id": &"floor_inspector", "name": "Floor Inspector", "stat": &"downs", "rule": &"most"},
	{"id": &"exterminator", "name": "Exterminator", "stat": &"kills", "rule": &"most"},
	{"id": &"untouchable", "name": "Untouchable", "stat": &"taken", "rule": &"least_alive"},
]
## Awards need at least this many heroes (co-op only).
const MIN_HEROES_FOR_AWARDS := 2
## Class colours stay within this luminance range: the Warlock's onion is nearly black, the Rogue's
## nearly white, and the bars carry white outlined text.
const MIN_CLASS_LUMINANCE := 0.28
const MAX_CLASS_LUMINANCE := 0.58


# --- Reading the run --------------------------------------------------------------------------

## The meter stats of slot [param slot_index] from RunState: {stat id: float}.
static func stats_of(slot_index: int) -> Dictionary:
	return {
		&"damage": float(RunState.damage_by_player.get(slot_index, 0.0)),
		&"healing": float(RunState.healing_by_player.get(slot_index, 0.0)),
		&"absorbed": float(RunState.absorbed_by_player.get(slot_index, 0.0)),
		&"taken": float(RunState.damage_taken_by_player.get(slot_index, 0.0)),
		&"revives": float(RunState.revives_by_player.get(slot_index, 0)),
		&"downs": float(RunState.downs_by_player.get(slot_index, 0)),
		&"kills": float(RunState.kills_by_player.get(slot_index, 0)),
		&"bosses": float(RunState.bosses_by_player.get(slot_index, 0)),
	}


## One hero entry for [param slot] (RunState.hero_results when the run recorded it, else what its
## hero looks like right now; a slot without a hero counts as standing).
static func hero_entry(slot: PlayerSlot) -> Dictionary:
	var data := slot.class_data
	var alive := true
	var item: ItemInstance = null
	if RunState.hero_results.has(slot.index):
		var result: Dictionary = RunState.hero_results[slot.index]
		alive = bool(result.get("alive", true))
		item = result.get("best_item") as ItemInstance
	else:
		var hero := slot.player as Player
		if hero != null and is_instance_valid(hero):
			alive = hero.is_alive()
			item = best_item(hero.equipment)
	return {
		"slot": slot.index,
		"label": slot.label(),
		"color": slot.color,
		"class_id": data.id if data != null else &"",
		"class_name": data.display_name if data != null else "?",
		"class_color": class_color(data),
		"alive": alive,
		"best_item": item,
		"stats": stats_of(slot.index),
	}


## The summary of the run that just ended (RunState + the joined slots).
static func collect(p_victory: bool) -> Dictionary:
	var heroes: Array[Dictionary] = []
	for slot in PlayerManager.get_slots():
		heroes.append(hero_entry(slot))
	var run := {
		"victory": p_victory,
		"waves_cleared": GameOverScreen.waves_cleared(p_victory),
		"total_waves": RunState.total_waves(),
		"wave": maxi(RunState.wave, 1),
		"mode": mode_label(RunState.mode, RunState.hardcore),
		"endless": RunState.is_endless(),
		"hardcore": RunState.hardcore,
		"environment": environment_label(RunState.environment),
		"time": RunState.run_time,
		"kills": RunState.kills,
		"gold_earned": RunState.gold_earned,
		"level": RunState.level,
	}
	return build(run, heroes)


## {slot index as String: {stat id: value}} of every joined hero – the SMOKE_RESULT "meter" entry
## (JSON keys are strings). Damage, healing, absorbed and taken are rounded to 0.1, the counts are
## whole numbers.
static func meter_dict() -> Dictionary:
	var out := {}
	for slot in PlayerManager.get_slots():
		var stats := stats_of(slot.index)
		var line := {}
		for id in STAT_IDS:
			line[String(id)] = int(stats[id]) if id in COUNT_STATS else snappedf(stats[id], 0.1)
		line["class"] = String(slot.class_data.id) if slot.class_data != null else ""
		out[str(slot.index)] = line
	return out


## {source id: {wave as String: damage}} – the SMOKE_RESULT "taken_by_source" entry, the heroes'
## damage taken (RunState.damage_taken_by_source) by what dealt it, rounded to 0.1. Balance
## diagnostics: it tells which enemy type is eating the party.
static func source_damage_dict() -> Dictionary:
	var out := {}
	for source in RunState.damage_taken_by_source:
		var per_wave: Dictionary = RunState.damage_taken_by_source[source]
		var line := {}
		for w in per_wave:
			line[str(w)] = snappedf(float(per_wave[w]), 0.1)
		out[String(source)] = line
	return out


## {slot index as String: damage} – the SMOKE_RESULT "boss_damage" entry: what each hero dealt to bosses
## (RunState.boss_damage_by_player), rounded to 0.1. Balance diagnostics.
static func boss_damage_dict() -> Dictionary:
	var out := {}
	for slot_index in RunState.boss_damage_by_player:
		out[str(slot_index)] = snappedf(float(RunState.boss_damage_by_player[slot_index]), 0.1)
	return out


## {slot index as String: ratio} – the SMOKE_RESULT "shield_peak" entry: the highest total absorb shield each
## hero carried, as a multiple of its Max HP (RunState.shield_peak_by_player), rounded to 0.01.
static func shield_peak_dict() -> Dictionary:
	var out := {}
	for slot_index in RunState.shield_peak_by_player:
		out[str(slot_index)] = snappedf(float(RunState.shield_peak_by_player[slot_index]), 0.01)
	return out


# --- Pure model -------------------------------------------------------------------------------

## Fills in the derived fields of [param run] (the run totals: victory, waves_cleared,
## total_waves, wave, mode, time, kills, gold_earned, level) and the [param heroes]' awards.
static func build(run: Dictionary, heroes: Array) -> Dictionary:
	var out := run.duplicate()
	var sorted := _by_slot(heroes)
	var won := awards_for(sorted)
	var list: Array[Dictionary] = []
	for h: Dictionary in sorted:
		var entry := h.duplicate()
		var mine: Array[StringName] = []
		mine.assign(won.get(int(h["slot"]), []))
		entry["awards"] = mine
		list.append(entry)
	out["heroes"] = list
	out["coop"] = list.size() >= MIN_HEROES_FOR_AWARDS
	out["time_text"] = format_time(float(out.get("time", 0.0)))
	var winners: Array[Dictionary] = []
	for award in AWARDS:
		for slot_index: int in won:
			if award["id"] in won[slot_index]:
				winners.append({"id": award["id"], "name": award["name"], "slot": slot_index})
	out["awards"] = winners
	return out


## Who wins which award: {slot index: Array[StringName] of award ids (AWARDS order)}. Co-op only
## (fewer than MIN_HEROES_FOR_AWARDS heroes: nothing). The best value wins; a tie goes to the lower
## slot; a "most" award needs a shown value above 0 ([method shown_value]); Untouchable (the least damage taken) is only for the
## heroes standing at the end (nobody left standing: nobody wins it).
static func awards_for(heroes: Array) -> Dictionary:
	var out := {}
	if heroes.size() < MIN_HEROES_FOR_AWARDS:
		return out
	var sorted := _by_slot(heroes)
	for award in AWARDS:
		var stat: StringName = award["stat"]
		var least: bool = award["rule"] == &"least_alive"
		var winner := -1
		var best := 0.0
		for h: Dictionary in sorted:
			if least and not bool(h.get("alive", true)):
				continue
			var value := float((h.get("stats", {}) as Dictionary).get(stat, 0.0))
			if not least and shown_value(value) <= 0.0:  # a 0.4 reads "0": no award for that
				continue
			var better := winner < 0 or (value < best if least else value > best)
			if better:  # strict: a tie keeps the lower slot
				winner = int(h["slot"])
				best = value
		if winner >= 0:
			var ids: Array = out.get(winner, [])
			ids.append(award["id"])
			out[winner] = ids
	return out


## [param heroes] ordered by [param stat_id], the highest first (ties: the lower slot first).
static func rank(heroes: Array, stat_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_by_slot(heroes))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var va := float((a.get("stats", {}) as Dictionary).get(stat_id, 0.0))
		var vb := float((b.get("stats", {}) as Dictionary).get(stat_id, 0.0))
		if not is_equal_approx(va, vb):
			return va > vb
		return int(a["slot"]) < int(b["slot"]))
	return out


static func award_name(award_id: StringName) -> String:
	for award in AWARDS:
		if award["id"] == award_id:
			return award["name"]
	return ""


## The best item of [param equipment] (worn first, then the backpack): the highest rarity, then
## item level, then shop price; the earlier one wins a tie. Null without items.
static func best_item(equipment: Equipment) -> ItemInstance:
	if equipment == null:
		return null
	var pool: Array[ItemInstance] = equipment.equipped_items()
	pool.append_array(equipment.backpack)
	var best: ItemInstance = null
	for item in pool:
		if item == null:
			continue
		if best == null or _item_key(item) > _item_key(best):
			best = item
	return best


## The colour a class's bars and card use: its onion colour, lightened when too dark and darkened
## when too bright to read the text on it (luminance within MIN_ / MAX_CLASS_LUMINANCE).
static func class_color(data: ClassData) -> Color:
	if data == null:
		return Color(0.6, 0.6, 0.65)
	var c := data.onion_color
	c.a = 1.0
	var lum := c.get_luminance()
	if lum < MIN_CLASS_LUMINANCE:
		c = c.lightened((MIN_CLASS_LUMINANCE - lum) / (1.0 - lum))  # towards white, exactly to the floor
	elif lum > MAX_CLASS_LUMINANCE:
		c = c.darkened(1.0 - MAX_CLASS_LUMINANCE / lum)  # scaled down, exactly to the ceiling
	return c


## "Normal" / "Endless" / "Normal · Hardcore" ... for the end screen and the card (RunState.mode_text).
static func mode_label(mode: StringName = &"normal", hardcore: bool = false) -> String:
	return RunState.mode_text(mode, hardcore)


## The display name of environment [param id] ("Forest Ruin"); an unknown id is capitalised as is.
static func environment_label(id: StringName) -> String:
	var env := Db.get_environment(id)
	if env != null and env.display_name != "":
		return env.display_name
	return String(id).capitalize()


# --- Formatting -------------------------------------------------------------------------------

## A meter value: counts as whole numbers, amounts shortened from 10,000 on ("12.3k", "1.25M").
static func format_value(stat_id: StringName, value: float) -> String:
	if stat_id in COUNT_STATS:
		return UiTheme.format_int(int(roundf(value)))
	return format_amount(value)


static func format_amount(value: float) -> String:
	if value >= 10000.0:
		var thousands := "%.1f" % (value / 1000.0)
		# 999,960 rounds to "1000.0k": from there on it is a million.
		if value < 1000000.0 and thousands != "1000.0":
			return thousands + "k"
		return "%.2fM" % (value / 1000000.0)
	return UiTheme.format_int(int(roundf(value)))


## What the meter shows for [param value] as a number: amounts and counts are whole numbers (from
## 10,000 on they are shortened, but never below 10,000), so anything under 0.5 reads "0". The awards
## ("a most award needs a value above 0") and the dimmed bars go by this, not by the raw value.
static func shown_value(value: float) -> float:
	return roundf(value)


## 754 s -> "12:34", 3725 s -> "1:02:05".
static func format_time(seconds: float) -> String:
	var s := maxi(0, int(roundf(seconds)))
	var minutes := floori(s / 60.0)
	if minutes >= 60:
		return "%d:%02d:%02d" % [floori(minutes / 60.0), minutes % 60, s % 60]
	return "%d:%02d" % [minutes, s % 60]


# --- Helpers ----------------------------------------------------------------------------------

static func _by_slot(heroes: Array) -> Array:
	var out := heroes.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["slot"]) < int(b["slot"]))
	return out


## Sort key of [method best_item]: rarity, item level, price.
static func _item_key(item: ItemInstance) -> int:
	return item.rarity * 100000000 + item.item_level * 10000 + mini(item.buy_price, 9999)
