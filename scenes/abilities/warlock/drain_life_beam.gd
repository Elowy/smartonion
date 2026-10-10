class_name WarlockDrainBeam
extends Node3D
## Drain Life visual: a wavering purple beam with a fel-green core from the drained enemy's
## chest to the Warlock's, and little green soul motes flowing along it towards the Warlock.
## Follows both ends every frame. [method finish] fades it out; it also frees itself when the
## Warlock is gone or downed. While the target is invalid (between a kill and the retarget)
## it is hidden. Shared meshes, cached materials.

const OUTER := Color(0.62, 0.22, 0.88, 0.5)
const CORE := Color(0.45, 1.0, 0.32)
const MOTE := Color(0.6, 1.0, 0.45)
const MOTES := 4
const MOTE_SPEED := 1.6
const OUTER_WIDTH := 0.2
const CORE_WIDTH := 0.07
const FADE_TIME := 0.15

static var _cylinder: CylinderMesh
static var _sphere: SphereMesh

var source: Player
var target: Node3D
var _age := 0.0
var _fade := 1.0
var _finishing := false
var _outer: MeshInstance3D
var _core: MeshInstance3D
var _motes: Array[MeshInstance3D] = []


## Creates the beam from [param p_source] to [param p_target] under the arena's entities.
static func create(p_source: Player, p_target: Node3D) -> WarlockDrainBeam:
	var b := WarlockDrainBeam.new()
	b.name = "DrainLifeBeam"
	b.source = p_source
	b.target = p_target
	b._build()
	var parent := WeaponRunner.effects_parent(p_source)
	if parent != null:
		parent.add_child(b)
		b._update(0.0)
	return b


## Fades out and frees itself.
func finish() -> void:
	_finishing = true


func is_finishing() -> bool:
	return _finishing


func _build() -> void:
	if _cylinder == null:
		_cylinder = CylinderMesh.new()
		_cylinder.top_radius = 0.5
		_cylinder.bottom_radius = 0.5
		_cylinder.height = 1.0
		_cylinder.radial_segments = 8
		_cylinder.rings = 1
		_sphere = SphereMesh.new()
		_sphere.radius = 0.07
		_sphere.height = 0.14
		_sphere.radial_segments = 8
		_sphere.rings = 4
	_outer = _mesh(_cylinder, Mats.unshaded(OUTER))
	_core = _mesh(_cylinder, Mats.glow(CORE, 2.4))
	for i in MOTES:
		_motes.append(_mesh(_sphere, Mats.glow(MOTE, 3.0)))


func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	_age += delta
	if source == null or not is_instance_valid(source) or not source.is_inside_tree() or source.downed:
		queue_free()
		return
	if _finishing:
		_fade -= delta / FADE_TIME
		if _fade <= 0.0:
			queue_free()
			return
	_update(delta)


func _update(_delta: float) -> void:
	if not is_inside_tree() or source == null or not is_instance_valid(source):
		return
	var live := is_instance_valid(target) and target.is_inside_tree()
	visible = live
	if not live:
		return
	var from := target.global_position + Vector3.UP * Player.CHEST_HEIGHT
	var to := source.get_chest_position()
	var d := to - from
	var length := d.length()
	if length < 0.05:
		visible = false
		return
	var dir := d / length
	global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), from + d * 0.5)
	var w := _fade * (1.0 + 0.18 * sin(_age * 21.0))
	_outer.scale = Vector3(OUTER_WIDTH * w, length, OUTER_WIDTH * w)
	_core.scale = Vector3(CORE_WIDTH * w, length, CORE_WIDTH * w)
	# Motes flow from the target (local y = -length / 2) to the Warlock (+length / 2).
	for i in _motes.size():
		var t := fposmod(_age * MOTE_SPEED + float(i) / float(_motes.size()), 1.0)
		var m := _motes[i]
		var wobble := Vector3(sin(_age * 9.0 + i * 2.1), 0.0, cos(_age * 7.0 + i * 1.7)) * 0.05
		m.position = Vector3(0.0, (t - 0.5) * length, 0.0) + wobble
		m.scale = Vector3.ONE * _fade * (0.6 + 0.4 * sin(t * PI))
