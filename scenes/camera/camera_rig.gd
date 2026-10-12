class_name CameraRig
extends Node3D
## Top-down camera (~57 degree pitch, FOV 40) owned by the "visuals" module. Follows the
## centroid of the living players (group &"players", Player.is_alive()), zooms out with the
## players' spread so everyone stays on screen, and clamps so the view stays inside the
## decorated area around the arena (Arena.current.get_view_rect()). While anybody is a ghost
## it also frames the arena's Spirit Healer (Arena.current.spirit_healer), so the healer is
## always on screen and reachable for the ghost ([method framing_points]). A living Loot
## Goblin (group &"loot_goblins", not dead and not escaped – still framed while its portal
## opens, it can be killed until it is gone) is framed too, with its name tag, as a soft
## point ([method goblin_points], the extras of [method compute_framing]): the camera zooms
## out (at most MAX_DISTANCE) to show it, but the players always win – when the goblin does
## not fit with them (a narrow screen), the view only leans towards it, and it never limits
## where a player may walk ([method get_walk_rect]).
##
## The rig node sits at the look-at point on the ground; [member camera] is offset back and
## up along the pitch. Framing math is static (see [method compute_framing]) and unit tested.

const PITCH_DEG := 57.0
const FOV := 40.0
const MIN_DISTANCE := 19.5
const MAX_DISTANCE := 36.0
## Metres (ground) kept between the outermost players and the screen edge, per side: the HUD
## covers more at the top (unit frames + wave / timer plaque) and the bottom (unit frames +
## XP strip) than at the sides, so heroes never sit under it.
const FRAME_MARGIN := 3.2
const FRAME_MARGIN_BOTTOM := 3.6
## The top margin grows with the distance (the wave / timer plaque covers a fixed share of
## the screen, i.e. more ground when zoomed out; heads stick up into it too): FRAME_MARGIN_TOP
## at MIN_DISTANCE, + TOP_MARGIN_SLOPE per metre further out, at most FRAME_MARGIN_TOP_MAX
## (so the whole MVP arena still fits at MAX_DISTANCE). See [method top_margin].
const FRAME_MARGIN_TOP := 6.0
const TOP_MARGIN_SLOPE := 0.2
const FRAME_MARGIN_TOP_MAX := 7.4
const FOLLOW_SHARPNESS := 4.5
const ZOOM_SHARPNESS := 2.2
const SHAKE_DECAY := 1.8
## Max screen offset of the camera (metres at the focus plane) at full trauma.
const SHAKE_MAX_OFFSET := 0.55
const SHAKE_MAX_ROLL := 0.035
## The rig moves late in each rendered frame (after the bodies it follows); screen-space
## overlays that read the camera (the Loot Goblin's tag) run after it.
const PROCESS_PRIORITY := 100
## Extra room below the top screen edge in [method walk_rect] so a player's head (1.3 m)
## stays on screen: at the top edge the view ray is ~37 degrees steep.
const WALK_HEAD_ROOM := 1.8

var camera: Camera3D
## Current (smoothed) look-at point and distance.
var focus := Vector3.ZERO
var distance := 24.0
## Optional explicit view rectangle (XZ). Empty = use Arena.current.get_view_rect().
var view_rect := Rect2()

var _trauma := 0.0
var _shake_time := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "CameraRig"
	process_priority = PROCESS_PRIORITY
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = FOV
	camera.near = 0.5
	camera.far = 260.0
	add_child(camera)
	_rng.seed = 1234
	_apply()


func _ready() -> void:
	camera.make_current()
	snap()


## Jumps to the target framing immediately (run start).
func snap() -> void:
	var goal := _goal()
	if not goal.is_empty():
		focus = goal["target"]
		distance = goal["distance"]
	_trauma = 0.0
	_apply()


## Screen shake, [param strength] ~0.1 (hit) .. 1.0 (boss slam).
func shake(strength: float) -> void:
	_trauma = clampf(_trauma + maxf(strength, 0.0), 0.0, 1.0)


func get_trauma() -> float:
	return _trauma


## Shared screen, no split (GDD 13): the ground rectangle [param body] (a node in group
## &"players") may stand in so that nobody leaves the screen – once the camera cannot zoom
## out any further, the screen edge acts as an invisible wall. Players clamp their movement
## to it. A framed (living) player is limited by the spread of the other framed points
## ([method walk_rect_for]; the Spirit Healer counts while a ghost exists); a ghost that the
## camera does not follow is kept inside the current view and out from under the HUD
## ([method safe_ground_rect]), so it stays easy to find – but it may always walk to the
## Spirit Healer ([method ghost_walk_rect]).
func get_walk_rect(body: Node3D) -> Rect2:
	var living: Array[Node3D] = []
	var ghosts: Array[Node3D] = []
	_split_players(living, ghosts)
	var framed := living if not living.is_empty() else ghosts
	var anchors := _anchor_points(living, ghosts)
	if body in framed:
		var others: Array[Vector3] = []
		for n in framed:
			if n != body:
				others.append(n.global_position)
		others.append_array(anchors)
		return walk_rect_for(others, _aspect())
	return ghost_walk_rect(safe_ground_rect(focus, distance, _aspect()), anchors)


func _process(delta: float) -> void:
	var goal := _goal()
	if not goal.is_empty():
		focus = focus.lerp(goal["target"], 1.0 - exp(-FOLLOW_SHARPNESS * delta))
		distance = lerpf(distance, goal["distance"], 1.0 - exp(-ZOOM_SHARPNESS * delta))
	_shake_time += delta
	_trauma = maxf(0.0, _trauma - SHAKE_DECAY * delta)
	_apply()


func _apply() -> void:
	var p := deg_to_rad(PITCH_DEG)
	if is_inside_tree():
		global_position = focus
	else:
		position = focus
	camera.position = Vector3(0.0, distance * sin(p), distance * cos(p))
	var shake_amount := _trauma * _trauma
	var t := _shake_time * 31.0
	camera.h_offset = SHAKE_MAX_OFFSET * shake_amount * (sin(t * 1.13) * 0.6 + sin(t * 2.71 + 1.3) * 0.4)
	camera.v_offset = SHAKE_MAX_OFFSET * shake_amount * (sin(t * 1.37 + 2.1) * 0.6 + sin(t * 2.33) * 0.4)
	camera.rotation = Vector3(-p, 0.0, SHAKE_MAX_ROLL * shake_amount * sin(t * 0.91 + 0.7))


func _goal() -> Dictionary:
	if not is_inside_tree():
		return {}
	var points := _player_points()
	if points.is_empty():
		return {}
	var rect := view_rect
	if rect.size == Vector2.ZERO and Arena.current != null and is_instance_valid(Arena.current):
		rect = Arena.current.get_view_rect()
	return compute_framing(points, _aspect(), rect, _goblin_points())


func _aspect() -> float:
	var vp := get_viewport()
	if vp == null:
		return 16.0 / 9.0
	var size := vp.get_visible_rect().size
	return size.x / size.y if size.y > 0.0 else 16.0 / 9.0


## The ground points the camera frames ([method framing_points]): the living players, plus
## the Spirit Healer while somebody is a ghost; the ghosts when everybody is down.
func _player_points() -> Array[Vector3]:
	var living: Array[Node3D] = []
	var ghosts: Array[Node3D] = []
	_split_players(living, ghosts)
	return framing_points(_positions(living), _positions(ghosts), _anchor_points(living, ghosts))


## Sorts the players in the tree (group &"players") into [param living] and [param ghosts]
## (is_alive() false).
func _split_players(living: Array[Node3D], ghosts: Array[Node3D]) -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group(&"players"):
		var n := node as Node3D
		if n == null or not n.is_inside_tree():
			continue
		if not n.has_method(&"is_alive") or n.call(&"is_alive"):
			living.append(n)
		else:
			ghosts.append(n)


## Extra points framed with the living players: the Spirit Healer of Arena.current while
## somebody is a ghost and somebody else still stands (empty otherwise).
func _anchor_points(living: Array[Node3D], ghosts: Array[Node3D]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if living.is_empty() or ghosts.is_empty():
		return out
	var arena := Arena.current
	if arena == null or not is_instance_valid(arena):
		return out
	var healer := arena.spirit_healer
	if healer != null and is_instance_valid(healer) and healer.is_inside_tree():
		out.append(healer.global_position)
	return out


## The soft framing points of the tree's Loot Goblins ([method goblin_points]); empty while
## nobody stands (the ghosts' fallback framing stays as it was).
func _goblin_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not is_inside_tree():
		return out
	var goblins := get_tree().get_nodes_in_group(&"loot_goblins")
	if goblins.is_empty():
		return out
	var living: Array[Node3D] = []
	var ghosts: Array[Node3D] = []
	_split_players(living, ghosts)
	if living.is_empty():
		return out
	return goblin_points(goblins)


## Ground positions of the [param goblins] the camera frames: LootGoblins in the tree that
## are neither dead nor escaped (one whose portal is opening still counts – it can be killed
## until it is gone).
static func goblin_points(goblins: Array[Node]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for node in goblins:
		var g := node as LootGoblin
		if g == null or not g.is_inside_tree() or g.is_queued_for_deletion() or g.is_dead() \
				or g.has_escaped():
			continue
		out.append(g.global_position)
	return out


static func _positions(nodes: Array[Node3D]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for n in nodes:
		out.append(n.global_position)
	return out


# --- Framing math (static, unit tested) ---------------------------------------

## The points [method compute_framing] keeps on screen: the [param living] players' positions
## plus, while there are [param ghosts], the [param anchors] (the Spirit Healer – a ghost
## always sees it and can walk to it). With nobody alive: the ghosts (the old fallback).
static func framing_points(living: Array[Vector3], ghosts: Array[Vector3], anchors: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if living.is_empty():
		out.append_array(ghosts)
		return out
	out.append_array(living)
	if not ghosts.is_empty():
		out.append_array(anchors)
	return out


## Walk rectangle of a ghost: [param safe] (the visible ground outside the HUD) grown just
## enough to hold every [param anchors] point, so the framed Spirit Healer is always within
## reach (the straight way there stays inside).
static func ghost_walk_rect(safe: Rect2, anchors: Array[Vector3]) -> Rect2:
	var out := safe
	for a in anchors:
		out = out.expand(Vector2(a.x, a.z))
	return out


## Visible ground distance in front of (north of) the focus point per metre of distance.
static func north_factor() -> float:
	var p := deg_to_rad(PITCH_DEG)
	var half := deg_to_rad(FOV) * 0.5
	return sin(p) / tan(p - half) - cos(p)


## Visible ground distance behind (south of) the focus point per metre of distance.
static func south_factor() -> float:
	var p := deg_to_rad(PITCH_DEG)
	var half := deg_to_rad(FOV) * 0.5
	return cos(p) - sin(p) / tan(p + half)


## Half of the visible ground width at the focus depth per metre of distance.
static func width_factor(aspect: float) -> float:
	return tan(deg_to_rad(FOV) * 0.5) * aspect


## Visible ground extents around the focus at [param dist]: x = half width, y = north
## (towards -Z), z = south (towards +Z).
static func ground_extents(dist: float, aspect: float) -> Vector3:
	return Vector3(dist * width_factor(aspect), dist * north_factor(), dist * south_factor())


## Visible ground half-width at [param dz] metres south (+Z) of the focus (perspective:
## the near / bottom part of the screen shows less ground than the far / top part).
static func half_width_at(dist: float, aspect: float, dz: float) -> float:
	return width_factor(aspect) * (dist - dz * cos(deg_to_rad(PITCH_DEG)))


## Ground metres kept free between the northmost player and the top screen edge at
## [param dist] (see FRAME_MARGIN_TOP).
static func top_margin(dist: float) -> float:
	return minf(FRAME_MARGIN_TOP + TOP_MARGIN_SLOPE * maxf(0.0, dist - MIN_DISTANCE), FRAME_MARGIN_TOP_MAX)


## Largest player spread (x = across the screen, y = along Z) that [method compute_framing]
## can still fit on screen at MAX_DISTANCE with the frame margins.
static func max_spread(aspect: float) -> Vector2:
	var ext := ground_extents(MAX_DISTANCE, aspect)
	return Vector2(2.0 * (ext.x - FRAME_MARGIN), ext.y + ext.z - top_margin(MAX_DISTANCE) - FRAME_MARGIN_BOTTOM)


## The part of the ground a camera focused on [param center] at [param dist] shows outside
## the HUD (frame margins on every side; the narrow bottom-edge width for the sides). Spawn
## telegraphs prefer it so they are never off-screen or under the HUD.
static func safe_ground_rect(center: Vector3, dist: float, aspect: float) -> Rect2:
	var north := dist * north_factor()
	var south := dist * south_factor()
	var half_w := half_width_at(dist, aspect, south)
	var x0 := center.x - half_w + FRAME_MARGIN
	var x1 := center.x + half_w - FRAME_MARGIN
	var z0 := center.z - north + top_margin(dist)
	var z1 := center.z + south - FRAME_MARGIN_BOTTOM
	return Rect2(x0, z0, maxf(x1 - x0, 0.0), maxf(z1 - z0, 0.0))


## [method safe_ground_rect] of the current (smoothed) view.
func get_safe_ground_rect() -> Rect2:
	return safe_ground_rect(focus, distance, _aspect())


## Where a framed player may stand so the whole team still fits on one screen together
## with [param others] (the other framed players' positions). Unbounded without others.
static func walk_rect_for(others: Array[Vector3], aspect: float) -> Rect2:
	if others.is_empty():
		return Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in others:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var spread := max_spread(aspect)
	var x0 := hi.x - spread.x
	var x1 := lo.x + spread.x
	var z0 := hi.y - spread.y
	var z1 := lo.y + spread.y
	if x0 > x1:
		x0 = (lo.x + hi.x) * 0.5
		x1 = x0
	if z0 > z1:
		z0 = (lo.y + hi.y) * 0.5
		z1 = z0
	return Rect2(x0, z0, x1 - x0, z1 - z0)


## Conservative walkable rectangle (XZ) inside the view of a camera focused on
## [param center] at [param dist]: the narrow bottom-edge width is used for the sides, and
## the top edge keeps [constant WALK_HEAD_ROOM] extra. Empty when the margins do not fit.
static func walk_rect(center: Vector3, dist: float, aspect: float, margin: float = 1.0) -> Rect2:
	var north := dist * north_factor()
	var south := dist * south_factor()
	var half_w := half_width_at(dist, aspect, south)
	var x0 := center.x - half_w + margin
	var x1 := center.x + half_w - margin
	var z0 := center.z - north + margin + WALK_HEAD_ROOM
	var z1 := center.z + south - margin
	return Rect2(x0, z0, maxf(x1 - x0, 0.0), maxf(z1 - z0, 0.0))


## Distance needed to keep all [param points] on screen with the frame margins
## (FRAME_MARGIN at the sides, [method top_margin] / FRAME_MARGIN_BOTTOM).
static func required_distance(points: Array[Vector3], aspect: float) -> float:
	if points.is_empty():
		return MIN_DISTANCE
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var dx := ((hi.x - lo.x) * 0.5 + FRAME_MARGIN) / width_factor(aspect)
	var dz := depth_distance(hi.y - lo.y)
	return clampf(maxf(dx, dz), MIN_DISTANCE, MAX_DISTANCE)


## Smallest distance whose visible depth holds [param spread_z] (metres along Z) plus the
## top ([method top_margin], which grows with the distance) and bottom margins.
static func depth_distance(spread_z: float) -> float:
	var k := north_factor() + south_factor()
	var d := (spread_z + FRAME_MARGIN_TOP + FRAME_MARGIN_BOTTOM) / k
	if d <= MIN_DISTANCE:
		return d
	# Sloped part: k * d = spread + FRAME_MARGIN_TOP + slope * (d - MIN) + bottom.
	d = (spread_z + FRAME_MARGIN_TOP - TOP_MARGIN_SLOPE * MIN_DISTANCE + FRAME_MARGIN_BOTTOM) / (k - TOP_MARGIN_SLOPE)
	if top_margin(d) < FRAME_MARGIN_TOP_MAX:
		return d
	return (spread_z + FRAME_MARGIN_TOP_MAX + FRAME_MARGIN_BOTTOM) / k


## Moves [param target] so the visible ground stays inside [param rect] (XZ) when possible.
static func clamp_to_view(target: Vector3, dist: float, aspect: float, rect: Rect2) -> Vector3:
	if rect.size == Vector2.ZERO:
		return target
	var ext := ground_extents(dist, aspect)
	var out := target
	var lo_x := rect.position.x + ext.x
	var hi_x := rect.end.x - ext.x
	out.x = clampf(out.x, lo_x, hi_x) if lo_x <= hi_x else rect.get_center().x
	var lo_z := rect.position.y + ext.y
	var hi_z := rect.end.y - ext.z
	out.z = clampf(out.z, lo_z, hi_z) if lo_z <= hi_z else (lo_z + hi_z) * 0.5
	return out


## Target framing for a set of player positions: {target: Vector3, distance: float}.
## Follows the centroid, respects the view rect, and finally guarantees (within
## MAX_DISTANCE) that every player stays inside the screen margins (so out from under the
## HUD: [method top_margin] / FRAME_MARGIN_BOTTOM / FRAME_MARGIN).
## [param extras] (the Loot Goblins, [method goblin_points]) are framed the same way when
## they fit together with [param points] – they count for the zoom and the centroid – but
## [param points] keep the guarantee: when everything does not fit, the view leans as far
## towards the extras as the points allow.
static func compute_framing(points: Array[Vector3], aspect: float, rect: Rect2 = Rect2(),
		extras: Array[Vector3] = []) -> Dictionary:
	if points.is_empty():
		return {"target": Vector3.ZERO, "distance": MIN_DISTANCE}
	var framed := points
	if not extras.is_empty():
		framed = points.duplicate()
		framed.append_array(extras)
	var centroid := Vector3.ZERO
	for p in framed:
		centroid += p
	centroid /= float(framed.size())
	centroid.y = 0.0
	var dist := required_distance(framed, aspect)
	var target := clamp_to_view(centroid, dist, aspect, rect)
	if not extras.is_empty():
		target = keep_in_margins(target, framed, dist, aspect)
	return {"target": keep_in_margins(target, points, dist, aspect), "distance": dist}


## [param target] moved as little as possible so that every one of [param points] is inside
## the screen margins of a camera at [param dist] (FRAME_MARGIN at the sides,
## [method top_margin] / FRAME_MARGIN_BOTTOM); on an axis where they cannot all fit, the
## middle of their extent.
static func keep_in_margins(target: Vector3, points: Array[Vector3], dist: float, aspect: float) -> Vector3:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var out := target
	var ext := ground_extents(dist, aspect)
	var lo_x := hi.x + FRAME_MARGIN - ext.x
	var hi_x := lo.x - FRAME_MARGIN + ext.x
	out.x = clampf(out.x, lo_x, hi_x) if lo_x <= hi_x else (lo.x + hi.x) * 0.5
	var lo_z := hi.y + FRAME_MARGIN_BOTTOM - ext.z
	var hi_z := lo.y - top_margin(dist) + ext.y
	out.z = clampf(out.z, lo_z, hi_z) if lo_z <= hi_z else (lo_z + hi_z) * 0.5
	return out
