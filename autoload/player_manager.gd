extends Node
## Autoload "PlayerManager": local co-op device handling (GDD chapter 6 / 11).
##
## - Up to MAX_PLAYERS slots, each bound to one device (controller, keyboard or bot).
## - While [member joining_enabled] is true, pressing A on an unused controller (or
##   Enter / Space on the keyboard) joins a new player.
## - Polls every slot's PlayerInput once per frame before any scene node runs.

signal player_joined(slot: PlayerSlot)
signal player_left(slot: PlayerSlot)
signal device_disconnected(slot: PlayerSlot)
signal device_reconnected(slot: PlayerSlot)

const MAX_PLAYERS := 4
const PLAYER_COLORS: Array[Color] = [
	Color(0.25, 0.55, 1.0),   # P1 blue
	Color(0.95, 0.3, 0.25),   # P2 red
	Color(0.35, 0.85, 0.35),  # P3 green
	Color(1.0, 0.82, 0.2),    # P4 yellow
]

var joining_enabled := false

var _slots: Array[PlayerSlot] = []
var _join_prev: Dictionary[String, bool] = {}


func _init() -> void:
	_slots.resize(MAX_PLAYERS)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _process(delta: float) -> void:
	for slot in _slots:
		if slot != null:
			slot.input.poll(delta)
	if joining_enabled:
		_scan_for_joins()


# --- Queries -----------------------------------------------------------------

func get_slots() -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	for slot in _slots:
		if slot != null:
			out.append(slot)
	return out


func get_slot(index: int) -> PlayerSlot:
	return _slots[index] if index >= 0 and index < MAX_PLAYERS else null


func count() -> int:
	return get_slots().size()


func is_full() -> bool:
	return count() >= MAX_PLAYERS


func is_device_used(device_key: String) -> bool:
	for slot in _slots:
		if slot != null and slot.input.get_device_key() == device_key:
			return true
	return false


func all_ready() -> bool:
	var slots := get_slots()
	if slots.is_empty():
		return false
	for slot in slots:
		if not slot.ready:
			return false
	return true


func set_all_ready(value: bool) -> void:
	for slot in get_slots():
		slot.ready = value


# --- Joining / leaving -------------------------------------------------------

## Joins a player with the given input. Returns null when full or the device is taken.
func join(input: PlayerInput, class_data: ClassData = null) -> PlayerSlot:
	if is_full() or is_device_used(input.get_device_key()):
		return null
	var index := _slots.find(null)
	var slot := PlayerSlot.new(index, input, PLAYER_COLORS[index])
	slot.class_data = class_data if class_data != null else Db.get_default_class()
	_slots[index] = slot
	player_joined.emit(slot)
	return slot


## Adds a bot-controlled player (smoke tests, demo mode).
func add_bot(class_id: StringName = &"", seed_value: int = 0) -> PlayerSlot:
	var bot := BotInput.new("bot:%d" % count(), seed_value)
	var data := Db.get_class_data(class_id) if class_id != &"" else null
	return join(bot, data)


func leave(index: int) -> void:
	var slot := get_slot(index)
	if slot == null:
		return
	_slots[index] = null
	player_left.emit(slot)


func clear() -> void:
	for i in MAX_PLAYERS:
		leave(i)


func _scan_for_joins() -> void:
	if is_full():
		return
	for device in Input.get_connected_joypads():
		var key := "joy:%d" % device
		var down := Input.is_joy_button_pressed(device, JOY_BUTTON_A)
		if down and not _join_prev.get(key, false) and not is_device_used(key):
			var slot := join(JoypadInput.new(device))
			if slot != null:
				slot.input.poll(0.0)  # swallow the join press
		_join_prev[key] = down
	var kb_down := Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SPACE)
	if kb_down and not _join_prev.get("keyboard", false) and not is_device_used("keyboard"):
		var slot := join(KeyboardInput.new())
		if slot != null:
			slot.input.poll(0.0)
	_join_prev["keyboard"] = kb_down


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	var key := "joy:%d" % device
	for slot in get_slots():
		if slot.input.get_device_key() == key:
			if connected:
				device_reconnected.emit(slot)
			else:
				device_disconnected.emit(slot)
