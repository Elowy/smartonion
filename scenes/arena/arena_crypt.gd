class_name ArenaCrypt
extends RefCounted
## The dungeon room's dressing (M7b VIS-ENV; GDD 16.1): a crypt. The room itself is [Arena]'s dungeon layout
## (24 x 14 m, the low stone wall and its gate); this builds what stands around it, all OUTSIDE the
## playable rectangle: a colonnade of pillars with a heavy cornice, a tall back wall with dark alcoves,
## sarcophagi, bone piles, hanging banners, and the torches in iron sconces whose flames flicker
## ([ArenaFx]) and whose warm light pools on the floor ([ArenaGround]'s crypt shader gets their places from
## [method torch_points]). The ring gets lower towards the south, where the camera looks from.
## Two meshes (two draw calls): the stonework and the flames. The stone is its own, the floor wears the
## run's environment palette.

const STONE := Color(0.44, 0.42, 0.45)
const STONE_DARK := Color(0.27, 0.25, 0.29)
const STONE_LIGHT := Color(0.56, 0.53, 0.55)
const BONE := Color(0.82, 0.78, 0.68)
const IRON := Color(0.14, 0.13, 0.16)
const BANNER := Color(0.45, 0.1, 0.12)
const BANNER_TRIM := Color(0.78, 0.6, 0.22)
const FLAME := Color(1.0, 0.62, 0.2)
## The colonnade stands this far outside the playable rectangle, the back wall this far.
const PILLAR_GROW := 1.9
const WALL_GROW := 3.6
const PILLAR_HEIGHT := 6.0
const WALL_HEIGHT := 7.5
## Spacing of the pillars along the north / south and the west / east sides.
const SPACING_X := 3.0
const SPACING_Z := 3.5
## Height of a torch flame above the floor.
const TORCH_Y := 2.35


## The decor node of the dungeon room: "Crypt" (stone) and "Torches" (flames).
static func build(arena: Arena, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var bounds := arena.get_bounds()
	var k := MeshKit.new()
	_back_wall(k, bounds)
	_colonnade(k, bounds, rng)
	_furnishings(k, bounds, rng)
	var mi := MeshInstance3D.new()
	mi.name = "Crypt"
	mi.mesh = k.build()
	mi.material_override = Mats.toon_vc(true, Color.WHITE, 0.04)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var flames := MeshKit.new()
	for p in torch_points(bounds):
		var at := Vector3(p.x, TORCH_Y, p.z)
		flames.add_sphere(0.17, MeshKit.xf(at + Vector3(0.0, 0.05, 0.0), Vector3.ZERO, Vector3(1.0, 1.25, 1.0)), ArenaFx.lit(at), 8, 4)
		flames.add_cylinder(0.0, 0.15, 0.42, MeshKit.xf(at + Vector3(0.0, 0.32, 0.0)), ArenaFx.lit(at), 6)
	var fm := MeshInstance3D.new()
	fm.name = "Torches"
	fm.mesh = flames.build()
	# (Flickering: shallow, fast, a little blink.)
	fm.material_override = ArenaFx.twinkle(FLAME, 9.0, 0.35, 0.2)
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fm)
	return root


## Where the torches burn (XZ, at the pillars along the north wall and two on each side wall): the floor
## shader lights its pools there. At most [constant ArenaGround.MAX_TORCHES].
static func torch_points(bounds: Rect2) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var half := bounds.size * 0.5
	for x: float in [-9.0, -3.0, 3.0, 9.0]:
		if absf(x) < half.x - 1.0:
			out.append(Vector3(bounds.get_center().x + x, 0.0, bounds.position.y - PILLAR_GROW + 0.9))
	for side: float in [-1.0, 1.0]:
		for z: float in [-3.5, 3.5]:
			if absf(z) < half.y - 1.0:
				out.append(Vector3(bounds.get_center().x + side * (half.x + PILLAR_GROW - 0.9), 0.0, bounds.get_center().y + z))
	return out.slice(0, ArenaGround.MAX_TORCHES)


# --- Parts ---------------------------------------------------------------------------------------------

## The tall back wall: slabs north / west / east with a cornice and dark alcoves between the pillars.
static func _back_wall(k: MeshKit, bounds: Rect2) -> void:
	var g := WALL_GROW
	var x0 := bounds.position.x - g
	var x1 := bounds.end.x + g
	var z0 := bounds.position.y - g
	var z1 := bounds.end.y
	var h := WALL_HEIGHT
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	# North slab and the two side slabs (not the south: the camera looks over that side).
	k.add_box(Vector3(x1 - x0 + 1.6, h, 0.9), MeshKit.xf(Vector3(cx, h * 0.5, z0)), STONE_DARK)
	for side: float in [-1.0, 1.0]:
		var x := x0 if side < 0.0 else x1
		k.add_box(Vector3(0.9, h, z1 - z0), MeshKit.xf(Vector3(x, h * 0.5, cz)), STONE_DARK)
	# Cornice and plinth along the three slabs.
	k.add_box(Vector3(x1 - x0 + 2.2, 0.5, 1.5), MeshKit.xf(Vector3(cx, h + 0.1, z0 + 0.3)), STONE)
	k.add_box(Vector3(x1 - x0 + 1.9, 0.9, 1.3), MeshKit.xf(Vector3(cx, 0.45, z0 + 0.2)), STONE)
	for side: float in [-1.0, 1.0]:
		var x := x0 if side < 0.0 else x1
		k.add_box(Vector3(1.5, 0.5, z1 - z0), MeshKit.xf(Vector3(x - side * 0.3, h + 0.1, cz)), STONE)
		k.add_box(Vector3(1.3, 0.9, z1 - z0), MeshKit.xf(Vector3(x - side * 0.2, 0.45, cz)), STONE)
	# Alcoves: dark, tall recesses in the face of the slabs, one between every two pillars.
	var ax := bounds.position.x + 1.5
	while ax < bounds.end.x - 1.0:
		if absf(ax) > 2.4:
			_alcove(k, Vector3(ax, 0.0, z0 + 0.5), 0.0)
		ax += SPACING_X * 2.0
	for side: float in [-1.0, 1.0]:
		var x := (x0 + 0.5) if side < 0.0 else (x1 - 0.5)
		for z: float in [-5.25, 1.75]:
			_alcove(k, Vector3(x, 0.0, z), -PI * 0.5 * side)


static func _alcove(k: MeshKit, p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	k.add_box(Vector3(1.9, 3.6, 0.2), Transform3D(b, p + b * Vector3(0.0, 1.9, 0.0)), Color(0.07, 0.06, 0.09))
	k.add_box(Vector3(2.3, 0.3, 0.3), Transform3D(b, p + b * Vector3(0.0, 3.85, 0.05)), STONE_LIGHT)
	k.add_box(Vector3(0.25, 3.8, 0.3), Transform3D(b, p + b * Vector3(-1.1, 1.9, 0.05)), STONE)
	k.add_box(Vector3(0.25, 3.8, 0.3), Transform3D(b, p + b * Vector3(1.1, 1.9, 0.05)), STONE)


## The pillars with a base and a capital and a beam over each pair; the torch sconces on the ones that burn.
## They stand in rows along the four sides (north and south every SPACING_X metres, west and east every
## SPACING_Z), a gap in front of the gate, so the torch points fall on pillars.
static func _colonnade(k: MeshKit, bounds: Rect2, rng: RandomNumberGenerator) -> void:
	var torches := torch_points(bounds)
	var ring := bounds.grow(PILLAR_GROW)
	var rows: Array[Array] = []
	var xs: Array[float] = []
	var x := -floorf(bounds.size.x * 0.5 / SPACING_X) * SPACING_X
	while x <= bounds.size.x * 0.5 + 0.01:
		xs.append(bounds.get_center().x + x)
		x += SPACING_X
	var zs: Array[float] = []
	var z := -floorf(bounds.size.y * 0.5 / SPACING_Z) * SPACING_Z
	while z <= bounds.size.y * 0.5 + 0.01:
		zs.append(bounds.get_center().y + z)
		z += SPACING_Z
	# (North, south: from corner to corner; west, east: between the corners' pillars.)
	var north: Array[Vector3] = [Vector3(ring.position.x, 0.0, ring.position.y)]
	var south: Array[Vector3] = [Vector3(ring.position.x, 0.0, ring.end.y)]
	for px in xs:
		north.append(Vector3(px, 0.0, ring.position.y))
		south.append(Vector3(px, 0.0, ring.end.y))
	north.append(Vector3(ring.end.x, 0.0, ring.position.y))
	south.append(Vector3(ring.end.x, 0.0, ring.end.y))
	var west: Array[Vector3] = [Vector3(ring.position.x, 0.0, ring.position.y)]
	var east: Array[Vector3] = [Vector3(ring.end.x, 0.0, ring.position.y)]
	for pz in zs:
		west.append(Vector3(ring.position.x, 0.0, pz))
		east.append(Vector3(ring.end.x, 0.0, pz))
	west.append(Vector3(ring.position.x, 0.0, ring.end.y))
	east.append(Vector3(ring.end.x, 0.0, ring.end.y))
	rows.append(north)
	rows.append(south)
	rows.append(west)
	rows.append(east)
	for row in rows:
		var prev := Vector3.INF
		var prev_h := 0.0
		for base: Vector3 in row:
			if base.z < bounds.position.y and absf(base.x) < ArenaDecor.GATE_HALF_WIDTH + 1.0:
				prev = Vector3.INF
				continue
			var h := PILLAR_HEIGHT * ArenaBackdrop.height_factor(bounds, base.z)
			_pillar(k, base, h, rng)
			# A beam from the last pillar of the row.
			if prev != Vector3.INF and h > 1.5 and prev_h > 1.5:
				var along := (base - prev).abs()
				k.add_box(Vector3(maxf(along.x, 0.5), 0.55, maxf(along.z, 0.5)),
						MeshKit.xf((prev + base) * 0.5 + Vector3(0.0, minf(h, prev_h) + 0.2, 0.0)), STONE_DARK.lightened(0.04))
			prev = base
			prev_h = h
			# An iron sconce where a torch burns (the flame mesh floats over it).
			for t in torches:
				if Vector2(t.x - base.x, t.z - base.z).length() < 1.2:
					k.add_box(Vector3(0.12, 0.9, 0.12), MeshKit.xf(Vector3(t.x, TORCH_Y - 0.45, t.z)), IRON)
					k.add_cylinder(0.22, 0.12, 0.2, MeshKit.xf(Vector3(t.x, TORCH_Y - 0.12, t.z)), IRON, 8)


static func _pillar(k: MeshKit, base: Vector3, h: float, rng: RandomNumberGenerator) -> void:
	var c := STONE.darkened(rng.randf_range(0.0, 0.18))
	k.add_box(Vector3(1.3, 0.5, 1.3), MeshKit.xf(base + Vector3(0.0, 0.25, 0.0)), c.darkened(0.12))
	var shaft := maxf(h - 0.9, 0.3)
	k.add_cylinder(0.5, 0.58, shaft, MeshKit.xf(base + Vector3(0.0, 0.5 + shaft * 0.5, 0.0)), c, 9)
	k.add_box(Vector3(1.25, 0.4, 1.25), MeshKit.xf(base + Vector3(0.0, h - 0.2, 0.0)), c.lightened(0.07))
	if h > 3.0:  # a carved band
		k.add_cylinder(0.56, 0.56, 0.18, MeshKit.xf(base + Vector3(0.0, h * 0.62, 0.0)), STONE_LIGHT, 9)


## Sarcophagi along the north, bone piles outside the wall, banners on the back wall.
static func _furnishings(k: MeshKit, bounds: Rect2, rng: RandomNumberGenerator) -> void:
	var z := bounds.position.y - PILLAR_GROW - 1.1
	var x := bounds.position.x + 2.2
	while x < bounds.end.x - 1.5:
		if absf(x) > 3.0 and rng.randf() < 0.75:
			var b := Basis(Vector3.UP, rng.randf_range(-0.05, 0.05))
			k.add_box(Vector3(2.3, 0.75, 0.95), Transform3D(b, Vector3(x, 0.38, z)), STONE.darkened(0.1))
			k.add_box(Vector3(2.45, 0.22, 1.08), Transform3D(b, Vector3(x, 0.86, z)), STONE.lightened(0.04))
			k.add_sphere(0.13, MeshKit.xf(Vector3(x - 0.6, 1.05, z), Vector3.ZERO, Vector3(1.0, 0.8, 1.2)), BONE, 7, 4)
		x += SPACING_X * 2.0 + rng.randf_range(-0.3, 0.3)
	# Bones scattered just outside the wall.
	for i in 22:
		var p := Vector3.ZERO
		match rng.randi_range(0, 2):
			0:
				p = Vector3(rng.randf_range(bounds.position.x, bounds.end.x), 0.0, bounds.position.y - rng.randf_range(0.9, 1.6))
			1:
				p = Vector3(bounds.position.x - rng.randf_range(0.9, 1.6), 0.0, rng.randf_range(bounds.position.y, bounds.end.y))
			_:
				p = Vector3(bounds.end.x + rng.randf_range(0.9, 1.6), 0.0, rng.randf_range(bounds.position.y, bounds.end.y))
		var a := rng.randf_range(0.0, TAU)
		var dir := Vector3(sin(a), 0.0, cos(a))
		k.add_segment(p - dir * 0.16 + Vector3(0.0, 0.04, 0.0), p + dir * 0.16 + Vector3(0.0, 0.04, 0.0), 0.03, 0.03, BONE, 5)
		if rng.randf() < 0.5:
			k.add_sphere(0.075, MeshKit.xf(p + Vector3(0.2, 0.08, 0.05), Vector3.ZERO, Vector3(1.0, 0.9, 1.1)), BONE.darkened(0.06), 7, 4)
	# Banners hanging from the north back wall.
	var banner := PackedVector2Array([Vector2(-0.5, 0.0), Vector2(0.5, 0.0), Vector2(0.5, -2.2), Vector2(0.0, -1.7), Vector2(-0.5, -2.2)])
	for bx: float in [-6.0, 6.0]:
		var at := Vector3(bx, 5.2, bounds.position.y - WALL_GROW + 0.55)
		k.add_extrusion(banner, 0.05, MeshKit.xf(at), BANNER)
		k.add_box(Vector3(1.2, 0.1, 0.12), MeshKit.xf(at + Vector3(0.0, 0.05, 0.02)), BANNER_TRIM)
		k.add_box(Vector3(0.9, 0.1, 0.12), MeshKit.xf(at + Vector3(0.0, -1.0, 0.04)), BANNER_TRIM)
