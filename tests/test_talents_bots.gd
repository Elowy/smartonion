extends TestCase
## TalentBot (M5, T-CORE-A, architecture §2.2 / GDD 7.3): one point at a time, trees from
## slot_index % trees (wrapping), capstone > modifier > first addable by (tier, column); talents
## whose effects all need an unmet weapon / ability and modifiers on unslotted abilities are
## deferred until nothing else is addable anywhere (two passes); no resets, no RNG.

const Fakes := preload("res://tests/player_fakes.gd")
const EFakes := preload("res://tests/enemies_fakes.gd")

const ARMS_PATH: Array[StringName] = [
	&"warrior_arms_deflection", &"warrior_arms_deflection", &"warrior_arms_deflection",
	&"warrior_arms_tactical_mastery", &"warrior_arms_tactical_mastery", &"warrior_arms_tactical_mastery",
	&"warrior_arms_sweeping_blows",
	&"warrior_arms_improved_charge", &"warrior_arms_improved_charge", &"warrior_arms_improved_charge",
	&"warrior_arms_deep_wounds", &"warrior_arms_deep_wounds",
	&"warrior_arms_mortal_strike",
	&"warrior_arms_deep_wounds",
	&"warrior_arms_impale", &"warrior_arms_impale", &"warrior_arms_impale",
	&"warrior_arms_sudden_death", &"warrior_arms_sudden_death", &"warrior_arms_sudden_death",
	&"warrior_arms_two_handed_specialization", &"warrior_arms_two_handed_specialization",
]

var world: Node3D


func before_each() -> void:
	RunState.start_run(1, 99)
	world = EFakes.make_world(tree)


func after_each() -> void:
	EFakes.free_world(tree, world)
	world = null


## A warrior at team [param level] whose talents are [param trees] (Db's when empty).
func _hero(index: int, level: int, trees: Array[TalentTreeData] = []) -> Player:
	RunState.set_start_level(level)
	var p := Fakes.spawn_player(world, index, &"warrior", Vector3(index * 6.0, 0, 0))
	if not trees.is_empty():
		p.talents = TalentState.create(&"warrior", trees)
		p.talents.changed.connect(p._on_talents_changed)
	return p


static func _arms_only() -> Array[TalentTreeData]:
	var out: Array[TalentTreeData] = [Db.get_talent_tree(&"warrior_arms")]
	return out


## The ids [method TalentBot.next_talent] picks, point by point, until it finds nothing.
static func _path(p: Player, slot_index: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in 100:
		var t := TalentBot.next_talent(p, slot_index)
		if t == null or not p.talents.add(t.id):
			break
		out.append(t.id)
	return out


static func _talent(tree_id: String, name: String, tier: int, column: int, max_rank: int,
		kind: TalentData.Kind = TalentData.Kind.TALENT, effects: Array[Dictionary] = []) -> TalentData:
	var t := TalentData.new()
	t.id = StringName("%s_%s" % [tree_id, name])
	t.display_name = name
	t.tier = tier
	t.column = column
	t.max_rank = max_rank
	t.kind = kind
	t.effects = effects
	return t


## A full-shape warrior fixture tree; its modifier changes [param modifier_ability] and every
## talent carries [param effects].
static func _tree(id: String, index: int, modifier_ability: StringName, effects: Array[Dictionary] = []) -> TalentTreeData:
	var t := TalentTreeData.new()
	t.id = StringName(id)
	t.class_id = &"warrior"
	t.display_name = id
	t.index = index
	var mod := _talent(id, "m", 3, 1, 1, TalentData.Kind.MODIFIER, effects)
	mod.ability = modifier_ability
	var list: Array[TalentData] = [
		_talent(id, "a1", 1, 0, 3, TalentData.Kind.TALENT, effects), _talent(id, "b1", 1, 1, 3, TalentData.Kind.TALENT, effects),
		_talent(id, "a2", 2, 0, 3, TalentData.Kind.TALENT, effects), _talent(id, "b2", 2, 1, 3, TalentData.Kind.TALENT, effects),
		_talent(id, "a3", 3, 0, 2, TalentData.Kind.TALENT, effects), mod,
		_talent(id, "a4", 4, 0, 3, TalentData.Kind.TALENT, effects), _talent(id, "b4", 4, 1, 3, TalentData.Kind.TALENT, effects),
		_talent(id, "cap", 5, 0, 1, TalentData.Kind.CAPSTONE, effects),
	]
	t.talents = list
	return t


# --- The Arms bot path -------------------------------------------------------------------------

func test_arms_path_capstone_at_13_and_two_hander_deferred() -> void:
	var p := _hero(0, 31, _arms_only())
	check(p.main_hand != null and not p.main_hand.is_two_handed(), "a one-handed sword")
	var path := _path(p, 0)
	check_eq(path, ARMS_PATH, "Arms bot path (talents_warrior.md 5.4)")
	check_eq(path.find(&"warrior_arms_sweeping_blows"), 6, "the modifier is point 7")
	check_eq(path.find(&"warrior_arms_mortal_strike"), 12, "the capstone is point 13")
	var q := _hero(1, 31, _arms_only())
	check_eq(TalentBot.spend_all(q, 0), 22, "spend_all spends the same 22 points")
	check_eq(q.talents.ranks, p.talents.ranks, "same ranks as the step-by-step path")


func test_a_two_hander_takes_its_specialization_after_the_capstone() -> void:
	var p := _hero(0, 31, _arms_only())
	var axe := ItemInstance.from_weapon(Db.get_weapon(&"two_hand_axe"), Items.Rarity.COMMON, 1, false)
	p.equipment.add_to_backpack(axe)
	check(p.equipment.equip(axe), "two-hander")
	var path := _path(p, 0)
	check_eq(path.find(&"warrior_arms_mortal_strike"), 12, "capstone still at 13")
	check_eq(path.find(&"warrior_arms_two_handed_specialization"), 14, "Two-Hander Prowess at 15-16")
	check_eq(path.size(), 22, "the whole tree")


func test_spend_all_stops_when_nothing_is_addable() -> void:
	var p := _hero(0, 34, _arms_only())
	check_eq(p.talents.points_free(), 25, "25 points")
	check_eq(TalentBot.spend_all(p, 0), 22, "a full tree")
	check_eq(p.talents.points_free(), 3, "the rest stays free")
	check_eq(TalentBot.spend_all(p, 0), 0, "nothing more")


func test_nothing_to_spend() -> void:
	var p := _hero(0, 9, _arms_only())
	check_eq(TalentBot.spend_all(p, 0), 0, "below level 10")
	check(TalentBot.next_talent(p, 0) == null, "no pick")
	check_eq(TalentBot.spend_all(null, 0), 0, "no hero")
	RunState.set_start_level(12)
	check_eq(TalentBot.spend_all(p, 0), 3, "level 12: three points")


# --- Deferral and the two passes ---------------------------------------------------------------

func test_modifier_waits_for_its_ability() -> void:
	var trees: Array[TalentTreeData] = [_tree("warrior_zz", 0, &"execute")]
	var p := _hero(0, 31, trees)
	var path := _path(p, 0)
	check_eq(path.size(), 22, "all 22 points")
	check_eq(path.find(&"warrior_zz_cap"), 12, "capstone at 13")
	check_eq(path[21], &"warrior_zz_m", "the modifier on an unlearned ability comes last (pass 2)")
	var q := _hero(1, 31, [_tree("warrior_zz", 0, &"execute")] as Array[TalentTreeData])
	check(q.abilities.learn(Db.get_ability(&"execute")) >= 0, "learn Execute")
	check_eq(_path(q, 0).find(&"warrior_zz_m"), 6, "learned: the modifier is point 7")


func test_deferred_tree_waits_until_no_tree_offers_anything() -> void:
	var shield_only: Array[Dictionary] = [{"kind": "stats", "stats": {"block_chance": 2.0}, "requires": {"weapon": "shield"}}]
	var small := TalentTreeData.new()
	small.id = &"warrior_yy"
	small.class_id = &"warrior"
	small.index = 1
	var only: Array[TalentData] = [_talent("warrior_yy", "x", 1, 0, 3)]
	small.talents = only
	var trees: Array[TalentTreeData] = [_tree("warrior_zz", 0, &"whirlwind", shield_only), small]
	var p := _hero(0, 14, trees)
	var path := _path(p, 0)
	check_eq(path.slice(0, 3), [&"warrior_yy_x", &"warrior_yy_x", &"warrior_yy_x"] as Array[StringName],
		"pass 1 skips the shield tree for the next tree")
	check_eq(path.slice(3), [&"warrior_zz_a1", &"warrior_zz_a1"] as Array[StringName], "pass 2: deferred talents once nothing else is left")
	# With a shield the first tree is not deferred.
	var q := _hero(1, 14, [_tree("warrior_zz", 0, &"whirlwind", shield_only), small] as Array[TalentTreeData])
	var shield := ItemInstance.from_weapon(Db.get_weapon(&"shield"), Items.Rarity.COMMON, 1, false)
	q.equipment.add_to_backpack(shield)
	check(q.equipment.equip(shield), "shield")
	check_eq(_path(q, 0)[0], &"warrior_zz_a1", "shield: the first tree")


func test_is_deferred_rules() -> void:
	var p := _hero(0, 31)
	var none := _talent("warrior_zz", "none", 1, 0, 3)
	check(not TalentBot.is_deferred(p, none), "no effects: never deferred")
	var gated := _talent("warrior_zz", "g", 1, 0, 3, TalentData.Kind.TALENT,
		[{"kind": "stats", "stats": {"crit": 1.0}, "requires": {"weapon": "two_handed"}},
		{"kind": "stats", "stats": {"crit": 1.0}, "requires": {"knows": "execute"}}] as Array[Dictionary])
	check(TalentBot.is_deferred(p, gated), "every effect needs something missing")
	var mixed := _talent("warrior_zz", "x", 1, 0, 3, TalentData.Kind.TALENT,
		[{"kind": "stats", "stats": {"crit": 1.0}, "requires": {"weapon": "two_handed"}},
		{"kind": "stats", "stats": {"dodge": 1.0}}] as Array[Dictionary])
	check(not TalentBot.is_deferred(p, mixed), "one unconditional effect: not deferred")
	var cap := _talent("warrior_zz", "c", 5, 0, 1, TalentData.Kind.CAPSTONE,
		[{"kind": "stats", "stats": {"crit": 1.0}, "requires": {"weapon": "shield"}}] as Array[Dictionary])
	check(TalentBot.is_deferred(p, cap), "capstones defer by the same rule")
	var mod := _talent("warrior_zz", "m", 3, 1, 1, TalentData.Kind.MODIFIER)
	mod.ability = &"charge"
	check(not TalentBot.is_deferred(p, mod), "a core ability is always slotted")
	mod.ability = &"bladestorm"
	check(TalentBot.is_deferred(p, mod), "a modifier on an unlearned ability")
	p.abilities.learn(Db.get_ability(&"bladestorm"))
	check(not TalentBot.is_deferred(p, mod), "learned")
	var slot := p.abilities.learn(Db.get_ability(&"execute"))
	check(not TalentBot.is_deferred(p, gated), "one effect's condition met is enough")
	p.abilities.forget(slot)
	check(TalentBot.is_deferred(p, gated), "forgotten again")
	p.equip_weapons(Db.get_weapon(&"two_hand_axe"), null)
	check(not TalentBot.is_deferred(p, gated), "a two-hander meets the other one")


# --- Tree order, determinism -------------------------------------------------------------------

func test_slot_index_picks_the_first_tree_and_wraps() -> void:
	for slot_index in 4:
		var trees: Array[TalentTreeData] = [_tree("warrior_zz", 0, &"whirlwind"), _tree("warrior_yy", 1, &"whirlwind")]
		var p := _hero(slot_index, 10, trees)
		check_eq(TalentBot.spend_all(p, slot_index), 1, "one point")
		var expected := &"warrior_zz_a1" if slot_index % 2 == 0 else &"warrior_yy_a1"
		check_eq(p.talents.rank_of(expected), 1, "slot %d starts in tree %d" % [slot_index, slot_index % 2])


func test_bots_are_deterministic_draw_nothing_and_never_reset() -> void:
	var a := _hero(0, 25)
	var b := _hero(1, 25)
	RunState.add_gold(500)
	var gold := RunState.gold
	var state := RunState.rng.state
	var spent := TalentBot.spend_all(a, 0)
	check(spent > 0, "spent %d" % spent)
	check_eq(TalentBot.spend_all(b, 0), spent, "same count")
	check_eq(a.talents.ranks, b.talents.ranks, "same ranks for the same hero state")
	check_eq(RunState.rng.state, state, "no RNG")
	check_eq(RunState.gold, gold, "no gold spent")
	check(a.talents.resets == 0 and RunState.talent_resets == 0, "never resets")
	check_eq(a.bonuses.effects_of(PlayerBonuses.SOURCE_TALENTS).size(), a.talents.effects().size(), "the engine got the effects")
