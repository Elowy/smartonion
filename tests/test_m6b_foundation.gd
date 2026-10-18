extends TestCase
## M6b P0-B foundation hooks (behaviour-neutral for the normal mode): RunState.total_waves() for both
## modes and every former TOTAL_WAVES user reading it (Main, HUD, Intermission, GameOverScreen,
## RunSummary, RunCard, LaunchOptions), the run settings (mode / hardcore / environment) and their
## reset per run, the sub-RNGs, Arena.create(null) = today's forest, EnvironmentData through Db, the
## EventSpawner slot, the SHRINE / PORTAL Intermission phases (skipped unless pending), the
## Leaderboard helper (round trip on a temp path, versioning, the write gate), the launch flags and the
## new SMOKE_RESULT keys.

const EFakes := preload("res://tests/enemies_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0
const TMP_BOARD := "user://m6b_foundation_leaderboard.json"


## An EventSpawner whose events "exist": it records the starts and the wave ends.
class ProbeSpawner extends EventSpawner:
	var started: Array[StringName] = []
	var ended := 0

	func _spawn_event(id: StringName) -> bool:
		started.append(id)
		return true

	func end_wave() -> void:
		ended += 1
		super()


## An Intermission that records the phases it enters, the frames of the SHRINE / PORTAL phases and the
## players who left during them. hold_shrine / hold_portal withhold the stub's "vote is over", so the
## phase stays open and _process runs it.
class PhaseProbe extends Intermission:
	var entered: Array[Intermission.Phase] = []
	var hold_shrine := false
	var hold_portal := false
	var shrine_updates := 0
	var portal_updates := 0
	var shrine_left: Array[int] = []
	var portal_left: Array[int] = []

	func _start_loot() -> void:
		entered.append(Intermission.Phase.LOOT)
		super()

	func _start_shrine() -> void:
		entered.append(Intermission.Phase.SHRINE)
		super()

	func _on_shrine_finished() -> void:
		if not hold_shrine:
			super()

	func _update_shrine(delta: float) -> void:
		shrine_updates += 1
		super(delta)

	func _on_shrine_player_left(slot: PlayerSlot) -> void:
		shrine_left.append(slot.index)
		super(slot)

	func _start_level_up() -> void:
		entered.append(Intermission.Phase.LEVEL_UP)
		super()

	func _start_portal() -> void:
		entered.append(Intermission.Phase.PORTAL)
		super()

	func _on_portal_finished() -> void:
		if not hold_portal:
			super()

	func _update_portal(delta: float) -> void:
		portal_updates += 1
		super(delta)

	func _on_portal_player_left(slot: PlayerSlot) -> void:
		portal_left.append(slot.index)
		super(slot)

	func _start_market() -> void:
		entered.append(Intermission.Phase.MARKET)
		super()


## A Main whose break path is recorded: the two roll seams and the intermission, in call order.
class BreakProbe extends Main:
	var calls: Array[String] = []

	func _roll_shrine() -> void:
		calls.append("shrine")
		super()

	func _roll_portal() -> void:
		calls.append("portal")
		super()

	func open_intermission() -> void:
		calls.append("open")


var main: Main
var world: Node3D
var nodes: Array[Node] = []
var screen: PhaseProbe
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
	RunState.environment_roller = Callable()
	Leaderboard.writes_enabled = _writes_before
	Leaderboard.path_override = _path_before
	_remove_board_files()
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()
	if screen != null:
		UiFakes.free_node(screen)
		screen = null
	if world != null:
		EFakes.free_world(tree, world)
		world = null
	tree.paused = false
	UiFakes.reset_players()
	RunState.start_run(1, 1)
	Enemy.invalidate_player_cache()


func _remove_board_files() -> void:
	for path in [TMP_BOARD, TMP_BOARD + ".tmp", TMP_BOARD + ".corrupt"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _make_main(opts: LaunchOptions = null) -> Main:
	main = Main.create(opts if opts != null else LaunchOptions.new())
	tree.root.add_child(main)
	return main


func _run_with_bots(count: int, opts: LaunchOptions = null) -> void:
	_make_main(opts)
	for i in count:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)
	main.start_run()


func _clear_wave_and_wait() -> void:
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	main._physics_process(Main.WAVE_END_DELAY + 0.01)


func _add(n: Node) -> Node:
	tree.root.add_child(n)
	nodes.append(n)
	return n


# --- total_waves() ----------------------------------------------------------------------------

func test_total_waves_of_the_normal_mode() -> void:
	RunState.start_run(1, 1)
	check_eq(RunState.mode, RunState.MODE_NORMAL, "normal by default")
	check_eq(RunState.total_waves(), 25, "25 waves")
	check_eq(RunState.total_waves(), RunState.TOTAL_WAVES, "= the constant of the normal mode")
	check(not RunState.is_endless(), "not endless")
	check(RunState.is_final_wave(25) and RunState.is_final_wave(26), "wave 25 is the final one")
	check(not RunState.is_final_wave(24) and not RunState.is_final_wave(1), "wave 24 is not")
	RunState.set_wave(24)
	check(not RunState.is_last_wave(), "is_last_wave at 24")
	RunState.set_wave(25)
	check(RunState.is_last_wave(), "is_last_wave at 25")
	check_eq(RunState.clamp_wave(0), 1, "clamped up to 1")
	check_eq(RunState.clamp_wave(40), 25, "clamped down to 25")
	check_eq(RunState.clamp_wave(12), 12, "inside the range")
	check_eq(RunState.count_text(12), "12 / 25", "count text")
	check_eq(RunState.wave_progress_text(7), "Wave 7 / 25", "HUD text")


func test_total_waves_of_the_endless_mode() -> void:
	RunState.start_run(1, 1, RunState.MODE_ENDLESS)
	check_eq(RunState.total_waves(), 0, "0 = unbounded")
	check(RunState.is_endless(), "endless")
	check(not RunState.is_final_wave(25) and not RunState.is_final_wave(500), "no final wave")
	RunState.set_wave(25)
	check(not RunState.is_last_wave(), "wave 25 is not the last one")
	check_eq(RunState.clamp_wave(0), 1, "still at least 1")
	check_eq(RunState.clamp_wave(40), 40, "no upper bound")
	check_eq(RunState.count_text(12), "12", "count text without a total")
	check_eq(RunState.wave_progress_text(31), "Wave 31", "HUD text without a total")


func test_waves_for_mode_and_mode_text() -> void:
	check_eq(RunState.waves_for_mode(RunState.MODE_NORMAL), 25, "normal")
	check_eq(RunState.waves_for_mode(RunState.MODE_ENDLESS), 0, "endless")
	check_eq(RunState.waves_for_mode(&"nonsense"), 25, "an unknown mode is a normal one")
	check_eq(RunState.mode_text(RunState.MODE_NORMAL), "Normal", "text")
	check_eq(RunState.mode_text(RunState.MODE_ENDLESS, true), "Endless · Hardcore", "text with hardcore")
	check_eq(RunState.MODES, [RunState.MODE_NORMAL, RunState.MODE_ENDLESS] as Array[StringName], "the modes")


# --- Former 25 users --------------------------------------------------------------------------

func test_hud_wave_label_reads_the_run_length() -> void:
	RunState.start_run(1, 1)
	var hud := _add(Hud.create()) as Hud
	RunState.set_wave(12)
	check_eq(hud.wave_label.text, "Wave 12 / 25", "normal")
	RunState.start_run(1, 1, RunState.MODE_ENDLESS)
	RunState.set_wave(31)
	check_eq(hud.wave_label.text, "Wave 31", "endless: no total")
	var fresh := _add(Hud.create()) as Hud
	check_eq(fresh.wave_label.text, "Wave 31", "a new HUD starts with the right text")


func test_market_header_text_reads_the_run_length() -> void:
	RunState.start_run(1, 1)
	check_eq(Intermission.next_wave_text(7), "Next up: Wave 7 of 25  ·  50 seconds", "normal")
	check_eq(Intermission.next_wave_text(10), "Next up: Wave 10 of 25 – Boss wave! (ends when the boss falls)", "normal boss")
	check_eq(Intermission.next_wave_text(20), "Next up: Wave 20 of 25  ·  160 seconds  –  Elite wave!", "normal elite")
	check_eq(Intermission.next_wave_text(26), "The final battle is won", "past the last wave")
	RunState.start_run(1, 1, RunState.MODE_ENDLESS)
	check_eq(Intermission.next_wave_text(26), "Next up: Wave 26  ·  %d seconds" % int(RunState.wave_duration(26)),
			"endless goes on past 25 (the 210 s cap is the MODES package's)")
	check_eq(Intermission.next_wave_text(10), "Next up: Wave 10 – Boss wave! (ends when the boss falls)", "endless boss wave")


func test_game_over_screen_reads_the_run_length() -> void:
	PlayerManager.join(UiFakes.HumanInput.new("pad:a"), Db.get_class_data(&"warrior"))
	var screen_go := _add(GameOverScreen.create()) as GameOverScreen
	RunState.set_wave(7)
	screen_go.open(false)
	check_eq(screen_go.waves_value.text, "6 / 25", "normal defeat")
	check_eq(GameOverScreen.waves_cleared(true), 25, "normal victory")
	screen_go.open(true)
	check_eq(screen_go.waves_value.text, "25 / 25", "normal victory text")
	check_eq(screen_go.subtitle_label.text, "All 25 waves survived – the onions prevail!", "normal victory subtitle")
	RunState.start_run(1, 1, RunState.MODE_ENDLESS)
	RunState.set_wave(31)
	check_eq(GameOverScreen.waves_cleared(false), 30, "endless: every wave before the fatal one")
	screen_go.open(false)
	check_eq(screen_go.waves_value.text, "30", "endless: the count alone")
	check_eq(screen_go.title_label.text, "Defeat", "defeat")
	screen_go.open(true)  # (an endless run has no victory; a forced one must still read sensibly)
	check_eq(screen_go.subtitle_label.text, "31 waves survived – the onions prevail!", "endless victory subtitle")


func test_run_summary_and_card_read_the_run_length() -> void:
	RunState.start_run(1, 1)
	RunState.set_wave(12)
	var s := RunSummary.collect(false)
	check_eq(s["total_waves"], 25, "summary: 25")
	check_eq(s["mode"], "Normal", "mode label")
	check_eq(s["environment"], "Forest Ruin", "environment label")
	check(not s["endless"] and not s["hardcore"], "flags")
	check_eq(RunCard.model(s)["waves_text"], "Fell on wave 12", "card: defeat")
	RunState.start_run(1, 1, RunState.MODE_ENDLESS, true)
	RunState.set_wave(31)
	s = RunSummary.collect(false)
	check_eq(s["total_waves"], 0, "summary: endless")
	check_eq(s["mode"], "Endless · Hardcore", "mode label with hardcore")
	check(s["endless"] and s["hardcore"], "flags")
	check_eq(s["waves_cleared"], 30, "waves cleared")
	var card := RunCard.model(s)
	check_eq(card["waves_text"], "Fell on wave 31", "card: endless defeat past 25")
	check_eq(card["mode"], "Endless · Hardcore", "card mode")
	var won := RunCard.model({"victory": true, "waves_cleared": 25, "total_waves": 25})
	check_eq(won["waves_text"], "25 / 25 waves", "card: normal victory")
	var survived := RunCard.model({"victory": true, "waves_cleared": 40, "total_waves": 0})
	check_eq(survived["waves_text"], "40 waves", "card: a count without a total")
	check_eq(RunSummary.mode_label(&"hardcore"), "Hardcore", "the label keeps capitalising any mode")


func test_launch_options_clamp_waves_by_mode() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--start-wave=99"]))
	check_eq(o.start_wave, 25, "normal: clamped to 25")
	o = LaunchOptions.parse(PackedStringArray(["--start-wave=0"]))
	check_eq(o.start_wave, 1, "clamped to 1")
	o = LaunchOptions.parse(PackedStringArray(["--mode=endless", "--start-wave=40"]))
	check_eq(o.start_wave, 40, "endless: the mode first")
	o = LaunchOptions.parse(PackedStringArray(["--start-wave=40", "--mode=endless"]))
	check_eq(o.start_wave, 40, "endless: the mode after (order does not matter)")
	o = LaunchOptions.parse(PackedStringArray(["--start-wave=500", "--mode=endless"]))
	check_eq(o.start_wave, LaunchOptions.MAX_ENDLESS_START_WAVE, "endless: a ceiling")
	o = LaunchOptions.parse(PackedStringArray(["--start-wave=24", "--waves=5"]))
	check_eq(o.last_wave(), 25, "normal smoke stops at 25")
	o = LaunchOptions.parse(PackedStringArray(["--start-wave=24", "--waves=5", "--mode=endless"]))
	check_eq(o.last_wave(), 28, "endless smoke plays all five")
	check_eq(o.clamp_wave(0), 1, "clamp_wave")


func test_main_clamps_and_ends_by_the_run_length() -> void:
	var opts := LaunchOptions.new()
	opts.start_wave = 25
	_run_with_bots(1, opts)
	main.start_wave(99)
	check_eq(main.wave, 25, "normal: wave 99 plays as 25")
	_clear_wave_and_wait()
	check_eq(main.state, Main.State.GAME_OVER, "normal: the last wave ends the run")
	check(main.victory, "victory")
	# Endless: the same wave 25 goes on to the market, wave 26 follows, no clamp.
	var endless := LaunchOptions.new()
	endless.mode = RunState.MODE_ENDLESS
	endless.start_wave = 25
	_run_with_bots_again(endless)
	check_eq(RunState.total_waves(), 0, "endless run")
	check_eq(main.wave, 25, "starts on 25")
	_clear_wave_and_wait()
	check_eq(main.state, Main.State.INTERMISSION, "endless: wave 25 ends in the market")
	check(not main.victory and RunState.active, "no victory, the run goes on")
	main._on_intermission_continue()
	check_eq(main.wave, 26, "wave 26 follows")
	check_eq(main.state, Main.State.WAVE, "playing")
	main.start_wave(120)
	check_eq(main.wave, 120, "no upper clamp")
	check_eq(main._wave_cleared_text(25), "Wave cleared!", "no victory banner past 25")


## A second Main run in the same test (the first one is torn down).
func _run_with_bots_again(opts: LaunchOptions) -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	UiFakes.reset_players()
	_run_with_bots(1, opts)


func test_normal_victory_banner() -> void:
	_run_with_bots(1)
	check_eq(main._wave_cleared_text(25), "Victory!", "the last wave of a normal run")
	check_eq(main._wave_cleared_text(24), "Wave cleared!", "an ordinary wave")


func test_an_endless_wave_has_the_wave_banner_never_the_final_one() -> void:
	var opts := LaunchOptions.new()
	opts.mode = RunState.MODE_ENDLESS
	_run_with_bots(1, opts)
	main.start_wave(26)
	check_eq(main.hud.banner_label.text, "Wave 26", "endless wave 26 has no final wave")
	main.start_wave(25)
	check_eq(main.hud.banner_label.text, "Wave 25", "endless wave 25 is not final either")


func test_a_normal_run_names_its_last_wave_final() -> void:
	_run_with_bots(1)
	main.start_wave(24)
	check_eq(main.hud.banner_label.text, "Wave 24", "an ordinary wave")
	main.start_wave(25)
	check_eq(main.hud.banner_label.text, "Final Wave", "normal wave 25 is the final one")


## The smoke path of a wave that clears (_smoke_done keeps the smoke result from quitting the runner).
func test_an_endless_smoke_run_never_wins_at_25_or_later() -> void:
	var opts := LaunchOptions.new()
	opts.mode = RunState.MODE_ENDLESS
	opts.start_wave = 25
	opts.waves = 1
	_run_with_bots(1, opts)
	main._smoke_running = true
	main._smoke_done = true
	for w in [25, 26]:
		main.start_wave(w)
		main._on_wave_cleared(w)
		check(not RunState.victory, "endless wave %d clears without a victory" % w)
	check(RunState.active and main.state != Main.State.GAME_OVER, "the endless run goes on")


func test_a_normal_smoke_run_wins_at_25() -> void:
	var opts := LaunchOptions.new()
	opts.start_wave = 25
	opts.waves = 1
	_run_with_bots(1, opts)
	main._smoke_running = true
	main._smoke_done = true
	main.start_wave(25)
	main._on_wave_cleared(25)
	check(RunState.victory, "normal wave 25 is the victory of a smoke run too")


# --- Run settings, reset per run --------------------------------------------------------------

func test_start_run_takes_mode_hardcore_and_environment() -> void:
	RunState.start_run(2, 7, RunState.MODE_ENDLESS, true, &"forest_ruin")
	check_eq(RunState.mode, RunState.MODE_ENDLESS, "mode")
	check(RunState.hardcore, "hardcore")
	check_eq(RunState.environment, &"forest_ruin", "environment")
	RunState.start_run(2, 7, &"turbo")
	check_eq(RunState.mode, RunState.MODE_NORMAL, "an unknown mode plays as normal")
	RunState.start_run(2, 7, RunState.MODE_NORMAL, false, &"")
	check_eq(RunState.environment, RunState.DEFAULT_ENVIRONMENT, "an empty environment is the default")


func test_run_settings_and_counters_reset_with_every_run() -> void:
	RunState.start_run(1, 3, RunState.MODE_ENDLESS, true, &"forest_ruin")
	RunState.shrine_chance_override = 0.5
	RunState.event_override = EventSpawner.DEFEND_TOTEM
	RunState.dungeon_forced = true
	RunState.events_spawned = 3
	RunState.events_completed = 2
	RunState.shrines_offered = 4
	RunState.shrines_accepted = 1
	RunState.dungeons_entered = 2
	RunState.dungeons_completed = 1
	RunState.dungeons_failed = 1
	RunState.pending_shrine = &"greed"
	RunState.portal_pending = true
	RunState.shrine_effects.append({"id": &"greed", "waves_left": 3})
	RunState.start_run(1, 3)
	check_eq(RunState.mode, RunState.MODE_NORMAL, "mode back to normal")
	check(not RunState.hardcore, "hardcore off")
	check_eq(RunState.environment, RunState.DEFAULT_ENVIRONMENT, "environment back to the default")
	check_eq(RunState.shrine_chance_override, -1.0, "shrine chance override off")
	check_eq(RunState.event_override, &"", "event override off")
	check(not RunState.dungeon_forced, "dungeon flag off")
	for v: int in [RunState.events_spawned, RunState.events_completed, RunState.shrines_offered,
			RunState.shrines_accepted, RunState.dungeons_entered, RunState.dungeons_completed, RunState.dungeons_failed]:
		check_eq(v, 0, "counter reset")
	check_eq(RunState.pending_shrine, &"", "no pending shrine")
	check(not RunState.portal_pending, "no pending portal")
	check(RunState.shrine_effects.is_empty(), "no shrine effects")


# --- Sub-RNGs ---------------------------------------------------------------------------------

func test_derived_seed_is_stable_distinct_and_non_negative() -> void:
	var a := RunState.derived_seed(5, RunState.SALT_EVENTS)
	check_eq(RunState.derived_seed(5, RunState.SALT_EVENTS), a, "stable")
	check(a >= 0, "non-negative")
	var seen: Dictionary = {}
	for salt in [RunState.SALT_ENVIRONMENT, RunState.SALT_EVENTS, RunState.SALT_SHRINES, RunState.SALT_DUNGEON]:
		for base in [0, 1, 5, 4242]:
			var v := RunState.derived_seed(base, salt)
			check(v >= 0, "non-negative")
			check(not seen.has(v), "unique per (seed, salt)")
			seen[v] = true


func test_sub_rngs_never_touch_the_gameplay_rng() -> void:
	RunState.start_run(1, 42)
	var ref := RandomNumberGenerator.new()
	ref.seed = 42
	check_eq(RunState.run_seed, 42, "the run seed")
	check_eq(RunState.rng.state, ref.state, "start_run left the gameplay rng exactly at its seed")
	for r in [RunState.environment_rng, RunState.event_rng, RunState.shrine_rng, RunState.dungeon_rng]:
		r.randf()
		r.randi()
	check_eq(RunState.rng.state, ref.state, "drawing from the sub-rngs does not move it")
	check_eq(RunState.rng.randi(), ref.randi(), "the gameplay stream is the plain seeded one")


func test_sub_rngs_follow_the_seed() -> void:
	RunState.start_run(1, 100)
	var a := [RunState.event_rng.randi(), RunState.shrine_rng.randi(), RunState.environment_rng.randi(), RunState.dungeon_rng.randi()]
	RunState.start_run(1, 100)
	var b := [RunState.event_rng.randi(), RunState.shrine_rng.randi(), RunState.environment_rng.randi(), RunState.dungeon_rng.randi()]
	check_eq(a, b, "same seed, same streams")
	RunState.start_run(1, 101)
	var c := [RunState.event_rng.randi(), RunState.shrine_rng.randi(), RunState.environment_rng.randi(), RunState.dungeon_rng.randi()]
	check(a != c, "another seed, other streams")
	check(a[0] != a[1] and a[1] != a[2] and a[2] != a[3], "the four streams differ")
	var again := RunState.sub_rng(RunState.SALT_EVENTS)
	check_eq(again.seed, RunState.derived_seed(RunState.run_seed, RunState.SALT_EVENTS), "sub_rng(salt)")


func test_a_random_run_seed_is_recorded() -> void:
	RunState.start_run(1)
	var r := RandomNumberGenerator.new()
	r.seed = RunState.run_seed
	check_eq(r.randi(), RunState.rng.randi(), "re-seeding with run_seed reproduces the gameplay stream")


# --- The environment roll ------------------------------------------------------------------

## A roller that records what it saw (the run seed, environment_rng's seed, the calls) and returns [param id].
func _roller_returning(id: StringName, seen: Dictionary) -> Callable:
	return func() -> StringName:
		seen["calls"] = int(seen.get("calls", 0)) + 1
		seen["run_seed"] = RunState.run_seed
		seen["env_seed"] = RunState.environment_rng.seed
		return id


func test_an_empty_environment_takes_the_roller_result() -> void:
	var seen := {}
	RunState.environment_roller = _roller_returning(&"dusk_marsh", seen)
	RunState.start_run(1, 4242)
	check_eq(seen.get("calls", 0), 1, "the roller runs once per run")
	check_eq(RunState.environment, &"dusk_marsh", "an empty environment is the roller's result")
	check_eq(seen.get("run_seed", -1), 4242, "the roll runs after run_seed is set")
	check_eq(seen.get("env_seed", -1), RunState.derived_seed(4242, RunState.SALT_ENVIRONMENT),
			"the roll runs after environment_rng is set")
	RunState.start_run(1, 4242, RunState.MODE_NORMAL, false, &"")
	check_eq(RunState.environment, &"dusk_marsh", "the same empty argument rolls again")
	check_eq(seen.get("calls", 0), 2, "each run rolls once")


func test_the_roll_without_a_roller_is_the_forest() -> void:
	RunState.start_run(1, 4242)
	check_eq(RunState.environment, &"forest_ruin", "no roller: the Forest Ruin, without drawing")


func test_a_forced_environment_wins_over_the_roll() -> void:
	var seen := {}
	RunState.environment_roller = _roller_returning(&"dusk_marsh", seen)
	var opts := LaunchOptions.new()
	opts.environment = &"forest_ruin"
	_run_with_bots(1, opts)
	check_eq(RunState.environment, &"forest_ruin", "--env forces the environment")
	check_eq(seen.get("calls", 0), 0, "the roll does not run when --env forces one")


func test_main_rolls_when_no_environment_is_forced() -> void:
	var seen := {}
	RunState.environment_roller = _roller_returning(&"forest_ruin", seen)
	_run_with_bots(1, LaunchOptions.new())
	check_eq(seen.get("calls", 0), 1, "Main passes an empty environment, so the run rolls")
	check_eq(RunState.environment, &"forest_ruin", "the run takes the roll")


func test_the_environment_roll_never_touches_the_gameplay_rng() -> void:
	var ref := RandomNumberGenerator.new()
	ref.seed = 77
	RunState.environment_roller = func() -> StringName:
		return &"dusk_marsh" if RunState.environment_rng.randi() % 2 == 0 else &"forest_ruin"
	RunState.start_run(1, 77)
	check_eq(RunState.rng.state, ref.state, "the roll leaves the gameplay rng at its seed")
	check_eq(RunState.rng.randi(), ref.randi(), "the gameplay stream is the plain seeded one")
	check(RunState.environment_rng.state != RunState.sub_rng(RunState.SALT_ENVIRONMENT).state,
			"the roll drew from environment_rng")


# --- Arena / EnvironmentData ------------------------------------------------------------------

func test_arena_without_an_environment_is_the_forest() -> void:
	var arena := Arena.create(null)
	nodes.append(arena)
	var plain := Arena.create()
	nodes.append(plain)
	for a: Arena in [arena, plain]:
		check(a.environment != null, "an environment is always set")
		var env := a.world_environment.environment
		check_eq(env.background_color, Color(0.56, 0.74, 0.92), "sky")
		check_eq(env.ambient_light_color, Color(0.6, 0.66, 0.8), "ambient colour")
		check_eq(env.ambient_light_energy, 0.62, "ambient energy")
		check_eq(env.fog_light_color, Color(0.7, 0.8, 0.88), "fog colour")
		check_eq(env.fog_density, 0.0045, "fog density")
		check_eq(env.glow_intensity, 0.55, "glow")
		check_eq(env.adjustment_saturation, 1.12, "saturation")
		check_eq(env.adjustment_contrast, 1.05, "contrast")
		check_eq(a.sun.light_color, Color(1.0, 0.92, 0.78), "sun colour")
		check_eq(a.sun.light_energy, 0.92, "sun energy")
		check(a.sun.rotation_degrees.is_equal_approx(Vector3(-52.0, -128.0, 0.0)), "sun direction")
		var mat := a.ground.material_override as ShaderMaterial
		check_eq(mat.get_shader_parameter("road"), Vector2(0.0, 1.7), "road")
		check_eq(mat.get_shader_parameter("grass_dark"), Color(0.2, 0.4, 0.12), "grass_dark")
		check_eq(mat.get_shader_parameter("dirt_light"), Color(0.62, 0.48, 0.3), "dirt_light")
		check(a.spirit_healer != null and a.entities != null and a.camera != null, "the usual parts")
		check_eq(a.get_bounds(), Rect2(-Arena.SIZE / 2.0, Arena.SIZE), "the playable rectangle")
		check_eq(a.dirt_patches.size(), 5, "dirt patches")
		check(a.get_node_or_null(^"Decor") != null, "the forest decor")


func test_arena_of_the_forest_ruin_data_equals_the_default() -> void:
	var forest := Db.get_environment(&"forest_ruin")
	check(forest != null, "forest_ruin.tres loads")
	var from_data := Arena.create(forest)
	nodes.append(from_data)
	var plain := Arena.create()
	nodes.append(plain)
	check(from_data.environment == forest, "the arena keeps the given environment")
	var a := from_data.world_environment.environment
	var b := plain.world_environment.environment
	check_eq(a.background_color, b.background_color, "sky")
	check_eq(a.fog_density, b.fog_density, "fog")
	check_eq(from_data.sun.light_energy, plain.sun.light_energy, "sun")
	var ma := from_data.ground.material_override as ShaderMaterial
	var mb := plain.ground.material_override as ShaderMaterial
	for param in ["road", "grass_dark", "grass_mid", "grass_light", "grass_warm", "dirt_light", "dirt_dark", "arena_half", "patch_count"]:
		check_eq(ma.get_shader_parameter(param), mb.get_shader_parameter(param), "ground %s" % param)
	check_eq(from_data.get_decor_rect(), plain.get_decor_rect(), "decor rectangle")


func test_arena_can_be_built_without_the_spirit_healer() -> void:
	var with_healer := Arena.create(null)
	nodes.append(with_healer)
	check(with_healer.spirit_healer != null and with_healer.spirit_healer.get_parent() == with_healer, "the default has one")
	var without := Arena.create(null, false)
	nodes.append(without)
	check(without.spirit_healer == null, "none on request (hardcore, the dungeon)")
	check(without.entities != null and without.camera != null and without.get_node_or_null(^"Decor") != null, "everything else is built")
	check_eq(Arena.SIZE, Vector2(34.0, 22.0), "the arena size every environment shares")


func test_arena_follows_a_custom_environment() -> void:
	# Every EnvironmentData field gets a value that differs from its default (checked below), and every
	# one of them is asserted on the arena built from it: the world environment, the sun, the ground
	# shader parameters and the wall material's tint. A field added later fails the first check until
	# this test gives it a value and an assertion.
	var env := EnvironmentData.new()
	env.id = &"test_env"
	env.display_name = "Test Glade"
	env.description = "A test environment."
	env.roll_weight = 0.5
	env.decor_id = &"test_decor"
	env.hazard_id = &"grasping_hands"
	env.sky_color = Color(0.1, 0.1, 0.2)
	env.ambient_color = Color(0.3, 0.2, 0.1)
	env.ambient_energy = 0.31
	env.fog_color = Color(0.4, 0.5, 0.6)
	env.fog_density = 0.02
	env.sun_color = Color(0.2, 0.9, 0.5)
	env.sun_energy = 0.4
	env.sun_rotation = Vector3(-30.0, 40.0, 10.0)
	env.glow_intensity = 0.8
	env.saturation = 0.7
	env.contrast = 1.3
	env.grass_dark = Color(0.9, 0.1, 0.1)
	env.grass_mid = Color(0.8, 0.2, 0.2)
	env.grass_light = Color(0.7, 0.3, 0.3)
	env.grass_warm = Color(0.6, 0.4, 0.3)
	env.dirt_light = Color(0.5, 0.5, 0.9)
	env.dirt_dark = Color(0.2, 0.2, 0.6)
	env.has_road = false
	env.road_width = 2.4
	env.wall_tint = Color(0.5, 0.5, 1.0)
	var defaults := EnvironmentData.new()
	var unset: Array[String] = []
	for prop in env.get_script().get_script_property_list():
		var name: String = prop["name"]
		if name == "script" or not (prop["usage"] & PROPERTY_USAGE_STORAGE):
			continue
		if env.get(name) == defaults.get(name):
			unset.append(name)
	check_eq(unset, [] as Array[String], "every EnvironmentData field has a non-default value in this test")

	var arena := Arena.create(env)
	nodes.append(arena)
	check(arena.environment == env, "the arena keeps the environment it was built from")
	check_eq(arena.environment.id, &"test_env", "id")
	check_eq(arena.environment.display_name, "Test Glade", "display_name")
	check_eq(arena.environment.description, "A test environment.", "description")
	check_eq(arena.environment.roll_weight, 0.5, "roll_weight")
	check_eq(arena.environment.decor_id, &"test_decor", "decor_id (an unknown set builds the forest)")
	check_eq(arena.environment.hazard_id, &"grasping_hands", "hazard_id")
	check(arena.environment.has_hazard(), "has_hazard")
	# World environment.
	var wenv := arena.world_environment.environment
	check_eq(wenv.background_color, Color(0.1, 0.1, 0.2), "sky_color -> background")
	check_eq(wenv.ambient_light_color, Color(0.3, 0.2, 0.1), "ambient_color")
	check_eq(wenv.ambient_light_energy, 0.31, "ambient_energy")
	check_eq(wenv.fog_light_color, Color(0.4, 0.5, 0.6), "fog_color")
	check_eq(wenv.fog_density, 0.02, "fog_density")
	check_eq(wenv.glow_intensity, 0.8, "glow_intensity")
	check_eq(wenv.adjustment_saturation, 0.7, "saturation")
	check_eq(wenv.adjustment_contrast, 1.3, "contrast")
	# Sun.
	check_eq(arena.sun.light_color, Color(0.2, 0.9, 0.5), "sun_color")
	check_eq(arena.sun.light_energy, 0.4, "sun_energy")
	check(arena.sun.rotation_degrees.is_equal_approx(Vector3(-30.0, 40.0, 10.0)), "sun_rotation")
	# Ground shader.
	var mat := arena.ground.material_override as ShaderMaterial
	check(mat.get_shader_parameter("road").y < 0.01, "has_road false: a vanishing road width")
	check_eq(mat.get_shader_parameter("grass_dark"), Color(0.9, 0.1, 0.1), "grass_dark")
	check_eq(mat.get_shader_parameter("grass_mid"), Color(0.8, 0.2, 0.2), "grass_mid")
	check_eq(mat.get_shader_parameter("grass_light"), Color(0.7, 0.3, 0.3), "grass_light")
	check_eq(mat.get_shader_parameter("grass_warm"), Color(0.6, 0.4, 0.3), "grass_warm")
	check_eq(mat.get_shader_parameter("dirt_light"), Color(0.5, 0.5, 0.9), "dirt_light")
	check_eq(mat.get_shader_parameter("dirt_dark"), Color(0.2, 0.2, 0.6), "dirt_dark")
	# Road: has_road switches it, road_width sets it (a second arena with the road on).
	var with_road := env.duplicate() as EnvironmentData
	with_road.has_road = true
	var road_arena := Arena.create(with_road)
	nodes.append(road_arena)
	var road_mat := road_arena.ground.material_override as ShaderMaterial
	check_eq(road_mat.get_shader_parameter("road"), Vector2(0.0, 2.4), "has_road + road_width")
	# Walls: the wall material is tinted by wall_tint.
	var stones := arena.walls.get_node("WallVisual/Stones") as MeshInstance3D
	var wall_mat := stones.material_override as ShaderMaterial
	check_eq(wall_mat.get_shader_parameter("albedo"), Color(0.5, 0.5, 1.0), "wall_tint -> wall material")
	check_eq(road_arena.walls.get_node("WallVisual/Stones").material_override.get_shader_parameter("albedo"),
			Color(0.5, 0.5, 1.0), "wall_tint on every arena of the environment")
	# decor_id: the arena keeps the id; the decor set of an unknown id is the forest's (same children).
	var forest := Arena.create()
	nodes.append(forest)
	check_eq(arena.get_node("Decor").get_child_count(), forest.get_node("Decor").get_child_count(),
			"an unknown decor_id builds the forest decor")
	check_eq(arena.get_bounds(), Rect2(-Arena.SIZE / 2.0, Arena.SIZE), "the playable rectangle never changes")
	check(not EnvironmentData.new().has_hazard(), "no hazard by default")


func test_db_loads_the_environments() -> void:
	check(Db.environments.has(&"forest_ruin"), "Forest Ruin is in the Db")
	var forest := Db.get_environment(&"forest_ruin")
	check_eq(forest.id, &"forest_ruin", "id")
	check_eq(forest.display_name, "Forest Ruin", "name")
	check(forest.description != "", "description")
	check_eq(forest.decor_id, &"forest", "forest decor")
	check(not forest.has_hazard(), "Forest Ruin has no hazard")
	check_eq(forest.sky_color, EnvironmentData.new().sky_color, "its look is the data class's defaults")
	check(Db.get_environment(&"nowhere") == null, "unknown id")
	check_eq(Db.environment_ids[0], &"forest_ruin", "roll order starts with the forest")
	check(Db.environment_or_default(&"nowhere") == forest, "an unknown id falls back to the default")
	check(Db.environment_or_default(&"forest_ruin") == forest, "a known id is itself")
	for id in Db.environment_ids:
		check(Db.environments.has(id), "every listed id is loaded (%s)" % id)
	check_eq(Db.environment_ids.size(), Db.environments.size(), "the list covers the dictionary")


# --- EventSpawner -----------------------------------------------------------------------------

func test_event_spawner_is_wired_into_the_run() -> void:
	_run_with_bots(1)
	check(main.event_spawner != null and is_instance_valid(main.event_spawner), "the run has an event spawner")
	check(main.event_spawner.get_parent() == main.wave_director, "a child of the director, like the GoblinSpawner")
	check(main.event_spawner.director == main.wave_director, "bound to it")
	check(main.wave_director.wave_started.is_connected(main.event_spawner._on_wave_started), "listens to wave_started")
	check(main.wave_director.wave_cleared.is_connected(main.event_spawner._on_wave_cleared), "listens to wave_cleared")
	check(main.event_spawner.announced.is_connected(main._on_announced), "announcements become HUD banners")
	check(main.goblin_spawner != null and main.goblin_spawner.get_parent() == main.wave_director, "the goblin spawner is still there")
	main.go_to_menu()
	check(main.event_spawner == null, "torn down with the run")


func test_event_waves_and_chance() -> void:
	for w in range(1, 4):
		check(not EventSpawner.is_eligible_wave(w), "wave %d: too early" % w)
	for w in [4, 5, 6, 7, 8, 9, 11, 12, 15, 19, 21, 24]:
		check(EventSpawner.is_eligible_wave(w), "wave %d is eligible" % w)
	for w in [10, 20, 25]:
		check(not EventSpawner.is_eligible_wave(w), "wave %d (boss / elite) is not" % w)
	check_eq(EventSpawner.chance_for(5), 0.3, "30% on an eligible wave")
	check_eq(EventSpawner.chance_for(3), 0.0, "none early")
	check_eq(EventSpawner.chance_for(10), 0.0, "none on a boss wave")
	RunState.event_override = EventSpawner.GOBLIN_CARAVAN
	check_eq(EventSpawner.chance_for(5), 1.0, "--event forces it")
	check_eq(EventSpawner.chance_for(10), 0.0, "even --event keeps boss waves clear")
	check_eq(EventSpawner.chance_for(20), 0.0, "and the elite wave")
	check_eq(EventSpawner.EVENT_IDS.size(), 3, "three events")
	for id in [EventSpawner.GUARDED_CHEST, EventSpawner.DEFEND_TOTEM, EventSpawner.GOBLIN_CARAVAN]:
		check(id in EventSpawner.EVENT_IDS, "%s is a known event" % id)


func test_event_roll_uses_its_own_rng() -> void:
	var spawner := EventSpawner.create(null)
	nodes.append(spawner)
	RunState.event_override = EventSpawner.GUARDED_CHEST
	var gameplay := RunState.rng.state
	var before := RunState.event_rng.state
	var id := spawner.roll_wave(5)
	check_eq(id, EventSpawner.GUARDED_CHEST, "the forced event")
	check_eq(spawner.event_id, id, "remembered")
	var dur := RunState.wave_duration(5)
	check(spawner.pending_time() >= 0.2 * dur - 0.0001 and spawner.pending_time() <= 0.4 * dur + 0.0001,
			"it starts at 20-40%% of the wave (%.2f of %.0f s)" % [spawner.pending_time(), dur])
	check_eq(RunState.rng.state, gameplay, "the gameplay rng did not move")
	check(RunState.event_rng.state != before, "the event rng did")
	# An ineligible wave draws nothing and clears the previous wave's event.
	before = RunState.event_rng.state
	check_eq(spawner.roll_wave(10), &"", "no event on a boss wave")
	check_eq(spawner.pending_time(), -1.0, "nothing pending")
	check_eq(RunState.event_rng.state, before, "no draw on an ineligible wave")
	check_eq(RunState.rng.state, gameplay, "and the gameplay rng still did not move")


func test_event_roll_draw_order_and_rate() -> void:
	var spawner := EventSpawner.create(null)
	nodes.append(spawner)
	var ref := RandomNumberGenerator.new()
	ref.state = RunState.event_rng.state
	var came := 0
	for i in 200:
		ref.state = RunState.event_rng.state
		var id := spawner.roll_wave(6)
		var hit := ref.randf() < EventSpawner.CHANCE
		check_eq(id != &"", hit, "the chance draw decides")
		if hit:
			came += 1
			var kind: StringName = EventSpawner.EVENT_IDS[ref.randi() % EventSpawner.EVENT_IDS.size()]
			check_eq(id, kind, "then the kind")
			check_near(spawner.pending_time(), ref.randf_range(0.2, 0.4) * RunState.wave_duration(6), 0.0001, "then the start time")
		check_eq(RunState.event_rng.state, ref.state, "exactly the documented draws")
	check(came > 30 and came < 90, "about 30%% of the waves (%d / 200)" % came)


func test_event_starts_at_its_time_and_counts() -> void:
	world = EFakes.make_world(tree)
	var director := WaveDirector.create(EFakes.arena_of(world))
	world.add_child(director)
	var spawner := ProbeSpawner.new()
	spawner.director = director
	director.add_child(spawner)
	RunState.event_override = EventSpawner.DEFEND_TOTEM
	director.start_wave(5)
	var t := spawner.pending_time()
	check(t > 0.0, "an event is coming")
	EFakes.step_all([director, spawner], t - 0.1)
	check(spawner.started.is_empty() and RunState.events_spawned == 0, "not yet")
	EFakes.step_all([director, spawner], 0.2)
	check_eq(spawner.started, [EventSpawner.DEFEND_TOTEM] as Array[StringName], "started once, at its time")
	check_eq(RunState.events_spawned, 1, "counted")
	check_eq(spawner.pending_time(), -1.0, "nothing pending")
	EFakes.step_all([director, spawner], 3.0)
	check_eq(spawner.started.size(), 1, "at most one per wave")
	spawner.end_wave()
	check_eq(spawner.ended, 1, "end_wave hook")


func test_the_base_event_spawner_spawns_nothing() -> void:
	world = EFakes.make_world(tree)
	var director := WaveDirector.create(EFakes.arena_of(world))
	world.add_child(director)
	var spawner := EventSpawner.create(director)
	director.add_child(spawner)
	var announced: Array[String] = []
	spawner.announced.connect(func(text: String, _c: Color) -> void: announced.append(text))
	RunState.event_override = EventSpawner.GUARDED_CHEST
	director.start_wave(5)
	check(spawner.pending_time() > 0.0, "the slot rolled")
	EFakes.step_all([director, spawner], 20.0)
	check_eq(RunState.events_spawned, 0, "no event exists yet: nothing spawned or counted")
	check(announced.is_empty(), "no banner")
	check(not spawner.start_event(EventSpawner.GUARDED_CHEST), "start_event reports false")


func test_wave_end_cancels_a_pending_event_and_frees_event_objects() -> void:
	world = EFakes.make_world(tree)
	var arena := EFakes.arena_of(world)
	var director := WaveDirector.create(arena)
	world.add_child(director)
	var spawner := ProbeSpawner.new()
	spawner.director = director
	director.add_child(spawner)
	RunState.event_override = EventSpawner.GOBLIN_CARAVAN
	director.start_wave(6)
	check(spawner.pending_time() > 0.0, "pending")
	var object := Node3D.new()
	object.add_to_group(EventSpawner.GROUP)
	arena.entities.add_child(object)
	director.time_left = 0.0
	director._physics_process(DT)  # the wave ends: stop(), then wave_cleared
	check(object.is_queued_for_deletion(), "stop() frees the event objects")
	check_eq(spawner.pending_time(), -1.0, "the clear forgets the pending event")
	check_eq(spawner.ended, 1, "and calls end_wave")
	EFakes.step_all([director, spawner], 30.0)
	check(spawner.started.is_empty(), "nothing starts after the wave")


# --- Intermission phases ----------------------------------------------------------------------

func _make_screen() -> void:
	world = MarketFakes.make_world(tree)
	RunState.shop = MarketFakes.FakeShop.new()
	screen = PhaseProbe.new()
	screen.name = "Intermission"
	screen._build()
	tree.root.add_child(screen)


func test_process_runs_the_shrine_frames_while_the_vote_is_open() -> void:
	_make_screen()
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	screen.hold_shrine = true
	RunState.pending_shrine = &"greed"
	screen.open(5, 0)
	check_eq(screen.phase, Intermission.Phase.SHRINE, "the held shrine vote is open")
	screen._process(DT)
	screen._process(DT)
	check_eq(screen.shrine_updates, 2, "two frames of the shrine phase")
	check_eq(screen.portal_updates, 0, "no portal frames")
	check_eq(screen.phase, Intermission.Phase.SHRINE, "the vote is still open")


func test_process_runs_the_portal_frames_while_the_vote_is_open() -> void:
	_make_screen()
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	screen.hold_portal = true
	RunState.portal_pending = true
	screen.open(5, 0)
	check_eq(screen.phase, Intermission.Phase.PORTAL, "the held portal vote is open")
	screen._process(DT)
	screen._process(DT)
	screen._process(DT)
	check_eq(screen.portal_updates, 3, "three frames of the portal phase")
	check_eq(screen.shrine_updates, 0, "no shrine frames")
	check_eq(screen.phase, Intermission.Phase.PORTAL, "the vote is still open")


func test_phase_order_and_chain() -> void:
	var P := Intermission.Phase
	check(P.CLOSED < P.LOOT and P.LOOT < P.SHRINE and P.SHRINE < P.LEVEL_UP and P.LEVEL_UP < P.PORTAL and P.PORTAL < P.MARKET,
			"LOOT, SHRINE, LEVEL_UP, PORTAL, MARKET")
	check_eq(Intermission.next_phase(P.CLOSED), P.LOOT, "closed -> loot")
	check_eq(Intermission.next_phase(P.LOOT), P.SHRINE, "loot -> shrine")
	check_eq(Intermission.next_phase(P.SHRINE), P.LEVEL_UP, "shrine -> level-up")
	check_eq(Intermission.next_phase(P.LEVEL_UP), P.PORTAL, "level-up -> portal")
	check_eq(Intermission.next_phase(P.PORTAL), P.MARKET, "portal -> market")
	check_eq(Intermission.next_phase(P.MARKET), P.MARKET, "the chain ends in the market")


func test_the_no_op_phases_are_skipped() -> void:
	_make_screen()
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	check(not screen.wants_shrine() and not screen.wants_portal(), "nothing pending")
	check(not screen.wants_phase(Intermission.Phase.SHRINE) and not screen.wants_phase(Intermission.Phase.PORTAL), "wants_phase says so")
	check(screen.wants_phase(Intermission.Phase.MARKET), "the market always runs")
	screen.open(5, 0)
	check_eq(screen.entered, [Intermission.Phase.MARKET] as Array[Intermission.Phase], "no loot, no level-ups: the market and nothing else")
	check_eq(screen.phase, Intermission.Phase.MARKET, "in the market")


func test_a_pending_shrine_passes_through_the_stub() -> void:
	_make_screen()
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	RunState.pending_shrine = &"greed"
	check(screen.wants_shrine(), "wanted")
	screen.open(5, 0)
	check_eq(screen.entered, [Intermission.Phase.SHRINE, Intermission.Phase.MARKET] as Array[Intermission.Phase],
			"the shrine phase, then (no level-ups, no portal) the market")
	check_eq(RunState.pending_shrine, &"", "the stub consumed the shrine")
	check_eq(screen.phase, Intermission.Phase.MARKET, "the break did not stall")


func test_a_pending_portal_passes_through_the_stub() -> void:
	_make_screen()
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	RunState.portal_pending = true
	check(screen.wants_portal(), "wanted")
	screen.open(5, 0)
	check_eq(screen.entered, [Intermission.Phase.PORTAL, Intermission.Phase.MARKET] as Array[Intermission.Phase],
			"the portal phase, then the market")
	check(not RunState.portal_pending, "the stub closed the portal")


func test_both_pending_run_in_order() -> void:
	_make_screen()
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	RunState.pending_shrine = &"haste"
	RunState.portal_pending = true
	screen.open(5, 0)
	check_eq(screen.entered, [Intermission.Phase.SHRINE, Intermission.Phase.PORTAL, Intermission.Phase.MARKET] as Array[Intermission.Phase],
			"SHRINE before PORTAL, then the market")


func test_pending_phases_without_a_hero_are_skipped() -> void:
	_make_screen()
	PlayerManager.join(UiFakes.HumanInput.new("pad:x"), Db.get_class_data(&"rogue"))  # a slot without a hero
	RunState.pending_shrine = &"haste"
	RunState.portal_pending = true
	check(not screen.wants_shrine() and not screen.wants_portal(), "nobody to vote")
	screen.open(5, 0)
	check_eq(screen.entered, [Intermission.Phase.MARKET] as Array[Intermission.Phase], "straight to the market")


func test_level_up_comes_between_the_shrine_and_the_portal() -> void:
	_make_screen()
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	RunState.level = 4
	RunState.pending_shrine = &"learning"
	RunState.portal_pending = true
	screen.open(5, 1)
	check_eq(screen.entered, [Intermission.Phase.SHRINE, Intermission.Phase.LEVEL_UP] as Array[Intermission.Phase],
			"the shrine, then the level-up cards (the portal waits for the picks)")
	check_eq(screen.phase, Intermission.Phase.LEVEL_UP, "waiting for the card pick")
	screen._on_level_up_finished()
	check_eq(screen.entered, [Intermission.Phase.SHRINE, Intermission.Phase.LEVEL_UP, Intermission.Phase.PORTAL,
			Intermission.Phase.MARKET] as Array[Intermission.Phase], "then the portal, then the market")


func test_a_player_leaving_the_shrine_vote_reaches_its_hook() -> void:
	_make_screen()
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	screen.hold_shrine = true
	RunState.pending_shrine = &"greed"
	screen.open(5, 0)
	check_eq(screen.phase, Intermission.Phase.SHRINE, "the shrine vote is held open")
	var slot := PlayerManager.get_slots()[0]
	screen._on_player_left(slot)
	check_eq(screen.shrine_left, [slot.index] as Array[int], "the SHRINE hook got the slot")
	check_eq(screen.portal_left, [] as Array[int], "not the PORTAL hook")


func test_a_player_leaving_the_portal_vote_reaches_its_hook() -> void:
	_make_screen()
	MarketFakes.human_with_hero(world, "pad:a", &"warrior")
	screen.hold_portal = true
	RunState.portal_pending = true
	screen.open(5, 0)
	check_eq(screen.phase, Intermission.Phase.PORTAL, "the portal vote is held open")
	var slot := PlayerManager.get_slots()[0]
	screen._on_player_left(slot)
	check_eq(screen.portal_left, [slot.index] as Array[int], "the PORTAL hook got the slot")
	check_eq(screen.shrine_left, [] as Array[int], "not the SHRINE hook")


func test_the_break_path_rolls_the_shrine_and_the_portal_before_the_intermission() -> void:
	var probe := BreakProbe.new()
	probe.options = LaunchOptions.new()
	main = probe  # freed by after_each
	probe.wave = 5
	probe._after_wave_end()
	check_eq(probe.calls, ["shrine", "portal", "open"] as Array[String], "the rolls come just before the break")
	probe.calls.clear()
	probe.wave = 25  # the normal mode's last wave ends the run: no break, no rolls
	probe._after_wave_end()
	check(probe.calls.is_empty(), "no break after the last wave")


# --- Leaderboard ------------------------------------------------------------------------------

func test_leaderboard_category_keys() -> void:
	check_eq(Leaderboard.category_key(&"normal", false, 2), "normal/standard/2", "normal")
	check_eq(Leaderboard.category_key(&"endless", true, 4), "endless/hardcore/4", "endless hardcore")
	check_eq(Leaderboard.category_key(&"normal", false, 9), "normal/standard/4", "party size clamped")
	check_eq(Leaderboard.category_key(&"normal", false, 0), "normal/standard/1", "party size clamped")
	check_eq(Leaderboard.category_key(&"weird", false, 1), "normal/standard/1", "an unknown mode is normal")
	check_eq(Leaderboard.mode_of_key("endless/hardcore/4"), &"endless", "mode of a key")


func test_leaderboard_ranking() -> void:
	var slow_win := Leaderboard.make_entry(25, 900.0, [&"warrior"], true, "d1")
	var fast_win := Leaderboard.make_entry(25, 700.0, [&"mage"], true, "d2")
	var far_loss := Leaderboard.make_entry(18, 500.0, [&"rogue"], false, "d3")
	var near_loss := Leaderboard.make_entry(9, 200.0, [&"rogue"], false, "d4")
	check(Leaderboard.better(fast_win, slow_win, &"normal"), "normal: the shorter victory first")
	check(Leaderboard.better(slow_win, far_loss, &"normal"), "normal: any victory above a defeat")
	check(Leaderboard.better(far_loss, near_loss, &"normal"), "normal: defeats by the wave reached")
	check(not Leaderboard.better(slow_win, slow_win, &"normal"), "a tie is not better")
	var deep := Leaderboard.make_entry(40, 1500.0, [&"mage"], false)
	var deeper_faster := Leaderboard.make_entry(40, 1400.0, [&"mage"], false)
	var shallow := Leaderboard.make_entry(30, 900.0, [&"mage"], false)
	check(Leaderboard.better(deep, shallow, &"endless"), "endless: the higher wave first")
	check(Leaderboard.better(deeper_faster, deep, &"endless"), "endless: then the shorter time")
	var e := Leaderboard.make_entry(7, 12.34, [&"warrior", &"mage"], false, "2026-01-01 10:00:00")
	check_eq(e["classes"], ["warrior", "mage"] as Array[String], "classes as strings")
	check_near(float(e["time"]), 12.3, 0.0001, "time to 0.1 s")
	check(Leaderboard.make_entry(1, 1.0, [], false)["date"] != "", "the date defaults to now")


func test_leaderboard_keeps_the_top_ten_per_category() -> void:
	var board := Leaderboard.create(TMP_BOARD)
	for i in 14:
		var rank := board.add_entry(Leaderboard.make_entry(10 + i, 100.0, [&"mage"], false, "d%d" % i), &"endless", false, 2)
		check_eq(rank, 0, "every entry is a new best (wave %d)" % (10 + i))
	var list := board.entries_for(&"endless", false, 2)
	check_eq(list.size(), Leaderboard.MAX_ENTRIES, "cut to ten")
	check_eq(int(list[0]["wave"]), 23, "best first")
	check_eq(int(list[9]["wave"]), 14, "the tenth")
	check_eq(board.add_entry(Leaderboard.make_entry(5, 1.0, [&"mage"], false), &"endless", false, 2), -1, "too weak for the board")
	check_eq(board.entries_for(&"endless", false, 2).size(), 10, "nothing changed")
	check_eq(board.rank_of(Leaderboard.make_entry(18, 1.0, [&"mage"], false), &"endless", false, 2), 5, "rank_of")
	check_eq(board.add_entry(Leaderboard.make_entry(18, 1.0, [&"mage"], false), &"endless", false, 2), 5, "inserted in the middle")
	check(board.entries_for(&"endless", false, 3).is_empty() and board.entries_for(&"endless", true, 2).is_empty()
			and board.entries_for(&"normal", false, 2).is_empty(), "other categories are separate")
	check_eq(board.best_for(&"endless", false, 3), {}, "no best in an empty category")
	check_eq(int(board.best_for(&"endless", false, 2)["wave"]), 23, "best_for")


func test_leaderboard_round_trip_on_a_temp_path() -> void:
	var board := Leaderboard.create(TMP_BOARD)
	check_eq(board.load_file(), OK, "a missing file is an empty board")
	check(board.categories.is_empty() and board.load_error == "", "empty and fine")
	board.add_entry(Leaderboard.make_entry(25, 812.4, [&"warrior", &"mage"], true, "2026-10-18 12:00:00"), &"normal", false, 2)
	board.add_entry(Leaderboard.make_entry(12, 400.0, [&"warrior", &"mage"], false, "2026-10-18 12:30:00"), &"normal", false, 2)
	board.add_entry(Leaderboard.make_entry(33, 1500.5, [&"rogue"], false, "2026-10-19 09:00:00"), &"endless", true, 1)
	check_eq(board.save_file(), OK, "saved")
	check(FileAccess.file_exists(TMP_BOARD), "the file exists")
	check(not FileAccess.file_exists(TMP_BOARD + ".tmp"), "no temporary file left behind")
	var again := Leaderboard.create(TMP_BOARD)
	check_eq(again.load_file(), OK, "loaded")
	check(not again.read_only and again.load_error == "", "no error")
	check_eq(again.categories.keys().size(), 2, "two categories")
	var normal := again.entries_for(&"normal", false, 2)
	check_eq(normal.size(), 2, "two normal entries")
	check_eq(normal[0], board.entries_for(&"normal", false, 2)[0], "the entry survives unchanged")
	check_eq(typeof(normal[0]["wave"]), TYPE_INT, "wave is an int again")
	check_eq(typeof(normal[0]["victory"]), TYPE_BOOL, "victory is a bool")
	check_eq(normal[0]["classes"], ["warrior", "mage"] as Array[String], "classes")
	check_eq(normal[0]["date"], "2026-10-18 12:00:00", "date")
	check_near(float(normal[0]["time"]), 812.4, 0.0001, "time")
	check(bool(normal[0]["victory"]) and not bool(normal[1]["victory"]), "the victory ranks first")
	var endless := again.best_for(&"endless", true, 1)
	check_eq(int(endless["wave"]), 33, "the endless entry")
	var text := FileAccess.get_file_as_string(TMP_BOARD)
	var raw: Variant = JSON.parse_string(text)
	check(raw is Dictionary and int(raw["version"]) == Leaderboard.FORMAT_VERSION, "the file carries its version")


func test_leaderboard_newer_version_is_never_overwritten() -> void:
	var file := FileAccess.open(TMP_BOARD, FileAccess.WRITE)
	var future := '{"version": 99, "categories": {"normal/standard/1": [{"wave": 3}]}, "extra": true}'
	file.store_string(future)
	file.close()
	var board := Leaderboard.create(TMP_BOARD)
	check_eq(board.load_file(), OK, "a newer file loads without an error")
	check(board.read_only, "but read-only")
	check_eq(board.load_error, "newer version", "reason")
	check(board.categories.is_empty(), "its entries are not interpreted")
	board.add_entry(Leaderboard.make_entry(5, 1.0, [&"mage"], false), &"normal", false, 1)
	check_eq(board.save_file(), ERR_FILE_NO_PERMISSION, "saving refuses")
	check_eq(FileAccess.get_file_as_string(TMP_BOARD), future, "the file is untouched")
	Leaderboard.writes_enabled = true
	Leaderboard.path_override = TMP_BOARD
	check_eq(Leaderboard.record_run(Leaderboard.make_entry(5, 1.0, [&"mage"], false), &"normal", false, 1), -1, "record_run writes nothing")
	check_eq(FileAccess.get_file_as_string(TMP_BOARD), future, "still untouched")


func test_leaderboard_older_or_odd_files() -> void:
	# The entries are stored worst first: the sanitize sort must put the victory on top.
	var file := FileAccess.open(TMP_BOARD, FileAccess.WRITE)
	file.store_string('{"version": 1, "categories": {"normal/standard/2": [{"wave": 2}, "junk", {"wave": 20.0, "time": 99.94, "classes": ["mage"], "victory": true}], "bad": 5}}')
	file.close()
	var board := Leaderboard.create(TMP_BOARD)
	check_eq(board.load_file(), OK, "loads")
	var list := board.entries_for(&"normal", false, 2)
	check_eq(list.size(), 2, "the junk entry is dropped")
	check_eq(typeof(list[0]["wave"]), TYPE_INT, "types are restored")
	check(bool(list[0]["victory"]), "best first (the victory), though it was stored last")
	check_eq(list[0]["wave"], 20, "the victory is the wave-20 run")
	check_eq(list[1]["wave"], 2, "then the wave-2 run")
	check_eq(list[1]["date"], "", "a missing date stays empty (no invented one)")
	check(not board.categories.has("bad"), "a category that is no list is dropped")


func test_leaderboard_corrupt_file_is_set_aside() -> void:
	var file := FileAccess.open(TMP_BOARD, FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	var board := Leaderboard.create(TMP_BOARD)
	check_eq(board.load_file(), ERR_PARSE_ERROR, "reported")
	check_eq(board.load_error, "corrupt", "reason")
	check(board.categories.is_empty() and not board.read_only, "an empty, writable board")
	check(FileAccess.file_exists(TMP_BOARD + ".corrupt"), "the broken file is kept as .corrupt")
	check(not FileAccess.file_exists(TMP_BOARD), "and the path is free")
	board.add_entry(Leaderboard.make_entry(5, 1.0, [&"mage"], false), &"normal", false, 1)
	check_eq(board.save_file(), OK, "the next save works")
	var again := Leaderboard.create(TMP_BOARD)
	again.load_file()
	check_eq(again.entries_for(&"normal", false, 1).size(), 1, "and reads back")


func test_leaderboard_record_run_respects_the_write_gate() -> void:
	Leaderboard.path_override = TMP_BOARD
	var entry := Leaderboard.make_entry(25, 700.0, [&"warrior"], true)
	Leaderboard.writes_enabled = false
	check_eq(Leaderboard.record_run(entry, &"normal", false, 1), -1, "switched off: nothing recorded")
	check(not FileAccess.file_exists(TMP_BOARD), "and no file written")
	Leaderboard.writes_enabled = true
	check_eq(Leaderboard.default_path(), TMP_BOARD, "path_override replaces the default path")
	check_eq(Leaderboard.record_run(entry, &"normal", false, 1), 0, "the first entry is the best")
	check_eq(Leaderboard.record_run(Leaderboard.make_entry(25, 650.0, [&"warrior"], true), &"normal", false, 1), 0, "a faster win is the new best")
	check_eq(Leaderboard.record_run(Leaderboard.make_entry(25, 800.0, [&"warrior"], true), &"normal", false, 1), 2, "a slower one is third")
	var board := Leaderboard.create()
	board.load_file()
	check_eq(board.entries_for(&"normal", false, 1).size(), 3, "all three are in the file")
	Leaderboard.path_override = ""
	check_eq(Leaderboard.default_path(), Leaderboard.DEFAULT_PATH, "the real path without the override")


func test_the_test_runner_switches_leaderboard_writing_off() -> void:
	check(not _writes_before, "tests/run_tests.gd disables Leaderboard.writes_enabled")


func test_main_writes_the_leaderboard_only_for_real_runs() -> void:
	_make_main(LaunchOptions.new())
	check(main.writes_leaderboard(), "a plain run")
	var smoke := LaunchOptions.new()
	smoke.smoke = true
	main.options = smoke
	check(not main.writes_leaderboard(), "not in smoke")
	var demo := LaunchOptions.new()
	demo.demo = true
	main.options = demo
	check(not main.writes_leaderboard(), "not in demo")
	var view := LaunchOptions.new()
	view.view = "game_over"
	main.options = view
	check(not main.writes_leaderboard(), "not with a forced view")
	var shot := LaunchOptions.new()
	shot.screenshot_path = "/tmp/x.png"
	main.options = shot
	check(not main.writes_leaderboard(), "not for a screenshot")


# --- Launch flags -----------------------------------------------------------------------------

func test_launch_flags_default_to_off() -> void:
	var o := LaunchOptions.parse(PackedStringArray())
	check_eq(o.mode, RunState.MODE_NORMAL, "normal")
	check(not o.hardcore, "no hardcore")
	check_eq(o.environment, &"", "environment rolled")
	check_eq(o.event, &"", "events roll")
	check_eq(o.shrine_chance, -1.0, "normal shrine chance")
	check(not o.dungeon, "no forced dungeon")
	check(o.unknown.is_empty(), "nothing unknown")


func test_launch_flags_parse() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--mode=endless", "--hardcore", "--env=forest_ruin",
			"--event=guarded_chest", "--shrine-chance=0.25", "--dungeon=1"]))
	check_eq(o.mode, RunState.MODE_ENDLESS, "mode")
	check(o.hardcore, "hardcore")
	check_eq(o.environment, &"forest_ruin", "environment")
	check_eq(o.event, EventSpawner.GUARDED_CHEST, "event")
	check_eq(o.shrine_chance, 0.25, "shrine chance")
	check(o.dungeon, "dungeon")
	check(o.unknown.is_empty(), "all understood")
	o = LaunchOptions.parse(PackedStringArray(["--dungeon", "--hardcore=1"]))
	check(o.dungeon and o.hardcore, "bare / =1 switch them on")
	o = LaunchOptions.parse(PackedStringArray(["--dungeon=0", "--hardcore=0"]))
	check(not o.dungeon and not o.hardcore, "=0 switches them off")
	o = LaunchOptions.parse(PackedStringArray(["--shrine-chance=7"]))
	check_eq(o.shrine_chance, 1.0, "clamped to 1")
	o = LaunchOptions.parse(PackedStringArray(["--shrine-chance=0"]))
	check_eq(o.shrine_chance, 0.0, "0 = never (not off)")


func test_launch_flags_reject_bad_values() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--mode=turbo", "--env=nowhere", "--event=party"]))
	check_eq(o.unknown, ["--mode=turbo", "--env=nowhere", "--event=party"] as Array[String], "reported once by Main")
	check_eq(o.mode, RunState.MODE_NORMAL, "mode unchanged")
	check_eq(o.environment, &"", "environment unchanged")
	check_eq(o.event, &"", "event unchanged")


func test_main_applies_the_flags_and_resets_them_per_run() -> void:
	var opts := LaunchOptions.parse(PackedStringArray(["--mode=endless", "--hardcore", "--env=forest_ruin",
			"--event=defend_totem", "--shrine-chance=0.5", "--dungeon"]))
	_run_with_bots(1, opts)
	check_eq(RunState.mode, RunState.MODE_ENDLESS, "RunState.mode")
	check(RunState.hardcore, "RunState.hardcore")
	check_eq(RunState.environment, &"forest_ruin", "RunState.environment")
	check_eq(RunState.event_override, EventSpawner.DEFEND_TOTEM, "event override")
	check_eq(RunState.shrine_chance_override, 0.5, "shrine chance override")
	check(RunState.dungeon_forced, "dungeon flag")
	check(main.arena.environment == Db.get_environment(&"forest_ruin"), "the arena was built from the environment")
	# The next run without flags: everything is back to the defaults.
	RunState.start_run(1, 1)
	check(RunState.mode == RunState.MODE_NORMAL and not RunState.hardcore, "mode reset")
	check(RunState.event_override == &"" and RunState.shrine_chance_override < 0.0 and not RunState.dungeon_forced, "overrides reset")


func test_configure_run_changes_the_next_run() -> void:
	_make_main(LaunchOptions.new())
	main.configure_run(RunState.MODE_ENDLESS, true)
	PlayerManager.add_bot(&"warrior", 1)
	main.start_run()
	check_eq(RunState.mode, RunState.MODE_ENDLESS, "endless")
	check(RunState.hardcore, "hardcore")
	main.configure_run(&"bogus", false)
	check_eq(main.options.mode, RunState.MODE_NORMAL, "an unknown mode is normal")
	main.start_run()
	check(RunState.mode == RunState.MODE_NORMAL and not RunState.hardcore, "the next run is a normal one")


func test_unknown_forced_environment_falls_back_to_the_default() -> void:
	var opts := LaunchOptions.new()
	opts.environment = &"not_there"  # (parse would have refused it; a hand-built option must not crash)
	_run_with_bots(1, opts)
	check_eq(RunState.environment, RunState.DEFAULT_ENVIRONMENT, "default environment")
	check(main.arena.environment == Db.get_environment(&"forest_ruin"), "the forest")


# --- SMOKE_RESULT -----------------------------------------------------------------------------

func test_smoke_result_has_the_m6b_keys() -> void:
	_run_with_bots(1)
	var data := main.smoke_result("completed")
	check_eq(data.get("mode"), "normal", "mode")
	check_eq(data.get("hardcore"), false, "hardcore")
	check_eq(data.get("environment"), "forest_ruin", "environment")
	for key in ["events_spawned", "events_completed", "shrines_offered", "shrines_accepted",
			"dungeons_entered", "dungeons_completed", "dungeons_failed"]:
		check(data.has(key), "SMOKE_RESULT has %s" % key)
		check_eq(data.get(key, -1), 0, "%s starts at 0" % key)
	RunState.events_spawned = 3
	RunState.events_completed = 2
	RunState.shrines_offered = 4
	RunState.shrines_accepted = 1
	RunState.dungeons_entered = 2
	RunState.dungeons_completed = 1
	RunState.dungeons_failed = 1
	data = main.smoke_result("completed")
	check_eq(data["events_spawned"], 3, "events_spawned")
	check_eq(data["events_completed"], 2, "events_completed")
	check_eq(data["shrines_offered"], 4, "shrines_offered")
	check_eq(data["shrines_accepted"], 1, "shrines_accepted")
	check_eq(data["dungeons_entered"], 2, "dungeons_entered")
	check_eq(data["dungeons_completed"], 1, "dungeons_completed")
	check_eq(data["dungeons_failed"], 1, "dungeons_failed")
	check(JSON.parse_string(JSON.stringify(data)) is Dictionary, "the result is JSON")


func test_smoke_result_reports_the_run_settings() -> void:
	var opts := LaunchOptions.new()
	opts.mode = RunState.MODE_ENDLESS
	opts.hardcore = true
	_run_with_bots(1, opts)
	var data := main.smoke_result("completed")
	check_eq(data["mode"], "endless", "mode")
	check_eq(data["hardcore"], true, "hardcore")
