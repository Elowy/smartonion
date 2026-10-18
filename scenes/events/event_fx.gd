class_name EventFx
extends RefCounted
## Small shared pieces of the mid-wave events' look (M6b EVENTS): a flat ground ring, a billboard
## progress bar and a billboard name tag, plus the gold / XP burst the events pay out with.
## Everything here is visual (no gameplay state) apart from [method burst], which drops Pickups.

## Height of the flat rings above the ground (the ability areas use 0.06, hazards 0.05).
const RING_Y := 0.04
## Bar size (m) of [method bar] and its default height above the node origin.
const BAR_SIZE := Vector2(1.7, 0.3)
const LABEL_PIXEL_SIZE := 0.00042
const LABEL_FONT_SIZE := 40


## A flat ring of [param radius] m around [param parent]'s origin, drawn with the shared ring shader.
## [param inner] / [param outer] are fractions of the radius (0..1), [param arc] the filled share of
## the circle (1 = all of it). Returns the MeshInstance3D ([method Mats.set_ring] reconfigures it).
static func ring(parent: Node3D, node_name: String, radius: float, color: Color, inner: float, outer: float,
		fill_alpha: float = 0.0, arc: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = MeshKit.cached("event:quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)
	mi.material_override = Mats.ring()
	mi.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	mi.position.y = RING_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	Mats.set_ring(mi, color, inner, outer, fill_alpha, arc)
	return mi


## A camera-facing progress bar (the revive cast bar's look) [param height] m above [param parent]'s
## origin, in [param color]; [method Mats.set_cast_bar] moves it. Hidden until the first update.
static func bar(parent: Node3D, node_name: String, height: float, color: Color, progress: float = 1.0,
		size: Vector2 = BAR_SIZE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = MeshKit.cached("event:bar_quad", func() -> Mesh:
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		return q)
	mi.material_override = Mats.cast_bar()
	mi.position = Vector3(0.0, height, 0.0)
	mi.scale = Vector3(size.x, size.y, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	Mats.set_cast_bar(mi, color, progress)
	return mi


## A billboard text tag whose bottom edge is [param height] m above [param parent]'s origin: fixed on-screen
## size (like the Loot Goblin's tag), no depth test, outlined.
static func label(parent: Node3D, node_name: String, text: String, height: float, color: Color) -> Label3D:
	var l := Label3D.new()
	l.name = node_name
	l.text = text
	l.font_size = LABEL_FONT_SIZE
	l.outline_size = 12
	l.pixel_size = LABEL_PIXEL_SIZE
	l.modulate = color
	l.outline_modulate = Color(0.08, 0.05, 0.02)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.no_depth_test = true
	l.shaded = false
	l.double_sided = true
	l.render_priority = 24
	l.outline_render_priority = 23
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.position = Vector3(0.0, height, 0.0)
	parent.add_child(l)
	return l


## The living enemies in [param tree] whose centre lies within [param radius] m (XZ) of [param center]
## (with [param bodies]: whose body touches the circle). Reads the enemy grid, so it is cheap with a crowd.
static func enemies_within(tree: SceneTree, center: Vector3, radius: float, bodies: bool = false) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if tree == null or radius < 0.0:
		return out
	for node in EnemyGrid.gather_around(tree, center, radius):
		var e := node as Enemy
		if e == null or not e.is_inside_tree() or e.is_dead() or e.is_queued_for_deletion():
			continue
		var reach := radius + (e.radius if bodies else 0.0)
		var dx := e.global_position.x - center.x
		var dz := e.global_position.z - center.z
		if dx * dx + dz * dz <= reach * reach:
			out.append(e)
	return out


## Splits [param gold] and [param xp] into [param piles] Pickups on a ring of [param radius] m around
## [param center] (under [param parent]; piles without gold and XP are skipped; no rng, the points are
## evenly spread and clamped into the arena). The whole amounts are always paid out. Returns the pickups.
static func burst(parent: Node, center: Vector3, gold: int, xp: int, piles: int = 8,
		radius: float = 1.0) -> Array[Pickup]:
	var out: Array[Pickup] = []
	if parent == null or not is_instance_valid(parent) or piles <= 0:
		return out
	for i in piles:
		var g := floori(float(gold) / piles) + (1 if i < gold % piles else 0)
		var x := floori(float(xp) / piles) + (1 if i < xp % piles else 0)
		if g <= 0 and x <= 0:
			continue
		var a := TAU * float(i) / float(piles)
		var at := Vector3(center.x + cos(a) * radius, 0.0, center.z + sin(a) * radius)
		if Arena.current != null and is_instance_valid(Arena.current):
			at = Arena.current.clamp_point(at, 0.3)
		var p := Pickup.drop(parent, g, x, at)
		if p != null:
			out.append(p)
	return out
