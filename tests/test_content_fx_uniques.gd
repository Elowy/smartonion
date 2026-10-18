extends TestCase
## M6b CONTENT-FX: the 20 new trinkets (30 in all) and the 17 new Legendaries (25 in all) of
## res://data/uniques/ (GDD 5.5 / 5.8). Every one loads with valid fields inside the unique
## vocabulary, its tooltip shows the numbers of its params, the Legendaries cover every slot type
## and every class, and every effect fires through its trigger and does what the tooltip says.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0

const NEW_TRINKETS: Array[StringName] = [
	&"bottled_thundercloud", &"wasp_nest_charm", &"jar_of_leeches", &"bell_of_stillness",
	&"warbeat_drum", &"carrion_talon", &"bone_chime", &"soul_lantern", &"notched_tally_stick",
	&"porcupine_quill", &"beetle_carapace", &"basilisk_eye", &"ashfall_feather", &"alarm_whistle",
	&"smoke_pouch", &"mote_lantern", &"singing_bowl", &"prospectors_pebble", &"wayward_compass",
	&"votive_candle",
]
const NEW_LEGENDARIES: Array[StringName] = [
	&"greathelm_of_the_gilded_oath", &"pauldrons_of_the_radiant_bulwark", &"sabatons_of_the_long_march",
	&"breastplate_of_unbroken_anger", &"girdle_of_the_last_roar", &"tearjerker",
	&"hood_of_the_quiet_knife", &"bracers_of_the_hidden_blade", &"breeches_of_the_light_fingers",
	&"vial_of_distilled_adrenaline", &"amulet_of_unspent_wishes", &"leggings_of_the_brimming_well",
	&"staff_of_the_deep_winter", &"gloves_of_the_patient_rot", &"robe_of_the_hollow_pact",
	&"ring_of_the_mischievous_imp", &"grimoire_of_seeded_doom",
]
const OLD_LEGENDARIES: Array[StringName] = [
	&"boots_of_the_wanderer", &"bulwark_of_the_last_stand", &"crown_of_ashes", &"gauntlets_of_the_titan",
	&"mantle_of_the_archmage", &"ring_of_endless_hunger", &"sash_of_twin_souls", &"stormcaller",
]
const OLD_TRINKETS: Array[StringName] = [
	&"banner_of_the_warband", &"ember_of_the_forge", &"gnomish_pocket_battery", &"goblin_coin_purse",
	&"heart_of_the_mountain", &"hourglass_of_echoes", &"idol_of_the_moon", &"lucky_rabbit_foot",
	&"shard_of_everfrost", &"vial_of_troll_blood",
]
const TRIGGERS: Array[String] = ["on_hit", "on_kill", "when_struck", "low_hp", "periodic", "equip"]
const TEXT_STARTS: Array[String] = ["Equip: ", "Chance on hit: ", "On kill: ", "When struck: ", "Every "]
const BANNED: Array[String] = [
	"azeroth", "murloc", "horde", "alliance", "thunderfury", "frozen throne", "silver hand",
	"ashbringer", "frostmourne", "warcraft", "lich king", "sylvanas", "windrunner", "arthas",
	"illidan", "thrall", "stormwind", "orgrimmar", "time is money", "felheart", "shadowcraft",
	"lightforged", "gorehowl", "sulfuras", "doomhammer", "atiesh", "warglaive",
]
## Params whose number the tooltip must show (when they matter for the effect).
const TEXT_KEYS: Array[String] = [
	"damage", "heal", "amount", "duration", "interval", "chance", "threshold", "radius", "targets",
	"stacks", "slow", "slow_duration", "stun", "dot", "dot_duration", "spread", "max_hp_pct",
	"hit_pct", "max_stacks", "count",
]

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 99)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


# --- Helpers ------------------------------------------------------------------------------

static func _all_new() -> Array[StringName]:
	var out: Array[StringName] = []
	out.append_array(NEW_TRINKETS)
	out.append_array(NEW_LEGENDARIES)
	return out


func _hero(class_id: StringName, index: int = 0, pos: Vector3 = Vector3.ZERO) -> Player:
	var p := Fakes.spawn_player(world, index, class_id, pos)
	p.stats.set_source(&"tough", {Stats.STAMINA: 500.0})
	p.hp = p.max_hp()
	return p


func _fake(pos: Vector3) -> Fakes.FakeEnemy:
	var e := Fakes.spawn_enemy(world, pos)
	EnemyGrid.mark_dirty()
	return e


func _corpse(pos: Vector3) -> Fakes.FakeEnemy:
	var c := _fake(pos)
	c.fake_dead = true
	return c


func _real(pos: Vector3, wave: int = 25) -> Enemy:
	var e := Enemy.create(Db.get_enemy(&"skeleton_grunt"), wave)
	world.add_child(e)
	e.global_position = pos
	EnemyGrid.mark_dirty()
	return e


## The hand-made item [param id] as a wave-10 loot drop for [param class_id], without the random
## enchants a Legendary is topped up with (they would add procs of their own).
func _item(id: StringName, class_id: StringName) -> ItemInstance:
	var item := ItemGenerator.from_unique(Db.get_unique(id), 10, true, RunState.rng, Db.get_class_data(class_id))
	item.enchants.clear()
	return item


## Equips [param id] on [param p] and returns its live proc, forced to fire on every qualifying
## event (PPM / chance / internal cooldown out of the way; "every" counters keep counting).
func _wear(p: Player, id: StringName, equip_slot: int = -1) -> ProcSystem.Proc:
	check(p.equipment.equip(_item(id, p.class_data.id), equip_slot), "%s worn by the %s" % [id, p.class_data.id])
	for proc in p.procs.procs:
		if proc.id == id:
			proc.icd = 0.0
			if proc.ppm > 0.0:
				proc.ppm = 100000.0
			if proc.every == 0 and proc.trigger != ProcSystem.TRIGGER_PERIODIC:
				proc.chance = 100.0
			return proc
	check(false, "%s is an active proc" % id)
	return null


## The damage a proc of [param school] with base [param base] deals to [param e] (power, school %,
## the hero's outgoing multipliers).
func _proc_damage(p: Player, e: Enemy, base: float, school: StringName, source: StringName = &"proc") -> float:
	return CombatMath.proc_damage(base, school, p.stats) * p.outgoing_damage_mult(e, school, source)


static func _sum(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total


static func _fmt(v: float) -> String:
	return str(int(roundf(v))) if absf(v - roundf(v)) < 0.0001 else "%.1f" % v


## Whether [param text] contains the number [param token] as a whole number (not inside another).
static func _has_number(text: String, token: String) -> bool:
	var re := RegEx.new()
	re.compile("(?<![0-9.])%s(?![0-9]|\\.[0-9])" % token.replace(".", "\\."))
	return re.search(text) != null


# --- Content ------------------------------------------------------------------------------

func test_counts_ids_and_names() -> void:
	check_eq(NEW_TRINKETS.size(), 20, "20 new trinkets listed")
	check_eq(NEW_LEGENDARIES.size(), 17, "17 new Legendaries listed")
	var names := {}
	for id in Db.uniques:
		var d: UniqueItemData = Db.uniques[id]
		check(not names.has(d.display_name), "%s: a unique display name" % id)
		names[d.display_name] = id
	for id in Db.artifacts:
		check(not names.has(Db.artifacts[id].display_name), "%s: not a hand-made name" % id)
	var forged := Forge.legendaries()
	for weapon_id in forged:
		check(not names.has(forged[weapon_id].display_name), "Forge Legendary %s: not a hand-made name" % forged[weapon_id].display_name)
	var trinkets := 0
	var legendaries := 0
	for id in Db.uniques:
		var d: UniqueItemData = Db.uniques[id]
		if d.set_id != &"" or d.class_restriction != &"":
			continue
		if d.rarity == Items.Rarity.LEGENDARY:
			legendaries += 1
		elif ItemGenerator.unique_slot(d) == Items.SlotType.TRINKET:
			trinkets += 1
	check_eq(trinkets, 30, "30 trinkets")
	check_eq(legendaries, 25, "25 Legendaries")
	for id in OLD_TRINKETS + OLD_LEGENDARIES:
		check(Db.uniques.has(id), "%s is still there" % id)
	for id in _all_new():
		check(Db.uniques.has(id), "%s loads" % id)
		check_eq(Db.get_unique(id).id, id, "%s: id matches" % id)


func test_new_trinkets_are_valid_hand_made_trinkets() -> void:
	var rarities := {}
	var triggers := {}
	var blocks := {}
	for id in NEW_TRINKETS:
		var d := Db.get_unique(id)
		if d == null:
			continue
		check_eq(d.slot_type, Items.SlotType.TRINKET, "%s: a trinket" % id)
		check(d.weapon == null and d.armor_type == Items.NO_ARMOR, "%s: no weapon, no armor" % id)
		check(d.rarity >= Items.Rarity.UNCOMMON and d.rarity <= Items.Rarity.EPIC, "%s: Uncommon to Epic" % id)
		check(d.class_restriction == &"" and d.set_id == &"", "%s: any class, no set" % id)
		check(d.flavor != "", "%s: flavour" % id)
		check_eq(d.sources, ItemGenerator.SOURCE_IDS, "%s: every source (like the old trinkets)" % id)
		check_eq(d.min_wave, 1, "%s: from wave 1" % id)
		check(d.weight > 0.0 and not d.stats.is_empty(), "%s: weight and stats" % id)
		rarities[d.rarity] = rarities.get(d.rarity, 0) + 1
		triggers[String(d.unique_params.get("trigger", ""))] = true
		blocks[d.unique_effect] = true
		_check_effect(id, d)
	check_eq(rarities.get(Items.Rarity.UNCOMMON, 0) + rarities.get(Items.Rarity.RARE, 0) + rarities.get(Items.Rarity.EPIC, 0), 20, "20 rated")
	check(rarities.get(Items.Rarity.UNCOMMON, 0) >= 4 and rarities.get(Items.Rarity.RARE, 0) >= 8
			and rarities.get(Items.Rarity.EPIC, 0) >= 3, "a spread of rarities %s" % [rarities])
	check_eq(triggers.size(), 5, "on hit, on kill, when struck, low HP and periodic are all used")
	check(blocks.size() >= 12, "many different blocks (%d)" % blocks.size())


func test_new_legendaries_are_valid_hand_made_legendaries() -> void:
	for id in NEW_LEGENDARIES:
		var d := Db.get_unique(id)
		if d == null:
			continue
		check_eq(d.rarity, Items.Rarity.LEGENDARY, "%s: Legendary" % id)
		check(d.class_restriction == &"" and d.set_id == &"", "%s: no class restriction, no set" % id)
		check(&"shop" not in d.sources and not d.sources.is_empty(), "%s: never from the shop" % id)
		for s in d.sources:
			check(s in ItemGenerator.SOURCE_IDS, "%s: known source %s" % [id, s])
		check(d.min_wave >= 10, "%s: from wave 10" % id)
		check(d.flavor != "" and d.weight > 0.0 and not d.stats.is_empty(), "%s: flavour, weight, stats" % id)
		if d.weapon != null:
			check_eq(d.slot_type, Items.SlotType.WEAPON, "%s: weapon slot" % id)
			check_eq(d.armor_type, Items.NO_ARMOR, "%s: no armor type" % id)
		else:
			check(d.slot_type != Items.SlotType.WEAPON, "%s: needs a weapon for the weapon slot" % id)
			check_eq(d.slot_type in Items.ARMOR_SLOTS, d.armor_type != Items.NO_ARMOR, "%s: armor type only on armor slots" % id)
		if d.slot_type in [Items.SlotType.NECK, Items.SlotType.RING]:
			for stat in d.stats:
				check(stat not in [Stats.STRENGTH, Stats.AGILITY, Stats.INTELLECT, Stats.STAMINA],
						"%s: no primary stat on jewellery (GDD 5.4)" % id)
		_check_effect(id, d)


## The unique vocabulary of test_items_gen_content (_check_effect), plus the text conventions.
func _check_effect(id: StringName, d: UniqueItemData) -> void:
	var params: Dictionary = d.unique_params
	var trigger := String(params.get("trigger", ""))
	check(d.unique_effect in ProcSystem.BLOCKS and d.unique_effect not in [&"resource"], "%s: building block %s" % [id, d.unique_effect])
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
		check(String(params["school"]) in ["physical", "fire", "frost", "arcane", "holy", "shadow", "nature"], "%s: school" % id)
	var required: Dictionary = {
		&"bolt": ["damage"], &"chain": ["damage", "targets"], &"dot": ["damage", "duration"],
		&"nova": ["damage", "radius"], &"explode": ["damage", "radius"], &"extra_attack": ["count"],
		&"buff": ["stats", "duration"], &"heal": ["amount", "target"], &"drain": ["damage"],
		&"slow": ["pct", "duration"], &"stun": ["duration"], &"gold": ["amount"],
		&"shield": ["amount", "duration"], &"reflect": ["damage"],
		&"smite_heal": ["damage", "heal"], &"cheat_death": ["invulnerable"],
	}
	for key in required.get(d.unique_effect, []):
		check(params.has(key), "%s: %s needs %s" % [id, d.unique_effect, key])
	if d.unique_effect == &"buff":
		for stat in params.get("stats", {}):
			check(StringName(stat) in Stats.ALL, "%s: buff stat %s" % [id, stat])
	for stat in d.stats:
		check(stat in Stats.ALL, "%s: known stat %s" % [id, stat])
	# The proc keys the engine understands (BonusVocabulary.PROC_KEYS) – no typos.
	for key in params:
		check(String(key) in BonusVocabulary.PROC_KEYS, "%s: %s is a proc key" % [id, key])
	var starts := false
	for s in TEXT_STARTS:
		starts = starts or d.unique_text.begins_with(s)
	check(starts, "%s: the tooltip starts with its trigger phrase (%s)" % [id, d.unique_text])
	match trigger:
		"on_hit":
			check(d.unique_text.begins_with("Chance on hit: "), "%s: Chance on hit: line" % id)
		"on_kill":
			check(d.unique_text.begins_with("On kill: ") or d.unique_text.begins_with("Every "), "%s: On kill: line" % id)
		"when_struck":
			check(d.unique_text.begins_with("When struck: "), "%s: When struck: line" % id)
		"periodic":
			check(d.unique_text.begins_with("Every "), "%s: Every N sec: line" % id)
		"low_hp":
			check(d.unique_text.begins_with("Equip: "), "%s: Equip: line (low HP)" % id)
	for word in BANNED:
		check(word not in (d.display_name + " " + d.flavor + " " + d.unique_text).to_lower(), "%s: no trademark '%s'" % [id, word])


func test_tooltips_show_the_numbers_of_the_params() -> void:
	for id in _all_new():
		var d := Db.get_unique(id)
		if d == null:
			continue
		var params: Dictionary = d.unique_params
		var text := d.unique_text
		for key in TEXT_KEYS:
			if not params.has(key):
				continue
			var v := float(params[key])
			if (key == "damage" and params.has("hit_pct")) or (key in ["amount", "slow", "stun", "dot", "spread"] and v == 0.0):
				continue
			if key == "stacks" and v <= 1.0:
				continue
			if key == "chance" and (v >= 100.0 or params.has("every")):
				continue
			check(_has_number(text, _fmt(v)), "%s: the tooltip shows %s = %s (%s)" % [id, key, _fmt(v), text])
		if params.has("every"):
			check(text.contains("%dth" % int(params["every"])), "%s: every %dth" % [id, int(params["every"])])
		var shown: Dictionary = params.get("stats", {})
		for stat in shown:
			check(_has_number(text, _fmt(float(shown[stat]))), "%s: the tooltip shows %s %s" % [id, stat, shown[stat]])


func test_legendaries_cover_every_slot_type_and_every_class() -> void:
	var per_slot := {}
	for id in Db.uniques:
		var d: UniqueItemData = Db.uniques[id]
		if d.rarity == Items.Rarity.LEGENDARY and d.set_id == &"" and d.class_restriction == &"":
			var slot := ItemGenerator.unique_slot(d)
			per_slot[slot] = per_slot.get(slot, 0) + 1
	for slot in Items.SlotType.values():
		check(per_slot.get(slot, 0) >= 1, "a Legendary for slot %s" % Items.SLOT_NAMES[slot])
	# The five slot types that had none before M6b each got one.
	for slot in [Items.SlotType.NECK, Items.SlotType.CHEST, Items.SlotType.WRIST, Items.SlotType.LEGS, Items.SlotType.TRINKET]:
		var got := false
		for id in NEW_LEGENDARIES:
			got = got or ItemGenerator.unique_slot(Db.get_unique(id)) == slot
		check(got, "a new Legendary for %s" % Items.SLOT_NAMES[slot])
	# Class flavour: each class can wear a good share of them and finds its primary stat on several.
	for class_id in Db.class_ids:
		var c := Db.get_class_data(class_id)
		var usable := 0
		var on_theme := 0
		for id in NEW_LEGENDARIES:
			var d := Db.get_unique(id)
			if ItemGenerator.unique_usable_by(d, c):
				usable += 1
				if d.stats.has(c.primary_stat):
					on_theme += 1
		check(usable >= 8, "%s can use %d of the new Legendaries" % [class_id, usable])
		check(on_theme >= 3, "%s finds its primary stat (%s) on %d usable new Legendaries" % [class_id, c.primary_stat, on_theme])
		var all_usable := 0
		for id in Db.uniques:
			var d: UniqueItemData = Db.uniques[id]
			if d.rarity == Items.Rarity.LEGENDARY and ItemGenerator.unique_usable_by(d, c):
				all_usable += 1
		check(all_usable >= 12, "%s can use %d of the 25 Legendaries" % [class_id, all_usable])


func test_generated_new_items_have_scaled_stats_and_enchants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for id in _all_new():
		var d := Db.get_unique(id)
		for wave in [10, 17]:
			var item := ItemGenerator.from_unique(d, wave, true, rng)
			check_eq(item.display_name, d.display_name, "%s keeps its name" % id)
			check_eq(item.unique_effect, d.unique_effect, "%s: effect" % id)
			check_eq(item.unique_text, d.unique_text, "%s: text" % id)
			check_eq(item.rarity, d.rarity, "%s: rarity" % id)
			for stat in d.stats:
				check(item.stats.get(stat, 0.0) >= d.stats[stat], "%s: %s scaled up by the tier / loot bonus" % [id, stat])
			if d.rarity == Items.Rarity.LEGENDARY:
				check_eq(item.enchants.size(), ItemGenerator.LEGENDARY_ENCHANTS, "%s: topped up to two enchants" % id)
				for roll in item.enchants:
					check(roll.rank <= 2, "%s: enchants start at rank III at most" % id)
				check(not item.unique_text.is_empty() and item.buy_price > 0, "%s: text and price" % id)


func test_new_items_drop_from_the_generator() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	# Legendaries: every Legendary roll is a hand-made one; the loot sources, never the shop.
	var seen := {}
	for i in 1500:
		var source: ItemGenerator.Source = [ItemGenerator.Source.LOOT, ItemGenerator.Source.ELITE,
				ItemGenerator.Source.GOBLIN, ItemGenerator.Source.BOSS][i % 4]
		var item := ItemGenerator.generate(source, 10 + (i % 16), rng, {&"rarity": Items.Rarity.LEGENDARY})
		check(item != null and item.unique, "a Legendary roll is hand-made")
		if item != null:
			seen[item.source_id] = true
	for id in NEW_LEGENDARIES:
		check(seen.has(id), "%s dropped" % id)
	for id in OLD_LEGENDARIES:
		check(seen.has(id), "%s still drops" % id)
	check_eq(seen.size(), 25, "25 different Legendaries")
	for i in 100:
		var shop_item := ItemGenerator.generate(ItemGenerator.Source.SHOP, 12, rng, {&"rarity": Items.Rarity.LEGENDARY})
		check(not (shop_item.unique and shop_item.rarity == Items.Rarity.LEGENDARY), "the shop offers no Legendary")
	# Trinkets: every trinket slot roll is a hand-made trinket; shop and loot offer all 30.
	var trinkets := {}
	for i in 2400:
		var source: ItemGenerator.Source = ItemGenerator.Source.SHOP if i % 2 == 0 else ItemGenerator.Source.LOOT
		var item := ItemGenerator.generate(source, 1 + (i % 25), rng, {&"slot_type": Items.SlotType.TRINKET,
				&"rarity": [Items.Rarity.UNCOMMON, Items.Rarity.RARE, Items.Rarity.EPIC][i % 3]})
		if item != null and item.slot_type == Items.SlotType.TRINKET:
			trinkets[item.source_id] = true
	for id in NEW_TRINKETS:
		check(trinkets.has(id), "%s was offered" % id)
	for id in OLD_TRINKETS:
		check(trinkets.has(id), "%s is still offered" % id)


# --- On-hit trinkets and Legendaries -------------------------------------------------------------

func test_bottled_thundercloud_chains_three_enemies() -> void:
	var p := _hero(&"warrior")
	var proc := _wear(p, &"bottled_thundercloud")
	check_eq(proc.trigger, ProcSystem.TRIGGER_ON_HIT, "on hit")
	var a := _fake(Vector3(2, 0, 0))
	var b := _fake(Vector3(5, 0, 0))
	var c := _fake(Vector3(8, 0, 0))
	var d := _fake(Vector3(11, 0, 0))
	p.procs.on_hit(a, 10.0, p.main_hand, false)
	check_eq([a.fake_hits(), b.fake_hits(), c.fake_hits(), d.fake_hits()], [1, 1, 1, 0], "three targets, each once")
	check_near(b.fake_damage_log[0], _proc_damage(p, b, 13.0, &"nature"), 0.001, "13 Nature damage")


func test_wasp_nest_charm_stings_and_stacks_three_times() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"wasp_nest_charm")
	var e := _fake(Vector3(2, 0, 0))
	for i in 5:
		p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_eq(p.procs.dot_stacks(e, &"wasp_nest_charm"), 3, "three stacks at most")
	for i in 260:
		p.procs._physics_process(DT)
	var per_stack := CombatMath.proc_damage(16.0, &"nature", p.stats) * p.outgoing_damage_mult(e, &"nature", &"dot")
	check_near(_sum(e.fake_damage_log), 3.0 * per_stack, 0.05, "16 Nature damage per stack over 4 sec")
	check_eq(p.procs.dot_count(), 0, "burned out")


func test_jar_of_leeches_drains_and_heals() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"jar_of_leeches")
	var e := _fake(Vector3(2, 0, 0))
	p.hp = 100.0
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	var dealt := _proc_damage(p, e, 7.0, &"shadow")
	check_near(e.fake_damage_log[0], dealt, 0.001, "7 Shadow damage")
	check_near(p.hp, 100.0 + dealt, 0.001, "healed for the same")


func test_bell_of_stillness_stuns() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"bell_of_stillness")
	var e := _real(Vector3(2, 0, 0))
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	check(e.is_stunned(), "stunned")


func test_warbeat_drum_stacks_haste_to_five_times() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"warbeat_drum")
	var e := _fake(Vector3(2, 0, 0))
	var base := p.stats.get_stat(Stats.HASTE)
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_eq(p.stats.get_stat(Stats.HASTE) - base, 4.0, "+4% Haste")
	for i in 9:
		p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_eq(p.stats.get_stat(Stats.HASTE) - base, 20.0, "five stacks at most")
	p.procs._physics_process(5.9)
	check_eq(p.stats.get_stat(Stats.HASTE) - base, 20.0, "still there at 5.9 s")
	p.procs._physics_process(0.3)
	check_eq(p.stats.get_stat(Stats.HASTE) - base, 0.0, "gone after 6 sec")


func test_votive_candle_smites_and_heals_an_ally() -> void:
	var p := _hero(&"paladin")
	var ally := _hero(&"warrior", 1, Vector3(3, 0, 0))
	Enemy.invalidate_player_cache()
	ally.hp = 50.0
	_wear(p, &"votive_candle")
	var e := _fake(Vector3(2, 0, 0))
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_near(e.fake_damage_log[0], _proc_damage(p, e, 12.0, &"holy"), 0.001, "12 Holy damage")
	check_near(ally.hp, 55.0, 0.001, "the wounded ally got 5")


func test_tearjerker_rends_and_spreads_its_wounds() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"tearjerker")
	check(p.main_hand.id == &"two_hand_axe", "the Legendary is a two-hand axe")
	var e := _fake(Vector3(2, 0, 0))
	var neighbour := _fake(Vector3(4, 0, 0))
	var far := _fake(Vector3(12, 0, 0))
	for i in 4:
		p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_eq(p.procs.dot_stacks(e, &"tearjerker"), 3, "three stacks at most")
	e.fake_dead = true
	p.procs._physics_process(DT)
	check_eq(p.procs.dot_stacks(neighbour, &"tearjerker"), 1, "the wounds spread to the enemy within 3 m")
	check_eq(p.procs.dot_stacks(far, &"tearjerker"), 0, "not to the far one")
	e.fake_dead = false
	var fresh := _fake(Vector3(2, 0, 3))
	p.procs.on_hit(fresh, 10.0, p.main_hand, false)
	for i in 260:
		p.procs._physics_process(DT)
	var one_stack := CombatMath.proc_damage(36.0, &"physical", p.stats) * p.outgoing_damage_mult(fresh, &"physical", &"dot")
	check_near(_sum(fresh.fake_damage_log), one_stack, 0.05, "36 Physical damage over 4 sec")


func test_bracers_of_the_hidden_blade_strike_for_a_share_of_the_hit() -> void:
	var p := _hero(&"rogue")
	var proc := _wear(p, &"bracers_of_the_hidden_blade")
	check_eq(proc.hit_pct, 120.0, "120% of the hit")
	var e := _fake(Vector3(2, 0, 0))
	p.procs.on_hit(e, 50.0, p.main_hand, false)
	check_near(e.fake_damage_log[0], 60.0 * p.outgoing_damage_mult(e, &"physical", &"proc"), 0.001, "120% of a 50 hit")
	p.procs.on_hit(e, 200.0, p.main_hand, false)
	check_near(e.fake_damage_log[1], 240.0 * p.outgoing_damage_mult(e, &"physical", &"proc"), 0.001, "it scales with the hit")


func test_leggings_of_the_brimming_well_stack_spell_power_and_arcane_damage() -> void:
	var p := _hero(&"mage")
	_wear(p, &"leggings_of_the_brimming_well")
	var e := _fake(Vector3(2, 0, 0))
	var sp := p.stats.get_raw(Stats.SPELL_POWER)
	var arcane := p.stats.get_raw(Stats.ARCANE_DAMAGE)
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_eq(p.stats.get_raw(Stats.SPELL_POWER) - sp, 2.0, "+2 Spell Power")
	check_eq(p.stats.get_raw(Stats.ARCANE_DAMAGE) - arcane, 3.0, "+3% Arcane Damage")
	for i in 9:
		p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_eq(p.stats.get_raw(Stats.SPELL_POWER) - sp, 10.0, "five stacks at most")
	check_eq(p.stats.get_raw(Stats.ARCANE_DAMAGE) - arcane, 15.0, "15% Arcane Damage")
	p.procs._physics_process(6.1)
	check_eq(p.stats.get_raw(Stats.SPELL_POWER) - sp, 0.0, "gone after 6 sec")


func test_staff_of_the_deep_winter_freezes_its_target() -> void:
	var p := _hero(&"mage")
	_wear(p, &"staff_of_the_deep_winter")
	check(p.main_hand.id == &"staff", "the Legendary is a staff")
	var e := _real(Vector3(3, 0, 0))
	var hp := e.hp
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_near(hp - e.hp, _proc_damage(p, e, 24.0, &"frost"), 0.001, "24 Frost damage")
	check(e.is_stunned(), "frozen in place")


func test_grimoire_of_seeded_doom_bursts_and_rots() -> void:
	var p := _hero(&"mage")
	_wear(p, &"grimoire_of_seeded_doom")
	check(p.off_hand != null and p.off_hand.id == &"tome", "worn in the off hand")
	var e := _fake(Vector3(4, 0, 0))
	var near := _fake(Vector3(6.5, 0, 0))
	var far := _fake(Vector3(10, 0, 0))
	p.procs.on_hit(e, 10.0, p.main_hand, false)
	check_near(e.fake_damage_log[0], _proc_damage(p, e, 26.0, &"shadow"), 0.001, "26 Shadow damage to the target")
	check_near(near.fake_damage_log[0], _proc_damage(p, near, 26.0, &"shadow"), 0.001, "and to the enemy within 3 m")
	check_eq(far.fake_hits(), 0, "not beyond 3 m")
	check_eq(p.procs.dot_count(), 2, "both rot")
	for i in 260:
		p.procs._physics_process(DT)
	var rot := CombatMath.proc_damage(20.0, &"shadow", p.stats) * p.outgoing_damage_mult(e, &"shadow", &"dot")
	check_near(_sum(e.fake_damage_log) - e.fake_damage_log[0], rot, 0.05, "20 more over 4 sec")


# --- On-kill trinkets and Legendaries ------------------------------------------------------------

func test_carrion_talon_restores_max_hp() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"carrion_talon")
	p.hp = 100.0
	p.procs.on_kill(_corpse(Vector3(3, 0, 0)))
	check_near(p.hp, 100.0 + p.max_hp() * 0.06, 0.001, "6% of Max HP")


func test_bone_chime_bursts_and_slows() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"bone_chime")
	var corpse := _corpse(Vector3(5, 0, 0))
	var near := _real(Vector3(7, 0, 0))
	var far := _real(Vector3(9, 0, 0))
	var hp := near.hp
	p.procs.on_kill(corpse)
	check_near(hp - near.hp, _proc_damage(p, near, 16.0, &"physical"), 0.001, "16 Physical damage")
	check(near.is_slowed() and near.slow_pct == 40.0, "slowed by 40%")
	check(far.hp == far.max_hp, "outside 2.5 m: untouched")


func test_soul_lantern_shields_on_a_kill() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"soul_lantern")
	p.procs.on_kill(_corpse(Vector3(3, 0, 0)))
	check_near(p.procs.shield_hp, p.max_hp() * 0.08, 0.001, "8% of Max HP")
	check_near(p.procs.shield_left, 6.0, 0.001, "for 6 sec")


func test_notched_tally_stick_stacks_damage_per_kill() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"notched_tally_stick")
	var before := p.stats.damage_mult()
	var corpse := _corpse(Vector3(3, 0, 0))
	p.procs.on_kill(corpse)
	check_near(p.stats.damage_mult() - before, 0.01, 0.0001, "+1% Damage")
	for i in 12:
		p.procs.on_kill(corpse)
	check_near(p.stats.damage_mult() - before, 0.08, 0.0001, "eight stacks at most")
	p.procs._physics_process(8.1)
	check_near(p.stats.damage_mult() - before, 0.0, 0.0001, "gone after 8 sec")


func test_hood_of_the_quiet_knife_grants_crit_and_speed() -> void:
	var p := _hero(&"rogue")
	_wear(p, &"hood_of_the_quiet_knife")
	var crit := p.stats.get_stat(Stats.CRIT)
	var speed := p.stats.get_stat(Stats.SPEED)
	p.procs.on_kill(_corpse(Vector3(3, 0, 0)))
	check_eq(p.stats.get_stat(Stats.CRIT) - crit, 20.0, "+20% Critical Strike")
	check_eq(p.stats.get_stat(Stats.SPEED) - speed, 15.0, "+15% Speed")
	p.procs._physics_process(5.1)
	check_eq(p.stats.get_stat(Stats.CRIT) - crit, 0.0, "gone after 5 sec")


func test_breeches_of_the_light_fingers_pick_pockets() -> void:
	var p := _hero(&"rogue")
	_wear(p, &"breeches_of_the_light_fingers")
	var gold := RunState.gold
	p.procs.on_kill(_corpse(Vector3(3, 0, 0)))
	check_eq(RunState.gold - gold, 3, "3 gold")


func test_ring_of_the_mischievous_imp_throws_fire_every_fourth_kill() -> void:
	var p := _hero(&"warlock")
	var proc := _wear(p, &"ring_of_the_mischievous_imp")
	check_eq(proc.every, 4, "every 4th kill")
	var a := _fake(Vector3(3, 0, 0))
	var b := _fake(Vector3(6, 0, 0))
	var c := _fake(Vector3(9, 0, 0))
	var d := _fake(Vector3(12, 0, 0))
	var corpse := _corpse(Vector3(2, 0, 0))
	for i in 3:
		p.procs.on_kill(corpse)
	check_eq(p.procs.fire_count(&"ring_of_the_mischievous_imp"), 0, "nothing on kills 1 to 3")
	check_eq(a.fake_hits() + b.fake_hits() + c.fake_hits(), 0, "no damage yet")
	p.procs.on_kill(corpse)
	check_eq(p.procs.fire_count(&"ring_of_the_mischievous_imp"), 1, "the 4th kill fires")
	check_eq([a.fake_hits(), b.fake_hits(), c.fake_hits(), d.fake_hits()], [1, 1, 1, 0], "three enemies, each once")
	check_near(a.fake_damage_log[0], _proc_damage(p, a, 20.0, &"fire"), 0.001, "20 Fire damage")
	for i in 3:
		p.procs.on_kill(corpse)
	check_eq(p.procs.fire_count(&"ring_of_the_mischievous_imp"), 1, "the count starts over")
	p.procs.on_kill(corpse)
	check_eq(p.procs.fire_count(&"ring_of_the_mischievous_imp"), 2, "and fires on the 8th")


# --- When-struck trinkets and Legendaries --------------------------------------------------------

func test_porcupine_quill_lashes_back_and_slows() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"porcupine_quill")
	var e := _real(Vector3(1, 0, 0))
	var hp := e.hp
	p.procs.on_struck(e, 2.0)
	check_near(hp - e.hp, _proc_damage(p, e, 8.0, &"physical"), 0.001, "8 Physical damage")
	check(e.is_slowed() and e.slow_pct == 30.0, "slowed by 30%")


func test_beetle_carapace_grants_armor() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"beetle_carapace")
	var armor := p.stats.get_stat(Stats.ARMOR)
	p.procs.on_struck(_fake(Vector3(1, 0, 0)), 2.0)
	check_eq(p.stats.get_stat(Stats.ARMOR) - armor, 8.0, "+8 Armor")
	p.procs._physics_process(5.1)
	check_eq(p.stats.get_stat(Stats.ARMOR) - armor, 0.0, "gone after 5 sec")


func test_basilisk_eye_stuns_the_attacker() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"basilisk_eye")
	var e := _real(Vector3(1, 0, 0))
	p.procs.on_struck(e, 2.0)
	check(e.is_stunned(), "petrified")


func test_pauldrons_of_the_radiant_bulwark_raise_a_ward() -> void:
	var p := _hero(&"paladin")
	_wear(p, &"pauldrons_of_the_radiant_bulwark")
	p.procs.on_struck(_fake(Vector3(1, 0, 0)), 2.0)
	check_near(p.procs.shield_hp, p.max_hp() * 0.15, 0.001, "15% of Max HP")
	check_near(p.procs.shield_left, 5.0, 0.001, "for 5 sec")


func test_breastplate_of_unbroken_anger_stacks_damage_when_struck() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"breastplate_of_unbroken_anger")
	var before := p.stats.damage_mult()
	var e := _fake(Vector3(1, 0, 0))
	p.procs.on_struck(e, 2.0)
	check_near(p.stats.damage_mult() - before, 0.04, 0.0001, "+4% Damage")
	for i in 9:
		p.procs.on_struck(e, 2.0)
	check_near(p.stats.damage_mult() - before, 0.24, 0.0001, "six stacks at most")
	p.procs._physics_process(8.1)
	check_near(p.stats.damage_mult() - before, 0.0, 0.0001, "gone after 8 sec")


func test_robe_of_the_hollow_pact_drains_the_attacker() -> void:
	var p := _hero(&"warlock")
	_wear(p, &"robe_of_the_hollow_pact")
	var e := _fake(Vector3(1, 0, 0))
	p.hp = 100.0
	p.procs.on_struck(e, 2.0)
	var dealt := _proc_damage(p, e, 24.0, &"shadow")
	check_near(e.fake_damage_log[0], dealt, 0.001, "24 Shadow damage")
	check_near(p.hp, 100.0 + dealt, 0.001, "healed for the same")


func test_struck_uniques_fire_through_player_take_damage() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"beetle_carapace")
	var armor := p.stats.get_stat(Stats.ARMOR)
	var e := _real(Vector3(1, 0, 0))
	p.take_damage(2.0, CombatMath.KIND_MELEE, e)
	check_eq(p.procs.fire_count(&"beetle_carapace"), 1, "a real hit triggers it")
	check_eq(p.stats.get_stat(Stats.ARMOR) - armor, 8.0, "+8 Armor")


# --- Low-HP trinkets and Legendaries ---------------------------------------------------------------

func test_ashfall_feather_heals_once_per_wave_below_thirty_percent() -> void:
	var p := _hero(&"warrior")
	var proc := _wear(p, &"ashfall_feather")
	check_eq(proc.trigger, ProcSystem.TRIGGER_LOW_HP, "low HP")
	var e := _fake(Vector3(1, 0, 0))
	p.hp = p.max_hp() * 0.4
	p.procs.on_struck(e, 1.0)
	check_eq(p.procs.fire_count(&"ashfall_feather"), 0, "not below 30% yet")
	p.hp = p.max_hp() * 0.2
	p.procs.on_struck(e, 1.0)
	check_near(p.hp, p.max_hp() * 0.45, 0.001, "healed 25% of Max HP")
	# Once per wave: back up above the threshold and down again does nothing.
	p.hp = p.max_hp() * 0.9
	p.procs._physics_process(DT)
	p.hp = p.max_hp() * 0.2
	p.procs.on_struck(e, 1.0)
	check_eq(p.procs.fire_count(&"ashfall_feather"), 1, "not twice in one wave")
	p.procs.begin_wave()
	p.hp = p.max_hp() * 0.2
	p.procs.on_struck(e, 1.0)
	check_eq(p.procs.fire_count(&"ashfall_feather"), 2, "ready again next wave")


func test_alarm_whistle_blasts_and_stuns_below_thirty_five_percent() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"alarm_whistle")
	var near := _real(Vector3(3.2, 0, 0))
	var far := _real(Vector3(0, 0, 6.0))
	p.hp = p.max_hp() * 0.3
	var hp := near.hp
	p.procs.on_struck(near, 1.0)
	check_near(hp - near.hp, _proc_damage(p, near, 25.0, &"physical"), 0.001, "25 damage within 4 m")
	check(near.is_stunned(), "stunned")
	check(far.hp == far.max_hp and not far.is_stunned(), "the far one is untouched")


func test_smoke_pouch_grants_speed_and_dodge_below_forty_percent() -> void:
	var p := _hero(&"rogue")
	_wear(p, &"smoke_pouch")
	var speed := p.stats.get_stat(Stats.SPEED)
	var dodge := p.stats.get_stat(Stats.DODGE)
	p.hp = p.max_hp() * 0.3
	p.procs.on_struck(_fake(Vector3(1, 0, 0)), 1.0)
	check_eq(p.stats.get_stat(Stats.SPEED) - speed, 20.0, "+20% Speed")
	check_eq(p.stats.get_stat(Stats.DODGE) - dodge, 15.0, "+15% Dodge")
	p.procs._physics_process(4.1)
	check_eq(p.stats.get_stat(Stats.SPEED) - speed, 0.0, "gone after 4 sec")


func test_girdle_of_the_last_roar_roars_once_per_wave() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"girdle_of_the_last_roar")
	var dmg := p.stats.damage_mult()
	var armor := p.stats.get_stat(Stats.ARMOR)
	p.hp = p.max_hp() * 0.35
	p.procs.on_struck(_fake(Vector3(1, 0, 0)), 1.0)
	check_near(p.stats.damage_mult() - dmg, 0.25, 0.0001, "+25% Damage")
	check_eq(p.stats.get_stat(Stats.ARMOR) - armor, 10.0, "+10 Armor")
	p.procs._physics_process(8.1)
	check_near(p.stats.damage_mult() - dmg, 0.0, 0.0001, "gone after 8 sec")
	p.hp = p.max_hp() * 0.9
	p.procs._physics_process(DT)
	p.hp = p.max_hp() * 0.3
	p.procs.on_struck(_fake(Vector3(1, 0, 0)), 1.0)
	check_eq(p.procs.fire_count(&"girdle_of_the_last_roar"), 1, "once per wave")


# --- Periodic trinkets and Legendaries ---------------------------------------------------------------

func test_mote_lantern_strikes_the_nearest_enemy_every_six_seconds() -> void:
	var p := _hero(&"mage")
	var proc := _wear(p, &"mote_lantern")
	check_eq(proc.trigger, ProcSystem.TRIGGER_PERIODIC, "periodic")
	p.procs._physics_process(6.1)
	check_eq(p.procs.fire_count(&"mote_lantern"), 0, "no enemy, no mote")
	var near := _fake(Vector3(3, 0, 0))
	var far := _fake(Vector3(8, 0, 0))
	p.procs._physics_process(0.3)
	check_eq(p.procs.fire_count(&"mote_lantern"), 1, "it strikes as soon as an enemy is near")
	check_eq([near.fake_hits(), far.fake_hits()], [1, 0], "the nearest one")
	check_near(near.fake_damage_log[0], _proc_damage(p, near, 22.0, &"holy"), 0.001, "22 Holy damage")
	p.procs._physics_process(5.0)
	check_eq(p.procs.fire_count(&"mote_lantern"), 1, "not before the next 6 sec")
	p.procs._physics_process(1.1)
	check_eq(p.procs.fire_count(&"mote_lantern"), 2, "again after 6 sec")


func test_singing_bowl_raises_a_ward_every_fifteen_seconds() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"singing_bowl")
	p.procs._physics_process(14.5)
	check_near(p.procs.shield_hp, 0.0, 0.0001, "not yet")
	p.procs._physics_process(0.6)
	check_near(p.procs.shield_hp, p.max_hp() * 0.08, 0.001, "8% of Max HP")
	check_near(p.procs.shield_left, 8.0 - 0.6, 0.001, "for 8 sec (0.6 s of it already ticked)")


func test_prospectors_pebble_finds_gold() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"prospectors_pebble")
	var gold := RunState.gold
	p.procs._physics_process(14.9)
	check_eq(RunState.gold, gold, "not yet")
	p.procs._physics_process(0.3)
	check_eq(RunState.gold - gold, 2, "2 gold")
	p.procs._physics_process(15.1)
	check_eq(RunState.gold - gold, 4, "2 more every 15 sec")


func test_wayward_compass_tears_open_a_rift_around_the_wearer() -> void:
	var p := _hero(&"mage")
	_wear(p, &"wayward_compass")
	var target := _fake(Vector3(2, 0, 0))
	var near := _fake(Vector3(0, 0, 3.2))
	var far := _fake(Vector3(7, 0, 0))
	p.procs._physics_process(8.9)
	check_eq(target.fake_hits() + near.fake_hits() + far.fake_hits(), 0, "not before 9 sec")
	p.procs._physics_process(0.3)
	check_eq([target.fake_hits(), near.fake_hits(), far.fake_hits()], [1, 1, 0], "every enemy within 3 m, not the far one")
	check_near(target.fake_damage_log[0], _proc_damage(p, target, 30.0, &"arcane"), 0.001, "30 Arcane damage")


func test_greathelm_of_the_gilded_oath_mends_the_most_wounded_ally() -> void:
	var p := _hero(&"paladin")
	var ally := _hero(&"warrior", 1, Vector3(3, 0, 0))
	Enemy.invalidate_player_cache()
	ally.hp = 100.0
	p.hp = p.max_hp() - 5.0
	_wear(p, &"greathelm_of_the_gilded_oath")
	p.procs._physics_process(7.9)
	check_near(ally.hp, 100.0, 0.0001, "not yet")
	p.procs._physics_process(0.3)
	check_near(ally.hp, 100.0 + ally.max_hp() * 0.12, 0.001, "12% of the ally's Max HP")


func test_sabatons_of_the_long_march_hallow_the_ground() -> void:
	var p := _hero(&"warrior")
	_wear(p, &"sabatons_of_the_long_march")
	var near := _real(Vector3(2.5, 0, 0))
	var far := _real(Vector3(0, 0, 6.0))
	var hp := near.hp
	p.procs._physics_process(6.1)
	check_near(hp - near.hp, _proc_damage(p, near, 18.0, &"holy"), 0.001, "18 Holy damage within 3 m")
	check(near.is_slowed() and near.slow_pct == 40.0, "slowed by 40%")
	check(far.hp == far.max_hp, "the far one is untouched")


func test_vial_of_distilled_adrenaline_surges_every_twenty_five_seconds() -> void:
	var p := _hero(&"rogue")
	_wear(p, &"vial_of_distilled_adrenaline")
	var haste := p.stats.get_stat(Stats.HASTE)
	var dmg := p.stats.damage_mult()
	p.procs._physics_process(24.9)
	check_eq(p.stats.get_stat(Stats.HASTE), haste, "not yet")
	p.procs._physics_process(0.3)
	check_eq(p.stats.get_stat(Stats.HASTE) - haste, 35.0, "+35% Haste")
	check_near(p.stats.damage_mult() - dmg, 0.15, 0.0001, "+15% Damage")
	p.procs._physics_process(8.1)
	check_eq(p.stats.get_stat(Stats.HASTE), haste, "gone after 8 sec")


func test_amulet_of_unspent_wishes_leaps_between_four_enemies() -> void:
	var p := _hero(&"mage")
	_wear(p, &"amulet_of_unspent_wishes")
	var enemies: Array[Fakes.FakeEnemy] = []
	for i in 5:
		enemies.append(_fake(Vector3(2.0 + 3.0 * i, 0, 0)))
	p.procs._physics_process(6.1)
	var hits: Array[int] = []
	for e in enemies:
		hits.append(e.fake_hits())
	check_eq(hits, [1, 1, 1, 1, 0] as Array[int], "four enemies, each once")
	check_near(enemies[1].fake_damage_log[0], _proc_damage(p, enemies[1], 20.0, &"arcane"), 0.001, "20 Arcane damage")


func test_gloves_of_the_patient_rot_sow_rot_that_spreads() -> void:
	var p := _hero(&"warlock")
	_wear(p, &"gloves_of_the_patient_rot")
	var e := _fake(Vector3(3, 0, 0))
	var neighbour := _fake(Vector3(5.5, 0, 0))
	Fakes.step(p.procs, 5.9)
	check_eq(p.procs.dot_stacks(e, &"gloves_of_the_patient_rot"), 0, "not before 6 sec")
	Fakes.step(p.procs, 0.2)
	check_eq(p.procs.dot_stacks(e, &"gloves_of_the_patient_rot"), 1, "the nearest enemy rots")
	check_eq(p.procs.dot_stacks(neighbour, &"gloves_of_the_patient_rot"), 0, "only that one")
	Fakes.step(p.procs, 1.0)
	e.fake_dead = true
	p.procs._physics_process(DT)
	check_eq(p.procs.dot_stacks(neighbour, &"gloves_of_the_patient_rot"), 1, "it spreads when its host dies")
	# Left alone it rots for the full 40 over 5 sec.
	var q := _hero(&"warlock", 1, Vector3(0, 0, 30))
	_wear(q, &"gloves_of_the_patient_rot")
	var lone := _fake(Vector3(3, 0, 30))
	Fakes.step(q.procs, 6.1)
	for i in 400:
		q.procs._physics_process(DT)
		if q.procs.dot_stacks(lone, &"gloves_of_the_patient_rot") == 0:
			break
	var expected := CombatMath.proc_damage(40.0, &"shadow", q.stats) * q.outgoing_damage_mult(lone, &"shadow", &"dot")
	check_near(_sum(lone.fake_damage_log), expected, 0.5, "40 Shadow damage over 5 sec")


# --- Real trigger paths -------------------------------------------------------------------------

func test_new_uniques_fire_at_their_documented_rates() -> void:
	# On hit: PPM x weapon cooldown / 60 per attack (Bell of Stillness: 2 PPM, 6 s ICD).
	var p := _hero(&"warrior")
	p.equipment.equip(_item(&"bell_of_stillness", &"warrior"))
	var e := _fake(Vector3(30, 0, 0))
	var axe := Db.get_weapon(&"two_hand_axe")  # 1.5 s -> 5% per hit
	for i in 4000:
		p.procs._physics_process(10.0)
		p.procs.on_hit(e, 5.0, axe, false)
	var n := p.procs.fire_count(&"bell_of_stillness")
	check(n > 140 and n < 260, "~5%% of 4000 axe hits (%d)" % n)
	# On kill: the listed percentage (Carrion Talon: 12%).
	var q := _hero(&"warrior", 1, Vector3(0, 0, 20))
	q.equipment.equip(_item(&"carrion_talon", &"warrior"))
	var corpse := _corpse(Vector3(3, 0, 20))
	for i in 3000:
		q.procs._physics_process(10.0)
		q.procs.on_kill(corpse)
	var k := q.procs.fire_count(&"carrion_talon")
	check(k > 290 and k < 430, "~12%% of 3000 kills (%d)" % k)
