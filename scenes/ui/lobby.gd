class_name Lobby
extends Control
## STUB – owned by the "ui" module. See docs/ARCHITECTURE.md.

signal start_requested
signal back_requested


static func create() -> Lobby:
	return Lobby.new()
