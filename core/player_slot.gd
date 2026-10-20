class_name PlayerSlot
extends RefCounted
## One joined local player: which device drives it, which class it plays, its colour.

var index: int
var input: PlayerInput
var class_data: ClassData
var color: Color
## Lobby "ready" flag; also reused by the between-wave screen.
var ready := false
## The spawned Player node during a run (null outside of a run).
var player: Node3D
## The companion picked in the lobby (an id of ClassData.companion_choices; &"" = none picked).
## Read the effective choice through [method companion_id]: it stays valid when the class changes.
var companion: StringName = &""


func _init(p_index: int, p_input: PlayerInput, p_color: Color) -> void:
	index = p_index
	input = p_input
	color = p_color


func label() -> String:
	return "P%d" % (index + 1)


func is_bot() -> bool:
	return input is ScriptedInput


## The companion this player gets (Player.companion_id): [member companion] when the class offers
## it, else the class's first choice; &"" for a class without companions.
func companion_id() -> StringName:
	return class_data.pick_companion(companion) if class_data != null else &""


## Picks the next ([param step] 1) or previous (-1) companion of the class (wraps) and returns it;
## &"" and no change for a class without companions.
func cycle_companion(step: int = 1) -> StringName:
	if class_data == null or class_data.companion_choices.is_empty():
		return &""
	var choices := class_data.companion_choices
	var at := choices.find(companion_id())
	companion = choices[wrapi(at + step, 0, choices.size())]
	return companion
