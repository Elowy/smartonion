extends "res://tests/talents_hunter_base.gd"
## The three Hunter talent trees as content (M8 TALENTS-H, design_hunter 4): Packlord, Sharpshot and
## Wildcraft are in Db and pass the talent content contract (test_talent_data.gd) – shape, 22 points,
## prerequisites, modifiers on Hunter abilities, scripts named after their file –, every mod names a real
## ability or companion param, the pending list no longer holds the Hunter's trees, the 27 talents and 3
## trees have their own pictures (unique inside the whole icon map), the names are unique game-wide and
## the bot talent paths (TalentBot: tree = slot % 3, capstone at point 13, weapon-bound talents deferred
## for a bow) are pinned. Per tree: test_talents_hunter_packlord / _sharpshot / _wildcraft; the Talents
## tab: test_talents_hunter_ui.

const DataTest := preload("res://tests/test_talent_data.gd")
const Rules := preload("res://tests/content_rules.gd")

const PL_CAPSTONE := &"hunter_packlord_pack_frenzy"
const SS_CAPSTONE := &"hunter_sharpshot_steady_aura"
const WC_CAPSTONE := &"hunter_wildcraft_firebug_bombs"

## Hunter-only content ids that must not be shared with any other picture of the game.
const AUTHORS: Array[String] = ["lorc", "delapouite"]


func _trees() -> Array[TalentTreeData]:
	return Db.talent_trees_for(&"hunter")


func _bot_path_ids(index: int, loadout: Callable = Callable()) -> Array[StringName]:
	var p := _hunter(index, Vector3(index * 6.0, 0, 0))
	if loadout.is_valid():
		loadout.call(p)
	return bot_path(p, index)


# --- The trees in Db ---------------------------------------------------------------------------

func test_the_three_hunter_trees_are_in_db() -> void:
	var trees := _trees()
	check_eq(trees.size(), 3, "three trees")
	if trees.size() != 3:
		return
	var ids: Array[StringName] = []
	for t in trees:
		ids.append(t.id)
		check_eq(DataTest.tree_problems(t), [] as Array[String], "%s passes the content contract" % t.id)
		check_eq(t.class_id, &"hunter", "%s belongs to the Hunter" % t.id)
		check_eq(t.talents.size(), 9, "%s: nine talents" % t.id)
		var points := 0
		for talent in t.talents:
			points += talent.max_rank
		check_eq(points, 22, "%s: 22 points" % t.id)
	check_eq(ids, [&"hunter_packlord", &"hunter_sharpshot", &"hunter_wildcraft"] as Array[StringName], "tab order")
	var names: Array[String] = []
	var icons: Array[StringName] = []
	var indexes: Array[int] = []
	for t in trees:
		names.append(t.display_name)
		icons.append(t.icon)
		indexes.append(t.index)
	check_eq(names, ["Packlord", "Sharpshot", "Wildcraft"] as Array[String], "names")
	check_eq(icons, [&"hunt_signal", &"long_shot", &"blast_snare"] as Array[StringName], "tree icons are Hunter ability ids")
	check_eq(indexes, [0, 1, 2] as Array[int], "indexes")
	check_eq(trees[0].description, "Your companion, Hunt Signal and Beastbond.", "Packlord description")
	check_eq(trees[1].description, "Bow, Long Shot and critical hits.", "Sharpshot description")
	check_eq(trees[2].description, "Snares, melee weapons and survival: polearm and dual wield.", "Wildcraft description")
	var talents := 0
	for id in Db.talents:
		if String(id).begins_with("hunter_"):
			talents += 1
	check_eq(talents, 27, "27 Hunter talents in the registry")


func test_the_pending_list_no_longer_holds_the_hunter_trees() -> void:
	check(not Rules.pending(&"hunter", "trees"), "hunter:trees is gone from the pending list")
	check_eq(Rules.count_of(&"hunter", "trees"), 3, "and the trees exist")
	check(&"hunter" in Rules.classes_with("trees"), "the completeness checks include the Hunter's trees")


func test_the_tier_layout_prerequisites_modifiers_and_capstones() -> void:
	var prerequisites := {
		&"hunter_packlord_feral_tempo": &"hunter_packlord_keen_companion",
		&"hunter_packlord_wild_kinship": &"hunter_packlord_feral_tempo",
		&"hunter_sharpshot_quickening_aim": &"hunter_sharpshot_fletchers_edge",
		&"hunter_sharpshot_skewering_shots": &"hunter_sharpshot_heavy_shafts",
		&"hunter_wildcraft_close_quarters": &"hunter_wildcraft_twin_fang_grip",
		&"hunter_wildcraft_fleet_retreat": &"hunter_wildcraft_trailwise",
	}
	var with_prerequisite := 0
	for tree_data in _trees():
		for t in tree_data.talents:
			if t.prerequisite != &"":
				with_prerequisite += 1
				check_eq(t.prerequisite, prerequisites.get(t.id, &""), "%s needs %s" % [t.id, prerequisites.get(t.id, &"")])
	check_eq(with_prerequisite, 6, "two prerequisites per tree")
	var modifiers := {
		&"hunter_packlord_open_wound": &"hunt_signal",
		&"hunter_sharpshot_finishing_arrow": &"long_shot",
		&"hunter_wildcraft_brace_of_snares": &"blast_snare",
	}
	for id: StringName in modifiers:
		var t := Db.get_talent(id)
		check(t != null and t.kind == TalentData.Kind.MODIFIER and t.tier == 3 and t.column == 1 and t.max_rank == 1, "%s: the tier-3 modifier" % id)
		check_eq(t.ability, modifiers[id], "%s changes %s" % [id, modifiers[id]])
	var scripts := {
		PL_CAPSTONE: "res://scenes/talents/hunter/packlord_pack_frenzy.gd",
		SS_CAPSTONE: "res://scenes/talents/hunter/sharpshot_steady_aura.gd",
	}
	for id: StringName in [PL_CAPSTONE, SS_CAPSTONE, WC_CAPSTONE]:
		var t := Db.get_talent(id)
		check(t != null and t.is_capstone() and t.tier == 5 and t.max_rank == 1, "%s: the capstone" % id)
		var script_entries := 0
		for e in t.effects:
			if e["kind"] == "script":
				script_entries += 1
				check_eq(e["script"], scripts.get(id, ""), "%s: its script" % id)
		check_eq(script_entries, 1 if scripts.has(id) else 0, "%s: %s" % [id, "a script" if scripts.has(id) else "data only"])
	# Class-specific rules of the design: the weapon-bound talents carry `requires` on every effect.
	for id: StringName in [&"hunter_wildcraft_twin_fang_grip", &"hunter_wildcraft_close_quarters"]:
		for e in Db.get_talent(id).effects:
			check(e.has("requires"), "%s: every effect names its weapon" % id)
	check_eq(Db.get_talent(&"hunter_wildcraft_twin_fang_grip").effects[0]["requires"]["weapon"], "dual_wield", "Twin Fang Grip: dual wield")
	check_eq(Db.get_talent(&"hunter_wildcraft_close_quarters").effects[0]["requires"]["weapon"], "melee", "Close Quarters: melee")


func test_every_mod_names_a_real_param() -> void:
	var seen_pet := 0
	for tree_data in _trees():
		for t in tree_data.talents:
			for e in t.effects:
				if e["kind"] != "ability":
					continue
				var id := StringName(e["match"]["id"])
				var names: Dictionary
				if id == PET_MOD:
					seen_pet += 1
					names = HunterCompanion.BASE_PARAMS
				else:
					var ability := Db.get_ability(id)
					check(ability != null and ability.class_id == &"hunter", "%s: %s is a Hunter ability" % [t.id, id])
					names = BonusVocabulary.param_names(ability)
				for key: String in e["mods"]:
					var param := key.trim_suffix("_add") if key.ends_with("_add") else key.trim_suffix("_pct")
					check(names.has(param), "%s: '%s' changes a param of %s" % [t.id, key, id])
	check_eq(seen_pet, 3, "three talents change the companion (the pseudo ability)")


func test_the_texts_are_english_short_and_free_of_old_names() -> void:
	for tree_data in _trees():
		check(tree_data.display_name.length() <= 12, "%s: a short tree name" % tree_data.id)
		for t in tree_data.talents:
			check(t.display_name.length() <= 20, "%s: a short name (%s)" % [t.id, t.display_name])
			for rank in range(1, t.max_rank + 1):
				var text := t.text_for_rank(rank)
				check(text.length() <= 150, "%s: rank %d text fits (%d chars)" % [t.id, rank, text.length()])
				check(text.ends_with("."), "%s: a full sentence" % t.id)
				check(not ("{" in text or "}" in text), "%s: no placeholder left" % t.id)
	# Names are unique game-wide (ability, Rank V specialisation, talent and tree names).
	var others: Dictionary = {}
	for a: AbilityData in Db.abilities.values():
		others[a.display_name] = "ability " + String(a.id)
		for spec: Dictionary in a.specs:
			others[String(spec.get("name", ""))] = "spec of " + String(a.id)
	for id in Db.talents:
		if not String(id).begins_with("hunter_"):
			others[Db.talents[id].display_name] = "talent " + String(id)
	for id in Db.talent_trees:
		if not String(id).begins_with("hunter_"):
			others[Db.talent_trees[id].display_name] = "tree " + String(id)
	var own: Dictionary = {}
	for tree_data in _trees():
		for name in [tree_data.display_name] + tree_data.talents.map(func(t: TalentData) -> String: return t.display_name):
			check(not others.has(name), "'%s' is also a %s" % [name, others.get(name, "")])
			check(not own.has(name), "'%s' is used twice by the Hunter" % name)
			own[name] = true
	check_eq(own.size(), 30, "27 talents + 3 trees, 30 distinct names")


# --- Pictures ----------------------------------------------------------------------------------

func test_every_talent_and_tree_has_its_own_picture() -> void:
	var map := GameIcons.icon_map()
	# Every path of the whole map and who uses it.
	var users: Dictionary = {}
	for block: Dictionary in [map.abilities, map.talents, map.trees, map.consumables, map.shrines, map.stats, map.schools]:
		for key: StringName in block:
			var path: String = block[key]
			users[path] = int(users.get(path, 0)) + 1
	var mine: Array[String] = []
	var wanted: Array[Array] = []
	for tree_data in _trees():
		wanted.append([tree_data.id, String(map.trees.get(tree_data.id, ""))])
		for t in tree_data.talents:
			wanted.append([t.id, String(map.talents.get(t.id, ""))])
	check_eq(wanted.size(), 30, "30 pictures wanted")
	for pair in wanted:
		var path: String = pair[1]
		check(path != "", "%s has an entry" % pair[0])
		check(not mine.has(path), "%s: %s is used twice by the Hunter" % [pair[0], path])
		mine.append(path)
		check_eq(int(users.get(path, 0)), 1, "%s: %s is used by nothing else in the map" % [pair[0], path])
		check(ResourceLoader.exists(path), "%s: the file exists" % path)
		var author := path.trim_prefix("res://assets/icons/").get_slice("/", 0)
		check(author in AUTHORS, "%s: by a credited author" % path)
		var tex := GameIcons.texture_at(path)
		check(tex != null and tex.get_width() == 128 and tex.get_height() == 128, "%s: imported at 128 px" % path)
		var import := FileAccess.get_file_as_string(path + ".import")
		check("svg/scale=0.25" in import and "mipmaps/generate=true" in import, "%s: imported like the others" % path)
	for tree_data in _trees():
		check(GameIcons.for_tree(tree_data) != null, "%s draws its picture" % tree_data.id)
		for t in tree_data.talents:
			check(GameIcons.for_talent(t) != null, "%s draws its picture" % t.id)
	# Nothing in the map points at a Hunter talent that does not exist.
	for key: StringName in map.talents:
		if String(key).begins_with("hunter_"):
			check(Db.get_talent(key) != null, "%s is a Hunter talent" % key)


func test_the_credits_name_the_icon_authors() -> void:
	var credits := FileAccess.get_file_as_string("res://CREDITS.md")
	for author in ["Lorc", "Delapouite"]:
		check(author in credits, "%s is credited" % author)


# --- Bots --------------------------------------------------------------------------------------

func test_bot_paths_reach_every_capstone_at_point_13() -> void:
	# A fresh Hunter knows no Active / Auto ability, so every modifier waits (deferred): the bot spends the
	# 21 other points of its tree in tier order, and its 22nd point goes to the next tree's first talent
	# (TalentBot pass 1 runs over all trees before a deferred talent is allowed).
	var designed: Array = [
		times(&"hunter_packlord_keen_companion", 3) + times(&"hunter_packlord_bonded_vigor", 3)
			+ times(&"hunter_packlord_feral_tempo", 3) + times(&"hunter_packlord_piercing_whistle", 3)
			+ times(PL_CAPSTONE, 1)
			+ times(&"hunter_packlord_alpha_hide", 2) + times(&"hunter_packlord_wild_kinship", 3)
			+ times(&"hunter_packlord_kindred_instinct", 3),
		times(&"hunter_sharpshot_keen_eyes", 3) + times(&"hunter_sharpshot_heavy_shafts", 3)
			+ times(&"hunter_sharpshot_fletchers_edge", 3) + times(&"hunter_sharpshot_calm_breath", 3)
			+ times(SS_CAPSTONE, 1)
			+ times(&"hunter_sharpshot_opening_shot", 2) + times(&"hunter_sharpshot_quickening_aim", 3)
			+ times(&"hunter_sharpshot_skewering_shots", 3),
		times(&"hunter_wildcraft_trailwise", 3) + times(&"hunter_wildcraft_powder_lore", 3)
			+ times(&"hunter_wildcraft_briar_hide", 3) + times(&"hunter_wildcraft_snared_prey", 2)
			+ times(&"hunter_wildcraft_fleet_retreat", 1) + times(WC_CAPSTONE, 1)
			+ times(&"hunter_wildcraft_fleet_retreat", 2),
	]
	var capstones: Array[StringName] = [PL_CAPSTONE, SS_CAPSTONE, WC_CAPSTONE]
	var modifiers: Array[StringName] = [&"hunter_packlord_open_wound", &"hunter_sharpshot_finishing_arrow",
			&"hunter_wildcraft_brace_of_snares"]
	for i in 3:
		var path := _bot_path_ids(i)
		var want: Array[StringName] = []
		want.assign(designed[i])
		check_eq(path.slice(0, want.size()), want, "bot %d path (design_hunter 8)" % i)
		check_eq(path.find(capstones[i]), 12, "bot %d: the capstone is point 13" % i)
		check_eq(path.size(), 22, "bot %d spends all 22 points" % i)
		check(modifiers[i] not in path, "bot %d: its modifier waits for the ability" % i)
		for id in [&"hunter_wildcraft_twin_fang_grip", &"hunter_wildcraft_close_quarters"]:
			check(id not in path, "bot %d: %s is never taken with a bow" % [i, id])
	var q := _hunter(3, Vector3(0, 0, 6))
	check_eq(TalentBot.spend_all(q, 3), 22, "bot 4 wraps to Packlord and spends 22")
	check_eq(q.talents.tree_points(&"hunter_packlord"), 21, "21 of them in Packlord (the modifier waits)")
	check_eq(q.talents.ranks.get(PL_CAPSTONE, 0), 1, "the capstone is in")


func test_a_bot_that_knows_the_ability_takes_the_modifier_at_point_seven() -> void:
	var cases := [
		[0, &"hunt_signal", &"hunter_packlord_open_wound", PL_CAPSTONE, &"hunter_packlord", 22],
		[1, &"long_shot", &"hunter_sharpshot_finishing_arrow", SS_CAPSTONE, &"hunter_sharpshot", 22],
		# A bow: Twin Fang Grip and Close Quarters (6 points) wait for a weapon that never comes.
		[2, &"blast_snare", &"hunter_wildcraft_brace_of_snares", WC_CAPSTONE, &"hunter_wildcraft", 16],
	]
	for c: Array in cases:
		var p := _hunter(c[0], Vector3(c[0] * 6.0, 0, 0))
		_learn(p, c[1])
		var path := bot_path(p, c[0])
		check_eq(path.find(c[2]), 6, "bot %d: %s is point 7" % [c[0], c[2]])
		check_eq(path.find(c[3]), 12, "bot %d: the capstone is point 13" % c[0])
		check_eq(p.talents.tree_points(c[4]), c[5], "bot %d: points in its own tree" % c[0])
		check_eq(path.size(), 22, "bot %d spends all 22 points" % c[0])


func test_a_bow_bot_defers_the_weapon_bound_talents_but_still_reaches_the_wildcraft_capstone() -> void:
	var p := _hunter(2)
	check(p.main_hand.weapon_type == &"bow", "a bow")
	check(TalentBot.is_deferred(p, Db.get_talent(&"hunter_wildcraft_twin_fang_grip")), "Twin Fang Grip is deferred")
	check(TalentBot.is_deferred(p, Db.get_talent(&"hunter_wildcraft_close_quarters")), "Close Quarters is deferred")
	check(TalentBot.is_deferred(p, Db.get_talent(&"hunter_wildcraft_brace_of_snares")), "Brace of Snares waits for Blast Snare")
	for id in [&"hunter_wildcraft_trailwise", &"hunter_wildcraft_powder_lore", &"hunter_wildcraft_briar_hide",
			&"hunter_wildcraft_snared_prey", &"hunter_wildcraft_fleet_retreat", &"hunter_packlord_alpha_hide",
			&"hunter_sharpshot_opening_shot"]:
		check(not TalentBot.is_deferred(p, Db.get_talent(id)), "%s works with any weapon" % id)
	var path := bot_path(p, 2)
	check_eq(path.find(WC_CAPSTONE), 12, "the capstone is still point 13 for a bow")
	check_eq(path.find(&"hunter_wildcraft_twin_fang_grip"), -1, "Twin Fang Grip is not taken at all")
	check_eq(path.count(&"hunter_wildcraft_fleet_retreat"), 3, "Fleet Retreat is the Wildcraft talent that opens the capstone")


func test_a_dual_wielding_bot_takes_twin_fang_grip_early() -> void:
	var p := _hunter(2)
	_wield(p, &"sword", &"dagger")
	check(not TalentBot.is_deferred(p, Db.get_talent(&"hunter_wildcraft_twin_fang_grip")), "not deferred")
	check(not TalentBot.is_deferred(p, Db.get_talent(&"hunter_wildcraft_close_quarters")), "a melee main hand: not deferred")
	var path := bot_path(p, 2)
	check_eq(path.find(&"hunter_wildcraft_twin_fang_grip"), 6, "Twin Fang Grip right after tier 1 (points 7-9)")
	check_eq(path.find(WC_CAPSTONE), 12, "the capstone is point 13")
	check_eq(path.size(), 22, "the whole tree")
