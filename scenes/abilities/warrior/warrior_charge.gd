class_name WarriorCharge
extends AbilityEffect
## Charge (GDD 3.1): the hero dashes in its movement direction (up to ~7 m), stuns the
## enemies it runs into, stuns everything around the landing spot and is invulnerable while it
## runs. The dash stops at walls, the arena bounds and the screen edge.
##
## Params (AbilityData.params, items change them through ability_mod):
##   distance       maximum dash length in metres
##   speed          dash speed in m/s
##   stun           seconds of stun for enemies hit on the way and around the landing spot
##   stun_radius    landing stun radius in metres (Area Size scales it)
##   buff_damage    % outgoing damage for buff_duration seconds after the dash (0 = none;
##                  Warbringer's Greaves)
##   buff_duration  seconds the buff lasts

## Key of the temporary damage multiplier in Player.damage_mults.
const BUFF_KEY := &"charge"
const DEFAULT_DISTANCE := 7.0
const DEFAULT_SPEED := 36.0
const DEFAULT_STUN := 1.0
const DEFAULT_STUN_RADIUS := 2.0
## Dashes shorter than this (a wall right in front) are refused (and refunded).
const MIN_DISTANCE := 0.8
## Enemies closer than this to the hero's centre line (m, plus their radius) get run over.
const PATH_RADIUS := 0.9
## Invulnerability that outlasts the dash (s).
const INVULNERABLE_PAD := 0.12
## Bots only charge when this much free road lies ahead (m) ...
const AUTO_MIN_FREE := 3.0
## ... to reach an enemy that is at least this far away (m) ...
const AUTO_MIN_GAP := 3.5
## ... or when this many enemies crowd the hero within AUTO_SURROUND_RADIUS ...
const AUTO_SURROUNDED := 3
const AUTO_SURROUND_RADIUS := 3.0
## ... or to flee below this HP ratio when at least AUTO_FLEE_ENEMIES enemies are close.
const AUTO_FLEE_HP := 0.4
const AUTO_FLEE_ENEMIES := 2
## How well the move direction must point at / away from the enemy (cosine).
const AUTO_ALIGNMENT := 0.7
const SPARK_COLOR := Color(1.0, 0.8, 0.45)

var _player: Player
var _dashing := false
var _dir := Vector3.FORWARD
var _left := 0.0
var _speed := DEFAULT_SPEED
var _stun := DEFAULT_STUN
var _stun_radius := DEFAULT_STUN_RADIUS
var _buff_damage := 0.0
var _buff_duration := 0.0
var _buff_left := 0.0
var _start := Vector3.ZERO
var _hit: Dictionary[int, Enemy] = {}


func is_dashing() -> bool:
	return _dashing


func can_cast(_ctx: AbilityContext) -> bool:
	return not _dashing


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree():
		return false
	var dir := Vector3(ctx.direction.x, 0.0, ctx.direction.z)
	if dir.length_squared() < 0.0001:
		return false
	dir = dir.normalized()
	var wanted := ctx.num("distance", DEFAULT_DISTANCE)
	if WarriorKit.free_distance(player, dir, wanted) < AUTO_MIN_FREE:
		return false
	var here := player.global_position
	var close := WarriorKit.enemies_around(player.get_tree(), here, AUTO_SURROUND_RADIUS)
	var hp_ratio := player.hp / player.max_hp() if player.max_hp() > 0.0 else 1.0
	# Escape: low HP, enemies close and the move direction leads away from them.
	if hp_ratio < AUTO_FLEE_HP and close.size() >= AUTO_FLEE_ENEMIES:
		var centre := Vector3.ZERO
		for e in close:
			centre += e.global_position
		var away := here - centre / float(close.size())
		away.y = 0.0
		return away.length_squared() > 0.0001 and dir.dot(away.normalized()) > 0.3
	# Close in: a gap to the nearest enemy, not surrounded, running at it.
	if hp_ratio < AUTO_FLEE_HP or close.size() >= AUTO_SURROUNDED or ctx.target == null:
		return false
	var to := ctx.target.global_position - here
	to.y = 0.0
	return to.length() >= AUTO_MIN_GAP and dir.dot(to.normalized()) >= AUTO_ALIGNMENT


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or _dashing:
		return false
	var dir := Vector3(ctx.direction.x, 0.0, ctx.direction.z)
	if dir.length_squared() < 0.0001:
		dir = Vector3(player.facing.x, 0.0, player.facing.z)
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var distance := WarriorKit.free_distance(player, dir, ctx.num("distance", DEFAULT_DISTANCE))
	if distance < MIN_DISTANCE:
		return false
	_player = player
	_dir = dir
	_left = distance
	_start = player.global_position
	_speed = maxf(1.0, ctx.num("speed", DEFAULT_SPEED))
	_stun = ctx.num("stun", DEFAULT_STUN)
	_stun_radius = ctx.num("stun_radius", DEFAULT_STUN_RADIUS) * CombatMath.area_mult(player.stats)
	_buff_damage = ctx.num("buff_damage")
	_buff_duration = ctx.num("buff_duration")
	_hit.clear()
	_dashing = true
	if not player.downed_changed.is_connected(_on_downed_changed):
		player.downed_changed.connect(_on_downed_changed)
	player.facing = dir
	player.velocity = Vector3.ZERO
	player.invulnerable_left = maxf(player.invulnerable_left, distance / _speed + INVULNERABLE_PAD)
	Vfx.hit_spark(_start + Vector3.UP * 0.4, SPARK_COLOR)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _buff_left > 0.0:
		_buff_left -= delta
		if _buff_left <= 0.0:
			_clear_buff()
	if not _dashing:
		return
	var player := _player
	if player == null or not is_instance_valid(player):
		_dashing = false
		return
	var step := minf(_speed * delta, _left)
	var from := player.global_position
	var motion := _dir * step
	if player.is_inside_tree():
		player.move_and_collide(motion)
	else:
		player.position += motion
	var to := WarriorKit.keep_in_play_area(player, from, player.global_position)
	if to != player.global_position:
		player.global_position = to
	player.velocity = Vector3.ZERO
	player.invulnerable_left = maxf(player.invulnerable_left, INVULNERABLE_PAD)
	_left -= step
	_run_over(player)
	var moved := Vector2(to.x - from.x, to.z - from.z).length()
	if _left <= 0.001 or moved < step - 0.01:
		_arrive(player)


## Stuns the enemies the hero touches on its way (once each).
func _run_over(player: Player) -> void:
	for e in WarriorKit.enemies_within(player, Player.RADIUS + PATH_RADIUS):
		var id := e.get_instance_id()
		if _hit.has(id):
			continue
		_hit[id] = e
		e.apply_stun(_stun)


## The dash ends (full length, wall or bounds): landing stun, effects, the Greaves buff.
func _arrive(player: Player) -> void:
	_dashing = false
	player.velocity = Vector3.ZERO
	player.invulnerable_left = maxf(player.invulnerable_left, INVULNERABLE_PAD)
	var victims: Dictionary[int, Enemy] = _hit.duplicate()
	for e in WarriorKit.enemies_within(player, _stun_radius):
		victims[e.get_instance_id()] = e
	for id in victims:
		var e := victims[id]
		if is_instance_valid(e) and not e.is_dead():
			e.apply_stun(_stun)
	_hit.clear()
	WarriorChargeVfx.spawn(_start, player.global_position, _stun_radius)
	if _buff_damage > 0.0 and _buff_duration > 0.0:
		player.damage_mults[BUFF_KEY] = 1.0 + _buff_damage / 100.0
		_buff_left = _buff_duration


func _clear_buff() -> void:
	_buff_left = 0.0
	if _player != null and is_instance_valid(_player):
		_player.damage_mults.erase(BUFF_KEY)


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		_dashing = false
		_hit.clear()
		_clear_buff()
