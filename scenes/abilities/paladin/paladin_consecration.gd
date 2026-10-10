class_name PaladinConsecration
extends AbilityEffect
## Consecration (GDD 3.3, RT): golden holy ground under the Paladin that burns enemies inside
## every [code]tick[/code] seconds for [code]duration[/code] seconds (AbilityArea).
##
## Params: radius, duration, tick, damage (holy per tick), strength_scale (per tick per point of
## Strength), spell_power_scale (per second per point of Spell Power – normalised like weapon
## power, so faster ticks do not multiply it), follows (Sabatons of the Dawn: the ground moves
## with the Paladin).

const GROUND_COLOR := Color(1.0, 0.84, 0.35, 0.3)
## Bots cast it when an enemy is this close (share of the radius).
const AUTO_CAST_REACH := 0.9


## Holy damage of one tick for [param stats] with [param params] (before the target bonuses,
## Mastery and the owner's outgoing multipliers, which ProcSystem.deal_raw applies).
static func tick_damage(stats: StatBlock, params: Dictionary, school: StringName = &"holy") -> float:
	var tick := float(params.get("tick", 0.5))
	var flat := float(params.get("damage", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.STRENGTH)) * float(params.get("strength_scale", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.SPELL_POWER)) * float(params.get("spell_power_scale", 0.0)) * tick
	return maxf(CombatMath.MIN_DAMAGE, flat * CombatMath.damage_mult_for(stats, school))


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var area := AbilityArea.spawn(p, p.global_position, ctx.num("radius", 3.0), ctx.num("duration", 4.0), GROUND_COLOR)
	if not area.is_inside_tree():
		area.free()
		return false
	area.school = ctx.ability.school
	area.tick_interval = maxf(0.1, ctx.num("tick", 0.5))
	area.damage_per_tick = tick_damage(p.stats, ctx.params, ctx.ability.school)
	if ctx.flag("follows"):
		area.follow = p
	area.add_child(ConsecrationVfx.create(area.radius, area.duration))
	return true


## Bots: an enemy stands (almost) inside the ground it would cover.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var reach := ctx.num("radius", 3.0) * AUTO_CAST_REACH \
			* (1.0 + p.stats.get_raw(Stats.AREA_SIZE) / 100.0)
	return EnemyGrid.nearest(p.get_tree(), p.global_position, reach) != null
