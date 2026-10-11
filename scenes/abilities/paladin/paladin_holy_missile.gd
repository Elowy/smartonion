class_name PaladinHolyMissile
extends Projectile
## A thrown holy weapon of the Paladin – the hammer of Hammer of Justice, the shield of
## Avenger's Shield. A regular player [Projectile] (swept hits, EnemyGrid, arena bounds) whose
## hits are ABILITY damage: ProcSystem.deal_raw(..., &"holy", true, &"ability") on the Paladin
## (kill credit, damage meter, Executioner / Slayer, Mastery and outgoing multipliers; no weapon
## procs, crits, leech or knockback), then per enemy struck: [member stun], [member slow_pct],
## an absorb shield for the Paladin ([member absorb_per_hit]).
##
## It homes in on [member homing_target] while that one lives. [member aoe_radius] > 0 makes
## the impact burst (every enemy around takes the hit, Projectile._explode); with
## [member pierce] > 0 a hit ricochets to the nearest enemy it has not hit yet within
## [member ricochet_range] (and homes in on it); without one the missile ends.

enum Look { HAMMER, SHIELD }

const RICOCHET_RANGE := 6.0
## Flight height (chest high, like the weapon projectiles).
const HEIGHT := 0.7

var look := Look.HAMMER
var stun := 0.0
var slow_pct := 0.0
var slow_duration := 0.0
var absorb_per_hit := 0.0
var absorb_duration := 6.0
## Bonus damage (+%) against enemies below [member execute_below] (0..1) of their HP.
var execute_bonus := 0.0
var execute_below := 0.0
## Called with no arguments when a hit of this missile kills its enemy.
var on_kill := Callable()
var ricochet_range := RICOCHET_RANGE
var homing_target: Enemy
## Instance ids of the enemies damaged, in order (tests).
var victim_ids: Array[int] = []

var _turned_at: Variant = null


## Throws a missile for [param paladin] from its chest along [param dir] (homing in on
## [param target] when given): [param p_damage] holy damage per enemy, [param targets] enemies
## in a row (ricochets), [param p_range] metres of flight before the first hit. Added under the
## arena's entities (or next to the Paladin). Null when the Paladin is not in the tree.
static func throw(paladin: Player, target: Enemy, dir: Vector3, p_damage: float, targets: int,
		p_range: float, p_speed: float, p_look: Look) -> PaladinHolyMissile:
	if paladin == null or not paladin.is_inside_tree():
		return null
	var m := PaladinHolyMissile.new()
	m.name = "HammerOfJustice" if p_look == Look.HAMMER else "AvengersShield"
	m.team = TEAM_PLAYERS
	m.damage = p_damage
	m.look = p_look
	var d := Vector3(dir.x, 0.0, dir.z)
	if target != null and is_instance_valid(target):
		var to := WeaponRunner.flat(target.global_position - paladin.global_position)
		if to.length_squared() > 0.0001:
			d = to
	m.direction = d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD
	m.speed = maxf(0.0, p_speed)
	m.max_range = maxf(0.0, p_range)
	m.pierce = maxi(0, targets - 1)
	m._pierce_left = m.pierce
	m.attacker = paladin
	m.homing_target = target
	m.color = PaladinKit.HOLY_COLOR
	m.knockback = 0.0
	m.add_to_group(&"projectiles")
	m._build_visual()
	var parent := WeaponRunner.effects_parent(paladin)
	if parent == null:
		m.free()
		return null
	parent.add_child(m)
	m.global_position = paladin.global_position + Vector3.UP * HEIGHT + m.direction * (Player.RADIUS + 0.1)
	return m


## Projectile.advance with homing, and a ricochet during the sweep keeps its new start point
## (the struck enemy) instead of being moved to the end of the old segment.
func advance(delta: float) -> void:
	_home()
	_turned_at = null
	super.advance(delta)
	if _turned_at != null and not is_done() and is_inside_tree():
		global_position = _turned_at
	_turned_at = null


func _home() -> void:
	if homing_target == null:
		return
	if not is_instance_valid(homing_target) or not homing_target.is_inside_tree() or homing_target.is_dead() \
			or _hit_ids.has(homing_target.get_instance_id()):
		homing_target = null
		return
	var to := WeaponRunner.flat(homing_target.global_position - global_position)
	if to.length_squared() < 0.0004:
		return
	direction = to.normalized()
	# Chasing a moving enemy may need a little more than the planned flight.
	max_range = maxf(max_range, travelled + to.length() + 0.5)
	if _visual != null:
		_visual.basis = Basis.looking_at(direction, Vector3.UP)


## Replaces the weapon hit of Projectile: holy ability damage through the Paladin's procs.
func _apply_hit(body: Node3D, _kb_dir: Vector3, from_explosion: bool) -> void:
	hit_count += 1
	var e := body as Enemy
	var paladin := attacker as Player if attacker != null and is_instance_valid(attacker) else null
	if e == null or paladin == null or paladin.procs == null:
		return
	victim_ids.append(e.get_instance_id())
	var amount := damage
	if execute_bonus > 0.0 and e.max_hp > 0.0 and e.hp / e.max_hp < execute_below:
		amount *= 1.0 + execute_bonus / 100.0
	paladin.procs.deal_raw(e, amount, PaladinKit.SCHOOL, true, &"ability")
	if is_instance_valid(e) and not e.is_dead():
		if stun > 0.0:
			e.apply_stun(stun)
		if slow_pct > 0.0:
			e.apply_slow(slow_pct, slow_duration)
	elif on_kill.is_valid():
		on_kill.call()
	if absorb_per_hit > 0.0 and paladin.is_alive():
		paladin.procs.add_shield(absorb_per_hit, absorb_duration)
	if not from_explosion and _pierce_left > 0 and is_instance_valid(e):
		_ricochet(e)


## Turns towards the nearest enemy not hit yet (homing in on it); ends when there is none.
func _ricochet(from_enemy: Enemy) -> void:
	if not is_inside_tree() or not from_enemy.is_inside_tree():
		return
	var center := from_enemy.global_position
	var best: Enemy = null
	var best_d := ricochet_range * ricochet_range
	for node in EnemyGrid.gather_around(get_tree(), center, ricochet_range):
		var e := node as Enemy
		if e == null or e == from_enemy or not e.is_inside_tree() or e.is_dead():
			continue
		if _hit_ids.has(e.get_instance_id()):
			continue
		var d := WeaponRunner.flat(e.global_position - center).length_squared()
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		_finish()
		return
	var to := WeaponRunner.flat(best.global_position - center)
	if to.length_squared() < 0.0001:
		to = direction
	direction = to.normalized()
	homing_target = best
	global_position = Vector3(center.x, global_position.y, center.z)
	max_range = travelled + ricochet_range + 1.0
	_turned_at = global_position
	if _visual != null:
		_visual.basis = Basis.looking_at(direction, Vector3.UP)


func _build_visual() -> void:
	_visual = PaladinVfx.shield_look() if look == Look.SHIELD else PaladinVfx.hammer_look()
	_visual.name = "Visual"
	_visual.basis = Basis.looking_at(direction, Vector3.UP)
	add_child(_visual)
	_spinner = _visual.find_child("Spinner", true, false) as Node3D
	set_process(_spinner != null)
