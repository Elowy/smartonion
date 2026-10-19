extends TestCase
## Enemy: creation / scaling, contact damage, death & loot, stun, knockback, behaviours.

const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0
## RunState.coop_damage_mult() for 1..4 players (GDD 9).
const COOP_DAMAGE: Array[float] = [0.45, 0.6, 0.85, 1.15]

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
	check_eq(e1.collision_mask, 1, "mask world only (crowd separation: EnemyGrid)")
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
	check_near(e5.max_hp, 4.0 * (1.0 + 0.12 * 4.0) * pow(1.22, 4.0), 0.0001,
			"wave 5 hp = 4 * (1 + 12% * 4) * 1.22^4")
	check_near(e5.contact_damage, 1.0 * (1.0 + 0.15 * 4.0) * pow(1.1, 4.0) * COOP_DAMAGE[0], 0.0001,
			"wave 5 contact damage = 1 * (1 + 15% * 4) * 1.1^4 * the solo damage factor")
	e5.free()


func test_wave_scaling_follows_gdd() -> void:
	# GDD 9: additive HP / damage growth per wave after the first (the fake data uses +12% /
	# +8% and no compounding, see EFakes.enemy_data); on top of it a compounding factor.
	var data := EFakes.enemy_data(EnemyData.Behavior.RANGED)
	data.max_hp = 10.0
	data.contact_damage = 3.0
	data.projectile_damage = 4.0
	var defaults := EnemyData.new()
	check_eq(defaults.hp_growth, 0.12, "default hp growth")
	check_eq(defaults.damage_growth, 0.15, "default damage growth")
	check_eq(defaults.hp_compound, 0.22, "default hp compounding")
	check_eq(defaults.damage_compound, 0.1, "default damage compounding")
	check_eq(data.hp_at_wave(1), 10.0, "wave 1 = base hp")
	check_eq(data.hp_at_wave(0), 10.0, "wave 0 / negative waves clamp to the base")
	check_eq(data.hp_at_wave(11), 10.0 * 2.2, "wave 11: +120%")
	check_eq(data.hp_at_wave(25), 10.0 * (1.0 + 0.12 * 24.0), "wave 25: x3.88")
	check_eq(data.contact_damage_at_wave(1), 3.0, "wave 1 = base contact damage")
	check_eq(data.contact_damage_at_wave(11), 3.0 * 1.8, "wave 11 contact: +80%")
	check_eq(data.projectile_damage_at_wave(1), 4.0, "wave 1 = base projectile damage")
	check_eq(data.projectile_damage_at_wave(6), 4.0 * 1.4, "wave 6 projectile: +40%")
	# The compounding factor multiplies the additive growth: (1 + g * n) * (1 + c)^n.
	data.hp_compound = 0.25
	data.damage_compound = 0.5
	check_eq(data.hp_at_wave(1), 10.0, "wave 1 stays the base with compounding")
	check_near(data.hp_at_wave(3), 10.0 * 1.24 * 1.5625, 0.0001, "wave 3: (1 + 24%) * 1.25^2")
	check_near(data.contact_damage_at_wave(3), 3.0 * 1.16 * 2.25, 0.0001, "wave 3 contact: (1 + 16%) * 1.5^2")
	check_near(data.projectile_damage_at_wave(3), 4.0 * 1.16 * 2.25, 0.0001, "wave 3 projectile")
	check(data.hp_at_wave(25) > data.hp_at_wave(24) * 1.25, "compounding outgrows the additive part")
	# Data driven: a difficulty can override the growth rates.
	data.hp_growth = 0.2
	data.hp_compound = 0.0
	data.damage_growth = 0.0
	data.damage_compound = 0.0
	check_eq(data.hp_at_wave(6), 20.0, "custom hp growth")
	check_eq(data.contact_damage_at_wave(6), 3.0, "no damage growth")
	# Every shipped enemy uses the defaults.
	for id in Db.enemies:
		var d: EnemyData = Db.enemies[id]
		check_eq(d.hp_growth, defaults.hp_growth, "%s hp growth" % id)
		check_eq(d.damage_growth, defaults.damage_growth, "%s damage growth" % id)
		check_eq(d.hp_compound, defaults.hp_compound, "%s hp compounding" % id)
		check_eq(d.damage_compound, defaults.damage_compound, "%s damage compounding" % id)


func test_enemy_stats_at_wave_include_coop_scaling() -> void:
	var data := Db.get_enemy(&"troll_axethrower")
	RunState.start_run(4, 1)
	var e := Enemy.create(data, 6)
	check_near(e.max_hp, data.max_hp * 1.6 * pow(1.22, 5.0) * 1.6, 0.0001,
			"hp: base * (1 + 12% * 5) * 1.22^5 * coop 1.6")
	check_near(e.contact_damage, data.contact_damage * 1.75 * pow(1.1, 5.0) * COOP_DAMAGE[3], 0.0001,
			"contact damage: (1 + 15% * 5) * 1.1^5 * the 4-player damage factor")
	check_near(e.projectile_damage, data.projectile_damage * 1.75 * pow(1.1, 5.0) * COOP_DAMAGE[3], 0.0001,
			"projectile damage: the same co-op factor")
	e.free()


func test_coop_damage_mult_by_party_size() -> void:
	# GDD 9: smaller parties take softer hits (alone, the first down ends the run).
	for n in range(1, 5):
		RunState.start_run(n, 1)
		check_near(RunState.coop_damage_mult(), COOP_DAMAGE[n - 1], 0.0001, "%d player(s)" % n)
	for n in range(1, 4):
		check(COOP_DAMAGE[n - 1] < COOP_DAMAGE[n], "%d players hit softer than %d" % [n, n + 1])
	check(COOP_DAMAGE[0] < 1.0, "a lone hero always takes softer hits than the EnemyData curve")


func test_enemy_damage_scales_with_party_size() -> void:
	var data := Db.get_enemy(&"troll_axethrower")
	for n in range(1, 5):
		RunState.start_run(n, 1)
		var e := Enemy.create(data, 10)
		check_near(e.contact_damage, data.contact_damage_at_wave(10) * COOP_DAMAGE[n - 1], 0.0001,
				"%d player(s): contact damage x the party factor" % n)
		check_near(e.projectile_damage, data.projectile_damage_at_wave(10) * COOP_DAMAGE[n - 1], 0.0001,
				"%d player(s): projectile damage x the party factor" % n)
		check_near(e.max_hp, data.hp_at_wave(10) * (1.0 + 0.2 * (n - 1)), 0.0001,
				"%d player(s): hp keeps its own co-op factor" % n)
		e.free()


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
		check_near(player.fake_hits[0], data.contact_damage_at_wave(3) * RunState.coop_damage_mult(), 0.0001,
				"wave- and party-scaled contact damage")
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


func test_stealthed_players_are_ignored() -> void:
	var hidden := EFakes.spawn_player(world, Vector3.ZERO)
	var other := EFakes.spawn_player(world, Vector3(-8.0, 0.0, 0.0))
	hidden.stealth_left = 2.0
	var data := EFakes.enemy_data()
	var e := EFakes.spawn_enemy(world, data, Vector3(0.6, 0.0, 0.0))
	EFakes.step(e, 0.5)
	check_eq(hidden.fake_hits.size(), 0, "no contact damage while stealthed")
	check(e.global_position.x < 0.6, "chases the visible player instead")
	other.downed = true
	hidden.stealth_left = 0.0
	LivingPlayers.mark_dirty()
	EFakes.step(e, 0.5)
	check(hidden.fake_hits.size() >= 1, "found again once the stealth is over")


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
	data.damage_growth = 0.5
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
		check_near(axe.damage, data.projectile_damage_at_wave(3) * RunState.coop_damage_mult(), 0.0001,
				"wave- and party-scaled projectile damage")
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


func test_freed_players_are_handled() -> void:
	# A script error (e.g. a freed instance passed to a typed parameter) aborts this method;
	# the sentinel failure then stays in the list.
	failures.append("aborted by a script error")
	var a := EFakes.spawn_player(world, Vector3(2.0, 0.0, 0.0))
	var b := EFakes.spawn_player(world, Vector3(-2.0, 0.0, 0.0))
	check_eq(Enemy.cached_players(tree).size(), 2, "both cached")
	# Free one and add another in the same frame: the group size stays the same.
	a.free()
	var c := FakeLookup.new()
	c.add_to_group(&"players")
	EFakes.arena_of(world).entities.add_child(c)
	c.global_position = Vector3(0.0, 0.0, 4.0)
	check(not Enemy.is_living_player(a), "freed player is not alive")
	check(not Enemy.is_living_player(null), "null is not alive")
	check(Enemy.is_living_player(b), "living player")
	var cached := Enemy.cached_players(tree)
	check_eq(cached.size(), 2, "rebuilt after a cached player was freed")
	check(c in cached, "new player seen")
	check_eq(Enemy.living_player_positions(tree).size(), 2, "living positions")
	# Enemies keep working with a freed target.
	var e := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3(-1.0, 0.0, 0.0))
	EFakes.step(e, 0.1)
	b.free()
	EFakes.step(e, 0.1)
	check(e.global_position.z > 0.0, "turned to the remaining player")
	failures.erase("aborted by a script error")


## Another fake player type (as a second Player subclass instance in the group).
class FakeLookup extends EFakes.FakePlayer:
	pass


func test_fear_runs_away_without_attacking() -> void:
	var player := EFakes.spawn_player(world, Vector3.ZERO)
	var e := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3(0.6, 0.0, 0.0))
	e.apply_fear(1.0, Vector3.ZERO)
	check(e.is_feared(), "feared")
	EFakes.step(e, 0.5)
	check_eq(player.fake_hits.size(), 0, "no contact damage while feared")
	check(e.global_position.x > 0.9, "runs away from the source")
	EFakes.step(e, 0.6)
	check(not e.is_feared(), "wears off")


func test_taunt_chases_the_taunter() -> void:
	EFakes.spawn_player(world, Vector3(-6.0, 0.0, 0.0))
	var decoy := Node3D.new()
	EFakes.arena_of(world).entities.add_child(decoy)
	decoy.global_position = Vector3(6.0, 0.0, 0.0)
	var e := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3.ZERO)
	e.apply_taunt(decoy, 2.0)
	EFakes.step(e, 0.5)
	check(e.global_position.x > 0.5, "walks to the taunter, not the player")
	decoy.free()
	check(not e.is_taunted(), "a freed taunter ends the taunt")
