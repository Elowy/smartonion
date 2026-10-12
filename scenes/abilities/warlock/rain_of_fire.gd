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
## circle), follows (Walking Inferno: the circle centres on the Warlock and moves with it),
## storms (Twin Storms: 2 = a second circle on the next-densest group at least
## [constant SECOND_STORM_GAP] radii away). "power" (Ranks II / IV) scales the damage.
## Rank III: +1 m radius. Rank V: Walking Inferno or Twin Storms.
##
## Talent params (M5, neutral defaults in warlock_rain_of_fire.tres):
## - slow (Aftermath): % slow on enemies inside the circle (AbilityArea.slow_pct, refreshed
##   every tick).
## - wild_imps, wild_imp_duration, wild_imp_power (%), wild_imp_max (Wild Imps): a successful
##   cast also summons roundi(wild_imps) Wild Imps (WarlockImp.spawn_wild) for
##   wild_imp_duration seconds that fight like the Imp for wild_imp_power % of its bolt
##   damage; once per cast (Twin Storms too); beyond wild_imp_max alive the oldest leave. They
##   are dismissed at wave start / end and with the Warlock.
## - ember_duration, ember_share (%), ember_slow (%) (Conflagrate): the circle lasts
##   ember_duration seconds longer as burning ground – a [WarlockEmbers] child switches it,
##   when the rain ends, to ember_share % of its tick damage, at least ember_slow % slow, no
##   longer following the Warlock, meta &"embers" (bots rain again instead of waiting).

const GROUND_COLOR := Color(1.0, 0.36, 0.06, 0.3)
## A second storm lands this many radii (at least) from the first one.
const SECOND_STORM_GAP := 1.5
const INFERNAL_ID := &"summon_infernal"
## Wild Imps: orbit spots around the Warlock (the permanent Imp keeps back-left).
const WILD_SLOTS := 4

## The last circle this Warlock called down (bots do not stack a second one on it).
var last_area: AbilityArea
## Living Wild Imps, oldest first (tests, the wild_imp_max cap).
var wild: Array[WarlockImp] = []


## Fire damage of one tick for [param stats] with [param params] (before the target bonuses,
## Mastery and the owner's outgoing multipliers, which ProcSystem.deal_raw applies).
static func tick_damage(stats: StatBlock, params: Dictionary, school: StringName = &"fire") -> float:
	var tick := float(params.get("tick", 0.5))
	var flat := float(params.get("damage", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.INTELLECT)) * float(params.get("intellect_scale", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.SPELL_POWER)) * float(params.get("spell_power_scale", 0.0)) * tick
	return maxf(CombatMath.MIN_DAMAGE, flat * CombatMath.damage_mult_for(stats, school) * WarlockSpell.power(params))


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
	var follows := ctx.flag("follows")
	var center := p.global_position if follows else ctx.point
	var area := _rain(ctx, center)
	if area == null:
		return false
	if follows:
		area.follow = p
	last_area = area
	if roundi(ctx.num("storms", 1.0)) >= 2 and not follows:
		var second: Variant = second_center(p, ctx.point, area.radius, ctx.ability.cast_range)
		if second != null:
			_rain(ctx, second)
	var imps := roundi(ctx.num("wild_imps", 0.0))
	if imps > 0:
		_summon_wild_imps(p, imps, ctx.num("wild_imp_duration", 6.0), ctx.num("wild_imp_power", 50.0) / 100.0,
				maxi(1, roundi(ctx.num("wild_imp_max", 4.0))), area.global_position)
	return true


## A burning circle at [param center] (null when it could not be placed).
func _rain(ctx: AbilityContext, center: Vector3) -> AbilityArea:
	var p := ctx.player
	var area := AbilityArea.spawn(p, center, ctx.num("radius", 3.0), ctx.num("duration", 4.0), GROUND_COLOR)
	if not area.is_inside_tree():
		area.free()
		return null
	area.school = ctx.ability.school
	area.tick_interval = maxf(0.1, ctx.num("tick", 0.5))
	area.damage_per_tick = tick_damage(p.stats, ctx.params, ctx.ability.school)
	area.slow_pct = clampf(ctx.num("slow", 0.0), 0.0, 90.0)
	var rain_duration := area.duration
	area.add_child(WarlockRainOfFireVfx.create(area.radius, rain_duration))
	var embers := ctx.num("ember_duration", 0.0)
	if embers > 0.0:
		area.duration = rain_duration + embers
		area.add_child(WarlockEmbers.create(rain_duration, ctx.num("ember_share", 40.0), ctx.num("ember_slow", 30.0)))
	return area


## Twin Storms: the enemy within [param reach] of the Warlock with the most neighbours that is
## at least SECOND_STORM_GAP x [param radius] from [param first] (null = no other group).
static func second_center(p: Player, first: Vector3, radius: float, reach: float) -> Variant:
	var tree := p.get_tree()
	var best: Enemy = null
	var best_count := 0
	var gap := radius * SECOND_STORM_GAP
	for node in EnemyGrid.gather_around(tree, p.global_position, reach):
		var e := node as Enemy
		if not WarlockSpell.is_live(e):
			continue
		if WeaponRunner.flat(e.global_position - p.global_position).length() > reach:
			continue
		if WeaponRunner.flat(e.global_position - first).length() < gap:
			continue
		var count := EnemyGrid.count_around(tree, e.global_position, radius)
		if count > best_count:
			best_count = count
			best = e
	return best.global_position if best != null else null


## Wave start: the old circle no longer blocks the bots; no Wild Imp carries over.
func begin_wave(_ctx: AbilityContext) -> void:
	last_area = null
	dismiss_wild_imps()


## Wave cleared (and the Warlock leaving): the Wild Imps go quietly – nothing over the market.
func end_wave(_ctx: AbilityContext) -> void:
	dismiss_wild_imps()


## Frees every Wild Imp now, without a puff.
func dismiss_wild_imps() -> void:
	for imp in wild:
		if is_instance_valid(imp) and not imp.is_queued_for_deletion():
			imp.queue_free()
	wild.clear()


## Living Wild Imps (freed / expired ones dropped).
func wild_imps() -> Array[WarlockImp]:
	_prune_wild()
	return wild.duplicate()


## Wild Imps: [param count] imps for [param duration] s at [param power] of the Imp's bolt
## damage; the oldest leave (with a puff) beyond [param max_alive]. A fel beam from the rain
## circle at [param from] to each new imp.
func _summon_wild_imps(p: Player, count: int, duration: float, power: float, max_alive: int, from: Vector3) -> void:
	_prune_wild()
	for i in count:
		while wild.size() >= max_alive:
			var oldest: WarlockImp = wild.pop_front()
			if is_instance_valid(oldest):
				oldest.dismiss(true)
		var imp := WarlockImp.spawn_wild(p, duration, power, _free_slot())
		if not imp.is_inside_tree():
			imp.free()
			continue
		wild.append(imp)
		ProcVfx.beam(from + Vector3.UP * 0.6, imp.global_position + Vector3.UP * WarlockImp.BOLT_HEIGHT,
				WarlockSpell.FEL_COLOR)


## The first orbit spot no living Wild Imp holds (0 .. WILD_SLOTS - 1; the oldest's when all
## are taken).
func _free_slot() -> int:
	for slot in WILD_SLOTS:
		var taken := false
		for imp in wild:
			if is_instance_valid(imp) and imp.orbit_slot == slot:
				taken = true
				break
		if not taken:
			return slot
	return wild.size() % WILD_SLOTS


func _prune_wild() -> void:
	var kept: Array[WarlockImp] = []
	for imp in wild:
		if is_instance_valid(imp) and not imp.is_queued_for_deletion():
			kept.append(imp)
	wild = kept


## Bots: at least auto_cast_min enemies under the circle (around the Warlock with Walking
## Inferno), and not on top of a running one. The last shard waits for a ready Summon Infernal.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or ctx.target == null:
		return false
	if leaves_shard_to_infernal(p):
		return false
	var radius := ctx.num("radius", 3.0) * CombatMath.area_mult(p.stats)
	var center := p.global_position if ctx.flag("follows") else ctx.point
	if is_instance_valid(last_area) and last_area.is_inside_tree() and not last_area.is_queued_for_deletion() \
			and not last_area.has_meta(WarlockEmbers.META) \
			and WeaponRunner.flat(last_area.global_position - center).length() < last_area.radius * 0.75:
		return false
	return enemies_in_circle(p.get_tree(), center, radius) >= int(ctx.num("auto_cast_min", 4.0))


## Bots: true while a learned Summon Infernal is off cooldown and the Warlock has fewer than 2
## Soul Shards – the shard is kept for the Infernal (a bigger use of it).
static func leaves_shard_to_infernal(p: Player) -> bool:
	var r := p.abilities
	if r == null:
		return false
	var slot := r.slot_of(INFERNAL_ID)
	if slot < 0 or r.remaining(slot) > 0.0:
		return false
	var shards := r.get_resource(&"soul_shard")
	return shards != null and shards.value < 2.0
