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


func test_create_binds_bot_and_slot() -> void:
	var slot := PlayerSlot.new(2, BotInput.new("bot:test", 5), PlayerManager.PLAYER_COLORS[2])
	slot.class_data = null  # falls back to the default class
	var p := Player.create(slot)
	check(p.class_data == Db.get_default_class(), "default class without a pick")
	check((slot.input as BotInput).body == p, "the bot steers this player")
	check(slot.player == p, "slot.player set")
	check_eq(p.name, "Player3", "named after the slot")
	check_eq(p.hp, p.max_hp(), "full hp before entering the tree")
	p.free()
	check(slot.player == null, "freed player clears slot.player")


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
	for _i in 200:
		p.hp = p.max_hp()
		p.invulnerable_left = 0.0
		p.take_damage(1.0)
		if p.hp == p.max_hp():
			dodged += 1
			check_eq(p.invulnerable_left, 0.0, "a dodge grants no i-frames")
	check(dodged > 90 and dodged < 150, "about 60%% dodged (got %d)" % dodged)

	var never := Fakes.spawn_player(world, 1, &"warrior", Vector3(4, 0, 0))
	for _i in 50:
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

	# A living teammate 1 m away revives after REVIVE_TIME (GDD 1: 5 s).
	check_eq(Player.REVIVE_TIME, 5.0, "5 s revive")
	for _i in 49:
		p1._physics_process(0.1)
	check(p1.downed, "still downed after 4.9 s")
	check_near(p1.revive_progress, 4.9, 0.01, "progress")
	check_eq(p1.reviver_count, 1, "one reviver")
	check_near(p1.revive_seconds_left(), 0.1, 0.01, "0.1 s left")
	p1._physics_process(0.1)
	check(not p1.downed, "revived after 5 s")
	check_eq(p1.hp, roundf(15.0 * Player.REVIVE_HP_RATIO), "revived at 30% hp")
	check_eq(downed_events, [true, false] as Array[bool], "downed_changed(false)")
	check_eq(Player.INVULNERABLE_AFTER_REVIVE, 1.0, "GDD 1: 1 s invulnerability")
	check_near(p1.invulnerable_left, Player.INVULNERABLE_AFTER_REVIVE, 0.001, "invulnerable after the revive")
	check_eq(p1.reviver_count, 0, "no revivers once alive")
	check_eq(p1.revive_seconds_left(), -1.0, "nothing left to cast")
	var hp_after := p1.hp
	p1.take_damage(5.0)
	check_eq(p1.hp, hp_after, "hits ignored during the grace")
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
	check_eq(p1.reviver_count, 0, "nobody in the circle")
	check_eq(p1.revive_seconds_left(), -1.0, "no cast time while nobody revives")
	# A downed teammate cannot revive.
	p2.global_position = Vector3(1.0, 0, 0)
	p2.take_damage(999.0)
	Fakes.step(p1, 4.0, 0.1)
	check(p1.downed, "downed teammate does not revive")


func test_more_revivers_revive_faster() -> void:
	check_eq(Player.revive_speed(0), 0.0, "nobody reviving")
	check_eq(Player.revive_speed(1), 1.0, "1 reviver = 1x")
	check_eq(Player.revive_speed(2), 1.5, "2 revivers = 1.5x")
	check_eq(Player.revive_speed(3), 2.0, "3 revivers = 2x")
	var ghost := Fakes.spawn_player(world, 0, &"warrior")
	Fakes.spawn_player(world, 1, &"warrior", Vector3(1.0, 0, 0))
	Fakes.spawn_player(world, 2, &"warrior", Vector3(-1.0, 0, 0))
	var third := Fakes.spawn_player(world, 3, &"warrior", Vector3(0, 0, 1.0))
	ghost.take_damage(999.0)
	Fakes.step(ghost, 1.0, 0.1)
	check_eq(ghost.reviver_count, 3, "three revivers in the circle")
	check_near(ghost.revive_progress, 2.0, 0.01, "2x speed")
	check_near(ghost.revive_seconds_left(), 1.5, 0.01, "(5 - 2) / 2 s left")
	var cast_text: String = ghost.model._cast_label.text
	check("1.5" in cast_text, "the cast bar shows the faster time: %s" % cast_text)
	# One reviver walks away: 1.5x for the rest.
	third.global_position = Vector3(10.0, 0, 0)
	Fakes.step(ghost, 1.0, 0.1)
	check_eq(ghost.reviver_count, 2, "two revivers left")
	check_near(ghost.revive_progress, 3.5, 0.01, "1.5x speed")
	check_near(ghost.revive_seconds_left(), 1.0, 0.01, "1.5 / 1.5 s left")
	Fakes.step(ghost, 1.05, 0.05)
	check(not ghost.downed, "revived after 1 + 1 + 1 s instead of 5 s")


func test_revive_is_not_interrupted_by_damage_and_ends_with_a_light_column() -> void:
	var ghost := Fakes.spawn_player(world, 0, &"warrior", Vector3(2.0, 0, -1.0))
	var reviver := Fakes.spawn_player(world, 1, &"warrior", Vector3(3.0, 0, -1.0))
	ghost.take_damage(999.0)
	Fakes.step(ghost, 2.0, 0.1)
	reviver.take_damage(3.0)
	check(reviver.is_alive() and reviver.hp < reviver.max_hp(), "the reviver got hit")
	Fakes.step(ghost, 0.1, 0.1)
	check_near(ghost.revive_progress, 2.1, 0.01, "taking damage does not interrupt the revive")
	var feet := ghost.global_position
	Fakes.step(ghost, 2.9, 0.1)
	check(not ghost.downed, "revived")
	var column: VfxEffect = null
	var resurrected := false
	for c in world.get_children():
		var fx := c as VfxEffect
		if fx == null:
			continue
		if fx.kind == VfxEffect.Kind.RESURRECT:
			column = fx
		var label := fx.get_node_or_null("Label") as Label3D
		if label != null and label.text == "Resurrected!":
			resurrected = true
	check(column != null, "a column of light from the sky")
	if column != null:
		var d := column.global_position - feet
		check(Vector2(d.x, d.z).length() < 0.01, "at the revived player's feet")
	check(resurrected, "\"Resurrected!\" floating text")


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


func test_team_level_placeholder_bonus() -> void:
	# TEMPORARY M1 placeholder (until the M4 level-up cards): +1 Max HP, +4% damage per level.
	var p := Fakes.spawn_player(world, 0, &"warrior")
	check(not p.stats.has_source(Player.LEVEL_SOURCE), "no level bonus at level 0")
	var dmg_pct := p.stats.get_raw(Stats.DAMAGE_PCT)
	var mult := p.stats.damage_mult()
	var ghost := Fakes.spawn_player(world, 1, &"warrior", Vector3(4, 0, 0))
	ghost.take_damage(999.0)
	check(ghost.downed, "ghost downed")
	p.stats.set_source(&"test", {Stats.ARMOR: -2.0})  # 2 class armour - 2 = 0
	p.take_damage(5.0)
	check_eq(p.hp, 10.0, "15 - 5")
	var hp_events: Array[float] = []
	p.hp_changed.connect(func(value: float, _max: float) -> void: hp_events.append(value))
	RunState.add_xp(RunState.xp_to_next_level())
	check_eq(RunState.level, 1, "levelled up")
	check_eq(p.max_hp(), 16.0, "+1 max hp")
	check_eq(p.hp, 11.0, "current hp rises by the max hp gained")
	check(not hp_events.is_empty() and is_equal_approx(hp_events[-1], 11.0), "hp_changed with the new hp")
	check_eq(p.stats.get_raw(Stats.DAMAGE_PCT), dmg_pct + 4.0, "+4% damage")
	check_eq(p.stats.damage_mult(), mult + 0.04, "damage mult +0.04")
	check_eq(ghost.hp, 0.0, "a ghost stays at 0 hp")
	check_eq(ghost.max_hp(), 16.0, "but its max hp grows too")
	# Two levels at once (one leveled_up per level).
	RunState.add_xp(RunState.xp_to_next_level() + RunState.xp_needed_for_level(3, 1))
	check_eq(RunState.level, 3, "two more levels")
	check_eq(p.max_hp(), 18.0, "+3 max hp in total")
	check_eq(p.hp, 13.0, "+2 hp from the two levels")
	check_eq(p.stats.get_raw(Stats.DAMAGE_PCT), dmg_pct + 12.0, "+12% damage in total")
	# A hero created mid-run starts with the team level's bonus at full hp.
	var late := Fakes.spawn_player(world, 2, &"warrior", Vector3(-4, 0, 0))
	check_eq(late.max_hp(), 18.0, "late hero has the level bonus")
	check_eq(late.hp, 18.0, "at full hp")


func test_floating_numbers_round_for_display() -> void:
	check_eq(Player._format_amount(2.0), "2", "whole")
	check_eq(Player._format_amount(1.32), "1.3", "one decimal")
	check_eq(Player._format_amount(1.875), "1.9", "rounded to one decimal")
	check_eq(Player._format_amount(4.98), "5", "no trailing .0")
	var p := Fakes.spawn_player(world, 0, &"warrior")
	p.stats.set_source(&"test", {Stats.ARMOR: -1.0})  # 2 class - 1 = 1 armour
	p.take_damage(2.0)
	check_near(p.hp, 15.0 - 2.0 * (1.0 - 1.0 / 16.0), 0.0001, "1 armour reduces a 2-damage hit")


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
	var input := p.slot.input as ScriptedInput
	input.move = Vector2(1, 0)
	p.global_position = Vector3(Arena.SIZE.x * 0.5 - 0.5, 0, 0)
	Fakes.step(p, 1.0)
	check(p.global_position.x <= Arena.SIZE.x * 0.5 - Player.RADIUS + 0.001, "clamped inside the arena")
	check_near(p.velocity.x, 0.0, 0.001, "no velocity into the wall")
	# Pushing diagonally into the wall slides along it.
	input.move = Vector2(1, 1).normalized()
	var z0 := p.global_position.z
	Fakes.step(p, 0.5)
	check(p.global_position.x <= Arena.SIZE.x * 0.5 - Player.RADIUS + 0.001, "still inside")
	check(p.global_position.z - z0 > p.stats.move_speed() * 0.707 * 0.5 * 0.7, "slides along the wall")
	# Outside the bounds (e.g. a bad spawn) it is pulled back in and can walk away freely.
	input.move = Vector2(-1, 0)
	p.global_position = Vector3(Arena.SIZE.x * 0.5 + 2.0, 0, 0)
	Fakes.step(p, 1.0 / 60.0)
	check(p.global_position.x <= Arena.SIZE.x * 0.5 - Player.RADIUS + 0.001, "pulled back inside")
	var x0 := p.global_position.x
	Fakes.step(p, 0.5)
	check(p.global_position.x < x0 - 1.0, "walks away from the wall")
	Arena.current = previous
	arena.free()


func test_clamp_motion_to_rect() -> void:
	var r := Rect2(-2.0, -1.0, 4.0, 2.0)  # x -2..2, z -1..1
	check_eq(Player.clamp_motion_to_rect(Vector3(0, 0, 0), Vector3(0.5, 0.2, -0.3), r), Vector3(0.5, 0.2, -0.3), "inside: untouched")
	check_eq(Player.clamp_motion_to_rect(Vector3(1, 0, 0), Vector3(3, 0, 0.5), r), Vector3(1, 0, 0.5), "x stops at the edge, z slides on")
	check_eq(Player.clamp_motion_to_rect(Vector3(0, 0, 0.5), Vector3(0, 0, 2), r), Vector3(0, 0, 0.5), "z stops at the edge")
	# Already outside (the camera moved): never pushed, never further out, free to come back.
	check_eq(Player.clamp_motion_to_rect(Vector3(5, 0, 0), Vector3(1, 0, 0), r), Vector3(0, 0, 0), "no further out")
	check_eq(Player.clamp_motion_to_rect(Vector3(5, 0, 0), Vector3(-1, 0, 0), r), Vector3(-1, 0, 0), "walks back in")
	check_eq(Player.clamp_motion_to_rect(Vector3(5, 0, 0), Vector3(0, 0, 0.5), r), Vector3(0, 0, 0.5), "slides along outside")
	# A squeezed (zero-size) rect only allows moving towards it.
	var dot := Rect2(0.0, 0.0, 0.0, 0.0)
	check_eq(Player.clamp_motion_to_rect(Vector3(3, 0, 0), Vector3(-1, 0, 0), dot), Vector3(-1, 0, 0), "towards the team")
	check_eq(Player.clamp_motion_to_rect(Vector3(3, 0, 0), Vector3(1, 0, 0), dot), Vector3(0, 0, 0), "not away")


## GDD 13: once the camera is fully zoomed out, the screen edge is an invisible wall.
func test_screen_edge_stops_runaways() -> void:
	var arena := Arena.new()  # bare arena: bounds only (34 x 22 m)
	var previous := Arena.current
	Arena.current = arena
	var rig := CameraRig.new()
	world.add_child(rig)
	arena.camera = rig
	var spread := CameraRig.max_spread(rig._aspect())
	# A teammate far west (outside the bare arena, so the wall binds inside it): at full
	# zoom the camera fits at most spread.x across, so the runner is stopped at x = 5.
	var runner := Fakes.spawn_player(world, 0, &"warrior", Vector3(0, 0, 0))
	var mate := Fakes.spawn_player(world, 1, &"warrior", Vector3(5.0 - spread.x, 0, 0))
	rig.snap()
	var rect := rig.get_walk_rect(runner)
	check_near(rect.end.x, 5.0, 0.001, "east limit = teammate + max spread")
	var input := runner.slot.input as ScriptedInput
	input.move = Vector2(1, 0)
	Fakes.step(runner, 2.0)
	check(runner.global_position.x <= 5.0 + 0.001, "stopped at the screen edge (x %.2f)" % runner.global_position.x)
	check(runner.global_position.x > 4.0, "walked up to it")
	check_near(runner.velocity.x, 0.0, 0.001, "no velocity into the screen edge")
	# Pushing diagonally slides along the edge.
	input.move = Vector2(1, 1).normalized()
	var z0 := runner.global_position.z
	Fakes.step(runner, 0.5)
	check(runner.global_position.x <= 5.0 + 0.001, "still on screen")
	check(runner.global_position.z - z0 > runner.stats.move_speed() * 0.707 * 0.5 * 0.7, "slides along the screen edge")
	# Walking back towards the team is free.
	input.move = Vector2(-1, 0)
	var x0 := runner.global_position.x
	Fakes.step(runner, 0.5)
	check(runner.global_position.x < x0 - 1.0, "walks back")
	# A ghost (the camera does not follow it) is kept inside the current view.
	mate.global_position = Vector3(0, 0, 0)
	rig.snap()
	runner.global_position = Vector3(0, 0, 0)
	runner.take_damage(999.0)
	var view := rig.get_walk_rect(runner)
	check(view.end.x < Arena.SIZE.x * 0.5, "the view is narrower than the arena")
	mate.global_position = Vector3(-6.0, 0, 0)  # out of the revive circle
	input.move = Vector2(1, 0)
	Fakes.step(runner, 20.0, 0.1)
	check(runner.global_position.x <= view.end.x + 0.001, "ghost stays on screen (x %.2f, edge %.2f)" % [runner.global_position.x, view.end.x])
	check(runner.global_position.x > view.end.x - 0.5, "ghost reached the edge")
	Arena.current = previous
	arena.free()


func test_no_screen_wall_without_a_camera() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	Fakes.spawn_player(world, 1, &"warrior", Vector3(-60.0, 0, 0))
	var input := p.slot.input as ScriptedInput
	input.move = Vector2(1, 0)
	Fakes.step(p, 10.0, 0.1)
	check(p.global_position.x > 30.0, "free movement without Arena.current / camera")
