class_name EnemyModel
extends Node3D
## STUB – owned by the "visuals" module.
## Procedural enemy look per EnemyData.model_style (skeleton, candlekin, gurgler, troll).
## Origin at the feet, faces -Z, scaled by data.model_scale.


func setup(data: EnemyData) -> void:
	pass


func set_facing(direction: Vector3) -> void:
	pass


func set_moving(speed_ratio: float) -> void:
	pass


func flash_hit() -> void:
	pass


## Wind-up tell before a lunge / throw.
func play_windup() -> void:
	pass


func play_attack() -> void:
	pass


## Visual stun indicator (stars / daze).
func set_stunned(stunned: bool) -> void:
	pass
