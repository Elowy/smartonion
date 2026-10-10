class_name MainMenu
extends Control
## STUB – owned by the "ui" module. See docs/ARCHITECTURE.md.

signal play_pressed
signal quit_pressed


static func create() -> MainMenu:
	return MainMenu.new()
