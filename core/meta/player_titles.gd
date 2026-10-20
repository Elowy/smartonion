class_name PlayerTitles
extends RefCounted
## Player titles (GDD 17.5, M9): a title is a profile unlock of kind [constant Profile.KIND_TITLE] that the player can
## pick as [member Profile.selected_title] and show next to their name. They come from achievements (the "name" of a
## title reward in the achievement data), from the achievement score ([constant POINT_TITLES]) and from a Class Level
## 30 (the Class Level package grants them; the names are listed here so every screen reads one place).

## Titles the achievement score earns: [{"points", "id", "name"}], ascending.
const POINT_TITLES: Array[Dictionary] = [
	{"points": 100, "id": &"title_collector", "name": "the Collector"},
	{"points": 250, "id": &"title_archivist", "name": "the Archivist"},
	{"points": 450, "id": &"title_patch_master", "name": "the Patch Master"},
	{"points": 600, "id": &"title_completionist", "name": "the Completionist"},
]

## The title of a class at Class Level 30 (id "title_<class>").
const CLASS_TITLES: Dictionary[StringName, String] = {
	&"title_warrior": "the Unbreakable", &"title_mage": "the Brightbulb", &"title_paladin": "the Gilded Layer",
	&"title_rogue": "the Silent Sprout", &"title_warlock": "the Rotten Root", &"title_hunter": "the Wild Chive",
	&"title_shaman": "the Stormleek",
}


## Unlocks the point titles that [param points] earns and [param profile] lacks; returns the new ids.
static func grant_for_points(profile: Profile, points: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if profile == null:
		return out
	for t in POINT_TITLES:
		if points >= int(t["points"]) and profile.unlock(Profile.KIND_TITLE, StringName(t["id"])):
			out.append(StringName(t["id"]))
	return out


## The display text of the title [param id] ("the Harvester"): the point titles, the class titles, then the "name" of an
## achievement reward; the id made readable when nobody names it.
static func name_of(id: StringName) -> String:
	for t in POINT_TITLES:
		if t["id"] == id:
			return String(t["name"])
	if CLASS_TITLES.has(id):
		return CLASS_TITLES[id]
	for a in Db.achievement_list():
		for reward in a.rewards:
			if StringName(str(reward.get("kind", ""))) == Profile.KIND_TITLE and StringName(str(reward.get("id", ""))) == id \
					and str(reward.get("name", "")) != "":
				return str(reward["name"])
	return String(id).trim_prefix("title_").capitalize()


## Every title the game knows, in listing order (point titles, class titles, achievement titles).
static func all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for t in POINT_TITLES:
		out.append(StringName(t["id"]))
	for id in CLASS_TITLES:
		out.append(id)
	for a in Db.achievement_list():
		for reward in a.rewards:
			var id := StringName(str(reward.get("id", "")))
			if StringName(str(reward.get("kind", ""))) == Profile.KIND_TITLE and id not in out:
				out.append(id)
	return out
