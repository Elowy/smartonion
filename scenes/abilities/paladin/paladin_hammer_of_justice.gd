class_name PaladinHammerOfJustice
extends AbilityEffect
## Hammer of Justice (GDD 6.4, Paladin Auto): throws a holy hammer at the nearest enemy that is
## not stunned yet (else the nearest): [code]damage_pct[/code] % of the main-hand hit +
## [code]spell_power_scale[/code] x Spell Power as Holy damage (x power), and a
## [code]stun[/code] second stun. The hammer homes in on its target (PaladinHolyMissile).
##
## Params: damage_pct, spell_power_scale, stun, hammers (Rank III: +1 = a second target),
## speed, impact_radius (spec "Shattering Hammer": the impact bursts – every enemy around
## takes the damage and the stun), execute_below / execute_bonus (spec "Wrathful Hammer":
## +% damage against enemies below that % of their HP) and kill_cdr (every killing blow takes
## that many seconds off the running cooldown).

const DEFAULT_SPEED := 16.0
## Metres the hammer may fly beyond the cast range (homing on a moving target).
const EXTRA_FLIGHT := 3.0


## The enemies the hammers go for: nearest first, enemies that are not stunned before stunned
## ones; at most [param count].
static func targets_for(ctx: AbilityContext, count: int) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var p := ctx.player
	if p == null or not p.is_inside_tree() or count <= 0:
		return out
	for e in PaladinKit.enemies_by_distance(p.get_tree(), p.global_position, ctx.ability.cast_range, true):
		out.append(e)
		if out.size() >= count:
			break
	return out


## Holy damage of one hammer for [param ctx] (Rank II / IV power included).
static func hammer_damage(ctx: AbilityContext) -> float:
	return PaladinKit.strike_damage(ctx.player, ctx.num("damage_pct", 150.0), ctx.num("spell_power_scale", 1.0),
			ctx.num("power", 1.0))


## An enemy in range (the default needs ctx.target from NEAREST_ENEMY targeting).
func wants_auto_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var targets := targets_for(ctx, maxi(1, roundi(ctx.num("hammers", 1.0))))
	if targets.is_empty():
		return false
	var damage := hammer_damage(ctx)
	var thrown := 0
	for e in targets:
		var m := PaladinHolyMissile.throw(p, e, ctx.direction, damage, 1, ctx.ability.cast_range + EXTRA_FLIGHT,
				ctx.num("speed", DEFAULT_SPEED), PaladinHolyMissile.Look.HAMMER)
		if m == null:
			continue
		m.stun = ctx.num("stun", 1.5)
		m.aoe_radius = maxf(0.0, ctx.num("impact_radius")) * CombatMath.area_mult(p.stats)
		m.execute_below = ctx.num("execute_below") / 100.0
		m.execute_bonus = ctx.num("execute_bonus")
		if ctx.num("kill_cdr") > 0.0:
			m.on_kill = _on_kill.bind(p, ctx.ability, ctx.num("kill_cdr"))
		thrown += 1
	return thrown > 0


## "Wrathful Hammer": a killing blow takes [param seconds] off the running cooldown.
func _on_kill(paladin: Player, ability: AbilityData, seconds: float) -> void:
	if not is_instance_valid(paladin) or paladin.abilities == null:
		return
	var slot := paladin.abilities.slot_of(ability.id)
	if slot < 0:
		return
	var left := paladin.abilities.remaining(slot)
	if left > 0.0:
		paladin.abilities.set_cooldown(ability, left - seconds)
