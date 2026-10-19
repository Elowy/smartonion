extends TestCase
## WaveDirector: spawn budget, weighted picks, spawn points, telegraphs, wave end, caps.

const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var arena: EFakes.TestArena
var director: WaveDirector


func before_each() -> void:
	RunState.start_run(1, 777)
	world = EFakes.make_world(tree)
	arena = EFakes.arena_of(world)
	director = WaveDirector.create(arena)
	world.add_child(director)


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null
	arena = null
	director = null


func _enemies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for node in tree.get_nodes_in_group(&"enemies"):
		var e := node as Enemy
		if e != null:
			out.append(e)
	return out


func test_spawn_rate_formula() -> void:
	check_eq(WaveDirector.spawn_rate(1), 0.9, "wave 1")
	check_eq(WaveDirector.spawn_rate(5), 0.9 + 0.08 * 4.0, "wave 5")
	check_eq(WaveDirector.spawn_rate(25, 2.8), (0.9 + 0.08 * 24.0) * 2.8, "wave 25, 4 players")
	RunState.start_run(2, 1)
	director.start_wave(3)
	check_eq(director.spawn_budget_per_second(), (0.9 + 0.08 * 2.0) * 1.6, "2 players: +60%")
	director.stop()


func test_start_wave_sets_state_and_signals() -> void:
	var started: Array[int] = []
	var timer: Array[float] = []
	director.wave_started.connect(func(w: int) -> void: started.append(w))
	director.wave_timer_changed.connect(func(t: float) -> void: timer.append(t))
	director.start_wave(4)
	check(director.is_running(), "running")
	check_eq(RunState.wave, 4, "RunState.wave set")
	check_eq(director.time_left, RunState.wave_duration(4), "duration")
	check_eq(started, [4] as Array[int], "wave_started(4)")
	check(timer.size() == 1 and is_equal_approx(timer[0], 35.0), "timer reported at start")
	timer.clear()
	EFakes.step(director, 1.0)
	check(timer.size() >= 9 and timer.size() <= 11, "timer reported every 0.1 s (%d)" % timer.size())
	if not timer.is_empty():
		check_near(timer.back(), 34.0, 0.02, "last timer value")
	check_near(director.time_left, 34.0, 0.001, "counts down")
	check_eq(director.process_mode, Node.PROCESS_MODE_PAUSABLE, "pauses with the tree")


func test_opening_group_appears_after_telegraph() -> void:
	EFakes.spawn_player(world, Vector3.ZERO)
	director.start_wave(1)
	check_eq(director.pending_groups(), 1, "opening group telegraphed at once")
	check(director.pending_count() >= WaveDirector.OPENING_GROUP_SIZE, "at least 2 enemies")
	check_eq(director.alive_count(), 0, "nothing spawned yet")
	var opening := director.pending_count()
	EFakes.step(director, WaveDirector.TELEGRAPH_TIME - 0.05)
	check_eq(_enemies().size(), 0, "still telegraphing")
	EFakes.step(director, 0.1)
	check(_enemies().size() >= opening, "opening group spawned after the telegraph")
	for e in _enemies():
		check(e.get_parent() == arena.entities, "enemies live under arena.entities")
		check_eq(e.wave, 1, "enemy wave")
		check(arena.get_bounds().has_point(Vector2(e.global_position.x, e.global_position.z)), "inside the arena")


func test_budget_accumulates_and_is_spent() -> void:
	EFakes.spawn_player(world, Vector3.ZERO)
	director.start_wave(3)
	var opening := director.pending_count()
	var seconds := 6.0
	EFakes.step(director, seconds)
	var spawned_or_pending := director.spawned_this_wave + director.pending_count()
	var spent := float(spawned_or_pending - opening)
	check_near(spent + director.budget, WaveDirector.spawn_rate(3) * seconds, 0.05,
			"spent + unspent budget = rate * time")
	check(director.budget >= 0.0, "budget never negative")
	check(director.spawned_this_wave > opening, "regular groups spawned")
	check_eq(director.alive_count(), director.spawned_this_wave, "every spawned enemy alive")


func test_coop_spawns_more() -> void:
	RunState.start_run(4, 777)
	EFakes.spawn_player(world, Vector3.ZERO)
	director.start_wave(3)
	EFakes.step(director, 6.0)
	var four := director.spawned_this_wave + director.pending_count()
	director.stop()
	RunState.start_run(1, 777)
	director.start_wave(3)
	EFakes.step(director, 6.0)
	var solo := director.spawned_this_wave + director.pending_count()
	check(four > solo * 1.8, "4 players: ~2.8x enemies (%d vs %d)" % [four, solo])


func test_eligible_enemies_respect_first_wave() -> void:
	for w in [1, 2, 3, 4, 5, 10, 25]:
		var list := WaveDirector.eligible_enemies(w)
		for d in list:
			check(d.first_wave <= w, "%s not before wave %d" % [d.id, d.first_wave])
		for d in Db.enemies.values():
			var data := d as EnemyData
			if data.first_wave <= w and data.spawn_weight > 0.0:
				check(data in list, "%s eligible at wave %d" % [data.id, w])
	var w1 := WaveDirector.eligible_enemies(1)
	check(w1.size() == 1 and w1[0].id == &"skeleton_grunt", "wave 1: skeletons only")
	var ids: Array[StringName] = []
	for d in WaveDirector.eligible_enemies(4):
		ids.append(d.id)
	check(&"troll_axethrower" not in ids, "trolls only from wave 5")
	check(&"marsh_gurgler" in ids, "gurglers from wave 3")
	var sorted := ids.duplicate()
	sorted.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	check_eq(ids, sorted, "deterministic order")


func test_weighted_pick_never_picks_locked_types() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for w in range(1, 8):
		var list := WaveDirector.eligible_enemies(w)
		for _i in 200:
			var d := WaveDirector.pick_weighted(list, rng)
			check(d != null and d.first_wave <= w, "picked an unlocked enemy")


func test_weighted_pick_distribution() -> void:
	var a := EFakes.enemy_data()
	a.id = &"a"
	a.spawn_weight = 1.0
	var b := EFakes.enemy_data()
	b.id = &"b"
	b.spawn_weight = 3.0
	var never := EFakes.enemy_data()
	never.id = &"never"
	never.spawn_weight = 0.0
	var list: Array[EnemyData] = [a, never, b]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var counts := {&"a": 0, &"b": 0, &"never": 0}
	for _i in 4000:
		var d := WaveDirector.pick_weighted(list, rng)
		counts[d.id] += 1
	check_eq(counts[&"never"], 0, "zero weight never picked")
	check_near(float(counts[&"a"]) / 4000.0, 0.25, 0.03, "weight 1 of 4")
	check_near(float(counts[&"b"]) / 4000.0, 0.75, 0.03, "weight 3 of 4")
	var empty: Array[EnemyData] = []
	check(WaveDirector.pick_weighted(empty, rng) == null, "empty list -> null")


func test_group_size_in_range() -> void:
	var data := Db.get_enemy(&"candlekin")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var seen := {}
	for _i in 300:
		var n := WaveDirector.roll_group_size(data, rng)
		check(n >= data.group_min and n <= data.group_max, "size %d in range" % n)
		seen[n] = true
	check(seen.has(data.group_min) and seen.has(data.group_max), "both ends reachable")
	var odd := EFakes.enemy_data()
	odd.group_min = 0
	odd.group_max = 0
	check_eq(WaveDirector.roll_group_size(odd, rng), 1, "at least one")


func test_spawn_point_distance_rule() -> void:
	var rng := RandomNumberGenerator.new()
	var players: Array[Vector3] = [Vector3.ZERO, Vector3(10.0, 0.0, 0.0)]
	# First two candidates are too close to a player, the third is fine.
	arena.scripted_points = [Vector3(2.0, 0.0, 0.0), Vector3(12.0, 0.0, 3.0), Vector3(-8.0, 0.0, 0.0)]
	var p := WaveDirector.pick_spawn_point(arena, rng, players)
	check(p.is_equal_approx(Vector3(-8.0, 0.0, 0.0)), "first point >= 6 m from every player")
	# Nothing far enough: the candidate farthest from its nearest player wins.
	var near: Array[Vector3] = []
	for i in WaveDirector.SPAWN_POINT_TRIES:
		near.append(Vector3(1.0 + 0.1 * i, 0.0, 0.0))
	near[3] = Vector3(0.0, 0.0, 5.0)
	arena.scripted_points = near
	p = WaveDirector.pick_spawn_point(arena, rng, [Vector3.ZERO] as Array[Vector3])
	check(p.is_equal_approx(Vector3(0.0, 0.0, 5.0)), "farthest fallback")
	check(arena.scripted_points.is_empty(), "used every try")
	# Random candidates with one player in the middle.
	rng.seed = 11
	var bounds := arena.get_bounds().grow(-WaveDirector.SPAWN_MARGIN + 0.001)
	for _i in 100:
		var q := WaveDirector.pick_spawn_point(arena, rng, [Vector3.ZERO] as Array[Vector3])
		check(Vector2(q.x, q.z).length() >= WaveDirector.MIN_PLAYER_DISTANCE, "random point far enough")
		check(bounds.has_point(Vector2(q.x, q.z)), "random point inside the margin")
	# No players: any point.
	arena.scripted_points = [Vector3(1.0, 0.0, 1.0)]
	p = WaveDirector.pick_spawn_point(arena, rng, [] as Array[Vector3])
	check(p.is_equal_approx(Vector3(1.0, 0.0, 1.0)), "no players: first candidate")


func test_spawned_groups_keep_away_from_players() -> void:
	var player := EFakes.spawn_player(world, Vector3(1.0, 0.0, -1.0))
	var spawn_positions: Array[Vector3] = []
	director.enemy_spawned.connect(func(e: Enemy) -> void: spawn_positions.append(e.global_position))
	director.start_wave(6)
	EFakes.step(director, 8.0)
	check(spawn_positions.size() >= 8, "enemies spawned (%d)" % spawn_positions.size())
	for pos in spawn_positions:
		check(EFakes.flat_distance(pos, player.global_position) >= WaveDirector.MIN_PLAYER_DISTANCE - 1.5,
				"spawned away from the player (%s)" % pos)


func test_wave_end_banks_loot_and_despawns() -> void:
	EFakes.spawn_player(world, Vector3(30.0, 0.0, 30.0))  # far away: nothing gets collected
	var cleared: Array[int] = []
	director.wave_cleared.connect(func(w: int) -> void: cleared.append(w))
	director.start_wave(2)
	EFakes.step(director, 3.0)
	check(director.alive_count() > 0, "enemies alive before the end")
	var p1 := Pickup.create(3, 2)
	var p2 := Pickup.create(1, 1)
	arena.entities.add_child(p1)
	arena.entities.add_child(p2)
	var axe := Projectile.create(Projectile.TEAM_ENEMIES, 2.0, false, Vector3.FORWARD, 9.0, 14.0)
	arena.entities.add_child(axe)
	var gold_before := RunState.gold
	var xp_before := RunState.xp
	var enemies := _enemies()
	director.time_left = 0.05
	EFakes.step(director, 0.1)
	check_eq(cleared, [2] as Array[int], "wave_cleared(2) once")
	check(not director.is_running(), "stopped")
	check_eq(director.alive_count(), 0, "no enemies left in the group")
	for e in enemies:
		check(e.is_queued_for_deletion(), "enemy despawned")
	check_eq(RunState.kills, 0, "despawn is not a kill")
	check_eq(EFakes.live_children_of_type(world, Pickup).size(), 0, "no new loot from despawns")
	check_eq(RunState.gold, gold_before + 4, "pickups banked (gold)")
	check_eq(RunState.xp, xp_before + 3, "pickups banked (xp)")
	check(p1.is_queued_for_deletion() and p2.is_queued_for_deletion(), "pickups removed")
	check(axe.is_queued_for_deletion(), "enemy axes in flight removed")
	check_eq(director.pending_count(), 0, "telegraphs cancelled")
	# Nothing happens afterwards.
	EFakes.step(director, 2.0)
	check_eq(_enemies().size(), 0, "no spawns after the end")
	check_eq(cleared.size(), 1, "cleared only once")
	director.stop()  # Main calls stop() again: harmless


func test_stop_cancels_telegraphs() -> void:
	director.start_wave(1)
	check(director.pending_count() > 0, "opening telegraph pending")
	var cleared: Array[int] = []
	director.wave_cleared.connect(func(w: int) -> void: cleared.append(w))
	director.stop()
	check(not director.is_running(), "stopped")
	check_eq(director.pending_count(), 0, "pending cleared")
	EFakes.step(director, 2.0)
	check_eq(_enemies().size(), 0, "telegraphed group never appears")
	check_eq(cleared.size(), 0, "stop() alone does not clear the wave")


func test_max_enemies_respected() -> void:
	EFakes.spawn_player(world, Vector3.ZERO)
	var dummies: Array[Node3D] = []
	for i in WaveDirector.MAX_ENEMIES - 3:
		var n := Node3D.new()
		n.add_to_group(&"enemies")
		arena.entities.add_child(n)
		dummies.append(n)
	director.start_wave(12)
	for _i in 8:
		EFakes.step(director, 0.5)
		check(director.alive_count() + director.pending_count() <= WaveDirector.MAX_ENEMIES,
				"alive + pending <= MAX_ENEMIES")
	check_eq(director.alive_count() + director.pending_count(), WaveDirector.MAX_ENEMIES, "filled up to the cap")
	# Free room: spawning resumes (enough time for a few groups at this wave's rate).
	for i in 20:
		dummies[i].free()
	EFakes.step(director, 3.0 + 8.0 / WaveDirector.spawn_rate(12) + WaveDirector.TELEGRAPH_TIME)
	check(director.spawned_this_wave > 3, "spawns resume when room frees up")
	check(director.alive_count() + director.pending_count() <= WaveDirector.MAX_ENEMIES, "still capped")


func test_copes_with_enemies_freed_any_time() -> void:
	EFakes.spawn_player(world, Vector3.ZERO)
	director.start_wave(5)
	EFakes.step(director, 3.0)
	var enemies := _enemies()
	check(enemies.size() > 0, "spawned")
	for e in enemies:
		e.free()
	check_eq(director.alive_count(), 0, "count follows frees")
	EFakes.step(director, 2.0)
	check(director.is_running(), "still running")
	director.time_left = 0.01
	EFakes.step(director, 0.05)
	check(not director.is_running(), "ended cleanly")


func test_spawned_enemies_fight() -> void:
	# Integration: spawned enemies walk to the player and hurt it.
	var player := EFakes.spawn_player(world, Vector3.ZERO)
	arena.scripted_points = [Vector3(7.0, 0.0, 0.0)]
	director.start_wave(1)
	EFakes.step(director, 1.05)
	var nodes: Array[Node] = []
	for e in _enemies():
		nodes.append(e)
	check(nodes.size() >= 2, "opening group spawned")
	EFakes.step_all(nodes, 4.0)
	check(player.fake_hits.size() > 0, "enemies reached the player and dealt contact damage")


## Spawn telegraphs prefer the HUD-safe visible ground (still >= 6 m from every player) and
## fall back to the whole arena when nothing on screen is far enough.
func test_spawn_point_prefers_the_screen() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var players: Array[Vector3] = [Vector3(10.0, 0.0, 0.0)]
	var view := Rect2(-12.0, -6.0, 14.0, 10.0)
	var area := arena.get_bounds().grow(-WaveDirector.SPAWN_MARGIN)
	for _i in 100:
		var p := WaveDirector.pick_spawn_point(arena, rng, players, WaveDirector.MIN_PLAYER_DISTANCE,
			WaveDirector.SPAWN_POINT_TRIES, view)
		check(view.grow(0.001).has_point(Vector2(p.x, p.z)), "on screen (%s)" % p)
		check(area.grow(0.001).has_point(Vector2(p.x, p.z)), "inside the arena margin (%s)" % p)
		check(Vector2(p.x - 10.0, p.z).length() >= WaveDirector.MIN_PLAYER_DISTANCE, "away from the player (%s)" % p)
	# The visible part sticks out of the arena: only the overlap is used.
	var half_out := Rect2(area.end.x - 3.0, -2.0, 20.0, 4.0)
	for _i in 30:
		var q := WaveDirector.pick_spawn_point(arena, rng, [] as Array[Vector3], WaveDirector.MIN_PLAYER_DISTANCE,
			WaveDirector.SPAWN_POINT_TRIES, half_out)
		check(q.x <= area.end.x + 0.001 and q.x >= area.end.x - 3.001, "clipped to the arena (%s)" % q)
	# The whole view is too close to the player: fall back to the arena (scripted candidates).
	var crowded := Rect2(9.0, -1.0, 2.0, 2.0)
	arena.scripted_points = [Vector3(9.0, 0.0, 0.0), Vector3(-8.0, 0.0, 3.0)]
	var f := WaveDirector.pick_spawn_point(arena, rng, players, WaveDirector.MIN_PLAYER_DISTANCE,
		WaveDirector.SPAWN_POINT_TRIES, crowded)
	check(f.is_equal_approx(Vector3(-8.0, 0.0, 3.0)), "falls back to anywhere far enough (%s)" % f)


func test_director_spawns_where_the_camera_looks() -> void:
	var rig := CameraRig.new()
	arena.add_child(rig)
	arena.camera = rig
	EFakes.spawn_player(world, Vector3(-12.0, 0.0, 6.0))
	rig.snap()
	# Pin the view (headless viewports are square): the hero stands outside its safe part.
	rig.focus = Vector3.ZERO
	rig.distance = 30.0
	var safe := rig.get_safe_ground_rect()
	check(safe.has_area(), "camera has a safe area")
	var inside := 0
	for _i in 40:
		var p := director.find_spawn_point()
		if safe.grow(0.001).has_point(Vector2(p.x, p.z)):
			inside += 1
	check_eq(inside, 40, "telegraphs land on screen outside the HUD")
	arena.camera = null
	rig.free()


## Groups never spawn on the Spirit Healer: a revived hero must not pop up inside one.
func test_spawn_point_avoids_the_spirit_healer() -> void:
	var healer := SpiritHealer.create()
	arena.add_child(healer)
	arena.spirit_healer = healer
	healer.global_position = Vector3(2.0, 0.0, 1.0)
	for _i in 60:
		var p := director.find_spawn_point()
		check(Vector2(p.x - 2.0, p.z - 1.0).length() >= WaveDirector.MIN_PLAYER_DISTANCE - 0.001,
				"away from the healer (%s)" % p)
	arena.spirit_healer = null
	healer.free()


func test_stop_ends_ability_areas() -> void:
	var area := AbilityArea.new()
	area.duration = 10.0
	EFakes.arena_of(world).entities.add_child(area)
	check(area.is_in_group(&"ability_areas"), "areas join the group")
	director.stop()
	check(area.is_queued_for_deletion(), "a Hailstorm does not survive the wave")
