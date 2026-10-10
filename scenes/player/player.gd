class_name Player
extends CharacterBody3D
## A local co-op hero (GDD 1, 2, 3). Group &"players". Collision layer 2 ("players"),
## mask 1 ("world") – enemies do NOT physically block players; they deal contact damage.
## Moves on the XZ plane: input Vector2(x, y) -> world Vector3(x, 0, y).
##
## Stats come from a StatBlock with the sources &"class" (ClassData.base_stats),
## &"weapon:main" and &"weapon:off" (WeaponData.bonus_stats). Every equipped weapon that
## attacks gets its own WeaponRunner child. At 0 HP the player is downed (a slow ghost that
## does not attack); a living teammate standing within REVIVE_RADIUS for REVIVE_TIME
## seconds revives them.

signal hp_changed(hp: float, max_hp: float)
signal downed_changed(is_downed: bool)
## Emitted after damage actually landed (not on dodge, i-frames or while downed).
signal damage_taken(amount: float, source: Node3D)
## Emitted from on_hit_dealt() after each successful weapon hit of this player.
signal hit_dealt(damage: float, target: Node3D)

const RADIUS := 0.45
## Height (metres) where projectiles / damage numbers originate.
const CHEST_HEIGHT := 0.7
const REVIVE_RADIUS := 1.8
const REVIVE_TIME := 3.0
const INVULNERABLE_AFTER_HIT := 0.35

## Collision capsule height (the onion is ~1.3 m tall).
const BODY_HEIGHT := 1.2
const COLLISION_LAYER_PLAYERS := 1 << 1
const COLLISION_MASK_WORLD := 1
## m/s^2 while steering / when the stick is released.
const ACCELERATION := 40.0
const DECELERATION := 60.0
const MOVE_DEADZONE := 0.05
## Downed ghosts move at half speed (GDD 1).
const GHOST_SPEED_MULT := 0.5
## HP fraction after a teammate revive / after a wave starts while downed.
const REVIVE_HP_RATIO := 0.3
const WAVE_START_REVIVE_HP_RATIO := 0.5
## Revive progress (seconds) lost per second while nobody stands next to the ghost.
const REVIVE_DECAY_PER_SECOND := 0.5
const INVULNERABLE_AFTER_REVIVE := 1.0
const BLOCK_DAMAGE_MULT := 0.5
## How long the model keeps looking at its last attack target while standing still.
const ATTACK_LOOK_TIME := 0.4
const HIT_SHAKE := 0.15

const DAMAGE_TEXT_COLOR := Color(1.0, 0.27, 0.22)
const HEAL_TEXT_COLOR := Color(0.35, 1.0, 0.4)
const DODGE_TEXT_COLOR := Color(0.7, 0.88, 1.0)
const BLOCK_TEXT_COLOR := Color(0.88, 0.88, 0.95)

var slot: PlayerSlot
var stats := StatBlock.new()
var hp := 10.0
var downed := false
var model: OnionModel
## Last non-zero movement direction (XZ, normalised); weapons fall back to it.
var facing := Vector3.FORWARD

## The class this player was built from (slot.class_data or the default class).
var class_data: ClassData
var main_hand: WeaponData
var off_hand: WeaponData
## One runner per equipped weapon that attacks (main hand first).
var weapons: Array[WeaponRunner] = []
## Seconds of revive progress while downed (0 .. REVIVE_TIME).
var revive_progress := 0.0
## Remaining invulnerability (i-frames) in seconds.
var invulnerable_left := 0.0

var _regen_accum := 0.0
var _attack_look_dir := Vector3.FORWARD
var _attack_look_left := 0.0


## Creates and configures a player for [param p_slot]. Not yet in the tree.
static func create(p_slot: PlayerSlot) -> Player:
	var p := Player.new()
	p.slot = p_slot
	p.name = "Player%d" % (p_slot.index + 1) if p_slot != null else "Player"
	p.collision_layer = COLLISION_LAYER_PLAYERS
	p.collision_mask = COLLISION_MASK_WORLD
	p.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	p.add_to_group(&"players")

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = BODY_HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0.0, BODY_HEIGHT * 0.5, 0.0)
	p.add_child(shape)

	p.class_data = p_slot.class_data if p_slot != null and p_slot.class_data != null else Db.get_default_class()
	p.model = OnionModel.new()
	p.model.name = "Model"
	p.add_child(p.model)
	if p.class_data != null:
		p.model.setup(p.class_data, p_slot.color if p_slot != null else Color.WHITE)
		p.stats.set_source(&"class", p.class_data.base_stats)
		p.equip_weapons(p.class_data.main_hand, p.class_data.off_hand)
	else:
		p.equip_weapons(null, null)
	p.hp = p.max_hp()
	p.stats.changed.connect(p._on_stats_changed)

	if p_slot != null:
		p_slot.player = p
		var bot := p_slot.input as BotInput
		if bot != null:
			bot.body = p
	return p


func max_hp() -> float:
	return stats.max_hp()


func is_alive() -> bool:
	return not downed


## Wave start: living players heal to full; downed players come back at 50% HP (GDD 1).
func begin_wave() -> void:
	velocity = Vector3.ZERO
	_regen_accum = 0.0
	_attack_look_left = 0.0
	revive_progress = 0.0
	if downed:
		revive(WAVE_START_REVIVE_HP_RATIO)
	else:
		hp = max_hp()
		_hp_updated()
	invulnerable_left = 0.0
	for runner in weapons:
		runner.reset()


## Called by enemies / enemy projectiles. Rolls dodge and block, applies armour etc.
## [param kind] is one of CombatMath.KIND_*.
func take_damage(raw: float, kind: StringName = CombatMath.KIND_MELEE, source: Node3D = null) -> void:
	if downed or invulnerable_left > 0.0 or raw <= 0.0:
		return
	var rng := RunState.rng
	var text_pos := get_chest_position() + Vector3.UP * 0.5
	if stats.get_stat(Stats.DODGE) > 0.0 and CombatMath.roll_dodge(stats, rng):
		Vfx.floating_text(text_pos, "Dodge", DODGE_TEXT_COLOR, 0.9)
		return
	var amount := raw
	var block := block_chance()
	if block > 0.0 and CombatMath.roll_block(block, rng):
		amount *= BLOCK_DAMAGE_MULT
		Vfx.floating_text(text_pos + Vector3.UP * 0.35, "Block", BLOCK_TEXT_COLOR, 0.9)
	var dmg := CombatMath.incoming_damage(amount, stats, kind)
	hp = maxf(0.0, hp - dmg)
	invulnerable_left = INVULNERABLE_AFTER_HIT
	Vfx.floating_text(text_pos, _format_amount(dmg), DAMAGE_TEXT_COLOR, 1.0)
	if model != null:
		model.flash_hit()
	_shake_camera(HIT_SHAKE)
	_hp_updated()
	damage_taken.emit(dmg, source)
	if hp <= 0.0:
		_go_down()


func heal(amount: float) -> void:
	if downed or amount <= 0.0:
		return
	var before := hp
	hp = minf(max_hp(), hp + amount)
	var gained := hp - before
	if gained <= 0.0:
		return
	Vfx.floating_text(get_chest_position() + Vector3.UP * 0.5, "+" + _format_amount(gained), HEAL_TEXT_COLOR, 0.9)
	_hp_updated()


## Called by this player's weapons after each successful hit (leech etc.).
func on_hit_dealt(damage: float, target: Node3D) -> void:
	if downed:
		return
	hit_dealt.emit(damage, target)
	if stats.get_stat(Stats.LEECH) > 0.0 and CombatMath.roll_leech(stats, RunState.rng):
		heal(1.0)


# --- Extra public helpers ------------------------------------------------------

## Equips [param p_main] / [param p_off] (null = empty hand): updates the weapon stat
## sources, rebuilds the WeaponRunners and the weapon models.
func equip_weapons(p_main: WeaponData, p_off: WeaponData) -> void:
	main_hand = p_main
	off_hand = p_off
	if p_main != null:
		stats.set_source(&"weapon:main", p_main.bonus_stats)
	else:
		stats.remove_source(&"weapon:main")
	if p_off != null:
		stats.set_source(&"weapon:off", p_off.bonus_stats)
	else:
		stats.remove_source(&"weapon:off")
	for runner in weapons:
		remove_child(runner)
		runner.queue_free()
	weapons.clear()
	if p_main != null and p_main.attacks():
		_add_runner(WeaponRunner.create(p_main, self, false))
	if p_off != null and p_off.attacks():
		_add_runner(WeaponRunner.create(p_off, self, true))
	if model != null:
		model.set_weapons(p_main, p_off)


## Total block chance (percent) of the equipped weapons (shields).
func block_chance() -> float:
	var total := 0.0
	if main_hand != null:
		total += main_hand.block_chance
	if off_hand != null:
		total += off_hand.block_chance
	return total


## Revives a downed player at [param hp_ratio] of max HP (min 1 HP).
func revive(hp_ratio: float = REVIVE_HP_RATIO) -> void:
	if not downed:
		return
	downed = false
	revive_progress = 0.0
	_regen_accum = 0.0
	velocity = Vector3.ZERO
	hp = clampf(roundf(max_hp() * hp_ratio), 1.0, max_hp())
	invulnerable_left = INVULNERABLE_AFTER_REVIVE
	if model != null:
		model.set_revive_progress(0.0)
		model.set_downed(false)
	_hp_updated()
	downed_changed.emit(false)


## Current top speed in m/s (halved while downed).
func current_max_speed() -> float:
	return stats.move_speed() * (GHOST_SPEED_MULT if downed else 1.0)


func get_chest_position() -> Vector3:
	return global_position + Vector3.UP * CHEST_HEIGHT if is_inside_tree() else position + Vector3.UP * CHEST_HEIGHT


## Called by weapons: while standing still the model briefly turns towards its target.
func face_attack(direction: Vector3) -> void:
	var d := Vector3(direction.x, 0.0, direction.z)
	if d.length_squared() > 0.0001:
		_attack_look_dir = d.normalized()
		_attack_look_left = ATTACK_LOOK_TIME


# --- Frame update ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	invulnerable_left = maxf(0.0, invulnerable_left - delta)
	_attack_look_left = maxf(0.0, _attack_look_left - delta)
	_update_movement(delta)
	if downed:
		_update_revive(delta)
	else:
		_update_regen(delta)


func _update_movement(delta: float) -> void:
	var move := Vector2.ZERO
	if slot != null and slot.input != null:
		move = slot.input.get_move()
	if move.length() > 1.0:
		move = move.normalized()
	var max_speed := current_max_speed()
	var target := Vector3(move.x, 0.0, move.y) * max_speed
	var rate := ACCELERATION if move.length() > MOVE_DEADZONE else DECELERATION
	velocity = Vector3(velocity.x, 0.0, velocity.z).move_toward(target, rate * delta)
	_move_body(velocity * delta)
	if Arena.current != null and is_inside_tree():
		global_position = Arena.current.clamp_point(global_position, RADIUS)
	if move.length() > MOVE_DEADZONE:
		facing = Vector3(move.x, 0.0, move.y).normalized()
	if model != null:
		var look := facing
		if move.length() <= MOVE_DEADZONE and _attack_look_left > 0.0:
			look = _attack_look_dir
		model.set_facing(look)
		model.set_moving(clampf(velocity.length() / maxf(0.01, max_speed), 0.0, 1.0))


## Moves by [param motion], sliding along walls. Uses move_and_collide so the motion is
## exactly the requested one (deterministic for tests and time-scaled smoke runs).
func _move_body(motion: Vector3) -> void:
	if motion.length_squared() < 1e-10:
		return
	if not is_inside_tree():
		position += motion
		return
	var remaining := motion
	for _i in 3:
		var col := move_and_collide(remaining)
		if col == null:
			break
		var normal := col.get_normal()
		normal.y = 0.0
		if normal.length_squared() < 1e-6:
			break
		normal = normal.normalized()
		remaining = col.get_remainder().slide(normal)
		remaining.y = 0.0
		velocity = velocity.slide(normal)
		if remaining.length_squared() < 1e-10:
			break


func _update_regen(delta: float) -> void:
	var regen := stats.hp_regen_per_second()
	if regen <= 0.0 or hp >= max_hp():
		_regen_accum = 0.0
		return
	_regen_accum += regen * delta
	if _regen_accum >= 1.0:
		var whole := floorf(_regen_accum)
		_regen_accum -= whole
		heal(whole)


func _update_revive(delta: float) -> void:
	if _has_reviver():
		revive_progress = minf(REVIVE_TIME, revive_progress + delta)
	else:
		revive_progress = maxf(0.0, revive_progress - REVIVE_DECAY_PER_SECOND * delta)
	if model != null:
		model.set_revive_progress(revive_progress / REVIVE_TIME)
	if revive_progress >= REVIVE_TIME - 0.0001:
		revive(REVIVE_HP_RATIO)
		Vfx.floating_text(get_chest_position() + Vector3.UP * 0.6, "Revived!", HEAL_TEXT_COLOR, 1.2)


## True when a living teammate stands within REVIVE_RADIUS.
func _has_reviver() -> bool:
	if not is_inside_tree():
		return false
	var here := global_position
	for node in get_tree().get_nodes_in_group(&"players"):
		var other := node as Player
		if other == null or other == self or not other.is_alive() or not other.is_inside_tree():
			continue
		var d := other.global_position - here
		if Vector2(d.x, d.z).length() <= REVIVE_RADIUS:
			return true
	return false


func _go_down() -> void:
	downed = true
	revive_progress = 0.0
	_regen_accum = 0.0
	invulnerable_left = 0.0
	if model != null:
		model.set_downed(true)
		model.set_revive_progress(0.0)
	downed_changed.emit(true)


func _hp_updated() -> void:
	var m := max_hp()
	if model != null:
		model.set_hp_ratio(clampf(hp / m, 0.0, 1.0))
	hp_changed.emit(hp, m)


func _on_stats_changed() -> void:
	if hp > max_hp():
		hp = max_hp()
	_hp_updated()


func _add_runner(runner: WeaponRunner) -> void:
	weapons.append(runner)
	add_child(runner)


func _shake_camera(strength: float) -> void:
	var arena := Arena.current
	if arena != null and is_instance_valid(arena.camera):
		arena.camera.shake(strength)


static func _format_amount(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and slot != null and slot.player == self:
		slot.player = null
