class_name SupportShield
extends Node3D
## The bubble around a NORMAL enemy that a Cultist Acolyte shielded (M6): violet and faint, shown
## while [member Enemy.shield_hp] holds (elites have their own bubble: [ElitePlate]). A child of
## the shielded enemy, created by [method Enemy.apply_support_shield] the first time and kept
## (hidden when the shield is gone) until the enemy leaves; polls the enemy every rendered
## frame, changes no gameplay state and never touches RunState.rng.

const COLOR := Color(0.72, 0.3, 1.0)
const RADIUS_MULT := 1.35
const MIN_RADIUS := 0.55

const _BUBBLE_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.62, 0.38, 1.0, 1.0);
void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.2);
	float pulse = 0.85 + 0.15 * sin(TIME * 3.4);
	ALBEDO = mix(tint.rgb, vec3(1.0), rim * 0.3);
	ALPHA = clamp((0.1 + rim * 0.85) * pulse, 0.0, 1.0);
}
"""

static var _shader: Shader

var enemy: Enemy
var _bubble: MeshInstance3D


## A bubble for [param p_enemy] (a child of it; call after the enemy has its model).
static func create(p_enemy: Enemy) -> SupportShield:
	var s := SupportShield.new()
	s.name = "SupportShield"
	s.enemy = p_enemy
	s._build()
	return s


## Shown exactly while the enemy has shield left.
func is_shown() -> bool:
	return _bubble != null and _bubble.visible


func _process(_delta: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	_bubble.visible = enemy.shield_hp > 0.0 and not enemy.is_dead()


func _build() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = _BUBBLE_CODE
	var head: float = enemy.model.head_height if enemy != null and enemy.model != null else 1.2
	var r := maxf(MIN_RADIUS, head * 0.5 * RADIUS_MULT)
	_bubble = MeshInstance3D.new()
	_bubble.name = "Bubble"
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	_bubble.mesh = sphere
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("tint", COLOR)
	material.render_priority = 3
	_bubble.material_override = material
	_bubble.position = Vector3(0.0, head * 0.5, 0.0)
	_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubble.visible = enemy != null and enemy.shield_hp > 0.0
	add_child(_bubble)
