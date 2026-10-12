class_name WarriorSpin
extends RefCounted
## A storm of blades around an anchor – the hero (Whirlwind, Bladestorm) or a thrown axe
## (Bladestorm's "Ravager"): every [member interval] seconds every enemy whose body touches the
## circle of [member radius] takes [member hit_pct] % weapon damage. Riders: a slow and leech
## (the hero heals [member leech] % of the damage dealt) and [member on_first_strike] (called
## with each enemy the first time this storm strikes it – Whirlwind's Meat Cleaver refund).
## Driven by the owning effect's tick() (physics, only while the hero lives); [method stop]
## ends it at once and frees its look.

const MAX_SPARKS := 4
const SPARK_HEIGHT := 0.6
const DEFAULT_SLOW_DURATION := 1.5

var player: Player
## Centre of the storm (the hero or a Ravager axe).
var anchor: Node3D
var radius := 3.0
var interval := 0.25
## % weapon damage per hit (ranks' power already included).
var hit_pct := 0.0
var school: StringName = &"physical"
var slow := 0.0
var slow_duration := DEFAULT_SLOW_DURATION
## % of the damage dealt healed to the hero.
var leech := 0.0
var spark_color := Color(1.0, 0.55, 0.3)
## Called with each Enemy the first time this storm strikes it (after its damage; invalid =
## none – Bladestorm, Ravager). The set of struck enemies resets at [method start] / [method stop].
var on_first_strike := Callable()
## The storm's look (freed by stop()).
var look: Node3D
## Totals of the current / last storm (tests, balancing).
var damage_dealt := 0.0
var hits := 0
var pulses := 0

var _left := 0.0
var _tick_left := 0.0
var _ticks_total := 0
## Instance ids of the enemies this storm struck (only kept while on_first_strike is valid).
var _struck: Dictionary[int, bool] = {}


## Starts a storm of [param duration] seconds around [param p_anchor]; the first hit lands at
## once, the rest every [member interval] (round(duration / interval) hits in total).
func start(p_player: Player, p_anchor: Node3D, duration: float) -> void:
	player = p_player
	anchor = p_anchor
	interval = maxf(0.05, interval)
	_left = maxf(interval, duration)
	_ticks_total = maxi(1, roundi(_left / interval))
	_tick_left = 0.0
	pulses = 0
	damage_dealt = 0.0
	hits = 0
	_struck.clear()
	pulse()


func is_running() -> bool:
	return _left > 0.0


func time_left() -> float:
	return maxf(0.0, _left)


func tick(delta: float) -> void:
	if _left <= 0.0:
		return
	_left = maxf(0.0, _left - delta)
	_tick_left -= delta
	while _tick_left <= 0.0 and pulses < _ticks_total:
		pulse()
	if _left <= 0.0:
		_finish(false)


## Ends the storm now and removes its look.
func stop() -> void:
	_left = 0.0
	_struck.clear()
	_finish(true)


## One hit of the storm on everything in reach.
func pulse() -> void:
	pulses += 1
	_tick_left += interval
	if player == null or not is_instance_valid(player) or player.procs == null:
		return
	if anchor == null or not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return
	var damage := WarriorKit.weapon_damage(player) * hit_pct / 100.0
	if damage <= 0.0:
		return
	var sparks := 0
	var dealt := 0.0
	var count := 0
	var watch := on_first_strike.is_valid()
	for e in WarriorKit.enemies_around(anchor.get_tree(), anchor.global_position, radius):
		if not is_instance_valid(e) or e.is_dead():
			continue
		var spot := e.global_position + Vector3.UP * SPARK_HEIGHT
		var id := e.get_instance_id()
		dealt += player.procs.deal_raw(e, damage, school, true, &"ability")
		count += 1
		if watch and not _struck.has(id):
			_struck[id] = true
			on_first_strike.call(e)
		if slow > 0.0 and is_instance_valid(e):
			e.apply_slow(slow, slow_duration)
		if sparks < MAX_SPARKS:
			sparks += 1
			Vfx.hit_spark(spot, spark_color)
	damage_dealt += dealt
	hits += count
	if leech > 0.0 and dealt > 0.0:
		player.heal(dealt * leech / 100.0)


func _finish(free_look: bool) -> void:
	if free_look and is_instance_valid(look) and not look.is_queued_for_deletion():
		look.queue_free()
	look = null
