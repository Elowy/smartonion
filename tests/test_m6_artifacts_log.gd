extends TestCase
## M6 ARTIFACTS in the smoke log: one "artifact drop" line per Artifact that drops (RunState
## .artifact_dropped, emitted by LootDrops.roll_artifact) and one "artifact held" line per hero
## per wave end for every Artifact it holds – class, waves held, Item Level, properties awake –
## so a seeded smoke run shows what the Artifacts did (Main.artifact_lines, printed behind
## "SMOKE ").

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0

var main: Main
var world: Node3D
var arena: EFakes.TestArena
var dropped: Array = []


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(2, 4711)
	RunState.set_wave(10)
	LootDrops.artifact_roll_probe = Callable()
	LootDrops.artifact_chance_override = -1.0
	tree.paused = false
	dropped.clear()


func after_each() -> void:
	LootDrops.artifact_roll_probe = Callable()
	LootDrops.artifact_chance_override = -1.0
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	if world != null:
		EFakes.free_world(tree, world)
		world = null
		arena = null
	tree.paused = false
	PlayerManager.clear()
	RunState.start_run(1, 1)
	Enemy.invalidate_player_cache()


func _boss() -> Enemy:
	world = EFakes.make_world(tree)
	arena = EFakes.arena_of(world)
	var data := EFakes.enemy_data()
	data.is_boss = true
	return EFakes.spawn_enemy(world, data, Vector3(3.0, 0.0, 2.0), 10)


func _record(item: ItemInstance, source: StringName) -> void:
	dropped.append([item, source])


## Main with [param count] bots, the run started.
func _run_with_bots(count: int) -> void:
	main = Main.create(LaunchOptions.new())
	tree.root.add_child(main)
	for i in count:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)
	main.start_run()


## Gives hero [param index] the Artifact of its class (equipped, or in the backpack).
func _give_artifact(index: int, equipped: bool) -> ItemInstance:
	var hero := main.players[index]
	var data := Db.artifact_for_class(hero.class_data.id)
	check(data != null, "%s has an Artifact" % hero.class_data.id)
	var item := ItemGenerator.from_artifact(data, 10)
	hero.equipment.backpack.append(item)
	if equipped:
		check(hero.equipment.equip(item), "the hero equips it")
	return item


## The market opens after wave [param wave]: the wave clears, the "Wave cleared!" pause passes.
func _end_the_wave() -> void:
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	check_eq(main.state, Main.State.WAVE_END, "wave end")
	main._physics_process(Main.WAVE_END_DELAY + 0.1)
	check_eq(main.state, Main.State.INTERMISSION, "market")


# --- The drop ----------------------------------------------------------------------------

func test_a_drop_announces_itself_with_its_source() -> void:
	RunState.artifact_dropped.connect(_record)
	var boss := _boss()
	LootDrops.artifact_chance_override = 1.0
	var bag := LootDrops.roll_artifact(ItemGenerator.Source.BOSS, boss, null)
	check(bag != null, "a bag")
	check_eq(dropped.size(), 1, "one announcement")
	check(dropped[0][0] == bag.item, "of the dropped item")
	check_eq(dropped[0][1], &"boss", "from a boss")
	# Another kind of kill names its own source.
	var elite_data := EFakes.enemy_data()
	var elite := EFakes.spawn_enemy(world, elite_data, Vector3(5.0, 0.0, 2.0), 10)
	LootDrops.roll_artifact(ItemGenerator.Source.ELITE, elite, null)
	check_eq(dropped.size(), 2, "the second drop")
	check_eq(dropped[1][1], &"elite", "from an elite")
	RunState.artifact_dropped.disconnect(_record)


func test_a_miss_announces_nothing() -> void:
	RunState.artifact_dropped.connect(_record)
	var boss := _boss()
	LootDrops.artifact_chance_override = 0.0
	check(LootDrops.roll_artifact(ItemGenerator.Source.BOSS, boss, null) == null, "no drop")
	RunState.set_wave(9)
	LootDrops.artifact_chance_override = 1.0
	check(LootDrops.roll_artifact(ItemGenerator.Source.BOSS, _enemy_under_arena(), null) == null, "none below wave 10")
	check(dropped.is_empty(), "no announcement")
	RunState.artifact_dropped.disconnect(_record)


func _enemy_under_arena() -> Enemy:
	var data := EFakes.enemy_data()
	data.is_boss = true
	return EFakes.spawn_enemy(world, data, Vector3(4.0, 0.0, 2.0), 10)


func test_the_drop_line_names_the_artifact_class_wave_source_and_item_level() -> void:
	var item := ItemGenerator.generate_artifact(&"warrior", 10)
	var line := Artifacts.drop_line(item, &"boss", 10)
	check_eq(line, "artifact drop: Earthsplitter (warrior) on wave 10 from boss, item level 65", "the line")


func test_the_held_line_reads_waves_held_item_level_and_properties_awake() -> void:
	var item := ItemGenerator.generate_artifact(&"warrior", 10)
	check_eq(Artifacts.held_line("P1", item, 10, true),
			"artifact held: P1 warrior Earthsplitter after wave 10, waves held 0, item level 65, properties awake 0/2, equipped", "fresh")
	for i in 3:
		Artifacts.grow_item(item)
	check_eq(Artifacts.held_line("P2", item, 13, false),
			"artifact held: P2 warrior Earthsplitter after wave 13, waves held 3, item level 74, properties awake 1/2, in the backpack", "three waves on")
	for i in 3:
		Artifacts.grow_item(item)
	check("properties awake 2/2" in Artifacts.held_line("P1", item, 16, true), "both awake after six")


func test_main_logs_a_dropped_artifact() -> void:
	_run_with_bots(2)
	RunState.set_wave(10)
	var boss := _boss()
	check(main.artifact_lines.is_empty(), "nothing logged yet")
	LootDrops.artifact_chance_override = 1.0
	var bag := LootDrops.roll_artifact(ItemGenerator.Source.BOSS, boss, null)
	check(bag != null, "dropped")
	check_eq(main.artifact_lines.size(), 1, "one line per drop")
	check_eq(main.artifact_lines[0], Artifacts.drop_line(bag.item, &"boss", 10), "the drop line")
	check("artifact drop:" in main.artifact_lines[0] and bag.item.display_name in main.artifact_lines[0], "names the Artifact")


# --- The wave end ---------------------------------------------------------------------------

func test_main_logs_every_artifact_every_hero_holds_at_each_wave_end() -> void:
	_run_with_bots(2)
	var held := _give_artifact(0, true)
	var packed := _give_artifact(1, false)
	check(main.artifact_lines.is_empty(), "nothing logged before a wave ends")
	_end_the_wave()
	check_eq(main.artifact_lines.size(), 2, "one line per hero holding an Artifact: %s" % [main.artifact_lines])
	var p1 := main.players[0]
	var p2 := main.players[1]
	check_eq(main.artifact_lines[0], Artifacts.held_line(p1.slot.label(), held, 1, true), "the equipped one")
	check_eq(main.artifact_lines[1], Artifacts.held_line(p2.slot.label(), packed, 1, false), "the one in the backpack")
	check("waves held 1" in main.artifact_lines[0] and "item level 68" in main.artifact_lines[0], "grown by the wave end it logs")
	check("properties awake 0/2" in main.artifact_lines[0], "properties still asleep")
	check(p1.class_data.display_name.to_lower() in main.artifact_lines[0] or String(p1.class_data.id) in main.artifact_lines[0], "names the class")
	# The next wave end logs again.
	main._on_intermission_continue()
	check_eq(main.state, Main.State.WAVE, "next wave")
	_end_the_wave()
	check_eq(main.artifact_lines.size(), 4, "two more lines")
	check("waves held 2" in main.artifact_lines[2] and "item level 71" in main.artifact_lines[2], "waves held 2, item level 71")


func test_a_hero_without_an_artifact_logs_nothing_and_a_new_run_clears_the_lines() -> void:
	_run_with_bots(2)
	_end_the_wave()
	check(main.artifact_lines.is_empty(), "no Artifact held: no line")
	_give_artifact(0, true)
	main._on_intermission_continue()
	_end_the_wave()
	check_eq(main.artifact_lines.size(), 1, "one line once a hero holds one")
	tree.paused = false
	main.start_run()
	check(main.artifact_lines.is_empty(), "a new run starts a new log")
