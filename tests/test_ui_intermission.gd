extends TestCase
## Intermission: per-player ready with START (A buys in the shop since M2), B unreadies,
## bots and unplugged devices auto-ready, continue_requested once when everybody is ready, or
## when the auto-continue countdown (GDD 12, 60 s, can be switched off) runs out. The M2 phases
## (loot roll, market routing) are covered by test_ui_market_intermission.gd.

const UiFakes := preload("res://tests/ui_fakes.gd")

var screen: Intermission
var continues := 0


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(2, 7)
	screen = Intermission.create()
	screen.continue_requested.connect(func() -> void: continues += 1)
	UiFakes.add_to_root(tree, screen)


func after_each() -> void:
	Intermission.auto_continue_time = Intermission.AUTO_CONTINUE_TIME
	UiFakes.free_node(screen)
	screen = null
	UiFakes.reset_players()


func _human(key: String) -> UiFakes.HumanInput:
	var input := UiFakes.HumanInput.new(key)
	PlayerManager.join(input, Db.get_class_data(&"rogue"))
	return input


func test_hidden_until_opened_and_fills_summary() -> void:
	check(not screen.visible, "hidden after create")
	RunState.add_gold(42)
	_human("pad:a")
	screen.open(3, 2)
	check(screen.visible, "open shows it")
	check(screen.is_open(), "open")
	check_eq(screen.title_label.text, "Wave 3 cleared!", "title")
	check_eq(screen.gold_value.text, "42", "shared gold")
	check_eq(screen.level_ups_value.text, "+2", "level-ups")
	check("Wave 4" in screen.next_label.text, "next wave preview: %s" % screen.next_label.text)
	check_eq(screen.chips_row.get_child_count(), 1, "one ready chip per player")
	screen.open(9, 0)
	check("Boss" in screen.next_label.text, "boss wave 10 announced")
	check_eq(screen.level_ups_value.text, "–", "no level-ups")


func test_everyone_ready_continues_once() -> void:
	var a := _human("pad:a")
	var b := _human("pad:b")
	PlayerManager.set_all_ready(true)
	screen.open(1, 0)
	check(not PlayerManager.get_slot(0).ready and not PlayerManager.get_slot(1).ready, "open clears ready")
	UiFakes.step(screen)  # first frame after open is ignored
	UiFakes.tap(screen, a, PlayerInput.Pad.START)
	check(PlayerManager.get_slot(0).ready, "P1 ready")
	check_eq(continues, 0, "waiting for P2")
	UiFakes.tap(screen, b, PlayerInput.Pad.START)
	check(PlayerManager.get_slot(1).ready, "START readies")
	check_eq(continues, 1, "all ready -> continue")
	UiFakes.tap(screen, a, PlayerInput.Pad.B)
	UiFakes.tap(screen, a, PlayerInput.Pad.START)
	check_eq(continues, 1, "only once per open")
	screen.open(2, 0)
	UiFakes.step(screen)
	UiFakes.tap(screen, a, PlayerInput.Pad.START)
	UiFakes.tap(screen, b, PlayerInput.Pad.START)
	check_eq(continues, 2, "next open works again")


func test_start_toggles_and_b_unreadies() -> void:
	var a := _human("pad:a")
	_human("pad:b")
	screen.open(1, 0)
	UiFakes.step(screen)
	var slot := PlayerManager.get_slot(0)
	UiFakes.tap(screen, a, PlayerInput.Pad.A)
	check(not slot.ready, "A buys in the shop, it does not ready")
	UiFakes.tap(screen, a, PlayerInput.Pad.START)
	check(slot.ready, "START readies")
	UiFakes.tap(screen, a, PlayerInput.Pad.START)
	check(not slot.ready, "START again unreadies")
	UiFakes.tap(screen, a, PlayerInput.Pad.START)
	UiFakes.tap(screen, a, PlayerInput.Pad.B)
	check(not slot.ready, "B unreadies")
	check_eq(continues, 0, "never everyone ready")


func test_press_on_the_opening_frame_is_ignored() -> void:
	var a := _human("pad:a")
	a.press(PlayerInput.Pad.START)
	a.poll(0.016)
	screen.open(1, 0)
	screen._process(0.016)
	check(not PlayerManager.get_slot(0).ready, "the press that was down when the screen opened is ignored")


func test_bots_are_auto_ready() -> void:
	PlayerManager.join(ScriptedInput.new("bot:0"), Db.get_class_data(&"mage"))
	var human := _human("pad:a")
	screen.open(4, 1)
	check(PlayerManager.get_slot(0).ready, "bot ready at once")
	check(not PlayerManager.get_slot(1).ready, "human not")
	UiFakes.step(screen)
	UiFakes.tap(screen, human, PlayerInput.Pad.START)
	check_eq(continues, 1, "bot never blocks")


func test_all_bots_continue_by_themselves() -> void:
	PlayerManager.add_bot(&"warrior", 1)
	PlayerManager.add_bot(&"mage", 2)
	screen.open(1, 0)
	UiFakes.step(screen)
	UiFakes.step(screen)
	check_eq(continues, 1, "bot-only party continues")


func test_unplugged_player_does_not_block() -> void:
	var a := _human("pad:a")
	var b := _human("pad:b")
	b.connected = false
	screen.open(1, 0)
	check(Intermission.is_auto_ready(PlayerManager.get_slot(1)), "unplugged counts as ready")
	UiFakes.step(screen)
	UiFakes.tap(screen, a, PlayerInput.Pad.START)
	check_eq(continues, 1, "continues without the unplugged player")


func test_b_and_start_together_act_as_b() -> void:
	var a := _human("pad:a")
	_human("pad:b")
	screen.open(1, 0)
	UiFakes.step(screen)
	UiFakes.tap(screen, a, PlayerInput.Pad.START)
	check(PlayerManager.get_slot(0).ready, "ready first")
	a.press(PlayerInput.Pad.B)
	a.press(PlayerInput.Pad.START)
	UiFakes.step(screen)
	check(not PlayerManager.get_slot(0).ready, "keyboard Esc (B + START) unreadies")


func test_next_wave_starts_by_itself_after_the_countdown() -> void:
	check_eq(Intermission.AUTO_CONTINUE_TIME, 60.0, "GDD 12: 60 s")
	var a := _human("pad:a")
	_human("pad:b")
	screen.open(1, 0)
	check(screen.countdown_label.visible, "countdown shown")
	check_eq(screen.countdown_label.text, "Next wave in 60 s", "full minute")
	UiFakes.step(screen, 18.0)
	check_eq(screen.countdown_label.text, "Next wave in 42 s", "counts down")
	check_eq(screen.countdown_label.get_theme_color(&"font_color"), UiTheme.TEXT_DIM, "calm colour")
	UiFakes.tap(screen, a, PlayerInput.Pad.START)
	check(PlayerManager.get_slot(0).ready, "P1 ready, P2 dawdles")
	UiFakes.step(screen, 31.5)
	check_eq(continues, 0, "still waiting")
	check_eq(screen.countdown_label.text, "Next wave in 11 s", "11 s left")
	UiFakes.step(screen, 1.0)
	check_eq(screen.countdown_label.get_theme_color(&"font_color"), UiTheme.GOLD, "last seconds in gold")
	UiFakes.step(screen, 9.0)
	check_eq(continues, 0, "not before the full minute")
	UiFakes.step(screen, 1.0)
	check_eq(continues, 1, "the next wave starts without P2")
	check(not PlayerManager.get_slot(1).ready, "P2 never readied")
	check_eq(screen.time_left, 0.0, "countdown done")
	UiFakes.step(screen, 5.0)
	check_eq(continues, 1, "only once per open")
	screen.open(2, 0)
	check_eq(screen.countdown_label.text, "Next wave in 60 s", "restarts on the next open")
	UiFakes.step(screen, 30.0)
	check_eq(continues, 1, "fresh minute")


func test_auto_continue_setting() -> void:
	_human("pad:a")
	Intermission.auto_continue_time = 0.0
	screen.open(1, 0)
	check(not screen.countdown_label.visible, "no countdown when switched off")
	for _i in 10:
		UiFakes.step(screen, 30.0)
	check_eq(continues, 0, "waits for everybody's Ready forever")
	Intermission.auto_continue_time = 5.0
	screen.open(2, 0)
	check(screen.countdown_label.visible, "countdown back")
	check_eq(screen.countdown_label.text, "Next wave in 5 s", "custom length")
	UiFakes.step(screen, 5.0)
	check_eq(continues, 1, "custom length honoured")
