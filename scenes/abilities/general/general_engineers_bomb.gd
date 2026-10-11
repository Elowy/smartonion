class_name GeneralEngineersBomb
extends AbilityEffect
## Engineer's Bomb (GDD 6.4, general Auto-cast): throws a bomb ([GeneralBombShell]) at the
## densest group of enemies within cast range; it lands after flight_time seconds and
## explodes for Fire spell damage in a radius m circle:
##   damage + primary stat x primary_scale + the better of Attack / Spell Power
##   (GeneralKit.spell_damage, x power; Area Size scales the radius).
## Auto-cast: only when at least min_cluster enemies stand in the circle around the target.
##
## Params (rank / spec / item mods change them):
##   damage, primary_scale, radius, flight_time, min_cluster
##   bombs            bombs per cast (Rank III: +1 – the next one goes to the next densest
##                    group, or next to the first when there is none)
##   bomblets, bomblet_pct, bomblet_radius     Cluster Bomb (spec)
##   burn_duration, burn_pct, burn_tick        Incendiary Bomb (spec)

const FIRE := &"fire"
const DEFAULT_RADIUS := 2.5
## A second bomb without a second group lands this share of the radius beside the first.
const SPREAD_SHARE := 1.1

## Bombs still in flight (tests, end_wave).
var bombs: Array[GeneralBombShell] = []


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


func wants_auto_cast(ctx: AbilityContext) -> bool:
	if ctx.target == null or not ctx.target.is_inside_tree():
		return false
	var r := ctx.num("radius", DEFAULT_RADIUS)
	var center := GeneralKit.cluster_center(ctx.target, r)
	return GeneralKit.cluster_size(ctx.target.get_tree(), center, r) >= maxi(1, roundi(ctx.num("min_cluster", 2.0)))


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or ctx.target == null or not ctx.target.is_inside_tree():
		return false
	var payload := payload_for(ctx)
	var hand := player.global_position + Vector3.UP * GeneralBombShell.HAND_HEIGHT
	_prune()
	var thrown := false
	for point in landing_points(ctx):
		var b := GeneralBombShell.throw(player, hand, point, payload)
		if not b.is_inside_tree():
			b.free()
			continue
		bombs.append(b)
		thrown = true
	return thrown


func begin_wave(_ctx: AbilityContext) -> void:
	_drop_bombs()


func end_wave(_ctx: AbilityContext) -> void:
	_drop_bombs()


## Damage of one bomb (x power), before target bonuses and outgoing multipliers.
static func bomb_damage(ctx: AbilityContext) -> float:
	return GeneralKit.spell_damage(ctx.player, ctx.num("damage", 8.0), ctx.num("primary_scale", 0.75), FIRE) \
			* ctx.num("power", 1.0)


## What every bomb of a cast carries (final numbers).
static func payload_for(ctx: AbilityContext) -> Dictionary:
	var area := CombatMath.area_mult(ctx.player.stats)
	return {
		"damage": bomb_damage(ctx),
		"radius": ctx.num("radius", DEFAULT_RADIUS) * area,
		"flight_time": ctx.num("flight_time", 0.55),
		"bomblets": maxi(0, roundi(ctx.num("bomblets"))),
		"bomblet_pct": ctx.num("bomblet_pct", 40.0),
		"bomblet_radius": ctx.num("bomblet_radius", 1.4) * area,
		"burn_duration": ctx.num("burn_duration"),
		"burn_pct": ctx.num("burn_pct", 15.0),
		"burn_tick": ctx.num("burn_tick", 0.5),
	}


## Landing spots of a cast: the cluster around the target first, then the densest other groups
## within cast range (enemies already covered by an earlier bomb do not count), else beside
## the first spot.
static func landing_points(ctx: AbilityContext) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var r := ctx.num("radius", DEFAULT_RADIUS)
	var count := maxi(1, roundi(ctx.num("bombs", 1.0)))
	out.append(GeneralKit.cluster_center(ctx.target, r))
	var tree := ctx.target.get_tree()
	var here := ctx.player.global_position
	while out.size() < count:
		var best: Enemy = null
		var best_count := 0
		for node in EnemyGrid.gather_around(tree, here, ctx.ability.cast_range):
			var e := node as Enemy
			if e == null or e.is_dead() or not e.is_inside_tree():
				continue
			if GeneralKit.flat_distance(e.global_position, here) > ctx.ability.cast_range:
				continue
			if _covered(e.global_position, out, r):
				continue
			var n := GeneralKit.cluster_size(tree, e.global_position, r)
			if n > best_count:
				best_count = n
				best = e
		if best != null:
			out.append(Vector3(best.global_position.x, 0.0, best.global_position.z))
		else:
			# No other group: beside the first spot, away from the thrower.
			var away := out[0] - here
			away.y = 0.0
			if away.length_squared() < 0.0001:
				away = Vector3.FORWARD
			var side := Vector3(away.z, 0.0, -away.x).normalized()
			var side_sign := 1.0 if out.size() % 2 == 1 else -1.0
			out.append(out[0] + side * side_sign * r * SPREAD_SHARE * ceilf(out.size() / 2.0))
	return out


static func _covered(pos: Vector3, points: Array[Vector3], radius: float) -> bool:
	for p in points:
		if GeneralKit.flat_distance(pos, p) <= radius:
			return true
	return false


func _prune() -> void:
	for i in range(bombs.size() - 1, -1, -1):
		if not is_instance_valid(bombs[i]) or bombs[i].is_queued_for_deletion():
			bombs.remove_at(i)


func _drop_bombs() -> void:
	for i in bombs.size():
		if is_instance_valid(bombs[i]) and not bombs[i].is_queued_for_deletion():
			bombs[i].queue_free()
	bombs.clear()
