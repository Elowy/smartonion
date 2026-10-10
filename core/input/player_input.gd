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
## Near a diagonal the axis of the previous frame wins until the other axis is stronger by
## more than this (stops a wobbling stick from flipping between left/right and up/down).
const NAV_AXIS_HYSTERESIS := 0.1

var _cur: Dictionary[int, bool] = {}
var _prev: Dictionary[int, bool] = {}
## Navigation direction held right now (unit vector, zero inside the deadzone).
var _nav_dir := Vector2i.ZERO
var _nav_prev := Vector2i.ZERO
var _nav_timer := 0.0
var _nav_fired := Vector2i.ZERO
## swallow() was called: no navigation edge until the stick / d-pad has been neutral once.
var _nav_swallowed := false


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


## The navigation direction currently held (unit vector, no key-repeat): zero while the
## stick / d-pad is inside the deadzone. Screens opened while a direction is still held (the
## stick the player was steering with) wait for this to be zero once before they navigate.
func nav_held() -> Vector2i:
	return _nav_dir


## Called by PlayerManager once per frame.
func poll(delta: float) -> void:
	_prev = _cur.duplicate()
	_cur = _read_buttons()
	_update_nav(delta)


## Treats everything held right now as already handled (PlayerManager calls it right after a
## join, so the join press is not also "A pressed" for the lobby): no just_pressed /
## just_released edge for the buttons that are down, and no navigation edge (nor key-repeat)
## until the stick / d-pad has been neutral once.
func swallow() -> void:
	_cur = _read_buttons()
	_prev = _cur.duplicate()
	_nav_fired = Vector2i.ZERO
	_nav_dir = _pick_nav_direction(_read_nav_vector(), Vector2i.ZERO)
	_nav_prev = _nav_dir
	_nav_timer = NAV_REPEAT_DELAY
	_nav_swallowed = _nav_dir != Vector2i.ZERO


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


## Quantises a stick / d-pad vector to a unit direction (zero inside the deadzone). Around
## the diagonals the axis of [param previous] is kept unless the other axis beats it by more
## than NAV_AXIS_HYSTERESIS.
func _pick_nav_direction(v: Vector2, previous: Vector2i) -> Vector2i:
	var ax := absf(v.x)
	var ay := absf(v.y)
	var x_ok := ax >= NAV_DEADZONE
	var y_ok := ay >= NAV_DEADZONE
	if not x_ok and not y_ok:
		return Vector2i.ZERO
	var horizontal: bool
	if previous.x != 0 and x_ok:
		horizontal = not (ay > ax + NAV_AXIS_HYSTERESIS)
	elif previous.y != 0 and y_ok:
		horizontal = ax > ay + NAV_AXIS_HYSTERESIS
	else:
		horizontal = ax > ay
	return Vector2i(signi(roundi(signf(v.x))), 0) if horizontal else Vector2i(0, signi(roundi(signf(v.y))))


func _update_nav(delta: float) -> void:
	var dir := _pick_nav_direction(_read_nav_vector(), _nav_prev)
	_nav_dir = dir
	_nav_fired = Vector2i.ZERO
	if dir == Vector2i.ZERO:
		_nav_timer = 0.0
		_nav_swallowed = false
	elif _nav_swallowed:
		_nav_timer = NAV_REPEAT_DELAY  # still the push from before swallow(): no edge, no repeat
	elif dir != _nav_prev:
		_nav_fired = dir
		_nav_timer = NAV_REPEAT_DELAY
	else:
		_nav_timer -= delta
		if _nav_timer <= 0.0:
			_nav_fired = dir
			_nav_timer = NAV_REPEAT_RATE
	_nav_prev = dir
