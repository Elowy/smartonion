class_name KeyboardInput
extends PlayerInput
## Keyboard + mouse player (GDD chapter 11).
## WASD / arrows move, LMB / RMB = core abilities, Q / E = learned abilities,
## Enter / Space / F = confirm, Esc / Backspace = back, R = sell, C = compare,
## Tab = ping, P / Esc = pause.

## The keys that confirm (Pad.A) AND join a new keyboard player in the lobby: one list, so
## the join gesture and the confirm gesture can never drift apart.
const JOIN_KEYS: Array[Key] = [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER, KEY_F]

const _KEYS := {
	PlayerInput.Pad.A: JOIN_KEYS,
	PlayerInput.Pad.B: [KEY_ESCAPE, KEY_BACKSPACE],
	PlayerInput.Pad.X: [KEY_R],
	PlayerInput.Pad.Y: [KEY_C],
	PlayerInput.Pad.LB: [KEY_Q],
	PlayerInput.Pad.RB: [KEY_E],
	PlayerInput.Pad.START: [KEY_P, KEY_ESCAPE],
	PlayerInput.Pad.SELECT: [KEY_TAB],
	PlayerInput.Pad.R3: [KEY_TAB],
	PlayerInput.Pad.DPAD_UP: [KEY_UP],
	PlayerInput.Pad.DPAD_DOWN: [KEY_DOWN],
	PlayerInput.Pad.DPAD_LEFT: [KEY_LEFT],
	PlayerInput.Pad.DPAD_RIGHT: [KEY_RIGHT],
}


## True while any of the JOIN_KEYS is held (physical keys, any keyboard layout).
static func join_key_held() -> bool:
	for key in JOIN_KEYS:
		if Input.is_physical_key_pressed(key):
			return true
	return false


## LMB / RMB = core slots, Q = learned slot 1 (slot 2), E = learned slot 2 (slot 3), GDD 11 –
## Q / E keep their menu meaning (LB / RB = tab left / right).
func ability_button(index: int) -> Pad:
	return [Pad.RT, Pad.LT, Pad.LB, Pad.RB][index]


func get_device_name() -> String:
	return "Keyboard & Mouse"


func get_device_key() -> String:
	return "keyboard"


func get_move() -> Vector2:
	var v := Vector2(
		float(_key(KEY_D) or _key(KEY_RIGHT)) - float(_key(KEY_A) or _key(KEY_LEFT)),
		float(_key(KEY_S) or _key(KEY_DOWN)) - float(_key(KEY_W) or _key(KEY_UP)),
	)
	return v.normalized() if v.length() > 1.0 else v


func _read_buttons() -> Dictionary[int, bool]:
	var out: Dictionary[int, bool] = {}
	for b in _KEYS:
		var down := false
		for key in _KEYS[b]:
			if _key(key):
				down = true
				break
		out[b] = down
	out[PlayerInput.Pad.RT] = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	out[PlayerInput.Pad.LT] = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	return out


func _read_nav_vector() -> Vector2:
	# WASD and arrows both navigate menus.
	return get_move()


func _key(key: Key) -> bool:
	return Input.is_physical_key_pressed(key)
