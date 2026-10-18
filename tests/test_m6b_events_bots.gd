extends TestCase
## M6b EVENTS, the camera and the bots: CameraRig.event_points (the chest, the totem and the cart are framed
## while they matter) and BotInput's play – a bot without an enemy around walks up to a locked chest's camp,
## goes to an openable chest and stands on it, stays within 6 m of the totem and chases the caravan's cart
## (never kiting it) like a Loot Goblin.

const DT := 1.0 / 60.0

## A stand-in for an enemy hazard: pushes every bot the same way (the bots read hazard_push).
class PushProbe extends Node3D:
	func hazard_push(_from: Vector3) -> Vector2:
		return Vector2(0.0, 2.0)


class FakeHero extends Node3D:
	var alive := true

	func is_alive() -> bool:
		return alive


var arena: Arena
var _index := 0
var _nodes: Array[Node] = []


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 4242)
	arena = Arena.create()
	tree.root.add_child(arena)
	_index = 0


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	if is_instance_valid(arena):
		tree.root.remove_child(arena)
		arena.free()
	arena = null
	Enemy.invalidate_player_cache()
	PlayerManager.clear()


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


func _chest(pos: Vector3, state: GuardedChest.State) -> GuardedChest:
	var c := GuardedChest.create(5)
	arena.entities.add_child(c)
	c.global_position = pos
	c.state = state
	return c


func _totem(pos: Vector3) -> DefendTotem:
	var t := DefendTotem.create(5)
	arena.entities.add_child(t)
	t.global_position = pos
	return t


func _cart(pos: Vector3) -> CaravanCart:
	var c := CaravanCart.create_route(5, Vector3(-15, 0, pos.z), Vector3(15, 0, pos.z))
	arena.entities.add_child(c)
	c.global_position = pos
	return c


func _move(p: Player) -> Vector2:
	var bot := p.slot.input as BotInput
	bot.think(DT)
	return bot.get_move()


## The bot's move with [param node] in [param group] and without it (same wander: the first call draws it).
func _with_and_without(p: Player, node: Node, group: StringName) -> Array[Vector2]:
	var with_it := _move(p)
	node.remove_from_group(group)
	var without := _move(p)
	node.add_to_group(group)
	return [with_it, without]


func _event(p: Player, node: Node) -> Array[Vector2]:
	_move(p)  # draws the wander
	return _with_and_without(p, node, EventSpawner.GROUP)


# --- Camera ----------------------------------------------------------------------------------

func test_event_points_follow_what_matters() -> void:
	var chest := _chest(Vector3(3.0, 0.0, 2.0), GuardedChest.State.LOCKED)
	var totem := _totem(Vector3(-4.0, 0.0, 1.0))
	var cart := _cart(Vector3(0.0, 0.0, -5.0))
	var all: Array[Node] = [chest, totem, cart]
	var pts := CameraRig.event_points(all)
	check_eq(pts.size(), 3, "all three are framed")
	check(chest.global_position in pts and totem.global_position in pts and cart.global_position in pts, "at their feet")
	chest.state = GuardedChest.State.OPEN
	check(not chest.global_position in CameraRig.event_points(all), "an opened chest is not framed")
	totem.state = DefendTotem.State.HELD
	check(not totem.global_position in CameraRig.event_points(all), "a held totem is not framed")
	totem.state = DefendTotem.State.ACTIVE
	check(totem.global_position in CameraRig.event_points(all), "an active one is")
	cart.hp = 0.0
	check(not cart.global_position in CameraRig.event_points(all), "a dead cart is not framed")
	cart.hp = cart.max_hp
	cart._escaped = true
	check(not cart.global_position in CameraRig.event_points(all), "one that got away is not framed")
	var plain: Array[Node] = [Node3D.new()]
	check(CameraRig.event_points(plain).is_empty(), "other nodes are not event objects")
	plain[0].free()


func _frames(rig: CameraRig, p: Vector3) -> bool:
	var aspect := rig._aspect()
	var ext := CameraRig.ground_extents(rig.distance, aspect)
	return p.z - (rig.focus.z - ext.y) >= CameraRig.top_margin(rig.distance) - 0.001 \
		and (rig.focus.z + ext.z) - p.z >= CameraRig.FRAME_MARGIN_BOTTOM - 0.001 \
		and ext.x - absf(p.x - rig.focus.x) >= CameraRig.FRAME_MARGIN - 0.001


func test_the_rig_zooms_out_to_frame_an_event_target() -> void:
	var rig := arena.camera
	var hero := FakeHero.new()
	hero.add_to_group(&"players")
	tree.root.add_child(hero)
	_nodes.append(hero)
	hero.global_position = Vector3(-6.0, 0.0, 4.0)
	rig.snap()
	var alone := rig.distance
	for kind in 3:
		var t: Node3D
		match kind:
			0:
				t = _chest(Vector3(10.0, 0.0, -8.0), GuardedChest.State.LOCKED)
			1:
				t = _totem(Vector3(10.0, 0.0, -8.0))
			_:
				t = _cart(Vector3(10.0, 0.0, -8.0))
		rig.snap()
		check(_frames(rig, t.global_position), "%s is framed (focus %s, d %.1f)" % [t.name, rig.focus, rig.distance])
		check(_frames(rig, hero.global_position), "%s: the hero too" % t.name)
		check(rig.distance > alone and rig.distance <= CameraRig.MAX_DISTANCE, "zoomed out for %s: %.1f" % [t.name, rig.distance])
		check(rig.get_walk_rect(hero).size.x > 1.0e5, "%s never limits where the hero may walk" % t.name)
		arena.entities.remove_child(t)
		t.free()
	rig.snap()
	check_near(rig.distance, alone, 0.001, "without an event object the framing is the heroes' alone")


# --- Bots: the chest ---------------------------------------------------------------------------

func test_a_bot_walks_up_to_a_locked_chests_camp() -> void:
	var mage := _bot_player(&"mage", Vector3(-12.0, 0.0, 0.0))
	var chest := _chest(Vector3(0.0, 0.0, 0.0), GuardedChest.State.LOCKED)
	var m := _event(mage, chest)
	check(m[0].x > 0.5 and not m[0].is_equal_approx(m[1]), "a bot 12 m away walks towards the camp: %s" % m[0])
	mage.global_position = Vector3(-(BotInput.CHEST_CAMP_DISTANCE - 1.0), 0.0, 0.0)
	m = _event(mage, chest)
	check(m[0].is_equal_approx(m[1]), "inside the camp distance it has done its part (it fights the guards)")
	mage.global_position = Vector3(-12.0, 0.0, 0.0)
	var e := _enemy(Vector3(-12.0, 0.0, -2.0))
	m = _event(mage, chest)
	check(m[0].is_equal_approx(m[1]), "an enemy within CROWD_RADIUS: fight first")
	e.remove_from_group(&"enemies")
	mage.hp = mage.max_hp() * (BotInput.RETREAT_HP_RATIO - 0.1)
	m = _event(mage, chest)
	check(m[0].is_equal_approx(m[1]), "too hurt to go")


func test_a_bot_goes_to_a_ready_chest_and_stands_on_it() -> void:
	var warrior := _bot_player(&"warrior", Vector3(-5.0, 0.0, 0.0))
	var chest := _chest(Vector3(0.0, 0.0, 0.0), GuardedChest.State.READY)
	var m := _event(warrior, chest)
	check(m[0].x > 0.7 and not m[0].is_equal_approx(m[1]), "it walks to the openable chest: %s" % m[0])
	warrior.global_position = Vector3(-BotInput.CHEST_HOLD_DISTANCE + 0.2, 0.0, 0.0)
	check_eq(_move(warrior), Vector2.ZERO, "at the chest it stands still while it opens")
	var probe := PushProbe.new()
	probe.add_to_group(EnemyHazard.GROUP)
	arena.entities.add_child(probe)
	check(_move(warrior) != Vector2.ZERO, "but a hazard moves it")
	probe.remove_from_group(EnemyHazard.GROUP)
	check_eq(_move(warrior), Vector2.ZERO, "and it comes back to stand")
	chest.state = GuardedChest.State.OPEN
	var m_open := _event(warrior, chest)
	check(m_open[0].is_equal_approx(m_open[1]), "an open chest no longer pulls")
	probe.free()


func test_a_downed_bot_does_not_go_for_the_chest() -> void:
	var ghost := _bot_player(&"warrior", Vector3(-5.0, 0.0, 0.0))
	ghost.downed = true
	var chest := _chest(Vector3(0.0, 0.0, 0.0), GuardedChest.State.READY)
	var m := _event(ghost, chest)
	check(m[0].is_equal_approx(m[1]), "ghosts walk to the Spirit Healer, not the chest")


# --- Bots: the totem ---------------------------------------------------------------------------

func test_a_bot_stays_within_6_m_of_the_totem() -> void:
	var mage := _bot_player(&"mage", Vector3(-4.0, 0.0, 0.0))
	var totem := _totem(Vector3(0.0, 0.0, 0.0))
	var m := _event(mage, totem)
	check(m[0].is_equal_approx(m[1]), "within the limit nothing pulls it")
	mage.global_position = Vector3(-(DefendTotem.GUARD_RADIUS - BotInput.TOTEM_PULL_MARGIN) - 0.5, 0.0, 0.0)
	var near_limit := _event(mage, totem)
	check(near_limit[0].x > near_limit[1].x, "just past the limit it is drawn back")
	mage.global_position = Vector3(-DefendTotem.GUARD_RADIUS - 3.0, 0.0, 0.0)
	var far := _event(mage, totem)
	check(far[0].x > far[1].x + 0.3, "far outside it is pulled back hard (%s vs %s)" % [far[0], far[1]])
	check(far[0].x >= near_limit[0].x, "the further out, the more it heads straight for the totem")
	totem.state = DefendTotem.State.HELD
	var done := _event(mage, totem)
	check(done[0].is_equal_approx(done[1]), "a held totem needs no more guarding")


func test_a_bot_with_a_swarm_on_the_totem_still_comes_back_to_it() -> void:
	var mage := _bot_player(&"mage", Vector3(-9.0, 0.0, 0.0))
	var totem := _totem(Vector3(0.0, 0.0, 0.0))
	for i in 3:
		_enemy(Vector3(-7.0, 0.0, float(i) - 1.0))
	var m := _event(mage, totem)
	check(m[0].x > m[1].x, "the totem still pulls it, whatever it kites from")


# --- Bots: the cart ----------------------------------------------------------------------------

func test_bots_chase_the_cart_when_no_enemy_is_near() -> void:
	var mage := _bot_player(&"mage", Vector3(-12.0, 0.0, 0.0))
	var cart := _cart(Vector3(2.0, 0.0, 0.0))
	_move(mage)
	var m := _with_and_without(mage, cart, &"enemies")
	check(m[0].x > 0.8 and not m[0].is_equal_approx(m[1]), "a ranged bot runs after the cart 14 m away: %s" % m[0])
	cart.global_position = Vector3(-12.0 + BotInput.KITE_DISTANCE - 1.0, 0.0, 0.0)
	m = _with_and_without(mage, cart, &"enemies")
	check(m[0].is_equal_approx(m[1]), "close enough to shoot it: no more chasing, and no kiting from it")
	var warrior := _bot_player(&"warrior", Vector3(-8.0, 0.0, 6.0))
	cart.global_position = Vector3(-8.0, 0.0, 6.0 - 6.0)
	_move(warrior)
	m = _with_and_without(warrior, cart, &"enemies")
	check(m[0].y < -0.5 and not m[0].is_equal_approx(m[1]), "a melee bot closes in: %s" % m[0])


func test_bots_leave_the_cart_when_crowded_hurt_or_far() -> void:
	var mage := _bot_player(&"mage", Vector3.ZERO)
	var cart := _cart(Vector3(12.0, 0.0, 0.0))
	_move(mage)
	var e := _enemy(Vector3(0.0, 0.0, -2.0))
	var m := _with_and_without(mage, cart, &"enemies")
	check(m[0].is_equal_approx(m[1]), "an enemy within CROWD_RADIUS: fight / kite first")
	e.remove_from_group(&"enemies")
	mage.hp = mage.max_hp() * (BotInput.RETREAT_HP_RATIO - 0.1)
	m = _with_and_without(mage, cart, &"enemies")
	check(m[0].is_equal_approx(m[1]), "too hurt to chase")
	mage.hp = mage.max_hp()
	cart.global_position = Vector3(BotInput.CART_ENGAGE_DISTANCE + 1.0, 0.0, 0.0)
	m = _with_and_without(mage, cart, &"enemies")
	check(m[0].is_equal_approx(m[1]), "beyond CART_ENGAGE_DISTANCE it is left alone")
	cart.global_position = Vector3(BotInput.CART_ENGAGE_DISTANCE - 2.0, 0.0, 0.0)
	m = _with_and_without(mage, cart, &"enemies")
	check(not m[0].is_equal_approx(m[1]), "but a cart across the whole arena is worth the run")
