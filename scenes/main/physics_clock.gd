class_name PhysicsClock
extends Node
## Times every physics tick for RunPerf (dev harness). A pair of nodes: this one runs first
## in the physics tick (lowest process_physics_priority), its child [code]End[/code] last.
## Pausable: nothing is measured while the tree is paused.

## [param step_ms]: the previous whole tick (scripts + physics server), measured start to
## start inside one frame; -1 when the previous tick was in another frame.
## [param script_ms]: the node _physics_process part of this tick.
signal tick_measured(step_ms: float, script_ms: float)

var _end: _End
var _tick_start := 0
var _prev_start := 0
var _prev_frame := -1
var _pending_step := -1.0


static func create() -> PhysicsClock:
	var c := PhysicsClock.new()
	c.name = "PhysicsClock"
	c.process_mode = Node.PROCESS_MODE_PAUSABLE
	c.process_physics_priority = -1000000
	c._end = _End.new()
	c._end.name = "End"
	c._end.clock = c
	c._end.process_physics_priority = 1000000
	c.add_child(c._end)
	return c


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame := Engine.get_process_frames()
	_pending_step = (now - _prev_start) / 1000.0 if frame == _prev_frame else -1.0
	_prev_start = now
	_prev_frame = frame
	_tick_start = now


func _finish_tick() -> void:
	tick_measured.emit(_pending_step, (Time.get_ticks_usec() - _tick_start) / 1000.0)


class _End extends Node:
	var clock: PhysicsClock

	func _physics_process(_delta: float) -> void:
		clock._finish_tick()
