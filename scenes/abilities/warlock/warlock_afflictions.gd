class_name WarlockAfflictions
extends Node
## The damage-over-time effects one Warlock keeps on enemies (M4, GDD 6.4): Corruption, Seed
## of Corruption, the Dread of Fear and (M5 talents) Agony. A child node of the Warlock
## ([method of]) – freed with it, ticking every physics frame on its own (also while the
## Warlock is downed: DoTs keep burning like item DoTs and Ignite; ability effects only tick
## while their hero lives).
##
## Ticks are DoT damage – ProcSystem.deal_raw(..., &"dot"), so Demonic Pact boosts them, the
## Warlock gets the kill credit and the damage meter counts them. Every enemy carries at most
## one affliction of each kind from this Warlock; re-applying one refreshes it.
## Agony (Curse of Agony, [method agonize]): every weapon hit of the Warlock curses its target
## with a share of the hit's base amount as Shadow damage over a few seconds; a new hit rolls
## the remaining damage into the refreshed curse (nothing is lost). Its ticks are damage
## derived from a hit: deal_raw(..., target_bonus = false, &"dot") (talent_vocabulary §3.6).
## When its host dies, Writhe in Agony splits the remaining curse between the nearest enemies
## without one ([member Affliction.spread_targets]) – the total never grows.
## Curse of Exhaustion ([method slow_pct], WarlockMastery's "warlock_afflictions" params):
## every affliction slows its enemy when it starts and after each tick.
## [signal afflicted_died] tells talents (Unstable Affliction) that an enemy died while it
## carried at least one of this Warlock's afflictions (any killer).
## Corruption: when its enemy dies it jumps, with the time it had left, to the nearest
## uncorrupted enemies within its spread radius (spread_targets of them).
## Seed: when its host dies – or the seed ripens after its duration – it bursts: Shadow damage
## (&"ability") to every enemy in its radius; optionally a Blighted Ground pool and a new seed
## in a surviving victim (Chain Reaction).
## A host that vanishes without dying (the wave-end despawn: no [signal Enemy.died]) only
## takes its afflictions along – no burst, no spread.
## Order: the afflictions run in the order they were applied (deterministic). Markers
## ([WarlockAfflictionMarker]) show them on the enemies.

## A seed burst at [param center] hit [param victims] enemies.
signal seed_burst(center: Vector3, victims: int)
## A Corruption jumped from a corpse at [param from] to [param to].
signal corruption_spread(from: Vector3, to: Enemy)
## An Agony split from a corpse at [param from] onto [param to] (Writhe in Agony).
signal agony_spread(from: Vector3, to: Enemy)
## An enemy died (its [signal Enemy.died] – any killer) while it carried at least one
## affliction of this Warlock; [param at] is where (y = 0). Once per death. A despawned enemy
## (wave end, no died signal) emits nothing.
signal afflicted_died(at: Vector3)

const NODE_NAME := "WarlockAfflictions"
const CORRUPTION := &"corruption"
const SEED := &"seed"
const DREAD := &"dread"
## Curse of Agony (M5 talent): a share of every weapon hit over a few seconds.
const AGONY := &"agony"
## Every kind, in the order [method afflicted] checks them.
const KINDS: Array[StringName] = [CORRUPTION, SEED, DREAD, AGONY]
## Seconds between damage ticks.
const TICK := 0.5
const EPSILON := 0.0001
## A Corruption / Agony with less time left than this does not spread.
const MIN_SPREAD_LEFT := 0.5
## Safety cap of afflictions per Warlock (new ones are refused beyond it). 120: Agony lands
## on every enemy the Warlock's weapon hits.
const MAX_AFFLICTIONS := 120
## Curse of Exhaustion: the slow lasts this much longer than a tick, so it never lapses
## between two ticks.
const SLOW_LINGER := 0.25
const POOL_COLOR := Color(0.35, 0.8, 0.2, 0.32)
## Writhe in Agony's beam (the dark crimson of the Agony marker).
const AGONY_BEAM_COLOR := Color(0.85, 0.15, 0.3)


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
	## The WarlockAfflictionMarker on the enemy (may be freed with the enemy).
	var marker: Variant = null
	var done := false
	## The enemy died (its died signal) – a freed corpse still bursts / spreads.
	var killed := false
	## Damage dealt so far (tests, stats).
	var dealt := 0.0
	## ProcSystem.deal_raw's target_bonus of the ticks: true for spells built from the
	## Warlock's stats, false for Agony (derived from a weapon hit – vocabulary §3.6).
	var target_bonus := true
	## Corruption / Agony: enemies it jumps to when its enemy dies, within spread_radius m
	## (Agony splits its remaining damage between them); share of the damage that heals the
	## Warlock (Siphon Life).
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
		a.target_bonus = target_bonus
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


## Curse of Agony: [param total] Shadow damage (a share of a weapon hit's base amount) over
## [param duration] seconds on [param e]. A running Agony takes the new total on top of the
## damage it still owes and restarts its [param duration] (rate = (rate x left + total) /
## duration – a refresh never loses damage). [param spread_targets] / [param spread_radius]
## (m, Area Size included): Writhe in Agony. Ticks with target_bonus = false. Null when the
## enemy is not alive, nothing is owed or the cap is reached.
func agonize(e: Enemy, total: float, duration: float, spread_targets: int = 0,
		spread_radius: float = 0.0) -> Affliction:
	if total <= 0.0 or duration <= 0.0:
		return null
	var rate := total / duration
	var running := get_affliction(AGONY, e)
	if running != null and not running.done:
		rate = (running.rate * maxf(0.0, running.left) + total) / duration
	var a := _start(AGONY, e, rate, duration)
	if a != null:
		a.target_bonus = false
		a.spread_targets = maxi(0, spread_targets)
		a.spread_radius = maxf(0.0, spread_radius)
	return a


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
		_watch(e)
	a.rate = maxf(0.0, rate)
	a.duration = duration
	a.left = duration
	a.last_pos = e.global_position
	_ensure_marker(a, e)
	_slow(e)
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


## True when [param e] carries any affliction of this Warlock (Corruption, Seed, Dread,
## Agony) – one dictionary lookup per kind, no allocation (Dark Harvest).
func afflicted(e: Node3D) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	var id := e.get_instance_id()
	for kind in KINDS:
		var index: Variant = _by_kind.get(kind)
		if index != null and (index as Dictionary).has(id):
			return true
	return false


## Curse of Exhaustion: % slow every affliction of this Warlock puts on its enemy (the
## "slow" of WarlockMastery.affliction_params – pseudo id "warlock_afflictions"; 0 = none).
func slow_pct() -> float:
	if player == null or not is_instance_valid(player) or player.abilities == null:
		return 0.0
	var m := player.abilities.mastery as WarlockMastery
	return m.affliction_slow() if m != null else 0.0


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
		_host_gone(a, e)
		return
	a.last_pos = e.global_position
	var look := _marker_of(a)
	if look != null and a.duration > 0.0:
		look.ripeness = 1.0 - clampf(a.left / a.duration, 0.0, 1.0)
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
		var dealt := player.procs.deal_raw(e, amount, a.school, a.target_bonus, &"dot")
		a.dealt += dealt
		if a.heal_ratio > 0.0 and dealt > 0.0:
			player.heal(minf(dealt, hp_before) * a.heal_ratio)
	if not WarlockSpell.is_live(e):
		if is_instance_valid(e) and e.is_inside_tree():
			a.last_pos = e.global_position
		_host_gone(a, e if is_instance_valid(e) else null)
		return
	_slow(e)
	if a.left <= EPSILON:
		if a.kind == SEED:
			_burst(a, e.global_position)
		_end(a)


## The enemy of [param a] is gone: when it died (its died signal, or 0 HP while it is still
## there) it counts as a death; one that vanished alive (despawned) only ends [param a].
func _host_gone(a: Affliction, e: Enemy) -> void:
	if a.killed or (e != null and e.hp <= 0.0):
		_host_died(a)
	else:
		_end(a)


## The enemy of [param a] died: Corruption spreads, Agony splits (Writhe in Agony), a seed
## bursts.
func _host_died(a: Affliction) -> void:
	match a.kind:
		CORRUPTION:
			_spread(a)
		AGONY:
			_split_agony(a)
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


## Writhe in Agony: the curse of a dead host is split between the (up to) spread_targets
## nearest enemies without Agony within spread_radius m of the corpse – each gets rate / n
## for the time the host had left, so the remaining damage is shared, never copied (judge
## B9: a copy multiplied an elite's rolled-up Agony with every death).
func _split_agony(a: Affliction) -> void:
	if a.spread_targets <= 0 or a.left <= MIN_SPREAD_LEFT or a.rate <= 0.0 or not is_inside_tree():
		return
	var targets := WarlockSpell.nearest_enemies(get_tree(), a.last_pos, a.spread_radius, a.spread_targets,
			lacks(AGONY))
	if targets.is_empty():
		return
	var share := a.rate / float(targets.size())
	var from := a.last_pos + Vector3.UP * Enemy.BODY_CENTER_HEIGHT
	for t in targets:
		var b := _start(AGONY, t, share, a.left)
		if b == null:
			continue
		b.target_bonus = false
		b.spread_targets = a.spread_targets
		b.spread_radius = a.spread_radius
		spreads += 1
		ProcVfx.beam(from, WarlockSpell.chest(t), AGONY_BEAM_COLOR)
		agony_spread.emit(a.last_pos, t)


func _burst(a: Affliction, center: Vector3) -> void:
	if not is_inside_tree():
		return
	center = Vector3(center.x, 0.0, center.z)
	bursts += 1
	WarlockVfx.seed_burst(center, a.burst_radius)
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
			_watch(next[0])
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


## Listens for [param e]'s death (once per enemy).
func _watch(e: Enemy) -> void:
	if not e.died.is_connected(_on_enemy_died):
		e.died.connect(_on_enemy_died)


## Marks the afflictions on [param e] as killed (their host may be freed before the next tick)
## and, when it carried any, emits [signal afflicted_died].
func _on_enemy_died(e: Enemy, _killer_index: int) -> void:
	var id := e.get_instance_id()
	var any := false
	for index: Dictionary in _by_kind.values():
		var a: Affliction = index.get(id)
		if a != null:
			a.killed = true
			any = true
	if any:
		var pos := e.global_position if e.is_inside_tree() else e.position
		afflicted_died.emit(Vector3(pos.x, 0.0, pos.z))


## Curse of Exhaustion on [param e] (nothing without the talent).
func _slow(e: Enemy) -> void:
	var pct := slow_pct()
	if pct > 0.0:
		e.apply_slow(pct, TICK + SLOW_LINGER)


func _compact() -> void:
	var kept: Array[Affliction] = []
	for a in _list:
		if not a.done:
			kept.append(a)
	_list = kept


func _ensure_marker(a: Affliction, e: Enemy) -> void:
	if _marker_of(a) != null:
		return
	var look := WarlockAfflictionMarker.FEAR if a.kind == DREAD else a.kind
	a.marker = WarlockAfflictionMarker.attach(e, look)


static func _marker_of(a: Affliction) -> WarlockAfflictionMarker:
	if a.marker == null or not is_instance_valid(a.marker):
		return null
	return a.marker as WarlockAfflictionMarker


func _index(kind: StringName) -> Dictionary:
	var d: Variant = _by_kind.get(kind)
	if d == null:
		d = {}
		_by_kind[kind] = d
	return d


func _exit_tree() -> void:
	clear()
