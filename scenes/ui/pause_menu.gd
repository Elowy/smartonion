class_name PauseMenu
extends Control
## STUB – owned by the "ui" module. See docs/ARCHITECTURE.md.

signal resume_requested
signal quit_to_menu_requested


static func create() -> PauseMenu:
	return PauseMenu.new()


## [param slot] is the player who paused (only they can navigate; any START resumes).
func open(slot: PlayerSlot) -> void:
	pass
