class_name WarriorKit
extends RefCounted
## Shared helpers of the Warrior kit (Whirlwind, Charge, Battle Fury and the M4 abilities):
## weapon damage, enemy queries around the hero, the free run-up in front of it, landing
## spots, knockback and Rage gains.

## Damage of a main-hand hit when the hero has no weapon (bare fists).
const FALLBACK_DAMAGE := 3.0
const RAGE := &"rage"
## Landing spots inside a prop are moved back towards the take-off in steps of this (m).
const LANDING_STEP := 0.4


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


## Living enemies around [param player] (within [param radius], bodies counted) inside the
## [param arc_degrees] wedge centred on [param direction] (XZ). 360 or more = the full circle.
static func enemies_in_arc(player: Player, radius: float, direction: Vector3, arc_degrees: float) -> Array[Enemy]:
	var all := enemies_within(player, radius)
	if arc_degrees >= 360.0:
		return all
	var dir := Vector3(direction.x, 0.0, direction.z)
	if dir.length_squared() < 0.0001:
		return all
	dir = dir.normalized()
	var min_dot := cos(deg_to_rad(clampf(arc_degrees, 0.0, 360.0) * 0.5))
	var here := player.global_position
	var out: Array[Enemy] = []
	for e in all:
		var to := Vector3(e.global_position.x - here.x, 0.0, e.global_position.z - here.z)
		var dist := to.length()
		# A body overlapping the hero always counts; else the centre must lie in the wedge.
		if dist <= Player.RADIUS + e.radius or to.dot(dir) >= min_dot * dist:
			out.append(e)
	return out


## +[param amount] Rage for [param player] (Resource Regen applies like any gain).
static func add_rage(player: Player, amount: float) -> void:
	if player == null or player.abilities == null or amount <= 0.0:
		return
	var rage := player.abilities.get_resource(RAGE)
	if rage != null:
		rage.add(amount)


## Pushes [param e] away from [param from] like a weapon knockback of [param strength]
## (the enemy's knockback resistance applies).
static func knock_back(e: Enemy, from: Vector3, strength: float) -> void:
	if e == null or not is_instance_valid(e) or e.is_dead() or strength <= 0.0:
		return
	var away := Vector3(e.global_position.x - from.x, 0.0, e.global_position.z - from.z)
	if away.length_squared() < 0.0001:
		away = Vector3.RIGHT
	var resist := clampf(e.data.knockback_resist, 0.0, 1.0) if e.data != null else 0.0
	var push := away.normalized() * strength * Enemy.KNOCKBACK_VELOCITY_PER_UNIT * (1.0 - resist)
	e.knockback_velocity = (e.knockback_velocity + push).limit_length(Enemy.MAX_KNOCKBACK_SPEED)


## Where [param player] coming from [param from] can land near [param to]: inside the arena
## and the shared screen, and – when [param to] is inside a prop – moved back towards
## [param from] until the body fits (at worst [param from]).
static func landing_spot(player: Player, from: Vector3, to: Vector3) -> Vector3:
	var dest := keep_in_play_area(player, from, Vector3(to.x, from.y, to.z))
	dest.y = from.y
	if player == null or not player.is_inside_tree():
		return dest
	var back := Vector3(from.x - dest.x, 0.0, from.z - dest.z)
	var length := back.length()
	var steps := ceili(length / LANDING_STEP)
	for i in steps + 1:
		var spot := dest + (back * (float(i) / float(steps)) if steps > 0 else Vector3.ZERO)
		if body_fits(player, spot):
			return spot
	return from


## True when the hero's body at [param pos] touches no world geometry (props, walls).
static func body_fits(player: Player, pos: Vector3) -> bool:
	if player == null or not player.is_inside_tree():
		return true
	var shape := CapsuleShape3D.new()
	shape.radius = Player.RADIUS
	shape.height = Player.BODY_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, Vector3(pos.x, pos.y + Player.BODY_HEIGHT * 0.5, pos.z))
	query.collision_mask = Player.COLLISION_MASK_WORLD
	query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## The living enemy within [param reach] of [param player] with the most other enemies within
## [param radius] of it (ties: the first found), null when none. [param min_count] = fewest
## enemies (itself included) the group must have.
static func densest_enemy(player: Player, reach: float, radius: float, min_count: int = 1) -> Enemy:
	if player == null or not player.is_inside_tree():
		return null
	var tree := player.get_tree()
	var best: Enemy = null
	var best_count := maxi(0, min_count - 1)
	for node in EnemyGrid.gather_around(tree, player.global_position, reach):
		var e := node as Enemy
		if e == null or e.is_dead():
			continue
		if WeaponRunner.flat(e.global_position - player.global_position).length() > reach:
			continue
		var count := EnemyGrid.count_around(tree, e.global_position, radius)
		if count > best_count:
			best_count = count
			best = e
	return best


## True when [param e] is an elite or a boss.
static func is_big(e: Enemy) -> bool:
	return e != null and is_instance_valid(e) and e.is_elite()


## A short "skill name" text over the hero's head.
static func shout_text(player: Player, text: String, color: Color) -> void:
	if player == null or not player.is_inside_tree():
		return
	Vfx.floating_text(player.self_text_position(1.0), text, color, Player.SELF_TEXT_SIZE, 1.0)
