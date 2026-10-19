extends TestCase


func before_each() -> void:
	PlayerManager.clear()


func after_each() -> void:
	PlayerManager.clear()


func test_launch_content_loads() -> void:
	check_eq(Db.class_ids, [&"warrior", &"mage", &"paladin", &"rogue", &"warlock"] as Array[StringName], "class order")
	check_eq(Db.weapons.size(), 13, "weapon count")
	check(Db.enemies.size() >= 4, "at least 4 enemies")
	for id in Db.class_ids:
		var c := Db.get_class_data(id)
		check(c.main_hand != null, "%s has a main hand" % id)
		check(c.can_use(c.main_hand), "%s can use its starting weapon" % id)
		if c.off_hand != null and c.off_hand.hand != WeaponData.Hand.OFF_HAND:
			check(c.can_dual_wield(), "%s needs dual wield for a second weapon" % id)
		if c.main_hand.is_two_handed():
			check(c.off_hand == null, "%s two-hander leaves the off hand empty" % id)


func test_cycle_class_wraps() -> void:
	check_eq(Db.cycle_class(&"warrior", -1), &"warlock")
	check_eq(Db.cycle_class(&"warlock", 1), &"warrior")


func test_shared_wallet() -> void:
	RunState.start_run(2, 1)
	RunState.add_gold(30)
	check(RunState.try_spend(20), "can spend")
	check(not RunState.try_spend(20), "cannot overspend")
	check_eq(RunState.gold, 10)


func test_gold_find_remainder_per_slot() -> void:
	RunState.start_run(2, 1)
	check_eq(RunState.add_gold_for(0, 1, 25.0), 1, "1.25 -> 1 now")
	check_eq(RunState.add_gold_for(1, 1, 25.0), 1, "other slot: own remainder")
	check_eq(RunState.add_gold_for(0, 1, 25.0), 1, "2.5 total")
	check_eq(RunState.add_gold_for(0, 1, 25.0), 1, "3.75 total")
	check_eq(RunState.add_gold_for(0, 1, 25.0), 2, "5.0 total: the fractions became a coin")
	check_eq(RunState.gold, 6, "whole gold in the shared wallet")
	check_eq(RunState.gold_earned, 6, "counts as earned")
	check_near(RunState.gold_remainder(1), 0.25, 0.0001, "slot 1 keeps its quarter")
	check_eq(RunState.add_gold_for(0, 0, 25.0), 0, "nothing picked up")
	var tenth := 0
	for i in 10:
		tenth += RunState.add_gold_for(3, 1, 10.0)
	check_eq(tenth, 11, "float sums of 0.1 still pay the 11th coin")
	RunState.start_run(2, 1)
	check_eq(RunState.gold_remainder(1), 0.0, "a new run clears the remainders")


func test_shared_xp_levels() -> void:
	RunState.start_run(1, 1)
	check_eq(RunState.level, 1, "the team starts at level 1 (WoW style)")
	check_eq(RunState.xp_to_next_level(), 16, "the first level-up (1 -> 2) needs (1+3)^2")
	RunState.add_xp(16 + 25 + 3)
	check_eq(RunState.level, 3)
	check_eq(RunState.xp, 3)
	check_eq(RunState.pending_level_ups, 2)
	check_eq(RunState.xp_to_next_level(), 36, "third level-up needs (3+3)^2")
	RunState.start_run(4, 1)
	check_eq(RunState.level, 1, "a new run starts at level 1 again")
	check_eq(RunState.xp_to_next_level(), int(ceil(16 * 2.8)), "co-op scaling")


func test_talent_points_start_at_level_10() -> void:
	RunState.start_run(1, 1)
	check_eq(RunState.talent_points_earned(), 0, "none at the start")
	RunState.level = 9
	check_eq(RunState.talent_points_earned(), 0, "none at level 9")
	RunState.level = 10
	check_eq(RunState.talent_points_earned(), 1, "first point at level 10")
	RunState.level = 14
	check_eq(RunState.talent_points_earned(), 5, "one per level after")
	RunState.start_run(1, 1)


func test_wave_duration() -> void:
	# GDD 1: waves 1-10 = min(60, 20 + 5 * (w - 1)); above 10: +10 s per wave.
	check_eq(RunState.wave_duration(1), 20.0, "wave 1")
	check_eq(RunState.wave_duration(5), 40.0, "wave 5")
	check_eq(RunState.wave_duration(8), 55.0, "wave 8")
	check_eq(RunState.wave_duration(9), 60.0, "wave 9 hits the cap")
	check_eq(RunState.wave_duration(10), 60.0, "wave 10 capped")
	check_eq(RunState.wave_duration(11), 70.0, "wave 11")
	check_eq(RunState.wave_duration(15), 110.0, "wave 15")
	check_eq(RunState.wave_duration(20), 160.0, "wave 20")
	check_eq(RunState.wave_duration(25), 210.0, "wave 25")
	var total := 0.0
	for w in range(1, RunState.TOTAL_WAVES + 1):
		total += RunState.wave_duration(w)
		if w > 1:
			check(RunState.wave_duration(w) >= RunState.wave_duration(w - 1), "never shorter than the previous wave (%d)" % w)
	check_near(total / 60.0, 42.0, 1.0, "a full run is ~42 minutes of fighting")


func test_join_rejects_duplicate_device_and_caps_at_four() -> void:
	check(PlayerManager.join(ScriptedInput.new("a")) != null, "first join")
	check(PlayerManager.join(ScriptedInput.new("a")) == null, "same device rejected")
	PlayerManager.join(ScriptedInput.new("b"))
	PlayerManager.join(ScriptedInput.new("c"))
	PlayerManager.join(ScriptedInput.new("d"))
	check(PlayerManager.join(ScriptedInput.new("e")) == null, "fifth rejected")
	check_eq(PlayerManager.count(), 4)
	PlayerManager.leave(1)
	var slot := PlayerManager.join(ScriptedInput.new("e"))
	check_eq(slot.index, 1, "reuses freed slot")


func test_input_edges_and_nav_repeat() -> void:
	var input := ScriptedInput.new()
	input.press(PlayerInput.Pad.A)
	input.poll(0.016)
	check(input.just_pressed(PlayerInput.Pad.A), "edge on first frame")
	input.poll(0.016)
	check(not input.just_pressed(PlayerInput.Pad.A), "no edge while held")
	input.move = Vector2(1, 0)
	input.poll(0.016)
	check_eq(input.nav_just_pressed(), Vector2i(1, 0), "nav fires")
	input.poll(0.1)
	check_eq(input.nav_just_pressed(), Vector2i.ZERO, "nav waits for repeat delay")
	input.poll(0.5)
	check_eq(input.nav_just_pressed(), Vector2i(1, 0), "nav repeats")
