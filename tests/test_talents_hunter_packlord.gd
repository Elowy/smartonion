extends "res://tests/talents_hunter_base.gd"
## Hunter Packlord (M8 TALENTS-H, design_hunter 4.1): every talent through player.talents.add ->
## PlayerBonuses on a real Hunter at every rank – Keen Companion (pet damage), Bonded Vigor (heal_pct),
## Feral Tempo (haste), Piercing Whistle (Hunt Signal power / cooldown), Alpha Hide (damage taken),
## Open Wound (Hunt Signal bleed), Wild Kinship (Mastery -> Beastbond), Kindred Instinct (slow / taunt /
## attack range per companion), and the Pack Frenzy capstone (HunterPacklordPackFrenzy: first frenzy
## 5 s into the wave, every 30 s, 10 s long, +50% damage / +30% attack speed on the companion's hooks,
## never in the market, nothing while the Hunter is down, ends with the wave).

const T := "packlord"
const PF_ID := &"hunter_packlord_pack_frenzy"


## The 12 points that open the capstone, then the capstone.
func _to_capstone(p: Player) -> HunterPacklordPackFrenzy:
	_add(p, T, "keen_companion", 3)
	_add(p, T, "bonded_vigor", 3)
	_add(p, T, "feral_tempo", 3)
	_add(p, T, "piercing_whistle", 3)
	_add(p, T, "pack_frenzy")
	return _frenzy(p)


func _frenzy(p: Player) -> HunterPacklordPackFrenzy:
	return p.bonuses.script_for(PF_ID) as HunterPacklordPackFrenzy


# --- Tier 1 ------------------------------------------------------------------------------------

func test_keen_companion_is_pet_damage_only() -> void:
	var p := _hunter()
	for n in range(1, 4):
		_add(p, T, "keen_companion")
		check_near(p.bonuses.damage_mult(null, &"physical", &"pet"), 1.0 + 0.04 * n, 0.0001, "+4%% pet damage per rank (%d)" % n)
	for source: StringName in [&"weapon", &"ability", &"dot", &"proc"]:
		check_eq(p.bonuses.damage_mult(null, &"physical", source), 1.0, "%s damage is untouched" % source)
	check_eq(_talent(T, "keen_companion").text_for_rank(3), "Your companion deals 12% more damage.", "rank text")
	_reset(p)
	check_eq(p.bonuses.damage_mult(null, &"physical", &"pet"), 1.0, "reset: back to 1")


func test_keen_companion_reaches_the_bite_and_hunt_signal() -> void:
	var p := _hunter()
	_add(p, T, "keen_companion", 3)
	var pet := _pet(p, &"wolf")
	var e := _enemy(Vector3(1.5, 0, 0))
	_step_pet(pet, 0.6)
	check(e.fake_hits() >= 1, "a bite")
	check_near(e.fake_damage_log[0], _w(p) * 0.38 * 1.12, 0.001, "38% W x 1.12")
	var slot := _learn(p, &"hunt_signal")
	var big := _enemy(Vector3(0, 0, -7))
	big.max_hp = 9000.0
	big.hp = 9000.0
	check(p.abilities.try_cast(slot), "Hunt Signal")
	_step_pet(pet, 1.0)
	check_near(big.fake_damage_log[0], _w(p) * 2.5 * 1.12, 0.001, "the blow is pet damage too")


func test_bonded_vigor_heals_a_share_of_the_companions_damage() -> void:
	var p := _hunter()
	for n in range(1, 4):
		_add(p, T, "bonded_vigor")
		check_near(float(_mods(p, PET_MOD).get("heal_pct_add", 0.0)), 4.0 * n, 0.0001, "heal_pct_add %d" % n)
	var pet := _pet(p, &"wolf")
	check_near(float(pet.current_params()["heal_pct"]), 12.0, 0.0001, "the companion's heal_pct: 12%")
	check_eq(_talent(T, "bonded_vigor").text_for_rank(3),
		"Your companion's attacks heal you for 12% of the damage they deal.", "rank text")
	p.hp = p.max_hp() * 0.5
	var before := p.hp
	var e := _enemy(Vector3(1.5, 0, 0))
	_step_pet(pet, 0.6)
	check(e.fake_hits() >= 1, "a bite")
	check_near(p.hp - before, e.fake_damage_log[0] * 0.12, 0.01, "12% of the damage dealt")
	_reset(p)
	check_eq(float(pet.current_params()["heal_pct"]), 0.0, "reset: no healing")


# --- Tier 2 ------------------------------------------------------------------------------------

func test_feral_tempo_needs_keen_companion_and_speeds_the_companion_up() -> void:
	var p := _hunter()
	check_eq(p.talents.add_block_reason(&"hunter_packlord_feral_tempo"), "Needs 3 points in Packlord", "tier 2 is gated")
	_add(p, T, "bonded_vigor", 3)
	check_eq(p.talents.add_block_reason(&"hunter_packlord_feral_tempo"), "Requires Keen Companion", "prerequisite")
	_add(p, T, "keen_companion", 3)
	var pet := _pet(p, &"wolf")
	_step_pet(pet, 0.3)
	check_near(pet.attack_interval(), 1.2, 0.0001, "1.2 s without the talent")
	for n in range(1, 4):
		_add(p, T, "feral_tempo")
		_step_pet(pet, 0.3)
		check_near(pet.attack_interval(), 1.2 / (1.0 + 0.05 * n), 0.0001, "+5%% attack speed per rank (%d)" % n)
	check_eq(_talent(T, "feral_tempo").text_for_rank(3), "Your companion attacks 15% faster.", "rank text")
	var owl := _pet(p, &"owl")
	_step_pet(owl, 0.3)
	check_near(owl.attack_interval(), 0.6 / 1.15, 0.0001, "every companion: the Owl too")


func test_piercing_whistle_changes_hunt_signal_power_and_cooldown() -> void:
	var p := _hunter()
	_add(p, T, "bonded_vigor", 3)
	var base := _params(p, &"hunt_signal")
	for n in range(1, 4):
		_add(p, T, "piercing_whistle")
		var now := _params(p, &"hunt_signal")
		check_near(float(now["power"]), float(base["power"]) * (1.0 + 0.06 * n), 0.0001, "+6%% power per rank (%d)" % n)
		check_near(float(now["cooldown"]), float(base["cooldown"]) * (1.0 - 0.06 * n), 0.0001, "-6%% cooldown per rank (%d)" % n)
	check_eq(_talent(T, "piercing_whistle").text_for_rank(3),
		"Hunt Signal strikes for 18% more damage and recharges 18% faster.", "rank text")
	check_near(float(_params(p, &"backstep")["cooldown"]), 8.0, 0.0001, "Backstep untouched")
	# The blow really is stronger: 250% W x power.
	var slot := _learn(p, &"hunt_signal")
	var pet := _pet(p, &"wolf")
	var e := _enemy(Vector3(0, 0, -7))
	check(p.abilities.try_cast(slot), "cast")
	_step_pet(pet, 1.0)
	check_near(e.fake_damage_log[0], _w(p) * 2.5 * 1.18, 0.001, "250% W x 1.18")
	check_near(p.abilities.remaining(slot), 10.0 * 0.82, 0.001, "recharge 18% faster")


# --- Tier 3 ------------------------------------------------------------------------------------

func test_alpha_hide_takes_a_share_of_every_hit() -> void:
	var p := _hunter()
	_add(p, T, "keen_companion", 3)
	_add(p, T, "bonded_vigor", 3)
	_add(p, T, "feral_tempo", 3)
	_add(p, T, "piercing_whistle", 3)
	for n in range(1, 3):
		_add(p, T, "alpha_hide")
		for kind: StringName in [CombatMath.KIND_MELEE, CombatMath.KIND_PROJECTILE, CombatMath.KIND_AOE]:
			check_near(p.bonuses.damage_taken_mult(kind, null), 1.0 - 0.04 * n, 0.0001, "-4%% %s damage per rank (%d)" % [kind, n])
	check_eq(_talent(T, "alpha_hide").text_for_rank(2), "You take 8% less damage.", "rank text")
	_reset(p)
	check_eq(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 1.0, "reset: back to 1")


func test_open_wound_bleeds_the_hunt_signal_blow() -> void:
	var p := _hunter()
	check(TalentBot.is_deferred(p, _talent(T, "open_wound")), "a bot defers it until Hunt Signal is slotted")
	_add(p, T, "keen_companion", 3)
	_add(p, T, "bonded_vigor", 3)
	_add(p, T, "feral_tempo", 3)
	_add(p, T, "piercing_whistle", 3)
	_add(p, T, "open_wound")
	check_eq(_talent(T, "open_wound").ability, &"hunt_signal", "it changes Hunt Signal")
	check_eq(_talent(T, "open_wound").kind, TalentData.Kind.MODIFIER, "the tier-3 modifier")
	check_near(float(_params(p, &"hunt_signal")["bleed_pct"]), 80.0, 0.0001, "bleed_pct 80")
	check_near(float(_params(p, &"hunt_signal")["bleed_duration"]), 4.0, 0.0001, "over 4 s")
	var slot := _learn(p, &"hunt_signal")
	check(not TalentBot.is_deferred(p, _talent(T, "open_wound")), "slotted: no longer deferred")
	var pet := _pet(p, &"wolf")
	var e := _enemy(Vector3(0, 0, -7))
	check(p.abilities.try_cast(slot), "cast")
	_step_pet(pet, 1.0)
	var blow: float = _w(p) * 2.5 * 1.18
	check_near(e.fake_damage_log[0], blow * 1.12, 0.001, "the blow (Keen Companion +12%)")
	var bleed := HunterBleed.find(e, p, &"hunt_signal")
	check(bleed != null, "a wound")
	if bleed != null:
		check_eq(bleed.source, &"pet", "pet damage")
		check_near(bleed.remaining(), blow * 0.8, 0.01, "80% of the blow's damage again, over 4 s")
		var before := e.fake_hits()
		for i in 4 * 60 + 10:
			bleed._physics_process(DT)
		var dealt := 0.0
		for i in range(before, e.fake_hits()):
			dealt += e.fake_damage_log[i]
		check_near(dealt, blow * 0.8 * 1.12, 0.01, "paid out in full, with the pet multipliers")
	_reset(p)
	check_eq(float(_params(p, &"hunt_signal")["bleed_pct"]), 0.0, "reset: no wound")


# --- Tier 4 ------------------------------------------------------------------------------------

func test_wild_kinship_adds_mastery_and_so_beastbond() -> void:
	var p := _hunter()
	check_eq(p.talents.add_block_reason(&"hunter_packlord_wild_kinship"), "Needs 9 points in Packlord", "tier 4 is gated")
	_add(p, T, "keen_companion", 3)
	_add(p, T, "bonded_vigor", 3)
	_add(p, T, "feral_tempo", 3)
	var mastery := p.stats.get_raw(Stats.MASTERY)
	var m := p.abilities.mastery as HunterMastery
	for n in range(1, 4):
		_add(p, T, "wild_kinship")
		check_near(p.stats.get_raw(Stats.MASTERY), mastery + 3.0 * n, 0.0001, "+3 Mastery per rank (%d)" % n)
		check_near(m.bond_mult(), 1.0 + (mastery + 3.0 * n) * 0.02, 0.0001, "Beastbond follows: +6%% per rank (%d)" % n)
	check_eq(_talent(T, "wild_kinship").text_for_rank(3),
		"Increases your Mastery by 9 (Beastbond: +18% companion damage).", "rank text")
	_reset(p)
	check_near(p.stats.get_raw(Stats.MASTERY), mastery, 0.0001, "reset: Mastery back")


func test_kindred_instinct_gives_each_companion_its_own_gift() -> void:
	var p := _hunter()
	_add(p, T, "keen_companion", 3)
	_add(p, T, "bonded_vigor", 3)
	_add(p, T, "feral_tempo", 3)
	var wolf := HunterCompanion.base_params(&"wolf")
	var boar := HunterCompanion.base_params(&"boar")
	var owl := HunterCompanion.base_params(&"owl")
	for n in range(1, 4):
		_add(p, T, "kindred_instinct")
		var mods := _mods(p, PET_MOD)
		check_near(float(mods["slow_add"]), 8.0 * n, 0.0001, "slow_add %d" % n)
		check_near(float(mods["taunt_duration_add"]), 0.3 * n, 0.0001, "taunt_duration_add %d" % n)
		check_near(float(mods["attack_range_add"]), 1.0 * n, 0.0001, "attack_range_add %d" % n)
	check_eq(_talent(T, "kindred_instinct").text_for_rank(3),
		"Your companion's gift grows: Wolf slows 24% more, Boar taunts 0.9 sec longer, Owl shoots 3 m farther.", "rank text")
	var pet := _pet(p, &"wolf")
	check_near(float(pet.current_params()["slow"]), float(wolf["slow"]) + 24.0, 0.0001, "Wolf: 30% -> 54% slow")
	pet = _pet(p, &"boar")
	check_near(float(pet.current_params()["taunt_duration"]), float(boar["taunt_duration"]) + 0.9, 0.0001, "Boar: 1.5 -> 2.4 s taunt")
	pet = _pet(p, &"owl")
	check_near(float(pet.current_params()["attack_range"]), float(owl["attack_range"]) + 3.0, 0.0001, "Owl: 8 -> 11 m")


func test_kindred_instinct_is_felt_in_play() -> void:
	var p := _hunter()
	_add(p, T, "keen_companion", 3)
	_add(p, T, "bonded_vigor", 3)
	_add(p, T, "feral_tempo", 3)
	_add(p, T, "kindred_instinct", 3)
	# Wolf bite: 54% slow for a second.
	var wolf := _pet(p, &"wolf")
	var e := _enemy(Vector3(1.5, 0, 0))
	_step_pet(wolf, 0.6)
	check_eq(e.slow_pct, 54.0, "the bite slows 54%")
	# Boar charge: the taunt lasts 0.9 s longer.
	_clear_enemies()
	var boar := _pet(p, &"boar")
	var target := _enemy(Vector3(0, 0, -5))
	boar.global_position = Vector3(0, 0, -1)
	var t := 0.0
	while boar.charges_made == 0 and t < 6.0:
		boar.step(DT)
		t += DT
	check_eq(boar.charges_made, 1, "it charged")
	check(target.is_taunted(), "taunted")
	check_near(target.taunt_left, 2.4, 0.05, "for 1.5 + 0.9 s")


# --- Pack Frenzy -------------------------------------------------------------------------------

func test_pack_frenzy_is_a_capstone_that_needs_twelve_points() -> void:
	var p := _hunter()
	check_eq(p.talents.add_block_reason(PF_ID), "Needs 12 points in Packlord", "gated")
	var r := _to_capstone(p)
	check(r != null, "the script runs")
	check(_talent(T, "pack_frenzy").is_capstone(), "capstone")
	check_eq(_talent(T, "pack_frenzy").text_for_rank(1),
		"Every 30 sec your companion enters a frenzy for 10 sec: +50% damage and +30% attack speed.", "text")


func test_pack_frenzy_starts_at_five_seconds_then_every_thirty() -> void:
	var p := _hunter()
	var r := _to_capstone(p)
	var pet := _pet(p, &"wolf")
	var state := RunState.rng.state
	# The market: a script outside a wave never starts a frenzy.
	_run(p, 60.0)
	check_eq(r.frenzies, 0, "no frenzy outside a wave")
	check_eq(pet.frenzy_left, 0.0, "the companion is calm")
	check_eq(r.time_to_next(), INF, "nothing due")
	p.begin_wave()
	check_near(r.time_to_next(), 5.0, 0.0001, "the first one is due 5 s into the wave")
	_run(p, 4.9)
	check(not pet.is_frenzied() and pet.frenzy_left == 0.0, "calm at 4.9 s")
	_run(p, 0.2)
	check(pet.frenzy_left > 9.5 and pet.frenzy_left <= 10.0, "frenzied after 5 s (%.2f left)" % pet.frenzy_left)
	check_near(pet.frenzy_damage_pct, 50.0, 0.0001, "+50% damage")
	check_near(pet.frenzy_haste_pct, 30.0, 0.0001, "+30% attack speed")
	check(pet.model.is_frenzied(), "the companion glows")
	check(r.is_active(), "active")
	check_eq(r.frenzies, 1, "one frenzy")
	# It runs 10 s.
	_run(p, 9.8)
	check(pet.frenzy_left > 0.0, "still frenzied at 14.9 s (%.2f)" % pet.frenzy_left)
	_run(p, 0.3)
	check_eq(pet.frenzy_left, 0.0, "over after 10 s")
	check(not pet.model.is_frenzied() and not r.is_active(), "the glow ends")
	# The next one starts 30 s after the first (at 35 s), not 30 s after the end.
	_run(p, 19.7)   # t = 34.9
	check_eq(pet.frenzy_left, 0.0, "calm at 34.9 s")
	check_near(r.time_to_next(), 0.1, 0.02, "due in 0.1 s")
	_run(p, 0.2)
	check(pet.frenzy_left > 0.0, "the second frenzy at 35 s")
	check_eq(r.frenzies, 2, "two frenzies")
	_run(p, 30.0)
	check_eq(r.frenzies, 3, "and the third 30 s later")
	check_eq(RunState.rng.state, state, "no RNG")


func test_a_frenzied_companion_hits_harder_and_faster() -> void:
	var p := _hunter()
	var r := _to_capstone(p)
	var pet := _pet(p, &"wolf")
	_step_pet(pet, 0.3)
	var calm_interval := pet.attack_interval()
	var calm_hit := pet.hit_damage(100.0)
	p.begin_wave()
	_run(p, 5.2)
	check(r.is_active(), "frenzied")
	check_near(pet.hit_damage(100.0), calm_hit * 1.5, 0.001, "+50% damage")
	# Feral Tempo's 15% and the frenzy's 30% add up (both are attack speed).
	check_near(pet.attack_interval(), 1.2 / 1.45, 0.0001, "attack speed +15% +30%")
	check(pet.attack_interval() < calm_interval, "faster than calm")
	# Real bites during the frenzy.
	var e := _enemy(Vector3(1.5, 0, 0))
	_step_pet(pet, 0.6)
	check(e.fake_hits() >= 1, "a bite")
	check_near(e.fake_damage_log[0], _w(p) * 0.38 * 1.12 * 1.5, 0.001, "38% W x Keen Companion x frenzy")
	check_eq(r.describe().begins_with("Pack Frenzy: "), true, "describe while it lasts")


func test_hunt_signal_rides_the_frenzy() -> void:
	var p := _hunter()
	var r := _to_capstone(p)
	var slot := _learn(p, &"hunt_signal")
	var pet := _pet(p, &"wolf")
	p.begin_wave()
	_run(p, 5.2)
	check(r.is_active(), "frenzied")
	var e := _enemy(Vector3(0, 0, -7))
	check(p.abilities.try_cast(slot), "cast")
	_step_pet(pet, 1.0)
	check_near(e.fake_damage_log[0], _w(p) * 2.5 * 1.18 * 1.12 * 1.5, 0.001, "the blow gets the frenzy's +50% as well")


func test_nothing_while_the_hunter_is_down_and_the_clock_keeps_running() -> void:
	var p := _hunter()
	var r := _to_capstone(p)
	var pet := _pet(p, &"wolf")
	p.begin_wave()
	_run(p, 2.0)
	p.downed = true
	_run(p, 4.0)  # t = 6: the first one came due while down
	check_eq(r.frenzies, 0, "missed")
	check_eq(pet.frenzy_left, 0.0, "no frenzy for a downed Hunter")
	_run(p, 20.0)  # t = 26, revived
	p.downed = false
	_run(p, 8.0)   # t = 34
	check_eq(pet.frenzy_left, 0.0, "the clock did not restart")
	_run(p, 1.5)   # t = 35.5: the second one is on time
	check_eq(r.frenzies, 1, "the 35 s frenzy came")
	check(pet.frenzy_left > 0.0, "frenzied")


func test_the_frenzy_ends_with_the_wave_and_with_the_talent() -> void:
	var p := _hunter()
	var r := _to_capstone(p)
	var pet := _pet(p, &"wolf")
	p.begin_wave()
	_run(p, 6.0)
	check(pet.frenzy_left > 0.0, "frenzied")
	p.end_wave()
	check_eq(pet.frenzy_left, 0.0, "the wave ends: calm")
	check_eq(pet.frenzy_damage_pct, 0.0, "and the numbers are cleared")
	check_eq(r.time_to_next(), INF, "nothing due in the market")
	_run(p, 40.0)
	check_eq(pet.frenzy_left, 0.0, "the market never sees a frenzy")
	# A new wave starts the clock again.
	p.begin_wave()
	check_near(r.time_to_next(), 5.0, 0.0001, "5 s into the new wave")
	_run(p, 5.5)
	check(pet.frenzy_left > 0.0, "again")
	_reset(p)
	check(_frenzy(p) == null, "the script is gone after a reset")
	check_eq(pet.frenzy_left, 0.0, "teardown ends the frenzy")
	check_eq(pet.frenzy_haste_pct, 0.0, "and clears the hooks")


func test_every_companion_kind_can_go_into_a_frenzy() -> void:
	var kinds: Array[StringName] = [&"wolf", &"boar", &"owl"]
	for i in kinds.size():
		var p := _hunter(i, Vector3(i * 6.0, 0, 0))
		var r := _to_capstone(p)
		var pet := _pet(p, kinds[i])
		p.begin_wave()
		_run(p, 5.2)
		check(pet.frenzy_left > 0.0 and r.is_active(), "%s: frenzied" % kinds[i])
		check(pet.model.is_frenzied(), "%s: glows" % kinds[i])
		p.end_wave()
		check_eq(pet.frenzy_left, 0.0, "%s: calm after the wave" % kinds[i])


func test_two_packlords_have_their_own_frenzies() -> void:
	var a := _hunter(0, Vector3.ZERO)
	var b := _hunter(1, Vector3(5, 0, 0))
	var ra := _to_capstone(a)
	var pet_a := _pet(a, &"wolf")
	var pet_b := _pet(b, &"owl")
	check(_frenzy(b) == null, "the second Hunter has no capstone")
	a.begin_wave()
	b.begin_wave()
	_run(a, 5.2)
	check(pet_a.frenzy_left > 0.0, "the first Hunter's companion is frenzied")
	check_eq(pet_b.frenzy_left, 0.0, "the second one's is not")
	check_eq(ra.frenzies, 1, "one frenzy")


func test_a_hunter_without_a_companion_out_just_waits() -> void:
	var p := _hunter()
	var r := _to_capstone(p)
	p.begin_wave()
	check(HunterKit.companion(p) == null, "no companion summoned yet")
	_tick(p, 6.0)
	check_eq(r.frenzies, 0, "nothing to enrage")
	check(not r.is_active(), "not active")
