class_name Arena
extends Node3D
## The battlefield (owned by the "visuals" module): an Elwynn-like forest clearing (GDD 13).
## Flat ground on the XZ plane, centred on the origin, enclosed by a low stone wall with tall
## invisible collision (layer 1 "world"). Screen-up is -Z. Contains:
##   entities: Node3D  – parent for players, enemies, projectiles, pickups and VFX.
##   camera:   CameraRig
## Everything (ground shader, walls, trees, props, light, environment) is built in code by
## [method create]; decoration lives outside the playable rectangle so the camera never
## shows the void.

## Playable area size in metres (x = width, y = depth along Z).
const SIZE := Vector2(34.0, 22.0)
## Collision walls: height and thickness (metres); the inner faces sit on the bounds.
const WALL_HEIGHT := 8.0
const WALL_THICKNESS := 4.0
## How far beyond the walls the camera is allowed to look (see CameraRig).
const VIEW_MARGIN := 8.0
## How far beyond the walls the forest decoration extends.
const DECOR_MARGIN := 24.0
const DECOR_SEED := 20240611

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
var walls: StaticBody3D
var sun: DirectionalLight3D
var world_environment: WorldEnvironment
var ground: MeshInstance3D
## Dirt patches inside the arena: (x, z, radius, noise seed).
var dirt_patches: Array[Vector4] = []


static func create() -> Arena:
	var arena := Arena.new()
	arena.name = "Arena"
	arena._build()
	return arena


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


## Playable rectangle on the XZ plane (Rect2.position = min x / min z).
func get_bounds() -> Rect2:
	return Rect2(-SIZE / 2.0, SIZE)


## Ground rectangle the camera may show (bounds + VIEW_MARGIN).
func get_view_rect() -> Rect2:
	return get_bounds().grow(VIEW_MARGIN)


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


# --- Building ----------------------------------------------------------------

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = DECOR_SEED
	_build_environment()
	_build_ground(rng)
	_build_walls()
	var decor := ArenaDecor.build(self, rng)
	decor.name = "Decor"
	add_child(decor)
	entities = Node3D.new()
	entities.name = "Entities"
	add_child(entities)
	camera = CameraRig.new()
	add_child(camera)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.56, 0.74, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.66, 0.8)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.88)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = env
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -128.0, 0.0)
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = 0.92
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 75.0
	add_child(sun)


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
	mat.set_shader_parameter("arena_half", SIZE / 2.0)
	mat.set_shader_parameter("road", Vector2(0.0, 1.7))
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
	for box in wall_boxes():
		var shape := BoxShape3D.new()
		shape.size = box.size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = box.get_center()
		walls.add_child(cs)
	var visual := ArenaDecor.build_wall_visual(get_bounds(), DECOR_SEED)
	walls.add_child(visual)


## The four collision boxes (AABBs in arena space). Their inner faces lie exactly on the
## playable bounds; they overlap at the corners so nothing can slip out.
static func wall_boxes() -> Array[AABB]:
	var half := SIZE / 2.0
	var t := WALL_THICKNESS
	var h := WALL_HEIGHT
	var y0 := -1.0
	var out: Array[AABB] = []
	out.append(AABB(Vector3(-half.x - t, y0, -half.y - t), Vector3(SIZE.x + 2.0 * t, h, t)))   # north
	out.append(AABB(Vector3(-half.x - t, y0, half.y), Vector3(SIZE.x + 2.0 * t, h, t)))       # south
	out.append(AABB(Vector3(-half.x - t, y0, -half.y - t), Vector3(t, h, SIZE.y + 2.0 * t)))   # west
	out.append(AABB(Vector3(half.x, y0, -half.y - t), Vector3(t, h, SIZE.y + 2.0 * t)))        # east
	return out
