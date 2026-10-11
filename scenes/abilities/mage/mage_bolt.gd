class_name MageBolt
extends Projectile
## A Mage spell in flight (Fireball, Pyroblast, Arcane Missiles): a regular player
## [Projectile] (flight, swept hits over [EnemyGrid], arena bounds) whose hits are SPELL
## damage – ProcSystem.deal_raw(..., &"ability") of its caster (kill credit, damage meter,
## Mastery multipliers; no weapon on-hit procs, leech, crits, knockback or resource gains).
## Options, set right after [method fire]:
##   burn_pct / burn_duration – every enemy it damages burns ([MageBurn]) for that share,
##   splash_radius / splash_pct – each hit bursts: the other enemies around take that share,
##   bounces ([method set_bounces]) – after a hit it turns to the nearest enemy it has not hit
##     within [constant BOUNCE_RANGE] m, its damage x [member bounce_mult] per bounce,
##   pierce ([method set_pierce]) – flies on through that many enemies,
##   homing – [member turn_rate] > 0 steers it towards [member home_target] (the turn gets
##     sharper with age so it never orbits); a dead target hands over to the nearest enemy
##     it has not hit within [constant RETARGET_RANGE] m.

const BOUNCE_RANGE := 6.0
const RETARGET_RANGE := 6.0
## The turn rate grows by this share per second of flight.
const TURN_GROWTH := 3.0

var school: StringName = &"fire"
var burn_pct := 0.0
var burn_duration := 3.0
var splash_radius := 0.0
var splash_pct := 50.0
var bounce_mult := 0.75
var bounces_left := 0
var home_target: Enemy
## Radians per second (0 = flies straight).
var turn_rate := 0.0
var age := 0.0
## Instance ids of the enemies this bolt damaged, in order (tests).
var victim_ids: Array[int] = []
## Total damage dealt (after the caster's multipliers; tests, meters).
var dealt := 0.0

## Where the last bounce put the bolt (null = none this step): Projectile.advance would move
## it to the end of the old segment after the sweep, see [method advance].
var _turned_at: Variant = null


## Fires a bolt from [param from] (world; its height is kept) along [param dir] for
## [param caster], added under the arena's entities (or next to the caster).
## [param p_style]: a [ProjectileVisual] style; [param p_scale] scales the whole look.
static func fire(caster: Player, from: Vector3, dir: Vector3, p_damage: float, p_school: StringName,
		p_speed: float, p_range: float, p_style: StringName, p_color: Color, p_scale: float = 1.0) -> MageBolt:
	var b := MageBolt.new()
	b.name = "MageBolt"
	b.team = TEAM_PLAYERS
	b.damage = p_damage
	b.school = p_school
	var d := Vector3(dir.x, 0.0, dir.z)
	b.direction = d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD
	b.speed = maxf(0.0, p_speed)
	b.max_range = maxf(0.0, p_range)
	b.attacker = caster
	b.style = p_style
	b.color = p_color
	b.knockback = 0.0
	b.add_to_group(&"projectiles")
	b._build_visual()
	b.scale = Vector3.ONE * maxf(0.1, p_scale)
	b.add_child(MageFx.trail(p_color, p_scale))
	var parent := WeaponRunner.effects_parent(caster)
	if parent != null:
		parent.add_child(b)
		b.global_position = from
	return b


## After a hit the bolt jumps on [param n] more times.
func set_bounces(n: int) -> void:
	bounces_left = maxi(0, n)
	pierce = bounces_left
	_pierce_left = bounces_left


## The bolt passes through [param n] enemies.
func set_pierce(n: int) -> void:
	pierce = maxi(0, n)
	_pierce_left = pierce


## Steers towards [param target] at [param rate] rad/s.
func home_on(target: Enemy, rate: float) -> void:
	home_target = target
	turn_rate = maxf(0.0, rate)


func advance(delta: float) -> void:
	age += delta
	_turned_at = null
	if turn_rate > 0.0 and not is_done():
		_steer(delta)
	super.advance(delta)
	if _turned_at != null and not is_done() and is_inside_tree():
		global_position = _turned_at
	_turned_at = null


## Replaces the weapon hit of Projectile: spell damage (+ burn, splash, bounce).
func _apply_hit(body: Node3D, _kb_dir: Vector3, _from_explosion: bool) -> void:
	hit_count += 1
	var e := body as Enemy
	var caster := attacker as Player if attacker != null and is_instance_valid(attacker) else null
	if e == null or caster == null or caster.procs == null:
		return
	var center := e.global_position
	_strike(caster, e, damage)
	if splash_radius > 0.0:
		_splash(caster, e, center)
	if bounces_left > 0:
		bounces_left -= 1
		damage *= bounce_mult
		_bounce(e, center)


func _strike(caster: Player, e: Enemy, amount: float) -> void:
	victim_ids.append(e.get_instance_id())
	dealt += caster.procs.deal_raw(e, amount, school, true, &"ability")
	if burn_pct > 0.0:
		MageBurn.apply(e, caster, amount * burn_pct / 100.0, burn_duration, school)


func _splash(caster: Player, hit: Enemy, center: Vector3) -> void:
	if not is_inside_tree():
		return
	var others := MageSpell.enemies_in(get_tree(), center, splash_radius)
	for e in others:
		if e == hit or _hit_ids.has(e.get_instance_id()) or not MageSpell.is_live(e):
			continue
		_hit_ids[e.get_instance_id()] = true
		_strike(caster, e, damage * splash_pct / 100.0)
	Vfx.explosion(Vector3(center.x, global_position.y * 0.5, center.z), splash_radius, color)


## Turns towards the nearest enemy this bolt has not hit yet (flies on when there is none).
func _bounce(from_enemy: Enemy, center: Vector3) -> void:
	if not is_inside_tree():
		return
	var best := _next_target(center, BOUNCE_RANGE, from_enemy)
	if best == null:
		return
	var to := WeaponRunner.flat(best.global_position - center)
	if to.length_squared() < 0.0001:
		return
	direction = to.normalized()
	global_position = Vector3(center.x, global_position.y, center.z)
	max_range = travelled + BOUNCE_RANGE + 2.0
	_turned_at = global_position
	if turn_rate > 0.0:
		home_target = best
		age = 0.0
	_face()


func _steer(delta: float) -> void:
	if not is_inside_tree():
		return
	var here := global_position
	if not MageSpell.is_live(home_target) or _hit_ids.has(home_target.get_instance_id()):
		home_target = _next_target(here, RETARGET_RANGE, null)
		if home_target == null:
			return
	var want := WeaponRunner.flat(home_target.global_position - here)
	if want.length_squared() < 0.0001:
		return
	var angle := direction.signed_angle_to(want.normalized(), Vector3.UP)
	var max_turn := turn_rate * (1.0 + age * TURN_GROWTH) * delta
	direction = direction.rotated(Vector3.UP, clampf(angle, -max_turn, max_turn))
	direction = Vector3(direction.x, 0.0, direction.z).normalized()
	_face()


## The nearest living enemy within [param reach] of [param center] that this bolt has not
## hit ([param skip] excluded).
func _next_target(center: Vector3, reach: float, skip: Enemy) -> Enemy:
	var best: Enemy = null
	var best_d := reach * reach
	for e in MageSpell.enemies_in(get_tree(), center, reach, false):
		if e == skip or _hit_ids.has(e.get_instance_id()):
			continue
		var d := WeaponRunner.flat(e.global_position - center).length_squared()
		if d < best_d:
			best_d = d
			best = e
	return best


## Replaces the weapon-projectile look with the Mage's spell look ([method MageFx.bolt_look]).
func _build_visual() -> void:
	_visual = MageFx.bolt_look(color)
	_visual.name = "Visual"
	_visual.basis = Basis.looking_at(direction, Vector3.UP)
	add_child(_visual)
	set_process(false)


func _face() -> void:
	if _visual != null and direction.length_squared() > 0.0001:
		_visual.basis = Basis.looking_at(direction, Vector3.UP)
