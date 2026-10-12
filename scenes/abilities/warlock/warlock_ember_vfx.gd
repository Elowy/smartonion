class_name WarlockEmberVfx
extends Node3D
## The look of Conflagrate's burning ground ([WarlockEmbers]): dark-red glowing cracks over the
## circle, low flickering flame tongues and a handful of sparks rising and falling back. Child
## of the [AbilityArea] (freed with it); it fades out over its last [constant FADE_TIME]
## seconds of [member life], with the area's own fade. Purely visual: the layout is a fixed
## golden-angle spiral (no RNG at all), meshes are cached and shared, materials are cached
## (Mats.glow / Mats.unshaded) – the animation only moves / scales nodes.

const CRACKS := 7
const TONGUES := 9
const SPARKS := 6
const FADE_TIME := 0.4
const CRACK_COLOR := Color(0.85, 0.12, 0.04)
const FLAME_COLOR := Color(1.0, 0.35, 0.08)
const SPARK_COLOR := Color(1.0, 0.7, 0.3)
const GOLDEN_ANGLE := 2.39996
const SPARK_HEIGHT := 1.1
const SPARK_PERIOD := 1.3

var radius := 3.0
## Seconds the ground burns.
var life := 3.0
var age := 0.0
var _tongues: Array[Node3D] = []
var _sparks: Array[Node3D] = []
var _cracks: Node3D


## The look for a burning circle of [param p_radius] m that burns [param p_life] seconds.
static func create(p_radius: float, p_life: float) -> WarlockEmberVfx:
	var fx := WarlockEmberVfx.new()
	fx.name = "EmberVfx"
	fx.radius = maxf(0.3, p_radius)
	fx.life = maxf(0.1, p_life)
	fx._build()
	return fx


func _build() -> void:
	_cracks = Node3D.new()
	_cracks.name = "Cracks"
	_cracks.position.y = 0.07
	add_child(_cracks)
	var crack_mesh := MeshKit.cached("warlock:ember:crack", func() -> Mesh: return _crack_mesh())
	var crack_mat := Mats.glow(CRACK_COLOR, 1.6)
	for i in CRACKS:
		var c := MeshInstance3D.new()
		c.mesh = crack_mesh
		c.material_override = crack_mat
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := float(i) * GOLDEN_ANGLE
		var r := radius * sqrt((float(i) + 0.5) / float(CRACKS)) * 0.85
		c.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		c.rotation.y = a * 1.7
		c.scale = Vector3.ONE * clampf(radius / 3.0, 0.6, 1.6)
		_cracks.add_child(c)
	var tongue_mesh := MeshKit.cached("warlock:ember:tongue", func() -> Mesh: return _tongue_mesh())
	var tongue_mat := Mats.unshaded(Color(FLAME_COLOR, 0.8))
	for i in TONGUES:
		var t := MeshInstance3D.new()
		t.mesh = tongue_mesh
		t.material_override = tongue_mat
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := float(i) * GOLDEN_ANGLE + 0.7
		var r := radius * sqrt((float(i) + 0.5) / float(TONGUES)) * 0.9
		t.position = Vector3(cos(a) * r, 0.04, sin(a) * r)
		add_child(t)
		_tongues.append(t)
	var spark_mesh := MeshKit.cached("warlock:ember:spark", func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = 0.05
		m.height = 0.1
		m.radial_segments = 6
		m.rings = 3
		return m)
	var spark_mat := Mats.glow(SPARK_COLOR, 2.6)
	for i in SPARKS:
		var s := MeshInstance3D.new()
		s.mesh = spark_mesh
		s.material_override = spark_mat
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := float(i) * GOLDEN_ANGLE * 1.3 + 0.2
		var r := radius * 0.7 * sqrt((float(i) + 0.5) / float(SPARKS))
		s.position = Vector3(cos(a) * r, 0.1, sin(a) * r)
		add_child(s)
		_sparks.append(s)
	_update()


func _process(delta: float) -> void:
	age += delta
	_update()


func _update() -> void:
	var fade := clampf((life - age) / FADE_TIME, 0.0, 1.0) * clampf(age / 0.2 + 0.3, 0.0, 1.0)
	_cracks.scale = Vector3(1.0, 1.0, 1.0) * maxf(0.05, fade)
	for i in _tongues.size():
		var flicker := 0.75 + 0.25 * sin(age * (9.0 + float(i)) + float(i) * 1.9)
		_tongues[i].scale = Vector3(1.0, flicker, 1.0) * maxf(0.05, fade)
	for i in _sparks.size():
		var t := fposmod(age / SPARK_PERIOD + float(i) / float(SPARKS), 1.0)
		var s := _sparks[i]
		s.position.y = 0.1 + SPARK_HEIGHT * t
		s.scale = Vector3.ONE * maxf(0.05, (1.0 - t) * fade)


## A jagged crack lying on the ground (white; the material colours it).
static func _crack_mesh() -> Mesh:
	var k := MeshKit.new()
	var points: Array[Vector3] = [Vector3(-0.45, 0, 0.05), Vector3(-0.2, 0, -0.06), Vector3(0.0, 0, 0.04),
			Vector3(0.22, 0, -0.05), Vector3(0.46, 0, 0.03)]
	for i in points.size() - 1:
		k.add_segment(points[i], points[i + 1], 0.03, 0.022, Color.WHITE, 4)
	k.add_segment(points[2], Vector3(0.08, 0, 0.24), 0.022, 0.0, Color.WHITE, 4)
	return k.build()


## A low flame tongue (a cone).
static func _tongue_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_cylinder(0.0, 0.12, 0.38, MeshKit.xf(Vector3(0, 0.19, 0)), Color.WHITE, 8)
	return k.build()
