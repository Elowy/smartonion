extends TestCase
## Warlock kit (M3, GDD 3.5 / 5.5): Soul Shards (+ Soulbinder's Sash), Rain of Fire, Drain Life,
## the Imp pet (+ Grimoire of the Imp Lord), Demonic Pact and the bot decisions.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0


## An enemy that dies when its HP runs out (no AI / model / loot).
class MortalEnemy extends Enemy:
	var hits: Array[float] = []
	var attackers: Array[Node3D] = []

	func _init() -> void:
		hp = 1000.0
		max_hp = 1000.0
		radius = 0.45

	func _enter_tree() -> void:
		pass

	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _physics_process(_delta: float) -> void:
		pass

	func is_dead() -> bool:
		return hp <= 0.0

	func take_damage(amount: float, _is_crit: bool = false, attacker: Node3D = null,
			_knockback: Vector3 = Vector3.ZERO) -> void:
		hits.append(amount)
		attackers.append(attacker)
		hp -= amount

	func apply_stun(_duration: float) -> void:
		pass

	func apply_slow(_pct: float, _duration: float) -> void:
		pass

	func total() -> float:
		var t := 0.0
		for v in hits:
			t += v
		return t


var world: Node3D


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 77)
	world = Fakes.make_world(tree)
	EnemyGrid.mark_dirty()


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	PlayerManager.clear()
	EnemyGrid.mark_dirty()


func _warlock(pos: Vector3 = Vector3.ZERO) -> Player:
	return Fakes.spawn_player(world, 0, &"warlock", pos)


func _enemy(pos: Vector3, hp: float = 1000.0) -> MortalEnemy:
	var e := MortalEnemy.new()
	e.hp = hp
	e.max_hp = maxf(hp, 1.0)
	e.add_to_group(&"enemies")
	world.add_child(e)
	e.global_position = pos
	EnemyGrid.mark_dirty()
	return e


func _mastery(p: Player) -> WarlockMastery:
	return p.abilities.mastery as WarlockMastery


func _shards(p: Player) -> ClassResource:
	return p.abilities.get_resource(&"soul_shard")


func _imp(p: Player) -> WarlockImp:
	return _mastery(p).ensure_imp()


func _flat_dist(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


func _step_imp(imp: WarlockImp, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		imp._physics_process(DT)
		t += DT


func _fly(bolt: WarlockImpBolt, seconds: float = 2.0) -> void:
	var t := 0.0
	while t < seconds and is_instance_valid(bolt) and not bolt.is_done():
		bolt.advance(DT)
		t += DT


func _item(unique_id: StringName) -> ItemInstance:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	return ItemGenerator.from_unique(Db.get_unique(unique_id), 1, false, rng)


## The class's ability_mod item as a plain trinket (no weapon swap needed for the test).
func _mod_trinket(unique_id: StringName) -> ItemInstance:
	var data := Db.get_unique(unique_id)
	var item := ItemInstance.new()
	item.slot_type = Items.SlotType.TRINKET
	item.armor_type = Items.NO_ARMOR
	item.source_id = data.id
	item.unique = true
	item.unique_effect = data.unique_effect
	item.unique_params = data.unique_params.duplicate(true)
	return item


# --- Data ------------------------------------------------------------------------------------

func test_class_data() -> void:
	var c := Db.get_class_data(&"warlock")
	check_eq(c.resources.size(), 1, "one resource")
	var shards := c.resources[0]
	check_eq(shards.id, &"soul_shard", "soul shards")
	check_eq(shards.display, ResourceData.Display.PIPS, "pips")
	check_eq(shards.max_value, 5.0, "0-5")
	check_eq(shards.gain_per_kills, 12, "+1 every 12 kills")
	check_eq(c.abilities.size(), 2, "two core abilities")
	check_eq(c.abilities[0].id, &"rain_of_fire", "RT")
	check_eq(c.abilities[0].resource, &"soul_shard", "costs shards")
	check_eq(c.abilities[0].cost, 1.0, "1 shard")
	check_eq(c.abilities[0].targeting, AbilityData.Targeting.DENSEST_CLUSTER, "cluster")
	check_eq(c.abilities[1].id, &"drain_life", "LT")
	check_eq(c.abilities[1].cooldown, 8.0, "8 s cooldown")
	check_eq(c.abilities[1].targeting, AbilityData.Targeting.NEAREST_ENEMY, "nearest")
	check(c.mastery != null and c.mastery.new() is WarlockMastery, "mastery script")
	check(c.mastery_text.begins_with("Demonic Pact"), "mastery text")


func test_class_items_are_ability_mods() -> void:
	var grimoire := Db.get_unique(&"grimoire_of_the_imp_lord")
	check_eq(grimoire.unique_effect, &"ability_mod", "grimoire mod")
	check_eq(String(grimoire.unique_params["ability"]), "warlock_imp", "grimoire -> imp")
	var sash := Db.get_unique(&"soulbinders_sash")
	check_eq(sash.unique_effect, &"ability_mod", "sash mod")
	check_eq(String(sash.unique_params["ability"]), "warlock_shards", "sash -> shards")


# --- Soul Shards -----------------------------------------------------------------------------

func test_soul_shards_every_12_kills() -> void:
	var p := _warlock()
	var res := _shards(p)
	p.begin_wave()
	check_eq(res.value, 1.0, "one shard at wave start")
	for i in 11:
		p.abilities.on_kill(null)
	check_eq(res.value, 1.0, "11 kills: nothing yet")
	p.abilities.on_kill(null)
	check_eq(res.value, 2.0, "12th kill: +1")
	res.set_value(5.0)
	for i in 12:
		p.abilities.on_kill(null)
	check_eq(res.value, 5.0, "capped at 5")


func test_soulbinders_sash_every_8_kills() -> void:
	var p := _warlock()
	var res := _shards(p)
	var sash := _item(&"soulbinders_sash")
	check(p.equipment.equip(sash), "equip the sash")
	_mastery(p).tick(DT)  # hooks the equipment (it does not exist at setup)
	check_eq(_mastery(p).kills_per_shard(), 8, "sash rule")
	p.begin_wave()
	for i in 7:
		p.abilities.on_kill(null)
	check_eq(res.value, 1.0, "7 kills: nothing yet")
	p.abilities.on_kill(null)
	check_eq(res.value, 2.0, "8th kill: +1")
	check_eq(Db.get_class_data(&"warlock").resources[0].gain_per_kills, 12, "shared data untouched")
	check(p.equipment.unequip(Items.EquipSlot.WAIST), "unequip")
	check_eq(_mastery(p).kills_per_shard(), 12, "back to 12")


# --- Rain of Fire ----------------------------------------------------------------------------

func test_rain_of_fire_spends_a_shard_and_burns_the_cluster() -> void:
	var p := _warlock()
	var lone := _enemy(Vector3(-6, 0, 0))
	var inside: Array[MortalEnemy] = []
	for i in 4:
		inside.append(_enemy(Vector3(6.0 + 0.6 * i, 0, 0.5 * (i % 2))))
	var res := _shards(p)
	res.set_value(1.0)
	var effect := p.abilities.effect_for(p.abilities.slots[0]) as WarlockRainOfFire
	check(effect.wants_auto_cast(p.abilities.build_context(p.abilities.slots[0])), "bots want it on 4+")
	check(p.abilities.try_cast(0), "cast")
	check_eq(res.value, 0.0, "1 shard spent")
	check(not p.abilities.try_cast(0), "no shard left")
	var areas := tree.get_nodes_in_group(&"ability_areas")
	check_eq(areas.size(), 1, "one fire circle")
	var area := areas[0] as AbilityArea
	check_eq(area.school, &"fire", "fire")
	check_near(area.radius, 3.0, 0.001, "radius")
	check_near(area.duration, 4.0, 0.001, "4 s")
	check(area.global_position.x > 5.0, "on the cluster")
	var vfx := area.get_node_or_null("RainOfFireVfx") as WarlockRainOfFireVfx
	check(vfx != null, "falling fire vfx")
	var expected := WarlockRainOfFire.tick_damage(p.stats, p.abilities.build_context(p.abilities.slots[0]).params)
	check_near(area.damage_per_tick, expected, 0.001, "tick damage")
	var t := 0.0
	while t < 4.2:
		area._physics_process(DT)
		if is_instance_valid(vfx):
			vfx._process(DT)
		t += DT
	for e in inside:
		check_eq(e.hits.size(), 8, "8 ticks on every enemy inside")
		check_near(e.hits[0], expected, 0.001, "per tick")
		check(e.attackers[0] == p, "kill credit to the warlock")
	check_eq(lone.hits.size(), 0, "nothing outside")


func test_rain_of_fire_needs_a_target_and_scales_with_intellect() -> void:
	var p := _warlock()
	_shards(p).set_value(1.0)
	check(not p.abilities.try_cast(0), "no enemies: no cast")
	check_eq(_shards(p).value, 1.0, "shard kept")
	var params: Dictionary = p.abilities.slots[0].params
	var base := WarlockRainOfFire.tick_damage(p.stats, params)
	p.stats.set_source(&"t", {Stats.INTELLECT: 10.0})
	check(WarlockRainOfFire.tick_damage(p.stats, params) > base + 2.0, "intellect scales it")
	p.stats.set_source(&"t", {Stats.SPELL_POWER: 10.0})
	check(WarlockRainOfFire.tick_damage(p.stats, params) > base + 2.0, "spell power scales it")


func test_rain_of_fire_bot_needs_four_in_the_circle() -> void:
	var p := _warlock()
	_shards(p).set_value(3.0)
	for i in 3:
		_enemy(Vector3(5.0 + 0.5 * i, 0, 0))
	var effect := p.abilities.effect_for(p.abilities.slots[0])
	check(not effect.wants_auto_cast(p.abilities.build_context(p.abilities.slots[0])), "3: no")
	_enemy(Vector3(5.2, 0, 0.6))
	check(effect.wants_auto_cast(p.abilities.build_context(p.abilities.slots[0])), "4: yes")
	check(p.abilities.try_cast(0), "cast")
	check(not effect.wants_auto_cast(p.abilities.build_context(p.abilities.slots[0])), "no second circle on top")


# --- Drain Life ------------------------------------------------------------------------------

func test_drain_life_heals_for_the_damage_dealt() -> void:
	var p := _warlock()
	var e := _enemy(Vector3(3, 0, 0))
	p.hp = 2.0
	check(p.abilities.try_cast(1), "cast")
	var effect := p.abilities.effect_for(p.abilities.slots[1]) as WarlockDrainLife
	check(effect.is_channeling(), "channelling")
	check(effect.beam != null and effect.beam.is_inside_tree(), "beam")
	check_near(p.abilities.remaining(1), 8.0, 0.001, "8 s cooldown")
	var per_tick := WarlockDrainLife.tick_damage(p.stats, p.abilities.slots[1].params)
	var t := 0.0
	while t < 2.2:
		p.global_position += Vector3(0, 0, -1.0) * DT  # walking while channelling
		p.abilities._physics_process(DT)
		t += DT
	check(not effect.is_channeling(), "ended after 2 s")
	check_eq(e.hits.size(), 5, "5 ticks (every 0.4 s)")
	check_near(e.hits[0], per_tick, 0.001, "shadow tick")
	check_near(effect.damage_total, per_tick * 5.0, 0.01, "total")
	check_near(p.hp, minf(p.max_hp(), 2.0 + per_tick * 5.0), 0.01, "healed by the damage dealt")
	check_near(effect.healed_total, p.hp - 2.0, 0.01, "healed total")


func test_drain_life_retargets_when_the_target_dies() -> void:
	var p := _warlock()
	var weak := _enemy(Vector3(2, 0, 0), 0.5)
	var next := _enemy(Vector3(-4, 0, 0))
	p.hp = 2.0
	check(p.abilities.try_cast(1), "cast")
	var effect := p.abilities.effect_for(p.abilities.slots[1]) as WarlockDrainLife
	check(effect.target == weak, "nearest first")
	for i in 30:
		p.abilities._physics_process(DT)
	check(weak.is_dead(), "first target died")
	check_near(p.hp, 2.5, 0.001, "overkill does not heal")
	check(effect.target == next, "jumped to the next enemy")
	check(effect.beam.target == next, "beam follows")
	for i in 120:
		p.abilities._physics_process(DT)
	check_eq(next.hits.size(), 4, "the rest of the ticks")


func test_drain_life_ends_without_enemies_or_when_downed() -> void:
	var p := _warlock()
	var e := _enemy(Vector3(2, 0, 0))
	check(p.abilities.try_cast(1), "cast")
	var effect := p.abilities.effect_for(p.abilities.slots[1]) as WarlockDrainLife
	e.global_position = Vector3(40, 0, 0)
	EnemyGrid.mark_dirty()
	p.abilities._physics_process(DT)
	check(not effect.is_channeling(), "out of range, nobody else: ends")
	e.global_position = Vector3(2, 0, 0)
	EnemyGrid.mark_dirty()
	p.begin_wave()
	check(p.abilities.try_cast(1), "cast again")
	p._go_down()
	check(not effect.is_channeling(), "downed: ends")
	p.begin_wave()
	check(p.abilities.try_cast(1), "cast after the revive")
	p.begin_wave()
	check(not effect.is_channeling(), "wave start: ends")
	check(effect.beam == null, "beam released")


func test_drain_life_bot_casts_when_hurt() -> void:
	var p := _warlock()
	var slot := p.abilities.slots[1]
	var effect := p.abilities.effect_for(slot)
	check(not effect.wants_auto_cast(p.abilities.build_context(slot)), "no enemy")
	_enemy(Vector3(4, 0, 0))
	check(not effect.wants_auto_cast(p.abilities.build_context(slot)), "full HP: no")
	p.hp = p.max_hp() * 0.6
	check(effect.wants_auto_cast(p.abilities.build_context(slot)), "below 70%: yes")


# --- Imp -------------------------------------------------------------------------------------

func test_imp_spawns_and_follows() -> void:
	var p := _warlock()
	check(_mastery(p).imp == null, "no imp before the first tick")
	p.abilities._physics_process(DT)
	var imp := _mastery(p).imp
	check(imp != null and imp.is_inside_tree(), "spawned on the first tick")
	check(imp.get_parent() == world, "next to the warlock (no arena)")
	check(imp.model != null, "has a model")
	check_near(_flat_dist(imp, p), WarlockImp.FOLLOW_DISTANCE, 0.05, "1.5 m away")
	p.abilities._physics_process(DT)
	check(_mastery(p).imp == imp, "only one imp")
	p.global_position = Vector3(3, 0, 2)
	_step_imp(imp, 2.0)
	check_near(_flat_dist(imp, p), WarlockImp.FOLLOW_DISTANCE, 0.15, "follows")
	p.global_position = Vector3(30, 0, 0)
	_step_imp(imp, DT)
	check_near(_flat_dist(imp, p), WarlockImp.FOLLOW_DISTANCE, 0.05, "pops back when far")


func test_imp_shoots_pet_firebolts() -> void:
	var p := _warlock()
	p.stats.set_source(&"t", {Stats.MASTERY: 10.0, Stats.INTELLECT: 5.0})
	var imp := _imp(p)
	var e := _enemy(imp.global_position + Vector3(0, 0, -5))
	_step_imp(imp, WarlockImp.FIRST_SHOT_DELAY + DT * 2.0)
	check_eq(imp.shots_fired, 1, "one bolt after the first delay")
	var bolt := imp.last_bolt
	check(bolt != null and bolt.is_inside_tree(), "bolt in flight")
	var params := imp.current_params()
	var dmg := WarlockImp.bolt_damage(p.stats, params)
	check_near(bolt.damage, dmg, 0.001, "bolt damage")
	check_eq(bolt.pierce, 0, "one target")
	_fly(bolt)
	check_eq(e.hits.size(), 1, "hit")
	check_near(e.hits[0], dmg * 1.2, 0.001, "pet damage x Demonic Pact (10 x 2%)")
	check(e.attackers[0] == p, "kill credit to the warlock")
	var no_int := WarlockImp.bolt_damage(StatBlock.new(), params)
	check(dmg > no_int + 1.5, "scales with intellect")
	var interval := WarlockImp.shot_interval(p.stats, params)
	_step_imp(imp, interval - 2.0 * DT)
	check_eq(imp.shots_fired, 1, "waits the interval")
	_step_imp(imp, 4.0 * DT)
	check_eq(imp.shots_fired, 2, "second bolt")


func test_imp_ignores_enemies_out_of_range() -> void:
	var p := _warlock()
	var imp := _imp(p)
	_enemy(imp.global_position + Vector3(0, 0, -12))
	_step_imp(imp, 2.0)
	check_eq(imp.shots_fired, 0, "9 m range")


func test_imp_hides_while_the_warlock_is_downed() -> void:
	var p := _warlock()
	var imp := _imp(p)
	_enemy(Vector3(0, 0, -5))
	p._go_down()
	_step_imp(imp, 2.0)
	check(not imp.visible and imp.is_hidden(), "hidden")
	check_eq(imp.shots_fired, 0, "no bolts while downed")
	p.abilities._physics_process(DT)
	check(_mastery(p).imp == imp, "still the same imp")
	p.revive()
	_step_imp(imp, WarlockImp.FIRST_SHOT_DELAY + 2.0 * DT)
	check(imp.visible and not imp.is_hidden(), "back")
	check_eq(imp.shots_fired, 1, "shoots again")


func test_imp_survives_waves_and_is_freed_in_teardown() -> void:
	var p := _warlock()
	var imp := _imp(p)
	p.global_position = Vector3(10, 0, 10)
	p.begin_wave()
	check(is_instance_valid(imp) and not imp.is_queued_for_deletion(), "survives the wave")
	check_near(_flat_dist(imp, p), WarlockImp.FOLLOW_DISTANCE, 0.05, "next to the warlock at wave start")
	world.remove_child(p)  # Player._exit_tree -> abilities.teardown()
	check(imp.is_queued_for_deletion(), "freed with the warlock")
	check(_mastery(p).imp == null, "forgotten")
	p.free()
	_step_imp(imp, DT)


func test_grimoire_of_the_imp_lord() -> void:
	var p := _warlock()
	var imp := _imp(p)
	var base := imp.current_params()
	var base_dmg := WarlockImp.bolt_damage(p.stats, base)
	check(p.equipment.equip(_mod_trinket(&"grimoire_of_the_imp_lord")), "equip")
	var params := imp.current_params()
	check_eq(int(params["targets"]), 2, "2 targets")
	check_near(WarlockImp.bolt_damage(p.stats, params), base_dmg * 1.5, 0.001, "+50% damage")
	var a := _enemy(imp.global_position + Vector3(0, 0, -4))
	var b := _enemy(imp.global_position + Vector3(3, 0, -4))
	check(imp.try_shoot(), "shoot")
	var bolt := imp.last_bolt
	check_eq(bolt.pierce, 1, "pierces once")
	_fly(bolt)
	check_eq(bolt.victim_ids, [a.get_instance_id(), b.get_instance_id()] as Array[int], "ricochets to the second")
	check_eq(a.hits.size(), 1, "a hit once")
	check_eq(b.hits.size(), 1, "b hit once")


# --- Demonic Pact ----------------------------------------------------------------------------

func test_demonic_pact() -> void:
	var p := _warlock()
	var m := _mastery(p)
	check_eq(m.damage_mult(null, &"fire", &"pet"), 1.0, "no mastery: x1")
	p.stats.set_source(&"t", {Stats.MASTERY: 15.0})
	check_near(m.damage_mult(null, &"fire", &"pet"), 1.3, 0.0001, "pets +2% per point")
	check_near(m.damage_mult(null, &"shadow", &"dot"), 1.3, 0.0001, "DoTs +2% per point")
	check_eq(m.damage_mult(null, &"fire", &"weapon"), 1.0, "not weapons")
	check_eq(m.damage_mult(null, &"fire", &"ability"), 1.0, "not direct abilities")
	check_near(p.outgoing_damage_mult(null, &"fire", &"pet"), 1.3, 0.0001, "through the player")
	check(m.describe().contains("30%"), "tooltip shows the bonus")
