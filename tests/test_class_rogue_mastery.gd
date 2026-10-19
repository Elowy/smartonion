extends TestCase
## Rogue Mastery "Deadly Poison" (M3, GDD 3.4): crits poison the target with a stacking
## Nature DoT.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

## An enemy that dies when its HP runs out (a crit can kill it).
class MortalEnemy extends Enemy:
	func _init() -> void:
		hp = 10.0
		max_hp = 10.0
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
		return hp <= 0.0

	func take_damage(amount: float, _is_crit: bool = false, _attacker: Node3D = null,
			_knockback: Vector3 = Vector3.ZERO) -> void:
		hp -= amount


var world: Node3D
var rogue: Player
var enemy: Fakes.FakeEnemy
var mastery: RogueMastery


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 12)
	world = Fakes.make_world(tree)
	rogue = Fakes.spawn_player(world, 0, &"rogue")
	rogue.stats.set_source(&"test", {Stats.CRIT: -500.0})
	enemy = Fakes.spawn_enemy(world, Vector3(0, 0, -3.0))
	mastery = rogue.abilities.mastery as RogueMastery


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	rogue = null
	enemy = null
	mastery = null
	PlayerManager.clear()
	EnemyGrid.mark_dirty()


func _run(seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		rogue.abilities._physics_process(DT)
		t += DT


func _total() -> float:
	var sum := 0.0
	for d in enemy.fake_damage_log:
		sum += d
	return sum


func test_only_crits_poison() -> void:
	WeaponRunner.apply_hit(rogue, enemy, 10.0, false, Vector3.ZERO)
	check_eq(mastery.stacks_on(enemy), 0, "a normal hit does not")
	WeaponRunner.apply_hit(rogue, enemy, 10.0, true, Vector3.ZERO)
	check_eq(mastery.stacks_on(enemy), 1, "a crit does")
	check_eq(mastery.poisoned_count(), 1, "one poisoned enemy")


func test_poison_damage_is_mastery_scaled() -> void:
	mastery.on_hit(enemy, 20.0, true)
	check_near(mastery.dps_on(enemy), 20.0 * 0.2 / 4.0, 0.001, "20% of the crit over 4 s at 0 Mastery")
	enemy.free()
	enemy = Fakes.spawn_enemy(world, Vector3(0, 0, -3.0))
	rogue.stats.set_source(&"mastery", {Stats.MASTERY: 30.0})
	mastery.on_hit(enemy, 20.0, true)
	check_near(mastery.dps_on(enemy), 20.0 * 0.5 / 4.0, 0.001, "+1% per Mastery point")
	check(mastery.describe().begins_with("Lethal Venom"), "tooltip")


func test_poison_ticks_for_the_stack_damage_over_four_seconds() -> void:
	mastery.on_hit(enemy, 40.0, true)
	var total := 40.0 * 0.2
	_run(1.0)
	check_near(_total(), total * 0.25, 0.05, "a quarter after 1 s")
	_run(2.9)
	check(mastery.stacks_on(enemy) == 1, "still poisoned just before the end")
	_run(0.2)
	check_near(_total(), total, 0.05, "the whole stack damage in the end")
	check_eq(mastery.stacks_on(enemy), 0, "poison gone")
	check_eq(mastery.poisoned_count(), 0, "tracker cleaned")
	var n := enemy.fake_hits()
	_run(1.0)
	check_eq(enemy.fake_hits(), n, "no more ticks")
	for a in enemy.fake_attacker_log:
		check_eq(a, rogue, "ticks credited to the rogue")


func test_poison_stacks_and_refreshes() -> void:
	for i in 3:
		mastery.on_hit(enemy, 20.0, true)
	check_eq(mastery.stacks_on(enemy), 3, "three stacks")
	check_near(mastery.dps_on(enemy), 3.0 * 1.0, 0.001, "dps adds up")
	for i in 5:
		mastery.on_hit(enemy, 20.0, true)
	check_eq(mastery.stacks_on(enemy), 5, "capped at 5 stacks")
	check_near(mastery.dps_on(enemy), 5.0 * 1.0, 0.001, "equal stacks keep the sum")
	mastery.on_hit(enemy, 60.0, true)
	check_eq(mastery.stacks_on(enemy), 5, "still 5")
	check_near(mastery.dps_on(enemy), 4.0 + 3.0, 0.001, "a stronger crit replaces an average stack")
	_run(3.5)
	mastery.on_hit(enemy, 20.0, true)
	_run(3.0)
	check(mastery.stacks_on(enemy) == 5, "the duration was refreshed")
	_run(1.1)
	check_eq(mastery.stacks_on(enemy), 0, "and runs out 4 s after the last crit")


func test_poison_ticks_use_the_outgoing_damage_multipliers() -> void:
	mastery.on_hit(enemy, 40.0, true)
	rogue.damage_mults[&"test"] = 2.0
	_run(0.6)
	check_near(enemy.fake_damage_log[0], 40.0 * 0.2 / 4.0 * 0.5 * 2.0, 0.01, "tick = dps x 0.5 s x multipliers")


func test_dead_enemies_drop_out() -> void:
	mastery.on_hit(enemy, 40.0, true)
	enemy.fake_dead = true
	_run(0.6)
	check_eq(mastery.poisoned_count(), 0, "dead enemies are forgotten")
	check_eq(enemy.fake_hits(), 0, "and not hit again")


func test_poison_clears_at_wave_start_and_teardown() -> void:
	mastery.on_hit(enemy, 40.0, true)
	rogue.begin_wave()
	check_eq(mastery.poisoned_count(), 0, "cleared at wave start")
	mastery.on_hit(enemy, 40.0, true)
	rogue.abilities.teardown()
	check_eq(mastery.poisoned_count(), 0, "cleared at teardown")


func test_knife_crits_poison_through_the_runner() -> void:
	rogue.stats.set_source(&"test", {Stats.CRIT: 500.0})
	rogue.abilities.try_cast(0)
	for i in 40:
		for node in tree.get_nodes_in_group(&"projectiles"):
			(node as Projectile).advance(DT)
	# The enemy straight ahead (-Z) is hit by the knife thrown along the facing.
	check_eq(mastery.stacks_on(enemy), 1, "one knife, one stack")


func _mortal(pos: Vector3) -> MortalEnemy:
	var e := MortalEnemy.new()
	e.add_to_group(&"enemies")
	world.add_child(e)
	e.global_position = pos
	EnemyGrid.mark_dirty()
	return e


func test_killing_crit_poisons_the_nearest_neighbour() -> void:
	enemy.global_position = Vector3(2.0, 0, -2.0)  # 2 m from the victim
	var farther := Fakes.spawn_enemy(world, Vector3(-2.3, 0, -2.0))
	var victim := _mortal(Vector3(0, 0, -2.0))
	WeaponRunner.apply_hit(rogue, victim, 25.0, true, Vector3.ZERO)
	check(victim.is_dead(), "the crit killed it")
	check_eq(mastery.stacks_on(victim), 0, "a corpse is not poisoned")
	check_eq(mastery.stacks_on(enemy), 1, "the poison spreads to the nearest living enemy")
	check_eq(mastery.stacks_on(farther), 0, "only one")
	check_near(mastery.dps_on(enemy), mastery.stack_damage(25.0) / RogueMastery.DURATION, 0.001,
			"with the share of the killing crit")
	_run(4.1)
	check_near(_total(), mastery.stack_damage(25.0), 0.05, "and ticks it out")


func test_killing_crit_spread_reach() -> void:
	enemy.global_position = Vector3(2.6, 0, -2.0)  # 2.6 m from the victim
	var victim := _mortal(Vector3(0, 0, -2.0))
	mastery.on_hit(victim, 25.0, true)
	check_eq(mastery.stacks_on(victim), 1, "a living target is poisoned itself")
	victim.hp = 0.0
	mastery.on_hit(victim, 25.0, true)
	check_eq(mastery.poisoned_count(), 1, "nobody within 2.5 m: the share is lost")
	check_eq(mastery.stacks_on(enemy), 0, "2.6 m is too far")
	enemy.global_position = Vector3(2.4, 0, -2.0)
	EnemyGrid.mark_dirty()
	mastery.on_hit(victim, 25.0, true)
	check_eq(mastery.stacks_on(enemy), 1, "2.4 m is close enough")
	enemy.fake_dead = true
	var other := Fakes.spawn_enemy(world, Vector3(0, 0, 0.0))
	EnemyGrid.mark_dirty()
	mastery.on_hit(victim, 25.0, true)
	check_eq(mastery.stacks_on(other), 1, "dead neighbours are skipped")
	var count := mastery.poisoned_count()
	mastery.on_hit(null, 25.0, true)
	mastery.on_hit(rogue, 25.0, true)
	check_eq(mastery.poisoned_count(), count, "no target or a non-enemy target: nothing")


func test_poison_keeps_ticking_while_the_rogue_is_downed() -> void:
	rogue.stats.set_source(&"test", {Stats.CRIT: -500.0, Stats.DODGE: -500.0})
	mastery.on_hit(enemy, 40.0, true)
	_run(1.0)
	var before := _total()
	rogue.invulnerable_left = 0.0
	rogue.take_damage(9999.0)
	check(rogue.downed, "downed")
	_run(3.1)
	check(_total() > before + 0.1, "the poison kept ticking")
	check_near(_total(), 40.0 * 0.2, 0.05, "the whole stack damage")
	for a in enemy.fake_attacker_log:
		check_eq(a, rogue, "credited to the downed rogue")
	check_eq(mastery.poisoned_count(), 0, "and ran out")
