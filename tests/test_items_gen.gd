extends TestCase
## ItemGenerator: rarity tables, budgets, prices, enchants, names, class options, uniques.
## Runs against a fixed set of test enchants (Db.enchants is swapped out and restored) so the
## results do not depend on the enchant content.

const SHOP := ItemGenerator.Source.SHOP
const LOOT := ItemGenerator.Source.LOOT
const ELITE := ItemGenerator.Source.ELITE
const GOBLIN := ItemGenerator.Source.GOBLIN
const BOSS := ItemGenerator.Source.BOSS

var _saved_enchants: Dictionary[StringName, EnchantData] = {}


func before_each() -> void:
	_saved_enchants = Db.enchants.duplicate()
	Db.enchants.clear()
	_add_enchant(&"t_mighty", EnchantData.Kind.EQUIP, "Mighty", 1, {Stats.ATTACK_POWER: 6.0})
	_add_enchant(&"t_zealous", EnchantData.Kind.EQUIP, "Zealous", 1, {Stats.EXTRA_ATTACK: 3.0})
	_add_enchant(&"t_blazing", EnchantData.Kind.ON_HIT, "Blazing", 2)
	_add_enchant(&"t_warded", EnchantData.Kind.WHEN_STRUCK, "Warded", 2)
	_add_enchant(&"t_greedy", EnchantData.Kind.ON_KILL, "Greedy", 2)
	_add_enchant(&"t_brutal", EnchantData.Kind.EQUIP, "Brutal", 3, {Stats.CRIT_DAMAGE: 15.0})
	var split := _add_enchant(&"t_splitting", EnchantData.Kind.EQUIP, "Splitting", 2,
			{Stats.EXTRA_PROJECTILE: 1.0})
	split.requires_projectile = true


func after_each() -> void:
	Db.enchants.clear()
	Db.enchants.merge(_saved_enchants)


func _add_enchant(id: StringName, kind: EnchantData.Kind, prefix: String, min_rarity: int,
		equip_stats: Dictionary[StringName, float] = {}) -> EnchantData:
	var e := EnchantData.new()
	e.id = id
	e.kind = kind
	e.prefix = prefix
	e.min_rarity = min_rarity
	e.equip_stats = equip_stats
	e.ppm = 3.0 if kind == EnchantData.Kind.ON_HIT else 0.0
	e.chance = 10.0 if kind in [EnchantData.Kind.ON_KILL, EnchantData.Kind.WHEN_STRUCK] else 0.0
	e.description = prefix
	Db.enchants[id] = e
	return e


func _rng(seed_value: int = 1234) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


static func _sig(item: ItemInstance) -> String:
	var parts: Array = [item.source_id, item.display_name, item.rarity, item.slot_type,
		item.armor_type, item.wave, item.looted, item.item_level, item.buy_price, item.stats]
	for roll in item.enchants:
		parts.append("%s:%d" % [roll.enchant.id, roll.rank])
	return str(parts)


# --- Rarity --------------------------------------------------------------------------------

func test_rarity_tables_match_gdd() -> void:
	_check_weights(ItemGenerator.rarity_weights(SHOP, 1), [1.0, 0.0, 0.0, 0.0, 0.0], "shop wave 1")
	_check_weights(ItemGenerator.rarity_weights(SHOP, 5), [0.6, 0.3, 0.1, 0.0, 0.0], "shop wave 5")
	_check_weights(ItemGenerator.rarity_weights(SHOP, 25), [0.1, 0.25, 0.38, 0.27, 0.0], "shop wave 25")
	_check_weights(ItemGenerator.rarity_weights(SHOP, 40), [0.1, 0.25, 0.38, 0.27, 0.0], "past the table")
	# Wave 3 interpolates 80 / 15 / 5, but Rare only from wave 4 in the shop.
	_check_weights(ItemGenerator.rarity_weights(SHOP, 3), [80.0 / 95.0, 15.0 / 95.0, 0.0, 0.0, 0.0], "shop wave 3")
	check_eq(ItemGenerator.rarity_weights(SHOP, 8)[Items.Rarity.EPIC], 0.0, "shop Epic from wave 9")
	check(ItemGenerator.rarity_weights(SHOP, 9)[Items.Rarity.EPIC] > 0.0, "shop Epic at wave 9")
	_check_weights(ItemGenerator.rarity_weights(LOOT, 1), [0.6, 0.4, 0.0, 0.0, 0.0], "loot wave 1")
	_check_weights(ItemGenerator.rarity_weights(LOOT, 12), [0.06, 0.31, 0.42, 0.178, 0.032], "loot wave 12")
	_check_weights(ItemGenerator.rarity_weights(LOOT, 25), [0.0, 0.08, 0.37, 0.43, 0.12], "loot wave 25")
	check_eq(ItemGenerator.rarity_weights(LOOT, 9)[Items.Rarity.LEGENDARY], 0.0, "Legendary from wave 10")
	check_eq(ItemGenerator.rarity_weights(LOOT, 2)[Items.Rarity.RARE], 0.0, "loot Rare from wave 3")
	_check_weights(ItemGenerator.rarity_weights(ELITE, 10), [0.0, 0.0, 40.0 / 55.0, 13.0 / 55.0, 2.0 / 55.0], "elite wave 10")
	_check_weights(ItemGenerator.rarity_weights(ELITE, 1), [0.0, 0.0, 1.0, 0.0, 0.0], "elite: at least Rare")
	_check_weights(ItemGenerator.rarity_weights(GOBLIN, 5), [0.0, 0.0, 0.75, 0.25, 0.0], "goblin: 25% Epic+")
	for wave in [3, 10, 15, 20, 25]:
		var g := ItemGenerator.rarity_weights(GOBLIN, wave)
		check(g[Items.Rarity.EPIC] + g[Items.Rarity.LEGENDARY] >= 0.25 - 0.0001, "goblin Epic+ >= 25%% at %d" % wave)
		check_eq(g[Items.Rarity.COMMON] + g[Items.Rarity.UNCOMMON], 0.0, "goblin Rare+ at %d" % wave)
	_check_weights(ItemGenerator.rarity_weights(BOSS, 10), [0.0, 0.0, 0.0, 0.8, 0.2], "boss wave 10")
	_check_weights(ItemGenerator.rarity_weights(BOSS, 25), [0.0, 0.0, 0.0, 0.8, 0.2], "boss wave 25")


func _check_weights(actual: Array[float], expected: Array, label: String) -> void:
	check_eq(actual.size(), expected.size(), label + " size")
	for r in mini(actual.size(), expected.size()):
		check_near(actual[r], float(expected[r]), 0.0005, "%s %s" % [label, Items.RARITY_NAMES[r]])


func test_fortune_shifts_towards_higher_rarities() -> void:
	for source in [SHOP, LOOT, ELITE, GOBLIN, BOSS]:
		var base := ItemGenerator.rarity_weights(source, 15)
		var lucky := ItemGenerator.rarity_weights(source, 15, 60.0)
		check(_mean_rarity(lucky) > _mean_rarity(base), "fortune raises the mean rarity (%d)" % source)
	check_near(ItemGenerator.rarity_weights(SHOP, 1, 100.0)[Items.Rarity.COMMON], 1.0, 0.0001,
			"fortune does not unlock rarities before their first wave")
	var rng := _rng()
	var plain := 0
	var lucky := 0
	for i in 2000:
		plain += ItemGenerator.roll_rarity(LOOT, 12, 0.0, rng)
		lucky += ItemGenerator.roll_rarity(LOOT, 12, 80.0, rng)
	check(lucky > plain, "lucky rolls are better on average")


static func _mean_rarity(w: Array[float]) -> float:
	var m := 0.0
	for r in w.size():
		m += r * w[r]
	return m


func test_shop_never_sells_above_epic() -> void:
	var rng := _rng()
	for wave in range(1, 41):
		for i in 30:
			check(ItemGenerator.roll_rarity(SHOP, wave, 500.0, rng) <= Items.Rarity.EPIC, "shop roll <= Epic")
	for i in 50:
		var item := ItemGenerator.generate(SHOP, 25, rng, {&"rarity": Items.Rarity.LEGENDARY})
		check(item.rarity <= Items.Rarity.EPIC, "forced Legendary is clamped in the shop")
	for i in 1500:
		var item := ItemGenerator.generate(SHOP, 1 + i % 30, rng, {&"fortune": 200.0})
		check(item.rarity <= Items.Rarity.EPIC, "shop item <= Epic: %s" % item.display_name)


func test_legendary_only_from_loot_sources() -> void:
	var rng := _rng(7)
	var legendaries := 0
	for i in 600:
		var item := ItemGenerator.generate(LOOT, 25, rng, {&"fortune": 100.0})
		if item.rarity == Items.Rarity.LEGENDARY:
			legendaries += 1
			check(item.unique, "Legendary loot is hand-made when one fits: %s" % item.display_name)
			check(item.looted, "looted")
			var data := Db.get_unique(item.source_id)
			check(data != null and &"shop" not in data.sources, "Legendary data never lists the shop")
	check(legendaries > 20, "Legendaries drop late with Fortune (%d)" % legendaries)
	for wave in [1, 5, 9]:
		for source in [LOOT, ELITE, GOBLIN, BOSS]:
			check_eq(ItemGenerator.rarity_weights(source, wave, 100.0)[Items.Rarity.LEGENDARY], 0.0,
					"no Legendary before wave 10 (source %d, wave %d)" % [source, wave])


func test_boss_and_elite_sources() -> void:
	var rng := _rng(3)
	var boss_legendary := 0
	for i in 500:
		var boss := ItemGenerator.generate(BOSS, 10, rng)
		check(boss.rarity >= Items.Rarity.EPIC, "boss Epic+")
		if boss.rarity == Items.Rarity.LEGENDARY:
			boss_legendary += 1
		check(ItemGenerator.generate(ELITE, 2, rng).rarity >= Items.Rarity.RARE, "elite Rare+")
		check(ItemGenerator.generate(GOBLIN, 2, rng).rarity >= Items.Rarity.RARE, "goblin Rare+")
	check(boss_legendary > 60 and boss_legendary < 140, "about 20%% boss Legendaries (%d / 500)" % boss_legendary)


# --- Determinism ---------------------------------------------------------------------------

func test_same_seed_same_items() -> void:
	var a := _rng(42)
	var b := _rng(42)
	var c := _rng(43)
	var differs := false
	var mage := Db.get_class_data(&"mage")
	for i in 300:
		var source: ItemGenerator.Source = [SHOP, LOOT, ELITE, GOBLIN, BOSS][i % 5]
		var options := {&"class_data": mage} if i % 3 == 0 else {}
		var x := ItemGenerator.generate(source, 1 + i % 25, a, options)
		var y := ItemGenerator.generate(source, 1 + i % 25, b, options)
		var z := ItemGenerator.generate(source, 1 + i % 25, c, options)
		check_eq(_sig(x), _sig(y), "same seed, same item")
		if _sig(x) != _sig(z):
			differs = true
	check(differs, "another seed gives other items")


# --- Formulas ------------------------------------------------------------------------------

func test_budget_formula() -> void:
	check_eq(ItemGenerator.stat_budget(Items.Rarity.RARE, Items.SlotType.HEAD, 1, false), 11.0, "Rare head")
	check_near(ItemGenerator.stat_budget(Items.Rarity.EPIC, Items.SlotType.WRIST, 17, true), 16.0 * 0.6 * 1.2 * 1.25, 0.0001, "Epic wrist, tier III, looted")
	check_near(ItemGenerator.stat_budget(Items.Rarity.UNCOMMON, Items.SlotType.FEET, 9, false), 7.0 * 0.8 * 1.1, 0.0001, "tier II")
	check_near(ItemGenerator.stat_budget(Items.Rarity.LEGENDARY, Items.SlotType.RING, 8, true), 22.0 * 0.7 * 1.25, 0.0001, "ring")
	check_near(ItemGenerator.stat_budget(Items.Rarity.COMMON, Items.SlotType.WEAPON, 1, false, Db.get_weapon(&"sword")), 4.0 * 0.6, 0.0001, "one-hander")
	check_near(ItemGenerator.stat_budget(Items.Rarity.COMMON, Items.SlotType.WEAPON, 1, false, Db.get_weapon(&"two_hand_axe")), 4.0, 0.0001, "two-hander")
	check_eq(ItemGenerator.implicit_armor(ClassData.ArmorType.PLATE, Items.SlotType.HEAD, 1), 3, "plate head")
	check_eq(ItemGenerator.implicit_armor(ClassData.ArmorType.PLATE, Items.SlotType.HEAD, 17), 4, "plate head tier III")
	check_eq(ItemGenerator.implicit_armor(ClassData.ArmorType.PLATE, Items.SlotType.WRIST, 1), 2, "plate wrist")
	check_eq(ItemGenerator.implicit_armor(ClassData.ArmorType.LEATHER, Items.SlotType.WRIST, 1), 1, "leather wrist")
	check_eq(ItemGenerator.implicit_armor(ClassData.ArmorType.CLOTH, Items.SlotType.CHEST, 20), 0, "cloth")
	check_eq(ItemGenerator.implicit_armor(Items.NO_ARMOR, Items.SlotType.NECK, 20), 0, "jewellery")
	check_eq(ItemGenerator.stat_cost({Stats.STRENGTH: 2.0, Stats.ARMOR: 3.0, Stats.FORTUNE: 4.0, Stats.DODGE: 2.0}), 2.0 + 6.0 + 2.0 + 3.0, "stat prices")


func test_generated_items_spend_their_budget() -> void:
	var rng := _rng(5)
	var checked := 0
	for i in 600:
		var item := ItemGenerator.generate([SHOP, LOOT][i % 2], 1 + i % 25, rng)
		if item.unique:
			continue
		checked += 1
		var budget := ItemGenerator.stat_budget(item.rarity, item.slot_type, item.wave, item.looted, item.weapon)
		var rolled := item.stats.duplicate()
		var implicit := ItemGenerator.implicit_armor(item.armor_type, item.slot_type, item.wave)
		if implicit > 0:
			check(rolled.get(Stats.ARMOR, 0.0) >= implicit, "implicit armor on %s" % item.display_name)
			rolled[Stats.ARMOR] = rolled[Stats.ARMOR] - implicit
		var tolerance := 0.0
		for stat in rolled:
			tolerance += ItemGenerator.stat_price(stat)
			check(item.stats[stat] >= 1.0, "every rolled stat is at least 1")
		check_near(ItemGenerator.stat_cost(rolled), budget, tolerance, "budget of %s" % item.display_name)
		if item.rarity >= Items.Rarity.EPIC:
			var secondaries := 0
			for stat in ItemGenerator.SECONDARY_STATS:
				if item.stats.has(stat):
					secondaries += 1
			check(secondaries >= 1, "Epic+ has an extra secondary stat")
	check(checked > 400, "mostly generated items")


func test_price_formula() -> void:
	check_eq(ItemGenerator.price_for(Items.Rarity.COMMON, 1), 15)
	check_eq(ItemGenerator.price_for(Items.Rarity.UNCOMMON, 1), 30)
	check_eq(ItemGenerator.price_for(Items.Rarity.RARE, 1), 55)
	check_eq(ItemGenerator.price_for(Items.Rarity.EPIC, 1), 90)
	check_eq(ItemGenerator.price_for(Items.Rarity.LEGENDARY, 1), 140)
	check_eq(ItemGenerator.price_for(Items.Rarity.EPIC, 11), 162, "90 x 1.8")
	check_eq(ItemGenerator.price_for(Items.Rarity.RARE, 10), 95, "55 x 1.72 = 94.6")
	check_eq(ItemGenerator.price_for(Items.Rarity.COMMON, 0), 15, "wave clamps to 1")
	var rng := _rng()
	for i in 200:
		var item := ItemGenerator.generate([SHOP, LOOT, BOSS][i % 3], 1 + i % 25, rng)
		check_eq(item.buy_price, ItemGenerator.price_for(item.rarity, item.wave), "buy price of %s" % item.display_name)
		check_eq(item.item_level, Items.item_level(item.wave, item.rarity, item.looted), "item level")
		check_eq(item.looted, i % 3 != 0, "looted unless bought")


# --- Enchants ------------------------------------------------------------------------------

func test_enchant_rank_by_wave() -> void:
	check_eq(ItemGenerator.enchant_rank(1, false), 0, "I at wave 1")
	check_eq(ItemGenerator.enchant_rank(8, false), 0, "I at wave 8")
	check_eq(ItemGenerator.enchant_rank(9, false), 1, "II at wave 9")
	check_eq(ItemGenerator.enchant_rank(16, false), 1, "II at wave 16")
	check_eq(ItemGenerator.enchant_rank(17, false), 2, "III at wave 17")
	check_eq(ItemGenerator.enchant_rank(1, true), 1, "looted +1")
	check_eq(ItemGenerator.enchant_rank(9, true), 2, "looted +1")
	check_eq(ItemGenerator.enchant_rank(30, true), 2, "max III")
	var rng := _rng()
	for wave in [3, 12, 20]:
		for i in 10:
			var bought := ItemGenerator.generate(SHOP, wave, rng, {&"rarity": Items.Rarity.RARE})
			var looted := ItemGenerator.generate(LOOT, wave, rng, {&"rarity": Items.Rarity.RARE})
			if not bought.unique:
				check_eq(bought.enchants[0].rank, ItemGenerator.enchant_rank(wave, false), "shop rank at %d" % wave)
			if not looted.unique:
				check_eq(looted.enchants[0].rank, ItemGenerator.enchant_rank(wave, true), "loot rank at %d" % wave)


func test_enchant_counts_by_rarity() -> void:
	var rng := _rng(11)
	var uncommon_with := 0
	var epic_counts := {}
	for i in 400:
		var wave := 1 + i % 25
		check(ItemGenerator.generate(SHOP, wave, rng, {&"rarity": Items.Rarity.COMMON}).enchants.is_empty(), "Common: none")
		var unc := ItemGenerator.generate(SHOP, wave, rng, {&"rarity": Items.Rarity.UNCOMMON})
		if unc.unique:
			continue
		check(unc.enchants.size() <= 1, "Uncommon: at most one")
		if not unc.enchants.is_empty():
			uncommon_with += 1
			check_eq(unc.enchants[0].enchant.kind, EnchantData.Kind.EQUIP, "Uncommon: Equip only")
		var looted_unc := ItemGenerator.generate(LOOT, wave, rng, {&"rarity": Items.Rarity.UNCOMMON})
		if not looted_unc.unique:
			check_eq(looted_unc.enchants.size(), 1, "looted Uncommon: always one (GDD 5.7)")
		var rare := ItemGenerator.generate(SHOP, wave, rng, {&"rarity": Items.Rarity.RARE})
		if not rare.unique:
			check_eq(rare.enchants.size(), 1, "Rare: one")
		var epic := ItemGenerator.generate(LOOT, wave, rng, {&"rarity": Items.Rarity.EPIC})
		if not epic.unique:
			check(epic.enchants.size() in [1, 2], "Epic: 1-2")
			epic_counts[epic.enchants.size()] = true
		var legendary := ItemGenerator.generate(LOOT, maxi(wave, 10), rng, {&"rarity": Items.Rarity.LEGENDARY})
		check(legendary.enchants.size() >= 2, "Legendary: 2 (+ unique)")
	check(uncommon_with > 70 and uncommon_with < 170, "about 30%% of shop Uncommons are enchanted (%d)" % uncommon_with)
	check(epic_counts.has(1) and epic_counts.has(2), "Epics roll both 1 and 2 enchants")


func test_enchant_slot_rules() -> void:
	var rng := _rng(13)
	var saw_split := false
	for i in 1500:
		var item := ItemGenerator.generate(LOOT, 1 + i % 25, rng, {&"rarity": [Items.Rarity.RARE, Items.Rarity.EPIC, Items.Rarity.LEGENDARY][i % 3]})
		var ids: Array[StringName] = []
		for roll in item.enchants:
			var e := roll.enchant
			check(e.id not in ids, "no duplicate enchants on %s" % item.display_name)
			ids.append(e.id)
			check(item.rarity >= e.min_rarity, "min rarity")
			match e.kind:
				EnchantData.Kind.ON_HIT:
					check(item.slot_type in [Items.SlotType.WEAPON, Items.SlotType.RING, Items.SlotType.TRINKET],
							"on hit only on weapons, rings, trinkets: %s" % item.display_name)
				EnchantData.Kind.WHEN_STRUCK:
					var shield := item.is_weapon() and item.weapon.weapon_type == &"shield"
					check(shield or item.slot_type in [Items.SlotType.CHEST, Items.SlotType.SHOULDERS, Items.SlotType.HEAD],
							"when struck only on chest / shoulders / head / shield: %s" % item.display_name)
			if e.requires_projectile:
				saw_split = true
				check(item.is_weapon() and item.weapon.attack_kind == WeaponData.AttackKind.PROJECTILE,
						"projectile enchant on a projectile weapon: %s" % item.display_name)
	check(saw_split, "projectile enchants do roll")


func test_empty_enchant_pool_is_fine() -> void:
	Db.enchants.clear()
	var rng := _rng()
	for i in 200:
		var item := ItemGenerator.generate(LOOT, 1 + i % 25, rng, {&"rarity": [Items.Rarity.UNCOMMON, Items.Rarity.RARE, Items.Rarity.EPIC, Items.Rarity.LEGENDARY][i % 4]})
		check(item != null and item.enchants.is_empty(), "no enchants without content")
		check(item.display_name != "" and not item.display_name.begins_with(" "), "still named")


# --- Names ---------------------------------------------------------------------------------

func test_names() -> void:
	var rng := _rng(17)
	for wave in [1, 12, 20]:
		var tier := Items.material_tier(wave)
		for i in 20:
			var head := ItemGenerator.generate(SHOP, wave, rng, {&"slot_type": Items.SlotType.HEAD, &"rarity": Items.Rarity.COMMON})
			if head.unique:
				continue
			var base := Db.item_bases[head.source_id]
			var material: String = Items.MATERIAL_NAMES[base.armor_type][tier]
			check(head.display_name.begins_with(material + " " + base.display_name),
					"[Material] [Base]: %s" % head.display_name)
			check(_ends_with_suffix(head.display_name), "[of the Suffix]: %s" % head.display_name)
			var ring := ItemGenerator.generate(SHOP, wave, rng, {&"slot_type": Items.SlotType.RING, &"rarity": Items.Rarity.COMMON})
			if not ring.unique:
				check(ring.display_name.begins_with(ItemGenerator.JEWEL_MATERIALS[tier] + " "), "jewel material: %s" % ring.display_name)
			var weapon := ItemGenerator.generate(SHOP, wave, rng, {&"slot_type": Items.SlotType.WEAPON, &"rarity": Items.Rarity.COMMON})
			if not weapon.unique:
				check(weapon.display_name.begins_with(Db.get_weapon(weapon.source_id).display_name),
						"[Weapon name]: %s" % weapon.display_name)
	for i in 30:
		var rare := ItemGenerator.generate(LOOT, 5, rng, {&"rarity": Items.Rarity.RARE})
		if rare.unique:
			continue
		check(rare.display_name.begins_with(rare.enchants[0].enchant.prefix + " "), "[Enchant prefix]: %s" % rare.display_name)
	var storm := ItemGenerator.from_unique(Db.get_unique(&"stormcaller"), 12, true, rng)
	check_eq(storm.display_name, "Stormcaller", "uniques keep their name")
	check_eq(storm.enchants.size(), 2, "Legendary: 2 enchants")


func _ends_with_suffix(name: String) -> bool:
	for id in Db.affixes:
		if name.ends_with(" " + Db.affixes[id].suffix):
			return true
	return false


# --- Class options -------------------------------------------------------------------------

func test_usable_by_respects_proficiency() -> void:
	var rng := _rng(19)
	for id in Db.class_ids:
		var c := Db.get_class_data(id)
		for i in 150:
			var source: ItemGenerator.Source = [SHOP, LOOT, BOSS][i % 3]
			var item := ItemGenerator.generate(source, 1 + i % 25, rng, {&"usable_by": c})
			check(item.can_be_used_by(c), "%s can use %s" % [id, item.display_name])
		for i in 30:
			var weapon := ItemGenerator.generate(SHOP, 5, rng, {&"usable_by": c, &"slot_type": Items.SlotType.WEAPON})
			check(weapon.is_weapon() and c.can_use(weapon.weapon), "%s weapon %s" % [id, weapon.display_name])
			var chest := ItemGenerator.generate(LOOT, 5, rng, {&"usable_by": c, &"slot_type": Items.SlotType.CHEST})
			check(chest.armor_type <= c.armor_type, "%s armor %s" % [id, chest.display_name])


func test_class_bias() -> void:
	var rng := _rng(23)
	var mage := Db.get_class_data(&"mage")
	var usable := 0
	var intellect := 0
	var strength := 0
	for i in 600:
		var item := ItemGenerator.generate(SHOP, 1 + i % 25, rng, {&"class_data": mage})
		if item.can_be_used_by(mage):
			usable += 1
		if not item.unique and not item.is_weapon():
			if item.stats.has(Stats.INTELLECT):
				intellect += 1
			if item.stats.has(Stats.STRENGTH):
				strength += 1
	check(usable >= 360, "at least ~60%% usable by the class (%d / 600)" % usable)
	check(intellect > strength * 2, "primary stat suffixes favoured (%d Int vs %d Str)" % [intellect, strength])


# --- Hand-made items -----------------------------------------------------------------------

## Mighty (+Attack Power) / Arcane-touched (+Spell Power) follow the class when one is known:
## magic-weapon classes (Mage, Warlock) mostly roll Spell Power, the others Attack Power;
## items for nobody in particular keep both.
func test_power_enchants_follow_the_class() -> void:
	var arcane := _add_enchant(&"t_arcane", EnchantData.Kind.EQUIP, "Arcane-touched", 1, {Stats.SPELL_POWER: 6.0})
	var mighty: EnchantData = Db.enchants[&"t_mighty"]
	var mage := Db.get_class_data(&"mage")
	var warrior := Db.get_class_data(&"warrior")
	check(ItemGenerator.uses_spell_power(mage) and ItemGenerator.uses_spell_power(Db.get_class_data(&"warlock")),
			"mage and warlock wield magic weapons")
	for id: StringName in [&"warrior", &"rogue", &"paladin"]:
		check(not ItemGenerator.uses_spell_power(Db.get_class_data(id)), "%s: Attack Power" % id)
	check_eq(ItemGenerator.power_enchant_weight(mighty, null), 1.0, "no class: unchanged")
	check_eq(ItemGenerator.power_enchant_weight(arcane, null), 1.0, "no class: unchanged")
	check(ItemGenerator.power_enchant_weight(arcane, mage) > ItemGenerator.power_enchant_weight(mighty, mage), "mage: Spell Power")
	check(ItemGenerator.power_enchant_weight(mighty, warrior) > ItemGenerator.power_enchant_weight(arcane, warrior), "warrior: Attack Power")
	check_eq(ItemGenerator.power_enchant_weight(Db.enchants[&"t_zealous"], mage), 1.0, "other enchants untouched")
	var counts := {}
	for key: String in ["mage", "warrior", "class bias", "nobody"]:
		var rng := _rng(4321)
		var ap := 0
		var sp := 0
		for i in 900:
			var options := {&"rarity": Items.Rarity.RARE}
			match key:
				"mage":
					options[&"usable_by"] = mage
				"warrior":
					options[&"usable_by"] = warrior
				"class bias":
					options[&"class_data"] = mage
			var item := ItemGenerator.generate(SHOP, 10, rng, options)
			for roll in item.enchants:
				if roll.enchant == mighty:
					ap += 1
				elif roll.enchant == arcane:
					sp += 1
		counts[key] = [ap, sp]
	check(counts["mage"][1] > 5 * counts["mage"][0] and counts["mage"][1] > 30, "mage items: Spell Power %s" % str(counts["mage"]))
	check(counts["warrior"][0] > 5 * counts["warrior"][1] and counts["warrior"][0] > 30, "warrior items: Attack Power %s" % str(counts["warrior"]))
	check(counts["class bias"][1] > 2 * counts["class bias"][0], "a class bias leans the same way %s" % str(counts["class bias"]))
	var generic: Array = counts["nobody"]
	check(generic[0] > 20 and generic[1] > 20 and absf(float(generic[0]) / generic[1] - 1.0) < 0.5,
			"generic items keep both %s" % str(generic))


func test_uniques_by_source() -> void:
	var storm := Db.get_unique(&"stormcaller")
	check(not ItemGenerator.unique_available(storm, SHOP, 25), "Legendary never in the shop")
	check(not ItemGenerator.unique_available(storm, LOOT, 9), "min_wave")
	check(ItemGenerator.unique_available(storm, LOOT, 10), "loot at wave 10")
	check(ItemGenerator.unique_available(storm, BOSS, 25), "boss")
	var rng := _rng(29)
	var named := 0
	var rares := 0
	for i in 3000:
		var wave := 1 + i % 25
		var item := ItemGenerator.generate(SHOP, wave, rng)
		if item.unique:
			var data := Db.get_unique(item.source_id)
			check(&"shop" in data.sources, "shop unique lists the shop: %s" % item.display_name)
			check(wave >= data.min_wave, "min wave")
			check_eq(item.rarity, data.rarity, "unique keeps its rarity")
	for i in 3000:
		var item := ItemGenerator.generate(LOOT, 1 + i % 25, rng, {&"rarity": Items.Rarity.RARE})
		rares += 1
		if item.unique and item.slot_type != Items.SlotType.TRINKET:
			named += 1
	var share := float(named) / rares
	check(share > 0.02 and share < 0.1, "named / class items are rare (%.3f)" % share)


func test_trinkets_are_hand_made() -> void:
	var rng := _rng(31)
	for i in 100:
		var item := ItemGenerator.generate([SHOP, LOOT][i % 2], 1 + i % 25, rng, {&"slot_type": Items.SlotType.TRINKET})
		check(item.unique and item.slot_type == Items.SlotType.TRINKET, "a trinket: %s" % item.display_name)
	var cheap := ItemGenerator.generate(SHOP, 1, rng, {&"slot_type": Items.SlotType.TRINKET, &"rarity": Items.Rarity.COMMON})
	check(cheap.slot_type == Items.SlotType.TRINKET and cheap.rarity <= Items.Rarity.EPIC, "forced trinket in the shop")


func test_from_unique() -> void:
	var rng := _rng()
	var storm := ItemGenerator.from_unique(Db.get_unique(&"stormcaller"), 17, true, rng)
	check(storm.unique and storm.is_weapon(), "weapon unique")
	check_eq(storm.weapon.base_damage, Db.get_weapon(&"sword").base_damage * Items.WEAPON_RARITY_DAMAGE[Items.Rarity.LEGENDARY], "Legendary damage")
	check_eq(storm.stats[Stats.STRENGTH], float(roundi(8.0 * 1.2 * 1.25)), "stats grow with tier and loot bonus")
	check_eq(storm.unique_effect, &"chain")
	check_eq(storm.item_level, Items.item_level(17, Items.Rarity.LEGENDARY, true), "item level")
	storm.unique_params["damage"] = 999.0
	check(Db.get_unique(&"stormcaller").unique_params["damage"] != 999.0, "params are a copy")
	var purse := ItemGenerator.from_unique(Db.get_unique(&"goblin_coin_purse"), 20, true, rng)
	check_eq(purse.stats[Stats.ARMOR], -1.0, "drawbacks are not scaled")
	var helm := ItemGenerator.from_unique(Db.get_unique(&"helm_of_the_iron_vigil"), 1, false, rng)
	check_eq(helm.stats.get(Stats.ARMOR, 0.0), 3.0, "plate uniques get implicit armor")
	check_eq(helm.armor_type, ClassData.ArmorType.PLATE)
	check(helm.enchants.is_empty(), "non-Legendary uniques get no random enchants")
	var grimoire := ItemGenerator.from_unique(Db.get_unique(&"grimoire_of_the_imp_lord"), 9, false, rng)
	check_eq(grimoire.class_restriction, &"warlock")
	check(grimoire.can_be_used_by(Db.get_class_data(&"warlock")), "warlock can use it")
	check(not grimoire.can_be_used_by(Db.get_class_data(&"mage")), "a mage cannot")
	check_eq(grimoire.buy_price, ItemGenerator.price_for(grimoire.rarity, 9), "price")


func test_neck_and_ring_have_no_primary_stats() -> void:
	var rng := _rng(37)
	for i in 300:
		var item := ItemGenerator.generate(LOOT, 1 + i % 25, rng, {&"slot_type": [Items.SlotType.NECK, Items.SlotType.RING][i % 2]})
		if item.unique:
			continue
		for stat in [Stats.STRENGTH, Stats.AGILITY, Stats.INTELLECT, Stats.STAMINA]:
			check(not item.stats.has(stat), "no %s on %s" % [stat, item.display_name])


func test_generate_weapon() -> void:
	var rng := _rng()
	var axe := Db.get_weapon(&"two_hand_axe")
	var item := ItemGenerator.generate_weapon(axe, Items.Rarity.EPIC, 5, false, rng)
	check(item.is_weapon() and item.weapon != axe, "a private weapon copy")
	check_eq(item.weapon.base_damage, axe.base_damage * Items.WEAPON_RARITY_DAMAGE[Items.Rarity.EPIC], "rarity damage")
	check(not item.stats.is_empty(), "rolled bonus stats")
	check(item.enchants.size() in [1, 2], "Epic enchants")
	check_eq(axe.base_damage, 12.0, "base untouched")
