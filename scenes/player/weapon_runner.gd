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
## Targets and melee arcs come from the shared [EnemyGrid] (only the enemies near the player
## are looked at). While nothing is in range the runner looks again every NO_TARGET_RETRY
## seconds – or at once when the number of enemies changes.
##
## Exotic stats (GDD 2.4.1): Extra Attack (% chance an attack strikes again at once; extra
## attacks never roll it again), Critical Damage (crit multiplier), Extra Projectile (a fan of
## FAN_STEP_DEGREES), Pierce, Area Size (explosion radius); Attack / Spell Power and school %
## are in [method CombatMath.weapon_hit_damage], Executioner / Slayer in [method apply_hit].
## Procs (Galeforce) add extra attacks through [method extra_attack].
## On-hit procs roll once per attack, not once per enemy hit: a melee arc rolls them on the
## attacked target (else the first enemy it hits), a projectile attack on the first hit of
## any of its projectiles (fan, pierce and explosions share one [ProcGate]); Executioner /
## Slayer, leech, stuns and damage stay per target.
## Crits (M5): a banked forced crit first (Player.consume_forced_crit), then a talent / set
## script that forces one (PlayerBonuses.crit_forced, [method _bonus_crit]), then the roll.

## Fraction of the cooldown the off hand waits at wave start / after idling.
const OFF_HAND_PHASE := 0.5
## Seconds between two target searches while no enemy is in range (a new or removed enemy
## triggers a search at once).
const NO_TARGET_RETRY := 0.1
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
## Angle (degrees) between the projectiles of an Extra Projectile fan.
const FAN_STEP_DEGREES := 10.0
## Safety cap of extra attacks resolved after one attack.
const MAX_EXTRA_ATTACKS := 8


## One attack's on-hit proc roll, shared by everything the attack hits: only the first hit
## rolls on-hit procs.
class ProcGate extends RefCounted:
	var open := true

	## True for the first hit of the attack, false afterwards.
	func take() -> bool:
		var was := open
		open = false
		return was

var weapon: WeaponData
var player: Player
var is_off_hand := false
## Seconds until the weapon may attack again (<= 0 = ready).
var cooldown_left := 0.0

var _waiting_for_target := false
## Seconds until the next target search while waiting for a target.
var _retry_left := 0.0
## Enemies in the tree at the last failed search (-1 = none yet).
var _retry_enemy_count := -1
## True while an attack resolves (extra attacks requested meanwhile wait for its end).
var _attacking := false
## Extra attacks waiting for the current attack to finish.
var _pending_extra := 0


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
	_retry_left = 0.0
	_retry_enemy_count = -1
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
	if _waiting_for_target:
		# Nothing was in range: search again only every NO_TARGET_RETRY s (or at once when
		# enemies came or went), not every tick.
		_retry_left -= delta
		if _retry_left > 0.0 and _enemy_count() == _retry_enemy_count:
			cooldown_left = 0.0
			return false
	var target := find_target()
	if target == null:
		cooldown_left = 0.0
		_waiting_for_target = true
		_retry_left = NO_TARGET_RETRY
		_retry_enemy_count = _enemy_count()
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


## Nearest living enemy within the weapon's attack range (null if none) – the same result as
## [method nearest_enemy] over the whole group, found through the shared [EnemyGrid]. A bot
## (smoke / demo) shoots a priority target in reach first (the Cultist Acolyte, M6:
## [method BotInput.priority_enemy]); humans aim at the nearest as always.
func find_target() -> Enemy:
	if weapon == null or player == null or not player.is_inside_tree():
		return null
	if player.slot != null and player.slot.input is BotInput:
		var priority := BotInput.priority_enemy(player.get_tree(), player.global_position, weapon.attack_range)
		if priority != null:
			return priority
	return EnemyGrid.nearest(player.get_tree(), player.global_position, weapon.attack_range)


func _enemy_count() -> int:
	return player.get_tree().get_node_count_in_group(&"enemies") if player.is_inside_tree() else 0


## Attacks [param target] right now (no cooldown check). A normal attack may strike again at
## once (Extra Attack stat); [param is_extra] marks an extra attack, whose hits can never
## trigger further extra attacks (stat or proc).
func attack(target: Enemy, is_extra: bool = false) -> void:
	if weapon == null or player == null or not player.is_inside_tree():
		return
	var outer := _attacking
	_attacking = true
	_strike(target, is_extra)
	_attacking = outer
	if not is_extra and player.stats.get_raw(Stats.EXTRA_ATTACK) > 0.0 \
			and CombatMath.roll_extra_attack(player.stats, RunState.rng):
		_pending_extra += 1
	if not outer:
		_flush_extra(target)


## [param count] extra attacks (procs such as Galeforce): right after the attack that is
## resolving now, else at once – at [param target] while it lives, else the nearest enemy.
func extra_attack(count: int, target: Enemy = null) -> void:
	if count <= 0 or weapon == null or not weapon.attacks():
		return
	_pending_extra += count
	if not _attacking:
		_flush_extra(target)


## Parry riposte: one instant hit of this weapon on [param target] (no range check – it just
## attacked in melee). A weapon hit (on-hit procs), but like an extra attack it never leads to
## further extra attacks.
func riposte(target: Enemy) -> void:
	if weapon == null or player == null or not player.is_inside_tree() or target == null \
			or not is_instance_valid(target) or target.is_dead():
		return
	var dir := flat(target.global_position - player.global_position)
	dir = dir.normalized() if dir.length_squared() > 0.000001 else player.facing
	var crit := player.consume_forced_crit() or _bonus_crit(target) \
			or CombatMath.roll_crit(player.stats, RunState.rng)
	var dmg := CombatMath.weapon_hit_damage(weapon, player.stats) \
			* (CombatMath.crit_multiplier(weapon, player.stats) if crit else 1.0)
	Vfx.slash_arc(player.global_position + Vector3.UP * 0.3, dir, 1.4, 70.0, _slash_color())
	Audio.play(AudioIds.swing(weapon))
	Vfx.hit_spark(target.global_position + Vector3.UP * 0.6, _slash_color())
	player.face_attack(dir)
	apply_hit(player, target, dmg, crit, dir * weapon.knockback, weapon.stun_chance,
			weapon.stun_duration, weapon, true)


func _flush_extra(target: Enemy) -> void:
	var done := 0
	while _pending_extra > 0 and done < MAX_EXTRA_ATTACKS:
		_pending_extra -= 1
		done += 1
		if player == null or not player.is_alive() or not player.is_inside_tree():
			break
		var t: Enemy = target if _is_live(target) else find_target()
		if t == null:
			break
		_attacking = true
		_strike(t, true)
		_attacking = false
	_pending_extra = 0


static func _is_live(e: Variant) -> bool:
	if not is_instance_valid(e):
		return false
	var enemy := e as Enemy
	return enemy != null and enemy.is_inside_tree() and not enemy.is_dead()


func _strike(target: Enemy, is_extra: bool) -> void:
	if target == null or not is_instance_valid(target):
		return
	var origin := player.global_position
	var dir := flat(target.global_position - origin)
	dir = dir.normalized() if dir.length_squared() > 0.000001 else player.facing
	match weapon.attack_kind:
		WeaponData.AttackKind.MELEE_ARC:
			_melee(origin, dir, is_extra, target)
		WeaponData.AttackKind.PROJECTILE:
			dir = _lead_direction(origin, target, dir)
			_shoot(origin, dir, is_extra, target)
		_:
			return
	player.face_attack(dir)
	if player.model != null:
		player.model.play_attack(is_off_hand)


## Hits every enemy in the arc; [param target] (the attacked enemy) is hit first and rolls
## the on-hit procs of this attack (the first enemy hit does when it is not in the arc).
func _melee(origin: Vector3, dir: Vector3, is_extra: bool = false, target: Enemy = null) -> void:
	var base := CombatMath.weapon_hit_damage(weapon, player.stats)
	var crit_mult := CombatMath.crit_multiplier(weapon, player.stats)
	# Only the enemies the grid finds within reach (+ their radius) – same hits, same order.
	var nodes := EnemyGrid.gather_around(player.get_tree(), origin, weapon.attack_range)
	var hits := enemies_in_arc(nodes, origin, dir, weapon.attack_range, weapon.arc_degrees)
	var at := hits.find(target) if target != null else -1
	if at > 0:
		hits.remove_at(at)
		hits.push_front(target)
	Vfx.slash_arc(origin + Vector3.UP * 0.3, dir, weapon.attack_range, weapon.arc_degrees, _slash_color())
	Audio.play(AudioIds.swing(weapon))
	var gate := ProcGate.new()
	for e in hits:
		if not is_instance_valid(e) or e.is_dead():
			continue
		var crit := player.consume_forced_crit() or _bonus_crit(e) \
				or CombatMath.roll_crit(player.stats, RunState.rng)
		var dmg := base * (crit_mult if crit else 1.0)
		Vfx.hit_spark(e.global_position + Vector3.UP * 0.6, _slash_color())
		apply_hit(player, e, dmg, crit, dir * weapon.knockback, weapon.stun_chance, weapon.stun_duration,
				weapon, is_extra, gate.take())


## Fires the weapon's projectile(s): 1 + Extra Projectile in a fan, with the extra Pierce and
## the Area Size of the player. [param target] (the aimed enemy) is what talent crit checks
## look at – a projectile may still hit another enemy.
func _shoot(origin: Vector3, dir: Vector3, is_extra: bool = false, target: Enemy = null) -> void:
	var parent := effects_parent(player)
	if parent == null:
		return
	var stats := player.stats
	var count := 1 + CombatMath.extra_projectiles(stats)
	var pierce := weapon.pierce + CombatMath.extra_pierce(stats)
	var radius := weapon.aoe_radius * CombatMath.area_mult(stats) if weapon.aoe_radius > 0.0 else 0.0
	var crit_mult := CombatMath.crit_multiplier(weapon, stats)
	var style := projectile_style(weapon)
	var color := _projectile_color(style)
	Audio.play(AudioIds.shot(weapon))
	var gate := ProcGate.new()
	for i in count:
		var shot := dir
		if count > 1:
			shot = dir.rotated(Vector3.UP, deg_to_rad(FAN_STEP_DEGREES * (float(i) - float(count - 1) * 0.5)))
		var crit := player.consume_forced_crit() or _bonus_crit(target) \
				or CombatMath.roll_crit(stats, RunState.rng)
		var dmg := CombatMath.weapon_hit_damage(weapon, stats) * (crit_mult if crit else 1.0)
		var proj := Projectile.create(Projectile.TEAM_PLAYERS, dmg, crit, shot, weapon.projectile_speed,
				weapon.attack_range + PROJECTILE_EXTRA_RANGE, pierce, radius, player, style, color)
		proj.knockback = weapon.knockback
		proj.stun_chance = weapon.stun_chance
		proj.stun_duration = weapon.stun_duration
		proj.weapon = weapon
		proj.is_extra = is_extra
		proj.proc_gate = gate
		parent.add_child(proj)
		proj.global_position = origin + Vector3.UP * Player.CHEST_HEIGHT + shot * (Player.RADIUS + 0.15)


## A talent / set script forces this crit (PlayerBonuses.crit_forced; [param target] may be
## null). Asked after consume_forced_crit() and before the crit roll – the order is intended:
## a banked forced crit (Vanish, Find Weakness) is used first, so inside Shadow Dance it is not
## wasted (judge B15). No rng draw when it says true; the roll is unchanged when it says false.
func _bonus_crit(target: Enemy) -> bool:
	return player.bonuses != null and player.bonuses.crit_forced(target)


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


## One weapon hit of [param attacker] (may be null) on [param enemy]: the attacker's
## Executioner / Slayer bonus against this target, records the damage (only what the enemy
## had left – overkill does not count), applies it (kill credit goes through the attacker),
## rolls the stun, shows the damage number and triggers the attacker's on-hit effects (leech,
## procs – [param weapon], [param is_extra] and [param roll_procs] (false for the further
## hits of one attack: on-hit procs roll once per attack) are passed on, see
## Player.on_hit_dealt). The incoming [param damage] (crit included) is the hit's base amount,
## passed on as well: damage derived from the hit starts from it (architecture §2.1).
static func apply_hit(attacker: Player, enemy: Enemy, damage: float, is_crit: bool, knockback: Vector3,
		stun_chance: float = 0.0, stun_duration: float = 0.5, weapon: WeaponData = null,
		is_extra: bool = false, roll_procs: bool = true) -> void:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_dead():
		return
	var base := damage
	var valid_attacker: Player = attacker if attacker != null and is_instance_valid(attacker) else null
	if valid_attacker != null:
		var ratio := enemy.hp / enemy.max_hp if enemy.max_hp > 0.0 else 1.0
		damage *= CombatMath.target_damage_mult(valid_attacker.stats, ratio, enemy.is_elite())
		damage *= valid_attacker.outgoing_damage_mult(enemy, weapon.school if weapon != null else &"physical", &"weapon")
	var text_pos := enemy.global_position + Vector3.UP * DAMAGE_TEXT_HEIGHT
	Audio.play(&"hit_crit" if is_crit else &"hit")
	if valid_attacker != null and valid_attacker.slot != null:
		RunState.record_damage(valid_attacker.slot.index, minf(damage, maxf(0.0, enemy.hp)), enemy.is_boss())
	enemy.take_damage(damage, is_crit, valid_attacker, knockback)
	if stun_chance > 0.0 and is_instance_valid(enemy) and not enemy.is_dead() \
			and RunState.rng.randf() < stun_chance:
		enemy.apply_stun(stun_duration)
	show_damage_number(text_pos, damage, is_crit, enemy)
	if valid_attacker != null and is_instance_valid(valid_attacker):
		valid_attacker.on_hit_dealt(damage, enemy, weapon, is_crit, is_extra, roll_procs, base)


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
