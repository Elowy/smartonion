class_name PadSource
extends RefCounted
## The one place that asks the engine which controllers are connected and what they press (the seam in front of
## Input.get_connected_joypads / get_joy_info / is_joy_button_pressed / get_joy_axis). Everything that used to call
## those directly – PlayerManager's join scan, UiPads, JoypadInput – goes through here, so that
## - the set of pads and each pad's [PadIdentity] is read ONCE per rendered frame (a snapshot: the engine's
##   joy_connection_changed signal is deferred and can describe a newer state than the moment it reports), and
## - tests and the dev smoke can fake hotplug: [method enable_fake] switches the source to a table the caller fills
##   with [method fake_connect] / [method fake_disconnect] / [method fake_press] (a script cannot make
##   Input.get_connected_joypads() return a fake pad).
## Nothing here touches RunState.rng.

## Fake mode: the pads below replace the engine's.
static var fake := false

static var _snapshot: Dictionary = {}  # device -> PadIdentity (untyped: a typed static container outlives its script at exit)
static var _snapshot_frame := -1
static var _fake_pads: Dictionary = {}  # device -> PadIdentity
static var _fake_buttons: Dictionary = {}  # device * 1000 + button -> down
static var _fake_axes: Dictionary = {}  # device * 1000 + axis -> value


# --- Reading --------------------------------------------------------------------------------

## The connected joypad ids, ascending.
static func devices() -> Array[int]:
	var out: Array[int] = []
	if fake:
		out.assign(_fake_pads.keys())
	else:
		_refresh()
		out.assign(_snapshot.keys())
	out.sort()
	return out


static func is_pad_connected(device: int) -> bool:
	if fake:
		return _fake_pads.has(device)
	_refresh()
	return _snapshot.has(device)


## The identity of the pad on [param device] right now; null when nothing is connected there.
static func identity(device: int) -> PadIdentity:
	if fake:
		return _fake_pads.get(device)
	_refresh()
	return _snapshot.get(device)


static func is_button_down(device: int, button: JoyButton) -> bool:
	if fake:
		return _fake_buttons.get(device * 1000 + button, false)
	return Input.is_joy_button_pressed(device, button)


static func axis_value(device: int, axis: JoyAxis) -> float:
	if fake:
		return _fake_axes.get(device * 1000 + axis, 0.0)
	return Input.get_joy_axis(device, axis)


static func pad_name(device: int) -> String:
	var id := identity(device)
	return id.pad_name if id != null else ""


## Forces the next read to re-scan the engine (a joy_connection_changed arrived).
static func invalidate() -> void:
	_snapshot_frame = -1


## Reads the engine once per rendered frame. A pad whose fingerprint did not change keeps its PadIdentity object.
static func _refresh() -> void:
	var frame := Engine.get_process_frames()
	if frame == _snapshot_frame:
		return
	_snapshot_frame = frame
	var fresh: Dictionary = {}
	for device in Input.get_connected_joypads():
		var read_id := PadIdentity.read(device)
		var old: PadIdentity = _snapshot.get(device)
		fresh[device] = old if old != null and old.same_pad(read_id) else read_id
	_snapshot = fresh


# --- Faking (tests, --hotplug-test) --------------------------------------------------------------

## Switches to the fake table (emptied) or back to the engine.
static func enable_fake(on: bool = true) -> void:
	fake = on
	_fake_pads.clear()
	_fake_buttons.clear()
	_fake_axes.clear()
	_snapshot.clear()
	_snapshot_frame = -1


## Connects a fake pad on [param device] and returns its identity. Without [param p_identity] it is a pad with a
## guid of its own ("fake-<id>"), i.e. a different physical pad than any other fake one.
static func fake_connect(device: int, p_identity: PadIdentity = null) -> PadIdentity:
	var id := p_identity if p_identity != null else PadIdentity.make(device, "Fake Pad %d" % (device + 1), "fake-%d" % device)
	id.device = device
	_fake_pads[device] = id
	return id


static func fake_disconnect(device: int) -> void:
	_fake_pads.erase(device)
	for button in range(JOY_BUTTON_MAX):
		_fake_buttons.erase(device * 1000 + button)
	for axis in range(JOY_AXIS_MAX):
		_fake_axes.erase(device * 1000 + axis)


static func fake_press(device: int, button: JoyButton, down: bool = true) -> void:
	_fake_buttons[device * 1000 + button] = down


static func fake_axis(device: int, axis: JoyAxis, value: float) -> void:
	_fake_axes[device * 1000 + axis] = value
