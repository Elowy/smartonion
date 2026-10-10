class_name EnemyGrid
extends RefCounted
## Shared spatial hash of the enemies (group &"enemies") on the XZ plane – no autoload, only
## static state.
##
## Rebuilt lazily by the first query of a physics tick (within the tick again only when an
## enemy entered the tree or one left it alive), then shared by everything that looks for
## enemies in that tick instead of each of them walking the whole group:
##   * Enemy        – crowd separation ([method crowd_velocity]); enemies only collide with
##                    the world, so this is what keeps a horde from merging into one blob.
##   * Projectile   – swept hit tests and explosions ([method gather_touching]).
##   * WeaponRunner – nearest target ([method nearest]) and melee arcs ([method gather_around]).
##
## A build is one pass over the group plus a native sort of packed cell keys
## (key = cell * MAX_ENEMIES + index), so empty cells cost nothing; a query binary-searches one
## key range per cell row. The cells hold the positions the enemies had at the build. Enemies
## keep moving during the tick, so queries widen their search by [method drift_margin] and the
## callers test the LIVE positions: the results are exactly those of a scan over the whole
## group. Candidates come back in group (tree) order, so every caller stays deterministic.
## Enemies that died since the build stay in it until the next one – callers skip
## [method Enemy.is_dead] ones (and freed ones are skipped here).

## Smallest cell edge (m); cells are never smaller than the largest contact distance, so the
## 3 x 3 block around an enemy holds every neighbour it can touch.
const CELL_SIZE := 1.2
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
## By build index (group order); untyped (a freed enemy can be read and checked safely).
static var _nodes: Array = []
static var _slot_of := PackedInt32Array()
## By slot (sorted by cell): keys, build index and build-time position / radius.
static var _keys := PackedInt64Array()
static var _sorted_i := PackedInt32Array()
static var _sx := PackedFloat64Array()
static var _sz := PackedFloat64Array()
static var _sr := PackedFloat64Array()
static var _max_radius := 0.0
static var _cell := CELL_SIZE
static var _inv_cell := 1.0 / CELL_SIZE
static var _min_x := 0.0
static var _min_z := 0.0
static var _cols := 1
static var _rows := 1
## Crowd separation of the current build (by slot): sum of the contact normals and of the
## overlap pushes; computed by the first [method crowd_velocity] call after a build.
static var _pairs_serial := -1
static var _nrm_x := PackedFloat64Array()
static var _nrm_z := PackedFloat64Array()
static var _push_x := PackedFloat64Array()
static var _push_z := PackedFloat64Array()


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
	var list := []
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	var rs := PackedFloat64Array()
	xs.resize(cap)
	zs.resize(cap)
	rs.resize(cap)
	var n := 0
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	var max_r := 0.0
	var tag_base := _serial * MAX_ENEMIES
	for node in nodes:
		if n >= cap:
			break
		var e := node as Enemy
		if e == null:
			continue
		var pos := e.global_position
		var x := pos.x
		var z := pos.z
		if not (is_finite(x) and is_finite(z)):
			continue
		var r := e.radius
		xs[n] = x
		zs[n] = z
		rs[n] = r
		e._grid_tag = tag_base + n
		list.append(e)
		if x < min_x:
			min_x = x
		if x > max_x:
			max_x = x
		if z < min_z:
			min_z = z
		if z > max_z:
			max_z = z
		if r > max_r:
			max_r = r
		n += 1
	_nodes = list
	_size = n
	_max_radius = max_r
	_cell = maxf(CELL_SIZE, 2.0 * max_r + CONTACT_SKIN)
	_inv_cell = 1.0 / _cell
	var keys := PackedInt64Array()
	keys.resize(n)
	if n == 0:
		_min_x = 0.0
		_min_z = 0.0
		_cols = 1
		_rows = 1
	else:
		_min_x = min_x
		_min_z = min_z
		_cols = clampi(int((max_x - min_x) * _inv_cell) + 1, 1, MAX_CELLS_PER_AXIS)
		_rows = clampi(int((max_z - min_z) * _inv_cell) + 1, 1, MAX_CELLS_PER_AXIS)
	var inv := _inv_cell
	var cols := _cols
	var last_col := _cols - 1
	var last_row := _rows - 1
	for i in n:
		var cx := int((xs[i] - min_x) * inv)
		if cx > last_col:
			cx = last_col
		var cz := int((zs[i] - min_z) * inv)
		if cz > last_row:
			cz = last_row
		keys[i] = (cz * cols + cx) * MAX_ENEMIES + i
	keys.sort()
	var sorted_i := PackedInt32Array()
	var slot_of := PackedInt32Array()
	var sx := PackedFloat64Array()
	var sz := PackedFloat64Array()
	var sr := PackedFloat64Array()
	sorted_i.resize(n)
	slot_of.resize(n)
	sx.resize(n)
	sz.resize(n)
	sr.resize(n)
	for a in n:
		var i := keys[a] % MAX_ENEMIES
		sorted_i[a] = i
		slot_of[i] = a
		sx[a] = xs[i]
		sz[a] = zs[i]
		sr[a] = rs[i]
	_keys = keys
	_sorted_i = sorted_i
	_slot_of = slot_of
	_sx = sx
	_sz = sz
	_sr = sr


## Build indices of the enemies whose build-time centre lies inside the rectangle (already
## grown by the caller), ascending (= group order).
static func _indices_in(min_x: float, min_z: float, max_x: float, max_z: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _size == 0 or max_x < min_x or max_z < min_z:
		return out
	var inv := _inv_cell
	var last_col := _cols - 1
	var last_row := _rows - 1
	var c0 := clampi(int(floorf((min_x - _min_x) * inv)), 0, last_col)
	var c1 := clampi(int(floorf((max_x - _min_x) * inv)), 0, last_col)
	var r0 := clampi(int(floorf((min_z - _min_z) * inv)), 0, last_row)
	var r1 := clampi(int(floorf((max_z - _min_z) * inv)), 0, last_row)
	var keys := _keys
	var sx := _sx
	var sz := _sz
	var si := _sorted_i
	var size := _size
	var cols := _cols
	for r in range(r0, r1 + 1):
		var row := r * cols
		var hi := (row + c1 + 1) * MAX_ENEMIES
		var a := keys.bsearch((row + c0) * MAX_ENEMIES, true)
		while a < size:
			if keys[a] >= hi:
				break
			var x := sx[a]
			var z := sz[a]
			if x >= min_x and x <= max_x and z >= min_z and z <= max_z:
				out.append(si[a])
			a += 1
	if out.size() > 1:
		out.sort()
	return out


## Every enemy (in the tree, possibly dead – check [method Enemy.is_dead]) whose body (live
## centre, [member Enemy.radius]) may touch the rectangle [min_x, max_x] × [min_z, max_z] now.
## In group order. Callers do the exact test on the live positions.
static func gather_touching(tree: SceneTree, min_x: float, min_z: float, max_x: float,
		max_z: float) -> Array[Node]:
	var out: Array[Node] = []
	if tree == null:
		return out
	ensure(tree)
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
	var sx := _sx
	var sz := _sz
	var slot_of := _slot_of
	var nodes := _nodes
	for i in _indices_in(origin.x - cut, origin.z - cut, origin.x + cut, origin.z + cut):
		# Build-time distance first (plain floats); the node only for the close ones.
		var a := slot_of[i]
		var bx := sx[a] - origin.x
		var bz := sz[a] - origin.z
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


## Crowd separation for [param e] (enemies do not collide with each other in the physics
## engine): returns [param velocity] without the part that walks into touching neighbours
## (it slides along the crowd as it would along a collision shape) plus – when [param push] –
## a push out of overlaps (SEPARATION_RESPONSE of each overlap per tick, at most
## MAX_SEPARATION_SPEED). Every pair of the build is evaluated once per build, on the
## build-time positions (symmetric and independent of the processing order).
static func crowd_velocity(e: Enemy, velocity: Vector3, delta: float, push: bool) -> Vector3:
	# Fast path: built this tick and not yet used by this enemy. (Enemies that entered since
	# the build are only separated from the next tick on – queries check that themselves.)
	if _dirty or _frame != Engine.get_physics_frames() or e._grid_used == _serial:
		var tree := e.get_tree()
		if tree == null:
			return velocity
		ensure(tree)
		if e._grid_used == _serial:
			# This enemy already moved with this build: a second tick within the same physics
			# frame (nodes stepped by hand, e.g. in tests) – the positions are stale, rebuild.
			_rebuild(tree, _frame, tree.get_node_count_in_group(&"enemies"))
	e._grid_used = _serial
	var tag := e._grid_tag
	if tag < _serial * MAX_ENEMIES or tag >= (_serial + 1) * MAX_ENEMIES:
		return velocity  # not in this build (entered after it): next tick
	if _pairs_serial != _serial:
		_compute_pairs()
	var a := _slot_of[tag - _serial * MAX_ENEMIES]
	var vx := velocity.x
	var vz := velocity.z
	var nx := _nrm_x[a]
	var nz := _nrm_z[a]
	if nx != 0.0 or nz != 0.0:
		var vn := vx * nx + vz * nz
		if vn < 0.0:
			# Slide: drop the part of the motion that points into the touching neighbours.
			var inv_sq := 1.0 / (nx * nx + nz * nz)
			vx -= nx * vn * inv_sq
			vz -= nz * vn * inv_sq
	if push and delta > 0.0:
		var px := _push_x[a]
		var pz := _push_z[a]
		if px != 0.0 or pz != 0.0:
			var k := SEPARATION_RESPONSE / delta
			px *= k
			pz *= k
			var p_sq := px * px + pz * pz
			if p_sq > MAX_SEPARATION_SPEED * MAX_SEPARATION_SPEED:
				var f := MAX_SEPARATION_SPEED / sqrt(p_sq)
				px *= f
				pz *= f
			vx += px
			vz += pz
	return Vector3(vx, velocity.y, vz)


## Every touching / overlapping pair of the current build once: sums each enemy's contact
## normals and overlap pushes. Pairs can only lie in the same or adjacent cells (cells are
## at least one contact distance wide); per slot it looks at the rest of its cell and the cell
## to the east, then the three cells of the next row – each pair is seen exactly once.
static func _compute_pairs() -> void:
	_pairs_serial = _serial
	var n := _size
	var nrm_x := PackedFloat64Array()
	var nrm_z := PackedFloat64Array()
	var push_x := PackedFloat64Array()
	var push_z := PackedFloat64Array()
	nrm_x.resize(n)
	nrm_z.resize(n)
	push_x.resize(n)
	push_z.resize(n)
	nrm_x.fill(0.0)
	nrm_z.fill(0.0)
	push_x.fill(0.0)
	push_z.fill(0.0)
	var keys := _keys
	var x := _sx
	var z := _sz
	var r := _sr
	var cols := _cols
	var last_col := cols - 1
	var reach := 2.0 * _max_radius + CONTACT_SKIN
	for a in n:
		var cell := keys[a] / MAX_ENEMIES
		var col := cell % cols
		var xa := x[a]
		var za := z[a]
		var ra := r[a]
		# The rest of this cell and the cell to the east (contiguous keys) ...
		var hi := (cell + (2 if col < last_col else 1)) * MAX_ENEMIES
		var b := a + 1
		for part in 2:
			while b < n:
				if keys[b] >= hi:
					break
				var dx := xa - x[b]
				if dx > reach or dx < -reach:
					b += 1
					continue
				var dz := za - z[b]
				var min_d := ra + r[b]
				var lim := min_d + CONTACT_SKIN
				var d_sq := dx * dx + dz * dz
				if d_sq < lim * lim:
					var ux := 1.0
					var uz := 0.0
					var d := sqrt(d_sq)
					if d > 0.0001:
						ux = dx / d
						uz = dz / d
					# (Exactly on top of each other: split along X, the later slot to -X.)
					nrm_x[a] += ux
					nrm_z[a] += uz
					nrm_x[b] -= ux
					nrm_z[b] -= uz
					if d < min_d:
						var o := min_d - d
						push_x[a] += ux * o
						push_z[a] += uz * o
						push_x[b] -= ux * o
						push_z[b] -= uz * o
				b += 1
			if part == 0:
				# ... then south-west, south and south-east (one contiguous key range).
				var lo_cell := cell + cols - (1 if col > 0 else 0)
				var hi_cell := cell + cols + (1 if col < last_col else 0)
				b = keys.bsearch(lo_cell * MAX_ENEMIES, true)
				hi = (hi_cell + 1) * MAX_ENEMIES
	_nrm_x = nrm_x
	_nrm_z = nrm_z
	_push_x = push_x
	_push_z = push_z
