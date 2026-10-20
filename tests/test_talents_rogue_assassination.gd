extends "res://tests/talents_rogue_base.gd"
## Rogue Assassination (M5 Wave 2, talents_rogue.md §1, §4.1, §4.4): every talent through
## player.talents.add -> PlayerBonuses on a real Rogue – Malice, Improved Poisons, Lethality
## (stats), Seal Fate (on_crit Combo Point proc), Coup de Grace (Fan of Knives combo bonus),
## Envenom (the FoK kit's poison detonation), Venomous Wounds / Master Poisoner (the
## rogue_deadly_poison pseudo id in RogueMastery), Cold Blood (the FoK kit's every-3rd-fan
## counter) – plus the kit's neutrality without talents.

const T := "assassination"


## The 12 points that open the capstone (talents_rogue.md 5.4 without the modifier).
func _to_capstone(p: Player) -> void:
	_add(p, T, "malice", 3)
	_add(p, T, "improved_poisons", 3)
	_add(p, T, "seal_fate", 3)
	_add(p, T, "coup_de_grace", 3)
	_add(p, T, "cold_blood")


# --- Tier 1-4 ----------------------------------------------------------------------------------

func test_malice_improved_poisons_and_lethality_add_stats_and_reset_restores() -> void:
	var p := _rogue()
	var crit := p.stats.get_raw(Stats.CRIT)
	var mastery := p.stats.get_raw(Stats.MASTERY)
	var crit_damage := p.stats.get_raw(Stats.CRIT_DAMAGE)
	for n in range(1, 4):
		_add(p, T, "malice")
		check_near(p.stats.get_raw(Stats.CRIT), crit + 2.0 * n, 0.0001, "Malice +2%% crit per rank (%d)" % n)
	for n in range(1, 4):
		_add(p, T, "improved_poisons")
		check_near(p.stats.get_raw(Stats.MASTERY), mastery + 3.0 * n, 0.0001, "Improved Poisons +3 Mastery per rank (%d)" % n)
	var share_before := _mastery(p).stack_damage(100.0)
	check_near(share_before, 100.0 * (20.0 + p.stats.get_raw(Stats.MASTERY)) / 100.0, 0.0001,
			"a Lethal Venom stack takes the Mastery's share")
	for n in range(1, 3):
		_add(p, T, "lethality")
		check_near(p.stats.get_raw(Stats.CRIT_DAMAGE), crit_damage + 10.0 * n, 0.0001, "Lethality +10%% crit damage per rank (%d)" % n)
	check_eq(_talent(&"rogue_assassination_lethality").text_for_rank(2), "Your critical strikes deal 20% more damage.", "rank text")
	_remove(p, T, "lethality")
	check_near(p.stats.get_raw(Stats.CRIT_DAMAGE), crit_damage + 10.0, 0.0001, "X takes one back")
	_reset(p)
	check_near(p.stats.get_raw(Stats.CRIT), crit, 0.0001, "reset: crit back")
	check_near(p.stats.get_raw(Stats.MASTERY), mastery, 0.0001, "reset: Mastery back")
	check_near(p.stats.get_raw(Stats.CRIT_DAMAGE), crit_damage, 0.0001, "reset: crit damage back")


func test_seal_fate_needs_malice_and_gives_a_combo_point_on_crits() -> void:
	var p := _rogue()
	check_eq(p.talents.add_block_reason(&"rogue_assassination_seal_fate"), "Needs 3 points in Toxins", "tier gate")
	_add(p, T, "improved_poisons", 3)
	check_eq(p.talents.add_block_reason(&"rogue_assassination_seal_fate"), "Requires Malice", "prerequisite")
	_add(p, T, "malice", 3)
	_add(p, T, "seal_fate", 3)
	var procs := _procs_of(p, &"rogue_assassination_seal_fate")
	check_eq(procs.size(), 1, "one proc")
	check(procs[0].trigger == &"on_crit" and procs[0].effect == &"resource", "an on_crit resource proc")
	check_near(procs[0].chance, 45.0, 0.0001, "15% per rank")
	check_eq(procs[0].label, "", "silent")
	_force_procs(p, &"rogue_assassination_seal_fate")
	var e := Fakes.spawn_enemy(world, Vector3(0, 0, -1.2))
	WeaponRunner.apply_hit(p, e, 5.0, false, Vector3.ZERO)
	check_eq(_combo(p).value, 0.0, "a normal hit gives nothing")
	WeaponRunner.apply_hit(p, e, 12.0, true, Vector3.ZERO)
	check_eq(_combo(p).value, 2.0, "a crit: its own Combo Point + Fateful Cuts's (exact: pips)")
	_remove(p, T, "seal_fate", 3)
	check(_procs_of(p, &"rogue_assassination_seal_fate").is_empty(), "taken back: no proc")


func test_coup_de_grace_raises_the_combo_bonus_of_fan_of_knives() -> void:
	var p := _rogue()
	var fan := _fan(p)
	check_near(float(p.abilities.params_for(fan)["combo_bonus_pct"]), 20.0, 0.0001, "base 20% per point")
	_add(p, T, "malice", 3)
	for n in range(1, 4):
		_add(p, T, "coup_de_grace")
		check_near(float(p.abilities.params_for(fan)["combo_bonus_pct"]), 20.0 + 2.0 * n, 0.0001, "+2%% per point per rank (%d)" % n)
	_combo(p).set_value(5.0)
	var expected := CombatMath.weapon_hit_damage(p.main_hand, p.stats) * 1.1 * (1.0 + 5.0 * 0.26)
	for k in _throw_fan(p):
		check_near(k.damage, expected, 0.0001, "5 points x 26%")
	check_eq(_talent(&"rogue_assassination_coup_de_grace").text_for_rank(3),
			"Knife Bloom deals an extra 6% damage for each Combo Point it spends.", "rank text")
	_reset(p)
	check_near(float(p.abilities.params_for(fan)["combo_bonus_pct"]), 20.0, 0.0001, "reset")


func test_venomous_wounds_gives_energy_for_poisoned_kills_only() -> void:
	var p := _rogue()
	_add(p, T, "malice", 3)
	_add(p, T, "improved_poisons", 3)
	_add(p, T, "seal_fate", 3)
	var mastery := _mastery(p)
	check_eq(mastery.kill_energy(), 0.0, "nothing before the talent")
	_add(p, T, "venomous_wounds", 3)
	check_eq(mastery.kill_energy(), 3.0, "+1 Energy per rank (pseudo id rogue_deadly_poison)")
	var poisoned := Fakes.spawn_enemy(world, Vector3(2, 0, 0))
	var clean := Fakes.spawn_enemy(world, Vector3(-2, 0, 0))
	mastery.poison(poisoned, 8.0)
	_energy(p).set_value(10.0)
	p.notify_kill(clean)
	check_eq(_energy(p).value, 10.0, "an unpoisoned kill: nothing")
	p.notify_kill(poisoned)
	check_eq(_energy(p).value, 13.0, "a poisoned kill: +3 Energy")
	var consumed := Fakes.spawn_enemy(world, Vector3(0, 0, 2))
	mastery.poison(consumed, 8.0)
	check(mastery.consume(consumed) > 0.0, "Overdose took the poison")
	check_eq(mastery.stacks_on(consumed), 0, "no stacks left")
	p.notify_kill(consumed)
	check_eq(_energy(p).value, 16.0, "a kill right after Overdose still counts")
	mastery.tick(DT)
	p.notify_kill(consumed)
	check_eq(_energy(p).value, 16.0, "but only within the tick")
	var late := Fakes.spawn_enemy(world, Vector3(0, 0, -2))
	mastery.poison(late, 8.0)
	p.downed = true
	p.notify_kill(late)
	check_eq(_energy(p).value, 16.0, "a downed Rogue gets only the credit")
	p.downed = false
	_energy(p).set_value(0.0)
	p.stats.set_source(&"test_regen", {Stats.RESOURCE_REGEN: 50.0})
	p.abilities._physics_process(DT)
	_energy(p).set_value(0.0)
	p.notify_kill(late)
	check_near(_energy(p).value, 4.5, 0.0001, "Resource Regen scales it (Energy is a bar)")
	_remove(p, T, "venomous_wounds", 3)
	check_eq(mastery.kill_energy(), 0.0, "taken back: the cache follows PlayerBonuses.changed")


func test_master_poisoner_adds_stacks_and_nature_damage() -> void:
	var p := _rogue()
	var mastery := _mastery(p)
	check_eq(mastery.max_stacks(), RogueMastery.MAX_STACKS, "5 stacks")
	_add(p, T, "improved_poisons", 3)
	_add(p, T, "malice", 3)
	_add(p, T, "coup_de_grace", 3)
	check(p.talents.can_add(&"rogue_assassination_master_poisoner"), "Improved Poisons 3/3 opens it")
	for n in range(1, 4):
		_add(p, T, "master_poisoner")
		check_eq(mastery.max_stacks(), 5 + n, "+1 stack per rank (%d)" % n)
		check_near(p.bonuses.damage_mult(null, &"nature", &"dot"), 1.0 + 0.04 * n, 0.0001, "+4%% Nature per rank (%d)" % n)
	check_eq(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, "Nature only")
	var e := Fakes.spawn_enemy(world, Vector3(0, 0, -2))
	for i in 10:
		mastery.on_hit(e, 10.0, true)
	check_eq(mastery.stacks_on(e), 8, "eight stacks on one enemy")
	check(mastery.describe().contains("8 times"), "the Mastery text follows")
	_reset(p)
	check_eq(mastery.max_stacks(), 5, "reset: 5 again")
	var other := Fakes.spawn_enemy(world, Vector3(0, 0, 2))
	for i in 8:
		mastery.on_hit(other, 10.0, true)
	check_eq(mastery.stacks_on(other), 5, "five stacks without the talent")


# --- Envenom (modifier) ------------------------------------------------------------------------

func test_envenom_data_is_valid_and_neutral_without_the_talent() -> void:
	var entry := {"kind": "ability", "match": {"id": "fan_of_knives"}, "mods": {"envenom_pct_add": 150.0}}
	check_eq(BonusVocabulary.validate(entry, &"rogue"), "", "envenom_pct_add is a valid mod (the FoK data declares envenom_pct)")
	var envenom := _talent(&"rogue_assassination_envenom")
	check(envenom.is_modifier() and envenom.ability == &"fan_of_knives", "modifier on Knife Bloom")
	var p := _rogue()
	var params := p.abilities.params_for(_fan(p))
	for key in ["envenom_pct", "cdr_per_combo", "cold_blood_crit_damage", "cold_blood_slow", "cold_blood_slow_duration"]:
		check_eq(float(params[key]), 0.0, "neutral %s" % key)
	check_eq(int(params["cold_blood_every"]), 0, "neutral cold_blood_every")


func test_envenom_detonates_the_poison_once_per_enemy() -> void:
	var p := _rogue()
	_add(p, T, "malice", 3)
	_add(p, T, "improved_poisons", 3)
	_add(p, T, "envenom")
	check_eq(float(p.abilities.params_for(_fan(p))["envenom_pct"]), 150.0, "the fan carries 150%")
	var mastery := _mastery(p)
	var e := Fakes.spawn_enemy(world, Vector3(0, 0, -3.0))
	EnemyGrid.mark_dirty()
	for i in 3:
		mastery.poison(e, 12.0)
	check_eq(mastery.stacks_on(e), 3, "three stacks")
	var knives := _throw_fan(p)
	check_eq(knives.size(), 10, "ten knives")
	for k in knives:
		check_eq(k.envenom_pct, 150.0, "every knife envenoms")
	_fly(p)
	check_eq(e.fake_hits(), 2, "the burst + the knife")
	check_near(e.fake_damage_log[0], 3.0 * 12.0 * 1.5, 0.0001, "150% of the 36 undealt poison damage, at once")
	check_eq(e.fake_attacker_log[0], p, "dealt by the Rogue")
	check_eq(mastery.stacks_on(e), 0, "the poison is gone (no knife crit re-poisoned it)")
	var detonations := 0
	for k in _all_knives(p):
		detonations += k.detonations
	check_eq(detonations, 1, "one detonation")


func test_envenom_hits_by_several_knives_detonate_once() -> void:
	var p := _rogue()
	_add(p, T, "malice", 3)
	_add(p, T, "improved_poisons", 3)
	_add(p, T, "envenom")
	var mastery := _mastery(p)
	var big := Fakes.spawn_enemy(world, Vector3(0, 0, -2.6), 1.6)
	EnemyGrid.mark_dirty()
	mastery.poison(big, 20.0)
	_throw_fan(p)
	_fly(p)
	var knife_hits := 0
	var detonations := 0
	for k in _all_knives(p):
		knife_hits += k.hit_count
		detonations += k.detonations
	check(knife_hits >= 2, "a big enemy takes several knives (%d)" % knife_hits)
	check_eq(detonations, 1, "but detonates once")
	check_eq(big.fake_hits(), knife_hits + 1, "the knives + one burst")
	check_near(big.fake_damage_log[0], 20.0 * 1.5, 0.0001, "the burst came first")


func test_without_envenom_the_fan_leaves_the_poison() -> void:
	var p := _rogue()
	var mastery := _mastery(p)
	var e := Fakes.spawn_enemy(world, Vector3(0, 0, -3.0))
	EnemyGrid.mark_dirty()
	for i in 3:
		mastery.poison(e, 12.0)
	_throw_fan(p)
	_fly(p)
	check_eq(e.fake_hits(), 1, "only the knife")
	check_eq(mastery.stacks_on(e), 3, "the poison stays")


func test_envenom_burst_kill_counts_for_venomous_wounds() -> void:
	var p := _rogue()
	_add(p, T, "malice", 3)
	_add(p, T, "improved_poisons", 3)
	_add(p, T, "envenom")
	_add(p, T, "seal_fate", 3)
	_add(p, T, "venomous_wounds", 3)
	var grunt := Enemy.create(Db.get_enemy(&"skeleton_grunt"), 1)
	world.add_child(grunt)
	grunt.global_position = Vector3(0, 0, -3.0)
	EnemyGrid.mark_dirty()
	_mastery(p).poison(grunt, 400.0)
	grunt.hp = 1.0
	var killers: Array[int] = []
	grunt.died.connect(func(_e: Enemy, idx: int) -> void: killers.append(idx))
	_throw_fan(p)
	check_near(_energy(p).value, 65.0, 0.0001, "35 Energy spent")
	_fly(p)
	check(grunt.is_dead(), "the burst killed it")
	check_eq(killers, [0] as Array[int], "credited to the Rogue")
	check_near(_energy(p).value, 68.0, 0.0001, "Toxic Harvest: +3 Energy for the envenomed kill")


## A fan over a poisoned 1 HP grunt (hit first, 1.5 m ahead) and a second enemy (3 m behind
## the hero), Combat Potency 3/3 forced to 100%; returns the Rogue (Energy after the cast: 65).
func _fan_over_a_dying_grunt(envenom: bool) -> Player:
	var p := _rogue()
	_add(p, T, "malice", 3)
	_add(p, T, "improved_poisons", 3)
	if envenom:
		_add(p, T, "envenom")
	_add(p, "combat", "combat_potency", 3)
	_force_procs(p, &"rogue_combat_combat_potency")
	var grunt := Enemy.create(Db.get_enemy(&"skeleton_grunt"), 1)
	world.add_child(grunt)
	grunt.global_position = Vector3(0, 0, -1.5)
	var other := Fakes.spawn_enemy(world, Vector3(0, 0, 3.0))
	EnemyGrid.mark_dirty()
	_mastery(p).poison(grunt, 400.0)
	grunt.hp = 1.0
	_throw_fan(p)
	check_near(_energy(p).value, 65.0, 0.0001, "35 Energy spent")
	_fly(p)
	check(grunt.is_dead(), "the grunt died")
	check_eq(other.fake_hits(), 1, "another knife hit the second enemy")
	var detonations := 0
	var hits := 0
	for k in _all_knives(p):
		detonations += k.detonations
		hits += k.hit_count
	check_eq(detonations, 1 if envenom else 0, "Overdose's burst killed the grunt" if envenom else "no burst")
	check_eq(hits, 2, "two knives landed (the grunt's one counts even on a corpse)")
	return p


func test_without_envenom_the_fan_rolls_its_on_hit_proc_once() -> void:
	var p := _fan_over_a_dying_grunt(false)
	check_near(_energy(p).value, 67.0, 0.0001, "Battle Verve fired once for the fan: +2 Energy")


## The burst's kill leaves its knife on a corpse: no weapon hit, so that knife must not close
## the fan's shared proc gate (the Envenom + Combat Potency hybrid, talents_rogue.md "Twin
## modifiers") – the knife on the second enemy still rolls.
func test_envenom_burst_kill_keeps_the_fans_on_hit_proc() -> void:
	var p := _fan_over_a_dying_grunt(true)
	check_near(_energy(p).value, 67.0, 0.0001, "Battle Verve still fired once for the fan: +2 Energy")


# --- Cold Blood (capstone) ---------------------------------------------------------------------

func test_cold_blood_every_third_fan_crits_harder_and_cripples() -> void:
	var p := _rogue()
	_to_capstone(p)
	var params := p.abilities.params_for(_fan(p))
	check_eq(int(params["cold_blood_every"]), 3, "every 3rd fan")
	check_near(float(params["cold_blood_crit_damage"]), 50.0, 0.0001, "+50% crit damage")
	var effect := RogueFanOfKnives.of(p)
	check(effect != null, "the FoK effect")
	var enemies := _surround(10, 3.0)
	var weapon := p.main_hand
	var base := CombatMath.weapon_hit_damage(weapon, p.stats) * 1.1
	for fan_no in 2:
		var knives := _throw_fan(p)
		for k in knives:
			check(not k.is_crit and k.slow_pct == 0.0, "fan %d rolls normally (no crit chance)" % (fan_no + 1))
		check(not effect.last_cold, "not cold")
		_fly(p)
	check(effect.has_cold_ring(), "after the 2nd fan the crimson ring says the next one is cold")
	var ring := p.get_node_or_null("ColdBloodRing")
	check(ring != null, "the ring is a child of the hero")
	for e in enemies:
		check(not e.is_slowed(), "no slow yet")
	var state := RunState.rng.state
	var cold := _throw_fan(p)
	check_eq(RunState.rng.state, state, "a cold fan draws no crit rolls")
	check(effect.last_cold, "the 3rd fan is cold")
	check_eq(cold.size(), 10, "ten knives")
	var mult := CombatMath.crit_multiplier(weapon, p.stats) + 0.5
	for k in cold:
		check(k.is_crit, "every knife crits")
		check_near(k.damage, base * mult, 0.0001, "crit multiplier + 50%")
		check(k.slow_pct == 30.0 and k.slow_duration == 3.0, "knives carry the slow")
		check_eq(k.color, RogueFanOfKnives.COLD_KNIFE_COLOR, "crimson knives")
	check(not effect.has_cold_ring(), "the ring goes with the cold fan")
	_fly(p)
	for e in enemies:
		check(e.is_slowed() and is_equal_approx(e.slow_pct, 30.0), "every enemy hit is slowed 30%")
		check_near(e.slow_left, 3.0, 0.75, "for about 3 sec")
	check_eq(_combo(p).value, 5.0, "the cold fan refills the Combo Points")
	check_eq(_mastery(p).poisoned_count(), 10, "and poisons the pack")
	var fourth := _throw_fan(p)
	check(not fourth[0].is_crit and not effect.last_cold, "the 4th fan is normal again")


func test_cold_blood_counter_and_ring_follow_the_waves_and_the_talent() -> void:
	var p := _rogue()
	_to_capstone(p)
	var effect := RogueFanOfKnives.of(p)
	_throw_fan(p)
	_throw_fan(p)
	check(effect.fans == 2 and effect.has_cold_ring(), "two fans, ring up")
	p.take_damage(99999.0)
	check(p.downed, "downed")
	check(not (p.get_node("ColdBloodRing") as Node3D).visible, "the ring hides while downed")
	check_eq(effect.fans, 2, "the counter is kept")
	p.revive(1.0)
	check((p.get_node("ColdBloodRing") as Node3D).visible, "back after a revive")
	p.end_wave()
	check(not effect.has_cold_ring(), "end_wave frees the ring")
	p.begin_wave()
	check_eq(effect.fans, 0, "a new wave counts from zero")
	_throw_fan(p)
	_throw_fan(p)
	check(not effect.last_cold and effect.has_cold_ring(), "two fans again")
	_reset(p)
	check_eq(int(p.abilities.params_for(_fan(p))["cold_blood_every"]), 0, "reset: neutral param")
	p.abilities._physics_process(DT)
	check(not effect.has_cold_ring(), "the next tick takes the ring away")
	for i in 3:
		_throw_fan(p)
		check(not effect.last_cold, "no cold fans without the talent")
	check(not effect.has_cold_ring(), "and no ring")


# --- Kit neutrality ----------------------------------------------------------------------------

func test_fan_without_talents_draws_one_crit_roll_per_knife() -> void:
	var p := _rogue()
	p.stats.set_source(QUIET, {Stats.CRIT: 30.0})
	var copy := RandomNumberGenerator.new()
	copy.seed = RunState.rng.seed
	copy.state = RunState.rng.state
	var expected: Array[bool] = []
	for i in 10:
		expected.append(CombatMath.roll_crit(p.stats, copy))
	var knives := _throw_fan(p)
	check_eq(RunState.rng.state, copy.state, "exactly the M4 draws")
	var crits: Array[bool] = []
	for k in knives:
		crits.append(k.is_crit)
		check(k.envenom_pct == 0.0 and k.slow_pct == 0.0 and k.envenomed.is_empty(), "no talent riders")
	check_eq(crits, expected, "the same crits")
	check(not RogueFanOfKnives.of(p).has_cold_ring(), "no ring")


# --- Bot ---------------------------------------------------------------------------------------

func test_assassination_bot_path_reaches_the_capstone_at_13() -> void:
	var p := _rogue()
	var path: Array[StringName] = []
	for i in 30:
		var t := TalentBot.next_talent(p, 0)
		if t == null or not p.talents.add(t.id):
			break
		path.append(t.id)
	check_eq(path.size(), 22, "the whole tree")
	check_eq(path[6], &"rogue_assassination_envenom", "the modifier is point 7")
	check_eq(path[12], &"rogue_assassination_cold_blood", "the capstone is point 13")
	check_eq(path.slice(7, 12), [&"rogue_assassination_seal_fate", &"rogue_assassination_seal_fate",
			&"rogue_assassination_seal_fate", &"rogue_assassination_coup_de_grace",
			&"rogue_assassination_coup_de_grace"] as Array[StringName], "Fateful Cuts 3, Finishing Flourish 2")
	check_eq(path[21], &"rogue_assassination_master_poisoner", "Venom Savant last")
	var q := _rogue(1, Vector3(4, 0, 0))
	check_eq(TalentBot.spend_all(q, 0), 22, "spend_all: the same 22 points")
	check_eq(q.talents.ranks, p.talents.ranks, "same ranks")
