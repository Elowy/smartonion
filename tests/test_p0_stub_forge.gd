extends TestCase
## P0 stub values owned by FORGE: nothing is forgeable, blocked_reason says "Forging is not
## available yet". FORGE: delete or replace this file when you implement Forge (architecture
## §3.1). The panel wiring that stays (the entry, its position, the reason shown) is tested in
## test_m5_foundation.gd (frozen, integrator only) through Forge.blocked_reason.


func test_forge_stub_forges_nothing() -> void:
	var eq := Equipment.new(Db.get_class_data(&"warrior"))
	eq.equip_starting_weapons()
	var sword := eq.get_item(Items.EquipSlot.MAIN_HAND)
	# A pair under FORGE's rules (same base, same rarity), refused by the stub.
	var twin := ItemInstance.from_weapon(sword.weapon)
	eq.add_to_backpack(twin)
	check(not Forge.is_forgeable(sword) and Forge.partner_for(eq, sword) == null, "stub: nothing forgeable")
	check_eq(Forge.blocked_reason(eq, sword), "Forging is not available yet", "stub: the reason")
	check(Forge.forge(eq, sword) == null and Forge.forge_with_offer(eq, twin) == null, "stub: no forging")
	check(Forge.make_result(sword, twin, RunState.rng) == null, "stub: no result")
	check(Forge.forged_rarity(sword) == 0 and Forge.result_text(sword) == "", "stub: no result text")
	check(Forge.offer_forge_slots(twin, PlayerManager.get_slots()).is_empty(), "stub: no anvil pips")
	check_eq(Forge.bot_forge_all(null), 0, "stub: bots forge nothing")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == sword and eq.backpack.size() == 1 and eq.backpack[0] == twin,
		"nothing moved")
