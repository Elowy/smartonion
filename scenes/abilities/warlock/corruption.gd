class_name WarlockCorruption
extends AbilityEffect
## Corruption (GDD 6.4, Warlock, Auto): a Shadow damage-over-time curse on the nearest
## uncorrupted enemy within range ([code]targets[/code] enemies per cast). Kept by
## [WarlockAfflictions] (ticks as &"dot": Demonic Pact boosts it; it keeps burning while the
## Warlock is downed). When a corrupted enemy dies the curse jumps – with the time it had
## left – to the nearest uncorrupted enemy within [code]spread_radius[/code] m
## ([code]spread_targets[/code] of them), so a cast is never wasted on a kill.
##
## Params: damage (Shadow per second), intellect_scale / spell_power_scale (per second per
## point), duration, targets, spread_radius, spread_targets, heal_pct (Siphon Life: share of
## the damage that heals the Warlock). "power" (Ranks II / IV) scales the damage.
## Rank III: +1 enemy per cast. Rank V: Contagion (spreads to 3) or Siphon Life (heals).

## The Warlock's afflictions node (null before the first cast).
var afflictions: WarlockAfflictions


## Damage per second of one Corruption for [param stats] with [param params].
static func rate(stats: StatBlock, params: Dictionary, school: StringName = &"shadow") -> float:
	return WarlockSpell.damage(stats, params, school)


## Needs an enemy within range (ctx.target, the nearest one).
func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or ctx.target == null:
		return false
	afflictions = WarlockAfflictions.of(p)
	if afflictions == null:
		return false
	var targets := _pick(ctx)
	if targets.is_empty():
		return false
	var school := ctx.ability.school
	var per_second := rate(p.stats, ctx.params, school)
	var applied := 0
	for e in targets:
		var a := afflictions.corrupt(e, per_second, maxf(0.5, ctx.num("duration", 8.0)),
				roundi(ctx.num("spread_targets", 1.0)), WarlockSpell.area(p.stats, ctx.num("spread_radius", 4.0)),
				ctx.num("heal_pct", 0.0) / 100.0)
		if a == null:
			continue
		a.school = school
		applied += 1
		ProcVfx.bolt(p.get_chest_position(), WarlockSpell.chest(e), WarlockSpell.SHADOW_COLOR)
	return applied > 0


## Auto-cast: only when an enemy within range is not corrupted yet (no refreshing in place).
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or ctx.target == null:
		return false
	var mine := WarlockAfflictions.of(p, false)
	if mine == null:
		return true
	return WarlockSpell.any_enemy(p.get_tree(), p.global_position, ctx.ability.cast_range,
			mine.lacks(WarlockAfflictions.CORRUPTION))


## Wave start / end and forgetting the ability: the curses end (no spreading).
func begin_wave(ctx: AbilityContext) -> void:
	_clear(ctx)


func end_wave(ctx: AbilityContext) -> void:
	_clear(ctx)


## Running Corruptions of this Warlock (tests, UI).
func active_count() -> int:
	return afflictions.count(WarlockAfflictions.CORRUPTION) if is_instance_valid(afflictions) else 0


## The enemies a cast curses: the nearest uncorrupted ones in range; with every enemy in range
## already corrupted, the nearest one is refreshed.
func _pick(ctx: AbilityContext) -> Array[Enemy]:
	var p := ctx.player
	var count := maxi(1, roundi(ctx.num("targets", 1.0)))
	var out := WarlockSpell.nearest_enemies(p.get_tree(), p.global_position, ctx.ability.cast_range, count,
			afflictions.lacks(WarlockAfflictions.CORRUPTION))
	if out.is_empty() and WarlockSpell.is_live(ctx.target):
		out.append(ctx.target as Enemy)
	return out


func _clear(ctx: AbilityContext) -> void:
	var mine := afflictions if is_instance_valid(afflictions) else WarlockAfflictions.of(ctx.player, false)
	if mine != null:
		mine.clear(WarlockAfflictions.CORRUPTION)
