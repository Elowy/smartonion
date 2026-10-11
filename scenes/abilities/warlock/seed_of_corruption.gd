class_name WarlockSeedOfCorruption
extends AbilityEffect
## Seed of Corruption (GDD 6.4, Warlock, Auto): plants a seed in an enemy of the densest group
## within range. The seed slowly hurts its host (a Shadow DoT, &"dot": Demonic Pact) and when
## the host dies – or the seed ripens after [code]duration[/code] seconds – it bursts for
## Shadow damage on every enemy within [code]radius[/code] m (&"ability"). Kept by
## [WarlockAfflictions]; one seed per enemy.
##
## Params: damage, intellect_scale, spell_power_scale (burst), dot_damage,
## dot_intellect_scale, dot_spell_power_scale (seed DoT per second), duration, radius (burst;
## Area Size counts – also the cluster radius of the targeting), auto_cast_min (enemies in
## the burst circle for the auto-cast), chain (Chain Reaction: further seeds a burst plants
## in a surviving victim), pool_duration / pool_damage_share / pool_slow (Blighted Ground: the
## burst leaves a slowing, burning pool; damage per 0.5 s tick as % of the burst).
## "power" (Ranks II / IV) scales every damage. Rank III: +1 m burst radius.

const POOL_RADIUS_SHARE := 0.8

var afflictions: WarlockAfflictions
## Seeds planted so far (tests).
var seeds_planted := 0


static func burst_damage(stats: StatBlock, params: Dictionary, school: StringName = &"shadow") -> float:
	return WarlockSpell.damage(stats, params, school)


static func dot_rate(stats: StatBlock, params: Dictionary, school: StringName = &"shadow") -> float:
	return WarlockSpell.damage(stats, params, school, "dot_")


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or ctx.target == null:
		return false
	afflictions = WarlockAfflictions.of(p)
	if afflictions == null:
		return false
	var host := host_for(ctx)
	if host == null:
		return false
	var school := ctx.ability.school
	var radius := WarlockSpell.area(p.stats, ctx.num("radius", 3.0))
	var burst := burst_damage(p.stats, ctx.params, school)
	var a := afflictions.plant_seed(host, dot_rate(p.stats, ctx.params, school), maxf(0.5, ctx.num("duration", 6.0)),
			burst, radius)
	if a == null:
		return false
	a.school = school
	a.chain_left = maxi(0, roundi(ctx.num("chain", 0.0)))
	a.pool_duration = maxf(0.0, ctx.num("pool_duration", 0.0))
	if a.pool_duration > 0.0:
		a.pool_radius = ctx.num("radius", 3.0) * POOL_RADIUS_SHARE
		a.pool_tick_damage = burst * ctx.num("pool_damage_share", 0.0) / 100.0
		a.pool_slow = ctx.num("pool_slow", 0.0)
	seeds_planted += 1
	ProcVfx.bolt(p.get_chest_position(), WarlockSpell.chest(host), WarlockSpell.FEL_COLOR)
	return true


## The enemy a cast seeds: the cluster's enemy (ctx.target) unless it already carries a seed,
## else the unseeded enemy nearest to it within the burst radius. Null when there is none.
func host_for(ctx: AbilityContext) -> Enemy:
	if not WarlockSpell.is_live(ctx.target):
		return null
	var p := ctx.player
	var mine := WarlockAfflictions.of(p, false) if p != null else null
	var target := ctx.target as Enemy
	if mine == null or not mine.has(WarlockAfflictions.SEED, target):
		return target
	var near := WarlockSpell.nearest_enemies(target.get_tree(), target.global_position,
			WarlockSpell.area(p.stats, ctx.num("radius", 3.0)), 1, mine.lacks(WarlockAfflictions.SEED))
	return near[0] if not near.is_empty() else null


## Auto-cast: an unseeded host with at least auto_cast_min enemies (itself included) in its
## burst circle.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var host := host_for(ctx)
	if host == null:
		return false
	var radius := WarlockSpell.area(p.stats, ctx.num("radius", 3.0))
	return WarlockSpell.count_in_circle(p.get_tree(), host.global_position, radius) \
			>= int(ctx.num("auto_cast_min", 2.0))


## Wave start / end and forgetting the ability: the seeds wither (no bursts).
func begin_wave(ctx: AbilityContext) -> void:
	_clear(ctx)


func end_wave(ctx: AbilityContext) -> void:
	_clear(ctx)


func active_count() -> int:
	return afflictions.count(WarlockAfflictions.SEED) if is_instance_valid(afflictions) else 0


func _clear(ctx: AbilityContext) -> void:
	var mine := afflictions if is_instance_valid(afflictions) else WarlockAfflictions.of(ctx.player, false)
	if mine != null:
		mine.clear(WarlockAfflictions.SEED)
