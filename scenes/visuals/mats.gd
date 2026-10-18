class_name Mats
extends RefCounted
## Shared material factory with caching (owned by the "visuals" module).
## Stylised WoW-like look: soft two-band toon shading, warm rim light, toon specular blob and
## a thin dark inverted-hull outline (next_pass, cull_front + vertex grow). All shaders work
## in the GL Compatibility renderer. The outline pass does not write depth, so it is drawn
## in the alpha pass only and never enters the (expensive) shadow pass – outlines all share
## one colour, so their mutual draw order does not matter.
##
## No `instance uniform`s anywhere: the GL Compatibility renderer keeps them in one 64 KB
## uniform buffer with 16 slots per instance, i.e. only ~256 instances for the whole scene –
## far too few for 150 enemies. Instead:
##   - hit flash / wind-up tint: [method set_overlay] swaps the node to a cached variant of
##     its (shared) material, quantised so only a handful of variants ever exist;
##   - ground rings, cast bars and VFX get their own material per node ([method ring],
##     [method cast_bar]) and are animated with regular shader parameters.

const OUTLINE_COLOR := Color(0.07, 0.045, 0.06)
## Outline thickness in metres (object space).
const OUTLINE_WIDTH := 0.016
const OVERLAY_PARAM := &"overlay"
## Overlay amounts are quantised to this many steps (variant materials are cached).
const OVERLAY_STEPS := 10
const _BASE_META := &"mats_base"

const _TOON_CODE := """
shader_type spatial;
render_mode %s;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float rim_strength = 0.32;
uniform float shade_softness = 0.16;
uniform float spec_strength = 0.22;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform vec4 overlay = vec4(1.0, 1.0, 1.0, 0.0);
// > 0: the overlay pulses with this angular speed (wind-up tells).
uniform float overlay_pulse = 0.0;
#ifdef ONION
uniform float stripe_count = 11.0;
uniform float stripe_strength = 0.22;
uniform float damage = 0.0;
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
	float over = overlay.a;
	if (overlay_pulse > 0.0) {
		over *= 0.6 + 0.4 * sin(TIME * overlay_pulse);
	}
	ALBEDO = mix(base, overlay.rgb, over);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim * rim_strength * mix(base, vec3(1.0, 0.95, 0.85), 0.55)
		+ emission_color.rgb * emission_energy
		+ overlay.rgb * over * 0.7;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.02, shade_softness, ndl);
	float top = smoothstep(0.55, 0.55 + shade_softness, ndl);
	float shadow = mix(1.0, ATTENUATION, 0.85);
	DIFFUSE_LIGHT += (lit * 0.82 + top * 0.18) * shadow * LIGHT_COLOR / PI;
	vec3 h = normalize(VIEW + LIGHT);
	float spec = smoothstep(0.986, 0.996, dot(NORMAL, h)) * lit * ATTENUATION;
	SPECULAR_LIGHT += spec * spec_strength * LIGHT_COLOR / PI;
}
"""

const _OUTLINE_CODE := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled;
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

## Flat ground ring / disc decal (quad on XZ, UV 0..1). One material per node (see
## [method ring]) animated through regular uniforms.
const _RING_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 ring_color = vec4(1.0, 1.0, 1.0, 1.0);
// x = inner radius, y = outer radius (0..1 of the quad half size), z = fill alpha, w = arc 0..1
uniform vec4 ring_shape = vec4(0.78, 0.95, 0.18, 1.0);
// 0..1: dark outline just outside the band + thin white stroke on its inner edge, so the
// player colour reads on any ground / class colour (player rings; VFX rings use 0).
uniform float ring_stroke = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = fwidth(r) * 1.5;
	float inner = ring_shape.x;
	float outer = ring_shape.y;
	float band = smoothstep(inner - aa, inner + aa, r) * (1.0 - smoothstep(outer - aa, outer + aa, r));
	float fill = (1.0 - smoothstep(inner - aa, inner + aa, r)) * ring_shape.z * (0.6 + 0.4 * r / max(inner, 0.001));
	float ang = fract(atan(p.x, -p.y) / 6.2831853 + 1.0);
	float arc = ring_shape.w >= 0.999 ? 1.0 : step(ang, ring_shape.w);
	vec3 col = ring_color.rgb;
	float a = max(band * arc, fill);
	if (ring_stroke > 0.0) {
		float w = max(outer - inner, 0.001);
		float ow = max(w * 0.3, aa * 2.0);
		float edge = smoothstep(outer - aa, outer + aa, r) * (1.0 - smoothstep(outer + ow - aa, outer + ow + aa, r));
		float iw = max(w * 0.17, aa * 1.6);
		float stroke = smoothstep(inner - aa, inner + aa, r) * (1.0 - smoothstep(inner + iw - aa, inner + iw + aa, r));
		col = mix(col, vec3(1.0), stroke * 0.85 * ring_stroke);
		col = mix(col, vec3(0.06, 0.035, 0.045), edge * ring_stroke);
		a = max(a, edge * arc * 0.8 * ring_stroke);
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * ring_color.a;
}
"""

## A small unlit sphere that swells and pops over and over, animated by the GPU (bog bubbles): scales
## around its own centre by max(0, sin(TIME * 2.2 + phase)) * 0.9 and rises a little with it. The phase
## is a hash of the node's world XZ, so bubbles in different places are out of step (instance uniforms
## are not an option, see the header). Nothing is animated from script.
const _BUBBLE_CODE := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled;
uniform vec4 albedo : source_color = vec4(0.62, 0.82, 0.3, 1.0);
void vertex() {
	vec2 at = MODEL_MATRIX[3].xz;
	float phase = TIME * 2.2 + fract(sin(dot(at, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
	float s = max(0.0, sin(phase)) * 0.9;
	VERTEX = VERTEX * max(s, 0.01) + vec3(0.0, 0.03 + s * 0.1, 0.0);
}
void fragment() {
	ALBEDO = albedo.rgb;
}
"""

## WoW-like cast bar quad (QuadMesh, UV 0..1) that always faces the camera and draws on
## top. Uniforms: bar_color (fill), bar_progress (0..1).
const _CAST_BAR_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, shadows_disabled;
uniform vec4 bar_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform float bar_progress = 0.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec2 uv = UV;
	float bx = 0.022;
	float by = 0.2;
	float inside = step(bx, uv.x) * step(uv.x, 1.0 - bx) * step(by, uv.y) * step(uv.y, 1.0 - by);
	float fill_x = (uv.x - bx) / (1.0 - 2.0 * bx);
	float filled = inside * step(fill_x, bar_progress);
	float shine = 0.78 + 0.4 * (1.0 - smoothstep(0.0, 0.5, abs(uv.y - 0.4)));
	vec3 frame = mix(vec3(0.55, 0.42, 0.18), vec3(0.95, 0.8, 0.42), smoothstep(0.0, 1.0, uv.y));
	vec3 col = mix(frame, vec3(0.08, 0.07, 0.07), inside);
	col = mix(col, bar_color.rgb * shine, filled);
	float spark = filled * (1.0 - smoothstep(0.0, 0.02, abs(fill_x - bar_progress)));
	ALBEDO = mix(col, vec3(1.0), spark * 0.8);
	ALPHA = 0.96 * bar_color.a;
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


## Onion skin: toon + vertical layer stripes; [param damage] (0..1, quantised to 0.05)
## peels the outer layers off. Cached per colour and damage step.
static func onion_skin(color: Color, damage: float = 0.0) -> Material:
	var step := roundi(clampf(damage, 0.0, 1.0) * 20.0)
	if step == 0:
		return _toon_variant("onion", color, true)
	var key := "onion_dmg:%s:%d" % [color.to_html(), step]
	if _cache.has(key):
		return _cache[key]
	var m := (_toon_variant("onion", color, true) as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter("damage", step / 20.0)
	_cache[key] = m
	return m


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


## A NEW ground ring material (shared shader) – one per node, configured with
## [method set_ring]. Not cached: each ring animates its own parameters.
static func ring() -> Material:
	var m := ShaderMaterial.new()
	m.shader = _shader("ring", _RING_CODE)
	m.render_priority = -1
	return m


## The self-animating bubble material of [constant _BUBBLE_CODE] for [param color] (lightened a little
## like [method glow]). Cached per colour.
static func bubble(color: Color) -> Material:
	var key := "bubble:%s" % color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("bubble", _BUBBLE_CODE)
	m.set_shader_parameter(&"albedo", Color(color.r, color.g, color.b, 1.0).lerp(Color.WHITE, 0.15))
	_cache[key] = m
	return m


## A NEW camera-facing cast bar material – one per node, see [method set_cast_bar].
static func cast_bar() -> Material:
	var m := ShaderMaterial.new()
	m.shader = _shader("cast_bar", _CAST_BAR_CODE)
	m.render_priority = 30
	return m


static func set_cast_bar(node: GeometryInstance3D, color: Color, progress: float) -> void:
	var m := node.material_override as ShaderMaterial
	if m == null:
		return
	m.set_shader_parameter(&"bar_color", color)
	m.set_shader_parameter(&"bar_progress", clampf(progress, 0.0, 1.0))


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
## [param amount] 0 = none, 1 = solid colour (quantised to [constant OVERLAY_STEPS]);
## [param pulse] > 0 makes the tint pulse in the shader (angular speed). The node is
## switched to a cached variant of its base material (remembered in node meta), so the
## call is cheap and shared by every node with the same base material.
static func set_overlay(node: GeometryInstance3D, color: Color, amount: float, pulse: float = 0.0) -> void:
	var base := base_material(node)
	if base == null:
		return
	node.material_override = with_overlay(base, color, amount, pulse)


## The node's material without any overlay (see [method set_overlay]).
static func base_material(node: GeometryInstance3D) -> Material:
	if node.has_meta(_BASE_META):
		var m: Material = node.get_meta(_BASE_META)
		# Somebody replaced the material meanwhile (e.g. the downed ghost look): track it.
		if node.material_override == m or _is_overlay_of(node.material_override, m):
			return m
	var current := node.material_override
	if current != null and current.has_meta(_BASE_META):
		current = current.get_meta(_BASE_META)
	node.set_meta(_BASE_META, current)
	return current


## Current overlay amount of a node (0 = none) – for tests / debugging.
static func overlay_amount(node: GeometryInstance3D) -> float:
	var m := node.material_override as ShaderMaterial
	if m == null:
		return 0.0
	var v: Variant = m.get_shader_parameter(OVERLAY_PARAM)
	return (v as Color).a if v is Color else 0.0


## Cached variant of [param base] (a toon ShaderMaterial) with an overlay tint.
static func with_overlay(base: Material, color: Color, amount: float, pulse: float = 0.0) -> Material:
	var step := roundi(clampf(amount, 0.0, 1.0) * OVERLAY_STEPS)
	var sm := base as ShaderMaterial
	if step == 0 or sm == null:
		return base
	var key := "overlay:%d:%s:%d:%.1f" % [base.get_instance_id(), color.to_html(false), step, pulse]
	if _cache.has(key):
		return _cache[key]
	var m := sm.duplicate() as ShaderMaterial
	m.set_shader_parameter(OVERLAY_PARAM, Color(color.r, color.g, color.b, float(step) / OVERLAY_STEPS))
	m.set_shader_parameter(&"overlay_pulse", pulse)
	m.set_meta(_BASE_META, base)
	_cache[key] = m
	return m


## Configures a node using its own [method ring] material: radii are fractions of the quad
## half size.
static func set_ring(node: GeometryInstance3D, color: Color, inner: float, outer: float,
		fill_alpha: float = 0.0, arc: float = 1.0) -> void:
	var m := node.material_override as ShaderMaterial
	if m == null:
		return
	m.set_shader_parameter(&"ring_color", color)
	m.set_shader_parameter(&"ring_shape", Vector4(inner, outer, fill_alpha, arc))


## Dark outline + white inner stroke on a [method ring] node (0 = plain band, 1 = full).
static func set_ring_stroke(node: GeometryInstance3D, amount: float) -> void:
	var m := node.material_override as ShaderMaterial
	if m != null:
		m.set_shader_parameter(&"ring_stroke", clampf(amount, 0.0, 1.0))


static func _is_overlay_of(material: Material, base: Material) -> bool:
	return material != null and material.has_meta(_BASE_META) and material.get_meta(_BASE_META) == base


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
