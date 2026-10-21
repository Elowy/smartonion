extends TestCase
## M9 PATCH, Heirlooms (design_m9 §4): the ten HeirloomData rows, the scaling formula (budget by wave and rank, slot
## multipliers, the weapon formula, item level), the item (starts equipped, takes the hero's armour type, BOUND: never
## sold, traded, disenchanted, forged, enchanted, put into the team loot or dropped), the rank perks as a bonus source,
## the re-scale at every wave start, the Seeds rank-up and its save, the class gift at Level 5, the achievement
## rewards, the --heirloom flag and the lobby pick.

const Fakes := preload("res://tests/player_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")
const Support := preload("res://tests/test_loot_support.gd")

## The ten Heirlooms (design §4) with the slot each one fills.
const SLOTS := {
	&"heir_sprout_cap": Items.SlotType.HEAD, &"heir_old_layers": Items.SlotType.SHOULDERS, &"heir_apron": Items.SlotType.CHEST,
	&"heir_oven_mitts": Items.SlotType.HANDS, &"heir_pantry_breeches": Items.SlotType.LEGS, &"heir_garden_clogs": Items.SlotType.FEET,
	&"heir_garlic_braid": Items.SlotType.NECK, &"heir_harvest_signet": Items.SlotType.RING, &"heir_seed_pouch": Items.SlotType.TRINKET,
	&"heir_ancestral_peeler": Items.SlotType.WEAPON,
}

var world: Node3D
var _saved_profile: Profile
var _saved_path := ""
var _saved_persist := false
var _nodes: Array[Node] = []
var _files: Array[String] = []


func before_each() -> void:
	_saved_profile = Meta.profile
	_saved_path = Meta.path
	_saved_persist = Meta.persist
	PlayerManager.clear()
	RunState.start_run(1, 43)
	world = Fakes.make_world(tree)


func after_each() -> void:
	for n in _nodes:
		UiFakes.free_node(n)
	_nodes.clear()
	Fakes.free_world(world)
	world = null
	Meta.profile = _saved_profile
	Meta.path = _saved_path
	Meta.persist = _saved_persist
	for f in _files:
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(f + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f + suffix))
	_files.clear()
	PlayerManager.clear()
	UiFakes.reset_players()
	EnemyGrid.mark_dirty()


# --- Helpers ------------------------------------------------------------------------------------------

## A real profile (not the dev one) in memory: [param level] for every class, the Heirloom ids owned at the ranks given.
func _profile(level: int, owned: Dictionary = {}) -> Profile:
	var p := Profile.fresh()
	for cid in Db.class_ids:
		p.set_class_progress(cid, 0, level)
	for id: StringName in owned:
		p.set_heirloom_rank(id, int(owned[id]))
	Meta.profile = p
	Meta.persist = false
	Meta.path = ""
	return p


func _slot(class_id: StringName, heirloom: StringName = &"", index: int = 0) -> PlayerSlot:
	var s := Fakes.make_slot(index, class_id)
	s.heirloom = heirloom
	return s


func _hero(class_id: StringName, heirloom: StringName = &"", index: int = 0) -> Player:
	var p := Player.create(_slot(class_id, heirloom, index))
	p.stats.remove_source(&"base")
	world.add_child(p)
	return p


func _item(id: StringName, class_id: StringName, wave: int = 1, rank: int = 1) -> ItemInstance:
	return Heirlooms.create_item(Db.get_heirloom(id), Db.get_class_data(class_id), wave, rank)


# --- Data ---------------------------------------------------------------------------------------------

func test_there_are_ten_heirlooms_in_the_design_order() -> void:
	check_eq(Db.heirlooms.size(), 10, "ten Heirlooms")
	check_eq(Db.heirloom_ids, Db.HEIRLOOM_ORDER, "in the display order")
	check_eq(Db.get_heirloom(&"heir_nope"), null, "an unknown id")
	for id: StringName in SLOTS:
		var h := Db.get_heirloom(id)
		check(h != null, "%s exists" % id)
		if h != null:
			check_eq(h.slot_type, SLOTS[id], "%s fills its slot" % id)


func test_every_row_is_valid_data_with_valid_perks() -> void:
	check_eq(Heirlooms.all_problems(), [] as Array[String], "no problems")
	for id in Db.heirlooms:
		var h := Db.heirlooms[id]
		check_eq(h.perk3.size(), 1, "%s: one rank 3 perk" % id)
		check_eq(h.perk5.size(), 1, "%s: one rank 5 perk" % id)
		for e in h.perk3 + h.perk5:
			check_eq(BonusVocabulary.validate(e), "", "%s: %s is a vocabulary entry" % [id, e])
		check(h.perk3_text != "" and h.perk5_text != "" and h.source_text != "", "%s: texts" % id)
		check(h.flavor != "", "%s: flavour" % id)


func test_a_bad_row_is_reported() -> void:
	var good := Db.get_heirloom(&"heir_sprout_cap")
	check(good.problems().is_empty(), "the good one is valid")
	var bad := good.duplicate() as HeirloomData
	bad.id = &"sprout_cap"
	check(not bad.problems().is_empty(), "an id without the heir_ prefix")
	bad = good.duplicate() as HeirloomData
	bad.weights = {&"stamina": 0.5, HeirloomData.PRIMARY: 0.2}
	check(not bad.problems().is_empty(), "shares that do not add up to 1")
	bad = good.duplicate() as HeirloomData
	bad.weights = {&"no_such_stat": 1.0}
	check(not bad.problems().is_empty(), "an unknown stat")
	bad = good.duplicate() as HeirloomData
	bad.perk5 = [{"kind": "proc", "proc": {"trigger": "no_such_trigger", "effect": "buff"}}]
	check(not bad.problems().is_empty(), "a perk that is not a vocabulary entry")
	bad = good.duplicate() as HeirloomData
	bad.armor_rule = HeirloomData.RULE_ANY
	check(not bad.problems().is_empty(), "a head piece without the hero's armour rule")
	bad = good.duplicate() as HeirloomData
	bad.gift_class = &""
	check(not bad.problems().is_empty(), "no place it comes from")
	var seen_ids := {}
	var seen_names := {}
	check(good.problems(seen_ids, seen_names).is_empty(), "first time")
	check(not good.problems(seen_ids, seen_names).is_empty(), "the same id and name again")


func test_where_each_heirloom_comes_from() -> void:
	var by_class: Dictionary[StringName, StringName] = {}
	for id in Db.heirlooms:
		var h := Db.heirlooms[id]
		if h.gift_class != &"":
			by_class[h.gift_class] = h.id
		else:
			var a := Db.get_achievement(h.achievement)
			check(a != null, "%s: its achievement %s exists" % [id, h.achievement])
			var rewarded := false
			for r in a.rewards if a != null else [] as Array[Dictionary]:
				rewarded = rewarded or (StringName(str(r["kind"])) == Profile.KIND_HEIRLOOM and StringName(str(r["id"])) == id)
			check(rewarded, "%s: %s rewards it" % [id, h.achievement])
	check_eq(by_class.size(), 7, "seven class gifts, one per class")
	for cid in Db.class_ids:
		var path := Db.class_path(cid)
		check_eq(path.gift_heirloom, by_class.get(cid, &""), "%s: the class path names the same gift" % cid)
		check_eq(Db.get_heirloom(path.gift_heirloom).display_name, path.gift_heirloom_name, "%s: and its name" % cid)


# --- The formula --------------------------------------------------------------------------------------

func test_budget_table_of_the_design() -> void:
	var head := Db.get_heirloom(&"heir_sprout_cap")
	check_near(Heirlooms.budget(head, 1, 1), 3.0, 0.0001, "head, wave 1, rank 1")
	check_near(Heirlooms.budget(head, 10, 1), 7.5, 0.0001, "head, wave 10, rank 1")
	check_near(Heirlooms.budget(head, 25, 1), 15.0, 0.0001, "head, wave 25, rank 1")
	check_near(Heirlooms.budget(head, 1, 5), 3.0 * 1.32, 0.0001, "rank 5 is x1.32")
	check_near(Heirlooms.budget(head, 10, 5), 9.9, 0.0001, "wave 10, rank 5")
	check_near(Heirlooms.budget(head, 25, 5), 19.8, 0.0001, "wave 25, rank 5")
	check_near(Heirlooms.budget(head, 10, 3), 7.5 * 1.16, 0.0001, "rank 3 is x1.16")
	check_near(Heirlooms.budget(Db.get_heirloom(&"heir_apron"), 10, 1), 7.5, 0.0001, "chest 1.0")
	check_near(Heirlooms.budget(Db.get_heirloom(&"heir_pantry_breeches"), 10, 1), 7.5, 0.0001, "legs 1.0")
	check_near(Heirlooms.budget(Db.get_heirloom(&"heir_old_layers"), 10, 1), 6.0, 0.0001, "shoulders 0.8")
	check_near(Heirlooms.budget(Db.get_heirloom(&"heir_oven_mitts"), 10, 1), 6.0, 0.0001, "hands 0.8")
	check_near(Heirlooms.budget(Db.get_heirloom(&"heir_garden_clogs"), 10, 1), 6.0, 0.0001, "feet 0.8")
	check_near(Heirlooms.budget(Db.get_heirloom(&"heir_garlic_braid"), 10, 1), 5.25, 0.0001, "neck 0.7")
	check_near(Heirlooms.budget(Db.get_heirloom(&"heir_harvest_signet"), 10, 1), 5.25, 0.0001, "ring 0.7")
	check_near(Heirlooms.budget(Db.get_heirloom(&"heir_seed_pouch"), 10, 1), 5.25, 0.0001, "trinket 0.7")
	check_near(Heirlooms.budget(head, 0, 1), Heirlooms.budget(head, 1, 1), 0.0001, "a wave below 1 counts as 1")
	check_near(Heirlooms.budget(head, 10, 9), Heirlooms.budget(head, 10, 5), 0.0001, "a rank above 5 counts as 5")


func test_weapon_formula_table_of_the_design() -> void:
	check_near(Heirlooms.weapon_mult(1, 1), 1.03, 0.0001, "wave 1, rank 1")
	check_near(Heirlooms.weapon_mult(25, 1), 1.75, 0.0001, "wave 25, rank 1")
	check_near(Heirlooms.weapon_mult(25, 5), 2.05, 0.0001, "wave 25, rank 5")
	check_near(Heirlooms.weapon_mult(10, 3), 1.0 + 0.036 * 10.0, 0.0001, "wave 10, rank 3")


func test_item_level_and_rarity_by_rank() -> void:
	check_eq(Heirlooms.item_level_for(1, 1), 7, "5 + 2 w")
	check_eq(Heirlooms.item_level_for(10, 1), 25, "wave 10")
	check_eq(Heirlooms.item_level_for(10, 3), 29, "+2 per rank above the first")
	check_eq(Heirlooms.item_level_for(25, 5), 63, "wave 25 rank 5")
	check_eq(Heirlooms.rarity_for(1), Items.Rarity.UNCOMMON, "rank 1: the look of an Uncommon")
	check_eq(Heirlooms.rarity_for(3), Items.Rarity.UNCOMMON, "rank 3")
	check_eq(Heirlooms.rarity_for(4), Items.Rarity.RARE, "rank 4: Rare")
	check_eq(Heirlooms.rarity_for(5), Items.Rarity.EPIC, "rank 5: Epic, for the glow")
	# Always below a looted Epic (24 points) and the shop Epic (16 - 19) in the head slot.
	var head := Db.get_heirloom(&"heir_sprout_cap")
	check(Heirlooms.budget(head, 25, 5) < 24.0, "the best Heirloom is below a looted Epic")


func test_stats_split_the_budget_by_the_shares_on_the_heroes_primary() -> void:
	var head := Db.get_heirloom(&"heir_sprout_cap")
	var mage := Heirlooms.stats_for(head, Db.get_class_data(&"mage"), 10, 1)
	check_near(mage.get(Stats.INTELLECT, 0.0), 3.8, 0.06, "the Mage's primary share (3.75)")
	check_near(mage.get(Stats.STAMINA, 0.0), 2.3, 0.06, "stamina .3 (2.25)")
	check_near(mage.get(Stats.CRIT, 0.0), 1.5, 0.06, "crit .2")
	check(not mage.has(Stats.STRENGTH) and not mage.has(Stats.ARMOR), "a cloth head: no Strength, no Armor")
	var warrior := Heirlooms.stats_for(head, Db.get_class_data(&"warrior"), 10, 1)
	check(warrior.has(Stats.STRENGTH) and not warrior.has(Stats.INTELLECT), "the Warrior's is Strength")
	check(warrior.get(Stats.ARMOR, 0.0) >= 3.0, "plus the implicit Armor of plate (3.0 x 1.0 x tier)")
	var garlic := Heirlooms.stats_for(Db.get_heirloom(&"heir_garlic_braid"), Db.get_class_data(&"rogue"), 10, 1)
	check_near(garlic.get(Stats.LEECH, 0.0), 5.25 * 0.3 / 2.0, 0.06, "leech costs 2 points a unit")
	check(not garlic.has(Stats.ARMOR), "a necklace has no implicit Armor")
	var pouch := Heirlooms.stats_for(Db.get_heirloom(&"heir_seed_pouch"), Db.get_class_data(&"rogue"), 10, 1)
	check_near(pouch.get(Stats.FORTUNE, 0.0), 5.25 * 0.4 / 0.5, 0.06, "fortune costs half a point a unit")
	check(Heirlooms.stats_for(Db.get_heirloom(&"heir_ancestral_peeler"), Db.get_class_data(&"rogue"), 10, 1).is_empty(), "the weapon has no stats")


func test_a_higher_rank_never_lowers_a_stat_and_a_later_wave_never_either() -> void:
	for id in Db.heirlooms:
		var h := Db.heirlooms[id]
		for cid in Db.class_ids:
			var cls := Db.get_class_data(cid)
			var previous := Heirlooms.stats_for(h, cls, 1, 1)
			for rank in range(1, 6):
				for wave in [1, 5, 10, 25]:
					var now := Heirlooms.stats_for(h, cls, wave, rank)
					var lower := Heirlooms.stats_for(h, cls, 1, 1)
					for stat in lower:
						check(now.get(stat, 0.0) >= lower[stat] - 0.0001, "%s / %s: %s does not drop (wave %d rank %d)" % [id, cid, stat, wave, rank])
			check(not previous.is_empty() or h.is_weapon(), "%s / %s has stats" % [id, cid])


# --- The item -----------------------------------------------------------------------------------------

func test_the_item_takes_the_heroes_armour_type_and_is_bound() -> void:
	for id in Db.heirlooms:
		var h := Db.heirlooms[id]
		for cid in Db.class_ids:
			var cls := Db.get_class_data(cid)
			var item := Heirlooms.create_item(h, cls, 1, 1)
			check(item != null, "%s / %s is made" % [id, cid])
			if item == null:
				continue
			check_eq(item.source_id, id, "its source id is the Heirloom's")
			check(item.is_heirloom() and item.is_bound(), "%s: bound" % id)
			check_eq(item.slot_type, h.slot_type, "%s: slot" % id)
			check_eq(item.display_name, h.display_name, "%s: name" % id)
			check_eq(item.class_restriction, &"", "%s: for any class" % id)
			check(not item.unique, "%s: not a hand-made unique (its look is generated)" % id)
			if h.armor_rule == HeirloomData.RULE_HERO:
				check_eq(item.armor_type, cls.armor_type, "%s / %s: the hero's armour type" % [id, cid])
				check(item.can_be_used_by(cls), "%s / %s: wearable" % [id, cid])
			elif not h.is_weapon():
				check_eq(item.armor_type, Items.NO_ARMOR, "%s: jewellery has none" % id)
				check(item.can_be_used_by(cls), "%s / %s: usable" % [id, cid])
			else:
				check(item.is_weapon() and cls.can_use(item.weapon), "%s / %s: the weapon is usable" % [id, cid])


func test_the_peeler_copies_the_weapon_type_of_the_starting_weapon() -> void:
	var h := Db.get_heirloom(&"heir_ancestral_peeler")
	for cid in Db.class_ids:
		var cls := Db.get_class_data(cid)
		var item := Heirlooms.create_item(h, cls, 1, 1)
		check_eq(item.weapon.weapon_type, cls.main_hand.weapon_type, "%s: the same type" % cid)
		check_eq(item.weapon.hand, cls.main_hand.hand, "%s: the same hands" % cid)
		check_near(item.weapon.base_damage, cls.main_hand.base_damage * 1.03, 0.0001, "%s: damage x1.03 at wave 1" % cid)
		check_near(item.weapon.attack_speed_pct, cls.main_hand.attack_speed_pct, 0.0001, "%s: no rarity attack speed" % cid)
		var late := Heirlooms.create_item(h, cls, 25, 5)
		check_near(late.weapon.base_damage, cls.main_hand.base_damage * 2.05, 0.0001, "%s: x2.05 at wave 25 rank 5" % cid)
		var alt := Db.class_path(cid)
		if alt != null and alt.has_alt_weapon():
			var alt_item := Heirlooms.create_item(h, cls, 1, 1, true)
			check_eq(alt_item.weapon.weapon_type, alt.alt_main_hand.weapon_type, "%s: the alternative weapon's type when it starts with it" % cid)
			check(cls.can_use(alt_item.weapon), "%s: usable" % cid)


func test_rescale_changes_wave_level_stats_and_damage_in_place() -> void:
	var cls := Db.get_class_data(&"mage")
	var item := _item(&"heir_sprout_cap", &"mage")
	var id_before := item.uid
	check_eq(item.wave, 1, "made for wave 1")
	check(Heirlooms.rescale(item, cls, 10), "re-scaled")
	check_eq(item.wave, 10, "to wave 10")
	check_eq(item.item_level, 25, "Item Level 5 + 2 w")
	check_near(item.stats.get(Stats.CRIT, 0.0), 1.5, 0.06, "stats of wave 10")
	check_eq(item.uid, id_before, "the same item")
	var peeler := _item(&"heir_ancestral_peeler", &"mage")
	var base := cls.main_hand.base_damage
	Heirlooms.rescale(peeler, cls, 25)
	check_near(peeler.weapon.base_damage, base * 1.75, 0.0001, "the weapon is linear on its base, not compounding")
	Heirlooms.rescale(peeler, cls, 5)
	check_near(peeler.weapon.base_damage, base * 1.15, 0.0001, "and goes back down just as well")
	check(not Heirlooms.rescale(ItemGenerator.generate_weapon(cls.main_hand, 1, 1, false, RunState.rng), cls, 3), "a plain item is not an Heirloom")
	check(not Heirlooms.rescale(null, cls, 3), "no item")


func test_an_item_made_at_a_rank_looks_like_its_rarity() -> void:
	for rank in range(1, 6):
		var item := _item(&"heir_sprout_cap", &"warrior", 5, rank)
		check_eq(item.rarity, Heirlooms.rarity_for(rank), "rank %d" % rank)
		check_eq(item.heirloom_rank, rank, "keeps its rank")
		var look := EquipLook.from_item(item)
		check(look != null and look.rarity == item.rarity and look.set_id == &"" and look.unique_id == &"", "a generated look of that rarity")
	check(EquipLook.from_item(_item(&"heir_sprout_cap", &"warrior", 5, 5)).glows(), "rank 5 glows")
	check(not EquipLook.from_item(_item(&"heir_sprout_cap", &"warrior", 5, 1)).glows(), "rank 1 does not")


# --- Bound ---------------------------------------------------------------------------------------------

func test_a_bound_item_is_never_sold_traded_or_disenchanted() -> void:
	var item := _item(&"heir_old_layers", &"paladin")
	check(not item.can_sell(), "never sold")
	check(not item.can_trade(), "never traded")
	check(not item.can_disenchant(), "never disenchanted")
	check(not item.can_be_shared(), "never shared")
	check_eq(Enchanter.dust_for(item), 0, "no Dust")
	check(not Enchanter.can_disenchant(item), "the Enchanter says no")
	check(Enchanter.disenchant_blocked_reason(item) != "", "and why")
	var eq := Equipment.new(Db.get_class_data(&"paladin"))
	eq.equip_starting_weapons()
	eq.add_to_backpack(item)
	check_eq(Enchanter.disenchant(eq, item), 0, "disenchanting gives nothing")
	check(eq.backpack.has(item), "and the item stays")
	check(not eq.remove_from_backpack(item), "the backpack will not give it up (sell, trade, disenchant)")
	check(eq.backpack.has(item), "still there")
	# A control: an ordinary backpack item sells as before.
	var plain := ItemGenerator.generate(ItemGenerator.Source.SHOP, 3, RunState.rng, {})
	eq.add_to_backpack(plain)
	check(plain.can_sell() and plain.can_trade() and eq.remove_from_backpack(plain), "an ordinary item still leaves")


func test_a_bound_item_never_enters_the_team_loot_a_bag_or_a_roll() -> void:
	var item := _item(&"heir_garlic_braid", &"warrior")
	RunState.team_loot.clear()
	RunState.add_team_loot(item)
	check(RunState.team_loot.is_empty(), "the team loot refuses it")
	check_eq(LootDrops.drop_item(item, Vector3.ZERO, world), null, "no bag is made for it")
	check_eq(world.get_child_count(), 0, "nothing was dropped into the world")
	var slot := _slot(&"warrior")
	var roll := LootRoll.create(item)
	check(not roll.can_need(slot), "nobody can Need it")
	var plain := ItemGenerator.generate(ItemGenerator.Source.SHOP, 3, RunState.rng, {})
	RunState.add_team_loot(plain)
	check_eq(RunState.team_loot.size(), 1, "an ordinary item still goes in")
	RunState.team_loot.clear()


func test_a_bound_weapon_is_never_forged_and_nothing_is_enchanted() -> void:
	var cls := Db.get_class_data(&"warrior")
	var peeler := _item(&"heir_ancestral_peeler", &"warrior")
	var eq := Equipment.new(cls)
	eq.equip_starting_weapons()
	eq.add_to_backpack(peeler)
	check_eq(Forge.blocked_reason(eq, peeler), Forge.REASON_BOUND, "the Forge says it is bound")
	check(not Forge.is_forgeable(peeler), "not forgeable")
	check_eq(Forge.forge(eq, peeler), null, "forging refuses")
	for id in Db.heirlooms:
		var item := Heirlooms.create_item(Db.heirlooms[id], cls, 5, 5)
		check_eq(Enchanter.blocked_reason(item, Enchanter.Action.IMBUE), Enchanter.REASON_BOUND, "%s: no Imbue" % id)
		check(not Enchanter.is_enchantable(item), "%s: nothing to do at the Enchanter" % id)


func test_a_bot_with_the_bound_peeler_enchants_something_else() -> void:
	var cls := Db.get_class_data(&"rogue")
	var peeler := _item(&"heir_ancestral_peeler", &"rogue", 12, 5)
	check(peeler.is_bound() and peeler.rarity > Items.Rarity.COMMON, "the Peeler is bound and rarer than a Common")
	var eq := Equipment.new(cls)
	eq.slots[Items.EquipSlot.MAIN_HAND] = peeler
	check_eq(Enchanter.best_weapon(eq), null, "only the Peeler in hand: no weapon to enchant")
	check_eq(Enchanter.bot_target(eq), null, "and nothing else to work on")
	check(Enchanter.bot_plan(peeler, cls).is_empty(), "no plan for a bound item")
	# A Common weapon in the other hand is still better than the bound Peeler: it is the bot's weapon.
	var dagger := Support.make_weapon(&"dagger", Items.Rarity.COMMON)
	eq.slots[Items.EquipSlot.OFF_HAND] = dagger
	check_eq(Enchanter.best_weapon(eq), dagger, "the other hand's weapon, never the Peeler")
	check_eq(Enchanter.bot_target(eq), dagger, "bot_target follows")
	# No other weapon: the bot falls back to its Epic armour.
	eq.slots.erase(Items.EquipSlot.OFF_HAND)
	var chest := Support.make_armor(90, ClassData.ArmorType.LEATHER, 20, Items.Rarity.EPIC, Items.SlotType.CHEST)
	eq.slots[Items.EquipSlot.CHEST] = chest
	check_eq(Enchanter.bot_target(eq), chest, "the Epic chest piece")
	check(not Enchanter.bot_plan(chest, cls).is_empty(), "with something to do")


func test_the_panel_greys_out_sell_and_trade_for_a_bound_item() -> void:
	var hero := _hero(&"warrior")
	var item := _item(&"heir_old_layers", &"warrior")
	hero.equipment.add_to_backpack(item)
	var mate := _hero(&"mage", &"", 1)
	check(mate != null, "a teammate (the Trade entry needs one)")
	var panel := PlayerPanel.create(hero.slot)
	world.add_child(panel)
	_nodes.append(panel)
	var entries := panel._backpack_entries(item)
	var sell: PlayerPanel.MenuEntry = null
	var trade: PlayerPanel.MenuEntry = null
	var names: Array[String] = []
	for e in entries:
		names.append(e.label)
		if e.label == "Sell":
			sell = e
		elif e.label == "Trade":
			trade = e
	check(sell != null and not sell.enabled and sell.reason == Heirlooms.NO_SELL_TEXT, "Sell is greyed out: %s" % str(names))
	check(not ("Disenchant" in names), "no Disenchant entry")
	if trade != null:
		check(not trade.enabled and trade.reason == Heirlooms.NO_TRADE_TEXT, "Trade is greyed out")
	var money := RunState.gold
	panel._do_sell(item)
	check_eq(RunState.gold, money, "selling it through the panel pays nothing")
	check(hero.equipment.backpack.has(item), "and keeps it")


func test_the_tooltip_names_the_rank_the_perks_and_the_binding() -> void:
	var item := _item(&"heir_sprout_cap", &"mage", 5, 3)
	var tip := ItemTooltip.create()
	world.add_child(tip)
	_nodes.append(tip)
	tip.show_item(item, Db.get_class_data(&"mage"))
	var text := _all_text(tip)
	check(text.contains("Heirloom") and text.contains("Rank 3"), "the rank: %s" % text.left(120))
	check(text.contains("+3 Haste"), "the rank 3 perk")
	check(text.contains("Rank 5: At the start of every wave"), "the rank 5 perk, not reached yet")
	check(text.contains(Heirlooms.BOUND_TEXT), "and that it is bound")
	check(not text.contains("Sell Price"), "no sell price")


func _all_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += (node as Label).text + "\n"
	for c in node.get_children():
		out += _all_text(c)
	return out


# --- The hero -----------------------------------------------------------------------------------------

func test_the_heirloom_starts_equipped_on_the_hero() -> void:
	var mage := _hero(&"mage", &"heir_sprout_cap")
	var item := mage.equipment.get_item(Items.EquipSlot.HEAD)
	check(item != null and item.is_heirloom(), "the Sprout Cap is on the Mage's head")
	check_eq(mage.heirloom_id, &"heir_sprout_cap", "the hero remembers it")
	check_eq(mage.stats.get_source(&"item:head"), item.equip_stats(), "its stats are a stat source")
	check(mage.stats.get_stat(Stats.INTELLECT) > Db.get_class_data(&"mage").base_stats.get(Stats.INTELLECT, 0.0), "Intellect went up")
	check(mage.equipment.backpack.is_empty(), "nothing else moved")
	var plain := _hero(&"mage", &"", 1)
	check(plain.equipment.get_item(Items.EquipSlot.HEAD) == null, "no pick, no item")
	check(plain.bonuses.effects_of(Heirlooms.SOURCE).is_empty(), "and no source")
	check_eq(plain.heirloom_id, &"", "nothing remembered")


func test_the_armour_heirloom_counts_for_armor_specialization_and_the_ring_goes_to_a_ring_slot() -> void:
	var warrior := _hero(&"warrior", &"heir_apron")
	var chest := warrior.equipment.get_item(Items.EquipSlot.CHEST)
	check_eq(chest.armor_type, Db.get_class_data(&"warrior").armor_type, "the Warrior's armour type")
	var ring := _hero(&"rogue", &"heir_harvest_signet", 1)
	check(ring.equipment.get_item(Items.EquipSlot.RING_1) != null, "a ring starts in the first ring slot")
	var braid := _hero(&"shaman", &"heir_garlic_braid", 2)
	check(braid.equipment.get_item(Items.EquipSlot.NECK) != null, "a necklace on the neck")
	var trinket := _hero(&"hunter", &"heir_seed_pouch", 3)
	check(trinket.equipment.get_item(Items.EquipSlot.TRINKET_1) != null, "a trinket in the first trinket slot")


func test_the_weapon_heirloom_takes_the_main_hand_and_the_old_weapon_goes_to_the_backpack() -> void:
	for cid in Db.class_ids:
		var hero := _hero(cid, &"heir_ancestral_peeler", Db.class_ids.find(cid) % 4)
		var main := hero.equipment.get_item(Items.EquipSlot.MAIN_HAND)
		check(main != null and main.is_heirloom() and main.is_weapon(), "%s: the Peeler is in the main hand" % cid)
		check_eq(hero.main_hand, main.weapon, "%s: and it is the weapon the hero fights with" % cid)
		check(hero.equipment.is_armed(), "%s: armed" % cid)
		check_eq(hero.equipment.backpack.size(), 1, "%s: the starting weapon waits in the backpack" % cid)
		check(hero.equipment.backpack[0].can_sell(), "%s: and that one can be sold" % cid)
		hero.free()
	# (heroes of the loop were freed: the world is reused by the next test)


func test_a_pick_the_hero_cannot_carry_is_dropped() -> void:
	var unknown := _hero(&"mage", &"heir_nope")
	check_eq(unknown.heirloom_id, &"", "an unknown id")
	check(unknown.equipment.get_item(Items.EquipSlot.HEAD) == null, "nothing equipped")
	_profile(4)
	var low := _hero(&"mage", &"heir_sprout_cap", 1)
	check_eq(low.heirloom_id, &"", "no slot below Class Level 5")
	_profile(5)
	var unowned := _hero(&"mage", &"heir_sprout_cap", 2)
	check_eq(unowned.heirloom_id, &"", "not owned yet")
	_profile(5, {&"heir_sprout_cap": 1})
	var fine := _hero(&"mage", &"heir_sprout_cap", 3)
	check_eq(fine.heirloom_id, &"heir_sprout_cap", "level 5 and owned")
	check(fine.equipment.get_item(Items.EquipSlot.HEAD) != null, "equipped")


func test_the_rank_the_profile_has_decides_the_item() -> void:
	_profile(5, {&"heir_sprout_cap": 4})
	var hero := _hero(&"mage", &"heir_sprout_cap")
	var item := hero.equipment.get_item(Items.EquipSlot.HEAD)
	check_eq(item.heirloom_rank, 4, "rank 4")
	check_eq(item.rarity, Items.Rarity.RARE, "looks Rare")
	check_eq(item.item_level, Heirlooms.item_level_for(1, 4), "Item Level of rank 4")


func test_the_rank_perks_switch_on_at_rank_3_and_5() -> void:
	var hero := _hero(&"mage", &"heir_sprout_cap")
	check(hero.bonuses.effects_of(Heirlooms.SOURCE).is_empty(), "rank 1 (the dev profile): no perk")
	hero.free()
	for rank in [2, 3, 4, 5]:
		_profile(5, {&"heir_sprout_cap": rank})
		var h := _hero(&"mage", &"heir_sprout_cap", 1)
		var entries := h.bonuses.effects_of(Heirlooms.SOURCE)
		var wanted := 0 if rank < 3 else (1 if rank < 5 else 2)
		check_eq(entries.size(), wanted, "rank %d: %d perk entries" % [rank, wanted])
		if rank >= 3:
			check_eq(entries[0].get("id", ""), "heirloom:heir_sprout_cap:perk3", "tagged")
			check_eq(entries[0].get("label", ""), "Sprout Cap", "labelled with the Heirloom")
		h.free()


func test_the_perk_lasts_only_while_the_heirloom_is_worn() -> void:
	_profile(5, {&"heir_sprout_cap": 3})
	var hero := _hero(&"mage", &"heir_sprout_cap")
	var with_cap := hero.stats.get_stat(Stats.HASTE)
	check(not hero.bonuses.effects_of(Heirlooms.SOURCE).is_empty(), "the perk is live")
	check(hero.equipment.unequip(Items.EquipSlot.HEAD), "taken off")
	check(hero.bonuses.effects_of(Heirlooms.SOURCE).is_empty(), "the perk goes with it")
	check_near(with_cap - hero.stats.get_stat(Stats.HASTE), 3.0, 0.01, "+3 Haste from the perk (the item itself has none)")
	check(hero.equipment.backpack[0].is_heirloom(), "the Heirloom sits in the backpack, still bound")
	check(hero.equipment.equip(hero.equipment.backpack[0]), "and can be put back on")
	check(not hero.bonuses.effects_of(Heirlooms.SOURCE).is_empty(), "the perk is back")


func test_the_rank_5_wave_start_buff_fires() -> void:
	_profile(5, {&"heir_sprout_cap": 5})
	var hero := _hero(&"mage", &"heir_sprout_cap")
	var before := hero.stats.get_stat(Stats.HASTE)
	hero.begin_wave()
	check_near(hero.stats.get_stat(Stats.HASTE) - before, 8.0, 0.01, "+8 Haste at the start of the wave")
	hero.end_wave()
	check_near(hero.stats.get_stat(Stats.HASTE), before, 0.01, "gone when the wave ends")


func test_every_rank_5_perk_is_accepted_by_the_engine() -> void:
	for id in Db.heirlooms:
		_profile(5, {id: 5})
		var cls := &"warrior"
		var hero := _hero(cls, id, Db.heirloom_ids.find(id) % 4)
		var entries := hero.bonuses.effects_of(Heirlooms.SOURCE)
		check_eq(entries.size(), 2, "%s: both perks are live" % id)
		check(hero.heirloom_id == id, "%s: carried" % id)
		hero.begin_wave()
		hero.end_wave()
		hero.free()


func test_rescale_player_grows_the_worn_heirloom_and_leaves_other_gear_alone() -> void:
	var hero := _hero(&"warrior", &"heir_apron")
	var item := hero.equipment.get_item(Items.EquipSlot.CHEST)
	var weapon := hero.equipment.get_item(Items.EquipSlot.MAIN_HAND)
	var weapon_damage := weapon.weapon.base_damage
	var level_before := item.item_level
	var seen: Array[int] = [0]
	hero.equipment.changed.connect(func() -> void: seen[0] += 1)
	check_eq(Heirlooms.rescale_player(hero, 10), 1, "one Heirloom re-scaled")
	check_eq(seen[0], 1, "the equipment was re-applied once")
	check(item.item_level > level_before and item.wave == 10, "it grew")
	check_eq(hero.stats.get_source(&"item:chest"), item.equip_stats(), "and the stat source follows")
	check_near(weapon.weapon.base_damage, weapon_damage, 0.0001, "the starting weapon is untouched")
	var none := _hero(&"warrior", &"", 1)
	var again: Array[int] = [0]
	none.equipment.changed.connect(func() -> void: again[0] += 1)
	check_eq(Heirlooms.rescale_player(none, 10), 0, "a hero without one: nothing")
	check_eq(again[0], 0, "and no equipment change")
	# A backpacked Heirloom is re-scaled too (it keeps up while it waits).
	hero.equipment.unequip(Items.EquipSlot.CHEST)
	Heirlooms.rescale_player(hero, 20)
	check_eq(item.wave, 20, "an Heirloom in the backpack follows the waves")


# --- Seeds, ranks and the save ------------------------------------------------------------------------

func _file(name: String) -> String:
	var path := "user://test_m9_patch_%s.json" % name
	_files.append(path)
	return path


func test_the_rank_prices() -> void:
	check_eq(HeirloomData.price_for_rank(2), 60, "R2")
	check_eq(HeirloomData.price_for_rank(3), 120, "R3")
	check_eq(HeirloomData.price_for_rank(4), 240, "R4")
	check_eq(HeirloomData.price_for_rank(5), 480, "R5")
	check_eq(HeirloomData.price_for_rank(1), 0, "R1 is free")
	check_eq(HeirloomData.price_for_rank(6), 0, "there is no R6")
	check_eq(60 + 120 + 240 + 480, 900, "900 Seeds from R1 to R5, 9000 for all ten")


func test_rank_ups_cost_seeds_and_save_at_once() -> void:
	var path := _file("ranks")
	Meta.configure(&"fresh", path, true)
	var p := Meta.profile
	p.unlock(Profile.KIND_HEIRLOOM, &"heir_sprout_cap")
	p.earn_seeds(900)
	var saves := Meta.save_count
	var expect_left := [840, 720, 480, 0]
	var heard: Array[int] = []
	Meta.heirloom_ranked.connect(func(_id: StringName, rank: int) -> void: heard.append(rank))
	check_eq(Meta.heirloom_rank(&"heir_sprout_cap"), 1, "owned at rank 1")
	check_eq(Meta.heirloom_rank_price(&"heir_sprout_cap"), 60, "the next rank costs 60")
	for i in 4:
		check_eq(Meta.heirloom_rank_up_reason(&"heir_sprout_cap"), "", "rank %d can be bought" % (i + 2))
		check(Meta.rank_up_heirloom(&"heir_sprout_cap"), "bought rank %d" % (i + 2))
		check_eq(Meta.seeds(), expect_left[i], "Seeds after rank %d" % (i + 2))
		check_eq(Meta.heirloom_rank(&"heir_sprout_cap"), i + 2, "the rank")
		check_eq(Meta.save_count, saves + i + 1, "exactly one write per purchase")
		var on_disk := Profile.load_file(path)
		check_eq(on_disk.heirloom_rank(&"heir_sprout_cap"), i + 2, "the file has the rank at once")
		check_eq(on_disk.seeds, expect_left[i], "and the Seeds")
	check_eq(heard, [2, 3, 4, 5] as Array[int], "the signal")
	check_eq(Meta.heirloom_rank_up_reason(&"heir_sprout_cap"), "Top rank", "rank 5 is the top")
	check(not Meta.rank_up_heirloom(&"heir_sprout_cap"), "no sixth rank")
	check_eq(Meta.heirloom_rank_price(&"heir_sprout_cap"), 0, "no price at the top")


func test_a_rank_up_without_the_seeds_or_the_heirloom_changes_nothing() -> void:
	var path := _file("poor")
	Meta.configure(&"fresh", path, true)
	var p := Meta.profile
	p.unlock(Profile.KIND_HEIRLOOM, &"heir_apron")
	p.earn_seeds(59)
	var saves := Meta.save_count
	check_eq(Meta.heirloom_rank_up_reason(&"heir_apron"), "Not enough Seeds", "one Seed short")
	check(not Meta.rank_up_heirloom(&"heir_apron"), "refused")
	check_eq(Meta.seeds(), 59, "no Seeds were taken")
	check_eq(Meta.heirloom_rank(&"heir_apron"), 1, "no rank was given")
	check_eq(Meta.save_count, saves, "nothing was written")
	check(not Meta.rank_up_heirloom(&"heir_oven_mitts"), "an Heirloom that is not owned cannot be ranked up")
	check_eq(Meta.heirloom_rank_up_reason(&"heir_oven_mitts"), "Not owned yet", "and says why")
	check_eq(Meta.heirloom_rank(&"heir_nope"), 0, "an unknown id has no rank")
	Meta.configure(&"", "", true)  # the dev profile of an automated run
	check(Meta.is_dev(), "dev profile")
	check(not Meta.rank_up_heirloom(&"heir_sprout_cap"), "the dev profile has no Seeds to spend")
	check_eq(Meta.heirloom_rank(&"heir_sprout_cap"), 1, "but owns every Heirloom at rank 1")
	check_eq(Meta.owned_heirloom_ids().size(), 10, "all ten")


func test_the_max_profile_owns_everything_at_the_top_rank() -> void:
	var p := Profile.max_profile(Db.class_ids, Db.heirloom_ids)
	for id in Db.heirloom_ids:
		check_eq(p.heirloom_rank(id), 5, "%s at rank 5" % id)
	Meta.configure(&"max", "", true)
	check_eq(Meta.heirloom_rank(&"heir_ancestral_peeler"), 5, "--profile=max")
	var hero := _hero(&"rogue", &"heir_garden_clogs")
	check_eq(hero.equipment.get_item(Items.EquipSlot.FEET).heirloom_rank, 5, "a hero of the max profile wears rank 5")
	check_eq(Profile.max_profile(Db.class_ids).heirloom_rank(&"heir_sprout_cap"), 1, "(without the list the old behaviour)")


# --- The gifts ----------------------------------------------------------------------------------------

func test_each_class_gives_its_heirloom_at_level_5() -> void:
	for cid in Db.class_ids:
		var p := Profile.fresh()
		var gift := Db.class_path(cid).gift_heirloom
		for level in range(2, 5):
			ClassLevels.grant_level(p, cid, level)
		check(not p.has_unlock(Profile.KIND_HEIRLOOM, gift), "%s: not before Level 5" % cid)
		ClassLevels.grant_level(p, cid, 5)
		check(p.has_unlock(Profile.KIND_HEIRLOOM, gift), "%s: %s at Level 5" % [cid, gift])
		check_eq(p.heirloom_rank(gift), 1, "%s: at rank 1" % cid)
		check_eq(p.unlocked_ids(Profile.KIND_HEIRLOOM).size(), 1, "%s: only its own" % cid)


func test_reaching_level_5_through_xp_grants_the_gift_once_and_the_slot_opens() -> void:
	var p := _profile(1)
	var xp := ClassLevels.xp_for_level(5)
	check_eq(Meta.heirloom_slots(&"mage"), 0, "no slot at level 1")
	ClassLevels.award_xp(p, &"mage", xp - 1)
	check(not p.has_unlock(Profile.KIND_HEIRLOOM, &"heir_sprout_cap"), "one XP short")
	check_eq(Meta.heirloom_slots(&"mage"), 0, "no slot at level 4")
	ClassLevels.award_xp(p, &"mage", 1)
	check(p.has_unlock(Profile.KIND_HEIRLOOM, &"heir_sprout_cap"), "the gift")
	check_eq(Meta.heirloom_slots(&"mage"), 1, "and the slot")
	var again := p.unlocked_ids(Profile.KIND_HEIRLOOM).size()
	ClassLevels.award_xp(p, &"mage", 500)
	check_eq(p.unlocked_ids(Profile.KIND_HEIRLOOM).size(), again, "granted once")
	check(Heirlooms.available(&"mage", &"heir_sprout_cap"), "the Mage may take it into a run")
	check(not Heirlooms.available(&"warrior", &"heir_apron"), "the Warrior has neither the slot nor the Heirloom")


func test_the_three_achievements_hand_out_their_heirlooms() -> void:
	var names := {&"ach_harvest_home": "Signet of the First Harvest", &"ach_gremlin_roundup": "Lucky Seed Pouch", &"ach_first_pungent": "Ancestral Peeler"}
	var gives := {&"ach_harvest_home": &"heir_harvest_signet", &"ach_gremlin_roundup": &"heir_seed_pouch", &"ach_first_pungent": &"heir_ancestral_peeler"}
	for aid: StringName in names:
		var a := Db.get_achievement(aid)
		check(a != null, "%s exists" % aid)
		var p := Profile.fresh()
		AchievementEngine.grant_rewards(p, a)
		check(p.has_unlock(Profile.KIND_HEIRLOOM, gives[aid]), "%s gives %s" % [aid, gives[aid]])
		check(Db.get_heirloom(gives[aid]) != null, "and the Heirloom exists")
		check_eq(AchievementTexts.reward_line(a.rewards[a.rewards.size() - 1]), "Heirloom: %s" % names[aid], "the reward line names it")
		check_eq(p.heirloom_rank(gives[aid]), 1, "at rank 1")


func test_an_achievement_reward_line_reads_the_heirloom_data() -> void:
	var line := AchievementTexts.reward_line({"kind": "heirloom", "id": "heir_garlic_braid"})
	check_eq(line, "Heirloom: Garlic Braid", "the name comes from the data when the reward names none")


# --- The flag -----------------------------------------------------------------------------------------

func _opts(args: Array) -> LaunchOptions:
	return LaunchOptions.parse(PackedStringArray(args))


func test_the_heirloom_flag_is_validated() -> void:
	var o := _opts(["--heirloom=heir_sprout_cap"])
	check(o.unknown.is_empty() and o.heirloom == &"heir_sprout_cap", "a known id")
	var bad := _opts(["--heirloom=heir_nope"])
	check_eq(bad.unknown.size(), 1, "an unknown id is an unknown argument (bad_args)")
	check_eq(bad.heirloom, &"", "and nothing is applied")
	check_eq(_opts(["--heirloom="]).unknown.size(), 1, "an empty value too")
	check_eq(_opts(["--smoke"]).heirloom, &"", "no flag, none")


func test_the_flag_gives_every_hero_the_heirloom_and_waves_re_scale_it() -> void:
	var main := Main.create(_opts(["--players=4", "--heirloom=heir_old_layers"]))
	tree.root.add_child(main)
	_nodes.append(main)
	main._add_bots()
	main.start_run()
	check_eq(main.players.size(), 4, "four heroes")
	for p in main.players:
		var item := p.equipment.get_item(Items.EquipSlot.SHOULDERS)
		check(item != null and item.is_heirloom(), "%s wears the Mantle" % p.name)
		check_eq(item.wave, 1, "made for wave 1")
		check_eq(p.heirloom_id, &"heir_old_layers", "remembered")
	main.start_wave(7)
	for p in main.players:
		var item := p.equipment.get_item(Items.EquipSlot.SHOULDERS)
		check_eq(item.wave, 7, "%s: re-scaled to wave 7 at the wave start" % p.name)
		check_eq(item.item_level, Heirlooms.item_level_for(7, 1), "Item Level")
		check_eq(p.stats.get_source(&"item:shoulders"), item.equip_stats(), "stats follow")


func test_runs_without_the_flag_start_without_heirlooms() -> void:
	var main := Main.create(_opts(["--players=4"]))
	tree.root.add_child(main)
	_nodes.append(main)
	main._add_bots()
	main.start_run()
	for p in main.players:
		check_eq(p.heirloom_id, &"", "%s: nothing" % p.name)
		check(Heirlooms.held(p.equipment).is_empty(), "%s: no Heirloom held" % p.name)
		check(p.bonuses.effects_of(Heirlooms.SOURCE).is_empty(), "%s: no source" % p.name)


# --- The lobby's pick ---------------------------------------------------------------------------------

func test_toggle_puts_an_owned_heirloom_in_the_slot_and_replaces_it() -> void:
	var slot := _slot(&"mage")
	check_eq(Heirlooms.toggle(slot, &"heir_sprout_cap"), Heirlooms.RESULT_ADDED, "the dev profile owns all")
	check_eq(slot.heirloom, &"heir_sprout_cap", "on the slot")
	check_eq(Heirlooms.toggle(slot, &"heir_apron"), Heirlooms.RESULT_ADDED, "another replaces it (one slot)")
	check_eq(slot.heirloom, &"heir_apron", "the new one")
	check_eq(Heirlooms.toggle(slot, &"heir_apron"), Heirlooms.RESULT_REMOVED, "the same again takes it out")
	check_eq(slot.heirloom, &"", "empty")
	check_eq(Heirlooms.toggle(slot, &"heir_nope"), Heirlooms.RESULT_INVALID, "unknown")
	check_eq(Heirlooms.toggle(null, &"heir_apron"), Heirlooms.RESULT_INVALID, "no slot")


func test_toggle_needs_the_slot_and_the_heirloom_and_remembers_per_class() -> void:
	var p := _profile(4, {&"heir_sprout_cap": 1})
	var slot := _slot(&"mage")
	check_eq(Heirlooms.toggle(slot, &"heir_sprout_cap"), Heirlooms.RESULT_NO_SLOT, "no slot below Class Level 5")
	p.set_class_progress(&"mage", 0, 5)
	check_eq(Heirlooms.toggle(slot, &"heir_apron"), Heirlooms.RESULT_LOCKED, "not owned")
	check_eq(Heirlooms.toggle(slot, &"heir_sprout_cap"), Heirlooms.RESULT_ADDED, "owned and the slot is open")
	check_eq(p.loadout(&"mage")["heirloom"], &"heir_sprout_cap", "remembered for the class")
	Meta.apply_loadout(_slot(&"mage", &"", 1))
	var again := _slot(&"mage", &"", 1)
	Meta.apply_loadout(again)
	check_eq(again.heirloom, &"heir_sprout_cap", "the next hero of the class starts with it")
	var warrior := _slot(&"warrior", &"", 2)
	Meta.apply_loadout(warrior)
	check_eq(warrior.heirloom, &"", "another class does not")


func test_prune_drops_what_the_class_cannot_carry() -> void:
	var p := _profile(1, {&"heir_apron": 1})
	p.set_class_progress(&"warrior", 0, 5)
	var slot := _slot(&"warrior", &"heir_apron")
	Heirlooms.prune(slot)
	check_eq(slot.heirloom, &"heir_apron", "a Warrior with the slot and the Heirloom keeps it")
	slot.class_data = Db.get_class_data(&"mage")
	Heirlooms.prune(slot)
	check_eq(slot.heirloom, &"", "the Mage has no slot yet")
	Heirlooms.prune(null)


func test_the_log_line_names_the_hero_the_rank_and_the_numbers() -> void:
	var item := _item(&"heir_sprout_cap", &"mage", 3, 2)
	var line := Heirlooms.log_line("P2", &"mage", item, true, 3)
	check(line.begins_with("heirloom: P2 mage Sprout Cap rank 2 on wave 3, item level 13, equipped:"), line)
	check(line.contains("Intellect"), "with its stats: " + line)
	var peeler := Heirlooms.log_line("P1", &"warrior", _item(&"heir_ancestral_peeler", &"warrior", 3, 1), false, 3)
	check(peeler.contains("in the backpack: weapon damage"), peeler)
