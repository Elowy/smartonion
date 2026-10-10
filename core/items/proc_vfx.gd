class_name ProcVfx
extends Node3D
## Small fire-and-forget visuals of procs (GDD 5.7) that [Vfx] has no helper for: a glowing
## bolt flying from the hero to its target and a short lightning / drain beam between two
## points. One node + one mesh each (shared meshes, cached [method Mats.glow] materials),
## animated in _process and freed after [member life] seconds. Bigger effects reuse [Vfx]
## (explosion, hit_spark, floating_text). Gameplay never waits for these (the damage of a
## proc is applied at once).

enum Kind { BOLT, BEAM }

const BOLT_TIME := 0.14
const BEAM_TIME := 0.18
const BOLT_RADIUS := 0.16
const BEAM_WIDTH := 0.07
## Colour of each damage school (damage numbers, bolts, beams, novas).
const SCHOOL_COLORS := {
	&"physical": Color(0.92, 0.86, 0.74),
	&"fire": Color(1.0, 0.52, 0.16),
	&"frost": Color(0.55, 0.85, 1.0),
	&"arcane": Color(0.78, 0.52, 1.0),
	&"holy": Color(1.0, 0.9, 0.45),
	&"shadow": Color(0.66, 0.36, 0.9),
	&"nature": Color(0.5, 0.95, 0.38),
}

static var _sphere: SphereMesh
static var _cylinder: CylinderMesh

var kind := Kind.BOLT
var life := BOLT_TIME
var age := 0.0
var from := Vector3.ZERO
var to := Vector3.ZERO
var _mesh: MeshInstance3D


static func school_color(school: StringName) -> Color:
	return SCHOOL_COLORS.get(school, Color.WHITE)


## A glowing ball flying from [param p_from] to [param p_to] (world positions).
static func bolt(p_from: Vector3, p_to: Vector3, color: Color) -> void:
	_spawn(Kind.BOLT, p_from, p_to, color, BOLT_TIME)


## A thin glowing beam from [param p_from] to [param p_to] that narrows and vanishes.
static func beam(p_from: Vector3, p_to: Vector3, color: Color) -> void:
	if p_from.distance_squared_to(p_to) < 0.0001:
		return
	_spawn(Kind.BEAM, p_from, p_to, color, BEAM_TIME)


static func _spawn(p_kind: Kind, p_from: Vector3, p_to: Vector3, color: Color, p_life: float) -> void:
	var parent := Vfx.effect_parent()
	if parent == null or not parent.is_inside_tree():
		return
	_ensure_meshes()
	var fx := ProcVfx.new()
	fx.name = "ProcVfx"
	fx.kind = p_kind
	fx.life = p_life
	fx.from = p_from
	fx.to = p_to
	fx._mesh = MeshInstance3D.new()
	fx._mesh.mesh = _sphere if p_kind == Kind.BOLT else _cylinder
	fx._mesh.material_override = Mats.glow(color, 2.5)
	fx._mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(fx._mesh)
	parent.add_child(fx)
	fx._update(0.0)


func _process(delta: float) -> void:
	age += delta
	_update(clampf(age / maxf(life, 0.001), 0.0, 1.0))
	if age >= life:
		queue_free()


func _update(t: float) -> void:
	if not is_inside_tree():
		return
	match kind:
		Kind.BOLT:
			global_position = from.lerp(to, t)
		Kind.BEAM:
			var d := to - from
			var length := d.length()
			var w := 1.0 - t
			global_transform = Transform3D(Basis(Quaternion(Vector3.UP, d / length)), from + d * 0.5)
			_mesh.scale = Vector3(w, length, w)


static func _ensure_meshes() -> void:
	if _sphere != null:
		return
	_sphere = SphereMesh.new()
	_sphere.radius = BOLT_RADIUS
	_sphere.height = BOLT_RADIUS * 2.0
	_sphere.radial_segments = 10
	_sphere.rings = 5
	_cylinder = CylinderMesh.new()
	_cylinder.top_radius = BEAM_WIDTH * 0.5
	_cylinder.bottom_radius = BEAM_WIDTH * 0.5
	_cylinder.height = 1.0
	_cylinder.radial_segments = 6
	_cylinder.rings = 1
