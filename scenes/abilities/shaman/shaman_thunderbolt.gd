class_name ShamanThunderbolt
extends AbilityEffect
## Thunderbolt (M8, Shaman Auto): a bolt out of the sky on the nearest enemy within range – one bolt per
## [code]bolts[/code], each at the next-nearest enemy (the nearest again when there are fewer). Instant
## ability damage (Nature, lightning tag: every struck target rolls Storm Echo); the strike's light is a
## short beam from above.
##
## Params: damage, intellect_scale, spell_power_scale (per bolt), bolts, splash_radius (Sundering Bolt: every
## other enemy within this many m of the target takes splash_pct % of the bolt; Area Size counts), splash_pct,
## stun (Staggering Bolt, s). "power" (Ranks II / IV) scales the damage. Elemental Surge: one charge per cast.
## Rank III: +1 bolt. Rank V: Sundering Bolt (splash) or Staggering Bolt (stun).

const SKY_HEIGHT := 9.0

var casts := 0


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or not ShamanKit.is_live(ctx.target):
		return false
	var empower := ShamanKit.empower(p)
	var dmg := ShamanKit.spell_damage(p.stats, ctx.params, ShamanKit.NATURE) * empower
	var count := maxi(1, roundi(ctx.num("bolts", 1.0)))
	var targets := ShamanKit.nearest_enemies(p.get_tree(), p.global_position, ctx.ability.cast_range, count)
	if targets.is_empty():
		targets.append(ctx.target as Enemy)
	var splash_radius := ctx.num("splash_radius")
	if splash_radius > 0.0:
		splash_radius *= CombatMath.area_mult(p.stats)
	var splash := dmg * ctx.num("splash_pct", 50.0) / 100.0
	var stun := ctx.num("stun")
	for i in count:
		var e := targets[i % targets.size()]
		if not ShamanKit.is_live(e):
			continue
		var at := ShamanKit.chest(e)
		ProcVfx.beam(Vector3(at.x + 0.5, SKY_HEIGHT, at.z + 0.3), at, ShamanKit.LIGHTNING_COLOR)
		Vfx.explosion(WeaponRunner.flat(e.global_position) + Vector3.UP * 0.1, maxf(0.6, splash_radius), ShamanKit.LIGHTNING_COLOR)
		var centre := e.global_position
		ShamanKit.strike(p, e, dmg, ShamanKit.NATURE, true)
		if stun > 0.0 and ShamanKit.is_live(e):
			e.apply_stun(stun)
		if splash_radius > 0.0:
			for other in ShamanKit.enemies_around(p.get_tree(), centre, splash_radius):
				if other != e:
					p.procs.deal_raw(other, splash, ShamanKit.NATURE, true, &"ability")
	casts += 1
	p.face_attack(WeaponRunner.flat(targets[0].global_position - p.global_position))
	return true
