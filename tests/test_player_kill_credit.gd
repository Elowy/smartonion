extends TestCase
## Player weapons against the real Enemy implementation (the other player tests use
## FakeEnemy): kill credit, damage records, knockback and stun end to end.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 31)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null


func _spawn_grunt(pos: Vector3, wave: int = 1) -> Enemy:
	var e := Enemy.create(Db.get_enemy(&"skeleton_grunt"), wave)
	world.add_child(e)
	e.global_position = pos
	return e


## Ticks [param runner] and every projectile in flight until [param done] returns true.
func _run_until(runner: WeaponRunner, seconds: float, done: Callable) -> void:
	var t := 0.0
	while t < seconds and not done.call():
		runner.tick(DT)
		for node in tree.get_nodes_in_group(&"projectiles"):
			(node as Projectile).advance(DT)
		t += DT


func test_melee_kill_credits_the_player() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var e := _spawn_grunt(Vector3(1.5, 0, 0))
	var max_hp := e.max_hp
	var killers: Array[int] = []
	e.died.connect(func(_e: Enemy, idx: int) -> void: killers.append(idx))
	var swings := 0
	while not e.is_dead() and swings < 20:
		p.weapons[0].attack(e)
		swings += 1
	check(e.is_dead(), "grunt killed")
	check_eq(killers, [0] as Array[int], "died(killer_index = P1)")
	check_eq(RunState.kills, 1, "one kill recorded")
	check_eq(RunState.kills_by_player.get(0, 0), 1, "kill credited to P1")
	check(RunState.damage_by_player.get(0, 0.0) >= max_hp, "all damage recorded for P1")
	check(p.weapons[0].find_target() == null, "a dead enemy is no longer a target")


func test_projectile_kill_credits_the_shooter() -> void:
	var p := Fakes.spawn_player(world, 1, &"mage", Vector3(0, 0, 0))
	p.equip_weapons(Db.get_weapon(&"wand"), null)
	var e := _spawn_grunt(Vector3(0, 0, -5))
	_run_until(p.weapons[0], 6.0, func() -> bool: return e.is_dead())
	check(e.is_dead(), "killed by arcane bolts")
	check_eq(RunState.kills_by_player.get(1, 0), 1, "kill credited to P2 (slot index 1)")
	check_eq(RunState.kills_by_player.get(0, 0), 0, "nothing credited to P1")
	check(RunState.damage_by_player.get(1, 0.0) > 0.0, "projectile damage recorded")


func test_fireball_explosion_kills_a_pack() -> void:
	var p := Fakes.spawn_player(world, 0, &"warlock")
	p.equip_weapons(Db.get_weapon(&"staff"), null)
	p.stats.set_source(&"test", {Stats.INTELLECT: 60.0})  # one blast is lethal
	var pack: Array[Enemy] = [
		_spawn_grunt(Vector3(0, 0, -5)),
		_spawn_grunt(Vector3(0.8, 0, -5.3)),
		_spawn_grunt(Vector3(-0.7, 0, -5.5)),
	]
	var survivor := _spawn_grunt(Vector3(4.0, 0, -5))
	_run_until(p.weapons[0], 3.0, func() -> bool: return pack[0].is_dead())
	for e in pack:
		check(e.is_dead(), "%s inside the blast died" % e.name)
	check(not survivor.is_dead(), "enemy outside the radius survives")
	check_eq(RunState.kills_by_player.get(0, 0), 3, "three kills credited")


func test_real_enemy_knockback_and_stun() -> void:
	var p := Fakes.spawn_player(world, 0, &"paladin")
	var mace := Db.get_weapon(&"mace").duplicate() as WeaponData
	mace.stun_chance = 1.0
	p.equip_weapons(mace, Db.get_weapon(&"shield"))
	var e := _spawn_grunt(Vector3(1.4, 0, 0), 25)  # sturdy enough to survive a hit
	p.weapons[0].attack(e)
	check(not e.is_dead(), "survives one hit")
	check(e.hp < e.max_hp, "took damage")
	check(e.is_stunned(), "stunned by the mace")
	check(e.knockback_velocity.x > 0.0, "pushed away from the player (+X)")
	check_near(e.knockback_velocity.z, 0.0, 0.001, "pushed along the swing direction")
