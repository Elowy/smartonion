class_name FakeRemotePlayBackend
extends RemotePlayBackend
## A scriptable backend for tests and the --fake-rpt=N dev flag (no Steam needed).
##
## Guests are plain data: [method connect_guest] adds a session with a name, [method assign_device] says which joypad
## belongs to it. With a guest count (FakeRemotePlayBackend.new(N), --fake-rpt=N) the guests are N sessions named after
## [constant NAMES] and joypad ids 1..N are their controllers (id 0 stays the host's); [method session_of_bot] gives smoke / demo bots
## (no joypad) the same identities, so the lobby shows "Remote · Mira" on their cards.

const NAMES: Array[String] = ["Mira", "Tobi", "Lena", "Odo"]
## Session ids of --fake-rpt guests: FAKE_SESSION_BASE + the guest number (1..N).
const FAKE_SESSION_BASE := 1000

var available := true
var invite_available := true
## How often [method show_invite] was called (tests).
var invites_shown := 0
## Overlay state last set through [method set_overlay].
var overlay_active := false

var _names: Dictionary[int, String] = {}
var _sessions: Array[int] = []
var _device_session: Dictionary[int, int] = {}
## --fake-rpt: joypad / bot index 1..guest_count belong to guest number index.
var _auto_guests := 0


## [param guest_count] guests (--fake-rpt=N) are connected from the start: sessions FAKE_SESSION_BASE + 1..N.
func _init(guest_count: int = 0) -> void:
	_auto_guests = clampi(guest_count, 0, NAMES.size())
	for i in _auto_guests:
		connect_guest(FAKE_SESSION_BASE + i + 1, NAMES[i])


func is_available() -> bool:
	return available


func session_of_device(device: int) -> int:
	if _device_session.has(device):
		return _device_session[device]
	return session_of_bot(device)


func guest_name(session_id: int) -> String:
	return _names.get(session_id, "")


func session_ids() -> Array[int]:
	return _sessions.duplicate()


func can_invite() -> bool:
	return available and invite_available


func show_invite() -> void:
	invites_shown += 1


## The session a smoke / demo bot [param index] (0 = the host) plays for: 0, or a --fake-rpt guest's.
func session_of_bot(index: int) -> int:
	if index >= 1 and index <= _auto_guests and (FAKE_SESSION_BASE + index) in _sessions:
		return FAKE_SESSION_BASE + index
	return 0


# --- Scripting ----------------------------------------------------------------------------

func connect_guest(session_id: int, guest_name_text: String) -> void:
	if session_id in _sessions:
		return
	_sessions.append(session_id)
	_names[session_id] = guest_name_text
	guest_connected.emit(session_id, guest_name_text)


func disconnect_guest(session_id: int) -> void:
	if session_id not in _sessions:
		return
	_sessions.erase(session_id)
	_names.erase(session_id)
	for device in _device_session.keys():
		if _device_session[device] == session_id:
			_device_session.erase(device)
	guest_disconnected.emit(session_id)


## Joypad [param device] becomes (or, with session 0, stops being) a controller of the guest [param session_id].
func assign_device(device: int, session_id: int) -> void:
	if session_id == 0:
		_device_session.erase(device)
	else:
		_device_session[device] = session_id


func set_overlay(active: bool) -> void:
	overlay_active = active
	overlay_toggled.emit(active)
