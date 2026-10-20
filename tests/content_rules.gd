extends RefCounted
## Content rules the tests share (M8 P0). A class, weapon type or tier set added later is checked
## against the same invariants – "every class has ... ", "every weapon has ..." – instead of fixed
## totals, so new content never needs a count edited, while a missing or a duplicate piece still
## fails the rule of its class. Preload it: const Rules := preload("res://tests/content_rules.gd").

## The five launch classes in lobby order (the M8 Hunter and Shaman come after them).
const LAUNCH_CLASSES: Array[StringName] = [&"warrior", &"mage", &"paladin", &"rogue", &"warlock"]
## The 13 weapon bases of the launch. Later weapon types add to Db.weapons; none may vanish.
const LAUNCH_WEAPONS: Array[StringName] = [&"sword", &"dagger", &"mace", &"two_hand_axe", &"two_hand_sword",
	&"two_hand_mace", &"shield", &"tome", &"orb", &"wand", &"staff", &"bow", &"gun"]
## Hand-made items of the launch content (63 M6a + 20 trinkets + 17 Legendaries + 30 named + 30 class
## items): the ones of the launch classes and the class-free, set-free ones. See [method launch_uniques].
const LAUNCH_UNIQUES := 160
## Non-set hand-made items every class has (2 of M6a + 6 of M6b), each with an "Equip:" ability mod.
const CLASS_ITEMS_PER_CLASS := 8
## Pieces of every tier set (Head, Shoulders, Chest, Hands, Legs).
const PIECES_PER_SET := 5
## Talent trees per class, and the points a full tree takes.
const TREES_PER_CLASS := 3

## M8 content that ships in a later package than its class (HUNTER / SHAMAN bring the class, its
## abilities and Mastery; ITEMS the Artifact, class set and class items; TALENTS the trees). While
## a "<class>:<part>" line is listed, the "every class has ..." completeness checks leave that part
## of that class out, so each package's suite stays green on its own. A package deletes its lines
## when its content lands; test_m8_foundation fails on a line whose content already exists, so none
## is forgotten, and a class missing a part that is NOT listed fails its completeness check.
## Parts: artifact, set, items, trees. Inert while the class has no data.
const PENDING: Array[String] = [
	# ITEMS package: the Artifact, the class tier set (5 pieces) and the 8 class items.
	"hunter:artifact",
	"shaman:artifact",
	"hunter:set",
	"shaman:set",
	"hunter:items",
	"shaman:items",
	# TALENTS packages: the three talent trees.
	"hunter:trees",
	"shaman:trees",
]


## The non-set hand-made items restricted to [param class_id] (its "class items").
static func class_items(class_id: StringName) -> Array[UniqueItemData]:
	var out: Array[UniqueItemData] = []
	for id in Db.uniques:
		var u := Db.uniques[id]
		if u.class_restriction == class_id and u.set_id == &"":
			out.append(u)
	return out


## The class sets (SetData.class_id == [param class_id]).
static func class_sets(class_id: StringName) -> Array[SetData]:
	var out: Array[SetData] = []
	for id in Db.sets:
		if Db.sets[id].class_id == class_id:
			out.append(Db.sets[id])
	return out


## The class-independent sets (SetData.class_id empty).
static func free_sets() -> Array[SetData]:
	return class_sets(&"")


## Hand-made items that belong to the launch content: restricted to a launch class, or restricted to
## no class and part of no set (the pieces of a class-independent set and the items of the M8
## classes are later content).
static func launch_uniques() -> int:
	var n := 0
	for id in Db.uniques:
		var u := Db.uniques[id]
		if u.class_restriction in LAUNCH_CLASSES or (u.class_restriction == &"" and u.set_id == &""):
			n += 1
	return n


## The class-independent set pool rule: whether a class of armour [param class_armor] rolls (is offered,
## collects) a class-independent set of armour [param set_armor] (ClassData.ArmorType values). Native armour
## only: a set rolls for the classes that wear exactly its armour type (Db.set_usable_by,
## ItemGenerator.independent_sets_for); wearing a lighter set is allowed but never rolled. test_m8_sets
## derives its pool expectations from here.
static func free_set_fits(set_armor: int, class_armor: int) -> bool:
	return set_armor == class_armor


## Whether [param part] ("artifact", "set", "items", "trees") of [param class_id] is still to come
## (listed in [constant PENDING]).
static func pending(class_id: StringName, part: String) -> bool:
	return "%s:%s" % [class_id, part] in PENDING


## The classes of Db whose [param part] is expected to be complete now (in lobby order): every class
## except those with the part pending.
static func classes_with(part: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Db.class_ids:
		if not pending(id, part):
			out.append(id)
	return out


## How many of [param part] the data holds for [param class_id] (Artifacts, class sets, class
## items, talent trees) – what the pending guard compares with the list.
static func count_of(class_id: StringName, part: String) -> int:
	match part:
		"artifact":
			var n := 0
			for id in Db.artifacts:
				if Db.artifacts[id].class_id == class_id:
					n += 1
			return n
		"set":
			return class_sets(class_id).size()
		"items":
			return class_items(class_id).size()
		"trees":
			return Db.talent_trees_for(class_id).size()
	return 0
