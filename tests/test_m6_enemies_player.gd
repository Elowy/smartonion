extends TestCase
## M6a ENEMIES with real heroes: Player.take_hook / pull_toward (the Flesh Golem's hook: one
## Dodge roll, then a drag), and the smoke bots' new behaviours (they sidestep a telegraphed hook
## line, chase a Cultist Acolyte and shoot it before the nearest enemy).

const EFakes := preload("res://tests/enemies_fakes.gd")
const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

var arena: Arena
var _index := 0


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 4242)
	arena = Arena.create()
	tree.root.add_child(arena)
	_index = 0


func after_each() -> void:
	if is_instance_valid(arena):
		tree.root.remove_child(arena)
		arena.free()
	arena = null
	Enemy.invalidate_player_cache()


func _hero(class_id: StringName, pos: Vector3, bot_seed: int = -1) -> Player:
	var input: PlayerInput = BotInput.new("bot:m6e%d" % _index, bot_seed) if bot_seed >= 0 \
			else ScriptedInput.new("m6e:%d" % _index)
	var slot := PlayerSlot.new(_index, input, PlayerManager.PLAYER_COLORS[_index])
	slot.class_data = Db.get_class_data(class_id)
	_index += 1
	var p := Player.create(slot)
	p.stats.remove_source(&"base")
	arena.entities.add_child(p)
	p.global_position = pos
	return p


func _step(node: Node, seconds: float) -> void:
	Fakes.step(node, seconds)


## A seed whose first draw rolls a Dodge (dodged = true) or does not at [param dodge_pct].
func _dodge_seed(dodge_pct: float, dodged: bool) -> int:
	for s in 200:
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		if (probe.randf() * 100.0 < dodge_pct) == dodged:
			return s
	return 0


# --- Player.take_hook / pull_toward -----------------------------------------------------------------

func test_a_landed_hook_hurts_like_a_projectile_and_drags_the_hero_in() -> void:
	var p := _hero(&"warrior", Vector3.ZERO)
	var twin := _hero(&"warrior", Vector3(0.0, 0.0, 12.0))
	RunState.rng.seed = 3
	var landed := p.take_hook(4.0, Vector3(10.0, 0.0, 0.0), 3.0)
	RunState.rng.seed = 3
	twin.take_damage(4.0, CombatMath.KIND_PROJECTILE)
	check(landed, "the hook landed")
	check_near(p.hp, twin.hp, 0.0001, "the same damage as a KIND_PROJECTILE hit")
	check(p.hp < p.max_hp(), "it hurt")
	check(p.is_pulled(), "and a pull is running")
	_step(p, Player.PULL_TIME / 2.0)
	check(p.global_position.x > 1.0 and p.global_position.x < 2.0, "half way after half the time: %f" % p.global_position.x)
	_step(p, Player.PULL_TIME)
	check_near(p.global_position.x, 3.0, 0.02, "3 m towards the golem")
	check_near(p.global_position.z, 0.0, 0.001, "in a straight line")
	check(not p.is_pulled(), "the pull is over")
	_step(p, 0.5)
	check_near(p.global_position.x, 3.0, 0.02, "and it does not go on")


func test_a_dodge_avoids_the_whole_hook_with_one_roll() -> void:
	var p := _hero(&"warrior", Vector3.ZERO)
	var twin := _hero(&"warrior", Vector3(0.0, 0.0, 12.0))
	p.stats.set_source(&"test", {Stats.DODGE: 60.0})
	twin.stats.set_source(&"test", {Stats.DODGE: 60.0})
	var seed_value := _dodge_seed(60.0, true)
	RunState.rng.seed = seed_value
	var landed := p.take_hook(4.0, Vector3(10.0, 0.0, 0.0), 3.0)
	var state_hook := RunState.rng.state
	RunState.rng.seed = seed_value
	twin.take_damage(4.0, CombatMath.KIND_PROJECTILE)
	check(not landed, "dodged")
	check_eq(p.hp, p.max_hp(), "no damage")
	check(not p.is_pulled(), "no pull")
	_step(p, 0.5)
	check_near(p.global_position.x, 0.0, 0.001, "it did not move")
	check_eq(RunState.rng.state, state_hook, "the hook drew exactly what an attack draws: one roll")
	# ... and the same Dodge stat lets one through when the roll misses.
	var q := _hero(&"warrior", Vector3(0.0, 0.0, -10.0))
	q.stats.set_source(&"test", {Stats.DODGE: 60.0})
	RunState.rng.seed = _dodge_seed(60.0, false)
	check(q.take_hook(4.0, Vector3(10.0, 0.0, -10.0), 3.0), "a failed Dodge roll: hooked")
	check(q.is_pulled(), "pulled")


func test_an_invulnerable_or_downed_hero_cannot_be_hooked() -> void:
	var p := _hero(&"warrior", Vector3.ZERO)
	p.invulnerable_left = 1.0
	check(not p.take_hook(4.0, Vector3(10.0, 0.0, 0.0), 3.0), "Divine Shield, a Charge, i-frames: immune")
	check_eq(p.hp, p.max_hp(), "no damage")
	check(not p.is_pulled(), "no pull")
	p.invulnerable_left = 0.0
	p.downed = true
	check(not p.take_hook(4.0, Vector3(10.0, 0.0, 0.0), 3.0), "ghosts are not hooked")
	p.downed = false
	check(not p.take_hook(0.0, Vector3(10.0, 0.0, 0.0), 3.0), "no damage, no hook")


func test_a_hook_that_brings_the_hero_down_does_not_drag_the_ghost() -> void:
	var p := _hero(&"warrior", Vector3.ZERO)
	check(p.take_hook(10000.0, Vector3(10.0, 0.0, 0.0), 3.0), "it landed")
	check(p.downed, "the hero went down")
	check(not p.is_pulled(), "a ghost is not pulled")
	_step(p, 0.5)
	check_near(p.global_position.x, 0.0, 0.001, "it stayed")


func test_pull_toward_covers_at_most_the_gap_and_a_new_pull_replaces_the_old() -> void:
	var p := _hero(&"mage", Vector3(2.0, 0.0, 2.0))
	check_eq(p.pull_toward(Vector3(2.0, 0.0, 3.0), 3.0), 1.0, "only the 1 m to the point")
	_step(p, 0.5)
	check_near(p.global_position.z, 3.0, 0.001, "ends exactly on it")
	check_eq(p.pull_toward(p.global_position, 3.0), 0.0, "already there")
	check_eq(p.pull_toward(Vector3(9.0, 0.0, 3.0), 0.0), 0.0, "no distance, no pull")
	check_eq(p.pull_toward(Vector3(9.0, 0.0, 3.0), 2.0, 0.0), 0.0, "no time, no pull")
	p.pull_toward(Vector3(9.0, 0.0, 3.0), 2.0)
	p.pull_toward(Vector3(2.0, 0.0, 10.0), 1.0)
	_step(p, 0.5)
	check_near(p.global_position.x, 2.0, 0.001, "the second pull replaced the first (x)")
	check_near(p.global_position.z, 4.0, 0.001, "1 m towards the new point")
	p.pull_toward(Vector3(9.0, 0.0, 4.0), 2.0)
	p.downed = true
	_step(p, 0.5)
	check_near(p.global_position.x, 2.0, 0.001, "going down ends the pull")


func test_a_pull_is_stopped_by_the_arena_wall() -> void:
	var half := Arena.SIZE.x * 0.5
	var p := _hero(&"warrior", Vector3(half - 1.0, 0.0, 0.0))
	# A (mis-aimed) point outside the wall: the hero never leaves the arena.
	p.pull_toward(Vector3(half + 6.0, 0.0, 0.0), 3.0)
	_step(p, 0.5)
	check(p.global_position.x <= half - Player.RADIUS + 0.001, "held by the wall: %f" % p.global_position.x)


# --- Bots ----------------------------------------------------------------------------------------

func _golem_in_hook_state(pos: Vector3) -> Enemy:
	var g := Enemy.create(Db.get_enemy(&"flesh_golem"), 12)
	arena.entities.add_child(g)
	g.global_position = pos
	g.attack_cooldown_left = 0.0
	return g


func test_a_bot_in_a_telegraphed_hook_line_sidesteps_it() -> void:
	var seed_dodging := 0
	for s in 200:
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		if probe.randf() < BotInput.HOOK_DODGE_CHANCE:
			seed_dodging = s
			break
	var bot_hero := _hero(&"mage", Vector3(6.0, 0.0, 0.1), seed_dodging)
	var g := _golem_in_hook_state(Vector3.ZERO)
	Fakes.step(g, DT)
	check_eq(g.ai_state, Enemy.AiState.HOOK, "the golem aims at the bot")
	var bot := bot_hero.slot.input as BotInput
	bot.think(DT)
	var move := bot.get_move()
	check(absf(move.y) > 0.99 and absf(move.x) < 0.1, "straight out of the line (sideways): %s" % move)
	check(move.y > 0.0, "to the side it was already on (z +0.1)")
	bot.think(DT)
	check(absf(bot.get_move().y) > 0.99, "the decision holds for the whole hook")


func test_a_bot_that_does_not_dodge_this_hook_is_left_in_the_line() -> void:
	var seed_slow := 0
	for s in 200:
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		if probe.randf() >= BotInput.HOOK_DODGE_CHANCE:
			seed_slow = s
			break
	var bot_hero := _hero(&"mage", Vector3(6.0, 0.0, 0.1), seed_slow)
	var g := _golem_in_hook_state(Vector3.ZERO)
	Fakes.step(g, DT)
	var bot := bot_hero.slot.input as BotInput
	bot.think(DT)
	var move := bot.get_move()
	check(not (absf(move.y) > 0.99 and absf(move.x) < 0.1), "no escape move: %s" % move)


func test_a_bot_outside_the_line_or_without_a_hook_does_not_sidestep() -> void:
	var seed_dodging := 0
	for s in 200:
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		if probe.randf() < BotInput.HOOK_DODGE_CHANCE:
			seed_dodging = s
			break
	var bot_hero := _hero(&"mage", Vector3(6.0, 0.0, 4.0), seed_dodging)
	var g := _golem_in_hook_state(Vector3.ZERO)
	Fakes.step(g, DT)
	check_eq(g.ai_state, Enemy.AiState.HOOK, "it hooks the bot")
	var bot := bot_hero.slot.input as BotInput
	bot.think(DT)
	var move := bot.get_move()
	check(not (absf(move.y) > 0.99 and absf(move.x) < 0.1), "4 m off the line: no panic move: %s" % move)


func test_bots_chase_an_acolyte_a_plain_enemy_would_not_pull_them_in() -> void:
	var warrior := _hero(&"warrior", Vector3.ZERO, 5)
	var data := Db.get_enemy(&"cultist_acolyte").duplicate() as EnemyData
	var a := Enemy.create(data, 9)
	arena.entities.add_child(a)
	# 13 m: beyond the 12 m a melee bot looks for a fight, inside the 14 m of a priority target.
	a.global_position = Vector3(13.0, 0.0, 0.0)
	a.attack_cooldown_left = 99.0
	var bot := warrior.slot.input as BotInput
	bot.think(DT)
	var with_priority := bot.get_move()
	data.priority_target = false
	bot.think(DT)  # same wander as before (the timer has not expired)
	var without := bot.get_move()
	check(with_priority.x > without.x + 0.2, "chases the Acolyte: %s vs %s" % [with_priority, without])
	check(with_priority.x > 0.5, "towards it")
	a.global_position = Vector3(15.0, 0.0, 0.0)
	data.priority_target = true
	bot.think(DT)
	var too_far := bot.get_move()
	check(too_far.x < with_priority.x, "beyond 14 m it is not worth the walk: %s" % too_far)


func test_a_crowded_or_hurt_bot_does_not_chase_the_acolyte() -> void:
	var warrior := _hero(&"warrior", Vector3.ZERO, 5)
	var data := Db.get_enemy(&"cultist_acolyte").duplicate() as EnemyData
	var a := Enemy.create(data, 9)
	arena.entities.add_child(a)
	a.global_position = Vector3(13.0, 0.0, 0.0)  # beyond a plain enemy's 12 m engage distance
	a.attack_cooldown_left = 99.0
	var bot := warrior.slot.input as BotInput
	# Healthy and alone it goes for the Acolyte ...
	bot.think(DT)
	var healthy := bot.get_move()
	data.priority_target = false
	bot.think(DT)
	check(healthy.x > bot.get_move().x + 0.1, "the control: a healthy bot chases it (%s vs %s)" % [healthy, bot.get_move()])
	data.priority_target = true
	# ... hurt it kites like for any enemy: the priority changes nothing.
	warrior.hp = warrior.max_hp() * 0.2
	bot.think(DT)
	var hurt_with := bot.get_move()
	data.priority_target = false
	bot.think(DT)
	check(hurt_with.is_equal_approx(bot.get_move()), "a hurt bot ignores the priority: %s vs %s" % [hurt_with, bot.get_move()])
	data.priority_target = true
	warrior.hp = warrior.max_hp()
	for i in BotInput.CROWD_COUNT:
		var e := Node3D.new()
		e.add_to_group(&"enemies")
		arena.entities.add_child(e)
		e.global_position = Vector3(-1.5 - float(i) * 0.2, 0.0, 0.0)
	bot.think(DT)
	var crowded_with := bot.get_move()
	data.priority_target = false
	bot.think(DT)
	check(crowded_with.is_equal_approx(bot.get_move()), "nor does one in a crowd: %s vs %s" % [crowded_with, bot.get_move()])


func test_a_bots_weapon_shoots_the_acolyte_before_the_nearest_enemy() -> void:
	var bot_hero := _hero(&"mage", Vector3.ZERO, 5)
	var human := _hero(&"mage", Vector3(0.0, 0.0, 10.0))
	var skeleton := Enemy.create(Db.get_enemy(&"skeleton_grunt"), 1)
	arena.entities.add_child(skeleton)
	skeleton.global_position = Vector3(2.0, 0.0, 0.0)
	var a := Enemy.create(Db.get_enemy(&"cultist_acolyte"), 9)
	arena.entities.add_child(a)
	a.global_position = Vector3(5.5, 0.0, 0.0)
	var runner := bot_hero.runner_for(bot_hero.main_hand)
	check(runner != null and runner.weapon.attack_range >= 5.5, "the wand reaches the Acolyte")
	check(runner.find_target() == a, "a bot aims at the Acolyte in reach")
	var human_runner := human.runner_for(human.main_hand)
	human.global_position = Vector3.ZERO
	check(human_runner.find_target() == skeleton, "a human hero's weapon still takes the nearest")
	human.global_position = Vector3(0.0, 0.0, 10.0)
	a.global_position = Vector3(20.0, 0.0, 0.0)
	check(runner.find_target() == skeleton, "an Acolyte out of reach changes nothing")
	a.global_position = Vector3(5.5, 0.0, 0.0)
	a.take_damage(1000.0)
	check(runner.find_target() == skeleton, "a dead one is no target")
