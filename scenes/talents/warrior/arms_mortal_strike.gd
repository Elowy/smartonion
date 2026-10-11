class_name WarriorArmsMortalStrike
extends TalentEffect
## Mortal Strike – the Warrior Arms capstone (GDD 7.5, talent_vocabulary.md §6): every 5th
## weapon ATTACK also strikes its target for 150% weapon damage and leaves a Mortal Wound for
## 8 sec: the target heals 50% less (Enemy.apply_healing_reduction – Vampiric elites) and takes
## 10% more damage from you, Execute included ([method damage_mult]).
##
## Attacks are counted with on_hit's [code]first[/code] (the attack's ProcGate hit): a swing
## that strikes five enemies counts once, and extra attacks / ripostes count as attacks of their
## own. The strike is WarriorKit.weapon_damage x strike_pct, built from the hero's stats, so it
## goes out with deal_raw(..., target_bonus = true, &"ability") (talent_vocabulary §3.7). If the
## counted attack's target is already dead (the hit killed it), the strike is held for the next
## attack instead of being wasted on a corpse.
## Wave start / end clear the counter and the wounds (the Enemy keeps its own healing
## reduction timer). Passive for bots.
##
## Params (not rank-scaled; capstone, rank 1): every, strike_pct, wound_duration,
## heal_reduction (%), damage_taken_pct (%).

const SLASH_COLOR := Color(0.85, 0.1, 0.08)
const SPARK_COLOR := Color(1.0, 0.3, 0.2)
const SLASH_RADIUS := 1.6
const SLASH_ARC := 80.0

## Attacks counted towards the next strike (0 .. every - 1; every = a strike is held).
var attacks := 0
## Strikes dealt (tests, UI).
var strikes := 0

var _every := 5
var _strike_mult := 1.5
var _wound_duration := 8.0
var _heal_reduction := 50.0
var _wound_mult := 1.1
## Enemy instance id -> seconds of Mortal Wound left.
var _wounds: Dictionary[int, float] = {}
## Reused by tick (no allocation per frame).
var _expired: Array[int] = []


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_every = maxi(1, int(num("every", 5.0)))
	_strike_mult = num("strike_pct", 150.0) / 100.0
	_wound_duration = num("wound_duration", 8.0)
	_heal_reduction = num("heal_reduction", 50.0)
	_wound_mult = 1.0 + num("damage_taken_pct", 10.0) / 100.0


## True while [param enemy] carries this hero's Mortal Wound.
func is_wounded(enemy: Node3D) -> bool:
	return enemy != null and is_instance_valid(enemy) and _wounds.has(enemy.get_instance_id())


func damage_mult(target: Node3D, _school: StringName, _source: StringName) -> float:
	if _wounds.is_empty() or target == null or not is_instance_valid(target):
		return 1.0
	return _wound_mult if _wounds.has(target.get_instance_id()) else 1.0


func on_hit(target: Node3D, _damage: float, _is_crit: bool, first: bool) -> void:
	if not first:
		return
	attacks = mini(attacks + 1, _every)
	if attacks < _every:
		return
	var e: Enemy = target as Enemy if target != null and is_instance_valid(target) else null
	if e == null or e.is_dead():
		return  # held: the next attack strikes
	attacks = 0
	_strike(e)


func tick(delta: float) -> void:
	if _wounds.is_empty():
		return
	_expired.clear()
	for id in _wounds:
		var left := _wounds[id] - delta
		if left <= 0.0 or not is_instance_id_valid(id):
			_expired.append(id)
		else:
			_wounds[id] = left
	for id in _expired:
		_wounds.erase(id)


func begin_wave() -> void:
	_reset()


func end_wave() -> void:
	_reset()


func teardown() -> void:
	_reset()


func describe() -> String:
	return "Mortal Strike: %d / %d attacks" % [attacks, _every]


func _strike(e: Enemy) -> void:
	if player == null or player.procs == null:
		return
	strikes += 1
	var shown := player.is_inside_tree() and e.is_inside_tree()
	var pos := e.global_position if shown else Vector3.ZERO
	var amount := WarriorKit.weapon_damage(player) * _strike_mult
	player.procs.deal_raw(e, amount, &"physical", true, &"ability")
	if is_instance_valid(e) and not e.is_dead():
		e.apply_healing_reduction(_heal_reduction, _wound_duration)
		_wounds[e.get_instance_id()] = _wound_duration
	if shown:
		var here := player.global_position
		var dir := Vector3(pos.x - here.x, 0.0, pos.z - here.z)
		if dir.length_squared() < 0.0001:
			dir = Vector3(player.facing.x, 0.0, player.facing.z)
		if dir.length_squared() > 0.0001:
			Vfx.slash_arc(here + Vector3.UP * 0.3, dir.normalized(), SLASH_RADIUS, SLASH_ARC, SLASH_COLOR)
		Vfx.hit_spark(pos + Vector3.UP * WarriorSpin.SPARK_HEIGHT, SPARK_COLOR)


func _reset() -> void:
	attacks = 0
	_wounds.clear()
	_expired.clear()
