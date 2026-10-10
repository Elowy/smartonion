extends TestCase
## Reproducible simulation: bots decide once per UNPAUSED physics tick (not per rendered frame,
## not while paused), and Main's "Wave cleared!" delay counts physics ticks. Like the other
## test_coop_* tests these are synchronous (they never advance a real frame).

const DT := 1.0 / 60.0

var main: Main
var arena: Arena


func before_each() -> void:
	PlayerManager.clear()
	PlayerManager.joining_enabled = false
	tree.paused = false


func after_each() -> void:
	for node: Node in [main, arena]:
		if node != null and is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	main = null
	arena = null
	tree.paused = false
	PlayerManager.clear()
	Enemy.invalidate_player_cache()


## A bot-driven hero standing at the origin with an enemy 3 m to its right (a mage backs off).
func _bot_with_enemy() -> BotInput:
	arena = Arena.create()
	tree.root.add_child(arena)
	var slot := PlayerManager.add_bot(&"mage", 7)
	var hero := Player.create(slot)
	arena.entities.add_child(hero)
	hero.global_position = Vector3.ZERO
	var enemy := Node3D.new()
	enemy.add_to_group(&"enemies")
	arena.entities.add_child(enemy)
	enemy.global_position = Vector3(3.0, 0.0, 0.0)
	return slot.input as BotInput


func test_bots_do_not_decide_in_the_per_frame_poll() -> void:
	var bot := _bot_with_enemy()
	bot.poll(DT)
	check_eq(bot.get_move(), Vector2.ZERO, "poll() only reads the button edges")
	bot.think(DT)
	check(bot.get_move().x < -0.5, "think() decides (the mage backs away from the enemy)")


func test_player_manager_lets_bots_think_once_per_unpaused_physics_tick() -> void:
	var bot := _bot_with_enemy()
	PlayerManager._process(DT)  # a rendered frame: polls, no decisions
	check_eq(bot.get_move(), Vector2.ZERO, "a rendered frame does not move the bot")
	check_eq(PlayerManager.process_physics_priority, PlayerManager.process_priority, "decides before bodies move")
	PlayerManager._physics_process(DT)
	check(bot.get_move().x < -0.5, "a physics tick makes the decision")
	bot.move = Vector2.ZERO
	tree.paused = true
	PlayerManager._physics_process(DT)
	check_eq(bot.get_move(), Vector2.ZERO, "no thinking while the game is paused")
	tree.paused = false


func test_wave_end_delay_counts_physics_ticks_not_frames() -> void:
	main = Main.create(LaunchOptions.new())
	tree.root.add_child(main)
	PlayerManager.add_bot(&"warrior", 1)
	main.start_run()
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	check_eq(main.state, Main.State.WAVE_END, "wave cleared")
	for i in 20:
		main._process(1.0)  # rendered frames of any length do not count
	check_eq(main.state, Main.State.WAVE_END, "frames do not end the banner")
	for i in 90:
		main._physics_process(DT)
	check_eq(main.state, Main.State.WAVE_END, "90 ticks (1.5 s) are not enough")
	for i in 10:
		main._physics_process(DT)
	check_eq(main.state, Main.State.INTERMISSION, "100 ticks (1.67 s) end it")
	# Paused ticks (the intermission freezes the tree) do not run the timer either.
	var t := main._state_time
	main._physics_process(DT)
	check_eq(main._state_time, t, "no counting while paused")
