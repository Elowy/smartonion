class_name HunterKit
extends RefCounted
## Small helpers shared by the Hunter kit (GDD 3.7, M8): the weapon the abilities are based on,
## enemy queries, the companion / Mastery lookup, a safe landing spot for Backstep and the
## "densest second group" of Crossfire Barrage. Weapon-based numbers use
## [method GeneralKit.weapon_damage] ("W": the main-hand hit normalised to a 1 s swing, so a slow
## crossbow and a fast bow give the same ability damage for the same weapon DPS).

const FOCUS_ID := &"focus"
const PHYSICAL := &"physical"
const FIRE := &"fire"
## Metres an arrow starts in front of the hero's centre (past the body).
const MUZZLE_GAP := 0.15


## The weapon the arrows are based on: the main hand, else the off hand (null = bare hands).
static func weapon(player: Player) -> WeaponData:
	if player == null:
		return null
	return player.main_hand if player.main_hand != null else player.off_hand


## One 100 % hit ("W") of [param player] as [param school] damage (see GeneralKit.weapon_damage).
static func hit_damage(player: Player, school: StringName = PHYSICAL) -> float:
	return GeneralKit.weapon_damage(player, school)


## The Focus pool of [param player] (null for a hero without one).
static func focus(player: Player) -> ClassResource:
	if player == null or player.abilities == null:
		return null
	return player.abilities.get_resource(FOCUS_ID)


## The Hunter Mastery (Beastbond) of [param player] (null for any other class).
static func mastery(player: Player) -> HunterMastery:
	if player == null or player.abilities == null:
		return null
	return player.abilities.mastery as HunterMastery


## The living companion of [param player] (null: none yet, other class, freed).
static func companion(player: Player) -> HunterCompanion:
	var m := mastery(player)
	return m.companion if m != null and m.has_companion() else null


## The effect object of the Hunter ability [param id] on [param player] (null when not slotted).
static func effect_of(player: Player, id: StringName) -> AbilityEffect:
	if player == null or player.abilities == null:
		return null
	var index := player.abilities.slot_of(id)
	return player.abilities.effect_for(player.abilities.slots[index]) if index >= 0 else null


## True when a talent / set script forces the crit of a weapon-hit ability on [param target]
## (PlayerBonuses.crit_forced; [param target] may be null). Asked before the crit roll, so
## without such a script the RunState.rng draws are unchanged (the Knife Bloom rule).
static func bonus_crit(player: Player, target: Node3D) -> bool:
	return player != null and player.bonuses != null and player.bonuses.crit_forced(target)


## True while [param e] is a living enemy in the tree.
static func is_live(e: Variant) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	var enemy := e as Enemy
	return enemy != null and enemy.is_inside_tree() and not enemy.is_dead() and not enemy.is_queued_for_deletion()


## Unit vector (XZ) from [param from] to [param to]; [param fallback] when they coincide.
static func dir_to(from: Vector3, to: Vector3, fallback: Vector3 = Vector3.FORWARD) -> Vector3:
	var d := WeaponRunner.flat(to - from)
	if d.length_squared() < 0.0001:
		d = WeaponRunner.flat(fallback)
	if d.length_squared() < 0.0001:
		d = Vector3.FORWARD
	return d.normalized()


## Living enemies within [param radius] of [param center] by body (XZ), nearest first.
static func enemies_near_point(tree: SceneTree, center: Vector3, radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in GeneralKit.enemies_around(tree, center, radius):
		out.append(e)
	out.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return GeneralKit.flat_distance(a.global_position, center) < GeneralKit.flat_distance(b.global_position, center))
	return out


## Enemies whose centre is within [param radius] of [param center] and inside the cone of
## [param half_angle_deg] degrees around [param dir] (unit, XZ).
static func enemies_in_cone(tree: SceneTree, center: Vector3, dir: Vector3, radius: float, half_angle_deg: float) -> int:
	var n := 0
	var cos_limit := cos(deg_to_rad(half_angle_deg))
	for node in EnemyGrid.gather_around(tree, center, radius):
		var e := node as Enemy
		if not is_live(e):
			continue
		var to := WeaponRunner.flat(e.global_position - center)
		var dist := to.length()
		if dist > radius:
			continue
		if dist < 0.001 or to.normalized().dot(dir) >= cos_limit:
			n += 1
	return n


## The enemy within [param reach] of the hero with the most neighbours within [param radius] that
## is at least [param gap] x [param radius] from [param first] (null = no other group): the
## second hail of Crossfire Barrage.
static func second_cluster(player: Player, first: Vector3, radius: float, reach: float, gap: float = 1.5) -> Variant:
	var tree := player.get_tree()
	var best: Enemy = null
	var best_count := 0
	for node in EnemyGrid.gather_around(tree, player.global_position, reach):
		var e := node as Enemy
		if not is_live(e):
			continue
		if GeneralKit.flat_distance(e.global_position, player.global_position) > reach:
			continue
		if GeneralKit.flat_distance(e.global_position, first) < radius * gap:
			continue
		var count := EnemyGrid.count_around(tree, e.global_position, radius)
		if count > best_count:
			best_count = count
			best = e
	return Vector3(best.global_position.x, 0.0, best.global_position.z) if best != null else null


## Where a hop of [param distance] m from [param from] along [param dir] (unit, XZ) lands: kept in
## the arena and the shared screen's walk rectangle and short of solid walls (the same limits as
## the walk). [param from] itself when the way is blocked.
static func landing(player: Player, from: Vector3, dir: Vector3, distance: float) -> Vector3:
	var flat := WeaponRunner.flat(dir)
	if flat.length_squared() < 0.0001 or distance <= 0.0:
		return from
	flat = flat.normalized()
	var margin := Player.RADIUS + Player.WALL_GAP
	var to := from + flat * distance
	var arena := Arena.current
	if arena != null and is_instance_valid(arena):
		to = arena.clamp_point(to, margin)
		if is_instance_valid(arena.camera) and arena.camera.is_inside_tree() and player != null:
			var walk := arena.camera.get_walk_rect(player)
			if walk.size.x >= 0.0:
				to = Player.keep_inside_from(from, to, walk)
	if player != null and player.is_inside_tree() and to.distance_squared_to(from) > 0.01:
		var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.5, to + Vector3.UP * 0.5,
				Player.COLLISION_MASK_WORLD)
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var stop: Vector3 = hit["position"]
			to = Vector3(stop.x - flat.x * margin, from.y, stop.z - flat.z * margin)
			if (to - from).dot(flat) < 0.0:
				to = from
	to.y = from.y
	return to


## A faint flat ground ring of [param radius] m under [param parent] (a hero, a pet): its own
## Mats.ring material (the owner recolours it with Mats.set_ring), unshaded, no shadow. The
## caller frees it.
static func ground_ring(parent: Node3D, color: Color, radius: float, alpha: float = 0.5,
		inner: float = 0.86, outer: float = 0.97, fill: float = 0.2) -> MeshInstance3D:
	if parent == null or not is_instance_valid(parent):
		return null
	var mi := MeshInstance3D.new()
	mi.name = "HunterRing"
	var quad := PlaneMesh.new()
	quad.size = Vector2(2.0 * radius, 2.0 * radius)
	mi.mesh = quad
	mi.material_override = Mats.ring()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, 0.05, 0.0)
	Mats.set_ring(mi, Color(color.r, color.g, color.b, alpha), inner, outer, fill)
	parent.add_child(mi)
	return mi
