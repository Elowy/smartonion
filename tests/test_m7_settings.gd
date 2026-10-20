extends TestCase
## M7a SETTINGS: GameSettings (defaults, file round trip, clamping / stepping, volume -> dB), the Settings
## autoload (audio buses, shake / damage-number reads, FPS counter, inert in automated runs), the camera and
## Vfx hooks, the Settings page (navigation changes a value), the Credits page (Markdown, built-in text),
## the main menu's four entries and the pause menu's Settings entry.

const UiFakes := preload("res://tests/ui_fakes.gd")

var _tmp_path := "user://m7_settings_test_%d.cfg" % OS.get_process_id()
var _saved: Dictionary[StringName, Variant] = {}
## Volume / mute of the buses (Master, Music, SFX, UI) that exist, as the test found them.
var _buses: Dictionary[StringName, Array] = {}
var _added_buses: Array[StringName] = []
var _nodes: Array[Node] = []
var _async := false


func is_async() -> bool:
	return _async


func before_each() -> void:
	UiFakes.reset_players()
	_saved = Settings.data.values.duplicate()
	_buses.clear()
	for bus_name: StringName in GameSettings.BUS_NAMES.values():
		var i := AudioServer.get_bus_index(bus_name)
		if i >= 0:
			_buses[bus_name] = [AudioServer.get_bus_volume_db(i), AudioServer.is_bus_mute(i)]


func after_each() -> void:
	for n in _nodes:
		UiFakes.free_node(n)
	_nodes.clear()
	for key: StringName in _saved:
		Settings.data.values[key] = _saved[key]
	Settings._sync_fps_overlay()
	if Settings.fps_overlay != null and not Settings.show_fps_enabled():
		Settings.fps_overlay.free()
		Settings.fps_overlay = null
	for bus_name in _added_buses:
		AudioServer.remove_bus(AudioServer.get_bus_index(bus_name))
	_added_buses.clear()
	for bus_name: StringName in _buses:
		var i := AudioServer.get_bus_index(bus_name)
		AudioServer.set_bus_volume_db(i, _buses[bus_name][0])
		AudioServer.set_bus_mute(i, _buses[bus_name][1])
	for path in [_tmp_path, _tmp_path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	UiFakes.reset_players()


func _add(node: Node) -> Node:
	tree.root.add_child(node)
	_nodes.append(node)
	return node


func _human(key: String = "pad:a") -> UiFakes.HumanInput:
	var input := UiFakes.HumanInput.new(key)
	PlayerManager.join(input, Db.get_class_data(&"paladin"))
	return input


# --- GameSettings: defaults, clamping, stepping -------------------------------------------------

func test_defaults() -> void:
	var s := GameSettings.new()
	check_eq(s.volume_percent(GameSettings.MASTER_VOLUME), 100, "master 100")
	check_eq(s.volume_percent(GameSettings.MUSIC_VOLUME), 70, "music 70")
	check_eq(s.volume_percent(GameSettings.SFX_VOLUME), 80, "sfx 80")
	check_eq(s.volume_percent(GameSettings.UI_VOLUME), 80, "ui 80")
	check_eq(s.window_mode(), GameSettings.WindowMode.WINDOWED, "windowed")
	check(s.vsync_enabled(), "VSync on")
	check_eq(s.max_fps(), 0, "unlimited FPS")
	check_eq(s.shake_level(), GameSettings.Shake.FULL, "full shake")
	check(s.damage_numbers_enabled(), "damage numbers on")
	check(not s.show_fps_enabled(), "FPS counter off")
	check(s.is_default(), "is_default")
	check_eq(GameSettings.options().size(), 10, "ten options")
	var sections: Array[String] = []
	for o in GameSettings.options():
		if sections.is_empty() or sections[-1] != o.section:
			sections.append(o.section)
	check_eq(sections, ["Audio", "Video", "Gameplay"] as Array[String], "listed in three sections")


func test_volumes_clamp_and_snap_to_steps_of_ten() -> void:
	var s := GameSettings.new()
	s.set_value(GameSettings.MASTER_VOLUME, 250)
	check_eq(s.volume_percent(GameSettings.MASTER_VOLUME), 100, "above 100 -> 100")
	s.set_value(GameSettings.MASTER_VOLUME, -40)
	check_eq(s.volume_percent(GameSettings.MASTER_VOLUME), 0, "below 0 -> 0")
	s.set_value(GameSettings.MUSIC_VOLUME, 33)
	check_eq(s.volume_percent(GameSettings.MUSIC_VOLUME), 30, "33 -> 30")
	s.set_value(GameSettings.MUSIC_VOLUME, 36.0)
	check_eq(s.volume_percent(GameSettings.MUSIC_VOLUME), 40, "36 -> 40")
	s.set_value(GameSettings.MUSIC_VOLUME, "loud")
	check_eq(s.volume_percent(GameSettings.MUSIC_VOLUME), 70, "nonsense -> the default")
	check(not s.set_value(&"no_such_key", 1), "an unknown key is refused")


func test_stepping() -> void:
	var s := GameSettings.new()
	check(s.step_value(GameSettings.SFX_VOLUME, 1), "80 -> 90 changes")
	check_eq(s.volume_percent(GameSettings.SFX_VOLUME), 90, "up")
	s.step_value(GameSettings.SFX_VOLUME, 1)
	check(not s.step_value(GameSettings.SFX_VOLUME, 1), "100 is the end: no wrap")
	check_eq(s.volume_percent(GameSettings.SFX_VOLUME), 100, "stays at 100")
	s.set_value(GameSettings.SFX_VOLUME, 0)
	check(not s.step_value(GameSettings.SFX_VOLUME, -1), "0 is the end too")
	# Choices wrap, toggles flip.
	s.step_value(GameSettings.WINDOW_MODE, -1)
	check_eq(s.window_mode(), GameSettings.WindowMode.FULLSCREEN, "left of Windowed wraps to Fullscreen")
	s.step_value(GameSettings.WINDOW_MODE, 1)
	check_eq(s.window_mode(), GameSettings.WindowMode.WINDOWED, "and back")
	var caps: Array[int] = []
	for i in GameSettings.FPS_CAPS.size():
		s.step_value(GameSettings.MAX_FPS, 1)
		caps.append(s.max_fps())
	check_eq(caps, [30, 60, 120, 144, 0] as Array[int], "Unlimited -> 30 -> 60 -> 120 -> 144 -> Unlimited")
	s.step_value(GameSettings.VSYNC, 1)
	check(not s.vsync_enabled(), "a toggle flips")
	s.step_value(GameSettings.VSYNC, -1)
	check(s.vsync_enabled(), "either direction")
	check_eq(s.value_text(GameSettings.WINDOW_MODE), "Windowed", "text of a choice")
	check_eq(s.value_text(GameSettings.MUSIC_VOLUME), "70%", "text of a volume")
	check_eq(s.value_text(GameSettings.DAMAGE_NUMBERS), "On", "text of a toggle")
	s.set_value(GameSettings.WINDOW_MODE, 7)
	check_eq(s.window_mode(), GameSettings.WindowMode.WINDOWED, "an unknown choice -> the default")


func test_reset_to_defaults() -> void:
	var s := GameSettings.new()
	check(not s.reset_to_defaults(), "nothing to reset")
	s.set_value(GameSettings.MUSIC_VOLUME, 10)
	s.set_value(GameSettings.SHOW_FPS, true)
	check(not s.is_default(), "changed")
	check(s.reset_to_defaults(), "reset reports a change")
	check(s.is_default(), "back to the defaults")


# --- File ------------------------------------------------------------------------------------

func test_save_and_load_round_trip() -> void:
	var s := GameSettings.new()
	s.path = _tmp_path
	s.set_value(GameSettings.MASTER_VOLUME, 40)
	s.set_value(GameSettings.MUSIC_VOLUME, 0)
	s.set_value(GameSettings.WINDOW_MODE, GameSettings.WindowMode.BORDERLESS)
	s.set_value(GameSettings.VSYNC, false)
	s.set_value(GameSettings.MAX_FPS, 144)
	s.set_value(GameSettings.SCREEN_SHAKE, GameSettings.Shake.LOW)
	s.set_value(GameSettings.DAMAGE_NUMBERS, false)
	s.set_value(GameSettings.SHOW_FPS, true)
	check_eq(s.save_file(), OK, "saved")
	check(not FileAccess.file_exists(_tmp_path + ".tmp"), "the temporary file is gone")
	var text := FileAccess.get_file_as_string(_tmp_path)
	check("[audio]" in text and "[video]" in text and "[gameplay]" in text, "ConfigFile sections")
	check('window_mode="borderless"' in text and 'max_fps="144"' in text, "readable names for the choices")
	var loaded := GameSettings.new()
	loaded.path = _tmp_path
	check_eq(loaded.load_file(), OK, "loaded")
	check_eq(loaded.values, s.values, "every value survives the round trip")
	check(not loaded.is_default(), "and they are not the defaults")


func test_a_missing_file_gives_the_defaults() -> void:
	var s := GameSettings.new()
	s.path = _tmp_path
	s.set_value(GameSettings.MASTER_VOLUME, 20)
	check_eq(s.load_file(), OK, "no file is fine")
	check(s.is_default(), "defaults")


func test_a_hand_edited_file_is_sanitised() -> void:
	var f := FileAccess.open(_tmp_path, FileAccess.WRITE)
	f.store_string('[audio]\nmaster_volume=250\nmusic_volume=-3\nsfx_volume="loud"\n[video]\nwindow_mode="sideways"\n'
		+ 'vsync="yes"\nmax_fps="100"\n[gameplay]\nscreen_shake="low"\n')
	f.close()
	var s := GameSettings.new()
	s.path = _tmp_path
	check_eq(s.load_file(), OK, "readable")
	check_eq(s.volume_percent(GameSettings.MASTER_VOLUME), 100, "250 -> 100")
	check_eq(s.volume_percent(GameSettings.MUSIC_VOLUME), 0, "-3 -> 0")
	check_eq(s.volume_percent(GameSettings.SFX_VOLUME), 80, "not a number -> default")
	check_eq(s.window_mode(), GameSettings.WindowMode.WINDOWED, "unknown name -> default")
	check(s.vsync_enabled(), "not a bool -> default")
	check_eq(s.max_fps(), 0, "an FPS cap that is not offered -> default")
	check_eq(s.shake_level(), GameSettings.Shake.LOW, "valid values are kept")
	check(s.damage_numbers_enabled(), "missing keys -> default")


func test_a_corrupt_file_gives_the_defaults_and_an_error() -> void:
	expect_error("ConfigFile parse error")
	var f := FileAccess.open(_tmp_path, FileAccess.WRITE)
	f.store_string("[audio\nthis is = not = a config {{{\n")
	f.close()
	var s := GameSettings.new()
	s.path = _tmp_path
	s.set_value(GameSettings.MUSIC_VOLUME, 10)
	check(s.load_file() != OK, "the parse error is reported")
	check(s.is_default(), "and the values are the defaults")


# --- Volume -> dB ----------------------------------------------------------------------------

func test_volume_to_db() -> void:
	check_near(GameSettings.volume_to_db(100), 0.0, 0.0001, "100% = 0 dB")
	check_near(GameSettings.volume_to_db(50), -6.0206, 0.001, "50% = -6 dB (linear amplitude)")
	check_near(GameSettings.volume_to_db(10), -20.0, 0.001, "10% = -20 dB")
	check_eq(GameSettings.volume_to_db(0), GameSettings.MUTE_DB, "0% is the floor")
	check_eq(GameSettings.volume_to_db(-5), GameSettings.MUTE_DB, "below 0 too")
	check_near(GameSettings.volume_to_db(300), 0.0, 0.0001, "above 100 never boosts")
	var last := -1000.0
	for p in range(0, 101, GameSettings.VOLUME_STEP):
		var db := GameSettings.volume_to_db(p)
		check(db > last, "louder at %d%%" % p)
		last = db


# --- The Settings autoload ---------------------------------------------------------------------

func test_the_autoload_is_inert_in_the_test_runner() -> void:
	check(Settings.is_automated_run(), "a test run is an automated run")
	check(not Settings.persist, "the player's settings file is never read or written")
	check(not Settings.video_enabled, "the window is never touched")
	check_eq(Settings.data.path, GameSettings.PATH, "(the real path, which nothing writes)")
	var existed := FileAccess.file_exists(GameSettings.PATH)
	Settings.set_value(GameSettings.MUSIC_VOLUME, 20)
	check_eq(Settings.save(), OK, "save is a no-op")
	check_eq(FileAccess.file_exists(GameSettings.PATH), existed, "no file appeared")


func test_launch_options_tell_automated_launches() -> void:
	check(not LaunchOptions.parse(PackedStringArray()).is_automated(), "a plain launch is the player's")
	for arg in ["--smoke", "--demo", "--view=settings", "--view=credits", "--view=pause", "--screenshot=/tmp/x.png"]:
		check(LaunchOptions.parse(PackedStringArray([arg])).is_automated(), "%s is automated" % arg)
	var o := LaunchOptions.parse(PackedStringArray(["--view=credits"]))
	check_eq(o.view, "credits", "--view=credits is a view")
	check(o.unknown.is_empty(), "and understood")
	check_eq(o.boot_state(), &"menu", "it boots into the menu")
	check_eq(LaunchOptions.parse(PackedStringArray(["--view=settings"])).boot_state(), &"menu", "settings too")


func test_changes_are_applied_and_announced() -> void:
	var seen: Array[StringName] = []
	var on_changed := func(key: StringName) -> void: seen.append(key)
	Settings.changed.connect(on_changed)
	Settings.set_value(GameSettings.SFX_VOLUME, 50)
	Settings.set_value(GameSettings.SFX_VOLUME, 50)
	Settings.step_value(GameSettings.SHOW_FPS, 1)
	Settings.set_value(GameSettings.MUSIC_VOLUME, 0)
	check_eq(seen, [GameSettings.SFX_VOLUME, GameSettings.SHOW_FPS, GameSettings.MUSIC_VOLUME] as Array[StringName],
		"one signal per real change")
	seen.clear()
	Settings.reset_to_defaults()
	Settings.changed.disconnect(on_changed)
	check_eq(seen, [GameSettings.MUSIC_VOLUME, GameSettings.SFX_VOLUME, GameSettings.SHOW_FPS] as Array[StringName],
		"a reset announces each key it moved")
	check(Settings.data.is_default(), "reset")


## Adds the buses Master / Music / SFX / UI the project does not have (after_each removes them again).
func _ensure_buses() -> void:
	for bus_name: StringName in GameSettings.BUS_NAMES.values():
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			_added_buses.append(bus_name)


func test_volumes_drive_the_buses_by_name() -> void:
	_ensure_buses()
	Settings.set_value(GameSettings.MUSIC_VOLUME, 50)
	var music := AudioServer.get_bus_index(&"Music")
	check_near(AudioServer.get_bus_volume_db(music), -6.0206, 0.001, "Music at 50%")
	check(not AudioServer.is_bus_mute(music), "audible")
	Settings.set_value(GameSettings.MUSIC_VOLUME, 0)
	check(AudioServer.is_bus_mute(music), "0% mutes the bus")
	check_eq(AudioServer.get_bus_volume_db(music), GameSettings.MUTE_DB, "at the floor")
	Settings.set_value(GameSettings.MUSIC_VOLUME, 10)
	check(not AudioServer.is_bus_mute(music), "10% unmutes it again")
	Settings.set_value(GameSettings.MASTER_VOLUME, 100)
	Settings.set_value(GameSettings.SFX_VOLUME, 90)
	Settings.set_value(GameSettings.UI_VOLUME, 20)
	check_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Master")), 0.0, 0.0001, "Master 100%")
	check_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX")), linear_to_db(0.9), 0.001, "SFX 90%")
	check_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"UI")), -13.9794, 0.001, "UI 20%")
	Settings.apply_all()
	check_near(AudioServer.get_bus_volume_db(music), linear_to_db(0.1), 0.001, "apply_all pushes every value")


func test_a_bus_the_project_does_not_have_is_ignored() -> void:
	var bus_name := GameSettings.BUS_NAMES[GameSettings.UI_VOLUME]
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		return  # (the audio package's layout has it: nothing to prove here)
	Settings.set_value(GameSettings.UI_VOLUME, 30)
	Settings.apply_all()
	check_eq(AudioServer.get_bus_index(bus_name), -1, "still no UI bus, and no error")


func test_screen_shake_levels() -> void:
	var s := GameSettings.new()
	for level in [[GameSettings.Shake.OFF, 0.0], [GameSettings.Shake.LOW, 0.5], [GameSettings.Shake.FULL, 1.0]]:
		s.set_value(GameSettings.SCREEN_SHAKE, level[0])
		check_eq(s.screen_shake_mult(), level[1], "level %s" % level[0])
	Settings.set_value(GameSettings.SCREEN_SHAKE, GameSettings.Shake.LOW)
	check_eq(Settings.screen_shake_mult(), 0.5, "Settings.screen_shake_mult")
	var rig := CameraRig.new()
	rig.view_rect = Rect2(-25, -19, 50, 38)
	_add(rig)
	rig.shake(0.4)
	check_near(rig.get_trauma(), 0.2, 0.0001, "Low halves the camera trauma")
	Settings.set_value(GameSettings.SCREEN_SHAKE, GameSettings.Shake.OFF)
	rig.snap()
	rig.shake(1.0)
	check_eq(rig.get_trauma(), 0.0, "Off: no shake at all")
	Settings.set_value(GameSettings.SCREEN_SHAKE, GameSettings.Shake.FULL)
	rig.shake(0.4)
	check_near(rig.get_trauma(), 0.4, 0.0001, "Full: unchanged")


func test_damage_numbers_toggle_is_respected_by_vfx() -> void:
	var arena := Arena.create()
	_add(arena)
	var target := Node3D.new()
	_add(target)
	var white := Color(1, 1, 1, 0.75)
	var count := func() -> int:
		var n := 0
		for c in arena.entities.get_children():
			if c is VfxEffect and not c.is_queued_for_deletion():
				n += 1
		return n
	check(Settings.damage_numbers_enabled(), "on by default")
	Vfx.damage_number(target, Vector3.ZERO, 5.0, white, 0.6)
	check_eq(count.call(), 1, "a number appears")
	Settings.set_value(GameSettings.DAMAGE_NUMBERS, false)
	check(not Settings.damage_numbers_enabled(), "Settings.damage_numbers_enabled")
	Vfx.damage_number(target, Vector3.ZERO, 5.0, white, 0.6)
	Vfx.damage_number(null, Vector3.ZERO, 9.0, Color.YELLOW, 1.1)
	check_eq(count.call(), 1, "off: no new number, and the live one is not merged into")
	Vfx.floating_text(Vector3.ZERO, "Dodge", white, 1.0)
	check_eq(count.call(), 2, "other floating text is not a damage number")
	Settings.set_value(GameSettings.DAMAGE_NUMBERS, true)
	Vfx.damage_number(null, Vector3.ZERO, 9.0, Color.YELLOW, 1.1)
	check_eq(count.call(), 3, "on again")


func test_the_fps_counter_follows_the_setting() -> void:
	Settings.set_value(GameSettings.SHOW_FPS, true)
	check(Settings.fps_overlay != null and Settings.fps_overlay.visible, "a corner label appears")
	check(Settings.fps_overlay.label.text.ends_with("FPS"), "it reads '<n> FPS'")
	check_eq(Settings.fps_overlay.layer, FpsOverlay.LAYER, "above every other screen")
	Settings.set_value(GameSettings.SHOW_FPS, false)
	check(not Settings.fps_overlay.visible, "hidden when switched off")


func test_settings_never_touch_the_gameplay_rng() -> void:
	RunState.start_run(4, 12345)
	var states: Array[int] = [RunState.rng.state, RunState.environment_rng.state, RunState.event_rng.state,
			RunState.shrine_rng.state, RunState.dungeon_rng.state]
	var s := GameSettings.new()
	s.path = _tmp_path
	for o in GameSettings.options():
		Settings.step_value(o.key, 1)
		Settings.step_value(o.key, -1)
		s.step_value(o.key, 1)
	s.save_file()
	s.load_file()
	Settings.apply_all()
	Settings.reset_to_defaults()
	var rig := CameraRig.new()
	_add(rig)
	rig.shake(0.5)
	var arena := Arena.create()
	_add(arena)
	Settings.set_value(GameSettings.DAMAGE_NUMBERS, false)
	Vfx.damage_number(null, Vector3.ZERO, 3.0, Color.WHITE, 1.0)
	var after: Array[int] = [RunState.rng.state, RunState.environment_rng.state, RunState.event_rng.state,
			RunState.shrine_rng.state, RunState.dungeon_rng.state]
	check_eq(after, states, "no gameplay generator moved")
	RunState.end_run(false)


# --- Settings page -----------------------------------------------------------------------------

func _page(dim: float = 0.5) -> SettingsPage:
	return _add(SettingsPage.create(dim)) as SettingsPage


func test_the_page_lists_every_option_then_reset_and_back() -> void:
	var page := _page()
	check_eq(page.rows.size(), GameSettings.options().size() + 2, "one row per option, Reset, Back")
	check_eq(page.rows[0].key, GameSettings.MASTER_VOLUME, "Master Volume first")
	check_eq(page.rows[-2].kind, SettingsPage.RowKind.RESET, "Reset to Defaults")
	check_eq(page.rows[-1].kind, SettingsPage.RowKind.BACK, "Back last")
	check(not page.visible, "hidden until opened")
	check_eq(page.process_mode, Node.PROCESS_MODE_ALWAYS, "works while the game is paused")
	check_eq(page.value_text(GameSettings.MUSIC_VOLUME), "70%", "shows the current value")
	check_eq(page.value_text(GameSettings.WINDOW_MODE), "Windowed", "and its name")


func test_navigation_changes_a_value() -> void:
	var a := _human()
	var page := _page()
	var closes: Array[int] = [0]
	page.closed.connect(func() -> void: closes[0] += 1)
	page.open(PlayerManager.get_slot(0))
	check(page.visible and page.selected == 0, "open selects the first row")
	UiFakes.step(page)  # (the opening frame is skipped)
	UiFakes.nudge(page, a, Vector2.LEFT)
	check_eq(Settings.get_value(GameSettings.MASTER_VOLUME), 90, "left lowers Master Volume by 10")
	check_eq(page.value_text(GameSettings.MASTER_VOLUME), "90%", "the page shows it")
	UiFakes.nudge(page, a, Vector2.RIGHT)
	UiFakes.nudge(page, a, Vector2.RIGHT)
	check_eq(Settings.get_value(GameSettings.MASTER_VOLUME), 100, "right raises it, and stops at 100")
	UiFakes.nudge(page, a, Vector2.DOWN)
	check_eq(page.selected, 1, "down moves to Music Volume")
	UiFakes.nudge(page, a, Vector2.RIGHT)
	check_eq(Settings.get_value(GameSettings.MUSIC_VOLUME), 80, "and changes that one")
	check_eq(Settings.get_value(GameSettings.MASTER_VOLUME), 100, "not the other")
	UiFakes.nudge(page, a, Vector2.UP)
	UiFakes.nudge(page, a, Vector2.UP)
	check_eq(page.selected, page.rows.size() - 1, "up from the first row wraps to Back")
	check_eq(closes[0], 0, "still open")
	UiFakes.tap(page, a, PlayerInput.Pad.A)
	check(not page.visible and closes[0] == 1, "A on Back closes the page")


func test_a_flips_toggles_and_cycles_choices_and_b_goes_back() -> void:
	var a := _human()
	var page := _page()
	var closes: Array[int] = [0]
	page.closed.connect(func() -> void: closes[0] += 1)
	page.open(PlayerManager.get_slot(0))
	UiFakes.step(page)
	page.select(page.rows.find(page.row_for(GameSettings.DAMAGE_NUMBERS)))
	UiFakes.tap(page, a, PlayerInput.Pad.A)
	check(not Settings.damage_numbers_enabled(), "A flips Damage Numbers off")
	page.select(page.rows.find(page.row_for(GameSettings.SCREEN_SHAKE)))
	UiFakes.tap(page, a, PlayerInput.Pad.A)
	check_eq(Settings.data.shake_level(), GameSettings.Shake.OFF, "A cycles Screen Shake (Full -> Off)")
	check_eq(page.value_text(GameSettings.SCREEN_SHAKE), "Off", "and the row says so")
	page.select(0)
	UiFakes.tap(page, a, PlayerInput.Pad.A)
	check_eq(Settings.get_value(GameSettings.MASTER_VOLUME), 100, "A does nothing on a volume")
	page.select(page.rows.size() - 2)
	check(not Settings.data.is_default(), "settings differ from the defaults")
	UiFakes.tap(page, a, PlayerInput.Pad.A)
	check(Settings.data.is_default(), "Reset to Defaults")
	check_eq(page.value_text(GameSettings.SCREEN_SHAKE), "Full", "and the page follows")
	UiFakes.tap(page, a, PlayerInput.Pad.B)
	check(not page.visible and closes[0] == 1, "B closes the page")


func test_only_the_driver_and_not_the_opening_press() -> void:
	var a := _human("pad:a")
	var b := _human("pad:b")
	var page := _page()
	a.press(PlayerInput.Pad.A)
	a.poll(0.016)
	page.open(PlayerManager.get_slot(0))
	page._process(0.016)
	a.release(PlayerInput.Pad.A)
	check(page.visible, "the A that opened it does not press anything")
	UiFakes.step(page)
	UiFakes.nudge(page, b, Vector2.LEFT)
	UiFakes.tap(page, b, PlayerInput.Pad.B)
	check(page.visible, "another player's stick and B do nothing")
	check_eq(Settings.get_value(GameSettings.MASTER_VOLUME), 100, "no change")


func test_without_a_driver_any_controller_works() -> void:
	var page := _page()
	var closes: Array[int] = [0]
	page.closed.connect(func() -> void: closes[0] += 1)
	page.open(null)
	UiFakes.step(page)
	page.move_selection(1)
	page.change_selected(-1)
	check_eq(Settings.get_value(GameSettings.MUSIC_VOLUME), 60, "the keyboard / any controller path")
	page.pads.injected.append(JOY_BUTTON_B)
	UiFakes.step(page)
	check(not page.visible and closes[0] == 1, "any controller's B closes it")


func test_the_page_prompts_name_the_drivers_keys() -> void:
	var page := _page()
	var key_caps: Array[String] = []
	page.open(null)
	for g in _glyphs(page):
		if g.style == UiGlyph.Style.KEY:
			key_caps.append(g.text)
	check("Enter" in key_caps and "Esc" in key_caps, "anyone: pad buttons plus Enter / Esc (%s)" % str(key_caps))
	page.hide()
	_human("pad:a")
	page.open(PlayerManager.get_slot(0))
	var pads: Array[String] = []
	for g in _glyphs(page):
		check(g.style != UiGlyph.Style.KEY, "a controller player sees no key caps")
		if g.style == UiGlyph.Style.PAD:
			pads.append(g.text)
	check("A" in pads and "B" in pads, "but the A and B buttons")


func _glyphs(node: Node) -> Array[UiGlyph]:
	var out: Array[UiGlyph] = []
	for c in node.get_children():
		if c is UiGlyph:
			out.append(c as UiGlyph)
		out.append_array(_glyphs(c))
	return out


# --- Credits page ------------------------------------------------------------------------------

func test_credits_markdown_is_rendered_as_simple_lines() -> void:
	var md := "# Credits\n\nIntro line one\ncontinues here.\n\n## Audio\n\n- **Kenney** – [Interface Sounds](https://kenney.nl/a) (CC0)\n"
	md += "* `plain` bullet\n\n| Asset | Author | Licence |\n|---|---|---|\n| Click | Kenney | CC0 |\n\n---\n\n> small print\n> continues\n>\n> second paragraph\n"
	var lines := CreditsPage.parse(md)
	var kinds: Array[int] = []
	for l in lines:
		kinds.append(int(l["kind"]))
	var L := CreditsPage.Line
	check_eq(kinds, [L.TITLE, L.GAP, L.TEXT, L.GAP, L.HEADING, L.GAP, L.BULLET, L.BULLET, L.GAP,
			L.SUBHEADING, L.TEXT, L.GAP, L.RULE, L.GAP, L.QUOTE, L.QUOTE] as Array[int], "headings, bullets, a table, a rule, quotes")
	check_eq(lines[0]["text"], "Credits", "title")
	check_eq(lines[2]["text"], "Intro line one continues here.", "consecutive lines join into a paragraph")
	check_eq(lines[6]["text"], "Kenney – Interface Sounds (https://kenney.nl/a) (CC0)", "bold / link marks are dropped")
	check_eq(lines[7]["text"], "plain bullet", "code marks too")
	check_eq(lines[9]["text"], "Asset  ·  Author  ·  Licence", "the table header")
	check_eq(lines[10]["text"], "Click  ·  Kenney  ·  CC0", "a table row (the |---| row is gone)")
	check_eq(lines[14]["text"], "small print continues", "a quote paragraph")
	check_eq(lines[15]["text"], "second paragraph", "a blank quote line starts a new one")
	check_eq(CreditsPage.parse("").size(), 0, "empty text, no lines")
	check_eq(CreditsPage.parse("\n\n  \n").size(), 0, "no stray gaps")


func test_credits_fall_back_to_the_built_in_text() -> void:
	var md := CreditsPage.page_markdown("res://no_such_credits_file.md")
	check("SmartOnion – a fan-made parody game" in md, "the built-in line")
	check("Made with Godot Engine" in md, "made with Godot")
	check("godotengine.org" in md, "the Godot site")
	check("Permission is hereby granted" in md, "and the engine's MIT licence text")
	check("Godot Engine contributors" in md, "with its copyright line")
	check("Third-party components in Godot Engine" in md, "the engine's third-party notices follow")
	check("FreeType" in md and "Expat" in md, "with the bundled components and their licence texts")
	var page := _add(CreditsPage.create(0.4, "res://no_such_credits_file.md")) as CreditsPage
	var texts: Array[String] = []
	for l in page.lines:
		texts.append(String(l["text"]))
	check("SmartOnion – a fan-made parody game" in texts, "the page shows the built-in line")
	check("Godot Engine" in texts, "and a Godot Engine heading")
	# The credits file's text wins when there is one (and a lone "# Credits" title is not repeated).
	var f := FileAccess.open(_tmp_path, FileAccess.WRITE)
	f.store_string("# Credits\n\n## Sounds\n\n- Some Pack by Someone\n")
	f.close()
	var own := _add(CreditsPage.create(0.4, _tmp_path)) as CreditsPage
	var own_texts: Array[String] = []
	for l in own.lines:
		own_texts.append(String(l["text"]))
	check("Some Pack by Someone" in own_texts, "the file's bullet is listed")
	check("SmartOnion – a fan-made parody game" not in own_texts, "no built-in text next to a real file")
	check("Credits" not in own_texts, "the page title is not repeated")
	check("Godot Engine" in own_texts, "the Godot notice is always there")
	check(own.content.get_child_count() > 3, "rendered as nodes")


func test_the_real_credits_file_is_readable_when_present() -> void:
	if not FileAccess.file_exists(CreditsPage.CREDITS_PATH):
		return  # (the audio package writes it)
	check(CreditsPage.read_markdown().strip_edges() != "", "CREDITS.md has text")
	check(CreditsPage.parse(CreditsPage.read_markdown()).size() > 0, "and it parses into lines")


func test_credits_scroll_with_the_stick() -> void:
	_async = true
	var a := _human()
	var md := "# Long\n\n"
	for i in 60:
		md += "Line number %d of the credits.\n\n" % i
	var page := _add(CreditsPage.create(0.4, _tmp_path)) as CreditsPage
	page.set_markdown(md)
	page.show()
	await tree.process_frame
	await tree.process_frame
	check(page.max_scroll() > 200, "the text is longer than the view (%d)" % page.max_scroll())
	page.open(PlayerManager.get_slot(0))
	UiFakes.step(page)
	a.move = Vector2.DOWN
	for i in 30:
		UiFakes.step(page, 1.0 / 60.0)
	var down := page.scroll.scroll_vertical
	check(down > 100, "holding down scrolls (%d)" % down)
	a.move = Vector2.UP
	for i in 10:
		UiFakes.step(page, 1.0 / 60.0)
	check(page.scroll.scroll_vertical < down, "holding up scrolls back")
	a.move = Vector2.DOWN
	for i in 600:
		UiFakes.step(page, 1.0 / 60.0)
	check_eq(page.scroll.scroll_vertical, page.max_scroll(), "it stops at the end")
	a.move = Vector2.ZERO
	UiFakes.tap(page, a, PlayerInput.Pad.B)
	check(not page.visible, "B closes the credits")
	finished.emit()


# --- Menus -------------------------------------------------------------------------------------

func test_the_main_menu_has_four_entries() -> void:
	var menu := _add(MainMenu.create()) as MainMenu
	var texts: Array[String] = []
	for b in menu.buttons:
		texts.append(b.text)
	check_eq(texts, ["Play", "Settings", "Credits", "Quit"] as Array[String], "Play / Settings / Credits / Quit")
	check(menu.buttons[0] == menu.play_button and menu.buttons[3] == menu.quit_button, "named buttons")
	check(menu.settings_button == menu.buttons[1] and menu.credits_button == menu.buttons[2], "Settings, Credits")
	for i in menu.buttons.size():
		var b := menu.buttons[i]
		check(b.get_node(b.focus_neighbor_bottom) == menu.buttons[(i + 1) % 4], "focus down from %s wraps" % b.text)
		check(b.get_node(b.focus_neighbor_top) == menu.buttons[(i + 3) % 4], "focus up from %s wraps" % b.text)


func test_the_main_menu_opens_and_closes_its_pages() -> void:
	var menu := _add(MainMenu.create()) as MainMenu
	var plays: Array[int] = [0]
	var quits: Array[int] = [0]
	menu.play_pressed.connect(func() -> void: plays[0] += 1)
	menu.quit_pressed.connect(func() -> void: quits[0] += 1)
	check(not menu.is_page_open(), "no page at first")
	menu.settings_button.pressed.emit()
	check(menu.is_page_open() and menu.settings_page.visible, "Settings opens the page")
	check(not menu.title_label.is_visible_in_tree(), "the title steps aside")
	menu._pads.injected.append(JOY_BUTTON_A)
	menu._process(0.016)
	check_eq(plays[0], 0, "the menu does not react to a controller while the page is up")
	menu.settings_page.close()
	check(not menu.is_page_open() and menu.title_label.is_visible_in_tree(), "closing brings the menu back")
	menu.credits_button.pressed.emit()
	check(menu.credits_page != null and menu.credits_page.visible, "Credits opens its page")
	check(menu.settings_page == null or not menu.settings_page.visible, "one page at a time")
	menu.open_settings()
	check(not menu.settings_page.visible, "(a second page does not open over the first)")
	menu.credits_page.close()
	menu.credits_button.grab_focus()
	menu.activate_focused()
	check(menu.credits_page.visible, "a controller's A on the focused Credits button opens it")
	menu.credits_page.close()
	menu.settings_button.grab_focus()
	menu.activate_focused()
	check(menu.settings_page.visible, "and on Settings")
	menu.settings_page.close()
	check_eq(plays[0] + quits[0], 0, "neither Play nor Quit was pressed")


func test_the_pause_menu_has_settings_between_resume_and_quit() -> void:
	var menu := _add(PauseMenu.create()) as PauseMenu
	var resumes: Array[int] = [0]
	menu.resume_requested.connect(func() -> void: resumes[0] += 1)
	var a := _human()
	menu.open(PlayerManager.get_slot(0))
	check_eq(menu.entries, [PauseMenu.Item.RESUME, PauseMenu.Item.SETTINGS, PauseMenu.Item.QUIT] as Array[int], "order")
	check_eq(menu.button_for(PauseMenu.Item.SETTINGS).text, "Settings", "the button says Settings")
	UiFakes.step(menu)
	UiFakes.nudge(menu, a, Vector2.DOWN)
	check_eq(menu.selected, PauseMenu.Item.SETTINGS, "highlighted")
	UiFakes.tap(menu, a, PlayerInput.Pad.A)
	check(menu.is_settings_open(), "A opens the page")
	check(menu.visible, "the menu stays up (the game stays paused)")
	check(menu.settings_page.driver_slot() == PlayerManager.get_slot(0), "driven by the player who paused")
	# While the page is up the menu waits: START does not resume.
	UiFakes.tap(menu, a, PlayerInput.Pad.START)
	check_eq(resumes[0], 0, "START does not resume under the page")
	check(menu.is_settings_open(), "still in the settings")
	UiFakes.step(menu.settings_page)
	UiFakes.tap(menu.settings_page, a, PlayerInput.Pad.B)
	check(not menu.is_settings_open() and menu.visible, "B closes the page, not the pause menu")
	UiFakes.step(menu)
	check_eq(resumes[0], 0, "the B that closed the page did not resume")
	check_eq(menu.selected, PauseMenu.Item.SETTINGS, "the highlight is where it was")
	UiFakes.tap(menu, a, PlayerInput.Pad.B)
	check_eq(resumes[0], 1, "a new B resumes as before")


func test_clicking_settings_in_the_pause_menu_and_reopening_it() -> void:
	var menu := _add(PauseMenu.create()) as PauseMenu
	menu.open(null)
	menu.button_for(PauseMenu.Item.SETTINGS).pressed.emit()
	check(menu.is_settings_open(), "a click opens it")
	check(menu.settings_page.driver_slot() == null, "without a pausing player anyone drives it")
	menu.hide()  # (Main resumes while the page is up)
	menu.open(null)
	check(not menu.is_settings_open(), "the menu opens again on its entries")
	check(menu.button_for(PauseMenu.Item.RESUME).is_visible_in_tree(), "with the list showing")
