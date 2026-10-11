extends TestCase
## P0 stub values owned by SETS: no set content in Db yet, SetBonuses counts nothing. SETS:
## delete or replace this file when you implement SetBonuses and ship data/sets/
## (architecture §3.1). The contracts that stay (Db.set_for_class / get_set on fixtures, the
## set_bonus source reaching player.bonuses) are in test_m5_foundation.gd (frozen, integrator
## only).


func test_no_set_content_yet() -> void:
	check(Db.sets.is_empty(), "no sets in Db yet")
	for class_id in Db.class_ids:
		check(Db.set_for_class(class_id) == null, "no %s set" % class_id)


func test_set_bonuses_stub_is_empty() -> void:
	var eq := Equipment.new(Db.get_class_data(&"warrior"))
	eq.equip_starting_weapons()
	var sword := eq.get_item(Items.EquipSlot.MAIN_HAND)
	check(SetBonuses.counts(eq).is_empty(), "stub: no counts")
	check(SetBonuses.effects_for(eq).is_empty(), "stub: no bonus entries")
	check_eq(SetBonuses.active_count(eq), 0, "stub: no active bonuses")
	check(SetBonuses.describe(sword, eq).is_empty() and SetBonuses.describe(sword, null).is_empty(), "stub: no tooltip rows")
