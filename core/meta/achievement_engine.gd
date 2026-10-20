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
##                                                    downs, need_wins).
##   stat_at_most   {stat, value, scope?, class_id?}  the same with <= (no hero qualifies in an empty party).
##   run_flag       {flag, value?}                     RunReport.flag(flag) == value (default true): victory,
##                                                    abandoned, hardcore, endless, solo, full_party, no_downs;
##                                                    text flags: mode, environment, difficulty.
##   counter_at_least {counter, value}                 the profile's counter >= value. Counters kept by
##                                                    [method update_counters]: "runs", "wins", "runs:<class>",
##                                                    "wins:<class>", "total:<stat>", "best:<stat>".
##   class_in_party {class_id}                          a hero of that class was in the party.
##   class_level_at_least {class_id, value}             the profile's Class Level of the class >= value.
##   achievements_at_least {count}                      this many achievements are unlocked.
##   points_at_least {value}                            the unlocked achievements' points add up to value.
##   unlocked       {unlock_kind, id, class_id?}        the profile has that unlock (Profile.KINDS).
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
const COND_ALL_OF := &"all_of"
const COND_ANY_OF := &"any_of"
const COND_NOT := &"not"
const CONDITION_KINDS: Array[StringName] = [COND_STAT_AT_LEAST, COND_STAT_AT_MOST, COND_RUN_FLAG,
		COND_COUNTER_AT_LEAST, COND_CLASS_IN_PARTY, COND_CLASS_LEVEL_AT_LEAST, COND_ACHIEVEMENTS_AT_LEAST,
		COND_POINTS_AT_LEAST, COND_UNLOCKED, COND_ALL_OF, COND_ANY_OF, COND_NOT]

const SCOPE_RUN := &"run"
const SCOPE_HERO := &"hero"
## The per-hero stats a "hero" scope reads (the keys of a RunReport hero entry).
const HERO_STATS: Array[StringName] = [&"damage", &"healing", &"absorbed", &"taken", &"kills", &"bosses",
		&"revives", &"downs", &"need_wins"]

## Counters [method update_counters] keeps, besides "total:<stat>" and "best:<stat>".
const COUNTER_RUNS := &"runs"
const COUNTER_WINS := &"wins"
## Prefixes of the counters.
const COUNTER_TOTAL := "total:"
const COUNTER_BEST := "best:"

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

## Updates the counters of [param profile] with a finished run: "runs" (+1), "wins" (+1 on a victory), "runs:<class>"
## and "wins:<class>" (+1 per class in the party, once even when two heroes share it), "total:<stat>" (+ the run's
## value, rounded) and "best:<stat>" (the highest run value) for every stat of the report that is not 0.
static func update_counters(profile: Profile, report: RunReport) -> void:
	if profile == null or report == null:
		return
	profile.add_counter(COUNTER_RUNS, 1)
	if report.victory:
		profile.add_counter(COUNTER_WINS, 1)
	for id in report.classes_played():
		profile.add_counter(StringName("%s:%s" % [COUNTER_RUNS, id]), 1)
		if report.victory:
			profile.add_counter(StringName("%s:%s" % [COUNTER_WINS, id]), 1)
	for id in report.stats:
		var value := roundi(report.stats[id])
		if value != 0:  # (a zero changes nothing and would only fill the file)
			profile.add_counter(StringName(COUNTER_TOTAL + String(id)), value)
			profile.raise_counter(StringName(COUNTER_BEST + String(id)), value)


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
