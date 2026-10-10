class_name LootBag
extends Node3D
## An item on the ground (GDD 10.1): a small leather bag with a tall, soft light beam in the
## item's rarity colour (white, green, blue, purple, orange, gold; Common is faint and short,
## so a good drop is visible from far away). Group &"loot_bags".
##
## Any living player walking within PICKUP_RADIUS sends it to the team loot
## ([method RunState.add_team_loot]; sparkle + the item's name floats up in the rarity
## colour). At wave end the remaining bags are banked too ([method collect_to_bank], called by
## WaveDirector.stop()), so loot is never lost. The bag bobs and spins gently.

## A living player this close (m, on the ground plane) picks the bag up.
const PICKUP_RADIUS := 1.0
const HOVER_HEIGHT := 0.14
const BOB_HEIGHT := 0.05
const BOB_SPEED := 2.6
const SPIN_SPEED := 1.4
## Seconds the bag and its beam take to pop in.
const POP_TIME := 0.35

## Beam height (m), width (m) and brightness by rarity (Common .. Artifact).
const BEAM_HEIGHT: Array[float] = [2.2, 3.6, 5.0, 6.5, 8.0, 9.0]
const BEAM_WIDTH: Array[float] = [0.45, 0.55, 0.6, 0.7, 0.8, 0.9]
const BEAM_INTENSITY: Array[float] = [0.28, 0.55, 0.7, 0.8, 0.9, 0.95]
const GROUND_GLOW_SIZE := 1.5

const LEATHER := Color(0.46, 0.29, 0.15)
const LEATHER_DARK := Color(0.3, 0.18, 0.09)
const ROPE := Color(0.85, 0.72, 0.4)

## Fixed-Y billboard quad: bright at the foot, fading upwards and towards the sides.
const _BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform vec4 beam_color : source_color = vec4(1.0);
uniform float intensity = 0.8;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], MODEL_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float across = clamp(1.0 - abs(UV.x - 0.5) * 2.0, 0.0, 1.0);
	float up = clamp(1.0 - UV.y, 0.0, 1.0);
	float core = pow(across, 1.7);
	ALBEDO = mix(beam_color.rgb, vec3(1.0), core * core * 0.35);
	ALPHA = core * pow(up, 1.4) * intensity;
}
"""

## Soft round glow on the ground under the bag.
const _GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform vec4 glow_color : source_color = vec4(1.0);
uniform float intensity = 0.6;
void fragment() {
	float d = clamp(1.0 - length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
	ALBEDO = glow_color.rgb;
	ALPHA = pow(d, 1.6) * intensity;
}
"""

var item: ItemInstance

var _collected := false
var _time := 0.0
var _age := 0.0
var _visual: Node3D
var _beam: MeshInstance3D
var _glow: MeshInstance3D

static var _beam_shader: Shader
static var _glow_shader: Shader
static var _materials: Dictionary[String, ShaderMaterial] = {}
static var _body_mesh: SphereMesh
static var _neck_mesh: CylinderMesh
static var _flare_mesh: CylinderMesh
static var _tie_mesh: TorusMesh
static var _gem_mesh: SphereMesh
static var _glow_quad: QuadMesh
static var _beam_meshes: Array[QuadMesh] = []


static func create(p_item: ItemInstance) -> LootBag:
	var b := LootBag.new()
	b.name = "LootBag"
	b.item = p_item
	b.add_to_group(&"loot_bags")
	b._build_visual()
	return b


## Beam / gem colour of an item rarity.
static func rarity_color(rarity: int) -> Color:
	return UiTheme.RARITY_COLORS[clampi(rarity, 0, UiTheme.RARITY_COLORS.size() - 1)]


func is_collected() -> bool:
	return _collected


## [param player] picks the bag up: the item goes to the team loot.
func collect(_player: Player = null) -> void:
	if _collected:
		return
	_collected = true
	RunState.add_team_loot(item)
	var pos := global_position if is_inside_tree() else position
	Vfx.pickup_sparkle(pos + Vector3.UP * 0.35)
	Vfx.floating_text(pos + Vector3.UP * 1.3, _item_title(), _color(), 1.15)
	_remove()


## Wave end: moves the item to RunState.team_loot and frees the bag.
func collect_to_bank() -> void:
	if _collected:
		return
	_collected = true
	RunState.add_team_loot(item)
	_remove()


# --- Frame update ------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _collected or not is_inside_tree():
		return
	var collector := _find_collector()
	if collector != null:
		collect(collector)


func _process(delta: float) -> void:
	if _visual == null:
		return
	_time += delta
	_age += delta
	_visual.position.y = HOVER_HEIGHT + sin(_time * BOB_SPEED) * BOB_HEIGHT
	_visual.rotate_y(SPIN_SPEED * delta)
	if _age <= POP_TIME + delta:
		var k := clampf(_age / POP_TIME, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - k, 3.0)
		_visual.scale = Vector3.ONE * (0.4 + 0.6 * eased)
		_beam.scale = Vector3(1.0, eased, 1.0)
		_glow.scale = Vector3.ONE * eased


## Nearest living player within PICKUP_RADIUS (null if none).
func _find_collector() -> Player:
	var here := global_position
	var best: Player = null
	var best_d := PICKUP_RADIUS * PICKUP_RADIUS
	for p in Enemy.cached_players(get_tree()):
		if not Enemy.is_living_player(p):
			continue
		var pos := p.global_position
		var dx := pos.x - here.x
		var dz := pos.z - here.z
		var d := dx * dx + dz * dz
		if d <= best_d:
			best_d = d
			best = p
	return best


func _remove() -> void:
	if is_in_group(&"loot_bags"):
		remove_from_group(&"loot_bags")
	set_physics_process(false)
	set_process(false)
	queue_free()


func _color() -> Color:
	return rarity_color(item.rarity if item != null else 0)


func _item_title() -> String:
	if item == null:
		return "Item"
	return item.display_name if item.display_name != "" else "%s item" % item.rarity_name()


# --- Look --------------------------------------------------------------------

func _build_visual() -> void:
	_ensure_shared_resources()
	var rarity := clampi(item.rarity if item != null else 0, 0, BEAM_HEIGHT.size() - 1)
	var color := _color()
	# Desynchronise neighbouring bags without touching the gameplay RNG.
	_time = float(get_instance_id() % 997) * 0.173

	_glow = MeshInstance3D.new()
	_glow.name = "GroundGlow"
	_glow.mesh = _glow_quad
	_glow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_glow.position = Vector3(0.0, 0.03, 0.0)
	_glow.material_override = _material("glow", rarity, color)
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)

	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	_beam.mesh = _beam_meshes[rarity]
	_beam.material_override = _material("beam", rarity, color)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)

	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.position = Vector3(0.0, HOVER_HEIGHT, 0.0)
	add_child(_visual)
	_add_part("Body", _body_mesh, Mats.toon(LEATHER), Vector3(0.0, 0.19, 0.0))
	_add_part("Neck", _neck_mesh, Mats.toon(LEATHER_DARK), Vector3(0.0, 0.4, 0.0))
	_add_part("Flare", _flare_mesh, Mats.toon(LEATHER), Vector3(0.0, 0.5, 0.0))
	_add_part("Tie", _tie_mesh, Mats.toon_plain(ROPE), Vector3(0.0, 0.4, 0.0))
	_add_part("Gem", _gem_mesh, Mats.glow(color, 1.6), Vector3(0.0, 0.2, 0.21))


func _add_part(part_name: String, mesh: Mesh, material: Material, pos: Vector3) -> void:
	var m := MeshInstance3D.new()
	m.name = part_name
	m.mesh = mesh
	m.material_override = material
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(m)


static func _material(kind: String, rarity: int, color: Color) -> ShaderMaterial:
	var key := "%s:%d" % [kind, rarity]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	if kind == "beam":
		m.shader = _beam_shader
		m.set_shader_parameter("beam_color", color)
		m.set_shader_parameter("intensity", BEAM_INTENSITY[rarity])
	else:
		m.shader = _glow_shader
		m.set_shader_parameter("glow_color", color)
		m.set_shader_parameter("intensity", 0.35 + 0.5 * BEAM_INTENSITY[rarity])
	_materials[key] = m
	return m


static func _ensure_shared_resources() -> void:
	if _body_mesh != null:
		return
	_beam_shader = Shader.new()
	_beam_shader.code = _BEAM_SHADER
	_glow_shader = Shader.new()
	_glow_shader.code = _GLOW_SHADER

	_body_mesh = SphereMesh.new()
	_body_mesh.radius = 0.22
	_body_mesh.height = 0.38
	_body_mesh.radial_segments = 14
	_body_mesh.rings = 8

	_neck_mesh = CylinderMesh.new()
	_neck_mesh.top_radius = 0.075
	_neck_mesh.bottom_radius = 0.12
	_neck_mesh.height = 0.13
	_neck_mesh.radial_segments = 10
	_neck_mesh.rings = 1

	_flare_mesh = CylinderMesh.new()
	_flare_mesh.top_radius = 0.15
	_flare_mesh.bottom_radius = 0.075
	_flare_mesh.height = 0.1
	_flare_mesh.radial_segments = 10
	_flare_mesh.rings = 1

	_tie_mesh = TorusMesh.new()
	_tie_mesh.inner_radius = 0.075
	_tie_mesh.outer_radius = 0.11
	_tie_mesh.rings = 10
	_tie_mesh.ring_segments = 5

	_gem_mesh = SphereMesh.new()
	_gem_mesh.radius = 0.05
	_gem_mesh.height = 0.1
	_gem_mesh.radial_segments = 8
	_gem_mesh.rings = 4

	_glow_quad = QuadMesh.new()
	_glow_quad.size = Vector2(GROUND_GLOW_SIZE, GROUND_GLOW_SIZE)

	_beam_meshes.clear()
	for r in BEAM_HEIGHT.size():
		var q := QuadMesh.new()
		q.size = Vector2(BEAM_WIDTH[r], BEAM_HEIGHT[r])
		q.center_offset = Vector3(0.0, BEAM_HEIGHT[r] * 0.5, 0.0)
		_beam_meshes.append(q)
