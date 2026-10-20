extends TestCase
## M6b item content (GDD 5.5 / 5.8): the 30 new named Rare / Epic hand-made items and the 30 new
## class items (8 per class, each with an "Equip:" ability mod). Every new item loads with valid
## fields; class items are usable by their class only and target a real ability of that class;
## every mod key changes a real parameter of its ability, and the change reaches the hero through
## the equipment; the tooltip shows the Equip line; every named item's proc fires.

const Fakes := preload("res://tests/player_fakes.gd")
const Rules := preload("res://tests/content_rules.gd")

const NAMED_IDS: Array[StringName] = [
	&"circlet_of_ninefold_skin", &"tunic_of_the_quiet_bulb", &"bracers_of_the_shallot_fold",
	&"garlic_clove_pendant", &"ring_of_the_chive_coil", &"quickstep_boots",
	&"leggings_of_the_scaled_skin", &"shardbound_gauntlets", &"cellar_sash",
	&"shoulderpads_of_shallow_roots", &"splinterwand", &"ring_of_the_ember_bulb",
	&"cuffs_of_the_last_breath", &"helm_of_the_brittle_crown", &"breastplate_of_the_crisp_shell",
	&"visor_of_the_sunward_watch", &"ringmail_of_the_second_skin", &"silken_leggings_of_the_veil",
	&"treads_of_the_nimble_clove", &"gauntlets_of_the_cloven_crust", &"girdle_of_the_unyielding_layer",
	&"spaulders_of_the_hollow_shell", &"halo_of_the_pearled_onion", &"signet_of_the_festering_wound",
	&"amulet_of_the_thousand_skins", &"wrap_of_the_blighted_peel", &"scallion_edge",
	&"shallot_shiv", &"robe_of_the_lantern_heart", &"leathers_of_the_rooted_dance",
]

const CLASS_IDS: Array[StringName] = [
	# Warrior
	&"warhelm_of_the_standing_shout", &"shoulderguards_of_the_stubborn_wall",
	&"breastplate_of_thunderous_echo", &"wristguards_of_the_sundering_edge",
	&"legplates_of_the_bold_leap", &"reaping_greataxe",
	# Mage
	&"long_coal_staff", &"shoulderwrap_of_the_glacial_ring", &"robe_of_the_tidewoven_veil",
	&"leggings_of_the_falling_star", &"cuffs_of_the_blazing_heart", &"gloves_of_the_quiet_missile",
	# Paladin
	&"helm_of_the_holy_hour", &"pauldrons_of_the_second_oath", &"cuirass_of_the_vigilant_dawn",
	&"vambrace_of_the_oathstone", &"girdle_of_lasting_grace", &"legplates_of_the_endless_storm",
	# Rogue
	&"hood_of_quick_blades", &"pauldrons_of_the_pale_smoke", &"jerkin_of_the_last_breath",
	&"gloves_of_the_quick_thrust", &"belt_of_shifting_shadows", &"leathers_of_the_unseen_throw",
	# Warlock
	&"hood_of_burning_summons", &"mantle_of_lingering_curses", &"robe_of_the_hollow_star",
	&"bracers_of_the_siphoning_thread", &"leggings_of_dread_steps", &"slippers_of_the_seeded_path",
]

## Block ids a hand-made item may use (test_items_gen_content.BLOCKS, minus the ones it lists).
const BLOCKS: Array[StringName] = [
	&"bolt", &"chain", &"dot", &"nova", &"explode", &"extra_attack", &"buff", &"heal", &"drain",
	&"slow", &"stun", &"gold", &"shield", &"reflect", &"smite_heal", &"cheat_death",
]
## Triggers a hand-made item may use with a proc (equip is not a proc).
const PROC_TRIGGERS: Array[String] = ["on_hit", "on_kill", "when_struck", "low_hp", "periodic"]

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


# --- Helpers ------------------------------------------------------------------------------------

## Stat text as the tooltip shows a mod number: "5", "0.5", "25".
static func _num_text(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return str(v)


## The parameter a mod key changes: "duration_add" -> "duration", "heal_pct" stays "heal_pct".
static func _mod_target(key: String) -> String:
	if key.ends_with("_add"):
		return key.trim_suffix("_add")
	if key.ends_with("_pct"):
		return key.trim_suffix("_pct")
	return key


## A fresh hero (of [param class_id]) in a fresh world, with nothing equipped.
func _fresh_hero(class_id: StringName) -> Player:
	Fakes.free_world(world)
	Enemy.invalidate_player_cache()
	world = Fakes.make_world(tree)
	return Fakes.spawn_player(world, 0, class_id, Vector3.ZERO)


# --- Loading and fields -------------------------------------------------------------------------

func test_new_item_lists_have_the_pinned_sizes() -> void:
	check_eq(NAMED_IDS.size(), 30, "30 new named items")
	check_eq(CLASS_IDS.size(), 30, "30 new class items")
	var per_class := {}
	for id in CLASS_IDS:
		var cls := Db.get_unique(id).class_restriction
		per_class[cls] = per_class.get(cls, 0) + 1
	for cls in Rules.LAUNCH_CLASSES:
		check_eq(per_class.get(cls, 0), 6, "6 new %s items" % cls)
	for cls in per_class:
		check(cls in Rules.LAUNCH_CLASSES, "the 30 are the launch classes' (%s)" % cls)


## Every class (the M8 ones too) has exactly 8 class items: the 2 of M6a and 6 more, each an
## "Equip:" ability mod of one of its own abilities, and a class set of 5 pieces restricted to it.
func test_every_class_has_eight_class_items_and_a_full_set() -> void:
	for class_id in Db.class_ids:
		var items := Rules.class_items(class_id)
		if not Rules.pending(class_id, "items"):
			check_eq(items.size(), Rules.CLASS_ITEMS_PER_CLASS, "%s: its class items" % class_id)
		var ids: Array[StringName] = []
		for u in items:
			check(u.id not in ids, "%s: %s listed once" % [class_id, u.id])
			ids.append(u.id)
			check_eq(u.unique_effect, &"ability_mod", "%s: %s is an ability mod" % [class_id, u.id])
		if Rules.pending(class_id, "set"):
			continue
		var sets := Rules.class_sets(class_id)
		check_eq(sets.size(), 1, "%s: one class tier set" % class_id)
		if sets.size() != 1:
			continue
		check_eq(sets[0].piece_ids.size(), Rules.PIECES_PER_SET, "%s: %d set pieces" % [class_id, Rules.PIECES_PER_SET])
		for piece_id in sets[0].piece_ids:
			var piece := Db.get_unique(piece_id)
			check(piece != null and piece.set_id == sets[0].id and piece.class_restriction == class_id,
					"%s: %s is a piece of the set, restricted to the class" % [class_id, piece_id])


func test_new_items_load_with_valid_fields() -> void:
	for id in NAMED_IDS + CLASS_IDS:
		check(Db.uniques.has(id), "%s loads from data/uniques" % id)
		var data := Db.get_unique(id)
		if data == null:
			continue
		check(data is UniqueItemData, "%s is a UniqueItemData" % id)
		check_eq(data.id, id, "%s: id is the file name" % id)
		check(ResourceLoader.exists("res://data/uniques/%s.tres" % id), "%s: file exists" % id)
		check(data.display_name != "" and data.flavor != "" and data.unique_text != "",
				"%s: name, flavour and text" % id)
		check(data.rarity == Items.Rarity.RARE or data.rarity == Items.Rarity.EPIC,
				"%s: Rare or Epic" % id)
		check(data.slot_type != Items.SlotType.TRINKET, "%s: not a trinket" % id)
		check(data.set_id == &"", "%s: not a set piece" % id)
		check(data.weight > 0.0 and data.min_wave >= 1, "%s: rolls from wave 1" % id)
		check_eq(data.sources.size(), 5, "%s: all five sources" % id)
		check(not data.stats.is_empty(), "%s: has stats" % id)
		for stat in data.stats:
			check(stat in Stats.ALL, "%s: known stat %s" % [id, stat])
		check(data.weapon == null or data.slot_type == Items.SlotType.WEAPON, "%s: weapon slot" % id)
		check_eq(data.slot_type in Items.ARMOR_SLOTS, data.armor_type != Items.NO_ARMOR,
				"%s: armour type exactly on armour slots" % id)
		check(data.unique_effect == &"ability_mod" or data.unique_effect in BLOCKS, "%s: known effect" % id)


func test_named_items_are_unrestricted_and_class_items_are_restricted() -> void:
	for id in NAMED_IDS:
		var data := Db.get_unique(id)
		if data != null:
			check_eq(data.class_restriction, &"", "%s: no class" % id)
			check(data.unique_effect != &"ability_mod", "%s: a proc, not an ability mod" % id)
	for id in CLASS_IDS:
		var data := Db.get_unique(id)
		if data != null:
			check(data.class_restriction in Db.class_ids, "%s: restricted to a class" % id)
			check_eq(data.unique_effect, &"ability_mod", "%s: an ability mod" % id)


func test_display_names_are_unique() -> void:
	var seen := {}
	for id in Db.uniques:
		var name: String = Db.uniques[id].display_name
		check(not seen.has(name), "'%s' is not used twice (%s)" % [name, id])
		seen[name] = true


# --- Named items: procs --------------------------------------------------------------------------

func test_named_items_use_one_known_proc_block() -> void:
	for id in NAMED_IDS:
		var data := Db.get_unique(id)
		if data == null:
			continue
		check(data.unique_effect in BLOCKS, "%s: block %s" % [id, data.unique_effect])
		var trigger := String(data.unique_params.get("trigger", ""))
		check(trigger in PROC_TRIGGERS, "%s: trigger %s" % [id, trigger])
		check(data.unique_text.begins_with("Equip:") or data.unique_text.begins_with("Chance on hit:")
				or data.unique_text.begins_with("On kill:") or data.unique_text.begins_with("When struck:")
				or data.unique_text.begins_with("Every "), "%s: a trigger phrase first" % id)


func test_every_named_proc_fires() -> void:
	for id in NAMED_IDS:
		_named_proc_fires(id)


## Equips the item on a hero that can use it, forces the roll (chance 100, no ppm, no internal
## cooldown) and fires the trigger the item names. The proc must count a fire.
func _named_proc_fires(id: StringName) -> void:
	var data := Db.get_unique(id)
	if data == null:
		return
	var class_id: StringName = &"mage" if data.weapon != null and data.weapon.weapon_type == &"wand" else &"warrior"
	var p := _fresh_hero(class_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var item := ItemGenerator.from_unique(data, 5, false, rng)
	check(p.equipment.equip(item), "%s: worn by %s" % [id, class_id])
	var proc: ProcSystem.Proc = null
	for pr in p.procs.procs:
		if pr.id == data.id:
			proc = pr
	check(proc != null, "%s: has a proc" % id)
	if proc == null:
		return
	proc.ppm = 0.0
	proc.chance = 100.0
	proc.icd = 0.0
	var enemy := Fakes.spawn_enemy(world, Vector3(1.5, 0, 0))
	EnemyGrid.mark_dirty()
	p.procs.begin_wave()
	var trigger := String(data.unique_params.get("trigger", ""))
	match trigger:
		"on_hit":
			p.procs.on_hit(enemy, 1.0, p.main_hand, false)
		"on_kill":
			p.procs.on_kill(enemy)
		"when_struck":
			p.procs.on_struck(enemy, 5.0)
		"periodic":
			Fakes.step(p.procs, float(data.unique_params.get("interval", 5.0)) + 0.5)
		"low_hp":
			# The HP check runs when the hero is struck (ProcSystem.on_struck).
			p.hp = p.max_hp() * 0.1
			p.procs.on_struck(enemy, 1.0)
	check(p.procs.fire_count(data.id) >= 1, "%s: its %s proc fires" % [id, trigger])


# --- Class items: usability and targets ----------------------------------------------------------

func test_class_items_are_usable_only_by_their_class() -> void:
	for id in CLASS_IDS:
		var data := Db.get_unique(id)
		if data == null:
			continue
		for cls_id in Db.class_ids:
			var c := Db.get_class_data(cls_id)
			check_eq(ItemGenerator.unique_usable_by(data, c), cls_id == data.class_restriction,
					"%s usable by %s only for its class" % [id, cls_id])


func test_class_items_target_an_ability_of_their_class() -> void:
	for id in CLASS_IDS:
		var data := Db.get_unique(id)
		if data == null:
			continue
		var ability_id := StringName(data.unique_params.get("ability", ""))
		var ability := Db.get_ability(ability_id)
		check(ability != null, "%s: ability %s exists" % [id, ability_id])
		if ability != null:
			check_eq(ability.class_id, data.class_restriction, "%s: the ability is the class's" % id)


func test_class_item_mods_change_real_ability_params() -> void:
	for id in CLASS_IDS:
		var data := Db.get_unique(id)
		if data == null:
			continue
		var ability := Db.get_ability(StringName(data.unique_params.get("ability", "")))
		if ability == null:
			continue
		var mods: Dictionary = data.unique_params.get("mods", {})
		check(not mods.is_empty(), "%s: has mods" % id)
		# The same base AbilityRunner.params_at_rank starts from (cooldown, cost, charges, power + params).
		var base := {"cooldown": ability.cooldown, "cost": ability.cost, "charges": 1, "power": 1.0}
		base.merge(ability.params, true)
		for key in mods:
			var value: Variant = mods[key]
			check(typeof(value) in [TYPE_INT, TYPE_FLOAT], "%s: %s is a number" % [id, key])
			var target := _mod_target(String(key))
			check(target in base, "%s: %s changes %s, a real param of %s" % [id, key, target, ability.id])
			var changed := AbilityRunner.apply_mods(base, {key: value})
			check(not is_equal_approx(float(changed.get(target, 0.0)), float(base.get(target, 0.0))),
					"%s: %s changes the value" % [id, key])


func test_class_item_mods_reach_the_hero_through_equipment() -> void:
	for id in CLASS_IDS:
		var data := Db.get_unique(id)
		if data == null:
			continue
		var cls := Db.get_class_data(data.class_restriction)
		var ability := Db.get_ability(StringName(data.unique_params.get("ability", "")))
		if cls == null or ability == null:
			continue
		var p := _fresh_hero(cls.id)
		var before := p.abilities.params_at_rank(ability, 1)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var item := ItemGenerator.from_unique(data, 5, false, rng, cls)
		check(p.equipment.equip(item), "%s: worn by its %s" % [id, cls.id])
		var mods: Dictionary = data.unique_params.get("mods", {})
		var worn := p.ability_mods(ability.id)
		for key in mods:
			check(worn.has(key), "%s: the hero's ability_mods carry %s" % [id, key])
		var after := p.abilities.params_at_rank(ability, 1)
		var expected := AbilityRunner.apply_mods(before, mods)
		for k in expected:
			if before.has(k) and typeof(expected[k]) in [TYPE_INT, TYPE_FLOAT]:
				check_near(float(after.get(k, 0.0)), float(expected[k]), 0.0001,
						"%s: %s is %s at rank I" % [id, k, expected[k]])
		check(after != before, "%s: the ability's params change" % id)


## Every number an Equip line states (the "10" of "10%", the "0.5" of "0.5 sec").
static func _text_numbers(text: String) -> Array[float]:
	var out: Array[float] = []
	var re := RegEx.new()
	re.compile("[0-9]+(\\.[0-9]+)?")
	for m in re.search_all(text):
		out.append(m.get_string().to_float())
	out.sort()
	return out


## The absolute values of a mod dictionary, sorted.
static func _mod_numbers(mods: Dictionary) -> Array[float]:
	var out: Array[float] = []
	for key in mods:
		out.append(absf(float(mods[key])))
	out.sort()
	return out


func test_class_item_text_numbers_are_the_mod_values() -> void:
	# Exactly the mods' numbers, no more: an absolute value of the ability (say "below 30% health")
	# that a rank or a spec changes would be a second number here.
	for id in CLASS_IDS:
		var data := Db.get_unique(id)
		if data == null:
			continue
		check(data.unique_text.begins_with("Equip: "), "%s: an Equip: line" % id)
		check(not data.unique_text.contains("{"), "%s: no placeholder left" % id)
		var mods: Dictionary = data.unique_params.get("mods", {})
		check_eq(_text_numbers(data.unique_text), _mod_numbers(mods),
				"%s: the text's numbers are the mods' (%s)" % [id, data.unique_text])


## Words that say how much a number changes ("1 sec longer", "10% higher"), not what it is.
const RELATIVE_WORDS: Array[String] = ["longer", "shorter", "more", "higher", "additional", "farther",
		"further", "lower", "extra"]


func test_class_item_text_says_how_much_it_changes() -> void:
	# A number that a rank changes is only true as a difference: "stuns for 1 sec" is 2 sec at
	# Rank III, "stuns for 1 sec longer" is true at every rank.
	for id in CLASS_IDS:
		var data := Db.get_unique(id)
		if data == null:
			continue
		var relative := false
		for word in RELATIVE_WORDS:
			if data.unique_text.contains(word):
				relative = true
		check(relative, "%s: the text says how much it changes (%s)" % [id, data.unique_text])


## The Equip lines that stated an absolute value which the ranks or a spec change, reworded.
const REWORDED_LINES: Dictionary = {
	&"wristguards_of_the_sundering_edge": "Equip: Your Execute's threshold is 10% higher.",
	&"legplates_of_the_bold_leap": "Equip: Your Soaring Slam stuns enemies for 1 sec longer.",
	&"pauldrons_of_the_pale_smoke": "Equip: Your Poison Bomb's fumes slow an additional 20%.",
	&"cuffs_of_the_blazing_heart": "Equip: Your Magma Bolt's burn deals 10% more of its hit.",
	&"leggings_of_the_falling_star": "Equip: Your Meteor stuns enemies for 0.5 sec longer.",
}


func test_absolute_equip_lines_are_reworded() -> void:
	for id in REWORDED_LINES:
		var data := Db.get_unique(id)
		if data != null:
			check_eq(data.unique_text, REWORDED_LINES[id], "%s: the relative wording" % id)


func test_class_item_tooltip_shows_the_equip_line() -> void:
	for id in CLASS_IDS:
		var data := Db.get_unique(id)
		if data == null:
			continue
		var cls := Db.get_class_data(data.class_restriction)
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var item := ItemGenerator.from_unique(data, 5, false, rng, cls)
		var tip := ItemTooltip.create()
		tree.root.add_child(tip)
		tip.show_item(item, cls)
		var line := tip.find_line(data.unique_text)
		check(line != null, "%s: the tooltip shows its Equip line" % id)
		if line != null:
			check(line.get_theme_color(&"font_color").is_equal_approx(ItemTooltip.ENCHANT_GREEN),
					"%s: the Equip line is green" % id)
		tip.get_parent().remove_child(tip)
		tip.free()


# --- Item effects checked on the ability (not only the params) ----------------------------------

func test_girdle_of_lasting_grace_shortens_lay_on_hands_at_rank_one() -> void:
	# An unconditional cooldown mod: it works without the Rank III shield (shield_max_hp).
	var p := _fresh_hero(&"paladin")
	var ability := Db.get_ability(&"lay_on_hands")
	check(p.abilities.learn(ability) >= 0, "Mending Touch learned")
	check_eq(p.abilities.rank_of(&"lay_on_hands"), 1, "Rank I")
	var before := p.abilities.cooldown_of(ability)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var item := ItemGenerator.from_unique(Db.get_unique(&"girdle_of_lasting_grace"), 5, false, rng,
			Db.get_class_data(&"paladin"))
	check(p.equipment.equip(item), "the girdle is worn")
	check_near(float(p.abilities.params_at_rank(ability, 1)["cooldown"]), 50.0, 0.001,
			"Rank I: the cooldown param is 60 - 10")
	check_near(p.abilities.cooldown_of(ability), before - 10.0, 0.001,
			"the hero waits 10 sec less")


func test_leathers_of_the_unseen_throw_adds_a_shuriken() -> void:
	# The count is the item's main effect; the 3 m of range is its second key.
	var p := _fresh_hero(&"rogue")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var item := ItemGenerator.from_unique(Db.get_unique(&"leathers_of_the_unseen_throw"), 5, false, rng,
			Db.get_class_data(&"rogue"))
	check(p.equipment.equip(item), "the leathers are worn")
	var ability := Db.get_ability(&"shuriken_toss")
	var slot := p.abilities.learn(ability)
	check(slot >= 0, "Throwing Stars learned")
	var at_rank := p.abilities.params_at_rank(ability, 1)
	check_near(float(at_rank["shuriken"]), 4.0, 0.001, "Rank I: 3 + 1 shuriken")
	check_near(float(at_rank["range"]), 14.0, 0.001, "Rank I: 11 + 3 m range")
	Fakes.spawn_enemy(world, Vector3(4, 0, -4))
	EnemyGrid.mark_dirty()
	check(p.abilities.try_cast(slot), "cast")
	var stars := 0
	for node in tree.get_nodes_in_group(&"projectiles"):
		var b := node as RogueBlade
		if b != null and b.attacker == p and not b.is_queued_for_deletion():
			stars += 1
	check_eq(stars, 4, "four shuriken are thrown")


# --- The Equip line of a class item greys out until the hero learns its ability -----------------

func _tip(item: ItemInstance, viewer: ClassData, viewer_eq: Equipment = null) -> ItemTooltip:
	var t := ItemTooltip.create()
	tree.root.add_child(t)
	t.viewer_equipment = viewer_eq
	t.show_item(item, viewer)
	return t


func _free_tip(t: ItemTooltip) -> void:
	t.get_parent().remove_child(t)
	t.free()


func test_class_item_equip_line_greys_out_until_the_ability_is_learned() -> void:
	PlayerManager.clear()
	var cls := Db.get_class_data(&"warrior")
	var data := Db.get_unique(&"warhelm_of_the_standing_shout")  # Equip: Battle Shout
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var item := ItemGenerator.from_unique(data, 5, false, rng, cls)
	# Nobody to ask (no hero joined): nothing is missing, the line is plain green.
	var nobody := _tip(item, cls)
	var plain := nobody.find_line(data.unique_text, true)
	check(plain != null and plain.get_theme_color(&"font_color").is_equal_approx(ItemTooltip.ENCHANT_GREEN),
			"no hero to ask: the Equip line is green")
	_free_tip(nobody)

	var slot := PlayerManager.join(ScriptedInput.new("m6b_tip:warrior"), cls)
	var hero := Player.create(slot)
	check(not hero.abilities.knows(&"battle_shout"), "precondition: Battle Roar is not learned yet")
	var needs_text := "%s (needs %s)" % [data.unique_text, Artifacts.ability_name(&"battle_shout")]
	var before := _tip(item, cls, hero.equipment)
	var grey := before.find_line(data.unique_text)
	check(grey != null and grey.text == needs_text, "the Equip line names what it needs")
	check(grey != null and grey.get_theme_color(&"font_color").is_equal_approx(ItemTooltip.DIM),
			"greyed out while the ability is missing")
	_free_tip(before)

	check(hero.abilities.learn(Db.get_ability(&"battle_shout")) >= 0, "Battle Roar learned")
	var after := _tip(item, cls, hero.equipment)
	var learned := after.find_line(data.unique_text, true)
	check(learned != null, "once learned: the plain Equip line, no suffix")
	check(learned != null and learned.get_theme_color(&"font_color").is_equal_approx(ItemTooltip.ENCHANT_GREEN),
			"once learned: green")
	check(after.find_line("(needs") == null, "once learned: no needs text")
	_free_tip(after)

	PlayerManager.clear()
	if is_instance_valid(hero):
		hero.free()
