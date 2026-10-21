extends TestCase
## RPT-STEAM: the Steam Remote Play Together backend, driven by a fake "Steam" singleton (no Steam client and
## no GodotSteam plug-in involved), and the Null behaviour of the RemotePlayBackend interface.

## Catches push_warning() messages (the test runner's own logger only keeps errors).
class WarningCatcher extends Logger:
	var warnings: Array[String] = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			warnings.append(rationale if rationale != "" else code)

const BACKEND_PATH := "res://core/platform/steam_remote_play_backend.gd"

var _fake: FakeSteamSingleton
var _catcher: WarningCatcher
var _saved_app_id: Variant
## Joypad id -> the Input.get_joy_info() dictionary of that pad.
var _pads: Dictionary = {}
var _provider_calls := 0
var _provided: Object
## What the backend announced, in order: "connected 7 Alice", "disconnected 7", "overlay true".
var _events: Array[String] = []


func before_each() -> void:
	_fake = FakeSteamSingleton.new()
	_catcher = WarningCatcher.new()
	OS.add_logger(_catcher)
	_saved_app_id = ProjectSettings.get_setting(SteamRemotePlayBackend.APP_ID_SETTING, null)
	_pads = {}
	_events = []
	_provider_calls = 0


func after_each() -> void:
	OS.remove_logger(_catcher)
	ProjectSettings.set_setting(SteamRemotePlayBackend.APP_ID_SETTING, _saved_app_id)


# --- Helpers ----------------------------------------------------------------------------------

## try_create() as a real (non-automated) session whose Steam singleton is [param steam].
func _try_create_with(steam: Object) -> SteamRemotePlayBackend:
	_provided = steam
	return SteamRemotePlayBackend.try_create(_provide, _not_automated)


func _provide() -> Object:
	_provider_calls += 1
	return _provided


func _not_automated() -> bool:
	return false


func _automated() -> bool:
	return true


## A working backend on the fake, with fake pads and its announcements recorded in _events.
func _backend() -> SteamRemotePlayBackend:
	var backend := _try_create_with(_fake)
	check(backend != null, "the fake Steam initialises")
	if backend == null:
		return SteamRemotePlayBackend.new()
	backend.joy_info_source = func(device: int) -> Dictionary: return _pads.get(device, {})
	backend.guest_connected.connect(func(session_id: int, name: String) -> void: _events.append("connected %d %s" % [session_id, name]))
	backend.guest_disconnected.connect(func(session_id: int) -> void: _events.append("disconnected %d" % session_id))
	backend.overlay_toggled.connect(func(active: bool) -> void: _events.append("overlay %s" % active))
	return backend


func _steam_pad(handle: int) -> Dictionary:
	return {"raw_name": "Steam Virtual Gamepad", "steam_input_index": str(handle)}


# --- Creation -----------------------------------------------------------------------------------

func test_there_is_no_backend_without_the_steam_singleton() -> void:
	check(_try_create_with(null) == null, "no singleton -> null")
	check_eq(_provider_calls, 1, "the singleton was looked up")
	check(_catcher.warnings.is_empty(), "a missing plug-in is not worth a warning")


func test_an_automated_run_never_touches_steam() -> void:
	check(Settings.is_automated_run(), "the test runner is an automated run")
	_provided = _fake
	check(SteamRemotePlayBackend.try_create(_provide) == null, "an automated run gets no Steam backend")
	check(SteamRemotePlayBackend.try_create(_provide, _automated) == null, "an explicitly automated run gets none either")
	check_eq(_provider_calls, 0, "the singleton is not even looked up")
	check(_fake.calls.is_empty(), "nothing was called on Steam: %s" % [_fake.calls])
	check(_catcher.warnings.is_empty(), "and nothing was warned about")


func test_the_default_lookup_in_an_automated_run_finds_nothing() -> void:
	# No seams: in the tests this is the real engine path (and a real plug-in, if one is installed, stays untouched).
	check(SteamRemotePlayBackend.try_create() == null, "the plain try_create() of an automated run")


func test_a_failed_init_gives_no_backend_and_one_warning() -> void:
	_fake.init_status = 2
	_fake.init_verbal = "Steam is not running"
	check(_try_create_with(_fake) == null, "init status 2 -> null")
	check_eq(_catcher.warnings.size(), 1, "exactly one warning")
	if not _catcher.warnings.is_empty():
		check("Steam is not running" in _catcher.warnings[0] and "status 2" in _catcher.warnings[0],
				"the warning says why: %s" % _catcher.warnings[0])
	check_eq(_fake.count("steamInitEx"), 1, "init was tried once")
	check(_fake.calls_while_uninitialised.is_empty(), "no Remote Play / Input call on a Steam that never started: %s" % [_fake.calls_while_uninitialised])
	check_eq(_fake.count("inputInit"), 0, "Steam Input was not started")


func test_a_garbage_init_answer_counts_as_a_failure() -> void:
	_fake.init_returns_garbage = true
	check(_try_create_with(_fake) == null, "a non-dictionary answer -> null")
	check_eq(_catcher.warnings.size(), 1, "exactly one warning")


func test_a_working_init_gives_an_available_backend() -> void:
	var backend := _backend()
	check(backend.is_available(), "available")
	check(backend is RemotePlayBackend, "it is a RemotePlayBackend")
	check(_catcher.warnings.is_empty(), "no warnings")
	check_eq(_fake.last_init_app_id, SteamRemotePlayBackend.configured_app_id(), "initialised with the configured app id")
	check(not _fake.last_init_embed, "the backend pumps the callbacks itself")
	check_eq(_fake.count("steamInitEx"), 1, "one init")
	check_eq(_fake.count("inputInit"), 1, "Steam Input started once")
	check(_fake.calls_while_uninitialised.is_empty(), "every gated call came after the init")


func test_the_app_id_comes_from_the_project_setting() -> void:
	ProjectSettings.set_setting(SteamRemotePlayBackend.APP_ID_SETTING, 1234567)
	check_eq(SteamRemotePlayBackend.configured_app_id(), 1234567, "a set id is used")
	_backend()
	check_eq(_fake.last_init_app_id, 1234567, "steamInitEx got it")


func test_the_app_id_defaults_to_the_test_app_480() -> void:
	check_eq(SteamRemotePlayBackend.DEFAULT_APP_ID, 480, "the default is Spacewar")
	ProjectSettings.set_setting(SteamRemotePlayBackend.APP_ID_SETTING, null)
	check_eq(SteamRemotePlayBackend.configured_app_id(), 480, "no setting -> 480")
	for bad: Variant in [0, -5, "abc", 1.5, true, null, ""]:
		ProjectSettings.set_setting(SteamRemotePlayBackend.APP_ID_SETTING, bad)
		check_eq(SteamRemotePlayBackend.configured_app_id(), 480, "%s is not an app id -> 480" % [bad])
	ProjectSettings.set_setting(SteamRemotePlayBackend.APP_ID_SETTING, "77")
	check_eq(SteamRemotePlayBackend.configured_app_id(), 77, "a numeric string is accepted")


func test_project_godot_declares_the_app_id_setting() -> void:
	var cfg := ConfigFile.new()
	check_eq(cfg.load("res://project.godot"), OK, "project.godot loads")
	check(cfg.has_section_key("smartonion", "steam/app_id"), "the setting is declared in project.godot")
	check_eq(int(cfg.get_value("smartonion", "steam/app_id", 0)), 480, "and defaults to 480")


func test_an_already_initialised_steam_is_not_initialised_twice() -> void:
	# The plug-in's own auto-init is on: a second steamInitEx would log an engine error.
	_fake.initialized = true
	_fake.current_app_id = 480
	var backend := _try_create_with(_fake)
	check(backend != null and backend.is_available(), "usable")
	check_eq(_fake.count("steamInitEx"), 0, "no second init")
	check_eq(_fake.count("inputInit"), 1, "but Steam Input is started")


func test_without_steam_input_no_pad_is_mapped_and_one_warning_is_logged() -> void:
	_fake.input_init_ok = false
	_fake.handle_sessions[111] = 4
	var backend := _backend()
	_pads[0] = _steam_pad(111)
	check(backend.is_available(), "still available")
	check_eq(_catcher.warnings.size(), 1, "one warning about Steam Input")
	check_eq(backend.session_of_device(0), 0, "no mapping without Steam Input")
	check_eq(_fake.count("getRemotePlaySessionID"), 0, "and no call")


# --- Sessions and names ----------------------------------------------------------------------------

func test_guests_connecting_and_leaving_are_announced_with_their_names() -> void:
	var backend := _backend()
	_fake.connect_guest(7, 76561198000000001, "Alice")
	check_eq(_events, ["connected 7 Alice"] as Array[String], "the persona name rides on guest_connected")
	check_eq(backend.session_ids(), [7] as Array[int], "the session is listed")
	_fake.connect_guest(3, 76561198000000002, "Bob")
	check_eq(backend.session_ids(), [3, 7] as Array[int], "sorted")
	_fake.disconnect_guest(7)
	check_eq(_events, ["connected 7 Alice", "connected 3 Bob", "disconnected 7"] as Array[String], "the disconnect is announced")
	check_eq(backend.session_ids(), [3] as Array[int], "gone from the list")


func test_a_session_is_announced_once() -> void:
	var backend := _backend()
	_fake.connect_guest(7, 5, "Alice")
	_fake.remote_play_session_connected.emit(7)
	_fake.remote_play_session_disconnected.emit(99)  # never connected
	backend.poll()
	backend.poll()
	check_eq(_events, ["connected 7 Alice"] as Array[String], "no duplicate, nothing for the unknown session")
	_fake.disconnect_guest(7)
	_fake.remote_play_session_disconnected.emit(7)
	check_eq(_events.count("disconnected 7"), 1, "a disconnect twice is one announcement")


func test_the_first_poll_announces_guests_that_were_already_streaming() -> void:
	_fake.sessions = [5, 9] as Array[int]
	_fake.steam_ids = {5: 11, 9: 12}
	_fake.persona_names = {11: "Carol", 12: "Dave"}
	var backend := _backend()
	check(_events.is_empty(), "nothing before the first poll (nobody listens yet)")
	backend.poll()
	check_eq(_events, ["connected 5 Carol", "connected 9 Dave"] as Array[String], "the sessions of the list")
	backend.poll()
	check_eq(_events.size(), 2, "only once")


func test_the_session_list_is_reconciled_every_so_many_polls() -> void:
	var backend := _backend()
	backend.reconcile_every = 3
	backend.poll()  # the first poll reads the list (empty)
	_fake.sessions = [4] as Array[int]  # a session the callbacks never told about
	backend.poll()
	check(_events.is_empty(), "not yet")
	backend.poll()
	check_eq(_events.size(), 1, "the missed session is found on the third poll")
	_fake.sessions = [] as Array[int]  # and one that vanished without a callback
	backend.poll()
	backend.poll()
	backend.poll()
	check_eq(_events.back(), "disconnected 4", "the vanished one is dropped")
	check(backend.session_ids().is_empty(), "no sessions left")


func test_poll_runs_the_callbacks_every_frame() -> void:
	var backend := _backend()
	for i in 5:
		backend.poll()
	check_eq(_fake.count("run_callbacks"), 5, "one run_callbacks per poll")


func test_a_guest_without_a_steam_account_is_called_guest_n() -> void:
	var backend := _backend()
	_fake.connect_guest(7, 0, "", 2)
	check_eq(backend.guest_name(7), "Guest 2", "Steam's guest id")
	check_eq(_events[0], "connected 7 Guest 2", "also on the signal")
	check(_fake.persona_requests.is_empty(), "no persona lookup for steam id 0 (the plug-in logs an error for it)")
	_fake.connect_guest(8, 0, "", 4000000)
	check_eq(backend.guest_name(8), "Guest 1", "a huge guest id falls back to the lowest free number")
	_fake.connect_guest(9, 0, "", 0)
	check_eq(backend.guest_name(9), "Guest 3", "no guest id: the lowest number not in use (1 and 2 are taken)")
	check_eq(backend.guest_name(8), "Guest 1", "the number is stable")
	_fake.disconnect_guest(8)
	_fake.connect_guest(10, 0, "", 0)
	check_eq(backend.guest_name(10), "Guest 1", "a freed number is used again")


func test_a_persona_name_that_is_still_loading_falls_back_and_then_arrives() -> void:
	var backend := _backend()
	_fake.connect_guest(7, 55, "", 3)
	check_eq(backend.guest_name(7), "Guest 3", "Steam has not loaded the name yet")
	_fake.persona_names[55] = "  Erin  "
	check_eq(backend.guest_name(7), "Erin", "the real name once it is there (trimmed)")
	check_eq(backend.guest_name(0), "", "no name for session 0")
	check_eq(backend.guest_name(-4), "", "nor for a bogus id")


func test_a_guest_who_left_keeps_the_name_and_costs_no_guest_number() -> void:
	var backend := _backend()
	_fake.connect_guest(4, 55, "Mira")
	check_eq(backend.guest_name(4), "Mira", "resolved while she is here")
	_fake.disconnect_guest(4)
	backend.poll()
	check(backend.session_ids().is_empty(), "the session is gone")
	var calls_before := _fake.calls.size()
	check_eq(backend.guest_name(4), "Mira", "still Mira after she left")
	check_eq(_fake.calls.size(), calls_before, "answered from memory: no Steam call for an ended session")
	check(not backend._guest_numbers.has(4), "no Guest N number is (re-)allocated for the dead session")
	# A guest without a Steam account: nothing to remember but no number to leak either.
	_fake.connect_guest(5, 0, "", 0)
	check_eq(backend.guest_name(5), "Guest 1", "numbered while here")
	_fake.disconnect_guest(5)
	check_eq(backend.guest_name(5), "", "the backend knows no name of the departed link guest")
	check(not backend._guest_numbers.has(5), "and does not number the dead session again")
	_fake.connect_guest(6, 0, "", 0)
	check_eq(backend.guest_name(6), "Guest 1", "the next link guest gets the freed number, not 2")
	check_eq(backend.guest_name(77), "", "an id Steam never listed has no name (and no number)")
	check(not backend._guest_numbers.has(77), "")


func test_the_device_name_of_a_session_is_never_used_as_the_guests_name() -> void:
	var backend := _backend()
	_fake.connect_guest(7, 55, "Frank")
	backend.guest_name(7)
	check_eq(_fake.count("getSessionClientName"), 0, "getSessionClientName is a device name like Pixel 8")


# --- Pad -> session -----------------------------------------------------------------------------------

func test_a_pad_is_mapped_to_its_remote_session() -> void:
	var backend := _backend()
	_fake.handle_sessions = {111: 4, 222: 0}
	_pads = {0: {"raw_name": "Xbox"}, 1: _steam_pad(111), 2: _steam_pad(222), 3: {}}
	check_eq(backend.session_of_device(1), 4, "a Steam virtual pad of a guest -> its session")
	check(backend.is_remote_device(1), "remote")
	check_eq(backend.session_of_device(0), 0, "a pad without steam_input_index is local")
	check(not backend.is_remote_device(0), "not remote")
	check_eq(backend.session_of_device(2), 0, "a Steam Input pad of the host (session 0) is local")
	check_eq(backend.session_of_device(3), 0, "an unconnected id is local")
	check_eq(backend.session_of_device(-1), 0, "a negative id (the keyboard) is local")
	check_eq(backend.session_of_device(15), 0, "an unknown id is local")
	check_eq(_fake.count("getRemotePlaySessionID"), 2, "Steam was asked for the two Steam Input handles only")


func test_a_pad_handle_given_as_a_number_works_too() -> void:
	var backend := _backend()
	_fake.handle_sessions = {111: 4}
	_pads = {0: {"steam_input_index": 111}, 1: {"steam_input_index": "0"}}
	check_eq(backend.session_of_device(0), 4, "an int handle")
	check_eq(backend.session_of_device(1), 0, "handle 0 = no Steam Input pad")


func test_a_mapped_session_that_steam_did_not_announce_yet_is_registered() -> void:
	var backend := _backend()
	_fake.handle_sessions = {111: 4}
	_fake.steam_ids = {4: 66}
	_fake.persona_names = {66: "Gina"}
	_pads = {0: _steam_pad(111)}
	check_eq(backend.session_of_device(0), 4, "mapped")
	check_eq(_events, ["connected 4 Gina"] as Array[String], "and announced once")
	_fake.remote_play_session_connected.emit(4)
	check_eq(_events.size(), 1, "the late callback adds nothing")


func test_the_mapping_is_cached_by_handle() -> void:
	var backend := _backend()
	_fake.handle_sessions = {111: 4, 222: 0}
	_fake.sessions = [4] as Array[int]
	_pads = {0: _steam_pad(111), 1: _steam_pad(222)}
	for i in 3:
		check_eq(backend.session_of_device(0), 4, "guest pad")
		check_eq(backend.session_of_device(1), 0, "host pad")
	check_eq(_fake.count("getRemotePlaySessionID"), 2, "one question per pad within a frame")
	backend.poll()
	check_eq(backend.session_of_device(0), 4, "guest pad, next frame")
	check_eq(backend.session_of_device(1), 0, "host pad, next frame")
	check_eq(_fake.count("getRemotePlaySessionID"), 3, "a guest's answer is kept; a local pad is asked again each frame")


func test_a_local_pad_that_turns_out_to_be_a_guests_is_found_on_the_next_frame() -> void:
	var backend := _backend()
	_pads = {0: _steam_pad(111)}
	check_eq(backend.session_of_device(0), 0, "Steam has not associated the pad with a session yet")
	_fake.handle_sessions[111] = 4
	_fake.sessions = [4] as Array[int]
	check_eq(backend.session_of_device(0), 0, "within the same frame the answer stays")
	backend.poll()
	check_eq(backend.session_of_device(0), 4, "the next frame finds the session")


func test_a_reused_joypad_id_does_not_inherit_the_old_pads_session() -> void:
	var backend := _backend()
	_fake.handle_sessions = {111: 4, 333: 0, 444: 6}
	_pads = {0: _steam_pad(111)}
	check_eq(backend.session_of_device(0), 4, "guest 4's pad on id 0")
	_pads = {0: _steam_pad(333)}  # id 0 reused by another pad (the host's)
	check_eq(backend.session_of_device(0), 0, "a different handle on the same id is asked afresh")
	_pads = {0: _steam_pad(444)}  # ... and by yet another guest, while session 4 still lives
	check_eq(backend.session_of_device(0), 6, "not 4")


func test_a_guest_leaving_forgets_its_pads() -> void:
	var backend := _backend()
	_fake.handle_sessions = {111: 4}
	_pads = {0: _steam_pad(111)}
	check_eq(backend.session_of_device(0), 4, "mapped")
	_fake.handle_sessions.erase(111)  # the session is over
	check_eq(backend.session_of_device(0), 4, "cached while the session lives")
	_fake.disconnect_guest(4)
	check_eq(backend.session_of_device(0), 0, "after the disconnect the pad is asked afresh (and is local)")
	check(not backend.is_remote_device(0), "not remote any more")


# --- Overlay, invite --------------------------------------------------------------------------------------

func test_the_overlay_state_is_forwarded() -> void:
	var backend := _backend()
	check(backend.is_available(), "available")
	_fake.overlay_toggled.emit(true, true, 480)
	_fake.overlay_toggled.emit(false, false, 480)
	check_eq(_events, ["overlay true", "overlay false"] as Array[String], "active flag only")


func test_the_invite_panel_opens_through_steam() -> void:
	var backend := _backend()
	check(backend.can_invite(), "can invite")
	backend.show_invite()
	check_eq(_fake.count("showRemotePlayTogetherUI"), 1, "the Remote Play Together panel was requested")
	check(_catcher.warnings.is_empty(), "no warning")


func test_a_refused_invite_panel_warns_once() -> void:
	_fake.invite_ok = false
	var backend := _backend()
	backend.show_invite()
	backend.show_invite()
	check_eq(_fake.count("showRemotePlayTogetherUI"), 2, "asked each time")
	check_eq(_catcher.warnings.size(), 1, "but the warning comes once")


# --- Interface contract ------------------------------------------------------------------------------------

func test_the_base_class_is_the_null_backend() -> void:
	var null_backend := RemotePlayBackend.new()
	check(not null_backend.is_available(), "not available")
	null_backend.poll()
	check_eq(null_backend.session_of_device(0), 0, "every pad is local")
	check(not null_backend.is_remote_device(0), "no remote device")
	check_eq(null_backend.guest_name(1), "", "no names")
	check(null_backend.session_ids().is_empty(), "no sessions")
	check(not null_backend.can_invite(), "no invite")
	null_backend.show_invite()


func test_the_direct_input_api_and_the_device_name_are_never_used() -> void:
	var backend := _backend()
	_fake.handle_sessions = {111: 4}
	_fake.sessions = [4] as Array[int]
	_fake.steam_ids = {4: 66}
	_fake.persona_names = {66: "Hank"}
	_pads = {0: _steam_pad(111)}
	for i in 130:
		backend.poll()
		backend.session_of_device(0)
		backend.is_remote_device(0)
		backend.guest_name(4)
		backend.session_ids()
	backend.show_invite()
	_fake.disconnect_guest(4)
	backend.poll()
	check(_fake.forbidden_calls.is_empty(), "forbidden calls: %s" % [_fake.forbidden_calls])
	check(_fake.calls_while_uninitialised.is_empty(), "no gated call before init: %s" % [_fake.calls_while_uninitialised])


func test_the_script_never_names_the_steam_singleton() -> void:
	# test_all_scripts_compile only notices this on a machine WITHOUT the plug-in; with the plug-in installed an
	# identifier "Steam" would compile, so look for it in the code (comments and strings removed).
	var text := FileAccess.get_file_as_string(BACKEND_PATH)
	check(text != "", "the script is readable")
	var strings := RegEx.create_from_string("&?\"[^\"\\n]*\"")
	var identifier := RegEx.create_from_string("(^|[^A-Za-z0-9_\\.])Steam\\b")
	for line in text.split("\n"):
		var code := strings.sub(line, "\"\"", true)
		var hash_at := code.find("#")
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		check(identifier.search(code) == null, "names the Steam identifier: %s" % line.strip_edges())
