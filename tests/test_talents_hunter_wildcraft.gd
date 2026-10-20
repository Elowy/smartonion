extends "res://tests/talents_hunter_base.gd"
## Hunter Wildcraft (M8 TALENTS-H, design_hunter 4.3): every talent through player.talents.add ->
## PlayerBonuses on a real Hunter at every rank – Trailwise (Speed), Powder Lore (Blast Snare power /
## cooldown), Twin Fang Grip (dual wield only: damage + extra attacks), Briar Hide (Armor, Thorns), Snared
## Prey (damage to slowed enemies), Brace of Snares (more snares, more at once), Close Quarters (melee
## weapon only: damage + less melee damage), Fleet Retreat (Backstep cooldown / slow) and the Firebug Bombs
## capstone (data only: burning ground + scattered bombs on Blast Snare). A bow Hunter gets nothing from
## the two weapon-bound talents; a sword + dagger or a Polearm Hunter does.

const T := "wildcraft"
const FB_ID := &"hunter_wildcraft_firebug_bombs"


## The 12 points that open the capstone with a bow (Twin Fang Grip is dual wield only): 11 + Fleet Retreat.
func _to_capstone(p: Player) -> void:
	_add(p, T, "trailwise", 3)
	_add(p, T, "powder_lore", 3)
	_add(p, T, "briar_hide", 3)
	_add(p, T, "snared_prey", 2)
	_add(p, T, "fleet_retreat")
	_add(p, T, "firebug_bombs")


func _snares() -> Array[HunterSnare]:
	var out: Array[HunterSnare] = []
	for node in tree.get_nodes_in_group(&"hunter_snares"):
		var s := node as HunterSnare
		if s != null and s.is_active():
			out.append(s)
	return out


func _areas(p: Player) -> Array[AbilityArea]:
	var out: Array[AbilityArea] = []
	for node in tree.get_nodes_in_group(&"ability_areas"):
		var a := node as AbilityArea
		if a != null and a.owner_player == p and not a.is_queued_for_deletion():
			out.append(a)
	return out


# --- Tier 1 ------------------------------------------------------------------------------------

func test_trailwise_adds_movement_speed() -> void:
	var p := _hunter()
	var speed := p.stats.get_raw(Stats.SPEED)
	for n in range(1, 4):
		_add(p, T, "trailwise")
		check_near(p.stats.get_raw(Stats.SPEED), speed + 2.0 * n, 0.0001, "+2%% Speed per rank (%d)" % n)
	check_eq(_talent(T, "trailwise").text_for_rank(3), "Increases your movement Speed by 6%.", "rank text")
	_reset(p)
	check_near(p.stats.get_raw(Stats.SPEED), speed, 0.0001, "reset: Speed back")


func test_powder_lore_changes_blast_snare_power_and_cooldown() -> void:
	var p := _hunter()
	var base := _params(p, &"blast_snare")
	for n in range(1, 4):
		_add(p, T, "powder_lore")
		var now := _params(p, &"blast_snare")
		check_near(float(now["power"]), float(base["power"]) * (1.0 + 0.06 * n), 0.0001, "+6%% power per rank (%d)" % n)
		check_near(float(now["cooldown"]), float(base["cooldown"]) * (1.0 - 0.06 * n), 0.0001, "-6%% cooldown per rank (%d)" % n)
	check_eq(_talent(T, "powder_lore").text_for_rank(3),
		"Blast Snare deals 18% more damage and recharges 18% faster.", "rank text")
	check_near(float(_params(p, &"backstep")["cooldown"]), 8.0, 0.0001, "Backstep untouched")
	# The burst really hits harder: 220% W Fire x power.
	_enemy(Vector3(0, 0, -6))
	var victim := _enemy(Vector3(0, 0, -3))
	var slot := _learn(p, &"blast_snare")
	check(p.abilities.try_cast(slot), "cast")
	var snares := _snares()
	check_eq(snares.size(), 1, "one snare")
	snares[0].burst()
	check_near(victim.fake_damage_log[0], _w(p, &"fire") * 2.2 * 1.18, 0.001, "220% W x 1.18")
	check_near(p.abilities.remaining(slot), 8.0 * 0.82, 0.001, "recharge 18% faster")


# --- Tier 2 ------------------------------------------------------------------------------------

func test_twin_fang_grip_needs_two_weapons() -> void:
	var p := _hunter()
	var extra := p.stats.get_raw(Stats.EXTRA_ATTACK)
	check(p.main_hand != null and p.off_hand == null, "a bow: one two-hander")
	_add(p, T, "trailwise", 3)
	for n in range(1, 4):
		_add(p, T, "twin_fang_grip")
		check_eq(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, "a bow: no damage bonus (%d)" % n)
		check_near(p.stats.get_raw(Stats.EXTRA_ATTACK), extra, 0.0001, "a bow: no extra attacks (%d)" % n)
	check(TalentBot.is_deferred(p, _talent(T, "twin_fang_grip")), "a bow bot defers it")
	_wield(p, &"sword", &"dagger")
	check(p.main_hand != null and p.off_hand != null and PlayerBonuses.weapon_requirement_met(p, &"dual_wield"), "sword + dagger: dual wield")
	check_near(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.12, 0.0001, "+4% damage per rank while dual wielding")
	check_near(p.bonuses.damage_mult(null, &"fire", &"ability"), 1.12, 0.0001, "every source")
	check_near(p.stats.get_raw(Stats.EXTRA_ATTACK), extra + 9.0, 0.0001, "+3% extra attack per rank")
	check(not TalentBot.is_deferred(p, _talent(T, "twin_fang_grip")), "not deferred for a dual wielder")
	check_eq(_talent(T, "twin_fang_grip").text_for_rank(3),
		"While dual wielding, you deal 12% more damage and your weapon hits strike again 9% of the time.", "rank text")
	check(p.equipment.unequip(Items.EquipSlot.OFF_HAND), "off hand away")
	check_eq(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, "one weapon: no damage bonus")
	check_near(p.stats.get_raw(Stats.EXTRA_ATTACK), extra, 0.0001, "and no extra attacks")


func test_briar_hide_adds_armor_and_thorns() -> void:
	var p := _hunter()
	var armor := p.stats.get_raw(Stats.ARMOR)
	var thorns := p.stats.get_raw(Stats.THORNS)
	_add(p, T, "trailwise", 3)
	for n in range(1, 4):
		_add(p, T, "briar_hide")
		check_near(p.stats.get_raw(Stats.ARMOR), armor + 2.0 * n, 0.0001, "+2 Armor per rank (%d)" % n)
		check_near(p.stats.get_raw(Stats.THORNS), thorns + 2.0 * n, 0.0001, "+2 Thorns per rank (%d)" % n)
	check_eq(_talent(T, "briar_hide").text_for_rank(3), "Increases your Armor by 6 and your Thorns by 6.", "rank text")
	_reset(p)
	check_near(p.stats.get_raw(Stats.THORNS), thorns, 0.0001, "reset: Thorns back")


# --- Tier 3 ------------------------------------------------------------------------------------

func test_snared_prey_hits_slowed_enemies_harder() -> void:
	var p := _hunter()
	_add(p, T, "trailwise", 3)
	_add(p, T, "briar_hide", 3)
	var slowed := _enemy(Vector3(0, 0, -3))
	var plain := _enemy(Vector3(2, 0, -3))
	slowed.apply_slow(40.0, 5.0)
	check(slowed.is_slowed() and not plain.is_slowed(), "one enemy is slowed")
	for n in range(1, 3):
		_add(p, T, "snared_prey")
		check_near(p.bonuses.damage_mult(slowed, &"physical", &"weapon"), 1.0 + 0.06 * n, 0.0001, "+6%% against a slowed enemy (%d)" % n)
		check_eq(p.bonuses.damage_mult(plain, &"physical", &"weapon"), 1.0, "nothing against a free one")
	for source: StringName in [&"ability", &"pet", &"dot", &"proc"]:
		check_near(p.bonuses.damage_mult(slowed, &"fire", source), 1.12, 0.0001, "every source: %s" % source)
	check_eq(_talent(T, "snared_prey").text_for_rank(2), "You deal 12% more damage to slowed enemies.", "rank text")


func test_brace_of_snares_lays_more_snares_and_keeps_more_of_them() -> void:
	var p := _hunter()
	check(TalentBot.is_deferred(p, _talent(T, "brace_of_snares")), "a bot defers it until Blast Snare is slotted")
	_add(p, T, "trailwise", 3)
	_add(p, T, "briar_hide", 3)
	_add(p, T, "brace_of_snares")
	check_eq(_talent(T, "brace_of_snares").ability, &"blast_snare", "it changes Blast Snare")
	var params := _params(p, &"blast_snare")
	check_near(float(params["traps"]), 2.0, 0.0001, "two snares per cast")
	check_near(float(params["max_traps"]), 5.0, 0.0001, "five at once")
	var slot := _learn(p, &"blast_snare")
	check(not TalentBot.is_deferred(p, _talent(T, "brace_of_snares")), "slotted: no longer deferred")
	_enemy(Vector3(0, 0, -7))
	check(p.abilities.try_cast(slot), "cast")
	check_eq(_snares().size(), 2, "two snares side by side")
	for i in 3:
		p.abilities.set_cooldown(Db.get_ability(&"blast_snare"), 0.0)
		p.global_position += Vector3(0, 0, -1.5)
		check(p.abilities.try_cast(slot), "cast %d" % (i + 2))
	check(_snares().size() <= 5 and _snares().size() >= 4, "at most five stay (%d)" % _snares().size())
	check_eq(_talent(T, "brace_of_snares").text_for_rank(1),
		"Blast Snare lays 1 more snare per cast, and 2 more can be set at once.", "text")


# --- Tier 4 ------------------------------------------------------------------------------------

func test_close_quarters_needs_a_melee_weapon() -> void:
	var p := _hunter()
	_add(p, T, "trailwise", 3)
	_add(p, T, "briar_hide", 3)
	_add(p, T, "twin_fang_grip", 3)
	check_eq(p.talents.add_block_reason(&"hunter_wildcraft_close_quarters"), "", "addable now")
	for n in range(1, 4):
		_add(p, T, "close_quarters")
		check_eq(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, "a bow: no damage bonus (%d)" % n)
		check_eq(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 1.0, "a bow: no melee relief (%d)" % n)
	check(TalentBot.is_deferred(p, _talent(T, "close_quarters")), "a bow bot defers it")
	# A Polearm is a melee weapon (two-handed: no dual wield, so Twin Fang Grip stays out).
	_wield(p, &"polearm")
	check(PlayerBonuses.weapon_requirement_met(p, &"melee"), "a polearm is melee")
	check(not PlayerBonuses.weapon_requirement_met(p, &"dual_wield"), "but not dual wield")
	check_near(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.12, 0.0001, "+4% damage per rank")
	check_near(p.bonuses.damage_mult(null, &"fire", &"ability"), 1.12, 0.0001, "every source")
	check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 0.91, 0.0001, "-3% melee damage taken per rank")
	check_eq(p.bonuses.damage_taken_mult(CombatMath.KIND_PROJECTILE, null), 1.0, "projectiles are not melee")
	check_eq(p.bonuses.damage_taken_mult(CombatMath.KIND_AOE, null), 1.0, "nor ground attacks")
	check(not TalentBot.is_deferred(p, _talent(T, "close_quarters")), "not deferred with a melee weapon")
	check_eq(_talent(T, "close_quarters").text_for_rank(3),
		"While you wield a melee weapon, you deal 12% more damage and take 9% less melee damage.", "rank text")
	# Sword + dagger: melee and dual wield, both talents apply.
	_wield(p, &"sword", &"dagger")
	check_near(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0 + 0.12 + 0.12, 0.0001, "dual wield and melee together (the bonuses add)")


func test_close_quarters_needs_twin_fang_grip_first() -> void:
	var p := _hunter()
	_add(p, T, "trailwise", 3)
	_add(p, T, "powder_lore", 3)
	_add(p, T, "briar_hide", 3)
	check_eq(p.talents.add_block_reason(&"hunter_wildcraft_close_quarters"), "Requires Twin Fang Grip", "prerequisite")
	check_eq(p.talents.add_block_reason(&"hunter_wildcraft_fleet_retreat"), "", "Fleet Retreat only needs Trailwise")


func test_fleet_retreat_changes_backstep() -> void:
	var p := _hunter()
	check_eq(p.talents.add_block_reason(&"hunter_wildcraft_fleet_retreat"), "Needs 9 points in Wildcraft", "tier 4 is gated")
	_add(p, T, "trailwise", 3)
	_add(p, T, "powder_lore", 3)
	_add(p, T, "briar_hide", 3)
	var base := _params(p, &"backstep")
	check_near(float(base["slow"]), 40.0, 0.0001, "Backstep slows 40% to begin with")
	for n in range(1, 4):
		_add(p, T, "fleet_retreat")
		var now := _params(p, &"backstep")
		check_near(float(now["cooldown"]), float(base["cooldown"]) * (1.0 - 0.08 * n), 0.0001, "-8%% cooldown per rank (%d)" % n)
		check_near(float(now["slow"]), 40.0 + 8.0 * n, 0.0001, "+8%% slow per rank (%d)" % n)
	check_eq(_talent(T, "fleet_retreat").text_for_rank(3), "Backstep recharges 24% faster and slows enemies 24% more.", "rank text")
	# In play: the leap leaves a 64% slow on the pack it left behind.
	var e := _enemy(Vector3(0, 0, -2))
	check(p.abilities.try_cast(1), "Backstep")
	check_near(e.slow_pct, 64.0, 0.001, "40% + 24%")
	check_near(p.abilities.remaining(1), 8.0 * 0.76, 0.001, "recharge 24% faster")
	check_near(float(_params(p, &"blast_snare")["cooldown"]), 8.0 * 0.82, 0.0001, "Blast Snare: only Powder Lore's -18%")


# --- Firebug Bombs -----------------------------------------------------------------------------

func test_firebug_bombs_is_a_data_capstone_on_blast_snare() -> void:
	var p := _hunter()
	check_eq(p.talents.add_block_reason(FB_ID), "Needs 12 points in Wildcraft", "gated")
	var neutral := _params(p, &"blast_snare")
	check(neutral["ember_duration"] == 0.0 and neutral["ember_pct"] == 0.0 and neutral["scatter"] == 0, "neutral: no embers, no bombs")
	_to_capstone(p)
	check(_talent(T, "firebug_bombs").is_capstone(), "capstone")
	for e in _talent(T, "firebug_bombs").effects:
		check_eq(e["kind"], "ability", "data only: no script")
	var params := _params(p, &"blast_snare")
	check_near(float(params["ember_duration"]), 4.0, 0.0001, "4 s of burning ground")
	check_near(float(params["ember_pct"]), 25.0, 0.0001, "25% W")
	check_near(float(params["ember_tick"]), 0.5, 0.0001, "every half second")
	check_near(float(params["scatter"]), 3.0, 0.0001, "three bombs")
	check_eq(_talent(T, "firebug_bombs").text_for_rank(1),
		"Blast Snare leaves burning ground for 4 sec (25% weapon damage every half second) and scatters 3 smaller bombs.", "text")
	_reset(p)
	check_eq(float(_params(p, &"blast_snare")["scatter"]), 0.0, "reset: no bombs")


func test_firebug_bombs_burn_the_ground_and_scatter_three_bombs() -> void:
	var p := _hunter()
	_to_capstone(p)
	var target := _enemy(Vector3(0, 0, -7))
	var slot := _learn(p, &"blast_snare")
	var power := float(_params(p, &"blast_snare")["power"])
	check(p.abilities.try_cast(slot), "cast")
	var snares := _snares()
	check_eq(snares.size(), 1, "one snare")
	var at := snares[0].global_position
	# One enemy at each scatter bomb's spot (3 m out, evenly round the burst), one at the blast, one far away.
	var spots: Array[Fakes.FakeEnemy] = []
	for i in 3:
		var angle := TAU * float(i) / 3.0 + 0.5
		spots.append(_enemy(at + Vector3(cos(angle), 0.0, sin(angle)) * 3.0))
	var centre := _enemy(at + Vector3(0.3, 0, 0))
	var far := _enemy(Vector3(0, 0, 6))
	check(target != null, "the enemy the snare was laid for")
	snares[0].burst()
	check_near(centre.fake_damage_log[0], _w(p, &"fire") * 2.2 * power, 0.001, "the snare's own burst")
	for i in 3:
		check_eq(spots[i].fake_hits(), 1, "bomb %d hit its enemy once" % i)
		check_near(spots[i].fake_damage_log[0], _w(p, &"fire") * 2.2 * power * 0.5, 0.001, "50% of the burst")
	check_eq(far.fake_hits(), 0, "nothing far away")
	var embers := _areas(p)
	check_eq(embers.size(), 1, "burning ground where the snare was")
	if embers.size() == 1:
		check_near(embers[0].duration, 4.0, 0.0001, "for 4 s")
		check_eq(embers[0].school, &"fire", "Fire")
		check_near(embers[0].tick_interval, 0.5, 0.0001, "every half second")
		check_near(embers[0].damage_per_tick, _w(p, &"fire") * 0.25 * power, 0.001, "25% W per tick")
	# The embers burn what stands in them.
	var hits := centre.fake_hits()
	for i in 4 * 60 + 30:
		for a in _areas(p):
			a._physics_process(DT)
	check(centre.fake_hits() >= hits + 6, "the embers tick on (%d new hits)" % (centre.fake_hits() - hits))


func test_firebug_bombs_work_with_brace_of_snares() -> void:
	var p := _hunter()
	_add(p, T, "trailwise", 3)
	_add(p, T, "powder_lore", 3)
	_add(p, T, "briar_hide", 3)
	_add(p, T, "brace_of_snares")
	_add(p, T, "fleet_retreat", 2)
	_add(p, T, "firebug_bombs")
	check_eq(p.talents.tree_points(&"hunter_wildcraft"), 13, "13 points: the modifier route to the capstone")
	var params := _params(p, &"blast_snare")
	check_near(float(params["traps"]), 2.0, 0.0001, "two snares")
	check_near(float(params["scatter"]), 3.0, 0.0001, "and the bombs on each")
	var slot := _learn(p, &"blast_snare")
	_enemy(Vector3(0, 0, -7))
	check(p.abilities.try_cast(slot), "cast")
	check_eq(_snares().size(), 2, "two snares")
	for s in _snares():
		check_near(float(s.numbers["scatter"]), 3.0, 0.0001, "each carries three bombs")
		check_near(float(s.numbers["ember_duration"]), 4.0, 0.0001, "and the embers")
