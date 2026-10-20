extends TestCase
## M9 ACHIEVE-DIFF, difficulty: the three DifficultyData tiers, their multipliers where the game reads them (enemy HP and
## damage, boss HP, spawn density, elite rate, every gold price but the rerolls), the Tear-Jerker pressure (a rotation that
## is a pure function of the run seed, its multipliers and hero effects, the Main break path), the lobby selector and
## its cap, the --difficulty flag, the XP / Seeds hooks, the leaderboard category and its file migration, and what the
## HUD, the end screen and the run card show.

const UiFakes := preload("res://tests/ui_fakes.gd")
const MarketFakes := preload("res://tests/test_ui_market_fakes.gd")
const SEED := 4711
const DT := 1.0 / 60.0

var main: Main
var world: Node3D
var nodes: Array[Node] = []
var lobby: Lobby
var _saved_profile: Profile
var _saved_path := ""
var _saved_persist := false
var _tmp := "user://m9_difficulty_test_%d.json" % OS.get_process_id()


func before_each() -> void:
	_saved_profile = Meta.profile
	_saved_path = Meta.path
	_saved_persist = Meta.persist
	UiFakes.reset_players()
	RunState.start_run(2, SEED)
	tree.paused = false


func after_each() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()
	UiFakes.free_node(lobby)
	lobby = null
	UiFakes.free_node(world)
	world = null
	Meta.profile = _saved_profile
	Meta.path = _saved_path
	Meta.persist = _saved_persist
	for suffix in ["", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(_tmp + suffix):
			DirAccess.remove_absolute(_tmp + suffix)
	tree.paused = false
	UiFakes.reset_players()
	Enemy.invalidate_player_cache()
	EliteAffixes.rate_mult = 1.0
	RunState.start_run(1, SEED)


# --- Helpers ------------------------------------------------------------------------------------

func _run(tier: StringName, players: int = 2, seed_value: int = SEED) -> void:
	RunState.start_run(players, seed_value, RunState.MODE_NORMAL, false, &"forest_ruin", tier)


func _world() -> Node3D:
	if world == null:
		world = MarketFakes.make_world(tree)
	return world


func _human(key: String = "pad:a", class_id: StringName = &"warrior") -> UiFakes.HumanInput:
	return MarketFakes.human_with_hero(_world(), key, class_id)


func _hero(slot_index: int = 0) -> Player:
	return PlayerManager.get_slot(slot_index).player as Player


func _enemy(id: StringName, wave: int) -> Enemy:
	var e := Enemy.create(Db.get_enemy(id), wave)
	nodes.append(e)
	return e


func _make_main(opts: LaunchOptions) -> Main:
	main = Main.create(opts)
	tree.root.add_child(main)
	return main


func _bots(count: int) -> void:
	for i in count:
		PlayerManager.add_bot(Db.class_ids[i % Db.class_ids.size()], i + 1)


func _clear_wave_and_wait() -> void:
	main.wave_director.time_left = 0.0
	main.wave_director._physics_process(DT)
	main._physics_process(Main.WAVE_END_DELAY + 0.01)


## A real player profile in memory that has unlocked nothing.
func _fresh() -> Profile:
	Meta.profile = Profile.fresh()
	Meta.persist = false
	Meta.path = ""
	return Meta.profile


## The pressure of waves 1..[param last] of a run with [param seed_value], the way Main walks them (begin, end, begin ...).
func _rotation(seed_value: int, last: int, tier: StringName = &"tear_jerker") -> Array[StringName]:
	_run(tier, 2, seed_value)
	var out: Array[StringName] = []
	for w in range(1, last + 1):
		Pressure.begin_wave(w, [])
		out.append(RunState.pressure_current)
		Pressure.end_wave(w, [])
	return out


# --- The data -----------------------------------------------------------------------------------

func test_the_three_tiers_have_the_designed_numbers() -> void:
	check_eq(Difficulty.ids(), [&"normal", &"pungent", &"tear_jerker"] as Array[StringName], "the ladder, Normal first")
	var table := {
		&"normal": [0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, false],
		&"pungent": [1, 1.3, 1.2, 1.15, 1.5, 1.1, 1.5, 1.5, false],
		&"tear_jerker": [2, 1.7, 1.45, 1.3, 2.0, 1.25, 2.5, 2.5, true],
	}
	for id: StringName in table:
		var d := Db.get_difficulty(id)
		check(d != null, "%s loads" % id)
		if d == null:
			continue
		var row: Array = table[id]
		check_eq(d.tier, row[0], "%s tier" % id)
		check_eq(d.enemy_hp_mult, row[1], "%s HP" % id)
		check_eq(d.enemy_damage_mult, row[2], "%s damage" % id)
		check_eq(d.spawn_density_mult, row[3], "%s density" % id)
		check_eq(d.elite_rate_mult, row[4], "%s elites" % id)
		check_eq(d.shop_price_mult, row[5], "%s prices" % id)
		check_eq(d.xp_mult, row[6], "%s XP" % id)
		check_eq(d.seeds_mult, row[7], "%s Seeds" % id)
		check_eq(d.pressure, row[8], "%s pressure" % id)
		check(d.display_name != "" and d.description != "", "%s has a name and a text" % id)
	check_eq(Db.get_difficulty(&"tear_jerker").display_name, "Tear-Jerker", "the name")


func test_normal_multiplies_by_exactly_one() -> void:
	_run(&"normal")
	for value: float in [Difficulty.enemy_hp_mult(), Difficulty.enemy_damage_mult(), Difficulty.spawn_mult(),
			Difficulty.elite_mult(), Pressure.enemy_speed_mult(), Pressure.elite_mult(), Pressure.gold_mult(),
			Pressure.xp_mult(), RunState.difficulty_xp_mult(), RunState.difficulty_seeds_mult()]:
		check(value == 1.0, "exactly 1.0 (a Normal run is the base game bit for bit)")
	check_eq(Difficulty.price(137), 137, "prices unchanged")
	check_eq(Difficulty.price(0), 0, "nothing stays nothing")


func test_unknown_ids_play_as_normal() -> void:
	_run(&"nonsense")
	check_eq(RunState.difficulty, &"normal", "start_run sanitises the tier")
	check_eq(Difficulty.sanitize(&"bogus"), &"normal", "sanitize")
	check_eq(Difficulty.tier_index(&"bogus"), -1, "no index")
	check_eq(Difficulty.data_of(&"bogus").id, &"normal", "Normal's data stands in")
	check_eq(Difficulty.name_of(&"pungent"), "Pungent", "name")
	check_eq(Difficulty.cycle(&"normal", 1), &"pungent", "cycle")
	check_eq(Difficulty.cycle(&"tear_jerker", 1), &"normal", "wraps")
	check_eq(Difficulty.cycle(&"normal", -1), &"tear_jerker", "backwards")
	var only: Array[StringName] = [&"normal", &"pungent"]
	check_eq(Difficulty.cycle(&"pungent", 1, only), &"normal", "within an allowed list")
	check(Difficulty.effect_lines(&"normal").is_empty(), "Normal changes nothing")
	check(Difficulty.effect_lines(&"tear_jerker").size() >= 5, "Tear-Jerker lists its effects: %s" % [Difficulty.effect_lines(&"tear_jerker")])


# --- The multipliers where they are read --------------------------------------------------------------

func test_enemies_scale_with_the_tier() -> void:
	for id: StringName in [&"skeleton_grunt", &"troll_axethrower", &"plague_ghoul"]:
		_run(&"normal")
		var base := _enemy(id, 6)
		for tier: StringName in [&"pungent", &"tear_jerker"]:
			_run(tier)
			var d := Db.get_difficulty(tier)
			var e := _enemy(id, 6)
			check_near(e.max_hp, base.max_hp * d.enemy_hp_mult, 0.001, "%s %s HP" % [id, tier])
			check_near(e.contact_damage, base.contact_damage * d.enemy_damage_mult, 0.0001, "%s %s contact damage" % [id, tier])
			check_near(e.projectile_damage, base.projectile_damage * d.enemy_damage_mult, 0.0001, "%s %s projectile damage" % [id, tier])


func test_a_normal_enemy_is_the_plain_formula() -> void:
	_run(&"normal")
	var data := Db.get_enemy(&"skeleton_grunt")
	var e := _enemy(&"skeleton_grunt", 9)
	check(e.max_hp == maxf(1.0, data.hp_at_wave(9) * RunState.coop_hp_mult() * 1.0 * 1.0), "no tier factor on Normal")


func test_bosses_scale_in_hp_not_through_the_party_factor() -> void:
	_run(&"normal")
	var data := Db.get_boss(&"lich_commander_morvain")
	var plain := Boss.create(data, 10)
	nodes.append(plain)
	_run(&"pungent")
	var hard := Boss.create(data, 10)
	nodes.append(hard)
	check_near(hard.max_hp, plain.max_hp * 1.3, 0.01, "+30% boss HP on Pungent")
	check_near(hard.contact_damage, plain.contact_damage * 1.2, 0.0001, "+20% boss damage (hazards and hits read it)")


func test_spawn_density_follows_the_tier() -> void:
	var director := WaveDirector.create(null)
	nodes.append(director)
	director.wave = 6
	_run(&"normal")
	var base := director.spawn_budget_per_second()
	check_near(base, WaveDirector.spawn_rate(6, RunState.coop_count_mult()), 0.000001, "Normal: the plain rate")
	_run(&"pungent")
	check_near(director.spawn_budget_per_second(), base * 1.15, 0.000001, "Pungent +15%")
	_run(&"tear_jerker")
	check_near(director.spawn_budget_per_second(), base * 1.3, 0.000001, "Tear-Jerker +30%")
	check(WaveDirector.MAX_ENEMIES == 150, "the enemy cap stays 150")
	director.boss_data = Db.get_boss(&"lich_commander_morvain")
	director.wave = 10
	check_near(director.spawn_budget_per_second(), WaveDirector.spawn_rate(10, RunState.coop_count_mult()) * WaveDirector.BOSS_ADD_RATE_MULT,
			0.000001, "a boss wave's adds keep their rate")


func test_elite_rate_reaches_the_run() -> void:
	var opts := LaunchOptions.new()
	opts.difficulty = &"pungent"
	_make_main(opts)
	_bots(1)
	main.start_run()
	check_eq(RunState.difficulty, &"pungent", "the run plays Pungent")
	check_near(EliteAffixes.rate_mult, 1.5, 0.000001, "elites x1.5")
	main.options.elite_mult = 2.0
	main.start_run()
	check_near(EliteAffixes.rate_mult, 3.0, 0.000001, "--elite-mult stacks with the tier")


func test_every_gold_price_but_the_rerolls_follows_the_tier() -> void:
	var hero_input := _human("pad:a", &"warrior")
	check(hero_input != null, "(a hero)")
	var slots := PlayerManager.get_slots()
	var rng := RandomNumberGenerator.new()
	_run(&"normal", 1)
	RunState.set_wave(8)
	var plain := Shop.new()
	rng.seed = 5
	plain.open_round(8, slots, rng)
	var base_offers: Array[int] = []
	var base_values: Array[int] = []
	for o in plain.offers:
		base_offers.append(o.price)
		base_values.append(o.item.buy_price)
	var base_consumables: Array[int] = []
	for c in plain.consumables:
		base_consumables.append(c.price)
	var base_black := plain.black_market.price if plain.black_market != null else -1
	check(not base_offers.is_empty(), "the stall has offers")
	_run(&"pungent", 1)
	RunState.set_wave(8)
	var hard := Shop.new()
	rng.seed = 5
	hard.open_round(8, slots, rng)
	check_eq(hard.offers.size(), base_offers.size(), "the same stall")
	for i in hard.offers.size():
		var o := hard.offers[i]
		check_eq(o.price, roundi(base_offers[i] * 1.1), "offer %d costs 10%% more" % i)
		check_eq(o.item.buy_price, base_values[i], "offer %d keeps its own value (the sell price does not rise)" % i)
	for i in hard.consumables.size():
		check_eq(hard.consumables[i].price, roundi(base_consumables[i] * 1.1), "consumable %d" % i)
	if base_black > 0:
		check_eq(hard.black_market.price, roundi(base_black * 1.1), "the Black Market")
	check_eq(hard.reroll_cost(), plain.reroll_cost(), "rerolls are exempt")
	_run(&"tear_jerker", 1)
	check_eq(Difficulty.price(100), 125, "Tear-Jerker +25%")
	check_eq(Difficulty.price(1), 1, "never below 1 gold")


func test_the_trainer_and_the_enchanter_follow_the_tier() -> void:
	_human("pad:a", &"warrior")
	var hero := _hero()
	var ability_id := hero.abilities.slots[AbilityRunner.CORE_SLOTS].id if hero.abilities.slots[AbilityRunner.CORE_SLOTS] != null else &"whirlwind"
	_run(&"normal", 1)
	RunState.set_wave(6)
	var base := hero.abilities.trainer_price(ability_id)
	_run(&"pungent", 1)
	RunState.set_wave(6)
	check_eq(hero.abilities.trainer_price(ability_id), roundi(base * 1.1), "the Trainer's rank price")
	var item := MarketFakes.make_item("Test Plate", Items.SlotType.CHEST)
	item.rarity = Items.Rarity.EPIC
	_run(&"normal", 1)
	RunState.set_wave(6)
	var enchant := Enchanter.gold_price(item)
	_run(&"tear_jerker", 1)
	RunState.set_wave(6)
	check_eq(Enchanter.gold_price(item), maxi(1, roundi(enchant * 1.25)), "the Enchanter's gold")
	check_eq(Enchanter.dust_price(item), Enchanter.dust_price(item), "Dust is no gold price")


func test_the_xp_and_seeds_hooks() -> void:
	_run(&"normal")
	check(RunState.difficulty_xp_mult() == 1.0 and RunState.difficulty_seeds_mult() == 1.0, "Normal pays the base")
	_run(&"pungent")
	check_eq(RunState.difficulty_xp_mult(), 1.5, "Pungent XP")
	_run(&"tear_jerker")
	check_eq(RunState.difficulty_xp_mult(), 2.5, "Tear-Jerker XP")
	check_eq(RunState.difficulty_seeds_mult(), 2.5, "Tear-Jerker Seeds")
	check_eq(Difficulty.xp_mult_of(&"pungent"), 1.5, "by id too (a RunReport carries the id)")


# --- Tear-Jerker pressure -----------------------------------------------------------------------------

func test_six_pressures_with_their_own_names() -> void:
	check_eq(Db.pressure_ids.size(), 6, "six modifiers")
	check_eq(Db.pressure_ids, Db.PRESSURE_ORDER, "in the designed order")
	var names: Array[String] = []
	for id in Db.pressure_ids:
		var p := Db.get_pressure(id)
		check(p.display_name != "" and p.text != "", "%s has a name and a text" % id)
		check(p.display_name not in names, "%s is unique" % p.display_name)
		names.append(p.display_name)
	check_eq(names, ["Salt Rain", "Hardened Peel", "Paring Knives", "Wilting Heat", "Weeping Fog", "Bitter Harvest"] as Array[String], "the names")
	var salt := Db.get_pressure(&"prs_salt_rain")
	check(salt.spawn_rate_pct == 30.0 and salt.enemy_hp_pct == -12.0, "Salt Rain: spawn +30%, HP -12%")
	var peel := Db.get_pressure(&"prs_hardened_peel")
	check(peel.enemy_hp_pct == 35.0 and peel.enemy_speed_pct == -10.0, "Hardened Peel")
	check_eq(Db.get_pressure(&"prs_paring_knives").enemy_damage_pct, 35.0, "Paring Knives")
	var heat := Db.get_pressure(&"prs_wilting_heat")
	check_eq(heat.hero_effects.size(), 2, "Wilting Heat: cooldowns and Haste")
	var fog := Db.get_pressure(&"prs_weeping_fog")
	check(fog.enemy_speed_pct == 10.0 and fog.hero_effects.size() == 1, "Weeping Fog")
	var bitter := Db.get_pressure(&"prs_bitter_harvest")
	check(bitter.elite_rate_pct == 100.0 and bitter.gold_pct == 40.0 and bitter.xp_pct == 40.0, "Bitter Harvest")
	for id in Db.pressure_ids:
		for e in Db.get_pressure(id).hero_effects:
			check_eq(BonusVocabulary.validate(e), "", "%s: the hero effect is valid vocabulary" % id)


func test_the_rotation_is_a_function_of_the_seed() -> void:
	var a := _rotation(31337, 40)
	var b := _rotation(31337, 40)
	check_eq(a, b, "the same seed, the same pressures")
	check(_rotation(4242, 40) != a, "another seed, another rotation")
	check(not a.is_empty() and a.size() == 40, "forty waves")


func test_pressure_skips_calm_boss_and_elite_waves_and_never_repeats() -> void:
	for seed_value in [1, 2, 3, 99, 31337]:
		var rot := _rotation(seed_value, 70)
		var seen: Dictionary = {}
		for i in rot.size():
			var w := i + 1
			if w < Pressure.FIRST_WAVE or RunState.is_boss_wave(w) or RunState.is_elite_wave(w):
				check_eq(rot[i], &"", "seed %d wave %d is calm" % [seed_value, w])
			else:
				check(Db.get_pressure(rot[i]) != null, "seed %d wave %d has a real modifier (%s)" % [seed_value, w, rot[i]])
				seen[rot[i]] = true
			if i > 0 and rot[i] != &"":
				check(rot[i] != rot[i - 1], "seed %d wave %d does not repeat the wave before" % [seed_value, w])
		check_eq(seen.size(), 6, "seed %d: every modifier turns up over 70 waves" % seed_value)


func test_only_tear_jerker_has_pressure() -> void:
	for tier: StringName in [&"normal", &"pungent"]:
		var rot := _rotation(7, 20, tier)
		for p in rot:
			check_eq(p, &"", "%s has no pressure" % tier)
	check(not Pressure.is_pressure_wave(5), "(the last run was Pungent)")
	_run(&"tear_jerker")
	check(Pressure.is_pressure_wave(5) and not Pressure.is_pressure_wave(2) and not Pressure.is_pressure_wave(10) \
			and not Pressure.is_pressure_wave(20) and not Pressure.is_pressure_wave(33), "waves 1-2, boss waves and elite waves are calm")


func test_the_pressure_never_touches_the_run_rng() -> void:
	_run(&"tear_jerker")
	var before := RunState.rng.state
	for w in range(1, 30):
		Pressure.begin_wave(w, [])
		Pressure.end_wave(w, [])
	check_eq(RunState.rng.state, before, "RunState.rng is untouched by 30 waves of pressure")
	check(RunState.pressure_rng.seed != RunState.rng.seed, "its own generator")


func test_the_next_wave_is_planned_at_the_break_and_used_at_its_start() -> void:
	_run(&"tear_jerker")
	Pressure.begin_wave(3, [])
	var third := RunState.pressure_current
	check(third != &"", "wave 3 has one")
	Pressure.end_wave(3, [])
	check_eq(RunState.pressure_next_wave, 4, "wave 4 is planned")
	var planned := RunState.pressure_next
	check(planned != &"" and planned != third, "and differs from the wave before")
	check(Pressure.next_wave_suffix(4).contains(Db.get_pressure(planned).display_name), "the break screen can name it: %s" % Pressure.next_wave_suffix(4))
	check_eq(Pressure.next_wave_suffix(5), "", "nothing for another wave")
	Pressure.begin_wave(4, [])
	check_eq(RunState.pressure_current, planned, "the planned modifier is the wave's")
	check_eq(RunState.pressure_next, &"", "the plan is spent")
	# A run that starts on a later wave rolls at the start.
	_run(&"tear_jerker")
	Pressure.begin_wave(7, [])
	check(RunState.pressure_current != &"" and RunState.pressure_live, "rolled on the spot")


func test_the_multipliers_are_live_only_inside_a_wave() -> void:
	_run(&"tear_jerker")
	RunState.pressure_current = &"prs_salt_rain"
	RunState.pressure_live = false
	check(Pressure.spawn_mult() == 1.0 and Pressure.enemy_hp_mult() == 1.0, "not live: 1")
	RunState.pressure_live = true
	check_near(Pressure.spawn_mult(), 1.3, 0.000001, "Salt Rain: spawn +30%")
	check_near(Difficulty.enemy_hp_mult(), 1.7 * 0.88, 0.000001, "HP: the tier's x1.7 and the pressure's -12%")
	check_near(Difficulty.spawn_mult(), 1.3 * 1.3, 0.000001, "density: the tier's x1.3 and the pressure's +30%")
	RunState.pressure_current = &"prs_hardened_peel"
	check_near(Pressure.enemy_hp_mult(), 1.35, 0.000001, "Hardened Peel HP")
	check_near(Pressure.enemy_speed_mult(), 0.9, 0.000001, "Hardened Peel speed")
	RunState.pressure_current = &"prs_paring_knives"
	check_near(Difficulty.enemy_damage_mult(), 1.45 * 1.35, 0.000001, "Paring Knives stacks with the tier")
	RunState.pressure_current = &"prs_weeping_fog"
	check_near(Pressure.enemy_speed_mult(), 1.1, 0.000001, "Weeping Fog enemy speed")
	RunState.pressure_current = &"prs_bitter_harvest"
	check_near(Pressure.elite_mult(), 2.0, 0.000001, "Bitter Harvest: twice the elites")
	check_near(Shrines.gold_mult(), 1.4, 0.000001, "pickup gold +40%")
	check_near(Shrines.xp_mult(), 1.4, 0.000001, "pickup XP +40%")
	var calm := EliteAffixes.expected_count(12, 2)
	RunState.pressure_live = false
	check_near(calm * 0.5, EliteAffixes.expected_count(12, 2), 0.000001, "the elite count doubles under Bitter Harvest only")


func test_an_enemy_made_under_pressure_carries_it() -> void:
	_run(&"tear_jerker")
	var plain := _enemy(&"skeleton_grunt", 7)
	RunState.pressure_current = &"prs_hardened_peel"
	RunState.pressure_live = true
	RunState.rng.seed = 5
	var peeled := _enemy(&"skeleton_grunt", 7)
	RunState.pressure_live = false
	RunState.rng.seed = 5
	var again := _enemy(&"skeleton_grunt", 7)
	check_near(peeled.max_hp, plain.max_hp * 1.35, 0.001, "Hardened Peel: +35% HP")
	check_near(peeled.move_speed, again.move_speed * 0.9, 0.0001, "and 10% slower")


func test_hero_effects_start_and_end_with_the_wave() -> void:
	_human("pad:a", &"warrior")
	var hero := _hero()
	_run(&"tear_jerker", 1)
	var haste := hero.stats.get_stat(Stats.HASTE)
	var speed := hero.stats.get_stat(Stats.SPEED)
	RunState.pressure_current = &"prs_wilting_heat"
	RunState.pressure_live = true
	Pressure.apply_to_hero(hero)
	check_near(hero.stats.get_stat(Stats.HASTE), haste - 10.0, 0.001, "Wilting Heat: Haste -10")
	var entries := hero.bonuses.effects_of(Pressure.SOURCE)
	check_eq(entries.size(), 2, "the cooldown entry and the Haste entry")
	check_eq(String(entries[0].get("kind", "")), "ability", "the cooldown side is an ability entry")
	Pressure.clear_hero(hero)
	check_near(hero.stats.get_stat(Stats.HASTE), haste, 0.001, "gone")
	check(hero.bonuses.effects_of(Pressure.SOURCE).is_empty(), "no source left")
	RunState.pressure_current = &"prs_weeping_fog"
	Pressure.apply_to_hero(hero)
	check_near(hero.stats.get_stat(Stats.SPEED), speed - 12.0, 0.001, "Weeping Fog: Speed -12")
	Pressure.apply_to_hero(null)
	Pressure.clear_hero(null)
	check(true, "a missing hero is skipped")


func test_wilting_heat_slows_the_cooldowns() -> void:
	_human("pad:a", &"warrior")
	var hero := _hero()
	var core: AbilityData = hero.abilities.slots[0]
	var base := hero.abilities.cooldown_of(core)
	RunState.pressure_current = &"prs_wilting_heat"
	RunState.pressure_live = true
	Pressure.apply_to_hero(hero)
	check_near(hero.abilities.cooldown_of(core), base * 1.2, 0.0001, "ability cooldowns +20%")


func test_the_main_break_path_walks_the_rotation() -> void:
	var opts := LaunchOptions.new()
	opts.difficulty = &"tear_jerker"
	opts.start_wave = 3
	_make_main(opts)
	_bots(2)
	main.start_run()
	check_eq(RunState.difficulty, &"tear_jerker", "the tier reached the run")
	check(RunState.pressure_live and RunState.pressure_current != &"", "wave 3 runs under a pressure")
	var first := RunState.pressure_current
	check(main.hud.pressure_chip.modulate.a > 0.5 and main.hud.pressure_chip.label.text == Db.get_pressure(first).display_name.to_upper(),
			"the HUD chip names it (%s)" % main.hud.pressure_chip.label.text)
	check(main.hud.difficulty_badge.visible and main.hud.difficulty_badge.label.text == "TEAR-JERKER", "and the tier's pill")
	_clear_wave_and_wait()
	check(not RunState.pressure_live, "not live in the break")
	check_eq(RunState.pressure_next_wave, 4, "the next wave is planned")
	check(main.intermission.next_label.text.contains("Pressure: "), "the break screen announces it: %s" % main.intermission.next_label.text)
	check(main.hud.pressure_chip.modulate.a < 0.1, "the chip empties")
	var planned := RunState.pressure_next
	main._on_intermission_continue()
	check_eq(main.wave, 4, "wave 4")
	check_eq(RunState.pressure_current, planned, "the planned pressure is in force")
	check_eq(String(main._pressure_log["4"]), String(planned), "and logged for the smoke result")


func test_a_boss_wave_has_no_pressure() -> void:
	var opts := LaunchOptions.new()
	opts.difficulty = &"tear_jerker"
	opts.start_wave = 10
	_make_main(opts)
	_bots(1)
	main.start_run()
	check(not RunState.pressure_live and RunState.pressure_current == &"", "the boss wave is calm")


func test_a_normal_run_shows_and_rolls_nothing() -> void:
	var opts := LaunchOptions.new()
	opts.start_wave = 4
	_make_main(opts)
	_bots(1)
	main.start_run()
	check(not main.hud.difficulty_badge.visible and not main.hud.pressure_chip.visible, "no pills on Normal")
	check(not RunState.pressure_live and RunState.pressure_next == &"", "no pressure")
	_clear_wave_and_wait()
	check_eq(RunState.pressure_next, &"", "nothing planned")
	check(not main.intermission.next_label.text.contains("Pressure"), "the break line is the base game's")
	var data := main.smoke_result("completed")
	check(not data.has("difficulty") and not data.has("pressures"), "SMOKE_RESULT keeps the base keys on Normal")


func test_the_smoke_result_names_the_tier_and_the_pressures() -> void:
	var opts := LaunchOptions.new()
	opts.difficulty = &"pungent"
	_make_main(opts)
	_bots(1)
	main.start_run()
	var data := main.smoke_result("completed")
	check_eq(data.get("difficulty"), "pungent", "the tier")
	check(data.has("pressures") and (data["pressures"] as Dictionary).is_empty(), "Pungent has no pressures")


# --- Selection ----------------------------------------------------------------------------------

func test_the_flag_is_validated() -> void:
	var ok := LaunchOptions.parse(PackedStringArray(["--difficulty=pungent"]))
	check_eq(ok.difficulty, &"pungent", "pungent")
	check(ok.unknown.is_empty(), "no complaint")
	check_eq(LaunchOptions.parse(PackedStringArray(["--difficulty=tear_jerker"])).difficulty, &"tear_jerker", "tear_jerker")
	check_eq(LaunchOptions.parse(PackedStringArray([])).difficulty, &"normal", "Normal by default")
	var bad := LaunchOptions.parse(PackedStringArray(["--difficulty=heroic"]))
	check_eq(bad.unknown, ["--difficulty=heroic"] as Array[String], "an unknown tier is an unknown argument")
	check_eq(bad.difficulty, &"normal", "and changes nothing")
	check(not LaunchOptions.parse(PackedStringArray(["--difficulty="])).unknown.is_empty(), "an empty value too")
	_make_main(bad)
	check_eq(main.smoke_outcome("completed"), "bad_args", "a smoke run with it ends as bad_args")


func test_a_run_never_plays_a_tier_the_party_has_not_unlocked() -> void:
	_fresh()
	var opts := LaunchOptions.new()
	opts.difficulty = &"tear_jerker"
	_make_main(opts)
	PlayerManager.add_bot(&"warrior", 1)
	main.start_run()
	check_eq(RunState.difficulty, &"normal", "a fresh profile can only play Normal")
	Meta.profile.unlock(Profile.KIND_DIFFICULTY, &"pungent", &"warrior")
	main.start_run()
	check_eq(RunState.difficulty, &"pungent", "capped at what the warrior unlocked")
	Meta.profile.unlock(Profile.KIND_DIFFICULTY, &"tear_jerker", &"warrior")
	main.start_run()
	check_eq(RunState.difficulty, &"tear_jerker", "open")
	Meta.profile = Profile.dev()
	opts.difficulty = &"pungent"
	main.start_run()
	check_eq(RunState.difficulty, &"pungent", "an automated run (dev profile) plays any tier")


func _lobby() -> Lobby:
	lobby = Lobby.create()
	UiFakes.add_to_root(tree, lobby)
	return lobby


func _join(input: PlayerInput, class_id: StringName) -> PlayerSlot:
	var slot := PlayerManager.join(input, Db.get_class_data(class_id))
	UiFakes.step(lobby)
	return slot


func test_the_lobby_selector_cycles_within_the_cap() -> void:
	_fresh()
	_lobby()
	var changes: Array[StringName] = []
	lobby.difficulty_changed.connect(func(id: StringName) -> void: changes.append(id))
	var a := UiFakes.HumanInput.new("pad:a")
	var slot := _join(a, &"warrior")
	check_eq(lobby.difficulty, &"normal", "Normal by default")
	check_eq(lobby.difficulty_label.text, "Difficulty: Normal", "the header")
	UiFakes.tap(lobby, a, PlayerInput.Pad.SELECT)
	check_eq(lobby.difficulty, &"normal", "a fresh warrior is capped at Normal")
	check(changes.is_empty(), "nothing changed")
	check(lobby._lock_notice.contains("Pungent is locked") and lobby._lock_notice.contains("Win a run on Normal with the Warrior"),
			"the footer says why: %s" % lobby._lock_notice)
	Meta.profile.unlock(Profile.KIND_DIFFICULTY, &"pungent", &"warrior")
	UiFakes.tap(lobby, a, PlayerInput.Pad.SELECT)
	check_eq(lobby.difficulty, &"pungent", "Pungent once the warrior has won on Normal")
	check_eq(changes, [&"pungent"] as Array[StringName], "Main is told")
	check_eq(lobby.difficulty_label.text, "Difficulty: Pungent", "the header follows")
	UiFakes.tap(lobby, a, PlayerInput.Pad.SELECT)
	check_eq(lobby.difficulty, &"normal", "Tear-Jerker is locked: the choice wraps to Normal")
	check(lobby._lock_notice.contains("Tear-Jerker is locked") and lobby._lock_notice.contains("Win a run on Pungent with the Warrior"), "and says why: %s" % lobby._lock_notice)
	check_eq(Difficulty.lock_reason(&"tear_jerker", [&"mage"] as Array[StringName]), "Win a run on Normal with the Mage", "the first missing step, not the last")
	check_eq(Difficulty.lock_reason(&"normal", [&"mage"] as Array[StringName]), "", "Normal is never locked")
	check_eq(Difficulty.lock_reason(&"pungent", [&"warrior"] as Array[StringName]), "", "open for the warrior")
	Meta.profile.unlock(Profile.KIND_DIFFICULTY, &"tear_jerker", &"warrior")
	UiFakes.tap(lobby, a, PlayerInput.Pad.SELECT)
	UiFakes.tap(lobby, a, PlayerInput.Pad.SELECT)
	check_eq(lobby.difficulty, &"tear_jerker", "all three open")
	check(slot != null, "(joined)")


func test_the_party_cap_is_the_lowest_class() -> void:
	_fresh()
	Meta.profile.unlock(Profile.KIND_DIFFICULTY, &"pungent", &"warrior")
	_lobby()
	var a := UiFakes.HumanInput.new("pad:a")
	var b := UiFakes.HumanInput.new("pad:b")
	_join(a, &"warrior")
	_join(b, &"mage")
	UiFakes.tap(lobby, a, PlayerInput.Pad.SELECT)
	check_eq(lobby.difficulty, &"normal", "the mage has not won: Normal only")
	check(lobby._lock_notice.contains("Mage"), "the mage is named: %s" % lobby._lock_notice)
	check_eq(Difficulty.selectable(lobby.party_classes()), [&"normal"] as Array[StringName], "selectable")


func test_a_class_change_lowers_the_choice() -> void:
	_fresh()
	Meta.profile.unlock(Profile.KIND_DIFFICULTY, &"pungent", &"warrior")
	_lobby()
	var changes: Array[StringName] = []
	lobby.difficulty_changed.connect(func(id: StringName) -> void: changes.append(id))
	var a := UiFakes.HumanInput.new("pad:a")
	var slot := _join(a, &"warrior")
	UiFakes.tap(lobby, a, PlayerInput.Pad.SELECT)
	check_eq(lobby.difficulty, &"pungent", "Pungent for the warrior")
	slot.class_data = Db.get_class_data(&"mage")
	UiFakes.step(lobby)
	check_eq(lobby.difficulty, &"normal", "the mage lowers it")
	check_eq(changes, [&"pungent", &"normal"] as Array[StringName], "and Main is told")


func test_set_difficulty_shows_without_telling_anybody() -> void:
	_lobby()
	var told := [0]
	lobby.difficulty_changed.connect(func(_id: StringName) -> void: told[0] += 1)
	lobby.set_difficulty(&"tear_jerker")
	check_eq(lobby.difficulty_label.text, "Difficulty: Tear-Jerker", "the header")
	lobby.set_difficulty(&"junk")
	check_eq(lobby.difficulty, &"normal", "an unknown id is Normal")
	check_eq(told[0], 0, "silent")


func test_a_change_during_the_countdown_unreadies_the_player() -> void:
	_lobby()
	var a := UiFakes.HumanInput.new("pad:a")
	var slot := _join(a, &"warrior")
	slot.ready = true
	lobby.countdown_left = 2.0
	lobby.cycle_difficulty(slot)
	check(not slot.ready and not lobby.is_counting_down(), "everybody sees the new tier before the run starts")


func test_main_stores_the_lobbys_choice_and_passes_the_flag_to_the_lobby() -> void:
	var opts := LaunchOptions.new()
	opts.difficulty = &"pungent"
	_make_main(opts)
	main.go_to_lobby()
	check_eq(main.lobby.difficulty, &"pungent", "the lobby opens on --difficulty")
	main.lobby.difficulty_changed.emit(&"tear_jerker")
	check_eq(main.options.difficulty, &"tear_jerker", "configure_difficulty stores the choice")
	main.configure_difficulty(&"junk")
	check_eq(main.options.difficulty, &"normal", "an unknown id plays as Normal")


# --- The leaderboard ----------------------------------------------------------------------------------

func test_leaderboard_categories_include_the_difficulty() -> void:
	check_eq(Leaderboard.category_key(&"normal", false, 2), "normal/standard/2", "Normal keeps its key")
	check_eq(Leaderboard.category_key(&"normal", false, 2, &"normal"), "normal/standard/2", "also when asked for")
	check_eq(Leaderboard.category_key(&"endless", true, 4, &"pungent"), "endless/hardcore/4/pungent", "Pungent appends")
	check_eq(Leaderboard.category_key(&"normal", false, 1, &"tear_jerker"), "normal/standard/1/tear_jerker", "Tear-Jerker appends")
	check_eq(Leaderboard.category_key(&"normal", false, 1, &"junk"), "normal/standard/1", "an unknown tier is Normal")
	check_eq(Leaderboard.difficulty_of_key("normal/standard/1/pungent"), &"pungent", "the tier of a key")
	check_eq(Leaderboard.difficulty_of_key("normal/standard/1"), &"normal", "a plain key is Normal")
	check_eq(Leaderboard.mode_of_key("endless/hardcore/4/pungent"), &"endless", "the mode survives the suffix")
	check_eq(Leaderboard.category_text(&"normal", false, 2, &"pungent"), "Normal · 2 players · Pungent", "the title")
	check_eq(Leaderboard.category_text(&"normal", false, 2), "Normal · 2 players", "Normal adds nothing")


func test_boards_of_different_tiers_are_separate() -> void:
	var board := Leaderboard.create(_tmp)
	var normal := Leaderboard.make_entry(25, 1500.0, [&"mage"], true, "2026-01-01 10:00:00")
	var hard := Leaderboard.make_entry(25, 1900.0, [&"mage"], true, "2026-01-02 10:00:00", &"pungent")
	check_eq(normal["difficulty"], "normal", "an entry carries its tier")
	check_eq(hard["difficulty"], "pungent", "a Pungent one")
	check_eq(board.add_entry(normal, &"normal", false, 1), 0, "first on the Normal board")
	check_eq(board.add_entry(hard, &"normal", false, 1, &"pungent"), 0, "and first on the Pungent board")
	check_eq(board.entries_for(&"normal", false, 1).size(), 1, "one each")
	check_eq(board.entries_for(&"normal", false, 1, &"pungent").size(), 1, "one each")
	check(board.categories.has("normal/standard/1") and board.categories.has("normal/standard/1/pungent"), "two categories")
	check_eq(board.best_for(&"normal", false, 1, &"pungent")["time"], 1900.0, "the Pungent best")
	check_eq(board.rank_of(hard, &"normal", false, 1, &"tear_jerker"), 0, "an empty Tear-Jerker board would rank it first")


func test_a_version_1_file_is_migrated_and_saved_as_version_2() -> void:
	var f := FileAccess.open(_tmp, FileAccess.WRITE)
	f.store_string('{"version": 1, "categories": {"normal/standard/2": [{"wave": 25, "time": 1500.0, "classes": ["mage"], "date": "2026-01-01 10:00:00", "victory": true}]}}')
	f.close()
	check_eq(Leaderboard.FORMAT_VERSION, 2, "the format is version 2")
	var board := Leaderboard.create(_tmp)
	check_eq(board.load_file(), OK, "a version 1 file loads")
	check_eq(board.load_error, "", "without a complaint")
	var entries := board.entries_for(&"normal", false, 2)
	check_eq(entries.size(), 1, "its entry is there")
	check_eq(entries[0]["difficulty"], "normal", "now a Normal entry")
	check_eq(board.add_entry(Leaderboard.make_entry(25, 1400.0, [&"mage"], true), &"normal", false, 2), 0, "a new best")
	check_eq(board.save_file(), OK, "saved")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(_tmp))
	check(raw is Dictionary and int(raw["version"]) == 2, "written as version 2")
	check(raw["categories"].has("normal/standard/2"), "the Normal key did not move")
	check_eq(raw["categories"]["normal/standard/2"][1]["difficulty"], "normal", "the old entry was given its tier")


func test_the_migration_steps() -> void:
	var data := {"version": 1, "categories": {"normal/standard/1": [{"wave": 3}, "junk"], "bad": 5}}
	var up := Leaderboard.migrate(data)
	check_eq(int(up["version"]), 2, "to version 2")
	check_eq(up["categories"]["normal/standard/1"][0]["difficulty"], "normal", "entries get Normal")
	check(not data["categories"]["normal/standard/1"][0].has("difficulty") and int(data["version"]) == 1, "the input is not changed")
	check_eq(int(Leaderboard.migrate({"version": 2, "categories": {}})["version"]), 2, "current stays")
	check_eq(int(Leaderboard.migrate({"version": 9, "categories": {}})["version"]), 9, "a newer version is left alone")
	check_eq(int(Leaderboard.migrate({"categories": {}})["version"]), 2, "no version counts as 0")


func test_a_newer_file_is_still_read_only() -> void:
	var f := FileAccess.open(_tmp, FileAccess.WRITE)
	f.store_string('{"version": 3, "categories": {}}')
	f.close()
	var board := Leaderboard.create(_tmp)
	board.load_file()
	check(board.read_only and board.load_error == "newer version", "never overwritten")


func test_recording_a_run_files_it_under_its_tier() -> void:
	var saved_path := Leaderboard.path_override
	var saved_writes := Leaderboard.writes_enabled
	Leaderboard.path_override = _tmp
	Leaderboard.writes_enabled = true
	var entry := Leaderboard.make_entry(25, 1500.0, [&"mage"], true, "", &"tear_jerker")
	var outcome := Leaderboard.record_run(entry, &"normal", false, 1, &"tear_jerker")
	check_eq(outcome["rank"], 0, "ranked first on the Tear-Jerker board")
	var board := Leaderboard.create(_tmp)
	board.load_file()
	check(board.categories.has("normal/standard/1/tear_jerker") and not board.categories.has("normal/standard/1"), "only the Tear-Jerker category")
	var model := Leaderboard.screen_model(board, entry, &"normal", false, 1, 0, false, &"tear_jerker")
	check_eq(model["key"], "normal/standard/1/tear_jerker", "the model's key")
	check_eq(model["difficulty"], &"tear_jerker", "the tier")
	check(String(model["category_text"]).ends_with("Tear-Jerker"), "the board's title names it: %s" % model["category_text"])
	Leaderboard.path_override = saved_path
	Leaderboard.writes_enabled = saved_writes


# --- What the screens show ----------------------------------------------------------------------------

func test_the_hud_shows_the_tier_pill_only_off_normal() -> void:
	_run(&"normal")
	var hud := Hud.create()
	tree.root.add_child(hud)
	nodes.append(hud)
	check(not hud.difficulty_badge.visible and not hud.pressure_chip.visible, "Normal: nothing")
	_run(&"pungent")
	var hud2 := Hud.create()
	tree.root.add_child(hud2)
	nodes.append(hud2)
	check(hud2.difficulty_badge.visible and hud2.difficulty_badge.label.text == "PUNGENT", "Pungent: the amber pill")
	check(not hud2.pressure_chip.visible, "but no pressure chip")
	_run(&"tear_jerker")
	var hud3 := Hud.create()
	tree.root.add_child(hud3)
	nodes.append(hud3)
	check(hud3.difficulty_badge.visible and hud3.pressure_chip.visible and hud3.pressure_chip.modulate.a == 0.0, "Tear-Jerker: the pill and an empty chip that keeps its place")


func test_the_end_screen_and_the_run_card_name_the_tier() -> void:
	_run(&"pungent")
	var screen := GameOverScreen.create()
	tree.root.add_child(screen)
	nodes.append(screen)
	screen.open(false)
	check(screen.difficulty_badge.visible and screen.difficulty_badge.label.text == "PUNGENT", "the end screen's pill")
	_run(&"normal")
	screen.open(false)
	check(not screen.difficulty_badge.visible, "none on Normal")
	var model := RunCard.model({"difficulty": "Pungent", "mode": "Normal"})
	check_eq(model["difficulty"], "Pungent", "the card's model")
	check_eq(RunCard.model({})["difficulty"], "Normal", "Normal by default")
	var view := RunCardView.create(model)
	nodes.append(view)
	check(view != null, "the card draws")
	_run(&"tear_jerker")
	check_eq(RunSummary.collect(false)["difficulty"], "Tear-Jerker", "the summary carries the tier's name")


func test_a_report_carries_the_tier() -> void:
	_run(&"pungent")
	var report := RunReport.collect(false, false, {"difficulty": RunState.difficulty, "classes": [&"mage"]})
	check_eq(report.difficulty, &"pungent", "the report")
	check_eq(report.flag(&"difficulty"), "pungent", "and its flag")
	var opts := LaunchOptions.new()
	_make_main(opts)
	check_eq(main._report_extras()["difficulty"], &"pungent", "Main hands the tier to every report")
