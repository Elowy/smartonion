class_name BotInput
extends ScriptedInput
## Very small kiting AI used by smoke runs (--smoke) and screenshot/demo mode.
## Steers away from nearby enemies, towards dropped loot, and back towards the arena centre.

var body: Node3D
var _wander := Vector2.ZERO
var _wander_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _init(p_key: String = "bot", p_seed: int = 0) -> void:
	super(p_key)
	_rng.seed = p_seed


func get_device_name() -> String:
	return "Bot"


func poll(delta: float) -> void:
	_think(delta)
	super(delta)


func _think(delta: float) -> void:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		move = Vector2.ZERO
		return
	var pos := Vector2(body.global_position.x, body.global_position.z)
	var steer := Vector2.ZERO
	for e in body.get_tree().get_nodes_in_group(&"enemies"):
		var n := e as Node3D
		if n == null:
			continue
		var d := pos - Vector2(n.global_position.x, n.global_position.z)
		var dist := d.length()
		if dist < 6.0 and dist > 0.001:
			steer += d / dist * (6.0 - dist)
	var best_loot := Vector2.ZERO
	var best_dist := 9.0
	for p in body.get_tree().get_nodes_in_group(&"pickups"):
		var n := p as Node3D
		if n == null:
			continue
		var d := Vector2(n.global_position.x, n.global_position.z) - pos
		if d.length() < best_dist:
			best_dist = d.length()
			best_loot = d.normalized()
	steer += best_loot * 1.5
	steer += -pos * 0.04  # drift back to the centre
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = _rng.randf_range(0.8, 2.0)
		_wander = Vector2.from_angle(_rng.randf() * TAU) * 0.6
	steer += _wander
	move = steer.normalized() if steer.length() > 0.05 else Vector2.ZERO
