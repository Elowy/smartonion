extends TestCase
## Pickup: magnet range, collection (Gold Find), nearest player, banking, merging, look.

const EFakes := preload("res://tests/enemies_fakes.gd")

var world: Node3D
var arena: EFakes.TestArena


func before_each() -> void:
	RunState.start_run(1, 31)
	world = EFakes.make_world(tree)
	arena = EFakes.arena_of(world)


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null
	arena = null


func _drop(gold: int, xp: int, pos: Vector3) -> Pickup:
	var p := Pickup.create(gold, xp)
	arena.entities.add_child(p)
	p.global_position = pos
	return p


func test_create_builds_coin_and_joins_group() -> void:
	var p := _drop(1, 1, Vector3.ZERO)
	check(p.is_in_group(&"pickups"), "in pickups group")
	check(p.is_idle(), "idle on the ground")
	var visual := p.get_node_or_null(^"Visual") as Node3D
	check(visual != null, "has a visual")
	var coin := p.get_node_or_null(^"Visual/Coin") as MeshInstance3D
	check(coin != null and coin.mesh is CylinderMesh, "gold is a coin")
	var orb := _drop(0, 2, Vector3(1, 0, 0))
	var body := orb.get_node_or_null(^"Visual/Coin") as MeshInstance3D
	check(body != null and body.mesh is SphereMesh, "xp-only loot is an orb")
	p._process(0.1)  # spin / bob without errors
	check(visual.position.y > 0.1, "hovers above the ground")


func test_collected_by_player_in_range_with_gold_find() -> void:
	var player := EFakes.spawn_player(world, Vector3.ZERO)
	player.stats.set_source(&"test", {Stats.GOLD_FIND: 50.0})
	var p := _drop(2, 3, Vector3(2.0, 0.0, 0.0))
	var gold_before := RunState.gold
	var xp_before := RunState.xp
	p._physics_process(1.0 / 60.0)
	check(p.target == player, "attracted by the player within 3 m")
	check(p.global_position.x < 2.0, "moves towards the player")
	EFakes.step(p, 1.0)
	check(p.is_collected(), "collected")
	check(p.is_queued_for_deletion(), "freed")
	check(not p.is_in_group(&"pickups"), "left the group")
	check_eq(RunState.gold, gold_before + 3, "2 gold * 1.5 gold find")
	check_eq(RunState.xp, xp_before + 3, "xp to the shared bar")


func test_out_of_range_stays_until_range_grows() -> void:
	var player := EFakes.spawn_player(world, Vector3.ZERO)
	var p := _drop(1, 1, Vector3(5.0, 0.0, 0.0))
	EFakes.step(p, 0.5)
	check(p.is_idle(), "5 m > 3 m pickup range")
	check_near(p.global_position.x, 5.0, 0.0001, "does not move")
	player.stats.set_source(&"test", {Stats.PICKUP_RANGE: 50.0})
	EFakes.step(p, 0.5)
	check(p.is_idle(), "+50% pickup range = 4.5 m < 5 m")
	player.stats.set_source(&"test", {Stats.PICKUP_RANGE: 100.0})
	EFakes.step(p, 1.0)
	check(p.is_collected(), "collected with +100% = 6 m range")


func test_downed_player_does_not_attract() -> void:
	var player := EFakes.spawn_player(world, Vector3.ZERO)
	player.downed = true
	var p := _drop(1, 1, Vector3(1.0, 0.0, 0.0))
	EFakes.step(p, 0.5)
	check(p.is_idle() and not p.is_collected(), "ghosts do not collect")
	# A flying pickup is released when its target goes down.
	player.downed = false
	p._physics_process(1.0 / 60.0)
	check(p.target == player, "attracted again")
	player.downed = true
	p._physics_process(1.0 / 60.0)
	check(p.target == null, "released")


func test_nearest_player_collects() -> void:
	var far := EFakes.spawn_player(world, Vector3(-2.5, 0.0, 0.0))
	var near := EFakes.spawn_player(world, Vector3(1.5, 0.0, 0.0))
	near.stats.set_source(&"test", {Stats.GOLD_FIND: 100.0})
	var p := _drop(2, 0, Vector3.ZERO)
	p._physics_process(1.0 / 60.0)
	check(p.target == near, "nearest player in range")
	check(p.target != far, "not the farther one")
	EFakes.step(p, 1.0)
	check_eq(RunState.gold, 4, "collector's gold find counts")


func test_small_gold_find_adds_up_over_pickups() -> void:
	# +10% Gold Find on ten 1-gold coins = 11 gold (it used to round to 1 per coin = 10).
	var player := EFakes.spawn_player(world, Vector3.ZERO, 0)
	player.stats.set_source(&"test", {Stats.GOLD_FIND: 10.0})
	for i in 10:
		_drop(1, 0, Vector3(0.2, 0.0, 0.0)).collect(player)
	check_eq(RunState.gold, 11, "10 coins * 1.1")
	check_near(RunState.gold_remainder(0), 0.0, 0.0001, "nothing left over")
	# +50% no longer doubles every coin: 1, then 2 (1.5 + 0.5 carried), then 1 ...
	var greedy := EFakes.spawn_player(world, Vector3(4.0, 0.0, 0.0), 1)
	greedy.stats.set_source(&"test", {Stats.GOLD_FIND: 50.0})
	var before := RunState.gold
	_drop(1, 0, Vector3(4.2, 0.0, 0.0)).collect(greedy)
	check_eq(RunState.gold, before + 1, "first coin: 1 (0.5 kept)")
	_drop(1, 0, Vector3(4.2, 0.0, 0.0)).collect(greedy)
	check_eq(RunState.gold, before + 3, "second coin: 1.5 + 0.5 = 2")
	check_near(RunState.gold_remainder(0), 0.0, 0.0001, "the other slot's fraction is separate")


func test_collect_to_bank() -> void:
	var player := EFakes.spawn_player(world, Vector3(10.0, 0.0, 0.0))
	player.stats.set_source(&"test", {Stats.GOLD_FIND: 100.0})
	var p := _drop(5, 2, Vector3.ZERO)
	p.collect_to_bank()
	check_eq(RunState.gold, 5, "banked at the wave end: no gold find without a collector")
	check_eq(RunState.xp, 2, "xp banked")
	check(p.is_queued_for_deletion(), "freed")
	p.collect_to_bank()
	p.collect(player)
	check_eq(RunState.gold, 5, "never counted twice")


func test_drop_merges_when_crowded() -> void:
	var a := Pickup.drop(arena.entities, 1, 1, Vector3(3.0, 0.0, 3.0))
	check(a != null and a.get_parent() == arena.entities, "drop creates a pickup")
	check(a.global_position.is_equal_approx(Vector3(3.0, 0.0, 3.0)), "at the drop position")
	check(Pickup.drop(arena.entities, 0, 0, Vector3.ZERO) == null, "empty loot drops nothing")
	# Fill up to the merge threshold, spread over the arena.
	for i in Pickup.MERGE_THRESHOLD - 1:
		_drop(1, 1, Vector3(-15.0 + float(i % 30), 0.0, -9.0 + float(i / 30) * 1.0))
	check_eq(tree.get_node_count_in_group(&"pickups"), Pickup.MERGE_THRESHOLD, "at the threshold")
	var host := Pickup.drop(arena.entities, 4, 2, Vector3(3.5, 0.0, 3.0))
	check(host == a, "merged into the nearby pickup")
	check_eq(a.gold, 5, "gold summed")
	check_eq(a.xp, 3, "xp summed")
	check_eq(tree.get_node_count_in_group(&"pickups"), Pickup.MERGE_THRESHOLD, "no new node")
	var visual := a.get_node(^"Visual") as Node3D
	check(visual.scale.x > 1.0, "merged pickups look bigger")
	# Nothing idle nearby: still creates a new one below the hard cap.
	var lone := Pickup.drop(arena.entities, 1, 1, Vector3(14.0, 0.0, 9.0))
	check(lone != a and lone.get_parent() == arena.entities, "far away: new pickup")


func test_flying_pickup_survives_freed_target() -> void:
	failures.append("aborted by a script error")
	var player := EFakes.spawn_player(world, Vector3.ZERO)
	var p := _drop(1, 1, Vector3(2.5, 0.0, 0.0))
	p._physics_process(1.0 / 60.0)
	check(p.target == player, "flying to the player")
	player.free()
	EFakes.step(p, 0.2)
	check(p.is_idle(), "released the freed target")
	check(not p.is_collected(), "not collected by nobody")
	var x := p.global_position.x
	EFakes.step(p, 0.2)
	check_near(p.global_position.x, x, 0.0001, "stops moving")
	failures.erase("aborted by a script error")
