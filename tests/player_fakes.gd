extends RefCounted
## Shared helpers for the "player" module tests (test_player_*.gd).
## Not a test file itself (no test_ prefix). Preload it:
##   const Fakes := preload("res://tests/player_fakes.gd")


## An Enemy that only records what happens to it – no AI, model or loot, so the player
## tests do not depend on the enemies module.
class FakeEnemy extends Enemy:
	var fake_damage_log: Array[float] = []
	var fake_crit_log: Array[bool] = []
	var fake_attacker_log: Array[Node3D] = []
	var fake_knockback_log: Array[Vector3] = []
	var fake_stun_count := 0
	var fake_dead := false
	## Counts as a boss (RogueBlade's one-big-target rule ...).
	var fake_boss := false

	func _init() -> void:
		hp = 1000.0
		max_hp = 1000.0
		radius = 0.45

	func _enter_tree() -> void:
		pass

	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _physics_process(_delta: float) -> void:
		pass

	func is_dead() -> bool:
		return fake_dead

	func is_boss() -> bool:
		return fake_boss

	func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null,
			knockback: Vector3 = Vector3.ZERO) -> void:
		fake_damage_log.append(amount)
		fake_crit_log.append(is_crit)
		fake_attacker_log.append(attacker)
		fake_knockback_log.append(knockback)
		hp -= amount

	func apply_stun(_duration: float) -> void:
		fake_stun_count += 1

	func fake_hits() -> int:
		return fake_damage_log.size()


## A Node3D under the root that is also the current scene (Vfx falls back to it).
static func make_world(tree: SceneTree) -> Node3D:
	var world := Node3D.new()
	world.name = "PlayerTestWorld"
	tree.root.add_child(world)
	tree.current_scene = world
	return world


static func free_world(world: Node3D) -> void:
	if world != null and is_instance_valid(world):
		world.free()


static func make_slot(index: int, class_id: StringName) -> PlayerSlot:
	var slot := PlayerSlot.new(index, ScriptedInput.new("test:%d" % index), PlayerManager.PLAYER_COLORS[index])
	slot.class_data = Db.get_class_data(class_id)
	return slot


## A real Player of [param class_id]. Without the universal base Mastery (Stats.BASE_MASTERY)
## so exact-number tests see 0 Mastery unless they add some (Mastery tests set their own).
static func spawn_player(world: Node3D, index: int, class_id: StringName, pos: Vector3 = Vector3.ZERO) -> Player:
	var p := Player.create(make_slot(index, class_id))
	p.stats.remove_source(&"base")
	world.add_child(p)
	p.global_position = pos
	return p


static func spawn_enemy(world: Node3D, pos: Vector3, radius: float = 0.45) -> FakeEnemy:
	var e := FakeEnemy.new()
	e.radius = radius
	e.add_to_group(&"enemies")
	world.add_child(e)
	e.global_position = pos
	return e


static func weapon(kind: WeaponData.AttackKind, base_damage: float = 5.0, attack_range: float = 2.0,
		arc_degrees: float = 100.0) -> WeaponData:
	var w := WeaponData.new()
	w.id = &"test_weapon"
	w.weapon_type = &"sword" if kind == WeaponData.AttackKind.MELEE_ARC else &"wand"
	w.attack_kind = kind
	w.base_damage = base_damage
	w.cooldown = 1.0
	w.attack_range = attack_range
	w.arc_degrees = arc_degrees
	w.knockback = 2.0
	return w


## Steps a node's _physics_process for [param seconds] with a fixed delta.
static func step(node: Node, seconds: float, delta: float = 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		node._physics_process(delta)
		t += delta
