class_name ArenaBackdrop
extends RefCounted
## The wall and backdrop dressing OUTSIDE the playable rectangle (M7b VIS-ENV): what the screen edges show
## at the camera's farthest zoom-out. Every environment of the decor sets ([ArenaThemes]) gets one more
## merged mesh in its decor node, a ring around the low stone wall with the character of the place:
##   Cemetery – a wrought-iron spear fence on stone posts and tall dark cypresses behind it;
##   Swamp    – a rotting log palisade hung with moss and a few tall dead snags;
##   Volcano  – a crater rim of black basalt fangs with dashes of magma glowing at the foot of the wall
##              ([method magma_seams], drawn by the volcano's lava glow mesh);
##   Ice Cave – a double wall of faceted ice cliffs.
## Taller than the 0.55 m of the playable area is fine out here (the height rule of the decor tests only
## counts what stands inside the rectangle), but the ring gets lower towards the south, where the camera
## looks from: nothing stands between it and the action. One draw call and a few thousand vertices per
## environment, no shadows (the far trees' recipe), its own seeded RNG (the decor's layout never moves).

const SEED_SALT := 311
## How much of its height the ring keeps at the south wall (the camera's side).
const SOUTH_HEIGHT := 0.25
## The ring is full height from this far north of the south wall and blends down towards it.
const SOUTH_BLEND := 7.0

const IRON := Color(0.15, 0.15, 0.19)
const STONE := Color(0.46, 0.48, 0.55)
const CYPRESS := Color(0.09, 0.19, 0.14)
const LOG := Color(0.27, 0.2, 0.14)
const MOSS := Color(0.42, 0.52, 0.28)
const FANG := Color(0.15, 0.13, 0.15)
const FANG_LIGHT := Color(0.3, 0.23, 0.21)
const CLIFF_DEEP := Color(0.3, 0.5, 0.8)
const CLIFF := Color(0.55, 0.78, 0.95)
const CLIFF_CAP := Color(0.82, 0.94, 1.0)


## The backdrop mesh node of [param arena]'s decor set (null for the forest and for any set without one).
static func build(arena: Arena) -> MeshInstance3D:
	var look := ArenaGround.look_for(arena.environment, false)
	var bounds := arena.get_bounds()
	var rng := RandomNumberGenerator.new()
	rng.seed = Arena.DECOR_SEED + SEED_SALT
	var k := MeshKit.new()
	match look:
		ArenaGround.CEMETERY:
			_cemetery(k, bounds, rng)
		ArenaGround.SWAMP:
			_swamp(k, bounds, rng)
		ArenaGround.VOLCANO:
			_volcano(k, bounds, rng)
		ArenaGround.ICE_CAVE:
			_ice_cave(k, bounds, rng)
		_:
			return null
	var mi := MeshInstance3D.new()
	mi.name = "Backdrop"
	mi.mesh = k.build()
	mi.material_override = Mats.toon_vc(true, Color.WHITE, 0.04)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The dashes of magma glowing along the foot of the volcano's wall: Array of [a, b] Vector3 pairs
## (3 - 4 m long, a gap between them, none in front of the gate), for the lava glow mesh.
static func magma_seams(bounds: Rect2) -> Array[PackedVector3Array]:
	var rng := RandomNumberGenerator.new()
	rng.seed = Arena.DECOR_SEED + SEED_SALT + 7
	var out: Array[PackedVector3Array] = []
	var ring := bounds.grow(1.1)
	var perimeter := 2.0 * (ring.size.x + ring.size.y)
	var d := 0.0
	while d < perimeter:
		var length := rng.randf_range(2.2, 4.0)
		var a := ArenaDecor.perimeter_point(ring, d)
		var b := ArenaDecor.perimeter_point(ring, d + length)
		# (A dash never turns a corner and never lies before the gate.)
		var straight := absf(a.x - b.x) < 0.01 or absf(a.y - b.y) < 0.01
		var gate := a.y < bounds.position.y and absf(a.x) < ArenaDecor.GATE_HALF_WIDTH + 3.0
		if straight and not gate and rng.randf() < 0.8:
			out.append(PackedVector3Array([Vector3(a.x, 0.05, a.y), Vector3(b.x, 0.05, b.y)]))
		d += length + rng.randf_range(1.2, 3.5)
	return out


## Calls [param fn](Vector3 base, Vector3 tangent, Vector3 outward, float height_factor) for points along
## the ring [param grow] metres outside [param bounds], [param lo]..[param hi] metres apart (none in
## front of the north gate when [param skip_gate]). The height factor is 1 on the north / west / east
## and blends down to [constant SOUTH_HEIGHT] at the south wall.
static func walk_ring(bounds: Rect2, grow: float, lo: float, hi: float, rng: RandomNumberGenerator,
		fn: Callable, skip_gate: bool = true) -> void:
	var ring := bounds.grow(grow)
	var perimeter := 2.0 * (ring.size.x + ring.size.y)
	var d := 0.0
	while d < perimeter:
		var p := ArenaDecor.perimeter_point(ring, d)
		var q := ArenaDecor.perimeter_point(ring, d + 0.05)
		var t := q - p
		if t.length() < 0.001:  # (at a corner the second point turns it: look back instead)
			t = p - ArenaDecor.perimeter_point(ring, d - 0.05)
		t = t.normalized()
		var out := Vector2(-t.y, t.x)
		if out.dot(p - bounds.get_center()) < 0.0:
			out = -out
		var gate := p.y < bounds.position.y and absf(p.x) < ArenaDecor.GATE_HALF_WIDTH + 2.5
		if not (skip_gate and gate):
			fn.call(Vector3(p.x, 0.0, p.y), Vector3(t.x, 0.0, t.y), Vector3(out.x, 0.0, out.y), height_factor(bounds, p.y))
		d += rng.randf_range(lo, hi)


## 1 on the northern part of the ring, [constant SOUTH_HEIGHT] at the south wall, a ramp in between.
static func height_factor(bounds: Rect2, z: float) -> float:
	var t := clampf((z - (bounds.end.y - SOUTH_BLEND)) / SOUTH_BLEND, 0.0, 1.0)
	return lerpf(1.0, SOUTH_HEIGHT, t)


static func _up(k: MeshKit, base: Vector3, tilt: Vector3, r_top: float, r_bot: float, h: float, color: Color,
		radial: int, y0: float = 0.0) -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(tilt.x), 0.0, deg_to_rad(tilt.z)))
	k.add_cylinder(r_top, r_bot, h, Transform3D(b, base + b * Vector3(0.0, y0 + h * 0.5, 0.0)), color, radial)


# --- Cemetery: iron fence and cypresses ----------------------------------------------------------------

static func _cemetery(k: MeshKit, bounds: Rect2, rng: RandomNumberGenerator) -> void:
	var state := {"i": 0, "prev": Vector3.INF}
	walk_ring(bounds, 1.5, 0.9, 1.1, rng, func(base: Vector3, tangent: Vector3, _out: Vector3, hf: float) -> void:
		var i: int = state["i"]
		state["i"] = i + 1
		var h := 1.55 * hf
		# A bar with a spear head; two rails to the last bar; a stone post every fourth step.
		_up(k, base, Vector3.ZERO, 0.025, 0.03, h, IRON, 5)
		k.add_cylinder(0.0, 0.055, 0.22, MeshKit.xf(base + Vector3(0.0, h + 0.1, 0.0)), IRON, 4)
		var prev: Vector3 = state["prev"]
		if prev != Vector3.INF and prev.distance_to(base) < 1.6:
			for rail: float in [0.35, 0.8]:
				k.add_segment(prev + Vector3(0.0, rail * hf + 0.1, 0.0), base + Vector3(0.0, rail * hf + 0.1, 0.0), 0.03, 0.03, IRON, 4, false)
		state["prev"] = base
		if i % 4 == 0:
			var ph := (2.0 + rng.randf_range(0.0, 0.25)) * maxf(hf, 0.55)
			var yaw := atan2(tangent.x, tangent.z)
			k.add_box(Vector3(0.38, ph, 0.38), MeshKit.xf(base + Vector3(0.0, ph * 0.5, 0.0), Vector3(0.0, rad_to_deg(yaw), 0.0)), STONE.darkened(rng.randf_range(0.0, 0.2)))
			k.add_cylinder(0.0, 0.34, 0.26, MeshKit.xf(base + Vector3(0.0, ph + 0.13, 0.0), Vector3(0.0, 45.0, 0.0)), STONE.lightened(0.05), 4)
			if rng.randf() < 0.4:
				k.add_sphere(0.1, MeshKit.xf(base + Vector3(0.0, ph + 0.36, 0.0)), STONE.lightened(0.1), 6, 3))
	# Tall, narrow cypresses behind the fence (never in front of the camera).
	walk_ring(bounds, 5.2, 6.0, 9.0, rng, func(base: Vector3, _t: Vector3, _o: Vector3, hf: float) -> void:
		if hf < 0.8:
			return
		var h := rng.randf_range(5.0, 8.0)
		var c := CYPRESS.lightened(rng.randf_range(-0.03, 0.08))
		k.add_cylinder(0.0, 0.8, h * 0.55, MeshKit.xf(base + Vector3(0.0, h * 0.275, 0.0)), c, 7)
		k.add_cylinder(0.0, 0.62, h * 0.55, MeshKit.xf(base + Vector3(0.0, h * 0.55, 0.0)), c.lightened(0.04), 7)
		k.add_cylinder(0.0, 0.44, h * 0.45, MeshKit.xf(base + Vector3(0.0, h * 0.78, 0.0)), c.lightened(0.08), 6)
		k.add_cylinder(0.05, 0.1, h * 0.25, MeshKit.xf(base + Vector3(0.0, h * 0.12, 0.0)), LOG, 5))


# --- Swamp: palisade and snags -------------------------------------------------------------------------

static func _swamp(k: MeshKit, bounds: Rect2, rng: RandomNumberGenerator) -> void:
	walk_ring(bounds, 1.35, 0.42, 0.58, rng, func(base: Vector3, tangent: Vector3, out: Vector3, hf: float) -> void:
		if rng.randf() < 0.16:
			return  # a gap where a log rotted away
		var h := rng.randf_range(1.3, 2.4) * hf
		var lean := out * rng.randf_range(0.0, 0.14) * h + tangent * rng.randf_range(-0.08, 0.08) * h
		var top := base + Vector3(0.0, h, 0.0) + lean
		var c := LOG.lightened(rng.randf_range(-0.04, 0.12))
		if rng.randf() < 0.25:
			c = c.lerp(MOSS, 0.4)
		k.add_segment(base - Vector3(0.0, 0.1, 0.0), top, 0.14, 0.11, c, 6)
		k.add_cylinder(0.0, 0.11, 0.28, MeshKit.xf(top + Vector3(0.0, 0.12, 0.0), Vector3(lean.z * -40.0, 0.0, lean.x * 40.0)), c.lightened(0.08), 6)
		if rng.randf() < 0.28:  # hanging moss
			var from := base.lerp(top, 0.9)
			k.add_segment(from, from + Vector3(0.0, -rng.randf_range(0.5, 1.0), 0.0), 0.015, 0.045, MOSS, 4, false))
	# Tall dead snags with long trailing moss, far behind the palisade.
	walk_ring(bounds, 4.5, 5.0, 8.0, rng, func(base: Vector3, _t: Vector3, out: Vector3, hf: float) -> void:
		if hf < 0.8:
			return
		var h := rng.randf_range(6.0, 9.0)
		var top := base + Vector3(0.0, h, 0.0) + out * rng.randf_range(-0.6, 0.8)
		k.add_segment(base - Vector3(0.0, 0.1, 0.0), top, 0.3, 0.1, LOG.darkened(0.1), 6)
		for b in 3:
			var a := rng.randf_range(0.0, TAU)
			var from := base.lerp(top, rng.randf_range(0.45, 0.85))
			var to := from + Vector3(sin(a), rng.randf_range(0.2, 0.7), cos(a)) * rng.randf_range(0.9, 1.6)
			k.add_segment(from, to, 0.09, 0.03, LOG.darkened(0.1), 4)
			k.add_segment(to, to + Vector3(0.0, -rng.randf_range(1.2, 2.4), 0.0), 0.02, 0.06, MOSS.darkened(0.1), 4, false))


# --- Volcano: crater rim -------------------------------------------------------------------------------

static func _volcano(k: MeshKit, bounds: Rect2, rng: RandomNumberGenerator) -> void:
	walk_ring(bounds, 1.3, 1.3, 2.1, rng, func(base: Vector3, tangent: Vector3, out: Vector3, hf: float) -> void:
		var n := rng.randi_range(2, 4)
		for i in n:
			var at := base + out * rng.randf_range(0.0, 2.2) + tangent * rng.randf_range(-0.7, 0.7)
			var h := rng.randf_range(1.4, 4.6) * hf * (1.0 + 0.25 * float(i == 0))
			var r := rng.randf_range(0.34, 0.6)
			if hf < 0.6:  # (towards the camera: a low rim, no spires)
				h = rng.randf_range(0.35, 0.8)
				r *= 0.8
			var col := FANG.lerp(FANG_LIGHT, rng.randf_range(0.0, 0.7))
			var tilt := Vector3(out.z * 11.0 + rng.randf_range(-5.0, 5.0), 0.0, -out.x * 11.0 + rng.randf_range(-5.0, 5.0))
			_up(k, at, tilt, r * 0.78, r, h, col, 6)
			_up(k, at, tilt, 0.0, r * 0.78, r * 1.5, col.lightened(0.07), 6, h))


# --- Ice cave: cliff wall ------------------------------------------------------------------------------

static func _ice_cave(k: MeshKit, bounds: Rect2, rng: RandomNumberGenerator) -> void:
	for row in 2:
		var grow := 1.2 + 1.9 * float(row)
		walk_ring(bounds, grow, 1.0, 1.4, rng, func(base: Vector3, _tangent: Vector3, out: Vector3, hf: float) -> void:
			if hf < 0.6 and row == 1:
				return  # (towards the camera only the low inner row stands)
			var h := (rng.randf_range(0.9, 2.4) if row == 0 else rng.randf_range(2.8, 6.8)) * hf
			var r := rng.randf_range(0.42, 0.62) * (1.0 if row == 0 else 1.3)
			if hf < 0.6:
				h = rng.randf_range(0.3, 0.6)
				r *= 0.8
			var col := CLIFF_DEEP.lerp(CLIFF, rng.randf_range(0.0, 1.0))
			var tilt := Vector3(out.z * 8.0 + rng.randf_range(-6.0, 6.0), 0.0, -out.x * 8.0 + rng.randf_range(-6.0, 6.0))
			var at := base + out * rng.randf_range(-0.3, 0.5)
			_up(k, at, tilt, r * 0.9, r, h, col, 6)
			_up(k, at, tilt, 0.0, r * 0.9, r * 1.9, CLIFF_CAP.lerp(col, 0.2), 6, h))
