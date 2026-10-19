extends TestCase
## M6b integration: the feature packages (modes, environments, events, shrines, the Dungeon, the leaderboard) were
## built apart; these tests pin what they do TOGETHER – hardcore + the dungeon (no Spirit Healer anywhere), the
## endless mode past wave 25 with shrines / events / the portal, the environment hazard inside the dungeon,
## shrine effects that live through a dungeon, the leaderboard that smoke runs never write, and the Enemy's
## open-field cache that the dungeon's small room must not poison.

const UiFakes := preload("res://tests/ui_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0
const SEED := 4242
# One temp board per test process: worktrees share user://, so parallel runs must not share a file.
var TMP_BOARD := "user://m6b_integration_lb_%d.json" % OS.get_process_id()

var main: Main
var world: Node3D
var nodes: Array[Node] = []
var _writes_before := true
var _path_before := ""
var _roll_screen_before := false


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, SEED)
	tree.paused = false
	_writes_before = Leaderboard.writes_enabled
	_path_before = Leaderboard.path_override
	_roll_screen_before = EnvironmentRollScreen.enabled


func after_each() -> void:
	Leaderboard.writes_enabled = _writes_before
	Leaderboard.path_override = _path_before
	EnvironmentRollScreen.enabled = _roll_screen_before
	for path in [TMP_BOARD, TMP_BOARD + ".tmp", TMP_BOARD + ".corrupt"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
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

func _options(p_mode: StringName = RunState.MODE_NORMAL, p_hardcore := false, p_env: StringName = &"") -> LaunchOptions:
	var opts := LaunchOptions.new()
	opts.seed_value = SEED
	opts.mode = p_mode
	opts.hardcore = p_hardcore
	opts.environment = p_env
	return opts


func _run_with_bots(count: int, opts: LaunchOptions = null) -> void:
	main = Main.create(opts if opts != null else _options())
	tree.root.add_child(main)
	for i in count:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)
	main.start_run()


## Wave [param p_wave] starts, runs out and the break opens (the real path: the director's clock, the wave-end
## delay, Main._after_wave_end).
func _play_wave(p_wave: int) -> void:
	main.start_wave(p_wave)
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	main._physics_process(Main.WAVE_END_DELAY + 0.01)


## Lets the bots vote through the break's phases until [param phase] is reached (or the screen closed).
func _until_phase(phase: Intermission.Phase) -> void:
	for i in 800:
		if main.intermission.phase == phase or main.state != Main.State.INTERMISSION:
			return
		for slot in PlayerManager.get_slots():
			slot.input.poll(0.1)
		main.intermission._process(0.1)
		if main.intermission.phase == Intermission.Phase.LOOT:
			main.intermission.loot_screen._process(0.1)  # (the loot roll runs on its own frames)


## The bots' portal vote passes and Main enters the dungeon (the signal is deferred in the real game).
func _enter_dungeon() -> void:
	_until_phase(Intermission.Phase.PORTAL)
	check_eq(main.intermission.phase, Intermission.Phase.PORTAL, "the break is at the portal vote")
	for i in 6:
		for slot in PlayerManager.get_slots():
			slot.input.poll(0.1)
		main.intermission._process(0.1)
	main.enter_dungeon()
	check(main.dungeon != null, "the party is in the dungeon")


func _kill_all(by: Player = null) -> void:
	for node in tree.get_nodes_in_group(&"enemies"):
		var e := node as Enemy
		if e != null and not e.is_dead():
			e.kill(by)


## Runs the dungeon to its end, killing every enemy at each step; [param tick] runs besides (other nodes).
func _play_dungeon(tick: Callable = Callable()) -> void:
	var guard := 0
	while main.dungeon != null and guard < 3000:
		main.dungeon._physics_process(0.25)
		if tick.is_valid():
			tick.call(0.25)
		if main.dungeon != null:
			_kill_all(main.players[0])
		guard += 1


func _down(p: Player) -> void:
	for i in 60:
		if p.downed:
			return
		p.invulnerable_left = 0.0
		p.take_damage(100000.0, CombatMath.KIND_MELEE, null)


## Nodes of [param group] that stay: one freed with queue_free() is gone for the game (the next frame deletes it).
func _standing_in(group: StringName) -> int:
	var count := 0
	for node in tree.get_nodes_in_group(group):
		if not node.is_queued_for_deletion():
			count += 1
	return count


func _healers_in_the_arena() -> int:
	return main.arena.find_children("*", "SpiritHealer", true, false).size()


func _hint_of(hero: Player) -> String:
	var frame := UnitFrame.create(0)
	tree.root.add_child(frame)
	nodes.append(frame)
	frame.bind(hero)
	frame._process(0.016)
	var text := frame.hint_label.text
	frame.unbind()
	return text


# --- Hardcore + the dungeon --------------------------------------------------------------------------------

func test_hardcore_and_the_dungeon_have_no_spirit_healer_anywhere() -> void:
	_run_with_bots(2, _options(RunState.MODE_NORMAL, true))
	check(RunState.hardcore, "a hardcore run")
	check(main.arena.spirit_healer == null and _healers_in_the_arena() == 0, "the clearing has none")
	_play_wave(6)
	_enter_dungeon()
	check(main.arena.in_dungeon_layout, "inside the dungeon room")
	check(main.arena.spirit_healer == null and _healers_in_the_arena() == 0, "none in the dungeon")
	_play_dungeon()
	check(main.dungeon == null and not main.arena.in_dungeon_layout, "the dungeon is over, the clearing is back")
	check(main.arena.spirit_healer == null, "and the clearing is still without a Grave Tender (hardcore)")
	check_eq(_healers_in_the_arena(), 0, "no Grave Tender node came back with it")
	check_eq(RunState.dungeons_completed, 1, "the dungeon was won")


func test_a_downed_hero_is_told_a_teammate_revives_them_in_hardcore_and_the_dungeon() -> void:
	_run_with_bots(2, _options(RunState.MODE_NORMAL, true))
	var hero := main.players[0]
	_down(hero)
	check_eq(_hint_of(hero), UnitFrame.TEAMMATE_HINT, "hardcore clearing")
	hero.revive(0.5)
	_play_wave(6)
	_enter_dungeon()
	main.dungeon._physics_process(Dungeon.INTRO_TIME + 0.02)
	_down(hero)
	check_eq(_hint_of(hero), UnitFrame.TEAMMATE_HINT, "hardcore dungeon")
	_play_dungeon()
	hero = main.players[0]
	if hero.is_alive():
		_down(hero)
	check_eq(_hint_of(hero), UnitFrame.TEAMMATE_HINT, "and back in the hardcore clearing")


func test_a_normal_run_keeps_its_spirit_healer_through_a_dungeon() -> void:
	_run_with_bots(2)
	check(main.arena.spirit_healer != null, "the clearing has it")
	_play_wave(6)
	_enter_dungeon()
	check(main.arena.spirit_healer == null, "off while the party is in the dungeon")
	_play_dungeon()
	check(main.arena.spirit_healer != null and main.arena.spirit_healer.is_inside_tree(), "back in the clearing")
	var hero := main.players[0]
	_down(hero)
	check("Grave Tender" in _hint_of(hero), "the ghost is sent to it again")


func test_a_lost_hardcore_dungeon_leaves_the_clearing_as_it_was() -> void:
	_run_with_bots(2, _options(RunState.MODE_NORMAL, true))
	_play_wave(6)
	_enter_dungeon()
	main.dungeon._physics_process(Dungeon.INTRO_TIME + 0.02)
	for p in main.players:
		_down(p)
	var guard := 0
	while main.dungeon != null and guard < 400:
		main.dungeon._physics_process(0.25)
		guard += 1
	check(main.dungeon == null, "every hero down ends the dungeon")
	check_eq(RunState.dungeons_failed, 1, "a failed dungeon")
	check(main.arena.spirit_healer == null and _healers_in_the_arena() == 0, "still no Grave Tender")
	check(not main.arena.in_dungeon_layout, "the clearing is back")
	check_eq(main.state, Main.State.INTERMISSION, "the break goes on (the run is not over)")


# --- The endless mode past wave 25 -------------------------------------------------------------------------

func test_the_portal_follows_waves_6_9_12_and_15_only_in_the_endless_mode_too() -> void:
	_run_with_bots(1, _options(RunState.MODE_ENDLESS))
	for w in range(1, 120):
		main.wave = w
		main._roll_portal()
		check_eq(RunState.portal_pending, w in [6, 9, 12, 15], "portal after wave %d" % w)
		check(not RunState.portal_forced, "never forced by itself (wave %d)" % w)


func test_an_endless_break_past_wave_25_has_a_market_and_no_portal() -> void:
	_run_with_bots(2, _options(RunState.MODE_ENDLESS))
	for w in [26, 27, 30, 33, 40]:
		_play_wave(w)
		check_eq(main.state, Main.State.INTERMISSION, "the break after wave %d" % w)
		check(not RunState.portal_pending, "no portal after wave %d" % w)
		_until_phase(Intermission.Phase.MARKET)
		check_eq(main.intermission.phase, Intermission.Phase.MARKET, "straight to the market after wave %d" % w)
		main._on_intermission_continue()


func test_the_forced_dungeon_flag_opens_one_portal_in_the_endless_mode_too() -> void:
	var opts := _options(RunState.MODE_ENDLESS)
	opts.dungeon = true
	opts.start_wave = 26
	_run_with_bots(2, opts)
	check(RunState.dungeon_forced, "--dungeon=1")
	_play_wave(26)
	check(RunState.portal_pending and RunState.portal_forced, "the debug portal after wave 26")
	_enter_dungeon()
	check_eq(main.dungeon.wave, 26, "scaled to wave 26")
	_play_dungeon()
	check_eq(RunState.dungeons_completed, 1, "won")
	main._on_intermission_continue()
	_play_wave(27)
	check(not RunState.portal_pending, "spent: not again after wave 27")


func test_endless_waves_past_25_roll_shrines_and_run_them() -> void:
	var opts := _options(RunState.MODE_ENDLESS)
	opts.shrine_chance = 1.0
	_run_with_bots(2, opts)
	_play_wave(26)
	check(RunState.pending_shrine != &"", "a shrine waits after wave 26")
	check_eq(main.intermission.phase, Intermission.Phase.SHRINE, "the break opens with the shrine vote")
	var id := RunState.pending_shrine
	_until_phase(Intermission.Phase.MARKET)
	check_eq(main.intermission.phase, Intermission.Phase.MARKET, "the bots decided, the market follows")
	check_eq(RunState.shrines_offered, 1, "offered")
	if RunState.has_shrine_effect(id):
		main._on_intermission_continue()
		check_eq(main.wave, 27, "wave 27")
		check(RunState.shrine_effects_live, "the effects are live in wave 27")
		check(RunState.shrine_waves_left(id) >= 1, "with waves left")
		check(not main.hud.shown_shrines().is_empty(), "the HUD shows the icon")


func test_a_timed_shrine_runs_over_the_waves_in_the_endless_mode() -> void:
	_run_with_bots(1, _options(RunState.MODE_ENDLESS))
	_play_wave(28)
	Shrines.accept(Db.get_shrine(&"learning"), PlayerManager.get_slots())
	check_eq(RunState.shrine_waves_left(&"learning"), 3, "three waves")
	main._on_intermission_continue()
	check_eq(main.wave, 29, "wave 29")
	check(RunState.shrine_effects_live, "live")
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	main._physics_process(Main.WAVE_END_DELAY + 0.01)
	check_eq(RunState.shrine_waves_left(&"learning"), 2, "wave 29 counted against it")
	check(not RunState.shrine_effects_live, "not live in the break")


func test_events_never_roll_on_boss_or_elite_rule_waves_in_the_endless_mode() -> void:
	RunState.start_run(1, SEED, RunState.MODE_ENDLESS)
	var spawner := EventSpawner.create(null)
	nodes.append(spawner)
	RunState.event_override = EventSpawner.GUARDED_CHEST
	var eligible := 0
	for w in range(1, 121):
		var special := RunState.is_boss_wave(w) or RunState.is_elite_wave(w)
		var chance := EventSpawner.chance_for(w)
		if special or w < EventSpawner.FIRST_WAVE:
			check_eq(chance, 0.0, "no event on wave %d" % w)
			check_eq(spawner.roll_wave(w), &"", "nothing rolled on wave %d" % w)
		else:
			eligible += 1
			check_eq(chance, 1.0, "a forced event is certain on wave %d" % w)
			check_eq(spawner.roll_wave(w), EventSpawner.GUARDED_CHEST, "rolled on wave %d" % w)
	RunState.event_override = &""
	check(eligible > 80, "most waves past the early ones are eligible (%d)" % eligible)
	for w in [30, 35, 40, 45, 33, 43, 53, 63]:
		check(RunState.is_boss_wave(w) or RunState.is_elite_wave(w), "wave %d is a special wave of the endless mode" % w)
		check_eq(EventSpawner.chance_for(w), 0.0, "so no event on wave %d" % w)
	for w in [26, 27, 28, 29, 31, 32, 34, 36]:
		check(EventSpawner.chance_for(w) > 0.0, "an ordinary endless wave %d may carry an event" % w)
	spawner.roll_wave(1)  # (leave nothing pending)


func test_the_event_of_a_wave_is_gone_before_the_dungeon() -> void:
	_run_with_bots(2)
	RunState.event_override = EventSpawner.GUARDED_CHEST
	main.start_wave(6)
	check(main.event_spawner.start_event(EventSpawner.GUARDED_CHEST), "the chest is up")
	check(_standing_in(EventSpawner.GROUP) > 0, "an event object stands in the arena")
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	main._physics_process(Main.WAVE_END_DELAY + 0.01)
	RunState.event_override = &""
	_enter_dungeon()
	check_eq(_standing_in(EventSpawner.GROUP), 0, "no event object follows the party into the dungeon")


# --- The environment hazard and the dungeon -------------------------------------------------------------------

func test_the_environment_hazard_is_off_inside_the_dungeon() -> void:
	for env_id in [&"cemetery", &"swamp", &"volcano", &"ice_cave"]:
		_run_with_bots(2, _options(RunState.MODE_NORMAL, false, env_id))
		var hazards := main.environment_hazards
		check(hazards.has_hazard(), "%s has a hazard" % env_id)
		main.start_wave(6)
		for i in 600:
			hazards._physics_process(DT)
		var laid := int(hazards.stats()["laid"])
		check(laid > 0, "%s: the hazard works in a wave (%d laid)" % [env_id, laid])
		main.wave_director.time_left = 0.0
		main.wave_director._physics_process(DT)
		main._physics_process(Main.WAVE_END_DELAY + 0.01)
		check_eq(_standing_in(&"enemy_hazards"), 0, "%s: nothing left on the ground at the wave end" % env_id)
		_enter_dungeon()
		var tick := func(delta: float) -> void:
			hazards._physics_process(delta)
			hazards._physics_process(delta)
		_play_dungeon(tick)
		check_eq(int(hazards.stats()["laid"]), laid, "%s: not one hazard was laid in the dungeon" % env_id)
		check_eq(_standing_in(&"enemy_hazards"), 0, "%s: none stands in it" % env_id)
		check_eq(RunState.dungeons_completed, 1, "%s: the dungeon was won" % env_id)
		main.free()
		main = null
		UiFakes.reset_players()
		RunState.start_run(1, SEED)


func test_the_dungeon_room_has_no_lava_vents_to_mistake_for_hazards() -> void:
	var clearing := Rect2(-Arena.SIZE / 2.0, Arena.SIZE)
	var room := Rect2(-Arena.DUNGEON_SIZE / 2.0, Arena.DUNGEON_SIZE)
	check_eq(ArenaThemes.vents_in(clearing).size(), EnvironmentHazards.LAVA_VENT_POINTS.size(), "all six vents stand in the clearing")
	check_eq(ArenaThemes.vents_in(room).size(), 0, "none of them in the smaller dungeon room")


# --- Shrines and the dungeon --------------------------------------------------------------------------------

func test_shrine_effects_survive_a_dungeon() -> void:
	_run_with_bots(2)
	RunState.add_shrine_effect(&"learning", 3)
	RunState.add_shrine_effect(&"blood", 3)
	var hero := main.players[0]
	var base_hp := hero.max_hp()
	main.start_wave(6)
	check(RunState.shrine_effects_live, "live in wave 6")
	check_near(hero.max_hp(), base_hp * 0.8, 0.5, "Blood's -20% max HP in the wave")
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	main._physics_process(Main.WAVE_END_DELAY + 0.01)
	check_eq(RunState.shrine_waves_left(&"learning"), 2, "wave 6 counted against Learning")
	check_eq(RunState.shrine_waves_left(&"blood"), 2, "and Blood")
	_enter_dungeon()
	check(not RunState.shrine_effects_live, "not live in the dungeon")
	check_eq(Shrines.enemy_hp_mult(), 1.0, "its enemies are plain")
	check_eq(Shrines.xp_mult(), 1.0, "its XP is plain")
	check_near(hero.max_hp(), base_hp, 0.5, "the heroes carry no shrine effect in it")
	_play_dungeon()
	check_eq(RunState.shrine_waves_left(&"learning"), 2, "the dungeon did not count as a wave (Learning)")
	check_eq(RunState.shrine_waves_left(&"blood"), 2, "nor for Blood")
	check_eq(RunState.shrine_effects.size(), 2, "both still run")
	check(not main.hud.shown_shrines().is_empty(), "the HUD still shows them")
	main._on_intermission_continue()
	check_eq(main.wave, 7, "wave 7")
	check(RunState.shrine_effects_live, "live again")
	check_near(hero.max_hp(), base_hp * 0.8, 0.5, "Blood is back on the heroes")
	check_near(Shrines.xp_mult(), 1.0 + Db.get_shrine(&"learning").xp_pct / 100.0, 0.0001, "and Learning pays out")
	var banner := Shrines.banner_lines()
	check_eq(banner.size(), 2, "the banner lists both")


func test_the_dungeon_is_not_a_wave_for_the_instant_shrines_purse() -> void:
	_run_with_bots(2)
	RunState.gold = 400
	_play_wave(6)
	_enter_dungeon()
	_play_dungeon()
	check(RunState.gold >= 400, "a won dungeon never takes gold")
	check_eq(RunState.dungeons_completed, 1, "won")


# --- The leaderboard and smoke runs --------------------------------------------------------------------------

func test_a_smoke_run_through_a_dungeon_and_an_endless_quit_never_writes_the_players_board() -> void:
	Leaderboard.writes_enabled = true
	Leaderboard.path_override = TMP_BOARD
	var opts := _options(RunState.MODE_ENDLESS, true)
	opts.start_wave = 6
	_run_with_bots(2, opts)
	main.options.smoke = true  # (set after the start: a smoke Main would boot into its own run)
	check(not main.writes_leaderboard(), "a smoke run does not write")
	_play_wave(6)
	_enter_dungeon()
	_play_dungeon()
	main.quit_to_menu()
	check(not FileAccess.file_exists(TMP_BOARD), "the abandoned endless run left no file")
	check(not FileAccess.file_exists(TMP_BOARD + ".tmp"), "not even a temp file")
	_run_with_bots(2, _options(RunState.MODE_ENDLESS, true))
	main.options.smoke = true
	main.end_run(false)
	check(not FileAccess.file_exists(TMP_BOARD), "a lost smoke run writes nothing either")


# --- The Enemy's open-field cache ---------------------------------------------------------------------------

## An arena of any playable size for the cache test (the test arena has the clearing's bounds only).
class SizedArena extends EFakes.TestArena:
	func get_bounds() -> Rect2:
		return Rect2(-play_size / 2.0, play_size)


## A test world whose arena has the playable size [param p_size] (instead of the fake's fixed clearing).
func _sized_world(p_size: Vector2) -> SizedArena:
	world = EFakes.make_world(tree)
	var fake := world.get_node(^"TestArena")
	world.remove_child(fake)
	fake.free()
	var arena := SizedArena.new()
	arena.play_size = p_size
	world.add_child(arena)
	return arena


func test_the_open_field_follows_the_arena_inside_one_physics_frame() -> void:
	var arena := _sized_world(Arena.SIZE)
	EFakes.spawn_player(world, Vector3(10.0, 0.0, 0.0))
	var enemy := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3(-5.0, 0.0, 0.0))
	enemy._physics_process(DT)
	check(Enemy._open_ok, "the clearing is an open field")
	check_near(Enemy._open_max_x, Arena.SIZE.x * 0.5, 0.001, "measured on the clearing")
	# The dungeon layout swaps the arena's size within the same physics frame (Main.enter_dungeon).
	arena.play_size = Arena.DUNGEON_SIZE
	enemy._physics_process(DT)
	check_near(Enemy._open_max_x, Arena.DUNGEON_SIZE.x * 0.5, 0.001, "measured again on the dungeon room")
	arena.play_size = Arena.SIZE
	enemy._physics_process(DT)
	check_near(Enemy._open_max_x, Arena.SIZE.x * 0.5, 0.001, "and on the clearing again")


func test_a_new_arena_in_the_same_physics_frame_gets_its_own_open_field() -> void:
	var first := _sized_world(Arena.DUNGEON_SIZE)
	var hero := EFakes.spawn_player(world, Vector3(10.0, 0.0, 0.0))
	var enemy := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3(-5.0, 0.0, 0.0))
	enemy._physics_process(DT)
	check_near(Enemy._open_max_x, Arena.DUNGEON_SIZE.x * 0.5, 0.001, "the first arena is the small room")
	enemy.reparent(world, false)
	hero.reparent(world, false)
	world.remove_child(first)
	first.free()
	var second := SizedArena.new()
	second.play_size = Arena.SIZE
	world.add_child(second)
	enemy.reparent(second.entities, false)
	hero.reparent(second.entities, false)
	enemy._physics_process(DT)
	check_near(Enemy._open_max_x, Arena.SIZE.x * 0.5, 0.001, "the second one is measured, not the first one's leftovers")


func test_invalidating_the_player_cache_forgets_the_open_field_too() -> void:
	Enemy._open_frame = Engine.get_physics_frames()
	Enemy.invalidate_player_cache()
	check_eq(Enemy._open_frame, -1, "the next move measures again")


# --- The launch flags and the HUD -----------------------------------------------------------------------------

func test_every_m6b_flag_parses_together_in_any_order() -> void:
	var args := PackedStringArray(["--smoke", "--waves=8", "--start-wave=24", "--start-level=30", "--seed=5", "--players=4",
			"--shrine-chance=0.5", "--dungeon=1", "--hardcore", "--event=totem", "--env=swamp",
			"--leaderboard=user://m6b_flags.json", "--end-page=leaderboard", "--mode=endless"])
	var reversed := PackedStringArray()
	for i in range(args.size() - 1, -1, -1):
		reversed.append(args[i])
	for label in ["as written", "reversed"]:
		var o := LaunchOptions.parse(args if label == "as written" else reversed)
		check(o.unknown.is_empty(), "%s: every flag is known (%s)" % [label, ", ".join(o.unknown)])
		check_eq(o.mode, RunState.MODE_ENDLESS, "%s: endless" % label)
		check(o.hardcore, "%s: hardcore" % label)
		check_eq(o.start_wave, 24, "%s: wave 24 is kept (the clamp comes after the whole line)" % label)
		check_eq(o.last_wave(), 31, "%s: 8 waves from 24" % label)
		check_eq(o.environment, &"swamp", "%s: --env" % label)
		check_eq(o.event, EventSpawner.DEFEND_TOTEM, "%s: --event" % label)
		check_eq(o.shrine_chance, 0.5, "%s: --shrine-chance" % label)
		check(o.dungeon, "%s: --dungeon" % label)
		check_eq(o.leaderboard_path, "user://m6b_flags.json", "%s: --leaderboard" % label)
		check_eq(o.end_page, "leaderboard", "%s: --end-page" % label)


func test_a_normal_run_clamps_the_start_wave_to_25_whatever_the_flag_order() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--start-wave=24", "--waves=8"]))
	check_eq(o.mode, RunState.MODE_NORMAL, "normal")
	check_eq(o.last_wave(), 25, "the run ends at 25")


func test_the_hud_shows_the_hardcore_badge_the_shrine_icons_and_the_dungeon_line_together() -> void:
	RunState.start_run(2, SEED, RunState.MODE_ENDLESS, true)
	RunState.set_wave(27)
	RunState.add_shrine_effect(&"greed", 3)
	RunState.add_shrine_effect(&"haste", 2)
	var hud := Hud.create()
	tree.root.add_child(hud)
	nodes.append(hud)
	hud.set_dungeon_status("Dungeon – Room 2/4", "Kill enemies  12 / 25", 14.0)
	check(hud.hardcore_badge.visible, "the HARDCORE badge")
	check_eq(hud.shown_shrines().size(), 2, "both shrine icons")
	check(hud.shrine_row.visible, "in a visible row")
	check(hud.is_dungeon_shown(), "the dungeon line")
	check_eq(hud.wave_label.text, "Dungeon – Room 2/4", "its title")
	check(hud.wave_tag_label.visible and hud.timer_label.visible, "the task and the room clock")
	hud.clear_dungeon()
	check(hud.hardcore_badge.visible and hud.shrine_row.visible, "back from the dungeon the badge and the icons stay")
	check_eq(hud.wave_label.text, RunState.wave_progress_text(27), "and the wave line is back (no total in the endless mode)")


# --- The break: every phase at once ---------------------------------------------------------------------------

func test_a_break_with_loot_a_shrine_a_level_up_and_a_portal_runs_the_phases_in_order() -> void:
	var opts := _options()
	opts.shrine_chance = 1.0
	_run_with_bots(2, opts)
	RunState.pending_level_ups = 1
	_play_wave(6)
	var seen: Array[int] = []
	for i in 400:
		if main.state != Main.State.INTERMISSION:
			break
		var phase := int(main.intermission.phase)
		if seen.is_empty() or seen[-1] != phase:
			seen.append(phase)
		if main.intermission.phase == Intermission.Phase.MARKET:
			break
		for slot in PlayerManager.get_slots():
			slot.input.poll(0.1)
		main.intermission._process(0.1)
		if main.intermission.is_in_dungeon():
			main.enter_dungeon()
			break
	var P := Intermission.Phase
	check_eq(seen, [P.SHRINE, P.LEVEL_UP, P.PORTAL] as Array[int], "shrine, then the level-up cards, then the portal")
	check(main.dungeon != null, "the bots took the portal")
	_play_dungeon()
	check_eq(main.state, Main.State.INTERMISSION, "back in the break")
	_until_phase(Intermission.Phase.MARKET)
	check_eq(main.intermission.phase, Intermission.Phase.MARKET, "after the dungeon (and its Epics) the market")


# --- The lobby: mode select, the roll screen and the run ------------------------------------------------------

func test_the_lobbys_mode_choice_reaches_the_run_the_roll_screen_starts() -> void:
	EnvironmentRollScreen.enabled = true
	var opts := LaunchOptions.new()
	opts.seed_value = 2024
	main = Main.create(opts)
	tree.root.add_child(main)
	PlayerManager.add_bot(&"warrior", 1)
	main.go_to_lobby()
	var slot := PlayerManager.get_slots()[0]
	main.lobby.cycle_mode(slot)
	main.lobby.toggle_hardcore(slot)
	check_eq(main.lobby.mode_text(), "Mode: Endless · Hardcore", "the lobby header")
	main._on_lobby_start()
	check(main.roll_screen != null, "the roll screen plays")
	var winner := main.roll_screen.winner
	check_eq(winner, RunState.environment_for_seed(2024), "it shows the environment of the run seed")
	main._on_roll_finished(winner)
	check_eq(main.state, Main.State.WAVE, "the run started")
	check_eq(RunState.mode, RunState.MODE_ENDLESS, "endless, as chosen")
	check(RunState.hardcore, "hardcore, as chosen")
	check_eq(RunState.environment, winner, "in the arena the roll landed on")
	check(main.arena.spirit_healer == null, "a hardcore arena without a Grave Tender")
	check(main.hud.hardcore_badge.visible, "the HUD shows the badge")
	check_eq(RunState.total_waves(), 0, "no last wave")
