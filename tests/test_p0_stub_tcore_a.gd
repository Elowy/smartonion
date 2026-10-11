extends TestCase
## P0 stub values owned by T-CORE-A: "no talent content in Db yet", the neutral PlayerBonuses
## stub and the TalentBot stub. T-CORE-A: delete or replace this file when you implement
## PlayerBonuses / TalentBot and ship the Arms tree (architecture §3.1). The contracts that
## stay true afterwards are in test_m5_foundation.gd (frozen, integrator only).

const Fakes := preload("res://tests/player_fakes.gd")

var world: Node3D


func after_each() -> void:
	Fakes.free_world(world)
	world = null


func test_no_talent_content_yet() -> void:
	check(Db.talent_trees.is_empty() and Db.talents.is_empty(), "no talent trees in Db yet")
	for class_id in Db.class_ids:
		check(Db.talent_trees_for(class_id).is_empty(), "no %s trees" % class_id)
	check(Db.get_talent_tree(&"warrior_arms") == null and Db.get_talent(&"warrior_arms_deflection") == null, "lookups")
	var s := TalentState.create(&"warrior")
	check(s.trees().is_empty() and s.effects().is_empty(), "a hero's TalentState is empty")
	check_eq(s.add_block_reason(&"warrior_arms_deflection"), "Unknown talent", "nothing to add")


func test_player_bonuses_stub_stores_but_applies_nothing() -> void:
	world = Fakes.make_world(tree)
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var crit := p.stats.get_raw(Stats.CRIT)
	var entries: Array[Dictionary] = [
		{"kind": "stats", "stats": {"crit": 5.0}, "rank": 1},
		{"kind": "ability", "match": {"id": "whirlwind"}, "mods": {"radius_add": 1.0}, "rank": 1},
		{"kind": "damage", "pct": 10.0, "rank": 1},
		{"kind": "damage_taken", "pct": -10.0, "rank": 1},
	]
	p.bonuses.set_effects(PlayerBonuses.SOURCE_TALENTS, entries)
	check_eq(p.bonuses.effects_of(PlayerBonuses.SOURCE_TALENTS).size(), 4, "stored")
	check_eq(p.stats.get_raw(Stats.CRIT), crit, "stub: no stats applied")
	check_eq(p.bonuses.ability_mods_for(&"whirlwind"), {}, "stub: no mods")
	check_eq(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, "stub: neutral damage")
	check_eq(p.bonuses.damage_taken_mult(&"melee", null), 1.0, "stub: neutral damage taken")
	check(not p.bonuses.crit_forced(null) and p.bonuses.scripts().is_empty(), "stub: no forced crits, no scripts")


func test_talent_bot_stub_spends_nothing() -> void:
	check_eq(TalentBot.spend_all(null, 0), 0, "stub: bots spend nothing")
