class_name WarriorThunderClap
extends AbilityEffect
## Thunder Clap (GDD 6.4, Warrior Auto-cast): the hero slams the ground – every enemy whose
## body touches the circle of [code]radius[/code] around it takes [code]damage_pct[/code] %
## weapon damage (times "power") and is slowed by [code]slow[/code] % for
## [code]slow_duration[/code] seconds.
##
## Params (AbilityData.params; items and ranks change them):
##   damage_pct, radius (Area Size scales it), slow, slow_duration
##   echoes, echo_delay, echo_pct   Rank V "Aftershock": the clap strikes [code]echoes[/code] more
##                                  times around the hero, echo_delay s apart, for echo_pct %
##                                  of its damage (slowing again)
##   rage_per_hit, rage_max         Rank V "Booming Voice": Rage per enemy hit, at most
##                                  rage_max per clap
## Rank III: +1 m radius, the slow lasts 1 s longer.
##
## Auto-cast: when two enemies are in reach – or a lone one with nobody else closing in (no
## other enemy within AUTO_APPROACH_FACTOR x the reach), so it is not wasted on the first of a
## pack but still fires against stragglers.

const DEFAULT_RADIUS := 3.5
const DEFAULT_SLOW_DURATION := 2.0
const AUTO_MIN_ENEMIES := 2
const AUTO_APPROACH_FACTOR := 2.0
const SPARK_COLOR := Color(0.7, 0.85, 1.0)
const MAX_SPARKS := 4

var _player: Player
var _school: StringName = &"physical"
var _radius := DEFAULT_RADIUS
var _slow := 0.0
var _slow_duration := DEFAULT_SLOW_DURATION
var _rage_per_hit := 0.0
var _rage_max := 0.0
var _echoes_left := 0
var _echo_left := 0.0
var _echo_delay := 0.6
var _echo_damage_pct := 0.0
## Enemies hit by the last clap (tests).
var last_hits := 0


## Reach around the hero in metres, with Area Size.
func reach_of(ctx: AbilityContext) -> float:
	return ctx.num("radius", DEFAULT_RADIUS) * CombatMath.area_mult(ctx.player.stats)


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var reach := reach_of(ctx)
	var close := WarriorKit.enemies_within(p, reach).size()
	if close >= AUTO_MIN_ENEMIES:
		return true
	if close == 0:
		return false
	return WarriorKit.enemies_within(p, reach * AUTO_APPROACH_FACTOR).size() <= close


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	_player = p
	_school = ctx.ability.school
	_radius = reach_of(ctx)
	_slow = ctx.num("slow", 50.0)
	_slow_duration = ctx.num("slow_duration", DEFAULT_SLOW_DURATION)
	_rage_per_hit = ctx.num("rage_per_hit")
	_rage_max = ctx.num("rage_max", 30.0)
	var damage_pct := ctx.num("damage_pct", 100.0) * ctx.num("power", 1.0)
	_echoes_left = maxi(0, roundi(ctx.num("echoes")))
	_echo_delay = maxf(0.1, ctx.num("echo_delay", 0.6))
	_echo_left = _echo_delay
	_echo_damage_pct = damage_pct * ctx.num("echo_pct", 50.0) / 100.0
	if not p.downed_changed.is_connected(_on_downed_changed):
		p.downed_changed.connect(_on_downed_changed)
	clap(damage_pct, false)
	return true


## Echo claps of Aftershock follow the hero.
func tick(_ctx: AbilityContext, delta: float) -> void:
	if _echoes_left <= 0:
		return
	_echo_left -= delta
	if _echo_left <= 0.0:
		_echoes_left -= 1
		_echo_left += _echo_delay
		clap(_echo_damage_pct, true)


## Echoes still to come (tests).
func echoes_pending() -> int:
	return _echoes_left


func begin_wave(_ctx: AbilityContext) -> void:
	_cancel()


## No echo claps in the market (also when the ability is forgotten).
func end_wave(_ctx: AbilityContext) -> void:
	_cancel()


## One clap around the hero for [param damage_pct] % weapon damage; returns the enemies hit.
func clap(damage_pct: float, echo: bool) -> int:
	last_hits = 0
	var p := _player
	if p == null or not is_instance_valid(p) or not p.is_inside_tree() or p.procs == null:
		return 0
	var here := p.global_position
	WarriorClapVfx.spawn(here, _radius, echo)
	var damage := WarriorKit.weapon_damage(p) * damage_pct / 100.0
	var sparks := 0
	for e in WarriorKit.enemies_within(p, _radius):
		if not is_instance_valid(e) or e.is_dead():
			continue
		var spot := e.global_position + Vector3.UP * WarriorSpin.SPARK_HEIGHT
		p.procs.deal_raw(e, damage, _school, true, &"ability")
		if _slow > 0.0 and is_instance_valid(e):
			e.apply_slow(_slow, _slow_duration)
		last_hits += 1
		if sparks < MAX_SPARKS:
			sparks += 1
			Vfx.hit_spark(spot, SPARK_COLOR)
	if _rage_per_hit > 0.0 and last_hits > 0:
		WarriorKit.add_rage(p, minf(_rage_per_hit * last_hits, _rage_max))
	return last_hits


func _cancel() -> void:
	_echoes_left = 0
	_echo_left = 0.0


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		_cancel()
