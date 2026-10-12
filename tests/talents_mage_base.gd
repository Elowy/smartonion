extends TestCase
## Shared helpers of the Mage talent tests (test_talents_mage_*.gd, M5, talents_mage.md 6): a
## real Mage with 22 talent points (team level 31), fake enemies, talent spending through
## player.talents (the real TalentState -> PlayerBonuses path), learning abilities and a
## stepper for everything the Mage leaves in the world (bolts, burns, ice, areas, Mirror
## Images). Not a test file itself (no test_ prefix).

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0

## The 12 points that open each capstone (the bot order, without the modifier).
const ARCANE_12: Array[Array] = [["mage_arcane_arcane_focus", 3], ["mage_arcane_arcane_meditation", 3],
	["mage_arcane_improved_blink", 3], ["mage_arcane_arcane_concentration", 3]]
const FIRE_12: Array[Array] = [["mage_fire_critical_mass", 3], ["mage_fire_fire_power", 3],
	["mage_fire_empowered_fire", 3], ["mage_fire_incineration", 3]]
const FROST_12: Array[Array] = [["mage_frost_piercing_ice", 3], ["mage_frost_ice_armor", 3],
	["mage_frost_improved_blizzard", 3], ["mage_frost_winters_chill", 3]]


## A fake boss (Mirror Image does not lure bosses).
class FakeBoss extends Fakes.FakeEnemy:
	func is_boss() -> bool:
		return true

	func is_elite() -> bool:
		return true


var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 4242)
	RunState.set_start_level(31)
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


## Adds [param n] points to [param id] (each must succeed).
func _add(p: Player, id: String, n: int = 1) -> void:
	for i in n:
		check(p.talents.add(StringName(id)), "add %s: %s" % [id, p.talents.add_block_reason(StringName(id))])


## Adds every [id, points] pair of [param plan].
func _plan(p: Player, plan: Array[Array]) -> void:
	for step in plan:
		_add(p, String(step[0]), int(step[1]))


## Takes [param n] pending points of [param id] back (each must succeed).
func _remove(p: Player, id: String, n: int = 1) -> void:
	for i in n:
		check(p.talents.remove(StringName(id)), "remove %s: %s" % [id, p.talents.remove_block_reason(StringName(id))])


func _ability(id: StringName) -> AbilityData:
	return Db.get_ability(id)


func _params(p: Player, id: StringName) -> Dictionary:
	return p.abilities.params_for(_ability(id))


func _effect(p: Player, id: StringName) -> AbilityEffect:
	return p.abilities.effect_for(_ability(id))


## Learns [param id] (Rank I; core abilities are already slotted). Returns the slot.
func _learn(p: Player, id: StringName) -> int:
	var slot := p.abilities.slot_of(id)
	if slot < 0:
		slot = p.abilities.learn(_ability(id))
	check(slot >= 0, "learned %s" % id)
	return slot


func _move(p: Player, v: Vector2) -> void:
	(p.slot.input as ScriptedInput).move = v


func _total(e: Fakes.FakeEnemy) -> float:
	var sum := 0.0
	for d in e.fake_damage_log:
		sum += d
	return sum


func _ice(e: Enemy, p: Player) -> MageFrozen:
	var ice := e.get_node_or_null(NodePath("MageFrozen%d" % p.get_instance_id())) as MageFrozen
	return ice if ice != null and not ice.is_queued_for_deletion() else null


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


## Steps the world by [param seconds]: projectiles, burns, ice, Mirror Images, ground areas –
## and the players' ability runners when [param runners] (effect ticks, auto-casts).
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
		for n in tree.get_nodes_in_group(MageMirrorImage.GROUP):
			if not n.is_queued_for_deletion():
				n._physics_process(DT)
		for n in tree.get_nodes_in_group(&"ability_areas"):
			if not n.is_queued_for_deletion():
				n._physics_process(DT)
		t += DT


## Steps until every Mage bolt / weapon projectile has landed (at most [param limit] s).
func _fly(limit: float = 3.0) -> void:
	var t := 0.0
	while t < limit:
		var flying := false
		for n in tree.get_nodes_in_group(&"projectiles"):
			if not n.is_queued_for_deletion():
				flying = true
		if not flying:
			return
		_step(DT)
		t += DT


## Spell damage the way MageSpell computes it for [param p] (before the outgoing multipliers).
func _spell(p: Player, base: float, int_scale: float, school: StringName, power: float = 1.0,
		sp: float = 1.0) -> float:
	var flat := base + int_scale * p.stats.get_raw(Stats.INTELLECT) + sp * p.stats.get_raw(Stats.SPELL_POWER)
	return maxf(CombatMath.MIN_DAMAGE, flat * CombatMath.damage_mult_for(p.stats, school)) * power


## Gives [param p] a big HP pool.
func _tough(p: Player) -> void:
	p.stats.set_source(&"test_tough", {Stats.STAMINA: 5000.0})
	p.hp = p.max_hp()


## Knocks [param p] down (lethal hit).
func _down(p: Player) -> void:
	p.invulnerable_left = 0.0
	p.procs.clear_shields()
	p.take_damage(100000.0)
	check(p.downed, "downed")


## True when the RNG state is unchanged since [param state].
func _rng_untouched(state: int) -> bool:
	return RunState.rng.state == state


## The RNG state after [param draws] randf() calls from [param state] (the state is restored).
func _state_after(state: int, draws: int) -> int:
	var saved := RunState.rng.state
	RunState.rng.state = state
	for i in draws:
		RunState.rng.randf()
	var out := RunState.rng.state
	RunState.rng.state = saved
	return out
