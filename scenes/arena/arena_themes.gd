class_name ArenaThemes
extends RefCounted
## The decor sets of the arena environments (GDD 13 / 16.1, M6b ENV): Cemetery, Swamp, Volcano and Ice
## Cave. Same recipe as the forest ([ArenaDecor]): everything is merged into a handful of
## vertex-coloured meshes / MultiMeshes (tall objects in 4 + 4 chunks that the camera can cull, one
## undergrowth mesh, one props mesh, one glow mesh, two MultiMeshes of ground details), so a set costs
## about the forest's draw calls (at most [constant MAX_DRAW_CALLS] mesh instances, a test pins it).
## Decoration stays OUTSIDE the walls, except for flat or knee-high ground details inside; the
## playable rectangle and the camera's view never change. Uses its own seeded RNG (the arena's decor
## seed), never RunState.rng. The placeholder art is primitives only: the final look is M7's.
##
## [method build] is the one entry point ([method Arena._build_decor] calls it): it picks the set by
## [member EnvironmentData.decor_id] and builds the forest ([method ArenaDecor.build]) for any id it
## does not know.

## The most mesh instances a set may add (the forest builds 15; walls and ground are separate).
const MAX_DRAW_CALLS := 16
const GATE := ArenaDecor.GATE_HALF_WIDTH

# Cemetery
const C_STONE := Color(0.5, 0.52, 0.57)
const C_MOSS := Color(0.3, 0.4, 0.3)
const C_BARK := Color(0.27, 0.23, 0.23)
const C_BONE := Color(0.86, 0.83, 0.74)
const C_IRON := Color(0.15, 0.15, 0.19)
const C_DIRT := Color(0.2, 0.16, 0.14)
const C_WISP := Color(0.55, 1.0, 0.85)
# Swamp
const S_BARK := Color(0.25, 0.2, 0.14)
const S_WOOD := Color(0.38, 0.27, 0.17)
const S_WATER := Color(0.12, 0.18, 0.1)
const S_REED := Color(0.5, 0.56, 0.26)
const S_MOSS := Color(0.46, 0.56, 0.3)
const S_LEAVES: Array[Color] = [Color(0.17, 0.31, 0.14), Color(0.21, 0.36, 0.15), Color(0.15, 0.27, 0.13), Color(0.26, 0.38, 0.16)]
const S_FIREFLY := Color(0.82, 1.0, 0.4)
# Volcano
const V_ROCK := Color(0.17, 0.15, 0.16)
const V_ROCK_LIGHT := Color(0.29, 0.23, 0.21)
const V_ASH := Color(0.32, 0.28, 0.27)
const V_IRON := Color(0.13, 0.11, 0.12)
const V_LAVA := Color(1.0, 0.42, 0.1)
# Ice cave
const I_ICE := Color(0.6, 0.82, 0.96)
const I_ICE_LIGHT := Color(0.8, 0.93, 1.0)
const I_ICE_DEEP := Color(0.33, 0.55, 0.82)
const I_SNOW := Color(0.93, 0.96, 1.0)
const I_ROCK := Color(0.4, 0.46, 0.6)
const I_GLOW := Color(0.5, 0.85, 1.0)


## The decor of [param arena] for its environment's decor set.
static func build(arena: Arena, rng: RandomNumberGenerator) -> Node3D:
	match arena.environment.decor_id:
		&"cemetery":
			return _cemetery(arena, rng)
		&"swamp":
			return _swamp(arena, rng)
		&"volcano":
			return _volcano(arena, rng)
		&"ice_cave":
			return _ice_cave(arena, rng)
	return ArenaDecor.build(arena, rng)


## The decor set ids this class builds (everything else is the forest).
static func set_ids() -> Array[StringName]:
	return [&"cemetery", &"swamp", &"volcano", &"ice_cave"]


# =================================================================================================
# Shared builders
# =================================================================================================

## Tall objects in the decor band, chunked like the forest's trees (north, south, west, east; a near
## and a far part each). [param placer] is called as placer(kit, Vector3 base, rng, far).
static func _scatter_tall(root: Node3D, bounds: Rect2, decor: Rect2, rng: RandomNumberGenerator,
		base_name: String, material: Material, dense_p: float, sparse_p: float, placer: Callable,
		cell: float = 3.6) -> void:
	var kits: Array[MeshKit] = []
	for i in 8:
		kits.append(MeshKit.new())
	var y := decor.position.y
	while y < decor.end.y:
		var x := decor.position.x
		while x < decor.end.x:
			var p := Vector2(x + rng.randf_range(0.2, cell - 0.2), y + rng.randf_range(0.2, cell - 0.2))
			var dense := absf(p.x) > bounds.end.x + 5.0 or p.y < bounds.position.y - 5.0 or p.y > bounds.end.y + 11.0
			if ArenaDecor.tree_allowed(p, bounds, decor) and rng.randf() < (dense_p if dense else sparse_p):
				var far := ArenaDecor.distance_outside(p, bounds) > ArenaDecor.FAR_TREE_DISTANCE
				placer.call(kits[ArenaDecor.chunk_of(p, bounds) + (4 if far else 0)], Vector3(p.x, 0.0, p.y), rng, far)
			x += cell
		y += cell
	var names := ["North", "South", "West", "East"]
	for i in kits.size():
		if kits[i].is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = base_name + names[i % 4] + ("Far" if i >= 4 else "")
		mi.mesh = kits[i].build()
		mi.material_override = material
		if i >= 4:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## Calls [param fn](Vector3 point, Vector2 toward_arena) for points along the ring [param grow] metres
## outside [param bounds] (spacing [param lo]..[param hi], none in front of the north gate).
static func _ring_items(bounds: Rect2, rng: RandomNumberGenerator, grow: float, lo: float, hi: float,
		fn: Callable) -> void:
	var ring := bounds.grow(grow)
	var perimeter := 2.0 * (ring.size.x + ring.size.y)
	var d := 0.0
	while d < perimeter:
		var p := ArenaDecor.perimeter_point(ring, d)
		var skip_gate := p.y < bounds.position.y and absf(p.x) < GATE + 2.5
		if not skip_gate:
			fn.call(Vector3(p.x, 0.0, p.y), (-p).normalized())
		d += rng.randf_range(lo, hi)


## A random point of the decor band outside [param skip] (a rect around the arena) and off the road
## corridor north of the gate; Vector2.INF when [param tries] attempts found none.
static func _band_point(bounds: Rect2, decor: Rect2, rng: RandomNumberGenerator, skip: float, tries: int = 6) -> Vector2:
	for _i in tries:
		var p := Vector2(rng.randf_range(decor.position.x, decor.end.x), rng.randf_range(decor.position.y, decor.end.y))
		if bounds.grow(skip).has_point(p):
			continue
		if p.y < bounds.position.y and absf(p.x - ArenaDecor.road_x(p.y, bounds)) < 2.6:
			continue
		return p
	return Vector2.INF


static func _basis(tilt_deg: Vector3, yaw: float) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(tilt_deg.x), yaw, deg_to_rad(tilt_deg.z)))


## A cylinder standing on [param base] (leaning by [param tilt_deg], turned by [param yaw]) whose lower end
## is [param y0] above the base; its top is [param h] higher.
static func _post(k: MeshKit, base: Vector3, tilt_deg: Vector3, yaw: float, r_top: float, r_bot: float,
		h: float, color: Color, radial: int, y0: float = 0.0) -> void:
	var b := _basis(tilt_deg, yaw)
	k.add_cylinder(r_top, r_bot, h, Transform3D(b, base + b * Vector3(0.0, y0 + h * 0.5, 0.0)), color, radial)


static func _glow_mesh(root: Node3D, node_name: String, kit: MeshKit, color: Color, energy: float) -> void:
	if kit.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = kit.build()
	mi.material_override = Mats.glow(color, energy)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _kit_node(root: Node3D, node_name: String, kit: MeshKit, material: Material, shadows: bool = true) -> void:
	if kit.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = kit.build()
	mi.material_override = material
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## A MultiMesh of [param mesh] copies: [param inside] of [param count] lie in the arena (never more
## than knee high), the rest in the decor band. [param tint_fn] gives each copy's colour.
static func _ground_multimesh(root: Node3D, node_name: String, mesh: Mesh, bounds: Rect2, decor: Rect2,
		rng: RandomNumberGenerator, count: int, inside: int, scale_lo: float, scale_hi: float,
		tints: Array[Color], inside_margin: float = 0.5, lighten: float = 0.18) -> void:
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in count:
		var p: Vector2
		if i < inside:
			p = Vector2(rng.randf_range(bounds.position.x + inside_margin, bounds.end.x - inside_margin),
					rng.randf_range(bounds.position.y + inside_margin, bounds.end.y - inside_margin))
		else:
			p = Vector2(rng.randf_range(decor.position.x, decor.end.x), rng.randf_range(decor.position.y, decor.end.y))
			if bounds.grow(1.2).has_point(p):
				continue
		var s := rng.randf_range(scale_lo, scale_hi) * (0.8 if i < inside else 1.15)
		points.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * s), Vector3(p.x, 0.0, p.y)))
		colors.append(tints[rng.randi_range(0, tints.size() - 1)].lightened(rng.randf_range(0.0, lighten)))
	if not points.is_empty():
		root.add_child(ArenaDecor.multimesh(node_name, mesh, points, colors))


## A tuft of [param blades] thin blades (white, tinted per copy by the MultiMesh).
static func _tuft_mesh(rng: RandomNumberGenerator, blades: int, h_lo: float, h_hi: float, spread: float, width: float) -> Mesh:
	var tuft := MeshKit.new()
	for i in blades:
		var a := TAU * float(i) / float(blades)
		var base := Vector3(sin(a) * 0.05, 0.0, cos(a) * 0.05)
		var tip := base * (1.0 + spread) + Vector3(0.0, rng.randf_range(h_lo, h_hi), 0.0)
		tuft.add_segment(base, tip, width, 0.0, Color.WHITE, 4, false)
	return tuft.build()


# =================================================================================================
# Cemetery
# =================================================================================================

static func _cemetery(arena: Arena, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var bounds := arena.get_bounds()
	var decor := arena.get_decor_rect()
	_scatter_tall(root, bounds, decor, rng, "DeadTrees", Mats.toon_vc(true, Color.WHITE, 0.045), 0.5, 0.3, _dead_tree)
	_cemetery_graves(root, bounds, decor, rng)
	_cemetery_props(root, bounds, rng)
	_cemetery_lights(root, bounds, decor, rng)
	# Dead grass tufts and bone scatter (inside only knee high).
	var tufts := _tuft_mesh(rng, 5, 0.18, 0.3, 1.8, 0.03)
	_ground_multimesh(root, "GrassTufts", tufts, bounds, decor, rng, 1100, 170, 0.8, 1.3,
			[Color(0.3, 0.34, 0.25), Color(0.36, 0.38, 0.28), Color(0.25, 0.3, 0.24)])
	_ground_multimesh(root, "Bones", _bones_mesh(), bounds, decor, rng, 110, 12, 0.8, 1.4, [Color(0.8, 0.78, 0.7)], 0.5, 0.0)
	return root


static func _dead_tree(k: MeshKit, p: Vector3, rng: RandomNumberGenerator, far: bool) -> void:
	var h := rng.randf_range(2.4, 4.4)
	var r := rng.randf_range(0.2, 0.32)
	var top := p + Vector3(rng.randf_range(-0.5, 0.5), h, rng.randf_range(-0.5, 0.5))
	var bark := C_BARK.lightened(rng.randf_range(-0.05, 0.12))
	k.add_segment(p + Vector3(0.0, -0.1, 0.0), top, r * 1.4, r * 0.3, bark, 5 if far else 7)
	for i in (3 if far else rng.randi_range(4, 6)):
		var t := rng.randf_range(0.3, 0.95)
		var from := p.lerp(top, t)
		var a := rng.randf_range(0.0, TAU)
		var length := rng.randf_range(0.9, 1.8) * (1.15 - t * 0.55)
		var to := from + Vector3(sin(a) * length, rng.randf_range(0.3, 1.0) * length, cos(a) * length)
		k.add_segment(from, to, r * 0.5 * (1.0 - t * 0.5), r * 0.08, bark, 4)
		if not far and rng.randf() < 0.65:
			var mid := from.lerp(to, 0.6)
			var a2 := a + rng.randf_range(-1.1, 1.1)
			k.add_segment(mid, mid + Vector3(sin(a2), 0.6, cos(a2)) * length * 0.5, r * 0.2, r * 0.04, bark, 4)
	if not far:
		for i in 3:  # root flare
			var a := rng.randf_range(0.0, TAU)
			k.add_segment(p + Vector3(0.0, 0.3, 0.0), p + Vector3(sin(a), 0.0, cos(a)) * r * 2.6, r * 0.6, r * 0.15, bark, 4)


static func _cemetery_graves(root: Node3D, bounds: Rect2, decor: Rect2, rng: RandomNumberGenerator) -> void:
	var k := MeshKit.new()
	# A row of headstones just outside the wall, all facing the arena.
	_ring_items(bounds, rng, 2.7, 1.5, 2.8, func(p: Vector3, toward: Vector2) -> void:
		if rng.randf() < 0.8:
			var jitter := Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
			_gravestone(k, p + jitter, rng, atan2(toward.x, toward.y), p.z > bounds.end.y))
	# Scattered graves, dead bushes, bones and rocks in the band.
	for i in 150:
		var q := _band_point(bounds, decor, rng, 2.2)
		if not q.is_finite():
			continue
		var at := Vector3(q.x, 0.0, q.y)
		var roll := rng.randf()
		if roll < 0.45:
			_gravestone(k, at, rng, rng.randf_range(-0.6, 0.6) + (PI if rng.randf() < 0.5 else 0.0), at.z > bounds.end.y)
		elif roll < 0.62:
			_dead_bush(k, at, rng)
		elif roll < 0.8:
			_bone_pile(k, at, rng)
		else:
			_graveyard_rock(k, at, rng.randf_range(0.35, 0.8), rng)
	_kit_node(root, "Graves", k, Mats.toon_vc(true, Color.WHITE, 0.03))


static func _gravestone(k: MeshKit, p: Vector3, rng: RandomNumberGenerator, yaw: float, low: bool) -> void:
	var kind := rng.randi() % (3 if low else 4)
	var stone := C_STONE.darkened(rng.randf_range(0.0, 0.28))
	if rng.randf() < 0.3:
		stone = stone.lerp(C_MOSS, 0.4)
	var b := _basis(Vector3(rng.randf_range(-9.0, 9.0), 0.0, rng.randf_range(-9.0, 9.0)), yaw)
	var at := func(local: Vector3) -> Vector3: return p + b * local
	match kind:
		0:  # arched headstone
			k.add_box(Vector3(0.7, 0.72, 0.16), Transform3D(b, at.call(Vector3(0.0, 0.36, 0.0))), stone)
			k.add_cylinder(0.35, 0.35, 0.16, Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), at.call(Vector3(0.0, 0.72, 0.0))), stone, 10)
		1:  # cross
			k.add_box(Vector3(0.16, 1.05, 0.14), Transform3D(b, at.call(Vector3(0.0, 0.52, 0.0))), stone)
			k.add_box(Vector3(0.6, 0.15, 0.14), Transform3D(b, at.call(Vector3(0.0, 0.76, 0.0))), stone)
		2:  # square slab with a cap
			k.add_box(Vector3(0.62, 0.55, 0.2), Transform3D(b, at.call(Vector3(0.0, 0.27, 0.0))), stone)
			k.add_box(Vector3(0.74, 0.1, 0.28), Transform3D(b, at.call(Vector3(0.0, 0.6, 0.0))), stone.lightened(0.06))
		_:  # obelisk
			k.add_box(Vector3(0.6, 0.18, 0.6), Transform3D(b, at.call(Vector3(0.0, 0.09, 0.0))), stone.darkened(0.08))
			k.add_cylinder(0.09, 0.24, 1.4, Transform3D(b * Basis(Vector3.UP, PI * 0.25), at.call(Vector3(0.0, 0.88, 0.0))), stone, 4)
	# The grave mound in front of it.
	k.add_sphere(0.5, Transform3D(b.scaled(Vector3(1.0, 0.3, 1.5)), at.call(Vector3(0.0, 0.0, 0.62))), C_DIRT.lerp(C_MOSS, rng.randf_range(0.0, 0.4)), 8, 4)


static func _dead_bush(k: MeshKit, p: Vector3, rng: RandomNumberGenerator) -> void:
	var bark := C_BARK.lightened(0.05)
	for i in rng.randi_range(5, 8):
		var a := rng.randf_range(0.0, TAU)
		var length := rng.randf_range(0.5, 1.0)
		var tip := p + Vector3(sin(a) * length * 0.6, rng.randf_range(0.5, 1.0) * length, cos(a) * length * 0.6)
		k.add_segment(p, tip, 0.04, 0.0, bark, 4, false)


static func _bone_pile(k: MeshKit, p: Vector3, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(3, 6):
		var a := rng.randf_range(0.0, TAU)
		var q := p + Vector3(sin(a), 0.0, cos(a)) * rng.randf_range(0.0, 0.5)
		var dir := Vector3(sin(a * 2.3), 0.1, cos(a * 1.7)).normalized()
		k.add_segment(q, q + dir * rng.randf_range(0.35, 0.6), 0.045, 0.045, C_BONE.darkened(rng.randf_range(0.0, 0.2)), 5)
	if rng.randf() < 0.6:
		k.add_sphere(0.17, MeshKit.xf(p + Vector3(0.1, 0.14, 0.05), Vector3.ZERO, Vector3(1.0, 0.9, 1.1)), C_BONE, 8, 4)
		k.add_box(Vector3(0.12, 0.09, 0.1), MeshKit.xf(p + Vector3(0.1, 0.06, 0.18)), C_BONE.darkened(0.1))


static func _graveyard_rock(k: MeshKit, p: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var c := C_STONE.darkened(rng.randf_range(0.1, 0.3))
	var rot := Vector3(rng.randf_range(-15.0, 15.0), rng.randf_range(0.0, 360.0), rng.randf_range(-15.0, 15.0))
	k.add_sphere(size, MeshKit.xf(p + Vector3(0.0, size * 0.3, 0.0), rot, Vector3(1.25, 0.7, 1.0)), c, 7, 4)


## A little pile of bones (a MultiMesh copy).
static func _bones_mesh() -> Mesh:
	return MeshKit.cached("theme:bones", func() -> Mesh:
		var k := MeshKit.new()
		k.add_segment(Vector3(-0.12, 0.04, 0.0), Vector3(0.14, 0.05, 0.06), 0.03, 0.03, C_BONE, 5)
		k.add_segment(Vector3(-0.05, 0.04, -0.1), Vector3(0.1, 0.04, -0.16), 0.025, 0.025, C_BONE.darkened(0.1), 5)
		k.add_sphere(0.075, MeshKit.xf(Vector3(0.18, 0.08, -0.05), Vector3.ZERO, Vector3(1.0, 0.9, 1.1)), C_BONE, 7, 4)
		k.add_sphere(0.04, MeshKit.xf(Vector3(-0.15, 0.04, 0.02)), C_BONE.darkened(0.05), 5, 3)
		return k.build())


static func _cemetery_props(root: Node3D, bounds: Rect2, rng: RandomNumberGenerator) -> void:
	var k := MeshKit.new()
	var z0 := bounds.position.y - ArenaDecor.WALL_OFFSET
	# The crypt, north-west, facing the arena (south).
	_crypt(k, Vector3(bounds.position.x - 7.5, 0.0, bounds.position.y - 9.0), 0.0)
	_crypt(k, Vector3(bounds.end.x + 9.0, 0.0, bounds.end.y - 6.0), PI * 0.5, 0.6)
	# Iron fences with stone posts along the road north of the gate.
	for side: float in [-1.0, 1.0]:
		var z := z0 - 2.5
		var prev := Vector3.ZERO
		var has_prev := false
		while z > z0 - 16.0:
			var post := Vector3(ArenaDecor.road_x(z, bounds) + 3.0 * side, 0.0, z)
			k.add_box(Vector3(0.3, 1.2, 0.3), MeshKit.xf(post + Vector3(0.0, 0.6, 0.0), Vector3(0.0, rng.randf_range(-8.0, 8.0), rng.randf_range(-4.0, 4.0))), C_STONE.darkened(0.12))
			k.add_cylinder(0.0, 0.2, 0.22, MeshKit.xf(post + Vector3(0.0, 1.3, 0.0), Vector3(0.0, 45.0, 0.0)), C_STONE, 4)
			if has_prev:
				for h: float in [0.5, 1.0]:
					k.add_segment(prev + Vector3(0.0, h, 0.0), post + Vector3(0.0, h, 0.0), 0.035, 0.035, C_IRON, 5)
				for f in 4:  # spears between the posts
					var q := prev.lerp(post, (float(f) + 0.5) / 4.0)
					k.add_cylinder(0.0, 0.05, 0.28, MeshKit.xf(q + Vector3(0.0, 1.14, 0.0)), C_IRON, 4)
					k.add_segment(q, q + Vector3(0.0, 1.0, 0.0), 0.022, 0.022, C_IRON, 4, false)
			prev = post
			has_prev = true
			z -= 2.3
	# Lantern posts flanking the gate (their flames are the glow mesh's).
	for side: float in [-1.0, 1.0]:
		var base := Vector3((GATE + 1.8) * side, 0.0, z0 - 1.0)
		k.add_cylinder(0.05, 0.08, 2.8, MeshKit.xf(base + Vector3(0.0, 1.4, 0.0)), C_IRON, 6)
		k.add_box(Vector3(0.34, 0.4, 0.34), MeshKit.xf(base + Vector3(0.0, 2.95, 0.0)), C_IRON.lightened(0.05))
		k.add_cylinder(0.0, 0.3, 0.3, MeshKit.xf(base + Vector3(0.0, 3.3, 0.0), Vector3(0.0, 45.0, 0.0)), C_IRON, 4)
	_kit_node(root, "Props", k, Mats.toon_vc())


## A mausoleum with its front towards +Z (turned by [param yaw]); [param s] scales it.
static func _crypt(k: MeshKit, p: Vector3, yaw: float, s: float = 1.0) -> void:
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
	var at := func(local: Vector3) -> Vector3: return p + b * local
	var wall := C_STONE.darkened(0.1)
	k.add_box(Vector3(5.6, 0.5, 4.6), Transform3D(b, at.call(Vector3(0.0, 0.25, 0.0))), wall.darkened(0.15))
	k.add_box(Vector3(5.0, 3.0, 4.0), Transform3D(b, at.call(Vector3(0.0, 2.0, 0.0))), wall)
	var gable := PackedVector2Array([Vector2(-2.9, 0.0), Vector2(2.9, 0.0), Vector2(0.0, 1.7)])
	k.add_extrusion(gable, 4.6, Transform3D(b, at.call(Vector3(0.0, 3.5, 0.0))), wall.darkened(0.2))
	k.add_box(Vector3(1.3, 2.1, 0.3), Transform3D(b, at.call(Vector3(0.0, 1.55, 2.0))), Color(0.04, 0.04, 0.06))
	k.add_box(Vector3(1.7, 0.25, 0.5), Transform3D(b, at.call(Vector3(0.0, 2.7, 2.1))), wall.lightened(0.08))
	for side: float in [-1.0, 1.0]:
		k.add_cylinder(0.24, 0.28, 3.0, Transform3D(b, at.call(Vector3(2.2 * side, 2.0, 2.3))), wall.lightened(0.05), 8)
	for step in 3:
		k.add_box(Vector3(2.6 + step * 0.5, 0.18, 0.6), Transform3D(b, at.call(Vector3(0.0, 0.42 - step * 0.13, 2.6 + step * 0.35))), wall.lightened(0.03))
	k.add_box(Vector3(0.14, 1.2, 0.14), Transform3D(b, at.call(Vector3(0.0, 5.7, 0.0))), wall.lightened(0.1))
	k.add_box(Vector3(0.7, 0.14, 0.14), Transform3D(b, at.call(Vector3(0.0, 5.9, 0.0))), wall.lightened(0.1))


static func _cemetery_lights(root: Node3D, bounds: Rect2, decor: Rect2, rng: RandomNumberGenerator) -> void:
	var k := MeshKit.new()
	var z0 := bounds.position.y - ArenaDecor.WALL_OFFSET
	for side: float in [-1.0, 1.0]:  # the gate lanterns
		k.add_sphere(0.14, MeshKit.xf(Vector3((GATE + 1.8) * side, 2.95, z0 - 1.0)), Color.WHITE, 8, 4)
	# Crypt door lamps.
	k.add_sphere(0.16, MeshKit.xf(Vector3(bounds.position.x - 7.5 - 1.6, 2.4, bounds.position.y - 9.0 + 2.6)), Color.WHITE, 8, 4)
	k.add_sphere(0.16, MeshKit.xf(Vector3(bounds.position.x - 7.5 + 1.6, 2.4, bounds.position.y - 9.0 + 2.6)), Color.WHITE, 8, 4)
	# Wisps and candle flames.
	for i in 40:
		var q := _band_point(bounds, decor, rng, 1.8)
		if not q.is_finite():
			continue
		var wisp := rng.randf() < 0.55
		var y := rng.randf_range(0.5, 1.9) if wisp else 0.2
		k.add_sphere(0.1 if wisp else 0.06, MeshKit.xf(Vector3(q.x, y, q.y), Vector3.ZERO, Vector3(1.0, 1.3, 1.0)), Color.WHITE, 6, 3)
	_glow_mesh(root, "Wisps", k, C_WISP, 1.9)


# =================================================================================================
# Swamp
# =================================================================================================

static func _swamp(arena: Arena, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var bounds := arena.get_bounds()
	var decor := arena.get_decor_rect()
	_scatter_tall(root, bounds, decor, rng, "Mangroves", Mats.toon_vc(true, Color.WHITE, 0.045), 0.8, 0.5, _mangrove)
	_swamp_undergrowth(root, bounds, decor, rng)
	_swamp_props(root, bounds, rng)
	_swamp_lights(root, bounds, decor, rng)
	var reeds := _reed_mesh(rng)
	_ground_multimesh(root, "Reeds", reeds, bounds, decor, rng, 520, 0, 0.8, 1.5,
			[Color(0.42, 0.5, 0.22), Color(0.5, 0.56, 0.26), Color(0.34, 0.44, 0.2)], 0.9)
	var tufts := _tuft_mesh(rng, 5, 0.2, 0.34, 2.0, 0.035)
	_ground_multimesh(root, "GrassTufts", tufts, bounds, decor, rng, 1000, 150, 0.8, 1.3,
			[Color(0.24, 0.36, 0.16), Color(0.3, 0.42, 0.18), Color(0.2, 0.3, 0.14)])
	return root


static func _mangrove(k: MeshKit, p: Vector3, rng: RandomNumberGenerator, far: bool) -> void:
	var lift := rng.randf_range(0.9, 1.4)
	var h := rng.randf_range(1.1, 1.9)
	var r := rng.randf_range(0.2, 0.3)
	var top := p + Vector3(rng.randf_range(-0.3, 0.3), lift + h, rng.randf_range(-0.3, 0.3))
	var bark := S_BARK.lightened(rng.randf_range(-0.03, 0.1))
	k.add_segment(p + Vector3(0.0, lift - 0.2, 0.0), top, r, r * 0.65, bark, 5 if far else 7)
	# Stilt roots arching down into the mud (the tree stands on them).
	for i in (4 if far else rng.randi_range(6, 8)):
		var a := TAU * float(i) / 7.0 + rng.randf_range(-0.3, 0.3)
		var out := rng.randf_range(1.0, 1.9)
		var from := p + Vector3(sin(a) * r * 0.5, lift + rng.randf_range(-0.1, 0.3), cos(a) * r * 0.5)
		var mid := p + Vector3(sin(a) * out * 0.7, lift * rng.randf_range(0.7, 1.05), cos(a) * out * 0.7)
		var foot := p + Vector3(sin(a) * out, -0.1, cos(a) * out)
		k.add_segment(from, mid, r * 0.5, r * 0.36, bark, 4)
		k.add_segment(mid, foot, r * 0.36, r * 0.15, bark, 4)
	# A broad, flat, drooping canopy.
	var base := S_LEAVES[rng.randi_range(0, S_LEAVES.size() - 1)]
	var canopy := top + Vector3(0.0, 0.25, 0.0)
	var size := rng.randf_range(1.3, 1.9)
	var radial := 8 if far else 11
	k.add_sphere(size, MeshKit.xf(canopy, Vector3.ZERO, Vector3(1.3, 0.5, 1.3)), base.darkened(0.06), radial, 4)
	for i in (3 if far else 5):
		var a := TAU * float(i) / 5.0 + rng.randf_range(-0.5, 0.5)
		var off := Vector3(sin(a), -0.1, cos(a)) * size * 0.9
		k.add_sphere(size * rng.randf_range(0.5, 0.75), MeshKit.xf(canopy + off, Vector3.ZERO, Vector3(1.2, 0.5, 1.2)),
				base.lightened(rng.randf_range(-0.03, 0.12)), radial - 1, 4)
		if not far:  # hanging moss
			for m in 2:
				var mp := canopy + off + Vector3(rng.randf_range(-0.5, 0.5), -0.2, rng.randf_range(-0.5, 0.5))
				k.add_segment(mp, mp + Vector3(0.0, -rng.randf_range(0.7, 1.4), 0.0), 0.02, 0.07, S_MOSS, 4, false)


static func _swamp_undergrowth(root: Node3D, bounds: Rect2, decor: Rect2, rng: RandomNumberGenerator) -> void:
	var k := MeshKit.new()
	# Murky pools beyond the walls with lily pads.
	for i in 16:
		var q := _band_point(bounds, decor, rng, 3.6, 10)
		if not q.is_finite():
			continue
		var r := rng.randf_range(1.2, 3.2)
		k.add_cylinder(r, r, 0.05, MeshKit.xf(Vector3(q.x, 0.03, q.y), Vector3.ZERO, Vector3(1.0, 1.0, rng.randf_range(0.6, 1.0))), S_WATER.lightened(rng.randf_range(0.0, 0.06)), 14)
		k.add_cylinder(r * 1.12, r * 1.12, 0.03, MeshKit.xf(Vector3(q.x, 0.015, q.y), Vector3.ZERO, Vector3(1.0, 1.0, 0.85)), S_WATER.lerp(S_BARK, 0.5), 14)
		for pad in rng.randi_range(2, 5):
			var a := rng.randf_range(0.0, TAU)
			var pr := rng.randf_range(0.2, 0.35)
			k.add_cylinder(pr, pr, 0.02, MeshKit.xf(Vector3(q.x + sin(a) * r * 0.6, 0.07, q.y + cos(a) * r * 0.5)), S_LEAVES[pad % S_LEAVES.size()].lightened(0.1), 8)
	# Reed clumps hugging the wall, mounds, logs, mushrooms and skulls in the band.
	_ring_items(bounds, rng, 1.8, 2.0, 3.4, func(p: Vector3, _toward: Vector2) -> void:
		if rng.randf() < 0.75:
			_reed_clump(k, p + Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4)), rng, p.z > bounds.end.y))
	for i in 120:
		var q := _band_point(bounds, decor, rng, 2.2)
		if not q.is_finite():
			continue
		var at := Vector3(q.x, 0.0, q.y)
		var roll := rng.randf()
		if roll < 0.4:
			_reed_clump(k, at, rng, at.z > bounds.end.y)
		elif roll < 0.6:
			var s := rng.randf_range(0.5, 1.1)
			k.add_sphere(s, MeshKit.xf(at + Vector3(0.0, s * 0.1, 0.0), Vector3.ZERO, Vector3(1.4, 0.4, 1.1)), S_BARK.lerp(S_MOSS, rng.randf_range(0.0, 0.5)), 8, 4)
		elif roll < 0.78:  # a fallen log
			var a := rng.randf_range(0.0, PI)
			var dir := Vector3(sin(a), 0.0, cos(a))
			k.add_segment(at - dir * 1.1 + Vector3(0.0, 0.2, 0.0), at + dir * 1.1 + Vector3(0.0, 0.2, 0.0), 0.2, 0.17, S_BARK, 6)
			k.add_sphere(0.19, MeshKit.xf(at + dir * 1.12 + Vector3(0.0, 0.2, 0.0), Vector3.ZERO, Vector3(0.5, 1.0, 1.0)), S_WOOD.lightened(0.15), 6, 3)
		else:  # toadstools
			for m in rng.randi_range(2, 4):
				var mq := at + Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))
				var ms := rng.randf_range(0.6, 1.2)
				k.add_cylinder(0.05 * ms, 0.07 * ms, 0.25 * ms, MeshKit.xf(mq + Vector3(0.0, 0.12 * ms, 0.0)), Color(0.85, 0.82, 0.7), 6)
				k.add_sphere(0.17 * ms, MeshKit.xf(mq + Vector3(0.0, 0.25 * ms, 0.0), Vector3.ZERO, Vector3(1.0, 0.7, 1.0)), Color(0.55, 0.75, 0.25), 8, 4, true)
	_kit_node(root, "Undergrowth", k, Mats.toon_vc(true, Color.WHITE, 0.03))


static func _reed_clump(k: MeshKit, p: Vector3, rng: RandomNumberGenerator, low: bool) -> void:
	var n := rng.randi_range(5, 9)
	for i in n:
		var a := rng.randf_range(0.0, TAU)
		var base := p + Vector3(sin(a), 0.0, cos(a)) * rng.randf_range(0.0, 0.35)
		var h := rng.randf_range(0.7, 1.1) if low else rng.randf_range(1.0, 2.1)
		var tip := base + Vector3(sin(a) * 0.25, h, cos(a) * 0.25)
		var col := S_REED.darkened(rng.randf_range(0.0, 0.25))
		k.add_segment(base, tip, 0.03, 0.0, col, 4, false)
		if not low and rng.randf() < 0.3:  # cattail head
			k.add_segment(base.lerp(tip, 0.8), base.lerp(tip, 0.93), 0.06, 0.05, Color(0.34, 0.2, 0.1), 5)


static func _reed_mesh(rng: RandomNumberGenerator) -> Mesh:
	var k := MeshKit.new()
	for i in 6:
		var a := TAU * float(i) / 6.0
		var base := Vector3(sin(a) * 0.1, 0.0, cos(a) * 0.1)
		k.add_segment(base, base + Vector3(sin(a) * 0.3, rng.randf_range(0.8, 1.5), cos(a) * 0.3), 0.03, 0.0, Color.WHITE, 4, false)
	return k.build()


static func _swamp_props(root: Node3D, bounds: Rect2, rng: RandomNumberGenerator) -> void:
	var k := MeshKit.new()
	var z0 := bounds.position.y - ArenaDecor.WALL_OFFSET
	# A stilt hut, north-east, facing the arena.
	_hut(k, Vector3(bounds.end.x + 8.5, 0.0, bounds.position.y - 6.0), -0.35)
	# A rickety pier running out from the east wall into the dark.
	var pier := Vector3(bounds.end.x + 1.4, 0.0, bounds.end.y - 4.0)
	for i in 9:
		var p := pier + Vector3(1.0 * i, 0.0, 0.0)
		k.add_box(Vector3(0.9, 0.08, 1.5), MeshKit.xf(p + Vector3(0.0, 0.55, 0.0), Vector3(0.0, rng.randf_range(-4.0, 4.0), rng.randf_range(-2.0, 2.0))), S_WOOD.darkened(rng.randf_range(0.0, 0.2)))
		if i % 2 == 0:
			for side: float in [-1.0, 1.0]:
				k.add_cylinder(0.07, 0.09, 0.9, MeshKit.xf(p + Vector3(0.0, 0.2, 0.7 * side)), S_BARK, 5)
	# Hanging lantern posts at the gate (the flames are the glow mesh's).
	for side: float in [-1.0, 1.0]:
		var base := Vector3((GATE + 1.8) * side, 0.0, z0 - 1.0)
		k.add_cylinder(0.07, 0.1, 3.2, MeshKit.xf(base + Vector3(0.0, 1.6, 0.0), Vector3(0.0, 0.0, 4.0 * side)), S_BARK, 6)
		k.add_segment(base + Vector3(0.0, 3.1, 0.0), base + Vector3(-0.5 * side, 3.1, 0.0), 0.04, 0.04, S_BARK, 5)
		k.add_box(Vector3(0.3, 0.38, 0.3), MeshKit.xf(base + Vector3(-0.5 * side, 2.8, 0.0)), S_WOOD.darkened(0.2))
	# Tattered flags on poles.
	for side: float in [-1.0, 1.0]:
		var base := Vector3((GATE + 4.2) * side, 0.0, z0 - 2.0)
		k.add_cylinder(0.05, 0.07, 3.4, MeshKit.xf(base + Vector3(0.0, 1.7, 0.0)), S_BARK, 5)
		var flag := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.9, -0.1), Vector2(0.7, -0.6), Vector2(0.95, -1.1), Vector2(0.0, -1.2)])
		k.add_extrusion(flag, 0.03, MeshKit.xf(base + Vector3(0.0, 3.3, 0.0)), Color(0.28, 0.34, 0.18))
	_kit_node(root, "Props", k, Mats.toon_vc())


static func _hut(k: MeshKit, p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var at := func(local: Vector3) -> Vector3: return p + b * local
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.add_cylinder(0.14, 0.17, 2.0, Transform3D(b, at.call(Vector3(1.4 * sx, 1.0, 1.3 * sz))), S_BARK, 6)
	k.add_box(Vector3(3.6, 0.16, 3.3), Transform3D(b, at.call(Vector3(0.0, 2.0, 0.0))), S_WOOD)
	k.add_box(Vector3(2.8, 1.7, 2.5), Transform3D(b, at.call(Vector3(0.0, 2.95, -0.1))), S_WOOD.darkened(0.12))
	k.add_cylinder(0.0, 2.55, 1.5, Transform3D(b * Basis(Vector3.UP, PI * 0.25), at.call(Vector3(0.0, 4.55, -0.1))), Color(0.4, 0.38, 0.2), 4)
	k.add_box(Vector3(0.9, 1.3, 0.12), Transform3D(b, at.call(Vector3(0.0, 2.75, 1.2))), Color(0.07, 0.05, 0.04))
	k.add_box(Vector3(0.6, 0.5, 0.12), Transform3D(b, at.call(Vector3(-0.85, 3.2, 1.2))), Color(0.9, 0.75, 0.3).darkened(0.3))
	for rung in 5:  # ladder
		k.add_box(Vector3(0.7, 0.06, 0.06), Transform3D(b, at.call(Vector3(0.0, 0.3 + rung * 0.4, 1.9 - rung * 0.04))), S_WOOD.lightened(0.05))
	for side: float in [-1.0, 1.0]:
		k.add_segment(at.call(Vector3(0.35 * side, 0.0, 1.95)), at.call(Vector3(0.35 * side, 2.0, 1.75)), 0.04, 0.04, S_BARK, 4)


static func _swamp_lights(root: Node3D, bounds: Rect2, decor: Rect2, rng: RandomNumberGenerator) -> void:
	var k := MeshKit.new()
	var z0 := bounds.position.y - ArenaDecor.WALL_OFFSET
	for side: float in [-1.0, 1.0]:
		k.add_sphere(0.12, MeshKit.xf(Vector3((GATE + 1.8) * side - 0.5 * side, 2.8, z0 - 1.0)), Color.WHITE, 8, 4)
	for i in 70:
		var q := _band_point(bounds, decor, rng, 1.5)
		if not q.is_finite():
			continue
		k.add_sphere(0.05 + 0.04 * rng.randf(), MeshKit.xf(Vector3(q.x, rng.randf_range(0.4, 2.4), q.y)), Color.WHITE, 5, 3)
	_glow_mesh(root, "Fireflies", k, S_FIREFLY, 2.1)


# =================================================================================================
# Volcano
# =================================================================================================

static func _volcano(arena: Arena, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var bounds := arena.get_bounds()
	var decor := arena.get_decor_rect()
	_scatter_tall(root, bounds, decor, rng, "Basalt", Mats.toon_vc(true, Color.WHITE, 0.045), 0.75, 0.42, _basalt_cluster)
	_volcano_undergrowth(root, bounds, decor, rng)
	_volcano_props(root, bounds, rng)
	_volcano_glow(root, bounds, decor, rng)
	var shards := MeshKit.cached("theme:ash_chips", func() -> Mesh:
		var k := MeshKit.new()
		for i in 5:
			var a := TAU * float(i) / 5.0
			k.add_box(Vector3(0.1, 0.06, 0.16), MeshKit.xf(Vector3(sin(a) * 0.12, 0.03, cos(a) * 0.12), Vector3(0.0, rad_to_deg(a), 8.0 * float(i % 2))), Color.WHITE)
		return k.build())
	_ground_multimesh(root, "AshChips", shards, bounds, decor, rng, 900, 120, 0.7, 1.4,
			[Color(0.18, 0.15, 0.14), Color(0.23, 0.18, 0.16), Color(0.13, 0.11, 0.11)], 0.5, 0.05)
	var tufts := _tuft_mesh(rng, 4, 0.14, 0.24, 1.6, 0.03)
	_ground_multimesh(root, "Embers", tufts, bounds, decor, rng, 380, 30, 0.7, 1.2,
			[Color(0.42, 0.2, 0.1), Color(0.5, 0.26, 0.12)])
	return root


static func _basalt_cluster(k: MeshKit, p: Vector3, rng: RandomNumberGenerator, far: bool) -> void:
	var cols := rng.randi_range(3, 5) if not far else 3
	var spread := rng.randf_range(0.9, 1.6)
	var tall := rng.randf_range(0.6, 1.4)
	for i in cols:
		var a := TAU * float(i) / float(cols) + rng.randf_range(-0.4, 0.4)
		var off := Vector3(sin(a), 0.0, cos(a)) * (spread * rng.randf_range(0.3, 1.0) if i > 0 else 0.0)
		var h := rng.randf_range(1.4, 4.2) * tall * (1.0 if i > 0 else 1.3)
		var r := rng.randf_range(0.34, 0.6)
		var col := V_ROCK.lerp(V_ROCK_LIGHT, rng.randf_range(0.0, 0.8))
		var tilt := Vector3(rng.randf_range(-7.0, 7.0), 0.0, rng.randf_range(-7.0, 7.0))
		_post(k, p + off, tilt, rng.randf_range(0.0, PI), r * 0.88, r, h, col, 6)
		if not far and rng.randf() < 0.45:  # a jagged top
			_post(k, p + off, tilt, rng.randf_range(0.0, PI), 0.0, r * 0.88, r * 1.1, col.lightened(0.06), 6, h)
	if rng.randf() < 0.3 and not far:  # a spire beside it
		var a := rng.randf_range(0.0, TAU)
		var q := p + Vector3(sin(a), 0.0, cos(a)) * (spread + 0.9)
		_post(k, q, Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-6.0, 6.0)), 0.0, 0.0, 0.5, rng.randf_range(3.5, 6.0), V_ROCK, 5)


static func _volcano_undergrowth(root: Node3D, bounds: Rect2, decor: Rect2, rng: RandomNumberGenerator) -> void:
	var k := MeshKit.new()
	_ring_items(bounds, rng, 1.8, 1.8, 3.2, func(p: Vector3, _toward: Vector2) -> void:
		if rng.randf() < 0.75:
			_basalt_boulder(k, p + Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4)), rng.randf_range(0.5, 1.0), rng))
	for i in 130:
		var q := _band_point(bounds, decor, rng, 2.2)
		if not q.is_finite():
			continue
		var at := Vector3(q.x, 0.0, q.y)
		var roll := rng.randf()
		if roll < 0.5:
			_basalt_boulder(k, at, rng.randf_range(0.4, 1.0), rng)
		elif roll < 0.72:  # an ash mound
			var s := rng.randf_range(0.6, 1.4)
			k.add_sphere(s, MeshKit.xf(at + Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(1.3, 0.28, 1.1)), V_ASH.darkened(rng.randf_range(0.0, 0.3)), 8, 4)
		elif roll < 0.88:  # obsidian shards
			for s in rng.randi_range(2, 4):
				var sq := at + Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
				_post(k, sq, Vector3(rng.randf_range(-20.0, 20.0), 0.0, rng.randf_range(-20.0, 20.0)), rng.randf_range(0.0, PI), 0.0, 0.14, rng.randf_range(0.5, 1.0), Color(0.08, 0.07, 0.1), 4)
		else:  # a horned skull
			k.add_sphere(0.22, MeshKit.xf(at + Vector3(0.0, 0.2, 0.0), Vector3.ZERO, Vector3(1.0, 0.85, 1.2)), C_BONE.darkened(0.25), 8, 4)
			for side: float in [-1.0, 1.0]:
				k.add_cylinder(0.0, 0.07, 0.4, MeshKit.xf(at + Vector3(0.22 * side, 0.4, 0.0), Vector3(0.0, 0.0, -35.0 * side)), C_BONE.darkened(0.3), 5)
	_kit_node(root, "Undergrowth", k, Mats.toon_vc(true, Color.WHITE, 0.03))


static func _basalt_boulder(k: MeshKit, p: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var c := V_ROCK.lerp(V_ROCK_LIGHT, rng.randf_range(0.0, 0.7))
	var rot := Vector3(rng.randf_range(-15.0, 15.0), rng.randf_range(0.0, 360.0), rng.randf_range(-15.0, 15.0))
	k.add_sphere(size, MeshKit.xf(p + Vector3(0.0, size * 0.3, 0.0), rot, Vector3(1.2, 0.72, 1.0)), c, 6, 3)
	if rng.randf() < 0.5:
		k.add_sphere(size * 0.55, MeshKit.xf(p + Vector3(size * 0.8, size * 0.15, size * 0.3), rot, Vector3(1.2, 0.7, 1.0)), c.lightened(0.05), 6, 3)


static func _volcano_props(root: Node3D, bounds: Rect2, rng: RandomNumberGenerator) -> void:
	var k := MeshKit.new()
	var z0 := bounds.position.y - ArenaDecor.WALL_OFFSET
	# Iron braziers flanking the gate (the fire is the glow mesh's).
	for side: float in [-1.0, 1.0]:
		var base := Vector3((GATE + 1.8) * side, 0.0, z0 - 1.0)
		for leg in 3:
			var a := TAU * float(leg) / 3.0
			k.add_segment(base + Vector3(sin(a) * 0.45, 0.0, cos(a) * 0.45), base + Vector3(0.0, 1.3, 0.0), 0.05, 0.05, V_IRON, 5)
		k.add_cylinder(0.55, 0.32, 0.4, MeshKit.xf(base + Vector3(0.0, 1.45, 0.0)), V_IRON.lightened(0.05), 10)
	# The ribs of some huge beast, west of the arena.
	var spine := Vector3(bounds.position.x - 9.0, 0.0, 2.0)
	for i in 7:
		var z := spine.z + float(i - 3) * 1.5
		var h := 3.6 - absf(float(i - 3)) * 0.35
		var prev := Vector3(spine.x, 0.0, z)
		for s in 8:
			var t := float(s + 1) / 8.0
			var a := t * PI * 0.55
			var q := Vector3(spine.x + (1.0 - cos(a)) * 2.4, sin(a) * h, z + t * 0.4)
			k.add_segment(prev, q, 0.2 * (1.0 - t * 0.6), 0.2 * (1.0 - (t + 0.125) * 0.6), C_BONE.darkened(0.3), 5)
			prev = q
	k.add_segment(Vector3(spine.x, 0.0, spine.z - 5.0), Vector3(spine.x, 0.1, spine.z + 5.0), 0.3, 0.3, C_BONE.darkened(0.35), 6)
	# Broken obsidian pillars north-east.
	for i in 3:
		var base := Vector3(bounds.end.x + 7.0 + i * 2.6, 0.0, bounds.position.y - 4.0 - i * 1.5)
		_post(k, base, Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-6.0, 6.0)), 0.0, 0.5, 0.65, 3.0 + i * 0.9, Color(0.09, 0.08, 0.11), 6)
		_post(k, base, Vector3.ZERO, 0.0, 0.0, 0.5, 0.7, Color(0.09, 0.08, 0.11), 6, 3.0 + i * 0.9)
	# The vents inside the arena: a low basalt rim and a dark crust (the glow mesh adds the cores).
	for v in EnvironmentHazards.LAVA_VENT_POINTS:
		k.add_cylinder(1.35, 1.35, 0.05, MeshKit.xf(v + Vector3(0.0, 0.03, 0.0)), Color(0.07, 0.05, 0.06), 14)
		for i in 9:
			var a := TAU * float(i) / 9.0 + rng.randf_range(-0.15, 0.15)
			var rr := rng.randf_range(0.95, 1.25)
			k.add_sphere(rng.randf_range(0.2, 0.32), MeshKit.xf(v + Vector3(sin(a) * rr, 0.08, cos(a) * rr), Vector3.ZERO, Vector3(1.0, 0.55, 1.0)),
					V_ROCK.lerp(V_ROCK_LIGHT, rng.randf_range(0.0, 0.6)), 6, 3)
	_kit_node(root, "Props", k, Mats.toon_vc())


## Lava: the vents' cores and cracks inside the arena, rivers beyond the walls, floating embers.
static func _volcano_glow(root: Node3D, bounds: Rect2, decor: Rect2, rng: RandomNumberGenerator) -> void:
	var k := MeshKit.new()
	var z0 := bounds.position.y - ArenaDecor.WALL_OFFSET
	for v in EnvironmentHazards.LAVA_VENT_POINTS:
		k.add_cylinder(0.78, 0.78, 0.04, MeshKit.xf(v + Vector3(0.0, 0.07, 0.0)), Color.WHITE, 12)
		# Cracks radiating from the vent.
		for i in 5:
			var a := TAU * float(i) / 5.0 + rng.randf_range(-0.3, 0.3)
			var prev := v + Vector3(sin(a), 0.0, cos(a)) * 0.9
			for s in 3:
				var a2 := a + rng.randf_range(-0.45, 0.45)
				var q := prev + Vector3(sin(a2), 0.0, cos(a2)) * rng.randf_range(0.6, 1.1)
				if not bounds.grow(-0.4).has_point(Vector2(q.x, q.z)):
					break
				k.add_segment(prev + Vector3(0.0, 0.04, 0.0), q + Vector3(0.0, 0.04, 0.0), 0.05 - s * 0.01, 0.04 - s * 0.01, Color.WHITE, 4, false)
				prev = q
	# Two lava rivers winding beyond the north and south-west walls.
	for river in 2:
		var start := Vector3(bounds.position.x - 3.0, 0.0, bounds.position.y - 4.5) if river == 0 else Vector3(bounds.end.x + 3.0, 0.0, bounds.end.y - 2.0)
		var heading := Vector3(1.0, 0.0, -0.1) if river == 0 else Vector3(0.0, 0.0, -1.0)
		if river == 0:
			start = Vector3(bounds.position.x - 1.0, 0.0, bounds.position.y - 5.5)
		var prev := start
		var dir := heading.normalized()
		for s in 26:
			dir = dir.rotated(Vector3.UP, sin(float(s) * 0.55 + float(river) * 2.0) * 0.28).normalized()
			var q := prev + dir * 1.6
			k.add_segment(prev + Vector3(0.0, 0.03, 0.0), q + Vector3(0.0, 0.03, 0.0), 0.5 + 0.2 * sin(float(s) * 0.9), 0.5 + 0.2 * sin(float(s + 1) * 0.9), Color.WHITE, 6)
			prev = q
			if absf(prev.x) > decor.end.x - 3.0 or prev.z < decor.position.y + 3.0 or prev.z > decor.end.y - 3.0:
				break
	# The gate braziers' fire.
	for side: float in [-1.0, 1.0]:
		var base := Vector3((GATE + 1.8) * side, 1.65, z0 - 1.0)
		k.add_sphere(0.28, MeshKit.xf(base, Vector3.ZERO, Vector3(1.0, 1.2, 1.0)), Color.WHITE, 8, 4)
		k.add_cylinder(0.0, 0.22, 0.6, MeshKit.xf(base + Vector3(0.0, 0.45, 0.0)), Color.WHITE, 6)
	_glow_mesh(root, "Lava", k, V_LAVA, 2.1)
	# Floating embers.
	var e := MeshKit.new()
	for i in 90:
		var q := _band_point(bounds, decor, rng, 0.5)
		if not q.is_finite():
			continue
		e.add_sphere(0.04 + 0.04 * rng.randf(), MeshKit.xf(Vector3(q.x, rng.randf_range(0.6, 5.0), q.y)), Color.WHITE, 4, 2)
	_glow_mesh(root, "FloatingEmbers", e, Color(1.0, 0.75, 0.3), 2.2)


# =================================================================================================
# Ice cave
# =================================================================================================

static func _ice_cave(arena: Arena, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var bounds := arena.get_bounds()
	var decor := arena.get_decor_rect()
	_scatter_tall(root, bounds, decor, rng, "Crystals", Mats.toon_vc_glow(I_GLOW, 0.4), 0.7, 0.4, _crystal_cluster)
	_ice_undergrowth(root, bounds, decor, rng)
	_ice_props(root, bounds, rng)
	_ice_sparkles(root, bounds, decor, rng)
	var frost := _tuft_mesh(rng, 6, 0.1, 0.22, 1.5, 0.03)
	_ground_multimesh(root, "FrostTufts", frost, bounds, decor, rng, 800, 130, 0.8, 1.3,
			[Color(0.78, 0.9, 0.98), Color(0.62, 0.82, 0.95), Color(0.9, 0.96, 1.0)])
	var snow := MeshKit.cached("theme:snow_patch", func() -> Mesh:
		var k := MeshKit.new()
		k.add_cylinder(0.5, 0.55, 0.03, MeshKit.xf(Vector3(0.0, 0.015, 0.0)), Color.WHITE, 10)
		k.add_cylinder(0.3, 0.34, 0.05, MeshKit.xf(Vector3(0.15, 0.03, 0.1)), Color.WHITE, 8)
		return k.build())
	_ground_multimesh(root, "SnowPatches", snow, bounds, decor, rng, 170, 0, 0.8, 1.8,
			[Color(0.62, 0.74, 0.9), Color(0.56, 0.68, 0.86)], 0.5, 0.0)
	return root


static func _crystal_cluster(k: MeshKit, p: Vector3, rng: RandomNumberGenerator, far: bool) -> void:
	var n := rng.randi_range(3, 6) if not far else 3
	var spread := rng.randf_range(0.7, 1.3)
	var tall := rng.randf_range(0.7, 1.4)
	for i in n:
		var a := TAU * float(i) / float(n) + rng.randf_range(-0.4, 0.4)
		var off := Vector3(sin(a), 0.0, cos(a)) * (spread * rng.randf_range(0.3, 1.0) if i > 0 else 0.0)
		var h := rng.randf_range(1.2, 3.8) * tall * (1.0 if i > 0 else 1.25)
		var r := rng.randf_range(0.22, 0.46)
		var col := I_ICE.lerp(I_ICE_LIGHT, rng.randf_range(0.0, 1.0)) if rng.randf() < 0.8 else I_ICE_DEEP
		var tilt := Vector3(rng.randf_range(-22.0, 22.0), 0.0, rng.randf_range(-22.0, 22.0))
		var yaw := rng.randf_range(0.0, PI)
		_post(k, p + off, tilt, yaw, r, r * 1.05, h, col, 6)
		_post(k, p + off, tilt, yaw, 0.0, r, r * 2.2, col.lightened(0.12), 6, h)
	if not far and rng.randf() < 0.25:  # a thick pillar of ice beside it
		var a := rng.randf_range(0.0, TAU)
		var q := p + Vector3(sin(a), 0.0, cos(a)) * (spread + 1.0)
		var ph := rng.randf_range(3.5, 6.5)
		_post(k, q, Vector3.ZERO, 0.0, 0.55, 0.75, ph, I_ICE.darkened(0.04), 8)
		for band in 2:
			_post(k, q, Vector3.ZERO, 0.0, 0.6, 0.62, 0.16, I_ICE_LIGHT, 8, ph * (0.3 + 0.3 * band))


static func _ice_undergrowth(root: Node3D, bounds: Rect2, decor: Rect2, rng: RandomNumberGenerator) -> void:
	var k := MeshKit.new()
	_ring_items(bounds, rng, 1.8, 1.8, 3.2, func(p: Vector3, _toward: Vector2) -> void:
		if rng.randf() < 0.75:
			_snow_drift(k, p + Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4)), rng.randf_range(0.6, 1.2), rng))
	for i in 130:
		var q := _band_point(bounds, decor, rng, 2.2)
		if not q.is_finite():
			continue
		var at := Vector3(q.x, 0.0, q.y)
		var roll := rng.randf()
		if roll < 0.4:
			_snow_drift(k, at, rng.randf_range(0.6, 1.5), rng)
		elif roll < 0.6:  # an ice boulder
			var s := rng.randf_range(0.4, 0.9)
			k.add_sphere(s, MeshKit.xf(at + Vector3(0.0, s * 0.3, 0.0), Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(0.0, 360.0), 0.0), Vector3(1.2, 0.75, 1.0)), I_ROCK.lerp(I_ICE, rng.randf_range(0.0, 0.6)), 6, 3)
		elif roll < 0.85:  # little crystals
			for c in rng.randi_range(2, 4):
				var cq := at + Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
				var h := rng.randf_range(0.3, 0.8)
				var col := I_ICE.lerp(I_ICE_LIGHT, rng.randf())
				var tilt := Vector3(rng.randf_range(-25.0, 25.0), 0.0, rng.randf_range(-25.0, 25.0))
				_post(k, cq, tilt, rng.randf_range(0.0, PI), 0.08, 0.1, h, col, 5)
				_post(k, cq, tilt, 0.0, 0.0, 0.1, 0.25, col.lightened(0.1), 5, h)
		else:  # a frozen skull
			k.add_sphere(0.2, MeshKit.xf(at + Vector3(0.0, 0.18, 0.0), Vector3.ZERO, Vector3(1.0, 0.85, 1.2)), C_BONE.lerp(I_ICE, 0.35), 8, 4)
	_kit_node(root, "Undergrowth", k, Mats.toon_vc(true, Color.WHITE, 0.03))


static func _snow_drift(k: MeshKit, p: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	k.add_sphere(size, MeshKit.xf(p, Vector3(0.0, rng.randf_range(0.0, 180.0), 0.0), Vector3(1.4, 0.45, 1.0)), I_SNOW.darkened(rng.randf_range(0.0, 0.08)), 9, 4)
	if rng.randf() < 0.5:
		k.add_sphere(size * 0.6, MeshKit.xf(p + Vector3(size * 0.9, 0.0, size * 0.2), Vector3.ZERO, Vector3(1.3, 0.5, 1.0)), I_SNOW, 8, 3)


static func _ice_props(root: Node3D, bounds: Rect2, rng: RandomNumberGenerator) -> void:
	var k := MeshKit.new()
	var z0 := bounds.position.y - ArenaDecor.WALL_OFFSET
	# Ice pillars crowned with crystals flanking the gate.
	for side: float in [-1.0, 1.0]:
		var base := Vector3((GATE + 1.9) * side, 0.0, z0 - 1.0)
		_post(k, base, Vector3.ZERO, 0.0, 0.45, 0.6, 3.4, I_ICE.darkened(0.03), 8)
		_post(k, base, Vector3.ZERO, 0.0, 0.5, 0.5, 0.15, I_ICE_LIGHT, 8, 1.2)
		_post(k, base, Vector3.ZERO, 0.0, 0.5, 0.5, 0.15, I_ICE_LIGHT, 8, 2.3)
		for c in 3:
			var a := TAU * float(c) / 3.0
			_post(k, base + Vector3(sin(a) * 0.2, 0.0, cos(a) * 0.2), Vector3(sin(a) * 22.0, 0.0, cos(a) * 22.0), 0.0, 0.0, 0.2, 1.1, I_ICE_LIGHT, 5, 3.3)
	# A ruined arch of ice west of the arena.
	var arch := Vector3(bounds.position.x - 9.0, 0.0, -3.0)
	for side: float in [-1.0, 1.0]:
		_post(k, arch + Vector3(0.0, 0.0, 2.2 * side), Vector3.ZERO, 0.0, 0.6, 0.8, 4.4, I_ICE.darkened(0.06), 7)
	k.add_box(Vector3(1.5, 0.8, 6.0), MeshKit.xf(arch + Vector3(0.0, 4.5, 0.0), Vector3(0.0, 0.0, 6.0)), I_ICE.darkened(0.1))
	# Big frozen crystals in the north-east corner.
	for i in 4:
		var base := Vector3(bounds.end.x + 6.0 + rng.randf_range(0.0, 3.0), 0.0, bounds.position.y - 3.0 - rng.randf_range(0.0, 3.0))
		var h := rng.randf_range(4.0, 6.5)
		var tilt := Vector3(rng.randf_range(-12.0, 12.0), 0.0, rng.randf_range(-12.0, 12.0))
		_post(k, base, tilt, rng.randf_range(0.0, PI), 0.5, 0.9, h, I_ICE_DEEP.lerp(I_ICE, rng.randf_range(0.0, 0.6)), 6)
		_post(k, base, tilt, 0.0, 0.0, 0.5, 1.6, I_ICE_LIGHT, 6, h)
	# Cracks in the ice floor, flat and dark (inside and out).
	for i in 14:
		var prev := Vector3(rng.randf_range(bounds.position.x + 2.0, bounds.end.x - 2.0), 0.03, rng.randf_range(bounds.position.y + 2.0, bounds.end.y - 2.0))
		var a := rng.randf_range(0.0, TAU)
		for s in 4:
			var a2 := a + rng.randf_range(-0.6, 0.6)
			var q := prev + Vector3(sin(a2), 0.0, cos(a2)) * rng.randf_range(0.7, 1.4)
			if not bounds.grow(-0.4).has_point(Vector2(q.x, q.z)):
				break
			k.add_segment(prev, q, 0.035, 0.03, I_ICE_DEEP.darkened(0.15), 4, false)
			prev = q
	_kit_node(root, "Props", k, Mats.toon_vc_glow(I_GLOW, 0.3))


static func _ice_sparkles(root: Node3D, bounds: Rect2, decor: Rect2, rng: RandomNumberGenerator) -> void:
	var k := MeshKit.new()
	var z0 := bounds.position.y - ArenaDecor.WALL_OFFSET
	for side: float in [-1.0, 1.0]:
		k.add_sphere(0.16, MeshKit.xf(Vector3((GATE + 1.9) * side, 3.5, z0 - 1.0)), Color.WHITE, 8, 4)
	for i in 60:
		var q := _band_point(bounds, decor, rng, 1.2)
		if not q.is_finite():
			continue
		k.add_sphere(0.04 + 0.03 * rng.randf(), MeshKit.xf(Vector3(q.x, rng.randf_range(0.3, 3.5), q.y)), Color.WHITE, 4, 2)
	_glow_mesh(root, "Sparkles", k, I_GLOW, 2.0)
