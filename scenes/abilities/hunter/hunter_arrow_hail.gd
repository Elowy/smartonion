class_name HunterArrowHail
extends AbilityEffect
## Arrow Hail (GDD 3.7, Hunter Active, 12 s): arrows rain on the densest group of enemies within
## the cast range – an [AbilityArea] of [code]radius[/code] (3) m (x Area Size) that hits every
## enemy inside every [code]tick[/code] (0.5) s for [code]duration[/code] (4) s, each tick
## [code]damage_pct[/code] (40) % of the weapon hit "W" x "power" as physical ability damage
## (no crits), with falling-arrow VFX ([HunterArrowHailVfx]). [code]slow[/code] % slows the
## enemies inside (Pinning Hail).
## Ranks (M4): Rank III +1 m radius; Rank V "Crossfire Barrage" ([code]storms[/code] 2: a second
## hail on the next-densest group at least 1.5 radii away) or "Pinning Hail" ([code]slow[/code] +40).
## Bots shoot when at least [code]auto_cast_min[/code] (4) enemies stand in the circle and no hail
## of theirs already covers the spot.

const GROUND_COLOR := Color(1.0, 0.7, 0.28, 0.26)
## A second hail lands this many radii (at least) from the first one.
const SECOND_GAP := 1.5

## The last circle this Hunter called down (bots do not stack a second one on it) and the second
## one of Crossfire Barrage.
var last_area: AbilityArea
var second_area: AbilityArea


## Physical damage of one tick of [param player]'s hail with [param params] (before the target
## bonuses, Mastery and the owner's outgoing multipliers, which ProcSystem.deal_raw applies).
static func tick_damage(player: Player, params: Dictionary) -> float:
	return HunterKit.hit_damage(player, HunterKit.PHYSICAL) * float(params.get("damage_pct", 40.0)) / 100.0 \
			* float(params.get("power", 1.0))


## Needs a cluster to rain on.
func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or ctx.target == null:
		return false
	var area := _hail(ctx, ctx.point)
	if area == null:
		return false
	last_area = area
	second_area = null
	if roundi(ctx.num("storms", 1.0)) >= 2:
		var second: Variant = HunterKit.second_cluster(player, ctx.point, area.radius, ctx.ability.cast_range, SECOND_GAP)
		if second != null:
			second_area = _hail(ctx, second)
	return true


## A hail circle at [param center] (null when it could not be placed).
func _hail(ctx: AbilityContext, center: Vector3) -> AbilityArea:
	var player := ctx.player
	var area := AbilityArea.spawn(player, center, ctx.num("radius", 3.0), ctx.num("duration", 4.0), GROUND_COLOR)
	if not area.is_inside_tree():
		area.free()
		return null
	area.school = HunterKit.PHYSICAL
	area.tick_interval = maxf(0.1, ctx.num("tick", 0.5))
	area.damage_per_tick = tick_damage(player, ctx.params)
	area.slow_pct = clampf(ctx.num("slow", 0.0), 0.0, 90.0)
	area.add_child(HunterArrowHailVfx.create(area.radius, area.duration))
	return area


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or ctx.target == null:
		return false
	var radius := ctx.num("radius", 3.0) * CombatMath.area_mult(player.stats)
	if is_instance_valid(last_area) and last_area.is_inside_tree() and not last_area.is_queued_for_deletion() \
			and GeneralKit.flat_distance(last_area.global_position, ctx.point) < last_area.radius * 0.75:
		return false
	return GeneralKit.cluster_size(player.get_tree(), ctx.point, radius) >= int(ctx.num("auto_cast_min", 4.0))


## Wave start: the old circle no longer blocks the bots.
func begin_wave(_ctx: AbilityContext) -> void:
	last_area = null
	second_area = null
