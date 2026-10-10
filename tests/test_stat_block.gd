extends TestCase


func test_sources_add_up_and_replace() -> void:
	var s := StatBlock.new()
	s.set_base(Stats.STRENGTH, 2.0)
	s.set_source(&"class", {Stats.STRENGTH: 3.0})
	s.set_source(&"item:head", {Stats.STRENGTH: 1.0, Stats.STAMINA: 4.0})
	check_eq(s.get_stat(Stats.STRENGTH), 6.0, "strength")
	check_eq(s.max_hp(), 14.0, "max hp")
	s.set_source(&"item:head", {Stats.STAMINA: 1.0})
	check_eq(s.get_stat(Stats.STRENGTH), 5.0, "strength after replace")
	s.remove_source(&"item:head")
	check_eq(s.max_hp(), 10.0, "max hp after remove")


func test_add_to_source_accumulates() -> void:
	var s := StatBlock.new()
	s.add_to_source(&"levelups", {Stats.CRIT: 3.0})
	s.add_to_source(&"levelups", {Stats.CRIT: 2.0, Stats.HASTE: 5.0})
	check_eq(s.get_stat(Stats.CRIT), 5.0)
	check_eq(s.get_stat(Stats.HASTE), 5.0)


func test_caps() -> void:
	var s := StatBlock.new()
	s.set_source(&"x", {Stats.DODGE: 90.0, Stats.CRIT: 150.0, Stats.AVOIDANCE: 70.0, Stats.SPEED: -200.0})
	check_eq(s.get_stat(Stats.DODGE), Stats.DODGE_CAP, "dodge cap")
	check_eq(s.get_stat(Stats.CRIT), 100.0, "crit cap")
	check_eq(s.get_stat(Stats.AVOIDANCE), Stats.AVOIDANCE_CAP, "avoidance cap")
	check_eq(s.get_stat(Stats.SPEED), Stats.MIN_SPEED, "speed floor")
	check_eq(s.get_raw(Stats.DODGE), 90.0, "raw stays uncapped")


func test_max_hp_never_below_one() -> void:
	var s := StatBlock.new()
	s.set_source(&"curse", {Stats.STAMINA: -50.0})
	check_eq(s.max_hp(), 1.0)


func test_derived_values() -> void:
	var s := StatBlock.new()
	s.set_source(&"x", {Stats.HASTE: 50.0, Stats.SPEED: 20.0, Stats.VERSATILITY: 10.0, Stats.DAMAGE_PCT: -10.0})
	check_eq(s.attack_speed_mult(), 1.5, "attack speed")
	check_eq(s.move_speed(), Stats.BASE_MOVE_SPEED * 1.2, "move speed")
	check_eq(s.damage_mult(), 1.0, "damage mult")
	check_near(s.cooldown_mult(), 1.0 / 1.25, 0.0001, "cooldown mult")


func test_pickup_range_is_a_percent_stat() -> void:
	var s := StatBlock.new()
	check_eq(s.pickup_range(), Stats.BASE_PICKUP_RANGE, "base range")
	s.set_source(&"x", {Stats.PICKUP_RANGE: 50.0})
	check_eq(s.pickup_range(), Stats.BASE_PICKUP_RANGE * 1.5, "+50%")
	s.set_source(&"x", {Stats.PICKUP_RANGE: -100.0})
	check_eq(s.pickup_range(), 0.5, "never below 0.5 m")
	check(Stats.is_percent(Stats.PICKUP_RANGE), "shown with a % suffix")
	check_eq(Stats.format_value(Stats.PICKUP_RANGE, 20.0), "+20%")


func test_changed_signal() -> void:
	var s := StatBlock.new()
	var hits := [0]
	s.changed.connect(func() -> void: hits[0] += 1)
	s.set_source(&"a", {Stats.ARMOR: 1.0})
	s.remove_source(&"a")
	s.remove_source(&"missing")
	check_eq(hits[0], 2)
