class_name GameOverScreen
extends Control
## STUB – owned by the "ui" module. See docs/ARCHITECTURE.md.

signal back_to_menu_requested


static func create() -> GameOverScreen:
	return GameOverScreen.new()


## Fills in the end-of-run summary from RunState (victory / defeat, waves, kills, gold).
func open(victory: bool) -> void:
	pass
