extends TestCase
## Item content (data/item_bases, data/affixes, data/uniques): counts from GDD 5.4 / 5.5 / 5.8,
## unique effects in the shared proc vocabulary, no Blizzard trademarks. Tier-set pieces
## (set_id, M5) have no unique effect – their set bonus is the effect (test_sets.gd).

## Shared unique-effect vocabulary (ProcSystem building blocks and triggers).
const BLOCKS: Array[StringName] = [
	&"bolt", &"chain", &"dot", &"nova", &"explode", &"extra_attack", &"buff", &"heal", &"drain",
	&"slow", &"stun", &"gold", &"shield", &"reflect", &"smite_heal", &"cheat_death",
]
const TRIGGERS: Array[String] = ["on_hit", "on_kill", "when_struck", "low_hp", "periodic", "equip"]
const SCHOOLS: Array[String] = ["physical", "fire", "frost", "arcane", "holy", "shadow", "nature"]
const GDD_SUFFIXES: Array[StringName] = [
	&"bear", &"monkey", &"eagle", &"tiger", &"owl", &"wolf", &"boar", &"falcon",
	&"striking", &"swiftness", &"sentinel", &"fortune",
]
const BANNED: Array[String] = [
	"azeroth", "murloc", "horde", "alliance", "thunderfury", "frozen throne", "silver hand",
	"ashbringer", "frostmourne", "warcraft", "lich king", "sylvanas", "windrunner", "arthas",
	"illidan", "thrall", "stormwind", "orgrimmar", "time is money",
	# Real tier-set names / WoW terms the M5 sets were renamed from (architecture §5 Q22).
	"felheart", "shadowcraft", "lightforged",
]


## Material tiers of the armour bases (ItemBase.min_wave): I from wave 1 (the original 32), II from
## wave 9, III from wave 17 (Items.material_tier's thresholds).
const BASE_TIER_WAVES: Array[int] = [1, 9, 17]


func test_armor_and_jewellery_bases() -> void:
	var per_tier := {}
	var armour := 0
	var neck := 0
	var ring := 0
	for id in Db.item_bases:
		var base := Db.item_bases[id]
		check_eq(base.id, id, "id matches")
		check(base.display_name != "", "%s has a name" % id)
		check(base.min_wave in BASE_TIER_WAVES, "%s: min_wave %d is a tier wave" % [id, base.min_wave])
		if base.slot_type in Items.ARMOR_SLOTS:
			armour += 1
			check(base.armor_type in Items.ARMOR_TYPE_NAMES, "%s has an armor type" % id)
			# One base per slot, armor type and material tier (min_wave).
			var tier_key := "%d:%d:%d" % [base.slot_type, base.armor_type, base.min_wave]
			check(not per_tier.has(tier_key), "one base per slot, armor type and tier (%s)" % id)
			per_tier[tier_key] = true
		else:
			check_eq(base.min_wave, 1, "%s: jewellery bases are not tiered" % id)
			check_eq(base.armor_type, Items.NO_ARMOR, "%s: jewellery has no armor type" % id)
			if base.slot_type == Items.SlotType.NECK:
				neck += 1
			elif base.slot_type == Items.SlotType.RING:
				ring += 1
			else:
				check(false, "%s: only armor, neck and ring bases (trinkets are hand-made)" % id)
	# 8 armor slots x 4 armor types x 3 material tiers (I, II, III) = 96, one base each.
	check_eq(armour, 96, "armor bases: 8 slots x 4 armor types x 3 tiers")
	for slot in Items.ARMOR_SLOTS:
		for armor_type in [ClassData.ArmorType.CLOTH, ClassData.ArmorType.LEATHER,
				ClassData.ArmorType.MAIL, ClassData.ArmorType.PLATE]:
			for wave in BASE_TIER_WAVES:
				check(per_tier.has("%d:%d:%d" % [slot, armor_type, wave]),
						"slot %d, armor type %d: a tier at wave %d" % [slot, armor_type, wave])
	check_eq(neck, 10, "neck bases (GDD 5.8)")
	check_eq(ring, 10, "ring bases (GDD 5.8)")
	check_eq(Db.item_bases.size(), 116, "item bases: 96 armour + 20 jewellery")


func test_suffixes() -> void:
	for id in GDD_SUFFIXES:
		check(Db.affixes.has(id), "GDD suffix %s" % id)
	check(Db.affixes.size() >= 12, "at least 12 suffixes")
	for id in Db.affixes:
		var affix := Db.affixes[id]
		check(affix.suffix.begins_with("of "), "%s: suffix text" % id)
		check(not affix.stats.is_empty() and affix.stats.size() == affix.shares.size(), "%s: stats and shares" % id)
		for stat in affix.stats:
			check(stat in Stats.ALL, "%s: known stat %s" % [id, stat])
		var primary := false
		for stat in affix.stats:
			if stat in [Stats.STRENGTH, Stats.AGILITY, Stats.INTELLECT, Stats.STAMINA]:
				primary = true
		if primary:
			check(not affix.slot_types.is_empty() and Items.SlotType.NECK not in affix.slot_types
					and Items.SlotType.RING not in affix.slot_types,
					"%s: no primary stats on neck / ring (GDD 5.4)" % id)


func test_unique_counts() -> void:
	var trinkets := 0
	var legendaries := 0
	var named := 0
	var per_class := {}
	for id in Db.uniques:
		var data := Db.uniques[id]
		if data.set_id != &"":
			continue  # tier-set pieces (test_sets.gd)
		if data.class_restriction != &"":
			per_class[data.class_restriction] = per_class.get(data.class_restriction, 0) + 1
		elif data.rarity == Items.Rarity.LEGENDARY:
			legendaries += 1
		elif ItemGenerator.unique_slot(data) == Items.SlotType.TRINKET:
			trinkets += 1
		else:
			named += 1
	check_eq(trinkets, 10, "trinkets")
	check_eq(legendaries, 8, "Legendaries")
	check(named >= 10, "named Rare / Epic items (%d)" % named)
	for class_id in Db.class_ids:
		check(per_class.get(class_id, 0) >= 2, "class items for %s" % class_id)


func test_unique_data_is_valid() -> void:
	for id in Db.uniques:
		var data := Db.uniques[id]
		check_eq(data.id, id, "id matches")
		var set_piece := data.set_id != &""
		check(data.display_name != "" and (data.unique_text != "" or set_piece), "%s: name and text" % id)
		check(data.rarity >= Items.Rarity.UNCOMMON and data.rarity <= Items.Rarity.LEGENDARY, "%s: rarity" % id)
		if data.weapon != null:
			check_eq(data.slot_type, Items.SlotType.WEAPON, "%s: weapon slot" % id)
			check_eq(data.armor_type, Items.NO_ARMOR, "%s: weapons have no armor type" % id)
		else:
			check(data.slot_type != Items.SlotType.WEAPON, "%s: weapon slot needs a weapon" % id)
			check_eq(data.slot_type in Items.ARMOR_SLOTS, data.armor_type != Items.NO_ARMOR,
					"%s: armor type only on armor slots" % id)
		for stat in data.stats:
			check(stat in Stats.ALL, "%s: known stat %s" % [id, stat])
		check(not data.sources.is_empty(), "%s: has sources" % id)
		for s in data.sources:
			check(s in ItemGenerator.SOURCE_IDS, "%s: known source %s" % [id, s])
		if data.rarity == Items.Rarity.LEGENDARY:
			check(&"shop" not in data.sources, "%s: Legendaries only from loot" % id)
			check(data.min_wave >= 10, "%s: Legendaries from wave 10" % id)
		if data.class_restriction != &"":
			var c := Db.get_class_data(data.class_restriction)
			check(c != null, "%s: known class" % id)
			check(data.rarity >= Items.Rarity.RARE, "%s: class items are Rare+" % id)
			check(ItemGenerator.unique_usable_by(data, c), "%s: usable by its class" % id)
		if set_piece:
			check(data.unique_effect == &"" and data.unique_text == "", "%s: set pieces carry no unique effect" % id)
			check(Db.get_set(data.set_id) != null, "%s: known set" % id)
			continue
		_check_effect(id, data.unique_effect, data.unique_params)


func _check_effect(id: StringName, effect: StringName, params: Dictionary) -> void:
	if effect == &"ability_mod":
		check(String(params.get("ability", "")) != "" and params.get("mods") is Dictionary,
				"%s: ability_mod needs an ability and mods" % id)
		return
	check(effect in BLOCKS, "%s: building block %s" % [id, effect])
	var trigger := String(params.get("trigger", ""))
	check(trigger in TRIGGERS, "%s: trigger %s" % [id, trigger])
	match trigger:
		"on_hit":
			check(float(params.get("ppm", 0.0)) > 0.0, "%s: on_hit needs ppm" % id)
		"on_kill", "when_struck":
			check(float(params.get("chance", 0.0)) > 0.0, "%s: needs chance" % id)
		"low_hp":
			check(float(params.get("threshold", 0.0)) > 0.0, "%s: needs threshold" % id)
		"periodic":
			check(float(params.get("interval", 0.0)) > 0.0, "%s: needs interval" % id)
	if params.has("school"):
		check(String(params["school"]) in SCHOOLS, "%s: school" % id)
	var required: Dictionary = {
		&"bolt": ["damage"], &"chain": ["damage", "targets"], &"dot": ["damage", "duration"],
		&"nova": ["damage", "radius"], &"explode": ["damage", "radius"], &"extra_attack": ["count"],
		&"buff": ["stats", "duration"], &"heal": ["amount", "target"], &"drain": ["damage"],
		&"slow": ["pct", "duration"], &"stun": ["duration"], &"gold": ["amount"],
		&"shield": ["amount", "duration"], &"reflect": ["damage"],
		&"smite_heal": ["damage", "heal"], &"cheat_death": ["invulnerable"],
	}
	for key in required.get(effect, []):
		check(params.has(key), "%s: %s needs %s" % [id, effect, key])
	if effect == &"buff":
		for stat in params.get("stats", {}):
			check(StringName(stat) in Stats.ALL, "%s: buff stat %s" % [id, stat])


func test_no_blizzard_trademarks() -> void:
	var texts: Array[String] = []
	for id in Db.uniques:
		var u := Db.uniques[id]
		texts.append_array([u.display_name, u.unique_text, u.flavor])
	for id in Db.item_bases:
		texts.append(Db.item_bases[id].display_name)
	for id in Db.affixes:
		texts.append(Db.affixes[id].suffix)
	for id in Db.sets:
		texts.append(Db.sets[id].display_name)
		for bonus in Db.sets[id].bonuses:
			texts.append(str(bonus.get("text", "")))
	for text in texts:
		for word in BANNED:
			check(word not in text.to_lower(), "'%s' in \"%s\"" % [word, text])
