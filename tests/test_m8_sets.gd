extends TestCase
## M8 P0 – class-independent tier sets (SetData.class_id empty): Db.sets_for_class, the generator's
## set roll over several eligible sets (draw order), the Black Market's candidates, set counting
## across classes, the tooltip and the generic armour look. No set content ships with P0: the sets
## here are fixtures built by set_fixtures.gd (a mail set, a plate set ...) and removed after each
## test. The rules the shipped class-free sets must follow are checked over whatever Db holds.

const Fakes := preload("res://tests/player_fakes.gd")
const Rules := preload("res://tests/content_rules.gd")
const SetFixtures := preload("res://tests/set_fixtures.gd")

const LOOT := ItemGenerator.Source.LOOT
const SHOP := ItemGenerator.Source.SHOP
## The fixture class-free sets by id, with their armour type (_all_armour_sets).
const FREE_ARMOR: Dictionary[StringName, int] = {
	&"zz_free_cloth": ClassData.ArmorType.CLOTH, &"zz_free_leather": ClassData.ArmorType.LEATHER,
	&"zz_free_mail": ClassData.ArmorType.MAIL, &"zz_free_plate": ClassData.ArmorType.PLATE,
}

var fixtures: SetFixtures
var world: Node3D
var tip: ItemTooltip


func before_each() -> void:
	RunState.start_run(1, 41)
	fixtures = SetFixtures.new()
	Enemy.invalidate_player_cache()


func after_each() -> void:
	if tip != null and is_instance_valid(tip):
		tip.get_parent().remove_child(tip)
		tip.free()
	tip = null
	if world != null:
		Fakes.free_world(world)
		world = null
	PlayerManager.clear()
	fixtures.restore()
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


func _ids(sets: Array[SetData]) -> Array[StringName]:
	var out: Array[StringName] = []
	for s in sets:
		out.append(s.id)
	return out


## Fixtures: one free set per armour type (cloth, leather, mail, plate).
func _all_armour_sets() -> void:
	fixtures.add_free_set(&"zz_free_cloth", ClassData.ArmorType.CLOTH)
	fixtures.add_free_set(&"zz_free_leather", ClassData.ArmorType.LEATHER)
	fixtures.add_free_set(&"zz_free_mail", ClassData.ArmorType.MAIL)
	fixtures.add_free_set(&"zz_free_plate", ClassData.ArmorType.PLATE)


## The fixture free sets a class collects (Rules.free_set_fits), by id.
func _free_for(class_id: StringName) -> Array[StringName]:
	var armor := int(Db.get_class_data(class_id).armor_type)
	var out: Array[StringName] = []
	for id in FREE_ARMOR:
		if Rules.free_set_fits(FREE_ARMOR[id], armor):
			out.append(id)
	return out


## The set ids of [param class_id]'s roll pool: its own set, then its free sets.
func _pool_of(class_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = [Db.set_for_class(class_id).id]
	out.append_array(_free_for(class_id))
	return out


## The set ids of a team's roll pool: the classes' own sets in team order, then the free sets any of
## them collects (by id).
func _team_pool(ids: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ids:
		var own := Db.set_for_class(id).id
		if own not in out:
			out.append(own)
	for free_id in FREE_ARMOR:
		for id in ids:
			if free_id in _free_for(id) and free_id not in out:
				out.append(free_id)
	return out


## [param n] Epic rolls of [param source] at [param wave]; the set pieces among them.
func _set_rolls(source: ItemGenerator.Source, wave: int, n: int, options: Dictionary = {}, seed_value: int = 7) -> Array[ItemInstance]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var opts := options.duplicate()
	opts[&"rarity"] = Items.Rarity.EPIC
	var out: Array[ItemInstance] = []
	for i in n:
		var it := ItemGenerator.generate(source, wave, rng, opts)
		if it.set_id != &"":
			out.append(it)
	return out


func _team(ids: Array[StringName]) -> Array[ClassData]:
	var out: Array[ClassData] = []
	for id in ids:
		out.append(Db.get_class_data(id))
	return out


# --- Db.sets_for_class ------------------------------------------------------------------------

func test_a_class_free_set_belongs_to_no_class() -> void:
	var s := fixtures.add_free_set(&"zz_free_mail", ClassData.ArmorType.MAIL)
	check_eq(s.class_id, &"", "SetData.class_id empty = class-independent")
	check(Db.set_for_class(&"") == null, "set_for_class(\"\") is nobody's own set")
	check(Db.get_set(&"zz_free_mail") == s, "Db.get_set finds it")
	for id in Rules.classes_with("set"):
		var own := Db.set_for_class(id)
		check(own != null and own != s and own.class_id == id, "%s: its own set is its class's, not the free one" % id)


func test_sets_for_class_lists_the_own_set_then_the_free_sets_the_class_can_collect() -> void:
	_all_armour_sets()
	for id in [&"warrior", &"mage", &"rogue", &"warlock", &"paladin"]:
		check_eq(_ids(Db.sets_for_class(id)), _pool_of(id), "%s: its own set, then the free sets it collects, by id" % id)
	# Whatever the rule, a class collects the free sets of its own armour and never a heavier one.
	check(&"zz_free_plate" in _ids(Db.sets_for_class(&"warrior")), "plate: the plate set")
	check(&"zz_free_cloth" in _ids(Db.sets_for_class(&"mage")), "cloth: the cloth set")
	for heavier in [&"zz_free_leather", &"zz_free_mail", &"zz_free_plate"]:
		check(heavier not in _ids(Db.sets_for_class(&"mage")), "cloth: not %s" % heavier)
	check(&"zz_free_plate" not in _ids(Db.sets_for_class(&"rogue")), "leather: no plate set")
	check(Db.sets_for_class(&"zz_no_such_class").is_empty(), "an unknown class has none")
	for id in Db.class_ids:
		for s in Db.sets_for_class(id):
			check(s.class_id == &"" or s.class_id == id, "%s: never another class's set (%s)" % [id, s.id])


func test_without_free_sets_every_class_has_exactly_its_own_set() -> void:
	fixtures.remove_free_sets()
	for id in Db.class_ids:
		var own := Db.set_for_class(id)
		if Rules.pending(id, "set"):
			check(own == null and Db.sets_for_class(id).is_empty(), "%s: its set is still to come, nothing to collect" % id)
			continue
		check(own != null, "%s has a class set" % id)
		check_eq(Db.sets_for_class(id), [own] as Array[SetData], "%s: the list is just that set" % id)


func test_a_class_without_a_set_still_collects_free_sets() -> void:
	fixtures.add_free_set(&"zz_free_cloth", ClassData.ArmorType.CLOTH)
	var nobody := ClassData.new()
	nobody.id = &"zz_set_less"
	nobody.armor_type = ClassData.ArmorType.CLOTH
	check_eq(_ids(Db.sets_for_class(nobody.id, nobody)), [&"zz_free_cloth"] as Array[StringName], "by its armour type")
	check(Db.set_usable_by(Db.get_set(&"zz_free_cloth"), nobody), "set_usable_by")
	nobody.armor_type = ClassData.ArmorType.CLOTH
	check(not Db.set_usable_by(Db.get_set(Db.set_for_class(&"warrior").id), nobody), "another class's set: never")


# --- The set roll -----------------------------------------------------------------------------

func test_set_candidates_are_the_class_sets_then_the_free_sets_the_team_can_collect() -> void:
	_all_armour_sets()
	var ids: Array[StringName] = [&"warrior", &"mage"]
	check_eq(_ids(ItemGenerator.set_candidates(_team(ids))), _team_pool(ids),
			"class sets in team order, then the free sets any of them collects")
	check_eq(_ids(ItemGenerator.set_candidates(_team([&"mage"]))), _pool_of(&"mage"), "a lone mage")
	check(&"zz_free_plate" not in _ids(ItemGenerator.set_candidates(_team([&"mage"]))), "a cloth wearer cannot collect the plate set")
	fixtures.remove_free_sets()
	check_eq(_ids(ItemGenerator.set_candidates(_team(ids))), [Db.set_for_class(&"warrior").id, Db.set_for_class(&"mage").id] as Array[StringName],
			"no free sets: one set per class")


func test_set_roll_draws_chance_then_set_then_piece() -> void:
	_all_armour_sets()
	var team := _team([&"mage", &"warrior"])
	var candidates := ItemGenerator.set_candidates(team)
	check_eq(candidates.size(), _team_pool([&"mage", &"warrior"]).size(), "two class sets + the free ones")
	check(candidates.size() > 2, "more than one set to draw from")
	var hit_seed := _seed_where(func(r: RandomNumberGenerator) -> bool: return r.randf() < 0.15)
	var rng := RandomNumberGenerator.new()
	var probe := RandomNumberGenerator.new()
	var seen_free := false
	var seen_class := false
	for offset in 60:
		var seed_value := hit_seed + offset * 7919
		rng.seed = seed_value
		probe.seed = seed_value
		if probe.randf() >= 0.15:
			continue
		var got := ItemGenerator._roll_set_piece(LOOT, 12, -1, null, team, rng)
		var set_data := candidates[probe.randi_range(0, candidates.size() - 1)]
		# Pieces the team can wear, in piece order (all five exist at wave 12).
		var pool: Array[StringName] = []
		for piece_id in set_data.piece_ids:
			var data := Db.get_unique(piece_id)
			for cls in team:
				if (set_data.class_id == &"" or set_data.class_id == cls.id) and ItemGenerator.unique_usable_by(data, cls):
					pool.append(piece_id)
					break
		var want := pool[probe.randi_range(0, pool.size() - 1)] if pool.size() > 1 else pool[0]
		check(got != null and got.id == want, "seed %d: set %s, piece %s (got %s)" % [seed_value, set_data.id, want, got.id if got != null else "-"])
		check_eq(rng.state, probe.state, "seed %d: exactly the documented draws" % seed_value)
		if set_data.class_id == &"":
			seen_free = true
			check_eq(got.class_restriction, &"", "a free piece has no class")
		else:
			seen_class = true
	check(seen_free and seen_class, "both kinds came up in the sample")


func test_with_one_eligible_set_there_is_no_set_draw() -> void:
	fixtures.remove_free_sets()
	var rng := RandomNumberGenerator.new()
	var probe := RandomNumberGenerator.new()
	var hit_seed := _seed_where(func(r: RandomNumberGenerator) -> bool: return r.randf() < 0.15)
	rng.seed = hit_seed
	probe.seed = hit_seed
	probe.randf()
	var got := ItemGenerator._roll_set_piece(LOOT, 12, -1, null, _team([&"mage"]), rng)
	var index := probe.randi_range(0, 4)
	check(got != null and got.id == Db.set_for_class(&"mage").piece_ids[index], "chance + piece")
	check_eq(rng.state, probe.state, "no set draw for one set (the old class draw for one class)")


func test_free_pieces_are_usable_by_the_team_and_respect_the_hero() -> void:
	_all_armour_sets()
	var team := _team([&"warrior", &"mage"])
	var by_set := {}
	for it in _set_rolls(LOOT, 12, 6000, {&"team_classes": team}):
		by_set[it.set_id] = by_set.get(it.set_id, 0) + 1
		var data := Db.get_unique(it.source_id)
		check(data != null and data.set_id == it.set_id, "%s: from the set's data" % it.display_name)
		check(it.unique and it.rarity == Items.Rarity.EPIC, "%s: a hand-made Epic" % it.display_name)
		check(it.can_be_used_by(team[0]) or it.can_be_used_by(team[1]), "%s: some team class wears it" % it.display_name)
		if it.set_id in [&"zz_free_cloth", &"zz_free_leather", &"zz_free_mail", &"zz_free_plate"]:
			check_eq(it.class_restriction, &"", "%s: no class restriction" % it.display_name)
	for id in _team_pool([&"warrior", &"mage"]):
		check(by_set.get(id, 0) > 0, "%s drops" % id)
	for id in by_set:
		check(id in _team_pool([&"warrior", &"mage"]), "%s is a set of the team's pool" % id)
	# usable_by / class bias: only what that hero can wear.
	var mage := Db.get_class_data(&"mage")
	for it in _set_rolls(SHOP, 12, 3000, {&"usable_by": mage, &"team_classes": team}):
		check(it.can_be_used_by(mage), "usable_by mage: %s" % it.display_name)
		check(it.set_id in _pool_of(&"mage"), "only the mage's own set or a free set it collects: %s" % it.set_id)
	var rogue_team := _set_rolls(LOOT, 12, 3000, {&"team_classes": _team([&"rogue"])})
	for it in rogue_team:
		check(it.set_id in _pool_of(&"rogue"), "a leather team: only its own pool (%s)" % it.set_id)
		check(it.set_id not in [&"zz_free_mail", &"zz_free_plate"], "a leather team: no mail / plate set")
	# A forced slot still picks that slot only.
	for it in _set_rolls(LOOT, 12, 1500, {&"slot_type": Items.SlotType.HANDS, &"team_classes": team}):
		check_eq(it.slot_type, Items.SlotType.HANDS, "forced Hands: a Hands piece")


func test_a_set_with_mixed_armour_only_rolls_the_pieces_the_team_can_wear() -> void:
	# (Designed sets have one armour type; the piece filter still guards the roll.) The chest is plate, the rest cloth.
	fixtures.add_free_set(&"zz_free_mixed", ClassData.ArmorType.CLOTH)
	Db.get_unique(&"zz_free_mixed_chest").armor_type = ClassData.ArmorType.PLATE
	var seen := {}
	for it in _set_rolls(LOOT, 12, 6000, {&"team_classes": _team([&"mage"])}):
		if it.set_id == &"zz_free_mixed":
			seen[it.source_id] = true
			check(it.can_be_used_by(Db.get_class_data(&"mage")), "%s: the mage can wear it" % it.source_id)
	check_eq(seen.size(), 4, "four of the five pieces roll for a cloth team")
	check(not seen.has(&"zz_free_mixed_chest"), "never the plate chest")


func test_waves_before_the_free_pieces_exist_roll_the_class_sets() -> void:
	fixtures.add_free_set(&"zz_free_late", ClassData.ArmorType.CLOTH, 20)
	for it in _set_rolls(LOOT, 12, 3000, {&"team_classes": _team([&"mage"])}):
		check(it.set_id != &"zz_free_late", "wave 12: the wave-20 pieces do not exist yet")
	var late := 0
	for it in _set_rolls(LOOT, 22, 3000, {&"team_classes": _team([&"mage"])}):
		if it.set_id == &"zz_free_late":
			late += 1
	check(late > 0, "wave 22: they do")


## The first seed whose fresh RandomNumberGenerator satisfies [param ok].
func _seed_where(ok: Callable) -> int:
	for s in range(1, 10000):
		var r := RandomNumberGenerator.new()
		r.seed = s
		if ok.call(r):
			return s
	return -1


# --- The Black Market -------------------------------------------------------------------------

func _heroes(ids: Array[StringName]) -> Array[PlayerSlot]:
	world = Fakes.make_world(tree)
	var out: Array[PlayerSlot] = []
	for i in ids.size():
		out.append(Fakes.spawn_player(world, i, ids[i]).slot)
	return out


func test_black_market_candidates_include_the_free_sets_a_hero_can_collect() -> void:
	_all_armour_sets()
	var slots := _heroes([&"warrior", &"mage"])
	var cands := BlackMarket.set_piece_candidates(18, slots)
	var by_set := {}
	for c in cands:
		var data: UniqueItemData = c["data"]
		by_set[data.set_id] = by_set.get(data.set_id, 0) + 1
		check(ItemGenerator.unique_usable_by(data, c["class"]), "%s: usable by the hero it is listed for" % data.id)
	check_eq(by_set.get(Db.set_for_class(&"warrior").id, 0), 5, "the warrior's class set")
	check_eq(by_set.get(Db.set_for_class(&"mage").id, 0), 5, "the mage's class set")
	var pool := _team_pool([&"warrior", &"mage"])
	for id in FREE_ARMOR:
		check_eq(by_set.get(id, 0), 5 if id in pool else 0, "%s: five pieces, listed once, when a hero collects it" % id)
	# Order: slot order, then the hero's own set before the free ones, then piece order.
	check_eq(cands[0]["data"].set_id, Db.set_for_class(&"warrior").id, "the first hero's own set first")
	check_eq(cands[5]["data"].set_id, _free_for(&"warrior")[0], "then its free sets by id")
	var mage_only := BlackMarket.set_piece_candidates(18, [slots[1]] as Array[PlayerSlot])
	var ids: Array[StringName] = []
	for c in mage_only:
		if c["data"].set_id not in ids:
			ids.append(c["data"].set_id)
	check_eq(ids, _pool_of(&"mage"), "a lone mage: its own pool")


func test_black_market_marks_a_free_piece_missing_unless_every_wearer_has_it() -> void:
	fixtures.add_free_set(&"zz_free_cloth", ClassData.ArmorType.CLOTH)
	var slots := _heroes([&"warlock", &"mage"])  # two cloth classes: both collect the cloth set under any rule
	var first := slots[0].player as Player
	var mage := slots[1].player as Player
	var head := ItemGenerator.from_unique(Db.get_unique(&"zz_free_cloth_head"), 18, false, RandomNumberGenerator.new())
	first.equipment.add_to_backpack(head)
	var missing := {}
	for c in BlackMarket.set_piece_candidates(18, slots):
		if c["data"].set_id == &"zz_free_cloth":
			missing[c["data"].id] = c["missing"]
	check_eq(missing[&"zz_free_cloth_head"], true, "the second hero lacks it: still missing")
	check_eq(missing[&"zz_free_cloth_hands"], true, "nobody has it")
	mage.equipment.add_to_backpack(ItemGenerator.from_unique(Db.get_unique(&"zz_free_cloth_head"), 18, false, RandomNumberGenerator.new()))
	missing.clear()
	for c in BlackMarket.set_piece_candidates(18, slots):
		if c["data"].set_id == &"zz_free_cloth":
			missing[c["data"].id] = c["missing"]
	check_eq(missing[&"zz_free_cloth_head"], false, "both heroes own it: not missing")
	check_eq(missing[&"zz_free_cloth_hands"], true, "the others still are")


func test_black_market_rolls_a_free_piece_when_it_is_the_missing_one() -> void:
	fixtures.add_free_set(&"zz_free_cloth", ClassData.ArmorType.CLOTH)
	var slots := _heroes([&"mage"])
	var mage := slots[0].player as Player
	# The mage owns every piece of its class set: the guaranteed offer is a free piece.
	for piece_id in Db.set_for_class(&"mage").piece_ids:
		mage.equipment.add_to_backpack(ItemGenerator.from_unique(Db.get_unique(piece_id), 18, false, RandomNumberGenerator.new()))
	var got := 0
	for seed_value in 80:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var item := BlackMarket.roll(18, slots, rng)
		check(item != null, "an offer")
		if item != null and item.set_id == &"zz_free_cloth":
			got += 1
			check_eq(item.class_restriction, &"", "a class-free piece")
			check(item.can_be_used_by(mage.class_data), "the mage can wear it")
			check(not item.looted, "not looted: exactly the shop's piece")
	check(got > 20, "the free set is what the set offers are made of (%d / 80)" % got)


# --- Counting, bonuses, tooltips, looks --------------------------------------------------------

func _wear(p: Player, piece_ids: Array[StringName]) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for id in piece_ids:
		var it := ItemGenerator.from_unique(Db.get_unique(id), 12, false, RandomNumberGenerator.new())
		p.equipment.add_to_backpack(it)
		check(p.equipment.equip(it), "%s equips on %s" % [id, p.class_data.id])
		out.append(it)
	return out


func test_two_classes_share_one_free_set_and_count_pieces_per_set_id() -> void:
	fixtures.add_free_set(&"zz_free_cloth", ClassData.ArmorType.CLOTH)
	world = Fakes.make_world(tree)
	var warrior := Fakes.spawn_player(world, 0, &"warrior")
	var mage := Fakes.spawn_player(world, 1, &"mage")
	for p in [warrior, mage]:
		_wear(p, [&"zz_free_cloth_head", &"zz_free_cloth_chest"])
		check_eq(p.equipment.set_counts(), {&"zz_free_cloth": 2} as Dictionary[StringName, int], "%s: two pieces counted" % p.class_data.id)
		check_eq(SetBonuses.active_count(p.equipment), 1, "%s: the 2-piece bonus" % p.class_data.id)
		check_eq(p.stats.get_source(&"set_bonus").get(Stats.STAMINA, 0.0), 10.0, "%s: +10 Stamina from the set" % p.class_data.id)
		check_near(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, 0.0001, "%s: no 4-piece yet" % p.class_data.id)
	_wear(mage, [&"zz_free_cloth_shoulders", &"zz_free_cloth_hands"])
	check_eq(SetBonuses.active_count(mage.equipment), 2, "four pieces: both bonuses")
	check_near(mage.bonuses.damage_mult(null, &"physical", &"weapon"), 1.05, 0.0001, "the 4-piece damage bonus")
	check_eq(SetBonuses.active_count(warrior.equipment), 1, "the warrior's count is its own")


func test_bots_value_a_free_piece_that_completes_a_set_bonus() -> void:
	fixtures.add_free_set(&"zz_free_cloth", ClassData.ArmorType.CLOTH)
	var mage := Db.get_class_data(&"mage")
	var eq := Equipment.new(mage)
	var rng := RandomNumberGenerator.new()
	var head := ItemGenerator.from_unique(Db.get_unique(&"zz_free_cloth_head"), 12, false, rng)
	var chest := ItemGenerator.from_unique(Db.get_unique(&"zz_free_cloth_chest"), 12, false, rng)
	eq.slots[Items.EquipSlot.HEAD] = head
	check_eq(SetBonuses.bonus_change(chest, [] as Array[ItemInstance], eq), 1, "the second piece of the set completes the 2-piece bonus")
	check_eq(SetBonuses.bonus_change(head, [] as Array[ItemInstance], eq), 0, "a duplicate of the worn piece adds nothing")
	check_eq(ItemTooltip.upgrade_direction(chest, null, mage, eq), 1, "an empty slot: upgrade")
	var plain := ItemInstance.new()
	plain.slot_type = Items.SlotType.CHEST
	plain.armor_type = ClassData.ArmorType.CLOTH
	plain.rarity = Items.Rarity.EPIC
	plain.stats = {Stats.STAMINA: 6.0, Stats.CRIT: 3.0, Stats.HASTE: 3.0}  # the same stats as the set piece
	eq.slots[Items.EquipSlot.CHEST] = plain
	check_eq(ItemTooltip.upgrade_direction(chest, plain, mage, eq), 1, "the set piece beats a plain chest of the same stats (the bonus tips it)")


func test_the_tooltip_shows_the_set_block_of_a_free_piece() -> void:
	fixtures.add_free_set(&"zz_free_cloth", ClassData.ArmorType.CLOTH)
	var mage := Db.get_class_data(&"mage")
	var head := ItemGenerator.from_unique(Db.get_unique(&"zz_free_cloth_head"), 12, false, RandomNumberGenerator.new())
	tip = ItemTooltip.create()
	tree.root.add_child(tip)
	tip.viewer_equipment = null
	tip.show_item(head, mage)
	check(tip.find_line("Test Set zz_free_cloth (5 pieces)", true) != null, "the loot-roll block: name and size: %s" % [tip.line_texts()])
	check(tip.find_line("(2) Set: +10 Stamina.", true) != null, "the 2-piece row")
	check(tip.find_line("(4) Set: Weapon hits deal 5% more damage.", true) != null, "the 4-piece row")
	check(tip.find_line("Classes:") == null, "a class-free piece has no Classes line")
	var eq := Equipment.new(mage)
	eq.slots[Items.EquipSlot.HEAD] = head
	eq.slots[Items.EquipSlot.CHEST] = ItemGenerator.from_unique(Db.get_unique(&"zz_free_cloth_chest"), 12, false, RandomNumberGenerator.new())
	tip.viewer_equipment = eq
	tip.show_item(head, mage)
	check(tip.compact_set(), "with a viewer: the compact block")
	check(tip.find_line("Test Set zz_free_cloth (2/5)", true) != null, "worn count")
	var two := tip.find_line("(2) Set: +10 Stamina.", true)
	check(two != null and two.get_theme_color(&"font_color").is_equal_approx(ItemTooltip.ENCHANT_GREEN), "the reached bonus is green")


func test_a_set_without_a_look_wears_the_generic_set_colours() -> void:
	fixtures.add_free_set(&"zz_free_cloth", ClassData.ArmorType.CLOTH)
	check(not OnionArmor.SET_STYLES.has(&"zz_free_cloth"), "no style of its own")
	var head := ItemGenerator.from_unique(Db.get_unique(&"zz_free_cloth_head"), 12, false, RandomNumberGenerator.new())
	var look := EquipLook.from_item(head)
	check(look != null and look.is_set(), "the piece is a set look")
	var pal := OnionArmor.palette(look)
	check_eq(pal.main, OnionArmor.GENERIC_SET["main"], "the generic main colour")
	check_eq(pal.trim, OnionArmor.GENERIC_SET["trim"], "the generic trim")
	var part := OnionArmor.part(EquipLook.Slot.HEAD, look, Db.get_class_data(&"mage"))
	check(part != null and part.solid != null, "and it draws")


# --- Rules for the shipped class-free sets (vacuous until some ship) ----------------------------

func test_every_set_names_a_class_or_none_and_owns_its_pieces() -> void:
	var class_sets := 0
	for id in Db.sets:
		var s := Db.sets[id]
		check(s.class_id == &"" or s.class_id in Db.class_ids, "%s: a class of the game, or class-independent" % id)
		if s.class_id != &"":
			class_sets += 1
		check_eq(s.piece_ids.size(), Rules.PIECES_PER_SET, "%s: five pieces" % id)
		var thresholds: Array[int] = []
		for b in s.bonuses:
			thresholds.append(int(b["pieces"]))
		check_eq(thresholds, [2, 4] as Array[int], "%s: 2- and 4-piece bonuses, no 5-piece" % id)
		for piece_id in s.piece_ids:
			var u := Db.get_unique(piece_id)
			check(u != null and u.set_id == s.id, "%s: %s carries the set id" % [id, piece_id])
			if u != null:
				check_eq(u.class_restriction, s.class_id, "%s: %s is restricted like its set" % [id, piece_id])
				check_eq(u.rarity, Items.Rarity.EPIC, "%s: %s is Epic" % [id, piece_id])
	check_eq(class_sets, Rules.classes_with("set").size(), "one class set per class")
	# Every set piece in the data is listed by its set (no stray set_id).
	var pieces := 0
	for id in Db.uniques:
		var u := Db.uniques[id]
		if u.set_id == &"":
			continue
		pieces += 1
		var s := Db.get_set(u.set_id)
		check(s != null and id in s.piece_ids, "%s is listed by %s" % [id, u.set_id])
	check_eq(pieces, Db.sets.size() * Rules.PIECES_PER_SET, "five pieces per set")


func test_shipped_class_free_sets_follow_the_design() -> void:
	for s in Rules.free_sets():
		var armor := -2
		for piece_id in s.piece_ids:
			var u := Db.get_unique(piece_id)
			check_eq(u.class_restriction, &"", "%s: usable by anyone who wears the armour" % piece_id)
			check(u.stats.get(Stats.STAMINA, 0.0) > 0.0, "%s: Stamina" % piece_id)
			for primary in [Stats.STRENGTH, Stats.AGILITY, Stats.INTELLECT]:
				check(not u.stats.has(primary), "%s: no primary stat (%s)" % [piece_id, primary])
			if armor == -2:
				armor = u.armor_type
			check_eq(u.armor_type, armor, "%s: one armour type per set" % piece_id)
		for b in s.bonuses:
			for e: Dictionary in b["effects"]:
				check_eq(BonusVocabulary.validate(e), "", "%s %d-piece: %s" % [s.id, b["pieces"], e])
