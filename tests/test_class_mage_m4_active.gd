extends "res://tests/test_class_mage_m4_base.gd"
## Mage learned Active abilities (M4, GDD 6.4) – Pyroblast and Meteor – and the Rank III /
## Rank V / power support of the Mage's core abilities Blizzard and Blink: casts, damage,
## power, Rank III, both specialisations, the bot rules and the cleanup.


# --- Pyroblast ------------------------------------------------------------------------------

func test_pyroblast_winds_up_then_hurls_at_the_toughest_enemy() -> void:
	var p := _mage()
	var slot := _learn(p, &"pyroblast")
	check(slot in AbilityRunner.ACTIVE_SLOTS, "RB / LB slot")
	var weak := _enemy(Vector3(3, 0, 0), 30.0)
	var tough := _enemy(Vector3(0, 0, -8), 3000.0)
	var effect := _effect(p, &"pyroblast") as MagePyroblast
	check(p.abilities.try_cast(slot), "cast")
	check(effect.is_winding_up(), "winding up")
	check(p.get_node_or_null(^"PyroCharge") is MagePyroCharge, "a fireball swells over the hero")
	check(not p.abilities.is_ready(slot), "the cooldown runs from the wind-up")
	_step(0.9, [p])
	check_eq(_bolts().size(), 0, "nothing thrown during the 1 sec wind-up")
	_step(0.15, [p])
	check_eq(effect.released, 1, "released")
	check(not effect.is_winding_up(), "done")
	var charge := p.get_node_or_null(^"PyroCharge")
	check(charge == null or charge.is_queued_for_deletion(), "the charge look goes")
	_fly()
	var hit := _spell(p, 18.0, 2.5, &"fire", 1.0, 2.0)
	check_eq(_count(tough, hit), 1, "the toughest enemy takes the hit")
	check_eq(weak.fake_hits(), 0, "not the nearer weak one")
	var burn := MageBurn.find(tough, p)
	check(burn != null, "burning")
	check_near(burn.remaining() + burn.dealt, hit * 0.3, 0.01, "for 30% more")


func test_pyroblast_the_hero_keeps_moving_during_the_wind_up() -> void:
	var p := _mage()
	var slot := _learn(p, &"pyroblast")
	_enemy(Vector3(6, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	var input := p.slot.input as ScriptedInput
	input.move = Vector2(0, -1)
	var before := p.global_position
	Fakes.step(p, 0.5)
	check(p.global_position.distance_to(before) > 1.0, "walks while winding up")
	check((_effect(p, &"pyroblast") as MagePyroblast).is_winding_up(), "still winding up")


func test_pyroblast_needs_a_target_and_is_not_cast_twice() -> void:
	var p := _mage()
	var slot := _learn(p, &"pyroblast")
	var effect := _effect(p, &"pyroblast")
	check(not p.abilities.try_cast(slot), "nobody in reach")
	check(not effect.wants_auto_cast(_ctx(p, &"pyroblast")), "bots wait too")
	_enemy(Vector3(8, 0, 0))
	check(effect.wants_auto_cast(_ctx(p, &"pyroblast")), "bots cast with an enemy in reach")
	check(p.abilities.try_cast(slot), "cast")
	p.abilities.set_cooldown(_ability(&"pyroblast"), 0.0)
	check(not p.abilities.try_cast(slot), "not during a wind-up")
	check(not effect.wants_auto_cast(_ctx(p, &"pyroblast")), "bots neither")


func test_pyroblast_is_cancelled_by_going_down_wave_end_and_forget() -> void:
	var p := _mage()
	var slot := _learn(p, &"pyroblast")
	_enemy(Vector3(6, 0, 0))
	var effect := _effect(p, &"pyroblast") as MagePyroblast
	check(p.abilities.try_cast(slot), "cast")
	_down(p)
	check(not effect.is_winding_up(), "going down cancels it")
	p.revive(1.0)
	_step(1.5, [p])
	check_eq(effect.released, 0, "nothing thrown after the revive")
	p.abilities.set_cooldown(_ability(&"pyroblast"), 0.0)
	check(p.abilities.try_cast(slot), "cast again")
	p.end_wave()
	check(not effect.is_winding_up(), "wave end cancels it")
	var charge := p.get_node_or_null(^"PyroCharge")
	check(charge == null or charge.is_queued_for_deletion(), "no charge in the market")
	p.begin_wave()
	check(p.abilities.try_cast(slot), "cast in the next wave")
	p.abilities.forget(slot)
	check(not effect.is_winding_up(), "forgetting cancels it")


func test_pyroblast_power_and_rank_three_explosion() -> void:
	var p := _mage()
	var slot := _learn(p, &"pyroblast", 3)
	var target := _enemy(Vector3(7, 0, 0), 2000.0)
	var close := _enemy(Vector3(8, 0, 1.5))
	var away := _enemy(Vector3(7, 0, 6))
	check(p.abilities.try_cast(slot), "cast")
	_step(1.05, [p])
	_fly()
	var hit := _spell(p, 18.0, 2.5, &"fire", 1.25, 2.0)
	check_eq(_count(target, hit), 1, "Rank II-III: +25%")
	check_eq(_count(close, hit * 0.5), 1, "Rank III: the explosion hits a neighbour for 50%")
	check_eq(away.fake_hits(), 0, "6 m away is safe")
	check_near(p.abilities.cooldown_of(_ability(&"pyroblast")), 9.0, 0.001, "-10% cooldown")


func test_pyroblast_pyroclasm_spec_pierces() -> void:
	var p := _mage()
	var slot := _learn(p, &"pyroblast", 5, 0)
	var first := _enemy(Vector3(3, 0, 0), 100.0)
	var second := _enemy(Vector3(7, 0, 0), 100.0)
	var third := _enemy(Vector3(10, 0, 0), 900.0)
	check(p.abilities.try_cast(slot), "cast")
	_step(1.05, [p])
	_fly()
	var hit := _spell(p, 18.0, 2.5, &"fire", 1.5, 2.0)
	for e: Fakes.FakeEnemy in [first, second, third]:
		check_eq(_count(e, hit), 1, "every enemy in the path takes the full hit")


func test_pyroblast_hot_streak_spec_is_instant() -> void:
	var p := _mage()
	var slot := _learn(p, &"pyroblast", 5, 1)
	var e := _enemy(Vector3(5, 0, 0))
	var effect := _effect(p, &"pyroblast") as MagePyroblast
	check(p.abilities.try_cast(slot), "cast")
	check(not effect.is_winding_up(), "no wind-up")
	check_eq(effect.released, 1, "thrown at once")
	check(p.get_node_or_null(^"PyroCharge") == null, "no charge look")
	_fly()
	check(e.fake_hits() >= 1, "hit")
	check_near(p.abilities.cooldown_of(_ability(&"pyroblast")), 10.0 * 0.8 * 0.7, 0.001,
			"-20% (ranks), then 30% shorter (spec)")


func test_pyroblast_waits_for_its_button_unless_a_bot() -> void:
	var p := _mage()
	_learn(p, &"pyroblast")
	_enemy(Vector3(6, 0, 0))
	var effect := _effect(p, &"pyroblast") as MagePyroblast
	_step(0.6, [p])
	check(not effect.is_winding_up(), "a human's RB slot waits for the button")
	p.abilities.auto_cast = true
	_step(0.3, [p])
	check(effect.is_winding_up(), "a bot casts it")


# --- Meteor ---------------------------------------------------------------------------------

func test_meteor_falls_on_the_densest_group_and_leaves_burning_ground() -> void:
	var p := _mage()
	var slot := _learn(p, &"meteor")
	var group := _cluster(Vector3(7, 0, 2), 5)
	var lone := _enemy(Vector3(-6, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	var strikes := _strikes()
	check_eq(strikes.size(), 1, "one meteor")
	var m := strikes[0]
	check_near(WeaponRunner.flat(m.global_position).distance_to(Vector3(7, 0, 2)), 0.0, 0.5, "on the group")
	_step(0.85)
	check_eq(group[0].fake_hits(), 0, "still falling")
	_step(0.1)
	var hit := _spell(p, 12.0, 2.0, &"fire")
	for e in group:
		check_eq(_count(e, hit), 1, "impact on the whole group")
	check_eq(lone.fake_hits(), 0, "the lone enemy is spared")
	var areas := _areas()
	check_eq(areas.size(), 1, "burning ground")
	var area := areas[0]
	check_near(area.duration, 4.0, 0.001, "4 sec")
	check_near(area.radius, 3.0, 0.001, "3 m")
	check_eq(area.school, &"fire", "fire")
	check_near(area.damage_per_tick, _spell(p, 1.5, 0.25, &"fire", 1.0, 0.5), 0.001, "ground ticks")
	_step(1.0)
	check(group[0].fake_hits() >= 2, "the ground burns")


func test_meteor_power_and_rank_three() -> void:
	var p := _mage()
	var slot := _learn(p, &"meteor", 4)
	var group := _cluster(Vector3(5, 0, 0), 4)
	check(p.abilities.try_cast(slot), "cast")
	_step(0.95)
	check_eq(_count(group[0], _spell(p, 12.0, 2.0, &"fire", 1.5)), 1, "Rank IV: +50% impact")
	var area := _areas()[0]
	check_near(area.duration, 6.0, 0.001, "Rank III: +2 sec of burning ground")
	check_near(area.damage_per_tick, _spell(p, 1.5, 0.25, &"fire", 1.5, 0.5), 0.001, "+50% ground")


func test_meteor_shower_spec() -> void:
	var p := _mage()
	var slot := _learn(p, &"meteor", 5, 0)
	var a := _cluster(Vector3(7, 0, 0), 5)
	var b := _cluster(Vector3(-7, 0, 0), 3)
	check(p.abilities.try_cast(slot), "cast")
	var strikes := _strikes()
	check_eq(strikes.size(), 3, "three meteors")
	var first := strikes[0]
	check_near(WeaponRunner.flat(first.global_position).distance_to(Vector3(7, 0, 0)), 0.0, 0.6, "the densest group first")
	var on_b := false
	for m in strikes:
		on_b = on_b or WeaponRunner.flat(m.global_position).distance_to(Vector3(-7, 0, 0)) < 0.9
	check(on_b, "the next group gets one too")
	check(strikes[1].time_left() > strikes[0].time_left(), "they land one after another")
	_step(1.6)
	var hit := _spell(p, 12.0, 2.0, &"fire", 1.5) * 0.6
	check(_count(a[0], hit) >= 1, "60% impact on the first group")
	check(_count(b[0], hit) >= 1, "and on the second")
	check_eq(_areas().size(), 3, "three burning grounds")


func test_meteor_shower_without_other_groups_lands_around_the_one() -> void:
	var centers := MageMeteor.targets_for(null, Vector3.ZERO, 12.0, 3.0, Vector3(5, 0, 0), 3)
	check_eq(centers.size(), 3, "three spots")
	check_eq(centers[0], Vector3(5, 0, 0), "the group itself")
	for i in range(1, 3):
		check_near(centers[i].distance_to(Vector3(5, 0, 0)), 3.6, 0.001, "around it")


func test_meteor_cataclysm_spec() -> void:
	var p := _mage()
	var slot := _learn(p, &"meteor", 5, 1)
	var group := _cluster(Vector3(6, 0, 0), 4)
	check(p.abilities.try_cast(slot), "cast")
	_step(0.95)
	for e in group:
		check(e.fake_stun_count >= 1, "stunned by the impact")
	var area := _areas()[0]
	check_near(area.radius, 4.5, 0.001, "50% wider burning ground")


func test_meteor_bot_rule() -> void:
	var p := _mage()
	_learn(p, &"meteor")
	var effect := _effect(p, &"meteor")
	_cluster(Vector3(6, 0, 0), 3)
	check(not effect.wants_auto_cast(_ctx(p, &"meteor")), "3 enemies are not worth a meteor")
	_enemy(Vector3(6.2, 0, 0.3))
	check(effect.wants_auto_cast(_ctx(p, &"meteor")), "4 are")
	p.abilities.get_resource(&"mana").set_value(0.0)  # (no Blizzard from the bot)
	p.abilities.auto_cast = true
	_step(0.3, [p])
	check_eq(_strikes().size(), 1, "the bot called one")
	p.abilities.set_cooldown(_ability(&"meteor"), 0.0)
	check(not effect.wants_auto_cast(_ctx(p, &"meteor")), "not a second one on the same spot")
	_step(1.0)
	check_eq(_areas().size(), 1, "landed")
	check(not effect.wants_auto_cast(_ctx(p, &"meteor")), "nor onto its burning ground")


func test_meteor_cleanup() -> void:
	var p := _mage()
	var slot := _learn(p, &"meteor")
	var group := _cluster(Vector3(6, 0, 0), 4)
	check(p.abilities.try_cast(slot), "cast")
	p.end_wave()
	check_eq(_strikes().size(), 0, "a falling meteor is removed at wave end")
	_step(1.5)
	check_eq(group[0].fake_hits(), 0, "and never lands")
	p.begin_wave()
	check(p.abilities.try_cast(slot), "cast")
	_step(0.95)
	check_eq(_areas().size(), 1, "burning ground")
	p.abilities.forget(slot)
	check_eq(_areas().size(), 0, "forgetting Meteor removes its ground")


# --- Core: Blizzard -------------------------------------------------------------------------

func test_blizzard_power_and_rank_three() -> void:
	var p := _mage()
	_cluster(Vector3(6, 0, 0), 4)
	var plain := BlizzardEffect.tick_damage(_ctx(p, &"blizzard"))
	_learn(p, &"blizzard", 3)
	var ctx := _ctx(p, &"blizzard")
	check_near(BlizzardEffect.tick_damage(ctx), plain * 1.25, 0.001, "Rank II: +25% per tick")
	check(p.abilities.try_cast(0), "cast")
	check_near(_areas()[0].duration, 4.0, 0.001, "Rank III: +1 sec of hail")


func test_blizzard_wandering_storm_spec() -> void:
	var p := _mage()
	_learn(p, &"blizzard", 5, 0)
	var group := _cluster(Vector3(6, 0, 0), 4)
	var ctx := _ctx(p, &"blizzard")
	check(p.abilities.try_cast(0), "cast")
	var area := _areas()[0]
	check(area.follow == ctx.target, "the storm follows the targeted enemy")
	check(area.follow in group, "one of the group")
	var target := area.follow as Node3D
	target.global_position += Vector3(0, 0, 3)
	area._physics_process(DT)
	check_near(WeaponRunner.flat(area.global_position).distance_to(WeaponRunner.flat(target.global_position)), 0.0, 0.001, "and moves with it")


func test_blizzard_permafrost_spec() -> void:
	var p := _mage()
	_learn(p, &"blizzard", 5, 1)
	var group := _cluster(Vector3(6, 0, 0), 4)
	check(p.abilities.try_cast(0), "cast")
	var area := _areas()[0]
	check_near(area.stun, 1.0, 0.001, "freezes for 1 sec")
	check(area.follow == null, "stays where it fell")
	_step(1.0)
	for e in group:
		check_eq(e.fake_stun_count, 1, "each enemy frozen once")


# --- Core: Blink ----------------------------------------------------------------------------

func test_blink_power_and_rank_three() -> void:
	var p := _mage()
	var blink := _ability(&"blink")
	_learn(p, &"blink", 2)
	check(p.abilities.try_cast(1), "blink")
	check_near(p.invulnerable_left, 0.4 * 1.25, 0.001, "Rank II: +25% untouchable time")
	check_eq(p.abilities.charges_max(blink), 1, "one charge at Rank II")
	_learn(p, &"blink", 3)
	check_eq(p.abilities.charges_max(blink), 2, "Rank III: +1 charge")


func test_blink_frost_blink_spec() -> void:
	var p := _mage()
	_learn(p, &"blink", 5, 0)
	var near := _enemy(Vector3(1.5, 0, 1.5))
	var far := _enemy(Vector3(-6, 0, 6))
	p.facing = Vector3(0, 0, -1)
	check(p.abilities.try_cast(1), "blink")
	check(p.global_position.distance_to(Vector3.ZERO) > 3.0, "moved")
	check_eq(near.fake_stun_count, 1, "the enemy next to the old spot is frozen")
	check(_ice(near, p) != null, "in ice")
	check_near(_ice(near, p).left, 1.5, 0.001, "for 1.5 sec")
	check_eq(far.fake_stun_count, 0, "far away is not")


func test_blink_arcane_burst_spec() -> void:
	var p := _mage()
	_learn(p, &"blink", 5, 1)
	p.facing = Vector3(1, 0, 0)
	var at_arrival := _enemy(Vector3(7, 0, 1))
	var at_start := _enemy(Vector3(-1, 0, 0))
	check(p.abilities.try_cast(1), "blink")
	var hit := _spell(p, 4.0, 0.6, &"arcane", 1.5)
	check_eq(_count(at_arrival, hit), 1, "arcane burst where the hero arrives")
	check_eq(at_start.fake_hits(), 0, "nothing where it left")
