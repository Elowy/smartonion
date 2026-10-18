class_name ArenaDecor
extends RefCounted
## Procedural decoration for [Arena] (owned by the "visuals" module): a stylised, WoW-like
## forest clearing. Everything is merged into a handful of vertex-coloured meshes / MultiMeshes
## (forest chunks, bushes, rocks, props, grass, flowers) so it costs only a few draw calls.
## Uses its own seeded RNG – never RunState.rng.

const STONE := Color(0.53, 0.5, 0.47)
const MOSS := Color(0.42, 0.54, 0.3)
const WOOD := Color(0.47, 0.31, 0.18)
const DARK_WOOD := Color(0.34, 0.22, 0.13)
const IRON := Color(0.3, 0.3, 0.33)
const GOLD := Color(0.95, 0.76, 0.3)
const BANNER_BLUE := Color(0.16, 0.3, 0.72)
const LEAF_GREENS: Array[Color] = [
	Color(0.27, 0.53, 0.17), Color(0.33, 0.6, 0.2), Color(0.22, 0.46, 0.15),
	Color(0.4, 0.64, 0.22), Color(0.3, 0.56, 0.24),
]
const LEAF_AUTUMN: Array[Color] = [Color(0.62, 0.64, 0.2), Color(0.78, 0.55, 0.18)]
const PINE_GREEN := Color(0.16, 0.38, 0.22)
## Wall centre line offset outside the bounds and its thickness / height.
const WALL_OFFSET := 0.4
const WALL_DEPTH := 0.7
const GATE_HALF_WIDTH := 1.6
## Trees farther than this from the playable bounds are only seen from afar: low-poly,
## no shadows.
const FAR_TREE_DISTANCE := 11.0


## Builds every decoration node for [param arena] (walls are built separately).
static func build(arena: Arena, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var bounds := arena.get_bounds()
	var decor := arena.get_decor_rect()
	_build_forest(root, bounds, decor, rng)
	_build_undergrowth(root, bounds, decor, rng)
	_build_props(root, bounds, rng)
	_build_grass(root, bounds, decor, rng)
	return root


## Low stone wall with pillars, corner towers and a north gate, just outside [param bounds].
## [param tint] is multiplied onto the stones' vertex colours (EnvironmentData.wall_tint; white = as is).
static func build_wall_visual(bounds: Rect2, seed_value: int, tint: Color = Color.WHITE) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 17
	var k := MeshKit.new()
	var o := WALL_OFFSET
	var x0 := bounds.position.x - o
	var x1 := bounds.end.x + o
	var z0 := bounds.position.y - o
	var z1 := bounds.end.y + o
	# Runs: north (with a gap for the gate), south, west, east.
	_wall_run(k, Vector3(x0, 0, z0), Vector3(-GATE_HALF_WIDTH - 0.5, 0, z0), rng)
	_wall_run(k, Vector3(GATE_HALF_WIDTH + 0.5, 0, z0), Vector3(x1, 0, z0), rng)
	# The south run sits between the camera and the action: keep it low.
	_wall_run(k, Vector3(x0, 0, z1), Vector3(x1, 0, z1), rng, true)
	_wall_run(k, Vector3(x0, 0, z0), Vector3(x0, 0, z1), rng)
	_wall_run(k, Vector3(x1, 0, z0), Vector3(x1, 0, z1), rng)
	# Pillars along the runs.
	for x in _steps(x0, x1, 8.5):
		if absf(x) > GATE_HALF_WIDTH + 1.0:
			_pillar(k, Vector3(x, 0, z0), rng)
		_pillar(k, Vector3(x, 0, z1), rng, true)
	for z in _steps(z0, z1, 7.5):
		_pillar(k, Vector3(x0, 0, z), rng)
		_pillar(k, Vector3(x1, 0, z), rng)
	for c: Vector3 in [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x0, 0, z1), Vector3(x1, 0, z1)]:
		_tower(k, c, rng)
	_gate(k, Vector3(0, 0, z0))
	var root := Node3D.new()
	root.name = "WallVisual"
	var mi := MeshInstance3D.new()
	mi.name = "Stones"
	mi.mesh = k.build()
	mi.material_override = Mats.toon_vc(true, tint)
	root.add_child(mi)
	# Torch flames on the gate and the north corners.
	var flames := MeshKit.new()
	for p: Vector3 in [Vector3(-GATE_HALF_WIDTH - 0.5, 2.12, z0), Vector3(GATE_HALF_WIDTH + 0.5, 2.12, z0),
			Vector3(x0, 2.08, z0), Vector3(x1, 2.08, z0)]:
		flames.add_sphere(0.13, MeshKit.xf(p + Vector3(0, 0.06, 0)), Color.WHITE, 8, 4)
		flames.add_cylinder(0.0, 0.12, 0.34, MeshKit.xf(p + Vector3(0, 0.25, 0)), Color.WHITE, 8)
	var fm := MeshInstance3D.new()
	fm.name = "TorchFlames"
	fm.mesh = flames.build()
	fm.material_override = Mats.glow(Color(1.0, 0.6, 0.18), 2.6)
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fm)
	return root


static func _steps(a: float, b: float, spacing: float) -> Array[float]:
	var out: Array[float] = []
	var n := maxi(1, int(round((b - a) / spacing)))
	for i in range(1, n):
		out.append(lerpf(a, b, float(i) / float(n)))
	return out


static func _stone_color(rng: RandomNumberGenerator) -> Color:
	var c := STONE.darkened(rng.randf_range(-0.08, 0.14))
	var r := rng.randf()
	if r < 0.18:
		c = c.lerp(MOSS, 0.45)
	elif r < 0.35:
		c = c.lerp(Color(0.7, 0.62, 0.5), 0.3)
	return c


static func _wall_run(k: MeshKit, a: Vector3, b: Vector3, rng: RandomNumberGenerator, low: bool = false) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / maxf(length, 0.001)
	var yaw := atan2(dir.x, dir.z)
	var rows := [[0.0, 0.34]] if low else [[0.0, 0.36], [0.36, 0.32]]
	var cap_y := 0.4 if low else 0.74
	for r in rows.size():
		var y: float = rows[r][0]
		var h: float = rows[r][1]
		var d := 0.0 if r == 0 else rng.randf_range(0.2, 0.45)
		while d < length - 0.05:
			var l := minf(rng.randf_range(0.5, 0.95), length - d)
			var c := a + dir * (d + l * 0.5)
			var basis := Basis(Vector3.UP, yaw + rng.randf_range(-0.04, 0.04))
			var size := Vector3(WALL_DEPTH + rng.randf_range(-0.06, 0.04) - r * 0.06, h - 0.03 + rng.randf_range(-0.02, 0.03), l - 0.05)
			k.add_box(size, Transform3D(basis, c + Vector3(0, y + size.y * 0.5, 0)), _stone_color(rng))
			d += l
	# Cap stones.
	var d2 := 0.0
	while d2 < length - 0.05:
		var l := minf(rng.randf_range(0.7, 1.2), length - d2)
		var c := a + dir * (d2 + l * 0.5)
		k.add_box(Vector3(WALL_DEPTH + 0.1, 0.13, l - 0.04), Transform3D(Basis(Vector3.UP, yaw), c + Vector3(0, cap_y, 0)), STONE.darkened(rng.randf_range(0.0, 0.12)))
		if rng.randf() < 0.22:
			k.add_sphere(rng.randf_range(0.18, 0.3), MeshKit.xf(c + Vector3(rng.randf_range(-0.1, 0.1), cap_y + 0.06, 0), Vector3.ZERO, Vector3(1.4, 0.45, 1.0)), MOSS.darkened(rng.randf_range(0.0, 0.15)), 8, 4)
		d2 += l


static func _pillar(k: MeshKit, p: Vector3, rng: RandomNumberGenerator, low: bool = false) -> void:
	var h := 0.62 if low else 1.15
	k.add_box(Vector3(0.95, h, 0.95), MeshKit.xf(p + Vector3(0, h * 0.5, 0), Vector3(0, rng.randf_range(-3, 3), 0)), STONE.darkened(rng.randf_range(0.02, 0.12)))
	k.add_box(Vector3(1.1, 0.16, 1.1), MeshKit.xf(p + Vector3(0, h + 0.07, 0)), STONE.lightened(0.06))
	k.add_cylinder(0.0, 0.45, 0.32, MeshKit.xf(p + Vector3(0, h + 0.31, 0), Vector3(0, 45, 0)), STONE.darkened(0.05), 4)


static func _tower(k: MeshKit, p: Vector3, rng: RandomNumberGenerator) -> void:
	k.add_cylinder(0.85, 0.95, 1.7, MeshKit.xf(p + Vector3(0, 0.85, 0)), STONE.darkened(0.04), 12)
	k.add_cylinder(1.02, 1.02, 0.22, MeshKit.xf(p + Vector3(0, 1.8, 0)), STONE.lightened(0.05), 12)
	for i in 6:
		var a := TAU * i / 6.0
		k.add_box(Vector3(0.36, 0.3, 0.3), Transform3D(Basis(Vector3.UP, a), p + Vector3(sin(a) * 0.86, 2.06, cos(a) * 0.86)), STONE.darkened(rng.randf_range(0.0, 0.1)))
	_torch(k, p + Vector3(0, 1.9, 0))


static func _torch(k: MeshKit, p: Vector3) -> void:
	k.add_cylinder(0.05, 0.07, 0.22, MeshKit.xf(p + Vector3(0, 0.06, 0)), DARK_WOOD, 6)
	k.add_cylinder(0.17, 0.1, 0.12, MeshKit.xf(p + Vector3(0, 0.2, 0)), IRON, 8)


static func _gate(k: MeshKit, p: Vector3) -> void:
	for side: float in [-1.0, 1.0]:
		var c := p + Vector3((GATE_HALF_WIDTH + 0.5) * side, 0, 0)
		k.add_box(Vector3(1.0, 1.95, 1.0), MeshKit.xf(c + Vector3(0, 0.975, 0)), STONE.darkened(0.06))
		k.add_box(Vector3(1.16, 0.16, 1.16), MeshKit.xf(c + Vector3(0, 2.0, 0)), STONE.lightened(0.06))
		_torch(k, c + Vector3(0, 2.05, 0))
	# Closed wooden gate (decoration – the collision wall is continuous).
	for i in 7:
		var x := lerpf(-GATE_HALF_WIDTH + 0.25, GATE_HALF_WIDTH - 0.25, i / 6.0)
		k.add_box(Vector3(0.42, 1.25 + (0.12 if i % 2 == 0 else 0.0), 0.12), MeshKit.xf(p + Vector3(x, 0.66, 0)), WOOD.darkened(0.05 * (i % 3)))
	for y: float in [0.35, 1.0]:
		k.add_box(Vector3(GATE_HALF_WIDTH * 2.0, 0.14, 0.16), MeshKit.xf(p + Vector3(0, y, -0.04)), DARK_WOOD)
	k.add_box(Vector3(0.12, 1.3, 0.16), MeshKit.xf(p + Vector3(0, 0.68, -0.05), Vector3(0, 0, 58)), DARK_WOOD)
	k.add_box(Vector3(GATE_HALF_WIDTH * 2.0 + 1.6, 0.3, 0.5), MeshKit.xf(p + Vector3(0, 2.25, 0)), DARK_WOOD)
	for side: float in [-1.0, 1.0]:
		k.add_sphere(0.07, MeshKit.xf(p + Vector3(0.9 * side, 0.68, -0.08)), IRON, 6, 3)


# --- Forest ------------------------------------------------------------------

## True when a tall tree may stand at [param p]: in the decor band, off the road and not
## in front of the camera (south band near the wall stays low so it never hides the action).
static func tree_allowed(p: Vector2, bounds: Rect2, decor: Rect2) -> bool:
	if not decor.has_point(p):
		return false
	if bounds.grow(2.6).has_point(p):
		return false
	if p.y > bounds.end.y and p.y < bounds.end.y + 8.0:
		return false
	if p.y < bounds.position.y and absf(p.x - road_x(p.y, bounds)) < 3.2:
		return false
	return true


## Road centre x at depth [param z] (matches the ground shader).
static func road_x(z: float, bounds: Rect2) -> float:
	var half_y := bounds.size.y * 0.5
	return sin(z * 0.11) * 2.2 * smoothstep(-half_y, -half_y - 8.0, z)


static func _build_forest(root: Node3D, bounds: Rect2, decor: Rect2, rng: RandomNumberGenerator) -> void:
	# Chunks N, S, W, E (so the camera can frustum-cull them), each split into a near part
	# (detailed, casts shadows into the clearing) and a far part (low-poly, no shadows).
	var kits: Array[MeshKit] = []
	for i in 8:
		kits.append(MeshKit.new())
	var cell := 3.6
	var y := decor.position.y
	while y < decor.end.y:
		var x := decor.position.x
		while x < decor.end.x:
			var p := Vector2(x + rng.randf_range(0.2, cell - 0.2), y + rng.randf_range(0.2, cell - 0.2))
			var dense := absf(p.x) > bounds.end.x + 5.0 or p.y < bounds.position.y - 5.0 or p.y > bounds.end.y + 11.0
			if tree_allowed(p, bounds, decor) and rng.randf() < (0.86 if dense else 0.6):
				var far := distance_outside(p, bounds) > FAR_TREE_DISTANCE
				var k := kits[_chunk(p, bounds) + (4 if far else 0)]
				if rng.randf() < 0.2:
					_pine(k, Vector3(p.x, 0, p.y), rng, far)
				else:
					_tree(k, Vector3(p.x, 0, p.y), rng, far)
			x += cell
		y += cell
	var names := ["ForestNorth", "ForestSouth", "ForestWest", "ForestEast"]
	for i in kits.size():
		if kits[i].is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = names[i % 4] + ("Far" if i >= 4 else "")
		mi.mesh = kits[i].build()
		mi.material_override = Mats.toon_vc(true, Color.WHITE, 0.045)
		if i >= 4:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## Distance (metres) from [param p] to the rectangle [param r] (0 inside).
static func distance_outside(p: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dy := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return Vector2(dx, dy).length()


## The decor sets of the other environments (ArenaThemes) reuse these three helpers.
static func chunk_of(p: Vector2, bounds: Rect2) -> int:
	return _chunk(p, bounds)


static func perimeter_point(r: Rect2, d: float) -> Vector2:
	return _perimeter_point(r, d)


static func multimesh(n: String, mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color]) -> MultiMeshInstance3D:
	return _multimesh(n, mesh, xforms, colors)


static func _chunk(p: Vector2, bounds: Rect2) -> int:
	if p.y < bounds.position.y:
		return 0
	if p.y > bounds.end.y:
		return 1
	return 2 if p.x < 0.0 else 3


static func _tree(k: MeshKit, p: Vector3, rng: RandomNumberGenerator, low: bool = false) -> void:
	var h := rng.randf_range(1.8, 3.0)
	var r := rng.randf_range(0.22, 0.34)
	var lean := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
	var top := p + Vector3(0, h, 0) + lean
	var bark := WOOD.darkened(rng.randf_range(-0.05, 0.15))
	k.add_segment(p + Vector3(0, -0.1, 0), top, r * 1.25, r * 0.7, bark, 5 if low else 7)
	# Root flare and a couple of branches.
	for i in 3:
		var a := rng.randf_range(0.0, TAU)
		var foot := p + Vector3(sin(a) * r * 2.2, 0.0, cos(a) * r * 2.2)
		if not low:
			k.add_segment(p + Vector3(0, 0.25, 0), foot, r * 0.55, r * 0.2, bark, 5)
	var palette := LEAF_GREENS if rng.randf() > 0.1 else LEAF_AUTUMN
	var base := palette[rng.randi_range(0, palette.size() - 1)]
	var canopy := top + Vector3(0, rng.randf_range(0.6, 1.0), 0)
	var blobs := rng.randi_range(3, 5)
	var size := rng.randf_range(1.3, 1.9)
	var radial := 8 if low else 12
	var rings := 4 if low else 6
	k.add_sphere(size, MeshKit.xf(canopy, Vector3.ZERO, Vector3(1.0, 0.85, 1.0)), base.darkened(0.08), radial, rings)
	for i in blobs:
		var a := TAU * i / blobs + rng.randf_range(-0.4, 0.4)
		var off := Vector3(sin(a) * size * 0.7, rng.randf_range(-0.2, 0.5), cos(a) * size * 0.7)
		var c := base.lightened(rng.randf_range(-0.05, 0.12))
		k.add_sphere(size * rng.randf_range(0.6, 0.8), MeshKit.xf(canopy + off, Vector3.ZERO, Vector3(1.0, 0.85, 1.0)), c, radial - 1, rings)
	k.add_sphere(size * 0.7, MeshKit.xf(canopy + Vector3(0, size * 0.6, 0), Vector3.ZERO, Vector3(1.0, 0.8, 1.0)), base.lightened(0.16), radial - 1, rings)


static func _pine(k: MeshKit, p: Vector3, rng: RandomNumberGenerator, low: bool = false) -> void:
	var h := rng.randf_range(5.0, 7.5)
	k.add_cylinder(0.16, 0.3, h * 0.35, MeshKit.xf(p + Vector3(0, h * 0.17, 0)), DARK_WOOD, 5 if low else 6)
	var tiers := 4
	for i in tiers:
		var t := float(i) / tiers
		var w := lerpf(1.9, 0.7, t) * rng.randf_range(0.9, 1.1)
		var y := lerpf(h * 0.25, h * 0.8, t)
		k.add_cylinder(0.0, w, h * 0.32, MeshKit.xf(p + Vector3(0, y + h * 0.16, 0), Vector3(0, rng.randf_range(0, 60), 0)), PINE_GREEN.lightened(t * 0.12 + rng.randf_range(-0.03, 0.05)), 7 if low else 8)


# --- Undergrowth: bushes, rocks, mushrooms ------------------------------------

static func _build_undergrowth(root: Node3D, bounds: Rect2, decor: Rect2, rng: RandomNumberGenerator) -> void:
	var k := MeshKit.new()
	# Hedge of bushes hugging the outside of the wall.
	var ring := bounds.grow(1.7)
	var perimeter := 2.0 * (ring.size.x + ring.size.y)
	var d := 0.0
	while d < perimeter:
		var p := _perimeter_point(ring, d)
		var skip_gate := p.y < bounds.position.y and absf(p.x) < GATE_HALF_WIDTH + 2.5
		if not skip_gate and rng.randf() < 0.75:
			_bush(k, Vector3(p.x, 0, p.y) + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)), rng.randf_range(0.6, 1.0), rng)
		d += rng.randf_range(1.6, 3.0)
	# Scattered bushes, rocks and mushrooms in the band.
	for i in 140:
		var p := Vector2(rng.randf_range(decor.position.x, decor.end.x), rng.randf_range(decor.position.y, decor.end.y))
		if bounds.grow(2.2).has_point(p):
			continue
		if p.y < bounds.position.y and absf(p.x - road_x(p.y, bounds)) < 2.6:
			continue
		var roll := rng.randf()
		var at := Vector3(p.x, 0, p.y)
		if roll < 0.45:
			_bush(k, at, rng.randf_range(0.6, 1.2), rng)
		elif roll < 0.8:
			_rock(k, at, rng.randf_range(0.35, 0.9), rng)
		else:
			_mushrooms(k, at, rng)
	var mi := MeshInstance3D.new()
	mi.name = "Undergrowth"
	mi.mesh = k.build()
	mi.material_override = Mats.toon_vc(true, Color.WHITE, 0.03)
	root.add_child(mi)


static func _perimeter_point(r: Rect2, d: float) -> Vector2:
	var w := r.size.x
	var h := r.size.y
	d = fposmod(d, 2.0 * (w + h))
	if d < w:
		return Vector2(r.position.x + d, r.position.y)
	d -= w
	if d < h:
		return Vector2(r.end.x, r.position.y + d)
	d -= h
	if d < w:
		return Vector2(r.end.x - d, r.end.y)
	d -= w
	return Vector2(r.position.x, r.end.y - d)


static func _bush(k: MeshKit, p: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var base := LEAF_GREENS[rng.randi_range(0, LEAF_GREENS.size() - 1)].darkened(0.12)
	var n := rng.randi_range(2, 4)
	for i in n:
		var a := rng.randf_range(0.0, TAU)
		var off := Vector3(sin(a), 0, cos(a)) * size * rng.randf_range(0.2, 0.6)
		var s := size * rng.randf_range(0.55, 0.85)
		k.add_sphere(s, MeshKit.xf(p + off + Vector3(0, s * 0.55, 0), Vector3.ZERO, Vector3(1.0, 0.8, 1.0)), base.lightened(rng.randf_range(0.0, 0.14)), 11, 5)
	if rng.randf() < 0.3:
		var bloom := [Color(0.98, 0.6, 0.75), Color(0.98, 0.95, 0.85), Color(1.0, 0.85, 0.3)][rng.randi_range(0, 2)] as Color
		for i in 5:
			var a := rng.randf_range(0.0, TAU)
			k.add_sphere(0.07, MeshKit.xf(p + Vector3(sin(a) * size * 0.5, size * rng.randf_range(0.7, 1.0), cos(a) * size * 0.5)), bloom, 5, 3)


static func _rock(k: MeshKit, p: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var c := STONE.darkened(rng.randf_range(0.0, 0.18))
	var rot := Vector3(rng.randf_range(-15, 15), rng.randf_range(0, 360), rng.randf_range(-15, 15))
	k.add_sphere(size, MeshKit.xf(p + Vector3(0, size * 0.3, 0), rot, Vector3(1.25, 0.7, 1.0)), c, 7, 4)
	if rng.randf() < 0.5:
		k.add_sphere(size * 0.55, MeshKit.xf(p + Vector3(size * 0.8, size * 0.15, size * 0.3), rot, Vector3(1.2, 0.7, 1.0)), c.lightened(0.05), 6, 3)
	if rng.randf() < 0.4:
		k.add_sphere(size * 0.75, MeshKit.xf(p + Vector3(0, size * 0.62, 0), rot, Vector3(1.1, 0.3, 0.9)), MOSS, 7, 3)


static func _mushrooms(k: MeshKit, p: Vector3, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(2, 4):
		var q := p + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
		var s := rng.randf_range(0.6, 1.1)
		k.add_cylinder(0.05 * s, 0.07 * s, 0.25 * s, MeshKit.xf(q + Vector3(0, 0.12 * s, 0)), Color(0.95, 0.92, 0.82), 6)
		k.add_sphere(0.17 * s, MeshKit.xf(q + Vector3(0, 0.24 * s, 0), Vector3.ZERO, Vector3(1, 0.75, 1)), Color(0.85, 0.18, 0.12), 8, 4, true)
		for j in 3:
			var a := TAU * j / 3.0 + i
			k.add_sphere(0.028 * s, MeshKit.xf(q + Vector3(sin(a) * 0.09 * s, 0.33 * s, cos(a) * 0.09 * s)), Color(1, 1, 0.95), 4, 2)


# --- Props: banners, fences, farm corner -------------------------------------

static func _build_props(root: Node3D, bounds: Rect2, rng: RandomNumberGenerator) -> void:
	var k := MeshKit.new()
	var cloth := MeshKit.new()
	var z0 := bounds.position.y - WALL_OFFSET
	# Banners flanking the gate.
	for side: float in [-1.0, 1.0]:
		var base := Vector3((GATE_HALF_WIDTH + 1.8) * side, 0, z0 - 1.0)
		k.add_cylinder(0.06, 0.08, 3.6, MeshKit.xf(base + Vector3(0, 1.8, 0)), DARK_WOOD, 6)
		k.add_sphere(0.1, MeshKit.xf(base + Vector3(0, 3.65, 0)), GOLD, 8, 4)
		k.add_cylinder(0.035, 0.035, 1.0, MeshKit.xf(base + Vector3(0, 3.4, 0), Vector3(0, 0, 90)), DARK_WOOD, 6)
		var flag := PackedVector2Array([Vector2(-0.45, 0), Vector2(0.45, 0), Vector2(0.45, -1.5),
			Vector2(0.0, -1.2), Vector2(-0.45, -1.5)])
		cloth.add_extrusion(flag, 0.03, MeshKit.xf(base + Vector3(0, 3.38, 0.02)), BANNER_BLUE, 0.98)
		var trim := PackedVector2Array([Vector2(-0.47, 0.02), Vector2(0.47, 0.02), Vector2(0.47, -0.12), Vector2(-0.47, -0.12)])
		cloth.add_extrusion(trim, 0.04, MeshKit.xf(base + Vector3(0, 3.38, 0.02)), GOLD)
		var star := PackedVector2Array()
		for i in 10:
			var a := TAU * i / 10.0
			var r := 0.26 if i % 2 == 0 else 0.11
			star.append(Vector2(sin(a), cos(a)) * r)
		cloth.add_extrusion(star, 0.045, MeshKit.xf(base + Vector3(0, 2.7, 0.02)), GOLD)
	# Fences along the road north of the gate.
	for side: float in [-1.0, 1.0]:
		var z := z0 - 2.5
		var prev := Vector3.ZERO
		var has_prev := false
		while z > z0 - 16.0:
			var x := road_x(z, bounds) + 3.0 * side
			var post := Vector3(x, 0, z)
			k.add_box(Vector3(0.14, 1.0, 0.14), MeshKit.xf(post + Vector3(0, 0.5, 0), Vector3(0, rng.randf_range(-6, 6), rng.randf_range(-4, 4))), WOOD)
			if has_prev:
				for h: float in [0.45, 0.82]:
					k.add_segment(prev + Vector3(0, h, 0), post + Vector3(0, h, 0), 0.045, 0.045, WOOD.lightened(0.05), 5)
			prev = post
			has_prev = true
			z -= 2.2
	# Farm corner south-west: hay bales and pumpkins behind a fence.
	var farm := Vector3(bounds.position.x - 6.0, 0, bounds.end.y + 5.0)
	for i in 4:
		var p := farm + Vector3(rng.randf_range(-3.0, 3.0), 0, rng.randf_range(-2.0, 2.0))
		k.add_cylinder(0.5, 0.5, 0.9, MeshKit.xf(p + Vector3(0, 0.5, 0), Vector3(90, rng.randf_range(0, 180), 0)), Color(0.92, 0.78, 0.38), 12)
		k.add_torus(0.47, 0.52, MeshKit.xf(p + Vector3(0, 0.5, 0), Vector3(90, 0, 0)), Color(0.75, 0.6, 0.25), 12, 3)
	for i in 9:
		var p := farm + Vector3(rng.randf_range(2.0, 6.5), 0, rng.randf_range(-2.5, 2.5))
		var s := rng.randf_range(0.25, 0.4)
		k.add_sphere(s, MeshKit.xf(p + Vector3(0, s * 0.7, 0), Vector3.ZERO, Vector3(1.15, 0.8, 1.15)), Color(0.95, 0.52, 0.12), 10, 5)
		k.add_cylinder(0.03, 0.04, 0.14, MeshKit.xf(p + Vector3(0, s * 1.35, 0)), Color(0.3, 0.45, 0.15), 5)
	var props := MeshInstance3D.new()
	props.name = "Props"
	props.mesh = k.build()
	props.material_override = Mats.toon_vc()
	root.add_child(props)
	var banners := MeshInstance3D.new()
	banners.name = "Banners"
	banners.mesh = cloth.build()
	banners.material_override = Mats.toon_vc()
	root.add_child(banners)


# --- Grass tufts and flowers (MultiMesh) ---------------------------------------

static func _build_grass(root: Node3D, bounds: Rect2, decor: Rect2, rng: RandomNumberGenerator) -> void:
	var tuft := MeshKit.new()
	for i in 5:
		var a := TAU * i / 5.0
		var base := Vector3(sin(a) * 0.06, 0, cos(a) * 0.06)
		var tip := base * 2.5 + Vector3(0, rng.randf_range(0.22, 0.34), 0)
		tuft.add_segment(base, tip, 0.035, 0.0, Color.WHITE, 4, false)
	var grass_mesh := tuft.build()
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in 1700:
		var inside := i < 260
		var p: Vector2
		if inside:
			p = Vector2(rng.randf_range(bounds.position.x + 0.5, bounds.end.x - 0.5), rng.randf_range(bounds.position.y + 0.5, bounds.end.y - 0.5))
		else:
			p = Vector2(rng.randf_range(decor.position.x, decor.end.x), rng.randf_range(decor.position.y, decor.end.y))
			if bounds.grow(1.2).has_point(p):
				continue
		var s := rng.randf_range(0.7, 1.3) * (0.8 if inside else 1.15)
		points.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * s), Vector3(p.x, 0, p.y)))
		var g := LEAF_GREENS[rng.randi_range(0, LEAF_GREENS.size() - 1)].lightened(rng.randf_range(0.0, 0.2))
		colors.append(g)
	root.add_child(_multimesh("GrassTufts", grass_mesh, points, colors))
	# Flowers: three colours, each a tiny petal cluster with a bright centre.
	var flower_colors: Array[Color] = [Color(1.0, 0.86, 0.25), Color(0.98, 0.97, 0.92), Color(0.75, 0.5, 0.95)]
	for fi in flower_colors.size():
		var fc := flower_colors[fi]
		var fk := MeshKit.new()
		for j in 5:
			var a := TAU * j / 5.0
			fk.add_sphere(0.05, MeshKit.xf(Vector3(sin(a) * 0.05, 0.1, cos(a) * 0.05)), fc, 4, 2)
		fk.add_sphere(0.035, MeshKit.xf(Vector3(0, 0.12, 0)), Color(1.0, 0.7, 0.2) if fc.b > 0.5 else Color(0.95, 0.55, 0.15), 4, 2)
		var fpoints: Array[Transform3D] = []
		var fcols: Array[Color] = []
		for i in 110:
			var p := Vector2(rng.randf_range(decor.position.x, decor.end.x), rng.randf_range(decor.position.y, decor.end.y))
			if i < 14:
				p = Vector2(rng.randf_range(bounds.position.x + 1.0, bounds.end.x - 1.0), rng.randf_range(bounds.position.y + 1.0, bounds.end.y - 1.0))
			elif bounds.grow(1.2).has_point(p):
				continue
			fpoints.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * rng.randf_range(0.8, 1.4)), Vector3(p.x, 0, p.y)))
			fcols.append(Color.WHITE)
		root.add_child(_multimesh("Flowers%d" % fi, fk.build(), fpoints, fcols))


static func _multimesh(n: String, mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	mmi.material_override = Mats.toon_vc(false)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
