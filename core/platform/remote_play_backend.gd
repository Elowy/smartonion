class_name RemotePlayBackend
extends RefCounted
## Interface of a Remote Play Together backend (Steam Remote Play Together, a fake one for tests, or none).
## This base class is the Null backend: nothing is available, every pad is local, nobody is a guest.
## A real backend overrides the methods below and emits the signals; it never reaches into gameplay.
##
## "Session" is a remote guest connection (Steam: a Remote Play session id, > 0). Session id 0 means
## "local" (the host's own pad or keyboard).

## A guest joined the party's stream. [param name] is the display name (see [method guest_name]).
@warning_ignore("unused_signal")
signal guest_connected(session_id: int, name: String)
## A guest left the stream.
@warning_ignore("unused_signal")
signal guest_disconnected(session_id: int)
## The platform overlay (Steam overlay) opened ([param active] true) or closed.
@warning_ignore("unused_signal")
signal overlay_toggled(active: bool)


## True when this backend really talks to a platform (false for the Null backend).
func is_available() -> bool:
	return false


## Called once per frame by the owner: pump the platform's callbacks and refresh the sessions.
func poll() -> void:
	pass


## The remote session the joypad [param device] belongs to, or 0 for a local device.
func session_of_device(_device: int) -> int:
	return 0


## True when the joypad [param device] is driven by a remote guest.
func is_remote_device(_device: int) -> bool:
	return false


## The display name of the guest of [param session_id] ("" when unknown).
func guest_name(_session_id: int) -> String:
	return ""


## The ids of the currently connected guest sessions.
func session_ids() -> Array[int]:
	return []


## True when [method show_invite] can open an invite UI.
func can_invite() -> bool:
	return false


## Opens the platform's invite UI (Steam: the Remote Play Together panel of the overlay).
func show_invite() -> void:
	pass
