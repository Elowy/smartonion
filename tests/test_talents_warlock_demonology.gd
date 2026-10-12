extends TestCase
## Warlock Demonology talents (M5 Wave 2, talents_warlock.md §2) through player.talents.add ->
## PlayerBonuses on a real Warlock: Demonic Embrace, Improved Imp (pseudo id warlock_imp),
## Unholy Power, Soul Harvest (ClassResource bonus on top of Soulbinder's Sash's private
## shard rule), Demonic Aegis, the Wild Imps modifier (Rain of Fire's new neutral params
## wild_imps / wild_imp_duration / wild_imp_power / wild_imp_max and WarlockImp.spawn_wild),
## Master Demonologist, Fel Synergy (periodic heal of the most wounded hero) and the Soul Link
## capstone (data only). Bot paths: test_talents_warlock.gd.

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const WFakes := preload("res://tests/talents_warlock_fakes.gd")
const DT := 1.0 / 60.0
const RT := 0

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 515)
	RunState.set_start_level(31)
	world = EFakes.make_world(tree)
	EnemyGrid.mark_dirty()


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null
	EnemyGrid.mark_dirty()


func _warlock(pos: Vector3 = Vector3.ZERO, index: int = 0) -> Player:
	return Fakes.spawn_player(world, index, &"warlock", pos)


func _enemy(pos: Vector3, hp: float = 1000.0) -> WFakes.DyingEnemy:
	return WFakes.spawn_enemy(world, pos, hp)


func _add(p: Player, name: String, n: int = 1) -> void:
	var id := StringName("warlock_demonology_" + name)
	for i in n:
		check(p.talents.add(id), "add %s: %s" % [id, p.talents.add_block_reason(id)])


func _remove(p: Player, name: String, n: int = 1) -> void:
	var id := StringName("warlock_demonology_" + name)
	for i in n:
		check(p.talents.remove(id), "remove %s: %s" % [id, p.talents.remove_block_reason(id)])


func _rain(p: Player) -> WarlockRainOfFire:
	return p.abilities.effect_for(Db.get_ability(&"rain_of_fire")) as WarlockRainOfFire


## Four enemies close together around (6, 0, 0): a Rain of Fire cluster.
func _cluster() -> Array[WFakes.DyingEnemy]:
	var out: Array[WFakes.DyingEnemy] = []
	for i in 4:
		out.append(_enemy(Vector3(6.0 + 0.6 * i, 0, 0.5 * (i % 2))))
	return out


func _sash() -> ItemInstance:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	return ItemGenerator.from_unique(Db.get_unique(&"soulbinders_sash"), 1, false, rng)


## HP a fresh melee hit of 10 takes off [param p] (full HP before, no i-frames).
func _hit_loss(p: Player) -> float:
	p.hp = p.max_hp()
	p.invulnerable_left = 0.0
	var before := p.hp
	p.take_damage(10.0, CombatMath.KIND_MELEE, null)
	return before - p.hp


# --- Tier 1-4 ----------------------------------------------------------------------------------

func test_demonic_embrace_adds_stamina() -> void:
	var p := _warlock()
	var stamina := p.stats.get_raw(Stats.STAMINA)
	var hp := p.max_hp()
	_add(p, "demonic_embrace", 3)
	check_eq(p.stats.get_raw(Stats.STAMINA), stamina + 9.0, "+3 Stamina per rank")
	check_near(p.max_hp(), hp + 9.0, 0.0001, "+9 Max HP")
	_remove(p, "demonic_embrace", 3)
	check_eq(p.stats.get_raw(Stats.STAMINA), stamina, "undone")


func test_improved_imp_reaches_the_imp_and_its_bolts() -> void:
	var p := _warlock()
	var imp := WFakes.mastery(p).ensure_imp()
	check(imp != null, "the permanent Imp")
	var base := imp.current_params()
	check_eq(base["damage_bonus"], 0.0, "neutral")
	_add(p, "improved_imp", 3)
	var params := imp.current_params()
	check_eq(params["damage_bonus"], 15.0, "+5% per rank through the pseudo id warlock_imp")
	check_near(WarlockImp.bolt_damage(p.stats, params), WarlockImp.bolt_damage(p.stats, base) * 1.15, 0.0001,
		"bolts deal 15% more")
	var e := _enemy(imp.global_position + Vector3(0, 0, -4))
	check(imp.try_shoot(), "shoots")
	check_near(imp.last_bolt.damage, WarlockImp.bolt_damage(p.stats, params), 0.0001, "read on every bolt")
	check(e != null, "a target")
	_remove(p, "improved_imp", 3)
	check_eq(imp.current_params()["damage_bonus"], 0.0, "undone")


func test_unholy_power_and_soul_link_pet_damage() -> void:
	var p := _warlock()
	_add(p, "demonic_embrace", 3)
	_add(p, "unholy_power", 3)
	check_near(p.bonuses.damage_mult(null, &"fire", &"pet"), 1.09, 0.0001, "+3% pet damage per rank")
	check_near(p.bonuses.damage_mult(null, &"shadow", &"dot"), 1.0, 0.0001, "pets only")
	p.stats.set_source(&"t", {Stats.MASTERY: 10.0})
	check_near(p.outgoing_damage_mult(null, &"fire", &"pet"), 1.09 * 1.2, 0.0001, "multiplies with Demonic Pact")
	_remove(p, "unholy_power", 3)
	check_near(p.bonuses.damage_mult(null, &"fire", &"pet"), 1.0, 0.0001, "undone")


func test_soul_harvest_shortens_the_shard_rule_also_with_the_sash() -> void:
	var p := _warlock()
	var m := WFakes.mastery(p)
	var res := WFakes.shards(p)
	m.tick(DT)
	check_eq(m.kills_per_shard(), 12, "12 kills per shard")
	_add(p, "demonic_embrace", 3)
	for rank in range(1, 4):
		_add(p, "soul_harvest")
		check_eq(m.kills_per_shard(), 12 - rank, "rank %d" % rank)
	check_eq(res.bonus, {"gain_per_kills_add": -3.0}, "ClassResource.set_bonus")
	p.begin_wave()
	check_eq(res.value, 1.0, "one shard at wave start")
	for i in 8:
		p.abilities.on_kill(null)
	check_eq(res.value, 1.0, "8 kills: nothing yet")
	p.abilities.on_kill(null)
	check_eq(res.value, 2.0, "the 9th kill gives a shard")
	var sash := _sash()
	check(p.equipment.equip(sash), "Soulbinder's Sash")
	m.tick(DT)
	check_eq(res.data.gain_per_kills, 8, "the sash's private shard rule")
	check_eq(m.kills_per_shard(), 5, "the talent applies on top of it (8 - 3)")
	RunState.add_gold(500)
	check(p.talents.try_reset(0), "Reset Talents (the wave start made the points permanent)")
	check_eq(m.kills_per_shard(), 8, "undone: the sash's rule alone")
	check_eq(res.bonus, {}, "no bonus left")
	check_eq(Db.get_class_data(&"warlock").resources[0].gain_per_kills, 12, "shared data untouched")


func test_demonic_aegis_and_soul_link_reduce_damage_taken() -> void:
	var p := _warlock()
	var plain := _hit_loss(p)
	check(plain > 0.0, "a hit lands")
	_add(p, "demonic_embrace", 3)
	_add(p, "improved_imp", 3)
	_add(p, "demonic_aegis", 2)
	check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 0.94, 0.0001, "-3% per rank")
	check_near(_hit_loss(p), plain * 0.94, 0.001, "a real hit")
	_add(p, "unholy_power", 3)
	_add(p, "soul_harvest", 1)
	check_eq(p.talents.add_block_reason(&"warlock_demonology_soul_link"), "", "12 points: the capstone opens")
	_add(p, "soul_link")
	check(p.bonuses.scripts().is_empty(), "Soul Link is data only")
	check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_PROJECTILE, null), 0.74, 0.0001, "-20% more (additive: -26%)")
	check_near(_hit_loss(p), plain * 0.74, 0.001, "a real hit")
	check_near(p.bonuses.damage_mult(null, &"fire", &"pet"), 1.39, 0.0001, "pets +30% (+9% Unholy Power)")
	check_near(p.bonuses.damage_mult(null, &"fire", &"weapon"), 1.0, 0.0001, "the Warlock's own damage unchanged")
	p.begin_wave()
	p._go_down()
	p.begin_wave()
	check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_AOE, null), 0.74, 0.0001, "nothing to reset across waves / downs")
	RunState.add_gold(500)
	check(p.talents.try_reset(0), "Reset Talents")
	check_near(p.bonuses.damage_taken_mult(CombatMath.KIND_MELEE, null), 1.0, 0.0001, "undone")
	check_near(p.bonuses.damage_mult(null, &"fire", &"pet"), 1.0, 0.0001, "undone")


func test_master_demonologist_needs_unholy_power_and_feeds_demonic_pact() -> void:
	var p := _warlock()
	var m := WFakes.mastery(p)
	_add(p, "demonic_embrace", 3)
	_add(p, "improved_imp", 3)
	_add(p, "unholy_power", 2)
	_add(p, "soul_harvest", 3)
	check_eq(p.talents.add_block_reason(&"warlock_demonology_master_demonologist"), "Requires Unholy Power", "prerequisite")
	_add(p, "unholy_power")
	_add(p, "master_demonologist", 3)
	check_eq(p.stats.get_raw(Stats.MASTERY), 12.0, "+4 Mastery per rank")
	check_near(m.pact_mult(), 1.24, 0.0001, "Demonic Pact +24% DoT / pet damage")
	check_near(p.outgoing_damage_mult(null, &"shadow", &"dot"), 1.24, 0.0001, "on DoTs")
	_remove(p, "master_demonologist", 3)
	check_near(m.pact_mult(), 1.0, 0.0001, "undone")


func test_fel_synergy_heals_the_most_wounded_hero() -> void:
	var p := _warlock()
	var ally := Fakes.spawn_player(world, 1, &"warrior", Vector3(20, 0, 0))
	Enemy.invalidate_player_cache()
	_add(p, "demonic_embrace", 3)
	_add(p, "improved_imp", 3)
	_add(p, "unholy_power", 3)
	_add(p, "fel_synergy", 3)
	ally.hp = ally.max_hp() * 0.5
	p.hp = p.max_hp() * 0.8
	var before := ally.hp
	var state := RunState.rng.state
	WFakes.step(p.procs, 4.9)
	check_eq(ally.hp, before, "not before 5 sec")
	WFakes.step(p.procs, 0.2)
	check_near(ally.hp, before + ally.max_hp() * 0.045, 0.001, "4.5% of the healed hero's Max HP (anywhere)")
	check_near(p.hp, p.max_hp() * 0.8, 0.001, "only the most wounded hero")
	check_eq(RunState.rng.state, state, "no RNG at 100%")
	ally.hp = ally.max_hp()
	WFakes.step(p.procs, 5.0)
	check_near(p.hp, p.max_hp() * 0.8 + p.max_hp() * 0.045, 0.001, "then the Warlock itself")
	p._go_down()
	ally.hp = ally.max_hp() * 0.5
	WFakes.step(p.procs, 10.0)
	check_near(ally.hp, ally.max_hp() * 0.5, 0.001, "not while the Warlock is down")
	_remove(p, "fel_synergy", 3)
	check_eq(p.procs.fire_count(&"warlock_demonology_fel_synergy"), 0, "the proc is gone")


# --- Wild Imps ---------------------------------------------------------------------------------

func test_wild_imps_join_every_rain_of_fire() -> void:
	var p := _warlock()
	var permanent := WFakes.mastery(p).ensure_imp()
	_cluster()
	var rain := Db.get_ability(&"rain_of_fire")
	var base := p.abilities.params_for(rain)
	check_eq(base["wild_imps"], 0, "neutral: no Wild Imps")
	WFakes.shards(p).set_value(5.0)
	check(p.abilities.try_cast(RT), "plain Rain of Fire")
	check(_rain(p).wild_imps().is_empty(), "no imps without the modifier")
	_add(p, "demonic_embrace", 3)
	_add(p, "improved_imp", 3)
	_add(p, "wild_imps")
	var params := p.abilities.params_for(rain)
	check_eq(params["wild_imps"], 2.0, "wild_imps 0 -> 2")
	check(params["wild_imp_duration"] == 6.0 and params["wild_imp_power"] == 50.0 and params["wild_imp_max"] == 4,
		"6 sec, 50%, at most 4")
	for a in tree.get_nodes_in_group(&"ability_areas"):
		a.free()
	check(p.abilities.try_cast(RT), "cast with Wild Imps")
	var imps := _rain(p).wild_imps()
	check_eq(imps.size(), 2, "two Wild Imps")
	if imps.size() != 2:
		return
	for imp in imps:
		check(imp.is_wild() and imp.is_inside_tree(), "a wild imp in the world")
		check_near(imp.lifetime, 6.0, 0.0001, "for 6 sec")
		check_near(imp.power_mult, 0.5, 0.0001, "at 50% power")
		check(imp != permanent, "never the Mastery's Imp")
	check(imps[0].orbit_slot != imps[1].orbit_slot, "each on its own spot")
	check(WFakes.mastery(p).imp == permanent and not permanent.is_wild(), "the permanent Imp stays")
	var imp_params := imps[0].current_params()
	check_eq(imp_params["damage_bonus"], 15.0, "Improved Imp applies to them too")
	check(imps[0].try_shoot(), "a wild imp shoots")
	check_near(imps[0].last_bolt.damage, WarlockImp.bolt_damage(p.stats, imp_params) * 0.5, 0.0001, "half an Imp bolt")
	for a in tree.get_nodes_in_group(&"ability_areas"):
		a.free()
	check(p.abilities.try_cast(RT), "second cast")
	for a in tree.get_nodes_in_group(&"ability_areas"):
		a.free()
	check(p.abilities.try_cast(RT), "third cast")
	var now := _rain(p).wild_imps()
	check_eq(now.size(), 4, "at most 4 at once")
	check(imps[0].is_queued_for_deletion() and imps[1].is_queued_for_deletion(), "the oldest left first")


func test_wild_imps_expire_and_leave_with_the_wave() -> void:
	var p := _warlock()
	_cluster()
	_add(p, "demonic_embrace", 3)
	_add(p, "improved_imp", 3)
	_add(p, "wild_imps")
	WFakes.shards(p).set_value(5.0)
	check(p.abilities.try_cast(RT), "cast")
	var imps := _rain(p).wild_imps()
	check_eq(imps.size(), 2, "two")
	WFakes.step(imps[0], 5.9)
	check(not imps[0].is_queued_for_deletion(), "alive at 5.9 sec")
	WFakes.step(imps[0], 0.2)
	check(imps[0].is_queued_for_deletion(), "gone after 6 sec")
	check_eq(_rain(p).wild_imps().size(), 1, "one left")
	p._go_down()
	WFakes.step(imps[1], 0.5)
	check(imps[1].is_hidden(), "hides while the Warlock is down")
	check_near(imps[1].lifetime, 5.5, 0.01, "and its time still runs")
	p.begin_wave()
	check(p.abilities.try_cast(RT), "cast again")
	check_eq(_rain(p).wild_imps().size(), 2, "two new imps")
	var last := _rain(p).wild_imps()
	p.end_wave()
	check(_rain(p).wild_imps().is_empty(), "wave end: dismissed")
	check(last[0].is_queued_for_deletion() and last[1].is_queued_for_deletion(), "freed")
	check(WFakes.mastery(p).has_imp() or WFakes.mastery(p).imp == null, "the Mastery's Imp is untouched")
