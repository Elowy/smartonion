extends TestCase
## M5 foundation (P0): the TalentState rules on fixture trees, the BonusVocabulary contract
## (validate / resolve / matches / matches_id / PSEUDO_IDS), the ability tags, Db's talent / set
## loading, the block caps, the Player / WeaponRunner / Enemy / LootDrops hooks (PlayerBonuses /
## ProcSystem through test doubles), RunState's spend log, wants, counters and start level, the
## launch options, Main's wiring and the panel's Forge entry / Talents tab.
##
## Frozen (integrator only). Every check here is a contract of the P0 API that the Wave-1
## implementations and content keep: no "nothing yet" asserts, no lookups of shipping ids,
## fixtures live in Db only under the "zz_test" class and Db is restored after each test. The
## P0 stubs have all been replaced by their packages (their pinned stub values went with them);
## the cross-package behaviour is covered by tests/test_m5_integration.gd.

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")
const DT := 1.0 / 60.0
const TMP_DIR := "user://m5_p0_talent_tree_test/"


## PlayerBonuses with every method overridden neutrally (set_effects only stores): the doubles
## below never run the real engine, only the P0 API.
class NeutralBonuses extends PlayerBonuses:
	var stored: Dictionary = {}

	func set_effects(source: StringName, entries: Array[Dictionary]) -> void:
		stored[source] = entries.duplicate(true)
		changed.emit()

	func effects_of(source: StringName) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		out.assign(stored.get(source, []))
		return out

	func ability_mods_for(_ability_id: StringName) -> Dictionary:
		return {}

	func damage_mult(_target: Node3D, _school: StringName, _source: StringName) -> float:
		return 1.0

	func damage_taken_mult(_kind: StringName, _attacker: Node3D) -> float:
		return 1.0

	func crit_forced(_target: Node3D) -> bool:
		return false

	func scripts() -> Array[TalentEffect]:
		var out: Array[TalentEffect] = []
		return out

	func on_hit(_target: Node3D, _damage: float, _is_crit: bool, _first: bool) -> void:
		pass

	func on_kill(_enemy: Node3D) -> void:
		pass

	func on_damage_taken(_amount: float, _attacker: Node3D) -> void:
		pass

	func on_cast(_slot_index: int, _ability: AbilityData) -> void:
		pass

	func on_avoided(_kind: StringName, _attacker: Node3D) -> void:
		pass

	func begin_wave() -> void:
		pass

	func end_wave() -> void:
		pass

	func tick(_delta: float) -> void:
		pass

	func teardown() -> void:
		pass


## PlayerBonuses test double: records hooks, returns scripted mods / forced crits.
class RecordingBonuses extends NeutralBonuses:
	## [target, damage, is_crit, first] per on_hit call.
	var hits: Array[Array] = []
	var order: Array[String] = []
	var mods: Dictionary = {}
	var force_crits := false
	var crit_asks: Array[Node3D] = []

	func on_hit(target: Node3D, damage: float, is_crit: bool, first: bool) -> void:
		hits.append([target, damage, is_crit, first])

	func begin_wave() -> void:
		order.append("bonuses.begin_wave")

	func ability_mods_for(ability_id: StringName) -> Dictionary:
		return mods.get(ability_id, {})

	func crit_forced(target: Node3D) -> bool:
		crit_asks.append(target)
		return force_crits


## ProcSystem test double: when after_wave_start runs and what the class resource holds then.
class RecordingProcs extends ProcSystem:
	var order: Array[String] = []
	var resource_at_start := -1.0

	func after_wave_start() -> void:
		order.append("procs.after_wave_start")
		var r := player.abilities.primary_resource()
		resource_at_start = r.value if r != null else -1.0


## Records on_avoided / on_damage_taken.
class AvoidBonuses extends NeutralBonuses:
	var kinds: Array[StringName] = []
	var taken := 0

	func on_avoided(kind: StringName, _attacker: Node3D) -> void:
		kinds.append(kind)

	func on_damage_taken(_amount: float, _attacker: Node3D) -> void:
		taken += 1


## An Enemy subclass built with Enemy.setup: its own AI step, no contact damage.
class ThinkingEnemy extends Enemy:
	var thoughts := 0

	func _think(_delta: float, _here: Vector3, _feared: bool) -> void:
		thoughts += 1

	func deals_contact_damage() -> bool:
		return false


var world: Node3D
var main: Main
var nodes: Array[Node] = []
var spent_entries: Array[Dictionary] = []
var specials: Array[Array] = []
## Db's talent / set dictionaries before a test injected fixtures (restored in after_each).
var _saved_db: Dictionary = {}


func before_each() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, 515)
	spent_entries.clear()
	specials.clear()


func after_each() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	tree.paused = false
	for n in nodes:
		UiFakes.free_node(n)
	nodes.clear()
	if world != null and is_instance_valid(world):
		EFakes.free_world(tree, world)
	world = null
	if RunState.spent.is_connected(_on_spent):
		RunState.spent.disconnect(_on_spent)
	if RunState.special_killed.is_connected(_on_special_killed):
		RunState.special_killed.disconnect(_on_special_killed)
	_restore_db()
	EliteAffixes.rate_mult = 1.0
	GoblinSpawner.chance_override = -1.0
	PlayerPanel.debug_start_tab = ""
	UiFakes.reset_players()
	Enemy.invalidate_player_cache()
	EnemyGrid.mark_dirty()


## Snapshot of Db's talent / set dictionaries; [method _restore_db] puts them back (after_each).
func _save_db() -> void:
	if _saved_db.is_empty():
		_saved_db = {"talent_trees": Db.talent_trees.duplicate(), "talents": Db.talents.duplicate(),
			"sets": Db.sets.duplicate()}


func _restore_db() -> void:
	if _saved_db.is_empty():
		return
	Db.talent_trees.assign(_saved_db["talent_trees"])
	Db.talents.assign(_saved_db["talents"])
	Db.sets.assign(_saved_db["sets"])
	_saved_db = {}


func _on_spent(entry: Dictionary) -> void:
	spent_entries.append(entry)


func _on_special_killed(kind: StringName, killer_index: int) -> void:
	specials.append([kind, killer_index])


# --- Fixtures ----------------------------------------------------------------------------------

static func _talent(id: String, tier: int, column: int, max_rank: int,
		kind: TalentData.Kind = TalentData.Kind.TALENT, prereq: StringName = &"") -> TalentData:
	var t := TalentData.new()
	t.id = StringName("warrior_arms_" + id)
	t.display_name = id.to_upper()
	t.tier = tier
	t.column = column
	t.max_rank = max_rank
	t.kind = kind
	t.prerequisite = prereq
	return t


static func _tree(id: StringName, display: String, index: int, talents: Array[TalentData]) -> TalentTreeData:
	var tree_data := TalentTreeData.new()
	tree_data.id = id
	tree_data.class_id = &"warrior"
	tree_data.display_name = display
	tree_data.index = index
	tree_data.talents = talents
	return tree_data


## A full-shape tree (22 points) "Arms": t1a/t1b, t2a/t2b, t3a (max 2) + t3m (modifier), t4a
## (prerequisite t2a) / t4b, t5 (capstone); plus a one-talent "Fury" tree (index 1).
static func _fixture_trees() -> Array[TalentTreeData]:
	var t1a := _talent("t1a", 1, 0, 3)
	t1a.display_name = "Deflection"
	t1a.description = "Increases your chance to dodge attacks by {dodge}% for {secs_fixed} sec."
	t1a.values = {"dodge": 2.0, "secs_fixed": 3.0}
	t1a.effects = [{"kind": "stats", "stats": {"dodge": 2.0}}]
	var t3m := _talent("t3m", 3, 1, 1, TalentData.Kind.MODIFIER)
	t3m.ability = &"whirlwind"
	var arms: Array[TalentData] = [
		t1a, _talent("t1b", 1, 1, 3), _talent("t2b", 2, 1, 3), _talent("t2a", 2, 0, 3),
		_talent("t3a", 3, 0, 2), t3m, _talent("t4a", 4, 0, 3, TalentData.Kind.TALENT, &"warrior_arms_t2a"),
		_talent("t4b", 4, 1, 3), _talent("t5", 5, 0, 1, TalentData.Kind.CAPSTONE),
	]
	var f1 := _talent("f1", 1, 0, 3)
	f1.id = &"warrior_fury_f1"
	var fury: Array[TalentData] = [f1]
	# Given out of order on purpose: TalentState sorts by index.
	return [_tree(&"warrior_fury", "Fury", 1, fury), _tree(&"warrior_arms", "Arms", 0, arms)]


func _state(level: int = 31) -> TalentState:
	RunState.set_start_level(level)
	return TalentState.create(&"warrior", _fixture_trees())


static func _id(short: String) -> StringName:
	return StringName("warrior_arms_" + short)


func _add_n(s: TalentState, short: String, n: int) -> void:
	for i in n:
		check(s.add(_id(short)), "add %s: %s" % [short, s.add_block_reason(_id(short))])


func _player_world() -> void:
	world = EFakes.make_world(tree)


# --- Data classes ------------------------------------------------------------------------------

func test_talent_data_text_and_tiers() -> void:
	var trees := _fixture_trees()
	var arms := trees[1]
	var t := arms.get_talent(_id("t1a"))
	check_eq(t.text_for_rank(0), "Increases your chance to dodge attacks by 2% for 3 sec.", "rank 0 shows rank 1")
	check_eq(t.text_for_rank(3), "Increases your chance to dodge attacks by 6% for 3 sec.", "x rank, _fixed unscaled")
	t.values = {"dodge": 0.3, "secs_fixed": 1.5}
	check_eq(t.text_for_rank(3), "Increases your chance to dodge attacks by 0.9% for 1.5 sec.", "decimals")
	check_eq(TalentData.format_number(1.25), "1.25", "two decimals")
	check(arms.get_talent(&"nope") == null, "unknown talent")
	var tier2 := arms.talents_in_tier(2)
	check_eq(tier2.size(), 2, "two talents in tier 2")
	check(tier2[0].column == 0 and tier2[1].column == 1, "sorted by column")
	check(arms.get_talent(_id("t5")).is_capstone(), "capstone")
	check(not t.is_capstone(), "a talent is not")
	var set_data := SetData.new()
	check(set_data.piece_ids.is_empty() and set_data.bonuses.is_empty(), "SetData defaults")


func test_ability_tags() -> void:
	check_eq(Db.abilities.size(), 46, "every ability")
	for id in Db.abilities:
		var a := Db.abilities[id]
		check(not a.tags.is_empty(), "%s has tags" % id)
		for tag in a.tags:
			check(tag in BonusVocabulary.TAGS, "%s: known tag %s" % [id, tag])
	check_eq(Db.get_ability(&"fireball").tags, [&"projectile", &"dot", &"spell"] as Array[StringName], "fireball")
	check_eq(Db.get_ability(&"thunder_clap").tags, [&"aoe", &"cc", &"weapon"] as Array[StringName], "thunder clap")
	var pets := 0
	for id in Db.abilities:
		if &"pet" in Db.abilities[id].tags:
			pets += 1
	check_eq(pets, 3, "spirit wolf, infernal, voidwalker")


## Two "zz_test" trees (index 1 given first) + one of another class, registered in Db like
## Db._add_talent_tree does (trees and their talents). Ids no shipping content uses.
func _inject_test_trees() -> Array[TalentTreeData]:
	_save_db()
	var a1 := _talent("a1", 1, 0, 3)
	a1.id = &"zz_test_arms_a1"
	a1.effects = [{"kind": "stats", "stats": {"crit": 1.0}}]
	var f1 := _talent("f1", 1, 0, 3)
	f1.id = &"zz_test_fury_f1"
	var fury := _tree(&"zz_test_fury", "Fury", 1, [f1] as Array[TalentData])
	var arms := _tree(&"zz_test_arms", "Arms", 0, [a1] as Array[TalentData])
	var other := _tree(&"zz_other_fire", "Fire", 0, [] as Array[TalentData])
	fury.class_id = &"zz_test"
	arms.class_id = &"zz_test"
	other.class_id = &"zz_other"
	var out: Array[TalentTreeData] = [fury, arms, other]
	for t in out:
		Db.talent_trees[t.id] = t
		for talent in t.talents:
			Db.talents[talent.id] = talent
	return out


func test_db_talents_and_sets() -> void:
	# Holds with or without shipped content: only "zz_test" ids are injected, Db is restored.
	var before := Db.talent_trees.size()
	_inject_test_trees()
	var got := Db.talent_trees_for(&"zz_test")
	check_eq(got.size(), 2, "the class's two trees, not the other class's")
	check(got.size() == 2 and got[0].id == &"zz_test_arms" and got[1].id == &"zz_test_fury", "by index")
	check_eq(Db.get_talent_tree(&"zz_test_fury"), got[1] if got.size() == 2 else null, "get_talent_tree")
	check(Db.get_talent(&"zz_test_arms_a1") != null and Db.get_talent(&"zz_test_arms_a1").display_name == "A1", "get_talent")
	check(Db.get_talent(&"zz_test_arms_nope") == null and Db.get_talent_tree(&"zz_test_nope") == null, "unknown ids")
	check(Db.talent_trees_for(&"zz_nobody").is_empty(), "a class without trees")
	# Sets: the first of the class by id.
	var s := SetData.new()
	s.id = &"zz_test_z_set"
	s.class_id = &"zz_test"
	var s2 := SetData.new()
	s2.id = &"zz_test_a_set"
	s2.class_id = &"zz_test"
	Db.sets[s.id] = s
	Db.sets[s2.id] = s2
	check_eq(Db.set_for_class(&"zz_test"), s2, "first set by id")
	check_eq(Db.get_set(&"zz_test_z_set"), s, "get_set")
	check(Db.get_set(&"zz_test_nope") == null and Db.set_for_class(&"zz_nobody") == null, "unknown set / class")
	_restore_db()
	check_eq(Db.talent_trees.size(), before, "restored")
	check(not Db.talent_trees.has(&"zz_test_arms") and not Db.talents.has(&"zz_test_arms_a1")
		and not Db.sets.has(&"zz_test_a_set"), "fixtures gone again")


func test_talent_state_reads_its_trees_from_db() -> void:
	_inject_test_trees()
	var s := TalentState.create(&"zz_test")
	check_eq(s.trees().size(), 2, "Db.talent_trees_for without explicit trees")
	check(not s.trees().is_empty() and s.trees()[0].id == &"zz_test_arms", "in tab order")
	var fury := s.tree_of(&"zz_test_fury_f1")
	check(s.talent(&"zz_test_arms_a1") != null and fury != null and fury.id == &"zz_test_fury", "lookups")
	check_eq(s.add_block_reason(&"zz_other_x"), "Unknown talent", "another class's id")
	RunState.set_start_level(10)
	check(s.add(&"zz_test_arms_a1"), "spend a point")
	check_eq(s.effects().size(), 1, "its entry")
	var empty := TalentState.create(&"zz_nobody")
	check(empty.trees().is_empty() and empty.effects().is_empty(), "a class without trees")
	check_eq(empty.add_block_reason(&"zz_test_arms_a1"), "Unknown talent", "nothing to add")


func test_db_load_tree_descends_into_subfolders() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR + "warrior")
	DirAccess.make_dir_recursive_absolute(TMP_DIR + "mage")
	var trees := _fixture_trees()
	check_eq(ResourceSaver.save(trees[1], TMP_DIR + "warrior/arms.tres"), OK, "save arms")
	check_eq(ResourceSaver.save(trees[0], TMP_DIR + "warrior/fury.tres"), OK, "save fury")
	var fire := _tree(&"mage_fire", "Fire", 1, [] as Array[TalentData])
	check_eq(ResourceSaver.save(fire, TMP_DIR + "mage/fire.tres"), OK, "save fire")
	var loaded := Db._load_tree(TMP_DIR)
	var ids: Array[StringName] = []
	for res in loaded:
		if res is TalentTreeData:
			ids.append(res.id)
	check_eq(ids, [&"mage_fire", &"warrior_arms", &"warrior_fury"] as Array[StringName], "every subfolder, by name")
	for res in loaded:
		if res is TalentTreeData and res.id == &"warrior_arms":
			check_eq(res.talents.size(), 9, "sub-resources load with the tree")
			check_eq(res.get_talent(_id("t1a")).effects[0]["stats"]["dodge"], 2.0, "effects survive the round trip")
	for path in ["warrior/arms.tres", "warrior/fury.tres", "mage/fire.tres", "warrior", "mage", ""]:
		DirAccess.remove_absolute(TMP_DIR + path)


# --- TalentState -------------------------------------------------------------------------------

func test_talent_points_and_level_gate() -> void:
	var s := _state(9)
	check_eq(s.trees().size(), 2, "two trees")
	check_eq(s.trees()[0].id, &"warrior_arms", "sorted by index")
	check_eq(s.tree_of(_id("t2a")).id, &"warrior_arms", "tree_of")
	check_eq(s.points_earned(), 0, "nothing before level 10")
	check_eq(s.add_block_reason(_id("t1a")), "Talent points from level 10", "level gate")
	check_eq(s.add_block_reason(&"nope"), "Unknown talent", "unknown")
	RunState.set_start_level(10)
	check_eq(s.points_free(), 1, "one point at level 10")
	check(s.add(_id("t1a")), "spend it")
	check_eq(s.add_block_reason(_id("t1b")), "No talent points", "spent out")
	RunState.set_start_level(31)
	check_eq(s.points_earned(), 22, "22 at level 31")
	check_eq(s.points_spent(), 1, "spent")
	check_eq(s.points_free(), 21, "free")
	_add_n(s, "t1a", 2)
	check_eq(s.add_block_reason(_id("t1a")), "Max rank", "max rank")
	check_eq(s.rank_of(_id("t1a")), 3, "rank 3")
	check_eq(s.tree_points(&"warrior_arms"), 3, "tree points")
	check_eq(s.tree_points(&"warrior_fury"), 0, "other tree")


func test_tier_gates_and_prerequisites() -> void:
	var s := _state()
	_add_n(s, "t1a", 2)
	check_eq(s.add_block_reason(_id("t2a")), "Needs 3 points in Arms", "tier 2 gate")
	_add_n(s, "t1a", 1)
	check(s.can_add(_id("t2a")), "3 points open tier 2")
	check_eq(s.points_below_tier(s.tree_of(_id("t2a")), 2), 3, "points below tier 2")
	check_eq(s.add_block_reason(_id("t3a")), "Needs 6 points in Arms", "tier 3 gate")
	_add_n(s, "t2b", 3)
	_add_n(s, "t3a", 2)
	_add_n(s, "t3m", 1)
	check_eq(s.points_below_tier(s.tree_of(_id("t4a")), 4), 9, "9 below tier 4")
	check_eq(s.add_block_reason(_id("t4a")), "Requires T2A", "prerequisite at max rank")
	check(s.can_add(_id("t4b")), "the other tier-4 talent has none")
	check_eq(s.add_block_reason(_id("t5")), "Needs 12 points in Arms", "capstone gate")
	_add_n(s, "t2a", 2)
	check_eq(s.add_block_reason(_id("t4a")), "Requires T2A", "2 / 3 is not enough")
	_add_n(s, "t2a", 1)
	check(s.can_add(_id("t4a")), "prerequisite maxed")
	check(s.can_add(_id("t5")), "12 points below tier 5 open the capstone")
	# Fury is gated by its own tree only.
	check(s.can_add(&"warrior_fury_f1"), "another tree's tier 1")


func test_capstone_reachable_with_13_points() -> void:
	var s := _state()
	_add_n(s, "t1a", 3)
	_add_n(s, "t1b", 3)
	_add_n(s, "t2a", 3)
	_add_n(s, "t2b", 3)
	check(s.can_add(_id("t5")), "12 points in tiers 1–2 open tier 5")
	check(s.add(_id("t5")), "capstone")
	check_eq(s.points_spent(), 13, "13 points")


func test_undo_rules() -> void:
	var s := _state()
	var emitted := [0]
	s.changed.connect(func() -> void: emitted[0] += 1)
	_add_n(s, "t1a", 3)
	check_eq(emitted[0], 3, "changed on every add")
	check_eq(s.pending.get(_id("t1a"), 0), 3, "pending")
	_add_n(s, "t2a", 3)
	check_eq(s.remove_block_reason(_id("t1a")), "T2A needs those points", "gate break")
	check(not s.remove(_id("t1a")), "refused")
	check_eq(s.rank_of(_id("t1a")), 3, "unchanged")
	_add_n(s, "t1b", 1)
	check(s.can_remove(_id("t1a")), "4 points in tier 1: one can go")
	check(s.remove(_id("t1a")), "take one back")
	check_eq(emitted[0], 8, "changed on remove")
	check_eq(s.pending.get(_id("t1a"), 0), 2, "one pending point less")
	_add_n(s, "t3a", 2)
	_add_n(s, "t3m", 1)
	_add_n(s, "t4a", 1)
	check_eq(s.remove_block_reason(_id("t2a")), "T4A depends on it", "a dependent prerequisite")
	check_eq(s.remove_block_reason(_id("t3m")), "T4A needs those points", "tier 4 needs all 9")
	check_eq(s.remove_block_reason(_id("t4a")), "", "the top one is free")
	check(s.remove(_id("t4a")), "the top one goes first")
	check(s.remove(_id("t3m")), "then the gate is free")
	check_eq(s.remove_block_reason(&"nope"), "Unknown talent", "unknown")
	# commit: no signal, nothing pending, nothing can be taken back.
	var before: int = emitted[0]
	s.commit()
	check_eq(emitted[0], before, "commit emits nothing")
	check(s.pending.is_empty(), "pending cleared")
	check_eq(s.remove_block_reason(_id("t1b")), "Only points spent since the last wave can be taken back",
		"nothing to take back")
	check_eq(s.remove_block_reason(_id("t1a")), "Only points spent since the last wave can be taken back",
		"committed points stay")
	var spent := s.points_spent()
	_add_n(s, "t1b", 1)
	check(s.remove(_id("t1b")), "a new pending point can be taken back")
	check_eq(s.rank_of(_id("t1b")), 1, "back to the committed rank")
	check_eq(s.remove_block_reason(_id("t1b")), "Only points spent since the last wave can be taken back",
		"but not below it")
	check_eq(s.points_spent(), spent, "points back")
	_add_n(s, "t2b", 1)
	check(s.remove(_id("t2b")), "a talent taken this round")
	check(not s.ranks.has(_id("t2b")), "rank 0 is not stored")


func test_player_begin_wave_commits_without_a_rebuild() -> void:
	_player_world()
	RunState.set_start_level(12)
	var p := Fakes.spawn_player(world, 0, &"warrior")
	p.talents = TalentState.create(&"warrior", _fixture_trees())
	p.talents.changed.connect(p._on_talents_changed)
	var rebuilds := [0]
	p.bonuses.changed.connect(func() -> void: rebuilds[0] += 1)
	check(p.talents.add(_id("t1a")), "add")
	check_eq(rebuilds[0], 1, "an add rebuilds the engine")
	var entries := p.bonuses.effects_of(PlayerBonuses.SOURCE_TALENTS)
	check_eq(entries.size(), 1, "the talent's entry reached the engine")
	check_eq(entries[0]["rank"], 1, "with its rank")
	p.begin_wave()
	check(p.talents.pending.is_empty(), "begin_wave commits")
	check_eq(rebuilds[0], 1, "without a rebuild")


func test_reset_prices_and_spend_log() -> void:
	var s := _state()
	RunState.spent.connect(_on_spent)
	check_eq(s.reset_price(), 20, "20 g")
	check_eq(s.reset_block_reason(), "Nothing to reset", "nothing spent")
	_add_n(s, "t1a", 2)
	check_eq(s.reset_block_reason(), "Not enough gold (20 g)", "broke")
	check(not s.try_reset(0), "refused")
	RunState.add_gold(200)
	var emitted := [0]
	s.changed.connect(func() -> void: emitted[0] += 1)
	check(s.try_reset(1), "reset")
	check(s.ranks.is_empty() and s.pending.is_empty(), "every point back (pending too)")
	check_eq(emitted[0], 1, "changed")
	check_eq(RunState.gold, 180, "paid from the wallet")
	check_eq(s.resets, 1, "counted")
	check_eq(RunState.talent_resets, 1, "run statistic")
	check_eq(spent_entries.size(), 1, "spent signal")
	var e := RunState.spend_log.back() as Dictionary
	check(e["slot"] == 1 and e["kind"] == &"talent_reset" and e["label"] == "Reset Talents" and e["amount"] == 20,
		"logged: %s" % str(e))
	check_eq(s.reset_price(), 40, "40 g next")
	_add_n(s, "t1a", 1)
	s.commit()
	check(s.try_reset(1), "committed points reset too")
	check_eq(s.reset_price(), 80, "80 g next")
	check_eq(RunState.gold, 140, "40 paid")


func test_effects_and_saving() -> void:
	var s := _state()
	_add_n(s, "t1a", 2)
	_add_n(s, "t1b", 1)
	var effects := s.effects()
	check_eq(effects.size(), 1, "only talents with effects give entries")
	var e := effects[0]
	check_eq(e["kind"], "stats", "kind")
	check_eq(e["rank"], 2, "rank")
	check_eq(e["id"], "warrior_arms_t1a", "talent id")
	check_eq(e["label"], "Deflection", "label")
	check_eq(e["stats"]["dodge"], 2.0, "amount stays per rank (the engine resolves it)")
	e["stats"]["dodge"] = 99.0
	check_eq(s.talent(_id("t1a")).effects[0]["stats"]["dodge"], 2.0, "a deep copy")
	var d := s.to_dict()
	check_eq(d["version"], 1, "version")
	check_eq(d["ranks"], {"warrior_arms_t1a": 2, "warrior_arms_t1b": 1}, "ranks")
	var other := _state()
	other.from_dict({"version": 1, "ranks": {"warrior_arms_t1a": 9, "warrior_arms_gone": 2, "warrior_arms_t1b": 1}, "resets": 2})
	check_eq(other.rank_of(_id("t1a")), 3, "clamped to max")
	check(not other.ranks.has(&"warrior_arms_gone"), "unknown ids dropped")
	check(other.pending.is_empty(), "nothing pending")
	check_eq(other.resets, 2, "resets")
	check_eq(other.reset_price(), 80, "price follows the resets")


# --- BonusVocabulary ---------------------------------------------------------------------------

## Every example of talent_vocabulary.md (and the set / capstone entries) with its class.
static func _valid_examples() -> Array[Array]:
	return [
		[{"kind": "stats", "stats": {"crit": 2.0, "primary": 1.0}}, &"warrior"],
		[{"kind": "stats", "stats": {"block_chance": 20.0}, "requires": {"weapon": "shield"}}, &"paladin"],
		[{"kind": "stats", "stats": {"healing_done": 5.0}}, &"paladin"],
		[{"kind": "ability", "match": {"id": "fireball"}, "mods": {"bounces_add": 1, "power_pct": 5}}, &"mage"],
		[{"kind": "ability", "match": {"school": "fire"}, "mods": {"power_pct": 3}}, &"mage"],
		[{"kind": "ability", "match": {"tag": "pet"}, "mods": {"cooldown_pct": -5}}, &"warlock"],
		[{"kind": "ability", "match": {"resource": "mana"}, "mods": {"cost_pct": 30}}, &"mage"],
		[{"kind": "ability", "match": {"kind": "auto"}, "mods": {"cooldown_add": -1}}, &"rogue"],
		[{"kind": "ability", "match": {"class": true}, "mods": {"charges_add": 1}}, &"rogue"],
		[{"kind": "ability", "match": {"ids": ["fireball", "pyroblast"]}, "mods": {"free_chance_add": 10}}, &"mage"],
		[{"kind": "ability", "match": {"id": "charge"}, "mods": {"stun_add": 0.3, "cooldown_add": -0.5}}, &"warrior"],
		[{"kind": "ability", "match": {"id": "whirlwind"}, "mods": {"free_chance_add": 30}}, &"warrior"],
		[{"kind": "ability", "match": {"id": "word_of_glory"}, "mods": {"heal_all": true}}, &"paladin"],
		[{"kind": "ability", "match": {"id": "rain_of_fire"}, "mods": {"free_chance_add": 20}}, &"warlock"],
		[{"kind": "ability", "match": {"id": "bandage"}, "mods": {"targets_add": 1}}, &"warrior"],
		# Whirlwind's damage is the "damage_pct" param itself: raise it with "damage_pct_add".
		[{"kind": "ability", "match": {"id": "whirlwind"}, "mods": {"damage_pct_add": 10}}, &"warrior"],
		[{"kind": "damage", "pct": 2.0}, &"warrior"],
		[{"kind": "damage", "pct": 5.0, "source": ["dot", "pet"]}, &"warlock"],
		[{"kind": "damage", "pct": 4.0, "school": "fire"}, &"mage"],
		[{"kind": "damage", "pct": 10.0, "target": "stunned"}, &"warrior"],
		[{"kind": "damage", "pct": 8.0, "target": "below_pct", "target_pct": 35.0}, &"warrior"],
		[{"kind": "damage", "pct": 6.0, "self_below_pct": 50.0}, &"warrior"],
		[{"kind": "damage", "pct": 5.0, "requires": {"weapon": "two_handed"}}, &"warrior"],
		[{"kind": "damage", "source": "pet", "pct": 10.0}, &"warlock"],
		[{"kind": "damage_taken", "pct": -3.0}, &"warrior"],
		[{"kind": "damage_taken", "pct": -5.0, "kind_filter": "projectile"}, &"warrior"],
		[{"kind": "resource", "resource": "rage", "start_value_add": 5.0}, &"warrior"],
		[{"kind": "resource", "resource": "holy_power", "gain_per_hits_add": -1}, &"paladin"],
		[{"kind": "resource", "resource": "primary", "regen_per_second_add": 1.0}, &"mage"],
		[{"kind": "resource", "resource": "mana", "max_value_add": 20.0}, &"mage"],
		[{"kind": "proc", "scale": ["chance"], "proc": {
			"trigger": "on_hit", "chance": 3.0, "effect": "cooldown", "ability": "execute", "reset": true}}, &"warrior"],
		[{"kind": "proc", "scale": ["hit_pct"], "proc": {
			"trigger": "on_crit", "effect": "dot", "hit_pct": 10.0, "duration": 3.0, "school": "physical"}}, &"warrior"],
		[{"kind": "proc", "proc": {
			"trigger": "on_cast", "ability": "blink", "effect": "buff", "stats": {"damage_pct": 30.0}, "duration": 3.0, "icd": 6}}, &"mage"],
		[{"kind": "proc", "proc": {
			"trigger": "on_hit", "every": 5, "effect": "nova", "hit_pct": 150.0, "radius": 2.5, "at": "target"}}, &"warrior"],
		[{"kind": "proc", "proc": {"trigger": "on_cast", "ability": "whirlwind", "effect": "buff",
			"stats": {"extra_attack": 25}, "duration": 5, "label": ""}}, &"warrior"],
		[{"kind": "proc", "proc": {"trigger": "on_cast", "ability": "vanish", "effect": "buff",
			"stats": {"crit_damage": 50}, "duration": 4}}, &"rogue"],
		[{"kind": "proc", "scale": ["chance"], "proc": {"trigger": "on_crit", "chance": 10, "effect": "resource",
			"resource": "soul_shard", "value": 1}}, &"warlock"],
		[{"kind": "proc", "proc": {"trigger": "on_block", "effect": "extra_attack", "count": 1}}, &"paladin"],
		[{"kind": "proc", "proc": {"trigger": "wave_start", "effect": "forced_crit", "count": 2}}, &"rogue"],
		[{"kind": "proc", "proc": {"trigger": "on_kill", "effect": "cooldown", "match": {"tag": "movement"}, "reduce": 1.0}}, &"rogue"],
		[{"kind": "proc", "scale": ["max_hp_pct"], "proc": {"trigger": "periodic", "interval": 5, "chance": 50,
			"effect": "heal", "max_hp_pct": 2.0, "target": "lowest_ally"}}, &"paladin"],
		[{"kind": "script", "script": "res://scenes/talents/warrior/arms_mortal_strike.gd",
			"params": {"every": 5, "strike_pct": 150.0, "wound_duration": 8.0, "heal_reduction": 50.0, "damage_taken_pct": 10.0}}, &"warrior"],
		# As a source hands them over (TalentState.effects / SetBonuses.effects_for).
		[{"kind": "stats", "stats": {"armor": 3.0}, "rank": 1, "id": "dawnforged_plate:2", "label": "Dawnforged Plate"}, &"paladin"],
		[{"kind": "damage", "pct": 25.0, "requires": {"knows": "fireball"}}, &"mage"],
	]


func test_validate_accepts_the_vocabulary_examples() -> void:
	for pair in _valid_examples():
		var err := BonusVocabulary.validate(pair[0], pair[1])
		check_eq(err, "", "%s for %s" % [str(pair[0]), pair[1]])
	# Without a class every class's abilities / resources are fine.
	check_eq(BonusVocabulary.validate({"kind": "resource", "resource": "energy", "gain_on_hit_add": 1}), "", "no class")


func test_validate_rejects_typos() -> void:
	var bad: Array[Array] = [
		[{"kind": "stat", "stats": {"crit": 2}}, &"warrior", "unknown kind"],
		[{"stats": {"crit": 2}}, &"warrior", "no kind"],
		[{"kind": "stats", "stats": {"crti": 2}}, &"warrior", "unknown stat"],
		[{"kind": "stats", "stats": {}}, &"warrior", "empty stats"],
		[{"kind": "stats", "stats": {"crit": "2"}}, &"warrior", "stat as text"],
		[{"kind": "ability", "match": {"tag": "aoee"}, "mods": {"power_pct": 3}}, &"warrior", "unknown tag"],
		[{"kind": "damage", "pct": 2, "sorce": "dot"}, &"warrior", "unknown key"],
		[{"kind": "ability", "match": {"school": "fire"}, "mods": {"damage_pct": 10}}, &"mage", "generic unsafe mod key"],
		[{"kind": "ability", "match": {"ids": ["fireball"]}, "mods": {"bounces_add": 1}}, &"mage", "ids are generic"],
		[{"kind": "resource", "resource": "holy_power", "max_value_add": 1}, &"paladin", "PIPS max_value_add"],
		[{"kind": "resource", "resource": "primary", "max_value_add": 1}, &"warlock", "primary pips"],
		[{"kind": "ability", "match": {"id": "firebal"}, "mods": {"power_pct": 5}}, &"mage", "unknown match.id"],
		[{"kind": "ability", "match": {"id": "fireball"}, "mods": {"bouncez_add": 1}}, &"mage", "unknown param"],
		[{"kind": "ability", "match": {"id": "fireball"}, "mods": {"explode": true}}, &"mage", "unknown replace key"],
		[{"kind": "ability", "match": {"id": "whirlwind"}, "mods": {"power_pct": 5}}, &"mage", "another class's ability"],
		[{"kind": "ability", "match": {"id": "fireball", "school": "fire"}, "mods": {"power_pct": 5}}, &"mage", "two match keys"],
		[{"kind": "ability", "match": {"class": false}, "mods": {"power_pct": 5}}, &"mage", "class false"],
		[{"kind": "ability", "match": {"school": "fire"}, "mods": {}}, &"mage", "no mods"],
		[{"kind": "ability", "match": {"kind": "passive"}, "mods": {"power_pct": 5}}, &"mage", "unknown ability kind"],
		[{"kind": "ability", "match": {"resource": "rage"}, "mods": {"power_pct": 5}}, &"mage", "another class's resource"],
		[{"kind": "damage"}, &"warrior", "no pct"],
		[{"kind": "damage", "pct": 5, "source": "spell"}, &"warrior", "unknown source"],
		[{"kind": "damage", "pct": 5, "target": "frozen"}, &"warrior", "unknown target"],
		[{"kind": "damage", "pct": 5, "target": "below_pct"}, &"warrior", "below_pct without target_pct"],
		[{"kind": "damage", "pct": 5, "school": "fel"}, &"warrior", "unknown school"],
		[{"kind": "damage_taken", "pct": -3, "kind_filter": "fire"}, &"warrior", "unknown kind_filter"],
		[{"kind": "resource", "resource": "soul_shards", "start_value_add": 1}, &"warlock", "resource id typo"],
		[{"kind": "resource", "resource": "rage"}, &"warrior", "no field"],
		[{"kind": "resource", "resource": "rage", "max_rage_add": 5}, &"warrior", "unknown field"],
		[{"kind": "proc", "proc": {"trigger": "on_hitt", "effect": "bolt", "damage": 3}}, &"warrior", "unknown trigger"],
		[{"kind": "proc", "proc": {"trigger": "on_hit", "effect": "fireball", "damage": 3}}, &"warrior", "unknown block"],
		[{"kind": "proc", "proc": {"trigger": "on_hit", "effect": "bolt", "damage_fixed": 3}}, &"warrior", "no _fixed keys"],
		[{"kind": "proc", "proc": {"trigger": "on_kill", "effect": "nova", "hit_pct": 50}}, &"warrior", "hit_pct needs a hit"],
		[{"kind": "proc", "scale": ["chance"], "proc": {"trigger": "on_hit", "effect": "bolt", "damage": 3}}, &"warrior", "scales a missing key"],
		[{"kind": "proc", "proc": {"trigger": "on_cast", "effect": "buff", "stats": {"crit": 5}}}, &"warrior", "on_cast without ability"],
		[{"kind": "proc", "proc": {"trigger": "on_hit", "effect": "cooldown", "ability": "execute"}}, &"warrior", "cooldown without reduce / reset"],
		[{"kind": "proc", "proc": {"trigger": "on_hit", "effect": "buff", "stats": {"crti": 5}}}, &"warrior", "unknown buff stat"],
		[{"kind": "proc", "proc": {"trigger": "on_hit", "effect": "heal", "amount": 2, "target": "ally"}}, &"paladin", "unknown heal target"],
		[{"kind": "proc", "proc": {"trigger": "on_crit", "effect": "resource", "resource": "rage", "value": 5}}, &"warlock", "another class's resource"],
		[{"kind": "script", "script": "scenes/talents/x.gd"}, &"warrior", "not a res:// path"],
		[{"kind": "script", "script": "res://scenes/talents/x.tres"}, &"warrior", "not a script"],
		[{"kind": "stats", "stats": {"crit": 1}, "requires": {"weapon": "bow"}}, &"warrior", "unknown weapon requirement"],
		[{"kind": "stats", "stats": {"crit": 1}, "requires": {"knows": "fireballl"}}, &"mage", "unknown known ability"],
		[{"kind": "stats", "stats": {"crit": 1}, "requires": {"level": 5}}, &"mage", "unknown requirement"],
		[{"kind": "stats", "stats": {"crit": 1}, "rank": 0}, &"mage", "rank 0"],
		[{"kind": "ability", "match": {"id": "whirlwind"}, "mods": {"damage_pct": 10}}, &"warrior",
			"a _pct that would replace (no 'damage' param, talent_vocabulary §3.2)"],
	]
	for case in bad:
		var err := BonusVocabulary.validate(case[0], case[1])
		check(err != "", "rejects %s: %s" % [case[2], str(case[0])])
	# The replace trap names the fix; apply_mods really would replace 150 with 10.
	var trap := {"kind": "ability", "match": {"id": "whirlwind"}, "mods": {"damage_pct": 10}}
	check_eq(BonusVocabulary.validate(trap, &"warrior"),
		"'damage_pct' would replace whirlwind's damage_pct (no 'damage' param); use damage_pct_add", "the message")
	var ww_params := Db.get_ability(&"whirlwind").params
	check_eq(AbilityRunner.apply_mods(ww_params, {"damage_pct": 10})["damage_pct"], 10, "why: apply_mods replaces")
	check_eq(AbilityRunner.apply_mods(ww_params, {"damage_pct_add": 10})["damage_pct"], 160.0, "the _add form adds")


func test_pseudo_ids_only_for_their_class() -> void:
	check_eq(BonusVocabulary.PSEUDO_IDS.size(), 5, "the closed registry")
	for id: StringName in BonusVocabulary.PSEUDO_IDS:
		var owner: StringName = BonusVocabulary.PSEUDO_IDS[id]
		var entry := {"kind": "ability", "match": {"id": String(id)}, "mods": {"damage_bonus_add": 10, "anything_pct": 5, "flag": true}}
		check_eq(BonusVocabulary.validate(entry, owner), "", "%s validates for %s (param keys skipped)" % [id, owner])
		for other in Db.class_ids:
			if other != owner:
				check(BonusVocabulary.validate(entry, other) != "", "%s refused for %s" % [id, other])
		check(BonusVocabulary.validate(entry) != "", "%s refused without a class" % id)
		var generic := {"kind": "ability", "match": {"ids": [String(id)]}, "mods": {"power_pct": 5}}
		check(BonusVocabulary.validate(generic, owner) != "", "%s only through match.id" % id)
	check(not Db.abilities.has(&"warlock_imp"), "pseudo ids are not abilities")


func test_resolve_scales_by_rank() -> void:
	var stats := BonusVocabulary.resolve({"kind": "stats", "stats": {"crit": 2.0, "primary": 1}}, 3)
	check_eq(stats["stats"], {"crit": 6.0, "primary": 3}, "stats: every number")
	var ability_entry := {"kind": "ability", "match": {"id": "fireball"},
		"mods": {"bounces_add": 1, "power_pct": 5.0, "heal_all": true, "windup": 0.5}}
	var ability := BonusVocabulary.resolve(ability_entry, 2)
	check_eq(ability["mods"], {"bounces_add": 2, "power_pct": 10.0, "heal_all": true, "windup": 0.5},
		"ability: _add / _pct only")
	check_eq(ability_entry["mods"]["bounces_add"], 1, "the input is untouched (deep copy)")
	var damage := BonusVocabulary.resolve({"kind": "damage", "pct": 2.0, "target": "below_pct", "target_pct": 35.0}, 3)
	check(damage["pct"] == 6.0 and damage["target_pct"] == 35.0, "damage: pct only")
	check_eq(BonusVocabulary.resolve({"kind": "damage_taken", "pct": -3.0}, 2)["pct"], -6.0, "damage_taken")
	var res := BonusVocabulary.resolve({"kind": "resource", "resource": "rage", "start_value_add": 5.0, "gain_on_hit_add": 1}, 3)
	check(res["start_value_add"] == 15.0 and res["gain_on_hit_add"] == 3 and res["resource"] == "rage", "resource: _add")
	var proc := BonusVocabulary.resolve({"kind": "proc", "scale": ["chance", "stats"], "proc": {
		"trigger": "on_hit", "chance": 3.0, "effect": "buff", "stats": {"crit": 2.0, "haste": 1}, "duration": 4.0, "icd": 2}}, 2)
	check_eq(proc["proc"]["chance"], 6.0, "proc: a listed key")
	check_eq(proc["proc"]["stats"], {"crit": 4.0, "haste": 2}, "proc: a listed stats dict")
	check(proc["proc"]["duration"] == 4.0 and proc["proc"]["icd"] == 2, "proc: unlisted keys stay")
	var script := {"kind": "script", "script": "res://x.gd", "params": {"every": 5}}
	check_eq(BonusVocabulary.resolve(script, 3), script, "script: nothing (rank goes to the script)")
	check_eq(BonusVocabulary.resolve({"kind": "stats", "stats": {"crit": 2.0}}, 1)["stats"]["crit"], 2.0, "rank 1")


func test_matches_filters_abilities() -> void:
	var fireball := Db.get_ability(&"fireball")
	var blizzard := Db.get_ability(&"blizzard")
	var bandage := Db.get_ability(&"bandage")
	check(BonusVocabulary.matches({"id": "fireball"}, fireball, &"mage"), "id")
	check(not BonusVocabulary.matches({"id": "blink"}, fireball, &"mage"), "another id")
	check(BonusVocabulary.matches({"ids": ["blink", "fireball"]}, fireball, &"mage"), "ids")
	check(BonusVocabulary.matches({"school": "fire"}, fireball, &"mage"), "school")
	check(not BonusVocabulary.matches({"school": "frost"}, fireball, &"mage"), "another school")
	check(BonusVocabulary.matches({"tag": "dot"}, fireball, &"mage"), "tag")
	check(not BonusVocabulary.matches({"tag": "aoe"}, fireball, &"mage"), "missing tag")
	check(BonusVocabulary.matches({"kind": "auto"}, fireball, &"mage"), "kind auto")
	check(BonusVocabulary.matches({"kind": "core"}, blizzard, &"mage"), "kind core")
	check(not BonusVocabulary.matches({"kind": "core"}, fireball, &"mage"), "not core")
	check(BonusVocabulary.matches({"resource": "mana"}, blizzard, &"mage"), "spends mana")
	check(not BonusVocabulary.matches({"resource": "mana"}, fireball, &"mage"), "free ability")
	check(BonusVocabulary.matches({"class": true}, fireball, &"mage"), "own class")
	check(not BonusVocabulary.matches({"class": true}, fireball, &"warrior"), "another class")
	check(not BonusVocabulary.matches({"class": true}, bandage, &"mage"), "general abilities are not the class's")
	check(not BonusVocabulary.matches({}, fireball, &"mage"), "empty filter")
	check(not BonusVocabulary.matches({"id": "fireball"}, null, &"mage"), "null ability")


func test_matches_id_reaches_pseudo_ids() -> void:
	# By id: real abilities go through matches with their Db data.
	check(BonusVocabulary.matches_id({"id": "fireball"}, &"fireball", &"mage"), "id")
	check(BonusVocabulary.matches_id({"school": "fire"}, &"fireball", &"mage"), "a generic filter")
	check(not BonusVocabulary.matches_id({"class": true}, &"fireball", &"warrior"), "owner class still counts")
	check(not BonusVocabulary.matches_id({"id": "fireball"}, &"firebal", &"mage"), "unknown id")
	# Pseudo ids have no AbilityData: matches alone never matches them, matches_id does by id.
	for id: StringName in BonusVocabulary.PSEUDO_IDS:
		var owner: StringName = BonusVocabulary.PSEUDO_IDS[id]
		check(not BonusVocabulary.matches({"id": String(id)}, Db.get_ability(id), owner), "%s: matches cannot" % id)
		check(BonusVocabulary.matches_id({"id": String(id)}, id, owner), "%s: matches_id can" % id)
		check(BonusVocabulary.matches_id({"id": id}, id, owner), "%s: StringName ids too" % id)
		check(not BonusVocabulary.matches_id({"id": "fireball"}, id, owner), "%s: another id" % id)
		check(not BonusVocabulary.matches_id({"class": true}, id, owner), "%s: generic filters never" % id)
		check(not BonusVocabulary.matches_id({"ids": [String(id)]}, id, owner), "%s: ids never" % id)
	check(not BonusVocabulary.matches_id({"id": "warlock_imp"}, &"paladin_aura", &"paladin"), "another pseudo id")


func test_vocabulary_constants_match_the_engine() -> void:
	var blocks: Array[StringName] = ProcSystem.BLOCKS.duplicate()
	blocks.append_array([&"cooldown", &"forced_crit"] as Array[StringName])
	check_eq(BonusVocabulary.PROC_BLOCKS, blocks, "ProcSystem.BLOCKS + cooldown, forced_crit")
	for r in BonusVocabulary.RESOURCE_FIELDS:
		check(r in ResourceData.new(), "ResourceData has %s" % r)
	for s in BonusVocabulary.SCHOOLS:
		check(Stats.SCHOOL_STATS.has(s), "school %s" % s)
	check_eq(BonusVocabulary.KINDS.size(), 7, "seven kinds")


# --- Stats, caps -------------------------------------------------------------------------------

func test_new_stats_and_block_caps() -> void:
	for s: StringName in [Stats.BLOCK_CHANCE, Stats.HEALING_DONE]:
		check(s in Stats.ALL, "%s in ALL" % s)
		check(Stats.is_percent(s), "%s is a percent stat" % s)
	check_eq(Stats.display_name(Stats.BLOCK_CHANCE), "Block", "Block")
	check_eq(Stats.display_name(Stats.HEALING_DONE), "Healing Done", "Healing Done")
	check_eq(CombatMath.block_absorb(1000.0), 0.85, "a block absorbs at most 85%")
	check_eq(CombatMath.block_absorb(0.0), 0.5, "half by default")
	_player_world()
	var p := Fakes.spawn_player(world, 0, &"paladin")
	check_eq(p.block_chance(), 10.0, "the shield's 10%")
	p.stats.set_source(&"test", {Stats.BLOCK_CHANCE: 25.0})
	check_eq(p.block_chance(), 35.0, "+ the Block stat")
	p.stats.set_source(&"test", {Stats.BLOCK_CHANCE: 60.0})
	check_eq(p.block_chance(), Stats.BLOCK_CAP, "capped at 50%")
	var w := Fakes.spawn_player(world, 1, &"warrior", Vector3(3, 0, 0))
	w.stats.set_source(&"test", {Stats.BLOCK_CHANCE: 20.0})
	check_eq(w.block_chance(), 20.0, "works without a shield (content uses requires: shield)")


# --- Player hooks ------------------------------------------------------------------------------

func test_player_has_bonuses_talents_and_merges_mods() -> void:
	_player_world()
	var p := Fakes.spawn_player(world, 0, &"warrior")
	check(p.bonuses != null and p.bonuses.player == p, "bonuses")
	check(p.talents != null and p.talents.class_id == &"warrior", "talents of the class")
	check(p.bonuses.effects_of(PlayerBonuses.SOURCE_SETS).is_empty(), "apply_equipment set the (empty) set bonuses")
	# A fresh hero has no talents and no set pieces: the engine is neutral.
	check_eq(p.bonuses.ability_mods_for(&"whirlwind"), {}, "no entries: no mods")
	check_eq(p.bonuses.damage_mult(null, &"fire", &"weapon"), 1.0, "no entries: neutral damage")
	check_eq(p.bonuses.damage_taken_mult(&"melee", null), 1.0, "no entries: neutral damage taken")
	check(not p.bonuses.crit_forced(null), "no entries: no forced crits")
	check(p.bonuses.scripts().is_empty(), "no entries: no scripts")
	var double := RecordingBonuses.new()
	double.player = p
	double.mods = {&"whirlwind": {"radius_add": 1.0, "power_pct": 10.0}}
	p.bonuses = double
	var item := ItemInstance.new()
	item.slot_type = Items.SlotType.HEAD
	item.armor_type = Items.NO_ARMOR
	item.unique_effect = &"ability_mod"
	item.unique_params = {"ability": "whirlwind", "mods": {"radius_add": 0.5}}
	check(p.equipment.equip(item), "equip the item")
	check_eq(p.ability_mods(&"whirlwind"), {"radius_add": 1.5, "power_pct": 10.0}, "items + bonuses, numbers summed")
	check_eq(p.ability_mods(&"charge"), {}, "other abilities")
	p.abilities.invalidate_params()
	var params := p.abilities.params_for(Db.get_ability(&"whirlwind"))
	check_eq(params["radius"], 4.5, "params_for sees the merged mods")
	check_near(float(params["power"]), 1.1, 0.0001, "power")


func test_talent_changes_reach_the_engine_and_invalidate_params() -> void:
	_player_world()
	RunState.set_start_level(15)
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var ww := Db.get_ability(&"whirlwind")
	var before := p.abilities.params_for(ww)
	check(is_same(p.abilities.params_for(ww), before), "cached")
	p.bonuses.set_effects(PlayerBonuses.SOURCE_TALENTS, [{"kind": "stats", "stats": {"crit": 2.0}, "rank": 1}] as Array[Dictionary])
	check(not is_same(p.abilities.params_for(ww), before), "bonuses.changed invalidated the params cache")
	check_eq(p.bonuses.effects_of(PlayerBonuses.SOURCE_TALENTS).size(), 1, "stored per source")
	check(p.bonuses.effects_of(PlayerBonuses.SOURCE_SETS).is_empty(), "other source untouched")


func test_on_hit_reaches_the_bonuses_for_every_hit_of_an_arc() -> void:
	_player_world()
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var rec := RecordingBonuses.new()
	rec.player = p
	p.bonuses = rec
	p.damage_mults[&"test"] = 2.0
	var a := Fakes.spawn_enemy(world, Vector3(1.2, 0, 0))
	var b := Fakes.spawn_enemy(world, Vector3(1.2, 0, 0.5))
	var c := Fakes.spawn_enemy(world, Vector3(1.2, 0, -0.5))
	EnemyGrid.mark_dirty()
	p.weapons[0].attack(a)
	check_eq(rec.hits.size(), 3, "every enemy of the arc")
	var firsts := 0
	for h in rec.hits:
		if h[3]:
			firsts += 1
		var e := h[0] as Fakes.FakeEnemy
		check_eq(e.fake_hits(), 1, "one hit each")
		check_near(float(h[1]), e.fake_damage_log[0] / 2.0, 0.0001, "the base amount, before the x2 multiplier")
		check_eq(h[2], e.fake_crit_log[0], "crit flag")
	check_eq(firsts, 1, "first once per attack")
	check(rec.hits[0][0] == a and rec.hits[0][3], "the attacked target is the first hit")
	check_near(p.last_hit_base, float(rec.hits[2][1]), 0.0001, "last_hit_base = the last hit's base")
	check(b.fake_hits() == 1 and c.fake_hits() == 1, "the arc hit all three")


func test_on_hit_dealt_without_a_base_uses_the_dealt_amount() -> void:
	_player_world()
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var rec := RecordingBonuses.new()
	rec.player = p
	p.bonuses = rec
	var e := Fakes.spawn_enemy(world, Vector3(1, 0, 0))
	p.on_hit_dealt(7.0, e)
	check_eq(rec.hits[0][1], 7.0, "old callers: base = damage")
	check(rec.hits[0][3], "roll_procs defaults to first")
	p.on_hit_dealt(9.0, e, null, true, false, false, 4.0)
	check(rec.hits[1][1] == 4.0 and rec.hits[1][2] and not rec.hits[1][3], "base, crit, not first")
	check_eq(p.last_hit_base, 4.0, "last_hit_base")


func test_crit_forced_is_asked_without_rng_draws() -> void:
	_player_world()
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var rec := RecordingBonuses.new()
	rec.player = p
	rec.force_crits = true
	p.bonuses = rec
	var a := Fakes.spawn_enemy(world, Vector3(1.2, 0, 0))
	var b := Fakes.spawn_enemy(world, Vector3(1.2, 0, 0.5))
	EnemyGrid.mark_dirty()
	var state := RunState.rng.state
	p.weapons[0].attack(a)
	check_eq(RunState.rng.state, state, "a forced crit draws nothing")
	check(a.fake_crit_log[0] and b.fake_crit_log[0], "every hit of the arc crits")
	check_eq(rec.crit_asks, [a, b] as Array[Node3D], "asked per enemy of the arc")
	# A banked forced crit (Vanish) is used first: the bonuses are not asked.
	rec.crit_asks.clear()
	p.forced_crits = 1
	p.weapons[0].riposte(a)
	check(rec.crit_asks.is_empty(), "consume_forced_crit first (judge B15)")
	check_eq(p.forced_crits, 0, "the banked crit was used")
	p.weapons[0].riposte(a)
	check_eq(rec.crit_asks, [a] as Array[Node3D], "riposte asks for its target")
	# Projectiles ask for the aimed enemy.
	var m := Fakes.spawn_player(world, 1, &"mage", Vector3(-6, 0, 0))
	var mrec := RecordingBonuses.new()
	mrec.player = m
	m.bonuses = mrec
	m.weapons[0].attack(a)
	check_eq(mrec.crit_asks, [a] as Array[Node3D], "the aimed enemy")


func test_after_wave_start_runs_after_the_resource_reset() -> void:
	_player_world()
	var p := Fakes.spawn_player(world, 0, &"warrior")
	var order: Array[String] = []
	var procs := RecordingProcs.new()
	nodes.append(procs)
	procs.player = p
	procs.order = order
	p.procs = procs
	var rec := RecordingBonuses.new()
	rec.player = p
	rec.order = order
	p.bonuses = rec
	var rage := p.abilities.primary_resource()
	rage.set_value(60.0)
	p.begin_wave()
	check_eq(procs.resource_at_start, rage.data.start_value, "the class resource was reset before")
	check_eq(order, ["procs.after_wave_start", "bonuses.begin_wave"] as Array[String], "then the scripts")


func test_avoided_hits_and_damage_taken_hooks() -> void:
	_player_world()
	var p := Fakes.spawn_player(world, 0, &"warrior")
	p.stats.set_source(&"test", {Stats.DODGE: 60.0, Stats.STAMINA: 100.0})
	p.hp = p.max_hp()
	var rec := AvoidBonuses.new()
	rec.player = p
	p.bonuses = rec
	var dodged := 0
	for i in 40:
		p.invulnerable_left = 0.0
		var before := p.hp
		p.take_damage(1.0)
		if p.hp == before:
			dodged += 1
	check(dodged > 0, "some hits dodged")
	check_eq(rec.kinds.count(&"dodge"), dodged, "every dodge reported")
	check_eq(rec.kinds.size(), dodged, "nothing else avoided")
	check_eq(rec.taken, 40 - dodged, "every landed hit reported")
	# Blocks (partial ones too) are reported and still land.
	var pal := Fakes.spawn_player(world, 1, &"paladin", Vector3(4, 0, 0))
	pal.stats.set_source(&"test", {Stats.BLOCK_CHANCE: 40.0, Stats.STAMINA: 100.0})
	pal.hp = pal.max_hp()
	var prec := AvoidBonuses.new()
	prec.player = pal
	pal.bonuses = prec
	for i in 40:
		pal.invulnerable_left = 0.0
		pal.take_damage(2.0)
	var blocks := prec.kinds.count(&"block")
	check(blocks > 0, "some hits blocked")
	check_eq(prec.taken + prec.kinds.count(&"dodge") + prec.kinds.count(&"parry"), 40, "blocked hits still land")


## The hand-off APIs T-CORE-B implemented (AbilityRunner.cooldown_left, ClassResource.set_bonus).
func test_cooldown_left_and_class_resource_bonus() -> void:
	_player_world()
	var p := Fakes.spawn_player(world, 0, &"mage")
	var blink := Db.get_ability(&"blink")
	check_eq(p.abilities.cooldown_left(blink), 0.0, "nothing running")
	p.abilities.set_cooldown(blink, 4.0)
	check_eq(p.abilities.cooldown_left(blink), 4.0, "the running recharge")
	p.abilities.set_cooldown(blink, 0.0)
	check_eq(p.abilities.cooldown_left(blink), 0.0, "reset")
	var mana := p.abilities.primary_resource()
	var bonus := {"max_value_add": 20.0}
	mana.set_bonus(bonus)
	bonus["max_value_add"] = 5.0
	check_eq(mana.bonus, {"max_value_add": 20.0}, "a copy is stored")


# --- Enemy -------------------------------------------------------------------------------------

func test_enemy_release_taunt_only_frees_that_target() -> void:
	_player_world()
	var data := EFakes.enemy_data()
	var e1 := EFakes.spawn_enemy(world, data, Vector3(3, 0, 0))
	var e2 := EFakes.spawn_enemy(world, data, Vector3(-3, 0, 0))
	var hero := Node3D.new()
	var pet := Node3D.new()
	world.add_child(hero)
	world.add_child(pet)
	e1.apply_taunt(hero, 5.0)
	e2.apply_taunt(pet, 5.0)
	e1.release_taunt(pet)
	check(e1.taunt_target == hero and e1.taunt_left > 0.0, "a taunt to someone else keeps running")
	e1.release_taunt(hero)
	check(e1.taunt_target == null and e1.taunt_left == 0.0 and not e1.is_taunted(), "released")
	check(e2.taunt_target == pet and e2.is_taunted(), "the other enemy keeps its taunt")
	e2.release_taunt(null)
	check(e2.is_taunted(), "null releases nothing")


func test_enemy_setup_on_a_subclass() -> void:
	_player_world()
	var data := EFakes.enemy_data()
	var e := Enemy.setup(ThinkingEnemy.new(), data, 3) as ThinkingEnemy
	check(e != null, "the subclass instance comes back")
	check_eq(e.data, data, "data")
	check_eq(e.wave, 3, "wave")
	check_near(e.max_hp, data.hp_at_wave(3) * RunState.coop_hp_mult(), 0.0001, "HP growth")
	check(e.is_in_group(&"enemies") and e.get_node_or_null(^"Model") != null and e.get_node_or_null(^"Shape") != null,
		"group, model and shape")
	EFakes.arena_of(world).entities.add_child(e)
	e.global_position = Vector3.ZERO
	var player := EFakes.spawn_player(world, Vector3(0.5, 0, 0))
	var normal := EFakes.spawn_enemy(world, data, Vector3(0.9, 0, 0))
	Enemy.invalidate_player_cache()
	e._physics_process(DT)
	check_eq(e.thoughts, 1, "its own AI step")
	check(player.fake_hits.is_empty(), "no contact damage")
	normal._physics_process(DT)
	check_eq(player.fake_hits.size(), 1, "a normal enemy still hits")
	e.apply_stun(1.0)
	e._physics_process(DT)
	check_eq(e.thoughts, 1, "no AI step while stunned")
	check(normal.deals_contact_damage(), "enemies deal contact damage")


func test_enemy_heal_and_healing_reduction() -> void:
	_player_world()
	var e := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3(2, 0, 0))
	e.hp = 4.0
	e.max_hp = 10.0
	check_eq(e.heal(3.0), 3.0, "heals")
	check_eq(e.hp, 7.0, "hp")
	e.apply_healing_reduction(50.0, 2.0)
	check_eq(e.healing_taken_mult(), 0.5, "50% less")
	check_eq(e.heal(4.0), 2.0, "half of it")
	check_eq(e.heal(5.0), 1.0, "never above max HP")
	check_eq(e.heal(5.0), 0.0, "full")
	e.apply_healing_reduction(30.0, 5.0)
	check(e.heal_reduction_pct == 50.0 and e.heal_reduction_left == 2.0, "a weaker one is ignored")
	e.apply_healing_reduction(50.0, 4.0)
	check_eq(e.heal_reduction_left, 4.0, "an equal one extends")
	e.apply_healing_reduction(80.0, 1.0)
	check(e.heal_reduction_pct == 80.0 and e.heal_reduction_left == 1.0, "a stronger one replaces")
	for i in 70:
		e._physics_process(DT)
	check_eq(e.healing_taken_mult(), 1.0, "runs out")
	check_eq(e.heal_reduction_pct, 0.0, "cleared")
	e.take_damage(999.0)
	check_eq(e.heal(5.0), 0.0, "the dead do not heal")


# --- Loot --------------------------------------------------------------------------------------

func test_drop_special_ignores_the_cap() -> void:
	PlayerManager.add_bot(&"warrior", 1)
	PlayerManager.add_bot(&"mage", 2)
	PlayerManager.add_bot(&"warrior", 3)
	RunState.start_run(3, 77)
	RunState.set_wave(6)
	check_eq(LootDrops.team_classes(), [Db.get_class_data(&"warrior"), Db.get_class_data(&"mage")] as Array[ClassData],
		"distinct classes, slot order")
	_player_world()
	var e := EFakes.spawn_enemy(world, EFakes.enemy_data(), Vector3(2, 0, 3))
	var bag := LootDrops.drop_special(ItemGenerator.Source.ELITE, e, null)
	check(bag != null and bag.item != null, "a bag")
	check_eq(RunState.loot_drops_this_wave, 0, "not counted")
	check(bag.item.looted and bag.item.rarity >= Items.Rarity.RARE, "looted, Rare+ (elite source)")
	check(bag.global_position.distance_to(Vector3(2, 0, 3)) < 0.01, "at the enemy")
	RunState.loot_drops_this_wave = LootDrops.max_drops_per_wave()
	check(LootDrops.drop_special(ItemGenerator.Source.GOBLIN, e, null) != null, "drops at the cap too")
	check_eq(RunState.loot_drops_this_wave, LootDrops.max_drops_per_wave(), "cap counter untouched")
	RunState.loot_drops_this_wave = 0
	check(LootDrops.drop_item(LootDrops.generate_item(null), Vector3.ZERO, e) != null, "a normal drop")
	check_eq(RunState.loot_drops_this_wave, 1, "counts")


# --- RunState ----------------------------------------------------------------------------------

func test_spend_log_and_wants() -> void:
	RunState.spent.connect(_on_spent)
	RunState.add_gold(50)
	RunState.set_wave(3)
	check(RunState.try_spend_for(20, 1, &"shop", "Rare Dagger"), "paid")
	check_eq(RunState.gold, 30, "gold")
	check_eq(RunState.gold_spent, 20, "gold_spent")
	check_eq(RunState.spend_log, [{"slot": 1, "kind": &"shop", "label": "Rare Dagger", "amount": 20, "wave": 3}] as Array[Dictionary],
		"logged")
	check_eq(spent_entries.size(), 1, "spent signal")
	check(not RunState.try_spend_for(40, 0, &"trainer", "Fireball Rank III"), "too poor")
	check(RunState.spend_log.size() == 1 and RunState.gold == 30 and spent_entries.size() == 1, "nothing logged")
	check(RunState.try_spend(5), "the plain spend stays")
	check_eq(RunState.spend_log.size(), 1, "and is not logged")
	RunState.begin_spend_round()
	check(RunState.spend_log.is_empty(), "a new round")
	check_eq(RunState.gold_spent, 20, "the run total stays")
	var changes := [0]
	var count := func() -> void: changes[0] += 1
	RunState.wants_changed.connect(count)
	check(RunState.toggle_want(1, "trainer:fireball", "Fireball Rank III", 45), "wanted")
	check(RunState.has_want(1, "trainer:fireball") and not RunState.has_want(0, "trainer:fireball"), "per slot")
	check_eq(RunState.wants[0], {"slot": 1, "key": "trainer:fireball", "label": "Fireball Rank III", "price": 45}, "entry")
	check(not RunState.toggle_want(1, "trainer:fireball", "Fireball Rank III", 45), "toggled off")
	RunState.toggle_want(2, "trainer:blink", "Blink Rank II", 30)
	RunState.clear_want(2, "trainer:nope")
	check_eq(RunState.wants.size(), 1, "clearing another key does nothing")
	RunState.clear_want(2, "trainer:blink")
	check(RunState.wants.is_empty(), "cleared")
	RunState.toggle_want(0, "trainer:charge", "Charge Rank II", 25)
	RunState.begin_spend_round()
	check(RunState.wants.is_empty(), "a new round clears the wants")
	check_eq(changes[0], 6, "wants_changed on every change")
	RunState.wants_changed.disconnect(count)


func test_spenders_log_who_and_what() -> void:
	_player_world()
	RunState.spent.connect(_on_spent)
	var p := Fakes.spawn_player(world, 2, &"warrior")
	RunState.add_gold(1000)
	check(Trainer.try_buy_rank(p, &"charge"), "trained")
	var e := RunState.spend_log.back() as Dictionary
	check(e["slot"] == 2 and e["kind"] == &"trainer" and e["label"] == "Charge Rank II", "trainer: %s" % str(e))
	check_eq(e["amount"], AbilityRanks.trainer_price(1, RunState.wave), "the price")


func test_start_run_resets_counters_statics_and_serial() -> void:
	EliteAffixes.rate_mult = 3.0
	GoblinSpawner.chance_override = 0.5
	RunState.elites_spawned = 2
	RunState.elites_killed = 1
	RunState.goblins_spawned = 1
	RunState.goblins_killed = 1
	RunState.goblins_escaped = 1
	RunState.weapons_forged = 3
	RunState.talent_resets = 2
	RunState.gold_spent = 99
	RunState.spend_log.append({"slot": 0})
	RunState.wants.append({"slot": 0, "key": "x"})
	var serial := RunState.run_serial
	RunState.start_run(2, 5)
	check_eq(RunState.run_serial, serial + 1, "run_serial bumped")
	check_eq(EliteAffixes.rate_mult, 1.0, "elite rate reset")
	check_eq(GoblinSpawner.chance_override, -1.0, "goblin override reset")
	for key: String in ["elites_spawned", "elites_killed", "goblins_spawned", "goblins_killed", "goblins_escaped",
			"weapons_forged", "talent_resets", "gold_spent"]:
		check_eq(RunState.get(key), 0, key)
	check(RunState.spend_log.is_empty() and RunState.wants.is_empty(), "log and wants")


func test_start_level_and_special_kills() -> void:
	RunState.set_start_level(12)
	check(RunState.level == 12 and RunState.xp == 0 and RunState.pending_level_ups == 0, "level only")
	check_eq(RunState.talent_points_earned(), 3, "3 talent points at 12")
	RunState.set_start_level(-4)
	check_eq(RunState.level, RunState.START_LEVEL, "never below the start level")
	RunState.special_killed.connect(_on_special_killed)
	RunState.record_special_kill(&"elite", 2)
	RunState.record_special_kill(&"goblin", -1)
	RunState.record_special_kill(&"boss", 0)
	check(RunState.elites_killed == 1 and RunState.goblins_killed == 1, "counted")
	check_eq(specials, [[&"elite", 2], [&"goblin", -1], [&"boss", 0]] as Array[Array], "signalled")


# --- Launch options and Main -------------------------------------------------------------------

func test_launch_flags_parse() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--goblin-chance=0.4", "--elite-mult=2.5", "--start-level=22",
		"--panel-tab=talents"]))
	check(is_equal_approx(o.goblin_chance, 0.4) and is_equal_approx(o.elite_mult, 2.5), "chances")
	check_eq(o.start_level, 22, "start level")
	check_eq(o.panel_tab, "talents", "--panel-tab=talents")
	check(o.unknown.is_empty(), "all understood")
	var d := LaunchOptions.parse(PackedStringArray())
	check(d.goblin_chance == -1.0 and d.elite_mult == 1.0 and d.start_level == 1 and d.panel_tab == "", "defaults")
	var c := LaunchOptions.parse(PackedStringArray(["--goblin-chance=3", "--elite-mult=-2", "--start-level=0",
		"--panel-tab=shop"]))
	check(c.goblin_chance == 1.0 and c.elite_mult == 0.0 and c.start_level == 1, "clamped")
	check(c.panel_tab == "" and "--panel-tab=shop" in c.unknown, "an unknown tab is reported")
	check_eq(LaunchOptions.parse(PackedStringArray(["--panel-tab=trainer"])).panel_tab, "trainer", "trainer")


func test_main_applies_the_m5_options_and_wires_the_spawner() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--start-level=12", "--elite-mult=3", "--goblin-chance=0.5",
		"--panel-tab=talents"]))
	main = Main.create(o)
	tree.root.add_child(main)
	PlayerManager.add_bot(&"warrior", 1)
	PlayerManager.add_bot(&"mage", 2)
	main.start_run()
	check_eq(EliteAffixes.rate_mult, 3.0, "--elite-mult")
	check_eq(GoblinSpawner.chance_override, 0.5, "--goblin-chance")
	check_eq(PlayerPanel.debug_start_tab, "talents", "--panel-tab")
	check_eq(RunState.level, 12, "--start-level")
	check_eq(main.players[0].talents.points_earned(), 3, "the heroes have the talent points")
	check(main.goblin_spawner != null and main.goblin_spawner.get_parent() == main.wave_director, "spawner under the director")
	check_eq(main.goblin_spawner.director, main.wave_director, "knows its director")
	main.goblin_spawner.announced.emit("A Loot Goblin appeared!", UiTheme.GOLD)
	check_eq(main.hud.banner_label.text, "A Loot Goblin appeared!", "announcements become banners")
	var data := main.smoke_result("completed")
	for key in ["elites_spawned", "elites_killed", "goblins_spawned", "goblins_killed", "goblins_escaped",
			"weapons_forged", "talent_points_spent", "talent_resets", "set_bonuses", "gold_spent"]:
		check(data.has(key), "SMOKE_RESULT has %s" % key)
	check_eq(data["talent_points_spent"], 0, "no talents spent")
	main.start_run()
	check_eq(EliteAffixes.rate_mult, 3.0, "a new run applies the options again")


# --- UI wiring ---------------------------------------------------------------------------------

func test_player_panel_forge_entry_and_talents_tab() -> void:
	var slot := PlayerManager.join(ScriptedInput.new("m5:0"), Db.get_class_data(&"warrior"))
	var hero := Player.create(slot)
	nodes.append(hero)
	var panel := PlayerPanel.create(slot)
	nodes.append(panel)
	tree.root.add_child(panel)
	panel.set_input_focus(true)
	panel.select_equip_slot(Items.EquipSlot.MAIN_HAND)
	check(panel.tooltip.viewer_equipment == hero.equipment, "the tooltip knows the viewer's equipment")
	panel.open_menu()
	check_eq(Array(panel.menu_labels()), ["Unequip", "Forge", "Cancel"], "Forge after Unequip")
	# The entry follows Forge.blocked_reason: a lone starting sword has no partner.
	var sword := hero.equipment.get_item(Items.EquipSlot.MAIN_HAND)
	var reason := Forge.blocked_reason(hero.equipment, sword)
	check(reason != "", "a lone starting sword cannot be forged")
	check_eq(panel.menu_entry_enabled("Forge"), reason == "", "enabled exactly when Forge allows it")
	panel.select_menu_entry("Forge")
	var input := slot.input as ScriptedInput
	input.press(PlayerInput.Pad.A)
	input.poll(DT)
	panel.handle_input(input)
	input.release(PlayerInput.Pad.A)
	input.poll(0.0)
	check_eq(panel.last_message, reason, "the reason is shown")
	panel.close_menu()
	var dagger := ItemGenerator.generate_weapon(Db.get_weapon(&"dagger"), Items.Rarity.COMMON, 1, false, RunState.rng)
	hero.equipment.add_to_backpack(dagger)
	var helm := ItemInstance.new()
	helm.slot_type = Items.SlotType.HEAD
	helm.armor_type = ClassData.ArmorType.PLATE
	helm.display_name = "Helm"
	hero.equipment.add_to_backpack(helm)
	panel.refresh()
	panel.select_backpack(hero.equipment.backpack.find(dagger))
	panel.open_menu()
	var labels := Array(panel.menu_labels())
	check(labels.find("Forge") == labels.find("Equip") + 1, "Forge after Equip: %s" % str(labels))
	panel.close_menu()
	panel.select_backpack(hero.equipment.backpack.find(helm))
	panel.open_menu()
	check(not Array(panel.menu_labels()).has("Forge"), "only weapons")
	panel.close_menu()
	panel.set_tab(PlayerPanel.TALENTS_TAB)
	check(panel.active_tab == PlayerPanel.TALENTS_TAB and panel.talents.visible, "the Talents tab opens")
	check(PlayerPanel.LOCKED_TABS.is_empty(), "no locked tabs")


func test_debug_start_tab_opens_p1_on_talents_once() -> void:
	PlayerPanel.debug_start_tab = "talents"
	var s1 := PlayerManager.join(ScriptedInput.new("m5:1"), Db.get_class_data(&"mage"))
	var s2 := PlayerManager.join(ScriptedInput.new("m5:2"), Db.get_class_data(&"rogue"))
	nodes.append(Player.create(s1))
	nodes.append(Player.create(s2))
	var p1 := PlayerPanel.create(s1)
	var p2 := PlayerPanel.create(s2)
	nodes.append(p1)
	nodes.append(p2)
	tree.root.add_child(p1)
	tree.root.add_child(p2)
	check_eq(p1.active_tab, PlayerPanel.TALENTS_TAB, "P1 opens on Talents")
	check_eq(p2.active_tab, PlayerPanel.CHARACTER_TAB, "only P1")
	p1.set_tab(PlayerPanel.CHARACTER_TAB)
	p1.refresh()
	check_eq(p1.active_tab, PlayerPanel.CHARACTER_TAB, "once")


## Frozen pieces of the classes P0 introduced (TalentEffect, EliteAffixes, PlayerBonuses ...).
func test_talent_effect_base_and_constants() -> void:
	var effect := TalentEffect.new()
	effect.setup(null, 2, {"every": 5, "name": "x"})
	check(effect.rank == 2 and effect.num("every") == 5.0 and effect.num("name", 1.0) == 1.0, "TalentEffect basics")
	check(effect.damage_mult(null, &"fire", &"weapon") == 1.0 and not effect.crit_forced(null), "neutral hooks")
	check_eq(EliteAffixes.ALL.size(), 4, "four affixes")
	check(EliteAffixes.expected_count(EliteAffixes.FIRST_WAVE - 1, 4) == 0.0, "no elites before FIRST_WAVE")
	check_eq(PlayerBonuses.SOURCE_TALENTS, &"talents", "talent source")
	check_eq(PlayerBonuses.SOURCE_SETS, &"set_bonus", "set source")
