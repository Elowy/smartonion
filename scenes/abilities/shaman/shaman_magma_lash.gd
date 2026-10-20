class_name ShamanMagmaLash
extends AbilityEffect
## Magma Lash (M8, Shaman Auto): lashes the nearest enemy in melee with molten energy – damage_pct % of the
## main hand's hit as Fire damage (+ Spell Power x spell_power_scale; the formula of PaladinKit.strike_damage
## with Fire, [method ShamanKit.weapon_strike]) and a [ShamanBurn] of burn_pct % more over burn_duration s.
## When the burn ends or the enemy dies it spreads to spread_targets enemies within spread_radius m (spread
## burns carry spread_pct % of the strength and never spread again). The lash is ability damage (Fire:
## Storm Echo eligible); the burn is DoT damage.
##
## Params: damage_pct, spell_power_scale, burn_pct, burn_duration, spread_targets, spread_radius, spread_pct,
## lashes (Twin Lashes: strikes twice, lash_delay s apart; the second lash picks the nearest enemy in reach when
## the first target died), ground_duration / ground_pct / ground_radius (Molten Trail: the target's ground burns
## for ground_duration s, ground_pct % of the lash per 0.5 s inside ground_radius m; 0 = none). "power" (Ranks
## II / IV) scales the damage. Elemental Surge: one charge per cast, baked into both lashes and the burns.
## Bot rule: an enemy within the cast range that does not burn from this Shaman.
## Rank III: +1 enemy the burn spreads to. Rank V: Contagious Flame (+3 enemies at full strength) or Twin Lashes.

const LASH_COLOR := Color(1.0, 0.5, 0.15)
const GROUND_TICK := 0.5

var casts := 0
## Lashes still to come: [{"time": s, "damage": float, ...}] (the second lash of Twin Lashes).
var _pending: Array[Dictionary] = []


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


## Auto-cast: an enemy within the cast range that does not burn from this Shaman yet.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or ctx.target == null:
		return false
	return _pick(p, ctx.ability.cast_range) != null


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or not ShamanKit.is_live(ctx.target):
		return false
	var empower := ShamanKit.empower(p)
	var target := _pick(p, ctx.ability.cast_range)
	if target == null:
		target = ctx.target as Enemy
	var power := ShamanKit.power(ctx.params)
	var amount := ShamanKit.weapon_strike(p, ctx.num("damage_pct", 150.0), ctx.num("spell_power_scale", 0.5),
			power, ShamanKit.FIRE) * empower
	var plan := {
		"amount": amount,
		"burn_pct": ctx.num("burn_pct", 40.0),
		"burn_duration": ctx.num("burn_duration", 4.0),
		"spread_targets": roundi(ctx.num("spread_targets", 0.0)),
		"spread_radius": ctx.num("spread_radius", 3.0),
		"spread_pct": ctx.num("spread_pct", 50.0),
		"ground_duration": ctx.num("ground_duration"),
		"ground_pct": ctx.num("ground_pct"),
		"ground_radius": ctx.num("ground_radius", 2.0),
		"reach": ctx.ability.cast_range,
	}
	_lash(p, target, plan)
	var extra := maxi(0, roundi(ctx.num("lashes", 1.0)) - 1)
	var delay := maxf(0.05, ctx.num("lash_delay", 0.4))
	for i in extra:
		var later := plan.duplicate()
		later["time"] = delay * float(i + 1)
		_pending.append(later)
	casts += 1
	p.face_attack(WeaponRunner.flat(target.global_position - p.global_position))
	return true


func tick(ctx: AbilityContext, delta: float) -> void:
	if _pending.is_empty():
		return
	var p := ctx.player
	var i := 0
	while i < _pending.size():
		var plan := _pending[i]
		plan["time"] = float(plan["time"]) - delta
		if float(plan["time"]) > 0.0:
			i += 1
			continue
		_pending.remove_at(i)
		if p != null and p.is_alive() and p.is_inside_tree():
			# The second lash hits the nearest enemy again (a burning one too).
			var target := _pick(p, float(plan["reach"]), false)
			if target != null:
				_lash(p, target, plan)


func begin_wave(_ctx: AbilityContext) -> void:
	_pending.clear()


func end_wave(_ctx: AbilityContext) -> void:
	_pending.clear()


## One lash on [param e]: the Fire hit (Storm Echo), the burn and the Molten Trail.
func _lash(p: Player, e: Enemy, plan: Dictionary) -> void:
	var amount := float(plan["amount"])
	var at := e.global_position
	Vfx.slash_arc(WeaponRunner.flat(p.global_position) + Vector3.UP * 0.6,
			WeaponRunner.flat(at - p.global_position), 1.6, 110.0, LASH_COLOR)
	ShamanKit.strike(p, e, amount, ShamanKit.FIRE, true)
	if ShamanKit.is_live(e):
		var burn := amount * float(plan["burn_pct"]) / 100.0
		ShamanBurn.apply(e, p, burn, float(plan["burn_duration"]), roundi(float(plan["spread_targets"])),
				float(plan["spread_radius"]), float(plan["spread_pct"]))
		Vfx.hit_spark(ShamanKit.chest(e), LASH_COLOR, ShamanKit.FIRE)
	var ground := float(plan["ground_duration"])
	if ground > 0.0 and float(plan["ground_pct"]) > 0.0:
		var area := AbilityArea.spawn(p, at, float(plan["ground_radius"]), ground, Color(1.0, 0.45, 0.12, 0.4))
		if not area.is_inside_tree():
			area.free()
			return
		area.school = ShamanKit.FIRE
		area.tick_interval = GROUND_TICK
		area.damage_per_tick = amount * float(plan["ground_pct"]) / 100.0


## The enemy to lash: the nearest one within [param reach] – with [param skip_burning] one that does not burn
## from [param p] (null when every one in reach burns already or none is near).
static func _pick(p: Player, reach: float, skip_burning: bool = true) -> Enemy:
	for e in ShamanKit.nearest_enemies(p.get_tree(), p.global_position, reach, 64):
		if not skip_burning or ShamanBurn.find(e, p) == null:
			return e
	return null
