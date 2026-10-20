extends TestCase
## M9 SEASONINGS: the 56 Seasonings (per-class ability side-grades) – data validity, a behaviour probe per
## Seasoning (the mod really changes what the ability reads when it is cast), the "seasoning" bonus source and its
## ownership / slot rules, the level-up card weight, the --seasonings flag, the lobby picker and its persistence,
## and the dev profile staying untouched.

const Fakes := preload("res://tests/player_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")

## Rows per class (the design: T1, T1, T2, T3, T4, T5, A, AA).
const PER_CLASS := 8
const TIER_PATTERN: Array[StringName] = [&"t1", &"t1", &"t2", &"t3", &"t4", &"t5", &"a", &"aa"]

var world: Node3D
var hero: Player
var _saved_profile: Profile
var _saved_path := ""
var _saved_persist := false
var _nodes: Array[Node] = []


func before_each() -> void:
	_saved_profile = Meta.profile
	_saved_path = Meta.path
	_saved_persist = Meta.persist
	PlayerManager.clear()
	RunState.start_run(1, 43)
	world = Fakes.make_world(tree)


func after_each() -> void:
	for n in _nodes:
		UiFakes.free_node(n)
	_nodes.clear()
	Fakes.free_world(world)
	world = null
	hero = null
	Meta.profile = _saved_profile
	Meta.path = _saved_path
	Meta.persist = _saved_persist
	PlayerManager.clear()
	UiFakes.reset_players()
	EnemyGrid.mark_dirty()


# --- Helpers ------------------------------------------------------------------------------------------

func _all() -> Array[SeasoningData]:
	var out: Array[SeasoningData] = []
	for id in Db.seasonings:
		out.append(Db.seasonings[id])
	return out


func _use_fresh() -> Profile:
	Meta.profile = Profile.fresh()
	Meta.persist = false
	Meta.path = ""
	return Meta.profile


func _hero(class_id: StringName, index: int = 0) -> Player:
	hero = Fakes.spawn_player(world, index, class_id)
	hero.stats.set_source(&"test", {Stats.CRIT: -500.0, Stats.DODGE: -500.0})
	return hero


## Learns [param id] and nothing else of the learned kinds (a class has two Active slots, four Auto ones).
func _learn_only(p: Player, id: StringName) -> void:
	var a := Db.get_ability(id)
	if a == null or not a.is_learned_kind():
		return
	for i in range(AbilityRunner.CORE_SLOTS, AbilityRunner.MAX_SLOTS):
		if p.abilities.slots[i] != null:
			p.abilities.forget(i)
	check(p.abilities.learn(a) >= 0, "%s is learned" % id)


func _rows(class_id: StringName) -> Array[SeasoningData]:
	return Db.seasonings_for_class(class_id)


# --- Data ---------------------------------------------------------------------------------------------

func test_there_are_56_seasonings_eight_per_class() -> void:
	check_eq(Db.seasonings.size(), 56, "56 Seasonings")
	for cid in Db.class_ids:
		var rows := _rows(cid)
		check_eq(rows.size(), PER_CLASS, "%s has eight" % cid)
		for i in mini(rows.size(), PER_CLASS):
			check_eq(rows[i].tier, TIER_PATTERN[i], "%s #%d is tier %s" % [cid, i + 1, TIER_PATTERN[i]])


func test_every_seasoning_is_valid_data() -> void:
	var seen_ids := {}
	var seen_names := {}
	for s in _all():
		for problem in s.problems(seen_ids, seen_names):
			check(false, problem)
	check_eq(seen_ids.size(), 56, "56 distinct ids")
	check_eq(seen_names.size(), 56, "56 distinct names")


func test_a_bad_seasoning_is_reported() -> void:
	var s := Db.get_seasoning(&"ssn_smoked_paprika").duplicate() as SeasoningData
	check(s.problems().is_empty(), "the copy of a good one is valid")
	var bad := s.duplicate() as SeasoningData
	bad.entries = [{"kind": "ability", "match": {"id": "whirlwind"}, "mods": {"no_such_param_add": 3}}]
	check(not bad.problems().is_empty(), "a mod of a param the ability lacks")
	bad = s.duplicate() as SeasoningData
	bad.class_id = &"mage"
	check(not bad.problems().is_empty(), "a Warrior ability on a Mage Seasoning")
	bad = s.duplicate() as SeasoningData
	bad.ability = &"fireball"
	bad.entries = [{"kind": "ability", "match": {"id": "fireball"}, "mods": {"burn_pct_add": 5}, "requires": {"knows": "fireball"}}]
	check(not bad.problems().is_empty(), "a Mage ability on a Warrior Seasoning")
	bad = s.duplicate() as SeasoningData
	bad.id = &"smoked_paprika"
	check(not bad.problems().is_empty(), "an id without the ssn_ prefix")
	bad = s.duplicate() as SeasoningData
	bad.tier = &"t9"
	check(not bad.problems().is_empty(), "an unknown tier")
	bad = s.duplicate() as SeasoningData
	bad.ability = &"execute"
	bad.entries = [{"kind": "ability", "match": {"id": "execute"}, "mods": {"threshold_add": 5}}]
	check(not bad.problems().is_empty(), "a learnable ability without requires.knows")
	bad = s.duplicate() as SeasoningData
	bad.entries = []
	check(not bad.problems().is_empty(), "no entries")
	check(not Db.get_seasoning(&"ssn_smoked_paprika").problems({&"ssn_smoked_paprika": true}).is_empty(), "a duplicate id")


func test_tier_prices_levels_and_hints() -> void:
	var s := Db.get_seasoning(&"ssn_smoked_paprika")
	check_eq(s.price(), 60, "T1 costs 60 Seeds")
	check_eq(s.unlock_level(), 3, "T1 at Class Level 3")
	check_eq(Db.get_seasoning(&"ssn_cayenne_rush").price(), 80, "T2")
	check_eq(Db.get_seasoning(&"ssn_cayenne_rush").unlock_level(), 6, "T2 level")
	check_eq(Db.get_seasoning(&"ssn_bay_leaf").unlock_level(), 9, "T3 level")
	check_eq(Db.get_seasoning(&"ssn_horseradish_kick").unlock_level(), 13, "T4 level")
	check_eq(Db.get_seasoning(&"ssn_sea_salt").unlock_level(), 17, "T5 level")
	var a := Db.get_seasoning(&"ssn_black_garlic")
	check_eq([a.price(), a.unlock_level(), a.unlock_achievement()], [160, 0, &"ach_clear_warrior"], "tier A: an achievement, 160 Seeds")
	var aa := Db.get_seasoning(&"ssn_ginger_snap")
	check_eq([aa.price(), aa.unlock_level(), aa.unlock_achievement()], [240, 0, &"ach_pungent_warrior"], "tier AA")
	check(s.unlock_hint().contains("Warrior Level 3") and s.unlock_hint().contains("60 Seeds"), "T1 hint: " + s.unlock_hint())
	check(a.unlock_hint().contains("Win a run") and a.unlock_hint().contains("160"), "A hint: " + a.unlock_hint())
	check(aa.unlock_hint().contains("Pungent"), "AA hint: " + aa.unlock_hint())
	var total := 0
	for cid in Db.class_ids:
		for r in _rows(cid):
			if cid == &"warrior":
				total += r.price()
	check_eq(total, 1020, "one class costs 1020 Seeds in all (design §2)")


func test_targets_and_icons() -> void:
	for s in _all():
		check(s.icon_ability() != null, "%s has an icon ability" % s.id)
		check(s.target_name() != "", "%s names its target" % s.id)
	var wolf := Db.get_seasoning(&"ssn_wild_garlic")
	check(wolf.is_pseudo() and wolf.target_ability() == null, "the companion Seasoning targets a pseudo id")
	check_eq(wolf.target_name(), "Companion", "named Companion")
	check_eq(Db.get_seasoning(&"ssn_sweet_basil").target_name(), "Storm Echo", "named Storm Echo")
	check_eq(Db.get_seasoning(&"ssn_smoked_paprika").target_name(), "Whirlwind", "the ability's own name")
	check(Db.get_seasoning(&"ssn_horseradish_kick").is_dormant_until_learned(), "Execute must be learned first")
	check(not Db.get_seasoning(&"ssn_smoked_paprika").is_dormant_until_learned(), "Whirlwind is a core ability")


# --- Behaviour probes: the mods change what the ability reads -----------------------------------------

## Scripts besides the effect that read an ability's params (pets, totems, areas the effect hands them to).
const HELPER_SCRIPTS: Dictionary[StringName, Array] = {
	&"fireball": ["res://scenes/abilities/mage/mage_spell.gd"],
	&"arcane_missiles": ["res://scenes/abilities/mage/mage_spell.gd"],
	&"corruption": ["res://scenes/abilities/warlock/warlock_spell.gd"],
	&"seed_of_corruption": ["res://scenes/abilities/warlock/warlock_spell.gd"],
	&"summon_voidwalker": ["res://scenes/abilities/warlock/voidwalker.gd", "res://scenes/abilities/warlock/warlock_spell.gd"],
	&"summon_infernal": ["res://scenes/abilities/warlock/infernal.gd", "res://scenes/abilities/warlock/warlock_spell.gd"],
	&"totem_rite": ["res://scenes/abilities/shaman/shaman_totem.gd", "res://scenes/abilities/shaman/shaman_kit.gd"],
	&"thunderbolt": ["res://scenes/abilities/shaman/shaman_kit.gd"],
	&"stormburst": ["res://scenes/abilities/shaman/shaman_kit.gd"],
}
## Mod keys the AbilityRunner itself reads (cooldown, cost, charges) or that scale the shared "power".
const RUNNER_KEYS: Array[String] = ["cooldown", "cost", "charges"]


## The numbers the target of [param s] reads right now: the ability's params, or the live kit's numbers for a pseudo
## target (the companion of [param kind], Storm Echo).
func _numbers(p: Player, s: SeasoningData, kind: StringName = &"wolf") -> Dictionary:
	match s.ability:
		&"hunter_companion":
			var m := p.abilities.mastery as HunterMastery
			if m.has_companion() and m.companion.kind != kind:
				m.companion.free()
				m.companion = null
			p.companion_id = kind
			return m.ensure_companion().current_params().duplicate()
		&"shaman_echo":
			var sm := p.abilities.mastery as ShamanMastery
			sm.invalidate_echo_params()
			return sm.echo_params().duplicate()
	return p.abilities.params_for(Db.get_ability(s.ability)).duplicate()


## What one mod key must do to [param before] (AbilityRunner.apply_mods): returns [param, expected value].
func _expected(key: String, v: Variant, before: Dictionary) -> Array:
	var numeric := typeof(v) in [TYPE_INT, TYPE_FLOAT]
	if key.ends_with("_add") and numeric:
		var base := key.trim_suffix("_add")
		return [base, float(before.get(base, 0.0)) + float(v)]
	if key.ends_with("_pct") and numeric and before.has(key.trim_suffix("_pct")):
		var base := key.trim_suffix("_pct")
		return [base, float(before[base]) * (1.0 + float(v) / 100.0)]
	return [key, v]


func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(a), float(b))
	return a == b


## The source text of the scripts that read [param s]'s ability numbers.
func _sources(s: SeasoningData) -> String:
	var paths: Array[String] = []
	var a := s.target_ability()
	if a != null and a.effect != null:
		paths.append(a.effect.resource_path)
	elif s.ability == &"hunter_companion":
		paths.append("res://scenes/abilities/hunter/hunter_companion.gd")
	elif s.ability == &"shaman_echo":
		paths.append("res://scenes/abilities/shaman/shaman_mastery.gd")
	for extra: Variant in HELPER_SCRIPTS.get(s.ability, []):
		paths.append(str(extra))
	var text := ""
	for path in paths:
		text += _code_only(FileAccess.get_file_as_string(path)) + "\n"
	return text


## [param source] without its comments (a "#" outside a string literal ends the line's code).
func _code_only(source: String) -> String:
	var out := PackedStringArray()
	for line in source.split("\n"):
		var in_string := false
		var cut := line.length()
		for i in line.length():
			var c := line[i]
			if c == "\"" and (i == 0 or line[i - 1] != "\\"):
				in_string = not in_string
			elif c == "#" and not in_string:
				cut = i
				break
		out.append(line.substr(0, cut))
	return "\n".join(out)


## One Seasoning: before / after the source is set, every mod moves its number as AbilityRunner.apply_mods says
## and is not a no-op, and the ability's code reads that number.
func _probe(p: Player, s: SeasoningData, kind: StringName = &"wolf") -> int:
	p.bonuses.set_effects(Seasonings.SOURCE, [] as Array[Dictionary])
	_learn_only(p, s.ability)
	var before := _numbers(p, s, kind)
	p.bonuses.set_effects(Seasonings.SOURCE, Seasonings.effects_for([s] as Array[SeasoningData]))
	var after := _numbers(p, s, kind)
	var mods: Dictionary = s.entries[0]["mods"]
	var source := _sources(s)
	var probed := 0
	for key: String in mods:
		var want := _expected(key, mods[key], before)
		var param: String = want[0]
		var label := "%s (%s) %s" % [s.id, s.ability, key]
		check(after.has(param), "%s: the resolved params have '%s'" % [label, param])
		check(_same(after.get(param), want[1]), "%s: %s should be %s, is %s" % [label, param, str(want[1]), str(after.get(param))])
		check(not _same(before.get(param, 0.0 if key.ends_with("_add") else null), want[1]), "%s: the mod changes nothing (%s stays %s)" % [label, param, str(before.get(param))])
		if param == "power":
			check(source.contains("\"power\"") or source.contains("power("), "%s: the code never reads the rank power" % label)
		elif param not in RUNNER_KEYS:
			check(source.contains("\"%s\"" % param), "%s: no script reads the param '%s'" % [label, param])
		probed += 1
	p.bonuses.set_effects(Seasonings.SOURCE, [] as Array[Dictionary])
	return probed


func _probe_class(class_id: StringName) -> void:
	var p := _hero(class_id)
	var rows := _rows(class_id)
	check_eq(rows.size(), PER_CLASS, "%s rows" % class_id)
	var probed := 0
	for s in rows:
		if s.ability == &"hunter_companion":
			# Every companion (wolf, boar, owl) must feel the mod.
			for kind: StringName in [&"wolf", &"boar", &"owl"]:
				probed += _probe(p, s, kind)
		else:
			probed += _probe(p, s)
	check(probed >= PER_CLASS * 2, "%s: %d mods probed" % [class_id, probed])


func test_probe_warrior_seasonings() -> void:
	_probe_class(&"warrior")


func test_probe_mage_seasonings() -> void:
	_probe_class(&"mage")


func test_probe_paladin_seasonings() -> void:
	_probe_class(&"paladin")


func test_probe_rogue_seasonings() -> void:
	_probe_class(&"rogue")


func test_probe_warlock_seasonings() -> void:
	_probe_class(&"warlock")


func test_probe_hunter_seasonings() -> void:
	_probe_class(&"hunter")


func test_probe_shaman_seasonings() -> void:
	_probe_class(&"shaman")


# --- Applying them at run start -----------------------------------------------------------------------

func _slot(class_id: StringName, ids: Array = [], index: int = 0) -> PlayerSlot:
	var slot := Fakes.make_slot(index, class_id)
	for id: Variant in ids:
		slot.seasonings.append(StringName(str(id)))
	return slot


func _create(slot: PlayerSlot) -> Player:
	var p := Player.create(slot)
	world.add_child(p)
	hero = p
	return p


func test_picked_seasonings_become_the_seasoning_source() -> void:
	var p := _create(_slot(&"warrior", ["ssn_smoked_paprika"]))
	check_eq(p.seasonings, [&"ssn_smoked_paprika"] as Array[StringName], "the hero carries it")
	var entries := p.bonuses.effects_of(Seasonings.SOURCE)
	check_eq(entries.size(), 1, "one entry in the source")
	check_eq(entries[0].get("id"), "ssn_smoked_paprika", "tagged with the Seasoning's id")
	check_eq(entries[0].get("label"), "Smoked Paprika", "and its name")
	var whirlwind := Db.get_ability(&"whirlwind")
	var params := p.abilities.params_for(whirlwind)
	check_eq(params["slow"], 35.0, "Whirlwind slows")
	check_eq(params["slow_duration"], 2.0, "for 2 sec")
	check_eq(params["cost"], 48.0, "and costs 8 more Rage")
	check_eq(p.ability_mods(&"whirlwind").get("cost_add"), 8.0, "Player.ability_mods merges the source")


func test_without_a_selection_nothing_changes() -> void:
	var p := _create(_slot(&"warrior"))
	check(p.seasonings.is_empty(), "no Seasonings")
	check(p.bonuses.effects_of(Seasonings.SOURCE).is_empty(), "no source at all")
	var plain := Player.create(_slot(&"warrior", [], 1))
	world.add_child(plain)
	var whirlwind := Db.get_ability(&"whirlwind")
	check_eq(p.abilities.params_for(whirlwind), plain.abilities.params_for(whirlwind), "the ability params are the base ones")
	check(p.ability_mods(&"whirlwind").is_empty(), "no ability mods")


func test_two_seasonings_of_one_ability_stack() -> void:
	var p := _create(_slot(&"warrior", ["ssn_smoked_paprika", "ssn_cracked_pepper"]))
	var params := p.abilities.params_for(Db.get_ability(&"whirlwind"))
	check_eq(params["slow"], 35.0, "the slow of the first")
	check_near(float(params["damage_pct"]), 190.0, 0.001, "the damage of the second")
	check_near(float(params["radius"]), 2.4, 0.001, "and its smaller reach")
	check_eq(params["cost"], 48.0, "the cost of the first")


func test_a_learnable_seasoning_waits_until_the_ability_is_learned() -> void:
	var p := _create(_slot(&"warrior", ["ssn_horseradish_kick"]))
	check(p.bonuses.ability_mods_for(&"execute").is_empty(), "dormant before Execute is learned")
	var execute := Db.get_ability(&"execute")
	check(p.abilities.learn(execute) >= 0, "Execute is learned")
	var params := p.abilities.params_for(execute)
	check_eq(params["threshold"], 30.0, "now it finishes enemies below 30%")
	check_eq(params["damage_pct"], 200.0, "for a weaker strike")
	p.abilities.forget(p.abilities.slot_of(&"execute"))
	check(p.bonuses.ability_mods_for(&"execute").is_empty(), "dormant again once it is forgotten")


func test_a_hero_carries_only_what_its_class_can() -> void:
	var p := _create(_slot(&"warrior", ["ssn_cinnamon_stick", "ssn_smoked_paprika", "ssn_no_such_thing", "ssn_smoked_paprika"]))
	check_eq(p.seasonings, [&"ssn_smoked_paprika"] as Array[StringName], "a Mage Seasoning, an unknown id and a repeat are dropped")


func test_a_real_profile_carries_only_owned_seasonings_within_its_slots() -> void:
	var profile := _use_fresh()
	profile.unlock(Profile.KIND_SEASONING, &"ssn_smoked_paprika")
	profile.unlock(Profile.KIND_SEASONING, &"ssn_cracked_pepper")
	profile.unlock(Profile.KIND_SEASONING, &"ssn_cayenne_rush")
	var ids := ["ssn_bay_leaf", "ssn_smoked_paprika", "ssn_cracked_pepper", "ssn_cayenne_rush"]
	profile.set_class_progress(&"warrior", 0, 2)
	check(_create(_slot(&"warrior", ids)).seasonings.is_empty(), "Class Level 2: no slot yet")
	profile.set_class_progress(&"warrior", 215, 3)
	check_eq(_create(_slot(&"warrior", ids, 1)).seasonings, [&"ssn_smoked_paprika"] as Array[StringName], "Level 3: one slot (the unowned Bay Leaf is skipped, not counted)")
	profile.set_class_progress(&"warrior", 2175, 10)
	check_eq(_create(_slot(&"warrior", ids, 2)).seasonings, [&"ssn_smoked_paprika", &"ssn_cracked_pepper"] as Array[StringName], "Level 10: two slots")
	profile.set_class_progress(&"warrior", 11335, 20)
	check_eq(_create(_slot(&"warrior", ids, 3)).seasonings.size(), 3, "Level 20: three slots")


func test_slot_levels() -> void:
	var expected := {1: 0, 2: 0, 3: 1, 9: 1, 10: 2, 19: 2, 20: 3, 30: 3}
	for level: int in expected:
		check_eq(Seasonings.slots_for_level(level), expected[level], "Class Level %d" % level)
	check_eq(Seasonings.slot_count(&"warrior"), 3, "the dev profile has every slot")
	var profile := _use_fresh()
	check_eq(Seasonings.slot_count(&"warrior"), 0, "a new player has none")
	profile.set_class_progress(&"warrior", 2175, 10)
	check_eq(Seasonings.slot_count(&"warrior"), 2, "Level 10")
	check_eq(Seasonings.slot_count(&"mage"), 0, "per class")
	Meta.profile = Profile.max_profile(Db.class_ids)
	check_eq(Seasonings.slot_count(&"mage"), 3, "the max profile has every slot")
	if Meta.has_method(&"seasoning_slots"):
		check_eq(Seasonings.slot_count(&"mage"), int(Meta.call(&"seasoning_slots", &"mage")), "the LEVELS rule answers once it exists")


func test_level_up_cards_favour_an_equipped_seasonings_ability() -> void:
	var plain := _create(_slot(&"warrior"))
	var favoured := _create(_slot(&"warrior", ["ssn_horseradish_kick"], 1))
	var base := {}
	for c: Array in LevelUpDeck.ability_candidates(plain):
		var card := c[0] as LevelCard
		if card.kind == LevelCard.Kind.NEW_ABILITY:
			base[card.ability.id] = float(c[1])
	check(base.has(&"execute"), "Execute is on the table")
	var seen := 0
	for c: Array in LevelUpDeck.ability_candidates(favoured):
		var card := c[0] as LevelCard
		if card.kind != LevelCard.Kind.NEW_ABILITY:
			continue
		seen += 1
		var factor := float(c[1]) / float(base[card.ability.id])
		check_near(factor, 3.0 if card.ability.id == &"execute" else 1.0, 0.0001, "%s weighs x%s" % [card.ability.id, str(factor)])
	check_eq(seen, base.size(), "the same cards")
	for c: Array in LevelUpDeck.ability_candidates(plain):
		var card := c[0] as LevelCard
		if card.kind == LevelCard.Kind.NEW_ABILITY:
			check_eq(float(c[1]), card.ability.card_weight, "a plain hero keeps the data's weight (%s)" % card.ability.id)
	check_eq(Seasonings.card_weight_mult(favoured, &"execute"), 3.0, "x3")
	check_eq(Seasonings.card_weight_mult(favoured, &"shield_wall"), 1.0, "other abilities: x1")
	check_eq(Seasonings.card_weight_mult(null, &"execute"), 1.0, "no hero: x1")


func test_toggle_results() -> void:
	var slot := _slot(&"warrior")
	check_eq(Seasonings.toggle(slot, &"ssn_smoked_paprika"), Seasonings.RESULT_ADDED, "added")
	check_eq(slot.seasonings, [&"ssn_smoked_paprika"] as Array[StringName], "on the slot")
	check_eq(Seasonings.toggle(slot, &"ssn_smoked_paprika"), Seasonings.RESULT_REMOVED, "removed again")
	check(slot.seasonings.is_empty(), "off the slot")
	check_eq(Seasonings.toggle(slot, &"ssn_cinnamon_stick"), Seasonings.RESULT_INVALID, "a Mage Seasoning")
	check_eq(Seasonings.toggle(slot, &"ssn_nope"), Seasonings.RESULT_INVALID, "an unknown one")
	check_eq(Seasonings.toggle(null, &"ssn_smoked_paprika"), Seasonings.RESULT_INVALID, "no slot")
	for id in [&"ssn_smoked_paprika", &"ssn_cracked_pepper", &"ssn_cayenne_rush"]:
		check_eq(Seasonings.toggle(slot, id), Seasonings.RESULT_ADDED, "%s fits" % id)
	check_eq(Seasonings.toggle(slot, &"ssn_bay_leaf"), Seasonings.RESULT_FULL, "the fourth finds every slot taken")
	check_eq(slot.seasonings.size(), 3, "three")
	var profile := _use_fresh()
	var other := _slot(&"warrior", [], 1)
	check_eq(Seasonings.toggle(other, &"ssn_smoked_paprika"), Seasonings.RESULT_LOCKED, "not owned")
	profile.unlock(Profile.KIND_SEASONING, &"ssn_smoked_paprika")
	check_eq(Seasonings.toggle(other, &"ssn_smoked_paprika"), Seasonings.RESULT_FULL, "owned, but a new player has no slot")
	profile.set_class_progress(&"warrior", 215, 3)
	check_eq(Seasonings.toggle(other, &"ssn_smoked_paprika"), Seasonings.RESULT_ADDED, "owned and a slot is open")
	check_eq(profile.loadout(&"warrior")["seasonings"], [&"ssn_smoked_paprika"] as Array[StringName], "remembered for the class")


func test_prune_drops_what_a_class_cannot_carry() -> void:
	var slot := _slot(&"warrior", ["ssn_smoked_paprika", "ssn_cinnamon_stick"])
	Seasonings.prune(slot)
	check_eq(slot.seasonings, [&"ssn_smoked_paprika"] as Array[StringName], "the Mage Seasoning goes")
	slot.class_data = Db.get_class_data(&"mage")
	Seasonings.prune(slot)
	check(slot.seasonings.is_empty(), "and the Warrior's goes with a class change")


# --- The --seasonings flag ----------------------------------------------------------------------------

func _opts(args: Array) -> LaunchOptions:
	return LaunchOptions.parse(PackedStringArray(args))


func test_the_flag_lists_seasonings_per_class() -> void:
	var o := _opts(["--classes=warrior,mage", "--seasonings=ssn_smoked_paprika,ssn_cinnamon_stick,ssn_cracked_pepper"])
	check(o.unknown.is_empty(), "valid: %s" % str(o.unknown))
	check_eq(o.seasonings.size(), 3, "three ids")
	check_eq(o.seasonings_for(&"warrior"), [&"ssn_smoked_paprika", &"ssn_cracked_pepper"] as Array[StringName], "the Warrior's, in the order given")
	check_eq(o.seasonings_for(&"mage"), [&"ssn_cinnamon_stick"] as Array[StringName], "the Mage's")
	check(o.seasonings_for(&"rogue").is_empty(), "nobody else's")
	check(_opts(["--smoke"]).seasonings.is_empty(), "no flag, none")
	var order := _opts(["--seasonings=ssn_smoked_paprika", "--classes=warrior"])
	check(order.unknown.is_empty(), "the order of the flags does not matter")


func test_the_flag_is_validated_fail_fast() -> void:
	var cases := {
		"an unknown id": ["--seasonings=ssn_smoked_paprika,ssn_nope"],
		"an id without a bot of its class": ["--classes=warrior,mage", "--seasonings=ssn_cumin_seed"],
		"the default party has no Hunter": ["--players=4", "--seasonings=ssn_wild_garlic"],
		"more than three for one class": ["--classes=warrior", "--seasonings=ssn_smoked_paprika,ssn_cracked_pepper,ssn_cayenne_rush,ssn_bay_leaf"],
		"a repeated id": ["--classes=warrior", "--seasonings=ssn_smoked_paprika,ssn_smoked_paprika"],
		"an id of a class cut off by --players": ["--players=1", "--classes=warrior,mage", "--seasonings=ssn_cinnamon_stick"],
	}
	for what: String in cases:
		var o := _opts(cases[what])
		check_eq(o.unknown.size(), 1, "%s is an unknown argument" % what)
		check(o.seasonings.is_empty(), "%s: nothing is applied" % what)
	var fine := _opts(["--players=4", "--seasonings=ssn_smoked_paprika,ssn_cracked_pepper,ssn_cayenne_rush"])
	check(fine.unknown.is_empty(), "three of the Warrior's with the default party")
	var seven := _opts(["--players=4", "--classes=hunter,shaman", "--seasonings=ssn_wild_garlic,ssn_rock_salt"])
	check(seven.unknown.is_empty(), "classes picked with --classes: %s" % str(seven.unknown))


func test_the_bots_carry_their_classes_seasonings() -> void:
	var o := _opts(["--classes=warrior,mage,warrior", "--players=3",
			"--seasonings=ssn_smoked_paprika,ssn_cinnamon_stick,ssn_cracked_pepper"])
	var main := Main.create(o)
	tree.root.add_child(main)
	_nodes.append(main)
	main._add_bots()
	var slots := PlayerManager.get_slots()
	check_eq(slots.size(), 3, "three bots")
	main.start_run()
	check_eq(slots[0].seasonings, [&"ssn_smoked_paprika", &"ssn_cracked_pepper"] as Array[StringName], "the first Warrior's slot")
	check_eq(slots[1].seasonings, [&"ssn_cinnamon_stick"] as Array[StringName], "the Mage's")
	check_eq(slots[2].seasonings, [&"ssn_smoked_paprika", &"ssn_cracked_pepper"] as Array[StringName], "the second Warrior's too")
	check_eq(main.players.size(), 3, "three heroes")
	check_eq(main.players[0].seasonings, [&"ssn_smoked_paprika", &"ssn_cracked_pepper"] as Array[StringName], "the Warrior carries both")
	check_near(float(main.players[0].abilities.params_for(Db.get_ability(&"whirlwind"))["damage_pct"]), 190.0, 0.001, "and they work")
	check_eq(main.players[1].seasonings, [&"ssn_cinnamon_stick"] as Array[StringName], "the Mage carries its own")
	check(not main.players[1].bonuses.effects_of(Seasonings.SOURCE).is_empty(), "as a source")


func test_the_flag_wins_over_what_a_real_profile_remembers() -> void:
	var profile := Profile.max_profile(Db.class_ids)
	Meta.profile = profile
	Meta.persist = false
	Meta.path = ""
	profile.set_loadout(&"warrior", {"seasonings": [&"ssn_bay_leaf"], "heirloom": &"", "looks": {}})
	var main := Main.create(_opts(["--players=1", "--classes=warrior", "--seasonings=ssn_smoked_paprika"]))
	tree.root.add_child(main)
	_nodes.append(main)
	main._add_bots()
	Meta.apply_loadout(PlayerManager.get_slot(0))  # (what the lobby does; the bots of a launch take it too once LEVELS is in)
	check_eq(PlayerManager.get_slot(0).seasonings, [&"ssn_bay_leaf"] as Array[StringName], "the profile's choice is on the slot first")
	main.start_run()
	check_eq(main.players[0].seasonings, [&"ssn_smoked_paprika"] as Array[StringName], "the flag replaces it when the run starts")


func test_bots_without_the_flag_carry_nothing() -> void:
	var main := Main.create(_opts(["--players=4"]))
	tree.root.add_child(main)
	_nodes.append(main)
	main._add_bots()
	main.start_run()
	for p in main.players:
		check(p.seasonings.is_empty(), "%s carries nothing" % p.name)
		check(p.bonuses.effects_of(Seasonings.SOURCE).is_empty(), "%s has no source" % p.name)


# --- The lobby picker ---------------------------------------------------------------------------------

var lobby: Lobby


func _lobby() -> Lobby:
	lobby = Lobby.create()
	UiFakes.add_to_root(tree, lobby)
	_nodes.append(lobby)
	return lobby


func _join(key: String, class_id: StringName) -> UiFakes.HumanInput:
	var input := UiFakes.HumanInput.new(key)
	PlayerManager.join(input, Db.get_class_data(class_id))
	return input


func _picker(index: int) -> SeasoningPicker:
	return lobby.picker_of(PlayerManager.get_slot(index))


func test_lt_opens_the_picker_over_that_players_card() -> void:
	_lobby()
	var p1 := _join("p1", &"warrior")
	var p2 := _join("p2", &"mage")
	UiFakes.step(lobby)
	check(not _picker(0).is_open() and not _picker(1).is_open(), "closed to begin with")
	UiFakes.tap(lobby, p2, PlayerInput.Pad.LT)
	check(_picker(1).is_open(), "P2's LT opens P2's picker")
	check(not _picker(0).is_open(), "and only theirs")
	check_eq(_picker(1).entries.size(), 8, "the eight Mage Seasonings")
	check_eq(_picker(1).entries[0].class_id, &"mage", "of the Mage")
	check(_picker(1).visible and not _picker(0).visible, "shown on P2's card only")
	# P1 is not held up: A readies P1 while P2 is picking.
	UiFakes.tap(lobby, p1, PlayerInput.Pad.A)
	check(PlayerManager.get_slot(0).ready, "P1 readies up meanwhile")
	check(not PlayerManager.get_slot(1).ready, "P2's A went to the picker")


func test_the_picker_is_driven_by_its_owners_input() -> void:
	_lobby()
	var p1 := _join("p1", &"warrior")
	var p2 := _join("p2", &"warrior")
	var slot1 := PlayerManager.get_slot(0)
	UiFakes.step(lobby)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	var picker := _picker(0)
	check_eq(picker.cursor, 0, "the cursor starts at the top")
	UiFakes.nudge(lobby, p2, Vector2(0, 1))
	check_eq(picker.cursor, 0, "another player's stick does not move it")
	UiFakes.nudge(lobby, p1, Vector2(0, 1))
	check_eq(picker.cursor, 1, "the owner's stick moves it down")
	UiFakes.nudge(lobby, p1, Vector2(0, 1))
	check_eq(picker.cursor, 2, "again")
	UiFakes.nudge(lobby, p1, Vector2(0, -1))
	check_eq(picker.cursor, 1, "and up")
	UiFakes.nudge(lobby, p1, Vector2(0, -1))
	UiFakes.nudge(lobby, p1, Vector2(0, -1))
	check_eq(picker.cursor, 7, "it wraps to the bottom")
	UiFakes.nudge(lobby, p1, Vector2(0, 1))
	check_eq(picker.cursor, 0, "and back to the top")
	check_eq(slot1.class_data.id, &"warrior", "the stick did not change the class")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.A)
	check_eq(slot1.seasonings, [picker.entries[0].id] as Array[StringName], "A equips the Seasoning under the cursor")
	check(not slot1.ready, "and does not ready the player")
	check_eq(picker.last_result, Seasonings.RESULT_ADDED, "added")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.A)
	check(slot1.seasonings.is_empty(), "A again removes it")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.B)
	check(not picker.is_open(), "B closes the picker")
	check_eq(PlayerManager.count(), 2, "and the player did not leave")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	check(picker.is_open(), "LT opens it again")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	check(not picker.is_open(), "and closes it")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.B)
	check_eq(PlayerManager.count(), 1, "B with the picker closed leaves the lobby as before")


func test_an_open_picker_takes_every_button_of_its_owner() -> void:
	_lobby()
	var p1 := _join("p1", &"warrior")
	var slot := PlayerManager.get_slot(0)
	UiFakes.step(lobby)
	var mode := lobby.run_mode
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.Y)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.X)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.START)
	UiFakes.nudge(lobby, p1, Vector2(1, 0))
	check_eq(lobby.run_mode, mode, "Y does not change the mode")
	check(not lobby.hardcore, "X does not toggle Hardcore")
	check(not slot.ready, "START does not ready")
	check_eq(slot.class_data.id, &"warrior", "the class stays")
	check(_picker(0).is_open(), "the picker stays open")


func test_a_ready_player_cannot_open_the_picker() -> void:
	_lobby()
	var p1 := _join("p1", &"warrior")
	UiFakes.step(lobby)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.A)
	check(PlayerManager.get_slot(0).ready, "ready")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	check(not _picker(0).is_open(), "the picks are locked like the class")
	check(not lobby.open_seasoning_picker(PlayerManager.get_slot(0)), "also through the API")
	check(not lobby.open_seasoning_picker(null), "no slot, no picker")


func test_the_picker_lists_owned_and_locked_seasonings() -> void:
	var profile := _use_fresh()
	profile.set_class_progress(&"warrior", 215, 3)
	profile.unlock(Profile.KIND_SEASONING, &"ssn_cracked_pepper")
	_lobby()
	var p1 := _join("p1", &"warrior")
	var slot := PlayerManager.get_slot(0)
	UiFakes.step(lobby)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	var picker := _picker(0)
	check_eq(picker.rows.size(), 8, "eight rows")
	check_eq(picker.slot_total(), 1, "one slot at Class Level 3")
	var states := {}
	for s in picker.entries:
		states[s.id] = picker.state_of(s)
	check_eq(states[&"ssn_cracked_pepper"], "", "the owned one is free to equip")
	check_eq(states[&"ssn_smoked_paprika"], "Locked", "the others are locked")
	check_eq(states[&"ssn_ginger_snap"], "Locked", "even the last")
	var owned_at := picker.entries.find(Db.get_seasoning(&"ssn_cracked_pepper"))
	var locked_at := picker.entries.find(Db.get_seasoning(&"ssn_bay_leaf"))
	picker.cursor = locked_at
	check_eq(picker.activate(), Seasonings.RESULT_LOCKED, "A on a locked one is refused")
	check(slot.seasonings.is_empty(), "nothing equipped")
	picker.cursor = owned_at
	check_eq(picker.activate(), Seasonings.RESULT_ADDED, "the owned one goes in")
	check_eq(picker.state_of(picker.entries[owned_at]), "Equipped", "and shows as equipped")
	check_eq(picker.activate(), Seasonings.RESULT_REMOVED, "A takes it out again")
	profile.unlock(Profile.KIND_SEASONING, &"ssn_smoked_paprika")
	picker.cursor = picker.entries.find(Db.get_seasoning(&"ssn_smoked_paprika"))
	check_eq(picker.activate(), Seasonings.RESULT_ADDED, "Smoked Paprika, owned now")
	picker.cursor = owned_at
	check_eq(picker.activate(), Seasonings.RESULT_FULL, "the one slot is taken")
	check_eq(slot.seasonings, [&"ssn_smoked_paprika"] as Array[StringName], "the first pick stays")


func test_a_locked_row_shows_how_to_get_it() -> void:
	_use_fresh()
	_lobby()
	var p1 := _join("p1", &"mage")
	UiFakes.step(lobby)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	var picker := _picker(0)
	check_eq(picker.slot_total(), 0, "a new Mage has no slot")
	picker.cursor = picker.entries.find(Db.get_seasoning(&"ssn_chili_flake"))
	picker.refresh()
	check(picker._detail_status.text.contains("Mage Level 13") and picker._detail_status.text.contains("140 Seeds"), "the hint: " + picker._detail_status.text)
	picker.cursor = picker.entries.find(Db.get_seasoning(&"ssn_pink_peppercorn"))
	picker.refresh()
	check(picker._detail_status.text.contains("Win a run with the Mage"), "an achievement tier: " + picker._detail_status.text)
	check_eq(picker._detail_name.text, "Pink Peppercorn", "named")
	check(picker._detail_text.text.contains("4 more darts"), "with its text: " + picker._detail_text.text)
	check(picker._detail_target.text.contains("Arcane Darts"), "and the ability it changes")
	check(picker._note.text.contains("first slot at Class Level 3"), "the header says why nothing can be equipped: " + picker._note.text)


func test_the_choice_follows_the_class_and_is_saved() -> void:
	var tmp := "user://m9_seasonings_test_%d.json" % OS.get_process_id()
	var profile := _use_fresh()
	Meta.persist = true
	Meta.path = tmp
	profile.set_class_progress(&"warrior", 2175, 10)
	profile.unlock(Profile.KIND_SEASONING, &"ssn_smoked_paprika")
	profile.unlock(Profile.KIND_SEASONING, &"ssn_cracked_pepper")
	_lobby()
	var p1 := _join("p1", &"warrior")
	var slot := PlayerManager.get_slot(0)
	UiFakes.step(lobby)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	var picker := _picker(0)
	picker.cursor = picker.entries.find(Db.get_seasoning(&"ssn_cracked_pepper"))
	picker.activate()
	picker.cursor = picker.entries.find(Db.get_seasoning(&"ssn_smoked_paprika"))
	picker.activate()
	check_eq(slot.seasonings, [&"ssn_cracked_pepper", &"ssn_smoked_paprika"] as Array[StringName], "two picks, in order")
	check_eq(profile.loadout(&"warrior")["seasonings"], [&"ssn_cracked_pepper", &"ssn_smoked_paprika"] as Array[StringName], "remembered at once for the Warrior")
	check(FileAccess.file_exists(tmp), "and saved")
	var reread := Profile.load_file(tmp)
	check_eq(reread.loadout(&"warrior")["seasonings"], [&"ssn_cracked_pepper", &"ssn_smoked_paprika"] as Array[StringName], "the file holds them")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.B)
	# Class change: the Mage has nothing remembered, the Warrior's picks come back with the Warrior.
	UiFakes.nudge(lobby, p1, Vector2(1, 0))
	check_eq(slot.class_data.id, &"mage", "on to the Mage")
	check(slot.seasonings.is_empty(), "the Mage carries none of the Warrior's")
	UiFakes.nudge(lobby, p1, Vector2(-1, 0))
	check_eq(slot.class_data.id, &"warrior", "and back")
	check_eq(slot.seasonings, [&"ssn_cracked_pepper", &"ssn_smoked_paprika"] as Array[StringName], "the Warrior's choice is back")
	# A new session: the slot of a joining player gets them.
	PlayerManager.clear()
	var fresh := PlayerManager.join(UiFakes.HumanInput.new("p9"), Db.get_class_data(&"warrior"))
	UiFakes.step(lobby)
	check_eq(fresh.seasonings, [&"ssn_cracked_pepper", &"ssn_smoked_paprika"] as Array[StringName], "a joining Warrior starts with them")
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(tmp + suffix):
			DirAccess.remove_absolute(tmp + suffix)


func test_the_dev_profile_keeps_a_choice_per_slot_only() -> void:
	_lobby()
	var p1 := _join("p1", &"warrior")
	var slot := PlayerManager.get_slot(0)
	UiFakes.step(lobby)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	_picker(0).activate()
	check_eq(slot.seasonings.size(), 1, "the dev profile owns everything: it equips")
	check(Meta.profile.loadout(&"warrior")["seasonings"].is_empty(), "but remembers nothing (no profile is touched)")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.B)
	UiFakes.nudge(lobby, p1, Vector2(1, 0))
	check(slot.seasonings.is_empty(), "the Warrior's Seasoning does not follow the player to the Mage")


func test_the_card_shows_sockets_the_glyph_and_the_count() -> void:
	var profile := _use_fresh()
	profile.set_class_progress(&"warrior", 2175, 10)
	profile.unlock(Profile.KIND_SEASONING, &"ssn_smoked_paprika")
	_lobby()
	var p1 := _join("p1", &"warrior")
	var slot := PlayerManager.get_slot(0)
	UiFakes.step(lobby)
	var card := lobby.cards[0]
	check(card.seasoning_pill_visible(), "the pill shows")
	var sockets := card.seasoning_sockets()
	check_eq(sockets.size(), 3, "three sockets")
	check(not sockets[0].locked and not sockets[1].locked and sockets[2].locked, "two slots open, the third not yet (Level 10)")
	check(sockets[0].content == null, "all empty")
	var glyph := card.seasoning_glyph()
	check(glyph != null and glyph.text == "LT", "the controller's LT opens it")
	slot.seasonings.assign([&"ssn_smoked_paprika"])
	UiFakes.step(lobby)
	sockets = card.seasoning_sockets()
	check(sockets[0].content != null and sockets[0].content.seasoning.id == &"ssn_smoked_paprika", "the first socket holds the pick")
	check(sockets[1].content == null, "the second is free")
	UiFakes.tap(lobby, p1, PlayerInput.Pad.A)
	check(card.seasoning_glyph() == null, "ready: no button to show, the picks are locked")


func test_the_keyboards_glyph_is_the_right_mouse_button() -> void:
	_lobby()
	var slot := PlayerManager.join(KeyboardInput.new(), Db.get_class_data(&"warrior"))
	check(slot != null, "the keyboard joins")
	UiFakes.step(lobby)
	var glyph := lobby.cards[0].seasoning_glyph()
	check(glyph != null and glyph.text == "RMB", "the right mouse button opens it on the keyboard")


func test_an_empty_slot_and_a_left_player_have_no_picker() -> void:
	_lobby()
	UiFakes.step(lobby)
	check(not lobby.cards[0].seasoning_pill_visible(), "no pill on an open slot")
	var p1 := _join("p1", &"warrior")
	UiFakes.step(lobby)
	UiFakes.tap(lobby, p1, PlayerInput.Pad.LT)
	check(_picker(0).is_open(), "open")
	PlayerManager.leave(0)
	UiFakes.step(lobby)
	check(not lobby.cards[0].picker.is_open(), "the card closes it when the player is gone")


# --- Names, every Seasoning through Player.create ------------------------------------------------------

func test_seasoning_names_do_not_repeat_any_other_name_in_the_game() -> void:
	var taken: Dictionary[String, String] = {}
	for id in Db.abilities:
		var a := Db.abilities[id]
		taken[a.display_name] = "ability %s" % id
		for spec in a.specs:
			taken[str(spec.get("name", ""))] = "spec of %s" % id
	for id in Db.talents:
		taken[Db.talents[id].display_name] = "talent %s" % id
	for id in Db.talent_trees:
		taken[Db.talent_trees[id].display_name] = "tree %s" % id
	for id in Db.sets:
		taken[Db.sets[id].display_name] = "set %s" % id
	for id in Db.uniques:
		taken[Db.uniques[id].display_name] = "unique %s" % id
	for id in Db.weapons:
		taken[Db.weapons[id].display_name] = "weapon %s" % id
	for id in Db.consumables:
		taken[Db.consumables[id].display_name] = "consumable %s" % id
	for s in _all():
		check(not taken.has(s.display_name), "%s is also %s" % [s.display_name, taken.get(s.display_name, "")])
		check(s.display_name == s.display_name.strip_edges() and s.display_name.length() <= 20, "%s fits the picker row" % s.display_name)
		check(s.text.length() <= 120, "%s: the text fits the detail panel (%d chars)" % [s.id, s.text.length()])


func test_every_seasoning_goes_through_player_create() -> void:
	var index := 0
	for s in _all():
		var p := Player.create(_slot(s.class_id, [s.id], index % PlayerManager.MAX_PLAYERS))
		world.add_child(p)
		check_eq(p.seasonings, [s.id] as Array[StringName], "%s is carried" % s.id)
		var entries := p.bonuses.effects_of(Seasonings.SOURCE)
		check_eq(entries.size(), 1, "%s: one entry" % s.id)
		p.free()
		index += 1


func test_the_picker_never_changes_the_cards_height_and_fits_inside_it() -> void:
	_lobby()
	var smallest_card := INF
	var tallest_picker := 0.0
	for cid in Db.class_ids:
		var input := _join("p_%s" % cid, cid)
		UiFakes.step(lobby)
		var card := lobby.cards[0]
		var closed := card.get_combined_minimum_size().y
		smallest_card = minf(smallest_card, closed)
		var slot := PlayerManager.get_slot(0)
		check(lobby.open_seasoning_picker(slot), "%s: the picker opens" % cid)
		check_eq(card.get_combined_minimum_size().y, closed, "%s: an open picker does not change the card's height" % cid)
		var picker := card.picker
		for i in picker.entries.size():
			picker.cursor = i
			picker.refresh()
			tallest_picker = maxf(tallest_picker, picker.get_combined_minimum_size().y)
		picker.close()
		PlayerManager.leave(0)
		check(input != null, "joined")
		UiFakes.step(lobby)
	check(tallest_picker <= smallest_card, "the picker (%d px at most) fits inside the smallest card (%d px) at 1080p" % [tallest_picker, smallest_card])


func test_the_achievement_tiers_name_real_achievements() -> void:
	if Db.achievements.is_empty():
		return  # (the ACHIEVE-DIFF package's data is not in this branch: checked once it is merged)
	for s in _all():
		var id := s.unlock_achievement()
		if id == &"":
			continue
		check(Db.get_achievement(id) != null, "%s opens with %s, which must exist" % [s.id, id])
