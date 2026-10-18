class_name Leaderboard
extends RefCounted
## The local leaderboard (GDD 16.1, M6b MODES): per category – (mode, hardcore, party size) – the best
## MAX_ENTRIES runs, kept in a small versioned JSON file (user://leaderboard.json). This class is the
## pure data model plus the file IO; what the end screen shows of it is the MODES package.
##
## File format (FORMAT_VERSION 1):
##   {"version": 1, "categories": {"normal/standard/2": [entry, ...], "endless/hardcore/4": [...]}}
## An entry: {"wave": int (the wave reached: the last wave cleared on a victory, the wave that ended
## the run on a defeat), "time": float (seconds of wave play, RunState.run_time), "classes": [class
## ids in slot order], "date": "YYYY-MM-DD HH:MM:SS", "victory": bool}. Entries of a category are
## kept best first ([method better]): a normal run ranks victories by the shortest time, then
## defeats by the highest wave; an endless run ranks by the highest wave, then the shortest time.
##
## - The path is injectable: [code]Leaderboard.create(path)[/code] works on any file (tests use a temp
##   path). [method default_path] is the real file ([member path_override] replaces it in tests).
## - A missing file is an empty board. A file that cannot be parsed is moved to "<path>.corrupt" and
##   the board starts empty ([member load_error] says so). A file of a NEWER version is never
##   overwritten: the board is [member read_only] (the entries stay readable but [method save_file]
##   refuses), so an old build cannot destroy a newer build's data.
## - [method record_run] is the one call the game makes at a run's end. It writes nothing while
##   [member writes_enabled] is false: tests/run_tests.gd switches it off, and Main skips the call in
##   smoke / demo / screenshot runs ([method Main.writes_leaderboard]). A test that wants to exercise
##   it sets [member path_override] to a temp path and [member writes_enabled] to true, and restores both.

const FORMAT_VERSION := 1
const DEFAULT_PATH := "user://leaderboard.json"
const MAX_ENTRIES := 10
const PARTY_MIN := 1
const PARTY_MAX := 4

## Master switch of [method record_run] (the unit test runner switches it off).
static var writes_enabled := true
## Replaces [constant DEFAULT_PATH] when not empty (tests).
static var path_override := ""

## The file this board reads and writes.
var path := ""
## Category key -> Array[Dictionary] of entries, best first (at most MAX_ENTRIES each).
var categories: Dictionary = {}
## "" = loaded fine (or no file); else why the file was not used: "corrupt" or "newer version".
var load_error := ""
## The file is of a newer version: [method save_file] refuses.
var read_only := false


## A board for [param p_path] ("" = [method default_path]); call [method load_file] to read it.
static func create(p_path: String = "") -> Leaderboard:
	var b := Leaderboard.new()
	b.path = p_path if p_path != "" else default_path()
	return b


static func default_path() -> String:
	return path_override if path_override != "" else DEFAULT_PATH


## The category of a run: "normal/standard/2", "endless/hardcore/4" (party size clamped to 1..4,
## an unknown mode counts as normal).
static func category_key(p_mode: StringName, p_hardcore: bool, p_party: int) -> String:
	var mode := p_mode if p_mode in RunState.MODES else RunState.MODE_NORMAL
	return "%s/%s/%d" % [mode, "hardcore" if p_hardcore else "standard", clampi(p_party, PARTY_MIN, PARTY_MAX)]


## The mode a [method category_key] belongs to.
static func mode_of_key(key: String) -> StringName:
	var mode := StringName(key.get_slice("/", 0))
	return mode if mode in RunState.MODES else RunState.MODE_NORMAL


## A well-formed entry. [param p_date] "" = now (system time).
static func make_entry(p_wave: int, p_time: float, p_classes: Array, p_victory: bool, p_date: String = "") -> Dictionary:
	var classes: Array[String] = []
	for c in p_classes:
		classes.append(String(c))
	return {
		"wave": maxi(p_wave, 0),
		"time": snappedf(maxf(p_time, 0.0), 0.1),
		"classes": classes,
		"date": p_date if p_date != "" else Time.get_datetime_string_from_system(false, true),
		"victory": p_victory,
	}


## True when entry [param a] ranks above [param b] in a [param p_mode] board (see the class doc).
## Ties are not "better" (a new entry goes below an equal older one).
static func better(a: Dictionary, b: Dictionary, p_mode: StringName) -> bool:
	var a_wave := int(a.get("wave", 0))
	var b_wave := int(b.get("wave", 0))
	var a_time := float(a.get("time", 0.0))
	var b_time := float(b.get("time", 0.0))
	if p_mode == RunState.MODE_ENDLESS:
		if a_wave != b_wave:
			return a_wave > b_wave
		return a_time < b_time - 0.00001
	var a_won := bool(a.get("victory", false))
	var b_won := bool(b.get("victory", false))
	if a_won != b_won:
		return a_won
	if a_won:
		return a_time < b_time - 0.00001
	if a_wave != b_wave:
		return a_wave > b_wave
	return a_time < b_time - 0.00001


# --- Reading ----------------------------------------------------------------------------------

## The entries of a category, best first (a copy; empty = none yet).
func entries_for(p_mode: StringName, p_hardcore: bool, p_party: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in categories.get(category_key(p_mode, p_hardcore, p_party), []):
		out.append(e.duplicate(true))
	return out


## The best entry of a category ({} = none yet).
func best_for(p_mode: StringName, p_hardcore: bool, p_party: int) -> Dictionary:
	var list := entries_for(p_mode, p_hardcore, p_party)
	return list[0] if not list.is_empty() else {}


## Where [param entry] would land in its category (0 = best), -1 when it would not make the top
## MAX_ENTRIES. Changes nothing.
func rank_of(entry: Dictionary, p_mode: StringName, p_hardcore: bool, p_party: int) -> int:
	var list: Array = categories.get(category_key(p_mode, p_hardcore, p_party), [])
	var at := list.size()
	for i in list.size():
		if better(entry, list[i], p_mode):
			at = i
			break
	return at if at < MAX_ENTRIES else -1


# --- Writing ----------------------------------------------------------------------------------

## Adds [param entry] to its category (best first, the list cut to MAX_ENTRIES). Returns its rank
## (0 = the new best), -1 when it did not make the board (then nothing changed). Does not save.
func add_entry(entry: Dictionary, p_mode: StringName, p_hardcore: bool, p_party: int) -> int:
	var at := rank_of(entry, p_mode, p_hardcore, p_party)
	if at < 0:
		return -1
	var key := category_key(p_mode, p_hardcore, p_party)
	var list: Array = categories.get(key, [])
	list.insert(at, entry.duplicate(true))
	while list.size() > MAX_ENTRIES:
		list.pop_back()
	categories[key] = list
	return at


## Reads [member path]. Returns OK for a missing file (an empty board) and for a readable one; an
## unreadable or corrupt file leaves the board empty, sets [member load_error] and moves the file to
## "<path>.corrupt"; a newer version leaves the board empty, sets [member read_only] and
## [member load_error].
func load_file() -> Error:
	categories = {}
	load_error = ""
	read_only = false
	if not FileAccess.file_exists(path):
		return OK
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_error = "unreadable"
		return FileAccess.get_open_error()
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
## category, saves, and returns the entry's rank (-1 = not in the top MAX_ENTRIES, or nothing written:
## [member writes_enabled] is false, or the file is of a newer version).
static func record_run(entry: Dictionary, p_mode: StringName, p_hardcore: bool, p_party: int) -> int:
	if not writes_enabled:
		return -1
	var board := create()
	board.load_file()
	if board.read_only:
		return -1
	var rank := board.add_entry(entry, p_mode, p_hardcore, p_party)
	if rank >= 0 and board.save_file() != OK:
		return -1
	return rank


# --- Internals --------------------------------------------------------------------------------

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
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return better(a, b, mode))
		while list.size() > MAX_ENTRIES:
			list.pop_back()
		out[key] = list
	return out


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
	}
