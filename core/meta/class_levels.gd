class_name ClassLevels
extends RefCounted
## Class XP, Class Levels and their reward path (M9 LEVELS, GDD 17.1 / 17.2, design 1 and 2). All numbers are in
## data: the curve, the XP / Seeds formulas and the reward list are the [ClassLevelTable] (data/meta/class_levels.tres),
## what is special about a class (its locked abilities, capstone order, alternative weapon, cosmetics) is its
## [ClassPathData]. This class is only the maths and the profile writes; it holds no state.
##
## A finished run: [method on_run_xp] and [method on_run_seeds] are Meta run-end listeners ([method register]). Every
## class that played earns Class XP (two heroes of one class ADD: each hero is one share of the run's team terms plus
## its own kills), the profile stores total XP and the level reached, a level reached pays its Seeds gift and unlocks its
## rewards ([method grant_level]): the learnable abilities and capstone trees through the profile's unlocks (the gates in
## data/unlocks/ hold them back until then), the Heirloom gift, cosmetics and the title as collectibles; the rest of the
## rewards are derived from the level when asked ([method seasoning_slots], [method heirloom_slots],
## [method raw_power] ...). The dev profile of the automated runs records nothing and uses none of it.
##
## The result of the run's record gets "class_xp" (one dictionary per class played, see [method on_run_xp]) and "seeds"
## (see [method on_run_seeds]) for the end screen.

const LISTENER_XP := &"class_xp"
const LISTENER_SEEDS := &"seeds"

## The XP multiplier of a difficulty tier, filled by the Difficulty package: [code]func(difficulty: StringName) -> float[/code].
## Unset (or returning <= 0) = 1.0. Read once per class per run.
static var xp_mult_hook: Callable
## The Seeds multiplier of a difficulty tier ([member xp_mult_hook]'s twin).
static var seeds_mult_hook: Callable

static var _fallback: ClassLevelTable


## Registers the two run-end listeners on [param meta] (the Meta autoload) at the default priority, XP first.
static func register(meta: Node) -> void:
	meta.add_run_listener(LISTENER_XP, on_run_xp)
	meta.add_run_listener(LISTENER_SEEDS, on_run_seeds)


# --- The table ----------------------------------------------------------------------------------

## The table in use ([member Db.class_levels]; an empty one – level 1 for ever, no rewards – if the data is missing).
static func table() -> ClassLevelTable:
	if Db.class_levels != null:
		return Db.class_levels
	if _fallback == null:
		_fallback = ClassLevelTable.new()
	return _fallback


static func max_level() -> int:
	return clampi(table().max_level, Profile.START_CLASS_LEVEL, Profile.MAX_CLASS_LEVEL)


## XP from [param level] to the next one (0 at the top level).
static func xp_to_next(level: int) -> int:
	var costs := table().xp_to_next
	if level < 1 or level >= max_level() or level > costs.size():
		return 0
	return costs[level - 1]


## Total XP needed to REACH [param level] (level 1 = 0).
static func xp_for_level(level: int) -> int:
	var costs := table().xp_to_next
	var total := 0
	for l in range(1, mini(level, max_level())):
		if l <= costs.size():
			total += costs[l - 1]
	return total


## The level [param xp] total XP reaches (1 .. max level).
static func level_for_xp(xp: int) -> int:
	var level := 1
	while level < max_level() and xp >= xp_for_level(level + 1):
		level += 1
	return level


## The XP bar of a class: {"level", "max" (top level), "into" (XP gathered towards the next level), "needed" (this
## level's cost), "fraction" (0..1, 1 at the top), "total"}. [param level] is the level STORED in the profile (it may be
## higher than the XP says: a max profile).
static func progress(xp: int, level: int = -1) -> Dictionary:
	var lv := level_for_xp(xp) if level < 0 else clampi(level, 1, max_level())
	var needed := xp_to_next(lv)
	var into := clampi(xp - xp_for_level(lv), 0, needed) if needed > 0 else 0
	return {"level": lv, "max": lv >= max_level(), "into": into, "needed": needed,
			"fraction": 1.0 if needed <= 0 else float(into) / float(needed), "total": xp}


## Seeds gift of reaching [param level]: gift_base + level, doubled on a level that gives nothing else.
static func level_gift(level: int) -> int:
	if level < 2 or level > max_level():
		return 0
	var t := table()
	var gift := t.level_gift_base + level
	if _rewards_at_level(level).is_empty():
		gift *= t.empty_level_gift_mult
	return gift


# --- Run rewards: Class XP ----------------------------------------------------------------------

## True when the run ended with the final boss dead: a victory, or the wave-25 boss of an Endless run (the report's
## "final_boss_down" flag when a package sets it, else derived).
static func final_boss_down(report: RunReport) -> bool:
	var flag: Variant = report.flag(&"final_boss_down")
	if flag != null:
		return bool(flag)
	return report.victory or (report.endless and report.waves_cleared >= RunState.TOTAL_WAVES)


## The run's team share of Class XP – what ONE hero of the party earns before its own kills: the cleared waves, the elites
## (capped), the bosses and the final boss.
static func team_xp(report: RunReport) -> float:
	var t := table()
	var xp := 0.0
	for w in range(1, report.waves_cleared + 1):
		xp += t.wave_xp_base + t.wave_xp_per_wave * mini(w, t.wave_xp_wave_cap)
	xp += minf(t.elite_xp_cap, t.elite_xp * report.stat(&"elites_killed"))
	xp += t.boss_xp * report.stat(&"bosses_killed")
	if final_boss_down(report):
		xp += t.final_boss_xp
	return xp


## The XP multiplier of the run's difficulty tier ([member xp_mult_hook]; 1.0 by default).
static func xp_multiplier(report: RunReport) -> float:
	return _hook_mult(xp_mult_hook, report.difficulty)


static func seeds_multiplier(report: RunReport) -> float:
	return _hook_mult(seeds_mult_hook, report.difficulty)


static func _hook_mult(hook: Callable, difficulty: StringName) -> float:
	if hook.is_valid():
		var v: Variant = hook.call(difficulty)
		if typeof(v) in [TYPE_INT, TYPE_FLOAT] and float(v) > 0.0:
			return float(v)
	return 1.0


## The catch-up multiplier of a class at [param level] when the profile's best class stands at [param best_level]: a class
## far behind it earns more until it is level catchup_below_level.
static func catchup_multiplier(level: int, best_level: int) -> float:
	var t := table()
	if level <= best_level - t.catchup_gap and level < t.catchup_below_level:
		return t.catchup_mult
	return 1.0


## The highest Class Level of any class in [param profile].
static func best_level(profile: Profile) -> int:
	var best := Profile.START_CLASS_LEVEL
	for id in profile.classes:
		best = maxi(best, profile.class_level(id))
	return best


## The profile counter that remembers the first final-boss kill of a class on a tier.
static func first_win_counter(class_id: StringName, tier: StringName) -> StringName:
	return StringName("first_win:%s:%s" % [tier, class_id])


## What [param report] earns each class that played, without changing anything (the XP maths of the design): one
## dictionary per class in party order: {"class_id", "heroes" (shares), "kills" (of its heroes), "raw" (before the
## multipliers), "multiplier" (difficulty), "catchup" (multiplier), "first_win_bonus", "xp" (the whole gain)}.
## [param profile] gives the levels (catch-up) and the first-win record.
static func run_xp(report: RunReport, profile: Profile) -> Array[Dictionary]:
	var t := table()
	var out: Array[Dictionary] = []
	var team := team_xp(report)
	var mult := xp_multiplier(report)
	var best := best_level(profile)
	var won := final_boss_down(report)
	for class_id in report.classes_played():
		var shares := report.hero_count_of(class_id)
		var kills := 0
		for h in report.heroes_of(class_id):
			kills += int(h.get("kills", 0))
		var raw := team * shares + t.kill_xp * kills
		var catchup := catchup_multiplier(profile.class_level(class_id), best)
		var bonus := 0
		if won and profile.counter(first_win_counter(class_id, report.difficulty)) == 0:
			bonus = int(t.first_win_bonus.get(report.difficulty, 0))
		out.append({
			"class_id": class_id, "heroes": shares, "kills": kills, "raw": raw, "multiplier": mult, "catchup": catchup,
			"first_win_bonus": bonus, "xp": roundi(raw * mult * catchup) + bonus,
		})
	return out


## Adds [param amount] XP to [param class_id], raises the stored level to what the XP reaches, and pays what the new
## levels give: the Seeds gift and the unlocks ([method grant_level]). Returns {"class_id", "xp_before", "xp_after",
## "xp_gained", "level_before", "level_after", "rewards" (the described rewards of the new levels, in order), "gift_seeds"}.
static func award_xp(profile: Profile, class_id: StringName, amount: int) -> Dictionary:
	var xp_before := profile.class_xp(class_id)
	var level_before := profile.class_level(class_id)
	var gained := maxi(amount, 0)
	var xp_after := xp_before + gained
	var level_after := maxi(level_before, level_for_xp(xp_after))
	profile.set_class_progress(class_id, xp_after, level_after)
	var rewards: Array[Dictionary] = []
	var gift := 0
	for level in range(level_before + 1, level_after + 1):
		gift += level_gift(level)
		rewards.append_array(grant_level(profile, class_id, level))
	if gift > 0:
		profile.earn_seeds(gift)
	return {"class_id": class_id, "xp_before": xp_before, "xp_after": xp_after, "xp_gained": gained,
			"level_before": level_before, "level_after": level_after, "rewards": rewards, "gift_seeds": gift}


## The run-end listener of Class XP: every class in the party earns [method run_xp]'s XP. Adds
## [code]result["class_xp"][/code] (one dictionary per class in party order: [method run_xp]'s plus [method award_xp]'s
## keys, the XP already rounded) and [code]result["level_seeds"][/code] (the level gifts paid).
static func on_run_xp(report: RunReport, profile: Profile, result: Dictionary) -> void:
	var entries: Array[Dictionary] = []
	var gifts := 0
	for run in run_xp(report, profile):
		var class_id: StringName = run["class_id"]
		var award := award_xp(profile, class_id, int(run["xp"]))
		if int(run["first_win_bonus"]) > 0:
			profile.add_counter(first_win_counter(class_id, report.difficulty), 1)
		var entry: Dictionary = run.duplicate()
		entry.merge(award, true)
		entries.append(entry)
		gifts += int(award["gift_seeds"])
	result["class_xp"] = entries
	result["level_seeds"] = gifts


# --- Run rewards: Seeds -------------------------------------------------------------------------

## The Seeds a run pays (once per run, to the wallet; the level gifts come on top): 1.5 per cleared wave, 12 per boss,
## 40 for the final boss and one per 400 team kills, times the difficulty's Seeds multiplier and +10% per extra player,
## at most seeds_cap.
static func run_seeds(report: RunReport) -> int:
	var t := table()
	var raw := t.seeds_per_wave * report.waves_cleared + t.seeds_per_boss * report.stat(&"bosses_killed")
	if final_boss_down(report):
		raw += t.seeds_final_boss
	if t.seeds_kills_per > 0:
		raw += floorf(report.stat(&"kills") / float(t.seeds_kills_per))
	var players := maxi(1, int(report.stat(&"party_size")))
	return mini(t.seeds_cap, roundi(raw * seeds_multiplier(report) * (1.0 + t.seeds_party_bonus * (players - 1))))


## The run-end listener of the Seeds: pays [method run_seeds] to the profile and adds [code]result["seeds"][/code]:
## {"run": Seeds of the run, "gifts": the level gifts [method on_run_xp] paid, "total": both, "wallet": the wallet now}.
static func on_run_seeds(report: RunReport, profile: Profile, result: Dictionary) -> void:
	var earned := run_seeds(report)
	profile.earn_seeds(earned)
	var gifts := int(result.get("level_seeds", 0))
	result["seeds"] = {"run": earned, "gifts": gifts, "total": earned + gifts, "wallet": profile.seeds}
	if earned + gifts > 0 and Meta.profile == profile:
		Meta.seeds_changed.emit(profile.seeds, earned + gifts)


# --- The reward path ----------------------------------------------------------------------------

## The raw rewards of [param level] (table entries).
static func _rewards_at_level(level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in table().rewards:
		if int(r.get("level", 0)) == level:
			out.append(r)
	return out


## The rewards [param class_id] gets on reaching [param level], described: [{"level", "kind", "class_id", "unlock_kind"
## (the Profile kind it unlocks, &"" = derived from the level), "id" (the unlocked content id), "text" (the line for the
## reward lists), "amount"}].
static func rewards_at(class_id: StringName, level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in _rewards_at_level(level):
		out.append(describe(r, class_id))
	return out


## Every described reward of levels 2 .. [param level] (in level order).
static func rewards_up_to(class_id: StringName, level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in range(2, mini(level, max_level()) + 1):
		out.append_array(rewards_at(class_id, l))
	return out


## The next [param count] rewards above [param level], in level order (an empty list at the top level).
static func next_rewards(class_id: StringName, level: int, count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in range(level + 1, max_level() + 1):
		for r in rewards_at(class_id, l):
			if out.size() < count:
				out.append(r)
		if out.size() >= count:
			break
	return out


## Unlocks what the rewards of [param level] unlock in [param profile] (abilities, capstone trees, the Heirloom gift,
## cosmetics, the title) and returns the described rewards of the level (all of them, also the derived ones).
static func grant_level(profile: Profile, class_id: StringName, level: int) -> Array[Dictionary]:
	var rewards := rewards_at(class_id, level)
	for r in rewards:
		if r["unlock_kind"] != &"" and r["id"] != &"":
			profile.unlock(r["unlock_kind"], r["id"], class_id)
	return rewards


## Re-grants the unlocks of every level a class of [param profile] has reached (a profile loaded from a file, after the
## table was retuned or an unlock was missed). Returns how many unlocks were new. Nothing is saved.
static func sync_unlocks(profile: Profile) -> int:
	var fresh := 0
	for class_id in Db.class_ids:
		for l in range(2, profile.class_level(class_id) + 1):
			for r in rewards_at(class_id, l):
				if r["unlock_kind"] != &"" and r["id"] != &"" and profile.unlock(r["unlock_kind"], r["id"], class_id):
					fresh += 1
	return fresh


## The number of rewards of [param kind] at or below [param level].
static func count_rewards(kind: StringName, level: int) -> int:
	var n := 0
	for r in table().rewards:
		if StringName(str(r.get("kind", ""))) == kind and int(r.get("level", 0)) <= level:
			n += 1
	return n


## Seasoning slots a class of [param level] has (0 .. 3).
static func seasoning_slots(level: int) -> int:
	return count_rewards(&"seasoning_slot", level)


## Heirloom slots a class of [param level] has (0 or 1).
static func heirloom_slots(level: int) -> int:
	return mini(1, count_rewards(&"heirloom_slot", level))


## The level that opens the Seasonings of [param tier] (1 .. 5 = T1 .. T5; 0 = no such tier).
static func seasoning_tier_level(tier: int) -> int:
	for r in table().rewards:
		if StringName(str(r.get("kind", ""))) == &"seasoning_tier" and int(r.get("tier", 0)) == tier:
			return int(r.get("level", 0))
	return 0


## The level that gives the alternative starting weapon (0 = none).
static func alt_weapon_level() -> int:
	return _first_level_of(&"alt_weapon")


static func _first_level_of(kind: StringName) -> int:
	var best := 0
	for r in table().rewards:
		if StringName(str(r.get("kind", ""))) == kind and (best == 0 or int(r.get("level", 0)) < best):
			best = int(r.get("level", 0))
	return best


## The level at which the Class Level reward of ([param kind], [param id]) is given for [param class_id] (0 = not a
## level reward): how the gates' hints and the tests find the level of an ability, a capstone tree ...
static func unlock_level(class_id: StringName, kind: StringName, id: StringName) -> int:
	for l in range(2, max_level() + 1):
		for r in rewards_at(class_id, l):
			if r["unlock_kind"] == kind and r["id"] == id:
				return l
	return 0


## The small permanent bonuses a hero of [param level] gets (the table's gold / primary_pct / reroll / backpack rewards
## added up): {"gold", "primary_pct", "rerolls", "backpack"}. Applied at run start for real profiles only (Meta.raw_power).
static func raw_power(level: int) -> Dictionary:
	var out := {"gold": 0, "primary_pct": 0.0, "rerolls": 0, "backpack": 0}
	for r in table().rewards:
		if int(r.get("level", 0)) > level:
			continue
		var amount: Variant = r.get("amount", 0)
		match StringName(str(r.get("kind", ""))):
			&"gold":
				out["gold"] += int(amount)
			&"primary_pct":
				out["primary_pct"] += float(amount)
			&"reroll":
				out["rerolls"] += int(amount)
			&"backpack":
				out["backpack"] += int(amount)
	return out


## Describes the table entry [param reward] for [param class_id] (see [method rewards_at]).
static func describe(reward: Dictionary, class_id: StringName) -> Dictionary:
	var kind := StringName(str(reward.get("kind", "")))
	var path := Db.class_path(class_id)
	var out := {"level": int(reward.get("level", 0)), "kind": kind, "class_id": class_id, "unlock_kind": &"",
			"id": &"", "text": "", "amount": reward.get("amount", 0)}
	var index := int(reward.get("index", 0))
	match kind:
		&"ability":
			var id: StringName = path.deck_abilities[index] if path != null and index < path.deck_abilities.size() else &""
			var ability := Db.get_ability(id)
			out["unlock_kind"] = Profile.KIND_ABILITY
			out["id"] = id
			out["text"] = "New ability: %s" % (ability.display_name if ability != null else String(id).capitalize())
		&"capstone":
			var tree_id: StringName = path.capstone_trees[index] if path != null and index < path.capstone_trees.size() else &""
			out["unlock_kind"] = Profile.KIND_CAPSTONE_TREE
			out["id"] = tree_id
			out["text"] = "Capstone talent: %s" % _capstone_name(tree_id)
		&"seasoning_slot":
			out["text"] = "Seasoning slot %d" % count_rewards(&"seasoning_slot", int(out["level"]))
		&"seasoning_tier":
			out["text"] = "Tier %d Seasonings" % int(reward.get("tier", 0))
		&"heirloom_slot":
			out["text"] = "Heirloom slot"
		&"heirloom_gift":
			out["unlock_kind"] = Profile.KIND_HEIRLOOM
			out["id"] = path.gift_heirloom if path != null else &""
			out["text"] = "Heirloom: %s" % (path.gift_heirloom_name if path != null and path.gift_heirloom_name != "" else "a gift")
		&"alt_weapon":
			out["text"] = "Alternative weapon: %s" % alt_weapon_name(class_id)
		&"cosmetic":
			var c: Dictionary = path.cosmetic(StringName(str(reward.get("slot", "")))) if path != null else {}
			out["unlock_kind"] = Profile.KIND_COSMETIC
			out["id"] = StringName(str(c.get("id", "")))
			out["text"] = "Cosmetic: %s" % str(c.get("name", "a cosmetic"))
		&"title":
			out["unlock_kind"] = Profile.KIND_TITLE
			out["id"] = path.title_id if path != null else &""
			out["text"] = "Title: %s" % (path.title_name if path != null else "")
		&"gold":
			out["text"] = "+%d starting gold" % int(reward.get("amount", 0))
		&"primary_pct":
			var cls := Db.get_class_data(class_id)
			var stat_name := Stats.display_name(cls.primary_stat) if cls != null else "primary stat"
			out["text"] = "+%s%% %s" % [_number_text(float(reward.get("amount", 0.0))), stat_name]
		&"reroll":
			out["text"] = "+%d free shop reroll per run" % int(reward.get("amount", 0))
		&"backpack":
			out["text"] = "+%d backpack slot" % int(reward.get("amount", 0))
		_:
			out["text"] = String(kind).capitalize()
	return out


static func _number_text(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


## "Evasion" ... the name of the capstone talent of tree [param tree_id] ("a capstone" when unknown).
static func _capstone_name(tree_id: StringName) -> String:
	var tree := Db.get_talent_tree(tree_id)
	if tree == null:
		return String(tree_id).capitalize()
	for t in tree.talents:
		if t != null and t.is_capstone():
			return "%s (%s)" % [t.display_name, tree.display_name]
	return tree.display_name


# --- The alternative starting weapon ------------------------------------------------------------

## The main hand [param class_id] starts with: the alternative one when [param alt] and the class has one, else the
## class's own.
static func start_main_hand(class_data: ClassData, alt: bool) -> WeaponData:
	if class_data == null:
		return null
	var path := Db.class_path(class_data.id)
	if alt and path != null and path.has_alt_weapon():
		return path.alt_main_hand
	return class_data.main_hand


## The off hand of the start loadout (the alternative's off hand replaces the class's: a two-hander leaves it empty).
static func start_off_hand(class_data: ClassData, alt: bool) -> WeaponData:
	if class_data == null:
		return null
	var path := Db.class_path(class_data.id)
	if alt and path != null and path.has_alt_weapon():
		return path.alt_off_hand
	return class_data.off_hand


## "Two-Hand Sword" / "Wand + Orb": the display name of the alternative start loadout ("" = none).
static func alt_weapon_name(class_id: StringName) -> String:
	var path := Db.class_path(class_id)
	if path == null or not path.has_alt_weapon():
		return ""
	var name := path.alt_main_hand.display_name
	if path.alt_off_hand != null:
		name += " + " + path.alt_off_hand.display_name
	return name
