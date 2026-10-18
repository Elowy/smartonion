extends TestCase
## M6b ENV (GDD 13, 16.1): the five EnvironmentData files, the seed-derived roll, the decor sets
## (ArenaThemes), the hazard director and its four hazards (Grasping Hands, Bog Pools, Lava Vents,
## Falling Icicles: damage from the Skeleton Grunt at the wave, half rate on boss waves, the bots' steering,
## the environment rng), Player.apply_root, Main's wiring, the "Rolling the arena..." screen and the
## environment on the end screen and the run card.

const EFakes := preload("res://tests/enemies_fakes.gd")
const PFakes := preload("res://tests/player_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var main: Main
var nodes: Array[Node] = []
var _roll_enabled_before := false


func before_each() -> void:
	UiFakes.reset_players()
	RunState.environment_roller = Callable()
	RunState.start_run(4, 4242, RunState.MODE_NORMAL, false, &"forest_ruin")
	world = EFakes.make_world(tree)
	_roll_enabled_before = EnvironmentRollScreen.enabled


func after_each() -> void:
	EnvironmentRollScreen.enabled = _roll_enabled_before
	RunState.environment_roller = Callable()
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()
	EFakes.free_world(tree, world)
	world = null
	tree.paused = false
	UiFakes.reset_players()
	Db.reload()
	RunState.start_run(1, 1)
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


# --- Helpers -----------------------------------------------------------------------------------

func _env(id: StringName) -> EnvironmentData:
	return Db.get_environment(id)


func _entities() -> Node3D:
	return EFakes.arena_of(world).entities


func _hero(pos: Vector3, slot_index: int = -1) -> EFakes.FakePlayer:
	return EFakes.spawn_player(world, pos, slot_index)


func _real_hero(index: int, pos: Vector3, class_id: StringName = &"warrior") -> Player:
	var p := Player.create(PFakes.make_slot(index, class_id))
	p.stats.remove_source(&"base")
	_entities().add_child(p)
	p.global_position = pos
	Enemy.invalidate_player_cache()
	return p


func _bot(pos: Vector3, index: int = 0) -> Player:
	var slot := PlayerSlot.new(index, BotInput.new("bot:b%d" % index, 3 + index), PlayerManager.PLAYER_COLORS[index])
	slot.class_data = Db.get_class_data(&"mage")
	var p := Player.create(slot)
	_entities().add_child(p)
	p.global_position = pos
	Enemy.invalidate_player_cache()
	return p


func _bot_move(p: Player) -> Vector2:
	var bot := p.slot.input as BotInput
	bot.think(DT)
	return bot.get_move()


func _director() -> WaveDirector:
	var d := WaveDirector.create(EFakes.arena_of(world))
	world.add_child(d)
	return d


## A running wave of [param wave] with the hazard director of environment [param id] under it.
func _hazard_director(id: StringName, wave: int = 5) -> EnvironmentHazards:
	var d := _director()
	var hz := EnvironmentHazards.create(d, _env(id))
	d.add_child(hz)
	d.start_wave(wave)
	return hz


func _hazards_of(script_class: GDScript) -> Array[Node]:
	var out: Array[Node] = []
	for n in tree.get_nodes_in_group(EnemyHazard.GROUP):
		if is_instance_of(n, script_class) and not n.is_queued_for_deletion():
			out.append(n)
	return out


func _step(hz: Node, seconds: float) -> void:
	EFakes.step(hz, seconds)


func _make_main(opts: LaunchOptions = null) -> Main:
	main = Main.create(opts if opts != null else LaunchOptions.new())
	tree.root.add_child(main)
	return main


func _free_main() -> void:
	if main != null and is_instance_valid(main):
		main._teardown_run()
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	UiFakes.reset_players()
	Enemy.invalidate_player_cache()


func _run_with_bots(count: int, opts: LaunchOptions = null) -> void:
	_make_main(opts)
	for i in count:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)
	main.start_run()


func _decor_instances(arena: Arena) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for c in arena.get_node("Decor").get_children():
		if c is GeometryInstance3D:
			out.append(c)
	return out


# --- Data ---------------------------------------------------------------------------------------

func test_the_five_environments_are_loaded_in_roll_order() -> void:
	check_eq(Db.environment_ids, [&"forest_ruin", &"cemetery", &"swamp", &"volcano", &"ice_cave"] as Array[StringName], "the roll order")
	var names := {&"forest_ruin": "Forest Ruin", &"cemetery": "Cemetery", &"swamp": "Swamp", &"volcano": "Volcano", &"ice_cave": "Ice Cave"}
	var hazards := {&"forest_ruin": &"", &"cemetery": &"grasping_hands", &"swamp": &"bog_pools",
			&"volcano": &"lava_vents", &"ice_cave": &"falling_icicles"}
	for id in Db.environment_ids:
		var env := _env(id)
		check_eq(env.id, id, "%s: the id is the file's" % id)
		check_eq(env.display_name, names[id], "%s: display name" % id)
		check(env.description != "", "%s: a card description" % id)
		check_eq(env.hazard_id, hazards[id], "%s: hazard" % id)
		check_eq(env.has_hazard(), hazards[id] != &"", "%s: has_hazard" % id)
		check(env.roll_weight > 0.0, "%s: can be rolled" % id)
		if env.has_hazard():
			check(env.hazard_id in EnvironmentHazards.HAZARD_IDS, "%s: the director knows the hazard" % id)
			check(env.hazard_name != "" and env.hazard_text != "", "%s: the card names its hazard" % id)
			check(env.decor_id in ArenaThemes.set_ids(), "%s: has its own decor set" % id)
		else:
			check_eq(env.decor_id, &"forest", "the Forest Ruin is today's decor")
	check_eq(EnvironmentHazards.HAZARD_IDS.size(), 4, "four hazards")
	check_eq(_env(&"forest_ruin").sky_color, EnvironmentData.new().sky_color, "the Forest Ruin is the data class's defaults")
	for id in [&"cemetery", &"swamp", &"volcano", &"ice_cave"]:
		var env := _env(id)
		var def := EnvironmentData.new()
		check(env.sky_color != def.sky_color and env.grass_mid != def.grass_mid and env.fog_color != def.fog_color,
				"%s has its own palette" % id)


func test_each_environment_builds_an_arena_of_the_same_size() -> void:
	for id in Db.environment_ids:
		var arena := Arena.create(_env(id))
		nodes.append(arena)
		check(arena.environment == _env(id), "%s: the arena keeps its environment" % id)
		check_eq(arena.get_bounds(), Rect2(-Arena.SIZE / 2.0, Arena.SIZE), "%s: the playable rectangle never changes" % id)
		check_eq(arena.world_environment.environment.background_color, _env(id).sky_color, "%s: the sky" % id)
		check_eq(arena.sun.light_color, _env(id).sun_color, "%s: the sun" % id)
		check(arena.get_node_or_null(^"Decor") != null, "%s: has decor" % id)


# --- The roll -----------------------------------------------------------------------------------

func test_the_roll_covers_every_environment_roughly_evenly() -> void:
	var counts := {}
	for seed_value in 1000:
		var id := RunState.environment_for_seed(seed_value)
		counts[id] = int(counts.get(id, 0)) + 1
	for id in Db.environment_ids:
		check(int(counts.get(id, 0)) > 140, "%s is rolled about a fifth of the time (%d / 1000)" % [id, int(counts.get(id, 0))])
	check_eq(RunState.environment_for_seed(31), RunState.environment_for_seed(31), "a seed always rolls the same")


func test_the_roll_follows_the_weights() -> void:
	for id in Db.environment_ids:
		_env(id).roll_weight = 0.0
	_env(&"volcano").roll_weight = 3.0
	for seed_value in 60:
		check_eq(RunState.environment_for_seed(seed_value), &"volcano", "only the weighted environment is drawn")
	_env(&"volcano").roll_weight = 0.0
	_env(&"swamp").roll_weight = 1.0
	_env(&"ice_cave").roll_weight = 3.0
	var ice := 0
	for seed_value in 800:
		var id := RunState.environment_for_seed(seed_value)
		check(id == &"swamp" or id == &"ice_cave", "a weight of 0 never wins (%s)" % id)
		if id == &"ice_cave":
			ice += 1
	check(ice > 520 and ice < 680, "3 : 1 weights give about 600 / 800 (got %d)" % ice)
	for id in Db.environment_ids:
		_env(id).roll_weight = 0.0
	check_eq(RunState.environment_for_seed(5), RunState.DEFAULT_ENVIRONMENT, "nothing to draw: the Forest Ruin")


func test_a_run_rolls_the_environment_of_its_seed_with_one_environment_rng_draw() -> void:
	for seed_value in [3, 17, 4242, 99999]:
		RunState.start_run(2, seed_value)
		check_eq(RunState.environment, RunState.environment_for_seed(seed_value), "the run rolls what the seed rolls (%d)" % seed_value)
		var mirror := RandomNumberGenerator.new()
		mirror.seed = RunState.derived_seed(seed_value, RunState.SALT_ENVIRONMENT)
		mirror.randf()
		check_eq(RunState.environment_rng.state, mirror.state, "exactly one draw (%d)" % seed_value)
	RunState.start_run(2, 17, RunState.MODE_NORMAL, false, &"cemetery")
	check_eq(RunState.environment, &"cemetery", "a forced environment is not rolled")
	var untouched := RunState.sub_rng(RunState.SALT_ENVIRONMENT)
	check_eq(RunState.environment_rng.state, untouched.state, "and draws nothing")


# --- Decor sets ---------------------------------------------------------------------------------

func test_the_decor_sets_stay_within_the_forests_draw_call_budget() -> void:
	var forest := Arena.create(_env(&"forest_ruin"))
	nodes.append(forest)
	var forest_calls := _decor_instances(forest).size()
	var forest_verts := _vertex_count(forest)
	for id in ArenaThemes.set_ids():
		var arena := Arena.create(_env(id))
		nodes.append(arena)
		var calls := _decor_instances(arena)
		check(calls.size() <= forest_calls, "%s: %d decor draws vs the forest's %d" % [id, calls.size(), forest_calls])
		check(calls.size() <= ArenaThemes.MAX_DRAW_CALLS, "%s: within the set limit" % id)
		check_eq(arena.get_node("Decor").get_child_count(), calls.size(), "%s: only visual instances (no physics bodies, no lights)" % id)
		check(_vertex_count(arena) <= forest_verts * 3 / 2, "%s: no heavier than the forest (%d vs %d vertices)" % [id, _vertex_count(arena), forest_verts])
		check(_vertex_count(arena) > 5000, "%s: really builds something" % id)


func _vertex_count(arena: Arena) -> int:
	var n := 0
	for mi in _decor_instances(arena):
		var mesh: Mesh = (mi as MeshInstance3D).mesh if mi is MeshInstance3D else (mi as MultiMeshInstance3D).multimesh.mesh
		for s in mesh.get_surface_count():
			n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return n


func test_the_decor_sets_never_put_anything_tall_inside_the_arena() -> void:
	for id in ArenaThemes.set_ids():
		var arena := Arena.create(_env(id))
		nodes.append(arena)
		var bounds := arena.get_bounds()
		for gi in _decor_instances(arena):
			if gi is MeshInstance3D:
				var mesh := (gi as MeshInstance3D).mesh
				for s in mesh.get_surface_count():
					for v: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
						if bounds.has_point(Vector2(v.x, v.z)):
							if v.y > 0.55:
								failures.append("%s: %s has a vertex %.2f m high inside the arena at (%.1f, %.1f)" % [id, gi.name, v.y, v.x, v.z])
								return
			elif gi is MultiMeshInstance3D:
				# (A MultiMesh cannot be read back headless: ArenaThemes records what stands inside.)
				check(gi.has_meta(&"inside_top"), "%s: %s records its tallest ground detail" % [id, gi.name])
				if float(gi.get_meta(&"inside_top", 99.0)) > 0.55:
					failures.append("%s: %s has a ground detail %.2f m high inside the arena" % [id, gi.name, float(gi.get_meta(&"inside_top"))])
					return
	# The recording itself: the Swamp's reeds stay outside, the tufts are the ones inside.
	var swamp := Arena.create(_env(&"swamp"))
	nodes.append(swamp)
	check_eq(int(swamp.get_node("Decor/Reeds").get_meta(&"inside_count")), 0, "no reed stands inside the arena")
	check(int(swamp.get_node("Decor/GrassTufts").get_meta(&"inside_count")) > 50, "but grass tufts do")
	check(float(swamp.get_node("Decor/GrassTufts").get_meta(&"inside_top")) > 0.1, "a little taller than nothing")


func test_the_decor_is_deterministic_and_differs_per_set() -> void:
	var sizes := {}
	for id in ArenaThemes.set_ids():
		var a := Arena.create(_env(id))
		var b := Arena.create(_env(id))
		nodes.append(a)
		nodes.append(b)
		check_eq(_vertex_count(a), _vertex_count(b), "%s: the same set twice" % id)
		sizes[id] = _vertex_count(a)
		var names_a: Array[String] = []
		var names_b: Array[String] = []
		for c in a.get_node("Decor").get_children():
			names_a.append(String(c.name))
		for c in b.get_node("Decor").get_children():
			names_b.append(String(c.name))
		check_eq(names_a, names_b, "%s: the same nodes" % id)
	check_eq(sizes.size(), 4, "four sets")
	var distinct := {}
	for id in sizes:
		distinct[sizes[id]] = true
	check_eq(distinct.size(), 4, "four different meshes")


func test_the_volcano_dresses_its_vents_and_the_hazard_uses_the_same_places() -> void:
	check_eq(EnvironmentHazards.LAVA_VENT_POINTS.size(), 6, "six vents")
	var arena := Arena.create(_env(&"volcano"))
	nodes.append(arena)
	var lava := arena.get_node("Decor/Lava") as MeshInstance3D
	check(lava != null, "the lava mesh")
	var found := 0
	for p in EnvironmentHazards.LAVA_VENT_POINTS:
		check(arena.is_inside(p, 2.0), "a vent lies inside the arena")
		check(Vector2(p.x, p.z).length() > 4.0, "and not at the Spirit Healer / spawn circle")
		var hit := false
		for v: Vector3 in lava.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			if absf(v.x - p.x) < 0.9 and absf(v.z - p.z) < 0.9 and v.y > 0.0 and v.y < 0.2:
				hit = true
				break
		if hit:
			found += 1
	check_eq(found, 6, "a glowing core at every vent")


# --- Formulas -------------------------------------------------------------------------------------

func test_hazard_damage_is_a_multiple_of_the_grunts_contact_damage_at_the_wave() -> void:
	var grunt := Db.enemies[&"skeleton_grunt"]
	for count in [1, 2, 4]:
		RunState.start_run(count, 4242, RunState.MODE_NORMAL, false, &"forest_ruin")
		for wave in [1, 6, 12, 25, 40]:
			var expected := grunt.contact_damage_at_wave(wave) * RunState.coop_damage_mult()
			check_near(EnvironmentHazards.grunt_damage(wave), expected, 0.0001, "grunt damage at wave %d, %d players" % [wave, count])
			check_near(EnvironmentHazards.damage_for(&"grasping_hands", wave), expected * 0.5, 0.0001, "hands: 0.5x")
			check_near(EnvironmentHazards.damage_for(&"lava_vents", wave), expected * 1.5, 0.0001, "lava: 1.5x")
			check_near(EnvironmentHazards.damage_for(&"falling_icicles", wave), expected, 0.0001, "icicles: 1x")
			check_eq(EnvironmentHazards.damage_for(&"bog_pools", wave), 0.0, "pools do no damage")
	check(EnvironmentHazards.grunt_damage(20) > EnvironmentHazards.grunt_damage(2), "it grows with the wave")
	RunState.start_run(1, 1, RunState.MODE_NORMAL, false, &"forest_ruin")
	var solo := EnvironmentHazards.grunt_damage(10)
	RunState.start_run(4, 1, RunState.MODE_NORMAL, false, &"forest_ruin")
	check(EnvironmentHazards.grunt_damage(10) != solo, "and follows the party size")


func test_boss_waves_halve_the_hazard_rate() -> void:
	check_eq(EnvironmentHazards.rate_mult(9), 1.0, "a normal wave")
	check_eq(EnvironmentHazards.rate_mult(10), 0.5, "the Morvain wave")
	check_eq(EnvironmentHazards.rate_mult(25), 0.5, "the Vor'thalax wave")
	check_near(EnvironmentHazards.interval_for(&"grasping_hands", 5), 9.0, 0.0001, "hands every 9 s")
	check_near(EnvironmentHazards.interval_for(&"falling_icicles", 5), 7.0, 0.0001, "icicles every 7 s")
	check_near(EnvironmentHazards.interval_for(&"lava_vents", 5), 8.0, 0.0001, "vents every 8 s")
	check_near(EnvironmentHazards.interval_for(&"grasping_hands", 10), 18.0, 0.0001, "hands twice as far apart on a boss wave")
	check_near(EnvironmentHazards.interval_for(&"falling_icicles", 25), 14.0, 0.0001, "icicles too")
	check_near(EnvironmentHazards.interval_for(&"lava_vents", 10), 16.0, 0.0001, "and the vents")
	check_eq(EnvironmentHazards.interval_for(&"bog_pools", 5), 0.0, "pools are not cast")
	check_eq(EnvironmentHazards.pool_count_for(5), 5, "five pools")
	check_eq(EnvironmentHazards.pool_count_for(10), 3, "three on a boss wave")


# --- The director: Cemetery -----------------------------------------------------------------------

func test_the_forest_has_no_hazard() -> void:
	var hz := _hazard_director(&"forest_ruin")
	_hero(Vector3(2, 0, 0))
	check(not hz.has_hazard(), "no hazard")
	_step(hz, 60.0)
	check_eq(hz.hazards_laid, 0, "nothing laid in a minute")
	check(tree.get_nodes_in_group(EnemyHazard.GROUP).is_empty(), "no hazard nodes")
	var bare := EnvironmentHazards.create(null, null)
	nodes.append(bare)
	check_eq(bare.kind, &"", "without an environment: no hazard")


func test_grasping_hands_come_every_nine_seconds_two_or_three_at_a_time_under_the_heroes() -> void:
	var heroes: Array[EFakes.FakePlayer] = [_hero(Vector3(-6, 0, -2)), _hero(Vector3(0, 0, 3)),
			_hero(Vector3(6, 0, -1)), _hero(Vector3(2, 0, 5))]
	var hz := _hazard_director(&"cemetery", 5)
	_step(hz, 4.0)
	check(_hazards_of(GraspingHands).is_empty(), "the first cast comes a little under 4.1 s in")
	_step(hz, 0.2)
	var first := _hazards_of(GraspingHands)
	check(first.size() >= 2 and first.size() <= 3, "two or three circles (%d)" % first.size())
	var under: Dictionary = {}
	for h in first:
		var hands := h as GraspingHands
		check_eq(hands.radius, 1.5, "radius 1.5")
		check_near(hands.telegraph_time, 1.0, 0.0001, "1 s warning")
		check_near(hands.root_time, 1.2, 0.0001, "1.2 s root")
		check_near(hands.damage, EnvironmentHazards.grunt_damage(5) * 0.5, 0.0001, "0.5x the grunt's damage")
		check(hands.tally == hz, "counted by the director")
		for hero in heroes:
			if hands.global_position.distance_to(hero.global_position) < 0.001:
				under[hero] = true
	check_eq(under.size(), first.size(), "each circle lies exactly under a different hero")
	_step(hz, 8.7)
	check_eq(_hazards_of(GraspingHands).size() >= first.size() and hz.hazards_laid == first.size(), true, "nothing between the casts")
	_step(hz, 0.3)
	check(hz.hazards_laid >= first.size() + 2, "the next cast comes 9 s after the first (%d laid)" % hz.hazards_laid)


func test_a_lone_hero_gets_the_extra_hands_beside_him() -> void:
	var hero := _hero(Vector3(3, 0, 2))
	var hz := _hazard_director(&"cemetery", 5)
	_step(hz, 4.2)
	var circles := _hazards_of(GraspingHands)
	check(circles.size() >= 2, "still two or three circles")
	var under := 0
	for c in circles:
		var d := (c as Node3D).global_position.distance_to(hero.global_position)
		if d < 0.001:
			under += 1
		else:
			check(d >= 1.5 and d <= 3.0, "an extra circle beside him (%.2f m)" % d)
	check_eq(under, 1, "one right under him")


func test_nothing_is_cast_without_a_living_hero_or_outside_a_running_wave() -> void:
	var downed := _hero(Vector3(2, 0, 0))
	downed.downed = true
	Enemy.invalidate_player_cache()
	var hz := _hazard_director(&"cemetery", 5)
	_step(hz, 30.0)
	check_eq(hz.hazards_laid, 0, "no living hero, no hands")
	var living := _hero(Vector3(-2, 0, 0))
	living.name = "Living"
	Enemy.invalidate_player_cache()
	hz.director.stop()  # (the wave is over: the director is not running)
	_step(hz, 30.0)
	check_eq(hz.hazards_laid, 0, "a stopped wave lays nothing")


func test_boss_waves_cast_half_as_often() -> void:
	_hero(Vector3(2, 0, 0))
	var normal := _hazard_director(&"cemetery", 9)
	_step(normal, 60.0)
	var normal_casts := normal.hazards_laid
	check(normal_casts >= 12, "about 6 casts of 2-3 circles in a minute (%d)" % normal_casts)
	for n in tree.get_nodes_in_group(EnemyHazard.GROUP):
		n.free()
	var boss := _hazard_director(&"cemetery", 10)
	_step(boss, 60.0)
	check(boss.hazards_laid >= 6 and boss.hazards_laid <= 9, "about 3 casts on the boss wave (%d)" % boss.hazards_laid)
	check(boss.hazards_laid * 3 < normal_casts * 2, "clearly fewer than on a normal wave (%d vs %d)" % [boss.hazards_laid, normal_casts])


func test_the_hazards_draw_only_from_the_environment_rng() -> void:
	_hero(Vector3(2, 0, 0))
	_hero(Vector3(-4, 0, 3))
	var game_before := RunState.rng.state
	var env_before := RunState.environment_rng.state
	var hz := _hazard_director(&"cemetery", 5)
	var game_after_start := RunState.rng.state  # (the director's own wave start draws from the game rng)
	_step(hz, 40.0)
	check_eq(RunState.rng.state, game_after_start, "casting never touches the gameplay rng")
	check(RunState.environment_rng.state != env_before, "it drew from the environment rng")
	check(game_before != 0, "(sanity)")


func test_the_hazard_stream_is_a_function_of_the_run_seed() -> void:
	var runs: Array[Array] = []
	for attempt in 2:
		RunState.start_run(4, 4242, RunState.MODE_NORMAL, false, &"cemetery")
		_hero(Vector3(2, 0, 0))
		_hero(Vector3(-4, 0, 3))
		var hz := _hazard_director(&"cemetery", 5)
		_step(hz, 30.0)
		var spots: Array = []
		for h in _hazards_of(GraspingHands):
			spots.append((h as Node3D).global_position)
		runs.append(spots)
		for n in tree.get_nodes_in_group(EnemyHazard.GROUP):
			n.free()
		for h in tree.get_nodes_in_group(&"players"):
			h.free()
		Enemy.invalidate_player_cache()
	check(not runs[0].is_empty(), "something was laid")
	check_eq(runs[0], runs[1], "the same seed lays the same hazards")


# --- Grasping Hands: the nodes --------------------------------------------------------------------

func test_grasping_hands_hurt_and_root_the_heroes_inside_when_they_close() -> void:
	var inside := _real_hero(0, Vector3(0.5, 0, 0))
	var outside := _real_hero(1, Vector3(5.0, 0, 0), &"mage")
	var hp_in := inside.hp
	var hands := GraspingHands.spawn(_entities(), Vector3.ZERO, 1.5, 1.0, 2.0, 1.2)
	check(hands.is_telegraphing() and hands.is_dangerous(), "a telegraphed hazard")
	check(hands.is_in_group(EnemyHazard.GROUP), "an enemy hazard")
	_step(hands, 0.9)
	check_eq(inside.hp, hp_in, "nothing before the strike")
	check(not inside.is_rooted(), "not rooted yet")
	_step(hands, 0.2)
	check(inside.hp < hp_in, "the hero inside is hurt")
	check(inside.is_rooted(), "and rooted")
	check_near(inside.rooted_left, 1.2, 0.2, "for 1.2 s")
	check(not outside.is_rooted(), "the hero outside is free")
	check_eq(hands.hits, 1, "one hit")
	check(not hands.is_dangerous(), "a hero walking into the open hands is not hurt again")
	check(hands.hazard_push(Vector3(0.5, 0, 0)) == Vector2.ZERO, "so the bots ignore them")
	_step(hands, 1.4)
	check(hands.stage == EnemyHazard.Stage.DONE, "the hands sink back after the root")
	_step(hands, 0.4)
	check(hands.is_queued_for_deletion(), "and free themselves")


func test_grasping_hands_use_the_aoe_kind_and_skip_the_downed() -> void:
	var live := _hero(Vector3(0.4, 0, 0))
	var downed := _hero(Vector3(-0.4, 0, 0))
	downed.downed = true
	Enemy.invalidate_player_cache()
	var hands := GraspingHands.spawn(_entities(), Vector3.ZERO, 1.5, 0.5, 3.0, 1.2)
	_step(hands, 0.6)
	check_eq(live.fake_hits, [3.0] as Array[float], "the living hero took the damage once")
	check_eq(live.fake_kinds[0], CombatMath.KIND_AOE, "AOE kind: Avoidance applies")
	check(downed.fake_hits.is_empty() and not downed.is_rooted(), "a downed hero is neither hit nor rooted")


func test_a_rooted_hero_stands_still_until_the_root_ends() -> void:
	var hero := _real_hero(0, Vector3.ZERO)
	var input := hero.slot.input as ScriptedInput
	input.move = Vector2(1, 0)
	for i in 20:
		hero._physics_process(DT)
	var walked := hero.global_position.x
	check(walked > 0.5, "an unrooted hero walks (%.2f)" % walked)
	check(hero.apply_root(0.5), "the root takes hold")
	hero.velocity = Vector3(5, 0, 0)
	var at := hero.global_position.x
	for i in 20:
		hero._physics_process(DT)
	check_near(hero.global_position.x, at, 0.01, "rooted: no walking")
	check(hero.is_rooted(), "still rooted at 0.33 s")
	for i in 20:
		hero._physics_process(DT)
	check(not hero.is_rooted(), "the root ended after 0.5 s")
	check(hero.global_position.x > at + 0.05, "and the hero walks again")
	hero.apply_root(5.0)
	check(hero.apply_root(1.0) and hero.rooted_left > 4.9, "a shorter root never shortens a longer one")
	hero.begin_wave()
	check(not hero.is_rooted(), "a new wave frees him")
	hero.apply_root(5.0)
	hero._go_down()
	check(not hero.is_rooted(), "a downed hero is not rooted")
	check(not hero.apply_root(1.0), "and cannot be rooted")
	check(not _real_hero(1, Vector3(4, 0, 0)).apply_root(0.0), "a root of no time is none")


# --- Falling Icicles ---------------------------------------------------------------------------------

func test_falling_icicles_land_near_the_heroes_three_every_seven_seconds() -> void:
	var a := _hero(Vector3(-5, 0, 0))
	var b := _hero(Vector3(5, 0, 2))
	var hz := _hazard_director(&"ice_cave", 5)
	_step(hz, 3.0)
	check(_hazards_of(FallingIcicle).is_empty(), "the first cast comes about 3.15 s in")
	_step(hz, 0.3)
	var icicles := _hazards_of(FallingIcicle)
	check_eq(icicles.size(), 3, "three circles")
	for n in icicles:
		var ic := n as FallingIcicle
		check_eq(ic.radius, 1.2, "radius 1.2")
		check_near(ic.telegraph_time, 1.0, 0.0001, "1 s warning")
		check_near(ic.damage, EnvironmentHazards.grunt_damage(5), 0.0001, "1x the grunt's damage")
		check_eq(ic.slow_pct, 30.0, "30% slow")
		check_eq(ic.slow_time, 1.5, "for 1.5 s")
		var near := minf(ic.global_position.distance_to(a.global_position), ic.global_position.distance_to(b.global_position))
		check(near >= 0.7 and near <= 3.4, "near a hero, not on him (%.2f m)" % near)
		check(EFakes.arena_of(world).get_bounds().has_point(Vector2(ic.global_position.x, ic.global_position.z)), "inside the arena")
	_step(hz, 6.8)
	check_eq(hz.hazards_laid, 3, "nothing until 7 s later")
	_step(hz, 0.3)
	check_eq(hz.hazards_laid, 6, "the next three")
	var boss := _hazard_director(&"ice_cave", 10)
	check_near(EnvironmentHazards.interval_for(boss.kind, 10), 14.0, 0.0001, "every 14 s on a boss wave")


func test_a_falling_icicle_hurts_and_chills_the_hero_it_lands_on() -> void:
	var inside := _real_hero(0, Vector3(0.4, 0, 0))
	var outside := _real_hero(1, Vector3(4, 0, 0), &"mage")
	var speed := inside.stats.get_stat(Stats.SPEED)
	var ic := FallingIcicle.spawn(_entities(), Vector3.ZERO, 1.2, 1.0, 3.0, 30.0, 1.5)
	check_near(ic.telegraph_left(), 1.0, 0.0001, "1 s warning")
	var hp := inside.hp
	_step(ic, 1.1)
	check(inside.hp < hp, "hurt")
	check_near(inside.stats.get_stat(Stats.SPEED), speed - 30.0, 0.0001, "chilled by 30%")
	check(GeneralBuff.find(outside, FallingIcicle.CHILL_KEY) == null, "the other hero is not")
	var chill := GeneralBuff.find(inside, FallingIcicle.CHILL_KEY)
	check(chill != null, "as a timed buff")
	EFakes.step(chill, 1.6)
	check_near(inside.stats.get_stat(Stats.SPEED), speed, 0.0001, "the chill ends after 1.5 s")
	check(not ic.is_dangerous(), "harmless once it landed")
	check(FallingIcicle.CHILL_KEY != FrostCircle.CHILL_KEY, "separate from Morvain's chill")


# --- Lava vents -----------------------------------------------------------------------------------------

func test_the_six_vents_erupt_in_turn_every_eight_seconds() -> void:
	_hero(Vector3(0, 0, 0))
	var hz := _hazard_director(&"volcano", 5)
	var seen: Array[Vector3] = []
	var t := 0.0
	while t < 40.0:
		_step(hz, 0.1)
		t += 0.1
		for n in _hazards_of(LavaEruption):
			var e := n as LavaEruption
			var known := false
			for s in seen:
				if s.distance_to(e.global_position) < 0.01 and e.age < 0.2:
					known = true
			if not known and e.age < 0.15:
				seen.append(e.global_position)
	check(hz.hazards_laid >= 24 and hz.hazards_laid <= 36, "about 5 eruptions of 6 vents in 40 s (%d)" % hz.hazards_laid)
	for p in EnvironmentHazards.LAVA_VENT_POINTS:
		var found := false
		for s in seen:
			if s.distance_to(p) < 0.01:
				found = true
		check(found, "the vent at %s erupted" % p)
	var one := _hazards_of(LavaEruption)
	for n in one:
		var e := n as LavaEruption
		check_eq(e.radius, 2.0, "radius 2")
		check_near(e.telegraph_time, 1.0, 0.0001, "1 s warning")
		check_near(e.damage, EnvironmentHazards.grunt_damage(5) * 1.5, 0.0001, "1.5x the grunt's damage")
	# One vent at a time: the first erupt times are spread over the interval.
	var hz2 := _hazard_director(&"volcano", 5)
	for n in tree.get_nodes_in_group(EnemyHazard.GROUP):
		n.free()
	_step(hz2, 3.7)
	check(hz2.hazards_laid <= 1, "the vents do not all go off together (%d at 3.7 s)" % hz2.hazards_laid)


func test_boss_waves_halve_the_eruptions() -> void:
	var normal := _hazard_director(&"volcano", 9)
	_step(normal, 48.0)
	var normal_count := normal.hazards_laid
	for n in tree.get_nodes_in_group(EnemyHazard.GROUP):
		n.free()
	var boss := _hazard_director(&"volcano", 10)
	_step(boss, 48.0)
	check(normal_count >= 30, "about 36 eruptions in 48 s (%d)" % normal_count)
	check(boss.hazards_laid * 2 <= normal_count + 6 and boss.hazards_laid * 2 >= normal_count - 6, "about half on the boss wave (%d vs %d)" % [boss.hazards_laid, normal_count])


func test_an_eruption_burns_heroes_and_enemies_alike() -> void:
	var hero := _hero(Vector3(0.5, 0, 0))
	var far_hero := _hero(Vector3(6, 0, 0))
	var data := EFakes.enemy_data()
	data.max_hp = 50.0
	var enemy := EFakes.spawn_enemy(world, data, Vector3(-0.8, 0, 0.3))
	var far_enemy := EFakes.spawn_enemy(world, data, Vector3(7, 0, 3))
	EnemyGrid.mark_dirty()
	var tally := EnvironmentHazards.create(null, null)
	nodes.append(tally)
	var eruption := LavaEruption.spawn(_entities(), Vector3.ZERO, 2.0, 1.0, 6.0, tally)
	var hp := enemy.hp
	_step(eruption, 0.9)
	check_eq(hero.fake_hits.size(), 0, "nothing before the eruption")
	check_eq(enemy.hp, hp, "enemies are safe during the warning")
	_step(eruption, 0.2)
	check_eq(hero.fake_hits, [6.0] as Array[float], "the hero inside is hurt")
	check_eq(hero.fake_kinds[0], CombatMath.KIND_AOE, "AOE kind")
	check(far_hero.fake_hits.is_empty(), "the hero outside is not")
	check_near(enemy.hp, hp - 6.0, 0.0001, "the enemy inside is hurt as much")
	check_eq(far_enemy.hp, far_enemy.max_hp, "the enemy outside is not")
	check_eq(eruption.hero_hits, 1, "one hero hit")
	check_eq(eruption.enemy_hits, 1, "one enemy hit")
	check_eq(tally.hero_hits, 1, "the director counts the hero hit")
	check_near(tally.hero_damage, 6.0, 0.0001, "and its damage")
	check_eq(tally.enemy_hits, 1, "the enemy hit")
	check_near(tally.enemy_damage, 6.0, 0.0001, "and its damage")
	check(not eruption.is_dangerous(), "harmless after the blast")
	_step(eruption, 0.7)
	check(eruption.is_queued_for_deletion(), "gone after its fade")


func test_an_eruption_can_kill_an_enemy_and_counts_it() -> void:
	var data := EFakes.enemy_data()
	data.max_hp = 2.0
	data.hp_growth = 0.0
	var enemy := EFakes.spawn_enemy(world, data, Vector3(0.5, 0, 0))
	EnemyGrid.mark_dirty()
	var tally := EnvironmentHazards.create(null, null)
	nodes.append(tally)
	var kills := RunState.kills
	var eruption := LavaEruption.spawn(_entities(), Vector3.ZERO, 2.0, 0.2, 50.0, tally)
	_step(eruption, 0.3)
	check(enemy.is_dead(), "the lava killed it")
	check_eq(eruption.enemy_kills, 1, "the eruption counts the kill")
	check_eq(tally.enemy_kills, 1, "so does the director")
	check_eq(RunState.kills, kills + 1, "it is a kill of the run (nobody gets the credit)")


# --- Bog pools --------------------------------------------------------------------------------------------

func test_the_swamp_lays_five_pools_in_the_same_places_every_wave() -> void:
	var d := _director()
	var hz := EnvironmentHazards.create(d, _env(&"swamp"))
	d.add_child(hz)
	d.start_wave(3)
	var first := _hazards_of(BogPool)
	check_eq(first.size(), 5, "five pools")
	check_eq(hz.pool_points.size(), 5, "five places")
	var spots: Array[Vector3] = []
	for p in first:
		spots.append((p as Node3D).global_position)
	for i in spots.size():
		check(spots[i].distance_to(hz.pool_points[i]) < 0.001, "the pool lies at its place")
		check(EFakes.arena_of(world).get_bounds().grow(-3.0 + 0.001).has_point(Vector2(spots[i].x, spots[i].z)), "inside the arena, off the walls")
		check(Vector2(spots[i].x, spots[i].z).length() >= 4.4, "clear of the middle")
		for j in range(i + 1, spots.size()):
			check(spots[i].distance_to(spots[j]) >= 5.9, "spaced apart (%.1f m)" % spots[i].distance_to(spots[j]))
	d.stop()  # the wave ends: the pools are freed with the other hazards
	for p in first:
		check(p.is_queued_for_deletion(), "the wave end frees the pool")
	var state := RunState.environment_rng.state
	d.start_wave(4)
	check_eq(RunState.environment_rng.state, state, "the places are drawn once: no draw on the next wave")
	var second: Array[Node] = []
	for n in _hazards_of(BogPool):
		second.append(n)
	check_eq(second.size(), 5, "five again")
	var again: Array[Vector3] = []
	for n in second:
		again.append((n as Node3D).global_position)
	check_eq(again, spots, "the same places")
	d.stop()
	d.start_wave(10)
	check_eq(_hazards_of(BogPool).size(), 3, "three pools on a boss wave")
	check_eq(hz.hazards_laid, 13, "every pool counts as laid")


func test_pool_places_are_a_function_of_the_rng_and_keep_their_rules() -> void:
	for seed_value in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var pts := EnvironmentHazards.draw_pool_points(rng)
		check_eq(pts.size(), 5, "five places")
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = seed_value
		check_eq(EnvironmentHazards.draw_pool_points(rng2), pts, "the same rng draws the same places")
		for i in pts.size():
			check(Rect2(-Arena.SIZE / 2.0, Arena.SIZE).grow(-EnvironmentHazards.BOG_WALL_MARGIN + 0.001).has_point(Vector2(pts[i].x, pts[i].z)), "off the walls")
			check(Vector2(pts[i].x, pts[i].z).length() >= EnvironmentHazards.BOG_CENTER_CLEARANCE - 0.001, "clear of the middle")
			for j in range(i + 1, pts.size()):
				check(pts[i].distance_to(pts[j]) >= EnvironmentHazards.BOG_SPACING - 0.001, "spaced apart")


func test_a_bog_pool_slows_the_heroes_and_enemies_inside_and_hurts_nobody() -> void:
	var inside := _real_hero(0, Vector3(1.0, 0, 0))
	var outside := _real_hero(1, Vector3(5.0, 0, 0), &"mage")
	var speed := inside.stats.get_stat(Stats.SPEED)
	var data := EFakes.enemy_data()
	var wader := EFakes.spawn_enemy(world, data, Vector3(-1.0, 0, 0.5))
	var dry := EFakes.spawn_enemy(world, data, Vector3(6.0, 0, 3.0))
	EnemyGrid.mark_dirty()
	var hp := inside.hp
	var pool := BogPool.spawn(_entities(), Vector3.ZERO, 2.3, 30.0, 15.0)
	check(pool.is_in_group(EnemyHazard.GROUP), "an enemy hazard")
	_step(pool, 0.5)
	check_near(inside.stats.get_stat(Stats.SPEED), speed - 30.0, 0.0001, "the hero inside is 30% slower")
	check(GeneralBuff.find(outside, BogPool.SLOW_KEY) == null, "the hero outside is not slowed")
	check_eq(inside.hp, hp, "the pool does no damage")
	check_near(wader.slow_pct, 15.0, 0.0001, "the enemy inside is 15% slower")
	check(wader.slow_left > 0.0, "with a running slow")
	check_eq(dry.slow_pct, 0.0, "the enemy outside is not")
	check(pool.stage == EnemyHazard.Stage.ACTIVE and pool.is_dangerous(), "a pool never ends")
	check(pool.hero_slows >= 1 and pool.enemy_slows >= 1, "counted")
	# Leaving the pool ends the slow a moment later.
	inside.global_position = Vector3(8, 0, 0)
	_step(pool, 0.1)
	EFakes.step(GeneralBuff.find(inside, BogPool.SLOW_KEY), 0.5)
	check_near(inside.stats.get_stat(Stats.SPEED), speed, 0.0001, "the hero is quick again once out")
	_step(pool, 20.0)
	check(pool.stage == EnemyHazard.Stage.ACTIVE, "still there 20 s later")


func test_the_bots_steer_around_a_bog_pool_but_only_gently() -> void:
	var pool := BogPool.spawn(_entities(), Vector3(4, 0, 0), 2.3, 30.0, 15.0)
	var from := Vector3(6.0, 0, 0)
	var push := pool.hazard_push(from)
	check(push.x > 0.0 and absf(push.y) < 0.01, "away from the pool (%s)" % push)
	var damaging := EnemyHazard.circle_push(pool.global_position, 2.3, from, EnemyHazard.BOT_MARGIN)
	check(push.length() < damaging.length(), "weaker than a damaging hazard's push")
	check_near(push.length(), EnemyHazard.circle_push(pool.global_position, 2.3, from, BogPool.BOT_AVOID_MARGIN).length() * BogPool.BOT_WEIGHT, 0.0001, "half of the narrow-margin push")
	check(pool.hazard_push(Vector3(12, 0, 0)) == Vector2.ZERO, "nothing far away")
	var bot := _bot(Vector3(5.5, 0, 0))
	check(_bot_move(bot).x > 0.3, "a bot at the pool's rim walks away from it")


# --- The bots and the other hazards ----------------------------------------------------------------------

func test_bots_step_out_of_the_telegraphs_of_the_environment_hazards() -> void:
	var cases := {
		&"hands": GraspingHands.spawn(_entities(), Vector3(3.5, 0, 0), 1.5, 1.0, 1.0, 1.2),
		&"icicle": FallingIcicle.spawn(_entities(), Vector3(3.5, 0, 10), 1.2, 1.0, 1.0, 30.0, 1.5),
		&"lava": LavaEruption.spawn(_entities(), Vector3(3.5, 0, -10), 2.0, 1.0, 1.0),
	}
	var bot_hands := _bot(Vector3(4.2, 0, 0), 0)
	check(_bot_move(bot_hands).x > 0.5, "the bot east of the hands' circle runs out of it")
	var bot_ice := _bot(Vector3(4.0, 0, 10), 1)
	check(_bot_move(bot_ice).x > 0.5, "out of the icicle's circle")
	var bot_lava := _bot(Vector3(4.5, 0, -10), 2)
	check(_bot_move(bot_lava).x > 0.5, "out of the eruption's circle")
	for id in cases:
		check(cases[id].is_dangerous() and cases[id].is_telegraphing(), "%s: dangerous while it warns" % id)
	EFakes.step(cases[&"lava"], 1.1)
	check(not cases[&"lava"].is_dangerous() and cases[&"lava"].hazard_push(Vector3(4.5, 0, -10)) == Vector2.ZERO, "an eruption that struck pushes nothing")


# --- Wave end and wiring ------------------------------------------------------------------------------------

func test_the_wave_end_frees_every_hazard_and_clears_their_effects() -> void:
	var hero := _real_hero(0, Vector3(1, 0, 0))
	var d := _director()
	var hz := EnvironmentHazards.create(d, _env(&"swamp"))
	d.add_child(hz)
	d.start_wave(3)
	_step(hz, 0.1)
	for pool in _hazards_of(BogPool):
		EFakes.step(pool, 0.2)
	hero.global_position = Vector3(0, 0, 0)
	for pool in _hazards_of(BogPool):
		(pool as BogPool).global_position = Vector3.ZERO
		EFakes.step(pool, 0.1)
	check(GeneralBuff.find(hero, BogPool.SLOW_KEY) != null, "slowed in the pool")
	hero.apply_root(3.0)
	var pools := _hazards_of(BogPool)
	d.stop()
	for p in pools:
		check(p.is_queued_for_deletion(), "WaveDirector.stop() frees the hazards")
	hz.end_wave()
	check(GeneralBuff.find(hero, BogPool.SLOW_KEY) == null, "the slow ends with the wave")
	check(not hero.is_rooted(), "so does the root")
	var cem := _hazard_director(&"cemetery", 5)
	var lone := _hero(Vector3(2, 0, 0))
	check(lone != null, "(a hero for the hands)")
	_step(cem, 4.5)
	var hands := _hazards_of(GraspingHands)
	check(not hands.is_empty(), "hands laid")
	cem.director.stop()
	for h in hands:
		check(h.is_queued_for_deletion(), "freed at the wave end")


func test_main_wires_a_hazard_director_for_the_runs_environment() -> void:
	var opts := LaunchOptions.new()
	opts.environment = &"ice_cave"
	_run_with_bots(2, opts)
	check_eq(RunState.environment, &"ice_cave", "--env forced")
	check(main.environment_hazards != null and is_instance_valid(main.environment_hazards), "a hazard director")
	check(main.environment_hazards.get_parent() == main.wave_director, "a child of the WaveDirector")
	check_eq(main.environment_hazards.kind, &"falling_icicles", "the Ice Cave's hazard")
	check(main.arena.environment == _env(&"ice_cave"), "the arena of the environment")
	check(main.wave_director.wave_started.is_connected(main.environment_hazards._on_wave_started), "listens to the waves")
	main.start_run()
	check_eq(main.environment_hazards.hazards_laid, 0, "a fresh director each run")
	var forest := LaunchOptions.new()
	forest.environment = &"forest_ruin"
	main.options = forest
	main.start_run()
	check_eq(main.environment_hazards.kind, &"", "the forest runs a director with nothing to do")
	main._teardown_run()
	check(main.environment_hazards == null, "torn down with the run")


func test_the_smoke_result_reports_the_hazards() -> void:
	var opts := LaunchOptions.new()
	opts.environment = &"volcano"
	_run_with_bots(1, opts)
	var data := main.smoke_result("completed")
	check(data.has("hazards"), "a hazards entry")
	var h: Dictionary = data["hazards"]
	check_eq(h.get("id"), "lava_vents", "the hazard id")
	for key in ["laid", "hero_hits", "hero_damage", "enemy_hits", "enemy_damage", "enemy_kills"]:
		check(h.has(key), "hazards.%s" % key)
	main.environment_hazards.record_hero_hit(2.5)
	main.environment_hazards.record_enemy_hit(3.0, true)
	var again: Dictionary = main.smoke_result("completed")["hazards"]
	check_eq(again["hero_hits"], 1, "hero hits")
	check_near(again["hero_damage"], 2.5, 0.0001, "hero damage")
	check_eq(again["enemy_hits"], 1, "enemy hits")
	check_eq(again["enemy_kills"], 1, "enemy kills")


func test_a_real_wave_in_each_environment_runs_its_hazard_without_errors() -> void:
	for id in [&"cemetery", &"swamp", &"volcano", &"ice_cave"]:
		var opts := LaunchOptions.new()
		opts.environment = id
		opts.start_wave = 5
		_run_with_bots(2, opts)
		var hz := main.environment_hazards
		check_eq(hz.kind, _env(id).hazard_id, "%s: the hazard" % id)
		var wd := main.wave_director
		for i in 60 * 14:
			wd._physics_process(DT)
			hz._physics_process(DT)
			for n in tree.get_nodes_in_group(EnemyHazard.GROUP):
				if is_instance_valid(n) and not n.is_queued_for_deletion():
					n._physics_process(DT)
		check(hz.hazards_laid > 0, "%s: something was laid in 14 s (%d)" % [id, hz.hazards_laid])
		_free_main()


# --- The roll screen ---------------------------------------------------------------------------------------------

func test_the_roll_screen_runs_a_reel_that_lands_on_the_winner() -> void:
	EnvironmentRollScreen.enabled = true
	var screen := EnvironmentRollScreen.create(&"swamp")
	tree.root.add_child(screen)
	nodes.append(screen)
	screen.size = Vector2(1920, 1080)
	var n := Db.environment_ids.size()
	check_eq(screen.cards.size(), EnvironmentRollScreen.CYCLES * n, "the list repeated")
	check_eq(screen.target_index() % n, Db.environment_ids.find(&"swamp"), "the target card is the winner")
	check(screen.target_index() >= (EnvironmentRollScreen.CYCLES - 2) * n, "far down the reel")
	check(screen.is_spinning(), "spinning at the start")
	check_eq(screen.title_label.text, "Rolling the arena…", "the title")
	var finished := []
	screen.finished.connect(func(id: StringName) -> void: finished.append(id))
	# Ease-out: the reel is fastest at the start and at rest at the end.
	check_eq(EnvironmentRollScreen.progress_at(0.0), 0.0, "starts at the first card")
	check_eq(EnvironmentRollScreen.progress_at(EnvironmentRollScreen.SPIN_TIME), 1.0, "ends on the target")
	var early := EnvironmentRollScreen.progress_at(0.2) - EnvironmentRollScreen.progress_at(0.0)
	var late := EnvironmentRollScreen.progress_at(3.5) - EnvironmentRollScreen.progress_at(3.3)
	check(early > late * 8.0, "decelerating: the first 0.2 s cover far more than the last 0.2 s")
	var prev := -1.0
	for i in 36:
		var p := EnvironmentRollScreen.progress_at(float(i) * 0.1)
		check(p >= prev, "monotonic")
		prev = p
	var x0 := screen.reel.position.x
	screen.step(1.0)
	check(screen.reel.position.x < x0 - 500.0, "the reel moved a long way in the first second")
	var mid := screen.reel.position.x
	screen.step(1.5)
	check(screen.reel.position.x < mid, "and keeps going")
	check(screen.is_spinning() and finished.is_empty(), "still spinning at 2.5 s")
	screen.step(1.0)
	check(not screen.is_spinning(), "at rest at 3.5 s")
	check_eq(screen.phase, EnvironmentRollScreen.Phase.HOLD, "holding")
	check_eq(screen.card_under_marker(), &"swamp", "the winner is under the marker")
	check_near(screen.cards[screen.target_index()].position.x + screen.reel.position.x + EnvironmentRollScreen.CARD_SIZE.x * 0.5, screen.size.x * 0.5, 0.5, "centred")
	check_eq(screen.title_label.text, "The arena: Swamp", "the result in the title")
	check(screen.result_label.text.contains("Bog Pools"), "and its hazard")
	screen.step(0.9)
	check(finished.is_empty(), "the hold lasts 1 s")
	screen.step(0.2)
	check_eq(finished, [&"swamp"] as Array, "then it reports the environment once")
	screen.step(5.0)
	check_eq(finished.size(), 1, "never twice")


func test_the_roll_screen_lands_on_each_environment_and_can_be_skipped() -> void:
	for id in Db.environment_ids:
		var screen := EnvironmentRollScreen.create(id)
		tree.root.add_child(screen)
		nodes.append(screen)
		screen.size = Vector2(1920, 1080)
		screen.step(EnvironmentRollScreen.SPIN_TIME + 0.01)
		check_eq(screen.card_under_marker(), id, "lands on %s" % id)
	var s := EnvironmentRollScreen.create(&"volcano")
	tree.root.add_child(s)
	nodes.append(s)
	s.size = Vector2(1920, 1080)
	s.step(0.3)
	var done := []
	s.finished.connect(func(e: StringName) -> void: done.append(e))
	s.skip()
	check_eq(s.phase, EnvironmentRollScreen.Phase.HOLD, "skip: straight to the hold")
	check_eq(s.card_under_marker(), &"volcano", "on the result")
	s.step(1.1)
	check_eq(done, [&"volcano"] as Array, "and on")


func test_a_players_a_press_skips_the_spin_after_the_grace_time() -> void:
	var pad := UiFakes.HumanInput.new("pad:roll")
	PlayerManager.join(pad, Db.get_class_data(&"warrior"))
	var screen := EnvironmentRollScreen.create(&"cemetery")
	tree.root.add_child(screen)
	nodes.append(screen)
	screen.size = Vector2(1920, 1080)
	UiFakes.tap(screen, pad, PlayerInput.Pad.A, 0.1)
	check(screen.is_spinning(), "a press right at the start is ignored (the press that readied the lobby)")
	UiFakes.step(screen, 1.0)
	UiFakes.tap(screen, pad, PlayerInput.Pad.A, 0.05)
	check_eq(screen.phase, EnvironmentRollScreen.Phase.HOLD, "a later press skips")
	var s2 := EnvironmentRollScreen.create(&"cemetery")
	tree.root.add_child(s2)
	nodes.append(s2)
	s2.size = Vector2(1920, 1080)
	UiFakes.step(s2, 1.0)
	UiFakes.tap(s2, pad, PlayerInput.Pad.START, 0.05)
	check_eq(s2.phase, EnvironmentRollScreen.Phase.HOLD, "START skips too")


func test_the_lobby_start_plays_the_roll_screen_and_then_the_run_with_the_same_environment() -> void:
	EnvironmentRollScreen.enabled = true
	var opts := LaunchOptions.new()
	opts.seed_value = 2024
	_make_main(opts)
	PlayerManager.add_bot(&"warrior", 1)
	main.go_to_lobby()
	check(main.plays_roll_screen(), "a lobby start plays the screen")
	main._on_lobby_start()
	check(main.roll_screen != null and is_instance_valid(main.roll_screen), "the roll screen is up")
	check_eq(main.state, Main.State.LOBBY, "the run has not started")
	check(main.arena == null, "no arena yet")
	main._on_lobby_start()  # (a second start request does not open a second screen)
	var screen := main.roll_screen
	check(main.roll_screen == screen, "one screen")
	var winner := screen.winner
	check_eq(winner, RunState.environment_for_seed(2024), "it shows the environment of the run seed")
	screen.size = Vector2(1920, 1080)
	screen.step(EnvironmentRollScreen.SPIN_TIME + 0.1)
	screen.step(EnvironmentRollScreen.HOLD_TIME + 0.1)
	# (the run starts from the deferred signal; drive it directly)
	main._on_roll_finished(winner)
	check_eq(main.state, Main.State.WAVE, "the run started")
	check_eq(RunState.environment, winner, "with the environment the screen landed on")
	check_eq(RunState.run_seed, 2024, "and its seed")
	check(main.arena.environment == _env(winner), "the arena of that environment")
	check(main.roll_screen == null, "the screen is gone")


func test_a_random_seed_is_fixed_by_the_roll_screen_so_the_run_matches_it() -> void:
	EnvironmentRollScreen.enabled = true
	_make_main(LaunchOptions.new())
	PlayerManager.add_bot(&"mage", 1)
	main.go_to_lobby()
	main._on_lobby_start()
	var winner := main.roll_screen.winner
	main._on_roll_finished(winner)
	check_eq(RunState.environment, winner, "the run rolled what the screen showed")
	check_eq(RunState.environment, RunState.environment_for_seed(RunState.run_seed), "= the roll of its (random) seed")


func test_env_forces_the_roll_screens_result() -> void:
	EnvironmentRollScreen.enabled = true
	var opts := LaunchOptions.new()
	opts.environment = &"volcano"
	opts.seed_value = 5
	_make_main(opts)
	PlayerManager.add_bot(&"mage", 1)
	main.go_to_lobby()
	main._on_lobby_start()
	check_eq(main.roll_screen.winner, &"volcano", "--env decides the card")
	main._on_roll_finished(&"volcano")
	check_eq(RunState.environment, &"volcano", "and the run")


func test_smoke_demo_view_and_test_runs_skip_the_roll_screen() -> void:
	_make_main(LaunchOptions.new())  # (an ordinary menu boot; the options below are swapped in for the question only)
	var smoke := LaunchOptions.new()
	smoke.smoke = true
	main.options = smoke
	EnvironmentRollScreen.enabled = true
	check(not main.plays_roll_screen(), "smoke: skipped")
	var demo := LaunchOptions.new()
	demo.demo = true
	main.options = demo
	check(not main.plays_roll_screen(), "demo: skipped")
	var view := LaunchOptions.new()
	view.view = "lobby"
	main.options = view
	check(not main.plays_roll_screen(), "a forced view: skipped")
	main.options = LaunchOptions.new()
	check(main.plays_roll_screen(), "a human run plays it")
	EnvironmentRollScreen.enabled = false
	check(not main.plays_roll_screen(), "tests switch it off (tests/run_tests.gd)")
	PlayerManager.add_bot(&"warrior", 1)
	main.go_to_lobby()
	main._on_lobby_start()
	check_eq(main.state, Main.State.WAVE, "with the screen off the lobby start goes straight to the run")


func test_the_test_runner_switches_the_roll_screen_off() -> void:
	# tests/run_tests.gd sets it for the whole run; before_each saved whatever it was.
	check(not _roll_enabled_before, "the roll screen is off while the suite runs")


func test_the_roll_view_flag_boots_the_lobby_and_opens_the_screen() -> void:
	var opts := LaunchOptions.parse(PackedStringArray(["--view=roll", "--env=ice_cave"]))
	check_eq(opts.view, "roll", "a known view")
	check(opts.unknown.is_empty(), "no unknown arguments")
	check_eq(opts.boot_state(), &"lobby", "boots into the lobby")
	check(opts.uses_bots(), "with bots")
	check(not opts.starts_run(), "no run")
	EnvironmentRollScreen.enabled = true
	_make_main(opts)
	check(main.roll_screen != null, "the screen opens at boot")
	check_eq(main.roll_screen.winner, &"ice_cave", "on the forced environment")
	main.roll_screen.size = Vector2(1920, 1080)
	main.roll_screen.step(EnvironmentRollScreen.SPIN_TIME + EnvironmentRollScreen.HOLD_TIME + 0.2)
	main._on_roll_finished(&"ice_cave")
	check_eq(main.state, Main.State.LOBBY, "a forced view never starts the run")
	check(main.roll_screen == null, "the screen is freed")


# --- End screen and run card ------------------------------------------------------------------------------------------

func test_the_end_screen_names_the_arena_and_its_hazard() -> void:
	check_eq(GameOverScreen.environment_text(&"cemetery"), "Arena: Cemetery  ·  Grasping Hands", "a hazard environment")
	check_eq(GameOverScreen.environment_text(&"forest_ruin"), "Arena: Forest Ruin", "the forest has no hazard")
	check_eq(GameOverScreen.environment_text(&"nowhere"), "", "an unknown id shows nothing")
	RunState.start_run(1, 5, RunState.MODE_NORMAL, false, &"swamp")
	var screen := GameOverScreen.create()
	tree.root.add_child(screen)
	nodes.append(screen)
	screen.open(false)
	check_eq(screen.environment_label.text, "Arena: Swamp  ·  Bog Pools", "the end screen")
	RunState.start_run(1, 5, RunState.MODE_NORMAL, false, &"forest_ruin")
	screen.open(true)
	check_eq(screen.environment_label.text, "Arena: Forest Ruin", "per run")


func test_the_run_card_carries_the_environment() -> void:
	RunState.start_run(1, 5, RunState.MODE_NORMAL, false, &"ice_cave")
	var summary := RunSummary.collect(false)
	check_eq(summary.get("environment"), "Ice Cave", "the summary names it")
	var card := RunCard.model(summary)
	check_eq(card.get("environment"), "Ice Cave", "the card model")
	var view := RunCardView.create(card)
	nodes.append(view)
	var found := false
	for l in view.find_children("*", "Label", true, false):
		if (l as Label).text.contains("Ice Cave"):
			found = true
			check((l as Label).text.contains("Normal mode"), "next to the mode")
	check(found, "the card shows the arena")
	check_eq(RunCard.model({}).get("environment"), "", "no environment: an empty field")
