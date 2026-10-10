extends TestCase
## CameraRig: framing math (pure static functions) and the follow / shake behaviour.

const ASPECT := 16.0 / 9.0


class FakePlayer extends Node3D:
	var alive := true

	func is_alive() -> bool:
		return alive


var _nodes: Array[Node] = []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


func _player(pos: Vector3, alive: bool = true) -> FakePlayer:
	var p := FakePlayer.new()
	p.alive = alive
	p.add_to_group(&"players")
	tree.root.add_child(p)
	p.global_position = pos
	_nodes.append(p)
	return p


func _rig() -> CameraRig:
	var rig := CameraRig.new()
	rig.view_rect = Rect2(-25, -19, 50, 38)
	tree.root.add_child(rig)
	_nodes.append(rig)
	return rig


func _visible(p: Vector3, target: Vector3, dist: float) -> bool:
	var ext := CameraRig.ground_extents(dist, ASPECT)
	return absf(p.x - target.x) <= ext.x + 0.001 and p.z >= target.z - ext.y - 0.001 \
		and p.z <= target.z + ext.z + 0.001


func test_ground_factors_match_pitch() -> void:
	check(CameraRig.north_factor() > CameraRig.south_factor(), "more ground visible up-screen than down-screen")
	check(CameraRig.south_factor() > 0.2, "south factor positive")
	check_near(CameraRig.width_factor(ASPECT), tan(deg_to_rad(20.0)) * ASPECT, 0.0001, "width factor")
	var ext := CameraRig.ground_extents(10.0, ASPECT)
	check_near(ext.y, 10.0 * CameraRig.north_factor(), 0.0001, "extents scale with distance")


func test_required_distance_grows_with_spread_and_is_clamped() -> void:
	var one: Array[Vector3] = [Vector3(3, 0, 2)]
	check_eq(CameraRig.required_distance(one, ASPECT), CameraRig.MIN_DISTANCE, "single player -> min distance")
	var close: Array[Vector3] = [Vector3(-2, 0, 0), Vector3(2, 0, 0)]
	var wide: Array[Vector3] = [Vector3(-12, 0, 0), Vector3(12, 0, 0)]
	var deep: Array[Vector3] = [Vector3(0, 0, -9), Vector3(0, 0, 9)]
	check(CameraRig.required_distance(wide, ASPECT) > CameraRig.required_distance(close, ASPECT), "spread zooms out")
	check(CameraRig.required_distance(deep, ASPECT) > CameraRig.MIN_DISTANCE, "vertical spread zooms out")
	var huge: Array[Vector3] = [Vector3(-200, 0, 0), Vector3(200, 0, 0)]
	check_eq(CameraRig.required_distance(huge, ASPECT), CameraRig.MAX_DISTANCE, "clamped to max distance")


func test_framing_keeps_every_player_on_screen() -> void:
	var layouts: Array = [
		[Vector3(0, 0, 0)],
		[Vector3(-14, 0, -8), Vector3(14, 0, 8)],
		[Vector3(-16, 0, 10), Vector3(-15, 0, 10.5), Vector3(-16.5, 0, 9)],
		[Vector3(16, 0, -10), Vector3(-10, 0, 10), Vector3(0, 0, 0), Vector3(5, 0, 5)],
	]
	var rect := Rect2(-25, -19, 50, 38)
	for layout in layouts:
		var pts: Array[Vector3] = []
		pts.assign(layout)
		var f := CameraRig.compute_framing(pts, ASPECT, rect)
		var target: Vector3 = f["target"]
		var dist: float = f["distance"]
		check(dist >= CameraRig.MIN_DISTANCE and dist <= CameraRig.MAX_DISTANCE, "distance in range")
		for p in pts:
			check(_visible(p, target, dist), "player %s visible (target %s, d %.1f)" % [p, target, dist])


func test_framing_follows_centroid_when_unconstrained() -> void:
	var pts: Array[Vector3] = [Vector3(1, 0, 1), Vector3(3, 0, -1)]
	var f := CameraRig.compute_framing(pts, ASPECT)
	check_near((f["target"] as Vector3).x, 2.0, 0.001, "centroid x")
	check_near((f["target"] as Vector3).z, 0.0, 0.001, "centroid z")


func test_clamp_keeps_view_inside_rect() -> void:
	var rect := Rect2(-25, -19, 50, 38)
	var dist := 24.0
	var ext := CameraRig.ground_extents(dist, ASPECT)
	var t := CameraRig.clamp_to_view(Vector3(40, 0, -40), dist, ASPECT, rect)
	check_near(t.x + ext.x, rect.end.x, 0.001, "right edge on the rect")
	check_near(t.z - ext.y, rect.position.y, 0.001, "top edge on the rect")
	var t2 := CameraRig.clamp_to_view(Vector3(-40, 0, 40), dist, ASPECT, rect)
	check_near(t2.x - ext.x, rect.position.x, 0.001, "left edge on the rect")
	check_near(t2.z + ext.z, rect.end.y, 0.001, "bottom edge on the rect")
	var inside := CameraRig.clamp_to_view(Vector3(1, 0, 1), dist, ASPECT, rect)
	check(inside.is_equal_approx(Vector3(1, 0, 1)), "no clamp when the view fits")
	var tiny := CameraRig.clamp_to_view(Vector3(5, 0, 5), dist, ASPECT, Rect2(-1, -1, 2, 2))
	check_near(tiny.x, 0.0, 0.001, "rect smaller than the view -> centred")


func test_rig_snaps_to_living_players_only() -> void:
	_player(Vector3(4, 0, 2))
	_player(Vector3(6, 0, 2))
	_player(Vector3(-20, 0, -15), false)
	var rig := _rig()
	rig.snap()
	check_near(rig.focus.x, 5.0, 0.01, "focus between living players")
	check_near(rig.distance, CameraRig.MIN_DISTANCE, 0.01, "close together -> min distance")
	var pitch := -rig.camera.rotation.x
	check_near(rad_to_deg(pitch), CameraRig.PITCH_DEG, 0.01, "camera pitch")
	check_near(rig.camera.fov, CameraRig.FOV, 0.01, "fov")
	check(rig.camera.position.y > 0.0 and rig.camera.position.z > 0.0, "camera up and behind (screen-up is -Z)")


func test_rig_uses_downed_players_when_everyone_is_down() -> void:
	_player(Vector3(-3, 0, 0), false)
	_player(Vector3(-5, 0, 0), false)
	var rig := _rig()
	rig.snap()
	check_near(rig.focus.x, -4.0, 0.01, "frames the ghosts")


func test_rig_follows_smoothly() -> void:
	var p := _player(Vector3(0, 0, 0))
	var rig := _rig()
	rig.snap()
	p.global_position = Vector3(8, 0, 0)
	rig._process(1.0 / 60.0)
	check(rig.focus.x > 0.0 and rig.focus.x < 2.0, "moves a little per frame (%.2f)" % rig.focus.x)
	for i in 240:
		rig._process(1.0 / 60.0)
	check_near(rig.focus.x, 8.0, 0.05, "catches up")


func test_shake_decays() -> void:
	_player(Vector3.ZERO)
	var rig := _rig()
	rig.snap()
	rig.shake(0.6)
	rig.shake(0.6)
	check_near(rig.get_trauma(), 1.0, 0.0001, "trauma clamps at 1")
	rig._process(0.05)
	check(absf(rig.camera.h_offset) + absf(rig.camera.v_offset) > 0.0, "camera offset while shaking")
	for i in 120:
		rig._process(1.0 / 60.0)
	check_eq(rig.get_trauma(), 0.0, "trauma decays")
	check_near(rig.camera.h_offset, 0.0, 0.0001, "offset gone")
	rig.shake(0.5)
	rig.snap()
	check_eq(rig.get_trauma(), 0.0, "snap clears shake")


func test_team_at_max_spread_still_fits_on_screen() -> void:
	var spread := CameraRig.max_spread(ASPECT)
	check(spread.x > 0.0 and spread.y > 0.0, "positive spread")
	var pts: Array[Vector3] = [Vector3(-spread.x * 0.5, 0, -spread.y * 0.5), Vector3(spread.x * 0.5, 0, spread.y * 0.5)]
	var f := CameraRig.compute_framing(pts, ASPECT)
	check_near(f["distance"], CameraRig.MAX_DISTANCE, 0.01, "needs the max zoom")
	for p in pts:
		check(_visible(p, f["target"], f["distance"]), "corner player %s visible" % p)
	# The MVP arena never needs the invisible screen wall: the whole team always fits.
	check(spread.x >= Arena.SIZE.x and spread.y >= Arena.SIZE.y, "arena %s fits in %s" % [Arena.SIZE, spread])


func test_walk_rect_keeps_runaways_on_screen() -> void:
	check(CameraRig.walk_rect_for([], ASPECT).size.x > 1000.0, "alone -> unbounded")
	var spread := CameraRig.max_spread(ASPECT)
	var others: Array[Vector3] = [Vector3(-5, 0, 2), Vector3(-3, 0, -1)]
	var r := CameraRig.walk_rect_for(others, ASPECT)
	check(r.has_point(Vector2(-4, 0)), "can walk among the team")
	check_near(r.end.x, -5.0 + spread.x, 0.001, "east limit = westmost teammate + max spread")
	check_near(r.position.y, 2.0 - spread.y, 0.001, "north limit = southmost teammate - max spread")
	# A player running far east is stopped at the limit and the camera still frames everyone.
	var runaway := Vector3(200, 0, 0)
	var stopped := Vector3(clampf(runaway.x, r.position.x, r.end.x), 0, clampf(runaway.z, r.position.y, r.end.y))
	var team: Array[Vector3] = [others[0], others[1], stopped]
	var f := CameraRig.compute_framing(team, ASPECT)
	for p in team:
		check(_visible(p, f["target"], f["distance"]), "player %s still visible" % p)
	# Teammates already too far apart collapse the rect onto their middle.
	var apart: Array[Vector3] = [Vector3(-200, 0, 0), Vector3(200, 0, 0)]
	var squeezed := CameraRig.walk_rect_for(apart, ASPECT)
	check_near(squeezed.size.x, 0.0, 0.001, "no room left")
	check_near(squeezed.position.x, 0.0, 0.001, "pulled to the middle")


func test_view_walk_rect_lies_inside_the_view() -> void:
	var center := Vector3(3, 0, -2)
	var dist := 26.0
	var r := CameraRig.walk_rect(center, dist, ASPECT, 1.0)
	check(r.size.x > 10.0 and r.size.y > 5.0, "usable area")
	var ext := CameraRig.ground_extents(dist, ASPECT)
	for corner: Vector2 in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
		var dz := corner.y - center.z
		check(dz >= -ext.y and dz <= ext.z, "corner %s inside the visible depth" % corner)
		check(absf(corner.x - center.x) <= CameraRig.half_width_at(dist, ASPECT, dz), "corner %s inside the visible width" % corner)
	check(r.position.y - (center.z - ext.y) >= CameraRig.WALK_HEAD_ROOM, "head room at the top edge")


func test_rig_walk_rect_for_players_and_ghosts() -> void:
	var a := _player(Vector3(0, 0, 0))
	var b := _player(Vector3(4, 0, 0))
	var ghost := _player(Vector3(2, 0, 3), false)
	var rig := _rig()
	rig.snap()
	# Headless viewports may not be 16:9 – use the rig's own aspect.
	var spread := CameraRig.max_spread(rig._aspect())
	var ra := rig.get_walk_rect(a)
	check_near(ra.end.x, 4.0 + spread.x, 0.001, "living player limited by the other living one")
	check_near(ra.position.x, 4.0 - spread.x, 0.001, "both ways")
	check(not rig.get_walk_rect(b).has_point(Vector2(-spread.x - 1.0, 0)), "b cannot run off the far side")
	var rg := rig.get_walk_rect(ghost)
	check(rg.has_point(Vector2(2, 3)), "ghost may stay where it is")
	check(rg.size.x < spread.x, "ghost is kept inside the current (closer) view")
