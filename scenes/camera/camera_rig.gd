class_name CameraRig
extends Node3D
## Top-down camera (~57 degree pitch, FOV 40) owned by the "visuals" module. Follows the
## centroid of the living players (group &"players", Player.is_alive()), zooms out with the
## players' spread so everyone stays on screen, and clamps so the view stays inside the
## decorated area around the arena (Arena.current.get_view_rect()).
##
## The rig node sits at the look-at point on the ground; [member camera] is offset back and
## up along the pitch. Framing math is static (see [method compute_framing]) and unit tested.

const PITCH_DEG := 57.0
const FOV := 40.0
const MIN_DISTANCE := 19.5
const MAX_DISTANCE := 36.0
## Metres kept between the outermost players and the screen edge.
const FRAME_MARGIN := 3.2
const FOLLOW_SHARPNESS := 4.5
const ZOOM_SHARPNESS := 2.2
const SHAKE_DECAY := 1.8
## Max screen offset of the camera (metres at the focus plane) at full trauma.
const SHAKE_MAX_OFFSET := 0.55
const SHAKE_MAX_ROLL := 0.035
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
	process_priority = 100
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
## to it. A framed (living) player is limited by the spread of the other framed players
## ([method walk_rect_for]); a ghost that the camera does not follow is kept inside the
## current view ([method walk_rect]).
func get_walk_rect(body: Node3D) -> Rect2:
	var others: Array[Vector3] = []
	var framed := false
	for n in _framed_players():
		if n == body:
			framed = true
		else:
			others.append(n.global_position)
	if framed:
		return walk_rect_for(others, _aspect())
	return walk_rect(focus, distance, _aspect())


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
	return compute_framing(points, _aspect(), rect)


func _aspect() -> float:
	var vp := get_viewport()
	if vp == null:
		return 16.0 / 9.0
	var size := vp.get_visible_rect().size
	return size.x / size.y if size.y > 0.0 else 16.0 / 9.0


func _player_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for n in _framed_players():
		out.append(n.global_position)
	return out


## Players the camera frames: the living ones, or everybody when all are down.
func _framed_players() -> Array[Node3D]:
	var alive: Array[Node3D] = []
	var all: Array[Node3D] = []
	if not is_inside_tree():
		return all
	for node in get_tree().get_nodes_in_group(&"players"):
		var n := node as Node3D
		if n == null or not n.is_inside_tree():
			continue
		all.append(n)
		if not n.has_method(&"is_alive") or n.call(&"is_alive"):
			alive.append(n)
	return alive if not alive.is_empty() else all


# --- Framing math (static, unit tested) ---------------------------------------

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


## Largest player spread (x = across the screen, y = along Z) that [method compute_framing]
## can still fit on screen at MAX_DISTANCE with FRAME_MARGIN.
static func max_spread(aspect: float) -> Vector2:
	var ext := ground_extents(MAX_DISTANCE, aspect)
	return Vector2(2.0 * (ext.x - FRAME_MARGIN), ext.y + ext.z - 2.0 * FRAME_MARGIN)


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


## Distance needed to keep all [param points] on screen with [constant FRAME_MARGIN].
static func required_distance(points: Array[Vector3], aspect: float) -> float:
	if points.is_empty():
		return MIN_DISTANCE
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var dx := ((hi.x - lo.x) * 0.5 + FRAME_MARGIN) / width_factor(aspect)
	var dz := ((hi.y - lo.y) + 2.0 * FRAME_MARGIN) / (north_factor() + south_factor())
	return clampf(maxf(dx, dz), MIN_DISTANCE, MAX_DISTANCE)


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
## MAX_DISTANCE) that every player stays inside the screen margin.
static func compute_framing(points: Array[Vector3], aspect: float, rect: Rect2 = Rect2()) -> Dictionary:
	var centroid := Vector3.ZERO
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		centroid += p
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	if points.is_empty():
		return {"target": Vector3.ZERO, "distance": MIN_DISTANCE}
	centroid /= float(points.size())
	centroid.y = 0.0
	var dist := required_distance(points, aspect)
	var target := clamp_to_view(centroid, dist, aspect, rect)
	var ext := ground_extents(dist, aspect)
	var lo_x := hi.x + FRAME_MARGIN - ext.x
	var hi_x := lo.x - FRAME_MARGIN + ext.x
	target.x = clampf(target.x, lo_x, hi_x) if lo_x <= hi_x else (lo.x + hi.x) * 0.5
	var lo_z := hi.y + FRAME_MARGIN - ext.z
	var hi_z := lo.y - FRAME_MARGIN + ext.y
	target.z = clampf(target.z, lo_z, hi_z) if lo_z <= hi_z else (lo_z + hi_z) * 0.5
	return {"target": target, "distance": dist}
