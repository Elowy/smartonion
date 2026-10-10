extends TestCase
## Main: the game-flow state machine (menu, lobby, run start, waves, intermission, defeat,
## victory, game over -> lobby, pause, controller disconnects), the deferred UI signal
## wiring (async tests) and the command line / perf helpers.

const UiFakes := preload("res://tests/ui_fakes.gd")
const DT := 1.0 / 60.0

var main: Main
var finished_runs: Array[bool] = []
var _async := false


func is_async() -> bool:
	return _async


func before_each() -> void:
	UiFakes.reset_players()
	tree.paused = false


func after_each() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	tree.paused = false
	UiFakes.reset_players()
	Enemy.invalidate_player_cache()


# --- Helpers -----------------------------------------------------------------------

func _make_main(opts: LaunchOptions = null) -> Main:
	main = Main.create(opts if opts != null else LaunchOptions.new())
	main.run_finished.connect(func(v: bool) -> void: finished_runs.append(v))
	tree.root.add_child(main)
	return main


func _bots(count: int) -> void:
	for i in count:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)


func _human(key: String) -> UiFakes.HumanInput:
	var input := UiFakes.HumanInput.new(key)
	PlayerManager.join(input, Db.get_class_data(&"warrior"))
	return input


func _run_with_bots(count: int, opts: LaunchOptions = null) -> void:
	_make_main(opts)
	_bots(count)
	main.start_run()


## Downs [param p] (several hits in case a dodge / block roll saves it).
func _down(p: Player) -> void:
	for i in 60:
		if p.downed:
			return
		p.invulnerable_left = 0.0
		p.take_damage(100000.0, CombatMath.KIND_MELEE, null)


## Runs the director's timer out (as at the end of a wave).
func _clear_wave() -> void:
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)


## Clears the wave and lets the "Wave cleared!" pause run out.
func _clear_wave_and_wait() -> void:
	_clear_wave()
	main._process(Main.WAVE_END_DELAY + 0.01)


# --- Menu / lobby --------------------------------------------------------------------

func test_boots_into_the_main_menu() -> void:
	_bots(2)
	_make_main()
	check_eq(main.state, Main.State.MENU, "state")
	check(is_instance_valid(main.main_menu) and main.main_menu.is_inside_tree(), "main menu shown")
	check_eq(PlayerManager.count(), 0, "the menu clears every slot")
	check(main.arena == null and main.lobby == null, "no run, no lobby")
	check_eq(main.process_mode, Node.PROCESS_MODE_ALWAYS, "Main drives the harness while paused")
	var layer := main.main_menu.get_parent() as CanvasLayer
	check(layer != null and layer.layer == Main.LAYER_MENU, "menu on its CanvasLayer")


func test_lobby_and_back_to_menu() -> void:
	_make_main()
	main.go_to_lobby()
	check_eq(main.state, Main.State.LOBBY, "lobby")
	check(is_instance_valid(main.lobby) and main.lobby.is_inside_tree(), "lobby shown")
	check(main.main_menu == null, "menu freed")
	check(PlayerManager.joining_enabled, "joining is on in the lobby")
	_bots(1)
	main.go_to_menu()
	check_eq(main.state, Main.State.MENU, "back in the menu")
	check(main.lobby == null, "lobby freed")
	check(not PlayerManager.joining_enabled, "joining off again")
	check_eq(PlayerManager.count(), 0, "leaving the lobby for the menu clears the slots")


func test_start_run_without_players_stays_in_the_lobby() -> void:
	_make_main()
	main.start_run()
	check_eq(main.state, Main.State.LOBBY, "nobody joined -> lobby")
	check(main.arena == null, "no arena")


# --- Run -------------------------------------------------------------------------------

func test_start_run_builds_the_run() -> void:
	_run_with_bots(3)
	check_eq(main.state, Main.State.WAVE, "wave state")
	check(is_instance_valid(main.arena) and Arena.current == main.arena, "arena is current")
	check_eq(main.arena.process_mode, Node.PROCESS_MODE_PAUSABLE, "arena freezes on pause")
	check(main.wave_director.is_running(), "director running")
	check_eq(main.wave, 1, "wave 1")
	check_eq(RunState.wave, 1, "RunState wave")
	check(RunState.active, "run active")
	check_eq(RunState.player_count, 3, "co-op scaling uses the player count")
	check_eq(main.players.size(), 3, "one player per slot")
	var spawns := main.arena.get_player_spawn_points(3)
	var slots := PlayerManager.get_slots()
	for i in 3:
		var p := main.players[i]
		check(p.get_parent() == main.arena.entities, "player %d under arena.entities" % i)
		check_eq(slots[i].player, p, "slot.player set")
		check(p.global_position.distance_to(spawns[i]) < 0.001, "player %d on its spawn point" % i)
		check(p.is_alive() and is_equal_approx(p.hp, p.max_hp()), "full HP")
		check_eq(main.hud.frames[i].player, p, "unit frame %d bound" % i)
	check(not tree.paused, "not paused")
	check(not main.intermission.visible and not main.game_over.visible and not main.pause_menu.visible,
		"run screens hidden")
	check_eq(main.intermission.process_mode, Node.PROCESS_MODE_ALWAYS, "intermission runs while paused")
	check_eq((main.hud.get_parent() as CanvasLayer).layer, Main.LAYER_HUD, "HUD layer")
	check_eq((main.pause_menu.get_parent() as CanvasLayer).layer, Main.LAYER_PAUSE, "pause on top")
	check(Main.LAYER_HUD < Main.LAYER_MENU and Main.LAYER_MENU < Main.LAYER_INTERMISSION
		and Main.LAYER_INTERMISSION < Main.LAYER_GAME_OVER and Main.LAYER_GAME_OVER < Main.LAYER_PAUSE,
		"layer order")


func test_wave_end_intermission_and_next_wave() -> void:
	_run_with_bots(2)
	_clear_wave()
	check_eq(main.state, Main.State.WAVE_END, "'Wave cleared!' pause first")
	check_eq(main.waves_completed, 1, "wave counted")
	check(not tree.paused, "players still move during the banner")
	main._process(Main.WAVE_END_DELAY * 0.5)
	check_eq(main.state, Main.State.WAVE_END, "still the banner")
	main._process(Main.WAVE_END_DELAY)
	check_eq(main.state, Main.State.INTERMISSION, "intermission")
	check(tree.paused, "the arena is frozen behind the intermission")
	check(main.intermission.is_open(), "intermission open")
	check_eq(main.intermission.cleared_wave, 1, "for wave 1")
	main.players[0].global_position = Vector3(9.0, 0.0, 5.0)
	RunState.pending_level_ups = 2
	main._on_intermission_continue()
	check_eq(main.state, Main.State.WAVE, "next wave")
	check_eq(main.wave, 2, "wave 2")
	check_eq(RunState.wave, 2, "RunState follows")
	check(not tree.paused, "unpaused")
	check(not main.intermission.visible, "intermission hidden")
	check_eq(RunState.pending_level_ups, 0, "level-ups resolved")
	var spawn := main.arena.get_player_spawn_points(2)[0]
	check(main.players[0].global_position.distance_to(spawn) < 0.001, "players back on the spawn points")


func test_downed_player_returns_next_wave() -> void:
	_run_with_bots(2)
	_down(main.players[0])
	check(main.players[0].downed, "P1 downed")
	check_eq(main.state, Main.State.WAVE, "P2 still fights")
	check_eq(main.players_downed, 1, "down counted")
	_clear_wave_and_wait()
	main._on_intermission_continue()
	check(main.players[0].is_alive(), "back at the next wave start")
	check_near(main.players[0].hp, roundf(main.players[0].max_hp() * Player.WAVE_START_REVIVE_HP_RATIO), 0.01, "at 50% HP")
	check_eq(main.revives, 0, "a wave-start return is not a teammate revive")


func test_everybody_down_is_defeat() -> void:
	_run_with_bots(2)
	_down(main.players[0])
	_down(main.players[1])
	check_eq(main.state, Main.State.GAME_OVER, "game over")
	check(not main.victory, "defeat")
	check_eq(finished_runs, [false] as Array[bool], "run_finished(false) once")
	check(tree.paused, "frozen")
	check(main.game_over.visible and not main.game_over.victory, "defeat screen")
	check(not main.hud.visible, "HUD hidden behind the game over screen")
	check(not RunState.active and not RunState.victory, "RunState ended")


func test_solo_down_is_defeat() -> void:
	_run_with_bots(1)
	_down(main.players[0])
	check_eq(main.state, Main.State.GAME_OVER, "solo: downed = defeat")


func test_victory_after_the_last_wave() -> void:
	var opts := LaunchOptions.new()
	opts.start_wave = RunState.TOTAL_WAVES
	_run_with_bots(2, opts)
	check_eq(main.wave, RunState.TOTAL_WAVES, "--start-wave jumps to the last wave")
	_clear_wave_and_wait()
	check_eq(main.state, Main.State.GAME_OVER, "game over after the last wave")
	check(main.victory and RunState.victory, "victory")
	check(main.game_over.visible and main.game_over.victory, "victory screen")
	check_eq(finished_runs, [true] as Array[bool], "run_finished(true)")


func test_game_over_returns_to_the_lobby_with_the_same_players() -> void:
	_run_with_bots(2)
	_down(main.players[0])
	_down(main.players[1])
	var old_arena := main.arena
	main._on_game_over_back()
	check_eq(main.state, Main.State.LOBBY, "lobby")
	check(main.arena == null and main.hud == null and main.wave_director == null, "run torn down")
	check(not old_arena.is_inside_tree(), "old arena left the tree")
	check(not tree.paused, "unpaused")
	check_eq(PlayerManager.count(), 2, "the party stays together")
	for slot in PlayerManager.get_slots():
		check(not slot.ready, "%s must ready again" % slot.label())
		check(slot.player == null, "%s has no player outside a run" % slot.label())
	main.start_run()
	check(is_instance_valid(main.arena) and main.arena != old_arena and Arena.current == main.arena, "fresh arena")
	check_eq(main.players.size(), 2, "both players again")
	check_eq(main.wave, 1, "from wave 1")


func test_quit_to_menu_abandons_the_run() -> void:
	_run_with_bots(2)
	main.quit_to_menu()
	check_eq(main.state, Main.State.MENU, "menu")
	check(not RunState.active, "run ended")
	check(main.arena == null, "arena freed")
	check_eq(PlayerManager.count(), 0, "slots cleared")


# --- Pause / disconnects --------------------------------------------------------------

func test_start_pauses_the_wave_and_resume_unpauses() -> void:
	_make_main()
	var a := _human("pad:a")
	var b := _human("pad:b")
	main.start_run()
	b.press(PlayerInput.Pad.START)
	a.poll(DT)
	b.poll(DT)
	main._process(DT)
	check(tree.paused, "paused")
	check(main.is_paused(), "pause menu open")
	check_eq(main.pause_menu.slot, PlayerManager.get_slot(1), "paused by P2")
	main.resume_game()
	check(not tree.paused and not main.is_paused(), "resumed")
	# START is ignored outside of a wave.
	b.release(PlayerInput.Pad.START)
	b.poll(DT)
	_clear_wave_and_wait()
	b.press(PlayerInput.Pad.START)
	b.poll(DT)
	main._process(DT)
	check(not main.is_paused(), "no pause menu over the intermission")


func test_disconnect_pauses_and_shows_a_notice() -> void:
	_make_main()
	_human("pad:a")
	main.start_run()
	var slot := PlayerManager.get_slot(0)
	PlayerManager.device_disconnected.emit(slot)
	check(tree.paused and main.is_paused(), "paused")
	check(main.hud.is_notice_visible(), "notice shown")
	check("P1" in main.hud.notice_label.text, "names the player: %s" % main.hud.notice_label.text)
	PlayerManager.device_reconnected.emit(slot)
	check(not main.hud.is_notice_visible(), "notice hidden after reconnect")
	check(main.is_paused(), "the player resumes with START")


func test_smoke_wipe_is_counted_not_game_over() -> void:
	_run_with_bots(2)
	main.options.smoke = true
	_down(main.players[0])
	_down(main.players[1])
	check_eq(main.state, Main.State.WAVE, "smoke runs go on after a wipe")
	check_eq(main.wipes, 1, "wipe counted")
	main._revive_all()
	check(main.players[0].is_alive() and main.players[1].is_alive(), "everybody up again")
	check_eq(main.revives, 0, "wipe revives are not teammate revives")
	main.options.smoke = false


# --- Deferred UI wiring (real frames) -------------------------------------------------

func test_screen_signals_drive_the_flow() -> void:
	_async = true
	_make_main()
	main.main_menu.play_pressed.emit()
	check_eq(main.state, Main.State.MENU, "transitions are deferred")
	await tree.process_frame
	check_eq(main.state, Main.State.LOBBY, "Play -> lobby")
	_bots(2)
	main.lobby.start_requested.emit()
	await tree.process_frame
	check_eq(main.state, Main.State.WAVE, "lobby start -> run")
	_clear_wave_and_wait()
	check_eq(main.state, Main.State.INTERMISSION, "intermission")
	# Bots are auto-ready: the intermission continues by itself after its first frame.
	for i in 5:
		await tree.process_frame
		if main.state == Main.State.WAVE:
			break
	check_eq(main.state, Main.State.WAVE, "bots continue on their own")
	check_eq(main.wave, 2, "wave 2")
	main.pause_game(PlayerManager.get_slot(0))
	main.pause_menu.resume_requested.emit()
	await tree.process_frame
	check(not tree.paused, "pause menu resume")
	_down(main.players[0])
	_down(main.players[1])
	main.game_over.back_to_menu_requested.emit()
	await tree.process_frame
	check_eq(main.state, Main.State.LOBBY, "game over -> lobby")
	finished.emit()


func test_smoke_wipe_revives_on_the_next_frame() -> void:
	_async = true
	_run_with_bots(1)
	main.options.smoke = true
	_down(main.players[0])
	await tree.process_frame
	check(main.players[0].is_alive(), "revived")
	check_eq(main.state, Main.State.WAVE, "still playing")
	main.options.smoke = false
	finished.emit()


# --- Helpers of the harness -----------------------------------------------------------

func test_launch_options() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--smoke", "--players=2", "--waves=5", "--seed=7",
		"--start-wave=3", "--screenshot=/tmp/x.png", "--shot-time=12", "--view=intermission", "--bogus",
		"--filter=main"]))
	check(o.smoke and o.starts_run() and o.uses_bots(), "smoke plays by itself")
	check_eq(o.players, 2, "players")
	check_eq(o.waves, 5, "waves")
	check_eq(o.run_seed(), 7, "seed")
	check_eq(o.start_wave, 3, "start wave")
	check_eq(o.last_wave(), 7, "plays waves 3..7")
	check_eq(o.screenshot_path, "/tmp/x.png", "screenshot")
	check_eq(o.shot_time, 12.0, "shot time")
	check_eq(o.view, "intermission", "view")
	check_eq(o.effective_view_time(), 9.0, "view forced 3 s before the shot")
	check_eq(o.effective_time_scale(), LaunchOptions.SMOKE_TIME_SCALE, "smoke is fast")
	check_eq(o.unknown, ["--bogus"] as Array[String], "unknown args (the test filter is ignored)")
	var d := LaunchOptions.parse(PackedStringArray())
	check_eq(d.boot_state(), &"menu", "plain launch -> menu")
	check(not d.uses_bots(), "no bots")
	check_eq(d.run_seed(), -1, "random seed")
	check_eq(d.effective_time_scale(), 1.0, "normal speed")
	check_eq(LaunchOptions.parse(PackedStringArray(["--smoke"])).run_seed(), LaunchOptions.SMOKE_SEED, "smoke is seeded")
	check_eq(LaunchOptions.parse(PackedStringArray(["--demo"])).boot_state(), &"run", "demo plays")
	check_eq(LaunchOptions.parse(PackedStringArray(["--view=lobby"])).boot_state(), &"lobby", "lobby view")
	check_eq(LaunchOptions.parse(PackedStringArray(["--start-wave=99", "--players=9"])).start_wave,
		RunState.TOTAL_WAVES, "start wave clamped")
	var w := LaunchOptions.parse(PackedStringArray(["--start-wave=24", "--waves=5"]))
	check_eq(w.last_wave(), RunState.TOTAL_WAVES, "never past the last wave")


func test_run_perf_groups_by_enemy_count() -> void:
	var perf := RunPerf.new()
	for i in 10:
		perf.sample(RunPerf.Kind.STEP, 5, 1.0)
	for i in 10:
		perf.sample(RunPerf.Kind.STEP, 100, 4.0)
	perf.sample(RunPerf.Kind.STEP, 95, 6.0)
	check_eq(perf.peak_enemies, 100, "peak")
	check_near(perf.average(RunPerf.Kind.STEP), (10.0 + 40.0 + 6.0) / 21.0, 0.0001, "overall average")
	check_near(perf.average_at_peak(RunPerf.Kind.STEP), 46.0 / 11.0, 0.0001, "average near the peak")
	check_eq(perf.step_ms_max, 6.0, "max")
	check_eq(perf.average(RunPerf.Kind.SCRIPT), 0.0, "no samples -> 0")
