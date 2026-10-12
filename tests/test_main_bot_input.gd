extends TestCase
## BotInput (the smoke / demo bots Main spawns): kiting by weapon reach, retreat when hurt,
## rescue runs to downed teammates close by, ghosts walking to the Spirit Healer (or to a
## living teammate without one), wall avoidance, Loot Goblin chases (M5).

const DT := 1.0 / 60.0

var arena: Arena
var _index := 0


func before_each() -> void:
	PlayerManager.clear()
	arena = Arena.create()
	tree.root.add_child(arena)
	_index = 0


func after_each() -> void:
	if is_instance_valid(arena):
		tree.root.remove_child(arena)
		arena.free()
	arena = null
	Enemy.invalidate_player_cache()


func _bot_player(class_id: StringName, pos: Vector3) -> Player:
	var slot := PlayerSlot.new(_index, BotInput.new("bot:test%d" % _index, 3 + _index), PlayerManager.PLAYER_COLORS[_index])
	slot.class_data = Db.get_class_data(class_id)
	_index += 1
	var p := Player.create(slot)
	arena.entities.add_child(p)
	p.global_position = pos
	return p


func _enemy(pos: Vector3) -> Node3D:
	var e := Node3D.new()
	e.add_to_group(&"enemies")
	arena.entities.add_child(e)
	e.global_position = pos
	return e


func _goblin(pos: Vector3) -> LootGoblin:
	var g := LootGoblin.create(LootGoblin.goblin_data(), 3)
	arena.entities.add_child(g)
	g.global_position = pos
	return g


## The bot's move with [param node] in the enemies group and without it (same wander: the
## first call draws it, the second reuses it).
func _move_with_and_without(p: Player, node: Node3D) -> Array[Vector2]:
	var with_it := _move(p)
	node.remove_from_group(&"enemies")
	var without := _move(p)
	node.add_to_group(&"enemies")
	return [with_it, without]


func _move(p: Player) -> Vector2:
	var bot := p.slot.input as BotInput
	bot.think(DT)  # bots decide once per physics tick (PlayerManager._physics_process)
	return bot.get_move()


func test_ranged_bot_keeps_its_distance() -> void:
	var mage := _bot_player(&"mage", Vector3.ZERO)
	_enemy(Vector3(3.0, 0.0, 0.0))
	check(_move(mage).x < -0.5, "a wand user backs away from an enemy 3 m away")


func test_melee_bot_closes_in_but_not_into_contact() -> void:
	var warrior := _bot_player(&"warrior", Vector3.ZERO)
	var e := _enemy(Vector3(6.0, 0.0, 0.0))
	check(_move(warrior).x > 0.5, "a sword user walks towards an enemy 6 m away")
	e.global_position = Vector3(0.8, 0.0, 0.0)
	check(_move(warrior).x < -0.5, "but steps back when it is about to touch")


func test_hurt_melee_bot_retreats() -> void:
	var warrior := _bot_player(&"warrior", Vector3.ZERO)
	warrior.hp = warrior.max_hp() * 0.2
	_enemy(Vector3(4.0, 0.0, 0.0))
	check(_move(warrior).x < -0.5, "low HP: kite instead of fighting")


func test_bot_runs_to_a_downed_teammate_close_by_and_stays() -> void:
	var rescuer := _bot_player(&"rogue", Vector3(0.0, 0.0, -3.0))
	var ghost := _bot_player(&"mage", Vector3(0.0, 0.0, -7.5))
	ghost.downed = true
	check(BotInput.RESCUE_RANGE <= 5.0, "rescue runs only for ghosts close by")
	var m := _move(rescuer)
	check(m.y < -0.9, "heads north to the ghost 4.5 m away: %s" % m)
	rescuer.global_position = Vector3(0.0, 0.0, -6.7)
	check_eq(_move(rescuer), Vector2.ZERO, "stands still inside the revive circle")
	_enemy(Vector3(1.0, 0.0, -6.7))
	check(_move(rescuer) != Vector2.ZERO, "an enemy on top of it makes it step away")


func test_living_bot_leaves_a_far_ghost_to_the_spirit_healer() -> void:
	var fighter := _bot_player(&"mage", Vector3(-6.0, 0.0, 0.0))
	var ghost := _bot_player(&"rogue", Vector3(4.0, 0.0, 0.0))
	ghost.downed = true
	_enemy(Vector3(-6.0, 0.0, -4.0))
	var m := _move(fighter)
	check(m.y > 0.5 and m.x < 0.7, "keeps kiting the enemy instead of running to a ghost 10 m away: %s" % m)
	ghost.remove_from_group(&"players")
	check(_move(fighter).is_equal_approx(m), "exactly as if there were no ghost")
	ghost.add_to_group(&"players")
	ghost.global_position = Vector3(-6.0 + BotInput.RESCUE_RANGE - 0.5, 0.0, 0.0)
	check(_move(fighter).x > 0.9, "but still rescues a ghost within RESCUE_RANGE")


func test_ghost_walks_straight_to_the_spirit_healer() -> void:
	var healer := arena.spirit_healer
	check(healer != null and healer.is_inside_tree(), "the arena has a Spirit Healer")
	var ghost := _bot_player(&"paladin", Vector3(-8.0, 0.0, 6.0))
	ghost.downed = true
	var mate := _bot_player(&"mage", Vector3(-12.0, 0.0, 8.0))
	_enemy(Vector3(-6.0, 0.0, 4.5))  # enemies ignore ghosts: no detour
	var m := _move(ghost)
	var want := Vector2(8.0, -6.0).normalized()
	check(m.dot(want) > 0.99, "straight towards the healer at the centre: %s" % m)
	check_near(m.length(), 1.0, 0.001, "full stick")
	ghost.global_position = Vector3(BotInput.HEALER_STOP_DISTANCE * 0.5, 0.0, 0.0)
	check_eq(_move(ghost), Vector2.ZERO, "waits inside the circle")
	check(BotInput.HEALER_STOP_DISTANCE < SpiritHealer.HEAL_RADIUS, "stops well inside the heal radius")
	ghost.global_position = Vector3(SpiritHealer.HEAL_RADIUS * 0.9, 0.0, 0.0)
	check(_move(ghost).x < -0.9, "walks deeper into the circle from its edge")
	check(mate.is_alive(), "the living teammate is not what it seeks")


func test_sick_ghost_seeks_a_teammate_instead_of_the_healer() -> void:
	var ghost := _bot_player(&"paladin", Vector3(-4.0, 0.0, 0.0))
	ghost.downed = true
	ghost.res_sickness_left = 8.0
	_bot_player(&"mage", Vector3(-10.0, 0.0, 0.0))
	check(_move(ghost).x < -0.9, "Resurrection Sickness: away from the healer, to the teammate")
	ghost.res_sickness_left = 0.0
	check(_move(ghost).x > 0.9, "healthy again: back to the healer")


func test_ghost_without_a_healer_seeks_a_living_teammate() -> void:
	arena.remove_child(arena.spirit_healer)
	arena.spirit_healer.free()
	var ghost := _bot_player(&"paladin", Vector3.ZERO)
	ghost.downed = true
	_bot_player(&"mage", Vector3(6.0, 0.0, 0.0))
	check(_move(ghost).x > 0.9, "the ghost drifts to the living teammate")


func test_bot_keeps_away_from_the_walls() -> void:
	var b := arena.get_bounds()
	var bot := _bot_player(&"mage", Vector3(b.end.x - 0.5, 0.0, 0.0))
	check(_move(bot).x < 0.0, "pushed back from the east wall")
	bot.global_position = Vector3(0.0, 0.0, b.end.y - 0.5)
	check(_move(bot).y < 0.0, "pushed back from the south wall")


func test_a_loot_goblin_is_never_kited() -> void:
	var mage := _bot_player(&"mage", Vector3.ZERO)
	var g := _goblin(Vector3(3.0, 0.0, 0.0))
	_move(mage)  # draws the wander
	var m := _move_with_and_without(mage, g)
	check(m[0].is_equal_approx(m[1]), "a goblin 3 m away is no threat: %s vs %s" % [m[0], m[1]])
	var warrior := _bot_player(&"warrior", Vector3(-8.0, 0.0, 6.0))
	g.global_position = Vector3(-7.4, 0.0, 6.0)
	_move(warrior)
	check(_move(warrior).x > -0.3, "a melee bot does not step back from a goblin at its feet")


func test_bots_chase_a_loot_goblin_nearby() -> void:
	var mage := _bot_player(&"mage", Vector3.ZERO)
	var g := _goblin(Vector3(9.0, 0.0, 0.0))
	_move(mage)
	var m := _move_with_and_without(mage, g)
	check(m[0].x > 0.8, "a ranged bot runs after a goblin 9 m away: %s" % m[0])
	check(not m[0].is_equal_approx(m[1]), "because of the goblin")
	g.global_position = Vector3(5.0, 0.0, 0.0)
	m = _move_with_and_without(mage, g)
	check(m[0].is_equal_approx(m[1]), "close enough to shoot it: no more chasing")
	var warrior := _bot_player(&"warrior", Vector3(-8.0, 0.0, -6.0))
	g.global_position = Vector3(-8.0, 0.0, -6.0 + 4.0)
	_move(warrior)
	m = _move_with_and_without(warrior, g)
	check(m[0].y > 0.8 and not m[0].is_equal_approx(m[1]), "a melee bot closes in on it: %s" % m[0])


func test_bots_leave_the_goblin_when_crowded_hurt_or_far() -> void:
	var mage := _bot_player(&"mage", Vector3.ZERO)
	var g := _goblin(Vector3(9.0, 0.0, 0.0))
	_move(mage)
	var e := _enemy(Vector3(0.0, 0.0, -2.0))
	var m := _move_with_and_without(mage, g)
	check(m[0].is_equal_approx(m[1]), "another enemy within CROWD_RADIUS: fight / kite first")
	e.global_position = Vector3(0.0, 0.0, -BotInput.CROWD_RADIUS - 0.5)
	m = _move_with_and_without(mage, g)
	check(not m[0].is_equal_approx(m[1]), "just outside the crowd radius it chases again")
	e.remove_from_group(&"enemies")
	mage.hp = mage.max_hp() * (BotInput.RETREAT_HP_RATIO - 0.1)
	m = _move_with_and_without(mage, g)
	check(m[0].is_equal_approx(m[1]), "too hurt to chase")
	mage.hp = mage.max_hp()
	g.global_position = Vector3(BotInput.ENGAGE_DISTANCE + 1.0, 0.0, 0.0)
	m = _move_with_and_without(mage, g)
	check(m[0].is_equal_approx(m[1]), "beyond ENGAGE_DISTANCE it is left alone")
