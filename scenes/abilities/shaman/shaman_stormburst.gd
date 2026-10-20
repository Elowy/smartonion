class_name ShamanStormburst
extends AbilityEffect
## Stormburst (M8, Shaman Auto): when enemies crowd the Shaman a burst of lightning hits every enemy within
## [code]radius[/code] m for Nature damage (lightning tag: every enemy hit rolls Storm Echo) and throws it back
## ([code]push[/code]: 12 ~ 3 m, the enemy's knockback resistance applies, [method ShamanKit.knock_back]).
##
## Params: damage, intellect_scale, spell_power_scale, radius (Area Size counts), push, min_enemies (the bot
## rule: this many enemies in the radius), auto_hp (the bot also bursts at one enemy while the HP % is below
## this), stun (Crackling Field, s), pulses (Echoing Discharge: a second burst pulse_delay s later; both bursts
## carry the cast's Elemental Surge charge). "power" (Ranks II / IV) scales the damage.
## Rank III: +1 m radius. Rank V: Echoing Discharge or Crackling Field.

const BEAMS_SHOWN := 6
const RING_HEIGHT := 0.1

var casts := 0
## Bursts still to come: [{"time": s, "amount": float, ...}].
var _pending: Array[Dictionary] = []


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.player != null and ctx.player.is_inside_tree() and _crowd(ctx) > 0


## Auto-cast: min_enemies in reach, or one while the Shaman's HP is below auto_hp %.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var crowd := _crowd(ctx)
	if crowd >= roundi(ctx.num("min_enemies", 3.0)):
		return true
	return crowd >= 1 and ShamanKit.hp_ratio(p) * 100.0 < ctx.num("auto_hp", 40.0)


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or _crowd(ctx) <= 0:
		return false
	var empower := ShamanKit.empower(p)
	var plan := {
		"amount": ShamanKit.spell_damage(p.stats, ctx.params, ShamanKit.NATURE) * empower,
		"radius": ctx.num("radius", 3.5) * CombatMath.area_mult(p.stats),
		"push": ctx.num("push", 12.0),
		"stun": ctx.num("stun"),
	}
	_burst(p, plan)
	var extra := maxi(0, roundi(ctx.num("pulses", 1.0)) - 1)
	var delay := maxf(0.05, ctx.num("pulse_delay", 0.8))
	for i in extra:
		var later := plan.duplicate()
		later["time"] = delay * float(i + 1)
		_pending.append(later)
	casts += 1
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
			_burst(p, plan)


func begin_wave(_ctx: AbilityContext) -> void:
	_pending.clear()


func end_wave(_ctx: AbilityContext) -> void:
	_pending.clear()


## One burst around the Shaman: damage, push and stun for every enemy in the radius (group order).
func _burst(p: Player, plan: Dictionary) -> void:
	var centre := p.global_position
	var radius := float(plan["radius"])
	var shown := 0
	Vfx.explosion(WeaponRunner.flat(centre) + Vector3.UP * RING_HEIGHT, radius, ShamanKit.LIGHTNING_COLOR)
	for e in ShamanKit.enemies_around(p.get_tree(), centre, radius):
		if shown < BEAMS_SHOWN:
			ProcVfx.beam(Vector3(centre.x, 0.9, centre.z), ShamanKit.chest(e), ShamanKit.LIGHTNING_COLOR)
			shown += 1
		ShamanKit.strike(p, e, float(plan["amount"]), ShamanKit.NATURE, true)
		if not ShamanKit.is_live(e):
			continue
		ShamanKit.knock_back(e, centre, float(plan["push"]))
		if float(plan["stun"]) > 0.0:
			e.apply_stun(float(plan["stun"]))


## Living enemies within the burst radius of the Shaman.
func _crowd(ctx: AbilityContext) -> int:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return 0
	return ShamanKit.count_around(p.get_tree(), p.global_position, ctx.num("radius", 3.5) * CombatMath.area_mult(p.stats))
