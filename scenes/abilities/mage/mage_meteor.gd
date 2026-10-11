class_name MageMeteor
extends AbilityEffect
## Meteor (GDD 6.4, Mage, Active – RB / LB): calls a meteor down on the densest group of
## enemies within reach ([method BlizzardEffect.cluster_center]). After fall seconds it lands
## ([MageMeteorStrike]): heavy Fire spell damage ([MageSpell], x power) within radius m
## (x Area Size), then burning ground ([AbilityArea]) for ground_duration seconds that burns
## every tick seconds for (ground_damage + ground_int_scaling x Intellect, as a Fire spell)
## x power.
##
## Params (data/abilities/mage_meteor.tres): radius, fall, damage, int_scaling,
## ground_damage, ground_int_scaling, ground_duration (Rank III: +2 s), tick, meteors +
## meteor_pct (Rank V "Meteor Shower": 3 meteors on the 3 densest groups – or around the one
## group – at 60 % each, landing one after another), stun + ground_scale (Rank V
## "Cataclysm": the impact stuns, the burning ground is wider), auto_cast_min (bots).

## Extra meteors of a shower land this much later each.
const SHOWER_STAGGER := 0.3
## Shower targets are at least this many radii apart.
const SHOWER_SPACING := 1.5
## Bots do not call a meteor onto a spot covered this much by a running one.
const OVERLAP_SHARE := 0.75

## Meteors falling and burning grounds of this Mage (freed at wave end / forget).
var strikes: Array[Node3D] = []
var areas: Array[Node3D] = []


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or ctx.target == null:
		return false
	var radius := ctx.num("radius", 3.0)
	var count := maxi(1, roundi(ctx.num("meteors", 1.0)))
	var first := BlizzardEffect.cluster_center(ctx)
	var centers := targets_for(p.get_tree(), p.global_position, ctx.ability.cast_range, radius, first, count)
	var share := maxf(0.0, ctx.num("meteor_pct", 100.0)) / 100.0
	var impact := MageSpell.damage_from(ctx, MageSpell.FIRE) * share
	var ground := MageSpell.damage_from(ctx, MageSpell.FIRE, "ground_") * share
	_prune()
	for i in centers.size():
		var m := MageMeteorStrike.spawn(p, centers[i], ctx.num("fall", 0.9) + SHOWER_STAGGER * float(i))
		if not m.is_inside_tree():
			m.free()
			return i > 0
		m.radius = radius * MageSpell.area_mult(p)
		m.damage = impact
		m.stun = ctx.num("stun", 0.0)
		m.ground_radius = radius * maxf(0.1, ctx.num("ground_scale", 1.0))
		m.ground_duration = ctx.num("ground_duration", 4.0)
		m.ground_tick = ctx.num("tick", 0.5)
		m.ground_damage = ground
		m.landed_at.connect(_on_strike_landed)
		strikes.append(m)
	return true


## Where the meteors of one cast land: [param first] (the densest group), then the
## next-densest groups at least SHOWER_SPACING radii from the chosen ones, then spots
## around [param first] when there are no more groups.
static func targets_for(tree: SceneTree, here: Vector3, reach: float, radius: float, first: Vector3,
		count: int) -> Array[Vector3]:
	var out: Array[Vector3] = [WeaponRunner.flat(first)]
	var spacing := radius * SHOWER_SPACING
	var pool := MageSpell.enemies_in(tree, here, reach, false)
	while out.size() < count:
		var best := Vector3.ZERO
		var best_n := 0
		for e in pool:
			var pos := WeaponRunner.flat(e.global_position)
			var apart := true
			for c in out:
				if pos.distance_to(c) < spacing:
					apart = false
					break
			if not apart:
				continue
			var n := EnemyGrid.count_around(tree, pos, radius)
			if n > best_n:
				best_n = n
				best = pos
		if best_n == 0:
			break
		out.append(best)
	var ring := count - out.size()
	for k in ring:
		var a := TAU * float(k) / float(ring) + 0.6
		out.append(out[0] + Vector3(cos(a), 0.0, sin(a)) * radius * 1.2)
	return out


## Bots: at least auto_cast_min enemies under the impact, not where one of my meteors or
## burning grounds already is.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or ctx.target == null:
		return false
	var radius := ctx.num("radius", 3.0) * MageSpell.area_mult(p)
	var center := BlizzardEffect.cluster_center(ctx)
	if MageSpell.enemies_in(p.get_tree(), center, radius).size() < int(ctx.num("auto_cast_min", 4.0)):
		return false
	_prune()
	for n in strikes + areas:
		if WeaponRunner.flat(n.global_position - center).length() < radius * OVERLAP_SHARE:
			return false
	return true


func begin_wave(_ctx: AbilityContext) -> void:
	MageSpell.free_all(strikes)
	MageSpell.free_all(areas)


func end_wave(_ctx: AbilityContext) -> void:
	MageSpell.free_all(strikes)
	MageSpell.free_all(areas)


func _on_strike_landed(m: MageMeteorStrike) -> void:
	if is_instance_valid(m) and m.ground != null and is_instance_valid(m.ground):
		areas.append(m.ground)


func _prune() -> void:
	MageSpell.prune(strikes)
	MageSpell.prune(areas)
