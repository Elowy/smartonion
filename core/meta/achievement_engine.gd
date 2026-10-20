class_name AchievementEngine
extends RefCounted
## The achievement evaluator (GDD 17.5, M9): pure functions of a [Profile], a [RunReport] and the [AchievementData]
## list, so tests run them on fake data. [Meta] runs it at the end of a run ([method Meta.record_run]) and on request
## ([method Meta.check_achievements]) and emits the signals.
##
## A run's bookkeeping comes first ([method update_counters]: the profile's counters), then [method evaluate] checks
## every achievement that is not unlocked yet, unlocks it (the profile's achievement record plus its rewards) and
## repeats until nothing new unlocks (so a condition may rest on another achievement or on points). Results are in
## the order of the list.
##
## Condition vocabulary – one flat dictionary per condition, [code]{"kind": ..., params}[/code]; an
## AchievementData holds it as condition_kind + condition_params ([method AchievementData.condition]). A condition
## the report cannot answer is false; an unknown kind is false (and [method validate] reports it).
##   stat_at_least  {stat, value, scope?, class_id?}  run stat >= value. scope "run" (default): the report's stats
##                                                    ([constant RunReport.STAT_IDS]); scope "hero": some hero
##                                                    (of class_id, when given) has that stat >= value (hero stats:
##                                                    damage, healing, absorbed, taken, kills, bosses, revives,
##                                                    downs, need_wins, capstones, rank5, sets_active).
##   total_at_least {stat, value}                       the profile's lifetime total of a run stat plus the run in
##                                                    progress (a report that is not in the counters yet) >= value:
##                                                    "500 enemies slain in total" fires in the middle of a run.
##   stat_at_most   {stat, value, scope?, class_id?}  the same with <= (no hero qualifies in an empty party).
##   run_flag       {flag, value?}                     RunReport.flag(flag) == value (default true): victory,
##                                                    abandoned, hardcore, endless, solo, full_party, no_downs;
##                                                    text flags: mode, environment, difficulty.
##   counter_at_least {counter, value}                 the profile's counter >= value. Counters kept by
##                                                    [method update_counters]: "runs", "runs_long", "wins",
##                                                    "runs:<class>", "wins:<class>", "wins:<class>:<tier>",
##                                                    "env_wins:<environment>", "total:<stat>", "best:<stat>".
##   class_in_party {class_id}                          a hero of that class was in the party.
##   class_level_at_least {class_id, value}             the profile's Class Level of the class >= value.
##   achievements_at_least {count}                      this many achievements are unlocked.
##   points_at_least {value}                            the unlocked achievements' points add up to value.
##   unlocked       {unlock_kind, id, class_id?}        the profile has that unlock (Profile.KINDS).
##   unlock_count_at_least {unlock_kind, count}         the profile holds this many unlocks of that kind ("150 looks").
##   difficulty_at_least {tier}                         the run was played on that difficulty tier or a higher one.
##   all_of / any_of {conditions: [condition...]}       every / at least one (an empty list: all_of true, any_of false).
##   not            {condition: condition}              the opposite.
## Rewards ([member AchievementData.rewards]): {"kind": a Profile.KINDS entry, "id": content id, "class_id"?}.
## A content package that needs another condition registers it: [method register_condition].

const COND_STAT_AT_LEAST := &"stat_at_least"
const COND_STAT_AT_MOST := &"stat_at_most"
const COND_RUN_FLAG := &"run_flag"
const COND_COUNTER_AT_LEAST := &"counter_at_least"
const COND_CLASS_IN_PARTY := &"class_in_party"
const COND_CLASS_LEVEL_AT_LEAST := &"class_level_at_least"
const COND_ACHIEVEMENTS_AT_LEAST := &"achievements_at_least"
const COND_POINTS_AT_LEAST := &"points_at_least"
const COND_UNLOCKED := &"unlocked"
const COND_TOTAL_AT_LEAST := &"total_at_least"
const COND_UNLOCK_COUNT_AT_LEAST := &"unlock_count_at_least"
const COND_DIFFICULTY_AT_LEAST := &"difficulty_at_least"
const COND_ALL_OF := &"all_of"
const COND_ANY_OF := &"any_of"
const COND_NOT := &"not"
const CONDITION_KINDS: Array[StringName] = [COND_STAT_AT_LEAST, COND_STAT_AT_MOST, COND_RUN_FLAG,
		COND_COUNTER_AT_LEAST, COND_CLASS_IN_PARTY, COND_CLASS_LEVEL_AT_LEAST, COND_ACHIEVEMENTS_AT_LEAST,
		COND_POINTS_AT_LEAST, COND_UNLOCKED, COND_ALL_OF, COND_ANY_OF, COND_NOT, COND_TOTAL_AT_LEAST,
		COND_UNLOCK_COUNT_AT_LEAST, COND_DIFFICULTY_AT_LEAST]

const SCOPE_RUN := &"run"
const SCOPE_HERO := &"hero"
## The per-hero stats a "hero" scope reads (the keys of a RunReport hero entry).
const HERO_STATS: Array[StringName] = [&"damage", &"healing", &"absorbed", &"taken", &"kills", &"bosses",
		&"revives", &"downs", &"need_wins", &"capstones", &"rank5", &"sets_active"]

## Counters [method update_counters] keeps, besides "total:<stat>" and "best:<stat>".
const COUNTER_RUNS := &"runs"
const COUNTER_WINS := &"wins"
## Runs that reached wave [constant LONG_RUN_WAVE] (a run abandoned in its first fight is not worth counting).
const COUNTER_RUNS_LONG := &"runs_long"
const LONG_RUN_WAVE := 3
## The win counters stop here (design: "cap the stored wins counters at 9999").
const WIN_COUNTER_CAP := 9999
## Prefixes of the counters.
const COUNTER_TOTAL := "total:"
const COUNTER_BEST := "best:"
const COUNTER_ENV_WINS := "env_wins:"
## The highest wave a class reached ("best_wave:<class>", M9 PATCH: the Classes tab of The Onion Patch).
const COUNTER_BEST_WAVE := "best_wave:"

## Conditions of content packages: kind -> Callable(condition: Dictionary, profile: Profile, report: RunReport,
## defs: Array[AchievementData]) -> bool.
static var _custom: Dictionary[StringName, Callable] = {}


## Adds the condition kind [param kind] ([param check] as in the table above). Replaces an earlier one of that kind;
## a built-in kind cannot be replaced.
static func register_condition(kind: StringName, check: Callable) -> bool:
	if kind in CONDITION_KINDS or kind == &"" or not check.is_valid():
		return false
	_custom[kind] = check
	return true


static func unregister_condition(kind: StringName) -> void:
	_custom.erase(kind)


# --- The run's bookkeeping ----------------------------------------------------------------------

## Updates the counters of [param profile] with a finished run: "runs" (+1), "runs_long" (+1 when it reached wave
## [constant LONG_RUN_WAVE]), "wins" (+1 on a win: [method RunReport.won]), "runs:<class>" and "wins:<class>" (+1 per
## class in the party, once even when two heroes share it), "wins:<class>:<tier>" (a win counts on its difficulty tier AND
## every lower one, so "Pungent" means Pungent or higher), "env_wins:<environment>", "total:<stat>" (+ the run's value,
## rounded) and "best:<stat>" (the highest run value) for every stat of the report that is not 0. Marks the report
## as counted ([member RunReport.counted]).
static func update_counters(profile: Profile, report: RunReport) -> void:
	if profile == null or report == null:
		return
	report.counted = true
	profile.add_counter(COUNTER_RUNS, 1)
	if report.stat(&"wave") >= LONG_RUN_WAVE:
		profile.add_counter(COUNTER_RUNS_LONG, 1)
	var won := report.won()
	if won:
		_add_win(profile, COUNTER_WINS)
		if report.environment != &"":
			_add_win(profile, StringName(COUNTER_ENV_WINS + String(report.environment)))
	var tiers := Difficulty.ids()
	var top_tier := maxi(Difficulty.tier_index(report.difficulty), 0)
	for id in report.classes_played():
		profile.add_counter(StringName("%s:%s" % [COUNTER_RUNS, id]), 1)
		profile.raise_counter(StringName(COUNTER_BEST_WAVE + String(id)), roundi(report.stat(&"wave")))
		if won:
			_add_win(profile, StringName("%s:%s" % [COUNTER_WINS, id]))
			for i in mini(top_tier + 1, tiers.size()):
				_add_win(profile, StringName("%s:%s:%s" % [COUNTER_WINS, id, tiers[i]]))
	for id in report.stats:
		var value := roundi(report.stats[id])
		if value != 0:  # (a zero changes nothing and would only fill the file)
			profile.add_counter(StringName(COUNTER_TOTAL + String(id)), value)
			profile.raise_counter(StringName(COUNTER_BEST + String(id)), value)


static func _add_win(profile: Profile, name: StringName) -> void:
	profile.counters[name] = mini(profile.counter(name) + 1, WIN_COUNTER_CAP)


# --- Evaluation ---------------------------------------------------------------------------------

## Unlocks every achievement of [param defs] whose condition holds (see the class doc) and returns their ids in the
## order they unlocked. [param report] may be null (a check outside a run: report conditions are false);
## [param now] is the unlock time stored in the profile (unix seconds).
static func evaluate(profile: Profile, report: RunReport, defs: Array[AchievementData], now: int = 0) -> Array[StringName]:
	var unlocked: Array[StringName] = []
	if profile == null:
		return unlocked
	var run := report if report != null else RunReport.new()
	var changed := true
	var passes := 0
	while changed and passes <= defs.size():
		changed = false
		passes += 1
		for d in defs:
			if d == null or d.id == &"" or profile.has_achievement(d.id):
				continue
			if not check(d.condition(), profile, run, defs):
				continue
			profile.unlock_achievement(d.id, now)
			grant_rewards(profile, d)
			unlocked.append(d.id)
			changed = true
	return unlocked


## Records the rewards of [param data] in [param profile].
static func grant_rewards(profile: Profile, data: AchievementData) -> void:
	for reward in data.rewards:
		profile.unlock(StringName(str(reward.get("kind", ""))), StringName(str(reward.get("id", ""))),
				StringName(str(reward.get("class_id", ""))))


## Whether [param condition] holds for [param profile] and [param report]. [param defs] is the achievement list the
## points / count conditions read.
static func check(condition: Dictionary, profile: Profile, report: RunReport, defs: Array[AchievementData] = []) -> bool:
	var kind := StringName(str(condition.get("kind", "")))
	match kind:
		COND_STAT_AT_LEAST:
			return _stat_check(condition, report, true)
		COND_STAT_AT_MOST:
			return _stat_check(condition, report, false)
		COND_RUN_FLAG:
			var expected: Variant = condition.get("value", true)
			return report.flag(StringName(str(condition.get("flag", "")))) == expected
		COND_COUNTER_AT_LEAST:
			return profile.counter(StringName(str(condition.get("counter", "")))) >= int(condition.get("value", 0))
		COND_CLASS_IN_PARTY:
			return report.has_class(StringName(str(condition.get("class_id", ""))))
		COND_CLASS_LEVEL_AT_LEAST:
			return profile.class_level(StringName(str(condition.get("class_id", "")))) >= int(condition.get("value", 0))
		COND_ACHIEVEMENTS_AT_LEAST:
			return profile.achievements.size() >= int(condition.get("count", 0))
		COND_POINTS_AT_LEAST:
			return points_of(profile, defs) >= int(condition.get("value", 0))
		COND_UNLOCKED:
			return profile.has_unlock(StringName(str(condition.get("unlock_kind", ""))),
					StringName(str(condition.get("id", ""))), StringName(str(condition.get("class_id", ""))))
		COND_TOTAL_AT_LEAST:
			var stat := StringName(str(condition.get("stat", "")))
			var lifetime := profile.counter(StringName(COUNTER_TOTAL + String(stat)))
			var live := 0 if report.counted else roundi(report.stat(stat))
			return lifetime + live >= int(condition.get("value", 0))
		COND_UNLOCK_COUNT_AT_LEAST:
			var unlock_kind := StringName(str(condition.get("unlock_kind", "")))
			var owned: Dictionary = profile.unlocks.get(Profile.stored_kind(unlock_kind, StringName(str(condition.get("class_id", "")))), {})
			return owned.size() >= int(condition.get("count", 0))
		COND_DIFFICULTY_AT_LEAST:
			var wanted := Difficulty.tier_index(StringName(str(condition.get("tier", ""))))
			return wanted >= 0 and Difficulty.tier_index(StringName(str(report.flag(&"difficulty")))) >= wanted
		COND_ALL_OF:
			for c: Variant in condition.get("conditions", []):
				if not (c is Dictionary) or not check(c, profile, report, defs):
					return false
			return true
		COND_ANY_OF:
			for c: Variant in condition.get("conditions", []):
				if c is Dictionary and check(c, profile, report, defs):
					return true
			return false
		COND_NOT:
			var inner: Variant = condition.get("condition", {})
			return inner is Dictionary and not check(inner, profile, report, defs)
	if _custom.has(kind):
		return bool(_custom[kind].call(condition, profile, report, defs))
	return false


## The points of the unlocked achievements of [param defs].
static func points_of(profile: Profile, defs: Array[AchievementData]) -> int:
	var total := 0
	for d in defs:
		if d != null and profile.has_achievement(d.id):
			total += d.points
	return total


# --- Validation ---------------------------------------------------------------------------------

## What is wrong with [param data] (empty = nothing): an empty id, an unknown condition kind or a nested one, a
## missing required parameter, a reward of an unknown kind or without an id, a class-scoped reward without a class.
static func validate(data: AchievementData) -> Array[String]:
	var problems: Array[String] = []
	if data == null:
		problems.append("no data")
		return problems
	if data.id == &"":
		problems.append("empty id")
	if data.display_name.strip_edges() == "":
		problems.append("%s: no name" % data.id)
	if data.points < 0:
		problems.append("%s: negative points" % data.id)
	for p in validate_condition(data.condition()):
		problems.append("%s: %s" % [data.id, p])
	for reward in data.rewards:
		var kind := StringName(str(reward.get("kind", "")))
		if kind not in Profile.KINDS:
			problems.append("%s: reward of unknown kind '%s'" % [data.id, kind])
		if str(reward.get("id", "")) == "":
			problems.append("%s: reward without an id" % data.id)
		if kind in Profile.SCOPED_KINDS and str(reward.get("class_id", "")) == "":
			problems.append("%s: reward '%s' needs a class_id" % [data.id, kind])
	return problems


## What is wrong with the condition [param condition] (see [method validate]).
static func validate_condition(condition: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var kind := StringName(str(condition.get("kind", "")))
	if kind not in CONDITION_KINDS and not _custom.has(kind):
		problems.append("unknown condition kind '%s'" % kind)
		return problems
	var required: Array[String] = []
	match kind:
		COND_STAT_AT_LEAST, COND_STAT_AT_MOST:
			required = ["stat", "value"]
			var scope := StringName(str(condition.get("scope", SCOPE_RUN)))
			if scope not in [SCOPE_RUN, SCOPE_HERO]:
				problems.append("%s: unknown scope '%s'" % [kind, scope])
			elif scope == SCOPE_RUN and StringName(str(condition.get("stat", ""))) not in RunReport.STAT_IDS:
				problems.append("%s: unknown run stat '%s'" % [kind, condition.get("stat", "")])
			elif scope == SCOPE_HERO and StringName(str(condition.get("stat", ""))) not in HERO_STATS:
				problems.append("%s: unknown hero stat '%s'" % [kind, condition.get("stat", "")])
		COND_RUN_FLAG:
			required = ["flag"]
		COND_COUNTER_AT_LEAST:
			required = ["counter", "value"]
		COND_CLASS_IN_PARTY:
			required = ["class_id"]
		COND_CLASS_LEVEL_AT_LEAST:
			required = ["class_id", "value"]
		COND_ACHIEVEMENTS_AT_LEAST:
			required = ["count"]
		COND_POINTS_AT_LEAST:
			required = ["value"]
		COND_UNLOCKED:
			required = ["unlock_kind", "id"]
		COND_TOTAL_AT_LEAST:
			required = ["stat", "value"]
			if StringName(str(condition.get("stat", ""))) not in RunReport.STAT_IDS:
				problems.append("%s: unknown run stat '%s'" % [kind, condition.get("stat", "")])
		COND_UNLOCK_COUNT_AT_LEAST:
			required = ["unlock_kind", "count"]
			if StringName(str(condition.get("unlock_kind", ""))) not in Profile.KINDS:
				problems.append("%s: unknown unlock kind '%s'" % [kind, condition.get("unlock_kind", "")])
		COND_DIFFICULTY_AT_LEAST:
			required = ["tier"]
			if not Difficulty.is_valid(StringName(str(condition.get("tier", "")))):
				problems.append("%s: unknown difficulty '%s'" % [kind, condition.get("tier", "")])
		COND_ALL_OF, COND_ANY_OF:
			required = ["conditions"]
			var list: Variant = condition.get("conditions", [])
			if list is Array:
				for c: Variant in list:
					if c is Dictionary:
						problems.append_array(validate_condition(c))
					else:
						problems.append("%s: a condition is not a dictionary" % kind)
			else:
				problems.append("%s: conditions is not a list" % kind)
		COND_NOT:
			required = ["condition"]
			var inner: Variant = condition.get("condition", null)
			if inner is Dictionary:
				problems.append_array(validate_condition(inner))
			else:
				problems.append("not: condition is not a dictionary")
	for key in required:
		if not condition.has(key):
			problems.append("%s: missing '%s'" % [kind, key])
	return problems


# --- Internals ----------------------------------------------------------------------------------

static func _stat_check(condition: Dictionary, report: RunReport, at_least: bool) -> bool:
	var stat := StringName(str(condition.get("stat", "")))
	var limit := float(condition.get("value", 0.0))
	if StringName(str(condition.get("scope", SCOPE_RUN))) == SCOPE_HERO:
		for h in report.heroes_of(StringName(str(condition.get("class_id", "")))):
			var v := float(h.get(String(stat), 0.0))
			if (v >= limit) if at_least else (v <= limit):
				return true
		return false
	var value := report.stat(stat)
	return value >= limit if at_least else value <= limit
