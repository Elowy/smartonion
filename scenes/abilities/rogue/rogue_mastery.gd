class_name RogueMastery
extends MasteryEffect
## Mastery "Deadly Poison" (GDD 3.4): a critical weapon hit poisons the target. Every crit adds
## a poison stack (up to MAX_STACKS) and refreshes the duration; one stack deals
## (BASE_PCT + PCT_PER_MASTERY x Mastery) % of the crit's damage as Nature damage spread over
## DURATION seconds (a full stack bar replaces an average stack instead). Ticks every TICK
## seconds through ProcSystem.deal_raw(..., &"dot") – no weapon hit (no procs, no crits), but
## Executioner / Slayer and the outgoing damage multipliers apply, and kills are credited.
## A crit that killed its target poisons the nearest living enemy within 2.5 m of it instead
## ([CritDot]). The poison keeps ticking while the Rogue is downed (MasteryEffect.tick).
## The tracker is per enemy, lives in this object and is cleared at wave start.
##
## M5 talents – pseudo ability id [constant PSEUDO_ID] (BonusVocabulary.PSEUDO_IDS), params
## [constant BASE] read through AbilityRunner.apply_mods(BASE, player.ability_mods(PSEUDO_ID)):
##   max_stacks   (5) – stacks one enemy can carry (Master Poisoner: max_stacks_add),
##   kill_energy  (0) – Energy (ClassResource.add: Resource Regen applies) when an enemy
##                      carrying this Rogue's poison dies and the kill is credited to this
##                      Rogue (MasteryEffect.on_kill – never while downed; Venomous Wounds:
##                      kill_energy_add).
## The params are cached and re-read after PlayerBonuses.changed (the engine is created after
## the Mastery, so the first read connects the signal). [method consume] (Envenom) takes an
## enemy's whole poison off it and returns the undealt damage; the enemy still counts as
## poisoned for kill_energy until the next tick (an Envenom burst that kills it).

## Pseudo ability id of the Deadly Poison numbers (talents_rogue.md 4.4).
const PSEUDO_ID := &"rogue_deadly_poison"
## The pseudo id's base params (talents / sets change them with _add / _pct / replace keys).
const BASE := {"max_stacks": 5, "kill_energy": 0.0}

const DURATION := 4.0
const TICK := 0.5
## Default stack limit (BASE "max_stacks").
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
## Enemies whose poison [method consume] took this tick (still "poisoned" for kill_energy).
var _consumed: Dictionary[int, bool] = {}
## Cached BASE params (see [method _ensure_params]).
var _max_stacks := MAX_STACKS
var _kill_energy := 0.0
var _params_ready := false


## Total damage one stack deals over DURATION for a crit that did [param hit_damage].
func stack_damage(hit_damage: float) -> float:
	return maxf(0.0, hit_damage) * (BASE_PCT + PCT_PER_MASTERY * mastery()) / 100.0


func on_hit(target: Node3D, damage: float, is_crit: bool) -> void:
	if not is_crit or damage <= 0.0 or player == null:
		return
	var enemy := CritDot.target_for(target)  # (a killing crit spreads to a neighbour)
	if enemy == null:
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
	if p.stacks < max_stacks():
		p.stacks += 1
		p.dps += stack_dps
	else:
		p.dps += stack_dps - p.dps / float(p.stacks)
	p.left = DURATION


func tick(delta: float) -> void:
	if not _consumed.is_empty():
		_consumed.clear()
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
	_consumed.clear()


func teardown() -> void:
	_poisons.clear()
	_consumed.clear()
	if player != null and player.bonuses != null and player.bonuses.changed.is_connected(_on_bonuses_changed):
		player.bonuses.changed.disconnect(_on_bonuses_changed)


## Venomous Wounds: an enemy this Rogue killed (alive Rogues only – Player.notify_kill) that
## carried its poison, or whose poison Envenom consumed this tick, gives kill_energy Energy.
func on_kill(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy) or player == null or player.abilities == null:
		return
	_ensure_params()
	if _kill_energy <= 0.0:
		return
	var id := enemy.get_instance_id()
	if not _poisons.has(id) and not _consumed.has(id):
		return
	var energy := player.abilities.get_resource(RogueUtil.ENERGY_ID)
	if energy != null:
		energy.add(_kill_energy)


## Envenom: removes the whole poison from [param enemy] and returns the damage it had not dealt
## yet (dps x (time left + time since the last tick)); 0 when it carries none. The enemy is
## remembered until the next tick, so a kill by the burst still counts as a poisoned death.
func consume(enemy: Enemy) -> float:
	if enemy == null or not is_instance_valid(enemy):
		return 0.0
	var id := enemy.get_instance_id()
	var p: Poison = _poisons.get(id)
	if p == null:
		return 0.0
	_poisons.erase(id)
	_consumed[id] = true
	return maxf(0.0, p.dps * (p.left + p.acc))


## Stacks one enemy can carry (BASE "max_stacks" after the talent / set mods, at least 1).
func max_stacks() -> int:
	_ensure_params()
	return _max_stacks


## Energy per poisoned kill (BASE "kill_energy" after the mods).
func kill_energy() -> float:
	_ensure_params()
	return _kill_energy


## Reads the pseudo id's params once per PlayerBonuses change. Stays unread (defaults) until
## the hero's bonus engine exists (it is created after the Mastery).
func _ensure_params() -> void:
	if _params_ready:
		return
	if player == null or player.bonuses == null:
		_max_stacks = MAX_STACKS
		_kill_energy = 0.0
		return
	if not player.bonuses.changed.is_connected(_on_bonuses_changed):
		player.bonuses.changed.connect(_on_bonuses_changed)
	var p := AbilityRunner.apply_mods(BASE, player.ability_mods(PSEUDO_ID))
	_max_stacks = maxi(1, roundi(float(p.get("max_stacks", MAX_STACKS))))
	_kill_energy = maxf(0.0, float(p.get("kill_energy", 0.0)))
	_params_ready = true


func _on_bonuses_changed() -> void:
	_params_ready = false


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
	return "Lethal Venom: critical hits poison the target for %s%% of the hit's damage over %d sec (stacks up to %d times)." % [
			String.num(BASE_PCT + PCT_PER_MASTERY * mastery(), 1).trim_suffix(".0"), int(DURATION), max_stacks()]
