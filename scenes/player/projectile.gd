class_name Projectile
extends Node3D
## STUB – owned by the "player" module (used by enemies too).
## Moves in a straight line on the XZ plane; hits by distance checks against
## group &"enemies" (TEAM_PLAYERS) or &"players" (TEAM_ENEMIES).

const TEAM_PLAYERS := 0
const TEAM_ENEMIES := 1


## [param style]: &"bolt" (arcane), &"fireball", &"arrow", &"bullet", &"axe" (troll throw).
## [param attacker]: the Player that fired it (for kill credit / leech) or the Enemy.
static func create(team: int, damage: float, is_crit: bool, direction: Vector3, speed: float,
		max_range: float, pierce: int = 0, aoe_radius: float = 0.0, attacker: Node3D = null,
		style: StringName = &"bolt", color: Color = Color.WHITE) -> Projectile:
	return Projectile.new()
