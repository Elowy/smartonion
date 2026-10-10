extends TestCase
## UiTheme helpers, MainMenu, Hud (unit frames bound to real players, wave timer, gold, XP,
## banner, notice) and GameOverScreen.

const UiFakes := preload("res://tests/ui_fakes.gd")

var world: Node3D
var nodes: Array[Node] = []


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(2, 11)
	world = Node3D.new()
	world.name = "UiTestWorld"
	tree.root.add_child(world)
	tree.current_scene = world


func after_each() -> void:
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()
	UiFakes.free_node(world)
	world = null
	UiFakes.reset_players()


func _add(n: Node) -> Node:
	tree.root.add_child(n)
	nodes.append(n)
	return n


func _player(index_class: StringName) -> Player:
	var slot := PlayerManager.join(UiFakes.HumanInput.new("pad:%s" % index_class), Db.get_class_data(index_class))
	var p := Player.create(slot)
	world.add_child(p)
	return p


# --- Theme ---------------------------------------------------------------------------

func test_theme_is_cached_and_complete() -> void:
	var t := UiTheme.get_theme()
	check(t != null, "theme")
	check(t == UiTheme.get_theme(), "cached")
	check(t.has_stylebox(&"panel", &"PanelContainer"), "panel style")
	for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		check(t.has_stylebox(state, &"Button"), "button %s" % state)
	check(t.has_stylebox(&"fill", &"ProgressBar"), "progress bar fill")
	check(t.has_stylebox(&"panel", &"TooltipPanel"), "parchment tooltip")
	check_eq(t.get_type_variation_base(UiTheme.TITLE), &"Label", "TitleLabel variation")
	check_eq(t.get_type_variation_base(UiTheme.PARCHMENT_PANEL), &"PanelContainer", "ParchmentPanel variation")
	check(t.get_constant(&"outline_size", &"Label") > 0, "outlined labels")


func test_format_helpers() -> void:
	check_eq(UiTheme.format_int(0), "0", "0")
	check_eq(UiTheme.format_int(999), "999", "999")
	check_eq(UiTheme.format_int(12345), "12,345", "thousands")
	check_eq(UiTheme.format_int(-1234567), "-1,234,567", "negative")
	check_eq(UiTheme.format_time(42.3), "43", "ceil seconds")
	check_eq(UiTheme.format_time(65.0), "1:05", "minutes")
	check_eq(UiTheme.format_time(-1.0), "0", "never negative")
	check_eq(UiTheme.format_amount(14.2), "15", "hp rounds up")
	check_eq(UiTheme.resource_name(&"holy_power"), "Holy Power", "resource names")


func test_glyph_for_keyboard_is_a_key_cap() -> void:
	var g := UiGlyph.for_input(KeyboardInput.new(), PlayerInput.Pad.A)
	check_eq(g.style, UiGlyph.Style.KEY, "keyboard -> key cap")
	check_eq(g.text, "Enter", "A = Enter")
	var p := UiGlyph.for_input(UiFakes.HumanInput.new(), PlayerInput.Pad.B)
	check_eq(p.style, UiGlyph.Style.PAD, "controller -> face button")
	check_eq(p.text, "B", "B")
	g.free()
	p.free()


# --- Main menu -------------------------------------------------------------------------

func test_main_menu_buttons() -> void:
	var menu := _add(MainMenu.create()) as MainMenu
	var plays: Array[int] = [0]
	var quits: Array[int] = [0]
	menu.play_pressed.connect(func() -> void: plays[0] += 1)
	menu.quit_pressed.connect(func() -> void: quits[0] += 1)
	check_eq(menu.title_label.text, "SmartOnion", "title")
	menu.play_button.pressed.emit()
	check_eq(plays[0], 1, "Play")
	menu.quit_button.pressed.emit()
	check_eq(quits[0], 1, "Quit")
	menu.quit_button.grab_focus()
	menu.activate_focused()
	check_eq(quits[0], 2, "controller A presses the focused button")
	menu.play_button.grab_focus()
	menu._pads.injected.append(JOY_BUTTON_A)
	menu._process(0.016)
	check_eq(plays[0], 2, "any controller's A works before anyone joined")


# --- HUD -----------------------------------------------------------------------------

func test_hud_frames_follow_players() -> void:
	var p1 := _player(&"warrior")
	var p2 := _player(&"mage")
	var hud := _add(Hud.create()) as Hud
	var players: Array[Player] = [p1, p2]
	hud.bind_players(players)
	check(hud.frames[0].visible and hud.frames[1].visible, "P1 / P2 frames shown")
	check(not hud.frames[2].visible and not hud.frames[3].visible, "unused frames hidden")
	check(hud.frames[0].player == p1, "frame 0 bound to P1")
	check_eq(hud.frames[0].hp_bar.text, "15 / 15", "warrior hp text")
	check_eq(hud.frames[1].hp_bar.text, "7 / 7", "mage hp text")
	check_eq(hud.frames[0].resource_bar.text, "Rage", "resource label")
	p1.take_damage(5.0)
	check_eq(hud.frames[0].hp_bar.text, "%s / 15" % UiTheme.format_amount(p1.hp), "hp_changed updates the bar")
	check(hud.frames[0].hp_bar.value < 15.0, "bar value dropped")
	p2.take_damage(1000.0)
	check(p2.downed, "mage downed")
	check(hud.frames[1].is_downed_shown(), "DOWNED overlay")
	p2.revive(0.5)
	check(not hud.frames[1].is_downed_shown(), "overlay gone after revive")
	world.remove_child(p2)
	p2.free()
	hud._process(0.016)
	for f in hud.frames:
		f._process(0.016)
	check(not hud.frames[1].visible, "freed player's frame hides")
	hud.bind_players([] as Array[Player])
	check(not hud.frames[0].visible, "rebinding with nobody hides all")


func test_hud_wave_timer_gold_xp() -> void:
	var hud := _add(Hud.create()) as Hud
	RunState.set_wave(10)
	check_eq(hud.wave_label.text, "Wave 10 / 25", "wave label")
	check(hud.wave_tag_label.visible, "boss wave tag")
	RunState.set_wave(3)
	check(not hud.wave_tag_label.visible, "regular wave")
	hud.set_wave_time(27.4)
	check_eq(hud.timer_label.text, "28", "timer text")
	check(hud.timer_label.get_theme_color(&"font_color") != UiTheme.RED, "not red")
	hud.set_wave_time(4.5)
	check_eq(hud.timer_label.get_theme_color(&"font_color"), UiTheme.RED, "red at <= 5 s")
	RunState.add_gold(37)
	for i in 30:
		hud._process(0.1)
	check_eq(hud.gold_label.text, "37", "gold counts up to the shared wallet")
	RunState.add_xp(5)
	check_eq(hud.xp_bar.value, 5.0, "xp bar value")
	check_eq(hud.xp_label.text, "5 / %d XP" % RunState.xp_to_next_level(), "xp text")
	RunState.add_xp(RunState.xp_to_next_level())
	check_eq(hud.level_label.text, "Level %d" % RunState.level, "level label")
	check(hud.is_banner_visible(), "LEVEL UP! banner")
	check_eq(hud.banner_label.text, "LEVEL UP!", "banner text")


func test_hud_banner_and_notice() -> void:
	var hud := _add(Hud.create()) as Hud
	hud.show_banner("Wave 4", UiTheme.TEXT)
	check(hud.is_banner_visible(), "banner shows")
	check_eq(hud.banner_label.text, "Wave 4", "banner text")
	check(not hud.is_notice_visible(), "no notice by default")
	hud.show_notice("Controller disconnected – P2")
	check(hud.is_notice_visible(), "notice")
	check_eq(hud.notice_label.text, "Controller disconnected – P2", "notice text")
	hud.hide_notice()
	check(not hud.is_notice_visible(), "hidden")


# --- Game over ---------------------------------------------------------------------------

func test_game_over_summary_and_input_delay() -> void:
	var a := UiFakes.HumanInput.new("pad:a")
	PlayerManager.join(a, Db.get_class_data(&"warrior"))
	PlayerManager.join(UiFakes.HumanInput.new("pad:b"), Db.get_class_data(&"mage"))
	RunState.set_wave(7)
	RunState.add_gold(250)
	RunState.record_kill(0)
	RunState.record_kill(0)
	RunState.record_kill(1)
	RunState.record_damage(1, 1234.0)
	var screen := _add(GameOverScreen.create()) as GameOverScreen
	var backs: Array[int] = [0]
	screen.back_to_menu_requested.connect(func() -> void: backs[0] += 1)
	check(not screen.visible, "hidden until opened")
	screen.open(false)
	check_eq(screen.title_label.text, "Defeat", "defeat title")
	check_eq(screen.waves_value.text, "6 / 25", "waves cleared")
	check_eq(screen.kills_value.text, "3", "total kills")
	check_eq(screen.gold_value.text, "250", "gold earned")
	check_eq(screen.rows_box.get_child_count(), 2, "a row per player")
	UiFakes.tap(screen, a, PlayerInput.Pad.A)
	check_eq(backs[0], 0, "input ignored right after opening")
	UiFakes.step(screen, GameOverScreen.INPUT_DELAY)
	UiFakes.tap(screen, a, PlayerInput.Pad.A)
	check_eq(backs[0], 1, "A -> back to menu")
	UiFakes.tap(screen, a, PlayerInput.Pad.A)
	check_eq(backs[0], 1, "only once")
	screen.open(true)
	check_eq(screen.title_label.text, "Victory!", "victory title")
	check_eq(screen.waves_value.text, "25 / 25", "all waves")
