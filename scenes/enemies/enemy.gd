class_name Enemy
extends CharacterBody3D
## A hostile unit (GDD 8). Group &"enemies". Collision layer 3 ("enemies"), mask 1 (world
## only): enemies do not collide with each other in the physics engine – that made every
## move_and_slide of a big horde expensive. Crowd separation comes from the shared
## [EnemyGrid] instead (built once per physics tick): an enemy slides along the neighbours it
## touches and pushes itself out of overlaps ([method EnemyGrid.crowd_velocity]).
##
## Behaviours (EnemyData.Behavior), always against the nearest living player:
##   CHASE  – walk straight at the target.
##   SWARM  – like CHASE (faster / weaker per data) with a slight weave.
##   LUNGE  – chase; within LUNGE_TRIGGER_RANGE wind up for data.lunge_windup seconds
##            (model.play_windup), then leap at data.lunge_speed for LUNGE_DURATION;
##            data.attack_cooldown between lunges.
##   RANGED – keep data.preferred_distance, strafe a little, and every data.attack_cooldown
##            throw an axe (Projectile, TEAM_ENEMIES) after a short wind-up.
## With no living player the enemy wanders. Touching a living player (distance <=
## radius + Player.RADIUS) deals contact damage, at most once per CONTACT_COOLDOWN.
## Damage taken by the enemy is recorded by the attacker side (WeaponRunner); the enemy only
## handles knockback, hit flash and death (kill credit, death puff, loot, [signal died]).
## Players are looked up through the shared per-tick [LivingPlayers] snapshot.

signal died(enemy: Enemy, killer_index: int)

enum AiState { MOVE, WINDUP, LEAP, THROW_WINDUP }

const COLLISION_LAYER_ENEMIES := 1 << 2
## Enemies collide with the world only (crowd separation: [EnemyGrid]).
const COLLISION_MASK_WORLD := 1
## The old mask (world + other enemies); no longer used by enemies (kept for tools / ablations).
const COLLISION_MASK_WORLD_AND_ENEMIES := 1 | (1 << 2)
## Seconds between two contact hits of the same enemy.
const CONTACT_COOLDOWN := 1.0
## Chasers stop pushing into a player at this fraction of the contact distance.
const CONTACT_HOLD_RATIO := 0.7

## LUNGE: centre distance (m) at which the wind-up starts.
const LUNGE_TRIGGER_RANGE := 3.5
## LUNGE: seconds of the leap itself.
const LUNGE_DURATION := 0.35
## LUNGE: the aim follows the target during the wind-up except for this last fraction.
const LUNGE_AIM_LOCK := 0.4

## RANGED: wind-up before each throw (seconds).
const THROW_WINDUP := 0.35
## RANGED: flight range of the thrown axe (m).
const THROW_RANGE := 14.0
## RANGED: only throw when the target is at most this far away (m).
const THROW_MAX_DISTANCE := 12.5
## RANGED: the preferred distance band is preferred_distance ± this (m).
const RANGED_DISTANCE_SLACK := 1.0
const STRAFE_SPEED_RATIO := 0.45
const STRAFE_SWITCH_MIN := 1.2
const STRAFE_SWITCH_MAX := 2.8
## Height (m) the axe is released at.
const THROW_HEIGHT := 0.8

const SWARM_WEAVE := 0.35
const SWARM_WEAVE_SPEED := 4.0
const WANDER_SPEED_RATIO := 0.35
const WANDER_TIME_MIN := 1.0
const WANDER_TIME_MAX := 2.5
## m/s^2 – how fast the walking velocity turns towards the desired one.
const STEER_ACCELERATION := 20.0
## Every enemy walks up to ± this fraction faster / slower than its data says.
const MOVE_SPEED_JITTER := 0.08

## Knockback impulse k (WeaponData.knockback) -> initial velocity k * this (m/s); it decays
## exponentially at KNOCKBACK_DECAY per second, so the total push is ~k * 0.25 m.
const KNOCKBACK_VELOCITY_PER_UNIT := 3.0
const KNOCKBACK_DECAY := 12.0
const MAX_KNOCKBACK_SPEED := 14.0

## Height (m) of the collision sphere's centre. All enemies stand on one plane, so they meet
## the walls (and each other, in [EnemyGrid]) like circles of [member radius].
const BODY_CENTER_HEIGHT := 0.6
## move_and_slide iterations: 2 lets enemies slide along a wall (they only collide with the
## world, so a second slide is only ever needed in a corner).
const MAX_SLIDES := 2
## Loot lands up to this far (m) from the death position.
const LOOT_SCATTER := 0.4
## State timers end this close to zero (keeps frame counts exact despite float error).
const TIMER_EPSILON := 0.0001

var data: EnemyData
var wave := 1
var hp := 1.0
var max_hp := 1.0
var radius := 0.45
var model: EnemyModel

## Contact damage per hit at this enemy's wave.
var contact_damage := 1.0
## Damage of each thrown projectile (RANGED) at this enemy's wave.
var projectile_damage := 1.0
## Walking speed (m/s) incl. the per-enemy jitter.
var move_speed := 2.4
var ai_state := AiState.MOVE
## Seconds left in the current timed state (WINDUP, LEAP, THROW_WINDUP).
var state_left := 0.0
## Seconds until the next lunge / throw may start.
var attack_cooldown_left := 0.0
## Seconds until the next contact hit may land.
var contact_cooldown_left := 0.0
var stun_left := 0.0
var knockback_velocity := Vector3.ZERO

var _dead := false
var _move_velocity := Vector3.ZERO
var _facing := Vector3.FORWARD
## Locked direction of the current lunge / throw.
var _aim_dir := Vector3.FORWARD
var _target: Player
var _target_pos := Vector3.ZERO
var _target_dist_sq := INF
var _strafe_sign := 1.0
var _strafe_left := 0.0
var _wander_dir := Vector3.ZERO
var _wander_left := 0.0
var _weave_phase := 0.0
var _age := 0.0
var _sent_facing := Vector3.ZERO
var _sent_moving := -1.0
## Serial of the LivingPlayers snapshot this enemy last read.
var _players_serial := -1
## Bookkeeping of the shared EnemyGrid (written by it): build serial * MAX_ENEMIES + index of
## this enemy in that build, and the last build this enemy moved with.
var _grid_tag := -1
var _grid_used := -1

# Frame-cached list of the players in the tree (shared by all enemies and pickups).
static var _player_cache: Array[Player] = []
static var _player_cache_frame := -1
static var _player_cache_count := -1
static var _no_players: Array[Player] = []


static func create(p_data: EnemyData, p_wave: int) -> Enemy:
	var e := Enemy.new()
	e.data = p_data
	e.wave = maxi(1, p_wave)
	e.collision_layer = COLLISION_LAYER_ENEMIES
	e.collision_mask = COLLISION_MASK_WORLD
	e.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	e.max_slides = MAX_SLIDES
	e.add_to_group(&"enemies")
	if p_data == null:
		push_error("Enemy.create: missing EnemyData")
		return e
	e.name = String(p_data.id).to_pascal_case() if p_data.id != &"" else "Enemy"
	e.radius = p_data.radius
	e.max_hp = maxf(1.0, p_data.hp_at_wave(e.wave) * RunState.coop_hp_mult())
	e.hp = e.max_hp
	e.contact_damage = p_data.contact_damage_at_wave(e.wave)
	e.projectile_damage = p_data.projectile_damage_at_wave(e.wave)
	var rng := RunState.rng
	e.move_speed = p_data.move_speed * (1.0 + rng.randf_range(-MOVE_SPEED_JITTER, MOVE_SPEED_JITTER))
	e._weave_phase = rng.randf() * TAU
	e._strafe_sign = 1.0 if rng.randf() < 0.5 else -1.0
	e._strafe_left = rng.randf_range(STRAFE_SWITCH_MIN, STRAFE_SWITCH_MAX)
	if p_data.behavior == EnemyData.Behavior.RANGED:
		# Do not throw the moment it arrives; stagger the throws of a group.
		e.attack_cooldown_left = p_data.attack_cooldown * rng.randf_range(0.5, 1.0)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var sphere := SphereShape3D.new()
	sphere.radius = p_data.radius
	shape.shape = sphere
	shape.position = Vector3(0.0, BODY_CENTER_HEIGHT, 0.0)
	e.add_child(shape)

	e.model = EnemyModel.new()
	e.model.name = "Model"
	e.add_child(e.model)
	e.model.setup(p_data)
	return e


func _enter_tree() -> void:
	EnemyGrid.mark_dirty()


func _exit_tree() -> void:
	# Dead enemies already left the group (the grid skips them until its next build); one
	# that leaves alive (wave end, tests) must not linger in the grid.
	if not _dead:
		EnemyGrid.mark_dirty()


func is_dead() -> bool:
	return _dead or hp <= 0.0


func is_stunned() -> bool:
	return stun_left > 0.0


## [param attacker] is the Player (or null). [param knockback] is a world-space impulse.
func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null,
		knockback: Vector3 = Vector3.ZERO) -> void:
	if is_dead() or amount <= 0.0:
		return
	hp -= amount
	if knockback.x != 0.0 or knockback.z != 0.0:
		var resist := clampf(data.knockback_resist, 0.0, 1.0) if data != null else 0.0
		var push := Vector3(knockback.x, 0.0, knockback.z) * KNOCKBACK_VELOCITY_PER_UNIT * (1.0 - resist)
		knockback_velocity = (knockback_velocity + push).limit_length(MAX_KNOCKBACK_SPEED)
	if model != null:
		model.flash_hit()
	if hp <= 0.0:
		_die(attacker)


func apply_stun(duration: float) -> void:
	if is_dead() or duration <= 0.0:
		return
	var resist := clampf(data.stun_resist, 0.0, 1.0) if data != null else 0.0
	var d := duration * (1.0 - resist)
	if d <= 0.0:
		return
	var was_stunned := stun_left > 0.0
	stun_left = maxf(stun_left, d)
	_move_velocity = Vector3.ZERO
	if ai_state != AiState.MOVE:
		# A stun interrupts a wind-up / lunge; the attack comes back sooner than usual.
		ai_state = AiState.MOVE
		state_left = 0.0
		if data != null:
			attack_cooldown_left = maxf(attack_cooldown_left, data.attack_cooldown * 0.5)
	if not was_stunned and model != null:
		model.set_stunned(true)


## Removes the enemy without loot (wave end).
func despawn() -> void:
	if _dead and is_queued_for_deletion():
		return
	_dead = true
	_leave_world()
	queue_free()


# --- Shared player lookup ------------------------------------------------------

## Every Player in the tree, cached once per physics frame (refreshed earlier when the
## number of players changes or a cached one was freed). Entries may be downed or out of
## the tree – use [method is_living_player]. Do not modify the array.
static func cached_players(tree: SceneTree) -> Array[Player]:
	if tree == null:
		return _no_players
	var frame := Engine.get_physics_frames()
	var count := tree.get_node_count_in_group(&"players")
	if frame != _player_cache_frame or count != _player_cache_count or _player_cache_has_freed():
		_player_cache_frame = frame
		_player_cache_count = count
		_player_cache.clear()
		for node in tree.get_nodes_in_group(&"players"):
			var p := node as Player
			if p != null:
				_player_cache.append(p)
	return _player_cache


## Forces the next [method cached_players] call (and [LivingPlayers] snapshot) to rebuild
## the list (tests).
static func invalidate_player_cache() -> void:
	_player_cache_frame = -1
	_player_cache_count = -1
	LivingPlayers.mark_dirty()


## True for a Player that is valid (not freed), inside the tree and not downed.
## Takes a Variant on purpose: passing a freed instance to a [Player]-typed parameter is a
## script error, and pickups / AI may still hold a reference to a freed player.
static func is_living_player(p: Variant) -> bool:
	if not is_instance_valid(p):
		return false
	var player := p as Player
	return player != null and player.is_inside_tree() and player.is_alive()


static func _player_cache_has_freed() -> bool:
	for p in _player_cache:
		if not is_instance_valid(p):
			return true
	return false


## World positions of every living player.
static func living_player_positions(tree: SceneTree) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in cached_players(tree):
		if is_living_player(p):
			out.append(p.global_position)
	return out


# --- Frame update ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dead or data == null or not is_inside_tree():
		return
	_age += delta
	if contact_cooldown_left > 0.0:
		contact_cooldown_left -= delta
	if attack_cooldown_left > 0.0:
		attack_cooldown_left -= delta
	var stunned := stun_left > 0.0
	if stunned:
		stun_left -= delta
		if stun_left <= 0.0:
			stun_left = 0.0
			if model != null:
				model.set_stunned(false)

	var here := global_position
	_scan_players(here, stunned)
	if _dead or not is_inside_tree():
		return  # a contact hit ended the run and the wave removed us

	if stunned:
		_move_velocity = Vector3.ZERO
	elif ai_state == AiState.LEAP:
		_update_lunge(delta, here)
	elif _target == null:
		if ai_state != AiState.MOVE:
			ai_state = AiState.MOVE
			state_left = 0.0
		_update_wander(delta)
	else:
		match data.behavior:
			EnemyData.Behavior.LUNGE:
				_update_lunge(delta, here)
			EnemyData.Behavior.RANGED:
				_update_ranged(delta, here)
			_:
				_update_chase(delta, here)
	_apply_movement(delta, stunned)
	if model != null:
		# Only forward noticeable changes (the model smooths them anyway).
		if _facing.dot(_sent_facing) < 0.9995:
			_sent_facing = _facing
			model.set_facing(_facing)
		var moving := clampf(_move_velocity.length() / maxf(0.1, move_speed), 0.0, 1.0)
		if absf(moving - _sent_moving) > 0.03:
			_sent_moving = moving
			model.set_moving(moving)


## Finds the nearest living player and deals contact damage to the first one touched.
## Reads the shared [LivingPlayers] snapshot (positions as packed floats); the player that is
## hit is re-checked first, and a hit marks the snapshot dirty (the player may have gone down).
func _scan_players(here: Vector3, stunned: bool) -> void:
	_target = null
	_target_dist_sq = INF
	_players_serial = LivingPlayers.refresh(self, _players_serial)
	var n := LivingPlayers.count
	if n == 0:
		return
	var players := LivingPlayers.players
	var xs := LivingPlayers.pos_x
	var zs := LivingPlayers.pos_z
	var reach := radius + Player.RADIUS
	var reach_sq := reach * reach
	var can_hit := not stunned and contact_cooldown_left <= 0.0
	var best := -1
	for i in n:
		var dx := xs[i] - here.x
		var dz := zs[i] - here.z
		var d_sq := dx * dx + dz * dz
		if can_hit and d_sq <= reach_sq:
			if not is_living_player(players[i]):
				continue  # went down (or away) since the snapshot
			var p := players[i]
			can_hit = false
			contact_cooldown_left = CONTACT_COOLDOWN
			p.take_damage(contact_damage, CombatMath.KIND_MELEE, self)
			LivingPlayers.mark_dirty()
			if _dead or not is_inside_tree():
				return
			if model != null and ai_state == AiState.MOVE:
				model.play_attack()  # (would cut a lunge / throw wind-up tell short)
			if not is_living_player(players[i]):
				continue
		if d_sq < _target_dist_sq:
			_target_dist_sq = d_sq
			best = i
	if best >= 0 and is_instance_valid(players[best]):
		_target = players[best]
		_target_pos = Vector3(xs[best], 0.0, zs[best])


func _update_chase(delta: float, here: Vector3) -> void:
	var dir := _dir_to_target(here)
	var dist := sqrt(_target_dist_sq)
	var speed := move_speed
	if dist <= (radius + Player.RADIUS) * CONTACT_HOLD_RATIO:
		speed = 0.0
	var desired := dir * speed
	if data.behavior == EnemyData.Behavior.SWARM and speed > 0.0:
		var side := Vector3(-dir.z, 0.0, dir.x)
		desired += side * (sin(_age * SWARM_WEAVE_SPEED + _weave_phase) * SWARM_WEAVE * speed)
	_steer(desired, delta)
	_facing = dir


func _update_lunge(delta: float, here: Vector3) -> void:
	match ai_state:
		AiState.WINDUP:
			state_left -= delta
			if _target != null and state_left > data.lunge_windup * LUNGE_AIM_LOCK:
				_aim_dir = _dir_to_target(here)
			_move_velocity = Vector3.ZERO
			_facing = _aim_dir
			if state_left <= TIMER_EPSILON:
				ai_state = AiState.LEAP
				state_left = LUNGE_DURATION
				_move_velocity = _aim_dir * data.lunge_speed
				if model != null:
					model.play_attack()
		AiState.LEAP:
			state_left -= delta
			_move_velocity = _aim_dir * data.lunge_speed
			_facing = _aim_dir
			if state_left <= TIMER_EPSILON:
				ai_state = AiState.MOVE
				state_left = 0.0
				attack_cooldown_left = data.attack_cooldown
				_move_velocity = _aim_dir * move_speed
		_:
			if attack_cooldown_left <= 0.0 and _target_dist_sq <= LUNGE_TRIGGER_RANGE * LUNGE_TRIGGER_RANGE:
				ai_state = AiState.WINDUP
				state_left = data.lunge_windup
				_aim_dir = _dir_to_target(here)
				_facing = _aim_dir
				_move_velocity = Vector3.ZERO
				if model != null:
					model.play_windup()
			else:
				_update_chase(delta, here)


func _update_ranged(delta: float, here: Vector3) -> void:
	var dir := _dir_to_target(here)
	_facing = dir
	if ai_state == AiState.THROW_WINDUP:
		state_left -= delta
		_aim_dir = dir
		_move_velocity = Vector3.ZERO
		if state_left <= TIMER_EPSILON:
			ai_state = AiState.MOVE
			state_left = 0.0
			attack_cooldown_left = data.attack_cooldown
			_throw(here)
		return
	var dist := sqrt(_target_dist_sq)
	if attack_cooldown_left <= 0.0 and dist <= THROW_MAX_DISTANCE:
		ai_state = AiState.THROW_WINDUP
		state_left = THROW_WINDUP
		_aim_dir = dir
		_move_velocity = Vector3.ZERO
		if model != null:
			model.play_windup()
		return
	_strafe_left -= delta
	if _strafe_left <= 0.0:
		var rng := RunState.rng
		_strafe_left = rng.randf_range(STRAFE_SWITCH_MIN, STRAFE_SWITCH_MAX)
		if rng.randf() < 0.6:
			_strafe_sign = -_strafe_sign
	var preferred := data.preferred_distance
	var desired: Vector3
	if dist > preferred + RANGED_DISTANCE_SLACK:
		desired = dir * move_speed
	elif dist < preferred - RANGED_DISTANCE_SLACK:
		desired = -dir * move_speed
	else:
		var side := Vector3(-dir.z, 0.0, dir.x) * _strafe_sign
		var radial := (dist - preferred) / RANGED_DISTANCE_SLACK
		desired = (side * STRAFE_SPEED_RATIO + dir * (radial * 0.5)) * move_speed
	_steer(desired, delta)


func _update_wander(delta: float) -> void:
	_wander_left -= delta
	if _wander_left <= 0.0:
		var rng := RunState.rng
		_wander_left = rng.randf_range(WANDER_TIME_MIN, WANDER_TIME_MAX)
		if rng.randf() < 0.35:
			_wander_dir = Vector3.ZERO
		else:
			_wander_dir = Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU)
	_steer(_wander_dir * move_speed * WANDER_SPEED_RATIO, delta)
	if _wander_dir != Vector3.ZERO:
		_facing = _wander_dir


func _throw(here: Vector3) -> void:
	var parent := _world_parent()
	if parent == null:
		return
	var dir := _aim_dir
	var proj := Projectile.create(Projectile.TEAM_ENEMIES, projectile_damage, false, dir,
			data.projectile_speed, THROW_RANGE, 0, 0.0, self, &"axe", Projectile.default_color(&"axe"))
	parent.add_child(proj)
	# Released a little in front of the body so it does not start inside the thrower.
	proj.global_position = here + Vector3.UP * THROW_HEIGHT + dir * (radius + 0.15)
	if model != null:
		model.play_attack()


func _steer(desired: Vector3, delta: float) -> void:
	_move_velocity = _move_velocity.move_toward(desired, STEER_ACCELERATION * delta)


## Walk + knockback, adjusted by the crowd ([method EnemyGrid.crowd_velocity]: slides along
## touching neighbours, pushes out of overlaps – not while stunned), then one move_and_slide
## against the world.
func _apply_movement(delta: float, stunned: bool) -> void:
	if knockback_velocity != Vector3.ZERO:
		knockback_velocity *= exp(-KNOCKBACK_DECAY * delta)
		if knockback_velocity.length_squared() < 0.0025:
			knockback_velocity = Vector3.ZERO
	velocity = EnemyGrid.crowd_velocity(self, _move_velocity + knockback_velocity, delta, not stunned)
	if velocity.length_squared() < 0.000001:
		velocity = Vector3.ZERO
		return
	move_and_slide()
	var pos := global_position
	# Stay on the ground plane and inside the arena (walls normally take care of that).
	var half_x := Arena.SIZE.x * 0.5 - radius
	var half_z := Arena.SIZE.y * 0.5 - radius
	if pos.y != 0.0 or absf(pos.x) > half_x or absf(pos.z) > half_z:
		var fixed := Vector3(pos.x, 0.0, pos.z)
		if Arena.current != null:
			fixed = Arena.current.clamp_point(fixed, radius)
		global_position = fixed


## Normalised XZ direction to the current target (or the current facing).
func _dir_to_target(here: Vector3) -> Vector3:
	var dx := _target_pos.x - here.x
	var dz := _target_pos.z - here.z
	var len_sq := dx * dx + dz * dz
	if len_sq < 0.000001:
		return _facing
	var inv := 1.0 / sqrt(len_sq)
	return Vector3(dx * inv, 0.0, dz * inv)


# --- Death -----------------------------------------------------------------------

func _die(attacker: Node3D) -> void:
	if _dead:
		return
	_dead = true
	var killer_index := -1
	if attacker != null and is_instance_valid(attacker):
		var player := attacker as Player
		if player != null and player.slot != null:
			killer_index = player.slot.index
	RunState.record_kill(killer_index)
	var pos := global_position if is_inside_tree() else position
	if data != null:
		Vfx.death_puff(pos + Vector3.UP * 0.5 * data.model_scale, data.color, data.model_scale)
		_drop_loot(pos)
	_leave_world()
	died.emit(self, killer_index)
	queue_free()


func _drop_loot(pos: Vector3) -> void:
	if data.gold <= 0 and data.xp <= 0:
		return
	var parent := _world_parent()
	if parent == null:
		return
	var rng := RunState.rng
	var offset := Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(0.0, LOOT_SCATTER)
	var at := Vector3(pos.x + offset.x, 0.0, pos.z + offset.z)
	if Arena.current != null:
		at = Arena.current.clamp_point(at, 0.3)
	Pickup.drop(parent, data.gold, data.xp, at)


## Leaves the group and stops colliding / processing (death, despawn).
func _leave_world() -> void:
	if is_in_group(&"enemies"):
		remove_from_group(&"enemies")
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	set_physics_process(false)


## Where projectiles and loot go: the arena's entity root, else this enemy's parent.
func _world_parent() -> Node:
	var arena := Arena.current
	if arena != null and is_instance_valid(arena.entities) and arena.entities.is_inside_tree():
		return arena.entities
	return get_parent()
