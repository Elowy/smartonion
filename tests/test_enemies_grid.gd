extends TestCase
## Performance helpers of the enemies module: EnemyGrid (shared spatial hash: exact queries,
## crowd separation), LivingPlayers (per-tick player snapshot), the pickup idle stagger and
## the WeaponRunner no-target retry throttle.

const EFakes := preload("res://tests/enemies_fakes.gd")
const PFakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 777)
	world = EFakes.make_world(tree)
	EnemyGrid.mark_dirty()


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null
	EnemyGrid.mark_dirty()


func _fake_enemy(pos: Vector3, radius: float) -> PFakes.FakeEnemy:
	var e := PFakes.FakeEnemy.new()
	e.radius = radius
	e.add_to_group(&"enemies")
	EFakes.arena_of(world).entities.add_child(e)
	e.global_position = pos
	return e


func test_grid_queries_match_a_full_scan() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 60:
		var e := _fake_enemy(Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-10, 10)),
				rng.randf_range(0.3, 0.6))
		e.fake_dead = i % 7 == 0
	for k in 40:
		var origin := Vector3(rng.randf_range(-18, 18), 0, rng.randf_range(-12, 12))
		var reach := rng.randf_range(0.5, 12.0)
		var group := tree.get_nodes_in_group(&"enemies")
		check(EnemyGrid.nearest(tree, origin, reach) == WeaponRunner.nearest_enemy(group, origin, reach),
				"nearest() == full scan (query %d)" % k)
		# gather_touching: a superset of the exact answer, in group order.
		var got := EnemyGrid.gather_around(tree, origin, reach)
		var last := -1
		for node in got:
			var idx := group.find(node)
			check(idx > last, "group order")
			last = idx
		for node in group:
			var e := node as Enemy
			var d := WeaponRunner.flat(e.global_position - origin).length()
			if d <= reach + e.radius:
				check(node in got, "enemy touching the circle is gathered (query %d)" % k)
	# Same hits as the full-scan arc helper.
	var nodes := tree.get_nodes_in_group(&"enemies")
	var full := WeaponRunner.enemies_in_arc(nodes, Vector3.ZERO, Vector3.RIGHT, 6.0, 120.0)
	var near := WeaponRunner.enemies_in_arc(EnemyGrid.gather_around(tree, Vector3.ZERO, 6.0),
			Vector3.ZERO, Vector3.RIGHT, 6.0, 120.0)
	check_eq(near, full, "melee arc through the grid == full scan (same order)")


func test_grid_follows_spawns_and_removals_in_the_same_frame() -> void:
	var a := _fake_enemy(Vector3(3, 0, 0), 0.45)
	check(EnemyGrid.nearest(tree, Vector3.ZERO, 5.0) == a, "first enemy found")
	var b := _fake_enemy(Vector3(1, 0, 0), 0.45)
	check(EnemyGrid.nearest(tree, Vector3.ZERO, 5.0) == b, "an enemy added this frame is found")
	b.get_parent().remove_child(b)
	b.free()
	check(EnemyGrid.nearest(tree, Vector3.ZERO, 5.0) == a, "a freed enemy is never returned")
	a.fake_dead = true
	check(EnemyGrid.nearest(tree, Vector3.ZERO, 5.0) == null, "dead enemies are skipped")


func test_overlapping_enemies_push_apart() -> void:
	var data := EFakes.enemy_data()
	data.move_speed = 0.0
	data.contact_damage = 0.0
	var a := EFakes.spawn_enemy(world, data, Vector3(0.0, 0.0, 0.0))
	var b := EFakes.spawn_enemy(world, data, Vector3(0.3, 0.0, 0.1))
	check_eq(a.collision_mask, Enemy.COLLISION_MASK_WORLD, "no physical enemy <-> enemy collision")
	EFakes.step_all([a, b] as Array[Node], 1.0)
	var d := EFakes.flat_distance(a.global_position, b.global_position)
	check(d >= a.radius + b.radius - 0.03, "separated to about the contact distance (%.3f)" % d)
	check(d < a.radius + b.radius + 0.2, "not flung apart (%.3f)" % d)
	check_near(a.global_position.y, 0.0, 0.0001, "stays on the ground plane")


func test_walker_slides_around_a_blocker() -> void:
	EFakes.spawn_player(world, Vector3(0.0, 0.0, -6.0))
	var still := EFakes.enemy_data()
	still.move_speed = 0.0
	var blocker := EFakes.spawn_enemy(world, still, Vector3(0.0, 0.0, -1.5))
	blocker.apply_stun(100.0)  # stands still, is not pushed
	var walker := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3(0.15, 0.0, 0.0))
	var min_d := INF
	var t := 0.0
	while t < 3.0:
		blocker._physics_process(DT)
		walker._physics_process(DT)
		min_d = minf(min_d, EFakes.flat_distance(walker.global_position, blocker.global_position))
		t += DT
	check(min_d > (walker.radius + blocker.radius) * 0.75, "does not walk through it (min %.3f)" % min_d)
	check(walker.global_position.z < -2.5, "got past it towards the player (z %.2f)" % walker.global_position.z)
	check_near(blocker.global_position.x, 0.0, 0.0001, "a stunned blocker stays put")


func test_living_players_snapshot() -> void:
	var p := EFakes.spawn_player(world, Vector3(2.0, 0.0, 1.0))
	p.stats.set_source(&"test", {Stats.PICKUP_RANGE: 100.0})
	var s1 := LivingPlayers.refresh(world, -1)
	check_eq(LivingPlayers.count, 1, "one living player")
	check_near(LivingPlayers.pos_x[0], 2.0, 0.0001, "position x")
	check_near(LivingPlayers.pos_z[0], 1.0, 0.0001, "position z")
	check_near(LivingPlayers.pickup_range_sq[0], pow(p.stats.pickup_range(), 2.0), 0.0001, "range squared")
	check_eq(LivingPlayers.refresh(world, -1), s1, "same tick, new consumer: no rebuild")
	p.downed = true
	LivingPlayers.mark_dirty()
	LivingPlayers.refresh(world, -1)
	check_eq(LivingPlayers.count, 0, "rebuilt after mark_dirty: the downed player is gone")
	p.downed = false
	var s2 := LivingPlayers.refresh(world, -1)
	check_eq(LivingPlayers.count, 0, "unchanged snapshot for a consumer that has not used it")
	LivingPlayers.refresh(world, s2)
	check_eq(LivingPlayers.count, 1, "a consumer asking twice in one frame gets a fresh one")


func test_idle_pickups_stagger_when_crowded() -> void:
	var player := EFakes.spawn_player(world, Vector3.ZERO)
	for i in Pickup.IDLE_STAGGER_THRESHOLD:
		var far := Pickup.create(1, 0)
		EFakes.arena_of(world).entities.add_child(far)
		far.global_position = Vector3(-15.0 + float(i % 30), 0.0, 9.0)
	var p := Pickup.create(1, 0)
	EFakes.arena_of(world).entities.add_child(p)
	p.global_position = Vector3(1.0, 0.0, 0.0)
	var calls := 0
	while p.target == null and not p.is_collected() and calls < 10:
		p._physics_process(DT)
		calls += 1
	check(p.target == player or p.is_collected(), "found its collector")
	check(calls <= Pickup.IDLE_CHECK_TICKS, "within IDLE_CHECK_TICKS ticks (%d)" % calls)
	# An idle pickup only looks every IDLE_CHECK_TICKS ticks.
	var q := Pickup.create(1, 0)
	EFakes.arena_of(world).entities.add_child(q)
	q.global_position = Vector3(6.0, 0.0, 0.0)
	for i in Pickup.IDLE_CHECK_TICKS:
		q._physics_process(DT)
	player.global_position = Vector3(5.5, 0.0, 0.0)
	var waited := 0
	while q.target == null and not q.is_collected() and waited < 10:
		q._physics_process(DT)
		waited += 1
	check(q.target == player or q.is_collected(), "picked up later")
	check(waited <= Pickup.IDLE_CHECK_TICKS, "at most IDLE_CHECK_TICKS ticks late (%d)" % waited)


func test_weapon_retries_a_missing_target_every_retry_interval() -> void:
	var pworld := PFakes.make_world(tree)
	var p := PFakes.spawn_player(pworld, 0, &"warrior")
	var runner := p.weapons[0]
	var e := PFakes.spawn_enemy(pworld, Vector3(6.0, 0.0, 0.0))
	check(not runner.tick(DT), "nothing in sword range")
	# Walks into range without the enemy count changing (teleported here: tell the grid).
	e.global_position = Vector3(1.5, 0.0, 0.0)
	EnemyGrid.mark_dirty()
	var ticks := 0
	while not runner.tick(DT) and ticks < 30:
		ticks += 1
	check_eq(e.fake_hits(), 1, "attacks once the retry comes")
	check(ticks >= roundi(WeaponRunner.NO_TARGET_RETRY / DT) - 2, "not searched every tick (%d)" % ticks)
	check(ticks <= roundi(WeaponRunner.NO_TARGET_RETRY / DT) + 1, "searched again after the interval (%d)" % ticks)
	# A new enemy triggers a search at once.
	runner.reset()
	e.global_position = Vector3(6.0, 0.0, 0.0)
	EnemyGrid.mark_dirty()
	check(not runner.tick(DT), "out of range again")
	var other := PFakes.spawn_enemy(pworld, Vector3(-1.2, 0.0, 0.0))
	check(runner.tick(DT), "a spawned enemy is attacked without waiting")
	check_eq(other.fake_hits(), 1, "hit the new one")
	PFakes.free_world(pworld)


func test_count_around_matches_a_full_scan() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 50:
		_fake_enemy(Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-10, 10)), 0.4)
	for k in 40:
		var center := Vector3(rng.randf_range(-18, 18), 0, rng.randf_range(-12, 12))
		var radius := rng.randf_range(0.5, 8.0)
		var expected := 0
		for node in tree.get_nodes_in_group(&"enemies"):
			if WeaponRunner.flat((node as Node3D).global_position - center).length() <= radius:
				expected += 1
		check_eq(EnemyGrid.count_around(tree, center, radius), expected, "centres within the radius (query %d)" % k)
