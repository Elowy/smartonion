class_name WarlockVoidwalker
extends Node3D
## The Warlock's second pet (Summon Voidwalker, GDD 6.4). Summoned by
## [WarlockSummonVoidwalker] under the arena's entity root (or next to the Warlock), it guards
## its master: with an enemy within [constant LEASH] m of the Warlock it floats
## [constant GUARD_DISTANCE] m towards the nearest one (between the threat and the Warlock),
## otherwise it follows behind the Warlock's right shoulder.
## - Threat aura: every [code]taunt_interval[/code] s, enemies within [code]taunt_radius[/code]
##   m are taunted onto it ([method Enemy.apply_taunt], [code]taunt_duration[/code] s).
## - Torment (the ability's cast, [method torment]): every enemy within
##   [code]torment_radius[/code] m is taunted for [code]torment_duration[/code] s (Consuming
##   Shadows: also Shadow damage + a slow).
## - Fists: every [code]attack_interval[/code] s (Haste shortens it) it slams the nearest enemy
##   within [code]attack_range[/code] m for Shadow PET damage (&"pet": Demonic Pact).
## - Shared Pain ([code]damage_reduction[/code] %): the Warlock takes that much less damage
##   while it is out (Player.damage_taken_mults[&"voidwalker"], removed when it leaves).
## Enemies never attack it (contact damage only hurts players): it cannot die. It leaves when
## the Warlock goes down, at wave start / end, when the ability is forgotten and when the
## Warlock is freed.
##
## [member params] is the ability's read-only params dictionary (refreshed by the effect).

const SCHOOL := &"shadow"
const DAMAGE_REDUCTION_KEY := &"voidwalker"
## Preferred spot without threats: behind the Warlock's right shoulder.
const FOLLOW_DISTANCE := 2.2
const ORBIT_BACK := 0.45
const ORBIT_SIDE := -0.9
## With a threat: this far from the Warlock towards it (never closer than the threat).
const GUARD_DISTANCE := 3.5
const GUARD_MIN := 2.0
## Gap kept to the threat it guards against (from the threat's edge).
const GUARD_GAP := 0.55
## Threats closer than this to the Warlock make it step in.
const LEASH := 7.0
const TELEPORT_DISTANCE := 12.0
const FOLLOW_GAIN := 4.0
const MAX_SPEED := 6.5
const SCAN_INTERVAL := 0.25
const FIRST_ATTACK_DELAY := 0.6
const FIRST_TAUNT_DELAY := 0.3
const SUMMON_COLOR := Color(0.45, 0.5, 1.0)

var owner_player: Player
var model: WarlockVoidwalkerModel
var params: Dictionary = {}
## Stats (tests): enemies taunted by the aura / Torment, fist slams landed.
var taunts_applied := 0
var attacks := 0

var _attack_left := FIRST_ATTACK_DELAY
var _taunt_left := FIRST_TAUNT_DELAY
var _scan_left := 0.0
var _guard_dir := Vector3.ZERO
var _speed_ratio := 0.0
var _look_dir := Vector3.FORWARD
var _ward_applied := 1.0
var _leaving := false


## Creates the Voidwalker for [param p_owner] next to it (under the arena's entities, else the
## Warlock's parent). Not in the tree when there is no such parent.
static func spawn(p_owner: Player, p_params: Dictionary) -> WarlockVoidwalker:
	var v := WarlockVoidwalker.new()
	v.name = "Voidwalker"
	v.owner_player = p_owner
	v.params = p_params
	v.model = WarlockVoidwalkerModel.new()
	v.add_child(v.model)
	var parent := WeaponRunner.effects_parent(p_owner)
	if parent != null:
		parent.add_child(v)
		v.snap_to_owner()
		v._puff()
	return v


func num(key: String, default: float) -> float:
	var v: Variant = params.get(key, default)
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else default


## Fist damage for the Warlock's [param stats] (before target bonuses, Demonic Pact and the
## Warlock's outgoing multipliers, which ProcSystem.deal_raw applies).
static func attack_damage(stats: StatBlock, p_params: Dictionary) -> float:
	return WarlockSpell.damage(stats, p_params, SCHOOL, "", float(p_params.get("attack_interval", 1.5)))


static func attack_interval(stats: StatBlock, p_params: Dictionary) -> float:
	return maxf(0.3, float(p_params.get("attack_interval", 1.5)) / maxf(0.2, stats.attack_speed_mult()))


func is_leaving() -> bool:
	return _leaving


## Leaves (frees itself) – with a puff of smoke unless [param quiet] (wave end: nothing may
## linger over the market).
func dismiss(quiet: bool = false) -> void:
	if _leaving:
		return
	_leaving = true
	_remove_ward()
	if is_inside_tree() and not quiet:
		Vfx.death_puff(global_position + Vector3.UP * 0.8, SUMMON_COLOR, 1.1)
	queue_free()


## Puts it at its follow spot next to the Warlock.
func snap_to_owner() -> void:
	if not _owner_valid() or not owner_player.is_inside_tree() or not is_inside_tree():
		return
	global_position = _flat(owner_player.global_position) + _follow_dir() * FOLLOW_DISTANCE


## Torment: taunts every enemy within the Torment radius for its duration (Consuming
## Shadows: plus Shadow damage and a slow). Returns the number of enemies taunted.
func torment() -> int:
	if _leaving or not is_inside_tree() or not _owner_valid():
		return 0
	var stats := owner_player.stats
	var radius := WarlockSpell.area(stats, num("torment_radius", 5.0))
	var duration := num("torment_duration", 3.0)
	var hit_mult := num("torment_damage_mult", 0.0)
	var dmg := attack_damage(stats, params) * hit_mult
	var slow := num("torment_slow", 0.0)
	var n := 0
	for e in WarlockSpell.enemies_in_circle(get_tree(), global_position, radius):
		e.apply_taunt(self, duration)
		n += 1
		if slow > 0.0:
			e.apply_slow(slow, duration)
		if dmg > 0.0 and owner_player.procs != null:
			owner_player.procs.deal_raw(e, dmg, SCHOOL, true, &"pet")
	taunts_applied += n
	WarlockVfx.torment_wave(global_position, radius)
	if model != null:
		model.play_roar()
	return n


## Enemies within [param radius] m of it not taunted onto it right now.
func untaunted_near(radius: float) -> int:
	if not is_inside_tree():
		return 0
	var n := 0
	for e in WarlockSpell.enemies_in_circle(get_tree(), global_position, radius):
		if not (e.is_taunted() and e.taunt_target == self):
			n += 1
	return n


func _physics_process(delta: float) -> void:
	if not _owner_valid():
		_leaving = true
		queue_free()
		return
	if _leaving or not owner_player.is_inside_tree() or not is_inside_tree():
		return
	if owner_player.downed:
		dismiss()
		return
	_apply_ward()
	_move(delta)
	_taunt_left -= delta
	if _taunt_left <= 0.0:
		_taunt_left = maxf(0.1, num("taunt_interval", 1.0))
		_threat_aura()
	_attack_left -= delta
	if _attack_left <= 0.0:
		try_attack()
	if model != null:
		model.set_facing(_look_dir)
		model.set_moving(_speed_ratio)


## Slams the nearest enemy within reach now (resets the timer). False: nothing in reach.
func try_attack() -> bool:
	if _leaving or not is_inside_tree() or not _owner_valid():
		return false
	var reach := num("attack_range", 1.6)
	var target := EnemyGrid.nearest(get_tree(), global_position, reach + 0.5)
	if target == null or WeaponRunner.flat(target.global_position - global_position).length() > reach + target.radius:
		_attack_left = 0.1
		return false
	_attack_left = attack_interval(owner_player.stats, params)
	_look_dir = _flat(target.global_position - global_position).normalized()
	if owner_player.procs != null:
		owner_player.procs.deal_raw(target, attack_damage(owner_player.stats, params), SCHOOL, true, &"pet")
	attacks += 1
	Vfx.hit_spark(WarlockSpell.chest(target), SUMMON_COLOR)
	if model != null:
		model.play_attack()
	return true


func _threat_aura() -> void:
	var radius := WarlockSpell.area(owner_player.stats, num("taunt_radius", 3.0))
	var duration := num("taunt_duration", 1.5)
	for e in WarlockSpell.enemies_in_circle(get_tree(), global_position, radius):
		if not (e.is_taunted() and e.taunt_target == self):
			taunts_applied += 1
		e.apply_taunt(self, duration)


func _move(delta: float) -> void:
	var anchor := _flat(owner_player.global_position)
	var here := _flat(global_position)
	if here.distance_to(anchor) > TELEPORT_DISTANCE:
		snap_to_owner()
		_speed_ratio = 0.0
		return
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = SCAN_INTERVAL
		_scan_threat(anchor)
	var want := anchor + _follow_dir() * FOLLOW_DISTANCE
	if _guard_dir != Vector3.ZERO:
		want = anchor + _guard_dir
	var step := (want - here) * (1.0 - exp(-FOLLOW_GAIN * delta))
	var max_step := MAX_SPEED * delta
	if step.length() > max_step:
		step = step.normalized() * max_step
	global_position = here + step
	_speed_ratio = clampf(step.length() / maxf(0.0001, delta) / 4.0, 0.0, 1.0)
	if _speed_ratio > 0.2:
		_look_dir = step.normalized()


## Picks the guard spot: towards the nearest enemy within LEASH of the Warlock (the offset
## from the Warlock, ZERO = no threat).
func _scan_threat(anchor: Vector3) -> void:
	var threat := EnemyGrid.nearest(get_tree(), anchor, LEASH)
	if threat == null:
		_guard_dir = Vector3.ZERO
		return
	var to := _flat(threat.global_position - anchor)
	var dist := to.length()
	if dist < 0.001:
		_guard_dir = Vector3.ZERO
		return
	# In front of the threat (body to body), between it and the Warlock.
	_guard_dir = to / dist * clampf(dist - threat.radius - GUARD_GAP, GUARD_MIN, GUARD_DISTANCE)
	_look_dir = to / dist


func _apply_ward() -> void:
	var dr := clampf(num("damage_reduction", 0.0), 0.0, 90.0)
	var mult := 1.0 - dr / 100.0
	if dr <= 0.0:
		if _ward_applied < 1.0:
			_remove_ward()
		return
	if not is_equal_approx(mult, _ward_applied) or not owner_player.damage_taken_mults.has(DAMAGE_REDUCTION_KEY):
		owner_player.damage_taken_mults[DAMAGE_REDUCTION_KEY] = mult
		_ward_applied = mult


func _remove_ward() -> void:
	_ward_applied = 1.0
	if _owner_valid():
		owner_player.damage_taken_mults.erase(DAMAGE_REDUCTION_KEY)


## Unit vector (XZ) from the Warlock to the follow spot: behind its right shoulder.
func _follow_dir() -> Vector3:
	var facing := _flat(owner_player.facing) if _owner_valid() else Vector3.FORWARD
	if facing.length_squared() < 0.0001:
		facing = Vector3.FORWARD
	facing = facing.normalized()
	var left := Vector3(facing.z, 0.0, -facing.x)
	return (-facing * ORBIT_BACK + left * ORBIT_SIDE).normalized()


func _owner_valid() -> bool:
	return owner_player != null and is_instance_valid(owner_player) and not owner_player.is_queued_for_deletion()


func _puff() -> void:
	if is_inside_tree():
		Vfx.hit_spark(global_position + Vector3.UP * 0.9, SUMMON_COLOR)


func _exit_tree() -> void:
	_remove_ward()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
