extends TestCase
## Projectile: pierce, AoE, range, team filtering, kill credit, arena exit.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 7)
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null


func _launch(team: int, dmg: float, dir: Vector3, max_range: float, pierce: int = 0,
		aoe: float = 0.0, attacker: Node3D = null, start: Vector3 = Vector3(0, 0.7, 0)) -> Projectile:
	var proj := Projectile.create(team, dmg, false, dir, 20.0, max_range, pierce, aoe, attacker)
	world.add_child(proj)
	proj.global_position = start
	return proj


func _fly(proj: Projectile, seconds: float) -> void:
	var t := 0.0
	while t < seconds and not proj.is_done():
		proj.advance(DT)
		t += DT


func test_single_target_stops_at_first_enemy() -> void:
	var a := Fakes.spawn_enemy(world, Vector3(2, 0, 0))
	var b := Fakes.spawn_enemy(world, Vector3(3, 0, 0))
	var proj := _launch(Projectile.TEAM_PLAYERS, 5.0, Vector3.RIGHT, 10.0)
	_fly(proj, 1.0)
	check_eq(a.fake_hits(), 1, "first enemy hit")
	check_eq(b.fake_hits(), 0, "second enemy not hit")
	check(proj.is_done() and proj.is_queued_for_deletion(), "projectile removed")


func test_pierce_counts_extra_targets() -> void:
	var a := Fakes.spawn_enemy(world, Vector3(2, 0, 0))
	var b := Fakes.spawn_enemy(world, Vector3(3.5, 0, 0))
	var c := Fakes.spawn_enemy(world, Vector3(5, 0, 0))
	var off_line := Fakes.spawn_enemy(world, Vector3(3, 0, 2))
	var proj := _launch(Projectile.TEAM_PLAYERS, 5.0, Vector3.RIGHT, 10.0, 1)
	_fly(proj, 1.0)
	check_eq(a.fake_hits(), 1, "first hit")
	check_eq(b.fake_hits(), 1, "pierced into the second")
	check_eq(c.fake_hits(), 0, "pierce 1 stops at the second")
	check_eq(off_line.fake_hits(), 0, "enemy off the line untouched")
	check_eq(proj.hit_count, 2, "two hits")
	check(proj.is_done(), "finished")


func test_fast_projectile_does_not_tunnel() -> void:
	var a := Fakes.spawn_enemy(world, Vector3(2, 0, 0), 0.3)
	var proj := Projectile.create(Projectile.TEAM_PLAYERS, 5.0, false, Vector3.RIGHT, 120.0, 10.0)
	world.add_child(proj)
	proj.global_position = Vector3(0, 0.7, 0)
	proj.advance(DT)  # 2 m in one tick: jumps over the enemy centre
	check_eq(a.fake_hits(), 1, "swept hit test")


func test_aoe_explosion_hits_everything_in_radius() -> void:
	var direct := Fakes.spawn_enemy(world, Vector3(3, 0, 0))
	var near := Fakes.spawn_enemy(world, Vector3(3, 0, 1.5))
	var behind := Fakes.spawn_enemy(world, Vector3(4.2, 0, 0))
	var outside := Fakes.spawn_enemy(world, Vector3(3, 0, 3))
	var proj := _launch(Projectile.TEAM_PLAYERS, 6.0, Vector3.RIGHT, 10.0, 0, 1.6)
	_fly(proj, 1.0)
	check_eq(direct.fake_hits(), 1, "direct target")
	check_eq(near.fake_hits(), 1, "neighbour in radius")
	check_eq(behind.fake_hits(), 1, "enemy behind in radius")
	check_eq(outside.fake_hits(), 0, "outside radius")
	check_eq(proj.hit_count, 3, "three victims")
	check(proj.is_done(), "explodes once")
	check(near.fake_knockback_log[0].z > 0.0, "explosion pushes outwards")


func test_max_range() -> void:
	var proj := _launch(Projectile.TEAM_PLAYERS, 5.0, Vector3.RIGHT, 5.0)
	var far := Fakes.spawn_enemy(world, Vector3(7, 0, 0))
	_fly(proj, 2.0)
	check(proj.is_done(), "freed at the end of its range")
	check_near(proj.travelled, 5.0, 0.001, "flew exactly its range")
	check_near(proj.global_position.y, 0.7, 0.001, "kept its height")
	check_eq(far.fake_hits(), 0, "enemy beyond range untouched")


func test_leaves_arena() -> void:
	var arena := Arena.new()
	var previous := Arena.current
	Arena.current = arena
	var edge := Arena.SIZE.x * 0.5
	var proj := _launch(Projectile.TEAM_PLAYERS, 5.0, Vector3.RIGHT, 100.0, 0, 0.0, null, Vector3(edge - 1.0, 0.7, 0))
	_fly(proj, 1.0)
	check(proj.is_done(), "removed after leaving the arena")
	check(proj.travelled < 4.0, "did not fly its full range")
	Arena.current = previous
	arena.free()


func test_player_projectile_credit_and_leech() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior", Vector3(0, 0, 5))
	p.stats.set_source(&"test", {Stats.LEECH: 100.0})
	p.take_damage(5.0)
	var hp := p.hp
	var e := Fakes.spawn_enemy(world, Vector3(3, 0, 0))
	var proj := _launch(Projectile.TEAM_PLAYERS, 7.0, Vector3.RIGHT, 10.0, 0, 0.0, p)
	proj.knockback = 3.0
	_fly(proj, 1.0)
	check(e.fake_attacker_log[0] == p, "attacker passed for kill credit")
	check_eq(RunState.damage_by_player.get(0, 0.0), 7.0, "damage recorded for P1")
	check_eq(p.hp, hp + 1.0, "leech on projectile hit")
	check(e.fake_knockback_log[0].is_equal_approx(Vector3.RIGHT * 3.0), "knockback along the shot")


func test_enemy_projectile_hits_only_living_players() -> void:
	var ghost := Fakes.spawn_player(world, 0, &"warrior", Vector3(2, 0, 0))
	var target := Fakes.spawn_player(world, 1, &"warrior", Vector3(4, 0, 0))
	var bystander := Fakes.spawn_enemy(world, Vector3(1, 0, 0))
	ghost.take_damage(999.0)
	check(ghost.downed, "ghost downed")
	var proj := _launch(Projectile.TEAM_ENEMIES, 6.0, Vector3.RIGHT, 10.0, 0, 0.0, bystander)
	_fly(proj, 1.0)
	check_eq(bystander.fake_hits(), 0, "enemy projectiles ignore enemies")
	var expected := target.max_hp() - CombatMath.incoming_damage(6.0, target.stats, CombatMath.KIND_PROJECTILE)
	check_eq(target.hp, expected, "living player takes projectile damage")
	check(proj.is_done(), "used up")


func test_enemy_projectile_kind_respects_avoidance() -> void:
	var target := Fakes.spawn_player(world, 0, &"warrior", Vector3(3, 0, 0))
	target.stats.set_source(&"test", {Stats.ARMOR: -2.0, Stats.AVOIDANCE: 50.0})
	var proj := _launch(Projectile.TEAM_ENEMIES, 8.0, Vector3.RIGHT, 10.0)
	_fly(proj, 1.0)
	check_eq(target.hp, target.max_hp() - 4.0, "avoidance halves projectile damage")


func test_all_styles_build() -> void:
	for style: StringName in [&"bolt", &"fireball", &"arrow", &"bullet", &"axe", &"unknown"]:
		var proj := Projectile.create(Projectile.TEAM_ENEMIES, 1.0, false, Vector3.BACK, 5.0, 5.0, 0, 0.0,
				null, style, Projectile.default_color(style))
		world.add_child(proj)
		check(proj.get_child_count() > 0, "%s has a visual" % style)
		proj._process(0.1)
	check_eq(WeaponRunner.projectile_style(Db.get_weapon(&"staff")), &"fireball", "staff style")
	check_eq(WeaponRunner.projectile_style(Db.get_weapon(&"bow")), &"arrow", "bow style")
	check_eq(WeaponRunner.projectile_style(Db.get_weapon(&"gun")), &"bullet", "gun style")
