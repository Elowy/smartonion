class_name ClassResource
extends RefCounted
## Runtime state of one class resource (ResourceData) for one player.

signal changed(value: float, max_value: float)

var data: ResourceData
var value := 0.0
## Multiplier on every gain and on regeneration (Resource Regen stat, GDD 2.4.1).
var gain_mult := 1.0
var _since_combat := 999.0
var _hits := 0
var _kills := 0


func _init(p_data: ResourceData = null) -> void:
	data = p_data
	if data != null:
		value = data.start_value


func max_value() -> float:
	return data.max_value if data != null else 0.0


func is_full() -> bool:
	return value >= max_value() - 0.0001


func can_afford(amount: float) -> bool:
	return value + 0.0001 >= amount


## Adds [param amount] (scaled by gain_mult when [param scaled]). Negative values drain.
func add(amount: float, scaled: bool = true) -> void:
	if data == null or amount == 0.0:
		return
	var before := value
	value = clampf(value + (amount * gain_mult if scaled and amount > 0.0 else amount), 0.0, max_value())
	if not is_equal_approx(before, value):
		changed.emit(value, max_value())


func spend(amount: float) -> bool:
	if not can_afford(amount):
		return false
	if amount > 0.0:
		add(-amount, false)
	return true


func set_value(v: float) -> void:
	var before := value
	value = clampf(v, 0.0, max_value())
	if not is_equal_approx(before, value):
		changed.emit(value, max_value())


## Wave start: back to the start value, counters cleared.
func reset() -> void:
	_hits = 0
	_kills = 0
	_since_combat = 999.0
	set_value(data.start_value if data != null else 0.0)


## [param haste_mult]: StatBlock.attack_speed_mult() for regen_uses_haste resources.
func tick(delta: float, haste_mult: float = 1.0) -> void:
	if data == null:
		return
	_since_combat += delta
	if data.regen_per_second > 0.0:
		add(data.regen_per_second * delta * (haste_mult if data.regen_uses_haste else 1.0))
	if data.decay_per_second > 0.0 and _since_combat >= data.decay_delay:
		add(-data.decay_per_second * delta, false)


func on_weapon_hit(is_crit: bool) -> void:
	if data == null:
		return
	_since_combat = 0.0
	if data.gain_on_hit > 0.0:
		add(data.gain_on_hit)
	if is_crit and data.gain_on_crit > 0.0:
		add(data.gain_on_crit)
	if data.gain_per_hits > 0:
		_hits += 1
		if _hits >= data.gain_per_hits:
			_hits = 0
			add(data.gain_per_hits_amount)


func on_damage_taken() -> void:
	if data == null:
		return
	_since_combat = 0.0
	if data.gain_on_damage_taken > 0.0:
		add(data.gain_on_damage_taken)


func on_kill() -> void:
	if data == null or data.gain_per_kills <= 0:
		return
	_kills += 1
	if _kills >= data.gain_per_kills:
		_kills = 0
		add(data.gain_per_kills_amount)
