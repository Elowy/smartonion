extends TestCase
## Mage ability Blink (GDD 3.2): teleport in the movement direction, arena clamp, short
## invulnerability, the second charge of the Band of the Blinking Star, the bots' escape.

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const DT := 1.0 / 60.0

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 33)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


func _mage(pos: Vector3 = Vector3.ZERO) -> Player:
	var p := Fakes.spawn_player(world, 0, &"mage", pos)
	p.abilities._physics_process(DT)
	return p


func _move(p: Player, v: Vector2) -> void:
	(p.slot.input as ScriptedInput).move = v


func _wear_band(p: Player) -> void:
	var item := ItemGenerator.from_unique(Db.uniques[&"band_of_the_blinking_star"], 1, false,
			RunState.rng, p.class_data)
	check(p.equipment.equip(item), "wear the band")


func _blink(p: Player) -> BlinkEffect:
	return p.abilities.effect_for(p.abilities.slots[1]) as BlinkEffect


func _enemy(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


func test_blink_moves_six_metres_in_the_movement_direction() -> void:
	var p := _mage(Vector3(1, 0, 2))
	_move(p, Vector2(1, 0))
	check(p.abilities.try_cast(1), "cast")
	check_near(p.global_position.distance_to(Vector3(7, 0, 2)), 0.0, 0.001, "6 m east")
	_move(p, Vector2(0, -1))
	p.abilities.set_cooldown(p.abilities.slots[1], 0.0)
	check(p.abilities.try_cast(1), "cast again after the cooldown")
	check_near(p.global_position.distance_to(Vector3(7, 0, -4)), 0.0, 0.001, "6 m north (-Z)")
	check_near(p.abilities.remaining(1), 6.0, 0.001, "6 s cooldown")


func test_blink_uses_the_facing_when_standing_still() -> void:
	var p := _mage()
	p.facing = Vector3(-1, 0, 0)
	check(p.abilities.try_cast(1), "cast")
	check_near(p.global_position.distance_to(Vector3(-6, 0, 0)), 0.0, 0.001, "6 m the way it looks")


func test_blink_gives_short_invulnerability() -> void:
	var p := _mage()
	_move(p, Vector2(1, 0))
	var hp := p.hp
	check(p.abilities.try_cast(1), "cast")
	check(p.invulnerable_left >= 0.39, "i-frames")
	p.take_damage(10.0)
	check_eq(p.hp, hp, "untouchable right after the blink")
	Fakes.step(p, 0.5)
	check_eq(p.invulnerable_left, 0.0, "short")


func test_blink_stays_inside_the_arena() -> void:
	var arena := EFakes.TestArena.new()
	world.add_child(arena)
	var edge := arena.get_bounds().end.x
	var p := _mage(Vector3(edge - 3.0, 0, 0))
	_move(p, Vector2(1, 0))
	check(p.abilities.try_cast(1), "cast")
	var margin := Player.RADIUS + Player.WALL_GAP
	check_near(p.global_position.x, edge - margin, 0.001, "stopped at the wall")
	check(arena.is_inside(p.global_position), "inside")
	# Wedged against the wall: nothing happens, nothing is spent.
	p.abilities.set_cooldown(p.abilities.slots[1], 0.0)
	check(not p.abilities.try_cast(1), "no room to blink")
	check_eq(p.abilities.remaining(1), 0.0, "no cooldown for a refused blink")
	_move(p, Vector2(0, -1))
	check(p.abilities.try_cast(1), "but along the wall it works")
	check(arena.is_inside(p.global_position), "still inside")
	arena.free()


func test_destination_math() -> void:
	var from := Vector3(2, 0, 3)
	check_near(BlinkEffect.destination(from, Vector3(0, 0, 1), 4.0).distance_to(Vector3(2, 0, 7)), 0.0, 0.001, "plain")
	check_near(BlinkEffect.destination(from, Vector3(3, 5, 4), 5.0).distance_to(Vector3(5, 0, 7)), 0.0, 0.001, "flat and normalised")
	check_eq(BlinkEffect.destination(from, Vector3.ZERO, 4.0), from, "no direction, no move")


func test_one_charge_without_the_band() -> void:
	var p := _mage()
	_move(p, Vector2(1, 0))
	check(p.abilities.try_cast(1), "first blink")
	Fakes.step(p.abilities, 0.1)
	check(not p.abilities.try_cast(1), "no second one")
	check_eq(_blink(p).charges_max(), 1, "one charge")
	check_eq(_blink(p).charges_available(), 0, "none left")
	Fakes.step(p.abilities, 6.0)
	check_eq(_blink(p).charges_available(), 1, "back after the cooldown")
	check(p.abilities.try_cast(1), "ready again")


func test_band_of_the_blinking_star_adds_a_charge() -> void:
	var p := _mage()
	_wear_band(p)
	_move(p, Vector2(1, 0))
	check_eq(p.abilities.build_context(p.abilities.slots[1]).num("charges"), 2.0, "params say 2 charges")
	check(p.abilities.try_cast(1), "first blink")
	Fakes.step(p.abilities, 0.1)
	check_eq(_blink(p).charges_max(), 2, "two charges")
	check_eq(_blink(p).charges_available(), 1, "one left")
	check(p.abilities.is_ready(1), "the HUD sees it ready")
	check_eq(p.abilities.remaining(1), 0.0, "no cooldown while a charge is left")
	check(p.abilities.try_cast(1), "second blink at once")
	Fakes.step(p.abilities, 0.1)
	check(not p.abilities.try_cast(1), "third: nothing left")
	check_eq(_blink(p).charges_available(), 0, "empty")
	check(p.abilities.remaining(1) > 5.0 and p.abilities.remaining(1) <= 6.0, "the sweep shows the next charge")
	check(not p.abilities.is_ready(1), "not ready")
	Fakes.step(p.abilities, 6.0)
	check_eq(_blink(p).charges_available(), 1, "one charge after 6 s")
	check(p.abilities.try_cast(1), "blink")
	Fakes.step(p.abilities, 0.1)
	check(not p.abilities.try_cast(1), "only one came back")
	Fakes.step(p.abilities, 12.0)
	check_eq(_blink(p).charges_available(), 2, "both back after the recharge")
	check_eq(p.abilities.remaining(1), 0.0, "ready")


func test_charges_recharge_faster_with_cooldown_reduction() -> void:
	var p := _mage()
	_wear_band(p)
	p.stats.set_source(&"cdr", {Stats.COOLDOWN_REDUCTION: 50.0})
	_move(p, Vector2(1, 0))
	p.abilities.try_cast(1)
	Fakes.step(p.abilities, 0.1)
	p.abilities.try_cast(1)
	Fakes.step(p.abilities, 3.2)
	check_eq(_blink(p).charges_available(), 1, "3 s per charge at 50% Cooldown Reduction")


func test_new_wave_refills_the_charges() -> void:
	var p := _mage()
	_wear_band(p)
	_move(p, Vector2(1, 0))
	p.abilities.try_cast(1)
	Fakes.step(p.abilities, 0.1)
	p.abilities.try_cast(1)
	Fakes.step(p.abilities, 0.1)
	check_eq(_blink(p).charges_available(), 0, "spent")
	p.begin_wave()
	Fakes.step(p.abilities, DT)
	check_eq(_blink(p).charges_available(), 2, "full again")
	check(p.abilities.is_ready(1), "ready")


func test_bot_blinks_out_of_a_crowd_only() -> void:
	var p := _mage()
	var ability := p.abilities.slots[1]
	var effect := _blink(p)
	_move(p, Vector2(1, 0))
	check(not effect.wants_auto_cast(p.abilities.build_context(ability)), "alone")
	_enemy(Vector3(-1.0, 0, 0.2))
	check(not effect.wants_auto_cast(p.abilities.build_context(ability)), "one enemy is no reason")
	_enemy(Vector3(-1.2, 0, -0.5))
	check(effect.wants_auto_cast(p.abilities.build_context(ability)), "two adjacent enemies, free way")
	# The jump would land in more enemies.
	for i in 3:
		_enemy(Vector3(6.0 + i * 0.3, 0, 0))
	check(not effect.wants_auto_cast(p.abilities.build_context(ability)), "not into a worse crowd")
	_move(p, Vector2(0, 1))
	check(effect.wants_auto_cast(p.abilities.build_context(ability)), "another way out")


func test_bot_blinks_away_from_a_single_enemy_when_hurt() -> void:
	var p := _mage()
	var ability := p.abilities.slots[1]
	_move(p, Vector2(1, 0))
	_enemy(Vector3(-1.0, 0, 0))
	check(not _blink(p).wants_auto_cast(p.abilities.build_context(ability)), "healthy")
	p.hp = p.max_hp() * 0.3
	check(_blink(p).wants_auto_cast(p.abilities.build_context(ability)), "hurt")


func test_bot_does_not_blink_away_from_a_revive() -> void:
	var p := _mage()
	var ability := p.abilities.slots[1]
	var effect := _blink(p)
	_move(p, Vector2(1, 0))
	_enemy(Vector3(-1.0, 0, 0.2))
	_enemy(Vector3(-1.2, 0, -0.5))
	check(effect.wants_auto_cast(p.abilities.build_context(ability)), "baseline: two adjacent enemies")
	var mate := Fakes.spawn_player(world, 1, &"warrior", Vector3(0.5, 0, 1.0))
	mate._go_down()
	check(p.is_reviving(), "next to a downed teammate")
	check(not effect.wants_auto_cast(p.abilities.build_context(ability)), "no blink while reviving")
	p.hp = p.max_hp() * 0.3
	check(not effect.wants_auto_cast(p.abilities.build_context(ability)), "not even when hurt")
	p.abilities.auto_cast = true
	Fakes.step(p.abilities, 0.3)
	check(p.global_position.length() < 0.01, "the bot stayed at the revive")
	mate.revive()
	check(effect.wants_auto_cast(p.abilities.build_context(ability)), "blinks again once the revive is done")


func test_bot_auto_cast_runs_through_the_runner() -> void:
	var p := _mage()
	p.abilities.auto_cast = true
	_move(p, Vector2(1, 0))
	_enemy(Vector3(-1.0, 0, 0.2))
	_enemy(Vector3(-1.2, 0, -0.5))
	Fakes.step(p.abilities, 0.3)
	check(p.global_position.x > 5.0, "the bot blinked away (x = %f)" % p.global_position.x)


func test_cooldown_mods_apply_to_blink_and_its_recharge() -> void:
	var p := _mage()
	var item := ItemInstance.new()
	item.slot_type = Items.SlotType.RING
	item.armor_type = Items.NO_ARMOR
	item.unique_effect = &"ability_mod"
	item.unique_params = {"ability": "blink", "mods": {"cooldown_add": -2.0, "charges_add": 1.0}}
	check(p.equipment.equip(item), "wear it")
	_move(p, Vector2(1, 0))
	check_near(p.abilities.cooldown_of(p.abilities.slots[1]), 4.0, 0.001, "4 s with the mod")
	p.abilities.try_cast(1)
	Fakes.step(p.abilities, 0.1)
	p.abilities.try_cast(1)
	Fakes.step(p.abilities, 4.1)
	check_eq(_blink(p).charges_available(), 1, "a charge per 4 s")
