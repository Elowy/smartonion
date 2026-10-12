extends TestCase
## Warlock talents (M5 Wave 2, talents_warlock.md): the three trees in Db, the bot paths of all
## three trees (TalentBot reaches each capstone at point 13) and the Affliction tree talent by
## talent through player.talents.add -> PlayerBonuses on a real Warlock: Curse of Agony (Agony
## from the hit's base amount, roll-up refresh, Shadow dot ticks, wave clear), Improved Drain
## Life, Shadow Mastery, Curse of Exhaustion, Malediction, Dark Harvest, Writhe in Agony (the
## rest of a curse is split, never copied), Death's Embrace and the Unstable Affliction
## capstone. Demonology: test_talents_warlock_demonology.gd; Destruction:
## test_talents_warlock_destruction.gd.
##
## Pseudo ability id &"warlock_afflictions" (BonusVocabulary.PSEUDO_IDS, read by
## WarlockMastery.affliction_params, cached until PlayerBonuses.changed / equipment.changed):
## BASE {"agony_pct": 0, "agony_duration": 6, "agony_spread": 0, "agony_spread_radius": 4,
## "slow": 0} – agony_pct = % of each weapon hit's base amount that becomes Agony (Curse of
## Agony "agony_pct_add"), agony_duration in s, agony_spread = enemies a dying host's Agony is
## split between (Writhe in Agony "agony_spread_add"), agony_spread_radius in m (x Area Size),
## slow = % slow of every affliction of the Warlock (Curse of Exhaustion "slow_add").

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const WFakes := preload("res://tests/talents_warlock_fakes.gd")
const DataTest := preload("res://tests/test_talent_data.gd")
const DT := 1.0 / 60.0
const LT := 1
const AGONY := WarlockAfflictions.AGONY
const UA_ID := &"warlock_affliction_unstable_affliction"

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 4711)
	RunState.set_start_level(31)
	world = EFakes.make_world(tree)
	EnemyGrid.mark_dirty()


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null
	EnemyGrid.mark_dirty()


# --- Helpers -----------------------------------------------------------------------------------

func _warlock(pos: Vector3 = Vector3.ZERO, index: int = 0) -> Player:
	return Fakes.spawn_player(world, index, &"warlock", pos)


func _enemy(pos: Vector3, hp: float = 1000.0) -> WFakes.DyingEnemy:
	return WFakes.spawn_enemy(world, pos, hp)


func _add(p: Player, name: String, n: int = 1) -> void:
	var id := StringName("warlock_affliction_" + name)
	for i in n:
		check(p.talents.add(id), "add %s: %s" % [id, p.talents.add_block_reason(id)])


func _remove(p: Player, name: String, n: int = 1) -> void:
	var id := StringName("warlock_affliction_" + name)
	for i in n:
		check(p.talents.remove(id), "remove %s: %s" % [id, p.talents.remove_block_reason(id)])


func _aff(p: Player) -> WarlockAfflictions:
	return WFakes.afflictions(p)


func _params(p: Player) -> Dictionary:
	return WFakes.mastery(p).affliction_params()


## A weapon hit of [param p] on [param e]: [param dealt] reported, [param base] its base amount.
func _hit(p: Player, e: Enemy, dealt: float, base: float, first: bool = true) -> void:
	p.on_hit_dealt(dealt, e, p.main_hand, false, false, first, base)


## Σ rate x left of every running Agony (the damage the curses still owe).
func _agony_owed(p: Player, enemies: Array) -> float:
	var t := 0.0
	for e: Variant in enemies:
		var a := _aff(p).get_affliction(AGONY, e as Node3D) if is_instance_valid(e) else null
		if a != null and not a.done:
			t += a.rate * maxf(0.0, a.left)
	return t


func _drain(p: Player) -> WarlockDrainLife:
	return p.abilities.effect_for(Db.get_ability(&"drain_life")) as WarlockDrainLife


## The 12 points that open the Affliction capstone, then the capstone.
func _to_capstone(p: Player) -> WarlockAfflictionUnstableAffliction:
	_add(p, "curse_of_agony", 3)
	_add(p, "improved_drain_life", 3)
	_add(p, "shadow_mastery", 3)
	_add(p, "curse_of_exhaustion", 3)
	_add(p, "unstable_affliction")
	return p.bonuses.script_for(UA_ID) as WarlockAfflictionUnstableAffliction


# --- Data and bots -----------------------------------------------------------------------------

func test_the_three_warlock_trees_are_in_db() -> void:
	var trees := Db.talent_trees_for(&"warlock")
	check_eq(trees.size(), 3, "three trees")
	if trees.size() != 3:
		return
	var ids: Array[StringName] = []
	for t in trees:
		ids.append(t.id)
		check_eq(DataTest.tree_problems(t), [] as Array[String], "%s passes the content contract" % t.id)
		check_eq(t.talents.size(), 9, "%s: nine talents" % t.id)
	check_eq(ids, [&"warlock_affliction", &"warlock_demonology", &"warlock_destruction"] as Array[StringName],
		"GDD 7.2 order")
	var aff := trees[0]
	check_eq(aff.get_talent(&"warlock_affliction_writhe_in_agony").prerequisite, &"warlock_affliction_curse_of_agony",
		"Writhe in Agony needs Curse of Agony")
	check_eq(aff.get_talent(&"warlock_affliction_dark_harvest").ability, &"drain_life", "Dark Harvest changes Drain Life")
	check(aff.get_talent(UA_ID).is_capstone(), "Unstable Affliction is the capstone")
	var demo := trees[1]
	check_eq(demo.get_talent(&"warlock_demonology_master_demonologist").prerequisite, &"warlock_demonology_unholy_power",
		"Master Demonologist needs Unholy Power")
	check_eq(demo.get_talent(&"warlock_demonology_wild_imps").ability, &"rain_of_fire", "Wild Imps change Rain of Fire")
	check(demo.get_talent(&"warlock_demonology_soul_link").is_capstone(), "Soul Link is the capstone")
	check_eq(demo.get_talent(&"warlock_demonology_fel_synergy").text_for_rank(3),
		"Your demons tend your party: every 5 sec the most wounded hero (you included) heals 4.5% of their Max HP.",
		"4.5 prints with its decimal")
	var dest := trees[2]
	check_eq(dest.get_talent(&"warlock_destruction_ruin").prerequisite, &"warlock_destruction_devastation",
		"Ruin needs Devastation")
	check_eq(dest.get_talent(&"warlock_destruction_shadowburn").ability, &"drain_life", "Shadowburn changes Drain Life")
	check(dest.get_talent(&"warlock_destruction_conflagrate").is_capstone(), "Conflagrate is the capstone")
	check_eq(aff.get_talent(&"warlock_affliction_curse_of_agony").text_for_rank(3),
		"Your weapon hits curse their target with Agony: 15% of the hit's damage as Shadow damage over 6 sec. Further hits add to the curse.",
		"rank text")


func test_bot_paths_reach_every_capstone_at_point_13() -> void:
	var paths: Array = [
		WFakes.times(&"warlock_affliction_curse_of_agony", 3) + WFakes.times(&"warlock_affliction_improved_drain_life", 3)
			+ WFakes.times(&"warlock_affliction_dark_harvest", 1) + WFakes.times(&"warlock_affliction_shadow_mastery", 3)
			+ WFakes.times(&"warlock_affliction_curse_of_exhaustion", 2) + WFakes.times(UA_ID, 1)
			+ WFakes.times(&"warlock_affliction_curse_of_exhaustion", 1) + WFakes.times(&"warlock_affliction_malediction", 2)
			+ WFakes.times(&"warlock_affliction_writhe_in_agony", 3) + WFakes.times(&"warlock_affliction_deaths_embrace", 3),
		WFakes.times(&"warlock_demonology_demonic_embrace", 3) + WFakes.times(&"warlock_demonology_improved_imp", 3)
			+ WFakes.times(&"warlock_demonology_wild_imps", 1) + WFakes.times(&"warlock_demonology_unholy_power", 3)
			+ WFakes.times(&"warlock_demonology_soul_harvest", 2) + WFakes.times(&"warlock_demonology_soul_link", 1)
			+ WFakes.times(&"warlock_demonology_soul_harvest", 1) + WFakes.times(&"warlock_demonology_demonic_aegis", 2)
			+ WFakes.times(&"warlock_demonology_master_demonologist", 3) + WFakes.times(&"warlock_demonology_fel_synergy", 3),
		WFakes.times(&"warlock_destruction_devastation", 3) + WFakes.times(&"warlock_destruction_emberstorm", 3)
			+ WFakes.times(&"warlock_destruction_shadowburn", 1) + WFakes.times(&"warlock_destruction_fire_and_brimstone", 3)
			+ WFakes.times(&"warlock_destruction_aftermath", 2) + WFakes.times(&"warlock_destruction_conflagrate", 1)
			+ WFakes.times(&"warlock_destruction_aftermath", 1) + WFakes.times(&"warlock_destruction_soul_leech", 2)
			+ WFakes.times(&"warlock_destruction_ruin", 3) + WFakes.times(&"warlock_destruction_burning_embers", 3),
	]
	var capstones: Array[StringName] = [UA_ID, &"warlock_demonology_soul_link", &"warlock_destruction_conflagrate"]
	for i in 3:
		var p := _warlock(Vector3(i * 6.0, 0, 0), i)
		var path := WFakes.bot_path(p, i)
		var want: Array[StringName] = []
		want.assign(paths[i])
		check_eq(path, want, "bot %d path (talents_warlock.md 5.4)" % i)
		check_eq(path.find(capstones[i]), 12, "bot %d: the capstone is point 13" % i)
		check_eq(path.size(), 22, "bot %d fills its tree" % i)
	var q := _warlock(Vector3(0, 0, 6), 3)
	check_eq(TalentBot.spend_all(q, 3), 22, "bot 4 wraps to Affliction and spends 22")
	check_eq(q.talents.tree_points(&"warlock_affliction"), 22, "all in Affliction")


# --- Curse of Agony ------------------------------------------------------------------------

func test_curse_of_agony_curses_from_the_base_amount_of_every_hit() -> void:
	var p := _warlock()
	var e := _enemy(Vector3(3, 0, 0))
	var f := _enemy(Vector3(3.5, 0, 0.5))
	check_eq(_params(p)["agony_pct"], 0.0, "neutral: no Agony")
	_hit(p, e, 10.0, 8.0)
	check(_aff(p) == null or not _aff(p).has(AGONY, e), "no talent: no Agony")
	_add(p, "curse_of_agony")
	check_eq(_params(p)["agony_pct"], 5.0, "rank 1: 5% (the cache was dropped on the talent change)")
	_add(p, "curse_of_agony", 2)
	check_eq(_params(p)["agony_pct"], 15.0, "rank 3: 15%")
	var state := RunState.rng.state
	_hit(p, e, 10.0, 8.0)
	_hit(p, f, 10.0, 8.0, false)  # a further enemy of the same attack (pierce / arc)
	var a := _aff(p).get_affliction(AGONY, e)
	check(a != null, "Agony on the target")
	if a == null:
		return
	check_near(a.rate, 8.0 * 0.15 / 6.0, 0.0001, "15% of the BASE amount (8, not the dealt 10) over 6 sec")
	check_eq(a.school, &"shadow", "Shadow")
	check(not a.target_bonus, "derived from a hit: target_bonus = false")
	check(_aff(p).has(AGONY, f), "every enemy a hit touches is cursed")
	check(e.get_node_or_null("WarlockAgonyMarker") != null, "thorn marker")
	check_eq(RunState.rng.state, state, "no RNG")
	WFakes.step(_aff(p), 0.5)
	check_eq(e.hits.size(), 1, "one tick after 0.5 sec")
	check_near(e.hits[0], 0.2 * 0.5, 0.0001, "0.1 per tick (Demonic Pact 0 at 0 Mastery)")
	check(e.attackers[0] == p, "kill credit to the Warlock")
	_remove(p, "curse_of_agony", 3)
	check_eq(_params(p)["agony_pct"], 0.0, "undone")
	var g := _enemy(Vector3(-3, 0, 0))
	_hit(p, g, 10.0, 8.0)
	check(not _aff(p).has(AGONY, g), "no new Agony without the talent")


func test_agony_rolls_the_rest_into_a_refresh_and_ticks_as_a_dot_once() -> void:
	var p := _warlock()
	_add(p, "curse_of_agony", 3)
	var e := _enemy(Vector3(3, 0, 0))
	_hit(p, e, 10.0, 8.0)  # 1.2 over 6 s
	WFakes.step(_aff(p), 3.0)
	var a := _aff(p).get_affliction(AGONY, e)
	check_near(a.left, 3.0, 0.02, "3 sec left")
	check_near(e.total(), 0.6, 0.001, "half dealt")
	_hit(p, e, 10.0, 8.0)  # +1.2
	check_near(a.left, 6.0, 0.0001, "the refresh restarts the curse")
	check_near(a.rate * a.left, 0.6 + 1.2, 0.02, "the rest (0.6) rolled into the new curse: nothing lost")
	p.stats.set_source(&"t", {Stats.MASTERY: 10.0})
	var before := e.hits.size()
	WFakes.step(_aff(p), 0.5)
	check_near(e.hits[before], a.rate * 0.5 * 1.2, 0.001, "Demonic Pact (+20%) once")
	check_near(p.outgoing_damage_mult(e, &"shadow", &"dot"), 1.2, 0.0001, "the multiplier of its ticks")
	WFakes.step(_aff(p), 6.0)
	check_near(e.total(), 0.6 + 1.8 * 1.2, 0.03, "every point of the curse dealt")
	check(not _aff(p).has(AGONY, e), "ran out")


func test_agony_keeps_ticking_while_downed_and_clears_on_waves() -> void:
	var p := _warlock()
	_add(p, "curse_of_agony", 3)
	var e := _enemy(Vector3(3, 0, 0))
	var other := _enemy(Vector3(3.5, 0, 0))
	_hit(p, e, 10.0, 8.0)
	p._go_down()
	check(p.downed, "down")
	WFakes.step(_aff(p), 1.0)
	check_eq(e.hits.size(), 2, "still ticking while the Warlock is down")
	_hit(p, other, 10.0, 8.0)
	check(not _aff(p).has(AGONY, other), "a downed hero lands no weapon hits")
	p.begin_wave()
	check(not _aff(p).has(AGONY, e), "wave start: cleared")
	check(not _aff(p).has(AGONY, other), "nothing spread")
	_hit(p, e, 10.0, 8.0)
	check(_aff(p).has(AGONY, e), "cursed again")
	p.end_wave()
	check(not _aff(p).has(AGONY, e), "wave end: cleared")


# --- Tier 1-4 ----------------------------------------------------------------------------------

func test_improved_drain_life_power_and_cooldown() -> void:
	var p := _warlock()
	var drain := Db.get_ability(&"drain_life")
	var base := p.abilities.params_for(drain)
	_add(p, "improved_drain_life", 3)
	var params := p.abilities.params_for(drain)
	check_near(float(params["power"]), float(base["power"]) * 1.18, 0.0001, "+6% power per rank (damage and healing)")
	check_near(float(params["cooldown"]), float(base["cooldown"]) * 0.88, 0.0001, "-4% cooldown per rank")
	check(WarlockDrainLife.tick_damage(p.stats, params) > WarlockDrainLife.tick_damage(p.stats, base) * 1.17, "bigger ticks")
	_remove(p, "improved_drain_life", 3)
	check_eq(p.abilities.params_for(drain), base, "undone")


func test_shadow_mastery_boosts_shadow_damage_and_agony() -> void:
	var p := _warlock()
	_add(p, "curse_of_agony", 3)
	_add(p, "shadow_mastery", 3)
	check_near(p.outgoing_damage_mult(null, &"shadow", &"ability"), 1.09, 0.0001, "+3% Shadow per rank")
	check_near(p.outgoing_damage_mult(null, &"fire", &"weapon"), 1.0, 0.0001, "not Fire")
	var e := _enemy(Vector3(3, 0, 0))
	_hit(p, e, 10.0, 8.0)
	WFakes.step(_aff(p), 0.5)
	check_near(e.hits[0], 0.1 * 1.09, 0.0001, "Agony's Shadow ticks once x 1.09")
	_remove(p, "shadow_mastery", 3)
	check_near(p.outgoing_damage_mult(null, &"shadow", &"ability"), 1.0, 0.0001, "undone")


func test_curse_of_exhaustion_slows_every_afflicted_enemy() -> void:
	var p := _warlock()
	_add(p, "curse_of_agony", 3)
	var e := _enemy(Vector3(3, 0, 0))
	var c := _enemy(Vector3(-3, 0, 0))
	_hit(p, e, 10.0, 8.0)
	check(not e.is_slowed(), "without the talent: no slow")
	for rank in range(1, 4):
		_add(p, "curse_of_exhaustion")
		check_eq(_params(p)["slow"], 10.0 * rank, "slow at rank %d" % rank)
		check_near(_aff(p).slow_pct(), 10.0 * rank, 0.0001, "the afflictions read it")
	_hit(p, e, 10.0, 8.0)
	check_eq(e.slow_pct, 30.0, "a fresh / refreshed Agony slows 30%")
	_aff(p).corrupt(c, 1.0, 4.0, 0, 0.0)
	check_eq(c.slow_pct, 30.0, "Corruption too")
	e.slow_left = 0.0
	c.slow_left = 0.0
	WFakes.step(_aff(p), 0.5)
	check(e.is_slowed() and c.is_slowed(), "re-applied after each tick")
	check_near(e.slow_left, WarlockAfflictions.TICK + WarlockAfflictions.SLOW_LINGER, 0.001, "until after the next tick")
	_remove(p, "curse_of_exhaustion", 3)
	e.slow_left = 0.0
	WFakes.step(_aff(p), 0.5)
	check(not e.is_slowed(), "undone")


func test_malediction_and_deaths_embrace_damage() -> void:
	var p := _warlock()
	_add(p, "curse_of_agony", 3)
	_add(p, "improved_drain_life", 3)
	_add(p, "malediction", 2)
	check_near(p.bonuses.damage_mult(null, &"shadow", &"dot"), 1.12, 0.0001, "+6% DoT damage per rank")
	check_near(p.bonuses.damage_mult(null, &"shadow", &"ability"), 1.0, 0.0001, "only DoTs")
	_add(p, "shadow_mastery", 1)
	_add(p, "deaths_embrace", 3)
	var low := _enemy(Vector3(3, 0, 0))
	low.hp = 300.0
	var high := _enemy(Vector3(-3, 0, 0))
	check_near(p.bonuses.damage_mult(low, &"fire", &"weapon"), 1.15, 0.0001, "+5% per rank below 35% health")
	check_near(p.bonuses.damage_mult(high, &"fire", &"weapon"), 1.0, 0.0001, "not above")
	check_near(p.bonuses.damage_mult(low, &"fire", &"dot"), 1.27, 0.0001, "adds up with Malediction")
	_remove(p, "deaths_embrace", 3)
	check_near(p.bonuses.damage_mult(low, &"fire", &"weapon"), 1.0, 0.0001, "undone")
	check_near(p.bonuses.damage_mult(low, &"fire", &"dot"), 1.12, 0.0001, "Malediction still counts")
	_remove(p, "shadow_mastery", 1)
	_remove(p, "malediction", 2)
	check_near(p.bonuses.damage_mult(null, &"shadow", &"dot"), 1.0, 0.0001, "Malediction undone: Shadow DoTs")
	check_near(p.bonuses.damage_mult(low, &"fire", &"dot"), 1.0, 0.0001, "and every other DoT")


# --- Dark Harvest ------------------------------------------------------------------------------

func test_dark_harvest_drains_every_afflicted_enemy_in_range() -> void:
	var p := _warlock()
	var a := _enemy(Vector3(2, 0, 0))
	var b := _enemy(Vector3(3, 0, 1))
	var c := _enemy(Vector3(-3, 0, 0))
	var d := _enemy(Vector3(0, 0, 4))
	var far := _enemy(Vector3(12, 0, 0))
	var aff := WarlockAfflictions.of(p)
	for e in [b, c, far]:
		aff.dread(e as Enemy, 0.0, 30.0)
	var effect := _drain(p)
	check(p.abilities.try_cast(LT), "cast without the modifier")
	WFakes.step_abilities(p, 2.1)
	check(b.hits.is_empty() and c.hits.is_empty(), "plain Drain Life drains its target only")
	check_eq(effect.harvest_hits, 0, "no harvest")
	_add(p, "curse_of_agony", 3)
	_add(p, "improved_drain_life", 3)
	_add(p, "dark_harvest")
	var params := p.abilities.params_for(Db.get_ability(&"drain_life"))
	check_eq(params["harvest_pct"], 25.0, "harvest_pct 0 -> 25")
	check_eq(params["harvest_targets"], 6, "up to 6")
	p.begin_wave()
	p.hp = 2.0
	var per_tick := WarlockDrainLife.tick_damage(p.stats, params)
	var a_before := a.hits.size()
	var state := RunState.rng.state
	check(p.abilities.try_cast(LT), "cast with Dark Harvest")
	check(effect.target == a, "the nearest enemy is drained")
	WFakes.step_abilities(p, 2.1)
	check_eq(a.hits.size() - a_before, 5, "5 ticks on the target")
	check_eq(b.hits.size(), 5, "B (afflicted) harvested every tick")
	check_eq(c.hits.size(), 5, "C (afflicted) harvested every tick")
	check_near(b.hits[0], per_tick * 0.25, 0.0001, "25% of a tick")
	check(d.hits.is_empty(), "D carries no affliction: spared")
	check(far.hits.is_empty(), "out of range: spared")
	check_eq(effect.harvest_hits, 10, "stats")
	check_near(effect.harvest_total, per_tick * 0.25 * 10.0, 0.001, "harvest total")
	check_near(p.hp, minf(p.max_hp(), 2.0 + per_tick * 5.0 + per_tick * 0.25 * 10.0), 0.01, "the harvest heals too")
	check_eq(RunState.rng.state, state, "no RNG")


func test_dark_harvest_cap_and_bot_rule() -> void:
	var p := _warlock()
	_add(p, "curse_of_agony", 3)
	_add(p, "improved_drain_life", 3)
	var target := _enemy(Vector3(1.5, 0, 0))
	var aff := WarlockAfflictions.of(p)
	var cursed: Array[WFakes.DyingEnemy] = []
	for i in 2:
		var e := _enemy(Vector3(-2.0 - i, 0, 1.0))
		aff.dread(e, 0.0, 30.0)
		cursed.append(e)
	var slot := p.abilities.slots[LT]
	var effect := _drain(p)
	check(not effect.wants_auto_cast(p.abilities.build_context(slot)), "full HP, no modifier: no")
	_add(p, "dark_harvest")
	check(not effect.wants_auto_cast(p.abilities.build_context(slot)), "two afflicted enemies: not yet")
	var third := _enemy(Vector3(-4, 0, 1.0))
	aff.dread(third, 0.0, 30.0)
	cursed.append(third)
	check(effect.wants_auto_cast(p.abilities.build_context(slot)), "three afflicted enemies in range: the bot drains at full HP")
	for i in 5:
		var e := _enemy(Vector3(0.5 * i, 0, -2.5))
		aff.dread(e, 0.0, 30.0)
		cursed.append(e)
	check(p.abilities.try_cast(LT), "cast")
	WFakes.step_abilities(p, 0.41)
	check_eq(effect.harvest_hits, 6, "eight afflicted enemies in range, six harvested per tick")
	check(target.hits.size() == 1, "the drained target is not harvested on top")
	WFakes.step_abilities(p, 2.0)
	check(not effect.is_channeling(), "completed")
	# Taken back: harvest_pct is neutral again; a channel drains its target only.
	_remove(p, "dark_harvest")
	var drain := Db.get_ability(&"drain_life")
	check_eq(p.abilities.params_for(drain)["harvest_pct"], 0.0, "undone: harvest_pct 0")
	check(not effect.wants_auto_cast(p.abilities.build_context(slot)), "the bot rule is gone too")
	var cursed_hits: Array[int] = []
	for e in cursed:
		cursed_hits.append(e.hits.size())
	p.abilities.set_cooldown(drain, 0.0)
	check(p.abilities.try_cast(LT), "cast without Dark Harvest")
	WFakes.step_abilities(p, 2.1)
	check(not effect.is_channeling(), "completed")
	check_eq(effect.harvest_hits, 0, "nothing harvested")
	check_near(effect.harvest_total, 0.0, 0.0001, "no harvest damage")
	for i in cursed.size():
		check_eq(cursed[i].hits.size(), cursed_hits[i], "afflicted enemy %d spared" % i)


# --- Writhe in Agony ---------------------------------------------------------------------------

func test_writhe_in_agony_splits_the_rest_of_the_curse() -> void:
	var p := _warlock()
	_add(p, "curse_of_agony", 3)
	_add(p, "improved_drain_life", 3)
	_add(p, "shadow_mastery", 3)
	_add(p, "writhe_in_agony", 2)
	check_eq(_params(p)["agony_spread"], 2.0, "two enemies at rank 2")
	var host := _enemy(Vector3(5, 0, 0))
	var a := _enemy(Vector3(6, 0, 0))
	var b := _enemy(Vector3(5, 0, 2))
	var c := _enemy(Vector3(3.5, 0, -1))
	var out := _enemy(Vector3(5, 0, 4.6))
	_hit(p, host, 50.0, 40.0)  # 6 over 6 s
	WFakes.step(_aff(p), 2.0)
	var owed := _agony_owed(p, [host])
	check_near(owed, 4.0, 0.05, "4 left on the host")
	host.die_now(null)
	WFakes.step(_aff(p), DT)
	var got: Array = [a, b, c].filter(func(x: Enemy) -> bool: return _aff(p).has(AGONY, x))
	check_eq(got.size(), 2, "split between the two nearest without Agony")
	check(_aff(p).has(AGONY, a) and _aff(p).has(AGONY, c), "A (1 m) and C (1.8 m), not B (2 m)")
	check(not _aff(p).has(AGONY, out), "not beyond 4 m")
	var aa := _aff(p).get_affliction(AGONY, a)
	check_near(aa.rate, 0.5, 0.01, "rate / 2 each")
	check_near(aa.left, 4.0, 0.05, "with the time the host had left")
	check(not aa.target_bonus, "still derived")
	check_near(_agony_owed(p, [a, b, c, out]), owed, 0.05, "the remaining damage is split, never copied")
	var before := _agony_owed(p, [a, b, c, out])
	a.die_now(null)
	WFakes.step(_aff(p), DT)
	check(_aff(p).has(AGONY, b), "A's rest goes on to B")
	check(_agony_owed(p, [b, c, out]) <= before + 0.0001, "a chain of deaths never grows the total")


func test_writhe_in_agony_rank_one_and_despawn() -> void:
	var p := _warlock()
	_add(p, "curse_of_agony", 3)
	_add(p, "improved_drain_life", 3)
	_add(p, "shadow_mastery", 3)
	_add(p, "writhe_in_agony")
	var host := _enemy(Vector3(5, 0, 0))
	var a := _enemy(Vector3(6, 0, 0))
	var b := _enemy(Vector3(5, 0, 1.5))
	_hit(p, host, 50.0, 40.0)
	host.die_now(p)
	WFakes.step(_aff(p), DT)
	check(_aff(p).has(AGONY, a) and not _aff(p).has(AGONY, b), "rank 1: one enemy")
	check_near(_aff(p).get_affliction(AGONY, a).rate, 1.0, 0.01, "the whole rest")
	var gone := _enemy(Vector3(-5, 0, 0))
	var near := _enemy(Vector3(-6, 0, 0))
	_hit(p, gone, 50.0, 40.0)
	gone.despawn()
	WFakes.step(_aff(p), DT)
	check(not _aff(p).has(AGONY, near), "a despawned host (wave end) spreads nothing")
	# Taken back: agony_spread is neutral again; a dying host's Agony dies with it.
	_remove(p, "writhe_in_agony")
	check_eq(_params(p)["agony_spread"], 0.0, "undone: agony_spread 0")
	var host2 := _enemy(Vector3(0, 0, 8))
	var n1 := _enemy(Vector3(1, 0, 8))
	var n2 := _enemy(Vector3(0, 0, 9.5))
	_hit(p, host2, 50.0, 40.0)
	check(_aff(p).has(AGONY, host2), "Curse of Agony still curses")
	host2.die_now(p)
	WFakes.step(_aff(p), DT)
	check(not _aff(p).has(AGONY, n1) and not _aff(p).has(AGONY, n2), "the neighbours stay clean")
	check(n1.hits.is_empty() and n2.hits.is_empty(), "and take nothing")


# --- Unstable Affliction -----------------------------------------------------------------------

func test_unstable_affliction_bursts_on_any_killers_kill() -> void:
	var p := _warlock()
	var ua := _to_capstone(p)
	check(ua != null, "the capstone script runs")
	if ua == null:
		return
	check_eq(_aff(p).afflicted_died.get_connections().size(), 1, "listens to afflicted_died")
	var other := Fakes.spawn_player(world, 1, &"warrior", Vector3(-6, 0, 0))
	var host := _enemy(Vector3(4, 0, 0))
	var near := _enemy(Vector3(5.5, 0, 0))
	var far := _enemy(Vector3(9.5, 0, 0))
	_aff(p).dread(host, 0.0, 30.0)
	var state := RunState.rng.state
	host.take_damage(5000.0, false, other)
	check(host.is_dead(), "killed by another hero")
	check_eq(ua.pending(), 1, "queued")
	check(near.hits.is_empty(), "nothing is dealt inside the died chain")
	p.bonuses.tick(DT)
	check_eq(ua.bursts, 1, "burst on the next tick")
	check_eq(near.hits.size(), 1, "the neighbour within 3 m is hit")
	check_near(near.hits[0], ua.burst_damage() * p.outgoing_damage_mult(near, &"shadow", &"ability"), 0.0001,
		"Shadow ability damage from the Warlock's stats")
	check(near.attackers[0] == p, "the Warlock's damage")
	check(near.is_stunned(), "stunned")
	check_near(near.stun_left, 1.0, 0.0001, "for 1 sec")
	check(far.hits.is_empty() and far.stun_calls == 0, "an enemy 5.5 m away is untouched")
	check_eq(RunState.rng.state, state, "no RNG")
	var clean := _enemy(Vector3(5, 0, 1))
	clean.die_now(other)
	check_eq(ua.pending(), 0, "a clean enemy's death: nothing")
	var nobody := _enemy(Vector3(5, 0, -1))
	_aff(p).corrupt(nobody, 0.1, 8.0, 0, 0.0)
	nobody.die_now(null)
	check_eq(ua.pending(), 1, "a death without a killer counts too")


func test_unstable_affliction_stun_memory_chain_and_cap() -> void:
	var p := _warlock()
	var ua := _to_capstone(p)
	var near := _enemy(Vector3(1, 0, 4))
	for i in 2:
		var host := _enemy(Vector3(0, 0, 4))
		_aff(p).dread(host, 0.0, 30.0)
		host.die_now(null)
		p.bonuses.tick(DT)
	check_eq(near.hits.size(), 2, "two bursts hit it")
	check_eq(near.stun_calls, 1, "stunned once: each enemy at most once every 4 sec")
	check(ua.stun_locked(near), "locked")
	WFakes.step_bonuses(p, 4.0)
	check(not ua.stun_locked(near), "4 sec later")
	var host2 := _enemy(Vector3(0, 0, 4))
	_aff(p).dread(host2, 0.0, 30.0)
	host2.die_now(null)
	p.bonuses.tick(DT)
	check_eq(near.stun_calls, 2, "stunned again")
	# Chain: a burst kills an afflicted neighbour, which bursts on the following tick.
	var first := _enemy(Vector3(-10, 0, 0))
	var weak := _enemy(Vector3(-8, 0, 0), 0.5)
	var beyond := _enemy(Vector3(-6, 0, 0))
	_aff(p).dread(first, 0.0, 30.0)
	_aff(p).dread(weak, 0.0, 30.0)
	first.die_now(null)
	var bursts := ua.bursts
	p.bonuses.tick(DT)
	check(weak.is_dead(), "the burst killed the afflicted neighbour")
	check(beyond.hits.is_empty(), "not reached by the first burst")
	check_eq(ua.pending(), 1, "its burst waits for the next tick")
	p.bonuses.tick(DT)
	check_eq(ua.bursts, bursts + 2, "chain reaction, one link per tick")
	check_eq(beyond.hits.size(), 1, "the second link reaches further")
	# At most max_per_tick (4) bursts per tick.
	for i in 6:
		var e := _enemy(Vector3(20.0 + 10.0 * i, 0, 20))
		_aff(p).dread(e, 0.0, 30.0)
		e.die_now(null)
	check_eq(ua.pending(), 6, "six queued")
	p.bonuses.tick(DT)
	check_eq(ua.pending(), 2, "four per tick")
	p.bonuses.tick(DT)
	check_eq(ua.pending(), 0, "the rest on the next tick")


func test_unstable_affliction_while_downed_waves_and_teardown() -> void:
	var p := _warlock()
	var ua := _to_capstone(p)
	var near := _enemy(Vector3(1, 0, 4))
	p._go_down()
	var host := _enemy(Vector3(0, 0, 4))
	_aff(p).dread(host, 0.0, 30.0)
	host.die_now(null)
	p.bonuses.tick(DT)
	check_eq(near.hits.size(), 1, "bursts while the Warlock is down")
	var h2 := _enemy(Vector3(0, 0, 4))
	_aff(p).dread(h2, 0.0, 30.0)
	h2.die_now(null)
	check_eq(ua.pending(), 1, "queued")
	p.begin_wave()
	check_eq(ua.pending(), 0, "wave start clears the queue")
	check(not ua.stun_locked(near), "and the stun memory")
	check(p.bonuses.script_for(UA_ID) == ua, "the same instance across the wave start")
	var h3 := _enemy(Vector3(0, 0, 4))
	_aff(p).dread(h3, 0.0, 30.0)
	h3.die_now(null)
	p.end_wave()
	check_eq(ua.pending(), 0, "wave end clears it too")
	RunState.add_gold(500)
	check(p.talents.try_reset(0), "Reset Talents")
	check(p.bonuses.script_for(UA_ID) == null and p.bonuses.scripts().is_empty(), "the capstone is gone")
	check(_aff(p).afflicted_died.get_connections().is_empty(), "teardown disconnected the signal")
	var h4 := _enemy(Vector3(0, 0, 4))
	_aff(p).dread(h4, 0.0, 30.0)
	h4.die_now(null)
	check_eq(ua.pending(), 0, "no state left")
