class_name MageFireCombustion
extends TalentEffect
## Combustion – the Mage Fire capstone (GDD 7.5, talents_mage.md 2.3): when the FIRST hit of a
## weapon attack is a critical strike (on_hit with [code]first[/code] – wand / staff bolts,
## melee, extra attacks; Ice Lance's forced crits count), the area around the target is set
## ablaze: the target (also when the crit killed it – its position is the centre) and the
## nearest living enemies within [code]radius[/code] m x Area Size, up to
## [code]max_targets[/code] in all, nearest first, get a [MageBurn] of this Mage worth
## [code]burn_pct[/code] % of the hit's base amount over [code]duration[/code] s. A Staff bolt's
## explosion reports every enemy it hits with the same crit, but only the first counts, so the
## burns do not grow with the square of the pack.
##
## The base amount (vocabulary §3.6: after the crit, before your outgoing multipliers) goes into
## the burn, whose ticks (Fire, &"dot", ProcSystem.deal_raw) apply Fire Power, Incineration and
## Mastery exactly once. A running burn of this Mage absorbs the new total and restarts its
## clock (an armed Living Bomb stays armed). An enemy that got a Combustion burn less than
## [code]refresh_icd[/code] s ago is skipped (it does not count towards the targets). Abilities
## never crit, so spells do not trigger it; Player.on_hit_dealt is not called while downed, so
## a downed Mage starts no new fires (running burns keep burning).
##
## State: an internal clock (advanced in [method tick], so it is deterministic under
## --fixed-fps), the per-enemy refresh times (pruned of freed / old ids beyond
## [constant PRUNE_AT] entries) and the fire-ring VFX timer – cleared at wave start / end and
## on teardown. No RNG. Passive for bots.
##
## Params (not rank-scaled; capstone, rank 1): burn_pct (%), radius (m), duration (s),
## max_targets, refresh_icd (s), fx_icd (s).

const PRUNE_AT := 64
const RING_HEIGHT := 0.3

## Combustions that went off (tests).
var combustions := 0
## Burns started / refreshed by Combustion (tests).
var burns := 0

var _burn_share := 0.2
var _radius := 2.5
var _duration := 3.0
var _max_targets := 4
var _refresh_icd := 1.0
var _fx_icd := 0.25
## Seconds since setup / the last wave start (the refresh times are on this clock).
var _clock := 0.0
## Enemy instance id -> _clock when Combustion last burned it.
var _burned_at: Dictionary[int, float] = {}
var _fx_left := 0.0


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_burn_share = maxf(0.0, num("burn_pct", 20.0)) / 100.0
	_radius = maxf(0.0, num("radius", 2.5))
	_duration = maxf(0.1, num("duration", 3.0))
	_max_targets = maxi(1, int(num("max_targets", 4.0)))
	_refresh_icd = maxf(0.0, num("refresh_icd", 1.0))
	_fx_icd = maxf(0.0, num("fx_icd", 0.25))


func on_hit(target: Node3D, damage: float, is_crit: bool, first: bool) -> void:
	if not first or not is_crit or damage <= 0.0 or _burn_share <= 0.0:
		return
	if player == null or not player.is_inside_tree() or target == null or not is_instance_valid(target) \
			or not target.is_inside_tree():
		return
	var centre := target.global_position
	var reach := _radius * MageSpell.area_mult(player)
	var pool := MageSpell.enemies_in(player.get_tree(), centre, reach, false)
	var total := damage * _burn_share
	var lit := 0
	while lit < _max_targets and not pool.is_empty():
		var best := _nearest(pool, centre)
		var e := pool[best]
		pool.remove_at(best)
		var id := e.get_instance_id()
		if _burned_at.has(id) and _clock - _burned_at[id] < _refresh_icd:
			continue
		if MageBurn.apply(e, player, total, _duration, MageSpell.FIRE) == null:
			continue
		_burned_at[id] = _clock
		lit += 1
	if lit == 0:
		return
	combustions += 1
	burns += lit
	if _burned_at.size() > PRUNE_AT:
		_prune()
	if _fx_left <= 0.0:
		_fx_left = _fx_icd
		Vfx.explosion(WeaponRunner.flat(centre) + Vector3.UP * RING_HEIGHT, maxf(0.5, reach), MageSpell.FIRE_COLOR)


func tick(delta: float) -> void:
	_clock += delta
	if _fx_left > 0.0:
		_fx_left -= delta


func begin_wave() -> void:
	_reset()


func end_wave() -> void:
	_reset()


func teardown() -> void:
	_reset()


## True while [param enemy] may not get another Combustion burn (tests).
func is_on_refresh_cooldown(enemy: Node3D) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var id := enemy.get_instance_id()
	return _burned_at.has(id) and _clock - _burned_at[id] < _refresh_icd


func describe() -> String:
	return "Combustion: %d fires started" % combustions


## Index of the enemy in [param pool] nearest to [param centre] (XZ; ties: the earlier one –
## group order).
static func _nearest(pool: Array[Enemy], centre: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in pool.size():
		var dx := pool[i].global_position.x - centre.x
		var dz := pool[i].global_position.z - centre.z
		var d := dx * dx + dz * dz
		if d < best_d:
			best_d = d
			best = i
	return best


## Drops the refresh times of freed enemies and of those whose cooldown is over.
func _prune() -> void:
	for id: int in _burned_at.keys():
		if not is_instance_id_valid(id) or _clock - _burned_at[id] >= _refresh_icd:
			_burned_at.erase(id)


func _reset() -> void:
	_clock = 0.0
	_fx_left = 0.0
	_burned_at.clear()
