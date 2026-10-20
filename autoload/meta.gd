extends Node
## Autoload "Meta" (M9): the main profile and the meta-progression mechanisms around it. It owns the current
## [Profile], answers the unlock questions the content pools ask, and runs the run-end hook. What the profile means
## (Class Level curve, Seasonings, Heirlooms, achievements, difficulty tiers, Wardrobe) is content: later packages plug
## in through the listener registry, the unlock gates and the achievement data. See docs/ARCHITECTURE.md.
##
## Which profile (decided once at startup, [method configure_from_command_line]):
##   - a normal session: the player's file user://profile.json (read at startup, saved when something changes);
##   - an AUTOMATED run (smoke, demo, --view, --screenshot, headless, the unit tests; [method is_automated]): the
##     dev profile – everything unlocked, no raw-power bonus, nothing selected, Normal – and NO file IO at all, so
##     every automated run and test plays the base game;
##   - --profile=dev|fresh|max picks one of those profiles in memory (fresh: a new player; max: every class at the
##     top level and everything unlocked); --profile-path=FILE reads and saves that file instead of the player's
##     (the only way an automated run touches a profile file: tests and manual checks). With both, the named profile
##     is the starting point and FILE is written to; dev never touches a file.
##
## The unlock question: [method is_unlocked] (kind, id, class). Content is available unless a gate holds it back:
## class, ability, capstone_tree and legendary content is locked only when an [UnlockGateData] exists for it
## (data/unlocks/, or [method Db.add_unlock_gate]) and the profile has not unlocked it; collectibles (seasoning,
## heirloom, cosmetic, title, look) and the difficulty tiers above Normal are locked until the profile owns them.
## The pools call it: Db.ability_pool, TalentState (capstones), ItemGenerator / Forge (Legendaries), the lobby and
## the bots (classes), the difficulty selector ([Difficulty], data/difficulties/).
##
## The run-end hook: Main builds a [RunReport] and calls [method record_run] once. It dispatches the report to the
## registered listeners in priority order (the counters first, the achievement check last, in between whoever
## registered: Class XP, Seeds, Wardrobe ...), saves ONCE after all of them, then emits the signals. A dev profile
## records nothing. See [method add_run_listener].

## An achievement unlocked (after the profile was saved). The toast listens.
signal achievement_unlocked(id: StringName)
## The Seeds wallet changed by [param delta].
signal seeds_changed(seeds: int, delta: int)
## A run was recorded and saved; [param result] is [method record_run]'s result.
signal run_recorded(report: RunReport, result: Dictionary)
## [member profile] was replaced ([method configure]).
signal profile_replaced

const PROFILE_DEV := &"dev"
const PROFILE_FRESH := &"fresh"
const PROFILE_MAX := &"max"
const PROFILE_KINDS: Array[StringName] = [PROFILE_DEV, PROFILE_FRESH, PROFILE_MAX]

## Listener priorities of [method add_run_listener]: lower runs first, ties in registration order.
const PRIORITY_COUNTERS := -1000
const PRIORITY_DEFAULT := 0
const PRIORITY_ACHIEVEMENTS := 1000
## The built-in listeners: the run counters (AchievementEngine.update_counters) and the achievement check.
const LISTENER_COUNTERS := &"counters"
const LISTENER_ACHIEVEMENTS := &"achievements"

## Seeds an achievement pays once for every point it is worth (design: 615 points = 3075 Seeds).
const SEEDS_PER_POINT := 5
const LOCKED_HINT := "Locked"

## The current profile (never null after startup).
var profile: Profile = Profile.dev()
## The file the profile is saved to ("" = none).
var path := ""
## The profile is saved to [member path] when it changes.
var persist := false
## Times the profile file was written (a save that attempted IO; tests count them).
var save_count := 0
## The result of the last [method record_run].
var last_result: Dictionary = {}
## >= 0 replaces the clock of achievement unlock times (tests).
var clock_override := -1

var _listeners: Array[Dictionary] = []
var _order := 0
var _batching := false
var _pending_unlocks: Array[StringName] = []
var _warned_read_only := false


func _ready() -> void:
	_add_builtin_listeners()
	configure_from_command_line()


# --- Which profile ------------------------------------------------------------------------------

## True for runs that are not the player's session (smoke, demo, views, screenshots, headless, the test runner):
## the rule Settings uses.
func is_automated() -> bool:
	return Settings.is_automated_run()


## Picks the profile from the command line (--profile, --profile-path) and the automated rule.
func configure_from_command_line() -> void:
	var options := LaunchOptions.parse(OS.get_cmdline_user_args())
	configure(options.profile_kind, options.profile_path, is_automated())


## Replaces the profile (see the class doc). [param kind]: &"" (the default for this kind of session), or one of
## [constant PROFILE_KINDS]; [param p_path]: the file to read and save ("" = the player's file in a normal session,
## none otherwise); [param automated]: the launch is an automated one.
func configure(kind: StringName, p_path: String, automated: bool) -> void:
	path = ""
	persist = false
	_warned_read_only = false
	match kind:
		PROFILE_DEV:
			profile = Profile.dev()
		PROFILE_FRESH:
			profile = Profile.fresh()
		PROFILE_MAX:
			profile = Profile.max_profile(Db.class_ids)
		_:
			if p_path != "":
				profile = Profile.load_file(p_path)
			elif automated:
				profile = Profile.dev()
			else:
				profile = Profile.load_file(Profile.DEFAULT_PATH)
				path = Profile.DEFAULT_PATH
				persist = true
	if p_path != "" and not profile.is_dev:
		path = p_path
		persist = true
	profile_replaced.emit()


## True when a finished run changes the profile (everything but the dev profile).
func records_runs() -> bool:
	return profile != null and not profile.is_dev


## True for the dev profile of the automated runs.
func is_dev() -> bool:
	return profile == null or profile.is_dev


# --- Unlock checks ------------------------------------------------------------------------------

## Whether the content [param id] of [param kind] ([constant Profile.KINDS]) is available to the profile:
## [param class_id] is the class a class-scoped kind (the difficulty tiers) is asked for. The rules are in the class
## doc: collectibles need the profile's record, other content only when an unlock gate holds it back. The dev and
## max profiles answer true for everything.
func is_unlocked(kind: StringName, id: StringName, class_id: StringName = &"") -> bool:
	if profile == null or profile.all_unlocked:
		return true
	if kind == Profile.KIND_DIFFICULTY:
		return is_difficulty_unlocked(id, class_id)
	if kind in Profile.COLLECTIBLE_KINDS:
		return profile.has_unlock(kind, id, class_id)
	if Db.get_unlock_gate(kind, id) == null:
		return true
	return profile.has_unlock(kind, id, class_id)


## The text shown where the content is locked (its gate's hint, else "Locked").
func unlock_hint(kind: StringName, id: StringName) -> String:
	var gate := Db.get_unlock_gate(kind, id)
	return gate.hint if gate != null and gate.hint != "" else LOCKED_HINT


## Unlocks [param id] of [param kind] in the profile and saves. True when it was new.
func unlock(kind: StringName, id: StringName, class_id: StringName = &"") -> bool:
	if profile == null or not profile.unlock(kind, id, class_id):
		return false
	_changed()
	return true


# --- Classes ------------------------------------------------------------------------------------

func is_class_unlocked(class_id: StringName) -> bool:
	return is_unlocked(Profile.KIND_CLASS, class_id)


## The class ids the lobby offers as playable, in lobby order (every class with the dev profile; never empty).
func unlocked_class_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Db.class_ids:
		if is_class_unlocked(id):
			out.append(id)
	if out.is_empty() and not Db.class_ids.is_empty():
		out.append(Db.class_ids[0])
	return out


## The class a joining player starts on: the lobby's first class, or the first unlocked one.
func default_class() -> ClassData:
	var first := Db.get_default_class()
	if first != null and is_class_unlocked(first.id):
		return first
	var ids := unlocked_class_ids()
	return Db.get_class_data(ids[0]) if not ids.is_empty() else first


## Gives every slot whose class is locked the default class; returns how many were changed (Main.start_run: a
## locked class never reaches a run, whatever put it on the slot).
func enforce_class_locks(slots: Array[PlayerSlot]) -> int:
	var changed := 0
	for slot in slots:
		if slot.class_data != null and not is_class_unlocked(slot.class_data.id):
			push_warning("Meta: %s plays %s, which is locked – using %s" % [slot.label(), slot.class_data.id, default_class().id])
			slot.class_data = default_class()
			changed += 1
	return changed


## The Class Level of [param class_id] (1 for the dev profile).
func class_level(class_id: StringName) -> int:
	return 1 if profile == null or profile.is_dev else profile.class_level(class_id)


## The Class Level raw-power bonuses apply (false in automated runs: the base game).
func raw_power_enabled() -> bool:
	return profile != null and profile.raw_power


# --- Difficulty ---------------------------------------------------------------------------------

## Whether the difficulty tier [param tier] (a [Difficulty] id, data/difficulties/) is open for [param class_id]: the
## first tier always, the others once the profile unlocked them for the class (the class-pair achievements do:
## winning with a class opens the next tier for it).
func is_difficulty_unlocked(tier: StringName, class_id: StringName) -> bool:
	if profile == null or profile.all_unlocked:
		return true
	var at := Difficulty.tier_index(tier)
	if at <= 0:
		return at == 0
	return profile.has_unlock(Profile.KIND_DIFFICULTY, tier, class_id)


## The highest tier every class of [param class_ids] has unlocked: the cap of the party's difficulty select.
func party_difficulty_cap(class_ids: Array[StringName]) -> StringName:
	var tiers := Difficulty.ids()
	if tiers.is_empty():
		return Difficulty.NORMAL
	var best := tiers[0]
	for tier in tiers:
		var open := true
		for id in class_ids:
			if not is_difficulty_unlocked(tier, id):
				open = false
		if not open:
			break
		best = tier
	return best


## [param tier] when a party of [param class_ids] may play it, else the highest tier it may (Main.start_run: a tier
## the heroes have not unlocked never reaches a run, whatever put it there).
func clamp_difficulty(tier: StringName, class_ids: Array[StringName]) -> StringName:
	var wanted := Difficulty.tier_index(tier)
	var cap := Difficulty.tier_index(party_difficulty_cap(class_ids))
	if wanted < 0:
		return Difficulty.NORMAL
	return tier if wanted <= cap else Difficulty.ids()[cap]


# --- Seeds --------------------------------------------------------------------------------------

func seeds() -> int:
	return profile.seeds if profile != null else 0


func can_afford_seeds(amount: int) -> bool:
	return profile != null and profile.can_afford(amount)


## Adds [param amount] Seeds; returns the wallet. Saved at once (inside [method record_run] with the run).
func earn_seeds(amount: int) -> int:
	if profile == null or amount <= 0:
		return seeds()
	var total := profile.earn_seeds(amount)
	seeds_changed.emit(total, amount)
	_changed()
	return total


## Pays [param amount] Seeds. False (nothing changes) when the wallet holds less.
func spend_seeds(amount: int) -> bool:
	if profile == null or amount < 0 or not profile.spend_seeds(amount):
		return false
	if amount > 0:
		seeds_changed.emit(profile.seeds, -amount)
		_changed()
	return true


# --- Lobby selections ---------------------------------------------------------------------------

## [param loadout] ([method Profile.loadout]) without what the profile has not unlocked (Seasonings, a Heirloom, looks).
func sanitize_loadout(loadout: Dictionary, class_id: StringName = &"") -> Dictionary:
	var l := Profile.normalize_loadout(loadout)
	var seasonings: Array[StringName] = []
	for s: StringName in l["seasonings"]:
		if is_unlocked(Profile.KIND_SEASONING, s, class_id):
			seasonings.append(s)
	l["seasonings"] = seasonings
	if l["heirloom"] != &"" and not is_unlocked(Profile.KIND_HEIRLOOM, l["heirloom"], class_id):
		l["heirloom"] = &""
	var looks: Dictionary[StringName, StringName] = {}
	for slot: StringName in l["looks"]:
		if is_unlocked(Profile.KIND_LOOK, l["looks"][slot], class_id):
			looks[slot] = l["looks"][slot]
	l["looks"] = looks
	return l


## The selections remembered for [param class_id], limited to what is unlocked. Empty for the dev profile (nothing
## selected in automated runs).
func remembered_loadout(class_id: StringName) -> Dictionary:
	if is_dev():
		return Profile.normalize_loadout({})
	return sanitize_loadout(profile.loadout(class_id), class_id)


## Puts the selections remembered for the class of [param slot] on it (the lobby calls it when a player joins or
## changes class). A dev profile leaves the slot as it is.
func apply_loadout(slot: PlayerSlot) -> void:
	if slot == null or slot.class_data == null or is_dev():
		return
	slot.set_meta_loadout(remembered_loadout(slot.class_data.id))


## Remembers the selections of [param slot] for its class (Main.start_run). Kept in memory; the run's end saves.
func remember_loadout(slot: PlayerSlot) -> void:
	if slot == null or slot.class_data == null or is_dev():
		return
	profile.set_loadout(slot.class_data.id, slot.meta_loadout())


# --- Achievements -------------------------------------------------------------------------------

## Checks every achievement against the profile and [param report] (null = no run: the report conditions are false),
## unlocks what holds, saves, and emits [signal achievement_unlocked] for each. Returns the new ids. A dev profile
## unlocks nothing.
func check_achievements(report: RunReport = null) -> Array[StringName]:
	if not records_runs():
		return []
	var ids := AchievementEngine.evaluate(profile, report, Db.achievement_list(), now())
	_pending_unlocks.append_array(ids)
	_pay_achievements(ids)
	if not ids.is_empty():
		_changed()
	_flush_unlocks()
	return ids


## What new achievements bring besides their rewards: their Seeds ([constant SEEDS_PER_POINT] per point, paid once) and
## the title the achievement score earns now ([PlayerTitles.POINT_TITLES]). Returns {"seeds": int, "titles":
## Array[StringName]}.
func _pay_achievements(ids: Array[StringName]) -> Dictionary:
	var paid := {"seeds": 0, "titles": [] as Array[StringName]}
	if ids.is_empty() or profile == null:
		return paid
	var seeds_total := 0
	for id in ids:
		var data := Db.get_achievement(id)
		if data != null:
			seeds_total += data.points * SEEDS_PER_POINT
	if seeds_total > 0:
		earn_seeds(seeds_total)
	paid["seeds"] = seeds_total
	paid["titles"] = PlayerTitles.grant_for_points(profile, achievement_points())
	return paid


## The profile's achievement score (the points of the unlocked achievements).
func achievement_points() -> int:
	return AchievementEngine.points_of(profile, Db.achievement_list()) if profile != null else 0


## Unix seconds (the unlock times of the profile).
func now() -> int:
	return clock_override if clock_override >= 0 else int(Time.get_unix_time_from_system())


# --- The run-end hook ---------------------------------------------------------------------------

## Registers [param callable] to run when a run is recorded: [code]func(report: RunReport, profile: Profile, result:
## Dictionary) -> void[/code]. [param result] is the dictionary [method record_run] returns – a listener adds its own
## keys to it (xp gained, Seeds earned, new looks ...). Lower [param priority] runs first, ties in registration order;
## the counters run at [constant PRIORITY_COUNTERS] and the achievement check at [constant PRIORITY_ACHIEVEMENTS]
## (so a listener at the default priority sees the run's counters and is seen by the achievements). Registering an
## id again replaces the listener (and its place in the order).
func add_run_listener(id: StringName, callable: Callable, priority: int = PRIORITY_DEFAULT) -> void:
	remove_run_listener(id)
	_order += 1
	_listeners.append({"id": id, "callable": callable, "priority": priority, "order": _order})


func remove_run_listener(id: StringName) -> void:
	for i in range(_listeners.size() - 1, -1, -1):
		if _listeners[i]["id"] == id:
			_listeners.remove_at(i)


## The listener ids in dispatch order.
func listener_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for l in _sorted_listeners():
		out.append(l["id"])
	return out


## Records a finished run (Main calls it once at the end of a run, also for an abandoned one): the counters, every
## listener in order, the achievement check, then ONE save, then the signals. Does nothing (and returns
## {"recorded": false}) for the dev profile, a null report or a report recorded before. Returns {"recorded": true,
## "listeners": [ids in the order they ran], "achievements": [ids unlocked by this run], "save_error": Error
## (OK also when nothing is written)} plus whatever the listeners added.
func record_run(report: RunReport) -> Dictionary:
	var result: Dictionary = {"recorded": false}
	if report == null or report.recorded or not records_runs():
		last_result = result
		return result
	report.recorded = true
	result = {"recorded": true, "listeners": [] as Array[StringName], "achievements": [] as Array[StringName], "save_error": OK}
	_batching = true
	for l in _sorted_listeners():
		(result["listeners"] as Array[StringName]).append(l["id"])
		var callable: Callable = l["callable"]
		if callable.is_valid():
			callable.call(report, profile, result)
		else:
			push_warning("Meta: the run listener '%s' is no longer valid" % l["id"])
	_batching = false
	result["save_error"] = _write()
	var unlocked: Array[StringName] = []
	unlocked.append_array(_pending_unlocks)
	result["achievements"] = unlocked
	last_result = result
	_flush_unlocks()
	run_recorded.emit(report, result)
	return result


# --- Saving -------------------------------------------------------------------------------------

## Writes the profile to [member path] now ([member persist] only; a dev profile never). Returns the Error (OK also when
## nothing is written). Inside [method record_run] the write waits for the end of the dispatch.
func save() -> Error:
	if _batching:
		return OK
	return _write()


func _write() -> Error:
	if not persist or path == "" or profile == null or profile.is_dev:
		return OK
	if profile.read_only:
		if not _warned_read_only:
			_warned_read_only = true
			push_warning("Meta: %s is not saved (%s)" % [path, profile.load_error])
		return ERR_FILE_NO_PERMISSION
	save_count += 1
	var err := profile.save_file(path)
	if err != OK:
		push_warning("Meta: could not write %s (%s)" % [path, error_string(err)])
	return err


## A change outside the run-end dispatch is saved at once.
func _changed() -> void:
	if not _batching:
		_write()


## Emits [signal achievement_unlocked] for the unlocks waiting (after the save that recorded them; inside the
## run-end dispatch they wait for its end).
func _flush_unlocks() -> void:
	if _batching or _pending_unlocks.is_empty():
		return
	var ids := _pending_unlocks.duplicate()
	_pending_unlocks.clear()
	for id in ids:
		achievement_unlocked.emit(id)


# --- Built-in listeners -------------------------------------------------------------------------

func _add_builtin_listeners() -> void:
	add_run_listener(LISTENER_COUNTERS, _on_counters, PRIORITY_COUNTERS)
	add_run_listener(LISTENER_ACHIEVEMENTS, _on_achievements, PRIORITY_ACHIEVEMENTS)


func _on_counters(report: RunReport, p: Profile, _result: Dictionary) -> void:
	AchievementEngine.update_counters(p, report)


func _on_achievements(report: RunReport, p: Profile, result: Dictionary) -> void:
	var ids := AchievementEngine.evaluate(p, report, Db.achievement_list(), now())
	_pending_unlocks.append_array(ids)
	var paid := _pay_achievements(ids)
	result["achievement_seeds"] = paid["seeds"]
	result["point_titles"] = paid["titles"]


func _sorted_listeners() -> Array[Dictionary]:
	var out := _listeners.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["priority"] != b["priority"]:
			return a["priority"] < b["priority"]
		return a["order"] < b["order"])
	var typed: Array[Dictionary] = []
	typed.assign(out)
	return typed
