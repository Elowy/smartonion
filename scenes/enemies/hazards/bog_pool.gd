class_name BogPool
extends ArenaHazard
## The Swamp's bog pool (GDD 16.1): a sticky pool lying in the arena for the whole wave (the director
## lays the same five again every wave). No telegraph and no damage: a hero standing in it moves
## [member hero_slow] percent slower (a GeneralBuff on the hero under [constant SLOW_KEY], refreshed
## while he stays and gone a moment after he leaves), an enemy [member enemy_slow] percent slower
## (Enemy.apply_slow, scanned every SCAN_TICKS physics ticks through the enemy grid; the heroes every
## HERO_SCAN_TICKS). Bots keep out
## of it, gently ([method hazard_push]: a weaker push than the damaging hazards').
##
## A pool does nothing per physics tick but the two scans: its materials are touched only while it fades
## in (FADE_IN, [member look_updates] counts them), and the bubbles swell and pop in a vertex shader on
## TIME ([method Mats.bubble]) – five pools used to cost ~0.1 ms of every physics tick re-writing the
## ring materials and 25 bubble transforms for a pool that never changes.
##
## M7b: the pool's water is a shader of its own ([constant _WATER_CODE]): a deep centre with a shallow,
## greener edge, slow ripples, drifting glints and a lighter wet edge, all animated on TIME. It keeps the
## ring shader's uniforms (ring_color, ring_shape, ring_stroke), so the fade-in above writes it exactly as
## it wrote the plain mud disc; the lime rim ([method marker_color]) stays the pool's marker.

const SLOW_KEY := &"bog_slow"
const MUD := Color(0.09, 0.08, 0.04)
const MUD_RIM := Color(0.78, 0.84, 0.34)
const BUBBLE_COLOR := Color(0.62, 0.82, 0.3)
## Seconds the slow outlasts a step out of the pool (the buff / slow is refreshed while inside).
const LINGER := 0.35
## Enemies are scanned every SCAN_TICKS physics ticks, heroes every HERO_SCAN_TICKS (the slow outlasts
## the gap: LINGER is far longer than three ticks). Pools are staggered by their index.
const SCAN_TICKS := 6
const HERO_SCAN_TICKS := 3
## How strongly a bot keeps away from the pool (a multiple of a damaging hazard's push) and its margin.
const BOT_WEIGHT := 0.5
const BOT_AVOID_MARGIN := 0.3
const FADE_IN := 0.4
const BUBBLES := 5

## The bog water: a filled disc (UV 0..1 on a quad) with the ring shader's uniforms.
const _WATER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 ring_color = vec4(0.09, 0.08, 0.04, 1.0);
uniform vec4 ring_shape = vec4(0.93, 1.0, 0.88, 1.0);
uniform float ring_stroke = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = fwidth(r) * 1.5;
	float disc = 1.0 - smoothstep(ring_shape.y - aa * 2.0, ring_shape.y, r);
	// Deep, dark middle; shallower and greener towards the bank.
	vec3 deep = ring_color.rgb * 0.6 + vec3(0.0, 0.02, 0.03);
	vec3 shallow = vec3(0.14, 0.21, 0.1);
	vec3 col = mix(shallow, deep, smoothstep(0.1, 0.85, 1.0 - r));
	// Slow, wobbling ripples spreading from the middle.
	vec2 q = p * 3.0;
	float wobble = (sin(q.x * 1.7 + TIME * 0.3) + sin(q.y * 2.1 - TIME * 0.2)) * 1.6;
	float ripple = smoothstep(0.55, 1.0, sin(r * 13.0 - TIME * 1.3 + wobble));
	col += vec3(0.05, 0.1, 0.08) * ripple * (1.0 - r);
	// Glints sliding over the surface.
	float g = sin(q.x * 3.7 + sin(q.y * 2.3 + TIME * 0.6) * 1.5 + TIME * 0.7) * sin(q.y * 3.3 - TIME * 0.5 + sin(q.x * 1.9) * 1.2);
	col += vec3(0.5, 0.78, 0.58) * smoothstep(0.5, 0.95, g) * 0.5 * (1.0 - 0.5 * r);
	// A lighter wet edge just inside the bank.
	col += vec3(0.38, 0.5, 0.2) * smoothstep(0.7, 0.93, r) * 0.28;
	ALBEDO = col;
	ALPHA = clamp(disc * 0.96, 0.0, 1.0) * ring_color.a;
}
"""

static var _water_shader: Shader

var hero_slow := 30.0
var enemy_slow := 15.0
## Serial number of the pool in its wave (staggers the enemy scan).
var index := 0
## Slows applied so far (tests): hero refreshes and enemy slows.
var hero_slows := 0
var enemy_slows := 0
## Times the pool wrote its ring materials (tests): while it fades in, never again afterwards.
var look_updates := 0

var _mud: MeshInstance3D
var _rim: MeshInstance3D
var _bubbles: Array[MeshInstance3D] = []
var _tick := 0
var _faded_in := false


static func spawn(parent: Node, pos: Vector3, p_radius: float, p_hero_slow: float, p_enemy_slow: float,
		p_index: int = 0, p_tally: EnvironmentHazards = null) -> BogPool:
	var h := BogPool.new()
	h.name = "BogPool"
	h.radius = p_radius
	h.telegraph_time = 0.0
	h.hero_slow = p_hero_slow
	h.enemy_slow = p_enemy_slow
	h.index = p_index
	h.color = MUD
	h.tally = p_tally
	place(parent, h, pos)
	return h


## The pool is marked by its bright rim (the mud itself is nearly as dark as the ground). This is the colour
## the rim is drawn in: in the picture the mud ring, which shares the render priority, covers most of it, so the
## swamp's pool reads as a dark oval (measured 1.3:1 for the rim, 1.4:1 for the oval against the olive ground in a
## screenshot; the rim on top of the mud would be a 4.4:1 lime ring, a look the art pass decides).
func marker_color() -> Color:
	return MUD_RIM


## Bots steer around the pool, but only mildly (it slows, it does not hurt).
func hazard_push(from: Vector3, margin: float = BOT_AVOID_MARGIN) -> Vector2:
	if not is_dangerous():
		return Vector2.ZERO
	return EnemyHazard.circle_push(global_position, radius, from, minf(margin, BOT_AVOID_MARGIN)) * BOT_WEIGHT


## A new bog water material (the shader is shared; one material per pool, like a ring: the fade-in writes
## its uniforms).
static func water_material() -> ShaderMaterial:
	if _water_shader == null:
		_water_shader = Shader.new()
		_water_shader.code = _WATER_CODE
	var m := ShaderMaterial.new()
	m.shader = _water_shader
	m.render_priority = -1
	return m


func _build() -> void:
	_mud = _ring("Mud", radius * 2.0)
	_mud.material_override = water_material()
	_rim = _ring("Rim", radius * 2.0)
	Mats.set_ring(_mud, MUD, 0.93, 1.0, 0.0)
	Mats.set_ring(_rim, MUD_RIM, 0.88, 0.99, 0.0)
	var bubble_mesh := MeshKit.cached("hazard:bog_bubble", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.11
		s.height = 0.22
		s.radial_segments = 8
		s.rings = 4
		return s)
	# One shared material: the bubble animates itself on the GPU, out of phase with its neighbours
	# (the phase comes from the bubble's place in the world).
	var bubble_material := Mats.bubble(BUBBLE_COLOR)
	for i in BUBBLES:
		var b := MeshInstance3D.new()
		b.name = "Bubble%d" % i
		b.mesh = bubble_mesh
		b.material_override = bubble_material
		var a := 2.399963 * float(i + 1) + float(index)
		var r := radius * (0.2 + 0.15 * float(i))
		b.position = Vector3(sin(a) * r, GROUND_Y, -cos(a) * r)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# (Hidden while the pool fades in: the bubbles would pop up on a bare ground.)
		b.visible = false
		add_child(b)
		_bubbles.append(b)


## (Called once from _ready: the pool starts invisible.)
func _update_telegraph(_progress: float) -> void:
	_update_fade_in()


func _strike() -> void:
	pass  # (a pool has nothing to strike: it is active at once)


func _update_active(_delta: float) -> void:
	_tick += 1
	if (_tick + index) % HERO_SCAN_TICKS == 0:
		for hero in heroes_in_circle():
			var buff := GeneralBuff.find(hero, SLOW_KEY)
			if buff == null or buff.left < LINGER * 0.5:
				GeneralBuff.apply(hero, SLOW_KEY, LINGER, {Stats.SPEED: -hero_slow})
				hero_slows += 1
	if (_tick + index) % SCAN_TICKS == 0:
		for e in enemies_in_circle():
			e.apply_slow(enemy_slow, LINGER * 1.5)
			enemy_slows += 1
	if not _faded_in:
		_update_fade_in()


## The pool appears: the mud and the rim fade in over FADE_IN seconds, then the bubbles show. The only
## place that writes the ring materials; once the fade is complete this is never called again.
func _update_fade_in() -> void:
	if _mud == null or _faded_in:
		return
	look_updates += 1
	var fade := clampf(age / FADE_IN, 0.0, 1.0)
	Mats.set_ring(_mud, Color(MUD.r, MUD.g, MUD.b, 0.88 * fade), 0.93, 1.0, 0.88 * fade)
	Mats.set_ring(_rim, Color(MUD_RIM.r, MUD_RIM.g, MUD_RIM.b, 0.9 * fade), 0.88, 0.985, 0.0)
	if fade >= 1.0:
		_faded_in = true
		for b in _bubbles:
			b.visible = true
