extends SceneTree
## Item generator sanity report (GDD 5.2 / 5.4 / 5.7 / 10 / 10.1): generates ~10 000 items
## across sources and waves with a fixed seed and prints rarity distributions, budgets, stat
## counts, enchant / unique frequencies and price ranges.
##
##   godot --headless --path . -s res://tools/item_report.gd [-- --seed=N --count=N]

const WAVES: Array[int] = [1, 3, 5, 8, 10, 13, 15, 18, 20, 25]
## Share of the items per source (shop and normal loot dominate, like in a run).
const SOURCE_SHARE := {
	ItemGenerator.Source.SHOP: 0.4, ItemGenerator.Source.LOOT: 0.3,
	ItemGenerator.Source.ELITE: 0.12, ItemGenerator.Source.GOBLIN: 0.1,
	ItemGenerator.Source.BOSS: 0.08,
}
const SOURCE_NAMES := ["SHOP", "LOOT", "ELITE", "GOBLIN", "BOSS"]
const RARITIES := 5


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var seed_value := 20261010
	var count := 10000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--count="):
			count = int(arg.trim_prefix("--count="))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	print("== Item report: %d items, seed %d ==" % [count, seed_value])
	print("Content: %d bases, %d suffixes, %d weapons, %d enchants, %d uniques" % [
		Db.item_bases.size(), Db.affixes.size(), Db.weapons.size(), Db.enchants.size(),
		Db.uniques.size()])
	_print_tables()

	var items: Array[ItemInstance] = []
	var item_sources: Array[int] = []
	var classes: Array[ClassData] = []
	for id in Db.class_ids:
		classes.append(Db.get_class_data(id))
	for source in SOURCE_SHARE:
		var n := roundi(count * float(SOURCE_SHARE[source]))
		for i in n:
			var wave := WAVES[i % WAVES.size()]
			if source == ItemGenerator.Source.BOSS:
				wave = 10 if i % 2 == 0 else 25
			var options := {}
			if source == ItemGenerator.Source.SHOP and not classes.is_empty() and i % 2 == 0:
				options[&"class_data"] = classes[i % classes.size()]
			var item := ItemGenerator.generate(source, wave, rng, options)
			if item != null:
				items.append(item)
				item_sources.append(source)
	print("Generated %d items\n" % items.size())
	_print_rarity_by_source(items, item_sources)
	_print_budgets(items)
	_print_slots(items)
	_print_enchants(items)
	_print_uniques(items)
	_print_prices(items)
	_print_samples(items)
	_print_class_bias(rng, classes)
	quit(0)


func _print_tables() -> void:
	print("\n-- Rarity tables (no Fortune): C / U / R / E / L --")
	for source in SOURCE_NAMES.size():
		var line := "%-7s" % SOURCE_NAMES[source]
		for wave in [1, 3, 5, 9, 10, 15, 20, 25]:
			var w := ItemGenerator.rarity_weights(source, wave)
			line += "  w%-2d %s" % [wave, "/".join(w.map(func(x: float) -> String: return "%d" % roundi(x * 100)))]
		print(line)
	var line := "LOOT w15, Fortune 0/25/50/100:"
	for f in [0.0, 25.0, 50.0, 100.0]:
		var w := ItemGenerator.rarity_weights(ItemGenerator.Source.LOOT, 15, f)
		line += "  " + "/".join(w.map(func(x: float) -> String: return "%d" % roundi(x * 100)))
	print(line)


func _print_rarity_by_source(items: Array[ItemInstance], sources: Array[int]) -> void:
	print("-- Rarity distribution by source (all waves) --")
	for source in SOURCE_NAMES.size():
		var counts: Array[int] = [0, 0, 0, 0, 0, 0]
		var total := 0
		for i in items.size():
			if sources[i] == source:
				counts[items[i].rarity] += 1
				total += 1
		if total == 0:
			continue
		var parts: PackedStringArray = []
		for r in RARITIES:
			parts.append("%s %.1f%%" % [Items.RARITY_NAMES[r], 100.0 * counts[r] / total])
		print("%-7s n=%-5d %s" % [SOURCE_NAMES[source], total, ", ".join(parts)])
	print("")


func _print_budgets(items: Array[ItemInstance]) -> void:
	print("-- Generated (non-unique) items per rarity: budget, spent, stat lines, ilvl --")
	for r in RARITIES:
		var n := 0
		var budget := 0.0
		var spent := 0.0
		var lines := 0
		var ilvl := 0
		var max_stat := 0.0
		for item in items:
			if item.unique or item.rarity != r:
				continue
			n += 1
			var b := ItemGenerator.stat_budget(item.rarity, item.slot_type, item.wave, item.looted,
					item.weapon)
			budget += b
			var rolled := item.stats.duplicate()
			var implicit := ItemGenerator.implicit_armor(item.armor_type, item.slot_type, item.wave)
			if implicit > 0:
				rolled[Stats.ARMOR] = rolled.get(Stats.ARMOR, 0.0) - implicit
				if is_zero_approx(rolled[Stats.ARMOR]):
					rolled.erase(Stats.ARMOR)
			spent += ItemGenerator.stat_cost(rolled)
			lines += item.stats.size()
			ilvl += item.item_level
			for stat in item.stats:
				max_stat = maxf(max_stat, item.stats[stat])
		if n == 0:
			continue
		print("%-10s n=%-5d budget %5.1f  spent %5.1f  stat lines %.2f  max stat %3d  avg ilvl %.1f" % [
			Items.RARITY_NAMES[r], n, budget / n, spent / n, float(lines) / n, roundi(max_stat),
			float(ilvl) / n])
	print("")


func _print_slots(items: Array[ItemInstance]) -> void:
	var counts := {}
	for item in items:
		var key: String = Items.SLOT_NAMES[item.slot_type]
		counts[key] = counts.get(key, 0) + 1
	var parts: PackedStringArray = []
	for key in counts:
		parts.append("%s %.1f%%" % [key, 100.0 * counts[key] / items.size()])
	print("-- Slots --\n%s\n" % ", ".join(parts))


func _print_enchants(items: Array[ItemInstance]) -> void:
	print("-- Enchants --")
	for r in RARITIES:
		var n := 0
		var total := 0
		var with_any := 0
		var max_count := 0
		for item in items:
			if item.rarity != r:
				continue
			n += 1
			total += item.enchants.size()
			max_count = maxi(max_count, item.enchants.size())
			if not item.enchants.is_empty():
				with_any += 1
		if n > 0:
			print("%-10s avg %.2f  with enchant %.1f%%  max %d" % [Items.RARITY_NAMES[r],
				float(total) / n, 100.0 * with_any / n, max_count])
	var by_id := {}
	var ranks: Array[int] = [0, 0, 0]
	for item in items:
		for roll in item.enchants:
			by_id[roll.enchant.id] = by_id.get(roll.enchant.id, 0) + 1
			ranks[roll.rank] += 1
	if by_id.is_empty():
		print("(no enchants – Db.enchants is empty)\n")
		return
	var ids := by_id.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return by_id[a] > by_id[b])
	var parts: PackedStringArray = []
	for id in ids:
		parts.append("%s %d" % [id, by_id[id]])
	print("By enchant: %s" % ", ".join(parts))
	print("Ranks I/II/III: %d / %d / %d\n" % ranks)


func _print_uniques(items: Array[ItemInstance]) -> void:
	print("-- Hand-made items --")
	var by_rarity: Array[int] = [0, 0, 0, 0, 0, 0]
	var n_rarity: Array[int] = [0, 0, 0, 0, 0, 0]
	var by_id := {}
	var trinkets := 0
	for item in items:
		n_rarity[item.rarity] += 1
		if item.unique:
			by_rarity[item.rarity] += 1
			by_id[item.source_id] = by_id.get(item.source_id, 0) + 1
			if item.slot_type == Items.SlotType.TRINKET:
				trinkets += 1
	for r in RARITIES:
		if n_rarity[r] > 0:
			print("%-10s %.1f%% hand-made (%d)" % [Items.RARITY_NAMES[r],
				100.0 * by_rarity[r] / n_rarity[r], by_rarity[r]])
	print("Trinkets: %d (%.1f%% of all items)" % [trinkets, 100.0 * trinkets / items.size()])
	var never: PackedStringArray = []
	for id in Db.uniques:
		if not by_id.has(id):
			never.append(String(id))
	print("Distinct uniques seen: %d / %d%s\n" % [by_id.size(), Db.uniques.size(),
		("  never: " + ", ".join(never)) if not never.is_empty() else ""])


func _print_prices(items: Array[ItemInstance]) -> void:
	print("-- Prices (buy) --")
	for r in RARITIES:
		var lo := 1 << 30
		var hi := 0
		var sum := 0
		var n := 0
		for item in items:
			if item.rarity != r:
				continue
			lo = mini(lo, item.buy_price)
			hi = maxi(hi, item.buy_price)
			sum += item.buy_price
			n += 1
		if n > 0:
			print("%-10s %4d .. %4d  avg %.0f   (wave 1: %d, wave 10: %d, wave 25: %d)" % [
				Items.RARITY_NAMES[r], lo, hi, float(sum) / n, ItemGenerator.price_for(r, 1),
				ItemGenerator.price_for(r, 10), ItemGenerator.price_for(r, 25)])
	print("")


func _print_samples(items: Array[ItemInstance]) -> void:
	print("-- Samples --")
	var shown := 0
	var step := maxi(1, items.size() / 12)
	for i in range(0, items.size(), step):
		var item := items[i]
		var stats: PackedStringArray = []
		for stat in item.all_stats():
			stats.append("%s %s" % [Stats.format_value(stat, item.all_stats()[stat]), Stats.display_name(stat)])
		var enchants: PackedStringArray = []
		for roll in item.enchants:
			enchants.append("%s %s" % [roll.enchant.id, ["I", "II", "III"][roll.rank]])
		print("[%s] %s (ilvl %d, w%d%s, %dg): %s%s%s" % [item.rarity_name(), item.display_name,
			item.item_level, item.wave, ", Looted" if item.looted else "", item.buy_price,
			", ".join(stats), (" | " + ", ".join(enchants)) if not enchants.is_empty() else "",
			(" | " + item.unique_text) if item.unique_text != "" else ""])
		shown += 1
		if shown >= 12:
			break
	print("")


func _print_class_bias(rng: RandomNumberGenerator, classes: Array[ClassData]) -> void:
	print("-- Shop class bias (&\"class_data\"): share usable by the class --")
	var parts: PackedStringArray = []
	for c in classes:
		var usable := 0
		for i in 400:
			var item := ItemGenerator.generate(ItemGenerator.Source.SHOP, 1 + i % 25, rng, {&"class_data": c})
			if item.can_be_used_by(c):
				usable += 1
		parts.append("%s %.0f%%" % [c.id, usable / 4.0])
	print(", ".join(parts))
