extends TestCase
## M6 BOSSES (GDD 8 "Bossok"): BossData / BossAbility and the two data files, the Boss (max HP
## rule, crowd-control rules, phase 2, enrage, the ability scheduler, rewards), the hazard nodes
## (Frost Circle, Frost Breath, Fire Field, Meteor), the WaveDirector's boss waves (no timer,
## the boss ends the wave, adds at half rate, smoke safety, hazard cleanup), the elite wave 20
## (lite affixes), the HUD boss frame, the bots' hazard avoidance and the Main flow (banner,
## victory on Vor'thalax).

const EFakes := preload("res://tests/enemies_fakes.gd")
const PFakes := preload("res://tests/player_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")
const DT := 1.0 / 60.0

const MORVAIN := &"lich_commander_morvain"
const VORTHALAX := &"vorthalax"

var world: Node3D
var _special: Array = []
var _extra_nodes: Array[Node] = []
var main: Main


func before_each() -> void:
	RunState.start_run(1, 4242)
	RunState.set_wave(10)
	PlayerManager.clear()
	world = EFakes.make_world(tree)
	_special.clear()
	RunState.special_killed.connect(_on_special_killed)


func after_each() -> void:
	if RunState.special_killed.is_connected(_on_special_killed):
		RunState.special_killed.disconnect(_on_special_killed)
	LootDrops.artifact_roll_probe = Callable()
	for n in _extra_nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_extra_nodes.clear()
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	EFakes.free_world(tree, world)
	world = null
	BossData.hp_mult = 1.0
	EliteAffixes.rate_mult = 1.0
	tree.paused = false
	PlayerManager.clear()
	UiFakes.reset_players()
	Db.reload()
	Enemy.invalidate_player_cache()


func _on_special_killed(kind: StringName, killer_index: int) -> void:
	_special.append([kind, killer_index])


# --- Helpers ---------------------------------------------------------------------------------

func _entities() -> Node3D:
	return EFakes.arena_of(world).entities


func _boss(id: StringName = MORVAIN, pos: Vector3 = Vector3.ZERO, p_wave: int = 10) -> Boss:
	var b := Boss.create(Db.get_boss(id), p_wave)
	_entities().add_child(b)
	b.global_position = pos
	return b


func _hero(pos: Vector3, slot_index: int = -1) -> EFakes.FakePlayer:
	return EFakes.spawn_player(world, pos, slot_index)


func _director() -> WaveDirector:
	var d := WaveDirector.create(EFakes.arena_of(world))
	world.add_child(d)
	return d


func _hazards() -> Array[Node]:
	return tree.get_nodes_in_group(EnemyHazard.GROUP)


func _hazards_of(script_class: GDScript) -> Array[Node]:
	var out: Array[Node] = []
	for n in _hazards():
		if is_instance_of(n, script_class) and not n.is_queued_for_deletion():
			out.append(n)
	return out


## A boss with exactly one ability, for the scheduler tests (no contact damage noise).
func _lone_boss(ability: BossAbility, pos: Vector3 = Vector3.ZERO) -> Boss:
	var d := BossData.new()
	d.id = &"test_boss"
	d.display_name = "Test Boss"
	d.max_hp = 100.0
	d.contact_damage = 2.0
	d.hp_compound = 0.0
	d.damage_compound = 0.0
	d.move_speed = 0.0
	d.radius = 0.8
	d.model_style = &"skeleton"
	d.abilities = [ability] as Array[BossAbility]
	var b := Boss.create(d, 1)
	_entities().add_child(b)
	b.global_position = pos
	return b


func _ability(kind: BossAbility.Kind, interval: float = 5.0) -> BossAbility:
	var a := BossAbility.new()
	a.id = &"test_ability"
	a.kind = kind
	a.interval = interval
	a.first_delay = 0.5
	a.telegraph = 1.0
	a.radius = 2.0
	a.damage_mult = 2.0
	a.count = 2
	return a


func _real_hero(index: int, class_id: StringName, pos: Vector3) -> Player:
	var p := Player.create(PFakes.make_slot(index, class_id))
	p.stats.remove_source(&"base")
	_entities().add_child(p)
	p.global_position = pos
	Enemy.invalidate_player_cache()
	return p


# --- Data --------------------------------------------------------------------------------------

func test_boss_data_files_are_loaded_by_db() -> void:
	check(Db.bosses.has(MORVAIN) and Db.bosses.has(VORTHALAX), "both bosses in Db.bosses")
	check_eq(Db.bosses.size(), 2, "two bosses")
	for id in Db.bosses:
		check(not Db.enemies.has(id), "%s is not in the random enemy pool" % id)
		check(Db.bosses[id].is_boss, "%s is_boss" % id)
	var m := Db.get_boss(MORVAIN)
	check_eq(m.display_name, "Lich Commander Morvain", "name")
	check_eq(m.boss_wave, 10, "wave")
	check_eq(m.max_hp, 450.0, "base HP")
	check_eq(m.contact_damage, 3.0, "contact")
	check_eq(m.phase_hp_ratio, 0.5, "phase 2 at 50%")
	check_eq(m.phase_cooldown_mult, 0.7, "cooldowns x0.7 in phase 2")
	check_eq(m.abilities.size(), 3, "three abilities")
	var frost := m.abilities[0]
	check(frost.kind == BossAbility.Kind.FROST_CIRCLES and frost.interval == 7.0 and frost.radius == 2.2
			and frost.telegraph == 1.2 and frost.damage_mult == 2.0 and frost.slow_pct == 40.0
			and frost.slow_time == 2.0, "Frost Circles: every 7 s, r 2.2, 1.2 s, 2x, 40% slow 2 s")
	var raise := m.abilities[1]
	check(raise.kind == BossAbility.Kind.SUMMON and raise.interval == 12.0 and raise.count == 4
			and raise.count_p2 == 6 and raise.summon_id == &"skeleton_grunt", "Raise Dead: 12 s, 4 (6 in phase 2) grunts")
	var breath := m.abilities[2]
	check(breath.kind == BossAbility.Kind.FROST_BREATH and breath.interval == 9.0 and breath.angle == 60.0
			and breath.range == 7.0 and breath.telegraph == 1.0 and breath.damage_mult == 3.0,
			"Frost Breath: 9 s, 60 deg, 7 m, 1 s, 3x")
	var v := Db.get_boss(VORTHALAX)
	check_eq(v.boss_wave, 25, "wave 25")
	check_eq(v.max_hp, 450.0, "base HP")
	check_eq(v.contact_damage, 4.0, "contact")
	check_eq(v.abilities.size(), 3, "three abilities")
	var fields := v.abilities[0]
	check(fields.kind == BossAbility.Kind.FIRE_FIELDS and fields.interval == 8.0 and fields.count == 2
			and fields.count_p2 == 3 and fields.radius == 2.0 and fields.telegraph == 1.0
			and fields.duration == 8.0 and fields.damage_mult == 1.0 and fields.tick_interval == 1.0,
			"Fire Fields: 8 s, 2 (3) patches r 2, 1 s, 8 s, 1x per second")
	var meteor := v.abilities[1]
	check(meteor.kind == BossAbility.Kind.METEOR and meteor.interval == 14.0 and meteor.interval_p2 == 10.0
			and meteor.radius == 3.0 and meteor.telegraph == 3.0 and meteor.damage_mult == 8.0
			and meteor.fallback_damage_mult == 4.0, "Meteor: 14 s (10), r 3, 3 s, 8x shared, 4x for all")
	var imps := v.abilities[2]
	check(imps.kind == BossAbility.Kind.SUMMON and imps.interval == 20.0 and imps.count == 6
			and imps.summon_id == &"candlekin", "Imp Swarm: 20 s, 6 Candlekin")
	for add_id in [raise.summon_id, imps.summon_id]:
		check(Db.get_enemy(add_id) != null, "the add %s exists" % add_id)
	for b: BossData in [m, v]:
		check_eq(b.reward_gold, 50, "%s: 50 gold" % b.id)
		check_eq(b.enrage_time, 90.0, "%s: enrage at 90 s" % b.id)
		check(b.knockback_resist >= 1.0, "%s: immune to knockback" % b.id)


func test_for_wave_finds_the_boss_of_a_boss_wave_only() -> void:
	check(BossData.for_wave(10) == Db.get_boss(MORVAIN), "wave 10")
	check(BossData.for_wave(25) == Db.get_boss(VORTHALAX), "wave 25")
	for w in [1, 9, 11, 20, 24]:
		check(BossData.for_wave(w) == null, "no boss on wave %d" % w)
	for w in RunState.BOSS_WAVES:
		check(BossData.for_wave(w) != null, "every RunState.BOSS_WAVES wave has a boss (%d)" % w)


func test_boss_max_hp_rule() -> void:
	var m := Db.get_boss(MORVAIN)
	var base := m.hp_at_wave(10)
	check_near(m.max_hp_for(10, 1), base, 0.001, "solo: base x the wave's growth")
	check_near(m.max_hp_for(10, 2), base * 1.75, 0.001, "2 players: x(1 + 0.75)")
	check_near(m.max_hp_for(10, 3), base * 2.5, 0.001, "3 players: x2.5")
	check_near(m.max_hp_for(10, 4), base * 3.25, 0.001, "4 players: x3.25 (not the normal +60%)")
	BossData.hp_mult = 0.1
	check_near(m.max_hp_for(10, 4), base * 3.25 * 0.1, 0.001, "--boss-hp multiplies it")
	BossData.hp_mult = 1.0
	check(m.max_hp_for(10, 1) > 4000.0, "wave 10 growth is the usual enemy growth (%f)" % m.max_hp_for(10, 1))


func test_enrage_math() -> void:
	var m := Db.get_boss(MORVAIN)
	check_eq(m.enrage_level_at(0.0), 0, "level 0 at the start")
	check_eq(m.enrage_level_at(89.9), 0, "still 0 at 89.9 s")
	check_eq(m.enrage_level_at(90.0), 1, "level 1 at 90 s")
	check_eq(m.enrage_level_at(119.9), 1, "1 until 120 s")
	check_eq(m.enrage_level_at(120.0), 2, "2 at 120 s")
	check_eq(m.enrage_level_at(150.0), 3, "3 at 150 s")
	check_eq(m.enrage_damage_at(0), 1.0, "x1 before")
	check_eq(m.enrage_damage_at(1), 1.5, "x1.5")
	check_eq(m.enrage_damage_at(2), 1.75, "+0.25 after 30 s")
	check_eq(m.enrage_damage_at(3), 2.0, "+0.25 again")


func test_ability_phase_helpers() -> void:
	var a := BossAbility.new()
	a.interval = 10.0
	a.count = 4
	check_eq(a.interval_at(1, 0.7), 10.0, "phase 1 interval")
	check_near(a.interval_at(2, 0.7), 7.0, 0.0001, "phase 2: x the boss's cooldown factor")
	a.interval_p2 = 6.0
	check_eq(a.interval_at(2, 0.7), 6.0, "an own phase-2 interval wins")
	check_eq(a.count_at(2), 4, "no phase-2 count: the same")
	a.count_p2 = 6
	check_eq(a.count_at(1), 4, "phase 1 count")
	check_eq(a.count_at(2), 6, "phase 2 count")
	check_near(a.first_cast_delay(), 6.0, 0.0001, "the first cast comes after 60% of the interval")
	a.first_delay = 2.0
	check_eq(a.first_cast_delay(), 2.0, "or the explicit delay")


# --- Boss: stats and crowd control -------------------------------------------------------------

func test_boss_create_uses_the_boss_hp_rule_and_party_damage() -> void:
	RunState.start_run(4, 7)
	var b := _boss(MORVAIN, Vector3.ZERO, 10)
	var m := Db.get_boss(MORVAIN)
	check(b.is_boss() and b.is_elite(), "a boss is an elite for targeting")
	check_near(b.max_hp, m.hp_at_wave(10) * 3.25, 0.001, "max HP = growth x (1 + 0.75 x 3)")
	check_eq(b.hp, b.max_hp, "full HP")
	check_near(b.contact_damage, m.contact_damage_at_wave(10) * RunState.coop_damage_mult(), 0.0001,
			"contact damage = base x the wave's growth x the party's damage factor")
	check(b.model is BossModel, "its own model")
	check(b.boss_data == m and b.abilities.size() == 3 and b.phase == 1 and b.enrage_level == 0, "fresh state")
	check_near(b.abilities[0].left, 7.0 * 0.6, 0.0001, "the first Frost Circles after 60% of 7 s")


func test_boss_crowd_control_rules() -> void:
	var b := _boss()
	var hero := _hero(Vector3(20, 0, 0))
	# Knockback: the hit lands, the push does not (also a direct write, like the Warrior's). A boss
	# whose data has no knockback_resist is immune all the same.
	var plain := _lone_boss(_ability(BossAbility.Kind.FROST_CIRCLES), Vector3(0, 0, 12))
	check_eq(plain.data.knockback_resist, 0.0, "(this one's data has no resistance)")
	for boss: Boss in [b, plain]:
		var hp := boss.hp
		boss.take_damage(10.0, false, null, Vector3(5.0, 0.0, 0.0))
		check_eq(boss.hp, hp - 10.0, "the damage lands")
		check_eq(boss.knockback_velocity, Vector3.ZERO, "no knockback")
		boss.knockback_velocity = Vector3(6.0, 0.0, 0.0)
		boss._physics_process(DT)
		check_eq(boss.knockback_velocity, Vector3.ZERO, "a direct push is cleared too")
	# Stun: a quarter of the time.
	b.apply_stun(2.0)
	check_near(b.stun_left, 0.5, 0.0001, "a 2 s stun lasts 0.5 s")
	# Slow: halved.
	b.apply_slow(40.0, 3.0)
	check_near(b.slow_pct, 20.0, 0.0001, "a 40% slow lands as 20%")
	check_near(b.slow_left, 3.0, 0.0001, "for the full time")
	# Taunt and fear: ignored.
	b.apply_taunt(hero, 5.0)
	check(not b.is_taunted() and b.taunt_left == 0.0, "no taunt")
	b.apply_fear(3.0, Vector3.ZERO)
	check(not b.is_feared() and b.fear_left == 0.0, "no fear")


func test_boss_ghost_slow_is_halved_too() -> void:
	var b := _boss()
	var base := b.move_speed * b.speed_mult
	check_near(b.walk_speed(), base, 0.0001, "no slow: the plain speed")
	b.ghost_slow_left = 1.0
	var g := Player.GHOST_SLOW_PCT
	# Enemy applies (1 - g / 100) to the speed it asked for: walk_speed compensates to half the slow.
	check_near(b.walk_speed() * (1.0 - g / 100.0), base * (1.0 - g / 200.0), 0.0001, "half of the ghost slow")
	b.apply_slow(90.0, 2.0)  # a stronger slow (45% halved) than the ghost's 33%
	check_near(b.walk_speed(), base, 0.0001, "the other slow is stronger: no compensation")


func test_normal_enemies_keep_their_crowd_control() -> void:
	var e := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3.ZERO)
	e.apply_stun(2.0)
	check_near(e.stun_left, 2.0, 0.0001, "a normal enemy takes the whole stun")
	e.apply_slow(40.0, 3.0)
	check_near(e.slow_pct, 40.0, 0.0001, "and the whole slow")
	e.take_damage(1.0, false, null, Vector3(5.0, 0.0, 0.0))
	check(e.knockback_velocity != Vector3.ZERO, "and the knockback")


# --- Boss: phases and enrage -------------------------------------------------------------------

func test_phase_two_at_half_hp_rescales_the_timers() -> void:
	var b := _boss()
	_hero(Vector3(20, 0, 0))
	var phases: Array[int] = []
	b.phase_changed.connect(func(p: int) -> void: phases.append(p))
	b.hp = b.max_hp * 0.51
	b._physics_process(DT)
	check_eq(b.phase, 1, "above 50%: phase 1")
	var before := b.abilities[0].left
	b.hp = b.max_hp * 0.5
	b._physics_process(DT)
	check_eq(b.phase, 2, "at 50%: phase 2")
	check_eq(phases, [2] as Array[int], "phase_changed(2) once")
	check_near(b.abilities[0].left, (before - DT) * 0.7, 0.01, "the running timer keeps its progress at x0.7 intervals")
	b.hp = b.max_hp * 0.2
	b._physics_process(DT)
	check_eq(phases.size(), 1, "never again")
	check_near(b.abilities[0].ability.interval_at(b.phase, 0.7), 4.9, 0.0001, "Frost Circles every 4.9 s now")


func test_enrage_raises_damage_and_speed_and_hits_harder() -> void:
	var b := _boss(MORVAIN, Vector3.ZERO)
	b.abilities.clear()  # no casts in this test
	var hero := _hero(Vector3(1.0, 0.0, 0.0))
	b.contact_cooldown_left = 0.0
	EFakes.step(b, 0.1)
	check_eq(hero.fake_hits.size(), 1, "a contact hit")
	check_near(hero.fake_hits[0], b.contact_damage, 0.0001, "plain damage before the enrage")
	var enraged: Array[int] = []
	b.enrage_changed.connect(func(l: int) -> void: enraged.append(l))
	b._age = 89.95
	EFakes.step(b, 1.2)
	check_eq(b.enrage_level, 1, "enraged at 90 s")
	check(b.is_boss_enraged(), "is_boss_enraged")
	check_eq(b.damage_mult, 1.5, "damage x1.5")
	check_eq(b.speed_mult, 1.3, "speed x1.3")
	check_near(b.walk_speed(), b.move_speed * 1.3, 0.0001, "walks 30% faster")
	check_eq(enraged, [1] as Array[int], "enrage_changed(1)")
	check(hero.fake_hits.size() >= 2, "hit again")
	check_near(hero.fake_hits[hero.fake_hits.size() - 1], b.contact_damage * 1.5, 0.0001, "the hit is x1.5")
	b._age = 120.01
	b._physics_process(DT)
	check_eq(b.enrage_level, 2, "level 2 at 120 s")
	check_eq(b.damage_mult, 1.75, "+0.25 damage")
	check_eq(b.speed_mult, 1.3, "the speed bonus does not grow")
	check_near(b.damage_of(2.0), b.contact_damage * 2.0 * 1.75, 0.0001, "hazard damage follows the enrage")
	check_eq(enraged, [1, 2] as Array[int], "each step signalled")


# --- Boss: the ability scheduler ---------------------------------------------------------------

func test_frost_circles_come_under_every_living_hero() -> void:
	var b := _lone_boss(_ability(BossAbility.Kind.FROST_CIRCLES))
	var h1 := _hero(Vector3(8, 0, 0))
	var h2 := _hero(Vector3(-8, 0, 3))
	var downed := _hero(Vector3(0, 0, 9))
	downed.downed = true
	Enemy.invalidate_player_cache()
	check(_hazards().is_empty(), "nothing before the first cast")
	EFakes.step(b, 0.6)
	var circles := _hazards_of(FrostCircle)
	check_eq(circles.size(), 2, "one circle per living hero")
	var at: Array[Vector3] = []
	for c in circles:
		at.append(c.global_position)
	check(at.has(h1.global_position) and at.has(h2.global_position), "under the heroes")
	check_near(circles[0].damage, b.contact_damage * 2.0, 0.0001, "2x the boss's contact damage")
	check_near(circles[0].radius, 2.0, 0.0001, "radius from the ability")
	EFakes.step(b, 4.3)
	check_eq(_hazards_of(FrostCircle).size() >= 2, true, "the next cast comes after the interval")


func test_no_cast_without_a_living_hero_retries_soon() -> void:
	var b := _lone_boss(_ability(BossAbility.Kind.FROST_CIRCLES))
	EFakes.step(b, 1.0)
	check(_hazards().is_empty(), "nobody to aim at")
	check_near(b.abilities[0].left, Boss.RETRY_TIME, 0.6, "it retries soon, not after the whole interval")
	_hero(Vector3(6, 0, 0))
	EFakes.step(b, 0.7)
	check_eq(_hazards_of(FrostCircle).size(), 1, "the circle comes as soon as a hero is there")


func test_a_stunned_boss_does_not_cast() -> void:
	var b := _lone_boss(_ability(BossAbility.Kind.FROST_CIRCLES))
	_hero(Vector3(6, 0, 0))
	b.stun_left = 2.0
	var left := b.abilities[0].left
	b._physics_process(DT)
	b._physics_process(DT)
	check_near(b.abilities[0].left, left, 0.0001, "the timers stand still while stunned")
	b.stun_left = 0.0
	EFakes.step(b, 0.6)
	check(not _hazards_of(FrostCircle).is_empty(), "and it casts once it is free")


func test_frost_breath_aims_at_the_nearest_hero() -> void:
	var a := _ability(BossAbility.Kind.FROST_BREATH)
	a.angle = 60.0
	a.range = 7.0
	var b := _lone_boss(a, Vector3(0, 0, 0))
	_hero(Vector3(5, 0, 0))
	_hero(Vector3(-12, 0, 0))
	EFakes.step(b, 0.6)
	var cones := _hazards_of(FrostBreath)
	check_eq(cones.size(), 1, "one cone")
	var cone := cones[0] as FrostBreath
	check_near(cone.direction.x, 1.0, 0.001, "towards the nearest hero (+X)")
	check_near(cone.damage, b.contact_damage * 2.0, 0.0001, "damage from the ability multiple")
	check_eq(cone.angle, 60.0, "angle")
	check_eq(cone.range_m, 7.0, "range")


func test_summon_ability_brings_adds_through_the_director() -> void:
	var d := _director()
	d.start_wave(10)
	d.boss_data = null  # (a plain director: the boss here is the test's own)
	var a := _ability(BossAbility.Kind.SUMMON)
	a.summon_id = &"skeleton_grunt"
	a.count = 3
	a.count_p2 = 5
	var b := _lone_boss(a, Vector3(4, 0, 4))
	b.director = d
	_hero(Vector3(-8, 0, 0))
	var before := d.alive_count()
	var added: Array[Enemy] = []
	d.enemy_spawned.connect(func(e: Enemy) -> void: added.append(e))
	EFakes.step(b, 0.6)
	check_eq(added.size(), 3, "three skeleton grunts")
	check_eq(d.alive_count(), before + 3, "alive")
	for e in added:
		check_eq(e.data.id, &"skeleton_grunt", "the add type")
		check(EFakes.flat_distance(e.global_position, b.global_position) < 4.0, "around the boss")
	b._enter_phase(2)
	b.abilities[0].left = 0.0
	added.clear()
	b._physics_process(DT)
	check_eq(added.size(), 5, "five in phase 2")


func test_summon_respects_the_enemy_cap() -> void:
	var d := _director()
	d.start_wave(9)
	var data := Db.get_enemy(&"skeleton_grunt")
	var made := d.summon(data, WaveDirector.MAX_ENEMIES + 20, Vector3.ZERO, 3.0)
	check(made.size() <= WaveDirector.MAX_ENEMIES, "never above the cap (%d)" % made.size())
	check(d.summon(data, 3, Vector3.ZERO, 3.0).is_empty(), "nothing more once full")
	d.stop()
	check(d.summon(data, 3, Vector3.ZERO, 3.0).is_empty(), "nothing when the wave is not running")


func test_fire_fields_land_on_different_heroes_and_extras_nearby() -> void:
	var a := _ability(BossAbility.Kind.FIRE_FIELDS)
	a.count = 2
	a.count_p2 = 3
	a.duration = 8.0
	var b := _lone_boss(a)
	var h1 := _hero(Vector3(8, 0, 0))
	var h2 := _hero(Vector3(-8, 0, 0))
	EFakes.step(b, 0.6)
	var fields := _hazards_of(FireField)
	check_eq(fields.size(), 2, "two patches")
	var spots: Array[Vector3] = []
	for f in fields:
		spots.append(f.global_position)
	check(spots.has(h1.global_position) and spots.has(h2.global_position), "one on each hero")
	for f in fields:
		f.free()
	# Three patches for two heroes: the third lands near one of them.
	b._enter_phase(2)
	b.abilities[0].left = 0.0
	b._physics_process(DT)
	fields = _hazards_of(FireField)
	check_eq(fields.size(), 3, "three patches in phase 2")
	var near_hero := 0
	for f in fields:
		if EFakes.flat_distance(f.global_position, h1.global_position) < 0.01 \
				or EFakes.flat_distance(f.global_position, h2.global_position) < 0.01:
			near_hero += 1
	check_eq(near_hero, 2, "two exactly on a hero, the extra beside one")


func test_meteor_marks_a_random_living_hero() -> void:
	var a := _ability(BossAbility.Kind.METEOR)
	a.telegraph = 3.0
	a.radius = 3.0
	a.damage_mult = 8.0
	a.fallback_damage_mult = 4.0
	var b := _lone_boss(a)
	var h1 := _hero(Vector3(8, 0, 0))
	var h2 := _hero(Vector3(-8, 0, 0))
	EFakes.step(b, 0.6)
	var meteors := _hazards_of(MeteorStrike)
	check_eq(meteors.size(), 1, "one meteor")
	var m := meteors[0] as MeteorStrike
	check(m.global_position == h1.global_position or m.global_position == h2.global_position, "on a hero")
	check_near(m.damage, b.contact_damage * 8.0, 0.0001, "8x contact in total")
	check_near(m.fallback_damage, b.contact_damage * 4.0, 0.0001, "4x contact for everybody otherwise")
	check_near(m.telegraph_time, 3.0, 0.0001, "3 s warning")


# --- Hazards -----------------------------------------------------------------------------------

func test_frost_circle_hurts_and_chills_heroes_inside_only() -> void:
	var inside := _real_hero(0, &"warrior", Vector3(0.5, 0, 0))
	var outside := _real_hero(1, &"mage", Vector3(6.0, 0, 0))
	var hp_in := inside.hp
	var hp_out := outside.hp
	var c := FrostCircle.spawn(_entities(), Vector3.ZERO, 2.0, 1.2, 3.0, 40.0, 2.0)
	check(c.is_telegraphing() and c.is_dangerous(), "telegraphing")
	check_near(c.telegraph_left(), 1.2, 0.0001, "1.2 s warning")
	var speed := inside.stats.get_stat(Stats.SPEED)
	EFakes.step(c, 1.1)
	check_eq(inside.hp, hp_in, "nothing before the strike")
	EFakes.step(c, 0.2)
	check(inside.hp < hp_in, "the hero inside is hurt")
	check_eq(outside.hp, hp_out, "the hero outside is not")
	check_near(inside.stats.get_stat(Stats.SPEED), speed - 40.0, 0.0001, "chilled: -40% speed")
	check(GeneralBuff.find(inside, FrostCircle.CHILL_KEY) != null, "as a timed buff")
	check(GeneralBuff.find(outside, FrostCircle.CHILL_KEY) == null, "not on the other")
	check_eq(c.hits, 1, "one hit")
	check(not c.is_dangerous(), "harmless once it struck")
	var chill := GeneralBuff.find(inside, FrostCircle.CHILL_KEY)
	EFakes.step(chill, 2.3)
	check_near(inside.stats.get_stat(Stats.SPEED), speed, 0.0001, "the chill ends after 2 s")
	EFakes.step(c, 0.6)
	check(c.is_queued_for_deletion(), "the circle frees itself after its fade")


func test_frost_circle_misses_the_dodging_and_the_downed() -> void:
	var a := _hero(Vector3(0.5, 0, 0))
	var downed := _hero(Vector3(-0.5, 0, 0))
	downed.downed = true
	Enemy.invalidate_player_cache()
	var c := FrostCircle.spawn(_entities(), Vector3.ZERO, 2.0, 1.0, 3.0, 0.0, 0.0)
	EFakes.step(c, 1.1)
	check_eq(a.fake_hits, [3.0] as Array[float], "the living hero took the damage once")
	check(downed.fake_hits.is_empty(), "a downed hero is not hit")
	check_eq(a.fake_kinds[0], CombatMath.KIND_AOE, "AOE kind (Avoidance applies)")


func test_frost_breath_cone_geometry() -> void:
	var cone := FrostBreath.spawn(_entities(), Vector3.ZERO, Vector3(1, 0, 0), 60.0, 7.0, 1.0, 5.0)
	check(cone.contains(Vector3(4, 0, 0)), "straight ahead")
	check(cone.contains(Vector3(6.9, 0, 0)), "at the far end")
	check(not cone.contains(Vector3(7.5, 0, 0)), "beyond the range")
	check(cone.contains(Vector3(4, 0, 2.0)), "inside the 30 deg half angle (26 deg)")
	check(not cone.contains(Vector3(4, 0, 3.5)), "outside it (41 deg)")
	check(not cone.contains(Vector3(-3, 0, 0)), "behind the boss")
	check(not cone.contains(Vector3(4, 0, 2.8)), "35 deg is outside")
	check(cone.contains(Vector3(4, 0, 2.8), 0.6), "a margin widens the cone")
	cone.free()


func test_frost_breath_hits_the_heroes_in_the_cone() -> void:
	var in_cone := _hero(Vector3(4, 0, 1))
	var out_cone := _hero(Vector3(0, 0, 5))
	var cone := FrostBreath.spawn(_entities(), Vector3.ZERO, Vector3(1, 0, 0), 60.0, 7.0, 1.0, 5.0)
	EFakes.step(cone, 0.9)
	check(in_cone.fake_hits.is_empty(), "no damage during the telegraph")
	EFakes.step(cone, 0.2)
	check_eq(in_cone.fake_hits, [5.0] as Array[float], "the hero in the cone is hit")
	check(out_cone.fake_hits.is_empty(), "the other is not")
	check_eq(cone.hits, 1, "one hit")


func test_fire_field_ticks_every_second_for_eight_seconds() -> void:
	var inside := _hero(Vector3(0.5, 0, 0))
	var outside := _hero(Vector3(8, 0, 0))
	var f := FireField.spawn(_entities(), Vector3.ZERO, 2.0, 1.0, 8.0, 1.0, 2.0)
	EFakes.step(f, 0.9)
	check(inside.fake_hits.is_empty(), "the telegraph does not burn")
	EFakes.step(f, 0.2)
	check_eq(inside.fake_hits.size(), 1, "the first tick the moment it ignites")
	check(f.is_dangerous() and not f.is_telegraphing(), "burning")
	EFakes.step(f, 3.0)
	check_eq(inside.fake_hits.size(), 4, "one tick per second")
	EFakes.step(f, 6.0)
	check_eq(inside.fake_hits.size(), 8, "eight ticks in 8 s, then it is over")
	check(not f.is_dangerous(), "burnt out")
	check(outside.fake_hits.is_empty(), "the hero outside never burns")
	check_eq(inside.fake_hits[0], 2.0, "damage per tick")


func test_fire_field_stops_hurting_a_hero_who_leaves() -> void:
	var h := _hero(Vector3(0.5, 0, 0))
	var f := FireField.spawn(_entities(), Vector3.ZERO, 2.0, 0.5, 8.0, 1.0, 2.0)
	EFakes.step(f, 1.6)
	var n := h.fake_hits.size()
	check_eq(n, 2, "two ticks while standing in it")
	h.global_position = Vector3(6, 0, 0)
	EFakes.step(f, 3.0)
	check_eq(h.fake_hits.size(), n, "none after stepping out")


func test_meteor_damage_is_shared_among_the_heroes_inside() -> void:
	var h1 := _hero(Vector3(0.5, 0, 0))
	var h2 := _hero(Vector3(-1.0, 0, 1.0))
	var h3 := _hero(Vector3(1.0, 0, -1.0))
	var far := _hero(Vector3(9, 0, 0))
	var m := MeteorStrike.spawn(_entities(), Vector3.ZERO, 3.0, 3.0, 90.0, 45.0)
	EFakes.step(m, 2.9)
	check(h1.fake_hits.is_empty(), "nothing during the 3 s warning")
	EFakes.step(m, 0.2)
	check_eq(m.inside_count, 3, "three inside")
	for h in [h1, h2, h3]:
		check_eq(h.fake_hits, [30.0] as Array[float], "each takes a third of the total")
	check(far.fake_hits.is_empty(), "the hero outside takes nothing")
	check(m.struck, "struck")


func test_meteor_alone_in_the_circle_takes_everything() -> void:
	var h := _hero(Vector3(0.5, 0, 0))
	var other := _hero(Vector3(9, 0, 0))
	var m := MeteorStrike.spawn(_entities(), Vector3.ZERO, 3.0, 1.0, 90.0, 45.0)
	EFakes.step(m, 1.1)
	check_eq(h.fake_hits, [90.0] as Array[float], "one hero inside: the whole 8x")
	check(other.fake_hits.is_empty(), "the others are spared")


func test_meteor_with_nobody_inside_hits_every_living_hero() -> void:
	var a := _hero(Vector3(8, 0, 0))
	var b := _hero(Vector3(-8, 0, 0))
	var downed := _hero(Vector3(0, 0, 8))
	downed.downed = true
	Enemy.invalidate_player_cache()
	var m := MeteorStrike.spawn(_entities(), Vector3.ZERO, 3.0, 1.0, 90.0, 45.0)
	EFakes.step(m, 1.1)
	check_eq(m.inside_count, 0, "nobody inside")
	check_eq(a.fake_hits, [45.0] as Array[float], "every living hero takes the 4x")
	check_eq(b.fake_hits, [45.0] as Array[float], "every living hero takes the 4x")
	check(downed.fake_hits.is_empty(), "a downed hero is spared")


func test_hazard_damage_comes_from_the_boss_as_aoe() -> void:
	var b := _boss()
	var h := _hero(Vector3(0.5, 0, 0))
	var f := FrostCircle.spawn(_entities(), Vector3.ZERO, 2.0, 0.5, 4.0, 0.0, 0.0, b)
	EFakes.step(f, 0.6)
	check_eq(h.fake_sources, [b] as Array[Node3D], "the boss is the damage source")
	check_eq(h.fake_kinds, [CombatMath.KIND_AOE] as Array[StringName], "damage kind AOE")


# --- Boss death ----------------------------------------------------------------------------------

func test_boss_death_rewards() -> void:
	RunState.start_run(3, 11)
	RunState.set_wave(10)
	var killer := _hero(Vector3(5, 0, 0), 1)
	var b := _boss()
	var drops_before := RunState.loot_drops_this_wave
	b.take_damage(b.hp + 1.0, false, killer)
	check(b.is_dead(), "dead")
	check_eq(RunState.bosses_killed, 1, "counted")
	check_eq(_special, [[&"boss", 1]], "special_killed(boss, killer slot)")
	var gold := 0
	for p in tree.get_nodes_in_group(&"pickups"):
		gold += (p as Pickup).gold
	check_eq(gold, 50, "50 gold on the ground")
	var bags: Array[Node] = tree.get_nodes_in_group(&"loot_bags")
	check_eq(bags.size(), 3, "one item per player")
	for bag in bags:
		check((bag as LootBag).item.rarity >= Items.Rarity.EPIC, "Epic+")
	check_eq(RunState.loot_drops_this_wave, drops_before, "boss drops do not count against the normal cap")
	check_eq(RunState.kills, 1, "a kill")


func test_boss_death_item_rarity_has_legendaries() -> void:
	RunState.start_run(4, 12)
	RunState.set_wave(25)
	var legendary := 0
	var total := 0
	for i in 40:
		var b := _boss(VORTHALAX, Vector3.ZERO, 25)
		b.kill()
		for bag in tree.get_nodes_in_group(&"loot_bags"):
			total += 1
			if (bag as LootBag).item.rarity == Items.Rarity.LEGENDARY:
				legendary += 1
			bag.free()
	check_eq(total, 160, "four per boss")
	check(legendary > 10 and legendary < 60, "about 20%% Legendary (%d / %d)" % [legendary, total])


func test_boss_death_makes_one_artifact_roll_per_item_and_no_loot_roll() -> void:
	RunState.start_run(2, 13)
	RunState.set_wave(10)
	var sources: Array = []
	var killers: Array = []
	LootDrops.artifact_roll_probe = func(source: ItemGenerator.Source, _enemy: Node3D, killer: Node3D) -> LootBag:
		sources.append(source)
		killers.append(killer)
		return null
	var killer := _hero(Vector3(5, 0, 0), 0)
	var b := _boss()
	b.take_damage(b.hp + 1.0, false, killer)
	check_eq(sources, [ItemGenerator.Source.BOSS, ItemGenerator.Source.BOSS], "BOSS-source rolls only, no normal LOOT roll after it")
	check(killers[0] == killer, "the killer's roll comes first (the Artifact dedupe keeps it)")


func test_loot_heroes_put_the_killer_first_and_cover_every_slot() -> void:
	var a := PlayerManager.add_bot(&"warrior", 1)
	var b_slot := PlayerManager.add_bot(&"mage", 2)
	var c := PlayerManager.add_bot(&"rogue", 3)
	var heroes: Array[Player] = []
	for s in [a, b_slot, c]:
		var h := _hero(Vector3(float(heroes.size()) * 3.0, 0, 8), s.index)
		s.player = h
		heroes.append(h)
	var boss := _boss()
	var order := boss._loot_heroes(heroes[2])
	check_eq(order.size(), 3, "one entry per player")
	check(order[0] == heroes[2], "the killer first")
	check(order.has(heroes[0]) and order.has(heroes[1]), "the others follow")
	var none := boss._loot_heroes(null)
	check(none[0] == heroes[0] and none[2] == heroes[2], "slot order without a killer")
	for s in [a, b_slot, c]:
		s.player = null


# --- WaveDirector: boss waves ------------------------------------------------------------------

func test_boss_wave_has_no_timer_and_the_boss_comes_after_the_telegraph() -> void:
	var hero := _hero(Vector3(-10, 0, 0))
	var d := _director()
	var timer_signals: Array[float] = []
	d.wave_timer_changed.connect(func(t: float) -> void: timer_signals.append(t))
	var arrived: Array[Boss] = []
	d.boss_spawned.connect(func(b: Boss) -> void: arrived.append(b))
	d.start_wave(10)
	check(d.boss_data == Db.get_boss(MORVAIN), "this wave's boss")
	check_eq(d.time_left, WaveDirector.BOSS_WAVE_TIME, "no real clock")
	check(timer_signals.is_empty(), "the timer is not reported on a boss wave")
	check(d.elite_times().is_empty(), "no elites: the boss is the elite")
	check(d.boss == null, "the boss is not there yet")
	EFakes.step(d, WaveDirector.BOSS_TELEGRAPH_TIME - 0.2)
	check(d.boss == null, "still telegraphed")
	EFakes.step(d, 0.3)
	check(d.boss != null and arrived.size() == 1 and arrived[0] == d.boss, "the boss arrived and was announced")
	check(d.boss.is_inside_tree() and d.boss.data == Db.get_boss(MORVAIN), "in the arena")
	check(EFakes.flat_distance(d.boss.global_position, hero.global_position) >= 10.0 - 0.01,
			"away from the heroes")
	check(d.is_running(), "the wave runs on")
	EFakes.step(d, 30.0)
	check(d.is_running() and d.time_left > 1000.0, "no timer ends it")


func test_boss_wave_ends_only_when_the_boss_dies() -> void:
	_hero(Vector3(-9, 0, 0), 0)
	var d := _director()
	var cleared: Array[int] = []
	d.wave_cleared.connect(func(w: int) -> void: cleared.append(w))
	var defeated: Array[Boss] = []
	d.boss_defeated.connect(func(b: Boss) -> void: defeated.append(b))
	d.start_wave(10)
	EFakes.step(d, WaveDirector.BOSS_TELEGRAPH_TIME + 0.1)
	check(d.boss != null, "boss there")
	EFakes.step(d, 20.0)
	check(cleared.is_empty(), "alive: no end")
	# Some adds and a pickup on the ground.
	var grunt := EFakes.spawn_enemy(world, Db.get_enemy(&"skeleton_grunt"), Vector3(3, 0, 3), 10)
	var coin := Pickup.drop(_entities(), 5, 0, Vector3(2, 0, 2))
	var boss := d.boss
	boss.kill()
	check_eq(defeated.size(), 1, "boss_defeated emitted at the death")
	check(cleared.is_empty(), "the wave ends on the next tick")
	d._physics_process(DT)
	check_eq(cleared, [10] as Array[int], "wave_cleared(10)")
	check(not d.is_running(), "stopped")
	check(grunt.is_queued_for_deletion() or not grunt.is_inside_tree() or not grunt.is_in_group(&"enemies"),
			"the adds despawned")
	check(coin == null or coin.is_queued_for_deletion() or not coin.is_in_group(&"pickups")
			or coin.is_collected_to_bank(), "pickups banked")


func test_the_wave_ends_when_the_dead_boss_is_already_freed() -> void:
	# In a real run queue_free() has deleted the boss by the next tick when something other than a
	# hero killed it (the smoke safety): a freed boss compares equal to null, which once left the
	# wave running forever.
	_hero(Vector3(-9, 0, 0))
	var d := _director()
	var cleared: Array[int] = []
	d.wave_cleared.connect(func(w: int) -> void: cleared.append(w))
	d.start_wave(10)
	EFakes.step(d, WaveDirector.BOSS_TELEGRAPH_TIME + 0.1)
	d.boss.kill()
	d.boss.free()
	d._physics_process(DT)
	check_eq(cleared, [10] as Array[int], "the wave still ends")


func test_the_wave_ends_when_the_boss_is_freed_without_a_death() -> void:
	_hero(Vector3(-9, 0, 0))
	var d := _director()
	var cleared: Array[int] = []
	d.wave_cleared.connect(func(w: int) -> void: cleared.append(w))
	d.start_wave(10)
	EFakes.step(d, WaveDirector.BOSS_TELEGRAPH_TIME + 0.1)
	d.boss.free()
	d._physics_process(DT)
	check_eq(cleared, [10] as Array[int], "a vanished boss does not strand the wave either")


func test_boss_wave_pickups_are_banked_like_a_normal_end() -> void:
	_hero(Vector3(-9, 0, 0))
	var d := _director()
	d.start_wave(10)
	EFakes.step(d, WaveDirector.BOSS_TELEGRAPH_TIME + 0.1)
	var gold := RunState.gold
	d.boss.kill()
	d._physics_process(DT)
	check(RunState.gold >= gold + 50, "the boss's 50 gold reached the wallet (%d -> %d)" % [gold, RunState.gold])
	check_eq(tree.get_nodes_in_group(&"loot_bags").size(), 0, "bags banked")
	check_eq(RunState.team_loot.size(), 1, "the boss item waits for the loot roll")


func test_boss_wave_adds_come_at_half_the_rate() -> void:
	var d := _director()
	d.start_wave(9)
	var normal := d.spawn_budget_per_second()
	d.stop()
	d.start_wave(10)
	check_near(d.spawn_budget_per_second(), normal * 0.5 * WaveDirector.spawn_rate(10) / WaveDirector.spawn_rate(9), 0.0001,
			"50% of wave 10's rate")
	check_near(d.spawn_budget_per_second(), WaveDirector.spawn_rate(10, RunState.coop_count_mult()) * 0.5, 0.0001, "the formula")
	d.stop()
	d.start_wave(11)
	check_near(d.spawn_budget_per_second(), WaveDirector.spawn_rate(11, RunState.coop_count_mult()), 0.0001, "normal again after")


func test_boss_wave_keeps_spawning_adds() -> void:
	_hero(Vector3(-9, 0, 0))
	var d := _director()
	d.start_wave(10)
	EFakes.step(d, 12.0)
	check(d.spawned_this_wave > 1, "adds spawned next to the boss (%d)" % d.spawned_this_wave)
	check(d.boss != null, "with the boss")


func test_boss_wave_without_a_boss_definition_is_a_timed_wave() -> void:
	Db.bosses.clear()
	var d := _director()
	d.start_wave(10)
	check(d.boss_data == null, "no BossData: a normal wave")
	check_eq(d.time_left, RunState.wave_duration(10), "with its normal clock")
	EFakes.step(d, RunState.wave_duration(10) + 0.5)
	check(not d.is_running(), "ended by the timer")


func test_forcing_the_end_of_a_boss_wave_by_the_clock_still_works() -> void:
	var d := _director()
	var cleared: Array[int] = []
	d.wave_cleared.connect(func(w: int) -> void: cleared.append(w))
	d.start_wave(25)
	d.time_left = 0.0
	d._physics_process(DT)
	check_eq(cleared, [25] as Array[int], "test / harness hooks that zero time_left end the wave")


func test_smoke_safety_kills_a_boss_that_outlives_its_enrage() -> void:
	_hero(Vector3(-9, 0, 0))
	var d := _director()
	d.smoke_boss_timeout = true
	d.start_wave(10)
	EFakes.step(d, WaveDirector.BOSS_TELEGRAPH_TIME + 0.1)
	var boss := d.boss
	boss._age = boss.boss_data.enrage_time + WaveDirector.SMOKE_BOSS_GRACE - 1.0
	d._physics_process(DT)
	check(not boss.is_dead(), "not yet")
	boss._age = boss.boss_data.enrage_time + WaveDirector.SMOKE_BOSS_GRACE + 0.1
	d._physics_process(DT)
	check(boss.is_dead(), "dead after enrage + 120 s")
	boss.free()  # a real frame deletes the queued boss before the next tick
	d._physics_process(DT)
	check(not d.is_running(), "the wave ended (the freed boss does not hang it)")


func test_the_boss_lives_on_without_the_smoke_safety() -> void:
	_hero(Vector3(-9, 0, 0))
	var d := _director()
	d.start_wave(10)
	EFakes.step(d, WaveDirector.BOSS_TELEGRAPH_TIME + 0.1)
	d.boss._age = 5000.0
	d._physics_process(DT)
	check(not d.boss.is_dead() and d.is_running(), "real runs never time a boss out")


func test_stop_frees_the_hazards_and_the_chill() -> void:
	var hero := _real_hero(0, &"warrior", Vector3(30, 0, 30))
	var d := _director()
	d.start_wave(9)
	FrostCircle.spawn(_entities(), Vector3.ZERO, 2.0, 5.0, 1.0, 0.0, 0.0)
	FireField.spawn(_entities(), Vector3(5, 0, 5), 2.0, 1.0, 8.0, 1.0, 1.0)
	MeteorStrike.spawn(_entities(), Vector3(-5, 0, 5), 3.0, 3.0, 1.0, 1.0)
	var puddle := Node3D.new()  # another package's hazard: only the group matters
	puddle.add_to_group(EnemyHazard.GROUP)
	_entities().add_child(puddle)
	var speed := hero.stats.get_stat(Stats.SPEED)
	GeneralBuff.apply(hero, FrostCircle.CHILL_KEY, 5.0, {Stats.SPEED: -40.0})
	check_near(hero.stats.get_stat(Stats.SPEED), speed - 40.0, 0.0001, "chilled")
	check_eq(_hazards().size(), 4, "four hazards")
	d.stop()
	for n in _hazards():
		check(n.is_queued_for_deletion(), "freed: %s" % n.name)
	check(GeneralBuff.find(hero, FrostCircle.CHILL_KEY) == null, "the chill is gone")
	check_near(hero.stats.get_stat(Stats.SPEED), speed, 0.0001, "and the speed is back")


func test_boss_wave_start_draws_the_boss_point_after_the_opening_group() -> void:
	# Determinism: nothing before the opening group's draws changed; the boss point comes last.
	_hero(Vector3(-9, 0, 0))
	var d := _director()
	RunState.rng.seed = 99
	var state := RunState.rng.state
	d.start_wave(9)
	d.stop()
	var normal_after := RunState.rng.state
	RunState.rng.state = state
	d.start_wave(10)
	check(RunState.rng.state != normal_after, "the boss wave drew its own point on top")
	d.stop()


# --- Elite wave 20 ---------------------------------------------------------------------------------

func _spawn_group_of(d: WaveDirector, data: EnemyData, count: int, p_wave: int) -> Array[Enemy]:
	var made: Array[Enemy] = []
	d.enemy_spawned.connect(func(e: Enemy) -> void: made.append(e))
	var g := WaveDirector.PendingGroup.new()
	g.data = data
	g.count = count
	g.position = Vector3(2, 0, 2)
	g.ring = 1.5
	RunState.set_wave(p_wave)
	d._spawn_group(g)
	return made


func test_elite_wave_gives_every_enemy_a_lite_affix() -> void:
	RunState.start_run(1, 5)
	var d := _director()
	d.start_wave(20)
	d.stop()
	d._running = true
	d._elite_times.clear()
	var data := Db.get_enemy(&"skeleton_grunt")
	var made := _spawn_group_of(d, data, 6, 20)
	check_eq(made.size(), 6, "six spawned")
	for e in made:
		check(e.elite_affix in EliteAffixes.ALL, "every enemy has an affix")
		check(e.elite_lite, "a lite one")
		check(not e.is_elite(), "not an elite for Slayer / targeting")
		check_near(e.max_hp, data.hp_at_wave(20) * RunState.coop_hp_mult() * 1.5, 0.0001, "HP x1.5")
		check_near(e.radius, data.radius, 0.0001, "normal size")
		check(e.elite_plate != null and e.elite_plate.compact, "a compact plate")
	check_eq(RunState.elites_spawned, 0, "lite affixes are not elites")
	check_eq(d.elites_this_wave, 0, "not counted as elites")


func test_other_waves_have_no_lite_affixes() -> void:
	var d := _director()
	for w in [19, 21, 10]:
		d.start_wave(w)
		d.stop()
		d._running = true
		d._elite_times.clear()
		var made := _spawn_group_of(d, Db.get_enemy(&"skeleton_grunt"), 3, w)
		for e in made:
			check(e.elite_affix == &"" and not e.elite_lite, "wave %d: plain enemies" % w)
			e.free()


func test_elite_wave_real_elites_are_still_elites_and_twice_as_many() -> void:
	for n in [1, 2, 4]:
		var normal := EliteAffixes.expected_count(19, n)
		var wave20 := EliteAffixes.expected_count(20, n)
		check_near(wave20 / (EliteAffixes.expected_count(20, n) / 2.0) , 2.0, 0.0001, "sanity")
		var plain := (EliteAffixes.BASE_COUNT + EliteAffixes.COUNT_PER_WAVE * 15.0) \
				* (1.0 + EliteAffixes.COUNT_PER_PLAYER * float(n - 1))
		check_near(wave20, plain * 2.0, 0.0001, "wave 20, %d players: x2" % n)
		check(normal > 0.0 and normal < wave20, "wave 19 is plain")
	var d := _director()
	d.start_wave(20)
	d.stop()
	d._running = true
	d._elite_times = [0.0] as Array[float]
	var made := _spawn_group_of(d, Db.get_enemy(&"skeleton_grunt"), 3, 20)
	check(made[0].is_elite() and not made[0].elite_lite, "the due time makes a real elite")
	check_near(made[0].max_hp, Db.get_enemy(&"skeleton_grunt").hp_at_wave(20) * RunState.coop_hp_mult() * 3.0,
			0.0001, "HP x3")
	check(made[1].elite_lite and made[2].elite_lite, "the rest are lite")
	check_eq(RunState.elites_spawned, 1, "one real elite counted")


func test_lite_affix_enemies_pay_normal_rewards() -> void:
	var data := Db.get_enemy(&"skeleton_grunt")
	var lite := Enemy.create(data, 20)
	lite.make_elite(EliteAffixes.FRENZIED, true)
	_entities().add_child(lite)
	lite.global_position = Vector3(3, 0, 3)
	lite.kill()
	var gold := 0
	for p in tree.get_nodes_in_group(&"pickups"):
		gold += (p as Pickup).gold
	check_eq(gold, data.gold, "normal gold, not the elite 10")
	check_eq(_special.size(), 0, "no special kill")
	check_eq(RunState.elites_killed, 0, "not an elite kill")
	for p in tree.get_nodes_in_group(&"pickups"):
		p.free()
	var real := Enemy.create(data, 20)
	real.make_elite(EliteAffixes.FRENZIED)
	_entities().add_child(real)
	real.global_position = Vector3(-3, 0, 3)
	real.kill()
	check_eq(RunState.elites_killed, 1, "a real elite still counts")


func test_lite_affix_effects_work() -> void:
	var data := Db.get_enemy(&"skeleton_grunt")
	var shield := Enemy.create(data, 20)
	shield.make_elite(EliteAffixes.SHIELDING, true)
	check_near(shield.shield_hp, shield.max_hp * EliteAffixes.SHIELD_PCT, 0.0001, "a shield of 30% of its (x1.5) HP")
	var frenzy := Enemy.create(data, 20)
	frenzy.make_elite(EliteAffixes.FRENZIED, true)
	check_eq(frenzy.speed_mult, EliteAffixes.FRENZY_SPEED_MULT, "Frenzied speed")
	var rage := Enemy.create(data, 20)
	rage.make_elite(EliteAffixes.ENRAGED, true)
	_entities().add_child(rage)
	rage.take_damage(rage.max_hp * 0.55)
	check(rage.is_enraged(), "Enraged below 50%")
	for e in [shield, frenzy]:
		e.free()


func test_compact_elite_plate_has_no_name_or_bar() -> void:
	var data := Db.get_enemy(&"skeleton_grunt")
	var lite := Enemy.create(data, 20)
	lite.make_elite(EliteAffixes.VAMPIRIC, true)
	_entities().add_child(lite)
	var plate := lite.elite_plate
	check(plate.compact and plate.name_label == null, "no name label")
	check(plate.bubble != null and plate.get_node_or_null(^"Plate/Gem") != null, "bubble and gem")
	check_eq(plate.plate.get_child_count(), 1, "one sprite on the plate (the gem)")
	var full := Enemy.create(data, 20)
	full.make_elite(EliteAffixes.VAMPIRIC)
	_entities().add_child(full)
	check(not full.elite_plate.compact and full.elite_plate.name_label != null, "a real elite keeps its nameplate")
	check(full.elite_plate.plate.get_child_count() > 3, "bar, wings, name")


# --- HUD boss frame -------------------------------------------------------------------------------

func _hud() -> Hud:
	var h := Hud.create()
	tree.root.add_child(h)
	_extra_nodes.append(h)
	return h


func test_hud_enraged_row_is_reserved_and_never_dim() -> void:
	var hud := _hud()
	RunState.set_wave(10)
	var b := _boss()
	hud.bind_boss(b)
	var calm_frame := hud.boss_frame.get_combined_minimum_size()
	var column := hud.boss_frame.get_parent() as Control
	var calm_column := column.get_combined_minimum_size()
	check(hud.boss_enraged_label.visible, "the row is laid out while the boss is calm")
	check(not hud.is_boss_enraged_shown(), "but transparent: nothing shows")
	check(hud.boss_enraged_label.modulate.a < 0.01, "alpha 0 while calm")
	b.enrage_level = 1
	var lowest := 1.0
	for i in 40:
		hud._clock = float(i) * 0.05
		hud._process(0.0)
		lowest = minf(lowest, hud.boss_enraged_label.modulate.a)
	check(hud.is_boss_enraged_shown(), "enraged: the line shows")
	check(lowest >= Hud.ENRAGED_ALPHA_MIN - 0.0001, "the pulse never drops below %.2f (%.3f)" % [Hud.ENRAGED_ALPHA_MIN, lowest])
	check(Hud.ENRAGED_ALPHA_MIN >= 0.8, "the floor is bright enough to read on the dark plaque")
	check_eq(hud.boss_frame.get_combined_minimum_size(), calm_frame, "the boss frame does not grow when it enrages")
	check_eq(column.get_combined_minimum_size(), calm_column,
		"nor the plaque column: the rows below do not jump")
	b.enrage_level = 0
	hud._process(0.0)
	check(not hud.is_boss_enraged_shown() and hud.boss_enraged_label.visible, "calm again: transparent, row kept")
	hud.bind_boss(b)
	check(not hud.is_boss_enraged_shown(), "a new frame starts calm")


func test_hud_boss_frame_replaces_the_timer_on_a_boss_wave() -> void:
	var hud := _hud()
	RunState.set_wave(9)
	check(not hud.is_boss_frame_visible() and hud.timer_label.visible, "a normal wave shows the timer")
	RunState.set_wave(10)
	check(hud.is_boss_frame_visible() and not hud.timer_label.visible, "a boss wave shows the frame from its start")
	check_eq(hud.boss_name_label.text, "Lich Commander Morvain", "named")
	var b := _boss()
	hud.bind_boss(b)
	check_eq(hud.boss_bar.text, "100%", "full bar")
	b.hp = b.max_hp * 0.5
	hud._process(DT)
	check_eq(hud.boss_bar.text, "50%", "the bar follows the boss")
	check_near(hud.boss_bar.value / hud.boss_bar.max_value, 0.5, 0.001, "half full")
	check_eq(hud.boss_phase_shown(), 1, "phase 1 pip")
	b.phase = 2
	hud._process(DT)
	check_eq(hud.boss_phase_shown(), 2, "phase 2 lights the second pip")
	check(not hud.is_boss_enraged_shown(), "not enraged")
	b.enrage_level = 1
	hud._process(DT)
	check(hud.is_boss_enraged_shown(), "ENRAGED shows")
	check_eq(hud.boss_enraged_label.text, "ENRAGED", "the text")
	hud.clear_boss()
	check(not hud.is_boss_frame_visible() and hud.timer_label.visible, "cleared: the timer is back")
	RunState.set_wave(25)
	check_eq(hud.boss_name_label.text, "Vor'thalax, the Burning Tyrant", "wave 25's boss")
	RunState.set_wave(11)
	check(not hud.is_boss_frame_visible() and hud.timer_label.visible, "the next normal wave hides it")


func test_hud_boss_frame_survives_a_freed_boss() -> void:
	var hud := _hud()
	RunState.set_wave(10)
	var b := _boss()
	hud.bind_boss(b)
	b.free()
	hud._process(DT)  # must not touch the freed boss
	check(hud.is_boss_frame_visible(), "still shown until cleared")


# --- Bots ------------------------------------------------------------------------------------------

func _bot(pos: Vector3, index: int = 0, class_id: StringName = &"mage") -> Player:
	var slot := PlayerSlot.new(index, BotInput.new("bot:b%d" % index, 3 + index), PlayerManager.PLAYER_COLORS[index])
	slot.class_data = Db.get_class_data(class_id)
	var p := Player.create(slot)
	_entities().add_child(p)
	p.global_position = pos
	Enemy.invalidate_player_cache()
	return p


func _bot_move(p: Player) -> Vector2:
	var bot := p.slot.input as BotInput
	bot.think(DT)
	return bot.get_move()


func test_bot_steps_out_of_a_telegraphed_circle() -> void:
	var bot := _bot(Vector3(5, 0, 0))
	var c := FrostCircle.spawn(_entities(), Vector3(3.5, 0, 0), 2.2, 1.2, 1.0, 0.0, 0.0)
	var move := _bot_move(bot)
	check(move.x > 0.5, "the bot at the circle's western... eastern side runs out of it (%s)" % move)
	c.global_position = Vector3(6.5, 0, 0)
	move = _bot_move(bot)
	check(move.x < -0.5, "from the other side it runs the other way (%s)" % move)
	c.global_position = Vector3(25, 0, 0)
	check(c.hazard_push(Vector3(5, 0, 0)) == Vector2.ZERO, "far away the hazard pushes nothing")


func test_bot_dead_centre_in_a_circle_runs_towards_the_middle() -> void:
	var bot := _bot(Vector3(8, 0, 0))
	FrostCircle.spawn(_entities(), Vector3(8, 0, 0), 2.2, 1.2, 1.0, 0.0, 0.0)
	var move := _bot_move(bot)
	check(move.x < -0.5, "straight under it: out, towards the arena's middle (%s)" % move)


func test_bot_sidesteps_a_frost_breath_cone() -> void:
	var bot := _bot(Vector3(4, 0, 0.5))
	FrostBreath.spawn(_entities(), Vector3.ZERO, Vector3(1, 0, 0), 60.0, 7.0, 1.0, 5.0)
	var move := _bot_move(bot)
	check(absf(move.y) > absf(move.x) and move.y > 0.5, "sideways, to the side it stands on (%s)" % move)
	var bot2 := _bot(Vector3(4, 0, -0.5), 1)
	var move2 := _bot_move(bot2)
	check(move2.y < -0.5, "the other side the other way (%s)" % move2)


func test_bot_ignores_hazards_that_already_struck() -> void:
	var bot := _bot(Vector3(5, 0, 0))
	var c := FrostCircle.spawn(_entities(), Vector3(5, 0, 0), 2.2, 0.2, 0.0, 0.0, 0.0)
	EFakes.step(c, 0.3)
	check(not c.is_dangerous() and c.hazard_push(Vector3(5, 0, 0)) == Vector2.ZERO, "a struck circle is harmless")


func test_bot_leaves_a_burning_field() -> void:
	var bot := _bot(Vector3(5, 0, 0))
	var f := FireField.spawn(_entities(), Vector3(4, 0, 0), 2.0, 0.2, 8.0, 1.0, 0.0)
	EFakes.step(f, 1.0)
	check(f.is_dangerous() and not f.is_telegraphing(), "burning")
	check(_bot_move(bot).x > 0.5, "the bot walks out of the fire")


func test_a_team_of_bots_gathers_in_the_meteor_circle_a_lone_bot_leaves_it() -> void:
	var a := _bot(Vector3(8, 0, 0), 0)
	_bot(Vector3(-9, 0, 0), 1)
	MeteorStrike.spawn(_entities(), Vector3(0, 0, 0), 3.0, 3.0, 90.0, 45.0)
	check(_bot_move(a).x < -0.5, "with a teammate alive the bot walks into the circle (%s)" % _bot_move(a))
	# Alone: out.
	var lone_world := _bot(Vector3(0.5, 0, 0), 2)
	for p in tree.get_nodes_in_group(&"players"):
		if p != lone_world:
			p.remove_from_group(&"players")
	Enemy.invalidate_player_cache()
	var move := _bot_move(lone_world)
	check(move.length() > 0.5, "a lone bot inside moves out (%s)" % move)
	var step := Vector3(lone_world.global_position.x + move.x * 3.0, 0, lone_world.global_position.z + move.y * 3.0)
	check(Vector2(step.x, step.z).length() > Vector2(0.5, 0.0).length(), "away from the middle")


# --- Main flow ----------------------------------------------------------------------------------------

func _run_main(start_wave: int, bots: int = 1) -> void:
	var o := LaunchOptions.new()
	o.start_wave = start_wave
	main = Main.create(o)
	tree.root.add_child(main)
	for i in bots:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)
	main.start_run()


func _step_director(seconds: float) -> void:
	var t := 0.0
	while t < seconds and is_instance_valid(main.wave_director) and main.wave_director.is_running():
		main.wave_director._physics_process(DT)
		t += DT


func test_main_boss_wave_banner_frame_and_end() -> void:
	_run_main(10)
	check_eq(main.state, Main.State.WAVE, "wave 10 running")
	check(main.hud.is_boss_frame_visible(), "the HUD shows the boss frame")
	_step_director(WaveDirector.BOSS_TELEGRAPH_TIME + 0.1)
	var boss := main.wave_director.boss
	check(boss != null, "the boss arrived")
	check_eq(main.hud.banner_label.text, "Lich Commander Morvain", "the arrival banner")
	# boss_spawned -> hud.bind_boss: the frame follows the boss the director spawned.
	boss.hp = boss.max_hp * 0.4
	boss._age = boss.boss_data.enrage_time + 1.0
	boss._physics_process(DT)
	main.hud._process(DT)
	check_eq(main.hud.boss_bar.text, "40%", "the HUD frame shows the new percentage")
	check_eq(main.hud.boss_phase_shown(), 2, "phase 2 lit")
	check(main.hud.is_boss_enraged_shown(), "ENRAGED shows after 90 s")
	_step_director(70.0)
	check_eq(main.state, Main.State.WAVE, "no timer ended the wave (it lasts past its nominal 60 s)")
	boss.kill()
	main.wave_director._physics_process(DT)
	check_eq(main.state, Main.State.WAVE_END, "the boss's death ends it")
	check_eq(main.hud.banner_label.text, "Lich Commander Morvain defeated!", "the banner names the boss")
	check(not main.hud.is_boss_frame_visible(), "the frame is gone")
	main._physics_process(Main.WAVE_END_DELAY + 0.01)
	check_eq(main.state, Main.State.INTERMISSION, "then the market")
	check_eq(RunState.bosses_killed, 1, "counted")


func test_main_banner_names_the_boss_even_when_it_is_freed() -> void:
	_run_main(10)
	_step_director(WaveDirector.BOSS_TELEGRAPH_TIME + 0.1)
	var boss := main.wave_director.boss
	boss.kill()
	boss.free()
	main.wave_director._physics_process(DT)
	check_eq(main.state, Main.State.WAVE_END, "ended")
	check_eq(main.hud.banner_label.text, "Lich Commander Morvain defeated!", "the banner uses the definition")


func test_main_normal_wave_banner_is_unchanged() -> void:
	_run_main(9)
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	check_eq(main.hud.banner_label.text, "Wave cleared!", "normal")


func test_main_victory_when_vorthalax_dies_on_wave_25() -> void:
	_run_main(25)
	check_eq(main.hud.banner_label.text, "Final Wave", "the final wave banner")
	_step_director(WaveDirector.BOSS_TELEGRAPH_TIME + 0.1)
	var boss := main.wave_director.boss
	check(boss != null and boss.data.id == VORTHALAX, "Vor'thalax")
	_step_director(10.0)
	check_eq(main.state, Main.State.WAVE, "the clock does not end the final wave")
	boss.kill()
	main.wave_director._physics_process(DT)
	check_eq(main.hud.banner_label.text, "Victory!", "the victory banner")
	main._physics_process(Main.WAVE_END_DELAY + 0.01)
	check_eq(main.state, Main.State.GAME_OVER, "game over screen")
	check(main.victory, "victory")
	check(RunState.victory, "RunState says victory")


func test_format_position_has_one_decimal_and_no_float_noise() -> void:
	check_eq(Main.format_position(Vector3(-4.9, 0.0, -8.400001)), "(-4.9, 0.0, -8.4)", "rounded")
	check_eq(Main.format_position(Vector3(12.0, 1.26, 0.04)), "(12.0, 1.3, 0.0)", "padded to one decimal")


func test_defeat_with_a_living_boss_is_logged_with_its_hp_and_age() -> void:
	var b := _boss(VORTHALAX, Vector3.ZERO, 25)
	b.hp = b.max_hp * 0.37
	b._age = 61.5
	b.phase = 1
	var line := Main.boss_standing_text(b, 12)
	check(line.contains("Vor'thalax, the Burning Tyrant alive after 61.5 s"), "name and age: %s" % line)
	check(line.contains("37% HP left"), "the HP share: %s" % line)
	check(line.contains("phase 1, enrage level 0") and line.ends_with("12 downs so far"), "phase, enrage, downs: %s" % line)


func test_boss_arrival_log_line_formats_the_position() -> void:
	var b := _boss(MORVAIN, Vector3(-4.9, 0.0, -8.400001))
	var line := Main.boss_arrival_text(b, 10, 3)
	check(line.contains("at (-4.9, 0.0, -8.4):"), "clean coordinates: %s" % line)
	check(line.begins_with("boss Lich Commander Morvain arrived on wave 10"), "name and wave: %s" % line)
	check(line.ends_with("3 player(s)"), "players: %s" % line)
	check(not line.contains("0000"), "no float noise: %s" % line)


## The smoke run's wall-clock timeout (s) for [param waves] waves from [param first].
func _smoke_timeout_seconds(first: int, waves: int) -> float:
	main.options.start_wave = first
	main.options.waves = waves
	main.options.smoke = true
	main._start_smoke()
	main._smoke_running = false  # (only the deadline matters here)
	return float(main._smoke_deadline_msec - main._start_msec) / 1000.0


func test_smoke_deadline_allows_a_boss_wave_its_enrage_and_safety_kill() -> void:
	_run_main(9)
	main.options.smoke = true  # (the time scale is the smoke one)
	var scale := main.options.effective_time_scale()
	var normal := _smoke_timeout_seconds(9, 1)
	var boss_wave := _smoke_timeout_seconds(10, 1)
	var expected_gap := (RunState.wave_duration(10) - RunState.wave_duration(9) + Main.SMOKE_BOSS_ALLOWANCE) \
			/ scale * Main.SMOKE_TIMEOUT_FACTOR
	check_near(boss_wave - normal, expected_gap, 0.01, "a boss wave adds SMOKE_BOSS_ALLOWANCE to the budget")
	check(Main.SMOKE_BOSS_ALLOWANCE >= 90.0 + WaveDirector.SMOKE_BOSS_GRACE,
		"the allowance covers the enrage plus the safety grace")
	var normal_pair := _smoke_timeout_seconds(8, 2)
	var expected_pair := (RunState.wave_duration(8) + RunState.wave_duration(9)
			+ 2.0 * (Main.WAVE_END_DELAY + 0.5 + Main.SMOKE_INTERMISSION_ALLOWANCE)) / scale \
			* Main.SMOKE_TIMEOUT_FACTOR + Main.SMOKE_TIMEOUT_EXTRA
	check_near(normal_pair, expected_pair, 0.01, "two normal waves: no boss allowance")
	main.options.smoke = false


func test_main_tells_the_director_about_the_smoke_safety() -> void:
	_run_main(1)
	check(not main.wave_director.smoke_boss_timeout, "normal runs: off")
	main.options.smoke = true  # (like the existing flow tests: flipped after the run was built)
	main.start_run()
	check(main.wave_director.smoke_boss_timeout, "smoke mode: the safety is on")
	main.options.smoke = false
