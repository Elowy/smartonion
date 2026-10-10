class_name OnionPreview
extends SubViewportContainer
## Live 3D preview of a class onion for the lobby cards (GDD 12 "class pick with character
## preview"): its own World3D in a transparent SubViewport, a key + rim light and a camera
## looking at the onion's face. The onion idles and slowly sways left and right.

const CAMERA_POS := Vector3(0.0, 1.25, 3.3)
const LOOK_AT := Vector3(0.0, 0.62, 0.0)
const SWAY_SPEED := 0.7
const SWAY_AMOUNT := 0.55

var viewport: SubViewport
var model: OnionModel
var camera: Camera3D

var _pivot: Node3D
var _t := 0.0
var _class_id: StringName = &""
var _color := Color(0, 0, 0, 0)


static func create() -> OnionPreview:
	var p := OnionPreview.new()
	p.name = "OnionPreview"
	p.stretch = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.viewport = SubViewport.new()
	p.viewport.name = "Viewport"
	p.viewport.own_world_3d = true
	p.viewport.transparent_bg = true
	p.viewport.msaa_3d = Viewport.MSAA_4X
	p.viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	p.viewport.size = Vector2i(400, 300)
	p.add_child(p.viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.72)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	p.viewport.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	key.light_color = Color(1.0, 0.93, 0.8)
	key.light_energy = 1.0
	p.viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.rotation_degrees = Vector3(-20.0, 200.0, 0.0)
	rim.light_color = Color(1.0, 0.75, 0.45)
	rim.light_energy = 0.5
	p.viewport.add_child(rim)

	p.camera = Camera3D.new()
	p.camera.name = "Camera"
	p.camera.fov = 30.0
	p.camera.transform = Transform3D(Basis.looking_at(LOOK_AT - CAMERA_POS, Vector3.UP), CAMERA_POS)
	p.viewport.add_child(p.camera)

	p._pivot = Node3D.new()
	p._pivot.name = "Pivot"
	p.viewport.add_child(p._pivot)
	return p


## Shows [param data]'s onion with its starting weapons and the player's ring colour.
func show_class(data: ClassData, player_color: Color) -> void:
	if data == null:
		return
	if model == null:
		model = OnionModel.new()
		_pivot.add_child(model)
	if data.id != _class_id or player_color != _color:
		_class_id = data.id
		_color = player_color
		model.setup(data, player_color)
		model.set_weapons(data.main_hand, data.off_hand)
		model.set_facing(Vector3(0.0, 0.0, 1.0))
		model.set_moving(0.0)


## Plays the weapon swing of the main hand (feedback when a player readies up).
func cheer() -> void:
	if model != null:
		model.play_attack(false)


func _process(delta: float) -> void:
	if model == null or not is_visible_in_tree():
		return
	_t += delta
	model.set_facing(Vector3(sin(_t * SWAY_SPEED) * SWAY_AMOUNT, 0.0, 1.0))
