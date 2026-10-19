class_name ItemGenerator
extends RefCounted
## Random item creation (GDD 5.2 rarity, 5.3 armor, 5.4 generation, 5.5 hand-made items,
## 5.6.1 Item Level, 5.7 enchants, 10 prices, 10.1 loot sources).
##
## Stateless: every random choice uses the rng passed in, so the same seed gives the same items.
## Every content pool (bases, suffixes, weapons, enchants, uniques) filters through
## Db.is_unlocked(id).
##
## A generated item is "[Enchant prefix] [Material] [Base] [of the Suffix]" (weapons:
## "[prefix] [Weapon name] [of the Suffix]"):
##   budget = RARITY_BUDGET x slot multiplier x material tier (+10% / +20%) x 1.25 when looted,
##   spent on the suffix's stats at STAT_PRICE (Epic+ moves EXTRA_SECONDARY_SHARE of it into one
##   extra secondary stat). Armor pieces also get implicit Armor (free, not from the budget).
## Hand-made items (UniqueItemData) keep their name and stats (scaled by tier and the loot bonus);
## Legendary rolls become a hand-made Legendary whenever one fits.
## Tier sets (GDD 5.5 / 5.2, M5): right after the rarity roll an EPIC roll becomes a set piece
## with SET_CHANCE_SHOP (shop) or SET_CHANCE_SHOP x SET_LOOT_MULT (loot, elite, goblin, boss),
## for one class: &"usable_by", else the &"class_data" bias, else a random &"team_classes"
## class with a set, else (no team given) any class with a set; the piece is uniform among
## that set's pieces available at the wave (set_piece_available; pieces have weight 0, so the
## plain unique roll never picks them). See [method _roll_set_piece] for the rng draws.
## Attack Power / Spell Power enchants (Mighty / Arcane-touched) follow the class when one is
## known (&"class_data" bias or &"usable_by"): classes whose own weapon is magic (Mage,
## Warlock) mostly roll Spell Power, the others Attack Power (power_enchant_weight); items
## for nobody in particular keep both.
## Artifacts (M6, GDD 5.5): never rolled from the tables – [method generate_artifact] /
## [method from_artifact] make the class's ArtifactData (called by LootDrops.roll_artifact):
## rarity Artifact, Item Level 10 + 3 x wave + 25, fixed enchants, no rng draw at all.

enum Source { SHOP, LOOT, ELITE, GOBLIN, BOSS }

## UniqueItemData.sources id of each Source.
const SOURCE_IDS: Array[StringName] = [&"shop", &"loot", &"elite", &"goblin", &"boss"]

## Stat budget by rarity (GDD 5.2), Common .. Artifact.
const RARITY_BUDGET: Array[float] = [4.0, 7.0, 11.0, 16.0, 22.0, 28.0]
## Base price by rarity (GDD 10). Legendary / Artifact are never sold but have Greed values.
const RARITY_PRICE: Array[int] = [15, 30, 55, 90, 140, 200]
## Price x (1 + PRICE_GROWTH x (wave - 1)).
const PRICE_GROWTH := 0.08
## Looted items get +25% budget (GDD 5.2 "Loot bonus").
const LOOTED_BUDGET_MULT := 1.25
## Material tier II / III: +10% / +20% budget (GDD 5.4).
const TIER_BUDGET_BONUS := 0.1

## Budget multiplier per slot (GDD 5.4). Weapons: one-handers / off-hands (two-handers use
## TWO_HAND_MULT). Trinkets are hand-made; the value only matters for hypothetical bases.
const SLOT_MULT := {
	Items.SlotType.HEAD: 1.0, Items.SlotType.CHEST: 1.0, Items.SlotType.LEGS: 1.0,
	Items.SlotType.SHOULDERS: 0.8, Items.SlotType.HANDS: 0.8, Items.SlotType.WAIST: 0.8,
	Items.SlotType.FEET: 0.8, Items.SlotType.NECK: 0.7, Items.SlotType.RING: 0.7,
	Items.SlotType.TRINKET: 0.7, Items.SlotType.WRIST: 0.6, Items.SlotType.WEAPON: 0.6,
}
const TWO_HAND_MULT := 1.0
## Implicit Armor per armor type, x slot multiplier x material tier (GDD 5.3).
const ARMOR_IMPLICIT := {
	ClassData.ArmorType.CLOTH: 0.0, ClassData.ArmorType.LEATHER: 1.0,
	ClassData.ArmorType.MAIL: 2.0, ClassData.ArmorType.PLATE: 3.0,
}
## Budget points per stat unit (GDD 5.4); stats not listed cost DEFAULT_STAT_PRICE.
const STAT_PRICE := {
	Stats.VERSATILITY: 1.5, Stats.DODGE: 1.5, Stats.SPIRIT: 1.5,
	Stats.ARMOR: 2.0, Stats.LEECH: 2.0,
	Stats.FORTUNE: 0.5, Stats.GOLD_FIND: 0.5,
}
const DEFAULT_STAT_PRICE := 1.0
## Epic+: share of the budget spent on one extra secondary stat (GDD 5.4).
const EXTRA_SECONDARY_SHARE := 0.2
const SECONDARY_STATS: Array[StringName] = [Stats.CRIT, Stats.HASTE, Stats.MASTERY, Stats.VERSATILITY]
const PRIMARY_ATTRIBUTES: Array[StringName] = [Stats.STRENGTH, Stats.AGILITY, Stats.INTELLECT]

## Rarity tables (GDD 5.2): one row per TABLE_WAVES entry, weights Common .. Legendary.
## Linear interpolation between the rows; past the last row the last row is used.
const TABLE_WAVES: Array[int] = [1, 5, 10, 15, 20, 25]
const SHOP_TABLE: Array = [
	[100.0, 0.0, 0.0, 0.0, 0.0],
	[60.0, 30.0, 10.0, 0.0, 0.0],
	[40.0, 35.0, 20.0, 5.0, 0.0],
	[26.0, 33.0, 29.0, 12.0, 0.0],
	[16.0, 30.0, 34.0, 20.0, 0.0],
	[10.0, 25.0, 38.0, 27.0, 0.0],
]
const LOOT_TABLE: Array = [
	[60.0, 40.0, 0.0, 0.0, 0.0],
	[25.0, 45.0, 30.0, 0.0, 0.0],
	[10.0, 35.0, 40.0, 13.0, 2.0],
	[0.0, 25.0, 45.0, 25.0, 5.0],
	[0.0, 15.0, 42.0, 35.0, 8.0],
	[0.0, 8.0, 37.0, 43.0, 12.0],
]
## First wave each rarity may appear (GDD 5.2 "Boltban" / "Lootban" columns).
const SHOP_MIN_WAVE: Array[int] = [1, 2, 4, 9, 1000]
const LOOT_MIN_WAVE: Array[int] = [1, 1, 3, 6, 10]
## Fortune: weight of rarity r x (1 + fortune x FORTUNE_PER_TIER x r).
const FORTUNE_PER_TIER := 0.01
## Loot Goblin: Rare+, at least this share Epic+ (GDD 10.1).
const GOBLIN_EPIC_SHARE := 0.25
## Boss: Epic+, this share Legendary (GDD 10.1).
const BOSS_LEGENDARY_SHARE := 0.2

## Artifacts (GDD 5.5): Greed pays this many Epic prices of the wave (not the sell value).
const ARTIFACT_GREED_MULT := 5.0

## Enchant counts (GDD 5.2 / 5.7).
const UNCOMMON_ENCHANT_CHANCE := 0.3
const EPIC_SECOND_ENCHANT_CHANCE := 0.5
const LEGENDARY_ENCHANTS := 2

## Chance that a non-Legendary roll becomes a hand-made item of the same rarity (named and
## class-specific items; trinkets come through the trinket slot instead).
const UNIQUE_CHANCE := 0.05
## Tier sets (GDD 5.5 / 5.2): chance that an Epic shop roll becomes a set piece; every loot
## source (LOOT, ELITE, GOBLIN, BOSS) rolls SET_LOOT_MULT times that ("3x more common in loot").
const SET_CHANCE_SHOP := 0.05
const SET_LOOT_MULT := 3.0
## The slots tier-set pieces exist for (a forced other slot never rolls a set piece).
const SET_SLOTS: Array[int] = [
	Items.SlotType.HEAD, Items.SlotType.SHOULDERS, Items.SlotType.CHEST, Items.SlotType.HANDS,
	Items.SlotType.LEGS,
]
## Armour bases (GDD 5.4 / 5.8, M6b): the bases of one slot x armour type are material tiers of
## each other (ItemBase.min_wave 1 / 9 / 17). Of those available at the wave the highest tier is
## taken with this chance, else one of the lower tiers (uniform).
const BASE_TOP_TIER_CHANCE := 0.7
## &"class_data" option: share of items made for that class (usable + favoured stats).
const CLASS_BIAS_CHANCE := 0.6
const OWN_ARMOR_WEIGHT := 4.0
const FAVOURED_SUFFIX_WEIGHT := 4.0
const OFF_STAT_SUFFIX_WEIGHT := 0.25
const WEAPON_STAT_SUFFIX_WEIGHT := 3.0
const WEAPON_OFF_STAT_SUFFIX_WEIGHT := 0.35
const OWN_CLASS_UNIQUE_WEIGHT := 3.0
## Enchant weight multipliers of the class's own power stat (Spell Power for magic-weapon
## classes, Attack Power for the others) and of the other one, when the class is known.
const FAVOURED_POWER_ENCHANT_WEIGHT := 1.9
const OFF_POWER_ENCHANT_WEIGHT := 0.1

## Which kind of item a random roll makes.
const SLOT_WEIGHTS := {
	Items.SlotType.WEAPON: 20.0,
	Items.SlotType.HEAD: 6.0, Items.SlotType.SHOULDERS: 6.0, Items.SlotType.CHEST: 6.0,
	Items.SlotType.WRIST: 6.0, Items.SlotType.HANDS: 6.0, Items.SlotType.WAIST: 6.0,
	Items.SlotType.LEGS: 6.0, Items.SlotType.FEET: 6.0,
	Items.SlotType.NECK: 6.0, Items.SlotType.RING: 8.0, Items.SlotType.TRINKET: 6.0,
}
## Material names of jewellery by tier (armor uses Items.MATERIAL_NAMES).
const JEWEL_MATERIALS: Array[String] = ["Copper", "Silver", "Golden"]


static func source_id(source: Source) -> StringName:
	return SOURCE_IDS[clampi(source, 0, SOURCE_IDS.size() - 1)]


# --- Rarity ------------------------------------------------------------------------------------

## Probabilities Common .. Legendary (sum 1) for [param source] at [param wave].
static func rarity_weights(source: Source, wave: int, fortune: float = 0.0) -> Array[float]:
	var loot := _gated(_table_row(LOOT_TABLE, wave), LOOT_MIN_WAVE, wave)
	var w: Array[float] = []
	match source:
		Source.SHOP:
			w = _gated(_table_row(SHOP_TABLE, wave), SHOP_MIN_WAVE, wave)
		Source.LOOT:
			w = loot
		Source.ELITE:
			w = _rare_plus(loot)
		Source.GOBLIN:
			w = _rare_plus(loot)
			var rare := w[Items.Rarity.RARE]
			var epic_plus := w[Items.Rarity.EPIC] + w[Items.Rarity.LEGENDARY]
			var target := rare * GOBLIN_EPIC_SHARE / (1.0 - GOBLIN_EPIC_SHARE)
			if epic_plus <= 0.0:
				w[Items.Rarity.EPIC] = target
			elif epic_plus < target:
				w[Items.Rarity.EPIC] *= target / epic_plus
				w[Items.Rarity.LEGENDARY] *= target / epic_plus
		_:
			w = [0.0, 0.0, 0.0, 1.0 - BOSS_LEGENDARY_SHARE, BOSS_LEGENDARY_SHARE]
			if wave < LOOT_MIN_WAVE[Items.Rarity.LEGENDARY]:
				w[Items.Rarity.LEGENDARY] = 0.0
	for r in range(1, w.size()):
		w[r] *= maxf(0.1, 1.0 + fortune * FORTUNE_PER_TIER * r)
	var total := 0.0
	for v in w:
		total += v
	if total <= 0.0:
		return [1.0, 0.0, 0.0, 0.0, 0.0]
	for r in w.size():
		w[r] /= total
	return w


## Rarity for [param source] at [param wave] (shop / loot tables of GDD 5.2, interpolated
## between the listed waves; Fortune shifts towards higher rarities; shop max Epic).
static func roll_rarity(source: Source, wave: int, fortune: float, rng: RandomNumberGenerator) -> int:
	var r := maxi(0, _pick_index(rarity_weights(source, wave, fortune), rng))
	return mini(r, Items.Rarity.EPIC) if source == Source.SHOP else r


static func _table_row(table: Array, wave: int) -> Array[float]:
	var w := clampi(wave, TABLE_WAVES[0], TABLE_WAVES[-1])
	var i := 0
	while i < TABLE_WAVES.size() - 2 and w > TABLE_WAVES[i + 1]:
		i += 1
	var t := float(w - TABLE_WAVES[i]) / float(TABLE_WAVES[i + 1] - TABLE_WAVES[i])
	var out: Array[float] = []
	for r in (table[i] as Array).size():
		out.append(lerpf(table[i][r], table[i + 1][r], t))
	return out


static func _gated(row: Array[float], min_waves: Array[int], wave: int) -> Array[float]:
	for r in row.size():
		if wave < min_waves[r]:
			row[r] = 0.0
	return row


## Loot table without Common / Uncommon (Rare when nothing is left).
static func _rare_plus(loot: Array[float]) -> Array[float]:
	var w := loot.duplicate()
	w[Items.Rarity.COMMON] = 0.0
	w[Items.Rarity.UNCOMMON] = 0.0
	if w[Items.Rarity.RARE] + w[Items.Rarity.EPIC] + w[Items.Rarity.LEGENDARY] <= 0.0:
		w[Items.Rarity.RARE] = 1.0
	return w


# --- Formulas ----------------------------------------------------------------------------------

## Shop price: rarity base price x (1 + 0.08 x (wave - 1)) (GDD 10).
static func price_for(rarity: int, wave: int) -> int:
	var base := RARITY_PRICE[clampi(rarity, 0, RARITY_PRICE.size() - 1)]
	return roundi(base * (1.0 + PRICE_GROWTH * (maxi(1, wave) - 1)))


## Material tier budget multiplier: 1.0 / 1.1 / 1.2 (waves 1-8 / 9-16 / 17+).
static func tier_multiplier(wave: int) -> float:
	return 1.0 + TIER_BUDGET_BONUS * Items.material_tier(wave)


static func slot_multiplier(slot_type: int, weapon: WeaponData = null) -> float:
	if slot_type == Items.SlotType.WEAPON and weapon != null and weapon.is_two_handed():
		return TWO_HAND_MULT
	return float(SLOT_MULT.get(slot_type, 1.0))


## Stat budget of a generated item (GDD 5.2 / 5.4).
static func stat_budget(rarity: int, slot_type: int, wave: int, looted: bool,
		weapon: WeaponData = null) -> float:
	var budget := RARITY_BUDGET[clampi(rarity, 0, RARITY_BUDGET.size() - 1)]
	budget *= slot_multiplier(slot_type, weapon) * tier_multiplier(wave)
	return budget * (LOOTED_BUDGET_MULT if looted else 1.0)


## Implicit Armor of an armor piece (GDD 5.3): type value x slot multiplier x material tier.
static func implicit_armor(armor_type: int, slot_type: int, wave: int) -> int:
	var base := float(ARMOR_IMPLICIT.get(armor_type, 0.0))
	if base <= 0.0 or slot_type not in Items.ARMOR_SLOTS:
		return 0
	return maxi(1, roundi(base * slot_multiplier(slot_type) * tier_multiplier(wave)))


static func stat_price(stat: StringName) -> float:
	return float(STAT_PRICE.get(stat, DEFAULT_STAT_PRICE))


## Budget points [param stats] are worth (negative values count as negative).
static func stat_cost(stats: Dictionary) -> float:
	var total := 0.0
	for stat in stats:
		total += float(stats[stat]) * stat_price(stat)
	return total


## Enchant rank (0 = I, 1 = II, 2 = III) by the item's wave; looted items get one rank more.
## Never above III (EnchantData.MAX_GENERATED_RANK): IV and V only come from the Enchanter.
static func enchant_rank(wave: int, looted: bool) -> int:
	return mini(Items.material_tier(wave) + (1 if looted else 0), EnchantData.MAX_GENERATED_RANK)


## How many random enchants an item of [param rarity] gets (GDD 5.2 / 5.7).
static func enchant_count(rarity: int, looted: bool, rng: RandomNumberGenerator) -> int:
	match rarity:
		Items.Rarity.COMMON:
			return 0
		Items.Rarity.UNCOMMON:
			return 1 if looted or rng.randf() < UNCOMMON_ENCHANT_CHANCE else 0
		Items.Rarity.RARE:
			return 1
		Items.Rarity.EPIC:
			return 2 if rng.randf() < EPIC_SECOND_ENCHANT_CHANCE else 1
	return LEGENDARY_ENCHANTS


## Whether [param enchant] may roll on [param item] (kind / slot rules of GDD 5.7, min rarity,
## projectile-only enchants). Uncommon items only take EQUIP enchants.
static func enchant_fits(enchant: EnchantData, item: ItemInstance) -> bool:
	if enchant == null or item == null or item.rarity < enchant.min_rarity:
		return false
	if item.rarity <= Items.Rarity.UNCOMMON and enchant.kind != EnchantData.Kind.EQUIP:
		return false
	if enchant.requires_projectile and not (item.is_weapon()
			and item.weapon.attack_kind == WeaponData.AttackKind.PROJECTILE):
		return false
	var slot := item.slot_type
	if not enchant.slot_types.is_empty() and int(slot) not in enchant.slot_types:
		return false
	match enchant.kind:
		EnchantData.Kind.ON_HIT:
			if enchant.slot_types.is_empty() and slot not in [Items.SlotType.WEAPON,
					Items.SlotType.RING, Items.SlotType.TRINKET]:
				return false
		EnchantData.Kind.WHEN_STRUCK:
			if slot == Items.SlotType.WEAPON and not (item.is_weapon()
					and item.weapon.weapon_type == &"shield"):
				return false
			if enchant.slot_types.is_empty() and slot not in [Items.SlotType.CHEST,
					Items.SlotType.SHOULDERS, Items.SlotType.HEAD, Items.SlotType.WEAPON]:
				return false
	return true


# --- Generation --------------------------------------------------------------------------------

## A new random item. [param options] (all optional):
##   &"class_data": ClassData – bias the base / weapon / stats towards what this class can use
##       (CLASS_BIAS_CHANCE of the items are usable by it, its own armor type and primary stat
##       suffixes are favoured)
##   &"usable_by": ClassData – only items this class can use
##   &"slot_type": Items.SlotType – force the slot
##   &"rarity": int – force the rarity (the shop still never goes above Epic)
##   &"fortune": float
##   &"team_classes": Array[ClassData] – the party (LootDrops.team_classes): a tier-set piece
##       rolled without &"usable_by" / &"class_data" is for one of these classes
##   &"rarity" = Items.Rarity.ARTIFACT: the Artifact of the class of &"usable_by" / &"class_data"
##       (else of the first &"team_classes" class that has one) – [method generate_artifact]; falls
##       back to a Legendary when no class / Artifact fits
static func generate(source: Source, wave: int, rng: RandomNumberGenerator, options: Dictionary = {}) -> ItemInstance:
	wave = maxi(1, wave)
	if options.has(&"rarity") and int(options[&"rarity"]) >= Items.Rarity.ARTIFACT:
		var artifact := generate_artifact(_artifact_class_of(options), wave)
		if artifact != null:
			return artifact
		options = options.duplicate()
		options[&"rarity"] = Items.Rarity.LEGENDARY
	var looted := source != Source.SHOP
	var rarity: int
	if options.has(&"rarity"):
		rarity = int(options[&"rarity"])
	else:
		rarity = roll_rarity(source, wave, float(options.get(&"fortune", 0.0)), rng)
	var max_rarity := Items.Rarity.EPIC if source == Source.SHOP else Items.Rarity.LEGENDARY
	rarity = clampi(rarity, Items.Rarity.COMMON, max_rarity)
	var usable := options.get(&"usable_by") as ClassData
	var bias := options.get(&"class_data") as ClassData
	var forced := int(options.get(&"slot_type", -1))

	# Tier sets: an Epic roll may become a set piece (GDD 5.5).
	if rarity == Items.Rarity.EPIC:
		var set_class := usable if usable != null else bias
		var piece := _roll_set_piece(source, wave, forced, set_class, options.get(&"team_classes", []), rng)
		if piece != null:
			return from_unique(piece, wave, looted, rng, Db.get_class_data(piece.class_restriction))

	var favour: ClassData = null
	if bias != null and rng.randf() < CLASS_BIAS_CHANCE:
		favour = bias
		if usable == null:
			usable = bias

	# Hand-made items: a Legendary roll is a hand-made Legendary whenever one fits.
	if rarity >= Items.Rarity.LEGENDARY or rng.randf() < UNIQUE_CHANCE:
		var with_trinkets := rarity >= Items.Rarity.LEGENDARY or forced == Items.SlotType.TRINKET
		var data := _pick_unique(source, wave, rarity, forced, with_trinkets, usable, favour, rng)
		if data != null:
			return from_unique(data, wave, looted, rng, favour if favour != null else usable)

	var slot := forced if forced >= 0 else _roll_slot(rng, true)
	if slot == Items.SlotType.TRINKET:
		# Trinkets are all hand-made (GDD 5.5).
		var trinket := _pick_unique(source, wave, rarity, slot, true, usable, favour, rng)
		if trinket == null and forced == Items.SlotType.TRINKET:
			trinket = _pick_unique(source, wave, -1, slot, true, usable, favour, rng)
		if trinket != null:
			return from_unique(trinket, wave, looted, rng, favour if favour != null else usable)
		slot = Items.SlotType.RING if forced == Items.SlotType.TRINKET else _roll_slot(rng, false)

	# The class the enchants are rolled for (Attack / Spell Power, power_enchant_weight).
	var for_class: ClassData = favour if favour != null else usable
	if slot == Items.SlotType.WEAPON:
		var weapon := _pick_weapon(usable, rng)
		if weapon != null:
			return _make_weapon(weapon, rarity, wave, looted, favour, rng, for_class)
		slot = Items.SlotType.CHEST
	var base := pick_base(slot, usable, favour, wave, rng)
	if base == null:
		var any_weapon := _pick_weapon(usable, rng)
		if any_weapon == null:
			push_warning("ItemGenerator: no item bases or weapons to generate from")
			return null
		return _make_weapon(any_weapon, rarity, wave, looted, favour, rng, for_class)
	return _make_from_base(base, rarity, wave, looted, favour, rng, for_class)


## The Artifact of [param class_id] as an item of [param wave] (null when the class has none) –
## see [method from_artifact]. Draws nothing from any rng.
static func generate_artifact(class_id: StringName, wave: int) -> ItemInstance:
	var data := Db.artifact_for_class(class_id)
	return from_artifact(data, wave) if data != null else null


## Gold a Greed on an Artifact of [param wave] pays (GDD 5.5: 5 x the Epic price of the wave).
static func artifact_greed_value(wave: int) -> int:
	return roundi(price_for(Items.Rarity.EPIC, wave) * ARTIFACT_GREED_MULT)


## The class id of a generate() call's options: usable_by, else class_data, else the first
## team class that has an Artifact ("" = none).
static func _artifact_class_of(options: Dictionary) -> StringName:
	var cd := (options.get(&"usable_by") as ClassData)
	if cd == null:
		cd = options.get(&"class_data") as ClassData
	if cd != null:
		return cd.id
	for c: Variant in options.get(&"team_classes", []):
		var team_class := c as ClassData
		if team_class != null and Db.artifact_for_class(team_class.id) != null:
			return team_class.id
	return &""


## A weapon item of [param base] (rarity damage multiplier, bonus stats, enchants).
static func generate_weapon(base: WeaponData, rarity: int, wave: int, looted: bool, rng: RandomNumberGenerator) -> ItemInstance:
	return _make_weapon(base, rarity, maxi(1, wave), looted, null, rng)


## A hand-designed item instance. Its stats grow with the material tier of [param wave] and the
## loot bonus (negative stats stay as designed); armor pieces get implicit Armor; fixed
## enchants come from data.enchant_ids (looted: +1 rank); Legendaries are topped up to
## LEGENDARY_ENCHANTS random enchants (for [param for_class], see power_enchant_weight).
static func from_unique(data: UniqueItemData, wave: int, looted: bool, rng: RandomNumberGenerator,
		for_class: ClassData = null) -> ItemInstance:
	wave = maxi(1, wave)
	var item := ItemInstance.new()
	item.source_id = data.id
	item.unique = true
	item.display_name = data.display_name
	item.flavor = data.flavor
	item.rarity = data.rarity
	item.wave = wave
	item.looted = looted
	item.item_level = Items.item_level(wave, data.rarity, looted)
	item.class_restriction = data.class_restriction
	item.unique_effect = data.unique_effect
	item.unique_params = data.unique_params.duplicate(true)
	item.unique_text = data.unique_text
	item.set_id = data.set_id
	if data.weapon != null:
		item.slot_type = Items.SlotType.WEAPON
		item.weapon = ItemInstance.scaled_weapon(data.weapon, data.rarity)
	else:
		item.slot_type = data.slot_type
		item.armor_type = data.armor_type
	var mult := tier_multiplier(wave) * (LOOTED_BUDGET_MULT if looted else 1.0)
	item.stats = _scaled_unique_stats(data.stats, mult)
	var armor := implicit_armor(item.armor_type, item.slot_type, wave)
	if armor > 0:
		item.stats[Stats.ARMOR] = item.stats.get(Stats.ARMOR, 0.0) + armor
	for i in data.enchant_ids.size():
		var enchant := Db.get_enchant(data.enchant_ids[i])
		if enchant == null:
			continue
		var rank := data.enchant_ranks[i] if i < data.enchant_ranks.size() else enchant_rank(wave, false)
		item.enchants.append(EnchantRoll.new(enchant,
				mini(rank + (1 if looted else 0), EnchantData.MAX_GENERATED_RANK)))
	# (An Artifact keeps exactly its fixed enchants: no top-up, no rng.)
	if data.rarity == Items.Rarity.LEGENDARY and item.enchants.size() < LEGENDARY_ENCHANTS:
		_roll_enchants(item, LEGENDARY_ENCHANTS - item.enchants.size(), rng, for_class)
	item.buy_price = price_for(data.rarity, wave)
	return item


## [param stats] of a hand-made item scaled by [param mult] (positive whole numbers round,
## fractions snap to 0.5; negative stats stay as designed).
static func _scaled_unique_stats(stats: Dictionary, mult: float) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	for stat: StringName in stats:
		var v := float(stats[stat])
		if v > 0.0:
			v = float(roundi(v * mult)) if is_equal_approx(v, roundf(v)) else snappedf(v * mult, 0.5)
		out[stat] = v
	return out


## The Artifact item of [param data] made at [param wave] (GDD 5.5): rarity Artifact, looted
## stats (tier and loot bonus like any hand-made item) and fixed enchants, Item Level
## 10 + 3 x wave + 25 (no Looted +6), the weapon at the Artifact damage multiplier with
## artifact_base_damage remembered for the growth, the model tint, and – for a pair (Fangs of
## the Shadow) – the off-hand piece as [member ItemInstance.companion]. No rng draw.
static func from_artifact(data: ArtifactData, wave: int) -> ItemInstance:
	if data == null:
		return null
	wave = maxi(1, wave)
	var item := from_unique(data, wave, true, null, Db.get_class_data(data.class_id))
	if data.class_id != &"":
		item.class_restriction = data.class_id
	item.rarity = Items.Rarity.ARTIFACT
	_finish_artifact_piece(item, data, wave)
	item.buy_price = artifact_greed_value(wave) * 2
	if data.is_pair():
		var off := ItemInstance.new()
		off.source_id = data.id
		off.unique = true
		off.display_name = data.pair_name if data.pair_name != "" else data.display_name
		off.flavor = data.flavor
		off.rarity = Items.Rarity.ARTIFACT
		off.wave = wave
		off.looted = true
		off.class_restriction = item.class_restriction
		off.slot_type = Items.SlotType.WEAPON
		off.weapon = ItemInstance.scaled_weapon(data.pair_weapon, Items.Rarity.ARTIFACT)
		off.stats = _scaled_unique_stats(data.pair_stats, tier_multiplier(wave) * LOOTED_BUDGET_MULT)
		for i in data.pair_enchant_ids.size():
			var enchant := Db.get_enchant(data.pair_enchant_ids[i])
			if enchant != null:
				var rank := data.pair_enchant_ranks[i] if i < data.pair_enchant_ranks.size() else enchant_rank(wave, false)
				off.enchants.append(EnchantRoll.new(enchant, rank + 1))
		off.pair_off = true
		off.buy_price = item.buy_price
		_finish_artifact_piece(off, data, wave)
		item.companion = off
	return item


## Item Level, growth baseline and look of one piece of an Artifact.
static func _finish_artifact_piece(piece: ItemInstance, data: ArtifactData, wave: int) -> void:
	piece.item_level = Items.item_level(wave, Items.Rarity.ARTIFACT, false)
	piece.artifact_waves = 0
	if piece.weapon != null:
		piece.artifact_base_damage = piece.weapon.base_damage
		if data.weapon_color.a > 0.0:
			piece.weapon.color = data.weapon_color


static func _make_from_base(base: ItemBase, rarity: int, wave: int, looted: bool,
		favour: ClassData, rng: RandomNumberGenerator, for_class: ClassData = null) -> ItemInstance:
	var item := ItemInstance.new()
	item.source_id = base.id
	item.slot_type = base.slot_type
	item.armor_type = base.armor_type
	item.rarity = rarity
	item.wave = wave
	item.looted = looted
	item.item_level = Items.item_level(wave, rarity, looted)
	var affix := _pick_affix(base.slot_type, favour, null, rng)
	_roll_stats(item, stat_budget(rarity, base.slot_type, wave, looted), affix,
			implicit_armor(base.armor_type, base.slot_type, wave), rng)
	_roll_enchants(item, enchant_count(rarity, looted, rng), rng, for_class)
	item.display_name = _join([_prefix(item), _material_name(base.armor_type, wave),
			base.display_name, affix.suffix if affix != null else ""])
	item.buy_price = price_for(rarity, wave)
	return item


static func _make_weapon(base: WeaponData, rarity: int, wave: int, looted: bool,
		favour: ClassData, rng: RandomNumberGenerator, for_class: ClassData = null) -> ItemInstance:
	var item := ItemInstance.from_weapon(base, rarity, wave, looted)
	var affix := _pick_affix(Items.SlotType.WEAPON, favour, base, rng)
	_roll_stats(item, stat_budget(rarity, Items.SlotType.WEAPON, wave, looted, base), affix, 0, rng)
	_roll_enchants(item, enchant_count(rarity, looted, rng), rng, for_class)
	item.display_name = _join([_prefix(item), base.display_name,
			affix.suffix if affix != null else ""])
	item.buy_price = price_for(rarity, wave)
	return item


## Spends [param budget] on the suffix's stats (+ the extra secondary stat for Epic+) and adds
## the implicit armor. Every stat is at least 1.
static func _roll_stats(item: ItemInstance, budget: float, affix: AffixData, armor: int,
		rng: RandomNumberGenerator) -> void:
	var extra := item.rarity >= Items.Rarity.EPIC
	var main := budget * (1.0 - EXTRA_SECONDARY_SHARE) if extra else budget
	var stats: Array[StringName] = []
	var shares: Array[float] = []
	if affix != null and not affix.stats.is_empty():
		stats = affix.stats
		for i in stats.size():
			shares.append(affix.shares[i] if i < affix.shares.size() else 1.0)
	else:
		stats = [Stats.VERSATILITY if item.slot_type in [Items.SlotType.NECK, Items.SlotType.RING]
				else Stats.STAMINA]
		shares = [1.0]
	var share_total := 0.0
	for s in shares:
		share_total += maxf(s, 0.0)
	for i in stats.size():
		var share := maxf(shares[i], 0.0) / share_total if share_total > 0.0 else 1.0 / stats.size()
		_add_stat(item, stats[i], main * share)
	if armor > 0:
		item.stats[Stats.ARMOR] = item.stats.get(Stats.ARMOR, 0.0) + armor
	if extra:
		var options: Array[StringName] = []
		for s in SECONDARY_STATS:
			if not item.stats.has(s):
				options.append(s)
		if not options.is_empty():
			_add_stat(item, options[rng.randi_range(0, options.size() - 1)],
					budget * EXTRA_SECONDARY_SHARE)


static func _add_stat(item: ItemInstance, stat: StringName, points: float) -> void:
	var units := maxi(1, roundi(points / stat_price(stat)))
	item.stats[stat] = item.stats.get(stat, 0.0) + units


## Adds up to [param count] different random enchants that fit the item (weighted; Attack /
## Spell Power by the class [param for_class], see power_enchant_weight).
static func _roll_enchants(item: ItemInstance, count: int, rng: RandomNumberGenerator,
		for_class: ClassData = null) -> void:
	if count <= 0:
		return
	var have: Array[StringName] = []
	for roll in item.enchants:
		if roll.enchant != null:
			have.append(roll.enchant.id)
	var pool: Array[EnchantData] = []
	var weights: Array[float] = []
	for id in Db.enchants:
		var enchant: EnchantData = Db.enchants[id]
		if enchant == null or enchant.weight <= 0.0 or enchant.id in have:
			continue
		if not Db.is_unlocked(enchant.id) or not enchant_fits(enchant, item):
			continue
		pool.append(enchant)
		weights.append(enchant.weight * power_enchant_weight(enchant, for_class))
	var rank := enchant_rank(item.wave, item.looted)
	while count > 0 and not pool.is_empty():
		var i := _pick_index(weights, rng)
		if i < 0:
			break
		item.enchants.append(EnchantRoll.new(pool[i], rank))
		pool.remove_at(i)
		weights.remove_at(i)
		count -= 1


## Whether [param class_data]'s damage goes through Spell Power: its own (starting) weapon is
## a magic weapon (GDD 2.4.1) – Mage (wand), Warlock (staff).
static func uses_spell_power(class_data: ClassData) -> bool:
	return class_data != null and class_data.main_hand != null and class_data.main_hand.is_magic()


## Enchant weight multiplier for [param for_class]: an Attack Power enchant (Mighty) is
## favoured for physical classes and rare for magic-weapon classes, a Spell Power enchant
## (Arcane-touched) the other way round. 1 for every other enchant and without a class.
static func power_enchant_weight(enchant: EnchantData, for_class: ClassData) -> float:
	if for_class == null or enchant == null:
		return 1.0
	var attack := enchant.equip_stats.has(Stats.ATTACK_POWER)
	var spell := enchant.equip_stats.has(Stats.SPELL_POWER)
	if attack == spell:
		return 1.0
	return FAVOURED_POWER_ENCHANT_WEIGHT if spell == uses_spell_power(for_class) else OFF_POWER_ENCHANT_WEIGHT


# --- Pools -------------------------------------------------------------------------------------

static func _roll_slot(rng: RandomNumberGenerator, allow_trinket: bool) -> int:
	var slots: Array[int] = []
	var weights: Array[float] = []
	for slot in SLOT_WEIGHTS:
		if slot == Items.SlotType.TRINKET and not allow_trinket:
			continue
		slots.append(slot)
		weights.append(SLOT_WEIGHTS[slot])
	return slots[maxi(0, _pick_index(weights, rng))]


static func _pick_weapon(usable: ClassData, rng: RandomNumberGenerator) -> WeaponData:
	var pool: Array[WeaponData] = []
	for id in Db.weapons:
		var w: WeaponData = Db.weapons[id]
		if Db.is_unlocked(w.id) and (usable == null or usable.can_use(w)):
			pool.append(w)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


## The base of a generated item for [param slot] at [param wave] (null = none fits). Bases
## with min_wave above the wave are not available; [param usable] drops armour heavier than its
## class wears. Armour bases are grouped per armour type (the material tiers of one slot x type):
## one weighted draw picks the type (the weight of the highest available tier, x OWN_ARMOR_WEIGHT
## for [param favour]'s own type – with one tier per type exactly the pre-M6b draw), then a group
## with several tiers draws once more: the highest tier below BASE_TOP_TIER_CHANCE, else
## one of the lower tiers (a second draw only with two or more lower ones). Jewellery bases are
## variety, every base is its own entry. Draws: 1, +1 for a group with tiers, +1 for the
## lower-tier pick among several.
static func pick_base(slot: int, usable: ClassData, favour: ClassData, wave: int,
		rng: RandomNumberGenerator) -> ItemBase:
	# Entries in the draw order: jewellery in Db order, armour by armour type; each is a list of
	# one base (jewellery) or the tiers of one armour type, lowest first.
	var entries: Array[Array] = []
	var tiers_of: Dictionary[int, Array] = {}
	for id: StringName in Db.item_bases:
		var base: ItemBase = Db.item_bases[id]
		if base.slot_type != slot or base.weight <= 0.0 or base.min_wave > wave \
				or not Db.is_unlocked(base.id):
			continue
		if usable != null and base.armor_type != Items.NO_ARMOR and base.armor_type > usable.armor_type:
			continue
		if base.armor_type == Items.NO_ARMOR:
			entries.append([base])
		else:
			if not tiers_of.has(base.armor_type):
				tiers_of[base.armor_type] = []
			tiers_of[base.armor_type].append(base)
	var armor_types: Array[int] = []
	armor_types.assign(tiers_of.keys())
	armor_types.sort()
	for armor_type: int in armor_types:
		var tiers: Array = tiers_of[armor_type]
		tiers.sort_custom(func(a: ItemBase, b: ItemBase) -> bool:
			return a.min_wave < b.min_wave or (a.min_wave == b.min_wave and String(a.id) < String(b.id)))
		entries.append(tiers)
	var weights: Array[float] = []
	for tiers: Array in entries:
		var top: ItemBase = tiers[-1]
		var own := favour != null and top.armor_type == favour.armor_type
		weights.append(top.weight * (OWN_ARMOR_WEIGHT if own else 1.0))
	var i := _pick_index(weights, rng)
	if i < 0:
		return null
	var picked: Array = entries[i]
	if picked.size() == 1 or rng.randf() < BASE_TOP_TIER_CHANCE:
		return picked[-1]
	var lower := picked.size() - 1
	return picked[0] if lower == 1 else picked[rng.randi_range(0, lower - 1)]


## A suffix for [param slot_type]. [param favour] prefers its primary stat; [param weapon]
## prefers the stats the weapon scales with (or grants, for shields / tomes).
static func _pick_affix(slot_type: int, favour: ClassData, weapon: WeaponData,
		rng: RandomNumberGenerator) -> AffixData:
	var weapon_stats: Array[StringName] = []
	if weapon != null:
		for stat in (weapon.scaling if not weapon.scaling.is_empty() else weapon.bonus_stats):
			weapon_stats.append(stat)
	var pool: Array[AffixData] = []
	var weights: Array[float] = []
	for id in Db.affixes:
		var affix: AffixData = Db.affixes[id]
		if affix.weight <= 0.0 or not Db.is_unlocked(affix.id):
			continue
		if not affix.slot_types.is_empty() and slot_type not in affix.slot_types:
			continue
		var w := affix.weight
		var has_attribute := false
		for stat in affix.stats:
			if stat in PRIMARY_ATTRIBUTES:
				has_attribute = true
		if favour != null:
			if favour.primary_stat in affix.stats:
				w *= FAVOURED_SUFFIX_WEIGHT
			elif has_attribute:
				w *= OFF_STAT_SUFFIX_WEIGHT
		if not weapon_stats.is_empty():
			var matches := false
			for stat in affix.stats:
				if stat in weapon_stats:
					matches = true
			if matches:
				w *= WEAPON_STAT_SUFFIX_WEIGHT
			elif has_attribute:
				w *= WEAPON_OFF_STAT_SUFFIX_WEIGHT
		pool.append(affix)
		weights.append(w)
	var i := _pick_index(weights, rng)
	return pool[i] if i >= 0 else null


## A hand-made item for this roll. [param rarity] -1 = any, [param slot] -1 = any.
static func _pick_unique(source: Source, wave: int, rarity: int, slot: int, with_trinkets: bool,
		usable: ClassData, favour: ClassData, rng: RandomNumberGenerator) -> UniqueItemData:
	var pool: Array[UniqueItemData] = []
	var weights: Array[float] = []
	for id in Db.uniques:
		var data: UniqueItemData = Db.uniques[id]
		if not unique_available(data, source, wave):
			continue
		if rarity >= 0 and data.rarity != rarity:
			continue
		var data_slot := unique_slot(data)
		if slot >= 0 and data_slot != slot:
			continue
		if data_slot == Items.SlotType.TRINKET and not with_trinkets:
			continue
		if usable != null and not unique_usable_by(data, usable):
			continue
		pool.append(data)
		var own := favour != null and data.class_restriction == favour.id
		weights.append(data.weight * (OWN_CLASS_UNIQUE_WEIGHT if own else 1.0))
	var i := _pick_index(weights, rng)
	return pool[i] if i >= 0 else null


## Chance (0..1) that an Epic roll from [param source] becomes a tier-set piece.
static func set_chance(source: Source) -> float:
	return SET_CHANCE_SHOP if source == Source.SHOP else SET_CHANCE_SHOP * SET_LOOT_MULT


## Whether the set piece [param data] may come from [param source] at [param wave]: like
## [method unique_available] but without the weight (pieces have weight 0 so that the plain
## unique roll never picks them).
static func set_piece_available(data: UniqueItemData, source: Source, wave: int) -> bool:
	if data == null or data.set_id == &"" or not Db.is_unlocked(data.id):
		return false
	if source_id(source) not in data.sources or wave < data.min_wave:
		return false
	return source != Source.SHOP or data.rarity <= Items.Rarity.EPIC


## The classes a set piece may be rolled for: [param for_class] alone when given, else the
## [param team] classes that have a set (in team order), else – no team given – every class
## with a set (Db.class_ids order). Empty when none fits.
static func set_classes(for_class: ClassData, team: Array) -> Array[ClassData]:
	var out: Array[ClassData] = []
	if for_class != null:
		if Db.set_for_class(for_class.id) != null:
			out.append(for_class)
		return out
	if not team.is_empty():
		for c: Variant in team:
			var cd := c as ClassData
			if cd != null and cd not in out and Db.set_for_class(cd.id) != null:
				out.append(cd)
		return out
	for id in Db.class_ids:
		if Db.set_for_class(id) != null:
			out.append(Db.get_class_data(id))
	return out


## The tier-set roll of an Epic item (null = it stays a normal Epic). [param rng] (RunState.rng
## for loot, the shop rng for offers) draws, in order: 1. the set chance (randf) – only when
## [param forced_slot] is none or a set slot; on a hit 2. the class (randi_range) – only when
## more than one class fits; 3. the piece (randi_range) – only when more than one piece of that
## set is available for the slot / wave.
## A hit without an available piece (wave < min_wave, a team without a set) draws no more.
static func _roll_set_piece(source: Source, wave: int, forced_slot: int, for_class: ClassData,
		team: Array, rng: RandomNumberGenerator) -> UniqueItemData:
	if forced_slot >= 0 and forced_slot not in SET_SLOTS:
		return null
	if rng.randf() >= set_chance(source):
		return null
	var classes := set_classes(for_class, team)
	if classes.is_empty():
		return null
	var cls := classes[0] if classes.size() == 1 else classes[rng.randi_range(0, classes.size() - 1)]
	var set_data := Db.set_for_class(cls.id)
	var pool: Array[UniqueItemData] = []
	for piece_id in set_data.piece_ids:
		var data := Db.get_unique(piece_id)
		if not set_piece_available(data, source, wave) or not unique_usable_by(data, cls):
			continue
		if forced_slot >= 0 and unique_slot(data) != forced_slot:
			continue
		pool.append(data)
	if pool.is_empty():
		return null
	return pool[0] if pool.size() == 1 else pool[rng.randi_range(0, pool.size() - 1)]


## Whether [param data] may come from [param source] at [param wave]: unlocked, listed source,
## min_wave reached; never above Epic in the shop (Legendaries only from loot sources).
static func unique_available(data: UniqueItemData, source: Source, wave: int) -> bool:
	if data == null or data.weight <= 0.0 or not Db.is_unlocked(data.id):
		return false
	if source_id(source) not in data.sources or wave < data.min_wave:
		return false
	return source != Source.SHOP or data.rarity <= Items.Rarity.EPIC


static func unique_slot(data: UniqueItemData) -> int:
	return Items.SlotType.WEAPON if data.weapon != null else data.slot_type


## Same rules as ItemInstance.can_be_used_by, on the data.
static func unique_usable_by(data: UniqueItemData, class_data: ClassData) -> bool:
	if class_data == null:
		return false
	if data.class_restriction != &"" and data.class_restriction != class_data.id:
		return false
	if data.weapon != null:
		return class_data.can_use(data.weapon)
	return data.armor_type == Items.NO_ARMOR or data.armor_type <= class_data.armor_type


# --- Helpers -----------------------------------------------------------------------------------

## Weighted random index (-1 if every weight is 0).
static func _pick_index(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return -1
	var x := rng.randf() * total
	var last := -1
	for i in weights.size():
		if weights[i] <= 0.0:
			continue
		last = i
		x -= weights[i]
		if x < 0.0:
			return i
	return last


static func _material_name(armor_type: int, wave: int) -> String:
	var tier := Items.material_tier(wave)
	if Items.MATERIAL_NAMES.has(armor_type):
		return Items.MATERIAL_NAMES[armor_type][tier]
	return JEWEL_MATERIALS[tier]


static func _prefix(item: ItemInstance) -> String:
	for roll in item.enchants:
		if roll.enchant != null and roll.enchant.prefix != "":
			return roll.enchant.prefix
	return ""


static func _join(parts: Array[String]) -> String:
	var out: PackedStringArray = []
	for p in parts:
		if p != "":
			out.append(p)
	return " ".join(out)
