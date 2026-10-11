extends TestCase
## Warlock M4 abilities (GDD 6.4): Corruption, Shadow Bolt, Seed of Corruption, Summon
## Voidwalker, Fear, Summon Infernal – data, ranks / specs, Demonic Pact on DoTs and pets,
## wave / down / forget clean-up, auto-cast and bot rules – plus the rank / spec support of
## the core Rain of Fire and Drain Life.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0
const M4_IDS: Array[StringName] = [&"corruption", &"shadow_bolt", &"seed_of_corruption",
		&"summon_voidwalker", &"fear", &"summon_infernal"]


## An enemy that dies when its HP runs out (no AI / model / loot). Fear, taunt, stun and slow
## use the real Enemy code (they only set timers).
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

	func total() -> float:
		var t := 0.0
		for v in hits:
			t += v
		return t


## A MortalEnemy that [method Enemy.despawn] takes out like a real one: dead (not live) at once,
## HP untouched, still in the tree until the queued free runs at the end of the frame.
class DespawnableEnemy extends MortalEnemy:
	func is_dead() -> bool:
		return _dead or hp <= 0.0


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


# --- Helpers ---------------------------------------------------------------------------------

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


func _kill(e: MortalEnemy) -> void:
	e.hp = 0.0
	EnemyGrid.mark_dirty()


func _ability(id: StringName) -> AbilityData:
	return Db.get_ability(id)


## Learns [param id] at [param rank] (spec at Rank V). Returns the slot.
func _learn(p: Player, id: StringName, rank: int = 1, spec: int = -1) -> int:
	var slot := p.abilities.learn(_ability(id))
	for i in rank - 1:
		p.abilities.rank_up(id)
	if spec >= 0:
		p.abilities.set_spec(id, spec)
	return slot


func _effect(p: Player, id: StringName) -> AbilityEffect:
	return p.abilities.effect_for(_ability(id))


func _ctx(p: Player, id: StringName) -> AbilityContext:
	return p.abilities.build_context(_ability(id))


func _params(p: Player, id: StringName) -> Dictionary:
	return p.abilities.params_for(_ability(id))


func _aff(p: Player) -> WarlockAfflictions:
	return WarlockAfflictions.of(p, false)


func _step(node: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		node._physics_process(DT)
		t += DT


func _fly(bolt: Projectile, seconds: float = 2.0) -> void:
	var t := 0.0
	while t < seconds and is_instance_valid(bolt) and not bolt.is_done():
		bolt.advance(DT)
		t += DT


func _marker(e: Node, kind: String) -> Node:
	return e.get_node_or_null("Warlock%sMarker" % kind)


# --- Data ------------------------------------------------------------------------------------

func test_m4_abilities_are_in_the_warlock_pool() -> void:
	var pool := Db.ability_pool(&"warlock")
	for id in M4_IDS:
		var a := _ability(id)
		check(a != null, "%s loads" % id)
		if a == null:
			continue
		check_eq(a.class_id, &"warlock", "%s belongs to the warlock" % id)
		check(a in pool, "%s offered on warlock cards" % id)
		check(a.effect != null and a.effect.new() is AbilityEffect, "%s effect script" % id)
		check_eq(String(a.icon), String(id), "%s icon id" % id)
		check(a.card_weight > 0.0, "%s weight" % id)
	check(not (_ability(&"corruption") in Db.ability_pool(&"mage")), "not a mage card")
	var auto := [&"corruption", &"shadow_bolt", &"seed_of_corruption", &"summon_voidwalker"]
	for id: StringName in auto:
		check_eq(_ability(id).kind, AbilityData.Kind.AUTO, "%s is auto-cast" % id)
	check_eq(_ability(&"fear").kind, AbilityData.Kind.ACTIVE, "fear is active")
	var infernal := _ability(&"summon_infernal")
	check_eq(infernal.kind, AbilityData.Kind.ACTIVE, "infernal is active")
	check_eq(infernal.resource, &"soul_shard", "infernal costs soul shards")
	check_eq(infernal.cost, 1.0, "1 shard")
	check(infernal.cooldown >= 30.0, "long cooldown")


## Rank III and both specs of every Warlock ability (M4 + core) only touch params the effect
## reads (every changed param exists in the params), every description placeholder is filled,
## and applying each mod really changes the param it is meant for (AbilityRunner.apply_mods:
## "<p>_add" adds to p, "<p>_pct" scales p when p exists, any other key sets itself).
func test_rank3_and_specs_use_known_params() -> void:
	var p := _warlock()
	var ids: Array[StringName] = []
	ids.append_array(M4_IDS)
	ids.append_array([&"rain_of_fire", &"drain_life"])
	for id in ids:
		var a := _ability(id)
		check(not a.rank3.is_empty(), "%s rank III" % id)
		check(a.rank3_text != "", "%s rank III text" % id)
		check_eq(a.specs.size(), 2, "%s has 2 specs" % id)
		_check_mods_change(p, a, a.rank3, p.abilities.params_at_rank(a, 2), p.abilities.params_at_rank(a, 3),
				"rank III")
		var r4 := p.abilities.params_at_rank(a, 4)
		for i in a.specs.size():
			var spec := a.specs[i]
			check(String(spec.get("name", "")) != "" and String(spec.get("text", "")) != "", "%s spec name / text" % id)
			_check_mods_change(p, a, spec.get("mods", {}), r4, p.abilities.params_at_rank(a, 5, i),
					"spec %s" % spec.get("name", i))
		var text := AbilityIcon.format_description(a, a.params)
		check(not text.contains("{"), "%s description filled: %s" % [id, text])


## Every key of [param mods] changes its intended param between [param before] and [param after].
func _check_mods_change(_p: Player, a: AbilityData, mods: Dictionary, before: Dictionary, after: Dictionary,
		what: String) -> void:
	check(not mods.is_empty(), "%s %s mods not empty" % [a.id, what])
	for key: String in mods:
		var target := key
		if key.ends_with("_add"):
			target = key.trim_suffix("_add")
		elif key.ends_with("_pct") and before.has(key.trim_suffix("_pct")):
			target = key.trim_suffix("_pct")
		check(a.params.has(target) or target in ["cooldown", "cost", "charges", "power"],
				"%s %s: %s changes %s, a param the effect knows" % [a.id, what, key, target])
		check(before.get(target) != after.get(target),
				"%s %s: %s really changes %s (%s -> %s)" % [a.id, what, key, target, before.get(target), after.get(target)])


func test_ranks_scale_power_and_merge_specs() -> void:
	var p := _warlock()
	_learn(p, &"shadow_bolt", 5, 1)
	var params := _params(p, &"shadow_bolt")
	check_near(float(params["power"]), 1.5, 0.0001, "Ranks II + IV: +50%")
	check_eq(roundi(float(params["bolts"])), 2, "Rank III: +1 bolt")
	check_near(float(params["blast_radius"]), 2.5, 0.0001, "Shadow Burst")
	check_near(WarlockShadowBolt.bolt_damage(p.stats, params),
			WarlockShadowBolt.bolt_damage(p.stats, _ability(&"shadow_bolt").params) * 1.5, 0.001, "damage x power")


# --- Corruption ------------------------------------------------------------------------------

func test_corruption_dot_with_demonic_pact() -> void:
	var p := _warlock()
	p.stats.set_source(&"t", {Stats.INTELLECT: 10.0})
	var e := _enemy(Vector3(4, 0, 0))
	var slot := _learn(p, &"corruption")
	check_eq(slot, 4, "first auto slot")
	var effect := _effect(p, &"corruption") as WarlockCorruption
	check(effect.wants_auto_cast(_ctx(p, &"corruption")), "wants an uncorrupted enemy")
	check(p.abilities.try_cast(slot), "cast")
	var aff := _aff(p)
	check(aff != null and aff.get_parent() == p, "afflictions live on the warlock")
	check(aff.has(WarlockAfflictions.CORRUPTION, e), "corrupted")
	check(_marker(e, "Corruption") != null, "purple wisps on the enemy")
	check(not effect.wants_auto_cast(_ctx(p, &"corruption")), "no recast on a corrupted enemy")
	var rate := WarlockCorruption.rate(p.stats, _params(p, &"corruption"))
	check(rate > WarlockCorruption.rate(StatBlock.new(), _params(p, &"corruption")) + 1.0, "scales with intellect")
	_step(aff, 8.2)
	check_eq(e.hits.size(), 16, "a tick every 0.5 s for 8 s")
	check_near(e.total(), rate * 8.0, 0.01, "rate x duration")
	check(e.attackers[0] == p, "kill credit")
	check(not aff.has(WarlockAfflictions.CORRUPTION, e), "expired")
	check(_marker(e, "Corruption") == null or _marker(e, "Corruption").is_queued_for_deletion(), "wisps gone")
	# Demonic Pact boosts the DoT ("dot" source).
	var e2 := _enemy(Vector3(-3, 0, 0))
	p.stats.set_source(&"m", {Stats.MASTERY: 10.0})
	p.abilities.set_cooldown(_ability(&"corruption"), 0.0)
	check(p.abilities.try_cast(slot), "cast again")
	_step(aff, 1.0)
	check_eq(e2.hits.size(), 2, "two ticks")
	check_near(e2.hits[0], rate * 0.5 * 1.2, 0.001, "x Demonic Pact (10 Mastery)")


func test_corruption_spreads_with_its_remaining_time() -> void:
	var p := _warlock()
	var a := _enemy(Vector3(3, 0, 0))
	var b := _enemy(Vector3(5, 0, 0))
	var far := _enemy(Vector3(3, 0, 8))
	var slot := _learn(p, &"corruption")
	check(p.abilities.try_cast(slot), "cast")
	var aff := _aff(p)
	check(aff.has(WarlockAfflictions.CORRUPTION, a), "nearest first")
	_step(aff, 1.0)
	_kill(a)
	aff._physics_process(DT)
	check(not aff.has(WarlockAfflictions.CORRUPTION, a), "gone from the corpse")
	check(aff.has(WarlockAfflictions.CORRUPTION, b), "jumped to the neighbour")
	check(not aff.has(WarlockAfflictions.CORRUPTION, far), "not beyond the spread radius")
	check_eq(aff.spreads, 1, "one spread")
	check_near(aff.get_affliction(WarlockAfflictions.CORRUPTION, b).left, 7.0, 0.05, "keeps the time left")
	_step(aff, 7.2)
	check_eq(b.hits.size(), 14, "the rest of the ticks")
	check(not aff.has(WarlockAfflictions.CORRUPTION, b), "expired after the original 8 s")


func test_corruption_rank3_contagion_and_siphon_life() -> void:
	var p := _warlock()
	var near: Array[MortalEnemy] = []
	for i in 4:
		near.append(_enemy(Vector3(3.0 + 0.8 * i, 0, 0)))
	var slot := _learn(p, &"corruption", 3)
	check(p.abilities.try_cast(slot), "Rank III cast")
	var aff := _aff(p)
	check_eq(aff.count(WarlockAfflictions.CORRUPTION), 2, "two enemies per cast")
	aff.clear()
	p.abilities.rank_up(&"corruption")
	p.abilities.rank_up(&"corruption")
	check(p.abilities.set_spec(&"corruption", 0), "Contagion")
	p.abilities.set_cooldown(_ability(&"corruption"), 0.0)
	check(p.abilities.try_cast(slot), "cast")
	var first := near[0]
	for e in near:
		if e != near[0] and e != near[1]:
			check(not aff.has(WarlockAfflictions.CORRUPTION, e), "only two at first")
	_kill(first)
	aff._physics_process(DT)
	check_eq(aff.count(WarlockAfflictions.CORRUPTION), 3, "spread to 2 more (3 targets, one already corrupted)")
	# Siphon Life heals.
	var p2 := Fakes.spawn_player(world, 1, &"warlock", Vector3(0, 0, 20))
	var e2 := _enemy(Vector3(0, 0, 23))
	var slot2 := _learn(p2, &"corruption", 5, 1)
	p2.hp = 2.0
	check(p2.abilities.try_cast(slot2), "cast")
	_step(_aff(p2), 2.0)
	check_near(p2.hp, 2.0 + e2.total() * 0.3, 0.01, "heals 30% of the damage")


func test_corruption_keeps_burning_while_downed_and_clears_on_waves() -> void:
	var p := _warlock()
	var e := _enemy(Vector3(3, 0, 0))
	var slot := _learn(p, &"corruption")
	check(p.abilities.try_cast(slot), "cast")
	p._go_down()
	_step(_aff(p), 1.0)
	check_eq(e.hits.size(), 2, "ticks while the warlock is downed")
	p.revive()
	p.end_wave()
	check_eq(_aff(p).count(), 0, "wave end clears")
	check(_marker(e, "Corruption") == null or _marker(e, "Corruption").is_queued_for_deletion(), "marker released")
	p.begin_wave()
	check(p.abilities.try_cast(slot), "cast in the new wave")
	p.begin_wave()
	check_eq(_aff(p).count(), 0, "wave start clears")
	check(p.abilities.try_cast(slot), "cast once more")
	p.abilities.forget(slot)
	check_eq(_aff(p).count(), 0, "forgetting clears")


# --- Shadow Bolt -----------------------------------------------------------------------------

func test_shadow_bolt_hits_the_nearest_enemy() -> void:
	var p := _warlock()
	p.stats.set_source(&"t", {Stats.INTELLECT: 10.0, Stats.MASTERY: 10.0})
	var e := _enemy(Vector3(0, 0, -6))
	var other := _enemy(Vector3(0, 0, 9))
	var slot := _learn(p, &"shadow_bolt")
	var effect := _effect(p, &"shadow_bolt") as WarlockShadowBolt
	check(effect.wants_auto_cast(_ctx(p, &"shadow_bolt")), "wants an enemy in range")
	check(p.abilities.try_cast(slot), "cast")
	check_eq(effect.last_bolts.size(), 1, "one bolt")
	var bolt := effect.last_bolts[0]
	var dmg := WarlockShadowBolt.bolt_damage(p.stats, _params(p, &"shadow_bolt"))
	check_near(bolt.damage, dmg, 0.001, "bolt damage")
	check(dmg > WarlockShadowBolt.bolt_damage(StatBlock.new(), _params(p, &"shadow_bolt")) + 10.0, "scales with intellect")
	_fly(bolt)
	check_eq(e.hits.size(), 1, "hit")
	check_near(e.hits[0], dmg, 0.001, "ability damage: no Demonic Pact")
	check(e.attackers[0] == p, "kill credit")
	check_eq(other.hits.size(), 0, "the other one untouched")


func test_shadow_bolt_rank3_and_specs() -> void:
	var p := _warlock()
	var a := _enemy(Vector3(0, 0, -5))
	var b := _enemy(Vector3(4, 0, 0))
	var slot := _learn(p, &"shadow_bolt", 3)
	var effect := _effect(p, &"shadow_bolt") as WarlockShadowBolt
	check(p.abilities.try_cast(slot), "cast")
	check_eq(effect.last_bolts.size(), 2, "Rank III: two bolts")
	for bolt in effect.last_bolts.duplicate():
		_fly(bolt)
	check_eq(a.hits.size(), 1, "first enemy")
	check_eq(b.hits.size(), 1, "second enemy")
	# Void Lance: pierces a line of enemies.
	var p2 := Fakes.spawn_player(world, 1, &"warlock", Vector3(20, 0, 0))
	var line: Array[MortalEnemy] = []
	for i in 4:
		line.append(_enemy(Vector3(20, 0, -3.0 - 1.5 * i)))
	var slot2 := _learn(p2, &"shadow_bolt", 5, 0)
	var effect2 := _effect(p2, &"shadow_bolt") as WarlockShadowBolt
	check(p2.abilities.try_cast(slot2), "cast")
	for bolt in effect2.last_bolts.duplicate():
		_fly(bolt)
	var pierced := 0
	for e in line:
		pierced += e.hits.size()
	check(pierced >= 4, "pierced the line (%d hits)" % pierced)
	# Shadow Burst: explodes on the first enemy, hitting its neighbours.
	var p3 := Fakes.spawn_player(world, 2, &"warlock", Vector3(-20, 0, 0))
	var target := _enemy(Vector3(-20, 0, -5))
	var side := _enemy(Vector3(-18.5, 0, -5.5))
	var slot3 := _learn(p3, &"shadow_bolt", 5, 1)
	var effect3 := _effect(p3, &"shadow_bolt") as WarlockShadowBolt
	check(p3.abilities.try_cast(slot3), "cast")
	for bolt in effect3.last_bolts.duplicate():
		_fly(bolt)
	check(target.hits.size() >= 1, "target hit")
	check(side.hits.size() >= 1, "neighbour caught in the burst")


# --- Seed of Corruption ----------------------------------------------------------------------

func test_seed_bursts_when_its_host_dies() -> void:
	var p := _warlock()
	p.stats.set_source(&"t", {Stats.INTELLECT: 10.0})
	var host := _enemy(Vector3(6, 0, 0))
	var near := _enemy(Vector3(7.5, 0, 0))
	var far := _enemy(Vector3(11, 0, 0))
	var slot := _learn(p, &"seed_of_corruption")
	var effect := _effect(p, &"seed_of_corruption") as WarlockSeedOfCorruption
	check(effect.wants_auto_cast(_ctx(p, &"seed_of_corruption")), "a group of 2 is enough")
	check(p.abilities.try_cast(slot), "cast")
	var aff := _aff(p)
	var seeded: Enemy = host if aff.has(WarlockAfflictions.SEED, host) else near
	check(aff.has(WarlockAfflictions.SEED, seeded), "seeded the cluster")
	check(_marker(seeded, "Seed") != null, "seed marker")
	_step(aff, 1.0)
	check_eq((seeded as MortalEnemy).hits.size(), 2, "the seed withers its host")
	var other: MortalEnemy = near if seeded == host else host
	var before := other.hits.size()
	_kill(seeded as MortalEnemy)
	aff._physics_process(DT)
	check_eq(aff.bursts, 1, "burst")
	var burst := WarlockSeedOfCorruption.burst_damage(p.stats, _params(p, &"seed_of_corruption"))
	check_eq(other.hits.size(), before + 1, "neighbour hit")
	check_near(other.hits[other.hits.size() - 1], burst, 0.001, "burst damage")
	check_eq(far.hits.size(), 0, "outside the radius")
	check(not aff.has(WarlockAfflictions.SEED, seeded), "seed used up")


func test_seed_ripens_and_needs_a_group() -> void:
	var p := _warlock()
	p.stats.set_source(&"t", {Stats.MASTERY: 10.0})
	var lone := _enemy(Vector3(5, 0, 0))
	var slot := _learn(p, &"seed_of_corruption")
	var effect := _effect(p, &"seed_of_corruption") as WarlockSeedOfCorruption
	check(not effect.wants_auto_cast(_ctx(p, &"seed_of_corruption")), "a lone enemy is not worth it")
	var buddy := _enemy(Vector3(5.8, 0, 0.5))
	check(effect.wants_auto_cast(_ctx(p, &"seed_of_corruption")), "two are")
	check(p.abilities.try_cast(slot), "cast")
	var aff := _aff(p)
	var host: MortalEnemy = lone if aff.has(WarlockAfflictions.SEED, lone) else buddy
	var rate := WarlockSeedOfCorruption.dot_rate(p.stats, _params(p, &"seed_of_corruption"))
	_step(aff, 6.05)
	check_eq(aff.bursts, 1, "burst when ripe")
	check_eq(host.hits.size(), 13, "12 DoT ticks + the burst")
	check_near(host.hits[0], rate * 0.5 * 1.2, 0.001, "seed DoT x Demonic Pact")
	check(effect.host_for(_ctx(p, &"seed_of_corruption")) != null, "can seed again")
	aff.plant_seed(lone, 1.0, 6.0, 5.0, 3.0)
	check(effect.host_for(_ctx(p, &"seed_of_corruption")) != lone, "never a second seed in one host")
	p.end_wave()
	check_eq(aff.count(), 0, "wave end: seeds wither")
	check_eq(aff.bursts, 1, "without bursting")


func test_seed_chain_reaction_and_blighted_ground() -> void:
	var p := _warlock()
	var host := _enemy(Vector3(5, 0, 0))
	var next := _enemy(Vector3(6, 0, 0.5))
	var slot := _learn(p, &"seed_of_corruption", 5, 0)
	check(p.abilities.try_cast(slot), "cast")
	var aff := _aff(p)
	var seeded: MortalEnemy = host if aff.has(WarlockAfflictions.SEED, host) else next
	var other: MortalEnemy = next if seeded == host else host
	_kill(seeded)
	aff._physics_process(DT)
	check(aff.has(WarlockAfflictions.SEED, other), "Chain Reaction: the burst seeded a survivor")
	check_eq(aff.get_affliction(WarlockAfflictions.SEED, other).chain_left, 1, "one more link")
	# Blighted Ground.
	var p2 := Fakes.spawn_player(world, 1, &"warlock", Vector3(0, 0, 20))
	var h2 := _enemy(Vector3(5, 0, 20))
	var n2 := _enemy(Vector3(5.6, 0, 20.5))
	var slot2 := _learn(p2, &"seed_of_corruption", 5, 1)
	check(p2.abilities.try_cast(slot2), "cast")
	var s2: MortalEnemy = h2 if _aff(p2).has(WarlockAfflictions.SEED, h2) else n2
	_kill(s2)
	_aff(p2)._physics_process(DT)
	var pools := tree.get_nodes_in_group(&"ability_areas")
	check_eq(pools.size(), 1, "a blighted pool")
	var pool := pools[0] as AbilityArea
	check_near(pool.slow_pct, 40.0, 0.001, "slows")
	check(pool.damage_per_tick > 0.0, "burns")
	check_near(pool.duration, 3.0, 0.001, "3 s")
	check(pool.get_node_or_null("BlightVfx") != null, "bubbling look")


func test_afflictions_wither_when_their_host_vanishes_without_dying() -> void:
	var p := _warlock()
	var host := _enemy(Vector3(5, 0, 0))
	var next := _enemy(Vector3(6, 0, 0.5))
	var slot := _learn(p, &"seed_of_corruption", 5, 1)  # Blighted Ground
	check(p.abilities.try_cast(slot), "cast")
	var aff := _aff(p)
	var seeded: MortalEnemy = host if aff.has(WarlockAfflictions.SEED, host) else next
	var other: MortalEnemy = next if seeded == host else host
	check(aff.corrupt(seeded, 1.0, 8.0, 2, 6.0) != null, "corrupted too")
	# Wave end: WaveDirector.stop() despawns every enemy (no died signal); freed by the next tick.
	seeded.free()
	aff._physics_process(DT)
	check_eq(aff.bursts, 0, "no burst over a despawned host")
	check_eq(aff.spreads, 0, "no spread either")
	check_eq(aff.count(), 0, "its afflictions withered")
	check(not aff.has(WarlockAfflictions.CORRUPTION, other), "nothing jumped to the neighbour")
	check_eq(tree.get_nodes_in_group(&"ability_areas").size(), 0, "no Blighted Ground pool")
	# A real death still counts, even when the corpse is already gone by the next tick.
	check(aff.plant_seed(other, 1.0, 6.0, 5.0, 3.0) != null, "seeded the other one")
	other.died.emit(other, 0)
	other.free()
	aff._physics_process(DT)
	check_eq(aff.bursts, 1, "a killed host bursts")


func test_afflictions_wither_when_their_host_vanishes_in_the_same_frame() -> void:
	var p := _warlock()
	var hosts: Array[DespawnableEnemy] = []
	for pos: Vector3 in [Vector3(5, 0, 0), Vector3(-5, 0, 0)]:
		var e := DespawnableEnemy.new()
		e.add_to_group(&"enemies")
		world.add_child(e)
		e.global_position = pos
		hosts.append(e)
	var neighbour := _enemy(Vector3(5.5, 0, 0.5))
	var far_neighbour := _enemy(Vector3(-5.5, 0, 0.5))
	EnemyGrid.mark_dirty()
	var aff := WarlockAfflictions.of(p)
	for e in hosts:
		var s := aff.plant_seed(e, 1.0, 6.0, 5.0, 3.0)
		check(s != null, "seeded")
		s.pool_duration = 4.0  # Blighted Ground
		s.pool_radius = 2.0
		check(aff.corrupt(e, 1.0, 8.0, 2, 6.0) != null, "corrupted too")
	# WaveDirector.stop() despawns the host while the afflictions have not ticked yet this frame:
	# the node is still valid and in the tree with HP left, only no longer live.
	var despawned := hosts[0]
	despawned.despawn()
	check(is_instance_valid(despawned) and despawned.is_inside_tree(), "still in the tree this frame")
	check(despawned.hp > 0.0 and not WarlockSpell.is_live(despawned), "alive by HP, but not live")
	# A host taken out of the tree alive (HP left, not yet freed).
	var removed := hosts[1]
	world.remove_child(removed)
	aff._physics_process(DT)
	check_eq(aff.bursts, 0, "no burst over a vanished host")
	check_eq(aff.spreads, 0, "no spread either")
	check_eq(aff.count(), 0, "their afflictions withered")
	for e in [neighbour, far_neighbour]:
		check(not aff.has(WarlockAfflictions.CORRUPTION, e), "nothing jumped to a neighbour")
		check_eq(e.hits.size(), 0, "and nothing hit it")
	check_eq(tree.get_nodes_in_group(&"ability_areas").size(), 0, "no Blighted Ground pool")
	removed.free()


# --- Summon Voidwalker -----------------------------------------------------------------------

func test_voidwalker_is_summoned_and_taunts() -> void:
	var p := _warlock()
	p.stats.set_source(&"t", {Stats.MASTERY: 10.0})
	_learn(p, &"summon_voidwalker")
	var effect := _effect(p, &"summon_voidwalker") as WarlockSummonVoidwalker
	check(not effect.has_pet(), "not before the first tick")
	p.abilities._physics_process(DT)
	check(effect.has_pet(), "summoned on the first tick")
	var pet := effect.pet
	check(pet.get_parent() == world, "next to the warlock (no arena)")
	check(pet.model != null, "has a model")
	var e := _enemy(Vector3(2.5, 0, 0))
	_step(pet, 1.0)
	check(e.is_taunted() and e.taunt_target == pet, "threat aura taunts enemies near it")
	check(pet.global_position.x > 0.8, "steps between the warlock and the threat")
	check(pet.attacks >= 1, "punches")
	var dmg := WarlockVoidwalker.attack_damage(p.stats, _params(p, &"summon_voidwalker"))
	check_near(e.hits[0], dmg * 1.2, 0.001, "pet damage x Demonic Pact")
	check(e.attackers[0] == p, "kill credit")
	p.abilities._physics_process(DT)
	check(effect.pet == pet, "only one voidwalker")


func test_voidwalker_torment_and_specs() -> void:
	var p := _warlock()
	var slot := _learn(p, &"summon_voidwalker", 5, 1)
	var effect := _effect(p, &"summon_voidwalker") as WarlockSummonVoidwalker
	check(not p.abilities.try_cast(slot), "nothing to torment without a pet")
	effect.ensure_pet(_ctx(p, &"summon_voidwalker"))
	var pet := effect.pet
	check(not effect.wants_auto_cast(_ctx(p, &"summon_voidwalker")), "no enemies: no Torment")
	var around: Array[MortalEnemy] = []
	for i in 3:
		around.append(_enemy(pet.global_position + Vector3(2.0 + i, 0, 1.0)))
	var out := _enemy(pet.global_position + Vector3(14, 0, 0))
	check(effect.wants_auto_cast(_ctx(p, &"summon_voidwalker")), "untaunted enemies near it")
	check(p.abilities.try_cast(slot), "Torment")
	for e in around:
		check(e.is_taunted() and e.taunt_target == pet, "taunted onto the voidwalker")
		check_near(e.taunt_left, 3.0, 0.001, "for 3 s")
		check(e.is_slowed(), "Consuming Shadows slows")
		check_eq(e.hits.size(), 1, "Consuming Shadows hurts")
	check(not out.is_taunted(), "out of range")
	check(not effect.wants_auto_cast(_ctx(p, &"summon_voidwalker")), "all taunted already")
	var dmg := WarlockVoidwalker.attack_damage(p.stats, _params(p, &"summon_voidwalker"))
	check_near(around[0].hits[0], dmg * 4.0, 0.001, "4x fist damage")


func test_voidwalker_shared_pain_and_clean_up() -> void:
	var p := _warlock()
	var slot := _learn(p, &"summon_voidwalker", 5, 0)
	var effect := _effect(p, &"summon_voidwalker") as WarlockSummonVoidwalker
	p.abilities._physics_process(DT)
	var pet := effect.pet
	pet._physics_process(DT)
	check_near(float(p.damage_taken_mults.get(WarlockVoidwalker.DAMAGE_REDUCTION_KEY, 1.0)), 0.8, 0.0001,
			"Shared Pain: 20% less damage taken")
	p._go_down()
	pet._physics_process(DT)
	check(pet.is_queued_for_deletion(), "leaves when the warlock goes down")
	check(not p.damage_taken_mults.has(WarlockVoidwalker.DAMAGE_REDUCTION_KEY), "ward removed")
	p.abilities._physics_process(DT)
	check(not effect.has_pet(), "not while downed")
	p.revive()
	p.abilities._physics_process(DT)
	check(effect.has_pet(), "back after the revive")
	pet = effect.pet
	p.end_wave()
	check(pet.is_queued_for_deletion(), "wave end dismisses it")
	p.begin_wave()
	p.abilities._physics_process(DT)
	pet = effect.pet
	check(effect.has_pet(), "summoned again in the new wave")
	p.begin_wave()
	check(pet.is_queued_for_deletion(), "wave start dismisses the old one")
	p.abilities._physics_process(DT)
	pet = effect.pet
	p.abilities.forget(slot)
	check(pet.is_queued_for_deletion(), "forgetting dismisses it")
	# Freed with the warlock.
	var p2 := Fakes.spawn_player(world, 1, &"warlock", Vector3(0, 0, 20))
	_learn(p2, &"summon_voidwalker")
	p2.abilities._physics_process(DT)
	var pet2 := (_effect(p2, &"summon_voidwalker") as WarlockSummonVoidwalker).pet
	p2.free()
	pet2._physics_process(DT)
	check(pet2.is_queued_for_deletion(), "freed with its master")


# --- Fear ------------------------------------------------------------------------------------

func test_fear_sends_enemies_running() -> void:
	var p := _warlock()
	var a := _enemy(Vector3(2, 0, 0))
	var b := _enemy(Vector3(0, 0, -3.5))
	var far := _enemy(Vector3(7, 0, 0))
	var slot := _learn(p, &"fear")
	check_eq(slot, 2, "RB")
	check(p.abilities.try_cast(slot), "cast")
	for e in [a, b]:
		check(e.is_feared(), "feared")
		check_near(e.fear_left, 2.0, 0.001, "2 s")
		check(_marker(e, "Fear") != null, "ghost wisp over it")
	check(not far.is_feared(), "outside the radius")
	check_near(p.abilities.remaining(slot), 14.0, 0.001, "cooldown")
	var effect := _effect(p, &"fear") as WarlockFear
	effect.tick(_ctx(p, &"fear"), 2.1)
	check(_marker(a, "Fear") == null or _marker(a, "Fear").is_queued_for_deletion(), "wisps fade with the fear")
	# Rank II: +25% duration ("power").
	var p2 := Fakes.spawn_player(world, 1, &"warlock", Vector3(0, 0, 30))
	var c := _enemy(Vector3(1, 0, 30))
	var slot2 := _learn(p2, &"fear", 2)
	check(p2.abilities.try_cast(slot2), "rank II cast")
	check_near(c.fear_left, 2.5, 0.001, "2.5 s")


func test_fear_needs_enemies_and_bot_rule() -> void:
	var p := _warlock()
	var slot := _learn(p, &"fear")
	check(not p.abilities.try_cast(slot), "nobody around: no cast")
	check_near(p.abilities.remaining(slot), 0.0, 0.001, "no cooldown spent")
	var effect := _effect(p, &"fear")
	_enemy(Vector3(2, 0, 0))
	check(not effect.wants_auto_cast(_ctx(p, &"fear")), "one enemy at full HP: no")
	p.hp = p.max_hp() * 0.3
	check(effect.wants_auto_cast(_ctx(p, &"fear")), "hurt: yes")
	p.hp = p.max_hp()
	for i in 3:
		_enemy(Vector3(-2, 0, 0.5 * i))
	check(effect.wants_auto_cast(_ctx(p, &"fear")), "four around: yes")


func test_fear_specs_dread_and_cower() -> void:
	var p := _warlock()
	p.stats.set_source(&"t", {Stats.MASTERY: 10.0})
	var e := _enemy(Vector3(2, 0, 0))
	var slot := _learn(p, &"fear", 5, 0)
	check(p.abilities.try_cast(slot), "Dread")
	var aff := _aff(p)
	check(aff != null and aff.has(WarlockAfflictions.DREAD, e), "afraid enemies wither")
	var rate := WarlockFear.dread_rate(p.stats, _params(p, &"fear"))
	check(rate > 0.0, "dread rate")
	# Rank V power (1.5) makes the fear last longer; the damage per second stays unranked, so
	# the whole Dread grows with power once (like Radiant Bubble), not with power squared.
	check_near(e.fear_left, 2.0 * 1.5, 0.001, "Rank V: the fear lasts 2 s x power")
	var per_second := (3.0 + 0.4 * p.stats.get_raw(Stats.INTELLECT) + 1.0 * p.stats.get_raw(Stats.SPELL_POWER)) \
			* CombatMath.damage_mult_for(p.stats, &"shadow")
	check_near(rate, per_second, 0.001, "Dread per second: 3 + 40% Int + 100% SP, not x power")
	_step(aff, 0.5)
	check_near(e.hits[0], rate * 0.5 * 1.2, 0.001, "a DoT: Demonic Pact applies")
	_step(aff, 3.0)
	check_near(e.total(), per_second * 3.0 * 1.2, 0.01, "the whole fear: 3 s of Dread")
	check(not aff.has(WarlockAfflictions.DREAD, e), "ends with the fear")
	var p2 := Fakes.spawn_player(world, 1, &"warlock", Vector3(0, 0, 30))
	var c := _enemy(Vector3(1, 0, 30))
	var slot2 := _learn(p2, &"fear", 5, 1)
	check(p2.abilities.try_cast(slot2), "Cower")
	check(not c.is_feared(), "does not run")
	check(c.is_stunned(), "freezes")
	var expected := WarlockFear.fear_duration(_params(p2, &"fear")) + 0.5
	check_near(c.stun_left, expected, 0.001, "stunned for the fear + 0.5 s")


# --- Summon Infernal -------------------------------------------------------------------------

func test_infernal_lands_stuns_and_smashes() -> void:
	var p := _warlock()
	p.stats.set_source(&"t", {Stats.MASTERY: 10.0})
	var group: Array[MortalEnemy] = []
	for i in 5:
		group.append(_enemy(Vector3(6.0 + 0.5 * i, 0, 0.4 * (i % 2))))
	var lone := _enemy(Vector3(-9, 0, 0))
	var slot := _learn(p, &"summon_infernal")
	check_eq(slot, 2, "RB")
	var shards := p.abilities.get_resource(&"soul_shard")
	shards.set_value(1.0)
	var effect := _effect(p, &"summon_infernal") as WarlockSummonInfernal
	check(effect.wants_auto_cast(_ctx(p, &"summon_infernal")), "bots: 5 in the circle")
	check(p.abilities.try_cast(slot), "cast")
	check_eq(shards.value, 0.0, "1 shard spent")
	check(effect.has_infernal(), "summoned")
	var inf := effect.infernal
	check(not inf.landed, "falling")
	check(inf.global_position.x > 5.0, "on the group")
	_step(inf, WarlockInfernal.FALL_TIME + DT)
	check(inf.landed, "landed")
	var impact := WarlockInfernal.impact_damage(p.stats, _params(p, &"summon_infernal"))
	for e in group:
		check(e.hits.size() >= 1, "landing burst hits the group")
		check_near(e.hits[0], impact * 1.2, 0.001, "pet damage x Demonic Pact")
		check(e.is_stunned(), "stunned")
	check_eq(lone.hits.size(), 0, "not the lone one")
	_step(inf, 2.0)
	check(inf.slams >= 1, "smashes")
	var slam := WarlockInfernal.slam_damage(p.stats, _params(p, &"summon_infernal"))
	check_near(group[0].hits[1], slam * 1.2, 0.001, "slam damage")
	check(not effect.can_cast(_ctx(p, &"summon_infernal")), "one at a time")
	_step(inf, 8.0)
	check(inf.is_queued_for_deletion(), "crumbles after 8 s")


func test_infernal_needs_a_target_and_cleans_up() -> void:
	var p := _warlock()
	var slot := _learn(p, &"summon_infernal")
	var shards := p.abilities.get_resource(&"soul_shard")
	shards.set_value(2.0)
	check(not p.abilities.try_cast(slot), "no enemies: no cast")
	check_eq(shards.value, 2.0, "shard kept")
	_enemy(Vector3(5, 0, 0))
	check(p.abilities.try_cast(slot), "cast")
	var effect := _effect(p, &"summon_infernal") as WarlockSummonInfernal
	var inf := effect.infernal
	p._go_down()
	inf._physics_process(DT)
	check(inf.is_queued_for_deletion(), "leaves when the warlock goes down")
	p.revive()
	p.abilities.set_cooldown(_ability(&"summon_infernal"), 0.0)
	check(p.abilities.try_cast(slot), "cast again")
	inf = effect.infernal
	p.end_wave()
	check(inf.is_queued_for_deletion(), "wave end dismisses it")


func test_infernal_specs() -> void:
	var p := _warlock()
	var e := _enemy(Vector3(5, 0, 0))
	var slot := _learn(p, &"summon_infernal", 5, 0)
	p.abilities.get_resource(&"soul_shard").set_value(1.0)
	check(p.abilities.try_cast(slot), "Immolation")
	var inf := (_effect(p, &"summon_infernal") as WarlockSummonInfernal).infernal
	check_near(inf.time_left, 11.0, 0.001, "Rank III: 11 s")
	_step(inf, WarlockInfernal.FALL_TIME + DT)
	var slam := WarlockInfernal.slam_damage(p.stats, _params(p, &"summon_infernal"))
	var before := e.hits.size()
	_step(inf, 1.1)
	var burns := 0
	for i in range(before, e.hits.size()):
		if is_equal_approx(e.hits[i], slam * 0.3):
			burns += 1
	check(burns >= 2, "burns every 0.5 s (%d)" % burns)
	var p2 := Fakes.spawn_player(world, 1, &"warlock", Vector3(0, 0, 30))
	var near := _enemy(Vector3(3, 0, 30))
	var slot2 := _learn(p2, &"summon_infernal", 5, 1)
	p2.abilities.get_resource(&"soul_shard").set_value(1.0)
	check(p2.abilities.try_cast(slot2), "Abyssal Guardian")
	var inf2 := (_effect(p2, &"summon_infernal") as WarlockSummonInfernal).infernal
	check_near(inf2.time_left, 13.0, 0.001, "11 + 2 s")
	var further := _enemy(inf2.global_position + Vector3(4.5, 0, 0))
	_step(inf2, WarlockInfernal.FALL_TIME + 0.2)
	check(further.is_taunted() and further.taunt_target == inf2, "draws enemies to itself")
	check(near.is_taunted(), "the one it landed on too")


# --- Core abilities: ranks and specs ---------------------------------------------------------

func test_rain_of_fire_power_rank3_and_specs() -> void:
	var p := _warlock()
	for i in 4:
		_enemy(Vector3(6.0 + 0.6 * i, 0, 0.5 * (i % 2)))
	var base := WarlockRainOfFire.tick_damage(p.stats, _ability(&"rain_of_fire").params)
	p.abilities.rank_up(&"rain_of_fire")
	p.abilities.rank_up(&"rain_of_fire")
	var params := p.abilities.params_for(p.abilities.slots[0])
	check_near(WarlockRainOfFire.tick_damage(p.stats, params), base * 1.25, 0.001, "Rank II: +25%")
	p.abilities.get_resource(&"soul_shard").set_value(1.0)
	check(p.abilities.try_cast(0), "cast")
	var area := tree.get_nodes_in_group(&"ability_areas")[0] as AbilityArea
	check_near(area.radius, 4.0, 0.001, "Rank III: +1 m")
	area.free()
	# Walking Inferno: on the warlock, following it.
	p.abilities.rank_up(&"rain_of_fire")
	p.abilities.rank_up(&"rain_of_fire")
	check(p.abilities.set_spec(&"rain_of_fire", 0), "Walking Inferno")
	p.abilities.get_resource(&"soul_shard").set_value(1.0)
	check(p.abilities.try_cast(0), "cast")
	area = tree.get_nodes_in_group(&"ability_areas")[0] as AbilityArea
	check(area.follow == p, "follows the warlock")
	check_near(area.global_position.x, 0.0, 0.001, "centred on the warlock")
	check_near(area.duration, 5.0, 0.001, "+1 s")
	area.free()
	# Twin Storms: a second circle on another group.
	var p2 := Fakes.spawn_player(world, 1, &"warlock", Vector3(0, 0, 40))
	for i in 4:
		_enemy(Vector3(6.0 + 0.6 * i, 0, 40.0 + 0.5 * (i % 2)))
	for i in 3:
		_enemy(Vector3(-6.0 - 0.6 * i, 0, 40.0))
	for i in 4:
		p2.abilities.rank_up(&"rain_of_fire")
	check(p2.abilities.set_spec(&"rain_of_fire", 1), "Twin Storms")
	p2.abilities.get_resource(&"soul_shard").set_value(1.0)
	check(p2.abilities.try_cast(0), "cast")
	var areas := tree.get_nodes_in_group(&"ability_areas")
	check_eq(areas.size(), 2, "two circles")
	if areas.size() == 2:
		var xs := [(areas[0] as Node3D).global_position.x, (areas[1] as Node3D).global_position.x]
		check(xs.max() > 4.0 and xs.min() < -4.0, "one on each group %s" % [xs])


func test_drain_life_power_soul_siphon_and_dark_bargain() -> void:
	var p := _warlock()
	var base := WarlockDrainLife.tick_damage(p.stats, _ability(&"drain_life").params)
	for i in 4:
		p.abilities.rank_up(&"drain_life")
	var params := p.abilities.params_for(p.abilities.slots[1])
	check_near(WarlockDrainLife.tick_damage(p.stats, params), base * 1.5, 0.001, "Ranks II + IV: +50%")
	check_near(float(params["duration"]), 3.0, 0.001, "Rank III: +1 s")
	check(p.abilities.set_spec(&"drain_life", 0), "Soul Siphon")
	var enemies: Array[MortalEnemy] = []
	for i in 4:
		enemies.append(_enemy(Vector3(2.0 + i, 0, 0)))
	p.hp = 2.0
	check(p.abilities.try_cast(1), "cast")
	var effect := p.abilities.effect_for(p.abilities.slots[1]) as WarlockDrainLife
	check_eq(effect.targets.size(), 3, "three enemies drained")
	check_eq(effect.beams.size(), 3, "three beams")
	_step(p.abilities, 0.45)
	for i in 3:
		check_eq(enemies[i].hits.size(), 1, "enemy %d drained" % i)
	check_eq(enemies[3].hits.size(), 0, "only three")
	effect.stop()
	check(effect.beams.is_empty() and effect.beam == null, "beams released")
	# Dark Bargain: overhealing becomes a shield.
	var p2 := Fakes.spawn_player(world, 1, &"warlock", Vector3(0, 0, 30))
	_enemy(Vector3(2, 0, 30))
	for i in 4:
		p2.abilities.rank_up(&"drain_life")
	check(p2.abilities.set_spec(&"drain_life", 1), "Dark Bargain")
	p2.hp = p2.max_hp()
	check(p2.abilities.try_cast(1), "cast at full health")
	_step(p2.abilities, 0.45)
	var effect2 := p2.abilities.effect_for(p2.abilities.slots[1]) as WarlockDrainLife
	check(effect2.shield_total > 0.0, "overheal became a shield")
	check_near(p2.procs.shield_hp, effect2.shield_total, 0.001, "on the warlock")
	_step(p2.abilities, 3.0)
	check(p2.procs.shield_hp <= p2.max_hp() * 0.5 + 0.001, "capped at 50% Max HP")


func test_rain_of_fire_bots_keep_the_last_shard_for_the_infernal() -> void:
	var p := _warlock()
	for i in 4:
		_enemy(Vector3(6.0 + 0.6 * i, 0, 0.5 * (i % 2)))
	var shards := p.abilities.get_resource(&"soul_shard")
	shards.set_value(1.0)
	var rof := p.abilities.effect_for(p.abilities.slots[0])
	check(rof.wants_auto_cast(p.abilities.build_context(p.abilities.slots[0])), "no infernal: rain")
	var slot := _learn(p, &"summon_infernal")
	check(not rof.wants_auto_cast(p.abilities.build_context(p.abilities.slots[0])), "ready infernal: keep the shard")
	check(not _effect(p, &"summon_infernal").wants_auto_cast(_ctx(p, &"summon_infernal")), "4 is too few for the infernal")
	_enemy(Vector3(6.8, 0, -0.5))
	check(_effect(p, &"summon_infernal").wants_auto_cast(_ctx(p, &"summon_infernal")), "5: infernal")
	shards.set_value(2.0)
	check(rof.wants_auto_cast(p.abilities.build_context(p.abilities.slots[0])), "two shards: both")
	shards.set_value(1.0)
	p.abilities.set_cooldown(_ability(&"summon_infernal"), 30.0)
	check(p.abilities.remaining(slot) > 0.0, "infernal on cooldown")
	check(rof.wants_auto_cast(p.abilities.build_context(p.abilities.slots[0])), "infernal on cooldown: rain")
