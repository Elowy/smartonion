class_name WarriorSpinVfx
extends Node3D
## The Whirlwind's spin: three translucent blade arcs and glinting blades circling the hero on
## the ground, a faint outer ring. Child of the hero (follows it) – or of a Ravager axe –,
## frees itself after its duration. Bladestorm spins more arcs, faster. Purely visual – the
## damage comes from [WarriorSpin].

const ARC_COUNT := 3
const ARC_DEGREES := 100.0
const INNER_RATIO := 0.4
const TURNS_PER_SECOND := 2.5
const FADE_IN := 0.1
const FADE_OUT := 0.25
const GROUND_Y := 0.06
const BLADE_HEIGHT := 0.7
const ARC_ALPHA := 0.5
const RING_ALPHA := 0.35
const BLADE_ALPHA := 0.9

var radius := 3.0
var duration := 1.0
var color := Color(0.9, 0.3, 0.2)
var arcs := ARC_COUNT
var turns_per_second := TURNS_PER_SECOND
## Bladestorm: spectral greatswords (WarriorExecuteVfx.sword_mesh) instead of plain blades.
var swords := false

var _elapsed := 0.0
var _spin: Node3D
var _materials: Array[StandardMaterial3D] = []
var _alphas: Array[float] = []


## Starts a spin around [param hero] (parented to it). Null when the hero is not in the tree.
## [param p_arcs] blade arcs turning [param p_turns] times a second; [param p_name] names the
## node (tests find it by name).
static func spawn(hero: Node3D, p_radius: float, p_duration: float, p_color: Color,
		p_arcs: int = ARC_COUNT, p_turns: float = TURNS_PER_SECOND, p_name: String = "WhirlwindSpin",
		p_swords: bool = false) -> WarriorSpinVfx:
	if hero == null or not hero.is_inside_tree():
		return null
	var fx := WarriorSpinVfx.new()
	fx.name = p_name
	fx.radius = maxf(0.5, p_radius)
	fx.duration = maxf(0.1, p_duration)
	fx.color = p_color
	fx.arcs = maxi(1, p_arcs)
	fx.turns_per_second = p_turns
	fx.swords = p_swords
	hero.add_child(fx)
	return fx


func _ready() -> void:
	position.y = GROUND_Y
	_spin = Node3D.new()
	_spin.name = "Spin"
	add_child(_spin)
	var arc_mesh := MeshKit.cached("warrior:spin_arc", func() -> Mesh:
		return MeshKit.new().add_arc(INNER_RATIO, 1.0, ARC_DEGREES, Transform3D.IDENTITY, Color.WHITE, 16).build())
	var blade_mesh := MeshKit.cached("warrior:spin_blade", func() -> Mesh:
		return MeshKit.new().add_box(Vector3(0.14, 0.05, 0.95), MeshKit.xf(Vector3(0.0, 0.0, -0.52)),
				Color.WHITE).build())
	var ring_mesh := MeshKit.cached("warrior:spin_ring", func() -> Mesh:
		return MeshKit.new().add_arc(0.94, 1.0, 360.0, Transform3D.IDENTITY, Color.WHITE, 48).build())
	for i in arcs:
		var yaw := TAU * float(i) / float(arcs)
		var arc := _part(arc_mesh, Color(color.r, color.g, color.b), ARC_ALPHA)
		arc.rotation.y = yaw
		arc.scale = Vector3(radius, 1.0, radius)
		_spin.add_child(arc)
		if swords:
			_spin.add_child(_sword(yaw + deg_to_rad(ARC_DEGREES * 0.5)))
			continue
		# A glinting blade on the leading edge of every arc, at weapon height.
		var blade := _part(blade_mesh, Color(0.92, 0.94, 1.0), BLADE_ALPHA)
		blade.position.y = BLADE_HEIGHT - GROUND_Y
		blade.rotation.y = yaw + deg_to_rad(ARC_DEGREES * 0.5)
		blade.scale = Vector3(1.0, 1.0, radius)
		_spin.add_child(blade)
	var ring := _part(ring_mesh, Color(color.r, color.g, color.b).lerp(Color.WHITE, 0.3), RING_ALPHA)
	ring.scale = Vector3(radius, 1.0, radius)
	add_child(ring)
	_apply_fade()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	_spin.rotation.y -= delta * TAU * turns_per_second
	_apply_fade()


## A greatsword lying flat at weapon height along [param yaw], hilt near the hero, tip on the
## edge of the reach.
func _sword(yaw: float) -> Node3D:
	var holder := Node3D.new()
	holder.rotation.y = yaw
	holder.position.y = BLADE_HEIGHT - GROUND_Y
	var s := clampf((radius - 0.5) / 2.6, 0.35, 1.6)
	var sword := _part(WarriorExecuteVfx.sword_mesh(), Color.WHITE, BLADE_ALPHA)
	(sword.material_override as StandardMaterial3D).vertex_color_use_as_albedo = true
	# Rotated so the pommel points at the hero (+Z) and the tip outwards (-Z).
	sword.rotation.x = deg_to_rad(90.0)
	sword.scale = Vector3.ONE * s
	sword.position.z = -(0.5 + 2.5 * s)
	holder.add_child(sword)
	return holder


func _part(mesh: Mesh, tint: Color, alpha: float) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	_materials.append(m)
	_alphas.append(alpha)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _apply_fade() -> void:
	var fade := clampf(minf(_elapsed / FADE_IN, (duration - _elapsed) / FADE_OUT), 0.0, 1.0)
	for i in _materials.size():
		_materials[i].albedo_color.a = _alphas[i] * fade
