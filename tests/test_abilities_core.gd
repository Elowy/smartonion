extends TestCase
## Ability core (M3): resources, cooldowns, casting, item mods.

const DT := 1.0 / 60.0


class CountingEffect extends AbilityEffect:
	var casts := 0
	func cast(_ctx: AbilityContext) -> bool:
		casts += 1
		return true


var _root: Node3D
var _player: Player


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 3)
	_root = Node3D.new()
	tree.root.add_child(_root)


func after_each() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	PlayerManager.clear()


func _ability(cost: float, cooldown: float) -> AbilityData:
	var a := AbilityData.new()
	a.id = &"test_strike"
	a.resource = &"test_rage"
	a.cost = cost
	a.cooldown = cooldown
	a.targeting = AbilityData.Targeting.SELF
	a.effect = CountingEffect
	a.params = {"radius": 2.0}
	return a


func _resource() -> ResourceData:
	var r := ResourceData.new()
	r.id = &"test_rage"
	r.max_value = 100.0
	r.gain_on_hit = 10.0
	r.gain_on_damage_taken = 5.0
	r.decay_per_second = 10.0
	r.decay_delay = 1.0
	return r


func _make_player() -> Player:
	var slot := PlayerManager.join(ScriptedInput.new("p1"))
	var p := Player.create(slot)
	_root.add_child(p)
	p.abilities.resources.clear()
	p.abilities.resource_order.clear()
	var res := ClassResource.new(_resource())
	p.abilities.resources[&"test_rage"] = res
	p.abilities.resource_order.append(&"test_rage")
	p.abilities.set_slot(0, _ability(30.0, 2.0))
	return p


func test_resource_gain_spend_decay() -> void:
	var p := _make_player()
	var res := p.abilities.get_resource(&"test_rage")
	check(not p.abilities.try_cast(0), "cannot cast without rage")
	for i in 3:
		p.abilities.on_weapon_hit(null, 5.0, false)
	check_eq(res.value, 30.0, "10 rage per hit")
	check(p.abilities.try_cast(0), "cast with enough rage")
	check_eq(res.value, 0.0, "cost spent")
	p.abilities.on_damage_taken(3.0)
	check_eq(res.value, 5.0, "rage from damage taken")
	for i in 120:
		p.abilities._physics_process(DT)
	check_near(res.value, 0.0, 0.01, "decays after the delay")


func test_cooldown_and_haste() -> void:
	var p := _make_player()
	p.abilities.get_resource(&"test_rage").set_value(100.0)
	check(p.abilities.try_cast(0), "first cast")
	check(not p.abilities.try_cast(0), "on cooldown")
	check_near(p.abilities.remaining(0), 2.0, 0.001, "full cooldown")
	p.stats.set_source(&"t", {Stats.HASTE: 100.0, Stats.COOLDOWN_REDUCTION: 10.0})
	check_near(p.abilities.cooldown_of(p.abilities.slots[0]), 2.0 / 1.5 * 0.9, 0.001, "haste (half) + CDR")
	for i in 130:
		p.abilities._physics_process(DT)
	check(p.abilities.try_cast(0), "ready again")


func test_begin_wave_resets() -> void:
	var p := _make_player()
	var res := p.abilities.get_resource(&"test_rage")
	res.set_value(80.0)
	p.abilities.try_cast(0)
	p.begin_wave()
	check_eq(res.value, 0.0, "start value")
	check_eq(p.abilities.remaining(0), 0.0, "cooldowns cleared")


func test_item_mods_apply() -> void:
	var base := {"radius": 2.0, "duration": 3.0}
	var mods := {"radius_pct": 50.0, "duration_add": 1.0, "follows": true}
	var out := AbilityRunner.apply_mods(base, mods)
	check_eq(out["radius"], 3.0, "pct")
	check_eq(out["duration"], 4.0, "add")
	check(out["follows"], "flag")
	check_eq(base["radius"], 2.0, "base untouched")


func test_ability_mod_items_are_collected() -> void:
	var p := _make_player()
	var item := ItemInstance.new()
	item.slot_type = Items.SlotType.HEAD
	item.armor_type = Items.NO_ARMOR
	item.unique_effect = &"ability_mod"
	item.unique_params = {"ability": "test_strike", "mods": {"radius_pct": 30.0}}
	check(p.equipment.equip(item), "equip")
	check_eq(p.ability_mods(&"test_strike"), {"radius_pct": 30.0}, "mods for the ability")
	check_eq(p.ability_mods(&"other"), {}, "no mods for other abilities")
	var ctx := p.abilities.build_context(p.abilities.slots[0])
	check_near(ctx.num("radius"), 2.6, 0.001, "context params include mods")


func test_forced_crits() -> void:
	var p := _make_player()
	p.forced_crits = 2
	check(p.consume_forced_crit(), "1")
	check(p.consume_forced_crit(), "2")
	check(not p.consume_forced_crit(), "used up")
