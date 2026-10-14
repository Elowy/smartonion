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
## data/bosses/<boss_id>.tres (BossData, M6; may be empty until the BOSSES package).
const BOSS_DIR := "res://data/bosses/"
## data/consumables/<id>.tres (ConsumableData, M6; may be empty until the SHOPSINKS package).
const CONSUMABLE_DIR := "res://data/consumables/"
## data/artifacts/<id>.tres (ArtifactData, M6 ARTIFACTS: one weapon per class).
const ARTIFACT_DIR := "res://data/artifacts/"
## Lobby order of the launch classes; any extra class is appended alphabetically.
const CLASS_ORDER: Array[StringName] = [&"warrior", &"mage", &"paladin", &"rogue", &"warlock"]

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
var class_ids: Array[StringName] = []


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


func get_ability(id: StringName) -> AbilityData:
	return abilities.get(id)


## Learnable abilities (Active / Auto-cast) offered to [param class_id] on level-up cards:
## the class's own plus the general ones (AbilityData.class_id empty), unlocked only.
func ability_pool(class_id: StringName) -> Array[AbilityData]:
	var out: Array[AbilityData] = []
	for id in abilities:
		var a := abilities[id]
		if not a.is_learned_kind() or a.card_weight <= 0.0 or not is_unlocked(id):
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


## The tier set of [param class_id] (the first by id when there are several; null = none).
func set_for_class(class_id: StringName) -> SetData:
	var best: SetData = null
	for id in sets:
		var s := sets[id]
		if s.class_id == class_id and (best == null or String(s.id) < String(best.id)):
			best = s
	return best


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


## Content-pool gate for meta-progression (ARCHITECTURE "Forward compatibility"): every
## player-facing pool (shop, loot, level-up cards, lobby) filters through this. All content is
## unlocked until milestone M9.
func is_unlocked(_id: StringName) -> bool:
	return true


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
