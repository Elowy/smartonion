extends TestCase
## M6b MODES: the endless mode (boss / elite waves past 25, the 210 s cap, "Endless begins!"), hardcore (no
## Spirit Healer, the ghost hint, the HARDCORE badge), the lobby's mode select (Y / X, any player, the header,
## Main.configure_run) and the leaderboard on the end screen (Main.end_run records, the "Best: ..." line and
## the Leaderboard page with the new entry highlighted).

const UiFakes := preload("res://tests/ui_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0
const MORVAIN := &"lich_commander_morvain"
const VORTHALAX := &"vorthalax"
# One temp board per test process: worktrees share user://, so parallel runs must not share a file.
var TMP_BOARD := "user://m6b_modes_lb_%d.json" % OS.get_process_id()

var main: Main
var world: Node3D
var nodes: Array[Node] = []
var _writes_before := true
var _path_before := ""


func before_each() -> void:
	UiFakes.reset_players()
	RunState.environment_roller = Callable()
	RunState.start_run(1, 4242)
	tree.paused = false
	_writes_before = Leaderboard.writes_enabled
	_path_before = Leaderboard.path_override
	_remove_board_files()


func after_each() -> void:
	Leaderboard.writes_enabled = _writes_before
	Leaderboard.path_override = _path_before
	_remove_board_files()
	_free_main()
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()
	if world != null:
		EFakes.free_world(tree, world)
		world = null
	tree.paused = false
	UiFakes.reset_players()
	RunState.start_run(1, 1)
	Enemy.invalidate_player_cache()


# --- Helpers ----------------------------------------------------------------------------------

func _remove_board_files() -> void:
	for path in [TMP_BOARD, TMP_BOARD + ".tmp", TMP_BOARD + ".corrupt"]:
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A second Main in the same test: the first one is torn down, its players are gone.
func _free_main() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
		UiFakes.reset_players()
		tree.paused = false
	main = null


func _make_main(opts: LaunchOptions = null) -> Main:
	_free_main()
	main = Main.create(opts if opts != null else LaunchOptions.new())
	tree.root.add_child(main)
	return main


func _run_with_bots(count: int, opts: LaunchOptions = null) -> void:
	_make_main(opts)
	for i in count:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)
	main.start_run()


func _human(key: String, class_id: StringName = &"warrior") -> UiFakes.HumanInput:
	var input := UiFakes.HumanInput.new(key)
	PlayerManager.join(input, Db.get_class_data(class_id))
	return input


func _add(n: Node) -> Node:
	tree.root.add_child(n)
	nodes.append(n)
	return n


func _clear_wave_and_wait() -> void:
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	main._physics_process(Main.WAVE_END_DELAY + 0.01)


func _director() -> WaveDirector:
	world = EFakes.make_world(tree)
	var d := WaveDirector.create(EFakes.arena_of(world))
	world.add_child(d)
	return d


func _endless_run(p_hardcore: bool = false) -> void:
	RunState.start_run(2, 4242, RunState.MODE_ENDLESS, p_hardcore)


## A leaderboard file with [param entries] of the (endless, standard, 2 players) category.
func _write_board(entries: Array, key: String = "endless/standard/2") -> void:
	var file := FileAccess.open(TMP_BOARD, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": Leaderboard.FORMAT_VERSION, "categories": {key: entries}}))
	file.close()


func _entry(wave: int, time: float, victory: bool = false, date: String = "2026-10-01 12:00:00") -> Dictionary:
	return {"wave": wave, "time": time, "classes": ["warrior", "mage"], "date": date, "victory": victory}


# --- Endless: boss / elite waves, the wave length -------------------------------------------------

func test_every_fifth_wave_from_30_is_a_boss_wave() -> void:
	for w in [10, 25, 30, 35, 40, 45, 50, 100]:
		check(RunState.is_boss_wave(w), "wave %d is a boss wave" % w)
	for w in [1, 9, 11, 20, 24, 26, 29, 31, 33, 34, 36, 39, 41, 99]:
		check(not RunState.is_boss_wave(w), "wave %d is not" % w)
	for w in RunState.BOSS_WAVES:
		check(not RunState.is_endless_boss_wave(w), "%d belongs to the normal run" % w)
	check(RunState.is_endless_boss_wave(30) and RunState.is_endless_boss_wave(35), "30 and 35 are the endless ones")


func test_the_elite_wave_rule_comes_back_every_ten_waves_from_33() -> void:
	for w in [20, 33, 43, 53, 63, 103]:
		check(RunState.is_elite_wave(w), "wave %d is an elite wave" % w)
	for w in [1, 19, 21, 23, 30, 32, 34, 35, 40, 42, 44, 50, 52, 99]:
		check(not RunState.is_elite_wave(w), "wave %d is not" % w)
	check(not RunState.is_endless_elite_wave(20), "wave 20 belongs to the normal run")


func test_endless_waves_stay_210_seconds() -> void:
	check_eq(RunState.wave_duration(24), 200.0, "wave 24 unchanged")
	check_eq(RunState.wave_duration(25), 210.0, "wave 25 unchanged")
	for w in [26, 27, 31, 33, 60, 150]:
		check_eq(RunState.wave_duration(w), 210.0, "wave %d is capped at 210 s" % w)
	check_eq(RunState.MAX_WAVE_DURATION, 210.0, "the constant")
	check_eq(RunState.wave_duration(10), 60.0, "the first half unchanged")
	check_eq(RunState.wave_duration(11), 70.0, "wave 11 unchanged")


func test_endless_bosses_alternate_morvain_and_vorthalax() -> void:
	var morvain := Db.get_boss(MORVAIN)
	var vorthalax := Db.get_boss(VORTHALAX)
	check(BossData.for_wave(10) == morvain and BossData.for_wave(25) == vorthalax, "the normal run's two bosses stay")
	for w in [30, 40, 50, 60, 100]:
		check(BossData.for_wave(w) == morvain, "wave %d: Morvain" % w)
	for w in [35, 45, 55, 105]:
		check(BossData.for_wave(w) == vorthalax, "wave %d: Vor'thalax" % w)
	for w in [26, 29, 31, 33, 34, 36, 39]:
		check(BossData.for_wave(w) == null, "no boss on wave %d" % w)
	check(BossData.endless_boss(10) == null and BossData.endless_boss(25) == null, "endless_boss is for 30+ only")
	check_eq(BossData.ENDLESS_ROTATION.size(), 2, "two bosses in turn")
	for id in BossData.ENDLESS_ROTATION:
		check(Db.get_boss(id) != null, "%s exists" % id)


func test_an_endless_boss_has_its_waves_normal_scaling() -> void:
	var morvain := Db.get_boss(MORVAIN)
	var vorthalax := Db.get_boss(VORTHALAX)
	RunState.start_run(2, 1, RunState.MODE_ENDLESS)
	var at30 := Boss.create(BossData.for_wave(30), 30)
	var at35 := Boss.create(BossData.for_wave(35), 35)
	nodes.append(at30)
	nodes.append(at35)
	check_near(at30.max_hp, morvain.max_hp_for(30, 2), 0.01, "Morvain's HP at wave 30")
	check_near(at30.max_hp, morvain.max_hp * morvain.hp_mult_at_wave(30) * 1.75, 0.01, "= base x the wave 30 growth x the boss co-op factor")
	check_near(at35.max_hp, vorthalax.max_hp_for(35, 2), 0.01, "Vor'thalax's HP at wave 35")
	check(at30.max_hp > morvain.max_hp_for(10, 2) * 10.0, "far above the wave 10 Morvain")
	check_near(at30.contact_damage, morvain.contact_damage_at_wave(30) * RunState.coop_damage_mult(), 0.001, "contact damage at the wave")


func test_the_director_runs_endless_boss_and_elite_waves() -> void:
	_endless_run()
	var d := _director()
	d.start_wave(30)
	check(d.boss_data == Db.get_boss(MORVAIN), "wave 30: Morvain")
	check_eq(d.time_left, WaveDirector.BOSS_WAVE_TIME, "no clock on a boss wave")
	check(not d.elite_wave, "a boss wave is no elite wave")
	d.start_wave(35)
	check(d.boss_data == Db.get_boss(VORTHALAX), "wave 35: Vor'thalax")
	d.start_wave(33)
	check(d.boss_data == null, "wave 33: no boss")
	check(d.elite_wave, "wave 33: the elite rule")
	d.start_wave(34)
	check(not d.elite_wave and d.boss_data == null, "wave 34: a normal wave")
	check_eq(d.duration, 210.0, "of the capped length")
	d.start_wave(27)
	check_eq(d.duration, 210.0, "wave 27: 210 s")
	check_eq(d.time_left, 210.0, "and the clock starts there")


func test_the_market_header_names_endless_boss_and_elite_waves() -> void:
	_endless_run()
	var boss := Intermission.next_wave_text(30)
	check_eq(boss, "Next up: Wave 30 – Boss wave! (ends when the boss falls)", "a boss wave has no timer: %s" % boss)
	var elite := Intermission.next_wave_text(33)
	check(elite.begins_with("Next up: Wave 33  ·  210 seconds") and "Elite wave!" in elite, "the elite wave: %s" % elite)
	check_eq(Intermission.next_wave_text(31), "Next up: Wave 31  ·  210 seconds", "a normal endless wave")


func test_the_hud_shows_the_endless_boss_frame_and_the_elite_tag() -> void:
	_endless_run()
	var hud := _add(Hud.create()) as Hud
	RunState.set_wave(30)
	check_eq(hud.wave_tag_label.text, "BOSS WAVE", "the boss tag on 30")
	check(hud.is_boss_frame_visible(), "the boss frame replaces the timer")
	check_eq(hud.boss_name_label.text, "Lich Commander Morvain", "Morvain's frame on 30")
	RunState.set_wave(35)
	check_eq(hud.boss_name_label.text, Db.get_boss(VORTHALAX).display_name, "Vor'thalax's frame on 35")
	RunState.set_wave(33)
	check_eq(hud.wave_tag_label.text, "ELITE WAVE", "the elite tag on 33")
	check(not hud.is_boss_frame_visible(), "no boss frame on 33")
	check_eq(hud.wave_label.text, "Wave 33", "no total in the endless mode")


func test_no_mid_wave_event_or_goblin_on_endless_boss_and_elite_waves() -> void:
	_endless_run()
	for w in [30, 33, 35, 43]:
		check(not EventSpawner.is_eligible_wave(w), "no event on wave %d" % w)
	for w in [31, 32, 34, 36]:
		check(EventSpawner.is_eligible_wave(w), "events may come on wave %d" % w)


func test_endless_begins_after_the_wave_25_boss_instead_of_the_victory() -> void:
	var endless := LaunchOptions.new()
	endless.mode = RunState.MODE_ENDLESS
	endless.start_wave = 25
	_run_with_bots(1, endless)
	check_eq(main._wave_cleared_text(25), "Endless begins!", "the endless text for wave 25")
	check_eq(Main.ENDLESS_BEGINS_TEXT, "Endless begins!", "the constant")
	_clear_wave_and_wait()
	check_eq(main.state, Main.State.INTERMISSION, "the run goes on to the market")
	check(not main.victory and RunState.active, "no victory")
	check_eq(main.hud.banner_label.text, "Endless begins!", "the banner at the wave 25 clear")
	main._on_intermission_continue()
	check_eq(main.wave, 26, "wave 26 follows")
	check_eq(main._wave_cleared_text(26) == "Endless begins!", false, "only wave 25 says it")
	check_eq(main.wave_director.duration, 210.0, "wave 26 lasts 210 s")


func test_the_normal_mode_still_ends_with_the_victory_on_wave_25() -> void:
	var opts := LaunchOptions.new()
	opts.start_wave = 25
	_run_with_bots(1, opts)
	check_eq(main._wave_cleared_text(25), "Victory!", "the victory text")
	_clear_wave_and_wait()
	check_eq(main.state, Main.State.GAME_OVER, "the run is over")
	check(main.victory, "victory")


func test_begins_endless_is_wave_25_of_the_endless_mode_only() -> void:
	RunState.start_run(1, 1)
	check(not RunState.begins_endless(25), "not in the normal mode")
	RunState.start_run(1, 1, RunState.MODE_ENDLESS)
	check(RunState.begins_endless(25), "wave 25 of the endless mode")
	check(not RunState.begins_endless(24) and not RunState.begins_endless(26) and not RunState.begins_endless(30), "no other wave")


# --- Hardcore ------------------------------------------------------------------------------------

func test_a_hardcore_arena_has_no_spirit_healer() -> void:
	var opts := LaunchOptions.new()
	opts.hardcore = true
	_run_with_bots(2, opts)
	check(RunState.hardcore, "hardcore run")
	check(main.arena.spirit_healer == null, "no Spirit Healer in the arena")


func test_a_normal_arena_keeps_its_spirit_healer() -> void:
	_run_with_bots(2)
	check(not RunState.hardcore, "not hardcore")
	check(main.arena.spirit_healer != null, "the Spirit Healer stands in the arena")


func test_hardcore_works_in_the_endless_mode_too() -> void:
	var opts := LaunchOptions.new()
	opts.hardcore = true
	opts.mode = RunState.MODE_ENDLESS
	_run_with_bots(2, opts)
	check(RunState.hardcore and RunState.is_endless(), "both flags")
	check(main.arena.spirit_healer == null, "no healer")


func test_the_ghost_hint_names_the_teammate_in_hardcore() -> void:
	var opts := LaunchOptions.new()
	opts.hardcore = true
	_run_with_bots(2, opts)
	var hero := main.players[0]
	hero.take_damage(1.0e6, CombatMath.KIND_MELEE, null)
	check(hero.downed, "downed")
	var frame := UnitFrame.create(0)
	_add(frame)
	frame.bind(hero)
	frame._process(0.016)
	check_eq(frame.hint_label.text, "Only a teammate can revive you", "the hardcore hint")
	check_eq(UnitFrame.HARDCORE_HINT, "Only a teammate can revive you", "the constant")
	hero.res_sickness_left = 9.5
	frame._process(0.016)
	check_eq(frame.hint_label.text, UnitFrame.SICKNESS_HINT % 10, "a sickness countdown would still show first")
	hero.res_sickness_left = 0.0
	RunState.hardcore = false  # the same ghost in a normal run: the Spirit Healer's hint
	frame._process(0.016)
	check("Spirit Healer" in frame.hint_label.text, "normal run: %s" % frame.hint_label.text)


func test_a_downed_hero_comes_back_at_the_next_wave_start_in_hardcore() -> void:
	var opts := LaunchOptions.new()
	opts.hardcore = true
	_run_with_bots(2, opts)
	var hero := main.players[0]
	hero.take_damage(1.0e6, CombatMath.KIND_MELEE, null)
	check(hero.downed, "downed")
	main.start_wave(2)
	check(hero.is_alive(), "back on its feet at the wave start")
	check_near(hero.hp / hero.max_hp(), Player.WAVE_START_REVIVE_HP_RATIO, 0.06, "with 50% HP (rounded to whole HP)")


func test_the_hud_shows_the_hardcore_badge_only_in_a_hardcore_run() -> void:
	RunState.start_run(2, 1, RunState.MODE_NORMAL, true)
	var hard := _add(Hud.create()) as Hud
	check(hard.hardcore_badge.visible, "badge in a hardcore run")
	check_eq(hard.hardcore_badge.label.text, "HARDCORE", "its text")
	RunState.start_run(2, 1)
	var normal := _add(Hud.create()) as Hud
	check(not normal.hardcore_badge.visible, "no badge in a normal run")
	RunState.start_run(2, 1, RunState.MODE_ENDLESS)
	var endless := _add(Hud.create()) as Hud
	check(not endless.hardcore_badge.visible, "none in an endless run either")


# --- Lobby: the mode select ----------------------------------------------------------------------

func _lobby() -> Lobby:
	var l := Lobby.create()
	_add(l)
	return l


func test_y_cycles_the_mode_and_x_toggles_hardcore() -> void:
	var a := _human("pad:a")
	var lobby := _lobby()
	var changes: Array[String] = []
	lobby.mode_changed.connect(func(m: StringName, h: bool) -> void: changes.append("%s/%s" % [m, h]))
	check_eq(lobby.mode_text(), "Mode: Normal", "starts as Normal")
	UiFakes.tap(lobby, a, PlayerInput.Pad.Y)
	check_eq(lobby.run_mode, RunState.MODE_ENDLESS, "Y -> Endless")
	check_eq(lobby.mode_label.text, "Mode: Endless", "the header")
	UiFakes.tap(lobby, a, PlayerInput.Pad.X)
	check(lobby.hardcore, "X -> Hardcore on")
	check_eq(lobby.mode_label.text, "Mode: Endless · Hardcore", "the header with both")
	check(lobby.hardcore_badge.visible, "the HARDCORE badge shows")
	UiFakes.tap(lobby, a, PlayerInput.Pad.Y)
	check_eq(lobby.run_mode, RunState.MODE_NORMAL, "Y again -> back to Normal")
	check(lobby.hardcore, "the two switches are independent")
	UiFakes.tap(lobby, a, PlayerInput.Pad.X)
	check(not lobby.hardcore and not lobby.hardcore_badge.visible, "X again -> Hardcore off, no badge")
	check_eq(changes, ["endless/false", "endless/true", "normal/true", "normal/false"] as Array[String], "every change was announced")


func test_any_joined_player_can_change_the_mode() -> void:
	var a := _human("pad:a")
	var b := _human("pad:b", &"mage")
	var c := _human("pad:c", &"rogue")
	var lobby := _lobby()
	UiFakes.tap(lobby, c, PlayerInput.Pad.Y)
	check_eq(lobby.run_mode, RunState.MODE_ENDLESS, "the third player changes the mode")
	UiFakes.tap(lobby, b, PlayerInput.Pad.X)
	check(lobby.hardcore, "the second player toggles Hardcore")
	UiFakes.tap(lobby, a, PlayerInput.Pad.Y)
	check_eq(lobby.run_mode, RunState.MODE_NORMAL, "the first one cycles on")


func test_the_mode_key_prompts_light_up_with_the_first_player() -> void:
	var lobby := _lobby()
	UiFakes.step(lobby)
	check_near(lobby._mode_prompts.modulate.a, Lobby.MODE_PROMPTS_IDLE_ALPHA, 0.001, "dimmed while nobody has joined")
	check(lobby._mode_prompts.visible, "but there, so the header never changes height")
	_human("pad:a")
	UiFakes.step(lobby)
	check_near(lobby._mode_prompts.modulate.a, 1.0, 0.001, "lit once somebody has joined")
	check_eq(lobby.mode_label.text, "Mode: Normal", "the header is there from the start")


func test_a_mode_change_during_the_countdown_cancels_it() -> void:
	_human("pad:a")
	var b := _human("pad:b", &"mage")
	var lobby := _lobby()
	PlayerManager.set_all_ready(true)
	UiFakes.step(lobby)
	check(lobby.is_counting_down(), "everybody is ready: counting down")
	UiFakes.tap(lobby, b, PlayerInput.Pad.Y)
	check_eq(lobby.run_mode, RunState.MODE_ENDLESS, "the mode changed")
	check(not PlayerManager.get_slot(1).ready, "the player who changed it is not ready any more")
	check(PlayerManager.get_slot(0).ready, "the others keep their ready")
	check(not lobby.is_counting_down(), "the countdown stopped")
	UiFakes.step(lobby)
	check(not lobby.is_counting_down(), "and stays stopped until the changer readies again")


func test_a_mode_change_before_the_countdown_leaves_ready_alone() -> void:
	var a := _human("pad:a")
	_human("pad:b", &"mage")
	var lobby := _lobby()
	PlayerManager.get_slot(0).ready = true
	UiFakes.step(lobby)
	check(not lobby.is_counting_down(), "only one of two is ready")
	UiFakes.tap(lobby, a, PlayerInput.Pad.X)
	check(PlayerManager.get_slot(0).ready, "a ready player toggling Hardcore stays ready")


func test_set_run_mode_shows_a_stored_choice_without_announcing_it() -> void:
	var lobby := _lobby()
	var changes: Array[int] = [0]
	lobby.mode_changed.connect(func(_m: StringName, _h: bool) -> void: changes[0] += 1)
	lobby.set_run_mode(RunState.MODE_ENDLESS, true)
	check_eq(lobby.mode_text(), "Mode: Endless · Hardcore", "the header")
	check(lobby.hardcore_badge.visible, "the badge")
	check_eq(changes[0], 0, "nobody was told")
	lobby.set_run_mode(&"bogus", false)
	check_eq(lobby.run_mode, RunState.MODE_NORMAL, "an unknown mode shows as Normal")
	check(not lobby.hardcore_badge.visible, "no badge")


func test_the_lobby_stores_the_choice_in_main_and_the_run_uses_it() -> void:
	_make_main()
	var a := _human("pad:a")
	main.go_to_lobby()
	var lobby := main.lobby
	check_eq(lobby.mode_label.text, "Mode: Normal", "the lobby opens on the launch options' mode")
	UiFakes.tap(lobby, a, PlayerInput.Pad.Y)
	UiFakes.tap(lobby, a, PlayerInput.Pad.X)
	check_eq(main.options.mode, RunState.MODE_ENDLESS, "Main.configure_run stored the mode")
	check(main.options.hardcore, "and the hardcore flag")
	main.start_run()
	check_eq(RunState.mode, RunState.MODE_ENDLESS, "the run is endless")
	check(RunState.hardcore, "and hardcore")
	check(main.arena.spirit_healer == null, "without a Spirit Healer")
	main.go_to_lobby()
	check_eq(main.lobby.mode_label.text, "Mode: Endless · Hardcore", "the next lobby keeps the choice")


func test_the_lobby_opens_on_the_mode_flags_of_the_command_line() -> void:
	var opts := LaunchOptions.parse(PackedStringArray(["--mode=endless", "--hardcore"]))
	_make_main(opts)
	main.go_to_lobby()
	check_eq(main.lobby.mode_label.text, "Mode: Endless · Hardcore", "--mode=endless --hardcore")
	check(main.lobby.hardcore_badge.visible, "the badge")


# --- The leaderboard texts and the model ---------------------------------------------------------

func test_the_result_texts() -> void:
	var endless := _entry(31, 1122.0)
	check_eq(Leaderboard.result_text(endless, RunState.MODE_ENDLESS), "Wave 31", "endless: the wave")
	check_eq(Leaderboard.summary_text(endless, RunState.MODE_ENDLESS), "Wave 31 · 18:42", "with the time")
	var won := _entry(25, 1500.0, true)
	check_eq(Leaderboard.result_text(won, RunState.MODE_NORMAL), "Victory", "normal victory")
	check_eq(Leaderboard.summary_text(won, RunState.MODE_NORMAL), "Victory · 25:00", "with the time")
	var lost := _entry(18, 560.0, false)
	check_eq(Leaderboard.result_text(lost, RunState.MODE_NORMAL), "Fell on wave 18", "normal defeat")
	check_eq(Leaderboard.party_text(won), "Warrior, Mage", "class names")
	check_eq(Leaderboard.party_text({"classes": ["warrior", "ghost_knight"]}), "Warrior, Ghost Knight", "an unknown id is capitalised")
	check_eq(Leaderboard.date_text(won), "2026-10-01", "the date part")
	check_eq(Leaderboard.party_size_text(1), "1 player", "one")
	check_eq(Leaderboard.party_size_text(4), "4 players", "four")
	check_eq(Leaderboard.category_text(RunState.MODE_ENDLESS, true, 3), "Endless · Hardcore · 3 players", "the category title")
	check_eq(Leaderboard.category_text(RunState.MODE_NORMAL, false, 1), "Normal · 1 player", "a plain category")


func test_the_best_line() -> void:
	var best := _entry(31, 1122.0)
	check_eq(Leaderboard.best_line(best, RunState.MODE_ENDLESS), "Best: Wave 31 · 18:42", "no rank")
	check_eq(Leaderboard.best_line(best, RunState.MODE_ENDLESS, 0), "Best: Wave 31 · 18:42  –  New best!", "first place")
	check_eq(Leaderboard.best_line(best, RunState.MODE_ENDLESS, 2), "Best: Wave 31 · 18:42  –  This run: #3", "third place")
	check_eq(Leaderboard.best_line({}, RunState.MODE_ENDLESS), "Best: –", "an empty board")


func test_the_screen_model_of_a_board() -> void:
	_write_board([_entry(31, 1122.0), _entry(27, 900.0), _entry(20, 700.0)])
	var board := Leaderboard.create(TMP_BOARD)
	board.load_file()
	var mine := _entry(27, 900.0)
	var model := Leaderboard.screen_model(board, mine, RunState.MODE_ENDLESS, false, 2, 1)
	check_eq(model["key"], "endless/standard/2", "the category")
	check_eq(model["category_text"], "Endless · 2 players", "its title")
	check_eq((model["entries"] as Array).size(), 3, "the entries")
	check_eq(model["rank"], 1, "the run's place")
	check_eq(model["line"], "Best: Wave 31 · 18:42  –  This run: #2", "the Best line")
	check_eq(model["error"], "", "no error")
	var outside := Leaderboard.screen_model(board, mine, RunState.MODE_ENDLESS, false, 2, 7)
	check_eq(outside["rank"], -1, "a rank beyond the entries is not on the board")
	var other := Leaderboard.screen_model(board, mine, RunState.MODE_NORMAL, true, 4, -1)
	check((other["entries"] as Array).is_empty() and other["best"] == {}, "another category is empty")
	check_eq(other["line"], "Best: –", "its Best line")


func test_the_screen_model_reports_an_unusable_file() -> void:
	var file := FileAccess.open(TMP_BOARD, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": Leaderboard.FORMAT_VERSION + 1, "categories": {}}))
	file.close()
	var board := Leaderboard.create(TMP_BOARD)
	board.load_file()
	var model := Leaderboard.screen_model(board, _entry(5, 100.0), RunState.MODE_NORMAL, false, 1, -1)
	check_eq(model["error"], "newer version", "the error")
	check("unavailable" in String(model["line"]), "the line says so: %s" % model["line"])


func test_equal_entries_keep_the_files_order_when_loaded() -> void:
	_write_board([_entry(20, 600.0, false, "2026-10-01 10:00:00"), _entry(20, 600.0, false, "2026-10-02 10:00:00"),
			_entry(20, 600.0, false, "2026-10-03 10:00:00"), _entry(25, 600.0, false, "2026-10-04 10:00:00")])
	var board := Leaderboard.create(TMP_BOARD)
	board.load_file()
	var dates: Array[String] = []
	for e in board.entries_for(RunState.MODE_ENDLESS, false, 2):
		dates.append(Leaderboard.date_text(e))
	check_eq(dates, ["2026-10-04", "2026-10-01", "2026-10-02", "2026-10-03"] as Array[String], "the best first, equal ones as stored")


func test_a_later_wave_and_a_longer_time_rank_higher_when_the_party_fell() -> void:
	# Endless: the later wave first, then the LONGER time held out on it.
	check(Leaderboard.better(_entry(34, 100.0), _entry(33, 2000.0), RunState.MODE_ENDLESS), "a later wave beats a longer time")
	check(Leaderboard.better(_entry(33, 2150.0), _entry(33, 2000.0), RunState.MODE_ENDLESS), "the same wave: the longer time")
	check(not Leaderboard.better(_entry(33, 2000.0), _entry(33, 2150.0), RunState.MODE_ENDLESS), "the same wave: not the shorter")
	# Normal defeats: the same rule.
	check(Leaderboard.better(_entry(20, 1100.0), _entry(20, 1000.0), RunState.MODE_NORMAL), "a defeat: the longer time on the same wave")
	check(not Leaderboard.better(_entry(20, 1000.0), _entry(20, 1100.0), RunState.MODE_NORMAL), "a defeat: not the shorter")
	check(Leaderboard.better(_entry(21, 100.0), _entry(20, 1100.0), RunState.MODE_NORMAL), "a defeat: the later wave first")
	# Normal victories: the SHORTER time.
	check(Leaderboard.better(_entry(25, 1000.0, true), _entry(25, 1100.0, true), RunState.MODE_NORMAL), "a victory: the shorter time")
	check(not Leaderboard.better(_entry(25, 1100.0, true), _entry(25, 1000.0, true), RunState.MODE_NORMAL), "a victory: not the longer")
	check(Leaderboard.better(_entry(25, 1500.0, true), _entry(24, 3000.0), RunState.MODE_NORMAL), "a victory beats any defeat")
	check(not Leaderboard.better(_entry(20, 1000.0), _entry(20, 1000.0), RunState.MODE_NORMAL), "a tie is not better")


func test_the_board_puts_the_longer_defeat_above_the_faster_one() -> void:
	var board := Leaderboard.create(TMP_BOARD)
	check_eq(board.add_entry(_entry(33, 2000.0), RunState.MODE_ENDLESS, false, 2), 0, "the first entry")
	check_eq(board.add_entry(_entry(33, 2150.0), RunState.MODE_ENDLESS, false, 2), 0, "a longer run on the same wave takes the top")
	check_eq(board.add_entry(_entry(33, 1000.0), RunState.MODE_ENDLESS, false, 2), 2, "a faster fall goes last")
	var times: Array[float] = []
	for e in board.entries_for(RunState.MODE_ENDLESS, false, 2):
		times.append(float(e["time"]))
	check_eq(times, [2150.0, 2000.0, 1000.0] as Array[float], "the order by time")


# --- Main.end_run records the run ----------------------------------------------------------------

func _recording_main(opts: LaunchOptions = null) -> void:
	Leaderboard.writes_enabled = true
	var o := opts if opts != null else LaunchOptions.new()
	o.leaderboard_path = TMP_BOARD
	_run_with_bots(2, o)


func _board() -> Leaderboard:
	var b := Leaderboard.create(TMP_BOARD)
	b.load_file()
	return b


func test_an_endless_defeat_is_recorded_and_shown() -> void:
	var opts := LaunchOptions.new()
	opts.mode = RunState.MODE_ENDLESS
	opts.start_wave = 27
	_recording_main(opts)
	RunState.tick_run_time(321.0)
	main.end_run(false)
	var entries := _board().entries_for(RunState.MODE_ENDLESS, false, 2)
	check_eq(entries.size(), 1, "one entry in the endless / standard / 2 category")
	check_eq(int(entries[0]["wave"]), 27, "the wave that ended the run")
	check_near(float(entries[0]["time"]), 321.0, 0.11, "the wave play time")
	check(not bool(entries[0]["victory"]), "a defeat")
	check_eq(entries[0]["classes"], ["warrior", "mage"] as Array[String], "the classes in slot order")
	check_eq(main.game_over.board["rank"], 0, "the end screen knows the place")
	check_eq(main.game_over.best_label.text, "Best: Wave 27 · 5:21  –  New best!", "the Best line")
	check(main.game_over.best_label.visible, "shown")


func test_a_normal_victory_is_recorded_as_one() -> void:
	var opts := LaunchOptions.new()
	opts.start_wave = 25
	_recording_main(opts)
	RunState.tick_run_time(1500.0)
	_clear_wave_and_wait()
	check_eq(main.state, Main.State.GAME_OVER, "victory")
	var entries := _board().entries_for(RunState.MODE_NORMAL, false, 2)
	check_eq(entries.size(), 1, "a normal / standard / 2 entry")
	check(bool(entries[0]["victory"]), "marked as a victory")
	check_eq(int(entries[0]["wave"]), 25, "wave 25")
	check_eq(main.game_over.best_label.text, "Best: Victory · 25:00  –  New best!", "the Best line")


func test_hardcore_and_party_size_pick_the_category() -> void:
	var opts := LaunchOptions.new()
	opts.mode = RunState.MODE_ENDLESS
	opts.hardcore = true
	_recording_main(opts)
	main.end_run(false)
	var board := _board()
	check_eq(board.entries_for(RunState.MODE_ENDLESS, true, 2).size(), 1, "endless / hardcore / 2")
	check(board.entries_for(RunState.MODE_ENDLESS, false, 2).is_empty(), "not the standard board")
	check(board.entries_for(RunState.MODE_ENDLESS, true, 3).is_empty(), "not another party size")
	check(board.entries_for(RunState.MODE_NORMAL, true, 2).is_empty(), "not another mode")


func test_a_second_run_ranks_against_the_first() -> void:
	var opts := LaunchOptions.new()
	opts.mode = RunState.MODE_ENDLESS
	opts.start_wave = 30
	_recording_main(opts)
	main.end_run(false)
	var better := LaunchOptions.new()
	better.mode = RunState.MODE_ENDLESS
	better.start_wave = 40
	_recording_main(better)
	main.end_run(false)
	check_eq(main.game_over.board["rank"], 0, "the wave 40 run is first")
	check_eq((main.game_over.board["entries"] as Array).size(), 2, "two entries")
	var worse := LaunchOptions.new()
	worse.mode = RunState.MODE_ENDLESS
	worse.start_wave = 5
	_recording_main(worse)
	main.end_run(false)
	check_eq(main.game_over.board["rank"], 2, "the wave 5 run is third")
	check_eq(main.game_over.best_label.text, "Best: Wave 40 · 0:00  –  This run: #3", "the line names the best and the place")
	check_eq(main.game_over.leaderboard_page.highlighted, 2, "the third row is highlighted")


func test_the_leaderboard_stays_untouched_when_the_file_is_off_limits() -> void:
	Leaderboard.writes_enabled = false
	var opts := LaunchOptions.new()
	opts.leaderboard_path = TMP_BOARD
	_run_with_bots(2, opts)
	main.end_run(false)
	check(not FileAccess.file_exists(TMP_BOARD), "nothing written")
	check(main.game_over.board.is_empty(), "no board model (the unit tests)")
	check(not main.game_over.best_label.visible, "no Best line")


func test_smoke_runs_do_not_even_read_the_players_file() -> void:
	Leaderboard.writes_enabled = true
	Leaderboard.path_override = TMP_BOARD
	_write_board([_entry(31, 1122.0)])
	_run_with_bots(2)
	main.options.smoke = true  # (set after the start: a smoke Main would boot into its own run)
	check(not main.writes_leaderboard(), "a smoke run does not write")
	main.end_run(false)
	check(main.game_over.board.is_empty(), "no board model: the file was not read")
	check_eq((_board().entries_for(RunState.MODE_ENDLESS, false, 2)).size(), 1, "and the file is as it was")


func test_demo_and_view_runs_show_the_board_but_do_not_write_it() -> void:
	Leaderboard.writes_enabled = true
	Leaderboard.path_override = TMP_BOARD
	for kind in ["demo", "view", "shot"]:
		_run_with_bots(2)
		match kind:
			"demo":
				main.options.demo = true
			"view":
				main.options.view = "game_over"
			"shot":
				main.options.screenshot_path = "/tmp/x.png"
		check(not main.writes_leaderboard(), "%s: no write" % kind)
		main.end_run(false)
		check(not FileAccess.file_exists(TMP_BOARD), "%s: no file" % kind)
		var model := main.game_over.board
		check(model["rank"] == -1 and (model["entries"] as Array).is_empty(), "%s: the screen shows the (empty) board, no place" % kind)
		check_eq(main.game_over.best_label.text, "Best: –", "%s: an empty board" % kind)


func test_leaderboard_flag_makes_a_smoke_run_write_its_own_file() -> void:
	var parsed := LaunchOptions.parse(PackedStringArray(["--leaderboard=" + TMP_BOARD]))
	check_eq(parsed.leaderboard_path, TMP_BOARD, "parsed")
	check(parsed.unknown.is_empty(), "known flag")
	check(not LaunchOptions.parse(PackedStringArray(["--leaderboard="])).unknown.is_empty(), "an empty path is unknown")
	_make_main(parsed)
	check_eq(Leaderboard.path_override, TMP_BOARD, "Main points the leaderboard at it")
	main.options.smoke = true  # (set after the start: a smoke Main would boot into its own run)
	check(main.writes_leaderboard(), "even a smoke run writes its own file")


func test_quitting_to_the_menu_does_not_record_the_run() -> void:
	_recording_main()
	main.quit_to_menu()
	check(not FileAccess.file_exists(TMP_BOARD), "an abandoned run is not a result")


# --- The end screen: the Leaderboard page, the mode row, the badge -------------------------------

func _screen(p_board: Dictionary = {}) -> GameOverScreen:
	var screen := GameOverScreen.create()
	_add(screen)
	screen.open(false, p_board)
	return screen


func _model(entries: Array, rank: int, p_mode: StringName = RunState.MODE_ENDLESS) -> Dictionary:
	_write_board(entries)
	var board := Leaderboard.create(TMP_BOARD)
	board.load_file()
	return Leaderboard.screen_model(board, entries[maxi(rank, 0)], p_mode, false, 2, rank)


func test_the_leaderboard_page_lists_ten_places_and_highlights_this_run() -> void:
	_human("pad:a")
	_human("pad:b", &"mage")
	var screen := _screen(_model([_entry(31, 1122.0), _entry(27, 900.0), _entry(20, 700.0)], 1))
	var page := screen.leaderboard_page
	check_eq(page.rows.size(), 10, "ten places, filled or not")
	check_eq(page.category_label.text, "Endless · 2 players", "the category title")
	check_eq(page.cell_text(0, 0), "#1", "rank 1")
	check_eq(page.cell_text(0, 1), "Wave 31", "its result")
	check_eq(page.cell_text(0, 2), "18:42", "its time")
	check_eq(page.cell_text(0, 3), "Warrior, Mage", "its party")
	check_eq(page.cell_text(0, 4), "2026-10-01", "its date")
	check_eq(page.cell_text(0, 5), "", "not this run")
	check_eq(page.highlighted, 1, "the second place is this run")
	check_eq(page.cell_text(1, 5), "This run", "marked")
	check_eq(page.cell_text(3, 1), "–", "an empty place is dashed")
	check_eq(page.cell_text(9, 0), "#10", "down to the tenth")
	var plain := page.rows[0].get_theme_stylebox(&"panel") as StyleBoxFlat
	var lit := page.rows[1].get_theme_stylebox(&"panel") as StyleBoxFlat
	check(plain.bg_color.a == 0.0 and lit.bg_color.a > 0.0, "only the run's row has a fill")
	check_eq(page.note_label.text, "New entry: place 2 of 10.", "the note")


func test_the_summary_shows_the_best_line_and_pages_reach_the_board() -> void:
	_human("pad:a")
	var screen := _screen(_model([_entry(31, 1122.0)], 0))
	check_eq(screen.best_label.text, "Best: Wave 31 · 18:42  –  New best!", "the Best line on the Summary")
	check(screen.best_label.get_parent() == screen.summary_page, "under the Summary's table")
	screen.set_page(GameOverScreen.Page.LEADERBOARD)
	check(screen.leaderboard_page.visible and not screen.summary_page.visible and not screen.meter_page.visible, "only the board shows")
	check_eq(GameOverScreen.page_from_name("leaderboard"), GameOverScreen.Page.LEADERBOARD, "--end-page=leaderboard")
	check_eq(GameOverScreen.PAGE_NAMES[GameOverScreen.Page.LEADERBOARD], "Leaderboard", "the tab's name")
	check_eq(screen.tab_labels.size(), 3, "three tabs")


func test_the_leaderboard_page_without_a_board_says_so() -> void:
	var screen := _screen()
	check_eq(screen.leaderboard_page.rows.size(), 10, "the places are there anyway")
	check_eq(screen.leaderboard_page.highlighted, -1, "none highlighted")
	check("not recorded" in screen.leaderboard_page.note_label.text, "the note: %s" % screen.leaderboard_page.note_label.text)
	check(not screen.best_label.visible, "no Best line")


func test_an_empty_category_and_a_run_outside_the_top_ten() -> void:
	var screen := _screen(_model([_entry(31, 1122.0)], -1))
	check_eq(screen.leaderboard_page.highlighted, -1, "this run is not on the board")
	check_eq(screen.leaderboard_page.note_label.text, "This run did not reach the top 10.", "the note")
	var fresh := Leaderboard.screen_model(Leaderboard.create(TMP_BOARD + ".none"), _entry(1, 1.0), RunState.MODE_NORMAL, false, 1, -1)
	screen.open(false, fresh)
	check_eq(screen.leaderboard_page.note_label.text, "No runs recorded in this category yet.", "an empty board")


func test_the_end_screen_marks_endless_and_hardcore_runs() -> void:
	RunState.start_run(2, 1)
	var normal := _screen()
	check(not normal.mode_row.visible, "a plain normal run adds nothing under the subtitle")
	check(not normal.hardcore_badge.visible, "no badge")
	RunState.start_run(2, 1, RunState.MODE_ENDLESS)
	var endless := _screen()
	check(endless.mode_row.visible and not endless.hardcore_badge.visible, "endless: the row, no badge")
	check_eq(endless.mode_label.text, "Endless mode", "its text")
	RunState.start_run(2, 1, RunState.MODE_NORMAL, true)
	var hard := _screen()
	check(hard.mode_row.visible and hard.hardcore_badge.visible, "hardcore: the HARDCORE badge")
	check_eq(hard.mode_label.text, "Normal mode", "the mode next to it")


func test_the_end_screen_with_a_full_board_fits_the_screen() -> void:
	_human("pad:a")
	_human("pad:b", &"mage")
	_human("pad:c", &"paladin")
	_human("pad:d", &"rogue")
	RunState.start_run(4, 1, RunState.MODE_ENDLESS, true)
	var entries: Array = []
	for i in 10:
		entries.append(_entry(40 - i, 1000.0 + i))
	var screen := _screen(_model(entries, 4))
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1920, 1080)
	UiFakes.step(screen, 0.0)
	for page in GameOverScreen.PAGE_NAMES.size():
		screen.set_page(page as GameOverScreen.Page)
		UiFakes.step(screen, 0.0)
		var rect := screen.panel.get_global_rect()
		check(rect.position.y >= 0.0 and rect.end.y <= 1080.0, "page %d: the panel fits the 1080 high canvas (%s)" % [page, rect])
		check(rect.size.x <= 1920.0, "page %d: and its width" % page)
