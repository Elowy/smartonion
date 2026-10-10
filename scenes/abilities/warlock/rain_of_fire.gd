class_name WarlockRainOfFire
extends AbilityEffect
## Rain of Fire (GDD 3.5, RT, 1 Soul Shard): fire rains on the densest group of enemies – an
## [AbilityArea] of [code]radius[/code] m (x Area Size) that burns everything inside every
## [code]tick[/code] seconds for [code]duration[/code] seconds, with falling-meteor VFX
## ([WarlockRainOfFireVfx]).
##
## Params: radius, duration, tick, damage (fire per tick), intellect_scale (per tick per point
## of Intellect), spell_power_scale (per second per point of Spell Power – normalised like
## weapon power, so faster ticks do not multiply it), auto_cast_min (bots: enemies in the
## circle).

const GROUND_COLOR := Color(1.0, 0.36, 0.06, 0.3)

## The last circle this Warlock called down (bots do not stack a second one on it).
var last_area: AbilityArea


## Fire damage of one tick for [param stats] with [param params] (before the target bonuses,
## Mastery and the owner's outgoing multipliers, which ProcSystem.deal_raw applies).
static func tick_damage(stats: StatBlock, params: Dictionary, school: StringName = &"fire") -> float:
	var tick := float(params.get("tick", 0.5))
	var flat := float(params.get("damage", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.INTELLECT)) * float(params.get("intellect_scale", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.SPELL_POWER)) * float(params.get("spell_power_scale", 0.0)) * tick
	return maxf(CombatMath.MIN_DAMAGE, flat * CombatMath.damage_mult_for(stats, school))


## Living enemies whose body touches the circle at [param center] (XZ).
static func enemies_in_circle(tree: SceneTree, center: Vector3, radius: float) -> int:
	var count := 0
	for node in EnemyGrid.gather_around(tree, center, radius):
		var e := node as Enemy
		if e == null or not e.is_inside_tree() or e.is_dead():
			continue
		var reach := radius + e.radius
		if WeaponRunner.flat(e.global_position - center).length_squared() <= reach * reach:
			count += 1
	return count


## Needs a cluster to rain on (no shard is spent into the void).
func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or ctx.target == null:
		return false
	var area := AbilityArea.spawn(p, ctx.point, ctx.num("radius", 3.0), ctx.num("duration", 4.0), GROUND_COLOR)
	if not area.is_inside_tree():
		area.free()
		return false
	area.school = ctx.ability.school
	area.tick_interval = maxf(0.1, ctx.num("tick", 0.5))
	area.damage_per_tick = tick_damage(p.stats, ctx.params, ctx.ability.school)
	area.add_child(WarlockRainOfFireVfx.create(area.radius, area.duration))
	last_area = area
	return true


## Bots: at least auto_cast_min enemies under the circle, and not on top of a running one.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or ctx.target == null:
		return false
	var radius := ctx.num("radius", 3.0) * CombatMath.area_mult(p.stats)
	if is_instance_valid(last_area) and last_area.is_inside_tree() and not last_area.is_queued_for_deletion() \
			and WeaponRunner.flat(last_area.global_position - ctx.point).length() < last_area.radius * 0.75:
		return false
	return enemies_in_circle(p.get_tree(), ctx.point, radius) >= int(ctx.num("auto_cast_min", 4.0))
