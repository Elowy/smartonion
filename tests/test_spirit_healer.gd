extends TestCase
## SpiritHealer (GDD 1): part of the arena at Arena.SPIRIT_HEALER_POINT; a ghost standing in its
## circle for CHANNEL_TIME comes back at full HP; leaving resets the channel; living players
## are not affected; several ghosts channel at once; the cast bar shows the revive that is
## further along; the unit frame tells a ghost where to go.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 0.1

var world: Node3D
var healer: SpiritHealer
var _nodes: Array[Node] = []


func before_each() -> void:
	RunState.start_run(1, 1234)
	world = Fakes.make_world(tree)
	healer = SpiritHealer.create()
	world.add_child(healer)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	Fakes.free_world(world)
	world = null
	healer = null
	tree.paused = false


func _ghost(index: int, pos: Vector3) -> Player:
	var p := Fakes.spawn_player(world, index, &"warrior", pos)
	p.take_damage(999.0)
	return p


## Steps the healer, then the given players (the arena order: the healer comes before the
## entities), for [param seconds].
func _step(seconds: float, players: Array[Player] = []) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		healer._physics_process(DT)
		for p in players:
			p._physics_process(DT)
		t += DT


func _effects() -> Dictionary:
	var out := {"columns": 0, "resurrected": 0}
	for c in world.get_children():
		var fx := c as VfxEffect
		if fx == null:
			continue
		if fx.kind == VfxEffect.Kind.RESURRECT:
			out["columns"] += 1
		var label := fx.get_node_or_null("Label") as Label3D
		if label != null and label.text == "Resurrected!":
			out["resurrected"] += 1
	return out


func test_arena_has_one_healer_at_its_point() -> void:
	var arena := Arena.create()
	_nodes.append(arena)
	tree.root.add_child(arena)
	var h := arena.spirit_healer
	check(h != null and h.get_parent() == arena, "the healer is part of the level (a child of the arena)")
	check(h.get_parent() != arena.entities, "not one of the per-wave entities")
	check(h.global_position.is_equal_approx(Arena.SPIRIT_HEALER_POINT), "at the healer point %s" % h.global_position)
	check(Arena.SPIRIT_HEALER_POINT.is_equal_approx(Vector3.ZERO), "the arena centre")
	check(arena.is_inside(Arena.SPIRIT_HEALER_POINT, SpiritHealer.HEAL_RADIUS + 1.0), "the whole circle is inside the walls")
	var healers := 0
	for n in arena.find_children("*", "Node3D", true, false):
		if n is SpiritHealer:
			healers += 1
	check_eq(healers, 1, "one healer per arena")
	check(h.find_children("*", "CollisionObject3D", true, false).is_empty(), "nothing to collide with")
	check(h.find_children("*", "OmniLight3D", true, false).size() == 1, "one light")
	check_eq(h.process_mode, Node.PROCESS_MODE_INHERIT, "pauses with the (pausable) arena")
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	tree.paused = true
	check(not h.can_process(), "pausing the game pauses the healer")
	tree.paused = false
	check(h.can_process(), "and it runs again")


func test_ghost_in_the_circle_revives_at_full_hp_after_one_second() -> void:
	check_eq(SpiritHealer.CHANNEL_TIME, 1.0, "GDD 1: 1 s")
	check_eq(SpiritHealer.REVIVE_HP_RATIO, 1.0, "GDD 1: 100% HP")
	var ghost := _ghost(0, Vector3(1.0, 0, 0.6))
	var events: Array[bool] = []
	ghost.downed_changed.connect(func(v: bool) -> void: events.append(v))
	var revived: Array[Player] = []
	healer.resurrected.connect(func(p: Player) -> void: revived.append(p))
	check(ghost.downed, "downed")
	_step(0.5, [ghost])
	check(ghost.downed, "still a ghost after 0.5 s")
	check_near(healer.channel_time(ghost), 0.5, 0.001, "channelling")
	check_near(ghost.healer_channel, 0.5, 0.001, "half way")
	check_near(ghost.healer_seconds_left, 0.5, 0.001, "0.5 s left")
	check(healer.is_active(), "a ghost exists: the healer glows")
	check(ghost.model.is_cast_bar_visible(), "the ghost shows the cast bar")
	var cast_text: String = ghost.model._cast_label.text
	check("0.5" in cast_text, "with the seconds left: %s" % cast_text)
	check(ghost.model._reviver_color.is_equal_approx(SpiritHealer.CAST_COLOR), "in the pale spirit colour")
	check_near(ghost.model.revive_progress, 0.5, 0.001, "bar half full")
	var feet := ghost.global_position
	_step(0.5, [ghost])
	check(not ghost.downed, "revived after 1 s")
	check_eq(ghost.hp, ghost.max_hp(), "at 100% HP")
	check_eq(events, [false] as Array[bool], "downed_changed(false)")
	check_eq(revived.size(), 1, "resurrected signal")
	check_near(ghost.invulnerable_left, Player.INVULNERABLE_AFTER_REVIVE - DT, 0.001, "the usual grace after a revive")
	check_eq(ghost.healer_channel, 0.0, "no channel left")
	check(not ghost.model.is_cast_bar_visible(), "cast bar gone")
	var fx := _effects()
	check_eq(fx["columns"], 1, "a column of light")
	check_eq(fx["resurrected"], 1, "\"Resurrected!\"")
	for c in world.get_children():
		var col := c as VfxEffect
		if col != null and col.kind == VfxEffect.Kind.RESURRECT:
			check(Vector2(col.global_position.x - feet.x, col.global_position.z - feet.z).length() < 0.01, "at the ghost's feet")
	healer._physics_process(DT)
	check(not healer.is_active(), "calm again without ghosts")


func test_leaving_the_circle_resets_the_channel() -> void:
	var ghost := _ghost(0, Vector3(0.5, 0, 0))
	_step(0.7, [ghost])
	check_near(healer.channel_time(ghost), 0.7, 0.001, "0.7 s channelled")
	ghost.global_position = Vector3(SpiritHealer.HEAL_RADIUS + 0.3, 0, 0)
	_step(DT, [ghost])
	check_eq(healer.channel_time(ghost), 0.0, "left the circle: reset")
	check_eq(ghost.healer_channel, 0.0, "nothing on the cast bar")
	check(not ghost.model.is_cast_bar_visible(), "cast bar hidden")
	check(healer.is_active(), "still a ghost around")
	ghost.global_position = Vector3(0, 0, -0.5)
	_step(0.7, [ghost])
	check(ghost.downed, "back in: a fresh 1 s channel")
	_step(0.3, [ghost])
	check(not ghost.downed, "revived after a full second in the circle")
	check_eq(ghost.hp, ghost.max_hp(), "full HP")


func test_radius_is_a_flat_ground_distance() -> void:
	check_near(SpiritHealer.HEAL_RADIUS, 1.6, 0.0001, "about 1.6 m")
	check(SpiritHealer.in_radius(Vector3.ZERO, Vector3(1.55, 0, 0)), "inside")
	check(SpiritHealer.in_radius(Vector3.ZERO, Vector3(1.0, 3.0, -1.2)), "height does not count")
	check(not SpiritHealer.in_radius(Vector3.ZERO, Vector3(1.2, 0, 1.2)), "outside (1.7 m)")
	healer.position = Vector3(4, 0, -2)
	check(healer.contains(Vector3(5, 0, -2)), "around its own position")
	check(not healer.contains(Vector3.ZERO), "not around the origin")
	var far := _ghost(0, Vector3(1.7, 0, 0))
	far.global_position = Vector3(5.0, 0, -1.5)
	_step(2.0, [far])
	check(not far.downed, "revived around the moved healer")


func test_living_players_are_not_affected() -> void:
	var p := Fakes.spawn_player(world, 0, &"warrior", Vector3(0.3, 0, 0))
	p.take_damage(5.0)
	var hp := p.hp
	check(hp < p.max_hp(), "hurt")
	var events: Array[bool] = []
	p.downed_changed.connect(func(v: bool) -> void: events.append(v))
	_step(3.0)
	check_eq(p.hp, hp, "no healing for the living")
	check(events.is_empty(), "no revive")
	check_eq(healer.channel_time(p), 0.0, "no channel")
	check_eq(p.healer_channel, 0.0, "nothing on the hook")
	check(not healer.is_active(), "no ghost: calm")


func test_several_ghosts_channel_at_once() -> void:
	var a := _ghost(0, Vector3(0.6, 0, 0))
	var b := _ghost(1, Vector3(-0.6, 0, 0.3))
	var c := _ghost(2, Vector3(0, 0, -1.2))
	var outside := _ghost(3, Vector3(6, 0, 0))
	var revived: Array[Player] = []
	healer.resurrected.connect(func(p: Player) -> void: revived.append(p))
	_step(0.5)
	check_eq(healer.ghost_count, 4, "four ghosts")
	for g: Player in [a, b, c]:
		check_near(healer.channel_time(g), 0.5, 0.001, "%s channels" % g.name)
	check_eq(healer.channel_time(outside), 0.0, "the one outside does not")
	_step(0.5)
	for g: Player in [a, b, c]:
		check(not g.downed and g.hp == g.max_hp(), "%s back at full HP" % g.name)
	check(outside.downed, "the one outside is still a ghost")
	check_eq(revived.size(), 3, "three revives")
	check_eq(_effects()["columns"], 3, "three light columns")
	healer._physics_process(DT)
	check_eq(healer.ghost_count, 1, "one ghost left")
	check(healer.is_active(), "still glowing for it")


func test_teammate_revive_and_healer_do_not_fight() -> void:
	# The teammate's revive is further along: its bar shows, and it finishes first (30% HP).
	var ghost := _ghost(0, Vector3(1.0, 0, 0))
	var mate := Fakes.spawn_player(world, 1, &"warrior", Vector3(5.0, 0, 0))
	ghost.global_position = Vector3(5.0, 0, 1.0)  # outside the healer circle, next to the mate
	_step(4.5, [ghost])
	check_near(ghost.revive_progress, 4.5, 0.01, "teammate revive at 90%")
	ghost.global_position = Vector3(0.8, 0, 0)
	mate.global_position = Vector3(1.8, 0, 0)
	_step(0.3, [ghost])
	check(ghost.healer_channel > 0.0, "the healer channels too")
	check(ghost.model._reviver_color.is_equal_approx(mate.slot.color), "the bar shows the teammate's (closer) revive")
	check(ghost.model.revive_progress > 0.9, "at its progress")
	_step(0.3, [ghost])
	check(not ghost.downed, "the teammate finished first")
	check_eq(ghost.hp, roundf(ghost.max_hp() * Player.REVIVE_HP_RATIO), "teammate revive: 30% HP")
	check_eq(_effects()["columns"], 1, "only one revive")
	healer._physics_process(DT)
	check_eq(ghost.healer_channel, 0.0, "the healer let go")
	# The healer is further along: its bar shows, and it revives at 100%.
	var ghost2 := _ghost(2, Vector3(0, 0, 0.5))
	var mate2 := Fakes.spawn_player(world, 3, &"warrior", Vector3(1.0, 0, 0.5))
	_step(0.5, [ghost2])
	check(ghost2.revive_progress > 0.0, "the teammate revives too")
	check(ghost2.model._reviver_color.is_equal_approx(SpiritHealer.CAST_COLOR), "the bar shows the healer (further along)")
	check_near(ghost2.model.revive_progress, 0.5, 0.001, "at the healer's progress")
	_step(0.5, [ghost2])
	check(not ghost2.downed, "the healer finished first")
	check_eq(ghost2.hp, ghost2.max_hp(), "healer revive: 100% HP")
	check(mate2.is_alive(), "the teammate is fine")


func test_ghosts_walk_at_full_speed() -> void:
	check_eq(Player.GHOST_SPEED_MULT, 1.0, "ghosts are not slowed (GDD 1)")
	var ghost := _ghost(0, Vector3(5, 0, 5))
	(ghost.slot.input as ScriptedInput).move = Vector2(1, 0)
	Fakes.step(ghost, 1.0)
	check_near(ghost.velocity.length(), ghost.stats.move_speed(), 0.01, "same top speed as when alive")


func test_unit_frame_tells_the_ghost_where_to_go() -> void:
	var ghost := _ghost(0, Vector3(5, 0, 0))
	var frame := UnitFrame.create(0)
	_nodes.append(frame)
	tree.root.add_child(frame)
	frame.bind(ghost)
	check(frame.is_downed_shown(), "DOWNED overlay")
	check(frame.hint_label.is_visible_in_tree(), "hint shown")
	check_eq(frame.hint_label.text, UnitFrame.GHOST_HINT, "hint text")
	check("Spirit Healer" in frame.hint_label.text, "names the Spirit Healer")
	ghost.global_position = Vector3(0.5, 0, 0)
	_step(0.4, [ghost])
	frame._process(0.016)
	check_near(frame.revive_bar.ratio(), 0.4, 0.001, "the bar shows the healer's channel")
	check(frame.revive_bar.fill_color.is_equal_approx(SpiritHealer.CAST_COLOR), "in the spirit colour")
	_step(0.6, [ghost])
	check(not frame.is_downed_shown(), "overlay gone after the revive")
