extends "res://tests/talents_mage_base.gd"
## Mage Fire tree (M5, talents_mage.md 2): every talent through player.talents on a real Mage
## – crit / Mastery / Critical Damage stats, Fire / DoT / execute / all-damage multipliers,
## damage taken – the Living Bomb modifier (Fireball -> MageBolt -> MageBurn: arming, natural
## end, death, despawn, re-arming) and the Combustion capstone (MageFireCombustion: first-hit
## crits only, nearest 4, 1 s per-enemy refresh, real wand / staff attacks, downed, wave start,
## teardown). Plus the bot paths of all three Mage trees.

const COMBUSTION := &"mage_fire_combustion"


func _combustion(p: Player) -> MageFireCombustion:
	return p.bonuses.script_for(COMBUSTION) as MageFireCombustion


## A Mage with the 12 points that open the capstone, then Combustion.
func _combustion_mage(pos: Vector3 = Vector3.ZERO) -> Player:
	var p := _mage(pos)
	_plan(p, FIRE_12)
	_add(p, String(COMBUSTION))
	check(_combustion(p) != null, "Combustion script live")
	return p


## A Mage with Living Bomb (6 points in tier 1, then the modifier) and Fireball learned.
func _bomb_mage() -> Player:
	var p := _mage()
	_learn(p, &"fireball")
	_plan(p, [["mage_fire_critical_mass", 3], ["mage_fire_fire_power", 3]])
	_add(p, "mage_fire_living_bomb")
	return p


func _burn(e: Enemy, p: Player) -> MageBurn:
	return MageBurn.find(e, p)


## Weapon projectiles in flight (not Mage bolts).
func _shots() -> Array[Projectile]:
	var out: Array[Projectile] = []
	for n in tree.get_nodes_in_group(&"projectiles"):
		if n is Projectile and not n is MageBolt and not n.is_queued_for_deletion():
			out.append(n)
	return out


# --- Tier 1-4 ----------------------------------------------------------------------------------

func test_critical_mass_adds_crit_per_rank() -> void:
	var p := _mage()
	var before := p.stats.get_raw(Stats.CRIT)
	_add(p, "mage_fire_critical_mass", 3)
	check_near(p.stats.get_raw(Stats.CRIT), before + 6.0, 0.0001, "+2% crit per rank")
	_remove(p, "mage_fire_critical_mass")
	check_near(p.stats.get_raw(Stats.CRIT), before + 4.0, 0.0001, "rank 2")
	_remove(p, "mage_fire_critical_mass", 2)
	check_near(p.stats.get_raw(Stats.CRIT), before, 0.0001, "undone")


func test_fire_power_raises_fire_damage_only() -> void:
	var p := _mage()
	_add(p, "mage_fire_fire_power", 3)
	check_near(p.bonuses.damage_mult(null, &"fire", &"dot"), 1.09, 0.0001, "+3% Fire per rank (burns)")
	check_near(p.bonuses.damage_mult(null, &"fire", &"weapon"), 1.09, 0.0001, "a Staff hit too")
	check_eq(p.bonuses.damage_mult(null, &"arcane", &"weapon"), 1.0, "not the wand")
	check_eq(p.bonuses.damage_mult(null, &"frost", &"ability"), 1.0, "not Frost")
	_remove(p, "mage_fire_fire_power", 3)
	check_eq(p.bonuses.damage_mult(null, &"fire", &"dot"), 1.0, "undone")


func test_empowered_fire_needs_critical_mass_and_adds_mastery() -> void:
	var p := _mage()
	var before := p.stats.get_raw(Stats.MASTERY)
	_add(p, "mage_fire_critical_mass", 2)
	_add(p, "mage_fire_fire_power")
	check_eq(p.talents.add_block_reason(&"mage_fire_empowered_fire"), "Requires Critical Mass", "prerequisite")
	_add(p, "mage_fire_critical_mass")
	_add(p, "mage_fire_empowered_fire", 3)
	check_near(p.stats.get_raw(Stats.MASTERY), before + 9.0, 0.0001, "+3 Mastery per rank")
	check_eq(Db.get_talent(&"mage_fire_empowered_fire").text_for_rank(3),
		"Increases your Mastery by 9: Ignite burns for a bigger share of your critical hits.", "text")
	_remove(p, "mage_fire_empowered_fire", 3)
	check_near(p.stats.get_raw(Stats.MASTERY), before, 0.0001, "undone")


func test_incineration_raises_burn_damage() -> void:
	var p := _mage()
	_add(p, "mage_fire_critical_mass", 3)
	_add(p, "mage_fire_incineration", 3)
	check_near(p.bonuses.damage_mult(null, &"fire", &"dot"), 1.15, 0.0001, "+5% DoT per rank")
	check_near(p.bonuses.damage_mult(null, &"shadow", &"dot"), 1.15, 0.0001, "any school's DoT")
	check_eq(p.bonuses.damage_mult(null, &"fire", &"ability"), 1.0, "not a direct spell")
	check_eq(p.bonuses.damage_mult(null, &"fire", &"weapon"), 1.0, "not a weapon hit")
	var e := _enemy(Vector3(3, 0, 0))
	MageBurn.apply(e, p, 10.0, 1.0)
	_step(1.1)
	check_near(_total(e), 11.5, 0.001, "a 10-damage burn deals 11.5")
	_remove(p, "mage_fire_incineration", 3)
	check_eq(p.bonuses.damage_mult(null, &"fire", &"dot"), 1.0, "undone")


func test_playing_with_fire_trades_damage_for_damage_taken() -> void:
	var p := _mage()
	_plan(p, [["mage_fire_critical_mass", 3], ["mage_fire_fire_power", 3]])
	check_eq(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 1.0, "nothing yet")
	_add(p, "mage_fire_playing_with_fire", 2)
	check_near(p.bonuses.damage_mult(null, &"frost", &"ability"), 1.06, 0.0001, "+3% all damage per rank")
	check_near(p.bonuses.damage_mult(null, &"arcane", &"weapon"), 1.06, 0.0001, "weapon hits too")
	check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 1.04, 0.0001, "+2% damage taken per rank")
	check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_PROJECTILE, null), 1.04, 0.0001, "every kind")
	_remove(p, "mage_fire_playing_with_fire", 2)
	check_eq(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 1.0, "undone")
	check_eq(p.bonuses.damage_mult(null, &"frost", &"ability"), 1.0, "undone")


func test_burnout_needs_empowered_fire_and_raises_crit_damage() -> void:
	var p := _mage()
	_plan(p, [["mage_fire_critical_mass", 3], ["mage_fire_fire_power", 3], ["mage_fire_empowered_fire", 2],
		["mage_fire_incineration", 1]])
	check_eq(p.talents.add_block_reason(&"mage_fire_burnout"), "Requires Empowered Fire", "prerequisite")
	_add(p, "mage_fire_empowered_fire")
	var before := p.stats.get_raw(Stats.CRIT_DAMAGE)
	_add(p, "mage_fire_burnout", 3)
	check_near(p.stats.get_raw(Stats.CRIT_DAMAGE), before + 30.0, 0.0001, "+10% Critical Damage per rank")
	check_near(CombatMath.crit_multiplier(p.main_hand, p.stats), 2.3 + before / 100.0, 0.0001, "crits x2.3")
	_remove(p, "mage_fire_burnout", 3)
	check_near(p.stats.get_raw(Stats.CRIT_DAMAGE), before, 0.0001, "undone")


func test_molten_fury_hits_enemies_below_35_percent_harder() -> void:
	var p := _mage()
	_plan(p, [["mage_fire_critical_mass", 3], ["mage_fire_fire_power", 3], ["mage_fire_incineration", 3]])
	_add(p, "mage_fire_molten_fury", 3)
	var e := _enemy(Vector3(3, 0, 0))
	e.hp = 300.0
	check_near(p.bonuses.damage_mult(e, &"arcane", &"weapon"), 1.15, 0.0001, "+5% per rank below 35%")
	e.hp = 350.0
	check_eq(p.bonuses.damage_mult(e, &"arcane", &"weapon"), 1.0, "35% is not below")
	e.hp = 900.0
	check_eq(p.bonuses.damage_mult(e, &"arcane", &"weapon"), 1.0, "healthy enemies")
	check_eq(p.bonuses.damage_mult(null, &"arcane", &"weapon"), 1.0, "no target: no bonus")
	check_eq(Db.get_talent(&"mage_fire_molten_fury").text_for_rank(3),
		"You deal 15% more damage to enemies below 35% health.", "the threshold is not rank-scaled")


# --- Living Bomb -------------------------------------------------------------------------------

func test_living_bomb_params_text_and_bot_deferral() -> void:
	var p := _mage()
	check_eq(float(_params(p, &"fireball")["bomb_pct"]), 0.0, "neutral without the talent")
	var lb := Db.get_talent(&"mage_fire_living_bomb")
	check(TalentBot.is_deferred(p, lb), "bots wait while Fireball is not slotted")
	_plan(p, [["mage_fire_critical_mass", 3], ["mage_fire_fire_power", 3]])
	_add(p, "mage_fire_living_bomb")
	check_eq(float(_params(p, &"fireball")["bomb_pct"]), 40.0, "40% of the hit")
	check_eq(float(_params(p, &"fireball")["bomb_radius"]), 2.5, "2.5 m")
	check_eq(lb.text_for_rank(1),
		"Fireball's burn becomes a Living Bomb: when it burns out or the enemy dies, it explodes for 40% of the Fireball's damage to enemies within 2.5 m.",
		"text")
	_learn(p, &"fireball")
	check(not TalentBot.is_deferred(p, lb), "not deferred once Fireball is slotted")


func test_fireball_burns_are_not_armed_without_the_talent() -> void:
	var p := _mage()
	var slot := _learn(p, &"fireball")
	var e := _enemy(Vector3(5, 0, 0))
	var n := _enemy(Vector3(6.5, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	_fly()
	var burn := _burn(e, p)
	check(burn != null and not burn.is_armed(), "a plain burn")
	_step(3.3)
	check(burn.bomb_hits == 0 and not burn.exploded, "no explosion")
	check_eq(n.fake_hits(), 0, "the neighbour is untouched")


func test_living_bomb_explodes_once_when_the_burn_runs_out() -> void:
	var p := _bomb_mage()
	var e := _enemy(Vector3(5, 0, 0))
	var n := _enemy(Vector3(6.5, 0, 0))
	var far := _enemy(Vector3(5, 0, 4))
	var state := RunState.rng.state
	check(p.abilities.try_cast(p.abilities.slot_of(&"fireball")), "cast")
	var hit := _bolts()[0].damage
	check_near(hit, _spell(p, 6.0, 1.0, &"fire"), 0.0001, "Fireball hit (before the multipliers)")
	_fly()
	var burn := _burn(e, p)
	check(burn != null and burn.is_armed(), "the burn is a Living Bomb")
	check_near(burn.bomb_damage, hit * 0.4, 0.0001, "40% of the hit")
	check_near(burn.bomb_radius, 2.5, 0.0001, "2.5 m (Area Size 0)")
	check(e.died.is_connected(burn._on_enemy_died), "the death is watched")
	_step(2.9)
	check_eq(n.fake_hits(), 0, "nothing while it burns")
	_step(0.3)
	check(burn.exploded, "burnt out: it explodes")
	check_eq(burn.bomb_hits, 2, "the enemy and its neighbour")
	check_eq(n.fake_hits(), 1, "the neighbour is hit once")
	check_near(n.fake_damage_log[0], hit * 0.4 * p.outgoing_damage_mult(n, &"fire", &"ability"), 0.0001,
		"Fire spell damage with the Mage's multipliers (Fire Power)")
	check_eq(far.fake_hits(), 0, "4 m away: outside")
	var e_hits := e.fake_hits()
	_step(1.0)
	check_eq(n.fake_hits(), 1, "it goes off once")
	check_eq(e.fake_hits(), e_hits, "no more burn, no second blast")
	check_eq(RunState.rng.state, state, "no RNG")


func test_living_bomb_explodes_at_the_corpse_when_the_enemy_dies() -> void:
	var p := _bomb_mage()
	var e := _enemy(Vector3(5, 0, 0))
	var n := _enemy(Vector3(6.5, 0, 0))
	check(p.abilities.try_cast(p.abilities.slot_of(&"fireball")), "cast")
	_fly()
	var burn := _burn(e, p)
	check(burn != null and burn.is_armed(), "armed")
	var e_hits := e.fake_hits()
	# Enemy._die: leaves the world (the enemies group), then emits died.
	e.fake_dead = true
	e.remove_from_group(&"enemies")
	EnemyGrid.mark_dirty()
	e.died.emit(e, 0)
	check(burn.exploded, "the death sets it off")
	check_eq(n.fake_hits(), 1, "the neighbour is hit")
	check_eq(e.fake_hits(), e_hits, "the corpse is not")
	burn._physics_process(DT)
	check(burn.is_queued_for_deletion(), "the burn ends with the enemy")
	_step(1.0)
	check_eq(n.fake_hits(), 1, "once")


func test_living_bomb_does_not_explode_on_despawn() -> void:
	var p := _bomb_mage()
	var e := _enemy(Vector3(5, 0, 0))
	var n := _enemy(Vector3(6.5, 0, 0))
	check(p.abilities.try_cast(p.abilities.slot_of(&"fireball")), "cast")
	_fly()
	var burn := _burn(e, p)
	check(burn != null and burn.is_armed(), "armed")
	e.fake_dead = true  # a real Enemy reports dead after despawn()
	e.despawn()
	burn._physics_process(DT)
	check(not burn.exploded, "wave end: no explosion")
	check_eq(n.fake_hits(), 0, "nobody hurt")


func test_living_bomb_keeps_the_bigger_bomb_and_survives_merged_burns() -> void:
	var p := _bomb_mage()
	var e := _enemy(Vector3(5, 0, 0))
	var burn := MageBurn.apply(e, p, 10.0, 3.0)
	burn.arm_bomb(5.0, 2.5)
	burn.arm_bomb(3.0, 2.0)
	check_near(burn.bomb_damage, 5.0, 0.0001, "a weaker arming keeps the bigger bomb")
	check_near(burn.bomb_radius, 2.5, 0.0001, "and the bigger radius")
	burn.arm_bomb(8.0, 2.5)
	check_near(burn.bomb_damage, 8.0, 0.0001, "a stronger one raises it")
	var merged := MageBurn.apply(e, p, 6.0, 3.0)  # Pyroblast / Combustion burn of the same Mage
	check(merged == burn and burn.is_armed(), "a merged burn stays armed")
	check_near(burn.bomb_damage, 8.0, 0.0001, "unchanged by the merge")
	var plain := MageBolt.new()
	check_eq(plain.bomb_pct, 0.0, "bolts (Pyroblast, Arcane Missiles) do not arm by default")
	plain.free()


# --- Combustion --------------------------------------------------------------------------------

func test_combustion_text_and_script() -> void:
	var t := Db.get_talent(COMBUSTION)
	check_eq(t.text_for_rank(1),
		"When the first hit of your weapon attack is a critical strike, it sets the area ablaze: the target and the nearest enemies within 2.5 m – up to 4 in all – burn for 20% of the critical hit's damage over 3 sec. An enemy burns from Combustion at most once every 1 sec.",
		"text")
	var p := _mage()
	check(_combustion(p) == null, "no script before the capstone")
	_combustion_mage()


func test_combustion_lights_the_target_and_its_neighbours_on_a_crit() -> void:
	var p := _combustion_mage()
	var c := _combustion(p)
	var target := _enemy(Vector3(3, 0, 0))
	var near := _enemy(Vector3(4.5, 0, 0))
	var far := _enemy(Vector3(3, 0, 4))
	var state := RunState.rng.state
	p.bonuses.on_hit(target, 20.0, true, true)
	check_eq(c.combustions, 1, "one Combustion")
	check_eq(c.burns, 2, "two burns")
	check(_burn(target, p) != null, "the target burns")
	check_near(_burn(target, p).remaining(), 4.0, 0.0001, "20% of the hit's base amount")
	check(_burn(near, p) != null, "a neighbour within 2.5 m burns")
	check_near(_burn(near, p).remaining(), 4.0, 0.0001, "the same share")
	check(_burn(far, p) == null, "4 m away: not")
	check_eq(RunState.rng.state, state, "no RNG")
	_step(3.2)
	check_near(_total(target), 4.0 * p.outgoing_damage_mult(target, &"fire", &"dot"), 0.001,
		"Fire DoT ticks: Fire Power and Incineration apply once")


func test_combustion_needs_a_crit_on_the_first_hit() -> void:
	var p := _combustion_mage()
	var c := _combustion(p)
	var e := _enemy(Vector3(3, 0, 0))
	p.bonuses.on_hit(e, 20.0, false, true)
	check(_burn(e, p) == null and c.combustions == 0, "a normal hit: nothing")
	p.bonuses.on_hit(e, 20.0, true, false)
	check(_burn(e, p) == null and c.combustions == 0, "a crit on a later hit of the attack: nothing")
	p.bonuses.on_hit(e, 0.0, true, true)
	check(_burn(e, p) == null, "no damage: nothing")
	p.bonuses.on_hit(null, 20.0, true, true)
	check_eq(c.combustions, 0, "no target: nothing (no error)")


func test_combustion_burns_at_most_four_enemies_nearest_first() -> void:
	var p := _combustion_mage()
	var c := _combustion(p)
	var target := _enemy(Vector3(2, 0, 0))
	var ring: Array[Fakes.FakeEnemy] = []
	for d: float in [2.4, 0.5, 2.0, 1.0, 1.5]:
		ring.append(_enemy(Vector3(2, 0, d)))
	p.bonuses.on_hit(target, 10.0, true, true)
	check_eq(c.burns, 4, "4 burns in all")
	check(_burn(target, p) != null, "the target first")
	check(_burn(ring[1], p) != null and _burn(ring[3], p) != null and _burn(ring[4], p) != null,
		"then the three nearest (0.5, 1, 1.5 m)")
	check(_burn(ring[2], p) == null and _burn(ring[0], p) == null, "not the farther ones (2, 2.4 m)")


func test_combustion_skips_enemies_it_burned_within_a_second() -> void:
	var p := _combustion_mage()
	var c := _combustion(p)
	var target := _enemy(Vector3(3, 0, 0))
	var near := _enemy(Vector3(4, 0, 0))
	p.bonuses.on_hit(target, 20.0, true, true)
	check(c.is_on_refresh_cooldown(target) and c.is_on_refresh_cooldown(near), "both on the 1 s refresh cooldown")
	var late := _enemy(Vector3(3, 0, 1.5))
	p.bonuses.on_hit(target, 20.0, true, true)
	check_near(_burn(target, p).remaining(), 4.0, 0.0001, "a second crit at once adds nothing to the target")
	check_near(_burn(near, p).remaining(), 4.0, 0.0001, "nor to the neighbour")
	check(_burn(late, p) != null, "a fresh enemy in reach still catches fire")
	check_eq(c.combustions, 2, "it still went off (one new burn)")
	p.bonuses.tick(0.5)
	p.bonuses.on_hit(target, 20.0, true, true)
	check_near(_burn(target, p).remaining(), 4.0, 0.0001, "0.5 sec later: still nothing")
	p.bonuses.tick(0.51)
	p.bonuses.on_hit(target, 20.0, true, true)
	check_near(_burn(target, p).remaining(), 8.0, 0.0001, "after 1 sec the running burn absorbs the new total")
	check_near(_burn(target, p).left, 3.0, 0.0001, "and restarts its clock")


func test_combustion_from_a_killing_crit_lights_the_neighbours() -> void:
	var p := _combustion_mage()
	var c := _combustion(p)
	var target := _enemy(Vector3(3, 0, 0))
	var near := _enemy(Vector3(4, 0, 0))
	target.fake_dead = true
	p.bonuses.on_hit(target, 20.0, true, true)
	check(_burn(target, p) == null, "the dead target does not burn")
	check(_burn(near, p) != null, "its neighbour does")
	check_eq(c.burns, 1, "one burn")


func test_combustion_on_a_real_wand_attack_with_a_forced_crit() -> void:
	var p := _combustion_mage()
	var c := _combustion(p)
	var target := _enemy(Vector3(3, 0, 0))
	var near := _enemy(Vector3(4.5, 0, 0))
	p.forced_crits = 1
	p.weapons[0].attack(target)
	var shots := _shots()
	check_eq(shots.size(), 1, "one wand bolt")
	check(shots[0].is_crit, "the forced crit")
	var base := shots[0].damage
	_fly()
	check(target.fake_crit_log.size() > 0 and target.fake_crit_log[0], "the target took a crit")
	check_eq(c.combustions, 1, "Combustion")
	check_near(_burn(target, p).remaining(), base * 0.2, 0.0001, "20% of the crit's base amount (before multipliers)")
	check(_burn(near, p) != null, "the neighbour burns too")
	check_eq(p.forced_crits, 0, "the forced crit was used")


func test_a_staff_explosion_over_six_enemies_is_one_combustion() -> void:
	var p := _combustion_mage()
	p.equip_weapons(Db.get_weapon(&"staff"), null)
	var c := _combustion(p)
	var pack := _cluster(Vector3(4, 0, 0), 6, 0.6)
	p.forced_crits = 1
	p.weapons[0].attack(pack[0])
	_fly()
	var crits := 0
	for e in pack:
		if e.fake_crit_log.size() > 0 and e.fake_crit_log[0]:
			crits += 1
	check_eq(crits, 6, "the explosion crit all six")
	check_eq(c.combustions, 1, "only the first hit counts")
	var burning := 0
	for e in pack:
		if _burn(e, p) != null:
			burning += 1
	check_eq(burning, 4, "4 burns, not 6 x 4")


func test_a_downed_mage_starts_no_fires() -> void:
	var p := _combustion_mage()
	var c := _combustion(p)
	var e := _enemy(Vector3(3, 0, 0))
	_down(p)
	WeaponRunner.apply_hit(p, e, 20.0, true, Vector3.ZERO, 0.0, 0.5, p.main_hand)
	check(_burn(e, p) == null and c.combustions == 0, "no Combustion while downed")


func test_combustion_resets_each_wave_and_tears_down() -> void:
	var p := _combustion_mage()
	var c := _combustion(p)
	var e := _enemy(Vector3(3, 0, 0))
	p.bonuses.on_hit(e, 20.0, true, true)
	check(c.is_on_refresh_cooldown(e), "on cooldown")
	p.begin_wave()
	check(not c.is_on_refresh_cooldown(e), "a new wave clears the refresh times")
	check(_combustion(p) == c, "the same instance across the wave start")
	p.bonuses.on_hit(e, 20.0, true, true)
	RunState.add_gold(100)
	check(p.talents.try_reset(0), "Reset Talents")
	check(_combustion(p) == null and p.bonuses.scripts().is_empty(), "the capstone is gone")
	check(not c.is_on_refresh_cooldown(e), "torn down: no refresh times left")
	check(p.damage_mults.is_empty(), "no damage_mults keys")
	var other := _enemy(Vector3(3, 0, 1))
	p.bonuses.on_hit(e, 20.0, true, true)
	check(_burn(other, p) == null, "no more fires")


# --- Bots --------------------------------------------------------------------------------------

func test_bots_reach_every_mage_capstone_at_point_thirteen() -> void:
	var capstones: Array[StringName] = [&"mage_arcane_arcane_power", &"mage_fire_combustion", &"mage_frost_ice_lance"]
	var modifiers: Array[StringName] = [&"mage_arcane_mirror_image", &"mage_fire_living_bomb", &"mage_frost_deep_freeze"]
	for slot in 3:
		var p := _mage(Vector3(0, 0, 3.0 * slot), slot)
		var picks: Array[StringName] = []
		while p.talents.points_free() > 0:
			var t := TalentBot.next_talent(p, slot)
			if t == null:
				break
			check(p.talents.add(t.id), "bot add %s" % t.id)
			picks.append(t.id)
		check_eq(picks.size(), 22, "slot %d spends 22 points" % slot)
		check_eq(picks.find(capstones[slot]), 12, "slot %d: capstone at point 13" % slot)
		check_eq(p.talents.rank_of(capstones[slot]), 1, "slot %d capstone taken" % slot)
		if slot == 1:
			check_eq(picks.find(modifiers[slot]), -1, "Fire: Living Bomb is deferred while Fireball is not slotted")
			check_eq(picks[21], &"mage_frost_piercing_ice", "the 22nd point goes to the next tree instead")
		else:
			check_eq(picks.find(modifiers[slot]), 6, "slot %d: modifier at point 7" % slot)
		p.free()
