extends "res://tests/talents_rogue_base.gd"
## Rogue Combat (M5 Wave 2, talents_rogue.md §2, §4.1): every talent through player.talents.add
## -> PlayerBonuses on a real Rogue – Lightning Reflexes, Hack and Slash (stats), Combat Potency
## (on_hit Energy proc), Unfair Advantage (Dodge + on_dodge counter), Aggression (Physical
## damage), Ambidexterity (Haste while dual wielding), Restless Blades (the FoK kit's
## cooldown engine through AbilityRunner.reduce_cooldown), Blade Tactics (learned-ability
## mods), Adrenaline Rush (RogueCombatAdrenalineRush) – and the Combat bot's path.

const T := "combat"
const AR_ID := &"rogue_combat_adrenaline_rush"


## The 12 points that open the capstone without dual wield (talents_rogue.md 5.2).
func _to_capstone(p: Player) -> void:
	_add(p, T, "lightning_reflexes", 3)
	_add(p, T, "combat_potency", 3)
	_add(p, T, "unfair_advantage", 3)
	_add(p, T, "aggression", 3)
	_add(p, T, "adrenaline_rush")


func _rush(p: Player) -> RogueCombatAdrenalineRush:
	return p.bonuses.script_for(AR_ID) as RogueCombatAdrenalineRush


func _tick_bonuses(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p.bonuses.tick(DT)
		t += DT


# --- Tier 1-4 ----------------------------------------------------------------------------------

func test_lightning_reflexes_unfair_advantage_and_hack_and_slash_stats() -> void:
	var p := _rogue()
	var dodge := p.stats.get_raw(Stats.DODGE)
	var extra := p.stats.get_raw(Stats.EXTRA_ATTACK)
	_add(p, T, "lightning_reflexes", 3)
	check_near(p.stats.get_raw(Stats.DODGE), dodge + 6.0, 0.0001, "+2% dodge per rank")
	check_eq(_talent(&"rogue_combat_lightning_reflexes").text_for_rank(3),
			"Increases your chance to dodge attacks by 6%.", "rank text")
	_add(p, T, "unfair_advantage", 3)
	check_near(p.stats.get_raw(Stats.DODGE), dodge + 9.0, 0.0001, "Unfair Advantage +1% dodge per rank")
	_add(p, T, "aggression", 3)
	for n in range(1, 4):
		_add(p, T, "hack_and_slash")
		check_near(p.stats.get_raw(Stats.EXTRA_ATTACK), extra + 4.0 * n, 0.0001, "Hack and Slash +4 extra attack per rank")
	_reset(p)
	check_near(p.stats.get_raw(Stats.DODGE), dodge, 0.0001, "reset: dodge back")
	check_near(p.stats.get_raw(Stats.EXTRA_ATTACK), extra, 0.0001, "reset: extra attack back")


func test_combat_potency_gives_energy_on_weapon_hits() -> void:
	var p := _rogue()
	_add(p, T, "combat_potency", 3)
	var procs := _procs_of(p, &"rogue_combat_combat_potency")
	check_eq(procs.size(), 1, "one proc")
	check(procs[0].trigger == &"on_hit" and procs[0].effect == &"resource", "an on_hit resource proc")
	check_near(procs[0].chance, 24.0, 0.0001, "8% per rank")
	check_near(procs[0].num("value"), 2.0, 0.0001, "2 Energy (not scaled)")
	check_eq(_talent(&"rogue_combat_combat_potency").text_for_rank(3),
			"Your weapon attacks have a 24% chance to generate 2 Energy.", "rank text (_fixed)")
	_force_procs(p, &"rogue_combat_combat_potency")
	var e := Fakes.spawn_enemy(world, Vector3(0, 0, -1.2))
	_energy(p).set_value(50.0)
	WeaponRunner.apply_hit(p, e, 5.0, false, Vector3.ZERO)
	check_near(_energy(p).value, 52.0, 0.0001, "+2 Energy per attack")
	WeaponRunner.apply_hit(p, e, 5.0, false, Vector3.ZERO, 0.0, 0.5, null, false, false)
	check_near(_energy(p).value, 52.0, 0.0001, "the further hits of one attack roll nothing")


func test_unfair_advantage_counters_a_dodged_attacker() -> void:
	var p := _rogue()
	_add(p, T, "lightning_reflexes", 3)
	_add(p, T, "unfair_advantage", 3)
	var procs := _procs_of(p, &"rogue_combat_unfair_advantage")
	check(procs.size() == 1 and procs[0].trigger == &"on_dodge" and procs[0].effect == &"extra_attack", "an on_dodge counter")
	check_near(procs[0].chance, 75.0, 0.0001, "25% per rank")
	check_near(procs[0].icd, 0.5, 0.0001, "0.5 sec internal cooldown")
	_force_procs(p, &"rogue_combat_unfair_advantage")
	var e := Fakes.spawn_enemy(world, Vector3(0, 0, -1.0))
	EnemyGrid.mark_dirty()
	p._avoided(&"dodge", e)
	check_eq(e.fake_hits(), 1, "a dodge: one swing back at the attacker")
	check_eq(e.fake_attacker_log[0], p, "by the Rogue")
	p._avoided(&"dodge", e)
	check_eq(e.fake_hits(), 1, "not again within 0.5 sec")
	p.procs._physics_process(0.6)
	p._avoided(&"block", e)
	check_eq(e.fake_hits(), 1, "only dodges")
	p._avoided(&"dodge", e)
	check_eq(e.fake_hits(), 2, "the next dodge after the cooldown")


func test_aggression_is_physical_damage() -> void:
	var p := _rogue()
	_add(p, T, "combat_potency", 3)
	for n in range(1, 4):
		_add(p, T, "aggression")
		check_near(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0 + 0.03 * n, 0.0001, "+3%% Physical per rank (%d)" % n)
	check_near(p.outgoing_damage_mult(null, &"physical", &"ability"), 1.09, 0.0001, "every Physical source")
	check_eq(p.bonuses.damage_mult(null, &"nature", &"dot"), 1.0, "not the poison")


func test_ambidexterity_needs_two_weapons() -> void:
	var p := _rogue()
	check(p.main_hand != null and p.off_hand != null, "two daggers")
	var haste := p.stats.get_raw(Stats.HASTE)
	_add(p, T, "lightning_reflexes", 3)
	_add(p, T, "combat_potency", 3)
	_add(p, T, "ambidexterity", 2)
	check_near(p.stats.get_raw(Stats.HASTE), haste + 10.0, 0.0001, "+5% Haste per rank while dual wielding")
	check(p.equipment.unequip(Items.EquipSlot.OFF_HAND), "off hand away")
	check(p.off_hand == null, "one dagger")
	check_near(p.stats.get_raw(Stats.HASTE), haste, 0.0001, "no Haste with one weapon")
	check(TalentBot.is_deferred(p, _talent(&"rogue_combat_ambidexterity")), "a one-weapon bot defers it")


func test_blade_tactics_changes_blade_flurry_and_killing_spree() -> void:
	var p := _rogue()
	var flurry := Db.get_ability(&"blade_flurry")
	var spree := Db.get_ability(&"killing_spree")
	var base_flurry := p.abilities.params_for(flurry)
	var base_spree := p.abilities.params_for(spree)
	_add(p, T, "lightning_reflexes", 3)
	_add(p, T, "combat_potency", 3)
	_add(p, T, "aggression", 3)
	_add(p, T, "blade_tactics", 3)
	check(not p.abilities.knows(&"blade_flurry"), "not learned: no error, the mods wait")
	var f := p.abilities.params_for(flurry)
	var s := p.abilities.params_for(spree)
	check_near(float(f["power"]), float(base_flurry["power"]) * 1.18, 0.0001, "Blade Flurry +18% power")
	check_near(float(f["cooldown"]), float(base_flurry["cooldown"]) * 0.82, 0.0001, "Blade Flurry -18% cooldown")
	check_near(float(s["power"]), float(base_spree["power"]) * 1.18, 0.0001, "Killing Spree +18% power")
	check_near(float(s["cooldown"]), float(base_spree["cooldown"]) * 0.82, 0.0001, "Killing Spree -18% cooldown")
	check_near(float(p.abilities.params_for(_vanish(p))["cooldown"]), 15.0, 0.0001, "Vanish untouched")


# --- Restless Blades (modifier) ----------------------------------------------------------------

func test_restless_blades_shortens_the_other_rogue_cooldowns() -> void:
	var p := _rogue()
	_add(p, T, "lightning_reflexes", 3)
	_add(p, T, "combat_potency", 3)
	_add(p, T, "restless_blades")
	check_near(float(p.abilities.params_for(_fan(p))["cdr_per_combo"]), 0.2, 0.0001, "0.2 sec per Combo Point")
	var runner := p.abilities
	var vanish := _vanish(p)
	var sprint := Db.get_ability(&"sprint")
	check(runner.learn(sprint) >= 0, "Sprint learned (a general ability)")
	runner.set_cooldown(vanish, 10.0)
	runner.set_cooldown(sprint, 5.0)
	_combo(p).set_value(0.0)
	_throw_fan(p)
	check_near(runner.cooldown_left(vanish), 10.0, 0.0001, "a fan at 0 points changes nothing")
	_combo(p).set_value(5.0)
	_throw_fan(p)
	check_near(runner.cooldown_left(vanish), 9.0, 0.0001, "5 points: Vanish 1 sec sooner")
	check_near(runner.cooldown_left(sprint), 5.0, 0.0001, "Sprint (general) untouched")
	_combo(p).set_value(3.0)
	_throw_fan(p)
	check_near(runner.cooldown_left(vanish), 8.4, 0.0001, "3 points: 0.6 sec")


func test_restless_blades_returns_one_charge_at_most() -> void:
	var p := _rogue()
	_add(p, T, "lightning_reflexes", 3)
	_add(p, T, "combat_potency", 3)
	_add(p, T, "restless_blades")
	var runner := p.abilities
	var step := Db.get_ability(&"shadowstep")
	check(runner.learn(step) >= 0, "Shadowstep learned")
	runner.ranks[&"shadowstep"] = 5
	runner.specs[&"shadowstep"] = 1
	runner.invalidate_params()
	check_eq(runner.charges_max(step), 2, "Twin Shadows: two charges")
	runner.spend_charge(step)
	runner.spend_charge(step)
	check_eq(runner.charges_available(step), 0, "both spent")
	var full := runner.cooldown_of(step)
	runner.reduce_cooldown(step, full - 0.5)
	check_near(runner.cooldown_left(step), 0.5, 0.0001, "0.5 sec left on the recharge")
	_combo(p).set_value(5.0)
	_throw_fan(p)
	check_eq(runner.charges_available(step), 1, "one charge back, never both")
	check_near(runner.cooldown_left(step), full - 0.5, 0.0001, "the next recharge runs with the leftover")
	check_eq(RogueUtil.reduce_other_cooldowns(p, _fan(p), 0.1), 1, "the helper counts the running recharges")
	check_eq(RogueUtil.reduce_other_cooldowns(p, step, 0.1), 0, "never the excepted ability")


func test_restless_blades_applies_to_free_fans() -> void:
	var p := _rogue()
	_add(p, T, "lightning_reflexes", 3)
	_add(p, T, "combat_potency", 3)
	_add(p, T, "restless_blades")
	p.abilities.set_cooldown(_vanish(p), 10.0)
	_combo(p).set_value(5.0)
	_energy(p).set_value(0.0)
	check(RogueFanOfKnives.throw_free(p), "a free fan")
	check_near(p.abilities.cooldown_left(_vanish(p)), 9.0, 0.0001, "a free fan applies it too")
	check_eq(_energy(p).value, 0.0, "no Energy spent")


# --- Adrenaline Rush (capstone) ----------------------------------------------------------------

func test_adrenaline_rush_in_a_pack_raises_energy_and_ally_haste() -> void:
	var p := _rogue(0)
	var near_ally := _rogue(1, Vector3(6, 0, 0))
	var far_ally := _rogue(2, Vector3(0, 0, 9))
	var ally_haste := near_ally.stats.get_raw(Stats.HASTE)
	_to_capstone(p)
	var rush := _rush(p)
	check(rush != null, "the capstone script runs")
	_tick_bonuses(p, 0.5)
	check(not rush.active, "no pack: off")
	check(not p.stats.has_source(RogueCombatAdrenalineRush.SELF_KEY), "no source")
	var enemies := _surround(3, 2.0)
	_tick_bonuses(p, 0.25)
	check(rush.active, "3 enemies within 5 m: on within 0.25 sec")
	check_near(p.stats.get_raw(Stats.RESOURCE_REGEN), 50.0, 0.0001, "+50% Energy generation")
	var key := StringName("rogue_combat_adrenaline_rush:0")
	check(near_ally.stats.has_source(key), "the ally at 6 m")
	check_near(near_ally.stats.get_raw(Stats.HASTE), ally_haste + 10.0, 0.0001, "+10% Haste")
	check(not far_ally.stats.has_source(key), "not the ally at 9 m")
	check_eq(rush.buffed_allies(), [near_ally] as Array[Player], "one buffed ally")
	check(p.get_node_or_null("AdrenalineRushRing") != null, "the energy ring under the hero")
	_energy(p).set_value(0.0)
	for i in 60:
		p.abilities._physics_process(DT)
	check_near(_energy(p).value, 22.5, 0.05, "15 Energy / s x 1.5")
	near_ally.global_position = Vector3(20, 0, 0)
	_tick_bonuses(p, 0.3)
	check(not near_ally.stats.has_source(key), "an ally that walks away loses it")
	for e in enemies:
		e.free()
	EnemyGrid.mark_dirty()
	_tick_bonuses(p, 0.5)
	check(rush.active, "it lingers a moment")
	_tick_bonuses(p, 0.75)
	check(not rush.active, "off within 1.25 sec")
	check(not p.stats.has_source(RogueCombatAdrenalineRush.SELF_KEY), "source removed")
	check_near(p.stats.get_raw(Stats.RESOURCE_REGEN), 0.0, 0.0001, "no Resource Regen left")


func test_adrenaline_rush_ends_when_downed_at_wave_end_and_on_teardown() -> void:
	var p := _rogue(0)
	var ally := _rogue(1, Vector3(3, 0, 0))
	_to_capstone(p)
	var key := StringName("rogue_combat_adrenaline_rush:0")
	_surround(4, 2.0)
	_tick_bonuses(p, 0.1)
	var rush := _rush(p)
	check(rush.active and ally.stats.has_source(key), "on")
	p.take_damage(99999.0)
	check(p.downed, "downed")
	_tick_bonuses(p, DT)
	check(not rush.active, "off while downed")
	check(not p.stats.has_source(RogueCombatAdrenalineRush.SELF_KEY) and not ally.stats.has_source(key), "no source on anyone")
	p.revive(1.0)
	_tick_bonuses(p, 0.3)
	check(rush.active, "back after the revive")
	p.end_wave()
	check(not rush.active and not ally.stats.has_source(key) and not p.stats.has_source(RogueCombatAdrenalineRush.SELF_KEY),
			"end_wave: off, nothing left (market)")
	p.begin_wave()
	_tick_bonuses(p, 0.3)
	check(rush.active, "on again in the next wave")
	_reset(p)
	check(_rush(p) == null, "reset: the script is gone")
	check(not ally.stats.has_source(key) and not p.stats.has_source(RogueCombatAdrenalineRush.SELF_KEY), "teardown: no source left")


func test_two_combat_rogues_buff_an_ally_twice() -> void:
	var a := _rogue(0)
	var b := _rogue(1, Vector3(1, 0, 0))
	var ally := _rogue(2, Vector3(-2, 0, 0))
	var haste := ally.stats.get_raw(Stats.HASTE)
	var a_haste := a.stats.get_raw(Stats.HASTE)
	_to_capstone(a)
	_to_capstone(b)
	_surround(4, 2.0)
	_tick_bonuses(a, 0.1)
	_tick_bonuses(b, 0.1)
	check_near(ally.stats.get_raw(Stats.HASTE), haste + 20.0, 0.0001, "two rushes, two Haste sources")
	check_near(a.stats.get_raw(Stats.HASTE), a_haste + 10.0, 0.0001, "each Rogue gets the other's")
	check_near(a.stats.get_raw(Stats.RESOURCE_REGEN), 50.0, 0.0001, "its own Energy bonus once")


# --- Bot ---------------------------------------------------------------------------------------

func test_combat_bot_path_reaches_the_capstone_at_13() -> void:
	var p := _rogue()
	var path: Array[StringName] = []
	for i in 30:
		var t := TalentBot.next_talent(p, 1)
		if t == null or not p.talents.add(t.id):
			break
		path.append(t.id)
	check_eq(path.size(), 22, "the whole tree")
	check_eq(path[6], &"rogue_combat_restless_blades", "the modifier is point 7")
	check_eq(path[12], AR_ID, "the capstone is point 13")
	check_eq(path.slice(0, 6), [&"rogue_combat_lightning_reflexes", &"rogue_combat_lightning_reflexes",
			&"rogue_combat_lightning_reflexes", &"rogue_combat_combat_potency", &"rogue_combat_combat_potency",
			&"rogue_combat_combat_potency"] as Array[StringName], "tier 1 first")
	check_eq(path.slice(13, 16), [&"rogue_combat_aggression", &"rogue_combat_ambidexterity",
			&"rogue_combat_ambidexterity"] as Array[StringName], "then the rest of tier 2 and Ambidexterity (two daggers)")
