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


func _init(p_device: int) -> void:
	device = p_device


func get_device_name() -> String:
	var joy_name := Input.get_joy_name(device)
	return "Controller %d" % (device + 1) if joy_name.is_empty() else joy_name


func get_device_key() -> String:
	return "joy:%d" % device


func is_connected_device() -> bool:
	return device in Input.get_connected_joypads()


func get_move() -> Vector2:
	return _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)


func get_aim() -> Vector2:
	return _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)


func _stick(axis_x: JoyAxis, axis_y: JoyAxis) -> Vector2:
	var v := Vector2(Input.get_joy_axis(device, axis_x), Input.get_joy_axis(device, axis_y))
	var length := v.length()
	if length < STICK_DEADZONE:
		return Vector2.ZERO
	# Rescale so the output starts at 0 right after the deadzone.
	return v / length * clampf((length - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 0.0, 1.0)


func _read_buttons() -> Dictionary[int, bool]:
	var out: Dictionary[int, bool] = {}
	for b in _BUTTON_MAP:
		out[b] = Input.is_joy_button_pressed(device, _BUTTON_MAP[b])
	out[PlayerInput.Pad.LT] = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > TRIGGER_THRESHOLD
	out[PlayerInput.Pad.RT] = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > TRIGGER_THRESHOLD
	return out
