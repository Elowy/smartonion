class_name ArenaAmbient
extends Node3D
## Ambient life of an arena environment (M7b VIS-ENV): a few small particle systems that drift through
## the part of the arena the camera shows, one look per environment – leaves and fireflies in the
## forest, ground mist and pale motes in the cemetery, mist with fireflies and bubbles in the swamp,
## embers and ash at the volcano, snow and glints in the ice cave, dust in the dungeon.
##
## Cheap on purpose: every look is two systems at most (two draw calls), 100 particles at most in all, each
## a CPUParticles3D with one shared billboard quad and one cached unshaded material. CPUParticles3D
## rather than GPUParticles3D: with these counts the CPU work is a few hundredths of a millisecond, it
## needs no transform-feedback support from the GL driver (the Compatibility renderer's weakest spot on
## old integrated GPUs), it runs and tests headless, and the game's 18 other particle effects are CPU
## particles too. The particles live in world space; the node follows the camera's focus and sizes its
## emission box to the ground the camera shows ([method follow]), so the density on screen stays about
## the same however far the camera is zoomed out.
##
## They never get in the way: tiny, low alpha, drawn with a lower render priority than the ground rings
## and telegraphs (so a telegraph is always on top of the mist), the leaves and flakes high above the
## heroes and fading out before they reach them, mist hugging the ground. Visual only: the particles use
## their own fixed seed, never RunState.rng, and nothing here touches gameplay.

const MIST := &"mist"
const SPECK := &"speck"  # a small round dot with a soft rim (embers, ash, snow, motes, fireflies, dust)
const LEAF := &"leaf"
const GLINT := &"glint"
const ATLAS := &"atlas"

## The most particles of all systems of one look (a test pins it) and the most systems.
const MAX_PARTICLES := 100
const MAX_SYSTEMS := 2
## The box is a little bigger than the view so a particle never pops in at the screen edge.
const BOX_MARGIN := 1.2
## A focus jump this long (m) is a camera snap (a layout change): the particles start over.
const SNAP_DISTANCE := 12.0

static var _textures: Dictionary[StringName, Texture2D] = {}
static var _materials: Dictionary[String, Material] = {}
static var _meshes: Dictionary[String, Mesh] = {}

## The look (an ArenaGround look id) and the systems built for it.
var look: StringName = ArenaGround.FOREST
var systems: Array[CPUParticles3D] = []

var _arena: Arena
var _last_focus := Vector3.INF
var _last_distance := -1.0
var _time := 0.0
## The volcano's light as the data set it (sun energy, ambient energy), read on the first flicker.
var _flicker_base := Vector2.ZERO


## The ambient life of [param p_look] for [param p_arena] (follows its camera).
static func create(p_arena: Arena, p_look: StringName) -> ArenaAmbient:
	var a := ArenaAmbient.new()
	a.name = "Ambient"
	a.look = p_look
	a._arena = p_arena
	for i in specs_for(p_look).size():
		var spec: Dictionary = specs_for(p_look)[i]
		var p := _build_system(spec, 1000 + i * 17 + p_look.hash() % 97)
		a.systems.append(p)
		a.add_child(p)
	return a


## The particle systems of [param p_look] as plain data (tests read them): name, texture kind, amount,
## lifetime, look of the material, the emission height band and the motion.
static func specs_for(p_look: StringName) -> Array[Dictionary]:
	match p_look:
		ArenaGround.CEMETERY:
			return [
				{"name": "Mist", "kind": MIST, "amount": 16, "life": 12.0, "y": 0.35, "half_y": 0.12,
					"color": Color(0.62, 0.64, 0.88), "alpha": 0.24, "scale": Vector2(3.2, 5.6), "flat": true,
					"velocity": Vector2(0.15, 0.35), "dir": Vector3(1.0, 0.0, 0.3), "gravity": Vector3.ZERO,
					"damping": 0.0, "spin": 8.0},
				{"name": "Motes", "kind": SPECK, "amount": 28, "life": 7.0, "y": 1.7, "half_y": 1.5,
					"color": Color(0.72, 0.98, 0.92), "alpha": 0.8, "scale": Vector2(0.07, 0.14), "additive": true,
					"velocity": Vector2(0.08, 0.28), "dir": Vector3.UP, "spread": 180.0,
					"gravity": Vector3(0.0, 0.05, 0.0), "damping": 0.6},
			]
		ArenaGround.SWAMP:
			return [
				{"name": "Mist", "kind": MIST, "amount": 12, "life": 12.0, "y": 0.3, "half_y": 0.12,
					"color": Color(0.56, 0.68, 0.42), "alpha": 0.15, "scale": Vector2(3.0, 6.0), "flat": true,
					"velocity": Vector2(0.12, 0.3), "dir": Vector3(-1.0, 0.0, 0.4), "gravity": Vector3.ZERO,
					"damping": 0.0, "spin": 6.0},
				{"name": "Glimmers", "kind": ATLAS, "amount": 30, "life": 6.0, "y": 0.9, "half_y": 0.85,
					"color": Color(0.86, 1.0, 0.48), "alpha": 0.9, "scale": Vector2(0.1, 0.3), "additive": true,
					"velocity": Vector2(0.06, 0.25), "dir": Vector3.UP, "spread": 180.0,
					"gravity": Vector3(0.0, 0.1, 0.0), "damping": 0.8, "blink": true},
			]
		ArenaGround.VOLCANO:
			return [
				{"name": "Embers", "kind": SPECK, "amount": 46, "life": 3.2, "y": 0.4, "half_y": 0.4,
					"color": Color(1.0, 0.92, 0.55), "alpha": 1.0, "scale": Vector2(0.07, 0.15), "additive": true,
					"velocity": Vector2(1.2, 2.3), "dir": Vector3.UP, "spread": 28.0,
					"gravity": Vector3(0.7, 0.35, 0.15), "damping": 0.35, "heat": true},
				{"name": "Ash", "kind": SPECK, "amount": 40, "life": 9.0, "y": 5.4, "half_y": 1.6,
					"color": Color(0.58, 0.53, 0.5), "alpha": 0.55, "scale": Vector2(0.1, 0.2),
					"velocity": Vector2(0.1, 0.4), "dir": Vector3(1.0, -0.2, 0.2), "spread": 60.0,
					"gravity": Vector3(0.25, -0.34, 0.05), "damping": 0.7},
			]
		ArenaGround.ICE_CAVE:
			return [
				{"name": "Snow", "kind": SPECK, "amount": 60, "life": 9.0, "y": 5.5, "half_y": 2.0,
					"color": Color(0.96, 0.98, 1.0), "alpha": 0.85, "scale": Vector2(0.09, 0.17),
					"velocity": Vector2(0.05, 0.3), "dir": Vector3(0.4, -1.0, 0.1), "spread": 40.0,
					"gravity": Vector3(0.12, -0.36, 0.05), "damping": 0.5},
				{"name": "Glints", "kind": GLINT, "amount": 18, "life": 2.4, "y": 1.3, "half_y": 1.3,
					"color": Color(0.82, 0.96, 1.0), "alpha": 1.0, "scale": Vector2(0.3, 0.6), "additive": true,
					"velocity": Vector2(0.0, 0.08), "dir": Vector3.UP, "spread": 180.0,
					"gravity": Vector3.ZERO, "damping": 0.0, "pulse": true},
			]
		ArenaGround.CRYPT:
			return [
				{"name": "Dust", "kind": SPECK, "amount": 26, "life": 8.0, "y": 2.0, "half_y": 1.8,
					"color": Color(1.0, 0.76, 0.46), "alpha": 0.5, "scale": Vector2(0.05, 0.1), "additive": true,
					"velocity": Vector2(0.05, 0.2), "dir": Vector3.UP, "spread": 180.0,
					"gravity": Vector3(0.0, 0.03, 0.0), "damping": 0.6},
			]
	# The forest (and any look nobody dresses).
	return [
		{"name": "Leaves", "kind": LEAF, "amount": 44, "life": 9.0, "y": 6.2, "half_y": 1.4,
			"color": Color.WHITE, "alpha": 0.8, "scale": Vector2(0.26, 0.44),
			"velocity": Vector2(0.3, 0.9), "dir": Vector3(1.0, -0.3, 0.3), "spread": 50.0,
			"gravity": Vector3(0.14, -0.3, 0.05), "damping": 0.6, "spin": 180.0, "autumn": true},
		{"name": "Fireflies", "kind": SPECK, "amount": 16, "life": 6.0, "y": 1.2, "half_y": 0.9,
			"color": Color(0.9, 1.0, 0.5), "alpha": 0.95, "scale": Vector2(0.11, 0.2), "additive": true,
			"velocity": Vector2(0.08, 0.3), "dir": Vector3.UP, "spread": 180.0,
			"gravity": Vector3.ZERO, "damping": 0.9, "blink": true},
	]


## The total particle count of [param p_look].
static func particle_count(p_look: StringName) -> int:
	var n := 0
	for spec in specs_for(p_look):
		n += int(spec["amount"])
	return n


## Moves the systems over the ground a camera focused on [param focus] at [param distance] metres shows
## and sizes the emission boxes to it. A jump of the focus is a camera snap: the particles start over
## (prefilled) instead of drifting in from the old place.
func follow(focus: Vector3, distance: float) -> void:
	var aspect := 16.0 / 9.0
	if is_inside_tree():
		var vp := get_viewport()
		if vp != null and vp.get_visible_rect().size.y > 0.0:
			aspect = vp.get_visible_rect().size.x / vp.get_visible_rect().size.y
	var ext := CameraRig.ground_extents(distance, aspect)
	var half_x := CameraRig.half_width_at(distance, aspect, -ext.y) + BOX_MARGIN
	var half_z := (ext.y + ext.z) * 0.5 + BOX_MARGIN
	var jumped := _last_focus != Vector3.INF and Vector2(focus.x, focus.z).distance_to(Vector2(_last_focus.x, _last_focus.z)) > SNAP_DISTANCE
	position = Vector3(focus.x, 0.0, focus.z + (ext.z - ext.y) * 0.5)
	if absf(distance - _last_distance) > 0.4 or _last_distance < 0.0:
		_last_distance = distance
		for p in systems:
			var box := p.emission_box_extents
			p.emission_box_extents = Vector3(half_x, box.y, half_z)
	_last_focus = focus
	if jumped and is_inside_tree():
		for p in systems:
			p.restart()


func _process(delta: float) -> void:
	if _arena == null or not is_instance_valid(_arena):
		return
	if _arena.camera != null and is_instance_valid(_arena.camera):
		follow(_arena.camera.focus, _arena.camera.distance)
	if look == ArenaGround.VOLCANO:
		_time += delta
		flicker(_time)


## The volcano's light breathes with the lava: a few percent of the sun and a little less of the ambient
## light, three slow sines out of step (cheap, visual only; the data's values are the centre).
func flicker(t: float) -> void:
	if _arena.sun == null or _arena.world_environment == null or not is_instance_valid(_arena.sun):
		return
	var env := _arena.world_environment.environment
	if _flicker_base == Vector2.ZERO:
		_flicker_base = Vector2(_arena.sun.light_energy, env.ambient_light_energy)
	var f := 1.0 + 0.035 * sin(t * 2.3) + 0.025 * sin(t * 5.1 + 1.0) + 0.015 * sin(t * 11.3 + 2.0)
	_arena.sun.light_energy = _flicker_base.x * f
	env.ambient_light_energy = _flicker_base.y * (1.0 + (f - 1.0) * 0.6)


# =================================================================================================
# Building
# =================================================================================================

static func _build_system(spec: Dictionary, seed_value: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = String(spec["name"])
	var life: float = spec["life"]
	p.amount = int(spec["amount"])
	p.lifetime = life
	p.lifetime_randomness = 0.25
	p.preprocess = life
	p.local_coords = false
	p.use_fixed_seed = true
	p.seed = seed_value
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	# (The box is resized to the camera's view in follow(); the height band is the look's.)
	p.emission_box_extents = Vector3(18.0, float(spec["half_y"]), 12.0)
	p.position = Vector3(0.0, float(spec["y"]), 0.0)
	p.direction = spec["dir"]
	p.spread = float(spec.get("spread", 25.0))
	p.gravity = spec["gravity"]
	var v: Vector2 = spec["velocity"]
	p.initial_velocity_min = v.x
	p.initial_velocity_max = v.y
	p.damping_min = float(spec["damping"])
	p.damping_max = float(spec["damping"]) * 1.4
	var s: Vector2 = spec["scale"]
	p.scale_amount_min = s.x
	p.scale_amount_max = s.y
	var flat: bool = spec.get("flat", false)
	var kind: StringName = spec["kind"]
	p.mesh = _quad(flat)
	p.material_override = _material(kind, bool(spec.get("additive", false)), flat)
	if flat:
		p.particle_flag_rotate_y = true
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.angular_velocity_min = -float(spec.get("spin", 6.0))
		p.angular_velocity_max = float(spec.get("spin", 6.0))
	else:
		p.angle_min = 0.0
		p.angle_max = 360.0
		var spin: float = spec.get("spin", 0.0)
		p.angular_velocity_min = -spin
		p.angular_velocity_max = spin
	if kind == ATLAS:
		p.anim_offset_min = 0.0
		p.anim_offset_max = 1.0
		p.anim_speed_min = 0.0
		p.anim_speed_max = 0.0
	p.color = spec["color"]
	p.color_ramp = _alpha_ramp(float(spec["alpha"]), spec)
	if spec.get("autumn", false):
		p.color_initial_ramp = _autumn_ramp()
	if spec.get("pulse", false):
		var c := Curve.new()
		c.add_point(Vector2(0.0, 0.0))
		c.add_point(Vector2(0.45, 1.0), 0.0, 0.0)
		c.add_point(Vector2(1.0, 0.0))
		p.scale_amount_curve = c
	p.emitting = true
	return p


## The alpha over a particle's life: fades in and out; a "blink" look flickers in between (fireflies),
## a "heat" look cools from white-hot to dark red (embers).
static func _alpha_ramp(alpha: float, spec: Dictionary) -> Gradient:
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	if spec.get("blink", false):
		var stops: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.08, 1.0), Vector2(0.22, 0.12), Vector2(0.36, 0.9),
				Vector2(0.5, 0.1), Vector2(0.66, 0.85), Vector2(0.82, 0.2), Vector2(1.0, 0.0)]
		for st in stops:
			offsets.append(st.x)
			colors.append(Color(1.0, 1.0, 1.0, alpha * st.y))
	elif spec.get("heat", false):
		offsets = PackedFloat32Array([0.0, 0.1, 0.45, 0.8, 1.0])
		colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 1.0, 1.0, alpha), Color(1.0, 0.66, 0.3, alpha * 0.9),
				Color(0.9, 0.3, 0.15, alpha * 0.55), Color(0.5, 0.1, 0.08, 0.0)])
	else:
		offsets = PackedFloat32Array([0.0, 0.18, 0.78, 1.0])
		colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 1.0, 1.0, alpha), Color(1.0, 1.0, 1.0, alpha),
				Color(1.0, 1.0, 1.0, 0.0)])
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	return g


static func _autumn_ramp() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 0.75, 1.0])
	g.colors = PackedColorArray([Color(0.46, 0.76, 0.2), Color(0.76, 0.86, 0.26), Color(0.96, 0.74, 0.24), Color(0.86, 0.5, 0.18)])
	return g


static func _quad(flat: bool) -> Mesh:
	var key := "flat" if flat else "billboard"
	var mesh: Mesh = _meshes.get(key)
	if mesh == null:
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		if flat:
			q.orientation = PlaneMesh.FACE_Y
		mesh = q
		_meshes[key] = mesh
	return mesh


static func _material(kind: StringName, additive: bool, flat: bool) -> Material:
	var key := "%s:%s:%s" % [kind, additive, flat]
	var m: Material = _materials.get(key)
	if m != null:
		return m
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = _texture(kind)
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if not flat:
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		# (Without it the billboard drops the particle's scale: every quad would be a metre wide.)
		sm.billboard_keep_scale = true
	if kind == ATLAS:
		sm.particles_anim_h_frames = 2
		sm.particles_anim_v_frames = 1
		sm.particles_anim_loop = false
	# Under the ground rings and telegraphs (priority -1 and up): they are always on top of the mist.
	sm.render_priority = -3 if flat else -2
	_materials[key] = sm
	return sm


# --- Textures (procedural, 64 px, made once) ---------------------------------------------------------

static func _texture(kind: StringName) -> Texture2D:
	var t: Texture2D = _textures.get(kind)
	if t != null:
		return t
	var img: Image
	match kind:
		LEAF:
			img = _image(64, 64, _leaf_pixel)
		SPECK:
			img = _image(32, 32, _dot_pixel)
		GLINT:
			img = _image(64, 64, _glint_pixel)
		ATLAS:
			img = _image(128, 64, _atlas_pixel)
		_:
			img = _image(64, 64, _soft_pixel)
	img.generate_mipmaps()
	t = ImageTexture.create_from_image(img)
	_textures[kind] = t
	return t


static func _image(w: int, h: int, pixel: Callable) -> Image:
	var img := Image.create(w, h, true, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, pixel.call(float(x) + 0.5, float(y) + 0.5, float(w), float(h)))
	return img


## White, alpha falling off from the middle (mist, flakes, motes, embers, fireflies).
static func _soft_pixel(x: float, y: float, w: float, h: float) -> Color:
	var u := (x / w) * 2.0 - 1.0
	var v := (y / h) * 2.0 - 1.0
	var r := clampf(sqrt(u * u + v * v), 0.0, 1.0)
	var a := pow(1.0 - r, 1.6)
	return Color(1.0, 1.0, 1.0, a * a * (3.0 - 2.0 * a))


## White, a solid core with a soft rim (small flakes and glows that must still read at a few pixels).
static func _dot_pixel(x: float, y: float, w: float, h: float) -> Color:
	var u := (x / w) * 2.0 - 1.0
	var v := (y / h) * 2.0 - 1.0
	var r := sqrt(u * u + v * v)
	return Color(1.0, 1.0, 1.0, 1.0 - smoothstep(0.3, 1.0, r))


## A pointed leaf along the vertical axis with a lighter midrib.
static func _leaf_pixel(x: float, y: float, w: float, h: float) -> Color:
	var u := (x / w) * 2.0 - 1.0
	var v := (y / h) * 2.0 - 1.0
	var width := 0.5 * pow(maxf(1.0 - v * v, 0.0), 0.75)
	var edge := clampf((width - absf(u)) * 14.0, 0.0, 1.0)
	var vein := 1.0 - 0.28 * clampf(1.0 - absf(u) * 18.0, 0.0, 1.0)
	var shade := 0.82 + 0.18 * (1.0 - absf(u) / maxf(width, 0.01))
	return Color(vein * shade, vein * shade, vein * shade, edge)


## A four-pointed star (ice glints).
static func _glint_pixel(x: float, y: float, w: float, h: float) -> Color:
	var u := absf((x / w) * 2.0 - 1.0)
	var v := absf((y / h) * 2.0 - 1.0)
	var ray := maxf(exp(-u * 13.0 - v * 2.6), exp(-v * 13.0 - u * 2.6))
	var core := pow(clampf(1.0 - sqrt(u * u + v * v) * 2.2, 0.0, 1.0), 2.0)
	return Color(1.0, 1.0, 1.0, clampf(ray * 0.95 + core, 0.0, 1.0))


## Two frames side by side: a glowing dot (left) and a bubble ring with a highlight (right).
static func _atlas_pixel(x: float, y: float, w: float, h: float) -> Color:
	var half := w * 0.5
	if x < half:
		return _dot_pixel(x, y, half, h)
	var u := ((x - half) / half) * 2.0 - 1.0
	var v := (y / h) * 2.0 - 1.0
	var r := sqrt(u * u + v * v)
	var ring := clampf(1.0 - absf(r - 0.78) * 9.0, 0.0, 1.0)
	var fill := (1.0 - smoothstep(0.74, 0.84, r)) * 0.14
	var spot := clampf(1.0 - sqrt((u + 0.35) * (u + 0.35) + (v + 0.4) * (v + 0.4)) * 6.0, 0.0, 1.0)
	return Color(1.0, 1.0, 1.0, clampf(ring * 0.9 + fill + spot, 0.0, 1.0))
