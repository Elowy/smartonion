class_name MeshKit
extends RefCounted
## Procedural mesh builder used by the "visuals" module.
##
## Merges primitive shapes (boxes, spheres, cylinders ...), surfaces of revolution (lathes)
## and extruded 2D outlines into ONE ArrayMesh with per-vertex colours, so a whole prop /
## enemy / weapon is a single draw call (+ its outline pass) with [method Mats.toon_vc].
## Built meshes can be cached by key with [method cached].
##
## Godot front faces are clockwise: for a front triangle (a, b, c) with outward normal n,
## (b - a).cross(c - a).dot(n) < 0. Custom geometry here is auto-corrected to that rule.

## Shared mesh cache: key -> Mesh. Meshes are immutable once cached.
static var _cache: Dictionary[String, Mesh] = {}

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()


## Returns the cached mesh for [param key], building it with [param builder] (a Callable
## returning a Mesh) on first use.
static func cached(key: String, builder: Callable) -> Mesh:
	var mesh: Mesh = _cache.get(key)
	if mesh == null:
		mesh = builder.call()
		_cache[key] = mesh
	return mesh


static func has_cached(key: String) -> bool:
	return _cache.has(key)


static func cache_size() -> int:
	return _cache.size()


func is_empty() -> bool:
	return _verts.is_empty()


func vertex_count() -> int:
	return _verts.size()


## Builds the merged ArrayMesh (or an empty ArrayMesh when nothing was added).
func build() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Primitive shapes --------------------------------------------------------

## Appends every surface of [param mesh] transformed by [param xform] and tinted [param color].
func add_mesh(mesh: Mesh, xform: Transform3D, color: Color) -> MeshKit:
	var nb := xform.basis.inverse().transposed()
	var mirrored := xform.basis.determinant() < 0.0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var base := _verts.size()
		for i in v.size():
			_verts.append(xform * v[i])
			_normals.append((nb * n[i]).normalized() if i < n.size() else Vector3.UP)
			_colors.append(color)
			_uvs.append(uv[i] if i < uv.size() else Vector2.ZERO)
		if idx.is_empty():
			for i in range(0, v.size(), 3):
				_add_index_tri(base + i, base + i + 1, base + i + 2, mirrored)
		else:
			for i in range(0, idx.size(), 3):
				_add_index_tri(base + idx[i], base + idx[i + 1], base + idx[i + 2], mirrored)
	return self


func _add_index_tri(a: int, b: int, c: int, flip: bool) -> void:
	if flip:
		_indices.append_array([a, c, b])
	else:
		_indices.append_array([a, b, c])


func add_box(size: Vector3, xform: Transform3D, color: Color) -> MeshKit:
	var m := BoxMesh.new()
	m.size = size
	return add_mesh(m, xform, color)


func add_sphere(radius: float, xform: Transform3D, color: Color, radial: int = 14, rings: int = 7,
		hemisphere: bool = false) -> MeshKit:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * (1.0 if hemisphere else 2.0)
	m.radial_segments = radial
	m.rings = rings
	m.is_hemisphere = hemisphere
	return add_mesh(m, xform, color)


func add_cylinder(top_radius: float, bottom_radius: float, height: float, xform: Transform3D,
		color: Color, radial: int = 10, caps: bool = true) -> MeshKit:
	var m := CylinderMesh.new()
	m.top_radius = top_radius
	m.bottom_radius = bottom_radius
	m.height = height
	m.radial_segments = radial
	m.rings = 0
	m.cap_top = caps
	m.cap_bottom = caps
	return add_mesh(m, xform, color)


func add_capsule(radius: float, height: float, xform: Transform3D, color: Color, radial: int = 10,
		rings: int = 4) -> MeshKit:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = maxf(height, radius * 2.0)
	m.radial_segments = radial
	m.rings = rings
	return add_mesh(m, xform, color)


func add_torus(inner_radius: float, outer_radius: float, xform: Transform3D, color: Color,
		rings: int = 16, ring_segments: int = 6) -> MeshKit:
	var m := TorusMesh.new()
	m.inner_radius = inner_radius
	m.outer_radius = outer_radius
	m.rings = rings
	m.ring_segments = ring_segments
	return add_mesh(m, xform, color)


## A cylinder (or cone when one radius is 0) spanning from [param a] to [param b].
func add_segment(a: Vector3, b: Vector3, radius_a: float, radius_b: float, color: Color,
		radial: int = 8, caps: bool = true) -> MeshKit:
	var length := a.distance_to(b)
	if length < 0.0001:
		return self
	var basis := basis_from_y((b - a) / length)
	return add_cylinder(radius_b, radius_a, length, Transform3D(basis, (a + b) * 0.5), color, radial, caps)


## A polyline tube through [param points] with radii interpolated from [param r0] to [param r1].
func add_tube(points: PackedVector3Array, r0: float, r1: float, color: Color, radial: int = 8) -> MeshKit:
	var n := points.size()
	for i in n - 1:
		var t0 := float(i) / float(n - 1)
		var t1 := float(i + 1) / float(n - 1)
		add_segment(points[i], points[i + 1], lerpf(r0, r1, t0), lerpf(r0, r1, t1), color, radial)
		if i > 0:
			add_sphere(lerpf(r0, r1, t0), Transform3D(Basis(), points[i]), color, radial, maxi(3, radial / 2))
	return self


# --- Custom geometry ---------------------------------------------------------

## Surface of revolution around the Y axis. [param profile] holds (radius, y) pairs from
## bottom to top. Angles are measured from the front (-Z) towards +X, so a partial lathe
## from 60 to 300 degrees covers the back and sides but leaves the face open.
## UV.x = angle fraction (0..1 over the given range), UV.y = profile fraction (0 bottom, 1 top).
func add_lathe(profile: PackedVector2Array, xform: Transform3D, color: Color, segments: int = 24,
		from_deg: float = 0.0, to_deg: float = 360.0, double_sided: bool = false) -> MeshKit:
	var count := profile.size()
	if count < 2:
		return self
	var nb := xform.basis.inverse().transposed()
	# Cumulative profile length for UV.y.
	var lengths := PackedFloat32Array([0.0])
	for i in range(1, count):
		lengths.append(lengths[i - 1] + profile[i].distance_to(profile[i - 1]))
	var total := maxf(lengths[count - 1], 0.0001)
	# Profile normals (r, y) from neighbour tangents; outward for bottom-to-top profiles.
	var pnormals := PackedVector2Array()
	for i in count:
		var t := profile[mini(i + 1, count - 1)] - profile[maxi(i - 1, 0)]
		pnormals.append(Vector2(t.y, -t.x).normalized())
	var cols := segments + 1
	var passes := 2 if double_sided else 1
	for side in passes:
		var sign_n := 1.0 if side == 0 else -1.0
		var base := _verts.size()
		for s in cols:
			var f := float(s) / float(segments)
			var a := deg_to_rad(lerpf(from_deg, to_deg, f))
			var sa := sin(a)
			var ca := cos(a)
			for i in count:
				var p := profile[i]
				var pn := pnormals[i]
				var local := Vector3(p.x * sa, p.y, -p.x * ca)
				var ln := Vector3(pn.x * sa, pn.y, -pn.x * ca) * sign_n
				_verts.append(xform * local)
				_normals.append((nb * ln).normalized())
				_colors.append(color)
				_uvs.append(Vector2(f, lengths[i] / total))
		for s in segments:
			for i in count - 1:
				var a0 := base + s * count + i
				var a1 := a0 + 1
				var b0 := a0 + count
				var b1 := b0 + 1
				_tri_auto(a0, b0, a1)
				_tri_auto(a1, b0, b1)
	return self


## Extrudes a 2D outline (XY plane, any winding) along Z by [param depth] (centred), then
## transforms it. Great for blades, axe heads, shields, wings and banners.
func add_extrusion(outline: PackedVector2Array, depth: float, xform: Transform3D, color: Color,
		bevel_scale: float = 1.0) -> MeshKit:
	var tris := Geometry2D.triangulate_polygon(outline)
	if tris.is_empty():
		return self
	var nb := xform.basis.inverse().transposed()
	var hz := depth * 0.5
	# Faces (front -Z ... back +Z); the back face may be scaled (bevelled look).
	var centroid := Vector2.ZERO
	for p in outline:
		centroid += p
	centroid /= float(outline.size())
	for face in 2:
		var z := -hz if face == 0 else hz
		var n := Vector3(0, 0, -1) if face == 0 else Vector3(0, 0, 1)
		var scale := 1.0 if face == 0 else bevel_scale
		var base := _verts.size()
		for p in outline:
			var q := centroid + (p - centroid) * scale
			_verts.append(xform * Vector3(q.x, q.y, z))
			_normals.append((nb * n).normalized())
			_colors.append(color)
			_uvs.append(q)
		for i in range(0, tris.size(), 3):
			_tri_auto(base + tris[i], base + tris[i + 1], base + tris[i + 2])
	# Sides: one quad per edge with a flat normal.
	var count := outline.size()
	for i in count:
		var p0 := outline[i]
		var p1 := outline[(i + 1) % count]
		var b0 := centroid + (p0 - centroid) * bevel_scale
		var b1 := centroid + (p1 - centroid) * bevel_scale
		var v0 := Vector3(p0.x, p0.y, -hz)
		var v1 := Vector3(p1.x, p1.y, -hz)
		var v2 := Vector3(b1.x, b1.y, hz)
		var v3 := Vector3(b0.x, b0.y, hz)
		var edge := v1 - v0
		var n := edge.cross(v3 - v0).normalized()
		# Make the normal point away from the centroid.
		var mid := (p0 + p1) * 0.5 - centroid
		if Vector2(n.x, n.y).dot(mid) < 0.0:
			n = -n
		var base := _verts.size()
		for v: Vector3 in [v0, v1, v2, v3]:
			_verts.append(xform * v)
			_normals.append((nb * n).normalized())
			_colors.append(color)
			_uvs.append(Vector2.ZERO)
		_tri_auto(base, base + 1, base + 2)
		_tri_auto(base, base + 2, base + 3)
	return self


## Flat annular sector on the XZ plane (Y up), centred on the -Z axis.
## UV.x = 0..1 across the arc, UV.y = 0 inner edge .. 1 outer edge.
func add_arc(inner_radius: float, outer_radius: float, arc_deg: float, xform: Transform3D,
		color: Color, segments: int = 24) -> MeshKit:
	var nb := xform.basis.inverse().transposed()
	var n := (nb * Vector3.UP).normalized()
	var base := _verts.size()
	for s in segments + 1:
		var f := float(s) / float(segments)
		var a := deg_to_rad(-arc_deg * 0.5 + arc_deg * f)
		var dir := Vector3(sin(a), 0.0, -cos(a))
		for ring in 2:
			var r := inner_radius if ring == 0 else outer_radius
			_verts.append(xform * (dir * r))
			_normals.append(n)
			_colors.append(color)
			_uvs.append(Vector2(f, float(ring)))
	for s in segments:
		var a0 := base + s * 2
		_tri_auto(a0, a0 + 2, a0 + 1)
		_tri_auto(a0 + 1, a0 + 2, a0 + 3)
	return self


## Adds a triangle and fixes its winding so it faces along the average vertex normal.
func _tri_auto(a: int, b: int, c: int) -> void:
	var n := _normals[a] + _normals[b] + _normals[c]
	var cr := (_verts[b] - _verts[a]).cross(_verts[c] - _verts[a])
	if cr.dot(n) > 0.0:
		_indices.append_array([a, c, b])
	else:
		_indices.append_array([a, b, c])


# --- Helpers -----------------------------------------------------------------

## Basis whose Y axis points along [param dir] (normalised).
static func basis_from_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Transform helper: position + euler rotation (degrees) + scale.
static func xf(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	return Transform3D(b * Basis.from_scale(scl), pos)


## Evenly spaced points on a smooth Catmull-Rom curve through [param points].
static func smooth_profile(points: PackedVector2Array, steps_per_segment: int = 4) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := points.size()
	if n < 3:
		return points
	for i in n - 1:
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, n - 1)]
		for s in steps_per_segment:
			var t := float(s) / float(steps_per_segment)
			out.append(p1.cubic_interpolate(p2, p0, p3, t))
	out.append(points[n - 1])
	return out
