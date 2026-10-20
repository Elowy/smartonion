extends TestCase
## Hunter (M8, GDD 3.7) – class data, the Focus resource, the eight abilities' data (kinds, params,
## Rank III / Rank V mods, texts, icons) and the wiring of Mastery, companion choice and kit helpers.
## Behaviour: test_class_hunter_abilities.gd, test_class_hunter_companion.gd, test_class_hunter_bots.gd;
## the look: test_class_hunter_look.gd.

const Fakes := preload("res://tests/player_fakes.gd")
const DT := 1.0 / 60.0
const CORE: Array[StringName] = [&"arrow_fan", &"backstep"]
const ACTIVES: Array[StringName] = [&"long_shot", &"arrow_hail", &"quick_draw", &"play_dead"]
const AUTOS: Array[StringName] = [&"blast_snare", &"hunt_signal"]
## Params every ability has through AbilityRunner.params_for.
const RUNNER_PARAMS: Array[String] = ["cooldown", "cost", "charges", "power"]
## Cooldowns of the design table (seconds).
const COOLDOWNS := {&"arrow_fan": 0.0, &"backstep": 8.0, &"long_shot": 9.0, &"arrow_hail": 12.0,
	&"quick_draw": 16.0, &"play_dead": 20.0, &"blast_snare": 8.0, &"hunt_signal": 10.0}

var world: Node3D
var hunter: Player


func before_each() -> void:
	PlayerManager.clear()
	RunState.start_run(1, 31)
	world = Fakes.make_world(tree)
	hunter = Fakes.spawn_player(world, 0, &"hunter")


func after_each() -> void:
	Fakes.free_world(world)
	world = null
	hunter = null
	PlayerManager.clear()
	EnemyGrid.mark_dirty()


func _all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.append_array(CORE)
	out.append_array(ACTIVES)
	out.append_array(AUTOS)
	return out


# --- Class data -------------------------------------------------------------------------------

func test_class_wiring() -> void:
	var c := Db.get_class_data(&"hunter")
	check(c != null, "the Hunter is a class of the game")
	check(&"hunter" in Db.class_ids, "in the class list")
	check_eq(c.display_name, "Hunter", "name")
	check_eq(c.armor_type, ClassData.ArmorType.MAIL, "Mail")
	check_eq(c.primary_stat, Stats.AGILITY, "Agility")
	check_eq(c.base_stats, {Stats.AGILITY: 2.0, Stats.STAMINA: -3.0}, "+2 Agility, -3 Stamina (Max HP)")
	check(c.main_hand != null and c.main_hand.weapon_type == &"bow", "starts with a bow")
	check(c.off_hand == null, "nothing in the off hand")
	var wanted: Array[StringName] = [&"bow", &"gun", &"crossbow", &"polearm", &"axe", &"sword", &"dagger", &"dual_wield"]
	check_eq(c.proficiencies, wanted, "proficiencies")
	check(c.can_dual_wield(), "may dual wield")
	check_eq(c.resource_type, &"focus", "resource type")
	check_eq(c.resources.size(), 1, "one resource")
	check_eq(c.resources[0].id, &"focus", "Focus")
	check_eq(c.abilities.size(), 2, "two core abilities")
	check_eq(c.abilities[0].id, &"arrow_fan", "RT")
	check_eq(c.abilities[1].id, &"backstep", "LT")
	check(c.mastery != null and c.mastery.can_instantiate(), "a Mastery script")
	check(c.mastery_text.begins_with("Beastbond"), "Mastery text")
	check_eq(c.companion_choices, [&"wolf", &"boar", &"owl"] as Array[StringName], "three companions")
	check_eq(c.default_companion(), &"wolf", "the Wolf is the default")
	check_eq(c.headgear, &"hunter_hat", "headgear id")
	check(not c.big_shoulders, "no big shoulders")
	check(c.onion_color.is_equal_approx(Color(0.74, 0.46, 0.27)), "copper-brown shallot")
	check(c.accent_color != Db.get_class_data(&"rogue").accent_color, "an accent of its own")
	check(c.description != "" and c.role != "", "lobby texts")
	for a in c.abilities:
		check(a.effect != null and a.effect.can_instantiate(), "%s has an effect script" % a.id)


func test_the_runner_builds_the_kit() -> void:
	check_eq(hunter.abilities.resource_order, [&"focus"] as Array[StringName], "Focus only")
	check(hunter.abilities.mastery is HunterMastery, "the Mastery")
	check_eq(hunter.abilities.slots[0].id, &"arrow_fan", "RT slot")
	check_eq(hunter.abilities.slots[1].id, &"backstep", "LT slot")
	check_eq(hunter.class_data.id, &"hunter", "class")
	check_eq(hunter.main_hand.weapon_type, &"bow", "the bow in the hand")
	check_eq(hunter.companion_id, &"wolf", "the Wolf without a lobby pick")


func test_the_lobby_text_of_the_mastery_fits() -> void:
	# Same budget as every class: the lobby card shows the Mastery in three lines (test_ui_m3_lobby).
	var longest := 0
	for id in Db.class_ids:
		longest = maxi(longest, Db.get_class_data(id).mastery_text.length())
	check(Db.get_class_data(&"hunter").mastery_text.length() <= longest, "no longer than the longest shipped text")
	check(Db.get_class_data(&"hunter").mastery_text.length() <= 150, "within the lobby card's three lines")


func test_class_data_is_a_hunter_kit_with_two_core_and_six_learned_abilities() -> void:
	var core := 0
	var learned := 0
	for id in Db.abilities:
		var a := Db.abilities[id]
		if a.class_id != &"hunter":
			continue
		if a.kind == AbilityData.Kind.CORE:
			core += 1
		else:
			learned += 1
	check_eq(core, 2, "two core abilities")
	check_eq(learned, 6, "six learned abilities")
	var pool := Db.ability_pool(&"hunter")
	for id in ACTIVES + AUTOS:
		check(Db.get_ability(id) in pool, "%s is on the cards" % id)
	for id in CORE:
		check(not Db.get_ability(id) in pool, "%s (core) is not" % id)
	for id in _all_ids():
		check(Db.get_ability(id) != null, "%s exists" % id)
		check(not Db.ability_pool(&"mage").has(Db.get_ability(id)), "%s is not offered to a Mage" % id)


# --- Focus ------------------------------------------------------------------------------------

func test_focus_resource() -> void:
	var f := Db.get_class_data(&"hunter").resources[0]
	check_eq(f.display_name, "Focus", "name")
	check_eq(f.max_value, 100.0, "max")
	check_eq(f.start_value, 100.0, "starts full")
	check_eq(f.regen_per_second, 10.0, "+10 per second")
	check(f.regen_uses_haste, "regen uses Haste")
	check_eq(f.display, ResourceData.Display.BAR, "a bar")
	check(f.color.is_equal_approx(Color(0.95, 0.62, 0.22)), "amber")
	check_eq(f.gain_on_hit, 0.0, "nothing is gained by hitting")
	check_eq(f.decay_per_second, 0.0, "nothing decays")
	check_eq(UiTheme.RESOURCE_NAMES.get(&"focus"), "Focus", "UI name")


func test_focus_regen_and_haste() -> void:
	var focus := HunterKit.focus(hunter)
	check_eq(focus.value, 100.0, "full at the wave start")
	focus.set_value(0.0)
	for i in 60:
		hunter.abilities._physics_process(DT)
	check_near(focus.value, 10.0, 0.05, "+10 per second")
	hunter.stats.set_source(&"haste", {Stats.HASTE: 100.0})
	focus.set_value(0.0)
	for i in 60:
		hunter.abilities._physics_process(DT)
	check_near(focus.value, 20.0, 0.1, "Haste doubles it")
	hunter.stats.remove_source(&"haste")
	hunter.stats.set_source(&"regen", {Stats.RESOURCE_REGEN: 50.0})
	focus.set_value(0.0)
	for i in 60:
		hunter.abilities._physics_process(DT)
	check_near(focus.value, 15.0, 0.1, "Resource Regen scales it")
	focus.set_value(99.0)
	for i in 60:
		hunter.abilities._physics_process(DT)
	check_eq(focus.value, 100.0, "capped at 100")
	hunter.begin_wave()
	check_eq(focus.value, 100.0, "full again each wave")


func test_a_resource_bonus_changes_the_focus_rules() -> void:
	# Calm Breath (Sharpshot): "resource" entries name the Focus by id.
	var focus := HunterKit.focus(hunter)
	var entries: Array[Dictionary] = [{"kind": "resource", "resource": "focus", "regen_per_second_add": 5.0}]
	check_eq(BonusVocabulary.validate(entries[0], &"hunter"), "", "the entry validates")
	hunter.bonuses.set_effects(PlayerBonuses.SOURCE_TALENTS, entries)
	focus.set_value(0.0)
	for i in 60:
		hunter.abilities._physics_process(DT)
	check_near(focus.value, 15.0, 0.1, "+5 Focus per second")


# --- Ability data -----------------------------------------------------------------------------

func test_abilities_match_the_design_table() -> void:
	for id in _all_ids():
		var a := Db.get_ability(id)
		check(a != null, "%s exists" % id)
		if a == null:
			continue
		check_eq(a.class_id, &"hunter", "%s class" % id)
		check_eq(a.icon, id, "%s icon id" % id)
		check_eq(a.cooldown, float(COOLDOWNS[id]), "%s cooldown" % id)
		check(a.display_name != "" and a.description != "", "%s texts" % id)
		check(a.effect != null and a.effect.can_instantiate() and a.effect.new() is AbilityEffect, "%s effect" % id)
		check(a.card_weight > 0.0, "%s is offered on cards" % id)
		if id in CORE:
			check_eq(a.kind, AbilityData.Kind.CORE, "%s core" % id)
		elif id in ACTIVES:
			check_eq(a.kind, AbilityData.Kind.ACTIVE, "%s active" % id)
		else:
			check_eq(a.kind, AbilityData.Kind.AUTO, "%s auto-cast" % id)
	check_eq(Db.get_ability(&"arrow_fan").resource, &"focus", "Arrow Fan spends Focus")
	check_eq(Db.get_ability(&"arrow_fan").cost, 40.0, "40 Focus")
	for id in _all_ids():
		if id != &"arrow_fan":
			check(Db.get_ability(id).resource == &"" and Db.get_ability(id).cost == 0.0, "%s is free" % id)
	check_eq(Db.get_ability(&"blast_snare").school, &"fire", "Blast Snare is the one Fire ability")
	for id in _all_ids():
		if id != &"blast_snare":
			check_eq(Db.get_ability(id).school, &"physical", "%s is physical" % id)
	check(&"pet" in Db.get_ability(&"hunt_signal").tags, "Hunt Signal keeps the pet tag")
	check(&"weapon" in Db.get_ability(&"arrow_fan").tags and &"projectile" in Db.get_ability(&"arrow_fan").tags, "Arrow Fan tags")
	check(&"stealth" in Db.get_ability(&"play_dead").tags, "Play Dead is a stealth ability")
	check(&"ground" in Db.get_ability(&"arrow_hail").tags and &"ground" in Db.get_ability(&"blast_snare").tags, "ground tags")
	check_eq(Db.get_ability(&"arrow_hail").targeting, AbilityData.Targeting.DENSEST_CLUSTER, "Hail picks the densest group")
	check_eq(Db.get_ability(&"backstep").targeting, AbilityData.Targeting.SELF, "Backstep is a self cast")
	check_eq(Db.get_ability(&"long_shot").cast_range, 12.0, "Long Shot range")
	check_eq(Db.get_ability(&"arrow_fan").cast_range, 9.0, "Arrow Fan range")


func test_rank_and_spec_data_of_every_ability() -> void:
	for id in _all_ids():
		var a := Db.get_ability(id)
		check(not a.rank3.is_empty() and a.rank3_text != "", "%s Rank III" % id)
		check_eq(a.specs.size(), 2, "%s: two Rank V specs" % id)
		for key: String in a.rank3:
			_check_mod_key(a, key, "%s Rank III" % id)
		for spec in a.specs:
			check(spec.get("name", "") != "" and spec.get("text", "") != "", "%s spec texts" % id)
			var mods: Dictionary = spec.get("mods", {})
			check(not mods.is_empty(), "%s: %s has mods" % [id, spec.get("name")])
			for key: String in mods:
				_check_mod_key(a, key, "%s %s" % [id, spec.get("name")])
		# The two specs have different names.
		check(a.specs[0]["name"] != a.specs[1]["name"], "%s: distinct spec names" % id)
		var text := AbilityIcon.format_description(a, a.params)
		check(text != "" and not "{" in text, "%s: the description fills every placeholder: %s" % [id, text])


## A mod key names a param of the ability ("x_add" / "x_pct" / "x" for a param x).
func _check_mod_key(a: AbilityData, key: String, what: String) -> void:
	var bases: Array[String] = [key, key.trim_suffix("_add"), key.trim_suffix("_pct")]
	var known := false
	for base in bases:
		known = known or a.params.has(base) or base in RUNNER_PARAMS
	check(known, "%s: '%s' names a param of %s" % [what, key, a.id])


func test_ranks_apply_to_the_params() -> void:
	var runner := hunter.abilities
	var fan := Db.get_ability(&"arrow_fan")
	check_eq(runner.params_at_rank(fan, 1)["arrows"], 5, "Rank I: five arrows")
	check_eq(runner.params_at_rank(fan, 3)["arrows"], 7.0, "Rank III: +2 arrows")
	check_near(runner.params_at_rank(fan, 2)["power"], 1.25, 0.001, "Rank II power")
	check_near(runner.params_at_rank(fan, 4)["power"], 1.5, 0.001, "Rank IV power")
	check_eq(runner.params_at_rank(fan, 5, 0)["pierce"], 1.0, "Skewering Fan: pierce")
	check_eq(runner.params_at_rank(fan, 5, 0)["range"], 14.0, "and range")
	check_eq(runner.params_at_rank(fan, 5, 1)["volleys"], 2.0, "Echo Draw: a second volley")
	var step := Db.get_ability(&"backstep")
	check_eq(runner.params_at_rank(step, 3)["charges"], 2.0, "Backstep Rank III: two charges")
	check_eq(runner.params_at_rank(step, 5, 0)["trail_duration"], 3.0, "Caltrop Trail")
	check_eq(runner.params_at_rank(step, 5, 1)["volley_arrows"], 3.0, "Parting Volley")
	var shot := Db.get_ability(&"long_shot")
	check_eq(runner.params_at_rank(shot, 3)["arrows"], 2.0, "Long Shot Rank III: two arrows")
	check_eq(runner.params_at_rank(shot, 5, 0)["windup"], 0.0, "Snap Shot: no aiming")
	check_near(runner.params_at_rank(shot, 5, 0)["cooldown"], 9.0 * 0.8 * 0.7, 0.001, "and 30% off the Rank IV cooldown")
	check_eq(runner.params_at_rank(shot, 5, 1)["bleed_pct"], 80.0, "Rending Shaft")
	var hail := Db.get_ability(&"arrow_hail")
	check_eq(runner.params_at_rank(hail, 3)["radius"], 4.0, "Hail Rank III: +1 m")
	check_eq(runner.params_at_rank(hail, 5, 0)["storms"], 2.0, "Crossfire Barrage")
	check_eq(runner.params_at_rank(hail, 5, 1)["slow"], 40.0, "Pinning Hail")
	var draw := Db.get_ability(&"quick_draw")
	check_eq(runner.params_at_rank(draw, 3)["pierce"], 1.0, "Quick Draw Rank III: pierce")
	check_eq(runner.params_at_rank(draw, 5, 0)["extra_arrows"], 2.0, "Hail of Shafts")
	check_eq(runner.params_at_rank(draw, 5, 1)["focus_gain"], 35.0, "Focus Rush")
	var dead := Db.get_ability(&"play_dead")
	check_eq(runner.params_at_rank(dead, 3)["decoy_radius"], 4.0, "Play Dead Rank III: the decoy")
	check_eq(runner.params_at_rank(dead, 5, 0)["forced_crits"], 3.0, "Patient Predator")
	check_eq(runner.params_at_rank(dead, 5, 1)["heal_max_hp_pct"], 30.0, "Rest and Recover")
	var snare := Db.get_ability(&"blast_snare")
	check_eq(runner.params_at_rank(snare, 3)["radius"], 3.5, "Snare Rank III: +1 m")
	check_eq(runner.params_at_rank(snare, 5, 0)["slow"], 60.0, "Clinging Net")
	check_eq(runner.params_at_rank(snare, 5, 1)["damage_pct"], 320.0, "Heavy Charge: +100%")
	check_near(runner.params_at_rank(snare, 5, 1)["arm_time"], 1.0, 0.001, "and a longer arming time")
	var signal_ := Db.get_ability(&"hunt_signal")
	check_eq(runner.params_at_rank(signal_, 3)["strikes"], 2.0, "Hunt Signal Rank III: a second strike")
	check_eq(runner.params_at_rank(signal_, 5, 0)["splash_radius"], 2.5, "Mauling Rush")
	check_eq(runner.params_at_rank(signal_, 5, 1)["kill_reset"], 2.0, "Relentless Pursuit")


func test_every_param_a_talent_or_item_names_exists_with_its_neutral_value() -> void:
	# The later packages (talents, items, sets) mod these keys: they must exist and be neutral (0) where
	# the design says so.
	var neutral := {
		&"blast_snare": ["ember_duration", "ember_pct", "scatter", "slow"],
		&"hunt_signal": ["bleed_pct", "kill_reset", "splash_radius"],
		&"long_shot": ["execute_bonus", "bleed_pct"],
		&"backstep": ["trail_duration", "volley_arrows"],
		&"play_dead": ["decoy_radius", "heal_max_hp_pct", "forced_crits"],
		&"quick_draw": ["pierce", "extra_arrows", "focus_gain"],
		&"arrow_hail": ["slow"],
		&"arrow_fan": ["pierce"],
	}
	for id: StringName in neutral:
		for key: String in neutral[id]:
			var params := Db.get_ability(id).params
			check(params.has(key), "%s has %s" % [id, key])
			check_eq(float(params.get(key, 1.0)), 0.0, "%s: %s is neutral" % [id, key])
	check(Db.get_ability(&"blast_snare").params.has("traps") and Db.get_ability(&"blast_snare").params.has("max_traps"), "snare counts")
	for key: String in ["haste", "heal_pct", "damage_bonus"]:
		check(HunterCompanion.BASE_PARAMS.has(key), "the companion has %s" % key)
		check_eq(float(HunterCompanion.BASE_PARAMS[key]), 0.0, "and it is neutral")


func test_every_hunter_ability_has_an_icon_and_a_glyph() -> void:
	var map := GameIcons.icon_map()
	var seen: Array[String] = []
	for id in _all_ids():
		var a := Db.get_ability(id)
		check(map.abilities.has(a.icon), "%s: an entry in the icon map" % id)
		var path := String(map.abilities.get(a.icon, ""))
		check(path.begins_with("res://assets/icons/") and ResourceLoader.exists(path), "%s: the svg exists" % id)
		check(not path in seen, "%s: its own picture" % id)
		seen.append(path)
		check(GameIcons.for_ability(a) != null, "%s: a picture" % id)
		check(AbilityIcon.EXACT_GLYPHS.has(id), "%s: a glyph in the exact table" % id)
		check(AbilityIcon.glyph_for_ability(a) != AbilityIcon.Glyph.GENERIC, "%s: a real glyph" % id)


func test_ability_names_are_unique_and_clean() -> void:
	var hunter_names: Array[String] = []
	for id in _all_ids():
		var a := Db.get_ability(id)
		hunter_names.append(a.display_name)
		for s in a.specs:
			hunter_names.append(s["name"])
	var seen: Dictionary[String, bool] = {}
	for n in hunter_names:
		check(not seen.has(n), "'%s' is used once among the Hunter's names" % n)
		seen[n] = true
	for id in Db.abilities:
		var a := Db.abilities[id]
		if a.class_id == &"hunter":
			continue
		check(a.display_name not in hunter_names, "the Hunter's '%s' clashes with %s" % [a.display_name, id])
		for s in a.specs:
			check(s["name"] not in hunter_names, "the Hunter's '%s' clashes with a spec of %s" % [s["name"], id])


# --- Wiring -----------------------------------------------------------------------------------

func test_the_pseudo_id_of_the_companion_validates_for_the_hunter_only() -> void:
	var entry := {"kind": "ability", "match": {"id": "hunter_companion"}, "mods": {"damage_bonus_add": 30.0, "haste_add": 10.0}}
	check_eq(BonusVocabulary.validate(entry, &"hunter"), "", "valid for the Hunter")
	check(BonusVocabulary.validate(entry, &"warrior") != "", "refused for another class")
	check(not Db.abilities.has(&"hunter_companion"), "it is no ability")


func test_a_class_item_style_mod_changes_the_ability_params() -> void:
	# Item mods ("Equip: ...") go through Player.ability_mods: the keys the design names exist.
	var entries: Array[Dictionary] = [{"kind": "ability", "match": {"id": "arrow_fan"}, "mods": {"arrows_add": 2.0}},
			{"kind": "ability", "match": {"id": "hunter_companion"}, "mods": {"damage_bonus_add": 30.0}}]
	for e in entries:
		check_eq(BonusVocabulary.validate(e, &"hunter"), "", "the entry validates")
	hunter.bonuses.set_effects(PlayerBonuses.SOURCE_TALENTS, entries)
	check_eq(hunter.abilities.params_for(Db.get_ability(&"arrow_fan"))["arrows"], 7.0, "+2 arrows")
	check_eq(hunter.ability_mods(&"hunter_companion").get("damage_bonus_add"), 30.0, "the companion's mods reach the pseudo ability")
