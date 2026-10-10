class_name Hud
extends Control
## STUB – owned by the "ui" module.
## In-run HUD: WoW-style unit frames in the screen corners (one per player), wave counter +
## timer and shared gold at the top, shared XP bar at the bottom, level-up banner.


static func create() -> Hud:
	return Hud.new()


## Connects the unit frames to the spawned players.
func bind_players(players: Array[Player]) -> void:
	pass


func set_wave_time(seconds_left: float) -> void:
	pass


## Big centred banner ("Wave 3", "Wave cleared!", "LEVEL UP!").
func show_banner(text: String, color: Color = UiTheme.GOLD) -> void:
	pass


## e.g. "Controller disconnected – P2: reconnect or press A on another controller".
func show_notice(text: String) -> void:
	pass


func hide_notice() -> void:
	pass
