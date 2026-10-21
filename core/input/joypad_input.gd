class_name JoypadInput
extends PlayerInput
## One physical game controller.

const STICK_DEADZONE := 0.2
const TRIGGER_THRESHOLD := 0.45

const _BUTTON_MAP := {
	PlayerInput.Pad.A: JOY_BUTTON_A,
	PlayerInput.Pad.B: JOY_BUTTON_B,
	PlayerInput.Pad.X: JOY_BUTTON_X,
	PlayerInput.Pad.Y: JOY_BUTTON_Y,
	PlayerInput.Pad.LB: JOY_BUTTON_LEFT_SHOULDER,
	PlayerInput.Pad.RB: JOY_BUTTON_RIGHT_SHOULDER,
	PlayerInput.Pad.START: JOY_BUTTON_START,
	PlayerInput.Pad.SELECT: JOY_BUTTON_BACK,
	PlayerInput.Pad.L3: JOY_BUTTON_LEFT_STICK,
	PlayerInput.Pad.R3: JOY_BUTTON_RIGHT_STICK,
	PlayerInput.Pad.DPAD_UP: JOY_BUTTON_DPAD_UP,
	PlayerInput.Pad.DPAD_DOWN: JOY_BUTTON_DPAD_DOWN,
	PlayerInput.Pad.DPAD_LEFT: JOY_BUTTON_DPAD_LEFT,
	PlayerInput.Pad.DPAD_RIGHT: JOY_BUTTON_DPAD_RIGHT,
}

var device: int
## The fingerprint of the pad that was on [member device] when this input was made (null when none was connected).
## Joypad ids are reused, so "joy:N is connected" does not mean "MY pad is connected": see [method is_connected_device].
var identity: PadIdentity


func _init(p_device: int) -> void:
	device = p_device
	identity = PadSource.identity(p_device)


func get_device_name() -> String:
	var joy_name := PadSource.pad_name(device)
	return "Controller %d" % (device + 1) if joy_name.is_empty() else joy_name


func get_device_key() -> String:
	return "joy:%d" % device


## True while the pad this input was made for is connected: the id must be connected AND still be the same
## pad (an id freed by a disconnect is handed to the next pad that connects, which may be somebody else's).
func is_connected_device() -> bool:
	var now := PadSource.identity(device)
	return now != null and (identity == null or identity == now or identity.same_pad(now))


func get_move() -> Vector2:
	return _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)


func get_aim() -> Vector2:
	return _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)


func _stick(axis_x: JoyAxis, axis_y: JoyAxis) -> Vector2:
	if not is_connected_device():
		return Vector2.ZERO  # (the id belongs to another pad now, or to none: not this player's stick)
	var v := Vector2(PadSource.axis_value(device, axis_x), PadSource.axis_value(device, axis_y))
	var length := v.length()
	if length < STICK_DEADZONE:
		return Vector2.ZERO
	# Rescale so the output starts at 0 right after the deadzone.
	return v / length * clampf((length - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 0.0, 1.0)


## A pad that is not this input's own (see [method is_connected_device]) presses nothing: a ghost slot whose id was
## handed to somebody else's pad must not be driven by it (a free pad's first A is seen by PlayerManager's scan only).
func _read_buttons() -> Dictionary[int, bool]:
	var out: Dictionary[int, bool] = {}
	var own := is_connected_device()
	for b in _BUTTON_MAP:
		out[b] = own and PadSource.is_button_down(device, _BUTTON_MAP[b])
	out[PlayerInput.Pad.LT] = own and PadSource.axis_value(device, JOY_AXIS_TRIGGER_LEFT) > TRIGGER_THRESHOLD
	out[PlayerInput.Pad.RT] = own and PadSource.axis_value(device, JOY_AXIS_TRIGGER_RIGHT) > TRIGGER_THRESHOLD
	return out
