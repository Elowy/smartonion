extends "res://tests/talents_rogue_base.gd"
## Rogue Subtlety (M5 Wave 2, talents_rogue.md §3, §4.2, §4.3): every talent through
## player.talents.add -> PlayerBonuses on a real Rogue – Premeditation, Master of Subtlety,
## Shadow Focus (on_cast Vanish procs + the Vanish params), Enveloping Shadows (Avoidance),
## Deadened Nerves (damage taken), Unseen Blades (the Vanish kit's free fan), Find Weakness
## (on_crit forced crit), Sleight of Hand (learned-ability mods), Shadow Dance
## (RogueSubtletyShadowDance and the kit crit hooks) – plus the Vanish bot rule and the
## Subtlety bot's path.

const T := "subtlety"
const SD_ID := &"rogue_subtlety_shadow_dance"


## The 12 points that open the capstone (talents_rogue.md 5.4 without the modifier).
func _to_capstone(p: Player) -> void:
	_add(p, T, "premeditation", 3)
	_add(p, T, "enveloping_shadows", 3)
	_add(p, T, "master_of_subtlety", 3)
	_add(p, T, "shadow_focus", 3)
	_add(p, T, "shadow_dance")


func _dance(p: Player) -> RogueSubtletyShadowDance:
	return p.bonuses.script_for(SD_ID) as RogueSubtletyShadowDance


## Casts Vanish (its cooldown cleared first).
func _cast_vanish(p: Player) -> void:
	p.abilities.set_cooldown(_vanish(p), 0.0)
	check(p.abilities.try_cast(1), "Vanish cast")


func _tick_bonuses(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p.bonuses.tick(DT)
		t += DT


# --- Tier 1-4 ----------------------------------------------------------------------------------

func test_premeditation_primes_combo_points_and_crits() -> void:
	var p := _rogue()
	for n in range(1, 4):
		_add(p, T, "premeditation")
		var params := p.abilities.params_for(_vanish(p))
		check_eq(int(params["forced_crits"]), 1 + n, "Vanish's guaranteed crits 1 + %d" % n)
		check(float(params["auto_offense"]) > 0.0, "bots vanish offensively")
		_combo(p).set_value(0.0)
		p.forced_crits = 0
		_cast_vanish(p)
		check_eq(_combo(p).value, float(n), "+%d Combo Point(s) (pips: exact)" % n)
		check_eq(p.forced_crits, 1 + n, "%d guaranteed crits" % (1 + n))
	check_eq(_talent(&"rogue_subtlety_premeditation").text_for_rank(2),
			"Vanish also grants 2 Combo Point(s), and 2 more of your next weapon hits are guaranteed critical strikes.", "rank text")
	_reset(p)
	var params := p.abilities.params_for(_vanish(p))
	check(int(params["forced_crits"]) == 1 and float(params["auto_offense"]) == 0.0, "reset: Vanish neutral again")
	_combo(p).set_value(0.0)
	_cast_vanish(p)
	check_eq(_combo(p).value, 0.0, "no Combo Point without the talent")


func test_enveloping_shadows_adds_avoidance() -> void:
	var p := _rogue()
	var avoid := p.stats.get_raw(Stats.AVOIDANCE)
	_add(p, T, "enveloping_shadows", 3)
	check_near(p.stats.get_raw(Stats.AVOIDANCE), avoid + 9.0, 0.0001, "+3% Avoidance per rank")
	_remove(p, T, "enveloping_shadows", 3)
	check_near(p.stats.get_raw(Stats.AVOIDANCE), avoid, 0.0001, "taken back")


func test_master_of_subtlety_buffs_damage_for_six_seconds() -> void:
	var p := _rogue()
	var dmg := p.stats.get_raw(Stats.DAMAGE_PCT)
	_add(p, T, "enveloping_shadows", 3)
	check_eq(p.talents.add_block_reason(&"rogue_subtlety_master_of_subtlety"), "Requires Premeditation", "prerequisite")
	_add(p, T, "premeditation", 3)
	_add(p, T, "master_of_subtlety", 3)
	check_eq(_talent(&"rogue_subtlety_master_of_subtlety").text_for_rank(3),
			"For 6 sec after you Vanish, you deal 12% more damage.", "rank text (_fixed duration)")
	_cast_vanish(p)
	check_near(p.stats.get_raw(Stats.DAMAGE_PCT), dmg + 12.0, 0.0001, "+4% damage per rank")
	p.procs._physics_process(3.0)
	_cast_vanish(p)
	check_near(p.stats.get_raw(Stats.DAMAGE_PCT), dmg + 12.0, 0.0001, "a recast refreshes, never stacks")
	p.procs._physics_process(5.9)
	check_near(p.stats.get_raw(Stats.DAMAGE_PCT), dmg + 12.0, 0.0001, "6 sec from the last Vanish")
	p.procs._physics_process(0.2)
	check_near(p.stats.get_raw(Stats.DAMAGE_PCT), dmg, 0.0001, "then gone")


func test_shadow_focus_restores_energy_on_vanish() -> void:
	var p := _rogue()
	_add(p, T, "premeditation", 3)
	for n in range(1, 4):
		_add(p, T, "shadow_focus")
		_energy(p).set_value(0.0)
		_cast_vanish(p)
		check_near(_energy(p).value, 10.0 * n, 0.0001, "+10 Energy per rank (%d)" % n)
	check(float(p.abilities.params_for(_vanish(p))["auto_offense"]) > 0.0, "bots vanish offensively")


func test_deadened_nerves_reduces_damage_taken() -> void:
	var p := _rogue()
	_add(p, T, "premeditation", 3)
	_add(p, T, "enveloping_shadows", 3)
	for n in range(1, 3):
		_add(p, T, "deadened_nerves")
		check_near(p.bonuses.damage_taken_mult(&"melee", null), 1.0 - 0.04 * n, 0.0001, "-4%% per rank (%d)" % n)
	check_near(p.bonuses.damage_taken_mult(&"projectile", null), 0.92, 0.0001, "every kind")
	_reset(p)
	check_eq(p.bonuses.damage_taken_mult(&"melee", null), 1.0, "reset")


func test_find_weakness_banks_a_guaranteed_crit() -> void:
	var p := _rogue()
	_add(p, T, "premeditation", 3)
	_add(p, T, "enveloping_shadows", 3)
	_add(p, T, "deadened_nerves", 2)
	_add(p, T, "unseen_blades")
	_add(p, T, "find_weakness", 3)
	var procs := _procs_of(p, &"rogue_subtlety_find_weakness")
	check(procs.size() == 1 and procs[0].trigger == &"on_crit" and procs[0].effect == &"forced_crit", "an on_crit forced-crit proc")
	check_near(procs[0].chance, 24.0, 0.0001, "8% per rank")
	check_near(procs[0].icd, 0.5, 0.0001, "0.5 sec internal cooldown")
	_force_procs(p, &"rogue_subtlety_find_weakness")
	var e := Fakes.spawn_enemy(world, Vector3(0, 0, -1.2))
	WeaponRunner.apply_hit(p, e, 5.0, false, Vector3.ZERO)
	check_eq(p.forced_crits, 0, "a normal hit banks nothing")
	WeaponRunner.apply_hit(p, e, 12.0, true, Vector3.ZERO)
	check_eq(p.forced_crits, 1, "a crit banks one")
	WeaponRunner.apply_hit(p, e, 12.0, true, Vector3.ZERO)
	check_eq(p.forced_crits, 1, "not again within 0.5 sec")
	EnemyGrid.mark_dirty()
	p.runner_for(p.main_hand).attack(e)
	check(e.fake_crit_log[-1], "the next dagger hit is the guaranteed crit")


func test_sleight_of_hand_changes_shadowstep_and_cheat_death() -> void:
	var p := _rogue()
	var step := Db.get_ability(&"shadowstep")
	var cheat := Db.get_ability(&"cheat_death")
	var base_step := p.abilities.params_for(step)
	var base_cheat := p.abilities.params_for(cheat)
	_add(p, T, "premeditation", 3)
	_add(p, T, "enveloping_shadows", 3)
	_add(p, T, "deadened_nerves", 2)
	_add(p, T, "unseen_blades")
	_add(p, T, "sleight_of_hand", 3)
	var s := p.abilities.params_for(step)
	var c := p.abilities.params_for(cheat)
	check_near(float(s["power"]), float(base_step["power"]) * 1.18, 0.0001, "Shadowstep +18% power")
	check_near(float(s["cooldown"]), float(base_step["cooldown"]) * 0.82, 0.0001, "Shadowstep -18% cooldown")
	check_near(float(c["power"]), float(base_cheat["power"]) * 1.18, 0.0001, "Cheat Death +18% power")
	check_near(float(c["cooldown"]), float(base_cheat["cooldown"]) * 0.82, 0.0001, "Cheat Death -18% cooldown")


# --- Unseen Blades (modifier) ------------------------------------------------------------------

func _to_unseen(p: Player) -> void:
	_add(p, T, "premeditation", 3)
	_add(p, T, "enveloping_shadows", 3)
	_add(p, T, "unseen_blades")


func test_unseen_blades_throws_a_free_fan_when_vanish_ends() -> void:
	var p := _rogue()
	_to_unseen(p)
	check(_talent(&"rogue_subtlety_unseen_blades").ability == &"vanish", "modifier on Vanish")
	check_eq(float(p.abilities.params_for(_vanish(p))["end_fan"]), 1.0, "the Vanish carries end_fan")
	var casts: Array[StringName] = []
	p.abilities.ability_cast.connect(func(_i: int, a: AbilityData) -> void: casts.append(a.id))
	_clear_knives()
	_cast_vanish(p)
	check_eq(_combo(p).value, 3.0, "Premeditation primed 3 Combo Points")
	check_eq(_energy(p).value, 100.0, "full Energy")
	_step(p, 1.9)
	check(_knives(p).is_empty(), "nothing while hidden")
	_step(p, 0.2)
	var knives := _knives(p)
	check_eq(knives.size(), 10, "Vanish ran out: a fan from the shadows")
	var base := CombatMath.weapon_hit_damage(p.main_hand, p.stats) * 1.1
	for k in knives:
		check_near(k.damage, base * 1.6, 0.0001, "the 3 Combo Points are spent on it")
		check_eq(k.color, RogueVfx.SHADOW_COLOR, "shadow-purple knives")
	check_eq(_combo(p).value, 0.0, "Combo Points spent")
	check_eq(_energy(p).value, 100.0, "no Energy spent")
	check_eq(casts, [&"vanish"] as Array[StringName], "no ability_cast for the free fan (no on-cast procs)")
	check_eq(_vanish_effect(p).end_fans, 1, "one free fan")


func test_unseen_blades_needs_the_natural_end() -> void:
	var p := _rogue()
	_to_unseen(p)
	var effect := _vanish_effect(p)
	_clear_knives()
	_cast_vanish(p)
	p.take_damage(99999.0)
	check(p.downed, "downed while hidden")
	p.revive(1.0)
	_step(p, 2.5)
	check(_knives(p).is_empty(), "going down: no fan")
	_cast_vanish(p)
	p.end_wave()
	_step(p, 2.5)
	check(_knives(p).is_empty(), "the wave ended: no fan")
	p.begin_wave()
	_cast_vanish(p)
	_step(p, 1.0)
	_cast_vanish(p)
	check(_knives(p).is_empty(), "a recast ends the first Vanish without a fan")
	_step(p, 2.1)
	check_eq(_knives(p).size(), 10, "only the second Vanish fans")
	check_eq(effect.end_fans, 1, "one fan in all")


func test_no_free_fan_without_unseen_blades() -> void:
	var p := _rogue()
	_clear_knives()
	_cast_vanish(p)
	_step(p, 2.5)
	check(_knives(p).is_empty(), "plain Vanish")
	check_eq(_vanish_effect(p).end_fans, 0, "no fan")


# --- Shadow Dance (capstone) -------------------------------------------------------------------

func test_shadow_dance_makes_every_weapon_hit_crit_for_five_seconds() -> void:
	var p := _rogue()
	_to_capstone(p)
	var dance := _dance(p)
	check(dance != null, "the capstone script runs")
	check(not p.bonuses.crit_forced(null), "nothing before Vanish")
	_cast_vanish(p)
	check(dance.is_dancing(), "Vanish opens the window")
	check(p.bonuses.crit_forced(null) and p.bonuses.crit_forced(world), "any target, null included")
	check(p.get_node_or_null("ShadowDanceGlow") != null, "the purple glow under the hero")
	var e := Fakes.spawn_enemy(world, Vector3(0, 0, -1.2))
	EnemyGrid.mark_dirty()
	var runner := p.runner_for(p.main_hand)
	for i in 6:
		runner.attack(e)
	check_eq(p.forced_crits, 0, "Premeditation's banked crits are used first")
	for c in e.fake_crit_log:
		check(c, "every dagger hit crits")
	var state := RunState.rng.state
	var knives := _throw_fan(p)
	check_eq(RunState.rng.state, state, "the knives ask the script, no roll")
	for k in knives:
		check(k.is_crit, "every knife crits")
	_clear_knives()
	check(RogueShurikenToss.throw_volley(p, Vector3.FORWARD, p.abilities.params_for(Db.get_ability(&"shuriken_toss")), e),
			"a shuriken volley")
	for k in _knives(p):
		check(k.is_crit, "every shuriken crits")
	var before := e.fake_hits()
	RogueShadowstep._ambush(p, e, 1.0)
	check(e.fake_hits() == before + 1 and e.fake_crit_log[-1], "the Ambush strike crits")
	_tick_bonuses(p, 4.9)
	check(dance.is_dancing(), "still dancing at 4.9 sec")
	_tick_bonuses(p, 0.2)
	check(not dance.is_dancing() and not p.bonuses.crit_forced(null), "over after 5 sec")
	runner.attack(e)
	check(not e.fake_crit_log[-1], "dagger hits roll again (no crit chance)")


func test_shadow_dance_once_per_twelve_seconds_and_only_real_vanishes() -> void:
	var p := _rogue()
	_to_capstone(p)
	var dance := _dance(p)
	RogueVanish.shroud(p, 3.0)
	check(not dance.is_dancing(), "a shroud (Shadow Escape, Untouchable) is no Vanish")
	p.bonuses.on_cast(0, _fan(p))
	check(not dance.is_dancing(), "other casts do nothing")
	_cast_vanish(p)
	check_eq(dance.dances, 1, "one window")
	_tick_bonuses(p, 6.0)
	check(not dance.is_dancing(), "closed")
	_cast_vanish(p)
	check(not dance.is_dancing() and dance.dances == 1, "a Vanish within 12 sec opens nothing")
	check(dance.describe().begins_with("Shadow Dance: ready in"), "describe: the cooldown")
	_tick_bonuses(p, 6.1)
	check_eq(dance.ready_in(), 0.0, "ready after 12 sec")
	_cast_vanish(p)
	check(dance.is_dancing() and dance.dances == 2, "the next window")
	p.begin_wave()
	check(not dance.is_dancing() and dance.ready_in() == 0.0, "a new wave: closed and ready")


func test_shadow_dance_gives_nearby_allies_crit_for_the_window() -> void:
	var p := _rogue(0)
	var near := _rogue(1, Vector3(6, 0, 0))
	var far := _rogue(2, Vector3(0, 0, 9))
	var crit := near.stats.get_raw(Stats.CRIT)
	_to_capstone(p)
	var dance := _dance(p)
	var key := StringName("rogue_subtlety_shadow_dance:0")
	_cast_vanish(p)
	check_near(near.stats.get_raw(Stats.CRIT), crit + 10.0, 0.0001, "+10% crit within 8 m")
	check(not far.stats.has_source(key), "not at 9 m")
	check_eq(dance.buffed_allies(), [near] as Array[Player], "one ally")
	_tick_bonuses(p, 5.1)
	check(not near.stats.has_source(key), "removed with the window")
	_tick_bonuses(p, 7.0)
	_cast_vanish(p)
	check(near.stats.has_source(key) and dance.is_dancing(), "the next window")
	p.take_damage(99999.0)
	_tick_bonuses(p, DT)
	check(not dance.is_dancing() and not near.stats.has_source(key), "going down ends it")
	p.revive(1.0)
	_tick_bonuses(p, 12.1)
	_cast_vanish(p)
	check(dance.is_dancing(), "dancing again")
	p.end_wave()
	check(not dance.is_dancing() and not near.stats.has_source(key), "end_wave ends it")
	p.begin_wave()
	_cast_vanish(p)
	check(dance.is_dancing() and near.stats.has_source(key), "and a new wave may start one at once")
	_reset(p)
	check(_dance(p) == null and not near.stats.has_source(key), "teardown: nothing left")
	check(not p.bonuses.crit_forced(null), "no forced crits")


# --- Vanish bot rule ---------------------------------------------------------------------------

func test_vanish_bot_rule_offense_with_the_talents() -> void:
	var p := _rogue()
	var vanish := _vanish(p)
	var effect := _vanish_effect(p)
	_surround(3, 2.5)
	p.hp = p.max_hp() * 0.8
	_energy(p).set_value(60.0)
	check(not effect.wants_auto_cast(p.abilities.build_context(vanish)), "without the param: only the low-HP rule")
	_add(p, T, "premeditation")
	var ctx := p.abilities.build_context(vanish)
	check(ctx.num("auto_offense") > 0.0, "Premeditation adds auto_offense")
	check(effect.wants_auto_cast(ctx), "healthy, in a pack, with Energy: vanish")
	_energy(p).set_value(40.0)
	check(not effect.wants_auto_cast(p.abilities.build_context(vanish)), "not without Energy for the fans")
	_energy(p).set_value(60.0)
	p.hp = p.max_hp() * 0.45
	check(not effect.wants_auto_cast(p.abilities.build_context(vanish)), "45% HP: neither rule")
	p.hp = p.max_hp() * 0.3
	check(effect.wants_auto_cast(p.abilities.build_context(vanish)), "the low-HP rule still works")
	p.hp = p.max_hp() * 0.8
	_clear_enemies()
	_surround(2, 2.5)
	check(not effect.wants_auto_cast(p.abilities.build_context(vanish)), "two enemies are no pack")
	_surround(1, 3.5)
	var friend := _rogue(1, Vector3(1, 0, 0))
	friend.take_damage(99999.0)
	check(friend.downed and p.is_reviving(), "reviving a teammate")
	check(not effect.wants_auto_cast(p.abilities.build_context(vanish)), "never while reviving")


# --- Bot ---------------------------------------------------------------------------------------

func test_subtlety_bot_path_reaches_the_capstone_at_13() -> void:
	var p := _rogue()
	var path: Array[StringName] = []
	for i in 30:
		var t := TalentBot.next_talent(p, 2)
		if t == null or not p.talents.add(t.id):
			break
		path.append(t.id)
	check_eq(path.size(), 22, "the whole tree")
	check_eq(path[0], &"rogue_subtlety_premeditation", "Premeditation first (offensive Vanish from point 1)")
	check_eq(path[6], &"rogue_subtlety_unseen_blades", "the modifier is point 7")
	check_eq(path[12], SD_ID, "the capstone is point 13")
	check_eq(path[13], &"rogue_subtlety_shadow_focus", "then Shadow Focus 3")
