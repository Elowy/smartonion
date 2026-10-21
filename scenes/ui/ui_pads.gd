class_name UiPads
extends RefCounted
## Button edges on EVERY connected controller, for the few screens that must work before
## anyone has joined (main menu, empty lobby). Godot's ui_accept / ui_cancel only map
## keyboard keys, so controllers are read here directly. Joined players always go through
## their own PlayerSlot.input instead. Call poll() once per frame from _process().

const BUTTONS: Array[JoyButton] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_START, JOY_BUTTON_LEFT_SHOULDER,
		JOY_BUTTON_RIGHT_SHOULDER]

var _prev: Dictionary[String, bool] = {}
var _cur: Dictionary[String, bool] = {}
## Tests / scripted demos: buttons forced down this frame (cleared by poll()).
var injected: Array[JoyButton] = []


func poll() -> void:
	_prev = _cur
	_cur = {}
	for device in PadSource.devices():
		for b in BUTTONS:
			if PadSource.is_button_down(device, b):
				_cur["%d:%d" % [device, b]] = true
	for b in injected:
		_cur["-1:%d" % b] = true
	injected.clear()


## True when [param button] went down this frame on any controller.
func any_just_pressed(button: JoyButton) -> bool:
	var suffix := ":%d" % button
	for key in _cur:
		if key.ends_with(suffix) and not _prev.has(key):
			return true
	return false


## The joypad ids whose [param button] went down this frame (the injected test press, device -1, is not listed).
func just_pressed_devices(button: JoyButton) -> Array[int]:
	var out: Array[int] = []
	var suffix := ":%d" % button
	for key in _cur:
		if key.ends_with(suffix) and not _prev.has(key):
			var device := int(key.get_slice(":", 0))
			if device >= 0:
				out.append(device)
	return out


## True while [param button] is held on any controller.
func any_pressed(button: JoyButton) -> bool:
	var suffix := ":%d" % button
	for key in _cur:
		if key.ends_with(suffix):
			return true
	return false


## True while any controller's A or one of the keyboard's join keys (KeyboardInput.JOIN_KEYS:
## Enter, Space, Keypad Enter, F – the same keys PlayerManager joins with) is held.
static func join_button_held() -> bool:
	if KeyboardInput.join_key_held():
		return true
	for device in PadSource.devices():
		if PadSource.is_button_down(device, JOY_BUTTON_A):
			return true
	return false
