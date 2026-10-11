extends TestCase
## P0 stub values owned by T-CORE-B: reduce_cooldown is a no-op, ClassResource.bonus is stored
## but not read, ProcSystem.set_extra_procs only stores. T-CORE-B: delete or replace this file
## when you implement them (architecture §3.1). The contracts that stay true afterwards
## (cooldown_left, set_bonus stores a copy, the hook order) are in test_m5_foundation.gd
## (frozen, integrator only).

const Fakes := preload("res://tests/player_fakes.gd")

var world: Node3D


func before_each() -> void:
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null


func test_reduce_cooldown_is_a_no_op() -> void:
	var p := Fakes.spawn_player(world, 0, &"mage")
	var blink := Db.get_ability(&"blink")
	p.abilities.set_cooldown(blink, 4.0)
	p.abilities.reduce_cooldown(blink, 1.0)
	check_eq(p.abilities.cooldown_left(blink), 4.0, "stub: nothing taken off")


func test_class_resource_bonus_is_not_read() -> void:
	var p := Fakes.spawn_player(world, 0, &"mage")
	var mana := p.abilities.primary_resource()
	var before := mana.max_value()
	mana.set_bonus({"max_value_add": 20.0})
	check_eq(mana.max_value(), before, "stub: the bonus changes nothing yet")


func test_extra_procs_are_stored_not_built() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var n := p.procs.procs.size()
	p.procs.set_extra_procs(&"talents", [{"trigger": "on_hit", "effect": "bolt", "damage": 3}] as Array[Dictionary])
	check_eq(p.procs._extra_defs[&"talents"].size(), 1, "stored")
	p.procs.refresh()
	check_eq(p.procs.procs.size(), n, "stub: not built into procs")
	var state := RunState.rng.state
	p.procs.on_ability_cast(Db.get_ability(&"charge"))
	p.procs.on_avoided(&"dodge", null)
	p.procs.after_wave_start()
	check_eq(RunState.rng.state, state, "stub: the new triggers do nothing")
