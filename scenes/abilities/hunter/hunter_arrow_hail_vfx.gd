class_name HunterArrowHailVfx
extends Node3D
## Falling arrows over an Arrow Hail circle: [constant ARROWS] arrows slant down from the sky onto
## random points of the circle and stick in the ground for a moment, over and over until the area
## fades; an amber ring marks the edge. Child of the [AbilityArea] (freed with it). Purely visual:
## its randomness uses a private RNG, never RunState.rng. Shared meshes and cached materials only
## (the ring owns its material).

const ARROWS := 9
const FALL_TIME := 0.32
const FALL_HEIGHT := 6.0
## Where the arrows come from relative to their landing point (screen up-right).
const FALL_SLANT := Vector3(1.2, 0.0, -0.9)
## How long a landed arrow stands in the ground (s).
const STAND_TIME := 0.35
## No new arrow starts this long before the area ends.
const STOP_BEFORE_END := 0.4
const RING := Color(1.0, 0.66, 0.24, 0.85)
const SHAFT := Color(0.55, 0.38, 0.22)
const STEEL := Color(0.8, 0.82, 0.88)
const FLETCH := Color(0.96, 0.9, 0.7)

var radius := 3.0
var duration := 4.0
var _age := 0.0
var _rng := RandomNumberGenerator.new()
var _arrows: Array[Node3D] = []
var _from: Array[Vector3] = []
var _to: Array[Vector3] = []
## Per arrow: < 0 = waiting, 0..1 = falling, 1..2 = standing in the ground, > 2 = done / idle.
var _t: Array[float] = []
var _ring: MeshInstance3D


static func create(p_radius: float, p_duration: float) -> HunterArrowHailVfx:
	var fx := HunterArrowHailVfx.new()
	fx.name = "ArrowHailVfx"
	fx.radius = maxf(0.3, p_radius)
	fx.duration = p_duration
	fx._rng.seed = hash(Time.get_ticks_usec())
	fx._build()
	return fx


## Number of arrows in the air right now (tests).
func falling_count() -> int:
	var n := 0
	for t in _t:
		if t >= 0.0 and t < 1.0:
			n += 1
	return n


func _build() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = MeshKit.cached("hunter:quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)
	_ring.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	_ring.material_override = Mats.ring()
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = 0.08
	Mats.set_ring(_ring, RING, 0.9, 0.99, 0.06)
	add_child(_ring)
	var mesh := arrow_mesh()
	for i in ARROWS:
		var a := MeshInstance3D.new()
		a.name = "Arrow%d" % i
		a.mesh = mesh
		a.material_override = Mats.toon_vc(false)
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		a.visible = false
		add_child(a)
		_arrows.append(a)
		_from.append(Vector3.ZERO)
		_to.append(Vector3.ZERO)
		# Staggered start so the hail begins at once but not in one wave.
		_t.append(-float(i) / float(ARROWS) * FALL_TIME * 1.2)
		_pick_spot(i)


func _process(delta: float) -> void:
	_age += delta
	var fade := clampf(minf(_age / 0.2, (duration - _age) / 0.3), 0.0, 1.0)
	if _ring != null:
		var pulse := 0.85 + 0.15 * sin(_age * 9.0)
		Mats.set_ring(_ring, Color(RING, RING.a * fade * pulse), 0.9, 0.99, 0.06 * fade)
	for i in _arrows.size():
		_t[i] += delta / FALL_TIME
		var t := _t[i]
		var a := _arrows[i]
		if t < 0.0:
			a.visible = false
			continue
		if t < 1.0:
			a.visible = true
			a.position = _from[i].lerp(_to[i], t * t)
			continue
		var standing := (t - 1.0) * FALL_TIME / STAND_TIME
		if standing < 1.0:
			a.visible = true
			a.position = _to[i]
			continue
		a.visible = false
		if _age < duration - STOP_BEFORE_END:
			_pick_spot(i)
			_t[i] = -_rng.randf_range(0.0, 0.2)
		else:
			_t[i] = -INF


## New landing point inside the circle (local space) for arrow [param i].
func _pick_spot(i: int) -> void:
	var angle := _rng.randf() * TAU
	var r := sqrt(_rng.randf()) * radius * 0.85
	var to := Vector3(cos(angle) * r, 0.0, sin(angle) * r)
	_to[i] = to
	_from[i] = to + FALL_SLANT + Vector3.UP * FALL_HEIGHT
	var dir := (_to[i] - _from[i]).normalized()
	_arrows[i].basis = Basis.looking_at(dir, Vector3.FORWARD if absf(dir.y) > 0.99 else Vector3.UP)


## A little arrow along -Z (head first), 0.8 m long: wooden shaft, steel head, pale fletching.
static func arrow_mesh() -> Mesh:
	return MeshKit.cached("hunter:hail_arrow", func() -> Mesh:
		var k := MeshKit.new()
		k.add_segment(Vector3(0, 0, 0.35), Vector3(0, 0, -0.28), 0.018, 0.018, SHAFT, 5)
		k.add_segment(Vector3(0, 0, -0.26), Vector3(0, 0, -0.42), 0.05, 0.0, STEEL, 5)
		for roll in [0.0, 90.0]:
			k.add_box(Vector3(0.1, 0.012, 0.16), MeshKit.xf(Vector3(0, 0, 0.3), Vector3(0, 0, roll)), FLETCH)
		return k.build())
