extends TestCase
## Weapon forging (GDD 4.1, Forge): pairing rules (base, rarity, hand-made, Legendary /
## Artifact), partner order, block reasons and the "→ Rare" detail, placement (backpack,
## equipped, dual wield, never unarmed), the result (rarity, wave, Looted, reroll determinism),
## the weapon types' Legendary effects (content + application), the shop helpers
## (forge_with_offer, offer_forge_slots), bot forging and RunState.weapons_forged.

const Support := preload("res://tests/test_loot_support.gd")

## Names that must never be used (WoW items, GDD 14) – a sample of the famous ones.
const FORBIDDEN_NAMES: Array[String] = [
	"Gorehowl", "Thunderfury", "Ashbringer", "Frostmourne", "Shadowmourne", "Sulfuras",
	"Doomhammer", "Atiesh", "Warglaive", "Thori'dal", "Val'anyr", "Quel'Delar", "Dragonwrath",
	"Fandral", "Xal'atath", "Azzinoth", "Murloc", "Azeroth", "Horde", "Alliance",
]

var rng: RandomNumberGenerator
var slots: Array[PlayerSlot] = []


func before_each() -> void:
	RunState.start_run(2, 21)
	rng = RandomNumberGenerator.new()
	rng.seed = 4242
	slots.clear()


func after_each() -> void:
	Support.free_slots(slots)
	slots.clear()


func _gen(id: StringName, rarity: int = Items.Rarity.COMMON, wave: int = 1, looted: bool = false) -> ItemInstance:
	return ItemGenerator.generate_weapon(Db.get_weapon(id), rarity, wave, looted, rng)


func _eq(class_id: StringName, starting: bool = true) -> Equipment:
	var eq := Equipment.new(Db.get_class_data(class_id))
	if starting:
		eq.equip_starting_weapons()
	return eq


## A joined-like slot with a (fake) hero of [param class_id] holding its starting weapons.
func _slot(class_id: StringName) -> PlayerSlot:
	var s := Support.make_slot(slots.size(), class_id)
	Support.equipment_of(s).equip_starting_weapons()
	slots.append(s)
	return s


## Name, rarity, wave, looted, stats and enchants – equal for equal rolls.
static func _signature(item: ItemInstance) -> String:
	var keys := item.stats.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s=%s" % [k, item.stats[k]])
	for roll in item.enchants:
		parts.append("%s:%d" % [roll.enchant.id, roll.rank])
	return "%s|%d|%d|%s|%s" % [item.display_name, item.rarity, item.wave, item.looted, ",".join(parts)]


func _hand_made_weapon() -> ItemInstance:
	for id in Db.uniques:
		var data: UniqueItemData = Db.uniques[id]
		if data.weapon != null and data.rarity < Items.Rarity.LEGENDARY:
			return ItemGenerator.from_unique(data, 3, false, rng)
	return null


# --- Pairing rules -------------------------------------------------------------------------

func test_pairing_rules() -> void:
	var a := _gen(&"dagger")
	var b := _gen(&"dagger")
	check(Forge.is_forgeable(a), "a generated Common dagger is forgeable")
	check(Forge.pairs_with(a, b), "same base, same rarity")
	check(not Forge.pairs_with(a, a), "never with itself")
	check(not Forge.pairs_with(a, _gen(&"dagger", Items.Rarity.UNCOMMON)), "another rarity")
	check(not Forge.pairs_with(a, _gen(&"sword")), "another base")
	var starting := ItemInstance.from_weapon(Db.get_weapon(&"dagger"))
	check(Forge.is_forgeable(starting) and Forge.pairs_with(a, starting), "starting weapons qualify")
	for r in [Items.Rarity.COMMON, Items.Rarity.UNCOMMON, Items.Rarity.RARE, Items.Rarity.EPIC]:
		check(Forge.is_forgeable(_gen(&"mace", r)), "%s is forgeable" % Items.RARITY_NAMES[r])
	check(not Forge.is_forgeable(_gen(&"mace", Items.Rarity.LEGENDARY)), "Legendary is not")
	var artifact := _gen(&"mace", Items.Rarity.EPIC)
	artifact.rarity = Items.Rarity.ARTIFACT
	check(not Forge.is_forgeable(artifact), "Artifact is not")
	var hand_made := _hand_made_weapon()
	check(hand_made != null and hand_made.unique and hand_made.is_weapon(), "a hand-made weapon exists")
	check(not Forge.is_forgeable(hand_made), "hand-made is not")
	var twin := ItemGenerator.generate_weapon(hand_made.weapon, hand_made.rarity, 3, false, rng)
	twin.source_id = hand_made.source_id
	check(not Forge.pairs_with(hand_made, twin), "not even with a look-alike")
	var helm := Support.make_armor(10, ClassData.ArmorType.PLATE, 20, Items.Rarity.COMMON, Items.SlotType.HEAD)
	check(not Forge.is_forgeable(helm) and not Forge.is_forgeable(null), "only weapons")
	var odd := _gen(&"dagger")
	odd.source_id = &"no_such_weapon"
	check(not Forge.is_forgeable(odd), "the base must be a Db weapon")


func test_blocked_reasons_and_result_text() -> void:
	var eq := _eq(&"warrior")
	var sword := eq.get_item(Items.EquipSlot.MAIN_HAND)
	check_eq(Forge.blocked_reason(eq, sword), "No other Common One-Hand Sword", "lone starting sword")
	check_eq(Forge.result_text(sword), "→ Uncommon", "the result's rarity even without a partner")
	check_eq(Forge.forged_rarity(sword), Items.Rarity.UNCOMMON, "Common -> Uncommon")
	var dagger := _gen(&"dagger", Items.Rarity.RARE)
	eq.add_to_backpack(dagger)
	check_eq(Forge.blocked_reason(eq, dagger), "No other Rare Dagger", "GDD text")
	check_eq(Forge.result_text(dagger), "→ Epic", "Rare -> Epic")
	eq.add_to_backpack(_gen(&"dagger", Items.Rarity.RARE))
	check_eq(Forge.blocked_reason(eq, dagger), "", "a partner: forgeable")
	var epic := _gen(&"dagger", Items.Rarity.EPIC)
	check_eq(Forge.result_text(epic), "→ Legendary", "Epic -> Legendary")
	var legendary := _gen(&"dagger", Items.Rarity.LEGENDARY)
	eq.add_to_backpack(legendary)
	eq.add_to_backpack(_gen(&"dagger", Items.Rarity.LEGENDARY))
	check_eq(Forge.blocked_reason(eq, legendary), "Legendary is the highest rarity", "Legendary, even with a twin")
	check_eq(Forge.result_text(legendary), "", "no detail")
	check_eq(Forge.forged_rarity(legendary), -1, "no result rarity")
	var artifact := _gen(&"dagger", Items.Rarity.EPIC)
	artifact.rarity = Items.Rarity.ARTIFACT
	check_eq(Forge.blocked_reason(eq, artifact), Forge.REASON_ARTIFACT, "Artifact")
	check_eq(Forge.blocked_reason(eq, _hand_made_weapon()), "Hand-made weapons cannot be forged", "hand-made")
	var helm := Support.make_armor(10, ClassData.ArmorType.PLATE, 20, Items.Rarity.COMMON, Items.SlotType.HEAD)
	check_eq(Forge.blocked_reason(eq, helm), Forge.REASON_NOT_WEAPON, "not a weapon")
	check_eq(Forge.blocked_reason(null, dagger), Forge.REASON_NO_HERO, "no equipment")


func test_forge_refuses_a_weapon_the_hero_does_not_own() -> void:
	var eq := _eq(&"rogue", false)
	var mine := _gen(&"dagger", Items.Rarity.RARE)
	eq.add_to_backpack(mine)
	var stray := _gen(&"dagger", Items.Rarity.RARE)
	check(Forge.forge(eq, stray, rng) == null, "not in this hero's equipment: no forge")
	check(eq.backpack.has(mine), "the partner was not consumed")
	check_eq(eq.backpack.size(), 1, "nothing created")


func test_partner_order_backpack_then_main_then_off_hand() -> void:
	var eq := _eq(&"rogue")
	var main := eq.get_item(Items.EquipSlot.MAIN_HAND)
	var off := eq.get_item(Items.EquipSlot.OFF_HAND)
	var sword := _gen(&"sword")
	var uncommon := _gen(&"dagger", Items.Rarity.UNCOMMON)
	var x := _gen(&"dagger")
	var y := _gen(&"dagger")
	for it in [sword, uncommon, x, y]:
		eq.add_to_backpack(it)
	check(Forge.partner_for(eq, main) == x, "the first matching backpack item (index 2)")
	check(Forge.partner_for(eq, x) == y, "x skips itself: y")
	check(Forge.partner_for(eq, y) == x, "y pairs with x (lowest index first)")
	check(Forge.partner_for(eq, uncommon) == null, "no other Uncommon dagger")
	check(Forge.partner_for(eq, sword) == null, "no other sword")
	eq.take(x)
	eq.take(y)
	check(Forge.partner_for(eq, main) == off, "then the off hand for the main hand (never itself)")
	check(Forge.partner_for(eq, off) == main, "then the main hand")
	var offer := _gen(&"dagger")
	check(Forge.partner_for(eq, offer) == main, "an item outside: main hand before off hand")
	eq.add_to_backpack(y)
	check(Forge.partner_for(eq, offer) == y, "backpack before the hands")
	check(Forge.partner_for(null, offer) == null, "no equipment")


# --- Forging and placement -----------------------------------------------------------------

func test_backpack_pair_goes_to_the_end_of_the_backpack() -> void:
	var eq := _eq(&"warrior")
	var main := eq.get_item(Items.EquipSlot.MAIN_HAND)
	var a := _gen(&"dagger")
	var helm := Support.make_armor(10, ClassData.ArmorType.PLATE, 20, Items.Rarity.COMMON, Items.SlotType.HEAD)
	var b := _gen(&"dagger")
	for it in [a, helm, b]:
		eq.add_to_backpack(it)
	var result := Forge.forge(eq, a, rng)
	check(result != null, "forged")
	check(not eq.backpack.has(a) and not eq.backpack.has(b), "both pieces are gone")
	check_eq(eq.backpack.size(), 2, "helm + result")
	check(eq.backpack[0] == helm and eq.backpack[1] == result, "the result is appended")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == main, "the hands are untouched")
	check_eq(result.rarity, Items.Rarity.UNCOMMON, "one rarity up")
	check_eq(result.source_id, &"dagger", "same base")
	check(not result.unique and Forge.is_forgeable(result), "a normal generated weapon (forgeable again)")
	check_eq(RunState.weapons_forged, 1, "counted")


func test_equipped_piece_gives_its_position_to_the_result() -> void:
	# Main hand + backpack (from either side).
	var eq := _eq(&"warrior")
	var sword := eq.get_item(Items.EquipSlot.MAIN_HAND)
	var spare := ItemInstance.from_weapon(Db.get_weapon(&"sword"))
	eq.add_to_backpack(spare)
	var result := Forge.forge(eq, spare, rng)
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == result, "the result takes the main hand")
	check(eq.backpack.is_empty() and result != sword, "both pieces gone")
	check(eq.is_armed(), "never unarmed")
	var spare2 := _gen(&"sword", Items.Rarity.UNCOMMON)
	eq.add_to_backpack(spare2)
	var again := Forge.forge(eq, result, rng)
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == again and again.rarity == Items.Rarity.RARE,
		"forging the equipped one: same place, Rare")
	check(eq.backpack.is_empty(), "the backpack partner went into it")
	# Off hand (shield) + backpack.
	var pal := _eq(&"paladin")
	var shield := pal.get_item(Items.EquipSlot.OFF_HAND)
	var mace := pal.get_item(Items.EquipSlot.MAIN_HAND)
	var other := ItemInstance.from_weapon(Db.get_weapon(&"shield"))
	pal.add_to_backpack(other)
	var forged_shield := Forge.forge(pal, other, rng)
	check(pal.get_item(Items.EquipSlot.OFF_HAND) == forged_shield and forged_shield != shield, "the off hand keeps a shield")
	check(pal.get_item(Items.EquipSlot.MAIN_HAND) == mace, "the mace stays")
	check_eq(RunState.weapons_forged, 3, "three forges")


func test_dual_wield_pair_goes_to_the_main_hand() -> void:
	var eq := _eq(&"rogue")
	var off := eq.get_item(Items.EquipSlot.OFF_HAND)
	var result := Forge.forge(eq, off, rng)
	check(result != null, "a human may forge both hands")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == result, "main hand preferred")
	check(eq.get_item(Items.EquipSlot.OFF_HAND) == null, "the off hand is free")
	check(eq.backpack.is_empty(), "nothing in the backpack")
	check(eq.is_armed(), "still armed")


func test_two_hander_with_a_full_backpack() -> void:
	var eq := _eq(&"warrior", false)
	var axe := _gen(&"two_hand_axe", Items.Rarity.RARE)
	check(eq.equip(axe), "two-hander on")
	var twin := _gen(&"two_hand_axe", Items.Rarity.RARE)
	eq.add_to_backpack(twin)
	while eq.has_space():
		eq.add_to_backpack(Support.make_armor(1))
	var result := Forge.forge(eq, axe, rng)
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == result and result.rarity == Items.Rarity.EPIC, "Epic two-hander equipped")
	check_eq(eq.backpack.size(), Items.BACKPACK_SIZE - 1, "the partner left the full backpack")


func test_an_unequippable_result_goes_to_the_backpack_or_is_refused() -> void:
	# No class: nothing can be equipped (Equipment.can_equip), so the result of two equipped
	# daggers (placed by hand) needs a free backpack place.
	var eq := Equipment.new(null)
	var a := _gen(&"dagger")
	var b := _gen(&"dagger")
	eq.slots[Items.EquipSlot.MAIN_HAND] = a
	eq.slots[Items.EquipSlot.OFF_HAND] = b
	while eq.has_space():
		eq.add_to_backpack(Support.make_armor(1))
	check(not Forge.can_place(eq, a, b), "both equipped, nothing equippable, backpack full")
	check_eq(Forge.blocked_reason(eq, a), Forge.REASON_NO_ROOM, "the reason")
	check(Forge.forge(eq, a, rng) == null, "refused")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == a and eq.get_item(Items.EquipSlot.OFF_HAND) == b, "nothing taken")
	eq.backpack.pop_back()
	check(Forge.can_place(eq, a, b), "a free place")
	var r := Forge.forge(eq, a, rng)
	check(r != null and eq.backpack[-1] == r, "the result went to the backpack")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == null and eq.get_item(Items.EquipSlot.OFF_HAND) == null, "both pieces taken")


func test_refusals_change_nothing_and_draw_nothing() -> void:
	var eq := _eq(&"warrior")
	var sword := eq.get_item(Items.EquipSlot.MAIN_HAND)
	var state := rng.state
	var run_state := RunState.rng.state
	check(Forge.forge(eq, sword, rng) == null, "no partner")
	check_eq(rng.state, state, "no draw for a refusal")
	check(Forge.forge(eq, sword) == null, "default rng too")
	check_eq(RunState.rng.state, run_state, "no RunState draw for a refusal")
	var legendary := _gen(&"sword", Items.Rarity.LEGENDARY)
	eq.add_to_backpack(legendary)
	eq.add_to_backpack(_gen(&"sword", Items.Rarity.LEGENDARY))
	state = rng.state
	check(Forge.forge(eq, legendary, rng) == null, "Legendary")
	check_eq(rng.state, state, "no draw")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == sword and eq.backpack.size() == 2, "nothing moved")
	check_eq(RunState.weapons_forged, 0, "nothing counted")
	check(Forge.make_result(sword, sword, rng) == null, "make_result needs two items")
	check(Forge.make_result(sword, legendary, rng) == null, "make_result needs a pair")


# --- The result ----------------------------------------------------------------------------

func test_result_wave_looted_and_damage() -> void:
	var a := _gen(&"mace", Items.Rarity.UNCOMMON, 3)
	var b := _gen(&"mace", Items.Rarity.UNCOMMON, 7, true)
	RunState.wave = 5
	var r := Forge.make_result(a, b, rng)
	check_eq(r.rarity, Items.Rarity.RARE, "Rare")
	check_eq(r.wave, 7, "the higher of the two waves")
	check(r.looted, "Looted when either was")
	check_eq(r.item_level, Items.item_level(7, Items.Rarity.RARE, true), "Item Level of the new roll")
	check_near(r.weapon.base_damage, Db.get_weapon(&"mace").base_damage * Items.WEAPON_RARITY_DAMAGE[Items.Rarity.RARE], 0.001, "Rare damage")
	check_eq(r.buy_price, ItemGenerator.price_for(Items.Rarity.RARE, 7), "priced for its wave")
	check(r.enchants.size() >= 1, "a Rare gets an enchant")
	RunState.wave = 12
	var later := Forge.make_result(a, _gen(&"mace", Items.Rarity.UNCOMMON, 3), rng)
	check_eq(later.wave, 12, "the current wave when it is higher")
	check(not later.looted, "not Looted when neither was")


func test_result_is_a_fresh_seeded_roll() -> void:
	var a := _gen(&"sword", Items.Rarity.RARE, 9)
	var b := _gen(&"sword", Items.Rarity.RARE, 9)
	var r1 := RandomNumberGenerator.new()
	r1.seed = 77
	var r2 := RandomNumberGenerator.new()
	r2.seed = 77
	var first := Forge.make_result(a, b, r1)
	var second := Forge.make_result(a, b, r2)
	check_eq(_signature(first), _signature(second), "same seed, same weapon")
	check(first != second and first.uid != second.uid, "two instances")
	var seen: Dictionary[String, bool] = {}
	for s in 8:
		var r := RandomNumberGenerator.new()
		r.seed = 1000 + s
		seen[_signature(Forge.make_result(a, b, r))] = true
	check(seen.size() > 1, "new random bonus stats per roll")
	# The default rng is RunState.rng.
	var before := RunState.rng.state
	Forge.make_result(a, b, null)
	check(RunState.rng.state != before, "RunState.rng draws by default")


# --- Legendary effects ---------------------------------------------------------------------

func test_every_weapon_type_has_one_legendary_effect() -> void:
	var all := Forge.legendaries()
	check_eq(all.size(), Db.weapons.size(), "one per Db weapon")
	var names: Array[String] = []
	var unique_names: Array[String] = []
	for id in Db.uniques:
		unique_names.append((Db.uniques[id] as UniqueItemData).display_name)
	for weapon_id in Db.weapons:
		var data := Forge.legendary_for(weapon_id)
		if data == null:
			failures.append("no Legendary effect for %s" % weapon_id)
			continue
		var label := String(weapon_id)
		check_eq(data.weapon_id, weapon_id, "%s: keyed by its weapon" % label)
		check(data.display_name != "" and data.display_name not in names, "%s: a distinct name" % label)
		names.append(data.display_name)
		check(data.display_name not in unique_names, "%s: not a hand-made item's name" % label)
		for bad in FORBIDDEN_NAMES:
			check(not data.display_name.containsn(bad), "%s: no trademark (%s)" % [label, bad])
		check(data.unique_text != "" and data.flavor != "", "%s: effect text and flavor" % label)
		check(data.unique_effect in ProcSystem.BLOCKS, "%s: a ProcSystem block" % label)
		var proc: Dictionary = data.unique_params.duplicate(true)
		proc["effect"] = String(data.unique_effect)
		var error := BonusVocabulary.validate({"kind": "proc", "proc": proc})
		check_eq(error, "", "%s: a valid proc dict" % label)
		check(String(proc.get("trigger", "equip")) != "equip", "%s: a triggered effect" % label)
		var attacks := Db.get_weapon(weapon_id).attacks()
		if attacks:
			check(proc.has("every") and proc.has("hit_pct"), "%s: every Nth hit, a share of the hit" % label)
	check(Forge.legendary_for(&"no_such_weapon") == null, "unknown weapon: none")


func test_dagger_legendary_follows_the_gdd_example() -> void:
	# GDD 4.1: every 4th hit throws a poison blade – 100% of the hit as Nature damage + poison.
	var data := Forge.legendary_for(&"dagger")
	check_eq(data.unique_effect, &"bolt", "a thrown blade")
	check_eq(String(data.unique_params.get("trigger")), "on_hit", "on hit")
	check_eq(int(data.unique_params.get("every")), 4, "every 4th hit")
	check_eq(float(data.unique_params.get("hit_pct")), 100.0, "100% of the hit")
	check_eq(String(data.unique_params.get("school")), "nature", "Nature damage")
	check(float(data.unique_params.get("dot", 0.0)) > 0.0, "plus a poison")


func test_epic_pair_becomes_the_weapon_types_legendary() -> void:
	for weapon_id in Db.weapons:
		var data := Forge.legendary_for(weapon_id)
		var a := _gen(weapon_id, Items.Rarity.EPIC, 14)
		var b := _gen(weapon_id, Items.Rarity.EPIC, 15)
		var r := Forge.make_result(a, b, rng)
		var label := String(weapon_id)
		check_eq(r.rarity, Items.Rarity.LEGENDARY, "%s: Legendary" % label)
		check_eq(r.display_name, data.display_name, "%s: named after its effect" % label)
		check_eq(r.unique_effect, data.unique_effect, "%s: effect" % label)
		check_eq(r.unique_params, data.unique_params, "%s: params" % label)
		check_eq(r.unique_text, data.unique_text, "%s: text" % label)
		check_eq(r.flavor, data.flavor, "%s: flavor" % label)
		check(not r.unique, "%s: still a generated weapon" % label)
		check_eq(r.source_id, weapon_id, "%s: same base" % label)
		check_near(r.weapon.base_damage, Db.get_weapon(weapon_id).base_damage * 3.0, 0.001, "%s: x3 damage" % label)
		check(not Forge.is_forgeable(r), "%s: never forged again" % label)
		check_eq(r.enchants.size(), ItemGenerator.LEGENDARY_ENCHANTS, "%s: Legendary enchants" % label)
		var proc := ProcSystem.proc_from_unique(r)
		check(proc != null and proc.effect == data.unique_effect, "%s: ProcSystem builds its effect" % label)
		check_eq(String(proc.trigger), String(data.unique_params.get("trigger")), "%s: its trigger" % label)
		check_eq(proc.label, data.display_name, "%s: floating text" % label)
	# The params are a copy: the data stays untouched.
	var x := Forge.make_result(_gen(&"bow", Items.Rarity.EPIC), _gen(&"bow", Items.Rarity.EPIC), rng)
	x.unique_params["hit_pct"] = 1.0
	check(float(Forge.legendary_for(&"bow").unique_params["hit_pct"]) > 1.0, "deep copy")


func test_lower_rarity_results_get_no_legendary_effect() -> void:
	var r := Forge.make_result(_gen(&"wand", Items.Rarity.RARE), _gen(&"wand", Items.Rarity.RARE), rng)
	check_eq(r.rarity, Items.Rarity.EPIC, "Epic")
	check(r.unique_effect == &"" and r.unique_text == "", "no Legendary effect below Legendary")
	check(r.display_name.contains("Wand"), "a generated name: %s" % r.display_name)


# --- Shop helpers ----------------------------------------------------------------------------

func test_forge_with_offer() -> void:
	var eq := _eq(&"warrior")
	var sword := eq.get_item(Items.EquipSlot.MAIN_HAND)
	var dagger := _gen(&"dagger", Items.Rarity.UNCOMMON)
	eq.add_to_backpack(dagger)
	while eq.has_space():
		eq.add_to_backpack(Support.make_armor(1))
	# Backpack partner: the result is appended where the partner left room.
	var offer := _gen(&"dagger", Items.Rarity.UNCOMMON)
	var r := Forge.forge_with_offer(eq, offer, rng)
	check(r != null and r.rarity == Items.Rarity.RARE, "Rare dagger")
	check(not eq.backpack.has(offer) and not eq.backpack.has(dagger), "the offer never entered, the partner left")
	check(eq.backpack[-1] == r and eq.backpack.size() == Items.BACKPACK_SIZE, "the result took the free place")
	# Equipped partner: the result goes into that hand; the full backpack stays as it was.
	var offer_sword := ItemInstance.from_weapon(Db.get_weapon(&"sword"))
	var r2 := Forge.forge_with_offer(eq, offer_sword, rng)
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == r2 and r2 != sword, "into the main hand")
	check(not eq.backpack.has(sword) and not eq.backpack.has(offer_sword), "neither in the backpack")
	check_eq(RunState.weapons_forged, 2, "both counted")
	# No partner / already owned: refused.
	check(Forge.forge_with_offer(eq, _gen(&"bow"), rng) == null, "no partner")
	check(Forge.forge_with_offer(eq, r, rng) == null, "an item of the hero is not an offer")
	check(Forge.forge_with_offer(null, offer, rng) == null, "no equipment")


func test_offer_forge_slots_follow_each_players_gear() -> void:
	var warrior := _slot(&"warrior")
	var mage := _slot(&"mage")
	var rogue := _slot(&"rogue")
	var all: Array[PlayerSlot] = [warrior, mage, rogue]
	check_eq(Forge.offer_forge_slots(ItemInstance.from_weapon(Db.get_weapon(&"sword")), all), [warrior.index] as Array[int], "the warrior's starting sword")
	check_eq(Forge.offer_forge_slots(ItemInstance.from_weapon(Db.get_weapon(&"dagger")), all), [rogue.index] as Array[int], "the rogue's daggers")
	check_eq(Forge.offer_forge_slots(_gen(&"dagger", Items.Rarity.RARE), all), [] as Array[int], "a Rare dagger pairs with nobody")
	Support.equipment_of(mage).add_to_backpack(_gen(&"dagger", Items.Rarity.RARE))
	check_eq(Forge.offer_forge_slots(_gen(&"dagger", Items.Rarity.RARE), all), [mage.index] as Array[int], "a backpack partner counts")
	check_eq(Forge.offer_forge_slots(_gen(&"dagger", Items.Rarity.LEGENDARY), all), [] as Array[int], "not forgeable")
	check_eq(Forge.offer_forge_slots(null, all), [] as Array[int], "no item")


# --- Bots ------------------------------------------------------------------------------------

func test_bots_forge_backpack_pairs_until_none_is_left() -> void:
	var s := _slot(&"warrior")
	var eq := Support.equipment_of(s)
	var sword := eq.get_item(Items.EquipSlot.MAIN_HAND)
	for i in 4:
		eq.add_to_backpack(_gen(&"dagger"))
	var helm := Support.make_armor(10, ClassData.ArmorType.PLATE, 20, Items.Rarity.COMMON, Items.SlotType.HEAD)
	eq.add_to_backpack(helm)
	check_eq(Forge.bot_forge_all(s), 3, "4 Common -> 2 Uncommon -> 1 Rare")
	check_eq(eq.backpack.size(), 2, "helm + Rare dagger")
	check(eq.backpack[0] == helm and eq.backpack[1].rarity == Items.Rarity.RARE, "the Rare dagger")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == sword, "the lone sword is not touched")
	check_eq(RunState.weapons_forged, 3, "counted")
	check_eq(Forge.bot_forge_all(s), 0, "nothing left")
	check_eq(Forge.bot_forge_all(null), 0, "no slot")


func test_bots_forge_equipped_with_backpack_but_never_two_equipped() -> void:
	var s := _slot(&"rogue")
	var eq := Support.equipment_of(s)
	var main := eq.get_item(Items.EquipSlot.MAIN_HAND)
	var off := eq.get_item(Items.EquipSlot.OFF_HAND)
	check_eq(Forge.bot_forge_all(s), 0, "two equipped daggers stay a pair")
	check(eq.get_item(Items.EquipSlot.MAIN_HAND) == main and eq.get_item(Items.EquipSlot.OFF_HAND) == off, "untouched")
	var spare := ItemInstance.from_weapon(Db.get_weapon(&"dagger"))
	eq.add_to_backpack(spare)
	check_eq(Forge.bot_forge_all(s), 1, "the spare forges with the main hand")
	var forged := eq.get_item(Items.EquipSlot.MAIN_HAND)
	check(forged != main and forged.rarity == Items.Rarity.UNCOMMON, "the result replaces the main-hand dagger")
	check(eq.get_item(Items.EquipSlot.OFF_HAND) == off, "the off hand keeps its dagger")
	check(eq.backpack.is_empty(), "nothing left over")


func test_bot_forging_is_deterministic() -> void:
	var results: Array[String] = []
	for run in 2:
		RunState.start_run(1, 555)
		var s := Support.make_slot(0, &"warrior")
		var eq := Support.equipment_of(s)
		eq.equip_starting_weapons()
		for i in 3:
			eq.add_to_backpack(ItemInstance.from_weapon(Db.get_weapon(&"sword")))
		Forge.bot_forge_all(s)
		var parts := PackedStringArray()
		for it in eq.equipped_items() + eq.backpack:
			parts.append(_signature(it))
		results.append(" / ".join(parts))
		Support.free_slots([s] as Array[PlayerSlot])
	check_eq(results[0], results[1], "same seed, same forges")
