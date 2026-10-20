class_name Profile
extends RefCounted
## The main profile (GDD 17.1, M9 meta-progression): everything the game keeps between runs. Plain data – no Node,
## no engine side effects – so tests build their own. The [Meta] autoload owns the current one.
##
## What it holds (all keyed by content id, never by slot or device):
##   - per class: Class XP and Class Level ([method class_xp] / [method class_level], 1 .. [constant MAX_CLASS_LEVEL]);
##     the level is stored, not derived: whoever raises XP sets the level (Class Level package) and it never drops;
##   - unlocks: sets of content ids by kind ([constant KINDS]); the class-scoped kind difficulty is stored per class
##     ("difficulty:warrior"). [method unlock] / [method has_unlock];
##   - achievements ({id: unix time of the unlock}) and counters for achievement progress;
##   - the Seeds wallet ([method earn_seeds] / [method spend_seeds] / [method can_afford]);
##   - heirloom ranks, the lobby selections remembered per class ([method loadout]: Seasonings, Heirloom, looks per
##     visible slot) and the chosen title.
##
## Origins: a profile read from a file (or [method fresh]) is a normal player profile. [method dev] is the profile
## of every automated run (smoke, demo, views, tests): everything unlocked, no raw-power bonus, nothing selected,
## never saved. [method max_profile] is a finished player: every class at the top level and everything unlocked.
## "Everything unlocked" is the [member all_unlocked] flag: [method has_unlock] answers true (the file keeps it only for a
## max profile written with --profile-path, so that file stays "max").
##
## File (FORMAT_VERSION 1, JSON, [method save_file] / [method load_file]):
##   {"version": 1, "created_at": unix, "classes": {id: {"xp": int, "level": int}}, "unlocks": {kind: [ids]},
##    "achievements": {id: unix}, "counters": {name: int}, "seeds": int, "seeds_earned": int,
##    "heirloom_ranks": {id: int}, "loadouts": {class id: {"seasonings": [ids], "heirloom": id, "looks": {slot: id}, "alt_weapon": bool}},
##    "selected_title": id, "all_unlocked": true (only a saved max profile)}
## A missing file is a fresh profile; a file that cannot be parsed is moved to "<path>.corrupt" and a fresh profile
## is used; a file of a NEWER version is never overwritten (the profile is fresh and read-only); a path that cannot
## be read as a file is never overwritten either. The write goes through "<path>.tmp" and a rename. Unknown keys and
## unknown content ids are kept as they are, so removing or adding content never destroys a save.

const FORMAT_VERSION := 1
const DEFAULT_PATH := "user://profile.json"
const START_CLASS_LEVEL := 1
const MAX_CLASS_LEVEL := 30

## Unlock kinds (the sets of [member unlocks]). The ids are the permanent content ids of their kind.
const KIND_CLASS := &"class"
const KIND_ABILITY := &"ability"
## A talent tree's capstone (TalentTreeData id).
const KIND_CAPSTONE_TREE := &"capstone_tree"
## A hand-made Legendary (UniqueItemData id) or a forged weapon type's Legendary effect (Forge, "legendary_<weapon>").
const KIND_LEGENDARY := &"legendary"
## A difficulty tier, per class: [code]unlock(KIND_DIFFICULTY, &"pungent", &"warrior")[/code].
const KIND_DIFFICULTY := &"difficulty"
const KIND_SEASONING := &"seasoning"
const KIND_HEIRLOOM := &"heirloom"
const KIND_COSMETIC := &"cosmetic"
const KIND_TITLE := &"title"
## A Wardrobe look (an item look the hero has worn).
const KIND_LOOK := &"look"
const KINDS: Array[StringName] = [KIND_CLASS, KIND_ABILITY, KIND_CAPSTONE_TREE, KIND_LEGENDARY, KIND_DIFFICULTY,
		KIND_SEASONING, KIND_HEIRLOOM, KIND_COSMETIC, KIND_TITLE, KIND_LOOK]
## Kinds that are earned or bought: locked until the profile owns them (the other kinds are locked only where an
## unlock gate holds content back, see Meta.is_unlocked).
const COLLECTIBLE_KINDS: Array[StringName] = [KIND_SEASONING, KIND_HEIRLOOM, KIND_COSMETIC, KIND_TITLE, KIND_LOOK]
## Kinds whose unlocks belong to one class (the stored kind is "<kind>:<class id>").
const SCOPED_KINDS: Array[StringName] = [KIND_DIFFICULTY]

## The visible armour slots a look can be picked for (the keys of a loadout's "looks").
const LOOK_SLOTS: Array[StringName] = [&"head", &"shoulders", &"chest"]
## --- Wardrobe (M9) --- The cosmetic keys of a loadout (flat, next to "looks"): the owned Tabard / Hat variant / Glow / Dye
## id picked for the class, &"" = none (CosmeticData.KINDS).
const COSMETIC_KEYS: Array[StringName] = [&"tabard", &"hat", &"glow", &"dye"]

## "" = a good file or none; else why the file was not used: "corrupt", "newer version" or "unreadable"
## (set by [method load_file]).
var load_error := ""
## The file was of a newer version, or exists but cannot be read: [method save_file] refuses.
var read_only := false
## No file was there ([method load_file]): this is the player's first launch.
var is_new := false

## The profile of automated runs: never saved, never touched by [method Meta.record_run].
var is_dev := false
## Every check answers "unlocked" (the dev and max profiles).
var all_unlocked := false
## The Class Level raw-power bonuses apply (false for the dev profile: a run is the base game).
var raw_power := true

var created_at := 0
## Class id -> {"xp": int, "level": int}.
var classes: Dictionary[StringName, Dictionary] = {}
## Stored kind -> {content id: true}.
var unlocks: Dictionary[StringName, Dictionary] = {}
## Achievement id -> unix time of the unlock.
var achievements: Dictionary[StringName, int] = {}
## Counters for achievement progress (see AchievementEngine.update_counters).
var counters: Dictionary[StringName, int] = {}
var seeds := 0
## Seeds earned over the profile's life (spending does not lower it).
var seeds_earned := 0
## Heirloom id -> rank above the first (an owned heirloom without an entry is rank 1).
var heirloom_ranks: Dictionary[StringName, int] = {}
## Class id -> remembered lobby selections (see [method loadout]).
var loadouts: Dictionary[StringName, Dictionary] = {}
var selected_title: StringName = &""


# --- Factories ----------------------------------------------------------------------------------

## A new player: nothing earned, nothing unlocked.
static func fresh() -> Profile:
	var p := Profile.new()
	p.created_at = int(Time.get_unix_time_from_system())
	return p


## The profile of automated runs: everything unlocked, no raw-power bonus, nothing selected, not saved.
static func dev() -> Profile:
	var p := Profile.new()
	p.is_dev = true
	p.all_unlocked = true
	p.raw_power = false
	return p


## A finished player: every class in [param class_ids] at [constant MAX_CLASS_LEVEL], everything unlocked, every
## Heirloom in [param heirloom_ids] at its top rank (M9 PATCH).
static func max_profile(class_ids: Array[StringName] = [], heirloom_ids: Array[StringName] = []) -> Profile:
	var p := Profile.fresh()
	p.all_unlocked = true
	for id in class_ids:
		p.set_class_progress(id, p.class_xp(id), MAX_CLASS_LEVEL)
	for id in heirloom_ids:
		p.set_heirloom_rank(id, HeirloomData.MAX_RANK)
	return p


# --- Class XP and level -------------------------------------------------------------------------

## Class XP earned with [param class_id] (0 = none).
func class_xp(class_id: StringName) -> int:
	return int(classes.get(class_id, {}).get("xp", 0))


## Class Level of [param class_id] (1 = a class never played).
func class_level(class_id: StringName) -> int:
	return clampi(int(classes.get(class_id, {}).get("level", START_CLASS_LEVEL)), START_CLASS_LEVEL, MAX_CLASS_LEVEL)


## Sets XP and level of [param class_id] (both clamped; the level never drops below the stored one).
func set_class_progress(class_id: StringName, xp: int, level: int) -> void:
	if class_id == &"":
		return
	classes[class_id] = {"xp": maxi(xp, 0), "level": clampi(maxi(level, class_level(class_id)), START_CLASS_LEVEL, MAX_CLASS_LEVEL)}


## Adds [param amount] (>= 0) Class XP to [param class_id]; returns the class's XP now. The level is left to the
## caller (the Class Level package computes it from the XP curve and stores it with [method set_class_progress]).
func add_class_xp(class_id: StringName, amount: int) -> int:
	if class_id == &"":
		return 0
	var xp := class_xp(class_id) + maxi(amount, 0)
	set_class_progress(class_id, xp, class_level(class_id))
	return xp


# --- Unlocks ------------------------------------------------------------------------------------

## The stored kind of [param kind] for [param class_id]: "difficulty:warrior" for a class-scoped kind, else [param kind].
static func stored_kind(kind: StringName, class_id: StringName = &"") -> StringName:
	if kind in SCOPED_KINDS and class_id != &"":
		return StringName("%s:%s" % [kind, class_id])
	return kind


## Records the unlock of [param id] of [param kind] ([param class_id] for the class-scoped kinds). True when it was
## new. An empty kind or id records nothing.
func unlock(kind: StringName, id: StringName, class_id: StringName = &"") -> bool:
	if kind == &"" or id == &"":
		return false
	var key := stored_kind(kind, class_id)
	var ids: Dictionary = unlocks.get(key, {})
	if ids.has(id):
		return false
	ids[id] = true
	unlocks[key] = ids
	return true


## True when the profile unlocked [param id] of [param kind] ([param class_id] for the class-scoped kinds) – or
## everything is unlocked ([member all_unlocked]). This is the profile's record only: whether the content is gated at
## all is [method Meta.is_unlocked]'s business.
func has_unlock(kind: StringName, id: StringName, class_id: StringName = &"") -> bool:
	if all_unlocked:
		return true
	return unlocks.get(stored_kind(kind, class_id), {}).has(id)


## The ids unlocked of [param kind] (sorted; the recorded ones only, [member all_unlocked] adds nothing).
func unlocked_ids(kind: StringName, class_id: StringName = &"") -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in unlocks.get(stored_kind(kind, class_id), {}):
		out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


# --- Achievements and counters ------------------------------------------------------------------

func has_achievement(id: StringName) -> bool:
	return achievements.has(id)


## Records the achievement [param id] as unlocked at [param at] (unix time). False when it already was.
func unlock_achievement(id: StringName, at: int = 0) -> bool:
	if id == &"" or achievements.has(id):
		return false
	achievements[id] = at
	return true


func counter(name: StringName) -> int:
	return counters.get(name, 0)


## Adds [param delta] to the counter [param name]; returns its value.
func add_counter(name: StringName, delta: int) -> int:
	var v := counter(name) + delta
	counters[name] = v
	return v


## Raises the counter [param name] to [param value] when that is more (a "best" counter); returns its value.
func raise_counter(name: StringName, value: int) -> int:
	var v := maxi(counter(name), value)
	counters[name] = v
	return v


# --- Seeds --------------------------------------------------------------------------------------

func can_afford(amount: int) -> bool:
	return amount <= seeds


## Adds [param amount] (>= 0) Seeds; returns the wallet.
func earn_seeds(amount: int) -> int:
	var a := maxi(amount, 0)
	seeds += a
	seeds_earned += a
	return seeds


## Pays [param amount] (>= 0) Seeds. False (nothing changes) when the wallet holds less.
func spend_seeds(amount: int) -> bool:
	var a := maxi(amount, 0)
	if a > seeds:
		return false
	seeds -= a
	return true


# --- Heirlooms ----------------------------------------------------------------------------------

## The rank of the heirloom [param id]: 0 = not owned, 1 = owned, more after upgrades.
func heirloom_rank(id: StringName) -> int:
	if not unlocks.get(KIND_HEIRLOOM, {}).has(id) and not all_unlocked:
		return 0
	return 1 + int(heirloom_ranks.get(id, 0))


## Sets the rank of the heirloom [param id] (>= 1; the heirloom is unlocked too).
func set_heirloom_rank(id: StringName, rank: int) -> void:
	if id == &"":
		return
	unlock(KIND_HEIRLOOM, id)
	var extra := maxi(rank, 1) - 1
	if extra > 0:
		heirloom_ranks[id] = extra
	else:
		heirloom_ranks.erase(id)


# --- Lobby selections ---------------------------------------------------------------------------

## The remembered selections of [param class_id]: {"seasonings": Array[StringName], "heirloom": StringName,
## "looks": {slot name (LOOK_SLOTS): look id}, "alt_weapon": bool (the class's alternative starting weapon, Class Level 12),
## and the Wardrobe's cosmetic keys (COSMETIC_KEYS: "tabard", "hat", "glow", "dye": a StringName id, &"" = none)}
## – a copy, empty values when nothing was remembered.
func loadout(class_id: StringName) -> Dictionary:
	return normalize_loadout(loadouts.get(class_id, {}))


## Remembers [param value] (see [method loadout]; normalised) for [param class_id].
func set_loadout(class_id: StringName, value: Dictionary) -> void:
	if class_id == &"":
		return
	loadouts[class_id] = normalize_loadout(value)


## [param value] with exactly the loadout keys and types (anything else dropped).
static func normalize_loadout(value: Dictionary) -> Dictionary:
	var seasonings: Array[StringName] = []
	var raw_seasonings: Variant = value.get("seasonings", [])
	if raw_seasonings is Array:
		for s: Variant in raw_seasonings:
			if str(s) != "" and StringName(str(s)) not in seasonings:
				seasonings.append(StringName(str(s)))
	var looks: Dictionary[StringName, StringName] = {}
	var raw_looks: Variant = value.get("looks", {})
	if raw_looks is Dictionary:
		for slot: Variant in raw_looks:
			if str(raw_looks[slot]) != "":
				looks[StringName(str(slot))] = StringName(str(raw_looks[slot]))
	var alt: Variant = value.get("alt_weapon", false)
	var out := {"seasonings": seasonings, "heirloom": StringName(str(value.get("heirloom", ""))), "looks": looks,
			"alt_weapon": typeof(alt) == TYPE_BOOL and alt}
	# --- Wardrobe (M9) ---
	for key in COSMETIC_KEYS:
		out[key] = StringName(str(value.get(key, "")))
	return out


# --- Saving and loading -------------------------------------------------------------------------

## The profile as plain JSON-able data (ids as strings, sets as sorted arrays). The runtime-only flags are not part
## of it.
func to_dict() -> Dictionary:
	var class_data := {}
	for id in classes:
		class_data[String(id)] = {"xp": int(classes[id].get("xp", 0)), "level": class_level(id)}
	var unlock_data := {}
	for kind in unlocks:
		var ids: Array[String] = []
		for id: StringName in unlocks[kind]:
			ids.append(String(id))
		ids.sort()
		if not ids.is_empty():
			unlock_data[String(kind)] = ids
	var achievement_data := {}
	for id in achievements:
		achievement_data[String(id)] = achievements[id]
	var counter_data := {}
	for name in counters:
		counter_data[String(name)] = counters[name]
	var rank_data := {}
	for id in heirloom_ranks:
		rank_data[String(id)] = heirloom_ranks[id]
	var loadout_data := {}
	for id in loadouts:
		var l := normalize_loadout(loadouts[id])
		var seasonings: Array[String] = []
		for s: StringName in l["seasonings"]:
			seasonings.append(String(s))
		var looks := {}
		for slot: StringName in l["looks"]:
			looks[String(slot)] = String(l["looks"][slot])
		loadout_data[String(id)] = {"seasonings": seasonings, "heirloom": String(l["heirloom"]), "looks": looks,
				"alt_weapon": l["alt_weapon"]}
		# --- Wardrobe (M9) --- (only the picked ones are written)
		for key in COSMETIC_KEYS:
			if l[key] != &"":
				loadout_data[String(id)][String(key)] = String(l[key])
	var out := {
		"version": FORMAT_VERSION,
		"created_at": created_at,
		"classes": class_data,
		"unlocks": unlock_data,
		"achievements": achievement_data,
		"counters": counter_data,
		"seeds": seeds,
		"seeds_earned": seeds_earned,
		"heirloom_ranks": rank_data,
		"loadouts": loadout_data,
		"selected_title": String(selected_title),
	}
	if all_unlocked:
		out["all_unlocked"] = true  # (only the max profile saved with --profile-path; a player's file never has it)
	return out


## The profile of [param data] (a parsed file; run it through [method migrate] first). Tolerant: a field of the
## wrong type or out of range falls back to its default, nothing here is fatal.
static func from_dict(data: Dictionary) -> Profile:
	var p := Profile.new()
	p.created_at = maxi(_int(data.get("created_at", 0)), 0)
	var class_data: Variant = data.get("classes", {})
	if class_data is Dictionary:
		for id: Variant in class_data:
			var entry: Variant = class_data[id]
			if str(id) != "" and entry is Dictionary:
				p.set_class_progress(StringName(str(id)), _int(entry.get("xp", 0)), _int(entry.get("level", START_CLASS_LEVEL)))
	var unlock_data: Variant = data.get("unlocks", {})
	if unlock_data is Dictionary:
		for kind: Variant in unlock_data:
			if unlock_data[kind] is Array:
				for id: Variant in unlock_data[kind]:
					if str(kind) != "" and str(id) != "":
						var ids: Dictionary = p.unlocks.get(StringName(str(kind)), {})
						ids[StringName(str(id))] = true
						p.unlocks[StringName(str(kind))] = ids
	var achievement_data: Variant = data.get("achievements", {})
	if achievement_data is Dictionary:
		for id: Variant in achievement_data:
			if str(id) != "":
				p.achievements[StringName(str(id))] = maxi(_int(achievement_data[id]), 0)
	var counter_data: Variant = data.get("counters", {})
	if counter_data is Dictionary:
		for name: Variant in counter_data:
			if str(name) != "":
				p.counters[StringName(str(name))] = _int(counter_data[name])
	p.seeds = maxi(_int(data.get("seeds", 0)), 0)
	p.seeds_earned = maxi(_int(data.get("seeds_earned", 0)), p.seeds)
	var rank_data: Variant = data.get("heirloom_ranks", {})
	if rank_data is Dictionary:
		for id: Variant in rank_data:
			if str(id) != "" and _int(rank_data[id]) > 0:
				p.heirloom_ranks[StringName(str(id))] = _int(rank_data[id])
	var loadout_data: Variant = data.get("loadouts", {})
	if loadout_data is Dictionary:
		for id: Variant in loadout_data:
			if str(id) != "" and loadout_data[id] is Dictionary:
				p.loadouts[StringName(str(id))] = normalize_loadout(loadout_data[id])
	p.selected_title = StringName(str(data.get("selected_title", "")))
	var unlocked_all: Variant = data.get("all_unlocked", false)
	p.all_unlocked = typeof(unlocked_all) == TYPE_BOOL and unlocked_all
	return p


## [param data] brought up to [param target] (the file format's version): each step turns version n into n + 1, so a
## file of any older version loads as the current one. The version-1 format has no older ancestors; the steps of
## later versions go into [method _migration_steps] ({from version: Callable(Dictionary) -> Dictionary}).
## [param steps] replaces that table (tests). A copy is returned; a version above [param target] is left as it is.
static func migrate(data: Dictionary, target: int = FORMAT_VERSION, steps: Dictionary = {}) -> Dictionary:
	var table: Dictionary = steps if not steps.is_empty() else _migration_steps()
	var out: Dictionary = data.duplicate(true)
	var version := _int(out.get("version", 0))
	while version < target:
		if table.has(version):
			var step: Callable = table[version]
			out = step.call(out)
		version += 1
		out["version"] = version
	return out


## The migration steps of the shipped formats (none yet: version 1 is the first).
static func _migration_steps() -> Dictionary:
	return {}


## Reads the profile at [param path]. Never null: a missing file gives a fresh profile ([member is_new]); a file that
## cannot be parsed is moved to "<path>.corrupt" and a fresh profile is used ([member load_error] "corrupt"); a file
## of a newer version gives a fresh read-only profile ("newer version"); a path that exists but cannot be read as a
## file gives a fresh read-only one ("unreadable"). The cases other than a missing file print a warning.
static func load_file(path: String) -> Profile:
	if DirAccess.dir_exists_absolute(path):
		return _unusable(path, "unreadable", true)
	if not FileAccess.file_exists(path):
		var p := fresh()
		p.is_new = true
		return p
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _unusable(path, "unreadable", true)
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()  # (JSON.parse_string would print an engine error for a broken file)
	if json.parse(text) != OK or not (json.data is Dictionary) or not (json.data as Dictionary).has("version"):
		return _unusable(path, "corrupt", false)
	var data: Dictionary = json.data
	if _int(data.get("version", 0)) > FORMAT_VERSION:
		return _unusable(path, "newer version", true)
	var p := from_dict(migrate(data))
	return p


## Writes the profile to [param path] through "<path>.tmp" and a rename, so a crash keeps the old file. Refuses a
## [member read_only] or [member is_dev] profile with ERR_FILE_NO_PERMISSION.
func save_file(path: String) -> Error:
	if read_only or is_dev:
		return ERR_FILE_NO_PERMISSION
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		var made := DirAccess.make_dir_recursive_absolute(dir)
		if made != OK:
			return made
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return DirAccess.rename_absolute(tmp, path)


## A fresh profile standing in for the unusable file at [param path]; the file is kept ("<path>.corrupt" for a corrupt
## one, untouched otherwise) and [param read_only] says whether saving is refused.
static func _unusable(path: String, why: String, p_read_only: bool) -> Profile:
	var p := fresh()
	p.load_error = why
	p.read_only = p_read_only
	if why == "corrupt":
		var backup := path + ".corrupt"
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		DirAccess.rename_absolute(path, backup)
		push_warning("Profile: %s is not a profile file, it was moved to %s and a new profile is used" % [path, backup])
	else:
		push_warning("Profile: %s cannot be used (%s), a new profile is used and the file is left alone" % [path, why])
	return p


## JSON numbers come back as floats; anything that is no number is 0.
static func _int(v: Variant) -> int:
	return int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0
