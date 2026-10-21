class_name FakeSteamSingleton
extends RefCounted
## A stand-in for the GodotSteam "Steam" singleton, for the tests of SteamRemotePlayBackend: the methods and
## signals of the plug-in that the backend uses (same names, same arguments, the same results), a record of
## every call, and knobs to script Steam's answers. Like the real plug-in it complains (here: records) about
## a Remote Play / Input call made while Steam is not initialised.

signal remote_play_session_connected(session_id: int)
signal remote_play_session_disconnected(session_id: int)
signal overlay_toggled(active: bool, user_initiated: bool, app_id: int)

## steamInitEx() answers {status: init_status, verbal: init_verbal}; 0 = ok.
var init_status := 0
var init_verbal := "Success"
## steamInitEx() answers something that is not a Dictionary.
var init_returns_garbage := false
## inputInit() result.
var input_init_ok := true
## showRemotePlayTogetherUI() result (false = the app is not configured for Remote Play Together).
var invite_ok := true

var initialized := false
var current_app_id := 0
var last_init_app_id := -1
var last_init_embed := false

## The sessions getSessionCount() / getSessionID() list.
var sessions: Array[int] = []
## session id -> Steam id (0 / missing = a guest without a Steam account).
var steam_ids: Dictionary = {}
## session id -> guest id.
var guest_ids: Dictionary = {}
## Steam id -> persona name ("" = Steam is still loading that user's data).
var persona_names: Dictionary = {}
## Input handle -> Remote Play session id (missing = 0, a local device).
var handle_sessions: Dictionary = {}

## Names of all calls, in order.
var calls: Array[String] = []
## Calls of Remote Play / Input / Friends functions made while not initialised (the real plug-in logs an engine error).
var calls_while_uninitialised: Array[String] = []
## Calls the backend must never make: the broken direct keyboard / mouse API of GodotSteam 4.23.2, and
## getSessionClientName (the guest's DEVICE name, not the player's).
var forbidden_calls: Array[String] = []
## Arguments of the getFriendPersonaName calls.
var persona_requests: Array[int] = []


func count(method: String) -> int:
	return calls.count(method)


# --- Test helpers ---------------------------------------------------------------------------

## A guest connects: Steam lists the session and sends the callback.
func connect_guest(session_id: int, steam_id: int = 0, persona: String = "", guest_id: int = 0) -> void:
	if session_id not in sessions:
		sessions.append(session_id)
	steam_ids[session_id] = steam_id
	guest_ids[session_id] = guest_id
	if steam_id != 0:
		persona_names[steam_id] = persona
	remote_play_session_connected.emit(session_id)


func disconnect_guest(session_id: int) -> void:
	sessions.erase(session_id)
	remote_play_session_disconnected.emit(session_id)


# --- Initialisation (not gated) ---------------------------------------------------------------

func get_current_app_id() -> int:
	calls.append("get_current_app_id")
	return current_app_id


func steamInitEx(app_id: int = 0, embed_callbacks: bool = false) -> Variant:
	calls.append("steamInitEx")
	last_init_app_id = app_id
	last_init_embed = embed_callbacks
	if init_returns_garbage:
		return "not a dictionary"
	initialized = init_status == 0
	if initialized:
		current_app_id = app_id
	return {"status": init_status, "verbal": init_verbal}


func run_callbacks() -> void:
	calls.append("run_callbacks")


# --- Gated like the plug-in's (an error while not initialised) ---------------------------------

func inputInit(_explicitly_call_runframe: bool = false) -> bool:
	_gate("inputInit")
	return input_init_ok


func getRemotePlaySessionID(input_handle: int) -> int:
	_gate("getRemotePlaySessionID")
	return int(handle_sessions.get(input_handle, 0))


func getSessionCount() -> int:
	_gate("getSessionCount")
	return sessions.size()


func getSessionID(index: int) -> int:
	_gate("getSessionID")
	return sessions[index] if index >= 0 and index < sessions.size() else 0


func getSessionSteamID(session_id: int) -> int:
	_gate("getSessionSteamID")
	return int(steam_ids.get(session_id, 0))


func getSessionGuestID(session_id: int) -> int:
	_gate("getSessionGuestID")
	return int(guest_ids.get(session_id, 0))


func getFriendPersonaName(steam_id: int) -> String:
	_gate("getFriendPersonaName")
	persona_requests.append(steam_id)
	return String(persona_names.get(steam_id, ""))


func showRemotePlayTogetherUI() -> bool:
	_gate("showRemotePlayTogetherUI")
	return invite_ok


# --- The direct-input API (broken in GodotSteam 4.23.2): recorded as forbidden --------------------

func enableRemotePlayTogetherDirectInput() -> bool:
	return _forbidden("enableRemotePlayTogetherDirectInput")


func disableRemotePlayTogetherDirectInput() -> void:
	_forbidden("disableRemotePlayTogetherDirectInput")


func getInput(_max_events: int = 0) -> Array:
	_forbidden("getInput")
	return []


func createMouseCursor(_width: int = 0, _height: int = 0, _hot_x: int = 0, _hot_y: int = 0, _pitch: int = 0) -> Dictionary:
	_forbidden("createMouseCursor")
	return {}


func setMouseCursor(_session_id: int = 0, _cursor_id: int = 0) -> void:
	_forbidden("setMouseCursor")


func setMousePosition(_session_id: int = 0, _x: float = 0.0, _y: float = 0.0) -> void:
	_forbidden("setMousePosition")


func setMouseVisibility(_session_id: int = 0, _visible: bool = true) -> void:
	_forbidden("setMouseVisibility")


func getSessionClientName(_session_id: int) -> String:
	_forbidden("getSessionClientName")
	return ""


func _gate(method: String) -> void:
	calls.append(method)
	if not initialized:
		calls_while_uninitialised.append(method)


func _forbidden(method: String) -> bool:
	calls.append(method)
	forbidden_calls.append(method)
	return false
