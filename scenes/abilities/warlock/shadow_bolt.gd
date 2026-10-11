class_name WarlockShadowBolt
extends AbilityEffect
## Shadow Bolt (GDD 6.4, Warlock, Auto): a strong, slow-ish Shadow projectile
## ([WarlockShadowBoltMissile]) at the nearest enemy within range – one bolt per
## [code]bolts[/code], each at the next-nearest enemy (the nearest again when there are fewer).
## Ability damage (no DoT: Demonic Pact does not apply).
##
## Params: damage, intellect_scale, spell_power_scale (per bolt), bolts, speed, pierce
## (Void Lance: extra enemies passed through), blast_radius (Shadow Burst: explodes, m;
## Area Size counts). "power" (Ranks II / IV) scales the damage.
## Rank III: +1 bolt. Rank V: Void Lance (pierces) or Shadow Burst (explodes).

## Bolts leave the Warlock at this height.
const BOLT_HEIGHT := 0.85
## Flight range beyond the cast range (a target walking away is still reached).
const RANGE_SLACK := 2.5

## Bolts fired so far (tests) and the last one (may be freed).
var bolts_fired := 0
var last_bolts: Array[WarlockShadowBoltMissile] = []


## Damage of one bolt for [param stats] with [param params] (before deal_raw's multipliers).
static func bolt_damage(stats: StatBlock, params: Dictionary, school: StringName = &"shadow") -> float:
	return WarlockSpell.damage(stats, params, school)


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or not WarlockSpell.is_live(ctx.target):
		return false
	var count := maxi(1, roundi(ctx.num("bolts", 1.0)))
	var targets := WarlockSpell.nearest_enemies(p.get_tree(), p.global_position, ctx.ability.cast_range, count)
	if targets.is_empty():
		targets.append(ctx.target as Enemy)
	var dmg := bolt_damage(p.stats, ctx.params, ctx.ability.school)
	var pierce := maxi(0, roundi(ctx.num("pierce", 0.0)))
	var blast := ctx.num("blast_radius", 0.0)
	if blast > 0.0:
		blast = WarlockSpell.area(p.stats, blast)
	var from := Vector3(p.global_position.x, BOLT_HEIGHT, p.global_position.z)
	last_bolts.clear()
	for i in count:
		var e := targets[i % targets.size()]
		var dir := WeaponRunner.flat(e.global_position - p.global_position)
		if dir.length_squared() < 0.0001:
			dir = p.facing
		var bolt := WarlockShadowBoltMissile.fire(p, from, dir, dmg, ctx.ability.cast_range + RANGE_SLACK,
				ctx.num("speed", 15.0), pierce, blast)
		bolt.school = ctx.ability.school
		if not bolt.is_inside_tree():
			bolt.free()
			continue
		last_bolts.append(bolt)
		bolts_fired += 1
	if last_bolts.is_empty():
		return false
	p.face_attack(WeaponRunner.flat(targets[0].global_position - p.global_position))
	Vfx.hit_spark(from + p.facing * 0.4, WarlockSpell.SHADOW_COLOR)
	return true


## Auto-cast: an enemy within range (ctx.target).
func wants_auto_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null and ctx.player != null and ctx.player.is_inside_tree()
