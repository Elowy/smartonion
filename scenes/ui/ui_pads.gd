class_name UiPads
extends RefCounted
## Button edges on EVERY connected controller, for the few screens that must work before
## anyone has joined (main menu, empty lobby). Godot's ui_accept / ui_cancel only map
## keyboard keys, so controllers are read here directly. Joined players always go through
## their own PlayerSlot.input instead. Call poll() once per frame from _process().

const BUTTONS: Array[JoyButton] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START]

var _prev: Dictionary[String, bool] = {}
var _cur: Dictionary[String, bool] = {}
## Tests / scripted demos: buttons forced down this frame (cleared by poll()).
var injected: Array[JoyButton] = []


func poll() -> void:
	_prev = _cur
	_cur = {}
	for device in Input.get_connected_joypads():
		for b in BUTTONS:
			if Input.is_joy_button_pressed(device, b):
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


## True while [param button] is held on any controller.
func any_pressed(button: JoyButton) -> bool:
	var suffix := ":%d" % button
	for key in _cur:
		if key.ends_with(suffix):
			return true
	return false


## True while any controller's A or the keyboard's Enter / Space is held (the join buttons).
static func join_button_held() -> bool:
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SPACE) \
			or Input.is_physical_key_pressed(KEY_KP_ENTER):
		return true
	for device in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(device, JOY_BUTTON_A):
			return true
	return false
