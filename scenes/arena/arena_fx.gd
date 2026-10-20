class_name ArenaFx
extends RefCounted
## The small animated materials of the arena's decor (M7b VIS-ENV): the glow meshes of the decor sets
## used to be plain emissive StandardMaterial3Ds (static). These two shaders animate them on TIME, out
## of step with each other, for free:
##   [method twinkle] – wisps, fireflies, lantern flames and ice sparkles: each light (one sphere of
##                      the merged glow mesh) carries its own phase in the vertex colour's alpha
##                      ([method phase]), so they pulse, blink or twinkle independently;
##   [method lava]    – the volcano's glow mesh: lava that churns and pulses, a darker crust drifting
##                      over it; the heat of every part is baked into its vertex colour (white-hot
##                      cores, orange cracks, red rivers).
## One cached ShaderMaterial per parameter set (the decor's draw calls do not change), no instance
## uniforms, no script work while the game runs.

## What the unshaded glow materials look like: the colour lightened a little (the albedo of
## [method Mats.glow]; the Compatibility renderer shows only the albedo of an unshaded material, so the
## emission of that recipe never reached the screen) times the pulse.
const _TWINKLE_CODE := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
uniform vec4 glow_color : source_color = vec4(1.0);
// Radians per second of the pulse, how deep it dips (0 = steady, 1 = fully dark) and how much of it
// is a sharp blink (fireflies) rather than a smooth swell.
uniform float speed = 1.4;
uniform float dip = 0.6;
uniform float blink = 0.0;
varying float level;
void vertex() {
	float s = 0.5 + 0.5 * sin(TIME * speed + COLOR.a * 6.2831853);
	level = mix(1.0 - dip, 1.0, mix(s, s * s * s, blink));
}
void fragment() {
	ALBEDO = mix(glow_color.rgb, vec3(1.0), 0.15) * level;
}
"""

const _LAVA_CODE := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
varying vec3 wp;
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
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float churn = noise(wp.xz * 1.3 + vec2(TIME * 0.22, TIME * 0.13));
	float fine = noise(wp.xz * 3.4 - vec2(TIME * 0.3, TIME * 0.05));
	float pulse = 0.84 + 0.16 * sin(TIME * 1.7 + wp.x * 0.45 + wp.z * 0.3);
	// A darker crust drifts over the cracks and rivers, never over the hot cores (their vertex alpha is 0).
	float crust = smoothstep(0.6, 0.82, fine * 0.7 + churn * 0.4) * COLOR.a;
	vec3 heat = COLOR.rgb * (0.82 + 0.3 * churn) * pulse;
	ALBEDO = mix(heat, heat * vec3(0.4, 0.16, 0.1), crust * 0.7);
}
"""

static var _shaders: Dictionary[StringName, Shader] = {}
static var _cache: Dictionary[String, Material] = {}


## A self-twinkling glow material for a mesh whose vertex colours carry [method phase] in their alpha.
## [param dip] 0 = steady .. 1 = fully dark between pulses, [param blink] 0 = smooth swell .. 1 = sharp
## flashes, [param speed] radians per second.
static func twinkle(color: Color, speed: float = 1.4, dip: float = 0.6, blink: float = 0.0) -> Material:
	var key := "twinkle:%s:%.2f:%.2f:%.2f" % [color.to_html(), speed, dip, blink]
	var m: Material = _cache.get(key)
	if m != null:
		return m
	var sm := ShaderMaterial.new()
	sm.shader = _shader(&"twinkle", _TWINKLE_CODE)
	sm.set_shader_parameter(&"glow_color", Color(color.r, color.g, color.b, 1.0))
	sm.set_shader_parameter(&"speed", speed)
	sm.set_shader_parameter(&"dip", dip)
	sm.set_shader_parameter(&"blink", blink)
	_cache[key] = sm
	return sm


## The molten material of the volcano's glow mesh (the colour of every part is its baked heat).
static func lava() -> Material:
	var m: Material = _cache.get("lava")
	if m != null:
		return m
	var sm := ShaderMaterial.new()
	sm.shader = _shader(&"lava", _LAVA_CODE)
	_cache["lava"] = sm
	return sm


## The phase (the vertex colour's alpha) of a light standing at [param at]: a hash of its place, so
## the same decor always twinkles the same way and no random number is drawn for it.
static func phase(at: Vector3) -> float:
	return fposmod(sin(at.x * 12.9898 + at.z * 78.233 + at.y * 37.719) * 43758.5453, 1.0)


## [param color] with the [method phase] of [param at] as its alpha (for MeshKit parts of a twinkling mesh).
static func lit(at: Vector3, color: Color = Color.WHITE) -> Color:
	return Color(color.r, color.g, color.b, phase(at))


static func _shader(id: StringName, code: String) -> Shader:
	var s: Shader = _shaders.get(id)
	if s == null:
		s = Shader.new()
		s.code = code
		_shaders[id] = s
	return s
