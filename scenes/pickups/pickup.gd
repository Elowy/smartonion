class_name Pickup
extends Node3D
## STUB – owned by the "enemies" module.
## Loot dropped by enemies: gold for the shared wallet + team XP (GDD 10).
## Group &"pickups". Flies to the nearest living player within its pickup range.

var gold := 0
var xp := 0


static func create(p_gold: int, p_xp: int) -> Pickup:
	var p := Pickup.new()
	p.gold = p_gold
	p.xp = p_xp
	return p


## Wave end: credits the loot to the team without a collector, then frees itself.
func collect_to_bank() -> void:
	RunState.add_gold(gold)
	RunState.add_xp(xp)
	queue_free()
