class_name TrailerStage
extends Node3D
## Dev tool (tools/trailer/): the set for the trailer's glamour shots (the tier-set line-up, the end card): one of the
## game's real arenas (its ground, scenery, sun and sky) with a free camera and a few posed heroes. The heroes are
## the game's own [OnionModel]s with the equipment looks of the item system.

var arena: Arena
var camera: Camera3D
var _models: Array[OnionModel] = []


## A stage in the arena of environment [param env_id] (an id of Db.environments; "" = the forest ruin).
static func create(env_id: StringName = &"") -> TrailerStage:
	var s := TrailerStage.new()
	s.name = "TrailerStage"
	s._build(env_id)
	return s


func _build(env_id: StringName) -> void:
	RunState.start_run(1, 7, RunState.MODE_NORMAL, false, env_id)
	arena = Arena.create(Db.environment_or_default(RunState.environment), false)
	add_child(arena)
	arena.camera.set_process(false)
	camera = Camera3D.new()
	camera.fov = 32.0
	camera.near = 0.3
	camera.far = 260.0
	add_child(camera)


func _ready() -> void:
	camera.make_current()  # (after the arena's own rig took the view in its _ready)


## A hero of [param class_id] at [param pos] facing [param yaw_deg] (0 = towards +Z, the camera's side), wearing the
## tier set of the class (rarity [param rarity], 0 = starter look) with its starting weapons.
func add_hero(class_id: StringName, pos: Vector3, yaw_deg: float, rarity: int = 3, color_index: int = 0) -> OnionModel:
	var cd := Db.get_class_data(class_id)
	var m := OnionModel.new()
	arena.entities.add_child(m)
	m.setup(cd, PlayerManager.PLAYER_COLORS[color_index % PlayerManager.PLAYER_COLORS.size()])
	m.set_weapons(cd.main_hand, cd.off_hand)
	m.position = pos
	var yaw := deg_to_rad(yaw_deg)
	m.set_facing(Vector3(sin(yaw), 0, cos(yaw)))
	if rarity > 0:
		var set_data := Db.set_for_class(class_id)
		var sid: StringName = set_data.id if set_data != null else &""
		m.set_looks(EquipLook.make(EquipLook.Slot.HEAD, cd.armor_type, 1, rarity, sid),
			EquipLook.make(EquipLook.Slot.SHOULDERS, cd.armor_type, 1, rarity, sid),
			EquipLook.make(EquipLook.Slot.CHEST, cd.armor_type, 1, rarity, sid))
	_models.append(m)
	return m


func models() -> Array[OnionModel]:
	return _models


## Camera on a sphere around [param look]: [param dist], [param pitch] / [param yaw] in degrees (yaw 0 = from +Z).
func aim(look: Vector3, dist: float, pitch: float, yaw: float, fov: float = 32.0) -> void:
	var p := deg_to_rad(pitch)
	var offset := (Vector3(0.0, sin(p), cos(p)) * dist).rotated(Vector3.UP, deg_to_rad(yaw))
	camera.fov = fov
	camera.global_position = look + offset
	camera.look_at(look, Vector3.UP)
