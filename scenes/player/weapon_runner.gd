class_name WeaponRunner
extends Node3D
## Auto-attacks with one equipped weapon (GDD 4). Child of a Player.
##
## Cooldown = CombatMath.weapon_cooldown (Haste shortens it). When ready, the runner picks
## the nearest living enemy within weapon.attack_range and
##   MELEE_ARC  – hits every enemy within attack_range + enemy.radius inside arc_degrees of
##                the swing direction,
##   PROJECTILE – fires a Projectile (TEAM_PLAYERS) at it.
## Main hand and off hand run independently; the off hand starts half a cooldown late so
## dual-wielded weapons alternate.

## Fraction of the cooldown the off hand waits at wave start / after idling.
const OFF_HAND_PHASE := 0.5
## Projectiles fly this much further than the targeting range.
const PROJECTILE_EXTRA_RANGE := 3.0
## Fraction of the target's velocity used to lead projectile shots.
const PROJECTILE_LEAD := 0.8
const DAMAGE_TEXT_HEIGHT := 1.2
## Damage numbers: small, slightly transparent white for normal hits, bigger opaque yellow
## for crits (hits on the same enemy within Vfx.MERGE_WINDOW add up on one number).
const NORMAL_TEXT_COLOR := Color(1.0, 1.0, 1.0, 0.75)
const CRIT_TEXT_COLOR := Color(1.0, 0.84, 0.12)
const NORMAL_TEXT_SIZE := 0.6
const CRIT_TEXT_SIZE := 1.1

var weapon: WeaponData
var player: Player
var is_off_hand := false
## Seconds until the weapon may attack again (<= 0 = ready).
var cooldown_left := 0.0

var _waiting_for_target := false


static func create(p_weapon: WeaponData, owner_player: Player, p_off_hand: bool) -> WeaponRunner:
	var w := WeaponRunner.new()
	w.weapon = p_weapon
	w.player = owner_player
	w.is_off_hand = p_off_hand
	w.name = "OffHandWeapon" if p_off_hand else "MainHandWeapon"
	w.reset()
	return w


## Wave start: main hand ready at once, off hand half a cooldown later.
func reset() -> void:
	_waiting_for_target = false
	cooldown_left = cooldown() * OFF_HAND_PHASE if is_off_hand else 0.0


## Current seconds between attacks (after Haste).
func cooldown() -> float:
	if weapon == null:
		return 1.0
	if player == null:
		return weapon.cooldown
	return CombatMath.weapon_cooldown(weapon, player.stats)


func _physics_process(delta: float) -> void:
	tick(delta)


## Advances the cooldown by [param delta] and attacks when ready. Returns true if it attacked.
func tick(delta: float) -> bool:
	if weapon == null or not weapon.attacks() or player == null or not player.is_alive():
		return false
	cooldown_left -= delta
	if cooldown_left > 0.0:
		return false
	var target := find_target()
	if target == null:
		cooldown_left = 0.0
		_waiting_for_target = true
		return false
	if _waiting_for_target:
		_waiting_for_target = false
		if is_off_hand:
			# Keep dual-wielded weapons alternating after an idle period.
			cooldown_left = cooldown() * OFF_HAND_PHASE
			return false
		cooldown_left = 0.0
	# Carry the overshoot of this tick so the average attack rate is exact.
	cooldown_left = maxf(cooldown_left, -delta) + cooldown()
	attack(target)
	return true


## Nearest living enemy within the weapon's attack range (null if none).
func find_target() -> Enemy:
	if weapon == null or player == null or not player.is_inside_tree():
		return null
	return nearest_enemy(player.get_tree().get_nodes_in_group(&"enemies"), player.global_position, weapon.attack_range)


## Attacks [param target] right now (no cooldown check).
func attack(target: Enemy) -> void:
	if weapon == null or player == null or not player.is_inside_tree():
		return
	var origin := player.global_position
	var dir := flat(target.global_position - origin)
	dir = dir.normalized() if dir.length_squared() > 0.000001 else player.facing
	match weapon.attack_kind:
		WeaponData.AttackKind.MELEE_ARC:
			_melee(origin, dir)
		WeaponData.AttackKind.PROJECTILE:
			dir = _lead_direction(origin, target, dir)
			_shoot(origin, dir)
		_:
			return
	player.face_attack(dir)
	if player.model != null:
		player.model.play_attack(is_off_hand)


func _melee(origin: Vector3, dir: Vector3) -> void:
	var base := CombatMath.weapon_hit_damage(weapon, player.stats)
	var nodes := player.get_tree().get_nodes_in_group(&"enemies")
	var hits := enemies_in_arc(nodes, origin, dir, weapon.attack_range, weapon.arc_degrees)
	Vfx.slash_arc(origin + Vector3.UP * 0.3, dir, weapon.attack_range, weapon.arc_degrees, _slash_color())
	for e in hits:
		if not is_instance_valid(e) or e.is_dead():
			continue
		var crit := CombatMath.roll_crit(player.stats, RunState.rng)
		var dmg := base * (weapon.crit_mult if crit else 1.0)
		Vfx.hit_spark(e.global_position + Vector3.UP * 0.6, _slash_color())
		apply_hit(player, e, dmg, crit, dir * weapon.knockback, weapon.stun_chance, weapon.stun_duration)


func _shoot(origin: Vector3, dir: Vector3) -> void:
	var parent := effects_parent(player)
	if parent == null:
		return
	var crit := CombatMath.roll_crit(player.stats, RunState.rng)
	var dmg := CombatMath.weapon_hit_damage(weapon, player.stats) * (weapon.crit_mult if crit else 1.0)
	var style := projectile_style(weapon)
	var proj := Projectile.create(Projectile.TEAM_PLAYERS, dmg, crit, dir, weapon.projectile_speed,
			weapon.attack_range + PROJECTILE_EXTRA_RANGE, weapon.pierce, weapon.aoe_radius, player,
			style, _projectile_color(style))
	proj.knockback = weapon.knockback
	proj.stun_chance = weapon.stun_chance
	proj.stun_duration = weapon.stun_duration
	parent.add_child(proj)
	proj.global_position = origin + Vector3.UP * Player.CHEST_HEIGHT + dir * (Player.RADIUS + 0.15)


## Aims a little ahead of a moving target.
func _lead_direction(origin: Vector3, target: Enemy, fallback: Vector3) -> Vector3:
	if weapon.projectile_speed <= 0.0:
		return fallback
	var to := flat(target.global_position - origin)
	var t := to.length() / weapon.projectile_speed
	var aim := to + flat(target.velocity) * t * PROJECTILE_LEAD
	return aim.normalized() if aim.length_squared() > 0.000001 else fallback


func _slash_color() -> Color:
	var c := weapon.color.lightened(0.3)
	if player.slot != null:
		c = c.lerp(player.slot.color, 0.35)
	return c


func _projectile_color(style: StringName) -> Color:
	# Magic bolts take the class accent colour (arcane blue, fel green ...) when it is bright.
	if style == &"bolt" or style == &"fireball":
		var cd := player.class_data
		if cd != null and cd.accent_color.get_luminance() > 0.3:
			return cd.accent_color.lightened(0.25)
	return Projectile.default_color(style)


# --- Shared static helpers (also used by Projectile) ------------------------------

static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Projectile look for a weapon type.
static func projectile_style(w: WeaponData) -> StringName:
	match w.weapon_type:
		&"wand":
			return &"bolt"
		&"staff":
			return &"fireball"
		&"bow":
			return &"arrow"
		&"gun":
			return &"bullet"
	return &"bolt"


## Nearest living Enemy among [param nodes] whose centre is within [param max_range] (XZ).
static func nearest_enemy(nodes: Array[Node], origin: Vector3, max_range: float) -> Enemy:
	var best: Enemy = null
	var best_d := max_range * max_range
	for node in nodes:
		var e := node as Enemy
		if e == null or not e.is_inside_tree():
			continue
		# Distance first (cheap), the script call is_dead() only for closer candidates.
		var pos := e.global_position
		var dx := pos.x - origin.x
		var dz := pos.z - origin.z
		var d := dx * dx + dz * dz
		if d > best_d or (d == best_d and best != null):
			continue
		if e.is_dead():
			continue
		best_d = d
		best = e
	return best


## Every living Enemy within [param reach] + its radius and inside the [param arc_degrees]
## cone around [param direction] (the enemy's own width counts towards the cone).
static func enemies_in_arc(nodes: Array[Node], origin: Vector3, direction: Vector3, reach: float,
		arc_degrees: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var fwd := flat(direction)
	if fwd.length_squared() < 0.000001:
		return out
	fwd = fwd.normalized()
	var half := deg_to_rad(arc_degrees) * 0.5
	for node in nodes:
		var e := node as Enemy
		if e == null or not e.is_inside_tree() or e.is_dead():
			continue
		var to := flat(e.global_position - origin)
		var dist := to.length()
		if dist > reach + e.radius:
			continue
		if dist > e.radius:
			var pad := asin(clampf(e.radius / dist, 0.0, 1.0))
			if fwd.angle_to(to) > half + pad:
				continue
		out.append(e)
	return out


## One weapon hit of [param attacker] (may be null) on [param enemy]: records the damage
## (only what the enemy had left – overkill does not count), applies it (kill credit goes
## through the attacker), rolls the stun, shows the damage number and triggers the
## attacker's on-hit effects (leech).
static func apply_hit(attacker: Player, enemy: Enemy, damage: float, is_crit: bool, knockback: Vector3,
		stun_chance: float = 0.0, stun_duration: float = 0.5) -> void:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_dead():
		return
	var valid_attacker: Player = attacker if attacker != null and is_instance_valid(attacker) else null
	var text_pos := enemy.global_position + Vector3.UP * DAMAGE_TEXT_HEIGHT
	if valid_attacker != null and valid_attacker.slot != null:
		RunState.record_damage(valid_attacker.slot.index, minf(damage, maxf(0.0, enemy.hp)))
	enemy.take_damage(damage, is_crit, valid_attacker, knockback)
	if stun_chance > 0.0 and is_instance_valid(enemy) and not enemy.is_dead() \
			and RunState.rng.randf() < stun_chance:
		enemy.apply_stun(stun_duration)
	show_damage_number(text_pos, damage, is_crit, enemy)
	if valid_attacker != null:
		valid_attacker.on_hit_dealt(damage, enemy)


## White number for normal hits, bigger yellow one for crits. Hits on the same
## [param target] in quick succession merge into one number (see Vfx.damage_number).
static func show_damage_number(pos: Vector3, damage: float, is_crit: bool, target: Object = null) -> void:
	if is_crit:
		Vfx.damage_number(target, pos, damage, CRIT_TEXT_COLOR, CRIT_TEXT_SIZE)
	else:
		Vfx.damage_number(target, pos, damage, NORMAL_TEXT_COLOR, NORMAL_TEXT_SIZE)


## Where spawned projectiles go: the arena's entity root, else next to [param near].
static func effects_parent(near: Node) -> Node:
	var arena := Arena.current
	if arena != null and is_instance_valid(arena.entities) and arena.entities.is_inside_tree():
		return arena.entities
	if near != null and near.is_inside_tree():
		return near.get_parent()
	return null
