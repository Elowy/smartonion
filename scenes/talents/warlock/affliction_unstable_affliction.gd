class_name WarlockAfflictionUnstableAffliction
extends TalentEffect
## Unstable Affliction – the Warlock Affliction capstone (GDD 7.5, talents_warlock.md §1.3;
## reinterpreted: enemies never dispel, so "removed early" is death, and Silence is a stun):
## when an enemy dies – any hero's kill, a DoT tick, a burst – while it carries at least one
## of this Warlock's afflictions (Agony, Corruption, Seed of Corruption, Fear's Dread), it
## bursts with unstable shadow: Shadow damage to every enemy within [code]radius[/code] m (x
## Area Size) and a [code]stun[/code]-second stun on the survivors, each enemy at most once
## every [code]stun_icd[/code] seconds (Enemy.apply_stun – an elite's stun resistance
## shortens it).
##
## The death is reported by WarlockAfflictions.afflicted_died, which only QUEUES the corpse's
## position (FIFO, at most queue_cap; the oldest is dropped) – nothing is dealt inside the
## died chain. [method tick] bursts up to max_per_tick queued positions per physics tick; a
## burst that kills an afflicted neighbour queues its burst for a later tick, so a cursed pack
## goes off as a chain reaction, one link per tick. Burst damage is built from the Warlock's
## stats: WarlockSpell.damage(stats, params, &"shadow") – damage + Intellect x
## intellect_scale + Spell Power x spell_power_scale, x Versatility / Damage % / Shadow % –
## dealt with deal_raw(..., target_bonus = true, &"ability"). Runs while the Warlock is down
## (its afflictions keep ticking; the bursts protect it and its reviver). A despawned enemy
## (wave end) does not die – nothing. No RNG. Passive for bots.
## Wave start / end clear the queue and the stun memory; teardown disconnects the signal.
##
## Params (not rank-scaled; capstone, rank 1): damage, intellect_scale, spell_power_scale,
## radius (m), stun (s), stun_icd (s), max_per_tick, queue_cap.

const SCHOOL := &"shadow"
## The stun memory is pruned of expired entries beyond this size.
const PRUNE_AT := 256

## Bursts so far (tests, stats).
var bursts := 0
## Enemies stunned by the bursts so far (tests, stats).
var stuns := 0

var _afflictions: WarlockAfflictions
var _radius := 3.0
var _stun := 1.0
var _stun_icd := 4.0
var _max_per_tick := 4
var _queue_cap := 32
## Corpse positions waiting to burst (oldest first).
var _queue: Array[Vector3] = []
## Seconds since setup (the stun memory's clock).
var _time := 0.0
## Enemy instance id -> the time it may be stunned again.
var _stun_until: Dictionary[int, float] = {}
var _expired: Array[int] = []


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_radius = maxf(0.1, num("radius", 3.0))
	_stun = maxf(0.0, num("stun", 1.0))
	_stun_icd = maxf(0.0, num("stun_icd", 4.0))
	_max_per_tick = maxi(1, int(num("max_per_tick", 4.0)))
	_queue_cap = maxi(1, int(num("queue_cap", 32.0)))
	_hook()


## Positions waiting to burst (tests).
func pending() -> int:
	return _queue.size()


## True while [param e] cannot be stunned by a burst again.
func stun_locked(e: Node3D) -> bool:
	return e != null and is_instance_valid(e) and _stun_until.get(e.get_instance_id(), -1.0) > _time


## Damage of one burst on one enemy for the Warlock's current stats.
func burst_damage() -> float:
	return WarlockSpell.damage(player.stats, params, SCHOOL) if player != null else 0.0


func tick(delta: float) -> void:
	_time += delta
	if _queue.is_empty():
		return
	if _afflictions == null or not is_instance_valid(_afflictions):
		_hook()
	var n := mini(_max_per_tick, _queue.size())
	for i in n:
		_burst(_queue.pop_front())


func begin_wave() -> void:
	_hook()
	_reset()


func end_wave() -> void:
	_reset()


func teardown() -> void:
	if _afflictions != null and is_instance_valid(_afflictions) \
			and _afflictions.afflicted_died.is_connected(_on_afflicted_died):
		_afflictions.afflicted_died.disconnect(_on_afflicted_died)
	_afflictions = null
	_reset()


func describe() -> String:
	return "Unstable Affliction: %d bursts" % bursts


## Connects to the Warlock's afflictions node (created when missing).
func _hook() -> void:
	if player == null or not is_instance_valid(player):
		return
	var aff := WarlockAfflictions.of(player)
	if aff == _afflictions:
		return
	if _afflictions != null and is_instance_valid(_afflictions) \
			and _afflictions.afflicted_died.is_connected(_on_afflicted_died):
		_afflictions.afflicted_died.disconnect(_on_afflicted_died)
	_afflictions = aff
	if aff != null and not aff.afflicted_died.is_connected(_on_afflicted_died):
		aff.afflicted_died.connect(_on_afflicted_died)


## Inside the dying enemy's died chain: only remember where (the burst comes on the next tick).
func _on_afflicted_died(at: Vector3) -> void:
	if _queue.size() >= _queue_cap:
		_queue.pop_front()
	_queue.append(Vector3(at.x, 0.0, at.z))


func _burst(center: Vector3) -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree() or player.procs == null:
		return
	bursts += 1
	var r := WarlockSpell.area(player.stats, _radius)
	var dmg := burst_damage()
	WarlockVfx.unstable_burst(center, r)
	for e in WarlockSpell.enemies_in_circle(player.get_tree(), center, r):
		if not WarlockSpell.is_live(e):
			continue
		player.procs.deal_raw(e, dmg, SCHOOL, true, &"ability")
		if _stun <= 0.0 or not WarlockSpell.is_live(e):
			continue
		var id := e.get_instance_id()
		if _stun_until.get(id, -1.0) > _time:
			continue
		e.apply_stun(_stun)
		_stun_until[id] = _time + _stun_icd
		stuns += 1
	if _stun_until.size() > PRUNE_AT:
		_prune()


## Drops the stun memory of enemies that may be stunned again (or are gone).
func _prune() -> void:
	_expired.clear()
	for id in _stun_until:
		if _stun_until[id] <= _time or not is_instance_id_valid(id):
			_expired.append(id)
	for id in _expired:
		_stun_until.erase(id)


func _reset() -> void:
	_queue.clear()
	_stun_until.clear()
	_expired.clear()
