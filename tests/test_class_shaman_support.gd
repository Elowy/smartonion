extends "res://tests/shaman_base.gd"
## Shaman melee, healing and pet abilities (M8, design_shaman.md §2): Magma Lash (weapon strike, burn, spread, Twin Lashes,
## Molten Trail), Soothing Downpour (the most wounded hero, heals, Following Rain, Thundercloud, Twin Squalls) and Spirit
## Pack (the wolves, bites, Surge, Thunder Pack, Pack Guardians) – damage / heal sources, ranks and specs, Storm Echo
## eligibility, the Elemental Surge charge, cleanup and the bot rules.

## Intellect 10 and Spell Power 4: a Rank I Magma Lash hits for (7 + 0.4 x 10) x 150% + 4 x 0.5 = 18.5.
func _stats(p: Player, mastery: float = 0.0) -> void:
	p.stats.set_source(&"test", {Stats.INTELLECT: 10.0, Stats.SPELL_POWER: 4.0, Stats.MASTERY: mastery})


const LASH := 18.5


## The burn of [param p] on [param e] (null = none).
func _burn(p: Player, e: Enemy) -> ShamanBurn:
	return ShamanBurn.find(e, p)


## A sure echo (100%) for the test.
func _echoing(p: Player) -> void:
	_stats(p, 5.0)
	_put(p, [{"kind": "ability", "match": {"id": "shaman_echo"}, "mods": {"max_chance_add": 40.0, "chance_per_mastery_add": 100.0}, "rank": 1}])


# --- Magma Lash ---------------------------------------------------------------------------------------------

func test_magma_lash_strikes_with_the_weapon_and_sets_the_enemy_burning() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"magma_lash")
	var e := _enemy(Vector3(2, 0, 0))
	check(_cast(p, &"magma_lash"), "cast")
	check_eq(e.fake_damage_log.size(), 1, "the lash")
	check_near(e.fake_damage_log[0], LASH, 0.001, "150% of the 11 damage mace hit + 0.5 SP")
	check(e.fake_attacker_log[0] == p, "the Shaman's damage")
	var burn := _burn(p, e)
	check(burn != null, "burning")
	check_near(burn.remaining(), LASH * 0.4, 0.001, "40% more over the burn")
	_run(p, 4.6)
	check_near(e.total(), LASH * 1.4, 0.01, "the lash and the whole burn")
	check(_burn(p, e) == null, "the burn ran out")
	check(not _cast(p, &"magma_lash"), "the 6 s cooldown is still running")


func test_the_lash_is_ability_damage_and_the_burn_is_dot_damage() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"magma_lash")
	_boost(p, "dot")
	var e := _enemy(Vector3(2, 0, 0))
	check(_cast(p, &"magma_lash"), "cast")
	_run(p, 4.6)
	check_near(e.total(), LASH + LASH * 0.4 * 2.0, 0.01, "only the burn is doubled by +100% DoT damage")
	var q := _shaman(Vector3(0, 0, 40), 1)
	_stats(q)
	_learn(q, &"magma_lash")
	_boost(q, "ability")
	var f := _enemy(Vector3(2, 0, 40))
	check(_cast(q, &"magma_lash"), "cast")
	_run(q, 4.6)
	check_near(f.total(), LASH * 2.0 + LASH * 0.4, 0.01, "only the lash is doubled by +100% ability damage")


func test_the_lash_needs_an_enemy_in_melee_range() -> void:
	var p := _shaman()
	_learn(p, &"magma_lash")
	var e := _enemy(Vector3(3.2, 0, 0))
	check(not _cast(p, &"magma_lash"), "3.2 m is out of the 2.8 m reach")
	e.global_position = Vector3(2.5, 0, 0)
	EnemyGrid.mark_dirty()
	check(_cast(p, &"magma_lash"), "2.5 m is in reach")


## A host with neighbours: [host, n1 (2 m away), n2 (2.5 m), n3 (2.9 m), far (4.8 m: out of reach of the host)].
func _flock() -> Array[Mortal]:
	return [_enemy(Vector3(2, 0, 0)), _enemy(Vector3(2, 0, 2.0)), _enemy(Vector3(2, 0, -2.5)),
		_enemy(Vector3(2, 0, 2.9)), _enemy(Vector3(2, 0, 4.8))]


func test_the_burn_spreads_to_two_enemies_when_it_ends() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"magma_lash")
	var f := _flock()
	check(_cast(p, &"magma_lash"), "cast")
	_run(p, 3.9)
	check(_burn(p, f[1]) == null and _burn(p, f[2]) == null, "nothing spreads while it burns")
	_run(p, 0.3)
	check(_burn(p, f[1]) != null, "the nearest neighbour burns")
	check(_burn(p, f[2]) != null, "and the next one")
	check(_burn(p, f[3]) == null, "only two enemies (the third is 2.9 m away)")
	check(_burn(p, f[4]) == null, "4.8 m away: out of reach")
	check_near(_burn(p, f[1]).total, LASH * 0.4 * 0.5, 0.001, "at half the strength")
	_run(p, 6.0)
	check_near(f[1].total(), LASH * 0.4 * 0.5, 0.01, "the spread burn dealt its half")
	check(f[3].fake_damage_log.is_empty() and f[4].fake_damage_log.is_empty(), "a spread burn never spreads again")
	check(_burn(p, f[3]) == null and _burn(p, f[4]) == null, "no burn on the others")


func test_the_burn_spreads_when_its_host_dies() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"magma_lash")
	var f := _flock()
	check(_cast(p, &"magma_lash"), "cast")
	f[0].hp = 0.0
	f[0].fake_dead = true
	f[0].died.emit(f[0], 0)
	check(_burn(p, f[1]) != null and _burn(p, f[2]) != null, "the neighbours catch fire at once")
	check(_burn(p, f[3]) == null, "two of them")


func test_rank_iii_spreads_to_one_more_enemy_and_contagious_flame_to_four_more() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"magma_lash", 3)
	var f := _flock()
	check(_cast(p, &"magma_lash"), "cast")
	f[0].fake_dead = true
	f[0].hp = 0.0
	f[0].died.emit(f[0], 0)
	check(_burn(p, f[1]) != null and _burn(p, f[2]) != null and _burn(p, f[3]) != null, "three enemies (Rank III)")
	check(_burn(p, f[4]) == null, "the fourth is out of reach")
	var q := _shaman(Vector3(0, 0, 40), 1)
	_stats(q)
	_learn(q, &"magma_lash", 5, 0)
	var g: Array[Mortal] = []
	for z in [0.0, 1.0, 2.0, -1.0, -2.0, 1.5]:
		g.append(_enemy(Vector3(2, 0, 40.0 + z)))
	var host := _enemy(Vector3(1.5, 0, 40))
	check(_cast(q, &"magma_lash"), "cast")
	host.fake_dead = true
	host.hp = 0.0
	host.died.emit(host, 0)
	var lit := 0
	for e in g:
		if _burn(q, e) != null:
			lit += 1
	check_eq(lit, 6, "Rank III (3) + Contagious Flame (3 more): six enemies")
	var burn := _burn(q, g[0])
	check_near(burn.total, LASH * 1.5 * 0.4, 0.001, "at full strength: 40% of the Rank IV lash")


func test_twin_lashes_strike_again_after_the_delay() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"magma_lash", 5, 1)
	var e := _enemy(Vector3(2, 0, 0))
	check(_cast(p, &"magma_lash"), "cast")
	var lash := LASH * 1.5
	_run(p, 0.3)
	check_eq(e.fake_damage_log.size(), 1, "one lash at first")
	_run(p, 0.2)
	var lashes := 0
	for v in e.fake_damage_log:
		if absf(v - lash) < 0.01:
			lashes += 1
	check_eq(lashes, 2, "the second lash 0.4 s later")


func test_molten_trail_leaves_burning_ground() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"magma_lash")
	_put(p, [{"kind": "ability", "match": {"id": "magma_lash"}, "mods": {"ground_duration_add": 3.0, "ground_pct_add": 15.0}, "rank": 1}])
	var e := _enemy(Vector3(2, 0, 0))
	check(_cast(p, &"magma_lash"), "cast")
	var area: AbilityArea = null
	for child in world.get_children():
		if child is AbilityArea:
			area = child
	check(area != null, "a patch of molten ground")
	check_near(area.damage_per_tick, LASH * 0.15, 0.001, "15% of the lash per tick")
	check_near(area.duration, 3.0, 0.0001, "for 3 s")
	check_eq(area.school, &"fire", "Fire")
	_run(p, 1.2)
	check(e.fake_damage_log.size() >= 3, "the ground burns it as well (%d hits)" % e.fake_damage_log.size())


func test_the_lash_can_echo_but_the_burn_cannot() -> void:
	var p := _shaman()
	_echoing(p)
	_learn(p, &"magma_lash")
	var e := _enemy(Vector3(2, 0, 0))
	check(_cast(p, &"magma_lash"), "cast")
	check_eq(e.fake_damage_log.size(), 2, "the lash and its echo")
	check_near(e.fake_damage_log[1], e.fake_damage_log[0] * 0.5, 0.001, "half of it")
	_run(p, 4.6)
	check_eq(_mastery(p).echoes, 1, "the burn ticks added no echoes")


func test_magma_lash_takes_one_charge_and_bakes_it_into_hit_and_burn() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"magma_lash")
	var e := _enemy(Vector3(2, 0, 0))
	_mastery(p).grant_empower(2, 100.0)
	check(_cast(p, &"magma_lash"), "cast")
	check_eq(_mastery(p).empower_charges, 1, "one charge")
	check_near(e.fake_damage_log[0], LASH * 2.0, 0.001, "the lash doubled")
	check_near(_burn(p, e).total, LASH * 2.0 * 0.4, 0.001, "and its burn")


func test_the_bot_lashes_only_enemies_that_do_not_burn_yet() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"magma_lash")
	var fx := _fx_lash(p)
	check(not fx.wants_auto_cast(_ctx(p, &"magma_lash")), "nobody near")
	var a := _enemy(Vector3(2, 0, 0))
	check(fx.wants_auto_cast(_ctx(p, &"magma_lash")), "an enemy in melee that does not burn")
	check(_cast(p, &"magma_lash"), "cast")
	p.abilities.set_cooldown(Db.get_ability(&"magma_lash"), 0.0)
	check(not fx.wants_auto_cast(_ctx(p, &"magma_lash")), "it burns now: wait")
	var b := _enemy(Vector3(-2, 0, 0))
	check(fx.wants_auto_cast(_ctx(p, &"magma_lash")), "a second enemy that does not")
	check(_cast(p, &"magma_lash"), "the next lash picks the unburnt one")
	check(not b.fake_damage_log.is_empty(), "it was the second enemy")
	check_eq(a.fake_damage_log.size(), 1, "the burning one was left alone")


# --- Soothing Downpour -------------------------------------------------------------------------------------

func test_the_rain_falls_on_the_most_wounded_hero_and_heals_everyone_inside() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"soothing_downpour")
	var hurt := _ally(1, Vector3(3, 0, 0))
	var hurt_less := _ally(2, Vector3(-3, 0, 0))
	hurt.hp = 2.0
	hurt_less.hp = hurt_less.max_hp() * 0.5
	p.hp = p.max_hp() * 0.6
	check(_cast(p, &"soothing_downpour"), "cast")
	var rains := _fx_rain(p).running()
	check_eq(rains.size(), 1, "one rain")
	check(_flat_dist(rains[0], hurt) < 0.01, "on the most wounded hero")
	check_near(rains[0].radius, 4.0, 0.0001, "4 m")
	_run(p, 0.05)
	var beat := 0.3 + 0.02 * hurt.max_hp() + 4.0 * 0.5 * 0.5
	check_near(hurt.hp, 2.0 + beat, 0.001, "0.3 + 2% Max HP + 0.5 SP (per second) in the first beat")
	var shaman_gap := 0.3 + 0.02 * p.max_hp() + 1.0
	check_near(p.hp, minf(p.max_hp(), p.max_hp() * 0.6 + shaman_gap), 0.001, "the Shaman is 3 m away: inside, healed too")
	check_near(hurt_less.hp, hurt_less.max_hp() * 0.5, 0.0001, "6 m from the centre: dry")
	check(RunState.healing_by_player.get(0, 0.0) > 0.0, "the healing is the Shaman's")


func test_the_rain_beats_every_half_second_for_five_seconds() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"soothing_downpour")
	var hurt := _ally(1, Vector3(2, 0, 0))
	hurt.stats.set_source(&"big", {Stats.STAMINA: 300.0})  # room for ten beats
	hurt.hp = 1.0
	check(_cast(p, &"soothing_downpour"), "cast")
	var beat := 0.3 + 0.02 * hurt.max_hp() + 4.0 * 0.5 * 0.5
	_run(p, 1.05)
	check_near(hurt.hp, 1.0 + 3.0 * beat, beat * 0.51, "three beats in the first second (0 s, 0.5 s, 1 s)")
	_run(p, 3.0)
	check(_fx_rain(p).running().size() == 1, "still raining after 4 s")
	_run(p, 1.5)
	check_near(hurt.hp, 1.0 + 10.0 * beat, beat * 1.01, "about ten beats in all")
	check_eq(_fx_rain(p).running().size(), 0, "the rain is over")


func test_the_rain_heals_more_at_higher_rank_and_with_healing_done() -> void:
	var p := _shaman()
	_stats(p)
	p.stats.set_source(&"heal", {Stats.HEALING_DONE: 50.0})
	_learn(p, &"soothing_downpour", 2)
	var hurt := _ally(1, Vector3(2, 0, 0))
	hurt.hp = 1.0
	check(_cast(p, &"soothing_downpour"), "cast")
	_run(p, 0.05)
	var beat := (0.3 + 0.02 * hurt.max_hp() + 1.0) * 1.25 * 1.5
	check_near(hurt.hp, 1.0 + beat, 0.001, "Rank II power and +50% Healing Done")


func test_the_rain_never_heals_a_downed_hero() -> void:
	var p := _shaman()
	_learn(p, &"soothing_downpour")
	var ghost := _ally(1, Vector3(2, 0, 0))
	_down(ghost)
	var rain_target := _shaman(Vector3(0, 0, 0), 2)
	rain_target.hp = 1.0
	check(_cast(p, &"soothing_downpour"), "cast on the living hero")
	_run(p, 1.0)
	check(ghost.downed, "still down")


func test_the_rain_picks_a_hero_in_range_and_falls_back_to_the_shaman() -> void:
	var p := _shaman()
	_learn(p, &"soothing_downpour")
	var far := _ally(1, Vector3(11, 0, 0))
	far.hp = 1.0
	p.hp = p.max_hp()
	check(_cast(p, &"soothing_downpour"), "cast")
	check(_flat_dist(_fx_rain(p).running()[0], p) < 0.01, "the hurt hero is 11 m away: the rain falls on the Shaman")
	var q := _shaman(Vector3(0, 0, 40), 1)
	_learn(q, &"soothing_downpour")
	q.hp = 3.0
	check(_cast(q, &"soothing_downpour"), "a lone, hurt Shaman")
	check(_flat_dist(_fx_rain(q).running()[0], q) < 0.01, "heals itself")


func test_ties_go_to_the_nearer_hero() -> void:
	var p := _shaman(Vector3(0, 0, 0))
	_learn(p, &"soothing_downpour")
	var a := _ally(1, Vector3(6, 0, 0))
	var b := _ally(2, Vector3(2, 0, 3))
	a.hp = a.max_hp() * 0.5
	b.hp = b.max_hp() * 0.5
	check(_cast(p, &"soothing_downpour"), "cast")
	check(_flat_dist(_fx_rain(p).running()[0], b) < 0.01, "the nearer of two equally hurt heroes")


func test_rank_iii_lengthens_the_rain() -> void:
	var p := _shaman()
	_learn(p, &"soothing_downpour", 3)
	check(_cast(p, &"soothing_downpour"), "cast")
	check_near(_fx_rain(p).running()[0].duration, 7.0, 0.0001, "+2 s")


func test_following_rain_follows_the_hero() -> void:
	var p := _shaman()
	_learn(p, &"soothing_downpour", 5, 0)
	var hurt := _ally(1, Vector3(3, 0, 0))
	hurt.hp = 1.0
	check(_cast(p, &"soothing_downpour"), "cast")
	var rain := _fx_rain(p).running()[0]
	hurt.global_position = Vector3(3, 0, 7)
	_run(p, 0.2)
	check(_flat_dist(rain, hurt) < 0.01, "the rain walked along")


func test_thundercloud_strikes_the_enemies_in_the_rain_every_tick() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"soothing_downpour", 5, 1)
	var hurt := _ally(1, Vector3(3, 0, 0))
	hurt.hp = 1.0
	var foe := _enemy(Vector3(4, 0, 1))
	var dry := _enemy(Vector3(3, 0, 9))
	_mastery(p).grant_empower(1, 100.0)
	check(_cast(p, &"soothing_downpour"), "cast")
	check_eq(_mastery(p).empower_charges, 1, "a healing ability never takes the charge")
	_run(p, 0.05)
	check_near(foe.fake_damage_log[0], (2.0 + 3.0 + 0.5 * 4.0 * 0.5) * 1.5, 0.001, "2 + 0.3 Int + 0.5 SP per tick, Rank IV power")
	check(foe.fake_attacker_log[0] == p, "the Shaman's damage")
	check(dry.fake_damage_log.is_empty(), "the dry one is spared")
	_run(p, 1.0)
	check(foe.fake_damage_log.size() >= 3, "every tick")


func test_a_plain_rain_hurts_nobody() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"soothing_downpour")
	p.hp = 1.0
	var foe := _enemy(Vector3(1, 0, 0))
	check(_cast(p, &"soothing_downpour"), "cast")
	_run(p, 1.0)
	check(foe.fake_damage_log.is_empty(), "no Thundercloud, no damage")


func test_twin_squalls_call_a_second_rain_on_the_then_most_wounded_hero() -> void:
	var p := _shaman()
	_learn(p, &"soothing_downpour")
	_put(p, [{"kind": "ability", "match": {"id": "soothing_downpour"}, "mods": {"rains_add": 1.0}, "rank": 1}])
	var a := _ally(1, Vector3(4, 0, 0))
	var b := _ally(2, Vector3(-4, 0, 0))
	a.hp = 1.0
	b.hp = b.max_hp()
	check(_cast(p, &"soothing_downpour"), "cast")
	check_eq(_fx_rain(p).running().size(), 1, "one rain at first")
	a.hp = a.max_hp()
	b.hp = 1.0
	_run(p, 2.9)
	check_eq(_fx_rain(p).running().size(), 1, "the second comes after 3 s")
	_run(p, 0.2)
	var rains := _fx_rain(p).running()
	check_eq(rains.size(), 2, "now two")
	check(_flat_dist(rains[1], b) < 0.01, "the second on the hero who is most wounded now")


func test_the_rain_ends_with_the_wave() -> void:
	var p := _shaman()
	_learn(p, &"soothing_downpour")
	p.hp = 1.0
	check(_cast(p, &"soothing_downpour"), "cast")
	check_eq(_fx_rain(p).running().size(), 1, "falling")
	p.end_wave()
	check_eq(_fx_rain(p).running().size(), 0, "forgotten at the wave end")


func test_the_bot_calls_the_rain_for_a_hero_below_sixty_percent_without_one_over_them() -> void:
	var p := _shaman()
	_learn(p, &"soothing_downpour")
	var fx := _fx_rain(p)
	var a := _ally(1, Vector3(4, 0, 0))
	check(not fx.wants_auto_cast(_ctx(p, &"soothing_downpour")), "everyone is well")
	a.hp = a.max_hp() * 0.7
	check(not fx.wants_auto_cast(_ctx(p, &"soothing_downpour")), "70% is fine")
	a.hp = a.max_hp() * 0.5
	check(fx.wants_auto_cast(_ctx(p, &"soothing_downpour")), "50%: rain")
	check(_cast(p, &"soothing_downpour"), "cast")
	p.abilities.set_cooldown(Db.get_ability(&"soothing_downpour"), 0.0)
	a.hp = a.max_hp() * 0.4
	check(not fx.wants_auto_cast(_ctx(p, &"soothing_downpour")), "a rain already covers the hero")
	p.hp = p.max_hp() * 0.3
	p.global_position = Vector3(-20, 0, 0)
	check(fx.wants_auto_cast(_ctx(p, &"soothing_downpour")), "the Shaman itself below 60% and not covered")


# --- Spirit Pack ----------------------------------------------------------------------------------------------

func test_the_pack_calls_two_wolves_that_bite_for_half_the_weapon_hit() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"spirit_pack")
	var e := _enemy(Vector3(3, 0, 0))
	check(_cast(p, &"spirit_pack"), "cast")
	var fx := _fx_pack(p)
	check_eq(fx.alive_count(), 2, "two wolves")
	check(fx.wolves[0].get_parent() == world, "in the world")
	check(not fx.wolves[0].is_in_group(&"enemies"), "no target for enemies")
	_run(p, 3.0)
	check(e.fake_damage_log.size() >= 4, "both wolves bite (%d)" % e.fake_damage_log.size())
	for v in e.fake_damage_log:
		check_near(v, 5.0, 0.001, "50% of the 10 damage normalised mace hit")
	for a in e.fake_attacker_log:
		check(a == p, "the Shaman is credited")
	check_eq(Db.get_ability(&"spirit_pack").school, &"nature", "Nature")


func test_the_bites_are_pet_damage_and_feed_the_shaman_one_surge_each() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"spirit_pack")
	_boost(p, "pet")
	var e := _enemy(Vector3(3, 0, 0))
	check(_cast(p, &"spirit_pack"), "cast")
	var surge_after_cast := _surge(p).value
	check_near(surge_after_cast, 5.0, 0.0001, "the cast gave 5")
	_run(p, 2.0)
	var bites := 0
	for w in _fx_pack(p).wolves:
		bites += w.bites
	check(bites >= 2, "bitten (%d)" % bites)
	for v in e.fake_damage_log:
		check_near(v, 10.0, 0.001, "+100% pet damage doubles every bite")
	check_near(_surge(p).value, surge_after_cast + float(bites), 0.0001, "one Surge per bite")


func test_the_pack_takes_one_charge_and_bakes_it_into_every_bite() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"spirit_pack")
	var e := _enemy(Vector3(3, 0, 0))
	_mastery(p).grant_empower(1, 100.0)
	check(_cast(p, &"spirit_pack"), "cast")
	check_eq(_mastery(p).empower_charges, 0, "one charge")
	_run(p, 3.0)
	check(e.fake_damage_log.size() >= 4, "bitten")
	for v in e.fake_damage_log:
		check_near(v, 10.0, 0.001, "every bite doubled, whatever happens to the charges later")


func test_rank_iii_calls_a_third_wolf_and_a_recast_tops_the_pack_up() -> void:
	var p := _shaman()
	_learn(p, &"spirit_pack", 3)
	_enemy(Vector3(3, 0, 0))
	check(_cast(p, &"spirit_pack"), "cast")
	var fx := _fx_pack(p)
	check_eq(fx.alive_count(), 3, "three wolves")
	var first := fx.wolves[0]
	_run(p, 4.0)
	p.abilities.set_cooldown(Db.get_ability(&"spirit_pack"), 0.0)
	check(_cast(p, &"spirit_pack"), "a recast")
	check_eq(fx.alive_count(), 3, "the same pack, refreshed")
	check(first.life_left > 8.0, "its time is back to the full duration (%s)" % first.life_left)


func test_thunder_pack_arcs_every_bite_to_a_neighbour() -> void:
	var p := _shaman()
	_stats(p)
	_learn(p, &"spirit_pack", 5, 0)
	var e := _enemy(Vector3(3, 0, 0))
	var near := _enemy(Vector3(3, 0, 2))
	var far := _enemy(Vector3(3, 0, 9))
	check(_cast(p, &"spirit_pack"), "cast")
	_run(p, 2.0)
	var arcs := 0
	for w in _fx_pack(p).wolves:
		arcs += w.arcs
	check(arcs >= 1, "the bites arc (%d)" % arcs)
	check(far.fake_damage_log.is_empty(), "9 m away is out of the arc")
	# Rank IV power: a bite is 7.5, an arc 40% of it = 3.0.
	var arc_hits := 0
	for v in e.fake_damage_log + near.fake_damage_log:
		check(is_equal_approx(v, 3.0) or is_equal_approx(v, 7.5), "a bite (7.5) or an arc (3.0), got %s" % v)
		if is_equal_approx(v, 3.0):
			arc_hits += 1
	check_eq(arc_hits, arcs, "every arc is 40% of the bite")


func test_pack_guardians_make_nearby_enemies_chase_the_wolves() -> void:
	var p := _shaman()
	_learn(p, &"spirit_pack", 5, 1)
	var close := _enemy(Vector3(2, 0, 0))
	var distant := _enemy(Vector3(12, 0, 0))
	check(_cast(p, &"spirit_pack"), "cast")
	_run(p, 1.5)
	var taunted := false
	for w in _fx_pack(p).wolves:
		taunted = taunted or w.taunts > 0
	check(taunted, "the wolves taunted")
	check(close.is_taunted() and close.taunt_target is ShamanWolf, "an enemy within 3 m of a wolf chases it")
	check(not distant.is_taunted(), "a far one does not")


func test_the_wolves_leave_with_the_wave_the_downed_shaman_and_the_teardown() -> void:
	var p := _shaman()
	_learn(p, &"spirit_pack")
	_enemy(Vector3(3, 0, 0))
	check(_cast(p, &"spirit_pack"), "cast")
	var wolf := _fx_pack(p).wolves[0]
	p.end_wave()
	check(wolf.dismissed, "the wave end dismisses them")
	check_eq(_fx_pack(p).alive_count(), 0, "none left")
	p.abilities.set_cooldown(Db.get_ability(&"spirit_pack"), 0.0)
	check(_cast(p, &"spirit_pack"), "again")
	var w2 := _fx_pack(p).wolves[0]
	_down(p)
	_run(p, 0.1)
	check(w2.dismissed, "a downed Shaman loses the pack")
	var q := _shaman(Vector3(0, 0, 40), 1)
	_learn(q, &"spirit_pack")
	check(_cast(q, &"spirit_pack"), "a second Shaman")
	var w3 := _fx_pack(q).wolves[0]
	world.remove_child(q)
	q.free()
	check(w3.dismissed, "freeing the hero dismisses the wolves")


func test_the_bot_calls_the_pack_for_a_crowd_an_elite_or_low_health() -> void:
	var p := _shaman()
	_learn(p, &"spirit_pack")
	var fx := _fx_pack(p)
	check(not fx.wants_auto_cast(_ctx(p, &"spirit_pack")), "no enemy: no pack")
	var a := _enemy(Vector3(5, 0, 0))
	check(not fx.wants_auto_cast(_ctx(p, &"spirit_pack")), "one enemy at full health is no reason")
	_enemy(Vector3(5, 0, 1))
	_enemy(Vector3(5, 0, -1))
	check(fx.wants_auto_cast(_ctx(p, &"spirit_pack")), "three enemies within 8 m")
	var q := _shaman(Vector3(0, 0, 50), 1)
	_learn(q, &"spirit_pack")
	var big := _enemy(Vector3(8.5, 0, 50))
	big.elite_affix = &"swift"
	check(_fx_pack(q).wants_auto_cast(_ctx(q, &"spirit_pack")), "an elite within 9 m")
	var r := _shaman(Vector3(0, 0, 100), 2)
	_learn(r, &"spirit_pack")
	_enemy(Vector3(5, 0, 100))
	r.hp = r.max_hp() * 0.4
	check(_fx_pack(r).wants_auto_cast(_ctx(r, &"spirit_pack")), "below 50% HP")
	check(_cast(p, &"spirit_pack"), "cast")
	p.abilities.set_cooldown(Db.get_ability(&"spirit_pack"), 0.0)
	check(not fx.wants_auto_cast(_ctx(p, &"spirit_pack")), "the wolves are out: no second pack")
	check(a != null, "the first enemy exists")


# --- The whole kit as a bot ------------------------------------------------------------------------------------

func test_a_bot_with_the_whole_kit_fights_a_crowd_and_uses_every_ability() -> void:
	var p := _shaman()
	p.abilities.auto_cast = true
	_stats(p, 5.0)
	for id in LEARNED:
		p.abilities.learn(Db.get_ability(id))  # the third Active ability finds no slot, like a real hero
	var used: Dictionary[StringName, bool] = {}
	p.abilities.ability_cast.connect(func(_slot: int, a: AbilityData) -> void: used[a.id] = true)
	var ally := _ally(1, Vector3(3, 0, 3))
	ally.hp = 2.0
	var foes := _cluster(Vector3(2.5, 0, 0), 6, 1.2)
	_surge(p).set_value(100.0)
	_run(p, 20.0)
	var total := 0.0
	for e in foes:
		total += e.total()
	check(total > 100.0, "the bot dealt damage (%s)" % total)
	check(RunState.healing_by_player.get(0, 0.0) > 0.0, "and healed")
	check(_fx_rite(p).cycle >= 1, "planted totems")
	for id: StringName in [&"forking_bolt", &"totem_rite", &"thunderbolt", &"rumbling_earth", &"magma_lash", &"soothing_downpour", &"stormburst"]:
		check(used.has(id), "the bot cast %s" % id)
