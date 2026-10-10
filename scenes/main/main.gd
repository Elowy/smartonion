class_name Main
extends Node
## Root game flow (owned by the "integration" module), see docs/ARCHITECTURE.md "Runtime flow":
##
##   MENU -> LOBBY -> RUN [ WAVE -> WAVE_END -> INTERMISSION -> WAVE ... ] -> GAME_OVER -> LOBBY
##
## - MENU: MainMenu. Nobody has joined there, so entering it clears every PlayerSlot.
##   Play -> LOBBY, Quit -> quits.
## - LOBBY: Lobby (join, class pick, ready). start_requested -> a run; back -> MENU.
## - RUN: Arena + WaveDirector + one Player per slot (Arena.entities) + Hud, Intermission,
##   GameOverScreen and PauseMenu. Every wave: players back on the spawn points,
##   Player.begin_wave(), WaveDirector.start_wave(n), camera snap, "Wave n" banner.
##   wave_cleared -> WAVE_END ("Wave cleared!" for WAVE_END_DELAY) -> INTERMISSION (tree
##   paused, RunState.pending_level_ups shown) -> next wave; after wave RunState.TOTAL_WAVES
##   -> GAME_OVER (victory). Everybody downed at the same time (solo: the player is downed)
##   -> GAME_OVER (defeat, tree paused). Game Over -> LOBBY with the same players.
## - Any player's START during a wave opens the PauseMenu (get_tree().paused). A controller
##   unplugged during a run pauses the wave and shows a HUD notice until it is back.
## - UI screens live on CanvasLayers: HUD < menus < intermission < game over < pause.
## - Main processes ALWAYS (it drives the dev harness while the tree is paused); the Arena and
##   the HUD layer are PAUSABLE, WaveDirector forces PAUSABLE, and the Intermission,
##   GameOverScreen and PauseMenu are ALWAYS.
## Command line (--smoke, --demo, --screenshot, --view ...): see LaunchOptions.

signal state_changed(state: State)
## A run ended (before the Game Over screen opens).
signal run_finished(victory: bool)

enum State { BOOT, MENU, LOBBY, WAVE, WAVE_END, INTERMISSION, GAME_OVER }

## Seconds (game time) between "Wave cleared!" and the intermission screen.
const WAVE_END_DELAY := 1.6
## Demo mode: seconds on the Game Over screen before the next run starts.
const DEMO_RESTART_DELAY := 6.0
const LAYER_HUD := 10
const LAYER_MENU := 20
const LAYER_INTERMISSION := 30
const LAYER_GAME_OVER := 40
const LAYER_PAUSE := 50
const LAYER_NAMES: Dictionary[int, String] = {
	LAYER_HUD: "HudLayer", LAYER_MENU: "MenuLayer", LAYER_INTERMISSION: "IntermissionLayer",
	LAYER_GAME_OVER: "GameOverLayer", LAYER_PAUSE: "PauseLayer",
}
## Physics ticks per second of game time (project setting); time-scaled launches run more
## ticks per real second instead of longer ones, so the simulation step stays 1/60 s.
const BASE_PHYSICS_TICKS := 60
## Real-time limit of a smoke run: expected duration * FACTOR + EXTRA seconds.
const SMOKE_TIMEOUT_FACTOR := 3.0
const SMOKE_TIMEOUT_EXTRA := 60.0
const DISCONNECT_NOTICE := "%s's controller disconnected – plug it back in to continue"

var options: LaunchOptions
var state := State.BOOT
var arena: Arena
var wave_director: WaveDirector
## The run's players, in slot order (entries are freed when the run is torn down).
var players: Array[Player] = []
var hud: Hud
var main_menu: MainMenu
var lobby: Lobby
var intermission: Intermission
var game_over: GameOverScreen
var pause_menu: PauseMenu
## First wave of the run (--start-wave) and the wave being played (or just cleared).
var first_wave := 1
var wave := 0
## Run statistics (smoke result / logs).
var waves_completed := 0
var players_downed := 0
var revives := 0
## Smoke runs only: full party wipes that were revived instead of ending the run.
var wipes := 0
var victory := false
## Frame times of the whole run, grouped by enemy count.
var perf := RunPerf.new()

var _layers: Dictionary[int, CanvasLayer] = {}
var _state_time := 0.0
var _disconnected: Dictionary[int, bool] = {}
var _error_counter: ErrorCounter
var _engine_tweaked := false
var _boot_frame := 0
var _run_frame := -1
var _start_msec := 0
var _wave_start_msec := 0
var _smoke_deadline_msec := 0
## The smoke harness is running (--smoke): it prints SMOKE_RESULT and quits.
var _smoke_running := false
var _smoke_done := false
var _shot_pending := false
var _view_forced := false
var _reviving_all := false
var _wave_perf := RunPerf.new()
var _clock: PhysicsClock


## Main for [param p_options] (null = parse the command line in _ready).
static func create(p_options: LaunchOptions = null) -> Main:
	var m := Main.new()
	m.name = "Main"
	m.options = p_options
	return m


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if options == null:
		options = LaunchOptions.parse(OS.get_cmdline_user_args())
	_start_msec = Time.get_ticks_msec()
	_boot_frame = Engine.get_physics_frames()
	if options.smoke:
		_error_counter = ErrorCounter.new()
		OS.add_logger(_error_counter)
	for arg in options.unknown:
		push_warning("Main: unknown command line argument '%s'" % arg)
	_build_layers()
	PlayerManager.device_disconnected.connect(_on_device_disconnected)
	PlayerManager.device_reconnected.connect(_on_device_reconnected)
	RunState.leveled_up.connect(_on_leveled_up)
	_apply_time_scale(options.effective_time_scale())
	if options.smoke or options.demo or options.view != "":
		_clock = PhysicsClock.create()
		_clock.tick_measured.connect(_on_tick_measured)
		add_child(_clock)
	match options.boot_state():
		&"run":
			_add_bots()
			if options.smoke:
				_start_smoke()
			start_run()
		&"lobby":
			go_to_lobby()
			_add_bots()
			if PlayerManager.count() >= 2:
				PlayerManager.get_slot(0).ready = true
		_:
			go_to_menu()


func _exit_tree() -> void:
	if _error_counter != null:
		OS.remove_logger(_error_counter)
		_error_counter = null
	_apply_time_scale(1.0)
	if is_inside_tree():
		get_tree().paused = false


# --- Flow ------------------------------------------------------------------------

## Title screen. Nobody has joined there: every slot is cleared.
func go_to_menu() -> void:
	_teardown_run()
	_free_lobby()
	PlayerManager.clear()
	if main_menu == null:
		main_menu = MainMenu.create()
		main_menu.play_pressed.connect(_on_menu_play, CONNECT_DEFERRED)
		main_menu.quit_pressed.connect(_on_menu_quit, CONNECT_DEFERRED)
		_layers[LAYER_MENU].add_child(main_menu)
	_set_state(State.MENU)


## Join / class select. Joined players stay (coming back from a run they must ready again).
func go_to_lobby() -> void:
	_teardown_run()
	_free_main_menu()
	if lobby == null:
		lobby = Lobby.create()
		lobby.start_requested.connect(_on_lobby_start, CONNECT_DEFERRED)
		lobby.back_requested.connect(_on_lobby_back, CONNECT_DEFERRED)
		_layers[LAYER_MENU].add_child(lobby)
	else:
		lobby.reset()
	_set_state(State.LOBBY)


## Starts a run with every joined slot: arena, director, players, HUD, run screens, wave 1
## (or --start-wave).
func start_run() -> void:
	_teardown_run()
	_free_main_menu()
	_free_lobby()
	var slots := PlayerManager.get_slots()
	if slots.is_empty():
		print_verbose("Main: start_run() without any joined player -> lobby")
		go_to_lobby()
		return
	RunState.start_run(slots.size(), options.run_seed())
	first_wave = options.start_wave
	wave = 0
	waves_completed = 0
	players_downed = 0
	revives = 0
	wipes = 0
	victory = false
	perf = RunPerf.new()

	arena = Arena.create()
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(arena)
	wave_director = WaveDirector.create(arena)
	add_child(wave_director)
	wave_director.wave_cleared.connect(_on_wave_cleared)

	hud = Hud.create()
	_layers[LAYER_HUD].add_child(hud)
	wave_director.wave_timer_changed.connect(hud.set_wave_time)
	intermission = Intermission.create()
	intermission.continue_requested.connect(_on_intermission_continue, CONNECT_DEFERRED)
	_layers[LAYER_INTERMISSION].add_child(intermission)
	game_over = GameOverScreen.create()
	game_over.back_to_menu_requested.connect(_on_game_over_back, CONNECT_DEFERRED)
	_layers[LAYER_GAME_OVER].add_child(game_over)
	pause_menu = PauseMenu.create()
	pause_menu.resume_requested.connect(resume_game, CONNECT_DEFERRED)
	pause_menu.quit_to_menu_requested.connect(quit_to_menu, CONNECT_DEFERRED)
	_layers[LAYER_PAUSE].add_child(pause_menu)

	players.clear()
	for slot in slots:
		players.append(_spawn_player(slot))
	hud.bind_players(players)
	if _run_frame < 0:
		_run_frame = Engine.get_physics_frames()
	_log("run started: %d players (%s), first wave %d, seed %d" % [players.size(), _class_list(), first_wave, options.run_seed()])
	start_wave(first_wave)


## Starts wave [param n]: players back on the spawn points, healed / revived by begin_wave().
func start_wave(n: int) -> void:
	if arena == null or wave_director == null:
		return
	wave = clampi(n, 1, RunState.TOTAL_WAVES)
	get_tree().paused = false
	if intermission != null:
		intermission.hide()
	if pause_menu != null:
		pause_menu.hide()
	_place_players()
	for p in players:
		if is_instance_valid(p):
			p.begin_wave()
	_set_state(State.WAVE)
	_wave_perf = RunPerf.new()
	_wave_start_msec = Time.get_ticks_msec()
	wave_director.start_wave(wave)
	arena.camera.snap()
	if hud != null:
		hud.show()
		hud.show_banner("Final Wave" if wave >= RunState.TOTAL_WAVES else "Wave %d" % wave)


## Between-wave screen (tree paused). Bots and unplugged devices are auto-ready.
func open_intermission() -> void:
	if intermission == null:
		return
	_set_state(State.INTERMISSION)
	get_tree().paused = true
	intermission.open(wave, RunState.pending_level_ups)


## Ends the run: Game Over screen (victory or defeat) over the frozen arena.
func end_run(p_victory: bool) -> void:
	if arena == null or state == State.GAME_OVER:
		return
	victory = p_victory
	get_tree().paused = true
	if pause_menu != null:
		pause_menu.hide()
	if intermission != null:
		intermission.hide()
	if hud != null:
		hud.hide()
	RunState.end_run(p_victory)
	_set_state(State.GAME_OVER)
	_log("run over: %s on wave %d (%d kills, %d gold, level %d)" % [
		"victory" if p_victory else "defeat", wave, RunState.kills, RunState.gold, RunState.level])
	run_finished.emit(p_victory)
	if game_over != null:
		game_over.open(p_victory)
	if _smoke_running:
		_finish_smoke("victory" if p_victory else "defeat")
	elif options.demo and not options.holds_screens():
		get_tree().create_timer(DEMO_RESTART_DELAY, true).timeout.connect(_on_demo_restart)


## Pause Menu "Quit to Menu": abandons the run.
func quit_to_menu() -> void:
	if arena != null and RunState.active:
		RunState.end_run(false)
	go_to_menu()


## Opens the PauseMenu for [param by] (null = no player, e.g. a controller was unplugged).
func pause_game(by: PlayerSlot = null) -> void:
	if state != State.WAVE and state != State.WAVE_END:
		return
	if pause_menu == null or pause_menu.visible:
		return
	get_tree().paused = true
	pause_menu.open(by)


func resume_game() -> void:
	if pause_menu != null and pause_menu.visible:
		pause_menu.hide()
	if state == State.WAVE or state == State.WAVE_END:
		get_tree().paused = false


func is_paused() -> bool:
	return pause_menu != null and pause_menu.visible


func is_running() -> bool:
	return arena != null


## True when every player of the run is downed (a solo player counts alone).
func all_players_down() -> bool:
	var any := false
	for p in players:
		if not is_instance_valid(p):
			continue
		any = true
		if p.is_alive():
			return false
	return any


func living_player_count() -> int:
	var n := 0
	for p in players:
		if is_instance_valid(p) and p.is_alive():
			n += 1
	return n


# --- Frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	var paused := get_tree().paused
	if not paused:
		_state_time += delta
		if state == State.WAVE or state == State.WAVE_END:
			_poll_pause_buttons()
			if state == State.WAVE:
				_sample_perf(RunPerf.Kind.MONITOR, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			elif _state_time >= WAVE_END_DELAY and not get_tree().paused:
				_after_wave_end()
	_update_harness()


func _poll_pause_buttons() -> void:
	for slot in PlayerManager.get_slots():
		if slot.input != null and slot.input.just_pressed(PlayerInput.Pad.START):
			pause_game(slot)
			return


func _after_wave_end() -> void:
	if wave >= RunState.TOTAL_WAVES:
		end_run(true)
	else:
		open_intermission()


# --- Run building ------------------------------------------------------------------

func _build_layers() -> void:
	for layer: int in LAYER_NAMES:
		var cl := CanvasLayer.new()
		cl.name = LAYER_NAMES[layer]
		cl.layer = layer
		add_child(cl)
		_layers[layer] = cl
	# The HUD freezes with the game; the run screens set PROCESS_MODE_ALWAYS themselves.
	_layers[LAYER_HUD].process_mode = Node.PROCESS_MODE_PAUSABLE


## The one place where a slot becomes a hero (class, starting weapons; later the M9 loadout).
func _spawn_player(slot: PlayerSlot) -> Player:
	var p := Player.create(slot)
	arena.entities.add_child(p)
	p.downed_changed.connect(_on_player_downed_changed.bind(p))
	return p


func _place_players() -> void:
	var spawns := arena.get_player_spawn_points(players.size())
	for i in players.size():
		var p := players[i]
		if not is_instance_valid(p) or i >= spawns.size():
			continue
		p.global_position = spawns[i]
		p.velocity = Vector3.ZERO


## Frees everything of the current run (arena with players / enemies / pickups / VFX,
## director, run UI) and unpauses. Slots stay joined but lose their player and ready flag.
func _teardown_run() -> void:
	if is_inside_tree():
		get_tree().paused = false
	for node: Variant in [pause_menu, game_over, intermission, hud, wave_director, arena]:
		_free_node(node)
	pause_menu = null
	game_over = null
	intermission = null
	hud = null
	wave_director = null
	arena = null
	players.clear()
	_disconnected.clear()
	for slot in PlayerManager.get_slots():
		slot.player = null
		slot.ready = false
		var bot := slot.input as BotInput
		if bot != null:
			bot.body = null


func _free_main_menu() -> void:
	_free_node(main_menu)
	main_menu = null


func _free_lobby() -> void:
	_free_node(lobby)
	lobby = null


static func _free_node(node: Variant) -> void:
	if not is_instance_valid(node):
		return
	var n := node as Node
	if n == null:
		return
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	n.queue_free()


func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0
	state_changed.emit(s)


# --- Signals ------------------------------------------------------------------------

func _on_menu_play() -> void:
	if state == State.MENU:
		go_to_lobby()


func _on_menu_quit() -> void:
	if state == State.MENU:
		_quit(0)


func _on_lobby_start() -> void:
	if state == State.LOBBY:
		start_run()


func _on_lobby_back() -> void:
	if state == State.LOBBY:
		go_to_menu()


func _on_wave_cleared(n: int) -> void:
	if state != State.WAVE or n != wave:
		return
	waves_completed += 1
	_log("wave %d cleared in %.1f s: %d kills, %d gold, level %d, %d / %d standing, %d downs; %s" % [
		n, (Time.get_ticks_msec() - _wave_start_msec) / 1000.0, RunState.kills, RunState.gold,
		RunState.level, living_player_count(), players.size(), players_downed, _wave_perf.summary()])
	if _smoke_running and n >= options.last_wave():
		if n >= RunState.TOTAL_WAVES:
			RunState.end_run(true)
		_finish_smoke("completed")
		return
	if hud != null:
		hud.show_banner("Victory!" if n >= RunState.TOTAL_WAVES else "Wave cleared!")
	_set_state(State.WAVE_END)


func _on_intermission_continue() -> void:
	if state != State.INTERMISSION:
		return
	if options.view == "intermission" and _view_forced:
		return  # held open for the screenshot
	RunState.pending_level_ups = 0  # level-up choices arrive in M4
	start_wave(wave + 1)


func _on_game_over_back() -> void:
	if state != State.GAME_OVER:
		return
	if options.demo:
		start_run()
	else:
		go_to_lobby()


func _on_demo_restart() -> void:
	if state == State.GAME_OVER:
		start_run()


func _on_player_downed_changed(is_downed: bool, _player: Player) -> void:
	if not is_downed:
		if state == State.WAVE and not _reviving_all:
			revives += 1
		return
	players_downed += 1
	if state != State.WAVE or not all_players_down():
		return
	if options.smoke and not options.allow_defeat:
		# Smoke runs exercise later waves: a wipe is counted, then everybody gets up again.
		wipes += 1
		_revive_all.call_deferred()
		return
	end_run(false)


func _revive_all() -> void:
	if state != State.WAVE:
		return
	_reviving_all = true
	for p in players:
		if is_instance_valid(p) and not p.is_alive():
			p.revive(Player.WAVE_START_REVIVE_HP_RATIO)
	_reviving_all = false
	_log("party wiped on wave %d – the smoke run revives everybody (wipe %d)" % [wave, wipes])


func _on_device_disconnected(slot: PlayerSlot) -> void:
	if hud == null:
		return  # the lobby handles its own disconnects
	_disconnected[slot.index] = true
	hud.show_notice(DISCONNECT_NOTICE % slot.label())
	pause_game(null)


func _on_device_reconnected(slot: PlayerSlot) -> void:
	_disconnected.erase(slot.index)
	if hud == null:
		return
	if _disconnected.is_empty():
		hud.hide_notice()
	else:
		var other := PlayerManager.get_slot(_disconnected.keys()[0])
		if other != null:
			hud.show_notice(DISCONNECT_NOTICE % other.label())


func _on_leveled_up(_level: int) -> void:
	if state != State.WAVE and state != State.WAVE_END:
		return
	for p in players:
		if is_instance_valid(p) and p.is_inside_tree() and p.is_alive():
			Vfx.level_up_burst(p.global_position)


# --- Dev harness: bots, smoke, screenshots -----------------------------------------------

func _apply_time_scale(scale: float) -> void:
	if is_equal_approx(scale, 1.0) and not _engine_tweaked:
		return
	_engine_tweaked = not is_equal_approx(scale, 1.0)
	Engine.time_scale = scale
	Engine.physics_ticks_per_second = maxi(1, roundi(BASE_PHYSICS_TICKS * scale))
	Engine.max_physics_steps_per_frame = maxi(8, ceili(8.0 * scale))


## Joins --players bots, classes cycling through Db.class_ids.
func _add_bots() -> void:
	PlayerManager.clear()
	var ids := Db.class_ids
	var base_seed := options.run_seed() if options.run_seed() >= 0 else randi() % 100000
	for i in options.players:
		var id: StringName = ids[i % ids.size()] if not ids.is_empty() else &""
		PlayerManager.add_bot(id, base_seed * 7919 + i * 101 + 1)


func _on_tick_measured(step_ms: float, script_ms: float) -> void:
	if state != State.WAVE:
		return
	_sample_perf(RunPerf.Kind.SCRIPT, script_ms)
	if step_ms >= 0.0:
		_sample_perf(RunPerf.Kind.STEP, step_ms)


func _sample_perf(kind: RunPerf.Kind, ms: float) -> void:
	var enemies := get_tree().get_node_count_in_group(&"enemies")
	perf.sample(kind, enemies, ms)
	_wave_perf.sample(kind, enemies, ms)


func _start_smoke() -> void:
	_smoke_running = true
	var expected := 0.0
	for w in range(options.start_wave, options.last_wave() + 1):
		expected += RunState.wave_duration(w) + WAVE_END_DELAY + 0.5
	var real := expected / options.effective_time_scale()
	_smoke_deadline_msec = _start_msec + int((real * SMOKE_TIMEOUT_FACTOR + SMOKE_TIMEOUT_EXTRA) * 1000.0)
	print("SMOKE start: %d bots, waves %d-%d, seed %d, time scale %.1f, %d physics ticks/s, timeout %.0f s" % [
		options.players, options.start_wave, options.last_wave(), options.run_seed(),
		options.effective_time_scale(), Engine.physics_ticks_per_second,
		(_smoke_deadline_msec - _start_msec) / 1000.0])


func _finish_smoke(result: String) -> void:
	if _smoke_done:
		return
	_smoke_done = true
	var errors := _error_counter.error_count() if _error_counter != null else 0
	var data := {
		"result": result,
		"waves_completed": waves_completed,
		"first_wave": first_wave,
		"last_wave": wave,
		"kills": RunState.kills,
		"gold": RunState.gold,
		"level": RunState.level,
		"players": players.size(),
		"players_downed": players_downed,
		"revives": revives,
		"wipes": wipes,
		"errors": errors,
		"warnings": _error_counter.warning_count() if _error_counter != null else 0,
		"seed": options.run_seed(),
		"game_time": snappedf(_game_time(), 0.1),
		"real_time": snappedf((Time.get_ticks_msec() - _start_msec) / 1000.0, 0.1),
		"perf": perf.to_dict(),
	}
	if errors > 0:
		data["error_samples"] = _error_counter.error_samples()
	print("SMOKE_RESULT " + JSON.stringify(data))
	_quit(0 if result == "completed" and errors == 0 else 1)


func _update_harness() -> void:
	if _smoke_running and not _smoke_done and Time.get_ticks_msec() > _smoke_deadline_msec:
		_log("smoke run timed out in state %s" % State.keys()[state])
		_finish_smoke("timeout")
	if not _view_forced and options.view in LaunchOptions.RUN_VIEWS and _run_frame >= 0 \
			and _game_time() >= options.effective_view_time():
		_view_forced = true
		_force_view()
	if options.screenshot_path != "" and not _shot_pending and _game_time() >= options.shot_time:
		_shot_pending = true
		_take_screenshot()


## Seconds of game time since the first run started (since boot when no run started).
func _game_time() -> float:
	var from := _run_frame if _run_frame >= 0 else _boot_frame
	return float(Engine.get_physics_frames() - from) / float(Engine.physics_ticks_per_second) * Engine.time_scale


## --view: jumps to the requested screen of the running game.
func _force_view() -> void:
	match options.view:
		"intermission":
			if state == State.WAVE and wave_director != null:
				wave_director.time_left = minf(wave_director.time_left, 0.001)
		"game_over":
			end_run(false)
		"victory":
			end_run(true)
		"pause":
			var slots := PlayerManager.get_slots()
			pause_game(slots[0] if not slots.is_empty() else null)


func _take_screenshot() -> void:
	var path := options.screenshot_path
	if DisplayServer.get_name() == "headless":
		printerr("Main: --screenshot needs a display: xvfb-run -a godot --path . --rendering-driver opengl3 -- ...")
		_quit(1)
		return
	await RenderingServer.frame_post_draw
	_log_player_screen_positions()
	var image := get_viewport().get_texture().get_image()
	var err := ERR_CANT_CREATE if image == null else image.save_png(path)
	print("SCREENSHOT %s (%s)" % [path, error_string(err)])
	_quit(0 if err == OK else 1)


## Screenshot aid: where every player is on screen (pixels of the visible rect).
func _log_player_screen_positions() -> void:
	if arena == null or not is_instance_valid(arena.camera):
		return
	var cam := arena.camera.camera
	var size := get_viewport().get_visible_rect().size
	for p in players:
		if not is_instance_valid(p):
			continue
		var px := cam.unproject_position(p.global_position + Vector3.UP * 0.6)
		_log("%s %s at %s -> screen (%d, %d) of %dx%d, camera distance %.1f" % [
			p.slot.label() if p.slot != null else "?", "alive" if p.is_alive() else "downed",
			p.global_position.snappedf(0.1), px.x, px.y, size.x, size.y, arena.camera.distance])


func _quit(code: int) -> void:
	if _error_counter != null:
		OS.remove_logger(_error_counter)
		_error_counter = null
	_apply_time_scale(1.0)
	get_tree().quit(code)


func _log(text: String) -> void:
	if _smoke_running or options.demo or options.view != "":
		print("%s %s" % ["SMOKE" if _smoke_running else "MAIN", text])


func _class_list() -> String:
	var names: Array[String] = []
	for p in players:
		names.append(String(p.class_data.id) if p.class_data != null else "?")
	return ", ".join(names)
