extends TestCase
## Mage ability Blizzard (GDD 3.2): targeting the densest cluster, the frost area (ticks,
## slow, duration), Mana cost, the Frostweave Cowl mod and the bots' decision.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 32)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


func _mage() -> Player:
	var p := Fakes.spawn_player(world, 0, &"mage", Vector3.ZERO)
	p.abilities._physics_process(DT)
	return p


## [param count] enemies packed around [param center].
func _cluster(center: Vector3, count: int) -> Array[Fakes.FakeEnemy]:
	var out: Array[Fakes.FakeEnemy] = []
	for i in count:
		var a := TAU * float(i) / float(maxi(1, count))
		out.append(Fakes.spawn_enemy(world, center + Vector3(cos(a), 0.0, sin(a)) * 0.8))
	EnemyGrid.mark_dirty()
	return out


func _areas() -> Array[AbilityArea]:
	var out: Array[AbilityArea] = []
	for n in tree.get_nodes_in_group(&"ability_areas"):
		if n is AbilityArea and not n.is_queued_for_deletion():
			out.append(n)
	return out


func _blizzard(p: Player) -> AbilityData:
	return p.abilities.slots[0]


func _total(e: Fakes.FakeEnemy) -> float:
	var sum := 0.0
	for d in e.fake_damage_log:
		sum += d
	return sum


func test_cast_spends_mana_and_drops_a_frost_area_on_the_cluster() -> void:
	var p := _mage()
	var cluster := _cluster(Vector3(7, 0, 0), 5)
	_cluster(Vector3(-8, 0, 8), 2)
	var mana := p.abilities.get_resource(&"mana")
	var before := mana.value
	check(p.abilities.try_cast(0), "cast")
	check_near(mana.value, before - 50.0, 0.001, "50 Mana")
	var areas := _areas()
	check_eq(areas.size(), 1, "one area")
	var area := areas[0]
	check_near(area.global_position.distance_to(Vector3(7, 0, 0)), 0.0, 0.5, "on the densest cluster")
	check_eq(area.school, &"frost", "frost")
	check_near(area.radius, 3.5, 0.001, "radius")
	check_near(area.duration, 3.0, 0.001, "3 sec")
	check_near(area.slow_pct, 40.0, 0.001, "slows")
	check(area.get_node_or_null("Shards") is BlizzardShards, "falling shards")
	check(cluster[0].global_position.distance_to(area.global_position) <= area.radius, "cluster inside")


func test_cast_needs_a_target_and_mana() -> void:
	var p := _mage()
	var mana := p.abilities.get_resource(&"mana")
	check(not p.abilities.try_cast(0), "nobody around")
	check_eq(mana.value, mana.max_value(), "nothing spent")
	_cluster(Vector3(20, 0, 0), 4)
	check(not p.abilities.try_cast(0), "out of reach (12 m)")
	_cluster(Vector3(6, 0, 0), 3)
	mana.set_value(49.0)
	check(not p.abilities.try_cast(0), "49 Mana is not enough")
	mana.set_value(50.0)
	check(p.abilities.try_cast(0), "50 Mana is")
	check_near(mana.value, 0.0, 0.001, "all spent")
	check_eq(_areas().size(), 1, "area")


func test_area_deals_frost_ticks_and_slows() -> void:
	var p := _mage()
	var inside := _cluster(Vector3(6, 0, 0), 3)
	var outside := Fakes.spawn_enemy(world, Vector3(6, 0, 9))
	EnemyGrid.mark_dirty()
	var ctx := p.abilities.build_context(_blizzard(p))
	var per_tick := BlizzardEffect.tick_damage(ctx)
	var base := 3.0 + 0.5 * p.stats.get_raw(Stats.INTELLECT)
	check_near(per_tick, CombatMath.proc_damage(base, &"frost", p.stats), 0.001, "spell damage formula")
	check(per_tick > 3.0, "scales with Intellect")
	check(p.abilities.try_cast(0), "cast")
	var area := _areas()[0]
	check_near(area.damage_per_tick, per_tick, 0.001, "tick damage")
	Fakes.step(area, 3.2)
	for e in inside:
		check(e.fake_damage_log.size() >= 5 and e.fake_damage_log.size() <= 7, "6 ticks in 3 sec (%d)" % e.fake_damage_log.size())
		check_near(_total(e), per_tick * e.fake_damage_log.size(), 0.01, "every tick is a full tick")
		check(e.is_slowed(), "slowed")
		check_near(e.slow_pct, 40.0, 0.001, "by 40%")
	check_eq(outside.fake_damage_log.size(), 0, "outside the circle is safe")
	check(not outside.is_slowed(), "and not slowed")


func test_spell_power_and_school_damage_raise_the_ticks() -> void:
	var p := _mage()
	var ctx := p.abilities.build_context(_blizzard(p))
	var plain := BlizzardEffect.tick_damage(ctx)
	p.stats.set_source(&"gear", {Stats.SPELL_POWER: 10.0, Stats.FROST_DAMAGE: 50.0})
	var boosted := BlizzardEffect.tick_damage(p.abilities.build_context(_blizzard(p)))
	check(boosted > (plain + 10.0), "Spell Power and Frost damage %% (%f vs %f)" % [boosted, plain])


func test_frostweave_cowl_widens_the_area() -> void:
	var p := _mage()
	_cluster(Vector3(6, 0, 0), 3)
	var item := ItemGenerator.from_unique(Db.uniques[&"frostweave_cowl"], 1, false, RunState.rng, p.class_data)
	check(p.equipment.equip(item), "wear the cowl")
	var ctx := p.abilities.build_context(_blizzard(p))
	check_near(ctx.num("radius"), 3.5 * 1.3, 0.001, "+30% area in the params")
	check(p.abilities.try_cast(0), "cast")
	var expected := 3.5 * 1.3 * (1.0 + p.stats.get_raw(Stats.AREA_SIZE) / 100.0)
	check_near(_areas()[0].radius, expected, 0.001, "the area is bigger")
	check(expected > 3.5 * 1.3, "Area Size on the cowl stacks")


func test_densest_cluster_wins() -> void:
	var p := _mage()
	_cluster(Vector3(5, 0, 0), 2)
	_cluster(Vector3(-2, 0, -9), 6)
	check(p.abilities.try_cast(0), "cast")
	check_near(_areas()[0].global_position.distance_to(Vector3(-2, 0, -9)), 0.0, 0.6, "on the bigger group")


func test_bot_wants_a_cluster_of_four_and_does_not_stack() -> void:
	var p := _mage()
	var ability := _blizzard(p)
	var effect := p.abilities.effect_for(ability) as BlizzardEffect
	_cluster(Vector3(6, 0, 0), 3)
	check(not effect.wants_auto_cast(p.abilities.build_context(ability)), "3 enemies are not worth it")
	var more := Fakes.spawn_enemy(world, Vector3(6.3, 0, 0.2))
	EnemyGrid.mark_dirty()
	check(effect.wants_auto_cast(p.abilities.build_context(ability)), "4 enemies are")
	check(p.abilities.try_cast(0), "cast")
	check(not effect.wants_auto_cast(p.abilities.build_context(ability)), "not again on the same spot")
	more.queue_free()


func test_bot_casts_on_its_own() -> void:
	var p := _mage()
	p.abilities.auto_cast = true
	_cluster(Vector3(6, 0, 0), 5)
	Fakes.step(p.abilities, 0.6)
	check_eq(_areas().size(), 1, "the bot cast one Hailstorm")
	Fakes.step(p.abilities, 0.6)
	check_eq(_areas().size(), 1, "and did not stack another")
