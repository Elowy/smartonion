class_name ScriptedInput
extends PlayerInput
## Input driven from code: tests set [member move] and [member held] directly.

var move := Vector2.ZERO
var aim := Vector2.ZERO
var held: Dictionary[int, bool] = {}
var device_key := "scripted"


func _init(p_key: String = "scripted") -> void:
	device_key = p_key


func get_device_name() -> String:
	return "Bot"


func get_device_key() -> String:
	return device_key


func get_move() -> Vector2:
	return move.limit_length(1.0)


func get_aim() -> Vector2:
	return aim


func press(button: PlayerInput.Pad) -> void:
	held[button] = true


func release(button: PlayerInput.Pad) -> void:
	held[button] = false


func _read_buttons() -> Dictionary[int, bool]:
	return held.duplicate()
