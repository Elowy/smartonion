class_name GeneralBuff
extends Node3D
## A timed buff of a general ability on one hero (Sprint, Berserking, Bandage): a named stat
## source ([member stat_mods] under [member key]), an optional damage-taken multiplier
## (Player.damage_taken_mults[key]) and optional heal ticks, plus its look
## ([GeneralAuraVfx]). It is a child of the buffed Player, so it follows the hero and is freed
## with it.
##
## Everything it added is removed when its time runs out, when the hero goes down
## (downed_changed) or by [method end] / [method clear] – the abilities call [method clear] on
## begin_wave / end_wave (and so on forget, which runs end_wave). Applying the same [member key]
## to a hero again refreshes the running buff (new numbers, new duration) instead of stacking.
## Logic runs in _physics_process (deterministic); the look animates in _process.

var key: StringName
var target: Player
## Stat -> flat value (e.g. {Stats.SPEED: 50.0}), the StatBlock source [member key].
var stat_mods: Dictionary = {}
## Player.damage_taken_mults entry (1 = none, 0.75 = 25% less damage taken).
var taken_mult := 1.0
## HP restored by each heal tick and the ticks still to come.
var heal_per_tick := 0.0
var heal_ticks_left := 0
var tick_interval := 0.5
## Seconds left.
var left := 0.0
## Seconds added by [method extend] so far (Feeding Frenzy cap).
var extended := 0.0
var look: GeneralAuraVfx

var _tick_left := 0.0
var _ended := false


## Buffs [param p_target] for [param duration] seconds under [param p_key] (refreshes a running
## buff with the same key). [param p_stats] go into the stat source, [param p_taken_mult] into
## Player.damage_taken_mults. [param look_style] (GeneralAuraVfx.Style, -1 = none) picks the
## look. Returns null for a downed / missing hero.
static func apply(p_target: Player, p_key: StringName, duration: float, p_stats: Dictionary = {},
		p_taken_mult: float = 1.0, look_style: int = -1, look_color: Color = Color.WHITE) -> GeneralBuff:
	if p_target == null or not is_instance_valid(p_target) or not p_target.is_alive():
		return null
	var buff := find(p_target, p_key)
	if buff == null:
		buff = GeneralBuff.new()
		buff.name = "Buff_%s" % p_key
		buff.key = p_key
		buff.target = p_target
		p_target.add_child(buff)
		p_target.downed_changed.connect(buff._on_downed_changed)
		if look_style >= 0:
			buff.look = GeneralAuraVfx.create(look_style as GeneralAuraVfx.Style, look_color)
			buff.add_child(buff.look)
	elif look_style >= 0 and buff.look != null:
		buff.look.refresh()
	buff.left = maxf(GeneralKit.TIME_EPSILON * 2.0, duration)
	buff.set_stats(p_stats)
	buff.set_taken_mult(p_taken_mult)
	return buff


## The running buff [param p_key] on [param p_target] (null = none).
static func find(p_target: Player, p_key: StringName) -> GeneralBuff:
	if p_target == null or not is_instance_valid(p_target):
		return null
	for child in p_target.get_children():
		var b := child as GeneralBuff
		if b != null and b.key == p_key and not b._ended:
			return b
	return null


## Ends the buff [param p_key] on every hero (wave hooks, forget).
static func clear(tree: SceneTree, p_key: StringName) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group(&"players"):
		var b := find(node as Player, p_key)
		if b != null:
			b.end()


## Ends the buff [param p_key] on [param p_target] (if any).
static func clear_on(p_target: Player, p_key: StringName) -> void:
	var b := find(p_target, p_key)
	if b != null:
		b.end()


func is_active() -> bool:
	return not _ended and left > GeneralKit.TIME_EPSILON


## Replaces the stat source's values.
func set_stats(p_stats: Dictionary) -> void:
	stat_mods = p_stats.duplicate()
	if target == null or not is_instance_valid(target):
		return
	if stat_mods.is_empty():
		target.stats.remove_source(key)
	else:
		target.stats.set_source(key, stat_mods)


func set_taken_mult(mult: float) -> void:
	taken_mult = maxf(0.0, mult)
	if target == null or not is_instance_valid(target):
		return
	if is_equal_approx(taken_mult, 1.0):
		target.damage_taken_mults.erase(key)
	else:
		target.damage_taken_mults[key] = taken_mult


## Heals [param total] HP in [param ticks] equal ticks, every [param interval] seconds (the
## first one an interval after now).
func set_heal(total: float, ticks: int, interval: float) -> void:
	heal_ticks_left = maxi(0, ticks)
	tick_interval = maxf(0.05, interval)
	heal_per_tick = total / float(heal_ticks_left) if heal_ticks_left > 0 else 0.0
	_tick_left = tick_interval


## +[param seconds], at most [param cap] seconds in total over the buff's life (cap < 0 = no
## cap). Returns the seconds actually added.
func extend(seconds: float, cap: float = -1.0) -> float:
	if not is_active() or seconds <= 0.0:
		return 0.0
	var add := seconds if cap < 0.0 else clampf(cap - extended, 0.0, seconds)
	left += add
	extended += add
	return add


## Removes everything the buff added and frees it.
func end() -> void:
	if _ended:
		return
	_ended = true
	left = 0.0
	heal_ticks_left = 0
	if target != null and is_instance_valid(target):
		target.stats.remove_source(key)
		target.damage_taken_mults.erase(key)
		if target.downed_changed.is_connected(_on_downed_changed):
			target.downed_changed.disconnect(_on_downed_changed)
	queue_free()


## One physics step (tests drive it directly).
func step(delta: float) -> void:
	if _ended:
		return
	if target == null or not is_instance_valid(target) or not target.is_alive():
		end()
		return
	left -= delta
	if heal_ticks_left > 0:
		_tick_left -= delta
		while _tick_left <= GeneralKit.TIME_EPSILON and heal_ticks_left > 0:
			heal_ticks_left -= 1
			_tick_left += tick_interval
			target.heal(heal_per_tick)
	if left <= GeneralKit.TIME_EPSILON and heal_ticks_left <= 0:
		end()


func _physics_process(delta: float) -> void:
	step(delta)


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		end()
