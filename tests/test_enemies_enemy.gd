extends TestCase
## Enemy: creation / scaling, contact damage, death & loot, stun, knockback, behaviours.

const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 4242)
	world = EFakes.make_world(tree)


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null


func test_create_builds_body_and_scales_hp_with_wave() -> void:
	var data := Db.get_enemy(&"skeleton_grunt")
	var e1 := Enemy.create(data, 1)
	check(e1.is_in_group(&"enemies"), "in enemies group")
	check_eq(e1.collision_layer, 4, "layer 3 (enemies)")
	check_eq(e1.collision_mask, 5, "mask world | enemies")
	check_eq(e1.max_hp, data.hp_at_wave(1), "wave 1 hp")
	check_eq(e1.hp, e1.max_hp, "starts at full hp")
	check_eq(e1.radius, data.radius, "radius from data")
	check(e1.model != null and e1.model.get_parent() == e1, "has an EnemyModel child")
	var shape := e1.get_node_or_null(^"Shape") as CollisionShape3D
	check(shape != null and shape.shape is SphereShape3D, "sphere collision (circle on the ground plane)")
	if shape != null and shape.shape is SphereShape3D:
		check_eq((shape.shape as SphereShape3D).radius, data.radius, "collision radius")
	check_eq(e1.motion_mode, CharacterBody3D.MOTION_MODE_FLOATING, "floating (top-down) motion")
	check_near(e1.move_speed, data.move_speed, data.move_speed * Enemy.MOVE_SPEED_JITTER + 0.0001, "speed jitter")
	e1.free()

	var e5 := Enemy.create(data, 5)
	check_eq(e5.max_hp, 4.0 + 2.5 * 4.0, "wave 5 hp = 4 + 2.5 * 4")
	check_eq(e5.contact_damage, data.contact_damage_at_wave(5), "contact damage scales")
	e5.free()


func test_hp_scales_with_coop() -> void:
	var data := Db.get_enemy(&"skeleton_grunt")
	RunState.start_run(3, 1)
	var e := Enemy.create(data, 5)
	check_eq(e.max_hp, data.hp_at_wave(5) * 1.4, "3 players: +40% hp")
	e.free()
	RunState.start_run(4, 1)
	e = Enemy.create(data, 1)
	check_eq(e.max_hp, data.hp_at_wave(1) * 1.6, "4 players: +60% hp")
	e.free()


func test_contact_damage_respects_cooldown() -> void:
	var player := EFakes.spawn_player(world, Vector3.ZERO)
	var data := EFakes.enemy_data()
	data.move_speed = 0.0
	var e := EFakes.spawn_enemy(world, data, Vector3(0.6, 0.0, 0.0), 3)
	e._physics_process(DT)
	check_eq(player.fake_hits.size(), 1, "first touch hits at once")
	if player.fake_hits.size() == 1:
		check_eq(player.fake_hits[0], data.contact_damage_at_wave(3), "wave-scaled contact damage")
		check_eq(player.fake_kinds[0], CombatMath.KIND_MELEE, "melee kind")
		check(player.fake_sources[0] == e, "enemy is the source")
	EFakes.step(e, 0.9)
	check_eq(player.fake_hits.size(), 1, "no second hit within the cooldown")
	EFakes.step(e, 0.15)
	check_eq(player.fake_hits.size(), 2, "hits again once the cooldown is over")


func test_no_contact_damage_out_of_reach_or_downed() -> void:
	var player := EFakes.spawn_player(world, Vector3.ZERO)
	var data := EFakes.enemy_data()
	data.move_speed = 0.0
	var far := EFakes.spawn_enemy(world, data, Vector3(0.95, 0.0, 0.0))
	far._physics_process(DT)
	check_eq(player.fake_hits.size(), 0, "0.95 m > 0.45 + 0.45 reach")
	player.downed = true
	var near := EFakes.spawn_enemy(world, data, Vector3(0.3, 0.0, 0.0))
	EFakes.step(near, 0.5)
	check_eq(player.fake_hits.size(), 0, "downed players are ignored")


func test_chases_nearest_living_player() -> void:
	EFakes.spawn_player(world, Vector3(-6.0, 0.0, 0.0))
	var b := EFakes.spawn_player(world, Vector3(6.0, 0.0, 0.0))
	var e := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3(1.0, 0.0, 0.0))
	EFakes.step(e, 0.5)
	check(e.global_position.x > 1.5, "walks towards the nearer player on +X")
	check_near(e.global_position.y, 0.0, 0.001, "stays on the ground plane")
	check(e.velocity.x > 0.0, "velocity is exposed (projectile lead)")
	# The near player goes down: the enemy turns to the other one.
	b.downed = true
	var x_before := e.global_position.x
	EFakes.step(e, 1.0)
	check(e.global_position.x < x_before - 0.5, "turns to the living player on -X")


func test_death_drops_loot_and_credits_killer() -> void:
	var player := EFakes.spawn_player(world, Vector3(8.0, 0.0, 0.0), 2)
	var data := EFakes.enemy_data()
	var e := EFakes.spawn_enemy(world, data, Vector3(1.0, 0.0, 1.0))
	var deaths: Array[int] = []
	e.died.connect(func(_enemy: Enemy, killer: int) -> void: deaths.append(killer))
	var kills_before := RunState.kills
	e.take_damage(4.0, false, player)
	check(not e.is_dead(), "still alive after 4 of 10")
	check_eq(e.hp, 6.0, "hp reduced")
	e.take_damage(100.0, true, player)
	check(e.is_dead(), "dead")
	check_eq(deaths.size(), 1, "died emitted once")
	if deaths.size() == 1:
		check_eq(deaths[0], 2, "killer index = attacker slot")
	check_eq(RunState.kills, kills_before + 1, "kill recorded")
	check_eq(RunState.kills_by_player.get(2, 0), 1, "kill credited to P3")
	check(not e.is_in_group(&"enemies"), "left the enemies group")
	check(e.is_queued_for_deletion(), "queued for deletion")
	var pickups := EFakes.live_children_of_type(world, Pickup)
	check_eq(pickups.size(), 1, "one pickup dropped")
	if pickups.size() == 1:
		var p := pickups[0] as Pickup
		check_eq(p.gold, data.gold, "pickup gold")
		check_eq(p.xp, data.xp, "pickup xp")
		check(p.is_in_group(&"pickups"), "pickup in group")
		check(EFakes.flat_distance(p.global_position, Vector3(1.0, 0.0, 1.0)) <= Enemy.LOOT_SCATTER + 0.001,
				"dropped at the death position")
	# Hitting the corpse again changes nothing.
	e.take_damage(5.0, false, player)
	check_eq(deaths.size(), 1, "no second death")
	check_eq(RunState.kills, kills_before + 1, "no second kill")
	check_eq(EFakes.live_children_of_type(world, Pickup).size(), 1, "no second drop")


func test_death_without_player_attacker() -> void:
	var e := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3.ZERO)
	var deaths: Array[int] = []
	e.died.connect(func(_enemy: Enemy, killer: int) -> void: deaths.append(killer))
	e.take_damage(1000.0)
	check_eq(deaths.size(), 1, "died")
	if deaths.size() == 1:
		check_eq(deaths[0], -1, "no killer")
	check_eq(RunState.kills, 1, "kill still counted")
	check(RunState.kills_by_player.is_empty(), "nobody credited")


func test_despawn_has_no_loot() -> void:
	var e := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3.ZERO)
	var deaths: Array[int] = []
	e.died.connect(func(_enemy: Enemy, killer: int) -> void: deaths.append(killer))
	e.despawn()
	check(e.is_queued_for_deletion(), "removed")
	check(not e.is_in_group(&"enemies"), "left the group at once")
	check(e.is_dead(), "counts as dead for targeting")
	check_eq(deaths.size(), 0, "no died signal")
	check_eq(RunState.kills, 0, "no kill")
	check_eq(EFakes.live_children_of_type(world, Pickup).size(), 0, "no loot")


func test_stun_stops_movement_and_attacks() -> void:
	var player := EFakes.spawn_player(world, Vector3(5.0, 0.0, 0.0))
	var e := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3.ZERO)
	e.apply_stun(0.5)
	check(e.is_stunned(), "stunned")
	EFakes.step(e, 0.45)
	check_near(e.global_position.x, 0.0, 0.0001, "does not move while stunned")
	EFakes.step(e, 0.3)
	check(not e.is_stunned(), "stun wore off")
	check(e.global_position.x > 0.05, "moves again afterwards")

	# Stunned enemies deal no contact damage.
	var data := EFakes.enemy_data()
	data.move_speed = 0.0
	var toucher := EFakes.spawn_enemy(world, data, Vector3(5.3, 0.0, 0.0))
	toucher.apply_stun(1.0)
	EFakes.step(toucher, 0.5)
	check_eq(player.fake_hits.size(), 0, "no contact damage while stunned")
	EFakes.step(toucher, 0.6)
	check_eq(player.fake_hits.size(), 1, "contact damage after the stun")


func test_stun_resist_shortens_stun() -> void:
	var data := EFakes.enemy_data()
	data.stun_resist = 0.5
	var e := EFakes.spawn_enemy(world, data, Vector3.ZERO)
	e.apply_stun(1.0)
	check_eq(e.stun_left, 0.5, "halved by 50% resist")
	data.stun_resist = 1.0
	var immune := EFakes.spawn_enemy(world, data, Vector3(2, 0, 0))
	immune.apply_stun(1.0)
	check(not immune.is_stunned(), "100% resist is immune")


func test_knockback_pushes_and_decays() -> void:
	var data := EFakes.enemy_data()
	var e := EFakes.spawn_enemy(world, data, Vector3.ZERO)
	e.apply_stun(2.0)  # isolate the knockback from walking
	e.take_damage(1.0, false, null, Vector3(2.0, 0.0, 0.0))
	EFakes.step(e, 1.0)
	var pushed := e.global_position.x
	check(pushed > 0.3 and pushed < 0.8, "pushed ~0.5 m along +X (got %s)" % pushed)
	check(e.knockback_velocity.length() < 0.1, "knockback decayed")
	EFakes.step(e, 0.5)
	check_near(e.global_position.x, pushed, 0.01, "stops after the push")

	data.knockback_resist = 1.0
	var heavy := EFakes.spawn_enemy(world, data, Vector3(0.0, 0.0, 5.0))
	heavy.apply_stun(2.0)
	heavy.take_damage(1.0, false, null, Vector3(4.0, 0.0, 0.0))
	EFakes.step(heavy, 0.5)
	check_near(heavy.global_position.x, 0.0, 0.0001, "full knockback resist")


func test_lunge_state_machine_timing() -> void:
	var data := EFakes.enemy_data(EnemyData.Behavior.LUNGE)
	data.lunge_windup = 0.5
	data.lunge_speed = 10.0
	data.attack_cooldown = 2.0
	data.contact_damage = 0.0
	var player := EFakes.spawn_player(world, Vector3(0.0, 0.0, -3.0))
	var e := EFakes.spawn_enemy(world, data, Vector3.ZERO)
	e._physics_process(DT)
	check_eq(e.ai_state, Enemy.AiState.WINDUP, "within 3.5 m: winds up")
	var start := e.global_position
	# Record the frames spent in each state until the lunge is over.
	var windup_frames := 1
	var leap_frames := 0
	var moved_in_windup := 0.0
	var leap_start := start
	for _i in 120:
		var before := e.ai_state
		var pos_before := e.global_position
		e._physics_process(DT)
		if before == Enemy.AiState.WINDUP:
			moved_in_windup = maxf(moved_in_windup, EFakes.flat_distance(pos_before, start))
		if e.ai_state == Enemy.AiState.WINDUP:
			windup_frames += 1
		elif e.ai_state == Enemy.AiState.LEAP:
			if leap_frames == 0:
				leap_start = pos_before
			leap_frames += 1
		elif before == Enemy.AiState.LEAP:
			break  # this frame already walks again
	check(absi(windup_frames - roundi(data.lunge_windup / DT)) <= 1,
			"wind-up lasts lunge_windup (%d frames)" % windup_frames)
	check(absi(leap_frames - roundi(Enemy.LUNGE_DURATION / DT)) <= 1,
			"leap lasts LUNGE_DURATION (%d frames)" % leap_frames)
	check(moved_in_windup < 0.01, "stands still during the wind-up")
	check_eq(e.ai_state, Enemy.AiState.MOVE, "back to chasing after the leap")
	var leapt := EFakes.flat_distance(e.global_position, leap_start)
	check_near(leapt, data.lunge_speed * Enemy.LUNGE_DURATION, 0.25, "leap distance")
	check(e.global_position.z < -2.5, "leapt towards the player (-Z)")
	check_near(e.attack_cooldown_left, data.attack_cooldown, 0.001, "cooldown started")
	# Within the cooldown: no new wind-up even though the player is close.
	player.global_position = e.global_position + Vector3(0.0, 0.0, -2.0)
	EFakes.step(e, 1.5)
	check_eq(e.ai_state, Enemy.AiState.MOVE, "no lunge during the cooldown")
	player.global_position = e.global_position + Vector3(0.0, 0.0, -3.0)
	EFakes.step(e, 0.6)
	check_eq(e.ai_state, Enemy.AiState.WINDUP, "winds up again after the cooldown")


func test_lunge_far_away_just_chases() -> void:
	var data := EFakes.enemy_data(EnemyData.Behavior.LUNGE)
	EFakes.spawn_player(world, Vector3(0.0, 0.0, -10.0))
	var e := EFakes.spawn_enemy(world, data, Vector3.ZERO)
	EFakes.step(e, 0.5)
	check_eq(e.ai_state, Enemy.AiState.MOVE, "too far for a lunge")
	check(e.global_position.z < -0.3, "walks towards the player")


func test_stun_interrupts_lunge() -> void:
	var data := EFakes.enemy_data(EnemyData.Behavior.LUNGE)
	data.attack_cooldown = 2.0
	EFakes.spawn_player(world, Vector3(0.0, 0.0, -3.0))
	var e := EFakes.spawn_enemy(world, data, Vector3.ZERO)
	e._physics_process(DT)
	check_eq(e.ai_state, Enemy.AiState.WINDUP, "winding up")
	e.apply_stun(0.3)
	check_eq(e.ai_state, Enemy.AiState.MOVE, "wind-up cancelled")
	check(e.attack_cooldown_left >= 1.0 - 0.001, "lunge delayed")


func test_ranged_keeps_distance_and_throws() -> void:
	var data := EFakes.enemy_data(EnemyData.Behavior.RANGED)
	data.preferred_distance = 7.0
	data.attack_cooldown = 1.0
	data.projectile_damage = 4.0
	data.damage_per_wave = 0.5
	var player := EFakes.spawn_player(world, Vector3.ZERO)
	var e := EFakes.spawn_enemy(world, data, Vector3(3.0, 0.0, 0.0), 3)
	EFakes.step(e, 0.5)
	check(e.global_position.x > 3.3, "backs off when too close")
	# Let it throw: cooldown (<= 1 s) + wind-up.
	EFakes.step(e, 1.5)
	var axes: Array[Projectile] = []
	for child in EFakes.arena_of(world).entities.get_children():
		var proj := child as Projectile
		if proj != null:
			axes.append(proj)
	check(axes.size() >= 1, "threw an axe")
	if not axes.is_empty():
		var axe := axes[0]
		check_eq(axe.team, Projectile.TEAM_ENEMIES, "enemy team")
		check_eq(axe.damage, data.projectile_damage_at_wave(3), "wave-scaled projectile damage")
		check(axe.attacker == e, "attacker is the enemy")
		check(axe.direction.x < -0.9, "aimed at the player (-X)")
	check_eq(player.fake_hits.size(), 0, "never touched the player")


func test_wanders_without_living_players() -> void:
	var p := EFakes.spawn_player(world, Vector3(3.0, 0.0, 0.0))
	p.downed = true
	var data := EFakes.enemy_data(EnemyData.Behavior.LUNGE)
	var e := EFakes.spawn_enemy(world, data, Vector3.ZERO)
	EFakes.step(e, 3.0)
	check_eq(e.ai_state, Enemy.AiState.MOVE, "no lunge at a downed player")
	check(EFakes.flat_distance(e.global_position, Vector3.ZERO) < 3.0 * e.move_speed * Enemy.WANDER_SPEED_RATIO + 0.01,
			"only wanders slowly")
	check_eq(p.fake_hits.size(), 0, "no damage")


func test_player_cache_follows_group_changes() -> void:
	var players := Enemy.cached_players(tree)
	check_eq(players.size(), 0, "no players yet")
	var p := EFakes.spawn_player(world, Vector3.ZERO)
	players = Enemy.cached_players(tree)
	check_eq(players.size(), 1, "new player seen in the same frame (count changed)")
	p.get_parent().remove_child(p)
	players = Enemy.cached_players(tree)
	check_eq(players.size(), 0, "removed player dropped")
	p.free()
	check_eq(Enemy.living_player_positions(null).size(), 0, "null tree is safe")
