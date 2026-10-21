class_name HostRules
extends RefCounted
## Who may do what when guests stream the host's window (Remote Play Together) or stray controllers are around.
## Minimal on purpose: only the destructive actions and the host's own window are the host's. Everything else stays
## "anyone" (GDD: any joined player picks mode / hardcore / difficulty). Without a Remote Play backend no device is
## remote, so for local co-op the rules change nothing – except that an unjoined pad cannot do the destructive
## things in a menu that no player drives (the slot-less pause menu) while a party exists.
##
## The keyboard, the mouse and anything without a joypad id (device -1: a bot, a test's injected press) are the
## host's. A guest's merged keyboard / mouse cannot be told from the host's; the host should not share them.

enum Action {
	QUIT_GAME,      ## the main menu's Quit
	QUIT_TO_MENU,   ## the pause menu's Quit to Menu (abandons the run for everyone)
	DROP_PLAYER,    ## "Continue without Pn"
	VIDEO_SETTINGS, ## window mode / VSync / max FPS (the host's window)
	INVITE,         ## the lobby's "Invite friends"
}

## What a menu says when it refuses.
const REFUSED_TEXT := "Only the host can do that"


## A joined player's own action: refused for a guest's slot. [param slot] null = the keyboard / nobody: allowed.
static func may(_action: Action, slot: PlayerSlot) -> bool:
	return slot == null or not slot.is_remote()


## An action by a pad press in a screen without a driving slot. [param party_present]: players have joined, so a pad
## nobody plays is a stray (a spare pad, a guest's second controller) and may not do destructive things.
static func may_device(action: Action, device: int, party_present: bool = false) -> bool:
	if device < 0:
		return true
	if RemotePlay.is_remote_device(device):
		return false
	if party_present and action != Action.INVITE and not PlayerManager.is_pad_bound(device):
		return false
	return true


## [method may_device] for the pads that pressed together: allowed when no pad pressed (the keyboard, a test) or when
## any of them may.
static func may_any_device(action: Action, devices: Array[int], party_present: bool = false) -> bool:
	if devices.is_empty():
		return true
	for device in devices:
		if may_device(action, device, party_present):
			return true
	return false


## Window mode / VSync / max FPS: the host's.
static func is_video_key(key: StringName) -> bool:
	return key == GameSettings.WINDOW_MODE or key == GameSettings.VSYNC or key == GameSettings.MAX_FPS
