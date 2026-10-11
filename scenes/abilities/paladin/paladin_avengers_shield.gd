class_name PaladinAvengersShield
extends AbilityEffect
## Avenger's Shield (GDD 6.4, Paladin Auto): hurls a holy shield at the nearest enemy that
## ricochets from enemy to enemy – [code]targets[/code] (3) enemies, the nearest one not hit
## yet within PaladinHolyMissile.RICOCHET_RANGE each time – for [code]damage_pct[/code] % of
## the main-hand hit + [code]spell_power_scale[/code] x Spell Power as Holy damage each (x power).
##
## Params: damage_pct, spell_power_scale, targets (Rank III: +1), speed, slow / slow_duration
## (spec "Dazing Shield": +2 targets, struck enemies are slowed), absorb_max_hp /
## absorb_duration (spec "Bulwark": every enemy struck gives the Paladin an absorb shield worth
## that % of its max HP).

const DEFAULT_SPEED := 18.0
const EXTRA_FLIGHT := 3.0
## Bots / auto-cast wait for this many enemies within the cast range (the shield is wasted on
## a lone enemy unless it is the only one around for a while) ...
const AUTO_MIN_ENEMIES := 2
## ... but a single enemy this close is worth it.
const AUTO_CLOSE_RANGE := 4.0


static func shield_damage(ctx: AbilityContext) -> float:
	return PaladinKit.strike_damage(ctx.player, ctx.num("damage_pct", 100.0), ctx.num("spell_power_scale", 0.8),
			ctx.num("power", 1.0))


## Absorb shield the Paladin gains per enemy struck (0 without the Bulwark spec).
static func absorb_per_hit(ctx: AbilityContext) -> float:
	var pct := ctx.num("absorb_max_hp")
	if pct <= 0.0 or ctx.player == null:
		return 0.0
	return ctx.player.max_hp() * pct / 100.0 * ctx.num("power", 1.0)


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if ctx.target == null or p == null or not p.is_inside_tree():
		return false
	if PaladinKit.flat_distance(ctx.target.global_position, p.global_position) <= AUTO_CLOSE_RANGE:
		return true
	return EnemyGrid.count_around(p.get_tree(), p.global_position, ctx.ability.cast_range) >= AUTO_MIN_ENEMIES


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	var target := ctx.target as Enemy
	if p == null or not p.is_inside_tree() or target == null or target.is_dead():
		return false
	var m := PaladinHolyMissile.throw(p, target, ctx.direction, shield_damage(ctx),
			maxi(1, roundi(ctx.num("targets", 3.0))), ctx.ability.cast_range + EXTRA_FLIGHT,
			ctx.num("speed", DEFAULT_SPEED), PaladinHolyMissile.Look.SHIELD)
	if m == null:
		return false
	m.slow_pct = ctx.num("slow")
	m.slow_duration = ctx.num("slow_duration", 3.0)
	m.absorb_per_hit = absorb_per_hit(ctx)
	m.absorb_duration = ctx.num("absorb_duration", 6.0)
	return true
