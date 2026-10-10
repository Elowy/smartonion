class_name PlayerInput
extends RefCounted
## Per-player input source. Local co-op cannot use Godot's global InputMap actions
## (they merge all devices), so every player polls its own device through one of:
##   JoypadInput   – one physical controller
##   KeyboardInput – keyboard + mouse
##   ScriptedInput / BotInput – tests, smoke runs and attract mode
##
## PlayerManager calls poll() once per rendered frame BEFORE any scene node processes.
## is_pressed() / get_move() are safe everywhere; just_pressed() / nav_just_pressed()
## describe edges of the current rendered frame and must be read from _process().

enum Pad {
	A, B, X, Y,          ## face buttons (Xbox naming): A confirm, B back, X sell, Y compare
	LB, RB, LT, RT,      ## shoulders / triggers
	START, SELECT,
	L3, R3,              ## stick clicks (R3 = ping)
	DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT,
}

## Gameplay mapping (GDD chapter 11).
const ABILITY_BUTTONS: Array[Pad] = [Pad.RT, Pad.LT, Pad.RB, Pad.LB]

const NAV_DEADZONE := 0.55
const NAV_REPEAT_DELAY := 0.38
const NAV_REPEAT_RATE := 0.11

var _cur: Dictionary[int, bool] = {}
var _prev: Dictionary[int, bool] = {}
var _nav_dir := Vector2i.ZERO
var _nav_prev := Vector2i.ZERO
var _nav_timer := 0.0
var _nav_fired := Vector2i.ZERO


## Human-readable device name for the lobby, e.g. "Controller 2" or "Keyboard".
func get_device_name() -> String:
	return "Input"


## Stable identifier of the device, used to stop one device joining twice.
func get_device_key() -> String:
	return "none"


func is_connected_device() -> bool:
	return true


## Movement vector, length 0..1.
func get_move() -> Vector2:
	return Vector2.ZERO


## Optional manual aim (right stick / mouse). Zero = auto aim.
func get_aim() -> Vector2:
	return Vector2.ZERO


func is_pressed(button: Pad) -> bool:
	return _cur.get(button, false)


func just_pressed(button: Pad) -> bool:
	return _cur.get(button, false) and not _prev.get(button, false)


func just_released(button: Pad) -> bool:
	return not _cur.get(button, false) and _prev.get(button, false)


func is_ability_pressed(index: int) -> bool:
	return index >= 0 and index < ABILITY_BUTTONS.size() and is_pressed(ABILITY_BUTTONS[index])


func ability_just_pressed(index: int) -> bool:
	return index >= 0 and index < ABILITY_BUTTONS.size() and just_pressed(ABILITY_BUTTONS[index])


## Menu navigation: a unit direction on the frame a direction is pushed, then with
## key-repeat while held. Zero otherwise.
func nav_just_pressed() -> Vector2i:
	return _nav_fired


## Called by PlayerManager once per frame.
func poll(delta: float) -> void:
	_prev = _cur.duplicate()
	_cur = _read_buttons()
	_update_nav(delta)


## Subclasses return { Button: bool } for the current hardware state.
func _read_buttons() -> Dictionary[int, bool]:
	return {}


## Subclasses may override to provide a navigation vector (stick / arrows).
func _read_nav_vector() -> Vector2:
	var v := get_move()
	if is_pressed(Pad.DPAD_LEFT): v.x = -1.0
	if is_pressed(Pad.DPAD_RIGHT): v.x = 1.0
	if is_pressed(Pad.DPAD_UP): v.y = -1.0
	if is_pressed(Pad.DPAD_DOWN): v.y = 1.0
	return v


func _update_nav(delta: float) -> void:
	var v := _read_nav_vector()
	var dir := Vector2i.ZERO
	if absf(v.x) >= NAV_DEADZONE or absf(v.y) >= NAV_DEADZONE:
		if absf(v.x) > absf(v.y):
			dir.x = signi(roundi(signf(v.x)))
		else:
			dir.y = signi(roundi(signf(v.y)))
	_nav_fired = Vector2i.ZERO
	if dir == Vector2i.ZERO:
		_nav_timer = 0.0
	elif dir != _nav_prev:
		_nav_fired = dir
		_nav_timer = NAV_REPEAT_DELAY
	else:
		_nav_timer -= delta
		if _nav_timer <= 0.0:
			_nav_fired = dir
			_nav_timer = NAV_REPEAT_RATE
	_nav_prev = dir
