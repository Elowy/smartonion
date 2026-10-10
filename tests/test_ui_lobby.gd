extends TestCase
## Lobby: joining toggle, join / ready / leave / class cycling via per-slot input, countdown.

const UiFakes := preload("res://tests/ui_fakes.gd")

var lobby: Lobby
var starts := 0
var backs := 0


func before_each() -> void:
	UiFakes.reset_players()
	lobby = Lobby.create()
	lobby.start_requested.connect(func() -> void: starts += 1)
	lobby.back_requested.connect(func() -> void: backs += 1)
	UiFakes.add_to_root(tree, lobby)


func after_each() -> void:
	UiFakes.free_node(lobby)
	lobby = null
	UiFakes.reset_players()


func _join(key: String, class_id: StringName = &"warrior") -> UiFakes.HumanInput:
	var input := UiFakes.HumanInput.new(key)
	PlayerManager.join(input, Db.get_class_data(class_id))
	return input


func test_joining_enabled_only_while_visible() -> void:
	check(PlayerManager.joining_enabled, "visible lobby enables joining")
	lobby.hide()
	check(not PlayerManager.joining_enabled, "hidden lobby disables joining")
	lobby.show()
	check(PlayerManager.joining_enabled, "shown again")
	UiFakes.free_node(lobby)
	lobby = null
	check(not PlayerManager.joining_enabled, "freed lobby disables joining")


func test_cards_follow_joins_and_leaves() -> void:
	check_eq(lobby.cards.size(), 4, "four slot cards")
	UiFakes.step(lobby)
	check(lobby.cards[0].slot == null, "empty before joining")
	var input := _join("pad:a", &"mage")
	UiFakes.step(lobby)
	var slot := PlayerManager.get_slot(0)
	check(lobby.cards[0].slot == slot, "card 0 shows P1")
	check(lobby.cards[0].preview.visible, "live preview shown")
	check(lobby.cards[0].preview.model != null, "preview has an onion")
	check(lobby.cards[1].slot == null, "card 1 still empty")
	UiFakes.tap(lobby, input, PlayerInput.Pad.B)
	check_eq(PlayerManager.count(), 0, "B while not ready leaves")
	check(lobby.cards[0].slot == null, "card emptied")


func test_ready_toggle_and_unready_with_b() -> void:
	var input := _join("pad:a")
	var slot := PlayerManager.get_slot(0)
	var input2 := _join("pad:b")
	UiFakes.tap(lobby, input, PlayerInput.Pad.A)
	check(slot.ready, "A readies")
	UiFakes.tap(lobby, input, PlayerInput.Pad.A)
	check(not slot.ready, "A again unreadies (toggle)")
	UiFakes.tap(lobby, input, PlayerInput.Pad.START)
	check(slot.ready, "START readies")
	UiFakes.tap(lobby, input, PlayerInput.Pad.B)
	check(not slot.ready, "B unreadies first")
	check_eq(PlayerManager.count(), 2, "and does not leave while ready")
	UiFakes.tap(lobby, input2, PlayerInput.Pad.B)
	check_eq(PlayerManager.count(), 1, "B while not ready leaves")
	check(PlayerManager.get_slot(1) == null, "P2 left")


func test_class_cycles_with_left_right() -> void:
	var input := _join("pad:a", &"warrior")
	var slot := PlayerManager.get_slot(0)
	UiFakes.nudge(lobby, input, Vector2.RIGHT)
	check_eq(slot.class_data.id, Db.cycle_class(&"warrior", 1), "right -> next class")
	UiFakes.nudge(lobby, input, Vector2.LEFT)
	check_eq(slot.class_data.id, &"warrior", "left -> back")
	UiFakes.nudge(lobby, input, Vector2.LEFT)
	check_eq(slot.class_data.id, Db.class_ids[Db.class_ids.size() - 1], "wraps around")
	var before := slot.class_data.id
	UiFakes.tap(lobby, input, PlayerInput.Pad.A)
	UiFakes.nudge(lobby, input, Vector2.RIGHT)
	check_eq(slot.class_data.id, before, "ready locks the class")
	UiFakes.tap(lobby, input, PlayerInput.Pad.B)
	check(not slot.ready, "unready again")
	input.press(PlayerInput.Pad.DPAD_RIGHT)
	UiFakes.step(lobby)
	input.release(PlayerInput.Pad.DPAD_RIGHT)
	UiFakes.step(lobby, 0.0)
	check_eq(slot.class_data.id, Db.cycle_class(before, 1), "d-pad works once unready")


func test_countdown_starts_when_everyone_ready() -> void:
	var a := _join("pad:a")
	var b := _join("pad:b")
	UiFakes.tap(lobby, a, PlayerInput.Pad.A)
	check(not lobby.is_counting_down(), "one of two ready: no countdown")
	UiFakes.tap(lobby, b, PlayerInput.Pad.A)
	check(lobby.is_counting_down(), "all ready: countdown")
	check_eq(lobby.countdown_left, Lobby.COUNTDOWN_TIME, "full countdown")
	UiFakes.step(lobby, 1.0)
	UiFakes.step(lobby, 1.0)
	check_eq(starts, 0, "not yet")
	UiFakes.step(lobby, 1.05)
	check_eq(starts, 1, "start_requested after the countdown")
	check(not PlayerManager.joining_enabled, "joining stops when the run starts")
	UiFakes.step(lobby, 1.0)
	check_eq(starts, 1, "emitted once")


func test_countdown_cancelled_by_unready_and_by_join() -> void:
	var a := _join("pad:a")
	UiFakes.tap(lobby, a, PlayerInput.Pad.A)
	check(lobby.is_counting_down(), "solo ready counts down")
	UiFakes.step(lobby, 1.0)
	UiFakes.tap(lobby, a, PlayerInput.Pad.B)
	check(not lobby.is_counting_down(), "unready cancels")
	UiFakes.tap(lobby, a, PlayerInput.Pad.A)
	check_eq(lobby.countdown_left, Lobby.COUNTDOWN_TIME, "restarts from the top")
	UiFakes.step(lobby, 2.0)
	_join("pad:b")
	UiFakes.step(lobby, 2.0)
	check(not lobby.is_counting_down(), "a new (unready) player cancels")
	check_eq(starts, 0, "never started")


func test_back_only_when_nobody_joined() -> void:
	lobby.pads.injected.append(JOY_BUTTON_B)
	UiFakes.step(lobby)
	check_eq(backs, 1, "B on any controller with nobody joined -> back")
	var a := _join("pad:a")
	UiFakes.step(lobby)
	lobby.pads.injected.append(JOY_BUTTON_B)
	UiFakes.step(lobby)
	check_eq(backs, 1, "no back while someone is joined")
	# The last player leaving with B must not also trigger back in the same frame.
	lobby.pads.injected.append(JOY_BUTTON_B)
	UiFakes.tap(lobby, a, PlayerInput.Pad.B)
	check_eq(PlayerManager.count(), 0, "left")
	check_eq(backs, 1, "leave does not double as back")


func test_showing_resets_ready_flags() -> void:
	_join("pad:a")
	var slot := PlayerManager.get_slot(0)
	slot.ready = true
	lobby.hide()
	lobby.show()
	check(not slot.ready, "ready cleared when the lobby is shown")
	check(not lobby.is_counting_down(), "no countdown")


func test_disconnect_frees_the_slot() -> void:
	_join("pad:a")
	var slot := PlayerManager.get_slot(0)
	PlayerManager.device_disconnected.emit(slot)
	check_eq(PlayerManager.count(), 0, "unplugged controller leaves the lobby")
