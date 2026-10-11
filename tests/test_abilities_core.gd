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
	var set_pct := AbilityRunner.apply_mods({"damage": 5.0}, {"slow_pct": 40.0})
	check_eq(set_pct["slow_pct"], 40.0, "a _pct key without its param sets the key itself")
	check(not set_pct.has("slow"), "and does not create a zero param")


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


class WaveCountingEffect extends AbilityEffect:
	var waves := 0
	func begin_wave(_ctx: AbilityContext) -> void:
		waves += 1


func test_charges_recharge_one_at_a_time() -> void:
	var p := _make_player()
	var a := p.abilities.slots[0]
	a.params["charges"] = 2
	p.abilities.get_resource(&"test_rage").set_value(100.0)
	check_eq(p.abilities.charges_max(a), 2, "two charges")
	check(p.abilities.try_cast(0), "first")
	check_eq(p.abilities.remaining(0), 0.0, "a charge is left")
	check(p.abilities.try_cast(0), "second in a row")
	check_eq(p.abilities.charges_available(a), 0, "empty")
	check_near(p.abilities.remaining(0), 2.0, 0.001, "next charge in one cooldown")
	for i in 121:
		p.abilities._physics_process(DT)
	check_eq(p.abilities.charges_available(a), 1, "one back after 2 s")
	check_near(p.abilities.remaining(0), 0.0, 0.001, "castable")
	for i in 120:
		p.abilities._physics_process(DT)
	check_eq(p.abilities.charges_available(a), 2, "both back after 4 s")


func test_charges_mod_and_set_cooldown() -> void:
	var p := _make_player()
	var a := p.abilities.slots[0]
	var item := ItemInstance.new()
	item.slot_type = Items.SlotType.HEAD
	item.armor_type = Items.NO_ARMOR
	item.unique_effect = &"ability_mod"
	item.unique_params = {"ability": "test_strike", "mods": {"charges_add": 1.0, "cooldown_add": -1.0}}
	check(p.equipment.equip(item), "equip")
	check_eq(p.abilities.charges_max(a), 2, "+1 charge from the item")
	check_near(p.abilities.cooldown_of(a), 1.0, 0.001, "-1 s from the item")
	p.abilities.get_resource(&"test_rage").set_value(100.0)
	check(p.abilities.try_cast(0) and p.abilities.try_cast(0), "two casts")
	check(not p.abilities.try_cast(0), "out of charges")
	p.abilities.set_cooldown(a, 0.0)
	check_eq(p.abilities.charges_available(a), 2, "set_cooldown(0) refills")
	p.abilities.set_cooldown(a, 5.0)
	check_eq(p.abilities.charges_available(a), 1, "a running recharge spends one charge")


func test_begin_wave_reaches_effects() -> void:
	var p := _make_player()
	var a := _ability(0.0, 1.0)
	a.id = &"test_wave"
	a.effect = WaveCountingEffect
	p.abilities.set_slot(1, a)
	p.begin_wave()
	check_eq((p.abilities.effect_for(a) as WaveCountingEffect).waves, 1, "effect told about the wave")


func test_pip_gains_ignore_resource_regen() -> void:
	var data := ResourceData.new()
	data.id = &"test_pips"
	data.display = ResourceData.Display.PIPS
	data.max_value = 5.0
	data.gain_on_crit = 1.0
	var res := ClassResource.new(data)
	res.gain_mult = 1.3
	res.on_weapon_hit(true)
	check_eq(res.value, 1.0, "a whole pip, not 1.3")
	var bar := ClassResource.new(_resource())
	bar.gain_mult = 1.5
	bar.on_weapon_hit(false)
	check_eq(bar.value, 15.0, "bars still scale")


class TickCountingMastery extends MasteryEffect:
	var ticks := 0
	var ended := 0
	func tick(_delta: float) -> void:
		ticks += 1
	func end_wave() -> void:
		ended += 1


func test_slot_state_matches_the_single_queries() -> void:
	var p := _make_player()
	var a := p.abilities.slots[0]
	a.params["charges"] = 2
	p.abilities.invalidate_params()
	var res := p.abilities.get_resource(&"test_rage")
	res.set_value(40.0)
	var st := p.abilities.slot_state(0)
	check_eq(st["charges"], 2, "charges")
	check_eq(st["charges_max"], 2, "max")
	check(st["ready"], "ready")
	check_eq(st["cost"], 30.0, "cost")
	check(p.abilities.try_cast(0), "cast once")
	st = p.abilities.slot_state(0)
	check_eq(st["charges"], 1, "one left")
	check(not st["ready"], "10 rage left: not affordable")
	res.set_value(100.0)
	p.abilities.try_cast(0)
	st = p.abilities.slot_state(0)
	check_near(st["left"], p.abilities.remaining(0), 0.0001, "left = remaining")
	check_near(st["ratio"], p.abilities.cooldown_ratio(0), 0.0001, "ratio = cooldown_ratio")
	check_eq(p.abilities.slot_state(3), {}, "empty slot")


func test_params_cache_follows_equipment() -> void:
	var p := _make_player()
	var a := p.abilities.slots[0]
	check_near(p.abilities.cooldown_of(a), 2.0, 0.001, "base")
	check(p.abilities.params_for(a).is_read_only(), "cached params are read-only")
	var item := ItemInstance.new()
	item.slot_type = Items.SlotType.HEAD
	item.armor_type = Items.NO_ARMOR
	item.unique_effect = &"ability_mod"
	item.unique_params = {"ability": "test_strike", "mods": {"cooldown_add": -1.0}}
	p.equipment.equip(item)
	check_near(p.abilities.cooldown_of(a), 1.0, 0.001, "equip invalidates the cache")
	p.equipment.unequip(Items.EquipSlot.HEAD)
	check_near(p.abilities.cooldown_of(a), 2.0, 0.001, "unequip too")


func test_mastery_ticks_while_downed_and_hears_wave_end() -> void:
	var p := _make_player()
	var m := TickCountingMastery.new()
	p.abilities.mastery = m
	p.abilities._physics_process(DT)
	p._go_down()
	p.abilities._physics_process(DT)
	check_eq(m.ticks, 2, "ticks alive and downed (DoTs keep burning)")
	p.end_wave()
	check_eq(m.ended, 1, "end_wave reaches the Mastery")


func test_wave_start_clears_crits_and_buffs() -> void:
	var p := _make_player()
	p.forced_crits = 1
	p.damage_mults[&"test"] = 1.5
	p.begin_wave()
	check_eq(p.forced_crits, 0, "forced crits do not carry over")
	check(p.damage_mults.is_empty(), "named buffs end with the wave")


func test_keyboard_learned_slots_are_q_then_e() -> void:
	var kb := KeyboardInput.new()
	check_eq(kb.ability_button(0), PlayerInput.Pad.RT, "LMB")
	check_eq(kb.ability_button(2), PlayerInput.Pad.LB, "Q = learned 1")
	check_eq(kb.ability_button(3), PlayerInput.Pad.RB, "E = learned 2")
	check_eq(ScriptedInput.new("x").ability_button(2), PlayerInput.Pad.RB, "pads: RB = learned 1")
