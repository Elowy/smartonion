extends "res://tests/shaman_base.gd"
## Shaman totems (M8, design_shaman.md §3): the Fire / Water / Earth / Air cycle of Totem Rite, the replace rule, the
## duration and what lengthens it, what each element does (numbers as designed), Twin / Walking Totem, the aura hook,
## and the cleanup (replace, expiry, wave start / end, teardown).


const EFakes := preload("res://tests/enemies_fakes.gd")


func _stats(p: Player) -> void:
	p.stats.set_source(&"test", {Stats.INTELLECT: 10.0, Stats.SPELL_POWER: 4.0})


## Casts Totem Rite again at once (the cooldown cleared).
func _recast(p: Player) -> bool:
	p.abilities.set_cooldown(Db.get_ability(&"totem_rite"), 0.0)
	return _cast(p, &"totem_rite")


## The one standing Rite totem of [param p] (null when none).
func _totem(p: Player) -> ShamanTotem:
	var list := _fx_rite(p).standing()
	return list[0] if not list.is_empty() else null


func _live_totems() -> int:
	return tree.get_nodes_in_group(&"shaman_totems").size()


# --- The cycle -------------------------------------------------------------------------------------------

func test_the_cycle_runs_fire_water_earth_air_and_a_new_totem_replaces_the_old() -> void:
	var p := _shaman()
	var order: Array[StringName] = [&"fire", &"water", &"earth", &"air", &"fire", &"water"]
	var previous: ShamanTotem = null
	for element in order:
		check_eq(_fx_rite(p).next_element(), element, "the next element is %s" % element)
		check(_recast(p), "cast")
		var t := _totem(p)
		check(t != null, "a totem stands")
		if t == null:
			break
		check_eq(t.element, element, "the totem is %s" % element)
		if previous != null:
			check(previous.dismissed, "the old totem is gone at once")
		check_eq(_live_totems(), 1, "one Totem Rite totem at a time")
		previous = t
	check_near(previous.global_position.distance_to(p.global_position), 0.0, 0.0001, "planted at the Shaman's feet")


func test_totem_rite_has_a_twelve_second_cooldown_and_no_cost() -> void:
	var p := _shaman()
	check(_cast(p, &"totem_rite"), "cast")
	check(not _cast(p, &"totem_rite"), "on cooldown")
	check_near(p.abilities.cooldown_of(Db.get_ability(&"totem_rite")), 12.0, 0.0001, "12 s")
	check_eq(Db.get_ability(&"totem_rite").resource, &"", "no resource")


func test_a_totem_is_no_target_and_has_no_health() -> void:
	var p := _shaman()
	check(_cast(p, &"totem_rite"), "cast")
	var t := _totem(p)
	check(not t.is_in_group(&"enemies"), "enemies do not know it")
	check(not t.has_method("take_damage"), "nothing can hurt it")
	check(t.get_parent() == world, "it stands in the world")


func test_the_cycle_persists_across_waves_and_totems_vanish_with_the_wave() -> void:
	var p := _shaman()
	check(_cast(p, &"totem_rite"), "Fire")
	check(_totem(p) != null, "standing")
	p.end_wave()
	check_eq(_live_totems(), 0, "gone when the wave is cleared")
	p.begin_wave()
	check(_cast(p, &"totem_rite"), "Water")
	check_eq(_totem(p).element, &"water", "the cycle went on")
	p.begin_wave()
	check_eq(_live_totems(), 0, "gone at a wave start too")
	check(_cast(p, &"totem_rite"), "Earth")
	check_eq(_totem(p).element, &"earth", "still going")


func test_a_new_run_starts_at_fire() -> void:
	var p := _shaman()
	check(_cast(p, &"totem_rite"), "cast")
	check_eq(_totem(p).element, &"fire", "a fresh Shaman calls Fire first")
	var q := _shaman(Vector3(0, 0, 30), 1)
	check_eq(_fx_rite(q).next_element(), &"fire", "each hero has its own cycle")


func test_totem_rite_never_takes_an_elemental_surge_charge() -> void:
	var p := _shaman()
	_mastery(p).grant_empower(2, 100.0)
	check(_cast(p, &"totem_rite"), "cast")
	check_eq(_mastery(p).empower_charges, 2, "the charges are untouched")


# --- Duration -------------------------------------------------------------------------------------------

func test_a_totem_stands_for_ten_seconds() -> void:
	var p := _shaman()
	check(_cast(p, &"totem_rite"), "cast")
	var t := _totem(p)
	_run(p, 9.8)
	check(t.is_active(), "alive after 9.8 s")
	_run(p, 0.4)
	check(not t.is_active(), "gone after 10.2 s")
	check_eq(_fx_rite(p).standing().size(), 0, "no totem is left")


func test_rank_iii_and_the_totem_mods_lengthen_the_duration() -> void:
	var p := _shaman()
	_learn(p, &"totem_rite", 3)
	check(_cast(p, &"totem_rite"), "cast")
	check_near(_totem(p).life_left, 14.0, 0.0001, "Rank III: +4 s")
	var q := _shaman(Vector3(0, 0, 30), 1)
	_put(q, [{"kind": "ability", "match": {"id": "shaman_totems"}, "mods": {"duration_pct": 30.0}, "rank": 1}])
	check(_cast(q, &"totem_rite"), "cast")
	check_near(_totem(q).life_left, 13.0, 0.0001, "the set bonus: +30%")
	var r := _shaman(Vector3(0, 0, 60), 2)
	_learn(r, &"totem_rite", 3)
	_put(r, [{"kind": "ability", "match": {"id": "shaman_totems"}, "mods": {"duration_pct": 30.0}, "rank": 1}])
	check(_cast(r, &"totem_rite"), "cast")
	check_near(_totem(r).life_left, 18.2, 0.0001, "(10 + 4) x 1.3")


func test_a_rootbound_item_adds_seconds() -> void:
	var p := _shaman()
	_put(p, [{"kind": "ability", "match": {"id": "shaman_totems"}, "mods": {"duration_add": 3.0}, "rank": 1}])
	check(_cast(p, &"totem_rite"), "cast")
	check_near(_totem(p).life_left, 13.0, 0.0001, "+3 s")


# --- Fire -------------------------------------------------------------------------------------------------

func test_the_fire_totem_shoots_the_nearest_enemy_every_second() -> void:
	var p := _shaman()
	_stats(p)
	var near := _enemy(Vector3(4, 0, 0))
	var far := _enemy(Vector3(8, 0, 0))
	check(_cast(p, &"totem_rite"), "cast")
	var t := _totem(p)
	_run(p, 0.2)
	check_eq(t.shots, 0, "the first shot comes 0.3 s after planting")
	_run(p, 0.2)
	check_eq(t.shots, 1, "then it shoots")
	_run(p, 2.7)
	check_eq(t.shots, 3, "once per second: 0.3 s, 1.3 s, 2.3 s")
	check_eq(near.fake_damage_log.size(), 3, "every bolt at the nearest enemy")
	check(far.fake_damage_log.is_empty(), "the farther one is left alone")
	for v in near.fake_damage_log:
		check_near(v, 4.0 + 7.0 + 4.0, 0.001, "4 + 0.7 Int + 1.0 SP per second")
	check(near.fake_attacker_log[0] == p, "the Shaman's damage")


func test_the_fire_totem_range_haste_power_and_source() -> void:
	var p := _shaman()
	_stats(p)
	var out := _enemy(Vector3(9.5, 0, 0))
	check(_cast(p, &"totem_rite"), "cast")
	_run(p, 2.0)
	check(out.fake_damage_log.is_empty(), "9.5 m is out of the totem's 9 m range")
	out.global_position = Vector3(8.5, 0, 0)
	EnemyGrid.mark_dirty()
	_run(p, 0.2)
	check(not out.fake_damage_log.is_empty(), "8.5 m is in range")
	# Haste shortens the interval, the pseudo ability's power raises the damage, the source is ability damage.
	var q := _shaman(Vector3(0, 0, 40), 1)
	_stats(q)
	q.stats.set_source(&"haste", {Stats.HASTE: 100.0})
	_put(q, [{"kind": "ability", "match": {"id": "shaman_totems"}, "mods": {"power_pct": 20.0}, "rank": 1},
		{"kind": "damage", "pct": 100.0, "source": "ability", "rank": 1}])
	var e := _enemy(Vector3(4, 0, 40))
	check(_cast(q, &"totem_rite"), "cast")
	_run(q, 3.0)
	check_eq(_totem(q).shots, 6, "twice as fast with 100% Haste: 0.3 s, 0.8 s ... 2.8 s")
	check_near(e.fake_damage_log[0], 15.0 * 1.2 * 2.0, 0.001, "+20% power and +100% ability damage")


func test_a_fire_totem_without_an_enemy_waits_for_one() -> void:
	var p := _shaman()
	_stats(p)
	check(_cast(p, &"totem_rite"), "cast")
	_run(p, 2.0)
	check_eq(_totem(p).shots, 0, "nothing to shoot")
	var e := _enemy(Vector3(5, 0, 0))
	_run(p, 0.1)
	check_eq(_totem(p).shots, 1, "it shoots at once when an enemy walks in")
	check_eq(e.fake_damage_log.size(), 1, "one bolt")


# --- Water -------------------------------------------------------------------------------------------------

func test_the_water_totem_heals_heroes_in_range() -> void:
	var p := _shaman()
	_stats(p)
	var near := _ally(1, Vector3(3, 0, 0))
	var far := _ally(2, Vector3(7, 0, 0))
	near.hp = 1.0
	far.hp = 1.0
	p.hp = 1.0
	check(_recast(p) and _recast(p), "Water is the second element")
	var t := _totem(p)
	check_eq(t.element, &"water", "Water")
	_run(p, 0.05)
	var heal_near := 0.5 + near.max_hp() * 0.025 + 4.0 * 0.5
	check_near(near.hp, 1.0 + heal_near, 0.001, "0.5 + 2.5% Max HP + 0.5 SP at the first beat")
	check_near(far.hp, 1.0, 0.0001, "7 m away: nothing")
	check_near(p.hp, 1.0 + 0.5 + p.max_hp() * 0.025 + 2.0, 0.001, "the Shaman heals itself too")
	check(RunState.healing_by_player.get(0, 0.0) > 0.0, "credited to the Shaman's meter")
	_run(p, 1.0)
	check_near(near.hp, minf(near.max_hp(), 1.0 + 2.0 * heal_near), 0.001, "one beat per second")


func test_the_water_totem_heals_more_with_healing_done_and_never_a_downed_hero() -> void:
	var p := _shaman()
	_stats(p)
	p.stats.set_source(&"heal", {Stats.HEALING_DONE: 50.0})
	var hurt := _ally(1, Vector3(3, 0, 0))
	hurt.hp = 1.0
	var ghost := _ally(2, Vector3(2, 0, 2))
	_down(ghost)
	check(_recast(p) and _recast(p), "Water")
	_run(p, 0.05)
	check_near(hurt.hp, 1.0 + (0.5 + hurt.max_hp() * 0.025 + 2.0) * 1.5, 0.001, "+50% Healing Done")
	check(ghost.downed, "the ghost stays down")


# --- Earth -------------------------------------------------------------------------------------------------

func test_the_earth_totem_slows_enemies_in_range() -> void:
	var p := _shaman()
	var inside := _enemy(Vector3(4, 0, 0))
	var outside := _enemy(Vector3(6, 0, 0))
	for i in 3:
		check(_recast(p), "cast %d" % i)
	check_eq(_totem(p).element, &"earth", "Earth")
	_run(p, 0.6)
	check(not inside.slows.is_empty() and inside.slows[0] == 30.0, "30% slow within 5 m")
	check(outside.slows.is_empty(), "6 m away: free")
	var count := inside.slows.size()
	_run(p, 1.0)
	check(inside.slows.size() > count, "refreshed every quarter second")


func test_the_earth_totem_numbers_follow_the_pseudo_ability_and_cap_at_sixty() -> void:
	var p := _shaman()
	_put(p, [{"kind": "ability", "match": {"id": "shaman_totems"}, "mods": {"power_pct": 8.0, "earth_slow_add": 3.0}, "rank": 1}])
	var e := _enemy(Vector3(4, 0, 0))
	for i in 3:
		_recast(p)
	_run(p, 0.3)
	check_near(e.slows[0], 33.0 * 1.08, 0.001, "(30 + 3) x 1.08")
	var q := _shaman(Vector3(0, 0, 40), 1)
	_put(q, [{"kind": "ability", "match": {"id": "shaman_totems"}, "mods": {"earth_slow_add": 100.0}, "rank": 1}])
	var f := _enemy(Vector3(4, 0, 40))
	for i in 3:
		_recast(q)
	_run(q, 0.3)
	check_near(f.slows[0], 60.0, 0.001, "never more than 60%")


# --- Air -----------------------------------------------------------------------------------------------------

func test_the_air_totem_gives_haste_to_heroes_in_range_and_takes_it_back() -> void:
	var p := _shaman()
	var near := _ally(1, Vector3(3, 0, 0))
	var far := _ally(2, Vector3(8, 0, 0))
	var haste0 := near.stats.get_stat(Stats.HASTE)
	for i in 4:
		check(_recast(p), "cast %d" % i)
	check_eq(_totem(p).element, &"air", "Air")
	_run(p, 0.3)
	check_near(near.stats.get_stat(Stats.HASTE), haste0 + 15.0, 0.0001, "+15% Haste")
	check_near(p.stats.get_stat(Stats.HASTE), 15.0, 0.0001, "the Shaman too")
	check_near(far.stats.get_stat(Stats.HASTE), haste0, 0.0001, "8 m away: nothing")
	check(near.stats.has_source(&"totem_air:0"), "a named stat source of the owner's slot")
	near.global_position = Vector3(9, 0, 0)
	_run(p, 0.3)
	check_near(near.stats.get_stat(Stats.HASTE), haste0, 0.0001, "leaving the circle ends it")
	far.global_position = Vector3(2, 0, 0)
	_run(p, 0.3)
	check_near(far.stats.get_stat(Stats.HASTE), haste0 + 15.0, 0.0001, "walking in starts it")


func test_the_air_haste_ends_with_the_totem_however_it_ends() -> void:
	var p := _shaman()
	var ally := _ally(1, Vector3(3, 0, 0))
	for i in 4:
		_recast(p)
	_run(p, 0.3)
	check(ally.stats.has_source(&"totem_air:0"), "buffed")
	check(_recast(p), "Fire replaces Air")
	check(not ally.stats.has_source(&"totem_air:0") and not p.stats.has_source(&"totem_air:0"), "replaced: the haste is gone at once")
	for i in 3:
		_recast(p)
	_run(p, 0.3)
	check(ally.stats.has_source(&"totem_air:0"), "buffed again")
	p.end_wave()
	check(not ally.stats.has_source(&"totem_air:0"), "wave end removes it")
	for i in 4:
		_recast(p)
	_run(p, 0.3)
	check(ally.stats.has_source(&"totem_air:0"), "again")
	_run(p, 10.5)
	check(not ally.stats.has_source(&"totem_air:0"), "expiry removes it")


func test_freeing_an_air_totem_or_its_shaman_removes_the_haste() -> void:
	var p := _shaman()
	var ally := _ally(1, Vector3(3, 0, 0))
	for i in 4:
		_recast(p)
	_run(p, 0.3)
	check(ally.stats.has_source(&"totem_air:0"), "buffed")
	var t := _totem(p)
	world.remove_child(t)
	t.free()
	check(not ally.stats.has_source(&"totem_air:0"), "a freed totem leaves no haste behind")
	for i in 4:
		_recast(p)
	_run(p, 0.3)
	check(ally.stats.has_source(&"totem_air:0"), "buffed once more")
	world.remove_child(p)
	p.free()
	check(not ally.stats.has_source(&"totem_air:0"), "a freed Shaman takes its totems with it")
	check_eq(_live_totems(), 0, "no totem is left")


func test_air_haste_is_capped_at_forty() -> void:
	var p := _shaman()
	_put(p, [{"kind": "ability", "match": {"id": "shaman_totems"}, "mods": {"air_haste_add": 100.0}, "rank": 1}])
	for i in 4:
		_recast(p)
	_run(p, 0.3)
	check_near(p.stats.get_stat(Stats.HASTE), 40.0, 0.0001, "never more than 40%")


# --- Twin and Walking Totems --------------------------------------------------------------------------------

func test_twin_totems_plant_two_and_move_the_cycle_on_by_two() -> void:
	var p := _shaman()
	_learn(p, &"totem_rite", 5, 0)
	check(_cast(p, &"totem_rite"), "cast")
	var both := _fx_rite(p).standing()
	check_eq(both.size(), 2, "two totems")
	check_eq(both[0].element, &"fire", "Fire")
	check_eq(both[1].element, &"water", "and the next element, Water")
	check_near(both[1].global_position.x - both[0].global_position.x, 1.6, 0.0001, "1.6 m to the right")
	check_eq(_live_totems(), 2, "two stand")
	check(_recast(p), "the next cast")
	var next := _fx_rite(p).standing()
	check_eq(next.size(), 2, "still two")
	check_eq(next[0].element, &"earth", "the cycle moved on by two")
	check_eq(next[1].element, &"air", "Earth and Air")
	check(both[0].dismissed and both[1].dismissed, "both old totems were replaced")
	check_eq(_live_totems(), 2, "never more than two")


func test_the_second_twin_totem_stays_inside_the_clearing() -> void:
	var arena := EFakes.TestArena.new()
	world.add_child(arena)
	var edge := arena.get_bounds().end.x
	# Open ground: still 1.6 m to the right.
	var mid := _shaman(Vector3(edge - 6.0, 0, 0))
	_learn(mid, &"totem_rite", 5, 0)
	check(_cast(mid, &"totem_rite"), "cast in the open")
	var open := _fx_rite(mid).standing()
	check_near(open[1].global_position.x - open[0].global_position.x, 1.6, 0.0001, "1.6 m to the right when there is room")
	_fx_rite(mid).clear()
	# 0.8 m from the right wall: the right-hand spot (x + 1.6) would stand outside.
	var p := _shaman(Vector3(edge - 0.8, 0, 0), 1)
	_learn(p, &"totem_rite", 5, 0)
	check(_cast(p, &"totem_rite"), "cast at the wall")
	var both := _fx_rite(p).standing()
	check_eq(both.size(), 2, "two totems")
	check_near(both[0].global_position.x, edge - 0.8, 0.0001, "the first at the feet")
	check(both[1].global_position.x <= edge - 0.5 + 0.0001, "the second keeps 0.5 m from the wall (%.2f, wall %.2f)" % [both[1].global_position.x, edge])
	check(arena.is_inside(both[1].global_position), "inside the playable area")
	check_near(both[1].global_position.z, 0.0, 0.0001, "z unchanged")
	_fx_rite(p).clear()
	arena.free()


func test_the_second_twin_totem_stays_inside_a_dungeon_room() -> void:
	var arena := Arena.create()
	world.add_child(arena)
	arena.enter_dungeon_layout()
	var edge := arena.get_bounds().end.x
	check_eq(edge, 12.0, "the dungeon room is 24 m wide")
	var p := _shaman(Vector3(edge - 0.9, 0, 0))
	_learn(p, &"totem_rite", 5, 0)
	check(_cast(p, &"totem_rite"), "cast")
	var both := _fx_rite(p).standing()
	check_eq(both.size(), 2, "two totems")
	check(both[1].global_position.x <= edge - 0.5 + 0.0001, "inside the room (%.2f, wall %.2f)" % [both[1].global_position.x, edge])
	check(arena.get_bounds().has_point(Vector2(both[1].global_position.x, both[1].global_position.z)), "inside the playable rectangle")
	_fx_rite(p).clear()
	arena.free()


func test_the_walking_totem_follows_the_shaman_and_lasts_longer() -> void:
	var p := _shaman()
	_learn(p, &"totem_rite", 5, 1)
	check(_cast(p, &"totem_rite"), "cast")
	var t := _totem(p)
	check_near(t.life_left, 10.0 + 4.0 + 2.0, 0.0001, "+4 s (Rank III) and +2 s")
	check(t.follows, "it follows")
	p.global_position = Vector3(6, 0, 3)
	_run(p, 0.1)
	check_near(t.global_position.x, 6.0, 0.001, "it walked along (x)")
	check_near(t.global_position.z, 3.0, 0.001, "(z)")


# --- Aura (Artifact hook) -------------------------------------------------------------------------------------

func test_the_aura_hook_is_neutral_by_default() -> void:
	var p := _shaman()
	var ally := _ally(1, Vector3(3, 0, 0))
	check(_cast(p, &"totem_rite"), "cast")
	_run(p, 1.0)
	check(not ally.stats.has_source(&"totem_aura:0"), "no aura without the property")
	check_near(float(Db.get_ability(&"totem_rite").params["aura_damage_pct"]), 0.0, 0.0001, "the param is 0")


func test_the_aura_gives_heroes_near_a_totem_more_damage() -> void:
	var p := _shaman()
	_put(p, [{"kind": "ability", "match": {"id": "shaman_totems"}, "mods": {"aura_damage_pct_add": 10.0}, "rank": 1}])
	var near := _ally(1, Vector3(4, 0, 0))
	var far := _ally(2, Vector3(9, 0, 0))
	check(_cast(p, &"totem_rite"), "cast")
	_run(p, 0.3)
	check_near(near.stats.get_raw(Stats.DAMAGE_PCT), 10.0, 0.0001, "+10% damage within 6 m")
	check_near(p.stats.get_raw(Stats.DAMAGE_PCT), 10.0, 0.0001, "the Shaman too")
	check_near(far.stats.get_raw(Stats.DAMAGE_PCT), 0.0, 0.0001, "9 m away: nothing")
	near.global_position = Vector3(8, 0, 0)
	_run(p, 0.3)
	check_near(near.stats.get_raw(Stats.DAMAGE_PCT), 0.0, 0.0001, "leaving ends it")
	_run(p, 10.0)
	check_near(p.stats.get_raw(Stats.DAMAGE_PCT), 0.0, 0.0001, "the totem's end takes it back")


func test_two_totems_keep_the_aura_while_one_still_covers_a_hero() -> void:
	var p := _shaman()
	_learn(p, &"totem_rite", 5, 0)
	_put(p, [{"kind": "ability", "match": {"id": "shaman_totems"}, "mods": {"aura_damage_pct_add": 10.0}, "rank": 1}])
	var ally := _ally(1, Vector3(3, 0, 0))
	check(_cast(p, &"totem_rite"), "cast")
	_run(p, 0.3)
	check_near(ally.stats.get_raw(Stats.DAMAGE_PCT), 10.0, 0.0001, "covered by both")
	ally.global_position = Vector3(7, 0, 0)  # out of range of the first (7 m), inside the second (5.4 m)
	_run(p, 0.5)
	check_near(ally.stats.get_raw(Stats.DAMAGE_PCT), 10.0, 0.0001, "still covered by the second totem")
	ally.global_position = Vector3(20, 0, 0)
	_run(p, 0.5)
	check_near(ally.stats.get_raw(Stats.DAMAGE_PCT), 0.0, 0.0001, "out of both: gone")


# --- Cleanup and the downed Shaman -----------------------------------------------------------------------------

func test_totems_keep_working_while_the_shaman_is_downed() -> void:
	var p := _shaman()
	_stats(p)
	var e := _enemy(Vector3(4, 0, 0))
	check(_cast(p, &"totem_rite"), "cast")
	_down(p)
	check(p.downed, "the Shaman is down")
	for i in 90:
		p._physics_process(DT)
		_step_world(DT)
	check(not e.fake_damage_log.is_empty(), "the Fire totem keeps shooting")
	check(_totem(p) != null, "and keeps standing")
	p.begin_wave()
	check_eq(_live_totems(), 0, "the next wave clears it")


func test_teardown_frees_every_totem() -> void:
	var p := _shaman()
	_learn(p, &"totem_rite", 5, 0)
	check(_cast(p, &"totem_rite"), "cast")
	check_eq(_live_totems(), 2, "two totems")
	world.remove_child(p)
	p.free()
	check_eq(_live_totems(), 0, "freeing the hero frees them")


func test_totems_radii_follow_area_size() -> void:
	var p := _shaman()
	p.stats.set_source(&"area", {Stats.AREA_SIZE: 50.0})
	var e := _enemy(Vector3(6.5, 0, 0))
	for i in 3:
		_recast(p)
	_run(p, 0.3)
	check(not e.slows.is_empty(), "6.5 m is inside the 5 m x 1.5 earth radius")


# --- Bot rule --------------------------------------------------------------------------------------------------

func test_the_bot_plants_a_totem_when_an_enemy_is_near_and_the_old_one_runs_low() -> void:
	var p := _shaman()
	var fx := _fx_rite(p)
	var ctx := _ctx(p, &"totem_rite")
	check(not fx.wants_auto_cast(ctx), "no enemy within 10 m: no totem")
	var e := _enemy(Vector3(5, 0, 0))
	check(fx.wants_auto_cast(_ctx(p, &"totem_rite")), "an enemy within 10 m: plant")
	e.global_position = Vector3(11, 0, 0)
	EnemyGrid.mark_dirty()
	check(not fx.wants_auto_cast(_ctx(p, &"totem_rite")), "11 m is too far")
	e.global_position = Vector3(5, 0, 0)
	EnemyGrid.mark_dirty()
	check(_cast(p, &"totem_rite"), "cast")
	check(not fx.wants_auto_cast(_ctx(p, &"totem_rite")), "a fresh totem stands: wait")
	_run(p, 5.0)
	check(not fx.wants_auto_cast(_ctx(p, &"totem_rite")), "5 s left: wait")
	_run(p, 1.5)
	check(fx.wants_auto_cast(_ctx(p, &"totem_rite")), "less than 4 s left: a new one")


func test_a_bot_shaman_keeps_a_totem_up_by_itself() -> void:
	var p := _shaman()
	p.abilities.auto_cast = true
	_enemy(Vector3(5, 0, 0))
	_run(p, 0.6)
	check(_totem(p) != null, "the bot planted a totem")
	_run(p, 24.0)
	check(_fx_rite(p).cycle > 1, "and went on through the elements")
