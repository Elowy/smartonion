extends TestCase
## M6 METER, the recorders: every call site feeds the per-slot damage-meter record of RunState
## (healing credited to the healer, absorbs credited to the caster of the shield, damage taken after
## mitigation, revives credited to every reviver, downs, Execute's finishing blow, bosses).

const Fakes := preload("res://tests/player_fakes.gd")

var world: Node3D


## An enemy whose first hit does not hurt it (a barrier), so Execute's finishing blow is needed.
class StubbornEnemy extends Fakes.FakeEnemy:
	func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null,
			knockback: Vector3 = Vector3.ZERO) -> void:
		var shielded := fake_damage_log.is_empty()
		var before := hp
		super(amount, is_crit, attacker, knockback)
		if shielded:
			hp = before


func before_each() -> void:
	RunState.start_run(4, 1234)
	world = Fakes.make_world(tree)
	EnemyGrid.mark_dirty()


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	EnemyGrid.mark_dirty()
	RunState.start_run(1, 1)


func _warrior(index: int = 0, pos: Vector3 = Vector3.ZERO) -> Player:
	return Fakes.spawn_player(world, index, &"warrior", pos)


## Takes the warrior's armour away: raw damage lands.
func _naked(p: Player) -> Player:
	p.stats.set_source(&"naked", {Stats.ARMOR: -2.0})
	return p


func _hurt(p: Player, hp: float) -> void:
	p.hp = hp
	p.invulnerable_left = 0.0


func _healing(index: int) -> float:
	return RunState.healing_by_player.get(index, 0.0)


func _absorbed(index: int) -> float:
	return RunState.absorbed_by_player.get(index, 0.0)


func _taken(index: int) -> float:
	return RunState.damage_taken_by_player.get(index, 0.0)


# --- Healing ----------------------------------------------------------------------------------

func test_a_self_heal_is_credited_to_the_hero() -> void:
	var p := _warrior(2)
	_hurt(p, 5.0)
	p.heal(3.0)
	check_eq(_healing(2), 3.0, "heal(amount) without a source counts for the hero itself")
	check(not RunState.healing_by_player.has(0), "nobody else")


func test_healing_is_credited_to_the_healer_not_the_target() -> void:
	var target := _warrior(1)
	_hurt(target, 4.0)
	target.heal(3.0, 3)
	check_eq(_healing(3), 3.0, "the healer (slot 3) gets the credit")
	check(not RunState.healing_by_player.has(1), "the target does not")


func test_only_the_effective_healing_counts() -> void:
	var p := _warrior(0)
	_hurt(p, p.max_hp() - 2.0)
	p.heal(10.0, 1)
	check_eq(_healing(1), 2.0, "overheal is not counted")
	p.heal(10.0, 1)
	check_eq(_healing(1), 2.0, "a full hero adds nothing")
	p.take_damage(999.0)
	p.heal(5.0, 1)
	check_eq(_healing(1), 2.0, "a ghost cannot be healed, nothing counted")


func test_regen_and_leech_count_as_self_healing() -> void:
	var p := _warrior(1)
	p.stats.set_source(&"test", {Stats.SPIRIT: 15.0, Stats.LEECH: 100.0})  # 1 hp / s, always leeches
	_hurt(p, 5.0)
	Fakes.step(p, 2.05)
	check_eq(_healing(1), 2.0, "two regen ticks of 1 HP, credited to the hero")
	p.on_hit_dealt(4.0, null)
	check_eq(_healing(1), 3.0, "a leeched point too")
	check_eq(RunState.healing_by_player.size(), 1, "only the hero itself")


func test_a_paladin_heal_is_credited_to_the_paladin() -> void:
	var paladin := Fakes.spawn_player(world, 0, &"paladin")
	var ally := Fakes.spawn_player(world, 2, &"warrior", Vector3(2.0, 0, 0))
	_hurt(ally, 3.0)
	paladin.abilities.get_resource(&"holy_power").set_value(3.0)
	check(paladin.abilities.try_cast(1), "Call of Valor heals the wounded ally")
	check(ally.hp > 3.0, "the ally was healed")
	check(_healing(0) > 0.0, "credited to the paladin (slot 0): %s" % RunState.healing_by_player)
	check(not RunState.healing_by_player.has(2), "not to the ally who was healed")
	check_near(_healing(0), ally.hp - 3.0, 0.001, "exactly the HP the ally gained")


func test_a_proc_heal_on_an_ally_is_credited_to_the_proc_owner() -> void:
	var owner_hero := _warrior(0)
	var ally := _warrior(3, Vector3(1.0, 0, 0))
	_hurt(ally, 2.0)
	var amount := 3.0
	# What the "heal" proc block does for an ally receiver.
	ally.heal(amount, owner_hero.slot_index())
	check_eq(_healing(0), amount, "the item's owner is credited")
	check(not RunState.healing_by_player.has(3), "not the ally")


func test_an_area_heal_is_credited_to_the_area_owner() -> void:
	var owner_hero := _warrior(1)
	var ally := _warrior(2, Vector3(1.0, 0, 0))
	_hurt(ally, 2.0)
	var area := AbilityArea.new()
	area.owner_player = owner_hero
	area.heal_per_tick = 2.0
	area.radius = 3.0
	world.add_child(area)
	area.global_position = Vector3(1.0, 0, 0)
	area._physics_process(1.0)
	check(ally.hp > 2.0, "the ally stood in the area and was healed")
	check(_healing(1) >= 2.0, "credited to the owner of the area (slot 1): %s" % RunState.healing_by_player)
	check(not RunState.healing_by_player.has(2), "not to the ally")


func test_a_bandage_over_time_is_credited_to_the_caster() -> void:
	var caster := _warrior(0)
	var ally := _warrior(1, Vector3(1.0, 0, 0))
	_hurt(ally, 2.0)
	var buff := GeneralBuff.apply(ally, &"bandage_test", 5.0)
	buff.set_heal(4.0, 2, 0.5, caster.slot_index())
	buff.step(0.5)
	buff.step(0.5)
	check_eq(_healing(0), 4.0, "both ticks go to the caster")
	check(not RunState.healing_by_player.has(1), "not to the bandaged ally")
	var own := GeneralBuff.apply(caster, &"bandage_own", 5.0)
	_hurt(caster, 1.0)
	own.set_heal(2.0, 1, 0.5)
	own.step(0.5)
	check_eq(_healing(0), 6.0, "a buff without a source heals for the buffed hero")


# --- Damage taken ------------------------------------------------------------------------------

func test_damage_taken_is_counted_after_mitigation() -> void:
	var p := _warrior(1)
	p.stats.set_source(&"test", {Stats.ARMOR: -1.0})  # 1 armour: 1 / 16 less
	var hp := p.hp
	p.take_damage(2.0)
	check_near(_taken(1), 2.0 * (1.0 - 1.0 / 16.0), 0.0001, "armour reduced the hit before it was counted")
	check_near(hp - p.hp, _taken(1), 0.0001, "= the HP the hero lost")
	check(not RunState.damage_taken_by_player.has(0), "nobody else")


func test_overkill_is_not_counted_as_damage_taken() -> void:
	var p := _warrior(0)
	_hurt(p, 3.0)
	p.take_damage(500.0)
	check_eq(_taken(0), 3.0, "the 3 HP it had, not the 500 of the hit")


func test_avoided_and_ignored_hits_are_not_damage_taken() -> void:
	var p := _warrior(0)
	p.stats.set_source(&"test", {Stats.DODGE: 1000.0})
	p.take_damage(5.0)
	check(not RunState.damage_taken_by_player.has(0), "a dodged hit")
	p.stats.remove_source(&"test")
	p.invulnerable_left = 1.0
	p.take_damage(5.0)
	check(not RunState.damage_taken_by_player.has(0), "a hit during the i-frames")
	p.invulnerable_left = 0.0
	p.take_damage(999.0)
	var after_down := _taken(0)
	p.invulnerable_left = 0.0
	p.take_damage(5.0)
	check_eq(_taken(0), after_down, "a ghost takes nothing")


func test_a_death_guard_leaves_one_hp_and_only_that_loss_counts() -> void:
	var p := _warrior(0)
	p.stats.set_source(&"test", {Stats.ARMOR: -2.0})  # no armour: the raw hit lands
	p.death_guards.append(func() -> bool: return true)
	var before := p.hp
	p.take_damage(999.0)
	check(not p.downed and p.hp >= 1.0, "the guard kept the hero up")
	check_near(_taken(0), before - p.hp, 0.0001, "only the HP really lost is counted")
	check(not RunState.downs_by_player.has(0), "and it did not go down")


# --- Absorbs -----------------------------------------------------------------------------------

func test_own_shield_absorb_is_credited_to_the_owner() -> void:
	var p := _naked(_warrior(1))
	p.procs.add_shield(4.0, 10.0)
	p.take_damage(3.0)
	check_eq(_absorbed(1), 3.0, "the shield soaked the whole hit")
	check(not RunState.damage_taken_by_player.has(1), "and nothing was taken")
	p.invulnerable_left = 0.0
	p.take_damage(3.0)
	check_eq(_absorbed(1), 4.0, "the last point of the shield")
	check_near(_taken(1), 2.0, 0.0001, "the rest went through")


func test_a_teammates_shield_credits_the_caster() -> void:
	var caster := _warrior(0)
	var target := _naked(_warrior(2, Vector3(1.0, 0, 0)))
	target.procs.add_shield(5.0, 10.0, &"", caster.slot_index())
	target.take_damage(2.0)
	check_eq(_absorbed(0), 2.0, "the caster (slot 0) is credited")
	check(not RunState.absorbed_by_player.has(2), "not the shielded hero")


func test_shields_of_two_casters_keep_separate_entries_and_credit() -> void:
	var target := _naked(_warrior(3))
	target.procs.add_shield(2.0, 5.0, &"holy", 0)
	target.procs.add_shield(3.0, 10.0, &"holy", 1)
	check_eq(target.procs.shield_of(&"holy"), 5.0, "shield_of sums every caster of the source")
	target.take_damage(4.0)
	# The shield that runs out first (2 HP, 5 s) soaks first: 2 for slot 0, then 2 for slot 1.
	check_eq(_absorbed(0), 2.0, "caster 0")
	check_eq(_absorbed(1), 2.0, "caster 1")
	check_eq(target.procs.shield_of(&"holy"), 1.0, "1 HP of the second shield is left")


func test_shield_hp_that_expires_unused_is_not_absorbed() -> void:
	var p := _warrior(0)
	p.procs.add_shield(5.0, 1.0)
	p.procs._physics_process(1.5)
	check(p.procs.shield_hp <= 0.0, "the shield ran out")
	check(not RunState.absorbed_by_player.has(0), "nothing soaked, nothing credited")


func test_a_block_counts_as_absorbed_by_the_blocking_hero() -> void:
	var p := _warrior(2)
	p.stats.set_source(&"test", {Stats.BLOCK_CHANCE: 1000.0})  # capped at Stats.BLOCK_CAP
	RunState.rng.seed = 99
	var raw := 4.0
	var hits := 60
	var full := p._mitigated(raw, CombatMath.KIND_MELEE, null)
	for _i in hits:
		p.hp = p.max_hp()
		p.invulnerable_left = 0.0
		p.take_damage(raw)
	check(_absorbed(2) > 0.0, "some hits were blocked: %s" % _absorbed(2))
	check_near(_absorbed(2) + _taken(2), full * hits, 0.001, "what was blocked + what was taken = every unblocked hit")


# --- Downs and revives -------------------------------------------------------------------------

func test_each_down_is_counted_for_that_hero() -> void:
	var a := _warrior(0)
	var b := _warrior(3, Vector3(5.0, 0, 0))
	a.take_damage(999.0)
	check_eq(RunState.downs_by_player.get(0, 0), 1, "slot 0 went down")
	a.revive(0.5)
	a.invulnerable_left = 0.0
	a.take_damage(999.0)
	b.take_damage(999.0)
	check_eq(RunState.downs_by_player.get(0, 0), 2, "slot 0 again")
	check_eq(RunState.downs_by_player.get(3, 0), 1, "slot 3 once")


func test_a_teammate_revive_credits_every_reviver() -> void:
	var ghost := _warrior(0)
	_warrior(1, Vector3(1.0, 0, 0))
	_warrior(2, Vector3(-1.0, 0, 0))
	_warrior(3, Vector3(10.0, 0, 0))  # too far away to help
	ghost.take_damage(999.0)
	Fakes.step(ghost, 3.0, 0.1)
	check(ghost.downed, "still channelling")
	check(RunState.revives_by_player.is_empty(), "nothing credited before the revive completes")
	Fakes.step(ghost, 0.6, 0.1)
	check(not ghost.downed, "revived")
	check_eq(RunState.revives_by_player, {1: 1, 2: 1} as Dictionary[int, int], "both reviving teammates, nobody else")


func test_the_wave_start_the_healer_and_the_smoke_revive_credit_nobody() -> void:
	var p := _warrior(0)
	p.take_damage(999.0)
	p.begin_wave()
	check(not p.downed, "the wave start brought it back")
	p.invulnerable_left = 0.0
	p.take_damage(999.0)
	p.revive(1.0)  # Spirit Healer / smoke runner: no reviver slots
	check(not p.downed, "revived")
	check(RunState.revives_by_player.is_empty(), "no revive credited: %s" % RunState.revives_by_player)
	check_eq(RunState.downs_by_player.get(0, 0), 2, "both downs are")


func test_reviving_a_hero_who_is_not_down_credits_nothing() -> void:
	var p := _warrior(0)
	p.revive(0.5, [1] as Array[int])
	check(RunState.revives_by_player.is_empty(), "no revive happened")


func test_word_of_glory_revive_is_credited_to_the_caster() -> void:
	var paladin := Fakes.spawn_player(world, 1, &"paladin")
	var ally := Fakes.spawn_player(world, 3, &"warrior", Vector3(6.0, 0, 3.0))
	ally.invulnerable_left = 0.0
	ally.hp = 1.0
	ally.take_damage(1000.0)
	check(ally.downed, "ally downed")
	paladin.abilities.get_resource(&"holy_power").set_value(3.0)
	check(paladin.abilities.try_cast(1), "Call of Valor raises the ally")
	check(not ally.downed, "revived")
	check_eq(RunState.revives_by_player, {1: 1} as Dictionary[int, int], "the caster only")


# --- Execute and bosses -------------------------------------------------------------------------

func test_execute_s_finishing_blow_is_recorded_as_damage() -> void:
	var p := _warrior(1)
	var e := StubbornEnemy.new()
	e.max_hp = 1000.0
	e.hp = 50.0
	e.add_to_group(&"enemies")
	world.add_child(e)
	EnemyGrid.mark_dirty()
	var executed := WarriorExecute.strike(p, e, 10.0, 20.0, 1.0, CombatMath.SCHOOL_PHYSICAL)
	check(executed, "below the threshold: an execution")
	check_eq(e.fake_damage_log.size(), 2, "the strike and the finishing blow")
	check_near(RunState.damage_by_player.get(1, 0.0), 50.0 + 50.0, 0.001,
			"both hits are on the meter (the strike capped at the 50 HP it had, plus the 50 HP finish)")


func test_a_boss_kill_is_counted_per_killer() -> void:
	RunState.record_special_kill(&"boss", 2)
	RunState.record_special_kill(&"boss", 2)
	RunState.record_special_kill(&"boss", 0)
	RunState.record_special_kill(&"boss", -1)
	RunState.record_special_kill(&"elite", 1)
	check_eq(RunState.bosses_by_player, {2: 2, 0: 1} as Dictionary[int, int], "per killer, nobody ignored")
	check_eq(RunState.bosses_killed, 4, "the team counter counts all four")


func test_the_hero_results_are_recorded_and_reset_by_a_new_run() -> void:
	var item := ItemInstance.new()
	RunState.record_hero_result(1, true, item)
	RunState.record_hero_result(0, false)
	RunState.record_hero_result(-1, true)
	check_eq(RunState.hero_results.size(), 2, "slot -1 is ignored")
	check_eq(RunState.hero_results[1]["alive"], true, "alive")
	check(RunState.hero_results[1]["best_item"] == item, "the item")
	check_eq(RunState.hero_results[0]["alive"], false, "downed")
	check(RunState.hero_results[0]["best_item"] == null, "no item")
	RunState.record_special_kill(&"boss", 1)
	RunState.start_run(2, 1)
	check(RunState.hero_results.is_empty() and RunState.bosses_by_player.is_empty(), "start_run resets both")
