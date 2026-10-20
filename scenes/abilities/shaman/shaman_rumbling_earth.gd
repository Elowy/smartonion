class_name ShamanRumblingEarth
extends AbilityEffect
## Rumbling Earth (M8, Shaman Active): splits the ground under the densest group of enemies within reach –
## a [ShamanQuake] of [code]radius[/code] m that deals Nature damage to everything inside every [code]tick[/code]
## s for [code]duration[/code] s; each enemy has a stun_chance % chance (one RunState.rng draw, on its first
## tick) to be stunned for [code]stun[/code] s. Ability damage; quake ticks are not Storm Echo eligible.
##
## Params: damage, intellect_scale, spell_power_scale (per tick; the Spell Power part counts per second, so
## x tick), radius, duration, tick, stun_chance, stun, slow (Faultline: % slow inside), quakes (Twin Fissures:
## a second quake opens under the next-densest group that the first does not cover), auto_cast_min (bot
## rule). "power" (Ranks II / IV) scales the damage. Elemental Surge: one charge per cast, baked into every
## tick of every quake of the cast.
## Bot rule: at least auto_cast_min enemies in the cluster and none of the Shaman's running quakes covers
## OVERLAP_SHARE of the new circle.
## Rank III: +1 m radius. Rank V: Faultline (slow 50%) or Twin Fissures (a second quake).

const COLOR := Color(0.7, 0.55, 0.35, 0.4)
const DEFAULT_RADIUS := 4.0
## Bots do not open a quake on one that still covers this share of the new radius.
const OVERLAP_SHARE := 0.6

var _areas: Array[ShamanQuake] = []


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null and ctx.player != null and ctx.player.is_inside_tree()


func wants_auto_cast(ctx: AbilityContext) -> bool:
	if ctx.target == null or not ctx.target.is_inside_tree() or ctx.player == null:
		return false
	var radius := _area_radius(ctx)
	var centre := ctx.target.global_position
	if ShamanKit.count_around(ctx.target.get_tree(), centre, radius) < roundi(ctx.num("auto_cast_min", 4.0)):
		return false
	_prune()
	for a in _areas:
		if ShamanKit.flat_distance(a.global_position, centre) < a.radius * OVERLAP_SHARE:
			return false
	return true


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or ctx.target == null or not ctx.target.is_inside_tree():
		return false
	var empower := ShamanKit.empower(p)
	var tick := maxf(0.05, ctx.num("tick", 0.5))
	var tick_damage := ShamanKit.spell_damage(p.stats, ctx.params, ShamanKit.NATURE, tick) * empower
	var centres: Array[Vector3] = [ctx.target.global_position]
	var want := maxi(1, roundi(ctx.num("quakes", 1.0)))
	var radius := _area_radius(ctx)
	while centres.size() < want:
		var next := _next_centre(p.get_tree(), p.global_position, ctx.ability.cast_range, radius, centres)
		if next.is_empty():
			break
		centres.append(next[0])
	var opened := 0
	for centre in centres:
		var area := ShamanQuake.open(p, centre, ctx.num("radius", DEFAULT_RADIUS), ctx.num("duration", 5.0), COLOR)
		if not area.is_inside_tree():
			area.free()
			continue
		area.school = ShamanKit.NATURE
		area.tick_interval = tick
		area.damage_per_tick = tick_damage
		area.slow_pct = ctx.num("slow")
		area.stun_chance = ctx.num("stun_chance")
		area.stun_time = ctx.num("stun", 1.2)
		_areas.append(area)
		opened += 1
	if opened == 0:
		return false
	Vfx.explosion(WeaponRunner.flat(centres[0]) + Vector3.UP * 0.1, minf(radius, 2.5), ShamanKit.EARTH_COLOR)
	p.face_attack(WeaponRunner.flat(centres[0] - p.global_position))
	return true


## The quakes of this Shaman still running (freed ones pruned).
func running() -> Array[ShamanQuake]:
	_prune()
	var out: Array[ShamanQuake] = []
	out.assign(_areas)
	return out


func begin_wave(_ctx: AbilityContext) -> void:
	_areas.clear()


func end_wave(_ctx: AbilityContext) -> void:
	_areas.clear()


## The quake radius with the owner's Area Size.
func _area_radius(ctx: AbilityContext) -> float:
	return ctx.num("radius", DEFAULT_RADIUS) * CombatMath.area_mult(ctx.player.stats)


## The centre of the densest group within [param reach] of [param from] that is not covered by the quakes
## already planned at [param taken] (their centres are at least a radius away); empty when there is none.
static func _next_centre(tree: SceneTree, from: Vector3, reach: float, radius: float, taken: Array[Vector3]) -> Array[Vector3]:
	var best: Array[Vector3] = []
	var best_count := 0
	var reach_sq := reach * reach
	for node in EnemyGrid.gather_around(tree, from, reach):
		var e := node as Enemy
		if not ShamanKit.is_live(e) or WeaponRunner.flat(e.global_position - from).length_squared() > reach_sq:
			continue
		var covered := false
		for c in taken:
			if ShamanKit.flat_distance(e.global_position, c) < radius:
				covered = true
				break
		if covered:
			continue
		var count := EnemyGrid.count_around(tree, e.global_position, radius)
		if count > best_count:
			best_count = count
			best = [e.global_position]
	return best


func _prune() -> void:
	for i in range(_areas.size() - 1, -1, -1):
		# Check validity on the element itself: a freed area must not be copied to a typed var.
		if not is_instance_valid(_areas[i]) or not _areas[i].is_inside_tree() or _areas[i].is_queued_for_deletion():
			_areas.remove_at(i)
