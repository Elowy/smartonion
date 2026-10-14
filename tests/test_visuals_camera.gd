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
	check(rg.is_equal_approx(rig.get_safe_ground_rect()), "ghost kept out from under the HUD")


## The HUD (unit frames, wave / timer plaque, XP strip) must never cover a hero: every
## framed player keeps the per-side margins – more room at the top, where the plaque sits.
func test_framing_keeps_heroes_out_from_under_the_hud() -> void:
	check(CameraRig.FRAME_MARGIN_TOP > CameraRig.FRAME_MARGIN_BOTTOM, "top margin is the biggest")
	check(CameraRig.FRAME_MARGIN_BOTTOM > CameraRig.FRAME_MARGIN, "bottom margin above the sides")
	var layouts: Array = [
		[Vector3(0, 0, 0)],
		[Vector3(-6, 0, -4), Vector3(6, 0, 4)],
		[Vector3(-12, 0, -8), Vector3(12, 0, 8), Vector3(0, 0, 0)],
		[Vector3(3, 0, -10), Vector3(-3, 0, 10)],
		[Vector3(-16, 0, -10), Vector3(16, 0, 10), Vector3(-16, 0, 10), Vector3(16, 0, -10)],
	]
	var arena_view := Rect2(-25, -19, 50, 38)
	for layout in layouts:
		var pts: Array[Vector3] = []
		pts.assign(layout)
		for rect: Rect2 in [Rect2(), arena_view]:
			var f := CameraRig.compute_framing(pts, ASPECT, rect)
			var target: Vector3 = f["target"]
			var dist: float = f["distance"]
			var ext := CameraRig.ground_extents(dist, ASPECT)
			for p in pts:
				var top := p.z - (target.z - ext.y)
				var bottom := (target.z + ext.z) - p.z
				var side := ext.x - absf(p.x - target.x)
				check(top >= CameraRig.top_margin(dist) - 0.001, "%s: %.2f m below the top edge (d %.1f)" % [p, top, dist])
				check(bottom >= CameraRig.FRAME_MARGIN_BOTTOM - 0.001, "%s: %.2f m above the bottom edge" % [p, bottom])
				check(side >= CameraRig.FRAME_MARGIN - 0.001, "%s: %.2f m from the side edge" % [p, side])


func test_top_margin_grows_with_distance_and_is_capped() -> void:
	check_near(CameraRig.top_margin(CameraRig.MIN_DISTANCE), CameraRig.FRAME_MARGIN_TOP, 0.0001, "base at min distance")
	check_near(CameraRig.top_margin(10.0), CameraRig.FRAME_MARGIN_TOP, 0.0001, "never below the base")
	check(CameraRig.top_margin(25.0) > CameraRig.top_margin(21.0), "grows when zoomed out (the plaque covers more ground)")
	check_near(CameraRig.top_margin(CameraRig.MAX_DISTANCE), CameraRig.FRAME_MARGIN_TOP_MAX, 0.0001, "capped")
	# depth_distance solves k * d = spread + top_margin(d) + bottom exactly (between the clamps).
	var k := CameraRig.north_factor() + CameraRig.south_factor()
	for spread: float in [8.0, 12.0, 16.0, 20.0]:
		var d := CameraRig.depth_distance(spread)
		if d > CameraRig.MIN_DISTANCE and d < CameraRig.MAX_DISTANCE:
			check_near(k * d, spread + CameraRig.top_margin(d) + CameraRig.FRAME_MARGIN_BOTTOM, 0.001,
				"spread %.0f fits exactly at d %.2f" % [spread, d])
	check(CameraRig.depth_distance(16.0) > CameraRig.depth_distance(12.0), "monotonic")


func test_safe_ground_rect_lies_inside_the_view_outside_the_hud() -> void:
	var center := Vector3(2, 0, -1)
	for dist: float in [CameraRig.MIN_DISTANCE, 26.0, CameraRig.MAX_DISTANCE]:
		var r := CameraRig.safe_ground_rect(center, dist, ASPECT)
		check(r.has_area(), "usable area at d %.1f" % dist)
		var ext := CameraRig.ground_extents(dist, ASPECT)
		check_near(r.position.y - (center.z - ext.y), CameraRig.top_margin(dist), 0.001, "top HUD margin")
		check_near((center.z + ext.z) - r.end.y, CameraRig.FRAME_MARGIN_BOTTOM, 0.001, "bottom HUD margin")
		for corner: Vector2 in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
			var dz := corner.y - center.z
			check(absf(corner.x - center.x) <= CameraRig.half_width_at(dist, ASPECT, dz) - CameraRig.FRAME_MARGIN + 0.001,
				"corner %s on screen, clear of the side edge" % corner)
	var rig := _rig()
	_player(Vector3(3, 0, 1))
	rig.snap()
	var live := rig.get_safe_ground_rect()
	check(live.has_point(Vector2(3, 1)), "the framed hero stands inside the safe rect")


# --- Spirit Healer (GDD 1) --------------------------------------------------------

func test_framing_points_add_the_spirit_healer_only_while_a_ghost_exists() -> void:
	var living: Array[Vector3] = [Vector3(4, 0, 2), Vector3(6, 0, 2)]
	var none: Array[Vector3] = []
	var ghosts: Array[Vector3] = [Vector3(-3, 0, 5)]
	var healer: Array[Vector3] = [Vector3.ZERO]
	check_eq(CameraRig.framing_points(living, none, healer), living, "nobody down: just the living")
	var with_ghost := CameraRig.framing_points(living, ghosts, healer)
	check_eq(with_ghost.size(), 3, "the living + the healer")
	check(Vector3.ZERO in with_ghost, "the healer is framed")
	check(not ghosts[0] in with_ghost, "the ghost itself is not")
	check_eq(CameraRig.framing_points(living, ghosts, none), living, "no healer: just the living")
	check_eq(CameraRig.framing_points(none, ghosts, healer), ghosts, "everybody down: the ghosts (old fallback)")


func test_ghost_walk_rect_reaches_the_healer() -> void:
	var safe := Rect2(2, -3, 10, 6)
	var none: Array[Vector3] = []
	check(CameraRig.ghost_walk_rect(safe, none).is_equal_approx(safe), "no healer: the safe rect")
	var inside: Array[Vector3] = [Vector3(5, 0, 0)]
	check(CameraRig.ghost_walk_rect(safe, inside).is_equal_approx(safe), "a healer on screen changes nothing")
	var beside: Array[Vector3] = [Vector3(-1, 0, 4)]
	var r := CameraRig.ghost_walk_rect(safe, beside)
	check(r.encloses(safe), "still the whole safe rect")
	check(r.position.x <= -1.0 and r.end.y >= 4.0, "the healer point is within reach: %s" % r)
	check_near(r.end.x, safe.end.x, 0.0001, "grown only towards the healer")
	check_near(r.position.y, safe.position.y, 0.0001, "grown only towards the healer")


func test_rig_frames_the_spirit_healer_while_a_ghost_exists() -> void:
	var arena := Arena.create()
	_nodes.append(arena)
	tree.root.add_child(arena)
	var rig := arena.camera
	var h := arena.spirit_healer.global_position
	var hero := _player(Vector3(15, 0, 9))
	rig.snap()
	check(not h in rig._player_points(), "nobody down: the healer is not framed")
	var ghost := _player(Vector3(14, 0, 7), false)
	check(h in rig._player_points(), "a ghost exists: the healer is framed")
	rig.snap()
	var aspect := rig._aspect()
	var ext := CameraRig.ground_extents(rig.distance, aspect)
	for p: Vector3 in [h, hero.global_position]:
		check(p.z - (rig.focus.z - ext.y) >= CameraRig.top_margin(rig.distance) - 0.001, "%s below the top margin" % p)
		check((rig.focus.z + ext.z) - p.z >= CameraRig.FRAME_MARGIN_BOTTOM - 0.001, "%s above the bottom margin" % p)
		check(ext.x - absf(p.x - rig.focus.x) >= CameraRig.FRAME_MARGIN - 0.001, "%s clear of the sides" % p)
	var gr := rig.get_walk_rect(ghost)
	check(gr.position.x <= h.x and gr.end.x >= h.x and gr.position.y <= h.z and gr.end.y >= h.z,
		"the ghost may walk to the healer: %s" % gr)
	var spread := CameraRig.max_spread(aspect)
	var hr := rig.get_walk_rect(hero)
	check_near(hr.position.x, h.x - spread.x, 0.001, "the living hero keeps the healer within one screen")
	check_near(hr.end.x, h.x + spread.x, 0.001, "both ways")
	ghost.alive = true
	check(not h in rig._player_points(), "revived: the healer is no longer framed")


# --- Loot Goblin (GDD 8, M5) ----------------------------------------------------------

func _arena_in_tree() -> Arena:
	var arena := Arena.create()
	_nodes.append(arena)
	tree.root.add_child(arena)
	return arena


func _goblin_in(arena: Arena, pos: Vector3) -> LootGoblin:
	var g := LootGoblin.create(LootGoblin.goblin_data(), 5)
	arena.entities.add_child(g)
	g.global_position = pos
	return g


## [param p] lies inside the screen margins of a camera on [param focus] at [param dist].
func _framed(p: Vector3, focus: Vector3, dist: float, aspect: float) -> bool:
	var ext := CameraRig.ground_extents(dist, aspect)
	return p.z - (focus.z - ext.y) >= CameraRig.top_margin(dist) - 0.001 \
		and (focus.z + ext.z) - p.z >= CameraRig.FRAME_MARGIN_BOTTOM - 0.001 \
		and ext.x - absf(p.x - focus.x) >= CameraRig.FRAME_MARGIN - 0.001


## The goblin's name tag on screen (px): bottom-centre anchored at the label.
func _tag_rect(g: LootGoblin) -> Rect2:
	var cam := g.get_viewport().get_camera_3d()
	var size := g.tag_screen_size(cam.get_viewport().get_visible_rect().size.y, cam.fov)
	var s := cam.unproject_position(g.label.global_position)
	return Rect2(s.x - size.x * 0.5, s.y - size.y, size.x, size.y)


func test_rig_frames_a_living_loot_goblin_and_its_tag() -> void:
	var arena := _arena_in_tree()
	var rig := arena.camera
	var hero := _player(Vector3(-6, 0, 4))
	var g := _goblin_in(arena, Vector3(10, 0, -8))
	rig.snap()
	var aspect := rig._aspect()
	check(_framed(g.global_position, rig.focus, rig.distance, aspect),
		"the goblin is framed (focus %s, d %.1f)" % [rig.focus, rig.distance])
	check(_framed(hero.global_position, rig.focus, rig.distance, aspect), "the hero too")
	check(rig.distance > CameraRig.MIN_DISTANCE and rig.distance <= CameraRig.MAX_DISTANCE,
		"zoomed out for it, at most MAX_DISTANCE: %.1f" % rig.distance)
	g.keep_tag_on_screen()
	check(g.label.position.is_equal_approx(g.tag_home()), "framed: the tag stays above its head")
	var view := Rect2(Vector2.ZERO, rig.get_viewport().get_visible_rect().size)
	check(view.encloses(_tag_rect(g)), "the whole name tag is on screen: %s in %s" % [_tag_rect(g), view])
	check(rig.get_walk_rect(hero).size.x > 1.0e5, "the goblin never limits where the hero may walk")


func test_rig_frames_only_living_goblins_while_a_hero_stands() -> void:
	var arena := _arena_in_tree()
	var rig := arena.camera
	var hero := _player(Vector3(0, 0, 0))
	var g := _goblin_in(arena, Vector3(8, 0, 3))
	check(g.global_position in rig._goblin_points(), "a living goblin is framed")
	g.portal_left = 0.5
	check(g.is_opening_portal() and g.global_position in rig._goblin_points(),
		"still framed while its portal opens (it can be killed until it is gone)")
	g._escaped = true
	check(rig._goblin_points().is_empty(), "escaped: no longer framed")
	g._escaped = false
	g.hp = 0.0
	check(rig._goblin_points().is_empty(), "dead: no longer framed")
	g.hp = g.max_hp
	hero.alive = false
	check(rig._goblin_points().is_empty(), "nobody stands: the ghosts' framing stays as it was")
	check(not g.global_position in rig._player_points(), "and the goblin is never a hard framing point")


func _boss_in(arena: Arena, pos: Vector3) -> Boss:
	var b := Boss.create(Db.get_boss(&"lich_commander_morvain"), 10)
	arena.entities.add_child(b)
	b.global_position = pos
	return b


func test_rig_frames_a_living_boss_feet_and_height() -> void:
	var arena := _arena_in_tree()
	var rig := arena.camera
	var hero := _player(Vector3(-6, 0, 4))
	var b := _boss_in(arena, Vector3(10, 0, -8))
	var raised := b.global_position + Vector3(0.0, 0.0, -b.model.head_height * CameraRig.BOSS_HEIGHT_SHARE)
	var pts := rig._goblin_points()
	check_eq(pts.size(), 2, "a living boss adds its feet and one raised point")
	check(b.global_position in pts, "the feet are framed")
	check(raised in pts, "so is the point up its height (screen-up is -Z)")
	check(raised.z < b.global_position.z, "the raised point lies further up the screen")
	rig.snap()
	var aspect := rig._aspect()
	for p: Vector3 in [b.global_position, raised, hero.global_position]:
		check(_framed(p, rig.focus, rig.distance, aspect),
			"%s is framed (focus %s, d %.1f)" % [p, rig.focus, rig.distance])
	check(not b.global_position in rig._player_points(), "the boss is never a hard framing point")
	check(rig.get_walk_rect(hero).size.x > 1.0e5, "the boss never limits where the hero may walk")


func test_rig_frames_no_dead_or_freed_boss_and_none_without_a_standing_hero() -> void:
	var arena := _arena_in_tree()
	var rig := arena.camera
	var hero := _player(Vector3(0, 0, 0))
	var b := _boss_in(arena, Vector3(8, 0, 3))
	check_eq(rig._goblin_points().size(), 2, "alive: framed")
	b.hp = 0.0
	check(rig._goblin_points().is_empty(), "dead (hp 0): no longer framed")
	b.hp = b.max_hp
	check_eq(rig._goblin_points().size(), 2, "alive again: framed")
	b.queue_free()
	check(rig._goblin_points().is_empty(), "queued for deletion: no longer framed")
	check(CameraRig.boss_points(tree.get_nodes_in_group(&"bosses")).is_empty(),
		"the static helper agrees: a queued boss adds nothing")
	b.free()
	check(rig._goblin_points().is_empty(), "freed: nothing left to frame")
	var b2 := _boss_in(arena, Vector3(8, 0, 3))
	hero.alive = false
	check(rig._goblin_points().is_empty(), "nobody stands: the ghosts' framing stays as it was")
	hero.alive = true
	check(b2.global_position in rig._goblin_points(), "a hero stands again: the boss is framed")


func test_compute_framing_leans_towards_extras_but_keeps_the_players() -> void:
	var aspect := 1.0
	var none: Array[Vector3] = []
	var pts: Array[Vector3] = [Vector3(-8, 0, 0), Vector3(-4, 0, 2)]
	var plain := CameraRig.compute_framing(pts, aspect)
	var same := CameraRig.compute_framing(pts, aspect, Rect2(), none)
	check((plain["target"] as Vector3).is_equal_approx(same["target"]) and is_equal_approx(plain["distance"], same["distance"]),
		"no extras: the old framing")
	var near: Array[Vector3] = [Vector3(6, 0, -4)]
	var f := CameraRig.compute_framing(pts, aspect, Rect2(), near)
	for p: Vector3 in [pts[0], pts[1], near[0]]:
		check(_framed(p, f["target"], f["distance"], aspect), "fits: %s framed" % p)
	var far: Array[Vector3] = [Vector3(30, 0, 0)]
	var lean := CameraRig.compute_framing(pts, aspect, Rect2(), far)
	check_near(lean["distance"], CameraRig.MAX_DISTANCE, 0.001, "zoomed all the way out")
	for p in pts:
		check(_framed(p, lean["target"], lean["distance"], aspect), "too far: the heroes still framed (%s)" % p)
	var ext := CameraRig.ground_extents(CameraRig.MAX_DISTANCE, aspect)
	check_near((lean["target"] as Vector3).x, -8.0 + ext.x - CameraRig.FRAME_MARGIN, 0.001,
		"leans towards the goblin as far as the leftmost hero allows")


func test_clamp_tag_keeps_the_tag_inside_the_view() -> void:
	var view := Vector2(1000, 600)
	var size := Vector2(200, 40)
	check_eq(LootGoblin.clamp_tag(Vector2(500, 300), size, view, 8.0), Vector2(500, 300), "inside: unchanged")
	check_eq(LootGoblin.clamp_tag(Vector2(950, 300), size, view, 8.0), Vector2(892, 300), "right edge")
	check_eq(LootGoblin.clamp_tag(Vector2(-300, 900), size, view, 8.0), Vector2(108, 592), "beyond the bottom left")
	check_eq(LootGoblin.clamp_tag(Vector2(500, 10), size, view, 8.0), Vector2(500, 48), "top: its height fits")


func test_goblin_tag_stays_on_screen_while_the_goblin_is_off_it() -> void:
	var arena := _arena_in_tree()
	var rig := arena.camera
	_player(Vector3(0, 0, 0))
	rig.snap()
	# Added after the snap: the camera has not moved to it yet.
	var g := _goblin_in(arena, Vector3(16, 0, 0))
	var cam := rig.camera
	var view := Rect2(Vector2.ZERO, rig.get_viewport().get_visible_rect().size)
	check(cam.unproject_position(g.global_position).x > view.end.x, "the goblin itself is off screen")
	g.keep_tag_on_screen()
	var r := _tag_rect(g)
	check(view.grow(-LootGoblin.TAG_SCREEN_PAD + 0.5).encloses(r), "the tag is on screen: %s in %s" % [r, view])
	check_near(r.end.x, view.end.x - LootGoblin.TAG_SCREEN_PAD, 1.0, "at the right edge, pointing the way")
	g.global_position = Vector3(1, 0, 0)
	g.keep_tag_on_screen()
	check(g.label.position.is_equal_approx(g.tag_home()), "back on screen: above its head again")
