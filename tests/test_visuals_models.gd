extends TestCase
## OnionModel, EnemyModel, WeaponModel, Mats and MeshKit.

var _nodes: Array[Node] = []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


func _keep(n: Node) -> Node:
	_nodes.append(n)
	return n


func _onion(class_id: StringName) -> OnionModel:
	var cd := Db.get_class_data(class_id)
	var m := _keep(OnionModel.new()) as OnionModel
	m.setup(cd, Color(0.2, 0.5, 1.0))
	m.set_weapons(cd.main_hand, cd.off_hand)
	return m


func _overlay(gi: GeometryInstance3D) -> float:
	return Mats.overlay_amount(gi)


func _param(gi: GeometryInstance3D, name: StringName) -> Variant:
	var m := gi.material_override as ShaderMaterial
	return m.get_shader_parameter(name) if m != null else null


# --- Mats ---------------------------------------------------------------------

func test_mats_are_cached_and_outlined() -> void:
	var a := Mats.toon(Color(0.5, 0.2, 0.1))
	check(a == Mats.toon(Color(0.5, 0.2, 0.1)), "toon cached per colour")
	check(a != Mats.toon(Color(0.1, 0.2, 0.5)), "different colour -> different material")
	check(a is ShaderMaterial and (a as ShaderMaterial).next_pass != null, "toon has an outline pass")
	check(Mats.toon_plain(Color.RED).next_pass == null, "plain toon has no outline")
	check(Mats.toon_vc() == Mats.toon_vc(), "vertex colour toon cached")
	var u := Mats.unshaded(Color(1, 1, 1, 0.5)) as StandardMaterial3D
	check(u.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, "alpha unshaded is transparent")
	check(Mats.glow(Color.GREEN) == Mats.glow(Color.GREEN), "glow cached")


func test_no_instance_uniforms() -> void:
	# The Compatibility renderer fits instance uniforms for only ~256 instances (16 vec4
	# slots each in a 64 KB buffer) – far fewer than 150 enemies + props need.
	var materials: Array[Material] = [Mats.toon(Color.RED), Mats.toon_vc(), Mats.onion_skin(Color.RED, 0.5),
		Mats.toon_cloth_vc(), Mats.ghost(Color.WHITE), Mats.ring(), Mats.cast_bar(), Mats.outline()]
	for m in materials:
		var sm := m as ShaderMaterial
		check(sm != null and not sm.shader.code.contains("instance uniform"), "%s free of instance uniforms" % m)
	var arena := _keep(Arena.create()) as Arena
	tree.root.add_child(arena)
	Vfx.slash_arc(Vector3.ZERO, Vector3.FORWARD, 2.0, 90.0, Color.WHITE)
	Vfx.explosion(Vector3.ZERO, 1.0, Color.RED)
	Vfx.spawn_telegraph(Vector3.ZERO, 1.0, 1.0)
	Vfx.level_up_burst(Vector3.ZERO)
	Vfx.resurrect_column(Vector3.ZERO)
	var checked := 0
	for gi in arena.find_children("*", "GeometryInstance3D", true, false):
		var sm := (gi as GeometryInstance3D).material_override as ShaderMaterial
		if sm != null and sm.shader != null:
			checked += 1
			check(not sm.shader.code.contains("instance uniform"), "%s free of instance uniforms" % gi.name)
	check(checked > 10, "arena and vfx materials inspected (%d)" % checked)


func test_overlay_variants_are_cached_and_reversible() -> void:
	var base := Mats.toon_vc()
	var a := _keep(MeshInstance3D.new()) as MeshInstance3D
	var b := _keep(MeshInstance3D.new()) as MeshInstance3D
	a.material_override = base
	b.material_override = base
	Mats.set_overlay(a, Color.WHITE, 0.8)
	Mats.set_overlay(b, Color.WHITE, 0.82)
	check(a.material_override != base, "tinted variant")
	check(a.material_override == b.material_override, "variant shared (quantised)")
	check((a.material_override as ShaderMaterial).next_pass == base.next_pass, "outline kept")
	check_near(Mats.overlay_amount(a), 0.8, 0.001, "amount")
	Mats.set_overlay(a, Color.RED, 0.5, 30.0)
	check(Mats.base_material(a) == base, "base remembered")
	Mats.set_overlay(a, Color.WHITE, 0.0)
	check(a.material_override == base, "zero amount restores the base")
	var ghost := Mats.ghost(Color.WHITE)
	a.material_override = ghost
	check(Mats.base_material(a) == ghost, "follows an external material change")


# --- MeshKit ------------------------------------------------------------------

func _check_winding(mesh: ArrayMesh, label: String) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bad := 0
	for i in range(0, idx.size(), 3):
		var c := (v[idx[i + 1]] - v[idx[i]]).cross(v[idx[i + 2]] - v[idx[i]])
		if c.length() < 1e-7:
			continue
		if c.dot(n[idx[i]] + n[idx[i + 1]] + n[idx[i + 2]]) > 0.0:
			bad += 1
	check_eq(bad, 0, "%s: front faces wound like Godot primitives" % label)


func test_mesh_kit_merges_and_winds_correctly() -> void:
	var k := MeshKit.new()
	k.add_box(Vector3.ONE, Transform3D(), Color.RED)
	check_eq(k.vertex_count(), 24, "box vertices")
	k.add_sphere(0.5, MeshKit.xf(Vector3(2, 0, 0)), Color.BLUE, 8, 4)
	var mesh := k.build()
	check_eq(mesh.get_surface_count(), 1, "one merged surface")
	_check_winding(mesh, "primitives")
	var lathe := MeshKit.new()
	lathe.add_lathe(OnionModel.bulb_profile(), Transform3D(), Color.WHITE, 12)
	_check_winding(lathe.build(), "lathe")
	var ext := MeshKit.new()
	ext.add_extrusion(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1)]), 0.1, Transform3D(), Color.WHITE)
	_check_winding(ext.build(), "extrusion")
	var arc := MeshKit.new()
	arc.add_arc(0.5, 1.0, 90.0, Transform3D(), Color.WHITE)
	_check_winding(arc.build(), "arc")
	var mirrored := MeshKit.new()
	mirrored.add_box(Vector3.ONE, Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO), Color.RED)
	_check_winding(mirrored.build(), "mirrored box")


func test_mesh_kit_cache() -> void:
	var calls := [0]
	var builder := func() -> Mesh:
		calls[0] += 1
		return ArrayMesh.new()
	var a := MeshKit.cached("test:cache_probe", builder)
	var b := MeshKit.cached("test:cache_probe", builder)
	check(a == b, "same mesh instance")
	check_eq(calls[0], 1, "built once")


# --- WeaponModel --------------------------------------------------------------

func test_every_weapon_builds_a_shared_mesh() -> void:
	check(Db.weapons.size() > 0, "weapons loaded")
	for id in Db.weapons:
		var w := Db.get_weapon(id)
		check(w.weapon_type in WeaponModel.TYPES, "%s has a known weapon_type" % id)
		var a := _keep(WeaponModel.build(w)) as Node3D
		var b := _keep(WeaponModel.build(w)) as Node3D
		var ma := a.get_node_or_null("Mesh") as MeshInstance3D
		var mb := b.get_node_or_null("Mesh") as MeshInstance3D
		check(ma != null and ma.mesh != null and ma.mesh.get_surface_count() == 1, "%s mesh" % id)
		check(ma != null and mb != null and ma.mesh == mb.mesh, "%s mesh shared" % id)
		var aabb := ma.mesh.get_aabb()
		check(aabb.end.y > 0.1, "%s extends along +Y" % id)
	check(_keep(WeaponModel.build(null)).get_child_count() == 0, "null weapon -> empty node")


func test_epic_weapons_glow() -> void:
	var w := Db.get_weapon(&"sword").duplicate() as WeaponData
	w.rarity = 3
	var node := _keep(WeaponModel.build(w)) as Node3D
	var mat := (node.get_node("Mesh") as MeshInstance3D).material_override as ShaderMaterial
	check(mat != Mats.toon_vc(), "epic uses the glowing material")
	check((mat.get_shader_parameter("emission_energy") as float) > 0.0, "emissive")


# --- OnionModel ---------------------------------------------------------------

func test_bulb_profile() -> void:
	check_eq(OnionModel.bulb_radius(0.0), 0.0, "below the bulb")
	check_eq(OnionModel.bulb_radius(1.2), 0.0, "above the bulb")
	var widest := 0.0
	var widest_y := 0.0
	for i in 100:
		var y := i / 100.0
		var r := OnionModel.bulb_radius(y)
		if r > widest:
			widest = r
			widest_y = y
	check_near(widest, 0.405, 0.01, "max radius")
	check(widest_y > 0.3 and widest_y < 0.55, "widest in the lower half (onion shape)")
	var p := OnionModel.bulb_point(0.5, 90.0)
	check(p.x > 0.35 and absf(p.z) < 0.001, "90 degrees is +X")
	check(OnionModel.bulb_point(0.5, 0.0).z < -0.35, "0 degrees is the front (-Z)")


func test_onion_builds_every_class() -> void:
	for id in Db.class_ids:
		var m := _onion(id)
		check(m.get_node_or_null("Yaw/Body/Bulb") != null, "%s bulb" % id)
		check(m.get_node_or_null("Ring") != null, "%s player ring" % id)
		check(m.get_node_or_null("Yaw/Body/HandMain/Grip") != null, "%s main hand grip" % id)
		var cd := Db.get_class_data(id)
		var grip := m.get_node("Yaw/Body/HandMain/Grip")
		check_eq(grip.get_child_count(), 1, "%s holds its main hand weapon" % id)
		if cd.off_hand != null:
			check_eq(m.get_node("Yaw/Body/HandOff/Grip").get_child_count(), 1, "%s holds its off hand" % id)
		check(m.get_node_or_null("Yaw/Body/Gear") != null, "%s armour" % id)
		var size := _mesh_bounds(m)
		check(size.y > 1.15 and size.y < 1.7, "%s ~1.3 m tall (%.2f)" % [id, size.y])


func _mesh_bounds(root: Node3D) -> Vector3:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for mi in _all_meshes(root):
		if not mi.is_visible_in_tree() or mi.name in ["Ring", "ReviveArea", "ReviveArc", "Pointer"]:
			continue
		var xf := _relative_xform(mi, root)
		var aabb := xf * mi.mesh.get_aabb()
		lo = lo.min(aabb.position)
		hi = hi.max(aabb.end)
	return hi - Vector3(hi.x, 0.0, hi.z) if lo.y > 0.0 else hi - lo


func _relative_xform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _all_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_meshes(c))
	return out


func test_onion_flash_and_hp() -> void:
	var m := _onion(&"warrior")
	var bulb := m.get_node("Yaw/Body/Bulb") as GeometryInstance3D
	m.flash_hit()
	check(_overlay(bulb) > 0.5, "white flash on hit")
	for i in 20:
		m._process(1.0 / 60.0)
	check_near(_overlay(bulb), 0.0, 0.001, "flash fades")
	m.set_hp_ratio(1.0)
	check_near(m.bulb_damage(), 0.0, 0.001, "healthy onion")
	m.set_hp_ratio(0.15)
	check(m.bulb_damage() > 0.5, "peeled at low HP")
	check(bulb.material_override == Mats.onion_skin(Db.get_class_data(&"warrior").onion_color, OnionModel.damage_amount(0.15)), "shared damage material")
	var visible_peels := 0
	for i in 3:
		if (m.get_node("Yaw/Body/Peel%d" % i) as Node3D).visible:
			visible_peels += 1
	check_eq(visible_peels, 3, "all peel flaps at 15% HP")
	m.set_hp_ratio(0.5)
	check((m.get_node("Yaw/Body/Peel0") as Node3D).visible, "first peel at 50%")
	check(not (m.get_node("Yaw/Body/Peel2") as Node3D).visible, "last peel hidden at 50%")


func test_onion_downed_ghost_and_revive() -> void:
	var m := _onion(&"mage")
	var bulb := m.get_node("Yaw/Body/Bulb") as GeometryInstance3D
	var original := bulb.material_override
	m.set_downed(true)
	check(bulb.material_override != original, "ghost material")
	check((m.get_node("Yaw/Body/Tear0") as Node3D).visible, "crying")
	check((m.get_node("ReviveArea") as Node3D).visible, "revive area shown")
	check(not (m.get_node("ReviveArc") as Node3D).visible, "no progress yet")
	check(not (m.get_node("Yaw/Body/HandMain/Grip").get_child(0) as Node3D).visible, "weapon hidden")
	m.set_revive_progress(0.5)
	check((m.get_node("ReviveArc") as Node3D).visible, "progress ring")
	var shape: Variant = _param(m.get_node("ReviveArc") as GeometryInstance3D, &"ring_shape")
	check(shape is Vector4 and is_equal_approx((shape as Vector4).w, 0.5), "ring arc = progress")
	for i in 30:
		m._process(1.0 / 30.0)
	check((m.get_node("Yaw/Body") as Node3D).position.y > 0.1, "ghost floats")
	m.set_downed(false)
	check(bulb.material_override == original, "normal look restored")
	check(not (m.get_node("ReviveArc") as Node3D).visible, "progress ring hidden")
	check((m.get_node("Yaw/Body/HandMain/Grip").get_child(0) as Node3D).visible, "weapon back")


func test_onion_facing_moving_and_attack() -> void:
	var m := _onion(&"rogue")
	m.set_facing(Vector3(1, 0, 0))
	for i in 60:
		m._process(1.0 / 60.0)
	var yaw := (m.get_node("Yaw") as Node3D).rotation.y
	check_near(angle_difference(yaw, OnionModel.yaw_for(Vector3.RIGHT)), 0.0, 0.02, "turned to +X")
	var forward := (m.get_node("Yaw") as Node3D).transform.basis * Vector3.FORWARD
	check(forward.x > 0.99, "model forward follows the direction")
	m.set_facing(Vector3.ZERO)
	check_near(angle_difference((m.get_node("Yaw") as Node3D).rotation.y, yaw), 0.0, 0.001, "zero direction ignored")
	m.set_moving(1.0)
	var heights: Array[float] = []
	for i in 40:
		m._process(1.0 / 60.0)
		heights.append((m.get_node("Yaw/Body") as Node3D).position.y)
	check(heights.max() > 0.03, "bobs while walking")
	var hand := m.get_node("Yaw/Body/HandOff") as Node3D
	var rest := hand.position
	m.play_attack(true)
	m._process(0.06)
	check(hand.position.distance_to(rest) > 0.05, "off hand swings")
	for i in 30:
		m._process(1.0 / 60.0)
	m.set_moving(0.0)


func test_onion_setup_twice_and_weapon_swap() -> void:
	var m := _onion(&"paladin")
	m.setup(Db.get_class_data(&"warlock"), Color.YELLOW)
	check_eq(m.class_data.id, &"warlock", "rebuilt for the new class")
	m.set_weapons(Db.get_weapon(&"wand"), Db.get_weapon(&"tome"))
	m.set_weapons(Db.get_weapon(&"dagger"), null)
	var off := m.get_node("Yaw/Body/HandOff/Grip")
	var live := 0
	for c in off.get_children():
		if not c.is_queued_for_deletion():
			live += 1
	check_eq(live, 0, "off hand emptied")


func test_onion_revive_cast_bar() -> void:
	var m := _onion(&"rogue")
	m.set_revive_progress(0.5)
	check(not m.is_cast_bar_visible(), "no cast bar while alive")
	m.set_downed(true)
	check(not m.is_cast_bar_visible(), "no cast bar before anyone revives")
	var reviver := Color(1.0, 0.3, 0.2)
	m.set_revive_progress(0.4, reviver, 3.0)
	check(m.is_cast_bar_visible(), "cast bar while being revived")
	var bar := m.get_node("CastBar") as GeometryInstance3D
	check_near(bar.global_position.y if bar.is_inside_tree() else bar.position.y, OnionModel.CAST_BAR_Y, 0.001, "above the head")
	check_near(_param(bar, &"bar_progress"), 0.4, 0.0001, "bar fill = progress")
	check(_param(bar, &"bar_color") == Color(reviver, 1.0), "reviver's colour")
	var label := m.get_node("CastLabel") as Label3D
	check(label.text.begins_with("Resurrecting") and label.text.contains("3.0"), "cast text with time (%s)" % label.text)
	var arc: Variant = _param(m.get_node("ReviveArc") as GeometryInstance3D, &"ring_color")
	check(arc is Color and (arc as Color).r > 0.9 and (arc as Color).g < 0.5, "ring in the reviver's colour")
	m.set_revive_progress(0.0)
	check(not m.is_cast_bar_visible(), "hidden when progress drops to zero")
	m.set_revive_progress(0.7, reviver)
	m.set_downed(false)
	check(not m.is_cast_bar_visible(), "hidden after the revive")


func test_onion_channels_a_revive_beam() -> void:
	var root := _keep(Node3D.new()) as Node3D
	tree.root.add_child(root)
	var healer := _onion(&"paladin")
	var ghost := _onion(&"mage")
	root.add_child(healer)
	root.add_child(ghost)
	ghost.position = Vector3(1.5, 0, 0)
	ghost.set_downed(true)
	var hand := healer.get_node("Yaw/Body/HandMain") as Node3D
	var rest_y := hand.position.y
	healer.set_channel_target(ghost)
	check(healer.is_channeling(), "channeling")
	for i in 10:
		healer._process(1.0 / 60.0)
	check(hand.position.y > rest_y + 0.3, "hands raised")
	var beam := healer.get_node("ChannelBeam") as Node3D
	check(beam.visible, "light beam shown")
	var end := beam.global_transform * Vector3(0, 1, 0)
	check(end.distance_to(ghost.global_position + Vector3.UP * OnionModel.CHANNEL_TARGET_HEIGHT) < 0.01, "beam ends on the ghost")
	check((hand.get_node("ChannelGlow") as Node3D).visible, "hands glow")
	healer.set_channel_target(null)
	check(not healer.is_channeling() and not beam.visible, "stopped")
	healer.set_channel_target(ghost)
	ghost.free()
	healer._process(1.0 / 60.0)
	check(not healer.is_channeling(), "stops when the target disappears")


# --- EnemyModel ---------------------------------------------------------------

func test_enemy_models_share_meshes() -> void:
	check(Db.enemies.size() >= 4, "enemies loaded")
	for id in Db.enemies:
		var data := Db.get_enemy(id)
		var a := _keep(EnemyModel.new()) as EnemyModel
		var b := _keep(EnemyModel.new()) as EnemyModel
		a.setup(data)
		b.setup(data)
		check_eq(a.style, data.model_style, "%s style" % id)
		var ba := a.get_node("Pivot/Body") as MeshInstance3D
		var bb := b.get_node("Pivot/Body") as MeshInstance3D
		check(ba.mesh == bb.mesh, "%s body mesh shared" % id)
		check((a.get_node("Pivot/Arm") as MeshInstance3D).mesh == (b.get_node("Pivot/Arm") as MeshInstance3D).mesh, "%s arm shared" % id)
		check(a.get_child_count() == 1 and a.get_node("Pivot").get_child_count() <= 3, "%s small node count" % id)
		check(a.head_height > 0.4, "%s head height" % id)
		check_near((a.get_node("Pivot") as Node3D).scale.x, data.model_scale, 0.001, "%s model scale" % id)


func test_enemy_animation_states() -> void:
	var e := _keep(EnemyModel.new()) as EnemyModel
	e.setup(Db.get_enemy(&"marsh_gurgler"))
	var body := e.get_node("Pivot/Body") as GeometryInstance3D
	e.flash_hit()
	check(_overlay(body) > 0.5, "hit flash")
	for i in 20:
		e._process(1.0 / 60.0)
	check_near(_overlay(body), 0.0, 0.001, "flash fades")
	e.play_windup()
	check(e.is_winding_up(), "winding up")
	e._process(0.1)
	var tint: Color = _param(body, Mats.OVERLAY_PARAM)
	check(tint.a > 0.05 and tint.r > tint.g, "red wind-up tell")
	check(_param(body, &"overlay_pulse") > 0.0, "pulsing")
	e.play_attack()
	check(not e.is_winding_up(), "attack ends the wind-up")
	for i in 30:
		e._process(1.0 / 60.0)
	e.set_stunned(true)
	check(e.is_stunned(), "stunned")
	var stars := e.get_node_or_null("Stars") as Node3D
	check(stars != null and stars.visible, "stun stars")
	e._process(0.1)
	e.set_stunned(false)
	check(not stars.visible, "stars hidden")
	e.set_facing(Vector3(0, 0, 1))
	e.set_moving(1.0)
	for i in 60:
		e._process(1.0 / 60.0)
	var pivot := e.get_node("Pivot") as Node3D
	check_near(absf(angle_difference(pivot.rotation.y, PI)), 0.0, 0.05, "faces +Z")


func test_unknown_enemy_style_falls_back() -> void:
	var data := EnemyData.new()
	data.model_style = &"no_such_style"
	var e := _keep(EnemyModel.new()) as EnemyModel
	e.setup(data)
	check_eq(e.style, &"skeleton", "fallback style")


func test_onion_player_marker() -> void:
	var m := _onion(&"warrior")
	check(not m.is_marker_visible(), "no marker without a tag (lobby previews)")
	m.set_tag("P2")
	check(m.is_marker_visible(), "marker shown")
	var label := m.get_node("Marker/Tag") as Label3D
	check_eq(label.text, "P2", "player tag")
	check(label.no_depth_test and label.fixed_size, "drawn through crowds at a fixed screen size")
	var diamond := m.get_node("Marker/Diamond") as Sprite3D
	check(diamond.no_depth_test, "diamond on top too")
	check(diamond.modulate.is_equal_approx(Color(0.2, 0.5, 1.0)), "diamond in the player colour")
	var marker := m.get_node("Marker") as Node3D
	check(marker.position.y >= OnionModel.MARKER_Y - 0.001, "above the head")
	check(OnionModel.marker_texture() == OnionModel.marker_texture(), "diamond texture built once")


func test_onion_ghost_stays_findable() -> void:
	var m := _onion(&"mage")
	m.set_tag("P3")
	var ring := m.get_node("Ring") as GeometryInstance3D
	check_near(_param(ring, &"ring_stroke"), 1.0, 0.0001, "player ring has the dark outline + white stroke")
	m.set_downed(true)
	check(ring.visible, "player-colour ring stays under the ghost")
	var area_color: Variant = _param(m.get_node("ReviveArea") as GeometryInstance3D, &"ring_color")
	check(area_color is Color and (area_color as Color).b > 0.9 and (area_color as Color).r < 0.3,
		"revive circle in the downed player's colour")
	check_near((area_color as Color).a, OnionModel.REVIVE_AREA_ALPHA, 0.001, "revive circle alpha")
	var bulb := m.get_node("Yaw/Body/Bulb") as GeometryInstance3D
	var ghost: Variant = (bulb.material_override as ShaderMaterial).get_shader_parameter(&"color")
	check(ghost is Color and is_equal_approx((ghost as Color).a, OnionModel.GHOST_ALPHA), "ghost alpha ~0.6")
	# The ring breathes.
	var sizes: Array[float] = []
	for i in 40:
		m._process(1.0 / 30.0)
		sizes.append(ring.scale.x)
	check(sizes.max() - sizes.min() > 0.1, "ring pulses while downed")
	var marker := m.get_node("Marker") as Node3D
	check(m.is_marker_visible(), "marker over the ghost")
	check(marker.position.y > OnionModel.MARKER_Y, "higher over the floating ghost")
	var heights: Array[float] = []
	for i in 30:
		m._process(1.0 / 30.0)
		heights.append(marker.position.y)
	check(heights.max() - heights.min() > OnionModel.MARKER_GHOST_BOB, "marker bobs")
	m.set_revive_progress(0.5, Color.RED, 2.0)
	m._process(0.01)
	check(marker.position.y > OnionModel.CAST_BAR_Y + 0.8, "lifted above the Resurrecting cast bar")
	m.set_downed(false)
	m._process(0.01)
	check_near(ring.scale.x, OnionModel.RING_SIZE, 0.001, "normal ring after the revive")
	check_near(marker.position.y, OnionModel.MARKER_Y, 0.001, "marker back above the head")


func test_rogue_and_warlock_read_from_above() -> void:
	var rogue := Db.get_class_data(&"rogue")
	check(rogue.accent_color.get_luminance() > 0.35, "rogue cowl is a light olive leather, not black")
	check(rogue.onion_color.get_luminance() > 0.8, "pale spring onion")
	var r := _onion(&"rogue")
	check(r.get_node_or_null("Yaw/Body/Sprout") != null, "green stalk")
	var w := _onion(&"warlock")
	var flames := 0
	for n: String in ["Yaw/Body/HornFlameL", "Yaw/Body/HornFlameR"]:
		if w.get_node_or_null(n) != null and (w.get_node(n) as Node3D).visible:
			flames += 1
	check_eq(flames, 2, "purple flames on both horns")
	check(OnionModel.WARLOCK_HOOD.get_luminance() > 0.2, "warlock hood light enough to read")
	w.set_downed(true)
	check(not (w.get_node("Yaw/Body/HornFlameL") as Node3D).visible, "no flames on the ghost")
