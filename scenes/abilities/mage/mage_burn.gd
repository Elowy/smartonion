class_name MageBurn
extends Node3D
## A burn left by a Mage spell (Fireball, Pyroblast): [member rate] x [member left] Fire
## damage still to come, dealt every [constant TICK] seconds through the caster's
## ProcSystem.deal_raw(..., &"dot") (kill credit, damage meter, Mastery multipliers; no
## crits, no on-hit procs). Child of the burning enemy – freed with it – with a few flames
## on its body. A new burn from the same Mage adds its damage to what is still burning and
## restarts the clock (one burn per caster per enemy). Keeps burning while the caster is
## downed, like Ignite; ends when the caster is freed.
##
## Living Bomb (M5 Fire modifier, talents_mage.md 4.3): [method arm_bomb] (a Fireball hit with
## the talent) arms the burn – one bomb per burn, a new arming keeps the bigger damage /
## radius, and burns that merge into it later (Pyroblast, Combustion, more Fireballs) keep it
## armed. It explodes once ([member exploded]): when the burn runs out with the enemy alive
## (the enemy is hit too) or when the enemy dies while burning (Enemy.died, connected one-shot
## when armed – the corpse already left the enemies group, so only its neighbours are hit):
## [member bomb_damage] Fire damage to every enemy within [member bomb_radius] through the
## caster's ProcSystem.deal_raw(..., &"ability"). No explosion when the caster is freed or the
## enemy despawns (wave end never emits died); explosions start no burns (no chain bombs).

const TICK := 0.5
const EPSILON := 0.0001
const FLAME_HIGH := Color(1.0, 0.78, 0.25, 0.95)
const FLAME_LOW := Color(0.95, 0.25, 0.04, 0.0)
const EMBER_COLOR := Color(1.0, 0.85, 0.4)
const EMBER_PULSE := 9.0

var caster: Player
var enemy: Enemy
var school: StringName = &"fire"
## Damage per second still to come and seconds left.
var rate := 0.0
var left := 0.0
## Damage dealt so far (tests).
var dealt := 0.0
var ticks := 0
## Living Bomb: explosion damage per enemy (0 = not armed) and radius (m, Area Size applied).
var bomb_damage := 0.0
var bomb_radius := 0.0
## The bomb went off (tests: it fires once) and the enemies it damaged.
var exploded := false
var bomb_hits := 0

var _tick_left := TICK
var _owed := 0.0
var _ember: MeshInstance3D
var _age := 0.0


## Sets [param e] burning for [param total] damage over [param duration] seconds (added to
## a running burn of the same [param p_caster]). Null when nothing burns.
static func apply(e: Enemy, p_caster: Player, total: float, duration: float,
		p_school: StringName = &"fire") -> MageBurn:
	if not MageSpell.is_live(e) or p_caster == null or total <= 0.0 or duration <= 0.0:
		return null
	var burn := find(e, p_caster)
	if burn != null:
		total += burn.remaining()
		burn._owed = 0.0
	else:
		burn = MageBurn.new()
		burn.name = _key(p_caster)
		burn.caster = p_caster
		burn.enemy = e
		e.add_child(burn)
		burn.position = Vector3.UP * Enemy.BODY_CENTER_HEIGHT
		burn._build_flames(e.radius)
	burn.school = p_school
	burn.left = duration
	burn.rate = total / duration
	return burn


## The running burn of [param p_caster] on [param e] (null = none).
static func find(e: Enemy, p_caster: Player) -> MageBurn:
	if not is_instance_valid(e) or p_caster == null:
		return null
	var burn := e.get_node_or_null(NodePath(_key(p_caster))) as MageBurn
	if burn == null or burn.is_queued_for_deletion() or burn.left <= EPSILON:
		return null
	return burn


## Damage still to come (incl. what burnt since the last tick).
func remaining() -> float:
	return rate * maxf(0.0, left) + _owed


## True while a Living Bomb waits on this burn.
func is_armed() -> bool:
	return bomb_damage > 0.0 and not exploded


## Arms this burn as a Living Bomb for [param damage] per enemy within [param radius] m (the
## bigger of the old and new numbers; the enemy's death is watched once).
func arm_bomb(damage: float, radius: float) -> void:
	if damage <= 0.0 or exploded or is_queued_for_deletion() or not MageSpell.is_live(enemy):
		return
	bomb_damage = maxf(bomb_damage, damage)
	bomb_radius = maxf(bomb_radius, radius)
	if not enemy.died.is_connected(_on_enemy_died):
		enemy.died.connect(_on_enemy_died, CONNECT_ONE_SHOT)
	if _ember == null:
		_build_ember()


func _physics_process(delta: float) -> void:
	if is_queued_for_deletion():
		return
	if not MageSpell.is_live(enemy) or not is_instance_valid(caster):
		_end()
		return
	if _ember != null:
		_age += delta
		_ember.scale = Vector3.ONE * (0.85 + 0.25 * sin(_age * EMBER_PULSE))
	_owed += rate * clampf(left, 0.0, delta)
	left -= delta
	_tick_left -= delta
	if _tick_left > EPSILON and left > EPSILON:
		return
	_tick_left += TICK
	var amount := _owed
	_owed = 0.0
	if amount > 0.0 and caster.procs != null:
		ticks += 1
		dealt += caster.procs.deal_raw(enemy, amount, school, true, &"dot")
	if left <= EPSILON and MageSpell.is_live(enemy) and is_instance_valid(caster):
		_explode(enemy.global_position)  # burnt out: the bomb goes off on the living enemy
	if left <= EPSILON or not MageSpell.is_live(enemy):
		_end()


## The enemy died while this burn was on it (Enemy.died, after it left the enemies group).
func _on_enemy_died(dead: Enemy, _killer_index: int) -> void:
	if is_queued_for_deletion() or not is_instance_valid(caster) or not is_instance_valid(dead) \
			or not dead.is_inside_tree():
		return
	_explode(dead.global_position)


## The Living Bomb explodes at [param at] (once): Fire damage to every enemy within the radius.
func _explode(at: Vector3) -> void:
	if not is_armed():
		return
	exploded = true
	if not is_inside_tree() or not is_instance_valid(caster) or caster.procs == null:
		return
	for e in MageSpell.enemies_in(get_tree(), at, bomb_radius):
		if caster.procs.deal_raw(e, bomb_damage, MageSpell.FIRE, true, &"ability") > 0.0:
			bomb_hits += 1
	Vfx.explosion(WeaponRunner.flat(at) + Vector3.UP * 0.5, maxf(0.5, bomb_radius), MageSpell.FIRE_COLOR)
	if _ember != null:
		_ember.visible = false


func _end() -> void:
	set_physics_process(false)
	# Free the name at once so a new burn can take it while this one waits for deletion.
	name = "SpentBurn"
	queue_free()


static func _key(p_caster: Player) -> String:
	return "MageBurn%d" % p_caster.get_instance_id()


## A small pulsing ember core in the flames: this burn is a Living Bomb.
func _build_ember() -> void:
	_ember = MeshInstance3D.new()
	_ember.name = "Ember"
	_ember.mesh = MeshKit.cached("mage:bomb_ember", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.16
		s.height = 0.32
		s.radial_segments = 8
		s.rings = 4
		return s)
	_ember.material_override = Mats.glow(EMBER_COLOR, 2.4)
	_ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ember)


## Small flames licking up the body (world-space particles: they trail a walking enemy).
func _build_flames(body_radius: float) -> void:
	var p := CPUParticles3D.new()
	p.name = "Flames"
	p.amount = 12
	p.lifetime = 0.5
	p.local_coords = false
	p.mesh = MeshKit.cached("mage:flame", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.1
		s.height = 0.24
		s.radial_segments = 6
		s.rings = 3
		return s)
	p.material_override = Mats.particle(false)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(0.15, body_radius * 0.6)
	p.direction = Vector3.UP
	p.spread = 18.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0.0, 1.5, 0.0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	var g := Gradient.new()
	g.set_color(0, FLAME_HIGH)
	g.set_color(1, FLAME_LOW)
	p.color_ramp = g
	p.emitting = true
	add_child(p)
