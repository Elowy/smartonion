class_name WaveDirector
extends Node
## STUB – owned by the "enemies" module.
## Runs one wave at a time (GDD 1, 9): timer, telegraphed spawns, co-op scaling.

signal wave_started(wave: int)
signal wave_timer_changed(seconds_left: float)
signal wave_cleared(wave: int)

const MAX_ENEMIES := 150

var arena: Arena
var time_left := 0.0


static func create(p_arena: Arena) -> WaveDirector:
	var d := WaveDirector.new()
	d.arena = p_arena
	return d


func is_running() -> bool:
	return false


func start_wave(wave: int) -> void:
	pass


## Stops spawning, removes remaining enemies (no loot) and banks dropped pickups.
func stop() -> void:
	pass
