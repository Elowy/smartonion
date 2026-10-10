class_name BlizzardEffect
extends AbilityEffect
## Mage ability Blizzard (GDD 3.2): hail on the densest group of enemies within reach – an
## [AbilityArea] of frost that ticks spell damage and slows everything inside for a few
## seconds. The numbers are params of data/abilities/mage_blizzard.tres:
##   radius (m), duration (s), tick (s), damage + int_scaling x Intellect (per tick, base),
##   slow (%). Items change them through ability_mod (e.g. Frostweave Cowl: radius_pct +30).

const FROST := &"frost"
const AREA_COLOR := Color(0.55, 0.85, 1.0, 0.35)
const DEFAULT_RADIUS := 3.5
const DEFAULT_DURATION := 3.0
const DEFAULT_TICK := 0.5
## Bots only cast on a group this big.
const BOT_MIN_CLUSTER := 4
## Bots do not stack a new Blizzard on one that still covers this share of the new radius.
const OVERLAP_SHARE := 0.6

## My running areas (bots check them so they do not stack Blizzards on one spot).
var _areas: Array[AbilityArea] = []


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


func cast(ctx: AbilityContext) -> bool:
	if ctx.target == null or ctx.player == null:
		return false
	var center := cluster_center(ctx)
	var area := AbilityArea.spawn(ctx.player, center, ctx.num("radius", DEFAULT_RADIUS),
			ctx.num("duration", DEFAULT_DURATION), AREA_COLOR)
	if not area.is_inside_tree():
		area.free()
		return false
	area.school = FROST
	area.tick_interval = maxf(0.05, ctx.num("tick", DEFAULT_TICK))
	area.damage_per_tick = tick_damage(ctx)
	area.slow_pct = ctx.num("slow", 0.0)
	BlizzardShards.attach(area)
	_areas.append(area)
	return true


func wants_auto_cast(ctx: AbilityContext) -> bool:
	if ctx.target == null or not ctx.target.is_inside_tree():
		return false
	var radius := ctx.num("radius", DEFAULT_RADIUS)
	var center := cluster_center(ctx)
	if cluster_size(ctx.target.get_tree(), center, radius) < BOT_MIN_CLUSTER:
		return false
	_prune()
	for a in _areas:
		if a.global_position.distance_to(center) < a.radius * OVERLAP_SHARE:
			return false
	return true


## Damage of one tick (Frost spell: base + Intellect scaling, Spell Power, Versatility, school %).
static func tick_damage(ctx: AbilityContext) -> float:
	var base := ctx.num("damage") + ctx.num("int_scaling") * ctx.player.stats.get_raw(Stats.INTELLECT)
	return CombatMath.proc_damage(base, FROST, ctx.player.stats)


## Where the hail falls: the centroid of the enemies around the targeted one – or that
## enemy's own position when it covers more of them.
static func cluster_center(ctx: AbilityContext) -> Vector3:
	var target := ctx.target
	if target == null or not target.is_inside_tree():
		return ctx.point
	var tree := target.get_tree()
	var radius := ctx.num("radius", DEFAULT_RADIUS)
	var sum := Vector3.ZERO
	var count := 0
	for node in EnemyGrid.gather_around(tree, target.global_position, radius):
		var e := node as Enemy
		if e == null or e.is_dead():
			continue
		sum += e.global_position
		count += 1
	if count == 0:
		return target.global_position
	var centroid := Vector3(sum.x / count, 0.0, sum.z / count)
	var on_target := Vector3(target.global_position.x, 0.0, target.global_position.z)
	if cluster_size(tree, on_target, radius) > cluster_size(tree, centroid, radius):
		return on_target
	return centroid


## Living enemies within [param radius] of [param center].
static func cluster_size(tree: SceneTree, center: Vector3, radius: float) -> int:
	var n := 0
	for node in EnemyGrid.gather_around(tree, center, radius):
		var e := node as Enemy
		if e != null and not e.is_dead() and e.global_position.distance_to(center) <= radius:
			n += 1
	return n


func _prune() -> void:
	for i in range(_areas.size() - 1, -1, -1):
		# Check validity on the element itself: a freed area must not be copied to a typed var.
		if not is_instance_valid(_areas[i]) or not _areas[i].is_inside_tree():
			_areas.remove_at(i)
