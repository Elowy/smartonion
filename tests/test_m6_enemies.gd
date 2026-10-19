extends TestCase
## M6a ENEMIES (GDD 8): the data of the Plague Ghoul / Cultist Acolyte / Flesh Golem, the ghoul's
## poison puddle, the Acolyte's support AI (distance keeping, channelled heal / shield,
## interruptions, priority target) and the golem's hook (telegraph line, first hero in it,
## cooldown, interruptions), plus the new EnemyModel styles. The real-Player / bot parts
## (take_hook, pull_toward, BotInput) are in test_m6_enemies_player.gd.

const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 4242)
	world = EFakes.make_world(tree)


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null


func _entities() -> Node3D:
	return EFakes.arena_of(world).entities


func _spawn(id: StringName, pos: Vector3, wave: int = 1) -> Enemy:
	return EFakes.spawn_enemy(world, Db.get_enemy(id), pos, wave)


## A plain enemy that never moves (speed 0) with [param hp_max] HP.
func _dummy(pos: Vector3, hp_max: float = 10.0) -> Enemy:
	var d := EFakes.enemy_data()
	d.max_hp = hp_max
	d.move_speed = 0.0
	var e := EFakes.spawn_enemy(world, d, pos)
	e.max_hp = hp_max
	e.hp = hp_max
	return e


## An Acolyte at [param pos] with the first channel ready, and a hero at [param hero_pos].
func _acolyte(pos: Vector3, hero_pos: Vector3) -> Enemy:
	EFakes.spawn_player(world, hero_pos)
	var a := _spawn(&"cultist_acolyte", pos, 9)
	a.attack_cooldown_left = 0.0
	return a


func _step(e: Node, seconds: float) -> void:
	EFakes.step(e, seconds)


func _players() -> Array[Player]:
	return Enemy.cached_players(tree)


func _hero(i: int = 0) -> EFakes.FakePlayer:
	Enemy.invalidate_player_cache()
	return _players()[i] as EFakes.FakePlayer


# --- Data ----------------------------------------------------------------------------------------

func test_the_three_new_enemies_follow_the_design() -> void:
	check_eq(Db.enemies.size(), 8, "five old + three new enemy types")
	var g := Db.get_enemy(&"plague_ghoul")
	check(g != null, "plague_ghoul loads")
	if g != null:
		check_eq(g.behavior, EnemyData.Behavior.CHASE, "ghoul chases")
		check_eq(g.first_wave, 7, "from wave 7")
		check_eq(g.max_hp, 7.0, "hp")
		check_eq(g.contact_damage, 2.0, "contact")
		check_eq(g.move_speed, 2.1, "speed")
		check_eq(g.radius, 0.5, "radius")
		check_eq(g.spawn_weight, 0.6, "weight")
		check_eq(g.group_min, 2, "group min")
		check_eq(g.group_max, 3, "group max")
		check_eq(g.gold, 1, "gold")
		check_eq(g.xp, 2, "xp")
		check_eq(g.death_effect, &"poison_puddle", "death effect")
		check_eq(g.death_radius, 1.6, "puddle radius")
		check_eq(g.death_duration, 3.0, "puddle time")
		check_eq(g.death_tick_interval, 0.5, "2 ticks a second")
		check_eq(g.death_damage_ratio, 0.5, "half the contact damage per tick")
		check_eq(g.model_style, &"ghoul", "style")
	var a := Db.get_enemy(&"cultist_acolyte")
	check(a != null, "cultist_acolyte loads")
	if a != null:
		check_eq(a.behavior, EnemyData.Behavior.SUPPORT, "support")
		check_eq(a.first_wave, 9, "from wave 9")
		check_eq(a.max_hp, 6.0, "hp")
		check_eq(a.contact_damage, 1.0, "contact")
		check_eq(a.move_speed, 2.3, "speed")
		check_eq(a.spawn_weight, 0.35, "weight")
		check_eq(a.group_min, 1, "group min")
		check_eq(a.group_max, 1, "group max")
		check_eq(a.gold, 2, "gold")
		check_eq(a.xp, 3, "xp")
		check_eq(a.attack_cooldown, 4.0, "a channel every 4 s")
		check_eq(a.support_channel, 0.6, "0.6 s channel")
		check_eq(a.support_distance_min, 6.0, "keeps 6 m ...")
		check_eq(a.support_distance_max, 9.0, "... to 9 m from the hero")
		check_eq(a.support_range, 7.0, "reach 7 m")
		check_eq(a.support_heal_pct, 0.25, "heals 25%")
		check_eq(a.support_shield_pct, 0.2, "shields 20%")
		check(a.priority_target, "primary target")
		check_eq(a.model_style, &"cultist", "style")
	var f := Db.get_enemy(&"flesh_golem")
	check(f != null, "flesh_golem loads")
	if f != null:
		check_eq(f.behavior, EnemyData.Behavior.BRUTE, "brute")
		check_eq(f.first_wave, 12, "from wave 12")
		check_eq(f.max_hp, 40.0, "hp")
		check_eq(f.contact_damage, 2.5, "contact")
		check_eq(f.move_speed, 1.5, "speed")
		check_eq(f.radius, 0.9, "radius")
		check_eq(f.model_scale, 1.6, "scale")
		check_eq(f.knockback_resist, 0.8, "knockback resist")
		check_eq(f.stun_resist, 0.5, "stun resist")
		check_eq(f.spawn_weight, 0.25, "weight")
		check_eq(f.gold, 4, "gold")
		check_eq(f.xp, 5, "xp")
		check_eq(f.attack_cooldown, 6.0, "a hook every 6 s")
		check_eq(f.hook_range_min, 4.0, "hooks from 4 m ...")
		check_eq(f.hook_range_max, 9.0, "... to 9 m")
		check_eq(f.hook_telegraph, 0.8, "0.8 s line")
		check_eq(f.hook_pull, 3.0, "pulls 3 m")
		check_eq(f.hook_damage_ratio, 1.0, "1 x contact damage")
		check_eq(f.model_style, &"golem", "style")
	check(not Db.get_enemy(&"skeleton_grunt").priority_target, "only the Acolyte is a primary target")
	check_eq(Db.get_enemy(&"skeleton_grunt").death_effect, &"", "no other enemy leaves a puddle")


func test_marsh_gurgler_groups_of_four_to_six_and_greedy_five_percent() -> void:
	var gurgler := Db.get_enemy(&"marsh_gurgler")
	check_eq(gurgler.group_min, 4, "gurgler group min (GDD 8)")
	check_eq(gurgler.group_max, 6, "gurgler group max (GDD 8)")
	var seen := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for _i in 200:
		seen[WaveDirector.roll_group_size(gurgler, rng)] = true
	check(seen.has(4) and seen.has(6) and not seen.has(3) and not seen.has(7), "4 to 6, both ends reachable")
	var greedy := Db.get_enchant(&"greedy")
	check_eq(greedy.chance, 5.0, "Greedy: 5% (GDD 5.8)")
	check("5%" in greedy.description, "the tooltip says 5%")
	check_eq(greedy.params["amount"], 1.0, "Greedy: +1 gold (GDD 5.8)")
	check("find 1 extra gold" in EnchantRoll.new(greedy, 0).description(), "the rank I tooltip says 1 gold: %s" % EnchantRoll.new(greedy, 0).description())


func test_the_director_picks_the_new_types_from_their_first_wave() -> void:
	var ids6: Array[StringName] = []
	for d in WaveDirector.eligible_enemies(6):
		ids6.append(d.id)
	check(not ids6.has(&"plague_ghoul") and not ids6.has(&"cultist_acolyte") and not ids6.has(&"flesh_golem"),
			"none of them before wave 7")
	var ids: Dictionary[int, Array] = {}
	for w in [7, 8, 9, 11, 12]:
		var list: Array[StringName] = []
		for d in WaveDirector.eligible_enemies(w):
			list.append(d.id)
		ids[w] = list
	check(ids[7].has(&"plague_ghoul") and not ids[7].has(&"cultist_acolyte"), "wave 7: the ghoul")
	check(ids[8].has(&"plague_ghoul") and not ids[8].has(&"cultist_acolyte"), "wave 8: still no Acolyte")
	check(ids[9].has(&"cultist_acolyte") and not ids[9].has(&"flesh_golem"), "wave 9: the Acolyte")
	check(ids[11].has(&"cultist_acolyte") and not ids[11].has(&"flesh_golem"), "wave 11: still no golem")
	check(ids[12].has(&"flesh_golem"), "wave 12: the golem")
	var bosses := WaveDirector.eligible_enemies(25)
	for d in bosses:
		check(not d.is_boss, "no boss in the pool")


# --- Plague Ghoul: death puddle ------------------------------------------------------------------

func test_ghoul_death_leaves_a_poison_puddle_with_data_numbers() -> void:
	var ghoul := _spawn(&"plague_ghoul", Vector3(2.0, 0.0, 3.0), 7)
	var data := Db.get_enemy(&"plague_ghoul")
	check(PoisonPuddle.alive(tree).is_empty(), "nothing before the death")
	ghoul.take_damage(1000.0)
	var list := PoisonPuddle.alive(tree)
	check_eq(list.size(), 1, "one puddle")
	if list.is_empty():
		return
	var puddle := list[0]
	check_near(puddle.global_position.x, 2.0, 0.001, "where it fell x")
	check_near(puddle.global_position.z, 3.0, 0.001, "where it fell z")
	check_eq(puddle.radius, 1.6, "radius 1.6 m")
	check_eq(puddle.duration, 3.0, "stays 3 s")
	check_eq(puddle.tick_interval, 0.5, "2 ticks a second")
	var expected := data.contact_damage_at_wave(7) * RunState.coop_damage_mult() * 0.5
	check_near(puddle.damage_per_tick, expected, 0.0001, "half the ghoul's contact damage at wave 7 (party scaled)")
	check(puddle.get_parent() == _entities(), "under the arena's entities")


func test_puddle_damage_follows_the_ghouls_wave_party_and_damage_mult() -> void:
	RunState.start_run(4, 11)
	var data := Db.get_enemy(&"plague_ghoul")
	var low := _spawn(&"plague_ghoul", Vector3(-8.0, 0.0, 0.0), 7)
	var high := _spawn(&"plague_ghoul", Vector3(8.0, 0.0, 0.0), 14)
	high.damage_mult = 1.5
	low.take_damage(1000.0)
	high.take_damage(1000.0)
	var list := PoisonPuddle.alive(tree)
	check_eq(list.size(), 2, "two puddles")
	if list.size() < 2:
		return
	var coop := RunState.coop_damage_mult()
	check_near(list[0].damage_per_tick, data.contact_damage_at_wave(7) * coop * 0.5, 0.0001, "wave 7, four players")
	check_near(list[1].damage_per_tick, data.contact_damage_at_wave(14) * coop * 0.5 * 1.5, 0.0001,
			"wave 14, an enraged ghoul hits harder")
	check(list[1].damage_per_tick > list[0].damage_per_tick * 2.0, "later waves hurt more")


func test_puddle_ticks_twice_a_second_on_heroes_only_for_three_seconds() -> void:
	var inside := EFakes.spawn_player(world, Vector3(2.5, 0.0, 3.0))
	var outside := EFakes.spawn_player(world, Vector3(6.0, 0.0, 3.0))
	var bystander := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3(2.0, 0.0, 3.0))
	bystander.data.move_speed = 0.0
	var ghoul := _spawn(&"plague_ghoul", Vector3(2.0, 0.0, 3.0), 7)
	ghoul.take_damage(1000.0)
	var puddle := PoisonPuddle.alive(tree)[0]
	_step(puddle, 0.45)
	check_eq(inside.fake_hits.size(), 0, "no tick before 0.5 s")
	_step(puddle, 0.1)
	check_eq(inside.fake_hits.size(), 1, "the first tick at 0.5 s")
	_step(puddle, 0.5)
	check_eq(inside.fake_hits.size(), 2, "two ticks a second")
	check_eq(outside.fake_hits.size(), 0, "a hero outside the 1.6 m takes nothing")
	check_near(inside.fake_hits[0], puddle.damage_per_tick, 0.0001, "the tick damage")
	check_eq(inside.fake_kinds[0], CombatMath.KIND_AOE, "ground damage (Avoidance counts)")
	check(inside.fake_sources[0] == null, "no source: nothing struck, no Thorns / Retribution")
	check_eq(bystander.hp, bystander.max_hp, "enemies walk through it unhurt")
	_step(puddle, 2.0)
	check_eq(puddle.ticks_done, 6, "six ticks in 3 s")
	check_eq(inside.fake_hits.size(), 6, "all of them on the hero standing in it")
	check(puddle.is_gone(), "gone after 3 s")
	check(PoisonPuddle.alive(tree).is_empty(), "no longer listed")
	_step(puddle, 1.0)
	check_eq(inside.fake_hits.size(), 6, "a gone puddle does not tick")


func test_stepping_out_of_the_puddle_stops_the_damage() -> void:
	var hero := EFakes.spawn_player(world, Vector3(2.0, 0.0, 3.0))
	var ghoul := _spawn(&"plague_ghoul", Vector3(2.0, 0.0, 3.0), 7)
	ghoul.take_damage(1000.0)
	var puddle := PoisonPuddle.alive(tree)[0]
	_step(puddle, 0.55)
	check_eq(hero.fake_hits.size(), 1, "hit once")
	hero.global_position = Vector3(2.0 + 1.7, 0.0, 3.0)
	_step(puddle, 1.5)
	check_eq(hero.fake_hits.size(), 1, "out of the 1.6 m: no more ticks")
	hero.global_position = Vector3(2.0 + 1.5, 0.0, 3.0)
	_step(puddle, 0.6)
	check(hero.fake_hits.size() >= 2, "back in: hurt again")


func test_a_downed_hero_is_not_hit() -> void:
	var hero := EFakes.spawn_player(world, Vector3(0.0, 0.0, 0.0))
	var puddle := PoisonPuddle.spawn(_entities(), Vector3.ZERO, 1.6, 3.0, 0.5, 2.0, Color.GREEN)
	hero.downed = true
	_step(puddle, 1.1)
	check_eq(hero.fake_hits.size(), 0, "ghosts are not hurt by the puddle")


func test_at_most_twelve_puddles_the_oldest_goes() -> void:
	var made: Array[PoisonPuddle] = []
	for i in 12:
		made.append(PoisonPuddle.spawn(_entities(), Vector3(float(i), 0.0, 0.0), 1.6, 3.0, 0.5, 1.0, Color.GREEN))
	check_eq(PoisonPuddle.alive(tree).size(), 12, "twelve alive")
	# The fifth is the oldest by age (the others have not been stepped).
	_step(made[4], 1.0)
	var newest := PoisonPuddle.spawn(_entities(), Vector3(20.0, 0.0, 0.0), 1.6, 3.0, 0.5, 1.0, Color.GREEN)
	var list := PoisonPuddle.alive(tree)
	check_eq(list.size(), 12, "still twelve: the 13th pushed one out")
	check(made[4].is_gone(), "the oldest (by age) vanished")
	check(not made[0].is_gone() and not newest.is_gone(), "the others stay")
	check(not list.has(made[4]) and list.has(newest), "the list agrees")
	# Equal ages: the first spawned goes.
	var fresh := PoisonPuddle.spawn(_entities(), Vector3(22.0, 0.0, 0.0), 1.6, 3.0, 0.5, 1.0, Color.GREEN)
	check(made[0].is_gone(), "ties: the one spawned first")
	check(not fresh.is_gone(), "the newest stays")
	check_eq(PoisonPuddle.alive(tree).size(), 12, "twelve")


func test_a_wave_end_despawn_leaves_no_puddle_but_the_wave_sweep_removes_any() -> void:
	var ghoul := _spawn(&"plague_ghoul", Vector3.ZERO, 7)
	ghoul.despawn()
	check(PoisonPuddle.alive(tree).is_empty(), "a despawn is no death")
	var puddle := PoisonPuddle.spawn(_entities(), Vector3.ZERO, 1.6, 3.0, 0.5, 1.0, Color.GREEN)
	check(puddle.is_in_group(&"enemy_hazards"), "an enemy hazard")
	check(puddle.is_in_group(&"ability_areas"), "in the group the wave end sweeps")
	var director := WaveDirector.create(EFakes.arena_of(world))
	world.add_child(director)
	director.stop()
	check(puddle.is_queued_for_deletion(), "WaveDirector.stop() sweeps it: it never survives the wave")
	check(not puddle.is_in_group(&"enemy_hazards") or puddle.is_queued_for_deletion(), "gone")


func test_a_new_puddle_does_not_touch_other_hazard_kinds_in_the_cap() -> void:
	# Only PoisonPuddles count towards the cap of twelve.
	var other := Node3D.new()
	other.add_to_group(&"enemy_hazards")
	_entities().add_child(other)
	for i in 12:
		PoisonPuddle.spawn(_entities(), Vector3(float(i), 0.0, 0.0), 1.6, 3.0, 0.5, 1.0, Color.GREEN)
	check_eq(PoisonPuddle.alive(tree).size(), 12, "twelve puddles next to a foreign hazard")
	check(not other.is_queued_for_deletion(), "the foreign hazard stays")


# --- Cultist Acolyte: distance, herd -------------------------------------------------------------

func test_acolyte_backs_off_inside_six_metres() -> void:
	var a := _acolyte(Vector3.ZERO, Vector3(3.0, 0.0, 0.0))
	a.attack_cooldown_left = 99.0
	_step(a, 1.0)
	var dist := EFakes.flat_distance(a.global_position, _hero().global_position)
	check(dist > 4.5, "it ran from the hero 3 m away: %f" % dist)
	check(a.global_position.x < -1.0, "away from the hero")


func test_acolyte_closes_in_beyond_nine_metres_and_holds_inside_the_band() -> void:
	var far := _acolyte(Vector3.ZERO, Vector3(14.0, 0.0, 0.0))
	far.attack_cooldown_left = 99.0
	_step(far, 1.0)
	check(far.global_position.x > 1.0, "it closes in on a hero 14 m away: %f" % far.global_position.x)
	# Band: 7.5 m is between 6 and 9, with nobody else around it stands.
	far.global_position = Vector3(0.0, 0.0, 0.0)
	far._move_velocity = Vector3.ZERO
	_hero().global_position = Vector3(7.5, 0.0, 0.0)
	Enemy.invalidate_player_cache()
	_step(far, 1.0)
	check(absf(far.global_position.x) < 0.3, "inside 6..9 m it holds its place: %f" % far.global_position.x)


func test_acolyte_keeps_to_the_other_enemies() -> void:
	var a := _acolyte(Vector3.ZERO, Vector3(7.5, 0.0, 0.0))
	a.attack_cooldown_left = 99.0
	for i in 3:
		_dummy(Vector3(float(i) - 1.0, 0.0, -7.0), 1000.0)
	_step(a, 2.5)
	check(a.global_position.z < -1.5, "it drifts to the herd in the band: z %f" % a.global_position.z)
	check(EFakes.flat_distance(a.global_position, _hero().global_position) >= 6.0, "but never inside 6 m of the hero")


func test_acolyte_backing_off_never_runs_into_a_wall() -> void:
	var half := Arena.SIZE * 0.5
	var a := _acolyte(Vector3(-half.x + 1.5, 0.0, 0.0), Vector3(-half.x + 4.5, 0.0, 0.0))
	a.attack_cooldown_left = 99.0
	_step(a, 2.0)
	check(a.global_position.x >= -half.x, "stays inside the arena: %f" % a.global_position.x)
	check(absf(a.global_position.z) > 1.0, "it slid along the wall instead of pressing into it: z %f" % a.global_position.z)


# --- Cultist Acolyte: heal / shield ---------------------------------------------------------------

func test_acolyte_channels_then_heals_25_percent_of_the_most_hurt_enemy() -> void:
	var a := _acolyte(Vector3.ZERO, Vector3(7.5, 0.0, 0.0))
	var ally := _dummy(Vector3(0.0, 0.0, 4.0), 40.0)
	ally.hp = 10.0
	_step(a, DT)
	check_eq(a.ai_state, Enemy.AiState.CHANNEL, "channelling")
	var beam := a.get_node_or_null(^"SupportBeam") as SupportBeam
	check(beam != null, "a beam")
	if beam != null:
		check(beam.top_level, "the beam lives in world coordinates")
		check_near(beam.to_point.z, 4.0 + Enemy.SUPPORT_BEAM_TO * 0.0, 0.05, "ends at the ally")
		check_near(beam.from_point.y, Enemy.SUPPORT_BEAM_FROM, 0.001, "leaves the staff height")
	check(a.model.is_winding_up(), "the model shows the tell")
	var spot := a.global_position
	_step(a, 0.5)
	check_eq(ally.hp, 10.0, "nothing before the channel ends (0.6 s)")
	check(a.global_position.is_equal_approx(spot), "it stands still while channelling")
	_step(a, 0.15)
	check_near(ally.hp, 10.0 + 40.0 * 0.25, 0.001, "healed 25% of the ally's max HP")
	check_eq(a.ai_state, Enemy.AiState.MOVE, "channel over")
	check_near(a.attack_cooldown_left, 4.0, 0.05, "the next one in 4 s")
	check(beam == null or beam.is_queued_for_deletion(), "the beam ends")
	check(not a.model.is_winding_up(), "the tell ends")


func test_acolyte_picks_the_most_injured_within_seven_metres() -> void:
	var a := _acolyte(Vector3.ZERO, Vector3(7.5, 0.0, 0.0))
	var mild := _dummy(Vector3(0.0, 0.0, 3.0), 20.0)
	mild.hp = 10.0
	var worst := _dummy(Vector3(0.0, 0.0, -6.5), 20.0)
	worst.hp = 3.0
	var out_of_reach := _dummy(Vector3(-7.5, 0.0, 0.0), 20.0)
	out_of_reach.hp = 1.0
	_step(a, DT)
	check(a._support_target == worst, "the lowest HP share in reach, not the one 7.5 m away")
	check_eq(a._support_action, Enemy.SupportAction.HEAL, "a heal")


func test_acolyte_heals_by_hp_share_not_by_absolute_hp() -> void:
	var a := _acolyte(Vector3.ZERO, Vector3(7.5, 0.0, 0.0))
	# The lower share (30%) has the higher absolute HP (30 vs 5): the share decides.
	var big := _dummy(Vector3(0.0, 0.0, 3.0), 100.0)
	big.hp = 30.0
	var small := _dummy(Vector3(0.0, 0.0, -3.0), 10.0)
	small.hp = 5.0
	_step(a, DT)
	check(a._support_target == big, "30% of 100 before 50% of 10, although 30 HP > 5 HP")
	_step(a, 0.7)
	check_near(big.hp, 30.0 + 100.0 * 0.25, 0.001, "the big one is healed")
	check_eq(small.hp, 5.0, "the small one is not")
	# And the share, not the HP missing: 20% of 10 (8 missing) before 60% of 100 (40 missing).
	EnemyGrid.mark_dirty()
	big.hp = 60.0
	small.hp = 2.0
	check(a._pick_support_target(a.global_position) == small, "the lowest share, not the most HP missing")


func test_acolyte_never_heals_a_boss_but_may_shield_it() -> void:
	var boss_data := EFakes.enemy_data()
	boss_data.is_boss = true
	boss_data.max_hp = 450.0
	boss_data.move_speed = 0.0
	var a := _acolyte(Vector3.ZERO, Vector3(7.5, 0.0, 0.0))
	var boss := EFakes.spawn_enemy(world, boss_data, Vector3(0.0, 0.0, 4.0))
	check(boss.is_boss(), "the control: it is a boss")
	boss.hp = 100.0
	# Alone and badly hurt: no heal. (The shield is allowed.)
	_step(a, DT)
	check_eq(a._support_action, Enemy.SupportAction.SHIELD, "a boss is shielded, not healed")
	check(a._support_target == boss, "the shield goes to the boss")
	_step(a, 0.7)
	check_eq(boss.hp, 100.0, "no HP for the boss")
	check_near(boss.shield_hp, 450.0 * 0.2, 0.001, "its shield is 20% of max HP")
	# The shield only refreshes: with it full there is nothing left to do.
	_step(a, 4.7)
	check_near(boss.shield_hp, 450.0 * 0.2, 0.001, "no stacking")
	check_eq(boss.hp, 100.0, "still no HP")
	check_eq(a.ai_state, Enemy.AiState.MOVE, "nothing to do: it waits")
	# A hurt normal enemy beside the (lower HP share) boss is healed instead.
	var grunt := _dummy(Vector3(0.0, 0.0, -3.0), 20.0)
	grunt.hp = 15.0
	EnemyGrid.mark_dirty()
	a.attack_cooldown_left = 0.0
	_step(a, DT)
	check_eq(a._support_action, Enemy.SupportAction.HEAL, "now there is somebody to heal")
	check(a._support_target == grunt, "the grunt, though the boss has the lower HP share")
	_step(a, 0.7)
	check_near(grunt.hp, 15.0 + 20.0 * 0.25, 0.001, "the grunt is healed")
	check_eq(boss.hp, 100.0, "the boss is not")


func test_acolyte_shields_the_strongest_when_nobody_is_hurt_and_never_stacks() -> void:
	var a := _acolyte(Vector3.ZERO, Vector3(7.5, 0.0, 0.0))
	var weak := _dummy(Vector3(0.0, 0.0, 3.0), 10.0)
	var strong := _dummy(Vector3(0.0, 0.0, -3.0), 50.0)
	_step(a, DT)
	check_eq(a._support_action, Enemy.SupportAction.SHIELD, "everybody healthy: a shield")
	check(a._support_target == strong, "on the strongest (highest max HP)")
	_step(a, 0.7)
	check_near(strong.shield_hp, 50.0 * 0.2, 0.001, "20% of its max HP")
	check_eq(weak.shield_hp, 0.0, "only one target")
	check(strong.get_node_or_null(^"SupportShield") != null, "a violet bubble on a normal enemy")
	# The next channel (4 s later) goes to the one without a shield: no stacking on the strong one.
	_step(a, 4.7)
	check_near(strong.shield_hp, 10.0, 0.001, "the strong one's shield did not grow")
	check_near(weak.shield_hp, 2.0, 0.001, "the next one is shielded instead")
	# Everybody shielded: no channel at all (nothing to do).
	_step(a, 1.0)
	_step(a, 5.0)
	check_eq(a.ai_state, Enemy.AiState.MOVE, "nothing left to shield: it waits")
	# A damaged shield is refreshed up to 20%, not by another 20%.
	strong.shield_hp = 4.0
	_step(a, 1.0)
	check_near(strong.shield_hp, 10.0, 0.001, "refreshed to 20% of max HP")


func test_acolyte_shield_never_exceeds_twenty_percent_and_keeps_a_bigger_one() -> void:
	var boss_data := EFakes.enemy_data()
	boss_data.is_boss = true
	boss_data.max_hp = 100.0
	var boss := EFakes.spawn_enemy(world, boss_data, Vector3.ZERO)
	check(boss.apply_support_shield(0.2), "a fresh shield")
	check_near(boss.shield_hp, boss.max_hp * 0.2, 0.001, "20%")
	check(not boss.apply_support_shield(0.2), "refresh only: no growth")
	check_near(boss.shield_hp, boss.max_hp * 0.2, 0.001, "still 20%")
	boss.shield_hp = boss.max_hp * 0.3
	check(not boss.apply_support_shield(0.2), "a bigger shield stays")
	check_near(boss.shield_hp, boss.max_hp * 0.3, 0.001, "30% kept")
	var dead := _dummy(Vector3(3.0, 0.0, 0.0))
	dead.take_damage(1000.0)
	check(not dead.apply_support_shield(0.2), "nothing for the dead")


func test_an_elite_shows_the_acolytes_shield_on_its_plate_not_as_a_bubble() -> void:
	var elite := _dummy(Vector3(3.0, 0.0, 0.0), 30.0)
	elite.make_elite(EliteAffixes.FRENZIED)
	check(elite.apply_support_shield(0.2), "shielded")
	check(elite.get_node_or_null(^"SupportShield") == null, "elites have their own plate")
	var normal := _dummy(Vector3(-3.0, 0.0, 0.0), 30.0)
	check(normal.apply_support_shield(0.2), "shielded")
	var bubble := normal.get_node_or_null(^"SupportShield") as SupportShield
	check(bubble != null, "a normal enemy gets the bubble")
	if bubble != null:
		bubble._process(DT)
		check(bubble.is_shown(), "shown while the shield holds")
		normal.shield_hp = 0.0
		bubble._process(DT)
		check(not bubble.is_shown(), "hidden once it is gone")


func test_an_acolyte_shield_breaks_for_good_but_a_shielding_elites_regrows() -> void:
	var normal := _dummy(Vector3(3.0, 0.0, 0.0), 1000.0)
	normal.apply_support_shield(0.2)
	normal.take_damage(normal.shield_hp + 1.0)
	check_eq(normal.shield_hp, 0.0, "the shield broke")
	_step(normal, EliteAffixes.SHIELD_REGROW + 1.0)
	check_eq(normal.shield_hp, 0.0, "an Acolyte's shield does not regrow")
	var elite := _dummy(Vector3(-3.0, 0.0, 0.0), 1000.0)
	elite.make_elite(EliteAffixes.SHIELDING)
	var full := elite.shield_hp
	check(full > 0.0, "a Shielding elite starts shielded")
	elite.take_damage(full + 1.0)
	check_eq(elite.shield_hp, 0.0, "broken")
	_step(elite, EliteAffixes.SHIELD_REGROW + 0.5)
	check(elite.shield_hp > 0.0, "the Shielding affix still regrows")


func test_acolyte_never_helps_itself_or_the_loot_goblin() -> void:
	var a := _acolyte(Vector3.ZERO, Vector3(7.5, 0.0, 0.0))
	a.hp = 1.0
	var goblin := LootGoblin.create(LootGoblin.goblin_data(), 3)
	_entities().add_child(goblin)
	goblin.global_position = Vector3(0.0, 0.0, 3.0)
	goblin.hp = 1.0
	_step(a, 0.1)
	check_eq(a.ai_state, Enemy.AiState.MOVE, "only itself and a goblin are hurt: nothing to channel on")
	check(a._support_target == null, "no target")
	goblin.despawn()


func test_acolyte_helps_other_acolytes() -> void:
	var a := _acolyte(Vector3.ZERO, Vector3(7.5, 0.0, 0.0))
	var b := _spawn(&"cultist_acolyte", Vector3(0.0, 0.0, 3.0), 9)
	b.attack_cooldown_left = 99.0
	b.hp = 1.0
	_step(a, DT)
	check(a._support_target == b, "an Acolyte may heal another")


# --- Cultist Acolyte: interruptions ---------------------------------------------------------------

func _channelling_acolyte() -> Array:
	var a := _acolyte(Vector3.ZERO, Vector3(7.5, 0.0, 0.0))
	var ally := _dummy(Vector3(0.0, 0.0, 4.0), 40.0)
	ally.hp = 10.0
	_step(a, 0.2)
	return [a, ally]


func _assert_interrupted(a: Enemy, ally: Enemy, what: String) -> void:
	check_eq(a.ai_state, Enemy.AiState.MOVE, "%s: the channel ends" % what)
	check(a._support_beam == null, "%s: the beam is gone" % what)
	check(not a.model.is_winding_up(), "%s: the tell stops" % what)
	check(a.attack_cooldown_left >= 2.0 - 0.01, "%s: half the cooldown comes first (%f)" % [what, a.attack_cooldown_left])
	_step(a, 0.6)
	check_eq(ally.hp, 10.0, "%s: no heal landed" % what)


func test_a_stun_interrupts_the_channel() -> void:
	var r := _channelling_acolyte()
	var a: Enemy = r[0]
	check_eq(a.ai_state, Enemy.AiState.CHANNEL, "channelling")
	a.apply_stun(1.0)
	_assert_interrupted(a, r[1], "stun")


func test_a_knockback_interrupts_the_channel_but_a_plain_hit_does_not() -> void:
	var r := _channelling_acolyte()
	var a: Enemy = r[0]
	a.take_damage(1.0)
	check_eq(a.ai_state, Enemy.AiState.CHANNEL, "damage alone does not break it")
	a.take_damage(1.0, false, null, Vector3(1.0, 0.0, 0.0))
	_assert_interrupted(a, r[1], "knockback")


func test_fear_and_taunt_interrupt_the_channel() -> void:
	var r := _channelling_acolyte()
	var a: Enemy = r[0]
	a.apply_fear(1.0, Vector3(5.0, 0.0, 0.0))
	_assert_interrupted(a, r[1], "fear")
	var r2 := _channelling_acolyte()
	var b: Enemy = r2[0]
	b.apply_taunt(_hero(), 1.0)
	_assert_interrupted(b, r2[1], "taunt")


func test_the_channel_ends_when_the_target_dies_or_leaves_the_reach() -> void:
	var r := _channelling_acolyte()
	var a: Enemy = r[0]
	var ally: Enemy = r[1]
	ally.take_damage(1000.0)
	_step(a, DT)
	check_eq(a.ai_state, Enemy.AiState.MOVE, "target died: cancelled")
	check(a._support_beam == null, "no beam")
	check(a.attack_cooldown_left >= Enemy.SUPPORT_RETRY - 0.01, "a short pause before the next search")
	var r2 := _channelling_acolyte()
	var b: Enemy = r2[0]
	var runner: Enemy = r2[1]
	runner.global_position = Vector3(0.0, 0.0, 12.0)
	_step(b, DT)
	check_eq(b.ai_state, Enemy.AiState.MOVE, "target out of reach + leash: cancelled")
	check_eq(runner.hp, 10.0, "not healed")


func test_no_target_hero_ends_the_channel() -> void:
	var r := _channelling_acolyte()
	var a: Enemy = r[0]
	_hero().downed = true
	Enemy.invalidate_player_cache()
	_step(a, DT)
	check_eq(a.ai_state, Enemy.AiState.MOVE, "nobody to keep a distance from: the channel is dropped")
	check(a._support_beam == null, "no beam")


func test_an_interrupted_acolyte_comes_back_sooner() -> void:
	var r := _channelling_acolyte()
	var a: Enemy = r[0]
	var ally: Enemy = r[1]
	a.apply_stun(0.5)
	check(a.attack_cooldown_left >= 1.99 and a.attack_cooldown_left <= 2.01, "half of 4 s")
	_step(a, 2.2)
	check_eq(a.ai_state, Enemy.AiState.CHANNEL, "channelling again after ~2 s, not 4")
	_step(a, 0.7)
	check(ally.hp > 10.0, "and this one heals")


# --- Priority target -----------------------------------------------------------------------------

func test_only_the_acolyte_is_a_priority_target() -> void:
	var a := _spawn(&"cultist_acolyte", Vector3.ZERO, 9)
	var skeleton := _spawn(&"skeleton_grunt", Vector3(3.0, 0.0, 0.0))
	check(a.is_priority_target(), "the Acolyte")
	check(not skeleton.is_priority_target(), "a skeleton is not")
	check(a.is_in_group(&"priority_targets") and not skeleton.is_in_group(&"priority_targets"), "the group")
	a.take_damage(1000.0)
	check(not a.is_priority_target(), "a dead Acolyte is none")
	check(not a.is_in_group(&"priority_targets"), "and leaves the group")
	var b := _spawn(&"cultist_acolyte", Vector3(5.0, 0.0, 0.0), 9)
	b.despawn()
	check(not b.is_in_group(&"priority_targets"), "a despawn too")


func test_priority_enemy_query_respects_the_reach() -> void:
	var near := _spawn(&"cultist_acolyte", Vector3(5.0, 0.0, 0.0), 9)
	var far := _spawn(&"cultist_acolyte", Vector3(9.0, 0.0, 0.0), 9)
	_spawn(&"skeleton_grunt", Vector3(1.0, 0.0, 0.0))
	check(BotInput.priority_enemy(tree, Vector3.ZERO, 7.5) == near, "the nearest Acolyte in reach")
	check(BotInput.priority_enemy(tree, Vector3.ZERO, 4.0) == null, "none beyond the reach")
	check(BotInput.priority_enemy(tree, Vector3.ZERO, 10.0) == near, "still the nearest of two")
	near.take_damage(1000.0)
	check(BotInput.priority_enemy(tree, Vector3.ZERO, 10.0) == far, "the dead one no longer counts")
	far.take_damage(1000.0)
	check(BotInput.priority_enemy(tree, Vector3.ZERO, 10.0) == null, "nobody")


# --- Flesh Golem: the hook -----------------------------------------------------------------------

func _golem(pos: Vector3, hero_pos: Vector3) -> Enemy:
	EFakes.spawn_player(world, hero_pos)
	var g := _spawn(&"flesh_golem", pos, 12)
	g.attack_cooldown_left = 0.0
	return g


func test_golem_telegraphs_a_line_for_0_8_s_then_hooks_the_hero_in_it() -> void:
	var g := _golem(Vector3.ZERO, Vector3(6.0, 0.0, 0.0))
	var hero := _hero()
	_step(g, DT)
	check_eq(g.ai_state, Enemy.AiState.HOOK, "telegraphing")
	check_eq(g.hook_serial, 1, "the first hook")
	var line := g.get_node_or_null(^"HookLine") as HookLine
	check(line != null, "a line child")
	check(g.model.is_winding_up(), "the model shows the tell")
	var spot := g.global_position
	_step(g, 0.4)
	check(g.global_position.is_equal_approx(spot), "it stands still while it aims")
	if line != null:
		check(line.progress > 0.4 and line.progress < 0.6, "the countdown fill runs: %f" % line.progress)
	check_eq(hero.fake_hooks.size(), 0, "no hook yet")
	_step(g, 0.45)
	check_eq(hero.fake_hooks.size(), 1, "hooked after 0.8 s")
	var hook := hero.fake_hooks[0]
	check_near(hook["raw"], g.contact_damage, 0.0001, "1 x the golem's contact damage")
	check(hook["source"] == g, "the golem is the source")
	check_near(hook["distance"], 3.0, 0.001, "pulled 3 m")
	check((hook["toward"] as Vector3).distance_to(Vector3.ZERO) < 0.001, "towards the golem (where it stood): %s" % hook["toward"])
	check_eq(g.ai_state, Enemy.AiState.MOVE, "back to walking")
	check_near(g.attack_cooldown_left, 6.0, 0.05, "the next hook in 6 s")
	check(line != null and line.striking, "the chain flies")
	check(not g.model.is_winding_up(), "the tell ends")


func test_golem_only_hooks_heroes_between_four_and_nine_metres() -> void:
	var g := _golem(Vector3.ZERO, Vector3(3.0, 0.0, 0.0))
	_step(g, 0.2)
	check_eq(g.ai_state, Enemy.AiState.MOVE, "a hero 3 m away is meleed, not hooked")
	_hero().global_position = Vector3(10.0, 0.0, 0.0)
	Enemy.invalidate_player_cache()
	_step(g, 0.2)
	check_eq(g.ai_state, Enemy.AiState.MOVE, "10 m is out of the band")
	_hero().global_position = Vector3(8.8, 0.0, 0.0)
	Enemy.invalidate_player_cache()
	_step(g, DT)
	check_eq(g.ai_state, Enemy.AiState.HOOK, "8.8 m is inside")


func test_golem_does_not_hook_while_its_cooldown_runs_and_starts_with_one() -> void:
	EFakes.spawn_player(world, Vector3(6.0, 0.0, 0.0))
	var fresh := _spawn(&"flesh_golem", Vector3.ZERO, 12)
	check(fresh.attack_cooldown_left >= 3.0 - 0.001 and fresh.attack_cooldown_left <= 6.0, "a new golem waits 3..6 s (staggered)")
	_step(fresh, 1.0)
	check_eq(fresh.ai_state, Enemy.AiState.MOVE, "no hook in the first seconds")
	var g := _golem(Vector3(0.0, 0.0, 4.0), Vector3(6.0, 0.0, 4.0))
	_step(g, 0.85)
	check_near(g.attack_cooldown_left, 6.0, 0.1, "one hook done")
	_step(g, 2.0)
	check_eq(g.hook_serial, 1, "no second hook for 6 s")
	check_eq(g.ai_state, Enemy.AiState.MOVE, "walking")


func test_golem_hooks_the_first_hero_in_the_line_only() -> void:
	var g := _golem(Vector3.ZERO, Vector3(5.0, 0.0, 0.0))
	var near := _hero()
	var behind := EFakes.spawn_player(world, Vector3(7.5, 0.0, 0.0))
	var beside := EFakes.spawn_player(world, Vector3(5.0, 0.0, 2.0))
	_step(g, 1.0)
	check_eq(near.fake_hooks.size(), 1, "the nearest in the line")
	check_eq(behind.fake_hooks.size(), 0, "the one behind it is shielded by the first")
	check_eq(beside.fake_hooks.size(), 0, "a hero beside the line is safe")


func test_the_hook_line_follows_the_hero_then_locks_for_the_last_part() -> void:
	# Early sidestep: the line follows, the hero is still hooked.
	var g := _golem(Vector3.ZERO, Vector3(6.0, 0.0, 0.0))
	var hero := _hero()
	_step(g, 0.2)
	hero.global_position = Vector3(6.0, 0.0, 3.0)
	Enemy.invalidate_player_cache()
	_step(g, 0.8)
	check_eq(hero.fake_hooks.size(), 1, "the line turned after the hero while the aim was free")
	# Late sidestep: after the lock the line stays and the hero is gone from it.
	var g2 := _golem(Vector3(0.0, 0.0, -10.0), Vector3(6.0, 0.0, -10.0))
	var hero2 := _hero(1)
	_step(g2, 0.55)
	check(g2._aim_dir.is_equal_approx(Vector3(1.0, 0.0, 0.0)), "aimed at the hero")
	hero2.global_position = Vector3(6.0, 0.0, -10.0 + 3.0)
	Enemy.invalidate_player_cache()
	_step(g2, 0.35)
	check_eq(hero2.fake_hooks.size(), 0, "a sidestep after the lock dodges the hook")
	check(g2._aim_dir.is_equal_approx(Vector3(1.0, 0.0, 0.0)), "the aim stayed locked")
	check_near(g2.attack_cooldown_left, 6.0, 0.1, "a whiff still costs the cooldown")


func test_the_pull_stops_short_of_touching_the_golem() -> void:
	var g := _golem(Vector3.ZERO, Vector3(4.0, 0.0, 0.0))
	var hero := _hero()
	_step(g, 1.0)
	check_eq(hero.fake_hooks.size(), 1, "hooked")
	# 4 m - golem radius 0.9 - hero radius 0.45 - the stop gap 0.1 = 2.55 m of pull room.
	check_near(hero.fake_hooks[0]["distance"], 4.0 - 0.9 - Player.RADIUS - Enemy.HOOK_STOP_GAP, 0.001,
			"the pull is limited to what keeps them apart")


func test_a_stealthed_hero_is_not_hooked() -> void:
	var g := _golem(Vector3.ZERO, Vector3(6.0, 0.0, 0.0))
	_hero().stealth_left = 5.0
	Enemy.invalidate_player_cache()
	_step(g, 1.0)
	check_eq(g.ai_state, Enemy.AiState.MOVE, "hidden heroes are neither targeted nor hooked")
	check_eq(g.hook_serial, 0, "no hook started")


func test_a_hero_who_turns_stealthed_during_the_telegraph_is_not_pulled() -> void:
	# A second, visible hero keeps the golem aiming; the first one is the hook target.
	var g := _golem(Vector3.ZERO, Vector3(5.0, 0.0, 0.0))
	var target := _hero()
	var other := EFakes.spawn_player(world, Vector3(0.0, 0.0, -8.0))
	Enemy.invalidate_player_cache()
	_step(g, 0.3)
	check_eq(g.ai_state, Enemy.AiState.HOOK, "the hero was visible: telegraphing")
	check(g._aim_dir.is_equal_approx(Vector3(1.0, 0.0, 0.0)), "aimed at the nearer hero: %s" % g._aim_dir)
	target.stealth_left = 5.0  # Vanish
	Enemy.invalidate_player_cache()
	_step(g, 0.1)
	check_eq(g.ai_state, Enemy.AiState.HOOK, "the other hero is still in sight: the telegraph goes on")
	_step(g, 0.8)
	check_eq(target.fake_hooks.size(), 0, "the chain skips the hero who vanished: no damage, no pull")
	check_eq(other.fake_hooks.size(), 0, "the other hero stood outside the line")
	check_eq(g.ai_state, Enemy.AiState.MOVE, "the hook is over")
	check(g.attack_cooldown_left > 5.0 and g.attack_cooldown_left <= 6.0, "a whiff still costs the whole cooldown (%f)" % g.attack_cooldown_left)


func test_a_lone_hero_who_vanishes_during_the_telegraph_makes_the_golem_drop_the_hook() -> void:
	var g := _golem(Vector3.ZERO, Vector3(6.0, 0.0, 0.0))
	var hero := _hero()
	_step(g, 0.3)
	check_eq(g.ai_state, Enemy.AiState.HOOK, "telegraphing")
	hero.stealth_left = 5.0
	Enemy.invalidate_player_cache()
	_step(g, 0.1)
	check_eq(g.ai_state, Enemy.AiState.MOVE, "nobody to see: the hook is dropped")
	check(g._hook_line == null, "no line")
	check_near(g.attack_cooldown_left, 3.0 - 0.1, 0.1, "half the cooldown, like any interruption")
	_step(g, 1.0)
	check_eq(hero.fake_hooks.size(), 0, "the hidden hero is never hooked")


func test_the_golem_aims_at_a_visible_hero_not_at_a_nearer_stealthed_one() -> void:
	var g := _golem(Vector3.ZERO, Vector3(5.0, 0.0, 0.0))
	var hidden := _hero()
	hidden.stealth_left = 5.0
	var seen := EFakes.spawn_player(world, Vector3(0.0, 0.0, 8.0))
	Enemy.invalidate_player_cache()
	_step(g, DT)
	check_eq(g.ai_state, Enemy.AiState.HOOK, "a visible hero in the band: it hooks")
	check(g._aim_dir.is_equal_approx(Vector3(0.0, 0.0, 1.0)), "aimed at the visible hero: %s" % g._aim_dir)
	_step(g, 1.0)
	check_eq(seen.fake_hooks.size(), 1, "the visible hero is hooked")
	check_eq(hidden.fake_hooks.size(), 0, "the stealthed one is not")


func test_a_stun_a_fear_or_a_taunt_cancels_the_hook_and_knockback_does_not() -> void:
	var g := _golem(Vector3.ZERO, Vector3(6.0, 0.0, 0.0))
	_step(g, 0.2)
	check_eq(g.ai_state, Enemy.AiState.HOOK, "telegraphing")
	g.take_damage(1.0, false, null, Vector3(1.0, 0.0, 0.0))
	check_eq(g.ai_state, Enemy.AiState.HOOK, "80% knockback resist: it keeps aiming")
	g.apply_stun(1.0)
	check_eq(g.ai_state, Enemy.AiState.MOVE, "stunned: the hook is off")
	check(g._hook_line == null, "the line is gone")
	check(not g.model.is_winding_up(), "the tell stops")
	check(g.attack_cooldown_left >= 3.0 - 0.01, "half the cooldown first (%f)" % g.attack_cooldown_left)
	var g2 := _golem(Vector3(0.0, 0.0, -9.0), Vector3(6.0, 0.0, -9.0))
	_step(g2, 0.2)
	g2.apply_fear(1.0, Vector3(3.0, 0.0, -9.0))
	check_eq(g2.ai_state, Enemy.AiState.MOVE, "fear")
	var g3 := _golem(Vector3(0.0, 0.0, 9.0), Vector3(6.0, 0.0, 9.0))
	_step(g3, 0.2)
	g3.apply_taunt(_hero(), 1.0)
	check_eq(g3.ai_state, Enemy.AiState.MOVE, "taunt")
	_step(g, 1.0)
	check_eq(_hero().fake_hooks.size(), 0, "nobody was hooked")


func test_a_dying_golem_never_fires() -> void:
	var g := _golem(Vector3.ZERO, Vector3(6.0, 0.0, 0.0))
	var hero := _hero()
	_step(g, 0.3)
	g.take_damage(1000.0)
	_step(g, 1.0)
	check_eq(hero.fake_hooks.size(), 0, "dead golems do not hook")
	check(g.is_queued_for_deletion(), "the golem and its line are freed")


func test_a_golem_with_no_hero_in_sight_wanders_and_drops_the_hook() -> void:
	var g := _golem(Vector3.ZERO, Vector3(6.0, 0.0, 0.0))
	_step(g, 0.3)
	check_eq(g.ai_state, Enemy.AiState.HOOK, "telegraphing")
	_hero().downed = true
	Enemy.invalidate_player_cache()
	_step(g, DT)
	check_eq(g.ai_state, Enemy.AiState.MOVE, "no living hero: the hook is dropped")
	check(g._hook_line == null, "no line")


func test_a_hook_is_data_driven() -> void:
	var data := EFakes.enemy_data(EnemyData.Behavior.BRUTE)
	data.attack_cooldown = 2.0
	data.hook_range_min = 2.0
	data.hook_range_max = 5.0
	data.hook_telegraph = 0.4
	data.hook_pull = 1.5
	data.hook_damage_ratio = 2.0
	data.move_speed = 0.0
	EFakes.spawn_player(world, Vector3(3.0, 0.0, 0.0))
	var g := EFakes.spawn_enemy(world, data, Vector3.ZERO)
	g.attack_cooldown_left = 0.0
	_step(g, 0.42)
	var hero := _hero()
	check_eq(hero.fake_hooks.size(), 1, "a 3 m hook with a band of 2..5 m and a 0.4 s line")
	check_near(hero.fake_hooks[0]["raw"], g.contact_damage * 2.0, 0.0001, "2 x contact damage")
	check_near(hero.fake_hooks[0]["distance"], 1.5, 0.001, "pull 1.5 m")
	check_near(g.attack_cooldown_left, 2.0, 0.05, "cooldown 2 s")


func test_hook_escape_dir_points_out_of_the_line_only_while_telegraphing() -> void:
	var g := _golem(Vector3.ZERO, Vector3(6.0, 0.0, 0.0))
	check_eq(g.hook_escape_dir(Vector3(6.0, 0.0, 0.0)), Vector3.ZERO, "not while it is not aiming")
	_step(g, 0.1)
	var left := g.hook_escape_dir(Vector3(6.0, 0.0, 0.3))
	var right := g.hook_escape_dir(Vector3(6.0, 0.0, -0.3))
	check(left != Vector3.ZERO and right != Vector3.ZERO and left.is_equal_approx(-right), "away from the centre line, either side")
	check(absf(left.dot(Vector3(1.0, 0.0, 0.0))) < 0.001, "sideways to the line")
	check_eq(g.hook_escape_dir(Vector3(6.0, 0.0, 3.0)), Vector3.ZERO, "outside the band")
	check(g.hook_escape_dir(Vector3(6.0, 0.0, 1.2), 0.8) != Vector3.ZERO, "the margin widens the band")
	check_eq(g.hook_escape_dir(Vector3(-3.0, 0.0, 0.0)), Vector3.ZERO, "behind the golem")
	check_eq(g.hook_escape_dir(Vector3(14.0, 0.0, 0.0)), Vector3.ZERO, "beyond the reach")


# --- HookLine / SupportBeam visuals --------------------------------------------------------------

func test_hook_line_band_progress_and_strike() -> void:
	var line := HookLine.create(Vector3(1.0, 0.0, 0.0), 9.5)
	world.add_child(line)
	check_near(line.rotation.y, -PI * 0.5, 0.001, "east: local -Z turned to +X")
	line.set_aim(Vector3(0.0, 0.0, -1.0))
	check_near(line.rotation.y, 0.0, 0.001, "north")
	line.set_progress(0.5)
	check_near(line.progress, 0.5, 0.0001, "progress")
	line.set_progress(3.0)
	check_eq(line.progress, 1.0, "clamped")
	var band := line.get_node(^"Band") as MeshInstance3D
	check(band.visible, "the band shows")
	line.play_strike(5.0)
	check(line.striking and not band.visible, "the chain replaces the band")
	check((line.get_node(^"Chain") as MeshInstance3D).visible, "the chain shows")
	line._process(HookLine.STRIKE_TIME + 0.05)
	check(line.is_queued_for_deletion(), "the strike frees the node")


func test_support_beam_points_from_the_staff_to_the_target() -> void:
	var beam := SupportBeam.create(SupportBeam.SHIELD_COLOR)
	world.add_child(beam)
	beam.set_ends(Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.0, -4.0))
	check(beam.visible, "visible")
	var outer := beam.get_node(^"Outer") as MeshInstance3D
	check_near(outer.transform.basis.y.length(), 4.0, 0.01, "stretched to the span")
	check(outer.transform.origin.is_equal_approx(Vector3(0.0, 1.0, -2.0)), "centred between the ends")
	check((beam.get_node(^"Orb") as MeshInstance3D).position.is_equal_approx(Vector3(0.0, 1.0, -4.0)), "the orb lands on the target")
	beam.set_ends(Vector3(1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0))
	check(not beam.visible, "a zero-length beam is hidden")


# --- EnemyModel styles ---------------------------------------------------------------------------

func test_new_model_styles_build_distinct_readable_meshes() -> void:
	for style in [&"ghoul", &"cultist", &"golem"]:
		check(EnemyModel.STYLES.has(style), "%s is a known style" % style)
	var bodies: Array[Mesh] = []
	for id in [&"plague_ghoul", &"cultist_acolyte", &"flesh_golem"]:
		var data := Db.get_enemy(id)
		var m := EnemyModel.new()
		world.add_child(m)
		m.setup(data)
		check_eq(m.style, data.model_style, "%s keeps its own style" % id)
		var body := m.get_node(^"Pivot/Body") as MeshInstance3D
		var arm := m.get_node(^"Pivot/Arm") as MeshInstance3D
		check(body.mesh != null and body.mesh.get_surface_count() > 0, "%s: a body" % id)
		check(arm.mesh != null and arm.mesh.get_surface_count() > 0, "%s: an arm" % id)
		check(m.head_height > 1.0 * data.model_scale * 0.8, "%s: head height %f" % [id, m.head_height])
		check(not bodies.has(body.mesh), "%s: its own mesh, not the skeleton fallback" % id)
		bodies.append(body.mesh)
		var skeleton := EnemyModel.parts_for(&"skeleton", Color.WHITE)
		check(body.mesh != skeleton["body"], "%s: not the skeleton" % id)
	# The golem is the biggest silhouette.
	var golem_model := EnemyModel.new()
	world.add_child(golem_model)
	golem_model.setup(Db.get_enemy(&"flesh_golem"))
	var skeleton_model := EnemyModel.new()
	world.add_child(skeleton_model)
	skeleton_model.setup(Db.get_enemy(&"skeleton_grunt"))
	check(golem_model.head_height > skeleton_model.head_height * 1.6, "the golem towers over a skeleton")
	var cultist := EnemyModel.new()
	world.add_child(cultist)
	cultist.setup(Db.get_enemy(&"cultist_acolyte"))
	check(cultist.get_node_or_null(^"Pivot/Glow") != null, "the Acolyte's orb glows")
	var ghoul := EnemyModel.new()
	world.add_child(ghoul)
	ghoul.setup(Db.get_enemy(&"plague_ghoul"))
	check(ghoul.get_node_or_null(^"Pivot/Glow") != null, "the ghoul's boil glows")


func test_the_channel_tell_is_violet_and_can_be_cancelled() -> void:
	var m := EnemyModel.new()
	world.add_child(m)
	m.setup(Db.get_enemy(&"cultist_acolyte"))
	var body := m.get_node(^"Pivot/Body") as GeometryInstance3D
	m.play_channel()
	check(m.is_winding_up(), "channelling shows the tell")
	m._process(0.1)
	var tint := _overlay_color(body)
	check(tint.b > tint.g and tint.r > tint.g, "violet, not red: %s" % tint)
	m.cancel_windup()
	check(not m.is_winding_up(), "cancelled")
	m._process(0.1)
	check_near(Mats.overlay_amount(body), 0.0, 0.001, "no tint left")
	m.cancel_windup()
	check(not m.is_winding_up(), "cancelling twice is harmless")
	m.play_windup()
	m._process(0.1)
	var red := _overlay_color(body)
	check(red.r > red.b, "a normal wind-up is red again: %s" % red)


func _overlay_color(node: GeometryInstance3D) -> Color:
	var mat := node.material_override as ShaderMaterial
	var v: Variant = mat.get_shader_parameter(Mats.OVERLAY_PARAM) if mat != null else null
	return v if v is Color else Color(0.0, 0.0, 0.0, 0.0)
