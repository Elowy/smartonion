extends "res://tests/shaman_base.gd"
## Shaman lightning and earth abilities (M8, design_shaman.md §2): Forking Bolt (chain, falloff, ranks, specs, the
## Rebounding Arc / set hooks), Thunderbolt, Stormburst and Rumbling Earth – what each deals through which source,
## what Ranks II-V and the Rank V specs change, Storm Echo eligibility, the Elemental Surge charge and the bot rules.

## Intellect 10 and Spell Power 4: a Rank I Forking Bolt hits for 7 + 10 + 4 x 1.5 = 23.
func _stats(p: Player, mastery: float = 0.0) -> void:
	p.stats.set_source(&"test", {Stats.INTELLECT: 10.0, Stats.SPELL_POWER: 4.0, Stats.MASTERY: mastery})


## A row of enemies along +X, [param gap] apart, the first [param first] m from the origin.
func _row(count: int, first: float, gap: float) -> Array[Mortal]:
	var out: Array[Mortal] = []
	for i in count:
		out.append(_enemy(Vector3(first + gap * float(i), 0, 0)))
	return out


# --- Forking Bolt -------------------------------------------------------------------------------------

func test_forking_bolt_forks_through_the_chain_with_falloff() -> void:
	var p := _shaman()
	_stats(p)
	var row := _row(5, 3.0, 3.0)
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "the bolt is cast")
	var expected := [23.0, 19.55, 16.6175, 14.124875]
	for i in 4:
		check_eq(row[i].fake_damage_log.size(), 1, "enemy %d is struck once" % i)
		if not row[i].fake_damage_log.is_empty():
			check_near(row[i].fake_damage_log[0], expected[i], 0.001, "jump %d: 15%% less than the one before" % i)
			check(row[i].fake_attacker_log[0] == p, "the Shaman is the attacker")
	check(row[4].fake_damage_log.is_empty(), "four enemies in all")
	check_near(_surge(p).value, 75.0, 0.0001, "30 Surge paid, 5 gained")
	check_near(RunState.damage_by_player.get(0, 0.0), 23.0 + 19.55 + 16.6175 + 14.124875, 0.001, "all of it is the Shaman's damage")


func test_forking_bolt_ends_when_no_enemy_is_in_jump_range() -> void:
	var p := _shaman()
	_stats(p)
	var near := _enemy(Vector3(3, 0, 0))
	var far := _enemy(Vector3(3.0 + 5.5, 0, 0))
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast")
	check_eq(near.fake_damage_log.size(), 1, "the first is struck")
	check(far.fake_damage_log.is_empty(), "5.5 m is out of the 5 m jump range")


func test_forking_bolt_never_strikes_an_enemy_twice_and_needs_a_target() -> void:
	var p := _shaman()
	_stats(p)
	var pair := _row(2, 3.0, 1.0)
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast")
	check_eq(pair[0].fake_damage_log.size(), 1, "once")
	check_eq(pair[1].fake_damage_log.size(), 1, "once")
	var q := _shaman(Vector3(40, 0, 0), 1)
	_full_surge(q)
	check(not _cast(q, &"forking_bolt"), "no enemy within 9 m: no cast")
	check_eq(_surge(q).value, 100.0, "nothing is paid")


func test_forking_bolt_range_is_nine_metres() -> void:
	var p := _shaman()
	_stats(p)
	var e := _enemy(Vector3(9.5, 0, 0))
	_full_surge(p)
	check(not _cast(p, &"forking_bolt"), "9.5 m is out of range")
	e.global_position = Vector3(8.5, 0, 0)
	EnemyGrid.mark_dirty()
	check(_cast(p, &"forking_bolt"), "8.5 m is in range")


func test_forking_bolt_rank_iii_and_the_set_bonus_add_enemies() -> void:
	var p := _shaman()
	_stats(p)
	var row := _row(8, 3.0, 2.0)
	_learn(p, &"forking_bolt", 3)
	check_eq(int(p.abilities.params_for(Db.get_ability(&"forking_bolt"))["targets"]), 5, "Rank III: 5 targets")
	_put(p, [{"kind": "ability", "match": {"id": "forking_bolt"}, "mods": {"targets_add": 2.0}, "rank": 1}])
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast")
	var struck := 0
	for e in row:
		struck += e.fake_damage_log.size()
	check_eq(struck, 7, "Rank III (5) + the 4-piece set bonus (+2)")
	# Rank III is also Rank II: +25% damage.
	check_near(row[0].fake_damage_log[0], 23.0 * 1.25, 0.001, "Rank II power")


func test_forking_bolt_thunder_web_loses_no_damage_and_forks_further() -> void:
	var p := _shaman()
	_stats(p)
	var row := _row(8, 3.0, 2.0)
	_learn(p, &"forking_bolt", 5, 0)
	var params := p.abilities.params_for(Db.get_ability(&"forking_bolt"))
	check_eq(float(params["falloff_pct"]), 0.0, "no falloff")
	check_eq(int(params["targets"]), 6, "Rank III +1 and Thunder Web +1")
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast")
	var struck := 0
	for e in row:
		struck += e.fake_damage_log.size()
		if not e.fake_damage_log.is_empty():
			check_near(e.fake_damage_log[0], 23.0 * 1.5, 0.001, "every jump hits for the full Rank IV amount")
	check_eq(struck, 6, "six enemies")


func test_forking_bolt_static_cling_stuns_every_enemy_struck() -> void:
	var p := _shaman()
	_stats(p)
	var row := _row(3, 3.0, 2.0)
	_learn(p, &"forking_bolt", 5, 1)
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast")
	for e in row:
		check_eq(e.stuns, [0.6] as Array[float], "stunned for 0.6 s")


func test_forking_bolt_rebounding_arc_strikes_the_first_enemy_again() -> void:
	var p := _shaman()
	_stats(p)
	var row := _row(3, 3.0, 2.0)
	_put(p, [{"kind": "ability", "match": {"id": "forking_bolt"}, "mods": {"return_pct_add": 60.0}, "rank": 1}])
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast")
	check_eq(row[0].fake_damage_log.size(), 2, "the first enemy is hit again after the last jump")
	check_near(row[0].fake_damage_log[1], 23.0 * 0.6, 0.001, "for 60% of the first hit")
	check_eq(row[1].fake_damage_log.size(), 1, "the others once")
	check_eq(row[2].fake_damage_log.size(), 1, "once")
	# A single enemy has nothing to rebound from.
	var q := _shaman(Vector3(0, 0, 30), 1)
	_stats(q)
	_put(q, [{"kind": "ability", "match": {"id": "forking_bolt"}, "mods": {"return_pct_add": 60.0}, "rank": 1}])
	var lone := _enemy(Vector3(3, 0, 30))
	_full_surge(q)
	check(_cast(q, &"forking_bolt"), "cast at the lone enemy")
	check_eq(lone.fake_damage_log.size(), 1, "no rebound without a jump")


func test_forking_bolt_remembers_where_it_struck_for_the_artifact() -> void:
	var p := _shaman()
	_stats(p)
	var row := _row(2, 3.0, 2.0)
	_full_surge(p)
	grant_one(p)
	check(_cast(p, &"forking_bolt"), "cast")
	var f := ShamanKit.last_fork(p)
	check_eq(f["point"], row[0].global_position, "where it first struck")
	check_near(float(f["damage"]), 23.0 * 2.0, 0.001, "the first hit's amount, Elemental Surge baked in")


## One empowered cast: +100%.
func grant_one(p: Player) -> void:
	_mastery(p).grant_empower(1, 100.0)


func test_a_lightning_talent_matches_the_three_lightning_abilities() -> void:
	var p := _shaman()
	_stats(p)
	var e := _enemy(Vector3(3, 0, 0))
	_put(p, [{"kind": "ability", "match": {"tag": "lightning"}, "mods": {"power_pct": 10.0}, "rank": 1}])
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast")
	check_near(e.fake_damage_log[0], 23.0 * 1.1, 0.001, "+10% Forking Bolt")
	_learn(p, &"thunderbolt")
	check_near(float(p.abilities.params_for(Db.get_ability(&"thunderbolt"))["power"]), 1.1, 0.0001, "+10% Thunderbolt")
	_learn(p, &"stormburst")
	check_near(float(p.abilities.params_for(Db.get_ability(&"stormburst"))["power"]), 1.1, 0.0001, "+10% Stormburst")
	_learn(p, &"magma_lash")
	check_near(float(p.abilities.params_for(Db.get_ability(&"magma_lash"))["power"]), 1.0, 0.0001, "Magma Lash is no lightning")


func test_every_lightning_hit_can_echo_and_totem_or_dot_damage_cannot() -> void:
	var p := _shaman()
	_stats(p, 5.0)
	_put(p, [{"kind": "ability", "match": {"id": "shaman_echo"}, "mods": {"max_chance_add": 40.0, "chance_per_mastery_add": 100.0}, "rank": 1}])
	var row := _row(3, 3.0, 2.0)
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast")
	for e in row:
		check_eq(e.fake_damage_log.size(), 2, "every jump echoes")
	check_eq(_mastery(p).echoes, 3, "three echoes")
	check_near(row[0].fake_damage_log[1], row[0].fake_damage_log[0] * 0.5, 0.001, "for half the hit")
	var before := _mastery(p).echoes
	var totem := ShamanTotem.plant(p, &"fire", Db.get_ability(&"totem_rite").params, Vector3(0, 0, 0), 5.0)
	_step_totem(totem, 0.4)
	check(totem.shots >= 1, "the Fire totem fired")
	check_eq(_mastery(p).echoes, before, "a Fire totem bolt never echoes")


func _step_totem(t: ShamanTotem, seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds - 0.00001:
		t.step(DT)
		elapsed += DT


func test_forking_bolt_takes_one_elemental_surge_charge_and_bakes_it_into_every_jump() -> void:
	var p := _shaman()
	_stats(p)
	var row := _row(2, 3.0, 2.0)
	_mastery(p).grant_empower(3, 100.0)
	_full_surge(p)
	check(_cast(p, &"forking_bolt"), "cast")
	check_eq(_mastery(p).empower_charges, 2, "one charge")
	check_near(row[0].fake_damage_log[0], 46.0, 0.001, "the first jump doubled")
	check_near(row[1].fake_damage_log[0], 46.0 * 0.85, 0.001, "and the second")


func test_forking_bolt_is_cast_by_bots_whenever_surge_allows() -> void:
	var p := _shaman()
	p.abilities.auto_cast = true
	_stats(p)
	var e := _enemy(Vector3(4, 0, 0))
	p.abilities.set_cooldown(Db.get_ability(&"totem_rite"), 999.0)  # the bot would plant a totem that shoots too
	check(_effect(p, &"forking_bolt").wants_auto_cast(_ctx(p, &"forking_bolt")), "an enemy in range: yes")
	_surge(p).set_value(0.0)
	_run(p, 0.5)
	check(e.fake_damage_log.is_empty(), "no Surge, no bolt")
	_surge(p).set_value(60.0)
	_run(p, 0.6)
	check(not e.fake_damage_log.is_empty(), "with Surge the bot casts")


# --- Thunderbolt -----------------------------------------------------------------------------------------

func test_thunderbolt_strikes_the_nearest_enemy() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"thunderbolt")
	var near := _enemy(Vector3(4, 0, 0))
	var far := _enemy(Vector3(8, 0, 0))
	check(_cast(p, &"thunderbolt"), "cast")
	check_near(near.fake_damage_log[0], 14.0 + 20.0 + 10.0, 0.001, "14 + 2 Int + 2.5 SP")
	check(far.fake_damage_log.is_empty(), "one bolt, one enemy")
	check(near.fake_attacker_log[0] == p, "the Shaman's damage")
	check_eq(Db.get_ability(&"thunderbolt").school, &"nature", "Nature")
	check(not _cast(p, &"thunderbolt"), "5 s cooldown")


func test_thunderbolt_rank_iii_adds_a_bolt_at_the_next_nearest_enemy() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"thunderbolt", 3)
	var row := _row(3, 3.0, 2.0)
	check(_cast(p, &"thunderbolt"), "cast")
	check_eq(row[0].fake_damage_log.size(), 1, "nearest")
	check_eq(row[1].fake_damage_log.size(), 1, "next-nearest")
	check(row[2].fake_damage_log.is_empty(), "two bolts only")
	check_near(row[0].fake_damage_log[0], 44.0 * 1.25, 0.001, "Rank II power")
	var lone := _shaman(Vector3(0, 0, 30), 1)
	_stats(lone)
	_learn(lone, &"thunderbolt", 3)
	var single := _enemy(Vector3(3, 0, 30))
	check(_cast(lone, &"thunderbolt"), "cast")
	check_eq(single.fake_damage_log.size(), 2, "one enemy takes both bolts")


func test_thunderbolt_sundering_bolt_blasts_the_neighbours_for_half() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"thunderbolt", 5, 0)
	var target := _enemy(Vector3(4, 0, 0))
	var next := _enemy(Vector3(6, 0, 0))
	var far := _enemy(Vector3(9, 0, 0))
	check(_cast(p, &"thunderbolt"), "cast")
	var bolt := 44.0 * 1.5
	# Rank V has two bolts (Rank III): one on each of the two nearest enemies; each blasts the other for half.
	check_eq(target.fake_damage_log.size(), 2, "the target: its own bolt and the blast of the second one")
	check_near(target.fake_damage_log[0], bolt, 0.001, "the target takes the bolt")
	check_near(target.fake_damage_log[1], bolt * 0.5, 0.001, "2 m away from the second bolt: half")
	check_near(next.fake_damage_log[0], bolt * 0.5, 0.001, "the first bolt's blast reaches the second enemy")
	check_near(next.fake_damage_log[1], bolt, 0.001, "and its own bolt")
	check(far.fake_damage_log.is_empty(), "3 m from the second bolt: out of the 2.5 m blast")
	var q := _shaman(Vector3(0, 0, 40), 1)
	_stats(q)
	_learn(q, &"thunderbolt", 5, 0)
	var lone := _enemy(Vector3(4, 0, 40))
	var beside := _enemy(Vector3(4, 0, 42))
	check(_cast(q, &"thunderbolt"), "cast")
	check_eq(lone.fake_damage_log.size(), 2, "two bolts: the lone enemy and its neighbour, splashing each other")
	check_near(beside.fake_damage_log[0] + beside.fake_damage_log[1], bolt * 1.5, 0.001, "bolt + blast")


func test_thunderbolt_staggering_bolt_stuns_the_target() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"thunderbolt", 5, 1)
	var e := _enemy(Vector3(4, 0, 0))
	var f := _enemy(Vector3(9, 0, 0))
	check(_cast(p, &"thunderbolt"), "cast")
	check_eq(e.stuns, [1.2] as Array[float], "stunned for 1.2 s")
	check_eq(f.stuns, [1.2] as Array[float], "the Rank III bolt stuns the second enemy as well")


func test_thunderbolt_range_echo_and_empower() -> void:
	var p := _shaman()
	_stats(p, 5.0)
	_learn(p, &"thunderbolt")
	_put(p, [{"kind": "ability", "match": {"id": "shaman_echo"}, "mods": {"max_chance_add": 40.0, "chance_per_mastery_add": 100.0}, "rank": 1}])
	var out := _enemy(Vector3(10.5, 0, 0))
	check(not _cast(p, &"thunderbolt"), "10.5 m is out of range")
	out.global_position = Vector3(9.5, 0, 0)
	EnemyGrid.mark_dirty()
	_mastery(p).grant_empower(1, 100.0)
	check(_cast(p, &"thunderbolt"), "9.5 m is in range")
	check_near(out.fake_damage_log[0], 88.0, 0.001, "Elemental Surge doubles it")
	check_eq(out.fake_damage_log.size(), 2, "and it echoes")
	check_near(out.fake_damage_log[1], 44.0, 0.001, "for half the (empowered) hit")
	check_eq(_mastery(p).empower_charges, 0, "one charge")


# --- Stormburst ------------------------------------------------------------------------------------------

func test_stormburst_hits_every_enemy_in_the_burst_and_throws_it_back() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"stormburst")
	var crowd := _cluster(Vector3.ZERO, 3, 2.0)
	var outside := _enemy(Vector3(6, 0, 0))
	check(_cast(p, &"stormburst"), "cast with a crowd")
	for e in crowd:
		check_near(e.fake_damage_log[0], 5.0 + 6.0 + 4.0, 0.001, "5 + 0.6 Int + 1 SP")
		check(e.knockback_velocity.length() > 10.0, "thrown back (%s)" % e.knockback_velocity)
		var away := Vector3(e.global_position.x, 0, e.global_position.z).normalized()
		check(e.knockback_velocity.normalized().dot(away) > 0.99, "away from the Shaman")
	check(outside.fake_damage_log.is_empty(), "6 m away: untouched")
	check(outside.knockback_velocity == Vector3.ZERO, "and not pushed")


func test_stormburst_needs_a_crowd_or_low_health_for_the_bot() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"stormburst")
	var a := _enemy(Vector3(1.5, 0, 0))
	var b := _enemy(Vector3(-1.5, 0, 0))
	var fx := _effect(p, &"stormburst")
	check(not fx.wants_auto_cast(_ctx(p, &"stormburst")), "two enemies are no crowd")
	var c := _enemy(Vector3(0, 0, 1.5))
	check(fx.wants_auto_cast(_ctx(p, &"stormburst")), "three are")
	c.global_position = Vector3(0, 0, 9.0)
	EnemyGrid.mark_dirty()
	p.hp = p.max_hp() * 0.3
	check(fx.wants_auto_cast(_ctx(p, &"stormburst")), "two enemies while the HP is below 40%")
	p.hp = p.max_hp()
	b.global_position = Vector3(0, 0, 12.0)
	a.global_position = Vector3(0, 0, 12.0)
	EnemyGrid.mark_dirty()
	check(not fx.can_cast(_ctx(p, &"stormburst")), "nobody in the burst: no cast")
	check(not _cast(p, &"stormburst"), "an empty burst is refused")


func test_stormburst_belt_item_lowers_the_crowd_size() -> void:
	var p := _shaman()
	_learn(p, &"stormburst")
	_enemy(Vector3(1.5, 0, 0))
	_enemy(Vector3(-1.5, 0, 0))
	_put(p, [{"kind": "ability", "match": {"id": "stormburst"}, "mods": {"min_enemies_add": -1.0}, "rank": 1}])
	check(_effect(p, &"stormburst").wants_auto_cast(_ctx(p, &"stormburst")), "two enemies are enough now")


func test_stormburst_rank_iii_widens_and_the_specs_pulse_or_stun() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"stormburst", 3)
	var e := _enemy(Vector3(4.2, 0, 0))
	_enemy(Vector3(1, 0, 0))
	check(_cast(p, &"stormburst"), "cast")
	check_eq(e.fake_damage_log.size(), 1, "4.2 m is inside the 4.5 m radius of Rank III")
	var q := _shaman(Vector3(0, 0, 40), 1)
	_stats(q)
	_learn(q, &"stormburst", 5, 0)
	var foes := _cluster(Vector3(0, 0, 40), 3, 1.5)
	check(_cast(q, &"stormburst"), "Echoing Discharge: first pulse")
	check_eq(foes[0].fake_damage_log.size(), 1, "one pulse at once")
	_run(q, 0.7)
	check_eq(foes[0].fake_damage_log.size(), 1, "the second pulse is 0.8 s later")
	_run(q, 0.2)
	check_eq(foes[0].fake_damage_log.size(), 2, "now")
	check_near(foes[0].fake_damage_log[1], foes[0].fake_damage_log[0], 0.001, "the same damage")
	var r := _shaman(Vector3(0, 0, 80), 2)
	_stats(r)
	_learn(r, &"stormburst", 5, 1)
	var stunned := _cluster(Vector3(0, 0, 80), 3, 1.5)
	check(_cast(r, &"stormburst"), "Crackling Field")
	for s in stunned:
		check_eq(s.stuns, [1.0] as Array[float], "stunned for 1 s")


func test_stormburst_takes_one_charge_and_both_pulses_carry_it() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"stormburst", 5, 0)
	var foes := _cluster(Vector3.ZERO, 3, 1.5)
	_mastery(p).grant_empower(2, 100.0)
	check(_cast(p, &"stormburst"), "cast")
	check_eq(_mastery(p).empower_charges, 1, "one charge for both pulses")
	_run(p, 1.0)
	check_eq(foes[0].fake_damage_log.size(), 2, "two pulses")
	check_near(foes[0].fake_damage_log[0], 15.0 * 1.5 * 2.0, 0.001, "15 x Rank IV power x the empower")
	check_near(foes[0].fake_damage_log[1], foes[0].fake_damage_log[0], 0.001, "the second pulse carries it too")


# --- Rumbling Earth --------------------------------------------------------------------------------------

func test_rumbling_earth_opens_under_the_densest_group() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"rumbling_earth")
	var big := _cluster(Vector3(8, 0, 0), 5, 1.0)
	var small := _cluster(Vector3(-6, 0, 0), 2, 1.0)
	check(_cast(p, &"rumbling_earth"), "cast")
	var areas := _fx_quake(p).running()
	check_eq(areas.size(), 1, "one quake")
	check(_flat_dist(areas[0], big[0]) < 1.6, "under the five enemies")
	check_near(areas[0].radius, 4.0, 0.0001, "4 m")
	check_near(areas[0].duration, 5.0, 0.0001, "5 s")
	_run(p, 5.2)
	for e in big:
		check(e.fake_damage_log.size() >= 9 and e.fake_damage_log.size() <= 11, "about ten ticks (%d)" % e.fake_damage_log.size())
		check_near(e.fake_damage_log[0], 2.5 + 4.0 + 0.6 * 4.0 * 0.5, 0.001, "2.5 + 0.4 Int + 0.6 SP per tick")
		check(e.fake_attacker_log[0] == p, "the Shaman's damage")
	for e in small:
		check(e.fake_damage_log.is_empty(), "the small group is outside the circle")


func test_rumbling_earth_rolls_the_stun_once_per_enemy_on_its_first_tick() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"rumbling_earth")
	var foes := _cluster(Vector3(5, 0, 0), 4, 1.0)
	var shadow := RandomNumberGenerator.new()
	shadow.seed = RunState.rng.seed
	shadow.state = RunState.rng.state
	check(_cast(p, &"rumbling_earth"), "cast")
	check_eq(RunState.rng.state, shadow.state, "casting itself draws nothing")
	_run(p, 0.05)
	for i in 4:
		shadow.randf()
	check_eq(RunState.rng.state, shadow.state, "one draw per enemy on the first tick")
	_run(p, 3.0)
	check_eq(RunState.rng.state, shadow.state, "and none after that")
	check(foes.size() == 4, "four enemies")


func test_rumbling_earth_stuns_with_the_chance_for_the_duration() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"rumbling_earth")
	_put(p, [{"kind": "ability", "match": {"id": "rumbling_earth"}, "mods": {"stun_chance_add": 75.0}, "rank": 1}])
	var foes := _cluster(Vector3(5, 0, 0), 3, 1.0)
	check(_cast(p, &"rumbling_earth"), "cast")
	_run(p, 2.0)
	for e in foes:
		check_eq(e.stuns, [1.2] as Array[float], "a sure stun, once, for 1.2 s")


func test_rumbling_earth_without_a_stun_chance_draws_nothing() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"rumbling_earth")
	_put(p, [{"kind": "ability", "match": {"id": "rumbling_earth"}, "mods": {"stun_chance": 0.0}, "rank": 1}])
	_cluster(Vector3(5, 0, 0), 3, 1.0)
	var before := RunState.rng.state
	check(_cast(p, &"rumbling_earth"), "cast")
	_run(p, 1.0)
	check_eq(RunState.rng.state, before, "no chance, no draw")


func test_rumbling_earth_rank_iii_radius_and_area_size() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"rumbling_earth", 3)
	_cluster(Vector3(5, 0, 0), 4, 1.0)
	check(_cast(p, &"rumbling_earth"), "cast")
	check_near(_fx_quake(p).running()[0].radius, 5.0, 0.0001, "Rank III: 5 m")
	var q := _shaman(Vector3(0, 0, 40), 1)
	_stats(q)
	q.stats.set_source(&"area", {Stats.AREA_SIZE: 50.0})
	_learn(q, &"rumbling_earth")
	_cluster(Vector3(5, 0, 40), 4, 1.0)
	check(_cast(q, &"rumbling_earth"), "cast with Area Size")
	check_near(_fx_quake(q).running()[0].radius, 6.0, 0.0001, "+50% Area Size")


func test_rumbling_earth_faultline_slows_everything_inside() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"rumbling_earth", 5, 0)
	var foes := _cluster(Vector3(5, 0, 0), 3, 1.0)
	check(_cast(p, &"rumbling_earth"), "cast")
	_run(p, 0.6)
	for e in foes:
		check(not e.slows.is_empty() and e.slows[0] == 50.0, "slowed by 50%")


func test_rumbling_earth_twin_fissures_open_a_second_quake_under_the_next_group() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"rumbling_earth", 5, 1)
	var big := _cluster(Vector3(8, 0, 0), 5, 1.0)
	var next := _cluster(Vector3(-5, 0, 3), 3, 1.0)
	check(_cast(p, &"rumbling_earth"), "cast")
	var areas := _fx_quake(p).running()
	check_eq(areas.size(), 2, "two quakes")
	check(_flat_dist(areas[0], big[0]) < 1.6, "the first under the big group")
	check(_flat_dist(areas[1], next[0]) < 1.6, "the second under the next-densest one")
	# With only one group the second quake has nothing to open under.
	var q := _shaman(Vector3(0, 0, 50), 1)
	_stats(q)
	_learn(q, &"rumbling_earth", 5, 1)
	_cluster(Vector3(5, 0, 50), 4, 0.8)
	check(_cast(q, &"rumbling_earth"), "cast")
	check_eq(_fx_quake(q).running().size(), 1, "one group, one quake")


func test_rumbling_earth_takes_one_charge_and_quake_ticks_never_echo() -> void:
	var p := _shaman()
	_stats(p, 5.0)
	_learn(p, &"rumbling_earth", 5, 1)
	_put(p, [{"kind": "ability", "match": {"id": "shaman_echo"}, "mods": {"max_chance_add": 40.0, "chance_per_mastery_add": 100.0}, "rank": 1}])
	var big := _cluster(Vector3(8, 0, 0), 4, 1.0)
	_cluster(Vector3(-5, 0, 3), 3, 1.0)
	_mastery(p).grant_empower(3, 100.0)
	check(_cast(p, &"rumbling_earth"), "cast")
	check_eq(_mastery(p).empower_charges, 2, "one charge for both quakes")
	_run(p, 1.0)
	check_near(big[0].fake_damage_log[0], (2.5 + 4.0 + 0.6 * 4.0 * 0.5) * 1.5 * 2.0, 0.001, "Rank IV power and the empower")
	check_eq(_mastery(p).echoes, 0, "quake ticks are not eligible for Storm Echo")


func test_rumbling_earth_bot_rule_needs_a_cluster_and_no_overlapping_quake() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"rumbling_earth")
	var fx := _fx_quake(p)
	_cluster(Vector3(6, 0, 0), 3, 1.0)
	check(not fx.wants_auto_cast(_ctx(p, &"rumbling_earth")), "three enemies are too few")
	_enemy(Vector3(6, 0, 1.2))
	check(fx.wants_auto_cast(_ctx(p, &"rumbling_earth")), "four are enough")
	check(_cast(p, &"rumbling_earth"), "cast")
	p.abilities.set_cooldown(Db.get_ability(&"rumbling_earth"), 0.0)
	check(not fx.wants_auto_cast(_ctx(p, &"rumbling_earth")), "the quake already covers the circle")
	_run(p, 6.0)
	check(fx.wants_auto_cast(_ctx(p, &"rumbling_earth")), "the quake is over: again")
