class_name ClassResource
extends RefCounted
## Runtime state of one class resource (ResourceData) for one player.
##
## Talent / set "resource" entries (M5, BonusVocabulary) add to the ResourceData numbers through
## [member bonus]: every rule reads the effective number ([method max_value],
## [method start_value], [method regen_per_second], [method decay_per_second],
## [method gain_on_hit], [method gain_on_damage_taken], [method gain_on_crit],
## [method gain_per_hits], [method gain_per_kills]) = the [member data] field + its
## "<field>_add". [member data] may be swapped for a private copy (MageMastery.sync_mana for
## Mana, WarlockMastery.refresh_shard_rule for Soul Shards): the bonus is kept here, so it
## applies on top of whichever copy is in place. Clamps: the maximum and the gains never go
## below 0, regen / decay never below 0, gain_per_hits / gain_per_kills never below 1 (a rule
## the data does not have starts only with a positive add), the start value stays within
## 0..maximum. A pool that starts full in its data (Mana, Energy) starts full with a raised
## maximum too ([method reset], [method top_up_to_start]). max_value_add only applies to BAR
## resources (pips are fixed in M5).

signal changed(value: float, max_value: float)

## Float tolerance of the "starts full" check.
const EPSILON := 0.0001

var data: ResourceData
var value := 0.0
## Multiplier on every gain and on regeneration (Resource Regen stat, GDD 2.4.1).
var gain_mult := 1.0
## M5 talent / set "resource" entries: "<field>_add" per BonusVocabulary.RESOURCE_FIELDS
## ({"start_value_add": 5.0}), summed and rank-resolved by PlayerBonuses (set_bonus). Read
## wherever the field is used (the effective-number getters above).
var bonus: Dictionary = {}
var _since_combat := 999.0
var _hits := 0
var _kills := 0


func _init(p_data: ResourceData = null) -> void:
	data = p_data
	if data != null:
		value = data.start_value


## Replaces [member bonus] with a copy of [param p_bonus] (PlayerBonuses hand-off, M5). The
## current value is clamped to the new maximum ([signal changed] tells the HUD the maximum).
func set_bonus(p_bonus: Dictionary) -> void:
	bonus = p_bonus.duplicate(true)
	if data == null:
		return
	value = clampf(value, 0.0, max_value())
	changed.emit(value, max_value())


## The "<field>_add" of [member bonus] (0 when absent or not a number; String or StringName keys).
func bonus_of(field: String) -> float:
	if bonus.is_empty():
		return 0.0
	var key := field + "_add"
	var v: Variant = bonus.get(key, bonus.get(StringName(key), 0.0))
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0.0


func is_pips() -> bool:
	return data != null and data.display == ResourceData.Display.PIPS


func max_value() -> float:
	if data == null:
		return 0.0
	if is_pips():
		return data.max_value
	return maxf(0.0, data.max_value + bonus_of("max_value"))


## Value at the start of every wave: the data's start value + start_value_add, within
## 0..[method max_value]; a pool that starts full in its data starts at the (raised) maximum.
func start_value() -> float:
	if data == null:
		return 0.0
	var start := data.start_value + bonus_of("start_value")
	if data.start_value >= data.max_value - EPSILON:
		start = max_value() + bonus_of("start_value")
	return clampf(start, 0.0, max_value())


func regen_per_second() -> float:
	return maxf(0.0, data.regen_per_second + bonus_of("regen_per_second")) if data != null else 0.0


func decay_per_second() -> float:
	return maxf(0.0, data.decay_per_second + bonus_of("decay_per_second")) if data != null else 0.0


func gain_on_hit() -> float:
	return maxf(0.0, data.gain_on_hit + bonus_of("gain_on_hit")) if data != null else 0.0


func gain_on_damage_taken() -> float:
	return maxf(0.0, data.gain_on_damage_taken + bonus_of("gain_on_damage_taken")) if data != null else 0.0


func gain_on_crit() -> float:
	return maxf(0.0, data.gain_on_crit + bonus_of("gain_on_crit")) if data != null else 0.0


## Weapon hits per +gain_per_hits_amount (0 = no such rule; never below 1 otherwise).
func gain_per_hits() -> int:
	return _per_count(data.gain_per_hits if data != null else 0, bonus_of("gain_per_hits"))


## Kills per +gain_per_kills_amount (0 = no such rule; never below 1 otherwise).
func gain_per_kills() -> int:
	return _per_count(data.gain_per_kills if data != null else 0, bonus_of("gain_per_kills"))


## A "+1 every N events" rule with a bonus: off (0) when the data has none and the add does
## not create one; else at least 1.
static func _per_count(base: int, add: float) -> int:
	if base <= 0 and add <= 0.0:
		return 0
	return maxi(1, base + roundi(add))


func is_full() -> bool:
	return value >= max_value() - EPSILON


func can_afford(amount: float) -> bool:
	return value + EPSILON >= amount


## Adds [param amount] (scaled by gain_mult when [param scaled]). Negative values drain.
## Pip resources (Combo Points, Holy Power, Soul Shards) move in whole points only: their
## gains ignore gain_mult (Resource Regen speeds up the bar resources).
func add(amount: float, scaled: bool = true) -> void:
	if data == null or amount == 0.0:
		return
	var before := value
	var pips := is_pips()
	value = clampf(value + (amount * gain_mult if scaled and amount > 0.0 and not pips else amount), 0.0, max_value())
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


## Wave start: back to the start value ([method start_value], bonus included), counters cleared.
func reset() -> void:
	_hits = 0
	_kills = 0
	_since_combat = 999.0
	set_value(start_value())


## Wave start, after the Mastery's begin_wave (AbilityRunner): a pool that starts full in its
## data (Mana, Energy) is raised to [method start_value] again – a Mastery that resized it
## (MageMastery.sync_mana fills to the data maximum) does not lose the max_value_add. Never
## lowers the value; other pools are left alone.
func top_up_to_start() -> void:
	if data == null or data.start_value < data.max_value - EPSILON:
		return
	var start := start_value()
	if value < start - EPSILON:
		set_value(start)


## [param haste_mult]: StatBlock.attack_speed_mult() for regen_uses_haste resources.
func tick(delta: float, haste_mult: float = 1.0) -> void:
	if data == null:
		return
	_since_combat += delta
	var regen := regen_per_second()
	if regen > 0.0:
		add(regen * delta * (haste_mult if data.regen_uses_haste else 1.0))
	var decay := decay_per_second()
	if decay > 0.0 and _since_combat >= data.decay_delay:
		add(-decay * delta, false)


func on_weapon_hit(is_crit: bool) -> void:
	if data == null:
		return
	_since_combat = 0.0
	var on_hit := gain_on_hit()
	if on_hit > 0.0:
		add(on_hit)
	if is_crit:
		var on_crit := gain_on_crit()
		if on_crit > 0.0:
			add(on_crit)
	var per_hits := gain_per_hits()
	if per_hits > 0:
		_hits += 1
		if _hits >= per_hits:
			_hits = 0
			add(data.gain_per_hits_amount)


func on_damage_taken() -> void:
	if data == null:
		return
	_since_combat = 0.0
	var gain := gain_on_damage_taken()
	if gain > 0.0:
		add(gain)


func on_kill() -> void:
	var per_kills := gain_per_kills()
	if data == null or per_kills <= 0:
		return
	_kills += 1
	if _kills >= per_kills:
		_kills = 0
		add(data.gain_per_kills_amount)
