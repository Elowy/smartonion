extends TestCase
## Hunter abilities (M8, GDD 3.7) – Arrow Fan, Backstep, Long Shot, Arrow Hail, Quick Draw, Play Dead,
## Blast Snare, Hunt Signal: casting, damage and its source (weapon hit / ability / pet), ranks,
## Rank V specialisations and clean-up. The companion itself: test_class_hunter_companion.gd.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D
var hunter: Player


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 41)
	world = Fakes.make_world(tree)
	hunter = Fakes.spawn_player(world, 0, &"hunter")
	# Deterministic damage: no random crits / dodges unless a test asks for them.
	hunter.stats.set_source(&"test", {Stats.CRIT: -500.0, Stats.DODGE: -500.0})
	hunter.facing = Vector3.FORWARD


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	hunter = null
	PlayerManager.clear()
	EnemyGrid.mark_dirty()


# --- Helpers ---------------------------------------------------------------------------------

func _w(school: StringName = &"physical") -> float:
	return GeneralKit.weapon_damage(hunter, school)


func _enemy(pos: Vector3, radius: float = 0.45) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos, radius)
	EnemyGrid.mark_dirty()
	return e


func _learn(id: StringName, rank: int = 1, spec: int = -1) -> int:
	var i := hunter.abilities.learn(Db.get_ability(id))
	check(i >= 0, "%s learned" % id)
	for r in range(1, rank):
		hunter.abilities.rank_up(id)
	if spec >= 0:
		check(hunter.abilities.set_spec(id, spec), "%s spec %d" % [id, spec])
	return i


func _core(id: StringName, rank: int = 1, spec: int = -1) -> int:
	for r in range(1, rank):
		hunter.abilities.rank_up(id)
	if spec >= 0:
		check(hunter.abilities.set_spec(id, spec), "%s spec %d" % [id, spec])
	return hunter.abilities.slot_of(id)


func _power(id: StringName) -> float:
	return float(hunter.abilities.params_for(Db.get_ability(id))["power"])


func _effect(id: StringName) -> AbilityEffect:
	return HunterKit.effect_of(hunter, id)


func _arrows() -> Array[HunterArrow]:
	var out: Array[HunterArrow] = []
	for node in tree.get_nodes_in_group(&"projectiles"):
		var a := node as HunterArrow
		if a != null and a.attacker == hunter and not a.is_queued_for_deletion():
			out.append(a)
	return out


func _fly(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		for a in _arrows():
			a.advance(DT)
		t += DT


func _run(seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		hunter.abilities._physics_process(DT)
		t += DT


func _companion() -> HunterCompanion:
	return (hunter.abilities.mastery as HunterMastery).ensure_companion()


func _clear_arrows() -> void:
	for a in _arrows():
		a.free()


# --- Arrow Fan -------------------------------------------------------------------------------

func test_arrow_fan_looses_five_weapon_arrows_in_a_fan() -> void:
	var target := _enemy(Vector3(0, 0, -5))
	var slot := hunter.abilities.slot_of(&"arrow_fan")
	check_eq(slot, 0, "RT")
	check(hunter.abilities.try_cast(slot), "cast")
	var arrows := _arrows()
	check_eq(arrows.size(), 5, "five arrows")
	check_eq(HunterKit.focus(hunter).value, 60.0, "40 Focus spent")
	var angles: Array[float] = []
	for a in arrows:
		check_eq(a.team, Projectile.TEAM_PLAYERS, "player arrow")
		check(a.weapon == hunter.main_hand and a.is_extra, "weapon hit, no extra-attack chains")
		check(a.proc_gate == arrows[0].proc_gate and a.proc_gate != null, "one on-hit proc roll per fan")
		check_near(a.damage, _w() * 1.2, 0.001, "120% of the weapon hit W")
		check(not a.is_crit, "no crit at -500% crit")
		check_near(a.max_range, 11.0, 0.001, "range")
		check_near(a.speed, 24.0, 0.001, "speed")
		check_eq(a.pierce, 0, "no pierce")
		check_near(a.global_position.y, Player.CHEST_HEIGHT, 0.001, "chest height")
		angles.append(snappedf(rad_to_deg(Vector3.FORWARD.signed_angle_to(a.direction, Vector3.UP)), 0.1))
	angles.sort()
	check_eq(angles, [-25.0, -12.5, 0.0, 12.5, 25.0] as Array[float], "a 50 degree fan centred on the nearest enemy")
	_fly(0.5)
	check_eq(target.fake_hits(), 1, "the middle arrow hits the enemy ahead")
	check_near(target.fake_damage_log[0], _w() * 1.2, 0.001, "for 120% W")
	check_eq(target.fake_attacker_log[0], hunter, "credited to the Hunter")


func test_arrow_fan_needs_a_target_and_focus() -> void:
	var slot := 0
	check(not hunter.abilities.try_cast(slot), "no enemy in range: refused")
	check_eq(HunterKit.focus(hunter).value, 100.0, "and nothing spent")
	_enemy(Vector3(0, 0, -5))
	HunterKit.focus(hunter).set_value(39.0)
	check(not hunter.abilities.try_cast(slot), "39 Focus is not enough")
	HunterKit.focus(hunter).set_value(40.0)
	check(hunter.abilities.try_cast(slot), "40 is")
	check_near(HunterKit.focus(hunter).value, 0.0, 0.001, "all spent")
	_enemy(Vector3(0, 0, -12))
	EnemyGrid.mark_dirty()


func test_arrow_fan_is_centred_on_the_nearest_enemy_not_the_facing() -> void:
	_enemy(Vector3(4, 0, 0))
	_enemy(Vector3(-6, 0, 0))
	check(hunter.abilities.try_cast(0), "cast")
	var centre := 0.0
	for a in _arrows():
		centre += a.direction.x
	check_near(centre / 5.0, 1.0 * cos(0.0), 0.05, "aimed at the nearer enemy on the right")


func test_arrow_fan_hits_are_weapon_hits() -> void:
	hunter.stats.set_source(&"test", {Stats.CRIT: 500.0})
	var e := _enemy(Vector3(0, 0, -4))
	check(hunter.abilities.try_cast(0), "cast")
	var crit_mult := CombatMath.crit_multiplier(hunter.main_hand, hunter.stats)
	for a in _arrows():
		check(a.is_crit, "crits at 100% crit")
		check_near(a.damage, _w() * 1.2 * crit_mult, 0.001, "crit damage")
	_fly(0.5)
	check_eq(e.fake_hits(), 1, "one arrow")
	check(e.fake_crit_log[0], "as a crit")


func test_arrow_fan_rank_three_and_extra_projectile_add_arrows_pierce_adds_pierce() -> void:
	_enemy(Vector3(0, 0, -5))
	_core(&"arrow_fan", 3)
	check(hunter.abilities.try_cast(0), "cast")
	check_eq(_arrows().size(), 7, "Rank III: +2 arrows")
	_clear_arrows()
	HunterKit.focus(hunter).set_value(100.0)
	hunter.abilities.set_cooldown(Db.get_ability(&"arrow_fan"), 0.0)
	hunter.stats.set_source(&"bonus", {Stats.EXTRA_PROJECTILE: 2.0, Stats.PIERCE: 1.0})
	check(hunter.abilities.try_cast(0), "cast again")
	check_eq(_arrows().size(), 9, "Extra Projectile adds arrows")
	for a in _arrows():
		check_eq(a.pierce, 1, "Pierce adds pierce")


func test_arrow_fan_skewering_fan_pierces_and_flies_further() -> void:
	var near := _enemy(Vector3(0, 0, -3))
	var far := _enemy(Vector3(0, 0, -6))
	_core(&"arrow_fan", 5, 0)
	check(hunter.abilities.try_cast(0), "cast")
	for a in _arrows():
		check_eq(a.pierce, 1, "pierces one more enemy")
		check_near(a.max_range, 14.0, 0.001, "and flies 3 m further")
	_fly(0.7)
	check(near.fake_hits() >= 1, "the first enemy")
	check(far.fake_hits() >= 1, "and the one behind it")
	check_eq(far.fake_hits(), 1, "the middle arrow went through the first to the second")


func test_arrow_fan_echo_draw_follows_with_a_second_fan_and_stops_when_down() -> void:
	_enemy(Vector3(0, 0, -5))
	_core(&"arrow_fan", 5, 1)
	check(hunter.abilities.try_cast(0), "cast")
	check_eq(_arrows().size(), 7, "the first fan (Rank III: seven arrows)")
	_run(0.3)
	check_eq(_arrows().size(), 14, "a second fan 0.25 s later")
	_clear_arrows()
	HunterKit.focus(hunter).set_value(100.0)
	hunter.abilities.set_cooldown(Db.get_ability(&"arrow_fan"), 0.0)
	check(hunter.abilities.try_cast(0), "cast again")
	hunter.downed = true
	hunter.downed_changed.emit(true)
	hunter.downed = false
	_run(0.5)
	check_eq(_arrows().size(), 7, "a Hunter that went down looses no late volley")


func test_arrow_fan_works_with_a_melee_main_hand() -> void:
	var sword := Db.weapons[&"sword"]
	hunter.equip_weapons(sword, null)
	_enemy(Vector3(0, 0, -5))
	check(hunter.abilities.try_cast(0), "cast")
	check_eq(_arrows().size(), 5, "the arrows leave the quiver by hand")
	for a in _arrows():
		check(a.weapon == sword, "weapon hits of the sword")
		check_near(a.damage, _w() * 1.2, 0.001, "same maths")


func test_arrow_fan_boss_takes_one_full_arrow_and_the_rest_weaker() -> void:
	var boss := _enemy(Vector3(0, 0, -2.0), 1.2)
	boss.fake_boss = true
	check(hunter.abilities.try_cast(0), "cast")
	_fly(0.4)
	check(boss.fake_hits() >= 2, "several arrows hit the wide boss")
	check_near(boss.fake_damage_log[0], _w() * 1.2, 0.001, "the first deals its full damage")
	for i in range(1, boss.fake_hits()):
		check_near(boss.fake_damage_log[i], _w() * 1.2 * HunterArrow.BOSS_REPEAT_MULT, 0.001, "the others %d%%" % int(HunterArrow.BOSS_REPEAT_MULT * 100))


func test_arrow_fan_auto_cast_rule() -> void:
	var fan := _effect(&"arrow_fan") as HunterArrowFan
	var ctx := hunter.abilities.build_context(Db.get_ability(&"arrow_fan"))
	check(not fan.wants_auto_cast(ctx), "nobody around")
	var first := _enemy(Vector3(0, 0, -5))
	ctx = hunter.abilities.build_context(Db.get_ability(&"arrow_fan"))
	HunterKit.focus(hunter).set_value(80.0)
	check(not fan.wants_auto_cast(ctx), "one enemy, Focus below 90")
	HunterKit.focus(hunter).set_value(90.0)
	check(fan.wants_auto_cast(ctx), "one enemy within 8 m and Focus >= 90")
	HunterKit.focus(hunter).set_value(60.0)
	_enemy(Vector3(1.5, 0, -6))
	ctx = hunter.abilities.build_context(Db.get_ability(&"arrow_fan"))
	check(fan.wants_auto_cast(ctx), "two enemies in the cone")
	first.global_position = Vector3(0, 0, -8.8)
	EnemyGrid.mark_dirty()
	ctx = hunter.abilities.build_context(Db.get_ability(&"arrow_fan"))
	check(not fan.wants_auto_cast(ctx), "the cone only counts enemies within 8 m")


# --- Backstep --------------------------------------------------------------------------------

func test_backstep_leaps_away_from_the_nearest_enemy() -> void:
	var e := _enemy(Vector3(0, 0, -2))
	var slot := hunter.abilities.slot_of(&"backstep")
	check_eq(slot, 1, "LT")
	check(hunter.abilities.try_cast(slot), "cast")
	var step := _effect(&"backstep") as HunterBackstep
	check(step.is_dashing(), "leaping")
	check(hunter.invulnerable_left >= 0.19, "0.2 s of invulnerability")
	_run(0.1)
	check(hunter.global_position.z > 0.5 and hunter.global_position.z < 5.0, "half way")
	_run(0.2)
	check(not step.is_dashing(), "landed")
	check_near(hunter.global_position.z, 5.0, 0.05, "5 m straight away from the enemy")
	check_near(hunter.global_position.x, 0.0, 0.05, "on the line")
	check_near(hunter.abilities.remaining(slot), 8.0 - 0.3, 0.05, "8 s cooldown (0.3 s ago)")
	check_eq(e.fake_hits(), 0, "no damage without a spec")


func test_backstep_without_an_enemy_leaps_opposite_the_facing() -> void:
	hunter.facing = Vector3(1, 0, 0)
	check(hunter.abilities.try_cast(1), "cast")
	_run(0.4)
	check_near(hunter.global_position.x, -5.0, 0.05, "opposite the facing")


func test_backstep_slows_enemies_around_the_spot_it_left() -> void:
	var close := _enemy(Vector3(0, 0, -2))
	var far := _enemy(Vector3(5, 0, -2.5))
	check(hunter.abilities.try_cast(1), "cast")
	check_eq(close.slow_pct, 40.0, "40% slow")
	check_near(close.slow_left, 2.0, 0.001, "for 2 s")
	check_eq(far.slow_pct, 0.0, "an enemy beyond 3 m is not slowed")


func test_backstep_rank_three_has_a_second_charge() -> void:
	_enemy(Vector3(0, 0, -2))
	_core(&"backstep", 3)
	check_eq(hunter.abilities.charges_max(Db.get_ability(&"backstep")), 2, "two charges")
	check(hunter.abilities.try_cast(1), "first leap")
	_run(0.4)
	check(hunter.abilities.try_cast(1), "second leap straight after")
	_run(0.4)
	check(not hunter.abilities.try_cast(1), "no third")


func test_backstep_parting_volley_looses_three_arrows_as_it_lands() -> void:
	_enemy(Vector3(0, 0, -2))
	_core(&"backstep", 5, 1)
	check(hunter.abilities.try_cast(1), "cast")
	check_eq(_arrows().size(), 0, "nothing while leaping")
	_run(0.4)
	var arrows := _arrows()
	check_eq(arrows.size(), 3, "three arrows")
	for a in arrows:
		check_near(a.damage, _w() * _power(&"backstep"), 0.001, "100% W x power each")
		check(a.weapon == hunter.main_hand, "weapon hits")


func test_backstep_caltrop_trail_slows_what_crosses_it() -> void:
	_enemy(Vector3(0, 0, -2))
	_core(&"backstep", 5, 0)
	check(hunter.abilities.try_cast(1), "cast")
	var step := _effect(&"backstep") as HunterBackstep
	check(step.last_trail.size() >= 2, "caltrop patches along the leap")
	for area in step.last_trail:
		check_near(area.duration, 3.0, 0.001, "3 s")
		check_near(area.slow_pct, 40.0 * _power(&"backstep"), 0.001, "40% slow x power")
		check(area.owner_player == hunter, "the Hunter's")


func test_backstep_is_refused_against_a_wall_and_stops_when_down() -> void:
	hunter.facing = Vector3.FORWARD
	_enemy(Vector3(0, 0, -2))
	check(hunter.abilities.try_cast(1), "cast")
	hunter.downed = true
	hunter.downed_changed.emit(true)
	var step := _effect(&"backstep") as HunterBackstep
	check(not step.is_dashing(), "going down ends the leap")
	hunter.downed = false


func test_backstep_auto_cast_rule() -> void:
	var step := _effect(&"backstep") as HunterBackstep
	var ctx := hunter.abilities.build_context(Db.get_ability(&"backstep"))
	check(not step.wants_auto_cast(ctx), "nobody around")
	var a := _enemy(Vector3(0, 0, -2.5))
	check(not step.wants_auto_cast(ctx), "one enemy, healthy")
	hunter.hp = hunter.max_hp() * 0.4
	check(not step.wants_auto_cast(ctx), "hurt but the enemy is 2.5 m away")
	a.global_position = Vector3(0, 0, -1.8)
	EnemyGrid.mark_dirty()
	check(step.wants_auto_cast(ctx), "hurt with an enemy within 2 m")
	hunter.hp = hunter.max_hp()
	check(not step.wants_auto_cast(ctx), "healthy again")
	_enemy(Vector3(1, 0, -1))
	check(step.wants_auto_cast(ctx), "two enemies within 3 m")


# --- Long Shot -------------------------------------------------------------------------------

func test_long_shot_takes_aim_then_looses_a_piercing_heavy_arrow() -> void:
	var near := _enemy(Vector3(0, 0, -4))
	var far := _enemy(Vector3(0, 0, -8))
	var slot := _learn(&"long_shot")
	check_eq(slot, 2, "an Active slot")
	check(hunter.abilities.try_cast(slot), "cast")
	var shot := _effect(&"long_shot") as HunterLongShot
	check(shot.is_winding_up(), "aiming")
	check_eq(_arrows().size(), 0, "no arrow yet")
	check(hunter.get_node_or_null("AimCharge") != null, "the aim charge shows")
	check_near(hunter.abilities.remaining(slot), 9.0, 0.001, "the cooldown starts with the aiming")
	_run(0.5)
	check_eq(_arrows().size(), 0, "still aiming after 0.5 s")
	_run(0.25)
	var arrows := _arrows()
	check_eq(arrows.size(), 1, "one arrow after 0.7 s")
	check(not shot.is_winding_up(), "done aiming")
	check_near(arrows[0].damage, _w() * 3.2, 0.001, "320% W")
	check_eq(arrows[0].pierce, 99, "pierces everything on the line")
	check(arrows[0].weapon == hunter.main_hand, "a weapon hit")
	check(hunter.get_node_or_null("AimCharge") == null, "the aim charge is gone")
	_fly(1.0)
	check_eq(near.fake_hits(), 1, "hits the first")
	check_eq(far.fake_hits(), 1, "and the second on the line")
	check_near(near.fake_damage_log[0], _w() * 3.2, 0.001, "full damage on both")


func test_long_shot_aims_at_the_line_holding_the_most_enemies() -> void:
	# Three enemies in a row to the right, two ahead, one nearer to the left.
	for x in [3.0, 6.0, 9.0]:
		_enemy(Vector3(x, 0, 0))
	for z in [-3.0, -6.0]:
		_enemy(Vector3(0, 0, z))
	_enemy(Vector3(-2, 0, 0.5))
	var lines := HunterLongShot.best_lines(hunter, 14.0, 1)
	check_eq(lines.size(), 1, "one line asked")
	check_eq(lines[0]["count"], 3, "three enemies on it")
	check_near((lines[0]["dir"] as Vector3).dot(Vector3.RIGHT), 1.0, 0.001, "the row to the right")
	var two := HunterLongShot.best_lines(hunter, 14.0, 2)
	check_eq(two.size(), 2, "a next-best line")
	check_eq(two[1]["count"], 2, "with the two ahead")
	check_near((two[1]["dir"] as Vector3).dot(Vector3.FORWARD), 1.0, 0.001, "ahead")


func test_long_shot_line_ties_go_to_the_enemy_with_the_most_health() -> void:
	var weak := _enemy(Vector3(4, 0, 0))
	var strong := _enemy(Vector3(-4, 0, 0))
	strong.hp = 1000.0
	weak.hp = 400.0
	var lines := HunterLongShot.best_lines(hunter, 14.0, 1)
	check_near((lines[0]["dir"] as Vector3).dot(Vector3.LEFT), 1.0, 0.001, "the stronger enemy's line")


func test_long_shot_rank_three_second_arrow_takes_the_next_best_line() -> void:
	for x in [3.0, 6.0]:
		_enemy(Vector3(x, 0, 0))
	_enemy(Vector3(0, 0, -5))
	var slot := _learn(&"long_shot", 3)
	check(hunter.abilities.try_cast(slot), "cast")
	_run(0.8)
	var arrows := _arrows()
	check_eq(arrows.size(), 2, "two arrows")
	var dots: Array[float] = []
	for a in arrows:
		dots.append(snappedf(a.direction.dot(Vector3.RIGHT), 0.01))
	dots.sort()
	check_eq(dots, [0.0, 1.0] as Array[float], "one along each line")


func test_long_shot_with_nobody_in_reach_flies_along_the_facing() -> void:
	var e := _enemy(Vector3(0, 0, -5))
	var slot := _learn(&"long_shot")
	check(hunter.abilities.try_cast(slot), "cast")
	e.global_position = Vector3(0, 0, -30)
	EnemyGrid.mark_dirty()
	hunter.facing = Vector3.RIGHT
	_run(0.8)
	var arrows := _arrows()
	check_eq(arrows.size(), 1, "an arrow anyway")
	check_near(arrows[0].direction.dot(Vector3.RIGHT), 1.0, 0.001, "along the facing")


func test_long_shot_snap_shot_is_instant_with_a_shorter_cooldown() -> void:
	_enemy(Vector3(0, 0, -5))
	var slot := _learn(&"long_shot", 5, 0)
	check(hunter.abilities.try_cast(slot), "cast")
	check_eq(_arrows().size(), 2, "loosed at once (Rank III: two arrows)")
	check_near(hunter.abilities.remaining(slot), 9.0 * 0.8 * 0.7, 0.001, "Rank IV cooldown, 30% shorter")


func test_long_shot_finishing_arrow_hits_wounded_enemies_harder() -> void:
	var healthy := _enemy(Vector3(0, 0, -4))
	var wounded := _enemy(Vector3(0, 0, -7))
	wounded.hp = 300.0
	var slot := _learn(&"long_shot")
	hunter.bonuses.set_effects(PlayerBonuses.SOURCE_TALENTS, [{"kind": "ability", "match": {"id": "long_shot"},
			"mods": {"execute_bonus_add": 60.0}}] as Array[Dictionary])
	check_eq(_effect(&"long_shot") != null, true, "effect")
	hunter.abilities.try_cast(slot)
	_run(0.8)
	_fly(1.0)
	check_near(healthy.fake_damage_log[0], _w() * 3.2, 0.001, "a healthy enemy takes the normal damage")
	check_near(wounded.fake_damage_log[0], _w() * 3.2 * 1.6, 0.001, "an enemy below 35% takes 60% more")


func test_long_shot_rending_shaft_makes_the_struck_bleed() -> void:
	var e := _enemy(Vector3(0, 0, -4))
	var slot := _learn(&"long_shot", 5, 1)
	hunter.abilities.set_cooldown(Db.get_ability(&"long_shot"), 0.0)
	var w := _w()
	var power: float = hunter.abilities.params_for(Db.get_ability(&"long_shot"))["power"]
	hunter.abilities.try_cast(slot)
	_run(0.8)
	_fly(0.5)
	check_eq(e.fake_hits(), 2, "both arrows of Rank III fly the only line")
	var bleed := HunterBleed.find(e, hunter, &"long_shot")
	check(bleed != null, "a bleed on the enemy")
	if bleed == null:
		return
	var total := w * 0.8 * power * 2.0
	check_near(bleed.remaining(), total, 0.001, "80% W x power over 4 s per arrow, added up")
	check_eq(bleed.source, &"dot", "damage over time")
	# It ticks every 0.5 s through deal_raw.
	var before := e.fake_hits()
	for i in 4 * 60 + 10:
		bleed._physics_process(DT)
	check_eq(e.fake_hits() - before, 8, "eight ticks")
	var dealt := 0.0
	for i in range(before, e.fake_hits()):
		dealt += e.fake_damage_log[i]
	check_near(dealt, total, 0.01, "the whole wound")


func test_long_shot_is_cancelled_by_going_down_and_by_the_wave() -> void:
	_enemy(Vector3(0, 0, -5))
	var slot := _learn(&"long_shot")
	var shot := _effect(&"long_shot") as HunterLongShot
	hunter.abilities.try_cast(slot)
	hunter.downed = true
	hunter.downed_changed.emit(true)
	hunter.downed = false
	check(not shot.is_winding_up(), "going down cancels it")
	_run(1.0)
	check_eq(_arrows().size(), 0, "nothing flies")
	hunter.abilities.set_cooldown(Db.get_ability(&"long_shot"), 0.0)
	hunter.abilities.try_cast(slot)
	hunter.abilities.end_wave()
	check(not shot.is_winding_up(), "the wave end cancels it")
	check(hunter.get_node_or_null("AimCharge") == null, "and the aim look")


func test_long_shot_auto_cast_rule() -> void:
	var slot := _learn(&"long_shot")
	var shot := _effect(&"long_shot") as HunterLongShot
	var ability := Db.get_ability(&"long_shot")
	_enemy(Vector3(0, 0, -5))
	check(not shot.wants_auto_cast(hunter.abilities.build_context(ability)), "one plain enemy")
	var elite := _enemy(Vector3(3, 0, -5))
	elite.fake_boss = true
	check(shot.wants_auto_cast(hunter.abilities.build_context(ability)), "a boss within 12 m")
	elite.free()
	EnemyGrid.mark_dirty()
	_enemy(Vector3(0, 0, -7))
	check(not shot.wants_auto_cast(hunter.abilities.build_context(ability)), "two on a line")
	_enemy(Vector3(0, 0, -9))
	check(shot.wants_auto_cast(hunter.abilities.build_context(ability)), "three on a line")
	check(slot >= 0, "slotted")
