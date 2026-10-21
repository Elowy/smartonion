extends TestCase
## RPT-CORE (Remote Play Together, Steam-free): the pad source with fake hotplug, slot identity and rebinding, the
## lobby / mid-run take-over of a missing player, the grace before the between-wave screens decide, the host rules,
## the RemotePlay autoload with its Null / Fake backends, the --fake-rpt / --hotplug-test flags and the project setting.
## Everything is synchronous: a "frame" is PlayerManager._process() plus the screen's own _process().

const UiFakes := preload("res://tests/ui_fakes.gd")
const DT := 1.0 / 60.0

var lobby: Lobby
var main: Main
var _screens: Array[Node] = []
var _fake: FakeRemotePlayBackend


func before_each() -> void:
	UiFakes.reset_players()
	PadSource.enable_fake(true)
	PlayerManager.takeover_enabled = false
	tree.paused = false


func after_each() -> void:
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
	RemotePlay.set_backend(null)
	_fake = null
	PadSource.enable_fake(false)
	PlayerManager.takeover_enabled = false
	UiFakes.reset_players()
	Enemy.invalidate_player_cache()


# --- Helpers ------------------------------------------------------------------------

## A fake pad on [param device]; its guid is "g<device>" (a pad of its own) unless [param guid] says otherwise.
func _pad(device: int, guid: String = "") -> PadIdentity:
	var g := guid if guid != "" else "g%d" % device
	return PadSource.fake_connect(device, PadIdentity.make(device, "Pad %s" % g, g))


## Joins a fake pad the way the lobby does (the slot remembers the pad's fingerprint).
func _join_pad(device: int, class_id: StringName = &"warrior", guid: String = "") -> PlayerSlot:
	if not PadSource.is_pad_connected(device):
		_pad(device, guid)
	return PlayerManager.join(JoypadInput.new(device), Db.get_class_data(class_id))


func _frame(delta: float = DT) -> void:
	PlayerManager._process(delta)


## A press and a release of [param button] on a fake pad, a PlayerManager frame each.
func _tap_pad(device: int, button: JoyButton = JOY_BUTTON_A) -> void:
	PadSource.fake_press(device, button, true)
	_frame()
	PadSource.fake_press(device, button, false)
	_frame()


func _fake_backend(guests: int = 2) -> FakeRemotePlayBackend:
	_fake = FakeRemotePlayBackend.new(guests)
	RemotePlay.set_backend(_fake)
	return _fake


func _make_lobby() -> Lobby:
	lobby = Lobby.create()
	UiFakes.add_to_root(tree, lobby)
	return lobby


func _make_main() -> Main:
	main = Main.create(LaunchOptions.new())
	tree.root.add_child(main)
	return main


func _menu_frame() -> void:
	PlayerManager._process(DT)
	UiFakes.step(main.pause_menu, DT)


# --- PadSource ----------------------------------------------------------------------

func test_fake_pads_connect_disconnect_and_press() -> void:
	check_eq(PadSource.devices(), [] as Array[int], "no pads")
	_pad(2)
	_pad(0)
	check_eq(PadSource.devices(), [0, 2] as Array[int], "ascending ids")
	check(PadSource.is_pad_connected(2) and not PadSource.is_pad_connected(1), "connected / not")
	check_eq(PadSource.pad_name(2), "Pad g2", "the name comes from the identity")
	PadSource.fake_press(2, JOY_BUTTON_A, true)
	PadSource.fake_axis(2, JOY_AXIS_LEFT_X, 0.8)
	check(PadSource.is_button_down(2, JOY_BUTTON_A) and not PadSource.is_button_down(0, JOY_BUTTON_A), "button state")
	check_near(PadSource.axis_value(2, JOY_AXIS_LEFT_X), 0.8, 0.001, "axis")
	PadSource.fake_disconnect(2)
	check(not PadSource.is_pad_connected(2) and not PadSource.is_button_down(2, JOY_BUTTON_A), "a removed pad reads nothing")
	PadSource.enable_fake(false)
	check_eq(PadSource.devices(), [] as Array[int], "back on the engine: this headless run has no pads")


func test_a_joypad_input_follows_its_own_pad_not_the_id() -> void:
	_pad(1, "pad-x")
	var input := JoypadInput.new(1)
	check(input.is_connected_device(), "its pad is there")
	PadSource.fake_disconnect(1)
	check(not input.is_connected_device(), "unplugged")
	_pad(1, "pad-y")
	check(not input.is_connected_device(), "the id was reused by ANOTHER pad: not this input's pad")
	_pad(1, "pad-x")
	check(input.is_connected_device(), "the same pad (same fingerprint) is back on the id")
	PadSource.fake_press(1, JOY_BUTTON_A, true)
	input.poll(DT)
	check(input.is_pressed(PlayerInput.Pad.A), "buttons come through the pad source")


func test_pad_identity_fingerprint_ignores_the_id() -> void:
	var a := PadIdentity.make(0, "Xbox", "guid1", "", "045e", "02ea")
	var b := PadIdentity.make(3, "Xbox", "guid1", "", "045e", "02ea")
	var c := PadIdentity.make(0, "Xbox", "guid1", "777", "045e", "02ea")
	check(a.same_pad(b), "same model and guid on another id")
	check(not a.same_pad(c), "a Steam handle makes it another pad")
	check(not a.same_pad(null), "null is nobody")


# --- Slot identity, announcements, auto rebind ----------------------------------------------

func test_a_slot_remembers_the_pad_and_its_session() -> void:
	var fake := _fake_backend(2)
	var slot := _join_pad(1)
	check(slot.identity() != null and slot.identity().guid == "g1", "the fingerprint is kept")
	check_eq(slot.session_id, FakeRemotePlayBackend.FAKE_SESSION_BASE + 1, "pad 1 belongs to guest 1")
	check(slot.is_remote(), "so the slot is remote")
	check(not _join_pad(0).is_remote(), "pad 0 is the host's")
	check_eq(RemotePlay.slot_label(slot), "Mira (P1)", "notices use the guest's name")
	check_eq(fake.guest_name(slot.session_id), "Mira", "from the backend")


func test_track_connections_announces_disconnect_and_return() -> void:
	_join_pad(0)
	var slot := _join_pad(1)
	var gone: Array[PlayerSlot] = []
	var back: Array[PlayerSlot] = []
	PlayerManager.device_disconnected.connect(func(s: PlayerSlot) -> void: gone.append(s))
	PlayerManager.device_reconnected.connect(func(s: PlayerSlot) -> void: back.append(s))
	_frame()
	check(gone.is_empty() and back.is_empty(), "nothing happened")
	PadSource.fake_disconnect(1)
	_frame(0.5)
	_frame(0.5)
	check_eq(gone.size(), 1, "announced once")
	check(gone[0] == slot, "for the right slot")
	check_near(slot.missing_time, 1.0, 0.001, "the clock counts how long it is gone")
	check_eq(PlayerManager.disconnected_slots().size(), 1, "it is a ghost")
	_pad(1, "g1")  # the same pad is back on the same id
	_frame()
	check_eq(back.size(), 1, "the return is announced")
	check_near(slot.missing_time, 0.0, 0.001, "the clock restarts")
	check(PlayerManager.disconnected_slots().is_empty(), "no ghost")


func test_a_reused_id_does_not_hand_the_hero_to_another_pad() -> void:
	_join_pad(0)
	var slot := _join_pad(1, &"mage", "owner-pad")
	PadSource.fake_disconnect(1)
	_frame()
	_pad(1, "stranger-pad")  # Godot hands the freed id 1 to the next pad that connects
	_frame()
	check(not slot.input.is_connected_device(), "the slot's pad is NOT the one on joy:1 now")
	check_eq(PlayerManager.disconnected_slots().size(), 1, "the slot is still a ghost")
	check_eq((slot.input as JoypadInput).device, 1, "and still on its old input")
	check(PlayerManager.is_pad_free(1), "the stranger's pad is a free pad")


func test_the_same_pad_on_a_new_id_takes_the_slot_back_by_itself() -> void:
	_join_pad(0)
	var slot := _join_pad(1, &"mage", "owner-pad")
	slot.ready = true
	PadSource.fake_disconnect(1)
	_frame()
	var back: Array[PlayerSlot] = []
	PlayerManager.device_reconnected.connect(func(s: PlayerSlot) -> void: back.append(s))
	_pad(5, "owner-pad")  # it comes back as joy:5
	_frame()
	check(slot.input.is_connected_device(), "the slot has a working pad again")
	check_eq((slot.input as JoypadInput).device, 5, "bound to the new id")
	check_eq(slot.class_data.id, &"mage", "the class is kept")
	check(slot.ready, "so is the ready flag")
	check_eq(slot.index, 1, "and the slot number")
	check_eq(back.size(), 1, "announced as a return")
	check_eq(PlayerManager.count(), 2, "nobody joined or left")


func test_a_guest_session_keeps_its_seat_whatever_pad_it_shows_up_as() -> void:
	var fake := _fake_backend(2)
	_join_pad(0)
	var slot := _join_pad(1, &"warrior", "steam-virtual-1")
	var session := slot.session_id
	PadSource.fake_disconnect(1)
	_frame()
	_pad(6, "steam-virtual-9")  # another virtual pad, nothing in common
	_frame()
	check(not slot.input.is_connected_device(), "a pad of no session is not the guest")
	fake.assign_device(6, session)
	_frame()
	check(slot.input.is_connected_device(), "the same Remote Play session is")
	check_eq((slot.input as JoypadInput).device, 6, "rebound to it")
	check_eq(slot.session_id, session, "the session id stays")


func test_a_host_pad_never_claims_a_guests_seat() -> void:
	_fake_backend(2)
	_join_pad(0)
	var slot := _join_pad(1, &"warrior", "same-model")
	PadSource.fake_disconnect(1)
	_frame()
	_pad(7, "same-model")  # a LOCAL pad with the identical fingerprint (session 0 vs the guest's)
	_frame()
	check(not slot.input.is_connected_device(), "a local pad of the same model is not the guest")


func test_rebind_swaps_the_device_and_keeps_the_player() -> void:
	var slot := _join_pad(0, &"paladin")
	slot.ready = true
	_pad(3, "new")
	var other := _join_pad(2)
	check(not PlayerManager.rebind(0, JoypadInput.new(2)), "a device that another slot uses is refused")
	check(not PlayerManager.rebind(3, JoypadInput.new(3)), "no slot, no rebind")
	var input := JoypadInput.new(3)
	PadSource.fake_press(3, JOY_BUTTON_A, true)
	check(PlayerManager.rebind(0, input), "a free pad is accepted")
	check(PlayerManager.get_slot(0) == slot and slot.input == input, "same slot object, new input")
	check(slot.ready and slot.class_data.id == &"paladin", "class and ready kept")
	check(not input.just_pressed(PlayerInput.Pad.A), "the held press was swallowed")
	check(other.input != input, "the other slot is untouched")


# --- Take-over ----------------------------------------------------------------------

func test_a_free_pad_takes_the_missing_slot_over_in_the_lobby() -> void:
	_make_lobby()
	var a := _join_pad(0)
	var b := _join_pad(1, &"mage")
	b.ready = true
	PadSource.fake_disconnect(1)
	_frame()
	lobby._process(DT)
	check_eq(PlayerManager.count(), 2, "the lobby KEEPS the slot of the missing controller")
	check(PlayerManager.get_slot(1) == b and b.ready, "with its class and ready flag")
	check(lobby.cards[1]._ghost_banner.visible, "its card says Disconnected")
	check_eq(lobby.cards[1]._device_label.text, "Disconnected", "in the header too")
	check("P2 disconnected" in lobby._sub_status.text, "and the footer names who waits: %s" % lobby._sub_status.text)
	# A pad nobody plays presses A: it takes P2 over (it does not join as P3).
	_pad(4, "newcomer")
	_frame()
	_tap_pad(4)
	check_eq(PlayerManager.count(), 2, "no third player")
	check_eq((b.input as JoypadInput).device, 4, "P2 plays on the new pad")
	check(b.ready and b.class_data.id == &"mage", "class and ready state survived")
	check(a.input.is_connected_device(), "P1 untouched")
	# The next free pad's A joins as usual.
	_pad(5, "friend")
	_frame()
	_tap_pad(5)
	check_eq(PlayerManager.count(), 3, "with nobody missing a free pad's A joins")


func test_the_lobby_start_waits_for_a_missing_player() -> void:
	_make_lobby()
	var a := _join_pad(0)
	var b := _join_pad(1)
	a.ready = true
	b.ready = true
	PadSource.fake_disconnect(1)
	for i in 3:
		_frame()
		lobby._process(DT)
	check(not lobby.is_counting_down(), "a ghost cannot be ready: no countdown, whatever its flag says")
	_pad(1, "g1")
	_frame()
	lobby._process(DT)
	check(lobby.is_counting_down(), "the pad is back: the countdown starts")


func test_the_lobby_frees_a_ghost_after_the_timeout() -> void:
	_make_lobby()
	_join_pad(0)
	_join_pad(1)
	PadSource.fake_disconnect(1)
	_frame(PlayerManager.GHOST_TIMEOUT - 1.0)
	lobby._process(DT)
	check_eq(PlayerManager.count(), 2, "still waiting a second before the timeout")
	_frame(2.0)
	lobby._process(DT)
	check_eq(PlayerManager.count(), 1, "freed after the long timeout")


func test_showing_the_lobby_restarts_the_ghost_clock() -> void:
	_join_pad(0)
	var b := _join_pad(1)
	PadSource.fake_disconnect(1)
	_frame(PlayerManager.GHOST_TIMEOUT * 2.0)  # a long run with a missing player
	_make_lobby()
	check_eq(PlayerManager.count(), 2, "the lobby opened: the ghost gets its full time again")
	check_near(b.missing_time, 0.0, 0.001, "clock restarted")


func test_a_fifth_pad_gets_one_party_full_notice() -> void:
	_make_lobby()
	for d in 4:
		_join_pad(d)
	var refused: Array[int] = []
	PlayerManager.join_refused.connect(func(device: int, reason: StringName) -> void:
		if reason == &"full":
			refused.append(device))
	_pad(4, "fifth")
	_frame()
	_tap_pad(4)
	_tap_pad(4)
	check_eq(refused, [4] as Array[int], "told once, not on every press")
	lobby._process(DT)
	check_eq(lobby._sub_status.text, Lobby.FULL_NOTICE, "the lobby says so")
	check_eq(PlayerManager.count(), 4, "still four")


func test_a_pad_held_while_the_party_is_full_does_not_join_when_a_slot_frees() -> void:
	_make_lobby()
	for d in 4:
		_join_pad(d)
	_pad(4, "fifth")
	PadSource.fake_press(4, JOY_BUTTON_A, true)
	_frame()
	PlayerManager.leave(3)
	_frame()
	check_eq(PlayerManager.count(), 3, "the held A is not a fresh press")


func test_midrun_take_over_pauses_then_resumes() -> void:
	_make_main()
	_join_pad(0)
	var b := _join_pad(1, &"mage")
	main.start_run()
	check(PlayerManager.takeover_enabled, "a run is on: take-over is armed")
	PadSource.fake_disconnect(1)
	_frame()
	check(main.is_paused() and tree.paused, "the missing pad pauses the wave")
	check(main.hud.is_notice_visible() and "P2" in main.hud.notice_label.text, "with a notice: %s" % main.hud.notice_label.text)
	var menu := main.pause_menu
	_menu_frame()
	check("press A on any free controller to take over" in menu._missing_label.text, "the menu names the way out: %s" % menu._missing_label.text)
	_pad(3, "newcomer")
	_menu_frame()
	PadSource.fake_press(3, JOY_BUTTON_A, true)
	_menu_frame()
	PadSource.fake_press(3, JOY_BUTTON_A, false)
	check_eq((b.input as JoypadInput).device, 3, "the new pad plays P2")
	check(menu.visible, "the A that took over did not also press a button of the menu")
	check(PlayerManager.disconnected_slots().is_empty(), "nobody is missing")
	check(not main.hud.is_notice_visible(), "notice gone")
	check(tree.paused, "the game waits for START")
	_menu_frame()
	PadSource.fake_press(3, JOY_BUTTON_START, true)
	_menu_frame()
	check(not menu.visible, "START on the new pad resumes")
	main.resume_game()
	check(not tree.paused, "running again")
	check_eq(main.players.size(), 2, "both heroes are still in the run")


func test_a_free_pad_during_a_run_without_a_missing_player_gets_the_next_lobby_notice() -> void:
	_make_main()
	_join_pad(0)
	main.start_run()
	_pad(2, "late")
	_frame()
	_tap_pad(2)
	check_eq(PlayerManager.count(), 1, "nobody joins mid-run")
	check(main.hud.is_notice_visible() and main.hud.notice_label.text == Main.JOIN_LATER_NOTICE, "'Joins at the next lobby'")


func test_take_over_needs_the_run_or_the_lobby() -> void:
	_join_pad(0)
	_join_pad(1)
	PadSource.fake_disconnect(1)
	_frame()
	_pad(4, "newcomer")
	_frame()
	_tap_pad(4)
	check_eq(PlayerManager.disconnected_slots().size(), 1, "joining and take-over are off in the menus")


# --- Grace -----------------------------------------------------------------------------

func test_the_grace_is_five_seconds_by_default() -> void:
	check_eq(PlayerManager.AUTO_DECIDE_GRACE, 5.0, "~5 s")
	PlayerManager.auto_decide_grace = PlayerManager.AUTO_DECIDE_GRACE


func test_a_blip_inside_the_grace_changes_nothing_for_the_screens() -> void:
	PlayerManager.auto_decide_grace = 5.0
	_join_pad(0)
	var b := _join_pad(1)
	PadSource.fake_disconnect(1)
	_frame(3.0)
	check(PlayerManager.is_missing(b), "gone")
	check(not PlayerManager.is_absent(b), "but not for good yet")
	check(not Intermission.is_auto_ready(b), "the market waits for it")
	check(not LevelUpScreen.is_automatic(b), "the level-up waits")
	check(not ShrineScreen.is_automatic(b), "the shrine vote waits")
	check(not PortalScreen.is_abstaining(b), "the portal vote waits")
	_pad(1, "g1")
	_frame(1.0)
	check(not PlayerManager.is_missing(b) and not Intermission.is_auto_ready(b), "back inside the grace: nothing was decided")
	check_near(b.missing_time, 0.0, 0.001, "and the clock is zero again")


func test_after_the_grace_the_screens_decide_for_the_missing_player() -> void:
	PlayerManager.auto_decide_grace = 5.0
	_join_pad(0)
	var b := _join_pad(1)
	PadSource.fake_disconnect(1)
	_frame(5.5)
	check(PlayerManager.is_absent(b), "absent for good")
	check(Intermission.is_auto_ready(b), "market: auto-ready")
	check(LevelUpScreen.is_automatic(b), "level-up: automatic")
	check(ShrineScreen.is_automatic(b), "shrine: by the data")
	check(PortalScreen.is_abstaining(b), "portal: abstains")


func test_the_grace_is_overridable_and_bots_are_never_absent() -> void:
	PlayerManager.auto_decide_grace = 0.25
	_join_pad(0)
	var b := _join_pad(1)
	var bot := PlayerManager.add_bot(&"mage", 1)
	PadSource.fake_disconnect(1)
	_frame(0.3)
	check(PlayerManager.is_absent(b), "a shortened grace is over")
	check(not PlayerManager.is_absent(bot), "a bot is handled by the screens' own bot checks")
	check(Intermission.is_auto_ready(bot), "and is auto-ready as ever")


func test_a_market_ghost_inside_the_grace_shows_reconnecting() -> void:
	PlayerManager.auto_decide_grace = 5.0
	_join_pad(0)
	var b := _join_pad(1)
	PadSource.fake_disconnect(1)
	_frame(2.0)
	check(PlayerManager.is_missing(b) and not PlayerManager.is_absent(b), "inside the grace")
	# (the chip text is built by Intermission._build_chip; the state it reads is what is asserted above)
	_frame(4.0)
	check(PlayerManager.is_absent(b), "past it")


# --- Host rules -------------------------------------------------------------------------

func test_without_a_backend_every_device_is_the_hosts() -> void:
	check(not RemotePlay.is_remote_device(1), "Null backend: nobody is remote")
	check(HostRules.may_device(HostRules.Action.QUIT_GAME, 3), "any pad may quit")
	check(HostRules.may(HostRules.Action.QUIT_TO_MENU, _join_pad(0)), "any slot may quit to menu")


func test_a_remote_device_cannot_quit_but_a_local_one_can() -> void:
	_fake_backend(2)
	check(not HostRules.may_device(HostRules.Action.QUIT_GAME, 1), "guest pad 1")
	check(HostRules.may_device(HostRules.Action.QUIT_GAME, 0), "host pad 0")
	check(HostRules.may_device(HostRules.Action.QUIT_GAME, -1), "keyboard / mouse")
	check(HostRules.may_any_device(HostRules.Action.QUIT_GAME, [1, 0] as Array[int]), "one local among them is enough")
	check(not HostRules.may_any_device(HostRules.Action.QUIT_GAME, [1, 2] as Array[int]), "only guests")
	check(HostRules.may_any_device(HostRules.Action.QUIT_GAME, [] as Array[int]), "no pad (keyboard)")


func test_a_stray_pad_cannot_do_destructive_things_while_a_party_exists() -> void:
	_join_pad(0)
	_pad(9, "spare")
	check(HostRules.may_device(HostRules.Action.QUIT_TO_MENU, 0, true), "a joined pad may")
	check(not HostRules.may_device(HostRules.Action.QUIT_TO_MENU, 9, true), "a pad nobody plays may not")
	check(HostRules.may_device(HostRules.Action.QUIT_GAME, 9, false), "in the main menu nobody has joined: no stray")


func test_the_main_menu_quit_is_refused_for_a_guest_pad() -> void:
	_fake_backend(2)
	var menu := MainMenu.create()
	UiFakes.add_to_root(tree, menu)
	_screens.append(menu)
	var quits := [0]
	menu.quit_pressed.connect(func() -> void: quits[0] += 1)
	menu.quit_button.grab_focus()
	menu.activate_focused([1] as Array[int])
	check_eq(quits[0], 0, "guest pad 1: refused")
	check(menu._refusal_label.visible, "and says so")
	menu.activate_focused([0] as Array[int])
	check_eq(quits[0], 1, "host pad 0 quits")
	menu.activate_focused()
	check_eq(quits[0], 2, "the keyboard / mouse too")


func test_the_pause_menu_refuses_quit_and_drop_for_a_guest() -> void:
	_fake_backend(2)
	var host := _join_pad(0)
	var guest := _join_pad(1)
	var menu := PauseMenu.create()
	UiFakes.add_to_root(tree, menu)
	_screens.append(menu)
	var quits := [0]
	menu.quit_to_menu_requested.connect(func() -> void: quits[0] += 1)
	menu.open(guest)
	menu.selected = PauseMenu.Item.QUIT
	menu.press_selected(HostRules.may(HostRules.Action.QUIT_TO_MENU, guest))
	check(not menu.quit_armed and quits[0] == 0, "a guest's press does not even arm Quit")
	check(menu._refusal_label.visible, "'Only the host can do that'")
	menu.open(host)
	menu.selected = PauseMenu.Item.QUIT
	menu.press_selected(HostRules.may(HostRules.Action.QUIT_TO_MENU, host))
	check(menu.quit_armed, "the host's press asks 'Are you sure?'")
	menu.press_selected()
	check_eq(quits[0], 1, "and the second one quits")


func test_the_slotless_pause_menu_only_lets_joined_local_pads_destroy() -> void:
	_fake_backend(1)
	var host := _join_pad(0)
	var guest := _join_pad(1)
	_pad(8, "spare")
	var menu := PauseMenu.create()
	UiFakes.add_to_root(tree, menu)
	_screens.append(menu)
	var quits := [0]
	menu.quit_to_menu_requested.connect(func() -> void: quits[0] += 1)
	# Nobody drives it (the pauser is gone): the fallback reads every pad.
	menu.open(null)
	menu.selected = PauseMenu.Item.QUIT
	var steps := func(device: int) -> void:
		menu._skip_frames = 0
		PadSource.fake_press(device, JOY_BUTTON_A, true)
		menu._process(DT)
		PadSource.fake_press(device, JOY_BUTTON_A, false)
		menu._process(DT)
	steps.call(1)  # the guest's pad
	steps.call(8)  # a stray
	check(not menu.quit_armed, "neither a guest nor a stray pad can arm Quit")
	check(menu._refusal_label.visible, "the menu says why")
	steps.call(0)  # the host's joined pad
	check(menu.quit_armed, "the host's pad can")
	check(host != null and guest != null, "")


func test_continue_without_asks_for_a_second_press() -> void:
	_join_pad(0)
	var b := _join_pad(1)
	PadSource.fake_disconnect(1)
	var menu := PauseMenu.create()
	UiFakes.add_to_root(tree, menu)
	_screens.append(menu)
	var dropped: Array[PlayerSlot] = []
	menu.drop_player_requested.connect(func(s: PlayerSlot) -> void: dropped.append(s))
	menu.open(null)
	menu.selected = PauseMenu.DROP_BASE + 1
	menu.press_selected()
	check(dropped.is_empty() and menu.drop_armed == PauseMenu.DROP_BASE + 1, "the first press only asks")
	check_eq(menu.button_for(PauseMenu.DROP_BASE + 1).text, PauseMenu.DROP_CONFIRM_TEXT, "'Are you sure?'")
	menu.move_selection(1)
	check_eq(menu.drop_armed, -1, "moving the highlight cancels")
	menu.selected = PauseMenu.DROP_BASE + 1
	menu.press_selected()
	menu.press_selected()
	check(dropped.size() == 1 and dropped[0] == b, "the second press drops P2")


func test_a_guest_cannot_drop_a_player_but_the_host_can() -> void:
	_fake_backend(2)
	var host := _join_pad(0)
	var guest := _join_pad(2)
	_join_pad(1)
	PadSource.fake_disconnect(1)
	var menu := PauseMenu.create()
	UiFakes.add_to_root(tree, menu)
	_screens.append(menu)
	var dropped: Array[PlayerSlot] = []
	menu.drop_player_requested.connect(func(s: PlayerSlot) -> void: dropped.append(s))
	menu.open(guest)
	menu.selected = PauseMenu.DROP_BASE + 2
	menu.press_selected(HostRules.may(HostRules.Action.DROP_PLAYER, guest))
	menu.press_selected(HostRules.may(HostRules.Action.DROP_PLAYER, guest))
	check(dropped.is_empty() and menu.drop_armed == -1, "a guest cannot drop a player (not even arm it)")
	menu.open(host)
	menu.selected = PauseMenu.DROP_BASE + 2
	menu.press_selected(HostRules.may(HostRules.Action.DROP_PLAYER, host))
	menu.press_selected(HostRules.may(HostRules.Action.DROP_PLAYER, host))
	check_eq(dropped.size(), 1, "the host can")


func test_video_settings_are_the_hosts() -> void:
	_fake_backend(2)
	var host := _join_pad(0)
	var guest := _join_pad(1)
	var page := SettingsPage.create(0.5)
	UiFakes.add_to_root(tree, page)
	_screens.append(page)
	var mode_before: Variant = Settings.get_value(GameSettings.WINDOW_MODE)
	var shake_before: Variant = Settings.get_value(GameSettings.SCREEN_SHAKE)
	page.open(guest)
	page.select(page.rows.find(page.row_for(GameSettings.WINDOW_MODE)))
	page.change_selected(1)
	check_eq(Settings.get_value(GameSettings.WINDOW_MODE), mode_before, "a guest cannot change the window mode")
	page.activate_selected()
	check_eq(Settings.get_value(GameSettings.WINDOW_MODE), mode_before, "nor flip it with A")
	check_eq(page.title_label.text, HostRules.REFUSED_TEXT, "the title line says why")
	page.select(page.rows.find(page.row_for(GameSettings.SCREEN_SHAKE)))
	page.change_selected(1)
	check(Settings.get_value(GameSettings.SCREEN_SHAKE) != shake_before, "gameplay rows are anyone's")
	Settings.set_value(GameSettings.SCREEN_SHAKE, shake_before)
	# The host's page, guests connected, the mouse: allowed.
	page.open(host)
	page.select(page.rows.find(page.row_for(GameSettings.VSYNC)))
	var vsync_before: Variant = Settings.get_value(GameSettings.VSYNC)
	page.change_selected(1)
	check(Settings.get_value(GameSettings.VSYNC) != vsync_before, "the host's own pad may change video options")
	Settings.set_value(GameSettings.VSYNC, vsync_before)
	# A page nobody drives while guests are connected: pads and keys are locked, the mouse is not.
	page.open(null)
	page.select(page.rows.find(page.row_for(GameSettings.VSYNC)))
	page.change_selected(1)
	check_eq(Settings.get_value(GameSettings.VSYNC), vsync_before, "an 'anyone' page locks the Video rows while guests are connected")
	page.change_selected(1, true)
	check(Settings.get_value(GameSettings.VSYNC) != vsync_before, "a mouse click is the host's")
	Settings.set_value(GameSettings.VSYNC, vsync_before)
	RemotePlay.set_backend(null)
	page.open(null)
	page.select(page.rows.find(page.row_for(GameSettings.VSYNC)))
	page.change_selected(1)
	check(Settings.get_value(GameSettings.VSYNC) != vsync_before, "without guests an 'anyone' page behaves as ever")
	Settings.set_value(GameSettings.VSYNC, vsync_before)


# --- RemotePlay autoload and backends ---------------------------------------------------------

func test_the_default_backend_is_null_without_the_steam_file_or_in_automated_runs() -> void:
	var b := RemotePlay.create_default_backend(0, false, "res://core/platform/no_such_backend.gd")
	check(b is NullRemotePlayBackend, "no Steam file: Null")
	check(RemotePlay.create_default_backend(0, true) is NullRemotePlayBackend, "automated runs never get the Steam backend")
	check(not b.is_available() and not b.can_invite() and b.session_ids().is_empty(), "inert")
	check_eq(b.session_of_device(3), 0, "everything is local")
	check(RemotePlay.backend is NullRemotePlayBackend, "this test run has the Null backend")
	check(not RemotePlay.is_remote_device(0) and not RemotePlay.has_guests(), "and nobody is remote")


func test_the_steam_backend_file_is_loaded_through_try_create() -> void:
	var path := "user://rpt_core_test_backend.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("extends RemotePlayBackend\n\nstatic func try_create() -> RemotePlayBackend:\n\treturn new()\n\nfunc is_available() -> bool:\n\treturn true\n")
	f.close()
	var made := RemotePlay.create_default_backend(0, false, path)
	check(made != null and made.is_available(), "the file's try_create() is used in a real session")
	check(RemotePlay.create_default_backend(0, true, path) is NullRemotePlayBackend, "but never in an automated run")
	var path2 := "user://rpt_core_test_backend_none.gd"
	f = FileAccess.open(path2, FileAccess.WRITE)
	f.store_string("extends RefCounted\n\nstatic func try_create() -> Object:\n\treturn null\n")
	f.close()
	check(RemotePlay.create_default_backend(0, false, path2) is NullRemotePlayBackend, "try_create() returning nothing: Null")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path2))


func test_fake_rpt_gives_the_fake_backend_even_in_automated_runs() -> void:
	var b := RemotePlay.create_default_backend(2, true)
	check(b is FakeRemotePlayBackend, "--fake-rpt: Fake")
	check_eq(b.session_ids().size(), 2, "two guests")
	check_eq(b.guest_name(b.session_of_device(1)), "Mira", "named")
	check_eq(b.guest_name(b.session_of_device(2)), "Tobi", "named")
	check(b.is_remote_device(1) and b.is_remote_device(2) and not b.is_remote_device(0) and not b.is_remote_device(3), "pads 1..2 are guests")
	check_eq(b.session_of_bot(0), 0, "bot 0 is the host")
	check_eq(b.session_of_bot(2), b.session_of_device(2), "bots share the identities")


func test_remote_play_forwards_the_backend_signals_and_names_guests() -> void:
	var fake := _fake_backend(0)
	var seen: Array = []
	RemotePlay.guest_connected.connect(func(sid: int, who: String) -> void: seen.append(["in", sid, who]))
	RemotePlay.guest_disconnected.connect(func(sid: int) -> void: seen.append(["out", sid]))
	RemotePlay.overlay_toggled.connect(func(on: bool) -> void: seen.append(["overlay", on]))
	fake.connect_guest(77, "Lena")
	fake.set_overlay(true)
	fake.disconnect_guest(77)
	check_eq(seen, [["in", 77, "Lena"], ["overlay", true], ["out", 77]], "signals forwarded in order")
	fake.connect_guest(78, "")
	check_eq(RemotePlay.guest_name(78), "Guest 1", "an unnamed guest is 'Guest N'")
	check_eq(RemotePlay.guest_name(0), "", "the host has no guest name")
	check(RemotePlay.has_guests(), "a guest is connected")


func test_set_backend_stops_forwarding_the_old_one() -> void:
	var old := _fake_backend(0)
	RemotePlay.set_backend(null)
	var seen := [0]
	RemotePlay.guest_connected.connect(func(_sid: int, _who: String) -> void: seen[0] += 1)
	old.connect_guest(5, "x")
	check_eq(seen[0], 0, "the replaced backend is silent")
	check(RemotePlay.backend is NullRemotePlayBackend, "back to Null")


func test_invite_only_works_when_the_backend_can() -> void:
	var fake := _fake_backend(0)
	RemotePlay.show_invite()
	check_eq(fake.invites_shown, 1, "forwarded")
	fake.invite_available = false
	check(not RemotePlay.can_invite(), "cannot")
	RemotePlay.show_invite()
	check_eq(fake.invites_shown, 1, "and not called then")


# --- UI through the interface -------------------------------------------------------------

func test_the_lobby_card_names_the_guest() -> void:
	_fake_backend(2)
	_make_lobby()
	_join_pad(0)
	_join_pad(1)
	lobby._process(DT)
	check_eq(lobby.cards[0]._device_label.text, "Pad g0", "the host's card shows the controller")
	check_eq(lobby.cards[1]._device_label.text, "Remote · Mira", "the guest's card: 'Remote · <name>'")


func test_the_invite_prompt_is_shown_only_when_the_backend_can_invite() -> void:
	var fake := _fake_backend(1)
	_make_lobby()
	var a := _join_pad(0)
	var guest_pad := _join_pad(1)
	RemotePlay.set_backend(null)
	lobby._process(DT)
	check_eq(lobby._footer_key, "", "Null backend: no prompt")
	RemotePlay.set_backend(fake)
	lobby._process(DT)
	check(lobby._footer_key.ends_with("+invite"), "Fake backend that can invite: the prompt appears")
	PadSource.fake_press(0, JOY_BUTTON_LEFT_STICK, true)
	lobby._process(DT)
	PlayerManager._process(DT)
	lobby._process(DT)
	check_eq(fake.invites_shown, 1, "L3 on the host's pad opens the invite")
	PadSource.fake_press(0, JOY_BUTTON_LEFT_STICK, false)
	PlayerManager._process(DT)
	PadSource.fake_press(1, JOY_BUTTON_LEFT_STICK, true)
	PlayerManager._process(DT)
	lobby._process(DT)
	check_eq(fake.invites_shown, 1, "a guest's L3 does nothing: invites are the host's")
	check(a != null and guest_pad != null, "")
	fake.invite_available = false
	lobby._process(DT)
	check(not lobby._footer_key.ends_with("+invite"), "the prompt goes when invites do")


func test_notices_name_the_guest() -> void:
	_fake_backend(2)
	_make_main()
	_join_pad(0)
	var guest := _join_pad(1)
	main.start_run()
	check_eq(main.disconnect_notice(guest), Main.REMOTE_DISCONNECT_NOTICE % "Mira (P2)", "a guest by name")
	check_eq(main.disconnect_notice(PlayerManager.get_slot(0)), Main.DISCONNECT_NOTICE % "P1", "the host by slot")
	PadSource.fake_disconnect(1)
	_frame()
	check("Mira" in main.hud.notice_label.text, "the HUD line: %s" % main.hud.notice_label.text)


func test_the_overlay_pauses_a_wave_and_a_dungeon_only() -> void:
	var fake := _fake_backend(0)
	_make_main()
	_join_pad(0)
	main.start_run()
	check_eq(main.state, Main.State.WAVE, "wave")
	fake.set_overlay(true)
	check(main.is_paused() and tree.paused, "the platform overlay pauses the wave")
	main.resume_game()
	fake.set_overlay(false)
	check(not main.is_paused(), "closing it does not touch the menu")
	main.state = Main.State.INTERMISSION
	fake.set_overlay(true)
	check(not main.is_paused(), "no pause over an intermission")


func test_losing_the_focus_pauses_when_the_setting_is_on() -> void:
	_make_main()
	_join_pad(0)
	main.start_run()
	check(bool(Settings.get_value(GameSettings.PAUSE_ON_FOCUS_LOSS)), "default: on")
	main.focus_lost(false)
	check(not main.is_paused(), "automated runs never pause on focus loss")
	main.focus_lost(true)
	check(main.is_paused() and tree.paused, "a real session pauses")
	main.resume_game()
	Settings.set_value(GameSettings.PAUSE_ON_FOCUS_LOSS, false)
	main.focus_lost(true)
	check(not main.is_paused(), "the setting switches it off")
	Settings.set_value(GameSettings.PAUSE_ON_FOCUS_LOSS, true)


func test_the_focus_setting_is_a_gameplay_toggle_that_is_saved() -> void:
	var o := GameSettings.option(GameSettings.PAUSE_ON_FOCUS_LOSS)
	check(o != null, "exists")
	check_eq(o.label, "Pause when the window loses focus", "label")
	check_eq(o.section, "Gameplay", "section")
	check_eq(o.default, true, "default on")
	var data := GameSettings.new()
	data.path = "user://rpt_core_test_settings.cfg"
	check(data.pause_on_focus_loss(), "on by default")
	data.set_value(GameSettings.PAUSE_ON_FOCUS_LOSS, false)
	check_eq(data.save_file(), OK, "saved")
	var again := GameSettings.new()
	again.path = data.path
	again.load_file()
	check(not again.pause_on_focus_loss(), "and read back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(data.path))


# --- Flags and the project -------------------------------------------------------------------

func test_fake_rpt_flag_parsing() -> void:
	check_eq(LaunchOptions.parse(PackedStringArray([])).fake_rpt, 0, "off by default")
	check_eq(LaunchOptions.parse(PackedStringArray(["--fake-rpt"])).fake_rpt, LaunchOptions.DEFAULT_FAKE_RPT, "bare: two guests")
	check_eq(LaunchOptions.parse(PackedStringArray(["--fake-rpt=3"])).fake_rpt, 3, "=3")
	check_eq(LaunchOptions.parse(PackedStringArray(["--fake-rpt=9"])).fake_rpt, 3, "clamped to the three guest seats")
	check_eq(LaunchOptions.parse(PackedStringArray(["--fake-rpt=0"])).fake_rpt, 0, "=0 is off")
	var bad := LaunchOptions.parse(PackedStringArray(["--fake-rpt=lots"]))
	check_eq(bad.unknown.size(), 1, "a non-number is an unknown argument")
	check(not LaunchOptions.parse(PackedStringArray(["--fake-rpt=2"])).is_automated(), "the flag alone does not make a run automated")


func test_hotplug_test_flag_needs_a_smoke_run_with_two_players_and_waves() -> void:
	var ok := LaunchOptions.parse(PackedStringArray(["--smoke", "--hotplug-test", "--waves=3"]))
	check(ok.hotplug_test and ok.unknown.is_empty(), "smoke + defaults: fine")
	for view in ["lobby", "pause"]:
		var shot := LaunchOptions.parse(PackedStringArray(["--view=%s" % view, "--hotplug-test"]))
		check(shot.hotplug_test and shot.unknown.is_empty(), "--view=%s shows the state" % view)
	for args in [["--hotplug-test"], ["--smoke", "--hotplug-test", "--players=1"], ["--smoke", "--hotplug-test", "--waves=1"]]:
		var o := LaunchOptions.parse(PackedStringArray(args))
		check(not o.hotplug_test and o.unknown.size() == 1, "refused: %s" % str(args))


func test_the_unfocused_joypad_setting_is_pinned_to_false() -> void:
	var key := "input_devices/joypads/ignore_joypad_on_unfocused_application"
	check(ProjectSettings.has_setting(key), "the setting exists")
	check_eq(ProjectSettings.get_setting(key), false, "and is false")
	var text := FileAccess.get_file_as_string("res://project.godot")
	check("joypads/ignore_joypad_on_unfocused_application=false" in text, "project.godot pins it explicitly")
	check_eq(Input.ignore_joypad_on_unfocused_application, false, "the runtime property agrees")


func test_remote_play_is_an_autoload_and_the_steam_file_is_optional() -> void:
	var text := FileAccess.get_file_as_string("res://project.godot")
	check("RemotePlay=\"*res://autoload/remote_play.gd\"" in text, "autoload registered")
	check(not "GodotSteam" in text and not "godotsteam" in text, "nothing needs the plug-in to start")
	check(RemotePlay.STEAM_BACKEND_PATH.ends_with("steam_remote_play_backend.gd"), "the path RPT-STEAM fills")


func test_no_script_asks_the_engine_for_pads_outside_the_seam() -> void:
	var banned: Array[String] = ["Input.get_connected_joypads(", "Input.is_joy_button_pressed(", "Input.get_joy_axis(",
			"Input.get_joy_name(", "Input.get_joy_guid(", "Input.get_joy_info("]
	var allowed: Array[String] = ["res://core/input/pad_source.gd", "res://core/input/pad_identity.gd"]
	var stack: Array[String] = ["res://scenes", "res://core", "res://autoload"]
	var scanned := 0
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(dir_path):
			stack.append(dir_path.path_join(sub))
		for file in DirAccess.get_files_at(dir_path):
			if not file.ends_with(".gd"):
				continue
			var path := dir_path.path_join(file)
			if path in allowed:
				continue
			scanned += 1
			var text := FileAccess.get_file_as_string(path)
			for needle in banned:
				check(not (needle in text), "%s calls %s: go through PadSource" % [path, needle])
	check(scanned > 100, "the scan saw the scripts (%d)" % scanned)


func test_the_invite_prompt_waits_for_the_first_joined_player() -> void:
	_fake_backend(1)
	_make_lobby()
	lobby._process(DT)
	check_eq(lobby._footer_key, "back", "nobody joined: only 'Back' (L3 is read from a joined player's pad)")
	_join_pad(0)
	lobby._process(DT)
	check(lobby._footer_key.ends_with("+invite"), "the first player joined: 'Invite friends' appears")
