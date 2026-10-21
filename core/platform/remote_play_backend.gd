class_name RemotePlayBackend
extends RefCounted
## What the game needs to know about online co-op ("Remote Play Together"): which controllers belong to guests
## streaming the host's window, and how they are called. The base class is the "nobody is remote" backend – every
## method has the inert default, so the Null backend is just this class.
##
## Backends: [NullRemotePlayBackend] (default), [FakeRemotePlayBackend] (tests and the --fake-rpt dev flag) and the
## Steam one (core/platform/steam_remote_play_backend.gd, loaded by the RemotePlay autoload when it exists).
## Devices are Godot joypad ids; a session id of 0 is the host's own (local) device. The game never talks to a
## backend directly: it asks the RemotePlay autoload, which forwards here and re-emits the signals.

## A guest connected to the host's session ([param guest_name] may be empty while it is unknown).
signal guest_connected(session_id: int, guest_name: String)
signal guest_disconnected(session_id: int)
## The platform overlay (the Steam overlay) opened ([param active] true) or closed.
signal overlay_toggled(active: bool)


## True when the platform layer works (Steam running and initialised; the Fake backend always).
func is_available() -> bool:
	return false


## Called every rendered frame by the autoload (run callbacks, read events).
func poll() -> void:
	pass


## The Remote Play session of joypad [param device]; 0 = a local device (or an unknown one).
func session_of_device(_device: int) -> int:
	return 0


## True when [param device] is a guest's controller.
func is_remote_device(device: int) -> bool:
	return session_of_device(device) != 0


## The display name of the guest of [param session_id] ("" = unknown).
func guest_name(_session_id: int) -> String:
	return ""


## The ids of the guest sessions connected right now.
func session_ids() -> Array[int]:
	var out: Array[int] = []
	return out


## True when [method show_invite] can open the platform's invite dialog.
func can_invite() -> bool:
	return false


## Opens the platform's invite dialog (the Steam Remote Play Together invite UI).
func show_invite() -> void:
	pass
