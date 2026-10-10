class_name EnemyGrid
extends RefCounted
## Shared spatial hash of the enemies (group &"enemies") on the XZ plane – no autoload, only
## static state.
##
## Rebuilt lazily by the first query of a physics tick (again within the tick only when an enemy
## entered or left the tree since), then shared by everything that looks for enemies in that
## tick instead of each of them walking the whole group:
##   * Enemy        – crowd separation ([method crowd_velocity]); enemies only collide with
##                    the world, so this is what keeps a horde from merging into one blob.
##   * Projectile   – swept hit tests and explosions ([method gather_touching]).
##   * WeaponRunner – nearest target ([method nearest]) and melee arcs ([method gather_touching]).
##
## A build is one pass over the group plus a native sort of packed cell keys
## (key = cell * MAX_ENEMIES + index), so empty cells cost nothing; a query binary-searches one
## key range per cell row. The cells hold the positions the enemies had at the build. Enemies
## keep moving during the tick, so queries widen their search by [method drift_margin] and the
## callers test the LIVE positions: the results are exactly those of a scan over the whole
## group. Candidates come back in group (tree) order, so every caller stays deterministic.
## Enemies that died since the build stay in it until the next one – callers skip
## [method Enemy.is_dead] ones.

const CELL_SIZE := 1.5
const INV_CELL := 1.0 / CELL_SIZE
## Upper bound (m/s) of how fast an enemy moves (walk + lunge + knockback + separation): how far
## it can get from its cell between the build and a query later in the same tick.
const MAX_ENEMY_SPEED := 30.0
## Positions beyond this many cells per axis are clamped into the edge cells (still correct).
const MAX_CELLS_PER_AXIS := 4096
## Enemies beyond this many are left out of the grid (the wave cap is far below).
const MAX_ENEMIES := 65536

## Crowd separation: neighbours closer than the sum of the radii + this (m) block the walking
## direction towards them (the enemy slides along them like along a collision shape).
const CONTACT_SKIN := 0.04
## Fraction of an overlap an enemy resolves per tick (each side of a pair does its share).
const SEPARATION_RESPONSE := 0.5
## Cap (m/s) of the push out of overlaps (a freshly spawned clump spreads over a few ticks).
const MAX_SEPARATION_SPEED := 5.0

static var _frame := -1
static var _count := 0
static var _dirty := true
static var _serial := 0
static var _size := 0
static var _nodes: Array[Enemy] = []
static var _px := PackedFloat64Array()
static var _pz := PackedFloat64Array()
static var _pr := PackedFloat64Array()
static var _keys := PackedInt64Array()
static var _max_radius := 0.0
static var _min_x := 0.0
static var _min_z := 0.0
static var _cols := 1
static var _rows := 1
static var _empty: Array[Node] = []


## The next query rebuilds the grid (an enemy entered or left the tree; tests, tools).
static func mark_dirty() -> void:
	_dirty = true


## How far (m) an enemy may have moved since the build of the current tick.
static func drift_margin() -> float:
	var ticks := maxi(1, Engine.physics_ticks_per_second)
	return MAX_ENEMY_SPEED * maxf(1.0, Engine.time_scale) / float(ticks)


## Number of the current build (changes with every rebuild).
static func serial() -> int:
	return _serial


## Makes the grid current for this tick.
static func ensure(tree: SceneTree) -> void:
	if tree == null:
		return
	var frame := Engine.get_physics_frames()
	var count := tree.get_node_count_in_group(&"enemies")
	if _dirty or frame != _frame or count > _count:
		_rebuild(tree, frame, count)
	elif count < _count:
		# Deaths: the dead stay in their cells until the next build (callers skip them).
		_count = count


static func _rebuild(tree: SceneTree, frame: int, count: int) -> void:
	_serial += 1
	_frame = frame
	_count = count
	_dirty = false
	var nodes := tree.get_nodes_in_group(&"enemies")
	var cap := mini(nodes.size(), MAX_ENEMIES)
	_nodes.clear()
	_px.resize(cap)
	_pz.resize(cap)
	_pr.resize(cap)
	var n := 0
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	var max_r := 0.0
	for node in nodes:
		if n >= cap:
			break
		var e := node as Enemy
		if e == null:
			continue
		var pos := e.global_position
		if not (is_finite(pos.x) and is_finite(pos.z)):
			continue
		_px[n] = pos.x
		_pz[n] = pos.z
		_pr[n] = e.radius
		e._grid_serial = _serial
		e._grid_index = n
		_nodes.append(e)
		min_x = minf(min_x, pos.x)
		max_x = maxf(max_x, pos.x)
		min_z = minf(min_z, pos.z)
		max_z = maxf(max_z, pos.z)
		max_r = maxf(max_r, e.radius)
		n += 1
	_size = n
	_px.resize(n)
	_pz.resize(n)
	_pr.resize(n)
	_keys.resize(n)
	_max_radius = max_r
	if n == 0:
		_min_x = 0.0
		_min_z = 0.0
		_cols = 1
		_rows = 1
		return
	_min_x = min_x
	_min_z = min_z
	_cols = clampi(int((max_x - min_x) * INV_CELL) + 1, 1, MAX_CELLS_PER_AXIS)
	_rows = clampi(int((max_z - min_z) * INV_CELL) + 1, 1, MAX_CELLS_PER_AXIS)
	var last_col := _cols - 1
	var last_row := _rows - 1
	for i in n:
		var cx := mini(int((_px[i] - min_x) * INV_CELL), last_col)
		var cz := mini(int((_pz[i] - min_z) * INV_CELL), last_row)
		_keys[i] = (cz * _cols + cx) * MAX_ENEMIES + i
	_keys.sort()


## Build indices of the enemies whose build-time centre lies inside the rectangle (already grown
## by the caller), ascending (= group order).
static func _indices_in(min_x: float, min_z: float, max_x: float, max_z: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _size == 0 or max_x < min_x or max_z < min_z:
		return out
	var last_col := _cols - 1
	var last_row := _rows - 1
	var c0 := clampi(int(floorf((min_x - _min_x) * INV_CELL)), 0, last_col)
	var c1 := clampi(int(floorf((max_x - _min_x) * INV_CELL)), 0, last_col)
	var r0 := clampi(int(floorf((min_z - _min_z) * INV_CELL)), 0, last_row)
	var r1 := clampi(int(floorf((max_z - _min_z) * INV_CELL)), 0, last_row)
	var keys := _keys
	var px := _px
	var pz := _pz
	var size := _size
	for r in range(r0, r1 + 1):
		var row := r * _cols
		var hi := (row + c1 + 1) * MAX_ENEMIES
		var j := keys.bsearch((row + c0) * MAX_ENEMIES, true)
		while j < size:
			var key := keys[j]
			if key >= hi:
				break
			var i := key % MAX_ENEMIES
			var x := px[i]
			var z := pz[i]
			if x >= min_x and x <= max_x and z >= min_z and z <= max_z:
				out.append(i)
			j += 1
	if r1 > r0:
		out.sort()
	return out


## Every enemy (in the tree, possibly dead – check [method Enemy.is_dead]) whose body (live
## centre, [member Enemy.radius]) may touch the rectangle [min_x, max_x] × [min_z, max_z] now.
## In group order. Callers do the exact test on the live positions.
static func gather_touching(tree: SceneTree, min_x: float, min_z: float, max_x: float,
		max_z: float) -> Array[Node]:
	if tree == null:
		return _empty.duplicate()
	ensure(tree)
	var out: Array[Node] = []
	if _size == 0:
		return out
	var grow := _max_radius + drift_margin()
	var nodes := _nodes
	for i in _indices_in(min_x - grow, min_z - grow, max_x + grow, max_z + grow):
		var e: Variant = nodes[i]
		if is_instance_valid(e) and (e as Enemy).is_inside_tree():
			out.append(e)
	return out


## Every enemy whose body may touch the circle at [param center] with [param radius] (XZ).
static func gather_around(tree: SceneTree, center: Vector3, radius: float) -> Array[Node]:
	return gather_touching(tree, center.x - radius, center.z - radius, center.x + radius,
			center.z + radius)


## Nearest living enemy whose centre is within [param max_range] of [param origin] (XZ) – the
## same result as [method WeaponRunner.nearest_enemy] over the whole group (ties: the first one
## in group order).
static func nearest(tree: SceneTree, origin: Vector3, max_range: float) -> Enemy:
	if tree == null or max_range < 0.0:
		return null
	ensure(tree)
	if _size == 0:
		return null
	var drift := drift_margin()
	var cut := max_range + drift
	var cut_sq := cut * cut
	var best: Enemy = null
	var best_d := max_range * max_range
	var px := _px
	var pz := _pz
	var nodes := _nodes
	for i in _indices_in(origin.x - cut, origin.z - cut, origin.x + cut, origin.z + cut):
		# Build-time distance first (plain floats); the node only for the close ones.
		var bx := px[i] - origin.x
		var bz := pz[i] - origin.z
		if bx * bx + bz * bz > cut_sq:
			continue
		var node: Variant = nodes[i]
		if not is_instance_valid(node):
			continue
		var e := node as Enemy
		if not e.is_inside_tree():
			continue
		var pos := e.global_position
		var dx := pos.x - origin.x
		var dz := pos.z - origin.z
		var d := dx * dx + dz * dz
		if d > best_d or (d == best_d and best != null):
			continue
		if e.is_dead():
			continue
		best_d = d
		best = e
		cut = sqrt(best_d) + drift
		cut_sq = cut * cut
	return best


## Crowd separation for [param e] standing at [param here] (enemies do not collide with each
## other in the physics engine): returns [param velocity] without the parts that walk into a
## touching neighbour (it slides along the crowd as it would along a collision shape) plus –
## when [param push] – a push out of overlaps (SEPARATION_RESPONSE of each overlap per tick,
## at most MAX_SEPARATION_SPEED). Uses the neighbours' build-time positions (symmetric and
## order independent).
static func crowd_velocity(e: Enemy, here: Vector3, velocity: Vector3, delta: float,
		push: bool) -> Vector3:
	var tree := e.get_tree()
	if tree == null:
		return velocity
	ensure(tree)
	if e._grid_used == _serial:
		# This enemy already moved with this build: a second tick within the same physics frame
		# (nodes stepped by hand, e.g. in tests) – the positions are stale, rebuild.
		_rebuild(tree, _frame, tree.get_node_count_in_group(&"enemies"))
	e._grid_used = _serial
	if _size == 0:
		return velocity
	var own := e._grid_index if e._grid_serial == _serial else -1
	var r := e.radius
	var reach := r + _max_radius + CONTACT_SKIN
	var hx := here.x
	var hz := here.z
	var last_col := _cols - 1
	var last_row := _rows - 1
	var c0 := clampi(int(floorf((hx - reach - _min_x) * INV_CELL)), 0, last_col)
	var c1 := clampi(int(floorf((hx + reach - _min_x) * INV_CELL)), 0, last_col)
	var r0 := clampi(int(floorf((hz - reach - _min_z) * INV_CELL)), 0, last_row)
	var r1 := clampi(int(floorf((hz + reach - _min_z) * INV_CELL)), 0, last_row)
	var keys := _keys
	var px := _px
	var pz := _pz
	var pr := _pr
	var size := _size
	var vx := velocity.x
	var vz := velocity.z
	var push_x := 0.0
	var push_z := 0.0
	for row_i in range(r0, r1 + 1):
		var row := row_i * _cols
		var hi := (row + c1 + 1) * MAX_ENEMIES
		var j := keys.bsearch((row + c0) * MAX_ENEMIES, true)
		while j < size:
			var key := keys[j]
			j += 1
			if key >= hi:
				break
			var i := key % MAX_ENEMIES
			if i == own:
				continue
			var dx := hx - px[i]
			var dz := hz - pz[i]
			var min_d := r + pr[i]
			var lim := min_d + CONTACT_SKIN
			var d_sq := dx * dx + dz * dz
			if d_sq >= lim * lim:
				continue
			var nx := 0.0
			var nz := 0.0
			var d := sqrt(d_sq)
			if d > 0.0001:
				nx = dx / d
				nz = dz / d
			else:
				# Exactly on top of each other: split along X by build order (deterministic).
				nx = 1.0 if own > i else -1.0
			var vn := vx * nx + vz * nz
			if vn < 0.0:
				vx -= nx * vn
				vz -= nz * vn
			if push and d < min_d:
				push_x += nx * (min_d - d)
				push_z += nz * (min_d - d)
	if push and (push_x != 0.0 or push_z != 0.0) and delta > 0.0:
		var k := SEPARATION_RESPONSE / delta
		var sx := push_x * k
		var sz := push_z * k
		var s_sq := sx * sx + sz * sz
		if s_sq > MAX_SEPARATION_SPEED * MAX_SEPARATION_SPEED:
			var f := MAX_SEPARATION_SPEED / sqrt(s_sq)
			sx *= f
			sz *= f
		vx += sx
		vz += sz
	return Vector3(vx, velocity.y, vz)
