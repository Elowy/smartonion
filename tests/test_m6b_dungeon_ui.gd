extends TestCase
## M6b DUNGEON, the portal and the flow (GDD 16.1): the PortalScreen's vote (all accept / one decline /
## 20 s timeout, bots' rule, unplugged abstain, leavers), the Intermission's PORTAL phase handing the party
## to Main and taking it back (loot roll of the Epics, then the market with its full countdown), the HUD's
## dungeon line, and Main's side: the portal roll after waves 6 / 9 / 12 / 15 and --dungeon, entering,
## the State.DUNGEON rules (pause), the reward and failure payouts, the teardown. The arena layout and
## the rooms are in test_m6b_dungeon_core.gd.

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var portal: PortalScreen
var screen: Intermission
var main: Main
var hud: Hud
var decisions: Array[bool] = []
var accepted := [0]
var nodes: Array[Node] = []


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, 4242)
	tree.paused = false
	decisions.clear()
	accepted[0] = 0


func after_each() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()
	UiFakes.free_node(portal)
	portal = null
	UiFakes.free_node(screen)
	screen = null
	UiFakes.free_node(hud)
	hud = null
	if world != null and is_instance_valid(world):
		world.free()
	world = null
	tree.paused = false
	UiFakes.reset_players()
	RunState.start_run(1, 1)
	Enemy.invalidate_player_cache()


# --- Helpers ----------------------------------------------------------------------------------

func _world() -> void:
	if world == null:
		world = MarketFakes.make_world(tree)


func _portal() -> PortalScreen:
	portal = PortalScreen.create()
	tree.root.add_child(portal)
	portal.decided.connect(func(enter: bool) -> void: decisions.append(enter))
	return portal


func _bot(class_id: StringName = &"warrior") -> PlayerSlot:
	_world()
	return MarketFakes.bot_with_hero(world, "bot:%d" % PlayerManager.count(), class_id)


func _human(class_id: StringName = &"mage") -> UiFakes.HumanInput:
	_world()
	return MarketFakes.human_with_hero(world, "pad:%d" % PlayerManager.count(), class_id)


func _open(p_wave: int = 6, forced: bool = false, downs: int = 0) -> void:
	portal.open(PlayerManager.get_slots(), p_wave, forced, downs)


## A frame of the vote: polls every input, then runs the screen.
func _frame(delta: float = DT) -> void:
	for s in PlayerManager.get_slots():
		s.input.poll(delta)
	portal.update(delta)


func _press(input: UiFakes.HumanInput, button: PlayerInput.Pad) -> void:
	input.press(button)
	_frame()
	input.release(button)
	_frame(0.0)


## Lets the lockout after opening run out.
func _wait_for_input() -> void:
	_frame(PortalScreen.INPUT_LOCKOUT + 0.1)


# --- PortalScreen: the rules -------------------------------------------------------------------------

func test_the_bots_rule() -> void:
	check(PortalScreen.bot_accepts(6, 0, false) and PortalScreen.bot_accepts(6, 3, false), "wave 6: always")
	check(PortalScreen.bot_accepts(9, 0, false) and PortalScreen.bot_accepts(9, 4, false), "wave 9: always")
	check(PortalScreen.bot_accepts(12, 0, false), "wave 12 with nobody downed: in")
	check(not PortalScreen.bot_accepts(12, 1, false), "wave 12 with a down: out")
	check(PortalScreen.bot_accepts(15, 0, false), "wave 15 with nobody downed: in")
	check(not PortalScreen.bot_accepts(15, 2, false), "wave 15 with downs: out")
	check(PortalScreen.bot_accepts(12, 5, true), "a forced portal is always taken")
	check(PortalScreen.bot_accepts(1, 0, true), "even after wave 1")


func test_tally() -> void:
	var V := PortalScreen.Vote
	check_eq(PortalScreen.tally([] as Array[int]), false, "no voters: a skip")
	check_eq(PortalScreen.tally([V.ACCEPT, V.ACCEPT] as Array[int]), true, "all accept")
	check(PortalScreen.tally([V.ACCEPT, V.PENDING] as Array[int]) == null, "still open")
	check_eq(PortalScreen.tally([V.PENDING, V.DECLINE] as Array[int]), false, "one decline ends it")
	check_eq(PortalScreen.tally([V.ACCEPT, V.DECLINE, V.PENDING] as Array[int]), false, "even with others open")
	check_eq(PortalScreen.VOTE_TIME, 20.0, "20 s")


func test_bots_accept_after_wave_6_at_once() -> void:
	_bot()
	_bot(&"mage")
	_portal()
	_open(6)
	check(portal.is_active() and portal.visible, "open")
	_frame()
	check_eq(decisions, [true] as Array[bool], "both bots accepted: the party enters")
	check(not portal.is_active(), "the vote is over")


func test_bots_decline_after_wave_12_when_somebody_was_downed() -> void:
	_bot()
	_portal()
	_open(12, false, 1)
	_frame()
	check_eq(decisions, [false] as Array[bool], "no entry")
	_bot()


func test_bots_accept_a_forced_portal_whatever_happened() -> void:
	_bot()
	_portal()
	_open(12, true, 3)
	_frame()
	check_eq(decisions, [true] as Array[bool], "forced")


func test_a_human_votes_with_a_and_b_after_the_lockout() -> void:
	var pad := _human()
	_portal()
	_open(6)
	_frame()
	_press(pad, PlayerInput.Pad.A)
	check(decisions.is_empty(), "an A inside the lockout does not vote")
	_wait_for_input()
	_press(pad, PlayerInput.Pad.A)
	check_eq(decisions, [true] as Array[bool], "A accepts")


func test_a_held_button_is_swallowed_at_the_opening() -> void:
	var pad := _human()
	pad.press(PlayerInput.Pad.A)  # the loot roll's Need press, still down
	pad.poll(DT)
	_portal()
	_open(6)
	_wait_for_input()
	check(decisions.is_empty(), "holding A does not vote")
	pad.release(PlayerInput.Pad.A)
	_frame()
	_press(pad, PlayerInput.Pad.A)
	check_eq(decisions, [true] as Array[bool], "a fresh press does")


func test_one_decline_skips_at_once_even_with_pending_votes() -> void:
	var a := _human(&"warrior")
	var b := _human(&"mage")
	_portal()
	_open(6)
	_wait_for_input()
	_press(a, PlayerInput.Pad.A)
	check(decisions.is_empty(), "one accept is not enough")
	check_eq(portal.vote_of(PlayerManager.get_slots()[0].index), PortalScreen.Vote.ACCEPT, "P1 accepted")
	_press(b, PlayerInput.Pad.B)
	check_eq(decisions, [false] as Array[bool], "a decline skips")


func test_everybody_has_to_accept() -> void:
	var a := _human(&"warrior")
	var b := _human(&"mage")
	_portal()
	_open(6)
	_wait_for_input()
	_press(a, PlayerInput.Pad.A)
	_press(b, PlayerInput.Pad.A)
	check_eq(decisions, [true] as Array[bool], "both accepted")


func test_a_vote_can_be_changed_before_the_decision() -> void:
	var a := _human(&"warrior")
	_human(&"mage")
	_portal()
	_open(6)
	_wait_for_input()
	_press(a, PlayerInput.Pad.A)
	_press(a, PlayerInput.Pad.A)
	check(decisions.is_empty(), "still waiting for the other player")
	check_eq(portal.vote_of(PlayerManager.get_slots()[0].index), PortalScreen.Vote.ACCEPT, "accept stays")


func test_the_timeout_skips_after_20_seconds() -> void:
	var a := _human()
	_portal()
	_open(6)
	_wait_for_input()
	_press(a, PlayerInput.Pad.A)  # (alone: it would decide) -> use two humans instead
	check_eq(decisions, [true] as Array[bool], "a lone accept decides")
	decisions.clear()
	UiFakes.reset_players()
	var x := _human(&"warrior")
	var y := _human(&"mage")
	_open(6)
	_wait_for_input()
	_press(x, PlayerInput.Pad.A)
	check_near(portal.time_left, 20.0 - PortalScreen.INPUT_LOCKOUT - 0.1 - 2.0 * DT, 0.2, "the clock runs")
	_frame(19.0)
	check(decisions.is_empty(), "still waiting at 19.5 s")
	_frame(1.0)
	check_eq(decisions, [false] as Array[bool], "the timeout declines")
	y.release(PlayerInput.Pad.A)


func test_a_player_with_an_unplugged_controller_abstains() -> void:
	_bot()
	var gone := _human()
	gone.connected = false
	_portal()
	_open(6)
	check_eq(portal.order.size(), 1, "only the bot votes")
	_frame()
	check_eq(decisions, [true] as Array[bool], "the unplugged player does not block")


func test_a_pad_unplugged_during_the_vote_stops_blocking() -> void:
	_bot()
	var pad := _human()
	_portal()
	_open(6)
	_frame()
	check(decisions.is_empty(), "the human has not voted")
	pad.connected = false
	_frame()
	check_eq(decisions, [true] as Array[bool], "the vote goes on without them")


func test_a_leaver_takes_the_vote_along_and_the_rest_decide() -> void:
	var a := _human(&"warrior")
	var b := _human(&"mage")
	_portal()
	_open(6)
	_wait_for_input()
	_press(a, PlayerInput.Pad.A)
	check(decisions.is_empty(), "waiting for P2")
	portal.remove_slot(PlayerManager.get_slots()[1].index)
	check_eq(decisions, [true] as Array[bool], "P2 left: P1's accept is everybody's")
	b.release(PlayerInput.Pad.A)


func test_nobody_left_to_vote_is_a_skip() -> void:
	var a := _human()
	_portal()
	_open(6)
	portal.remove_slot(PlayerManager.get_slots()[0].index)
	check_eq(decisions, [false] as Array[bool], "a skip")
	a.release(PlayerInput.Pad.A)


func test_a_slot_without_a_hero_does_not_vote() -> void:
	_bot()
	PlayerManager.join(UiFakes.HumanInput.new("pad:nohero"), Db.get_class_data(&"rogue"))
	_portal()
	_open(6)
	check_eq(portal.order.size(), 1, "one voter")
	_frame()
	check_eq(decisions, [true] as Array[bool], "the heroless slot does not block")


func test_the_demo_bots_think_before_they_vote() -> void:
	_bot()
	_portal()
	portal.bot_think_time = 1.0
	_open(6)
	_frame()
	check(decisions.is_empty(), "thinking")
	_frame(0.9)
	check(decisions.is_empty(), "still thinking just before its second")
	_frame(0.2)
	check_eq(decisions, [true] as Array[bool], "then it accepts")


func test_the_decision_is_made_once() -> void:
	_bot()
	_portal()
	_open(6)
	_frame()
	_frame()
	_frame(30.0)
	check_eq(decisions.size(), 1, "decided() fired once")


func test_one_chip_per_voter_shows_the_vote() -> void:
	var a := _human(&"warrior")
	_human(&"mage")
	_portal()
	_open(6)
	check_eq(portal._chips.size(), 2, "two chips")
	_wait_for_input()
	var key_before: String = portal._chip_keys[PlayerManager.get_slots()[0].index]
	_press(a, PlayerInput.Pad.A)
	_frame()
	check(portal._chip_keys[PlayerManager.get_slots()[0].index] != key_before, "the chip changed with the vote")
	check_eq(portal.title_label.text, "A dungeon portal has opened!", "the title")


# --- Intermission: the PORTAL phase ---------------------------------------------------------------------

func _make_screen() -> void:
	_world()
	RunState.shop = MarketFakes.FakeShop.new()
	screen = Intermission.create()
	tree.root.add_child(screen)
	screen.portal_accepted.connect(func() -> void: accepted[0] += 1)


func _drive(frames: int = 3) -> void:
	for i in frames:
		for s in PlayerManager.get_slots():
			s.input.poll(DT)
		screen._process(DT)


func test_bots_open_the_dungeon_and_the_screen_steps_aside() -> void:
	_make_screen()
	_bot()
	_bot(&"mage")
	RunState.portal_pending = true
	screen.open(6, 0)
	check_eq(screen.phase, Intermission.Phase.PORTAL, "the portal vote")
	check(screen.portal_screen.visible, "on screen")
	_drive()
	check_eq(accepted[0], 1, "portal_accepted fired once")
	check(screen.is_in_dungeon() and not screen.visible, "hidden while the party is inside")
	check_eq(screen.phase, Intermission.Phase.PORTAL, "still the portal phase")
	check(not screen.portal_screen.visible, "the vote is gone")


func test_a_declined_portal_goes_to_the_market_without_a_dungeon() -> void:
	_make_screen()
	var pad := _human()
	RunState.portal_pending = true
	screen.open(6, 0)
	_drive(1)
	screen.portal_screen.cast(PlayerManager.get_slots()[0].index, PortalScreen.Vote.DECLINE)
	check_eq(accepted[0], 0, "no dungeon")
	check_eq(screen.phase, Intermission.Phase.MARKET, "the market")
	check(not RunState.portal_pending, "closed")
	check(screen.visible and not screen.is_in_dungeon(), "the screen stays")
	pad.release(PlayerInput.Pad.A)


func test_the_market_countdown_does_not_run_inside_the_dungeon() -> void:
	_make_screen()
	_bot()
	RunState.portal_pending = true
	screen.open(6, 0)
	_drive()
	check(screen.is_in_dungeon(), "inside")
	var left := screen.time_left
	for i in 50:
		screen._process(5.0)
	check_eq(screen.time_left, left, "the countdown stood still for 250 s")
	check_eq(screen.phase, Intermission.Phase.PORTAL, "and the break did not move on")
	screen.dungeon_returned(false)
	check_eq(screen.phase, Intermission.Phase.MARKET, "back: the market")
	check_eq(screen.time_left, Intermission.auto_continue_time, "with its full countdown")
	screen._process(1.0)
	check_near(screen.time_left, Intermission.auto_continue_time - 1.0, 0.01, "which starts only now")


func test_a_won_dungeons_epics_are_rolled_before_the_market() -> void:
	_make_screen()
	_bot()
	_bot(&"mage")
	RunState.portal_pending = true
	screen.open(6, 0)
	_drive()
	for i in 2:
		RunState.add_team_loot(MarketFakes.make_weapon(&"sword", Items.Rarity.EPIC, 90))
	screen.dungeon_returned(true)
	check(screen.visible and not screen.is_in_dungeon(), "the screen is back")
	check_eq(screen.phase, Intermission.Phase.LOOT, "the Need / Greed / Pass roll first")
	check(screen.loot_screen.visible, "on screen")
	screen.loot_screen.finished.emit()
	check_eq(screen.phase, Intermission.Phase.MARKET, "then straight to the market (the level-ups and shrines are behind us)")
	check(not RunState.portal_pending, "the portal is closed")


func test_a_lost_dungeon_goes_straight_to_the_market() -> void:
	_make_screen()
	_bot()
	RunState.portal_pending = true
	screen.open(6, 0)
	_drive()
	screen.dungeon_returned(false)
	check_eq(screen.phase, Intermission.Phase.MARKET, "the market follows either way")
	check(not RunState.portal_pending, "closed")


func test_dungeon_returned_outside_a_dungeon_does_nothing() -> void:
	_make_screen()
	_human()
	screen.open(5, 0)
	var phase_before := screen.phase
	screen.dungeon_returned(true)
	check_eq(screen.phase, phase_before, "ignored")


func test_a_player_leaving_the_vote_drops_their_vote() -> void:
	_make_screen()
	var a := _human(&"warrior")
	_human(&"mage")
	RunState.portal_pending = true
	screen.open(6, 0)
	check_eq(screen.portal_screen.order.size(), 2, "two voters")
	var leaver := PlayerManager.get_slots()[1]
	screen._on_player_left(leaver)
	check_eq(screen.portal_screen.order.size(), 1, "one voter left")
	a.release(PlayerInput.Pad.A)


func test_the_portal_phase_comes_after_the_level_ups_and_before_the_market() -> void:
	_make_screen()
	_bot()
	RunState.level = 4
	RunState.portal_pending = true
	screen.open(6, 1)
	check_eq(screen.phase, Intermission.Phase.LEVEL_UP, "the level-up cards first")
	screen._on_level_up_finished()
	check_eq(screen.phase, Intermission.Phase.PORTAL, "then the portal")


# --- HUD ---------------------------------------------------------------------------------------------------

func test_the_hud_shows_the_dungeon_line_and_the_room_clock() -> void:
	hud = Hud.create()
	tree.root.add_child(hud)
	RunState.set_wave(6)
	hud.set_dungeon_status("Dungeon – Room 2/4", "Survive", 17.2)
	check(hud.is_dungeon_shown(), "shown")
	check_eq(hud.wave_label.text, "Dungeon – Room 2/4", "the wave line")
	check(hud.wave_tag_label.visible and hud.wave_tag_label.text == "Survive", "the task under it")
	check(hud.timer_label.visible and hud.timer_label.text == UiTheme.format_time(17.2), "the clock in the timer's place")
	hud.set_dungeon_status("Dungeon – Room 1/4", "Kill enemies  3 / 25", -1.0)
	check(not hud.timer_label.visible, "no clock in an untimed room")
	check_eq(hud.wave_tag_label.text, "Kill enemies  3 / 25", "the kill count")
	hud.set_dungeon_status("Dungeon – Room 3/4", "Defend the brazier  (80%)", 12.0)
	check(hud.timer_label.visible, "the clock again")
	hud.clear_dungeon()
	check(not hud.is_dungeon_shown(), "cleared")
	check_eq(hud.wave_label.text, RunState.wave_progress_text(6), "the wave line is back")
	check(not hud.wave_tag_label.visible and hud.timer_label.visible, "the plaque is the wave's again")


func test_the_hud_keeps_the_timer_hidden_while_the_wardens_frame_shows() -> void:
	hud = Hud.create()
	tree.root.add_child(hud)
	var boss := Boss.create(Db.get_boss(&"dungeon_warden"), 6)
	nodes.append(boss)
	hud.bind_boss(boss)
	hud.set_dungeon_status("Dungeon – Room 4/4", "Defeat the Dungeon Warden", 5.0)
	check(hud.is_boss_frame_visible() and not hud.timer_label.visible, "the boss frame replaces the clock")
	check_eq(hud.boss_name_label.text, "Dungeon Warden", "named")
	hud.clear_boss()
	hud.clear_dungeon()
	check(not hud.is_boss_frame_visible() and hud.timer_label.visible, "all back")


# --- Main ------------------------------------------------------------------------------------------------

func _make_main() -> Main:
	var opts := LaunchOptions.new()
	opts.seed_value = 4242
	main = Main.create(opts)
	tree.root.add_child(main)
	return main


func _run_with_bots(count: int) -> void:
	_make_main()
	for i in count:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)
	main.start_run()


func _break_after(p_wave: int) -> void:
	main.wave = p_wave
	main.state = Main.State.WAVE_END
	main._after_wave_end()


## The bots' vote passes in the Intermission (the party is "inside": the screen hides itself) and Main
## enters (the signal is deferred in the real game, so a synchronous test calls it itself).
func _enter_by_vote() -> void:
	for i in 3:
		main.intermission._process(DT)
	check(main.intermission.is_in_dungeon(), "the vote passed")
	main.enter_dungeon()


func _kill_all(by: Player = null) -> void:
	for node in tree.get_nodes_in_group(&"enemies"):
		var e := node as Enemy
		if e != null and not e.is_dead():
			e.kill(by)


## Runs the dungeon to its end, killing everything that is not a hero at every step.
func _play_dungeon(kill: bool = true) -> void:
	var guard := 0
	while main.dungeon != null and guard < 3000:
		main.dungeon._physics_process(0.25)
		if kill and main.dungeon != null:
			_kill_all(main.players[0])
		guard += 1


func _down(p: Player) -> void:
	for i in 60:
		if p.downed:
			return
		p.invulnerable_left = 0.0
		p.take_damage(100000.0, CombatMath.KIND_MELEE, null)


func test_the_portal_opens_after_waves_6_9_12_and_15_only() -> void:
	_run_with_bots(1)
	for w in [6, 9, 12, 15]:
		main.wave = w
		main._roll_portal()
		check(RunState.portal_pending, "after wave %d" % w)
		check(not RunState.portal_forced, "not forced")
	for w in [1, 5, 7, 8, 10, 11, 13, 14, 16, 20]:
		main.wave = w
		main._roll_portal()
		check(not RunState.portal_pending, "not after wave %d" % w)


func test_dungeon_flag_forces_the_portal_after_the_next_wave_once() -> void:
	_run_with_bots(1)
	RunState.dungeon_forced = true
	main.wave = 2
	main._roll_portal()
	check(RunState.portal_pending and RunState.portal_forced, "forced after wave 2")
	check(not RunState.dungeon_forced, "the flag is spent")
	main.wave = 3
	main._roll_portal()
	check(not RunState.portal_pending and not RunState.portal_forced, "not again after wave 3")
	RunState.dungeon_forced = true
	main.wave = 6
	main._roll_portal()
	check(RunState.portal_pending and RunState.portal_forced and not RunState.dungeon_forced, "on a portal wave it is still spent")


func test_the_launch_flag_reaches_the_run() -> void:
	var opts := LaunchOptions.parse(["--dungeon=1"])
	opts.seed_value = 7
	main = Main.create(opts)
	tree.root.add_child(main)
	PlayerManager.add_bot(&"warrior", 1)
	main.start_run()
	check(RunState.dungeon_forced, "--dungeon=1 forces the next portal")


func test_the_wave_end_path_opens_the_portal_phase() -> void:
	_run_with_bots(2)
	_break_after(6)
	check_eq(main.state, Main.State.INTERMISSION, "the break")
	check(tree.paused, "paused")
	check_eq(main.intermission.phase, Intermission.Phase.PORTAL, "the portal vote")


func test_no_portal_after_wave_5() -> void:
	_run_with_bots(2)
	_break_after(5)
	check_eq(main.intermission.phase, Intermission.Phase.MARKET, "straight to the market")


func test_entering_the_dungeon() -> void:
	_run_with_bots(2)
	_break_after(6)
	var got := [0]
	main.intermission.portal_accepted.connect(func() -> void: got[0] += 1)
	for i in 3:
		main.intermission._process(DT)
	check_eq(got[0], 1, "the bots voted yes")
	main.enter_dungeon()  # (the deferred signal would call this on the next frame)
	check_eq(main.state, Main.State.DUNGEON, "State.DUNGEON")
	check(main.dungeon != null and main.dungeon.is_running(), "the dungeon runs")
	check_eq(main.dungeon.wave, 6, "scaled to the cleared wave")
	check(not tree.paused, "the tree runs")
	check(main.arena.in_dungeon_layout, "the arena is the small room")
	check(main.hud.visible and main.hud.is_dungeon_shown(), "the HUD shows the dungeon")
	check_eq(RunState.dungeons_entered, 1, "counted")
	check(main.dungeon.smoke_boss_timeout == main.options.smoke, "the smoke safety follows the run")
	main.enter_dungeon()
	check_eq(RunState.dungeons_entered, 1, "a second call changes nothing")


func test_the_hud_line_follows_the_rooms() -> void:
	_run_with_bots(2)
	_break_after(6)
	main.enter_dungeon()
	main.dungeon._physics_process(Dungeon.INTRO_TIME + 0.02)
	check_eq(main.hud.wave_label.text, "Dungeon – Room 1/4", "room 1")
	check_eq(main.hud.wave_tag_label.text, "Kill enemies  0 / 25", "its task")
	main.dungeon._start_room(Dungeon.Room.SURVIVE)
	check_eq(main.hud.wave_label.text, "Dungeon – Room 2/4", "room 2")
	check(main.hud.timer_label.visible, "with a clock")
	main.dungeon._start_room(Dungeon.Room.WARDEN)
	main.dungeon._physics_process(Dungeon.WARDEN_TELEGRAPH + 0.1)
	check(main.hud.is_boss_frame_visible(), "the Warden's frame")
	check_eq(main.hud.boss_name_label.text, "Dungeon Warden", "named")


func test_a_cleared_dungeon_pays_and_hands_the_break_back() -> void:
	_run_with_bots(2)
	RunState.gold = 40
	_break_after(6)
	_enter_by_vote()
	var gold := RunState.gold
	_play_dungeon()
	check(main.dungeon == null, "the dungeon is over")
	check_eq(main.state, Main.State.INTERMISSION, "the break again")
	check(tree.paused, "paused")
	check_eq(RunState.dungeons_completed, 1, "counted")
	check_eq(RunState.dungeons_failed, 0, "not a failure")
	check_eq(RunState.dungeon_rooms_cleared, 4, "four rooms")
	check(RunState.dungeon_time > 60.0, "time spent inside (%.1f)" % RunState.dungeon_time)
	check(RunState.gold >= gold + DungeonRewards.gold_for(6), "the purse got 20x the average gold")
	check_eq(main.intermission.phase, Intermission.Phase.LOOT, "the Epics are rolled for")
	check(main.intermission.loot_screen.visible, "on screen")
	check(not main.hud.visible and not main.hud.is_dungeon_shown(), "the HUD is back to the break")
	check(not main.arena.in_dungeon_layout and main.arena.spirit_healer != null, "the clearing is back")
	var smoke := main.smoke_result("completed")
	check_eq(smoke["dungeon_rooms_cleared"], 4, "SMOKE_RESULT: rooms")
	check_eq(smoke["dungeons_completed"], 1, "SMOKE_RESULT: completed")
	check(smoke["dungeon_time"] > 60.0, "SMOKE_RESULT: time")


func test_after_the_loot_roll_the_market_opens_with_the_full_countdown() -> void:
	_run_with_bots(2)
	_break_after(6)
	_enter_by_vote()
	_play_dungeon()
	main.intermission.loot_screen.finished.emit()
	check_eq(main.intermission.phase, Intermission.Phase.MARKET, "the market")
	check_eq(main.intermission.time_left, Intermission.auto_continue_time, "60 s")
	check_eq(main.state, Main.State.INTERMISSION, "Main still in the break")


func test_a_lost_dungeon_halves_the_purse_and_the_market_follows() -> void:
	_run_with_bots(2)
	RunState.gold = 100
	_break_after(6)
	_enter_by_vote()
	main.dungeon._physics_process(Dungeon.INTRO_TIME + 0.02)
	for p in main.players:
		_down(p)
	_play_dungeon(false)
	check(main.dungeon == null, "over")
	check_eq(RunState.dungeons_failed, 1, "a failure")
	check_eq(RunState.dungeons_completed, 0, "not a clear")
	check_eq(RunState.gold, 50, "the purse lost half")
	for p in main.players:
		check(not p.downed, "everybody is revived")
	check_eq(main.state, Main.State.INTERMISSION, "the break")
	check_eq(main.intermission.phase, Intermission.Phase.MARKET, "the market follows either way")
	check(RunState.team_loot.is_empty(), "no reward")
	check(not main.arena.in_dungeon_layout, "the clearing is back")


func test_the_pause_menu_works_inside_the_dungeon() -> void:
	_run_with_bots(2)
	_break_after(6)
	main.enter_dungeon()
	main.pause_game(PlayerManager.get_slots()[0])
	check(tree.paused and main.pause_menu.visible, "paused inside the dungeon")
	main.resume_game()
	check(not tree.paused, "and resumed")
	check_eq(main.state, Main.State.DUNGEON, "still inside")


func test_revives_inside_the_dungeon_are_counted() -> void:
	_run_with_bots(2)
	_break_after(6)
	main.enter_dungeon()
	main.dungeon._physics_process(Dungeon.INTRO_TIME + 0.02)
	var revives := main.revives
	_down(main.players[0])
	main.players[0].revive(0.3, [1])
	check_eq(main.revives, revives + 1, "a revive in the dungeon counts")


func test_quitting_during_the_dungeon_frees_everything() -> void:
	_run_with_bots(2)
	_break_after(6)
	main.enter_dungeon()
	main.dungeon._physics_process(Dungeon.INTRO_TIME + 1.5)
	var d := main.dungeon
	var arena := main.arena
	main.quit_to_menu()
	check(main.dungeon == null and main.arena == null, "gone")
	check(d.get_parent() == null or d.is_queued_for_deletion(), "the dungeon node is freed")
	check(arena.is_queued_for_deletion() or not is_instance_valid(arena), "so is the arena")
	check_eq(main.state, Main.State.MENU, "the menu")


func test_downs_in_the_wave_feed_the_bots_rule() -> void:
	_run_with_bots(2)
	check_eq(RunState.last_wave_downs, 0, "none yet")
	main.start_wave(3)
	_down(main.players[0])
	main.state = Main.State.WAVE
	main._on_wave_cleared(3)
	check_eq(RunState.last_wave_downs, 1, "one down in wave 3")
	main.start_wave(4)
	main.state = Main.State.WAVE
	main._on_wave_cleared(4)
	check_eq(RunState.last_wave_downs, 0, "wave 4 had none: the baseline moved")


func test_the_portal_vote_is_instant_for_smoke_bots_and_slow_in_the_demo() -> void:
	_run_with_bots(1)
	check_eq(main.intermission.portal_screen.bot_think_time, 0.0, "smoke / normal: at once")
	var opts := LaunchOptions.new()
	opts.demo = true
	opts.seed_value = 3
	main.get_parent().remove_child(main)
	main.free()
	main = Main.create(opts)
	tree.root.add_child(main)
	PlayerManager.clear()
	PlayerManager.add_bot(&"warrior", 1)
	main.start_run()
	check_eq(main.intermission.portal_screen.bot_think_time, Main.DEMO_PORTAL_THINK_TIME, "demo: the bots deliberate")


func test_state_dungeon_is_appended_to_the_enum() -> void:
	check_eq(Main.State.GAME_OVER, 6, "the old values stay")
	check_eq(Main.State.DUNGEON, 7, "DUNGEON is last")
