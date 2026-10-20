class_name AchievementProgress
extends RefCounted
## How far a profile is from an achievement (M9 PATCH, the Achievements tab of The Onion Patch): a pure function of an
## [AchievementData] and a [Profile]. Only the conditions that rest on the profile's own numbers have a progress – a
## counter, a lifetime total, the Class Level, the achievement points or count, the number of looks – and the
## compounds of them ("win with every class": the share of finished parts). A condition that is decided inside one
## run (win without anyone going down) has none: the achievement is "not yet" or "done".
##
## [method of] returns {"known": bool, "value": int, "goal": int, "done": bool}; "known" = a progress bar can be drawn
## (goal > 0). An unlocked achievement is always value == goal.


static func of(data: AchievementData, profile: Profile) -> Dictionary:
	var out := {"known": false, "value": 0, "goal": 0, "done": false}
	if data == null or profile == null:
		return out
	if profile.has_achievement(data.id):
		out["done"] = true
		out["known"] = true
		out["value"] = 1
		out["goal"] = 1
		var measured := measure(data.condition(), profile)
		if int(measured["goal"]) > 0:
			out["value"] = int(measured["goal"])
			out["goal"] = int(measured["goal"])
		return out
	var m := measure(data.condition(), profile)
	if int(m["goal"]) > 0:
		out["known"] = true
		out["value"] = clampi(int(m["value"]), 0, int(m["goal"]))
		out["goal"] = int(m["goal"])
	return out


## {"value": int, "goal": int} of [param condition] (goal 0 = no progress): see the class doc.
static func measure(condition: Dictionary, profile: Profile) -> Dictionary:
	var kind := StringName(str(condition.get("kind", "")))
	match kind:
		AchievementEngine.COND_COUNTER_AT_LEAST:
			return _pair(profile.counter(StringName(str(condition.get("counter", "")))), int(condition.get("value", 0)))
		AchievementEngine.COND_TOTAL_AT_LEAST:
			return _pair(profile.counter(StringName(AchievementEngine.COUNTER_TOTAL + str(condition.get("stat", "")))),
					int(condition.get("value", 0)))
		AchievementEngine.COND_CLASS_LEVEL_AT_LEAST:
			return _pair(profile.class_level(StringName(str(condition.get("class_id", "")))), int(condition.get("value", 0)))
		AchievementEngine.COND_POINTS_AT_LEAST:
			return _pair(AchievementEngine.points_of(profile, Db.achievement_list()), int(condition.get("value", 0)))
		AchievementEngine.COND_ACHIEVEMENTS_AT_LEAST:
			return _pair(profile.achievements.size(), int(condition.get("count", 0)))
		AchievementEngine.COND_UNLOCK_COUNT_AT_LEAST:
			var owned: Dictionary = profile.unlocks.get(Profile.stored_kind(StringName(str(condition.get("unlock_kind", ""))),
					StringName(str(condition.get("class_id", "")))), {})
			return _pair(owned.size(), int(condition.get("count", 0)))
		AchievementEngine.COND_ALL_OF:
			return _share(condition, profile, false)
		AchievementEngine.COND_ANY_OF:
			return _share(condition, profile, true)
	return _pair(0, 0)


static func _pair(value: int, goal: int) -> Dictionary:
	return {"value": value, "goal": goal}


## all_of: how many parts are finished (every part must have a progress); any_of: the part that is furthest.
static func _share(condition: Dictionary, profile: Profile, best_only: bool) -> Dictionary:
	var parts: Array[Dictionary] = []
	for c: Variant in condition.get("conditions", []):
		if not (c is Dictionary):
			return _pair(0, 0)
		var m := measure(c, profile)
		if int(m["goal"]) <= 0:
			return _pair(0, 0)
		parts.append(m)
	if parts.is_empty():
		return _pair(0, 0)
	if best_only:
		var best := parts[0]
		for m in parts:
			if float(m["value"]) / float(m["goal"]) > float(best["value"]) / float(best["goal"]):
				best = m
		return _pair(mini(int(best["value"]), int(best["goal"])), int(best["goal"]))
	var done := 0
	for m in parts:
		if int(m["value"]) >= int(m["goal"]):
			done += 1
	return _pair(done, parts.size())
