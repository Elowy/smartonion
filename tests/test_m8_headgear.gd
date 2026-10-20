extends TestCase
## M8 P0 – headgear defaults: a class whose headgear id the armour and body builders do not know
## (and the M8 id tribal_mask until its class package draws it; hunter_hat is drawn since the Hunter,
## see test_class_hunter_look) shows a plain circlet, the default gloves and boots – never a bare
## head. The classes are fixtures.

const Rules := preload("res://tests/content_rules.gd")
const ClassFixtures := preload("res://tests/class_fixtures.gd")

const HEAD := EquipLook.Slot.HEAD
const CHEST := EquipLook.Slot.CHEST

var classes := ClassFixtures.new()
var _nodes: Array[Node] = []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	classes.restore()


func _onion(cd: ClassData) -> OnionModel:
	var m := OnionModel.new()
	_nodes.append(m)
	m.setup(cd, Color(0.2, 0.5, 1.0))
	return m


# --- Headgear defaults ------------------------------------------------------------------------

func test_an_unknown_headgear_id_draws_a_plain_head_never_a_bare_one() -> void:
	for gear: StringName in [&"zz_unknown_headgear", &"", &"tribal_mask"]:
		var cd := classes.add_class(gear)
		var head := OnionArmor.part(HEAD, null, cd)
		check(head != null and head.solid != null, "headgear '%s': a head piece is drawn" % gear)
		if head == null:
			continue
		check(head.is_starter(), "'%s': the starter piece" % gear)
		check(head.brows and not head.hides_sprout and not head.hides_mouth, "'%s': face, brows and sprout stay" % gear)
		check(head.extras.is_empty(), "'%s': no class extras" % gear)
		var chest := OnionArmor.part(CHEST, null, cd)
		check(chest != null and chest.solid != null, "'%s': the default belt" % gear)
		var m := _onion(cd)
		check(m.get_node_or_null("Yaw/Body/Gear/Solid") != null, "'%s': the model shows the plain armour mesh" % gear)
		check((m.get_node("Yaw/Body/Sprout") as Node3D).visible, "'%s': the sprout shows" % gear)
		check_eq(m._glove_color(), cd.onion_color.lightened(0.1), "'%s': the default gloves" % gear)
		check_eq(m._boot_color(), OnionModel.LEATHER, "'%s': the default boots" % gear)
		classes.restore()


func test_the_plain_head_adds_no_draw_call() -> void:
	# The circlet joins the single "Solid" mesh of the starter gear, like the classes' own heads.
	var cd := classes.add_class(&"zz_unknown_headgear")
	var head := OnionArmor.part(HEAD, null, cd)
	check_eq(head.solid.get_surface_count(), 1, "one surface: merged with the rest of the gear")


func test_known_headgear_is_not_the_plain_circlet() -> void:
	var plain := classes.add_class(&"zz_unknown_headgear")
	var circlet := OnionArmor.part(HEAD, null, plain).solid.get_faces().size()
	classes.restore()
	for id in Rules.LAUNCH_CLASSES:
		var head := OnionArmor.part(HEAD, null, Db.get_class_data(id))
		check(head != null and head.solid != null, "%s: its head piece" % id)
		check(head.solid.get_faces().size() > circlet, "%s: more than the plain circlet (%d faces)" % [id, head.solid.get_faces().size()])


