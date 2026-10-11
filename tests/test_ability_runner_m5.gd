extends TestCase
## AbilityRunner M5 (T-CORE-B): reduce_cooldown (one charge back at most, the leftover kept –
## like time passing), cooldown_left while charges are left, the "free_chance" param (clamped
## to 75%, no draw at 0 or without a cost, "Free!", last_paid).

const Fakes := preload("res://tests/player_fakes.gd")

## An effect that always casts and never draws.
class AlwaysCast extends AbilityEffect:
	func cast(_ctx: AbilityContext) -> bool:
		return true


var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 7)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	Enemy.invalidate_player_cache()


# --- Helpers -----------------------------------------------------------------------------------

## A Mage whose Blink has Rank III (two charges).
func _mage_with_two_blinks() -> Player:
	var p := Fakes.spawn_player(world, 0, &"mage")
	p.abilities.ranks[&"blink"] = 3
	p.abilities.invalidate_params()
	return p


## An Active Rage spender (cost [param cost], no cooldown) with [param params].
static func _spender(cost: float, params: Dictionary = {}) -> AbilityData:
	var a := AbilityData.new()
	a.id = &"test_spender"
	a.display_name = "Test Spender"
	a.class_id = &"warrior"
	a.kind = AbilityData.Kind.ACTIVE
	a.resource = &"rage"
	a.cost = cost
	a.cooldown = 0.0
	a.targeting = AbilityData.Targeting.SELF
	a.effect = AlwaysCast
	a.params = params
	return a


## A Warrior with [param a] in slot 2 (RB).
func _warrior_with(a: AbilityData) -> Player:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	p.abilities.set_slot(2, a)
	return p


func _texts(text: String) -> int:
	var n := 0
	for node in world.find_children("*", "Label3D", true, false):
		if (node as Label3D).text == text:
			n += 1
	return n


# --- reduce_cooldown / cooldown_left -----------------------------------------------------------

func test_reduce_cooldown_returns_one_charge_and_keeps_the_leftover() -> void:
	var p := _mage_with_two_blinks()
	var r := p.abilities
	var blink := Db.get_ability(&"blink")
	var slot := r.slot_of(&"blink")
	check_eq(r.charges_max(blink), 2, "Rank III: two charges")
	var full := r.cooldown_of(blink)
	r.spend_charge(blink)
	check_eq(r.remaining(slot), 0.0, "a charge is left: castable")
	check_near(r.cooldown_left(blink), full, 0.0001, "cooldown_left: the recharge runs while a charge is left")
	r.spend_charge(blink)
	check_eq(r.charges_available(blink), 0, "both spent")
	r.reduce_cooldown(blink, 1.0)
	check_near(r.cooldown_left(blink), full - 1.0, 0.0001, "1 s off the running recharge")
	check_eq(r.charges_available(blink), 0, "no charge back yet")
	r.reduce_cooldown(blink, full)  # 1 s more than what is left
	check_eq(r.charges_available(blink), 1, "one charge back, not both")
	check_near(r.cooldown_left(blink), full - 1.0, 0.0001, "the next recharge keeps the 1 s overshoot")
	check_eq(r.remaining(slot), 0.0, "castable again")
	r.reduce_cooldown(blink, full * 5.0)
	check_eq(r.charges_available(blink), 2, "the second charge (still one per call)")
	check_eq(r.cooldown_left(blink), 0.0, "nothing left to recharge")
	# The reset block's set_cooldown(a, 0) refunds every spent charge at once.
	r.spend_charge(blink)
	r.spend_charge(blink)
	r.set_cooldown(blink, 0.0)
	check_eq(r.charges_available(blink), 2, "reset: every charge back")


func test_reduce_cooldown_matches_time_passing() -> void:
	var a := _mage_with_two_blinks()
	var b := Fakes.spawn_player(world, 1, &"mage", Vector3(5, 0, 0))
	b.abilities.ranks[&"blink"] = 3
	b.abilities.invalidate_params()
	var blink := Db.get_ability(&"blink")
	var full := a.abilities.cooldown_of(blink)
	for p: Player in [a, b]:
		p.abilities.spend_charge(blink)
		p.abilities.spend_charge(blink)
	a.abilities.reduce_cooldown(blink, full + 0.5)
	b.abilities._tick_cooldowns(full + 0.5)
	check_eq(a.abilities.charges_available(blink), b.abilities.charges_available(blink), "same charges")
	check_near(a.abilities.cooldown_left(blink), b.abilities.cooldown_left(blink), 0.0001, "same timer")


func test_reduce_cooldown_single_charge_and_no_ops() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var r := p.abilities
	var charge := Db.get_ability(&"charge")
	var slot := r.slot_of(&"charge")
	r.reduce_cooldown(charge, 2.0)
	check_eq(r.cooldown_left(charge), 0.0, "nothing running: no-op")
	check_eq(r.charges_available(charge), 1, "no charge invented")
	r.spend_charge(charge)
	var full := r.cooldown_of(charge)
	r.reduce_cooldown(charge, 0.0)
	r.reduce_cooldown(charge, -3.0)
	check_near(r.cooldown_left(charge), full, 0.0001, "0 / negative seconds change nothing")
	r.reduce_cooldown(charge, 3.0)
	check_near(r.cooldown_left(charge), full - 3.0, 0.0001, "3 s off")
	check_near(r.remaining(slot), full - 3.0, 0.0001, "the slot waits that much less")
	r.reduce_cooldown(charge, 100.0)
	check_eq(r.cooldown_left(charge), 0.0, "ready")
	check_eq(r.charges_available(charge), 1, "the one charge")
	r.reduce_cooldown(null, 1.0)
	check_eq(r.cooldown_left(null), 0.0, "null ability: nothing")


# --- free_chance --------------------------------------------------------------------------------

func test_free_chance_is_clamped_to_75_percent() -> void:
	var a := _spender(40.0, {"free_chance": 100.0})
	var p := _warrior_with(a)
	var rage := p.abilities.get_resource(&"rage")
	var free := 0
	var casts := 400
	for i in casts:
		rage.set_value(100.0)
		check(p.abilities.try_cast(2), "cast %d" % i)
		if rage.value > 99.0:
			free += 1
	check(free > 255 and free < 345, "~75%% of %d casts free, never all (%d)" % [casts, free])
	check_eq(AbilityRunner.FREE_CHANCE_CAP, 75.0, "the cap")


func test_free_cast_spends_nothing_and_says_so() -> void:
	var a := _spender(40.0, {"free_chance": 50.0})
	var p := _warrior_with(a)
	var rage := p.abilities.get_resource(&"rage")
	var saw_free := false
	var saw_paid := false
	for i in 12:  # (floating texts are capped at Vfx.MAX_TEXTS)
		rage.set_value(100.0)
		var texts := _texts(AbilityRunner.FREE_TEXT)
		p.abilities.try_cast(2)
		if is_equal_approx(rage.value, 100.0):
			saw_free = true
			check_eq(p.abilities.last_paid(a), 0.0, "a free cast paid nothing")
			check_eq(_texts(AbilityRunner.FREE_TEXT), texts + 1, "\"Free!\" above the caster")
		else:
			saw_paid = true
			check_near(rage.value, 60.0, 0.0001, "a paid cast spends the cost")
			check_eq(p.abilities.last_paid(a), 40.0, "last_paid = the cost")
			check_eq(_texts(AbilityRunner.FREE_TEXT), texts, "no text when paid")
	check(saw_free and saw_paid, "both outcomes at 50%")
	check_eq(p.abilities.last_paid(null), 0.0, "null: 0")


func test_free_chance_draws_only_when_it_can_matter() -> void:
	var p := _warrior_with(_spender(40.0))
	var rage := p.abilities.get_resource(&"rage")
	rage.set_value(100.0)
	var state := RunState.rng.state
	check(p.abilities.try_cast(2), "cast without free_chance")
	check_eq(RunState.rng.state, state, "no free_chance: no draw")
	check_near(rage.value, 60.0, 0.0001, "paid")
	# A chance on an ability that costs nothing: nothing to save, no draw.
	var q := Fakes.spawn_player(world, 1, &"warrior", Vector3(4, 0, 0))
	var costless := _spender(0.0, {"free_chance": 50.0})
	q.abilities.set_slot(2, costless)
	state = RunState.rng.state
	check(q.abilities.try_cast(2), "cast")
	check_eq(RunState.rng.state, state, "no cost: no draw")
	# A chance above 0 on a cost: exactly one draw per cast.
	var r := Fakes.spawn_player(world, 2, &"warrior", Vector3(-4, 0, 0))
	r.abilities.set_slot(2, _spender(40.0, {"free_chance": 30.0}))
	r.abilities.get_resource(&"rage").set_value(100.0)
	var probe := RandomNumberGenerator.new()
	probe.state = RunState.rng.state
	probe.randf()
	check(r.abilities.try_cast(2), "cast")
	check_eq(RunState.rng.state, probe.state, "one draw")


func test_free_chance_add_mods_reach_the_roll() -> void:
	var a := _spender(40.0)
	var p := _warrior_with(a)
	var item := ItemInstance.new()
	item.source_id = &"test_free_mod"
	item.display_name = "Test Free Mod"
	item.slot_type = Items.SlotType.TRINKET
	item.rarity = Items.Rarity.LEGENDARY
	item.unique = true
	item.unique_effect = &"ability_mod"
	item.unique_params = {"ability": "test_spender", "mods": {"free_chance_add": 90.0}}
	p.equipment.equip(item)
	check_eq(p.abilities.params_for(a).get("free_chance"), 90.0, "free_chance_add -> the free_chance param")
	var rage := p.abilities.get_resource(&"rage")
	var free := 0
	for i in 200:
		rage.set_value(100.0)
		p.abilities.try_cast(2)
		if rage.value > 99.0:
			free += 1
	check(free > 120 and free < 180, "90 clamped to 75%% (%d of 200)" % free)
