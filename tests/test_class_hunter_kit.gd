extends TestCase
## Hunter abilities, part 2 (M8, GDD 3.7) – Arrow Hail, Quick Draw, Play Dead and Blast Snare: casting,
## damage and its source, ranks, Rank V specialisations and clean-up. Part 1 (Arrow Fan, Backstep, Long
## Shot): test_class_hunter_abilities.gd; Hunt Signal and the companion: test_class_hunter_companion.gd.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var hunter: Player


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 42)
	world = Fakes.make_world(tree)
	hunter = Fakes.spawn_player(world, 0, &"hunter")
	hunter.stats.set_source(&"test", {Stats.CRIT: -500.0, Stats.DODGE: -500.0})
	hunter.facing = Vector3.FORWARD


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	hunter = null
	PlayerManager.clear()
	EnemyGrid.mark_dirty()


# --- Helpers ---------------------------------------------------------------------------------

func _w(school: StringName = &"physical") -> float:
	return GeneralKit.weapon_damage(hunter, school)


func _power(id: StringName) -> float:
	return float(hunter.abilities.params_for(Db.get_ability(id))["power"])


func _enemy(pos: Vector3, radius: float = 0.45) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos, radius)
	EnemyGrid.mark_dirty()
	return e


func _learn(id: StringName, rank: int = 1, spec: int = -1) -> int:
	var i := hunter.abilities.learn(Db.get_ability(id))
	check(i >= 0, "%s learned" % id)
	for r in range(1, rank):
		hunter.abilities.rank_up(id)
	if spec >= 0:
		check(hunter.abilities.set_spec(id, spec), "%s spec %d" % [id, spec])
	return i


func _effect(id: StringName) -> AbilityEffect:
	return HunterKit.effect_of(hunter, id)


func _run(seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		hunter.abilities._physics_process(DT)
		for child in hunter.get_children():
			if child is GeneralBuff:
				(child as GeneralBuff).step(DT)
		t += DT


## Steps every ability area and snare node for [param seconds].
func _step_world(seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		for node in tree.get_nodes_in_group(&"ability_areas"):
			(node as AbilityArea)._physics_process(DT)
		for node in tree.get_nodes_in_group(&"hunter_snares"):
			(node as HunterSnare).step(DT)
		t += DT


func _areas() -> Array[AbilityArea]:
	var out: Array[AbilityArea] = []
	for node in tree.get_nodes_in_group(&"ability_areas"):
		var a := node as AbilityArea
		if a != null and a.owner_player == hunter and not a.is_queued_for_deletion():
			out.append(a)
	return out


func _snares() -> Array[HunterSnare]:
	var out: Array[HunterSnare] = []
	for node in tree.get_nodes_in_group(&"hunter_snares"):
		var s := node as HunterSnare
		if s != null and s.is_active():
			out.append(s)
	return out


# --- Arrow Hail ------------------------------------------------------------------------------

func test_arrow_hail_rains_on_the_densest_group() -> void:
	for p in [Vector3(6, 0, 0), Vector3(7, 0, 0.8), Vector3(6.4, 0, -0.9), Vector3(6.8, 0, 0.2)]:
		_enemy(p)
	_enemy(Vector3(-5, 0, 0))
	var slot := _learn(&"arrow_hail")
	check_eq(slot, 2, "an Active slot")
	check(hunter.abilities.try_cast(slot), "cast")
	var areas := _areas()
	check_eq(areas.size(), 1, "one circle")
	var a := areas[0]
	check_near(a.radius, 3.0, 0.001, "3 m")
	check_near(a.duration, 4.0, 0.001, "for 4 s")
	check_near(a.tick_interval, 0.5, 0.001, "every half second")
	check_near(a.damage_per_tick, _w() * 0.4, 0.001, "40% W per tick")
	check_eq(a.school, &"physical", "physical")
	check(a.global_position.x > 5.0, "on the dense group to the right")
	check(a.get_node_or_null("ArrowHailVfx") != null, "with falling arrows")
	check_near(hunter.abilities.remaining(slot), 12.0, 0.001, "12 s cooldown")


func test_arrow_hail_ticks_hurt_enemies_inside_through_the_ability_source() -> void:
	var inside := _enemy(Vector3(6, 0, 0))
	var outside := _enemy(Vector3(6, 0, 5))
	var slot := _learn(&"arrow_hail")
	hunter.abilities.try_cast(slot)
	_step_world(2.0)
	check_eq(inside.fake_hits(), 4, "four ticks in two seconds")
	for d in inside.fake_damage_log:
		check_near(d, _w() * 0.4, 0.001, "40% W each")
		check(not inside.fake_crit_log[0], "no crits")
	check_eq(inside.fake_attacker_log[0], hunter, "credited to the Hunter")
	check_eq(outside.fake_hits(), 0, "outside the circle: nothing")
	_step_world(3.0)
	check_eq(inside.fake_hits(), 8, "eight ticks in all")


func test_arrow_hail_rank_three_specs_and_power() -> void:
	_enemy(Vector3(6, 0, 0))
	_enemy(Vector3(-6, 0, 0.5))
	var slot := _learn(&"arrow_hail", 3)
	hunter.abilities.try_cast(slot)
	check_near(_areas()[0].radius, 4.0, 0.001, "Rank III: +1 m")
	for a in _areas():
		a.free()
	var slot_b := hunter.abilities.slot_of(&"arrow_hail")
	hunter.abilities.rank_up(&"arrow_hail")
	hunter.abilities.rank_up(&"arrow_hail")
	hunter.abilities.set_spec(&"arrow_hail", 0)
	hunter.abilities.set_cooldown(Db.get_ability(&"arrow_hail"), 0.0)
	hunter.abilities.try_cast(slot_b)
	var hail := _effect(&"arrow_hail") as HunterArrowHail
	check_eq(_areas().size(), 2, "Crossfire Barrage: a second hail")
	check(hail.second_area != null, "on the next group")
	check(hail.second_area.global_position.x < 0.0, "the one on the left")
	check_near(hail.last_area.damage_per_tick, _w() * 0.4 * 1.5, 0.001, "power x1.5 at Rank IV")
	for a in _areas():
		a.free()
	hunter.abilities.set_spec(&"arrow_hail", 1)
	hunter.abilities.set_cooldown(Db.get_ability(&"arrow_hail"), 0.0)
	hunter.abilities.try_cast(slot_b)
	check_eq(_areas().size(), 1, "Pinning Hail: one circle")
	check_eq(_areas()[0].slow_pct, 40.0, "that slows by 40%")


func test_arrow_hail_auto_cast_wants_a_group_and_no_second_hail_on_the_first() -> void:
	var slot := _learn(&"arrow_hail")
	var hail := _effect(&"arrow_hail") as HunterArrowHail
	var ability := Db.get_ability(&"arrow_hail")
	for p in [Vector3(6, 0, 0), Vector3(6.5, 0, 0.5), Vector3(5.5, 0, -0.5)]:
		_enemy(p)
	check(not hail.wants_auto_cast(hunter.abilities.build_context(ability)), "three enemies are not enough")
	_enemy(Vector3(6.2, 0, 0.9))
	check(hail.wants_auto_cast(hunter.abilities.build_context(ability)), "four are")
	hunter.abilities.try_cast(slot)
	hunter.abilities.set_cooldown(ability, 0.0)
	check(not hail.wants_auto_cast(hunter.abilities.build_context(ability)), "not on a hail that is already falling")


# --- Quick Draw ------------------------------------------------------------------------------

func test_quick_draw_gives_haste_one_tick_later_and_ends() -> void:
	var slot := _learn(&"quick_draw")
	var base_haste := hunter.stats.get_stat(Stats.HASTE)
	check(hunter.abilities.try_cast(slot), "cast")
	check_eq(hunter.stats.get_stat(Stats.HASTE), base_haste, "the Haste lands on the next tick (it must not shorten its own cooldown)")
	check_near(hunter.abilities.remaining(slot), 16.0, 0.001, "16 s cooldown, booked without the Haste")
	_run(DT * 2.0)
	check_near(hunter.stats.get_stat(Stats.HASTE), base_haste + 40.0, 0.001, "+40% Haste")
	var draw := _effect(&"quick_draw") as HunterQuickDraw
	check(draw.active_buff() != null, "a buff")
	check(draw.active_buff().get_node_or_null("QuickDrawLook") != null, "with its look")
	_run(4.1)
	check_eq(hunter.stats.get_stat(Stats.HASTE), base_haste, "gone after 4 s")
	check(draw.active_buff() == null, "buff freed")


func test_quick_draw_rank_three_pierce_and_hail_of_shafts() -> void:
	var slot := _learn(&"quick_draw", 3)
	hunter.abilities.try_cast(slot)
	_run(DT * 2.0)
	check_eq(CombatMath.extra_pierce(hunter.stats), 1, "Rank III: pierce 1 while it lasts")
	hunter.abilities.end_wave()
	check_eq(CombatMath.extra_pierce(hunter.stats), 0, "and gone with the wave")
	hunter.abilities.rank_up(&"quick_draw")
	hunter.abilities.rank_up(&"quick_draw")
	hunter.abilities.set_spec(&"quick_draw", 0)
	hunter.abilities.set_cooldown(Db.get_ability(&"quick_draw"), 0.0)
	hunter.abilities.try_cast(slot)
	_run(DT * 2.0)
	check_eq(CombatMath.extra_projectiles(hunter.stats), 2, "Hail of Shafts: two extra arrows")
	# Arrow Fan reads the same stat.
	_enemy(Vector3(0, 0, -5))
	hunter.abilities.try_cast(0)
	var n := 0
	for node in tree.get_nodes_in_group(&"projectiles"):
		if node is HunterArrow:
			n += 1
	check_eq(n, 7, "Arrow Fan looses two more arrows too")


func test_quick_draw_focus_rush_restores_focus_on_the_cast() -> void:
	var slot := _learn(&"quick_draw", 5, 1)
	HunterKit.focus(hunter).set_value(10.0)
	hunter.abilities.try_cast(slot)
	check_near(HunterKit.focus(hunter).value, 45.0, 0.001, "+35 Focus at once")


func test_quick_draw_is_cleared_by_the_wave_and_by_going_down() -> void:
	var slot := _learn(&"quick_draw")
	var base_haste := hunter.stats.get_stat(Stats.HASTE)
	hunter.abilities.try_cast(slot)
	_run(DT * 2.0)
	hunter.abilities.end_wave()
	check_eq(hunter.stats.get_stat(Stats.HASTE), base_haste, "the wave end ends it")
	hunter.abilities.set_cooldown(Db.get_ability(&"quick_draw"), 0.0)
	hunter.abilities.try_cast(slot)
	_run(DT * 2.0)
	hunter.downed = true
	hunter.downed_changed.emit(true)
	hunter.downed = false
	check_eq(hunter.stats.get_stat(Stats.HASTE), base_haste, "going down ends it")


func test_quick_draw_auto_cast_rule() -> void:
	var slot := _learn(&"quick_draw")
	var draw := _effect(&"quick_draw") as HunterQuickDraw
	var ability := Db.get_ability(&"quick_draw")
	_enemy(Vector3(5, 0, 0))
	_enemy(Vector3(-5, 0, 0))
	check(not draw.wants_auto_cast(hunter.abilities.build_context(ability)), "two enemies")
	_enemy(Vector3(0, 0, 7))
	check(draw.wants_auto_cast(hunter.abilities.build_context(ability)), "three within 8 m")
	hunter.abilities.try_cast(slot)
	_run(DT * 2.0)
	hunter.abilities.set_cooldown(ability, 0.0)
	check(not draw.wants_auto_cast(hunter.abilities.build_context(ability)), "not while it runs")


# --- Play Dead -------------------------------------------------------------------------------

func test_play_dead_hides_the_hunter_and_tips_the_onion_over() -> void:
	var slot := _learn(&"play_dead")
	check(hunter.abilities.try_cast(slot), "cast")
	check(hunter.is_stealthed(), "stealthed")
	check_near(hunter.stealth_left, 2.0, 0.001, "for 2 s")
	check(hunter.model.play_dead, "the model plays dead")
	for i in 20:
		hunter.model._process(DT * 2.0)
	check(hunter.model.tip_amount() > 0.9, "tipped over")
	check_near(hunter.abilities.remaining(slot), 20.0, 0.001, "20 s cooldown")
	var dead := _effect(&"play_dead") as HunterPlayDead
	check(dead.is_active(), "active")
	_run(2.1)
	check(not dead.is_active(), "up again")
	check(not hunter.model.play_dead, "the pose ends")
	check_eq(dead.risen, 1, "the Hunter rose on its own")
	check_eq(hunter.forced_crits, 0, "no crits without Patient Predator")


func test_play_dead_makes_enemies_lose_the_hunter() -> void:
	var slot := _learn(&"play_dead")
	hunter.abilities.try_cast(slot)
	check(hunter.is_stealthed(), "enemies skip a stealthed player")
	# Stealth is the hook enemies read (Enemy / Projectile._is_valid_target skip stealthed heroes).
	var proj := Projectile.create(Projectile.TEAM_ENEMIES, 5.0, false, Vector3.FORWARD, 10.0, 10.0)
	check(not proj._is_valid_target(hunter), "enemy projectiles ignore it")
	proj.free()


func test_play_dead_patient_predator_banks_three_crits_when_it_ends() -> void:
	var slot := _learn(&"play_dead", 5, 0)
	hunter.abilities.try_cast(slot)
	check_eq(hunter.forced_crits, 0, "nothing while down")
	_run(2.1)
	check_eq(hunter.forced_crits, 3, "three guaranteed crits when it rises")


func test_play_dead_patient_predator_is_lost_when_cut_short() -> void:
	var slot := _learn(&"play_dead", 5, 0)
	hunter.abilities.try_cast(slot)
	hunter.abilities.end_wave()
	_run(2.1)
	check_eq(hunter.forced_crits, 0, "a wave hook ends it without the crits")


func test_play_dead_rest_and_recover_heals_while_down() -> void:
	var slot := _learn(&"play_dead", 5, 1)
	hunter.hp = hunter.max_hp() * 0.1
	var before := hunter.hp
	hunter.abilities.try_cast(slot)
	_run(2.2)
	var power := _power(&"play_dead")
	check_near(hunter.hp - before, hunter.max_hp() * 0.3 * power, 0.01, "30% of the max health x power")


func test_play_dead_decoy_taunts_enemies_to_the_companion() -> void:
	var slot := _learn(&"play_dead", 3)
	var pet := (hunter.abilities.mastery as HunterMastery).ensure_companion()
	var near := _enemy(Vector3(2, 0, 0))
	var far := _enemy(Vector3(6, 0, 0))
	hunter.abilities.try_cast(slot)
	check(near.is_taunted() and near.taunt_target == pet, "an enemy within 4 m is taunted to the companion")
	check(not far.is_taunted(), "one beyond 4 m is not")
	_run(2.2)
	check(not near.is_taunted(), "released when Play Dead ends")


func test_play_dead_auto_cast_rule() -> void:
	var slot := _learn(&"play_dead")
	var dead := _effect(&"play_dead") as HunterPlayDead
	var ability := Db.get_ability(&"play_dead")
	check(not dead.wants_auto_cast(hunter.abilities.build_context(ability)), "nobody around")
	var e := _enemy(Vector3(0, 0, -3.5))
	check(not dead.wants_auto_cast(hunter.abilities.build_context(ability)), "healthy, one enemy")
	hunter.hp = hunter.max_hp() * 0.39
	check(dead.wants_auto_cast(hunter.abilities.build_context(ability)), "hurt (<= 40%) with an enemy within 4 m")
	e.global_position = Vector3(0, 0, -6)
	EnemyGrid.mark_dirty()
	check(not dead.wants_auto_cast(hunter.abilities.build_context(ability)), "hurt but the enemy is far")
	hunter.hp = hunter.max_hp()
	for i in 6:
		_enemy(Vector3(2.0, 0, 0).rotated(Vector3.UP, TAU * float(i) / 6.0))
	check(dead.wants_auto_cast(hunter.abilities.build_context(ability)), "six enemies within 3 m")
	check(slot >= 0, "slotted")


# --- Blast Snare -----------------------------------------------------------------------------

func test_blast_snare_lays_a_snare_towards_the_nearest_enemy() -> void:
	_enemy(Vector3(0, 0, -6))
	var slot := _learn(&"blast_snare")
	check_eq(slot, 4, "an Auto slot")
	check(hunter.abilities.try_cast(slot), "cast")
	var snares := _snares()
	check_eq(snares.size(), 1, "one snare")
	check_near(snares[0].global_position.z, -3.0, 0.001, "3 m ahead")
	check_near(snares[0].global_position.x, 0.0, 0.001, "on the line to the enemy")
	check_near(hunter.abilities.remaining(slot), 8.0, 0.001, "8 s cooldown")
	check(not snares[0].armed, "not armed yet")
	_step_world(0.6)
	check(snares[0].armed, "armed after 0.5 s")


func test_blast_snare_bursts_for_fire_weapon_damage_when_an_enemy_steps_on_it() -> void:
	var walker := _enemy(Vector3(0, 0, -6))
	var slot := _learn(&"blast_snare")
	hunter.abilities.try_cast(slot)
	var bystander := _enemy(Vector3(2.0, 0, -3.0))
	var distant := _enemy(Vector3(5.0, 0, -3.0))
	_step_world(1.0)
	check_eq(walker.fake_hits(), 0, "nothing triggered yet")
	walker.global_position = Vector3(0, 0, -3.6)
	EnemyGrid.mark_dirty()
	_step_world(0.3)
	check_eq(_snares().size(), 0, "the snare burst")
	check_eq(walker.fake_hits(), 1, "the enemy on the snare is hit")
	check_near(walker.fake_damage_log[0], _w(&"fire") * 2.2, 0.001, "220% W as Fire damage")
	check_eq(walker.fake_attacker_log[0], hunter, "credited to the Hunter")
	check_eq(bystander.fake_hits(), 1, "an enemy within 2.5 m is caught by the blast")
	check_eq(distant.fake_hits(), 0, "one further out is not")
	check(not walker.fake_crit_log[0], "no crit")


func test_blast_snare_does_not_burst_before_it_is_armed() -> void:
	var e := _enemy(Vector3(0, 0, -3.2))
	var slot := _learn(&"blast_snare")
	hunter.abilities.try_cast(slot)
	_step_world(0.3)
	check_eq(_snares().size(), 1, "an enemy on an unarmed snare does nothing")
	_step_world(0.4)
	check_eq(_snares().size(), 0, "armed: it goes off")
	check_eq(e.fake_hits(), 1, "hit")


func test_blast_snare_keeps_at_most_three_and_the_oldest_fizzles() -> void:
	_enemy(Vector3(0, 0, -7))
	var slot := _learn(&"blast_snare")
	var snare := _effect(&"blast_snare") as HunterBlastSnare
	var first: HunterSnare
	for i in 4:
		check(hunter.abilities.try_cast(slot), "lay %d" % i)
		if i == 0:
			first = snare.live_snares()[0]
		hunter.abilities.set_cooldown(Db.get_ability(&"blast_snare"), 0.0)
		hunter.global_position += Vector3(0, 0, -0.7)
	check_eq(snare.live_snares().size(), 3, "three live snares")
	check(not first.is_active(), "the oldest was pushed out")


func test_blast_snare_expires_after_fifteen_seconds_and_with_the_wave() -> void:
	_enemy(Vector3(0, 0, -8))
	var slot := _learn(&"blast_snare")
	hunter.abilities.try_cast(slot)
	_step_world(14.5)
	check_eq(_snares().size(), 1, "still there at 14.5 s")
	_step_world(1.0)
	check_eq(_snares().size(), 0, "fizzled at 15 s")
	hunter.abilities.set_cooldown(Db.get_ability(&"blast_snare"), 0.0)
	hunter.abilities.try_cast(slot)
	hunter.abilities.end_wave()
	for s in tree.get_nodes_in_group(&"hunter_snares"):
		check((s as Node).is_queued_for_deletion(), "removed with the wave")


func test_blast_snare_ranks_and_specs() -> void:
	var e := _enemy(Vector3(0, 0, -3.2))
	var slot := _learn(&"blast_snare", 3)
	hunter.abilities.try_cast(slot)
	check_near(_snares()[0].numbers["radius"], 3.5, 0.001, "Rank III: +1 m")
	for s in _snares():
		s.free()
	hunter.abilities.rank_up(&"blast_snare")
	hunter.abilities.rank_up(&"blast_snare")
	hunter.abilities.set_spec(&"blast_snare", 1)
	hunter.abilities.set_cooldown(Db.get_ability(&"blast_snare"), 0.0)
	hunter.abilities.try_cast(slot)
	var numbers := _snares()[0].numbers
	check_near(numbers["damage"], _w(&"fire") * 3.2 * 1.5, 0.001, "Heavy Charge: +100% weapon damage, x power")
	check_near(numbers["arm_time"], 1.0, 0.001, "armed after 1 s")
	_step_world(1.2)
	check_eq(e.fake_hits(), 1, "hit")
	for s in _snares():
		s.free()
	hunter.abilities.set_spec(&"blast_snare", 0)
	hunter.abilities.set_cooldown(Db.get_ability(&"blast_snare"), 0.0)
	e.global_position = Vector3(0, 0, -3.2)
	hunter.abilities.try_cast(slot)
	_step_world(0.8)
	check_near(e.slow_pct, 90.0 if 60.0 * 1.5 > 90.0 else 60.0 * 1.5, 0.001, "Clinging Net: 60% x power (capped at 90)")
	check_near(e.slow_left, 3.0, 0.2, "for 3 s")


func test_blast_snare_talent_riders_ember_scatter_and_more_traps() -> void:
	var e := _enemy(Vector3(0, 0, -3.2))
	var other := _enemy(Vector3(2.9, 0, -3.2))
	var slot := _learn(&"blast_snare")
	hunter.bonuses.set_effects(PlayerBonuses.SOURCE_TALENTS, [{"kind": "ability", "match": {"id": "blast_snare"},
			"mods": {"ember_duration_add": 4.0, "ember_pct_add": 25.0, "scatter_add": 3.0, "traps_add": 1.0, "max_traps_add": 2.0}}] as Array[Dictionary])
	check(hunter.abilities.try_cast(slot), "cast")
	check_eq(_snares().size(), 2, "Brace of Snares: two snares per cast")
	_step_world(0.7)
	check_eq(_snares().size(), 0, "both burst")
	var embers := _areas()
	check(embers.size() >= 1, "burning ground")
	var found := false
	for a in embers:
		if is_equal_approx(a.duration, 4.0) and a.school == &"fire":
			found = true
			check_near(a.damage_per_tick, _w(&"fire") * 0.25, 0.001, "25% W every half second")
	check(found, "an ember area of 4 s")
	check(e.fake_hits() >= 1 and other.fake_hits() >= 1, "the burst and the scatter bombs hit")


func test_blast_snare_auto_cast_rule() -> void:
	var slot := _learn(&"blast_snare")
	var snare := _effect(&"blast_snare") as HunterBlastSnare
	var ability := Db.get_ability(&"blast_snare")
	var e := _enemy(Vector3(0, 0, -1.5))
	check(not snare.wants_auto_cast(hunter.abilities.build_context(ability)), "an enemy 1.5 m away is too close")
	e.global_position = Vector3(0, 0, -5)
	EnemyGrid.mark_dirty()
	check(snare.wants_auto_cast(hunter.abilities.build_context(ability)), "an enemy 5 m away")
	e.global_position = Vector3(0, 0, -9)
	EnemyGrid.mark_dirty()
	check(not snare.wants_auto_cast(hunter.abilities.build_context(ability)), "9 m is out of range")
	e.global_position = Vector3(0, 0, -5)
	EnemyGrid.mark_dirty()
	hunter.abilities.try_cast(slot)
	hunter.abilities.set_cooldown(ability, 0.0)
	check(not snare.wants_auto_cast(hunter.abilities.build_context(ability)), "not on top of the snare it just laid")
