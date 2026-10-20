extends TestCase
## M9 LEVELS: Class XP (formula, co-op sum, catch-up, first-win bonus, the difficulty hook), the 30-level curve, the Seeds
## of a run and the level gifts, the reward path (every reward unlocks at its level; the locked abilities, capstone trees and
## the Hunter / Shaman classes are held back for a fresh profile), the level-derived slots, the alternative starting weapon,
## the raw-power bonuses (real profiles only), the lobby card and the end-screen panel, and the save round trip.

const UiFakes := preload("res://tests/ui_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const Fakes := preload("res://tests/player_fakes.gd")

## The design's per-class path (design 1.3): the four starting abilities of the deck, the two that join at level 2 / 4, the
## trees whose capstone opens at level 8 / 16 / 24 with that capstone's talent id, the alternative weapon.
const PATHS := {
	&"warrior": {"start": [&"battle_shout", &"execute", &"shield_wall", &"thunder_clap"], "locked": [&"heroic_leap", &"bladestorm"],
		"trees": [&"warrior_fury", &"warrior_protection", &"warrior_arms"],
		"capstones": [&"warrior_fury_rampage", &"warrior_protection_unbreakable", &"warrior_arms_mortal_strike"], "alt": [&"two_hand_sword", &""]},
	&"mage": {"start": [&"arcane_missiles", &"fireball", &"frost_nova", &"ice_barrier"], "locked": [&"meteor", &"pyroblast"],
		"trees": [&"mage_arcane", &"mage_fire", &"mage_frost"],
		"capstones": [&"mage_arcane_arcane_power", &"mage_fire_combustion", &"mage_frost_ice_lance"], "alt": [&"staff", &""]},
	&"paladin": {"start": [&"avengers_shield", &"blessing_of_kings", &"divine_storm", &"hammer_of_justice"], "locked": [&"lay_on_hands", &"divine_shield"],
		"trees": [&"paladin_retribution", &"paladin_holy", &"paladin_protection"],
		"capstones": [&"paladin_retribution_seal_of_command", &"paladin_holy_holy_shock", &"paladin_protection_holy_shield"], "alt": [&"two_hand_mace", &""]},
	&"rogue": {"start": [&"blade_flurry", &"cheat_death", &"poison_bomb", &"shuriken_toss"], "locked": [&"killing_spree", &"shadowstep"],
		"trees": [&"rogue_combat", &"rogue_assassination", &"rogue_subtlety"],
		"capstones": [&"rogue_combat_adrenaline_rush", &"rogue_assassination_cold_blood", &"rogue_subtlety_shadow_dance"], "alt": [&"gun", &""]},
	&"warlock": {"start": [&"corruption", &"seed_of_corruption", &"shadow_bolt", &"summon_voidwalker"], "locked": [&"summon_infernal", &"fear"],
		"trees": [&"warlock_demonology", &"warlock_affliction", &"warlock_destruction"],
		"capstones": [&"warlock_demonology_soul_link", &"warlock_affliction_unstable_affliction", &"warlock_destruction_conflagrate"], "alt": [&"wand", &"orb"]},
	&"hunter": {"start": [&"arrow_hail", &"blast_snare", &"hunt_signal", &"quick_draw"], "locked": [&"long_shot", &"play_dead"],
		"trees": [&"hunter_packlord", &"hunter_sharpshot", &"hunter_wildcraft"],
		"capstones": [&"hunter_packlord_pack_frenzy", &"hunter_sharpshot_steady_aura", &"hunter_wildcraft_firebug_bombs"], "alt": [&"crossbow", &""]},
	&"shaman": {"start": [&"magma_lash", &"rumbling_earth", &"stormburst", &"thunderbolt"], "locked": [&"soothing_downpour", &"spirit_pack"],
		"trees": [&"shaman_warspirit", &"shaman_stormweaving", &"shaman_wellspring"],
		"capstones": [&"shaman_warspirit_gale_strike", &"shaman_stormweaving_elemental_surge", &"shaman_wellspring_bond_totem"], "alt": [&"staff", &""]},
}
const ABILITY_LEVELS: Array[int] = [2, 4]
const CAPSTONE_LEVELS: Array[int] = [8, 16, 24]

var _tmp_path := "user://m9_levels_test_%d.json" % OS.get_process_id()
var _saved_profile: Profile
var _saved_path := ""
var _saved_persist := false
var _saved_listeners: Array[Dictionary] = []
var _saved_xp_hook := Callable()
var _saved_seeds_hook := Callable()
var _nodes: Array[Node] = []
var main: Main
var world: Node3D
var rng: RandomNumberGenerator


func before_each() -> void:
	_saved_profile = Meta.profile
	_saved_path = Meta.path
	_saved_persist = Meta.persist
	_saved_listeners = Meta._listeners.duplicate()
	_saved_xp_hook = ClassLevels.xp_mult_hook
	_saved_seeds_hook = ClassLevels.seeds_mult_hook
	Meta.save_count = 0
	Meta._pending_unlocks.clear()
	UiFakes.reset_players()
	tree.paused = false
	rng = RandomNumberGenerator.new()
	rng.seed = 4242


func after_each() -> void:
	_free_main()
	if world != null:
		EFakes.free_world(tree, world)
		world = null
	for n in _nodes:
		UiFakes.free_node(n)
	_nodes.clear()
	Meta.profile = _saved_profile
	Meta.path = _saved_path
	Meta.persist = _saved_persist
	Meta._listeners = _saved_listeners
	Meta._pending_unlocks.clear()
	Meta._batching = false
	ClassLevels.xp_mult_hook = _saved_xp_hook
	ClassLevels.seeds_mult_hook = _saved_seeds_hook
	for suffix in ["", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(_tmp_path + suffix):
			DirAccess.remove_absolute(_tmp_path + suffix)
	RunState.free_rerolls = 0
	tree.paused = false
	UiFakes.reset_players()
	Enemy.invalidate_player_cache()


# --- Helpers ------------------------------------------------------------------------------------

func _use_fresh() -> Profile:
	Meta.profile = Profile.fresh()
	Meta.persist = false
	Meta.path = ""
	return Meta.profile


func _use_file() -> Profile:
	Meta.profile = Profile.fresh()
	Meta.persist = true
	Meta.path = _tmp_path
	return Meta.profile


func _party(ids: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in ids:
		out.append(StringName(str(id)))
	return out


## A report of [param ids] as the party; [param kills] is the kills per hero in party order.
func _report(victory: bool, p_stats: Dictionary, ids: Array, kills: Array = [], p_flags: Dictionary = {}) -> RunReport:
	var heroes: Array[Dictionary] = []
	for i in ids.size():
		heroes.append({"slot": i, "class_id": str(ids[i]), "kills": int(kills[i]) if i < kills.size() else 0})
	return RunReport.make(_party(ids), victory, p_stats, p_flags, heroes)


func _make_main() -> Main:
	main = Main.create(LaunchOptions.new())
	tree.root.add_child(main)
	return main


func _run_with_bots(ids: Array) -> void:
	_make_main()
	for i in ids.size():
		PlayerManager.add_bot(StringName(str(ids[i])), i + 1)
	main.start_run()


func _free_main() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null


## Puts [param class_id] of [param profile] at [param level] through the real path (the XP and what the levels give).
func _level_to(profile: Profile, class_id: StringName, level: int) -> void:
	ClassLevels.award_xp(profile, class_id, ClassLevels.xp_for_level(level) - profile.class_xp(class_id))


func _solo_stats(waves: int, extra: Dictionary = {}) -> Dictionary:
	var out := {"waves_cleared": waves, "wave": waves + 1, "party_size": 1}
	out.merge(extra, true)
	return out


# --- Class XP -----------------------------------------------------------------------------------

func test_the_table_is_the_design_curve() -> void:
	var t := ClassLevels.table()
	check_eq(t.xp_to_next.size(), 29, "29 level costs")
	var sum := 0
	for c in t.xp_to_next:
		sum += c
	check_eq(sum, 33205, "level 30 needs 33205 XP in all")
	check_eq(ClassLevels.xp_for_level(1), 0, "level 1 is free")
	check_eq(ClassLevels.xp_for_level(2), 95, "level 2")
	check_eq(ClassLevels.xp_for_level(5), 545, "level 5")
	check_eq(ClassLevels.xp_for_level(10), 2175, "level 10")
	check_eq(ClassLevels.xp_for_level(20), 11335, "level 20")
	check_eq(ClassLevels.xp_for_level(24), 18235, "level 24")
	check_eq(ClassLevels.xp_for_level(30), 33205, "level 30")
	check_eq(ClassLevels.xp_to_next(1), 95, "the first cost")
	check_eq(ClassLevels.xp_to_next(29), 2925, "the last cost")
	check_eq(ClassLevels.xp_to_next(30), 0, "nothing past the top")
	check_eq(ClassLevels.max_level(), 30, "max level")


func test_level_thresholds() -> void:
	check_eq(ClassLevels.level_for_xp(0), 1, "no XP: level 1")
	check_eq(ClassLevels.level_for_xp(94), 1, "one short of level 2")
	check_eq(ClassLevels.level_for_xp(95), 2, "level 2 exactly")
	check_eq(ClassLevels.level_for_xp(214), 2, "one short of 3")
	check_eq(ClassLevels.level_for_xp(215), 3, "level 3")
	check_eq(ClassLevels.level_for_xp(33204), 29, "one short of 30")
	check_eq(ClassLevels.level_for_xp(33205), 30, "level 30")
	check_eq(ClassLevels.level_for_xp(999999), 30, "capped")
	for level in range(1, 31):
		check_eq(ClassLevels.level_for_xp(ClassLevels.xp_for_level(level)), level, "level %d starts at its XP" % level)
	var p := ClassLevels.progress(215 + 75, 3)
	check_eq(p["level"], 3, "the bar's level")
	check_eq(p["into"], 75, "XP into the level")
	check_eq(p["needed"], 150, "level 3 costs 150")
	check_near(p["fraction"], 0.5, 0.001, "half way")
	check(ClassLevels.progress(40000, 30)["max"], "the top level has no bar")
	check_near(ClassLevels.progress(0, 30)["fraction"], 1.0, 0.001, "a stored level above the XP (max profile) is a full bar")


func test_the_xp_formula() -> void:
	var profile := _use_fresh()
	# 8 waves, nothing else: sum of 6 + 0.5 w = 66; own kills 0.03 each.
	var r := _report(false, _solo_stats(8), ["warrior"], [100])
	check_near(ClassLevels.team_xp(r), 66.0, 0.001, "eight waves")
	var run := ClassLevels.run_xp(r, profile)
	check_eq(run.size(), 1, "one class")
	check_near(run[0]["raw"], 69.0, 0.001, "plus 0.03 per kill")
	check_eq(run[0]["xp"], 69, "rounded")
	# Elites are capped at 60, bosses give 40 each, the final boss 150.
	check_near(ClassLevels.team_xp(_report(false, _solo_stats(1, {"elites_killed": 10}), ["warrior"])), 6.5 + 15.0, 0.001, "1.5 per elite")
	check_near(ClassLevels.team_xp(_report(false, _solo_stats(1, {"elites_killed": 500}), ["warrior"])), 6.5 + 60.0, 0.001, "elites cap at 60")
	check_near(ClassLevels.team_xp(_report(false, _solo_stats(1, {"bosses_killed": 2}), ["warrior"])), 6.5 + 80.0, 0.001, "40 per boss")
	check_near(ClassLevels.team_xp(_report(true, _solo_stats(1), ["warrior"])), 6.5 + 150.0, 0.001, "the final boss: a victory")
	# The wave term stops growing at wave 30: Endless waves 31+ are worth 21.
	var long := ClassLevels.team_xp(_report(false, _solo_stats(32), ["warrior"]))
	var to_30 := ClassLevels.team_xp(_report(false, _solo_stats(30), ["warrior"]))
	check_near(long - to_30, 2.0 * 21.0, 0.001, "waves past 30 are worth 21 each")
	# A full Normal win: waves 1..25 = 312.5, 30 elites (45), 2 bosses (80), the final boss (150), 800 kills (24).
	var win := _report(true, _solo_stats(25, {"elites_killed": 30, "bosses_killed": 2}), ["warrior"], [800])
	var win_run := ClassLevels.run_xp(win, profile)
	check_near(win_run[0]["raw"], 312.5 + 45.0 + 80.0 + 150.0 + 24.0, 0.001, "a win")
	check_eq(win_run[0]["first_win_bonus"], 250, "plus the first Normal win bonus")
	check_eq(win_run[0]["xp"], roundi(611.5) + 250, "612 + 250")
	# The Endless run that kills the wave-25 boss counts as a final-boss kill too.
	var endless := _report(false, _solo_stats(26), ["warrior"], [], {"endless": true})
	endless.endless = true
	check(ClassLevels.final_boss_down(endless), "endless: wave 25 cleared")
	endless.waves_cleared = 24
	check(not ClassLevels.final_boss_down(endless), "endless: not yet")
	check(not ClassLevels.final_boss_down(_report(false, _solo_stats(25), ["warrior"])), "a defeat is no final boss")


func test_two_heroes_of_one_class_add_up() -> void:
	var profile := _use_fresh()
	var r := _report(false, {"waves_cleared": 4, "wave": 5, "party_size": 3, "bosses_killed": 1}, ["warrior", "warrior", "mage"], [50, 150, 10])
	var team := 6.5 + 7.0 + 7.5 + 8.0 + 40.0
	check_near(ClassLevels.team_xp(r), team, 0.001, "the team's share")
	var run := ClassLevels.run_xp(r, profile)
	check_eq(run.size(), 2, "two classes")
	check_eq(run[0]["class_id"], &"warrior", "in party order")
	check_eq(run[0]["heroes"], 2, "two warrior shares")
	check_near(run[0]["raw"], 2.0 * team + 0.03 * 200, 0.001, "two shares and both heroes' kills")
	check_eq(run[1]["heroes"], 1, "one mage share")
	check_near(run[1]["raw"], team + 0.03 * 10, 0.001, "the mage")
	# Through the run-end hook: the class XP of the profile.
	Meta.record_run(r)
	check_eq(profile.class_xp(&"warrior"), roundi(2.0 * team + 6.0), "the warrior got both shares")
	check_eq(profile.class_xp(&"mage"), roundi(team + 0.3), "the mage one")
	check_eq(profile.class_xp(&"rogue"), 0, "a class that did not play gets nothing")


func test_catch_up_and_the_first_win_bonus() -> void:
	var profile := _use_fresh()
	_level_to(profile, &"warrior", 15)
	var r := _report(false, _solo_stats(8), ["mage"])
	var run := ClassLevels.run_xp(r, profile)
	check_near(run[0]["catchup"], 1.5, 0.001, "a level 1 mage far behind the level 15 warrior")
	check_eq(run[0]["xp"], roundi(66.0 * 1.5), "earns half as much again")
	check_near(ClassLevels.run_xp(_report(false, _solo_stats(8), ["warrior"]), profile)[0]["catchup"], 1.0, 0.001, "the leader gets no catch-up")
	check_near(ClassLevels.catchup_multiplier(9, 19), 1.5, 0.001, "ten levels behind")
	check_near(ClassLevels.catchup_multiplier(10, 19), 1.0, 0.001, "nine behind")
	check_near(ClassLevels.catchup_multiplier(20, 30), 1.0, 0.001, "not from level 20 up")
	check_near(ClassLevels.catchup_multiplier(19, 30), 1.5, 0.001, "level 19 still gets it")
	# The first-win bonus: once per class and tier, never multiplied.
	var fresh := _use_fresh()
	var win := _report(true, _solo_stats(1), ["rogue"], [], {"difficulty": "pungent"})
	win.difficulty = &"pungent"
	var first := ClassLevels.run_xp(win, fresh)
	check_eq(first[0]["first_win_bonus"], 400, "Pungent: 400")
	Meta.record_run(win)
	check_eq(fresh.class_xp(&"rogue"), roundi(156.5) + 400, "the bonus is part of the XP")
	var win2 := _report(true, _solo_stats(1), ["rogue"])
	win2.difficulty = &"pungent"
	check_eq(ClassLevels.run_xp(win2, fresh)[0]["first_win_bonus"], 0, "not the second time on that tier")
	win2.difficulty = &"tear_jerker"
	check_eq(ClassLevels.run_xp(win2, fresh)[0]["first_win_bonus"], 600, "but a new tier pays again")
	win2.difficulty = &"normal"
	check_eq(ClassLevels.run_xp(win2, fresh)[0]["first_win_bonus"], 250, "Normal: 250")
	check_eq(ClassLevels.run_xp(win2, fresh)[0]["xp"] , roundi(156.5) + 250, "and the multiplier does not touch it")
	ClassLevels.xp_mult_hook = func(_d: StringName) -> float: return 2.0
	check_eq(ClassLevels.run_xp(win2, fresh)[0]["xp"], roundi(156.5 * 2.0) + 250, "even with a difficulty multiplier")


func test_the_difficulty_hook_scales_xp_and_seeds() -> void:
	var profile := _use_fresh()
	var r := _report(false, _solo_stats(8), ["warrior"])
	check_near(ClassLevels.xp_multiplier(r), 1.0, 0.0001, "no hook: 1.0")
	check_near(ClassLevels.seeds_multiplier(r), 1.0, 0.0001, "no hook: 1.0 for the Seeds too")
	var seen: Array[StringName] = []
	ClassLevels.xp_mult_hook = func(d: StringName) -> float:
		seen.append(d)
		return 1.5 if d == &"pungent" else 1.0
	ClassLevels.seeds_mult_hook = func(_d: StringName) -> float: return 2.5
	r.difficulty = &"pungent"
	check_near(ClassLevels.xp_multiplier(r), 1.5, 0.0001, "the hook is read with the run's tier")
	check_eq(seen, [&"pungent"] as Array[StringName], "with the difficulty id")
	check_eq(ClassLevels.run_xp(r, profile)[0]["xp"], roundi(66.0 * 1.5), "XP x 1.5")
	var base := ClassLevels.run_seeds(_report(false, _solo_stats(8), ["warrior"], [], {}))
	check_eq(ClassLevels.run_seeds(r), roundi(12.0 * 2.5), "Seeds x 2.5 (%d without)" % base)
	ClassLevels.xp_mult_hook = func(_d: StringName) -> float: return 0.0
	check_near(ClassLevels.xp_multiplier(r), 1.0, 0.0001, "a broken hook (0) falls back to 1.0")
	ClassLevels.xp_mult_hook = Callable()
	check_near(ClassLevels.xp_multiplier(r), 1.0, 0.0001, "an unset hook too")


# --- Seeds --------------------------------------------------------------------------------------

func test_seeds_of_a_run() -> void:
	# Design examples: Normal win solo ~114, 4 players ~176; defeats 15 / 33 / 47.
	var win := _report(true, {"waves_cleared": 25, "wave": 25, "party_size": 1, "bosses_killed": 2, "kills": 5000}, ["warrior"])
	check_eq(ClassLevels.run_seeds(win), 114, "a solo win: 37.5 + 24 + 40 + 12")
	var party := _report(true, {"waves_cleared": 25, "wave": 25, "party_size": 4, "bosses_killed": 2, "kills": 13600}, ["warrior", "mage", "paladin", "rogue"])
	check_eq(ClassLevels.run_seeds(party), 176, "four players: (37.5 + 24 + 40 + 34) x 1.3")
	check_eq(ClassLevels.run_seeds(_report(false, {"waves_cleared": 8, "party_size": 1, "kills": 1200}, ["warrior"])), 15, "a defeat on wave 9")
	check_eq(ClassLevels.run_seeds(_report(false, {"waves_cleared": 0, "party_size": 1}, ["warrior"])), 0, "nothing for nothing")
	var huge := _report(true, {"waves_cleared": 99, "party_size": 4, "bosses_killed": 20, "kills": 999999}, ["warrior", "mage", "paladin", "rogue"])
	check_eq(ClassLevels.run_seeds(huge), 400, "capped at 400")


func test_the_seeds_listener_pays_the_wallet_once() -> void:
	var profile := _use_file()
	var seen: Array[int] = []
	Meta.seeds_changed.connect(func(total: int, delta: int) -> void: seen.append(delta), CONNECT_ONE_SHOT)
	var r := _report(true, {"waves_cleared": 25, "wave": 25, "party_size": 1, "bosses_killed": 2, "kills": 5000}, ["warrior"])
	var result := Meta.record_run(r)
	var seeds: Dictionary = result["seeds"]
	check_eq(seeds["run"], 114, "the run's Seeds")
	check_eq(seeds["gifts"], int(result["level_seeds"]), "the level gifts of the new levels")
	check_eq(profile.seeds, 114 + int(result["level_seeds"]), "the wallet has both")
	check_eq(seeds["wallet"], profile.seeds, "the result tells the wallet")
	check_eq(profile.seeds_earned, profile.seeds, "lifetime Seeds")
	check_eq(seen.size(), 1, "one seeds_changed for the run")
	check_eq(Profile.load_file(_tmp_path).seeds, profile.seeds, "saved")
	var again := Meta.record_run(r)
	check(not again["recorded"], "a report counts once")
	check_eq(profile.seeds, 114 + int(result["level_seeds"]), "so the wallet did not move")


func test_level_gifts() -> void:
	check_eq(ClassLevels.level_gift(1), 0, "nothing for level 1")
	check_eq(ClassLevels.level_gift(2), 7, "5 + level on a level with a reward")
	check_eq(ClassLevels.level_gift(30), 35, "level 30 has a reward")
	var empty: Array[int] = []
	for level in range(2, 31):
		if ClassLevels.rewards_at(&"warrior", level).is_empty():
			empty.append(level)
	check_eq(empty, [18, 22, 23, 26, 27, 28, 29] as Array[int], "seven levels with no reward")
	for level in empty:
		check_eq(ClassLevels.level_gift(level), (5 + level) * 2, "doubled on level %d" % level)
	var total := 0
	for level in range(2, 31):
		total += ClassLevels.level_gift(level)
	check_eq(total, 817, "817 Seeds of gifts per class")
	var profile := _use_fresh()
	var award := ClassLevels.award_xp(profile, &"mage", ClassLevels.xp_for_level(5))
	check_eq(award["level_after"], 5, "four levels at once")
	check_eq(award["gift_seeds"], 7 + 8 + 9 + 10, "one gift per level")
	check_eq(profile.seeds, 34, "paid to the wallet")


# --- The reward path ----------------------------------------------------------------------------

func test_the_class_paths_match_the_design() -> void:
	for class_id: StringName in PATHS:
		var spec: Dictionary = PATHS[class_id]
		var path := Db.class_path(class_id)
		check(path != null, "%s has a level path" % class_id)
		if path == null:
			continue
		check_eq(path.deck_abilities, spec["locked"] as Array[StringName], "%s: the abilities of level 2 and 4" % class_id)
		check_eq(path.capstone_trees, spec["trees"] as Array[StringName], "%s: the capstone trees of level 8 / 16 / 24" % class_id)
		# The class's learnable abilities are the 4 of the start deck + the 2 locked ones.
		var learnable: Array[StringName] = []
		for id in Db.abilities:
			var a := Db.abilities[id]
			if a.class_id == class_id and a.is_learned_kind() and a.card_weight > 0.0:
				learnable.append(id)
		var want: Array[StringName] = []
		want.append_array(spec["start"])
		want.append_array(spec["locked"])
		learnable.sort()
		want.sort()
		check_eq(learnable, want, "%s: six learnable abilities = 4 + 2" % class_id)
		for i in 3:
			var tree := Db.get_talent_tree(path.capstone_trees[i])
			check(tree != null and tree.class_id == class_id, "%s: tree %s exists" % [class_id, path.capstone_trees[i]])
			if tree == null:
				continue
			var capstone: TalentData = null
			for t in tree.talents:
				if t != null and t.is_capstone():
					capstone = t
			check(capstone != null and capstone.id == spec["capstones"][i], "%s: the tree's capstone is %s" % [class_id, spec["capstones"][i]])
		var alt: Array = spec["alt"]
		check_eq(path.alt_main_hand.id if path.alt_main_hand != null else &"", alt[0], "%s: alternative main hand" % class_id)
		check_eq(path.alt_off_hand.id if path.alt_off_hand != null else &"", alt[1], "%s: alternative off hand" % class_id)
		var cls := Db.get_class_data(class_id)
		check(cls.can_use(path.alt_main_hand), "%s: the alternative weapon is in its proficiencies" % class_id)
		if path.alt_off_hand != null:
			check(cls.can_use(path.alt_off_hand), "%s: and so is its off hand" % class_id)
		check(path.alt_main_hand.id != cls.main_hand.id, "%s: a different weapon" % class_id)
		check_eq(path.cosmetics.size(), 3, "%s: tabard, hat and glow" % class_id)
		for slot in [&"tabard", &"hat", &"glow"]:
			check_eq(str(path.cosmetic(slot).get("id", "")), "cos_%s_%s" % [class_id, slot], "%s: cosmetic id of the %s" % [class_id, slot])
			check(str(path.cosmetic(slot).get("name", "")) != "", "%s: the %s has a name" % [class_id, slot])
		check_eq(path.title_id, StringName("title_%s" % class_id), "%s: the title id" % class_id)
		check(path.title_name != "" and path.gift_heirloom != &"", "%s: a title and a gift Heirloom" % class_id)


func test_every_gate_exists_with_its_hint() -> void:
	var count := 0
	for class_id: StringName in PATHS:
		var spec: Dictionary = PATHS[class_id]
		for i in 2:
			var gate := Db.get_unlock_gate(Profile.KIND_ABILITY, spec["locked"][i])
			check(gate != null, "gate of %s" % spec["locked"][i])
			if gate != null:
				count += 1
				check_eq(gate.class_id, class_id, "%s: the gate knows its class" % spec["locked"][i])
				check(("level %d" % ABILITY_LEVELS[i]) in gate.hint, "%s: the hint names the level (%s)" % [spec["locked"][i], gate.hint])
		for i in 3:
			var gate := Db.get_unlock_gate(Profile.KIND_CAPSTONE_TREE, spec["trees"][i])
			check(gate != null, "gate of %s" % spec["trees"][i])
			if gate != null:
				count += 1
				check(("level %d" % CAPSTONE_LEVELS[i]) in gate.hint, "%s: the hint names the level (%s)" % [spec["trees"][i], gate.hint])
		for id in spec["start"]:
			check(Db.get_unlock_gate(Profile.KIND_ABILITY, id) == null, "%s starts unlocked" % id)
	check_eq(count, 35, "14 abilities and 21 capstone trees")
	for class_id in [&"hunter", &"shaman"]:
		var gate := Db.get_unlock_gate(Profile.KIND_CLASS, class_id)
		check(gate != null and gate.hint.length() > 8, "%s: a class gate with a hint" % class_id)
	check(Db.get_unlock_gate(Profile.KIND_CLASS, &"warrior") == null, "the five original classes are open")
	check(Db.get_unlock_gate(Profile.KIND_CLASS, &"mage") == null, "mage too")


func test_every_reward_unlocks_at_its_level() -> void:
	var profile := _use_fresh()
	for class_id: StringName in PATHS:
		var spec: Dictionary = PATHS[class_id]
		for i in 2:
			var id: StringName = spec["locked"][i]
			check_eq(ClassLevels.unlock_level(class_id, Profile.KIND_ABILITY, id), ABILITY_LEVELS[i], "%s: unlocked at level %d" % [id, ABILITY_LEVELS[i]])
		for i in 3:
			var tree: StringName = spec["trees"][i]
			check_eq(ClassLevels.unlock_level(class_id, Profile.KIND_CAPSTONE_TREE, tree), CAPSTONE_LEVELS[i], "%s: at level %d" % [tree, CAPSTONE_LEVELS[i]])
		# Walk the levels: what is locked before a level is open from it on, and nothing opens early.
		var p := Profile.fresh()
		Meta.profile = p
		for level in range(2, 31):
			var before_ab: Array[bool] = []
			var before_tr: Array[bool] = []
			for i in 2:
				before_ab.append(Meta.is_unlocked(Profile.KIND_ABILITY, spec["locked"][i], class_id))
			for i in 3:
				before_tr.append(Meta.is_unlocked(Profile.KIND_CAPSTONE_TREE, spec["trees"][i], class_id))
			ClassLevels.award_xp(p, class_id, ClassLevels.xp_for_level(level) - p.class_xp(class_id))
			check_eq(p.class_level(class_id), level, "%s: level %d reached" % [class_id, level])
			for i in 2:
				check_eq(Meta.is_unlocked(Profile.KIND_ABILITY, spec["locked"][i], class_id), level >= ABILITY_LEVELS[i], "%s: ability %d at level %d" % [class_id, i, level])
			for i in 3:
				check_eq(Meta.is_unlocked(Profile.KIND_CAPSTONE_TREE, spec["trees"][i], class_id), level >= CAPSTONE_LEVELS[i], "%s: capstone %d at level %d" % [class_id, i, level])
		# The collectibles of the path: gift Heirloom (5), tabard (15), hat (25), glow (30), title (30).
		var path := Db.class_path(class_id)
		check(p.has_unlock(Profile.KIND_HEIRLOOM, path.gift_heirloom), "%s: the gift Heirloom" % class_id)
		for slot in [&"tabard", &"hat", &"glow"]:
			check(p.has_unlock(Profile.KIND_COSMETIC, StringName(str(path.cosmetic(slot)["id"]))), "%s: the %s" % [class_id, slot])
		check(p.has_unlock(Profile.KIND_TITLE, path.title_id), "%s: the title" % class_id)
	Meta.profile = profile
	# The collectibles come at their levels and not before.
	var q := Profile.fresh()
	var path := Db.class_path(&"warrior")
	_level_to(q, &"warrior", 4)
	check(not q.has_unlock(Profile.KIND_HEIRLOOM, path.gift_heirloom), "no Heirloom at level 4")
	_level_to(q, &"warrior", 5)
	check(q.has_unlock(Profile.KIND_HEIRLOOM, path.gift_heirloom), "the Heirloom at level 5")
	_level_to(q, &"warrior", 14)
	check(not q.has_unlock(Profile.KIND_COSMETIC, &"cos_warrior_tabard"), "no tabard at level 14")
	_level_to(q, &"warrior", 15)
	check(q.has_unlock(Profile.KIND_COSMETIC, &"cos_warrior_tabard"), "the tabard at level 15")
	check(not q.has_unlock(Profile.KIND_COSMETIC, &"cos_warrior_hat"), "no hat yet")
	_level_to(q, &"warrior", 29)
	check(not q.has_unlock(Profile.KIND_TITLE, &"title_warrior"), "no title at level 29")
	_level_to(q, &"warrior", 30)
	check(q.has_unlock(Profile.KIND_TITLE, &"title_warrior") and q.has_unlock(Profile.KIND_COSMETIC, &"cos_warrior_glow"), "level 30: the title and the glow")
	# Rewards never mix between classes.
	check(not q.has_unlock(Profile.KIND_TITLE, &"title_mage"), "the mage's title is not the warrior's")


func test_a_fresh_profile_holds_the_deck_and_the_capstones_back() -> void:
	var profile := _use_fresh()
	var pool := Db.ability_pool(&"warrior")
	var ids: Array[StringName] = []
	for a in pool:
		ids.append(a.id)
	check(&"heroic_leap" not in ids and &"bladestorm" not in ids, "the warrior's deck lacks the two locked abilities")
	for id in PATHS[&"warrior"]["start"]:
		check(id in ids, "%s is in the starting deck" % id)
	check(&"general_sprint" in ids or &"sprint" in ids or ids.size() >= 4 + 1, "the general abilities stay")
	_level_to(profile, &"warrior", 2)
	ids.clear()
	for a in Db.ability_pool(&"warrior"):
		ids.append(a.id)
	check(&"heroic_leap" in ids and &"bladestorm" not in ids, "level 2: Heroic Leap joins")
	_level_to(profile, &"warrior", 4)
	ids.clear()
	for a in Db.ability_pool(&"warrior"):
		ids.append(a.id)
	check(&"bladestorm" in ids, "level 4: Bladestorm joins")
	# The level-up deck never offers a locked ability (here: a mage at level 1).
	world = EFakes.make_world(tree)
	RunState.start_run(1, 7)
	var mage := Fakes.spawn_player(world, 0, &"mage")
	for i in 30:
		for card in LevelUpDeck.draw(mage, rng):
			check(card.ability == null or card.ability.id not in [&"meteor", &"pyroblast"], "no hand offers a locked mage ability")
	# The dev profile (automated runs): everything is open.
	Meta.configure(&"dev", "", true)
	ids.clear()
	for a in Db.ability_pool(&"mage"):
		ids.append(a.id)
	check(&"meteor" in ids and &"pyroblast" in ids, "dev profile: the full deck")
	# Capstones.
	var fury := Db.get_talent(&"warrior_fury_rampage")
	var state := TalentState.create(&"warrior")
	Meta.profile = Profile.fresh()
	check(state.capstone_locked(fury), "a fresh profile: the Fury capstone is locked")
	check(state.capstone_lock_text(fury).contains("level 8"), "its lock text names the level (%s)" % state.capstone_lock_text(fury))
	check(state.add_block_reason(fury.id).begins_with("Capstone locked"), "and it takes no point")
	_level_to(Meta.profile, &"warrior", 8)
	check(not state.capstone_locked(fury), "level 8 opens the first capstone")
	check(state.capstone_locked(Db.get_talent(&"warrior_protection_unbreakable")), "the second one stays closed")
	_level_to(Meta.profile, &"warrior", 16)
	check(not state.capstone_locked(Db.get_talent(&"warrior_protection_unbreakable")), "level 16 opens the second")
	check(state.capstone_locked(Db.get_talent(&"warrior_arms_mortal_strike")), "the third needs level 24")
	Meta.configure(&"dev", "", true)
	check(not state.capstone_locked(fury), "dev profile: no capstone is locked")


func test_hunter_and_shaman_start_locked() -> void:
	var profile := _use_fresh()
	check(not Meta.is_class_unlocked(&"hunter") and not Meta.is_class_unlocked(&"shaman"), "a fresh profile: both locked")
	check(Meta.is_class_unlocked(&"warrior"), "the warrior is open")
	var open := Meta.unlocked_class_ids()
	check(&"hunter" not in open and &"shaman" not in open and open.size() == Db.class_ids.size() - 2, "the lobby offers five classes")
	check(Meta.unlock_hint(Profile.KIND_CLASS, &"hunter") != Meta.LOCKED_HINT, "the Hunter hint is its own text")
	check(Meta.unlock_hint(Profile.KIND_CLASS, &"shaman") != Meta.LOCKED_HINT, "so is the Shaman's")
	check(Meta.unlock_hint(Profile.KIND_CLASS, &"hunter") != Meta.unlock_hint(Profile.KIND_CLASS, &"shaman"), "and they differ")
	# The achievement package grants them with a class reward.
	check(Meta.unlock(Profile.KIND_CLASS, &"hunter"), "granted")
	check(Meta.is_class_unlocked(&"hunter") and not Meta.is_class_unlocked(&"shaman"), "only the Hunter")
	check(profile.has_unlock(Profile.KIND_CLASS, &"hunter"), "recorded")
	Meta.configure(&"dev", "", true)
	check(Meta.is_class_unlocked(&"shaman"), "dev profile: everything")
	Meta.profile = Profile.max_profile(Db.class_ids)
	check(Meta.is_class_unlocked(&"shaman"), "max profile: everything")


func test_slots_follow_the_class_level() -> void:
	check_eq(ClassLevels.seasoning_slots(1), 0, "level 1: none")
	check_eq(ClassLevels.seasoning_slots(2), 0, "level 2: none")
	check_eq(ClassLevels.seasoning_slots(3), 1, "level 3: the first")
	check_eq(ClassLevels.seasoning_slots(9), 1, "level 9")
	check_eq(ClassLevels.seasoning_slots(10), 2, "level 10: the second")
	check_eq(ClassLevels.seasoning_slots(19), 2, "level 19")
	check_eq(ClassLevels.seasoning_slots(20), 3, "level 20: the third")
	check_eq(ClassLevels.seasoning_slots(30), 3, "never more than three")
	check_eq(ClassLevels.heirloom_slots(4), 0, "no Heirloom slot at level 4")
	check_eq(ClassLevels.heirloom_slots(5), 1, "one at level 5")
	check_eq(ClassLevels.heirloom_slots(30), 1, "and only one")
	check_eq([ClassLevels.seasoning_tier_level(1), ClassLevels.seasoning_tier_level(2), ClassLevels.seasoning_tier_level(3),
			ClassLevels.seasoning_tier_level(4), ClassLevels.seasoning_tier_level(5), ClassLevels.seasoning_tier_level(6)],
			[3, 6, 9, 13, 17, 0] as Array[int], "the Seasoning tiers open at 3 / 6 / 9 / 13 / 17")
	var profile := _use_fresh()
	check_eq(Meta.seasoning_slots(&"warrior"), 0, "Meta: a fresh warrior has no slot")
	check_eq(Meta.heirloom_slots(&"warrior"), 0, "no Heirloom slot")
	_level_to(profile, &"warrior", 12)
	check_eq(Meta.seasoning_slots(&"warrior"), 2, "a level 12 warrior: two slots")
	check_eq(Meta.heirloom_slots(&"warrior"), 1, "and the Heirloom slot")
	check_eq(Meta.seasoning_slots(&"mage"), 0, "another class is its own business")
	check(Meta.seasoning_tier_unlocked(&"warrior", 4) == false and Meta.seasoning_tier_unlocked(&"warrior", 3), "tier 3 yes, tier 4 (level 13) not yet")
	Meta.configure(&"dev", "", true)
	check_eq(Meta.seasoning_slots(&"warrior"), 3, "dev profile: every slot (nothing is selected by default)")
	check_eq(Meta.heirloom_slots(&"warrior"), 1, "dev: the Heirloom slot")


func test_rewards_are_described_for_the_lists() -> void:
	var at2 := ClassLevels.rewards_at(&"warrior", 2)
	check_eq(at2.size(), 1, "level 2 gives one thing")
	check_eq(at2[0]["text"], "Ability: %s" % Db.get_ability(&"heroic_leap").display_name, "the ability's name")
	check_eq(at2[0]["unlock_kind"], Profile.KIND_ABILITY, "it unlocks an ability")
	check_eq(at2[0]["id"], &"heroic_leap", "which one")
	var l3 := ClassLevels.rewards_at(&"warrior", 3)
	check_eq(l3.size(), 2, "level 3: a slot and a tier")
	check_eq(l3[0]["text"], "Seasoning slot 1", "the slot")
	check_eq(ClassLevels.rewards_at(&"warrior", 10)[0]["text"], "Seasoning slot 2", "the second slot")
	check(ClassLevels.rewards_at(&"mage", 12)[0]["text"].begins_with("Alternative weapon: Staff"), "level 12 names the weapon")
	check_eq(ClassLevels.rewards_at(&"warlock", 12)[0]["text"], "Alternative weapon: Wand + Orb", "the Warlock's pair")
	check(ClassLevels.rewards_at(&"warrior", 8)[0]["text"].begins_with("Capstone: "), "a capstone")
	check_eq(ClassLevels.rewards_at(&"warrior", 7)[0]["text"], "+10 starting gold", "starting gold")
	check_eq(ClassLevels.rewards_at(&"mage", 9)[0]["text"], "+1% Intellect", "the primary stat of the class")
	check_eq(ClassLevels.rewards_at(&"warrior", 9)[0]["text"], "+1% Strength", "Strength for the warrior")
	check_eq(ClassLevels.rewards_at(&"warrior", 11)[0]["text"], "+1 free shop reroll per run", "the reroll")
	check_eq(ClassLevels.rewards_at(&"warrior", 14)[0]["text"], "+1 backpack slot", "the backpack slot")
	check(ClassLevels.rewards_at(&"warrior", 5)[1]["text"].begins_with("Heirloom: Grandmother"), "the gift Heirloom")
	var next := ClassLevels.next_rewards(&"warrior", 6, 3)
	check_eq(next.size(), 3, "the next three")
	check_eq(int(next[0]["level"]), 7, "starting at level 7")
	check_eq(ClassLevels.next_rewards(&"warrior", 30, 3).size(), 0, "nothing past the top")
	check_eq(ClassLevels.rewards_up_to(&"warrior", 1).size(), 0, "nothing at level 1")
	check(ClassLevels.rewards_up_to(&"warrior", 30).size() >= 26, "the whole path")


# --- The alternative starting weapon ------------------------------------------------------------

func test_alt_weapon_unlocks_at_level_12() -> void:
	var profile := _use_fresh()
	check_eq(ClassLevels.alt_weapon_level(), 12, "level 12")
	_level_to(profile, &"warrior", 11)
	check(not Meta.alt_weapon_unlocked(&"warrior"), "not at 11")
	_level_to(profile, &"warrior", 12)
	check(Meta.alt_weapon_unlocked(&"warrior"), "at 12")
	check(not Meta.alt_weapon_unlocked(&"mage"), "per class")
	Meta.configure(&"dev", "", true)
	check(Meta.alt_weapon_unlocked(&"mage"), "dev profile: available (nothing selects it)")
	check(not Meta.alt_weapon_unlocked(&"nobody"), "an unknown class has none")


func test_the_alternative_weapon_replaces_the_starting_main_hand() -> void:
	for class_id: StringName in PATHS:
		var cls := Db.get_class_data(class_id)
		var path := Db.class_path(class_id)
		var eq := Equipment.new(cls)
		eq.equip_starting_weapons()
		check_eq(eq.get_item(Items.EquipSlot.MAIN_HAND).source_id, cls.main_hand.id, "%s: the standard main hand" % class_id)
		check_eq(eq.get_item(Items.EquipSlot.OFF_HAND) != null, cls.off_hand != null, "%s: the standard off hand" % class_id)
		var alt := Equipment.new(cls)
		alt.equip_starting_weapons(true)
		check_eq(alt.get_item(Items.EquipSlot.MAIN_HAND).source_id, path.alt_main_hand.id, "%s: the alternative main hand" % class_id)
		var off := alt.get_item(Items.EquipSlot.OFF_HAND)
		check_eq(off.source_id if off != null else &"", path.alt_off_hand.id if path.alt_off_hand != null else &"", "%s: the alternative off hand (a two-hander leaves it empty)" % class_id)
		check(alt.main_weapon() != null, "%s: an attacking weapon" % class_id)
	# A class without a path starts as usual.
	var fake := ClassData.new()
	fake.id = &"nobody"
	fake.main_hand = Db.get_class_data(&"warrior").main_hand
	var eq2 := Equipment.new(fake)
	eq2.equip_starting_weapons(true)
	check_eq(eq2.get_item(Items.EquipSlot.MAIN_HAND).source_id, fake.main_hand.id, "no path: the usual weapon")


func test_the_lobby_lets_a_hero_pick_the_alternative_weapon_once_unlocked() -> void:
	var profile := _use_fresh()
	var lobby := Lobby.create()
	_nodes.append(lobby)
	UiFakes.add_to_root(tree, lobby)
	var input := UiFakes.HumanInput.new("pad:a")
	var slot := PlayerManager.join(input, Db.get_class_data(&"warrior"))
	UiFakes.step(lobby)
	UiFakes.tap(lobby, input, PlayerInput.Pad.LB)
	check(not slot.alt_weapon, "level 1: LB does nothing")
	_level_to(profile, &"warrior", 12)
	UiFakes.step(lobby)
	var card: LobbyCard = lobby.cards[slot.index]
	var tag := card._weapons_box.find_child("WeaponTag", true, false) as Label
	check(tag != null and tag.text == "Standard", "the weapons line offers the switch")
	UiFakes.tap(lobby, input, PlayerInput.Pad.LB)
	check(slot.alt_weapon, "LB picks the alternative weapon")
	var tag2 := card._weapons_box.find_child("WeaponTag", true, false) as Label
	check(tag2 != null and tag2.text == "Alt", "the card says so")
	check(_label_texts(card._weapons_box).has("Two-Hand Sword"), "and names the weapon")
	UiFakes.tap(lobby, input, PlayerInput.Pad.LB)
	check(not slot.alt_weapon, "LB again goes back")
	# The choice is remembered per class and survives a class change.
	slot.alt_weapon = true
	Meta.remember_loadout(slot)
	check(profile.loadout(&"warrior")["alt_weapon"], "remembered for the warrior")
	var other := Fakes.make_slot(1, &"warrior")
	Meta.apply_loadout(other)
	check(other.alt_weapon, "a slot that picks the class gets it back")
	var mage := Fakes.make_slot(2, &"mage")
	Meta.apply_loadout(mage)
	check(not mage.alt_weapon, "another class: standard")
	# A locked weapon is never remembered as chosen.
	profile.set_loadout(&"mage", {"alt_weapon": true})
	check(not Meta.remembered_loadout(&"mage")["alt_weapon"], "a mage below level 12 does not get it back")


func _label_texts(root: Node) -> Array[String]:
	var out: Array[String] = []
	for n in root.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	return out


func test_a_run_starts_with_the_chosen_alternative_weapon() -> void:
	var profile := _use_fresh()
	_make_main()
	var bot := PlayerManager.add_bot(&"warrior", 1)
	bot.alt_weapon = true
	main.start_run()
	check(not bot.alt_weapon, "a level 1 warrior cannot have it: Main takes it away")
	check_eq(main.players[0].main_hand.id, Db.get_class_data(&"warrior").main_hand.id, "standard sword")
	_free_main()
	UiFakes.reset_players()
	_level_to(profile, &"warrior", 12)
	_make_main()
	var bot2 := PlayerManager.add_bot(&"warrior", 1)
	bot2.alt_weapon = true
	main.start_run()
	check(bot2.alt_weapon, "level 12: kept")
	check_eq(main.players[0].main_hand.id, &"two_hand_sword", "the hero holds the Two-Hand Sword")
	check(main.players[0].off_hand == null, "no off hand")
	check(profile.loadout(&"warrior")["alt_weapon"], "the profile remembers the choice")
	# --alt-weapon: the bots of an automated run take it (the dev profile has every level).
	_free_main()
	UiFakes.reset_players()
	Meta.configure(&"dev", "", true)
	var opts := LaunchOptions.parse(["--alt-weapon", "--players=2", "--classes=mage,warlock"])
	check(opts.alt_weapon and opts.unknown.is_empty(), "the flag parses")
	main = Main.create(opts)
	tree.root.add_child(main)
	main._add_bots()
	main.start_run()
	check_eq(main.players[0].main_hand.id, &"staff", "the mage staff")
	check_eq(main.players[1].main_hand.id, &"wand", "the warlock wand")
	check_eq(main.players[1].off_hand.id, &"orb", "and the orb")
	check(not LaunchOptions.parse(["--alt-weapon=0"]).alt_weapon, "=0 is off")


# --- Raw power ----------------------------------------------------------------------------------

func test_raw_power_by_level() -> void:
	var zero := ClassLevels.raw_power(1)
	check_eq(zero["gold"], 0, "nothing at level 1")
	check_eq(zero["rerolls"], 0, "no reroll")
	check_eq(ClassLevels.raw_power(6)["gold"], 0, "level 6: no gold yet")
	check_eq(ClassLevels.raw_power(7)["gold"], 10, "level 7: +10 gold")
	check_eq(ClassLevels.raw_power(18)["gold"], 10, "still 10")
	check_eq(ClassLevels.raw_power(19)["gold"], 20, "level 19: +10 more")
	check_near(ClassLevels.raw_power(8)["primary_pct"], 0.0, 0.001, "no primary stat yet")
	check_near(ClassLevels.raw_power(9)["primary_pct"], 1.0, 0.001, "level 9: +1%")
	check_near(ClassLevels.raw_power(21)["primary_pct"], 2.0, 0.001, "level 21: +2%")
	check_eq(ClassLevels.raw_power(10)["rerolls"], 0, "no reroll at 10")
	check_eq(ClassLevels.raw_power(11)["rerolls"], 1, "level 11: a free reroll")
	check_eq(ClassLevels.raw_power(13)["backpack"], 0, "no backpack slot at 13")
	check_eq(ClassLevels.raw_power(14)["backpack"], 1, "level 14: +1 slot")
	var top := ClassLevels.raw_power(30)
	check(top["gold"] == 20 and top["rerolls"] == 1 and top["backpack"] == 1 and is_equal_approx(top["primary_pct"], 2.0), "the whole sum: +20 gold, +1 reroll, +1 slot, +2%")
	check(top["primary_pct"] <= 10.0, "well inside the GDD's +10% of raw power")


func test_raw_power_applies_only_to_real_profiles() -> void:
	# The dev profile (every automated run): the base game.
	Meta.configure(&"dev", "", true)
	check(not Meta.raw_power_enabled(), "dev: raw power off")
	check_eq(Meta.raw_power(&"warrior")["gold"], 0, "dev: no gold")
	_run_with_bots([&"warrior", &"mage"])
	check_eq(RunState.gold, 0, "dev: no starting gold")
	check_eq(RunState.free_rerolls, 0, "dev: no free reroll")
	for hero in main.players:
		check_eq(hero.equipment.backpack_size, Items.BACKPACK_SIZE, "dev: ten backpack slots")
		check(not hero.stats.has_source(Player.META_SOURCE), "dev: no meta stat source")
	var dev_connections := (main.players[0].wave_began.get_connections() as Array).size()
	_free_main()
	UiFakes.reset_players()
	# A max profile: every hero is level 30.
	Meta.profile = Profile.max_profile(Db.class_ids)
	Meta.persist = false
	Meta.path = ""
	check(Meta.raw_power_enabled(), "max: raw power on")
	check_eq(Meta.raw_power(&"warrior")["gold"], 20, "max: 20 gold per hero")
	_run_with_bots([&"warrior", &"mage", &"paladin"])
	check_eq(RunState.gold, 60, "three heroes: 60 starting gold in the shared wallet")
	check_eq(RunState.gold_earned, 0, "which is not earned gold")
	check_eq(RunState.free_rerolls, 3, "and three free rerolls")
	for hero in main.players:
		check_eq(hero.equipment.backpack_size, Items.BACKPACK_SIZE + 1, "max: eleven backpack slots")
	check_eq((main.players[0].wave_began.get_connections() as Array).size(), dev_connections + 1, "the primary stat share refreshes at every wave start")
	# A hero below the levels gets nothing: a fresh profile.
	_free_main()
	UiFakes.reset_players()
	_use_fresh()
	_run_with_bots([&"warrior"])
	check_eq(RunState.gold, 0, "level 1: no gold")
	check_eq(main.players[0].equipment.backpack_size, Items.BACKPACK_SIZE, "level 1: ten slots")
	# Level 7 gives gold, level 11 the reroll: per class, summed over the party.
	_free_main()
	UiFakes.reset_players()
	var profile := _use_fresh()
	_level_to(profile, &"warrior", 11)
	_level_to(profile, &"mage", 7)
	_run_with_bots([&"warrior", &"mage", &"rogue"])
	check_eq(RunState.gold, 20, "warrior 10 + mage 10 + rogue 0")
	check_eq(RunState.free_rerolls, 1, "only the warrior has a reroll")


func test_the_primary_stat_share_follows_the_gear() -> void:
	var profile := _use_fresh()
	_level_to(profile, &"warrior", 21)
	world = EFakes.make_world(tree)
	RunState.start_run(1, 5)
	var hero := Fakes.spawn_player(world, 0, &"warrior")
	check(hero.stats.has_source(Player.META_SOURCE) == false, "no primary stat, no share yet")
	hero.stats.set_source(&"test_gear", {Stats.STRENGTH: 100.0})
	hero.refresh_meta_power()
	check_near(float(hero.stats.get_source(Player.META_SOURCE).get(Stats.STRENGTH, 0.0)), 2.0, 0.001, "+2% of 100 Strength")
	check_near(hero.stats.get_stat(Stats.STRENGTH), 102.0, 0.001, "added to the stat")
	hero.refresh_meta_power()
	check_near(hero.stats.get_stat(Stats.STRENGTH), 102.0, 0.001, "refreshing does not stack it")
	hero.stats.set_source(&"test_gear", {Stats.STRENGTH: 200.0})
	hero.begin_wave()
	check_near(hero.stats.get_stat(Stats.STRENGTH), 204.0, 0.001, "the wave start re-reads the stat")
	# Level 9: 1%.
	var other := Profile.fresh()
	Meta.profile = other
	_level_to(other, &"mage", 9)
	var mage := Fakes.spawn_player(world, 1, &"mage")
	mage.stats.set_source(&"test_gear", {Stats.INTELLECT: 50.0})
	mage.refresh_meta_power()
	check_near(mage.stats.get_stat(Stats.INTELLECT), 53.5, 0.001, "a level 9 mage: +1% of 53 Intellect (the class's own +3 counts), snapped to 0.1")
	# The dev profile: not a number.
	Meta.configure(&"dev", "", true)
	var dev_hero := Fakes.spawn_player(world, 2, &"warrior")
	dev_hero.stats.set_source(&"test_gear", {Stats.STRENGTH: 100.0})
	dev_hero.refresh_meta_power()
	check_near(dev_hero.stats.get_stat(Stats.STRENGTH), 100.0, 0.001, "dev: nothing added")


func test_a_backpack_with_the_extra_slot_holds_eleven() -> void:
	var cls := Db.get_class_data(&"warrior")
	var eq := Equipment.new(cls)
	eq.equip_starting_weapons()
	var sword := Db.weapons[&"sword"]
	for i in Items.BACKPACK_SIZE:
		check(eq.add_to_backpack(ItemInstance.from_weapon(sword)), "slot %d" % (i + 1))
	check(not eq.has_space(), "ten: full")
	check(not eq.add_to_backpack(ItemInstance.from_weapon(sword)), "an eleventh does not fit")
	eq.backpack_size = Items.BACKPACK_SIZE + 1
	check(eq.has_space(), "with the Class Level slot there is room")
	check(eq.add_to_backpack(ItemInstance.from_weapon(sword)), "the eleventh")
	check(not eq.has_space(), "now full")


func test_the_player_panel_shows_the_extra_backpack_cell() -> void:
	check_eq(PlayerPanel.bag_cell_count(), Items.BACKPACK_SIZE + 1, "one hidden cell is built for the Class Level slot")
	var profile := _use_fresh()
	_level_to(profile, &"warrior", 14)
	world = EFakes.make_world(tree)
	RunState.start_run(1, 5)
	var hero := Fakes.spawn_player(world, 0, &"warrior")
	check_eq(hero.equipment.backpack_size, Items.BACKPACK_SIZE + 1, "a level 14 hero has eleven slots")
	var panel := PlayerPanel.create(hero.slot)
	_nodes.append(panel)
	UiFakes.add_to_root(tree, panel)
	panel.refresh()
	var shown := 0
	for cell in panel._cells:
		if cell.bag_index >= 0 and cell.icon.visible:
			shown += 1
	check_eq(shown, Items.BACKPACK_SIZE + 1, "the panel shows eleven cells")
	check(panel._bag_count.text.ends_with("/ 11"), "the counter says / 11 (%s)" % panel._bag_count.text)
	var dev_hero := Fakes.spawn_player(world, 1, &"mage")
	dev_hero.equipment.backpack_size = Items.BACKPACK_SIZE
	var panel2 := PlayerPanel.create(dev_hero.slot)
	_nodes.append(panel2)
	UiFakes.add_to_root(tree, panel2)
	panel2.refresh()
	shown = 0
	for cell in panel2._cells:
		if cell.bag_index >= 0 and cell.icon.visible:
			shown += 1
	check_eq(shown, Items.BACKPACK_SIZE, "a hero without the slot sees ten")


func test_free_rerolls_come_before_gold() -> void:
	RunState.start_run(2, 11)
	var shop := Shop.new()
	var slots: Array[PlayerSlot] = [Fakes.make_slot(0, &"warrior")]
	shop.open_round(3, slots, rng)
	var voters: Array[int] = [0]
	check_eq(shop.reroll_cost(), 3 * 2 + 2, "the usual price")
	check(not shop.next_reroll_free(), "no free reroll without the perk")
	RunState.free_rerolls = 1
	RunState.gold = 0
	check_eq(shop.reroll_cost(), 0, "a free reroll costs nothing")
	check(shop.next_reroll_free(), "next one is free")
	check(shop.vote_reroll(0, voters, rng), "it rerolls with an empty wallet")
	check_eq(RunState.free_rerolls, 0, "and uses the free one up")
	check_eq(RunState.gold_spent, 0, "no gold left the wallet")
	check_eq(shop.rerolls_this_round, 1, "it counts as a reroll")
	check_eq(shop.reroll_cost(), 3 * 2 + 2, "the next one costs the usual price (a free one does not raise it)")
	RunState.gold = 100
	check(shop.vote_reroll(0, voters, rng), "a paid reroll")
	check_eq(RunState.gold, 100 - 8, "pays the usual price")
	check_eq(shop.reroll_cost(), 3 * 2 + 2 + 2, "and raises it by 2")
	shop.open_round(4, slots, rng)
	check_eq(shop.free_rerolls_this_round, 0, "a new round starts clean")


# --- The lobby card and the end screen ----------------------------------------------------------

func test_the_lobby_card_shows_level_badge_and_xp_bar_for_real_profiles() -> void:
	var profile := _use_fresh()
	_level_to(profile, &"warrior", 12)
	ClassLevels.award_xp(profile, &"warrior", 300)
	var lobby := Lobby.create()
	_nodes.append(lobby)
	UiFakes.add_to_root(tree, lobby)
	var input := UiFakes.HumanInput.new("pad:a")
	var slot := PlayerManager.join(input, Db.get_class_data(&"warrior"))
	UiFakes.step(lobby)
	var card: LobbyCard = lobby.cards[slot.index]
	check(card.level_badge.visible, "the badge shows")
	check_eq(card.level_badge_label.text, "Lv 12", "Lv 12")
	check(card.xp_bar.visible, "the XP bar shows")
	var info := Meta.class_progress(&"warrior")
	check_eq(info["level"], 12, "level 12")
	check_eq(info["into"], 300, "300 XP into it")
	check_near(card.xp_bar.value, float(info["fraction"]), 0.001, "the bar follows the progress")
	check(card.xp_label.text.contains("300") and card.xp_label.text.contains("665"), "its numbers name the XP (%s)" % card.xp_label.text)
	# Another class shows its own level.
	slot.class_data = Db.get_class_data(&"mage")
	UiFakes.step(lobby)
	check_eq(card.level_badge_label.text, "Lv 1", "a class never played: Lv 1")
	# A max profile: MAX LEVEL.
	Meta.profile = Profile.max_profile(Db.class_ids)
	slot.class_data = Db.get_class_data(&"warrior")
	UiFakes.step(lobby)
	check_eq(card.level_badge_label.text, "Lv 30", "Lv 30")
	check_eq(card.xp_label.text, "MAX LEVEL", "no bar to fill at the top")
	# The dev profile of the automated runs shows no levels.
	Meta.configure(&"dev", "", true)
	slot.class_data = Db.get_class_data(&"mage")
	UiFakes.step(lobby)
	check(not card.level_badge.visible and not card.xp_bar.visible, "dev profile: neither")


func test_a_recorded_run_describes_itself_for_the_end_screen() -> void:
	var profile := _use_fresh()
	_level_to(profile, &"mage", 1)
	var r := _report(false, {"waves_cleared": 14, "wave": 15, "party_size": 2, "bosses_killed": 1, "kills": 1500}, ["warrior", "mage"], [100, 30])
	var result := Meta.record_run(r)
	var rows := GameOverScreen.progress_rows(result)
	check_eq(rows.size(), 2, "one row per class")
	check_eq(rows[0]["class_id"], &"warrior", "in party order")
	var team := 0.0
	for w in range(1, 15):
		team += 6.0 + 0.5 * w
	team += 40.0
	check_eq(rows[0]["xp_gained"], roundi(team + 3.0), "the warrior's XP")
	check_eq(rows[0]["level_before"], 1, "from level 1")
	check_eq(rows[0]["level_after"], ClassLevels.level_for_xp(roundi(team + 3.0)), "to the level the XP reaches")
	check(rows[0]["leveled_up"], "a level-up")
	check(rows[0]["rewards"].size() > 0, "with rewards listed")
	check_near(rows[0]["to"], float(ClassLevels.progress(roundi(team + 3.0))["fraction"]), 0.001, "the bar's end")
	check(rows[0]["rewards"][0].begins_with("Ability: "), "the level 2 reward is the first line")
	check(GameOverScreen.seeds_text(result).begins_with("+"), "the Seeds line")
	var line := ClassLevels.summary_text(result)
	check(line.begins_with("warrior +") and line.contains("mage +") and line.contains("->") and line.ends_with("Seeds"), "the log line (%s)" % line)
	check_eq(ClassLevels.summary_text({}), "", "no line without Class XP")
	check_eq(GameOverScreen.seeds_text({}), "", "no Seeds line without a record")
	check(GameOverScreen.progress_rows({}).is_empty(), "no rows without a record")
	check(GameOverScreen.progress_rows({"class_xp": "junk"}).is_empty(), "junk is ignored")
	# A listener result of a class that stays on its level: no level-up.
	var again := Meta.record_run(_report(false, {"waves_cleared": 1, "wave": 2, "party_size": 1}, ["warrior"]))
	var rows2 := GameOverScreen.progress_rows(again)
	check(not rows2[0]["leveled_up"] or rows2[0]["level_after"] > rows2[0]["level_before"], "consistent")


func test_the_end_screen_panel() -> void:
	var profile := _use_fresh()
	world = EFakes.make_world(tree)
	RunState.start_run(2, 3)
	var input := UiFakes.HumanInput.new("pad:a")
	PlayerManager.join(input, Db.get_class_data(&"warrior"))
	PlayerManager.join(UiFakes.HumanInput.new("pad:b"), Db.get_class_data(&"warrior"))
	var screen := GameOverScreen.create()
	_nodes.append(screen)
	UiFakes.add_to_root(tree, screen)
	screen.open(false, {}, {})
	check(not screen.has_progress(), "nothing recorded: no Progress page")
	check_eq(screen.tab_labels.size(), 3, "the three usual tabs")
	screen.set_page(GameOverScreen.Page.PROGRESS)
	check_eq(screen.page, GameOverScreen.Page.SUMMARY, "the page is not there: the Summary stays")
	var r := _report(true, {"waves_cleared": 25, "wave": 25, "party_size": 2, "bosses_killed": 2, "kills": 3000}, ["warrior", "warrior"], [400, 300])
	var result := Meta.record_run(r)
	screen.open(true, {}, result)
	check(screen.has_progress(), "a recorded run: the Progress page")
	check_eq(screen.tab_labels.size(), 4, "with its tab")
	check_eq(screen.tab_labels[3].text, "Progress", "named Progress")
	check(screen.summary_page.visible and not screen.progress_page.visible, "the Summary is still the first page")
	screen.set_page(GameOverScreen.Page.LEADERBOARD)
	screen.switch_page(1)
	check_eq(screen.page, GameOverScreen.Page.PROGRESS, "one page past the Leaderboard")
	check(screen.progress_page.visible and not screen.leaderboard_page.visible and not screen.summary_page.visible, "only that page shows")
	screen.switch_page(1)
	check_eq(screen.page, GameOverScreen.Page.PROGRESS, "the ends do not wrap")
	check_eq(GameOverScreen.page_from_name("progress"), GameOverScreen.Page.PROGRESS, "--end-page=progress")
	check(LaunchOptions.parse(["--end-page=progress"]).unknown.is_empty(), "and the launch option accepts it")
	check_eq(screen.progress_box.get_child_count(), 1, "two warriors are one row")
	var joined := "|".join(_label_texts(screen.progress_box))
	check(joined.contains("Warrior ×2"), "the row says two heroes (%s)" % joined)
	check(joined.contains("XP"), "and the XP gained")
	check(joined.contains("→"), "and the level-ups")
	check(joined.contains("New:"), "and what the levels gave")
	check(screen.progress_seeds_label.text.begins_with("+") and screen.progress_seeds_label.text.ends_with("Seeds"), "the Seeds of the run")
	check(screen.progress_box.find_child("XpBar", true, false) != null, "with an XP bar")
	# The same screen, next run, not recorded (the dev profile): the page and its tab are gone.
	Meta.configure(&"dev", "", true)
	var dev_result := Meta.record_run(_report(true, {"waves_cleared": 25}, ["warrior"]))
	check(not dev_result["recorded"], "the dev profile records nothing")
	screen.open(true, {}, dev_result)
	check(not screen.has_progress(), "dev profile: no Progress page")
	check_eq(screen.tab_labels.size(), 3, "its tab is gone again")
	screen.set_page(GameOverScreen.Page.LEADERBOARD)
	screen.switch_page(1)
	check_eq(screen.page, GameOverScreen.Page.LEADERBOARD, "the Leaderboard is the last page")
	check(profile.class_xp(&"warrior") > 0, "(the real profile did earn)")


func test_main_hands_the_result_to_the_end_screen() -> void:
	_use_file()
	_run_with_bots([&"warrior", &"mage"])
	main.waves_completed = 5
	main.end_run(false)
	check(main.meta_result.has("class_xp"), "Main kept the XP result")
	check(main.game_over.has_progress(), "and the end screen has its Progress page")
	check_eq(main.game_over.progress_box.get_child_count(), 2, "one row per class")
	_free_main()
	UiFakes.reset_players()
	Meta.configure(&"dev", "", true)
	_run_with_bots([&"warrior", &"mage"])
	main.end_run(false)
	check(not main.game_over.has_progress(), "dev profile: no Progress page")


# --- The profile --------------------------------------------------------------------------------

func test_the_listeners_run_between_the_counters_and_the_achievements() -> void:
	var ids := Meta.listener_ids()
	var xp := ids.find(ClassLevels.LISTENER_XP)
	var seeds := ids.find(ClassLevels.LISTENER_SEEDS)
	check(xp >= 0 and seeds >= 0, "both are registered")
	check(ids.find(Meta.LISTENER_COUNTERS) < xp, "the counters ran first")
	check(xp < seeds, "XP before Seeds (the Seeds line includes the level gifts)")
	check(seeds < ids.find(Meta.LISTENER_ACHIEVEMENTS), "the achievements see the new levels")


func test_the_dev_profile_earns_nothing() -> void:
	Meta.configure(&"dev", "", true)
	var result := Meta.record_run(_report(true, {"waves_cleared": 25, "bosses_killed": 2}, ["warrior"]))
	check(not result["recorded"], "nothing is recorded")
	check_eq(Meta.profile.class_xp(&"warrior"), 0, "no XP")
	check_eq(Meta.seeds(), 0, "no Seeds")
	check_eq(Meta.class_level(&"warrior"), 1, "level 1 (no levels in an automated run)")


func test_a_level_up_happens_inside_the_run_end_save() -> void:
	var profile := _use_file()
	var r := _report(true, {"waves_cleared": 25, "wave": 25, "party_size": 1, "bosses_killed": 2, "kills": 5000, "elites_killed": 30}, ["warrior"], [800])
	var result := Meta.record_run(r)
	check_eq(Meta.save_count, 1, "one save for the whole run")
	var entry: Dictionary = (result["class_xp"] as Array)[0]
	check_eq(entry["level_before"], 1, "from level 1")
	check(int(entry["level_after"]) >= 5, "a win is worth several levels (%d)" % int(entry["level_after"]))
	check_eq(profile.class_level(&"warrior"), entry["level_after"], "stored")
	check(Meta.is_unlocked(Profile.KIND_ABILITY, &"heroic_leap", &"warrior"), "the level 2 and 4 abilities are open")
	check(Meta.is_unlocked(Profile.KIND_ABILITY, &"bladestorm", &"warrior"), "both")
	check(not Meta.is_unlocked(Profile.KIND_CAPSTONE_TREE, &"warrior_fury", &"warrior"), "the first capstone needs level 8")


func test_the_profile_round_trips_levels_unlocks_and_the_weapon_choice() -> void:
	var profile := _use_file()
	_level_to(profile, &"warrior", 16)
	_level_to(profile, &"mage", 5)
	profile.set_loadout(&"warrior", {"alt_weapon": true})
	profile.set_loadout(&"mage", {"alt_weapon": false, "seasonings": [&"ssn_x"]})
	check_eq(Meta.save(), OK, "saved")
	var back := Profile.load_file(_tmp_path)
	check_eq(back.class_xp(&"warrior"), profile.class_xp(&"warrior"), "warrior XP")
	check_eq(back.class_level(&"warrior"), 16, "warrior level")
	check_eq(back.class_level(&"mage"), 5, "mage level")
	check(back.has_unlock(Profile.KIND_ABILITY, &"bladestorm"), "the ability unlock")
	check(back.has_unlock(Profile.KIND_CAPSTONE_TREE, &"warrior_protection"), "the second capstone")
	check(not back.has_unlock(Profile.KIND_CAPSTONE_TREE, &"warrior_arms"), "and not the third")
	check(back.has_unlock(Profile.KIND_COSMETIC, &"cos_warrior_tabard"), "the tabard")
	check(back.has_unlock(Profile.KIND_HEIRLOOM, &"heir_apron"), "the gift Heirloom")
	check(back.loadout(&"warrior")["alt_weapon"], "the weapon choice")
	check(not back.loadout(&"mage")["alt_weapon"], "per class")
	check_eq(back.loadout(&"mage")["seasonings"], [&"ssn_x"] as Array[StringName], "the rest of the loadout is untouched")
	check_eq(back.to_dict(), profile.to_dict(), "the same data")
	# A file written before the weapon choice existed has no key: standard weapon.
	var data := profile.to_dict()
	((data["loadouts"] as Dictionary)["warrior"] as Dictionary).erase("alt_weapon")
	check(not Profile.from_dict(data).loadout(&"warrior")["alt_weapon"], "a missing key is standard")


func test_loading_a_profile_regrants_the_unlocks_of_its_levels() -> void:
	var profile := Profile.fresh()
	profile.set_class_progress(&"warrior", ClassLevels.xp_for_level(9), 9)
	var file := FileAccess.open(_tmp_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(profile.to_dict()))
	file.close()
	check(not profile.has_unlock(Profile.KIND_ABILITY, &"heroic_leap"), "(the file has the level but no unlock)")
	Meta.configure(&"", _tmp_path, true)
	check(Meta.is_unlocked(Profile.KIND_ABILITY, &"heroic_leap", &"warrior"), "loading it grants the level 2 ability")
	check(Meta.is_unlocked(Profile.KIND_ABILITY, &"bladestorm", &"warrior"), "and level 4")
	check(Meta.is_unlocked(Profile.KIND_CAPSTONE_TREE, &"warrior_fury", &"warrior"), "and the capstone of level 8")
	check(not Meta.is_unlocked(Profile.KIND_CAPSTONE_TREE, &"warrior_protection", &"warrior"), "but not the one of level 16")
	check_eq(ClassLevels.sync_unlocks(Meta.profile), 0, "a second sync has nothing to add")
	# The max profile: levels 30, the collectibles recorded too.
	Meta.configure(&"max", "", true)
	check(Meta.profile.has_unlock(Profile.KIND_COSMETIC, &"cos_shaman_glow"), "max: every class's glow")
	check(Meta.profile.unlocked_ids(Profile.KIND_TITLE).size() == Db.class_ids.size(), "max: every title")
