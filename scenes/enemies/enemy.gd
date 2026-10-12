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
## Damage taken by the enemy is recorded by the attacker side (WeaponRunner / ProcSystem); the
## enemy only handles knockback, hit flash, slows and death (kill credit, death puff, loot,
## item drops via [method LootDrops.on_enemy_killed], [method Player.notify_kill] for the
## killing Player, [signal died]).
## Players are looked up through the shared per-tick [LivingPlayers] snapshot.
## Subclasses (M5: the Loot Goblin) are built with [method setup] on their own instance and
## override [method _think] (the AI step), [method deals_contact_damage] and
## [method _death_loot] (gold / XP pickup and the item drop roll). Healing (Vampiric elites)
## goes through [method heal], which healing reduction (Mortal Wound) lowers.
##
## Elites (M5, GDD 8, architecture §2.5): [method make_elite] (WaveDirector calls it before
## add_child) turns any enemy into an elite – HP ×3, size ×1.3 (model and body radius), one
## affix ([member elite_affix], numbers in [EliteAffixes]) and an [ElitePlate] child (nameplate,
## shield bubble, enrage tint). Affixes act through per-enemy state used everywhere the base
## numbers are: [member shield_hp] (Shielding – [method take_damage] drains it first),
## [member speed_mult] (walking: [method walk_speed]), [member attack_cooldown_mult] (contact,
## lunge and throw cooldowns: [method attack_cooldown]) and [member damage_mult] (contact and
## thrown damage); Enraged ignores slows once it raged ([method is_enraged]); Vampiric heals
## through the heroes' [signal Player.damage_taken]. Elite rewards (10 gold, XP ×5, a
## guaranteed Rare+ [method LootDrops.drop_special], [method RunState.record_special_kill])
## key on [member elite_affix], never on [method is_elite] (the Loot Goblin returns true there
## for Slayer / targeting only).

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
## Open-field fast path: an enemy whose step stays this far (m, beyond its radius) inside the
## part of the arena that holds no world collider moves directly – move_and_slide would not
## hit anything there. Once per physics tick one shape query checks that the arena interior
## (inside the walls) is free of world colliders; any prop on the world layer switches the
## fast path off for that tick and everybody uses move_and_slide.
const OPEN_FIELD_MARGIN := 0.05
## Height range (m above the ground) of the interior check (enemy bodies live in it).
const OPEN_FIELD_HEIGHT := Vector2(0.05, 2.0)
## Loot lands up to this far (m) from the death position.
const LOOT_SCATTER := 0.4
## Size of the green heal number ([method heal]).
const HEAL_TEXT_SIZE := 0.7
## Shielding elites: "Absorb" text colour / size and the least seconds between two of them.
const ABSORB_TEXT_COLOR := Color(0.62, 0.86, 1.0)
const ABSORB_TEXT_SIZE := 0.7
const ABSORB_TEXT_INTERVAL := 0.3
## Enraged elites: the "Enrage!" text when it triggers.
const ENRAGE_TEXT_COLOR := Color(1.0, 0.32, 0.22)
## State timers end this close to zero (keeps frame counts exact despite float error).
const TIMER_EPSILON := 0.0001

var data: EnemyData
var wave := 1
var hp := 1.0
var max_hp := 1.0
var radius := 0.45
var model: EnemyModel

## Contact damage per hit at this enemy's wave and party size (RunState.coop_damage_mult()).
var contact_damage := 1.0
## Damage of each thrown projectile (RANGED) at this enemy's wave and party size.
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
## Fear (runs away from _fear_from, no attacks) and taunt (chases taunt_target) timers.
var fear_left := 0.0
var taunt_left := 0.0
var taunt_target: Node3D
var _fear_from := Vector3.ZERO
var stun_left := 0.0
## Movement slow (procs such as Frostbite): percent and seconds left (the strongest wins).
var slow_pct := 0.0
var slow_left := 0.0
## Healing reduction (Mortal Wound, M5): percent and seconds left (the strongest wins).
var heal_reduction_pct := 0.0
var heal_reduction_left := 0.0
var knockback_velocity := Vector3.ZERO

## Elite affix (one of EliteAffixes.ALL) or &"" for a normal enemy ([method make_elite]).
var elite_affix: StringName = &""
## Shielding elites: absorb shield left (drained before HP; regrows, see EliteAffixes).
var shield_hp := 0.0
## Per-enemy multipliers (elite affixes): walking speed, contact / lunge / throw cooldowns,
## contact and thrown damage.
var speed_mult := 1.0
var attack_cooldown_mult := 1.0
var damage_mult := 1.0
## The elite's nameplate / look (null for normal enemies).
var elite_plate: ElitePlate

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
## Shielding: seconds until the broken shield regrows.
var _shield_regrow_left := 0.0
## _age of the last "Absorb" text.
var _absorb_text_at := -INF
var _enraged := false
## Vampiric: the heroes whose damage_taken this elite listens to (untyped: entries may be
## freed heroes, never copied into a Player-typed variable before is_instance_valid).
var _vampiric_heroes: Array = []

# Open-field fast path (see OPEN_FIELD_MARGIN): the collider-free interior of this tick.
static var _open_frame := -1
static var _open_ok := false
static var _open_min_x := 0.0
static var _open_max_x := 0.0
static var _open_min_z := 0.0
static var _open_max_z := 0.0
static var _open_query: PhysicsShapeQueryParameters3D

# Frame-cached list of the players in the tree (shared by all enemies and pickups).
static var _player_cache: Array[Player] = []
static var _player_cache_frame := -1
static var _player_cache_count := -1
static var _no_players: Array[Player] = []


static func create(p_data: EnemyData, p_wave: int) -> Enemy:
	return setup(Enemy.new(), p_data, p_wave)


## Configures [param e] (a new Enemy or subclass instance, not in the tree) for [param p_data]
## at wave [param p_wave]: HP / damage growth, speed jitter, collision shape and model.
static func setup(e: Enemy, p_data: EnemyData, p_wave: int) -> Enemy:
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
	e.contact_damage = p_data.contact_damage_at_wave(e.wave) * RunState.coop_damage_mult()
	e.projectile_damage = p_data.projectile_damage_at_wave(e.wave) * RunState.coop_damage_mult()
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
	_disconnect_vampiric()


func is_dead() -> bool:
	return _dead or hp <= 0.0


func is_stunned() -> bool:
	return stun_left > 0.0


## Elites (an [member elite_affix], [method make_elite]) and bosses: Slayer, Execute's victim
## choice and other targeting. Rewards never key on it (the Loot Goblin overrides it with
## true and must not get elite rewards – see [method _death_loot]).
func is_elite() -> bool:
	return elite_affix != &""


## An Enraged elite that has raged (at or below EliteAffixes.ENRAGE_HP_RATIO, once): more
## damage and speed, immune to slows.
func is_enraged() -> bool:
	return _enraged


## Bosses only (a boss is also [method is_elite]): immune to instant kills such as Execute.
## No bosses until M5 / M6.
func is_boss() -> bool:
	return false


func is_slowed() -> bool:
	return slow_left > 0.0 and slow_pct > 0.0


## Slows walking (and lunges) by [param pct] percent (at most 90) for [param duration]
## seconds. A stronger slow replaces the running one, an equal one extends it, a weaker one
## is ignored while the stronger one lasts. An enraged elite ignores slows.
func apply_slow(pct: float, duration: float) -> void:
	if is_dead() or pct <= 0.0 or duration <= 0.0 or _enraged:
		return
	var p := clampf(pct, 0.0, 90.0)
	if slow_left <= 0.0 or p > slow_pct:
		slow_pct = p
		slow_left = duration
	elif is_equal_approx(p, slow_pct):
		slow_left = maxf(slow_left, duration)


## [param attacker] is the Player (or null). [param knockback] is a world-space impulse.
## A Shielding elite's [member shield_hp] takes the damage first ("Absorb"); knockback and the
## hit flash happen either way. An Enraged elite rages when this drops it to half HP.
func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null,
		knockback: Vector3 = Vector3.ZERO) -> void:
	if is_dead() or amount <= 0.0:
		return
	if shield_hp > 0.0:
		amount = _absorb(amount)
	hp -= amount
	if knockback.x != 0.0 or knockback.z != 0.0:
		var resist := clampf(data.knockback_resist, 0.0, 1.0) if data != null else 0.0
		var push := Vector3(knockback.x, 0.0, knockback.z) * KNOCKBACK_VELOCITY_PER_UNIT * (1.0 - resist)
		knockback_velocity = (knockback_velocity + push).limit_length(MAX_KNOCKBACK_SPEED)
	if model != null:
		model.flash_hit()
	if hp <= 0.0:
		_die(attacker)
	elif elite_affix == EliteAffixes.ENRAGED and not _enraged \
			and hp <= max_hp * EliteAffixes.ENRAGE_HP_RATIO:
		_enrage()


## Kills this enemy outright – through a Shielding elite's absorb shield – with the normal
## death (kill credit, loot, [signal died]). For instant kills such as Execute; callers check
## [method is_boss] themselves.
func kill(attacker: Node3D = null) -> void:
	if is_dead():
		return
	shield_hp = 0.0
	hp = 0.0
	_die(attacker)


## Runs away from [param from] for [param duration] seconds (Fear): no attacks, no contact
## damage. Stun resistance shortens it.
func apply_fear(duration: float, from: Vector3) -> void:
	if is_dead() or duration <= 0.0:
		return
	var resist := clampf(data.stun_resist, 0.0, 1.0) if data != null else 0.0
	var d := duration * (1.0 - resist)
	if d <= 0.0:
		return
	fear_left = maxf(fear_left, d)
	_fear_from = Vector3(from.x, 0.0, from.z)
	if ai_state != AiState.MOVE:
		ai_state = AiState.MOVE
		state_left = 0.0


func is_feared() -> bool:
	return fear_left > 0.0


## Chases [param target] (a pet, a decoy) instead of the players for [param duration]
## seconds; touching a player still hurts it.
func apply_taunt(target: Node3D, duration: float) -> void:
	if is_dead() or target == null or duration <= 0.0:
		return
	taunt_target = target
	taunt_left = maxf(taunt_left, duration)


func is_taunted() -> bool:
	return taunt_left > 0.0 and taunt_target != null and is_instance_valid(taunt_target) \
			and taunt_target.is_inside_tree()


## Ends a taunt towards [param target] (a hero that went down – Challenging Charge, Righteous
## Fury); a taunt towards anything else keeps running.
func release_taunt(target: Node3D) -> void:
	if target == null or taunt_target != target:
		return
	taunt_left = 0.0
	taunt_target = null


## Whether touching a player hurts it (the Loot Goblin overrides it with false).
func deals_contact_damage() -> bool:
	return true


## Healing reduction (Mortal Wound): heals on this enemy restore [param pct] percent less for
## [param duration] seconds. A stronger reduction replaces the running one, an equal one
## extends it, a weaker one is ignored while the stronger one lasts.
func apply_healing_reduction(pct: float, duration: float) -> void:
	if is_dead() or pct <= 0.0 or duration <= 0.0:
		return
	var p := clampf(pct, 0.0, 100.0)
	if heal_reduction_left <= 0.0 or p > heal_reduction_pct:
		heal_reduction_pct = p
		heal_reduction_left = duration
	elif is_equal_approx(p, heal_reduction_pct):
		heal_reduction_left = maxf(heal_reduction_left, duration)


## Multiplier on heals this enemy receives (1 = full, 0.5 under a 50% reduction).
func healing_taken_mult() -> float:
	if heal_reduction_left <= 0.0:
		return 1.0
	return clampf(1.0 - heal_reduction_pct / 100.0, 0.0, 1.0)


## Heals [param amount] x [method healing_taken_mult], at most up to max_hp, with a green
## number. Returns the HP restored (0 when dead or full).
func heal(amount: float) -> float:
	if is_dead() or amount <= 0.0:
		return 0.0
	var gained := minf(max_hp - hp, amount * healing_taken_mult())
	if gained <= 0.0:
		return 0.0
	hp += gained
	var pos := global_position if is_inside_tree() else position
	Vfx.floating_text(pos + Vector3.UP * WeaponRunner.DAMAGE_TEXT_HEIGHT,
			"+" + Player._format_amount(gained), Player.HEAL_TEXT_COLOR, HEAL_TEXT_SIZE)
	return gained


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
			attack_cooldown_left = maxf(attack_cooldown_left, attack_cooldown() * 0.5)
	if not was_stunned and model != null:
		model.set_stunned(true)


## Removes the enemy without loot (wave end).
func despawn() -> void:
	if _dead and is_queued_for_deletion():
		return
	_dead = true
	_leave_world()
	queue_free()


# --- Elites (M5) -------------------------------------------------------------------

## Turns this enemy into an elite with [param affix] (one of EliteAffixes.ALL): HP ×3 (hp and
## max_hp), model and body ×1.3, the affix's state and an [ElitePlate] child. Called before
## add_child (WaveDirector), so it needs no tree: a Vampiric elite connects to the heroes of
## PlayerManager's slots right here (heroes that join later are not connected – there is no
## drop-in during a wave). Draws nothing from the rng. An enemy is made elite at most once;
## an unknown affix is an error.
func make_elite(affix: StringName) -> void:
	if elite_affix != &"" or is_dead():
		return
	if affix not in EliteAffixes.ALL:
		push_error("Enemy.make_elite: unknown affix '%s'" % affix)
		return
	elite_affix = affix
	max_hp *= EliteAffixes.HP_MULT
	hp *= EliteAffixes.HP_MULT
	radius *= EliteAffixes.MODEL_SCALE
	var shape := get_node_or_null(^"Shape") as CollisionShape3D
	if shape != null and shape.shape is SphereShape3D:
		(shape.shape as SphereShape3D).radius = radius
	if model != null:
		model.scale = Vector3.ONE * EliteAffixes.MODEL_SCALE
	match affix:
		EliteAffixes.SHIELDING:
			_raise_shield()
		EliteAffixes.FRENZIED:
			speed_mult *= EliteAffixes.FRENZY_SPEED_MULT
			attack_cooldown_mult *= EliteAffixes.FRENZY_COOLDOWN_MULT
			attack_cooldown_left *= EliteAffixes.FRENZY_COOLDOWN_MULT
		EliteAffixes.VAMPIRIC:
			_connect_vampiric()
	elite_plate = ElitePlate.create(self)
	add_child(elite_plate)
	EnemyGrid.mark_dirty()  # the radius changed


## Walking speed (m/s): [member move_speed] × [member speed_mult] (Frenzied / Enraged).
func walk_speed() -> float:
	return move_speed * speed_mult


## Seconds between two lunges / throws: data.attack_cooldown × [member attack_cooldown_mult].
func attack_cooldown() -> float:
	return (data.attack_cooldown if data != null else 0.0) * attack_cooldown_mult


## Shielding: a fresh absorb shield of EliteAffixes.SHIELD_PCT of max HP.
func _raise_shield() -> void:
	shield_hp = max_hp * EliteAffixes.SHIELD_PCT
	_shield_regrow_left = 0.0


## The shield takes what it can of [param amount]; returns the rest. A broken shield starts
## its regrow timer.
func _absorb(amount: float) -> float:
	var absorbed := minf(shield_hp, amount)
	shield_hp -= absorbed
	if shield_hp <= 0.0001:
		shield_hp = 0.0
		_shield_regrow_left = EliteAffixes.SHIELD_REGROW
	if absorbed > 0.0 and _age - _absorb_text_at >= ABSORB_TEXT_INTERVAL:
		_absorb_text_at = _age
		var pos := global_position if is_inside_tree() else position
		Vfx.floating_text(pos + Vector3.UP * WeaponRunner.DAMAGE_TEXT_HEIGHT, "Absorb",
				ABSORB_TEXT_COLOR, ABSORB_TEXT_SIZE)
	return amount - absorbed


## Enraged: more damage and speed for the rest of its life, slows end and no longer land.
func _enrage() -> void:
	_enraged = true
	damage_mult *= EliteAffixes.ENRAGE_DAMAGE_MULT
	speed_mult *= EliteAffixes.ENRAGE_SPEED_MULT
	slow_pct = 0.0
	slow_left = 0.0
	var pos := global_position if is_inside_tree() else position
	var top := model.head_height * EliteAffixes.MODEL_SCALE if model != null else 1.2
	Vfx.floating_text(pos + Vector3.UP * top, "Enrage!", ENRAGE_TEXT_COLOR, 1.0)


## Vampiric: listens to every joined hero's damage_taken (see [method make_elite]).
func _connect_vampiric() -> void:
	for slot in PlayerManager.get_slots():
		if not is_instance_valid(slot.player):
			continue
		var hero := slot.player as Player
		if hero == null or _vampiric_heroes.has(hero):
			continue
		hero.damage_taken.connect(_on_hero_damage_taken)
		_vampiric_heroes.append(hero)


func _disconnect_vampiric() -> void:
	for i in _vampiric_heroes.size():
		if not is_instance_valid(_vampiric_heroes[i]):
			continue
		var hero := _vampiric_heroes[i] as Player
		if hero != null and hero.damage_taken.is_connected(_on_hero_damage_taken):
			hero.damage_taken.disconnect(_on_hero_damage_taken)
	_vampiric_heroes.clear()


## A hero took [param amount] damage from [param source]: when that was this Vampiric elite
## (contact or one of its axes), heal EliteAffixes.VAMPIRIC_HEAL_PCT of max HP.
func _on_hero_damage_taken(amount: float, source: Node3D) -> void:
	if source != self or amount <= 0.0 or is_dead():
		return
	heal(max_hp * EliteAffixes.VAMPIRIC_HEAL_PCT)


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
	if slow_left > 0.0:
		slow_left -= delta
		if slow_left <= 0.0:
			slow_left = 0.0
			slow_pct = 0.0
	if heal_reduction_left > 0.0:
		heal_reduction_left -= delta
		if heal_reduction_left <= 0.0:
			heal_reduction_left = 0.0
			heal_reduction_pct = 0.0
	if _shield_regrow_left > 0.0 and shield_hp <= 0.0:
		_shield_regrow_left -= delta
		if _shield_regrow_left <= TIMER_EPSILON:
			_raise_shield()
	if stunned:
		stun_left -= delta
		if stun_left <= 0.0:
			stun_left = 0.0
			if model != null:
				model.set_stunned(false)
	var feared := fear_left > 0.0
	if feared:
		fear_left = maxf(0.0, fear_left - delta)
	if taunt_left > 0.0:
		taunt_left = maxf(0.0, taunt_left - delta)
		if taunt_left <= 0.0:
			taunt_target = null

	var here := global_position
	_scan_players(here, stunned or feared or not deals_contact_damage())
	if _dead or not is_inside_tree():
		return  # a contact hit ended the run and the wave removed us

	if stunned:
		_move_velocity = Vector3.ZERO
	else:
		_think(delta, here, feared)
	_apply_movement(delta, here, stunned)
	if model != null:
		# Only forward noticeable changes (the model smooths them anyway).
		if _facing.dot(_sent_facing) < 0.9995:
			_sent_facing = _facing
			model.set_facing(_facing)
		var moving := clampf(_move_velocity.length() / maxf(0.1, walk_speed()), 0.0, 1.0)
		if absf(moving - _sent_moving) > 0.03:
			_sent_moving = moving
			model.set_moving(moving)


## One AI step while not stunned (after the player scan: [member _target] is the nearest
## visible living player or null): fear (run away), taunt (chase the taunter), then the
## behaviour (lunge / ranged / chase, or wander without a target). Sets the desired walking
## velocity; subclasses (the Loot Goblin's flight) replace it.
func _think(delta: float, here: Vector3, feared: bool) -> void:
	if feared:
		var away := Vector3(here.x - _fear_from.x, 0.0, here.z - _fear_from.z)
		var dir := away.normalized() if away.length_squared() > 0.0001 else _facing
		_steer(dir * walk_speed(), delta)
		_facing = dir
	elif is_taunted():
		_target_pos = Vector3(taunt_target.global_position.x, 0.0, taunt_target.global_position.z)
		_target_dist_sq = WeaponRunner.flat(_target_pos - here).length_squared()
		_update_chase(delta, here)
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
	var hidden := LivingPlayers.stealthed
	var reach := radius + Player.RADIUS
	var reach_sq := reach * reach
	var can_hit := not stunned and contact_cooldown_left <= 0.0
	var best := -1
	for i in n:
		if hidden[i] != 0:
			continue  # stealthed (Vanish): neither touched nor chased
		var dx := xs[i] - here.x
		var dz := zs[i] - here.z
		var d_sq := dx * dx + dz * dz
		if can_hit and d_sq <= reach_sq:
			if not is_living_player(players[i]):
				continue  # went down (or away) since the snapshot
			var p := players[i]
			can_hit = false
			contact_cooldown_left = CONTACT_COOLDOWN * attack_cooldown_mult
			p.take_damage(contact_damage * damage_mult, CombatMath.KIND_MELEE, self)
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
	var speed := walk_speed()
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
				attack_cooldown_left = attack_cooldown()
				_move_velocity = _aim_dir * walk_speed()
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
			attack_cooldown_left = attack_cooldown()
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
	var speed := walk_speed()
	var desired: Vector3
	if dist > preferred + RANGED_DISTANCE_SLACK:
		desired = dir * speed
	elif dist < preferred - RANGED_DISTANCE_SLACK:
		desired = -dir * speed
	else:
		var side := Vector3(-dir.z, 0.0, dir.x) * _strafe_sign
		var radial := (dist - preferred) / RANGED_DISTANCE_SLACK
		desired = (side * STRAFE_SPEED_RATIO + dir * (radial * 0.5)) * speed
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
	_steer(_wander_dir * walk_speed() * WANDER_SPEED_RATIO, delta)
	if _wander_dir != Vector3.ZERO:
		_facing = _wander_dir


func _throw(here: Vector3) -> void:
	var parent := _world_parent()
	if parent == null:
		return
	var dir := _aim_dir
	var proj := Projectile.create(Projectile.TEAM_ENEMIES, projectile_damage * damage_mult, false, dir,
			data.projectile_speed, THROW_RANGE, 0, 0.0, self, &"axe", Projectile.default_color(&"axe"))
	parent.add_child(proj)
	# Released a little in front of the body so it does not start inside the thrower.
	proj.global_position = here + Vector3.UP * THROW_HEIGHT + dir * (radius + 0.15)
	if model != null:
		model.play_attack()


func _steer(desired: Vector3, delta: float) -> void:
	_move_velocity = _move_velocity.move_toward(desired, STEER_ACCELERATION * delta)


## Walk + knockback, adjusted by the crowd ([method EnemyGrid.crowd_velocity]: slides along
## touching neighbours, pushes out of overlaps – not while stunned), then a move against the
## world: directly in the open field (nothing to hit there), else move_and_slide.
func _apply_movement(delta: float, here: Vector3, stunned: bool) -> void:
	if knockback_velocity != Vector3.ZERO:
		knockback_velocity *= exp(-KNOCKBACK_DECAY * delta)
		if knockback_velocity.length_squared() < 0.0025:
			knockback_velocity = Vector3.ZERO
	var walk := _move_velocity
	if slow_left > 0.0:
		walk *= 1.0 - slow_pct / 100.0
	velocity = EnemyGrid.crowd_velocity(self, walk + knockback_velocity, delta, not stunned)
	if velocity.length_squared() < 0.000001:
		velocity = Vector3.ZERO
		return
	var nx := here.x + velocity.x * delta
	var nz := here.z + velocity.z * delta
	if _open_frame != Engine.get_physics_frames():
		_update_open_field(self)
	var m := radius + OPEN_FIELD_MARGIN
	if _open_ok and here.y == 0.0 and nx - m >= _open_min_x and nx + m <= _open_max_x \
			and nz - m >= _open_min_z and nz + m <= _open_max_z:
		global_position = Vector3(nx, 0.0, nz)
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


## Once per physics tick: is the arena interior (inside the walls) free of world colliders?
static func _update_open_field(e: Enemy) -> void:
	_open_frame = Engine.get_physics_frames()
	_open_ok = false
	var arena := Arena.current
	if arena == null or not arena.is_inside_tree() or not e.is_inside_tree():
		return
	var world := e.get_world_3d()
	var space := world.direct_space_state if world != null else null
	if space == null:
		return
	var b := arena.get_bounds()
	if not b.has_area():
		return
	if _open_query == null:
		_open_query = PhysicsShapeQueryParameters3D.new()
		_open_query.shape = BoxShape3D.new()
		_open_query.collision_mask = COLLISION_MASK_WORLD
		_open_query.collide_with_areas = false
		_open_query.collide_with_bodies = true
	# Slightly smaller than the bounds: the walls' inner faces lie exactly on them.
	var inner := b.grow(-0.02)
	var height := OPEN_FIELD_HEIGHT.y - OPEN_FIELD_HEIGHT.x
	(_open_query.shape as BoxShape3D).size = Vector3(inner.size.x, height, inner.size.y)
	var center := inner.get_center()
	_open_query.transform = Transform3D(Basis.IDENTITY,
			Vector3(center.x, OPEN_FIELD_HEIGHT.x + height * 0.5, center.y))
	if not space.intersect_shape(_open_query, 1).is_empty():
		return
	_open_ok = true
	_open_min_x = b.position.x
	_open_max_x = b.end.x
	_open_min_z = b.position.y
	_open_max_z = b.end.y


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
	var killer: Player = null
	if attacker != null and is_instance_valid(attacker):
		killer = attacker as Player
		if killer != null and killer.slot != null:
			killer_index = killer.slot.index
	RunState.record_kill(killer_index)
	var pos := global_position if is_inside_tree() else position
	if data != null:
		Vfx.death_puff(pos + Vector3.UP * 0.5 * data.model_scale, data.color, data.model_scale)
	_death_loot(pos, attacker)
	_leave_world()
	died.emit(self, killer_index)
	# On-kill effects of the killing hero (Life on Kill, on-kill procs) – after the enemy left
	# the world, so a corpse explosion never hits the corpse itself.
	if killer != null and is_instance_valid(killer):
		killer.notify_kill(self)
	queue_free()


## What a death leaves at [param pos]: the gold / XP pickup and the item drop roll (GDD 10.1 –
## the killer's Fortune counts; a null / freed [param attacker] uses the base chance).
## An elite ([member elite_affix] set – not [method is_elite], which the Loot Goblin
## overrides) pays EliteAffixes.GOLD instead of data.gold and data.xp × XP_MULT, drops a
## guaranteed Rare+ item through [method LootDrops.drop_special] (killer's Fortune, not
## counted against the normal cap) and records the special kill; the normal drop roll still
## follows. Subclasses with their own rewards (the Loot Goblin) replace it.
func _death_loot(pos: Vector3, attacker: Node3D) -> void:
	var killer: Node3D = attacker if attacker != null and is_instance_valid(attacker) else null
	if elite_affix != &"":
		_drop_pickup(pos, EliteAffixes.GOLD, (data.xp if data != null else 0) * EliteAffixes.XP_MULT)
		LootDrops.drop_special(ItemGenerator.Source.ELITE, self, killer)
		var killer_player := killer as Player
		RunState.record_special_kill(&"elite",
				killer_player.slot.index if killer_player != null and killer_player.slot != null else -1)
	elif data != null:
		_drop_loot(pos)
	LootDrops.on_enemy_killed(self, killer)


## The regular gold / XP pickup of data.gold and data.xp.
func _drop_loot(pos: Vector3) -> void:
	_drop_pickup(pos, data.gold, data.xp)


## A gold / XP pickup scattered up to LOOT_SCATTER around [param pos] (two rng draws).
func _drop_pickup(pos: Vector3, gold: int, xp: int) -> void:
	if gold <= 0 and xp <= 0:
		return
	var parent := _world_parent()
	if parent == null:
		return
	var rng := RunState.rng
	var offset := Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(0.0, LOOT_SCATTER)
	var at := Vector3(pos.x + offset.x, 0.0, pos.z + offset.z)
	if Arena.current != null:
		at = Arena.current.clamp_point(at, 0.3)
	Pickup.drop(parent, gold, xp, at)


## Leaves the group and stops colliding / processing (death, despawn); a Vampiric elite stops
## listening to the heroes.
func _leave_world() -> void:
	_disconnect_vampiric()
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
