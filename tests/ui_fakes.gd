extends RefCounted
## Shared helpers for the "ui" module tests (test_ui_*.gd). Not a test file (no test_ prefix).
##   const UiFakes := preload("res://tests/ui_fakes.gd")


## A human-like scripted device: unlike ScriptedInput, PlayerSlot.is_bot() is false for it,
## and it can pretend to be unplugged.
class HumanInput extends PlayerInput:
	var held: Dictionary[int, bool] = {}
	var move := Vector2.ZERO
	var key := "human"
	var connected := true

	func _init(p_key: String = "human") -> void:
		key = p_key

	func get_device_name() -> String:
		return "Test Pad"

	func get_device_key() -> String:
		return key

	func is_connected_device() -> bool:
		return connected

	func get_move() -> Vector2:
		return move

	func press(button: PlayerInput.Pad) -> void:
		held[button] = true

	func release(button: PlayerInput.Pad) -> void:
		held[button] = false

	func _read_buttons() -> Dictionary[int, bool]:
		return held.duplicate()


## Resets PlayerManager (no slots, joining off, no grace: an unplugged HumanInput is "absent" for the between-wave
## screens at once, as these tests assume – the grace has its own tests in test_rpt_core.gd).
static func reset_players() -> void:
	PlayerManager.clear()
	PlayerManager.joining_enabled = false
	PlayerManager.auto_decide_grace = 0.0


## One frame: polls every slot's input (what PlayerManager does) then runs the screen.
static func step(screen: Node, delta: float = 1.0 / 60.0) -> void:
	for slot in PlayerManager.get_slots():
		slot.input.poll(delta)
	screen.call(&"_process", delta)


## Press + frame, release + frame (the second frame has delta 0 so timers do not move).
static func tap(screen: Node, input: PlayerInput, button: PlayerInput.Pad, delta: float = 1.0 / 60.0) -> void:
	input.call(&"press", button)
	step(screen, delta)
	input.call(&"release", button)
	step(screen, 0.0)


## Pushes the stick for one frame then centres it again.
static func nudge(screen: Node, input: PlayerInput, direction: Vector2) -> void:
	input.set(&"move", direction)
	step(screen)
	input.set(&"move", Vector2.ZERO)
	step(screen, 0.0)


static func add_to_root(tree: SceneTree, node: Node) -> Node:
	tree.root.add_child(node)
	return node


## Untyped on purpose: callers may pass an already freed node (a typed Node parameter would
## raise a script error before is_instance_valid() could reject it).
static func free_node(node: Variant) -> void:
	if node != null and is_instance_valid(node) and node is Node:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
