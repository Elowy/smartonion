extends Node
## Autoload "PlayerManager": local co-op device handling (GDD chapter 6 / 11).
##
## - Up to MAX_PLAYERS slots, each bound to one device (controller, keyboard or bot).
## - While [member joining_enabled] is true, pressing A on an unused controller (or one of
##   KeyboardInput.JOIN_KEYS on the keyboard) joins a new player. The join press is swallowed
##   (PlayerInput.swallow()), so it does not also count as A for the screen that is open.
## - Polls every slot's PlayerInput once per frame before any scene node runs, and lets the
##   inputs "think" (bot AI) once per unpaused physics tick before any body moves.
## - Hotplug (RPT-CORE): controllers are read through [PadSource] (one snapshot per frame, fakeable). A slot
##   remembers its pad's fingerprint ([PadIdentity]) and its Remote Play session; a connected pad takes a missing
##   slot back by itself only when session or fingerprint match ("joy:N" alone proves nothing, ids are reused). Any
##   other free pad takes a missing slot over by pressing A – the one it provably belongs to, else the lowest
##   ([method take_over], in the lobby while [member joining_enabled], during a run while [member takeover_enabled]):
##   [method rebind] swaps the slot's input.

signal player_joined(slot: PlayerSlot)
signal player_left(slot: PlayerSlot)
signal device_disconnected(slot: PlayerSlot)
## The slot's controller is back (the same pad, or another one that took the slot over: [method rebind]).
signal device_reconnected(slot: PlayerSlot)
## A free pad pressed A and got nothing: [param reason] is &"full" (the lobby is full; announced once per pad) or
## &"in_run" (a run is on: new players join at the next lobby).
signal join_refused(device: int, reason: StringName)

const MAX_PLAYERS := 4
## The lobby frees a slot whose controller has been missing this long (seconds); until then it waits as
## "Disconnected – press A to take over".
const GHOST_TIMEOUT := 60.0
## The between-wave screens (market, loot roll, level-up, shrine, portal) wait this long (seconds) for a missing
## player before they decide for them. Tests shorten it.
const AUTO_DECIDE_GRACE := 5.0
const PLAYER_COLORS: Array[Color] = [
	Color(0.25, 0.55, 1.0),   # P1 blue
	Color(0.95, 0.3, 0.25),   # P2 red
	Color(0.35, 0.85, 0.35),  # P3 green
	Color(1.0, 0.82, 0.2),    # P4 yellow
]

var joining_enabled := false
## During a run: a free pad's A takes a missing slot over (Main switches it on while a run is on screen).
var takeover_enabled := false
## See [constant AUTO_DECIDE_GRACE].
var auto_decide_grace := AUTO_DECIDE_GRACE

var _slots: Array[PlayerSlot] = []
var _join_prev: Dictionary[String, bool] = {}
## Pads that already got the "party is full" notice (cleared when a slot frees up).
var _full_notified: Dictionary[int, bool] = {}
## A free pad took a slot over since the last frame (the pause menu must not read the same A as one of its own).
var _took_over := false


func _init() -> void:
	_slots.resize(MAX_PLAYERS)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	process_physics_priority = -1000
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _process(delta: float) -> void:
	_took_over = false
	for slot in _slots:
		if slot != null:
			slot.input.poll(delta)
	track_connections(delta)
	_scan_free_pads()


## Bots decide here, once per physics tick and only while the game runs: their movement is a
## function of the tick, not of how many ticks a rendered frame happened to contain (seeded
## smoke runs must be reproducible). Runs before every body's own _physics_process.
func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	for slot in _slots:
		if slot != null:
			slot.input.think(delta)


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


## Human (non-bot) slots whose device is not connected right now (an unplugged controller).
func disconnected_slots() -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	for slot in _slots:
		if slot != null and slot.input != null and not slot.is_bot() and not slot.input.is_connected_device():
			out.append(slot)
	return out


## True when at least one human slot has a working device (it can press buttons).
func has_connected_human() -> bool:
	for slot in _slots:
		if slot != null and slot.input != null and not slot.is_bot() and slot.input.is_connected_device():
			return true
	return false


## The lowest-numbered human slot whose device is missing (what a free pad takes over when it matches no slot's pad
## better, [method take_over]); null when none.
func first_ghost() -> PlayerSlot:
	var ghosts := disconnected_slots()
	return ghosts[0] if not ghosts.is_empty() else null


## True when [param slot] is a human whose device is missing right now (a "ghost").
func is_missing(slot: PlayerSlot) -> bool:
	return slot != null and slot.input != null and not slot.is_bot() and not slot.input.is_connected_device()


## True when nobody is behind [param slot] for good: no input at all, or a human whose device has been missing longer
## than [member auto_decide_grace]. The between-wave screens decide for such a slot; for a shorter absence they wait
## (a blip of a few seconds changes nothing). Bots are not "absent" (the screens handle them on their own).
func is_absent(slot: PlayerSlot) -> bool:
	if slot == null or slot.input == null:
		return true
	return is_missing(slot) and slot.missing_time >= auto_decide_grace


## Removes every human slot whose device has been missing for at least [param min_missing] seconds (0 = every ghost: a
## ghost slot can never ready up, so it would block the lobby for good). Returns how many slots were removed.
func prune_disconnected(min_missing: float = 0.0) -> int:
	var gone: Array[PlayerSlot] = []
	for slot in disconnected_slots():
		if slot.missing_time >= min_missing:
			gone.append(slot)
	for slot in gone:
		leave(slot.index)
	return gone.size()


## Restarts the "missing for" clock of every ghost (the lobby opens: its timeout starts from there).
func restart_ghost_timers() -> void:
	for slot in disconnected_slots():
		slot.missing_time = 0.0


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
	slot.class_data = class_data if class_data != null else Meta.default_class()
	var pad := input as JoypadInput
	if pad != null:
		slot.session_id = RemotePlay.session_of_device(pad.device)
	_slots[index] = slot
	if not slot.is_bot():
		Audio.play_ui(&"ui_join")
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


## Pads nobody plays: connected, and not the working pad of any slot.
func is_pad_free(device: int) -> bool:
	return PadSource.is_pad_connected(device) and not is_pad_bound(device)


## True when a slot's working JoypadInput is on [param device] (a ghost slot whose id now belongs to another pad is not).
func is_pad_bound(device: int) -> bool:
	for slot in _slots:
		var pad := slot.input as JoypadInput if slot != null else null
		if pad != null and pad.device == device and pad.is_connected_device():
			return true
	return false


## Gives the slot [param index] to [param input] (the player's controller is gone and another one takes over, or a
## test / script swaps the device). The new device must not be in use by another slot – a slot whose device WORKS: a
## ghost's stale "joy:N" is no claim on the id (it is whoever's pad is there now; the ghost reads nothing from it).
## The slot keeps its class, ready flag, loadout and hero; the press that is held on the new input is swallowed.
## Emits [signal device_reconnected].
func rebind(index: int, input: PlayerInput) -> bool:
	var slot := get_slot(index)
	if slot == null or input == null:
		return false
	var key := input.get_device_key()
	for other in _slots:
		if other != null and other != slot and other.input.get_device_key() == key and other.input.is_connected_device():
			return false
	slot.input = input
	var pad := input as JoypadInput
	if pad != null:
		slot.session_id = RemotePlay.session_of_device(pad.device)
	slot.missing_time = 0.0
	slot.connection_reported = true
	slot.idle_pads_at_loss.clear()
	input.swallow()
	device_reconnected.emit(slot)
	return true


## The free pad on [param device] takes over a missing slot: the one it provably belongs to (same Remote Play session
## or fingerprint – an identical model that was lying around when the slot's pad died, [method _is_returning_pad]),
## else the lowest. Returns that slot; null (nothing changes) when no slot is missing or the pad is not free.
func take_over(device: int) -> PlayerSlot:
	var ghost := _ghost_for_pad(device)
	if ghost == null or not is_pad_free(device):
		return null
	if not rebind(ghost.index, JoypadInput.new(device)):
		return null
	_took_over = true
	Audio.play_ui(&"ui_join")
	return ghost


## True (once) when a free pad took a slot over since the last frame: a menu that reads "any pad's A" skips the frame.
func consume_takeover() -> bool:
	var v := _took_over
	_took_over = false
	return v


## Once per frame, after the inputs polled: announces a slot's device going away or coming back, and gives a missing
## slot back to a pad that is provably its own ([method _rebind_to_returning_pad]). Counts how long each ghost has been
## missing. The loss is announced first (and the pads lying around at that moment are noted, see
## [member PlayerSlot.idle_pads_at_loss]), so a later automatic return is a visible one.
func track_connections(delta: float) -> void:
	for slot in get_slots():
		if slot.is_bot():
			continue
		if not slot.input.is_connected_device():
			slot.missing_time += delta
			if slot.connection_reported:
				slot.connection_reported = false
				slot.idle_pads_at_loss = _idle_pads()
				device_disconnected.emit(slot)
			if slot.input is JoypadInput:
				_rebind_to_returning_pad(slot)
		if slot.input.is_connected_device():
			slot.missing_time = 0.0
			slot.idle_pads_at_loss.clear()
			if not slot.connection_reported:
				slot.connection_reported = true
				device_reconnected.emit(slot)


## The fingerprints of the connected pads nobody plays.
func _idle_pads() -> Array[PadIdentity]:
	var out: Array[PadIdentity] = []
	for device in PadSource.devices():
		if not is_pad_bound(device):
			out.append(PadSource.identity(device))
	return out


## Gives [param slot] the first pad that provably is its own and CONNECTED AFTER the slot went missing: a pad that was
## already there and idle (an identical model of a spectator, a spare) cannot be the one that went away.
func _rebind_to_returning_pad(slot: PlayerSlot) -> void:
	for device in PadSource.devices():
		if slot.idle_pads_at_loss.has(PadSource.identity(device)):
			continue
		if not is_pad_bound(device) and _is_returning_pad(slot, device) and rebind(slot.index, JoypadInput.new(device)):
			return


## The missing slot the free pad on [param device] takes over: the first one it is [method _is_returning_pad] for, else
## the lowest ([method first_ghost]); null when nobody is missing.
func _ghost_for_pad(device: int) -> PlayerSlot:
	var ghosts := disconnected_slots()
	for ghost in ghosts:
		if _is_returning_pad(ghost, device):
			return ghost
	return ghosts[0] if not ghosts.is_empty() else null


## True when the free pad on [param device] provably is [param slot]'s: the same Remote Play session (a guest keeps
## their seat whatever pad Steam shows them as), or – for a local slot – the same fingerprint. Never the joypad id alone.
func _is_returning_pad(slot: PlayerSlot, device: int) -> bool:
	if RemotePlay.session_of_device(device) != slot.session_id:
		return false
	if slot.session_id != 0:
		return true
	var old := slot.identity()
	return old != null and old.same_pad(PadSource.identity(device))


## Frees pads' A presses for joining, taking a missing slot over and the "full" / "joins at the next lobby" notices,
## and joins the keyboard. A pad's edge is tracked every frame, so a button held when a slot frees up does not join.
func _scan_free_pads() -> void:
	var scanning := joining_enabled or takeover_enabled
	if not is_full():
		_full_notified.clear()
	for device in PadSource.devices():
		var key := "joy:%d" % device
		var down := PadSource.is_button_down(device, JOY_BUTTON_A)
		var pressed: bool = down and not _join_prev.get(key, false)
		_join_prev[key] = down
		if not scanning or not pressed or not is_pad_free(device):
			continue
		if first_ghost() != null:
			take_over(device)
		elif joining_enabled and not is_full():
			_join_with(JoypadInput.new(device))
		elif joining_enabled:
			if not _full_notified.get(device, false):
				_full_notified[device] = true
				join_refused.emit(device, &"full")
		else:
			join_refused.emit(device, &"in_run")
	if not joining_enabled:
		return
	var kb_down := KeyboardInput.join_key_held()
	if kb_down and not _join_prev.get("keyboard", false) and not is_full() and not is_device_used("keyboard"):
		_join_with(KeyboardInput.new())
	_join_prev["keyboard"] = kb_down


## Joins a device that was just seen pressing its join button. The input is swallowed BEFORE
## the join is announced: the press that joined must not be A for the lobby (it would ready
## the new player at once), and a stick held at that moment must not navigate.
func _join_with(input: PlayerInput) -> PlayerSlot:
	input.swallow()
	return join(input)


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	# (The signal is deferred and can describe a newer state than the moment it reports: the next read re-scans the
	# engine, and track_connections() announces what changed for the slots.)
	PadSource.invalidate()
