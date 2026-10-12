class_name MageFireball
extends AbilityEffect
## Fireball (GDD 6.4, Mage, Auto-cast): whenever it is ready and an enemy is within reach it
## hurls a fireball at the nearest one – Fire spell damage ([MageSpell]: damage +
## int_scaling x Intellect, Spell Power, Fire %, x power) and a burn ([MageBurn]) for
## burn_pct % of the hit over burn_duration seconds. The bolt ([MageBolt]) homes in gently so
## a walking target is not missed.
##
## Params (data/abilities/mage_fireball.tres): damage, int_scaling, burn_pct, burn_duration,
## speed, fireballs (Rank III: +1 – the extra ones go to the next nearest enemies),
## bounces + bounce_pct (Rank V "Bouncing Fireball"), splash_radius + splash_pct (Rank V
## "Explosive Fireball"; x Area Size).
## Talent hook (M5, Fire modifier "Living Bomb", talents_mage.md 4.3): bomb_pct > 0 (neutral 0)
## arms every burn a fireball starts ([member MageBolt.bomb_pct]): when the burn runs out or the
## enemy dies while burning, it explodes for bomb_pct % of that hit within bomb_radius m
## (x Area Size) – see [MageBurn].

const TURN_RATE := 4.0
## Extra flight range beyond the cast range (a homing curve is longer than the line).
const RANGE_SLACK := 3.0
## Side-by-side fireballs at one target spread this far apart (radians).
const FAN := 0.14

## Bolts in flight (freed at wave end / forget).
var bolts: Array[Node3D] = []


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or not MageSpell.is_live(ctx.target):
		return false
	var count := maxi(1, roundi(ctx.num("fireballs", 1.0)))
	var targets := MageSpell.nearest_enemies(p.get_tree(), p.global_position, ctx.ability.cast_range, count)
	if targets.is_empty():
		targets.append(ctx.target as Enemy)
	var damage := MageSpell.damage_from(ctx, MageSpell.FIRE)
	var from := p.global_position + Vector3.UP * Player.CHEST_HEIGHT
	MageSpell.prune(bolts)
	for i in count:
		var target := targets[i % targets.size()]
		var dir := WeaponRunner.flat(target.global_position - from)
		if dir.length_squared() < 0.0001:
			dir = p.facing
		# Several fireballs at the same enemy fan out a little and converge.
		var lap := i / targets.size()
		if lap > 0:
			dir = dir.rotated(Vector3.UP, FAN * float(lap) * (1.0 if lap % 2 == 1 else -1.0))
		var bolt := MageBolt.fire(p, from + dir.normalized() * (Player.RADIUS + 0.1), dir, damage,
				MageSpell.FIRE, ctx.num("speed", 15.0), ctx.ability.cast_range + RANGE_SLACK,
				&"fireball", MageSpell.FIRE_COLOR, 1.5)
		bolt.home_on(target, TURN_RATE)
		bolt.burn_pct = ctx.num("burn_pct", 0.0)
		bolt.burn_duration = ctx.num("burn_duration", 3.0)
		bolt.splash_radius = ctx.num("splash_radius", 0.0) * MageSpell.area_mult(p)
		bolt.splash_pct = ctx.num("splash_pct", 60.0)
		bolt.set_bounces(roundi(ctx.num("bounces", 0.0)))
		bolt.bounce_mult = ctx.num("bounce_pct", 75.0) / 100.0
		bolt.bomb_pct = maxf(0.0, ctx.num("bomb_pct", 0.0))
		bolt.bomb_radius = ctx.num("bomb_radius", 2.5) * MageSpell.area_mult(p)
		bolts.append(bolt)
	p.face_attack(WeaponRunner.flat(targets[0].global_position - p.global_position))
	return true


func begin_wave(_ctx: AbilityContext) -> void:
	MageSpell.free_all(bolts)


func end_wave(_ctx: AbilityContext) -> void:
	MageSpell.free_all(bolts)
