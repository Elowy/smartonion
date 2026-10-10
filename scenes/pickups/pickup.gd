class_name Pickup
extends Node3D
## Loot dropped by enemies: gold for the shared wallet + team XP (GDD 10).
## Group &"pickups". Flies to the nearest living player within its pickup range.
##
## Looks like a small spinning golden coin with a faint glow (an XP-only drop is a small
## glowing orb). Once a player's [method StatBlock.pickup_range] covers it, it accelerates
## towards that player and is collected within COLLECT_DISTANCE: gold goes through the
## collector's Gold Find ([method RunState.add_gold_for] keeps the fraction per player slot),
## XP to the shared bar. Loot banked at the wave end has no collector, so no Gold Find.
## When many pickups lie around, new drops merge into a nearby idle one ([method drop]).
## Idle pickups read the collectors from the shared per-tick [LivingPlayers] snapshot (positions
## and pickup range squared as packed floats) instead of calling into every player each tick;
## with IDLE_STAGGER_THRESHOLD+ pickups around, an idle one only looks every IDLE_CHECK_TICKS
## ticks (phases spread by the pickup count when it lands, so the work is spread evenly and
## the run stays deterministic).

const COLLECT_DISTANCE := 0.5
## Speed (m/s) when a player starts pulling the pickup, acceleration and top speed.
const START_SPEED := 3.0
const ACCELERATION := 40.0
const MAX_SPEED := 22.0

## From this many pickups on, new drops merge into an idle pickup within MERGE_RADIUS.
const MERGE_THRESHOLD := 120
const MERGE_RADIUS := 3.0
## From this many pickups on, new drops merge into the nearest idle pickup at any distance.
const HARD_CAP := 220
## From this many pickups on, idle ones look for a collector only every IDLE_CHECK_TICKS
## physics ticks (a pickup starts flying at most (IDLE_CHECK_TICKS - 1) / 60 s late).
const IDLE_STAGGER_THRESHOLD := 64
const IDLE_CHECK_TICKS := 3

const HOVER_HEIGHT := 0.32
const BOB_HEIGHT := 0.06
const BOB_SPEED := 3.4
const SPIN_SPEED := 3.2
const COIN_RADIUS := 0.15
const COIN_THICKNESS := 0.045
const COIN_COLOR := Color(1.0, 0.77, 0.22)
const COIN_EMISSION := Color(1.0, 0.62, 0.12)
const GLOW_COLOR := Color(1.0, 0.8, 0.35, 0.42)
const XP_COLOR := Color(0.45, 0.85, 1.0)
const GLOW_SIZE := 0.75

var gold := 0
var xp := 0
## The player currently pulling this pickup (null while it lies idle).
var target: Player
## Current flight speed towards [member target] (m/s).
var speed := 0.0

var _collected := false
var _time := 0.0
var _visual: Node3D
var _body: MeshInstance3D
var _is_coin := true
## Serial of the LivingPlayers snapshot this pickup last read.
var _players_serial := -1
## Idle ticks left until the next collector check while the stagger is on.
var _idle_wait := 0

static var _coin_mesh: CylinderMesh
static var _orb_mesh: SphereMesh
static var _glow_mesh: QuadMesh
static var _glow_material: StandardMaterial3D


static func create(p_gold: int, p_xp: int) -> Pickup:
	var p := Pickup.new()
	p.name = "Pickup"
	p.gold = maxi(0, p_gold)
	p.xp = maxi(0, p_xp)
	p.add_to_group(&"pickups")
	p._build_visual()
	return p


## Drops loot at [param world_pos] under [param parent]. With MERGE_THRESHOLD+ pickups in
## the tree the loot is merged into a nearby idle pickup instead (keeps node counts low).
## Returns the pickup that holds the loot (null if nothing was dropped).
static func drop(parent: Node, p_gold: int, p_xp: int, world_pos: Vector3) -> Pickup:
	if parent == null or (p_gold <= 0 and p_xp <= 0):
		return null
	var tree := parent.get_tree()
	if tree != null:
		var count := tree.get_node_count_in_group(&"pickups")
		if count >= MERGE_THRESHOLD:
			var max_dist := MERGE_RADIUS if count < HARD_CAP else INF
			var host := find_merge_host(tree, world_pos, max_dist)
			if host != null:
				host.absorb(p_gold, p_xp)
				return host
	var p := Pickup.create(p_gold, p_xp)
	var parent_3d := parent as Node3D
	if parent_3d != null and parent_3d.is_inside_tree():
		p.position = parent_3d.global_transform.affine_inverse() * Vector3(world_pos.x, 0.0, world_pos.z)
	else:
		p.position = Vector3(world_pos.x, 0.0, world_pos.z)
	parent.add_child(p)
	return p


## Nearest idle (not flying, not collected) pickup within [param max_dist] of [param pos].
static func find_merge_host(tree: SceneTree, pos: Vector3, max_dist: float) -> Pickup:
	var best: Pickup = null
	var best_d := max_dist * max_dist if max_dist < INF else INF
	for node in tree.get_nodes_in_group(&"pickups"):
		var p := node as Pickup
		if p == null or not p.is_idle() or not p.is_inside_tree():
			continue
		var at := p.global_position
		var dx := at.x - pos.x
		var dz := at.z - pos.z
		var d := dx * dx + dz * dz
		if d <= best_d:
			best_d = d
			best = p
	return best


## True while the pickup lies on the ground waiting for a collector.
func is_idle() -> bool:
	return not _collected and target == null


func is_collected() -> bool:
	return _collected


## Adds more loot to this pickup (merging).
func absorb(p_gold: int, p_xp: int) -> void:
	if _collected:
		return
	gold += maxi(0, p_gold)
	xp += maxi(0, p_xp)
	_update_look()


## [param player] picks the loot up: gold (with the player's Gold Find) to the shared
## wallet, XP to the shared bar, a sparkle, then the pickup frees itself.
func collect(player: Player) -> void:
	if _collected:
		return
	_collected = true
	if player != null and is_instance_valid(player):
		var slot_index := player.slot.index if player.slot != null else -1
		RunState.add_gold_for(slot_index, gold, player.stats.get_stat(Stats.GOLD_FIND))
	else:
		RunState.add_gold(gold)
	RunState.add_xp(xp)
	var pos := global_position if is_inside_tree() else position
	Vfx.pickup_sparkle(pos + Vector3.UP * HOVER_HEIGHT)
	_remove()


## Wave end: credits the loot to the team without a collector (so without Gold Find),
## then frees itself.
func collect_to_bank() -> void:
	if _collected:
		return
	_collected = true
	RunState.add_gold(gold)
	RunState.add_xp(xp)
	_remove()


# --- Frame update ----------------------------------------------------------------

func _enter_tree() -> void:
	# Stagger phase (only used with many pickups): consecutive drops get different phases.
	_idle_wait = get_tree().get_node_count_in_group(&"pickups") % IDLE_CHECK_TICKS


func _physics_process(delta: float) -> void:
	if _collected or not is_inside_tree():
		return
	if target != null and not Enemy.is_living_player(target):
		target = null
		speed = 0.0
	if target == null:
		if _idle_wait > 0 and get_tree().get_node_count_in_group(&"pickups") >= IDLE_STAGGER_THRESHOLD:
			_idle_wait -= 1
			return
		_idle_wait = IDLE_CHECK_TICKS - 1
		target = _find_collector(global_position)
		if target == null:
			return
		speed = START_SPEED
	var here := global_position
	var goal := target.global_position
	var dx := goal.x - here.x
	var dz := goal.z - here.z
	var dist := sqrt(dx * dx + dz * dz)
	if dist <= COLLECT_DISTANCE:
		collect(target)
		return
	speed = minf(MAX_SPEED, speed + ACCELERATION * delta)
	var step := speed * delta
	if step >= dist - COLLECT_DISTANCE:
		global_position = Vector3(goal.x, here.y, goal.z)
		collect(target)
		return
	var k := step / dist
	global_position = Vector3(here.x + dx * k, here.y, here.z + dz * k)


func _process(delta: float) -> void:
	if _visual == null:
		return
	_time += delta
	_visual.position.y = HOVER_HEIGHT + sin(_time * BOB_SPEED) * BOB_HEIGHT
	_visual.rotate_y(SPIN_SPEED * delta)


## Nearest living player whose pickup range reaches [param here] (from the shared
## [LivingPlayers] snapshot; the winner is re-checked, a stale one falls back to a live scan).
func _find_collector(here: Vector3) -> Player:
	_players_serial = LivingPlayers.refresh(get_tree(), _players_serial)
	var xs := LivingPlayers.pos_x
	var zs := LivingPlayers.pos_z
	var ranges := LivingPlayers.pickup_range_sq
	var best_i := -1
	var best_d := INF
	for i in LivingPlayers.count:
		var dx := xs[i] - here.x
		var dz := zs[i] - here.z
		var d := dx * dx + dz * dz
		if d < best_d and d <= ranges[i]:
			best_d = d
			best_i = i
	if best_i < 0:
		return null
	var players := LivingPlayers.players
	if Enemy.is_living_player(players[best_i]):
		return players[best_i]
	return _find_collector_live(here)


## [method _find_collector] without the snapshot (every player checked now).
func _find_collector_live(here: Vector3) -> Player:
	var best: Player = null
	var best_d := INF
	for p in Enemy.cached_players(get_tree()):
		if not Enemy.is_living_player(p):
			continue
		var pos := p.global_position
		var dx := pos.x - here.x
		var dz := pos.z - here.z
		var d := dx * dx + dz * dz
		if d >= best_d:
			continue
		var reach := p.stats.pickup_range()
		if d <= reach * reach:
			best_d = d
			best = p
	return best


func _remove() -> void:
	target = null
	if is_in_group(&"pickups"):
		remove_from_group(&"pickups")
	set_physics_process(false)
	set_process(false)
	queue_free()


# --- Look --------------------------------------------------------------------------

func _build_visual() -> void:
	_ensure_shared_resources()
	# Desynchronise the bob / spin of neighbouring coins without touching the gameplay RNG.
	_time = float(get_instance_id() % 997) * 0.173
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.position = Vector3(0.0, HOVER_HEIGHT, 0.0)
	add_child(_visual)

	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	glow.mesh = _glow_mesh
	glow.material_override = _glow_material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(glow)

	_body = MeshInstance3D.new()
	_body.name = "Coin"
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(_body)
	_is_coin = gold > 0 or xp <= 0
	_apply_body_look()
	_update_look()


func _apply_body_look() -> void:
	if _is_coin:
		_body.mesh = _coin_mesh
		# Stand the coin up (axis along Z) so its face shows towards the camera as it spins.
		_body.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		_body.material_override = Mats.toon_emissive(COIN_COLOR, COIN_EMISSION, 0.45)
	else:
		_body.mesh = _orb_mesh
		_body.rotation = Vector3.ZERO
		_body.material_override = Mats.glow(XP_COLOR, 1.6)


## Bigger (merged) pickups look a little bigger.
func _update_look() -> void:
	if _visual == null:
		return
	var want_coin := gold > 0 or xp <= 0
	if want_coin != _is_coin:
		_is_coin = want_coin
		_apply_body_look()
	var value := maxi(1, gold if _is_coin else xp)
	var s := clampf(1.0 + 0.22 * log(float(value)) / log(2.0), 1.0, 2.2)
	_visual.scale = Vector3(s, s, s)


static func _ensure_shared_resources() -> void:
	if _coin_mesh != null:
		return
	_coin_mesh = CylinderMesh.new()
	_coin_mesh.top_radius = COIN_RADIUS
	_coin_mesh.bottom_radius = COIN_RADIUS
	_coin_mesh.height = COIN_THICKNESS
	_coin_mesh.radial_segments = 14
	_coin_mesh.rings = 1

	_orb_mesh = SphereMesh.new()
	_orb_mesh.radius = 0.11
	_orb_mesh.height = 0.22
	_orb_mesh.radial_segments = 10
	_orb_mesh.rings = 6

	_glow_mesh = QuadMesh.new()
	_glow_mesh.size = Vector2(GLOW_SIZE, GLOW_SIZE)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.35, Color(1.0, 1.0, 1.0, 0.45))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64

	_glow_material = StandardMaterial3D.new()
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_glow_material.albedo_texture = tex
	_glow_material.albedo_color = GLOW_COLOR
