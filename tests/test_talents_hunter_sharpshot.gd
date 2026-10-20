extends "res://tests/talents_hunter_base.gd"
## Hunter Sharpshot (M8 TALENTS-H, design_hunter 4.2): every talent through player.talents.add ->
## PlayerBonuses on a real Hunter at every rank – Keen Eyes (crit), Heavy Shafts (weapon damage: the
## Arrow Fan arrows are weapon hits), Fletcher's Edge (crit damage), Calm Breath (Focus regeneration),
## Opening Shot (weapon damage above 70% health), Finishing Arrow (Long Shot execute), Quickening Aim
## (stacking Haste on crits), Skewering Shots (Pierce) and the Steady Aura capstone
## (HunterSharpshotSteadyAura: +5% damage for every living hero within 8 m, the Hunter included, on every
## damage source; per-slot keys so two Hunters stack; off in the market, while the Hunter is down and
## beyond the radius; Long Shot recharges twice as fast).

const T := "sharpshot"
const SA_ID := &"hunter_sharpshot_steady_aura"


## The 12 points that open the capstone, then the capstone.
func _to_capstone(p: Player) -> HunterSharpshotSteadyAura:
	_add(p, T, "keen_eyes", 3)
	_add(p, T, "heavy_shafts", 3)
	_add(p, T, "fletchers_edge", 3)
	_add(p, T, "calm_breath", 3)
	_add(p, T, "steady_aura")
	return _aura(p)


func _aura(p: Player) -> HunterSharpshotSteadyAura:
	return p.bonuses.script_for(SA_ID) as HunterSharpshotSteadyAura


## The 6 points of tier 1 and 2 (Keen Eyes, Fletcher's Edge: no weapon damage among them) that open tier 3.
func _to_tier_three(p: Player) -> void:
	_add(p, T, "keen_eyes", 3)
	_add(p, T, "fletchers_edge", 3)


func _arrows(p: Player) -> Array[HunterArrow]:
	var out: Array[HunterArrow] = []
	for node in tree.get_nodes_in_group(&"projectiles"):
		var a := node as HunterArrow
		if a != null and a.attacker == p and not a.is_queued_for_deletion():
			out.append(a)
	return out


func _fly(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		for a in _arrows(p):
			a.advance(DT)
		t += DT


# --- Tier 1 and 2 ------------------------------------------------------------------------------

func test_keen_eyes_adds_crit_chance() -> void:
	var p := _hunter()
	var crit := p.stats.get_raw(Stats.CRIT)
	for n in range(1, 4):
		_add(p, T, "keen_eyes")
		check_near(p.stats.get_raw(Stats.CRIT), crit + 2.0 * n, 0.0001, "+2%% crit per rank (%d)" % n)
	check_eq(_talent(T, "keen_eyes").text_for_rank(3), "Increases your Critical Strike chance by 6%.", "rank text")
	_reset(p)
	check_near(p.stats.get_raw(Stats.CRIT), crit, 0.0001, "reset: crit back")


func test_heavy_shafts_boost_weapon_hits_and_so_the_arrow_fan() -> void:
	var p := _hunter()
	for n in range(1, 4):
		_add(p, T, "heavy_shafts")
		check_near(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0 + 0.03 * n, 0.0001, "+3%% weapon damage per rank (%d)" % n)
	for source: StringName in [&"ability", &"dot", &"pet", &"proc"]:
		check_eq(p.bonuses.damage_mult(null, &"physical", source), 1.0, "%s damage is untouched" % source)
	check_eq(_talent(T, "heavy_shafts").text_for_rank(3), "Your weapon hits deal 9% more damage.", "rank text")
	# An Arrow Fan arrow is a weapon hit: it gets the bonus.
	var e := _enemy(Vector3(0, 0, -4))
	check(p.abilities.try_cast(0), "Arrow Fan")
	_fly(p, 0.6)
	check_eq(e.fake_hits(), 1, "one arrow reached the enemy")
	check_near(e.fake_damage_log[0], _w(p) * 1.2 * 1.09, 0.001, "120% W x 1.09")
	_reset(p)
	check_eq(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, "reset: back to 1")


func test_fletchers_edge_raises_the_crit_multiplier() -> void:
	var p := _hunter()
	_add(p, T, "keen_eyes", 3)
	var mult := CombatMath.crit_multiplier(p.main_hand, p.stats)
	var cd := p.stats.get_raw(Stats.CRIT_DAMAGE)
	for n in range(1, 4):
		_add(p, T, "fletchers_edge")
		check_near(p.stats.get_raw(Stats.CRIT_DAMAGE), cd + 8.0 * n, 0.0001, "+8%% crit damage per rank (%d)" % n)
		check_near(CombatMath.crit_multiplier(p.main_hand, p.stats), mult + 0.08 * n, 0.0001, "the crit multiplier grows (%d)" % n)
	check_eq(_talent(T, "fletchers_edge").text_for_rank(3), "Your critical strikes deal 24% more damage.", "rank text")


func test_calm_breath_regenerates_focus_faster() -> void:
	var p := _hunter()
	_to_tier_three(p)
	var focus := HunterKit.focus(p)
	check_near(focus.regen_per_second(), 10.0, 0.0001, "10 Focus per second at the start")
	for n in range(1, 4):
		_add(p, T, "calm_breath")
		check_near(focus.regen_per_second(), 10.0 + n, 0.0001, "+1 per second per rank (%d)" % n)
	check_eq(_talent(T, "calm_breath").text_for_rank(3), "Your Focus regenerates 3 per second faster.", "rank text")
	focus.set_value(0.0)
	p.abilities._physics_process(1.0)
	check_near(focus.value, 13.0, 0.01, "13 Focus after one second")
	_reset(p)
	check_near(focus.regen_per_second(), 10.0, 0.0001, "reset: 10 again")


# --- Tier 3 ------------------------------------------------------------------------------------

func test_opening_shot_needs_a_healthy_target() -> void:
	var p := _hunter()
	_to_tier_three(p)
	var healthy := _enemy(Vector3(0, 0, -3))
	var hurt := _enemy(Vector3(2, 0, -3))
	hurt.hp = 600.0
	var edge := _enemy(Vector3(-2, 0, -3))
	edge.hp = 700.0
	for n in range(1, 3):
		_add(p, T, "opening_shot")
		check_near(p.bonuses.damage_mult(healthy, &"physical", &"weapon"), 1.0 + 0.05 * n, 0.0001, "+5%% above 70%% health (%d)" % n)
		check_eq(p.bonuses.damage_mult(hurt, &"physical", &"weapon"), 1.0, "nothing at 60%")
		check_eq(p.bonuses.damage_mult(edge, &"physical", &"weapon"), 1.0, "exactly 70% is not above it")
		check_eq(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, "no target, no bonus")
	check_eq(p.bonuses.damage_mult(healthy, &"physical", &"ability"), 1.0, "weapon hits only")
	check_eq(p.bonuses.damage_mult(healthy, &"physical", &"pet"), 1.0, "not the companion")
	check_eq(_talent(T, "opening_shot").text_for_rank(2), "Your weapon hits deal 10% more damage to enemies above 70% health.", "rank text")


func test_finishing_arrow_hits_wounded_enemies_with_long_shot() -> void:
	var p := _hunter()
	check(TalentBot.is_deferred(p, _talent(T, "finishing_arrow")), "a bot defers it until Long Shot is slotted")
	_to_tier_three(p)
	check_eq(_params(p, &"long_shot")["execute_bonus"], 0.0, "neutral: no bonus")
	_add(p, T, "finishing_arrow")
	check_eq(_talent(T, "finishing_arrow").ability, &"long_shot", "it changes Long Shot")
	check_near(float(_params(p, &"long_shot")["execute_bonus"]), 60.0, 0.0001, "execute_bonus 60")
	check_near(float(_params(p, &"long_shot")["execute_threshold"]), 35.0, 0.0001, "below 35%")
	var healthy := _enemy(Vector3(0, 0, -4))
	var wounded := _enemy(Vector3(0, 0, -7))
	wounded.hp = 300.0
	var slot := _learn(p, &"long_shot")
	check(not TalentBot.is_deferred(p, _talent(T, "finishing_arrow")), "slotted: no longer deferred")
	check(p.abilities.try_cast(slot), "Long Shot")
	for i in 50:
		p.abilities._physics_process(DT)
	_fly(p, 1.0)
	check_near(healthy.fake_damage_log[0], _w(p) * 3.2, 0.001, "a healthy enemy: the normal hit")
	check_near(wounded.fake_damage_log[0], _w(p) * 3.2 * 1.6, 0.001, "a wounded enemy takes 60% more")
	check_eq(_talent(T, "finishing_arrow").text_for_rank(1),
		"Long Shot deals 60% more damage to enemies below 35% health.", "text")


# --- Tier 4 ------------------------------------------------------------------------------------

func test_quickening_aim_stacks_haste_on_crits_up_to_five_times() -> void:
	var p := _hunter()
	var e := _enemy(Vector3(1.2, 0, 0))
	_add(p, T, "keen_eyes", 3)
	_add(p, T, "heavy_shafts", 3)
	check_eq(p.talents.add_block_reason(&"hunter_sharpshot_quickening_aim"), "Needs 9 points in Sharpshot", "tier 4 is gated")
	_add(p, T, "fletchers_edge", 3)
	_add(p, T, "calm_breath", 3)
	var haste := p.stats.get_raw(Stats.HASTE)
	_add(p, T, "quickening_aim", 3)
	var defs := p.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS)
	check_eq(defs.size(), 1, "one proc")
	if defs.size() == 1:
		var def: Dictionary = defs[0]
		check(def.get("trigger") == "on_crit" and def.get("effect") == "buff" and def.get("max_stacks") == 5, "an on-crit buff, 5 stacks")
		check(def.get("duration") == 4.0 and def.get("stats", {}).get("haste") == 3.0, "+1% Haste per rank, 4 sec")
	p.procs.on_hit(e, 5.0, p.main_hand, false)
	check_near(p.stats.get_raw(Stats.HASTE), haste, 0.0001, "a plain hit does nothing")
	for n in range(1, 5):
		p.procs.on_hit(e, 5.0, p.main_hand, true)
		check_near(p.stats.get_raw(Stats.HASTE), haste + 3.0 * n, 0.0001, "%d stacks: +%d%% Haste" % [n, 3 * n])
	for i in 4:
		p.procs.on_hit(e, 5.0, p.main_hand, true)
	check_near(p.stats.get_raw(Stats.HASTE), haste + 15.0, 0.0001, "at most five stacks")
	p.procs._physics_process(4.1)
	check_near(p.stats.get_raw(Stats.HASTE), haste, 0.0001, "gone 4 sec later")
	check_eq(_talent(T, "quickening_aim").text_for_rank(3),
		"After a critical strike you gain 3% Haste for 4 sec, stacking up to 5 times.", "rank text")
	_reset(p)
	check(p.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS).is_empty(), "reset: no proc")


func test_a_critical_arrow_of_the_fan_feeds_quickening_aim() -> void:
	var p := _hunter()
	_add(p, T, "keen_eyes", 3)
	_add(p, T, "heavy_shafts", 3)
	_add(p, T, "fletchers_edge", 3)
	_add(p, T, "quickening_aim")
	var haste := p.stats.get_raw(Stats.HASTE)
	p.stats.set_source(QUIET, {Stats.CRIT: 500.0, Stats.DODGE: -500.0})
	var e := _enemy(Vector3(0, 0, -4))
	check(p.abilities.try_cast(0), "Arrow Fan")
	_fly(p, 0.6)
	check(e.fake_hits() >= 1, "the fan hit")
	check(e.fake_crit_log[0], "as a crit")
	check_near(p.stats.get_raw(Stats.HASTE), haste + 1.0, 0.0001, "one stack for the cast: the on-hit procs roll once per fan")


func test_skewering_shots_add_pierce_to_the_arrows() -> void:
	var p := _hunter()
	_add(p, T, "keen_eyes", 3)
	_add(p, T, "fletchers_edge", 3)
	var pierce := p.stats.get_raw(Stats.PIERCE)
	check_eq(p.talents.add_block_reason(&"hunter_sharpshot_skewering_shots"), "Needs 9 points in Sharpshot", "tier 4 is gated")
	_add(p, T, "heavy_shafts", 3)
	for n in range(1, 4):
		_add(p, T, "skewering_shots")
		check_near(p.stats.get_raw(Stats.PIERCE), pierce + n, 0.0001, "+%d Pierce" % n)
		check_eq(CombatMath.extra_pierce(p.stats), n, "whole enemies pierced")
	check_eq(_talent(T, "skewering_shots").text_for_rank(3), "Increases the Pierce of your arrows by 3.", "rank text")
	_enemy(Vector3(0, 0, -5))
	check(p.abilities.try_cast(0), "Arrow Fan")
	var arrows := _arrows(p)
	check(arrows.size() >= 5, "the fan")
	for a in arrows:
		check_eq(a.pierce, 3, "every arrow pierces 3 more enemies")
	_reset(p)
	check_eq(CombatMath.extra_pierce(p.stats), 0, "reset: none")


# --- Steady Aura -------------------------------------------------------------------------------

func test_steady_aura_is_a_capstone_that_needs_twelve_points() -> void:
	var p := _hunter()
	check_eq(p.talents.add_block_reason(SA_ID), "Needs 12 points in Sharpshot", "gated")
	var a := _to_capstone(p)
	check(a != null, "the script runs")
	check(_talent(T, "steady_aura").is_capstone(), "capstone")
	check_eq(a.key, &"hunter_steady_aura:0", "one key per Hunter (its slot)")
	check_eq(_talent(T, "steady_aura").text_for_rank(1),
		"Heroes within 8 m of you (you included) deal 5% more damage, and Long Shot recharges twice as fast.", "text")


func test_steady_aura_halves_the_long_shot_cooldown() -> void:
	var p := _hunter()
	check_near(float(_params(p, &"long_shot")["cooldown"]), 9.0, 0.0001, "9 s before")
	_to_capstone(p)
	check_near(float(_params(p, &"long_shot")["cooldown"]), 4.5, 0.0001, "4.5 s: twice as fast")
	check_near(float(_params(p, &"hunt_signal")["cooldown"]), 10.0, 0.0001, "other abilities untouched")
	_enemy(Vector3(0, 0, -4))
	var slot := _learn(p, &"long_shot")
	check(p.abilities.try_cast(slot), "cast")
	check_near(p.abilities.remaining(slot), 4.5, 0.001, "the cooldown that starts is 4.5 s")


func test_steady_aura_buffs_heroes_within_eight_metres_and_the_hunter() -> void:
	var p := _hunter(0)
	var near := _ally(1, Vector3(5, 0, 0))
	var edge := _ally(2, Vector3(0, 0, 7.9))
	var far := _ally(3, Vector3(-8.2, 0, 0))
	var a := _to_capstone(p)
	var state := RunState.rng.state
	p.begin_wave()
	near.begin_wave()
	edge.begin_wave()
	far.begin_wave()
	_tick(p, DT)
	for hero: Player in [p, near, edge]:
		check_near(float(hero.damage_mults.get(a.key, 0.0)), 1.05, 0.0001, "%s: +5%%" % hero.name)
	check(not far.damage_mults.has(a.key), "beyond 8 m: nothing")
	check_eq(a.buffed().size(), 3, "three heroes hold it")
	# Every damage source, multiplied with the rest.
	var e := _enemy(Vector3(1, 0, 0))
	for source: StringName in [&"ability", &"dot", &"pet", &"proc"]:
		check_near(near.outgoing_damage_mult(e, &"fire", source), 1.05, 0.0001, "the ally's %s damage" % source)
	check_near(near.outgoing_damage_mult(e, &"physical", &"weapon"), 1.05, 0.0001, "the ally's weapon damage")
	check_near(p.outgoing_damage_mult(null, &"fire", &"dot"), 1.05, 0.0001, "the Hunter's own dot damage")
	check_near(p.outgoing_damage_mult(e, &"physical", &"weapon"), 1.05 * 1.09, 0.0001, "the Hunter: Heavy Shafts on top")
	check(p.get_node_or_null("SteadyAuraRing") != null, "a faint ring shows the radius")
	check_eq(a.describe(), "Steady Aura: 3 heroes inside", "describe")
	check_eq(RunState.rng.state, state, "no RNG")


func test_the_buff_follows_who_is_in_range() -> void:
	var p := _hunter(0)
	var walker := _ally(1, Vector3(12, 0, 0))
	var a := _to_capstone(p)
	p.begin_wave()
	_tick(p, 0.3)
	check(not walker.damage_mults.has(a.key), "out of range")
	walker.global_position = Vector3(6, 0, 0)
	_tick(p, 0.1)
	check(not walker.damage_mults.has(a.key), "re-checked every 0.25 s: not yet")
	_tick(p, 0.3)
	check_near(float(walker.damage_mults.get(a.key, 0.0)), 1.05, 0.0001, "walked in: it gets the buff")
	walker.global_position = Vector3(9, 0, 0)
	_tick(p, 0.3)
	check(not walker.damage_mults.has(a.key), "walked out: it is gone")
	check_eq(a.buffed().size(), 1, "only the Hunter holds it")
	# The Hunter walks: the circle moves with it.
	p.global_position = Vector3(8, 0, 0)
	_tick(p, 0.3)
	check(walker.damage_mults.has(a.key), "the Hunter moved towards the ally")


func test_a_downed_ally_loses_it_and_a_downed_hunter_drops_the_aura() -> void:
	var p := _hunter(0)
	var ally := _ally(1, Vector3(4, 0, 0))
	var a := _to_capstone(p)
	p.begin_wave()
	_tick(p, 0.3)
	check(ally.damage_mults.has(a.key) and p.damage_mults.has(a.key), "both hold it")
	ally.downed = true
	_tick(p, 0.3)
	check(not ally.damage_mults.has(a.key), "a downed ally loses it")
	check(p.damage_mults.has(a.key), "the Hunter keeps it")
	ally.downed = false
	_tick(p, 0.3)
	check(ally.damage_mults.has(a.key), "revived and in range: back")
	p.downed = true
	_tick(p, 0.3)
	check(not ally.damage_mults.has(a.key) and not p.damage_mults.has(a.key), "a downed Hunter: nobody has it")
	check(p.get_node_or_null("SteadyAuraRing") == null or p.get_node("SteadyAuraRing").is_queued_for_deletion(), "no ring")
	check(not a.is_active(), "inactive")
	_tick(p, 5.0)
	check(not ally.damage_mults.has(a.key), "and it stays off")
	p.downed = false
	_tick(p, 0.3)
	check(ally.damage_mults.has(a.key) and p.damage_mults.has(a.key), "the revived Hunter: the aura is back")


func test_the_market_never_sees_the_aura() -> void:
	var p := _hunter(0)
	var ally := _ally(1, Vector3(3, 0, 0))
	var a := _to_capstone(p)
	_tick(p, 2.0)
	check(not ally.damage_mults.has(a.key) and not p.damage_mults.has(a.key), "no wave yet: no aura")
	p.begin_wave()
	ally.begin_wave()
	_tick(p, 0.3)
	check(ally.damage_mults.has(a.key), "the wave runs: on")
	p.end_wave()
	check(not ally.damage_mults.has(a.key) and not p.damage_mults.has(a.key), "wave end: gone")
	check(p.get_node_or_null("SteadyAuraRing") == null or p.get_node("SteadyAuraRing").is_queued_for_deletion(), "ring gone")
	_tick(p, 3.0)
	check(not ally.damage_mults.has(a.key), "and not back in the market")
	p.begin_wave()
	ally.begin_wave()
	check(not ally.damage_mults.has(a.key), "a wave start is clean")
	_tick(p, 0.3)
	check(ally.damage_mults.has(a.key), "and the aura returns")


func test_taking_the_talent_back_removes_every_key_and_the_ring() -> void:
	var p := _hunter(0)
	var ally := _ally(1, Vector3(3, 0, 0))
	var a := _to_capstone(p)
	var key := a.key
	p.begin_wave()
	_tick(p, 0.3)
	check(ally.damage_mults.has(key) and p.damage_mults.has(key), "running")
	_reset(p)
	check(_aura(p) == null, "the script is gone")
	check(not ally.damage_mults.has(key) and not p.damage_mults.has(key), "teardown removed every key")
	check(p.get_node_or_null("SteadyAuraRing") == null or p.get_node("SteadyAuraRing").is_queued_for_deletion(), "and the ring")
	check_near(float(_params(p, &"long_shot")["cooldown"]), 9.0, 0.0001, "and the cooldown mod")


func test_two_hunters_stack_on_a_hero_both_reach() -> void:
	var a_hunter := _hunter(0, Vector3(-3, 0, 0))
	var b_hunter := _hunter(1, Vector3(3, 0, 0))
	var middle := _ally(2, Vector3(0, 0, 0))
	var a := _to_capstone(a_hunter)
	var b := _to_capstone(b_hunter)
	check(a.key != b.key, "one key per Hunter (%s, %s)" % [a.key, b.key])
	for hero: Player in [a_hunter, b_hunter, middle]:
		hero.begin_wave()
	_tick(a_hunter, 0.3)
	_tick(b_hunter, 0.3)
	check_near(middle.outgoing_damage_mult(null, &"fire", &"dot"), 1.05 * 1.05, 0.0001, "two Steady Auras: +10.25%")
	check_near(a_hunter.outgoing_damage_mult(null, &"fire", &"dot"), 1.05 * 1.05, 0.0001, "each Hunter also holds the other's aura")
	# One Hunter's aura ends: the other's stays.
	a_hunter.end_wave()
	check_near(middle.outgoing_damage_mult(null, &"fire", &"dot"), 1.05, 0.0001, "only the second aura is left")


func test_a_freed_ally_is_forgotten() -> void:
	var p := _hunter(0)
	var ally := _ally(1, Vector3(3, 0, 0))
	var a := _to_capstone(p)
	p.begin_wave()
	_tick(p, 0.3)
	check_eq(a.buffed().size(), 2, "two heroes")
	ally.get_parent().remove_child(ally)
	ally.free()
	_tick(p, 0.3)
	check_eq(a.buffed().size(), 1, "the freed ally dropped out")
