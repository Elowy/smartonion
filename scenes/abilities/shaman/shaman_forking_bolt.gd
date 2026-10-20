class_name ShamanForkingBolt
extends AbilityEffect
## Forking Bolt (M8, Shaman core, RT): instant lightning at the nearest enemy that forks to up to
## [code]targets[/code] enemies in all – each jump goes to the nearest not-yet-hit enemy within
## [code]jump_range[/code] m of the last one and deals falloff_pct % less Nature damage than the one before;
## the chain ends early when no enemy is left in reach. Ability damage (lightning tag: every hit rolls
## Storm Echo), instant beams ([ProcVfx.beam]).
##
## Params: damage, intellect_scale, spell_power_scale (the first hit), targets, jump_range, falloff_pct,
## return_pct (Rebounding Arc: after the last jump the bolt strikes the FIRST enemy again for this % of the
## first hit), stun (Static Cling: every enemy struck is stunned, s), slow + slow_duration. "power" (Ranks II
## / IV) scales the damage. Elemental Surge: one charge is taken at the top of every cast and multiplies all
## the damage of the cast. The Thunderpost Artifact reads where the bolt first struck and the first hit's
## amount ([method ShamanKit.last_fork]).
## Rank III: +1 enemy. Rank V: Thunder Web (no falloff, +1 enemy) or Static Cling (stun).

const BEAM_HEIGHT := 0.8
const MAX_FALLOFF := 90.0

## Bolts cast so far and the enemies the last one struck, in order (tests).
var casts := 0
var last_hits: Array[Enemy] = []


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	var first := ctx.target as Enemy
	if p == null or not p.is_inside_tree() or not ShamanKit.is_live(first):
		return false
	var empower := ShamanKit.empower(p)
	var base := ShamanKit.spell_damage(p.stats, ctx.params, ShamanKit.NATURE) * empower
	var count := maxi(1, roundi(ctx.num("targets", 1.0)))
	var jump := maxf(0.0, ctx.num("jump_range", 5.0))
	var keep := 1.0 - clampf(ctx.num("falloff_pct", 0.0), 0.0, MAX_FALLOFF) / 100.0
	var stun := ctx.num("stun")
	var slow := ctx.num("slow")
	var slow_time := ctx.num("slow_duration", 2.0)
	var from := Vector3(p.global_position.x, BEAM_HEIGHT, p.global_position.z) + p.facing * 0.35
	last_hits.clear()
	var hit: Array[Enemy] = []
	var amount := base
	var current := first
	var first_point := first.global_position
	var first_amount := base
	while current != null and hit.size() < count:
		var to := ShamanKit.chest(current)
		ProcVfx.beam(from, to, ShamanKit.LIGHTNING_COLOR)
		_hit(p, current, amount, stun, slow, slow_time)
		hit.append(current)
		last_hits.append(current)
		from = to
		amount *= keep
		var from_pos := current.global_position
		current = null
		if hit.size() < count:
			var next := ShamanKit.nearest_enemies(p.get_tree(), from_pos, jump, 1, hit)
			if not next.is_empty():
				current = next[0]
	var back := ctx.num("return_pct")
	if back > 0.0 and hit.size() > 1 and ShamanKit.is_live(first):
		ProcVfx.beam(from, ShamanKit.chest(first), ShamanKit.LIGHTNING_COLOR)
		_hit(p, first, first_amount * back / 100.0, stun, slow, slow_time)
	ShamanKit.set_last_fork(p, first_point, first_amount)
	casts += 1
	p.face_attack(WeaponRunner.flat(first_point - p.global_position))
	return true


## One strike: damage (Storm Echo eligible), the optional stun / slow and a spark.
func _hit(p: Player, e: Enemy, amount: float, stun: float, slow: float, slow_time: float) -> void:
	ShamanKit.strike(p, e, amount, ShamanKit.NATURE, true)
	if not ShamanKit.is_live(e):
		return
	if stun > 0.0:
		e.apply_stun(stun)
	if slow > 0.0:
		e.apply_slow(slow, slow_time)
	Vfx.hit_spark(ShamanKit.chest(e), ShamanKit.LIGHTNING_COLOR, ShamanKit.NATURE)
