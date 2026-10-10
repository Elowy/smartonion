extends TestCase
## LootDrops: base chance, Fortune, the per-wave cap, where the bag lands.

const EFakes := preload("res://tests/enemies_fakes.gd")

var world: Node3D
var arena: EFakes.TestArena


func before_each() -> void:
	RunState.start_run(2, 21)
	RunState.set_wave(3)
	world = EFakes.make_world(tree)
	arena = EFakes.arena_of(world)


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null
	arena = null


func _enemy_at(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	arena.entities.add_child(n)
	n.global_position = pos
	return n


## A far-away player with [param fortune] Fortune.
func _killer(fortune: float) -> Player:
	var p := EFakes.spawn_player(world, Vector3(25.0, 0.0, 25.0), 0)
	if fortune != 0.0:
		p.stats.set_source(&"test", {Stats.FORTUNE: fortune})
	return p


func _bags() -> Array[Node]:
	return tree.get_nodes_in_group(&"loot_bags")


func test_chance_formula() -> void:
	check_near(LootDrops.drop_chance(null), 0.015, 0.000001, "base 1.5%")
	check_near(LootDrops.drop_chance(_killer(0.0)), 0.015, 0.000001, "no Fortune")
	check_near(LootDrops.drop_chance(_killer(8.0)), 0.023, 0.000001, "+8 Fortune = +0.8 points")
	check_near(LootDrops.drop_chance(_killer(50.0)), 0.065, 0.000001, "+50 Fortune = +5 points")
	check_near(LootDrops.drop_chance(_killer(5000.0)), 1.0, 0.000001, "capped at 100%")
	var not_a_player := Node3D.new()
	check_near(LootDrops.drop_chance(not_a_player), 0.015, 0.000001, "a non-player killer has no Fortune")
	not_a_player.free()


func test_cap_is_one_plus_players() -> void:
	RunState.start_run(1, 1)
	check_eq(LootDrops.max_drops_per_wave(), 2, "1 player")
	RunState.start_run(4, 1)
	check_eq(LootDrops.max_drops_per_wave(), 5, "4 players")


func test_wave_cap_limits_drops_and_resets_each_wave() -> void:
	var killer := _killer(5000.0)  # every kill would drop
	var enemy := _enemy_at(Vector3(2, 0, 2))
	var dropped := 0
	for i in 10:
		if LootDrops.on_enemy_killed(enemy, killer) != null:
			dropped += 1
	check_eq(dropped, 3, "2 players -> at most 3 drops per wave")
	check_eq(RunState.loot_drops_this_wave, 3, "counter")
	check_eq(_bags().size(), 3, "three bags on the ground")
	RunState.set_wave(4)
	check_eq(RunState.loot_drops_this_wave, 0, "new wave resets the counter")
	check(LootDrops.on_enemy_killed(enemy, killer) != null, "drops again")


func test_bag_lands_at_the_enemy_with_a_looted_item() -> void:
	var killer := _killer(5000.0)
	var enemy := _enemy_at(Vector3(4.0, 0.0, -3.0))
	var bag := LootDrops.on_enemy_killed(enemy, killer)
	check(bag != null, "dropped")
	check(bag.is_in_group(&"loot_bags"), "in the loot_bags group")
	check(bag.get_parent() == arena.entities, "under the arena's entities")
	check_near(bag.global_position.x, 4.0, 0.001, "x")
	check_near(bag.global_position.z, -3.0, 0.001, "z")
	check_near(bag.global_position.y, 0.0, 0.001, "on the ground")
	check(bag.item != null, "holds an item")
	check(bag.item.looted, "marked as looted")
	check(bag.item.buy_price > 0, "has a value for Greed")


func test_base_rate_is_about_one_and_a_half_percent() -> void:
	var enemy := _enemy_at(Vector3.ZERO)
	var drops := 0
	for i in 4000:
		RunState.loot_drops_this_wave = 0
		var bag := LootDrops.on_enemy_killed(enemy, null)
		if bag != null:
			drops += 1
			bag.free()
	check(drops >= 30 and drops <= 100, "1.5%% of 4000 = 60, got %d" % drops)


func test_fortune_raises_the_rate() -> void:
	var enemy := _enemy_at(Vector3.ZERO)
	var killer := _killer(200.0)  # 1.5% + 20 points = 21.5%
	var drops := 0
	for i in 600:
		RunState.loot_drops_this_wave = 0
		var bag := LootDrops.on_enemy_killed(enemy, killer)
		if bag != null:
			drops += 1
			bag.free()
	check(drops >= 90 and drops <= 170, "21.5%% of 600 = 129, got %d" % drops)


func test_same_seed_same_drops() -> void:
	var enemy := _enemy_at(Vector3.ZERO)
	var killer := _killer(300.0)
	var runs: Array[Array] = []
	for r in 2:
		RunState.rng.seed = 77
		var pattern: Array[bool] = []
		for i in 40:
			RunState.loot_drops_this_wave = 0
			var bag := LootDrops.on_enemy_killed(enemy, killer)
			pattern.append(bag != null)
			if bag != null:
				bag.free()
		runs.append(pattern)
	check_eq(runs[0], runs[1], "deterministic with RunState.rng")


func test_bag_goes_under_the_enemy_parent_without_an_arena() -> void:
	var killer := _killer(5000.0)
	killer.reparent(world)  # survives the arena
	var holder := Node3D.new()
	world.add_child(holder)
	var enemy := Node3D.new()
	holder.add_child(enemy)
	arena.free()  # Arena.current becomes null
	check(Arena.current == null, "no arena")
	var bag := LootDrops.on_enemy_killed(enemy, killer)
	check(bag != null and bag.get_parent() == holder, "falls back to the enemy's parent")


func test_nothing_without_an_enemy_or_a_place() -> void:
	check(LootDrops.on_enemy_killed(null, null) == null, "null enemy")
	check_eq(RunState.loot_drops_this_wave, 0, "no count")
	var killer := _killer(5000.0)
	killer.reparent(world)
	var orphan := Node3D.new()
	arena.free()
	check(LootDrops.on_enemy_killed(orphan, killer) == null, "no arena and no parent -> no bag")
	check_eq(RunState.loot_drops_this_wave, 0, "failed drops are not counted")
	orphan.free()
