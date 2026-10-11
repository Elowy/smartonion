extends TestCase
## The talent content contract (M5, T-CORE-A; talent_vocabulary.md §1, §8.3): every tree in Db
## must pass [method tree_problems] – shape (GDD 7.2: tiers 2 / 2 / talent + modifier / 2 /
## capstone, 22 points), ids unique and prefixed "<class>_<tree>_", prerequisites in the same
## tree and a lower tier, every effect valid for the tree's class (BonusVocabulary.validate),
## every description placeholder filled at every rank, modifiers naming an existing ability of
## the class, icons that resolve, and scripts that load, extend TalentEffect and are named
## <Class><Tree><Name> after their file. The Wave-2 class trees are checked by the same test.
## The checker itself is exercised on broken fixtures (so a silent checker cannot pass).

const Probe := preload("res://tests/talent_effect_probe.gd")
const TREES_PER_CLASS := 3
const POINTS_PER_TREE := 22
## Tier -> [kind, max_rank, column] of the talents it must hold (talent_vocabulary §1.1).
const SHAPE := {
	1: [[TalentData.Kind.TALENT, 3, 0], [TalentData.Kind.TALENT, 3, 1]],
	2: [[TalentData.Kind.TALENT, 3, 0], [TalentData.Kind.TALENT, 3, 1]],
	3: [[TalentData.Kind.TALENT, 2, 0], [TalentData.Kind.MODIFIER, 1, 1]],
	4: [[TalentData.Kind.TALENT, 3, 0], [TalentData.Kind.TALENT, 3, 1]],
	5: [[TalentData.Kind.CAPSTONE, 1, -1]],
}


# --- Db content --------------------------------------------------------------------------------

func test_every_tree_in_db_passes_the_contract() -> void:
	check(not Db.talent_trees.is_empty(), "at least the Arms reference tree is in Db")
	for id in Db.talent_trees:
		for problem in tree_problems(Db.talent_trees[id]):
			failures.append("%s: %s" % [id, problem])


func test_talent_ids_are_global_and_trees_fit_their_class() -> void:
	var by_class: Dictionary[StringName, Array] = {}
	for id in Db.talent_trees:
		var tree_data := Db.talent_trees[id]
		check_eq(Db.get_talent_tree(id), tree_data, "lookup %s" % id)
		var list: Array = by_class.get(tree_data.class_id, [])
		list.append(tree_data)
		by_class[tree_data.class_id] = list
		for t in tree_data.talents:
			if t != null:
				check(Db.get_talent(t.id) == t, "%s is registered once, for its own tree" % t.id)
	for class_id in by_class:
		var trees: Array = by_class[class_id]
		check(trees.size() <= TREES_PER_CLASS, "%s: at most %d trees" % [class_id, TREES_PER_CLASS])
		var indexes := {}
		for tree_data: TalentTreeData in trees:
			check(not indexes.has(tree_data.index), "%s: tree index %d used once" % [class_id, tree_data.index])
			indexes[tree_data.index] = true
		var ordered := Db.talent_trees_for(class_id)
		check_eq(ordered.size(), trees.size(), "%s: talent_trees_for lists them all" % class_id)
		for i in ordered.size() - 1:
			check(ordered[i].index < ordered[i + 1].index, "%s: tab order by index" % class_id)


func test_arms_is_the_warrior_reference_tree() -> void:
	var arms := Db.get_talent_tree(&"warrior_arms")
	check(arms != null, "warrior_arms in Db")
	if arms == null:
		return
	check(arms.class_id == &"warrior" and arms.index == 0 and arms.display_name == "Arms", "Warrior tree 1")
	check_eq(arms.talents.size(), 9, "nine talents")
	var ids: Array[StringName] = []
	for t in arms.talents:
		ids.append(t.id)
	check_eq(ids, [&"warrior_arms_deflection", &"warrior_arms_tactical_mastery", &"warrior_arms_improved_charge",
		&"warrior_arms_deep_wounds", &"warrior_arms_two_handed_specialization", &"warrior_arms_sweeping_blows",
		&"warrior_arms_impale", &"warrior_arms_sudden_death", &"warrior_arms_mortal_strike"] as Array[StringName], "ids")
	check_eq(arms.get_talent(&"warrior_arms_impale").prerequisite, &"warrior_arms_deep_wounds", "Impale needs Deep Wounds")
	check_eq(arms.get_talent(&"warrior_arms_sweeping_blows").ability, &"whirlwind", "the modifier changes Whirlwind")
	check(arms.get_talent(&"warrior_arms_mortal_strike").is_capstone(), "Mortal Strike is the capstone")
	check_eq(arms.get_talent(&"warrior_arms_deflection").text_for_rank(3),
		"Increases your chance to dodge attacks by 6%.", "rank text")


# --- The checker on broken fixtures ------------------------------------------------------------

func test_checker_accepts_a_valid_fixture() -> void:
	check_eq(tree_problems(_valid_tree()), [] as Array[String], "a clean fixture tree")


func test_checker_reports_shape_problems() -> void:
	var t := _valid_tree()
	t.talents.remove_at(1)
	_expect(t, "tier 1", "a missing tier-1 talent")
	t = _valid_tree()
	t.talents[0].max_rank = 2
	_expect(t, "22 points", "wrong point total")
	t = _valid_tree()
	t.talents[5].kind = TalentData.Kind.TALENT
	_expect(t, "tier 3", "no modifier in tier 3")
	t = _valid_tree()
	t.talents[8].tier = 4
	_expect(t, "tier 5", "no capstone")
	t = _valid_tree()
	t.index = 3
	_expect(t, "index", "tree index out of range")


func test_checker_reports_id_and_prerequisite_problems() -> void:
	var t := _valid_tree()
	t.talents[2].id = &"warrior_other_x"
	_expect(t, "prefix", "an id without the tree prefix")
	t = _valid_tree()
	t.talents[3].id = t.talents[2].id
	_expect(t, "duplicate", "a duplicate id")
	t = _valid_tree()
	t.talents[6].prerequisite = &"warrior_zz_nowhere"
	_expect(t, "prerequisite", "an unknown prerequisite")
	t = _valid_tree()
	t.talents[2].prerequisite = t.talents[3].id
	_expect(t, "lower tier", "a prerequisite in the same tier")


func test_checker_reports_effect_text_and_icon_problems() -> void:
	var t := _valid_tree()
	t.talents[0].effects = [{"kind": "stats", "stats": {"critt": 1.0}}]
	_expect(t, "critt", "an invalid effect")
	t = _valid_tree()
	t.talents[0].effects = [{"kind": "ability", "match": {"id": "fireball"}, "mods": {"power_pct": 5.0}}]
	_expect(t, "mage", "another class's ability")
	t = _valid_tree()
	t.talents[0].effects = []
	_expect(t, "no effects", "a talent without effects")
	t = _valid_tree()
	t.talents[0].description = "Gain {dodge}% dodge and {nope} more."
	_expect(t, "placeholder", "an unresolved placeholder")
	t = _valid_tree()
	t.talents[5].ability = &"no_such_ability"
	_expect(t, "modifier", "a modifier without a real ability")
	t = _valid_tree()
	t.talents[5].ability = &"fireball"
	_expect(t, "modifier", "a modifier on another class's ability")
	t = _valid_tree()
	t.talents[1].icon = &"not_a_glyph"
	_expect(t, "icon", "an unknown icon")


func test_checker_reports_script_problems() -> void:
	var t := _valid_tree()
	t.talents[8].effects = [{"kind": "script", "script": "res://scenes/talents/warrior/zz_missing.gd"}]
	_expect(t, "load", "a missing script")
	t = _valid_tree()
	t.talents[8].effects = [{"kind": "script", "script": Probe.PATH}]
	_expect(t, "scenes/talents/warrior/", "a script outside the class folder")
	t = _valid_tree()
	_rename(t, "warrior_arms")
	t.talents[8].effects = [{"kind": "script", "script": "res://scenes/talents/warrior/arms_mortal_strike.gd"}]
	check_eq(tree_problems(t), [] as Array[String], "the real Mortal Strike script passes")
	_rename(t, "warrior_fury")
	_expect(t, "file name", "a script of another tree")


## Gives [param t] the id [param tree_id] (talent ids and prerequisites follow).
static func _rename(t: TalentTreeData, tree_id: String) -> void:
	var old := String(t.id) + "_"
	t.id = StringName(tree_id)
	for talent in t.talents:
		talent.id = StringName(String(talent.id).replace(old, tree_id + "_"))
		if talent.prerequisite != &"":
			talent.prerequisite = StringName(String(talent.prerequisite).replace(old, tree_id + "_"))


func _expect(t: TalentTreeData, needle: String, what: String) -> void:
	var problems := tree_problems(t)
	var found := false
	for p in problems:
		if needle in p:
			found = true
	check(found, "%s: expected a problem mentioning '%s', got %s" % [what, needle, problems])


## A clean fixture tree "warrior_zz" (stats effects only, a capstone without a script).
static func _valid_tree() -> TalentTreeData:
	var t := TalentTreeData.new()
	t.id = &"warrior_zz"
	t.class_id = &"warrior"
	t.display_name = "Fixture"
	t.index = 1
	t.description = "A clean fixture."
	t.icon = &"whirlwind"
	var layout: Array[Array] = [[1, 0, 3], [1, 1, 3], [2, 0, 3], [2, 1, 3], [3, 0, 2], [3, 1, 1], [4, 0, 3], [4, 1, 3], [5, 0, 1]]
	var list: Array[TalentData] = []
	for i in layout.size():
		var d := TalentData.new()
		d.id = StringName("warrior_zz_t%d" % i)
		d.display_name = "T%d" % i
		d.tier = layout[i][0]
		d.column = layout[i][1]
		d.max_rank = layout[i][2]
		d.kind = TalentData.Kind.TALENT
		d.description = "Gain {dodge}% dodge for {secs_fixed} sec."
		d.values = {"dodge": 1.0, "secs_fixed": 3.0}
		d.effects = [{"kind": "stats", "stats": {"dodge": 1.0}}]
		list.append(d)
	list[5].kind = TalentData.Kind.MODIFIER
	list[5].ability = &"whirlwind"
	list[5].effects = [{"kind": "ability", "match": {"id": "whirlwind"}, "mods": {"radius_add": 1.0}}]
	list[6].prerequisite = list[2].id
	list[8].kind = TalentData.Kind.CAPSTONE
	list[1].icon = &"crit"
	list[2].icon = &"charge"
	t.talents = list
	return t


# --- The contract ------------------------------------------------------------------------------

## Every problem of [param tree] (empty = it satisfies the talent content contract).
static func tree_problems(tree: TalentTreeData) -> Array[String]:
	var out: Array[String] = []
	if tree == null:
		out.append("null tree")
		return out
	var cls := tree.class_id
	if not Db.classes.has(cls):
		out.append("unknown class '%s'" % cls)
	if not String(tree.id).begins_with(String(cls) + "_"):
		out.append("tree id must start with '%s_'" % cls)
	if tree.index < 0 or tree.index >= TREES_PER_CLASS:
		out.append("tree index %d outside 0..%d" % [tree.index, TREES_PER_CLASS - 1])
	if tree.display_name.strip_edges() == "" or tree.description.strip_edges() == "":
		out.append("tree needs a display name and a description")
	if Db.get_ability(tree.icon) == null:
		out.append("tree icon '%s' is not an ability id" % tree.icon)
	_shape_problems(tree, out)
	var seen := {}
	for t in tree.talents:
		if t == null:
			out.append("null talent")
			continue
		if seen.has(t.id):
			out.append("duplicate talent id %s" % t.id)
		seen[t.id] = true
		_talent_problems(tree, t, out)
	return out


static func _shape_problems(tree: TalentTreeData, out: Array[String]) -> void:
	var points := 0
	for t in tree.talents:
		if t == null:
			continue
		points += t.max_rank
		if not SHAPE.has(t.tier):
			out.append("%s: tier %d outside 1..5" % [t.id, t.tier])
	if points != POINTS_PER_TREE:
		out.append("the tree holds %d points, not %d points" % [points, POINTS_PER_TREE])
	for tier: int in SHAPE:
		var want: Array = SHAPE[tier]
		var have := tree.talents_in_tier(tier)
		if have.size() != want.size():
			out.append("tier %d holds %d talents, not %d" % [tier, have.size(), want.size()])
			continue
		for i in want.size():
			var spec: Array = want[i]
			var t := have[i]
			if t.kind != spec[0] or t.max_rank != spec[1] or (spec[2] >= 0 and t.column != spec[2]):
				out.append("tier %d: %s must be %s max %d%s" % [tier, t.id, TalentData.Kind.keys()[spec[0]], spec[1],
					(" in column %d" % spec[2]) if spec[2] >= 0 else ""])


static func _talent_problems(tree: TalentTreeData, t: TalentData, out: Array[String]) -> void:
	var cls := tree.class_id
	if not String(t.id).begins_with(String(tree.id) + "_"):
		out.append("%s: id needs the tree prefix '%s_'" % [t.id, tree.id])
	if t.display_name.strip_edges() == "" or t.description.strip_edges() == "":
		out.append("%s: needs a display name and a description" % t.id)
	if t.prerequisite != &"":
		var pre := tree.get_talent(t.prerequisite)
		if pre == null:
			out.append("%s: prerequisite %s is not in the tree" % [t.id, t.prerequisite])
		elif pre.tier >= t.tier:
			out.append("%s: prerequisite %s must be in a lower tier" % [t.id, t.prerequisite])
	for key: Variant in t.values:
		if typeof(t.values[key]) not in [TYPE_INT, TYPE_FLOAT]:
			out.append("%s: value '%s' is not a number" % [t.id, key])
	for rank in range(1, maxi(1, t.max_rank) + 1):
		var text := t.text_for_rank(rank)
		if "{" in text or "}" in text:
			out.append("%s: unresolved placeholder at rank %d: %s" % [t.id, rank, text])
			break
	if t.kind == TalentData.Kind.MODIFIER:
		var a := Db.get_ability(t.ability)
		if a == null or (a.class_id != &"" and a.class_id != cls):
			out.append("%s: the modifier's ability '%s' is not a %s / general ability" % [t.id, t.ability, cls])
	if t.icon != &"" and Db.get_ability(t.icon) == null and t.icon not in Stats.ALL:
		out.append("%s: icon '%s' is neither an ability nor a stat id" % [t.id, t.icon])
	if t.effects.is_empty():
		out.append("%s: no effects" % t.id)
	for e in t.effects:
		var error := BonusVocabulary.validate(e, cls)
		if error != "":
			out.append("%s: %s" % [t.id, error])
		elif str(e.get("kind")) == "script":
			_script_problems(tree, t, String(e["script"]), out)


## A script entry: loads, extends TalentEffect, lives in scenes/talents/<class>/<tree>_<name>.gd
## and is named <Class><Tree><Name>.
static func _script_problems(tree: TalentTreeData, t: TalentData, path: String, out: Array[String]) -> void:
	var script: Script = load(path) as Script if ResourceLoader.exists(path) else null
	if script == null or not script.can_instantiate():
		out.append("%s: cannot load script %s" % [t.id, path])
		return
	var inst: Variant = script.new()
	if not (inst is TalentEffect):
		out.append("%s: %s does not extend TalentEffect" % [t.id, path])
		if inst is Object and not (inst is RefCounted):
			(inst as Object).free()
		return
	var folder := "res://scenes/talents/%s/" % tree.class_id
	if not path.begins_with(folder):
		out.append("%s: scripts live in %s, not %s" % [t.id, folder, path])
		return
	var short := String(tree.id).trim_prefix(String(tree.class_id) + "_")
	var base := path.get_file().get_basename()
	if not base.begins_with(short + "_"):
		out.append("%s: script file name %s must start with '%s_'" % [t.id, base, short])
	var expected := String(tree.class_id).to_pascal_case() + base.to_pascal_case()
	if script.get_global_name() != StringName(expected):
		out.append("%s: script class_name must be %s, not '%s'" % [t.id, expected, script.get_global_name()])
