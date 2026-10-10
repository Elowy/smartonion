extends TestCase
## WeaponRunner: cooldown / haste, target selection, melee arc, crit, stun, kill credit.

const Fakes := preload("res://tests/player_fakes.gd")

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 99)
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null


func test_cooldown_with_haste() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var runner := p.weapons[0]
	check_eq(runner.cooldown(), 0.9, "sword base cooldown")
	p.stats.set_source(&"test", {Stats.HASTE: 50.0})
	check_eq(runner.cooldown(), 0.6, "haste 50% -> 0.9 / 1.5")
	var enemy := Fakes.spawn_enemy(world, Vector3(1.5, 0, 0))
	check(runner.tick(1.0 / 60.0), "ready weapon attacks at once")
	check_eq(enemy.fake_hits(), 1, "one hit")
	check(not runner.tick(0.55), "still cooling down")
	check(runner.tick(0.06), "fires again after the hasted cooldown")
	check_eq(enemy.fake_hits(), 2, "two hits")


func test_attack_rate_over_time() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var runner := p.weapons[0]
	var enemy := Fakes.spawn_enemy(world, Vector3(0, 0, -1.5))
	var t := 0.0
	while t < 9.0 - 0.0001:
		runner.tick(1.0 / 60.0)
		t += 1.0 / 60.0
	# Attacks at 0, 0.9, ..., 8.1 -> 10 swings in 9 s.
	check(enemy.fake_hits() >= 9 and enemy.fake_hits() <= 11, "~10 swings in 9 s (got %d)" % enemy.fake_hits())


func test_no_target_out_of_range_and_nearest_first() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var runner := p.weapons[0]
	var far := Fakes.spawn_enemy(world, Vector3(5, 0, 0))
	check(runner.find_target() == null, "5 m is out of sword range")
	check(not runner.tick(0.1), "nothing to attack")
	check_eq(far.fake_hits(), 0, "far enemy untouched")
	var mid := Fakes.spawn_enemy(world, Vector3(0, 0, 2.0))
	var near := Fakes.spawn_enemy(world, Vector3(-1.2, 0, 0))
	check(runner.find_target() == near, "nearest enemy is the target")
	near.fake_dead = true
	check(runner.find_target() == mid, "dead enemies are skipped")


func test_melee_arc_selection() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")  # sword: range 2.3, arc 110
	var runner := p.weapons[0]
	var target := Fakes.spawn_enemy(world, Vector3(1.5, 0, 0))
	var side_in := Fakes.spawn_enemy(world, Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(60)) * 1.6)
	var side_out := Fakes.spawn_enemy(world, Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(110)) * 1.6)
	var behind := Fakes.spawn_enemy(world, Vector3(-1.55, 0, 0))
	var edge := Fakes.spawn_enemy(world, Vector3(2.3 + 0.45 - 0.05, 0, 0.2))
	var beyond := Fakes.spawn_enemy(world, Vector3(2.3 + 0.45 + 0.2, 0, 0))
	var big := Fakes.spawn_enemy(world, Vector3(0, 0, 2.3 + 0.9), 1.0)
	check(runner.find_target() == target, "target is the nearest")
	runner.attack(target)
	check_eq(target.fake_hits(), 1, "target hit")
	check_eq(side_in.fake_hits(), 1, "60 deg off-axis is inside the 110 deg arc (+ body width)")
	check_eq(side_out.fake_hits(), 0, "110 deg off-axis is outside")
	check_eq(behind.fake_hits(), 0, "behind is not hit")
	check_eq(edge.fake_hits(), 1, "range counts the enemy radius")
	check_eq(beyond.fake_hits(), 0, "beyond range + radius")
	check_eq(big.fake_hits(), 0, "90 deg off-axis big enemy is outside the arc")
	var expected := CombatMath.weapon_hit_damage(Db.get_weapon(&"sword"), p.stats)
	check_eq(target.fake_damage_log[0], expected, "weapon_hit_damage")


func test_static_arc_helper() -> void:
	var a := Fakes.spawn_enemy(world, Vector3(0, 0, -1.0))
	var b := Fakes.spawn_enemy(world, Vector3(0, 0, 1.0))
	var nodes := tree.get_nodes_in_group(&"enemies")
	var hits := WeaponRunner.enemies_in_arc(nodes, Vector3.ZERO, Vector3.FORWARD, 2.0, 90.0)
	check(a in hits and b not in hits, "only the enemy in front")
	var overlap := Fakes.spawn_enemy(world, Vector3(0, 0, 0.2))
	hits = WeaponRunner.enemies_in_arc(tree.get_nodes_in_group(&"enemies"), Vector3.ZERO, Vector3.FORWARD, 2.0, 90.0)
	check(overlap in hits, "an enemy on top of the player is always hit")


func test_damage_record_kill_credit_and_knockback() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var enemy := Fakes.spawn_enemy(world, Vector3(1.5, 0, 0))
	var dealt: Array[float] = []
	p.hit_dealt.connect(func(d: float, _t: Node3D) -> void: dealt.append(d))
	p.weapons[0].attack(enemy)
	var dmg := enemy.fake_damage_log[0]
	check(enemy.fake_attacker_log[0] == p, "the player is passed as attacker (kill credit)")
	check_eq(RunState.damage_by_player.get(0, 0.0), dmg, "record_damage(slot index, dmg)")
	check(enemy.fake_knockback_log[0].is_equal_approx(Vector3.RIGHT * Db.get_weapon(&"sword").knockback),
			"knockback along the swing direction")
	check_eq(dealt, [dmg] as Array[float], "on_hit_dealt called")


func test_crit_multiplies_damage() -> void:
	var p := Fakes.spawn_player(world, 0, &"rogue")
	p.stats.set_source(&"test", {Stats.CRIT: 100.0})
	var enemy := Fakes.spawn_enemy(world, Vector3(1.0, 0, 0))
	p.weapons[0].attack(enemy)
	var dagger := Db.get_weapon(&"dagger")
	check(enemy.fake_crit_log[0], "crit flag passed")
	check_eq(enemy.fake_damage_log[0], CombatMath.weapon_hit_damage(dagger, p.stats) * dagger.crit_mult, "x2.5")


func test_stun_chance() -> void:
	var p := Fakes.spawn_player(world, 0, &"paladin")
	var mace := Db.get_weapon(&"mace").duplicate() as WeaponData
	mace.stun_chance = 1.0
	p.equip_weapons(mace, Db.get_weapon(&"shield"))
	var enemy := Fakes.spawn_enemy(world, Vector3(1.0, 0, 0))
	p.weapons[0].attack(enemy)
	check_eq(enemy.fake_stun_count, 1, "100% stun chance stuns")
	mace.stun_chance = 0.0
	p.weapons[0].attack(enemy)
	check_eq(enemy.fake_stun_count, 1, "0% never stuns")


func test_dual_wield_alternates() -> void:
	var p := Fakes.spawn_player(world, 0, &"rogue")
	var main := p.weapons[0]
	var off := p.weapons[1]
	var cd := main.cooldown()
	check_near(off.cooldown_left, cd * WeaponRunner.OFF_HAND_PHASE, 0.0001, "off hand starts half a cooldown late")
	# Idle without enemies, then an enemy arrives.
	for _i in 60:
		main.tick(1.0 / 60.0)
		off.tick(1.0 / 60.0)
	Fakes.spawn_enemy(world, Vector3(1.0, 0, 0))
	check(main.tick(1.0 / 60.0), "main hand attacks first")
	check(not off.tick(1.0 / 60.0), "off hand waits")
	var main_times: Array[float] = []
	var off_times: Array[float] = []
	var t := 0.0
	while t < 2.0:
		t += 1.0 / 60.0
		if main.tick(1.0 / 60.0):
			main_times.append(t)
		if off.tick(1.0 / 60.0):
			off_times.append(t)
	check(not off_times.is_empty() and not main_times.is_empty(), "both hands attack")
	check_near(off_times[0], cd * WeaponRunner.OFF_HAND_PHASE, 0.05, "off hand half a cooldown later")
	check_near(main_times[0], cd, 0.02, "main hand on its own cooldown")


func test_projectile_weapon_fires_projectile() -> void:
	var p := Fakes.spawn_player(world, 0, &"mage")
	var enemy := Fakes.spawn_enemy(world, Vector3(0, 0, -5))
	check(p.weapons[0].tick(1.0 / 60.0), "wand fires")
	var projectiles := tree.get_nodes_in_group(&"projectiles")
	check_eq(projectiles.size(), 1, "one projectile spawned")
	if projectiles.is_empty():
		return
	var proj := projectiles[0] as Projectile
	check_eq(proj.team, Projectile.TEAM_PLAYERS, "player team")
	check(proj.attacker == p, "attacker is the player")
	check(proj.direction.is_equal_approx(Vector3.FORWARD), "flies at the target")
	check_eq(proj.style, &"bolt", "wand -> arcane bolt")
	check_near(proj.global_position.y, Player.CHEST_HEIGHT, 0.001, "chest height")
	for _i in 60:
		proj.advance(1.0 / 60.0)
		if proj.is_done():
			break
	check_eq(enemy.fake_hits(), 1, "bolt hits the enemy")
	check(proj.is_done(), "single-target bolt is used up")
	check_eq(RunState.damage_by_player.get(0, 0.0), enemy.fake_damage_log[0], "projectile damage recorded")
