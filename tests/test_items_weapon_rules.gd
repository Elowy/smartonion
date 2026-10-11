extends TestCase
## Weapon rules between waves (M2 review fixes): two-handers are compared with both hands, an
## off-hand item next to a two-hander with that two-hander (ItemTooltip.equipped_for_compare /
## upgrade_direction, the character panel's "Replaces ..."), bots equip without flip-flopping
## and a hero never ends up without an attacking weapon (Equipment guards, PlayerPanel greys
## out Unequip / Sell / Trade / Equip with "You need a weapon"). Bot forging between waves
## (M5, the Intermission._bots_shop order: equip upgrades -> Forge.bot_forge_all -> equip
## again) keeps the hero armed and never forges two equipped weapons.

const UiFakes := preload("res://tests/ui_fakes.gd")
const Support := preload("res://tests/test_loot_support.gd")

var slots: Array[PlayerSlot] = []
var players: Array[Player] = []
var panels: Array[PlayerPanel] = []


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(2, 17)
	slots.clear()
	players.clear()
	panels.clear()


func after_each() -> void:
	for panel in panels:
		UiFakes.free_node(panel)
	for p in players:
		if is_instance_valid(p):
			p.free()
	Support.free_slots(slots)
	slots.clear()
	players.clear()
	panels.clear()
	UiFakes.reset_players()


## A slot with a (fake, out of tree) hero of [param class_id] holding its starting weapons.
func _armed(class_id: StringName) -> PlayerSlot:
	var slot := Support.make_slot(slots.size(), class_id)
	Support.equipment_of(slot).equip_starting_weapons()
	slots.append(slot)
	return slot


func _weapon(id: StringName, rarity: int = Items.Rarity.COMMON) -> ItemInstance:
	return Support.make_weapon(id, rarity)


func _hands(eq: Equipment) -> String:
	var m := eq.get_item(Items.EquipSlot.MAIN_HAND)
	var o := eq.get_item(Items.EquipSlot.OFF_HAND)
	return "%s | %s" % [m.display_name if m != null else "-", o.display_name if o != null else "-"]


# --- Comparisons ---------------------------------------------------------------------------

func test_two_hander_is_compared_with_both_hands() -> void:
	var rogue := _armed(&"rogue")
	var eq := Support.equipment_of(rogue)
	var cls := rogue.class_data
	var bow := _weapon(&"bow", Items.Rarity.EPIC)
	var cmp := ItemTooltip.equipped_for_compare(bow, eq)
	check(cmp is ItemTooltip.EquippedPair, "main + off hand together")
	check_eq(cmp.display_name, "Dagger + Dagger", "shown as both")
	var dagger := eq.get_item(Items.EquipSlot.MAIN_HAND)
	check_near(ItemTooltip.item_score(cmp, cls), ItemTooltip.item_score(dagger, cls) * 2.0, 0.001, "scores add up")
	check_near(ItemTooltip.weapon_dps(cmp), ItemTooltip.weapon_dps(dagger) * 2.0, 0.001, "both hands attack")
	check(ItemTooltip.item_score(bow, cls) > ItemTooltip.item_score(dagger, cls), "the Epic bow beats one dagger")
	check_eq(ItemTooltip.upgrade_direction(bow, cmp, cls, eq), -1, "but not two")
	# The tooltip's comparison block lists the pair.
	var tip := ItemTooltip.create()
	tip.show_item(bow, cls, cmp)
	check(tip.find_line("Equipped: Dagger + Dagger") != null, "Equipped: Dagger + Dagger")
	tip.free()
	# Only one hand filled: that item.
	check(eq.unequip(Items.EquipSlot.OFF_HAND), "off hand off")
	check(ItemTooltip.equipped_for_compare(bow, eq) == dagger, "compared with the main hand alone")


func test_off_hand_next_to_a_two_hander_is_compared_with_it() -> void:
	var mage := _armed(&"mage")
	var eq := Support.equipment_of(mage)
	var staff := _weapon(&"staff", Items.Rarity.EPIC)
	eq.add_to_backpack(staff)
	check(eq.equip(staff), "staff on")
	var tome := _weapon(&"tome", Items.Rarity.EPIC)
	tome.stats[Stats.INTELLECT] = 200.0
	eq.add_to_backpack(tome)
	check(ItemTooltip.equipped_for_compare(tome, eq) == staff, "a tome would push the staff out")
	check_eq(ItemTooltip.upgrade_direction(tome, staff, mage.class_data), -1,
			"never an upgrade: the mage would have no attacking weapon")
	check_eq(ItemTooltip.upgrade_direction(tome, staff, mage.class_data, eq), -1, "with the equipment too")
	# A one-hander next to a two-hander is compared with the two-hander, not with "empty".
	var rogue := _armed(&"rogue")
	var req := Support.equipment_of(rogue)
	var bow := _weapon(&"bow", Items.Rarity.EPIC)
	req.add_to_backpack(bow)
	check(req.equip(bow), "bow on")
	var dagger := _weapon(&"dagger")
	check(ItemTooltip.equipped_for_compare(dagger, req) == bow, "the off hand is not empty next to a bow")
	check_eq(ItemTooltip.upgrade_direction(dagger, bow, rogue.class_data, req), -1, "a Common dagger is no upgrade")


func test_bots_do_not_flip_flop_between_a_bow_and_daggers() -> void:
	var rogue := _armed(&"rogue")
	var eq := Support.equipment_of(rogue)
	eq.add_to_backpack(_weapon(&"bow", Items.Rarity.EPIC))
	var seen: Array[String] = []
	for round_index in 4:
		Intermission.bot_equip_upgrades(rogue)
		seen.append(_hands(eq))
	check_eq(seen, ["Dagger | Dagger", "Dagger | Dagger", "Dagger | Dagger", "Dagger | Dagger"] as Array[String],
			"two daggers beat the Epic bow: kept every round")
	# The other way round: a Common bow in hand, two daggers in the backpack -> switch once.
	var other := _armed(&"rogue")
	var oeq := Support.equipment_of(other)
	var common_bow := _weapon(&"bow")
	oeq.add_to_backpack(common_bow)
	check(oeq.equip(common_bow), "bow on, daggers in the backpack")
	check_eq(oeq.backpack.size(), 2, "two daggers")
	seen.clear()
	for round_index in 4:
		Intermission.bot_equip_upgrades(other)
		seen.append(_hands(oeq))
	check_eq(seen, ["Dagger | Dagger", "Dagger | Dagger", "Dagger | Dagger", "Dagger | Dagger"] as Array[String],
			"switches to the daggers once and stays")
	check(oeq.backpack == [common_bow], "the bow waits in the backpack")


func test_mage_bot_keeps_its_staff_next_to_a_tome() -> void:
	RunState.start_run(1, 3)
	var slot := PlayerSlot.new(0, ScriptedInput.new("x"), Color.WHITE)
	slot.class_data = Db.get_class_data(&"mage")
	var p := Player.create(slot)
	players.append(p)
	var eq := p.equipment
	var staff := _weapon(&"staff", Items.Rarity.EPIC)
	eq.add_to_backpack(staff)
	check(eq.equip(staff), "staff on (the wand goes to the backpack)")
	eq.add_to_backpack(_weapon(&"tome"))
	for round_index in 3:
		Intermission.bot_equip_upgrades(slot)
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == staff, "still the staff")
	check_eq(eq.get_item(Items.EquipSlot.OFF_HAND), null, "no tome pushed it out")
	check_eq(p.weapons.size(), 1, "one attacking weapon")


## What Intermission._bots_shop does with a bot's gear before buying (M5 hook).
static func _bot_gear_pass(slot: PlayerSlot) -> int:
	Intermission.bot_equip_upgrades(slot)
	var forged := Forge.bot_forge_all(slot)
	if forged > 0:
		Intermission.bot_equip_upgrades(slot)
	return forged


func test_bots_wear_a_spare_one_hander_in_a_free_off_hand_instead_of_forging() -> void:
	var warrior := _armed(&"warrior")
	var eq := Support.equipment_of(warrior)
	var sword := eq.get_item(Items.EquipSlot.MAIN_HAND)
	var spare := _weapon(&"sword")
	eq.add_to_backpack(spare)
	check_eq(_bot_gear_pass(warrior), 0, "two equipped swords are never forged together")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == sword and eq.get_item(Items.EquipSlot.OFF_HAND) == spare,
		"dual wield: the spare went into the free off hand")
	check_eq(RunState.weapons_forged, 0, "nothing forged")


func test_bots_forge_a_spare_into_the_equipped_weapon_and_stay_armed() -> void:
	var paladin := _armed(&"paladin")
	var eq := Support.equipment_of(paladin)
	var mace := eq.get_item(Items.EquipSlot.MAIN_HAND)
	var shield := eq.get_item(Items.EquipSlot.OFF_HAND)
	eq.add_to_backpack(_weapon(&"mace"))
	check_eq(_bot_gear_pass(paladin), 1, "the spare mace forges with the equipped one")
	var forged := eq.get_item(Items.EquipSlot.MAIN_HAND)
	check(forged != mace and forged.rarity == Items.Rarity.UNCOMMON, "the Uncommon mace is worn")
	check(eq.get_item(Items.EquipSlot.OFF_HAND) == shield, "the shield stays")
	check(eq.backpack.is_empty() and eq.is_armed(), "nothing left over, armed")


func test_bots_chain_forges_after_wearing_an_upgrade() -> void:
	var rogue := _armed(&"rogue")
	var eq := Support.equipment_of(rogue)
	eq.add_to_backpack(_weapon(&"dagger"))
	eq.add_to_backpack(_weapon(&"dagger", Items.Rarity.UNCOMMON))
	# The Uncommon dagger replaces a Common one, the two Commons in the backpack forge into an
	# Uncommon, which forges with the worn Uncommon into a Rare (into that hand).
	check_eq(_bot_gear_pass(rogue), 2, "two forges")
	var rarities: Array[int] = [eq.get_item(Items.EquipSlot.MAIN_HAND).rarity, eq.get_item(Items.EquipSlot.OFF_HAND).rarity]
	rarities.sort()
	check_eq(rarities, [Items.Rarity.COMMON, Items.Rarity.RARE] as Array[int], "a Rare and a Common dagger in hand")
	check(eq.backpack.is_empty(), "the backpack is empty")
	for s in [Items.EquipSlot.MAIN_HAND, Items.EquipSlot.OFF_HAND]:
		check_eq(eq.get_item(s).source_id, &"dagger", "daggers in both hands")


# --- Never without a weapon ---------------------------------------------------------------

func test_equipment_keeps_an_attacking_weapon() -> void:
	var warrior := _armed(&"warrior")
	var eq := Support.equipment_of(warrior)
	var sword := eq.get_item(Items.EquipSlot.MAIN_HAND)
	check(eq.is_last_weapon(sword), "the sword is the warrior's only weapon")
	check(not eq.unequip(Items.EquipSlot.MAIN_HAND), "refused: you need a weapon")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == sword and eq.backpack.is_empty(), "nothing changed")
	# Paladin: the shield does not attack.
	var paladin := _armed(&"paladin")
	var peq := Support.equipment_of(paladin)
	check(not peq.unequip(Items.EquipSlot.MAIN_HAND), "the mace stays (a shield is no weapon)")
	check(peq.unequip(Items.EquipSlot.OFF_HAND), "the shield may go")
	# Rogue: one of two daggers may go, not both.
	var rogue := _armed(&"rogue")
	var req := Support.equipment_of(rogue)
	check(req.unequip(Items.EquipSlot.MAIN_HAND), "one dagger off")
	check(not req.unequip(Items.EquipSlot.OFF_HAND), "not the last one")
	check(req.remove_from_backpack(req.backpack[0]), "the spare dagger can be sold")
	# A shield next to a two-hander would push the only weapon out.
	var axe := _weapon(&"two_hand_axe")
	eq.add_to_backpack(axe)
	check(eq.equip(axe), "axe on")
	var shield := _weapon(&"shield")
	eq.add_to_backpack(shield)
	check(eq.equip_disarms(shield), "the shield would disarm")
	check(not eq.equip(shield), "refused")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == axe, "axe still in hand")
	check_eq(eq.default_slot(sword), Items.EquipSlot.MAIN_HAND, "the off hand beside a two-hander is not 'empty'")
	check(eq.equip(sword), "a one-hander first")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == sword, "into the main hand")
	check(eq.equip(shield), "then the shield")
	# Weaponless (only via take()): the last usable weapon in the backpack cannot be sold.
	check(eq.take(sword), "taken out")
	check(not eq.is_armed(), "nothing attacking equipped")
	var weapons: Array[ItemInstance] = []
	for it in eq.backpack:
		if Equipment.is_attacking_weapon(it):
			weapons.append(it)
	check_eq(weapons.size(), 1, "only the axe is left")
	check(eq.is_last_weapon(axe), "the axe is the last weapon")
	check(not eq.remove_from_backpack(axe), "cannot sell / trade it away")
	eq.add_to_backpack(_weapon(&"sword"))
	check(eq.remove_from_backpack(axe), "with a spare weapon it can go")


func _join(class_id: StringName) -> PlayerSlot:
	var slot := PlayerManager.join(ScriptedInput.new("rules:%d" % PlayerManager.count()), Db.get_class_data(class_id))
	players.append(Player.create(slot))
	return slot


func _panel(slot: PlayerSlot) -> PlayerPanel:
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	panel.set_input_focus(true)
	panels.append(panel)
	return panel


func _tap(panel: PlayerPanel, slot: PlayerSlot, button: PlayerInput.Pad) -> void:
	var input := slot.input as ScriptedInput
	input.press(button)
	input.poll(1.0 / 60.0)
	panel.handle_input(input)
	input.release(button)
	input.poll(0.0)
	panel.handle_input(input)


func test_panel_refuses_to_leave_the_hero_unarmed() -> void:
	var slot := _join(&"warrior")
	var mate := _join(&"mage")
	var panel := _panel(slot)
	var eq := (slot.player as Player).equipment
	var sword := eq.get_item(Items.EquipSlot.MAIN_HAND)
	panel.select_equip_slot(Items.EquipSlot.MAIN_HAND)
	_tap(panel, slot, PlayerInput.Pad.A)
	check(not panel.menu_entry_enabled("Unequip"), "Unequip greyed out for the last weapon")
	_tap(panel, slot, PlayerInput.Pad.A)
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == sword, "still equipped")
	check_eq(panel.last_message, Equipment.NEED_WEAPON, "You need a weapon")
	panel.close_menu()
	# Weaponless (forced through take()): the sword in the backpack can neither be sold nor traded.
	eq.take(sword)
	eq.add_to_backpack(sword)
	panel.refresh()
	panel.select_backpack(0)
	_tap(panel, slot, PlayerInput.Pad.X)
	check(panel.is_menu_open() and panel.menu_labels()[panel.menu_index()] == "Sell", "X: cursor on Sell")
	check(not panel.menu_entry_enabled("Sell"), "Sell greyed out")
	check(not panel.menu_entry_enabled("Trade"), "Trade greyed out")
	var gold := RunState.gold
	_tap(panel, slot, PlayerInput.Pad.A)
	check(eq.backpack.has(sword) and RunState.gold == gold, "not sold")
	check_eq(panel.last_message, Equipment.NEED_WEAPON, "You need a weapon")
	check((mate.player as Player).equipment.backpack.is_empty(), "nothing traded")


func test_panel_equip_shows_what_a_two_hander_replaces() -> void:
	var slot := _join(&"rogue")
	var panel := _panel(slot)
	var eq := (slot.player as Player).equipment
	var bow := _weapon(&"bow")
	eq.add_to_backpack(bow)
	panel.refresh()
	panel.select_backpack(0)
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(panel.menu_entry_detail("Equip"), "Replaces Dagger + Dagger", "a bow replaces both daggers")
	_tap(panel, slot, PlayerInput.Pad.A)
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == bow, "bow equipped")
	check_eq(eq.backpack.size(), 2, "both daggers in the backpack")
	# A dagger next to the bow: the off hand "Replaces Bow".
	panel.select_backpack(0)
	_tap(panel, slot, PlayerInput.Pad.A)
	_tap(panel, slot, PlayerInput.Pad.A)
	check_eq(panel.menu_labels(), PackedStringArray(["Main Hand", "Off Hand"]), "equip choice")
	check_eq(panel.menu_entry_detail("Main Hand"), "Bow", "main hand: the bow")
	check_eq(panel.menu_entry_detail("Off Hand"), "Replaces Bow", "off hand: pushes the bow out too")
	panel.close_menu()
	# A shield next to a two-hander would leave the warrior unarmed: greyed out.
	var wslot := _join(&"warrior")
	var wpanel := _panel(wslot)
	var weq := (wslot.player as Player).equipment
	var axe := _weapon(&"two_hand_axe")
	weq.add_to_backpack(axe)
	check(weq.equip(axe), "axe on")
	var sword := weq.backpack[0]
	check(weq.remove_from_backpack(sword), "sell the spare sword")
	weq.add_to_backpack(_weapon(&"shield"))
	wpanel.refresh()
	wpanel.select_backpack(0)
	_tap(wpanel, wslot, PlayerInput.Pad.A)
	check_eq(wpanel.menu_entry_detail("Equip"), "Replaces Two-Hand Axe", "the shield would push the axe out")
	check(not wpanel.menu_entry_enabled("Equip"), "greyed out")
	_tap(wpanel, wslot, PlayerInput.Pad.A)
	check(weq.get_item(Items.EquipSlot.MAIN_HAND) == axe, "the axe stays")
	check(Equipment.NEED_WEAPON in wpanel.last_message, "reason: %s" % wpanel.last_message)


# --- Stats ---------------------------------------------------------------------------------

## Armor Specialization (+10% primary stat) is computed after the weapons' bonus stats
## (a tome's Intellect) are in place.
func test_armor_specialization_includes_weapon_bonus_stats() -> void:
	var slot := _join(&"mage")
	var p := slot.player as Player
	var eq := p.equipment
	for st in Items.ARMOR_SLOTS:
		var piece := ItemInstance.new()
		piece.display_name = "Robe Part %d" % st
		piece.slot_type = st
		piece.armor_type = ClassData.ArmorType.CLOTH
		piece.stats[Stats.INTELLECT] = 2.0
		eq.add_to_backpack(piece)
		check(eq.equip(piece), "cloth piece %d on" % st)
	check(eq.armor_spec_active(), "Armor Specialization active")
	var tome := _weapon(&"tome")
	check(tome.weapon.bonus_stats.get(Stats.INTELLECT, 0.0) > 0.0, "the tome grants Intellect")
	eq.add_to_backpack(tome)
	check(eq.equip(tome), "tome in the off hand")
	_check_spec(p, "with the tome")
	check(eq.unequip(Items.EquipSlot.OFF_HAND), "tome off")
	_check_spec(p, "without the tome")


func _check_spec(p: Player, label: String) -> void:
	var spec: Dictionary = p.stats.get_source(&"armor_spec")
	var bonus := float(spec.get(Stats.INTELLECT, 0.0))
	var rest := p.stats.get_raw(Stats.INTELLECT) - bonus
	check(bonus > 0.0, "a bonus %s" % label)
	check_near(bonus, rest * Equipment.ARMOR_SPEC_BONUS, 0.0001, "10%% of the Intellect %s" % label)
