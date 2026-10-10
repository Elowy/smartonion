extends TestCase
## Mage kit (M3, GDD 3.2): class data, Mana (max 100 + 2 x Intellect, regen 10/s with Haste),
## Mastery "Ignite" and the Mage's ability-mod items.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 31)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


func _mage(index: int = 0, pos: Vector3 = Vector3.ZERO) -> Player:
	var p := Fakes.spawn_player(world, index, &"mage", pos)
	p.abilities._physics_process(DT)  # first tick: Mana maximum follows Intellect
	return p


func _enemy(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


func _mana(p: Player) -> ClassResource:
	return p.abilities.get_resource(&"mana")


func _total(e: Fakes.FakeEnemy) -> float:
	var sum := 0.0
	for d in e.fake_damage_log:
		sum += d
	return sum


# --- Data -----------------------------------------------------------------------------------

func test_class_data() -> void:
	var c := Db.get_class_data(&"mage")
	check(c != null, "mage exists")
	check_eq(c.resources.size(), 1, "one resource")
	check_eq(c.resources[0].id, &"mana", "mana")
	check_eq(c.abilities.size(), 2, "two core abilities")
	check_eq(c.abilities[0].id, &"blizzard", "RT = Blizzard")
	check_eq(c.abilities[1].id, &"blink", "LT = Blink")
	check(c.mastery == MageMastery, "Ignite mastery script")
	check(c.mastery_text.begins_with("Ignite"), "mastery text")
	var mana := c.resources[0]
	check_eq(mana.regen_per_second, 10.0, "10 mana / s")
	check(mana.regen_uses_haste, "regen scales with Haste")
	var blizzard := c.abilities[0]
	check_eq(blizzard.resource, &"mana", "Blizzard costs mana")
	check_eq(blizzard.cost, 50.0, "50 Mana")
	check_eq(blizzard.targeting, AbilityData.Targeting.DENSEST_CLUSTER, "densest cluster")
	check_eq(blizzard.school, &"frost", "frost")
	check(blizzard.effect == BlizzardEffect, "Blizzard effect")
	var blink := c.abilities[1]
	check_eq(blink.resource, &"", "Blink is free")
	check_eq(blink.cooldown, 6.0, "6 s cooldown")
	check_eq(blink.targeting, AbilityData.Targeting.MOVE_DIRECTION, "movement direction")
	check(blink.effect == BlinkEffect, "Blink effect")


func test_class_items_are_ability_mods() -> void:
	var cowl := Db.uniques[&"frostweave_cowl"]
	check_eq(cowl.unique_effect, &"ability_mod", "cowl")
	check_eq(cowl.unique_params["ability"], "blizzard", "cowl ability")
	check_eq(cowl.unique_params["mods"], {"radius_pct": 30.0}, "+30% area")
	check_eq(cowl.class_restriction, &"mage", "mage item")
	var band := Db.uniques[&"band_of_the_blinking_star"]
	check_eq(band.unique_effect, &"ability_mod", "band")
	check_eq(band.unique_params["ability"], "blink", "band ability")
	check_eq(band.unique_params["mods"], {"charges_add": 1.0}, "+1 charge")
	check_eq(band.class_restriction, &"mage", "mage item")
	var p := _mage()
	for id: StringName in [&"frostweave_cowl", &"band_of_the_blinking_star"]:
		var item := ItemGenerator.from_unique(Db.uniques[id], 1, false, RunState.rng, p.class_data)
		check(p.equipment.equip(item), "mage can wear %s" % id)
	check_eq(p.ability_mods(&"blizzard"), {"radius_pct": 30.0}, "blizzard mods")
	check_eq(p.ability_mods(&"blink"), {"charges_add": 1.0}, "blink mods")


# --- Mana -----------------------------------------------------------------------------------

func test_mana_max_follows_intellect() -> void:
	var p := _mage()
	var res := _mana(p)
	var intellect := p.stats.get_raw(Stats.INTELLECT)
	check(intellect >= 3.0, "class Intellect")
	check_eq(res.max_value(), 100.0 + 2.0 * intellect, "100 + 2 x Intellect")
	check_eq(res.value, res.max_value(), "starts full")
	p.stats.set_source(&"gear", {Stats.INTELLECT: 10.0})
	p.abilities._physics_process(DT)
	check_eq(res.max_value(), 100.0 + 2.0 * (intellect + 10.0), "max follows gear")
	check_eq(res.value, res.max_value(), "the new mana is granted at once")
	p.stats.remove_source(&"gear")
	p.abilities._physics_process(DT)
	check_eq(res.max_value(), 100.0 + 2.0 * intellect, "max falls again")
	check(res.value <= res.max_value() + 0.001, "value clamped")


func test_mana_data_is_per_player() -> void:
	var a := _mage(0)
	var b := _mage(1)
	b.stats.set_source(&"gear", {Stats.INTELLECT: 20.0})
	b.abilities._physics_process(DT)
	check(_mana(b).max_value() > _mana(a).max_value(), "own maximum per mage")
	check_eq(Db.get_class_data(&"mage").resources[0].max_value, 100.0, "shared data untouched")


func test_mana_regen_and_haste() -> void:
	var p := _mage()
	var res := _mana(p)
	res.set_value(0.0)
	Fakes.step(p.abilities, 1.0)
	check_near(res.value, 10.0, 0.2, "10 mana / s")
	res.set_value(0.0)
	p.stats.set_source(&"haste", {Stats.HASTE: 100.0})
	var haste := p.stats.attack_speed_mult()
	check(haste > 1.5, "haste active")
	Fakes.step(p.abilities, 1.0)
	check_near(res.value, 10.0 * haste, 0.3, "regen scales with Haste")
	p.stats.remove_source(&"haste")
	res.set_value(0.0)
	p.stats.set_source(&"regen", {Stats.RESOURCE_REGEN: 50.0})
	Fakes.step(p.abilities, 1.0)
	check_near(res.value, 15.0, 0.3, "Resource Regen % scales it")


func test_mana_refills_each_wave() -> void:
	var p := _mage()
	var res := _mana(p)
	res.set_value(3.0)
	p.begin_wave()
	check_eq(res.value, res.max_value(), "full at wave start")
	check(res.max_value() > 100.0, "includes the Intellect bonus")


# --- Mastery: Ignite --------------------------------------------------------------------------

func test_ignite_burns_a_share_of_the_crit() -> void:
	var p := _mage()
	p.stats.set_source(&"mastery", {Stats.MASTERY: 50.0})
	var e := _enemy(Vector3(5, 0, 0))
	var mastery := p.abilities.mastery as MageMastery
	p.on_hit_dealt(20.0, e, p.main_hand, true)
	check_eq(mastery.burning_count(), 1, "burning")
	check_near(mastery.burn_rate(e), 10.0 / 3.0, 0.001, "50% of 20 over 3 s")
	Fakes.step(p.abilities, 3.3)
	check_near(_total(e), 10.0, 0.05, "the burn deals 50% of the crit in total")
	check_eq(mastery.burning_count(), 0, "burn over")
	check(e.fake_damage_log.size() >= 5, "in ticks (%d)" % e.fake_damage_log.size())


func test_ignite_scales_with_mastery_points() -> void:
	var p := _mage()
	var e := _enemy(Vector3(5, 0, 0))
	var mastery := p.abilities.mastery as MageMastery
	p.stats.set_source(&"mastery", {Stats.MASTERY: 10.0})
	p.on_hit_dealt(40.0, e, p.main_hand, true)
	check_near(mastery.burn_rate(e) * 3.0, 4.0, 0.001, "1% per point: 10 points = 10%")
	check(mastery.describe().begins_with("Ignite"), "tooltip")
	check("10%" in mastery.describe(), "tooltip shows the share")


func test_ignite_needs_a_crit_and_mastery() -> void:
	var p := _mage()
	var e := _enemy(Vector3(5, 0, 0))
	var mastery := p.abilities.mastery as MageMastery
	p.stats.set_source(&"mastery", {Stats.MASTERY: 50.0})
	p.on_hit_dealt(20.0, e, p.main_hand, false)
	check_eq(mastery.burning_count(), 0, "no crit, no burn")
	p.stats.remove_source(&"mastery")
	p.on_hit_dealt(20.0, e, p.main_hand, true)
	check_eq(mastery.burning_count(), 0, "no Mastery, no burn")


func test_ignite_stacks_on_a_burning_target() -> void:
	var p := _mage()
	p.stats.set_source(&"mastery", {Stats.MASTERY: 100.0})
	var e := _enemy(Vector3(5, 0, 0))
	var mastery := p.abilities.mastery as MageMastery
	p.on_hit_dealt(30.0, e, p.main_hand, true)
	Fakes.step(p.abilities, 1.5)
	p.on_hit_dealt(30.0, e, p.main_hand, true)
	var again := mastery.burn_rate(e) * 3.0
	check(again > 40.0 and again < 50.0, "about half the first crit is left and joins the new one (%f)" % again)
	Fakes.step(p.abilities, 3.3)
	check_near(_total(e), 60.0, 0.1, "nothing lost")


func test_ignite_stops_with_the_enemy() -> void:
	var p := _mage()
	p.stats.set_source(&"mastery", {Stats.MASTERY: 100.0})
	var e := _enemy(Vector3(5, 0, 0))
	var mastery := p.abilities.mastery as MageMastery
	p.on_hit_dealt(30.0, e, p.main_hand, true)
	Fakes.step(p.abilities, 0.6)
	e.fake_dead = true
	var hits := e.fake_damage_log.size()
	Fakes.step(p.abilities, 1.0)
	check_eq(e.fake_damage_log.size(), hits, "a dead enemy takes no more ticks")
	check_eq(mastery.burning_count(), 0, "forgotten")


func test_ignite_is_cleared_at_wave_start() -> void:
	var p := _mage()
	p.stats.set_source(&"mastery", {Stats.MASTERY: 100.0})
	var e := _enemy(Vector3(5, 0, 0))
	p.on_hit_dealt(30.0, e, p.main_hand, true)
	p.begin_wave()
	check_eq((p.abilities.mastery as MageMastery).burning_count(), 0, "burns end with the wave")
