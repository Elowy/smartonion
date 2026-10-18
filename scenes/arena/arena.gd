class_name Arena
extends Node3D
## The battlefield (owned by the "visuals" module): an Elwynn-like forest clearing (GDD 13).
## Flat ground on the XZ plane, centred on the origin, enclosed by a low stone wall with tall
## invisible collision (layer 1 "world"). Screen-up is -Z. Contains:
##   entities:      Node3D  – parent for players, enemies, projectiles, pickups and VFX.
##   camera:        CameraRig
##   spirit_healer: SpiritHealer – part of the level at SPIRIT_HEALER_POINT (GDD 1): ghosts
##                  standing in its circle come back at full HP (null when the arena was built
##                  without one: hardcore, the dungeon).
## Everything (ground shader, walls, trees, props, light, environment) is built in code by
## [method create]; decoration lives outside the playable rectangle so the camera never
## shows the void.
## M6b: [method create] takes an optional [EnvironmentData] (the run's arena environment: palette,
## decor set, hazard id); without one the arena is the forest clearing it always was. The playable
## SIZE is the same for every environment.
## M6b dungeon: [method enter_dungeon_layout] swaps the scenery (environment, sun, ground, walls,
## decor) for a small DUNGEON_SIZE room in the run's palette without a Spirit Healer – the entities,
## the camera and Arena.current stay, so the heroes never leave the tree – and
## [method leave_dungeon_layout] puts the clearing back. The playable rectangle of the layout in use
## is [member play_size] ([method get_bounds]); SIZE stays the clearing's size for the static
## readers that only fall back on it.

## Playable area size in metres (x = width, y = depth along Z).
const SIZE := Vector2(34.0, 22.0)
## The dungeon room's playable size (GDD 16.1).
const DUNGEON_SIZE := Vector2(24.0, 14.0)
## Collision walls: height and thickness (metres); the inner faces sit on the bounds.
const WALL_HEIGHT := 8.0
const WALL_THICKNESS := 4.0
## How far beyond the walls the camera is allowed to look (see CameraRig).
const VIEW_MARGIN := 8.0
## Smaller margin on the near (south, +Z) side: the camera looks from the south, so
## showing less of the outside there keeps more of the arena on screen.
const VIEW_MARGIN_SOUTH := 4.0
## How far beyond the walls the forest decoration extends.
const DECOR_MARGIN := 24.0
const DECOR_SEED := 20240611
## Where the Spirit Healer stands: the arena centre (no decor or props inside the walls).
const SPIRIT_HEALER_POINT := Vector3.ZERO

const _GROUND_CODE := """
shader_type spatial;
render_mode cull_back;

uniform vec4 grass_dark : source_color = vec4(0.2, 0.4, 0.12, 1.0);
uniform vec4 grass_mid : source_color = vec4(0.33, 0.56, 0.17, 1.0);
uniform vec4 grass_light : source_color = vec4(0.5, 0.7, 0.23, 1.0);
uniform vec4 grass_warm : source_color = vec4(0.66, 0.7, 0.26, 1.0);
uniform vec4 dirt_light : source_color = vec4(0.62, 0.48, 0.3, 1.0);
uniform vec4 dirt_dark : source_color = vec4(0.42, 0.3, 0.18, 1.0);
uniform vec4 patches[8];
uniform int patch_count = 0;
uniform vec2 arena_half = vec2(17.0, 11.0);
uniform vec2 road = vec2(0.0, 1.8);
varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float big = fbm(p * 0.05);
	float mid = fbm(p * 0.17 + 3.0);
	float stroke = noise(vec2(p.x * 0.8 + p.y * 0.35, p.y * 2.4 - p.x * 0.2));
	vec3 g = mix(grass_dark.rgb, grass_mid.rgb, smoothstep(0.26, 0.52, big));
	g = mix(g, grass_light.rgb, smoothstep(0.5, 0.74, big + (mid - 0.5) * 0.45) * 0.85);
	g = mix(g, grass_warm.rgb, smoothstep(0.64, 0.82, mid) * 0.3);
	g *= 0.92 + 0.14 * stroke;
	// Clover-like round speckles (one jittered dot per cell, sparse, varied size).
	vec2 cell = floor(p * 2.2);
	vec2 dot_center = cell + 0.25 + 0.5 * vec2(hash(cell), hash(cell + 7.1));
	float dot_r = 0.07 + 0.17 * hash(cell + 3.3);
	float speck = step(0.86, hash(cell + 1.7)) * (1.0 - smoothstep(dot_r * 0.5, dot_r, length(p * 2.2 - dot_center)));
	speck *= smoothstep(0.3, 0.6, mid + 0.25 * hash(cell + 4.4));
	g = mix(g, mix(grass_light.rgb, grass_warm.rgb, hash(cell + 9.0)) * 1.04, speck * 0.28);
	// Slightly darker, lusher grass along the inside of the walls.
	vec2 edge = arena_half - abs(p);
	float inside = step(0.0, min(edge.x, edge.y));
	g *= 1.0 - inside * (1.0 - smoothstep(0.0, 1.8, min(edge.x, edge.y))) * 0.22;
	// Dirt patches with noisy edges.
	float dirt = 0.0;
	float rim = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= patch_count) {
			break;
		}
		vec4 pt = patches[i];
		float d = length((p - pt.xy) * vec2(1.0, 1.25)) / pt.z;
		d += (fbm(p * 0.75 + pt.w) - 0.5) * 0.6;
		dirt = max(dirt, 1.0 - smoothstep(0.8, 0.9, d));
		rim = max(rim, smoothstep(0.75, 0.88, d) * (1.0 - smoothstep(0.9, 1.05, d)));
	}
	// Dirt road leaving through the north gate.
	float rx = road.x + sin(p.y * 0.11) * 2.2 * smoothstep(-arena_half.y, -arena_half.y - 8.0, p.y);
	float rd = abs(p.x - rx) / road.y + (fbm(p * 0.55) - 0.5) * 0.45;
	float on_road = (1.0 - smoothstep(0.8, 1.0, rd)) * (1.0 - smoothstep(-arena_half.y - 1.0, -arena_half.y + 0.2, p.y));
	rim = max(rim, smoothstep(0.75, 0.95, rd) * (1.0 - smoothstep(0.95, 1.2, rd)) * (1.0 - smoothstep(-arena_half.y - 1.0, -arena_half.y + 0.2, p.y)));
	dirt = max(dirt, on_road);
	vec3 dc = mix(dirt_dark.rgb, dirt_light.rgb, smoothstep(0.25, 0.7, mid) * 0.75 + stroke * 0.25);
	vec2 pc = floor(p * 3.0);
	vec2 pcen = pc + 0.3 + 0.4 * vec2(hash(pc + 2.0), hash(pc + 5.0));
	float pr = 0.06 + 0.1 * hash(pc + 8.0);
	float pd = length(p * 3.0 - pcen);
	float pebble = step(0.84, hash(pc)) * (1.0 - smoothstep(pr * 0.7, pr, pd));
	float pebble_shadow = step(0.84, hash(pc)) * (1.0 - smoothstep(pr, pr * 1.5, length(p * 3.0 - pcen - vec2(0.05, 0.06))));
	dc *= 1.0 - 0.18 * max(pebble_shadow - pebble, 0.0);
	dc = mix(dc, mix(dirt_light.rgb, vec3(0.74, 0.7, 0.62), 0.55) * 1.08, pebble * 0.75);
	g *= 1.0 - rim * 0.25;
	ALBEDO = mix(g, dc, dirt);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += ndl * mix(1.0, ATTENUATION, 0.72) * LIGHT_COLOR / PI;
}
"""

static var current: Arena

var entities: Node3D
var camera: CameraRig
var spirit_healer: SpiritHealer
var walls: StaticBody3D
## The environment this arena was built from (never null; EnvironmentData.new() = the forest).
var environment: EnvironmentData
var sun: DirectionalLight3D
var world_environment: WorldEnvironment
var ground: MeshInstance3D
## The decoration around the playable rectangle (child "Decor").
var decor: Node3D
## Dirt patches inside the arena: (x, z, radius, noise seed).
var dirt_patches: Array[Vector4] = []
## Playable size of the layout in use: SIZE, DUNGEON_SIZE while a dungeon layout is up.
var play_size := SIZE
## A dungeon layout replaced the clearing's scenery ([method enter_dungeon_layout]).
var in_dungeon_layout := false

var _with_spirit_healer := true
## The clearing's layout while a dungeon layout is up: size, environment, scenery nodes, dirt
## patches, Spirit Healer and its process mode.
var _home: Dictionary = {}


## The arena of [param p_environment] (null = the forest clearing: EnvironmentData's defaults).
## [param p_spirit_healer] false builds it without the Spirit Healer ([member spirit_healer] stays
## null – the hardcore mode uses this; every consumer of the healer is null-safe). [param p_size] is
## the playable size (default SIZE; DUNGEON_SIZE builds a stand-alone dungeon room – the run's dungeon
## swaps the layout of its own arena instead, see [method enter_dungeon_layout]).
static func create(p_environment: EnvironmentData = null, p_spirit_healer: bool = true,
		p_size: Vector2 = SIZE) -> Arena:
	var arena := Arena.new()
	arena.name = "Arena"
	arena.environment = p_environment if p_environment != null else EnvironmentData.new()
	arena._with_spirit_healer = p_spirit_healer
	arena.play_size = p_size
	arena._build()
	return arena


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


## Playable rectangle on the XZ plane (Rect2.position = min x / min z).
func get_bounds() -> Rect2:
	return Rect2(-play_size / 2.0, play_size)


## Ground rectangle the camera may show (bounds + VIEW_MARGIN, VIEW_MARGIN_SOUTH at +Z).
func get_view_rect() -> Rect2:
	return get_bounds().grow_individual(VIEW_MARGIN, VIEW_MARGIN, VIEW_MARGIN, VIEW_MARGIN_SOUTH)


## Rectangle covered by decoration (bounds + DECOR_MARGIN).
func get_decor_rect() -> Rect2:
	return get_bounds().grow(DECOR_MARGIN)


## [param count] spawn points near the centre, spread out, one per player.
func get_player_spawn_points(count: int) -> Array[Vector3]:
	return spawn_points(count)


## Spawn layout used by [method get_player_spawn_points]: centre for one player, otherwise
## a circle of radius 1.8 m (2 = left / right, 4 = diamond).
static func spawn_points(count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if count <= 0:
		return out
	if count == 1:
		out.append(Vector3.ZERO)
		return out
	for i in count:
		var a := PI + TAU * float(i) / float(count)
		out.append(Vector3(cos(a) * 1.8, 0.0, sin(a) * 1.8))
	return out


## Random point inside the bounds keeping [param margin] metres from the walls.
func random_point(rng: RandomNumberGenerator, margin: float = 1.5) -> Vector3:
	var b := get_bounds().grow(-margin)
	return Vector3(rng.randf_range(b.position.x, b.end.x), 0.0, rng.randf_range(b.position.y, b.end.y))


## Clamps a world position into the playable area.
func clamp_point(p: Vector3, margin: float = 0.5) -> Vector3:
	var b := get_bounds().grow(-margin)
	return Vector3(clampf(p.x, b.position.x, b.end.x), p.y, clampf(p.z, b.position.y, b.end.y))


## True when [param p] (XZ) is inside the playable area shrunk by [param margin].
func is_inside(p: Vector3, margin: float = 0.0) -> bool:
	return get_bounds().grow(-margin).has_point(Vector2(p.x, p.z))


# --- Dungeon layout ------------------------------------------------------------

## Swaps the clearing's scenery for a dungeon room of [param p_size] in the palette of
## [param p_environment] (null = the one the arena has): the clearing's environment, sun, ground,
## walls and decor leave the tree (kept for [method leave_dungeon_layout]), new ones of the small room
## take their place, and the Spirit Healer is switched off ([member spirit_healer] is null meanwhile –
## every consumer is null-safe). The entities root, the camera and Arena.current stay as they are, so
## the heroes and everything else standing in `entities` keep working. Does nothing in a dungeon
## layout already. The decor uses its own generator (DECOR_SEED), never RunState.rng.
func enter_dungeon_layout(p_environment: EnvironmentData = null, p_size: Vector2 = DUNGEON_SIZE) -> void:
	if in_dungeon_layout:
		return
	_home = {
		"size": play_size, "environment": environment, "world_environment": world_environment,
		"sun": sun, "ground": ground, "walls": walls, "decor": decor, "dirt_patches": dirt_patches,
		"healer": spirit_healer,
		"healer_mode": spirit_healer.process_mode if spirit_healer != null else Node.PROCESS_MODE_INHERIT,
	}
	for node: Node in [world_environment, sun, ground, walls, decor]:
		if node != null and node.get_parent() == self:
			remove_child(node)
	if spirit_healer != null and is_instance_valid(spirit_healer):
		spirit_healer.process_mode = Node.PROCESS_MODE_DISABLED
		spirit_healer.visible = false
	spirit_healer = null
	play_size = p_size
	if p_environment != null:
		environment = p_environment
	dirt_patches = []
	in_dungeon_layout = true
	var rng := RandomNumberGenerator.new()
	rng.seed = DECOR_SEED + 17
	_build_environment()
	_build_ground(rng)
	_build_walls()
	decor = _build_decor(rng)
	decor.name = "Decor"
	add_child(decor)


## Puts the clearing back ([method enter_dungeon_layout] undone): the dungeon room's scenery is
## removed first (never two WorldEnvironments in the tree), the Spirit Healer wakes up again.
func leave_dungeon_layout() -> void:
	if not in_dungeon_layout:
		return
	for node: Node in [world_environment, sun, ground, walls, decor]:
		_discard(node)
	in_dungeon_layout = false
	play_size = _home["size"]
	environment = _home["environment"]
	world_environment = _home["world_environment"]
	sun = _home["sun"]
	ground = _home["ground"]
	walls = _home["walls"]
	decor = _home["decor"]
	dirt_patches = _home["dirt_patches"]
	for node: Node in [world_environment, sun, ground, walls, decor]:
		if node != null and is_instance_valid(node):
			add_child(node)
	var healer: SpiritHealer = _home["healer"]
	if healer != null and is_instance_valid(healer):
		healer.process_mode = _home["healer_mode"]
		spirit_healer = healer
	_home = {}


## The clearing's scenery is parked outside the tree while a dungeon layout is up: it is freed
## with the arena.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and in_dungeon_layout:
		for key: String in ["world_environment", "sun", "ground", "walls", "decor"]:
			var node: Node = _home.get(key)
			if node != null and is_instance_valid(node) and node.get_parent() == null:
				node.free()


static func _discard(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()


# --- Building ----------------------------------------------------------------

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = DECOR_SEED
	_build_environment()
	_build_ground(rng)
	_build_walls()
	decor = _build_decor(rng)
	decor.name = "Decor"
	add_child(decor)
	if _with_spirit_healer:
		# Before the entities: it processes first, so a ghost's cast bar shows this tick's channel.
		spirit_healer = SpiritHealer.create()
		spirit_healer.position = SPIRIT_HEALER_POINT
		add_child(spirit_healer)
	entities = Node3D.new()
	entities.name = "Entities"
	add_child(entities)
	camera = CameraRig.new()
	add_child(camera)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = environment.sky_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = environment.ambient_color
	env.ambient_light_energy = environment.ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = environment.fog_color
	env.fog_density = environment.fog_density
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = environment.glow_intensity
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = environment.saturation
	env.adjustment_contrast = environment.contrast
	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = env
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = environment.sun_rotation
	sun.light_color = environment.sun_color
	sun.light_energy = environment.sun_energy
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 75.0
	add_child(sun)


## The decoration around the playable rectangle for [member environment]'s decor set
## (EnvironmentData.decor_id): [method ArenaThemes.build] picks the set (cemetery, swamp, volcano,
## ice_cave) and builds the forest ([method ArenaDecor.build]) for every id it does not know.
func _build_decor(rng: RandomNumberGenerator) -> Node3D:
	return ArenaThemes.build(self, rng)


func _build_ground(rng: RandomNumberGenerator) -> void:
	dirt_patches.clear()
	var spots: Array[Vector2] = [Vector2(-9.5, -4.0), Vector2(8.5, 4.5), Vector2(1.5, -7.0),
		Vector2(-6.0, 6.5), Vector2(12.5, -6.0)]
	for s in spots:
		var jitter := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.8, 0.8))
		dirt_patches.append(Vector4(s.x + jitter.x, s.y + jitter.y, rng.randf_range(1.6, 2.8), rng.randf_range(0.0, 50.0)))
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = _GROUND_CODE
	mat.shader = sh
	var arr := PackedVector4Array()
	for p in dirt_patches:
		arr.append(p)
	while arr.size() < 8:
		arr.append(Vector4(0, 0, 0.001, 0))
	mat.set_shader_parameter("patches", arr)
	mat.set_shader_parameter("patch_count", dirt_patches.size())
	mat.set_shader_parameter("arena_half", play_size / 2.0)
	# (A road width of ~0 makes no road: the shader divides the distance to the road by it.)
	mat.set_shader_parameter("road", Vector2(0.0, environment.road_width if environment.has_road else 0.0001))
	mat.set_shader_parameter("grass_dark", environment.grass_dark)
	mat.set_shader_parameter("grass_mid", environment.grass_mid)
	mat.set_shader_parameter("grass_light", environment.grass_light)
	mat.set_shader_parameter("grass_warm", environment.grass_warm)
	mat.set_shader_parameter("dirt_light", environment.dirt_light)
	mat.set_shader_parameter("dirt_dark", environment.dirt_dark)
	var plane := PlaneMesh.new()
	plane.size = get_decor_rect().grow(40.0).size
	ground = MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


func _build_walls() -> void:
	walls = StaticBody3D.new()
	walls.name = "Walls"
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)
	for box in wall_boxes_for(play_size):
		var shape := BoxShape3D.new()
		shape.size = box.size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = box.get_center()
		walls.add_child(cs)
	var visual := ArenaDecor.build_wall_visual(get_bounds(), DECOR_SEED, environment.wall_tint)
	walls.add_child(visual)


## The four collision boxes (AABBs in arena space). Their inner faces lie exactly on the
## playable bounds; they overlap at the corners so nothing can slip out.
static func wall_boxes() -> Array[AABB]:
	return wall_boxes_for(SIZE)


## [method wall_boxes] of a playable rectangle of [param p_size] (the dungeon room's walls).
static func wall_boxes_for(p_size: Vector2) -> Array[AABB]:
	var half := p_size / 2.0
	var t := WALL_THICKNESS
	var h := WALL_HEIGHT
	var y0 := -1.0
	var out: Array[AABB] = []
	out.append(AABB(Vector3(-half.x - t, y0, -half.y - t), Vector3(p_size.x + 2.0 * t, h, t)))   # north
	out.append(AABB(Vector3(-half.x - t, y0, half.y), Vector3(p_size.x + 2.0 * t, h, t)))       # south
	out.append(AABB(Vector3(-half.x - t, y0, -half.y - t), Vector3(t, h, p_size.y + 2.0 * t)))   # west
	out.append(AABB(Vector3(half.x, y0, -half.y - t), Vector3(t, h, p_size.y + 2.0 * t)))        # east
	return out
