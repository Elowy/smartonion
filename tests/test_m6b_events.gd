extends TestCase
## M6b EVENTS: the three mid-wave events the EventSpawner builds – the Guarded Chest (guards on posts, x2
## HP, no affix; opened by a hero standing at it for 1.5 s once they are dead; a Rare+ item outside the drop
## cap + 10 x average gold), Defend the Totem (30 x grunt HP, lures enemies within 8 m, they bite it; 20 s =
## +15% damage for the heroes + 25 x average XP) and the Goblin Caravan (40 x grunt HP cart crossing the arena
## in ~25 s with 3 guards; killed = 40 x average gold + a Rare item, else "The caravan got away"), their
## banners and counters, the camera's event points and the bots' play (test_m6b_events_bots.gd).

## Records everything the game prints (stdout and stderr) while installed with OS.add_logger().
class PrintSpy extends Logger:
	var lines: Array[String] = []
	var _mutex := Mutex.new()

	func _log_message(message: String, _error: bool) -> void:
		_mutex.lock()
		lines.append(message)
		_mutex.unlock()

	func with_text(text: String) -> Array[String]:
		var out: Array[String] = []
		_mutex.lock()
		for l in lines:
			if text in l:
				out.append(l)
		_mutex.unlock()
		return out


const EFakes := preload("res://tests/enemies_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var director: WaveDirector
var spawner: EventSpawner
var main: Main
var announcements: Array[String] = []
var results: Array[Array] = []
var nodes: Array[Node] = []


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, 4242)
	tree.paused = false
	world = EFakes.make_world(tree)
	announcements.clear()
	results.clear()


func after_each() -> void:
	RunState.event_override = &""
	LootDrops.artifact_roll_probe = Callable()
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()
	if world != null:
		EFakes.free_world(tree, world)
		world = null
	director = null
	spawner = null
	tree.paused = false
	UiFakes.reset_players()
	RunState.start_run(1, 1)
	Enemy.invalidate_player_cache()


func _arena() -> Arena:
	return EFakes.arena_of(world)


## A WaveDirector on the test arena with an EventSpawner child; banners and results are recorded.
func _make_spawner() -> EventSpawner:
	director = WaveDirector.create(_arena())
	world.add_child(director)
	spawner = EventSpawner.create(director)
	director.add_child(spawner)
	spawner.announced.connect(func(text: String, _color: Color) -> void: announcements.append(text))
	spawner.event_finished.connect(func(kind: StringName, success: bool) -> void: results.append([kind, success]))
	return spawner


## The event objects, their guards and every enemy in the arena, in a fixed order.
func _movers() -> Array[Node]:
	var out: Array[Node] = []
	if spawner != null:
		if spawner.chest != null and is_instance_valid(spawner.chest):
			out.append(spawner.chest.guards)
			out.append(spawner.chest)
		if spawner.totem != null and is_instance_valid(spawner.totem):
			out.append(spawner.totem)
		if spawner.cart != null and is_instance_valid(spawner.cart):
			out.append(spawner.cart.guards)
	for e in tree.get_nodes_in_group(&"enemies"):
		out.append(e)
	return out


func _tick(seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		for n in _movers():
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				n._physics_process(DT)
		t += DT


func _hero(pos: Vector3) -> EFakes.FakePlayer:
	return EFakes.spawn_player(world, pos)


func _items_on_the_ground() -> Array[LootBag]:
	var out: Array[LootBag] = []
	for b in tree.get_nodes_in_group(&"loot_bags"):
		if b is LootBag and not b.is_queued_for_deletion():
			out.append(b)
	return out


func _gold_on_the_ground() -> int:
	var sum := 0
	for p in EFakes.live_children_of_type(world, Pickup):
		sum += (p as Pickup).gold
	return sum


func _xp_on_the_ground() -> int:
	var sum := 0
	for p in EFakes.live_children_of_type(world, Pickup):
		sum += (p as Pickup).xp
	return sum


func _grunt(wave: int) -> Enemy:
	var e := Enemy.create(Db.get_enemy(EventSpawner.GRUNT_ID), wave)
	nodes.append(e)
	return e


## The max HP an enemy of [param data] gets at [param wave] (a throw-away instance).
func _hp_of(data: EnemyData, wave: int) -> float:
	var e := Enemy.create(data, wave)
	var hp := e.max_hp
	e.free()
	return hp


# --- Shared numbers --------------------------------------------------------------------------

func test_event_names_and_the_short_forms_parse() -> void:
	check_eq(EventSpawner.parse_id("guarded_chest"), EventSpawner.GUARDED_CHEST, "the id")
	check_eq(EventSpawner.parse_id("chest"), EventSpawner.GUARDED_CHEST, "the short form")
	check_eq(EventSpawner.parse_id("totem"), EventSpawner.DEFEND_TOTEM, "totem")
	check_eq(EventSpawner.parse_id("Goblin_Caravan"), EventSpawner.GOBLIN_CARAVAN, "case does not matter")
	check_eq(EventSpawner.parse_id("caravan"), EventSpawner.GOBLIN_CARAVAN, "caravan")
	check_eq(EventSpawner.parse_id("tower"), &"", "an unknown name is none")
	var o := LaunchOptions.parse(PackedStringArray(["--event=totem"]))
	check_eq(o.event, EventSpawner.DEFEND_TOTEM, "--event takes the short form")
	check(o.unknown.is_empty(), "and it is not unknown")
	o = LaunchOptions.parse(PackedStringArray(["--event=tower"]))
	check_eq(o.event, &"", "a bad name sets nothing")
	check_eq(o.unknown.size(), 1, "and is reported")


func test_the_hp_yardstick_is_a_real_grunt() -> void:
	for players in [1, 3]:
		RunState.start_run(players, 4242)
		for wave in [4, 9, 16]:
			check_near(EventSpawner.grunt_hp(wave), _grunt(wave).max_hp, 0.0001,
					"grunt HP at wave %d with %d player(s)" % [wave, players])
			check_near(DefendTotem.hp_for(wave), 30.0 * _grunt(wave).max_hp, 0.0001, "the totem: 30 grunts")
			check_near(CaravanCart.hp_for(wave), 40.0 * _grunt(wave).max_hp, 0.0001, "the cart: 40 grunts")


func test_rewards_are_multiples_of_the_average_enemy() -> void:
	for wave in [4, 8, 14]:
		check_eq(GuardedChest.reward_gold(wave), roundi(10.0 * LootGoblin.average_gold(wave)), "chest gold, wave %d" % wave)
		check_eq(CaravanCart.reward_gold(wave), roundi(40.0 * LootGoblin.average_gold(wave)), "cart gold, wave %d" % wave)
		check_eq(DefendTotem.reward_xp(wave), roundi(25.0 * LootGoblin.average_xp(wave)), "totem XP, wave %d" % wave)
	check(GuardedChest.reward_gold(8) > 0 and DefendTotem.reward_xp(8) > 0, "and they are not zero")


# --- Guards ----------------------------------------------------------------------------------

func test_guards_hold_their_posts_until_a_hero_comes_close() -> void:
	_make_spawner()
	spawner.roll_wave(5)
	check(spawner.start_event(EventSpawner.GUARDED_CHEST), "the chest is built")
	var chest := spawner.chest
	var guards := chest.guards
	check_eq(guards.alive_count(), GuardedChest.GUARD_COUNT, "four guards")
	_tick(3.0)
	for i in guards.guards.size():
		var g := guards.guards[i]
		check(g.is_taunted() and g.taunt_target == guards.posts[i], "guard %d is on its own post" % i)
		check(EFakes.flat_distance(g.global_position, guards.posts[i].global_position) < 1.0,
				"and stands there (%.2f m off)" % EFakes.flat_distance(g.global_position, guards.posts[i].global_position))
	check(not guards.is_alerted, "nobody came: not alerted")
	# A hero far from every guard (the test heroes may stand outside the arena) changes nothing ...
	var hero := _hero(chest.global_position + Vector3(40.0, 0.0, 0.0))
	guards.scan()
	check(not guards.is_alerted, "a hero outside the aggro radius of every guard changes nothing")
	# ... one just inside the radius of a guard wakes the whole group.
	hero.global_position = guards.guards[0].global_position + Vector3(EventGuards.AGGRO_RADIUS - 1.0, 0.0, 0.0)
	guards.scan()
	check(guards.is_alerted, "a hero within the aggro radius of a guard alerts the group")
	for g in guards.guards:
		check(not g.is_taunted(), "every guard is free to hunt")


func test_a_hurt_guard_alerts_the_group() -> void:
	_make_spawner()
	spawner.roll_wave(5)
	spawner.start_event(EventSpawner.GUARDED_CHEST)
	var guards := spawner.chest.guards
	guards.scan()
	check(not guards.is_alerted, "calm")
	guards.guards[2].take_damage(0.5)
	guards.scan()
	check(guards.is_alerted, "a bolt from far away alerts the group")


# --- Guarded Chest ---------------------------------------------------------------------------

func test_the_spawner_builds_a_guarded_chest() -> void:
	_make_spawner()
	var hero := _hero(Vector3(-15.0, 0.0, 9.0))
	spawner.roll_wave(5)
	RunState.event_rng.seed = 99
	check(spawner.start_event(EventSpawner.GUARDED_CHEST), "built")
	var chest := spawner.chest
	check(chest != null and chest.is_in_group(EventSpawner.GROUP), "the chest is an event object")
	check_eq(chest.get_parent(), _arena().entities, "under the arena's entities")
	check(chest.is_locked(), "locked while its guards live")
	check(EFakes.flat_distance(chest.global_position, hero.global_position) >= EventSpawner.CHEST_HERO_DISTANCE - 0.01,
			"away from the heroes: they have to walk")
	var eligible := WaveDirector.eligible_enemies(5)
	var count := 0
	for g in chest.guards.guards:
		count += 1
		check(g.data in eligible, "an enemy type of the wave (%s)" % g.data.id)
		check_near(g.max_hp, 2.0 * _hp_of(g.data, 5), 0.0001, "x2 HP")
		check_eq(g.hp, g.max_hp, "at full health")
		check_eq(g.elite_affix, &"", "no affix")
		check(g.is_in_group(&"enemies"), "an ordinary enemy")
		check(EFakes.flat_distance(g.global_position, chest.global_position) <= GuardedChest.POST_RADIUS + 0.2,
				"around the chest")
	check_eq(count, 4, "four guards")
	check_eq(RunState.events_spawned, 1, "counted")
	check_eq(announcements, [EventSpawner.CHEST_TEXT] as Array[String], "announced")
	check_eq(director.spawned_this_wave, 4, "the guards count as spawned this wave")


func test_the_chest_opens_after_the_guards_when_a_hero_stands_at_it() -> void:
	_make_spawner()
	var hero := _hero(Vector3(-15.0, 0.0, 9.0))
	spawner.roll_wave(5)
	spawner.start_event(EventSpawner.GUARDED_CHEST)
	var chest := spawner.chest
	hero.global_position = chest.global_position + Vector3(0.5, 0.0, 0.0)
	_tick(2.0)
	check(chest.is_locked() and chest.progress == 0.0, "a hero at the locked chest does nothing")
	check(not chest.is_open(), "still shut")
	for g in chest.guards.alive():
		g.kill()
	_tick(DT * 2.0)
	check(chest.is_ready(), "the guards are dead: ready")
	_tick(GuardedChest.OPEN_TIME - 0.3)
	check(chest.is_ready() and chest.progress > 1.0, "not yet at %.2f s" % chest.progress)
	_tick(0.4)
	check(chest.is_open(), "1.5 s at the chest: open")
	check_eq(chest.opener, hero, "the hero who stood there")
	check_eq(RunState.events_completed, 1, "a won event")
	check_eq(spawner.result, &"completed", "completed")
	check_eq(results, [[EventSpawner.GUARDED_CHEST, true]] as Array[Array], "event_finished")
	check(EventSpawner.CHEST_OPENED_TEXT in announcements, "banner")


func test_the_chest_progress_drains_while_nobody_is_there_and_ignores_the_downed() -> void:
	var chest := GuardedChest.create(5)
	_arena().entities.add_child(chest)
	chest.global_position = Vector3(2.0, 0.0, 2.0)
	var hero := _hero(Vector3(30.0, 0.0, 0.0))
	chest._physics_process(DT)
	check(chest.is_ready() and chest.progress == 0.0, "no guards: ready at once, nobody there")
	hero.global_position = chest.global_position + Vector3(GuardedChest.OPEN_RADIUS - 0.1, 0.0, 0.0)
	for i in 60:
		chest._physics_process(DT)
	check_near(chest.progress, 1.0, 0.03, "one second at the chest")
	hero.global_position = Vector3(30.0, 0.0, 0.0)
	for i in 30:
		chest._physics_process(DT)
	check_near(chest.progress, 0.5, 0.05, "half a second away: it drains")
	hero.global_position = chest.global_position + Vector3(GuardedChest.OPEN_RADIUS + 0.2, 0.0, 0.0)
	for i in 60:
		chest._physics_process(DT)
	check(chest.progress < 0.5 and not chest.is_open(), "just outside the radius does not count")
	hero.global_position = chest.global_position
	hero.downed = true
	Enemy.invalidate_player_cache()
	for i in 200:
		chest._physics_process(DT)
	check(not chest.is_open(), "a downed hero cannot open it")


func test_opening_the_chest_pays_an_item_and_gold_outside_the_drop_limit() -> void:
	_make_spawner()
	_hero(Vector3(-15.0, 0.0, 9.0))
	spawner.roll_wave(6)
	RunState.set_wave(6)
	spawner.start_event(EventSpawner.GUARDED_CHEST)
	var chest := spawner.chest
	RunState.loot_drops_this_wave = LootDrops.max_drops_per_wave()
	var artifact_rolls := [0]
	LootDrops.artifact_roll_probe = func(_s: Variant, _e: Variant, _k: Variant) -> LootBag:
		artifact_rolls[0] += 1
		return null
	var before := _gold_on_the_ground()
	chest.open(null)
	var bags := _items_on_the_ground()
	check_eq(bags.size(), 1, "one item bag")
	if bags.size() == 1:
		check(bags[0].item.rarity >= Items.Rarity.RARE, "Rare or better (%d)" % bags[0].item.rarity)
		check(bags[0].item.looted, "a looted item")
	check_eq(_gold_on_the_ground() - before, GuardedChest.reward_gold(6), "10 x the average enemy gold")
	check_eq(RunState.loot_drops_this_wave, LootDrops.max_drops_per_wave(), "not counted against the drop limit")
	check_eq(artifact_rolls[0], 0, "no Artifact roll")
	chest.open(null)
	check_eq(_items_on_the_ground().size(), 1, "it pays once")
	check_eq(RunState.events_completed, 1, "and counts once")


func test_the_chest_item_is_rare_or_better_every_time() -> void:
	RunState.set_wave(7)
	for i in 40:
		var bag := LootDrops.drop_event_item(ItemGenerator.Source.ELITE, Vector3.ZERO)
		check(bag != null and bag.item.rarity >= Items.Rarity.RARE, "roll %d" % i)
		if bag != null:
			bag.collect_to_bank()
	RunState.take_team_loot()
	for i in 20:
		var bag := LootDrops.drop_event_item(ItemGenerator.Source.LOOT, Vector3.ZERO, null, Items.Rarity.RARE)
		check(bag != null and bag.item.rarity == Items.Rarity.RARE, "forced Rare, roll %d" % i)
		if bag != null:
			bag.collect_to_bank()
	RunState.take_team_loot()


func test_an_event_item_without_an_arena_goes_to_the_team_loot() -> void:
	EFakes.free_world(tree, world)
	world = null
	RunState.take_team_loot()
	RunState.set_wave(5)
	var bag := LootDrops.drop_event_item(ItemGenerator.Source.ELITE, Vector3.ZERO)
	check(bag == null, "no bag without a world")
	check_eq(RunState.team_loot.size(), 1, "the item is never lost")
	RunState.take_team_loot()


func test_an_unopened_chest_is_a_failed_event_at_the_wave_end() -> void:
	_make_spawner()
	_hero(Vector3(-15.0, 0.0, 9.0))
	spawner.roll_wave(5)
	spawner.start_event(EventSpawner.GUARDED_CHEST)
	var chest := spawner.chest
	var guards: Array[Enemy] = []
	guards.append_array(chest.guards.guards)
	director.time_left = 0.0
	director.stop()  # what the director does at the wave end
	check(chest.is_queued_for_deletion(), "stop() frees the chest with the wave")
	for g in guards:
		check(g.is_queued_for_deletion(), "and its guards")
	spawner.end_wave()
	check_eq(spawner.result, &"failed", "the chest stayed shut")
	check_eq(RunState.events_completed, 0, "nothing won")


func test_the_wave_end_settles_an_open_chest_as_failed() -> void:
	_make_spawner()
	spawner.roll_wave(5)
	spawner.start_event(EventSpawner.GUARDED_CHEST)
	spawner.end_wave()
	check_eq(spawner.result, &"failed", "the chest stayed shut")
	check_eq(results, [[EventSpawner.GUARDED_CHEST, false]] as Array[Array], "event_finished(false)")
	check_eq(RunState.events_completed, 0, "not completed")
	check(spawner.chest == null, "the spawner forgot it")
	spawner.end_wave()
	check_eq(results.size(), 1, "settled once")


# --- Defend the Totem ------------------------------------------------------------------------

func test_the_spawner_builds_a_totem_near_the_heroes() -> void:
	_make_spawner()
	_hero(Vector3(-6.0, 0.0, 3.0))
	spawner.roll_wave(6)
	check(spawner.start_event(EventSpawner.DEFEND_TOTEM), "built")
	var totem := spawner.totem
	check(totem != null and totem.is_in_group(EventSpawner.GROUP), "an event object")
	check_near(totem.max_hp, 30.0 * _grunt(6).max_hp, 0.0001, "30 x grunt HP")
	check_eq(totem.hp, totem.max_hp, "full")
	check_near(totem.time_left, 20.0, 0.0001, "20 s to hold")
	check(totem.is_active(), "active")
	check_eq(announcements, [EventSpawner.TOTEM_TEXT] as Array[String], "announced")
	check_eq(RunState.events_spawned, 1, "counted")
	check(EFakes.flat_distance(totem.global_position, Vector3(-6.0, 0.0, 3.0)) >= EventSpawner.TOTEM_HERO_DISTANCE - 0.01,
			"not on top of a hero")


func test_the_totem_lures_enemies_within_8_m_only() -> void:
	var totem := DefendTotem.create(5)
	_arena().entities.add_child(totem)
	totem.global_position = Vector3(0.0, 0.0, 0.0)
	var data := EFakes.enemy_data()
	var near := EFakes.spawn_enemy(world, data, Vector3(7.5, 0.0, 0.0), 5)
	var far := EFakes.spawn_enemy(world, data, Vector3(8.6, 0.0, 0.0), 5)
	var pet := Node3D.new()
	_arena().entities.add_child(pet)
	var held := EFakes.spawn_enemy(world, data, Vector3(0.0, 0.0, 6.0), 5)
	held.apply_taunt(pet, 5.0)
	var boss_data := EFakes.enemy_data()
	boss_data.is_boss = true
	var boss := EFakes.spawn_enemy(world, boss_data, Vector3(0.0, 0.0, -5.0), 5)
	var goblin := LootGoblin.create(LootGoblin.goblin_data(), 5)
	_arena().entities.add_child(goblin)
	goblin.global_position = Vector3(4.0, 0.0, 4.0)
	check_eq(totem.lure(), 1, "exactly one enemy was lured")
	check(near.is_taunted() and near.taunt_target == totem, "the enemy within 8 m goes for the totem")
	check(not far.is_taunted(), "8.6 m away: left alone")
	check_eq(held.taunt_target, pet, "an enemy taunted onto something alive keeps it")
	check(not boss.is_taunted(), "bosses are not lured")
	check(not goblin.is_taunted(), "the goblin ignores taunts anyway")
	pet.queue_free()


func test_a_lured_enemy_walks_to_the_totem_and_bites_it() -> void:
	_make_spawner()
	spawner.roll_wave(5)
	spawner.start_event(EventSpawner.DEFEND_TOTEM)
	var totem := spawner.totem
	totem.global_position = Vector3(0.0, 0.0, 0.0)
	var data := EFakes.enemy_data()
	data.contact_damage = 3.0
	var e := EFakes.spawn_enemy(world, data, Vector3(6.0, 0.0, 0.0), 5)
	var hero := _hero(Vector3(7.0, 0.0, 0.0))
	hero.global_position = Vector3(7.0, 0.0, 8.0)  # a hero in reach of the enemy's eyes, not touching
	_tick(4.0)
	check(totem.hp < totem.max_hp, "the enemy hurt the totem")
	check(totem.bites >= 1, "by biting")
	check(EFakes.flat_distance(e.global_position, totem.global_position) < 1.5, "at the totem")
	check_eq(hero.fake_hits.size(), 0, "and not the hero")
	var per_bite := e.contact_damage * e.damage_mult
	check_near(totem.damage_taken, per_bite * float(totem.bites), 0.0001, "each bite is the enemy's contact damage")
	var bites := totem.bites
	_tick(0.5)
	check(totem.bites - bites <= 1, "one bite per contact cooldown (%d in half a second)" % (totem.bites - bites))


func test_bites_follow_the_enemies_contact_rules() -> void:
	var totem := DefendTotem.create(5)
	_arena().entities.add_child(totem)
	totem.global_position = Vector3.ZERO
	var data := EFakes.enemy_data()
	data.contact_damage = 3.0
	var e := EFakes.spawn_enemy(world, data, Vector3(0.6, 0.0, 0.0), 5)
	e.damage_mult = 2.0
	e.apply_stun(1.0)
	check_eq(totem.bite(), 0.0, "a stunned enemy does not bite")
	e.stun_left = 0.0
	e.apply_fear(1.0, Vector3(5, 0, 0))
	check_eq(totem.bite(), 0.0, "neither does a feared one")
	e.fear_left = 0.0
	var expected := e.contact_damage * 2.0
	check_near(totem.bite(), expected, 0.0001, "an elite's damage multiplier counts")
	check(e.contact_cooldown_left > 0.0, "and starts the cooldown")
	check_eq(totem.bite(), 0.0, "no second bite while it cools down")
	var peaceful := EFakes.spawn_enemy(world, data, Vector3(-0.5, 0.0, 0.0), 5)
	var goblin := LootGoblin.create(LootGoblin.goblin_data(), 5)
	_arena().entities.add_child(goblin)
	goblin.global_position = Vector3(0.0, 0.0, 0.5)
	peaceful.contact_cooldown_left = 5.0
	check_eq(totem.bite(), 0.0, "an enemy on cooldown and the harmless goblin do not bite")


func test_the_totem_falls_at_zero_hp_and_pays_nothing() -> void:
	_make_spawner()
	spawner.roll_wave(5)
	spawner.start_event(EventSpawner.DEFEND_TOTEM)
	var totem := spawner.totem
	var xp_before := _xp_on_the_ground()
	totem.take_damage(totem.max_hp * 0.4)
	check(totem.is_active() and totem.hp_ratio() > 0.55 and totem.hp_ratio() < 0.65, "hurt but standing")
	totem.take_damage(totem.max_hp)
	check(totem.state == DefendTotem.State.FALLEN, "fallen")
	check(totem.is_queued_for_deletion(), "and gone")
	check_eq(spawner.result, &"failed", "a failed event")
	check_eq(results, [[EventSpawner.DEFEND_TOTEM, false]] as Array[Array], "event_finished(false)")
	check(EventSpawner.TOTEM_FELL_TEXT in announcements, "banner")
	check_eq(RunState.events_completed, 0, "nothing won")
	check_eq(_xp_on_the_ground(), xp_before, "no XP")
	check(not spawner._buff_on, "and no buff")
	totem.take_damage(5.0)
	check_eq(results.size(), 1, "it falls once")


func test_a_totem_that_lasts_20_s_pays_xp_and_the_team_buff() -> void:
	_run_with_bots(2)
	var sp := main.event_spawner
	sp.announced.connect(func(text: String, _color: Color) -> void: announcements.append(text))
	RunState.event_override = EventSpawner.DEFEND_TOTEM
	main.start_wave(6)
	check(sp.start_event(EventSpawner.DEFEND_TOTEM), "built")
	var totem := sp.totem
	var heroes: Array[Player] = []
	for slot in PlayerManager.get_slots():
		heroes.append(slot.player as Player)
	for h in heroes:
		check_near(h.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, 0.0001, "no buff yet")
	# Nothing around: strip the wave's enemies so the totem is left alone.
	for e in tree.get_nodes_in_group(&"enemies"):
		(e as Enemy).despawn()
	var xp_before := _xp_in(main.arena.entities)
	for i in int(DefendTotem.SURVIVE_TIME / DT) + 2:
		totem._physics_process(DT)
	check(totem.state == DefendTotem.State.HELD, "held after 20 s")
	check_eq(RunState.events_completed, 1, "a won event")
	check_eq(sp.result, &"completed", "completed")
	for h in heroes:
		check_near(h.bonuses.damage_mult(null, &"physical", &"weapon"), 1.15, 0.0001, "+15% damage for every hero")
	check_eq(_xp_in(main.arena.entities) - xp_before, DefendTotem.reward_xp(6), "25 x the average enemy XP")
	check(EventSpawner.totem_held_text() in announcements, "banner")
	check_eq(EventSpawner.totem_held_text(), "The totem holds!  +15% damage", "its words")
	var calm := totem.damage_taken
	totem.take_damage(100.0)
	check_eq(totem.damage_taken, calm, "a held totem takes no more damage")
	sp.end_wave()
	for h in heroes:
		check_near(h.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, 0.0001, "the buff ends with the wave")


func test_the_buff_is_gone_when_the_next_wave_starts_too() -> void:
	_run_with_bots(1)
	var sp := main.event_spawner
	check_eq(sp.apply_team_buff(), 1, "one hero buffed")
	var h := PlayerManager.get_slots()[0].player as Player
	check_near(h.bonuses.damage_mult(null, &"physical", &"weapon"), 1.15, 0.0001, "buffed")
	sp.roll_wave(8)
	check_near(h.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, 0.0001, "a new wave starts clean")


func _xp_in(root: Node) -> int:
	var sum := 0
	for p in root.get_children():
		if p is Pickup and not p.is_queued_for_deletion():
			sum += (p as Pickup).xp
	return sum


func _run_with_bots(count: int) -> void:
	main = Main.create(LaunchOptions.new())
	tree.root.add_child(main)
	for i in count:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)
	main.start_run()


# --- Goblin Caravan --------------------------------------------------------------------------

func test_the_cart_is_a_heavy_harmless_enemy() -> void:
	var cart := CaravanCart.create_route(6, Vector3(-15, 0, 0), Vector3(15, 0, 0))
	_arena().entities.add_child(cart)
	check_near(cart.max_hp, 40.0 * _grunt(6).max_hp, 0.0001, "40 x grunt HP")
	check(cart.is_in_group(&"enemies") and cart.is_in_group(EventSpawner.GROUP), "an enemy and an event object")
	check(not cart.deals_contact_damage(), "never hurts")
	check(not cart.is_boss() and not cart.is_elite(), "no boss, no elite")
	var hero := _hero(Vector3(-14.5, 0.0, 0.0))
	for i in 120:
		cart._physics_process(DT)
	check_eq(hero.fake_hits.size(), 0, "a hero beside it takes no damage")
	cart.apply_taunt(hero, 5.0)
	check(not cart.is_taunted(), "taunt does nothing")
	cart.apply_fear(5.0, Vector3.ZERO)
	check(not cart.is_feared(), "neither does fear")
	cart.take_damage(1.0, false, null, Vector3(50.0, 0.0, 0.0))
	check(cart.knockback_velocity == Vector3.ZERO, "knockback does not move it")
	cart.apply_stun(2.0)
	check(not cart.is_stunned(), "too heavy to stun")
	cart.apply_slow(50.0, 2.0)
	check(cart.is_slowed(), "but a slow holds it back")
	check(cart.model is CartModel, "the cart's own model")


func test_the_spawner_builds_a_caravan_with_three_guards() -> void:
	_make_spawner()
	_hero(Vector3(0.0, 0.0, 0.0))
	spawner.roll_wave(6)
	check(spawner.start_event(EventSpawner.GOBLIN_CARAVAN), "built")
	var cart := spawner.cart
	var b := _arena().get_bounds()
	check(cart != null and cart.is_in_group(EventSpawner.GROUP), "an event object")
	check_near(absf(cart.route_from.x), b.end.x - CaravanCart.EDGE_MARGIN, 0.001, "starts at an edge")
	check_near(absf(cart.route_to.x), b.end.x - CaravanCart.EDGE_MARGIN, 0.001, "ends at the other edge")
	check(signf(cart.route_from.x) != signf(cart.route_to.x), "on the other side")
	check_eq(cart.route_from.z, cart.route_to.z, "in a straight lane")
	check(cart.route_from.z >= b.position.y + EventSpawner.LANE_MARGIN - 0.001
			and cart.route_from.z <= b.end.y - EventSpawner.LANE_MARGIN + 0.001, "inside the arena's lanes")
	check_near(cart.cross_time, 25.0, 0.0001, "25 s")
	check_near(cart.move_speed, cart.route_length() / 25.0, 0.0001, "so many metres a second")
	check_eq(cart.guards.guards.size(), 3, "three guards")
	for g in cart.guards.guards:
		check_near(g.max_hp, _hp_of(g.data, 6), 0.0001, "normal HP (only the chest's guards are tougher)")
		check_eq(g.elite_affix, &"", "no affix")
	check_eq(announcements, [EventSpawner.CARAVAN_TEXT] as Array[String], "announced")
	check_eq(RunState.events_spawned, 1, "counted")
	check_eq(director.spawned_this_wave, 3, "the guards count as spawned this wave")


func test_the_crossing_is_shortened_when_the_wave_would_end_first() -> void:
	_make_spawner()
	director.start_wave(4)
	check_near(spawner._cross_time(), 25.0, 0.0001, "plenty of wave left")
	director.time_left = 20.0
	check_near(spawner._cross_time(), 18.0, 0.0001, "ends 2 s before the wave")
	director.time_left = 10.0
	check_near(spawner._cross_time(), CaravanCart.MIN_CROSS_TIME, 0.0001, "never faster than the minimum")


func test_the_cart_crosses_the_arena_and_gets_away() -> void:
	_make_spawner()
	spawner.roll_wave(6)
	spawner.start_event(EventSpawner.GOBLIN_CARAVAN)
	var cart := spawner.cart
	var start := cart.global_position
	_tick(12.5)
	var half := EFakes.flat_distance(start, cart.global_position)
	check_near(half, cart.route_length() * 0.5, 1.2, "half way after half the time (%.1f of %.1f m)" % [half, cart.route_length()])
	check(not cart.has_escaped(), "still rolling")
	_tick(13.5)
	check(cart.has_escaped(), "it reached the far edge")
	check(cart.is_queued_for_deletion(), "and rolled out of the arena")
	check_eq(spawner.result, &"failed", "a failed event")
	check_eq(results, [[EventSpawner.GOBLIN_CARAVAN, false]] as Array[Array], "event_finished(false)")
	check(EventSpawner.CARAVAN_ESCAPED_TEXT in announcements, "The caravan got away")
	check_eq(EventSpawner.CARAVAN_ESCAPED_TEXT, "The caravan got away", "the GDD's words")
	check_eq(RunState.events_completed, 0, "nothing won")
	check_eq(_items_on_the_ground().size(), 0, "no loot")


func test_a_killed_cart_pays_gold_and_a_rare_item() -> void:
	_make_spawner()
	_hero(Vector3(0.0, 0.0, 0.0))
	spawner.roll_wave(7)
	RunState.set_wave(7)
	spawner.start_event(EventSpawner.GOBLIN_CARAVAN)
	var cart := spawner.cart
	RunState.loot_drops_this_wave = LootDrops.max_drops_per_wave()
	var artifact_rolls := [0]
	LootDrops.artifact_roll_probe = func(_s: Variant, _e: Variant, _k: Variant) -> LootBag:
		artifact_rolls[0] += 1
		return null
	var kills := RunState.kills
	var before := _gold_on_the_ground()
	cart.take_damage(cart.max_hp * 2.0)
	check(cart.is_dead(), "dead")
	check_eq(_gold_on_the_ground() - before, CaravanCart.reward_gold(7), "40 x the average enemy gold")
	var bags := _items_on_the_ground()
	check_eq(bags.size(), 1, "one item")
	if bags.size() == 1:
		check_eq(bags[0].item.rarity, Items.Rarity.RARE, "Rare")
	check_eq(RunState.loot_drops_this_wave, LootDrops.max_drops_per_wave(), "not counted against the drop limit")
	check_eq(artifact_rolls[0], 0, "no Artifact roll and no normal drop roll")
	check_eq(RunState.kills, kills + 1, "it counts as a kill")
	check_eq(RunState.events_completed, 1, "a won event")
	check_eq(spawner.result, &"completed", "completed")
	check_eq(results, [[EventSpawner.GOBLIN_CARAVAN, true]] as Array[Array], "event_finished(true)")
	check(EventSpawner.CARAVAN_PLUNDERED_TEXT in announcements, "banner")


func test_hitting_the_cart_alerts_its_escort() -> void:
	_make_spawner()
	spawner.roll_wave(6)
	spawner.start_event(EventSpawner.GOBLIN_CARAVAN)
	var cart := spawner.cart
	cart.guards.scan()
	check(not cart.guards.is_alerted, "calm")
	for g in cart.guards.guards:
		check(g.is_taunted(), "the escort follows its posts")
	cart.take_damage(1.0)
	check(cart.guards.is_alerted, "a hit on the cart wakes the escort")


func test_the_escort_walks_with_the_cart() -> void:
	_make_spawner()
	spawner.roll_wave(6)
	spawner.start_event(EventSpawner.GOBLIN_CARAVAN)
	var cart := spawner.cart
	_tick(8.0)
	check(not cart.guards.is_alerted, "nobody came")
	var moved := EFakes.flat_distance(cart.route_from, cart.global_position)
	check(moved > 6.0, "the cart rolled %.1f m" % moved)
	for g in cart.guards.guards:
		check(EFakes.flat_distance(g.global_position, cart.global_position) < 6.5,
				"the guard is still with it (%.1f m)" % EFakes.flat_distance(g.global_position, cart.global_position))


func test_the_cart_model_rolls_its_wheels() -> void:
	var cart := CaravanCart.create_route(5, Vector3(-15, 0, 0), Vector3(15, 0, 0))
	_arena().entities.add_child(cart)
	var model := cart.model as CartModel
	check(model != null and model.head_height > 1.0, "a cart model")
	model.set_moving(1.0)
	var wheel := model.get_node(^"Pivot/WheelL") as Node3D
	check(wheel != null, "has wheels")
	for i in 30:
		model._process(DT)
	check(absf(wheel.rotation.x) > 0.5, "the wheels roll while it moves (%.2f rad)" % wheel.rotation.x)
	model.flash_hit()
	check(Mats.overlay_amount(model.get_node(^"Pivot/Body") as GeometryInstance3D) > 0.0, "and it flashes when hit")


# --- Every event: stop() and determinism -------------------------------------------------------

func test_stop_frees_every_event_object_and_the_guards() -> void:
	for id in EventSpawner.EVENT_IDS:
		_make_spawner()
		director.start_wave(5)
		spawner.start_event(id)
		var objects: Array[Node] = []
		for n in tree.get_nodes_in_group(EventSpawner.GROUP):
			objects.append(n)
		check(not objects.is_empty(), "%s: event objects exist" % id)
		var guards: Array[Enemy] = []
		if spawner.chest != null:
			guards.append_array(spawner.chest.guards.guards)
		if spawner.cart != null:
			guards.append_array(spawner.cart.guards.guards)
		director.stop()
		for n in objects:
			check(not is_instance_valid(n) or n.is_queued_for_deletion(), "%s: %s is freed" % [id, n.name])
		for g in guards:
			check(not is_instance_valid(g) or g.is_queued_for_deletion() or g.is_dead(), "%s: the guards are freed" % id)
		spawner.end_wave()
		EFakes.free_world(tree, world)
		world = EFakes.make_world(tree)


func test_the_same_event_rng_builds_the_same_event() -> void:
	var picks: Array[Array] = []
	for run in 2:
		RunState.start_run(1, 777)
		var w := EFakes.make_world(tree)
		world = w
		_make_spawner()
		_hero(Vector3(-15.0, 0.0, 9.0))
		spawner.roll_wave(8)
		spawner.start_event(EventSpawner.GUARDED_CHEST)
		var ids: Array = []
		for g in spawner.chest.guards.guards:
			ids.append(g.data.id)
		picks.append([spawner.chest.global_position, ids])
		spawner.end_wave()
		EFakes.free_world(tree, world)
		world = null
		director = null
		spawner = null
	check_eq(picks[0][0], picks[1][0], "the same spot")
	check_eq(picks[0][1], picks[1][1], "the same guards")


func test_the_totem_is_built_from_the_event_rng_alone() -> void:
	# Everything the spawner chooses itself comes from the event rng (a chest's and a cart's guards then go
	# through Enemy.setup, which draws from the gameplay rng like every enemy; a totem has none).
	_make_spawner()
	spawner.roll_wave(5)
	var event_state := RunState.event_rng.state
	var gameplay := RunState.rng.state
	spawner.start_event(EventSpawner.DEFEND_TOTEM)
	check(RunState.event_rng.state != event_state, "choosing a spot draws from the event rng")
	check_eq(RunState.rng.state, gameplay, "a totem draws nothing from the gameplay rng")
	spawner.end_wave()
	check_eq(RunState.rng.state, gameplay, "nor does settling it")


func test_guards_and_the_gold_burst_stay_inside_their_numbers() -> void:
	# The guards' ring is clamped into the arena (a chest in a corner), the burst pays the whole amounts.
	var chest := GuardedChest.create(5)
	_arena().entities.add_child(chest)
	chest.global_position = Vector3(-16.0, 0.0, -10.0)
	var datas: Array[EnemyData] = [EFakes.enemy_data(), EFakes.enemy_data(), EFakes.enemy_data(), EFakes.enemy_data()]
	var guards := chest.guards.spawn_guards(datas, 5, GuardedChest.post_offsets(4), 2.0, _arena().entities)
	check_eq(guards.size(), 4, "four guards")
	var b := _arena().get_bounds()
	for g in guards:
		check(b.has_point(Vector2(g.global_position.x, g.global_position.z)), "inside the arena: %s" % g.global_position)
	for off in GuardedChest.post_offsets(4):
		check_near(off.length(), GuardedChest.POST_RADIUS, 0.0001, "the unclamped posts lie on the ring")
	var pickups := EventFx.burst(_arena().entities, Vector3.ZERO, 10, 3, 8, 1.0)
	var gold := 0
	var xp := 0
	for p in pickups:
		gold += p.gold
		xp += p.xp
	check_eq(gold, 10, "all the gold is paid")
	check_eq(xp, 3, "all the XP is paid")
	check_eq(pickups.size(), 8, "in the piles that have something in them")
	check(EventFx.burst(null, Vector3.ZERO, 10, 3).is_empty(), "no parent, no burst")


func test_the_escort_stands_behind_the_cart_whichever_way_it_rolls() -> void:
	for sign_x in [-1.0, 1.0]:
		var dir := Vector3(sign_x, 0.0, 0.0)
		var offsets := CaravanCart.escort_offsets(3, dir)
		check_eq(offsets.size(), 3, "three posts")
		for o in offsets:
			check(o.dot(dir) < -2.0, "behind the cart (%s for dir %s)" % [o, dir])
		check(offsets[0].z * offsets[1].z < 0.0, "two of them on either side")


func test_a_run_with_a_forced_event_builds_it_and_settles_it_at_the_wave_end() -> void:
	_run_with_bots(2)
	var sp := main.event_spawner
	RunState.event_override = EventSpawner.GUARDED_CHEST
	main.start_wave(5)
	check(sp.pending_time() > 0.0, "an event is pending")
	var t := sp.pending_time()
	main.wave_director.time_left = main.wave_director.duration - t - 0.01
	for i in 3:
		sp._physics_process(DT)
	check(sp.chest != null and is_instance_valid(sp.chest), "the chest exists")
	check_eq(RunState.events_spawned, 1, "counted")
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	check_eq(sp.result, &"failed", "nobody opened it before the wave ended")
	check_eq(RunState.events_completed, 0, "not completed")


# --- The log lines -----------------------------------------------------------------------------

## The spy sees what the game prints: the base of the "nothing is printed" checks below.
func test_the_print_spy_sees_what_is_printed() -> void:
	var spy := PrintSpy.new()
	OS.add_logger(spy)
	print("PRINT_SPY_SELF_CHECK")
	OS.remove_logger(spy)
	check_eq(spy.with_text("PRINT_SPY_SELF_CHECK").size(), 1, "a print reaches the logger")


func test_the_spawner_logs_through_its_signal_and_prints_nothing() -> void:
	_make_spawner()
	_hero(Vector3.ZERO)
	var lines: Array[String] = []
	spawner.logged.connect(func(text: String) -> void: lines.append(text))
	var spy := PrintSpy.new()
	OS.add_logger(spy)
	spawner.roll_wave(5)
	check(spawner.start_event(EventSpawner.GUARDED_CHEST), "the chest is built")
	spawner.end_wave()
	OS.remove_logger(spy)
	check_eq(lines.size(), 2, "one line at the start, one at the end: %s" % [lines])
	if lines.size() == 2:
		var started := RegEx.create_from_string("^EVENT guarded_chest \\(wave 5\\): started at \\d+\\.\\d s$")
		var ended := RegEx.create_from_string("^EVENT guarded_chest \\(wave 5\\): failed at \\d+\\.\\d s$")
		check(started.search(lines[0]) != null, "the start line reads right: %s" % lines[0])
		check(ended.search(lines[1]) != null, "so does the end line: %s" % lines[1])
	check(spy.with_text("EVENT").is_empty(), "nothing was printed: %s" % [spy.lines])


func test_a_run_prints_no_event_lines_itself_main_logs_them_through_its_gate() -> void:
	_run_with_bots(1)
	var sp := main.event_spawner
	check(sp.logged.is_connected(main._log), "Main logs the spawner's lines through _log (smoke, demo and view runs only)")
	var spy := PrintSpy.new()
	OS.add_logger(spy)
	sp.roll_wave(6)
	check(sp.start_event(EventSpawner.DEFEND_TOTEM), "the totem is built (a plain run)")
	sp.end_wave()
	OS.remove_logger(spy)
	check(spy.with_text("EVENT").is_empty(), "a plain run prints no event line: %s" % [spy.with_text("EVENT")])
