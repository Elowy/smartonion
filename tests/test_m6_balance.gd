extends TestCase
## M6a balance pass (BALANCE package): the damage-by-source diagnostics the pass is measured with,
## and the tuned numbers it ended on (so a later data change cannot silently undo them).

const EFakes := preload("res://tests/enemies_fakes.gd")
const Fakes := preload("res://tests/player_fakes.gd")

var arena: Arena
var _index := 0


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 4242)
	arena = Arena.create()
	tree.root.add_child(arena)
	_index = 0


func after_each() -> void:
	if is_instance_valid(arena):
		tree.root.remove_child(arena)
		arena.free()
	arena = null
	Enemy.invalidate_player_cache()
	RunState.start_run(1, 1)


func _hero(class_id: StringName, pos: Vector3) -> Player:
	var slot := PlayerSlot.new(_index, ScriptedInput.new("m6bal:%d" % _index), PlayerManager.PLAYER_COLORS[_index])
	slot.class_data = Db.get_class_data(class_id)
	_index += 1
	var p := Player.create(slot)
	p.stats.remove_source(&"base")
	arena.entities.add_child(p)
	p.global_position = pos
	return p


# --- Damage by source (diagnostics) ---------------------------------------------------------------

func test_record_damage_taken_keeps_the_source_per_wave() -> void:
	RunState.set_wave(12)
	RunState.record_damage_taken(0, 3.0, &"flesh_golem")
	RunState.record_damage_taken(1, 2.0, &"flesh_golem")
	RunState.set_wave(13)
	RunState.record_damage_taken(0, 1.5, &"flesh_golem")
	RunState.record_damage_taken(0, 4.0, &"troll_axethrower")
	RunState.record_damage_taken(0, 9.0)
	check_eq(RunState.damage_taken_by_source[&"flesh_golem"], {12: 5.0, 13: 1.5}, "golem per wave")
	check_eq(RunState.damage_taken_by_source[&"troll_axethrower"], {13: 4.0}, "axethrower")
	check_eq(RunState.damage_taken_by_source.size(), 2, "a hit without a source id is not listed")
	check_eq(RunState.damage_taken_by_player[0], 17.5, "but it still counts for the player")
	RunState.record_damage_taken(0, 0.0, &"x")
	RunState.record_damage_taken(-1, 5.0, &"x")
	check(not RunState.damage_taken_by_source.has(&"x"), "nothing, nobody: ignored")


func test_start_run_clears_the_damage_by_source() -> void:
	RunState.record_damage_taken(0, 3.0, &"flesh_golem")
	RunState.start_run(1, 5)
	check(RunState.damage_taken_by_source.is_empty(), "a new run starts clean")


func test_a_hit_on_a_hero_is_booked_under_the_enemy_that_dealt_it() -> void:
	var p := _hero(&"warrior", Vector3.ZERO)
	var golem := Enemy.create(Db.get_enemy(&"flesh_golem"), 12)
	arena.entities.add_child(golem)
	RunState.set_wave(12)
	p.stats.set_source(&"naked", {Stats.ARMOR: -2.0})
	p.take_damage(2.0, CombatMath.KIND_MELEE, golem)
	var per_wave: Dictionary = RunState.damage_taken_by_source.get(&"flesh_golem", {})
	check(float(per_wave.get(12, 0.0)) > 0.0, "booked under the golem, wave 12: %s" % [RunState.damage_taken_by_source])
	p.invulnerable_left = 0.0
	p.take_damage(1.0, CombatMath.KIND_AOE, null)
	check(RunState.damage_taken_by_source.has(&"environment"), "a puddle tick (no enemy) is the environment")


func test_the_smoke_result_lists_the_damage_by_source() -> void:
	RunState.set_wave(12)
	RunState.record_damage_taken(0, 5.04, &"flesh_golem")
	var out := RunSummary.source_damage_dict()
	check_eq(out, {"flesh_golem": {"12": 5.0}}, "string keys, rounded to 0.1")


# --- Boss-arrival log: how tough the party is ----------------------------------------------------

func test_the_heroes_defence_line_shows_hp_and_the_share_of_a_raw_hit() -> void:
	var w := _hero(&"warrior", Vector3.ZERO)
	var m := _hero(&"mage", Vector3(3.0, 0.0, 0.0))
	var line := Main.heroes_defence_text([w, m] as Array[Player])
	var share_w := CombatMath.incoming_damage(100.0, w.stats, CombatMath.KIND_MELEE)
	check(line.begins_with("heroes: P1 warrior %.0f HP (takes %.0f%% of a raw hit)" % [w.max_hp(), share_w]), line)
	check("P2 mage" in line, "every hero is listed: " + line)
	check_eq(Main.heroes_defence_text([] as Array[Player]), "heroes: ", "nobody: just the prefix")
