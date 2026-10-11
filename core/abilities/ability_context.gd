class_name AbilityContext
extends RefCounted
## Everything an AbilityEffect needs for one cast.

var player: Player
var ability: AbilityData
## Ability rank 0..4 (Rank I..V, M4); 0 in M3.
var rank := 0
## The ability's params with item mods (ability_mod) and rank bonuses applied.
var params: Dictionary = {}
## Resolved target (enemy, ally or null) and aim point / direction on the ground.
var target: Node3D
var point := Vector3.ZERO
var direction := Vector3.FORWARD
var rng: RandomNumberGenerator


## A numeric param (after mods).
func num(key: String, default: float = 0.0) -> float:
	var v: Variant = params.get(key, default)
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else default


func flag(key: String) -> bool:
	return bool(params.get(key, false))
