class_name StatBlock
extends RefCounted
## Base stats plus a list of named modifier sources -> final stat values.
##
## Sources are things like &"class", &"item:head", &"levelup:3". Re-adding a source
## replaces it, so equipment changes are a single set_source() call.

signal changed

var _base: Dictionary[StringName, float] = {}
var _sources: Dictionary[StringName, Dictionary] = {}
var _cache: Dictionary[StringName, float] = {}
var _dirty := true


func set_base(stat: StringName, value: float) -> void:
	_base[stat] = value
	_mark_dirty()


## Replaces all modifiers coming from [param source]. [param mods] maps stat -> flat value.
func set_source(source: StringName, mods: Dictionary) -> void:
	var clean: Dictionary[StringName, float] = {}
	for key in mods:
		clean[StringName(key)] = float(mods[key])
	_sources[source] = clean
	_mark_dirty()


## Adds [param mods] on top of whatever [param source] already contributes.
func add_to_source(source: StringName, mods: Dictionary) -> void:
	var current: Dictionary = _sources.get(source, {})
	var merged := current.duplicate()
	for key in mods:
		var stat := StringName(key)
		merged[stat] = float(merged.get(stat, 0.0)) + float(mods[key])
	set_source(source, merged)


func remove_source(source: StringName) -> void:
	if _sources.erase(source):
		_mark_dirty()


func has_source(source: StringName) -> bool:
	return _sources.has(source)


func get_source(source: StringName) -> Dictionary:
	return _sources.get(source, {}).duplicate()


## Raw (uncapped) total of a stat.
func get_raw(stat: StringName) -> float:
	if _dirty:
		_rebuild()
	return _cache.get(stat, 0.0)


## Final value with caps applied.
func get_stat(stat: StringName) -> float:
	var value := get_raw(stat)
	match stat:
		Stats.CRIT:
			return clampf(value, 0.0, Stats.CRIT_CAP)
		Stats.DODGE:
			return minf(value, Stats.DODGE_CAP)
		Stats.AVOIDANCE:
			return clampf(value, 0.0, Stats.AVOIDANCE_CAP)
		Stats.LEECH:
			return clampf(value, 0.0, Stats.LEECH_CAP)
		Stats.SPEED:
			return maxf(value, Stats.MIN_SPEED)
		Stats.HASTE:
			return maxf(value, Stats.MIN_HASTE)
	return value


# --- Derived values -------------------------------------------------------

func max_hp() -> float:
	return maxf(1.0, Stats.BASE_MAX_HP + get_raw(Stats.STAMINA))


func move_speed() -> float:
	return Stats.BASE_MOVE_SPEED * (1.0 + get_stat(Stats.SPEED) / 100.0)


func attack_speed_mult() -> float:
	return 1.0 + get_stat(Stats.HASTE) / 100.0


## Cooldown multiplier for abilities: Haste has half effect (GDD 2.2).
func cooldown_mult() -> float:
	return 1.0 / (1.0 + get_stat(Stats.HASTE) / 200.0)


func damage_mult() -> float:
	return maxf(0.0, 1.0 + (get_stat(Stats.VERSATILITY) + get_raw(Stats.DAMAGE_PCT)) / 100.0)


## Loot magnet radius in metres. Pickup Range is a percent stat (GDD 2.4.1): +50 = 1.5x.
func pickup_range() -> float:
	return maxf(0.5, Stats.BASE_PICKUP_RANGE * (1.0 + get_raw(Stats.PICKUP_RANGE) / 100.0))


## HP regenerated per second from Spirit (5 Spirit ~= 1 HP every 3 s).
func hp_regen_per_second() -> float:
	return maxf(0.0, get_raw(Stats.SPIRIT)) / 15.0


func snapshot() -> Dictionary:
	var out := {}
	for stat in Stats.ALL:
		out[stat] = get_stat(stat)
	return out


func _mark_dirty() -> void:
	_dirty = true
	changed.emit()


func _rebuild() -> void:
	_cache.clear()
	for stat in _base:
		_cache[stat] = _base[stat]
	for source in _sources:
		var mods: Dictionary = _sources[source]
		for stat in mods:
			_cache[stat] = _cache.get(stat, 0.0) + mods[stat]
	_dirty = false
