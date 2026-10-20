extends TestCase
## Hunter bots and determinism (M8, GDD 3.7): a bot Hunter plays its whole kit from data (every slot
## casts by wants_auto_cast, the companion is the Wolf), two identical runs are bit-identical, and the
## Hunter scripts draw RunState.rng for the arrows' crit rolls only.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0
## Two Active slots: a bot Hunter plays one of these kits (and the same two Auto-cast abilities).
const KIT_A: Array[StringName] = [&"arrow_hail", &"quick_draw", &"blast_snare", &"hunt_signal"]
const KIT_B: Array[StringName] = [&"long_shot", &"play_dead", &"blast_snare", &"hunt_signal"]

var world: Node3D


func before_each() -> void:
	PlayerManager.clear()


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	PlayerManager.clear()
	EnemyGrid.mark_dirty()


## A bot Hunter with the six learned abilities facing a ring of fake enemies; returns the enemies.
func _arena(seed_value: int, kit: Array[StringName] = KIT_A) -> Dictionary:
	PlayerManager.clear()
	RunState.start_run(1, seed_value)
	world = Fakes.make_world(tree)
	var slot := PlayerManager.add_bot(&"hunter", 0)
	var hunter := Player.create(slot)
	hunter.stats.remove_source(&"base")
	world.add_child(hunter)
	hunter.stats.set_source(&"test", {Stats.DODGE: -500.0})
	for id in kit:
		check(hunter.abilities.learn(Db.get_ability(id)) >= 0, "%s learned" % id)
	var enemies: Array[Fakes.FakeEnemy] = []
	# A tight group for Arrow Hail ...
	for p in [Vector3(7, 0, 0), Vector3(7.8, 0, 0.6), Vector3(6.4, 0, -0.7), Vector3(7.2, 0, 1.3), Vector3(6.6, 0, 0.9)]:
		var g := Fakes.spawn_enemy(world, p)
		g.hp = 1.0e6
		g.max_hp = 1.0e6
		enemies.append(g)
	# ... and a ring around the Hunter.
	for i in 12:
		var angle := TAU * float(i) / 12.0
		var e := Fakes.spawn_enemy(world, Vector3(sin(angle), 0, cos(angle)) * (3.0 + float(i % 4) * 1.2))
		e.hp = 1.0e6
		e.max_hp = 1.0e6
		if i == 5:
			e.fake_boss = true
		enemies.append(e)
	EnemyGrid.mark_dirty()
	return {"hunter": hunter, "enemies": enemies}


func _step_all(hunter: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		hunter.abilities._physics_process(DT)
		for node in tree.get_nodes_in_group(&"projectiles"):
			var p := node as Projectile
			if p != null and not p.is_queued_for_deletion():
				p.advance(DT)
		for node in tree.get_nodes_in_group(&"ability_areas"):
			(node as AbilityArea)._physics_process(DT)
		for node in tree.get_nodes_in_group(&"hunter_snares"):
			(node as HunterSnare).step(DT)
		var pet := HunterKit.companion(hunter)
		if pet != null:
			pet.step(DT)
		for child in hunter.get_children():
			if child is GeneralBuff:
				(child as GeneralBuff).step(DT)
		t += DT


func test_a_bot_hunter_plays_its_whole_kit() -> void:
	var setup := _arena(7)
	var hunter: Player = setup["hunter"]
	var enemies: Array = setup["enemies"]
	check(hunter.abilities.auto_cast, "a bot casts every slot by its wants_auto_cast")
	check_eq(hunter.companion_id, &"wolf", "and plays with the Wolf")
	var used := {}
	hunter.abilities.ability_cast.connect(func(_i: int, a: AbilityData) -> void: used[a.id] = used.get(a.id, 0) + 1)
	_step_all(hunter, 20.0)
	for id in [&"arrow_fan", &"arrow_hail", &"quick_draw", &"blast_snare", &"hunt_signal"]:
		check(used.get(id, 0) >= 1, "the bot cast %s" % id)
	var total := 0
	for e: Fakes.FakeEnemy in enemies:
		total += e.fake_hits()
	check(total > 50, "and it dealt plenty of hits (%d)" % total)
	check(HunterKit.companion(hunter) != null, "the companion is out")
	var pet_hits := 0
	for e: Fakes.FakeEnemy in enemies:
		for a in e.fake_attacker_log:
			if a == hunter:
				pet_hits += 1
	check(pet_hits == total, "everything is credited to the Hunter (%d of %d)" % [pet_hits, total])


func test_a_bot_hunter_with_the_other_actives_casts_them_too() -> void:
	var setup := _arena(8, KIT_B)
	var hunter: Player = setup["hunter"]
	var used := {}
	hunter.abilities.ability_cast.connect(func(_i: int, a: AbilityData) -> void: used[a.id] = used.get(a.id, 0) + 1)
	# Hurt, with enemies close: Play Dead and Backstep are on the menu.
	hunter.hp = hunter.max_hp() * 0.3
	for e: Fakes.FakeEnemy in setup["enemies"]:
		if e.global_position.length() < 4.0:
			e.global_position = e.global_position.normalized() * 2.0
	EnemyGrid.mark_dirty()
	_step_all(hunter, 12.0)
	check(used.get(&"long_shot", 0) >= 1, "Long Shot (the boss is in reach)")
	check(used.get(&"play_dead", 0) >= 1, "Play Dead (hurt with enemies close)")
	check(used.get(&"backstep", 0) >= 1, "Backstep")


func test_a_bot_hunter_does_not_cast_without_enemies() -> void:
	var setup := _arena(7)
	var hunter: Player = setup["hunter"]
	for e: Fakes.FakeEnemy in setup["enemies"]:
		e.free()
	EnemyGrid.mark_dirty()
	var used := {}
	hunter.abilities.ability_cast.connect(func(_i: int, a: AbilityData) -> void: used[a.id] = used.get(a.id, 0) + 1)
	_step_all(hunter, 8.0)
	check(used.is_empty(), "nothing to shoot at, nothing cast: %s" % [used.keys()])


func _run_once(seed_value: int) -> Array:
	var setup := _arena(seed_value)
	var hunter: Player = setup["hunter"]
	# Crits roll on RunState.rng: leave them on so a different draw order shows.
	hunter.stats.set_source(&"crit", {Stats.CRIT: 30.0})
	_step_all(hunter, 15.0)
	var logs: Array = []
	for e: Fakes.FakeEnemy in setup["enemies"]:
		logs.append(e.fake_damage_log.duplicate())
		logs.append(e.fake_crit_log.duplicate())
	logs.append(RunState.rng.state)
	Fakes.free_world(world)
	world = null
	EnemyGrid.mark_dirty()
	return logs


func test_two_identical_runs_are_bit_identical() -> void:
	var a := _run_once(11)
	var b := _run_once(11)
	check_eq(a.size(), b.size(), "same shape")
	check(a == b, "same damage, crits and rng state with the same seed")
	var c := _run_once(12)
	check(a != c, "a different seed rolls different crits")


func test_the_hunter_scripts_use_the_run_rng_for_arrow_crits_only() -> void:
	var dir := "res://scenes/abilities/hunter/"
	var users: Array[String] = []
	for file in ResourceLoader.list_directory(dir):
		if not file.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string(dir + file)
		for line in src.split("\n"):
			var code := line.strip_edges()
			if code.begins_with("#") or code.begins_with("##"):
				continue
			if "RunState.rng" in code or "randf(" in code.replace("_rng.randf(", "") or "randi(" in code:
				users.append(file)
				break
	check_eq(users, ["hunter_arrow.gd"] as Array[String], "RunState.rng: only the arrows' crit rolls")


func test_visual_randomness_stays_private() -> void:
	# The hail's falling arrows pick their spots with a private RNG (never the run's).
	var src := FileAccess.get_file_as_string("res://scenes/abilities/hunter/hunter_arrow_hail_vfx.gd")
	check("_rng.randf" in src and "RandomNumberGenerator.new()" in src, "a private generator")
