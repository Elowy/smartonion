class_name Enemy
extends CharacterBody3D
## STUB – owned by the "enemies" module.
## A hostile unit (GDD 8). Group &"enemies". Collision layer 3 ("enemies"),
## mask 1 | 3 (world + other enemies, for natural crowd separation).

signal died(enemy: Enemy, killer_index: int)

var data: EnemyData
var wave := 1
var hp := 1.0
var max_hp := 1.0
var radius := 0.45
var model: EnemyModel


static func create(p_data: EnemyData, p_wave: int) -> Enemy:
	var e := Enemy.new()
	e.data = p_data
	e.wave = p_wave
	return e


func is_dead() -> bool:
	return hp <= 0.0


## [param attacker] is the Player (or null). [param knockback] is a world-space impulse.
func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null,
		knockback: Vector3 = Vector3.ZERO) -> void:
	pass


func apply_stun(duration: float) -> void:
	pass


## Removes the enemy without loot (wave end).
func despawn() -> void:
	queue_free()
