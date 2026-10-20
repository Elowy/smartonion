extends TestCase
## Shared helpers of the Hunter talent tests (M8 TALENTS-H, design_hunter 4): test_talents_hunter_packlord.gd,
## test_talents_hunter_sharpshot.gd and test_talents_hunter_wildcraft.gd extend this file. Not a test
## file itself (no test_ prefix). Real Hunters (tests/player_fakes.gd) take their talents through
## player.talents.add -> PlayerBonuses; crits and dodges are switched off by a test stat source unless a
## test asks. The Hunter's base Mastery is removed by the fake spawner (exact numbers).

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0
## Stat source that keeps crits / dodges out of the way (tests set their own numbers).
const QUIET := &"test_quiet"
const PET_MOD := &"hunter_companion"

## An enemy that dies when its health runs out (the plain fake only records hits).
class MortalEnemy extends Fakes.FakeEnemy:
	func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null,
			knockback: Vector3 = Vector3.ZERO) -> void:
		super.take_damage(amount, is_crit, attacker, knockback)
		if hp <= 0.0:
			fake_dead = true

var world: Node3D


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 4343)
	RunState.set_start_level(31)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	PlayerManager.clear()
	EnemyGrid.mark_dirty()


# --- Heroes and enemies -------------------------------------------------------------------------

## A Hunter (slot [param index]) without random crits / dodges.
func _hunter(index: int = 0, pos: Vector3 = Vector3.ZERO) -> Player:
	var p := Fakes.spawn_player(world, index, &"hunter", pos)
	p.stats.set_source(QUIET, {Stats.CRIT: -500.0, Stats.DODGE: -500.0})
	p.facing = Vector3.FORWARD
	return p


func _enemy(pos: Vector3, radius: float = 0.45) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos, radius)
	EnemyGrid.mark_dirty()
	return e


func _mortal(pos: Vector3, hp: float = 1000.0) -> MortalEnemy:
	var e := MortalEnemy.new()
	e.hp = hp
	e.max_hp = hp
	e.add_to_group(&"enemies")
	world.add_child(e)
	e.global_position = pos
	EnemyGrid.mark_dirty()
	return e


func _clear_enemies() -> void:
	for node in tree.get_nodes_in_group(&"enemies"):
		node.get_parent().remove_child(node)
		node.free()
	EnemyGrid.mark_dirty()


# --- Talents ------------------------------------------------------------------------------------

## Adds [param n] ranks of "hunter_<tree>_<short>" (checks each one).
func _add(p: Player, tree_id: String, short: String, n: int = 1) -> void:
	var id := StringName("hunter_%s_%s" % [tree_id, short])
	for i in n:
		check(p.talents.add(id), "add %s: %s" % [id, p.talents.add_block_reason(id)])


func _remove(p: Player, tree_id: String, short: String, n: int = 1) -> void:
	var id := StringName("hunter_%s_%s" % [tree_id, short])
	for i in n:
		check(p.talents.remove(id), "remove %s: %s" % [id, p.talents.remove_block_reason(id)])


## Reset Talents (paid from a fresh purse).
func _reset(p: Player) -> void:
	RunState.add_gold(1000)
	check(p.talents.try_reset(p.slot.index), "Reset Talents")


func _talent(tree_id: String, short: String) -> TalentData:
	return Db.get_talent(StringName("hunter_%s_%s" % [tree_id, short]))


## The mods the Hunter's talents / items hand to ability (or pseudo ability) [param id].
func _mods(p: Player, id: StringName) -> Dictionary:
	return p.ability_mods(id)


func _params(p: Player, id: StringName) -> Dictionary:
	return p.abilities.params_for(Db.get_ability(id))


func _learn(p: Player, id: StringName) -> int:
	var i := p.abilities.learn(Db.get_ability(id))
	check(i >= 0, "%s learned" % id)
	return i


## The Hunter's companion of [param kind] (spawned now; a fresh one when the kind changes).
func _pet(p: Player, kind: StringName = &"wolf") -> HunterCompanion:
	var m := p.abilities.mastery as HunterMastery
	if m.has_companion() and m.companion.kind != kind:
		m.companion.free()
		m.companion = null
	p.companion_id = kind
	return m.ensure_companion()


func _w(p: Player, school: StringName = &"physical") -> float:
	return GeneralKit.weapon_damage(p, school)


## Steps the companion for [param seconds].
func _step_pet(pet: HunterCompanion, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		pet.step(DT)
		t += DT


## Steps the talent scripts of [param p] for [param seconds] (60 Hz).
func _tick(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p.bonuses.tick(DT)
		t += DT


## Steps the companion and the talent scripts together (one physics frame at a time).
func _run(p: Player, seconds: float) -> void:
	var pet := HunterKit.companion(p)
	var t := 0.0
	while t < seconds - 0.00001:
		if pet != null:
			pet.step(DT)
		p.bonuses.tick(DT)
		t += DT


## An ally of [param p] at [param pos] (slot [param index]; a Hunter too – the class does not matter).
func _ally(index: int, pos: Vector3) -> Player:
	return _hunter(index, pos)


## The ids TalentBot picks for [param p] (bot [param slot_index]), point by point.
static func bot_path(p: Player, slot_index: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in 100:
		var t := TalentBot.next_talent(p, slot_index)
		if t == null or not p.talents.add(t.id):
			break
		out.append(t.id)
	return out


## [param n] copies of [param id] (bot path tables).
static func times(id: StringName, n: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in n:
		out.append(id)
	return out


# --- Equipment ----------------------------------------------------------------------------------

## Puts the weapons [param main] (and [param off]) of weapon base ids into the Hunter's hands.
func _wield(p: Player, main: StringName, off: StringName = &"") -> void:
	var item := ItemInstance.from_weapon(Db.get_weapon(main), Items.Rarity.COMMON, 1, false)
	p.equipment.add_to_backpack(item)
	check(p.equipment.equip(item), "wield %s" % main)
	if off != &"":
		var second := ItemInstance.from_weapon(Db.get_weapon(off), Items.Rarity.COMMON, 1, false)
		p.equipment.add_to_backpack(second)
		check(p.equipment.equip(second, Items.EquipSlot.OFF_HAND), "wield %s in the off hand" % off)
