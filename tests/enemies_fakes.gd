extends RefCounted
## Shared helpers for the "enemies" module tests (test_enemies_*.gd).
## Not a test file itself (no test_ prefix). Preload it:
##   const EFakes := preload("res://tests/enemies_fakes.gd")


## A Player that only records the damage it receives – no input, model, weapons or AI.
class FakePlayer extends Player:
	var fake_hits: Array[float] = []
	var fake_kinds: Array[StringName] = []
	var fake_sources: Array[Node3D] = []

	func _init() -> void:
		add_to_group(&"players")

	func _ready() -> void:
		pass

	func _physics_process(_delta: float) -> void:
		pass

	func take_damage(raw: float, kind: StringName = CombatMath.KIND_MELEE, source: Node3D = null) -> void:
		fake_hits.append(raw)
		fake_kinds.append(kind)
		fake_sources.append(source)

	## The Flesh Golem's hook (M6): records {raw, toward, distance, source}; lands unless
	## [member fake_hook_dodges].
	var fake_hooks: Array[Dictionary] = []
	var fake_hook_dodges := false

	func take_hook(raw: float, toward: Vector3, distance: float, source: Node3D = null) -> bool:
		fake_hooks.append({"raw": raw, "toward": toward, "distance": distance, "source": source})
		return not fake_hook_dodges


## A bare Arena (no level geometry) with an entities root. Optional scripted
## random_point() results make spawn-point tests exact.
class TestArena extends Arena:
	var scripted_points: Array[Vector3] = []

	func _init() -> void:
		name = "TestArena"
		entities = Node3D.new()
		entities.name = "Entities"
		add_child(entities)

	func _enter_tree() -> void:
		Arena.current = self

	func _exit_tree() -> void:
		if Arena.current == self:
			Arena.current = null

	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _physics_process(_delta: float) -> void:
		pass

	func random_point(rng: RandomNumberGenerator, margin: float = 1.5) -> Vector3:
		if not scripted_points.is_empty():
			return scripted_points.pop_front()
		var b := get_bounds().grow(-margin)
		return Vector3(rng.randf_range(b.position.x, b.end.x), 0.0, rng.randf_range(b.position.y, b.end.y))

	func get_bounds() -> Rect2:
		return Rect2(-Arena.SIZE / 2.0, Arena.SIZE)

	func clamp_point(p: Vector3, margin: float = 0.5) -> Vector3:
		var b := get_bounds().grow(-margin)
		return Vector3(clampf(p.x, b.position.x, b.end.x), p.y, clampf(p.z, b.position.y, b.end.y))


## Root world for a test: a Node3D (current scene, so Vfx has a parent) holding a TestArena.
static func make_world(tree: SceneTree) -> Node3D:
	Enemy.invalidate_player_cache()
	var world := Node3D.new()
	world.name = "EnemiesTestWorld"
	tree.root.add_child(world)
	tree.current_scene = world
	var arena := TestArena.new()
	world.add_child(arena)
	return world


static func arena_of(world: Node3D) -> TestArena:
	return world.get_node(^"TestArena") as TestArena


static func free_world(tree: SceneTree, world: Node3D) -> void:
	if world != null and is_instance_valid(world):
		if tree.current_scene == world:
			tree.current_scene = null
		world.free()
	Enemy.invalidate_player_cache()


static func spawn_player(world: Node3D, pos: Vector3, slot_index: int = -1) -> FakePlayer:
	var p := FakePlayer.new()
	if slot_index >= 0:
		p.slot = PlayerSlot.new(slot_index, ScriptedInput.new("test:%d" % slot_index),
				PlayerManager.PLAYER_COLORS[slot_index])
	arena_of(world).entities.add_child(p)
	p.global_position = pos
	Enemy.invalidate_player_cache()
	return p


static func enemy_data(behavior: EnemyData.Behavior = EnemyData.Behavior.CHASE) -> EnemyData:
	var d := EnemyData.new()
	d.id = &"test_enemy"
	d.display_name = "Test Enemy"
	d.behavior = behavior
	d.max_hp = 10.0
	d.hp_growth = 0.12
	d.hp_compound = 0.0  # plain GDD 9 additive growth; tests opt into the compounding factor
	d.contact_damage = 3.0
	d.damage_growth = 0.08
	d.damage_compound = 0.0
	d.move_speed = 3.0
	d.radius = 0.45
	d.gold = 2
	d.xp = 3
	d.model_style = &"skeleton"
	return d


static func spawn_enemy(world: Node3D, data: EnemyData, pos: Vector3, p_wave: int = 1) -> Enemy:
	var e := Enemy.create(data, p_wave)
	arena_of(world).entities.add_child(e)
	e.global_position = pos
	return e


## Every Enemy / Pickup currently under the arena's entities (not queued for deletion).
static func live_children_of_type(world: Node3D, script_class: GDScript) -> Array[Node]:
	var out: Array[Node] = []
	for child in arena_of(world).entities.get_children():
		if is_instance_of(child, script_class) and not child.is_queued_for_deletion():
			out.append(child)
	return out


## Steps a node's _physics_process for [param seconds] with a fixed delta.
static func step(node: Node, seconds: float, delta: float = 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			return
		node._physics_process(delta)
		t += delta


## Steps several nodes together (same order every frame).
static func step_all(nodes: Array[Node], seconds: float, delta: float = 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		for node in nodes:
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				node._physics_process(delta)
		t += delta


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
