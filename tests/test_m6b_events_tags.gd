extends TestCase
## M6b EVENTS, the name tags: the chest's, the totem's and the cart's [EventTag] keep on screen and out from
## under the HUD like the Loot Goblin's tag (LootGoblin.clamp_tag_in / label_screen_size, the camera's
## get_safe_screen_rect): in the middle of the view they sit above the object, near the edge of the free
## part of the screen – or with the object in a corner under a unit frame, or off screen – they slide along
## its edge.

const PAD := LootGoblin.TAG_SCREEN_PAD

class FakeHero extends Node3D:
	func is_alive() -> bool:
		return true


var _nodes: Array[Node] = []
var _root_size := Vector2i.ZERO


func before_each() -> void:
	# A 16:9 window like a player's (the headless one is a tiny square): the camera reads its aspect.
	_root_size = tree.root.size
	tree.root.size = Vector2i(1920, 1080)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	tree.root.size = _root_size


## An Arena in the tree with a hero at the origin and the camera snapped onto it. Event objects added
## afterwards are not framed yet: the camera stays where it is.
func _arena_with_hero() -> Arena:
	RunState.start_run(1, 4242)
	var arena := Arena.create()
	_nodes.append(arena)
	tree.root.add_child(arena)
	var hero := FakeHero.new()
	hero.add_to_group(&"players")
	tree.root.add_child(hero)
	_nodes.append(hero)
	arena.camera.snap()
	return arena


func _object(kind: int, arena: Arena, at: Vector3) -> Node3D:
	var n: Node3D
	match kind:
		0:
			n = GuardedChest.create(5)
		1:
			n = DefendTotem.create(5)
		_:
			n = CaravanCart.create_route(5, Vector3(-15, 0, at.z), Vector3(15, 0, at.z))
	arena.entities.add_child(n)
	n.global_position = at
	return n


func _tag_of(n: Node3D) -> EventTag:
	return n.get_node("NameTag") as EventTag


## The tag on screen (px): bottom-centre anchored at the label's world position.
func _tag_rect(tag: EventTag) -> Rect2:
	var cam := tag.get_viewport().get_camera_3d()
	var view := cam.get_viewport().get_visible_rect()
	var size := LootGoblin.label_screen_size(tag, view.size.y, cam.fov)
	var s := cam.unproject_position(tag.global_position)
	return Rect2(s.x - size.x * 0.5, s.y - size.y, size.x, size.y)


## A ground point well inside the free part of the view: a little south of the camera's focus.
func _middle(rig: CameraRig) -> Vector3:
	return rig.focus + Vector3(0.0, 0.0, 4.0)


## The ground point at the top right of the camera's view (just inside the visible ground).
func _top_right_corner(rig: CameraRig) -> Vector3:
	var ext := CameraRig.ground_extents(rig.distance, rig._aspect())
	return Vector3(rig.focus.x + ext.x - 0.5, 0.0, rig.focus.z - ext.y + 1.5)


# --- The clamp ------------------------------------------------------------------------------------

func test_clamp_tag_in_keeps_the_tag_inside_any_rectangle() -> void:
	var area := Rect2(100, 50, 800, 500)
	var size := Vector2(200, 40)
	check_eq(LootGoblin.clamp_tag_in(Vector2(500, 300), size, area, 8.0), Vector2(500, 300), "inside: unchanged")
	check_eq(LootGoblin.clamp_tag_in(Vector2(0, 300), size, area, 8.0), Vector2(208, 300), "left edge: area + pad + half the tag")
	check_eq(LootGoblin.clamp_tag_in(Vector2(990, 300), size, area, 8.0), Vector2(792, 300), "right edge")
	check_eq(LootGoblin.clamp_tag_in(Vector2(500, 0), size, area, 8.0), Vector2(500, 98), "top: the tag's height fits under the edge")
	check_eq(LootGoblin.clamp_tag_in(Vector2(500, 900), size, area, 8.0), Vector2(500, 542), "bottom")
	check_eq(LootGoblin.clamp_tag_in(Vector2(0, 0), Vector2(900, 40), area, 8.0), Vector2(500, 98),
		"a tag wider than the area is centred on it")
	var view := Vector2(1000, 600)
	for p in [Vector2(950, 300), Vector2(-300, 900), Vector2(500, 10)]:
		check_eq(LootGoblin.clamp_tag(p, size, view, 8.0), LootGoblin.clamp_tag_in(p, size, Rect2(Vector2.ZERO, view), 8.0),
			"the goblin's clamp is the same one on the whole view")


func test_the_safe_screen_rect_is_the_free_part_of_the_view() -> void:
	var arena := _arena_with_hero()
	var rig := arena.camera
	var cam := rig.camera
	var view := cam.get_viewport().get_visible_rect()
	var safe := rig.get_safe_screen_rect()
	check(view.encloses(safe), "inside the view: %s in %s" % [safe, view])
	check(safe.position.y > view.size.y * 0.08, "below the wave plaque: top at %.0f of %.0f px" % [safe.position.y, view.size.y])
	check(safe.end.y < view.size.y - 4.0, "above the bottom strip: %.0f of %.0f px" % [safe.end.y, view.size.y])
	check(safe.position.x > 4.0 and safe.end.x < view.size.x - 4.0, "away from the side edges: %s" % safe)
	var g := rig.get_safe_ground_rect()
	for corner in [Vector3(g.position.x, 0.0, g.position.y), Vector3(g.end.x, 0.0, g.end.y),
			Vector3(g.position.x, 0.0, g.end.y), Vector3(g.end.x, 0.0, g.position.y)]:
		var s := cam.unproject_position(corner)
		check(s.y >= safe.position.y - 1.0 and s.y <= safe.end.y + 1.0, "the ground rect's rows %s are the rect's" % s)
	check_eq(CameraRig.safe_screen_rect(cam, Rect2()), view, "no ground rect: the whole view")


# --- The tags -------------------------------------------------------------------------------------

func test_the_event_objects_have_event_tags_that_run_every_frame() -> void:
	var arena := _arena_with_hero()
	var heights := [2.35, 4.2, 2.4]
	for kind in 3:
		var n := _object(kind, arena, Vector3(2.0, 0.0, 3.0))
		var tag := _tag_of(n)
		check(tag != null, "kind %d has an EventTag called NameTag" % kind)
		if tag == null:
			continue
		check_near(tag.home.y, heights[kind], 0.0001, "kind %d: its tag floats %.2f m up" % [kind, heights[kind]])
		check(tag.is_processing(), "kind %d: the tag follows the camera every rendered frame" % kind)
		check(tag.fixed_size and tag.no_depth_test and tag.billboard == BaseMaterial3D.BILLBOARD_ENABLED,
			"kind %d: a fixed-size billboard without depth test" % kind)


func test_a_tag_in_the_middle_of_the_view_stays_above_its_object() -> void:
	var arena := _arena_with_hero()
	for kind in 3:
		var n := _object(kind, arena, _middle(arena.camera))
		var tag := _tag_of(n)
		tag.keep_on_screen()
		check(tag.position.is_equal_approx(tag.home), "kind %d: the tag sits at its home" % kind)


func test_a_tag_in_a_screen_corner_is_kept_out_from_under_the_hud() -> void:
	var arena := _arena_with_hero()
	var rig := arena.camera
	var cam := rig.camera
	var view := cam.get_viewport().get_visible_rect()
	var safe := rig.get_safe_screen_rect()
	var corner := _top_right_corner(rig)
	for kind in 3:
		var n := _object(kind, arena, corner)
		var tag := _tag_of(n)
		var home_screen := cam.unproject_position(n.global_transform * tag.home)
		check(not safe.has_point(home_screen), "kind %d: its home %s is outside the free area %s (that is the case)" % [kind, home_screen, safe])
		tag.keep_on_screen()
		var r := _tag_rect(tag)
		check(view.encloses(r), "kind %d: the whole tag is on screen: %s in %s" % [kind, r, view])
		check(safe.grow(-PAD + 0.5).encloses(r), "kind %d: and inside the free area: %s in %s" % [kind, r, safe])
		check(not tag.position.is_equal_approx(tag.home), "kind %d: it slid along the edge" % kind)
		check(r.get_center().x > view.size.x * 0.5, "kind %d: still on the right, pointing the way: %s" % [kind, r])
		n.global_position = _middle(rig)
		tag.keep_on_screen()
		check(tag.position.is_equal_approx(tag.home), "kind %d: back in the middle: above the object again" % kind)


func test_a_tag_of_an_object_off_the_screen_stays_on_it() -> void:
	var arena := _arena_with_hero()
	var rig := arena.camera
	var view := rig.camera.get_viewport().get_visible_rect()
	var safe := rig.get_safe_screen_rect()
	var ext := CameraRig.ground_extents(rig.distance, rig._aspect())
	var away := [Vector3(rig.focus.x + ext.x + 14.0, 0.0, rig.focus.z), Vector3(rig.focus.x - ext.x - 14.0, 0.0, rig.focus.z + 2.0)]
	for kind in 3:
		var n := _object(kind, arena, away[kind % 2])
		var tag := _tag_of(n)
		tag.keep_on_screen()
		var r := _tag_rect(tag)
		check(view.encloses(r) and safe.grow(-PAD + 0.5).encloses(r), "kind %d: the tag is in the free area: %s in %s" % [kind, r, safe])


func test_a_tag_without_a_camera_stays_at_home() -> void:
	var arena := _arena_with_hero()
	var n := _object(0, arena, Vector3(4.0, 0.0, 2.0))
	var tag := _tag_of(n)
	tag.position = Vector3(9.0, 9.0, 9.0)
	arena.camera.camera.clear_current()
	tag.keep_on_screen()
	check(tag.position.is_equal_approx(tag.home), "no camera: back at home")
	check(is_instance_valid(tag), "(and nothing broke)")


func test_a_two_line_tag_is_measured_with_both_lines() -> void:
	var arena := _arena_with_hero()
	var cam := arena.camera.camera
	var view_h := cam.get_viewport().get_visible_rect().size.y
	var totem := _object(1, arena, Vector3(2.0, 0.0, 2.0)) as DefendTotem
	var tag := _tag_of(totem)
	var lines := tag.text.split("\n").size()
	check_eq(lines, 2, "the totem's tag reads over two lines (\"Totem\" / \"Hold N s\")")
	var two := LootGoblin.label_screen_size(tag, view_h, cam.fov)
	tag.text = "Totem"
	var one := LootGoblin.label_screen_size(tag, view_h, cam.fov)
	check(two.y > one.y * 1.6, "two lines are about twice as tall: %.1f vs %.1f px" % [two.y, one.y])
	var goblin := LootGoblin.create(LootGoblin.goblin_data(), 5)
	_nodes.append(goblin)
	check_eq(goblin.tag_screen_size(view_h, cam.fov), LootGoblin.label_screen_size(goblin.label, view_h, cam.fov),
		"the goblin's own tag is measured the same way")
