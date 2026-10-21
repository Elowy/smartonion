extends TestCase
## Local co-op input / device handling regressions: the join press is swallowed (no auto-ready,
## a join cancels the countdown), ghost slots of unplugged controllers, the pause menu with a
## held stick and its quit confirmation, disconnects around a wave start, "Continue without Pn",
## the Game Over screen reading only slot inputs, the shared keyboard join keys and the nav
## hysteresis near the diagonals.

const UiFakes := preload("res://tests/ui_fakes.gd")
const DT := 1.0 / 60.0
## Every keyboard key the tests press (released again in before_each / after_each).
## All tests here are synchronous on purpose: they never await a frame. The enemies tests
## (which run later in the same engine frame) step bodies by hand and move_and_slide() then
## uses Engine's last PROCESS delta, so a real frame advancing in between (headless frames are
## ~1 ms) shortens every movement they measure. A press of a ui_* key (Enter, Space) leaves
## Input.is_action_just_pressed() true for the rest of the frame, so _release_keys() also
## resets the actions.
const TEST_KEYS: Array[Key] = [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER, KEY_F, KEY_D]

var lobby: Lobby
var main: Main
var starts := 0
## Screens created by a test: freed in after_each even when a check bails out early.
var _screens: Array[Node] = []


func before_each() -> void:
	_release_keys()
	UiFakes.reset_players()
	tree.paused = false


func after_each() -> void:
	_release_keys()
	UiFakes.free_node(lobby)
	lobby = null
	for node in _screens:
		UiFakes.free_node(node)
	_screens.clear()
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	tree.paused = false
	UiFakes.reset_players()
	Enemy.invalidate_player_cache()


# --- Helpers -----------------------------------------------------------------------

func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _release_keys() -> void:
	for code in TEST_KEYS:
		_key(code, false)
	# A key press also marks its ui_* action as "just pressed" for the rest of the frame.
	for action in InputMap.get_actions():
		Input.action_release(action)


func _make_lobby() -> Lobby:
	lobby = Lobby.create()
	lobby.start_requested.connect(func() -> void: starts += 1)
	UiFakes.add_to_root(tree, lobby)
	return lobby


## One real frame of the lobby: PlayerManager polls every slot and scans for joins first.
func _lobby_frame(delta: float = DT) -> void:
	PlayerManager._process(delta)
	lobby._process(delta)


func _human(key: String, class_id: StringName = &"warrior") -> UiFakes.HumanInput:
	var input := UiFakes.HumanInput.new(key)
	PlayerManager.join(input, Db.get_class_data(class_id))
	return input


func _make_main() -> Main:
	main = Main.create(LaunchOptions.new())
	tree.root.add_child(main)
	return main


func _clear_wave_and_wait() -> void:
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	main._physics_process(Main.WAVE_END_DELAY + 0.01)


## One frame of the open pause menu (its own input polling included).
func _menu_frame(delta: float = DT) -> void:
	UiFakes.step(main.pause_menu, delta)


func _down(p: Player) -> void:
	for i in 60:
		if p.downed:
			return
		p.invulnerable_left = 0.0
		p.take_damage(100000.0, CombatMath.KIND_MELEE, null)


# --- PlayerInput.swallow() ----------------------------------------------------------

func test_swallow_removes_the_edges_of_held_buttons() -> void:
	var input := UiFakes.HumanInput.new("pad:a")
	input.press(PlayerInput.Pad.A)
	input.swallow()
	check(input.is_pressed(PlayerInput.Pad.A), "still held")
	check(not input.just_pressed(PlayerInput.Pad.A), "but not 'just pressed'")
	input.poll(DT)
	check(not input.just_pressed(PlayerInput.Pad.A), "and not on the next frame either")
	input.release(PlayerInput.Pad.A)
	input.poll(DT)
	input.press(PlayerInput.Pad.A)
	input.poll(DT)
	check(input.just_pressed(PlayerInput.Pad.A), "a fresh press after the release is seen")


func test_swallow_holds_back_navigation_until_neutral() -> void:
	var input := UiFakes.HumanInput.new("pad:a")
	input.move = Vector2.RIGHT
	input.swallow()
	check_eq(input.nav_held(), Vector2i.RIGHT, "nav_held reports the held direction")
	check_eq(input.nav_just_pressed(), Vector2i.ZERO, "no edge right after swallow()")
	for i in 90:  # 1.5 s held: well past the key-repeat delay
		input.poll(DT)
		check_eq(input.nav_just_pressed(), Vector2i.ZERO, "no edge / repeat while the old push is held")
	input.move = Vector2.DOWN
	input.poll(DT)
	check_eq(input.nav_just_pressed(), Vector2i.ZERO, "a changed direction without a neutral stick stays swallowed")
	input.move = Vector2.ZERO
	input.poll(DT)
	check_eq(input.nav_held(), Vector2i.ZERO, "neutral")
	input.move = Vector2.RIGHT
	input.poll(DT)
	check_eq(input.nav_just_pressed(), Vector2i.RIGHT, "after a neutral frame the next push navigates")


# --- Join press is swallowed ----------------------------------------------------------

func test_join_press_does_not_ready_the_new_player() -> void:
	_make_lobby()
	_lobby_frame()
	_key(KEY_F, true)
	_lobby_frame()
	check_eq(PlayerManager.count(), 1, "F joins the keyboard player")
	var slot := PlayerManager.get_slot(0)
	check(slot != null and not slot.ready, "joined but not ready on the join frame")
	for i in 5:
		_lobby_frame()
	check(not slot.ready, "still not ready while the join key is held")
	_key(KEY_F, false)
	_lobby_frame()
	_lobby_frame()
	check(not slot.ready, "and after releasing it")
	_key(KEY_F, true)
	_lobby_frame()
	check(slot.ready, "a second press readies as usual")
	_key(KEY_F, false)


func test_join_cancels_a_running_countdown() -> void:
	_make_lobby()
	var a := _human("pad:a")
	UiFakes.tap(lobby, a, PlayerInput.Pad.A)
	check(lobby.is_counting_down(), "P1 ready -> countdown")
	_lobby_frame(1.0)
	check(lobby.is_counting_down(), "still counting")
	_key(KEY_F, true)
	_lobby_frame(0.1)
	check_eq(PlayerManager.count(), 2, "the keyboard joined mid-countdown")
	check(not PlayerManager.get_slot(1).ready, "the newcomer is not ready")
	check(not lobby.is_counting_down(), "the join cancelled the countdown")
	for i in 5:
		_lobby_frame(1.0)  # 5 s with the join key still down
	check_eq(starts, 0, "the run never started")
	check(not lobby.is_counting_down(), "still no countdown")
	check(PlayerManager.get_slot(0).ready and not PlayerManager.get_slot(1).ready, "P1 stays ready, P2 not")
	_key(KEY_F, false)


func test_stick_held_while_joining_does_not_move_the_class_cursor() -> void:
	_make_lobby()
	_lobby_frame()
	_key(KEY_D, true)
	_key(KEY_F, true)
	_lobby_frame()
	var slot := PlayerManager.get_slot(0)
	check(slot != null, "joined")
	if slot == null:
		return
	var joined_as := slot.class_data.id
	for i in 60:
		_lobby_frame()
	check_eq(slot.class_data.id, joined_as, "no class change from the stick held at join time")
	_key(KEY_D, false)
	_key(KEY_F, false)
	_lobby_frame()
	_key(KEY_D, true)
	_lobby_frame()
	check_eq(slot.class_data.id, Db.cycle_class(joined_as, 1), "a new push after the release cycles the class")


func test_all_keyboard_join_keys_join_and_confirm() -> void:
	check_eq(KeyboardInput.JOIN_KEYS.size(), 4, "Enter, Space, Keypad Enter and F")
	for code in KeyboardInput.JOIN_KEYS:
		var key_name := OS.get_keycode_string(code)
		UiFakes.reset_players()
		_make_lobby()
		_lobby_frame()
		_key(code, true)
		check(UiPads.join_button_held(), "UiPads treats %s as a join button" % key_name)
		check(KeyboardInput.join_key_held(), "join_key_held (%s)" % key_name)
		var kb := KeyboardInput.new()
		kb.poll(DT)
		check(kb.is_pressed(PlayerInput.Pad.A), "%s is the keyboard's A too" % key_name)
		_lobby_frame()
		check_eq(PlayerManager.count(), 1, "%s joins" % key_name)
		check(not PlayerManager.get_slot(0).ready, "%s: the join press is swallowed" % key_name)
		_key(code, false)
		_lobby_frame()
		UiFakes.free_node(lobby)
		lobby = null


# --- Ghost slots ---------------------------------------------------------------------

func test_lobby_keeps_the_slot_of_an_unplugged_controller_until_the_timeout() -> void:
	_make_lobby()
	var a := _human("pad:a")
	var b := _human("pad:b")
	_lobby_frame()
	check_eq(PlayerManager.count(), 2, "both joined")
	b.connected = false
	_lobby_frame()
	check_eq(PlayerManager.count(), 2, "RPT-CORE: the slot waits as 'Disconnected – press A to take over'")
	UiFakes.tap(lobby, a, PlayerInput.Pad.A)
	check(not lobby.is_counting_down(), "a ghost cannot ready up: the start waits for it")
	_lobby_frame(PlayerManager.GHOST_TIMEOUT + 1.0)
	check_eq(PlayerManager.count(), 1, "freed after the long timeout")
	check(PlayerManager.get_slot(1) == null, "P2 left")
	UiFakes.tap(lobby, a, PlayerInput.Pad.A)
	UiFakes.tap(lobby, a, PlayerInput.Pad.A)
	check(lobby.is_counting_down(), "P1 alone can start now")


func test_lobby_keeps_ghosts_when_shown_and_restarts_their_clock() -> void:
	_make_lobby()
	_human("pad:a")
	var b := _human("pad:b")
	lobby.hide()
	b.connected = false
	PlayerManager.get_slot(1).missing_time = 500.0
	lobby.show()
	check_eq(PlayerManager.count(), 2, "reset() keeps the slot of the unplugged controller (its clock restarts)")
	check_near(PlayerManager.get_slot(1).missing_time, 0.0, 0.001, "clock restarted")


func test_prune_keeps_bots_and_working_devices() -> void:
	PlayerManager.add_bot(&"warrior", 1)
	_human("pad:a")
	var c := _human("pad:c")
	check(PlayerManager.disconnected_slots().is_empty(), "everybody connected")
	check(PlayerManager.has_connected_human(), "a connected human exists")
	c.connected = false
	check_eq(PlayerManager.disconnected_slots().size(), 1, "one unplugged")
	check_eq(PlayerManager.prune_disconnected(), 1, "one slot pruned")
	check_eq(PlayerManager.count(), 2, "bot and the working pad stay")


func test_game_over_to_lobby_drops_the_ghost_slot() -> void:
	_make_main()
	var a := _human("pad:a")
	var b := _human("pad:b")
	main.start_run()
	main.end_run(false)
	b.connected = false
	PlayerManager.device_disconnected.emit(PlayerManager.get_slot(1))
	main._on_game_over_back()
	check_eq(main.state, Main.State.LOBBY, "lobby")
	check_eq(PlayerManager.count(), 1, "the ghost slot did not come along")
	UiFakes.tap(main.lobby, a, PlayerInput.Pad.A)
	check(main.lobby.is_counting_down(), "P1 can ready up and start")


# --- Pause menu: held stick, quit confirmation ------------------------------------------

func _pause_menu() -> PauseMenu:
	var menu := PauseMenu.create()
	UiFakes.add_to_root(tree, menu)
	_screens.append(menu)
	return menu


func test_pause_ignores_the_stick_held_from_gameplay() -> void:
	var menu := _pause_menu()
	var a := _human("pad:a")
	a.move = Vector2.DOWN  # running down the screen when START was pressed
	for i in 60:
		a.poll(DT)
	menu.open(PlayerManager.get_slot(0))
	var last := menu.selected
	var changes := 0
	for i in 60:
		UiFakes.step(menu)
		if menu.selected != last:
			changes += 1
			last = menu.selected
	check_eq(changes, 0, "the held stick must not flicker the selection")
	check_eq(menu.selected, PauseMenu.Item.RESUME, "Resume stays highlighted")
	UiFakes.nudge(menu, a, Vector2.ZERO)
	UiFakes.nudge(menu, a, Vector2.DOWN)
	check_eq(menu.selected, PauseMenu.Item.SETTINGS, "after one neutral frame the stick navigates again")
	UiFakes.free_node(menu)


func test_nav_held_reports_the_quantised_direction() -> void:
	var input := UiFakes.HumanInput.new("pad:a")
	input.move = Vector2(0.3, 0.2)
	input.poll(DT)
	check_eq(input.nav_held(), Vector2i.ZERO, "inside the deadzone")
	input.move = Vector2(0.1, 0.9)
	input.poll(DT)
	check_eq(input.nav_held(), Vector2i.DOWN, "down")
	for i in 60:
		input.poll(DT)
	check_eq(input.nav_held(), Vector2i.DOWN, "nav_held does not repeat or expire")


func test_quit_needs_a_second_press() -> void:
	var menu := _pause_menu()
	var quits: Array[int] = [0]
	var resumes: Array[int] = [0]
	menu.quit_to_menu_requested.connect(func() -> void: quits[0] += 1)
	menu.resume_requested.connect(func() -> void: resumes[0] += 1)
	var a := _human("pad:a")
	menu.open(PlayerManager.get_slot(0))
	UiFakes.step(menu)
	UiFakes.nudge(menu, a, Vector2.DOWN)
	UiFakes.nudge(menu, a, Vector2.DOWN)  # (Resume, Settings, Quit)
	check_eq(menu.selected, PauseMenu.Item.QUIT, "Quit highlighted")
	UiFakes.tap(menu, a, PlayerInput.Pad.A)
	check_eq(quits[0], 0, "one A press does not quit")
	check(menu.quit_armed and menu.visible, "it asks first")
	check_eq(menu.button_for(PauseMenu.Item.QUIT).text, PauseMenu.QUIT_CONFIRM_TEXT, "the button asks 'Are you sure?'")
	UiFakes.nudge(menu, a, Vector2.UP)
	check(not menu.quit_armed, "moving the highlight cancels the question")
	check_eq(menu.button_for(PauseMenu.Item.QUIT).text, PauseMenu.QUIT_TEXT, "button text restored")
	UiFakes.nudge(menu, a, Vector2.DOWN)
	UiFakes.tap(menu, a, PlayerInput.Pad.A)
	check_eq(quits[0], 0, "armed again, still not quit")
	UiFakes.tap(menu, a, PlayerInput.Pad.A)
	check_eq(quits[0], 1, "the second press quits")
	check_eq(resumes[0], 0, "never resumed")
	UiFakes.free_node(menu)


func test_clicking_quit_also_asks() -> void:
	var menu := _pause_menu()
	var quits: Array[int] = [0]
	menu.quit_to_menu_requested.connect(func() -> void: quits[0] += 1)
	menu.open(null)
	menu.button_for(PauseMenu.Item.QUIT).pressed.emit()
	check_eq(quits[0], 0, "first click asks")
	menu.button_for(PauseMenu.Item.QUIT).pressed.emit()
	check_eq(quits[0], 1, "second click quits")
	UiFakes.free_node(menu)


# --- Disconnects ------------------------------------------------------------------------

func test_wave_start_with_a_missing_pad_pauses_at_once() -> void:
	_make_main()
	_human("pad:a")
	var b := _human("pad:b")
	b.connected = false
	main.start_run()
	check_eq(main.state, Main.State.WAVE, "wave running")
	check(tree.paused and main.is_paused(), "paused straight away")
	check(main.hud.is_notice_visible(), "with the notice")
	check("P2" in main.hud.notice_label.text, "naming P2: %s" % main.hud.notice_label.text)


func test_next_wave_start_with_a_pad_unplugged_in_the_intermission_pauses() -> void:
	_make_main()
	_human("pad:a")
	var b := _human("pad:b")
	main.start_run()
	_clear_wave_and_wait()
	check_eq(main.state, Main.State.INTERMISSION, "intermission")
	b.connected = false
	PlayerManager.device_disconnected.emit(PlayerManager.get_slot(1))
	check(not main.is_paused(), "no pause menu over the intermission")
	main._on_intermission_continue()
	check_eq(main.state, Main.State.WAVE, "wave 2")
	check(tree.paused and main.is_paused(), "wave 2 starts paused")
	check(main.hud.is_notice_visible(), "with the notice")


func test_start_cannot_resume_while_a_pad_is_unplugged() -> void:
	_make_main()
	var a := _human("pad:a")
	var b := _human("pad:b")
	main.start_run()
	b.connected = false
	PlayerManager.device_disconnected.emit(PlayerManager.get_slot(1))
	check(main.is_paused(), "paused by the disconnect")
	var menu := main.pause_menu
	_menu_frame()  # the skipped first frame
	for i in 2:
		a.press(PlayerInput.Pad.START)
		_menu_frame()
		a.release(PlayerInput.Pad.START)
		_menu_frame()
	check(menu.visible and tree.paused, "START does not resume")
	check_eq(menu.entries, [PauseMenu.Item.RESUME, PauseMenu.DROP_BASE + 1, PauseMenu.Item.SETTINGS, PauseMenu.Item.QUIT] as Array[int],
		"Resume / Continue without P2 / Settings / Quit")
	check_eq(menu.buttons[1].text, "Continue without P2", "the offer names the player")
	menu.activate_selected()
	check(menu.visible, "the Resume entry does not resume either")
	main.resume_game()
	check(main.is_paused() and tree.paused, "Main.resume_game() keeps the game paused too")
	# The pad comes back: START resumes again.
	b.connected = true
	PlayerManager.device_reconnected.emit(PlayerManager.get_slot(1))
	_menu_frame()
	check_eq(menu.entries.size(), 3, "the offer disappears")
	a.press(PlayerInput.Pad.START)
	_menu_frame()
	check(not menu.visible, "START resumes with every pad back")


func test_pausing_players_own_pad_dying_leaves_the_menu_usable() -> void:
	_make_main()
	var a := _human("pad:a")
	_human("pad:b")
	main.start_run()
	main.pause_game(PlayerManager.get_slot(0))
	_menu_frame()
	a.connected = false
	PlayerManager.device_disconnected.emit(PlayerManager.get_slot(0))
	_menu_frame()
	check_eq(main.pause_menu.slot, PlayerManager.get_slot(0), "P1 is still the pausing slot")
	main.pause_menu.pads.injected.append(JOY_BUTTON_A)
	main.pause_menu.move_selection(1)  # Continue without P1 (the fallback drives the menu)
	check_eq(main.pause_menu.selected, PauseMenu.DROP_BASE, "drop entry highlighted")
	var dropped: Array[PlayerSlot] = []
	main.pause_menu.drop_player_requested.connect(func(s: PlayerSlot) -> void: dropped.append(s))
	_menu_frame()
	check_eq(dropped.size(), 1, "the fallback (any connected pad's A) can choose it")


func test_continue_without_removes_the_player_and_keeps_the_run_going() -> void:
	_make_main()
	var a := _human("pad:a")
	var b := _human("pad:b")
	main.start_run()
	var hero_b := main.players[1]
	var slot_b := PlayerManager.get_slot(1)
	b.connected = false
	PlayerManager.device_disconnected.emit(slot_b)
	check(main.is_paused(), "paused")
	main.drop_player(slot_b)
	check_eq(PlayerManager.count(), 1, "slot P2 left")
	check(PlayerManager.get_slot(1) == null, "slot index 1 is free again")
	check_eq(main.players.size(), 1, "one hero left in the run")
	check(main.players[0].slot == PlayerManager.get_slot(0), "and it is P1's")
	check(not is_instance_valid(hero_b) or hero_b.is_queued_for_deletion() or not hero_b.is_inside_tree(), "P2's hero is gone")
	check(slot_b.player == null, "slot no longer points at the hero")
	check_eq(main.state, Main.State.WAVE, "still in the wave")
	check(not tree.paused and not main.is_paused(), "the game resumed")
	check(not main.hud.is_notice_visible(), "notice gone")
	a.press(PlayerInput.Pad.START)
	a.poll(DT)
	main._process(DT)
	check(main.is_paused(), "P1 can still pause afterwards")


func test_continue_without_through_the_menu() -> void:
	_make_main()
	_human("pad:a")
	var b := _human("pad:b")
	main.start_run()
	b.connected = false
	PlayerManager.device_disconnected.emit(PlayerManager.get_slot(1))
	var menu := main.pause_menu
	check(menu.drop_player_requested.is_connected(main.drop_player), "Main listens to the menu's drop request")
	var dropped: Array[PlayerSlot] = []
	menu.drop_player_requested.connect(func(s: PlayerSlot) -> void: dropped.append(s))
	_menu_frame()
	menu.move_selection(1)
	check_eq(menu.selected, PauseMenu.DROP_BASE + 1, "Continue without P2 highlighted")
	menu.pads.injected.append(JOY_BUTTON_A)
	_menu_frame()
	check_eq(dropped.size(), 1, "A on the entry requests the drop")
	check(dropped.size() == 1 and dropped[0] == PlayerManager.get_slot(1), "for P2's slot")
	check(menu.visible, "the menu stays up until Main has handled it")
	# Main's connection is deferred (the new state never sees the press): run what it queues.
	main.drop_player(dropped[0])
	check_eq(PlayerManager.count(), 1, "P2 removed")
	check(not tree.paused and not menu.visible, "run resumed")
	check_eq(main.state, Main.State.WAVE, "wave goes on")


func test_continue_without_keeps_pausing_while_another_pad_is_missing() -> void:
	_make_main()
	_human("pad:a")
	var b := _human("pad:b")
	var c := _human("pad:c")
	main.start_run()
	b.connected = false
	c.connected = false
	PlayerManager.device_disconnected.emit(PlayerManager.get_slot(1))
	PlayerManager.device_disconnected.emit(PlayerManager.get_slot(2))
	main.drop_player(PlayerManager.get_slot(1))
	check(main.is_paused() and tree.paused, "P3 is still missing: stay paused")
	check("P3" in main.hud.notice_label.text, "notice names P3: %s" % main.hud.notice_label.text)
	_menu_frame()
	check_eq(main.pause_menu.entries, [PauseMenu.Item.RESUME, PauseMenu.DROP_BASE + 2, PauseMenu.Item.SETTINGS, PauseMenu.Item.QUIT] as Array[int],
		"the menu now offers P3")
	main.drop_player(PlayerManager.get_slot(2))
	check(not main.is_paused() and not tree.paused, "last missing pad dropped: running")
	check_eq(main.players.size(), 1, "P1 alone")


func test_continue_without_the_last_player_returns_to_the_lobby() -> void:
	_make_main()
	var a := _human("pad:a")
	main.start_run()
	a.connected = false
	PlayerManager.device_disconnected.emit(PlayerManager.get_slot(0))
	main.drop_player(PlayerManager.get_slot(0))
	check_eq(main.state, Main.State.LOBBY, "nobody left -> lobby")
	check(main.arena == null, "the run is torn down")
	check(not RunState.active, "run ended")
	check(not tree.paused, "not left paused")
	check_eq(PlayerManager.count(), 0, "no slots")


func test_dropping_the_only_living_player_ends_the_run() -> void:
	_make_main()
	_human("pad:a")
	var b := _human("pad:b")
	main.start_run()
	_down(main.players[0])
	check(main.state == Main.State.WAVE, "one downed hero is not a defeat yet")
	b.connected = false
	PlayerManager.device_disconnected.emit(PlayerManager.get_slot(1))
	main.drop_player(PlayerManager.get_slot(1))
	check_eq(main.state, Main.State.GAME_OVER, "the remaining hero is downed: defeat")


# --- Game Over input -------------------------------------------------------------------

func _game_over_screen() -> GameOverScreen:
	var screen := GameOverScreen.create()
	UiFakes.add_to_root(tree, screen)
	_screens.append(screen)
	screen.open(false)
	UiFakes.step(screen, GameOverScreen.INPUT_DELAY)
	return screen


func test_game_over_with_joined_slots_ignores_global_input() -> void:
	var a := _human("pad:a")
	var screen := _game_over_screen()
	var backs: Array[int] = [0]
	screen.back_to_menu_requested.connect(func() -> void: backs[0] += 1)
	screen.pads.injected.append(JOY_BUTTON_A)
	UiFakes.step(screen)
	screen.pads.injected.append(JOY_BUTTON_START)
	UiFakes.step(screen)
	_key(KEY_ENTER, true)  # ui_accept as well (whether Godot reports it as "just pressed" depends on the frame type)
	UiFakes.step(screen)
	_key(KEY_ENTER, false)
	check_eq(backs[0], 0, "another device's A / ui_accept does not act for a joined player")
	UiFakes.tap(screen, a, PlayerInput.Pad.A)
	check_eq(backs[0], 1, "the slot's own A does")
	UiFakes.free_node(screen)


func test_game_over_falls_back_to_global_input_without_a_usable_slot() -> void:
	var backs: Array[int] = [0]
	var screen := _game_over_screen()
	screen.back_to_menu_requested.connect(func() -> void: backs[0] += 1)
	screen.pads.injected.append(JOY_BUTTON_A)
	UiFakes.step(screen)
	check_eq(backs[0], 1, "nobody joined: any controller's A")
	# Every human's controller is unplugged: the screen must not soft-lock.
	var a := _human("pad:a")
	a.connected = false
	screen.open(false)
	UiFakes.step(screen, GameOverScreen.INPUT_DELAY)
	screen.pads.injected.append(JOY_BUTTON_A)
	UiFakes.step(screen)
	check_eq(backs[0], 2, "all joined pads unplugged: global fallback")
	# Bots only (demo): nobody can press a slot button, the global input still works.
	UiFakes.reset_players()
	PlayerManager.add_bot(&"warrior", 1)
	screen.open(false)
	UiFakes.step(screen, GameOverScreen.INPUT_DELAY)
	screen.pads.injected.append(JOY_BUTTON_START)
	UiFakes.step(screen)
	check_eq(backs[0], 3, "bots only: any controller's START")
	UiFakes.free_node(screen)


# --- Nav hysteresis -----------------------------------------------------------------------

func test_nav_does_not_flip_axes_on_a_wobbling_diagonal() -> void:
	var input := UiFakes.HumanInput.new("pad:a")
	var vertical := 0
	var horizontal := 0
	for i in 120:  # 2 s of a stick held at ~45 degrees with +-0.01 wobble
		input.move = Vector2(0.80, 0.79) if i % 2 == 0 else Vector2(0.79, 0.80)
		input.poll(DT)
		var n := input.nav_just_pressed()
		if n.x != 0:
			horizontal += 1
		if n.y != 0:
			vertical += 1
	check(horizontal > 0, "the first axis was picked")
	check_eq(vertical, 0, "and kept (no flip to vertical)")
	# The same with the other axis first.
	var input2 := UiFakes.HumanInput.new("pad:b")
	input2.move = Vector2(0.60, 0.85)
	input2.poll(DT)
	check_eq(input2.nav_just_pressed(), Vector2i.DOWN, "vertical wins clearly")
	for i in 60:
		input2.move = Vector2(0.80, 0.79) if i % 2 == 0 else Vector2(0.79, 0.80)
		input2.poll(DT)
		check_eq(input2.nav_held(), Vector2i.DOWN, "stays vertical on the wobbling diagonal")


func test_nav_switches_axis_when_the_other_one_clearly_wins() -> void:
	var input := UiFakes.HumanInput.new("pad:a")
	input.move = Vector2(0.9, 0.5)
	input.poll(DT)
	check_eq(input.nav_held(), Vector2i.RIGHT, "right")
	input.move = Vector2(0.70, 0.75)
	input.poll(DT)
	check_eq(input.nav_held(), Vector2i.RIGHT, "75 vs 70 is within the hysteresis")
	input.move = Vector2(0.60, 0.78)
	input.poll(DT)
	check_eq(input.nav_held(), Vector2i.DOWN, "more than 0.1 stronger: switch")
	check_eq(input.nav_just_pressed(), Vector2i.DOWN, "and the new direction fires")
	input.move = Vector2(0.9, 0.0)
	input.poll(DT)
	check_eq(input.nav_just_pressed(), Vector2i.RIGHT, "a clear horizontal push fires at once")
