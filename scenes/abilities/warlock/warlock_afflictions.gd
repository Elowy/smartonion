class_name WarlockAfflictions
extends Node
## The damage-over-time effects one Warlock keeps on enemies (M4, GDD 6.4): Corruption, Seed
## of Corruption and the Dread of Fear. A child node of the Warlock ([method of]) – freed with
## it, ticking every physics frame on its own (also while the Warlock is downed: DoTs keep
## burning like item DoTs and Ignite; ability effects only tick while their hero lives).
##
## Ticks are DoT damage – ProcSystem.deal_raw(..., &"dot"), so Demonic Pact boosts them, the
## Warlock gets the kill credit and the damage meter counts them. Every enemy carries at most
## one affliction of each kind from this Warlock; re-applying one refreshes it.
## Corruption: when its enemy dies it jumps, with the time it had left, to the nearest
## uncorrupted enemies within its spread radius (spread_targets of them).
## Seed: when its host dies – or the seed ripens after its duration – it bursts: Shadow damage
## (&"ability") to every enemy in its radius; optionally a Blighted Ground pool and a new seed
## in a surviving victim (Chain Reaction).
## Order: the afflictions run in the order they were applied (deterministic). Markers
## ([WarlockAfflictionMarker]) show them on the enemies.

## A seed burst at [param center] hit [param victims] enemies.
signal seed_burst(center: Vector3, victims: int)
## A Corruption jumped from a corpse at [param from] to [param to].
signal corruption_spread(from: Vector3, to: Enemy)

const NODE_NAME := "WarlockAfflictions"
const CORRUPTION := &"corruption"
const SEED := &"seed"
const DREAD := &"dread"
## Seconds between damage ticks.
const TICK := 0.5
const EPSILON := 0.0001
## A Corruption with less time left than this does not spread.
const MIN_SPREAD_LEFT := 0.5
## Safety cap of afflictions per Warlock (new ones are refused beyond it).
const MAX_AFFLICTIONS := 60
const BURST_COLOR := Color(0.6, 0.3, 0.95)
const POOL_COLOR := Color(0.35, 0.8, 0.2, 0.32)


class Affliction extends RefCounted:
	var kind: StringName
	var enemy_id := 0
	var school: StringName = &"shadow"
	## Damage per second (already scaled by the spell; deal_raw adds the multipliers).
	var rate := 0.0
	var duration := 0.0
	var left := 0.0
	var tick_left := 0.5
	var owed := 0.0
	var last_pos := Vector3.ZERO
	var marker: WarlockAfflictionMarker
	var done := false
	## Damage dealt so far (tests, stats).
	var dealt := 0.0
	## Corruption: enemies it jumps to when its enemy dies, within spread_radius m; share of
	## the damage that heals the Warlock (Siphon Life).
	var spread_targets := 0
	var spread_radius := 0.0
	var heal_ratio := 0.0
	## Seed: burst damage / radius (Area Size included), further seeds it may plant (Chain
	## Reaction) and the Blighted Ground pool (seconds, unscaled radius, damage per tick, slow %).
	var burst_damage := 0.0
	var burst_radius := 0.0
	var chain_left := 0
	var pool_duration := 0.0
	var pool_radius := 0.0
	var pool_tick_damage := 0.0
	var pool_slow := 0.0

	func enemy() -> Enemy:
		return instance_from_id(enemy_id) as Enemy if enemy_id != 0 else null

	## A copy for another enemy (spreads, chained seeds).
	func copy_for(e: Enemy) -> Affliction:
		var a := Affliction.new()
		a.kind = kind
		a.enemy_id = e.get_instance_id()
		a.school = school
		a.rate = rate
		a.duration = duration
		a.left = duration
		a.spread_targets = spread_targets
		a.spread_radius = spread_radius
		a.heal_ratio = heal_ratio
		a.burst_damage = burst_damage
		a.burst_radius = burst_radius
		a.chain_left = chain_left
		a.pool_duration = pool_duration
		a.pool_radius = pool_radius
		a.pool_tick_damage = pool_tick_damage
		a.pool_slow = pool_slow
		return a


var player: Player
var _list: Array[Affliction] = []
## Per kind: enemy instance id -> its affliction.
var _by_kind: Dictionary[StringName, Dictionary] = {}
## Seed bursts so far (tests, stats).
var bursts := 0
var spreads := 0


## The afflictions node of [param p] (created as its child when missing and [param make]).
static func of(p: Player, make: bool = true) -> WarlockAfflictions:
	if p == null or not is_instance_valid(p):
		return null
	var node := p.get_node_or_null(NODE_NAME) as WarlockAfflictions
	if node != null and not node.is_queued_for_deletion():
		return node
	if not make:
		return null
	node = WarlockAfflictions.new()
	node.name = NODE_NAME
	node.player = p
	p.add_child(node)
	return node


# --- Applying ---------------------------------------------------------------------------------

## Corrupts [param e]: [param rate] damage per second for [param duration] seconds (refreshes
## a running Corruption). Null when the enemy is not alive or the cap is reached.
func corrupt(e: Enemy, rate: float, duration: float, spread_targets: int, spread_radius: float,
		heal_ratio: float = 0.0) -> Affliction:
	var a := _start(CORRUPTION, e, rate, duration)
	if a != null:
		a.spread_targets = maxi(0, spread_targets)
		a.spread_radius = maxf(0.0, spread_radius)
		a.heal_ratio = maxf(0.0, heal_ratio)
	return a


## Plants a seed in [param e] (its DoT: [param rate] per second for [param duration] s, then
## it bursts for [param burst_damage] in [param burst_radius] m). Configure the rest on the
## returned affliction (chain_left, pool_*). Null when the enemy is not alive.
func plant_seed(e: Enemy, rate: float, duration: float, burst_damage: float, burst_radius: float) -> Affliction:
	var a := _start(SEED, e, rate, duration)
	if a != null:
		a.burst_damage = maxf(0.0, burst_damage)
		a.burst_radius = maxf(0.1, burst_radius)
	return a


## Fear's Dread: [param rate] Shadow damage per second for [param duration] seconds.
func dread(e: Enemy, rate: float, duration: float) -> Affliction:
	return _start(DREAD, e, rate, duration)


func _start(kind: StringName, e: Enemy, rate: float, duration: float) -> Affliction:
	if not WarlockSpell.is_live(e) or duration <= 0.0:
		return null
	var a := get_affliction(kind, e)
	if a == null:
		if _list.size() >= MAX_AFFLICTIONS:
			return null
		a = Affliction.new()
		a.kind = kind
		a.enemy_id = e.get_instance_id()
		_list.append(a)
		_index(kind)[a.enemy_id] = a
	a.rate = maxf(0.0, rate)
	a.duration = duration
	a.left = duration
	a.last_pos = e.global_position
	_ensure_marker(a, e)
	return a


# --- Queries ----------------------------------------------------------------------------------

func has(kind: StringName, e: Node3D) -> bool:
	return e != null and is_instance_valid(e) and _index(kind).has(e.get_instance_id())


func get_affliction(kind: StringName, e: Node3D) -> Affliction:
	if e == null or not is_instance_valid(e):
		return null
	return _index(kind).get(e.get_instance_id())


## Running afflictions of [param kind] (&"" = all).
func count(kind: StringName = &"") -> int:
	if kind == &"":
		return _by_kind.values().reduce(func(acc: int, d: Dictionary) -> int: return acc + d.size(), 0)
	return _index(kind).size()


## Callable for WarlockSpell queries: enemies without an affliction of [param kind].
func lacks(kind: StringName) -> Callable:
	return func(e: Enemy) -> bool: return not has(kind, e)


## Drops every affliction of [param kind] (&"" = all) without bursts or spreads (wave start /
## end, a forgotten ability).
func clear(kind: StringName = &"") -> void:
	for a in _list:
		if kind == &"" or a.kind == kind:
			_end(a)
	_compact()


# --- Frame update -----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _list.is_empty():
		return
	if player == null or not is_instance_valid(player):
		clear()
		return
	# Afflictions added while stepping (spreads, chained seeds) start next tick.
	var n := _list.size()
	for i in n:
		var a := _list[i]
		if not a.done:
			_step(a, delta)
	_compact()


func _step(a: Affliction, delta: float) -> void:
	var e := a.enemy()
	if not WarlockSpell.is_live(e):
		if e != null and e.is_inside_tree():
			a.last_pos = e.global_position
		_host_died(a)
		return
	a.last_pos = e.global_position
	if a.marker != null and is_instance_valid(a.marker) and a.duration > 0.0:
		a.marker.ripeness = 1.0 - clampf(a.left / a.duration, 0.0, 1.0)
	a.owed += a.rate * clampf(a.left, 0.0, delta)
	a.left -= delta
	a.tick_left -= delta
	if a.tick_left > EPSILON and a.left > EPSILON:
		return
	a.tick_left += TICK
	var amount := a.owed
	a.owed = 0.0
	if amount > 0.0 and player.procs != null:
		var hp_before := maxf(0.0, e.hp)
		var dealt := player.procs.deal_raw(e, amount, a.school, true, &"dot")
		a.dealt += dealt
		if a.heal_ratio > 0.0 and dealt > 0.0:
			player.heal(minf(dealt, hp_before) * a.heal_ratio)
	if not WarlockSpell.is_live(e):
		if is_instance_valid(e) and e.is_inside_tree():
			a.last_pos = e.global_position
		_host_died(a)
		return
	if a.left <= EPSILON:
		if a.kind == SEED:
			_burst(a, e.global_position)
		_end(a)


## The enemy of [param a] died (or vanished): Corruption spreads, a seed bursts.
func _host_died(a: Affliction) -> void:
	match a.kind:
		CORRUPTION:
			_spread(a)
		SEED:
			_burst(a, a.last_pos)
	_end(a)


func _spread(a: Affliction) -> void:
	if a.spread_targets <= 0 or a.left <= MIN_SPREAD_LEFT or not is_inside_tree():
		return
	var targets := WarlockSpell.nearest_enemies(get_tree(), a.last_pos, a.spread_radius, a.spread_targets,
			lacks(CORRUPTION))
	var from := a.last_pos + Vector3.UP * Enemy.BODY_CENTER_HEIGHT
	for t in targets:
		var b := corrupt(t, a.rate, a.left, a.spread_targets, a.spread_radius, a.heal_ratio)
		if b == null:
			continue
		b.duration = a.duration
		spreads += 1
		ProcVfx.beam(from, WarlockSpell.chest(t), WarlockSpell.SHADOW_COLOR)
		corruption_spread.emit(a.last_pos, t)


func _burst(a: Affliction, center: Vector3) -> void:
	if not is_inside_tree():
		return
	center = Vector3(center.x, 0.0, center.z)
	bursts += 1
	WarlockSeedBurstVfx.spawn(center, a.burst_radius)
	var victims := WarlockSpell.enemies_in_circle(get_tree(), center, a.burst_radius)
	for v in victims:
		if WarlockSpell.is_live(v) and player.procs != null:
			player.procs.deal_raw(v, a.burst_damage, a.school, true, &"ability")
	seed_burst.emit(center, victims.size())
	if a.pool_duration > 0.0:
		var pool := AbilityArea.spawn(player, center, a.pool_radius, a.pool_duration, POOL_COLOR)
		if pool.is_inside_tree():
			pool.school = a.school
			pool.tick_interval = TICK
			pool.damage_per_tick = a.pool_tick_damage
			pool.slow_pct = a.pool_slow
			pool.add_child(WarlockBlightVfx.create(pool.radius, pool.duration))
		else:
			pool.free()
	if a.chain_left > 0:
		# Chain Reaction: a fresh seed in the nearest surviving victim without one.
		var next := WarlockSpell.nearest_enemies(get_tree(), center, a.burst_radius + 1.0, 1, lacks(SEED))
		if not next.is_empty() and _list.size() < MAX_AFFLICTIONS:
			var b := a.copy_for(next[0])
			b.chain_left = a.chain_left - 1
			b.last_pos = next[0].global_position
			_list.append(b)
			_index(SEED)[b.enemy_id] = b
			_ensure_marker(b, next[0])
			ProcVfx.beam(center + Vector3.UP * 0.6, WarlockSpell.chest(next[0]), WarlockSpell.FEL_COLOR)


func _end(a: Affliction) -> void:
	if a.done:
		return
	a.done = true
	var index := _index(a.kind)
	if index.get(a.enemy_id) == a:
		index.erase(a.enemy_id)
	WarlockAfflictionMarker.release(a.marker)
	a.marker = null


func _compact() -> void:
	var kept: Array[Affliction] = []
	for a in _list:
		if not a.done:
			kept.append(a)
	_list = kept


func _ensure_marker(a: Affliction, e: Enemy) -> void:
	if a.marker != null and is_instance_valid(a.marker):
		return
	var look := WarlockAfflictionMarker.FEAR if a.kind == DREAD else a.kind
	a.marker = WarlockAfflictionMarker.attach(e, look)


func _index(kind: StringName) -> Dictionary:
	var d: Variant = _by_kind.get(kind)
	if d == null:
		d = {}
		_by_kind[kind] = d
	return d


func _exit_tree() -> void:
	clear()
