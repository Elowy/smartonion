extends TestCase
## The Shaman's look (M8): a garlic bulb (white-lilac with purple streaks) in a carved wooden mask, bone beads and a
## small totem on the back; the procedural totem models (one per element, cheap) and the Surge colour of the class.

var _nodes: Array[Node] = []


func after_each() -> void:
	for i in range(_nodes.size() - 1, -1, -1):
		if is_instance_valid(_nodes[i]):
			_nodes[i].free()
	_nodes.clear()


func _keep(n: Node) -> Node:
	_nodes.append(n)
	tree.root.add_child(n)
	return n


func _onion(class_id: StringName) -> OnionModel:
	var cd := Db.get_class_data(class_id)
	var m := OnionModel.new()
	_keep(m)
	m.setup(cd, Color(0.2, 0.5, 1.0))
	m.set_weapons(cd.main_hand, cd.off_hand)
	m.set_looks(null, null, null)
	return m


func _draws(root: Node) -> int:
	var total := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var outlined := mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).next_pass != null
		total += mi.mesh.get_surface_count() * (2 if outlined else 1)
	return total


## A totem model of [param element] in the tree (set up before it enters the tree, like ShamanTotem.plant).
func _totem_model(element: StringName) -> ShamanTotemModel:
	var model := ShamanTotemModel.new()
	model.setup(element)
	_keep(model)
	return model


func _faces(mesh: Mesh) -> int:
	return mesh.get_faces().size() / 3 if mesh != null else 0


# --- The hero ---------------------------------------------------------------------------------------------

func test_the_head_and_chest_pieces_are_the_shamans_own() -> void:
	var cd := Db.get_class_data(&"shaman")
	var head := OnionArmor.part(EquipLook.Slot.HEAD, null, cd)
	var chest := OnionArmor.part(EquipLook.Slot.CHEST, null, cd)
	var shoulders := OnionArmor.part(EquipLook.Slot.SHOULDERS, null, cd)
	check(head != null and head.solid != null and head.is_starter(), "a starter head piece")
	check(chest != null and chest.solid != null, "a starter chest piece")
	check(shoulders != null and shoulders.solid != null, "big shoulders")
	var plain := ClassData.new()
	plain.id = &"zz_plain"
	plain.headgear = &"zz_unknown"
	plain.accent_color = cd.accent_color
	var circlet := OnionArmor.part(EquipLook.Slot.HEAD, null, plain)
	check(_faces(head.solid) > _faces(circlet.solid) * 2, "the mask, band and feathers are far more than the plain circlet (%d vs %d faces)"
			% [_faces(head.solid), _faces(circlet.solid)])
	var belt := OnionArmor.part(EquipLook.Slot.CHEST, null, plain)
	check(_faces(chest.solid) > _faces(belt.solid) * 3, "the bead strings are more than the default belt (%d vs %d faces)"
			% [_faces(chest.solid), _faces(belt.solid)])
	check(head.brows and not head.hides_sprout and not head.hides_mouth, "face, brows and sprout stay readable")
	check(head.extras.is_empty() and chest.extras.is_empty(), "no animated extras")


func test_the_head_piece_keeps_the_eyes_and_mouth_free() -> void:
	var cd := Db.get_class_data(&"shaman")
	var head := OnionArmor.part(EquipLook.Slot.HEAD, null, cd)
	var low := INF
	for s in head.solid.get_surface_count():
		for v: Vector3 in head.solid.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			if v.z < -0.2 and absf(v.x) < 0.2:
				low = minf(low, v.y)
	check(low > 0.62, "the mask stays above the eyes (lowest front point %.2f)" % low)


func test_the_hero_is_a_garlic_bulb_with_a_totem_on_its_back() -> void:
	var m := _onion(&"shaman")
	var bulb := m.get_node("Yaw/Body/Bulb") as MeshInstance3D
	var mat := bulb.material_override as ShaderMaterial
	check(mat != null and mat.shader.code.contains("#define GARLIC"), "the bulb has the garlic streaks")
	check(m.get_node_or_null("Yaw/Body/BackTotem") != null, "the small totem on the back")
	check((m.get_node("Yaw/Body/Sprout") as Node3D).visible, "the pale sprout shows")
	var other := _onion(&"warrior")
	var other_mat := (other.get_node("Yaw/Body/Bulb") as MeshInstance3D).material_override as ShaderMaterial
	check(not other_mat.shader.code.contains("#define GARLIC"), "other onions are plain")
	check(other.get_node_or_null("Yaw/Body/BackTotem") == null, "and carry no totem")
	m.set_hp_ratio(0.3)
	var hurt := bulb.material_override as ShaderMaterial
	check(hurt.shader.code.contains("#define GARLIC") and float(hurt.get_shader_parameter("damage")) > 0.0, "a peeled garlic keeps its streaks")


func test_the_skin_is_white_lilac_and_the_gloves_are_wooden() -> void:
	var cd := Db.get_class_data(&"shaman")
	check(cd.onion_color.get_luminance() > 0.8, "a pale garlic")
	check(cd.onion_color.b > cd.onion_color.g, "with a lilac tint")
	var m := _onion(&"shaman")
	check_eq(m._glove_color(), Color(0.5, 0.34, 0.2), "wrapped wooden-brown hands")
	check(m._boot_color() != OnionModel.LEATHER, "dark wooden boots")


func test_the_look_costs_few_draw_calls() -> void:
	var m := _onion(&"shaman")
	var draws := _draws(m)
	var warrior := _draws(_onion(&"warrior"))
	check(draws <= 30, "the starter look draws %d (the warrior %d)" % [draws, warrior])
	check(draws <= warrior + 6, "at most six more than the warrior")


func test_the_meter_colour_stays_readable() -> void:
	var c := RunSummary.class_color(Db.get_class_data(&"shaman"))
	check(c.get_luminance() <= RunSummary.MAX_CLASS_LUMINANCE + 0.001, "not brighter than the ceiling")
	check(c.get_luminance() >= RunSummary.MIN_CLASS_LUMINANCE - 0.001, "not darker than the floor")


func test_the_surge_bar_has_the_class_colour() -> void:
	var cd := Db.get_class_data(&"shaman")
	check(cd.resources[0].color.is_equal_approx(cd.resource_color), "the resource and the class agree on the colour")
	var slot := PlayerSlot.new(0, ScriptedInput.new("t:0"), Color(0.2, 0.5, 1.0))
	slot.class_data = cd
	var p := Player.create(slot)
	_keep(p)
	check_eq(p.abilities.primary_resource().data.color, cd.resource_color, "the HUD bar is cyan")


# --- Totem models -------------------------------------------------------------------------------------------

func test_every_totem_element_has_a_cheap_model() -> void:
	for element: StringName in [&"fire", &"water", &"earth", &"air", &"bond", &"storm"]:
		var model := _totem_model(element)
		var draws := _draws(model)
		check(draws >= 3 and draws <= 9, "%s: %d draws" % [element, draws])
		check(model.get_node_or_null("Body") != null and model.get_node_or_null("Crown/CrownMesh") != null, "%s: body and crown" % element)
		check(model.get_node_or_null("Disc") != null, "%s: the ground disc that colours it from above" % element)
		check_eq(model.color(), ShamanKit.ELEMENT_COLORS[element], "%s: the element colour" % element)
		var crown := model.get_node("Crown/CrownMesh") as MeshInstance3D
		check(_faces(crown.mesh) > 20, "%s: a real crown (%d faces)" % [element, _faces(crown.mesh)])
		var top := 0.0
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var box := (mi as MeshInstance3D).mesh.get_aabb()
			top = maxf(top, box.end.y)
		check(top > 1.3 and top < 2.0, "%s: %.2f m tall, a post over the heroes' heads" % [element, top])


func test_totem_meshes_are_shared_between_totems() -> void:
	var a := _totem_model(&"water")
	var b := _totem_model(&"water")
	check((a.get_node("Body") as MeshInstance3D).mesh == (b.get_node("Body") as MeshInstance3D).mesh, "one cached body mesh per element")
	check((a.get_node("Crown/CrownMesh") as MeshInstance3D).mesh == (b.get_node("Crown/CrownMesh") as MeshInstance3D).mesh, "and one crown")
	var fire := _totem_model(&"fire")
	check((fire.get_node("Crown/CrownMesh") as MeshInstance3D).mesh != (a.get_node("Crown/CrownMesh") as MeshInstance3D).mesh, "elements differ")


func test_a_totem_grows_in_and_shrinks_out() -> void:
	var model := _totem_model(&"earth")
	model.set_grow(0.0)
	check(model.scale.x < 0.01, "starts tiny")
	model.set_grow(0.5)
	check_near(model.scale.x, 0.5, 0.0001, "half grown")
	model.set_grow(2.0)
	check_near(model.scale.x, 1.0, 0.0001, "never larger than the full size")


func test_a_planted_totem_wears_its_model_and_fades_with_its_life() -> void:
	var world := Node3D.new()
	_keep(world)
	tree.current_scene = world
	RunState.start_run(1, 3)
	var slot := PlayerSlot.new(0, ScriptedInput.new("t:0"), Color(0.2, 0.5, 1.0))
	slot.class_data = Db.get_class_data(&"shaman")
	var p := Player.create(slot)
	world.add_child(p)
	var t := ShamanTotem.plant(p, &"air", Db.get_ability(&"totem_rite").params, Vector3(2, 0, 2), 10.0)
	check(t.is_inside_tree() and t.model != null, "planted with a model")
	check(t.model.scale.x < 0.01, "it rises")
	t.step(0.1)
	check_near(t.model.scale.x, 0.5, 0.01, "half way after 0.1 s of the 0.2 s fade")
	t.step(0.2)
	check_near(t.model.scale.x, 1.0, 0.0001, "full size")
	t.life_left = 0.1
	t.step(0.01)
	check_near(t.model.scale.x, 0.45, 0.06, "it shrinks before it ends")
