extends TestCase
## Hunter look (M8): the feathered hat, the fur-trimmed mail pauldron, the quiver and the strap, the gloves
## and boots, the Play Dead pose, the class colour of the meter and the three companion models.

const Fakes := preload("res://tests/player_fakes.gd")

const HEAD := EquipLook.Slot.HEAD
const CHEST := EquipLook.Slot.CHEST

var _nodes: Array[Node] = []


func after_each() -> void:
	for i in range(_nodes.size() - 1, -1, -1):
		if is_instance_valid(_nodes[i]):
			_nodes[i].free()
	_nodes.clear()


func _onion() -> OnionModel:
	var cd := Db.get_class_data(&"hunter")
	var m := OnionModel.new()
	_nodes.append(m)
	m.setup(cd, Color(0.2, 0.5, 1.0))
	m.set_weapons(cd.main_hand, cd.off_hand)
	return m


func _draws(root: Node) -> int:
	var total := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() and not _visible_below(mi, root):
			continue
		var outlined := mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).next_pass != null
		total += mi.mesh.get_surface_count() * (2 if outlined else 1)
	return total


func _visible_below(node: Node, root: Node) -> bool:
	var n := node
	while n != null:
		if n is Node3D and not (n as Node3D).visible:
			return false
		if n == root:
			return true
		n = n.get_parent()
	return true


## Euclidean distance of two colours in RGB.
func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


# --- The hero ---------------------------------------------------------------------------------

func test_the_hat_is_more_than_the_plain_circlet_and_covers_the_sprout() -> void:
	var cd := Db.get_class_data(&"hunter")
	var head := OnionArmor.part(HEAD, null, cd)
	check(head != null and head.solid != null and head.is_starter(), "a starter head piece")
	var circlet := ClassFixtureHeads.circlet_faces()
	check(head.solid.get_faces().size() > circlet * 2, "much more than the plain circlet (%d faces)" % head.solid.get_faces().size())
	check(head.hides_sprout, "the hat closes over the sprout")
	check(head.brows and not head.hides_mouth, "the brows and mouth stay")
	check(head.extras.is_empty(), "no animated extras")
	check_eq(head.solid.get_surface_count(), 1, "one merged surface: no extra draw call")
	var m := _onion()
	check(not (m.get_node("Yaw/Body/Sprout") as Node3D).visible, "the model hides the sprout under the hat")


func test_the_starter_chest_has_the_pauldron_strap_and_quiver() -> void:
	var cd := Db.get_class_data(&"hunter")
	var chest := OnionArmor.part(CHEST, null, cd)
	check(chest != null and chest.solid != null and chest.is_starter(), "a starter chest piece")
	var belt_only := OnionArmor.part(CHEST, null, Db.get_class_data(&"warrior"))
	check(chest.solid.get_faces().size() > belt_only.solid.get_faces().size() * 4, "far more than a belt")
	check_eq(chest.solid.get_surface_count(), 1, "still one merged surface")
	# Fur, mail, leather and the quiver's arrows are in the vertex colours.
	var aabb := chest.solid.get_aabb()
	check(aabb.position.z + aabb.size.z > 0.45, "the quiver sticks out at the back (z > 0.45)")
	check(aabb.position.x < -0.3, "the pauldron sits over the left shoulder")
	var shoulders := OnionArmor.part(EquipLook.Slot.SHOULDERS, null, cd)
	check(shoulders == null or shoulders.solid == null, "no big shoulders: the pauldron belongs to the chest piece")


func test_gloves_boots_and_brows_have_their_own_look() -> void:
	var m := _onion()
	check_eq(m._glove_color(), Color(0.45, 0.3, 0.18), "brown leather gloves")
	check_eq(m._boot_color(), Color(0.3, 0.2, 0.12), "dark boots")
	var cd := Db.get_class_data(&"hunter")
	check(m._glove_color() != cd.onion_color.lightened(0.1), "not the plain default")
	var rogue := Db.get_class_data(&"rogue")
	check(_dist(cd.onion_color, rogue.onion_color) > 0.3, "a skin of its own")


func test_the_hunter_is_cheaper_than_the_heaviest_class() -> void:
	var m := _onion()
	var draws := _draws(m)
	check(draws <= 40, "%d draws for the starter look (ceiling 40, the Warlock has 32)" % draws)
	check(draws >= 20, "(and it is a full model: %d)" % draws)


func test_play_dead_tips_the_body_and_stands_up_again() -> void:
	var m := _onion()
	check_eq(m.tip_amount(), 0.0, "upright")
	m.set_play_dead(true)
	for i in 30:
		m._process(1.0 / 30.0)
	check(m.tip_amount() > 0.99, "tipped over")
	var body := m.get_node("Yaw/Body") as Node3D
	check(absf(body.rotation.z) > 1.3, "on its side (%.2f rad)" % body.rotation.z)
	check(body.position.y > 0.3, "resting on the ground, not in it")
	m.set_play_dead(false)
	for i in 30:
		m._process(1.0 / 30.0)
	check_eq(m.tip_amount(), 0.0, "up again")
	check(absf((m.get_node("Yaw/Body") as Node3D).rotation.z) < 0.4, "standing")


func test_the_class_colour_of_the_meter_tells_the_hunter_apart() -> void:
	var color := RunSummary.class_color(Db.get_class_data(&"hunter"))
	check(color.get_luminance() >= RunSummary.MIN_CLASS_LUMINANCE - 0.001 and color.get_luminance() <= RunSummary.MAX_CLASS_LUMINANCE + 0.001,
			"within the readable luminance range")
	for id in Db.class_ids:
		if id == &"hunter":
			continue
		var other := RunSummary.class_color(Db.get_class_data(id))
		check(_dist(color, other) > 0.12, "distinct from %s (%.2f)" % [id, _dist(color, other)])


# --- Companion models -----------------------------------------------------------------------------

func _model(kind: StringName) -> HunterCompanionModel:
	var model := HunterCompanionModel.new()
	model.kind = kind
	_nodes.append(model)
	var holder := Node3D.new()
	_nodes.append(holder)
	holder.add_child(model)
	Engine.get_main_loop().root.add_child(holder)
	return model


func test_each_companion_model_builds_with_its_parts() -> void:
	for kind: StringName in [&"wolf", &"boar", &"owl"]:
		var model := _model(kind)
		check(model.get_node_or_null("Pivot/Body") != null, "%s: a body mesh" % kind)
		check((model.get_node("Pivot/Body") as MeshInstance3D).mesh.get_surface_count() == 1, "%s: one merged surface" % kind)
		var parts := model.find_children("*", "MeshInstance3D", true, false).size()
		check(parts >= 3, "%s: %d mesh parts" % [kind, parts])
		check(parts <= 9, "%s: a light model (%d parts)" % [kind, parts])
	check_eq(_model(&"wolf").find_children("Leg*", "Node3D", true, false).size(), 4, "the Wolf has four legs")
	check_eq(_model(&"boar").find_children("Leg*", "Node3D", true, false).size(), 4, "the Boar has four legs")
	check_eq(_model(&"owl").find_children("Wing*", "Node3D", true, false).size(), 2, "the Owl has two wings")
	check_eq(_model(&"owl").find_children("Leg*", "Node3D", true, false).size(), 0, "and no legs to run on")


func test_the_owl_hovers_and_the_others_stand_on_the_ground() -> void:
	var owl := _model(&"owl")
	check_near(owl._pivot.position.y, HunterCompanionModel.HOVER_HEIGHT, 0.01, "the Owl's pivot is lifted 1.6 m")
	check(owl.get_node_or_null("Shadow") != null, "with a ground shadow")
	for kind: StringName in [&"wolf", &"boar"]:
		check_near(_model(kind)._pivot.position.y, 0.0, 0.01, "the %s stands on the ground" % kind)


func test_animation_moves_nodes_only_and_the_dive_lowers_the_owl() -> void:
	var owl := _model(&"owl")
	owl.set_moving(1.0)
	for i in 10:
		owl._process(1.0 / 60.0)
	var wing := owl._wings[0] as Node3D
	var before := wing.rotation.z
	for i in 5:
		owl._process(1.0 / 60.0)
	check(absf(wing.rotation.z - before) > 0.01, "the wings flap")
	var high := owl._pivot.position.y
	owl.set_diving(true)
	for i in 60:
		owl._process(1.0 / 60.0)
	check(owl._pivot.position.y < high - 0.5, "a Hunt Signal dive brings the Owl down")
	var wolf := _model(&"wolf")
	wolf.set_moving(1.0)
	wolf._process(0.1)
	wolf._process(0.1)
	var swing := false
	for leg in wolf._legs:
		swing = swing or absf(leg.rotation.x) > 0.05
	check(swing, "the Wolf's legs swing while it runs")
	wolf.play_attack()
	wolf._process(0.05)
	check(wolf._pivot.rotation.x < -0.01, "and it lunges when it bites")


func test_the_frenzy_ring_shows_only_while_frenzied() -> void:
	var wolf := _model(&"wolf")
	var glow := wolf.get_node("FrenzyGlow") as Node3D
	check(not glow.visible, "calm")
	wolf.set_frenzy(true)
	check(glow.visible and wolf.is_frenzied(), "ring on")
	wolf.set_frenzy(false)
	check(not glow.visible, "ring off")


func test_snare_and_arrow_models_are_cheap_shared_meshes() -> void:
	check(HunterSnare.body_mesh() == HunterSnare.body_mesh(), "the snare mesh is cached")
	check(HunterArrowHailVfx.arrow_mesh() == HunterArrowHailVfx.arrow_mesh(), "so is the hail's arrow")
	check_eq(HunterSnare.body_mesh().get_surface_count(), 1, "one surface")


## The plain circlet's face count (OnionArmor._head_plain through a class with an unknown headgear id).
class ClassFixtureHeads:
	static func circlet_faces() -> int:
		var k := MeshKit.new()
		var cd := Db.get_class_data(&"warrior").duplicate() as ClassData
		cd.headgear = &"zz_unknown_headgear"
		OnionArmor._head_plain(k, cd)
		return k.build().get_faces().size()
