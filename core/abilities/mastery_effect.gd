class_name MasteryEffect
extends RefCounted
## A class's Mastery (GDD 3) and passive class hooks (pets, auras). Referenced by
## ClassData.mastery (a script extending this). Mastery points: player.stats.get_raw(Stats.MASTERY).

var player: Player


## Once, when the player is created (spawn pets, connect signals).
func setup(_player: Player) -> void:
	player = _player


func mastery() -> float:
	return player.stats.get_raw(Stats.MASTERY) if player != null else 0.0


## Multiplier for this player's outgoing damage. [param source]: &"weapon", &"proc", &"dot",
## &"ability", &"pet". [param target] may be null.
func damage_mult(_target: Node3D, _school: StringName, _source: StringName) -> float:
	return 1.0


## A weapon hit landed (after damage).
func on_hit(_target: Node3D, _damage: float, _is_crit: bool) -> void:
	pass


func on_kill(_enemy: Node3D) -> void:
	pass


func on_damage_taken(_amount: float) -> void:
	pass


func begin_wave() -> void:
	pass


## Every physics frame while the player is alive (auras).
func tick(_delta: float) -> void:
	pass


## Called when the player is about to be freed (free pets).
func teardown() -> void:
	pass


## Tooltip text, e.g. "Battle Fury: +x% damage per 10% missing health".
func describe() -> String:
	return ""
