extends Node
## Autoload "Settings" (M7a): the player's options – audio volumes, window / VSync / FPS cap, screen shake,
## damage numbers, FPS counter. The values and the file format live in [GameSettings] (core/game_settings.gd);
## this node loads them at startup, saves on every change and applies them:
##   - volumes -> the audio buses Master / Music / SFX / UI by name (a bus that does not exist is ignored,
##     0 % mutes the bus);
##   - window mode / VSync / max FPS -> DisplayServer / Engine, only in a real player session;
##   - screen shake and damage numbers are read by CameraRig.shake and Vfx.damage_number
##     ([method screen_shake_mult], [method damage_numbers_enabled]); the FPS counter is an [FpsOverlay].
##
## Smoke, demo, --view / --screenshot runs, headless runs and the unit tests (a custom main-loop script) are
## "automated": there the settings are the defaults, user://settings.cfg is neither read nor written and the
## window is left alone ([method is_automated_run]). Tests inject their own [member GameSettings.path].
## Nothing here draws from RunState.rng or changes a gameplay number.
## See docs/ARCHITECTURE.md.

## A value changed (also once per key a reset changed).
signal changed(key: StringName)

## Values, defaults and file. Replace [member GameSettings.path] to redirect the file.
var data := GameSettings.new()
## Changes are written to the file (and it was read at startup).
var persist := false
## Window mode / VSync / FPS cap are applied to DisplayServer / Engine.
var video_enabled := false
## The Error of the last read or write of the file (OK = fine or untouched).
var file_error: Error = OK
var fps_overlay: FpsOverlay


## True when nothing of the player's setup may be touched: headless, a custom main loop (the test runner), or
## a launch with --smoke / --demo / --view / --screenshot (LaunchOptions.is_automated).
static func is_automated_run() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	var loop := Engine.get_main_loop()
	if loop != null and loop.get_script() != null:
		return true
	return LaunchOptions.parse(OS.get_cmdline_user_args()).is_automated()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var live := not is_automated_run()
	persist = live
	video_enabled = live
	if live:
		file_error = data.load_file()
		if file_error != OK:
			push_warning("Settings: could not read %s (%s), using the defaults" % [data.path, error_string(file_error)])
		apply_all()
	_sync_fps_overlay()


# --- Reads -------------------------------------------------------------------------------

func get_value(key: StringName) -> Variant:
	return data.get_value(key)


## 0 (Off) / 0.5 (Low) / 1 (Full): CameraRig.shake multiplies its trauma by it.
func screen_shake_mult() -> float:
	return data.screen_shake_mult()


## False when Vfx.damage_number should draw nothing.
func damage_numbers_enabled() -> bool:
	return data.damage_numbers_enabled()


func show_fps_enabled() -> bool:
	return data.show_fps_enabled()


# --- Changes -----------------------------------------------------------------------------

## Sets [param key] to the nearest legal [param value], applies and saves it. No-op when unchanged.
func set_value(key: StringName, value: Variant) -> void:
	if data.set_value(key, value):
		_after_change([key])


## Moves [param key] one step ([param direction] < 0 left, > 0 right).
func step_value(key: StringName, direction: int) -> void:
	if data.step_value(key, direction):
		_after_change([key])


func reset_to_defaults() -> void:
	var before := data.values.duplicate()
	if not data.reset_to_defaults():
		return
	var keys: Array[StringName] = []
	for key: StringName in data.values:
		if data.values[key] != before[key]:
			keys.append(key)
	_after_change(keys)


func _after_change(keys: Array[StringName]) -> void:
	for key in keys:
		_apply_key(key)
	save()
	for key in keys:
		changed.emit(key)


## Writes the file ([member persist] only). Returns the Error (OK also when nothing is written).
func save() -> Error:
	if not persist:
		return OK
	file_error = data.save_file()
	if file_error != OK:
		push_warning("Settings: could not write %s (%s)" % [data.path, error_string(file_error)])
	return file_error


# --- Applying ----------------------------------------------------------------------------

## Pushes every value to the engine (audio always, video only when [member video_enabled]).
func apply_all() -> void:
	apply_audio()
	apply_video()
	_sync_fps_overlay()


func _apply_key(key: StringName) -> void:
	if GameSettings.BUS_NAMES.has(key):
		_apply_bus(key)
	elif key == GameSettings.SHOW_FPS:
		_sync_fps_overlay()
	elif key in [GameSettings.WINDOW_MODE, GameSettings.VSYNC, GameSettings.MAX_FPS]:
		apply_video()


func apply_audio() -> void:
	for key: StringName in GameSettings.BUS_NAMES:
		_apply_bus(key)


## Volume of one bus: 0 % mutes it. A bus the project does not have (yet) is ignored.
func _apply_bus(key: StringName) -> void:
	var bus := AudioServer.get_bus_index(GameSettings.BUS_NAMES[key])
	if bus < 0:
		return
	var percent := data.volume_percent(key)
	AudioServer.set_bus_mute(bus, percent <= 0)
	AudioServer.set_bus_volume_db(bus, GameSettings.volume_to_db(percent))


func apply_video() -> void:
	if not video_enabled:
		return
	var mode := DisplayServer.WINDOW_MODE_WINDOWED
	match data.window_mode():
		GameSettings.WindowMode.BORDERLESS:
			mode = DisplayServer.WINDOW_MODE_FULLSCREEN
		GameSettings.WindowMode.FULLSCREEN:
			mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	var current := DisplayServer.window_get_mode()
	# (A maximized window counts as windowed: do not un-maximize it at startup.)
	if current != mode and not (mode == DisplayServer.WINDOW_MODE_WINDOWED and current == DisplayServer.WINDOW_MODE_MAXIMIZED):
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if data.vsync_enabled() else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = data.max_fps()


func _sync_fps_overlay() -> void:
	var on := data.show_fps_enabled()
	if on and fps_overlay == null:
		fps_overlay = FpsOverlay.create()
		add_child(fps_overlay)
	if fps_overlay != null:
		fps_overlay.visible = on
		fps_overlay.set_process(on)
