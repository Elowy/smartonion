class_name ShamanSoothingDownpour
extends AbilityEffect
## Soothing Downpour (M8, Shaman Active): calls a healing rain on the most wounded living hero within range
## (the Shaman included; ties: the nearest) – a [ShamanRain] of [code]radius[/code] m for [code]duration[/code] s
## in which every hero heals heal + heal_max_hp_pct % of its Max HP every [code]tick[/code] s (more with Spell
## Power). Targeting is SELF because the generic ALLY rule never considers the caster: cast() picks the hero
## itself ([method ShamanKit.lowest_hero]). Healing is credited to the Shaman's healing meter.
##
## Params: heal, heal_max_hp_pct, heal_spell_power_scale (per second), radius, duration, tick, follows
## (Following Rain: the rain follows the hero it was called on), rains (Twin Squalls: a second rain rain_delay s
## later on the then most wounded hero), damage / intellect_scale / spell_power_scale (Thundercloud: lightning
## strikes the enemies in the rain every tick), auto_hp (bot rule, %). "power" (Ranks II / IV) scales heals and
## damage. A heal never takes an Elemental Surge charge; the Thundercloud damage does not either (it is a
## side effect of a healing ability).
## Bot rule: a living hero within range below auto_hp % whom none of the Shaman's running rains covers.
## Rank III: +2 s of rain. Rank V: Following Rain or Thundercloud.

const COLOR := Color(0.4, 0.8, 0.9, 0.34)

var casts := 0
var _rains: Array[ShamanRain] = []
## Rains still to come: [{"time": s}] (Twin Squalls).
var _pending: Array[Dictionary] = []


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.player != null and ctx.player.is_inside_tree() and _pick(ctx.player, ctx.ability.cast_range, false) != null


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var hero := _pick(p, ctx.ability.cast_range, true)
	if hero == null or ShamanKit.hp_ratio(hero) * 100.0 >= ctx.num("auto_hp", 60.0):
		return false
	_prune()
	for r in _rains:
		if ShamanKit.flat_distance(r.global_position, hero.global_position) <= r.radius:
			return false
	return true


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var hero := _pick(p, ctx.ability.cast_range, false)
	if hero == null:
		return false
	var made := _rain(p, hero, ctx.params)
	if made == null:
		return false
	var extra := maxi(0, roundi(ctx.num("rains", 1.0)) - 1)
	var delay := maxf(0.1, ctx.num("rain_delay", 3.0))
	for i in extra:
		_pending.append({"time": delay * float(i + 1), "params": ctx.params.duplicate(true)})
	casts += 1
	Vfx.floating_text(p.self_text_position(1.0), "Downpour", ShamanKit.WATER_COLOR, Player.SELF_TEXT_SIZE, 1.0)
	return true


func tick(ctx: AbilityContext, delta: float) -> void:
	if _pending.is_empty():
		return
	var p := ctx.player
	var i := 0
	while i < _pending.size():
		var item := _pending[i]
		item["time"] = float(item["time"]) - delta
		if float(item["time"]) > 0.0:
			i += 1
			continue
		_pending.remove_at(i)
		if p != null and p.is_alive() and p.is_inside_tree():
			var hero := _pick(p, ctx.ability.cast_range, false)
			if hero != null:
				_rain(p, hero, item["params"] as Dictionary)


func begin_wave(_ctx: AbilityContext) -> void:
	_pending.clear()
	_rains.clear()


func end_wave(_ctx: AbilityContext) -> void:
	_pending.clear()
	_rains.clear()


## The rains of this Shaman still running (freed ones pruned).
func running() -> Array[ShamanRain]:
	_prune()
	var out: Array[ShamanRain] = []
	out.assign(_rains)
	return out


## Opens one rain on [param hero] with [param params] (null when it could not be placed).
func _rain(p: Player, hero: Player, params: Dictionary) -> ShamanRain:
	var area := ShamanRain.open(p, hero.global_position, float(params.get("radius", 4.0)),
			float(params.get("duration", 5.0)), COLOR)
	if not area.is_inside_tree():
		area.free()
		return null
	var power := ShamanKit.power(params)
	area.school = ShamanKit.NATURE
	area.tick_interval = maxf(0.05, float(params.get("tick", 0.5)))
	area.heal = float(params.get("heal", 0.3))
	area.heal_max_hp_pct = float(params.get("heal_max_hp_pct", 2.0))
	area.heal_sp_scale = float(params.get("heal_spell_power_scale", 0.5))
	area.power = power
	if float(params.get("damage", 0.0)) > 0.0:
		area.strike_damage = ShamanKit.spell_damage(p.stats, params, ShamanKit.NATURE, area.tick_interval)
	if bool(params.get("follows", false)):
		area.follow = hero
	_rains.append(area)
	return area


## The hero to rain on: the most wounded living hero within [param reach] of the Shaman (the Shaman
## included); with [param hurt_only] only wounded ones count.
static func _pick(p: Player, reach: float, hurt_only: bool) -> Player:
	return ShamanKit.lowest_hero(p.get_tree(), p.global_position, reach, hurt_only, null)


func _prune() -> void:
	for i in range(_rains.size() - 1, -1, -1):
		if not is_instance_valid(_rains[i]) or not _rains[i].is_inside_tree() or _rains[i].is_queued_for_deletion():
			_rains.remove_at(i)
