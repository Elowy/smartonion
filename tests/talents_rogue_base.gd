extends TestCase
## Shared helpers of the Rogue talent tests (M5 Wave 2, talents_rogue.md §6):
## test_talents_rogue_assassination.gd, test_talents_rogue_combat.gd,
## test_talents_rogue_subtlety.gd extend this file. Not a test file itself (no test_ prefix).
## Real Rogues (tests/player_fakes.gd) take their talents through player.talents.add ->
## PlayerBonuses; crits and dodges are switched off by a test stat source unless a test asks.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0
## Stat source that keeps crits / dodges out of the way (tests set their own numbers).
const QUIET := &"test_quiet"

var world: Node3D


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 4242)
	RunState.set_start_level(31)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	PlayerManager.clear()
	EnemyGrid.mark_dirty()


## A Rogue (slot [param index]) without random crits / dodges.
func _rogue(index: int = 0, pos: Vector3 = Vector3.ZERO) -> Player:
	var p := Fakes.spawn_player(world, index, &"rogue", pos)
	p.stats.set_source(QUIET, {Stats.CRIT: -500.0, Stats.DODGE: -500.0})
	p.facing = Vector3.FORWARD
	return p


## Adds [param n] ranks of "rogue_<tree>_<short>" (checks each one).
func _add(p: Player, tree_id: String, short: String, n: int = 1) -> void:
	var id := StringName("rogue_%s_%s" % [tree_id, short])
	for i in n:
		check(p.talents.add(id), "add %s: %s" % [id, p.talents.add_block_reason(id)])


func _remove(p: Player, tree_id: String, short: String, n: int = 1) -> void:
	var id := StringName("rogue_%s_%s" % [tree_id, short])
	for i in n:
		check(p.talents.remove(id), "remove %s: %s" % [id, p.talents.remove_block_reason(id)])


## Reset Talents (paid from a fresh purse).
func _reset(p: Player) -> void:
	RunState.add_gold(1000)
	check(p.talents.try_reset(p.slot.index), "Reset Talents")


func _talent(id: StringName) -> TalentData:
	return Db.get_talent(id)


func _energy(p: Player) -> ClassResource:
	return p.abilities.get_resource(&"energy")


func _combo(p: Player) -> ClassResource:
	return p.abilities.get_resource(&"combo_points")


func _mastery(p: Player) -> RogueMastery:
	return p.abilities.mastery as RogueMastery


func _fan(p: Player) -> AbilityData:
	return Db.get_ability(&"fan_of_knives")


func _vanish(p: Player) -> AbilityData:
	return Db.get_ability(&"vanish")


func _vanish_effect(p: Player) -> RogueVanish:
	return RogueVanish.of(p)


## Live RogueBlades of [param p].
func _knives(p: Player) -> Array[RogueBlade]:
	var out: Array[RogueBlade] = []
	for node in tree.get_nodes_in_group(&"projectiles"):
		var b := node as RogueBlade
		if b != null and b.attacker == p and not b.is_queued_for_deletion() and not b.is_done():
			out.append(b)
	return out


## Every RogueBlade of [param p] (also finished ones not freed yet).
func _all_knives(p: Player) -> Array[RogueBlade]:
	var out: Array[RogueBlade] = []
	for node in tree.get_nodes_in_group(&"projectiles"):
		var b := node as RogueBlade
		if b != null and b.attacker == p:
			out.append(b)
	return out


## Frees every blade (so the next fan's knives are counted alone).
func _clear_knives() -> void:
	for node in tree.get_nodes_in_group(&"projectiles"):
		node.get_parent().remove_child(node)
		node.free()


## Lets the thrown blades fly for [param seconds].
func _fly(p: Player, seconds: float = 0.7) -> void:
	var t := 0.0
	while t < seconds:
		for k in _knives(p):
			k.advance(DT)
		t += DT


## Casts Fan of Knives (Energy topped up first) and returns its knives.
func _throw_fan(p: Player) -> Array[RogueBlade]:
	_clear_knives()
	_energy(p).set_value(100.0)
	check(p.abilities.try_cast(0), "Knife Bloom cast")
	return _knives(p)


## Enemies standing on a ring of [param distance] m around [param center].
func _surround(count: int, distance: float, center: Vector3 = Vector3.ZERO) -> Array[Fakes.FakeEnemy]:
	var out: Array[Fakes.FakeEnemy] = []
	for i in count:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(i) / float(count))
		out.append(Fakes.spawn_enemy(world, center + dir * distance))
	EnemyGrid.mark_dirty()
	return out


func _clear_enemies() -> void:
	for node in tree.get_nodes_in_group(&"enemies"):
		node.get_parent().remove_child(node)
		node.free()
	EnemyGrid.mark_dirty()


## The talent / set procs of [param p] built from talent [param talent_id].
func _procs_of(p: Player, talent_id: StringName) -> Array[ProcSystem.Proc]:
	var out: Array[ProcSystem.Proc] = []
	for proc in p.procs.procs:
		if proc.id == talent_id:
			out.append(proc)
	return out


## Test override: the procs of [param talent_id] always fire (chance 100%).
func _force_procs(p: Player, talent_id: StringName) -> void:
	var list := _procs_of(p, talent_id)
	check(not list.is_empty(), "%s has a proc" % talent_id)
	for proc in list:
		proc.chance = 100.0


## Steps the hero's Player / AbilityRunner / ProcSystem physics for [param seconds].
func _step(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p.abilities._physics_process(DT)
		p.procs._physics_process(DT)
		p._physics_process(DT)
		t += DT
