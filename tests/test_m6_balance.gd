extends TestCase
## Final balance pass: the diagnostics the pass is measured with (damage taken by source, damage dealt to
## bosses, the shield peak) and the tuned numbers it ended on (so a later data change cannot silently undo them).

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


# --- Damage on bosses (diagnostics) ----------------------------------------------------------------

func test_boss_damage_is_booked_per_hero_and_cleared_with_the_run() -> void:
	RunState.record_damage(0, 10.0)
	RunState.record_damage(0, 5.0, true)
	RunState.record_damage(1, 7.0, true)
	check_eq(RunState.damage_by_player[0], 15.0, "the boss hit counts for the meter too")
	check_eq(RunState.boss_damage_by_player[0], 5.0, "only the boss part")
	check_eq(RunSummary.boss_damage_dict(), {"0": 5.0, "1": 7.0}, "string keys")
	RunState.start_run(1, 5)
	check(RunState.boss_damage_by_player.is_empty(), "a new run starts clean")


func test_a_weapon_hit_on_a_boss_is_boss_damage_a_hit_on_a_grunt_is_not() -> void:
	var p := _hero(&"warrior", Vector3.ZERO)
	var boss := Boss.create(Db.get_boss(&"lich_commander_morvain"), 10)
	arena.entities.add_child(boss)
	var grunt := Enemy.create(Db.get_enemy(&"skeleton_grunt"), 10)
	arena.entities.add_child(grunt)
	WeaponRunner.apply_hit(p, boss, 7.0, false, Vector3.ZERO)
	WeaponRunner.apply_hit(p, grunt, 3.0, false, Vector3.ZERO)
	check_eq(RunState.boss_damage_by_player.get(0, 0.0), 7.0, "7 on the boss")
	check(RunState.damage_by_player.get(0, 0.0) > 7.0, "the grunt hit is in the meter: %s" % [RunState.damage_by_player])


# --- Shield stacking (diagnostics) -------------------------------------------------------------------

func test_the_shield_peak_keeps_the_highest_total_as_a_multiple_of_max_hp() -> void:
	var p := _hero(&"warrior", Vector3.ZERO)
	var hp := p.max_hp()
	p.procs.add_shield(hp * 0.25, 5.0, &"a")
	p.procs.add_shield(hp * 0.5, 5.0, &"b")
	check_near(RunState.shield_peak_by_player.get(0, 0.0), 0.75, 0.0001, "two sources: 75% of Max HP")
	p.procs.absorb(hp * 0.7)
	p.procs.add_shield(hp * 0.1, 5.0, &"c")
	check_near(RunState.shield_peak_by_player.get(0, 0.0), 0.75, 0.0001, "the peak stays")
	check_eq(RunSummary.shield_peak_dict(), {"0": 0.75}, "string keys, rounded to 0.01")
	RunState.start_run(1, 5)
	check(RunState.shield_peak_by_player.is_empty(), "a new run starts clean")


# --- The tuned numbers (final balance, round 1) -----------------------------------------------------
# Pinned so a later data change cannot silently undo the measured pass (docs/GDD.md chapter 9).

## The Flesh Golem was 30-74% of everything the heroes took from wave 10 on, from 2% of the enemies.
func test_the_flesh_golem_hits_softer_than_the_first_draft() -> void:
	var golem := Db.get_enemy(&"flesh_golem")
	check_eq(golem.contact_damage, 2.5, "contact 4 -> 2.5")
	check_eq(golem.hook_damage_ratio, 1.0, "the hook is still 1 x contact")
	check_eq(golem.attack_cooldown, 6.0, "the hook cadence is unchanged")


## Vor'thalax: his hazards are multiples of the contact damage and one-shot the glass classes at 4. His co-op HP
## factor is convex (x1 / x1.5 / x2.7 / x4.6): the party's damage grows faster than its size, and a party without a
## Rogue (80-90% of the bosses' damage in the bot runs) could not kill the linear x2.5 duo boss at all. Final
## balance 2: the convex term went from 1.0 (x3 / x5.5) to 0.7 once the Rogue's boss damage was trimmed (Fan of
## Knives against a boss, the Fangs' free fans) - four heroes with a Rogue whose gear was ordinary then needed over
## 210 s in 3 of 10 runs.
func test_the_bosses_co_op_hp_factors_and_vorthalax_contact() -> void:
	var v := Db.get_boss(&"vorthalax")
	var m := Db.get_boss(&"lich_commander_morvain")
	check_eq(v.contact_damage, 1.5, "Vor'thalax contact 4 -> 1.5")
	check_eq(v.coop_hp_per_player, 0.5, "Vor'thalax +50% HP per extra hero ...")
	check_eq(v.coop_hp_convex, 0.7, "... plus +70% per pair of extra heroes")
	check_eq(m.coop_hp_per_player, 1.25, "Morvain +125% HP per extra hero")
	check_eq(m.coop_hp_convex, 0.0, "Morvain stays linear")
	check_eq(m.contact_damage, 3.0, "Morvain contact unchanged")
	var solo := v.max_hp_for(25, 1)
	check_near(v.max_hp_for(25, 2) / solo, 1.5, 0.0001, "Vor'thalax duo x1.5")
	check_near(v.max_hp_for(25, 3) / solo, 2.7, 0.0001, "Vor'thalax trio x2.7")
	check_near(v.max_hp_for(25, 4) / solo, 4.6, 0.0001, "Vor'thalax four x4.6")
	check_near(m.max_hp_for(10, 2) / m.max_hp_for(10, 1), 2.25, 0.0001, "Morvain duo x2.25")
	check_near(m.max_hp_for(10, 4) / m.max_hp_for(10, 1), 4.75, 0.0001, "Morvain four x4.75")
	check_near(solo, 450.0 * v.hp_mult_at_wave(25), 0.01, "the solo HP is the base growth")


## The enemy damage by party size: the full party was raised once the golem was softened and the bots' first downs
## had moved from wave ~11 to wave ~20.
func test_the_co_op_damage_factors() -> void:
	check_eq(RunState.COOP_DAMAGE_MULTS, [0.45, 0.6, 0.9, 1.05] as Array[float], "1 / 2 / 3 / 4 heroes")


## The dungeon's enemies, brazier and Warden are scaled to a wave read from a table per portal wave and party size
## (final balance 2: the flat x1.6 / x1.3 was too hard at the late portals; the bots lost not one of 55 dungeons at
## the cleared wave's own strength); which enemy types appear still follows the cleared wave.
func test_the_dungeon_is_scaled_above_the_cleared_wave_by_portal_and_party() -> void:
	var expected := {
		6: [7, 10, 10, 10],
		9: [11, 14, 14, 16],
		12: [15, 17, 18, 20],
		15: [18, 21, 22, 23],
	}
	for portal: int in expected:
		for n in range(1, 5):
			check_eq(Dungeon.strength_wave(portal, n), expected[portal][n - 1], "portal %d, %d hero(es)" % [portal, n])
	check_eq(Dungeon.strength_wave(15, 4), 23, "four heroes after wave 15: wave 23 strength")
	check_eq(Dungeon.strength_wave(9, 9), 16, "more than four: the four-hero row")
	check_eq(Dungeon.strength_wave(9, 0), 11, "fewer than one: the lone hero's row")
	for portal in Dungeon.PORTAL_WAVES:
		check(Dungeon.STRENGTH_WAVES.has(portal), "a row for portal %d" % portal)
		for n in range(1, 4):
			check(int(Dungeon.STRENGTH_WAVES[portal][n - 1]) <= int(Dungeon.STRENGTH_WAVES[portal][n]),
					"a bigger party never gets an easier dungeon (portal %d, %d -> %d)" % [portal, n, n + 1])
	for n in range(1, 5):
		var last := 0
		for portal in Dungeon.PORTAL_WAVES:
			var s: int = Dungeon.strength_wave(portal, n)
			check(s > portal and s > last, "stronger than the cleared wave and than the portal before (%d heroes, portal %d)" % [n, portal])
			last = s
	check_eq(Dungeon.strength_wave(7, 4), 12, "a wave between two portals: the bonus is interpolated (+4 -> +7: 7 + 5, rounded)")
	check_eq(Dungeon.strength_wave(1, 4), 5, "before the first portal: its bonus (+4)")
	check_eq(Dungeon.strength_wave(0, 4), 5, "never below wave 1")
	check_eq(Dungeon.strength_wave(20, 4), 28, "after the last portal: its bonus (+8)")
	RunState.start_run(2, 1)
	check_eq(Dungeon.strength_wave(9), 14, "the run's own party size by default")
