class_name Shrines
extends RefCounted
## Shrines (GDD 16.1, M6b SHRINES): the rules around [ShrineData] – the 5% roll at a break, the card texts, the
## bots' vote, what an accepted shrine does and how the effects of a timed one run over the next waves. Nothing
## here is a node; the vote itself is [ShrineVote], the card [ShrineScreen] (the Intermission's SHRINE phase).
##
## Life of a shrine (the break after wave N):
##   Main._roll_shrine      -> [method end_wave] (wave N counted against every running shrine, expired ones go),
##                             then [method roll]: 5% per break (--shrine-chance), from RunState.shrine_rng
##                             (draw order: the chance, then the pick), RunState.pending_shrine = the id.
##   Intermission SHRINE    -> the whole party votes (ShrineVote: all must accept, 15 s, then declined).
##   accepted               -> [method accept]: a TIMED shrine joins RunState.shrine_effects with its waves
##                             left; an INSTANT one acts at once (a free Epic item per hero, a share of the
##                             purse lost, a gamble on the purse).
##   Main.start_wave        -> [method begin_wave]: the effects are live until [method end_wave] – the multipliers
##                             below are 1 outside a wave, the heroes get the PlayerBonuses source [constant SOURCE].
## The multipliers are read where things are made: [method enemy_hp_mult] / [method enemy_damage_mult] /
## [method enemy_speed_mult] by Enemy.setup (and Boss.create for the HP), [method gold_find_pct] and
## RunState.scale_xp by the pickups.
## Several running shrines multiply; a timed shrine that already runs is not offered again.

## PlayerBonuses source of the heroes' shrine effects.
const SOURCE := &"shrine"
## The chance of a shrine at a break (GDD 16.1: 5%); --shrine-chance replaces it.
const CHANCE := 0.05
## The chance a break has without --shrine-chance. The test runner sets it to 0 (through the script object, like
## the leaderboard switch), so a Main flow test never meets a shrine it did not ask for; the game never changes it.
static var base_chance := CHANCE
## The spend kind of the purse a shrine takes (RunState.try_spend_for).
const SPEND_KIND := &"shrine"


# --- The roll ----------------------------------------------------------------------------------

## Every shrine of the pool (Db.shrines, unlocked), in pool order.
static func pool() -> Array[ShrineData]:
	var out: Array[ShrineData] = []
	for id in Db.shrine_ids:
		if Db.is_unlocked(id):
			out.append(Db.shrines[id])
	return out


## The pool without the timed shrines that run right now (an instant shrine is always possible).
static func available() -> Array[ShrineData]:
	var out: Array[ShrineData] = []
	for data in pool():
		if data.is_timed() and RunState.has_shrine_effect(data.id):
			continue
		out.append(data)
	return out


## The chance of a shrine at a break: --shrine-chance when given, else [member base_chance] (5%).
static func chance() -> float:
	var override := RunState.shrine_chance_override
	return clampf(override, 0.0, 1.0) if override >= 0.0 else base_chance


## The roll of one break: the id of the shrine on offer ("" = none). Draws from RunState.shrine_rng only: first the
## chance (no draw when the chance is 0 or 1), then, on a hit, the pick among [method available].
static func roll() -> StringName:
	var p := chance()
	if p <= 0.0:
		return &""
	if p < 1.0 and RunState.shrine_rng.randf() >= p:
		return &""
	var choices := available()
	if choices.is_empty():
		return &""
	return choices[RunState.shrine_rng.randi_range(0, choices.size() - 1)].id


## What a bot votes: Accept for the shrines the data marks ([member ShrineData.bot_accepts]).
static func bot_accepts(data: ShrineData) -> bool:
	return data != null and data.bot_accepts


# --- Texts -------------------------------------------------------------------------------------

## The card's boon lines ("+30% gold from pickups").
static func boon_lines(data: ShrineData) -> Array[String]:
	return _lines(data, true)


## The card's bane lines ("Enemies deal +20% damage").
static func bane_lines(data: ShrineData) -> Array[String]:
	return _lines(data, false)


## "Lasts 3 waves" / "Takes effect at once".
static func duration_text(data: ShrineData) -> String:
	if data == null or data.is_instant():
		return "Takes effect at once"
	return "Lasts the next %d wave%s" % [data.waves, "" if data.waves == 1 else "s"]


## One line for the wave banner and the logs, the boons then the banes in the short card wording:
## "Shrine of Greed: +30% gold, enemies +20% damage · 2 waves left".
static func effect_text(id: StringName, waves_left: int) -> String:
	var data := Db.get_shrine(id)
	var name := data.display_name if data != null else String(id)
	var parts: Array[String] = _lines(data, true, true)
	parts.append_array(_lines(data, false, true))
	var summary := ""
	if not parts.is_empty():
		summary = ": " + ", ".join(PackedStringArray(parts))
	return "%s%s · %d wave%s left" % [name, summary, waves_left, "" if waves_left == 1 else "s"]


## The wave banner's sub-lines: one [method effect_text] per running shrine (empty while none runs).
static func banner_lines() -> Array[String]:
	var out: Array[String] = []
	for e in RunState.shrine_effects:
		out.append(effect_text(StringName(e.get("id", &"")), int(e.get("waves_left", 0))))
	return out


## The running shrines as one log line ("greed 3, haste 1"; "none").
static func effects_log() -> String:
	if RunState.shrine_effects.is_empty():
		return "none"
	var parts: Array[String] = []
	for e in RunState.shrine_effects:
		parts.append("%s %d" % [e.get("id", &""), int(e.get("waves_left", 0))])
	return ", ".join(parts)


## The lines of one side of the card: [param good] = the boons, else the banes. Every number comes from the data.
## [param short]: the one-line wording of [method effect_text] ("+30% gold", "enemies +20% damage").
static func _lines(data: ShrineData, good: bool, short: bool = false) -> Array[String]:
	var out: Array[String] = []
	if data == null:
		return out
	var from_pickups := "" if short else " from pickups"
	# [text, good] pairs in card order.
	var all: Array = []
	if not is_zero_approx(data.gold_pct):
		all.append(["%s gold%s" % [_pct(data.gold_pct), from_pickups], data.gold_pct > 0.0])
	if not is_zero_approx(data.xp_pct):
		all.append(["%s XP%s" % [_pct(data.xp_pct), from_pickups], data.xp_pct > 0.0])
	for e in data.hero_effects:
		all.append_array(_hero_lines(e))
	if not is_zero_approx(data.enemy_damage_pct):
		all.append([("enemies %s damage" if short else "Enemies deal %s damage") % _pct(data.enemy_damage_pct),
				data.enemy_damage_pct < 0.0])
	if not is_zero_approx(data.enemy_hp_pct):
		all.append([("enemies %s HP" if short else "Enemies have %s HP") % _pct(data.enemy_hp_pct), data.enemy_hp_pct < 0.0])
	if not is_zero_approx(data.enemy_speed_pct):
		# The sign is the direction ("15% faster" / "15% slower"), never a second sign.
		var speed := data.enemy_speed_pct
		var move := "%s%% %s" % [_num(absf(speed)), "faster" if speed > 0.0 else "slower"]
		all.append([("enemies %s" if short else "Enemies move %s") % move, speed < 0.0])
	if data.give_epic:
		all.append(["Every hero gets a free Epic item", true])
	if data.purse_loss_pct > 0.0:
		all.append(["The party loses %s of the purse" % _pct(data.purse_loss_pct, false), false])
	if data.gamble_chance > 0.0:
		var chance_text := "%d%%" % roundi(data.gamble_chance * 100.0)
		var lose_text := "%d%%" % roundi((1.0 - data.gamble_chance) * 100.0)
		all.append(["%s chance: the purse x%s" % [chance_text, _num(1.0 + data.gamble_win_pct / 100.0)], true])
		all.append(["%s chance: the purse x%s" % [lose_text, _num(1.0 - data.gamble_lose_pct / 100.0)], false])
	for pair: Array in all:
		if bool(pair[1]) == good:
			out.append(String(pair[0]))
	return out


## The lines of one hero effect entry as [text, good] pairs ("+15% haste", "-20% max HP").
static func _hero_lines(e: Dictionary) -> Array:
	var out: Array = []
	match String(e.get("kind", "")):
		"damage":
			var pct := float(e.get("pct", 0.0))
			out.append(["%s damage" % _pct(pct), pct > 0.0])
		"damage_taken":
			var pct := float(e.get("pct", 0.0))
			out.append(["%s damage taken" % _pct(pct), pct < 0.0])
		"stats":
			var pct_stats: Dictionary = e.get("stats_pct", {})
			for key: Variant in pct_stats:
				var name := "max HP" if String(key) == "max_hp" else Stats.display_name(StringName(key)).to_lower()
				var v := float(pct_stats[key])
				out.append(["%s %s" % [_pct(v), name], v > 0.0])
			var stats: Dictionary = e.get("stats", {})
			for key: Variant in stats:
				var stat := StringName(key)
				var v := float(stats[stat])
				out.append(["%s %s" % [Stats.format_value(stat, v), Stats.display_name(stat).to_lower()], v > 0.0])
	return out


## "+30%" / "-20%" (whole numbers without decimals); [param signed] = false: "25%".
static func _pct(value: float, signed: bool = true) -> String:
	return ("+" if signed and value >= 0.0 else "") + _num(value) + "%"


static func _num(value: float) -> String:
	return str(int(roundf(value))) if is_equal_approx(value, roundf(value)) else "%.1f" % value


# --- Running effects ----------------------------------------------------------------------------

## A wave starts (Main.start_wave, after the heroes' begin_wave): the running shrines are live and every hero gets
## their effects (PlayerBonuses source [constant SOURCE]).
static func begin_wave(players: Array) -> void:
	RunState.shrine_effects_live = true
	for p: Variant in players:
		apply_to_hero(p as Player)


## A wave is over (the break path, before the shrine roll): the effects stop, the heroes lose them, every running
## shrine has one wave less. Returns the ids that expired.
static func end_wave(players: Array) -> Array[StringName]:
	RunState.shrine_effects_live = false
	for p: Variant in players:
		clear_hero(p as Player)
	return RunState.tick_shrine_effects()


## Puts the heroes' side of the running shrines into [param player]'s bonuses (a bigger Max HP is filled up, a
## smaller one clamps the HP by itself).
static func apply_to_hero(player: Player) -> void:
	if player == null or not is_instance_valid(player) or player.bonuses == null:
		return
	var entries: Array[Dictionary] = []
	if RunState.shrine_effects_live:
		for e in RunState.shrine_effects:
			var data := Db.get_shrine(StringName(e.get("id", &"")))
			if data != null and not data.hero_effects.is_empty():
				entries.append_array(Consumables.resolve_effects(_shim(data), player))
	if entries.is_empty() and player.bonuses.effects_of(SOURCE).is_empty():
		return
	var before := player.max_hp()
	player.bonuses.set_effects(SOURCE, entries)
	var gain := player.max_hp() - before
	if gain > 0.0:
		player.fill_hp(gain)


## Takes the shrine effects off [param player].
static func clear_hero(player: Player) -> void:
	if player == null or not is_instance_valid(player) or player.bonuses == null:
		return
	if player.bonuses.effects_of(SOURCE).is_empty():
		return
	player.bonuses.set_effects(SOURCE, [] as Array[Dictionary])


## The hero-effect entries of [param data] as a ConsumableData: the consumables' resolver turns "stats_pct" into
## plain stats against the hero's current numbers. (Not cached: a static Resource would still be alive at exit.)
static func _shim(data: ShrineData) -> ConsumableData:
	var shim := ConsumableData.new()
	shim.id = data.id
	shim.display_name = data.display_name
	shim.effects = data.hero_effects
	return shim


# --- Multipliers (1 outside a wave) -------------------------------------------------------------

## The product of (1 + pct / 100) of one ShrineData percent field over the running shrines.
static func _product(field: StringName) -> float:
	if not RunState.shrine_effects_live or RunState.shrine_effects.is_empty():
		return 1.0
	var m := 1.0
	for e in RunState.shrine_effects:
		var data := Db.get_shrine(StringName(e.get("id", &"")))
		if data != null:
			m *= 1.0 + float(data.get(field)) / 100.0
	return maxf(0.0, m)


## Gold of a pickup.
static func gold_mult() -> float:
	return _product(&"gold_pct")


## XP of a pickup (RunState.scale_xp).
static func xp_mult() -> float:
	return _product(&"xp_pct")


## Contact and projectile damage of an enemy that spawns now.
static func enemy_damage_mult() -> float:
	return _product(&"enemy_damage_pct")


## Max HP of an enemy that spawns now.
static func enemy_hp_mult() -> float:
	return _product(&"enemy_hp_pct")


## Walking speed of an enemy that spawns now.
static func enemy_speed_mult() -> float:
	return _product(&"enemy_speed_pct")


## [param find_pct] (the collector's Gold Find) with the shrines' gold bonus folded in: the percent that
## RunState.add_gold_for turns into the same gold as "pickup x Gold Find x shrine multiplier". Unchanged
## (not even re-computed) while no shrine boosts gold.
static func gold_find_pct(find_pct: float) -> float:
	var m := gold_mult()
	if is_equal_approx(m, 1.0):
		return find_pct
	return ((1.0 + find_pct / 100.0) * m - 1.0) * 100.0


# --- Accepting -----------------------------------------------------------------------------------

## The party accepted [param data]: a timed shrine starts running, an instant one acts now (slots with a hero
## only). Returns {"lines": Array[String]} – what happened, for the card's result line. Instant effects draw
## from RunState.shrine_rng (the Gambler's coin and the Epic items), never from RunState.rng.
static func accept(data: ShrineData, slots: Array[PlayerSlot]) -> Dictionary:
	var lines: Array[String] = []
	if data == null:
		return {"lines": lines}
	if data.is_timed():
		RunState.add_shrine_effect(data.id, data.waves)
		lines.append("Starts with the next wave (%d wave%s)." % [data.waves, "" if data.waves == 1 else "s"])
	if data.purse_loss_pct > 0.0:
		lines.append(_take_from_purse(data, data.purse_loss_pct))
	if data.gamble_chance > 0.0:
		var win := RunState.shrine_rng.randf() < data.gamble_chance
		if win:
			var won := floori(RunState.gold * data.gamble_win_pct / 100.0)
			if won > 0:
				RunState.add_gold_logged(won, -1, data.display_name)
				lines.append("The dice favour you: +%s gold!" % UiTheme.format_int(won))
			else:
				lines.append("The dice favour you, but the purse is %s." % _small_purse_text())
		else:
			lines.append(_take_from_purse(data, data.gamble_lose_pct, "The dice turn on you: "))
	if data.give_epic:
		lines.append_array(_give_epics(slots))
	return {"lines": lines}


## The shrine takes [param pct] of the purse (rounded down; spend kind [constant SPEND_KIND]). One sentence: behind
## the Gambler's [param prefix] the clause starts in lower case ("The dice turn on you: the purse is empty.").
static func _take_from_purse(data: ShrineData, pct: float, prefix: String = "") -> String:
	var amount := floori(RunState.gold * pct / 100.0)
	if amount > 0 and RunState.try_spend_for(amount, -1, SPEND_KIND, data.display_name):
		var taken := UiTheme.format_int(amount)
		if prefix != "":
			return prefix + "the shrine takes %s gold." % taken
		return "The shrine takes %s gold." % taken
	var empty := RunState.gold <= 0
	if prefix != "":
		return prefix + ("the purse is empty." if empty else "the purse is too small to take from.")
	return "The purse is empty: the shrine takes nothing." if empty else "The purse is too small: the shrine takes nothing."


## What a share of the purse is when it rounds to nothing: "empty" with no gold at all, else "too small to gain from"
## (the end of "The dice favour you, but the purse is ...").
static func _small_purse_text() -> String:
	return "empty" if RunState.gold <= 0 else "too small to gain from"


## A free Epic item for every hero (usable by their class) into the backpack; a full backpack sells it. The sales
## share one result line ("Backpacks full: 3 items sold for 201 gold"), so four full backpacks never run behind the
## voter chips.
static func _give_epics(slots: Array[PlayerSlot]) -> Array[String]:
	var lines: Array[String] = []
	var sorted := slots.duplicate()
	sorted.sort_custom(func(a: PlayerSlot, b: PlayerSlot) -> bool: return a.index < b.index)
	var sold := 0
	var sold_gold := 0
	for s: PlayerSlot in sorted:
		var hero := s.player as Player
		if hero == null or not is_instance_valid(hero) or hero.equipment == null:
			continue
		var item := ItemGenerator.generate(ItemGenerator.Source.LOOT, maxi(1, RunState.wave), RunState.shrine_rng, {
			&"usable_by": s.class_data,
			&"class_data": s.class_data,
			&"rarity": Items.Rarity.EPIC,
		})
		if item == null:
			continue
		if hero.equipment.add_to_backpack(item):
			lines.append("%s gets [%s]." % [s.label(), item.display_name])
		else:
			var gold := item.greed_value()
			RunState.add_gold_logged(gold, s.index, "Shrine of Fortune: %s" % item.display_name)
			sold += 1
			sold_gold += gold
	if sold > 0:
		lines.append("Backpacks full: %d item%s sold for %s gold." % [sold, "" if sold == 1 else "s", UiTheme.format_int(sold_gold)])
	return lines
