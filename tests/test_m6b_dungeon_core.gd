extends TestCase
## M6b DUNGEON, the core (GDD 16.1, dungeon portal): the Arena's dungeon layout (24 x 14, the run's
## palette, no Spirit Healer, nothing of the clearing lost), the Dungeon's four rooms (Clear / Survive /
## Defend / Warden), the 3 s heal pauses, the fail rules (everybody down, a lost brazier), the Warden
## (a BossData run by Boss, enrage at 60 s, Raise Dead through the Dungeon), the dungeon enemies' lack
## of loot, the rewards (an Epic per hero, the extra set piece, 20x the average gold, the failure's
## 50% purse loss) and the brazier. The portal vote, the Intermission and Main are in
## test_m6b_dungeon_ui.gd.

const PFakes := preload("res://tests/player_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var arena: Arena
var dungeon: Dungeon
var heroes: Array[Player] = []
var finished_with: Array[bool] = []
var rooms_cleared_events: Array[int] = []
var waves_ended := 0


func before_each() -> void:
	PlayerManager.clear()
	UiFakes.reset_players()
	RunState.start_run(2, 777)
	RunState.set_wave(6)
	world = Node3D.new()
	world.name = "DungeonTestWorld"
	tree.root.add_child(world)
	tree.current_scene = world
	arena = Arena.create()
	world.add_child(arena)
	heroes.clear()
	finished_with.clear()
	rooms_cleared_events.clear()
	waves_ended = 0
	Enemy.invalidate_player_cache()


func after_each() -> void:
	if dungeon != null and is_instance_valid(dungeon):
		if dungeon.get_parent() != null:
			dungeon.get_parent().remove_child(dungeon)
		dungeon.free()
	dungeon = null
	if world != null and is_instance_valid(world):
		if tree.current_scene == world:
			tree.current_scene = null
		world.free()
	world = null
	arena = null
	heroes.clear()
	PlayerManager.clear()
	UiFakes.reset_players()
	Db.reload()
	tree.paused = false
	RunState.start_run(1, 1)
	Enemy.invalidate_player_cache()


# --- Helpers -------------------------------------------------------------------------------------

func _hero(index: int = 0, class_id: StringName = &"warrior", pos: Vector3 = Vector3.ZERO) -> Player:
	var p := PFakes.spawn_player(arena.entities, index, class_id, pos)
	heroes.append(p)
	return p


func _slots() -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	for h in heroes:
		out.append(h.slot)
	return out


## A dungeon for [param p_wave] with [param count] heroes, started (INTRO).
func _start(p_wave: int = 6, count: int = 2) -> Dungeon:
	RunState.set_wave(p_wave)
	var classes: Array[StringName] = [&"warrior", &"mage", &"paladin", &"rogue"]
	for i in count:
		if i >= heroes.size():
			_hero(i, classes[i], Vector3(float(i), 0.0, 0.0))
	dungeon = Dungeon.create(arena, p_wave)
	world.add_child(dungeon)
	dungeon.finished.connect(func(ok: bool) -> void: finished_with.append(ok))
	dungeon.room_cleared.connect(func(i: int) -> void: rooms_cleared_events.append(i))
	for h in heroes:
		h.wave_ended.connect(func() -> void: waves_ended += 1)
	dungeon.start(heroes)
	return dungeon


func _step(seconds: float) -> void:
	PFakes.step(dungeon, seconds)


## Enters room [param index] directly (after the intro).
func _enter_room(index: int) -> void:
	_step(Dungeon.INTRO_TIME + 0.02)
	if index != Dungeon.Room.CLEAR:
		dungeon._start_room(index)


func _kill_all() -> int:
	var n := 0
	for node in tree.get_nodes_in_group(&"enemies"):
		var e := node as Enemy
		if e != null and not e.is_dead():
			e.kill(heroes[0] if not heroes.is_empty() else null)
			n += 1
	return n


func _enemy_at(pos: Vector3, p_wave: int = 6) -> Enemy:
	var e := Enemy.create(Db.get_enemy(&"skeleton_grunt"), p_wave)
	e.drops_loot = false
	arena.entities.add_child(e)
	e.global_position = pos
	return e


func _down(p: Player) -> void:
	for i in 60:
		if p.downed:
			return
		p.invulnerable_left = 0.0
		p.take_damage(100000.0, CombatMath.KIND_MELEE, null)


# --- Arena: the dungeon layout ------------------------------------------------------------------------

func test_the_dungeon_layout_is_24_by_14_with_its_own_walls() -> void:
	var home_walls := arena.walls
	check_eq(arena.get_bounds().size, Arena.SIZE, "the clearing first")
	arena.enter_dungeon_layout()
	check(arena.in_dungeon_layout, "in the dungeon layout")
	check_eq(arena.play_size, Arena.DUNGEON_SIZE, "24 x 14")
	check_eq(Arena.DUNGEON_SIZE, Vector2(24.0, 14.0), "the GDD's size")
	check_eq(arena.get_bounds(), Rect2(-12.0, -7.0, 24.0, 14.0), "the playable rectangle")
	check_eq(Arena.SIZE, Vector2(34.0, 22.0), "SIZE (the static readers' fallback) is the clearing's")
	check(arena.walls != home_walls, "new walls")
	var boxes := Arena.wall_boxes_for(Arena.DUNGEON_SIZE)
	var shapes: Array[CollisionShape3D] = []
	for c in arena.walls.get_children():
		if c is CollisionShape3D:
			shapes.append(c)
	check_eq(shapes.size(), 4, "four wall colliders")
	for i in shapes.size():
		check_eq((shapes[i].shape as BoxShape3D).size, boxes[i].size, "wall %d size" % i)
		check_eq(shapes[i].position, boxes[i].get_center(), "wall %d place" % i)
	check(arena.clamp_point(Vector3(30, 0, 30), 0.0) == Vector3(12.0, 0.0, 7.0), "clamp_point follows the small room")
	check(not arena.is_inside(Vector3(15, 0, 0)) and arena.is_inside(Vector3(11, 0, 6)), "is_inside too")
	check_eq(arena.wall_boxes_for(Arena.SIZE), Arena.wall_boxes(), "the clearing's boxes are unchanged")


func test_a_stand_alone_small_arena_has_its_own_bounds_and_walls() -> void:
	var small := Arena.create(null, false, Arena.DUNGEON_SIZE)
	world.add_child(small)
	check_eq(small.get_bounds(), Rect2(-12.0, -7.0, 24.0, 14.0), "the small room's rectangle")
	check_eq(small.get_decor_rect().size, Arena.DUNGEON_SIZE + Vector2(48, 48), "its decor grows around it")
	var shapes: Array[CollisionShape3D] = []
	for c in small.walls.get_children():
		if c is CollisionShape3D:
			shapes.append(c)
	var boxes := Arena.wall_boxes_for(Arena.DUNGEON_SIZE)
	check_eq(shapes.size(), 4, "four walls")
	for i in shapes.size():
		check_eq((shapes[i].shape as BoxShape3D).size, boxes[i].size, "wall %d" % i)
	check_eq(arena.get_bounds().size, Arena.SIZE, "the other arena is the clearing")
	var default := Arena.create()
	check_eq(default.get_bounds().size, Arena.SIZE, "the default stays the clearing")
	default.free()


func test_the_dungeon_layout_has_no_spirit_healer_and_one_environment() -> void:
	check(arena.spirit_healer != null, "the clearing has one")
	var healer := arena.spirit_healer
	var home_env := arena.world_environment
	arena.enter_dungeon_layout()
	check(arena.spirit_healer == null, "no Grave Tender inside")
	check(not healer.is_processing() or healer.process_mode == Node.PROCESS_MODE_DISABLED, "the healer sleeps")
	var envs := 0
	var suns := 0
	for c in arena.get_children():
		if c is WorldEnvironment:
			envs += 1
		if c is DirectionalLight3D:
			suns += 1
	check_eq(envs, 1, "exactly one WorldEnvironment in the tree")
	check_eq(suns, 1, "exactly one sun")
	check(arena.world_environment != home_env and home_env.get_parent() == null, "the clearing's environment is parked")
	check(arena.entities.get_parent() == arena and arena.camera.get_parent() == arena, "entities and camera stay")
	check(Arena.current == arena, "Arena.current stays")


func test_leaving_the_dungeon_layout_restores_the_clearing_exactly() -> void:
	var home := {
		"walls": arena.walls, "ground": arena.ground, "sun": arena.sun, "env": arena.world_environment,
		"decor": arena.decor, "healer": arena.spirit_healer, "patches": arena.dirt_patches,
		"environment": arena.environment, "mode": arena.spirit_healer.process_mode,
	}
	arena.enter_dungeon_layout()
	var dungeon_walls := arena.walls
	arena.leave_dungeon_layout()
	check(not arena.in_dungeon_layout, "out of it")
	check(arena.walls == home["walls"] and arena.ground == home["ground"] and arena.sun == home["sun"]
			and arena.world_environment == home["env"] and arena.decor == home["decor"], "the same scenery nodes")
	check(arena.walls.get_parent() == arena and arena.world_environment.get_parent() == arena
			and arena.decor.get_parent() == arena and arena.ground.get_parent() == arena, "all back in the tree")
	check(arena.spirit_healer == home["healer"] and arena.spirit_healer.process_mode == home["mode"], "the healer is back")
	check(arena.dirt_patches == home["patches"] and arena.environment == home["environment"], "patches and palette")
	check_eq(arena.get_bounds(), Rect2(-Arena.SIZE / 2.0, Arena.SIZE), "the clearing's bounds")
	check(dungeon_walls.get_parent() == null, "the dungeon walls left the tree")
	var envs := 0
	for c in arena.get_children():
		if c is WorldEnvironment:
			envs += 1
	check_eq(envs, 1, "one WorldEnvironment again")


func test_the_dungeon_layout_wears_the_environment_palette() -> void:
	var env := EnvironmentData.new()
	env.id = &"test_env"
	env.sky_color = Color(0.1, 0.9, 0.3)
	env.grass_mid = Color(0.9, 0.1, 0.1)
	var home_sky := arena.world_environment.environment.background_color
	arena.enter_dungeon_layout(env)
	check_eq(arena.world_environment.environment.background_color, env.sky_color, "the sky")
	check_eq((arena.ground.material_override as ShaderMaterial).get_shader_parameter("grass_mid"), env.grass_mid, "the ground")
	check_eq((arena.ground.material_override as ShaderMaterial).get_shader_parameter("arena_half"), Arena.DUNGEON_SIZE / 2.0,
			"the ground shader knows the small room")
	arena.leave_dungeon_layout()
	check_eq(arena.world_environment.environment.background_color, home_sky, "the clearing's sky is back")


func test_the_layout_works_on_a_hardcore_arena_without_a_healer() -> void:
	var bare := Arena.create(null, false)
	world.add_child(bare)
	check(bare.spirit_healer == null, "a hardcore arena has no healer")
	bare.enter_dungeon_layout()
	check(bare.spirit_healer == null and bare.in_dungeon_layout, "none inside either")
	bare.leave_dungeon_layout()
	check(bare.spirit_healer == null and not bare.in_dungeon_layout, "and none afterwards (nothing appears out of thin air)")
	check_eq(bare.get_bounds().size, Arena.SIZE, "the clearing is back")


func test_entering_and_leaving_twice_is_harmless() -> void:
	arena.enter_dungeon_layout()
	var walls := arena.walls
	arena.enter_dungeon_layout()
	check(arena.walls == walls, "a second enter changes nothing")
	arena.leave_dungeon_layout()
	arena.leave_dungeon_layout()
	check(not arena.in_dungeon_layout and arena.spirit_healer != null, "a second leave changes nothing")


func test_freeing_the_arena_in_the_dungeon_layout_frees_the_parked_clearing() -> void:
	arena.enter_dungeon_layout()
	var parked: Array[Node] = [arena._home["walls"], arena._home["ground"], arena._home["sun"],
			arena._home["world_environment"], arena._home["decor"]]
	var ids: Array[int] = []
	for n in parked:
		ids.append(n.get_instance_id())
		check(n.get_parent() == null, "parked outside the tree")
	world.remove_child(arena)
	arena.free()
	arena = null
	for id in ids:
		check(not is_instance_valid(instance_from_id(id)), "the parked node was freed with the arena")


# --- Dungeon: entering and the rooms --------------------------------------------------------------------

func test_portal_waves() -> void:
	for w in [6, 9, 12, 15]:
		check(Dungeon.is_portal_wave(w), "wave %d opens the portal" % w)
	for w in [1, 5, 7, 8, 10, 11, 13, 14, 16, 25]:
		check(not Dungeon.is_portal_wave(w), "wave %d does not" % w)


func test_start_enters_the_layout_and_places_and_heals_the_heroes() -> void:
	var h0 := _hero(0, &"warrior", Vector3(9.0, 0.0, 4.0))
	h0.hp = 1.0
	_start(6, 2)
	check(arena.in_dungeon_layout, "the arena is in the dungeon layout")
	check_eq(dungeon.phase, Dungeon.Phase.INTRO, "the intro first")
	check(dungeon.is_running(), "running")
	for h in heroes:
		check(arena.get_bounds().has_point(Vector2(h.global_position.x, h.global_position.z)), "%s is inside the small room" % h.name)
	check_eq(h0.global_position, arena.get_player_spawn_points(2)[0], "on the spawn points")
	check_near(h0.hp, h0.max_hp(), 0.01, "begin_wave healed the hero")
	check_eq(waves_ended, 0, "no wave-end signal (Artifacts must not grow)")


func test_the_intro_gives_way_to_room_one() -> void:
	_start()
	_step(Dungeon.INTRO_TIME - 0.1)
	check_eq(dungeon.phase, Dungeon.Phase.INTRO, "still the intro")
	_step(0.2)
	check_eq(dungeon.phase, Dungeon.Phase.ROOM, "room one")
	check_eq(dungeon.room, Dungeon.Room.CLEAR, "the Clear room")
	check_eq(dungeon.room_number(), 1, "Room 1")
	check(dungeon.pending_count() > 0, "the first group is already telegraphed")


func test_room_one_is_won_with_25_kills_and_never_overfills() -> void:
	_start()
	_step(Dungeon.INTRO_TIME + 0.02)
	var guard := 0
	var worst := 0
	while dungeon.phase == Dungeon.Phase.ROOM and guard < 400:
		_step(0.25)
		worst = maxi(worst, dungeon.alive_count() + dungeon.pending_count())
		_kill_all()
		guard += 1
	check_eq(dungeon.phase, Dungeon.Phase.PAUSE, "the Clear room is won")
	check_eq(dungeon.kills_total, Dungeon.CLEAR_KILLS, "exactly 25 enemies came and died")
	check(worst <= Dungeon.CLEAR_CAP, "never more than %d alive or telegraphed (%d)" % [Dungeon.CLEAR_CAP, worst])
	check_eq(rooms_cleared_events, [0] as Array[int], "room_cleared fired")
	check_eq(dungeon.rooms_cleared, 1, "counted")
	check_eq(dungeon.room_times.size(), 1, "its time was recorded")
	check_eq(dungeon.alive_count(), 0, "nothing left standing")


func test_the_dungeons_enemies_pay_no_loot_but_count_as_kills() -> void:
	_start()
	var kills := RunState.kills
	var gold := RunState.gold
	var xp := RunState.xp
	var e := _enemy_at(Vector3(5, 0, 0))
	e.kill(heroes[0])
	check_eq(RunState.kills, kills + 1, "the kill counts (meter, run stats)")
	check_eq(tree.get_nodes_in_group(&"pickups").size(), 0, "no gold / XP pickup")
	check_eq(RunState.gold, gold, "no gold")
	check_eq(RunState.xp, xp, "no XP")
	check(RunState.team_loot.is_empty(), "no item")
	# Control: an ordinary enemy of the same data does drop its pickup.
	var normal := Enemy.create(Db.get_enemy(&"skeleton_grunt"), 6)
	arena.entities.add_child(normal)
	normal.global_position = Vector3(6, 0, 0)
	normal.kill(heroes[0])
	check(tree.get_nodes_in_group(&"pickups").size() > 0, "a normal enemy does drop one (the test measures something)")


func test_hatched_groups_are_loot_free_enemies_of_the_cleared_wave() -> void:
	_start(9, 2)
	_step(Dungeon.INTRO_TIME + 1.2)
	var enemies := tree.get_nodes_in_group(&"enemies")
	check(enemies.size() > 0, "a group hatched")
	for node in enemies:
		var e := node as Enemy
		check(not e.drops_loot, "no loot")
		check_eq(e.wave, Dungeon.strength_wave(9), "scaled to the cleared wave plus the strength bonus")
		check(e.data.first_wave <= 9 and e.data.spawn_weight > 0.0, "an eligible enemy")
		check(arena.get_bounds().has_point(Vector2(e.global_position.x, e.global_position.z)), "inside the room")


func test_the_pause_between_rooms_heals_30_percent_and_lasts_3_seconds() -> void:
	_start()
	_enter_room(Dungeon.Room.CLEAR)
	var h := heroes[0]
	h.hp = h.max_hp() * 0.2
	var down := heroes[1]
	_down(down)
	dungeon._room_done()
	check_eq(dungeon.phase, Dungeon.Phase.PAUSE, "the pause")
	check_near(h.hp, h.max_hp() * 0.5, 0.6, "20% + 30% of Max HP")
	check(down.downed, "a downed hero is not healed or revived by the pause")
	check_eq(dungeon.task_text(), "Room cleared!", "the HUD says so")
	_step(Dungeon.ROOM_PAUSE - 0.1)
	check_eq(dungeon.phase, Dungeon.Phase.PAUSE, "3 s long")
	# (the downed hero would fail the dungeon only when everybody is down)
	_step(0.2)
	check_eq(dungeon.phase, Dungeon.Phase.ROOM, "the next room")
	check_eq(dungeon.room, Dungeon.Room.SURVIVE, "Survive follows Clear")


func test_the_heal_never_overfills() -> void:
	_start()
	_enter_room(Dungeon.Room.CLEAR)
	var h := heroes[0]
	h.hp = h.max_hp() * 0.9
	dungeon._room_done()
	check_near(h.hp, h.max_hp(), 0.001, "capped at Max HP")


func test_room_two_is_25_seconds_of_a_denser_spawn() -> void:
	_start()
	_enter_room(Dungeon.Room.CLEAR)
	var clear_rate := dungeon._rate
	dungeon._start_room(Dungeon.Room.SURVIVE)
	check(dungeon._rate > clear_rate, "denser than room one")
	check_near(dungeon._rate, WaveDirector.spawn_rate(6, RunState.coop_count_mult()) * Dungeon.SURVIVE_DENSITY, 0.0001,
			"SURVIVE_DENSITY x the wave's spawn rate for this party")
	check_near(dungeon.seconds_left(), 25.0, 0.01, "25 s on the clock")
	_step(24.9)
	check_eq(dungeon.phase, Dungeon.Phase.ROOM, "still surviving")
	check(dungeon.alive_count() > 0, "enemies about")
	_step(0.2)
	check_eq(dungeon.phase, Dungeon.Phase.PAUSE, "survived")
	check_eq(dungeon.alive_count(), 0, "the leftovers are swept")
	check_near(dungeon.room_times[-1], 25.0, 0.1, "the room took 25 s")


func test_room_three_draws_the_enemies_to_the_brazier_and_the_brazier_takes_their_hits() -> void:
	_start()
	_enter_room(Dungeon.Room.DEFEND)
	var b := dungeon.brazier
	check(b != null and b.is_inside_tree(), "the brazier stands")
	check_eq(b.global_position, Vector3.ZERO, "in the middle")
	check_near(b.max_hp, Dungeon.brazier_hp(Dungeon.strength_wave(6)), 0.001, "30 grunts' worth of HP")
	var grunt := Db.get_enemy(&"skeleton_grunt")
	check_near(b.max_hp, 30.0 * grunt.hp_at_wave(Dungeon.strength_wave(6)) * RunState.coop_hp_mult(), 0.001, "= 30 x a Grunt's HP x the party factor")
	dungeon._spawning = false
	var near := _enemy_at(Vector3(6, 0, 0))
	var far := _enemy_at(Vector3(11.5, 0, 0))
	var at_it := _enemy_at(Vector3(1.0, 0.0, 0.0))
	_step(DT)
	check(near.is_taunted() and near.taunt_target == b, "an enemy within 9 m chases the brazier")
	check(not far.is_taunted(), "one beyond that keeps its target")
	check(at_it.is_taunted(), "the one standing at it too")
	_step(Dungeon.BRAZIER_TICK)
	var hit := at_it.contact_damage * at_it.damage_mult
	check_near(b.hp, b.max_hp - hit, 0.001, "the enemy at the brazier hit it once: its contact damage")
	at_it.apply_stun(3.0)
	var hp_now := b.hp
	_step(Dungeon.BRAZIER_TICK)
	check_near(b.hp, hp_now, 0.001, "a stunned enemy does not hit")


func test_an_existing_taunt_of_another_source_is_left_alone() -> void:
	_start()
	_enter_room(Dungeon.Room.DEFEND)
	dungeon._spawning = false
	var decoy := Node3D.new()
	arena.entities.add_child(decoy)
	var e := _enemy_at(Vector3(4, 0, 0))
	e.apply_taunt(decoy, 5.0)
	_step(0.7)
	check(e.taunt_target == decoy, "the pet's taunt stays")


func test_room_three_is_won_after_20_seconds_with_the_brazier_standing() -> void:
	_start()
	_enter_room(Dungeon.Room.DEFEND)
	check_near(dungeon.seconds_left(), 20.0, 0.01, "20 s")
	_step(19.9)
	check_eq(dungeon.phase, Dungeon.Phase.ROOM, "holding")
	_step(0.2)
	check_eq(dungeon.phase, Dungeon.Phase.PAUSE, "held")
	check(dungeon.brazier == null, "the brazier is cleared away")
	check_eq(dungeon.room_times.size(), 1, "recorded")


func test_the_brazier_health_left_is_recorded_for_the_balance_pass() -> void:
	_start()
	check_near(dungeon.brazier_left, -1.0, 0.0001, "not known before the room is won")
	_enter_room(Dungeon.Room.DEFEND)
	dungeon._spawning = false
	dungeon.brazier.take_damage(dungeon.brazier.max_hp * 0.25)
	_step(Dungeon.DEFEND_TIME + 0.1)
	check_eq(dungeon.phase, Dungeon.Phase.PAUSE, "held")
	check_near(dungeon.brazier_left, 0.75, 0.0001, "75% left")


func test_a_destroyed_brazier_fails_the_dungeon() -> void:
	_start()
	_enter_room(Dungeon.Room.DEFEND)
	dungeon.brazier.take_damage(1.0e9)
	_step(DT)
	check_eq(dungeon.phase, Dungeon.Phase.OUTRO, "the outro")
	check(not dungeon.success, "a failure")
	check_eq(dungeon.fail_reason, "The brazier was destroyed", "the reason")
	check_eq(dungeon.title_text(), "Dungeon failed", "the HUD title")
	check(finished_with.is_empty(), "the arena changes back only after the outro")
	_step(Dungeon.OUTRO_TIME + 0.05)
	check_eq(finished_with, [false] as Array[bool], "finished(false)")
	check(not arena.in_dungeon_layout, "the clearing is back")


func test_the_warden_arrives_after_a_rune_with_the_boss_rules() -> void:
	_start(6, 2)
	_enter_room(Dungeon.Room.WARDEN)
	check(dungeon.warden == null, "not yet")
	_step(Dungeon.WARDEN_TELEGRAPH - 0.1)
	check(dungeon.warden == null, "the rune is still showing")
	_step(0.2)
	var w := dungeon.warden
	check(w != null and w is Boss, "the Warden is here")
	check_eq(w.boss_data.id, &"dungeon_warden", "the Dungeon Warden")
	check_eq(w.boss_data.max_hp, 120.0, "base HP 120")
	check_eq(w.boss_data.enrage_time, 60.0, "enrage at 60 s")
	check_near(w.max_hp, w.boss_data.max_hp_for(Dungeon.strength_wave(6), RunState.player_count), 0.001, "the boss HP rules (wave growth, party x(1 + 0.75 (n - 1)))")
	check_near(w.max_hp, w.boss_data.hp_at_wave(Dungeon.strength_wave(6)) * 1.75, 0.01, "x1.75 for two players")
	check(w.is_in_group(&"bosses") and w.is_boss(), "a boss to the rest of the game")
	check(not w.drops_loot, "no boss loot")
	check(w.director == dungeon, "its adds come through the dungeon")
	check(arena.get_bounds().has_point(Vector2(w.global_position.x, w.global_position.z)), "inside the room")
	var kinds: Array[int] = []
	for a in w.boss_data.abilities:
		kinds.append(a.kind)
	check_eq(kinds, [BossAbility.Kind.FROST_CIRCLES, BossAbility.Kind.SUMMON] as Array[int], "frost circles + call the fallen")
	check(Dungeon.WARDEN_ID != &"" and not Db.enemies.has(Dungeon.WARDEN_ID), "never in the random enemy pool")
	check(BossData.for_wave(10).id == &"lich_commander_morvain", "wave 10 still has Morvain, not the Warden")


func test_the_wardens_raise_dead_and_frost_circles_work_in_the_dungeon() -> void:
	_start(6, 2)
	_enter_room(Dungeon.Room.WARDEN)
	_step(Dungeon.WARDEN_TELEGRAPH + 0.1)
	var w := dungeon.warden
	var before := dungeon.alive_count()
	var raise: BossAbility = null
	var frost: BossAbility = null
	for a in w.boss_data.abilities:
		if a.kind == BossAbility.Kind.SUMMON:
			raise = a
		elif a.kind == BossAbility.Kind.FROST_CIRCLES:
			frost = a
	check(w._cast_summon(raise), "Call the Fallen cast")
	check_eq(dungeon.alive_count(), before + raise.count, "four adds came")
	for node in tree.get_nodes_in_group(&"enemies"):
		check(not (node as Enemy).drops_loot, "the adds pay nothing")
	check(w._cast_frost_circles(frost), "Frost Circles cast")
	check_eq(tree.get_nodes_in_group(EnemyHazard.GROUP).size(), heroes.size(), "one circle under each living hero")


func test_killing_the_warden_clears_the_dungeon_and_gives_the_arena_back() -> void:
	_start(6, 2)
	_enter_room(Dungeon.Room.WARDEN)
	_step(Dungeon.WARDEN_TELEGRAPH + 0.1)
	var bosses := RunState.bosses_killed
	var w := dungeon.warden
	w.kill(heroes[0])
	_step(DT)
	check_eq(dungeon.phase, Dungeon.Phase.OUTRO, "the outro")
	check(dungeon.success, "success")
	check_eq(dungeon.title_text(), "Dungeon cleared!", "the HUD title")
	check_eq(dungeon.alive_count(), 0, "the adds are swept")
	check_eq(RunState.bosses_killed, bosses, "the Warden is not a wave boss")
	check_eq(tree.get_nodes_in_group(&"loot_bags").size(), 0, "no boss items on the ground")
	check(finished_with.is_empty(), "not finished before the outro ends")
	_step(Dungeon.OUTRO_TIME + 0.05)
	check_eq(finished_with, [true] as Array[bool], "finished(true)")
	check_eq(dungeon.phase, Dungeon.Phase.DONE, "done")
	check(not arena.in_dungeon_layout and arena.spirit_healer != null, "the clearing and its Grave Tender are back")
	check_eq(arena.get_bounds().size, Arena.SIZE, "34 x 22 again")


func test_the_warden_enrages_at_60_seconds_not_90() -> void:
	_start(6, 1)
	_enter_room(Dungeon.Room.WARDEN)
	_step(Dungeon.WARDEN_TELEGRAPH + 0.1)
	var w := dungeon.warden
	w._age = 59.0
	w._physics_process(DT)
	check_eq(w.enrage_level, 0, "calm at 59 s")
	w._age = 60.0
	w._physics_process(DT)
	check_eq(w.enrage_level, 1, "enraged at 60 s")
	check(w.damage_mult > 1.0 and w.speed_mult > 1.0, "damage and speed up")


func test_the_smoke_safety_kills_a_warden_that_outlives_its_enrage() -> void:
	_start(6, 1)
	_enter_room(Dungeon.Room.WARDEN)
	dungeon.smoke_boss_timeout = true
	_step(Dungeon.WARDEN_TELEGRAPH + 0.1)
	var w := dungeon.warden
	w._age = 60.0 + Dungeon.SMOKE_BOSS_GRACE - 1.0
	_step(DT)
	check(not w.is_dead(), "not yet")
	w._age = 60.0 + Dungeon.SMOKE_BOSS_GRACE + 0.5
	_step(DT)
	check(w.is_dead(), "killed")
	_step(DT)
	check_eq(dungeon.phase, Dungeon.Phase.OUTRO, "the room ends")
	check(dungeon.success, "as a clear (the safety is only for runs that must end)")


func test_without_the_smoke_flag_the_warden_lives_on() -> void:
	_start(6, 1)
	_enter_room(Dungeon.Room.WARDEN)
	_step(Dungeon.WARDEN_TELEGRAPH + 0.1)
	dungeon.warden._age = 60.0 + Dungeon.SMOKE_BOSS_GRACE + 30.0
	_step(DT)
	check(not dungeon.warden.is_dead(), "a real run has no such safety")


func test_a_missing_warden_file_skips_the_room_instead_of_hanging() -> void:
	_start(6, 1)
	_enter_room(Dungeon.Room.CLEAR)
	Db.bosses.erase(Dungeon.WARDEN_ID)
	dungeon.warden_data = null
	dungeon._start_room(Dungeon.Room.WARDEN)
	_step(DT)
	check_eq(dungeon.phase, Dungeon.Phase.OUTRO, "cleared at once")


# --- Dungeon: failing ------------------------------------------------------------------------------

func test_everybody_down_fails_the_dungeon_and_the_party_gets_up() -> void:
	_start(6, 2)
	_enter_room(Dungeon.Room.CLEAR)
	_down(heroes[0])
	_step(DT)
	check_eq(dungeon.phase, Dungeon.Phase.ROOM, "one hero down: the dungeon goes on (teammates revive)")
	_down(heroes[1])
	_step(DT)
	check_eq(dungeon.phase, Dungeon.Phase.OUTRO, "everybody down: failed")
	check(not dungeon.success, "a failure")
	check_eq(dungeon.fail_reason, "The party has fallen", "the reason")
	_step(Dungeon.OUTRO_TIME + 0.05)
	check_eq(finished_with, [false] as Array[bool], "finished(false)")
	for h in heroes:
		check(not h.downed, "%s is back on its feet" % h.name)
		check_near(h.hp, roundf(h.max_hp() * Player.WAVE_START_REVIVE_HP_RATIO), 1.01, "at the wave-start ratio")
	check(not arena.in_dungeon_layout, "the clearing is back")


func test_a_hero_given_up_mid_dungeon_is_dropped_from_the_party() -> void:
	_start(6, 2)
	_enter_room(Dungeon.Room.CLEAR)
	var gone := heroes[1]
	gone.get_parent().remove_child(gone)
	gone.free()
	_step(DT)
	check_eq(dungeon.heroes.size(), 1, "the freed hero left the list")
	check_eq(dungeon.phase, Dungeon.Phase.ROOM, "the other one fights on")
	_down(heroes[0])
	_step(DT)
	check_eq(dungeon.phase, Dungeon.Phase.OUTRO, "and when it falls the dungeon is lost")


func test_with_every_hero_gone_the_dungeon_fails() -> void:
	_start(6, 1)
	_enter_room(Dungeon.Room.CLEAR)
	var gone := heroes[0]
	gone.get_parent().remove_child(gone)
	gone.free()
	_step(DT)
	check_eq(dungeon.phase, Dungeon.Phase.OUTRO, "nobody left: failed")
	_step(Dungeon.OUTRO_TIME + 0.05)
	check_eq(finished_with, [false] as Array[bool], "and over")


func test_a_solo_hero_going_down_fails_the_dungeon_not_the_run() -> void:
	_start(6, 1)
	_enter_room(Dungeon.Room.CLEAR)
	_down(heroes[0])
	_step(DT)
	check_eq(dungeon.phase, Dungeon.Phase.OUTRO, "failed")
	check(RunState.active, "the run itself goes on")


func test_the_failure_sweeps_the_room() -> void:
	_start(6, 2)
	_enter_room(Dungeon.Room.CLEAR)
	_step(2.5)
	check(dungeon.alive_count() > 0, "enemies about")
	_down(heroes[0])
	_down(heroes[1])
	_step(DT)
	check_eq(dungeon.alive_count(), 0, "swept")
	check_eq(dungeon.pending_count(), 0, "no group is left to hatch")


func test_finishing_ends_auras_without_the_wave_end_signal_and_places_the_heroes() -> void:
	_start(6, 2)
	_enter_room(Dungeon.Room.WARDEN)
	_step(Dungeon.WARDEN_TELEGRAPH + 0.1)
	heroes[0].global_position = Vector3(3, 0, 3)
	dungeon.warden.kill(heroes[0])
	_step(DT + Dungeon.OUTRO_TIME + 0.05)
	check_eq(waves_ended, 0, "wave_ended never fired (Artifacts grow once per wave end)")
	var spawns := arena.get_player_spawn_points(2)
	check_eq(heroes[0].global_position, spawns[0], "back on the clearing's spawn points")
	check_eq(heroes[1].global_position, spawns[1], "both of them")
	check(Arena.current == arena, "Arena.current")


func test_downed_heroes_are_revived_when_a_won_dungeon_ends() -> void:
	_start(6, 2)
	_enter_room(Dungeon.Room.WARDEN)
	_step(Dungeon.WARDEN_TELEGRAPH + 0.1)
	_down(heroes[1])
	dungeon.warden.kill(heroes[0])
	_step(DT + Dungeon.OUTRO_TIME + 0.05)
	check(not heroes[1].downed, "revived as at a wave start")


# --- Dungeon: bookkeeping ----------------------------------------------------------------------------

func test_the_dungeon_draws_its_own_rng_not_the_runs() -> void:
	_start()
	var run_before := RunState.rng.state
	var dungeon_before := RunState.dungeon_rng.state
	_step(Dungeon.INTRO_TIME + 0.5)  # room one begins, its first group is picked and telegraphed
	check(dungeon.pending_count() > 0, "a group is pending")
	check_eq(RunState.rng.state, run_before, "RunState.rng untouched until enemies are set up")
	check(RunState.dungeon_rng.state != dungeon_before, "the dungeon generator moved")


func test_the_status_line_follows_the_rooms() -> void:
	_start()
	check_eq(dungeon.title_text(), "Dungeon", "entering")
	check_eq(dungeon.task_text(), "Get ready", "get ready")
	_step(Dungeon.INTRO_TIME + 0.02)
	check_eq(dungeon.title_text(), "Dungeon – Room 1/4", "room 1")
	check_eq(dungeon.task_text(), "Kill enemies  0 / 25", "the kill count")
	check_near(dungeon.seconds_left(), -1.0, 0.001, "no clock in room 1")
	dungeon._start_room(Dungeon.Room.SURVIVE)
	check_eq(dungeon.title_text(), "Dungeon – Room 2/4", "room 2")
	check_eq(dungeon.task_text(), "Survive", "survive")
	check(dungeon.seconds_left() > 24.0, "with a clock")
	dungeon._start_room(Dungeon.Room.DEFEND)
	check_eq(dungeon.title_text(), "Dungeon – Room 3/4", "room 3")
	check(dungeon.task_text().begins_with("Defend the brazier  (100%)"), "defend, with the brazier's health")
	dungeon._start_room(Dungeon.Room.WARDEN)
	check_eq(dungeon.title_text(), "Dungeon – Room 4/4", "room 4")
	check_eq(dungeon.task_text(), "Defeat the Dungeon Warden", "the Warden")


func test_status_changed_is_emitted_when_the_text_changes() -> void:
	_start()
	var n := [0]
	dungeon.status_changed.connect(func() -> void: n[0] += 1)
	_step(Dungeon.INTRO_TIME + 0.02)
	var after_intro: int = n[0]
	check(after_intro > 0, "the room change")
	_step(1.2)  # the first group hatches
	var after_hatch: int = n[0]
	var e := tree.get_nodes_in_group(&"enemies")[0] as Enemy
	e.kill(heroes[0])
	_step(DT)
	check(n[0] > after_hatch, "a kill changes the task text")
	check_eq(dungeon.task_text(), "Kill enemies  1 / 25", "to 1 / 25")


func test_the_summary_line_names_rooms_and_times() -> void:
	_start(6, 1)
	_enter_room(Dungeon.Room.CLEAR)
	dungeon._room_done()
	var line := dungeon.summary_text()
	check(line.contains("failed on wave 6") and line.contains("1 / 4 rooms ("), line)
	var none := Dungeon.create(arena, 9)
	world.add_child(none)
	check_eq(none.summary_text(), "failed on wave 9: 0 / 4 rooms, 0 kills, 0.0 s", "no empty parentheses without rooms")
	none.free()


# --- Rewards -----------------------------------------------------------------------------------------

func _four_heroes() -> void:
	var classes: Array[StringName] = [&"warrior", &"mage", &"paladin", &"rogue"]
	for i in 4:
		_hero(i, classes[i], Vector3(float(i), 0.0, 0.0))


func _seed_for(hit: bool) -> int:
	for sd in range(1, 400):
		var r := RandomNumberGenerator.new()
		r.seed = sd
		if (r.randf() < DungeonRewards.SET_PIECE_CHANCE) == hit:
			return sd
	return 1


func test_a_won_dungeon_gives_every_hero_an_epic_they_can_use() -> void:
	_four_heroes()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var gold := RunState.gold
	var paid := DungeonRewards.grant_success(9, _slots(), rng)
	var items: Array = paid["items"]
	check_eq(items.size(), 4, "one Epic per hero")
	for i in items.size():
		var item: ItemInstance = items[i]
		check_eq(item.rarity, Items.Rarity.EPIC, "hero %d: an Epic" % i)
		check(item.can_be_used_by(heroes[i].class_data), "hero %d can use it" % i)
		check(item.looted and item.buy_price > 0, "a loot-quality, priced item")
	var extra: ItemInstance = paid["extra"]
	check_eq(RunState.team_loot.size(), 4 + (1 if extra != null else 0), "all of it waits for the Need / Greed / Pass roll")
	check_eq(paid["gold"], DungeonRewards.gold_for(9), "the gold")
	check_eq(RunState.gold, gold + int(paid["gold"]), "paid into the purse")


func test_the_gold_is_20_times_the_waves_average_enemy_gold() -> void:
	for w in [6, 9, 12, 15]:
		check_eq(DungeonRewards.gold_for(w), roundi(20.0 * LootGoblin.average_gold(w)), "wave %d" % w)
	check_eq(DungeonRewards.GOLD_MULT, 20, "20x")
	check(DungeonRewards.gold_for(15) > DungeonRewards.gold_for(6), "more at wave 15 than at wave 6")


func test_the_extra_tier_set_piece_comes_half_of_the_time() -> void:
	_four_heroes()
	check_eq(DungeonRewards.SET_PIECE_CHANCE, 0.5, "50%")
	check(not BlackMarket.set_piece_candidates(15, _slots()).is_empty(), "the team has set pieces at wave 15")
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(true)
	var piece := DungeonRewards.bonus_set_piece(15, _slots(), rng)
	check(piece != null, "a hit gives a piece")
	check(piece.set_id != &"" and piece.rarity == Items.Rarity.EPIC, "a tier-set Epic")
	var classes: Array[StringName] = []
	for h in heroes:
		classes.append(h.class_data.id)
	check(piece.class_restriction in classes, "for a class of the team")
	rng.seed = _seed_for(false)
	check(DungeonRewards.bonus_set_piece(15, _slots(), rng) == null, "a miss gives none")


func test_the_extra_piece_prefers_one_a_hero_is_missing() -> void:
	_four_heroes()
	var cands := BlackMarket.set_piece_candidates(15, _slots())
	var missing := 0
	for c in cands:
		if c["missing"]:
			missing += 1
	check(missing > 0, "something is missing at the start")
	var rng := RandomNumberGenerator.new()
	for sd in 30:
		rng.seed = _seed_for(true) + sd * 2
		var again := RandomNumberGenerator.new()
		again.seed = rng.seed
		if again.randf() >= 0.5:
			continue
		var piece := DungeonRewards.bonus_set_piece(15, _slots(), rng)
		check(piece != null, "a piece")
		var ok := false
		for c in cands:
			if c["missing"] and c["data"].id == piece.source_id:
				ok = true
		check(ok, "seed %d: the piece is one that is missing" % rng.seed)


func test_grant_success_with_a_hit_adds_the_piece_to_the_loot() -> void:
	_four_heroes()
	var rng := RandomNumberGenerator.new()
	# Find a seed where the chance draw after four Epics hits: just try a few.
	var got_extra := false
	var got_none := false
	for sd in range(1, 60):
		RunState.team_loot.clear()
		rng.seed = sd
		var paid := DungeonRewards.grant_success(15, _slots(), rng)
		if paid["extra"] != null:
			got_extra = true
			check_eq(RunState.team_loot.size(), 5, "four Epics and the piece")
			check(RunState.team_loot.has(paid["extra"]), "the piece is in the loot")
		else:
			got_none = true
			check_eq(RunState.team_loot.size(), 4, "four Epics")
	check(got_extra and got_none, "both outcomes occur")


func test_a_lost_dungeon_takes_half_the_purse_and_logs_it() -> void:
	RunState.gold = 101
	RunState.begin_spend_round()
	var spent_before := RunState.gold_spent
	var changes: Array[int] = []
	RunState.gold_changed.connect(func(_g: int, d: int) -> void: changes.append(d))
	check_eq(DungeonRewards.failure_loss(), 50, "half, rounded down")
	var lost := DungeonRewards.apply_failure()
	check_eq(lost, 50, "50 gold lost")
	check_eq(RunState.gold, 51, "the rest stays")
	check_eq(changes, [-50] as Array[int], "gold_changed fired")
	check_eq(RunState.spend_log.size(), 1, "the purse board has a line")
	check_eq(RunState.spend_log[0]["kind"], &"dungeon", "of its own kind")
	check_eq(RunState.spend_log[0]["label"], "Dungeon failed", "named")
	check_eq(RunState.spend_log[0]["slot"], -1, "the team's")
	check_eq(RunState.gold_spent, spent_before, "not counted as a purchase")


func test_a_lost_dungeon_with_an_empty_purse_loses_nothing() -> void:
	RunState.gold = 1
	RunState.begin_spend_round()
	check_eq(DungeonRewards.apply_failure(), 0, "half of one gold is nothing")
	check_eq(RunState.gold, 1, "unchanged")
	check(RunState.spend_log.is_empty(), "no log line")


# --- The brazier ----------------------------------------------------------------------------------------

func test_the_brazier_takes_damage_and_is_destroyed_once() -> void:
	var b := DungeonBrazier.create(100.0)
	world.add_child(b)
	var destroyed := [0]
	var damage := [0.0]
	b.destroyed.connect(func() -> void: destroyed[0] += 1)
	b.damaged.connect(func(a: float) -> void: damage[0] += a)
	check(b.is_alive() and b.is_in_group(DungeonBrazier.GROUP), "alive, in its group")
	b.take_damage(30.0)
	check_near(b.hp_ratio(), 0.7, 0.0001, "70%")
	check_near(damage[0], 30.0, 0.0001, "damaged() carries the amount")
	b.take_damage(0.0)
	b.take_damage(-5.0)
	check_near(b.hp, 70.0, 0.0001, "no healing by negative damage")
	b.take_damage(500.0)
	check(not b.is_alive() and b.hp == 0.0, "destroyed")
	b.take_damage(10.0)
	check_eq(destroyed[0], 1, "destroyed fires once")


func test_the_brazier_reach() -> void:
	var b := DungeonBrazier.create(100.0)
	world.add_child(b)
	check(b.reaches(Vector3(1.0, 0, 0), 0.45), "an enemy at its foot")
	check(not b.reaches(Vector3(3.0, 0, 0), 0.45), "one three metres away")
	check(b.reaches(Vector3(0, 0, -1.5), 0.45), "from the other side too")
