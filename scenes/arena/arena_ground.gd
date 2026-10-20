class_name ArenaGround
extends RefCounted
## The arena's ground shader, one look per environment (M7b VIS-ENV; GDD 13 / 16.1): the forest's grass
## and dirt, the Cemetery's dark soil and moss with a flagstone path, the Swamp's wet mud and puddles,
## the Volcano's cracked basalt with pulsing lava seams, the Ice Cave's packed snow and glossy ice, and
## the dungeon's crypt tiles. Every look reads the same palette uniforms (EnvironmentData's grass_* /
## dirt_* colours, the dirt patches, the road) and paints them its own way, so the data stays the
## palette and the code the surface.
##
## One compiled shader per look (cached for the whole process): the heavy noise only runs for the look
## that needs it, the fragment cost stays about the forest's. Animation runs on TIME in the shader
## (water sheen, lava pulse, ice glints): no script touches the material while the game runs, no
## instance uniforms, nothing for the physics tick to pay. [method Arena._build_ground] builds the
## material through [method make_material] / [method apply_look].

const FOREST := &"forest"
const CEMETERY := &"cemetery"
const SWAMP := &"swamp"
const VOLCANO := &"volcano"
const ICE_CAVE := &"ice_cave"
const CRYPT := &"crypt"
const LOOKS: Array[StringName] = [FOREST, CEMETERY, SWAMP, VOLCANO, ICE_CAVE, CRYPT]

## The sheen / glow colour a look passes to its shader (the shader's `accent` uniform).
const LAVA_GLOW := Color(1.0, 0.36, 0.06)
const SWAMP_SHEEN := Color(0.6, 0.9, 0.78)
const ICE_GLINT := Color(0.72, 0.92, 1.0)
const CRYPT_TORCH := Color(1.0, 0.56, 0.2)
## The most lava vents / crypt torches a ground shader lights (array sizes of its uniforms).
const MAX_VENTS := 6
const MAX_TORCHES := 8

static var _shaders: Dictionary[StringName, Shader] = {}


## The look of [param env]'s ground: the decor set id picks it (the forest for an id nobody knows), the
## dungeon room always gets the crypt.
static func look_for(env: EnvironmentData, in_dungeon: bool) -> StringName:
	if in_dungeon:
		return CRYPT
	match env.decor_id:
		&"cemetery":
			return CEMETERY
		&"swamp":
			return SWAMP
		&"volcano":
			return VOLCANO
		&"ice_cave":
			return ICE_CAVE
	return FOREST


## The shader source of [param look] (tests read it; the forest's for an unknown look).
static func code_for(look: StringName) -> String:
	var body := _FOREST_BODY
	match look:
		CEMETERY:
			body = _CEMETERY_BODY
		SWAMP:
			body = _SWAMP_BODY
		VOLCANO:
			body = _VOLCANO_BODY
		ICE_CAVE:
			body = _ICE_BODY
		CRYPT:
			body = _CRYPT_BODY
	return _HEAD + body + _LIGHT


## A new ground material of [param look] (the shader is shared, the material is the arena's own).
static func make_material(look: StringName) -> ShaderMaterial:
	var key: StringName = look if look in LOOKS else FOREST
	var shader: Shader = _shaders.get(key)
	if shader == null:
		shader = Shader.new()
		shader.code = code_for(key)
		_shaders[key] = shader
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


## The uniforms only some looks have: the sun direction (for the sheen), the accent colour, the lava
## vents of the arena's rectangle [param bounds], the crypt's torches. Harmless on the others (a
## parameter a shader does not declare is ignored).
static func apply_look(m: ShaderMaterial, look: StringName, env: EnvironmentData, bounds: Rect2) -> void:
	var sun_basis := Basis.from_euler(Vector3(deg_to_rad(env.sun_rotation.x), deg_to_rad(env.sun_rotation.y),
			deg_to_rad(env.sun_rotation.z)))
	# (A directional light shines along its -Z axis: the vector towards the sun is +Z.)
	m.set_shader_parameter(&"sun_dir", (sun_basis * Vector3(0.0, 0.0, 1.0)).normalized())
	match look:
		SWAMP:
			# The sky the puddles mirror: a pale marsh green.
			m.set_shader_parameter(&"accent", SWAMP_SHEEN)
		VOLCANO:
			m.set_shader_parameter(&"accent", LAVA_GLOW)
			var vents := PackedVector2Array()
			for v in ArenaThemes.vents_in(bounds):
				vents.append(Vector2(v.x, v.z))
			m.set_shader_parameter(&"vent_count", vents.size())
			while vents.size() < MAX_VENTS:
				vents.append(Vector2(1000.0, 1000.0))
			m.set_shader_parameter(&"vents", vents)
		ICE_CAVE:
			m.set_shader_parameter(&"accent", ICE_GLINT)
		CRYPT:
			m.set_shader_parameter(&"accent", CRYPT_TORCH)
			var spots := ArenaCrypt.torch_points(bounds)
			var packed := PackedVector4Array()
			for s in spots:
				packed.append(Vector4(s.x, s.z, 5.5, 0.0))
			m.set_shader_parameter(&"torch_count", mini(packed.size(), MAX_TORCHES))
			while packed.size() < MAX_TORCHES:
				packed.append(Vector4(1000.0, 1000.0, 1.0, 0.0))
			m.set_shader_parameter(&"torches", packed.slice(0, MAX_TORCHES))


# =================================================================================================
# Shader source
# =================================================================================================

## Uniforms, noise and the helpers every look shares. The first uniforms are what the forest always had
## (tests read them); the dirt patches and the road are painted by each look as it likes.
const _HEAD := """
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
uniform vec3 sun_dir = vec3(0.4, 0.7, 0.5);
varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
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
float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}

// Slightly darker along the inside of the walls (0.78 at the wall .. 1 from 1.8 m in).
float wall_shade(vec2 p) {
	vec2 edge = arena_half - abs(p);
	float inside = step(0.0, min(edge.x, edge.y));
	return 1.0 - inside * (1.0 - smoothstep(0.0, 1.8, min(edge.x, edge.y))) * 0.22;
}

// The dirt patches: coverage 0..1, the soft rim around their edge and how deep inside one the point is.
float patch_cover(vec2 p, out float rim, out float core) {
	float cover = 0.0;
	rim = 0.0;
	core = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= patch_count) {
			break;
		}
		vec4 pt = patches[i];
		float d = length((p - pt.xy) * vec2(1.0, 1.25)) / pt.z;
		if (d > 1.5) {
			continue;  // far from this patch: its edge noise (at most +-0.3) cannot reach here, skip the fbm
		}
		d += (fbm3(p * 0.75 + pt.w) - 0.5) * 0.6;
		cover = max(cover, 1.0 - smoothstep(0.8, 0.9, d));
		rim = max(rim, smoothstep(0.75, 0.88, d) * (1.0 - smoothstep(0.9, 1.05, d)));
		core = max(core, 1.0 - smoothstep(0.1, 0.8, d));
	}
	return cover;
}

// x of the road's centre line at depth z (ArenaDecor.road_x), the road's coverage and its rim.
float road_cx(float z) {
	return road.x + sin(z * 0.11) * 2.2 * smoothstep(-arena_half.y, -arena_half.y - 8.0, z);
}
float road_cover(vec2 p, out float rim) {
	float rd = abs(p.x - road_cx(p.y)) / road.y + (fbm3(p * 0.55) - 0.5) * 0.45;
	float gate = 1.0 - smoothstep(-arena_half.y - 1.0, -arena_half.y + 0.2, p.y);
	rim = smoothstep(0.75, 0.95, rd) * (1.0 - smoothstep(0.95, 1.2, rd)) * gate;
	return (1.0 - smoothstep(0.8, 1.0, rd)) * gate;
}

// Blinn highlight of a perturbed world normal against the sun (the water / ice sheen).
float sheen(vec3 n_world, float shininess, vec3 view_vec, mat4 view_matrix) {
	vec3 nv = normalize((view_matrix * vec4(normalize(n_world), 0.0)).xyz);
	vec3 l = normalize((view_matrix * vec4(sun_dir, 0.0)).xyz);
	return pow(clamp(dot(nv, normalize(l + view_vec)), 0.0, 1.0), shininess);
}

// A smooth, slowly moving surface normal (sums of sines: no grid look, unlike a noise gradient);
// [amp] is the slope, [scale] the wave frequency, [speed] how fast it moves.
vec3 wavy_normal(vec2 p, float scale, float speed, float amp) {
	vec2 q = p * scale;
	float a = sin(q.x * 2.3 + TIME * speed + sin(q.y * 1.3 + TIME * speed * 0.3));
	float b = sin(q.y * 2.9 - TIME * speed * 0.8 + sin(q.x * 1.1));
	float c = sin((q.x + q.y) * 4.1 + TIME * speed * 1.4);
	return vec3((a * 0.6 + c * 0.4) * amp, 1.0, (b * 0.6 - c * 0.4) * amp);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
"""

## The sun lights the ground (shadows at 72 % strength: the clearing never goes black under the trees).
const _LIGHT := """
void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += ndl * mix(1.0, ATTENUATION, 0.72) * LIGHT_COLOR / PI;
}
"""

## The clearing as it always was (grass, clover speckles, dirt patches, the road north of the gate) plus
## a slow dappled light drifting over it.
const _FOREST_BODY := """
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
	// Sunlight filtering through the canopy: two slow, soft patches of brighter grass drifting past.
	float dapple = noise(p * 0.34 + vec2(TIME * 0.035, TIME * 0.02)) * noise(p * 0.21 - vec2(TIME * 0.02, 0.0) + 11.0);
	g *= 0.96 + 0.2 * smoothstep(0.12, 0.34, dapple);
	g *= wall_shade(p);
	// Dirt patches with noisy edges.
	float rim;
	float core;
	float dirt = patch_cover(p, rim, core);
	// Dirt road leaving through the north gate.
	float road_rim;
	float on_road = road_cover(p, road_rim);
	rim = max(rim, road_rim);
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
"""

## Dark churned soil with moss and lichen creeping over it, bare gravel patches, flagstones on the path
## through the gate.
const _CEMETERY_BODY := """
void fragment() {
	vec2 p = wpos.xz;
	float big = fbm(p * 0.06);
	float mid = fbm3(p * 0.28 + 5.0);
	float fine = noise(p * 2.4);
	float grit = noise(p * 7.0);
	// Churned, dark soil.
	vec3 soil = mix(grass_dark.rgb, grass_mid.rgb, smoothstep(0.3, 0.7, big));
	soil *= 0.82 + 0.3 * fine + 0.12 * (grit - 0.5);
	// Moss and lichen in blotches.
	float det = fbm3(p * 1.15 + 2.0);
	float m = smoothstep(0.46, 0.62, mid + (big - 0.5) * 0.5 + (det - 0.44) * 0.55);
	vec3 moss = mix(grass_light.rgb, grass_warm.rgb, smoothstep(0.35, 0.85, fine + 0.3 * mid));
	moss *= 0.82 + 0.3 * grit;
	vec3 g = mix(soil, moss, m * 0.9);
	// Pale specks (petals, bone dust).
	vec2 cell = floor(p * 3.0);
	vec2 c = cell + 0.2 + 0.6 * hash2(cell);
	float dot_r = 0.04 + 0.07 * hash(cell + 3.0);
	float speck = step(0.9, hash(cell + 1.3)) * (1.0 - smoothstep(dot_r * 0.5, dot_r, length(p * 3.0 - c)));
	g = mix(g, dirt_light.rgb * 1.2, speck * 0.55);
	g *= wall_shade(p);
	// Bare, trodden gravel.
	float rim;
	float core;
	float dirt = patch_cover(p, rim, core);
	vec3 dc = mix(dirt_dark.rgb, dirt_light.rgb, 0.25 + 0.5 * smoothstep(0.3, 0.7, fbm3(p * 0.5 + 2.0)));
	dc *= 0.92 + 0.14 * grit;
	vec2 pc = floor(p * 4.0);
	vec2 pcen = pc + 0.25 + 0.5 * hash2(pc + 3.0);
	float pr = 0.07 + 0.08 * hash(pc + 8.0);
	float pebble = step(0.78, hash(pc)) * (1.0 - smoothstep(pr * 0.7, pr, length(p * 4.0 - pcen)));
	dc = mix(dc, dirt_light.rgb * 1.25, pebble * 0.7);
	g *= 1.0 - rim * 0.3;
	vec3 col = mix(g, dc, dirt);
	// Flagstones, off-set rows, moss in the joints.
	float road_rim;
	float on_road = road_cover(p, road_rim);
	vec2 q = vec2((p.x - road_cx(p.y)) / 0.9, p.y / 0.75);
	q.x += floor(q.y) * 0.5;
	vec2 id = floor(q);
	vec2 f = fract(q);
	float joint = 1.0 - smoothstep(0.0, 0.08, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	vec3 slab = mix(dirt_dark.rgb, dirt_light.rgb, 0.3 + 0.55 * hash(id)) * (0.9 + 0.2 * noise(p * 6.0));
	slab = mix(slab, moss, 0.4 * smoothstep(0.5, 0.8, noise(p * 1.6 + 4.0)));
	slab = mix(slab, soil * 0.6, joint * 0.8);
	col = mix(col, slab, on_road);
	col *= 1.0 - road_rim * 0.3;
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""

## Wet mud and algae with irregular puddles that mirror the sky: a slow shimmer on the water, a darker
## wet edge. (The bog pools of the hazard are the dark ovals with the lime rim: the puddles here never
## go that dark.)
const _SWAMP_BODY := """
uniform vec4 accent : source_color = vec4(0.7, 0.8, 0.6, 1.0);

void fragment() {
	vec2 p = wpos.xz;
	float big = fbm(p * 0.055);
	float mid = fbm3(p * 0.22 + 9.0);
	float fine = noise(p * 2.2);
	vec3 mud = mix(grass_dark.rgb, grass_mid.rgb, smoothstep(0.25, 0.65, big));
	mud *= 0.84 + 0.26 * fine;
	// Algae film and duckweed.
	float alg = smoothstep(0.5, 0.72, mid + (big - 0.5) * 0.4);
	vec3 weed = mix(grass_light.rgb, grass_warm.rgb, smoothstep(0.3, 0.9, fine));
	vec3 g = mix(mud, weed, alg * 0.8);
	g *= wall_shade(p);
	// Peat banks.
	float rim;
	float core;
	float dirt = patch_cover(p, rim, core);
	vec3 dc = mix(dirt_dark.rgb, dirt_light.rgb, 0.2 + 0.6 * smoothstep(0.3, 0.7, fbm3(p * 0.45 + 6.0)));
	g = mix(g, dc, dirt) * (1.0 - rim * 0.2);
	// Shallow puddles: a darker, bluer surface with a moving shimmer.
	float pn = fbm3(p * 0.14 + vec2(21.0, 4.0));
	float pud = smoothstep(0.56, 0.61, pn) * (1.0 - dirt * 0.7);
	float wet_edge = pud * (1.0 - smoothstep(0.61, 0.68, pn));
	float h0 = fbm3(p * 1.4 + vec2(TIME * 0.05, TIME * 0.03));
	float spec = sheen(wavy_normal(p, 0.8, 0.9, 0.2), 90.0, VIEW, VIEW_MATRIX);
	float swell = 0.5 + 0.5 * sin(TIME * 0.7 + pn * 40.0);
	vec3 water = mix(g * 0.6, vec3(0.15, 0.27, 0.25), 0.7);
	vec3 col = mix(g, water, pud * 0.9);
	col += accent.rgb * wet_edge * 0.05;
	// Glossy wet mud between the puddles.
	float wet = smoothstep(0.35, 0.7, mid) * (1.0 - pud);
	col *= 1.0 - 0.16 * wet;
	ALBEDO = col;
	EMISSION = accent.rgb * (pud * (0.06 + 0.06 * swell * h0 + 0.5 * spec) + wet * spec * 0.1);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""

## Black basalt plates split by cracks; some of the cracks are open and glow, pulsing slowly, and the
## ones around the vents glow more (the idle glow of the vents). The cracks stay thin and dim: the
## eruption's circle must stay the brightest thing on the floor.
const _VOLCANO_BODY := """
uniform vec4 accent : source_color = vec4(1.0, 0.36, 0.06, 1.0);
uniform vec2 vents[6];
uniform int vent_count = 0;

void fragment() {
	vec2 p = wpos.xz;
	float big = fbm(p * 0.06);
	float mid = noise(p * 0.5 + 3.0);
	float fine = noise(p * 3.0);
	// Voronoi plates, ~2.3 m across.
	vec2 q = p / 2.3;
	vec2 ip = floor(q);
	vec2 fp = fract(q);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 cid = ip;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 gcell = vec2(float(i), float(j));
			vec2 r = gcell + hash2(ip + gcell) - fp;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				cid = ip + gcell;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	float edge = sqrt(f2) - sqrt(f1);
	float plate = hash(cid);
	vec3 base = mix(grass_dark.rgb, grass_mid.rgb, smoothstep(0.2, 0.7, big));
	base = mix(base, grass_light.rgb, smoothstep(0.55, 0.85, big * 0.7 + plate * 0.5) * 0.5);
	base *= 0.8 + 0.3 * plate + 0.12 * (fine - 0.5);
	base *= 0.7 + 0.3 * smoothstep(0.0, 0.25, edge);
	base = mix(base, grass_warm.rgb, smoothstep(0.7, 0.9, mid) * 0.25);
	base *= wall_shade(p);
	// Ash drifts.
	float rim;
	float core;
	float dirt = patch_cover(p, rim, core);
	vec3 ash = mix(dirt_dark.rgb, dirt_light.rgb, 0.2 + 0.6 * smoothstep(0.3, 0.7, fbm3(p * 0.45 + 8.0)));
	vec3 col = mix(base, ash, dirt * 0.9);
	col *= 1.0 - rim * 0.25;
	// Open cracks.
	float line = 1.0 - smoothstep(0.01, 0.055, edge);
	float vein = smoothstep(0.55, 0.75, noise(p * 0.21 + 7.0));
	float near_vent = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= vent_count) {
			break;
		}
		near_vent = max(near_vent, 1.0 - smoothstep(1.3, 5.5, length(p - vents[i])));
	}
	float pulse = 0.7 + 0.3 * sin(TIME * 1.15 + dot(p, vec2(0.23, 0.17)) + plate * 2.0);
	float heat = line * clamp(vein * 0.55 + near_vent * 0.9, 0.0, 1.0) * (1.0 - dirt * 0.8) * pulse;
	col = mix(col, vec3(0.04, 0.015, 0.012), heat * 0.5);
	ALBEDO = col;
	EMISSION = mix(accent.rgb * 0.8, vec3(1.0, 0.62, 0.2), heat) * (heat * 0.85) + accent.rgb * near_vent * near_vent * 0.2 * pulse;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""

## Packed, wind-sculpted snow with sheets of ice: deeper blue in the middle, hairline cracks, a
## sun glint that slides over the ice and a few twinkles.
const _ICE_BODY := """
uniform vec4 accent : source_color = vec4(0.72, 0.92, 1.0, 1.0);

void fragment() {
	vec2 p = wpos.xz;
	float big = fbm(p * 0.05);
	float mid = fbm3(p * 0.25 + 2.0);
	float fine = noise(p * 2.0);
	// Packed snow.
	float rip = noise(vec2(p.x * 0.55 + p.y * 0.28 + big * 3.0, p.y * 2.2 - p.x * 0.4));
	vec3 snow = mix(grass_dark.rgb, grass_mid.rgb, smoothstep(0.25, 0.6, big));
	snow = mix(snow, grass_light.rgb, smoothstep(0.45, 0.75, mid + (rip - 0.5) * 0.3) * 0.85);
	snow = mix(snow, grass_warm.rgb, smoothstep(0.65, 0.85, mid) * 0.25);
	snow *= 0.95 + 0.07 * rip + 0.04 * (fine - 0.5);
	snow *= wall_shade(p);
	// Ice sheets.
	float rim;
	float core;
	float ice = patch_cover(p, rim, core);
	vec3 ic = mix(dirt_light.rgb, dirt_dark.rgb, core * 0.7);
	// Hairline cracks (a Voronoi net, lighter than the ice).
	vec2 q = p / 1.4;
	vec2 ip = floor(q);
	vec2 fp = fract(q);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 gcell = vec2(float(i), float(j));
			vec2 r = gcell + hash2(ip + gcell) - fp;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	float crack = 1.0 - smoothstep(0.015, 0.06, sqrt(f2) - sqrt(f1));
	ic = mix(ic, mix(ic, vec3(0.92, 0.97, 1.0), 0.6), crack * 0.55 * (0.4 + 0.6 * core));
	// Sheen: a perturbed normal against the sun, slow twinkles.
	float spec = sheen(wavy_normal(p, 0.35, 0.15, 0.16), 22.0, VIEW, VIEW_MATRIX);
	float twinkle = pow(smoothstep(0.62, 1.0, noise(p * 7.0 + vec2(TIME * 0.4, -TIME * 0.25))), 3.0);
	vec3 col = mix(snow, ic, ice);
	col *= 1.0 - rim * 0.12;
	ALBEDO = col;
	EMISSION = accent.rgb * (ice * (0.05 + 0.5 * spec + 0.55 * twinkle) + (1.0 - ice) * twinkle * 0.12);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""

## The dungeon floor: big stone tiles in a chequer, worn and cracked, with moss in the joints, the
## palette tinting the stone; the torches along the walls throw warm pools of light on it.
const _CRYPT_BODY := """
uniform vec4 accent : source_color = vec4(1.0, 0.56, 0.2, 1.0);
uniform vec4 torches[8];
uniform int torch_count = 0;

void fragment() {
	vec2 p = wpos.xz;
	float big = fbm3(p * 0.09);
	float fine = noise(p * 3.0);
	float grit = noise(p * 9.0);
	// Tiles 1.6 m across, a chequer of two stones.
	vec2 q = p / 1.6;
	vec2 id = floor(q);
	vec2 f = fract(q);
	float chess = mod(id.x + id.y, 2.0);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	// Grey stone with a hint of the run's palette.
	vec3 pal = mix(dirt_dark.rgb, dirt_light.rgb, 0.3 + 0.28 * chess + 0.3 * hash(id));
	vec3 stone = mix(vec3(dot(pal, vec3(0.3, 0.59, 0.11))), pal, 0.3) * 1.15;
	stone *= 0.86 + 0.24 * fine + 0.1 * (grit - 0.5);
	// Bevelled edges: lighter on the north-west, darker on the south-east, grout in the joint.
	float bevel = smoothstep(0.0, 0.07, edge);
	float lit = (1.0 - smoothstep(0.0, 0.06, min(f.x, 1.0 - f.y))) * 0.14;
	stone *= 0.55 + 0.45 * bevel;
	stone += lit;
	// Worn, dirty and cracked: darker in the middle of the room's traffic, hairline cracks.
	stone *= 0.78 + 0.3 * smoothstep(0.25, 0.7, big);
	float crack = 1.0 - smoothstep(0.0, 0.025, abs(noise(p * vec2(1.3, 1.9) + hash(id) * 9.0) - 0.5));
	stone *= 1.0 - 0.35 * crack * step(0.8, hash(id + 4.0));
	// Moss in the joints and along the walls.
	float mossy = smoothstep(0.55, 0.8, noise(p * 0.8 + 3.0) + (1.0 - bevel) * 0.4);
	stone = mix(stone, grass_mid.rgb * 0.8, mossy * 0.22);
	stone *= wall_shade(p);
	// Torch light: warm pools on the stone.
	float lamp = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= torch_count) {
			break;
		}
		float d = length(p - torches[i].xy) / torches[i].z;
		lamp += 1.0 - smoothstep(0.0, 1.0, d);
	}
	float flicker = 0.9 + 0.1 * sin(TIME * 9.0 + dot(p, vec2(1.7, 2.3))) * sin(TIME * 5.3 + p.x);
	lamp = clamp(lamp, 0.0, 1.0) * flicker;
	ALBEDO = stone;
	EMISSION = accent.rgb * stone * lamp * 0.95;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""
