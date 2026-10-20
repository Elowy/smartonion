class_name Leaderboard
extends RefCounted
## The local leaderboard (GDD 16.1, M6b MODES): per category – (mode, hardcore, party size, difficulty) – the best
## MAX_ENTRIES runs, kept in a small versioned JSON file (user://leaderboard.json). This class is the
## pure data model plus the file IO; the end screen's texts and model are [method screen_model] and the
## text helpers under "The end screen's board".
##
## File format (FORMAT_VERSION 2; a version 1 file is migrated on load, see [method migrate]):
##   {"version": 2, "categories": {"normal/standard/2": [entry, ...], "endless/hardcore/4/pungent": [...]}}
## The difficulty (M9) is the key's last segment: a Normal run keeps the plain "mode/standard|hardcore/party" key,
## Pungent and Tear-Jerker append "/pungent" / "/tear_jerker" (so a Normal board never moved).
## An entry: {"wave": int (the wave reached: the last wave cleared on a victory, the wave that ended
## the run on a defeat), "time": float (seconds of wave play, RunState.run_time), "classes": [class
## ids in slot order], "date": "YYYY-MM-DD HH:MM:SS", "victory": bool, "difficulty": the tier id (version 2;
## "normal" when missing)}. Entries of a category are
## kept best first ([method better]). A normal run ranks victories by the shortest time, and defeats by the
## highest wave, then by the LONGEST time (the longer the party held out on its last wave, the better). An
## endless run ranks every entry by the highest wave, then by the longest time.
##
## - The path is injectable: [code]Leaderboard.create(path)[/code] works on any file (tests use a temp
##   path). [method default_path] is the real file ([member path_override] replaces it in tests).
## - A missing file is an empty board. A file that cannot be parsed is moved to "<path>.corrupt" and
##   the board starts empty ([member load_error] says so). A file of a NEWER version is never
##   overwritten: the board stays empty and read-only ([member read_only]: [method save_file] refuses),
##   so an old build cannot destroy a newer build's data. Something at the path that cannot be read as
##   a file (a directory, a file that cannot be opened) is never overwritten either: the same empty,
##   read-only board, with [member load_error] "unreadable".
## - [method record_run] is the one call the game makes at a run's end. It writes nothing while
##   [member writes_enabled] is false: tests/run_tests.gd switches it off, and Main skips the call in
##   smoke / demo / screenshot runs ([method Main.writes_leaderboard]). A test that wants to exercise
##   it sets [member path_override] to a temp path and [member writes_enabled] to true, and restores both.

const FORMAT_VERSION := 2
const DEFAULT_PATH := "user://leaderboard.json"
const MAX_ENTRIES := 10
const PARTY_MIN := 1
const PARTY_MAX := 4
## Times are snapped to 0.1 s (see [method make_entry]), so this tolerance only absorbs float noise.
const TIME_EPSILON := 0.00001

## Master switch of [method record_run] (the unit test runner switches it off).
static var writes_enabled := true
## Replaces [constant DEFAULT_PATH] when not empty (tests).
static var path_override := ""

## The file this board reads and writes.
var path := ""
## Category key -> Array[Dictionary] of entries, best first (at most MAX_ENTRIES each).
var categories: Dictionary = {}
## "" = loaded fine (or no file); else why the file was not used: "corrupt", "newer version" or "unreadable".
var load_error := ""
## The file is of a newer version, or exists but cannot be read: [method save_file] refuses.
var read_only := false


## A board for [param p_path] ("" = [method default_path]); call [method load_file] to read it.
static func create(p_path: String = "") -> Leaderboard:
	var b := Leaderboard.new()
	b.path = p_path if p_path != "" else default_path()
	return b


static func default_path() -> String:
	return path_override if path_override != "" else DEFAULT_PATH


## The category of a run: "normal/standard/2", "endless/hardcore/4", "normal/standard/1/pungent" (party size clamped
## to 1..4, an unknown mode counts as normal, an unknown or Normal difficulty adds nothing).
static func category_key(p_mode: StringName, p_hardcore: bool, p_party: int, p_difficulty: StringName = Difficulty.NORMAL) -> String:
	var mode := p_mode if p_mode in RunState.MODES else RunState.MODE_NORMAL
	var key := "%s/%s/%d" % [mode, "hardcore" if p_hardcore else "standard", clampi(p_party, PARTY_MIN, PARTY_MAX)]
	if p_difficulty != Difficulty.NORMAL and Difficulty.is_valid(p_difficulty):
		key += "/" + String(p_difficulty)
	return key


## The difficulty a [method category_key] belongs to (Normal for a key without the last segment).
static func difficulty_of_key(key: String) -> StringName:
	var parts := key.split("/")
	if parts.size() > 3 and Difficulty.is_valid(StringName(parts[3])):
		return StringName(parts[3])
	return Difficulty.NORMAL


## The mode a [method category_key] belongs to.
static func mode_of_key(key: String) -> StringName:
	var mode := StringName(key.get_slice("/", 0))
	return mode if mode in RunState.MODES else RunState.MODE_NORMAL


## A well-formed entry. [param p_date] "" = now (system time).
static func make_entry(p_wave: int, p_time: float, p_classes: Array, p_victory: bool, p_date: String = "",
		p_difficulty: StringName = Difficulty.NORMAL) -> Dictionary:
	var classes: Array[String] = []
	for c in p_classes:
		classes.append(String(c))
	return {
		"wave": maxi(p_wave, 0),
		"time": snappedf(maxf(p_time, 0.0), 0.1),
		"classes": classes,
		"date": p_date if p_date != "" else Time.get_datetime_string_from_system(false, true),
		"victory": p_victory,
		"difficulty": String(p_difficulty),
	}


## True when entry [param a] ranks above [param b] in a [param p_mode] board (see the class doc).
## Ties are not "better" (a new entry goes below an equal older one).
## Endless: the later wave, then the LONGER time. Normal: a victory above a defeat, victories by the
## SHORTER time, defeats by the later wave and then the LONGER time.
static func better(a: Dictionary, b: Dictionary, p_mode: StringName) -> bool:
	var a_wave := int(a.get("wave", 0))
	var b_wave := int(b.get("wave", 0))
	var a_time := float(a.get("time", 0.0))
	var b_time := float(b.get("time", 0.0))
	if p_mode == RunState.MODE_ENDLESS:
		if a_wave != b_wave:
			return a_wave > b_wave
		return a_time > b_time + TIME_EPSILON
	var a_won := bool(a.get("victory", false))
	var b_won := bool(b.get("victory", false))
	if a_won != b_won:
		return a_won
	if a_won:
		return a_time < b_time - TIME_EPSILON
	if a_wave != b_wave:
		return a_wave > b_wave
	return a_time > b_time + TIME_EPSILON


# --- Reading ----------------------------------------------------------------------------------

## The entries of a category, best first (a copy; empty = none yet).
func entries_for(p_mode: StringName, p_hardcore: bool, p_party: int, p_difficulty: StringName = Difficulty.NORMAL) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in categories.get(category_key(p_mode, p_hardcore, p_party, p_difficulty), []):
		out.append(e.duplicate(true))
	return out


## The best entry of a category ({} = none yet).
func best_for(p_mode: StringName, p_hardcore: bool, p_party: int, p_difficulty: StringName = Difficulty.NORMAL) -> Dictionary:
	var list := entries_for(p_mode, p_hardcore, p_party, p_difficulty)
	return list[0] if not list.is_empty() else {}


## Where [param entry] would land in its category (0 = best), -1 when it would not make the top
## MAX_ENTRIES. Changes nothing.
func rank_of(entry: Dictionary, p_mode: StringName, p_hardcore: bool, p_party: int, p_difficulty: StringName = Difficulty.NORMAL) -> int:
	var list: Array = categories.get(category_key(p_mode, p_hardcore, p_party, p_difficulty), [])
	var at := list.size()
	for i in list.size():
		if better(entry, list[i], p_mode):
			at = i
			break
	return at if at < MAX_ENTRIES else -1


# --- Writing ----------------------------------------------------------------------------------

## Adds [param entry] to its category (best first, the list cut to MAX_ENTRIES). Returns its rank
## (0 = the new best), -1 when it did not make the board (then nothing changed). Does not save.
func add_entry(entry: Dictionary, p_mode: StringName, p_hardcore: bool, p_party: int, p_difficulty: StringName = Difficulty.NORMAL) -> int:
	var at := rank_of(entry, p_mode, p_hardcore, p_party, p_difficulty)
	if at < 0:
		return -1
	var key := category_key(p_mode, p_hardcore, p_party, p_difficulty)
	var list: Array = categories.get(key, [])
	list.insert(at, entry.duplicate(true))
	while list.size() > MAX_ENTRIES:
		list.pop_back()
	categories[key] = list
	return at


## Reads [member path]. Returns OK for a missing file (an empty board) and for a readable one; a corrupt
## file leaves the board empty, sets [member load_error] and moves the file to "<path>.corrupt"; a newer
## version, or a path that exists but cannot be read as a file, leaves the board empty and read-only
## ([member read_only]) with [member load_error] set ("newer version" / "unreadable").
func load_file() -> Error:
	categories = {}
	load_error = ""
	read_only = false
	if DirAccess.dir_exists_absolute(path):
		return _set_unreadable(ERR_FILE_CANT_OPEN)
	if not FileAccess.file_exists(path):
		return OK
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _set_unreadable(FileAccess.get_open_error())
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()  # (JSON.parse_string would print an engine error for a broken file)
	if json.parse(text) != OK or not (json.data is Dictionary) or not (json.data as Dictionary).has("version"):
		_set_corrupt()
		return ERR_PARSE_ERROR
	var data: Dictionary = json.data
	var version := int(data.get("version", 0))
	if version > FORMAT_VERSION:
		read_only = true
		load_error = "newer version"
		return OK
	data = migrate(data)
	if not (data.get("categories", {}) is Dictionary):
		_set_corrupt()
		return ERR_PARSE_ERROR
	categories = _sanitize(data.get("categories", {}))
	return OK


## Writes the board to [member path] (through a temporary file, so a crash keeps the old board).
## Refuses a [member read_only] board with ERR_FILE_NO_PERMISSION.
func save_file() -> Error:
	if read_only:
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
	file.store_string(JSON.stringify({"version": FORMAT_VERSION, "categories": categories}, "\t"))
	file.close()
	return DirAccess.rename_absolute(tmp, path)


## The call a finished run makes: loads the board at [method default_path], adds [param entry] to its
## category, saves, and returns {"rank": int, "save_failed": bool}. "rank" is the entry's place (0 = the best),
## -1 when it did not make the top MAX_ENTRIES or nothing was written ([member writes_enabled] is false, or the
## board is [member read_only]: a newer version, or a file that cannot be read). "save_failed" is true only when
## the entry made the board but the file could not be written: then "rank" is -1 too and the file is as it was.
static func record_run(entry: Dictionary, p_mode: StringName, p_hardcore: bool, p_party: int, p_difficulty: StringName = Difficulty.NORMAL) -> Dictionary:
	var outcome := {"rank": -1, "save_failed": false}
	if not writes_enabled:
		return outcome
	var board := create()
	board.load_file()
	if board.read_only:
		return outcome
	var rank := board.add_entry(entry, p_mode, p_hardcore, p_party, p_difficulty)
	if rank < 0:
		return outcome
	if board.save_file() != OK:
		outcome["save_failed"] = true
		return outcome
	outcome["rank"] = rank
	return outcome


# --- The end screen's board (M6b MODES) -------------------------------------------------------

## What an entry reached: "Wave 31" (an endless run), "Victory" or "Fell on wave 18" (a normal run).
static func result_text(entry: Dictionary, p_mode: StringName) -> String:
	var wave := int(entry.get("wave", 0))
	if p_mode == RunState.MODE_ENDLESS:
		return "Wave %d" % wave
	return "Victory" if bool(entry.get("victory", false)) else "Fell on wave %d" % wave


## [method result_text] and the run time: "Wave 31 · 18:22", "Victory · 24:10" (the "Best: ..." line).
static func summary_text(entry: Dictionary, p_mode: StringName) -> String:
	return "%s · %s" % [result_text(entry, p_mode), RunSummary.format_time(float(entry.get("time", 0.0)))]


## The date part of an entry's "YYYY-MM-DD HH:MM:SS".
static func date_text(entry: Dictionary) -> String:
	return String(entry.get("date", "")).get_slice(" ", 0)


## "Warrior, Mage" for the class ids of an entry (an unknown id is capitalised as is).
static func party_text(entry: Dictionary) -> String:
	var names: Array[String] = []
	for id: Variant in entry.get("classes", []):
		var data := Db.get_class_data(StringName(String(id)))
		names.append(data.display_name if data != null else String(id).capitalize())
	return ", ".join(names)


## "4 players" / "1 player".
static func party_size_text(p_party: int) -> String:
	var n := clampi(p_party, PARTY_MIN, PARTY_MAX)
	return "%d player%s" % [n, "" if n == 1 else "s"]


## The title of a category: "Endless · Hardcore · 4 players", "Normal · 2 players · Pungent" (Normal adds nothing).
static func category_text(p_mode: StringName, p_hardcore: bool, p_party: int, p_difficulty: StringName = Difficulty.NORMAL) -> String:
	var text := "%s · %s" % [RunState.mode_text(p_mode, p_hardcore), party_size_text(p_party)]
	if p_difficulty != Difficulty.NORMAL and Difficulty.is_valid(p_difficulty):
		text += " · " + Difficulty.name_of(p_difficulty)
	return text


## One row of the board: {"rank": "1", "result", "time", "party", "date"} (the end screen's table cells).
static func row_texts(rank_index: int, entry: Dictionary, p_mode: StringName) -> Dictionary:
	return {
		"rank": str(rank_index + 1),
		"result": result_text(entry, p_mode),
		"time": RunSummary.format_time(float(entry.get("time", 0.0))),
		"party": party_text(entry),
		"date": date_text(entry),
	}


## The "Best: ..." line of the end screen: the best entry of the category ("Best: Wave 31 · 18:22"), plus
## this run's place when it made the board ("  –  New best!" for the first place, "  –  This run: #3").
## [param p_rank] is the place [method record_run] returned (-1 = the run is not on the board).
static func best_line(p_best: Dictionary, p_mode: StringName, p_rank: int = -1) -> String:
	var line := "Best: %s" % (summary_text(p_best, p_mode) if not p_best.is_empty() else "–")
	if p_rank == 0:
		line += "  –  New best!"
	elif p_rank > 0:
		line += "  –  This run: #%d" % (p_rank + 1)
	return line


## What the end screen shows of the board after a run: {"mode", "hardcore", "party", "difficulty", "key" (the category),
## "category_text", "entries" (the category on [param board], best first), "rank" (the run's place in
## them, -1 = not on the board: it was not written or missed the top 10), "entry" (the run's own entry),
## "best" ({} = none yet), "line" (the "Best: ..." text), "error" ("" or why the file was not used),
## "save_failed" (the entry made the board but the file could not be written: see [method record_run])}.
## [param board] is the board read after the run was recorded ([method load_file]).
static func screen_model(board: Leaderboard, entry: Dictionary, p_mode: StringName, p_hardcore: bool,
		p_party: int, p_rank: int, p_save_failed: bool = false, p_difficulty: StringName = Difficulty.NORMAL) -> Dictionary:
	var entries := board.entries_for(p_mode, p_hardcore, p_party, p_difficulty)
	var best: Dictionary = entries[0] if not entries.is_empty() else {}
	var rank := p_rank if p_rank >= 0 and p_rank < entries.size() and not p_save_failed else -1
	var line := best_line(best, p_mode, rank)
	if board.load_error != "":
		line = "Leaderboard unavailable (%s)" % board.load_error
	return {
		"mode": p_mode,
		"hardcore": p_hardcore,
		"party": clampi(p_party, PARTY_MIN, PARTY_MAX),
		"difficulty": p_difficulty,
		"key": category_key(p_mode, p_hardcore, p_party, p_difficulty),
		"category_text": category_text(p_mode, p_hardcore, p_party, p_difficulty),
		"entries": entries,
		"rank": rank,
		"entry": entry,
		"best": best,
		"line": line,
		"error": board.load_error,
		"save_failed": p_save_failed,
	}


# --- Versions ---------------------------------------------------------------------------------

## [param data] (a parsed file) brought up to [param target] (the current format): each step of [method _migration_steps]
## turns version n into n + 1. A copy; a version above [param target] is left as it is. [param steps] replaces the table
## (tests).
static func migrate(data: Dictionary, target: int = FORMAT_VERSION, steps: Dictionary = {}) -> Dictionary:
	var table: Dictionary = steps if not steps.is_empty() else _migration_steps()
	var out: Dictionary = data.duplicate(true)
	var version := int(out.get("version", 0))
	while version < target:
		if table.has(version):
			var step: Callable = table[version]
			out = step.call(out)
		version += 1
		out["version"] = version
	return out


## {from version: Callable(Dictionary) -> Dictionary}. 1 -> 2 (M9): the difficulty arrived; every entry of a version 1
## file was a Normal run, so the plain keys stay as they are and each entry gets "difficulty": "normal".
static func _migration_steps() -> Dictionary:
	return {1: _migrate_1_to_2}


static func _migrate_1_to_2(data: Dictionary) -> Dictionary:
	var categories_in: Variant = data.get("categories", {})
	if categories_in is Dictionary:
		for key: Variant in categories_in:
			var list: Variant = categories_in[key]
			if list is Array:
				for e: Variant in list:
					if e is Dictionary and not (e as Dictionary).has("difficulty"):
						(e as Dictionary)["difficulty"] = String(Difficulty.NORMAL)
	return data


# --- Internals --------------------------------------------------------------------------------

## An existing board file that cannot be read: nothing is overwritten (the board is read-only).
func _set_unreadable(err: Error) -> Error:
	categories = {}
	read_only = true
	load_error = "unreadable"
	return err


func _set_corrupt() -> void:
	load_error = "corrupt"
	categories = {}
	var backup := path + ".corrupt"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	DirAccess.rename_absolute(path, backup)


## The categories of a parsed file as typed entries (JSON numbers come back as floats): bad entries
## are dropped, every list is sorted best first and cut to MAX_ENTRIES.
static func _sanitize(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in raw:
		if not (key is String) or not (raw[key] is Array):
			continue
		var mode := mode_of_key(key)
		var list: Array[Dictionary] = []
		for e: Variant in raw[key]:
			if e is Dictionary:
				list.append(_clean_entry(e))
		_sort_best_first(list, mode)
		while list.size() > MAX_ENTRIES:
			list.pop_back()
		out[key] = list
	return out


## Sorts [param list] best first, keeping the file's order among equal entries (an equal older entry stays
## above a newer one, as [method add_entry] put them). Each entry is paired with its index in the file and the
## index breaks every tie, so the order is total: Array.sort_custom (not stable by itself) gives the stable
## result in O(n log n) whatever the file holds.
static func _sort_best_first(list: Array[Dictionary], p_mode: StringName) -> void:
	var pairs: Array[Dictionary] = []
	for i in list.size():
		pairs.append({"entry": list[i], "index": i})
	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if better(a["entry"], b["entry"], p_mode):
			return true
		if better(b["entry"], a["entry"], p_mode):
			return false
		return int(a["index"]) < int(b["index"]))
	for i in pairs.size():
		var e: Dictionary = pairs[i]["entry"]
		list[i] = e


## [param e] with exactly the entry fields and their types (missing ones get neutral values; the date
## is kept as stored, even when empty).
static func _clean_entry(e: Dictionary) -> Dictionary:
	var classes: Array[String] = []
	var raw_classes: Variant = e.get("classes", [])
	if raw_classes is Array:
		for c: Variant in raw_classes:
			classes.append(String(c))
	return {
		"wave": maxi(int(e.get("wave", 0)), 0),
		"time": snappedf(maxf(float(e.get("time", 0.0)), 0.0), 0.1),
		"classes": classes,
		"date": String(e.get("date", "")),
		"victory": bool(e.get("victory", false)),
		"difficulty": String(e.get("difficulty", Difficulty.NORMAL)),
	}
