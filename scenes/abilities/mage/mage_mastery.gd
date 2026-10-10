class_name MageMastery
extends MasteryEffect
## Mage Mastery "Ignite" (GDD 3.2) and the Mage's Mana pool.
##
## Ignite: a critical weapon hit sets its target burning for (1% x Mastery) of the crit's
## damage, spread over BURN_DURATION seconds in ticks of fire damage. A new crit on a burning
## enemy adds its share to what is still burning and restarts the clock.
##
## Mana: max 100 + 2 x Intellect (follows gear and level bonuses). ResourceData is shared by
## every Mage, so this class swaps its own resource's data for a private copy on the first
## tick and keeps max / start value in step with Intellect; a rise of the maximum is
## granted as mana right away, a fall clamps the current value.

const MANA := &"mana"
const BASE_MANA := 100.0
const MANA_PER_INTELLECT := 2.0
const BURN_DURATION := 3.0
const BURN_TICK := 0.5
const EPSILON := 0.0001
const FIRE := &"fire"


## One burning enemy.
class Burn extends RefCounted:
	## Damage per second still to come, seconds left, time to the next tick, damage owed.
	var rate := 0.0
	var left := 0.0
	var tick_left := 0.0
	var owed := 0.0


var _burns: Dictionary[int, Burn] = {}
var _mana: ClassResource


## Max Mana at [param intellect].
static func mana_max_for(intellect: float) -> float:
	return BASE_MANA + MANA_PER_INTELLECT * maxf(0.0, intellect)


func on_hit(target: Node3D, damage: float, is_crit: bool) -> void:
	if is_crit:
		ignite(target as Enemy, damage)


## Sets [param enemy] burning for Mastery% of [param crit_damage] over BURN_DURATION.
func ignite(enemy: Enemy, crit_damage: float) -> void:
	var share := mastery() / 100.0
	if share <= 0.0 or crit_damage <= 0.0 or not _is_live(enemy):
		return
	var total := crit_damage * share
	var id := enemy.get_instance_id()
	var burn: Burn = _burns.get(id)
	if burn == null:
		burn = Burn.new()
		burn.tick_left = BURN_TICK
		_burns[id] = burn
		MageVfx.ignite(enemy.global_position + Vector3.UP * Enemy.BODY_CENTER_HEIGHT)
	else:
		total += burn.rate * burn.left
	burn.left = BURN_DURATION
	burn.rate = total / BURN_DURATION


## Enemies currently burning (tests, UI).
func burning_count() -> int:
	return _burns.size()


## Damage per second still to come on [param enemy] (0 = not burning).
func burn_rate(enemy: Node3D) -> float:
	var burn: Burn = _burns.get(enemy.get_instance_id()) if enemy != null else null
	return burn.rate if burn != null else 0.0


func begin_wave() -> void:
	_burns.clear()
	sync_mana(true)


func tick(delta: float) -> void:
	sync_mana()
	if _burns.is_empty():
		return
	for id in _burns.keys():
		var burn: Burn = _burns[id]
		var enemy := instance_from_id(id) as Enemy
		if not _is_live(enemy):
			_burns.erase(id)
			continue
		burn.owed += burn.rate * clampf(burn.left, 0.0, delta)
		burn.left -= delta
		burn.tick_left -= delta
		if burn.tick_left > EPSILON and burn.left > EPSILON:
			continue
		burn.tick_left += BURN_TICK
		var amount := burn.owed
		burn.owed = 0.0
		if amount > 0.0 and player != null and player.procs != null:
			player.procs.deal_raw(enemy, amount, FIRE, false, &"dot")
		if burn.left <= EPSILON or not _is_live(enemy):
			_burns.erase(id)


func teardown() -> void:
	_burns.clear()


func describe() -> String:
	return "Ignite: critical hits set the target burning for %d%% of their damage over %d sec." \
			% [roundi(mastery()), roundi(BURN_DURATION)]


## Keeps this hero's Mana maximum at 100 + 2 x Intellect. [param fill]: also fills the pool
## (wave start, first sync).
func sync_mana(fill: bool = false) -> void:
	if player == null or player.abilities == null:
		return
	var res := player.abilities.get_resource(MANA)
	if res == null:
		return
	var first := res != _mana
	if first:
		_mana = res
		res.data = res.data.duplicate()
	var max_mana := mana_max_for(player.stats.get_raw(Stats.INTELLECT))
	var grown := max_mana - res.data.max_value
	if not first and not fill and absf(grown) < EPSILON:
		return
	res.data.max_value = max_mana
	res.data.start_value = max_mana
	if fill or first:
		res.set_value(max_mana)
	elif grown > 0.0:
		res.set_value(res.value + grown)
	else:
		res.set_value(res.value)


static func _is_live(e: Enemy) -> bool:
	return e != null and is_instance_valid(e) and e.is_inside_tree() and not e.is_dead()
