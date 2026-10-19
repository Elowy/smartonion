extends TestCase
## PauseMenu: only the pausing player navigates, B / any START resumes, the opening press is
## swallowed, process_mode ALWAYS.

const UiFakes := preload("res://tests/ui_fakes.gd")

var menu: PauseMenu
var resumes := 0
var quits := 0


func before_each() -> void:
	UiFakes.reset_players()
	menu = PauseMenu.create()
	menu.resume_requested.connect(func() -> void: resumes += 1)
	menu.quit_to_menu_requested.connect(func() -> void: quits += 1)
	UiFakes.add_to_root(tree, menu)


func after_each() -> void:
	UiFakes.free_node(menu)
	menu = null
	UiFakes.reset_players()


func _human(key: String) -> UiFakes.HumanInput:
	var input := UiFakes.HumanInput.new(key)
	PlayerManager.join(input, Db.get_class_data(&"paladin"))
	return input


func test_processes_while_paused_and_starts_hidden() -> void:
	check_eq(menu.process_mode, Node.PROCESS_MODE_ALWAYS, "runs while the tree is paused")
	check(not menu.visible, "hidden until opened")
	check_eq(menu.buttons.size(), 3, "Resume / Settings / Quit to Menu")
	check_eq(menu.entries, [PauseMenu.Item.RESUME, PauseMenu.Item.SETTINGS, PauseMenu.Item.QUIT] as Array[int], "in that order")


func test_navigate_and_quit() -> void:
	var a := _human("pad:a")
	menu.open(PlayerManager.get_slot(0))
	check(menu.visible, "open shows it")
	check_eq(menu.selected, PauseMenu.Item.RESUME, "Resume selected first")
	UiFakes.step(menu)
	UiFakes.nudge(menu, a, Vector2.DOWN)
	check_eq(menu.selected, PauseMenu.Item.SETTINGS, "down -> Settings")
	UiFakes.nudge(menu, a, Vector2.DOWN)
	check_eq(menu.selected, PauseMenu.Item.QUIT, "down again -> Quit to Menu")
	UiFakes.nudge(menu, a, Vector2.DOWN)
	check_eq(menu.selected, PauseMenu.Item.RESUME, "wraps around")
	UiFakes.nudge(menu, a, Vector2.UP)
	check_eq(menu.selected, PauseMenu.Item.QUIT, "up wraps too")
	UiFakes.tap(menu, a, PlayerInput.Pad.A)
	check_eq(quits, 0, "the first A on Quit only asks 'Are you sure?'")
	UiFakes.tap(menu, a, PlayerInput.Pad.A)
	check_eq(quits, 1, "the second A on Quit -> quit_to_menu_requested")
	check_eq(resumes, 0, "no resume")
	check(not menu.visible, "closed")


func test_a_on_resume_resumes() -> void:
	var a := _human("pad:a")
	menu.open(PlayerManager.get_slot(0))
	UiFakes.step(menu)
	UiFakes.tap(menu, a, PlayerInput.Pad.A)
	check_eq(resumes, 1, "resume")
	check_eq(quits, 0, "no quit")


func test_only_the_pausing_player_navigates() -> void:
	_human("pad:a")
	var b := _human("pad:b")
	menu.open(PlayerManager.get_slot(0))
	UiFakes.step(menu)
	UiFakes.nudge(menu, b, Vector2.DOWN)
	check_eq(menu.selected, PauseMenu.Item.RESUME, "P2 cannot move the selection")
	UiFakes.tap(menu, b, PlayerInput.Pad.A)
	UiFakes.tap(menu, b, PlayerInput.Pad.B)
	check_eq(resumes + quits, 0, "P2's A / B do nothing")
	UiFakes.tap(menu, b, PlayerInput.Pad.START)
	check_eq(resumes, 1, "any player's START resumes")


func test_b_resumes() -> void:
	var a := _human("pad:a")
	menu.open(PlayerManager.get_slot(0))
	UiFakes.step(menu)
	UiFakes.tap(menu, a, PlayerInput.Pad.B)
	check_eq(resumes, 1, "B resumes")


func test_opening_start_press_does_not_resume() -> void:
	var a := _human("pad:a")
	a.press(PlayerInput.Pad.START)
	a.poll(0.016)
	menu.open(PlayerManager.get_slot(0))
	menu._process(0.016)
	check_eq(resumes, 0, "the START that paused is swallowed")
	a.release(PlayerInput.Pad.START)
	UiFakes.step(menu)
	UiFakes.tap(menu, a, PlayerInput.Pad.START)
	check_eq(resumes, 1, "a new START resumes")


func test_open_without_slot_uses_any_controller() -> void:
	menu.open(null)
	UiFakes.step(menu)
	menu.pads.injected.append(JOY_BUTTON_A)
	UiFakes.step(menu)
	check_eq(resumes, 1, "any controller's A on Resume")
	menu.open(null)
	UiFakes.step(menu)
	menu.move_selection(2)
	menu.activate_selected()
	check_eq(quits, 1, "activate_selected on Quit")
