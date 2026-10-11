class_name CritDot
extends RefCounted
## Shared rule of the crit DoT Masteries – Ignite (GDD 3.2) and Deadly Poison (GDD 3.4).
## MasteryEffect.on_hit runs after the hit's damage, and most crits kill their target, so the
## DoT share of a killing crit is not lost: it spreads to the nearest living enemy within
## [constant SPREAD_RADIUS] m of the corpse (none in reach: the share is lost).

const SPREAD_RADIUS := 2.5


## The enemy a crit DoT for a hit on [param hit] goes to: the hit enemy while it lives, else
## the nearest living enemy within SPREAD_RADIUS of it. Null when there is none (or the
## target was not an enemy).
static func target_for(hit: Node3D) -> Enemy:
	var enemy := hit as Enemy if hit != null and is_instance_valid(hit) else null
	if enemy == null or not enemy.is_inside_tree():
		return null
	if not enemy.is_dead():
		return enemy
	return EnemyGrid.nearest(enemy.get_tree(), enemy.global_position, SPREAD_RADIUS)
