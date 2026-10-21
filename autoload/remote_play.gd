extends Node
## Autoload "RemotePlay": the game's view of online co-op (Steam Remote Play Together) through a
## [RemotePlayBackend]. Without a platform layer the backend is the Null one and nobody is remote, so local co-op
## behaves exactly as it always did.
##
## - Backend choice ([method create_default_backend]): --fake-rpt=N -> [FakeRemotePlayBackend] (dev flag, also in
##   automated runs); otherwise, in a real session only, the Steam backend when the file
##   core/platform/steam_remote_play_backend.gd exists and its static try_create() returns one; otherwise Null.
##   Smoke runs, demos, view runs, headless runs and the unit tests never get the Steam backend.
## - The game asks here: [method is_remote_device] (host rules, HostRules), [method guest_name] / [method slot_label]
##   (lobby card, notices), [method can_invite] / [method show_invite] (the lobby's "Invite friends"), and listens to
##   [signal overlay_toggled] (Main pauses the run while the platform overlay is open).
## - Nothing here draws from RunState.rng.
## See docs/ARCHITECTURE.md.

signal guest_connected(session_id: int, guest_name: String)
signal guest_disconnected(session_id: int)
signal overlay_toggled(active: bool)

## The Steam backend of the RPT-STEAM package, loaded by path so that the project compiles without it.
const STEAM_BACKEND_PATH := "res://core/platform/steam_remote_play_backend.gd"

var backend: RemotePlayBackend = NullRemotePlayBackend.new()

## The last name the backend gave each guest session (ids are not reused). A backend forgets a guest when the session
## ends, but the ghost seat, the pause menu's "Continue without …" and the disconnect notice still call them by name.
var _names: Dictionary[int, String] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1100
	var options := LaunchOptions.parse(OS.get_cmdline_user_args())
	set_backend(create_default_backend(options.fake_rpt, Settings.is_automated_run()))


func _process(_delta: float) -> void:
	backend.poll()


## The backend a launch gets (see the class comment). [param steam_path] is a parameter for tests.
static func create_default_backend(fake_count: int, automated: bool, steam_path: String = STEAM_BACKEND_PATH) -> RemotePlayBackend:
	if fake_count > 0:
		return FakeRemotePlayBackend.new(fake_count)
	if not automated and ResourceLoader.exists(steam_path):
		var script := load(steam_path) as GDScript
		if script != null:
			var made: Variant = script.call(&"try_create")
			if made is RemotePlayBackend:
				return made
	return NullRemotePlayBackend.new()


## Replaces the backend (null = Null). The signals of the old one stop being forwarded.
func set_backend(p_backend: RemotePlayBackend) -> void:
	if backend.guest_connected.is_connected(_on_guest_connected):
		backend.guest_connected.disconnect(_on_guest_connected)
		backend.guest_disconnected.disconnect(_on_guest_disconnected)
		backend.overlay_toggled.disconnect(_on_overlay_toggled)
	backend = p_backend if p_backend != null else NullRemotePlayBackend.new()
	backend.guest_connected.connect(_on_guest_connected)
	backend.guest_disconnected.connect(_on_guest_disconnected)
	backend.overlay_toggled.connect(_on_overlay_toggled)
	_names.clear()
	for session_id in backend.session_ids():  # (guests that were connected before anybody listened)
		guest_name(session_id)


# --- Queries ------------------------------------------------------------------------------

func is_available() -> bool:
	return backend.is_available()


## The Remote Play session of joypad [param device] (0 = local; the keyboard, a bot and unknown devices are -1 -> 0).
func session_of_device(device: int) -> int:
	return backend.session_of_device(device) if device >= 0 else 0


## The session a smoke / demo bot [param index] plays for (--fake-rpt: the first bots are guests; otherwise 0).
func session_of_bot(index: int) -> int:
	var fake := backend as FakeRemotePlayBackend
	return fake.session_of_bot(index) if fake != null else 0


## True when joypad [param device] belongs to a guest, not to the host.
func is_remote_device(device: int) -> bool:
	return device >= 0 and backend.is_remote_device(device)


## The guests' session ids.
func session_ids() -> Array[int]:
	return backend.session_ids()


## True while at least one guest is connected.
func has_guests() -> bool:
	return not backend.session_ids().is_empty()


## The name of the guest of [param session_id]: "" for the host (0); the backend's, else the last one it gave (a guest
## who has left keeps their name); "Guest N" while no name was ever known.
func guest_name(session_id: int) -> String:
	if session_id == 0:
		return ""
	var named := backend.guest_name(session_id)
	if named != "":
		_names[session_id] = named
		return named
	if _names.has(session_id):
		return _names[session_id]
	var ids := backend.session_ids()
	var at := ids.find(session_id)
	return "Guest %d" % (at + 1 if at >= 0 else 1)


## The guest's name behind [param slot] ("" for a local player).
func slot_name(slot: PlayerSlot) -> String:
	return guest_name(slot.session_id) if slot != null and slot.session_id != 0 else ""


## "Mira (P3)" for a guest's slot, "P3" for a local one: how notices name a player.
func slot_label(slot: PlayerSlot) -> String:
	var who := slot_name(slot)
	return slot.label() if who == "" else "%s (%s)" % [who, slot.label()]


func can_invite() -> bool:
	return backend.can_invite()


func show_invite() -> void:
	if backend.can_invite():
		backend.show_invite()


# --- Forwarding ----------------------------------------------------------------------------

func _on_guest_connected(session_id: int, guest_name_text: String) -> void:
	if guest_name_text != "":
		_names[session_id] = guest_name_text
	guest_connected.emit(session_id, guest_name_text)


func _on_guest_disconnected(session_id: int) -> void:
	guest_disconnected.emit(session_id)


func _on_overlay_toggled(active: bool) -> void:
	overlay_toggled.emit(active)
