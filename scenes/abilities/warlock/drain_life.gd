class_name WarlockDrainLife
extends AbilityEffect
## Drain Life (GDD 3.5, LT, 8 s cooldown): a [code]duration[/code]-second channel on the
## nearest enemy. Every [code]tick[/code] seconds it deals Shadow damage
## (ProcSystem.deal_raw(..., &"ability")) and heals the Warlock for [code]heal_pct[/code]% of
## the damage actually dealt (overkill does not heal). The Warlock keeps moving and attacking
## (no root). When the target dies or leaves [code]range[/code] x [constant BREAK_SLACK] the
## drain jumps to the nearest enemy within [code]range[/code]; with none left it ends early.
## Going down ends it. A green-purple beam ([WarlockDrainBeam]) links the two.
##
## Params: duration, tick, damage (shadow per tick), intellect_scale (per tick per point of
## Intellect), spell_power_scale (per second per point of Spell Power), heal_pct, range,
## auto_cast_hp (bots: cast below this HP %).

## The drain holds until the target is this much further than the range.
const BREAK_SLACK := 1.25
const TIME_EPSILON := 0.0001
const SPARK_COLOR := Color(0.6, 0.3, 0.9)

## The enemy being drained (null when not channelling).
var target: Enemy
## Seconds of channel left (0 = not channelling).
var channel_left := 0.0
## Ticks done / planned in the current channel.
var ticks_done := 0
var ticks_total := 0
## Totals of the current (or last) channel – tests, stats.
var damage_total := 0.0
var healed_total := 0.0
var beam: WarlockDrainBeam

var _player: Player
var _tick := 0.4
var _tick_left := 0.0
var _tick_damage := 0.0
var _heal_ratio := 1.0
var _range := 8.0
var _school: StringName = &"shadow"


## Shadow damage of one tick for [param stats] with [param params] (before the target
## bonuses and the owner's outgoing multipliers, which ProcSystem.deal_raw applies).
static func tick_damage(stats: StatBlock, params: Dictionary, school: StringName = &"shadow") -> float:
	var tick := float(params.get("tick", 0.4))
	var flat := float(params.get("damage", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.INTELLECT)) * float(params.get("intellect_scale", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.SPELL_POWER)) * float(params.get("spell_power_scale", 0.0)) * tick
	return maxf(CombatMath.MIN_DAMAGE, flat * CombatMath.damage_mult_for(stats, school))


func is_channeling() -> bool:
	return ticks_total > 0 and ticks_done < ticks_total


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null and not is_channeling()


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or not _is_live(ctx.target):
		return false
	var e := ctx.target as Enemy
	_player = p
	_school = ctx.ability.school
	_tick = maxf(0.05, ctx.num("tick", 0.4))
	var duration := maxf(_tick, ctx.num("duration", 2.0))
	_range = maxf(0.5, ctx.num("range", ctx.ability.cast_range))
	_tick_damage = tick_damage(p.stats, ctx.params, _school)
	_heal_ratio = maxf(0.0, ctx.num("heal_pct", 100.0) / 100.0)
	target = e
	channel_left = duration
	ticks_total = maxi(1, roundi(duration / _tick))
	ticks_done = 0
	_tick_left = _tick
	damage_total = 0.0
	healed_total = 0.0
	if not p.downed_changed.is_connected(_on_downed_changed):
		p.downed_changed.connect(_on_downed_changed)
	if beam != null and is_instance_valid(beam):
		beam.finish()
	beam = WarlockDrainBeam.create(p, e)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if not is_channeling():
		return
	if _player == null or not is_instance_valid(_player) or _player.downed or not _player.is_inside_tree():
		stop()
		return
	channel_left = maxf(0.0, channel_left - delta)
	if not _holds(target) and not _retarget():
		stop()
		return
	_tick_left -= delta
	while _tick_left <= TIME_EPSILON and is_channeling():
		_tick_left += _tick
		_drain_once()
		if is_channeling() and not _holds(target) and not _retarget():
			stop()
			return
	if not is_channeling():
		stop()


## Ends the channel (and the beam) now.
func stop() -> void:
	channel_left = 0.0
	ticks_done = ticks_total
	target = null
	if beam != null and is_instance_valid(beam):
		beam.finish()
	beam = null


## Wave start: a channel never carries over into the next wave.
func begin_wave(_ctx: AbilityContext) -> void:
	if is_channeling():
		stop()


## Bots: hurt (HP below auto_cast_hp %) and an enemy within range.
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or ctx.target == null or is_channeling():
		return false
	var m := p.max_hp()
	return m > 0.0 and p.hp / m * 100.0 < ctx.num("auto_cast_hp", 70.0)


func _drain_once() -> void:
	ticks_done += 1
	if not _is_live(target) or _player.procs == null:
		return
	var e := target
	var hp_before := maxf(0.0, e.hp)
	var dealt := _player.procs.deal_raw(e, _tick_damage, _school, true, &"ability")
	var real := minf(dealt, hp_before)
	damage_total += dealt
	Vfx.hit_spark(e.global_position + Vector3.UP * Player.CHEST_HEIGHT, SPARK_COLOR)
	var heal := real * _heal_ratio
	if heal > 0.0:
		var before := _player.hp
		_player.heal(heal)
		healed_total += maxf(0.0, _player.hp - before)


## The target is still drainable (alive, in the tree, within range x BREAK_SLACK).
func _holds(e: Variant) -> bool:
	if not _is_live(e):
		return false
	var reach := _range * BREAK_SLACK
	var pos: Vector3 = (e as Enemy).global_position
	return WeaponRunner.flat(pos - _player.global_position).length_squared() <= reach * reach


## Jumps to the nearest enemy within range. False when there is none.
func _retarget() -> bool:
	var next := EnemyGrid.nearest(_player.get_tree(), _player.global_position, _range)
	if next == null:
		return false
	target = next
	if beam != null and is_instance_valid(beam):
		beam.target = next
	return true


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed and is_channeling():
		stop()


static func _is_live(e: Variant) -> bool:
	if not is_instance_valid(e):
		return false
	var enemy := e as Enemy
	return enemy != null and enemy.is_inside_tree() and not enemy.is_dead()
