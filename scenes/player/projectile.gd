class_name Projectile
extends Node3D
## Owned by the "player" module (used by enemies too).
## Moves in a straight line on the XZ plane; hits by distance checks against
## group &"enemies" (TEAM_PLAYERS – only the ones the shared [EnemyGrid] finds near the
## travelled segment / blast) or &"players" (TEAM_ENEMIES).
##
## The caller adds the node to the scene (Arena.current.entities) and sets its
## global_position (y ~ Player.CHEST_HEIGHT); the height is kept while flying.
## Hits are swept along the travelled segment so fast bullets cannot tunnel. Each target is
## hit at most once; [member pierce] extra targets may be passed through. With
## [member aoe_radius] > 0 every impact explodes and damages everything in the radius.
## Frees itself at the end of its range or when it leaves the arena.

const TEAM_PLAYERS := 0
const TEAM_ENEMIES := 1

## Radius of the projectile itself for hit tests (added to the target radius).
const HIT_RADIUS := 0.2
## Projectiles further than this outside the arena bounds are removed.
const ARENA_MARGIN := 1.0
const AXE_SPIN_SPEED := 14.0
## Enemy throws spin faster (reads as dangerous).
const ENEMY_SPIN_SPEED := 24.0

var team := TEAM_PLAYERS
var damage := 1.0
var is_crit := false
## Normalised flight direction on the XZ plane.
var direction := Vector3.FORWARD
var speed := 10.0
var max_range := 10.0
var pierce := 0
var aoe_radius := 0.0
## The Player that fired it (kill credit / leech) or the Enemy. May be freed mid-flight.
var attacker: Node3D
var style: StringName = &"bolt"
var color := Color.WHITE
## TEAM_PLAYERS only: knockback impulse strength along the shot direction.
var knockback := 1.5
## TEAM_PLAYERS only: chance (0..1) to stun each enemy hit.
var stun_chance := 0.0
var stun_duration := 0.5
## TEAM_PLAYERS only: the weapon that fired it (on-hit procs read its cooldown) and whether it
## belongs to an extra attack (its hits cannot trigger further extra attacks).
var weapon: WeaponData
var is_extra := false
## Metres flown so far.
var travelled := 0.0
## Number of targets damaged so far.
var hit_count := 0

var _pierce_left := 0
var _hit_ids: Dictionary[int, bool] = {}
var _done := false
var _visual: Node3D
var _spinner: Node3D


## [param p_style]: &"bolt" (arcane), &"fireball", &"arrow", &"bullet", &"axe" (troll throw).
## [param p_attacker]: the Player that fired it (for kill credit / leech) or the Enemy.
## [param p_pierce]: how many extra targets it passes through; [param p_aoe_radius] > 0
## makes every impact explode.
static func create(p_team: int, p_damage: float, p_is_crit: bool, p_direction: Vector3, p_speed: float,
		p_max_range: float, p_pierce: int = 0, p_aoe_radius: float = 0.0, p_attacker: Node3D = null,
		p_style: StringName = &"bolt", p_color: Color = Color.WHITE) -> Projectile:
	var p := Projectile.new()
	p.name = "Projectile"
	p.team = p_team
	p.damage = p_damage
	p.is_crit = p_is_crit
	var d := Vector3(p_direction.x, 0.0, p_direction.z)
	p.direction = d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD
	p.speed = maxf(0.0, p_speed)
	p.max_range = maxf(0.0, p_max_range)
	p.pierce = maxi(0, p_pierce)
	p._pierce_left = p.pierce
	p.aoe_radius = maxf(0.0, p_aoe_radius)
	p.attacker = p_attacker
	p.style = p_style
	p.color = p_color
	p.add_to_group(&"projectiles")
	p._build_visual()
	return p


## Fallback colour for a projectile style.
static func default_color(p_style: StringName) -> Color:
	match p_style:
		&"bolt":
			return Color(0.72, 0.5, 1.0)
		&"fireball":
			return Color(1.0, 0.5, 0.12)
		&"arrow":
			return Color(0.95, 0.9, 0.75)
		&"bullet":
			return Color(1.0, 0.86, 0.45)
		&"axe":
			return Color(0.75, 0.75, 0.78)
	return Color.WHITE


## True once the projectile has finished (hit its last target or ran out of range).
func is_done() -> bool:
	return _done


func _physics_process(delta: float) -> void:
	advance(delta)


func _process(delta: float) -> void:
	if _spinner != null:
		_spinner.rotate_y((ENEMY_SPIN_SPEED if team == TEAM_ENEMIES else AXE_SPIN_SPEED) * delta)


## Moves the projectile [param delta] seconds forward and resolves hits along the way.
func advance(delta: float) -> void:
	if _done or not is_inside_tree():
		return
	var step := minf(speed * delta, max_range - travelled)
	var from := global_position
	var to := from + direction * maxf(0.0, step)
	_sweep(from, to)
	if _done:
		return
	global_position = to
	travelled += maxf(0.0, step)
	if travelled >= max_range - 0.0001 or _outside_arena():
		_finish()


func _sweep(from: Vector3, to: Vector3) -> void:
	# Hot path (every projectile each tick): only the targets near the segment (EnemyGrid),
	# plain float maths first, the validity checks only for the few bodies close to it.
	var sx := to.x - from.x
	var sz := to.z - from.z
	var seg_len_sq := sx * sx + sz * sz
	var inv_len_sq := 1.0 / seg_len_sq if seg_len_sq > 0.0 else 0.0
	var vs_enemies := team == TEAM_PLAYERS
	var candidates: Array[Array] = []
	var nodes := _targets_near(minf(from.x, to.x) - HIT_RADIUS, minf(from.z, to.z) - HIT_RADIUS,
			maxf(from.x, to.x) + HIT_RADIUS, maxf(from.z, to.z) + HIT_RADIUS)
	for order in nodes.size():
		var body := nodes[order] as Node3D
		if body == null:
			continue
		var pos := body.global_position
		var rx := pos.x - from.x
		var rz := pos.z - from.z
		var t := clampf((rx * sx + rz * sz) * inv_len_sq, 0.0, 1.0)
		var dx := rx - sx * t
		var dz := rz - sz * t
		var e := body as Enemy if vs_enemies else null
		var reach := (e.radius if e != null else Player.RADIUS) + HIT_RADIUS
		if dx * dx + dz * dz > reach * reach:
			continue
		if _is_valid_target(body):
			candidates.append([t, order, body])
	if candidates.is_empty():
		return
	if candidates.size() > 1:
		# Along the flight path; equal positions in group order (deterministic).
		candidates.sort_custom(func(a: Array, b: Array) -> bool:
			return float(a[0]) < float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
	for c in candidates:
		if _done:
			return
		var body := c[2] as Node3D
		if not _is_valid_target(body):
			continue
		var t := float(c[0])
		_impact(body, from.lerp(to, t))


func _impact(body: Node3D, at: Vector3) -> void:
	if aoe_radius > 0.0:
		var center := Vector3(body.global_position.x, at.y, body.global_position.z)
		_explode(center)
	else:
		_hit_ids[body.get_instance_id()] = true
		_apply_hit(body, direction, false)
		Vfx.hit_spark(at, color)
	if _pierce_left > 0:
		_pierce_left -= 1
	else:
		_finish()


func _explode(center: Vector3) -> void:
	Vfx.explosion(center, aoe_radius, color)
	var victims: Array[Node3D] = []
	for node in _targets_near(center.x - aoe_radius, center.z - aoe_radius, center.x + aoe_radius,
			center.z + aoe_radius):
		var body := node as Node3D
		if not _is_valid_target(body):
			continue
		var reach := aoe_radius + _target_radius(body)
		if WeaponRunner.flat(body.global_position - center).length_squared() <= reach * reach:
			victims.append(body)
	for body in victims:
		if not _is_valid_target(body):
			continue
		_hit_ids[body.get_instance_id()] = true
		var away := WeaponRunner.flat(body.global_position - center)
		var kb_dir := away.normalized() if away.length_squared() > 0.0001 else direction
		_apply_hit(body, kb_dir, true)


func _apply_hit(body: Node3D, kb_dir: Vector3, from_explosion: bool) -> void:
	hit_count += 1
	var source: Node3D = attacker if attacker != null and is_instance_valid(attacker) else null
	if team == TEAM_PLAYERS:
		WeaponRunner.apply_hit(source as Player, body as Enemy, damage, is_crit, kb_dir * knockback,
				stun_chance, stun_duration, weapon, is_extra)
	else:
		var p := body as Player
		p.take_damage(damage, CombatMath.KIND_AOE if from_explosion else CombatMath.KIND_PROJECTILE, source)
		LivingPlayers.mark_dirty()  # the player may have gone down


func _target_group() -> StringName:
	return &"enemies" if team == TEAM_PLAYERS else &"players"


## Possible targets whose body may touch the rectangle (XZ): the enemies the shared
## [EnemyGrid] finds there (group order) for player shots, every player for enemy throws.
func _targets_near(min_x: float, min_z: float, max_x: float, max_z: float) -> Array[Node]:
	if team == TEAM_PLAYERS:
		return EnemyGrid.gather_touching(get_tree(), min_x, min_z, max_x, max_z)
	return get_tree().get_nodes_in_group(&"players")


func _is_valid_target(body: Node3D) -> bool:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return false
	if _hit_ids.has(body.get_instance_id()):
		return false
	if team == TEAM_PLAYERS:
		var e := body as Enemy
		return e != null and not e.is_dead()
	var p := body as Player
	return p != null and p.is_alive()


func _target_radius(body: Node3D) -> float:
	var e := body as Enemy
	if e != null:
		return e.radius
	return Player.RADIUS


func _outside_arena() -> bool:
	var arena := Arena.current
	if arena == null:
		return false
	var b := arena.get_bounds().grow(ARENA_MARGIN)
	return not b.has_point(Vector2(global_position.x, global_position.z))


func _finish() -> void:
	if _done:
		return
	_done = true
	set_physics_process(false)
	set_process(false)
	queue_free()


func _build_visual() -> void:
	_visual = ProjectileVisual.build(style, color, is_crit, team == TEAM_ENEMIES)
	_visual.name = "Visual"
	_visual.basis = Basis.looking_at(direction, Vector3.UP)
	add_child(_visual)
	# The spinner sits under a tilt (and, for enemies, a scale) node.
	_spinner = _visual.find_child("Spinner", true, false) as Node3D
	set_process(_spinner != null)
