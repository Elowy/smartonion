extends TestCase
## M9 ACHIEVE-DIFF, achievements: the 40 AchievementData of data/achievements (ids, points, valid conditions, rewards
## that resolve), every one of them firing from a crafted RunReport / counters and unlocking its rewards through the
## profile (and not firing on a near miss), the Hunter / Shaman unlock path, the five locked Legendaries, the difficulty
## tiers the class-pair achievements open, the Seeds and point titles they pay, the conditions and counters added for
## them, the mid-run checks of Main with the HUD toast, and the end screen's block.

const UiFakes := preload("res://tests/ui_fakes.gd")
const DT := 1.0 / 60.0
const CLASSES: Array[StringName] = [&"warrior", &"mage", &"paladin", &"rogue", &"warlock", &"hunter", &"shaman"]
const ENVS: Array[StringName] = [&"forest_ruin", &"cemetery", &"swamp", &"volcano", &"ice_cave"]

var main: Main
var nodes: Array[Node] = []
var _saved_profile: Profile
var _saved_path := ""
var _saved_persist := false
var _saved_clock := -1
var _saved_gates: Dictionary[StringName, UnlockGateData] = {}
var _saved_listeners: Array = []
var _tmp := "user://m9_achievements_test_%d.json" % OS.get_process_id()


func before_each() -> void:
	_saved_profile = Meta.profile
	_saved_path = Meta.path
	_saved_persist = Meta.persist
	_saved_clock = Meta.clock_override
	_saved_gates = Db.unlock_gates.duplicate()
	# The achievement tests count only the achievement Seeds: the Class XP / Seeds listeners of the levels stay out.
	_saved_listeners = Meta._listeners.duplicate()
	Meta.remove_run_listener(ClassLevels.LISTENER_XP)
	Meta.remove_run_listener(ClassLevels.LISTENER_SEEDS)
	Meta._pending_unlocks.clear()
	UiFakes.reset_players()
	RunState.start_run(2, 77)
	tree.paused = false


func after_each() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()
	Meta.profile = _saved_profile
	Meta._listeners = _saved_listeners
	Meta.path = _saved_path
	Meta.persist = _saved_persist
	Meta.clock_override = _saved_clock
	Meta._pending_unlocks.clear()
	Meta._batching = false
	Db.unlock_gates = _saved_gates
	for suffix in ["", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(_tmp + suffix):
			DirAccess.remove_absolute(_tmp + suffix)
	tree.paused = false
	UiFakes.reset_players()
	Enemy.invalidate_player_cache()
	RunState.start_run(1, 77)


# --- Helpers ------------------------------------------------------------------------------------

func _fresh() -> Profile:
	Meta.profile = Profile.fresh()
	Meta.persist = false
	Meta.path = ""
	return Meta.profile


func _party(ids: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in ids:
		out.append(StringName(str(id)))
	return out


## A run report from plain values. [param party] class ids, [param stats], [param flags] (overrides), [param heroes].
func _report(victory: bool, party: Array = ["warrior"], stats: Dictionary = {}, flags: Dictionary = {},
		heroes: Array[Dictionary] = []) -> RunReport:
	return RunReport.make(_party(party), victory, stats, flags, heroes)


## A win: the final boss is down, nobody went down, a party of [param party].
func _win(party: Array = ["warrior"], stats: Dictionary = {}, flags: Dictionary = {}) -> RunReport:
	var s := {"wave": 25, "waves_cleared": 25, "run_time": 3000.0, "downs": 0}
	s.merge(stats, true)
	return _report(true, party, s, flags)


func _ach(id: String) -> AchievementData:
	return Db.get_achievement(StringName("ach_" + id))


## True when achievement [param id] fires for [param report] on [param profile] (evaluated alone); the profile is
## changed (the unlock and its rewards).
func _fires(id: String, report: RunReport, profile: Profile) -> bool:
	var def := _ach(id)
	check(def != null, "ach_%s exists" % id)
	if def == null:
		return false
	var defs: Array[AchievementData] = [def]
	var fired := StringName("ach_" + id) in AchievementEngine.evaluate(profile, report, defs, 1000)
	if fired:
		check(profile.has_achievement(def.id), "ach_%s is recorded" % id)
		for r in def.rewards:  # (every reward of an achievement that fires is in the profile)
			check(profile.has_unlock(StringName(str(r["kind"])), StringName(str(r["id"])), StringName(str(r.get("class_id", "")))),
					"ach_%s: the reward %s %s is unlocked" % [id, r["kind"], r["id"]])
	return fired


## [method _fires] on a fresh profile with [param counters] ({name: value}) set first.
func _fires_with(id: String, report: RunReport, counters: Dictionary = {}) -> bool:
	var p := Profile.fresh()
	for key: Variant in counters:
		p.counters[StringName(str(key))] = int(counters[key])
	return _fires(id, report, p)


func _hero(class_id: String, facts: Dictionary) -> Dictionary:
	var h := {"slot": 0, "class_id": class_id, "alive": true}
	h.merge(facts, true)
	return h


func _heroes(list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h: Variant in list:
		out.append(h)
	return out


func _gate(kind: StringName, id: StringName, hint: String = "") -> void:
	var g := UnlockGateData.new()
	g.kind = kind
	g.id = id
	g.hint = hint
	Db.add_unlock_gate(g)


func _make_main(opts: LaunchOptions = null) -> Main:
	main = Main.create(opts if opts != null else LaunchOptions.new())
	tree.root.add_child(main)
	return main


func _bots(count: int) -> void:
	for i in count:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)


func _clear_wave_and_wait() -> void:
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	main._physics_process(Main.WAVE_END_DELAY + 0.01)


# --- The data -----------------------------------------------------------------------------------

func test_forty_achievements_worth_615_points() -> void:
	var list := Db.achievement_list()
	check_eq(list.size(), 40, "forty achievements")
	var points := 0
	var seen: Dictionary = {}
	for a in list:
		points += a.points
		check(String(a.id).begins_with("ach_"), "%s has the ach_ prefix" % a.id)
		check(not seen.has(a.id), "%s is unique" % a.id)
		seen[a.id] = true
		check(a.display_name != "" and a.description != "", "%s has a name and a text" % a.id)
		check_eq(AchievementEngine.validate(a), [] as Array[String], "%s is valid" % a.id)
	check_eq(points, 615, "615 points in all")
	var names: Dictionary = {}
	for a in list:
		check(not names.has(a.display_name), "the name %s is used once" % a.display_name)
		names[a.display_name] = true


func test_the_point_values_of_the_design() -> void:
	var table := {
		"green_shoot": 5, "salt_of_earth": 5, "regular": 5, "tenth_hour": 10, "harvest_home": 15, "lone_bulb": 20,
		"full_table": 15, "untouched": 25, "swift_harvest": 20, "hardcore_win": 25, "five_gardens": 20, "seven_bulbs": 30,
		"endless_40": 25, "first_pungent": 20, "first_tear": 30, "tear_all": 50, "gremlin_roundup": 10,
		"need_legendary": 10, "relic_hunter": 10, "peak_of_the_tree": 10, "master_chef": 10, "dressed_up": 10,
		"cellar_cleaner": 15, "second_chance": 10, "level_thirty": 25, "wardrobe_150": 10,
	}
	for id: String in table:
		check_eq(_ach(id).points, table[id], "%s points" % id)
	for c in CLASSES:
		check_eq(_ach("clear_" + c).points, 10, "clear_%s points" % c)
		check_eq(_ach("pungent_" + c).points, 15, "pungent_%s points" % c)


func test_every_reward_resolves() -> void:
	var legendaries := 0
	for a in Db.achievement_list():
		for r in a.rewards:
			var kind := StringName(str(r["kind"]))
			var id := StringName(str(r["id"]))
			match kind:
				Profile.KIND_CLASS:
					check(Db.get_class_data(id) != null, "%s: class %s exists" % [a.id, id])
				Profile.KIND_LEGENDARY:
					legendaries += 1
					var u := Db.get_unique(id)
					check(u != null and u.rarity == Items.Rarity.LEGENDARY, "%s: %s is a hand-made Legendary" % [a.id, id])
					check(Db.get_unlock_gate(Profile.KIND_LEGENDARY, id) != null, "%s: %s is gated" % [a.id, id])
				Profile.KIND_DIFFICULTY:
					check(Difficulty.tier_index(id) > 0, "%s: %s is a tier above Normal" % [a.id, id])
					check(Db.get_class_data(StringName(str(r.get("class_id", "")))) != null, "%s: for a real class" % a.id)
				Profile.KIND_TITLE:
					check(str(r.get("name", "")) != "" and PlayerTitles.name_of(id) == str(r["name"]), "%s: the title %s is named" % [a.id, id])
				Profile.KIND_HEIRLOOM, Profile.KIND_COSMETIC:
					check(str(r.get("name", "")) != "", "%s: %s has a display name" % [a.id, id])
				_:
					check(false, "%s: unexpected reward kind %s" % [a.id, kind])
	check_eq(legendaries, 5, "five Legendaries are locked behind achievements")


func test_the_five_legendary_gates() -> void:
	var ids := [&"stormcaller", &"sash_of_twin_souls", &"vial_of_distilled_adrenaline", &"crown_of_ashes", &"tearjerker"]
	for id: StringName in ids:
		var g := Db.get_unlock_gate(Profile.KIND_LEGENDARY, id)
		check(g != null and g.hint != "", "%s has a gate with a hint" % id)
		check(Db.get_unique(id) != null, "%s exists" % id)
	_fresh()
	for id: StringName in ids:
		check(not Meta.is_unlocked(Profile.KIND_LEGENDARY, id), "%s is locked for a new player" % id)
		check(not ItemGenerator.unique_available(Db.get_unique(id), ItemGenerator.Source.LOOT, 30), "and out of the loot pool")
	Meta.profile = Profile.dev()
	for id: StringName in ids:
		check(ItemGenerator.unique_available(Db.get_unique(id), ItemGenerator.Source.LOOT, 30), "%s is in the pool for the dev profile" % id)
	check(Meta.unlock_hint(Profile.KIND_LEGENDARY, &"stormcaller").contains("Tenth Hour"), "the hint names the achievement")


# --- Every achievement fires from crafted data ---------------------------------------------------------

func test_the_first_three_open_the_classes() -> void:
	check(_fires_with("green_shoot", _report(false, ["warrior"], {"waves_cleared": 5})), "wave 5 cleared")
	check(not _fires_with("green_shoot", _report(false, ["warrior"], {"waves_cleared": 4})), "four is not enough")
	check(_fires_with("salt_of_earth", _report(false, ["warrior"], {"kills": 100}), {"total:kills": 400}), "500 slain in total")
	check(not _fires_with("salt_of_earth", _report(false, ["warrior"], {"kills": 99}), {"total:kills": 400}), "499 is not")
	var counted := _report(false, ["warrior"], {"kills": 100})
	counted.counted = true  # (the run is already in the lifetime counter: never counted twice)
	check(not _fires_with("salt_of_earth", counted, {"total:kills": 480}), "a counted run is not added again")
	check(_fires_with("salt_of_earth", counted, {"total:kills": 500}), "but the lifetime total counts")
	check(_fires_with("regular", _report(false), {"runs_long": 3}), "three runs that reached wave 3")
	check(not _fires_with("regular", _report(false), {"runs_long": 2}), "two do not")


func test_the_boss_and_win_achievements() -> void:
	check(_fires_with("tenth_hour", _report(false, ["mage"], {"boss_wave_down": 10, "wave": 10})), "the wave 10 boss is down")
	check(not _fires_with("tenth_hour", _report(false, ["mage"], {"boss_wave_down": 9})), "not before")
	check(_fires_with("harvest_home", _win()), "a win")
	check(not _fires_with("harvest_home", _report(false)), "a defeat is no win")
	# The endless mode: the run ends in defeat, but the wave-25 boss died.
	var endless := _report(false, ["warrior"], {"boss_wave_down": 25, "wave": 31}, {"endless": true})
	check(endless.won(), "the endless final boss counts as a win")
	check(_fires_with("harvest_home", endless), "so Harvest Home fires there too")
	check(_fires_with("lone_bulb", _win(["warrior"])), "a solo win")
	check(not _fires_with("lone_bulb", _win(["warrior", "mage"])), "not with two")
	check(_fires_with("full_table", _win(["warrior", "mage", "paladin", "rogue"])), "a party of four")
	check(not _fires_with("full_table", _win(["warrior", "mage", "paladin"])), "three is not a full table")
	check(_fires_with("untouched", _win(["warrior"], {"downs": 0})), "nobody went down")
	check(not _fires_with("untouched", _win(["warrior"], {"downs": 1})), "one down spoils it")
	check(_fires_with("swift_harvest", _win(["warrior"], {"run_time": 2400.0})), "40 minutes")
	check(not _fires_with("swift_harvest", _win(["warrior"], {"run_time": 2401.0})), "a second slower")
	check(not _fires_with("swift_harvest", _win(["warrior"], {"run_time": 100.0}, {"mode": "endless"})), "Normal mode only")
	check(_fires_with("hardcore_win", _win(["warrior"], {}, {"hardcore": true})), "hardcore")
	check(not _fires_with("hardcore_win", _win()), "not on a standard run")


func test_the_collection_achievements_read_the_counters() -> void:
	var gardens: Dictionary = {}
	for e in ENVS:
		gardens["env_wins:" + e] = 1
	check(_fires_with("five_gardens", _report(false), gardens), "a win in each arena")
	gardens.erase("env_wins:swamp")
	check(not _fires_with("five_gardens", _report(false), gardens), "four arenas are not five")
	var bulbs: Dictionary = {}
	var tears: Dictionary = {}
	for c in CLASSES:
		bulbs["wins:%s:normal" % c] = 1
		tears["wins:%s:tear_jerker" % c] = 1
	check(_fires_with("seven_bulbs", _report(false), bulbs), "a win with each class")
	bulbs.erase("wins:shaman:normal")
	check(not _fires_with("seven_bulbs", _report(false), bulbs), "six are not seven")
	check(_fires_with("tear_all", _report(false), tears), "Tear-Jerker with all seven")
	tears["wins:hunter:tear_jerker"] = 0
	check(not _fires_with("tear_all", _report(false), tears), "one class missing")
	check(not _fires_with("tear_all", _report(false), bulbs), "Normal wins are not Tear-Jerker wins")


func test_the_difficulty_achievements() -> void:
	var normal := _win(["mage"])
	var pungent := _win(["mage"], {}, {"difficulty": "pungent"})
	var tear := _win(["mage"], {}, {"difficulty": "tear_jerker"})
	check(not _fires_with("first_pungent", normal), "Normal does not")
	check(_fires_with("first_pungent", pungent), "Pungent")
	check(_fires_with("first_pungent", tear), "Tear-Jerker is above Pungent")
	check(not _fires_with("first_tear", pungent), "Pungent is not Tear-Jerker")
	check(_fires_with("first_tear", tear), "Tear-Jerker")
	check(not _fires_with("first_pungent", _report(false, ["mage"], {}, {"difficulty": "pungent"})), "a defeat on Pungent is no win")
	check(_fires_with("endless_40", _report(false, ["mage"], {"wave": 40}, {"endless": true})), "wave 40 in the endless mode")
	check(not _fires_with("endless_40", _report(false, ["mage"], {"wave": 39}, {"endless": true})), "wave 39")
	check(not _fires_with("endless_40", _report(false, ["mage"], {"wave": 40}, {"endless": false})), "a normal run cannot reach it")


func test_the_in_run_achievements() -> void:
	check(_fires_with("gremlin_roundup", _report(false, ["rogue"], {"goblins_killed": 3})), "three Coin Gremlins")
	check(not _fires_with("gremlin_roundup", _report(false, ["rogue"], {"goblins_killed": 2})), "two")
	check(_fires_with("need_legendary", _report(false, ["rogue"], {"need_legendary_wins": 1})), "a Need roll on a Legendary")
	check(not _fires_with("need_legendary", _report(false, ["rogue"], {"need_wins": 5})), "Need wins on lesser items")
	check(_fires_with("relic_hunter", _report(false, ["rogue"], {"artifacts_dropped": 1})), "an Artifact drops")
	check(_fires_with("cellar_cleaner", _report(false, ["rogue"], {"dungeons_completed": 3})), "three dungeons")
	check(not _fires_with("cellar_cleaner", _report(false, ["rogue"], {"dungeons_completed": 2})), "two")
	check(_fires_with("second_chance", _report(false, ["rogue"], {"revives": 5})), "five revives")
	check(not _fires_with("second_chance", _report(false, ["rogue"], {"revives": 4})), "four")


func test_the_hero_achievements_read_one_hero() -> void:
	var plain := _heroes([_hero("warrior", {"capstones": 0, "rank5": 0, "sets_active": 1})])
	var capped := _heroes([_hero("warrior", {}), _hero("mage", {"capstones": 1})])
	check(_fires_with("peak_of_the_tree", _report(false, ["warrior", "mage"], {}, {}, capped)), "a capstone on some hero")
	check(not _fires_with("peak_of_the_tree", _report(false, ["warrior"], {}, {}, plain)), "none")
	check(_fires_with("master_chef", _report(false, ["mage"], {}, {}, _heroes([_hero("mage", {"rank5": 1})]))), "an ability at Rank V")
	check(not _fires_with("master_chef", _report(false, ["warrior"], {}, {}, plain)), "none")
	check(_fires_with("dressed_up", _report(false, ["mage"], {}, {}, _heroes([_hero("mage", {"sets_active": 2})]))), "two set bonuses on one hero")
	check(not _fires_with("dressed_up", _report(false, ["warrior"], {}, {}, plain)), "one")
	var split := _heroes([_hero("warrior", {"sets_active": 1}), _hero("mage", {"sets_active": 1})])
	check(not _fires_with("dressed_up", _report(false, ["warrior", "mage"], {}, {}, split)), "two heroes with one each do not add up")


func test_the_profile_achievements() -> void:
	var p := Profile.fresh()
	check(not _fires("level_thirty", _report(false), p), "no class at 30")
	p.set_class_progress(&"shaman", 33205, 30)
	check(_fires("level_thirty", _report(false), p), "any class at Class Level 30")
	var q := Profile.fresh()
	for i in 149:
		q.unlock(Profile.KIND_LOOK, StringName("g.head.0.0.%d" % i))
	check(not _fires("wardrobe_150", _report(false), q), "149 looks")
	q.unlock(Profile.KIND_LOOK, &"s.head.some_set")
	check(_fires("wardrobe_150", _report(false), q), "150 looks")


func test_a_class_pair_opens_the_next_tier_for_that_class() -> void:
	for c in CLASSES:
		var win := _win([c])
		var p := Profile.fresh()
		check(not _fires("pungent_" + c, win, p), "%s: a Normal win is no Pungent win" % c)
		check(_fires("clear_" + c, win, p), "%s: a win with the class" % c)
		check(p.has_unlock(Profile.KIND_DIFFICULTY, &"pungent", c), "%s: Pungent opens for the class" % c)
		check(not p.has_unlock(Profile.KIND_DIFFICULTY, &"pungent", &"warrior") or c == &"warrior", "%s: and only for it" % c)
		check(not p.has_unlock(Profile.KIND_DIFFICULTY, &"tear_jerker", c), "%s: not Tear-Jerker yet" % c)
		var hard := _win([c], {}, {"difficulty": "pungent"})
		check(_fires("pungent_" + c, hard, p), "%s: a Pungent win" % c)
		check(p.has_unlock(Profile.KIND_DIFFICULTY, &"tear_jerker", c), "%s: Tear-Jerker opens" % c)
		var other := Profile.fresh()
		check(not _fires("clear_" + c, _win(["warrior" if c != &"warrior" else "mage"]), other), "%s: another class's win does not count" % c)


func test_a_defeat_opens_nothing() -> void:
	var p := Profile.fresh()
	var defs := Db.achievement_list()
	var ids := AchievementEngine.evaluate(p, _report(false, ["warrior"], {"wave": 4, "waves_cleared": 3}), defs, 5)
	check(ids.is_empty(), "a short lost run unlocks nothing: %s" % [ids])


func test_a_win_pays_its_rewards_into_the_profile() -> void:
	var p := Profile.fresh()
	var ids := AchievementEngine.evaluate(p, _win(["warrior"]), Db.achievement_list(), 5)
	for id in [&"ach_harvest_home", &"ach_lone_bulb", &"ach_untouched", &"ach_clear_warrior"]:
		check(id in ids, "%s unlocked" % id)
	check(p.has_unlock(Profile.KIND_TITLE, &"title_harvester"), "the Harvester title")
	check(p.has_unlock(Profile.KIND_HEIRLOOM, &"heir_harvest_signet"), "its heirloom")
	check(p.has_unlock(Profile.KIND_LEGENDARY, &"vial_of_distilled_adrenaline"), "the Vial")
	check(p.has_unlock(Profile.KIND_DIFFICULTY, &"pungent", &"warrior"), "Pungent for the warrior")
	check(not p.has_unlock(Profile.KIND_LEGENDARY, &"sash_of_twin_souls"), "but not the Sash (a full table)")


# --- Hunter and Shaman -----------------------------------------------------------------------------------

func _class_gates() -> void:
	_gate(Profile.KIND_CLASS, &"hunter", "Clear wave 5 in a run")
	_gate(Profile.KIND_CLASS, &"shaman", "Slay 500 enemies")


func test_hunter_and_shaman_unlock_in_the_first_runs() -> void:
	_class_gates()
	var p := _fresh()
	check(not Meta.is_class_unlocked(&"hunter") and not Meta.is_class_unlocked(&"shaman"), "both start locked")
	check(Meta.is_class_unlocked(&"warrior") and Meta.is_class_unlocked(&"mage"), "the five others are open")
	Meta.clock_override = 100
	# Run 1: wave 5 reached with 160 kills.
	Meta.record_run(_report(false, ["warrior", "mage"], {"wave": 6, "waves_cleared": 5, "kills": 160}))
	check(Meta.is_class_unlocked(&"hunter"), "the Hunter opens with the first run to wave 5")
	check(not Meta.is_class_unlocked(&"shaman"), "the Shaman is not there yet (160 kills)")
	check(p.has_achievement(&"ach_green_shoot"), "Green Shoot")
	# Run 2: 340 more kills = 500 in total.
	Meta.record_run(_report(false, ["warrior"], {"wave": 4, "waves_cleared": 3, "kills": 340}))
	check(Meta.is_class_unlocked(&"shaman"), "the Shaman opens at 500 kills in total")
	check(p.has_achievement(&"ach_salt_of_earth"), "Salt of the Earth")


func test_regular_at_the_patch_is_the_safety_net() -> void:
	_class_gates()
	_fresh()
	for i in 3:
		check(not Meta.is_class_unlocked(&"hunter"), "locked before run %d" % (i + 1))
		Meta.record_run(_report(false, ["warrior"], {"wave": 3, "waves_cleared": 2, "kills": 10}))
	check(Meta.is_class_unlocked(&"hunter") and Meta.is_class_unlocked(&"shaman"), "three runs to wave 3 open both")
	check(Meta.profile.has_achievement(&"ach_regular"), "Regular at the Patch")
	# A run abandoned in the first fight does not count.
	_fresh()
	for i in 5:
		Meta.record_run(_report(false, ["warrior"], {"wave": 2, "waves_cleared": 1, "kills": 5}))
	check(not Meta.is_class_unlocked(&"hunter"), "runs that never reached wave 3 do not count")


func test_the_lobby_blocks_a_locked_class_and_unblocks_it() -> void:
	_class_gates()
	_fresh()
	UiFakes.reset_players()
	var lobby := Lobby.create()
	UiFakes.add_to_root(tree, lobby)
	nodes.append(lobby)
	var slot := PlayerManager.join(UiFakes.HumanInput.new("pad:a"), Db.get_class_data(&"hunter"))
	check_eq(lobby.ready_block_reason(slot), "Clear wave 5 in a run", "the hint is the reason")
	Meta.record_run(_report(false, ["mage"], {"wave": 6, "waves_cleared": 5}))
	check_eq(lobby.ready_block_reason(slot), "", "unblocked once the achievement unlocked")


# --- Seeds, titles and the counters -----------------------------------------------------------------------

func test_an_achievement_pays_five_seeds_a_point() -> void:
	var p := _fresh()
	Meta.record_run(_report(false, ["warrior"], {"wave": 6, "waves_cleared": 5, "kills": 10}))
	check(p.has_achievement(&"ach_green_shoot"), "Green Shoot (5 points)")
	check_eq(p.seeds, 25, "5 x 5 points")
	check_eq(Meta.last_result["achievement_seeds"], 25, "the run's result says so")
	check_eq(Meta.achievement_points(), 5, "the score")
	Meta.record_run(_report(false, ["warrior"], {"wave": 6, "waves_cleared": 5, "kills": 10}))
	check_eq(p.seeds, 25, "paid once")


func test_the_score_earns_titles() -> void:
	var p := _fresh()
	var points := 0
	for id in [&"ach_harvest_home", &"ach_lone_bulb", &"ach_untouched", &"ach_seven_bulbs", &"ach_first_tear", &"ach_tear_all"]:
		var a := Db.get_achievement(id)
		p.unlock_achievement(id, 1)
		points += a.points
	check_eq(points, 15 + 20 + 25 + 30 + 30 + 50, "170 points before the run")
	check(not p.has_unlock(Profile.KIND_TITLE, &"title_collector"), "no title yet")
	Meta.record_run(_report(false, ["warrior"], {"wave": 6, "waves_cleared": 5}))
	check_eq(Meta.achievement_points(), 175, "Green Shoot added 5")
	check(p.has_unlock(Profile.KIND_TITLE, &"title_collector"), "100 points: the Collector")
	check(not p.has_unlock(Profile.KIND_TITLE, &"title_archivist"), "250 not yet")
	check(&"title_collector" in (Meta.last_result["point_titles"] as Array), "listed in the result")
	check_eq(PlayerTitles.name_of(&"title_collector"), "the Collector", "named")
	check_eq(PlayerTitles.name_of(&"title_harvester"), "the Harvester", "an achievement title is named by its reward")
	check_eq(PlayerTitles.name_of(&"title_warrior"), "the Unbreakable", "a class title")
	check_eq(PlayerTitles.POINT_TITLES.size(), 4, "four point titles")
	check(&"title_completionist" in PlayerTitles.all_ids() and &"title_gardener" in PlayerTitles.all_ids(), "the title list")
	var q := Profile.fresh()
	check_eq(PlayerTitles.grant_for_points(q, 600).size(), 4, "600 points earn all four")
	check(PlayerTitles.grant_for_points(q, 600).is_empty(), "once")


func test_the_counters_a_run_leaves() -> void:
	var p := Profile.fresh()
	var win := _win(["mage", "mage", "rogue"], {"wave": 25}, {"difficulty": "pungent", "environment": "cemetery"})
	win.difficulty = &"pungent"
	win.environment = &"cemetery"
	AchievementEngine.update_counters(p, win)
	check(win.counted, "the report is marked as counted")
	check_eq(p.counter(&"runs"), 1, "a run")
	check_eq(p.counter(&"runs_long"), 1, "that reached wave 3")
	check_eq(p.counter(&"wins"), 1, "a win")
	check_eq(p.counter(&"wins:mage"), 1, "once per class even with two heroes")
	check_eq(p.counter(&"wins:mage:normal"), 1, "a Pungent win counts on Normal")
	check_eq(p.counter(&"wins:mage:pungent"), 1, "and on Pungent")
	check_eq(p.counter(&"wins:mage:tear_jerker"), 0, "not on Tear-Jerker")
	check_eq(p.counter(&"wins:rogue:pungent"), 1, "every class in the party")
	check_eq(p.counter(&"env_wins:cemetery"), 1, "the arena")
	var lost := _report(false, ["mage"], {"wave": 2, "waves_cleared": 1})
	AchievementEngine.update_counters(p, lost)
	check_eq(p.counter(&"runs"), 2, "a second run")
	check_eq(p.counter(&"runs_long"), 1, "a run that never reached wave 3 is not a long one")
	check_eq(p.counter(&"wins"), 1, "and no win")
	p.counters[&"wins:mage:normal"] = AchievementEngine.WIN_COUNTER_CAP
	AchievementEngine.update_counters(p, _win(["mage"]))
	check_eq(p.counter(&"wins:mage:normal"), 9999, "the win counters stop at 9999")
	p.counters[&"wins:mage:normal"] = 1
	var endless_win := _report(false, ["warrior"], {"wave": 31, "boss_wave_down": 25}, {"endless": true})
	endless_win.difficulty = &"tear_jerker"
	AchievementEngine.update_counters(p, endless_win)
	check_eq(p.counter(&"wins:warrior:tear_jerker"), 1, "the endless final boss is a win on its tier")
	check_eq(p.counter(&"wins:warrior:normal"), 1, "and on the lower ones")


func test_the_new_conditions_validate() -> void:
	check_eq(AchievementEngine.validate_condition({"kind": "total_at_least", "stat": "kills", "value": 5}), [] as Array[String], "total_at_least")
	check(not AchievementEngine.validate_condition({"kind": "total_at_least", "stat": "nonsense", "value": 5}).is_empty(), "an unknown stat")
	check(not AchievementEngine.validate_condition({"kind": "total_at_least", "stat": "kills"}).is_empty(), "a missing value")
	check_eq(AchievementEngine.validate_condition({"kind": "unlock_count_at_least", "unlock_kind": "look", "count": 3}), [] as Array[String], "unlock_count_at_least")
	check(not AchievementEngine.validate_condition({"kind": "unlock_count_at_least", "unlock_kind": "bogus", "count": 3}).is_empty(), "an unknown unlock kind")
	check_eq(AchievementEngine.validate_condition({"kind": "difficulty_at_least", "tier": "pungent"}), [] as Array[String], "difficulty_at_least")
	check(not AchievementEngine.validate_condition({"kind": "difficulty_at_least", "tier": "heroic"}).is_empty(), "an unknown tier")
	for kind in [AchievementEngine.COND_TOTAL_AT_LEAST, AchievementEngine.COND_UNLOCK_COUNT_AT_LEAST, AchievementEngine.COND_DIFFICULTY_AT_LEAST]:
		check(kind in AchievementEngine.CONDITION_KINDS, "%s is a built-in kind" % kind)
	for stat in [&"capstones", &"rank5", &"sets_active"]:
		check(stat in AchievementEngine.HERO_STATS, "%s is a hero stat" % stat)
	check(&"boss_wave_down" in RunReport.STAT_IDS and &"need_legendary_wins" in RunReport.STAT_IDS, "the new run stats")
	var live := _report(false, ["mage"], {"kills": 40})
	check(AchievementEngine.check({"kind": "total_at_least", "stat": "kills", "value": 60}, _with_counter(&"total:kills", 20), live), "a live run adds to the total")
	live.counted = true
	check(not AchievementEngine.check({"kind": "total_at_least", "stat": "kills", "value": 60}, _with_counter(&"total:kills", 20), live), "a counted one does not")


func _with_counter(name: StringName, value: int) -> Profile:
	var p := Profile.fresh()
	p.counters[name] = value
	return p


func test_texts_of_the_rewards() -> void:
	check_eq(AchievementTexts.reward_line({"kind": "class", "id": "hunter"}), "Class unlocked: Hunter", "a class")
	check_eq(AchievementTexts.reward_line({"kind": "legendary", "id": "stormcaller"}), "Legendary: Stormcaller", "a Legendary")
	check_eq(AchievementTexts.reward_line({"kind": "difficulty", "id": "pungent", "class_id": "mage"}), "Pungent unlocked for the Mage", "a tier")
	check_eq(AchievementTexts.reward_line({"kind": "title", "id": "title_harvester", "name": "the Harvester"}), "Title: the Harvester", "a title")
	check_eq(AchievementTexts.reward_line({"kind": "heirloom", "id": "heir_x", "name": "Test Signet"}), "Heirloom: Test Signet", "an heirloom")
	check_eq(AchievementTexts.reward_line({"kind": "cosmetic", "id": "dye_ember", "name": "Ember Orange"}), "Cosmetic: Ember Orange", "a cosmetic")
	check_eq(AchievementTexts.toast_detail(_ach("green_shoot")), "Class unlocked: Hunter", "one reward: the line itself")
	check(AchievementTexts.toast_detail(_ach("regular")).ends_with("(+1)"), "two rewards: the first and a count")
	check(AchievementTexts.toast_detail(_ach("relic_hunter")).begins_with("10 points"), "no reward: the payout")
	check_eq(AchievementTexts.payout_text(_ach("relic_hunter")), "10 points  ·  +50 Seeds", "what the achievement itself pays")
	for a in Db.achievement_list():
		check(AchievementTexts.toast_detail(a) != "", "%s has a toast line" % a.id)


# --- The toast ---------------------------------------------------------------------------------------------

func test_the_toast_queues_and_runs_out() -> void:
	var toast := AchievementToast.create()
	nodes.append(toast)
	tree.root.add_child(toast)
	check(not toast.is_showing(), "idle")
	toast.push(_ach("green_shoot"))
	toast.push(_ach("tenth_hour"))
	toast.push(null)
	check(toast.is_showing() and toast.current.id == &"ach_green_shoot", "the first shows at once")
	check_eq(toast.name_label.text, "Green Shoot", "its name")
	check_eq(toast.detail_label.text, "Class unlocked: Hunter", "and what it brings")
	check_eq(toast.pending_ids(), [&"ach_green_shoot", &"ach_tenth_hour"] as Array[StringName], "the second waits")
	toast._process(AchievementToast.SLIDE_TIME + 1.0)
	check(toast.current.id == &"ach_green_shoot", "still on show in the middle")
	toast._process(AchievementToast.SLIDE_TIME * 2.0 + AchievementToast.HOLD_TIME)
	check(toast.current != null and toast.current.id == &"ach_tenth_hour", "then the next one")
	toast._process(10.0)
	check(not toast.is_showing() and not toast._panel.visible, "and it is gone")
	for i in 20:
		toast.push(_ach("green_shoot"))
	check(toast.queue.size() <= AchievementToast.MAX_QUEUE, "the queue is bounded")


# --- Main: mid-run checks ------------------------------------------------------------------------------------

func test_a_wave_five_clear_unlocks_green_shoot_in_the_middle_of_the_run() -> void:
	_class_gates()
	var p := _fresh()
	_make_main()
	_bots(2)
	main.start_run()
	check(not Meta.is_class_unlocked(&"hunter"), "the Hunter is locked at the start")
	for i in 4:
		_clear_wave_and_wait()
		main._on_intermission_continue()
	check(not p.has_achievement(&"ach_green_shoot"), "four waves are not enough")
	_clear_wave_and_wait()
	check(p.has_achievement(&"ach_green_shoot"), "wave 5 cleared: Green Shoot, before the run is over")
	check(Meta.is_class_unlocked(&"hunter"), "and the Hunter is open")
	check(main.hud.toast.is_showing() or main.hud.toast.pending_ids().has(&"ach_green_shoot"), "the HUD toast pops")
	check_eq(p.seeds, 25, "the achievement's Seeds are in the wallet")
	check(&"ach_green_shoot" in main.run_achievements, "the run keeps its list")
	main.end_run(false)
	var listed: Array = main.meta_result.get("achievements", [])
	check(&"ach_green_shoot" in listed, "the end screen lists the mid-run achievement too")
	check_eq(listed.count(&"ach_green_shoot"), 1, "once")
	check(main.game_over.rewards_panel.visible, "so the block shows even though nothing new unlocked at the very end")


func test_a_toast_waits_for_the_hud_after_a_break() -> void:
	_fresh()
	_make_main()
	_bots(1)
	main.start_run()
	main.hud.hide()  # (the market has the screen)
	main._on_achievement_unlocked(&"ach_relic_hunter")
	check_eq(main.hud.toast.pending_ids(), [&"ach_relic_hunter"] as Array[StringName], "queued on the HUD")
	main.hud.toast._process(30.0)
	check(main.hud.toast.is_showing(), "a hidden HUD does not run the toast out")
	main.hud.show()
	main.hud.toast._process(AchievementToast.SLIDE_TIME * 2.0 + AchievementToast.HOLD_TIME + 0.1)
	check(not main.hud.toast.is_showing(), "it plays once the wave starts")
	check_eq(main.run_achievements, [&"ach_relic_hunter"] as Array[StringName], "and the run listed it")


func test_a_dev_profile_checks_nothing() -> void:
	Meta.profile = Profile.dev()
	_make_main()
	_bots(1)
	main.start_run()
	main.waves_completed = 9
	main._check_achievements_live()
	check(Meta.profile.achievements.is_empty(), "the automated runs' profile never unlocks")
	check(not main.hud.toast.is_showing(), "and shows no toast")
	check(main.meta_result.is_empty(), "nor a result")


func test_the_wave_ten_boss_unlocks_the_stormcaller_when_the_director_reports_it() -> void:
	var p := _fresh()
	var opts := LaunchOptions.new()
	opts.start_wave = 10
	_make_main(opts)
	_bots(1)
	main.start_run()
	check(not Meta.is_unlocked(Profile.KIND_LEGENDARY, &"stormcaller"), "the Stormcaller is locked")
	var boss := Boss.create(Db.get_boss(&"lich_commander_morvain"), 10)
	nodes.append(boss)
	main._on_boss_defeated(boss)
	check_eq(RunState.boss_wave_down, 10, "recorded")
	check(p.has_achievement(&"ach_tenth_hour"), "Tenth Hour")
	check(Meta.is_unlocked(Profile.KIND_LEGENDARY, &"stormcaller"), "the Stormcaller joins the loot pool")
	check(not p.has_achievement(&"ach_harvest_home"), "and the run is not won")


func test_a_goblin_kill_and_an_artifact_check_the_run_at_once() -> void:
	var p := _fresh()
	_make_main()
	_bots(1)
	main.start_run()
	RunState.goblins_killed = 3
	RunState.record_special_kill(&"goblin", 0)
	check(p.has_achievement(&"ach_gremlin_roundup"), "the third Coin Gremlin")
	RunState.artifacts_dropped = 1
	var item := ItemInstance.new()
	RunState.artifact_dropped.emit(item, &"boss")
	check(p.has_achievement(&"ach_relic_hunter"), "an Artifact drop")


func test_the_final_boss_is_a_win_before_the_end_screen() -> void:
	var p := _fresh()
	var opts := LaunchOptions.new()
	opts.start_wave = 25
	_make_main(opts)
	_bots(1)
	main.start_run()
	var boss := Boss.create(Db.get_boss(&"vorthalax"), 25)
	nodes.append(boss)
	main._on_boss_defeated(boss)
	check(RunState.final_boss_down(), "wave 25's boss is the final one")
	check(p.has_achievement(&"ach_harvest_home") and p.has_achievement(&"ach_lone_bulb"), "a solo win, right when the boss falls")
	check(p.has_unlock(Profile.KIND_DIFFICULTY, &"pungent", PlayerManager.get_slot(0).class_data.id), "and Pungent opens for the hero's class")


# --- Main: the end screen ----------------------------------------------------------------------------------------

func test_the_end_screen_lists_what_the_run_unlocked() -> void:
	_fresh()
	_make_main()
	_bots(1)
	main.start_run()
	RunState.boss_wave_down = 25
	main.waves_completed = 25
	main.wave = 25
	main.end_run(true)
	var ids: Array = main.meta_result.get("achievements", [])
	check(&"ach_harvest_home" in ids and &"ach_lone_bulb" in ids, "the win and the solo win: %s" % [ids])
	var panel := main.game_over.rewards_panel
	check(panel.visible, "the block shows")
	check(panel.row_texts.size() >= 1 and panel.row_texts.size() <= MetaRewardsPanel.MAX_ROWS + 4, "its lines: %s" % [panel.row_texts])
	check(panel.title_label.text.contains("achievements unlocked"), "the header counts them: %s" % panel.title_label.text)
	check(panel.summary_label.text.contains("Seeds"), "and the Seeds: %s" % panel.summary_label.text)
	check(main.meta_result.get("achievement_seeds", 0) > 0, "the result carries the Seeds")


func test_the_rewards_block_caps_its_lines() -> void:
	var panel := MetaRewardsPanel.create()
	nodes.append(panel)
	tree.root.add_child(panel)
	var ids: Array = []
	for a in Db.achievement_list().slice(0, 6):
		ids.append(a.id)
	panel.fill({"achievements": ids, "achievement_seeds": 100})
	check(panel.visible, "visible")
	check_eq(panel.row_texts.size(), MetaRewardsPanel.MAX_ROWS, "three lines")
	check(panel.title_label.text == "6 achievements unlocked", panel.title_label.text)
	panel.fill({"achievements": [&"ach_green_shoot", &"ach_untouched", &"ach_relic_hunter", &"ach_harvest_home", &"ach_regular"], "achievement_seeds": 325})
	check(panel.row_texts[0].begins_with("Untouched") and panel.row_texts[1].begins_with("Harvest Home") and panel.row_texts[2].begins_with("Relic Hunter"),
			"the biggest achievements are listed first: %s" % [panel.row_texts])
	panel.fill({"achievements": [ids[0]], "achievement_seeds": 25, "point_titles": [&"title_collector"]})
	check_eq(panel.title_label.text, "Achievement unlocked", "one achievement")
	check(panel.row_texts.has("Title: the Collector") and panel.summary_label.text.contains("Title: the Collector"), "a point title rides on the header")
	panel.fill({})
	check(not panel.visible, "an empty result hides the block")
	panel.fill({"achievements": [&"ach_nonexistent"]})
	check(not panel.visible, "an unknown id too")


func test_a_dev_profile_run_shows_no_block() -> void:
	Meta.profile = Profile.dev()
	_make_main()
	_bots(1)
	main.start_run()
	main.end_run(true)
	check(not main.game_over.rewards_panel.visible, "automated runs list nothing")


## The end screen with four heroes, an endless hardcore Tear-Jerker header and the block at its fullest still fits 1080.
func test_the_end_screen_with_the_block_at_its_fullest_fits_the_screen() -> void:
	for i in 4:
		PlayerManager.join(UiFakes.HumanInput.new("pad:%d" % i), Db.get_class_data(CLASSES[i]))
	RunState.start_run(4, 7, RunState.MODE_ENDLESS, true, &"forest_ruin", &"tear_jerker")
	var ids: Array = []
	for a in Db.achievement_list().slice(0, 9):
		ids.append(a.id)
	var screen := GameOverScreen.create()
	nodes.append(screen)
	UiFakes.add_to_root(tree, screen)
	screen.open(false, {}, {"achievements": ids, "achievement_seeds": 400, "point_titles": [&"title_collector"]})
	check(screen.rewards_panel.visible and screen.difficulty_badge.visible and screen.hardcore_badge.visible, "everything is up")
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1920, 1080)
	UiFakes.step(screen, 0.0)
	for page in GameOverScreen.PAGE_NAMES.size():
		screen.set_page(page as GameOverScreen.Page)
		UiFakes.step(screen, 0.0)
		var need := screen.panel.get_combined_minimum_size()
		check(need.y <= 1080.0 - 40.0, "page %d: the panel needs %s px of the 1080" % [page, need.y])
		var rect := screen.panel.get_global_rect()
		check(rect.position.y >= 0.0 and rect.end.y <= 1080.0, "page %d: it fits the canvas (%s)" % [page, rect])


# --- All forty, one table ----------------------------------------------------------------------------------------

## A crafted case per achievement: {report, counters?, profile_setup?}. Every id of the data must have one and must fire.
func _case(id: String) -> Dictionary:
	var gardens: Dictionary = {}
	var bulbs: Dictionary = {}
	var tears: Dictionary = {}
	for e in ENVS:
		gardens["env_wins:" + e] = 1
	for c in CLASSES:
		bulbs["wins:%s:normal" % c] = 1
		tears["wins:%s:tear_jerker" % c] = 1
	var hero_set := _heroes([_hero("mage", {"capstones": 1, "rank5": 1, "sets_active": 2})])
	match id:
		"green_shoot":
			return {"report": _report(false, ["mage"], {"waves_cleared": 5})}
		"salt_of_earth":
			return {"report": _report(false, ["mage"], {"kills": 50}), "counters": {"total:kills": 450}}
		"regular":
			return {"report": _report(false), "counters": {"runs_long": 3}}
		"tenth_hour":
			return {"report": _report(false, ["mage"], {"boss_wave_down": 10})}
		"harvest_home":
			return {"report": _win()}
		"lone_bulb":
			return {"report": _win(["mage"])}
		"full_table":
			return {"report": _win(["warrior", "mage", "paladin", "rogue"])}
		"untouched":
			return {"report": _win(["mage", "rogue"])}
		"swift_harvest":
			return {"report": _win(["mage"], {"run_time": 1800.0})}
		"hardcore_win":
			return {"report": _win(["mage"], {}, {"hardcore": true})}
		"five_gardens":
			return {"report": _report(false), "counters": gardens}
		"seven_bulbs":
			return {"report": _report(false), "counters": bulbs}
		"endless_40":
			return {"report": _report(false, ["mage"], {"wave": 41}, {"endless": true})}
		"first_pungent":
			return {"report": _win(["mage"], {}, {"difficulty": "pungent"})}
		"first_tear":
			return {"report": _win(["mage"], {}, {"difficulty": "tear_jerker"})}
		"tear_all":
			return {"report": _report(false), "counters": tears}
		"gremlin_roundup":
			return {"report": _report(false, ["mage"], {"goblins_killed": 4})}
		"need_legendary":
			return {"report": _report(false, ["mage"], {"need_legendary_wins": 2})}
		"relic_hunter":
			return {"report": _report(false, ["mage"], {"artifacts_dropped": 1})}
		"peak_of_the_tree", "master_chef", "dressed_up":
			return {"report": _report(false, ["mage"], {}, {}, hero_set)}
		"cellar_cleaner":
			return {"report": _report(false, ["mage"], {"dungeons_completed": 3})}
		"second_chance":
			return {"report": _report(false, ["mage"], {"revives": 6})}
		"level_thirty":
			return {"report": _report(false), "setup": func(p: Profile) -> void: p.set_class_progress(&"rogue", 33205, 30)}
		"wardrobe_150":
			return {"report": _report(false), "setup": func(p: Profile) -> void:
				for i in 150:
					p.unlock(Profile.KIND_LOOK, StringName("g.chest.0.0.%d" % i))}
	for c in CLASSES:
		if id == "clear_" + c:
			return {"report": _win([c])}
		if id == "pungent_" + c:
			return {"report": _win([c], {}, {"difficulty": "pungent"})}
	return {}


func test_every_one_of_the_forty_fires_and_pays_its_rewards() -> void:
	var covered := 0
	for a in Db.achievement_list():
		var id := String(a.id).trim_prefix("ach_")
		var c := _case(id)
		check(not c.is_empty(), "%s has a crafted case" % id)
		if c.is_empty():
			continue
		var p := Profile.fresh()
		for key: Variant in c.get("counters", {}):
			p.counters[StringName(str(key))] = int(c["counters"][key])
		if c.has("setup"):
			(c["setup"] as Callable).call(p)
		check(_fires(id, c["report"], p), "%s fires" % id)
		covered += 1
	check_eq(covered, 40, "all forty were exercised")


func test_a_blank_run_fires_none_of_the_forty() -> void:
	var p := Profile.fresh()
	var blank := _report(false, ["warrior"], {"wave": 1})
	check(AchievementEngine.evaluate(p, blank, Db.achievement_list(), 1).is_empty(), "nothing fires on an empty run")
	check(AchievementEngine.evaluate(p, null, Db.achievement_list(), 1).is_empty(), "nor without a report (a check outside a run)")
