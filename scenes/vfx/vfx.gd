class_name Vfx
extends RefCounted
## Fire-and-forget effects (owned by the "visuals" module). Every node created here frees
## itself (see [VfxEffect]). Effects are parented to Arena.current.entities when an arena
## exists, otherwise to the current scene. Positions are world positions.
##
## Cheap by design: one VfxEffect node + 1-3 children per effect, shared meshes and shaders
## (each animated part owns a duplicate of a cached material – no instance uniforms, which
## the Compatibility renderer only fits for ~256 instances), small CPU particle bursts.
## Visual randomness uses a private RNG so gameplay determinism (RunState.rng) is untouched.

## Floating texts alive at once; extra non-crit texts (size <= 1) are dropped when the
## screen is busy. Crits may go CRIT_EXTRA_TEXTS above it.
const MAX_TEXTS := 28
const CRIT_EXTRA_TEXTS := 8
## Hits on the same target within this many seconds add up on one damage number.
const MERGE_WINDOW := 0.25
## Label3D uses fixed_size: pixel_size is the world size at 1 m, i.e. constant on screen.
const TEXT_PIXEL_SIZE := 0.00046
const TEXT_FONT_SIZE := 64
## Explosion flash: start alpha, radius factor and fade time (s) – a short pop, the ground
## ring and embers carry the effect so the targets stay visible.
const EXPLOSION_FLASH_ALPHA := 0.45
const EXPLOSION_FLASH_SCALE := 0.6
const EXPLOSION_FLASH_TIME := 0.15
## World height of ground decals (shock-wave rings) – they snap to the ground whatever
## height the effect itself was spawned at (explosions happen at projectile height ...).
const GROUND_Y := 0.04
## Extra height added to [method slash_arc] positions (callers pass feet + 0.3 m), so the
## swing reads at mid-body height.
const ARC_LIFT := 0.3
## Height (m) of the [method resurrect_column] light shaft.
const RESURRECT_HEIGHT := 14.0

const _ARC_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 arc_color = vec4(1.0);
uniform float arc_progress = 0.0;
uniform float arc_fade = 1.0;
void fragment() {
	float head = arc_progress;
	float behind = head - UV.x;
	float trail = step(0.0, behind) * clamp(1.0 - behind / 0.95, 0.0, 1.0);
	float body = smoothstep(0.0, 0.45, UV.y) * (1.0 - smoothstep(0.9, 1.0, UV.y));
	float core = smoothstep(0.6, 0.85, UV.y) * (1.0 - smoothstep(0.88, 1.0, UV.y));
	ALBEDO = mix(arc_color.rgb, vec3(1.0), core * 0.8);
	ALPHA = clamp(trail * (body * 0.95 + core) * arc_fade * arc_color.a, 0.0, 1.0);
}
"""

## Flash balls: mixed (not additive) so they keep their colour over the bright grass,
## with a hot white core.
const _GLOW_CODE := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 fx_color = vec4(1.0);
uniform float fx_fade = 1.0;
void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = mix(fx_color.rgb * 1.15, vec3(1.0), smoothstep(0.55, 1.0, facing) * 0.75);
	ALPHA = clamp(fx_color.a * fx_fade * (0.2 + 0.8 * pow(facing, 1.2)), 0.0, 1.0);
}
"""

## Level-up column (unit cylinder from y 0 to 1): strongest at the ground, fading upwards.
const _COLUMN_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;
uniform vec4 fx_color = vec4(1.0);
uniform float fx_fade = 1.0;
varying float height;
void vertex() {
	height = VERTEX.y;
}
void fragment() {
	float v = 1.0 - clamp(height, 0.0, 1.0);
	float stripes = 0.75 + 0.25 * sin(UV.x * 6.2831853 * 6.0 + TIME * 4.0);
	ALBEDO = fx_color.rgb;
	ALPHA = clamp(fx_color.a * fx_fade * v * v * stripes, 0.0, 1.0);
}
"""

## Light shaft from the sky (unit cylinder from y 0 to 1, scaled up): bright at the
## ground, fading out high up.
const _SKY_COLUMN_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;
uniform vec4 fx_color = vec4(1.0);
uniform float fx_fade = 1.0;
varying float height;
void vertex() {
	height = VERTEX.y;
}
void fragment() {
	float v = 1.0 - smoothstep(0.25, 1.0, clamp(height, 0.0, 1.0));
	float edge = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	float rays = 0.8 + 0.2 * sin(UV.x * 6.2831853 * 5.0 - TIME * 3.0);
	ALBEDO = mix(fx_color.rgb, vec3(1.0), 0.35 * (1.0 - edge));
	ALPHA = clamp(fx_color.a * fx_fade * v * (0.3 + 0.7 * (1.0 - edge)) * rays, 0.0, 1.0);
}
"""

const _RUNE_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 rune_color = vec4(1.0, 0.16, 0.1, 1.0);
uniform float rune_progress = 0.0;
uniform float rune_fade = 1.0;

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = max(fwidth(r) * 1.5, 0.004);
	float outer = smoothstep(0.84 - aa, 0.84 + aa, r) * (1.0 - smoothstep(0.96 - aa, 0.96 + aa, r));
	float inner = smoothstep(0.6 - aa, 0.6 + aa, r) * (1.0 - smoothstep(0.65 - aa, 0.65 + aa, r));
	float ang = atan(p.y, p.x) / 6.2831853 + 0.5;
	float seg = fract(ang * 14.0);
	float band = step(0.68, r) * step(r, 0.8);
	float glyph = band * (step(0.15, seg) * step(seg, 0.3) + step(0.5, seg) * step(seg, 0.85) * step(0.735, r));
	float star = 1.0;
	for (int i = 0; i < 5; i++) {
		float a0 = 6.2831853 * float(i) / 5.0 + 1.5708;
		float a1 = 6.2831853 * float(i + 2) / 5.0 + 1.5708;
		star = min(star, seg_dist(p, vec2(cos(a0), sin(a0)) * 0.6, vec2(cos(a1), sin(a1)) * 0.6));
	}
	float star_line = 1.0 - smoothstep(0.012, 0.012 + aa * 1.5, star);
	float speed = 5.0 + 22.0 * rune_progress;
	float pulse = 0.72 + 0.28 * sin(TIME * speed);
	float fill = (1.0 - smoothstep(0.84, 0.88, r)) * (0.12 + 0.2 * rune_progress) * pulse;
	float lines = clamp(outer + inner * 0.85 + glyph * 0.9 + star_line * 0.8, 0.0, 1.0);
	// White-hot core inside the red lines (outer circle and star) plus a soft white glow
	// along the inner rim: readable without relying on red alone (colour-blind players).
	float core_ring = smoothstep(0.885 - aa, 0.885 + aa, r) * (1.0 - smoothstep(0.915 - aa, 0.915 + aa, r));
	float core_star = 1.0 - smoothstep(0.004, 0.004 + aa, star);
	float rim_glow = smoothstep(0.62, 0.84, r) * (1.0 - smoothstep(0.84, 0.86, r)) * 0.35;
	float core = clamp(core_ring + core_star * 0.85 + rim_glow, 0.0, 1.0) * (0.75 + 0.25 * pulse);
	vec3 col = mix(rune_color.rgb, vec3(1.0, 0.75, 0.55), lines * 0.35 * rune_progress);
	ALBEDO = mix(col, vec3(1.0, 0.97, 0.94), core);
	ALPHA = clamp(lines * pulse + fill + core * 0.6, 0.0, 1.0) * clamp(rune_fade, 0.0, 1.6) * rune_color.a;
}
"""

static var _text_count := 0
static var _rng := RandomNumberGenerator.new()
static var _materials: Dictionary[String, Material] = {}
## Live damage numbers by target instance id (see [method damage_number]).
static var _merge: Dictionary[int, VfxEffect] = {}


## Floating combat text (damage, "Dodge", "Resurrected!" ...) in WoW scrolling-combat-text
## style: pops in, then arcs up and sideways. [param size] 1 = normal (crits bigger);
## [param color] alpha is the text's opacity. [param side] +1 / -1 arcs to the right / left,
## 0 picks a random side.
static func floating_text(pos: Vector3, text: String, color: Color, size: float = 1.0, side: float = 0.0) -> void:
	_text(pos, text, color, size, side)


## A damage number on [param target] (merge key: hits on the same target within
## MERGE_WINDOW add up on one number that pops again; null never merges). Nothing is drawn when the
## Damage Numbers setting is off. A crit merged into
## a normal number upgrades it to [param color] / [param size].
static func damage_number(target: Object, pos: Vector3, amount: float, color: Color, size: float) -> void:
	if not Settings.damage_numbers_enabled():
		return
	var key := target.get_instance_id() if target != null and is_instance_valid(target) else 0
	if key != 0 and _merge.has(key):
		var live: VfxEffect = _merge[key]
		if is_instance_valid(live) and not live.is_queued_for_deletion() and live.age < MERGE_WINDOW:
			live.amount += amount
			if size > live.size:
				live.size = size
				live.color = color
				var label := live.main as Label3D
				if label != null:
					label.pixel_size = TEXT_PIXEL_SIZE * size
					label.modulate = Color(color.r, color.g, color.b, label.modulate.a)
			(live.main as Label3D).text = format_damage(live.amount)
			live.repop()
			return
		_merge.erase(key)
	var fx := _text(pos, format_damage(amount), color, size, 0.0)
	if fx == null:
		return
	fx.amount = amount
	if key != 0:
		fx.merge_key = key
		_merge[key] = fx


## Whole-number damage text (at least 1).
static func format_damage(amount: float) -> String:
	return str(maxi(1, roundi(amount)))


static func _text(pos: Vector3, text: String, color: Color, size: float, side: float) -> VfxEffect:
	if _text_count >= MAX_TEXTS + CRIT_EXTRA_TEXTS or (_text_count >= MAX_TEXTS and size <= 1.0):
		return null
	var fx := _effect(VfxEffect.Kind.TEXT, pos, 0.8 + 0.15 * size)
	if fx == null:
		return null
	_text_count += 1
	var label := Label3D.new()
	label.name = "Label"
	label.text = text
	label.font_size = TEXT_FONT_SIZE
	label.pixel_size = TEXT_PIXEL_SIZE * size
	label.outline_size = 18
	label.modulate = Color(color.r, color.g, color.b, color.a)
	label.outline_modulate = Color(0.08, 0.04, 0.05, color.a)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.double_sided = true
	label.fixed_size = true
	label.render_priority = 20
	label.outline_render_priority = 19
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(label)
	fx.main = label
	fx.size = size
	fx.color = color
	var s := signf(side) if side != 0.0 else (1.0 if _rng.randf() < 0.5 else -1.0)
	# Sideways part of the arc (world X = screen X); a little random so numbers fan out.
	fx.drift = Vector3(s * _rng.randf_range(0.3, 0.55), 0.0, _rng.randf_range(-0.08, 0.08))
	_start(fx)
	return fx


## Melee swing arc on the ground plane.
static func slash_arc(pos: Vector3, direction: Vector3, radius: float, arc_degrees: float, color: Color) -> void:
	var fx := _effect(VfxEffect.Kind.ARC, pos, 0.2)
	if fx == null:
		return
	var deg := clampf(snappedf(arc_degrees, 10.0), 10.0, 360.0)
	var mi := MeshInstance3D.new()
	mi.name = "Arc"
	mi.mesh = MeshKit.cached("vfx:arc:%d" % int(deg), func() -> Mesh:
		var k := MeshKit.new()
		k.add_arc(0.5, 1.0, deg, Transform3D(), Color.WHITE, maxi(8, int(deg / 6.0)))
		return k.build())
	mi.material_override = _unique_material("arc", _ARC_CODE)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * maxf(radius, 0.1)
	VfxEffect.param(mi, &"arc_color", Color(color.r, color.g, color.b, 1.0))
	fx.add_child(mi)
	fx.main = mi
	fx.color = color
	var flat := Vector2(direction.x, direction.z)
	if flat.length_squared() > 0.0001:
		fx.rotation.y = atan2(-direction.x, -direction.z)
	# Swing at mid-body height so it reads over the crowd.
	fx.position.y += ARC_LIFT
	_start(fx)


static func hit_spark(pos: Vector3, color: Color) -> void:
	var fx := _effect(VfxEffect.Kind.SPARK, pos, 0.3)
	if fx == null:
		return
	fx.size = 0.26
	fx.color = color
	fx.flash = _glow_ball(fx, color.lerp(Color.WHITE, 0.4), 0.9)
	fx.flash.position.y = 0.0
	var p := _particles(fx, 9, 0.28, _spark_mesh(), Mats.particle(true))
	p.particle_flag_align_y = true
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 3.5
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -6, 0)
	p.damping_min = 6.0
	p.damping_max = 9.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	p.color_ramp = _fade_gradient(color.lerp(Color.WHITE, 0.5), color)
	_start(fx)


## [param pos] is the body centre (the shock ring snaps to the ground).
static func death_puff(pos: Vector3, color: Color, size: float = 1.0) -> void:
	var fx := _effect(VfxEffect.Kind.PUFF, pos, 0.7)
	if fx == null:
		return
	fx.size = size
	fx.color = Color(color.r, color.g, color.b, 0.75)
	fx.ring = _ground_ring(fx)
	var smoke := _particles(fx, 10, 0.6, _ball_mesh(), Mats.particle(false))
	smoke.position.y = 0.05 * size
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.25 * size
	smoke.direction = Vector3.UP
	smoke.spread = 75.0
	smoke.initial_velocity_min = 1.2 * size
	smoke.initial_velocity_max = 2.6 * size
	smoke.gravity = Vector3(0, 1.2, 0)
	smoke.damping_min = 2.5
	smoke.damping_max = 4.0
	smoke.scale_amount_min = 0.9 * size
	smoke.scale_amount_max = 1.6 * size
	smoke.scale_amount_curve = _grow_curve()
	var light := color.lerp(Color(0.95, 0.93, 0.9), 0.55)
	smoke.color_ramp = _fade_gradient(Color(light.r, light.g, light.b, 0.95), Color(light.r, light.g, light.b, 0.0))
	var bits := _particles(fx, 6, 0.55, _chip_mesh(), Mats.particle(false))
	bits.position.y = 0.1 * size
	bits.direction = Vector3.UP
	bits.spread = 60.0
	bits.initial_velocity_min = 2.5
	bits.initial_velocity_max = 4.5
	bits.gravity = Vector3(0, -14, 0)
	bits.angular_velocity_min = -400.0
	bits.angular_velocity_max = 400.0
	bits.color_ramp = _fade_gradient(color, Color(color.r, color.g, color.b, 0.0))
	_start(fx)


static func explosion(pos: Vector3, radius: float, color: Color) -> void:
	Audio.play(&"explosion", clampf(radius - 2.0, -5.0, 2.0))
	var fx := _effect(VfxEffect.Kind.EXPLOSION, pos, 0.55)
	if fx == null:
		return
	fx.size = maxf(radius, 0.3)
	fx.color = color
	# Short, faint, small flash: the targets inside stay readable (ring + embers carry it).
	fx.flash = _glow_ball(fx, color, EXPLOSION_FLASH_ALPHA)
	fx.flash.position.y = 0.0
	fx.ring = _ground_ring(fx)
	var embers := _particles(fx, 14, 0.5, _ball_mesh(), Mats.particle(true))
	embers.position.y = 0.0
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = radius * 0.3
	embers.direction = Vector3.UP
	embers.spread = 100.0
	embers.initial_velocity_min = radius * 2.5
	embers.initial_velocity_max = radius * 5.0
	embers.gravity = Vector3(0, -4, 0)
	embers.damping_min = 4.0
	embers.damping_max = 7.0
	embers.scale_amount_min = 0.25
	embers.scale_amount_max = 0.55
	embers.color_ramp = _fade_gradient(color.lerp(Color.WHITE, 0.3), Color(color.r, color.g, color.b, 0.0))
	_start(fx)


## Red rune circle warning that an enemy will spawn here in [param duration] seconds.
static func spawn_telegraph(pos: Vector3, radius: float, duration: float) -> void:
	var fx := _effect(VfxEffect.Kind.TELEGRAPH, pos, maxf(duration, 0.05) + 0.15)
	if fx == null:
		return
	fx.size = radius
	var mi := MeshInstance3D.new()
	mi.name = "Rune"
	mi.mesh = _quad()
	mi.material_override = _unique_material("rune", _RUNE_CODE)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.035
	mi.set_meta(&"diameter", maxf(radius, 0.3) * 2.0)
	VfxEffect.param(mi, &"rune_color", Color(1.0, 0.16, 0.1, 1.0))
	fx.add_child(mi)
	fx.main = mi
	_start(fx)


static func level_up_burst(pos: Vector3) -> void:
	Audio.play(&"level_up")
	var gold := Color(1.0, 0.82, 0.3)
	var fx := _effect(VfxEffect.Kind.LEVEL_UP, pos, 1.0)
	if fx == null:
		return
	fx.color = gold
	var column := MeshInstance3D.new()
	column.name = "Column"
	column.mesh = MeshKit.cached("vfx:column", func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = 0.75
		c.bottom_radius = 0.6
		c.height = 1.0
		c.radial_segments = 20
		c.rings = 1
		c.cap_top = false
		c.cap_bottom = false
		var k := MeshKit.new()
		k.add_mesh(c, MeshKit.xf(Vector3(0, 0.5, 0)), Color.WHITE)
		return k.build())
	column.material_override = _unique_material("column", _COLUMN_CODE)
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	VfxEffect.param(column, &"fx_color", Color(1.0, 0.88, 0.42, 1.0))
	fx.add_child(column)
	fx.main = column
	fx.size = 0.9
	fx.flash = _glow_ball(fx, Color(1.0, 0.9, 0.5), 1.0)
	fx.flash.position.y = 0.7
	fx.ring = _ground_ring(fx)
	var sparks := _particles(fx, 26, 0.9, _star_mesh(), Mats.particle(true))
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sparks.emission_ring_axis = Vector3.UP
	sparks.emission_ring_radius = 0.7
	sparks.emission_ring_inner_radius = 0.3
	sparks.emission_ring_height = 0.1
	sparks.direction = Vector3.UP
	sparks.spread = 20.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 4.5
	sparks.gravity = Vector3(0, -1.0, 0)
	sparks.explosiveness = 0.7
	sparks.angular_velocity_min = -200.0
	sparks.angular_velocity_max = 200.0
	sparks.color_ramp = _fade_gradient(Color(1.0, 0.95, 0.6), Color(1.0, 0.7, 0.2, 0.0))
	_start(fx)


## Resurrection (GDD 1): a shaft of golden light from the sky onto [param pos] (the
## revived player's feet), a shock ring and rising sparkles.
static func resurrect_column(pos: Vector3) -> void:
	Audio.play(&"revive")
	var fx := _effect(VfxEffect.Kind.RESURRECT, pos, 1.3)
	if fx == null:
		return
	fx.color = Color(1.0, 0.9, 0.55)
	fx.size = RESURRECT_HEIGHT
	var column := MeshInstance3D.new()
	column.name = "Column"
	column.mesh = MeshKit.cached("vfx:sky_column", func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = 0.8
		c.bottom_radius = 0.55
		c.height = 1.0
		c.radial_segments = 20
		c.rings = 0
		c.cap_top = false
		c.cap_bottom = false
		var k := MeshKit.new()
		k.add_mesh(c, MeshKit.xf(Vector3(0, 0.5, 0)), Color.WHITE)
		return k.build())
	column.material_override = _unique_material("sky_column", _SKY_COLUMN_CODE)
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	VfxEffect.param(column, &"fx_color", Color(1.0, 0.86, 0.45, 0.6))
	fx.add_child(column)
	fx.main = column
	fx.flash = _glow_ball(fx, Color(1.0, 0.95, 0.7), 0.85)
	fx.flash.position.y = 0.7
	fx.ring = _ground_ring(fx)
	var motes := _particles(fx, 18, 1.1, _star_mesh(), Mats.particle(true))
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 0.6
	motes.position.y = 0.4
	motes.direction = Vector3.UP
	motes.spread = 25.0
	motes.initial_velocity_min = 1.0
	motes.initial_velocity_max = 2.6
	motes.gravity = Vector3(0, 0.6, 0)
	motes.explosiveness = 0.6
	motes.angular_velocity_min = -180.0
	motes.angular_velocity_max = 180.0
	motes.color_ramp = _fade_gradient(Color(1.0, 0.97, 0.75), Color(1.0, 0.8, 0.3, 0.0))
	_start(fx)


## Small coin sparkle when loot is collected.
static func pickup_sparkle(pos: Vector3) -> void:
	var gold := Color(1.0, 0.85, 0.3)
	var fx := _effect(VfxEffect.Kind.SPARKLE, pos, 0.4)
	if fx == null:
		return
	fx.size = 0.2
	fx.color = gold
	fx.flash = _glow_ball(fx, gold, 0.85)
	fx.flash.position.y = 0.0
	var p := _particles(fx, 8, 0.4, _star_mesh(), Mats.particle(true))
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 1.8
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0, -5, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.3
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	p.color_ramp = _fade_gradient(Color(1.0, 0.97, 0.7), Color(1.0, 0.75, 0.2, 0.0))
	_start(fx)


## Number of floating texts currently alive (for tests / debugging).
static func text_count() -> int:
	return _text_count


# --- Internals ---------------------------------------------------------------

## The node effects are parented to (null when there is no scene tree).
static func effect_parent() -> Node:
	var arena := Arena.current
	if arena != null and is_instance_valid(arena) and arena.entities != null and arena.entities.is_inside_tree():
		return arena.entities
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	if tree.current_scene != null and tree.current_scene.is_inside_tree():
		return tree.current_scene
	return tree.root


static func _effect(kind: VfxEffect.Kind, pos: Vector3, life: float) -> VfxEffect:
	var parent := effect_parent()
	if parent == null:
		return null
	var fx := VfxEffect.new()
	fx.name = "Vfx_%s" % VfxEffect.Kind.keys()[kind]
	fx.kind = kind
	fx.life = life
	fx.set_meta(&"parent", parent)
	fx.set_meta(&"pos", pos)
	return fx


## Adds the finished effect to the tree at its world position.
static func _start(fx: VfxEffect) -> void:
	var parent: Node = fx.get_meta(&"parent")
	var pos: Vector3 = fx.get_meta(&"pos")
	var local := fx.position
	fx.remove_meta(&"parent")
	fx.remove_meta(&"pos")
	var origin := pos
	if parent is Node3D and (parent as Node3D).is_inside_tree():
		origin = (parent as Node3D).global_transform.affine_inverse() * pos
	fx.position = origin + local
	if fx.ring != null:
		fx.ring.position.y = GROUND_Y - (pos.y + local.y)
	parent.add_child(fx)
	for child in fx.get_children():
		if child is CPUParticles3D:
			(child as CPUParticles3D).restart()


## A fresh copy of the cached material [param key] (shared shader, own parameters).
static func _unique_material(key: String, code: String) -> Material:
	return _material(key, code).duplicate()


static func _material(key: String, code: String) -> Material:
	if _materials.has(key):
		return _materials[key]
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = 2
	_materials[key] = m
	return m


static func _quad() -> Mesh:
	return MeshKit.cached("vfx:quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)


static func _ground_ring(fx: VfxEffect) -> GeometryInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Ring"
	mi.mesh = _quad()
	mi.material_override = Mats.ring()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.04
	mi.scale = Vector3(0.01, 1, 0.01)
	Mats.set_ring(mi, Color(fx.color.r, fx.color.g, fx.color.b, 0.0), 0.8, 0.97, 0.0)
	fx.add_child(mi)
	return mi


static func _glow_ball(fx: VfxEffect, color: Color, alpha: float) -> GeometryInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Flash"
	mi.mesh = MeshKit.cached("vfx:ball", func() -> Mesh:
		var k := MeshKit.new()
		k.add_sphere(1.0, Transform3D(), Color.WHITE, 16, 8)
		return k.build())
	mi.material_override = _unique_material("glow", _GLOW_CODE)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.5
	mi.scale = Vector3.ONE * 0.01
	VfxEffect.param(mi, &"fx_color", Color(color.r, color.g, color.b, alpha))
	fx.add_child(mi)
	return mi


static func _particles(fx: VfxEffect, amount: int, lifetime: float, mesh: Mesh, material: Material) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Particles%d" % fx.get_child_count()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.mesh = mesh
	p.material_override = material
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.seed = _rng.randi()
	p.emitting = true
	fx.add_child(p)
	return p


static func _spark_mesh() -> Mesh:
	return MeshKit.cached("vfx:spark", func() -> Mesh:
		var k := MeshKit.new()
		k.add_box(Vector3(0.07, 0.42, 0.07), Transform3D(), Color.WHITE)
		return k.build())


static func _ball_mesh() -> Mesh:
	return MeshKit.cached("vfx:smoke", func() -> Mesh:
		var k := MeshKit.new()
		k.add_sphere(0.18, Transform3D(), Color.WHITE, 8, 4)
		return k.build())


static func _chip_mesh() -> Mesh:
	return MeshKit.cached("vfx:chip", func() -> Mesh:
		var k := MeshKit.new()
		k.add_box(Vector3(0.09, 0.07, 0.06), Transform3D(), Color.WHITE)
		return k.build())


static func _star_mesh() -> Mesh:
	return MeshKit.cached("vfx:star", func() -> Mesh:
		var k := MeshKit.new()
		k.add_sphere(0.07, MeshKit.xf(Vector3.ZERO, Vector3(0, 0, 45), Vector3(1.0, 1.0, 0.35)), Color.WHITE, 4, 2)
		return k.build())


static func _fade_gradient(from: Color, to: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, to)
	return g


static func _grow_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.5))
	c.add_point(Vector2(0.3, 1.0))
	c.add_point(Vector2(1.0, 0.7))
	return c
