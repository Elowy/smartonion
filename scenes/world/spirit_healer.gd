class_name SpiritHealer
extends Node3D
## The Spirit Healer (GDD 1): a floating, winged, translucent spirit at a fixed point of the
## arena ([constant Arena.SPIRIT_HEALER_POINT]) that brings ghosts back. A downed [Player]
## standing within [constant HEAL_RADIUS] (flat XZ distance) channels for
## [constant CHANNEL_TIME] seconds and comes back at full HP ([constant REVIVE_HP_RATIO]) with
## the usual light column and "Resurrected!" text. Leaving the circle resets that ghost's
## channel; several ghosts channel at once; living players are not affected.
##
## The channel shows on the ghost's "Resurrecting" cast bar in [constant CAST_COLOR] through
## [member Player.healer_channel] / [member Player.healer_seconds_left]: the bar shows whichever
## revive (teammates' or the healer's) is closer to completion, and whichever finishes first
## revives. Part of the level: a child of the Arena (not of the per-wave entities) that
## processes with it, so pausing the game pauses it. No collision: players, enemies and
## projectiles pass through it.
##
## Look (procedural placeholder, cheap for the GL Compatibility renderer – about ten draw
## calls, no shadows): robed, hooded body with open arms and two flapping wings
## ([method Mats.ghost] look, one own material each so they can brighten), glowing face and
## hands, golden halo, sash and cuffs, a faint aura, a rune circle on the ground marking
## HEAL_RADIUS, rising light motes and one OmniLight3D. While any ghost exists
## ([method is_active]) the circle, the spirit and the light pulse brighter and a soft light
## column marks the spot from afar.

## Emitted right after the healer revived [param player].
signal resurrected(player: Player)

## Ghosts closer than this (metres, flat XZ distance) channel.
const HEAL_RADIUS := 1.6
## Seconds a ghost has to stand in the circle.
const CHANNEL_TIME := 1.0
## HP fraction the healer revives at (100 %).
const REVIVE_HP_RATIO := 1.0
## Pale spirit colour of the ghost's cast bar while the healer channels.
const CAST_COLOR := Color(0.62, 0.86, 1.0)

## Rune circle tint; the circle's line lies on HEAL_RADIUS, the quad is RING_PAD x larger so
## its soft outer glow fits.
const RING_COLOR := Color(0.6, 0.84, 1.0)
const RING_PAD := 1.18
## Robe / wing tints (alpha = base translucency), calm and while a ghost needs the healer.
const BODY_IDLE := Color(0.7, 0.85, 1.0, 0.5)
const BODY_ACTIVE := Color(0.78, 0.9, 1.0, 0.62)
const WING_IDLE := Color(0.84, 0.93, 1.0, 0.42)
const WING_ACTIVE := Color(0.92, 0.97, 1.0, 0.56)
const HALO_COLOR := Color(1.0, 0.84, 0.4)
const GLOW_COLOR := Color(0.86, 0.95, 1.0)
const LIGHT_COLOR := Color(0.62, 0.84, 1.0)
## Soft additive glow around the spirit (calm / active strength).
const AURA_COLOR := Color(0.62, 0.82, 1.0)
const AURA_IDLE := 0.06
const AURA_ACTIVE := 0.13
## Size of the whole figure (the robe is ~2 m tall at 1.0).
const SPIRIT_SCALE := 1.12
## Height (m) of the spirit's origin (the tip of its wispy tail hangs below it).
const FLOAT_HEIGHT := 0.72
const BOB_HEIGHT := 0.12
const LIGHT_ENERGY_IDLE := 0.6
const LIGHT_ENERGY_ACTIVE := 1.5
const LIGHT_RANGE := 3.4
## Light column (only while a ghost exists): height and radius (m).
const COLUMN_HEIGHT := 11.0
const COLUMN_RADIUS := 1.0
## Seconds to fade between calm and active.
const FADE_TIME := 0.5

const _RING_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 rune_color : source_color = vec4(0.6, 0.84, 1.0, 1.0);
// Radius of the main circle in quad half-sizes (= the heal radius).
uniform float edge = 0.85;
// 0 = calm, 1 = a ghost needs the healer (brighter, pulsing).
uniform float intensity = 0.0;
// 0..1: the furthest channel in progress (the runes spin faster, the fill rises).
uniform float channel = 0.0;
// 0..1: short flash after a resurrection.
uniform float flare = 0.0;

float band(float r, float c, float w, float aa) {
	return smoothstep(c - w - aa, c - w + aa, r) * (1.0 - smoothstep(c + w - aa, c + w + aa, r));
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = max(fwidth(r) * 1.2, 0.003);
	float pulse = 0.5 + 0.5 * sin(TIME * 3.4);
	float glow = mix(0.62, 1.0, intensity) * (1.0 + 0.3 * intensity * pulse) + flare;
	// Main circle (the heal radius) with a white-hot core, a thin inner circle.
	float main_line = band(r, edge, 0.03, aa);
	float core = band(r, edge, 0.009, aa);
	float inner = band(r, edge * 0.7, 0.012, aa);
	// Rune band between the circles, slowly turning (faster while a ghost channels).
	float turn = TIME * (0.03 + 0.25 * channel);
	float ang = fract(atan(p.y, p.x) / 6.2831853 + 0.5 + turn);
	float seg = fract(ang * 18.0);
	float in_band = step(edge * 0.76, r) * step(r, edge * 0.92);
	float glyph = in_band * (step(0.1, seg) * step(seg, 0.22)
		+ step(0.4, seg) * step(seg, 0.78) * step(edge * 0.82, r) * step(r, edge * 0.86));
	// Hexagram inside, turning the other way.
	float a = -TIME * 0.12;
	vec2 q = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p;
	float star = 1.0;
	for (int i = 0; i < 6; i++) {
		float a0 = 6.2831853 * float(i) / 6.0;
		float a1 = 6.2831853 * float(i + 2) / 6.0;
		star = min(star, seg_dist(q, vec2(cos(a0), sin(a0)) * edge * 0.68, vec2(cos(a1), sin(a1)) * edge * 0.68));
	}
	float star_line = 1.0 - smoothstep(0.01, 0.01 + aa * 1.5, star);
	// Soft fill (brighter towards the rim) and a halo just outside the circle.
	float inside = 1.0 - smoothstep(edge - aa, edge + aa, r);
	float fill = inside * (0.06 + 0.1 * intensity + 0.22 * channel + 0.2 * flare) * (0.45 + 0.55 * r / edge);
	float halo = step(edge, r) * (1.0 - smoothstep(edge, 1.0, r)) * 0.4 * glow;
	float lines = clamp(main_line + glyph * 0.75 + inner * 0.6 + star_line * 0.45, 0.0, 1.0);
	ALBEDO = mix(rune_color.rgb, vec3(1.0), clamp(core + star_line * 0.3 + flare * 0.5, 0.0, 1.0));
	ALPHA = clamp(lines * glow * 0.9 + core * 0.5 * glow + fill + halo, 0.0, 1.0) * rune_color.a;
}
"""

## Light column (unit cylinder from y 0 to 1, scaled up): strongest at the ground; mixed, not
## added, so it reads as pale light instead of turning the grass mint.
const _COLUMN_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 fx_color : source_color = vec4(0.6, 0.84, 1.0, 1.0);
uniform float strength = 0.0;
varying float height;
void vertex() {
	height = VERTEX.y;
}
void fragment() {
	float h = clamp(height, 0.0, 1.0);
	float v = (1.0 - smoothstep(0.05, 1.0, h)) * smoothstep(0.0, 0.04, h);
	float edge = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	float rays = 0.72 + 0.28 * sin(UV.x * 6.2831853 * 4.0 + TIME * 1.3);
	float rise = 0.82 + 0.18 * sin(h * 26.0 - TIME * 3.0);
	ALBEDO = mix(fx_color.rgb, vec3(1.0), 0.55 * (1.0 - edge));
	ALPHA = clamp(strength * v * (0.2 + 0.8 * (1.0 - edge)) * rays * rise, 0.0, 1.0);
}
"""

## Soft glow ball (sphere): bright where it faces the camera, gone at its silhouette.
const _AURA_CODE := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_add, shadows_disabled;
uniform vec4 aura_color : source_color = vec4(0.82, 0.92, 1.0, 1.0);
uniform float strength = 0.2;
void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = aura_color.rgb;
	ALPHA = clamp(strength * pow(facing, 2.6), 0.0, 1.0);
}
"""

static var _shaders: Dictionary[String, Shader] = {}

## Ghosts (players with is_alive() false) currently in the tree – see [method is_active].
var ghost_count := 0

var _ring: MeshInstance3D
var _column: MeshInstance3D
var _motes: CPUParticles3D
var _light: OmniLight3D
var _spirit: Node3D
var _body: MeshInstance3D
var _wings: Array[Node3D] = []
var _wing_meshes: Array[MeshInstance3D] = []
var _halo: MeshInstance3D
var _glows: MeshInstance3D
var _aura: MeshInstance3D
## Channel seconds per ghost inside the circle (instance id -> seconds).
var _channels: Dictionary[int, float] = {}
## Smoothed 0 (calm) .. 1 (active) look, the strongest channel (0..1) and the flash after a
## resurrection.
var _glow := 0.0
var _channel_ratio := 0.0
var _flare := 0.0
var _time := 0.0
## Wing beat phase (accumulated: the beat speeds up while active without jumping).
var _wing_phase := 0.0


## A Spirit Healer with its whole look built (place it with position).
static func create() -> SpiritHealer:
	var h := SpiritHealer.new()
	h.name = "SpiritHealer"
	h._build()
	return h


## True while at least one ghost exists: the healer glows, pulses and shows its light column.
func is_active() -> bool:
	return ghost_count > 0


## True when [param point] is inside the heal circle (flat XZ distance).
func contains(point: Vector3) -> bool:
	return in_radius(global_position if is_inside_tree() else position, point)


## True when [param point] lies within HEAL_RADIUS of [param center] on the ground (XZ).
static func in_radius(center: Vector3, point: Vector3) -> bool:
	return Vector2(point.x - center.x, point.z - center.z).length() <= HEAL_RADIUS


## Seconds [param player] has channelled so far (0 outside the circle / when alive).
func channel_time(player: Player) -> float:
	if player == null:
		return 0.0
	return _channels.get(player.get_instance_id(), 0.0)


# --- Gameplay ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	var center := global_position
	var ghosts := 0
	var best := 0.0
	var channels: Dictionary[int, float] = {}
	var done: Array[Player] = []
	for node in get_tree().get_nodes_in_group(&"players"):
		var p := node as Player
		if p == null or not p.is_inside_tree():
			continue
		if p.is_alive():
			_clear(p)
			continue
		ghosts += 1
		if not in_radius(center, p.global_position):
			_clear(p)
			continue
		var t: float = _channels.get(p.get_instance_id(), 0.0) + delta
		if t >= CHANNEL_TIME - 0.0001:
			done.append(p)
			continue
		channels[p.get_instance_id()] = t
		p.healer_channel = t / CHANNEL_TIME
		p.healer_seconds_left = CHANNEL_TIME - t
		best = maxf(best, t / CHANNEL_TIME)
	_channels = channels
	_channel_ratio = best
	ghost_count = ghosts
	for p in done:
		_resurrect(p)


## The channel of [param p] ended (left the circle, alive again): nothing on its cast bar.
func _clear(p: Player) -> void:
	p.healer_channel = 0.0
	p.healer_seconds_left = -1.0


## Brings [param p] back at full HP: light column at its feet, "Resurrected!" (as a
## teammate revive does) and a flash of the healer itself.
func _resurrect(p: Player) -> void:
	_clear(p)
	var feet := p.global_position
	p.revive(REVIVE_HP_RATIO)
	Vfx.resurrect_column(feet)
	Vfx.floating_text(p.get_chest_position() + Vector3.UP * 0.6, "Resurrected!", Player.HEAL_TEXT_COLOR, 1.2)
	ghost_count = maxi(0, ghost_count - 1)
	_flare = 1.0
	resurrected.emit(p)


# --- Look ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _spirit == null:
		return
	_time += delta
	_glow = move_toward(_glow, 1.0 if is_active() else 0.0, delta / FADE_TIME)
	_flare = maxf(0.0, _flare - delta * 1.4)
	var pulse := 0.5 + 0.5 * sin(_time * 3.4)
	var g := _glow
	_spirit.position.y = FLOAT_HEIGHT + sin(_time * 1.7) * BOB_HEIGHT
	_spirit.rotation.z = sin(_time * 1.1) * 0.03
	_wing_phase = fmod(_wing_phase + delta * (2.2 + 1.2 * g), TAU)
	var flap := sin(_wing_phase) * (0.1 + 0.08 * g)
	for i in _wings.size():
		var side := 1.0 if i == 0 else -1.0
		_wings[i].rotation = Vector3(0.0, side * (0.42 + flap), side * (-0.06 - flap * 0.6))
	var ring_mat := _ring.material_override as ShaderMaterial
	ring_mat.set_shader_parameter(&"intensity", g)
	ring_mat.set_shader_parameter(&"channel", _channel_ratio)
	ring_mat.set_shader_parameter(&"flare", _flare)
	_set_ghost_color(_body, BODY_IDLE.lerp(BODY_ACTIVE, clampf(g * (0.8 + 0.2 * pulse) + _flare * 0.4, 0.0, 1.0)))
	var wing_color := WING_IDLE.lerp(WING_ACTIVE, clampf(g * (0.8 + 0.2 * pulse) + _flare * 0.4, 0.0, 1.0))
	for w in _wing_meshes:
		_set_ghost_color(w, wing_color)
	(_aura.material_override as ShaderMaterial).set_shader_parameter(&"strength",
		lerpf(AURA_IDLE, AURA_ACTIVE, g) * (1.0 + 0.25 * g * pulse) + 0.4 * _flare)
	var halo_scale := 1.0 + 0.08 * g * pulse + 0.25 * _flare
	_halo.scale = Vector3(halo_scale, 1.0, halo_scale)
	_light.light_energy = lerpf(LIGHT_ENERGY_IDLE, LIGHT_ENERGY_ACTIVE, g) * (1.0 + 0.2 * g * pulse) + 1.5 * _flare
	_column.visible = g > 0.01
	if _column.visible:
		(_column.material_override as ShaderMaterial).set_shader_parameter(&"strength", 0.5 * g * (0.85 + 0.15 * pulse))
	_motes.speed_scale = 1.0 + 0.8 * g


static func _set_ghost_color(mi: MeshInstance3D, c: Color) -> void:
	var m := mi.material_override as ShaderMaterial
	if m != null:
		m.set_shader_parameter(&"color", c)


func _build() -> void:
	_build_ring()
	_build_column()
	_build_motes()
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.position = Vector3(0, 1.5, 0)
	_light.light_color = LIGHT_COLOR
	_light.light_energy = LIGHT_ENERGY_IDLE
	_light.omni_range = LIGHT_RANGE
	_light.omni_attenuation = 1.2
	_light.shadow_enabled = false
	_light.light_specular = 0.0
	add_child(_light)
	_spirit = Node3D.new()
	_spirit.name = "Spirit"
	_spirit.position = Vector3(0, FLOAT_HEIGHT, 0)
	_spirit.scale = Vector3.ONE * SPIRIT_SCALE
	add_child(_spirit)
	var aura_mat := ShaderMaterial.new()
	aura_mat.shader = _shader("aura", _AURA_CODE)
	aura_mat.render_priority = 3
	aura_mat.set_shader_parameter(&"aura_color", AURA_COLOR)
	_aura = _mesh("Aura", _spirit, MeshKit.cached("spirit_healer:aura", func() -> Mesh:
		var k := MeshKit.new()
		k.add_sphere(1.0, Transform3D(), Color.WHITE, 16, 8)
		return k.build()), aura_mat)
	_aura.position = Vector3(0, 1.15, 0)
	_aura.scale = Vector3(1.25, 1.35, 1.25)
	_body = _mesh("Body", _spirit, _body_mesh(), _own_ghost_material(BODY_IDLE))
	_glows = _mesh("Glows", _spirit, _glows_mesh(), Mats.glow(GLOW_COLOR, 1.5))
	_halo = _mesh("Halo", _spirit, MeshKit.cached("spirit_healer:halo", func() -> Mesh:
		var k := MeshKit.new()
		k.add_torus(0.16, 0.24, Transform3D(), Color.WHITE, 24, 6)
		return k.build()), Mats.glow(HALO_COLOR, 1.1))
	_mesh("Trim", _spirit, _trim_mesh(), Mats.glow(HALO_COLOR, 0.6))
	_halo.position = Vector3(0, 2.08, -0.06)
	_halo.rotation = Vector3(deg_to_rad(-14.0), 0, 0)
	var wing := _wing_mesh()
	for side: float in [1.0, -1.0]:
		var pivot := Node3D.new()
		pivot.name = "WingR" if side > 0.0 else "WingL"
		pivot.position = Vector3(0.12 * side, 1.2, -0.16)
		_spirit.add_child(pivot)
		var mi := _mesh("Wing", pivot, wing, _own_ghost_material(WING_IDLE))
		mi.scale = Vector3(side, 1.0, 1.0)
		_wings.append(pivot)
		_wing_meshes.append(mi)
	_process(0.0)


func _mesh(n: String, parent: Node, mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A copy of [method Mats.ghost] the healer can brighten without touching the shared one.
static func _own_ghost_material(c: Color) -> ShaderMaterial:
	var m := (Mats.ghost(c) as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter(&"color", c)
	return m


func _build_ring() -> void:
	var m := ShaderMaterial.new()
	m.shader = _shader("ring", _RING_CODE)
	m.render_priority = -1
	m.set_shader_parameter(&"rune_color", RING_COLOR)
	m.set_shader_parameter(&"edge", 1.0 / RING_PAD)
	_ring = _mesh("Ring", self, MeshKit.cached("spirit_healer:quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q), m)
	var d := HEAL_RADIUS * 2.0 * RING_PAD
	_ring.scale = Vector3(d, 1.0, d)
	_ring.position.y = 0.025


func _build_column() -> void:
	var m := ShaderMaterial.new()
	m.shader = _shader("column", _COLUMN_CODE)
	# Before the spirit (ghost materials are priority 1): the light does not wash it out.
	m.render_priority = 0
	m.set_shader_parameter(&"fx_color", LIGHT_COLOR)
	_column = _mesh("Column", self, MeshKit.cached("spirit_healer:column", func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = 1.25
		c.bottom_radius = 1.0
		c.height = 1.0
		c.radial_segments = 20
		c.rings = 0
		c.cap_top = false
		c.cap_bottom = false
		var k := MeshKit.new()
		k.add_mesh(c, MeshKit.xf(Vector3(0, 0.5, 0)), Color.WHITE)
		return k.build()), m)
	_column.scale = Vector3(COLUMN_RADIUS, COLUMN_HEIGHT, COLUMN_RADIUS)
	_column.visible = false


func _build_motes() -> void:
	_motes = CPUParticles3D.new()
	_motes.name = "Motes"
	_motes.amount = 16
	_motes.lifetime = 2.6
	_motes.preprocess = 2.6
	_motes.local_coords = false
	_motes.mesh = MeshKit.cached("spirit_healer:mote", func() -> Mesh:
		var k := MeshKit.new()
		k.add_sphere(0.055, Transform3D(), Color.WHITE, 6, 3)
		return k.build())
	_motes.material_override = Mats.particle(true)
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_motes.emission_ring_axis = Vector3.UP
	_motes.emission_ring_radius = HEAL_RADIUS * 0.85
	_motes.emission_ring_inner_radius = 0.25
	_motes.emission_ring_height = 0.1
	_motes.direction = Vector3.UP
	_motes.spread = 12.0
	_motes.gravity = Vector3(0, 0.3, 0)
	_motes.initial_velocity_min = 0.4
	_motes.initial_velocity_max = 0.95
	_motes.scale_amount_min = 0.7
	_motes.scale_amount_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.75, 0.9, 1.0, 0.0))
	ramp.set_color(1, Color(0.75, 0.9, 1.0, 0.0))
	ramp.add_point(0.25, Color(0.88, 0.96, 1.0, 0.95))
	ramp.add_point(0.7, Color(0.7, 0.88, 1.0, 0.6))
	_motes.color_ramp = ramp
	_motes.seed = 4242
	_motes.position.y = 0.05
	_motes.emitting = true
	add_child(_motes)


static func _shader(key: String, code: String) -> Shader:
	if _shaders.has(key):
		return _shaders[key]
	var sh := Shader.new()
	sh.code = code
	_shaders[key] = sh
	return sh


## Robe (hem flaring, tapering into a wispy tail), open-fronted hood and bell sleeves of open
## arms. Faces +Z (towards the camera); origin at the spirit's float height.
static func _body_mesh() -> Mesh:
	return MeshKit.cached("spirit_healer:body", func() -> Mesh:
		var k := MeshKit.new()
		var robe := MeshKit.smooth_profile(PackedVector2Array([
			Vector2(0.0, -0.62), Vector2(0.1, -0.46), Vector2(0.28, -0.2), Vector2(0.47, 0.05),
			Vector2(0.54, 0.17), Vector2(0.5, 0.32), Vector2(0.42, 0.55), Vector2(0.34, 0.8),
			Vector2(0.3, 1.0), Vector2(0.32, 1.15), Vector2(0.36, 1.26), Vector2(0.28, 1.36),
			Vector2(0.14, 1.42), Vector2(0.0, 1.44),
		]), 3)
		k.add_lathe(robe, Transform3D(), Color.WHITE, 20)
		# Hood: open at the front (+Z, lathe angle 180) so the glowing face shows.
		var hood := MeshKit.smooth_profile(PackedVector2Array([
			Vector2(0.2, 1.36), Vector2(0.25, 1.5), Vector2(0.26, 1.63), Vector2(0.22, 1.77),
			Vector2(0.13, 1.88), Vector2(0.0, 1.95),
		]), 3)
		k.add_lathe(hood, Transform3D(), Color.WHITE, 16, -140.0, 140.0, true)
		# Bell sleeves of open, welcoming arms.
		for side: float in [1.0, -1.0]:
			var shoulder := Vector3(0.3 * side, 1.25, 0.0)
			var elbow := Vector3(0.52 * side, 1.08, 0.08)
			var wrist := Vector3(0.7 * side, 1.0, 0.2)
			k.add_segment(shoulder, elbow, 0.11, 0.12, Color.WHITE, 8)
			k.add_segment(elbow, wrist, 0.12, 0.18, Color.WHITE, 8, false)
		return k.build())


## Golden trim: a sash at the waist and the sleeve cuffs.
static func _trim_mesh() -> Mesh:
	return MeshKit.cached("spirit_healer:trim", func() -> Mesh:
		var k := MeshKit.new()
		k.add_torus(0.28, 0.32, MeshKit.xf(Vector3(0, 0.98, 0)), Color.WHITE, 20, 4)
		for side: float in [1.0, -1.0]:
			var cuff := Vector3(0.7 * side, 1.0, 0.2)
			var dir := Vector3(0.18 * side, -0.08, 0.12).normalized()
			k.add_torus(0.15, 0.19, Transform3D(MeshKit.basis_from_y(dir), cuff), Color.WHITE, 14, 4)
		return k.build())


## Glowing face inside the hood and the two hands.
static func _glows_mesh() -> Mesh:
	return MeshKit.cached("spirit_healer:glows", func() -> Mesh:
		var k := MeshKit.new()
		k.add_sphere(0.15, MeshKit.xf(Vector3(0, 1.6, 0.05), Vector3.ZERO, Vector3(0.9, 1.1, 0.7)), Color.WHITE, 12, 6)
		for side: float in [1.0, -1.0]:
			k.add_sphere(0.085, MeshKit.xf(Vector3(0.76 * side, 0.98, 0.24)), Color.WHITE, 10, 5)
		return k.build())


## One wing (right side; the left one is mirrored by its node scale): a feathered outline
## from the root at the shoulder blades up and out to the tip, primaries hanging below.
static func _wing_mesh() -> Mesh:
	return MeshKit.cached("spirit_healer:wing", func() -> Mesh:
		var outline := PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(0.16, 0.22), Vector2(0.42, 0.44), Vector2(0.72, 0.62),
			Vector2(1.02, 0.74), Vector2(1.28, 0.78), Vector2(1.46, 0.72),
			Vector2(1.26, 0.57), Vector2(1.34, 0.42), Vector2(1.11, 0.38), Vector2(1.15, 0.19),
			Vector2(0.92, 0.21), Vector2(0.92, 0.0), Vector2(0.71, 0.06), Vector2(0.67, -0.17),
			Vector2(0.49, -0.06), Vector2(0.41, -0.29), Vector2(0.26, -0.12), Vector2(0.13, -0.26),
			Vector2(0.05, -0.08),
		])
		var k := MeshKit.new()
		k.add_extrusion(outline, 0.035, Transform3D(), Color.WHITE)
		return k.build())
