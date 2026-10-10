class_name WarlockRainOfFireVfx
extends Node3D
## Falling fire over a Rain of Fire circle: [constant METEORS] glowing fireballs with tails
## slant down from the sky onto random points of the circle and burst into a short ground
## flash, over and over until the area fades; a burning ring marks the edge. Child of the
## [AbilityArea] (freed with it). Purely visual: its randomness uses a private RNG, never
## RunState.rng. Shared meshes and cached materials only (the ring owns its material).

const METEORS := 7
const FALL_TIME := 0.45
const FALL_HEIGHT := 6.5
## Where the meteors come from relative to their landing point (screen up-right).
const FALL_SLANT := Vector3(1.4, 0.0, -1.1)
const FLASH_TIME := 0.22
## No new meteor starts this long before the area ends.
const STOP_BEFORE_END := 0.45
const CORE := Color(1.0, 0.86, 0.45)
const FIRE := Color(1.0, 0.45, 0.1)
const RING := Color(1.0, 0.42, 0.08, 0.85)

static var _meshes: Dictionary[String, Mesh] = {}

var radius := 3.0
var duration := 4.0
var _age := 0.0
var _rng := RandomNumberGenerator.new()
var _meteors: Array[Node3D] = []
var _flashes: Array[Node3D] = []
var _from: Array[Vector3] = []
var _to: Array[Vector3] = []
## Per meteor: < 0 = waiting, 0..1 = falling, > 1 = landed (flash runs).
var _t: Array[float] = []
var _ring: MeshInstance3D


static func create(p_radius: float, p_duration: float) -> WarlockRainOfFireVfx:
	var fx := WarlockRainOfFireVfx.new()
	fx.name = "RainOfFireVfx"
	fx.radius = maxf(0.3, p_radius)
	fx.duration = p_duration
	fx._rng.seed = hash(Time.get_ticks_usec())
	fx._build()
	return fx


## Number of meteors in the air right now (tests).
func falling_count() -> int:
	var n := 0
	for i in _t.size():
		if _t[i] >= 0.0 and _t[i] < 1.0:
			n += 1
	return n


func _build() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = MeshKit.cached("warlock:ground_quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)
	_ring.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	_ring.material_override = Mats.ring()
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = 0.08
	Mats.set_ring(_ring, RING, 0.9, 0.99, 0.06)
	add_child(_ring)
	for i in METEORS:
		var m := Node3D.new()
		m.name = "Meteor%d" % i
		_add_mesh(m, _sphere(0.13), Mats.glow(CORE, 3.0), Vector3.ZERO, Vector3.ONE)
		_add_mesh(m, _sphere(0.24), Mats.unshaded(Color(FIRE, 0.65)), Vector3.ZERO, Vector3.ONE)
		_add_mesh(m, _sphere(0.16), Mats.unshaded(Color(FIRE, 0.3)), Vector3(0, 0, 0.42), Vector3(1, 1, 3.0))
		m.visible = false
		add_child(m)
		_meteors.append(m)
		var flash := Node3D.new()
		flash.name = "Flash%d" % i
		_add_mesh(flash, _sphere(0.5), Mats.glow(Color(FIRE, 0.55), 2.0), Vector3.ZERO, Vector3(1.0, 0.35, 1.0))
		_add_mesh(flash, _sphere(0.22), Mats.glow(CORE, 2.6), Vector3.ZERO, Vector3(1.0, 0.6, 1.0))
		flash.visible = false
		add_child(flash)
		_flashes.append(flash)
		_from.append(Vector3.ZERO)
		_to.append(Vector3.ZERO)
		# Staggered start so the rain begins at once but not in one wave.
		_t.append(-float(i) / float(METEORS) * FALL_TIME * 1.1)
		_pick_spot(i)


func _process(delta: float) -> void:
	_age += delta
	var fade := clampf(minf(_age / 0.2, (duration - _age) / 0.3), 0.0, 1.0)
	if _ring != null:
		var pulse := 0.85 + 0.15 * sin(_age * 9.0)
		Mats.set_ring(_ring, Color(RING, RING.a * fade * pulse), 0.9, 0.99, 0.06 * fade)
	for i in _meteors.size():
		_t[i] += delta / FALL_TIME
		var t := _t[i]
		var m := _meteors[i]
		var flash := _flashes[i]
		if t < 0.0:
			m.visible = false
			flash.visible = false
			continue
		if t < 1.0:
			m.visible = true
			flash.visible = false
			m.position = _from[i].lerp(_to[i], t * t)
			continue
		m.visible = false
		var f := (t - 1.0) * FALL_TIME / FLASH_TIME
		if f < 1.0:
			flash.visible = true
			flash.position = _to[i]
			flash.scale = Vector3.ONE * (0.4 + 0.9 * sin(f * PI * 0.5)) * (1.0 - f * f)
			continue
		flash.visible = false
		if _age < duration - STOP_BEFORE_END:
			_pick_spot(i)
			_t[i] = -_rng.randf_range(0.0, 0.25)
		else:
			_t[i] = -INF


## New landing point inside the circle (local space) for meteor [param i].
func _pick_spot(i: int) -> void:
	var a := _rng.randf() * TAU
	var r := sqrt(_rng.randf()) * radius * 0.85
	var to := Vector3(cos(a) * r, 0.12, sin(a) * r)
	_to[i] = to
	_from[i] = to + FALL_SLANT + Vector3.UP * FALL_HEIGHT
	var dir := (_to[i] - _from[i]).normalized()
	_meteors[i].basis = Basis.looking_at(dir, Vector3.FORWARD if absf(dir.y) > 0.99 else Vector3.UP)


static func _add_mesh(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _sphere(r: float) -> Mesh:
	var key := "sphere:%.3f" % r
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 10
		m.rings = 5
		_meshes[key] = m
	return _meshes[key]
