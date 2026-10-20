extends TestCase
## Shared helpers of the Shaman tests (test_class_shaman*.gd): a Shaman (and allies) in a fake world, enemies
## that record their hits, learning / ranking abilities, bonus entries standing in for talents and a stepper for
## everything the kit leaves in the world (totems, areas, burns, wolves). No tests of its own.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

## The six learned abilities and the two core ones (bare ids, files carry the class prefix).
const CORE: Array[StringName] = [&"forking_bolt", &"totem_rite"]
const LEARNED: Array[StringName] = [
	&"thunderbolt", &"rumbling_earth", &"magma_lash", &"soothing_downpour", &"stormburst", &"spirit_pack",
]


## An enemy that really dies at 0 HP (Fakes.FakeEnemy only dies when told to) and counts its slows.
class Mortal extends Fakes.FakeEnemy:
	var slows: Array[float] = []
	var stuns: Array[float] = []

	func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null,
			knockback: Vector3 = Vector3.ZERO) -> void:
		super.take_damage(amount, is_crit, attacker, knockback)
		if hp <= 0.0:
			fake_dead = true

	func apply_stun(duration: float) -> void:
		super.apply_stun(duration)
		stuns.append(duration)

	func apply_slow(pct: float, duration: float) -> void:
		slows.append(pct)
		super.apply_slow(pct, duration)

	func total() -> float:
		var t := 0.0
		for v in fake_damage_log:
			t += v
		return t


var world: Node3D


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 4711)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)
	EnemyGrid.mark_dirty()


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	PlayerManager.clear()
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


## A Shaman with no Mastery of its own (Fakes drops the base source) after its first ability tick (hooks the
## cast signal like the first physics frame of a real run).
func _shaman(pos: Vector3 = Vector3.ZERO, index: int = 0) -> Player:
	var p := Fakes.spawn_player(world, index, &"shaman", pos)
	p.abilities._physics_process(DT)
	return p


func _ally(index: int, pos: Vector3, class_id: StringName = &"warrior") -> Player:
	return Fakes.spawn_player(world, index, class_id, pos)


func _enemy(pos: Vector3, hp: float = 100000.0) -> Mortal:
	var e := Mortal.new()
	e.radius = 0.45
	e.hp = hp
	e.max_hp = maxf(hp, 1.0)
	e.add_to_group(&"enemies")
	world.add_child(e)
	e.global_position = pos
	EnemyGrid.mark_dirty()
	return e


## [param count] enemies packed around [param center].
func _cluster(center: Vector3, count: int, spread: float = 0.8) -> Array[Mortal]:
	var out: Array[Mortal] = []
	for i in count:
		var a := TAU * float(i) / float(maxi(1, count))
		out.append(_enemy(center + Vector3(cos(a), 0.0, sin(a)) * spread))
	return out


## Learns [param id] (Rank I) and raises it to [param rank] ([param spec] at Rank V); core abilities are only
## ranked. Returns the slot.
func _learn(p: Player, id: StringName, rank: int = 1, spec: int = -1) -> int:
	var r := p.abilities
	var slot := r.slot_of(id)
	if slot < 0:
		slot = r.learn(Db.get_ability(id))
	check(slot >= 0, "learned %s" % id)
	if slot < 0:
		return -1
	while r.rank_of(id) < rank:
		check(r.rank_up(id), "rank up %s" % id)
	if spec >= 0:
		check(r.set_spec(id, spec), "spec %d of %s" % [spec, id])
	return slot


func _effect(p: Player, id: StringName) -> AbilityEffect:
	return p.abilities.effect_for(Db.get_ability(id))


## The typed effects (the base type has no accessors of the kit's own).
func _fx_rite(p: Player) -> ShamanTotemRite:
	return _effect(p, &"totem_rite") as ShamanTotemRite


func _fx_quake(p: Player) -> ShamanRumblingEarth:
	return _effect(p, &"rumbling_earth") as ShamanRumblingEarth


func _fx_lash(p: Player) -> ShamanMagmaLash:
	return _effect(p, &"magma_lash") as ShamanMagmaLash


func _fx_rain(p: Player) -> ShamanSoothingDownpour:
	return _effect(p, &"soothing_downpour") as ShamanSoothingDownpour


func _fx_pack(p: Player) -> ShamanSpiritPack:
	return _effect(p, &"spirit_pack") as ShamanSpiritPack


func _ctx(p: Player, id: StringName) -> AbilityContext:
	return p.abilities.build_context(Db.get_ability(id))


## Casts [param id] through the runner's slot (cost, cooldown, the ability_cast signal) like a button press.
func _cast(p: Player, id: StringName) -> bool:
	return p.abilities.try_cast(p.abilities.slot_of(id))


## The Shaman's Surge resource.
func _surge(p: Player) -> ClassResource:
	return p.abilities.get_resource(&"surge")


func _mastery(p: Player) -> ShamanMastery:
	return p.abilities.mastery as ShamanMastery


## Runs the hero's frame and abilities for [param seconds] ([param nodes_to_step]: extra nodes that are stepped
## by hand because Fakes worlds are not processed: totems, areas, burns, wolves).
func _run(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p._physics_process(DT)
		p.abilities._physics_process(DT)
		_step_world(DT)
		t += DT


## Steps every totem, area, burn and wolf in the world once ([param delta] s).
func _step_world(delta: float) -> void:
	for node in tree.get_nodes_in_group(&"shaman_totems"):
		(node as ShamanTotem).step(delta)
	for child in world.get_children():
		if child is AbilityArea and not child.is_queued_for_deletion():
			(child as AbilityArea)._physics_process(delta)
		elif child is ShamanWolf and not child.is_queued_for_deletion():
			(child as ShamanWolf).step(delta)
		elif child is Enemy:
			for sub in child.get_children():
				if sub is ShamanBurn and not sub.is_queued_for_deletion():
					(sub as ShamanBurn)._physics_process(delta)


func _flat_dist(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


## Replaces the talent entries of [param p] (stand-ins for the later talent trees).
func _put(p: Player, entries: Array) -> void:
	var typed: Array[Dictionary] = []
	typed.assign(entries)
	p.bonuses.set_effects(PlayerBonuses.SOURCE_TALENTS, typed)


## Damage entries of one source: {"kind": "damage", "pct": ..., "source": ...}.
func _boost(p: Player, source: String, pct: float = 100.0) -> void:
	_put(p, [{"kind": "damage", "pct": pct, "source": source, "rank": 1}])


## Puts [param id]'s Surge cost aside: fills the pool.
func _full_surge(p: Player) -> void:
	_surge(p).set_value(_surge(p).max_value())


func _down(p: Player) -> void:
	p.invulnerable_left = 0.0
	p.hp = 1.0
	p.take_damage(1000.0)
