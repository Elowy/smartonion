class_name AchievementTexts
extends RefCounted
## The words of the achievement UI (M9): the HUD toast and the end screen's block. Pure functions of an
## [AchievementData] / a reward dictionary, so a test can read what the player would.

## One reward as a line: "Class unlocked: Hunter", "Legendary: Stormcaller", "Pungent unlocked for the
## Warrior", "Title: the Harvester", "Heirloom: Signet of the First Harvest", "Cosmetic: Ember Orange". A reward whose
## content is unknown (another package's id) is shown with its readable id.
static func reward_line(reward: Dictionary) -> String:
	var kind := StringName(str(reward.get("kind", "")))
	var id := StringName(str(reward.get("id", "")))
	var named := str(reward.get("name", ""))
	match kind:
		Profile.KIND_CLASS:
			var c := Db.get_class_data(id)
			return "Class unlocked: %s" % (c.display_name if c != null else String(id).capitalize())
		Profile.KIND_LEGENDARY:
			var u := Db.get_unique(id)
			return "Legendary: %s" % (u.display_name if u != null else (named if named != "" else String(id).capitalize()))
		Profile.KIND_DIFFICULTY:
			var c2 := Db.get_class_data(StringName(str(reward.get("class_id", ""))))
			return "%s unlocked for the %s" % [Difficulty.name_of(id), c2.display_name if c2 != null else "class"]
		Profile.KIND_TITLE:
			return "Title: %s" % (named if named != "" else PlayerTitles.name_of(id))
		Profile.KIND_HEIRLOOM:
			var h := Db.get_heirloom(id)  # (M9 PATCH: the Heirloom data names it, the reward's "name" is the fallback)
			return "Heirloom: %s" % (h.display_name if h != null else (named if named != "" else String(id).trim_prefix("heir_").capitalize()))
		Profile.KIND_COSMETIC:
			return "Cosmetic: %s" % (named if named != "" else String(id).capitalize())
		Profile.KIND_SEASONING:
			return "Seasoning: %s" % (named if named != "" else String(id).trim_prefix("ssn_").capitalize())
		Profile.KIND_ABILITY:
			return "Ability unlocked: %s" % (named if named != "" else String(id).capitalize())
	return "%s: %s" % [String(kind).capitalize(), named if named != "" else String(id).capitalize()]


## The reward lines of [param data] (one per reward, in order).
static func reward_lines(data: AchievementData) -> Array[String]:
	var out: Array[String] = []
	if data == null:
		return out
	for reward in data.rewards:
		out.append(reward_line(reward))
	return out


## "+25 points · +125 Seeds" – what the achievement itself pays.
static func payout_text(data: AchievementData) -> String:
	if data == null:
		return ""
	return "%d point%s  ·  +%d Seeds" % [data.points, "" if data.points == 1 else "s", data.points * Meta.SEEDS_PER_POINT]


## The toast's second line: the first reward line (and how many more follow), else the payout.
static func toast_detail(data: AchievementData) -> String:
	var lines := reward_lines(data)
	if lines.is_empty():
		return payout_text(data)
	if lines.size() == 1:
		return lines[0]
	return "%s (+%d)" % [lines[0], lines.size() - 1]
