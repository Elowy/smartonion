class_name MageFrostNova
extends AbilityEffect
## Frost Nova (GDD 6.4, Mage, Auto-cast): when an enemy gets close enough to touch the Mage
## (within trigger m of the hero's body), frost bursts out: Frost spell damage ([MageSpell],
## x power) to every enemy within radius m (x Area Size) and a freeze (stun, stun resistance
## shortens it) of freeze seconds, shown as ice on them ([MageFrozen]).
##
## Params (data/abilities/mage_frost_nova.tres): damage, int_scaling, radius, freeze (Rank
## III: +1 s), trigger, shatter_pct + shatter_radius (Rank V "Shatter": the ice bursts when
## the freeze ends for shatter_pct % of the nova's damage around each frozen enemy; each enemy
## takes one nova's shatter at most once, [member MageFrozen.shatter_group]),
## ground_duration + ground_slow + ground_freeze (Rank V "Frozen Ground": an [AbilityArea]
## that slows and freezes each newcomer once).

const GROUND_COLOR := Color(0.62, 0.88, 1.0, 0.3)

## Frozen-ground areas still running (freed at wave end / forget).
var areas: Array[Node3D] = []
## Enemies hit by the last nova (tests).
var last_hits := 0


## Auto-cast: an enemy is touching the hero (within "trigger" m of its body).
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	return touching(p, ctx.num("trigger", 0.5)) > 0


## Living enemies whose body is within [param slack] m of [param p]'s body.
static func touching(p: Player, slack: float) -> int:
	return MageSpell.enemies_in(p.get_tree(), p.global_position, Player.RADIUS + slack).size()


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var center := WeaponRunner.flat(p.global_position)
	var radius := ctx.num("radius", 3.5) * MageSpell.area_mult(p)
	var victims := MageSpell.enemies_in(p.get_tree(), center, radius)
	if victims.is_empty():
		return false
	var damage := MageSpell.damage_from(ctx, MageSpell.FROST)
	var freeze := ctx.num("freeze", 1.5)
	var shatter := damage * ctx.num("shatter_pct", 0.0) / 100.0
	var shatter_radius := ctx.num("shatter_radius", 1.5) * MageSpell.area_mult(p)
	var group: MageFrozen.ShatterGroup = MageFrozen.ShatterGroup.new() if shatter > 0.0 else null
	last_hits = 0
	for e in victims:
		if not MageSpell.is_live(e):
			continue
		p.procs.deal_raw(e, damage, MageSpell.FROST, true, &"ability")
		last_hits += 1
		MageSpell.freeze(e, p, freeze, shatter, shatter_radius, group)
	if ctx.num("ground_duration", 0.0) > 0.0:
		_frozen_ground(ctx, center)
	MageFx.frost_nova(center, radius)
	return true


func _frozen_ground(ctx: AbilityContext, center: Vector3) -> void:
	var p := ctx.player
	var area := AbilityArea.spawn(p, center, ctx.num("radius", 3.5), ctx.num("ground_duration", 4.0), GROUND_COLOR)
	if not area.is_inside_tree():
		area.free()
		return
	area.school = MageSpell.FROST
	area.tick_interval = 0.25
	area.slow_pct = ctx.num("ground_slow", 60.0)
	area.stun = ctx.num("ground_freeze", 1.0)
	MageFx.ground_frost(area)
	MageSpell.prune(areas)
	areas.append(area)


func begin_wave(_ctx: AbilityContext) -> void:
	MageSpell.free_all(areas)


func end_wave(_ctx: AbilityContext) -> void:
	MageSpell.free_all(areas)
