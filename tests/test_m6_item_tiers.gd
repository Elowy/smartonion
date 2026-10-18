extends TestCase
## M6b CONTENT-W: armour base material tiers (GDD 5.4 / 5.8) – ItemBase.min_wave and the generator's
## tier pick (the highest tier available at the wave 70%, a lower one 30%, deterministic on the
## given rng), shown with the example tier-II / tier-III plate chest bases (plate_cuirass,
## plate_carapace) that the CONTENT-DATA package copies for the other 31 slot x type pairs.

const Content := preload("res://tests/test_items_gen_content.gd")

var rng: RandomNumberGenerator
var _saved_bases: Dictionary[StringName, ItemBase] = {}


func before_each() -> void:
	RunState.start_run(1, 5)
	rng = RandomNumberGenerator.new()
	rng.seed = 8080
	_saved_bases = Db.item_bases.duplicate()


func after_each() -> void:
	Db.item_bases.clear()
	Db.item_bases.merge(_saved_bases)


## A synthetic armour base (not in the data): [param id] of [param slot] x [param armor_type].
func _add_base(id: StringName, slot: Items.SlotType, armor_type: int, min_wave: int,
		weight: float = 1.0) -> ItemBase:
	var b := ItemBase.new()
	b.id = id
	b.display_name = String(id).capitalize()
	b.slot_type = slot
	b.armor_type = armor_type
	b.min_wave = min_wave
	b.weight = weight
	Db.item_bases[id] = b
	return b


## How often pick_base returns each base id over [param n] picks.
func _tally(slot: int, usable: ClassData, favour: ClassData, wave: int, n: int) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for i in n:
		var b := ItemGenerator.pick_base(slot, usable, favour, wave, rng)
		if b != null:
			out[b.id] = out.get(b.id, 0) + 1
	return out


# --- Data -----------------------------------------------------------------------------------

func test_min_wave_defaults_to_one_and_the_examples_are_tiers_two_and_three() -> void:
	check_eq(ItemBase.new().min_wave, 1, "default: from the first wave")
	check_eq(Db.item_bases[&"plate_breastplate"].min_wave, 1, "tier I")
	var cuirass := Db.item_bases.get(&"plate_cuirass") as ItemBase
	var carapace := Db.item_bases.get(&"plate_carapace") as ItemBase
	check(cuirass != null and carapace != null, "both example tier bases are loaded")
	for pair: Array in [[cuirass, 9], [carapace, 17]]:
		var b: ItemBase = pair[0]
		check_eq(b.min_wave, pair[1], "%s: min_wave" % b.id)
		check_eq(b.slot_type, Items.SlotType.CHEST, "%s: chest" % b.id)
		check_eq(b.armor_type, ClassData.ArmorType.PLATE, "%s: plate" % b.id)
		check_eq(b.weight, 1.0, "%s: weight" % b.id)
		check(b.display_name != "" and b.display_name != Db.item_bases[&"plate_breastplate"].display_name,
				"%s: its own name" % b.id)
		check_eq(b.look, &"plate_breastplate", "%s: the tier I model piece" % b.id)
		for bad in Content.BANNED:
			check(not b.display_name.containsn(bad), "%s: no trademark (%s)" % [b.id, bad])
	var names: Array[String] = []
	for id in Db.item_bases:
		names.append((Db.item_bases[id] as ItemBase).display_name)
	check_eq(names.count("Cuirass"), 1, "Cuirass is unique")
	check_eq(names.count("Plate Carapace"), 1, "Plate Carapace is unique")


func test_only_tier_waves_are_used_and_the_tiers_match_the_material_tiers() -> void:
	for id in Db.item_bases:
		var b: ItemBase = Db.item_bases[id]
		check(b.min_wave in [1, 9, 17], "%s: min_wave %d" % [id, b.min_wave])
		check_eq(Items.material_tier(b.min_wave), [1, 9, 17].find(b.min_wave), "%s: the material tier of its wave" % id)


# --- The tier pick --------------------------------------------------------------------------

func test_bases_above_the_wave_are_never_offered() -> void:
	for wave in [1, 4, 8]:
		var seen := _tally(Items.SlotType.CHEST, null, null, wave, 300)
		check(not seen.has(&"plate_cuirass") and not seen.has(&"plate_carapace"), "wave %d: tier I only (%s)" % [wave, seen])
		check(seen.has(&"plate_breastplate"), "wave %d: the tier I plate chest" % wave)
	var nine := _tally(Items.SlotType.CHEST, null, null, 9, 600)
	check(nine.has(&"plate_cuirass") and not nine.has(&"plate_carapace"), "wave 9: tiers I and II (%s)" % nine)
	var sixteen := _tally(Items.SlotType.CHEST, null, null, 16, 600)
	check(not sixteen.has(&"plate_carapace"), "wave 16: still no tier III")
	var seventeen := _tally(Items.SlotType.CHEST, null, null, 17, 900)
	check(seventeen.has(&"plate_carapace") and seventeen.has(&"plate_cuirass") and seventeen.has(&"plate_breastplate"),
			"wave 17: all three tiers (%s)" % seventeen)


func test_the_highest_available_tier_is_taken_70_percent_of_the_time() -> void:
	var n := 6000
	var paladin := Db.get_class_data(&"paladin")
	# Only plate chests: tiers I + II at wave 9, I + II + III at wave 17.
	var at9 := _tally(Items.SlotType.CHEST, null, paladin, 12, n)
	var plate9: int = at9.get(&"plate_breastplate", 0) + at9.get(&"plate_cuirass", 0)
	check(plate9 > 0, "plate chests were rolled")
	check_near(float(at9.get(&"plate_cuirass", 0)) / float(plate9), 0.7, 0.04,
			"wave 12: the tier II chest 70%% of the plate chests (%s)" % at9)
	var at17 := _tally(Items.SlotType.CHEST, null, paladin, 20, n)
	var plate17: int = at17.get(&"plate_breastplate", 0) + at17.get(&"plate_cuirass", 0) + at17.get(&"plate_carapace", 0)
	check_near(float(at17.get(&"plate_carapace", 0)) / float(plate17), 0.7, 0.04, "wave 20: tier III 70%%")
	check_near(float(at17.get(&"plate_cuirass", 0)) / float(plate17), 0.15, 0.04, "tier II 15%% (a lower one, uniform)")
	check_near(float(at17.get(&"plate_breastplate", 0)) / float(plate17), 0.15, 0.04, "tier I 15%%")


func test_armour_type_weights_do_not_change_with_tiers() -> void:
	var n := 8000
	var seen := {}
	for i in n:
		var b := ItemGenerator.pick_base(Items.SlotType.CHEST, null, null, 20, rng)
		seen[b.armor_type] = seen.get(b.armor_type, 0) + 1
	for armor_type in Items.ARMOR_TYPE_NAMES:
		check_near(float(seen.get(armor_type, 0)) / n, 0.25, 0.03,
				"%s: a quarter of the chests, tiers or not (%s)" % [Items.ARMOR_TYPE_NAMES[armor_type], seen])
	# A class favours its own armour type exactly as before (OWN_ARMOR_WEIGHT).
	var warrior := Db.get_class_data(&"warrior")
	var plate := 0
	for i in n:
		if ItemGenerator.pick_base(Items.SlotType.CHEST, null, warrior, 20, rng).armor_type == ClassData.ArmorType.PLATE:
			plate += 1
	var expected := ItemGenerator.OWN_ARMOR_WEIGHT / (ItemGenerator.OWN_ARMOR_WEIGHT + 3.0)
	check_near(float(plate) / n, expected, 0.03, "the favoured class gets plate %s%% of the time" % (expected * 100.0))


func test_usable_by_still_limits_the_armour_type() -> void:
	var mage := Db.get_class_data(&"mage")
	var rogue := Db.get_class_data(&"rogue")
	for wave in [1, 9, 20]:
		for i in 80:
			var b := ItemGenerator.pick_base(Items.SlotType.CHEST, mage, null, wave, rng)
			check_eq(b.armor_type, ClassData.ArmorType.CLOTH, "a mage only gets cloth (wave %d)" % wave)
			var r := ItemGenerator.pick_base(Items.SlotType.CHEST, rogue, null, wave, rng)
			check(r.armor_type <= ClassData.ArmorType.LEATHER, "a rogue never gets mail or plate (wave %d)" % wave)


func test_pick_base_is_deterministic_on_the_rng() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 123
	b.seed = 123
	for i in 200:
		var wave := 1 + i % 25
		var slot: int = [Items.SlotType.CHEST, Items.SlotType.HEAD, Items.SlotType.NECK, Items.SlotType.FEET][i % 4]
		check_eq(ItemGenerator.pick_base(slot, null, null, wave, a).id, ItemGenerator.pick_base(slot, null, null, wave, b).id,
				"same seed, same base (pick %d)" % i)
	check_eq(a.state, b.state, "and the same number of draws")


func test_a_single_tier_costs_exactly_one_draw_like_before() -> void:
	# Jewellery at any wave and every armour slot below wave 9 (tier I only): one draw per pick,
	# so the items rolled before M6b are unchanged.
	var cases: Array = [[Items.SlotType.NECK, 25], [Items.SlotType.RING, 25], [Items.SlotType.HEAD, 5],
			[Items.SlotType.CHEST, 5], [Items.SlotType.LEGS, 8], [Items.SlotType.FEET, 1]]
	for c: Array in cases:
		var used := RandomNumberGenerator.new()
		var reference := RandomNumberGenerator.new()
		used.seed = 31
		reference.seed = 31
		for i in 50:
			ItemGenerator.pick_base(c[0], null, null, c[1], used)
			reference.randf()
		check_eq(used.state, reference.state, "slot %d at wave %d: one draw per pick" % [c[0], c[1]])


func test_tiers_with_three_levels_use_the_lower_pick_draw_and_ties_break_by_id() -> void:
	# A synthetic slot: head, cloth, three tiers whose ids sort against the tier order, and a tie.
	for id in Db.item_bases.keys():
		if (Db.item_bases[id] as ItemBase).slot_type == Items.SlotType.HEAD:
			Db.item_bases.erase(id)
	_add_base(&"z_head_one", Items.SlotType.HEAD, ClassData.ArmorType.CLOTH, 1)
	_add_base(&"a_head_two", Items.SlotType.HEAD, ClassData.ArmorType.CLOTH, 9)
	_add_base(&"m_head_three", Items.SlotType.HEAD, ClassData.ArmorType.CLOTH, 17)
	var seen := _tally(Items.SlotType.HEAD, null, null, 25, 6000)
	check_near(float(seen[&"m_head_three"]) / 6000.0, 0.7, 0.03, "the top tier is by min_wave, not by id (%s)" % seen)
	check_near(float(seen[&"a_head_two"]) / 6000.0, 0.15, 0.03, "tier II")
	check_near(float(seen[&"z_head_one"]) / 6000.0, 0.15, 0.03, "tier I")
	# Same min_wave twice: the later id counts as the higher one (a stable rule).
	_add_base(&"n_head_three_b", Items.SlotType.HEAD, ClassData.ArmorType.CLOTH, 17)
	var tie := _tally(Items.SlotType.HEAD, null, null, 25, 4000)
	check(tie.get(&"n_head_three_b", 0) > 2400 and tie.has(&"m_head_three"),
			"the top is the last by (min_wave, id), the other one is a lower tier: %s" % tie)
	# Weight 0 bases are never rolled, whatever their tier.
	Db.item_bases[&"n_head_three_b"].weight = 0.0
	Db.item_bases[&"m_head_three"].weight = 0.0
	var no_top := _tally(Items.SlotType.HEAD, null, null, 25, 600)
	check(not no_top.has(&"m_head_three") and not no_top.has(&"n_head_three_b"), "weight 0: never")
	check(no_top.get(&"a_head_two", 0) > 400, "tier II is the top then (%s)" % no_top)


func test_no_base_for_the_slot_returns_null() -> void:
	for id in Db.item_bases.keys():
		if (Db.item_bases[id] as ItemBase).slot_type == Items.SlotType.WAIST:
			Db.item_bases.erase(id)
	check(ItemGenerator.pick_base(Items.SlotType.WAIST, null, null, 5, rng) == null, "nothing to pick")
	# Every base above the wave: also nothing.
	_add_base(&"late_belt", Items.SlotType.WAIST, ClassData.ArmorType.MAIL, 17)
	check(ItemGenerator.pick_base(Items.SlotType.WAIST, null, null, 16, rng) == null, "a tier III belt at wave 16: none")
	check(ItemGenerator.pick_base(Items.SlotType.WAIST, null, null, 17, rng).id == &"late_belt", "at wave 17: it")


# --- Generated items ------------------------------------------------------------------------

func test_generated_chests_use_the_tier_bases_and_keep_their_names() -> void:
	var seen: Dictionary[StringName, int] = {}
	for i in 500:
		var wave := 1 + i % 25
		var item := ItemGenerator.generate(ItemGenerator.Source.SHOP, wave, rng,
				{&"slot_type": Items.SlotType.CHEST, &"rarity": Items.Rarity.COMMON})
		if item.unique:
			continue
		var base := Db.item_bases[item.source_id]
		check(base.min_wave <= wave, "%s at wave %d: base available" % [base.id, wave])
		seen[item.source_id] = seen.get(item.source_id, 0) + 1
		var material: String = Items.MATERIAL_NAMES[base.armor_type][Items.material_tier(wave)]
		check(item.display_name.begins_with(material + " " + base.display_name), "[Material] [Base]: %s" % item.display_name)
		check_eq(item.armor_type, base.armor_type, "the armour type of the base")
	check(seen.get(&"plate_cuirass", 0) > 0 and seen.get(&"plate_carapace", 0) > 0, "the tier bases were rolled (%s)" % seen)
	# The budget follows the wave's material tier (4 x chest 1.0 x tier II 1.1), not the base's tier.
	check_near(ItemGenerator.stat_budget(Items.Rarity.COMMON, Items.SlotType.CHEST, 9, false), 4.4, 0.0001,
			"budget stays wave-driven")
