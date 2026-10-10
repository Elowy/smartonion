extends TestCase
## Arena: construction, collision walls, spawn layout and the point helpers.

var _arena: Arena


func after_each() -> void:
	if _arena != null and is_instance_valid(_arena):
		_arena.free()
	_arena = null


func _make(in_tree: bool = true) -> Arena:
	_arena = Arena.create()
	if in_tree:
		tree.root.add_child(_arena)
	return _arena


func test_create_builds_members_and_registers_current() -> void:
	var a := _make(false)
	check(a.entities != null and a.entities.get_parent() == a, "entities root")
	check(a.camera != null and a.camera.get_parent() == a, "camera rig")
	check(a.camera.camera != null, "camera node")
	check(a.sun != null and a.sun.shadow_enabled, "sun with shadows")
	check(a.world_environment != null and a.world_environment.environment != null, "environment")
	check(a.ground != null, "ground")
	tree.root.add_child(a)
	check(Arena.current == a, "current set on enter")
	tree.root.remove_child(a)
	check(Arena.current == null, "current cleared on exit")


func test_walls_enclose_the_bounds() -> void:
	var a := _make()
	check_eq(a.walls.collision_layer, 1, "world layer")
	var shapes := 0
	for c in a.walls.get_children():
		if c is CollisionShape3D:
			shapes += 1
	check_eq(shapes, 4, "four wall boxes")
	var b := a.get_bounds()
	var boxes := Arena.wall_boxes()
	var north := boxes[0]
	var south := boxes[1]
	var west := boxes[2]
	var east := boxes[3]
	check_near(north.end.z, b.position.y, 0.0001, "north inner face")
	check_near(south.position.z, b.end.y, 0.0001, "south inner face")
	check_near(west.end.x, b.position.x, 0.0001, "west inner face")
	check_near(east.position.x, b.end.x, 0.0001, "east inner face")
	for box in boxes:
		check(box.position.y < 0.0 and box.end.y >= 6.0, "tall enough that nothing escapes")
	# Corners are covered: a point just outside each corner is inside some box.
	for corner in [Vector3(b.position.x - 0.5, 1, b.position.y - 0.5), Vector3(b.end.x + 0.5, 1, b.end.y + 0.5)]:
		var covered := false
		for box in boxes:
			covered = covered or box.has_point(corner)
		check(covered, "corner %s covered" % corner)
	# Nothing inside the playable area is blocked.
	for box in boxes:
		check(not box.has_point(Vector3(0, 1, 0)), "centre is free")


func test_spawn_points() -> void:
	var a := _make()
	for count in range(1, 5):
		var pts := a.get_player_spawn_points(count)
		check_eq(pts.size(), count, "one point per player")
		for i in pts.size():
			check(a.is_inside(pts[i], 1.0), "spawn inside the arena")
			check(pts[i].length() <= 2.5, "near the centre")
			for j in range(i + 1, pts.size()):
				check(pts[i].distance_to(pts[j]) >= 1.5, "spread out")
	check(a.get_player_spawn_points(0).is_empty(), "no players -> no points")
	var two := Arena.spawn_points(2)
	check(two[0].x < 0.0 and two[1].x > 0.0, "two players side by side")


func test_random_and_clamp_points() -> void:
	var a := _make(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 200:
		var p := a.random_point(rng, 1.5)
		check(a.is_inside(p, 1.49), "random point respects the margin")
		check_eq(p.y, 0.0, "on the ground")
	var c := a.clamp_point(Vector3(100, 2, -100), 0.5)
	check_near(c.x, Arena.SIZE.x / 2.0 - 0.5, 0.0001, "clamped x")
	check_near(c.z, -Arena.SIZE.y / 2.0 + 0.5, 0.0001, "clamped z")
	check_eq(c.y, 2.0, "keeps height")
	check(a.get_view_rect().encloses(a.get_bounds()), "view rect contains the arena")
	check(a.get_decor_rect().encloses(a.get_view_rect()), "decoration covers the camera view")


func test_decor_keeps_the_view_clear() -> void:
	var a := _make(false)
	var b := a.get_bounds()
	var d := a.get_decor_rect()
	check(not ArenaDecor.tree_allowed(Vector2(0, 0), b, d), "no trees in the arena")
	check(not ArenaDecor.tree_allowed(Vector2(0, b.end.y + 3.0), b, d), "no tall trees right in front of the camera")
	check(not ArenaDecor.tree_allowed(Vector2(ArenaDecor.road_x(b.position.y - 10.0, b), b.position.y - 10.0), b, d), "road stays clear")
	check(ArenaDecor.tree_allowed(Vector2(b.end.x + 8.0, 0), b, d), "forest beside the arena")
	check(not ArenaDecor.tree_allowed(Vector2(d.end.x + 5.0, 0), b, d), "nothing beyond the decor rect")
	var forest := a.get_node_or_null("Decor/ForestNorth") as MeshInstance3D
	check(forest != null and forest.mesh.get_surface_count() == 1, "forest chunk built")


func test_entities_host_vfx() -> void:
	var a := _make()
	Vfx.hit_spark(Vector3(1, 0.5, 1), Color.WHITE)
	check_eq(a.entities.get_child_count(), 1, "vfx parented to the entities root")


func test_view_rect_shows_less_outside_towards_the_camera() -> void:
	var a := _make(false)
	var b := a.get_bounds()
	var v := a.get_view_rect()
	check_near(b.position.y - v.position.y, Arena.VIEW_MARGIN, 0.0001, "north margin")
	check_near(v.end.y - b.end.y, Arena.VIEW_MARGIN_SOUTH, 0.0001, "south margin")
	check_near(b.position.x - v.position.x, Arena.VIEW_MARGIN, 0.0001, "west margin")
	check(Arena.VIEW_MARGIN_SOUTH < Arena.VIEW_MARGIN, "near side margin is smaller")
	# A lone player at the south wall stays on screen with the camera clamped to the view rect.
	var at_wall: Array[Vector3] = [Vector3(0, 0, b.end.y - 0.5)]
	var f := CameraRig.compute_framing(at_wall, 16.0 / 9.0, v)
	var ext := CameraRig.ground_extents(f["distance"], 16.0 / 9.0)
	var target: Vector3 = f["target"]
	check(target.z + ext.z <= v.end.y + 0.001, "view stays inside the rect")
	check(target.z + ext.z >= at_wall[0].z + CameraRig.FRAME_MARGIN_BOTTOM - 0.001, "player keeps its bottom frame margin")
