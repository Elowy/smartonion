extends TestCase


func before_each() -> void:
	PlayerManager.clear()


func after_each() -> void:
	PlayerManager.clear()


func test_launch_content_loads() -> void:
	check_eq(Db.class_ids, [&"warrior", &"mage", &"paladin", &"rogue", &"warlock"] as Array[StringName], "class order")
	check_eq(Db.weapons.size(), 10, "weapon count")
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


func test_shared_xp_levels() -> void:
	RunState.start_run(1, 1)
	check_eq(RunState.xp_to_next_level(), 16, "level 1 needs (1+3)^2")
	RunState.add_xp(16 + 25 + 3)
	check_eq(RunState.level, 2)
	check_eq(RunState.xp, 3)
	check_eq(RunState.pending_level_ups, 2)
	RunState.start_run(4, 1)
	check_eq(RunState.xp_to_next_level(), int(ceil(16 * 2.8)), "co-op scaling")


func test_wave_duration() -> void:
	check_eq(RunState.wave_duration(1), 20.0)
	check_eq(RunState.wave_duration(5), 40.0)
	check_eq(RunState.wave_duration(25), 60.0)


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
