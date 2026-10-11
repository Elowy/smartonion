class_name WarriorExecute
extends AbilityEffect
## Execute (GDD 6.4, Warrior Active): a huge strike on an enemy in melee reach for
## [code]damage_pct[/code] % weapon damage (times "power"). An enemy below
## [code]threshold[/code] % HP dies outright (elites too); bosses ([method Enemy.is_boss]) are
## never killed outright – below the threshold they take [code]boss_mult[/code] x damage
## instead.
##
## The strike picks its victim among the enemies within the ability's cast range: an
## executable one first (the one with the most HP left: the biggest saving), else an elite /
## boss (lowest HP share), else the nearest.
##
## Params (AbilityData.params; items and ranks change them):
##   damage_pct, threshold (% HP; Rank III +10), boss_mult
##   arc         Rank V "Sweeping Strikes": every enemy in an arc of this many degrees in front
##               of the hero (towards the victim) is struck and checked for execution (0 = one)
##   kill_reset  Rank V "Massacre": a kill sets the remaining cooldown to this many seconds
##               (0 = off)
##
## Bots strike when the victim is an elite / boss or has at least AUTO_WORTH of the hit's
## damage left (no wasting the big hit on scraps).

const DEFAULT_THRESHOLD := 20.0
const DEFAULT_BOSS_MULT := 2.0
const AUTO_WORTH := 0.4
const SLASH_COLOR := Color(0.9, 0.15, 0.1)
const TEXT_COLOR := Color(1.0, 0.25, 0.2)
const SPARK_COLOR := Color(1.0, 0.35, 0.25)
## Floating "Execute!" texts per cast (Sweeping Strikes can execute a crowd).
const MAX_TEXTS := 3

## Enemies struck / executed by the last cast (tests).
var last_struck := 0
var last_executed := 0
var last_victim: Enemy

var _reset_pending := -1.0


## Below the threshold and not a boss: dies to the strike.
static func is_executable(e: Enemy, threshold_pct: float) -> bool:
	if e == null or not is_instance_valid(e) or e.is_dead() or e.hp <= 0.0 or e.max_hp <= 0.0 or e.is_boss():
		return false
	return e.hp / e.max_hp <= threshold_pct / 100.0 + 0.000001


## The enemy the strike goes to (see the class notes), null when nobody is in reach.
static func pick_victim(player: Player, reach: float, threshold_pct: float) -> Enemy:
	var best_exec: Enemy = null
	var best_big: Enemy = null
	var nearest: Enemy = null
	var nearest_d := INF
	for e in WarriorKit.enemies_within(player, reach):
		if is_executable(e, threshold_pct):
			if best_exec == null or e.hp > best_exec.hp:
				best_exec = e
		elif e.is_elite():
			if best_big == null or e.hp / maxf(0.001, e.max_hp) < best_big.hp / maxf(0.001, best_big.max_hp):
				best_big = e
		var d := WeaponRunner.flat(e.global_position - player.global_position).length()
		if d < nearest_d:
			nearest_d = d
			nearest = e
	if best_exec != null:
		return best_exec
	return best_big if best_big != null else nearest


## Damage of one strike before target bonuses and multipliers.
static func hit_damage(player: Player, ctx: AbilityContext) -> float:
	return WarriorKit.weapon_damage(player) * ctx.num("damage_pct", 300.0) / 100.0 * ctx.num("power", 1.0)


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	var victim := pick_victim(p, ctx.ability.cast_range, ctx.num("threshold", DEFAULT_THRESHOLD))
	if victim == null:
		return false
	return victim.is_elite() or victim.hp >= hit_damage(p, ctx) * AUTO_WORTH


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	last_struck = 0
	last_executed = 0
	last_victim = null
	if p == null or not p.is_inside_tree() or p.procs == null:
		return false
	var threshold := ctx.num("threshold", DEFAULT_THRESHOLD)
	var victim := pick_victim(p, ctx.ability.cast_range, threshold)
	if victim == null:
		return false
	last_victim = victim
	var here := p.global_position
	var dir := Vector3(victim.global_position.x - here.x, 0.0, victim.global_position.z - here.z)
	if dir.length_squared() < 0.0001:
		dir = Vector3(p.facing.x, 0.0, p.facing.z)
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	p.face_attack(dir)
	var victims: Array[Enemy] = [victim]
	var arc := ctx.num("arc")
	if arc > 0.0:
		for e in WarriorKit.enemies_in_arc(p, ctx.ability.cast_range, dir, arc):
			if e != victim:
				victims.append(e)
	var hit := hit_damage(p, ctx)
	var boss_mult := ctx.num("boss_mult", DEFAULT_BOSS_MULT)
	var kills := 0
	var texts := 0
	for e in victims:
		if not is_instance_valid(e) or e.is_dead():
			continue
		var pos := e.global_position
		var executed := strike(p, e, hit, threshold, boss_mult, ctx.ability.school)
		last_struck += 1
		var dead := not is_instance_valid(e) or e.is_dead() or e.hp <= 0.0
		if dead:
			kills += 1
		if executed:
			last_executed += 1
			if texts < MAX_TEXTS:
				texts += 1
				Vfx.floating_text(pos + Vector3.UP * 1.6, "Execute!", TEXT_COLOR, 1.1)
		if e == victim:
			WarriorExecuteVfx.spawn(pos, executed or dead)
		else:
			Vfx.hit_spark(pos + Vector3.UP * WarriorSpin.SPARK_HEIGHT, SPARK_COLOR)
	Vfx.slash_arc(here + Vector3.UP * 0.3, dir, ctx.ability.cast_range, maxf(arc, 70.0), SLASH_COLOR)
	if kills > 0 and ctx.num("kill_reset") > 0.0:
		# The runner starts the cooldown after cast() returns: shorten it on the next tick.
		_reset_pending = ctx.num("kill_reset")
	return true


## One strike on [param e]: [param hit] damage, boss_mult x on a boss below the threshold, a
## kill on any other enemy below it. Returns true when it was an execution.
static func strike(p: Player, e: Enemy, hit: float, threshold_pct: float, boss_mult: float,
		school: StringName) -> bool:
	var ratio := e.hp / e.max_hp if e.max_hp > 0.0 else 1.0
	var below := ratio <= threshold_pct / 100.0 + 0.000001
	var amount := hit
	if below and e.is_boss():
		amount *= boss_mult
	var execute := below and not e.is_boss()
	if execute:
		# Enough to finish it whatever the multipliers (outgoing and target bonuses).
		var mult := p.outgoing_damage_mult(e, school, &"ability") \
				* CombatMath.target_damage_mult(p.stats, ratio, e.is_elite())
		if mult > 0.0:
			amount = maxf(amount, e.hp / mult * 1.001 + 0.01)
	p.procs.deal_raw(e, amount, school, true, &"ability")
	if execute and is_instance_valid(e) and not e.is_dead() and e.hp > 0.0:
		e.take_damage(e.hp, false, p)
	return execute


func tick(ctx: AbilityContext, _delta: float) -> void:
	if _reset_pending < 0.0:
		return
	var seconds := _reset_pending
	_reset_pending = -1.0
	var runner := ctx.player.abilities if ctx.player != null else null
	if runner == null:
		return
	var slot := runner.slot_of(ctx.ability.id)
	if slot >= 0 and runner.remaining(slot) > seconds:
		runner.set_cooldown(ctx.ability, seconds)


func begin_wave(_ctx: AbilityContext) -> void:
	_reset_pending = -1.0


func end_wave(_ctx: AbilityContext) -> void:
	_reset_pending = -1.0
