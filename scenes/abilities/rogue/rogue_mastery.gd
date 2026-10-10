class_name RogueMastery
extends MasteryEffect
## Mastery "Deadly Poison" (GDD 3.4): a critical weapon hit poisons the target. Every crit adds
## a poison stack (up to MAX_STACKS) and refreshes the duration; one stack deals
## (BASE_PCT + PCT_PER_MASTERY x Mastery) % of the crit's damage as Nature damage spread over
## DURATION seconds (a full stack bar replaces an average stack instead). Ticks every TICK
## seconds through ProcSystem.deal_raw(..., &"dot") – no weapon hit (no procs, no crits), but
## Executioner / Slayer and the outgoing damage multipliers apply, and kills are credited.
## The tracker is per enemy, lives in this object and is cleared at wave start.

const DURATION := 4.0
const TICK := 0.5
const MAX_STACKS := 5
const BASE_PCT := 20.0
const PCT_PER_MASTERY := 1.0
const SCHOOL := &"nature"
const TIME_EPSILON := 0.0001


## One poisoned enemy.
class Poison extends RefCounted:
	var target_id := 0
	var stacks := 0
	## Damage per second of all stacks together.
	var dps := 0.0
	var left := 0.0
	## Time passed since the last tick (poison time, flushed when it expires).
	var acc := 0.0

var _poisons: Dictionary[int, Poison] = {}


## Total damage one stack deals over DURATION for a crit that did [param hit_damage].
func stack_damage(hit_damage: float) -> float:
	return maxf(0.0, hit_damage) * (BASE_PCT + PCT_PER_MASTERY * mastery()) / 100.0


func on_hit(target: Node3D, damage: float, is_crit: bool) -> void:
	if not is_crit or damage <= 0.0 or player == null:
		return
	var enemy := target as Enemy
	if enemy == null or not is_instance_valid(enemy) or enemy.is_dead():
		return
	poison(enemy, stack_damage(damage))


## Adds one stack worth [param total] damage over DURATION to [param enemy].
func poison(enemy: Enemy, total: float) -> void:
	if total <= 0.0:
		return
	var id := enemy.get_instance_id()
	var p: Poison = _poisons.get(id)
	if p == null:
		p = Poison.new()
		p.target_id = id
		_poisons[id] = p
	var stack_dps := total / DURATION
	if p.stacks < MAX_STACKS:
		p.stacks += 1
		p.dps += stack_dps
	else:
		p.dps += stack_dps - p.dps / float(p.stacks)
	p.left = DURATION


func tick(delta: float) -> void:
	if _poisons.is_empty() or player == null or player.procs == null:
		return
	for id in _poisons.keys():
		var p := _poisons[id]
		var enemy := instance_from_id(id) as Enemy
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_inside_tree() or enemy.is_dead():
			_poisons.erase(id)
			continue
		var step := minf(delta, p.left)
		p.left -= step
		p.acc += step
		if p.acc >= TICK - TIME_EPSILON or p.left <= TIME_EPSILON:
			var amount := p.dps * p.acc
			p.acc = 0.0
			player.procs.deal_raw(enemy, amount, SCHOOL, false, &"dot")
		if p.left <= TIME_EPSILON:
			_poisons.erase(id)


func begin_wave() -> void:
	_poisons.clear()


func teardown() -> void:
	_poisons.clear()


## Poison stacks on [param enemy] (0 = not poisoned) – tests, UI.
func stacks_on(enemy: Node3D) -> int:
	if enemy == null:
		return 0
	var p: Poison = _poisons.get(enemy.get_instance_id())
	return p.stacks if p != null else 0


## Poison damage per second on [param enemy] (all stacks).
func dps_on(enemy: Node3D) -> float:
	if enemy == null:
		return 0.0
	var p: Poison = _poisons.get(enemy.get_instance_id())
	return p.dps if p != null else 0.0


func poisoned_count() -> int:
	return _poisons.size()


func describe() -> String:
	return "Deadly Poison: critical hits poison the target for %s%% of the hit's damage over %d sec (stacks up to %d times)." % [
			String.num(BASE_PCT + PCT_PER_MASTERY * mastery(), 1).trim_suffix(".0"), int(DURATION), MAX_STACKS]
