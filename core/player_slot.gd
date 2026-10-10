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


func _init(p_index: int, p_input: PlayerInput, p_color: Color) -> void:
	index = p_index
	input = p_input
	color = p_color


func label() -> String:
	return "P%d" % (index + 1)


func is_bot() -> bool:
	return input is ScriptedInput
