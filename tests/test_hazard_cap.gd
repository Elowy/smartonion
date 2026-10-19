extends TestCase
## Final balance 2: no single ground attack of a boss (or of the arena) one-shots a hero at full health. One hit of
## a Fire Fields tick, a Meteor's share, a Frost Circle or a Frost Breath takes at most EnemyHazard.MAX_HIT_SHARE of
## the hero's Max HP (Player.take_damage's max_hp_share, applied after armour and the other reductions).

const EFakes := preload("res://tests/enemies_fakes.gd")
const PFakes := preload("res://tests/player_fakes.gd")
const QUIET := &"test_quiet"

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 4242)
	RunState.set_wave(10)
	PlayerManager.clear()
	world = EFakes.make_world(tree)


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null
	PlayerManager.clear()
	Enemy.invalidate_player_cache()


func _entities() -> Node3D:
	return EFakes.arena_of(world).entities


## A real Player of [param class_id] (no dodge, no crits) at [param pos], full health.
func _real_hero(class_id: StringName, pos: Vector3, index: int = 0) -> Player:
	var p := Player.create(PFakes.make_slot(index, class_id))
	p.stats.remove_source(&"base")
	p.stats.set_source(QUIET, {Stats.CRIT: -500.0, Stats.DODGE: -500.0, Stats.PARRY: -500.0})
	_entities().add_child(p)
	p.global_position = pos
	p.hp = p.max_hp()
	Enemy.invalidate_player_cache()
	return p


func test_the_share_is_the_tuned_number() -> void:
	check_eq(EnemyHazard.MAX_HIT_SHARE, 0.4, "a ground hit takes at most 40% of Max HP")


func test_take_damage_caps_the_hit_at_a_share_of_max_hp() -> void:
	var p := _real_hero(&"mage", Vector3.ZERO)
	var max_hp := p.max_hp()
	p.take_damage(100000.0, CombatMath.KIND_AOE, null, 0.4)
	check_near(max_hp - p.hp, max_hp * 0.4, 0.0001, "the huge hit took exactly 40% of Max HP")
	check(p.hp > 0.0 and not p.downed, "and the hero stands")


func test_take_damage_without_a_share_is_unchanged() -> void:
	var p := _real_hero(&"mage", Vector3.ZERO)
	var q := _real_hero(&"mage", Vector3(5, 0, 0), 1)
	var small := p.max_hp() * 0.2
	p.take_damage(small, CombatMath.KIND_AOE)
	q.take_damage(small, CombatMath.KIND_AOE, null, 0.4)
	check(p.hp < p.max_hp(), "(the small hit landed)")
	check_near(p.hp, q.hp, 0.0001, "a hit below the cap lands in full either way")
	var big := _real_hero(&"mage", Vector3(9, 0, 0), 2)
	big.take_damage(100000.0, CombatMath.KIND_AOE)
	check(big.downed, "no share: an enormous hit still kills")


func test_the_cap_applies_to_the_mitigated_damage() -> void:
	var p := _real_hero(&"warrior", Vector3.ZERO)
	var max_hp := p.max_hp()
	var mitigated := CombatMath.incoming_damage(max_hp * 0.3, p.stats, CombatMath.KIND_AOE)
	check(mitigated < max_hp * 0.3 and mitigated > 0.0, "(armour takes a share of the hit: %.1f)" % mitigated)
	p.take_damage(max_hp * 0.3, CombatMath.KIND_AOE, null, 0.4)
	check_near(max_hp - p.hp, mitigated, 0.01, "armour first, the cap only on what is left")
	var q := _real_hero(&"warrior", Vector3(5, 0, 0), 1)
	q.take_damage(max_hp * 50.0, CombatMath.KIND_AOE, null, 0.4)
	check_near(max_hp - q.hp, max_hp * 0.4, 0.01, "a huge hit: the cap")


func test_a_second_hit_after_the_grace_period_takes_another_share() -> void:
	var p := _real_hero(&"rogue", Vector3.ZERO)
	var max_hp := p.max_hp()
	p.take_damage(100000.0, CombatMath.KIND_AOE, null, 0.4)
	p.invulnerable_left = 0.0
	p.take_damage(100000.0, CombatMath.KIND_AOE, null, 0.4)
	check_near(max_hp - p.hp, max_hp * 0.8, 0.0001, "two hits: 80%")
	check(not p.downed, "still up")
	p.invulnerable_left = 0.0
	p.take_damage(100000.0, CombatMath.KIND_AOE, null, 0.4)
	check(p.downed, "the third one is the last")


func test_hit_hero_passes_the_cap() -> void:
	var h := EFakes.spawn_player(world, Vector3.ZERO)
	var f := FireField.spawn(_entities(), Vector3(0.5, 0, 0), 2.0, 0.1, 8.0, 1.0, 50.0)
	EFakes.step(f, 0.2)
	check_eq(h.fake_hits.size(), 1, "the first tick hit")
	check_eq(h.fake_caps, [EnemyHazard.MAX_HIT_SHARE] as Array[float], "with the share cap")


func test_the_first_fire_fields_tick_never_one_shots_a_full_hero() -> void:
	var p := _real_hero(&"mage", Vector3(0.5, 0, 0))
	var f := FireField.spawn(_entities(), Vector3.ZERO, 2.0, 0.1, 8.0, 1.0, p.max_hp() * 10.0)
	EFakes.step(f, 0.2)
	check(not p.downed and p.hp > 0.0, "a tick ten times the Max HP leaves the hero standing")
	check_near(p.max_hp() - p.hp, p.max_hp() * EnemyHazard.MAX_HIT_SHARE, 0.0001, "it took the capped share")


func test_a_lone_hero_in_the_meteor_survives_its_whole_damage() -> void:
	var p := _real_hero(&"rogue", Vector3(0.5, 0, 0))
	var m := MeteorStrike.spawn(_entities(), Vector3.ZERO, 3.0, 1.0, p.max_hp() * 20.0, p.max_hp() * 10.0)
	EFakes.step(m, 1.1)
	check_eq(m.inside_count, 1, "alone inside")
	check(not p.downed, "the 8x meteor does not kill a full-health hero")
	check_near(p.max_hp() - p.hp, p.max_hp() * EnemyHazard.MAX_HIT_SHARE, 0.0001, "40% of Max HP")


func test_the_meteor_fallback_and_the_frost_hits_are_capped_too() -> void:
	var a := _real_hero(&"mage", Vector3(8, 0, 0))
	var m := MeteorStrike.spawn(_entities(), Vector3.ZERO, 3.0, 1.0, 9000.0, a.max_hp() * 5.0)
	EFakes.step(m, 1.1)
	check_eq(m.inside_count, 0, "nobody inside")
	check(not a.downed, "the fallback hit on everybody does not kill")
	var b := _real_hero(&"mage", Vector3(30, 0, 0), 1)
	var circle := FrostCircle.spawn(_entities(), Vector3(30, 0, 0), 2.0, 0.5, b.max_hp() * 3.0, 0.0, 0.0)
	EFakes.step(circle, 0.6)
	check(not b.downed, "a Frost Circle three times the Max HP does not kill")
	check_near(b.max_hp() - b.hp, b.max_hp() * EnemyHazard.MAX_HIT_SHARE, 0.0001, "40%")
	var c := _real_hero(&"mage", Vector3(30, 0, 12), 2)
	var breath := FrostBreath.spawn(_entities(), Vector3(30, 0, 8), Vector3(0, 0, 1), 60.0, 7.0, 0.5, c.max_hp() * 3.0)
	EFakes.step(breath, 0.6)
	check(not c.downed, "a Frost Breath three times the Max HP does not kill")
