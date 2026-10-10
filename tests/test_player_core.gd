extends TestCase
## Player: stats, damage pipeline, i-frames, downed / revive, wave start, regen, movement.

const Fakes := preload("res://tests/player_fakes.gd")

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 1234)
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null


func test_stats_from_class_and_weapons() -> void:
	var warrior := Fakes.spawn_player(world, 0, &"warrior")
	check_eq(warrior.max_hp(), 15.0, "warrior max hp = 10 + 5 stamina")
	check_eq(warrior.hp, 15.0, "starts at full hp")
	check_eq(warrior.stats.get_stat(Stats.ARMOR), 2.0, "warrior armour")
	check_eq(warrior.stats.move_speed(), Stats.BASE_MOVE_SPEED * 0.95, "-5% speed")
	check_eq(warrior.weapons.size(), 1, "one sword runner")
	check(warrior.is_in_group(&"players"), "in players group")
	check_eq(warrior.collision_layer, 2, "layer 2")
	check_eq(warrior.collision_mask, 1, "mask 1")
	check(warrior.model != null and warrior.model.get_parent() == warrior, "has an onion model")
	check(warrior.slot.player == warrior, "slot knows its player")

	var paladin := Fakes.spawn_player(world, 1, &"paladin", Vector3(3, 0, 0))
	check_eq(paladin.stats.get_stat(Stats.ARMOR), 5.0, "3 class + 2 shield armour")
	check_eq(paladin.block_chance(), 10.0, "shield block")
	check_eq(paladin.weapons.size(), 1, "shield does not attack")
	check(paladin.stats.has_source(&"weapon:off"), "shield is a stat source")
	check_eq(paladin.stats.get_raw(Stats.DAMAGE_PCT), -10.0, "-10% damage")

	var rogue := Fakes.spawn_player(world, 2, &"rogue", Vector3(-3, 0, 0))
	check_eq(rogue.weapons.size(), 2, "two daggers")
	check(not rogue.weapons[0].is_off_hand and rogue.weapons[1].is_off_hand, "main then off hand")
	check_eq(rogue.max_hp(), 7.0, "rogue -3 stamina")

	var mage := Fakes.spawn_player(world, 3, &"mage", Vector3(0, 0, 3))
	mage.equip_weapons(Db.get_weapon(&"wand"), Db.get_weapon(&"tome"))
	check_eq(mage.stats.get_raw(Stats.INTELLECT), 5.0, "3 class + 2 tome intellect")
	check_eq(mage.stats.get_stat(Stats.CRIT), 3.0, "tome crit")
	check_eq(mage.weapons.size(), 1, "tome does not attack")
	mage.equip_weapons(Db.get_weapon(&"staff"), null)
	check(not mage.stats.has_source(&"weapon:off"), "unequipped off hand removes its stats")
	check_eq(mage.stats.get_raw(Stats.INTELLECT), 3.0, "tome intellect gone")


func test_armor_reduces_damage() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	p.stats.set_source(&"test", {Stats.ARMOR: 13.0})  # total 15 -> 50%
	var changes: Array[float] = []
	p.hp_changed.connect(func(value: float, _max: float) -> void: changes.append(value))
	p.take_damage(10.0)
	check_eq(p.hp, 10.0, "15 - 5")
	check_eq(changes.size(), 1, "hp_changed emitted once")
	check_eq(changes[0], 10.0, "hp_changed value")


func test_projectile_damage_uses_avoidance() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	p.stats.set_source(&"test", {Stats.ARMOR: -2.0, Stats.AVOIDANCE: 50.0})  # armour 0
	p.take_damage(10.0, CombatMath.KIND_PROJECTILE)
	check_eq(p.hp, 10.0, "avoidance halves projectiles")
	p.invulnerable_left = 0.0
	p.take_damage(4.0, CombatMath.KIND_MELEE)
	check_eq(p.hp, 6.0, "avoidance ignores melee")


func test_shield_block_halves_damage() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var shield := Db.get_weapon(&"shield").duplicate() as WeaponData
	shield.block_chance = 100.0
	p.equip_weapons(Db.get_weapon(&"sword"), shield)
	p.stats.set_source(&"test", {Stats.ARMOR: -4.0})  # 2 class + 2 shield - 4 = 0
	p.take_damage(10.0)
	check_eq(p.hp, 10.0, "blocked hit deals half")


func test_dodge_avoids_whole_hit() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	p.stats.set_source(&"test", {Stats.DODGE: 60.0})
	var dodged := 0
	for i in 200:
		p.hp = p.max_hp()
		p.invulnerable_left = 0.0
		p.take_damage(1.0)
		if p.hp == p.max_hp():
			dodged += 1
			check_eq(p.invulnerable_left, 0.0, "a dodge grants no i-frames")
	check(dodged > 90 and dodged < 150, "about 60%% dodged (got %d)" % dodged)

	var never := Fakes.spawn_player(world, 1, &"warrior", Vector3(4, 0, 0))
	for i in 50:
		never.hp = never.max_hp()
		never.invulnerable_left = 0.0
		never.take_damage(1.0)
		check(never.hp < never.max_hp(), "0% dodge never dodges")


func test_invulnerable_after_hit() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	p.take_damage(3.0)
	var after_first := p.hp
	check(after_first < 15.0, "first hit lands")
	p.take_damage(3.0)
	check_eq(p.hp, after_first, "second hit ignored during i-frames")
	Fakes.step(p, Player.INVULNERABLE_AFTER_HIT + 0.05)
	p.take_damage(3.0)
	check(p.hp < after_first, "hit lands after i-frames")


func test_downed_and_revive_timing() -> void:
	var p1 := Fakes.spawn_player(world, 0, &"warrior")
	var p2 := Fakes.spawn_player(world, 1, &"warrior", Vector3(1.0, 0, 0))
	var downed_events: Array[bool] = []
	p1.downed_changed.connect(func(v: bool) -> void: downed_events.append(v))
	p1.take_damage(999.0)
	check(p1.downed, "downed at 0 hp")
	check(not p1.is_alive(), "not alive")
	check_eq(p1.hp, 0.0, "hp 0")
	check_eq(downed_events, [true] as Array[bool], "downed_changed(true)")
	p1.invulnerable_left = 0.0
	p1.take_damage(5.0)
	check_eq(p1.hp, 0.0, "downed players take no damage")
	p1.heal(5.0)
	check_eq(p1.hp, 0.0, "downed players cannot be healed")

	# A living teammate 1 m away revives after REVIVE_TIME seconds.
	for i in 29:
		p1._physics_process(0.1)
	check(p1.downed, "still downed after 2.9 s")
	check_near(p1.revive_progress, 2.9, 0.01, "progress")
	p1._physics_process(0.1)
	check(not p1.downed, "revived after 3 s")
	check_eq(p1.hp, roundf(15.0 * Player.REVIVE_HP_RATIO), "revived at 30% hp")
	check_eq(downed_events, [true, false] as Array[bool], "downed_changed(false)")
	check(p1.invulnerable_left > 0.0, "short grace after revive")
	check(p2.is_alive(), "reviver unaffected")


func test_revive_needs_living_teammate_nearby() -> void:
	var p1 := Fakes.spawn_player(world, 0, &"warrior")
	var p2 := Fakes.spawn_player(world, 1, &"warrior", Vector3(Player.REVIVE_RADIUS + 1.0, 0, 0))
	p1.take_damage(999.0)
	Fakes.step(p1, 5.0, 0.1)
	check(p1.downed, "teammate too far away")
	check_eq(p1.revive_progress, 0.0, "no progress")
	p2.global_position = Vector3(1.0, 0, 0)
	Fakes.step(p1, 1.0, 0.1)
	check_near(p1.revive_progress, 1.0, 0.01, "progress while close")
	p2.global_position = Vector3(10.0, 0, 0)
	Fakes.step(p1, 1.0, 0.1)
	check_near(p1.revive_progress, 1.0 - Player.REVIVE_DECAY_PER_SECOND, 0.01, "decays slowly")
	# A downed teammate cannot revive.
	p2.global_position = Vector3(1.0, 0, 0)
	p2.take_damage(999.0)
	Fakes.step(p1, 4.0, 0.1)
	check(p1.downed, "downed teammate does not revive")


func test_downed_ghost_does_not_attack_and_moves_slowly() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	Fakes.spawn_enemy(world, Vector3(1.5, 0, 0))
	p.take_damage(999.0)
	check(not p.weapons[0].tick(1.0), "ghost does not attack")
	(p.slot.input as ScriptedInput).move = Vector2(0, -1)
	p.global_position = Vector3(0, 0, 5)
	Fakes.step(p, 1.0)
	check_near(p.velocity.length(), p.stats.move_speed() * Player.GHOST_SPEED_MULT, 0.01, "half speed")


func test_begin_wave_heals_and_revives() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	p.take_damage(6.0)
	check(p.hp < p.max_hp(), "damaged")
	p.begin_wave()
	check_eq(p.hp, p.max_hp(), "living -> full hp")
	p.take_damage(999.0)
	check(p.downed, "downed")
	var events: Array[bool] = []
	p.downed_changed.connect(func(v: bool) -> void: events.append(v))
	p.begin_wave()
	check(not p.downed, "back at wave start")
	check_eq(p.hp, roundf(p.max_hp() * 0.5), "50% hp")
	check_eq(events, [false] as Array[bool], "downed_changed(false)")
	check_eq(p.invulnerable_left, 0.0, "no leftover i-frames")


func test_spirit_regen_accumulates_fractions() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	p.stats.set_source(&"test", {Stats.SPIRIT: 15.0})  # 1 hp / s
	p.take_damage(5.0)
	var start := p.hp
	Fakes.step(p, 0.9)
	check_eq(p.hp, start, "no regen before a whole point")
	Fakes.step(p, 0.2)
	check_eq(p.hp, start + 1.0, "+1 after a second")
	Fakes.step(p, 1.0)
	check_eq(p.hp, start + 2.0, "+2 after two seconds")
	p.hp = p.max_hp()
	Fakes.step(p, 3.0)
	check_eq(p.hp, p.max_hp(), "never above max")


func test_leech_heals_on_hit() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	p.take_damage(5.0)
	var hp := p.hp
	p.on_hit_dealt(4.0, null)
	check_eq(p.hp, hp, "0% leech does nothing")
	p.stats.set_source(&"test", {Stats.LEECH: 100.0})
	p.on_hit_dealt(4.0, null)
	check_eq(p.hp, hp + 1.0, "100% leech heals 1")


func test_movement_follows_input() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var input := p.slot.input as ScriptedInput
	input.move = Vector2(1, 0)
	Fakes.step(p, 1.0)
	var speed := p.stats.move_speed()
	check(p.global_position.x > speed * 0.85 and p.global_position.x <= speed + 0.001,
			"moved ~speed metres to +X (got %.2f)" % p.global_position.x)
	check_near(p.global_position.z, 0.0, 0.001, "no drift on Z")
	check_near(p.global_position.y, 0.0, 0.001, "stays on the ground")
	check(p.facing.is_equal_approx(Vector3.RIGHT), "faces +X")
	input.move = Vector2(0, -1)
	Fakes.step(p, 0.5)
	check(p.facing.is_equal_approx(Vector3.FORWARD), "screen-up = -Z")
	input.move = Vector2.ZERO
	Fakes.step(p, 0.5)
	check_near(p.velocity.length(), 0.0, 0.001, "stops")
	check(p.facing.is_equal_approx(Vector3.FORWARD), "keeps last facing")


func test_movement_clamped_to_arena() -> void:
	var arena := Arena.new()
	var previous := Arena.current
	Arena.current = arena
	var p := Fakes.spawn_player(world, 0, &"warrior")
	(p.slot.input as ScriptedInput).move = Vector2(1, 0)
	p.global_position = Vector3(Arena.SIZE.x * 0.5 - 0.5, 0, 0)
	Fakes.step(p, 1.0)
	check(p.global_position.x <= Arena.SIZE.x * 0.5 - Player.RADIUS + 0.001, "clamped inside the arena")
	Arena.current = previous
	arena.free()
