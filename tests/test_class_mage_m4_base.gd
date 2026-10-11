extends TestCase
## Shared helpers of the Mage M4 tests (test_class_mage_m4*.gd): a Mage, fake enemies,
## learning / ranking abilities and a stepper for everything the spells leave in the world
## (bolts, burns, ice, meteors, ground areas). No tests of its own.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 4711)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


func _mage(pos: Vector3 = Vector3.ZERO, index: int = 0) -> Player:
	var p := Fakes.spawn_player(world, index, &"mage", pos)
	p.abilities._physics_process(DT)  # first tick: Mana follows Intellect
	return p


func _enemy(pos: Vector3, hp: float = 1000.0) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	e.hp = hp
	e.max_hp = maxf(hp, 1.0)
	EnemyGrid.mark_dirty()
	return e


## [param count] enemies packed around [param center].
func _cluster(center: Vector3, count: int, spread: float = 0.8) -> Array[Fakes.FakeEnemy]:
	var out: Array[Fakes.FakeEnemy] = []
	for i in count:
		var a := TAU * float(i) / float(maxi(1, count))
		out.append(_enemy(center + Vector3(cos(a), 0.0, sin(a)) * spread))
	return out


## Learns [param id] (Rank I) and raises it to [param rank]; [param spec] at Rank V.
## Core abilities (already slotted) are only ranked. Returns the slot.
func _learn(p: Player, id: StringName, rank: int = 1, spec: int = -1) -> int:
	var r := p.abilities
	var slot := r.slot_of(id)
	if slot < 0:
		slot = r.learn(Db.get_ability(id))
	check(slot >= 0, "learned %s" % id)
	while r.rank_of(id) < rank:
		check(r.rank_up(id), "rank up %s" % id)
	if spec >= 0:
		check(r.set_spec(id, spec), "spec %d of %s" % [spec, id])
	return slot


func _ability(id: StringName) -> AbilityData:
	return Db.get_ability(id)


func _ctx(p: Player, id: StringName) -> AbilityContext:
	return p.abilities.build_context(_ability(id))


func _effect(p: Player, id: StringName) -> AbilityEffect:
	return p.abilities.effect_for(_ability(id))


func _total(e: Fakes.FakeEnemy) -> float:
	var sum := 0.0
	for d in e.fake_damage_log:
		sum += d
	return sum


func _bolts() -> Array[MageBolt]:
	var out: Array[MageBolt] = []
	for n in tree.get_nodes_in_group(&"projectiles"):
		if n is MageBolt and not n.is_queued_for_deletion():
			out.append(n)
	return out


func _areas() -> Array[AbilityArea]:
	var out: Array[AbilityArea] = []
	for n in tree.get_nodes_in_group(&"ability_areas"):
		if n is AbilityArea and not n.is_queued_for_deletion():
			out.append(n)
	return out


func _strikes() -> Array[MageMeteorStrike]:
	var out: Array[MageMeteorStrike] = []
	for n in tree.get_nodes_in_group(&"ability_areas"):
		if n is MageMeteorStrike and not n.is_queued_for_deletion():
			out.append(n)
	return out


func _ice(e: Enemy, p: Player) -> MageFrozen:
	var ice := e.get_node_or_null(NodePath("MageFrozen%d" % p.get_instance_id())) as MageFrozen
	return ice if ice != null and not ice.is_queued_for_deletion() else null


## Steps the world by [param seconds]: bolts, burns, ice, meteors, ground areas – and the
## players' ability runners when [param runners] (auto-cast, wind-ups, volleys).
func _step(seconds: float, runners: Array[Player] = []) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		for p in runners:
			p.abilities._physics_process(DT)
		for n in tree.get_nodes_in_group(&"projectiles"):
			if not n.is_queued_for_deletion():
				n._physics_process(DT)
		for n in tree.get_nodes_in_group(&"enemies"):
			for c in n.get_children():
				if (c is MageBurn or c is MageFrozen) and not c.is_queued_for_deletion():
					c._physics_process(DT)
		for n in tree.get_nodes_in_group(&"ability_areas"):
			if not n.is_queued_for_deletion():
				n._physics_process(DT)
		t += DT


## Steps until every Mage bolt has landed (at most [param limit] seconds).
func _fly(limit: float = 3.0) -> void:
	var t := 0.0
	while not _bolts().is_empty() and t < limit:
		_step(DT)
		t += DT


## Entries of [param e]'s damage log equal to [param amount] (direct hits, not burn ticks).
func _count(e: Fakes.FakeEnemy, amount: float) -> int:
	var n := 0
	for d in e.fake_damage_log:
		if absf(d - amount) <= 0.001:
			n += 1
	return n


## Spell damage the way MageSpell computes it for [param p]: ([param base] + [param int_scale]
## x Intellect + [param sp] x Spell Power) x school / Versatility % x [param power].
func _spell(p: Player, base: float, int_scale: float, school: StringName, power: float = 1.0,
		sp: float = 1.0) -> float:
	var flat := base + int_scale * p.stats.get_raw(Stats.INTELLECT) + sp * p.stats.get_raw(Stats.SPELL_POWER)
	return maxf(CombatMath.MIN_DAMAGE, flat * CombatMath.damage_mult_for(p.stats, school)) * power


## Gives [param p] a big HP pool (survives hits that break a shield).
func _tough(p: Player) -> void:
	p.stats.set_source(&"test_tough", {Stats.STAMINA: 5000.0})
	p.hp = p.max_hp()


## Knocks [param p] down (lethal hit).
func _down(p: Player) -> void:
	p.invulnerable_left = 0.0
	p.procs.shield_hp = 0.0
	p.take_damage(10000.0)
	check(p.downed, "downed")
