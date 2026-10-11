class_name WarlockFear
extends AbilityEffect
## Fear (GDD 6.4, Warlock, Active): every enemy within [code]radius[/code] m (Area Size
## counts) of the Warlock flees from it for [code]duration[/code] seconds
## ([method Enemy.apply_fear]: no attacks, no contact damage; stun resistance shortens it).
## A purple wave rolls out and a ghost wisp hovers over every feared enemy.
##
## Params: radius, duration (x "power": Ranks II / IV make it last longer), cower (Cower:
## enemies freeze in place – a stun of the same length + cower_bonus s – instead of running),
## dread_damage / dread_intellect_scale / dread_spell_power_scale (Dread: Shadow damage per
## second while they are afraid, a DoT: Demonic Pact; x "power"), auto_cast_min (bots:
## enemies in the radius), auto_cast_hp (bots: with fewer, cast below this HP % or while
## reviving a teammate).
## Rank III: +1.5 m radius. Rank V: Dread (afraid enemies wither) or Cower (they freeze).

## Feared enemies of the last cast (tests).
var last_feared: Array[Enemy] = []
## Ghost wisp markers of the last cast (may be freed with their enemies).
var _markers: Array = []
var _marker_left := 0.0


static func fear_duration(params: Dictionary) -> float:
	return maxf(0.1, float(params.get("duration", 2.0))) * WarlockSpell.power(params)


static func dread_rate(stats: StatBlock, params: Dictionary, school: StringName = &"shadow") -> float:
	if float(params.get("dread_damage", 0.0)) <= 0.0:
		return 0.0
	return WarlockSpell.damage(stats, params, school, "dread_")


## Needs at least one enemy within the radius.
func can_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	return p != null and p.is_inside_tree() and _count(ctx) > 0


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var radius := WarlockSpell.area(p.stats, ctx.num("radius", 4.0))
	var victims := WarlockSpell.enemies_in_circle(p.get_tree(), p.global_position, radius)
	if victims.is_empty():
		return false
	_release_markers()
	var duration := fear_duration(ctx.params)
	var cower := ctx.flag("cower")
	var rate := dread_rate(p.stats, ctx.params, ctx.ability.school)
	var afflictions := WarlockAfflictions.of(p) if rate > 0.0 else null
	last_feared = victims
	for e in victims:
		if cower:
			e.apply_stun(duration + ctx.num("cower_bonus", 0.0))
		else:
			e.apply_fear(duration, p.global_position)
		if afflictions != null:
			var a := afflictions.dread(e, rate, duration)
			if a != null:
				a.school = ctx.ability.school
		else:
			var m := WarlockAfflictionMarker.attach(e, WarlockAfflictionMarker.FEAR)
			if m != null:
				_markers.append(m)
	_marker_left = duration
	WarlockVfx.fear_wave(p.global_position, radius)
	Vfx.hit_spark(p.get_chest_position(), WarlockSpell.SHADOW_COLOR)
	return true


## Ghost wisps of the last cast fade with the fear.
func tick(_ctx: AbilityContext, delta: float) -> void:
	if _markers.is_empty():
		return
	_marker_left -= delta
	if _marker_left <= 0.0:
		_release_markers()


## Bots: enough enemies around, or any while hurt / reviving a teammate.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var n := _count(ctx)
	if n <= 0:
		return false
	if n >= int(ctx.num("auto_cast_min", 4.0)):
		return true
	var m := p.max_hp()
	var hurt := m > 0.0 and p.hp / m * 100.0 < ctx.num("auto_cast_hp", 45.0)
	return hurt or p.is_reviving()


func begin_wave(ctx: AbilityContext) -> void:
	_clear(ctx)


func end_wave(ctx: AbilityContext) -> void:
	_clear(ctx)


func _clear(ctx: AbilityContext) -> void:
	_release_markers()
	last_feared.clear()
	var mine := WarlockAfflictions.of(ctx.player, false) if ctx != null else null
	if mine != null:
		mine.clear(WarlockAfflictions.DREAD)


func _release_markers() -> void:
	for m: Variant in _markers:
		WarlockAfflictionMarker.release(m)
	_markers.clear()


func _count(ctx: AbilityContext) -> int:
	var p := ctx.player
	return WarlockSpell.count_in_circle(p.get_tree(), p.global_position, WarlockSpell.area(p.stats, ctx.num("radius", 4.0)))
