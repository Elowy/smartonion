class_name GeneralBombShell
extends Node3D
## One thrown bomb of Engineer's Bomb: a black iron ball with a sputtering fuse that arcs from
## the hero's hand to its landing spot (marked by a red warning ring) in [member flight_time]
## seconds and explodes there: Fire damage (ProcSystem.deal_raw, source &"ability") to every
## enemy touching the [member radius] circle. Then, by spec:
##   bomblets > 0  – Cluster Bomb: that many small bombs scatter 1.4-2.4 m around and explode
##                   for bomblet_pct % of the damage in bomblet_radius;
##   burn_duration > 0 – Incendiary Bomb: an AbilityArea of burning ground (burn_pct % of the
##                   damage per burn_tick s).
## In group &"ability_areas" (WaveDirector.stop frees bombs still in flight); the ability's
## end_wave frees them too. Logic in _physics_process, looks in _process.

const FIRE := &"fire"
const BLAST_COLOR := Color(1.0, 0.55, 0.15)
const BURN_COLOR := Color(1.0, 0.4, 0.08, 0.45)
const IRON := Color(0.16, 0.15, 0.17)
const BRASS := Color(0.78, 0.6, 0.28)
const FUSE := Color(0.55, 0.42, 0.28)
const SPARK := Color(1.0, 0.75, 0.25)
const WARN_COLOR := Color(1.0, 0.25, 0.12, 0.8)
const HAND_HEIGHT := 0.9
const BOMBLET_SCALE := 0.55
const BOMBLET_FLIGHT := 0.35
const BOMBLET_MIN_DISTANCE := 1.4
const BOMBLET_MAX_DISTANCE := 2.4

var owner_player: Player
var start := Vector3.ZERO
var landing := Vector3.ZERO
var flight_time := 0.55
var arc_height := 2.0
var damage := 1.0
var radius := 2.5
var bomblets := 0
var bomblet_pct := 40.0
var bomblet_radius := 1.4
var burn_duration := 0.0
var burn_pct := 15.0
var burn_tick := 0.5
var is_bomblet := false
## Enemies damaged by the blast (tests).
var victims: Array[Enemy] = []
## The burning ground left behind (tests; may be freed).
var burn_area: AbilityArea
var exploded := false

var _t := 0.0
var _ball: Node3D
var _spark: MeshInstance3D
var _warn: MeshInstance3D
var _age := 0.0


## Throws a bomb for [param thrower] from [param from] (world, its height is kept) to
## [param to] (ground). [param payload]: damage, radius (already final) and the spec numbers
## (bomblets, bomblet_pct, bomblet_radius, burn_duration, burn_pct, burn_tick, flight_time).
## Not in the tree when there is no arena / parent.
static func throw(thrower: Player, from: Vector3, to: Vector3, payload: Dictionary, bomblet: bool = false) -> GeneralBombShell:
	var b := GeneralBombShell.new()
	b.name = "Bomblet" if bomblet else "Bomb"
	b.owner_player = thrower
	b.is_bomblet = bomblet
	b.start = from
	b.landing = Vector3(to.x, 0.0, to.z)
	b.damage = float(payload.get("damage", 1.0))
	b.radius = maxf(0.3, float(payload.get("radius", 2.5)))
	b.flight_time = maxf(0.05, float(payload.get("flight_time", 0.55)))
	b.bomblets = int(payload.get("bomblets", 0))
	b.bomblet_pct = float(payload.get("bomblet_pct", 40.0))
	b.bomblet_radius = float(payload.get("bomblet_radius", 1.4))
	b.burn_duration = float(payload.get("burn_duration", 0.0))
	b.burn_pct = float(payload.get("burn_pct", 15.0))
	b.burn_tick = float(payload.get("burn_tick", 0.5))
	var dist := GeneralKit.flat_distance(from, to)
	b.arc_height = (0.9 if bomblet else 1.6) + dist * 0.12
	b.add_to_group(&"ability_areas")
	var parent := WeaponRunner.effects_parent(thrower)
	if parent != null:
		parent.add_child(b)
		b.global_position = from
	return b


func _ready() -> void:
	_build()


func _physics_process(delta: float) -> void:
	advance(delta)


## One physics step of the flight; explodes on landing (tests drive it directly).
func advance(delta: float) -> void:
	if exploded:
		return
	_t += delta
	var k := clampf(_t / flight_time, 0.0, 1.0)
	var flat := start.lerp(landing, k)
	var y := lerpf(start.y, 0.15, k) + arc_height * 4.0 * k * (1.0 - k)
	if is_inside_tree():
		global_position = Vector3(flat.x, y, flat.z)
	if k >= 1.0:
		explode()


## Blast now (damage, bomblets / burning ground, effects) and free.
func explode() -> void:
	if exploded:
		return
	exploded = true
	if is_inside_tree():
		var tree := get_tree()
		var center := landing
		if _owner_valid() and owner_player.procs != null:
			for e in GeneralKit.enemies_around(tree, center, radius):
				owner_player.procs.deal_raw(e, damage, FIRE, true, &"ability")
				victims.append(e)
		Vfx.explosion(center + Vector3.UP * 0.3, radius, BLAST_COLOR)
		if not is_bomblet:
			Vfx.death_puff(center + Vector3.UP * 0.4, Color(0.3, 0.27, 0.25), 0.9)
		if _owner_valid():
			_spread(center)
	queue_free()


func _spread(center: Vector3) -> void:
	if bomblets > 0 and not is_bomblet:
		var payload := {
			"damage": damage * bomblet_pct / 100.0,
			"radius": bomblet_radius,
			"flight_time": BOMBLET_FLIGHT,
		}
		var rng := RunState.rng
		var turn := rng.randf() * TAU
		for i in bomblets:
			var angle := turn + TAU * float(i) / float(bomblets)
			var dist := rng.randf_range(BOMBLET_MIN_DISTANCE, BOMBLET_MAX_DISTANCE)
			var to := center + Vector3(cos(angle), 0.0, sin(angle)) * dist
			if Arena.current != null and is_instance_valid(Arena.current):
				to = Arena.current.clamp_point(to, 0.5)
			GeneralBombShell.throw(owner_player, center + Vector3.UP * 0.3, to, payload, true)
	if burn_duration > 0.0 and not is_bomblet:
		burn_area = AbilityArea.spawn(owner_player, center, radius, burn_duration, BURN_COLOR)
		if not burn_area.is_inside_tree():
			burn_area.free()
			burn_area = null
			return
		burn_area.school = FIRE
		burn_area.tick_interval = maxf(0.1, burn_tick)
		burn_area.damage_per_tick = damage * burn_pct / 100.0
		GeneralFlames.attach(burn_area)


func _owner_valid() -> bool:
	return owner_player != null and is_instance_valid(owner_player) and not owner_player.is_queued_for_deletion()


# --- Look --------------------------------------------------------------------------------------

func _build() -> void:
	_ball = Node3D.new()
	_ball.name = "Ball"
	_ball.scale = Vector3.ONE * (BOMBLET_SCALE if is_bomblet else 1.0)
	add_child(_ball)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = MeshKit.cached("general:bomb", func() -> Mesh: return _bomb_mesh())
	body.material_override = Mats.toon_vc()
	_ball.add_child(body)
	_spark = MeshInstance3D.new()
	_spark.name = "Spark"
	_spark.mesh = MeshKit.cached("general:bomb_spark", func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = 0.07
		m.height = 0.14
		m.radial_segments = 8
		m.rings = 4
		return m)
	_spark.material_override = Mats.glow(SPARK, 3.0)
	_spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spark.position = Vector3(0.05, 0.34, 0.0)
	_ball.add_child(_spark)
	# Warning ring on the landing spot (world space: top level).
	_warn = MeshInstance3D.new()
	_warn.name = "Warning"
	_warn.top_level = true
	_warn.mesh = MeshKit.cached("general:aura_quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(2.0, 2.0)
		return q)
	_warn.material_override = Mats.ring()
	_warn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_warn)
	_warn.global_transform = Transform3D(Basis.from_scale(Vector3(radius, 1.0, radius)), landing + Vector3.UP * 0.05)
	Mats.set_ring(_warn, Color(WARN_COLOR.r, WARN_COLOR.g, WARN_COLOR.b, 0.25), 0.9, 0.97, 0.03)


func _process(delta: float) -> void:
	_age += delta
	if _ball != null:
		_ball.rotation.x += delta * 7.0
		_ball.rotation.z += delta * 3.0
	if _spark != null:
		_spark.scale = Vector3.ONE * (0.8 + 0.35 * sin(_age * 40.0) + 0.2 * sin(_age * 23.0))
	if _warn != null:
		var k := clampf(_t / flight_time, 0.0, 1.0)
		Mats.set_ring(_warn, Color(WARN_COLOR.r, WARN_COLOR.g, WARN_COLOR.b, 0.25 + 0.45 * k), 0.9, 0.97, 0.03 + 0.09 * k)


static func _bomb_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_sphere(0.24, Transform3D.IDENTITY, IRON, 14, 8)
	# Brass collar and fuse.
	k.add_cylinder(0.09, 0.1, 0.08, MeshKit.xf(Vector3(0, 0.24, 0)), BRASS, 10)
	k.add_tube(PackedVector3Array([Vector3(0, 0.27, 0), Vector3(0.02, 0.31, 0), Vector3(0.05, 0.33, 0)]),
			0.022, 0.016, FUSE, 6)
	# A highlight band and rivets.
	k.add_torus(0.225, 0.25, MeshKit.xf(Vector3.ZERO, Vector3(90, 0, 0)), Color(0.28, 0.27, 0.3), 18, 6)
	for i in 4:
		var a := TAU * float(i) / 4.0
		k.add_sphere(0.03, MeshKit.xf(Vector3(cos(a) * 0.24, 0.0, sin(a) * 0.24)), BRASS, 6, 3)
	return k.build()
