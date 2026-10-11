class_name WarriorKit
extends RefCounted
## Shared helpers of the Warrior kit (Whirlwind, Charge, Battle Fury): weapon damage, enemy
## queries around the hero and the free run-up in front of it.

## Damage of a main-hand hit when the hero has no weapon (bare fists).
const FALLBACK_DAMAGE := 3.0


## Damage of one main-hand weapon hit (100%), before crits and target bonuses. Abilities
## multiply it by their percentage and deal it with ProcSystem.deal_raw.
static func weapon_damage(player: Player) -> float:
	if player == null:
		return CombatMath.MIN_DAMAGE
	if player.main_hand != null:
		return CombatMath.weapon_hit_damage(player.main_hand, player.stats)
	var base := FALLBACK_DAMAGE + player.stats.get_raw(Stats.STRENGTH)
	return maxf(CombatMath.MIN_DAMAGE, base * CombatMath.damage_mult_for(player.stats, &"physical"))


## Living enemies whose body touches the circle of [param radius] around [param center] (XZ).
static func enemies_around(tree: SceneTree, center: Vector3, radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if tree == null:
		return out
	for node in EnemyGrid.gather_around(tree, center, radius):
		var e := node as Enemy
		if e == null or e.is_dead():
			continue
		var dx := e.global_position.x - center.x
		var dz := e.global_position.z - center.z
		var reach := radius + e.radius
		if dx * dx + dz * dz <= reach * reach:
			out.append(e)
	return out


## [method enemies_around] centred on [param player].
static func enemies_within(player: Player, radius: float) -> Array[Enemy]:
	if player == null or not player.is_inside_tree():
		return []
	return enemies_around(player.get_tree(), player.global_position, radius)


## How far (m, at most [param wanted]) [param player] can run along [param dir] before it hits
## the arena bounds or the edge of the shared screen (the same limits the walk uses).
static func free_distance(player: Player, dir: Vector3, wanted: float) -> float:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if player == null or flat.length_squared() < 0.0001:
		return 0.0
	flat = flat.normalized()
	var arena := Arena.current
	if arena == null or not is_instance_valid(arena):
		return wanted
	var start := player.global_position
	var limit := wanted
	var margin := Player.RADIUS + Player.WALL_GAP
	limit = minf(limit, _ray_to_rect(start, flat, arena.get_bounds().grow(-margin)))
	var walk := _walk_rect(arena, player)
	if walk.size.x >= 0.0:
		limit = minf(limit, _ray_to_rect(start, flat, walk))
	return maxf(0.0, limit)


## [param to] limited to the arena and the shared screen, as the walk does it ([param from] is
## where the body came from: a body already outside a limit is never pushed further out).
static func keep_in_play_area(player: Player, from: Vector3, to: Vector3) -> Vector3:
	var arena := Arena.current
	if arena == null or not is_instance_valid(arena):
		return to
	var out := arena.clamp_point(to, Player.RADIUS + Player.WALL_GAP)
	var walk := _walk_rect(arena, player)
	if walk.size.x >= 0.0:
		out = Player.keep_inside_from(from, out, walk)
	return out


## Distance along [param dir] (unit, XZ) from [param start] to the edge of [param rect]; 0 when
## already outside on the way out.
static func _ray_to_rect(start: Vector3, dir: Vector3, rect: Rect2) -> float:
	var t := INF
	if dir.x > 0.0001:
		t = minf(t, (rect.end.x - start.x) / dir.x)
	elif dir.x < -0.0001:
		t = minf(t, (rect.position.x - start.x) / dir.x)
	if dir.z > 0.0001:
		t = minf(t, (rect.end.y - start.z) / dir.z)
	elif dir.z < -0.0001:
		t = minf(t, (rect.position.y - start.z) / dir.z)
	return maxf(0.0, t)


static func _walk_rect(arena: Arena, player: Player) -> Rect2:
	if not is_instance_valid(arena.camera) or not arena.camera.is_inside_tree():
		return Rect2(0.0, 0.0, -1.0, -1.0)
	return arena.camera.get_walk_rect(player)
