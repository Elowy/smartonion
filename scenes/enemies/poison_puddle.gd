class_name PoisonPuddle
extends Node3D
## The Plague Ghoul's death puddle (M6, GDD 8): a green disc on the ground that hurts HEROES
## only (enemies walk through it), [member tick_interval] seconds apart, for [member duration]
## seconds. No telegraph – it is already on the ground when the ghoul dies, and the hero
## standing next to the kill takes the first tick half a second later unless it steps out.
## Numbers come from the dead enemy's EnemyData ([method Enemy._on_death_effect]): the damage
## per tick is a fraction of the ghoul's contact damage at its wave.
##
## At most [constant MAX_ALIVE] puddles live at once: spawning the next one frees the oldest.
## In the groups &"enemy_hazards" (the hazards of enemies: WaveDirector.stop() frees the group,
## and the bots read [method hazard_push] to step out of a puddle like out of a boss's circle)
## and &"ability_areas" (the group Main.open_intermission() sweeps too), so a puddle never
## survives its wave into the market or the next wave. Parent: the arena's entity root.
## Damage is KIND_AOE without a source (Avoidance, Armor, Dodge and Block count as for any
## ground effect; nothing "struck" it, so no Thorns / Retribution). No RNG.

## The group every hazard of an enemy joins.
const GROUP := &"enemy_hazards"
## The group the wave end sweeps (see the class doc).
const SWEPT_GROUP := &"ability_areas"
## The most puddles alive at once; the next one removes the oldest.
const MAX_ALIVE := 12
const FADE_IN := 0.2
const FADE_OUT := 0.45
## Height of the disc above the floor (the ability areas use 0.06).
const DISC_Y := 0.055
const DISC_HEIGHT := 0.03
const BUBBLES := 5

var radius := 1.6
var duration := 3.0
var tick_interval := 0.5
## Raw damage of each tick (before the hero's Armor etc.).
var damage_per_tick := 1.0
var color := Color(0.36, 0.78, 0.2)
## Seconds since it appeared.
var age := 0.0
## Ticks dealt so far (each one hits every hero inside).
var ticks_done := 0
## Spawn order (the tie-break between puddles of the same age).
var serial := 0

static var _next_serial := 0

var _tick_left := 0.0
var _gone := false
var _disc_material: StandardMaterial3D
var _rim_material: StandardMaterial3D
var _bubbles: Array[MeshInstance3D] = []


## Puts a puddle at [param center] (XZ) under [param parent] (the arena's entity root); the
## 13th alive puddle makes the oldest vanish. Returns null without a parent.
static func spawn(parent: Node, center: Vector3, p_radius: float, p_duration: float,
		p_tick_interval: float, p_damage: float, p_color: Color) -> PoisonPuddle:
	if parent == null or not is_instance_valid(parent):
		return null
	var puddle := PoisonPuddle.new()
	puddle.name = "PoisonPuddle"
	puddle.radius = maxf(0.2, p_radius)
	puddle.duration = maxf(0.1, p_duration)
	puddle.tick_interval = maxf(0.05, p_tick_interval)
	puddle.damage_per_tick = maxf(0.0, p_damage)
	puddle.color = p_color
	puddle._tick_left = puddle.tick_interval
	puddle.serial = _next_serial
	_next_serial += 1
	if parent.is_inside_tree():
		_enforce_cap(parent.get_tree())
	parent.add_child(puddle)
	puddle.global_position = Vector3(center.x, 0.0, center.z)
	return puddle


## The puddles alive in [param tree] (not removed, not queued), oldest first.
static func alive(tree: SceneTree) -> Array[PoisonPuddle]:
	var out: Array[PoisonPuddle] = []
	if tree == null:
		return out
	for node in tree.get_nodes_in_group(GROUP):
		var p := node as PoisonPuddle
		if p != null and is_instance_valid(p) and not p._gone and not p.is_queued_for_deletion():
			out.append(p)
	out.sort_custom(func(a: PoisonPuddle, b: PoisonPuddle) -> bool:
		return a.age > b.age or (a.age == b.age and a.serial < b.serial))
	return out


## Makes room for one more: removes the oldest puddles until fewer than MAX_ALIVE are left.
static func _enforce_cap(tree: SceneTree) -> void:
	var list := alive(tree)
	var excess := list.size() - (MAX_ALIVE - 1)
	for i in maxi(0, excess):
		list[i].remove()


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SWEPT_GROUP)
	_build_visual()


func _physics_process(delta: float) -> void:
	if _gone or is_queued_for_deletion():
		return
	age += delta
	_tick_left -= delta
	while _tick_left <= 0.0001 and age <= duration + 0.0001:
		_tick_left += tick_interval
		_tick()
	_update_visual()
	if age >= duration:
		remove()


## Takes the puddle away now (expired, or pushed out by a newer one).
func remove() -> void:
	if _gone:
		return
	_gone = true
	remove_from_group(GROUP)
	remove_from_group(SWEPT_GROUP)
	queue_free()


func is_gone() -> bool:
	return _gone


## Whether the ground point [param pos] (XZ) is inside the puddle.
func covers(pos: Vector3) -> bool:
	var dx := pos.x - global_position.x
	var dz := pos.z - global_position.z
	return dx * dx + dz * dz <= radius * radius


## Whether standing in it can still hurt: until it is gone (expired, pushed out by a newer one)
## and while it deals damage at all. The same query as [method EnemyHazard.is_dangerous].
func is_dangerous() -> bool:
	return not _gone and not is_queued_for_deletion() and age < duration and damage_per_tick > 0.0


## The bots' steering out of the puddle ([method EnemyHazard.hazard_push]'s contract, read by
## BotInput through the group &"enemy_hazards"): 1..2 long inside radius + [param margin],
## radially away from the middle, zero outside or when it is harmless. Only the arena's heroes
## are hurt, so nothing else uses it.
func hazard_push(from: Vector3, margin: float = EnemyHazard.BOT_MARGIN) -> Vector2:
	if not is_dangerous() or not is_inside_tree():
		return Vector2.ZERO
	return EnemyHazard.circle_push(global_position, radius, from, margin)


## One tick: every living hero whose centre is inside takes [member damage_per_tick].
func _tick() -> void:
	ticks_done += 1
	if damage_per_tick <= 0.0 or not is_inside_tree():
		return
	for p in Enemy.cached_players(get_tree()):
		if not Enemy.is_living_player(p) or not covers(p.global_position):
			continue
		p.take_damage(damage_per_tick, CombatMath.KIND_AOE, null)
		if _gone or not is_inside_tree():
			return


# --- Look ----------------------------------------------------------------------------

func _build_visual() -> void:
	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = DISC_HEIGHT
	mesh.radial_segments = 36
	mesh.rings = 0
	disc.mesh = mesh
	_disc_material = StandardMaterial3D.new()
	_disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_disc_material.albedo_color = Color(color.r, color.g, color.b, 0.0)
	disc.material_override = _disc_material
	disc.position.y = DISC_Y
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	# A brighter rim keeps the edge readable on every floor colour.
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.05, radius - 0.09)
	torus.outer_radius = radius
	torus.rings = 36
	torus.ring_segments = 4
	rim.mesh = torus
	_rim_material = StandardMaterial3D.new()
	_rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rim_material.albedo_color = Color(0.7, 1.0, 0.4, 0.0)
	rim.material_override = _rim_material
	rim.position.y = DISC_Y + 0.02
	rim.scale = Vector3(1.0, 0.25, 1.0)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)
	# Bubbles bobbing on the surface (golden-angle spread, no RNG).
	var bubble_mesh := SphereMesh.new()
	bubble_mesh.radius = 0.1
	bubble_mesh.height = 0.2
	bubble_mesh.radial_segments = 8
	bubble_mesh.rings = 4
	var bubble_material := Mats.glow(Color(0.62, 0.95, 0.35), 1.2)
	for i in BUBBLES:
		var b := MeshInstance3D.new()
		b.name = "Bubble%d" % i
		b.mesh = bubble_mesh
		b.material_override = bubble_material
		var a := 2.399963 * float(i + 1)
		var r := radius * (0.25 + 0.14 * float(i))
		b.position = Vector3(sin(a) * r, DISC_Y, -cos(a) * r)
		b.scale = Vector3.ONE * 0.01
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
		_bubbles.append(b)
	_update_visual()


func _update_visual() -> void:
	if _disc_material == null:
		return
	var fade := clampf(minf(age / FADE_IN, (duration - age) / FADE_OUT), 0.0, 1.0)
	var pulse := 0.9 + 0.1 * sin(age * 7.0)
	_disc_material.albedo_color.a = 0.5 * fade * pulse
	_rim_material.albedo_color.a = 0.85 * fade
	for i in _bubbles.size():
		var phase := age * 2.6 + float(i) * 1.7
		var s := maxf(0.0, sin(phase)) * 0.9 * fade
		_bubbles[i].scale = Vector3.ONE * maxf(0.01, s)
		_bubbles[i].position.y = DISC_Y + 0.03 + s * 0.1
