extends Control
## A stand-in for WARDROBE's LookPicker (M9 PATCH tests): the contract the Loadout screen embeds – a static
## create(slot), a signal closed and an optional handle_input(inp). Not a test file (no test_ prefix).

signal closed

var slot: PlayerSlot
var pressed: Array[int] = []


static func create(p_slot: PlayerSlot) -> Control:
	var f: Control = load("res://tests/fake_look_picker.gd").new()
	f.slot = p_slot
	return f


func handle_input(inp: PlayerInput) -> void:
	if inp.just_pressed(PlayerInput.Pad.A):
		pressed.append(PlayerInput.Pad.A)
	if inp.just_pressed(PlayerInput.Pad.B):
		closed.emit()
