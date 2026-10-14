class_name HookLine
extends Node3D
## The Flesh Golem's hook (M6, GDD 8): a child of the golem, at its feet, that shows
##   1. the telegraph – a red band along the locked aim ([member length] m long, 2 ×
##      [constant HALF_WIDTH] wide, bright edges, a fill that runs out from the golem as the
##      telegraph runs down: [method set_progress]) – the hero who is still inside it when
##      the telegraph ends gets hooked ([method Enemy._fire_hook]), and
##   2. the strike – an iron chain with a hook head that shoots out along the band and back
##      ([method play_strike], [constant STRIKE_TIME] s), after which the node frees itself.
## The aim is turned by [method set_aim]. Freed with the golem (dies / is stunned / is
## taunted while telegraphing: [method Enemy._cancel_special]).
## Visual only (the hit test is Enemy's): no RNG, no gameplay state.

## Half the width (m) of the band: a hero whose centre is closer than this to the aim line
## (and in front of the golem, within the hook range) is in the line.
const HALF_WIDTH := 0.6
const STRIKE_TIME := 0.3
const CHAIN_HEIGHT := 0.9
const CHAIN_COLOR := Color(0.46, 0.47, 0.52)
const HEAD_COLOR := Color(0.72, 0.74, 0.8)

const _BAND_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 line_color : source_color = vec4(1.0, 0.16, 0.1, 1.0);
uniform float progress = 0.0;
uniform float fade = 1.0;
void fragment() {
	float along = 1.0 - UV.y;
	float across = abs(UV.x * 2.0 - 1.0);
	float aa = max(fwidth(across) * 1.5, 0.01);
	float edge = smoothstep(0.82 - aa, 0.82 + aa, across);
	float filled = 1.0 - smoothstep(progress - 0.012, progress + 0.012, along);
	float pulse = 0.8 + 0.2 * sin(TIME * (7.0 + 24.0 * progress));
	// White-hot edges and fill: readable without relying on red alone.
	vec3 col = mix(line_color.rgb, vec3(1.0, 0.93, 0.86), edge * 0.7 + filled * 0.25);
	ALBEDO = col;
	ALPHA = clamp((0.16 + 0.4 * filled + 0.55 * edge) * pulse, 0.0, 1.0) * fade * line_color.a;
}
"""

static var _band_shader: Shader

## Length (m) of the band and of the strike.
var length := 9.0
## Telegraph progress 0..1 (what [method set_progress] last got).
var progress := 0.0
## True from [method play_strike] on.
var striking := false

var _band: MeshInstance3D
var _band_material: ShaderMaterial
var _chain: MeshInstance3D
var _head: MeshInstance3D
var _strike_length := 0.0
var _strike_time := 0.0


## A telegraph band of [param p_length] m along [param aim] (XZ, need not be normalised),
## not in the tree yet.
static func create(aim: Vector3, p_length: float) -> HookLine:
	var h := HookLine.new()
	h.name = "HookLine"
	h.length = maxf(0.5, p_length)
	h._build()
	h.set_aim(aim)
	return h


## Turns the band to point along [param aim] (XZ).
func set_aim(aim: Vector3) -> void:
	if Vector2(aim.x, aim.z).length_squared() < 0.0001:
		return
	rotation.y = atan2(-aim.x, -aim.z)


## How far the telegraph has run (0 = just started, 1 = the hook fires).
func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	if _band_material != null:
		_band_material.set_shader_parameter("progress", progress)


## Replaces the band with the chain: out to [param hit_length] m and back.
func play_strike(hit_length: float) -> void:
	if striking:
		return
	striking = true
	_strike_length = clampf(hit_length, 0.5, length)
	_strike_time = 0.0
	if _band != null:
		_band.visible = false
	if _chain != null:
		_chain.visible = true
		_head.visible = true
	_update_strike()


func _process(delta: float) -> void:
	if not striking:
		return
	_strike_time += delta
	if _strike_time >= STRIKE_TIME:
		queue_free()
		return
	_update_strike()


func _update_strike() -> void:
	# Out in the first 40%, back in the rest (the head leads).
	var t := clampf(_strike_time / STRIKE_TIME, 0.0, 1.0)
	var reach := (t / 0.4) if t < 0.4 else (1.0 - (t - 0.4) / 0.6)
	var l := maxf(0.05, _strike_length * clampf(reach, 0.0, 1.0))
	_chain.scale = Vector3(1.0, 1.0, l)
	_chain.position = Vector3(0.0, CHAIN_HEIGHT, -l * 0.5)
	_head.position = Vector3(0.0, CHAIN_HEIGHT, -l)


func _build() -> void:
	if _band_shader == null:
		_band_shader = Shader.new()
		_band_shader.code = _BAND_CODE
	_band = MeshInstance3D.new()
	_band.name = "Band"
	var plane := PlaneMesh.new()
	plane.size = Vector2(HALF_WIDTH * 2.0, length)
	_band.mesh = plane
	_band_material = ShaderMaterial.new()
	_band_material.shader = _band_shader
	_band_material.render_priority = 2
	_band.material_override = _band_material
	_band.position = Vector3(0.0, 0.05, -length * 0.5)
	_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_band)
	# The chain (a unit box stretched along -Z) and its hook head, shown by play_strike.
	_chain = MeshInstance3D.new()
	_chain.name = "Chain"
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.1, 1.0)
	_chain.mesh = box
	_chain.material_override = Mats.toon_plain(CHAIN_COLOR)
	_chain.visible = false
	_chain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_chain)
	_head = MeshInstance3D.new()
	_head.name = "Head"
	var head := BoxMesh.new()
	head.size = Vector3(0.34, 0.34, 0.34)
	_head.mesh = head
	_head.material_override = Mats.toon_plain(HEAD_COLOR)
	_head.visible = false
	_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_head)
