extends RefCounted
## Shared helpers of the Warlock talent tests (test_talents_warlock*.gd). Not a test file
## itself (no test_ prefix). Preload it:
##   const WFakes := preload("res://tests/talents_warlock_fakes.gd")

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0


## An enemy that takes real damage and dies like a real one – [signal Enemy.died] with the
## killer's slot index, then Player.notify_kill, and it leaves the "enemies" group – but drops
## no loot, draws nothing from RunState.rng and stays in the tree (tests look at it
## afterwards). No AI / model. Slows and stuns run the real Enemy code (they only set timers);
## stuns are counted.
class DyingEnemy extends Enemy:
	var hits: Array[float] = []
	var attackers: Array[Node3D] = []
	var stun_calls := 0

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

	func take_damage(amount: float, _is_crit: bool = false, attacker: Node3D = null,
			_knockback: Vector3 = Vector3.ZERO) -> void:
		if is_dead() or amount <= 0.0:
			return
		hits.append(amount)
		attackers.append(attacker)
		hp -= amount
		if hp <= 0.0:
			die_now(attacker)

	func apply_stun(duration: float) -> void:
		stun_calls += 1
		super(duration)

	## Dies now (credit to [param attacker] when it is a Player; null = nobody's kill).
	func die_now(attacker: Node3D = null) -> void:
		if _dead:
			return
		_dead = true
		hp = minf(hp, 0.0)
		if is_in_group(&"enemies"):
			remove_from_group(&"enemies")
		EnemyGrid.mark_dirty()
		var killer: Player = attacker as Player if attacker != null and is_instance_valid(attacker) else null
		died.emit(self, killer.slot.index if killer != null and killer.slot != null else -1)
		if killer != null:
			killer.notify_kill(self)

	func total() -> float:
		var t := 0.0
		for v in hits:
			t += v
		return t


static func spawn_enemy(world: Node3D, pos: Vector3, hp: float = 1000.0) -> DyingEnemy:
	var e := DyingEnemy.new()
	e.hp = hp
	e.max_hp = maxf(hp, 1.0)
	e.add_to_group(&"enemies")
	world.add_child(e)
	e.global_position = pos
	EnemyGrid.mark_dirty()
	return e


## Steps [param node]'s _physics_process for [param seconds] at 60 Hz.
static func step(node: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		node._physics_process(DT)
		t += DT


## Steps the hero's ability runner (cooldowns, channels, Mastery) for [param seconds].
static func step_abilities(p: Player, seconds: float) -> void:
	step(p.abilities, seconds)


## Steps the hero's talent / set scripts (PlayerBonuses.tick) for [param seconds].
static func step_bonuses(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		p.bonuses.tick(DT)
		t += DT


static func mastery(p: Player) -> WarlockMastery:
	return p.abilities.mastery as WarlockMastery


static func afflictions(p: Player) -> WarlockAfflictions:
	return WarlockAfflictions.of(p, false)


static func shards(p: Player) -> ClassResource:
	return p.abilities.get_resource(&"soul_shard")


## The ids TalentBot picks for [param p] (bot [param slot_index]), point by point.
static func bot_path(p: Player, slot_index: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in 100:
		var t := TalentBot.next_talent(p, slot_index)
		if t == null or not p.talents.add(t.id):
			break
		out.append(t.id)
	return out


## [param n] copies of [param id] (bot path tables).
static func times(id: StringName, n: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in n:
		out.append(id)
	return out
