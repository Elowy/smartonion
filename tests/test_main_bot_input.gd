extends TestCase
## BotInput (the smoke / demo bots Main spawns): kiting by weapon reach, retreat when hurt,
## rescue runs to downed teammates, ghosts seeking help, wall avoidance.

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


func test_bot_runs_to_a_downed_teammate_and_stays() -> void:
	var rescuer := _bot_player(&"rogue", Vector3.ZERO)
	var ghost := _bot_player(&"mage", Vector3(0.0, 0.0, -8.0))
	ghost.downed = true
	var m := _move(rescuer)
	check(m.y < -0.9, "heads north to the ghost: %s" % m)
	rescuer.global_position = Vector3(0.0, 0.0, -7.2)
	check_eq(_move(rescuer), Vector2.ZERO, "stands still inside the revive circle")
	_enemy(Vector3(1.0, 0.0, -7.2))
	check(_move(rescuer) != Vector2.ZERO, "an enemy on top of it makes it step away")


func test_ghost_seeks_a_living_teammate() -> void:
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
