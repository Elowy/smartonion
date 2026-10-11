class_name RogueUtil
extends RefCounted
## Small helpers shared by the Rogue kit (Fan of Knives, Vanish, Deadly Poison, the learned
## M4 abilities, bots): weapon damage, enemy queries and the teleports' landing spots.

const COMBO_ID := &"combo_points"
const ENERGY_ID := &"energy"
## Damage of a weapon hit when the Rogue holds no weapon (bare fists): this + Agility.
const FALLBACK_DAMAGE := 3.0
## Gap (m) left between a teleporting Rogue's body and its target's body.
const TELEPORT_GAP := 0.15


## Whole Combo Points the player holds (the resource is a float; a Resource Regen bonus can
## leave a fraction on it).
static func combo_points(player: Player) -> int:
	if player == null or player.abilities == null:
		return 0
	var combo := player.abilities.get_resource(COMBO_ID)
	return floori(combo.value + 0.0001) if combo != null else 0


## Living enemies whose centre is within [param radius] metres (XZ) of the player.
static func enemies_within(player: Player, radius: float) -> int:
	if player == null or not player.is_inside_tree():
		return 0
	var center := player.global_position
	var count := 0
	for node in EnemyGrid.gather_around(player.get_tree(), center, radius):
		var e := node as Enemy
		if e == null or e.is_dead():
			continue
		var d := WeaponRunner.flat(e.global_position - center)
		if d.length_squared() <= radius * radius:
			count += 1
	return count


## The weapon the Rogue's abilities are based on: the main hand, else the off hand.
static func weapon(player: Player) -> WeaponData:
	if player == null:
		return null
	return player.main_hand if player.main_hand != null else player.off_hand


## One 100 % hit of the Rogue's weapon ([method weapon]) dealt as [param school] damage (that
## school's damage % instead of the weapon's), before crits, target bonuses and the outgoing
## multipliers. Without a weapon: FALLBACK_DAMAGE + Agility.
static func weapon_damage(player: Player, school: StringName = CombatMath.SCHOOL_PHYSICAL) -> float:
	if player == null:
		return CombatMath.MIN_DAMAGE
	var w := weapon(player)
	var base := CombatMath.weapon_base_damage(w, player.stats) if w != null \
			else FALLBACK_DAMAGE + maxf(0.0, player.stats.get_raw(Stats.AGILITY))
	return maxf(CombatMath.MIN_DAMAGE, base * CombatMath.damage_mult_for(player.stats, school))


## Crit multiplier of the Rogue's weapon (x2 without one).
static func crit_mult(player: Player) -> float:
	return CombatMath.crit_multiplier(weapon(player), player.stats) if player != null else 2.0


## Living enemies whose body touches the circle of [param radius] around [param center] (XZ),
## in group order.
static func enemies_around(tree: SceneTree, center: Vector3, radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if tree == null:
		return out
	for node in EnemyGrid.gather_around(tree, center, radius):
		var e := node as Enemy
		if e == null or not e.is_inside_tree() or e.is_dead():
			continue
		var dx := e.global_position.x - center.x
		var dz := e.global_position.z - center.z
		var reach := radius + e.radius
		if dx * dx + dz * dz <= reach * reach:
			out.append(e)
	return out


## Up to [param count] living enemies whose centre is within [param radius] of
## [param center] (XZ), nearest first (ties: group order), skipping the instance ids in
## [param exclude].
static func nearest_enemies(tree: SceneTree, center: Vector3, radius: float, count: int,
		exclude: Dictionary[int, bool] = {}) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if tree == null or count <= 0:
		return out
	var dists: Array[float] = []
	var r_sq := radius * radius
	for node in EnemyGrid.gather_around(tree, center, radius):
		var e := node as Enemy
		if e == null or not e.is_inside_tree() or exclude.has(e.get_instance_id()) or e.is_dead():
			continue
		var dx := e.global_position.x - center.x
		var dz := e.global_position.z - center.z
		var d := dx * dx + dz * dz
		if d > r_sq:
			continue
		var at := dists.size()
		while at > 0 and dists[at - 1] > d:
			at -= 1
		if at >= count:
			continue
		dists.insert(at, d)
		out.insert(at, e)
		if out.size() > count:
			out.resize(count)
			dists.resize(count)
	return out


## [param to] limited to the arena and the shared screen's walk rectangle, as the walk does it
## ([param from] is where the body came from: a body already outside a limit is never pushed
## further out).
static func keep_in_play_area(player: Player, from: Vector3, to: Vector3) -> Vector3:
	var arena := Arena.current
	if arena == null or not is_instance_valid(arena):
		return to
	var out := arena.clamp_point(to, Player.RADIUS + Player.WALL_GAP)
	if player != null and is_instance_valid(arena.camera) and arena.camera.is_inside_tree():
		var walk := arena.camera.get_walk_rect(player)
		if walk.size.x >= 0.0:
			out = Player.keep_inside_from(from, out, walk)
	out.y = from.y
	return out


## Where [param player] lands when it steps "behind" [param target]: on the far side of the
## target as seen from [param from] (the player's position before the step), just outside the
## target's body; kept inside the arena / the shared screen and short of solid props between
## the target and that spot.
static func spot_behind(player: Player, target: Node3D, from: Vector3) -> Vector3:
	var center := target.global_position
	var dir := WeaponRunner.flat(center - from)
	if dir.length_squared() < 0.0001:
		dir = WeaponRunner.flat(player.facing) if player != null else Vector3.FORWARD
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var enemy := target as Enemy
	var offset := (enemy.radius if enemy != null else 0.45) + Player.RADIUS + TELEPORT_GAP
	var to := Vector3(center.x, from.y, center.z) + dir * offset
	if player != null and player.is_inside_tree():
		var query := PhysicsRayQueryParameters3D.create(Vector3(center.x, 0.5, center.z),
				Vector3(to.x, 0.5, to.z), Player.COLLISION_MASK_WORLD)
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var stop: Vector3 = hit["position"]
			to = Vector3(stop.x, from.y, stop.z) - dir * (Player.RADIUS + Player.WALL_GAP)
	return keep_in_play_area(player, from, to)


## Moves [param player] to [param to] at once (a teleport: no sliding, no velocity left).
static func teleport(player: Player, to: Vector3) -> void:
	if player.is_inside_tree():
		player.global_position = to
	else:
		player.position = to
	player.velocity = Vector3.ZERO
