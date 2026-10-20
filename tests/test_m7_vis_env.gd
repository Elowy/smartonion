extends TestCase
## M7b VIS-ENV: the final environment look – ambient particles (bounded, camera-following, never in the way),
## the ground shader of every look (compiles, no instance uniforms, shared and cached), the animated glow /
## water materials, the wall and backdrop rings, the lava / fireflies / sparkles, the dungeon's crypt, the
## light grades in the data, the decor budgets, and that none of it draws from the gameplay RNG.

const EnemiesFakes := preload("res://tests/enemies_fakes.gd")

var nodes: Array[Node] = []


func after_each() -> void:
	for n in nodes:
		if n != null and is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	nodes.clear()


func _arena(id: StringName) -> Arena:
	var arena := Arena.create(Db.get_environment(id))
	nodes.append(arena)
	return arena


func _all_ids() -> Array[StringName]:
	return Db.environment_ids


func _decor_draws(arena: Arena) -> int:
	var n := 0
	for c in arena.get_node("Decor").get_children():
		if c is GeometryInstance3D:
			n += 1
	return n


## The lights of [param arena] that are not the Spirit Healer's own (it carries one while a ghost waits).
func _lights(arena: Arena) -> Array[Node]:
	var out: Array[Node] = []
	for l in arena.find_children("*", "Light3D", true, false):
		var n: Node = l
		var healer := false
		while n != null and n != arena:
			if n is SpiritHealer:
				healer = true
			n = n.get_parent()
		if not healer:
			out.append(l)
	return out


func _mesh_of(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	return null


func _vertices(mesh: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in mesh.get_surface_count():
		out.append_array(mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	return out


# --- Ambient particles --------------------------------------------------------------------------------

func test_every_environment_builds_bounded_ambient_particles() -> void:
	var names := {}
	for id in _all_ids():
		var arena := _arena(id)
		var ambient := arena.ambient
		check(ambient != null and ambient.get_parent() == arena, "%s: an Ambient node under the arena" % id)
		check(arena.get_node("Decor").get_node_or_null("Ambient") == null, "%s: not part of the decor (its draw budget)" % id)
		check(ambient.systems.size() >= 1 and ambient.systems.size() <= ArenaAmbient.MAX_SYSTEMS, "%s: %d systems" % [id, ambient.systems.size()])
		var total := 0
		for p in ambient.systems:
			check(p is CPUParticles3D and p.emitting, "%s: %s is an emitting CPUParticles3D" % [id, p.name])
			check(not p.local_coords, "%s: %s lives in world space" % [id, p.name])
			check(p.use_fixed_seed, "%s: %s has its own fixed seed (no global random numbers)" % [id, p.name])
			check_eq(p.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: %s casts no shadow" % [id, p.name])
			check(p.amount > 0 and p.amount <= 60, "%s: %s has %d particles" % [id, p.name, p.amount])
			total += p.amount
			names[p.name] = true
		check(total <= ArenaAmbient.MAX_PARTICLES, "%s: %d particles in all" % [id, total])
		check_eq(total, ArenaAmbient.particle_count(ArenaGround.look_for(arena.environment, false)), "%s: the spec's count" % id)
	# Every environment has its own life (leaves, mist, glimmers, embers, snow ... all different names).
	check(names.size() >= 9, "each environment has its own particles (%d distinct systems)" % names.size())
	for expected in ["Leaves", "Fireflies", "Mist", "Motes", "Glimmers", "Embers", "Ash", "Snow", "Glints"]:
		check(names.has(expected), "the %s system exists" % expected)


func test_the_particles_never_hide_a_telegraph_or_a_hero() -> void:
	var ring_priority := (Mats.ring() as ShaderMaterial).render_priority
	for look in [ArenaGround.FOREST, ArenaGround.CEMETERY, ArenaGround.SWAMP, ArenaGround.VOLCANO, ArenaGround.ICE_CAVE, ArenaGround.CRYPT]:
		for spec in ArenaAmbient.specs_for(look):
			var label := "%s / %s" % [look, spec["name"]]
			var sc: Vector2 = spec["scale"]
			var flat: bool = spec.get("flat", false)
			var additive: bool = spec.get("additive", false)
			var alpha: float = spec["alpha"]
			if flat:
				# Ground mist: very faint and under the rings.
				check(alpha <= 0.25, "%s: mist alpha %.2f" % [label, alpha])
				check(float(spec["y"]) + float(spec["half_y"]) <= 0.6, "%s: mist hugs the ground" % label)
			elif not additive:
				# Leaves, ash, snow: high above the heroes, small.
				check(float(spec["y"]) - float(spec["half_y"]) >= 3.0, "%s: starts high above the heroes" % label)
				check(sc.y <= 0.5, "%s: small (%.2f m)" % [label, sc.y])
				check(alpha <= 0.9, "%s: never opaque" % label)
			else:
				check(sc.y <= 0.7, "%s: glows are small (%.2f m)" % [label, sc.y])
			var material := ArenaAmbient._material(spec["kind"], additive, flat) as StandardMaterial3D
			check(material != null and material.render_priority < ring_priority, "%s: drawn under the ground rings (priority %d vs %d)" % [
					label, material.render_priority if material != null else 0, ring_priority])
			check(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "%s: unshaded" % label)


func test_the_ambient_follows_the_camera_and_sizes_its_box_to_the_view() -> void:
	var arena := _arena(&"swamp")
	var ambient := arena.ambient
	ambient.follow(Vector3(6.0, 0.0, -4.0), 24.0)
	var ext := CameraRig.ground_extents(24.0, 16.0 / 9.0)
	check_near(ambient.position.x, 6.0, 0.001, "centred on the focus x")
	check_near(ambient.position.z, -4.0 + (ext.z - ext.y) * 0.5, 0.001, "and on the middle of the visible ground in z")
	var box_near: Vector3 = ambient.systems[0].emission_box_extents
	check(box_near.x > ext.x and box_near.z > (ext.y + ext.z) * 0.5, "the box is a little bigger than the view")
	ambient.follow(Vector3(6.0, 0.0, -4.0), 36.0)
	var box_far: Vector3 = ambient.systems[0].emission_box_extents
	check(box_far.x > box_near.x * 1.3 and box_far.z > box_near.z * 1.3, "the box grows with the zoom-out (%.1f -> %.1f)" % [box_near.x, box_far.x])
	check_eq(ambient.systems[0].emission_box_extents.y, float(ArenaAmbient.specs_for(ArenaGround.SWAMP)[0]["half_y"]), "the height band is the look's")
	# A jump of the focus restarts the particles (a camera snap).
	ambient.follow(Vector3(-20.0, 0.0, 10.0), 36.0)
	check(ambient.systems[0].emitting, "still emitting after the snap")


# --- Ground shaders ------------------------------------------------------------------------------------

func test_every_ground_look_compiles_and_has_no_instance_uniforms() -> void:
	var codes := {}
	for look in ArenaGround.LOOKS:
		var code := ArenaGround.code_for(look)
		check(code.contains("shader_type spatial;"), "%s: a spatial shader" % look)
		check(not code.contains("instance uniform"), "%s: free of instance uniforms" % look)
		check(code.contains("TIME") or look == ArenaGround.CEMETERY, "%s: animated on TIME (the cemetery's soil is still)" % look)
		var m := ArenaGround.make_material(look)
		check(m.shader != null and m.shader.code == code, "%s: the material has the look's shader" % look)
		# (Headless the shader language still parses the code: a broken shader lists no uniforms.)
		var names: Array[String] = []
		for u in m.shader.get_shader_uniform_list():
			names.append(String(u["name"]))
		check(names.size() >= 11, "%s: compiles, %d uniforms" % [look, names.size()])
		for expected in ["grass_dark", "grass_mid", "grass_light", "grass_warm", "dirt_light", "dirt_dark", "patches", "patch_count", "arena_half", "road"]:
			check(names.has(expected), "%s: declares %s" % [look, expected])
		codes[code] = true
	check_eq(codes.size(), ArenaGround.LOOKS.size(), "every look is its own shader")
	check(ArenaGround.make_material(ArenaGround.VOLCANO).shader == ArenaGround.make_material(ArenaGround.VOLCANO).shader, "one compiled shader per look")
	check(ArenaGround.make_material(&"nonsense").shader == ArenaGround.make_material(ArenaGround.FOREST).shader, "an unknown look is the forest's")


func test_each_arena_wears_the_ground_look_of_its_decor_set() -> void:
	var expected := {&"forest_ruin": ArenaGround.FOREST, &"cemetery": ArenaGround.CEMETERY, &"swamp": ArenaGround.SWAMP,
			&"volcano": ArenaGround.VOLCANO, &"ice_cave": ArenaGround.ICE_CAVE}
	for id in expected:
		var arena := _arena(id)
		var mat := arena.ground.material_override as ShaderMaterial
		check_eq(mat.shader.code, ArenaGround.code_for(expected[id]), "%s: the %s ground" % [id, expected[id]])
		check_eq(ArenaGround.look_for(arena.environment, false), expected[id], "%s: look_for" % id)
		check_eq(ArenaGround.look_for(arena.environment, true), ArenaGround.CRYPT, "%s: the dungeon room is always the crypt" % id)
		check(not mat.shader.code.contains("instance uniform"), "%s: no instance uniforms" % id)
		var sun: Vector3 = mat.get_shader_parameter("sun_dir")
		check(absf(sun.length() - 1.0) < 0.001 and sun.y > 0.3, "%s: the sun direction points up at the sun" % id)
	var volcano := _arena(&"volcano")
	var vents: PackedVector2Array = (volcano.ground.material_override as ShaderMaterial).get_shader_parameter("vents")
	check_eq(vents.size(), ArenaGround.MAX_VENTS, "the volcano's ground knows its six vents")
	check_eq((volcano.ground.material_override as ShaderMaterial).get_shader_parameter("vent_count"), EnvironmentHazards.LAVA_VENT_POINTS.size(), "vent count")
	for i in EnvironmentHazards.LAVA_VENT_POINTS.size():
		var v := EnvironmentHazards.LAVA_VENT_POINTS[i]
		check(vents.has(Vector2(v.x, v.z)), "the vent at %s glows in the ground too" % v)


func test_the_glow_materials_animate_on_time_and_are_cached() -> void:
	var twinkle := ArenaFx.twinkle(Color(0.5, 1.0, 0.5), 1.5, 0.9, 0.7) as ShaderMaterial
	check(twinkle == ArenaFx.twinkle(Color(0.5, 1.0, 0.5), 1.5, 0.9, 0.7), "cached per parameter set")
	check(twinkle != ArenaFx.twinkle(Color(1.0, 0.5, 0.5), 1.5, 0.9, 0.7), "per colour")
	var lava := ArenaFx.lava() as ShaderMaterial
	check(lava == ArenaFx.lava(), "the lava material is cached")
	for m: ShaderMaterial in [twinkle, lava]:
		check(m.shader.code.contains("TIME"), "animated on TIME")
		check(not m.shader.code.contains("instance uniform"), "no instance uniforms")
		check(m.shader.get_shader_uniform_list().size() > 0 or m == lava, "compiles")
		check(m.shader.code.contains("unshaded"), "unshaded (the Compatibility renderer shows only the albedo of those)")
	check(ArenaFx.phase(Vector3(1, 2, 3)) == ArenaFx.phase(Vector3(1, 2, 3)), "the phase is a function of the place")
	check(ArenaFx.phase(Vector3(1, 2, 3)) != ArenaFx.phase(Vector3(4, 2, 3)), "different lights, different phases")
	for i in 50:
		var ph := ArenaFx.phase(Vector3(float(i) * 1.7, 1.0, float(i) * -0.9))
		check(ph >= 0.0 and ph < 1.0, "phase %.3f in range" % ph)
	check_near(ArenaFx.lit(Vector3(3, 1, 2), Color(0.2, 0.4, 0.6)).a, ArenaFx.phase(Vector3(3, 1, 2)), 0.0001, "lit() puts the phase in alpha")
	# The decor's glow meshes use them.
	var volcano := _arena(&"volcano")
	check((volcano.get_node("Decor/Lava") as MeshInstance3D).material_override == ArenaFx.lava(), "the volcano's lava churns")
	check((volcano.get_node("Decor/FloatingEmbers") as MeshInstance3D).material_override is ShaderMaterial, "floating embers twinkle")
	check((_arena(&"swamp").get_node("Decor/Fireflies") as MeshInstance3D).material_override is ShaderMaterial, "fireflies blink")
	check((_arena(&"cemetery").get_node("Decor/Wisps") as MeshInstance3D).material_override is ShaderMaterial, "wisps pulse")
	check((_arena(&"ice_cave").get_node("Decor/Sparkles") as MeshInstance3D).material_override is ShaderMaterial, "sparkles twinkle")
	# Their parts carry a phase in the vertex alpha: not all the same.
	var alphas := {}
	for c: Color in (volcano.get_node("Decor/FloatingEmbers") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
		alphas[snappedf(c.a, 0.01)] = true
	check(alphas.size() > 20, "the embers have many different phases (%d)" % alphas.size())


func test_the_bog_water_is_a_ring_compatible_animated_shader() -> void:
	var a := BogPool.water_material()
	var b := BogPool.water_material()
	check(a != b, "one material per pool (the fade writes its uniforms)")
	check(a.shader == b.shader, "one shared shader")
	check(a.shader.code.contains("TIME") and not a.shader.code.contains("instance uniform"), "animated, no instance uniforms")
	var names: Array[String] = []
	for u in a.shader.get_shader_uniform_list():
		names.append(String(u["name"]))
	for expected in ["ring_color", "ring_shape", "ring_stroke"]:
		check(names.has(expected), "%s: the ring shader's uniform, so the pool's fade-in writes it" % expected)
	var world := EnemiesFakes.make_world(tree)
	var pool := BogPool.spawn(EnemiesFakes.arena_of(world).entities, Vector3(4, 0, 4), 2.3, 30.0, 15.0)
	check((pool._mud.material_override as ShaderMaterial).shader == a.shader, "the pool's water is the water shader")
	check((pool._rim.material_override as ShaderMaterial).shader != a.shader, "its rim stays a ring")
	check_eq(pool.marker_color(), BogPool.MUD_RIM, "and the lime rim is still the marker")
	EnemiesFakes.free_world(tree, world)


# --- Backdrops, decor budgets -------------------------------------------------------------------------

func test_the_four_sets_have_a_backdrop_ring_outside_the_playfield() -> void:
	var forest := _arena(&"forest_ruin")
	check(forest.get_node("Decor").get_node_or_null("Backdrop") == null, "the forest keeps today's decor")
	var forest_draws := _decor_draws(forest)
	for id in [&"cemetery", &"swamp", &"volcano", &"ice_cave"]:
		var arena := _arena(id)
		var back := arena.get_node("Decor").get_node_or_null("Backdrop") as MeshInstance3D
		check(back != null, "%s: a Backdrop mesh" % id)
		if back == null:
			continue
		check_eq(back.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: no shadows from the backdrop" % id)
		var verts := _vertices(back.mesh)
		check(verts.size() > 1500 and verts.size() < 40000, "%s: %d vertices" % [id, verts.size()])
		var bounds := arena.get_bounds()
		var tallest := 0.0
		var tallest_south := 0.0
		for v in verts:
			check(not bounds.has_point(Vector2(v.x, v.z)), "%s: stands outside the playable rectangle" % id)
			if not bounds.has_point(Vector2(v.x, v.z)):
				tallest = maxf(tallest, v.y)
				if v.z > bounds.end.y - 0.5 and absf(v.x) < bounds.end.x * 0.6:
					tallest_south = maxf(tallest_south, v.y)
		check(tallest > 3.0, "%s: taller than 3 m somewhere (%.1f)" % [id, tallest])
		check(tallest_south < 2.2, "%s: low towards the camera at the south (%.1f m)" % [id, tallest_south])
		check(_decor_draws(arena) <= forest_draws and _decor_draws(arena) <= ArenaThemes.MAX_DRAW_CALLS, "%s: %d decor draws" % [id, _decor_draws(arena)])
	# Deterministic: the same arena twice builds the same backdrop.
	var a := ArenaBackdrop.build(_arena(&"ice_cave"))
	var b := ArenaBackdrop.build(_arena(&"ice_cave"))
	nodes.append(a)
	nodes.append(b)
	check_eq(_vertices(a.mesh).size(), _vertices(b.mesh).size(), "the same backdrop twice")


func test_the_backdrop_ring_gets_lower_towards_the_south_and_leaves_the_gate_free() -> void:
	var bounds := Rect2(-Arena.SIZE / 2.0, Arena.SIZE)
	check_eq(ArenaBackdrop.height_factor(bounds, bounds.position.y), 1.0, "full height in the north")
	check_near(ArenaBackdrop.height_factor(bounds, bounds.end.y), ArenaBackdrop.SOUTH_HEIGHT, 0.0001, "low at the south wall")
	check(ArenaBackdrop.height_factor(bounds, 0.0) > ArenaBackdrop.height_factor(bounds, 9.0), "a ramp between")
	var at_gate := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	ArenaBackdrop.walk_ring(bounds, 1.5, 0.9, 1.1, rng, func(base: Vector3, _t: Vector3, _o: Vector3, _h: float) -> void:
		if base.z < bounds.position.y and absf(base.x) < ArenaDecor.GATE_HALF_WIDTH + 2.4:
			at_gate += 1)
	check_eq(at_gate, 0, "nothing stands in front of the north gate")
	var seams := ArenaBackdrop.magma_seams(bounds)
	check(seams.size() > 10, "the volcano has magma seams along its wall (%d)" % seams.size())
	for s in seams:
		check(not bounds.has_point(Vector2(s[0].x, s[0].z)) and not bounds.has_point(Vector2(s[1].x, s[1].z)), "a seam lies outside the wall")


func test_the_decor_budgets_hold_with_the_new_dressing() -> void:
	var forest := _arena(&"forest_ruin")
	var forest_draws := _decor_draws(forest)
	var forest_verts := 0
	for c in forest.get_node("Decor").get_children():
		var mesh: Mesh = (c as MeshInstance3D).mesh if c is MeshInstance3D else (c as MultiMeshInstance3D).multimesh.mesh
		forest_verts += _vertices(mesh).size()
	for id in ArenaThemes.set_ids():
		var arena := _arena(id)
		var verts := 0
		for c in arena.get_node("Decor").get_children():
			var mesh: Mesh = (c as MeshInstance3D).mesh if c is MeshInstance3D else (c as MultiMeshInstance3D).multimesh.mesh
			verts += _vertices(mesh).size()
		check(_decor_draws(arena) <= forest_draws, "%s: %d decor draws vs the forest's %d" % [id, _decor_draws(arena), forest_draws])
		check(verts <= forest_verts * 3 / 2, "%s: %d vertices (the forest has %d)" % [id, verts, forest_verts])
		# The ambient particles are at most two more draws.
		check(arena.ambient.systems.size() <= 2, "%s: at most two particle draws" % id)


# --- Dungeon ------------------------------------------------------------------------------------------

func test_the_dungeon_room_is_a_crypt() -> void:
	var arena := _arena(&"forest_ruin")
	var clearing_ambient := arena.ambient
	var clearing_decor := arena.decor
	var clearing_energy := arena.world_environment.environment.ambient_light_energy
	arena.enter_dungeon_layout()
	var bounds := arena.get_bounds()
	check_eq(bounds.size, Arena.DUNGEON_SIZE, "the small room")
	# Floor: the crypt's tiles, wearing the run's palette.
	var mat := arena.ground.material_override as ShaderMaterial
	check_eq(mat.shader.code, ArenaGround.code_for(ArenaGround.CRYPT), "the crypt floor")
	check_eq(mat.get_shader_parameter("grass_mid"), arena.environment.grass_mid, "in the run's palette")
	check_eq(mat.get_shader_parameter("torch_count"), ArenaCrypt.torch_points(bounds).size(), "the floor lights the torches")
	check(ArenaCrypt.torch_points(bounds).size() >= 6 and ArenaCrypt.torch_points(bounds).size() <= ArenaGround.MAX_TORCHES, "six to eight torches")
	# Dressing: stone and flames, two meshes, all of it outside the playable rectangle.
	var names: Array[String] = []
	for c in arena.decor.get_children():
		names.append(String(c.name))
	check_eq(names, ["Crypt", "Torches"] as Array[String], "the crypt's two meshes")
	check(_decor_draws(arena) <= 4, "a few draws")
	var crypt := arena.decor.get_node("Crypt") as MeshInstance3D
	var verts := _vertices(crypt.mesh)
	check(verts.size() > 3000, "the crypt really builds something (%d vertices)" % verts.size())
	var tallest := 0.0
	for v in verts:
		tallest = maxf(tallest, v.y)
		if bounds.has_point(Vector2(v.x, v.z)) and v.y > 0.55:
			failures.append("the crypt has a vertex %.2f m high inside the room at (%.1f, %.1f)" % [v.y, v.x, v.z])
			break
	check(tallest >= 6.0, "pillars and a tall back wall (%.1f m)" % tallest)
	for p in ArenaCrypt.torch_points(bounds):
		check(not bounds.has_point(Vector2(p.x, p.z)), "a torch stands outside the room")
	var torches := arena.decor.get_node("Torches") as MeshInstance3D
	check(torches.material_override is ShaderMaterial and (torches.material_override as ShaderMaterial).shader.code.contains("TIME"), "the flames flicker")
	check_eq(torches.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no flame shadows")
	# Ambient dust instead of the clearing's leaves; the grade is dimmer than the clearing's.
	check(arena.ambient != clearing_ambient and arena.ambient.look == ArenaGround.CRYPT, "dust motes in the crypt")
	check(clearing_ambient.get_parent() == null, "the clearing's ambient is parked")
	check(arena.world_environment.environment.ambient_light_energy < clearing_energy, "dimmer than the clearing")
	check_eq(arena.world_environment.environment.background_color, arena.environment.sky_color, "the sky stays the environment's")
	# No light but the sun (the brazier's own is the only one a room adds), one WorldEnvironment.
	check_eq(_lights(arena).size(), 1, "just the sun (the Spirit Healer's light sleeps with it)")
	var envs := 0
	for c in arena.get_children():
		if c is WorldEnvironment:
			envs += 1
	check_eq(envs, 1, "one WorldEnvironment")
	# Leaving puts everything back, ambient included.
	arena.leave_dungeon_layout()
	check(arena.ambient == clearing_ambient and clearing_ambient.get_parent() == arena, "the clearing's ambient is back")
	check(arena.decor == clearing_decor and arena.decor.get_parent() == arena, "and its decor")
	check_near(arena.world_environment.environment.ambient_light_energy, clearing_energy, 0.0001, "and its light")
	check_eq((arena.ground.material_override as ShaderMaterial).shader.code, ArenaGround.code_for(ArenaGround.FOREST), "and its ground")


func test_the_dungeon_wears_every_environments_palette_and_each_room_builds() -> void:
	for id in _all_ids():
		var arena := _arena(id)
		arena.enter_dungeon_layout(Db.get_environment(id))
		check_eq((arena.ground.material_override as ShaderMaterial).get_shader_parameter("grass_mid"), Db.get_environment(id).grass_mid, "%s: palette" % id)
		check_eq(arena.decor.get_child_count(), 2, "%s: the crypt dressing" % id)
		check_eq(arena.ambient.look, ArenaGround.CRYPT, "%s: dust" % id)
		check(arena.get_node_or_null("Ambient") == arena.ambient, "%s: one Ambient in the tree" % id)
		arena.leave_dungeon_layout()
		check_eq(arena.ambient.look, ArenaGround.look_for(Db.get_environment(id), false), "%s: its own life is back" % id)


func test_the_brazier_throws_a_warm_flickering_light() -> void:
	var b := DungeonBrazier.create(100.0)
	nodes.append(b)
	var light := b.get_node("Glow") as OmniLight3D
	check(light.light_color.r > light.light_color.g and light.light_color.g > light.light_color.b, "warm: red > green > blue")
	check(light.light_color.b < 0.3, "orange, not yellow-white")
	check(light.omni_range >= 9.0, "reaches across the crypt")
	check(not light.shadow_enabled, "no shadows")
	var seen := {}
	for i in 30:
		b._process(0.07)
		seen[snappedf(light.light_energy, 0.001)] = true
	check(seen.size() > 10, "it flickers (%d distinct energies)" % seen.size())


# --- Light, grade, data -------------------------------------------------------------------------------

func test_the_environment_data_stays_in_a_sane_range() -> void:
	for id in _all_ids():
		var e := Db.get_environment(id)
		check(e.fog_density >= 0.002 and e.fog_density <= 0.02, "%s: fog density %.4f" % [id, e.fog_density])
		check(e.ambient_energy >= 0.3 and e.ambient_energy <= 1.0, "%s: ambient energy %.2f" % [id, e.ambient_energy])
		check(e.sun_energy >= 0.5 and e.sun_energy <= 1.3, "%s: sun energy %.2f" % [id, e.sun_energy])
		check(e.glow_intensity >= 0.3 and e.glow_intensity <= 1.0, "%s: glow %.2f" % [id, e.glow_intensity])
		check(e.saturation >= 0.8 and e.saturation <= 1.2, "%s: saturation %.2f" % [id, e.saturation])
		check(e.contrast >= 1.0 and e.contrast <= 1.2, "%s: contrast %.2f" % [id, e.contrast])
		check(e.sun_rotation.x <= -35.0 and e.sun_rotation.x >= -70.0, "%s: sun pitch %.0f" % [id, e.sun_rotation.x])
		for c in [e.sky_color, e.ambient_color, e.fog_color, e.sun_color] + e.floor_colors():
			check(c.r >= 0.0 and c.r <= 1.0 and c.g >= 0.0 and c.g <= 1.0 and c.b >= 0.0 and c.b <= 1.0, "%s: a colour in range" % id)
		# The ground has to stay a floor: no tone brighter than a pale snow or darker than black basalt.
		for c in e.floor_colors():
			check(c.get_luminance() > 0.07 and c.get_luminance() < 0.85, "%s: floor luminance %.2f" % [id, c.get_luminance()])
	# Every environment looks different: no two share a fog colour or a sun colour.
	var fogs := {}
	var suns := {}
	for id in _all_ids():
		fogs[Db.get_environment(id).fog_color] = true
		suns[Db.get_environment(id).sun_color] = true
	check_eq(fogs.size(), 5, "five different fogs")
	check_eq(suns.size(), 5, "five different suns")


func test_the_grades_reach_the_world_environment_and_the_sun() -> void:
	for id in _all_ids():
		var arena := _arena(id)
		var e := Db.get_environment(id)
		var env := arena.world_environment.environment
		check_eq(env.fog_density, e.fog_density, "%s: fog" % id)
		check_eq(env.ambient_light_energy, e.ambient_energy, "%s: ambient" % id)
		check_eq(arena.sun.light_energy, e.sun_energy, "%s: sun" % id)
		check_eq(env.adjustment_contrast, e.contrast, "%s: contrast" % id)
		check_eq(_lights(arena).size(), 1, "%s: the sun is the only light" % id)
		check(arena.sun.shadow_enabled, "%s: sun shadows (the one shadow caster)" % id)


func test_the_volcano_light_breathes_a_few_percent_around_the_data() -> void:
	var arena := _arena(&"volcano")
	var e := Db.get_environment(&"volcano")
	var lo := INF
	var hi := -INF
	for i in 200:
		arena.ambient.flicker(float(i) * 0.1)
		lo = minf(lo, arena.sun.light_energy)
		hi = maxf(hi, arena.sun.light_energy)
	check(hi > lo, "it flickers")
	check(lo > e.sun_energy * 0.92 and hi < e.sun_energy * 1.08, "within +-8%% of the data (%.3f .. %.3f of %.2f)" % [lo, hi, e.sun_energy])
	check_near(arena.world_environment.environment.ambient_light_energy, e.ambient_energy, e.ambient_energy * 0.06, "the ambient light barely moves")
	var forest := _arena(&"forest_ruin")
	forest.ambient._process(0.5)
	check_eq(forest.sun.light_energy, Db.get_environment(&"forest_ruin").sun_energy, "the forest's sun is steady")


# --- Determinism --------------------------------------------------------------------------------------

func test_none_of_it_draws_from_the_gameplay_rng() -> void:
	RunState.start_run(4, 4242, RunState.MODE_NORMAL, false, &"forest_ruin")
	var before := RunState.rng.state
	for id in _all_ids():
		var arena := _arena(id)
		arena.ambient.follow(Vector3(3.0, 0.0, 1.0), 28.0)
		arena.ambient.flicker(1.0)
		arena.enter_dungeon_layout()
		arena.leave_dungeon_layout()
	check_eq(RunState.rng.state, before, "RunState.rng untouched by building / following / dressing")
	RunState.start_run(1, 1)
