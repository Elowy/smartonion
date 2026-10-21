class_name SteamRemotePlayBackend
extends RemotePlayBackend
## Steam Remote Play Together through the GodotSteam GDExtension (singleton "Steam").
##
## Steam streams the host's window to its guests; a guest's gamepad shows up on the host as a Steam Input
## virtual pad that connects and disconnects at any time. This backend only adds what the game cannot see
## by itself: WHICH pad belongs to a guest (session id), the guest's name, whether the invite UI is there, and
## the overlay state. Everything else works with no Steam at all (see [RemotePlayBackend], the Null backend).
##
## The plug-in is optional and gitignored (tools/steam/fetch_godotsteam.sh). So this script never names the
## singleton as an identifier (it would not compile without the plug-in): it holds the object in an untyped
## [member _steam] and goes through [method Object.call]. GodotSteam logs an engine ERROR for every
## RemotePlay / Input call made while Steam is not initialised, so every call is gated behind [method is_available].
## A failure is a [method push_warning], never push_error (the smoke run and the tests fail on errors).
##
## Create it with [method try_create]: it returns null outside a real player session (smoke, demo, headless, the
## tests), without the plug-in, and when Steam cannot be initialised (no Steam client, wrong app id).
## Not used on purpose: GodotSteam's direct keyboard / mouse input of guests (its getInput and createMouseCursor
## calls are broken in 4.23.2), so a guest plays with a pad only.

## Project setting with the Steam app id handed to steamInitEx. 480 is Valve's public test app (Spacewar), for
## development only; the real id comes with the game's Steamworks registration.
const APP_ID_SETTING := "smartonion/steam/app_id"
const DEFAULT_APP_ID := 480
## The name the GodotSteam plug-in registers its singleton under.
const SINGLETON_NAME := &"Steam"
## steamInitEx() status for "initialised".
const INIT_OK := 0
## The session list is compared with the one Steam reported through its callbacks every this many polls
## (a callback may have been missed, or a session may have existed before the game started).
const RECONCILE_EVERY_POLLS := 60
## "Guest N" uses the guest id Steam reports while it is in this range, else the lowest free number.
const MAX_GUEST_NUMBER := 99
const SETTINGS_SCRIPT_PATH := "res://autoload/settings.gd"

## The singleton, an untyped Object (see the class comment). Null when the backend is not usable.
var _steam: Object
## The app id steamInitEx was (or would be) called with.
var _app_id := DEFAULT_APP_ID
## Steam Input was started (inputInit returned true): pads can be mapped to sessions.
var _input_ready := false
## Test seam: a Callable(device) -> Dictionary like Input.get_joy_info; unset, the handle comes from PadSource.
var joy_info_source := Callable()
## The live sessions: session id -> true.
var _sessions: Dictionary[int, bool] = {}
## The "Guest N" number handed to a session whose name Steam could not resolve: session id -> N (live sessions only).
var _guest_numbers: Dictionary[int, int] = {}
## The persona names Steam resolved: session id -> name. Kept after the session ended (session ids are not reused), so
## the ghost seat of a guest who left is still called by name; Steam itself forgets an ended session.
var _names: Dictionary[int, String] = {}
## Input handle -> session id, for handles that belong to a guest (kept while that session lives).
var _session_by_handle: Dictionary[int, int] = {}
## Input handle -> poll generation in which Steam said "local" (0), so one frame asks Steam once per pad.
var _local_in_generation: Dictionary[int, int] = {}
var _generation := 0
var _polls := 0
## The first poll reads the session list (guests may have been connected before the game started).
var _seed_pending := true
## Overrides RECONCILE_EVERY_POLLS (tests).
var reconcile_every := RECONCILE_EVERY_POLLS
var _warned_invite := false


## The Steam backend, or null when it cannot work: automated run, no plug-in, Steam not running / init failed.
## Call it with no arguments. The two optional Callables are test seams: [param singleton_provider] returns the
## object to use as the Steam singleton (null = none; unset = the engine's singleton) and [param automated_provider]
## returns whether this is an automated run (unset = [method Settings.is_automated_run]).
## (No static variables here on purpose: in Godot 4.7.2 a script that extends another script class and reads a static
## variable, or names itself, keeps every project script alive at exit - "resources still in use".)
static func try_create(singleton_provider: Callable = Callable(), automated_provider: Callable = Callable()) -> SteamRemotePlayBackend:
	if _is_automated(automated_provider):
		return null
	var steam := _find_singleton(singleton_provider)
	if steam == null:
		return null
	return create_from(steam, configured_app_id())


## The Steam backend on top of [param steam] (the GodotSteam singleton or a stand-in), or null when
## steamInitEx fails (one warning). Does not look at the run kind: [method try_create] does.
static func create_from(steam: Object, app_id: int = DEFAULT_APP_ID) -> SteamRemotePlayBackend:
	if steam == null:
		return null
	var backend: SteamRemotePlayBackend = new()
	if not backend._start(steam, app_id):
		return null
	return backend


## The app id from the project setting [constant APP_ID_SETTING] (480 when missing or not a positive integer).
static func configured_app_id() -> int:
	var raw: Variant = ProjectSettings.get_setting(APP_ID_SETTING, DEFAULT_APP_ID)
	if typeof(raw) == TYPE_INT and int(raw) > 0:
		return int(raw)
	if typeof(raw) == TYPE_FLOAT and float(raw) >= 1.0 and float(raw) == floorf(float(raw)):
		return int(raw)
	if typeof(raw) == TYPE_STRING and String(raw).is_valid_int() and String(raw).to_int() > 0:
		return String(raw).to_int()
	return DEFAULT_APP_ID


static func _is_automated(automated_provider: Callable) -> bool:
	if automated_provider.is_valid():
		return bool(automated_provider.call())
	# Through the script, not the autoload's name: this may run before the Settings autoload exists.
	var settings_script: GDScript = load(SETTINGS_SCRIPT_PATH)
	return bool(settings_script.call(&"is_automated_run"))


static func _find_singleton(singleton_provider: Callable) -> Object:
	if singleton_provider.is_valid():
		return singleton_provider.call() as Object
	if Engine.has_singleton(SINGLETON_NAME):
		return Engine.get_singleton(SINGLETON_NAME)
	return null


# --- Start ---------------------------------------------------------------------------------

func _start(steam: Object, app_id: int) -> bool:
	_app_id = app_id
	# Already initialised (the plug-in's auto-init is on)? A second steamInitEx would log an engine error.
	var already := false
	if steam.has_method(&"get_current_app_id"):
		already = int(steam.call(&"get_current_app_id")) != 0
	if not already:
		var result: Variant = steam.call(&"steamInitEx", app_id, false)
		var status := -1
		var verbal := ""
		if typeof(result) == TYPE_DICTIONARY:
			var dict: Dictionary = result
			status = int(dict.get("status", -1))
			verbal = str(dict.get("verbal", ""))
		if status != INIT_OK:
			push_warning("SteamRemotePlayBackend: Steam did not start (status %d%s) - Remote Play Together features are off. Is the Steam client running, and does app id %d own the game?" % [
					status, (": " + verbal) if verbal != "" else "", app_id])
			return false
	_steam = steam
	_input_ready = bool(steam.call(&"inputInit", false))
	if not _input_ready:
		push_warning("SteamRemotePlayBackend: Steam Input did not start, guest pads cannot be told from local ones")
	_connect_signal(&"remote_play_session_connected", _on_session_connected)
	_connect_signal(&"remote_play_session_disconnected", _on_session_disconnected)
	_connect_signal(&"overlay_toggled", _on_overlay_toggled)
	return true


func _connect_signal(signal_name: StringName, handler: Callable) -> void:
	if not _steam.has_signal(signal_name):
		push_warning("SteamRemotePlayBackend: the Steam plug-in has no signal %s (version mismatch?)" % signal_name)
		return
	_steam.connect(signal_name, handler)


# --- RemotePlayBackend ---------------------------------------------------------------------

func is_available() -> bool:
	return _steam != null and is_instance_valid(_steam)


func poll() -> void:
	if not is_available():
		return
	_steam.call(&"run_callbacks")
	_generation += 1
	_polls += 1
	if _seed_pending or (reconcile_every > 0 and _polls % reconcile_every == 0):
		_seed_pending = false
		_reconcile_sessions()


func session_of_device(device: int) -> int:
	if not is_available() or not _input_ready or device < 0:
		return 0
	var handle := _input_handle_of(device)
	if handle == 0:
		return 0
	if _session_by_handle.has(handle):
		return _session_by_handle[handle]
	if _local_in_generation.get(handle, -1) == _generation:
		return 0
	var session := int(_steam.call(&"getRemotePlaySessionID", handle))
	if session <= 0:
		_local_in_generation[handle] = _generation
		return 0
	_session_by_handle[handle] = session
	_add_session(session)
	return session


func is_remote_device(device: int) -> bool:
	return session_of_device(device) > 0


func guest_name(session_id: int) -> String:
	if not is_available() or session_id <= 0:
		return ""
	if not _sessions.has(session_id):
		# A guest who has left (or an id Steam never listed): the name we resolved while they were here, else "" – no
		# Steam call (it has nothing for an ended session) and no new "Guest N" number that would never be freed.
		return _names.get(session_id, "")
	var steam_id := int(_steam.call(&"getSessionSteamID", session_id))
	if steam_id > 0:
		# "" while Steam is still loading that user's data; the next call may have it.
		var persona := String(_steam.call(&"getFriendPersonaName", steam_id)).strip_edges()
		if persona != "":
			_names[session_id] = persona
			return persona
	return "Guest %d" % _guest_number(session_id)


func session_ids() -> Array[int]:
	var out: Array[int] = _sessions.keys()
	out.sort()
	return out


func can_invite() -> bool:
	return is_available()


func show_invite() -> void:
	if not is_available():
		return
	if not bool(_steam.call(&"showRemotePlayTogetherUI")) and not _warned_invite:
		_warned_invite = true
		push_warning("SteamRemotePlayBackend: Steam refused to open the Remote Play Together panel (Remote Play Together is not enabled for app id %d)" % _app_id)


# --- Sessions ------------------------------------------------------------------------------

func _add_session(session_id: int) -> void:
	if session_id <= 0 or _sessions.has(session_id):
		return
	_sessions[session_id] = true
	guest_connected.emit(session_id, guest_name(session_id))


func _remove_session(session_id: int) -> void:
	if not _sessions.has(session_id):
		return
	_sessions.erase(session_id)
	_guest_numbers.erase(session_id)
	for handle in _session_by_handle.keys():
		if _session_by_handle[handle] == session_id:
			_session_by_handle.erase(handle)
	guest_disconnected.emit(session_id)


## Makes [member _sessions] equal to what Steam lists now (announcing the differences).
func _reconcile_sessions() -> void:
	var live: Dictionary[int, bool] = {}
	var count := int(_steam.call(&"getSessionCount"))
	for i in count:
		var session := int(_steam.call(&"getSessionID", i))
		if session > 0:
			live[session] = true
	for session in session_ids():
		if not live.has(session):
			_remove_session(session)
	var ids: Array[int] = live.keys()
	ids.sort()
	for session in ids:
		_add_session(session)


## The number in "Guest N": Steam's guest id when it is small, else the lowest number no other session uses.
func _guest_number(session_id: int) -> int:
	if _guest_numbers.has(session_id):
		return _guest_numbers[session_id]
	var guest_id := int(_steam.call(&"getSessionGuestID", session_id))
	var number := guest_id if guest_id >= 1 and guest_id <= MAX_GUEST_NUMBER else 1
	var taken := _guest_numbers.values()
	while number in taken:
		number += 1
	_guest_numbers[session_id] = number
	return number


## The Steam Input handle of a joypad (0 = not a Steam Input pad). Godot stores the handle, as a string,
## under "steam_input_index"; the key is missing for a pad that is not a Steam Input device. Read through
## PadSource (the one place that asks the engine about pads), or [member joy_info_source] in tests.
func _input_handle_of(device: int) -> int:
	if joy_info_source.is_valid():
		var info: Dictionary = joy_info_source.call(device)
		return str(info.get("steam_input_index", "")).to_int()
	var pad := PadSource.identity(device)
	return pad.steam_input_index.to_int() if pad != null else 0


# --- Steam callbacks -----------------------------------------------------------------------

func _on_session_connected(session_id: int) -> void:
	_add_session(session_id)


func _on_session_disconnected(session_id: int) -> void:
	_remove_session(session_id)


## Steam emits (active, user_initiated, app_id); only the first matters.
func _on_overlay_toggled(active: bool, _user_initiated: bool = false, _app_id_arg: int = 0) -> void:
	overlay_toggled.emit(active)
