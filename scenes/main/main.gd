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
##   paused: loot roll of RunState.team_loot, the level-up cards for
##   RunState.pending_level_ups, then the shared shop + personal panels; the pending level-ups
##   are cleared when the next wave starts) -> next wave; after wave RunState.total_waves() (25 in
##   the normal mode, never in the endless one) -> GAME_OVER (victory). Everybody downed at the same
##   time (solo: the player is downed) -> GAME_OVER (defeat, tree paused). Game Over -> LOBBY with
##   the same players.
## - Any player's START during a wave opens the PauseMenu (get_tree().paused). A controller
##   unplugged during a run pauses the wave and shows a HUD notice until it is back (also when
##   it is already gone as the next wave is about to start). The game cannot be resumed while a
##   joined controller is missing: the menu offers "Continue without Pn" instead
##   (drop_player: the slot is given up and the hero removed; nobody left -> lobby).
## - UI screens live on CanvasLayers: HUD < menus < intermission < game over < pause.
## - Main processes ALWAYS (it drives the dev harness while the tree is paused); the Arena and
##   the HUD layer are PAUSABLE, WaveDirector forces PAUSABLE, and the Intermission,
##   GameOverScreen and PauseMenu are ALWAYS.
## - M6 bosses: a boss wave (10, 25) lasts until its boss dies (WaveDirector); the director's
##   boss_spawned / boss_defeated drive the HUD's boss frame and the banners, the "Wave cleared!"
##   banner names the boss, and clearing wave 25 – Vor'thalax's death – is the victory
##   ([method _after_wave_end]). Smoke runs tell the director to kill a boss that outlives its enrage
##   by WaveDirector.SMOKE_BOSS_GRACE ("SMOKE boss timeout").
## - M5: the WaveDirector gets a GoblinSpawner child ([member goblin_spawner]; its
##   announcements become HUD banners). A run applies the launch options' test hooks right
##   after RunState.start_run (which resets them): GoblinSpawner.chance_override,
##   EliteAffixes.rate_mult, PlayerPanel.debug_start_tab and the start level
##   (RunState.set_start_level, before the heroes spawn).
## - M6b: the run's mode (normal / endless), hardcore flag and environment come from the launch
##   options ([method configure_run] is how the lobby changes them) and go into RunState.start_run;
##   [member RunState.environment] picks the arena's [EnvironmentData] ([method _environment_id]), and
##   the WaveDirector gets an [EventSpawner] child ([member event_spawner]) next to the GoblinSpawner.
##   Every "last wave" decision reads RunState.total_waves() / is_final_wave() (0 = endless: the run
##   ends only in defeat).
## Command line (--smoke, --demo, --screenshot, --view, --goblin-chance, --elite-mult,
## --start-level, --panel-tab, --mode, --hardcore, --env, --event ...): see LaunchOptions. SMOKE_RESULT
## keys: see smoke_result().

signal state_changed(state: State)
## A run ended (before the Game Over screen opens).
signal run_finished(victory: bool)

enum State { BOOT, MENU, LOBBY, WAVE, WAVE_END, INTERMISSION, GAME_OVER }

## Seconds (game time) between "Wave cleared!" and the intermission screen.
const WAVE_END_DELAY := 1.6
## Demo mode: seconds on the Game Over screen before the next run starts.
const DEMO_RESTART_DELAY := 6.0
## Demo mode: the bots' market stays open this long (they shop half-way), and their loot-roll
## "thinking" time scale (see LootRollScreen.bot_think_time).
const DEMO_MARKET_TIME := 4.0
const DEMO_BOT_THINK_TIME := 1.0
## Demo mode: seconds a bot "thinks" per level-up card (LevelUpScreen.bot_think_time).
const DEMO_LEVEL_UP_THINK_TIME := 1.0
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
## Game seconds allowed per intermission of a smoke run (the loot roll shows every item's
## result for LootRollScreen.RESULT_TIME).
const SMOKE_INTERMISSION_ALLOWANCE := 12.0
## Game seconds a boss wave of a smoke run may take on top of its nominal duration: the enrage
## (90 s), the safety kill after it (WaveDirector.SMOKE_BOSS_GRACE) and the fight's start.
const SMOKE_BOSS_ALLOWANCE := 90.0 + WaveDirector.SMOKE_BOSS_GRACE + 30.0
const DISCONNECT_NOTICE := "%s's controller disconnected – plug it back in to continue"
## The banner of the endless mode's wave 25 clear (RunState.begins_endless): the run goes on.
const ENDLESS_BEGINS_TEXT := "Endless begins!"

var options: LaunchOptions
var state := State.BOOT
var arena: Arena
var wave_director: WaveDirector
## Child of the WaveDirector (M5): the Loot Goblin's spawner.
var goblin_spawner: GoblinSpawner
## Child of the WaveDirector (M6b): the mid-wave event slot (EVENTS package).
var event_spawner: EventSpawner
## Child of the WaveDirector (M6b): the arena environment's hazard director (ENV package; a Forest Ruin
## run has one too, with nothing to do).
var environment_hazards: EnvironmentHazards
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
## Items bought in the shared shop / item bags picked up (RunState.team_loot) / loot rolls
## resolved this run.
var items_bought := 0
var items_looted := 0
var loot_rolls := 0
## Level-up cards picked / ability ranks the bots bought from the Trainer / stall rerolls the
## bots paid for (Intermission.bot_rerolled) this run.
var level_cards := 0
var ranks_trained := 0
var shop_rerolls := 0
## The shared wallet when the last market closed (the gold carried into the wave after it;
## the starting wallet before the first market). Unlike the final gold, it leaves out the
## last wave's haul, which no shop follows (SMOKE_RESULT "gold_at_last_shop").
var gold_at_last_shop := 0
var victory := false
## The party's class ids in slot order as the run started (start_run): the leaderboard entry keeps a
## player who left mid-run (drop_player), the slots no longer have them.
var run_classes: Array[StringName] = []
## Frame times of the whole run, grouped by enemy count.
var perf := RunPerf.new()

## The "Rolling the arena..." screen while it is up (M6b ENV), the run seed it fixed (-1 = none yet)
## and the environment it landed on.
var roll_screen: EnvironmentRollScreen
var _roll_seed := -1
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
## The "artifact ..." log lines of this run in order: one per Artifact drop and one per hero per
## wave end for every Artifact it holds (Artifacts.drop_line / held_line; printed with the SMOKE
## prefix in a smoke run). Cleared by start_run.
var artifact_lines: Array[String] = []
## The smoke harness is running (--smoke): it prints SMOKE_RESULT and quits.
var _smoke_running := false
var _smoke_done := false
var _shot_pending := false
var _view_forced := false
var _reviving_all := false
var _wave_perf := RunPerf.new()
var _clock: PhysicsClock
## RunState.team_loot size last seen (items_looted counts the growth).
var _loot_seen := 0


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
	if options.leaderboard_path != "":
		Leaderboard.path_override = options.leaderboard_path
	_build_layers()
	PlayerManager.device_disconnected.connect(_on_device_disconnected)
	PlayerManager.device_reconnected.connect(_on_device_reconnected)
	RunState.leveled_up.connect(_on_leveled_up)
	RunState.team_loot_changed.connect(_on_team_loot_changed)
	RunState.artifact_dropped.connect(_on_artifact_dropped)
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
			if options.view == "roll":
				begin_roll()
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
	# A controller that died during the run / on the game-over screen must not leave a ghost
	# slot behind (it could never ready up).
	PlayerManager.prune_disconnected()
	if lobby == null:
		lobby = Lobby.create()
		lobby.start_requested.connect(_on_lobby_start, CONNECT_DEFERRED)
		lobby.back_requested.connect(_on_lobby_back, CONNECT_DEFERRED)
		lobby.mode_changed.connect(configure_run)  # the mode select (Y / X) stores the run settings at once
		_layers[LAYER_MENU].add_child(lobby)
	else:
		lobby.reset()
	lobby.set_run_mode(options.mode, options.hardcore)  # --mode / --hardcore, or what the party chose last time
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
	RunState.start_run(slots.size(), _run_seed(), options.mode, options.hardcore, _environment_id())
	_roll_seed = -1
	artifact_lines.clear()
	run_classes.clear()
	for slot in slots:
		run_classes.append(slot.class_data.id if slot.class_data != null else &"")
	# Test hooks (start_run reset the statics to their defaults).
	RunState.shrine_chance_override = options.shrine_chance
	RunState.event_override = options.event
	RunState.dungeon_forced = options.dungeon
	GoblinSpawner.chance_override = options.goblin_chance
	EliteAffixes.rate_mult = options.elite_mult
	BossData.hp_mult = options.boss_hp
	LootDrops.artifact_chance_override = options.artifact_chance
	PlayerPanel.debug_start_tab = options.panel_tab
	if options.start_level > RunState.START_LEVEL:
		RunState.set_start_level(options.start_level)
	first_wave = options.clamp_wave(options.start_wave)  # (the lobby may have changed the mode since the parse)
	wave = 0
	waves_completed = 0
	players_downed = 0
	revives = 0
	wipes = 0
	items_bought = 0
	items_looted = 0
	loot_rolls = 0
	level_cards = 0
	ranks_trained = 0
	shop_rerolls = 0
	gold_at_last_shop = RunState.gold
	_loot_seen = RunState.team_loot.size()
	victory = false
	perf = RunPerf.new()

	# Hardcore: no Spirit Healer (only a teammate can revive a downed hero).
	arena = Arena.create(Db.environment_or_default(RunState.environment), not RunState.hardcore)
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(arena)
	wave_director = WaveDirector.create(arena)
	add_child(wave_director)
	wave_director.wave_cleared.connect(_on_wave_cleared)
	wave_director.boss_spawned.connect(_on_boss_spawned)
	wave_director.boss_defeated.connect(_on_boss_defeated)
	wave_director.smoke_boss_timeout = options.smoke
	goblin_spawner = GoblinSpawner.create(wave_director)
	wave_director.add_child(goblin_spawner)
	goblin_spawner.announced.connect(_on_announced)
	event_spawner = EventSpawner.create(wave_director)
	wave_director.add_child(event_spawner)
	event_spawner.announced.connect(_on_announced)
	environment_hazards = EnvironmentHazards.create(wave_director, Db.environment_or_default(RunState.environment))
	wave_director.add_child(environment_hazards)

	hud = Hud.create()
	_layers[LAYER_HUD].add_child(hud)
	wave_director.wave_timer_changed.connect(hud.set_wave_time)
	wave_director.boss_spawned.connect(hud.bind_boss)
	wave_director.wave_cleared.connect(hud.clear_boss)
	intermission = Intermission.create()
	intermission.continue_requested.connect(_on_intermission_continue, CONNECT_DEFERRED)
	intermission.item_bought.connect(_on_item_bought)
	intermission.loot_rolled.connect(_on_loot_rolled)
	intermission.level_card_picked.connect(_on_level_card_picked)
	intermission.ranks_trained.connect(_on_ranks_trained)
	intermission.bot_rerolled.connect(_on_bot_rerolled)
	intermission.shrine_resolved.connect(_on_shrine_resolved)
	# Smoke / demo bots shop and equip upgrades, so the item systems get exercised.
	intermission.bot_shopping = options.smoke or options.demo
	intermission.bot_market_time = DEMO_MARKET_TIME if options.demo and not options.smoke else 0.0
	intermission.loot_screen.bot_think_time = DEMO_BOT_THINK_TIME if options.demo and not options.smoke else 0.0
	intermission.level_up_screen.bot_think_time = DEMO_LEVEL_UP_THINK_TIME if options.demo and not options.smoke else 0.0
	_layers[LAYER_INTERMISSION].add_child(intermission)
	game_over = GameOverScreen.create()
	game_over.back_to_menu_requested.connect(_on_game_over_back, CONNECT_DEFERRED)
	_layers[LAYER_GAME_OVER].add_child(game_over)
	pause_menu = PauseMenu.create()
	pause_menu.resume_requested.connect(resume_game, CONNECT_DEFERRED)
	pause_menu.quit_to_menu_requested.connect(quit_to_menu, CONNECT_DEFERRED)
	pause_menu.drop_player_requested.connect(drop_player, CONNECT_DEFERRED)
	_layers[LAYER_PAUSE].add_child(pause_menu)

	players.clear()
	for slot in slots:
		players.append(_spawn_player(slot))
	hud.bind_players(players)
	if _run_frame < 0:
		_run_frame = Engine.get_physics_frames()
	_log("run started: %d players (%s), first wave %d, seed %d, mode %s, environment %s" % [
		players.size(), _class_list(), first_wave, options.run_seed(), RunState.mode_text(RunState.mode, RunState.hardcore).to_lower(),
		RunState.environment])
	start_wave(first_wave)


## Starts wave [param n]: players back on the spawn points, healed / revived by begin_wave().
func start_wave(n: int) -> void:
	if arena == null or wave_director == null:
		return
	wave = RunState.clamp_wave(n)
	get_tree().paused = false
	if intermission != null:
		intermission.hide()
	if pause_menu != null:
		pause_menu.hide()
	_place_players()
	for p in players:
		if is_instance_valid(p):
			p.begin_wave()
	_begin_shrines()
	_set_state(State.WAVE)
	_wave_perf = RunPerf.new()
	_wave_start_msec = Time.get_ticks_msec()
	# Frame the team first: the opening spawn group picks on-screen points from the camera.
	arena.camera.snap()
	wave_director.start_wave(wave)
	if hud != null:
		hud.show()
		# The running shrines (M6b) are listed under the title, with the waves they have left.
		hud.show_banner("Final Wave" if RunState.is_final_wave(wave) else "Wave %d" % wave, UiTheme.GOLD, Shrines.banner_lines())
	_pause_if_pad_missing()


## The next run's mode and hardcore flag (the lobby's mode select calls this, through Lobby.mode_changed;
## --mode / --hardcore set the same fields at launch). An unknown mode plays as normal.
func configure_run(p_mode: StringName, p_hardcore: bool) -> void:
	options.mode = p_mode if p_mode in RunState.MODES else RunState.MODE_NORMAL
	options.hardcore = p_hardcore


## The environment argument of RunState.start_run: --env when given (and known), else &"" so the run
## rolls its own environment (RunState.roll_environment, after its run seed and environment_rng exist).
func _environment_id() -> StringName:
	if options.environment != &"" and Db.get_environment(options.environment) != null:
		return options.environment
	return &""


## The seed of the next run: the one the roll screen fixed (it showed the environment of that seed),
## else the launch options' (-1 = a random one).
func _run_seed() -> int:
	return _roll_seed if _roll_seed >= 0 else options.run_seed()


## Whether a run started from the lobby plays the "Rolling the arena..." screen first: not in smoke,
## demo, screenshot and forced-view runs, and not while a test switched it off
## (EnvironmentRollScreen.enabled).
func plays_roll_screen() -> bool:
	return EnvironmentRollScreen.enabled and not (options.smoke or options.demo or options.view != "")


## Opens the "Rolling the arena..." screen over the lobby: fixes the run's seed (the launch seed, else a
## random one), shows the environment that seed rolls (--env wins) and starts the run when the reel has
## come to rest and held. The run then rolls the same environment on its own (RunState.start_run with an
## empty environment draws the same value from environment_rng), so the screen never decides anything.
func begin_roll() -> void:
	if roll_screen != null and is_instance_valid(roll_screen):
		return
	_roll_seed = options.run_seed()
	if _roll_seed < 0:
		_roll_seed = int(randi() & 0x7FFFFFFF)
	var winner := _environment_id()
	if winner == &"":
		winner = RunState.environment_for_seed(_roll_seed)
	roll_screen = EnvironmentRollScreen.create(winner)
	roll_screen.finished.connect(_on_roll_finished, CONNECT_DEFERRED)
	_layers[LAYER_MENU].add_child(roll_screen)


func _on_roll_finished(_environment_id_rolled: StringName) -> void:
	_free_roll_screen()
	if state == State.LOBBY and options.view == "":
		start_run()


func _free_roll_screen() -> void:
	_free_node(roll_screen)
	roll_screen = null


## True when a finished run goes into the leaderboard file (Leaderboard.record_run): not in smoke,
## demo, screenshot or forced-view runs, whose runs are not the player's – unless --leaderboard names
## a file of its own for them.
func writes_leaderboard() -> bool:
	if options.leaderboard_path != "":
		return true
	return not (options.smoke or options.demo or options.view != "" or options.screenshot_path != "")


## Between-wave screen (tree paused): loot roll (if any team loot), then the shared shop and
## the personal panels. Bots and unplugged devices are auto-ready.
func open_intermission() -> void:
	if intermission == null:
		return
	_set_state(State.INTERMISSION)
	get_tree().paused = true
	for slot in PlayerManager.get_slots():
		var p := slot.player as Player
		if p != null and is_instance_valid(p):
			p.end_wave()  # auras / buffs must not show in the market
			_log_artifacts_held(p)
	# WaveDirector.stop() swept the ground effects at the clear; this catches the ones that
	# landed during the "Wave cleared!" pause (bursts, bombs, craters), which would otherwise
	# wait out the market and come back in the next wave.
	for node in get_tree().get_nodes_in_group(&"ability_areas"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()
	if hud != null:
		hud.hide()  # the market has its own summary; start_wave shows the HUD again
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
	_record_hero_results()
	var board := _record_leaderboard(p_victory)
	_set_state(State.GAME_OVER)
	_log("run over: %s on wave %d (%d kills, %d gold, level %d)" % [
		"victory" if p_victory else "defeat", wave, RunState.kills, RunState.gold, RunState.level])
	var boss: Boss = wave_director.boss if wave_director != null and not p_victory else null
	if is_instance_valid(boss) and not boss.is_dead():
		_log(boss_standing_text(boss, players_downed))
	run_finished.emit(p_victory)
	if game_over != null:
		game_over.open(p_victory, board)
	if _smoke_running:
		_finish_smoke("victory" if p_victory else "defeat")
	elif options.demo and not options.holds_screens():
		get_tree().create_timer(DEMO_RESTART_DELAY, true).timeout.connect(_on_demo_restart)


## The finished run in the leaderboard: its entry (the wave that ended it, the wave play time, the party's
## classes as the run started ([member run_classes]), victory) goes into the file's category for the run's
## mode, hardcore flag and party size ([method writes_leaderboard]; Leaderboard.record_run), then the board is
## read for the end screen
## (Leaderboard.screen_model: the "Best: ..." line, the top 10 of the category, the run's place). {} when the
## leaderboard file is off limits: Leaderboard.writes_enabled is false (the unit tests), or a smoke run
## without a file of its own (--leaderboard) – a smoke run does not even read the player's file.
func _record_leaderboard(p_victory: bool) -> Dictionary:
	if not Leaderboard.writes_enabled or (options.smoke and not writes_leaderboard()):
		return {}
	var entry := Leaderboard.make_entry(wave, RunState.run_time, run_classes, p_victory)
	var rank := -1
	var save_failed := false
	if writes_leaderboard():
		var outcome := Leaderboard.record_run(entry, RunState.mode, RunState.hardcore, RunState.player_count)
		rank = int(outcome["rank"])
		save_failed = bool(outcome["save_failed"])
	var board := Leaderboard.create()
	board.load_file()
	var model := Leaderboard.screen_model(board, entry, RunState.mode, RunState.hardcore, RunState.player_count,
			rank, save_failed)
	_log("leaderboard %s: %s" % [model["key"], model["line"]])
	if save_failed:
		_log("leaderboard: the run made the board but %s could not be written" % board.path)
	return model


## How every hero ended the run (standing or down, the best item), taken now because the heroes are
## freed when the screen is left: RunState.hero_results, read by the end screen and the run card.
func _record_hero_results() -> void:
	for slot in PlayerManager.get_slots():
		var hero := slot.player as Player
		var valid := hero != null and is_instance_valid(hero)
		RunState.record_hero_result(slot.index, valid and hero.is_alive(),
				RunSummary.best_item(hero.equipment) if valid else null)


## Pause Menu "Quit to Menu": abandons the run. An endless run is still a result: it goes into the leaderboard
## as a defeat on the wave it reached (its wave in progress). A normal run that is quit is not recorded.
func quit_to_menu() -> void:
	if arena != null and RunState.active:
		if RunState.is_endless():
			_record_leaderboard(false)
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
	var running := state == State.WAVE or state == State.WAVE_END
	if running and pause_menu != null and not PlayerManager.disconnected_slots().is_empty():
		# A joined controller is unplugged: stay paused (the menu offers "Continue without Pn").
		if not pause_menu.visible:
			pause_menu.open(null)
		return
	if pause_menu != null and pause_menu.visible:
		pause_menu.hide()
	if running:
		get_tree().paused = false


## Pause Menu "Continue without Pn": the player's controller is gone, so their slot is given
## up (PlayerManager.leave) and their hero removed; the run goes on with the others. Nobody
## left -> the run is abandoned and the lobby opens.
func drop_player(slot: PlayerSlot) -> void:
	if slot == null or PlayerManager.get_slot(slot.index) != slot:
		return
	_disconnected.erase(slot.index)
	for p in players.duplicate():
		if not is_instance_valid(p) or p.slot == slot:
			players.erase(p)
			_free_node(p)
	_free_node(slot.player)
	slot.player = null
	PlayerManager.leave(slot.index)
	if hud != null:
		hud.bind_players(players)
	_log("%s dropped out (controller unplugged), %d player(s) left" % [slot.label(), PlayerManager.count()])
	if PlayerManager.count() == 0:
		if arena != null and RunState.active:
			RunState.end_run(false)
		go_to_lobby()
		return
	_show_disconnect_notice()
	if PlayerManager.disconnected_slots().is_empty():
		resume_game()
	elif is_running() and (state == State.WAVE or state == State.WAVE_END):
		pause_game(null)
	_check_party_wipe()


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

## The state timer counts physics ticks, not rendered frames: "Wave cleared!" ends after the
## same number of ticks on every run (seeded smoke runs must be reproducible).
func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	_state_time += delta
	if state == State.WAVE:
		RunState.tick_run_time(delta)
	if state == State.WAVE_END and _state_time >= WAVE_END_DELAY:
		_after_wave_end()


func _process(_delta: float) -> void:
	if not get_tree().paused and (state == State.WAVE or state == State.WAVE_END):
		_poll_pause_buttons()
		if state == State.WAVE:
			_sample_perf(RunPerf.Kind.MONITOR, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_update_harness()


func _poll_pause_buttons() -> void:
	for slot in PlayerManager.get_slots():
		if slot.input != null and slot.input.just_pressed(PlayerInput.Pad.START):
			pause_game(slot)
			return


## A joined controller that is already unplugged when a wave is about to start pauses the
## game at once, with the usual notice.
func _pause_if_pad_missing() -> void:
	var missing := PlayerManager.disconnected_slots()
	if missing.is_empty():
		return
	for m in missing:
		_disconnected[m.index] = true
	_show_disconnect_notice()
	pause_game(null)


## HUD notice for the lowest-numbered player whose controller is missing (hidden when none).
func _show_disconnect_notice() -> void:
	if hud == null:
		return
	var indices := _disconnected.keys()
	indices.sort()
	for index: int in indices:
		var other := PlayerManager.get_slot(index)
		if other != null:
			hud.show_notice(DISCONNECT_NOTICE % other.label())
			return
	hud.hide_notice()


func _after_wave_end() -> void:
	if RunState.is_final_wave(wave):
		end_run(true)
	else:
		_roll_shrine()
		_roll_portal()
		open_intermission()


## SHRINES seam (M6b): the break's shrine roll (RunState.pending_shrine, from RunState.shrine_rng), called
## on the break path just before open_intermission. The wave that just ended first counts against every
## running shrine (their effects stop, the expired ones go), then the 5% roll (--shrine-chance) decides whether
## the SHRINE phase of this break opens. See Shrines.
func _roll_shrine() -> void:
	var expired := Shrines.end_wave(players)
	if not expired.is_empty():
		_log("shrines expired after wave %d: %s" % [wave, ", ".join(PackedStringArray(expired))])
	RunState.pending_shrine = Shrines.roll()
	if RunState.pending_shrine != &"":
		_log("a shrine waits after wave %d: %s" % [wave, RunState.pending_shrine])


## The running shrines' effects (M6b) go live for the wave that starts (start_wave, after the heroes' begin_wave).
func _begin_shrines() -> void:
	Shrines.begin_wave(players)
	if not RunState.shrine_effects.is_empty():
		_log("wave %d runs under shrines: %s" % [wave, Shrines.effects_log()])


## Intermission.shrine_resolved (the SHRINE phase's vote was decided): the smoke log line.
func _on_shrine_resolved(id: StringName, accepted: bool, reason: StringName) -> void:
	_log("shrine %s %s (%s); running: %s" % [id, "accepted" if accepted else "declined", reason, Shrines.effects_log()])


## DUNGEON seam (M6b): the break's portal roll (RunState.portal_pending, from RunState.dungeon_rng), called
## on the break path just before open_intermission. The DUNGEON package owns the body.
func _roll_portal() -> void:
	pass


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
	goblin_spawner = null  # freed with the director
	event_spawner = null
	environment_hazards = null  # (freed with the director)
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
	_free_roll_screen()


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
	if state != State.LOBBY:
		return
	if plays_roll_screen():
		begin_roll()
	else:
		start_run()


func _on_lobby_back() -> void:
	if state == State.LOBBY:
		go_to_menu()


func _on_wave_cleared(n: int) -> void:
	if state != State.WAVE or n != wave:
		return
	waves_completed += 1
	_log("wave %d cleared in %.1f s: %d kills, %d gold, level %d, %d / %d standing, %d downs, items: %d looted, %d bought; elites %d/%d, goblin %d/%d/%d; %s" % [
		n, (Time.get_ticks_msec() - _wave_start_msec) / 1000.0, RunState.kills, RunState.gold,
		RunState.level, living_player_count(), players.size(), players_downed, items_looted, items_bought,
		RunState.elites_killed, RunState.elites_spawned, RunState.goblins_spawned,
		RunState.goblins_killed, RunState.goblins_escaped, _wave_perf.summary()])
	if _smoke_running and n >= options.last_wave():
		if RunState.is_final_wave(n):
			RunState.end_run(true)
		_finish_smoke("completed")
		return
	if hud != null:
		hud.show_banner(_wave_cleared_text(n))
	_set_state(State.WAVE_END)


## The banner of a won wave: "Victory!" after the last one (never in the endless mode, whose wave 25 gives
## "Endless begins!" instead), "<Boss> defeated!" after a boss wave, else "Wave cleared!".
func _wave_cleared_text(n: int) -> String:
	if RunState.is_final_wave(n):
		return "Victory!"
	if RunState.begins_endless(n):
		return ENDLESS_BEGINS_TEXT
	# (The boss itself may be freed by now: the definition stays.)
	if wave_director != null and wave_director.boss_data != null:
		return "%s defeated!" % wave_director.boss_data.display_name
	return "Wave cleared!"


## WaveDirector.boss_spawned: the arrival banner.
func _on_boss_spawned(boss: Boss) -> void:
	if hud != null and boss.boss_data != null:
		hud.show_banner(boss.boss_data.intro_text(), UiTheme.RED)
	_log(boss_arrival_text(boss, wave, players.size()))


## The smoke-log line of a boss's arrival.
static func boss_arrival_text(boss: Boss, p_wave: int, player_count: int) -> String:
	return "boss %s arrived on wave %d at %s: %.0f HP, %d player(s)" % [
		boss.boss_data.display_name if boss.boss_data != null else "?", p_wave,
		format_position(boss.global_position if boss.is_inside_tree() else boss.position),
		boss.max_hp, player_count]


## The smoke-log line of a run that was lost while [param boss] still stood (balance data: how
## far the party got).
static func boss_standing_text(boss: Boss, downs: int) -> String:
	return "defeat with boss %s alive after %.1f s: %.0f%% HP left (phase %d, enrage level %d), %d downs so far" % [
		boss.boss_data.display_name if boss.boss_data != null else "?", boss.age(),
		boss.hp_ratio() * 100.0, boss.phase, boss.enrage_level, downs]


## "(x, y, z)" with one decimal for the smoke / screenshot logs (a Vector3's own text prints
## float noise such as -8.400001).
static func format_position(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]


## WaveDirector.boss_defeated (the wave ends on the next tick): the kill time for the smoke log.
func _on_boss_defeated(boss: Boss) -> void:
	_log("boss %s defeated after %.1f s (phase %d, enrage level %d, %d casts): %d / %d standing, %d downs, %d revives so far" % [
		boss.boss_data.display_name if boss.boss_data != null else "?", boss.age(), boss.phase,
		boss.enrage_level, boss.casts_total, living_player_count(), players.size(), players_downed, revives])


func _on_intermission_continue() -> void:
	if state != State.INTERMISSION:
		return
	if options.view == "intermission" and _view_forced:
		return  # held open for the screenshot
	RunState.pending_level_ups = 0  # resolved by the intermission's level-up cards
	gold_at_last_shop = RunState.gold
	_log("market closed after wave %d: %d gold carried into wave %d (%d bot rerolls so far)" % [
		wave, gold_at_last_shop, wave + 1, shop_rerolls])
	start_wave(wave + 1)


func _on_item_bought(_slot_index: int, _item: ItemInstance) -> void:
	items_bought += 1


## RunState.artifact_dropped: the "artifact drop" log line.
func _on_artifact_dropped(item: ItemInstance, source: StringName) -> void:
	_log_artifact(Artifacts.drop_line(item, source, RunState.wave))


## After [param hero]'s wave end (its Artifacts grew): one "artifact held" line per Artifact it
## holds, in the hand or in the backpack.
func _log_artifacts_held(hero: Player) -> void:
	if hero.equipment == null:
		return
	var label := hero.slot.label() if hero.slot != null else "?"
	for item in Artifacts.held(hero.equipment):
		_log_artifact(Artifacts.held_line(label, item, wave, hero.equipment.is_equipped(item)))


func _log_artifact(text: String) -> void:
	artifact_lines.append(text)
	_log(text)


func _on_loot_rolled(_roll: LootRoll) -> void:
	loot_rolls += 1


func _on_level_card_picked(_slot_index: int, _card: LevelCard) -> void:
	level_cards += 1


func _on_ranks_trained(_slot_index: int, count: int) -> void:
	ranks_trained += count


func _on_bot_rerolled(_slot_index: int, _cost: int) -> void:
	shop_rerolls += 1


## GoblinSpawner.announced: a banner on the HUD ("A Loot Goblin appeared!").
func _on_announced(text: String, color: Color) -> void:
	if hud != null:
		hud.show_banner(text, color)


func _on_team_loot_changed() -> void:
	var n := RunState.team_loot.size()
	if n > _loot_seen:
		items_looted += n - _loot_seen
	_loot_seen = n


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
	_check_party_wipe()


## Everybody downed at once during a wave: defeat (smoke runs count a wipe and revive instead).
func _check_party_wipe() -> void:
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
	_show_disconnect_notice()


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


## Joins --players bots, classes cycling through --classes (default: Db.class_ids).
func _add_bots() -> void:
	PlayerManager.clear()
	var ids: Array[StringName] = []
	for id in options.classes:
		if Db.get_class_data(id) != null:
			ids.append(id)
		else:
			push_warning("--classes: unknown class '%s'" % id)
	if ids.is_empty():
		ids = Db.class_ids
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
		expected += RunState.wave_duration(w) + WAVE_END_DELAY + 0.5 + SMOKE_INTERMISSION_ALLOWANCE
		if RunState.is_boss_wave(w):
			expected += SMOKE_BOSS_ALLOWANCE
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
	var data := smoke_result(result)
	for line in meter_lines(data["meter"]):
		print("SMOKE meter " + line)
	print("SMOKE_RESULT " + JSON.stringify(data))
	_quit(0 if result == "completed" and int(data["errors"]) == 0 else 1)


## The SMOKE_RESULT payload (see docs/ARCHITECTURE.md "Command line"). M5 keys: elites_spawned,
## elites_killed, goblins_spawned, goblins_killed, goblins_escaped, weapons_forged,
## talent_points_spent (all heroes), talent_resets, set_bonuses (active bonuses of all heroes),
## gold_spent (RunState.try_spend_for). M6 keys: bosses_killed, artifacts_dropped,
## consumables_bought, black_market_bought, enchants_done, dust_earned, dust_spent, run_time
## (seconds of wave play, RunState.tick_run_time), meter ({slot index: {damage, healing, absorbed,
## taken, revives, downs, kills, bosses, class}} – the damage meter, RunSummary.meter_dict). M6b keys:
## mode ("normal" / "endless"), hardcore, environment (id), events_spawned, events_completed,
## shrines_offered, shrines_accepted, dungeons_entered, dungeons_completed, dungeons_failed (all
## counters of the feature packages; 0 until they land).
func smoke_result(result: String) -> Dictionary:
	var errors := _error_counter.error_count() if _error_counter != null else 0
	var need_wins := 0
	for slot_index in RunState.need_wins_by_player:
		need_wins += RunState.need_wins_by_player[slot_index]
	var talent_points := 0
	var set_bonuses := 0
	for p in players:
		if not is_instance_valid(p):
			continue
		if p.talents != null:
			talent_points += p.talents.points_spent()
		set_bonuses += SetBonuses.active_count(p.equipment)
	var data := {
		"result": result,
		"waves_completed": waves_completed,
		"first_wave": first_wave,
		"last_wave": wave,
		"kills": RunState.kills,
		"gold": RunState.gold,
		"gold_at_last_shop": gold_at_last_shop,
		"level": RunState.level,
		"players": players.size(),
		"players_downed": players_downed,
		"revives": revives,
		"wipes": wipes,
		"items_bought": items_bought,
		"items_looted": items_looted,
		"loot_rolls": loot_rolls,
		"need_wins": need_wins,
		"greed_gold": RunState.greed_gold,
		"level_cards": level_cards,
		"abilities_learned": abilities_learned(),
		"ranks_trained": ranks_trained,
		"shop_rerolls": shop_rerolls,
		"elites_spawned": RunState.elites_spawned,
		"elites_killed": RunState.elites_killed,
		"goblins_spawned": RunState.goblins_spawned,
		"goblins_killed": RunState.goblins_killed,
		"goblins_escaped": RunState.goblins_escaped,
		"weapons_forged": RunState.weapons_forged,
		"talent_points_spent": talent_points,
		"talent_resets": RunState.talent_resets,
		"set_bonuses": set_bonuses,
		"gold_spent": RunState.gold_spent,
		"bosses_killed": RunState.bosses_killed,
		"artifacts_dropped": RunState.artifacts_dropped,
		"consumables_bought": RunState.consumables_bought,
		"black_market_bought": RunState.black_market_bought,
		"enchants_done": RunState.enchants_done,
		"dust_earned": RunState.dust_earned,
		"dust_spent": RunState.dust_spent,
		"run_time": snappedf(RunState.run_time, 0.1),
		"mode": String(RunState.mode),
		"hardcore": RunState.hardcore,
		"environment": String(RunState.environment),
		"events_spawned": RunState.events_spawned,
		"events_completed": RunState.events_completed,
		"shrines_offered": RunState.shrines_offered,
		"shrines_accepted": RunState.shrines_accepted,
		"dungeons_entered": RunState.dungeons_entered,
		"dungeons_completed": RunState.dungeons_completed,
		"dungeons_failed": RunState.dungeons_failed,
		"hazards": environment_hazards.stats() if environment_hazards != null else {},
		"meter": RunSummary.meter_dict(),
		"errors": errors,
		"warnings": _error_counter.warning_count() if _error_counter != null else 0,
		"seed": options.run_seed(),
		"game_time": snappedf(_game_time(), 0.1),
		"real_time": snappedf((Time.get_ticks_msec() - _start_msec) / 1000.0, 0.1),
		"perf": perf.to_dict(),
	}
	if errors > 0:
		data["error_samples"] = _error_counter.error_samples()
	return data


## The "SMOKE meter ..." log lines: one per hero of [param meter] (RunSummary.meter_dict).
static func meter_lines(meter: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for key: String in meter:
		var m: Dictionary = meter[key]
		lines.append("P%d %s: damage %.1f, healing %.1f, absorbed %.1f, taken %.1f, revives %d, downs %d, kills %d, bosses %d" % [
			int(key) + 1, m.get("class", "?"), m["damage"], m["healing"], m["absorbed"], m["taken"],
			m["revives"], m["downs"], m["kills"], m["bosses"]])
	return lines


## Learned abilities (RB / LB and auto-cast slots) over every hero (SMOKE_RESULT).
func abilities_learned() -> int:
	var n := 0
	for p in players:
		if is_instance_valid(p) and p.abilities != null:
			for i in range(AbilityRunner.CORE_SLOTS, AbilityRunner.MAX_SLOTS):
				if p.abilities.slots[i] != null:
					n += 1
	return n


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
			_end_screen_extras()
		"victory":
			end_run(true)
			_end_screen_extras()
		"pause":
			var slots := PlayerManager.get_slots()
			pause_game(slots[0] if not slots.is_empty() else null)


## --end-page / --save-card on the forced end screen (screenshots of the Damage Meter and the card).
func _end_screen_extras() -> void:
	if game_over == null:
		return
	if options.end_page != "":
		game_over.set_page(GameOverScreen.page_from_name(options.end_page))
	if options.save_card:
		game_over.card_saved.connect(func(path: String) -> void: print("CARD %s" % path), CONNECT_ONE_SHOT)
		game_over.save_card()


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
			format_position(p.global_position), px.x, px.y, size.x, size.y, arena.camera.distance])
	var boss: Boss = wave_director.boss if wave_director != null else null
	if is_instance_valid(boss) and boss.is_inside_tree():
		var bp := cam.unproject_position(boss.global_position + Vector3.UP * 1.2)
		_log("boss %s at %s -> screen (%d, %d), %.0f%% HP, phase %d" % [
			boss.data.display_name, format_position(boss.global_position), bp.x, bp.y,
			boss.hp_ratio() * 100.0, boss.phase])


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
