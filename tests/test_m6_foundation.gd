extends TestCase
## M6 P0 foundation hooks (behaviour-neutral): the Arcane Dust wallet, the damage-meter
## recorders, the run clock, the boss kind of record_special_kill, the SUPPORT / BRUTE AI
## dispatch and death-effect virtuals of Enemy, EnemyData.is_boss / BossData, the Db boss and
## consumable dirs, ConsumableData, the locked Enchanter tab, the optional parameters of
## Player.heal / revive, the LootDrops.roll_artifact wiring (the ARTIFACTS package made the roll
## real: its behaviour is tested in test_m6_artifacts_*), the Shop / Intermission hooks, the new
## SMOKE_RESULT keys and the --boss-hp / --artifact-chance launch flags.

const EFakes := preload("res://tests/enemies_fakes.gd")
const Fakes := preload("res://tests/player_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")
const DT := 1.0 / 60.0
const TMP_CONSUMABLE := "user://m6_foundation_consumable.tres"
const TMP_BOSS := "user://m6_foundation_boss.tres"


## An Enemy that records the M6 virtuals.
class ProbeEnemy extends Enemy:
	var support_calls := 0
	var brute_calls := 0
	var death_effects := 0
	var death_in_tree := false
	var death_position := Vector3.INF

	func _think_support(delta: float, here: Vector3) -> void:
		support_calls += 1
		super(delta, here)

	func _think_brute(delta: float, here: Vector3) -> void:
		brute_calls += 1
		super(delta, here)

	func _on_death_effect() -> void:
		death_effects += 1
		death_in_tree = is_inside_tree()
		death_position = global_position


## An Intermission that counts the M6 bot hooks and records the order of the passes.
class HookIntermission extends Intermission:
	var order: Array[StringName] = []

	func _bots_buy(p_shoppers: Array[PlayerSlot]) -> void:
		order.append(&"buy")
		super(p_shoppers)

	func _bots_black_market() -> int:
		order.append(&"black_market")
		return super()

	func _bots_consumables() -> int:
		order.append(&"consumables")
		return super()

	func _bots_train() -> int:
		order.append(&"train")
		return super()

	func _bots_talents() -> int:
		order.append(&"talents")
		return super()

	func _bots_enchant() -> int:
		order.append(&"enchant")
		return super()

	func _bots_reroll(p_shoppers: Array[PlayerSlot]) -> int:
		order.append(&"reroll")
		return super(p_shoppers)


var world: Node3D
var main: Main
var nodes: Array[Node] = []
var _probe_calls: Array = []


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, 4242)
	tree.paused = false
	LootDrops.artifact_roll_probe = Callable()
	_probe_calls.clear()


func after_each() -> void:
	LootDrops.artifact_roll_probe = Callable()
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
	for path in [TMP_CONSUMABLE, TMP_BOSS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	tree.paused = false
	UiFakes.reset_players()
	RunState.start_run(1, 1)
	Enemy.invalidate_player_cache()


func _make_main(opts: LaunchOptions = null) -> Main:
	main = Main.create(opts if opts != null else LaunchOptions.new())
	tree.root.add_child(main)
	return main


func _run_with_bots(count: int, opts: LaunchOptions = null) -> void:
	_make_main(opts)
	for i in count:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)
	main.start_run()


# --- Arcane Dust -------------------------------------------------------------------------------

func test_dust_starts_empty() -> void:
	check_eq(RunState.arcane_dust, 0, "no Dust")
	check_eq(RunState.dust_earned, 0, "none earned")
	check_eq(RunState.dust_spent, 0, "none spent")
	check(RunState.dust_spend_log.is_empty() and RunState.dust_gain_log.is_empty(), "empty logs")


func test_add_dust_counts_logs_and_signals() -> void:
	var seen: Array[Vector2i] = []
	RunState.dust_changed.connect(func(dust: int, delta: int) -> void: seen.append(Vector2i(dust, delta)))
	RunState.set_wave(4)
	RunState.add_dust(8, 2, "Epic Sword")
	RunState.add_dust(3)
	check_eq(RunState.arcane_dust, 11, "the pile")
	check_eq(RunState.dust_earned, 11, "earned")
	check_eq(seen, [Vector2i(8, 8), Vector2i(11, 3)] as Array[Vector2i], "dust_changed (dust, delta)")
	check_eq(RunState.dust_gain_log.size(), 2, "two gains logged")
	check_eq(RunState.dust_gain_log[0], {"slot": 2, "label": "Epic Sword", "amount": 8, "wave": 4}, "gain entry")
	check_eq(int(RunState.dust_gain_log[1]["slot"]), -1, "the team by default")
	# Nothing to add: no change, no signal.
	RunState.add_dust(0, 1, "nothing")
	RunState.add_dust(-5, 1, "negative")
	check_eq(RunState.arcane_dust, 11, "unchanged")
	check_eq(seen.size(), 2, "no signal")
	check_eq(RunState.dust_gain_log.size(), 2, "not logged")


func test_spend_dust_logs_like_gold_and_signals() -> void:
	RunState.set_wave(7)
	RunState.add_dust(10, 0, "Rare Ring")
	var seen: Array[Vector2i] = []
	RunState.dust_changed.connect(func(dust: int, delta: int) -> void: seen.append(Vector2i(dust, delta)))
	check(RunState.can_afford_dust(10) and not RunState.can_afford_dust(11), "can_afford_dust")
	check(RunState.try_spend_dust_for(4, 1, &"enchant", "Reroll Brutal"), "paid")
	check_eq(RunState.arcane_dust, 6, "pile")
	check_eq(RunState.dust_spent, 4, "spent total")
	check_eq(RunState.dust_earned, 10, "earned is not reduced")
	check_eq(RunState.dust_spend_log.size(), 1, "one entry")
	check_eq(RunState.dust_spend_log[0],
			{"slot": 1, "kind": &"enchant", "label": "Reroll Brutal", "amount": 4, "wave": 7}, "the same entry shape as gold")
	check_eq(seen, [Vector2i(6, -4)] as Array[Vector2i], "dust_changed with a negative delta")
	# Too poor / negative: nothing changes.
	check(not RunState.try_spend_dust_for(7, 1, &"enchant", "too much"), "refused")
	check(not RunState.try_spend_dust_for(-1, 1, &"enchant", "negative"), "negative refused")
	check_eq(RunState.arcane_dust, 6, "unchanged")
	check_eq(RunState.dust_spent, 4, "unchanged total")
	check_eq(RunState.dust_spend_log.size(), 1, "no extra entry")
	check_eq(seen.size(), 1, "no extra signal")
	check(RunState.try_spend_dust_for(6, -1, &"enchant", "all of it"), "exactly the pile")
	check_eq(RunState.arcane_dust, 0, "empty")
	check_eq(RunState.spend_log.size(), 0, "gold's log is separate")
	check_eq(RunState.gold_spent, 0, "gold untouched")


func test_a_new_spend_round_clears_the_dust_logs_but_not_the_pile() -> void:
	RunState.add_dust(5, 0, "Item")
	RunState.try_spend_dust_for(2, 0, &"enchant", "x")
	RunState.begin_spend_round()
	check(RunState.dust_spend_log.is_empty() and RunState.dust_gain_log.is_empty(), "logs cleared")
	check_eq(RunState.arcane_dust, 3, "the pile stays")
	check_eq(RunState.dust_earned, 5, "totals stay")
	check_eq(RunState.dust_spent, 2, "totals stay")


# --- Damage-meter recorders / run clock / counters ---------------------------------------------

func test_recorders_accumulate_per_slot() -> void:
	RunState.record_heal(0, 4.5)
	RunState.record_heal(0, 2.0)
	RunState.record_heal(1, 1.0)
	RunState.record_absorb(2, 7.0)
	RunState.record_damage_taken(1, 3.0)
	RunState.record_damage_taken(1, 0.5)
	RunState.record_revive(0)
	RunState.record_revive(0)
	RunState.record_revive(3)
	RunState.record_down(2)
	check_eq(RunState.healing_by_player, {0: 6.5, 1: 1.0}, "healing")
	check_eq(RunState.absorbed_by_player, {2: 7.0}, "absorbed")
	check_eq(RunState.damage_taken_by_player, {1: 3.5}, "damage taken")
	check_eq(RunState.revives_by_player, {0: 2, 3: 1}, "revives")
	check_eq(RunState.downs_by_player, {2: 1}, "downs")


func test_recorders_ignore_nobody_and_empty_amounts() -> void:
	RunState.record_heal(-1, 5.0)
	RunState.record_heal(0, 0.0)
	RunState.record_heal(0, -3.0)
	RunState.record_absorb(-1, 5.0)
	RunState.record_absorb(0, 0.0)
	RunState.record_damage_taken(-1, 5.0)
	RunState.record_damage_taken(0, -1.0)
	RunState.record_revive(-1)
	RunState.record_down(-1)
	check(RunState.healing_by_player.is_empty(), "no healing")
	check(RunState.absorbed_by_player.is_empty(), "no absorb")
	check(RunState.damage_taken_by_player.is_empty(), "no damage taken")
	check(RunState.revives_by_player.is_empty(), "no revives")
	check(RunState.downs_by_player.is_empty(), "no downs")


func test_tick_run_time_sums_deltas() -> void:
	check_eq(RunState.run_time, 0.0, "starts at 0")
	RunState.tick_run_time(0.5)
	RunState.tick_run_time(1.25)
	check_eq(RunState.run_time, 1.75, "sum")
	RunState.tick_run_time(0.0)
	RunState.tick_run_time(-3.0)
	check_eq(RunState.run_time, 1.75, "non-positive deltas are ignored")


func test_boss_kind_of_record_special_kill() -> void:
	var seen: Array = []
	RunState.special_killed.connect(func(kind: StringName, killer: int) -> void: seen.append([kind, killer]))
	RunState.record_special_kill(&"boss", 2)
	RunState.record_special_kill(&"boss", -1)
	RunState.record_special_kill(&"elite", 0)
	RunState.record_special_kill(&"goblin", 1)
	check_eq(RunState.bosses_killed, 2, "bosses")
	check_eq(RunState.elites_killed, 1, "elites unchanged")
	check_eq(RunState.goblins_killed, 1, "goblins unchanged")
	check_eq(seen, [[&"boss", 2], [&"boss", -1], [&"elite", 0], [&"goblin", 1]], "special_killed emitted for the boss too")


func test_start_run_resets_everything_new() -> void:
	RunState.add_dust(9, 0, "x")
	RunState.try_spend_dust_for(3, 0, &"enchant", "x")
	RunState.record_heal(0, 1.0)
	RunState.record_absorb(0, 1.0)
	RunState.record_damage_taken(0, 1.0)
	RunState.record_revive(0)
	RunState.record_down(0)
	RunState.tick_run_time(12.0)
	RunState.record_special_kill(&"boss", 0)
	RunState.artifacts_dropped = 2
	RunState.consumables_bought = 3
	RunState.black_market_bought = 1
	RunState.enchants_done = 4
	RunState.artifact_pity = 0.1
	RunState.artifact_classes.append(&"warrior")
	BossData.hp_mult = 3.0
	LootDrops.artifact_chance_override = 0.5
	var seen: Array[Vector2i] = []
	RunState.dust_changed.connect(func(dust: int, delta: int) -> void: seen.append(Vector2i(dust, delta)))
	RunState.start_run(2, 5)
	check_eq(RunState.arcane_dust, 0, "dust")
	check_eq(RunState.dust_earned, 0, "dust earned")
	check_eq(RunState.dust_spent, 0, "dust spent")
	check(RunState.dust_spend_log.is_empty() and RunState.dust_gain_log.is_empty(), "dust logs")
	check(RunState.healing_by_player.is_empty() and RunState.absorbed_by_player.is_empty()
			and RunState.damage_taken_by_player.is_empty() and RunState.revives_by_player.is_empty()
			and RunState.downs_by_player.is_empty(), "meter dictionaries")
	check_eq(RunState.run_time, 0.0, "run time")
	check_eq(RunState.bosses_killed, 0, "bosses")
	check_eq(RunState.artifacts_dropped, 0, "artifacts")
	check_eq(RunState.consumables_bought, 0, "consumables")
	check_eq(RunState.black_market_bought, 0, "black market")
	check_eq(RunState.enchants_done, 0, "enchants")
	check_eq(RunState.artifact_pity, 0.0, "pity")
	check(RunState.artifact_classes.is_empty(), "artifact classes")
	check_eq(BossData.hp_mult, 1.0, "--boss-hp static back to default")
	check_eq(LootDrops.artifact_chance_override, -1.0, "--artifact-chance static back to default")
	check_eq(seen, [Vector2i(0, 0)] as Array[Vector2i], "dust_changed announces the fresh pile")


# --- Main: run clock and SMOKE_RESULT ----------------------------------------------------------

func test_main_ticks_the_run_clock_only_while_a_wave_runs() -> void:
	_run_with_bots(2)
	check_eq(main.state, Main.State.WAVE, "wave running")
	check_eq(RunState.run_time, 0.0, "nothing yet")
	for i in 60:
		main._physics_process(DT)
	check_near(RunState.run_time, 1.0, 0.001, "one second of wave play")
	# Paused (pause menu): the game is not running.
	tree.paused = true
	main._physics_process(5.0)
	tree.paused = false
	check_near(RunState.run_time, 1.0, 0.001, "pauses do not count")
	# The wave ends: "Wave cleared!" is not wave play, nor is the market.
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	check_eq(main.state, Main.State.WAVE_END, "wave end")
	var at_end := RunState.run_time
	main._physics_process(0.5)
	check_near(RunState.run_time, at_end, 0.001, "the end-of-wave pause does not count")
	main._physics_process(Main.WAVE_END_DELAY)
	check_eq(main.state, Main.State.INTERMISSION, "market")
	main._physics_process(3.0)
	check_near(RunState.run_time, at_end, 0.001, "the market does not count")
	main._on_intermission_continue()
	check_eq(main.state, Main.State.WAVE, "next wave")
	main._physics_process(0.25)
	check_near(RunState.run_time, at_end + 0.25, 0.001, "the next wave counts again (sum of waves)")


func test_smoke_result_has_the_m6_keys() -> void:
	_run_with_bots(2)
	var data := main.smoke_result("completed")
	for key in ["bosses_killed", "artifacts_dropped", "consumables_bought", "black_market_bought",
			"enchants_done", "dust_earned", "dust_spent", "run_time"]:
		check(data.has(key), "SMOKE_RESULT has %s" % key)
		check_eq(data.get(key, -1), 0, "%s starts at 0" % key)
	RunState.record_special_kill(&"boss", 0)
	RunState.artifacts_dropped = 1
	RunState.consumables_bought = 5
	RunState.black_market_bought = 2
	RunState.enchants_done = 3
	RunState.add_dust(10)
	RunState.try_spend_dust_for(4, 0, &"enchant", "x")
	RunState.tick_run_time(12.34)
	data = main.smoke_result("completed")
	check_eq(data["bosses_killed"], 1, "bosses_killed")
	check_eq(data["artifacts_dropped"], 1, "artifacts_dropped")
	check_eq(data["consumables_bought"], 5, "consumables_bought")
	check_eq(data["black_market_bought"], 2, "black_market_bought")
	check_eq(data["enchants_done"], 3, "enchants_done")
	check_eq(data["dust_earned"], 10, "dust_earned")
	check_eq(data["dust_spent"], 4, "dust_spent")
	check_near(float(data["run_time"]), 12.3, 0.001, "run_time (0.1 s resolution)")


# --- Launch flags ------------------------------------------------------------------------------

func test_launch_flags_default_off() -> void:
	var o := LaunchOptions.parse(PackedStringArray())
	check_eq(o.boss_hp, 1.0, "--boss-hp default 1")
	check_eq(o.artifact_chance, -1.0, "--artifact-chance default -1 (off)")
	check("enchanter" in LaunchOptions.PANEL_TABS, "--panel-tab=enchanter is a known value")


func test_launch_flags_parse_and_clamp() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--boss-hp=0.25", "--artifact-chance=0.4"]))
	check_eq(o.boss_hp, 0.25, "--boss-hp")
	check_eq(o.artifact_chance, 0.4, "--artifact-chance")
	check(o.unknown.is_empty(), "both are known flags: %s" % str(o.unknown))
	o = LaunchOptions.parse(PackedStringArray(["--boss-hp=0", "--artifact-chance=7"]))
	check_eq(o.boss_hp, LaunchOptions.MIN_BOSS_HP_MULT, "boss HP never 0")
	check_eq(o.artifact_chance, 1.0, "chance at most 1")
	o = LaunchOptions.parse(PackedStringArray(["--boss-hp=5000", "--artifact-chance=-3"]))
	check_eq(o.boss_hp, LaunchOptions.MAX_BOSS_HP_MULT, "boss HP capped")
	check_eq(o.artifact_chance, 0.0, "chance at least 0 (0 = never, not off)")
	o = LaunchOptions.parse(PackedStringArray(["--panel-tab=enchanter"]))
	check_eq(o.panel_tab, "enchanter", "--panel-tab=enchanter")


func test_main_applies_the_launch_flags_each_run_and_start_run_resets_them() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--boss-hp=2.5", "--artifact-chance=0.3"]))
	_run_with_bots(2, o)
	check_eq(BossData.hp_mult, 2.5, "boss HP multiplier applied")
	check_eq(LootDrops.artifact_chance_override, 0.3, "artifact chance override applied")
	main.start_run()
	check_eq(BossData.hp_mult, 2.5, "a new run applies them again")
	check_eq(LootDrops.artifact_chance_override, 0.3, "again")
	RunState.start_run(1, 3)
	check_eq(BossData.hp_mult, 1.0, "RunState.start_run resets the boss multiplier")
	check_eq(LootDrops.artifact_chance_override, -1.0, "and the chance override")
	# Without the flags the statics stay at their defaults after Main.start_run.
	main.options = LaunchOptions.new()
	main.start_run()
	check_eq(BossData.hp_mult, 1.0, "default 1")
	check_eq(LootDrops.artifact_chance_override, -1.0, "default off")


# --- Enemy: boss flag, behaviours, death effect ------------------------------------------------

func _enemy_world() -> void:
	world = EFakes.make_world(tree)


func _spawn_probe(data: EnemyData, pos: Vector3) -> ProbeEnemy:
	var e := Enemy.setup(ProbeEnemy.new(), data, 1) as ProbeEnemy
	EFakes.arena_of(world).entities.add_child(e)
	e.global_position = pos
	return e


func test_is_boss_comes_from_the_data() -> void:
	_enemy_world()
	var plain := EFakes.enemy_data()
	check(not plain.is_boss, "EnemyData.is_boss defaults to false")
	var e := EFakes.spawn_enemy(world, plain, Vector3.ZERO)
	check(not e.is_boss(), "a normal enemy is no boss")
	for id in Db.enemies:
		check(not Db.enemies[id].is_boss, "%s is no boss" % id)
	var flagged := EFakes.enemy_data()
	flagged.is_boss = true
	var flagged_enemy := EFakes.spawn_enemy(world, flagged, Vector3(2, 0, 0))
	check(flagged_enemy.is_boss(), "is_boss = true on the data")
	check(flagged_enemy.is_elite() and not e.is_elite(), "a boss counts as an elite (Slayer, targeting)")
	var boss := BossData.new()
	boss.id = &"test_boss"
	check(boss.is_boss, "BossData is a boss by default")
	check(boss is EnemyData, "BossData extends EnemyData")
	var be := Enemy.create(boss, 10)
	check(be.is_boss(), "an Enemy made from a BossData")
	be.free()
	var goblin := LootGoblin.create(Db.get_enemy(&"loot_goblin"), 5)
	check(goblin.is_elite() and not goblin.is_boss(), "the Loot Goblin stays an elite, no boss")
	goblin.free()
	var no_data := Enemy.new()
	check(not no_data.is_boss(), "no data, no boss")
	no_data.free()


func test_support_and_brute_dispatch_and_fall_back_to_chase() -> void:
	_enemy_world()
	EFakes.spawn_player(world, Vector3(8.0, 0.0, 0.0))
	var support := _spawn_probe(EFakes.enemy_data(EnemyData.Behavior.SUPPORT), Vector3(0.0, 0.0, 0.0))
	var brute := _spawn_probe(EFakes.enemy_data(EnemyData.Behavior.BRUTE), Vector3(0.0, 0.0, 2.0))
	var chase := _spawn_probe(EFakes.enemy_data(EnemyData.Behavior.CHASE), Vector3(0.0, 0.0, -2.0))
	EFakes.step_all([support, brute, chase] as Array[Node], 0.5)
	check(support.support_calls > 0 and support.brute_calls == 0, "SUPPORT goes to _think_support")
	check(brute.brute_calls > 0 and brute.support_calls == 0, "BRUTE goes to _think_brute")
	check(chase.support_calls == 0 and chase.brute_calls == 0, "CHASE uses neither")
	check(support.global_position.x > 0.5, "the SUPPORT fallback walks at the hero (CHASE)")
	check(brute.global_position.x > 0.5, "the BRUTE fallback walks at the hero (CHASE)")
	check(chase.global_position.x > 0.5, "CHASE for reference")


func test_chase_fallback_moves_like_the_chase_behaviour() -> void:
	_enemy_world()
	EFakes.spawn_player(world, Vector3(8.0, 0.0, 0.0))
	var base_data := EFakes.enemy_data(EnemyData.Behavior.CHASE)
	var chaser := EFakes.spawn_enemy(world, base_data, Vector3.ZERO)
	var support := EFakes.spawn_enemy(world, EFakes.enemy_data(EnemyData.Behavior.SUPPORT), Vector3(0.0, 0.0, 3.0))
	var brute := EFakes.spawn_enemy(world, EFakes.enemy_data(EnemyData.Behavior.BRUTE), Vector3(0.0, 0.0, -3.0))
	# Same speed, so the same distance walked in a straight line.
	for e: Enemy in [chaser, support, brute]:
		e.move_speed = 3.0
	EFakes.step_all([chaser, support, brute] as Array[Node], 1.0)
	var walked := chaser.global_position.x
	check(walked > 1.0, "the chaser walked: %f" % walked)
	check_near(support.global_position.x, walked, 0.35, "SUPPORT walks as far as CHASE")
	check_near(brute.global_position.x, walked, 0.35, "BRUTE walks as far as CHASE")


func test_on_death_effect_is_called_from_die_before_the_enemy_leaves() -> void:
	_enemy_world()
	var e := _spawn_probe(EFakes.enemy_data(), Vector3(3.0, 0.0, -2.0))
	e.take_damage(2.0)
	check_eq(e.death_effects, 0, "not while alive")
	e.take_damage(1000.0)
	check_eq(e.death_effects, 1, "called once on death")
	check(e.death_in_tree, "still in the tree")
	check_near(e.death_position.x, 3.0, 0.001, "at the place of death x")
	check_near(e.death_position.z, -2.0, 0.001, "at the place of death z")
	e.take_damage(5.0)
	check_eq(e.death_effects, 1, "not twice")
	# Despawn (wave end) is no death.
	var d := _spawn_probe(EFakes.enemy_data(), Vector3.ZERO)
	d.despawn()
	check_eq(d.death_effects, 0, "a despawn leaves nothing")
	# Kill (Execute) is a death.
	var k := _spawn_probe(EFakes.enemy_data(), Vector3(1.0, 0.0, 1.0))
	k.kill()
	check_eq(k.death_effects, 1, "kill() too")
	# The base implementation exists and does nothing.
	var plain := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3(-4.0, 0.0, 0.0))
	plain._on_death_effect()
	check(not plain.is_dead(), "the base virtual is empty")


# --- Db / data ---------------------------------------------------------------------------------

func test_db_has_the_boss_and_consumable_dirs() -> void:
	check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(Db.BOSS_DIR)), "data/bosses exists")
	check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(Db.CONSUMABLE_DIR)), "data/consumables exists")
	check_eq(Db.BOSS_DIR, "res://data/bosses/", "boss dir")
	check_eq(Db.CONSUMABLE_DIR, "res://data/consumables/", "consumable dir")
	# The dirs may be empty; whatever is in them is of the right class and keyed by id.
	for id in Db.bosses:
		check(Db.bosses[id] is BossData and Db.bosses[id].id == id, "boss %s" % id)
		check(not Db.enemies.has(id), "bosses are not in the random enemy pool (%s)" % id)
	for id in Db.consumables:
		check(Db.consumables[id] is ConsumableData and Db.consumables[id].id == id, "consumable %s" % id)


func test_db_getters() -> void:
	check(Db.get_boss(&"no_such_boss") == null, "unknown boss")
	check(Db.get_consumable(&"no_such_consumable") == null, "unknown consumable")
	var boss := BossData.new()
	boss.id = &"m6_test_boss"
	var cons := ConsumableData.new()
	cons.id = &"m6_test_flask"
	Db.bosses[boss.id] = boss
	Db.consumables[cons.id] = cons
	check(Db.get_boss(&"m6_test_boss") == boss, "get_boss")
	check(Db.get_consumable(&"m6_test_flask") == cons, "get_consumable")
	check(Db.get_enemy(&"m6_test_boss") == null, "get_enemy does not see bosses")
	# reload() rebuilds both from disk (the injected ones are gone).
	Db.reload()
	check(Db.get_boss(&"m6_test_boss") == null and Db.get_consumable(&"m6_test_flask") == null, "reload clears them")
	check_eq(Db.enemies.size(), 5, "the enemy pool is unchanged")


func test_consumable_data_defaults_and_round_trip() -> void:
	var c := ConsumableData.new()
	check_eq(c.kind, ConsumableData.Kind.POTION, "potion by default")
	check(c.is_potion() and not c.is_food(), "kind helpers")
	check(c.effects.is_empty(), "no effects")
	c.id = &"flask_of_test"
	c.display_name = "Flask of Testing"
	c.kind = ConsumableData.Kind.FOOD
	c.effects = [{"kind": "damage", "pct": 15.0}, {"kind": "stats", "stats": {"fortune": 25.0}}] as Array[Dictionary]
	c.base_price = 14
	c.icon_id = &"flask"
	c.description = "+15% damage."
	check(c.is_food() and not c.is_potion(), "food")
	check_eq(ResourceSaver.save(c, TMP_CONSUMABLE), OK, "saved")
	var loaded := ResourceLoader.load(TMP_CONSUMABLE, "", ResourceLoader.CACHE_MODE_IGNORE) as ConsumableData
	check(loaded != null, "loads back as a ConsumableData")
	if loaded == null:
		return
	check_eq(loaded.id, &"flask_of_test", "id")
	check_eq(loaded.display_name, "Flask of Testing", "name")
	check_eq(loaded.kind, ConsumableData.Kind.FOOD, "kind")
	check_eq(loaded.base_price, 14, "price")
	check_eq(loaded.icon_id, &"flask", "icon")
	check_eq(loaded.description, "+15% damage.", "description")
	check_eq(loaded.effects.size(), 2, "effects")
	check_eq(loaded.effects[0], {"kind": "damage", "pct": 15.0}, "an effect entry")
	check_eq(BonusVocabulary.KINDS.has(StringName(loaded.effects[1]["kind"])), true, "effects are BonusVocabulary entries")


func test_boss_data_round_trip_keeps_the_boss_flag() -> void:
	var b := BossData.new()
	b.id = &"m6_round_trip_boss"
	b.max_hp = 450.0
	check_eq(ResourceSaver.save(b, TMP_BOSS), OK, "saved")
	var loaded := ResourceLoader.load(TMP_BOSS, "", ResourceLoader.CACHE_MODE_IGNORE) as BossData
	check(loaded != null and loaded.is_boss, "a BossData loads as a boss")
	check(loaded != null and loaded.max_hp == 450.0, "its EnemyData fields too")


func test_enemy_behavior_enum_keeps_the_old_values() -> void:
	check_eq(EnemyData.Behavior.CHASE, 0, "CHASE")
	check_eq(EnemyData.Behavior.SWARM, 1, "SWARM")
	check_eq(EnemyData.Behavior.LUNGE, 2, "LUNGE")
	check_eq(EnemyData.Behavior.RANGED, 3, "RANGED")
	check_eq(EnemyData.Behavior.SUPPORT, 4, "SUPPORT appended")
	check_eq(EnemyData.Behavior.BRUTE, 5, "BRUTE appended")


func test_item_instance_counts_enchant_uses() -> void:
	var item := ItemInstance.new()
	check_eq(item.enchant_uses, 0, "no Enchanter action yet")
	check_eq(ItemInstance.from_weapon(Db.get_weapon(&"sword")).enchant_uses, 0, "weapons too")


# --- Shop / Intermission hooks -----------------------------------------------------------------

func test_shop_has_empty_consumable_and_black_market_slots() -> void:
	var shop := Shop.new()
	check(shop.consumables.is_empty(), "no consumables row yet")
	check(shop.black_market == null, "no Black Market offer yet")
	RunState.set_wave(15)
	var slot := PlayerManager.join(ScriptedInput.new("m6:shop"), Db.get_class_data(&"warrior"))
	shop.open_round(15, [slot] as Array[PlayerSlot], RunState.rng)
	check_eq(shop.offers.size(), Shop.offer_count(1), "the offers are unchanged")
	check(shop.consumables.is_empty() and shop.black_market == null, "open_round leaves them empty")


func test_bot_shopping_calls_the_m6_hooks_in_order() -> void:
	var im := HookIntermission.new()
	im.name = "Intermission"
	im._build()
	nodes.append(im)
	tree.root.add_child(im)
	im._bots_shop()
	check_eq(im.order, [&"buy", &"black_market", &"consumables", &"train", &"talents", &"enchant", &"reroll"] as Array[StringName],
			"the passes of _bots_shop")
	var plain := Intermission.create()
	nodes.append(plain)
	tree.root.add_child(plain)
	check_eq(plain._bots_black_market(), 0, "black market stub")
	check_eq(plain._bots_consumables(), 0, "consumables stub")
	check_eq(plain._bots_enchant(), 0, "enchant stub")


# --- PlayerPanel: the locked Enchanter tab -----------------------------------------------------

func _panel() -> PlayerPanel:
	var slot := PlayerManager.join(ScriptedInput.new("m6:panel"), Db.get_class_data(&"warrior"))
	var hero := Player.create(slot)
	nodes.append(hero)
	var panel := PlayerPanel.create(slot)
	nodes.append(panel)
	tree.root.add_child(panel)
	panel.set_input_focus(true)
	return panel


func test_enchanter_tab_constants() -> void:
	check_eq(PlayerPanel.ENCHANTER_TAB, 3, "the fourth tab")
	check_eq(PlayerPanel.TAB_NAMES.size(), 4, "four tabs")
	check_eq(PlayerPanel.TAB_NAMES[PlayerPanel.ENCHANTER_TAB], "Enchanter", "named")
	check_eq(PlayerPanel.TAB_IDS.get("enchanter", -1), PlayerPanel.ENCHANTER_TAB, "--panel-tab id")
	check_eq(PlayerPanel.TAB_IDS.size(), PlayerPanel.TAB_NAMES.size(), "an id per tab")
	for id in PlayerPanel.TAB_IDS:
		check(id in LaunchOptions.PANEL_TABS, "%s is a --panel-tab value" % id)
	for id in LaunchOptions.PANEL_TABS:
		check(PlayerPanel.TAB_IDS.has(id), "%s has a tab" % id)
	check(PlayerPanel.ENCHANTER_TAB in PlayerPanel.LOCKED_TABS, "locked until the ENCHANTER package")
	check_eq(PlayerPanel.LOCKED_TABS.size(), 1, "and the only locked one")


func test_lt_rt_never_reach_the_locked_enchanter_tab() -> void:
	var panel := _panel()
	check_eq(panel.active_tab, PlayerPanel.CHARACTER_TAB, "starts on Character")
	var seen: Array[int] = []
	for i in 8:
		panel.switch_tab(1)
		seen.append(panel.active_tab)
	check_eq(seen, [1, 2, 0, 1, 2, 0, 1, 2] as Array[int], "RT cycles Character / Trainer / Talents only")
	seen.clear()
	for i in 8:
		panel.switch_tab(-1)
		seen.append(panel.active_tab)
	check_eq(seen, [1, 0, 2, 1, 0, 2, 1, 0] as Array[int], "LT too")
	check(PlayerPanel.ENCHANTER_TAB not in seen, "never the Enchanter")
	# From the last open tab RT wraps to the first (as with three tabs), LT from the first to the last open one.
	panel.set_tab(PlayerPanel.TALENTS_TAB)
	panel.switch_tab(1)
	check_eq(panel.active_tab, PlayerPanel.CHARACTER_TAB, "Talents + RT = Character")
	panel.switch_tab(-1)
	check_eq(panel.active_tab, PlayerPanel.TALENTS_TAB, "Character + LT = Talents")


func test_set_tab_refuses_the_locked_enchanter_tab() -> void:
	var panel := _panel()
	panel.set_tab(PlayerPanel.TRAINER_TAB)
	panel.set_tab(PlayerPanel.ENCHANTER_TAB)
	check_eq(panel.active_tab, PlayerPanel.TRAINER_TAB, "set_tab refuses it")
	PlayerPanel.debug_start_tab = "enchanter"
	panel._debug_tab_done = false
	panel._apply_debug_start_tab()
	PlayerPanel.debug_start_tab = ""
	check(panel.active_tab != PlayerPanel.ENCHANTER_TAB, "--panel-tab=enchanter stays closed too")
	panel.set_tab(PlayerPanel.CHARACTER_TAB)
	check_eq(panel.active_tab, PlayerPanel.CHARACTER_TAB, "the others still open")


func test_the_tab_strip_shows_the_padlock_and_fits_the_panel() -> void:
	var panel := _panel()
	panel.size = PlayerPanel.DESIGN_SIZE
	panel.refresh()
	panel.set_tab(PlayerPanel.TALENTS_TAB)
	check_eq(panel._tab_labels.size(), 4, "four tab labels")
	check_eq(panel.tab_text(PlayerPanel.ENCHANTER_TAB), "Enchanter", "the label")
	# The widest case (the active Talents tab with a two-digit label) stays inside the design width.
	panel._tab_labels[PlayerPanel.TALENTS_TAB].text = "Talents (20)"
	var strip := panel._tabs_row.get_combined_minimum_size()
	check(strip.x <= PlayerPanel.DESIGN_SIZE.x, "the tab strip fits: %s" % strip)
	var frame_min := panel.get_child(0).get_combined_minimum_size() as Vector2
	check(frame_min.x <= PlayerPanel.DESIGN_SIZE.x + 0.5, "the frame fits the design width: %s" % frame_min)


# --- Player: optional parameters ---------------------------------------------------------------

func test_heal_and_revive_take_optional_source_slots() -> void:
	world = Fakes.make_world(tree)
	var p := Fakes.spawn_player(world, 0, &"warrior")
	p.hp = 1.0
	p.heal(4.0)
	check_eq(p.hp, 5.0, "heal(amount) as before")
	p.heal(3.0, 2)
	check_eq(p.hp, 8.0, "heal(amount, source_slot)")
	p.heal(2.0, -1)
	check_eq(p.hp, 10.0, "heal(amount, -1)")
	p._go_down()
	check(p.downed, "down")
	p.revive(0.5, [1, 3] as Array[int])
	check(not p.downed, "revive(ratio, reviver_slots)")
	check_near(p.hp, roundf(p.max_hp() * 0.5), 1.0, "at the given ratio")
	p._go_down()
	p.revive()
	check(not p.downed, "revive() as before")
	check_near(p.hp, roundf(p.max_hp() * Player.REVIVE_HP_RATIO), 1.0, "at the default ratio")
	p._go_down()
	p.revive(1.0)
	check_eq(p.hp, p.max_hp(), "revive(ratio) as before")
	Fakes.free_world(world)
	world = null


# --- LootDrops: the Artifact roll wiring ------------------------------------------------------

func _probe(source: ItemGenerator.Source, enemy: Node3D, killer: Node3D) -> LootBag:
	_probe_calls.append([source, enemy, killer])
	return null


## (P0 pinned a stub that never rolled; the real roll – test_m6_artifacts_core – only rolls from
## wave 10 and draws nothing before it, which is what keeps the old seeds comparable.)
func test_roll_artifact_below_wave_10_draws_nothing_and_drops_nothing() -> void:
	_enemy_world()
	var e := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3.ZERO)
	LootDrops.artifact_chance_override = 1.0  # even a sure drop waits for wave 10
	RunState.set_wave(9)
	var before := RunState.rng.state
	check(LootDrops.roll_artifact(ItemGenerator.Source.BOSS, e, null) == null, "returns null")
	check(LootDrops.roll_artifact(ItemGenerator.Source.LOOT, e, null) == null, "for every source")
	check_eq(RunState.rng.state, before, "no RunState.rng draw (seeded runs stay comparable)")
	RunState.set_wave(10)
	check(LootDrops.roll_artifact(ItemGenerator.Source.BOSS, e, null) != null, "wave 10: the roll is real")


func test_drop_special_calls_roll_artifact() -> void:
	_enemy_world()
	LootDrops.artifact_roll_probe = _probe
	var e := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3(2.0, 0.0, 1.0))
	var bag := LootDrops.drop_special(ItemGenerator.Source.ELITE, e, null)
	check(bag != null, "the guaranteed drop still drops")
	check_eq(_probe_calls.size(), 1, "the Artifact roll ran once")
	if _probe_calls.size() == 1:
		check_eq(_probe_calls[0][0], ItemGenerator.Source.ELITE, "with the source")
		check(_probe_calls[0][1] == e, "and the enemy")
		check(_probe_calls[0][2] == null, "and the killer")
	LootDrops.drop_special(ItemGenerator.Source.BOSS, e, null)
	check_eq(_probe_calls.size(), 2, "boss drops roll too")
	check_eq(_probe_calls[1][0], ItemGenerator.Source.BOSS, "BOSS source")


func test_on_enemy_killed_calls_roll_artifact_after_the_normal_roll() -> void:
	_enemy_world()
	LootDrops.artifact_roll_probe = _probe
	var e := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3.ZERO)
	# Whatever the normal roll does, the Artifact roll follows (also when the wave cap is reached).
	RunState.loot_drops_this_wave = LootDrops.max_drops_per_wave()
	check(LootDrops.on_enemy_killed(e, null) == null, "the capped normal roll drops nothing")
	check_eq(_probe_calls.size(), 1, "the Artifact roll still ran")
	if _probe_calls.size() == 1:
		check_eq(_probe_calls[0][0], ItemGenerator.Source.LOOT, "as a LOOT roll")
	RunState.loot_drops_this_wave = 0
	for i in 20:
		LootDrops.on_enemy_killed(e, null)
	check_eq(_probe_calls.size(), 21, "once per kill")
	LootDrops.on_enemy_killed(null, null)
	check_eq(_probe_calls.size(), 21, "no enemy, no roll")


func test_the_artifact_roll_keeps_seeded_drops_identical_below_wave_10() -> void:
	_enemy_world()
	var e := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3.ZERO)
	RunState.start_run(1, 99)
	var plain: Array[bool] = []
	for i in 40:
		RunState.loot_drops_this_wave = 0
		plain.append(LootDrops._roll_normal_drop(e, null) != null)  # the normal roll alone (as before M6)
	var state_after := RunState.rng.state
	RunState.start_run(1, 99)
	var with_roll: Array[bool] = []
	for i in 40:
		RunState.loot_drops_this_wave = 0
		with_roll.append(LootDrops.on_enemy_killed(e, null) != null)  # normal roll + Artifact roll
	check_eq(with_roll, plain, "the same drops")
	check_eq(RunState.rng.state, state_after, "the same rng state: the Artifact roll drew nothing")
	check(true in plain, "the sample dropped something (seed sanity)")


func test_player_reports_wave_begin_and_end() -> void:
	world = Fakes.make_world(tree)
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var seen: Array[String] = []
	p.wave_began.connect(func() -> void: seen.append("began"))
	p.wave_ended.connect(func() -> void: seen.append("ended"))
	p.end_wave()
	p.begin_wave()
	check_eq(seen, ["ended", "began"], "end_wave / begin_wave emit wave_ended / wave_began")
	Fakes.free_world(world)
	world = null
