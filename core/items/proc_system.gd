class_name ProcSystem
extends Node
## STUB – owned by the "procs" agent. Runs a player's enchantments and unique item effects
## (GDD 5.7): ON_HIT with PPM chance per hit (ppm x weapon cooldown / 60), ON_KILL /
## WHEN_STRUCK with a % chance, internal cooldowns, proc damage scaling with Spell Power /
## Attack Power, no proc chains. Child node of its Player ("Procs").


static func create(owner_player: Player) -> ProcSystem:
	return ProcSystem.new()


## Rebuilds the active enchant list from the player's equipment (call on equipment.changed).
func refresh() -> void:
	pass


## A weapon hit landed (not called for proc damage).
func on_hit(target: Node3D, damage: float, weapon: WeaponData, is_crit: bool) -> void:
	pass


func on_kill(enemy: Node3D) -> void:
	pass


## The player took a hit (after dodge / block).
func on_struck(attacker: Node3D, damage: float) -> void:
	pass
