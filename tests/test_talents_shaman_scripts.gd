extends "res://tests/shaman_base.gd"
## The four Shaman talent scripts (M8 TALENTS-S, design_shaman.md 4.4) on a real Shaman through player.talents.add:
## Elemental Surge (Stormweaving capstone: the clock behind the ShamanMastery empower hub - first grant 8 s into
## the wave, then every 20 s, three casts at +100%, charges set never added, reset by wave end and going down, no
## charge for Totem Rite / Soothing Downpour), Gale Strike (Warspirit capstone: every 5th attack, two Nature strikes
## 0.2 s apart on the target and the nearest other enemy, held for a dead target, Surge, Storm Echo, no weapon
## hit), Elder Spirits / Gift of the Elders (Wellspring: the reviver fields of the Player and the real revive time /
## Max HP, caps, stacking) and the Bond Totem (Wellspring capstone: the script's schedule and the totem's rules -
## HP shares even out 10% of the gap per second, donors never below the average and never lethal, a downed or
## distant hero is not part of it, -20% damage taken inside, wave end / expiry / teardown clean up).
##
## Gates (TalentState): tier 2 needs 3 points in tier 1, tier 3 needs 6, tier 4 needs 9, the capstone 12 (in the
## tree's lower tiers); a prerequisite talent has to be at its max rank.

const SURGE_ID := &"shaman_stormweaving_elemental_surge"
const GALE_ID := &"shaman_warspirit_gale_strike"
const ELDER_ID := &"shaman_wellspring_elder_spirits"
const GIFT_ID := &"shaman_wellspring_gift_of_the_elders"
const BOND_ID := &"shaman_wellspring_bond_totem"
const STRIKE := {"damage": 5.0, "intellect_scale": 0.8, "spell_power_scale": 1.2}


func before_each() -> void:
	super()
	RunState.set_start_level(31)


# --- Helpers -----------------------------------------------------------------------------------

func _add(p: Player, id: StringName, n: int = 1) -> void:
	for i in n:
		check(p.talents.add(id), "add %s: %s" % [id, p.talents.add_block_reason(id)])


func _stats(p: Player, mastery: float = 0.0) -> void:
	p.stats.set_source(&"test", {Stats.INTELLECT: 10.0, Stats.SPELL_POWER: 4.0, Stats.MASTERY: mastery})


## The 12 Stormweaving points that open the capstone, then Elemental Surge.
func _to_surge(p: Player) -> ShamanStormweavingElementalSurge:
	for n in ["livewire", "kindled_spark", "charged_mind", "stormcharged"]:
		_add(p, StringName("shaman_stormweaving_" + n), 3)
	_add(p, SURGE_ID)
	return p.bonuses.script_for(SURGE_ID) as ShamanStormweavingElementalSurge


## 12 Warspirit points without a Surge or ability talent (they would blur the numbers), then Gale Strike.
func _to_gale(p: Player) -> ShamanWarspiritGaleStrike:
	for n in ["twinned_spirits", "hardened_knuckles", "mirrored_strikes"]:
		_add(p, StringName("shaman_warspirit_" + n), 3)
	_add(p, &"shaman_warspirit_flame_tempering", 2)
	_add(p, &"shaman_warspirit_molten_trail")
	_add(p, GALE_ID)
	return p.bonuses.script_for(GALE_ID) as ShamanWarspiritGaleStrike


## 12 Wellspring points that leave the totems alone (no Weathered Wood), then Bond Totem.
func _to_bond(p: Player) -> ShamanWellspringBondTotem:
	_add(p, &"shaman_wellspring_gentle_current", 3)
	_add(p, &"shaman_wellspring_elder_spirits", 3)
	_add(p, &"shaman_wellspring_deepening_rain", 3)
	_add(p, &"shaman_wellspring_attuned_totems", 2)
	_add(p, &"shaman_wellspring_ancestral_reach")
	_add(p, BOND_ID)
	return p.bonuses.script_for(BOND_ID) as ShamanWellspringBondTotem


## The 3 Wellspring tier-1 points Elder Spirits (tier 2) needs.
func _elder_gate(p: Player) -> void:
	_add(p, &"shaman_wellspring_gentle_current", 3)


## The 9 points below Gift of the Elders (tier 4): tier 1 twice and Elder Spirits.
func _gift_gate(p: Player) -> void:
	_add(p, &"shaman_wellspring_gentle_current", 3)
	_add(p, &"shaman_wellspring_weathered_wood", 3)
	_add(p, ELDER_ID, 3)


## The hero's bonuses tick for [param seconds] (Fakes worlds are not processed) and every totem / area in the world.
func _tick(p: Player, seconds: float, world_too: bool = false) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p.bonuses.tick(DT)
		if world_too:
			_step_world(DT)
		t += DT


## One weapon attack's first hit on [param e]: what Player.on_hit_dealt does after a swing.
func _attack(p: Player, e: Enemy, first: bool = true) -> void:
	p.on_hit_dealt(3.0, e, p.main_hand, false, false, first, 3.0)


func _strike_amount(p: Player) -> float:
	return ShamanKit.spell_damage(p.stats, STRIKE, ShamanKit.NATURE)


func _hp_ratio(p: Player) -> float:
	return p.hp / p.max_hp()


func _bond_params(extra: Dictionary = {}) -> Dictionary:
	var out := {"duration": 10.0, "radius": 6.0, "equalize_pct": 10.0, "tick": 0.5, "damage_taken_pct": 20.0}
	out.merge(extra, true)
	return out


func _plant_bond(p: Player, extra: Dictionary = {}) -> ShamanTotem:
	return ShamanTotem.plant(p, &"bond", _bond_params(extra), p.global_position, 10.0)


## [param n] equalise ticks of the totem (0.5 s each).
func _bond_ticks(t: ShamanTotem, n: int) -> void:
	for i in n * 30:
		t.step(DT)


# --- Elemental Surge ---------------------------------------------------------------------------

func test_elemental_surge_grants_three_empowered_casts_8_seconds_into_the_wave_then_every_20() -> void:
	var p := _shaman()
	_stats(p)
	var s := _to_surge(p)
	check(s != null, "the capstone script runs")
	if s == null:
		return
	var m := _mastery(p)
	check_eq(m.empower_charges, 0, "no charges to start with")
	_tick(p, 30.0)
	check_eq(m.empower_charges, 0, "the clock waits for a wave")
	s.begin_wave()
	check_near(s.time_left(), 8.0, 0.0001, "first grant after 8 sec")
	_tick(p, 7.9)
	check_eq(m.empower_charges, 0, "not yet")
	_tick(p, 0.2)
	check_eq([m.empower_charges, m.empower_pct, s.grants], [3, 100.0, 1], "three casts at +100%")
	check_near(s.time_left(), 19.9, 0.05, "the next one in 20 sec")
	# Charges are set, never added: spend one, wait for the next grant.
	check_eq(m.take_empower(), 2.0, "a cast takes one charge and doubles")
	check_eq(m.empower_charges, 2, "two left")
	_tick(p, 19.7)
	check_eq(m.empower_charges, 2, "the old charges stay until the grant")
	_tick(p, 0.4)
	check_eq(m.empower_charges, 3, "the grant sets three (not 2 + 3)")
	check_eq(s.grants, 2, "two grants")
	check(s.describe().begins_with("Elemental Surge: 3 empowered"), "describe: %s" % s.describe())


func test_elemental_surge_doubles_the_next_three_damaging_casts_and_leaves_support_alone() -> void:
	var p := _shaman()
	_stats(p)
	var e := _enemy(Vector3(3, 0, 0))
	_learn(p, &"thunderbolt")
	_learn(p, &"soothing_downpour")
	var s := _to_surge(p)
	var cd := Db.get_ability(&"thunderbolt")
	# The talent path has Livewire 3/3 (+9% Nature): compare with the same cast before the grant.
	check(_cast(p, &"thunderbolt"), "a plain bolt")
	var plain := e.fake_damage_log[0]
	s.begin_wave()
	_tick(p, 8.1)
	var m := _mastery(p)
	check_eq(m.empower_charges, 3, "granted")
	var dealt: Array[float] = []
	for i in 4:
		p.abilities.set_cooldown(cd, 0.0)
		var first_new := e.fake_damage_log.size()
		check(_cast(p, &"thunderbolt"), "bolt %d" % i)
		# The bolt's own hit comes first; the path's Mastery may add a Storm Echo hit after it.
		dealt.append(e.fake_damage_log[first_new])
		if i == 0:
			# Support never takes a charge.
			p.abilities.set_cooldown(Db.get_ability(&"soothing_downpour"), 0.0)
			check(_cast(p, &"soothing_downpour"), "Soothing Downpour")
			p.abilities.set_cooldown(Db.get_ability(&"totem_rite"), 0.0)
			check(_cast(p, &"totem_rite"), "Totem Rite")
			check_eq(m.empower_charges, 2, "Soothing Downpour and Totem Rite took no charge")
	check_near(dealt[0], plain * 2.0, 0.001, "the first empowered bolt deals +100%")
	check_near(dealt[1], plain * 2.0, 0.001, "the second")
	check_near(dealt[2], plain * 2.0, 0.001, "the third")
	check_near(dealt[3], plain, 0.001, "the fourth is a plain bolt again")
	check_eq(m.empower_charges, 0, "all spent")


func test_elemental_surge_resets_with_the_wave_and_when_the_shaman_goes_down() -> void:
	var p := _shaman()
	_stats(p)
	var s := _to_surge(p)
	var m := _mastery(p)
	s.begin_wave()
	_tick(p, 8.1)
	check_eq(m.empower_charges, 3, "granted")
	# Wave end: the hub drops the charges (AbilityRunner.end_wave), the clock stops.
	p.end_wave()
	check_eq(m.empower_charges, 0, "wave end clears the charges")
	_tick(p, 60.0)
	check_eq(m.empower_charges, 0, "no clock between waves")
	check_near(s.time_left(), 8.0, 0.0001, "ready to start over")
	# Next wave: 8 sec again.
	p.begin_wave()
	_tick(p, 7.5)
	check_eq(m.empower_charges, 0, "8 sec into the wave, not before")
	_tick(p, 0.7)
	check_eq(m.empower_charges, 3, "granted again")
	_tick(p, 5.0)
	# Going down: the hub drops the charges at its next tick, the clock goes back to its start.
	_down(p)
	p.abilities._physics_process(DT)
	check_eq(m.empower_charges, 0, "down: no charges")
	_tick(p, 0.2)
	check_near(s.time_left(), 8.0, 0.0001, "the clock is back at 8 sec")
	var grants := s.grants
	_tick(p, 30.0)
	check_eq(s.grants, grants, "no grant while downed")
	p.revive(1.0)
	_tick(p, 7.9)
	check_eq(m.empower_charges, 0, "after the revive the first grant needs 8 sec again")
	_tick(p, 0.3)
	check_eq(m.empower_charges, 3, "granted")


func test_elemental_surge_leaves_nothing_behind_when_taken_back() -> void:
	var p := _shaman()
	var s := _to_surge(p)
	var m := _mastery(p)
	s.begin_wave()
	_tick(p, 8.1)
	check_eq(m.empower_charges, 3, "granted")
	check(p.talents.remove(SURGE_ID), "the capstone is taken back")
	check_eq(m.empower_charges, 0, "the charges went with it")
	check(p.bonuses.script_for(SURGE_ID) == null, "the script is gone")
	_tick(p, 60.0)
	check_eq(m.empower_charges, 0, "and nothing is granted any more")
	check_eq(ShamanKit.empower(p), 1.0, "plain casts")


func test_elemental_surge_params_and_text() -> void:
	var def: Dictionary = Db.get_talent(SURGE_ID).effects[0]
	check_eq(def.get("params"), {"interval": 20.0, "first_at": 8.0, "casts": 3, "pct": 100.0}, "the params as designed")
	check_eq(Db.get_talent(SURGE_ID).text_for_rank(1), "Every 20 sec, your next 3 damaging abilities deal 100% more damage.", "text")


# --- Gale Strike -------------------------------------------------------------------------------

func test_every_fifth_attack_calls_two_lightning_strikes() -> void:
	var p := _shaman()
	_stats(p)
	var g := _to_gale(p)
	check(g != null, "the capstone script runs")
	if g == null:
		return
	var a := _enemy(Vector3(3, 0, 0))
	var b := _enemy(Vector3(4, 0, 0))
	var c := _enemy(Vector3(8, 0, 0))
	var far := _enemy(Vector3(12, 0, 0))
	_surge(p).set_value(0.0)
	for i in 4:
		_attack(p, a)
	check_eq(g.attacks, 4, "four attacks counted")
	check(a.fake_damage_log.is_empty() and b.fake_damage_log.is_empty(), "nothing yet")
	_attack(p, a)
	var amount := _strike_amount(p)
	check_eq(g.volleys, 1, "the fifth attack calls the strikes")
	check_eq(g.attacks, 0, "the count starts over")
	check_eq(a.fake_damage_log.size(), 1, "strike one: the attack's target, at once")
	check_near(a.fake_damage_log[0], amount, 0.001, "5 + 0.8 Intellect + 1.2 Spell Power = %.2f" % amount)
	check_near(amount, 5.0 + 8.0 + 4.8, 0.001, "17.8 at Intellect 10, Spell Power 4")
	check(b.fake_damage_log.is_empty(), "strike two waits 0.2 sec")
	check_near(_surge(p).value, 5.0 * 5.0 + 3.0, 0.0001, "five weapon hits built 5 Surge each, the strike 3")
	_tick(p, 0.15)
	check(b.fake_damage_log.is_empty(), "0.15 sec: not yet")
	_tick(p, 0.1)
	check_eq(b.fake_damage_log.size(), 1, "strike two: the nearest other enemy within 6 m of the first target")
	check_near(b.fake_damage_log[0], amount, 0.001, "the same amount")
	check(c.fake_damage_log.is_empty() and far.fake_damage_log.is_empty(), "no one else")
	check_eq(a.fake_damage_log.size(), 1, "the first target is not struck twice while others are near")
	check_near(_surge(p).value, 5.0 * 5.0 + 6.0, 0.0001, "3 Surge per strike")
	check_eq(g.strikes_dealt, 2, "two strikes")
	check_near(RunState.damage_by_player.get(0, 0.0), amount * 2.0, 0.001, "both are the Shaman's damage")
	check(a.fake_attacker_log[0] == p and b.fake_attacker_log[0] == p, "the Shaman is the attacker")
	# The second volley: a plain fifth attack again.
	for i in 5:
		_attack(p, c)
	check_eq(g.volleys, 2, "every fifth attack")


func test_the_second_strike_falls_back_to_the_same_target_and_is_lost_without_one() -> void:
	var p := _shaman()
	_stats(p)
	var g := _to_gale(p)
	var only := _enemy(Vector3(3, 0, 0))
	for i in 5:
		_attack(p, only)
	_tick(p, 0.3)
	check_eq(only.fake_damage_log.size(), 2, "alone: both strikes land on the same enemy")
	# The first target dies between the strikes and nobody else is near: the second one is lost.
	var frail := _enemy(Vector3(-20, 0, 0), 1000.0)
	for i in 5:
		_attack(p, frail)
	check_eq(frail.fake_damage_log.size(), 1, "strike one landed")
	frail.fake_dead = true
	var before := g.strikes_dealt
	_tick(p, 0.3)
	check_eq(g.strikes_dealt, before, "no target for strike two: it is lost")


func test_a_strike_is_held_for_the_next_attack_when_the_target_is_already_dead() -> void:
	var p := _shaman()
	_stats(p)
	var g := _to_gale(p)
	var corpse := _enemy(Vector3(3, 0, 0))
	var live := _enemy(Vector3(5, 0, 0))
	corpse.fake_dead = true
	for i in 5:
		_attack(p, corpse)
	check_eq(g.volleys, 0, "the target is dead: no strikes")
	check_eq(g.attacks, 5, "the count is held at 5")
	check(corpse.fake_damage_log.is_empty(), "nothing struck a corpse")
	_attack(p, live)
	check_eq(g.volleys, 1, "the next attack calls them")
	check_eq(live.fake_damage_log.size(), 1, "on the living target")
	check_eq(g.attacks, 0, "and the count starts over")


func test_only_the_first_hit_of_an_attack_counts() -> void:
	var p := _shaman()
	_stats(p)
	var g := _to_gale(p)
	var e := _enemy(Vector3(3, 0, 0))
	for i in 12:
		_attack(p, e, false)
	check_eq(g.attacks, 0, "a swing's further hits do not count")
	check_eq(g.volleys, 0, "no strikes")
	for i in 5:
		_attack(p, e)
		_attack(p, e, false)
	check_eq(g.volleys, 1, "five attacks, however many targets each hit")


func test_gale_strikes_are_no_weapon_hits_and_wave_hooks_clear_the_count() -> void:
	var p := _shaman()
	_stats(p)
	var g := _to_gale(p)
	var e := _enemy(Vector3(3, 0, 0))
	var weapon_hits := [0]
	p.hit_dealt.connect(func(_d: float, _t: Node3D) -> void: weapon_hits[0] += 1)
	for i in 5:
		_attack(p, e)
	_tick(p, 0.3)
	check_eq(weapon_hits[0], 5, "five weapon hits and no more: the strikes are spell hits")
	# Wave start / end clear the count and the strikes still to come.
	for i in 3:
		_attack(p, e)
	check_eq(g.attacks, 3, "three counted")
	g.begin_wave()
	check_eq(g.attacks, 0, "wave start clears the count")
	for i in 5:
		_attack(p, e)
	var before := e.fake_damage_log.size()
	g.end_wave()
	_tick(p, 0.5)
	check_eq(e.fake_damage_log.size(), before, "wave end drops the second strike")
	check_eq(g.attacks, 0, "and the count")
	# Going down drops the strikes in flight.
	for i in 5:
		_attack(p, e)
	before = e.fake_damage_log.size()
	_down(p)
	_tick(p, 0.5)
	check_eq(e.fake_damage_log.size(), before, "a downed Shaman's second strike never comes")
	check_eq(g.describe(), "Gale Strike: 0 / 5 attacks", "describe")


func test_gale_strikes_follow_the_outgoing_multipliers_and_roll_storm_echo() -> void:
	var p := _shaman()
	_stats(p, 100.0)
	var g := _to_gale(p)
	var e := _enemy(Vector3(3, 0, 0))
	var amount := _strike_amount(p)
	p.damage_mults[&"test"] = 1.5
	for i in 5:
		_attack(p, e)
	check_near(e.fake_damage_log[0], amount * 1.5, 0.001, "the Nature multipliers apply to the strike")
	var m := _mastery(p)
	check_near(m.echo_chance(), 60.0, 0.0001, "Mastery for the 60% cap")
	var before := m.echoes
	for volley in 40:
		for i in 5:
			_attack(p, e)
	check_eq(g.volleys, 41, "41 volleys")
	var echoes := m.echoes - before
	check(echoes >= 25 and echoes <= 65, "about 60%% of the 80 strikes echo (got %d)" % echoes)
	# No Elemental Surge charge is ever spent on a strike.
	m.grant_empower(3, 100.0)
	for i in 5:
		_attack(p, e)
	check_eq(m.empower_charges, 3, "Gale Strike takes no Elemental Surge charge")


func test_gale_strike_params_and_text() -> void:
	var def: Dictionary = Db.get_talent(GALE_ID).effects[0]
	check_eq(def.get("params"), {"every": 5, "strikes": 2, "damage": 5.0, "intellect_scale": 0.8, "spell_power_scale": 1.2,
		"strike_delay": 0.2, "range": 6.0, "surge_per_strike": 3.0}, "the params as designed")
	check_eq(Db.get_talent(GALE_ID).text_for_rank(1),
		"Every 5th weapon attack calls down 2 lightning strikes on the target, each a Nature hit that also builds Surge.", "text")


# --- Elder Spirits and Gift of the Elders ------------------------------------------------------------

## Seconds a downed [param ally] needs until it is up, with [param revivers] standing next to it.
func _revive_time(ally: Player) -> float:
	var steps := 0
	while ally.downed and steps < 2000:
		ally._update_revive(DT)
		steps += 1
	return float(steps) * DT


func test_elder_spirits_raises_the_reviver_fields_and_gives_spirit() -> void:
	var p := _shaman()
	check_eq([p.revive_speed_pct, p.revive_hp_pct], [0.0, 0.0], "no bonuses to start with")
	var spirit := p.stats.get_raw(Stats.SPIRIT)
	_elder_gate(p)
	spirit = p.stats.get_raw(Stats.SPIRIT)
	for n in range(1, 4):
		_add(p, ELDER_ID)
		check_eq(p.revive_speed_pct, 25.0 * n, "+25%% revive speed per rank (rank %d)" % n)
		check_eq(p.stats.get_raw(Stats.SPIRIT) - spirit, float(n), "+1 Spirit per rank")
	check_eq(p.revive_hp_pct, 0.0, "no extra HP from Elder Spirits")
	_add(p, &"shaman_wellspring_weathered_wood", 3)
	for n in range(1, 4):
		_add(p, GIFT_ID)
		check_eq(p.revive_hp_pct, 10.0 * n, "+10%% revive HP per rank (rank %d)" % n)
		check_eq(p.revive_speed_pct, 75.0, "the speed is untouched")
	check_eq(p.bonuses.script_for(ELDER_ID).describe(), "Elder Spirits: revives 75% faster", "describe")
	check_eq(p.bonuses.script_for(GIFT_ID).describe(), "Elder Spirits: revived allies return with 30% more HP", "describe")
	check(Player.reviver_speed_boost([p] as Array[Player]) == 1.75 and Player.reviver_hp_bonus([p] as Array[Player]) == 30.0,
		"the Player's statics read them")
	check(p.talents.remove(GIFT_ID), "the Gift is taken back")
	check_eq(p.revive_hp_pct, 20.0, "one rank less")
	_remove_all(p)
	check_eq([p.revive_speed_pct, p.revive_hp_pct], [0.0, 0.0], "everything taken back: exactly zero")


## Takes back every pending talent point (the order the tree allows: highest tier first).
func _remove_all(p: Player) -> void:
	for guard in 100:
		var removed := false
		for tier in range(5, 0, -1):
			for tree_data in p.talents.trees():
				for t in tree_data.talents_in_tier(tier):
					if p.talents.rank_of(t.id) > 0 and p.talents.remove(t.id):
						removed = true
		if not removed:
			break


func test_elder_spirits_shortens_the_real_revive() -> void:
	var p := _shaman(Vector3(1.0, 0, 0))
	var ally := _ally(1, Vector3.ZERO)
	_elder_gate(p)
	_down(ally)
	check(ally.downed, "the ally is down")
	check_near(_revive_time(ally), 5.0, 0.05, "5 sec without talents")
	for n in range(1, 4):
		_add(p, ELDER_ID)
		_down(ally)
		var time := _revive_time(ally)
		check_near(time, 5.0 / (1.0 + 0.25 * n), 0.05, "rank %d: %.2f sec" % [n, 5.0 / (1.0 + 0.25 * n)])
	_down(ally)
	ally._update_revive(DT)
	check_near(ally.revive_seconds_left(), 5.0 / 1.75 - DT, 0.06, "the bar shows the shorter time (reviver_boost)")
	# A downed Shaman revives nobody.
	_down(p)
	ally.revive_progress = 0.0
	ally._update_revive(DT)
	check_eq(ally.reviver_boost, 1.0, "a downed Shaman is no reviver")


func test_the_revive_speed_stacks_between_shamans_up_to_the_cap() -> void:
	var a := _shaman(Vector3(1.0, 0, 0), 0)
	var b := _shaman(Vector3(-1.0, 0, 0), 1)
	var c := _shaman(Vector3(0, 0, 1.0), 2)
	var ally := _ally(3, Vector3.ZERO)
	for p in [a, b, c]:
		_elder_gate(p)
		_add(p, ELDER_ID, 3)
	_down(ally)
	# Two Shamans: (1 + 1.5) from the talents x (1 + 0.5) for the second reviver = 3.75.
	c.global_position = Vector3(30, 0, 0)
	check_near(_revive_time(ally), 5.0 / 3.75, 0.05, "two Shamans: 150% faster and the second reviver's 50%")
	# Three Shamans: 225% is capped at 150%: 2.5 x (1 + 0.5 x 2) = 5.
	c.global_position = Vector3(0, 0, 1.0)
	_down(ally)
	check_near(_revive_time(ally), 5.0 / 5.0, 0.05, "three Shamans: capped at +150%")
	check_eq(Player.reviver_speed_boost([a, b, c] as Array[Player]), 2.5, "the boost is capped")


func test_a_reviver_without_the_talent_adds_only_the_second_reviver_bonus() -> void:
	var shaman := _shaman(Vector3(1.0, 0, 0), 0)
	var warrior := _ally(1, Vector3(-1.0, 0, 0))
	var ally := _ally(2, Vector3.ZERO, &"mage")
	_elder_gate(shaman)
	_add(shaman, ELDER_ID, 3)
	_down(ally)
	check_near(_revive_time(ally), 5.0 / (1.5 * 1.75), 0.05, "Shaman + Warrior: 1.5 x 1.75")
	check_eq(warrior.revive_speed_pct, 0.0, "the Warrior has no bonus")


func test_gift_of_the_elders_returns_allies_with_more_hp() -> void:
	var p := _shaman(Vector3(1.0, 0, 0))
	var ally := _ally(1, Vector3.ZERO)
	_gift_gate(p)
	_down(ally)
	_revive_time(ally)
	check_eq(ally.hp, _revived_hp(ally, 0.0), "30% of Max HP without the Gift")
	for n in range(1, 4):
		_add(p, GIFT_ID)
		_down(ally)
		_revive_time(ally)
		check_eq(ally.hp, _revived_hp(ally, 10.0 * n), "rank %d: %d%% of Max HP" % [n, 30 + 10 * n])
	# Two more Shamans with the Gift: 30% each is capped at +60%.
	var q := _shaman(Vector3(-1.0, 0, 0), 2)
	var r := _shaman(Vector3(0, 0, 1.0), 3)
	for hero in [q, r]:
		_gift_gate(hero)
		_add(hero, GIFT_ID, 3)
	_down(ally)
	_revive_time(ally)
	check_eq(ally.hp, _revived_hp(ally, 60.0), "capped: 30% + 60% = 90%")
	check_eq(Player.reviver_hp_bonus([p, q, r] as Array[Player]), 60.0, "the HP bonus is capped at 60 points")


## The HP a revive with [param bonus] percentage points brings back (Player.revive's own arithmetic).
func _revived_hp(ally: Player, bonus: float) -> float:
	return clampf(roundf(ally.max_hp() * minf(1.0, Player.REVIVE_HP_RATIO + bonus / 100.0)), 1.0, ally.max_hp())


func test_a_word_of_glory_revive_is_not_touched() -> void:
	# Elder Spirits changes the circle revive only: a direct revive() keeps its own ratio.
	var p := _shaman()
	var ally := _ally(1, Vector3(1.0, 0, 0))
	_elder_gate(p)
	_add(p, ELDER_ID, 3)
	_down(ally)
	ally.revive(0.5)
	check_eq(ally.hp, clampf(roundf(ally.max_hp() * 0.5), 1.0, ally.max_hp()), "revive(0.5) is 50%")


# --- Bond Totem: the totem node ------------------------------------------------------------------

func test_the_bond_totem_evens_out_hp_shares_a_tenth_of_the_gap_per_second() -> void:
	var s := _shaman(Vector3.ZERO, 0)
	var a := _ally(1, Vector3(2, 0, 0))
	var b := _ally(2, Vector3(-3, 0, 0), &"mage")
	a.hp = a.max_hp() * 0.4
	var t := _plant_bond(s)
	var avg := (1.0 + 0.4 + 1.0) / 3.0
	check_eq(t.element, &"bond", "a bond totem")
	t.step(DT)
	# One tick (0.5 sec): 10% per second x 0.5 = 5% of the gap.
	check_near(_hp_ratio(a), 0.4 + (avg - 0.4) * 0.05, 0.001, "the wounded hero gains 5%% of the gap per tick: %.4f" % _hp_ratio(a))
	check_near(_hp_ratio(s), 1.0 - (1.0 - avg) * 0.05, 0.001, "the Shaman gives 5% of its gap")
	check_near(_hp_ratio(b), 1.0 - (1.0 - avg) * 0.05, 0.001, "so does the Mage")
	# Ten seconds: the gap is 0.95^20 of what it was; the average does not move.
	_bond_ticks(t, 19)
	var gap := avg - 0.4
	check_near(_hp_ratio(a), avg - gap * pow(0.95, 20), 0.002, "after 10 sec the gap is 0.95^20 of the start")
	check_near((_hp_ratio(a) + _hp_ratio(s) + _hp_ratio(b)) / 3.0, avg, 0.002, "the average stays")
	t.dismiss()


func test_the_bond_totem_credits_the_heal_and_loses_hp_silently() -> void:
	var s := _shaman(Vector3.ZERO, 0)
	var a := _ally(1, Vector3(2, 0, 0))
	a.hp = a.max_hp() * 0.2
	var taken_before := float(RunState.damage_taken_by_player.get(1, 0.0)) + float(RunState.damage_taken_by_player.get(0, 0.0))
	var healed_before := float(RunState.healing_by_player.get(0, 0.0))
	var hurt_events := [0]
	s.damage_taken.connect(func(_d: float, _src: Node3D) -> void: hurt_events[0] += 1)
	var s_hp := s.hp
	var a_hp := a.hp
	var t := _plant_bond(s)
	t.step(DT)
	var gained := a.hp - a_hp
	var lost := s_hp - s.hp
	check(gained > 0.0 and lost > 0.0, "HP moved: +%.3f / -%.3f" % [gained, lost])
	check_near(float(RunState.healing_by_player.get(0, 0.0)) - healed_before, gained, 0.0001, "the gain is the Shaman's healing")
	var taken_after := float(RunState.damage_taken_by_player.get(1, 0.0)) + float(RunState.damage_taken_by_player.get(0, 0.0))
	check_eq(taken_after, taken_before, "the loss is no damage: nothing on the damage-taken meter")
	check_eq(hurt_events[0], 0, "no damage event")
	check_eq(s.invulnerable_left, 0.0, "no invulnerability frames")
	t.dismiss()


func test_a_donor_never_drops_below_the_average_and_is_never_lethal() -> void:
	var s := _shaman(Vector3.ZERO, 0)
	var a := _ally(1, Vector3(2, 0, 0))
	var b := _ally(2, Vector3(-2, 0, 0))
	a.hp = a.max_hp() * 0.2
	b.hp = b.max_hp() * 0.5
	# A share of 100%: everybody lands exactly on the average - donors on it, not below it.
	var t := _plant_bond(s, {"equalize_pct": 1000.0})
	var avg := (1.0 + 0.2 + 0.5) / 3.0
	t.step(DT)
	for hero in [s, a, b]:
		check_near(_hp_ratio(hero), avg, 0.001, "%s is on the average (not below it)" % hero.name)
	t.dismiss()
	# Never lethal: the floor is 1 HP even when the average lies below it.
	s.hp = 1.3
	a.hp = 1.2
	b.hp = 0.1
	var t2 := _plant_bond(s, {"equalize_pct": 1000.0})
	t2.step(DT)
	check(s.hp >= 1.0 and not s.downed, "a donor never goes below 1 HP (%.2f)" % s.hp)
	check(a.hp >= 1.0 and not a.downed, "a donor never goes below 1 HP (%.2f)" % a.hp)
	check(b.hp > 0.1, "the receiver gained (%.2f)" % b.hp)
	t2.dismiss()


func test_drain_hp_is_silent_and_floored() -> void:
	var p := _shaman()
	p.hp = 10.0
	var taken := p.drain_hp(4.0)
	check_eq([taken, p.hp], [4.0, 6.0], "takes what it is told")
	check_eq(p.drain_hp(100.0), 5.0, "never below 1 HP")
	check_eq(p.hp, 1.0, "1 HP")
	check_eq(p.drain_hp(5.0), 0.0, "nothing left to take")
	p.hp = 10.0
	check_eq(p.drain_hp(100.0, 6.0), 4.0, "the given floor")
	check_eq(p.hp, 6.0, "6 HP")
	check_eq(p.drain_hp(100.0, 0.0), 5.0, "a floor below 1 counts as 1")
	check_eq(p.drain_hp(-3.0), 0.0, "negative: nothing")
	check(not p.downed and p.invulnerable_left == 0.0, "no hit reaction")
	_down(p)
	check_eq(p.drain_hp(5.0), 0.0, "a downed hero loses nothing")


func test_downed_and_distant_heroes_are_not_part_of_the_bond() -> void:
	var s := _shaman(Vector3.ZERO, 0)
	var a := _ally(1, Vector3(2, 0, 0))
	var downed := _ally(2, Vector3(-2, 0, 0))
	var far := _ally(3, Vector3(7, 0, 0))
	a.hp = a.max_hp() * 0.4
	far.hp = far.max_hp() * 0.1
	_down(downed)
	var downed_hp := downed.hp
	var far_hp := far.hp
	var t := _plant_bond(s)
	t.step(DT)
	var avg := (1.0 + 0.4) / 2.0
	check_near(_hp_ratio(a), 0.4 + (avg - 0.4) * 0.05, 0.001, "the average is of the two living heroes in range (%.2f)" % avg)
	check_eq(downed.hp, downed_hp, "a downed hero is untouched")
	check_eq(far.hp, far_hp, "a hero at 7 m (radius 6) is untouched")
	check(not far.damage_taken_mults.has(&"bond_totem:0"), "and takes no less damage")
	# Walking in: the next field check (0.25 sec) picks the hero up; walking out drops it.
	far.global_position = Vector3(4, 0, 0)
	for i in 20:
		t.step(DT)
	check(far.damage_taken_mults.has(&"bond_totem:0"), "inside: the reduction")
	_bond_ticks(t, 4)
	check(far.hp > far_hp, "inside: its HP share moves towards the average (%.2f -> %.2f)" % [far_hp, far.hp])
	far.global_position = Vector3(6.5, 0, 0)
	for i in 20:
		t.step(DT)
	check(not far.damage_taken_mults.has(&"bond_totem:0"), "outside again: no reduction")
	var left_at := far.hp
	_bond_ticks(t, 3)
	check_eq(far.hp, left_at, "and no more evening out")
	# The circle counts the Shaman's Area Size.
	far.global_position = Vector3(6.8, 0, 0)
	for i in 20:
		t.step(DT)
	check(not far.damage_taken_mults.has(&"bond_totem:0"), "6.8 m is outside 6 m")
	s.stats.set_source(&"test_area", {Stats.AREA_SIZE: 20.0})
	for i in 20:
		t.step(DT)
	check(far.damage_taken_mults.has(&"bond_totem:0"), "with +20% Area Size the circle is 7.2 m")
	t.dismiss()


func test_the_bond_totem_cuts_damage_taken_by_a_fifth() -> void:
	var s := _shaman(Vector3.ZERO, 0)
	var a := _ally(1, Vector3(2, 0, 0))
	var out := _ally(2, Vector3(9, 0, 0))
	var plain := s._mitigated(10.0, CombatMath.KIND_MELEE, null)
	var plain_projectile := a._mitigated(10.0, CombatMath.KIND_PROJECTILE, null)
	var t := _plant_bond(s)
	for i in 20:
		t.step(DT)
	var key := &"bond_totem:0"
	check_near(float(s.damage_taken_mults.get(key, 0.0)), 0.8, 0.0001, "x0.8 for the Shaman")
	check_near(float(a.damage_taken_mults.get(key, 0.0)), 0.8, 0.0001, "and for the ally")
	check(not out.damage_taken_mults.has(key), "not for a hero out of range")
	check_near(s._mitigated(10.0, CombatMath.KIND_MELEE, null), plain * 0.8, 0.0001, "the mitigated hit is 20% smaller")
	check_near(a._mitigated(10.0, CombatMath.KIND_PROJECTILE, null), plain_projectile * 0.8, 0.0001, "every kind of hit")
	var hp := s.hp
	s.take_damage(10.0, CombatMath.KIND_MELEE)
	check_near(hp - s.hp, plain * 0.8, 0.0001, "the real hit takes 20% less")
	# A second Shaman's totem stacks multiplicatively (one key per owner).
	var s2 := _shaman(Vector3(1, 0, 0), 3)
	var t2 := _plant_bond(s2)
	for i in 20:
		t2.step(DT)
	check_near(float(s.damage_taken_mults.get(&"bond_totem:0", 0.0)) * float(s.damage_taken_mults.get(&"bond_totem:3", 0.0)), 0.64, 0.0001,
		"two totems: x0.8 x 0.8")
	t2.dismiss()
	check(not s.damage_taken_mults.has(&"bond_totem:3"), "the second totem's key goes with it")
	check(s.damage_taken_mults.has(key), "the first one stays")
	t.dismiss()
	check(not s.damage_taken_mults.has(key) and not a.damage_taken_mults.has(key), "dismissed: no reduction left")


func test_the_bond_totem_works_solo_and_cleans_up_when_it_expires_or_is_freed() -> void:
	var s := _shaman(Vector3.ZERO, 0)
	var t := ShamanTotem.plant(s, &"bond", _bond_params(), s.global_position, 2.0)
	var hp := s.hp
	_bond_ticks(t, 2)
	check_eq(s.hp, hp, "alone: nothing to even out")
	check_near(float(s.damage_taken_mults.get(&"bond_totem:0", 0.0)), 0.8, 0.0001, "but the damage reduction")
	check(t.is_in_group(&"shaman_totems"), "it is a totem of the group")
	for i in 90:
		t.step(DT)
	check(t.dismissed, "expired after its duration")
	check(not s.damage_taken_mults.has(&"bond_totem:0"), "the reduction ended with it")
	# Freed with the tree: the key goes too.
	var t2 := _plant_bond(s)
	for i in 20:
		t2.step(DT)
	check(s.damage_taken_mults.has(&"bond_totem:0"), "reduction on")
	world.remove_child(t2)
	t2.free()
	check(not s.damage_taken_mults.has(&"bond_totem:0"), "freed: gone")


# --- Bond Totem: the talent script ---------------------------------------------------------------------

func test_the_bond_totem_rises_8_seconds_into_the_wave_then_every_25() -> void:
	var p := _shaman(Vector3(2, 0, 0))
	_stats(p)
	var b := _to_bond(p)
	check(b != null, "the capstone script runs")
	if b == null:
		return
	check(b.standing() == null, "no totem before a wave")
	_tick(p, 30.0, true)
	check(b.standing() == null, "the clock waits for a wave")
	b.begin_wave()
	_tick(p, 7.9, true)
	check(b.standing() == null, "not yet")
	_tick(p, 0.2, true)
	var t := b.standing()
	check(t != null, "the totem rises at 8 sec")
	if t == null:
		return
	check_eq([t.element, b.planted], [&"bond", 1], "a Bond Totem")
	check_eq(t.global_position, Vector3(2, 0, 0), "at the Shaman's feet")
	check_near(t.time_left(), 10.0 - 0.1, 0.15, "for 10 sec")
	check_eq([float(t.params["radius"]), float(t.params["equalize_pct"]), float(t.params["damage_taken_pct"])], [6.0, 10.0, 20.0], "the designed numbers")
	check(p.damage_taken_mults.has(&"bond_totem:0"), "the Shaman is covered")
	# It is gone after 10 sec; the next one comes 25 sec after the first.
	_tick(p, 10.0, true)
	check(b.standing() == null, "expired")
	check(not p.damage_taken_mults.has(&"bond_totem:0"), "the cover ended")
	_tick(p, 14.6, true)
	check_eq(b.planted, 1, "25 sec after the first one: not yet")
	_tick(p, 0.4, true)
	check_eq(b.planted, 2, "the second one rises")
	check(b.standing() != null, "standing")
	check(b.describe().begins_with("Bond Totem: "), "describe: %s" % b.describe())


func test_the_bond_totem_is_separate_from_totem_rite_and_a_new_one_replaces_the_old() -> void:
	var p := _shaman()
	_stats(p)
	var b := _to_bond(p)
	_enemy(Vector3(3, 0, 0))
	b.begin_wave()
	_tick(p, 8.1, true)
	var first := b.standing()
	check(first != null, "a Bond Totem stands")
	check(_cast(p, &"totem_rite"), "Totem Rite")
	check(first.is_active() and b.standing() == first, "the Rite did not replace the Bond Totem")
	check_eq(_fx_rite(p).standing().size(), 1, "the Rite totem stands too")
	p.abilities.set_cooldown(Db.get_ability(&"totem_rite"), 0.0)
	check(_cast(p, &"totem_rite"), "another Rite totem")
	check(first.is_active(), "still standing: a Rite cast never touches it")
	check(tree.get_nodes_in_group(&"shaman_totems").size() == 2, "one of each in the world")
	# A new Bond Totem replaces the last one of the script at once.
	b._left = 0.0
	_tick(p, 0.1, true)
	check_eq(b.planted, 2, "a second Bond Totem")
	check(first.dismissed, "the first one is gone")
	check(b.standing() != null and b.standing() != first, "the new one stands")


func test_the_bond_totem_timer_holds_while_down_and_wave_end_removes_the_totem() -> void:
	var p := _shaman()
	_stats(p)
	var b := _to_bond(p)
	var ally := _ally(1, Vector3(2, 0, 0))
	ally.hp = ally.max_hp() * 0.3
	b.begin_wave()
	_tick(p, 5.0, true)
	var left := b.time_left()
	_down(p)
	_tick(p, 20.0, true)
	check_near(b.time_left(), left, 0.0001, "the timer holds while the Shaman is down")
	check(b.standing() == null, "no totem rises for a downed Shaman")
	p.revive(1.0)
	_tick(p, left + 0.1, true)
	var t := b.standing()
	check(t != null, "it rises after the revive")
	# A standing totem keeps working while its Shaman is down.
	var before := _hp_ratio(ally)
	_down(p)
	_bond_ticks(t, 2)
	check(_hp_ratio(ally) == before, "alone in the circle with a downed Shaman: nothing to even out")
	check(ally.damage_taken_mults.has(&"bond_totem:0"), "the cover goes on (the totem outlives the Shaman's fall)")
	p.revive(1.0)
	# Wave end: the totem and the cover are gone, the clock stops.
	p.end_wave()
	check(b.standing() == null and t.dismissed, "wave end removes the totem")
	check(not ally.damage_taken_mults.has(&"bond_totem:0"), "and the cover")
	_tick(p, 60.0, true)
	check(b.standing() == null, "nothing between waves")
	check_near(b.time_left(), 8.0, 0.0001, "ready to start over")
	p.begin_wave()
	_tick(p, 8.1, true)
	check(b.standing() != null, "the next wave starts the clock again")


func test_taking_the_bond_totem_back_removes_the_totem() -> void:
	var p := _shaman()
	var b := _to_bond(p)
	b.begin_wave()
	_tick(p, 8.1, true)
	var t := b.standing()
	check(t != null and p.damage_taken_mults.has(&"bond_totem:0"), "the totem stands")
	check(p.talents.remove(BOND_ID), "the capstone is taken back")
	check(t.dismissed, "the totem is gone")
	check(not p.damage_taken_mults.has(&"bond_totem:0"), "and the cover")
	check(p.bonuses.script_for(BOND_ID) == null, "the script is gone")


func test_weathered_wood_lengthens_the_bond_totem() -> void:
	var p := _shaman()
	_add(p, &"shaman_wellspring_weathered_wood", 3)
	_add(p, &"shaman_wellspring_gentle_current", 3)
	_add(p, &"shaman_wellspring_elder_spirits", 3)
	_add(p, &"shaman_wellspring_deepening_rain", 3)
	_add(p, BOND_ID)
	var b := p.bonuses.script_for(BOND_ID) as ShamanWellspringBondTotem
	b.begin_wave()
	_tick(p, 8.1, true)
	var t := b.standing()
	check(t != null, "it stands")
	check_near(t.time_left(), 13.0 - 0.1, 0.15, "+30% duration (Weathered Wood 3/3): 13 sec")


func test_bond_totem_params_and_text() -> void:
	var def: Dictionary = Db.get_talent(BOND_ID).effects[0]
	check_eq(def.get("params"), {"interval": 25.0, "first_at": 8.0, "duration": 10.0, "radius": 6.0, "equalize_pct": 10.0, "tick": 0.5,
		"damage_taken_pct": 20.0}, "the params as designed")
	# The model of the Bond Totem exists (the class package drew it).
	var t := ShamanTotem.plant(_shaman(), &"bond", _bond_params(), Vector3.ZERO, 10.0)
	check(t.model != null, "a model")
	t.dismiss()
