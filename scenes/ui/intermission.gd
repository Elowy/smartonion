class_name Intermission
extends Control
## STUB – owned by the "ui" module. See docs/ARCHITECTURE.md.

signal continue_requested


static func create() -> Intermission:
	return Intermission.new()


## Shows the screen for the wave that was just cleared. Players ready up with A.
func open(cleared_wave: int, level_ups: int) -> void:
	pass
