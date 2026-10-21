extends TestCase
## M9 SEASONINGS, cast level: test_m9_seasonings.gd proves for all 56 that every mod moves the number its ability
## reads; these casts prove the number matters where that is not obvious – a replaced flag or value, a gate, a
## multi-part amount, a charge count, a pet or a totem that reads the numbers on its own. Each test casts the
## ability without and then with the Seasoning (same hero, same enemies) and compares what happens in the world.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0


## A fake enemy that dies at 0 HP and records the slows and stuns it is given.
class Dummy extends Fakes.FakeEnemy:
	var slows: Array[float] = []
	var stuns: Array[float] = []

	func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null,
			knockback: Vector3 = Vector3.ZERO) -> void:
		super.take_damage(amount, is_crit, attacker, knockback)
		if hp <= 0.0:
			fake_dead = true

	func apply_stun(duration: float) -> void:
		super.apply_stun(duration)
		stuns.append(duration)

	func apply_slow(pct: float, duration: float) -> void:
		slows.append(pct)
		super.apply_slow(pct, duration)

	func total() -> float:
		var t := 0.0
		for d in fake_damage_log:
			t += d
		return t


var world: Node3D


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 4711)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)
	EnemyGrid.mark_dirty()


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	PlayerManager.clear()
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


# --- Helpers ------------------------------------------------------------------------------------------

func _hero(class_id: StringName, pos: Vector3 = Vector3.ZERO, index: int = 0) -> Player:
	var p := Fakes.spawn_player(world, index, class_id, pos)
	p.stats.set_source(&"test", {Stats.CRIT: -500.0, Stats.DODGE: -500.0, Stats.STAMINA: 500.0})
	p.hp = p.max_hp()
	p.abilities._physics_process(DT)
	return p


func _enemy(pos: Vector3, hp: float = 100000.0) -> Dummy:
	var e := Dummy.new()
	e.radius = 0.45
	e.max_hp = hp
	e.hp = hp
	e.add_to_group(&"enemies")
	world.add_child(e)
	e.global_position = pos
	EnemyGrid.mark_dirty()
	return e


func _season(p: Player, id: StringName) -> void:
	var s := Db.get_seasoning(id)
	check(s != null, "%s exists" % id)
	p.bonuses.set_effects(Seasonings.SOURCE, Seasonings.effects_for([s] as Array[SeasoningData]))


func _plain(p: Player) -> void:
	p.bonuses.set_effects(Seasonings.SOURCE, [] as Array[Dictionary])


func _learn(p: Player, id: StringName) -> int:
	var ability := Db.get_ability(id)
	var slot := p.abilities.slot_of(id)
	if slot < 0:
		slot = p.abilities.learn(ability)
	check(slot >= 0, "%s is learned" % id)
	return slot


func _fx(p: Player, id: StringName) -> AbilityEffect:
	return p.abilities.effect_for(Db.get_ability(id))


func _ctx(p: Player, id: StringName) -> AbilityContext:
	EnemyGrid.mark_dirty()
	return p.abilities.build_context(Db.get_ability(id))


func _step(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p.abilities._physics_process(DT)
		for n in tree.get_nodes_in_group(&"projectiles"):
			if not n.is_queued_for_deletion():
				n._physics_process(DT)
		for n in tree.get_nodes_in_group(&"ability_areas"):
			if not n.is_queued_for_deletion():
				n._physics_process(DT)
		t += DT


func _rage(p: Player, amount: float) -> ClassResource:
	var r := p.abilities.get_resource(&"rage")
	r.value = amount
	return r


func _hit(p: Player) -> float:
	return CombatMath.weapon_hit_damage(p.main_hand, p.stats)


func _areas() -> Array[AbilityArea]:
	var out: Array[AbilityArea] = []
	for n in tree.get_nodes_in_group(&"ability_areas"):
		if n is AbilityArea and not n.is_queued_for_deletion():
			out.append(n as AbilityArea)
	return out


# --- Warrior ------------------------------------------------------------------------------------------

func test_smoked_paprika_slows_and_costs_more_rage() -> void:
	var p := _hero(&"warrior")
	var e := _enemy(Vector3(2.0, 0.0, 0.0))
	var slot := _learn(p, &"whirlwind")
	_rage(p, 40.0)
	check(p.abilities.try_cast(slot), "a plain Whirlwind costs 40")
	check(e.slows.is_empty(), "and slows nobody")
	_step(p, 1.2)
	_plain(p)
	p.abilities.begin_wave()
	_season(p, &"ssn_smoked_paprika")
	_rage(p, 47.0)
	check(not p.abilities.try_cast(slot), "47 Rage is not enough with the Seasoning")
	_rage(p, 48.0)
	check(p.abilities.try_cast(slot), "48 is")
	check_eq(e.slows.size(), 1, "the first pulse slows the enemy")
	check_near(e.slows[0], 35.0, 0.001, "by 35%")
	var spin := (_fx(p, &"whirlwind") as WarriorWhirlwind).spin()
	check_near(spin.slow_duration, 2.0, 0.001, "for 2 sec")


func test_cracked_pepper_hits_harder_and_reaches_less() -> void:
	var p := _hero(&"warrior")
	_enemy(Vector3(2.0, 0.0, 0.0))
	var slot := _learn(p, &"whirlwind")
	var fx := _fx(p, &"whirlwind") as WarriorWhirlwind
	_rage(p, 100.0)
	check(p.abilities.try_cast(slot), "plain cast")
	var base_hit := fx.spin().hit_pct
	var base_radius := fx.spin().radius
	_step(p, 1.2)
	_plain(p)
	p.abilities.begin_wave()
	_season(p, &"ssn_cracked_pepper")
	_rage(p, 100.0)
	check(p.abilities.try_cast(slot), "cast with the Seasoning")
	check_near(fx.spin().hit_pct / base_hit, 190.0 / 150.0, 0.0001, "40 points more weapon damage per hit")
	check_near(base_radius - fx.spin().radius, 0.6, 0.0001, "0.6 m less reach")


func test_horseradish_kick_finishes_enemies_up_to_30_percent() -> void:
	var p := _hero(&"warrior")
	var slot := _learn(p, &"execute")
	var low := _enemy(Vector3(1.5, 0.0, 0.0), 1000.0)
	low.hp = 250.0  # 25%: above Execute's 20%, below 30%
	check(p.abilities.try_cast(slot), "a plain Execute")
	check(not low.fake_dead and low.fake_hits() == 1, "only strikes it: not executed at 25%")
	var plain_hit := low.fake_damage_log[0]
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_horseradish_kick")
	low.hp = 250.0
	low.fake_damage_log.clear()
	check(p.abilities.try_cast(slot), "Execute with Horseradish Kick")
	check(low.fake_dead, "an enemy at 25% is finished")
	check_near(plain_hit, _hit(p) * 3.0, 0.01, "(the plain strike was 300% weapon damage)")
	var other := _enemy(Vector3(1.5, 0.0, 0.5), 1000.0)
	_enemy(Vector3(30.0, 0.0, 0.0))
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	check(p.abilities.try_cast(slot), "a third cast")
	check_near(other.fake_damage_log[0], _hit(p) * 2.0, 0.01, "a healthy enemy takes the weaker 200% strike")


func test_bay_leaf_gives_a_second_charge() -> void:
	var p := _hero(&"warrior")
	_enemy(Vector3(20.0, 0.0, 0.0))
	var slot := p.abilities.slot_of(&"charge")
	check(slot >= 0, "Charge is a core ability")
	var charge := Db.get_ability(&"charge")
	check_eq(p.abilities.charges_max(charge), 1, "one charge")
	_season(p, &"ssn_bay_leaf")
	check_eq(p.abilities.charges_max(charge), 2, "two with Bay Leaf")
	check(p.abilities.try_cast(slot), "the first Charge")
	_step(p, 0.6)
	check(p.abilities.try_cast(slot), "a second one right after, without waiting")
	_step(p, 0.6)
	check(not p.abilities.try_cast(slot), "but not a third")
	check_near(p.abilities.params_for(charge)["distance"], 5.0, 0.001, "each one rushes 2 m less")


func test_cayenne_rush_ends_in_a_shockwave() -> void:
	var p := _hero(&"warrior")
	_enemy(Vector3(20.0, 0.0, 0.0))
	var slot := p.abilities.slot_of(&"charge")
	var fx := _fx(p, &"charge") as WarriorCharge
	check(p.abilities.try_cast(slot), "a plain Charge")
	check_near(fx._shock_radius, 0.0, 0.0001, "has no shockwave")
	_step(p, 1.0)
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_cayenne_rush")
	check(p.abilities.try_cast(slot), "Charge with the Seasoning")
	check_near(fx._shock_radius, 3.0, 0.0001, "ends in a 3 m shockwave")
	check_near(fx._shock_stun, 0.5, 0.0001, "that stuns for 0.5 sec")
	check_near(p.abilities.cooldown_of(Db.get_ability(&"charge")), 10.0, 0.001, "and recharges 25% slower (8 -> 10 s)")


func test_sea_salt_pays_rage_per_enemy_hit() -> void:
	var p := _hero(&"warrior")
	var slot := _learn(p, &"thunder_clap")
	for i in 3:
		_enemy(Vector3(1.5 + 0.3 * float(i), 0.0, 0.0))
	var rage := _rage(p, 0.0)
	check(p.abilities.try_cast(slot), "a plain Ground Slam")
	var plain := rage.value
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_sea_salt")
	rage.value = 0.0
	check(p.abilities.try_cast(slot), "Ground Slam with Sea Salt")
	check_near(rage.value - plain, 12.0, 0.01, "4 Rage for each of the three enemies hit")
	check_near(p.abilities.cooldown_of(Db.get_ability(&"thunder_clap")), 7.2, 0.001, "recharges 20% slower")


func test_black_garlic_strikes_attackers_back() -> void:
	var p := _hero(&"warrior")
	var attacker := _enemy(Vector3(1.0, 0.0, 0.0))
	var slot := _learn(p, &"shield_wall")
	p.abilities.try_cast(slot)
	p.invulnerable_left = 0.0
	p.take_damage(5.0, CombatMath.KIND_PROJECTILE, attacker)
	check_eq(attacker.fake_hits(), 0, "the plain wall has no thorns")
	p.abilities.end_wave()
	p.abilities.begin_wave()
	_season(p, &"ssn_black_garlic")
	p.abilities.try_cast(slot)
	p.invulnerable_left = 0.0
	p.take_damage(5.0, CombatMath.KIND_PROJECTILE, attacker)
	check_eq(attacker.fake_hits(), 1, "the attacker is struck back")
	check_near(attacker.fake_damage_log[0], _hit(p), 0.01, "for 100% weapon damage")
	check_near(float(p.abilities.params_for(Db.get_ability(&"shield_wall"))["reduction"]), 35.0, 0.001, "behind a wall that blocks 15 points less")


func test_ginger_snap_leaves_a_crater() -> void:
	var p := _hero(&"warrior")
	_enemy(Vector3(5.0, 0.0, 0.0))
	var slot := _learn(p, &"heroic_leap")
	var leap := _fx(p, &"heroic_leap") as WarriorHeroicLeap
	check(p.abilities.try_cast(slot), "a plain leap")
	_step(p, 0.9)
	check(leap.last_crater == null or not is_instance_valid(leap.last_crater), "leaves no crater")
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	p.global_position = Vector3.ZERO
	_season(p, &"ssn_ginger_snap")
	check(p.abilities.try_cast(slot), "a leap with Ginger Snap")
	_step(p, 0.9)
	var crater := leap.last_crater
	check(crater != null and is_instance_valid(crater), "a crater is left behind")
	if crater != null and is_instance_valid(crater):
		check_near(crater.slow_pct, 50.0, 0.001, "slows by 50%")
		check_near(crater.duration, 3.0, 0.001, "for 3 sec")


# --- Mage ---------------------------------------------------------------------------------------------

func _mana(p: Player) -> void:
	p.abilities.get_resource(&"mana").value = 1000.0


func _bolts() -> Array[MageBolt]:
	var out: Array[MageBolt] = []
	for n in tree.get_nodes_in_group(&"projectiles"):
		if n is MageBolt and not n.is_queued_for_deletion():
			out.append(n as MageBolt)
	return out


func test_cinnamon_stick_lengthens_the_burn_and_softens_the_hit() -> void:
	var p := _hero(&"mage")
	_enemy(Vector3(4.0, 0.0, 0.0))
	var slot := _learn(p, &"fireball")
	_mana(p)
	var plain_damage := MageSpell.damage_from(_ctx(p, &"fireball"), MageSpell.FIRE)
	check(p.abilities.try_cast(slot), "a plain Fireball")
	var plain := _bolts()[0]
	check_near(plain.burn_pct, 50.0, 0.001, "burns for 50%")
	check_near(plain.burn_duration, 3.0, 0.001, "over 3 sec")
	for b in _bolts():
		b.free()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_cinnamon_stick")
	var damage := MageSpell.damage_from(_ctx(p, &"fireball"), MageSpell.FIRE)
	check_near(damage / plain_damage, 0.85, 0.0001, "15% less overall")
	check(p.abilities.try_cast(slot), "Fireball with Cinnamon Stick")
	var bolt := _bolts()[0]
	check_near(bolt.burn_pct, 80.0, 0.001, "burns for 80%")
	check_near(bolt.burn_duration, 4.0, 0.001, "over 4 sec")


func test_vanilla_bean_makes_the_whole_shield_bigger() -> void:
	var p := _hero(&"mage")
	p.stats.set_source(&"intellect", {Stats.INTELLECT: 40.0, Stats.SPELL_POWER: 20.0})
	_learn(p, &"ice_barrier")
	var plain := MageIceBarrier.shield_amount(_ctx(p, &"ice_barrier"))
	check(plain > 0.0, "a shield")
	_season(p, &"ssn_vanilla_bean")
	var amount := MageIceBarrier.shield_amount(_ctx(p, &"ice_barrier"))
	check_near(amount / plain, 1.6, 0.0001, "60% more in all, Intellect and Spell Power parts included")
	check_near(p.abilities.cooldown_of(Db.get_ability(&"ice_barrier")), 15.6, 0.001, "recharging 30% slower")


func test_mint_leaf_and_star_anise_change_the_hailstorm() -> void:
	var p := _hero(&"mage")
	_enemy(Vector3(4.0, 0.0, 0.0))
	var slot := p.abilities.slot_of(&"blizzard")
	check(slot >= 0, "Hailstorm is core")
	_mana(p)
	check(p.abilities.try_cast(slot), "a plain cast")
	var area := _areas()[0]
	var plain_slow := area.slow_pct
	var plain_tick := area.damage_per_tick
	var plain_radius := area.radius
	var plain_duration := area.duration
	for a in _areas():
		a.free()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_mint_leaf")
	check(p.abilities.try_cast(slot), "with Mint Leaf")
	area = _areas()[0]
	check_near(area.slow_pct - plain_slow, 20.0, 0.001, "20 points more slow")
	check_near(area.damage_per_tick / plain_tick, 0.85, 0.0001, "15% less damage per tick")
	for a in _areas():
		a.free()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_star_anise")
	check(p.abilities.try_cast(slot), "with Star Anise")
	area = _areas()[0]
	check_near(area.radius - plain_radius, 1.0, 0.001, "1 m wider")
	check_near(plain_duration - area.duration, 0.5, 0.001, "0.5 sec shorter")


func test_saffron_thread_gives_a_second_blink_that_jumps_less() -> void:
	var p := _hero(&"mage")
	var slot := p.abilities.slot_of(&"blink")
	var blink := Db.get_ability(&"blink")
	check_eq(p.abilities.charges_max(blink), 1, "one Blink")
	_season(p, &"ssn_saffron_thread")
	check_eq(p.abilities.charges_max(blink), 2, "two")
	p.facing = Vector3.RIGHT
	check(p.abilities.try_cast(slot), "the first Blink")
	check_near(p.global_position.x, 4.0, 0.05, "jumps 4 m instead of 6")
	check(p.abilities.try_cast(slot), "a second one at once")
	check_near(p.global_position.x, 8.0, 0.05, "4 m further")
	check(not p.abilities.try_cast(slot), "not a third")
	check_near(p.abilities.params_for(blink)["invulnerable"], 0.2, 0.0001, "protecting 0.2 sec instead of 0.4")


func test_chili_flake_burns_more_and_takes_longer() -> void:
	var p := _hero(&"mage")
	_enemy(Vector3(4.0, 0.0, 0.0))
	var slot := _learn(p, &"pyroblast")
	var fx := _fx(p, &"pyroblast") as MagePyroblast
	_mana(p)
	check(p.abilities.try_cast(slot), "a plain Magma Bolt")
	check_near(fx.windup_left, 1.0, 0.0001, "gathers for 1 sec")
	_step(p, 1.1)
	check_near(fx.last_bolt.burn_pct, 30.0, 0.001, "burning for 30% of the hit")
	for b in _bolts():
		b.free()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_chili_flake")
	check(p.abilities.try_cast(slot), "with Chili Flake")
	check_near(fx.windup_left, 1.4, 0.0001, "gathers for 1.4 sec")
	_step(p, 1.5)
	check_near(fx.last_bolt.burn_pct, 70.0, 0.001, "burning for 70% of the hit")


func test_juniper_berry_lands_sooner_and_wider() -> void:
	var p := _hero(&"mage")
	for e in 5:
		_enemy(Vector3(4.0 + 0.4 * float(e), 0.0, 0.0))
	var slot := _learn(p, &"meteor")
	_mana(p)
	check(p.abilities.try_cast(slot), "a plain Meteor")
	var plain := _strikes()[0]
	var plain_fall := plain.fall_time
	var plain_radius := plain.radius
	for s in _strikes():
		s.free()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_juniper_berry")
	check(p.abilities.try_cast(slot), "Meteor with Juniper Berry")
	var strike := _strikes()[0]
	check_near(plain_fall - strike.fall_time, 0.3, 0.001, "lands 0.3 sec sooner")
	check_near(strike.ground_radius - plain_radius, 0.8, 0.001, "and burns a wider patch")
	check_near(p.abilities.cooldown_of(Db.get_ability(&"meteor")), 19.2, 0.001, "recharging 20% slower")


func _strikes() -> Array[MageMeteorStrike]:
	var out: Array[MageMeteorStrike] = []
	for n in tree.get_nodes_in_group(&"ability_areas"):
		if n is MageMeteorStrike and not n.is_queued_for_deletion():
			out.append(n as MageMeteorStrike)
	return out


func test_pink_peppercorn_fires_more_but_weaker_darts() -> void:
	var p := _hero(&"mage")
	_enemy(Vector3(4.0, 0.0, 0.0))
	var slot := _learn(p, &"arcane_missiles")
	var fx := _fx(p, &"arcane_missiles") as MageArcaneMissiles
	_mana(p)
	var plain_damage := MageSpell.damage_from(_ctx(p, &"arcane_missiles"), MageSpell.ARCANE)
	check(p.abilities.try_cast(slot), "a plain volley")
	check_eq(fx.pending, 4, "five darts, one fired at once")
	_step(p, 1.0)
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_pink_peppercorn")
	check(p.abilities.try_cast(slot), "a volley with Pink Peppercorn")
	check_eq(fx.pending, 8, "nine darts, one fired at once")
	check_near(MageSpell.damage_from(_ctx(p, &"arcane_missiles"), MageSpell.ARCANE) / plain_damage, 0.6, 0.0001, "each 40% weaker")


# --- Paladin ------------------------------------------------------------------------------------------

func _holy(p: Player, points: float = 3.0) -> void:
	var hp := p.abilities.get_resource(&"holy_power")
	if hp != null:
		hp.value = points


func test_rosemary_sprig_slows_the_circle_and_shortens_it() -> void:
	var p := _hero(&"paladin")
	var slot := p.abilities.slot_of(&"consecration")
	check(slot >= 0, "Sacred Circle is core")
	check(p.abilities.try_cast(slot), "a plain circle")
	var plain := _areas()[0]
	check_near(plain.slow_pct, 0.0, 0.001, "slows nobody")
	var plain_duration := plain.duration
	for a in _areas():
		a.free()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_rosemary_sprig")
	check(p.abilities.try_cast(slot), "a circle with Rosemary Sprig")
	var area := _areas()[0]
	check_near(area.slow_pct, 35.0, 0.001, "slows by 35%")
	check_near(plain_duration - area.duration, 1.0, 0.001, "1 sec shorter")


func test_thyme_sprig_heals_heroes_in_a_smaller_circle() -> void:
	var p := _hero(&"paladin")
	var slot := p.abilities.slot_of(&"consecration")
	p.abilities.try_cast(slot)
	var plain := _areas()[0]
	check_near(plain.heal_per_tick, 0.0, 0.0001, "a plain circle heals nobody")
	var plain_radius := plain.radius
	for a in _areas():
		a.free()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_thyme_sprig")
	check(p.abilities.try_cast(slot), "a circle with Thyme Sprig")
	var area := _areas()[0]
	check(area.heal_per_tick > 0.0, "it heals each tick")
	check_near(plain_radius - area.radius, 0.7, 0.001, "0.7 m smaller")


func test_sage_leaf_shields_and_heals_less() -> void:
	var p := _hero(&"paladin")
	var slot := p.abilities.slot_of(&"word_of_glory")
	check(slot >= 0, "Call of Valor is core")
	p.hp = p.max_hp() * 0.4
	_holy(p)
	var before := p.hp
	check(p.abilities.try_cast(slot), "a plain cast")
	var plain_heal := p.hp - before
	check_near(p.procs.shield_hp, 0.0, 0.0001, "no shield")
	check(plain_heal / p.max_hp() > 0.25, "heals 25% of max HP and a little more (the flat part)")
	p.hp = p.max_hp() * 0.4
	_holy(p)
	_season(p, &"ssn_sage_leaf")
	before = p.hp
	check(p.abilities.try_cast(slot), "a cast with Sage Leaf")
	check_near((plain_heal - (p.hp - before)) / p.max_hp(), 0.10, 0.001, "heals 10% of max HP less")
	check_near(p.procs.shield_hp / p.max_hp(), 0.12, 0.001, "and shields for 12% of max HP")


func test_fennel_seed_bounces_to_more_enemies_for_less() -> void:
	var p := _hero(&"paladin")
	var slot := _learn(p, &"avengers_shield")
	var row: Array[Dummy] = []
	for i in 7:
		row.append(_enemy(Vector3(3.0 + 2.0 * float(i), 0.0, 0.0)))
	check(p.abilities.try_cast(slot), "a plain Ricochet Shield")
	_step(p, 3.0)
	var hit := 0
	for e in row:
		if e.fake_hits() > 0:
			hit += 1
	check_eq(hit, 3, "three enemies struck")
	var plain_hit := row[0].fake_damage_log[0]
	for e in row:
		e.fake_damage_log.clear()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_fennel_seed")
	check(p.abilities.try_cast(slot), "a cast with Fennel Seed")
	_step(p, 3.0)
	hit = 0
	for e in row:
		if e.fake_hits() > 0:
			hit += 1
	check_eq(hit, 5, "five enemies struck")
	check_near(row[0].fake_damage_log[0] / plain_hit, 0.7, 0.01, "each hit 30 points weaker")


func test_cardamom_pod_stuns_longer_and_recharges_slower() -> void:
	var p := _hero(&"paladin")
	var slot := _learn(p, &"hammer_of_justice")
	var e := _enemy(Vector3(4.0, 0.0, 0.0))
	check(p.abilities.try_cast(slot), "a plain hammer")
	_step(p, 1.5)
	check_eq(e.stuns.size(), 1, "stuns the enemy")
	check_near(e.stuns[0], 1.5, 0.001, "for 1.5 sec")
	e.stuns.clear()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_cardamom_pod")
	check(p.abilities.try_cast(slot), "a hammer with Cardamom Pod")
	_step(p, 1.5)
	check_near(e.stuns[0], 2.5, 0.001, "stuns for 2.5 sec")
	check_near(p.abilities.cooldown_of(Db.get_ability(&"hammer_of_justice")), 10.0, 0.001, "recharging 25% slower")


func test_nutmeg_dust_heals_more_and_strikes_weaker() -> void:
	var p := _hero(&"paladin")
	var slot := _learn(p, &"divine_storm")
	var e := _enemy(Vector3(1.5, 0.0, 0.0))
	p.hp = p.max_hp() * 0.3
	var before := p.hp
	check(p.abilities.try_cast(slot), "a plain whirl")
	var plain_heal := p.hp - before
	var plain_hit := e.fake_damage_log[0]
	check(plain_heal / p.max_hp() >= 0.05, "heals 5% of max HP and the flat part")
	_step(p, 1.0)
	e.fake_damage_log.clear()
	p.hp = p.max_hp() * 0.3
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_nutmeg_dust")
	before = p.hp
	check(p.abilities.try_cast(slot), "a whirl with Nutmeg Dust")
	check_near(((p.hp - before) - plain_heal) / p.max_hp(), 0.04, 0.001, "heals 4% of max HP more")
	check_near(e.fake_damage_log[0] / plain_hit, 0.65, 0.01, "striking 35 points weaker")


func test_clove_pinch_lengthens_the_halo() -> void:
	var p := _hero(&"paladin")
	var slot := _learn(p, &"divine_shield")
	check(p.abilities.try_cast(slot), "a plain Gilded Halo")
	check_near(p.invulnerable_left, 3.0, 0.05, "protects for 3 sec")
	p.abilities.end_wave()
	p.invulnerable_left = 0.0
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_clove_pinch")
	check(p.abilities.try_cast(slot), "a halo with Clove Pinch")
	check_near(p.invulnerable_left, 4.5, 0.05, "protects for 4.5 sec")
	check_near(p.abilities.cooldown_of(Db.get_ability(&"divine_shield")), 54.0, 0.001, "recharging 35% slower")


func test_golden_turmeric_shields_and_guards() -> void:
	var p := _hero(&"paladin")
	var slot := _learn(p, &"lay_on_hands")
	p.hp = p.max_hp() * 0.2
	check(p.abilities.try_cast(slot), "a plain Mending Touch")
	check_near(p.procs.shield_hp, 0.0, 0.0001, "no shield")
	var key := &"lay_on_hands"
	var plain_guard := p.damage_taken_mults.size()
	p.abilities.end_wave()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	p.hp = p.max_hp() * 0.2
	_season(p, &"ssn_golden_turmeric")
	check(p.abilities.try_cast(slot), "a touch with Golden Turmeric")
	check(p.procs.shield_hp > 0.0, "it also shields")
	check_near(p.procs.shield_hp / p.max_hp(), 0.15, 0.02, "for about 15% of max HP")
	check(p.damage_taken_mults.size() > plain_guard, "and cuts the damage taken (%s)" % str(p.damage_taken_mults))
	var mult := 1.0
	for k: StringName in p.damage_taken_mults:
		mult *= p.damage_taken_mults[k]
	check_near(mult, 0.8, 0.001, "by 20%")
	check_near(p.abilities.cooldown_of(Db.get_ability(key)), 78.0, 0.001, "recharging 30% slower")


# --- Rogue --------------------------------------------------------------------------------------------

func _energy(p: Player, amount: float = 100.0) -> ClassResource:
	var r := p.abilities.get_resource(&"energy")
	r.value = amount
	return r


func _blades() -> Array[RogueBlade]:
	var out: Array[RogueBlade] = []
	for n in tree.get_nodes_in_group(&"projectiles"):
		if n is RogueBlade and not n.is_queued_for_deletion():
			out.append(n as RogueBlade)
	return out


func _free_blades() -> void:
	for b in _blades():
		b.free()


func test_sichuan_pepper_throws_more_weaker_knives() -> void:
	var p := _hero(&"rogue")
	var e := _enemy(Vector3(3.0, 0.0, 0.0))
	var slot := p.abilities.slot_of(&"fan_of_knives")
	check(slot >= 0, "Knife Bloom is core")
	_energy(p)
	check(p.abilities.try_cast(slot), "a plain Bloom")
	check_eq(_blades().size(), 10, "ten knives")
	_free_blades()
	var plain := RogueFanOfKnives.knife_damage(p, p.main_hand, 110.0, 0, 20.0)
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_sichuan_pepper")
	_energy(p)
	check(p.abilities.try_cast(slot), "a Bloom with Sichuan Pepper")
	check_eq(_blades().size(), 14, "fourteen knives")
	var weaker := RogueFanOfKnives.knife_damage(p, p.main_hand, 85.0, 0, 20.0)
	check_near(weaker / plain, 85.0 / 110.0, 0.0001, "each 25 points weaker")
	check_near(_blades()[0].damage / plain, 85.0 / 110.0, 0.01, "(and that is what the knife carries)")
	check(e != null, "an enemy stood by")


func test_caraway_seed_costs_energy_for_combo_damage() -> void:
	var p := _hero(&"rogue")
	_enemy(Vector3(3.0, 0.0, 0.0))
	var slot := p.abilities.slot_of(&"fan_of_knives")
	_season(p, &"ssn_caraway_seed")
	_energy(p, 39.0)
	check(not p.abilities.try_cast(slot), "39 Energy is short of the 40 it costs now")
	_energy(p, 40.0)
	check(p.abilities.try_cast(slot), "40 is enough")
	var params := p.abilities.params_for(Db.get_ability(&"fan_of_knives"))
	var with_points := RogueFanOfKnives.knife_damage(p, p.main_hand, float(params["damage_pct"]), 3, float(params["combo_bonus_pct"]))
	var without := RogueFanOfKnives.knife_damage(p, p.main_hand, float(params["damage_pct"]), 0, float(params["combo_bonus_pct"]))
	check_near(with_points / without, 1.0 + 3.0 * 0.35, 0.0001, "each Combo Point adds 35% instead of 20%")


func test_dill_sprig_hides_longer_and_heals_less() -> void:
	var p := _hero(&"rogue")
	var slot := p.abilities.slot_of(&"vanish")
	var fx := _fx(p, &"vanish") as RogueVanish
	p.hp = p.max_hp() * 0.4
	var before := p.hp
	check(p.abilities.try_cast(slot), "a plain Melt Away")
	check_near(fx._left, 2.0, 0.001, "hidden for 2 sec")
	check_near((p.hp - before) / p.max_hp(), 0.30, 0.001, "heals 30% of max HP")
	fx.end(false)
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	p.hp = p.max_hp() * 0.4
	before = p.hp
	_season(p, &"ssn_dill_sprig")
	check(p.abilities.try_cast(slot), "Melt Away with Dill Sprig")
	check_near(fx._left, 3.0, 0.001, "hidden for 3 sec")
	check_near((p.hp - before) / p.max_hp(), 0.15, 0.001, "heals 15%")


func test_tarragon_throws_two_more_stars_and_recharges_slower() -> void:
	var p := _hero(&"rogue")
	_enemy(Vector3(3.0, 0.0, 0.0))
	var slot := _learn(p, &"shuriken_toss")
	check(p.abilities.try_cast(slot), "a plain toss")
	check_eq(_blades().size(), 3, "three stars")
	_free_blades()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_tarragon")
	check(p.abilities.try_cast(slot), "a toss with Tarragon")
	check_eq(_blades().size(), 5, "five stars")
	check_near(p.abilities.cooldown_of(Db.get_ability(&"shuriken_toss")), 5.0, 0.001, "recharging 25% slower")


func test_coriander_makes_a_longer_slowing_weaker_cloud() -> void:
	var p := _hero(&"rogue")
	_enemy(Vector3(3.0, 0.0, 0.0))
	var slot := _learn(p, &"poison_bomb")
	check(p.abilities.try_cast(slot), "a plain bomb")
	var plain := _flasks()[0]
	var plain_duration := plain.duration
	var plain_tick := plain.damage_per_tick
	check_near(plain.slow_pct, 0.0, 0.001, "no slow")
	for f in _flasks():
		f.free()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_coriander")
	check(p.abilities.try_cast(slot), "a bomb with Coriander")
	var flask := _flasks()[0]
	check_near(flask.duration - plain_duration, 2.0, 0.001, "2 sec longer")
	check_near(flask.slow_pct, 25.0, 0.001, "slowing by 25%")
	check_near(flask.damage_per_tick / plain_tick, 18.0 / 25.0, 0.001, "each tick 7 points weaker")


func _flasks() -> Array[RoguePoisonFlask]:
	var out: Array[RoguePoisonFlask] = []
	for n in tree.get_nodes_in_group(&"ability_areas"):
		if n is RoguePoisonFlask and not n.is_queued_for_deletion():
			out.append(n as RoguePoisonFlask)
	return out


func test_lemongrass_strikes_another_target_for_less_time() -> void:
	var p := _hero(&"rogue")
	var slot := _learn(p, &"blade_flurry")
	var fx := _fx(p, &"blade_flurry") as RogueBladeFlurry
	check(p.abilities.try_cast(slot), "a plain flurry")
	check_eq(fx._targets, 1, "one target")
	check_near(fx.time_left(), 5.0, 0.001, "for 5 sec")
	fx.end()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_lemongrass")
	check(p.abilities.try_cast(slot), "a flurry with Lemongrass")
	check_eq(fx._targets, 2, "two targets")
	check_near(fx.time_left(), 3.5, 0.001, "for 3.5 sec")


func test_fenugreek_recharges_faster_and_saves_for_less() -> void:
	var p := _hero(&"rogue")
	var ability := Db.get_ability(&"cheat_death")
	_learn(p, &"cheat_death")
	p.abilities._physics_process(DT)
	check_near(p.abilities.cooldown_of(ability), 60.0, 0.001, "recharges in 60 sec")
	p.invulnerable_left = 0.0
	p.take_damage(p.max_hp() * 5.0)
	check(p.is_alive(), "the lethal hit is survived")
	check_near(p.invulnerable_left, 1.0, 0.001, "protected for 1 sec")
	p.abilities._physics_process(DT)
	var plain_heal := p.hp
	p.abilities.set_cooldown(ability, 0.0)
	p.hp = p.max_hp()
	p.invulnerable_left = 0.0
	_season(p, &"ssn_fenugreek")
	check_near(p.abilities.cooldown_of(ability), 42.0, 0.001, "30% faster: 42 sec")
	p.take_damage(p.max_hp() * 5.0)
	check(p.is_alive(), "survived again")
	check_near(p.invulnerable_left, 0.6, 0.001, "protected for 0.6 sec")
	p.abilities._physics_process(DT)
	check_near((plain_heal - 1.0) / p.max_hp() - (p.hp - 1.0) / p.max_hp(), 0.07, 0.002, "healing 7 points less of max HP")


func test_ghost_chili_strikes_more_often_and_weaker() -> void:
	var p := _hero(&"rogue")
	for i in 4:
		_enemy(Vector3(3.0 + float(i), 0.0, float(i) - 2.0))
	var slot := _learn(p, &"killing_spree")
	var fx := _fx(p, &"killing_spree") as RogueKillingSpree
	check(p.abilities.try_cast(slot), "a plain Cutthroat Rush")
	check_eq(fx.strikes + fx.strikes_left(), 8, "eight strikes over 2 sec")
	fx.end(false)
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_ghost_chili")
	check(p.abilities.try_cast(slot), "a Rush with Ghost Chili")
	check_eq(fx.strikes + fx.strikes_left(), 10, "ten strikes: one every 0.2 sec")
	check_near(fx._mult, 1.1, 0.0001, "each at 110% instead of 150%")
	check_near(fx._interval, 0.2, 0.0001, "0.2 sec apart")


# --- Warlock ------------------------------------------------------------------------------------------

func _shards(p: Player, amount: float = 3.0) -> void:
	p.abilities.get_resource(&"soul_shard").set_value(amount)


func _afflictions(p: Player) -> WarlockAfflictions:
	return WarlockAfflictions.of(p, false)


func test_cumin_seed_lasts_longer_and_jumps_further() -> void:
	var p := _hero(&"warlock")
	p.stats.set_source(&"intellect", {Stats.INTELLECT: 20.0})
	var e := _enemy(Vector3(4.0, 0.0, 0.0))
	var slot := _learn(p, &"corruption")
	check(p.abilities.try_cast(slot), "a plain Corruption")
	var plain := _afflictions(p).get_affliction(WarlockAfflictions.CORRUPTION, e)
	var plain_rate := plain.rate
	check_near(plain.duration, 8.0, 0.001, "8 sec")
	var plain_radius := plain.spread_radius
	_afflictions(p).clear()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_cumin_seed")
	check(p.abilities.try_cast(slot), "a Corruption with Cumin Seed")
	var a := _afflictions(p).get_affliction(WarlockAfflictions.CORRUPTION, e)
	check_near(a.duration, 12.0, 0.001, "12 sec")
	check_near(a.spread_radius - plain_radius, 2.0, 0.001, "jumps 2 m further")
	check_near(a.rate / plain_rate, 0.85, 0.0001, "ticking 15% weaker")


func test_sumac_pierces_more_enemies_and_recharges_slower() -> void:
	var p := _hero(&"warlock")
	var line: Array[Dummy] = []
	for i in 5:
		line.append(_enemy(Vector3(3.0 + 1.5 * float(i), 0.0, 0.0)))
	var slot := _learn(p, &"shadow_bolt")
	check(p.abilities.try_cast(slot), "a plain Umbral Bolt")
	_step(p, 2.0)
	var hit := 0
	for e in line:
		if e.fake_hits() > 0:
			hit += 1
	check_eq(hit, 1, "hits one enemy")
	for e in line:
		e.fake_damage_log.clear()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_sumac")
	check(p.abilities.try_cast(slot), "a bolt with Sumac")
	_step(p, 2.0)
	hit = 0
	for e in line:
		if e.fake_hits() > 0:
			hit += 1
	check_eq(hit, 3, "hits three: it pierces two more")
	check_near(p.abilities.cooldown_of(Db.get_ability(&"shadow_bolt")), 4.2, 0.001, "recharging 20% slower")


func test_allspice_bursts_wider_and_weaker() -> void:
	var p := _hero(&"warlock")
	p.stats.set_source(&"intellect", {Stats.INTELLECT: 20.0})
	var e := _enemy(Vector3(4.0, 0.0, 0.0))
	_enemy(Vector3(4.5, 0.0, 0.5))
	var slot := _learn(p, &"seed_of_corruption")
	check(p.abilities.try_cast(slot), "a plain Blight Seed")
	var plain := _afflictions(p).get_affliction(WarlockAfflictions.SEED, e)
	check(plain != null, "a seed is planted")
	var plain_radius := plain.burst_radius
	var plain_burst := plain.burst_damage
	_afflictions(p).clear()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_allspice")
	check(p.abilities.try_cast(slot), "a seed with Allspice")
	var a := _afflictions(p).get_affliction(WarlockAfflictions.SEED, e)
	check_near(a.burst_radius - plain_radius, 1.5, 0.001, "bursts 1.5 m wider")
	check_near(a.burst_damage / plain_burst, 0.8, 0.0001, "20% weaker")


func test_wasabi_widens_the_torment_and_softens_the_fists() -> void:
	var p := _hero(&"warlock")
	var slot := _learn(p, &"summon_voidwalker")
	var fx := _fx(p, &"summon_voidwalker") as WarlockSummonVoidwalker
	p.abilities._physics_process(DT)
	check(fx.has_pet(), "the Voidwalker fights at the Warlock's side")
	var plain_fist := WarlockVoidwalker.attack_damage(p.stats, fx.pet.params)
	check_near(float(fx.pet.params["torment_radius"]), 5.0, 0.001, "the Menace reaches 5 m")
	_season(p, &"ssn_wasabi")
	p.abilities._physics_process(DT)
	check_near(float(fx.pet.params["torment_radius"]), 7.0, 0.001, "7 m with Wasabi (the pet read the new numbers)")
	check_near(WarlockVoidwalker.attack_damage(p.stats, fx.pet.params) / plain_fist, 0.7, 0.0001, "its fists hit 30% softer")
	check(slot >= 0, "(learned)")


func test_tamarind_drains_two_enemies_and_heals_less() -> void:
	var p := _hero(&"warlock")
	var a := _enemy(Vector3(3.0, 0.0, 0.0))
	var b := _enemy(Vector3(3.0, 0.0, 1.5))
	var slot := p.abilities.slot_of(&"drain_life")
	check(slot >= 0, "Vital Siphon is core")
	p.hp = p.max_hp() * 0.3
	check(p.abilities.try_cast(slot), "a plain drain")
	_step(p, 2.2)
	check(a.fake_hits() > 0 and b.fake_hits() == 0, "one enemy drained")
	var plain_heal := (p.hp - p.max_hp() * 0.3)
	var plain_damage := a.total()
	a.fake_damage_log.clear()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	p.hp = p.max_hp() * 0.3
	_season(p, &"ssn_tamarind")
	check(p.abilities.try_cast(slot), "a drain with Tamarind")
	_step(p, 2.2)
	check(a.fake_hits() > 0 and b.fake_hits() > 0, "two enemies drained")
	check_near(a.total() / plain_damage, 1.0, 0.01, "each for the same damage")
	check((p.hp - p.max_hp() * 0.3) < plain_heal * 1.5, "healing: the second target adds damage, but 40 points less of each is healed")


func test_five_spice_drops_a_second_smaller_circle() -> void:
	var p := _hero(&"warlock")
	for i in 3:
		_enemy(Vector3(3.0 + 0.4 * float(i), 0.0, 0.0))
	for i in 3:
		_enemy(Vector3(3.0 + 0.4 * float(i), 0.0, 7.0))
	var slot := p.abilities.slot_of(&"rain_of_fire")
	check(slot >= 0, "Ember Rain is core")
	_shards(p)
	check(p.abilities.try_cast(slot), "a plain Ember Rain")
	check_eq(_areas().size(), 1, "one circle")
	var plain_radius := _areas()[0].radius
	for a in _areas():
		a.free()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_shards(p)
	_season(p, &"ssn_five_spice")
	check(p.abilities.try_cast(slot), "Ember Rain with Five-Spice")
	check_eq(_areas().size(), 2, "two circles")
	check_near(plain_radius - _areas()[0].radius, 0.7, 0.001, "each 0.7 m smaller")


func test_harissa_keeps_the_brute_longer_and_recharges_slower() -> void:
	var p := _hero(&"warlock")
	for i in 5:
		_enemy(Vector3(4.0 + 0.3 * float(i), 0.0, 0.0))
	var slot := _learn(p, &"summon_infernal")
	var fx := _fx(p, &"summon_infernal") as WarlockSummonInfernal
	_shards(p)
	check(p.abilities.try_cast(slot), "a plain Cinder Brute")
	check_near(fx.infernal.time_left, 8.0, 0.001, "stays 8 sec")
	fx.dismiss(true)
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_shards(p)
	_season(p, &"ssn_harissa")
	check(p.abilities.try_cast(slot), "a brute with Harissa")
	check_near(fx.infernal.time_left, 12.0, 0.001, "stays 12 sec")
	check_near(p.abilities.cooldown_of(Db.get_ability(&"summon_infernal")), 58.5, 0.001, "recharging 30% slower")


func test_ras_el_hanout_makes_fleeing_enemies_burn() -> void:
	var p := _hero(&"warlock")
	p.stats.set_source(&"intellect", {Stats.INTELLECT: 20.0})
	var e := _enemy(Vector3(2.0, 0.0, 0.0))
	var slot := _learn(p, &"fear")
	check(p.abilities.try_cast(slot), "a plain Fear")
	check(_afflictions(p) == null or not _afflictions(p).has(&"dread", e), "no damage over time")
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_ras_el_hanout")
	check(p.abilities.try_cast(slot), "a Fear with Ras el Hanout")
	var aff := _afflictions(p)
	check(aff != null and aff.has(&"dread", e), "the fleeing enemy is afflicted")
	check_near(p.abilities.cooldown_of(Db.get_ability(&"fear")), 17.5, 0.001, "recharging 25% slower")


# --- Hunter -------------------------------------------------------------------------------------------

func _focus(p: Player, amount: float = 100.0) -> void:
	p.abilities.get_resource(&"focus").value = amount


func _arrows() -> Array[HunterArrow]:
	var out: Array[HunterArrow] = []
	for n in tree.get_nodes_in_group(&"projectiles"):
		if n is HunterArrow and not n.is_queued_for_deletion():
			out.append(n as HunterArrow)
	return out


func _free_arrows() -> void:
	for a in _arrows():
		a.free()


func test_mustard_seed_looses_more_weaker_arrows() -> void:
	var p := _hero(&"hunter")
	_enemy(Vector3(5.0, 0.0, 0.0))
	var slot := p.abilities.slot_of(&"arrow_fan")
	check(slot >= 0, "Arrow Fan is core")
	_focus(p)
	check(p.abilities.try_cast(slot), "a plain fan")
	check_eq(_arrows().size(), 5, "five arrows")
	var plain_damage := _arrows()[0].damage
	_free_arrows()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_mustard_seed")
	_focus(p)
	check(p.abilities.try_cast(slot), "a fan with Mustard Seed")
	check_eq(_arrows().size(), 8, "eight arrows")
	check_near(_arrows()[0].damage / plain_damage, 85.0 / 120.0, 0.001, "each 35 points weaker")
	var angles: Array[float] = []
	for a in _arrows():
		angles.append(rad_to_deg(Vector2(a.direction.x, a.direction.z).angle()))
	angles.sort()
	check_near(angles[-1] - angles[0], 70.0, 0.5, "in a 70 degree fan instead of 50")


func test_wild_garlic_bites_harder_but_less_often() -> void:
	var p := _hero(&"hunter")
	var mastery := p.abilities.mastery as HunterMastery
	for kind: StringName in [&"wolf", &"boar", &"owl"]:
		if mastery.has_companion():
			mastery.companion.free()
			mastery.companion = null
		_plain(p)
		p.companion_id = kind
		var pet := mastery.ensure_companion()
		pet._params = pet.current_params()
		var interval := pet.attack_interval()
		var hit := pet.hit_damage(100.0)
		_season(p, &"ssn_wild_garlic")
		pet._params = pet.current_params()
		check_near(pet.attack_interval() / interval, 1.25, 0.0001, "%s: 25%% less often" % kind)
		check_near(pet.hit_damage(100.0) / hit, 1.25, 0.0001, "%s: 25%% harder" % kind)


func test_hickory_smoke_lays_two_snares() -> void:
	var p := _hero(&"hunter")
	_enemy(Vector3(6.0, 0.0, 0.0))
	var slot := _learn(p, &"blast_snare")
	var fx := _fx(p, &"blast_snare") as HunterBlastSnare
	check(p.abilities.try_cast(slot), "a plain Blast Snare")
	check_eq(fx.live_snares().size(), 1, "one snare")
	var plain := HunterBlastSnare.snare_numbers(_ctx(p, &"blast_snare"))
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_hickory_smoke")
	check(p.abilities.try_cast(slot), "a cast with Hickory Smoke")
	check_eq(fx.live_snares().size(), 3, "two more: the first one stays (three live at most)")
	var weaker := HunterBlastSnare.snare_numbers(_ctx(p, &"blast_snare"))
	check_near(float(weaker["damage"]) / float(plain["damage"]), 160.0 / 220.0, 0.0001, "each blast 60 points weaker")
	check_near(p.abilities.cooldown_of(Db.get_ability(&"blast_snare")), 10.0, 0.001, "recharging 25% slower")


func test_pine_needle_leaves_caltrops_and_leaps_less() -> void:
	var p := _hero(&"hunter")
	_enemy(Vector3(2.0, 0.0, 0.0))
	var slot := p.abilities.slot_of(&"backstep")
	var fx := _fx(p, &"backstep") as HunterBackstep
	p.facing = Vector3.RIGHT
	check(p.abilities.try_cast(slot), "a plain Backstep")
	check(fx.last_trail.is_empty(), "no trail")
	_step(p, 0.5)
	var plain_moved := p.global_position.length()
	check_near(plain_moved, 5.0, 0.05, "a plain Backstep leaps 5 m")
	p.global_position = Vector3.ZERO
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_pine_needle")
	check(p.abilities.try_cast(slot), "a Backstep with Pine Needle")
	check(not fx.last_trail.is_empty(), "caltrops are left behind")
	if not fx.last_trail.is_empty():
		check_near(fx.last_trail[0].duration, 2.5, 0.001, "for 2.5 sec")
	_step(p, 0.5)
	check_near(plain_moved - p.global_position.length(), 1.5, 0.05, "the leap is 1.5 m shorter")


func test_dried_chive_lengthens_quick_draw_and_lowers_the_haste() -> void:
	var p := _hero(&"hunter")
	var slot := _learn(p, &"quick_draw")
	var fx := _fx(p, &"quick_draw") as HunterQuickDraw
	var base_haste := p.stats.get_raw(Stats.HASTE)
	check(p.abilities.try_cast(slot), "a plain Quick Draw")
	_step(p, 0.05)
	check_near(p.stats.get_raw(Stats.HASTE) - base_haste, 40.0, 0.001, "40% Haste")
	check_near(fx.active_buff().left, 4.0, 0.1, "for 4 sec")
	p.abilities.end_wave()
	check_near(p.stats.get_raw(Stats.HASTE) - base_haste, 0.0, 0.001, "gone with the wave")
	p.abilities.begin_wave()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_dried_chive")
	check(p.abilities.try_cast(slot), "a Quick Draw with Dried Chive")
	_step(p, 0.05)
	check_near(p.stats.get_raw(Stats.HASTE) - base_haste, 25.0, 0.001, "25% Haste")
	check_near(fx.active_buff().left, 6.0, 0.1, "for 6 sec")


func test_pickling_brine_makes_the_blow_bleed() -> void:
	var p := _hero(&"hunter")
	_enemy(Vector3(4.0, 0.0, 0.0))
	var slot := _learn(p, &"hunt_signal")
	var pet := (p.abilities.mastery as HunterMastery).ensure_companion()
	check(p.abilities.try_cast(slot), "a plain Hunt Signal")
	check_near(float(pet._signal_blow["bleed_pct"]), 0.0, 0.001, "the blow does not bleed")
	check_near(float(pet._signal_blow["pct"]), 250.0, 0.001, "250% weapon damage")
	pet._clear_commands()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_pickling_brine")
	check(p.abilities.try_cast(slot), "a Hunt Signal with Pickling Brine")
	check_near(float(pet._signal_blow["bleed_pct"]), 60.0, 0.001, "the blow bleeds for 60% over 4 sec")
	check_near(float(pet._signal_blow["pct"]), 160.0, 0.001, "and strikes 90 points weaker")


func test_marjoram_aims_faster_and_hits_weaker() -> void:
	var p := _hero(&"hunter")
	_enemy(Vector3(6.0, 0.0, 0.0))
	var slot := _learn(p, &"long_shot")
	var fx := _fx(p, &"long_shot") as HunterLongShot
	check(p.abilities.try_cast(slot), "a plain Long Shot")
	check_near(fx.windup_left, 0.7, 0.0001, "aims for 0.7 sec")
	_step(p, 0.8)
	check(not fx.last_arrows.is_empty(), "the arrow is loosed")
	var plain_damage := fx.last_arrows[0].damage
	_free_arrows()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_marjoram")
	check(p.abilities.try_cast(slot), "a Long Shot with Marjoram")
	check_near(fx.windup_left, 0.35, 0.0001, "aims for 0.35 sec")
	_step(p, 0.4)
	check(not fx.last_arrows.is_empty(), "loosed sooner")
	check_near(fx.last_arrows[0].damage / plain_damage, 220.0 / 320.0, 0.001, "hits 100 points weaker")


func test_ancho_chile_heals_while_playing_dead() -> void:
	var p := _hero(&"hunter")
	_enemy(Vector3(2.0, 0.0, 0.0))
	var slot := _learn(p, &"play_dead")
	var fx := _fx(p, &"play_dead") as HunterPlayDead
	p.hp = p.max_hp() * 0.3
	var start := p.hp
	check(p.abilities.try_cast(slot), "a plain Play Dead")
	_step(p, 2.5)
	check_near(p.hp, start, 0.01, "heals nothing")
	fx.end(false)
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	p.hp = p.max_hp() * 0.3
	start = p.hp
	_season(p, &"ssn_ancho_chile")
	check(p.abilities.try_cast(slot), "Play Dead with Ancho Chile")
	check_near(fx._left, 1.5, 0.001, "playing dead for 1.5 sec")
	_step(p, 2.5)
	check_near((p.hp - start) / p.max_hp(), 0.15, 0.01, "heals 15% of max HP")
	check_near(p.abilities.cooldown_of(Db.get_ability(&"play_dead")), 25.0, 0.001, "recharging 25% slower")


# --- Shaman -------------------------------------------------------------------------------------------

func _shaman() -> Player:
	var p := _hero(&"shaman")
	p.stats.set_source(&"intellect", {Stats.INTELLECT: 10.0, Stats.SPELL_POWER: 4.0})
	return p


func _surge(p: Player, amount: float = 100.0) -> void:
	p.abilities.get_resource(&"surge").value = amount


func _run(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p._physics_process(DT)
		p.abilities._physics_process(DT)
		for node in tree.get_nodes_in_group(&"shaman_totems"):
			(node as ShamanTotem).step(DT)
		for child in world.get_children():
			if child is AbilityArea and not child.is_queued_for_deletion():
				(child as AbilityArea)._physics_process(DT)
			elif child is ShamanWolf and not child.is_queued_for_deletion():
				(child as ShamanWolf).step(DT)
			elif child is Enemy:
				for sub in child.get_children():
					if sub is ShamanBurn and not sub.is_queued_for_deletion():
						(sub as ShamanBurn)._physics_process(DT)
		t += DT


func test_smoked_salt_forks_to_two_more_enemies_with_more_falloff() -> void:
	var p := _shaman()
	var line: Array[Dummy] = []
	for i in 9:
		line.append(_enemy(Vector3(3.0 + 2.0 * float(i), 0.0, 0.0)))
	var slot := p.abilities.slot_of(&"forking_bolt")
	_surge(p)
	check(p.abilities.try_cast(slot), "a plain Forking Bolt")
	var plain: Array[float] = []
	for e in line:
		if e.fake_hits() > 0:
			plain.append(e.fake_damage_log[0])
	check_eq(plain.size(), 4, "four enemies struck")
	check_near(plain[1] / plain[0], 0.85, 0.001, "each jump 15% weaker")
	for e in line:
		e.fake_damage_log.clear()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_surge(p)
	_season(p, &"ssn_smoked_salt")
	check(p.abilities.try_cast(slot), "a bolt with Smoked Salt")
	var forked: Array[float] = []
	for e in line:
		if e.fake_hits() > 0:
			forked.append(e.fake_damage_log[0])
	check_eq(forked.size(), 6, "six enemies struck")
	check_near(forked[1] / forked[0], 0.75, 0.001, "each jump 25% weaker")


func test_rock_salt_keeps_the_totems_longer_and_recharges_slower() -> void:
	var p := _shaman()
	var slot := p.abilities.slot_of(&"totem_rite")
	var fx := p.abilities.effect_for(Db.get_ability(&"totem_rite")) as ShamanTotemRite
	check(p.abilities.try_cast(slot), "a plain Rite")
	check_near(fx.standing()[0].life_left, 10.0, 0.0001, "the totem stands 10 sec")
	fx.clear()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_rock_salt")
	check(p.abilities.try_cast(slot), "a Rite with Rock Salt")
	check_near(fx.standing()[0].life_left, 14.0, 0.0001, "the totem stands 14 sec")
	check_near(p.abilities.cooldown_of(Db.get_ability(&"totem_rite")), 16.8, 0.001, "recharging 40% slower")


func test_lovage_heals_more_and_the_fire_totem_fires_slower() -> void:
	var p := _shaman()
	var slot := p.abilities.slot_of(&"totem_rite")
	var fx := p.abilities.effect_for(Db.get_ability(&"totem_rite")) as ShamanTotemRite
	check(p.abilities.try_cast(slot), "Fire: a plain totem")
	var fire := fx.standing()[0]
	check_eq(fire.element, &"fire", "the first totem is Fire")
	var plain_interval := fire.fire_interval()
	fx.clear()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_lovage")
	check(p.abilities.try_cast(slot), "Water next")
	var water := fx.standing()[0]
	check_eq(water.element, &"water", "the second is Water")
	check_near(water.num("water_heal_max_hp_pct", 0.0), 4.5, 0.0001, "the Water totem heals 4.5% of max HP per sec instead of 2.5%")
	fx.clear()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	for element in ["Earth", "Air"]:
		check(p.abilities.try_cast(slot), element)
		fx.clear()
		p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	check(p.abilities.try_cast(slot), "the cycle is back at Fire")
	var fire2 := fx.standing()[0]
	check_eq(fire2.element, &"fire", "Fire again")
	check_near(fire2.fire_interval() / plain_interval, 1.5, 0.0001, "firing every 1.5 sec instead of 1")


func test_curry_leaf_stuns_and_hits_softer() -> void:
	var p := _shaman()
	var e := _enemy(Vector3(4.0, 0.0, 0.0))
	var slot := _learn(p, &"thunderbolt")
	check(p.abilities.try_cast(slot), "a plain Thunderbolt")
	check(e.stuns.is_empty(), "no stun")
	var plain := e.fake_damage_log[0]
	e.fake_damage_log.clear()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_curry_leaf")
	check(p.abilities.try_cast(slot), "a bolt with Curry Leaf")
	check_eq(e.stuns.size(), 1, "the enemy is stunned")
	check_near(e.stuns[0], 0.5, 0.001, "for 0.5 sec")
	check_near(e.fake_damage_log[0] / plain, 0.8, 0.001, "for 20% less")


func test_celery_seed_bursts_for_a_smaller_crowd() -> void:
	var p := _shaman()
	_enemy(Vector3(1.5, 0.0, 0.0))
	_enemy(Vector3(-1.5, 0.0, 0.0))
	var slot := _learn(p, &"stormburst")
	var fx := _fx(p, &"stormburst")
	var ctx := _ctx(p, &"stormburst")
	check(not fx.wants_auto_cast(ctx), "two enemies are no crowd")
	_season(p, &"ssn_celery_seed")
	ctx = _ctx(p, &"stormburst")
	check(fx.wants_auto_cast(ctx), "with Celery Seed they are")
	check(slot >= 0, "(learned)")
	var e := _enemy(Vector3(1.0, 0.0, 1.0))
	check(p.abilities.try_cast(slot), "a Stormburst with a crowd")
	var weak := e.fake_damage_log[0]
	e.fake_damage_log.clear()
	_plain(p)
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	check(p.abilities.try_cast(slot), "a plain one")
	check_near(weak / e.fake_damage_log[0], 0.75, 0.001, "hitting 25% weaker with Celery Seed")


func test_oregano_spreads_the_burn_to_more_enemies_but_weaker() -> void:
	var p := _shaman()
	var cluster: Array[Dummy] = []
	for i in 7:
		cluster.append(_enemy(Vector3(2.0 + 0.4 * float(i), 0.0, 0.0)))
	var slot := _learn(p, &"magma_lash")
	check(p.abilities.try_cast(slot), "a plain Magma Lash")
	var burn := ShamanBurn.find(cluster[0], p)
	check(burn != null, "the target burns")
	var plain_total := burn.total
	check_eq(burn.spread_targets, 2, "the fire may pass to two enemies")
	_run(p, 5.0)
	check_eq(burn.spread_hits, 2, "and it does: two more enemies catch fire")
	for e in cluster:
		var b := ShamanBurn.find(e, p)
		if b != null:
			b.free()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_oregano")
	check(p.abilities.try_cast(slot), "a Lash with Oregano")
	burn = ShamanBurn.find(cluster[0], p)
	check(burn != null, "the target burns")
	check_eq(burn.spread_targets, 4, "the fire may pass to four enemies")
	check_near(burn.total / plain_total, 0.5, 0.05, "the burn is 20 points weaker (20% of the hit instead of 40%)")
	_run(p, 5.0)
	check_eq(burn.spread_hits, 4, "four more enemies catch fire")


func test_sweet_basil_echoes_harder_but_less_often() -> void:
	var p := _shaman()
	p.stats.set_source(&"mastery", {Stats.MASTERY: 100.0})
	var mastery := p.abilities.mastery as ShamanMastery
	var e := _enemy(Vector3(3.0, 0.0, 0.0))
	check_near(mastery.echo_chance(), 60.0, 0.001, "a plain Echo is capped at 60%")
	_season(p, &"ssn_sweet_basil")
	check_near(mastery.echo_chance(), 40.0, 0.001, "capped at 40% with Sweet Basil")
	var dealt := 0.0
	for i in 60:
		dealt = mastery.roll_echo(e, 100.0, &"nature")
		if dealt > 0.0:
			break
	check_near(dealt, 75.0, 0.001, "an echo repeats 75% of the hit")


func test_wolfberry_calls_another_wolf_that_bites_softer() -> void:
	var p := _shaman()
	_enemy(Vector3(3.0, 0.0, 0.0))
	var slot := _learn(p, &"spirit_pack")
	var fx := _fx(p, &"spirit_pack") as ShamanSpiritPack
	check(p.abilities.try_cast(slot), "a plain Spirit Pack")
	check_eq(fx.alive_count(), 2, "two wolves")
	var plain := ShamanSpiritPack.pet_params_for(_ctx(p, &"spirit_pack"))
	fx.dismiss_all()
	p.abilities.set_cooldown(p.abilities.slots[slot], 0.0)
	_season(p, &"ssn_wolfberry")
	check(p.abilities.try_cast(slot), "a pack with Wolfberry")
	check_eq(fx.alive_count(), 3, "three wolves")
	var soft := ShamanSpiritPack.pet_params_for(_ctx(p, &"spirit_pack"))
	check_near(float(plain["bite_pct"]) - float(soft["bite_pct"]), 15.0, 0.001, "each bite 15 points weaker")
	check_near(float(_ctx(p, &"spirit_pack").num("duration")), 8.0, 0.001, "and 2 sec shorter")
