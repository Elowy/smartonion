class_name PaladinConsecration
extends AbilityEffect
## Consecration (GDD 3.3, RT): golden holy ground under the Paladin that burns enemies inside
## every [code]tick[/code] seconds for [code]duration[/code] seconds (AbilityArea).
##
## Params: radius (Rank III: +1 m), duration, tick, damage (holy per tick), strength_scale (per
## tick per point of Strength), spell_power_scale (per second per point of Spell Power –
## normalised like weapon power, so faster ticks do not multiply it), follows (Sabatons of the
## Dawn: the ground moves with the Paladin), heal / heal_spell_power_scale (spec "Hallowed
## Ground": living heroes standing in it heal that much per tick, + Spell Power per second,
## x the Paladin's Healing Done), slow (spec "Binding Ground": enemies inside are slowed by
## that %). Damage and heal x power (ranks II / IV).
##
## M5 talent params (neutral defaults in paladin_consecration.tres; read at the cast and copied
## into a [Ground] record – the kit never keeps an AbilityContext):
##   ally_range (m, 0 = off; Holy modifier Light's Hammer +10): the ground is hurled at the feet
##     of the most wounded living hero within that range (the Paladin included) when that hero
##     is below [constant ALLY_HP_RATIO] of max HP – else it lands at the Paladin's feet as
##     usual. Instant (no flight). With "follows" it follows the hero it was hurled at.
##   heal_max_hp_pct (%, 0 = off; Light's Hammer +1): on each of the ground's ticks every living
##     hero inside heals that % of their max HP x the Paladin's Healing Done – NOT x power.
##   taunt (s, 0 = off; Protection modifier Righteous Fury +1): on each ground tick every living
##     enemy inside is taunted to the Paladin for that long (Enemy.apply_taunt; not power-scaled,
##     ignores stun resistance – the Loot Goblin ignores taunts itself).
##   ward (%, 0 = off; Righteous Fury +10): while the Paladin stands inside one of its live
##     grounds it takes that much less damage (Player.damage_taken_mults[ward_key]).
## The heal / taunt clocks run with the ground's tick interval only while the Paladin lives
## (AbilityEffect.tick); the ground itself keeps burning (AbilityArea). The Paladin going down,
## wave start / end and teardown (AbilityRunner.teardown -> end_wave) drop the ground records,
## release every enemy still taunted to the Paladin (Enemy.release_taunt) and erase the ward key.

const GROUND_COLOR := Color(1.0, 0.84, 0.35, 0.3)
## Bots cast it when an enemy is this close (share of the radius).
const AUTO_CAST_REACH := 0.9
## Light's Hammer: the most wounded hero in ally_range gets the ground below this HP share.
const ALLY_HP_RATIO := 0.8
## Light's Hammer bots also cast for a hero in ally_range below this HP share.
const AUTO_ALLY_RATIO := 0.7
## Righteous Fury: at most this many "newly taunted" sparks per ground tick.
const MAX_TAUNT_SPARKS := 6
const MAX_WARD := 90.0
const FURY_SPARK_COLOR := Color(1.0, 0.55, 0.15)
const SPARK_HEIGHT := 0.6
## Timers within this of zero count as run out (float steps of 1/60 s).
const TIME_EPSILON := 0.0001


## One live ground with talent riders (copied from the cast's params).
class Ground extends RefCounted:
	var area: AbilityArea
	var duration := 4.0
	var elapsed := 0.0
	var interval := 0.5
	## Seconds to the next heal / taunt tick (0 = at the next kit tick, like the area's own).
	var clock := 0.0
	var heal_pct := 0.0
	var taunt := 0.0
	var ward := 0.0


var _player: Player
## Live grounds with a rider (heal_max_hp_pct, taunt or ward); plain grounds are not kept.
var _grounds: Array[Ground] = []
## Enemy instance id -> true: enemies this Paladin's grounds taunted (released on cleanup).
var _taunted: Dictionary[int, bool] = {}
var _ward_key: StringName = &""
var _ward_on := false


## Holy damage of one tick for [param stats] with [param params] (before the target bonuses,
## Mastery and the owner's outgoing multipliers, which ProcSystem.deal_raw applies).
static func tick_damage(stats: StatBlock, params: Dictionary, school: StringName = &"holy") -> float:
	var tick := float(params.get("tick", 0.5))
	var flat := float(params.get("damage", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.STRENGTH)) * float(params.get("strength_scale", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.SPELL_POWER)) * float(params.get("spell_power_scale", 0.0)) * tick
	return maxf(CombatMath.MIN_DAMAGE, flat * CombatMath.damage_mult_for(stats, school)) \
			* maxf(0.0, float(params.get("power", 1.0)))


## Heal per tick for heroes standing in the ground (0 without the Hallowed Ground spec), x the
## Healing Done of [param caster] (PaladinKit.healing_mult) when given.
static func tick_heal(stats: StatBlock, params: Dictionary, caster: Player = null) -> float:
	var heal := float(params.get("heal", 0.0))
	if heal <= 0.0:
		return 0.0
	var tick := float(params.get("tick", 0.5))
	var flat := heal + maxf(0.0, stats.get_raw(Stats.SPELL_POWER)) * float(params.get("heal_spell_power_scale", 0.0)) * tick
	return flat * maxf(0.0, float(params.get("power", 1.0))) * PaladinKit.healing_mult(caster)


## Light's Hammer: the hero the ground is hurled at (the most wounded living hero within
## ally_range, the Paladin included, below ALLY_HP_RATIO); null = at the Paladin's feet
## (no talent, nobody that hurt in range).
static func hurl_target(ctx: AbilityContext) -> Player:
	var p := ctx.player
	var reach := ctx.num("ally_range")
	if reach <= 0.0 or p == null or not p.is_inside_tree():
		return null
	var t := PaladinKit.lowest_hero(p.get_tree(), p.global_position, reach, true)
	if t == null or PaladinKit.hp_ratio(t) >= ALLY_HP_RATIO:
		return null
	return t


## The ward key of [param paladin]'s Righteous Fury on its own damage_taken_mults.
static func ward_key(paladin: Player) -> StringName:
	return PaladinKit.buff_key(paladin, "righteous_fury")


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var hurled := hurl_target(ctx)
	var center := hurled.global_position if hurled != null else p.global_position
	var area := AbilityArea.spawn(p, center, ctx.num("radius", 3.0), ctx.num("duration", 4.0), GROUND_COLOR)
	if not area.is_inside_tree():
		area.free()
		return false
	area.school = ctx.ability.school
	area.tick_interval = maxf(0.1, ctx.num("tick", 0.5))
	area.damage_per_tick = tick_damage(p.stats, ctx.params, ctx.ability.school)
	area.heal_per_tick = tick_heal(p.stats, ctx.params, p)
	area.slow_pct = clampf(ctx.num("slow"), 0.0, 90.0)
	if ctx.flag("follows"):
		area.follow = hurled if hurled != null else p
	var heal_pct := maxf(0.0, ctx.num("heal_max_hp_pct"))
	var taunt := maxf(0.0, ctx.num("taunt"))
	var ward := clampf(ctx.num("ward"), 0.0, MAX_WARD)
	var inner := ConsecrationVfx.HEAL_GOLD if heal_pct > 0.0 else ConsecrationVfx.GOLD
	var rim := ConsecrationVfx.FURY_GOLD if taunt > 0.0 else inner
	area.add_child(ConsecrationVfx.create(area.radius, area.duration, rim, inner))
	if hurled != null and hurled != p:
		ProcVfx.beam(p.get_chest_position(), hurled.get_chest_position(), PaladinKit.HOLY_COLOR)
		Vfx.hit_spark(Vector3(center.x, SPARK_HEIGHT, center.z), PaladinKit.HOLY_COLOR)
	if heal_pct > 0.0 or taunt > 0.0 or ward > 0.0:
		_bind(p)
		var g := Ground.new()
		g.area = area
		g.duration = area.duration
		g.interval = area.tick_interval
		g.heal_pct = heal_pct
		g.taunt = taunt
		g.ward = ward
		_grounds.append(g)
	return true


## Light's Hammer heals, Righteous Fury taunts (per ground tick) and the ward (every tick).
## Runs only while the Paladin lives.
func tick(ctx: AbilityContext, delta: float) -> void:
	if _grounds.is_empty():
		if _ward_on:
			_set_ward(0.0)
		return
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return
	var tree := p.get_tree()
	var ward := 0.0
	var i := 0
	while i < _grounds.size():
		var g := _grounds[i]
		g.elapsed += delta
		if not _area_live(g.area) or g.elapsed > g.duration + TIME_EPSILON:
			_grounds.remove_at(i)
			continue
		i += 1
		var center := g.area.global_position
		g.clock -= delta
		if g.clock <= TIME_EPSILON:
			g.clock = g.interval
			if g.heal_pct > 0.0:
				_heal_inside(p, tree, center, g.area.radius, g.heal_pct)
			if g.taunt > 0.0:
				_taunt_inside(p, tree, center, g.area.radius, g.taunt)
		if g.ward > ward and PaladinKit.flat_distance(p.global_position, center) <= g.area.radius:
			ward = g.ward
	_set_ward(ward)


func begin_wave(_ctx: AbilityContext) -> void:
	release()


func end_wave(_ctx: AbilityContext) -> void:
	release()


## Drops every ground record, releases the enemies still taunted to the Paladin and erases
## the ward key (Paladin down, wave start / end, teardown).
func release() -> void:
	_grounds.clear()
	for id: int in _taunted:
		var e := instance_from_id(id) as Enemy
		if e != null and is_instance_valid(e) and _player != null:
			e.release_taunt(_player)
	_taunted.clear()
	_set_ward(0.0)


## Live grounds with talent riders (tests).
func ground_count() -> int:
	return _grounds.size()


## Enemies this Paladin's grounds have taunted since the last cleanup (tests).
func taunted_count() -> int:
	return _taunted.size()


## Bots: an enemy stands (almost) inside the ground it would cover; with Light's Hammer also
## when a hero within ally_range is below AUTO_ALLY_RATIO of max HP.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var reach := ctx.num("radius", 3.0) * AUTO_CAST_REACH \
			* (1.0 + p.stats.get_raw(Stats.AREA_SIZE) / 100.0)
	if EnemyGrid.nearest(p.get_tree(), p.global_position, reach) != null:
		return true
	var ally_range := ctx.num("ally_range")
	if ally_range <= 0.0:
		return false
	var t := PaladinKit.lowest_hero(p.get_tree(), p.global_position, ally_range, true)
	return t != null and PaladinKit.hp_ratio(t) < AUTO_ALLY_RATIO


func _bind(p: Player) -> void:
	if _player == p:
		return
	if _player != null and is_instance_valid(_player):
		release()
	_player = p
	_ward_key = ward_key(p)
	PaladinKit.connect_once(p.downed_changed, _on_downed_changed)


## Light's Hammer: every living hero inside heals heal_pct % of max HP x Healing Done.
func _heal_inside(p: Player, tree: SceneTree, center: Vector3, reach: float, heal_pct: float) -> void:
	var mult := PaladinKit.healing_mult(p)
	for hero in PaladinKit.living_heroes_around(tree, center, reach):
		hero.heal(hero.max_hp() * heal_pct / 100.0 * mult)


## Righteous Fury: every living enemy inside is taunted to the Paladin.
func _taunt_inside(p: Player, tree: SceneTree, center: Vector3, reach: float, taunt: float) -> void:
	var sparks := 0
	for e in PaladinKit.enemies_around(tree, center, reach):
		var fresh := not (e.is_taunted() and e.taunt_target == p)
		e.apply_taunt(p, taunt)
		_taunted[e.get_instance_id()] = true
		if fresh and sparks < MAX_TAUNT_SPARKS and e.is_taunted() and e.taunt_target == p:
			sparks += 1
			Vfx.hit_spark(e.global_position + Vector3.UP * SPARK_HEIGHT, FURY_SPARK_COLOR)


## Righteous Fury's ward: [param pct] % less damage taken (0 = erase the key).
func _set_ward(pct: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_ward_on = false
		return
	if pct > 0.0:
		_player.damage_taken_mults[_ward_key] = 1.0 - pct / 100.0
		_ward_on = true
	elif _ward_on or _player.damage_taken_mults.has(_ward_key):
		_player.damage_taken_mults.erase(_ward_key)
		_ward_on = false


static func _area_live(area: AbilityArea) -> bool:
	return area != null and is_instance_valid(area) and area.is_inside_tree() and not area.is_queued_for_deletion()


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		release()
