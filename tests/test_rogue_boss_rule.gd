extends "res://tests/talents_rogue_base.gd"
## Final balance 2: Fan of Knives against a boss (RogueBlade.BOSS_REPEAT_MULT / BOSS_ENVENOM_MULT). A boss is one
## big target: of the knives of one cast that hit the same boss only the first deals its full damage, the others
## 40%, and an Envenom burst on a boss is two thirds of the normal one. Ordinary enemies are untouched.


## Fan Of Knives hits on [param e] as the damage log, after one cast and a flight.
func _fan_log(p: Player, e: Fakes.FakeEnemy) -> Array[float]:
	_throw_fan(p)
	_fly(p)
	return e.fake_damage_log.duplicate()


func test_the_constants_are_the_tuned_numbers() -> void:
	check_eq(RogueBlade.BOSS_REPEAT_MULT, 0.4, "a further knife on the same boss deals 40%")
	check_near(RogueBlade.BOSS_ENVENOM_MULT, 2.0 / 3.0, 0.00001, "an Envenom burst on a boss is two thirds")


func test_a_normal_big_enemy_takes_every_knife_in_full() -> void:
	var p := _rogue()
	var big := Fakes.spawn_enemy(world, Vector3(0, 0, -2.6), 1.6)
	EnemyGrid.mark_dirty()
	var log := _fan_log(p, big)
	check(log.size() >= 3, "a wide enemy takes several knives (%d)" % log.size())
	for d in log:
		check_near(d, log[0], 0.0001, "every knife deals the same")


func test_a_boss_takes_the_first_knife_in_full_and_the_rest_at_40_percent() -> void:
	var p := _rogue()
	var big := Fakes.spawn_enemy(world, Vector3(0, 0, -2.6), 1.6)
	EnemyGrid.mark_dirty()
	var reference := _fan_log(p, big)
	var full := reference[0]
	_clear_knives()
	var boss := Fakes.spawn_enemy(world, Vector3(0, 0, 2.6), 1.6)
	boss.fake_boss = true
	big.fake_dead = true  # (out of the way: the second fan's knives all go to the boss)
	EnemyGrid.mark_dirty()
	var log := _fan_log(p, boss)
	check(log.size() >= 3, "the boss takes several knives too (%d)" % log.size())
	check_near(log[0], full, 0.0001, "the first knife in full")
	for i in range(1, log.size()):
		check_near(log[i], full * RogueBlade.BOSS_REPEAT_MULT, 0.0001, "knife %d: 40%%" % (i + 1))


func test_every_cast_counts_afresh() -> void:
	var p := _rogue()
	var boss := Fakes.spawn_enemy(world, Vector3(0, 0, -2.6), 1.6)
	boss.fake_boss = true
	EnemyGrid.mark_dirty()
	var first := _fan_log(p, boss)
	boss.fake_damage_log.clear()
	var second := _fan_log(p, boss)
	check_near(second[0], first[0], 0.0001, "the next fan opens with a full knife again")
	if second.size() > 1:
		check_near(second[1], first[0] * RogueBlade.BOSS_REPEAT_MULT, 0.0001, "and goes on at 40%")


func test_two_targets_are_counted_apart() -> void:
	var p := _rogue()
	var boss := Fakes.spawn_enemy(world, Vector3(0, 0, -2.6), 1.6)
	boss.fake_boss = true
	var other := Fakes.spawn_enemy(world, Vector3(0, 0, 2.6), 1.6)
	EnemyGrid.mark_dirty()
	_throw_fan(p)
	_fly(p)
	check(boss.fake_damage_log.size() >= 2 and other.fake_damage_log.size() >= 2, "both take several knives")
	check_near(other.fake_damage_log[0], boss.fake_damage_log[0], 0.0001, "each opens with a full knife")
	check_near(other.fake_damage_log[1], other.fake_damage_log[0], 0.0001, "the normal enemy keeps taking full knives")
	check_near(boss.fake_damage_log[1], boss.fake_damage_log[0] * RogueBlade.BOSS_REPEAT_MULT, 0.0001, "the boss does not")


func test_envenom_on_a_boss_is_two_thirds_of_the_burst() -> void:
	var p := _rogue()
	_add(p, "assassination", "malice", 3)
	_add(p, "assassination", "improved_poisons", 3)
	_add(p, "assassination", "envenom")
	var mastery := _mastery(p)
	var boss := Fakes.spawn_enemy(world, Vector3(0, 0, -3.0))
	boss.fake_boss = true
	var normal := Fakes.spawn_enemy(world, Vector3(0, 0, 3.0))
	EnemyGrid.mark_dirty()
	for i in 3:
		mastery.poison(boss, 12.0)
		mastery.poison(normal, 12.0)
	_throw_fan(p)
	_fly(p)
	check_near(normal.fake_damage_log[0], 3.0 * 12.0 * 1.5, 0.0001, "a normal enemy takes the whole 150% burst")
	check_near(boss.fake_damage_log[0], 3.0 * 12.0 * 1.5 * RogueBlade.BOSS_ENVENOM_MULT, 0.0001, "the boss takes two thirds of it")
