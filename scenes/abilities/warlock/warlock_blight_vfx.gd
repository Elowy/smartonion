class_name WarlockBlightVfx
extends Node3D
## Blighted Ground (Seed of Corruption, Rank V): a sickly green rim around the pool and fel
## bubbles that swell, rise a little and pop all over it until the area fades. Child of the
## [AbilityArea] (freed with it). Purely visual: fixed bubble layout, no RunState.rng.
## The rim owns its ring material; the bubbles share a mesh and a cached glow material.

const BUBBLES := 7
const BUBBLE_TIME := 0.7
const RIM := Color(0.45, 0.95, 0.25, 0.8)
const BUBBLE := Color(0.5, 1.0, 0.35)

static var _bubble_mesh: Mesh

var radius := 2.0
var duration := 3.0
var _age := 0.0
var _rim: MeshInstance3D
var _bubbles: Array[MeshInstance3D] = []
var _spots: Array[Vector3] = []


static func create(p_radius: float, p_duration: float) -> WarlockBlightVfx:
	var fx := WarlockBlightVfx.new()
	fx.name = "BlightVfx"
	fx.radius = maxf(0.3, p_radius)
	fx.duration = p_duration
	fx._build()
	return fx


func _build() -> void:
	_rim = MeshInstance3D.new()
	_rim.name = "Rim"
	_rim.mesh = MeshKit.cached("warlock:ground_quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)
	_rim.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	_rim.material_override = Mats.ring()
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rim.position.y = 0.08
	add_child(_rim)
	if _bubble_mesh == null:
		var m := SphereMesh.new()
		m.radius = 0.16
		m.height = 0.32
		m.radial_segments = 10
		m.rings = 5
		_bubble_mesh = m
	var mat := Mats.glow(BUBBLE, 1.6)
	for i in BUBBLES:
		var b := MeshInstance3D.new()
		b.mesh = _bubble_mesh
		b.material_override = mat
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
		_bubbles.append(b)
		# Golden-angle spiral: evenly spread, no randomness needed.
		var a := float(i) * 2.39996
		var r := sqrt((float(i) + 0.5) / float(BUBBLES)) * radius * 0.8
		_spots.append(Vector3(cos(a) * r, 0.05, sin(a) * r))
	_update()


func _process(delta: float) -> void:
	_age += delta
	_update()


func _update() -> void:
	var fade := clampf(minf(_age / 0.2, (duration - _age) / 0.3), 0.0, 1.0)
	Mats.set_ring(_rim, Color(RIM, RIM.a * fade), 0.88, 0.99, 0.0)
	for i in _bubbles.size():
		var t := fposmod(_age / BUBBLE_TIME + float(i) / float(BUBBLES), 1.0)
		var b := _bubbles[i]
		b.position = _spots[i] + Vector3(0.0, 0.25 * t, 0.0)
		b.scale = Vector3.ONE * maxf(0.02, sin(t * PI) * fade)
