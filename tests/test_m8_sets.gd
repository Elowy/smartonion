extends TestCase
## M8 – class-independent tier sets (SetData.class_id empty, SetData.armor_type): Db.sets_for_class, the
## generator's set roll (native armour only, SET_INDEPENDENT_SHARE of the hits, draw order), the Black
## Market's tiers, set counting across classes, the tooltip and the generic armour look. The sets here are
## fixtures built by set_fixtures.gd (a mail set, a plate set ...): every test starts in the world of
## class sets only (the shipped class-independent sets are taken out) and puts everything back after it.
## The shipped sets and the rules they follow: test_m8_items_shared.gd and the last tests of this file.

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
	fixtures.remove_free_sets()
	ItemGenerator.independent_share_override = -1.0
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
	ItemGenerator.independent_share_override = -1.0
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
	check(s.is_independent() and s.armor_type == ClassData.ArmorType.MAIL, "is_independent, with its armour type")
	check(not Db.set_for_class(Db.class_ids[0]).is_independent(), "a class set is not")
	check_eq(Db.set_for_class(Db.class_ids[0]).armor_type, -1, "a class set has no armor_type of its own")
	check_eq(_ids(Db.independent_sets()), [&"zz_free_mail"] as Array[StringName], "Db.independent_sets")
	check(Db.set_for_class(&"") == null, "set_for_class(\"\") is nobody's own set")
	check(Db.get_set(&"zz_free_mail") == s, "Db.get_set finds it")
	for id in Rules.classes_with("set"):
		var own := Db.set_for_class(id)
		check(own != null and own != s and own.class_id == id, "%s: its own set is its class's, not the free one" % id)


func test_sets_for_class_lists_the_own_set_then_the_free_sets_of_its_armour() -> void:
	_all_armour_sets()
	for id in [&"warrior", &"mage", &"rogue", &"warlock", &"paladin"]:
		check_eq(_ids(Db.sets_for_class(id)), _pool_of(id), "%s: its own set, then the free sets it collects, by id" % id)
	# Whatever the rule, a class collects the free sets of its own armour and never a heavier one.
	check(&"zz_free_plate" in _ids(Db.sets_for_class(&"warrior")), "plate: the plate set")
	check(&"zz_free_cloth" in _ids(Db.sets_for_class(&"mage")), "cloth: the cloth set")
	for heavier in [&"zz_free_leather", &"zz_free_mail", &"zz_free_plate"]:
		check(heavier not in _ids(Db.sets_for_class(&"mage")), "cloth: not %s" % heavier)
	check(&"zz_free_plate" not in _ids(Db.sets_for_class(&"rogue")), "leather: no plate set")
	# Native armour only: a plate hero could wear the cloth set but never rolls or collects it.
	for lighter in [&"zz_free_cloth", &"zz_free_leather", &"zz_free_mail"]:
		check(lighter not in _ids(Db.sets_for_class(&"warrior")), "plate: not %s (wearable, not collected)" % lighter)
		check(not Db.set_usable_by(Db.get_set(lighter), Db.get_class_data(&"warrior")), "set_usable_by: not %s" % lighter)
	check(Db.set_usable_by(Db.get_set(&"zz_free_plate"), Db.get_class_data(&"paladin")), "paladin: the plate set")
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

func test_independent_sets_for_follow_the_native_armour() -> void:
	_all_armour_sets()
	var ids: Array[StringName] = [&"warrior", &"mage"]
	check_eq(_ids(Db.independent_sets()), [&"zz_free_cloth", &"zz_free_leather", &"zz_free_mail", &"zz_free_plate"] as Array[StringName],
			"Db.independent_sets: by id")
	check_eq(_ids(Db.independent_sets_for_armor(ClassData.ArmorType.MAIL)), [&"zz_free_mail"] as Array[StringName], "by armour")
	check_eq(_ids(ItemGenerator.independent_sets_for(null, _team(ids))), [&"zz_free_cloth", &"zz_free_plate"] as Array[StringName],
			"a plate + cloth team: those two sets, by id")
	check_eq(_ids(ItemGenerator.independent_sets_for(null, _team([&"mage"]))), [&"zz_free_cloth"] as Array[StringName], "a lone mage")
	check_eq(_ids(ItemGenerator.independent_sets_for(Db.get_class_data(&"rogue"), _team(ids))), [&"zz_free_leather"] as Array[StringName],
			"the hero alone wins over the team")
	var every: Array[StringName] = []
	for id in FREE_ARMOR:
		for class_id in Db.class_ids:
			if Rules.free_set_fits(FREE_ARMOR[id], int(Db.get_class_data(class_id).armor_type)) and id not in every:
				every.append(id)
	check_eq(_ids(ItemGenerator.independent_sets_for(null, [])), every, "nobody given: the sets of every class's armour, by id")
	check_eq(_ids(ItemGenerator.independent_sets_for(null, _team([&"warrior", &"paladin"]))), [&"zz_free_plate"] as Array[StringName],
			"two plate classes: one set")
	# The class sets are the old rule: one per class with a set, in team order.
	var class_ids: Array[StringName] = []
	for cls in ItemGenerator.set_classes(null, _team(ids)):
		class_ids.append(cls.id)
	check_eq(class_ids, ids, "set_classes: the team classes that have a class set")
	fixtures.remove_free_sets()
	check(ItemGenerator.independent_sets_for(null, _team(ids)).is_empty(), "no independent sets: none")


## Rolls the documented draws of a set hit on [param probe] (already past the chance draw) and returns
## the piece id the roll must give: [param sets] is the list the set (or class) is drawn from.
func _expected_piece(probe: RandomNumberGenerator, sets: Array[SetData], users: Array[ClassData]) -> StringName:
	var set_data := sets[0] if sets.size() == 1 else sets[probe.randi_range(0, sets.size() - 1)]
	var pool: Array[StringName] = []
	for piece_id in set_data.piece_ids:
		for cls in users:
			if (set_data.class_id == &"" or set_data.class_id == cls.id) and ItemGenerator.unique_usable_by(Db.get_unique(piece_id), cls):
				pool.append(piece_id)
				break
	return pool[probe.randi_range(0, pool.size() - 1)] if pool.size() > 1 else pool[0]


func test_set_roll_draws_follow_the_two_bands() -> void:
	_all_armour_sets()
	var team := _team([&"mage", &"warrior"])
	var class_sets: Array[SetData] = [Db.set_for_class(&"mage"), Db.set_for_class(&"warrior")]
	var independent: Array[SetData] = [Db.get_set(&"zz_free_cloth"), Db.get_set(&"zz_free_plate")]
	var chance := ItemGenerator.set_chance(LOOT)
	var band := chance * ItemGenerator.SET_INDEPENDENT_SHARE
	check_near(chance, 0.15, 0.0001, "loot chance 15%")
	check_near(band, 0.045, 0.0001, "the independent band: the first 30% of it")
	var rng := RandomNumberGenerator.new()
	var probe := RandomNumberGenerator.new()
	var seen := {&"independent": 0, &"class": 0}
	for seed_value in range(1, 400):
		rng.seed = seed_value
		probe.seed = seed_value
		var r := probe.randf()
		if r >= chance:
			continue
		var got := ItemGenerator._roll_set_piece(LOOT, 12, -1, null, team, rng)
		var want: StringName
		if r < band:
			# Independent band: the set (2 candidates), then the piece (5).
			want = _expected_piece(probe, independent, team)
			seen[&"independent"] += 1
			check(got != null and got.class_restriction == &"", "seed %d: an independent piece" % seed_value)
		else:
			# Class band: the class (2), then its piece; the same draws as before M8.
			want = _expected_piece(probe, class_sets, team)
			seen[&"class"] += 1
			check(got != null and got.class_restriction != &"", "seed %d: a class piece" % seed_value)
		check(got != null and got.id == want, "seed %d (r %.3f): piece %s (got %s)" % [seed_value, r, want, got.id if got != null else "-"])
		check_eq(rng.state, probe.state, "seed %d: exactly the documented draws" % seed_value)
	check(seen[&"independent"] > 5 and seen[&"class"] > 20, "both bands came up: %s" % [seen])


func test_a_miss_draws_exactly_once_whatever_sets_exist() -> void:
	_all_armour_sets()
	var miss_seed := _seed_where(func(r: RandomNumberGenerator) -> bool: return r.randf() >= 0.15)
	var rng := RandomNumberGenerator.new()
	rng.seed = miss_seed
	check(ItemGenerator._roll_set_piece(LOOT, 12, -1, null, _team([&"warrior", &"mage"]), rng) == null, "miss")
	var probe := RandomNumberGenerator.new()
	probe.seed = miss_seed
	probe.randf()
	check_eq(rng.state, probe.state, "one randf")
	# A forced non-set slot draws nothing at all.
	rng.seed = miss_seed
	var state := rng.state
	check(ItemGenerator._roll_set_piece(LOOT, 12, Items.SlotType.RING, null, _team([&"mage"]), rng) == null, "ring")
	check_eq(rng.state, state, "no draw for a non-set slot")


func test_one_independent_set_and_one_piece_draw_no_set_and_no_piece_draw() -> void:
	# A class without a class set of its own and a single mail set: the roll is that set at any r.
	var set_data := fixtures.add_free_set(&"zz_free_mail", ClassData.ArmorType.MAIL)
	var nobody := ClassData.new()
	nobody.id = &"zz_set_less"
	nobody.armor_type = ClassData.ArmorType.MAIL
	var hit_seed := _seed_where(func(r: RandomNumberGenerator) -> bool: return r.randf() < 0.15)
	var rng := RandomNumberGenerator.new()
	var probe := RandomNumberGenerator.new()
	rng.seed = hit_seed
	probe.seed = hit_seed
	probe.randf()
	var got := ItemGenerator._roll_set_piece(LOOT, 12, -1, null, [nobody], rng)
	check(got != null and got.set_id == &"zz_free_mail", "a team with no class set rolls the independent set at any r")
	check_eq(got.id, set_data.piece_ids[probe.randi_range(0, 4)], "chance + piece, no set draw")
	check_eq(rng.state, probe.state, "exactly those draws")
	# A forced slot leaves one piece: chance only.
	rng.seed = hit_seed
	probe.seed = hit_seed
	probe.randf()
	got = ItemGenerator._roll_set_piece(LOOT, 12, Items.SlotType.LEGS, null, [nobody], rng)
	check(got != null and got.id == &"zz_free_mail_legs", "the Legs piece")
	check_eq(rng.state, probe.state, "one candidate piece: no piece draw")


func test_the_independent_share_is_thirty_percent_of_the_hits() -> void:
	_all_armour_sets()
	var team := _team([&"mage", &"warrior"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260
	var independent := 0
	var hits := 0
	for i in 40000:
		var got := ItemGenerator._roll_set_piece(LOOT, 12, -1, null, team, rng)
		if got == null:
			continue
		hits += 1
		if got.class_restriction == &"":
			independent += 1
	check(hits > 5000, "hits: %d" % hits)
	check_near(float(independent) / hits, ItemGenerator.SET_INDEPENDENT_SHARE, 0.03, "30%% independent (%d / %d)" % [independent, hits])
	# The overall set rate is the chance, share or no share.
	check_near(float(hits) / 40000.0, 0.15, 0.01, "15% of the rolls are a set piece")
	# The test hook: 0 = class sets only, 1 = independent sets only.
	for share in [0.0, 1.0]:
		ItemGenerator.independent_share_override = share
		rng.seed = 77
		var free := 0
		var total := 0
		for i in 4000:
			var got := ItemGenerator._roll_set_piece(LOOT, 12, -1, null, team, rng)
			if got != null:
				total += 1
				free += 1 if got.class_restriction == &"" else 0
		check(total > 300, "share %.0f: hits %d" % [share, total])
		check_eq(free, 0 if share == 0.0 else total, "share %.0f: %s" % [share, "class sets only" if share == 0.0 else "independent only"])
	ItemGenerator.independent_share_override = -1.0


func test_without_a_matching_independent_set_the_roll_is_the_old_class_roll() -> void:
	# Only a mail set exists; a plate / cloth team has no independent set: every hit is a class set,
	# drawn exactly as in M7 (chance, class, piece).
	fixtures.add_free_set(&"zz_free_mail", ClassData.ArmorType.MAIL)
	var team := _team([&"mage", &"warrior"])
	var class_sets: Array[SetData] = [Db.set_for_class(&"mage"), Db.set_for_class(&"warrior")]
	var rng := RandomNumberGenerator.new()
	var probe := RandomNumberGenerator.new()
	var hits := 0
	for seed_value in range(1, 200):
		rng.seed = seed_value
		probe.seed = seed_value
		if probe.randf() >= 0.15:
			continue
		hits += 1
		var got := ItemGenerator._roll_set_piece(LOOT, 12, -1, null, team, rng)
		check(got != null and got.id == _expected_piece(probe, class_sets, team), "seed %d: class, then piece" % seed_value)
		check_eq(rng.state, probe.state, "seed %d: three draws" % seed_value)
	check(hits > 10, "hits: %d" % hits)


func test_with_one_eligible_set_there_is_no_set_draw() -> void:
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


func test_black_market_lists_class_pieces_and_independent_pieces_apart() -> void:
	_all_armour_sets()
	var slots := _heroes([&"warrior", &"mage"])
	var cands := BlackMarket.set_piece_candidates(18, slots)
	var by_set := {}
	for c in cands:
		var data: UniqueItemData = c["data"]
		by_set[data.set_id] = by_set.get(data.set_id, 0) + 1
		check(ItemGenerator.unique_usable_by(data, c["class"]), "%s: usable by the hero it is listed for" % data.id)
	check_eq(by_set.keys().size(), 2, "set_piece_candidates: the two class sets only")
	check_eq(by_set.get(Db.set_for_class(&"warrior").id, 0), 5, "the warrior's class set")
	check_eq(by_set.get(Db.set_for_class(&"mage").id, 0), 5, "the mage's class set")
	# The independent pieces: per hero in slot order, the sets of its own armour (native only).
	var free := BlackMarket.independent_piece_candidates(18, slots)
	var free_sets := {}
	for c in free:
		var data: UniqueItemData = c["data"]
		free_sets[data.set_id] = free_sets.get(data.set_id, 0) + 1
		check_eq(data.class_restriction, &"", "%s: a class-free piece" % data.id)
	check_eq(free.size(), 10, "two native sets x five pieces")
	for id in FREE_ARMOR:
		var native := id in _team_pool([&"warrior", &"mage"])
		check_eq(free_sets.get(id, 0), 5 if native else 0, "%s: five pieces, listed once, when a hero collects it" % id)
	check_eq(free[0]["data"].set_id, &"zz_free_plate", "the first hero's set first (warrior = plate)")
	check_eq(free[5]["data"].set_id, &"zz_free_cloth", "then the mage's")
	var mage_only := BlackMarket.independent_piece_candidates(18, [slots[1]] as Array[PlayerSlot])
	check_eq(mage_only.size(), 5, "a lone mage: the cloth set")
	check_eq(mage_only[0]["data"].set_id, &"zz_free_cloth", "its own armour")
	check(BlackMarket.independent_piece_candidates(3, slots).is_empty(), "before wave 6: nothing")


func test_the_set_piece_pool_tiers_class_missing_then_independent_missing_then_all() -> void:
	_all_armour_sets()
	var slots := _heroes([&"mage"])
	var mage := slots[0].player as Player
	var rng := RandomNumberGenerator.new()
	var class_ids := Db.set_for_class(&"mage").piece_ids
	# 1. A class piece is missing: only class pieces, only the missing ones.
	mage.equipment.add_to_backpack(ItemGenerator.from_unique(Db.get_unique(class_ids[0]), 18, false, rng))
	var pool := BlackMarket.set_piece_pool(18, slots)
	check_eq(pool.size(), 4, "tier 1: the four class pieces the mage lacks")
	for c in pool:
		check(c["data"].set_id == Db.set_for_class(&"mage").id and c["missing"], "%s: a missing class piece" % c["data"].id)
	# 2. The class set complete: the missing independent pieces.
	for piece_id in class_ids:
		if mage.equipment.backpack.filter(func(it: ItemInstance) -> bool: return it.source_id == piece_id).is_empty():
			mage.equipment.add_to_backpack(ItemGenerator.from_unique(Db.get_unique(piece_id), 18, false, rng))
	pool = BlackMarket.set_piece_pool(18, slots)
	check_eq(pool.size(), 5, "tier 2: the five cloth pieces")
	for c in pool:
		check(c["data"].set_id == &"zz_free_cloth" and c["missing"], "%s: a missing independent piece" % c["data"].id)
	# 3. Everything owned: all candidates of both.
	for piece_id in Db.get_set(&"zz_free_cloth").piece_ids:
		mage.equipment.add_to_backpack(ItemGenerator.from_unique(Db.get_unique(piece_id), 18, false, rng))
	pool = BlackMarket.set_piece_pool(18, slots)
	check_eq(pool.size(), 10, "tier 3: 5 class + 5 independent pieces")
	for c in pool:
		check(not c["missing"], "nothing is missing")
	# The offer draws one randi_range over the pool (and none for a single entry).
	var hit := _seed_where(func(r: RandomNumberGenerator) -> bool: return r.randf() >= BlackMarket.MAX_ROLL_CHANCE)
	rng.seed = hit
	var probe := RandomNumberGenerator.new()
	probe.seed = hit
	probe.randf()
	var item := BlackMarket.roll(18, slots, rng)
	check(item != null and item.source_id == pool[probe.randi_range(0, pool.size() - 1)]["data"].id, "the offer is the pool's pick")
	check_eq(rng.state, probe.state, "from_unique draws nothing for a hand-made piece: chance + pick")


func test_dungeon_rewards_use_the_same_pool() -> void:
	_all_armour_sets()
	var slots := _heroes([&"mage"])
	var mage := slots[0].player as Player
	var rng := RandomNumberGenerator.new()
	# The class set complete, the independent set missing: the extra piece is a cloth piece.
	for piece_id in Db.set_for_class(&"mage").piece_ids:
		mage.equipment.add_to_backpack(ItemGenerator.from_unique(Db.get_unique(piece_id), 18, false, rng))
	var hit := _seed_where(func(r: RandomNumberGenerator) -> bool: return r.randf() < DungeonRewards.SET_PIECE_CHANCE)
	rng.seed = hit
	var piece := DungeonRewards.bonus_set_piece(18, slots, rng)
	check(piece != null and piece.set_id == &"zz_free_cloth", "an independent piece once the class set is complete")
	check(piece != null and piece.looted, "a dungeon piece is looted")
	# A second hero whose class set is incomplete: a class piece comes first.
	var both: Array[PlayerSlot] = [slots[0], Fakes.spawn_player(world, 1, &"warrior").slot]
	rng.seed = hit
	piece = DungeonRewards.bonus_set_piece(18, both, rng)
	check(piece != null and piece.set_id == Db.set_for_class(&"warrior").id, "class pieces first")


func test_black_market_marks_a_free_piece_missing_unless_every_wearer_has_it() -> void:
	fixtures.add_free_set(&"zz_free_cloth", ClassData.ArmorType.CLOTH)
	var slots := _heroes([&"warlock", &"mage"])  # two cloth classes: both collect the cloth set
	var first := slots[0].player as Player
	var mage := slots[1].player as Player
	var head := ItemGenerator.from_unique(Db.get_unique(&"zz_free_cloth_head"), 18, false, RandomNumberGenerator.new())
	first.equipment.add_to_backpack(head)
	var missing := {}
	for c in BlackMarket.independent_piece_candidates(18, slots):
		if c["data"].set_id == &"zz_free_cloth":
			missing[c["data"].id] = c["missing"]
	check_eq(missing[&"zz_free_cloth_head"], true, "the second hero lacks it: still missing")
	check_eq(missing[&"zz_free_cloth_hands"], true, "nobody has it")
	mage.equipment.add_to_backpack(ItemGenerator.from_unique(Db.get_unique(&"zz_free_cloth_head"), 18, false, RandomNumberGenerator.new()))
	missing.clear()
	for c in BlackMarket.independent_piece_candidates(18, slots):
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
	fixtures.restore()  # the shipped data, class-independent sets included
	var class_sets := 0
	for id in Db.sets:
		var s := Db.sets[id]
		check(s.class_id == &"" or s.class_id in Db.class_ids, "%s: a class of the game, or class-independent" % id)
		if s.class_id != &"":
			class_sets += 1
			check_eq(s.armor_type, -1, "%s: a class set takes its class's armour" % id)
		check_eq(s.is_independent(), s.class_id == &"", "%s: is_independent" % id)
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
	fixtures.restore()  # the shipped data
	for s in Rules.free_sets():
		check(s.armor_type >= 0 and s.armor_type <= ClassData.ArmorType.PLATE, "%s: an armour type 0..3" % s.id)
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
			check_eq(u.armor_type, s.armor_type, "%s: the set's armor_type" % piece_id)
		for b in s.bonuses:
			for e: Dictionary in b["effects"]:
				check_eq(BonusVocabulary.validate(e), "", "%s %d-piece: %s" % [s.id, b["pieces"], e])
