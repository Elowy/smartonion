extends TestCase
## Paladin Retribution talents (M5 Wave 2, talents_paladin.md §3) through player.talents.add ->
## PlayerBonuses on a real Paladin: Divine Strength, Conviction, Art of War, Sanctity of
## Battle, Vengeance, the Divine Verdict modifier (Word of Glory strikes while the party is
## healthy), Righteous Vengeance and the Seal of Command capstone (one RunState.rng roll per
## attack, derived damage from the hit's base amount). Sanctified Retribution (the aura's
## "might") is checked with the other aura talent in test_talents_paladin.gd.

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0
const LT := 1
const SEAL_ID := &"paladin_retribution_seal_of_command"

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 9001)
	RunState.set_start_level(31)
	world = EFakes.make_world(tree)
	EnemyGrid.mark_dirty()


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null
	EnemyGrid.mark_dirty()


func _paladin(pos: Vector3 = Vector3.ZERO, index: int = 0) -> Player:
	return Fakes.spawn_player(world, index, &"paladin", pos)


func _ally(index: int, pos: Vector3, class_id: StringName = &"warrior") -> Player:
	return Fakes.spawn_player(world, index, class_id, pos)


func _enemy(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


func _add(p: Player, name: String, n: int = 1) -> void:
	var id := StringName("paladin_retribution_" + name)
	for i in n:
		check(p.talents.add(id), "add %s: %s" % [id, p.talents.add_block_reason(id)])


func _remove(p: Player, name: String, n: int = 1) -> void:
	var id := StringName("paladin_retribution_" + name)
	for i in n:
		check(p.talents.remove(id), "remove %s: %s" % [id, p.talents.remove_block_reason(id)])


func _holy_power(p: Player) -> ClassResource:
	return p.abilities.get_resource(&"holy_power")


func _down(p: Player) -> void:
	p.invulnerable_left = 0.0
	p.hp = 1.0
	p.take_damage(1000.0)
	check(p.downed, "%s is down" % p.name)


func _def(p: Player, talent_id: StringName) -> Dictionary:
	for d: Dictionary in p.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS):
		if d.get("id") == String(talent_id):
			return d
	return {}


## Test override: every built proc of [param talent_id] fires on each qualifying event.
func _force(p: Player, talent_id: StringName) -> void:
	var found := false
	for pr in p.procs.procs:
		if pr.id == talent_id:
			pr.chance = 100.0
			found = true
	check(found, "%s is built" % talent_id)


## Seeds RunState.rng so its next randf() * 100 is below [param pct] ([param below] true) or
## not (false).
static func _seed_roll(pct: float, below: bool) -> void:
	for s in range(1, 5000):
		RunState.rng.seed = s
		if (RunState.rng.randf() * 100.0 < pct) == below:
			RunState.rng.seed = s
			return


## RunState.rng's state after [param draws] more randf() calls from [param state].
static func _state_after(state: int, draws: int) -> int:
	var probe := RandomNumberGenerator.new()
	probe.state = state
	for i in draws:
		probe.randf()
	return probe.state


func _wog_ctx(p: Player) -> AbilityContext:
	return p.abilities.build_context(Db.get_ability(&"word_of_glory"))


## The 13-point path (talents_paladin.md 5.2): Divine Strength 3, Conviction 3, Art of War 3,
## Sanctity of Battle 3, Seal of Command.
func _to_capstone(p: Player) -> void:
	_add(p, "divine_strength", 3)
	_add(p, "conviction", 3)
	_add(p, "art_of_war", 3)
	_add(p, "sanctity_of_battle", 3)
	_add(p, "seal_of_command")


func _seal(p: Player) -> PaladinRetributionSealOfCommand:
	return p.bonuses.script_for(SEAL_ID) as PaladinRetributionSealOfCommand


# --- Tier 1-2 ----------------------------------------------------------------------------------

func test_divine_strength_and_conviction_are_stats() -> void:
	var p := _paladin()
	var strength := p.stats.get_raw(Stats.STRENGTH)
	var crit := p.stats.get_raw(Stats.CRIT)
	for n in range(1, 4):
		_add(p, "divine_strength")
		_add(p, "conviction")
		check_eq(p.stats.get_raw(Stats.STRENGTH), strength + 2.0 * n, "+2 Strength (primary) per rank")
		check_eq(p.stats.get_raw(Stats.CRIT), crit + 2.0 * n, "+2% crit per rank")
	_remove(p, "divine_strength", 3)
	_remove(p, "conviction", 3)
	check(is_equal_approx(p.stats.get_raw(Stats.STRENGTH), strength) and is_equal_approx(p.stats.get_raw(Stats.CRIT), crit), "undone")


func test_art_of_war_gives_holy_power_on_crits() -> void:
	var p := _paladin()
	var id := &"paladin_retribution_art_of_war"
	var hp := _holy_power(p)
	var e := _enemy(Vector3(1.2, 0, 0))
	_add(p, "divine_strength", 3)
	_add(p, "art_of_war", 3)
	var def := _def(p, id)
	check(def.get("trigger") == "on_crit" and def.get("effect") == "resource" and def.get("resource") == "holy_power", "on_crit Holy Power")
	check(def.get("chance") == 60.0 and def.get("icd") == 1.0 and def.get("value") == 1 and def.get("label") == "", "20% per rank, 1 sec icd")
	_force(p, id)
	hp.set_value(0.0)
	p.procs.on_hit(e, 5.0, p.main_hand, false)
	check_eq(hp.value, 0.0, "a normal hit: nothing")
	p.procs.on_hit(e, 5.0, p.main_hand, true)
	check_eq(hp.value, 1.0, "a critical hit: +1 Holy Power")
	p.procs.on_hit(e, 5.0, p.main_hand, true)
	check_eq(hp.value, 1.0, "at most once per second")
	p.procs._physics_process(1.1)
	p.procs.on_hit(e, 5.0, p.main_hand, true)
	check_eq(hp.value, 2.0, "a second later again")


func test_sanctity_of_battle_holy_damage_and_consecration_cooldown() -> void:
	var p := _paladin()
	var cons := Db.get_ability(&"consecration")
	_add(p, "divine_strength", 3)
	for n in range(1, 4):
		_add(p, "sanctity_of_battle")
		check_near(p.bonuses.damage_mult(null, &"holy", &"ability"), 1.0 + 0.04 * n, 0.0001, "+4% Holy per rank")
		check_near(float(p.abilities.params_for(cons)["cooldown"]), 10.0 - 0.5 * n, 0.0001, "-0.5 sec per rank")
	check_near(p.abilities.cooldown_of(cons), 8.5, 0.0001, "the real cooldown")
	check_eq(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, "Holy only")
	_remove(p, "sanctity_of_battle", 3)
	check_near(p.abilities.cooldown_of(cons), 10.0, 0.0001, "undone")


# --- Tier 3 ------------------------------------------------------------------------------------

func test_vengeance_stacks_twice_after_crits() -> void:
	var p := _paladin()
	var id := &"paladin_retribution_vengeance"
	var e := _enemy(Vector3(1.2, 0, 0))
	var base := p.stats.get_raw(Stats.DAMAGE_PCT)
	_add(p, "divine_strength", 3)
	_add(p, "conviction", 2)
	_add(p, "art_of_war", 1)
	check_eq(p.talents.add_block_reason(id), "Requires Conviction", "prerequisite")
	_remove(p, "art_of_war")
	_add(p, "conviction")
	_add(p, "vengeance", 2)
	var def := _def(p, id)
	check(def.get("trigger") == "on_crit" and def.get("effect") == "buff" and def.get("max_stacks") == 2, "an on-crit buff, 2 stacks")
	check(def.get("stats", {}).get("damage_pct") == 2.0 and def.get("duration") == 8.0, "+1% per rank, 8 sec")
	for i in 3:
		p.procs.on_hit(e, 5.0, p.main_hand, true)
	check_eq(p.stats.get_raw(Stats.DAMAGE_PCT), base + 4.0, "3 crits: 2 stacks of +2%")
	p.procs._physics_process(8.1)
	check_eq(p.stats.get_raw(Stats.DAMAGE_PCT), base, "gone 8 sec later")


func test_divine_verdict_strikes_while_the_party_is_healthy() -> void:
	var p := _paladin()
	var ally := _ally(1, Vector3(-3.0, 0, 0))
	var e := _enemy(Vector3(3.0, 0, 0))
	var hp := _holy_power(p)
	hp.set_value(3.0)
	check(not p.abilities.can_cast(LT), "no talent: nobody hurt, nothing to do")
	_add(p, "divine_strength", 3)
	_add(p, "conviction", 3)
	_add(p, "divine_verdict")
	var params := p.abilities.params_for(Db.get_ability(&"word_of_glory"))
	check(float(params["verdict_pct"]) == 300.0 and float(params["verdict_range"]) == 4.0 and float(params["verdict_sp_scale"]) == 1.5, "Verdict params")
	check(p.abilities.can_cast(LT), "an enemy within 4 m")
	var expected := PaladinKit.strike_damage(p, 300.0, 1.5) * p.outgoing_damage_mult(e, &"holy", &"ability")
	p.hp = p.max_hp() * 0.85
	check(p.abilities.try_cast(LT), "Verdict")
	check_eq(e.fake_hits(), 1, "the enemy is judged")
	if e.fake_hits() > 0:
		check_near(e.fake_damage_log[0], expected, 0.0001, "300% weapon damage + 1.5 SP as Holy")
	check_near(p.hp, p.max_hp() * 0.85, 0.0001, "85%: no heal")
	check_eq(hp.value, 0.0, "3 Holy Power spent")
	hp.set_value(3.0)
	ally.hp = ally.max_hp() * 0.6
	check(p.abilities.try_cast(LT), "cast with a hurt ally")
	check(ally.hp > ally.max_hp() * 0.6 and e.fake_hits() == 1, "a hero below 80%: heals instead")
	hp.set_value(3.0)
	ally.hp = ally.max_hp()
	_down(ally)
	check(p.abilities.try_cast(LT), "cast with a downed ally")
	check(not ally.downed and e.fake_hits() == 1, "a downed ally in range: revives")
	hp.set_value(3.0)
	ally.hp = ally.max_hp()
	p.hp = p.max_hp()
	e.global_position = Vector3(6.0, 0, 0)
	EnemyGrid.mark_dirty()
	check(not p.abilities.can_cast(LT), "no enemy within 4 m and nobody hurt: nothing to do")
	check(not p.abilities.try_cast(LT) and hp.value == 3.0, "no Holy Power spent")


func test_divine_verdict_prefers_elites_and_the_bot_keeps_holy_power_for_revives() -> void:
	var p := _paladin()
	_add(p, "divine_strength", 3)
	_add(p, "conviction", 3)
	_add(p, "divine_verdict")
	var near := _enemy(Vector3(2.0, 0, 0))
	var elite := _enemy(Vector3(0, 0, 3.5))
	elite.elite_affix = &"test"
	check(PaladinWordOfGlory.verdict_target(_wog_ctx(p)) == elite, "elites and bosses first")
	elite.elite_affix = &""
	check(PaladinWordOfGlory.verdict_target(_wog_ctx(p)) == near, "else the nearest")
	var wog := Db.get_ability(&"word_of_glory")
	var effect := p.abilities.effect_for(wog)
	check(effect.wants_auto_cast(_wog_ctx(p)), "bot: a healthy party and an enemy close")
	var far_ally := _ally(1, Vector3(20.0, 0, 0))
	_down(far_ally)
	check(not effect.wants_auto_cast(_wog_ctx(p)), "bot: a teammate is down somewhere – keep the Holy Power")
	far_ally.revive(1.0)
	var hurt := _ally(2, Vector3(-3.0, 0, 0), &"mage")
	hurt.hp = hurt.max_hp() * 0.4
	check(effect.wants_auto_cast(_wog_ctx(p)), "bot: the heal rule first")
	check(PaladinWordOfGlory.verdict_now(_wog_ctx(p)) == null, "and that cast would heal")


# --- Tier 4 ------------------------------------------------------------------------------------

func test_righteous_vengeance_burns_on_crits() -> void:
	var p := _paladin()
	var id := &"paladin_retribution_righteous_vengeance"
	var e := _enemy(Vector3(1.2, 0, 0))
	_add(p, "divine_strength", 3)
	_add(p, "conviction", 3)
	_add(p, "art_of_war", 3)
	_add(p, "righteous_vengeance", 3)
	var def := _def(p, id)
	check(def.get("trigger") == "on_crit" and def.get("effect") == "dot" and def.get("school") == "holy", "a holy burn on crits")
	check(def.get("hit_pct") == 30.0 and def.get("duration") == 4.0, "10% of the hit per rank over 4 sec")
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_eq(p.procs.dot_stacks(e, id), 0, "normal hits do not burn")
	p.procs.on_hit(e, 10.0, p.main_hand, true)
	check_eq(p.procs.dot_stacks(e, id), 1, "a crit burns")
	var t := 0.0
	while t < 4.2:
		p.procs._physics_process(DT)
		t += DT
	var total := 0.0
	for d in e.fake_damage_log:
		total += d
	check_near(total, 10.0 * 0.3 * p.outgoing_damage_mult(e, &"holy", &"dot"), 0.001, "30% of the hit's base amount")


# --- Seal of Command ---------------------------------------------------------------------------

func test_seal_of_command_strikes_three_enemies_from_the_base_amount() -> void:
	var p := _paladin()
	_to_capstone(p)
	var seal := _seal(p)
	check(seal != null, "the capstone script runs")
	if seal == null:
		return
	var e := _enemy(Vector3(1.2, 0, 0))
	var n1 := _enemy(Vector3(2.2, 0, 0))
	var n2 := _enemy(Vector3(1.2, 0, 2.0))
	var n3 := _enemy(Vector3(1.2, 0, -2.5))
	var far := _enemy(Vector3(4.7, 0, 0))
	var ally := _ally(1, Vector3(-3.0, 0, 0))
	ally.hp = ally.max_hp() * 0.5
	check_near(p.outgoing_damage_mult(e, &"holy", &"proc"), 1.12, 0.0001, "Sanctity of Battle 3/3: +12% Holy")
	_seed_roll(15.0, true)
	var state := RunState.rng.state
	p.bonuses.on_hit(e, 10.0, true, true)
	check_eq(seal.seals, 1, "the roll passed")
	check_eq(RunState.rng.state, _state_after(state, 1), "exactly one draw")
	var each := 10.0 * 0.7 * 1.12
	for v: Fakes.FakeEnemy in [e, n1, n2]:
		check_eq(v.fake_hits(), 1, "struck")
		if v.fake_hits() > 0:
			check_near(v.fake_damage_log[0], each, 0.0001, "70% of the hit's base amount x Holy 1.12 (once)")
	check_eq(n3.fake_hits(), 0, "only the 2 nearest besides the target")
	check_eq(far.fake_hits(), 0, "3.5 m away: nothing")
	check_near(ally.hp, ally.max_hp() * 0.52, 0.0001, "the most wounded hero heals 2% of max HP")


func test_seal_of_command_rolls_once_per_attack() -> void:
	var p := _paladin()
	_to_capstone(p)
	var seal := _seal(p)
	var e := _enemy(Vector3(1.2, 0, 0))
	var state := RunState.rng.state
	p.bonuses.on_hit(e, 10.0, false, false)
	check_eq(RunState.rng.state, state, "further hits of an attack draw nothing")
	_seed_roll(15.0, false)
	state = RunState.rng.state
	p.bonuses.on_hit(e, 10.0, false, true)
	check(seal.seals == 0 and e.fake_hits() == 0, "the roll failed")
	check_eq(RunState.rng.state, _state_after(state, 1), "one draw")
	e.fake_dead = true
	state = RunState.rng.state
	p.bonuses.on_hit(e, 10.0, false, true)
	check_eq(RunState.rng.state, state, "a dead target: no roll")
	e.fake_dead = false
	_down(p)
	state = RunState.rng.state
	p.bonuses.on_hit(e, 10.0, false, true)
	check_eq(RunState.rng.state, state, "downed: no roll")


func test_seal_of_command_on_real_swings_and_extra_attacks() -> void:
	var p := _paladin()
	_to_capstone(p)
	var seal := _seal(p)
	seal._chance = 100.0  # test override: every attack seals
	var a := _enemy(Vector3(1.2, 0, 0))
	var b := _enemy(Vector3(1.2, 0, 0.5))
	var c := _enemy(Vector3(1.2, 0, -0.5))
	p.weapons[0].attack(a)
	check_eq(seal.seals, 1, "one seal for a swing over three enemies")
	check(a.fake_hits() == 2 and b.fake_hits() == 2 and c.fake_hits() == 2, "each: the weapon hit + the seal")
	p.weapons[0].extra_attack(1, a)
	check_eq(seal.seals, 2, "an extra attack is an attack of its own")
	RunState.add_gold(100)
	check(p.talents.try_reset(0), "Reset Talents")
	check(_seal(p) == null and p.bonuses.scripts().is_empty(), "torn down")
	var before := a.fake_hits()
	p.weapons[0].attack(a)
	check_eq(a.fake_hits(), before + 1, "no more seals")
