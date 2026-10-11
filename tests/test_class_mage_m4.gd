extends "res://tests/test_class_mage_m4_base.gd"
## Mage learned Auto-cast abilities (M4, GDD 6.4): Fireball, Frost Nova, Arcane Missiles and
## Ice Barrier – casts, damage formulas, power (ranks II / IV), Rank III, both Rank V
## specialisations, the auto-cast conditions and the cleanup. Plus the data of all six.

const MAGE_POOL: Dictionary[StringName, AbilityData.Kind] = {
	&"fireball": AbilityData.Kind.AUTO, &"frost_nova": AbilityData.Kind.AUTO,
	&"arcane_missiles": AbilityData.Kind.AUTO, &"ice_barrier": AbilityData.Kind.AUTO,
	&"pyroblast": AbilityData.Kind.ACTIVE, &"meteor": AbilityData.Kind.ACTIVE,
}


# --- Data -----------------------------------------------------------------------------------

func test_the_six_mage_abilities_are_in_the_pool() -> void:
	var pool := Db.ability_pool(&"mage")
	var ids: Array[StringName] = []
	for a in pool:
		ids.append(a.id)
	for id in MAGE_POOL:
		check(id in ids, "%s offered to the Mage" % id)
		var a := Db.get_ability(id)
		check_eq(a.kind, MAGE_POOL[id], "%s kind" % id)
		check_eq(a.class_id, &"mage", "%s belongs to the Mage" % id)
		check(a.effect != null and a.effect.new() is AbilityEffect, "%s has an effect" % id)
		check(a.card_weight > 0.0, "%s can be drawn" % id)
	for a in Db.ability_pool(&"warrior"):
		check(not MAGE_POOL.has(a.id), "%s is not offered to a Warrior" % a.id)


func test_every_mage_ability_has_ranks_specs_and_a_filled_description() -> void:
	var ids: Array[StringName] = []
	ids.assign(MAGE_POOL.keys())
	ids.append_array([&"blizzard", &"blink"] as Array[StringName])
	var placeholder := RegEx.create_from_string("\\{([a-z_]+)\\}")
	for id in ids:
		var a := Db.get_ability(id)
		check(not a.rank3.is_empty(), "%s Rank III mods" % id)
		check(a.rank3_text != "", "%s Rank III text" % id)
		check_eq(a.specs.size(), 2, "%s has two specialisations" % id)
		for s in a.specs:
			check(String(s.get("name", "")) != "" and String(s.get("text", "")) != "", "%s spec named" % id)
			check(not (s.get("mods", {}) as Dictionary).is_empty(), "%s spec changes something" % id)
		for m in placeholder.search_all(a.description):
			check(a.params.has(m.get_string(1)), "%s: {%s} is a param" % [id, m.get_string(1)])
		check(a.school in [&"fire", &"frost", &"arcane"], "%s school" % id)
	check_eq(Db.get_ability(&"blizzard").kind, AbilityData.Kind.CORE, "Blizzard stays core")


func test_spell_power_intellect_and_school_damage_scale_the_spells() -> void:
	var p := _mage()
	for id in MAGE_POOL:
		_learn(p, id)
	var int_before := p.stats.get_raw(Stats.INTELLECT)
	var fire_before := MageSpell.damage_from(_ctx(p, &"fireball"), &"fire")
	p.stats.set_source(&"test_gear", {Stats.SPELL_POWER: 10.0, Stats.INTELLECT: 5.0, Stats.FIRE_DAMAGE: 20.0})
	check_near(p.stats.get_raw(Stats.INTELLECT), int_before + 5.0, 0.001, "Intellect from gear")
	var i := p.stats.get_raw(Stats.INTELLECT)
	check_near(MageSpell.damage_from(_ctx(p, &"fireball"), &"fire"), (6.0 + i + 10.0) * 1.2, 0.001,
			"Fireball: + Intellect, + Spell Power, Fire %")
	check(MageSpell.damage_from(_ctx(p, &"fireball"), &"fire") > fire_before + 15.0, "much stronger")
	check_near(MageSpell.damage_from(_ctx(p, &"arcane_missiles"), &"arcane"), 1.5 + 0.35 * i + 0.4 * 10.0, 0.001,
			"each missile takes 40% of the Spell Power (many hits)")
	check_near(MageSpell.damage_from(_ctx(p, &"pyroblast"), &"fire"), (18.0 + 2.5 * i + 2.0 * 10.0) * 1.2, 0.001,
			"Pyroblast takes double Spell Power")
	check_near(MageSpell.damage_from(_ctx(p, &"meteor"), &"fire", "ground_"), (1.5 + 0.25 * i + 0.5 * 10.0) * 1.2, 0.001,
			"burning ground: half Spell Power per tick")
	check_near(MageIceBarrier.shield_amount(_ctx(p, &"ice_barrier")), 4.0 + 0.5 * i + 0.5 * 10.0, 0.001,
			"Ice Barrier: + Intellect and Spell Power (no damage %)")


# --- Fireball -------------------------------------------------------------------------------

func test_fireball_hits_the_nearest_enemy_and_sets_it_burning() -> void:
	var p := _mage()
	var slot := _learn(p, &"fireball")
	check(slot >= AbilityRunner.CORE_SLOTS + 2, "auto slot")
	var near := _enemy(Vector3(5, 0, 0))
	var far := _enemy(Vector3(-8, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	check_eq(_bolts().size(), 1, "one fireball")
	_fly()
	var hit := _spell(p, 6.0, 1.0, &"fire")
	check_eq(near.fake_hits(), 1, "the nearest enemy is hit")
	check_near(near.fake_damage_log[0], hit, 0.001, "spell damage: 6 + Intellect, Spell Power, Fire %")
	check_eq(far.fake_hits(), 0, "the other one is not")
	var burn := MageBurn.find(near, p)
	check(burn != null, "burning")
	check_near(burn.remaining() + burn.dealt, hit * 0.5, 0.01, "burn = 50% of the hit")
	_step(3.2)
	check_near(_total(near), hit * 1.5, 0.02, "hit + full burn")
	check(MageBurn.find(near, p) == null, "the burn is over")
	check_eq(p.abilities.cooldown_of(_ability(&"fireball")), 4.0, "4 sec cooldown")


func test_fireball_auto_casts_only_with_an_enemy_in_reach() -> void:
	var p := _mage()
	_learn(p, &"fireball")
	_step(1.0, [p])
	check_eq(_bolts().size(), 0, "nobody around: nothing thrown")
	var e := _enemy(Vector3(14, 0, 0))
	_step(0.5, [p])
	check_eq(_bolts().size(), 0, "14 m is out of reach")
	e.global_position = Vector3(7, 0, 0)
	EnemyGrid.mark_dirty()
	_step(0.3, [p])
	check_eq(_bolts().size(), 1, "a human's auto slot casts by itself")
	_fly()
	check_eq(e.fake_hits(), 1, "hit")
	_step(1.0, [p])
	check_eq(_bolts().size(), 0, "then on cooldown")


func test_fireball_power_and_rank_three() -> void:
	var p := _mage()
	var slot := _learn(p, &"fireball", 2)
	check_near(_ctx(p, &"fireball").num("power"), 1.25, 0.0001, "Rank II power")
	var a := _enemy(Vector3(4, 0, 0))
	var b := _enemy(Vector3(0, 0, -6))
	check(p.abilities.try_cast(slot), "cast")
	check_near(_bolts()[0].damage, _spell(p, 6.0, 1.0, &"fire", 1.25), 0.001, "+25% damage")
	check_eq(_bolts().size(), 1, "one fireball below Rank III")
	_fly()
	check_eq(b.fake_hits(), 0, "the second enemy is spared")
	_learn(p, &"fireball", 3)
	p.abilities.set_cooldown(_ability(&"fireball"), 0.0)
	check(p.abilities.try_cast(slot), "cast at Rank III")
	check_eq(_bolts().size(), 2, "Rank III: two fireballs")
	_fly()
	var hit := _spell(p, 6.0, 1.0, &"fire", 1.25)
	check_eq(_count(a, hit), 2, "the nearest is hit again")
	check_eq(_count(b, hit), 1, "and the next nearest too")


func test_fireball_two_fireballs_at_a_single_enemy() -> void:
	var p := _mage()
	var slot := _learn(p, &"fireball", 3)
	var e := _enemy(Vector3(6, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	_fly()
	check_eq(_count(e, _spell(p, 6.0, 1.0, &"fire", 1.25)), 2, "both fireballs find the only target")


func test_fireball_bouncing_spec() -> void:
	var p := _mage()
	var slot := _learn(p, &"fireball", 5, 0)
	var first := _enemy(Vector3(3, 0, 0))
	var second := _enemy(Vector3(6, 0, 2))
	var third := _enemy(Vector3(9, 0, 0))
	var power := _ctx(p, &"fireball").num("power")
	check_near(power, 1.5, 0.0001, "Rank V keeps +50%")
	check(p.abilities.try_cast(slot), "cast")
	_fly()
	var hit := _spell(p, 6.0, 1.0, &"fire", power)
	check_eq(_count(first, hit), 1, "first hit: full damage")
	check_eq(_count(second, hit * 0.75), 1, "first bounce: 75%")
	check_eq(_count(third, hit * 0.75 * 0.75), 1, "second bounce: 75% of that")
	check(MageBurn.find(third, p) != null, "the bounces burn too")


func test_fireball_explosive_spec() -> void:
	var p := _mage()
	var slot := _learn(p, &"fireball", 5, 1)
	var target := _enemy(Vector3(5, 0, 0))
	var close := _enemy(Vector3(6.5, 0, 1.0))
	var away := _enemy(Vector3(5, 0, 6))
	var ctx := _ctx(p, &"fireball")
	check_near(ctx.num("splash_radius"), 2.5, 0.0001, "2.5 m blast")
	check(p.abilities.try_cast(slot), "cast")
	_fly()
	var hit := _spell(p, 6.0, 1.0, &"fire", ctx.num("power"))
	# (Rank III's second fireball goes to the neighbour, whose blast catches the target.)
	check_eq(_count(target, hit), 1, "the target takes the full hit")
	check_eq(_count(close, hit * 0.6), 1, "the neighbour is caught in the blast for 60%")
	check_eq(_count(target, hit * 0.6), 1, "and the other way round")
	check(MageBurn.find(close, p) != null, "and burns")
	check_eq(away.fake_hits(), 0, "6 m away is safe")


func test_fireball_bolts_go_at_wave_end() -> void:
	var p := _mage()
	var slot := _learn(p, &"fireball")
	_enemy(Vector3(9, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	check_eq(_bolts().size(), 1, "in flight")
	p.end_wave()
	check_eq(_bolts().size(), 0, "removed before the intermission")


# --- Burns ----------------------------------------------------------------------------------

func test_burns_stack_per_caster_and_stop_with_the_enemy() -> void:
	var p := _mage()
	var other := _mage(Vector3(2, 0, 0), 1)
	var e := _enemy(Vector3(5, 0, 0))
	var b := MageBurn.apply(e, p, 6.0, 3.0)
	check_near(b.remaining(), 6.0, 0.0001, "6 damage to come")
	_step(1.0)
	check_near(b.dealt, 2.0, 0.01, "a third burnt after 1 sec")
	var again := MageBurn.apply(e, p, 6.0, 3.0)
	check(again == b, "one burn per caster")
	check_near(b.remaining(), 10.0, 0.01, "the rest is added and the clock restarts")
	check(MageBurn.apply(e, other, 3.0, 3.0) != b, "another Mage burns separately")
	e.fake_dead = true
	_step(0.1)
	check(MageBurn.find(e, p) == null, "a dead enemy stops burning")
	check(MageBurn.apply(_enemy(Vector3(3, 0, 3)), p, 0.0, 3.0) == null, "nothing to burn")


# --- Frost Nova -----------------------------------------------------------------------------

func test_frost_nova_waits_for_an_enemy_to_touch_the_hero() -> void:
	var p := _mage()
	_learn(p, &"frost_nova")
	var effect := _effect(p, &"frost_nova")
	var e := _enemy(Vector3(2.5, 0, 0))
	check(not effect.wants_auto_cast(_ctx(p, &"frost_nova")), "2.5 m away: not yet")
	_step(0.6, [p])
	check_eq(e.fake_stun_count, 0, "no nova")
	e.global_position = Vector3(1.1, 0, 0)
	EnemyGrid.mark_dirty()
	check(effect.wants_auto_cast(_ctx(p, &"frost_nova")), "touching")
	_step(0.3, [p])
	check_eq(e.fake_stun_count, 1, "the nova went off by itself")
	check(e.fake_hits() == 1, "and hurt it")


func test_frost_nova_freezes_and_damages_everything_around() -> void:
	var p := _mage()
	var slot := _learn(p, &"frost_nova")
	var touching := _enemy(Vector3(0.9, 0, 0))
	var around := _enemy(Vector3(-3.0, 0, 1.0))
	var outside := _enemy(Vector3(0, 0, 5.0))
	check(p.abilities.try_cast(slot), "cast")
	var hit := _spell(p, 2.0, 0.3, &"frost")
	for e: Fakes.FakeEnemy in [touching, around]:
		check_eq(e.fake_hits(), 1, "hit")
		check_near(e.fake_damage_log[0], hit, 0.001, "frost damage")
		check_eq(e.fake_stun_count, 1, "frozen")
		check(_ice(e, p) != null, "ice on it")
		check_near(_ice(e, p).left, 1.5, 0.001, "for 1.5 sec")
	check_eq(outside.fake_hits(), 0, "5 m away is safe")
	check(_ice(outside, p) == null, "and not frozen")
	_step(1.6)
	check(_ice(touching, p) == null, "the ice melts")
	check_eq(touching.fake_hits(), 1, "without shattering at Rank I")


func test_frost_nova_power_and_rank_three() -> void:
	var p := _mage()
	var slot := _learn(p, &"frost_nova", 3)
	var e := _enemy(Vector3(1, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	check_near(e.fake_damage_log[0], _spell(p, 2.0, 0.3, &"frost", 1.25), 0.001, "+25% at Rank III")
	check_near(_ice(e, p).left, 2.5, 0.001, "Rank III: +1 sec freeze")
	check_near(p.abilities.cooldown_of(_ability(&"frost_nova")), 9.0, 0.001, "-10% cooldown")


func test_frost_nova_shatter_spec() -> void:
	var p := _mage()
	var slot := _learn(p, &"frost_nova", 5, 0)
	var frozen := _enemy(Vector3(1, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	var hit := frozen.fake_damage_log[0]
	var late := _enemy(Vector3(1.8, 0, 0.6))  # walks in after the nova, next to the ice
	check_eq(frozen.fake_hits(), 1, "nova hit")
	_step(2.4)
	check_eq(frozen.fake_hits(), 1, "no shatter while frozen (2.5 sec)")
	_step(0.2)
	check_eq(frozen.fake_hits(), 2, "the ice shatters")
	check_near(frozen.fake_damage_log[1], hit * 2.0, 0.001, "for 200% of the nova")
	check_eq(late.fake_hits(), 1, "the burst hits a neighbour within 1.5 m")


func test_frost_nova_shatter_hits_each_enemy_once_per_nova() -> void:
	var p := _mage()
	var slot := _learn(p, &"frost_nova", 5, 0)
	var ring := _cluster(Vector3.ZERO, 8, 0.95)  # a tight clump: every ice touches every enemy
	check(p.abilities.try_cast(slot), "cast")
	var hit := ring[0].fake_damage_log[0]
	_step(2.6)
	for e in ring:
		check(_ice(e, p) == null, "melted")
		check_eq(e.fake_hits(), 2, "the nova + one shatter, however many frozen neighbours burst")
		if e.fake_hits() == 2:
			check_near(e.fake_damage_log[1], hit * 2.0, 0.001, "200% of the nova")
	# The next nova shatters anew.
	p.abilities.set_cooldown(_ability(&"frost_nova"), 0.0)
	check(p.abilities.try_cast(slot), "second nova")
	_step(2.6)
	check_eq(ring[0].fake_hits(), 4, "one more nova + shatter")


func test_frost_nova_frozen_ground_spec() -> void:
	var p := _mage()
	var slot := _learn(p, &"frost_nova", 5, 1)
	_enemy(Vector3(1, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	var areas := _areas()
	check_eq(areas.size(), 1, "frozen ground")
	var area := areas[0]
	check_near(area.duration, 4.0, 0.001, "4 sec")
	check_near(area.slow_pct, 60.0, 0.001, "slows by 60%")
	check_near(area.stun, 1.0, 0.001, "freezes newcomers for 1 sec")
	check_eq(area.school, &"frost", "frost")
	var newcomer := _enemy(Vector3(-2, 0, 0))
	_step(0.3)
	check_eq(newcomer.fake_stun_count, 1, "stepping in freezes")
	check(newcomer.is_slowed(), "and slows")
	p.end_wave()
	check_eq(_areas().size(), 0, "gone at wave end")


func test_frost_nova_is_refunded_with_nobody_in_reach() -> void:
	var p := _mage()
	var slot := _learn(p, &"frost_nova")
	check(not p.abilities.try_cast(slot), "nothing to freeze")
	check(p.abilities.is_ready(slot), "no cooldown spent")


# --- Arcane Missiles ------------------------------------------------------------------------

## Hits per enemy of one volley at three enemies with run seed [param seed_value].
func _volley_targets(seed_value: int) -> Array[int]:
	RunState.start_run(1, seed_value)
	var p := _mage()
	var slot := _learn(p, &"arcane_missiles")
	var enemies := [_enemy(Vector3(5, 0, 0)), _enemy(Vector3(-5, 0, 1)), _enemy(Vector3(0, 0, 6))]
	check(p.abilities.try_cast(slot), "cast")
	_step(1.6, [p])
	var order: Array[int] = []
	for e: Fakes.FakeEnemy in enemies:
		order.append(e.fake_hits())
	for c in world.get_children():
		c.free()
	EnemyGrid.mark_dirty()
	Enemy.invalidate_player_cache()
	return order


func test_arcane_missiles_volley_at_random_targets() -> void:
	var p := _mage()
	var slot := _learn(p, &"arcane_missiles")
	var enemies := [_enemy(Vector3(5, 0, 0)), _enemy(Vector3(-5, 0, 1)), _enemy(Vector3(0, 0, 6))]
	var effect := _effect(p, &"arcane_missiles") as MageArcaneMissiles
	check(p.abilities.try_cast(slot), "cast")
	check(effect.is_firing(), "a volley")
	check_eq(effect.launched, 1, "the first missile leaves at once")
	_step(0.13, [p])
	check_eq(effect.launched, 2, "then one every 0.12 sec")
	_step(1.6, [p])
	check(not effect.is_firing(), "volley done")
	check_eq(effect.launched, 5, "5 missiles")
	var hits := 0
	var struck := 0
	var each := _spell(p, 1.5, 0.35, &"arcane", 1.0, 0.4)
	for e: Fakes.FakeEnemy in enemies:
		hits += e.fake_hits()
		struck += 1 if e.fake_hits() > 0 else 0
		for d in e.fake_damage_log:
			check_near(d, each, 0.001, "arcane damage per missile")
	check_eq(hits, 5, "every missile hits")
	check(struck >= 2, "spread over random targets (%d)" % struck)


func test_arcane_missiles_targets_follow_the_run_rng() -> void:
	var a := _volley_targets(99)
	var b := _volley_targets(99)
	check_eq(a, b, "same seed, same targets")


func test_arcane_missiles_rank_three_and_power() -> void:
	var p := _mage()
	var slot := _learn(p, &"arcane_missiles", 4)
	var e := _enemy(Vector3(6, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	_step(2.0, [p])
	check_eq(e.fake_hits(), 7, "Rank III: 7 missiles")
	check_near(e.fake_damage_log[0], _spell(p, 1.5, 0.35, &"arcane", 1.5, 0.4), 0.001, "Rank IV: +50%")


func test_arcane_missiles_barrage_spec() -> void:
	var p := _mage()
	var slot := _learn(p, &"arcane_missiles", 5, 0)
	var target := _enemy(Vector3(6, 0, 0))
	var close := _enemy(Vector3(6.6, 0, 1.0))
	check(p.abilities.try_cast(slot), "cast")
	_step(2.0, [p])
	var each := _spell(p, 1.5, 0.35, &"arcane", 1.5, 0.4)
	check(target.fake_hits() + close.fake_hits() >= 14, "every missile also bursts (%d hits)" % (target.fake_hits() + close.fake_hits()))
	var splashed := 0
	for d in target.fake_damage_log + close.fake_damage_log:
		if is_equal_approx(d, each * 0.5):
			splashed += 1
	check_eq(splashed, 7, "7 bursts at 50%")


func test_arcane_missiles_focused_spec() -> void:
	var p := _mage()
	var slot := _learn(p, &"arcane_missiles", 5, 1)
	var tough := _enemy(Vector3(-7, 0, 0), 5000.0)
	var weak := _enemy(Vector3(3, 0, 0), 50.0)
	check(p.abilities.try_cast(slot), "cast")
	_step(2.0, [p])
	check_eq(tough.fake_hits(), 7, "every missile seeks the toughest enemy")
	check_eq(weak.fake_hits(), 0, "even past a nearer one")
	check_near(tough.fake_damage_log[0], _spell(p, 1.5, 0.35, &"arcane", 1.5, 0.4) * 1.4, 0.001, "+40% damage")


func test_arcane_missiles_stop_when_the_hero_goes_down_and_at_wave_end() -> void:
	var p := _mage()
	var slot := _learn(p, &"arcane_missiles")
	var effect := _effect(p, &"arcane_missiles") as MageArcaneMissiles
	_enemy(Vector3(6, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	_down(p)
	check(not effect.is_firing(), "the volley stops when downed")
	p.revive(1.0)
	p.abilities.set_cooldown(_ability(&"arcane_missiles"), 0.0)
	check(p.abilities.try_cast(slot), "cast again")
	check(not effect.can_cast(_ctx(p, &"arcane_missiles")), "no second volley on top")
	p.end_wave()
	check(not effect.is_firing(), "and at wave end")
	check_eq(_bolts().size(), 0, "missiles in flight removed")


# --- Ice Barrier ----------------------------------------------------------------------------

func test_ice_barrier_shields_and_absorbs() -> void:
	var p := _mage()
	_learn(p, &"ice_barrier")
	_step(0.5, [p])
	check_eq(p.procs.shield_hp, 0.0, "no enemy around: no barrier")
	var e := _enemy(Vector3(9, 0, 0))
	_step(0.3, [p])
	var amount := 4.0 + 0.5 * p.stats.get_raw(Stats.INTELLECT) + 0.5 * p.stats.get_raw(Stats.SPELL_POWER)
	check_near(p.procs.shield_hp, amount, 0.001, "shield: 4 + 0.5 x Intellect + 0.5 x Spell Power")
	check(MageBarrierBubble.of(p) != null, "an icy bubble")
	var hp := p.hp
	p.invulnerable_left = 0.0
	p.take_damage(1.0, CombatMath.KIND_PROJECTILE, e)
	check_eq(p.hp, hp, "absorbed")
	check(p.procs.shield_hp < amount, "the barrier wore down")
	var effect := _effect(p, &"ice_barrier") as MageIceBarrier
	check(effect.active, "still up")
	check(not effect.can_cast(_ctx(p, &"ice_barrier")), "no recast while it holds")


func test_ice_barrier_is_recast_once_broken_and_off_cooldown() -> void:
	var p := _mage()
	var slot := _learn(p, &"ice_barrier")
	var e := _enemy(Vector3(9, 0, 0))
	_tough(p)
	check(p.abilities.try_cast(slot), "cast")
	var effect := _effect(p, &"ice_barrier") as MageIceBarrier
	p.invulnerable_left = 0.0
	p.take_damage(100.0, CombatMath.KIND_PROJECTILE, e)
	_step(0.1, [p])
	check(not effect.active, "broken")
	check_eq(effect.breaks, 1, "one break")
	check_eq(p.procs.shield_hp, 0.0, "no shield")
	check(not p.abilities.is_ready(slot), "cooling down")
	_step(11.0, [p])
	check_eq(p.procs.shield_hp, 0.0, "still cooling down (12 sec)")
	_step(1.2, [p])
	check(p.procs.shield_hp > 0.0, "recast by itself")


func test_ice_barrier_and_other_shields_keep_their_own_timers() -> void:
	var p := _mage()
	var slot := _learn(p, &"ice_barrier")
	_enemy(Vector3(9, 0, 0))
	var effect := _effect(p, &"ice_barrier") as MageIceBarrier
	p.procs.add_shield(5.0, 8.0)  # a teammate's Holy Bulwark, an item's when-struck shield ...
	check(effect.can_cast(_ctx(p, &"ice_barrier")), "another shield does not block the barrier")
	check(p.abilities.try_cast(slot), "cast")
	var amount := effect.strength
	check_near(p.procs.shield_hp, 5.0 + amount, 0.001, "shield_hp is the total absorb")
	check_near(p.procs.shield_of(MageIceBarrier.SHIELD_SOURCE), amount, 0.001, "the barrier's own entry")
	check(not effect.can_cast(_ctx(p, &"ice_barrier")), "no recast while the barrier holds")
	check_near(p.procs.absorb(3.0), 0.0, 0.001, "absorbed")
	check_near(p.procs.shield_of(MageIceBarrier.SHIELD_SOURCE), amount, 0.001,
			"the shield that runs out first soaks first")
	p.procs._physics_process(9.0)
	check_near(p.procs.shield_hp, amount, 0.001, "the 8 s shield expired on its own timer")
	p.procs.add_shield(4.0, 2.0)
	p.procs._physics_process(3.0)
	check_near(p.procs.shield_hp, amount, 0.001, "a shield added on top of the barrier still expires")
	_step(DT, [p])
	check(effect.active, "the barrier still holds")
	check_eq(effect.breaks, 0, "never broken")
	check(MageBarrierBubble.of(p) != null, "and still shows")


func test_ice_barrier_power() -> void:
	var p := _mage()
	var slot := _learn(p, &"ice_barrier", 2)
	_enemy(Vector3(9, 0, 0))
	var ctx := _ctx(p, &"ice_barrier")
	var base := 4.0 + 0.5 * p.stats.get_raw(Stats.INTELLECT) + 0.5 * p.stats.get_raw(Stats.SPELL_POWER)
	check_near(MageIceBarrier.shield_amount(ctx), base * 1.25, 0.001, "+25% shield at Rank II")
	check(p.abilities.try_cast(slot), "cast")
	check_near(p.procs.shield_hp, base * 1.25, 0.001, "on the hero")


func test_ice_barrier_rank_three_chills_attackers() -> void:
	var p := _mage()
	var slot := _learn(p, &"ice_barrier", 3)
	var biter := _enemy(Vector3(0.9, 0, 0))
	var bystander := _enemy(Vector3(5, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	_step(0.1, [p])
	check(not biter.is_slowed(), "nothing struck yet")
	p.invulnerable_left = 0.0
	p.take_damage(0.5, CombatMath.KIND_MELEE, biter)
	_step(DT, [p])
	check(biter.is_slowed(), "the attacker is chilled")
	check_near(biter.slow_pct, 50.0, 0.001, "by 50%")
	check(not bystander.is_slowed(), "enemies further away are not")


func test_ice_barrier_shattering_spec() -> void:
	var p := _mage()
	var slot := _learn(p, &"ice_barrier", 5, 0)
	var biter := _enemy(Vector3(1, 0, 0))
	var near := _enemy(Vector3(-3, 0, 0))
	var far := _enemy(Vector3(8, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	var effect := _effect(p, &"ice_barrier") as MageIceBarrier
	var strength := effect.strength
	_tough(p)
	p.invulnerable_left = 0.0
	p.take_damage(1000.0, CombatMath.KIND_MELEE, biter)
	check(not p.downed, "survived")
	_step(DT, [p])
	check_eq(effect.breaks, 1, "broken")
	for e: Fakes.FakeEnemy in [biter, near]:
		check_eq(e.fake_hits(), 1, "the barrier explodes on enemies within 3.5 m")
		check_near(e.fake_damage_log[0], strength, 0.001, "for its strength")
		check(_ice(e, p) != null, "and freezes them")
	check_eq(far.fake_hits(), 0, "8 m away is safe")


func test_ice_barrier_ice_block_spec() -> void:
	var p := _mage()
	var slot := _learn(p, &"ice_barrier", 5, 1)
	var e := _enemy(Vector3(1, 0, 0))
	_tough(p)
	check(p.abilities.try_cast(slot), "cast")
	p.invulnerable_left = 0.0
	p.take_damage(1000.0, CombatMath.KIND_MELEE, e)
	check(not p.downed, "survived the blow")
	_step(DT, [p])
	check(p.invulnerable_left >= 1.5 - DT * 2.0, "encased in ice: immune for 1.5 sec")
	check(p.get_node_or_null(^"IceBlock") != null, "an ice block around the hero")
	var hp := p.hp
	p.take_damage(5.0, CombatMath.KIND_MELEE, e)
	check_eq(p.hp, hp, "no damage inside the ice")
	p.end_wave()
	var block := p.get_node_or_null(^"IceBlock")
	check(block == null or block.is_queued_for_deletion(), "the ice goes at wave end")


func test_ice_barrier_cleanup() -> void:
	var p := _mage()
	var slot := _learn(p, &"ice_barrier")
	_enemy(Vector3(5, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	var effect := _effect(p, &"ice_barrier") as MageIceBarrier
	p.end_wave()
	check(MageBarrierBubble.of(p) == null, "no bubble in the market")
	check(not effect.active, "inactive")
	p.begin_wave()
	check_eq(p.procs.shield_hp, 0.0, "shields are cleared at wave start")
	check(p.abilities.try_cast(slot), "cast again")
	check_eq(p.abilities.forget(slot) >= 0, true, "forget")
	check(MageBarrierBubble.of(p) == null, "forgetting removes the bubble")
	check(not effect.active, "and the barrier state")
