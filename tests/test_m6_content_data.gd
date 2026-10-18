extends TestCase
## M6b CONTENT-DATA: the new item data (GDD 5.4 / 5.8) loads and has valid fields, and it works.
## 62 armour tier II / III bases (min_wave 9 / 17), 12 jewellery bases (10 neck, 10 ring) and 7
## stat suffixes. Every new base is rolled at its wave, every new suffix puts its stats on an item.

const Content := preload("res://tests/test_items_gen_content.gd")

## Armour tier bases of the M6b content: the tier II (min_wave 9) and III (min_wave 17) piece of each
## slot x armour type that the data package adds (the plate chest pair is in test_m6_item_tiers).
const NEW_ARMOUR_BASES: Array[StringName] = [
	&"cloth_hood", &"cloth_veil", &"leather_headguard", &"leather_mask",
	&"mail_bascinet", &"mail_great_helm", &"plate_sallet", &"plate_warhelm",
	&"cloth_pelerine", &"cloth_cape", &"leather_epaulets", &"leather_spikeguard",
	&"mail_shoulderguards", &"mail_mantlet", &"plate_shoulderplates", &"plate_warplates",
	&"cloth_vestments", &"cloth_raiment", &"leather_jerkin", &"leather_brigandine",
	&"mail_haubergeon", &"mail_byrnie",
	&"cloth_wristwraps", &"cloth_bindings", &"leather_armlets", &"leather_wristguards",
	&"mail_manchettes", &"mail_brassards", &"plate_armguards", &"plate_wristplates",
	&"cloth_mitts", &"cloth_handwraps", &"leather_grips", &"leather_handguards",
	&"mail_fingerguards", &"mail_knuckleguards", &"plate_warfists", &"plate_clawgauntlets",
	&"cloth_cord", &"cloth_cincture", &"leather_waistband", &"leather_cinch",
	&"mail_clasp", &"mail_waistguard", &"plate_tassets", &"plate_waistplate",
	&"cloth_trousers", &"cloth_breeches", &"leather_chaps", &"leather_legwraps",
	&"mail_chausses", &"mail_cuisses", &"plate_greaves", &"plate_kneecops",
	&"cloth_sandals", &"cloth_treads", &"leather_moccasins", &"leather_stalkers",
	&"mail_sollerets", &"mail_footguards", &"plate_warboots", &"plate_stompers",
]
const NEW_JEWELLERY_BASES: Array[StringName] = [
	&"neck_torque", &"neck_locket", &"neck_collar", &"neck_medallion", &"neck_talisman",
	&"neck_lavalier", &"ring_seal", &"ring_hoop", &"ring_crest", &"ring_bezel",
	&"ring_keeper", &"ring_thumb_ring",
]
const NEW_SUFFIXES: Array[StringName] = [
	&"ox", &"lynx", &"raven", &"thorns", &"mending", &"hunter", &"magpie",
]
## Material words of Items.MATERIAL_NAMES and ItemGenerator.JEWEL_MATERIALS: the generated name
## adds one of them, so a base name must not carry one.
const MATERIAL_WORDS: Array[String] = [
	"Linen", "Silk", "Moonweave", "Rugged", "Thick", "Shadowhide", "Chain", "Scaled",
	"Stormforged", "Iron", "Steel", "Runed", "Copper", "Silver", "Golden",
]
const TIER_WAVES: Array[int] = [1, 9, 17]

var rng: RandomNumberGenerator


func before_each() -> void:
	RunState.start_run(1, 5)
	rng = RandomNumberGenerator.new()
	rng.seed = 5151


## One or two Title Case words without a material word (the generator adds the material).
func _is_piece_name(text: String) -> bool:
	var words := text.split(" ")
	if words.size() < 1 or words.size() > 2:
		return false
	for word in words:
		if word == "" or word[0] != word[0].to_upper() or word in MATERIAL_WORDS:
			return false
	return true


func _count_named(text: String) -> int:
	var n := 0
	for id in Db.item_bases:
		if (Db.item_bases[id] as ItemBase).display_name == text:
			n += 1
	return n


## The tier I base of a slot x armour type (the look of the tier II / III base must match it).
func _tier_one(slot: int, armor_type: int) -> ItemBase:
	for id in Db.item_bases:
		var b := Db.item_bases[id] as ItemBase
		if b.slot_type == slot and b.armor_type == armor_type and b.min_wave == 1:
			return b
	return null


## How often pick_base returns each base id over [param n] picks.
func _tally(slot: int, wave: int, n: int) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for i in n:
		var b := ItemGenerator.pick_base(slot, null, null, wave, rng)
		if b != null:
			out[b.id] = out.get(b.id, 0) + 1
	return out


# --- Data -----------------------------------------------------------------------------------

func test_the_new_lists_hold_the_gdd_counts() -> void:
	check_eq(NEW_ARMOUR_BASES.size(), 62, "62 new armour tier bases (96 - 32 - 2 plate chest)")
	check_eq(NEW_JEWELLERY_BASES.size(), 12, "12 new jewellery bases (20 - 8)")
	check_eq(NEW_SUFFIXES.size(), 7, "7 new suffixes (25 - 18)")


func test_new_armour_bases_load_with_valid_fields() -> void:
	for id in NEW_ARMOUR_BASES:
		var b := Db.item_bases.get(id) as ItemBase
		check(b != null, "%s loads as an ItemBase" % id)
		check(FileAccess.file_exists("res://data/item_bases/%s.tres" % id), "%s: file name is the id" % id)
		if b == null:
			continue
		check_eq(b.id, id, "%s: id" % id)
		check(b.slot_type in Items.ARMOR_SLOTS, "%s: armour slot" % id)
		check(b.armor_type >= ClassData.ArmorType.CLOTH and b.armor_type <= ClassData.ArmorType.PLATE,
				"%s: armour type" % id)
		check(b.min_wave == 9 or b.min_wave == 17, "%s: tier II or III wave (%d)" % [id, b.min_wave])
		check_eq(b.weight, 1.0, "%s: weight" % id)
		check(_is_piece_name(b.display_name), "%s: a piece name, no material word (%s)" % [id, b.display_name])
		check_eq(_count_named(b.display_name), 1, "%s: name %s is unique" % [id, b.display_name])
		var tier_one := _tier_one(b.slot_type, b.armor_type)
		check(tier_one != null, "%s: a tier I base of its slot and type" % id)
		if tier_one != null:
			check_eq(b.look, tier_one.look, "%s: the tier I model piece" % id)
		for bad in Content.BANNED:
			check(not b.display_name.containsn(bad), "%s: no trademark (%s)" % [id, bad])


func test_new_jewellery_bases_load_with_valid_fields() -> void:
	for id in NEW_JEWELLERY_BASES:
		var b := Db.item_bases.get(id) as ItemBase
		check(b != null, "%s loads as an ItemBase" % id)
		check(FileAccess.file_exists("res://data/item_bases/%s.tres" % id), "%s: file name is the id" % id)
		if b == null:
			continue
		check_eq(b.id, id, "%s: id" % id)
		check(b.slot_type == Items.SlotType.NECK or b.slot_type == Items.SlotType.RING,
				"%s: neck or ring" % id)
		check_eq(b.armor_type, Items.NO_ARMOR, "%s: no armour type" % id)
		check_eq(b.min_wave, 1, "%s: jewellery is not tiered" % id)
		check_eq(b.weight, 1.0, "%s: weight" % id)
		check_eq(b.look, &"", "%s: no model piece" % id)
		check(_is_piece_name(b.display_name), "%s: a piece name (%s)" % [id, b.display_name])
		check_eq(_count_named(b.display_name), 1, "%s: name %s is unique" % [id, b.display_name])
		for bad in Content.BANNED:
			check(not b.display_name.containsn(bad), "%s: no trademark (%s)" % [id, bad])


func test_each_slot_and_armour_type_has_exactly_one_base_per_tier() -> void:
	for slot in Items.ARMOR_SLOTS:
		for armor_type in [ClassData.ArmorType.CLOTH, ClassData.ArmorType.LEATHER,
				ClassData.ArmorType.MAIL, ClassData.ArmorType.PLATE]:
			for wave in TIER_WAVES:
				var n := 0
				for id in Db.item_bases:
					var b := Db.item_bases[id] as ItemBase
					if b.slot_type == slot and b.armor_type == armor_type and b.min_wave == wave:
						n += 1
				check_eq(n, 1, "slot %d, armour type %d, tier from wave %d: one base" % [slot, armor_type, wave])


func test_new_suffixes_load_with_valid_fields() -> void:
	for id in NEW_SUFFIXES:
		var a := Db.affixes.get(id) as AffixData
		check(a != null, "%s loads as an AffixData" % id)
		check(FileAccess.file_exists("res://data/affixes/%s.tres" % id), "%s: file name is the id" % id)
		if a == null:
			continue
		check_eq(a.id, id, "%s: id" % id)
		check(a.suffix.begins_with("of ") and a.suffix.length() > 3, "%s: suffix text (%s)" % [id, a.suffix])
		check_eq(_suffix_count(a.suffix), 1, "%s: suffix text is unique" % id)
		check(not a.stats.is_empty() and a.stats.size() == a.shares.size(), "%s: stats and shares" % id)
		for stat in a.stats:
			check(stat in Stats.ALL, "%s: known stat %s" % [id, stat])
		for share in a.shares:
			check(share > 0.0, "%s: positive share" % id)
		check(a.weight > 0.0 and a.weight <= 1.0, "%s: weight %.2f" % [id, a.weight])
		for slot in a.slot_types:
			check(slot >= Items.SlotType.HEAD and slot <= Items.SlotType.WEAPON, "%s: slot %d" % [id, slot])
		var primary := false
		for stat in a.stats:
			if stat in [Stats.STRENGTH, Stats.AGILITY, Stats.INTELLECT, Stats.STAMINA]:
				primary = true
		if primary:
			check(not a.slot_types.is_empty() and Items.SlotType.NECK not in a.slot_types
					and Items.SlotType.RING not in a.slot_types, "%s: primary stat off neck / ring" % id)
		for bad in Content.BANNED:
			check(not a.suffix.containsn(bad), "%s: no trademark (%s)" % [id, bad])


func _suffix_count(text: String) -> int:
	var n := 0
	for id in Db.affixes:
		if (Db.affixes[id] as AffixData).suffix == text:
			n += 1
	return n


# --- Works ----------------------------------------------------------------------------------

func test_new_armour_bases_are_rolled_at_their_wave() -> void:
	for slot in Items.ARMOR_SLOTS:
		var late := _tally(slot, 17, 1200)
		for id in NEW_ARMOUR_BASES:
			var b := Db.item_bases[id] as ItemBase
			if b.slot_type == slot:
				check(late.has(id), "%s is rolled at wave 17 (%s)" % [id, late])
		var early := _tally(slot, 8, 300)
		for id in early:
			check(Db.item_bases[id].min_wave == 1, "wave 8: only tier I, got %s" % id)


func test_new_jewellery_bases_are_rolled() -> void:
	for slot in [Items.SlotType.NECK, Items.SlotType.RING]:
		var seen := _tally(slot, 1, 600)
		for id in NEW_JEWELLERY_BASES:
			var b := Db.item_bases[id] as ItemBase
			if b.slot_type == slot:
				check(seen.has(id), "%s is rolled (%s)" % [id, seen])


func test_new_suffixes_are_rolled_on_their_slots() -> void:
	for id in NEW_SUFFIXES:
		var a := Db.affixes[id] as AffixData
		var slot: int = a.slot_types[0] if not a.slot_types.is_empty() else Items.SlotType.HEAD
		var seen := 0
		for i in 2000:
			var picked := ItemGenerator._pick_affix(slot, null, null, rng)
			if picked != null and picked.id == id:
				seen += 1
		check(seen > 0, "%s rolls on slot %d (%d of 2000)" % [id, slot, seen])


func test_new_suffixes_put_their_stats_on_an_item() -> void:
	for id in NEW_SUFFIXES:
		var a := Db.affixes[id] as AffixData
		var item := ItemInstance.new()
		item.rarity = Items.Rarity.RARE
		item.slot_type = a.slot_types[0] if not a.slot_types.is_empty() else Items.SlotType.HEAD
		ItemGenerator._roll_stats(item, 30.0, a, 0, rng)
		for stat in a.stats:
			check(item.stats.get(stat, 0.0) >= 1.0, "%s: %s on the item" % [id, stat])
		# No implicit armor (armor 0) and a Rare item: nothing but the suffix's own stats.
		check_eq(item.stats.size(), a.stats.size(), "%s: only its own stats" % id)
