extends TestCase
## M9 P0-META: the main profile (model, JSON file, migration, corrupt / newer files), the dev / fresh / max profiles
## and the launch flags, automated runs never touching a profile file, the unlock checks and the content pools they
## filter (lobby classes, the level-up ability deck, capstones incl. the bots, hand-made and forged Legendaries, the
## difficulty tiers), the run-end hook (listener order, one save, signals, Main's calls), the achievement engine on
## fake data, the Seeds wallet and the per-slot lobby selections.

const UiFakes := preload("res://tests/ui_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const Fakes := preload("res://tests/player_fakes.gd")
const Support := preload("res://tests/test_loot_support.gd")
const DT := 1.0 / 60.0

var _tmp_path := "user://m9_meta_core_test_%d.json" % OS.get_process_id()
var _saved_profile: Profile
var _saved_path := ""
var _saved_persist := false
var _saved_clock := -1
var _saved_listeners: Array[Dictionary] = []
var _saved_gates: Dictionary[StringName, UnlockGateData] = {}
var _saved_achievements: Dictionary[StringName, AchievementData] = {}
var _nodes: Array[Node] = []
var main: Main
var world: Node3D
var order: Array[StringName] = []
var reports: Array[RunReport] = []
var rng: RandomNumberGenerator


func before_each() -> void:
	_saved_profile = Meta.profile
	_saved_path = Meta.path
	_saved_persist = Meta.persist
	_saved_clock = Meta.clock_override
	_saved_listeners = Meta._listeners.duplicate()
	_saved_gates = Db.unlock_gates.duplicate()
	_saved_achievements = Db.achievements.duplicate()
	Db.achievements = {}  # (these tests run the mechanisms on fake data; the real 40 are tested in test_m9_achievements)
	# The mechanism tests run on their own gates and listeners, not the shipped content's (M9 LEVELS: the class / ability /
	# capstone gates and the Class XP / Seeds listeners; tests/test_m9_levels.gd covers those).
	Db.unlock_gates.clear()
	Meta.remove_run_listener(ClassLevels.LISTENER_XP)
	Meta.remove_run_listener(ClassLevels.LISTENER_SEEDS)
	Meta.remove_run_listener(Wardrobe.LISTENER)  # (M9 WARDROBE: tests/test_m9_wardrobe.gd covers the looks)
	Meta.save_count = 0
	Meta._pending_unlocks.clear()
	UiFakes.reset_players()
	tree.paused = false
	rng = RandomNumberGenerator.new()
	rng.seed = 909
	order.clear()
	reports.clear()


func after_each() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	if world != null:
		EFakes.free_world(tree, world)
		world = null
	for n in _nodes:
		UiFakes.free_node(n)
	_nodes.clear()
	Meta.profile = _saved_profile
	Meta.path = _saved_path
	Meta.persist = _saved_persist
	Meta.clock_override = _saved_clock
	Meta._listeners = _saved_listeners
	Meta._pending_unlocks.clear()
	Meta._batching = false
	Db.unlock_gates = _saved_gates
	Db.achievements = _saved_achievements
	for kind in ["test_cond", "test_cond_b"]:
		AchievementEngine.unregister_condition(StringName(kind))
	Profile.write_limit = -1
	for suffix in ["", ".tmp", ".corrupt", ".bak"]:
		if FileAccess.file_exists(_tmp_path + suffix):
			DirAccess.remove_absolute(_tmp_path + suffix)
	if DirAccess.dir_exists_absolute(_tmp_path + "_dir"):
		DirAccess.remove_absolute(_tmp_path + "_dir")
	tree.paused = false
	UiFakes.reset_players()
	Enemy.invalidate_player_cache()


# --- Helpers ------------------------------------------------------------------------------------

func _gate(kind: StringName, id: StringName, hint: String = "") -> UnlockGateData:
	var g := UnlockGateData.new()
	g.kind = kind
	g.id = id
	g.hint = hint
	Db.add_unlock_gate(g)
	return g


## A real player profile in memory (no file) as the current one.
func _use_fresh() -> Profile:
	Meta.profile = Profile.fresh()
	Meta.persist = false
	Meta.path = ""
	return Meta.profile


## A real player profile saved to the temp file as the current one.
func _use_file() -> Profile:
	Meta.profile = Profile.fresh()
	Meta.persist = true
	Meta.path = _tmp_path
	return Meta.profile


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _party(ids: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in ids:
		out.append(StringName(str(id)))
	return out


func _report(victory: bool = true, p_stats: Dictionary = {}, ids: Array = ["warrior"], p_flags: Dictionary = {},
		p_heroes: Array[Dictionary] = []) -> RunReport:
	return RunReport.make(_party(ids), victory, p_stats, p_flags, p_heroes)


func _achievement(id: String, kind: StringName, params: Dictionary, rewards: Array[Dictionary] = [], points: int = 0) -> AchievementData:
	var a := AchievementData.new()
	a.id = StringName(id)
	a.display_name = id.capitalize()
	a.condition_kind = kind
	a.condition_params = params
	a.rewards = rewards
	a.points = points
	return a


func _defs(list: Array) -> Array[AchievementData]:
	var out: Array[AchievementData] = []
	for a: Variant in list:
		out.append(a)
	return out


func _make_main(opts: LaunchOptions = null) -> Main:
	main = Main.create(opts if opts != null else LaunchOptions.new())
	tree.root.add_child(main)
	return main


func _run_with_bots(count: int) -> void:
	_make_main()
	for i in count:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)
	main.start_run()


func _hero(index: int, level: int, trees: Array[TalentTreeData] = []) -> Player:
	RunState.set_start_level(level)
	var p := Fakes.spawn_player(world, index, &"warrior", Vector3(index * 6.0, 0, 0))
	if not trees.is_empty():
		p.talents = TalentState.create(&"warrior", trees)
		p.talents.changed.connect(p._on_talents_changed)
	return p


func _track(listener_id: StringName, priority: int = 0, seeds_each: int = 0) -> void:
	var listener := func(report: RunReport, p: Profile, _result: Dictionary) -> void:
		order.append(listener_id)
		reports.append(report)
		if seeds_each > 0:
			Meta.earn_seeds(seeds_each)
		order.append(StringName("runs=%d" % p.counter(&"runs")))
	Meta.add_run_listener(listener_id, listener, priority)


func _free_main() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null


# --- Profile model ------------------------------------------------------------------------------

func test_a_fresh_profile_has_nothing() -> void:
	var p := Profile.fresh()
	check(not p.is_dev and not p.all_unlocked and p.raw_power, "a normal player profile")
	check_eq(p.class_level(&"warrior"), 1, "level 1")
	check_eq(p.class_xp(&"warrior"), 0, "no XP")
	check_eq(p.seeds, 0, "no Seeds")
	check(p.unlocks.is_empty() and p.achievements.is_empty() and p.counters.is_empty(), "nothing earned")
	check(not p.has_unlock(Profile.KIND_CLASS, &"hunter"), "nothing unlocked")
	check_eq(p.selected_title, &"", "no title")
	check_eq(p.loadout(&"warrior"), Profile.normalize_loadout({}), "an empty loadout")


func test_the_dev_profile_is_everything_unlocked_and_no_power() -> void:
	var p := Profile.dev()
	check(p.is_dev and p.all_unlocked and not p.raw_power, "dev: all unlocked, no raw power")
	check(p.has_unlock(Profile.KIND_SEASONING, &"anything"), "any unlock check is true")
	check_eq(p.class_level(&"warrior"), 1, "level 1: no bonus")
	check_eq(p.seeds, 0, "no Seeds")
	check_eq(p.loadout(&"warrior"), Profile.normalize_loadout({}), "nothing selected")
	check_eq(p.save_file(_tmp_path), ERR_FILE_NO_PERMISSION, "never saved")
	check(not FileAccess.file_exists(_tmp_path), "no file appeared")


func test_the_max_profile_has_every_class_at_the_top() -> void:
	var p := Profile.max_profile(Db.class_ids)
	check(p.all_unlocked and p.raw_power and not p.is_dev, "max: everything unlocked, raw power on")
	for id in Db.class_ids:
		check_eq(p.class_level(id), Profile.MAX_CLASS_LEVEL, "%s at the top level" % id)
	check_eq(Profile.MAX_CLASS_LEVEL, 30, "GDD 17.2: 30 levels")


func test_class_xp_adds_up_and_the_level_never_drops() -> void:
	var p := Profile.fresh()
	check_eq(p.add_class_xp(&"warrior", 120), 120, "XP")
	check_eq(p.add_class_xp(&"warrior", 30), 150, "two heroes of a class add up")
	check_eq(p.add_class_xp(&"warrior", -50), 150, "a negative amount adds nothing")
	check_eq(p.class_xp(&"mage"), 0, "another class is untouched")
	p.set_class_progress(&"warrior", 150, 7)
	check_eq(p.class_level(&"warrior"), 7, "level stored")
	p.set_class_progress(&"warrior", 200, 3)
	check_eq(p.class_level(&"warrior"), 7, "the level never drops")
	p.set_class_progress(&"mage", -5, 99)
	check_eq(p.class_level(&"mage"), Profile.MAX_CLASS_LEVEL, "level clamped to 30")
	check_eq(p.class_xp(&"mage"), 0, "XP clamped to 0")
	p.add_class_xp(&"", 10)
	check(not p.classes.has(&""), "no class, no entry")


func test_unlocks_are_sets_by_kind_and_difficulty_is_per_class() -> void:
	var p := Profile.fresh()
	check(p.unlock(Profile.KIND_ABILITY, &"a"), "new")
	check(not p.unlock(Profile.KIND_ABILITY, &"a"), "not new twice")
	check(p.has_unlock(Profile.KIND_ABILITY, &"a") and not p.has_unlock(Profile.KIND_SEASONING, &"a"), "kinds are separate")
	p.unlock(Profile.KIND_ABILITY, &"b")
	check_eq(p.unlocked_ids(Profile.KIND_ABILITY), [&"a", &"b"] as Array[StringName], "sorted ids")
	check(p.unlock(Profile.KIND_DIFFICULTY, &"pungent", &"warrior"), "a class's tier")
	check(p.has_unlock(Profile.KIND_DIFFICULTY, &"pungent", &"warrior"), "unlocked for the warrior")
	check(not p.has_unlock(Profile.KIND_DIFFICULTY, &"pungent", &"mage"), "not for the mage")
	check(p.unlocks.has(&"difficulty:warrior"), "stored per class")
	check(not p.unlock(&"", &"x") and not p.unlock(Profile.KIND_TITLE, &""), "empty kind / id record nothing")


func test_achievements_counters_and_best_counters() -> void:
	var p := Profile.fresh()
	check(p.unlock_achievement(&"first", 1234), "unlocked")
	check(not p.unlock_achievement(&"first", 99), "only once")
	check_eq(p.achievements[&"first"], 1234, "the first time stays")
	check(p.has_achievement(&"first") and not p.has_achievement(&"second"), "has")
	check_eq(p.add_counter(&"kills", 5), 5, "counter")
	check_eq(p.add_counter(&"kills", 7), 12, "counter adds")
	check_eq(p.raise_counter(&"best", 9), 9, "best")
	check_eq(p.raise_counter(&"best", 4), 9, "best does not drop")
	check_eq(p.counter(&"nothing"), 0, "unknown counter is 0")


func test_the_seeds_wallet() -> void:
	var p := Profile.fresh()
	check(p.can_afford(0) and not p.can_afford(1), "empty wallet")
	check_eq(p.earn_seeds(30), 30, "earn")
	check_eq(p.earn_seeds(-5), 30, "a negative earn adds nothing")
	check(p.can_afford(30) and not p.can_afford(31), "can_afford")
	check(p.spend_seeds(12), "spend")
	check_eq(p.seeds, 18, "wallet")
	check(not p.spend_seeds(19), "too poor")
	check_eq(p.seeds, 18, "nothing taken")
	check(p.spend_seeds(18) and p.seeds == 0, "spend it all")
	check_eq(p.seeds_earned, 30, "the life total ignores spending")


func test_heirloom_ranks() -> void:
	var p := Profile.fresh()
	check_eq(p.heirloom_rank(&"old_ladle"), 0, "not owned")
	p.unlock(Profile.KIND_HEIRLOOM, &"old_ladle")
	check_eq(p.heirloom_rank(&"old_ladle"), 1, "owned: rank 1")
	p.set_heirloom_rank(&"old_ladle", 4)
	check_eq(p.heirloom_rank(&"old_ladle"), 4, "ranked")
	p.set_heirloom_rank(&"old_ladle", 1)
	check_eq(p.heirloom_rank(&"old_ladle"), 1, "back to the first rank")
	check(p.heirloom_ranks.is_empty(), "rank 1 stores nothing")
	p.set_heirloom_rank(&"cracked_pan", 2)
	check(p.has_unlock(Profile.KIND_HEIRLOOM, &"cracked_pan"), "ranking an heirloom owns it")


func test_loadouts_are_normalised_and_kept_per_class() -> void:
	var p := Profile.fresh()
	p.set_loadout(&"warrior", {"seasonings": [&"a", "b", &"a", ""], "heirloom": "ladle", "looks": {"head": "helm", "chest": ""}, "junk": 1})
	var l := p.loadout(&"warrior")
	check_eq(l["seasonings"], [&"a", &"b"] as Array[StringName], "seasonings: unique, no empty ids")
	check_eq(l["heirloom"], &"ladle", "heirloom")
	check_eq((l["looks"] as Dictionary).size(), 1, "a look without an id is dropped")
	check(not l.has("junk"), "unknown keys are dropped")
	check_eq(p.loadout(&"mage"), Profile.normalize_loadout({}), "another class: empty")
	l["seasonings"].append(&"c")
	check_eq((p.loadout(&"warrior")["seasonings"] as Array).size(), 2, "the read is a copy")


# --- Profile file -------------------------------------------------------------------------------

func _rich_profile() -> Profile:
	var p := Profile.fresh()
	p.created_at = 1700000000
	p.set_class_progress(&"warrior", 340, 6)
	p.add_class_xp(&"mage", 50)
	p.unlock(Profile.KIND_CLASS, &"hunter")
	p.unlock(Profile.KIND_ABILITY, &"whirlwind")
	p.unlock(Profile.KIND_DIFFICULTY, &"pungent", &"warrior")
	p.unlock(Profile.KIND_TITLE, &"the_unbreakable")
	p.set_heirloom_rank(&"old_ladle", 3)
	p.unlock_achievement(&"first_blood", 1700000500)
	p.add_counter(&"runs", 4)
	p.earn_seeds(25)
	p.spend_seeds(5)
	p.set_loadout(&"warrior", {"seasonings": [&"smoked"], "heirloom": &"old_ladle", "looks": {"head": &"iron_helm"}})
	p.selected_title = &"the_unbreakable"
	return p


func test_a_profile_round_trips_through_its_file() -> void:
	var p := _rich_profile()
	check_eq(p.save_file(_tmp_path), OK, "saved")
	check(not FileAccess.file_exists(_tmp_path + ".tmp"), "no temporary file left")
	var json: Dictionary = JSON.parse_string(_read(_tmp_path))
	check_eq(int(json["version"]), Profile.FORMAT_VERSION, "version 1 in the file")
	check_eq(Profile.FORMAT_VERSION, 1, "the first format")
	var back := Profile.load_file(_tmp_path)
	check_eq(back.load_error, "", "loaded fine")
	check(not back.read_only and not back.is_new, "writable, not new")
	check_eq(back.to_dict(), p.to_dict(), "the same data")
	check_eq(back.class_level(&"warrior"), 6, "level")
	check_eq(back.class_xp(&"mage"), 50, "XP")
	check(back.has_unlock(Profile.KIND_DIFFICULTY, &"pungent", &"warrior"), "scoped unlock")
	check_eq(back.heirloom_rank(&"old_ladle"), 3, "heirloom rank")
	check_eq(back.achievements[&"first_blood"], 1700000500, "achievement time (an int again)")
	check_eq(back.seeds, 20, "Seeds")
	check_eq(back.selected_title, &"the_unbreakable", "title")


func test_a_saved_max_profile_stays_max_and_a_players_file_never_is() -> void:
	var m := Profile.max_profile(Db.class_ids)
	m.save_file(_tmp_path)
	var back := Profile.load_file(_tmp_path)
	check(back.all_unlocked and not back.is_dev, "max: everything unlocked after a reload")
	check_eq(back.class_level(Db.class_ids[0]), 30, "and the levels")
	check(not Profile.from_dict(_rich_profile().to_dict()).all_unlocked, "a normal profile is not")
	check(not _rich_profile().to_dict().has("all_unlocked"), "its file has no such key")
	check(not Profile.from_dict({"all_unlocked": "yes"}).all_unlocked, "only a real true counts")


func test_saving_replaces_the_old_file() -> void:
	var p := Profile.fresh()
	p.earn_seeds(1)
	check_eq(p.save_file(_tmp_path), OK, "first save")
	p.earn_seeds(1)
	check_eq(p.save_file(_tmp_path), OK, "second save over the first")
	check_eq(Profile.load_file(_tmp_path).seeds, 2, "the newer data")
	check(not FileAccess.file_exists(_tmp_path + ".tmp"), "the temporary file is gone")


func test_saving_keeps_the_previous_good_file_as_the_backup() -> void:
	var p := Profile.fresh()
	p.earn_seeds(1)
	check_eq(p.save_file(_tmp_path), OK, "first save")
	check(not FileAccess.file_exists(_tmp_path + ".bak"), "nothing to back up yet")
	p.earn_seeds(1)
	check_eq(p.save_file(_tmp_path), OK, "second save")
	check(FileAccess.file_exists(_tmp_path + ".bak"), "the .bak is there")
	check_eq(Profile.load_file(_tmp_path + ".bak").seeds, 1, "it holds the file the second save replaced")
	p.earn_seeds(1)
	p.save_file(_tmp_path)
	check_eq(Profile.load_file(_tmp_path + ".bak").seeds, 2, "and moves on with every save")
	check_eq(Profile.load_file(_tmp_path).seeds, 3, "the file is the newest")
	# A corrupt file is no backup: it never replaces the good .bak.
	_write(_tmp_path, "{ broken")
	p.earn_seeds(1)
	check_eq(p.save_file(_tmp_path), OK, "saved over a corrupt file")
	check_eq(Profile.load_file(_tmp_path + ".bak").seeds, 2, "the good .bak is kept")
	check_eq(Profile.load_file(_tmp_path).seeds, 4, "the new file loads")


func test_a_failed_write_keeps_the_old_file_and_the_backup() -> void:
	var p := Profile.fresh()
	p.earn_seeds(1)
	p.save_file(_tmp_path)
	p.earn_seeds(1)
	p.save_file(_tmp_path)
	var good := _read(_tmp_path)
	var backup := _read(_tmp_path + ".bak")
	p.earn_seeds(10)
	Profile.write_limit = 40  # the disk is full: a short file reaches the disk
	check_eq(p.save_file(_tmp_path), ERR_FILE_CANT_WRITE, "the short write is reported")
	check_eq(_read(_tmp_path), good, "the old file is untouched")
	check_eq(_read(_tmp_path + ".bak"), backup, "so is the backup")
	check(not FileAccess.file_exists(_tmp_path + ".tmp"), "the broken temporary file is removed")
	Profile.write_limit = 0
	check_eq(p.save_file(_tmp_path), ERR_FILE_CANT_WRITE, "nothing written at all")
	check_eq(_read(_tmp_path), good, "the old file is untouched")
	Profile.write_limit = -1
	check_eq(p.save_file(_tmp_path), OK, "the next save, with room again, works")
	check_eq(Profile.load_file(_tmp_path).seeds, 12, "and has everything")
	# A temporary file that cannot even be opened keeps the old file too.
	DirAccess.remove_absolute(_tmp_path + ".tmp")
	DirAccess.make_dir_absolute(_tmp_path + ".tmp")
	var before := _read(_tmp_path)
	check(p.save_file(_tmp_path) != OK, "the write is refused")
	check_eq(_read(_tmp_path), before, "the file is untouched")
	DirAccess.remove_absolute(_tmp_path + ".tmp")


func test_a_corrupt_or_missing_file_loads_the_backup() -> void:
	var p := Profile.fresh()
	p.earn_seeds(5)
	p.save_file(_tmp_path)
	p.earn_seeds(5)
	p.save_file(_tmp_path)  # (the .bak has 5 Seeds)
	_write(_tmp_path, "{ the disk lied")
	var back := Profile.load_file(_tmp_path)
	check_eq(back.load_error, Profile.LOAD_RECOVERED, "the recovery is reported")
	check_eq(back.seeds, 5, "the backup's progress, not a fresh profile")
	check(not back.read_only and not back.is_new, "writable, not new")
	check(FileAccess.file_exists(_tmp_path + ".corrupt") and not FileAccess.file_exists(_tmp_path), "the corrupt file is set aside")
	check_eq(back.save_file(_tmp_path), OK, "it can be saved again")
	check_eq(Profile.load_file(_tmp_path).load_error, "", "and the file is good")
	check_eq(Profile.load_file(_tmp_path).seeds, 5, "with the recovered progress")
	# The file is gone (a crash between the steps, a manual delete): the backup is used as well.
	DirAccess.remove_absolute(_tmp_path)
	var missing := Profile.load_file(_tmp_path)
	check_eq(missing.load_error, Profile.LOAD_RECOVERED, "a missing file with a backup is a recovery")
	check(not missing.is_new, "not a first launch")
	# No usable backup: a corrupt file is the fresh profile it always was.
	_write(_tmp_path, "{ broken")
	_write(_tmp_path + ".bak", "{ broken too")
	var fresh := Profile.load_file(_tmp_path)
	check_eq(fresh.load_error, "corrupt", "both are broken")
	check_eq(fresh.seeds, 0, "a fresh profile")
	DirAccess.remove_absolute(_tmp_path + ".bak")
	DirAccess.remove_absolute(_tmp_path + ".corrupt")
	check(Profile.load_file(_tmp_path).is_new, "neither file: a first launch")
	# A backup of a newer game is not read either.
	_write(_tmp_path + ".bak", "{\"version\": 2, \"seeds\": 9}")
	check(Profile.load_file(_tmp_path).is_new, "a newer backup does not count")
	# A good file wins over its backup.
	p.earn_seeds(1)
	p.save_file(_tmp_path)
	check_eq(Profile.load_file(_tmp_path).load_error, "", "a good file is loaded as it is")


func test_the_dev_profile_never_writes_a_backup() -> void:
	var dev := Profile.dev()
	check_eq(dev.save_file(_tmp_path), ERR_FILE_NO_PERMISSION, "refused")
	check(not FileAccess.file_exists(_tmp_path) and not FileAccess.file_exists(_tmp_path + ".bak"), "nothing on disk")
	Meta.configure(&"dev", "", true)
	Meta.save()
	check(not Meta.persist and Meta.path == "", "no file for an automated run")


func test_a_missing_file_is_a_fresh_profile() -> void:
	var p := Profile.load_file(_tmp_path)
	check(p.is_new and p.load_error == "" and not p.read_only, "first launch")
	check_eq(p.to_dict()["classes"], {}, "empty")
	check(not FileAccess.file_exists(_tmp_path), "loading creates nothing")


func test_a_corrupt_file_is_moved_aside_and_a_fresh_profile_used() -> void:
	_write(_tmp_path, "{ this is not json")
	var p := Profile.load_file(_tmp_path)
	check_eq(p.load_error, "corrupt", "reported")
	check(not p.read_only, "a fresh profile can be saved")
	check(p.achievements.is_empty() and p.seeds == 0, "fresh")
	check(FileAccess.file_exists(_tmp_path + ".corrupt"), "the old file is kept")
	check(not FileAccess.file_exists(_tmp_path), "the path is free")
	check_eq(p.save_file(_tmp_path), OK, "saving works again")
	check_eq(Profile.load_file(_tmp_path).load_error, "", "and loads")
	_write(_tmp_path, "[1, 2, 3]")
	check_eq(Profile.load_file(_tmp_path).load_error, "corrupt", "not a dictionary")
	_write(_tmp_path, "{\"seeds\": 5}")
	check_eq(Profile.load_file(_tmp_path).load_error, "corrupt", "no version")


func test_a_newer_version_is_never_overwritten() -> void:
	var text := "{\"version\": 2, \"seeds\": 77}"
	_write(_tmp_path, text)
	var p := Profile.load_file(_tmp_path)
	check_eq(p.load_error, "newer version", "reported")
	check(p.read_only, "read-only")
	check_eq(p.seeds, 0, "a fresh profile stands in")
	check_eq(p.save_file(_tmp_path), ERR_FILE_NO_PERMISSION, "saving is refused")
	check_eq(_read(_tmp_path), text, "the file is untouched")


func test_a_directory_at_the_path_is_unreadable_and_left_alone() -> void:
	DirAccess.make_dir_absolute(_tmp_path + "_dir")
	var p := Profile.load_file(_tmp_path + "_dir")
	check_eq(p.load_error, "unreadable", "reported")
	check(p.read_only, "read-only")
	check(DirAccess.dir_exists_absolute(_tmp_path + "_dir"), "still there")


func test_migrate_is_the_hook_for_older_versions() -> void:
	var data := {"version": 1, "seeds": 9}
	check_eq(Profile.migrate(data), data, "version 1 is current: unchanged")
	var steps := {
		1: func(d: Dictionary) -> Dictionary:
			d["step_one"] = true
			return d,
		2: func(d: Dictionary) -> Dictionary:
			d["step_two"] = d.get("step_one", false)
			return d,
	}
	var up := Profile.migrate(data, 3, steps)
	check_eq(int(up["version"]), 3, "brought to the target version")
	check(up.get("step_one", false) and up.get("step_two", false), "each step ran, in order")
	check(not data.has("step_one") and int(data["version"]) == 1, "the input is not changed")
	var legacy := Profile.migrate({"seeds": 2}, 2, {0: func(d: Dictionary) -> Dictionary:
		d["from_zero"] = true
		return d})
	check(legacy.get("from_zero", false) and int(legacy["version"]) == 2, "no version counts as 0")
	check_eq(int(Profile.migrate({"version": 5}, 3, steps)["version"]), 5, "a newer file is left as it is")


func test_from_dict_is_tolerant() -> void:
	var p := Profile.from_dict({
		"classes": {"warrior": {"xp": 12.0, "level": 99}, "mage": "bad", "": {"xp": 1}},
		"unlocks": {"ability": ["a", "", 5], "title": "not a list"},
		"achievements": {"x": "soon", "y": 12.0},
		"counters": [1, 2],
		"seeds": -4, "seeds_earned": "lots", "heirloom_ranks": {"a": -1, "b": 2.0},
		"loadouts": {"warrior": {"seasonings": "oops"}}, "selected_title": 5, "extra": true,
	})
	check_eq(p.class_level(&"warrior"), Profile.MAX_CLASS_LEVEL, "level clamped")
	check_eq(p.class_xp(&"warrior"), 12, "float XP is an int")
	check(not p.classes.has(&"mage") and not p.classes.has(&""), "bad class entries are dropped")
	check(p.has_unlock(Profile.KIND_ABILITY, &"a") and p.has_unlock(Profile.KIND_ABILITY, &"5"), "list entries are read as ids")
	check(not p.unlocks.has(Profile.KIND_TITLE), "a non-list kind is dropped")
	check_eq(p.achievements.get(&"x", -1), 0, "a bad time is 0")
	check_eq(p.achievements.get(&"y", -1), 12, "a float time is an int")
	check(p.counters.is_empty(), "counters of the wrong type are dropped")
	check_eq(p.seeds, 0, "Seeds are never negative")
	check_eq(p.heirloom_ranks, {&"b": 2} as Dictionary[StringName, int], "only positive ranks")
	check_eq(p.loadout(&"warrior"), Profile.normalize_loadout({}), "a bad loadout is empty")
	check_eq(p.selected_title, &"5", "the title is text")


func test_unknown_content_ids_survive_a_round_trip() -> void:
	var p := Profile.fresh()
	p.unlock(Profile.KIND_ABILITY, &"removed_in_a_later_build")
	p.set_class_progress(&"future_class", 10, 2)
	p.save_file(_tmp_path)
	var back := Profile.load_file(_tmp_path)
	check(back.has_unlock(Profile.KIND_ABILITY, &"removed_in_a_later_build"), "unknown ids are kept")
	check_eq(back.class_level(&"future_class"), 2, "and unknown classes")


# --- Which profile, and files -------------------------------------------------------------------

func test_the_unit_tests_are_an_automated_run_with_the_dev_profile() -> void:
	check(Meta.is_automated(), "the test runner is automated")
	check(_saved_profile.is_dev and _saved_profile.all_unlocked, "the dev profile is the current one")
	check(not Meta.records_runs(), "the dev profile records nothing")
	check(not _saved_persist and _saved_path == "", "no file for automated runs")


func test_configure_picks_the_profile_for_each_launch() -> void:
	Meta.configure(&"", "", true)
	check(Meta.profile.is_dev and not Meta.persist and Meta.path == "", "automated, no flags: dev, no file")
	Meta.configure(&"fresh", "", true)
	check(not Meta.profile.is_dev and not Meta.persist and Meta.path == "", "--profile=fresh: in memory only")
	check(not Meta.profile.all_unlocked, "fresh unlocks nothing by itself")
	Meta.configure(&"max", "", true)
	check(Meta.profile.all_unlocked and not Meta.persist, "--profile=max: in memory only")
	check_eq(Meta.profile.class_level(Db.class_ids[0]), 30, "at the top level")
	Meta.configure(&"dev", "", false)
	check(Meta.profile.is_dev and not Meta.persist, "--profile=dev in a real session: still no file")
	Profile.fresh().save_file(_tmp_path)
	Meta.configure(&"", _tmp_path, true)
	check(not Meta.profile.is_dev and Meta.persist and Meta.path == _tmp_path, "--profile-path alone: that file, saved")
	check(not Meta.profile.is_new, "the file was read")


func test_a_named_profile_with_a_path_starts_from_the_named_profile() -> void:
	var old := Profile.fresh()
	old.earn_seeds(500)
	old.save_file(_tmp_path)
	Meta.configure(&"fresh", _tmp_path, true)
	check_eq(Meta.profile.seeds, 0, "--profile=fresh ignores what the file held")
	check(Meta.persist and Meta.path == _tmp_path, "and writes to the file")
	Meta.configure(&"max", _tmp_path, true)
	check(Meta.profile.all_unlocked and Meta.persist, "--profile=max with a path is saved there")
	Meta.configure(&"", _tmp_path, true)
	check_eq(Meta.profile.seeds, 500, "no kind: the file is loaded")


func test_automated_runs_never_touch_a_profile_file() -> void:
	var default_existed := FileAccess.file_exists(Profile.DEFAULT_PATH)
	var default_time := FileAccess.get_modified_time(Profile.DEFAULT_PATH) if default_existed else 0
	Meta.configure(&"", "", true)
	var saves := Meta.save_count
	check_eq(Meta.save(), OK, "save() is a no-op")
	Meta.earn_seeds(10)
	Meta.unlock(Profile.KIND_TITLE, &"x")
	var result := Meta.record_run(_report())
	check(not result["recorded"], "nothing recorded")
	check_eq(Meta.save_count, saves, "no write was attempted")
	check_eq(FileAccess.file_exists(Profile.DEFAULT_PATH), default_existed, "user://profile.json did not appear")
	if default_existed:
		check_eq(FileAccess.get_modified_time(Profile.DEFAULT_PATH), default_time, "and was not touched")


func test_the_profile_flags_are_validated() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--profile=fresh", "--profile-path=/tmp/p.json"]))
	check_eq(o.profile_kind, &"fresh", "kind")
	check_eq(o.profile_path, "/tmp/p.json", "path")
	check(o.unknown.is_empty(), "valid")
	check(not o.is_automated(), "the profile flags do not make a run automated")
	check_eq(LaunchOptions.parse(PackedStringArray(["--profile=max"])).profile_kind, &"max", "max")
	check_eq(LaunchOptions.parse(PackedStringArray(["--profile=dev"])).profile_kind, &"dev", "dev")
	check_eq(LaunchOptions.parse(PackedStringArray([])).profile_kind, &"", "default: none")
	for bad in ["--profile=bogus", "--profile=", "--profile-path="]:
		var b := LaunchOptions.parse(PackedStringArray([bad]))
		check(not b.unknown.is_empty(), "'%s' is an unknown argument" % bad)
		check_eq(b.profile_kind, &"", "'%s' sets no kind" % bad)
	var conflict := LaunchOptions.parse(PackedStringArray(["--profile=dev", "--profile-path=/tmp/p.json"]))
	check_eq(conflict.unknown.size(), 1, "dev with a file is refused")


# --- Unlock checks ------------------------------------------------------------------------------

func test_the_dev_profile_answers_true_to_everything() -> void:
	_gate(Profile.KIND_CLASS, &"hunter", "Win once")
	_gate(Profile.KIND_ABILITY, &"whirlwind")
	Meta.configure(&"dev", "", true)
	check(Meta.is_unlocked(Profile.KIND_CLASS, &"hunter"), "a gated class")
	check(Meta.is_unlocked(Profile.KIND_ABILITY, &"whirlwind"), "a gated ability")
	check(Meta.is_unlocked(Profile.KIND_SEASONING, &"anything"), "a collectible")
	check(Meta.is_unlocked(Profile.KIND_DIFFICULTY, &"tear_jerker", &"warrior"), "a difficulty tier")
	check(Db.is_unlocked(&"anything"), "the id-only pools stay open")
	check(Db.is_unlocked(&"hunter", Profile.KIND_CLASS), "Db forwards a kind to Meta")


func test_content_is_open_unless_a_gate_holds_it_back() -> void:
	_use_fresh()
	check(Meta.is_unlocked(Profile.KIND_CLASS, &"hunter"), "ungated: open")
	_gate(Profile.KIND_CLASS, &"hunter", "Win with any class")
	check(not Meta.is_unlocked(Profile.KIND_CLASS, &"hunter"), "gated: locked")
	check(Meta.is_unlocked(Profile.KIND_CLASS, &"warrior"), "another class: open")
	check(Meta.is_unlocked(Profile.KIND_ABILITY, &"hunter"), "the same id of another kind: open")
	check(Meta.unlock(Profile.KIND_CLASS, &"hunter"), "unlock")
	check(Meta.is_unlocked(Profile.KIND_CLASS, &"hunter"), "unlocked")
	check(not Meta.unlock(Profile.KIND_CLASS, &"hunter"), "not new twice")
	check_eq(Meta.unlock_hint(Profile.KIND_CLASS, &"hunter"), "Win with any class", "the gate's hint")
	check_eq(Meta.unlock_hint(Profile.KIND_CLASS, &"warrior"), Meta.LOCKED_HINT, "no gate: the plain text")


func test_collectibles_are_locked_until_the_profile_owns_them() -> void:
	_use_fresh()
	for kind in Profile.COLLECTIBLE_KINDS:
		check(not Meta.is_unlocked(kind, &"thing"), "%s: locked without a gate" % kind)
		Meta.unlock(kind, &"thing")
		check(Meta.is_unlocked(kind, &"thing"), "%s: unlocked" % kind)
	Meta.profile = Profile.max_profile(Db.class_ids)
	check(Meta.is_unlocked(Profile.KIND_SEASONING, &"never_bought"), "the max profile has everything")


func test_difficulty_tiers_unlock_per_class() -> void:
	_use_fresh()
	check_eq(Difficulty.ids(), [&"normal", &"pungent", &"tear_jerker"] as Array[StringName], "the three tiers (data/difficulties)")
	check(Meta.is_difficulty_unlocked(&"normal", &"warrior"), "Normal is always open")
	check(not Meta.is_difficulty_unlocked(&"pungent", &"warrior"), "Pungent is locked")
	check(not Meta.is_unlocked(Profile.KIND_DIFFICULTY, &"pungent", &"warrior"), "through the generic check too")
	check(not Meta.is_difficulty_unlocked(&"nonsense", &"warrior"), "an unknown tier is not open")
	Meta.unlock(Profile.KIND_DIFFICULTY, &"pungent", &"warrior")
	check(Meta.is_difficulty_unlocked(&"pungent", &"warrior"), "unlocked for the warrior")
	check(not Meta.is_difficulty_unlocked(&"pungent", &"mage"), "not for the mage")
	check(not Meta.is_difficulty_unlocked(&"tear_jerker", &"warrior"), "the next tier is still locked")
	var both: Array[StringName] = [&"warrior", &"mage"]
	var warrior_only: Array[StringName] = [&"warrior"]
	var nobody: Array[StringName] = []
	check_eq(Meta.party_difficulty_cap(both), &"normal", "the lowest class caps the party")
	check_eq(Meta.party_difficulty_cap(warrior_only), &"pungent", "a lone warrior")
	check_eq(Meta.party_difficulty_cap(nobody), &"tear_jerker", "no classes: nothing caps")
	Meta.profile = Profile.max_profile(Db.class_ids)
	check_eq(Meta.party_difficulty_cap(both), &"tear_jerker", "the max profile")


func test_the_lobby_class_list_skips_locked_classes() -> void:
	_use_fresh()
	var all := Db.class_ids.duplicate()
	check_eq(Meta.unlocked_class_ids(), all, "ungated: every class, in lobby order")
	_gate(Profile.KIND_CLASS, Db.class_ids[0], "Locked first class")
	var rest: Array[StringName] = []
	for i in range(1, Db.class_ids.size()):
		rest.append(Db.class_ids[i])
	check_eq(Meta.unlocked_class_ids(), rest, "the locked class is not offered")
	check_eq(Meta.default_class().id, Db.class_ids[1], "a joining player starts on the first open class")
	var slot := PlayerManager.join(UiFakes.HumanInput.new("pad:a"))
	check_eq(slot.class_data.id, Db.class_ids[1], "PlayerManager.join uses it")
	slot.class_data = Db.get_class_data(Db.class_ids[0])
	var swapped := Meta.enforce_class_locks(PlayerManager.get_slots())
	check_eq(swapped, 1, "a locked class on a slot is replaced at run start")
	check_eq(slot.class_data.id, Db.class_ids[1], "by the default class")
	Meta.profile = Profile.dev()
	check_eq(Meta.unlocked_class_ids(), all, "the dev profile offers every class")
	for id in Db.class_ids:
		_gate(Profile.KIND_CLASS, id)
	Meta.profile = Profile.fresh()
	check_eq(Meta.unlocked_class_ids().size(), 1, "never an empty list")


func test_bots_do_not_pick_locked_classes() -> void:
	_use_fresh()
	_gate(Profile.KIND_CLASS, &"hunter")
	_gate(Profile.KIND_CLASS, &"shaman")
	var opts := LaunchOptions.new()
	opts.players = 4
	_make_main(opts)
	main._add_bots()
	for slot in PlayerManager.get_slots():
		check(slot.class_data.id not in [&"hunter", &"shaman"], "%s: a class that is open" % slot.label())
	# An explicit locked class on a slot never reaches the run.
	PlayerManager.clear()
	PlayerManager.add_bot(&"hunter", 1)
	main.start_run()
	check_eq(main.players[0].class_data.id, Db.class_ids[0], "start_run replaced the locked class")


func test_the_lobby_blocks_ready_for_a_locked_class() -> void:
	_use_fresh()
	_gate(Profile.KIND_CLASS, &"hunter", "Win a run with any class")
	var lobby := Lobby.create()
	_nodes.append(lobby)
	UiFakes.add_to_root(tree, lobby)
	var input := UiFakes.HumanInput.new("pad:a")
	var slot := PlayerManager.join(input, Db.get_class_data(&"hunter"))
	UiFakes.step(lobby)
	check_eq(lobby.ready_block_reason(slot), "Win a run with any class", "the unlock hint is the reason")
	var card: LobbyCard = lobby.cards[slot.index]
	check(card._desc_label.text.begins_with("Locked: Win a run with any class"), "the card shows the hint")
	UiFakes.tap(lobby, input, PlayerInput.Pad.A)
	check(not slot.ready, "A does not ready a locked class")
	UiFakes.tap(lobby, input, PlayerInput.Pad.START)
	check(not slot.ready, "neither does START")
	slot.class_data = Db.get_class_data(&"warrior")
	check_eq(lobby.ready_block_reason(slot), "", "an open class")
	UiFakes.tap(lobby, input, PlayerInput.Pad.A)
	check(slot.ready, "A readies an open class")
	slot.ready = false
	Meta.unlock(Profile.KIND_CLASS, &"hunter")
	slot.class_data = Db.get_class_data(&"hunter")
	UiFakes.tap(lobby, input, PlayerInput.Pad.A)
	check(slot.ready, "an unlocked class can ready")


func test_the_ability_pool_and_the_level_up_deck_skip_locked_abilities() -> void:
	world = EFakes.make_world(tree)
	RunState.start_run(1, 99)
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var open_pool := Db.ability_pool(&"warrior")
	check(open_pool.size() >= 2, "the warrior has learnable abilities")
	var target: AbilityData = null
	for a in open_pool:
		if not p.abilities.knows(a.id):
			target = a
			break
	check(target != null, "an ability the hero does not know yet")
	if target == null:
		return
	# The dev profile: nothing is locked, gate or not.
	_gate(Profile.KIND_ABILITY, target.id, "Reach Class Level 2")
	check(Db.ability_pool(&"warrior").has(target), "dev profile: still in the pool")
	_use_fresh()
	check(not Db.ability_pool(&"warrior").has(target), "fresh profile: not in the pool")
	check_eq(Db.ability_pool(&"warrior").size(), open_pool.size() - 1, "only that one is missing")
	var offered := false
	for card in LevelUpDeck.ability_candidates(p):
		if (card[0] as LevelCard).ability == target:
			offered = true
	check(not offered, "the deck's candidates do not include it")
	for i in 40:
		for card in LevelUpDeck.draw(p, rng):
			check(card.ability != target, "no hand offers a locked ability")
	Meta.unlock(Profile.KIND_ABILITY, target.id)
	check(Db.ability_pool(&"warrior").has(target), "unlocked: back in the pool")
	offered = false
	for card in LevelUpDeck.ability_candidates(p):
		if (card[0] as LevelCard).ability == target:
			offered = true
	check(offered, "and in the deck")


func test_a_locked_capstone_takes_no_points_and_the_bots_skip_it() -> void:
	world = EFakes.make_world(tree)
	RunState.start_run(1, 99)
	var arms: Array[TalentTreeData] = [Db.get_talent_tree(&"warrior_arms")]
	var capstone: TalentData = null
	for t in arms[0].talents:
		if t.is_capstone():
			capstone = t
	check(capstone != null, "the Arms tree has a capstone")
	if capstone == null:
		return
	# Dev profile: unchanged behaviour.
	_gate(Profile.KIND_CAPSTONE_TREE, arms[0].id, "Reach Class Level 8")
	var dev_hero := _hero(0, 31, arms)
	check(not dev_hero.talents.capstone_locked(capstone), "dev profile: not locked")
	var dev_spent := TalentBot.spend_all(dev_hero, 0)
	check(dev_hero.talents.rank_of(capstone.id) == capstone.max_rank, "dev profile: the bot takes the capstone")
	# A fresh profile.
	_use_fresh()
	var hero := _hero(1, 31, arms)
	var s := hero.talents
	check(s.capstone_locked(capstone), "locked on a fresh profile")
	check(s.add_block_reason(capstone.id).begins_with("Capstone locked"), "the reason says so")
	check(s.add_block_reason(capstone.id).contains("Reach Class Level 8"), "and carries the hint")
	var spent := TalentBot.spend_all(hero, 0)
	check_eq(s.rank_of(capstone.id), 0, "the bot skipped the capstone")
	check_eq(dev_spent - spent, capstone.max_rank, "and spent everything else")
	check(s.points_free() > 0, "the point it could not use is left over")
	check(not s.can_add(capstone.id) and not s.add(capstone.id), "no point can go in, even with points free")
	check(TalentBot.next_talent(hero, 0) == null or TalentBot.next_talent(hero, 0) != capstone, "the bot would not pick it")
	check_eq(TalentNode.state_for(s, capstone), TalentNode.State.LOCKED, "the node shows as locked")
	check(not TalentNode.is_open(s, capstone), "and not open")
	for other in arms[0].talents:
		if not other.is_capstone():
			check(not s.capstone_locked(other), "only the capstone is locked")
	# Unlocking opens it.
	Meta.unlock(Profile.KIND_CAPSTONE_TREE, arms[0].id)
	check(not s.capstone_locked(capstone), "unlocked")
	check(s.can_add(capstone.id), "a point can go in")
	check_eq(TalentNode.state_for(s, capstone), TalentNode.State.AVAILABLE, "the node is available")
	check(s.add(capstone.id), "taken")


func _legendary_uniques() -> Array[UniqueItemData]:
	var out: Array[UniqueItemData] = []
	for id in Db.uniques:
		var data: UniqueItemData = Db.uniques[id]
		if data.rarity == Items.Rarity.LEGENDARY and ItemGenerator.unique_available(data, ItemGenerator.Source.LOOT, 25):
			out.append(data)
	return out


func test_locked_legendaries_leave_the_loot_pool() -> void:
	var all := _legendary_uniques()
	check(all.size() >= 2, "there are hand-made Legendaries to drop")
	if all.size() < 2:
		return
	for data in all:
		_gate(Profile.KIND_LEGENDARY, data.id, "Earn the achievement")
	check_eq(_legendary_uniques().size(), all.size(), "dev profile: all of them (unchanged)")
	_use_fresh()
	check_eq(_legendary_uniques().size(), 0, "fresh profile: none")
	for i in 40:
		check(ItemGenerator._pick_unique(ItemGenerator.Source.LOOT, 25, Items.Rarity.LEGENDARY, -1, true, null, null, rng) == null,
				"no locked Legendary is ever rolled")
	Meta.unlock(Profile.KIND_LEGENDARY, all[0].id)
	check_eq(_legendary_uniques().size(), 1, "one unlocked")
	var seen: Dictionary[StringName, bool] = {}
	for i in 60:
		var pick := ItemGenerator._pick_unique(ItemGenerator.Source.LOOT, 25, Items.Rarity.LEGENDARY, -1, true, null, null, rng)
		if pick != null:
			seen[pick.id] = true
	check(seen.has(all[0].id) and seen.size() == 1, "only the unlocked Legendary can drop")
	# A Legendary gate on a lower rarity changes nothing: the gate is about Legendaries.
	for id in Db.uniques:
		var lower: UniqueItemData = Db.uniques[id]
		if lower.rarity < Items.Rarity.LEGENDARY and ItemGenerator.unique_available(lower, ItemGenerator.Source.LOOT, 25):
			_gate(Profile.KIND_LEGENDARY, id)
			check(ItemGenerator.unique_available(lower, ItemGenerator.Source.LOOT, 25), "a non-Legendary stays in its pool")
			break


func test_a_locked_forged_legendary_blocks_the_forge() -> void:
	RunState.start_run(2, 21)
	var data := Forge.legendary_for(&"dagger")
	var eq := Equipment.new(Db.get_class_data(&"rogue"))
	var a := ItemGenerator.generate_weapon(Db.get_weapon(&"dagger"), Items.Rarity.EPIC, 14, false, rng)
	var b := ItemGenerator.generate_weapon(Db.get_weapon(&"dagger"), Items.Rarity.EPIC, 15, false, rng)
	eq.add_to_backpack(a)
	eq.add_to_backpack(b)
	check_eq(data.unlock_id(), &"legendary_dagger", "the unlock id is the file's stem")
	_gate(Profile.KIND_LEGENDARY, data.unlock_id())
	check(not Forge.result_locked(a), "dev profile: not locked")
	check_eq(Forge.blocked_reason(eq, a), "", "dev profile: forgeable")
	_use_fresh()
	check(Forge.result_locked(a), "fresh profile: the Legendary is locked")
	check_eq(Forge.blocked_reason(eq, a), Forge.REASON_LEGENDARY_LOCKED, "the reason")
	check(Forge.make_result(a, b, rng) == null, "no result")
	check(Forge.forge(eq, a, rng) == null and eq.backpack.size() == 2, "nothing was forged")
	var slot := Support.make_slot(0, &"rogue")
	var slots: Array[PlayerSlot] = [slot]
	var hero_eq := Support.equipment_of(slot)
	hero_eq.add_to_backpack(ItemGenerator.generate_weapon(Db.get_weapon(&"dagger"), Items.Rarity.EPIC, 14, false, rng))
	hero_eq.add_to_backpack(ItemGenerator.generate_weapon(Db.get_weapon(&"dagger"), Items.Rarity.EPIC, 15, false, rng))
	check_eq(Forge.bot_forge_all(slot), 0, "the bots forge nothing")
	var offer := ItemGenerator.generate_weapon(Db.get_weapon(&"dagger"), Items.Rarity.EPIC, 14, false, rng)
	check(Forge.offer_forge_slots(offer, slots).is_empty(), "no anvil pip in the shop")
	# Lower forges are not affected.
	var c1 := ItemGenerator.generate_weapon(Db.get_weapon(&"dagger"), Items.Rarity.RARE, 9, false, rng)
	var c2 := ItemGenerator.generate_weapon(Db.get_weapon(&"dagger"), Items.Rarity.RARE, 9, false, rng)
	check(not Forge.result_locked(c1) and Forge.make_result(c1, c2, rng) != null, "a Rare pair still forges an Epic")
	Meta.unlock(Profile.KIND_LEGENDARY, data.unlock_id())
	check(not Forge.result_locked(a) and Forge.blocked_reason(eq, a) == "", "unlocked: forgeable")
	var result := Forge.forge(eq, a, rng)
	check(result != null and result.rarity == Items.Rarity.LEGENDARY, "and it makes the Legendary")
	check_eq(Forge.offer_forge_slots(offer, slots), [0] as Array[int], "the shop's anvil pip is back")
	check_eq(Forge.bot_forge_all(slot), 1, "and the bots forge")
	Support.free_slots(slots)


# --- The run-end hook ---------------------------------------------------------------------------

func test_record_run_dispatches_in_order_and_saves_once() -> void:
	_use_file()
	_track(&"late", 50)
	_track(&"first_default", 0, 3)
	_track(&"early", -50)
	_track(&"second_default", 0)
	var result := Meta.record_run(_report(true, {"kills": 12}))
	check(result["recorded"], "recorded")
	check_eq(result["listeners"], [&"counters", &"early", &"first_default", &"second_default", &"late", &"achievements"] as Array[StringName],
			"counters, then by priority and registration, the achievement check last")
	var ran: Array[StringName] = []
	for entry in order:
		if not String(entry).begins_with("runs="):
			ran.append(entry)
	check_eq(ran, [&"early", &"first_default", &"second_default", &"late"] as Array[StringName], "the listeners ran in that order")
	check(order.has(&"runs=1"), "the run's counters were already counted when the listeners ran")
	check_eq(Meta.save_count, 1, "ONE save for the whole run, although a listener paid out Seeds")
	check_eq(result["save_error"], OK, "saved fine")
	var back := Profile.load_file(_tmp_path)
	check_eq(back.seeds, 3, "the file holds what the listeners did")
	check_eq(back.counter(&"runs"), 1, "and the counters")
	check_eq(back.counter(&"total:kills"), 12, "total:kills")
	check(reports.size() == 4 and reports[0].recorded, "the listeners got the report")
	check(Meta.last_result == result, "last_result")


func test_record_run_counts_a_report_once() -> void:
	_use_file()
	var report := _report()
	check(Meta.record_run(report)["recorded"], "first")
	var saves := Meta.save_count
	check(not Meta.record_run(report)["recorded"], "the same report is not recorded again")
	check(not Meta.record_run(null)["recorded"], "null records nothing")
	check_eq(Meta.save_count, saves, "no second save")
	check_eq(Meta.profile.counter(&"runs"), 1, "one run")


func test_listeners_are_replaced_by_id_and_can_be_removed() -> void:
	_use_fresh()
	_track(&"a")
	_track(&"b")
	_track(&"a")  # registering an id again replaces it (and moves it behind b)
	check_eq(Meta.listener_ids(), [&"counters", &"b", &"a", &"achievements"] as Array[StringName], "replaced, now last of the default priority")
	Meta.remove_run_listener(&"b")
	check_eq(Meta.listener_ids(), [&"counters", &"a", &"achievements"] as Array[StringName], "removed")
	Meta.record_run(_report())
	check_eq(order.filter(func(e: StringName) -> bool: return not String(e).begins_with("runs=")), [&"a"], "only a ran")


func test_the_dev_profile_records_nothing_and_calls_no_listener() -> void:
	Meta.configure(&"dev", "", true)
	_track(&"a")
	var result := Meta.record_run(_report())
	check(not result["recorded"], "not recorded")
	check(order.is_empty(), "no listener ran")
	check_eq(Meta.profile.counter(&"runs"), 0, "no counters")
	check(Meta.check_achievements(_report()).is_empty(), "no achievement check either")


func test_signals_come_after_the_save() -> void:
	_use_file()
	var defs := _defs([_achievement("signal_test", AchievementEngine.COND_RUN_FLAG, {"flag": "victory"})])
	Db.achievements = {&"signal_test": defs[0]}
	var seen: Array[String] = []
	var on_unlock := func(id: StringName) -> void:
		seen.append("unlocked:%s file_has_it=%s" % [id, Profile.load_file(_tmp_path).has_achievement(id)])
	var on_run := func(_r: RunReport, result: Dictionary) -> void:
		seen.append("run_recorded saved=%s" % [result["save_error"] == OK and FileAccess.file_exists(_tmp_path)])
	Meta.achievement_unlocked.connect(on_unlock)
	Meta.run_recorded.connect(on_run)
	var result := Meta.record_run(_report(true))
	Meta.achievement_unlocked.disconnect(on_unlock)
	Meta.run_recorded.disconnect(on_run)
	check_eq(result["achievements"], [&"signal_test"] as Array[StringName], "the run unlocked it")
	check_eq(seen, ["unlocked:signal_test file_has_it=true", "run_recorded saved=true"] as Array[String], "both signals fired after the file was written")


func test_main_records_a_real_run_once_and_the_dev_profile_none() -> void:
	_use_file()
	_track(&"watch")
	_run_with_bots(2)
	var classes: Array[StringName] = main.run_classes.duplicate()
	main.end_run(true)
	check(main.meta_result.get("recorded", false), "Main kept the result")
	check_eq(reports.size(), 1, "one report")
	var r := reports[0]
	check(r.victory and not r.abandoned, "a victory")
	check_eq(r.party, classes, "the party as the run started")
	check_eq(r.heroes.size(), 2, "both heroes")
	check_eq(r.flag(&"mode"), "normal", "mode flag")
	check(r.stats.has(&"kills") and r.stats.has(&"party_size"), "the stats")
	check_eq(int(r.stat(&"party_size")), 2, "party size")
	var file := Profile.load_file(_tmp_path)
	check_eq(file.counter(&"runs"), 1, "saved in the file")
	check_eq(file.counter(StringName("wins:%s" % classes[0])), 1, "a win per class played")
	check_eq(Meta.save_count, 1, "one save")
	main.end_run(true)
	check_eq(reports.size(), 1, "a second end_run does not record again")
	# The dev profile: nothing.
	reports.clear()
	Meta.configure(&"dev", "", true)
	_free_main()
	UiFakes.reset_players()
	_run_with_bots(2)
	main.end_run(false)
	check(main.meta_result.is_empty(), "dev profile: no result")
	check(reports.is_empty(), "dev profile: no listener ran")


func test_an_abandoned_run_is_recorded_once_a_wave_was_cleared() -> void:
	_use_file()
	_track(&"watch")
	_run_with_bots(2)
	main.quit_to_menu()
	check(reports.is_empty(), "a run given up in its first fight is no result")
	_free_main()
	UiFakes.reset_players()
	_run_with_bots(2)
	main.waves_completed = 3
	main.quit_to_menu()
	check_eq(reports.size(), 1, "recorded")
	check(reports[0].abandoned and not reports[0].victory, "as abandoned")
	check_eq(int(reports[0].stat(&"waves_cleared")), 3, "with the waves cleared")


func _smoke_options(waves: int, start_wave: int = 1) -> LaunchOptions:
	var opts := LaunchOptions.new()
	opts.smoke = true
	opts.waves = waves
	opts.start_wave = start_wave
	return opts


func test_a_smoke_run_with_a_real_profile_records_its_planned_waves() -> void:
	_use_file()
	_track(&"watch")
	_make_main(_smoke_options(1))
	main.quit_app = false
	main._smoke_running = true
	PlayerManager.add_bot(&"warrior", 1)
	PlayerManager.add_bot(&"mage", 2)
	main.start_run()
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	check_eq(main.quit_code, 0, "the smoke run finished")
	check_eq(reports.size(), 1, "its planned waves were recorded as a run")
	check(reports[0].abandoned and not reports[0].victory, "one the harness stopped")
	check_eq(int(reports[0].stat(&"waves_cleared")), 1, "after one wave")
	check_eq(Profile.load_file(_tmp_path).counter(&"runs"), 1, "saved")
	# On the last wave the same ending is a victory.
	_free_main()
	UiFakes.reset_players()
	reports.clear()
	_make_main(_smoke_options(1, RunState.TOTAL_WAVES))
	main.quit_app = false
	main._smoke_running = true
	PlayerManager.add_bot(&"warrior", 1)
	main.start_run()
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	check(reports.size() == 1 and reports[0].victory and not reports[0].abandoned, "a victory on the final wave")
	# The dev profile (every automated run): nothing is recorded.
	_free_main()
	UiFakes.reset_players()
	reports.clear()
	Meta.configure(&"dev", "", true)
	_make_main(_smoke_options(1))
	main.quit_app = false
	main._smoke_running = true
	PlayerManager.add_bot(&"warrior", 1)
	main.start_run()
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	check_eq(main.quit_code, 0, "the dev smoke run finished")
	check(reports.is_empty() and main.meta_result.is_empty(), "the dev profile recorded nothing")


func test_the_run_report_collects_what_the_run_kept() -> void:
	RunState.start_run(2, 5)
	PlayerManager.add_bot(&"warrior", 1)
	PlayerManager.add_bot(&"mage", 2)
	RunState.kills = 77
	RunState.bosses_killed = 1
	RunState.goblins_killed = 3
	RunState.record_down(1)
	RunState.record_revive(0)
	RunState.damage_by_player[0] = 500.0
	RunState.need_wins_by_player[1] = 2
	var r := RunReport.collect(true, false, {"classes": [&"warrior", &"mage"], "wave": 25, "waves_cleared": 25, "items_bought": 7})
	check(r.victory and not r.abandoned and not r.endless and not r.hardcore, "flags from the run")
	check_eq(r.party, _party(["warrior", "mage"]), "party")
	check_eq(r.stat(&"kills"), 77.0, "kills")
	check_eq(r.stat(&"bosses_killed"), 1.0, "bosses")
	check_eq(r.stat(&"goblins_killed"), 3.0, "goblins")
	check_eq(r.stat(&"downs"), 1.0, "downs")
	check_eq(r.stat(&"revives"), 1.0, "revives")
	check_eq(r.stat(&"damage"), 500.0, "damage")
	check_eq(r.stat(&"need_wins"), 2.0, "need wins")
	check_eq(r.stat(&"items_bought"), 7.0, "Main's own counters come in")
	check_eq(r.stat(&"wave"), 25.0, "wave")
	check_eq(r.stat(&"party_size"), 2.0, "party size")
	check_eq(r.flag(&"no_downs"), false, "somebody went down")
	check_eq(r.flag(&"solo"), false, "not solo")
	check_eq(r.heroes.size(), 2, "two hero entries")
	check_eq(r.heroes[0]["class_id"], "warrior", "hero class")
	check_eq(int(r.heroes[1]["downs"]), 1, "hero downs")
	check_eq(r.hero_count_of(&"mage"), 1, "one mage")
	check(r.has_class(&"warrior") and not r.has_class(&"rogue"), "has_class")
	check_eq(r.heroes_of(&"mage").size(), 1, "heroes_of")
	for id in RunReport.STAT_IDS:
		check(r.stats.has(id), "stat %s is filled" % id)
	check(r.to_dict().has("stats") and r.to_dict()["party"].size() == 2, "to_dict")


func test_a_hero_who_left_mid_run_stays_in_the_run_report() -> void:
	RunState.start_run(2, 5)
	PlayerManager.add_bot(&"warrior", 1)
	PlayerManager.add_bot(&"mage", 2)
	RunState.record_down(1)
	RunState.record_revive(0)
	RunState.kills_by_player[1] = 40
	RunState.kills_by_player[0] = 10
	RunState.damage_by_player[0] = 500.0
	RunState.damage_by_player[1] = 250.0
	RunState.healing_by_player[1] = 30.0
	RunState.absorbed_by_player[1] = 20.0
	RunState.damage_taken_by_player[1] = 90.0
	RunState.need_wins_by_player[1] = 2
	var snapshot := RunReport.hero_entry(PlayerManager.get_slot(1))
	PlayerManager.leave(1)  # (Main.drop_player: "Continue without P2")
	var extras := {"classes": [&"warrior", &"mage"], "wave": 25, "waves_cleared": 25, "departed_heroes": [snapshot]}
	var r := RunReport.collect(true, false, extras)
	check_eq(r.stat(&"downs"), 1.0, "the dropped hero's down counts")
	check_eq(r.flag(&"no_downs"), false, "so this is no 'no downs' win")
	check_eq(r.stat(&"revives"), 1.0, "revives")
	check_eq(r.stat(&"damage"), 750.0, "damage of both")
	check_eq(r.stat(&"healing"), 30.0, "healing")
	check_eq(r.stat(&"absorbed"), 20.0, "absorbed")
	check_eq(r.stat(&"damage_taken"), 90.0, "damage taken")
	check_eq(r.stat(&"need_wins"), 2.0, "need wins")
	check_eq(r.stat(&"party_size"), 2.0, "the party was two")
	check_eq(r.heroes.size(), 2, "both heroes are in the report")
	check_eq(int(r.heroes[0]["slot"]), 0, "in slot order")
	check_eq(r.heroes[1]["class_id"], "mage", "the dropped hero's class")
	check_eq(int(r.heroes[1]["kills"]), 40, "the dropped hero's kills")
	check_eq(int(r.heroes[1]["downs"]), 1, "the dropped hero's downs")
	# Numbers that tick on after the hero left are read again at the report.
	RunState.kills_by_player[1] = 41
	check_eq(int(RunReport.collect(true, false, extras).heroes[1]["kills"]), 41, "the counters are current")
	# The class still gets its share of the Class XP (the 0.03-per-kill term).
	var p := Profile.fresh()
	var mage_run := ClassLevels.run_xp(r, p).filter(func(e: Dictionary) -> bool: return e["class_id"] == &"mage")
	check_eq(mage_run.size(), 1, "the mage is paid")
	check_eq(int(mage_run[0]["kills"]), 40, "with the dropped hero's kills")
	var without := RunReport.collect(true, false, {"classes": [&"warrior", &"mage"], "wave": 25, "waves_cleared": 25})
	check_eq(without.stat(&"downs"), 1.0, "the run-wide numbers do not need the snapshot")
	check_eq(without.heroes.size(), 1, "(only the per-hero entry does)")
	# The last hero drops: the abandoned run still has its heroes.
	var first := RunReport.hero_entry(PlayerManager.get_slot(0))
	PlayerManager.leave(0)
	var abandoned := RunReport.collect(false, true, {"classes": [&"warrior", &"mage"], "waves_cleared": 3,
			"departed_heroes": [snapshot, first]})
	check_eq(abandoned.heroes.size(), 2, "nobody left, two heroes in the report")
	check_eq(abandoned.stat(&"downs"), 1.0, "downs")
	check_eq(abandoned.stat(&"party_size"), 2.0, "party size")


func test_main_drop_player_snapshots_the_hero_for_the_run_report() -> void:
	_run_with_bots(2)
	RunState.record_down(1)
	RunState.kills_by_player[1] = 12
	var slot := PlayerManager.get_slot(1)
	var class_id := String(slot.class_data.id)
	check(main.departed_heroes.is_empty(), "nobody has left")
	main.drop_player(slot)
	check_eq(main.departed_heroes.size(), 1, "the dropped hero is kept")
	check_eq(int(main.departed_heroes[0]["slot"]), 1, "slot")
	check_eq(main.departed_heroes[0]["class_id"], class_id, "class")
	check(not (main.departed_heroes[0]["equipped"] as Array).is_empty(), "with what it wore (taken before the hero was freed)")
	var r := RunReport.collect(true, false, main._report_extras())
	check_eq(r.stat(&"downs"), 1.0, "a down of the dropped hero")
	check_eq(r.flag(&"no_downs"), false, "no Untouched for this run")
	check_eq(r.heroes.size(), 2, "two hero entries")
	check_eq(int(r.heroes_of(StringName(class_id))[0]["kills"]), 12, "the kills of the dropped hero")
	main.start_run()
	check(main.departed_heroes.is_empty(), "a new run starts clean")


# --- Achievements -------------------------------------------------------------------------------

func test_achievement_conditions() -> void:
	var p := Profile.fresh()
	var heroes: Array[Dictionary] = [
		{"slot": 0, "class_id": "warrior", "kills": 90, "downs": 0, "damage": 1000.0},
		{"slot": 1, "class_id": "mage", "kills": 10, "downs": 2, "damage": 50.0},
	]
	var r := _report(true, {"kills": 100, "downs": 2, "wave": 25, "party_size": 2}, ["warrior", "mage"], {}, heroes)
	var check_it := func(cond: Dictionary) -> bool: return AchievementEngine.check(cond, p, r)
	check(check_it.call({"kind": "stat_at_least", "stat": "kills", "value": 100}), "stat_at_least: equal")
	check(not check_it.call({"kind": "stat_at_least", "stat": "kills", "value": 101}), "stat_at_least: not enough")
	check(check_it.call({"kind": "stat_at_most", "stat": "downs", "value": 2}), "stat_at_most")
	check(not check_it.call({"kind": "stat_at_most", "stat": "downs", "value": 1}), "stat_at_most: too many")
	check(check_it.call({"kind": "stat_at_least", "stat": "kills", "value": 90, "scope": "hero"}), "a hero with 90 kills")
	check(not check_it.call({"kind": "stat_at_least", "stat": "kills", "value": 91, "scope": "hero"}), "no hero with 91")
	check(not check_it.call({"kind": "stat_at_least", "stat": "kills", "value": 50, "scope": "hero", "class_id": "mage"}), "the mage has 10")
	check(check_it.call({"kind": "stat_at_most", "stat": "downs", "value": 0, "scope": "hero", "class_id": "warrior"}), "the warrior never went down")
	check(check_it.call({"kind": "run_flag", "flag": "victory"}), "run_flag defaults to true")
	check(not check_it.call({"kind": "run_flag", "flag": "hardcore"}), "hardcore is off")
	check(check_it.call({"kind": "run_flag", "flag": "hardcore", "value": false}), "an expected false")
	check(check_it.call({"kind": "run_flag", "flag": "mode", "value": "normal"}), "text flag")
	check(not check_it.call({"kind": "run_flag", "flag": "no_downs"}), "downs happened")
	check(check_it.call({"kind": "class_in_party", "class_id": "mage"}), "class_in_party")
	check(not check_it.call({"kind": "class_in_party", "class_id": "rogue"}), "no rogue")
	p.add_counter(&"total:kills", 500)
	check(check_it.call({"kind": "counter_at_least", "counter": "total:kills", "value": 500}), "counter_at_least")
	check(not check_it.call({"kind": "counter_at_least", "counter": "total:kills", "value": 501}), "counter too low")
	p.set_class_progress(&"warrior", 0, 8)
	check(check_it.call({"kind": "class_level_at_least", "class_id": "warrior", "value": 8}), "class_level_at_least")
	check(not check_it.call({"kind": "class_level_at_least", "class_id": "mage", "value": 2}), "the mage is level 1")
	p.unlock(Profile.KIND_TITLE, &"champion")
	check(check_it.call({"kind": "unlocked", "unlock_kind": "title", "id": "champion"}), "unlocked")
	check(not check_it.call({"kind": "unlocked", "unlock_kind": "title", "id": "nobody"}), "not unlocked")
	var yes := {"kind": "run_flag", "flag": "victory"}
	var no := {"kind": "run_flag", "flag": "hardcore"}
	check(check_it.call({"kind": "all_of", "conditions": [yes, yes]}), "all_of")
	check(not check_it.call({"kind": "all_of", "conditions": [yes, no]}), "all_of: one fails")
	check(check_it.call({"kind": "all_of", "conditions": []}), "all_of: empty is true")
	check(check_it.call({"kind": "any_of", "conditions": [no, yes]}), "any_of")
	check(not check_it.call({"kind": "any_of", "conditions": [no, no]}), "any_of: none")
	check(not check_it.call({"kind": "any_of", "conditions": []}), "any_of: empty is false")
	check(check_it.call({"kind": "not", "condition": no}), "not")
	check(not check_it.call({"kind": "not", "condition": yes}), "not: inverted")
	check(not check_it.call({"kind": "no_such_kind"}), "an unknown kind is false")
	check(not AchievementEngine.check({"kind": "run_flag", "flag": "victory"}, p, RunReport.new()), "an empty report is no win")


func test_achievements_unlock_once_and_grant_their_rewards() -> void:
	var p := Profile.fresh()
	var rewards: Array[Dictionary] = [
		{"kind": "class", "id": "hunter"},
		{"kind": "difficulty", "id": "pungent", "class_id": "warrior"},
		{"kind": "title", "id": "survivor"},
	]
	var win := _achievement("win_normal", AchievementEngine.COND_RUN_FLAG, {"flag": "victory"}, rewards, 10)
	var lose := _achievement("never", AchievementEngine.COND_RUN_FLAG, {"flag": "abandoned"}, [], 5)
	var defs := _defs([win, lose])
	var ids := AchievementEngine.evaluate(p, _report(true), defs, 1700)
	check_eq(ids, [&"win_normal"] as Array[StringName], "only the one that holds")
	check_eq(p.achievements[&"win_normal"], 1700, "the unlock time")
	check(p.has_unlock(Profile.KIND_CLASS, &"hunter") and p.has_unlock(Profile.KIND_TITLE, &"survivor"), "rewards recorded")
	check(p.has_unlock(Profile.KIND_DIFFICULTY, &"pungent", &"warrior") and not p.has_unlock(Profile.KIND_DIFFICULTY, &"pungent", &"mage"),
			"a class-scoped reward for its class")
	check_eq(AchievementEngine.evaluate(p, _report(true), defs, 1800), [] as Array[StringName], "never twice")
	check_eq(p.achievements[&"win_normal"], 1700, "the first time stays")
	check_eq(AchievementEngine.points_of(p, defs), 10, "points of the unlocked ones")
	check(AchievementEngine.evaluate(null, _report(), defs).is_empty(), "no profile, no crash")
	check_eq(AchievementEngine.evaluate(Profile.fresh(), null, defs).size(), 0, "no report: report conditions are false")


func test_achievements_chain_to_a_fixpoint_whatever_the_order() -> void:
	var p := Profile.fresh()
	var meta_points := _achievement("collector", AchievementEngine.COND_POINTS_AT_LEAST, {"value": 15}, [], 1)
	var count := _achievement("triple", AchievementEngine.COND_ACHIEVEMENTS_AT_LEAST, {"count": 3}, [], 1)
	var a := _achievement("a", AchievementEngine.COND_RUN_FLAG, {"flag": "victory"}, [], 10)
	var b := _achievement("b", AchievementEngine.COND_CLASS_IN_PARTY, {"class_id": "warrior"}, [], 5)
	var ids := AchievementEngine.evaluate(p, _report(true), _defs([meta_points, count, a, b]), 5)
	check_eq(ids.size(), 4, "all four in one call, although the dependent ones come first in the list")
	check(ids.find(&"collector") > ids.find(&"a") and ids.find(&"collector") > ids.find(&"b"), "the points achievement came after its sources")


func test_run_counters() -> void:
	var p := Profile.fresh()
	var r := _report(true, {"kills": 40, "wave": 25}, ["warrior", "warrior", "mage"])
	AchievementEngine.update_counters(p, r)
	check_eq(p.counter(&"runs"), 1, "runs")
	check_eq(p.counter(&"wins"), 1, "wins")
	check_eq(p.counter(&"runs:warrior"), 1, "a class counts once even with two heroes")
	check_eq(p.counter(&"wins:mage"), 1, "wins per class")
	check_eq(p.counter(&"total:kills"), 40, "total")
	check_eq(p.counter(&"best:kills"), 40, "best")
	AchievementEngine.update_counters(p, _report(false, {"kills": 10, "wave": 9}, ["mage"]))
	check_eq(p.counter(&"runs"), 2, "two runs")
	check_eq(p.counter(&"wins"), 1, "a defeat is no win")
	check_eq(p.counter(&"wins:mage"), 1, "no mage win added")
	check_eq(p.counter(&"runs:mage"), 2, "mage runs")
	check_eq(p.counter(&"total:kills"), 50, "totals add up")
	check_eq(p.counter(&"best:kills"), 40, "the best stays")
	check(not p.counters.has(&"total:bosses_killed"), "a stat that is 0 stores no counter")


func test_meta_checks_achievements_saves_and_emits() -> void:
	_use_file()
	var a := _achievement("ten_kills", AchievementEngine.COND_COUNTER_AT_LEAST, {"counter": "total:kills", "value": 10})
	Db.achievements = {&"ten_kills": a}
	var got: Array[StringName] = []
	var on_unlock := func(id: StringName) -> void: got.append(id)
	Meta.achievement_unlocked.connect(on_unlock)
	check(Meta.check_achievements(_report()).is_empty(), "nothing yet")
	Meta.profile.add_counter(&"total:kills", 12)
	Meta.clock_override = 4242
	var ids := Meta.check_achievements()
	Meta.achievement_unlocked.disconnect(on_unlock)
	check_eq(ids, [&"ten_kills"] as Array[StringName], "unlocked outside a run")
	check_eq(got, [&"ten_kills"] as Array[StringName], "signal emitted")
	check_eq(Meta.save_count, 1, "saved")
	check_eq(Profile.load_file(_tmp_path).achievements[&"ten_kills"], 4242, "with the injected clock")
	check_eq(Meta.achievement_points(), 0, "no points on this one")
	check(Meta.check_achievements().is_empty(), "and only once")


func test_a_content_package_can_register_a_condition() -> void:
	check(AchievementEngine.register_condition(&"test_cond", func(c: Dictionary, _p: Profile, r: RunReport, _d: Array) -> bool:
		return r.stat(&"kills") == float(c.get("exactly", 0))), "registered")
	check(not AchievementEngine.register_condition(AchievementEngine.COND_RUN_FLAG, func(_c, _p, _r, _d) -> bool: return true), "a built-in kind cannot be replaced")
	var a := _achievement("custom", &"test_cond", {"exactly": 7})
	check(AchievementEngine.validate(a).is_empty(), "a registered kind validates")
	check_eq(AchievementEngine.evaluate(Profile.fresh(), _report(true, {"kills": 6}), _defs([a])).size(), 0, "not 6")
	check_eq(AchievementEngine.evaluate(Profile.fresh(), _report(true, {"kills": 7}), _defs([a])).size(), 1, "exactly 7")
	AchievementEngine.unregister_condition(&"test_cond")
	check(not AchievementEngine.validate(a).is_empty(), "gone again: unknown kind")


func test_validation_names_what_is_wrong() -> void:
	var good := _achievement("good", AchievementEngine.COND_STAT_AT_LEAST, {"stat": "kills", "value": 5}, [{"kind": "title", "id": "x"}], 5)
	check_eq(AchievementEngine.validate(good), [] as Array[String], "a good one")
	check(not AchievementEngine.validate(_achievement("", AchievementEngine.COND_RUN_FLAG, {"flag": "victory"})).is_empty(), "empty id")
	check(not AchievementEngine.validate(_achievement("x", &"nope", {})).is_empty(), "unknown condition kind")
	check(not AchievementEngine.validate(_achievement("x", AchievementEngine.COND_STAT_AT_LEAST, {"value": 5})).is_empty(), "missing stat")
	check(not AchievementEngine.validate(_achievement("x", AchievementEngine.COND_STAT_AT_LEAST, {"stat": "no_such_stat", "value": 5})).is_empty(), "unknown run stat")
	check(AchievementEngine.validate(_achievement("x", AchievementEngine.COND_STAT_AT_LEAST, {"stat": "kills", "value": 5, "scope": "hero"})).is_empty(), "kills is a hero stat too")
	check(not AchievementEngine.validate(_achievement("x", AchievementEngine.COND_STAT_AT_LEAST, {"stat": "wave", "value": 5, "scope": "hero"})).is_empty(), "wave is no hero stat")
	check(not AchievementEngine.validate(_achievement("x", AchievementEngine.COND_ALL_OF, {"conditions": [{"kind": "nope"}]})).is_empty(), "nested problems are found")
	check(not AchievementEngine.validate(_achievement("x", AchievementEngine.COND_RUN_FLAG, {"flag": "victory"}, [{"kind": "bogus", "id": "x"}])).is_empty(), "reward of an unknown kind")
	check(not AchievementEngine.validate(_achievement("x", AchievementEngine.COND_RUN_FLAG, {"flag": "victory"}, [{"kind": "difficulty", "id": "pungent"}])).is_empty(), "a difficulty reward needs its class")
	check(not AchievementEngine.validate(null).is_empty(), "null")


func test_shipped_data_is_valid() -> void:
	for a in Db.achievement_list():
		check_eq(AchievementEngine.validate(a), [] as Array[String], "achievement %s" % a.id)
	var ids: Dictionary[StringName, bool] = {}
	for a in Db.achievement_list():
		check(not ids.has(a.id), "unique achievement id %s" % a.id)
		ids[a.id] = true
	for key in Db.unlock_gates:
		var g := Db.unlock_gates[key]
		check(g.kind in Profile.KINDS and g.id != &"", "gate %s: a known kind and an id" % key)
		match g.kind:
			Profile.KIND_CLASS:
				check(Db.get_class_data(g.id) != null, "gate %s: the class exists" % key)
			Profile.KIND_ABILITY:
				check(Db.get_ability(g.id) != null, "gate %s: the ability exists" % key)
			Profile.KIND_CAPSTONE_TREE:
				check(Db.get_talent_tree(g.id) != null, "gate %s: the tree exists" % key)
			Profile.KIND_LEGENDARY:
				check(Db.get_unique(g.id) != null or String(g.id).begins_with("legendary_"), "gate %s: the Legendary exists" % key)


# --- Seeds through Meta -------------------------------------------------------------------------

func test_the_seeds_wallet_through_meta() -> void:
	_use_file()
	var log: Array[Vector2i] = []
	var on_change := func(total: int, delta: int) -> void: log.append(Vector2i(total, delta))
	Meta.seeds_changed.connect(on_change)
	check_eq(Meta.seeds(), 0, "empty")
	check(not Meta.can_afford_seeds(1), "cannot afford")
	check_eq(Meta.earn_seeds(40), 40, "earn")
	check_eq(Meta.earn_seeds(0), 40, "zero earns nothing")
	check(Meta.can_afford_seeds(40) and not Meta.can_afford_seeds(41), "can afford")
	check(Meta.spend_seeds(15), "spend")
	check(not Meta.spend_seeds(26), "too poor")
	check(not Meta.spend_seeds(-1), "negative spend refused")
	Meta.seeds_changed.disconnect(on_change)
	check_eq(log, [Vector2i(40, 40), Vector2i(25, -15)] as Array[Vector2i], "the signal reports totals and deltas")
	check_eq(Meta.seeds(), 25, "wallet")
	check_eq(Profile.load_file(_tmp_path).seeds, 25, "saved after each change outside a run")
	check_eq(Meta.save_count, 2, "one save per change")


# --- Lobby selections ---------------------------------------------------------------------------

func test_slot_selections_default_to_empty_and_reach_the_player() -> void:
	RunState.start_run(1, 99)
	var slot := Fakes.make_slot(0, &"warrior")
	check(slot.seasonings.is_empty() and slot.heirloom == &"" and slot.looks.is_empty(), "empty by default")
	check(slot.has_meta_selection() == false, "no selection")
	var plain := Player.create(slot)
	check(plain.seasonings.is_empty() and plain.heirloom_id == &"" and plain.look_overrides.is_empty(), "the player gets nothing")
	plain.free()
	slot.seasonings = [&"ssn_smoked_paprika", &"ssn_cracked_pepper"]  # (real Warrior Seasonings: the hero keeps those it can carry)
	slot.heirloom = &"heir_apron"  # (a real Heirloom: the hero drops one it cannot carry, M9 PATCH)
	slot.looks = {&"head": &"iron_helm"}
	check(slot.has_meta_selection(), "a selection")
	var p := Player.create(slot)
	check_eq(p.seasonings, [&"ssn_smoked_paprika", &"ssn_cracked_pepper"] as Array[StringName], "the Seasonings arrive")
	check_eq(p.heirloom_id, &"heir_apron", "the Heirloom arrives")
	check_eq(p.look_overrides, {&"head": &"iron_helm"} as Dictionary[StringName, StringName], "the look overrides arrive")
	slot.seasonings.append(&"ssn_sea_salt")
	check_eq(p.seasonings.size(), 2, "the player has its own copy")
	p.free()


func test_the_lobby_remembers_selections_per_class() -> void:
	var profile := _use_fresh()
	profile.unlock(Profile.KIND_SEASONING, &"smoked_paprika")
	profile.unlock(Profile.KIND_HEIRLOOM, &"heir_apron")
	profile.set_class_progress(&"warrior", 0, 5)  # (the Heirloom slot opens at Class Level 5: the lobby drops a pick a class has no slot for)
	var warrior := Fakes.make_slot(0, &"warrior")
	warrior.seasonings = [&"smoked_paprika", &"never_bought"]
	warrior.heirloom = &"heir_apron"
	Meta.remember_loadout(warrior)
	check_eq(profile.loadout(&"warrior")["seasonings"].size(), 2, "remembered as picked")
	# A slot that changes to the warrior gets what the profile owns of it.
	var other := Fakes.make_slot(1, &"warrior")
	Meta.apply_loadout(other)
	check_eq(other.seasonings, [&"smoked_paprika"] as Array[StringName], "only owned Seasonings come back")
	check_eq(other.heirloom, &"heir_apron", "the owned Heirloom")
	var mage := Fakes.make_slot(2, &"mage")
	Meta.apply_loadout(mage)
	check(not mage.has_meta_selection(), "another class: nothing remembered")
	# The dev profile: nothing is selected, nothing remembered.
	Meta.configure(&"dev", "", true)
	var dev_slot := Fakes.make_slot(3, &"warrior")
	Meta.apply_loadout(dev_slot)
	check(not dev_slot.has_meta_selection(), "dev profile: nothing selected")
	dev_slot.seasonings = [&"x"]
	Meta.remember_loadout(dev_slot)
	check(Meta.profile.loadouts.is_empty(), "dev profile: nothing remembered")
	# The lobby applies the remembered selection when a class is picked.
	Meta.profile = profile
	var lobby := Lobby.create()
	_nodes.append(lobby)
	UiFakes.add_to_root(tree, lobby)
	var input := UiFakes.HumanInput.new("pad:a")
	var joined := PlayerManager.join(input, Db.get_class_data(Db.class_ids[1]))
	UiFakes.step(lobby)
	check(not joined.has_meta_selection(), "a class with nothing remembered")
	UiFakes.nudge(lobby, input, Vector2(-1, 0))
	check_eq(joined.class_data.id, Db.class_ids[0], "the player picked the first class (the warrior)")
	check_eq(joined.heirloom, &"heir_apron", "and got what is remembered for it")


func test_main_remembers_the_selections_at_run_start() -> void:
	var profile := _use_fresh()
	profile.unlock(Profile.KIND_SEASONING, &"ssn_smoked_paprika")
	profile.set_class_progress(&"warrior", 215, 3)  # (Class Level 3 opens the first Seasoning slot)
	_make_main()
	var bot := PlayerManager.add_bot(&"warrior", 1)
	bot.seasonings = [&"ssn_smoked_paprika"]
	main.start_run()
	check_eq(profile.loadout(&"warrior")["seasonings"], [&"ssn_smoked_paprika"] as Array[StringName], "remembered when the run starts")
	check_eq(main.players[0].seasonings, [&"ssn_smoked_paprika"] as Array[StringName], "and the hero has it")
