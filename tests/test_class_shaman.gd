extends "res://tests/shaman_base.gd"
## Shaman class (M8, design_shaman.md §1): the class data, Surge (+5 per weapon hit and per cast, slow decay, the
## cost of Forking Bolt), the Mastery Storm Echo (chance maths, one RNG draw per eligible hit, 50% echo without
## target bonuses, no echo of echoes, ineligible sources), the Elemental Surge hub, the reviver hooks of the Player
## and determinism.


# --- Data ---------------------------------------------------------------------------------------

func test_the_class_data_follows_the_design() -> void:
	var c := Db.get_class_data(&"shaman")
	check(c != null, "the class is loaded")
	if c == null:
		return
	check_eq(c.display_name, "Shaman", "name")
	check_eq(c.armor_type, ClassData.ArmorType.MAIL, "Mail")
	check_eq(c.primary_stat, &"intellect", "Intellect")
	check_eq(c.base_stats.get(&"armor", 0.0), 2.0, "+2 Armor")
	check_eq(c.base_stats.get(&"spirit", 0.0), 3.0, "+3 Spirit")
	check_eq(c.base_stats.get(&"speed", 0.0), -5.0, "-5% Speed")
	check_eq(c.base_stats.size(), 3, "nothing else")
	check_eq(c.main_hand.id, &"mace", "starts with a Mace")
	check_eq(c.off_hand.id, &"shield", "and a Shield")
	var proficiencies: Array[StringName] = [&"mace", &"axe", &"dagger", &"staff", &"fist_weapon", &"shield", &"two_hand_mace"]
	check_eq(c.proficiencies.size(), proficiencies.size(), "seven proficiencies")
	for t in proficiencies:
		check(t in c.proficiencies, "proficient with %s" % t)
	check(not c.can_dual_wield(), "no Dual Wield proficiency (the Warspirit talent grants it)")
	check_eq(c.resource_type, &"surge", "resource type")
	check_eq(c.resources.size(), 1, "one resource")
	check_eq(c.resources[0].id, &"surge", "Surge")
	check_eq(c.abilities.size(), 2, "two core abilities")
	check_eq(c.abilities[0].id, &"forking_bolt", "RT")
	check_eq(c.abilities[1].id, &"totem_rite", "LT")
	check(c.mastery == load("res://scenes/abilities/shaman/shaman_mastery.gd"), "Mastery script")
	check_eq(c.headgear, &"tribal_mask", "headgear")
	check(c.big_shoulders, "big shoulders")
	check(c.onion_color.is_equal_approx(Color(0.92, 0.88, 0.96, 1.0)), "garlic white-lilac")
	check(c.accent_color.is_equal_approx(Color(0.2, 0.72, 0.68, 1.0)), "teal accent")
	check(c.mastery_text.begins_with("Storm Echo:"), "the Mastery text names Storm Echo")
	check(Db.class_ids.find(&"shaman") > Db.class_ids.find(&"warlock"), "the class comes after the Warlock")
	check(c.companion_choices.is_empty(), "no companion row")


func test_a_proficiency_without_a_weapon_in_the_game_is_harmless() -> void:
	var c := Db.get_class_data(&"shaman")
	var fist := WeaponData.new()
	fist.weapon_type = &"fist_weapon"
	fist.id = &"zz_fist"
	check(c.can_use(fist), "a Fist Weapon would be usable")
	var odd := WeaponData.new()
	odd.weapon_type = &"zz_unknown"
	check(not c.can_use(odd), "an unknown type is not")
	var p := _shaman()
	check_eq(p.main_hand.id, &"mace", "the starting Mace is in the main hand")
	check_eq(p.off_hand.id, &"shield", "the Shield in the off hand")
	var base := p.stats.get_source(&"class")
	check_eq(base.get(Stats.ARMOR, 0.0), 2.0, "class armour")
	check_eq(base.get(Stats.SPIRIT, 0.0), 3.0, "class spirit")
	check_eq(base.get(Stats.SPEED, 0.0), -5.0, "class speed")


func test_the_surge_resource_data() -> void:
	var r := Db.get_class_data(&"shaman").resources[0]
	check_eq(r.display, ResourceData.Display.BAR, "a bar")
	check_eq(r.max_value, 100.0, "0..100")
	check_eq(r.start_value, 0.0, "starts empty")
	check_eq(r.gain_on_hit, 5.0, "+5 per weapon hit")
	check_eq(r.decay_per_second, 2.0, "slow decay")
	check_eq(r.decay_delay, 3.0, "after 3 s")
	check_eq(r.regen_per_second, 0.0, "no regeneration")
	check_eq(r.gain_per_hits, 0, "no per-hit-count rule")
	check(r.color.is_equal_approx(Color(0.35, 0.85, 1.0, 1.0)), "the class colour")
	check_eq(UiTheme.resource_name(&"surge"), "Surge", "the UI name is the capitalised id")


func test_eight_abilities_two_core_and_six_learned() -> void:
	var all: Array[StringName] = []
	all.append_array(CORE)
	all.append_array(LEARNED)
	check_eq(all.size(), 8, "eight")
	for id in all:
		var a := Db.get_ability(id)
		check(a != null, "%s exists" % id)
		if a == null:
			continue
		check_eq(a.class_id, &"shaman", "%s belongs to the class" % id)
		check(a.effect != null and a.effect.new() is AbilityEffect, "%s has an effect script" % id)
		check(not a.rank3.is_empty() and a.rank3_text != "", "%s has Rank III" % id)
		check_eq(a.specs.size(), 2, "%s has two Rank V specs" % id)
		check(GameIcons.for_ability(a) != null, "%s has its picture" % id)
		check(a.card_weight > 0.0, "%s can be offered" % id)
	for id in CORE:
		check_eq(Db.get_ability(id).kind, AbilityData.Kind.CORE, "%s is core" % id)
	var kinds := {
		&"thunderbolt": AbilityData.Kind.AUTO, &"rumbling_earth": AbilityData.Kind.ACTIVE,
		&"magma_lash": AbilityData.Kind.AUTO, &"soothing_downpour": AbilityData.Kind.ACTIVE,
		&"stormburst": AbilityData.Kind.AUTO, &"spirit_pack": AbilityData.Kind.ACTIVE,
	}
	for id: StringName in kinds:
		check_eq(Db.get_ability(id).kind, kinds[id], "%s kind" % id)
	var pool := Db.ability_pool(&"shaman")
	for id in LEARNED:
		var found := false
		for a in pool:
			found = found or a.id == id
		check(found, "%s is in the level-up pool" % id)


func test_schools_tags_and_costs() -> void:
	var forking := Db.get_ability(&"forking_bolt")
	check_eq(forking.school, &"nature", "Forking Bolt is Nature")
	check_eq(forking.resource, &"surge", "it spends Surge")
	check_eq(forking.cost, 30.0, "30 Surge")
	for id: StringName in [&"forking_bolt", &"thunderbolt", &"stormburst"]:
		check(&"lightning" in Db.get_ability(id).tags, "%s carries the lightning tag" % id)
	for id: StringName in [&"forking_bolt", &"thunderbolt", &"rumbling_earth", &"magma_lash", &"stormburst"]:
		check(&"spell" in Db.get_ability(id).tags, "%s scales as a spell" % id)
	check_eq(Db.get_ability(&"magma_lash").school, &"fire", "Magma Lash is Fire")
	check(&"pet" in Db.get_ability(&"spirit_pack").tags, "Spirit Pack carries the pet tag")
	check(&"heal" in Db.get_ability(&"soothing_downpour").tags, "Soothing Downpour heals")
	check(&"buff" in Db.get_ability(&"totem_rite").tags, "Totem Rite is a buff")
	check(&"lightning" in BonusVocabulary.TAGS, "the tag is in the vocabulary")
	check(BonusVocabulary.PSEUDO_IDS.get(&"shaman_totems") == &"shaman", "pseudo id shaman_totems")
	check(BonusVocabulary.PSEUDO_IDS.get(&"shaman_echo") == &"shaman", "pseudo id shaman_echo")
	var entry := {"kind": "ability", "match": {"tag": "lightning"}, "mods": {"power_pct": 10.0}}
	check_eq(BonusVocabulary.validate(entry), "", "a lightning match validates")
	check(BonusVocabulary.matches(entry["match"], Db.get_ability(&"thunderbolt"), &"shaman"), "and matches Thunderbolt")
	check(not BonusVocabulary.matches(entry["match"], Db.get_ability(&"magma_lash"), &"shaman"), "but not Magma Lash")


func test_ranks_II_and_IV_add_power_and_shorten_the_cooldown() -> void:
	var all: Array[StringName] = []
	all.append_array(CORE)
	all.append_array(LEARNED)
	for id in all:
		var p := _shaman(Vector3.ZERO, 0)
		_learn(p, id)
		var base_cd := Db.get_ability(id).cooldown
		check_near(float(p.abilities.params_for(Db.get_ability(id))["power"]), 1.0, 0.0001, "%s Rank I power" % id)
		_learn(p, id, 2)
		check_near(float(p.abilities.params_for(Db.get_ability(id))["power"]), 1.25, 0.0001, "%s Rank II power" % id)
		check_near(float(p.abilities.params_for(Db.get_ability(id))["cooldown"]), base_cd * 0.9, 0.0001, "%s Rank II cooldown" % id)
		_learn(p, id, 4)
		check_near(float(p.abilities.params_for(Db.get_ability(id))["power"]), 1.5, 0.0001, "%s Rank IV power" % id)


# --- Surge ------------------------------------------------------------------------------------------

func test_surge_starts_at_zero() -> void:
	var p := _shaman()
	check_eq(_surge(p).value, 0.0, "empty")
	_surge(p).set_value(40.0)
	p.begin_wave()
	check_eq(_surge(p).value, 0.0, "a new wave starts empty")


func test_a_weapon_hit_builds_five_surge() -> void:
	var p := _shaman()
	var e := _enemy(Vector3(1, 0, 0))
	p.on_hit_dealt(5.0, e)
	check_eq(_surge(p).value, 5.0, "+5 per weapon hit")
	p.on_hit_dealt(5.0, e)
	check_eq(_surge(p).value, 10.0, "two hits")
	p.stats.set_source(&"test", {Stats.RESOURCE_REGEN: 100.0})
	p.abilities._physics_process(DT)
	p.on_hit_dealt(5.0, e)
	check_eq(_surge(p).value, 20.0, "Resource Regen doubles the gain")


func test_every_cast_builds_five_surge_after_it_was_paid() -> void:
	var p := _shaman()
	_enemy(Vector3(3, 0, 0))
	_surge(p).set_value(30.0)
	check(_cast(p, &"forking_bolt"), "Forking Bolt costs 30")
	check_eq(_surge(p).value, 5.0, "30 - 30 + 5")
	check(_cast(p, &"totem_rite"), "a free cast")
	check_eq(_surge(p).value, 10.0, "+5 for Totem Rite")
	check(not _cast(p, &"forking_bolt"), "not enough Surge for another bolt")
	check_eq(_surge(p).value, 10.0, "a failed cast gives nothing")


func test_surge_decays_slowly_out_of_combat() -> void:
	var p := _shaman()
	var e := _enemy(Vector3(1, 0, 0))
	for i in 4:
		p.on_hit_dealt(5.0, e)
	check_eq(_surge(p).value, 20.0, "20 Surge")
	_run(p, 2.9)
	check_near(_surge(p).value, 20.0, 0.0001, "no decay for 3 s after the last hit")
	_run(p, 2.1)  # 5 s after the hit: 2 s of decay at 2 per second
	check_near(_surge(p).value, 16.0, 0.1, "then 2 per second")
	_run(p, 20.0)
	check_eq(_surge(p).value, 0.0, "down to nothing")


func test_casting_without_melee_keeps_the_surge() -> void:
	var p := _shaman()
	_surge(p).set_value(50.0)
	_enemy(Vector3(3, 0, 0))
	check(_cast(p, &"totem_rite"), "a cast restarts the decay timer")
	_run(p, 2.5)
	check_near(_surge(p).value, 55.0, 0.0001, "no decay 2.5 s after the cast")
	_run(p, 1.0)
	check(_surge(p).value < 55.0, "it decays once 3 s passed")


func test_a_talent_bonus_to_the_gain_speeds_hits_and_casts() -> void:
	var p := _shaman()
	_put(p, [{"kind": "resource", "resource": "surge", "gain_on_hit_add": 1.0, "rank": 1}])
	var e := _enemy(Vector3(1, 0, 0))
	p.on_hit_dealt(5.0, e)
	check_eq(_surge(p).value, 6.0, "a hit gives 6")
	_cast(p, &"totem_rite")
	check_eq(_surge(p).value, 12.0, "a cast gives 6 too")


# --- Storm Echo -------------------------------------------------------------------------------------

func test_the_echo_chance_is_one_and_a_half_percent_per_mastery_point() -> void:
	var p := _shaman()
	var m := _mastery(p)
	check_eq(m.echo_chance(), 0.0, "no Mastery, no echo")
	p.stats.set_source(&"test", {Stats.MASTERY: 5.0})
	check_near(m.echo_chance(), 7.5, 0.0001, "5 Mastery = 7.5%")
	check_eq(m.describe(), "Storm Echo: 7.5% echo", "the tooltip")
	p.stats.set_source(&"test", {Stats.MASTERY: 10.0})
	check_near(m.echo_chance(), 15.0, 0.0001, "10 Mastery = 15%")
	check_eq(m.describe(), "Storm Echo: 15% echo", "whole numbers lose the decimal")
	p.stats.set_source(&"test", {Stats.MASTERY: 100.0})
	check_near(m.echo_chance(), 60.0, 0.0001, "capped at 60%")


func test_the_base_mastery_of_a_real_hero_gives_the_design_chance() -> void:
	var p := Player.create(Fakes.make_slot(0, &"shaman"))
	world.add_child(p)
	check_near(p.stats.get_raw(Stats.MASTERY), Stats.BASE_MASTERY, 0.0001, "the universal base Mastery")
	check_near(_mastery(p).echo_chance(), Stats.BASE_MASTERY * 1.5, 0.0001, "chance = base Mastery x 1.5")


func test_the_echo_numbers_take_the_pseudo_ability_mods() -> void:
	var p := _shaman()
	var m := _mastery(p)
	p.stats.set_source(&"test", {Stats.MASTERY: 5.0})
	check_near(float(m.echo_params()["echo_pct"]), 50.0, 0.0001, "50% echo")
	_put(p, [{"kind": "ability", "match": {"id": "shaman_echo"}, "mods": {"echo_pct_add": 10.0, "chance_per_mastery_add": 0.5}, "rank": 1}])
	check_near(float(m.echo_params()["echo_pct"]), 60.0, 0.0001, "the talent raises the echo")
	check_near(m.echo_chance(), 10.0, 0.0001, "and the chance per point: 5 x 2")
	_put(p, [])
	check_near(m.echo_chance(), 7.5, 0.0001, "taking the talent back restores it")


func test_no_rng_draw_without_a_chance_and_exactly_one_with_it() -> void:
	var p := _shaman()
	var m := _mastery(p)
	var e := _enemy(Vector3(2, 0, 0))
	var before := RunState.rng.state
	check_eq(ShamanKit.strike(p, e, 10.0, &"nature", true), 10.0, "the hit lands")
	check_eq(RunState.rng.state, before, "no Mastery: no draw")
	p.stats.set_source(&"test", {Stats.MASTERY: 5.0})
	var shadow := RandomNumberGenerator.new()
	shadow.seed = RunState.rng.seed
	shadow.state = RunState.rng.state
	shadow.randf()
	ShamanKit.strike(p, e, 10.0, &"nature", true)
	check_eq(RunState.rng.state, shadow.state, "one draw per eligible hit")
	var again := RunState.rng.state
	ShamanKit.strike(p, e, 10.0, &"nature", false)
	check_eq(RunState.rng.state, again, "an ineligible hit draws nothing")
	check(m.echoes >= 0, "the counter exists")


## A Shaman whose every eligible hit echoes (100% chance).
func _echoing_shaman() -> Player:
	var p := _shaman()
	p.stats.set_source(&"test", {Stats.MASTERY: 5.0})
	_put(p, [{"kind": "ability", "match": {"id": "shaman_echo"}, "mods": {"max_chance_add": 40.0, "chance_per_mastery_add": 100.0}, "rank": 1}])
	return p


func test_an_echo_repeats_half_the_hit_without_target_bonuses() -> void:
	var p := _echoing_shaman()
	var m := _mastery(p)
	check_near(m.echo_chance(), 100.0, 0.0001, "a sure echo for the test")
	var e := _enemy(Vector3(2, 0, 0), 1000.0)
	e.hp = 200.0
	e.max_hp = 1000.0  # below 30%: Executioner applies to the hit, not to the echo
	p.stats.set_source(&"exec", {Stats.EXECUTIONER: 100.0})
	ShamanKit.strike(p, e, 10.0, &"nature", true)
	check_eq(e.fake_damage_log.size(), 2, "the hit and its echo")
	check_near(e.fake_damage_log[0], 20.0, 0.0001, "the hit gets Executioner")
	check_near(e.fake_damage_log[1], 5.0, 0.0001, "the echo is half of the base hit, no target bonus")
	check_eq(m.echoes, 1, "one echo - an echo never echoes")
	for a in e.fake_attacker_log:
		check(a == p, "both are the Shaman's damage")


func test_an_echo_of_a_dead_target_is_skipped() -> void:
	var p := _echoing_shaman()
	var e := _enemy(Vector3(2, 0, 0), 5.0)
	ShamanKit.strike(p, e, 10.0, &"nature", true)
	check_eq(e.fake_damage_log.size(), 1, "the kill leaves nothing to echo")
	check_eq(_mastery(p).echoes, 0, "no echo")


func test_the_mastery_damage_multiplier_is_neutral() -> void:
	var p := _shaman()
	var e := _enemy(Vector3(2, 0, 0))
	for source: StringName in [&"weapon", &"ability", &"dot", &"pet", &"proc"]:
		check_eq(_mastery(p).damage_mult(e, &"nature", source), 1.0, "%s damage is not changed by the Mastery" % source)


# --- Elemental Surge hub ------------------------------------------------------------------------------

func test_the_empower_hub_is_neutral_until_a_talent_grants_charges() -> void:
	var p := _shaman()
	check_eq(ShamanKit.empower(p), 1.0, "no charge: x1")
	check_eq(ShamanKit.empower(null), 1.0, "no player: x1")
	var m := _mastery(p)
	m.grant_empower(3, 100.0)
	check_eq(ShamanKit.empower(p), 2.0, "the first charge doubles")
	check_eq(ShamanKit.empower(p), 2.0, "the second")
	m.grant_empower(3, 100.0)
	check_eq(m.empower_charges, 3, "a grant SETS the charges, it never adds")
	for i in 3:
		check_eq(ShamanKit.empower(p), 2.0, "charge %d" % i)
	check_eq(ShamanKit.empower(p), 1.0, "spent")
	m.grant_empower(2, 50.0)
	check_eq(ShamanKit.empower(p), 1.5, "+50%")


func test_empower_charges_end_with_the_wave_and_when_downed() -> void:
	var p := _shaman()
	var m := _mastery(p)
	m.grant_empower(3, 100.0)
	p.begin_wave()
	check_eq(m.empower_charges, 0, "a new wave drops them")
	m.grant_empower(3, 100.0)
	p.end_wave()
	check_eq(m.empower_charges, 0, "a cleared wave too")
	m.grant_empower(3, 100.0)
	_down(p)
	p.abilities._physics_process(DT)
	check_eq(m.empower_charges, 0, "going down drops them")


func test_the_last_fork_is_stored_for_the_artifact() -> void:
	var p := _shaman()
	check(ShamanKit.last_fork(p).is_empty(), "nothing before the first bolt")
	ShamanKit.set_last_fork(p, Vector3(3, 0, 4), 12.5)
	var f := ShamanKit.last_fork(p)
	check_eq(f["point"], Vector3(3, 0, 4), "the point")
	check_eq(f["damage"], 12.5, "the damage")
	p.begin_wave()
	check(ShamanKit.last_fork(p).is_empty(), "a new wave forgets it")


# --- Reviver hooks of the Player ----------------------------------------------------------------------

func test_the_revive_hooks_are_neutral_by_default() -> void:
	var ghost := _ally(0, Vector3.ZERO)
	var shaman := _shaman(Vector3(1, 0, 0), 1)
	check_eq(shaman.revive_speed_pct, 0.0, "no speed bonus")
	check_eq(shaman.revive_hp_pct, 0.0, "no HP bonus")
	_down(ghost)
	ghost._update_revive(1.0)
	check_near(ghost.revive_progress, 1.0, 0.0001, "one reviver: 1 s per second")
	check_near(ghost.revive_seconds_left(), Player.REVIVE_TIME - 1.0, 0.0001, "the displayed time")


func test_a_revivers_speed_bonus_speeds_up_the_revive_and_is_capped() -> void:
	var ghost := _ally(0, Vector3.ZERO)
	var shaman := _shaman(Vector3(1, 0, 0), 1)
	shaman.revive_speed_pct = 25.0
	_down(ghost)
	ghost._update_revive(1.0)
	check_near(ghost.revive_progress, 1.25, 0.0001, "+25% faster")
	check_near(ghost.revive_seconds_left(), (Player.REVIVE_TIME - 1.25) / 1.25, 0.0001, "the displayed time follows")
	ghost.revive_progress = 0.0
	shaman.revive_speed_pct = 400.0
	ghost._update_revive(1.0)
	check_near(ghost.revive_progress, 2.5, 0.0001, "capped at +150%")


func test_a_revivers_hp_bonus_returns_more_max_hp() -> void:
	var ghost := _ally(0, Vector3.ZERO)
	var shaman := _shaman(Vector3(1, 0, 0), 1)
	shaman.revive_hp_pct = 20.0
	_down(ghost)
	ghost.revive_progress = Player.REVIVE_TIME - 0.001
	ghost._update_revive(0.1)
	check(not ghost.downed, "revived")
	check_near(ghost.hp, roundf(ghost.max_hp() * 0.5), 0.0001, "30% + 20% of Max HP")
	var plain := _ally(2, Vector3(10, 0, 0))
	var other := _ally(3, Vector3(11, 0, 0))
	_down(plain)
	plain.revive_progress = Player.REVIVE_TIME - 0.001
	plain._update_revive(0.1)
	check_near(plain.hp, roundf(plain.max_hp() * Player.REVIVE_HP_RATIO), 0.0001, "no bonus: 30%")
	check(other != null, "the plain reviver exists")


# --- Determinism ------------------------------------------------------------------------------------

## A scripted fight (Surge, bolts, totems, a quake, burns, wolves) with every random effect on; returns the damage
## every enemy took in the order it happened.
func _scenario(seed_value: int) -> Array[float]:
	Fakes.free_world(world)
	EnemyGrid.mark_dirty()
	RunState.start_run(1, seed_value)
	world = Fakes.make_world(tree)
	var p := _shaman()
	p.stats.set_source(&"test", {Stats.MASTERY: 12.0, Stats.INTELLECT: 6.0, Stats.SPELL_POWER: 3.0})
	_learn(p, &"rumbling_earth")
	_learn(p, &"magma_lash")
	_learn(p, &"spirit_pack")
	var foes := _cluster(Vector3(2.5, 0, 0), 6, 1.0)
	_surge(p).set_value(100.0)
	_cast(p, &"forking_bolt")
	_cast(p, &"totem_rite")
	_cast(p, &"rumbling_earth")
	_cast(p, &"spirit_pack")
	_run(p, 4.0)
	var out: Array[float] = []
	for e in foes:
		for v in e.fake_damage_log:
			out.append(v)
	return out


func test_the_same_seed_gives_the_same_fight() -> void:
	var one := _scenario(99)
	var two := _scenario(99)
	check(one.size() > 10, "the fight dealt damage (%d hits)" % one.size())
	check_eq(one, two, "bit-identical damage with one seed")
