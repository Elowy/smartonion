extends TestCase
## SpiritHealer (GDD 1): part of the arena at Arena.SPIRIT_HEALER_POINT; a 10 s countdown
## (restarted every wave) revives every ghost in its circle at full HP when it hits 0, except
## ghosts with Resurrection Sickness (15 s after a healer revive); living players
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


## Runs the healer (and [param players]) until the next pulse is at most one step (plus
## [param before] seconds) away: the following DT step fires it.
func _to_pulse(players: Array[Player] = [], before: float = 0.0) -> void:
	var steps := ceili((healer.pulse_left - before) / DT - 0.0001) - 1
	for i in maxi(0, steps):
		_step(DT, players)


func test_pulse_revives_ghosts_in_the_circle_at_full_hp() -> void:
	check_eq(SpiritHealer.PULSE_INTERVAL, 10.0, "a 10 s countdown")
	check_eq(SpiritHealer.REVIVE_HP_RATIO, 1.0, "GDD 1: 100% HP")
	healer.begin_wave()
	var ghost := _ghost(0, Vector3(1.0, 0, 0.6))
	var events: Array[bool] = []
	ghost.downed_changed.connect(func(v: bool) -> void: events.append(v))
	var revived: Array[Player] = []
	healer.resurrected.connect(func(p: Player) -> void: revived.append(p))
	_step(4.0, [ghost])
	check(ghost.downed, "waits for the pulse")
	check_near(ghost.healer_seconds_left, 6.0, 0.02, "6 s to the pulse")
	check_near(ghost.healer_channel, 0.4, 0.002, "bar at 40%")
	check(healer.is_active(), "a ghost exists: the healer glows")
	check(ghost.model.is_cast_bar_visible(), "the ghost shows the cast bar")
	check(ghost.model._reviver_color.is_equal_approx(SpiritHealer.CAST_COLOR), "in the pale spirit colour")
	var feet := ghost.global_position
	_to_pulse([ghost])
	check(ghost.downed, "still a ghost right before the pulse")
	_step(DT, [ghost])
	check(not ghost.downed, "revived by the pulse")
	check_eq(ghost.hp, ghost.max_hp(), "at 100% HP")
	check_eq(events, [false] as Array[bool], "downed_changed(false)")
	check_eq(revived.size(), 1, "resurrected signal")
	check_near(ghost.res_sickness_left, Player.RES_SICKNESS_TIME, DT + 0.001, "15 s Resurrection Sickness")
	check_eq(ghost.healer_channel, 0.0, "no channel left")
	check(not ghost.model.is_cast_bar_visible(), "cast bar gone")
	var fx := _effects()
	check_eq(fx["columns"], 1, "a column of light")
	check_eq(fx["resurrected"], 1, "\"Resurrected!\"")
	for c in world.get_children():
		var col := c as VfxEffect
		if col != null and col.kind == VfxEffect.Kind.RESURRECT:
			check(Vector2(col.global_position.x - feet.x, col.global_position.z - feet.z).length() < 0.01, "at the ghost's feet")
	check_near(healer.pulse_left, SpiritHealer.PULSE_INTERVAL, DT + 0.001, "the countdown starts over")
	healer._physics_process(DT)
	check(not healer.is_active(), "calm again without ghosts")


func test_the_countdown_runs_on_and_restarts_each_wave() -> void:
	healer.begin_wave()
	_step(3.0)
	check_near(healer.pulse_left, 7.0, 0.02, "runs without ghosts too")
	var ghost := _ghost(0, Vector3(0.4, 0, 0))
	_step(7.0 + DT, [ghost])
	check(not ghost.downed, "a ghost arriving late waits only for the running countdown")
	RunState.set_wave(RunState.wave + 1)
	check_eq(healer.pulse_left, SpiritHealer.PULSE_INTERVAL, "a new wave restarts it")


func test_resurrection_sickness_blocks_the_healer_for_15_s() -> void:
	healer.begin_wave()
	var ghost := _ghost(0, Vector3(0.4, 0, 0))
	_to_pulse([ghost])
	_step(DT, [ghost])
	check(not ghost.downed, "first revive")
	ghost.invulnerable_left = 0.0
	ghost.take_damage(9999.0)
	check(ghost.downed, "down again at once")
	_step(10.0, [ghost])
	check(ghost.downed, "the next pulse skips a sick ghost")
	check_eq(ghost.healer_channel, 0.0, "no healer bar while sick")
	check(not healer.will_revive(ghost), "will_revive says no")
	_step(5.2, [ghost])
	check(ghost.res_sickness_left <= 0.0, "sickness over after 15 s")
	check(ghost.downed, "still waiting for a pulse")
	_to_pulse([ghost])
	_step(DT, [ghost])
	check(not ghost.downed, "the first pulse after the sickness revives")
	ghost.begin_wave()
	check_eq(ghost.res_sickness_left, 0.0, "a new wave clears the sickness")


func test_sickness_does_not_block_teammates() -> void:
	var ghost := _ghost(0, Vector3(5, 0, 0))
	ghost.res_sickness_left = Player.RES_SICKNESS_TIME
	Fakes.spawn_player(world, 1, &"warrior", Vector3(5.5, 0, 0))
	Fakes.step(ghost, Player.REVIVE_TIME + 0.2, 0.1)
	check(not ghost.downed, "a teammate still revives a sick ghost")


func test_leaving_the_circle_drops_the_bar() -> void:
	healer.begin_wave()
	var ghost := _ghost(0, Vector3(0.5, 0, 0))
	_step(2.0, [ghost])
	check(ghost.healer_channel > 0.0, "waiting in the circle")
	ghost.global_position = Vector3(SpiritHealer.HEAL_RADIUS + 0.3, 0, 0)
	_step(DT, [ghost])
	check_eq(ghost.healer_channel, 0.0, "left the circle: nothing on the cast bar")
	check(not ghost.model.is_cast_bar_visible(), "cast bar hidden")
	_to_pulse([ghost])
	_step(DT, [ghost])
	check(ghost.downed, "a ghost outside the circle is not revived")
	check(healer.is_active(), "still a ghost around")


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
	_step(SpiritHealer.PULSE_INTERVAL + DT, [far])
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
	check_eq(p.healer_channel, 0.0, "nothing on the hook")
	check(not healer.is_active(), "no ghost: calm")


func test_one_pulse_revives_every_ghost_in_the_circle() -> void:
	healer.begin_wave()
	var a := _ghost(0, Vector3(0.6, 0, 0))
	var b := _ghost(1, Vector3(-0.6, 0, 0.3))
	var c := _ghost(2, Vector3(0, 0, -1.2))
	var outside := _ghost(3, Vector3(6, 0, 0))
	var revived: Array[Player] = []
	healer.resurrected.connect(func(p: Player) -> void: revived.append(p))
	_step(0.5)
	check_eq(healer.ghost_count, 4, "four ghosts")
	for g: Player in [a, b, c]:
		check(g.healer_channel > 0.0, "%s waits in the circle" % g.name)
	check_eq(outside.healer_channel, 0.0, "the one outside does not")
	_to_pulse()
	_step(DT)
	for g: Player in [a, b, c]:
		check(not g.downed and g.hp == g.max_hp(), "%s back at full HP" % g.name)
	check(outside.downed, "the one outside is still a ghost")
	check_eq(revived.size(), 3, "three revives in one pulse")
	check_eq(_effects()["columns"], 3, "three light columns")
	healer._physics_process(DT)
	check_eq(healer.ghost_count, 1, "one ghost left")
	check(healer.is_active(), "still glowing for it")


func test_teammate_revive_and_healer_do_not_fight() -> void:
	healer.begin_wave()
	# The teammate's revive is further along: its bar shows, and it finishes first (30% HP).
	var ghost := _ghost(0, Vector3(5.0, 0, 1.0))
	var mate := Fakes.spawn_player(world, 1, &"warrior", Vector3(5.0, 0, 0))
	_step(4.5, [ghost])
	check_near(ghost.revive_progress, 4.5, 0.01, "teammate revive at 90%")
	ghost.global_position = Vector3(0.8, 0, 0)
	mate.global_position = Vector3(1.8, 0, 0)
	_step(0.3, [ghost])
	check(ghost.healer_channel > 0.0, "the healer counts down for it too")
	check(ghost.model._reviver_color.is_equal_approx(mate.slot.color), "the bar shows the teammate's (closer) revive")
	_step(0.3, [ghost])
	check(not ghost.downed, "the teammate finished first")
	check_eq(ghost.hp, roundf(ghost.max_hp() * Player.REVIVE_HP_RATIO), "teammate revive: 30% HP")
	check_eq(ghost.res_sickness_left, 0.0, "no sickness from a teammate revive")
	healer._physics_process(DT)
	check_eq(ghost.healer_channel, 0.0, "the healer let go")
	# The healer's pulse is closer: its bar shows, and it revives at 100%.
	var ghost2 := _ghost(2, Vector3(0, 0, 0.5))
	var mate2 := Fakes.spawn_player(world, 3, &"warrior", Vector3(1.0, 0, 0.5))
	healer.pulse_left = 1.0
	_step(0.5, [ghost2])
	check(ghost2.revive_progress > 0.0, "the teammate revives too")
	check(ghost2.model._reviver_color.is_equal_approx(SpiritHealer.CAST_COLOR), "the bar shows the healer (closer)")
	_step(0.5 + DT, [ghost2])
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
	var arena := Arena.current
	var ghost := _ghost(0, Vector3(5, 0, 0))
	var frame := UnitFrame.create(0)
	_nodes.append(frame)
	tree.root.add_child(frame)
	frame.bind(ghost)
	check(frame.is_downed_shown(), "DOWNED overlay")
	check(frame.hint_label.is_visible_in_tree(), "hint shown")
	frame._process(0.016)
	check("Spirit Healer" in frame.hint_label.text, "names the Spirit Healer: %s" % frame.hint_label.text)
	ghost.global_position = Vector3(0.5, 0, 0)
	healer.begin_wave()
	_step(4.0, [ghost])
	frame._process(0.016)
	check_near(frame.revive_bar.ratio(), 0.4, 0.01, "the bar shows the healer's countdown")
	check(frame.revive_bar.fill_color.is_equal_approx(SpiritHealer.CAST_COLOR), "in the spirit colour")
	if arena != null and arena.spirit_healer == healer:
		check(frame.hint_label.text == UnitFrame.WAITING_HINT % 6, "\"Spirit Healer: 6 s\": %s" % frame.hint_label.text)
	ghost.res_sickness_left = 9.5
	frame._process(0.016)
	check_eq(frame.hint_label.text, UnitFrame.SICKNESS_HINT % 10, "Resurrection Sickness countdown")
	ghost.res_sickness_left = 0.0
	_to_pulse([ghost])
	_step(DT, [ghost])
	frame._process(0.016)
	check(not frame.is_downed_shown(), "overlay gone after the revive")
