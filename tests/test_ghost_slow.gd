extends TestCase
## Ghost slow (GDD 16.1 "Szellem-lassítás", M5 integration): while a hero is downed, the enemies
## whose centre is inside the ghost's revive circle (Player.REVIVE_RADIUS around it) walk
## Player.GHOST_SLOW_PCT (33%) slower – refreshed every tick (Enemy.apply_ghost_slow), so it
## ends a moment after the enemy leaves, the ghost moves away or revives; several ghosts never
## stack it; it sits beside the other slows (the strongest wins, none is replaced); the Loot
## Goblin is slowed too (crowd control works on it), an enraged elite is not; it draws nothing
## from RunState.rng; the revive ring shows a cue while it slows something.

const PFakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0
## The walking factor inside a ghost circle.
const SLOWED := 1.0 - Player.GHOST_SLOW_PCT / 100.0

var world: Node3D


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(2, 515)
	RunState.set_wave(6)
	world = EFakes.make_world(tree)


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null
	PlayerManager.clear()
	EnemyGrid.mark_dirty()


# --- Helpers -----------------------------------------------------------------------------------

## A real hero (slot [param index]) at [param pos], downed (a ghost).
func _ghost(index: int, pos: Vector3) -> Player:
	var p := PFakes.spawn_player(world, index, &"mage", pos)
	p.take_damage(99999.0)
	check(p.downed, "P%d is a ghost" % (index + 1))
	return p


func _enemy(pos: Vector3, data: EnemyData = null) -> Enemy:
	return EFakes.spawn_enemy(world, data if data != null else EFakes.enemy_data(), pos)


## One physics tick: the ghosts (the heroes come first in the arena), then the enemies. The
## grid is rebuilt every tick like it is per physics frame in the game (here every tick runs in
## the same engine frame).
func _tick(ghosts: Array[Player], enemies: Array[Enemy], ticks: int = 1) -> void:
	for i in ticks:
		EnemyGrid.mark_dirty()
		for g in ghosts:
			if is_instance_valid(g):
				g._physics_process(DT)
		for e in enemies:
			if is_instance_valid(e) and not e.is_dead():
				e._physics_process(DT)


## Ticks covering GHOST_SLOW_LINGER (and one more).
static func _linger_ticks() -> int:
	return ceili(Player.GHOST_SLOW_LINGER / DT) + 1


# --- Inside / outside --------------------------------------------------------------------------

func test_enemies_inside_the_circle_are_slowed_and_the_ones_outside_are_not() -> void:
	var ghost := _ghost(0, Vector3.ZERO)
	var r := Player.REVIVE_RADIUS
	var inside := _enemy(Vector3(1.0, 0.0, 0.0))
	var at_edge := _enemy(Vector3(0.0, 0.0, r - 0.02))
	var just_out := _enemy(Vector3(0.0, 0.0, -(r + 0.05)))
	var far := _enemy(Vector3(6.0, 0.0, 6.0))
	_tick([ghost] as Array[Player], [] as Array[Enemy])
	check(inside.is_slowed() and at_edge.is_slowed(), "the enemies inside the circle are slowed")
	check_eq(inside.current_slow_pct(), Player.GHOST_SLOW_PCT, "by 33%")
	check_near(inside.ghost_slow_left, Player.GHOST_SLOW_LINGER, 0.0001, "for a short, refreshed time")
	check(not just_out.is_slowed() and not far.is_slowed(), "the ones outside are not")
	check_eq(just_out.current_slow_pct(), 0.0, "no slow outside")
	check_eq(ghost.ghost_slowed, 2, "the ghost counts what it slowed")
	check(ghost.model.ghost_slowing, "the revive ring shows the cue")


func test_a_living_hero_slows_nothing() -> void:
	var hero := PFakes.spawn_player(world, 0, &"mage", Vector3.ZERO)
	var e := _enemy(Vector3(0.8, 0.0, 0.0))
	_tick([hero] as Array[Player], [] as Array[Enemy], 3)
	check(not e.is_slowed(), "no ghost, no slow")
	check_eq(hero.ghost_slowed, 0, "nothing counted")
	check(not hero.model.ghost_slowing, "no cue")


func test_dead_enemies_are_skipped() -> void:
	var ghost := _ghost(0, Vector3.ZERO)
	var e := _enemy(Vector3(0.5, 0.0, 0.0))
	e.take_damage(e.max_hp * 10.0)
	check(e.is_dead(), "dead")
	_tick([ghost] as Array[Player], [] as Array[Enemy])
	check_eq(e.ghost_slow_left, 0.0, "a corpse is not slowed")
	check_eq(ghost.ghost_slowed, 0, "nor counted")


# --- Movement ----------------------------------------------------------------------------------

func test_slowed_enemies_walk_33_percent_slower() -> void:
	EFakes.spawn_player(world, Vector3(12.0, 0.0, 0.0))  # the living target both chase
	var ghost := _ghost(1, Vector3.ZERO)
	var slowed := _enemy(Vector3(-1.7, 0.0, 0.0))  # walks through the middle of the circle
	var free := _enemy(Vector3(-1.7, 0.0, 6.0))
	var enemies: Array[Enemy] = [slowed, free]
	_tick([ghost] as Array[Player], enemies, 12)  # steering reaches full speed
	var a0 := slowed.global_position
	var b0 := free.global_position
	_tick([ghost] as Array[Player], enemies, 30)
	check(EFakes.flat_distance(slowed.global_position, ghost.global_position) < Player.REVIVE_RADIUS,
		"still inside the circle")
	check_near(slowed.velocity.length(), slowed.walk_speed() * SLOWED, 0.05, "walks at 67% of its speed")
	check_near(free.velocity.length(), free.walk_speed(), 0.05, "the other one at full speed")
	var ratio := EFakes.flat_distance(slowed.global_position, a0) / slowed.walk_speed() \
		/ (EFakes.flat_distance(free.global_position, b0) / free.walk_speed())
	check_near(ratio, SLOWED, 0.03, "a third less ground covered")


func test_an_enemy_walking_out_of_the_circle_speeds_up_again() -> void:
	EFakes.spawn_player(world, Vector3(12.0, 0.0, 0.0))
	var ghost := _ghost(1, Vector3.ZERO)
	var e := _enemy(Vector3(1.2, 0.0, 0.0))
	var enemies: Array[Enemy] = [e]
	_tick([ghost] as Array[Player], enemies, 6)
	check(e.is_slowed(), "slowed while inside")
	var guard := 0
	while EFakes.flat_distance(e.global_position, Vector3.ZERO) <= Player.REVIVE_RADIUS and guard < 300:
		_tick([ghost] as Array[Player], enemies)
		guard += 1
	_tick([ghost] as Array[Player], enemies, _linger_ticks())
	check(not e.is_slowed(), "the slow ran out after it left the circle")
	check_eq(ghost.ghost_slowed, 0, "the ghost slows nothing now")
	check(not ghost.model.ghost_slowing, "and the cue is off")
	check_near(e.velocity.length(), e.walk_speed(), 0.05, "full speed outside")


func test_the_slow_follows_a_moving_ghost() -> void:
	var ghost := _ghost(0, Vector3.ZERO)
	var e := _enemy(Vector3(1.0, 0.0, 0.0))
	_tick([ghost] as Array[Player], [e] as Array[Enemy])
	check(e.is_slowed(), "slowed")
	ghost.global_position = Vector3(-8.0, 0.0, 0.0)  # the ghost walks off (to the Spirit Healer)
	_tick([ghost] as Array[Player], [e] as Array[Enemy], _linger_ticks())
	check(not e.is_slowed(), "the circle went with the ghost")


# --- Revive ------------------------------------------------------------------------------------

func test_the_slow_ends_when_the_ghost_revives() -> void:
	var ghost := _ghost(0, Vector3.ZERO)
	var e := _enemy(Vector3(-1.0, 0.0, 0.5))
	var enemies: Array[Enemy] = [e]
	_tick([ghost] as Array[Player], enemies, 3)
	check(e.is_slowed() and ghost.model.ghost_slowing, "slowed, cue on")
	ghost.revive()
	check_eq(ghost.ghost_slowed, 0, "a living hero counts nothing")
	check(not ghost.model.ghost_slowing, "the cue goes with the ghost")
	_tick([ghost] as Array[Player], enemies, _linger_ticks())
	check(not e.is_slowed(), "the slow ended right after the revive")
	check_eq(e.ghost_slow_left, 0.0, "nothing left")


func test_a_teammate_revive_through_the_channel_ends_it() -> void:
	var ghost := _ghost(0, Vector3.ZERO)
	var reviver := PFakes.spawn_player(world, 1, &"warrior", Vector3(0.6, 0.0, 0.0))
	var e := _enemy(Vector3(-1.2, 0.0, 0.0))
	var heroes: Array[Player] = [ghost, reviver]
	var enemies: Array[Enemy] = [e]
	e.stun_left = 99.0  # it stays where it is (the reviver is its nearest target)
	_tick(heroes, enemies, 6)
	check(e.is_slowed(), "slowed while the teammate channels")
	var guard := 0
	while ghost.downed and guard < 600:
		_tick(heroes, enemies)
		guard += 1
	check(not ghost.downed, "revived by the teammate")
	_tick(heroes, enemies, _linger_ticks())
	check(not e.is_slowed(), "no ghost, no slow")


# --- Several ghosts, other slows ---------------------------------------------------------------

func test_several_ghosts_slow_their_own_circles_and_never_stack() -> void:
	var a := _ghost(0, Vector3(-1.0, 0.0, 0.0))
	var b := _ghost(1, Vector3(1.0, 0.0, 0.0))
	var c := _ghost(2, Vector3(10.0, 0.0, 0.0))
	var both := _enemy(Vector3(0.0, 0.0, 0.3))
	var only_a := _enemy(Vector3(-2.5, 0.0, 0.0))
	var only_c := _enemy(Vector3(10.0, 0.0, 1.0))
	var ghosts: Array[Player] = [a, b, c]
	var enemies: Array[Enemy] = [both, only_a, only_c]
	for e in enemies:
		e.stun_left = 99.0
	_tick(ghosts, enemies, 2)
	check(both.is_slowed() and only_a.is_slowed() and only_c.is_slowed(), "every ghost slows its own circle")
	check_eq(both.current_slow_pct(), Player.GHOST_SLOW_PCT, "two circles: still 33%, not stacked")
	check_eq([a.ghost_slowed, b.ghost_slowed, c.ghost_slowed], [2, 1, 1], "each ghost counts its circle")
	b.revive()
	_tick(ghosts, enemies, _linger_ticks())
	check(both.is_slowed(), "the other ghost still slows the shared enemy")
	a.revive()
	_tick(ghosts, enemies, _linger_ticks())
	check(not both.is_slowed() and not only_a.is_slowed(), "both ghosts up: the slow is gone")
	check(only_c.is_slowed(), "the third ghost keeps its own")


func test_the_strongest_slow_wins_and_no_slow_is_replaced() -> void:
	var ghost := _ghost(0, Vector3.ZERO)
	var frost := _enemy(Vector3(1.0, 0.0, 0.0))
	var light := _enemy(Vector3(-1.0, 0.0, 0.0))
	var enemies: Array[Enemy] = [frost, light]
	for e in enemies:
		e.stun_left = 99.0
	frost.apply_slow(60.0, 5.0)
	light.apply_slow(20.0, 5.0)
	_tick([ghost] as Array[Player], enemies)
	check_eq(frost.current_slow_pct(), 60.0, "a stronger slow wins")
	check_eq(light.current_slow_pct(), Player.GHOST_SLOW_PCT, "the ghost slow beats a weaker one")
	check_eq(light.slow_pct, 20.0, "without replacing it")
	ghost.revive()
	_tick([ghost] as Array[Player], enemies, _linger_ticks())
	check_eq(light.current_slow_pct(), 20.0, "the weaker slow is still there afterwards")
	check(light.is_slowed() and frost.is_slowed(), "both keep their own slows")


# --- Goblin, elites ----------------------------------------------------------------------------

func test_the_loot_goblin_is_slowed_too() -> void:
	EFakes.spawn_player(world, Vector3(-6.0, 0.0, 0.0))  # it flees from this hero (+x)
	var ghost := _ghost(1, Vector3.ZERO)
	var g := LootGoblin.create(LootGoblin.goblin_data(), 6)
	EFakes.arena_of(world).entities.add_child(g)
	g.global_position = Vector3(-1.2, 0.0, 0.0)
	_tick([ghost] as Array[Player], [g] as Array[Enemy], 10)
	check(g.is_slowed(), "crowd control works on the goblin: slowed")
	check_eq(g.current_slow_pct(), Player.GHOST_SLOW_PCT, "by 33%")
	check(g._move_velocity.length() > 0.5, "it is running")
	check_near(g.velocity.length(), g._move_velocity.length() * SLOWED, 0.05, "a third slower than it wants to run")


func test_an_enraged_elite_ignores_the_ghost_slow() -> void:
	var ghost := _ghost(0, Vector3.ZERO)
	var e := Enemy.create(EFakes.enemy_data(), 6)
	e.make_elite(EliteAffixes.ENRAGED)
	EFakes.arena_of(world).entities.add_child(e)
	e.global_position = Vector3(0.5, 0.0, 0.5)
	_tick([ghost] as Array[Player], [] as Array[Enemy])
	check(e.is_slowed(), "slowed before it rages")
	e.take_damage(e.max_hp * 0.6)
	check(e.is_enraged(), "enraged at half HP")
	check(not e.is_slowed(), "the rage ends the ghost slow")
	_tick([ghost] as Array[Player], [] as Array[Enemy])
	check(not e.is_slowed(), "and it no longer lands")
	check_eq(ghost.ghost_slowed, 0, "not counted")


# --- Determinism ---------------------------------------------------------------------------------

func test_the_ghost_slow_draws_nothing_and_is_deterministic() -> void:
	var ghost := _ghost(0, Vector3.ZERO)
	var enemies: Array[Enemy] = []
	for i in 6:
		enemies.append(_enemy(Vector3(-1.5 + 0.6 * i, 0.0, 0.4 * (i % 2))))
	var state := RunState.rng.state
	_tick([ghost] as Array[Player], [] as Array[Enemy], 30)
	check_eq(RunState.rng.state, state, "no RunState.rng draws")
	check_eq(ghost.ghost_slowed, 6, "all six inside")
	var first := _walk_through(4321)
	var second := _walk_through(4321)
	check_eq(first, second, "the same run twice gives the same positions")


## A fresh world: a ghost, a hero and a few enemies chasing it through the circle for 1 s with
## [param seed_value]; returns the enemies' final positions.
func _walk_through(seed_value: int) -> Array[Vector3]:
	EFakes.free_world(tree, world)
	RunState.start_run(2, seed_value)
	world = EFakes.make_world(tree)
	EFakes.spawn_player(world, Vector3(9.0, 0.0, 0.0))
	var ghost := _ghost(1, Vector3.ZERO)
	var enemies: Array[Enemy] = []
	for i in 4:
		enemies.append(_enemy(Vector3(-2.0, 0.0, -1.2 + 0.8 * i)))
	_tick([ghost] as Array[Player], enemies, 60)
	var out: Array[Vector3] = []
	for e in enemies:
		out.append(e.global_position)
	return out
