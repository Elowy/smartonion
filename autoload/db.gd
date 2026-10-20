extends Node
## Autoload "Db": loads all data resources from res://data/ at startup.
## Content is data-driven – adding a .tres file to the right folder adds it to the game.

const CLASS_DIR := "res://data/classes/"
const WEAPON_DIR := "res://data/weapons/"
const ENEMY_DIR := "res://data/enemies/"
const ITEM_BASE_DIR := "res://data/item_bases/"
const AFFIX_DIR := "res://data/affixes/"
const ENCHANT_DIR := "res://data/enchants/"
const UNIQUE_DIR := "res://data/uniques/"
const ABILITY_DIR := "res://data/abilities/"
## One subfolder per class: data/talents/<class>/<tree>.tres (TalentTreeData, M5).
const TALENT_DIR := "res://data/talents/"
## data/sets/<set_id>.tres (SetData, M5).
const SET_DIR := "res://data/sets/"
## data/bosses/<boss_id>.tres (BossData, M6: Lich Commander Morvain, Vor'thalax).
const BOSS_DIR := "res://data/bosses/"
## data/consumables/<id>.tres (ConsumableData, M6: the seven flasks, elixirs and foods).
const CONSUMABLE_DIR := "res://data/consumables/"
## data/artifacts/<id>.tres (ArtifactData, M6 ARTIFACTS: one weapon per class).
const ARTIFACT_DIR := "res://data/artifacts/"
## data/environments/<id>.tres (EnvironmentData, M6b: the arena environments; ENV package).
const ENVIRONMENT_DIR := "res://data/environments/"
## Roll order of the environments; any extra one is appended alphabetically.
const ENVIRONMENT_ORDER: Array[StringName] = [&"forest_ruin", &"cemetery", &"swamp", &"volcano", &"ice_cave"]
## data/shrines/<id>.tres (ShrineData, M6b: the six shrines of the break's shrine vote).
const SHRINE_DIR := "res://data/shrines/"
## Pool order of the shrines; any extra one is appended alphabetically.
const SHRINE_ORDER: Array[StringName] = [&"greed", &"haste", &"learning", &"blood", &"fortune", &"gambler"]
## data/unlocks/<id>.tres (UnlockGateData, M9: content the main profile has to unlock before it is offered).
const UNLOCK_DIR := "res://data/unlocks/"
## data/achievements/<id>.tres (AchievementData, M9).
const ACHIEVEMENT_DIR := "res://data/achievements/"
## The Class Level curve and reward list (ClassLevelTable, M9 LEVELS) and one path per class
## (data/meta/class_paths/<class>.tres, ClassPathData: locked abilities, capstone order, alternative weapon ...).
const CLASS_LEVELS_PATH := "res://data/meta/class_levels.tres"
const CLASS_PATH_DIR := "res://data/meta/class_paths/"
## Lobby order of the classes; any extra class is appended alphabetically. An id without a
## class resource (yet) is skipped, so the order may name classes before their data exists (the M8
## Hunter and Shaman); the default 4-bot party is the first four ids that exist.
const CLASS_ORDER: Array[StringName] = [&"warrior", &"mage", &"paladin", &"rogue", &"warlock", &"hunter", &"shaman"]

var classes: Dictionary[StringName, ClassData] = {}
var weapons: Dictionary[StringName, WeaponData] = {}
var enemies: Dictionary[StringName, EnemyData] = {}
var item_bases: Dictionary[StringName, ItemBase] = {}
var affixes: Dictionary[StringName, AffixData] = {}
var enchants: Dictionary[StringName, EnchantData] = {}
var uniques: Dictionary[StringName, UniqueItemData] = {}
## Every ability (core ones too), by id, in file order.
var abilities: Dictionary[StringName, AbilityData] = {}
## Every talent tree, by id (M5).
var talent_trees: Dictionary[StringName, TalentTreeData] = {}
## Every talent of every tree, by id (ids are global; a duplicate is an error).
var talents: Dictionary[StringName, TalentData] = {}
## Every tier set, by id (M5).
var sets: Dictionary[StringName, SetData] = {}
## Every boss, by id (M6). Separate from [member enemies]: the wave director's random pool
## (eligible_enemies) never sees a boss.
var bosses: Dictionary[StringName, BossData] = {}
## Every class Artifact, by id (M6). Separate from [member uniques]: the normal item pools
## never see them (LootDrops.roll_artifact / ItemGenerator.generate_artifact make them).
var artifacts: Dictionary[StringName, ArtifactData] = {}
## Every shop consumable, by id (M6).
var consumables: Dictionary[StringName, ConsumableData] = {}
## Every arena environment, by id (M6b).
var environments: Dictionary[StringName, EnvironmentData] = {}
## The environment ids in ENVIRONMENT_ORDER (extras alphabetically): the order of the roll reel.
var environment_ids: Array[StringName] = []
## Every shrine, by id (M6b), and the ids in SHRINE_ORDER (extras alphabetically): the roll's pool order.
var shrines: Dictionary[StringName, ShrineData] = {}
var shrine_ids: Array[StringName] = []
var class_ids: Array[StringName] = []
## Every unlock gate (M9), by UnlockGateData.key (kind/id): the content the profile has to unlock. Content without a
## gate is available from the start. Filled by [method reload]; [method add_unlock_gate] adds one in code.
var unlock_gates: Dictionary[StringName, UnlockGateData] = {}
## Every achievement (M9), by id, in file order.
var achievements: Dictionary[StringName, AchievementData] = {}
## The Class Level curve and reward list (M9 LEVELS); null only when the file is missing (ClassLevels then falls
## back to a bare table with no rewards).
var class_levels: ClassLevelTable
## Every class's level path (M9 LEVELS), by class id.
var class_paths: Dictionary[StringName, ClassPathData] = {}


func _ready() -> void:
	reload()


func reload() -> void:
	classes.clear()
	weapons.clear()
	enemies.clear()
	for res in _load_dir(CLASS_DIR):
		if res is ClassData:
			classes[res.id] = res
	for res in _load_dir(WEAPON_DIR):
		if res is WeaponData:
			weapons[res.id] = res
	for res in _load_dir(ENEMY_DIR):
		if res is EnemyData:
			enemies[res.id] = res
	item_bases.clear()
	affixes.clear()
	enchants.clear()
	uniques.clear()
	for res in _load_dir(ITEM_BASE_DIR):
		if res is ItemBase:
			item_bases[res.id] = res
	for res in _load_dir(AFFIX_DIR):
		if res is AffixData:
			affixes[res.id] = res
	for res in _load_dir(ENCHANT_DIR):
		if res is EnchantData:
			enchants[res.id] = res
	for res in _load_dir(UNIQUE_DIR):
		if res is UniqueItemData:
			uniques[res.id] = res
	abilities.clear()
	for res in _load_dir(ABILITY_DIR):
		if res is AbilityData:
			abilities[res.id] = res
	talent_trees.clear()
	talents.clear()
	for res in _load_tree(TALENT_DIR):
		if res is TalentTreeData:
			_add_talent_tree(res)
	sets.clear()
	for res in _load_dir(SET_DIR):
		if res is SetData:
			sets[res.id] = res
	bosses.clear()
	for res in _load_dir(BOSS_DIR):
		if res is BossData:
			bosses[res.id] = res
	artifacts.clear()
	for res in _load_dir(ARTIFACT_DIR):
		if res is ArtifactData:
			artifacts[res.id] = res
	consumables.clear()
	for res in _load_dir(CONSUMABLE_DIR):
		if res is ConsumableData:
			consumables[res.id] = res
	environments.clear()
	for res in _load_dir(ENVIRONMENT_DIR):
		if res is EnvironmentData:
			environments[res.id] = res
	environment_ids.clear()
	for id in ENVIRONMENT_ORDER:
		if environments.has(id):
			environment_ids.append(id)
	var extra_envs: Array[StringName] = []
	for id in environments:
		if id not in environment_ids:
			extra_envs.append(id)
	extra_envs.sort()
	environment_ids.append_array(extra_envs)
	shrines.clear()
	for res in _load_dir(SHRINE_DIR):
		if res is ShrineData:
			shrines[res.id] = res
	shrine_ids.clear()
	for id in SHRINE_ORDER:
		if shrines.has(id):
			shrine_ids.append(id)
	var extra_shrines: Array[StringName] = []
	for id in shrines:
		if id not in shrine_ids:
			extra_shrines.append(id)
	extra_shrines.sort()
	shrine_ids.append_array(extra_shrines)
	unlock_gates.clear()
	for res in _load_dir(UNLOCK_DIR):
		if res is UnlockGateData:
			add_unlock_gate(res)
	achievements.clear()
	for res in _load_dir(ACHIEVEMENT_DIR):
		if res is AchievementData:
			if achievements.has(res.id):
				push_error("Db: duplicate achievement id %s" % res.id)
			else:
				achievements[res.id] = res
	class_levels = null
	if ResourceLoader.exists(CLASS_LEVELS_PATH):
		class_levels = load(CLASS_LEVELS_PATH) as ClassLevelTable
	class_paths.clear()
	for res in _load_dir(CLASS_PATH_DIR):
		if res is ClassPathData:
			class_paths[res.class_id] = res
	class_ids.clear()
	for id in CLASS_ORDER:
		if classes.has(id):
			class_ids.append(id)
	var extra: Array[StringName] = []
	for id in classes:
		if id not in class_ids:
			extra.append(id)
	extra.sort()
	class_ids.append_array(extra)


func get_class_data(id: StringName) -> ClassData:
	return classes.get(id)


## The level path of [param class_id] (M9 LEVELS: locked abilities, capstone order, alternative weapon ...); null for a
## class without one.
func class_path(class_id: StringName) -> ClassPathData:
	return class_paths.get(class_id)


func get_ability(id: StringName) -> AbilityData:
	return abilities.get(id)


## Learnable abilities (Active / Auto-cast) offered to [param class_id] on level-up cards:
## the class's own plus the general ones (AbilityData.class_id empty), unlocked only (M9: the main profile's
## ability unlocks, Meta.is_unlocked).
func ability_pool(class_id: StringName) -> Array[AbilityData]:
	var out: Array[AbilityData] = []
	for id in abilities:
		var a := abilities[id]
		if not a.is_learned_kind() or a.card_weight <= 0.0 or not is_unlocked(id, Profile.KIND_ABILITY, class_id):
			continue
		if a.class_id == &"" or a.class_id == class_id:
			out.append(a)
	return out


## The talent trees of [param class_id] in tab order (TalentTreeData.index, then id).
func talent_trees_for(class_id: StringName) -> Array[TalentTreeData]:
	var out: Array[TalentTreeData] = []
	for id in talent_trees:
		if talent_trees[id].class_id == class_id:
			out.append(talent_trees[id])
	out.sort_custom(func(a: TalentTreeData, b: TalentTreeData) -> bool:
		return a.index < b.index if a.index != b.index else String(a.id) < String(b.id))
	return out


func get_talent(id: StringName) -> TalentData:
	return talents.get(id)


func get_talent_tree(id: StringName) -> TalentTreeData:
	return talent_trees.get(id)


func get_set(id: StringName) -> SetData:
	return sets.get(id)


## The class's own tier set (SetData.class_id == [param class_id]; the first by id when there are
## several; null = none, and for an empty id: a class-independent set is nobody's own).
## [method sets_for_class] adds the class-independent sets of its armour type.
func set_for_class(class_id: StringName) -> SetData:
	if class_id == &"":
		return null
	var best: SetData = null
	for id in sets:
		var s := sets[id]
		if s.class_id == class_id and (best == null or String(s.id) < String(best.id)):
			best = s
	return best


## The class-independent tier sets (SetData.class_id empty), by id.
func independent_sets() -> Array[SetData]:
	var ids: Array[StringName] = []
	ids.assign(sets.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var out: Array[SetData] = []
	for id in ids:
		if sets[id].is_independent():
			out.append(sets[id])
	return out


## The class-independent sets of armour type [param armor] (ClassData.ArmorType), by id.
func independent_sets_for_armor(armor: int) -> Array[SetData]:
	var out: Array[SetData] = []
	for s in independent_sets():
		if s.armor_type == armor:
			out.append(s)
	return out


## Every tier set that can ROLL for a hero of [param class_id], in roll order: the class's own set
## ([method set_for_class]) first, then the class-independent sets of the class's own armour type
## (SetData.armor_type; a set rolls only for its native armour, a plate hero never rolls the cloth set
## though it could wear it), by id. Empty for a class with neither.
## [param class_data]: the class resource when it is not one of [member classes] (a fixture); else
## the registered one is used.
func sets_for_class(class_id: StringName, class_data: ClassData = null) -> Array[SetData]:
	var out: Array[SetData] = []
	var own := set_for_class(class_id)
	if own != null:
		out.append(own)
	var cls := class_data if class_data != null else get_class_data(class_id)
	if cls == null:
		return out
	out.append_array(independent_sets_for_armor(cls.armor_type))
	return out


## Whether [param class_data] collects [param set_data]: its own class set, or a class-independent
## set of its own armour type (SetData.armor_type). Wearing is wider (ItemInstance.can_be_used_by).
func set_usable_by(set_data: SetData, class_data: ClassData) -> bool:
	if set_data == null or class_data == null:
		return false
	if not set_data.is_independent():
		return set_data.class_id == class_data.id
	return set_data.armor_type == class_data.armor_type


## Every companion id some class offers (ClassData.companion_choices), in lobby order of the
## classes, without duplicates – what `--companion=` accepts.
func companion_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for cid in class_ids:
		for c in classes[cid].companion_choices:
			if c not in out:
				out.append(c)
	return out


func get_default_class() -> ClassData:
	return classes.get(class_ids[0]) if not class_ids.is_empty() else null


func get_weapon(id: StringName) -> WeaponData:
	return weapons.get(id)


func get_enemy(id: StringName) -> EnemyData:
	return enemies.get(id)


func get_boss(id: StringName) -> BossData:
	return bosses.get(id)


func get_consumable(id: StringName) -> ConsumableData:
	return consumables.get(id)


## The shrine [param id] (null = unknown).
func get_shrine(id: StringName) -> ShrineData:
	return shrines.get(id)


## The environment [param id] (null = unknown).
func get_environment(id: StringName) -> EnvironmentData:
	return environments.get(id)


## The environment of [param id], else the default one (RunState.DEFAULT_ENVIRONMENT), else null
## (Arena.create(null) is then the forest anyway).
func environment_or_default(id: StringName) -> EnvironmentData:
	var env: EnvironmentData = environments.get(id)
	return env if env != null else environments.get(RunState.DEFAULT_ENVIRONMENT)


func get_artifact(id: StringName) -> ArtifactData:
	return artifacts.get(id)


## The Artifact of [param class_id] (null when the class has none). One per class; the first by
## id wins when a data error lists two.
func artifact_for_class(class_id: StringName) -> ArtifactData:
	var best: ArtifactData = null
	for id in artifacts:
		var a := artifacts[id]
		if a.class_id == class_id and is_unlocked(a.id) and (best == null or String(a.id) < String(best.id)):
			best = a
	return best


## The class ids that have an Artifact, in lobby order (class_ids).
func artifact_classes() -> Array[StringName]:
	var out: Array[StringName] = []
	for cid in class_ids:
		if artifact_for_class(cid) != null:
			out.append(cid)
	return out


func get_enchant(id: StringName) -> EnchantData:
	return enchants.get(id)


func get_unique(id: StringName) -> UniqueItemData:
	return uniques.get(id)


## Content-pool gate for meta-progression (ARCHITECTURE "Forward compatibility"): every player-facing pool (shop,
## loot, level-up cards, lobby) filters through this. M9 gates the content kinds of Profile.KINDS: a call with a
## [param kind] asks the main profile ([method Meta.is_unlocked]); a call without one (the item, enchant, set,
## consumable and shrine pools) is not gated and answers true.
func is_unlocked(id: StringName, kind: StringName = &"", class_id: StringName = &"") -> bool:
	return kind == &"" or Meta.is_unlocked(kind, id, class_id)


## The gate of the content [param id] of [param kind] (null = not gated).
func get_unlock_gate(kind: StringName, id: StringName) -> UnlockGateData:
	return unlock_gates.get(UnlockGateData.key_for(kind, id))


## Registers [param gate] (a gate of the same kind and id is replaced). A content package without a .tres in
## data/unlocks/ and the tests use it; [method reload] forgets it.
func add_unlock_gate(gate: UnlockGateData) -> void:
	if gate != null and gate.kind != &"" and gate.id != &"":
		unlock_gates[gate.key()] = gate


func remove_unlock_gate(kind: StringName, id: StringName) -> void:
	unlock_gates.erase(UnlockGateData.key_for(kind, id))


func get_achievement(id: StringName) -> AchievementData:
	return achievements.get(id)


## Every achievement in file order.
func achievement_list() -> Array[AchievementData]:
	var out: Array[AchievementData] = []
	out.assign(achievements.values())
	return out


## Next / previous class id in lobby order (wraps around).
func cycle_class(current: StringName, step: int) -> StringName:
	if class_ids.is_empty():
		return current
	var i := class_ids.find(current)
	return class_ids[wrapi(i + step, 0, class_ids.size())]


## Registers [param tree] and its talents (a duplicate tree / talent id is an error; the first
## one loaded stays).
func _add_talent_tree(tree: TalentTreeData) -> void:
	if talent_trees.has(tree.id):
		push_error("Db: duplicate talent tree id %s" % tree.id)
		return
	talent_trees[tree.id] = tree
	for t in tree.talents:
		if t == null:
			continue
		if talents.has(t.id):
			push_error("Db: duplicate talent id %s (tree %s)" % [t.id, tree.id])
			continue
		talents[t.id] = t


## [method _load_dir] of [param path] and, depth first in name order, of its subfolders.
func _load_tree(path: String) -> Array[Resource]:
	var out := _load_dir(path)
	var entries := ResourceLoader.list_directory(path)
	entries.sort()
	for entry in entries:
		if entry.ends_with("/"):
			out.append_array(_load_tree(path + entry))
	return out


func _load_dir(path: String) -> Array[Resource]:
	var out: Array[Resource] = []
	var files := ResourceLoader.list_directory(path)
	files.sort()
	for file in files:
		# Exported builds list "x.tres.remap"; ResourceLoader resolves the original name.
		var name := file.trim_suffix(".remap")
		if name.ends_with(".tres") or name.ends_with(".res"):
			var res := load(path + name)
			if res != null:
				out.append(res)
			else:
				push_error("Db: failed to load %s" % (path + name))
	return out
