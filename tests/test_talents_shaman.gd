extends "res://tests/shaman_base.gd"
## Shaman talents, the data half (M8 TALENTS-S, design_shaman.md 4): the three trees in Db (Stormweaving,
## Warspirit, Wellspring: shape, names, prerequisites, bare ability ids, own pictures, no PENDING line left), the bot
## path of every tree (the capstone is reachable) and every talent that is pure data - stats, damage, resource,
## ability-mod, proc and the dual-wield grant - taken rank by rank on a real Shaman: the numbers the engine reads,
## the take-back, and the first real effect where the design makes one. The four talent scripts (Elemental Surge,
## Gale Strike, Elder Spirits / Gift of the Elders, Bond Totem): test_talents_shaman_scripts.gd; the Talents tab:
## test_talents_shaman_ui.gd.
##
## Gates (TalentState): tier 2 needs 3 points in tier 1, tier 3 needs 6, tier 4 needs 9, the capstone 12 (in the
## tree's lower tiers), and a prerequisite talent has to be at its max rank - every test takes the points it needs.

const DataTest := preload("res://tests/test_talent_data.gd")
const Rules := preload("res://tests/content_rules.gd")

const STORM := "stormweaving"
const WAR := "warspirit"
const WELL := "wellspring"
const TREE_IDS: Array[StringName] = [&"shaman_stormweaving", &"shaman_warspirit", &"shaman_wellspring"]
## The talents of each tree in layout order (tier, column).
const NAMES := {
	"stormweaving": ["Livewire", "Kindled Spark", "Charged Mind", "Stormcharged", "Static Veins", "Rebounding Arc",
		"Resounding Echo", "Quickening Storm", "Elemental Surge"],
	"warspirit": ["Twinned Spirits", "Hardened Knuckles", "Mirrored Strikes", "Spirit Pulse", "Flame Tempering",
		"Molten Trail", "Crackling Blows", "Howling Chorus", "Gale Strike"],
	"wellspring": ["Gentle Current", "Weathered Wood", "Elder Spirits", "Deepening Rain", "Attuned Totems",
		"Ancestral Reach", "Gift of the Elders", "Blessed Rite", "Bond Totem"],
}
## Old / prefixed spellings of the Shaman's ability ids that no entry may use (the ids are bare).
const PREFIXED := ["shaman_forking_bolt", "shaman_totem_rite", "shaman_thunderbolt", "shaman_magma_lash",
	"shaman_soothing_downpour", "shaman_spirit_pack", "shaman_rumbling_earth", "shaman_stormburst"]


func before_each() -> void:
	super()
	RunState.set_start_level(31)


# --- Helpers -----------------------------------------------------------------------------------

func _tid(tree_name: String, name: String) -> StringName:
	return StringName("shaman_%s_%s" % [tree_name, name])


func _add(p: Player, tree_name: String, name: String, n: int = 1) -> void:
	var id := _tid(tree_name, name)
	for i in n:
		check(p.talents.add(id), "add %s: %s" % [id, p.talents.add_block_reason(id)])


func _remove(p: Player, tree_name: String, name: String, n: int = 1) -> void:
	var id := _tid(tree_name, name)
	for i in n:
		check(p.talents.remove(id), "remove %s: %s" % [id, p.talents.remove_block_reason(id)])


## The ids [method TalentBot.next_talent] picks, point by point, until it finds nothing.
func _bot_path(p: Player, slot_index: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in 100:
		var t := TalentBot.next_talent(p, slot_index)
		if t == null or not p.talents.add(t.id):
			break
		out.append(t.id)
	return out


func _params(p: Player, id: StringName) -> Dictionary:
	return p.abilities.params_for(Db.get_ability(id))


func _dagger() -> ItemInstance:
	return ItemInstance.from_weapon(Db.get_weapon(&"dagger"))


func _areas() -> int:
	var n := 0
	for child in world.get_children():
		if child is AbilityArea and not child.is_queued_for_deletion():
			n += 1
	return n


# --- The trees ---------------------------------------------------------------------------------

func test_the_three_shaman_trees_are_in_db_in_tab_order() -> void:
	var trees := Db.talent_trees_for(&"shaman")
	check_eq(trees.size(), 3, "three trees")
	if trees.size() != 3:
		return
	var ids: Array[StringName] = []
	for t in trees:
		ids.append(t.id)
		check_eq(DataTest.tree_problems(t), [] as Array[String], "%s passes the content contract" % t.id)
		check_eq(t.talents.size(), 9, "%s: nine talents" % t.id)
		var points := 0
		for talent in t.talents:
			points += talent.max_rank
		check_eq(points, 22, "%s: 22 points" % t.id)
		check_eq(t.class_id, &"shaman", "class id")
	check_eq(ids, TREE_IDS, "tab order")
	check_eq([trees[0].display_name, trees[1].display_name, trees[2].display_name], ["Stormweaving", "Warspirit", "Wellspring"], "names")
	check_eq([trees[0].icon, trees[1].icon, trees[2].icon], [&"thunderbolt", &"magma_lash", &"soothing_downpour"],
		"bare ability ids as tree icons")
	for i in 3:
		check_eq(trees[i].index, i, "tree index")
	var p := _shaman()
	check_eq(p.talents.trees().size(), 3, "a Shaman's TalentState holds them")
	check(not Rules.pending(&"shaman", "trees"), "no PENDING line for the Shaman trees is left")
	check_eq(Rules.count_of(&"shaman", "trees"), Rules.TREES_PER_CLASS, "the completeness rule sees three trees")


func test_every_talent_is_named_and_laid_out_as_designed() -> void:
	for tree_name: String in NAMES:
		var tree_data := Db.get_talent_tree(StringName("shaman_" + tree_name))
		if tree_data == null:
			check(false, "tree %s" % tree_name)
			continue
		var shown: Array[String] = []
		for t in tree_data.talents:
			shown.append(t.display_name)
			check(String(t.id).begins_with("shaman_%s_" % tree_name), "%s: prefixed id" % t.id)
			check_eq(Db.get_talent(t.id), t, "%s: registered" % t.id)
		check_eq(shown, NAMES[tree_name], "%s: the nine talents in layout order" % tree_name)
	# The prerequisite arrows: two per tree.
	var arrows := {
		_tid(STORM, "charged_mind"): _tid(STORM, "livewire"), _tid(STORM, "resounding_echo"): _tid(STORM, "charged_mind"),
		_tid(WAR, "mirrored_strikes"): _tid(WAR, "twinned_spirits"), _tid(WAR, "crackling_blows"): _tid(WAR, "mirrored_strikes"),
		_tid(WELL, "deepening_rain"): _tid(WELL, "gentle_current"), _tid(WELL, "gift_of_the_elders"): _tid(WELL, "elder_spirits"),
	}
	var with_prerequisite := 0
	for tree_id in TREE_IDS:
		for t in Db.get_talent_tree(tree_id).talents:
			if t.prerequisite != &"":
				with_prerequisite += 1
				check_eq(t.prerequisite, arrows.get(t.id, &"?"), "%s: its prerequisite" % t.id)
	check_eq(with_prerequisite, 6, "six arrows")
	check_eq(Db.get_talent(_tid(STORM, "rebounding_arc")).ability, &"forking_bolt", "Rebounding Arc changes Forking Bolt")
	check_eq(Db.get_talent(_tid(WAR, "molten_trail")).ability, &"magma_lash", "Molten Trail changes Magma Lash")
	check_eq(Db.get_talent(_tid(WELL, "ancestral_reach")).ability, &"totem_rite", "Ancestral Reach changes Totem Rite")
	for tree_id in TREE_IDS:
		var caps := Db.get_talent_tree(tree_id).talents_in_tier(5)
		check(caps.size() == 1 and caps[0].is_capstone(), "%s has one capstone" % tree_id)
	check_eq(Db.get_talent(_tid(STORM, "charged_mind")).text_for_rank(3),
		"Increases your Mastery by 9: Storm Echo triggers 13.5% more often.", "rank text with a decimal")
	check_eq(Db.get_talent(_tid(WAR, "twinned_spirits")).text_for_rank(2),
		"You can wield a one-handed weapon in each hand (Dual Wield). While dual wielding, your Haste is increased by 6%.", "dual wield text")
	check_eq(Db.get_talent(_tid(WELL, "bond_totem")).text_for_rank(1),
		"Every 25 sec a Bond Totem rises at your feet for 10 sec: heroes within 6 m even out their health (10% of the gap per second) and take 20% less damage.",
		"capstone text")


func test_the_entries_use_bare_ability_ids_and_implemented_params() -> void:
	var ability_entries := 0
	var scripts: Array[String] = []
	for tree_id in TREE_IDS:
		for t in Db.get_talent_tree(tree_id).talents:
			for e in t.effects:
				check_eq(BonusVocabulary.validate(e, &"shaman"), "", "%s: a valid entry" % t.id)
				var text := JSON.stringify(e)
				for old: String in PREFIXED:
					check(old not in text, "%s: no prefixed ability id '%s' in %s" % [t.id, old, text])
				match str(e.get("kind")):
					"script":
						scripts.append(String(e["script"]).get_file())
					"ability":
						ability_entries += 1
						var id := StringName(str(e["match"]["id"]))
						var ability := Db.get_ability(id)
						check(ability != null or BonusVocabulary.PSEUDO_IDS.has(id), "%s: %s is an ability or a pseudo id" % [t.id, id])
						if ability == null:
							continue
						for key: String in e["mods"]:
							if key.ends_with("_add"):
								check(ability.params.has(key.trim_suffix("_add")), "%s: %s changes a param of %s" % [t.id, key, id])
	check_eq(ability_entries, 9, "nine ability entries")
	scripts.sort()
	check_eq(scripts, ["stormweaving_elemental_surge.gd", "warspirit_gale_strike.gd", "wellspring_bond_totem.gd",
		"wellspring_elder_spirits.gd", "wellspring_elder_spirits.gd"], "four scripts: Elder Spirits and its Gift share one")
	# Twinned Spirits is data: the generic proficiency grant plus the Haste that needs a second weapon.
	var twinned := Db.get_talent(_tid(WAR, "twinned_spirits"))
	check_eq(twinned.effects.size(), 2, "two entries")
	check(twinned.effects[0] == {"kind": "proficiency", "grant": "dual_wield"}, "the grant: %s" % twinned.effects[0])
	check_eq(twinned.effects[1].get("requires"), {"weapon": "dual_wield"}, "the Haste needs dual wield")


func test_every_shaman_talent_has_its_own_picture_used_by_nothing_else() -> void:
	var map := GameIcons.icon_map()
	var users: Dictionary[String, Array] = {}
	for dict: Dictionary in [map.abilities, map.talents, map.trees, map.consumables, map.shrines, map.stats, map.schools]:
		for key: StringName in dict:
			var path := String(dict[key])
			var list: Array = users.get(path, [])
			list.append(key)
			users[path] = list
	var checked := 0
	for tree_id in TREE_IDS:
		var tree_path := String(map.trees.get(tree_id, ""))
		check(tree_path != "" and ResourceLoader.exists(tree_path), "%s has a picture" % tree_id)
		check_eq((users.get(tree_path, []) as Array).size(), 1, "%s: the tree picture is used once" % tree_id)
		check(GameIcons.for_tree(Db.get_talent_tree(tree_id)) != null, "%s draws its emblem" % tree_id)
		_picture_file(tree_path)
		for t in Db.get_talent_tree(tree_id).talents:
			var path := String(map.talents.get(t.id, ""))
			check(path != "" and ResourceLoader.exists(path), "%s has a picture file" % t.id)
			check_eq((users.get(path, []) as Array).size(), 1, "%s: its picture is used by nothing else (%s)" % [t.id, users.get(path, [])])
			check(GameIcons.for_talent(t) != null, "%s draws it" % t.id)
			_picture_file(path)
			checked += 1
	check_eq(checked, 27, "27 talents")


## [param path] is a stripped game-icons.net silhouette imported at 128 px.
func _picture_file(path: String) -> void:
	var svg := FileAccess.get_file_as_string(path)
	check("<svg" in svg and "M0 0h512v512H0z" not in svg and 'fill="#fff"' in svg, "%s: a stripped white game-icons svg" % path)
	check("svg/scale=0.25" in FileAccess.get_file_as_string(path + ".import"), "%s: imported at 128 px" % path)


# --- The bot path --------------------------------------------------------------------------------

func test_the_bot_path_reaches_every_capstone_at_point_13() -> void:
	var capstones := ["elemental_surge", "gale_strike", "bond_totem"]
	# Points a bot puts into its own tree before it spills over: everything that is not deferred (Warspirit: Mirrored
	# Strikes needs a second weapon, Molten Trail an unlearned Magma Lash, Crackling Blows is behind Mirrored Strikes).
	var own := [22, 15, 22]
	for slot_index in 3:
		var p := _shaman(Vector3(slot_index * 4.0, 0, 0), slot_index)
		var path := _bot_path(p, slot_index)
		var tree_id := TREE_IDS[slot_index]
		var cap := StringName("%s_%s" % [tree_id, capstones[slot_index]])
		check_eq(path.find(cap), 12, "slot %d: the capstone is point 13" % slot_index)
		check_eq(p.talents.rank_of(cap), 1, "slot %d: the capstone is taken" % slot_index)
		check_eq(p.talents.tree_points(tree_id), own[slot_index], "slot %d: %d points in %s" % [slot_index, own[slot_index], tree_id])
		for i in own[slot_index]:
			check(String(path[i]).begins_with(String(tree_id) + "_"), "slot %d: point %d stays in its tree: %s" % [slot_index, i + 1, path[i]])
		check_eq(path.size(), 22, "slot %d: all 22 points are spent" % slot_index)
	var wrap := _shaman(Vector3(20, 0, 0), 3)
	check_eq(_bot_path(wrap, 3).front(), _tid(STORM, "livewire"), "a fourth bot wraps round to the first tree")
	# Warspirit: the talents that need a second weapon (or an unlearned ability) wait until nothing else is addable.
	var w := _shaman(Vector3(24, 0, 0), 1)
	var war := _bot_path(w, 1)
	for late in ["mirrored_strikes", "crackling_blows", "molten_trail"]:
		check(war.find(_tid(WAR, late)) < 0 or war.find(_tid(WAR, late)) >= 15, "%s is not among the first 15 points" % late)
	check(war.find(_tid(WAR, "twinned_spirits")) < 3, "Twinned Spirits is not deferred: it grants dual wield itself")
	check(TalentBot.is_deferred(w, Db.get_talent(_tid(WAR, "mirrored_strikes"))), "Mirrored Strikes is deferred without a second weapon")
	check(not TalentBot.is_deferred(w, Db.get_talent(_tid(WAR, "twinned_spirits"))), "the grant is never deferred")
	check(not TalentBot.is_deferred(w, Db.get_talent(_tid(WAR, "gale_strike"))), "nor the capstone")


# --- Stormweaving ----------------------------------------------------------------------------------

func test_livewire_and_kindled_spark_raise_their_schools_only() -> void:
	var p := _shaman()
	p.stats.set_source(&"test", {Stats.INTELLECT: 10.0, Stats.SPELL_POWER: 4.0})
	var e := _enemy(Vector3(3, 0, 0))
	_learn(p, &"thunderbolt")
	check(_cast(p, &"thunderbolt"), "Thunderbolt")
	var plain := e.fake_damage_log[e.fake_damage_log.size() - 1]
	for n in range(1, 4):
		_add(p, STORM, "livewire")
		check_near(p.bonuses.damage_mult(null, &"nature", &"ability"), 1.0 + 0.03 * n, 0.0001, "+3% Nature per rank")
	check_eq(p.bonuses.damage_mult(null, &"fire", &"ability"), 1.0, "not Fire")
	check_eq(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.0, "not physical")
	p.abilities.set_cooldown(Db.get_ability(&"thunderbolt"), 0.0)
	check(_cast(p, &"thunderbolt"), "Thunderbolt again")
	check_near(e.fake_damage_log[e.fake_damage_log.size() - 1], plain * 1.09, 0.001, "the real bolt deals 9% more")
	for n in range(1, 4):
		_add(p, STORM, "kindled_spark")
		check_near(p.bonuses.damage_mult(null, &"fire", &"ability"), 1.0 + 0.03 * n, 0.0001, "+3% Fire per rank")
	check_near(p.bonuses.damage_mult(null, &"nature", &"ability"), 1.09, 0.0001, "Nature is not changed by it")
	_remove(p, STORM, "kindled_spark", 3)
	_remove(p, STORM, "livewire", 3)
	check_eq(p.bonuses.damage_mult(null, &"nature", &"ability"), 1.0, "undone")
	check_eq(p.bonuses.damage_mult(null, &"fire", &"ability"), 1.0, "undone")


func test_charged_mind_and_resounding_echo_feed_storm_echo() -> void:
	var p := _shaman()
	var m := _mastery(p)
	check_eq(p.stats.get_raw(Stats.MASTERY), 0.0, "no Mastery to start with")
	check_eq(m.echo_chance(), 0.0, "no echo")
	_add(p, STORM, "livewire", 3)
	for n in range(1, 4):
		_add(p, STORM, "charged_mind")
		check_eq(p.stats.get_raw(Stats.MASTERY), 3.0 * n, "+3 Mastery per rank")
		check_near(m.echo_chance(), 4.5 * n, 0.0001, "Storm Echo +4.5% per rank")
	check_eq(float(m.echo_params().get("echo_pct", 0.0)), 50.0, "the echo repeats 50% of the hit")
	_add(p, STORM, "kindled_spark", 3)
	for n in range(1, 4):
		_add(p, STORM, "resounding_echo")
		check_near(float(m.echo_params().get("echo_pct", 0.0)), 50.0 + 10.0 * n, 0.0001, "+10% echo per rank (the cache was dropped)")
		check_eq(p.stats.get_raw(Stats.MASTERY), 9.0 + float(n), "+1 Mastery per rank")
	check_near(m.echo_chance(), 12.0 * 1.5, 0.0001, "12 Mastery -> 18%")
	check_near(float(m.echo_params().get("max_chance", 0.0)), 60.0, 0.0001, "the cap is untouched")
	# The echo really repeats 80% of the hit (Mastery for the 60% cap: the roll is one rng draw).
	p.stats.set_source(&"test", {Stats.MASTERY: 100.0})
	check_near(m.echo_chance(), 60.0, 0.0001, "capped at 60%")
	var e := _enemy(Vector3(3, 0, 0))
	var dealt := 0.0
	for i in 60:
		dealt = m.roll_echo(e, 100.0, &"nature")
		if dealt > 0.0:
			break
	check_near(dealt, 80.0 * 1.09, 0.001, "an echo of a 100 hit deals 80 at Resounding Echo 3/3 (x1.09: Livewire 3/3)")
	_remove(p, STORM, "resounding_echo", 3)
	check_near(float(m.echo_params().get("echo_pct", 0.0)), 50.0, 0.0001, "undone")


func test_stormcharged_starts_the_wave_with_surge() -> void:
	var p := _shaman()
	check_eq(_surge(p).value, 0.0, "Surge starts at 0")
	_add(p, STORM, "livewire", 3)
	for n in range(1, 4):
		_add(p, STORM, "stormcharged")
		p.begin_wave()
		check_eq(_surge(p).value, 10.0 * n, "%d Surge at the wave start (rank %d)" % [10 * n, n])
	check_eq(p.talents.rank_of(_tid(STORM, "stormcharged")), 3, "three ranks")


func test_static_veins_gives_spell_power_and_intellect() -> void:
	var p := _shaman()
	var sp := p.stats.get_raw(Stats.SPELL_POWER)
	var intellect := p.stats.get_raw(Stats.INTELLECT)
	_add(p, STORM, "livewire", 3)
	_add(p, STORM, "kindled_spark", 3)
	for n in range(1, 3):
		_add(p, STORM, "static_veins")
		check_eq(p.stats.get_raw(Stats.SPELL_POWER) - sp, 3.0 * n, "+3 Spell Power per rank")
		check_eq(p.stats.get_raw(Stats.INTELLECT) - intellect, 2.0 * n, "+2 Intellect (the primary stat) per rank")
	_remove(p, STORM, "static_veins", 2)
	check_eq(p.stats.get_raw(Stats.SPELL_POWER), sp, "undone")
	check_eq(p.stats.get_raw(Stats.INTELLECT), intellect, "undone")


func test_rebounding_arc_lets_forking_bolt_arc_back() -> void:
	var p := _shaman()
	p.stats.set_source(&"test", {Stats.INTELLECT: 10.0, Stats.SPELL_POWER: 4.0})
	var bolt := &"forking_bolt"
	check_eq(float(_params(p, bolt).get("return_pct", -1.0)), 0.0, "no return arc to start with")
	_add(p, STORM, "livewire", 3)
	_add(p, STORM, "kindled_spark", 3)
	_add(p, STORM, "rebounding_arc")
	check_eq(float(_params(p, bolt).get("return_pct", -1.0)), 60.0, "+60% return arc")
	var a := _enemy(Vector3(3, 0, 0))
	var b := _enemy(Vector3(5, 0, 0))
	_full_surge(p)
	check(_cast(p, bolt), "cast")
	check_eq(a.fake_damage_log.size(), 2, "the first enemy is struck again on the way back")
	check_eq(b.fake_damage_log.size(), 1, "the last one once")
	check_near(a.fake_damage_log[1], a.fake_damage_log[0] * 0.6, 0.001, "the arc deals 60% of the first hit")
	_remove(p, STORM, "rebounding_arc")
	check_eq(float(_params(p, bolt).get("return_pct", -1.0)), 0.0, "undone")


func test_quickening_storm_stacks_haste_with_every_forking_bolt() -> void:
	var p := _shaman()
	p.stats.set_source(&"test", {Stats.INTELLECT: 10.0, Stats.SPELL_POWER: 4.0})
	_enemy(Vector3(3, 0, 0))
	_add(p, STORM, "livewire", 3)
	_add(p, STORM, "kindled_spark", 3)
	_add(p, STORM, "stormcharged", 3)
	_add(p, STORM, "quickening_storm", 3)
	check_eq(p.stats.get_raw(Stats.HASTE), 0.0, "no Haste yet")
	var seen: Array[float] = []
	for i in 4:
		_full_surge(p)
		p.abilities.set_cooldown(Db.get_ability(&"forking_bolt"), 0.0)
		check(_cast(p, &"forking_bolt"), "Forking Bolt %d" % i)
		seen.append(p.stats.get_raw(Stats.HASTE))
	check_eq(seen, [6.0, 12.0, 18.0, 18.0] as Array[float], "2% x rank 3 per cast, three stacks at most")
	p.procs._physics_process(5.1)
	check_eq(p.stats.get_raw(Stats.HASTE), 0.0, "gone after 5 sec")
	var found := false
	for d: Dictionary in p.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS):
		if d.get("trigger") == "on_cast" and d.get("effect") == "buff":
			found = true
			check_eq(d.get("ability"), "forking_bolt", "on the bare id")
	check(found, "an on_cast buff proc")


# --- Warspirit -------------------------------------------------------------------------------------

func test_twinned_spirits_grants_dual_wield_and_taking_it_away_frees_the_off_hand() -> void:
	var p := _shaman()
	check(not p.class_data.can_dual_wield(), "the Shaman has no dual wield of its own")
	check(not p.equipment.can_dual_wield(), "so the equipment refuses")
	var dagger := _dagger()
	check_eq(p.equipment.target_slots(dagger), [Items.EquipSlot.MAIN_HAND] as Array[Items.EquipSlot], "a one-hander goes to the main hand only")
	_add(p, WAR, "twinned_spirits")
	check(p.bonuses.has_proficiency(&"dual_wield"), "the talent grants the proficiency")
	check(p.equipment.can_dual_wield(), "the equipment follows at rank 1")
	check_eq(p.equipment.target_slots(dagger), [Items.EquipSlot.MAIN_HAND, Items.EquipSlot.OFF_HAND] as Array[Items.EquipSlot], "either hand")
	check_eq(p.stats.get_raw(Stats.HASTE), 0.0, "no Haste while the off hand holds a shield")
	check(p.equipment.add_to_backpack(dagger), "in the bag")
	check(p.equipment.equip(dagger, Items.EquipSlot.OFF_HAND), "the dagger goes into the off hand")
	check(p.off_hand == dagger.weapon and p.weapons.size() == 2, "both hands attack")
	check_eq(p.stats.get_raw(Stats.HASTE), 3.0, "+3% Haste while dual wielding")
	# A rank-up keeps the off hand and raises the Haste.
	_add(p, WAR, "twinned_spirits")
	check(p.equipment.get_item(Items.EquipSlot.OFF_HAND) == dagger, "rank 2: the dagger stays")
	check_eq(p.stats.get_raw(Stats.HASTE), 6.0, "+6% Haste at rank 2")
	_add(p, WAR, "twinned_spirits")
	check_eq(p.stats.get_raw(Stats.HASTE), 9.0, "+9% Haste at rank 3")
	# The grant ends: the off-hand weapon goes back to the backpack, once.
	var changes := [0]
	p.equipment.changed.connect(func() -> void: changes[0] += 1)
	_remove(p, WAR, "twinned_spirits", 3)
	check(not p.equipment.can_dual_wield(), "no dual wield any more")
	check(p.equipment.get_item(Items.EquipSlot.OFF_HAND) == null, "the off hand is empty")
	check(dagger in p.equipment.backpack, "the dagger is in the backpack")
	check(p.off_hand == null and p.weapons.size() == 1, "one weapon attacks")
	check_eq(p.stats.get_raw(Stats.HASTE), 0.0, "the Haste went with it")
	check(changes[0] >= 1, "the equipment reported the change")
	check(not p.equipment.equip(dagger, Items.EquipSlot.OFF_HAND), "the off hand is closed again")


func test_taking_twinned_spirits_back_leaves_a_shield_alone() -> void:
	var p := _shaman()
	var shield := p.equipment.get_item(Items.EquipSlot.OFF_HAND)
	check(shield != null, "the Shaman starts with a shield")
	_add(p, WAR, "twinned_spirits")
	check(p.equipment.get_item(Items.EquipSlot.OFF_HAND) == shield, "the shield stays while the talent is on")
	_remove(p, WAR, "twinned_spirits")
	check(p.equipment.get_item(Items.EquipSlot.OFF_HAND) == shield, "a shield never needed dual wield: it stays")


func test_hardened_knuckles_and_mirrored_strikes() -> void:
	var p := _shaman()
	_add(p, WAR, "twinned_spirits", 3)
	_add(p, WAR, "hardened_knuckles")
	check_near(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.04, 0.0001, "+4% weapon damage")
	_add(p, WAR, "hardened_knuckles", 2)
	check_near(p.bonuses.damage_mult(null, &"physical", &"weapon"), 1.12, 0.0001, "+12% at 3/3")
	check_eq(p.bonuses.damage_mult(null, &"nature", &"ability"), 1.0, "abilities are not weapon hits")
	check_eq(p.bonuses.damage_mult(null, &"fire", &"dot"), 1.0, "neither are burns")
	_add(p, WAR, "mirrored_strikes", 3)
	check_eq(p.stats.get_raw(Stats.EXTRA_ATTACK), 0.0, "no extra attacks with the shield")
	var dagger := _dagger()
	check(p.equipment.add_to_backpack(dagger) and p.equipment.equip(dagger, Items.EquipSlot.OFF_HAND), "dual wield")
	check_eq(p.stats.get_raw(Stats.EXTRA_ATTACK), 12.0, "4% per rank while dual wielding")
	check(p.equipment.unequip(Items.EquipSlot.OFF_HAND), "the second weapon goes")
	check_eq(p.stats.get_raw(Stats.EXTRA_ATTACK), 0.0, "and the extra attacks with it")


func test_spirit_pulse_builds_more_surge_per_hit_and_cast() -> void:
	var p := _shaman()
	p.stats.set_source(&"test", {Stats.INTELLECT: 10.0, Stats.SPELL_POWER: 4.0})
	var e := _enemy(Vector3(3, 0, 0))
	_learn(p, &"thunderbolt")
	check_eq(_surge(p).gain_on_hit(), 5.0, "5 Surge per hit")
	_add(p, WAR, "hardened_knuckles", 3)
	for n in range(1, 4):
		_add(p, WAR, "spirit_pulse")
		check_eq(_surge(p).gain_on_hit(), 5.0 + float(n), "%d Surge per hit (rank %d)" % [5 + n, n])
	_surge(p).set_value(0.0)
	p.on_hit_dealt(3.0, e, p.main_hand, false, false, true, 3.0)
	check_eq(_surge(p).value, 8.0, "a weapon hit gives 8")
	_surge(p).set_value(0.0)
	check(_cast(p, &"thunderbolt"), "a cast")
	check_eq(_surge(p).value, 8.0, "and a cast gives 8 too")


func test_flame_tempering_molten_trail_and_howling_chorus_change_their_abilities() -> void:
	var p := _shaman()
	_learn(p, &"magma_lash")
	_learn(p, &"spirit_pack")
	_learn(p, &"soothing_downpour")
	var lash := Db.get_ability(&"magma_lash")
	var pack := Db.get_ability(&"spirit_pack")
	var rain := Db.get_ability(&"soothing_downpour")
	var lash_cd := p.abilities.cooldown_of(lash)
	var pack_cd := p.abilities.cooldown_of(pack)
	var rain_cd := p.abilities.cooldown_of(rain)
	var lash_power := float(_params(p, &"magma_lash").get("power", 1.0))
	var pack_power := float(_params(p, &"spirit_pack").get("power", 1.0))
	_add(p, WAR, "twinned_spirits", 3)
	_add(p, WAR, "hardened_knuckles", 3)
	for n in range(1, 3):
		_add(p, WAR, "flame_tempering")
		check_near(float(_params(p, &"magma_lash")["power"]), lash_power * (1.0 + 0.08 * n), 0.0001, "+8% Magma Lash damage per rank")
		check_near(p.abilities.cooldown_of(lash), lash_cd * (1.0 - 0.08 * n), 0.0001, "-8% cooldown per rank")
	check_eq(float(_params(p, &"magma_lash")["ground_duration"]), 0.0, "no molten ground yet")
	_add(p, WAR, "molten_trail")
	var ground := _params(p, &"magma_lash")
	check_eq(float(ground["ground_duration"]), 3.0, "Molten Trail: 3 sec of molten ground")
	check_eq(float(ground["ground_pct"]), 15.0, "15% of the lash every tick")
	_add(p, WAR, "spirit_pulse", 3)
	for n in range(1, 4):
		_add(p, WAR, "howling_chorus")
		check_near(float(_params(p, &"spirit_pack")["power"]), pack_power * (1.0 + 0.08 * n), 0.0001, "+8% Spirit Pack damage per rank")
		check_near(p.abilities.cooldown_of(pack), pack_cd * (1.0 - 0.05 * n), 0.0001, "-5% cooldown per rank")
	check_eq(p.abilities.cooldown_of(rain), rain_cd, "other abilities are untouched")
	_remove(p, WAR, "howling_chorus", 3)
	_remove(p, WAR, "molten_trail")
	check_near(p.abilities.cooldown_of(pack), pack_cd, 0.0001, "undone")
	check_eq(float(_params(p, &"magma_lash")["ground_duration"]), 0.0, "the ground is gone")


func test_molten_trail_leaves_burning_ground_under_the_lash() -> void:
	var p := _shaman()
	p.stats.set_source(&"test", {Stats.INTELLECT: 10.0, Stats.SPELL_POWER: 4.0})
	_learn(p, &"magma_lash")
	_add(p, WAR, "twinned_spirits", 3)
	_add(p, WAR, "hardened_knuckles", 3)
	_add(p, WAR, "molten_trail")
	var e := _enemy(Vector3(1.5, 0, 0))
	var before := _areas()
	check(_cast(p, &"magma_lash"), "Magma Lash")
	check_eq(_areas(), before + 1, "a patch of molten ground under the target")
	check(e.fake_damage_log.size() >= 1, "the lash itself landed")


func test_crackling_blows_shocks_a_share_of_the_hit() -> void:
	var p := _shaman()
	_add(p, WAR, "twinned_spirits", 3)
	_add(p, WAR, "hardened_knuckles", 3)
	_add(p, WAR, "mirrored_strikes", 3)
	_add(p, WAR, "crackling_blows", 3)
	var def: Dictionary = {}
	for d: Dictionary in p.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS):
		if d.get("trigger") == "on_hit":
			def = d
	check(def.get("effect") == "bolt" and def.get("chance") == 45.0 and def.get("hit_pct") == 60.0 and def.get("school") == "nature",
		"15%% per rank, 60%% of the hit as Nature: %s" % def)
	var e := _enemy(Vector3(2, 0, 0))
	for i in 400:
		p.on_hit_dealt(10.0, e, p.main_hand, false, false, true, 10.0)
	var shocks := e.fake_damage_log.size()
	for v in e.fake_damage_log:
		check_near(v, 6.0, 0.001, "a shock is 60% of the hit's 10")
	check(shocks >= 130 and shocks <= 230, "about 45%% of 400 hits shock (got %d)" % shocks)
	for i in 50:
		p.on_hit_dealt(10.0, e, p.main_hand, false, true, false, 10.0)
	check_eq(e.fake_damage_log.size(), shocks, "hits that do not roll procs shock nothing")


# --- Wellspring ------------------------------------------------------------------------------------

func test_gentle_current_raises_healing_done() -> void:
	var p := _shaman()
	var ally := _ally(1, Vector3(3, 0, 0))
	for n in range(1, 4):
		_add(p, WELL, "gentle_current")
		check_eq(p.stats.get_raw(Stats.HEALING_DONE), 4.0 * n, "+4% Healing Done per rank")
		check_near(ShamanKit.healing_mult(p), 1.0 + 0.04 * n, 0.0001, "the kit multiplier")
	check_near(ShamanKit.heal_amount(p, ally, 1.0, 0.0, 0.0), 1.12, 0.0001, "a heal of 1 is 1.12")
	_remove(p, WELL, "gentle_current", 3)
	check_eq(ShamanKit.healing_mult(p), 1.0, "undone")


func test_weathered_wood_and_attuned_totems_change_the_totems() -> void:
	var p := _shaman()
	p.stats.set_source(&"test", {Stats.INTELLECT: 10.0, Stats.SPELL_POWER: 4.0})
	var rite := _params(p, &"totem_rite")
	check_eq(float(ShamanKit.totem_params(p, rite)["duration"]), 10.0, "10 sec")
	for n in range(1, 4):
		_add(p, WELL, "weathered_wood")
		check_near(float(ShamanKit.totem_params(p, rite)["duration"]), 10.0 * (1.0 + 0.1 * n), 0.0001, "+10% duration per rank")
	var e := _enemy(Vector3(3, 0, 0))
	check(_cast(p, &"totem_rite"), "Fire Totem")
	var fire := _fx_rite(p).standing()[0]
	check_near(fire.life_left, 13.0, 0.0001, "the real totem stands 13 sec")
	fire.step(0.31)
	var plain := e.fake_damage_log[0]
	_add(p, WELL, "gentle_current", 3)
	for n in range(1, 3):
		_add(p, WELL, "attuned_totems")
		var tp := ShamanKit.totem_params(p, rite)
		check_near(float(tp["power"]), 1.0 + 0.08 * n, 0.0001, "+8% power per rank")
		check_near(float(tp["earth_slow"]), 30.0 + 3.0 * n, 0.0001, "+3% Earth slow per rank")
	p.abilities.set_cooldown(Db.get_ability(&"totem_rite"), 0.0)
	check(_cast(p, &"totem_rite"), "Water Totem")
	var water := _fx_rite(p).standing()[0]
	check_eq(water.element, &"water", "the next element")
	var hurt := _ally(1, Vector3(2, 0, 0))
	hurt.hp = hurt.max_hp() * 0.5
	var before := hurt.hp
	water.step(0.0)
	check_near(hurt.hp - before, ShamanKit.heal_amount(p, hurt, 0.5, 2.5, 0.5, 1.16), 0.001,
		"the Water totem heals 16% more (Attuned Totems 2/2), 12% more with Gentle Current")
	p.abilities.set_cooldown(Db.get_ability(&"totem_rite"), 0.0)
	check(_cast(p, &"totem_rite"), "Earth Totem")
	var earth := _fx_rite(p).standing()[0]
	check_eq(earth.element, &"earth", "earth")
	e.slows.clear()
	earth.step(0.3)
	check(not e.slows.is_empty(), "the Earth totem slows")
	if not e.slows.is_empty():
		check_near(e.slows[0], 36.0 * 1.16, 0.001, "36% x 1.16 power")
	# Fire damage grew with the power too.
	p.abilities.set_cooldown(Db.get_ability(&"totem_rite"), 0.0)
	_cast(p, &"totem_rite")  # Air
	p.abilities.set_cooldown(Db.get_ability(&"totem_rite"), 0.0)
	_cast(p, &"totem_rite")  # Fire again
	var again := _fx_rite(p).standing()[0]
	check_eq(again.element, &"fire", "fire again")
	e.fake_damage_log.clear()
	again.step(0.31)
	check_near(e.fake_damage_log[0], plain * 1.16, 0.001, "the Fire totem's bolt deals 16% more")


func test_deepening_rain_and_ancestral_reach() -> void:
	var p := _shaman()
	_learn(p, &"soothing_downpour")
	var rain := Db.get_ability(&"soothing_downpour")
	var cd := p.abilities.cooldown_of(rain)
	var power := float(_params(p, &"soothing_downpour")["power"])
	_add(p, WELL, "gentle_current", 3)
	for n in range(1, 4):
		_add(p, WELL, "deepening_rain")
		check_near(float(_params(p, &"soothing_downpour")["power"]), power * (1.0 + 0.06 * n), 0.0001, "+6% heal per rank")
		check_near(p.abilities.cooldown_of(rain), cd * (1.0 - 0.05 * n), 0.0001, "-5% cooldown per rank")
	var rite := _params(p, &"totem_rite")
	check_eq(float(rite["water_radius"]), 6.0, "6 m to start with")
	_add(p, WELL, "ancestral_reach")
	rite = _params(p, &"totem_rite")
	check_eq([float(rite["water_radius"]), float(rite["earth_radius"]), float(rite["air_radius"])], [8.0, 7.0, 8.0], "+2 m on the three fields")
	check_eq(float(rite["fire_range"]), 9.0, "the Fire totem's range is not a field")
	# The Water totem really reaches 2 m farther.
	var far := _ally(1, Vector3(7.5, 0, 0))
	far.hp = far.max_hp() * 0.5
	var before := far.hp
	_enemy(Vector3(3, 0, 0))
	check(_cast(p, &"totem_rite"), "Fire")
	p.abilities.set_cooldown(Db.get_ability(&"totem_rite"), 0.0)
	check(_cast(p, &"totem_rite"), "Water")
	var water := _fx_rite(p).standing()[0]
	check_eq(water.element, &"water", "Water")
	water.step(0.0)
	check(far.hp > before, "the ally at 7.5 m is healed (6 m would not reach)")
	_remove(p, WELL, "ancestral_reach")
	check_eq(float(_params(p, &"totem_rite")["water_radius"]), 6.0, "undone")


func test_blessed_rite_heals_the_most_wounded_hero_on_every_cast() -> void:
	var p := _shaman()
	var ally := _ally(1, Vector3(15, 0, 0))
	ally.hp = ally.max_hp() * 0.4
	p.hp = p.max_hp() * 0.9
	_add(p, WELL, "gentle_current", 3)
	_add(p, WELL, "weathered_wood", 3)
	_add(p, WELL, "elder_spirits", 3)
	var before := ally.hp
	_add(p, WELL, "blessed_rite", 3)
	_enemy(Vector3(3, 0, 0))
	check(_cast(p, &"totem_rite"), "Totem Rite")
	check_near(ally.hp - before, ally.max_hp() * 0.12, 0.001, "the most wounded hero (far away) heals 12% of their Max HP")
	check_eq(p.hp, p.max_hp() * 0.9, "the Shaman is not the most wounded")
	var found := false
	for d: Dictionary in p.procs.extra_defs(PlayerBonuses.SOURCE_TALENTS):
		if d.get("effect") == "heal":
			found = true
			check(d.get("trigger") == "on_cast" and d.get("target") == "lowest_ally" and d.get("max_hp_pct") == 12.0
				and d.get("ability") == "totem_rite", "12%% of Max HP at 3 ranks, on the bare id: %s" % d)
	check(found, "a heal proc")
