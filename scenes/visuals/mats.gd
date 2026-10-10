class_name Mats
extends RefCounted
## Shared material factory with caching (owned by the "visuals" module).
## Stylised WoW-like look: soft two-band toon shading, warm rim light, toon specular blob and
## a thin dark inverted-hull outline (next_pass, cull_front + vertex grow). All shaders work
## in the GL Compatibility renderer.
##
## Every toon shader declares `instance uniform vec4 overlay` (rgb = colour, a = amount):
## a per-node hit flash / wind-up tint without duplicating materials –
## see [method set_overlay].

const OUTLINE_COLOR := Color(0.07, 0.045, 0.06)
## Outline thickness in metres (object space).
const OUTLINE_WIDTH := 0.016
const OVERLAY_PARAM := &"overlay"

const _TOON_CODE := """
shader_type spatial;
render_mode %s;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float rim_strength = 0.32;
uniform float shade_softness = 0.16;
uniform float spec_strength = 0.22;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
instance uniform vec4 overlay = vec4(1.0, 1.0, 1.0, 0.0);
#ifdef ONION
uniform float stripe_count = 11.0;
uniform float stripe_strength = 0.22;
instance uniform float damage = 0.0;
#endif

#ifdef ONION
float onion_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float onion_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(onion_hash(i), onion_hash(i + vec2(1.0, 0.0)), u.x),
		mix(onion_hash(i + vec2(0.0, 1.0)), onion_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
#endif

void fragment() {
	vec3 base = albedo.rgb;
#ifdef VERTEX_COLOR
	base *= COLOR.rgb;
#endif
#ifdef ONION
	// Vertical skin layers: soft ridges with a thin darker seam per layer.
	float u = fract(UV.x * stripe_count);
	float seam = smoothstep(0.40, 0.5, u) * (1.0 - smoothstep(0.5, 0.60, u));
	float ridge = 0.5 + 0.5 * cos(u * 6.2831853);
	base *= 1.0 - stripe_strength * seam;
	base *= 0.94 + 0.10 * ridge;
	// Darker towards the root, papery and lighter towards the neck.
	base = mix(base * 0.78, base * 1.12, smoothstep(0.02, 0.8, UV.y));
	// Low HP: outer layers peel off and reveal the pale, juicy inner layer.
	if (damage > 0.0) {
		vec2 p = vec2(UV.x * 9.0, UV.y * 5.0);
		float n = onion_noise(p) * 0.65 + onion_noise(p * 2.7) * 0.35;
		float peel = smoothstep(1.0 - damage * 0.75, 1.0 - damage * 0.75 + 0.03, n);
		float edge = smoothstep(1.0 - damage * 0.75 - 0.05, 1.0 - damage * 0.75, n) - peel;
		vec3 inner = mix(vec3(0.97, 0.95, 0.86), base, 0.25);
		base = mix(base, inner, peel);
		base *= 1.0 - 0.55 * clamp(edge, 0.0, 1.0);
	}
#endif
	ALBEDO = mix(base, overlay.rgb, overlay.a);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim * rim_strength * mix(base, vec3(1.0, 0.95, 0.85), 0.55)
		+ emission_color.rgb * emission_energy
		+ overlay.rgb * overlay.a * 0.7;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.02, shade_softness, ndl);
	float top = smoothstep(0.55, 0.55 + shade_softness, ndl);
	float shadow = mix(1.0, ATTENUATION, 0.85);
	DIFFUSE_LIGHT += (lit * 0.82 + top * 0.18) * shadow * LIGHT_COLOR / PI;
	vec3 h = normalize(VIEW + LIGHT);
	float spec = smoothstep(0.965, 0.985, dot(NORMAL, h)) * lit * ATTENUATION;
	SPECULAR_LIGHT += spec * spec_strength * LIGHT_COLOR / PI;
}
"""

const _OUTLINE_CODE := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
uniform vec4 color : source_color = vec4(0.07, 0.045, 0.06, 1.0);
uniform float width = 0.016;
void vertex() {
	VERTEX += NORMAL * width;
}
void fragment() {
	ALBEDO = color.rgb;
}
"""

const _GHOST_CODE := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_always, blend_mix;
uniform vec4 color : source_color = vec4(0.85, 0.92, 1.0, 0.45);
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float wave = 0.5 + 0.5 * sin(TIME * 3.0 + UV.y * 12.0);
	ALBEDO = mix(color.rgb, vec3(1.0), f * 0.7) * (0.92 + 0.08 * wave);
	ALPHA = clamp(color.a + f * 0.45, 0.0, 1.0);
}
"""

## Flat ground ring / disc decal (quad on XZ, UV 0..1). Instance uniforms so every user
## (player rings, revive rings, shock waves) shares one material.
const _RING_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
instance uniform vec4 ring_color = vec4(1.0, 1.0, 1.0, 1.0);
// x = inner radius, y = outer radius (0..1 of the quad half size), z = fill alpha, w = arc 0..1
instance uniform vec4 ring_shape = vec4(0.78, 0.95, 0.18, 1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = fwidth(r) * 1.5;
	float band = smoothstep(ring_shape.x - aa, ring_shape.x + aa, r) * (1.0 - smoothstep(ring_shape.y - aa, ring_shape.y + aa, r));
	float fill = (1.0 - smoothstep(ring_shape.x - aa, ring_shape.x + aa, r)) * ring_shape.z * (0.6 + 0.4 * r / max(ring_shape.x, 0.001));
	float ang = fract(atan(p.x, -p.y) / 6.2831853 + 1.0);
	float arc = ring_shape.w >= 0.999 ? 1.0 : step(ang, ring_shape.w);
	ALBEDO = ring_color.rgb;
	ALPHA = clamp(max(band * arc, fill), 0.0, 1.0) * ring_color.a;
}
"""

static var _shaders: Dictionary[String, Shader] = {}
static var _cache: Dictionary[String, Material] = {}


## Lit, toon-shaded material for [param color] with a dark outline. Cached per colour.
static func toon(color: Color) -> Material:
	return _toon_variant("toon", color, true)


## Toon material without outline (tiny details: pupils, highlights, small gems).
static func toon_plain(color: Color) -> Material:
	return _toon_variant("toon", color, false)


## Toon material multiplying vertex colours (for [MeshKit] merged meshes). Cached.
## [param outline_width] in metres – big props (trees) need a thicker line to read.
static func toon_vc(outline: bool = true, tint: Color = Color.WHITE, outline_width: float = OUTLINE_WIDTH) -> Material:
	return _toon_variant("vc", tint, outline, outline_width)


## Vertex-colour toon material with a faint emissive glow (epic / legendary gear).
static func toon_vc_glow(emission: Color, energy: float = 0.5) -> Material:
	var key := "vc_glow:%s:%.2f" % [emission.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _toon_shader("vc")
	m.set_shader_parameter("albedo", Color.WHITE)
	m.set_shader_parameter("emission_color", emission)
	m.set_shader_parameter("emission_energy", energy)
	m.set_shader_parameter("rim_strength", 0.6)
	m.next_pass = outline()
	_cache[key] = m
	return m


## Double-sided toon material for capes, hoods and banners (no outline).
static func toon_cloth(color: Color) -> Material:
	return _toon_variant("cloth", color, false)


## Double-sided vertex-colour toon material (merged cloth meshes, foliage cards).
static func toon_cloth_vc() -> Material:
	return _toon_variant("cloth_vc", Color.WHITE, false)


## Onion skin: toon + vertical layer stripes + instance uniform `damage` (0..1) peeling.
static func onion_skin(color: Color) -> Material:
	return _toon_variant("onion", color, true)


## Toon material with an emissive tint (glowing gems / trims that still read as solid).
static func toon_emissive(color: Color, emission: Color, energy: float = 1.0) -> Material:
	var key := "toon_em:%s:%s:%.2f" % [color.to_html(), emission.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _toon_shader("toon")
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("emission_color", emission)
	m.set_shader_parameter("emission_energy", energy)
	m.next_pass = outline()
	_cache[key] = m
	return m


## Unlit material (VFX, UI-in-world). Supports alpha when color.a < 1.
static func unshaded(color: Color) -> Material:
	var key := "unshaded:" + color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m


## Glowing (emissive) material for epic/legendary items, magic projectiles.
static func glow(color: Color, energy: float = 2.0) -> Material:
	var key := "glow:%s:%.2f" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var c := Color(color.r, color.g, color.b, 1.0)
	m.albedo_color = c.lerp(Color.WHITE, 0.15)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	if color.a < 1.0:
		m.albedo_color.a = color.a
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = false
	_cache[key] = m
	return m


## Additive unlit material using vertex / particle colours (CPUParticles3D, sparks).
static func particle(additive: bool = false, billboard: bool = false) -> Material:
	var key := "particle:%s:%s" % [additive, billboard]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shadow_mode = 0
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_cache[key] = m
	return m


## Translucent, softly glowing ghost material (downed players).
static func ghost(color: Color) -> Material:
	var key := "ghost:" + color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("ghost", _GHOST_CODE)
	m.set_shader_parameter("color", color)
	m.render_priority = 1
	_cache[key] = m
	return m


## Shared ground ring material – configure per node with [method set_ring].
static func ring() -> Material:
	if _cache.has("ring"):
		return _cache["ring"]
	var m := ShaderMaterial.new()
	m.shader = _shader("ring", _RING_CODE)
	m.render_priority = -1
	_cache["ring"] = m
	return m


## The outline pass (inverted hull). One cached instance per width.
static func outline(width: float = OUTLINE_WIDTH) -> Material:
	var key := "outline:%.4f" % width
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("outline", _OUTLINE_CODE)
	m.set_shader_parameter("color", OUTLINE_COLOR)
	m.set_shader_parameter("width", width)
	_cache[key] = m
	return m


## Per-node colour overlay for toon materials: hit flash (white), wind-up tell (red) ...
## [param amount] 0 = none, 1 = solid colour.
static func set_overlay(node: GeometryInstance3D, color: Color, amount: float) -> void:
	node.set_instance_shader_parameter(OVERLAY_PARAM, Color(color.r, color.g, color.b, clampf(amount, 0.0, 1.0)))


## Configures a node using [method ring]: radii are fractions of the quad half size.
static func set_ring(node: GeometryInstance3D, color: Color, inner: float, outer: float,
		fill_alpha: float = 0.0, arc: float = 1.0) -> void:
	node.set_instance_shader_parameter(&"ring_color", color)
	node.set_instance_shader_parameter(&"ring_shape", Vector4(inner, outer, fill_alpha, arc))


static func cached_count() -> int:
	return _cache.size()


# --- Internals ---------------------------------------------------------------

static func _toon_variant(variant: String, color: Color, with_outline: bool,
		outline_width: float = OUTLINE_WIDTH) -> Material:
	var key := "%s:%s:%s:%.4f" % [variant, color.to_html(), with_outline, outline_width]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _toon_shader(variant)
	m.set_shader_parameter("albedo", color)
	if variant == "onion":
		m.set_shader_parameter("rim_strength", 0.38)
	if with_outline:
		m.next_pass = outline(outline_width)
	_cache[key] = m
	return m


static func _toon_shader(variant: String) -> Shader:
	var modes := "cull_back"
	var defines := ""
	match variant:
		"vc":
			defines = "#define VERTEX_COLOR\n"
		"cloth":
			modes = "cull_disabled"
		"cloth_vc":
			modes = "cull_disabled"
			defines = "#define VERTEX_COLOR\n"
		"onion":
			defines = "#define ONION\n"
	var code := _TOON_CODE % modes
	code = code.replace("shader_type spatial;\n", "shader_type spatial;\n" + defines)
	return _shader("toon_" + variant, code)


static func _shader(name: String, code: String) -> Shader:
	if _shaders.has(name):
		return _shaders[name]
	var sh := Shader.new()
	sh.code = code
	_shaders[name] = sh
	return sh
