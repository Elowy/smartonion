class_name Wardrobe
extends RefCounted
## The Wardrobe (M9 WARDROBE, design_m9 section 7): the account-wide collection of item looks and cosmetics, and the
## mapping between a look id and the [EquipLook] the model draws.
##
## Look ids (normalised, slot is head | shoulders | chest, i.e. [constant Profile.LOOK_SLOTS]):
##   g.<slot>.<armor 0-3>.<tier 0-2>.<rarity 0-5>   a generated piece (ClassData.ArmorType, Items.material_tier, Items.Rarity)
##   s.<slot>.<set_id>                               a tier set piece (the set's kit and richest detail; armour from the set)
##   u.<slot>.<unique_id>                            a hand-made unique (UniqueItemData.id, not a set piece)
## [method look_id] digests an [EquipLook] (an item's, see [method look_id_of_item]), [method look_from_id] turns an id back into
## the look to draw; the two are inverse for every id of [method all_look_ids].
##
## A look is COLLECTED when the profile unlocked it ([constant Profile.KIND_LOOK]): the items a hero wears at a wave start and
## at the run's end are recorded ([method register] hooks both, real runs only – never in an automated run). The cosmetics
## (Tabard, Hat, Glow, Dye: [CosmeticData], [member Db.cosmetics]) are owned the same way ([constant Profile.KIND_COSMETIC]).
## The player's choice is [member PlayerSlot.looks] / [member PlayerSlot.cosmetics]; [OnionDress] turns it into what the model
## shows. Nothing here changes a stat.

## The listener id of the run-end hook.
const LISTENER := &"wardrobe"
## Seeds a Dye costs in The Onion Patch (the price is on each CosmeticData too; this is the design value).
const DYE_PRICE := 100
## Armour pieces never come with the Artifact rarity (those are weapons): a look of that rarity can be drawn but is not
## part of the collection.
const MAX_COLLECTED_RARITY := Items.Rarity.LEGENDARY
## Rarity (and tier) a set piece / unique look is drawn with: sets are Epic; a unique keeps its own rarity and shows the
## richest material.
const SET_RARITY := Items.Rarity.EPIC
const SHOWCASE_TIER := EquipLook.MAX_TIER

## Results of [method buy_cosmetic].
const RESULT_BOUGHT := &"bought"
const RESULT_OWNED := &"owned"
const RESULT_POOR := &"poor"
const RESULT_INVALID := &"invalid"

## Player-visible name of the part of each family ("plate_helm" -> "Great Helm").
const PIECE_NAMES := {
	&"cowl": "Cowl", &"cap": "Cap", &"coif": "Coif", &"helm": "Great Helm",
	&"mantle": "Mantle", &"shoulderpads": "Shoulderpads", &"spaulders": "Spaulders", &"pauldrons": "Pauldrons",
	&"robe": "Robe", &"tunic": "Tunic", &"hauberk": "Hauberk", &"breastplate": "Breastplate",
}

## Every collected-or-collectable look id, built once ([method all_look_ids]); rebuilt when the item data changes.
static var _cache: Array[StringName] = []
static var _cache_sig := -1
## The ids found in this run so far (the end screen / log read it through [method run_new_looks]).
static var _run_new: Array[StringName] = []
static var _wired := false


# --- Ids ------------------------------------------------------------------------------------

## The slot name ("head" ...) of an [enum EquipLook.Slot]; &"" for anything else.
static func slot_name(slot: int) -> StringName:
	return Profile.LOOK_SLOTS[slot] if slot >= 0 and slot < Profile.LOOK_SLOTS.size() else &""


## The [enum EquipLook.Slot] of a slot name; -1 for an unknown name.
static func slot_index(name: StringName) -> int:
	return Profile.LOOK_SLOTS.find(name)


## The normalised id of [param look] (&"" for null). A set piece becomes "s.<slot>.<set>", a hand-made unique "u.<slot>.<id>"; a
## set or unique the data does not know (an Heirloom, removed content) falls back to the generated id of its armour.
static func look_id(look: EquipLook) -> StringName:
	if look == null:
		return &""
	var slot := slot_name(look.slot)
	if look.is_set() and Db.get_set(look.set_id) != null:
		return StringName("s.%s.%s" % [slot, look.set_id])
	if look.unique_id != &"" and Db.get_unique(look.unique_id) != null and Db.get_unique(look.unique_id).set_id == &"":
		return StringName("u.%s.%s" % [slot, look.unique_id])
	return StringName("g.%s.%d.%d.%d" % [slot, look.armor, look.tier, look.rarity])


## The look id of what [param item] looks like when worn (&"" for an item without a model part).
static func look_id_of_item(item: ItemInstance) -> StringName:
	return look_id(EquipLook.from_item(item))


## The look to draw for [param id]; null for an id that is not a look (malformed, unknown set / unique, a slot name that does not exist).
static func look_from_id(id: StringName) -> EquipLook:
	var parts := String(id).split(".")
	if parts.size() < 3:
		return null
	var slot := slot_index(StringName(parts[1]))
	if slot < 0:
		return null
	match parts[0]:
		"g":
			if parts.size() != 5 or not _is_digits(parts[2]) or not _is_digits(parts[3]) or not _is_digits(parts[4]):
				return null
			var armor := int(parts[2])
			var tier := int(parts[3])
			var rarity := int(parts[4])
			if armor > ClassData.ArmorType.PLATE or tier > EquipLook.MAX_TIER or rarity >= WeaponModel.RARITY_COLORS.size():
				return null
			return EquipLook.make(slot as EquipLook.Slot, armor, tier, rarity)
		"s":
			var set := Db.get_set(StringName(parts[2])) if parts.size() == 3 else null
			if set == null:
				return null
			return EquipLook.make(slot as EquipLook.Slot, _set_armor(set), EquipLook.MAX_TIER, SET_RARITY, set.id)
		"u":
			var data := Db.get_unique(StringName(parts[2])) if parts.size() == 3 else null
			if data == null or data.set_id != &"" or EquipLook.slot_for_type(data.slot_type) != slot:
				return null
			var armor_type := data.armor_type if data.armor_type != Items.NO_ARMOR else ClassData.ArmorType.CLOTH
			return EquipLook.make(slot as EquipLook.Slot, armor_type, SHOWCASE_TIER, data.rarity, &"", data.id)
	return null


static func is_look_id(id: StringName) -> bool:
	return look_from_id(id) != null


## The slot name ("head" ...) a look id is for; &"" for a malformed id.
static func slot_of(id: StringName) -> StringName:
	var parts := String(id).split(".")
	return StringName(parts[1]) if parts.size() >= 3 and slot_index(StringName(parts[1])) >= 0 else &""


## The armour type the pieces of [param set] are made of (a class set: the class's).
static func _set_armor(set: SetData) -> int:
	if set.armor_type >= 0:
		return set.armor_type
	var cd := Db.get_class_data(set.class_id)
	return cd.armor_type if cd != null else ClassData.ArmorType.CLOTH


static func _is_digits(s: String) -> bool:
	return s.is_valid_int() and int(s) >= 0 and not s.begins_with("+")


## Every look id of the collection, grouped by slot (head, shoulders, chest), inside a slot: generated by armour / tier /
## rarity, then the tier sets, then the uniques. [param include_artifact]: also the Artifact-rarity generated looks no armour
## piece ever has (they can be drawn, they are not collectable). 256 ids with the default (180 generated, 36 set, 40 unique).
static func all_look_ids(include_artifact: bool = false) -> Array[StringName]:
	var sig := Db.sets.size() * 10000 + Db.uniques.size()
	if sig != _cache_sig:
		_cache_sig = sig
		_cache = _build_ids(true)
	if include_artifact:
		return _cache.duplicate()
	var out: Array[StringName] = []
	for id in _cache:
		if not is_artifact_look(id):
			out.append(id)
	return out


## The collection ids of one slot ([param slot] is a name of [constant Profile.LOOK_SLOTS]).
static func look_ids_for_slot(slot: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in all_look_ids():
		if slot_of(id) == slot:
			out.append(id)
	return out


static func is_artifact_look(id: StringName) -> bool:
	var parts := String(id).split(".")
	return parts.size() == 5 and parts[0] == "g" and int(parts[4]) > MAX_COLLECTED_RARITY


static func _build_ids(with_artifact: bool) -> Array[StringName]:
	var out: Array[StringName] = []
	var set_ids: Array[StringName] = []
	set_ids.assign(Db.sets.keys())
	set_ids.sort()
	var unique_ids: Array[StringName] = []
	for uid in Db.uniques:
		var data: UniqueItemData = Db.uniques[uid]
		if data.set_id == &"" and EquipLook.slot_for_type(data.slot_type) >= 0:
			unique_ids.append(uid)
	unique_ids.sort()
	for slot in Profile.LOOK_SLOTS.size():
		var name := Profile.LOOK_SLOTS[slot]
		for armor in 4:
			for tier in EquipLook.MAX_TIER + 1:
				for rarity in WeaponModel.RARITY_COLORS.size():
					if with_artifact or rarity <= MAX_COLLECTED_RARITY:
						out.append(StringName("g.%s.%d.%d.%d" % [name, armor, tier, rarity]))
		for set_id in set_ids:
			out.append(StringName("s.%s.%s" % [name, set_id]))
		for uid in unique_ids:
			if EquipLook.slot_for_type(Db.uniques[uid].slot_type) == slot:
				out.append(StringName("u.%s.%s" % [name, uid]))
	return out


# --- Names ----------------------------------------------------------------------------------

## The name of a look: "Steel Great Helm", a set piece "Battlegear of Fury", a unique's own name.
static func look_name(id: StringName) -> String:
	var look := look_from_id(id)
	if look == null:
		return String(id)
	var parts := String(id).split(".")
	match parts[0]:
		"s":
			var set := Db.get_set(StringName(parts[2]))
			return "%s %s" % [set.display_name, _slot_word(look.slot)]
		"u":
			return Db.get_unique(StringName(parts[2])).display_name
	var material: String = Items.MATERIAL_NAMES[look.armor][look.tier]
	var piece: String = PIECE_NAMES.get(StringName(String(look.family()).get_slice("_", 1)), "Piece")
	return "%s %s" % [material, piece]


## The second line of a look's card: the armour type and rarity ("Plate · Rare"), "Tier set piece", "Unique ...".
static func look_detail(id: StringName) -> String:
	var look := look_from_id(id)
	if look == null:
		return ""
	var armor_name: String = Items.ARMOR_TYPE_NAMES.get(look.armor, "")
	var rarity_name: String = Items.RARITY_NAMES[clampi(look.rarity, 0, Items.RARITY_NAMES.size() - 1)]
	match String(id).get_slice(".", 0):
		"s":
			return "%s · tier set piece" % armor_name
		"u":
			return "%s · %s unique" % [armor_name, rarity_name]
	return "%s · %s" % [armor_name, rarity_name]


## How to get a look (the line under a locked card).
static func look_hint(id: StringName) -> String:
	match String(id).get_slice(".", 0):
		"s":
			return "Wear the piece of this set in a run."
		"u":
			return "Wear this item in a run."
	return "Wear a piece like this in a run."


static func _slot_word(slot: int) -> String:
	return ["Head", "Shoulders", "Chest"][clampi(slot, 0, 2)]


# --- Collection -----------------------------------------------------------------------------

## True when [param id] is in the collection (the dev and max profiles own everything).
static func is_collected(id: StringName) -> bool:
	return Meta.is_unlocked(Profile.KIND_LOOK, id)


## Looks of the collection the profile owns / the size of the collection.
static func collected_count() -> int:
	var n := 0
	for id in all_look_ids():
		if is_collected(id):
			n += 1
	return n


static func total_count() -> int:
	return all_look_ids().size()


## The collected look ids of one slot, in collection order.
static func collected_for_slot(slot: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in look_ids_for_slot(slot):
		if is_collected(id):
			out.append(id)
	return out


# --- Cosmetics ------------------------------------------------------------------------------

static func cosmetic(id: StringName) -> CosmeticData:
	return Db.get_cosmetic(id)


static func cosmetic_owned(id: StringName) -> bool:
	return Db.get_cosmetic(id) != null and Meta.is_unlocked(Profile.KIND_COSMETIC, id)


## The cosmetics of [param kind] (CosmeticData.KINDS) in list order; [param owned_only] keeps the owned ones.
static func cosmetics_of(kind: StringName, owned_only: bool = false) -> Array[CosmeticData]:
	var out: Array[CosmeticData] = []
	for c in Db.cosmetics_of_kind(kind):
		if not owned_only or cosmetic_owned(c.id):
			out.append(c)
	return out


## How to get a cosmetic: the Class Level of a level cosmetic, the achievement that grants it, the Seeds price of a Dye.
static func cosmetic_source(id: StringName) -> String:
	var c := Db.get_cosmetic(id)
	if c == null:
		return ""
	var bits: Array[String] = []
	if c.class_id != &"":
		var level := level_of_cosmetic(c)
		var cd := Db.get_class_data(c.class_id)
		bits.append("Class Level %d with the %s" % [level, cd.display_name if cd != null else String(c.class_id)])
	for a in Db.achievement_list():
		for reward in a.rewards:
			if str(reward.get("kind", "")) == "cosmetic" and StringName(str(reward.get("id", ""))) == id:
				bits.append("Achievement: %s" % a.display_name)
	if c.price > 0:
		bits.append("Buy for %d Seeds" % c.price)
	return " · ".join(bits) if not bits.is_empty() else "Earned in play"


## The Class Level at which a level cosmetic is awarded (0 for any other).
static func level_of_cosmetic(c: CosmeticData) -> int:
	if c == null or c.class_id == &"":
		return 0
	for r in ClassLevels.table().rewards:
		if str(r.get("kind", "")) == "cosmetic" and StringName(str(r.get("slot", ""))) == c.kind:
			return int(r.get("level", 0))
	return 0


## Buys the cosmetic [param id] (a Dye: [member CosmeticData.price] Seeds, saved at once). Returns a RESULT_ constant:
## [constant RESULT_BOUGHT], [constant RESULT_OWNED] (nothing is paid), [constant RESULT_POOR] (not enough Seeds) or
## [constant RESULT_INVALID] (unknown, or not sold).
static func buy_cosmetic(id: StringName) -> StringName:
	var c := Db.get_cosmetic(id)
	if c == null or c.price <= 0:
		return RESULT_INVALID
	if cosmetic_owned(id):
		return RESULT_OWNED
	if not Meta.can_afford_seeds(c.price):
		return RESULT_POOR
	# Unlock first: a crash between the two writes leaves the player with the Dye and the Seeds, never without both.
	Meta.unlock(Profile.KIND_COSMETIC, id)
	Meta.spend_seeds(c.price)
	return RESULT_BOUGHT


# --- Selections -----------------------------------------------------------------------------

## [param looks] ({slot name: look id}) without ids that are not a look of that slot or that the profile has not collected
## ([param check_owned]).
static func sanitize_looks(looks: Dictionary, class_id: StringName = &"", check_owned: bool = true) -> Dictionary[StringName, StringName]:
	var out: Dictionary[StringName, StringName] = {}
	for slot: StringName in looks:
		var id: StringName = looks[slot]
		if slot_index(slot) < 0 or slot_of(id) != slot or look_from_id(id) == null:
			continue
		if check_owned and not Meta.is_unlocked(Profile.KIND_LOOK, id, class_id):
			continue
		out[slot] = id
	return out


## [param value] (cosmetic key -> id) without ids of the wrong kind or that the profile does not own.
static func sanitize_cosmetics(value: Dictionary, class_id: StringName = &"", check_owned: bool = true) -> Dictionary[StringName, StringName]:
	var out: Dictionary[StringName, StringName] = {}
	for key: StringName in CosmeticData.KINDS:
		var id: StringName = StringName(str(value.get(key, "")))
		var c := Db.get_cosmetic(id)
		if c == null or c.kind != key:
			continue
		if check_owned and not Meta.is_unlocked(Profile.KIND_COSMETIC, id, class_id):
			continue
		out[key] = id
	return out


# --- Recording ------------------------------------------------------------------------------

## The look ids of the Head / Shoulders / Chest pieces [param equipment] wears (no duplicates).
static func worn_ids(equipment: Equipment) -> Array[StringName]:
	var out: Array[StringName] = []
	if equipment == null:
		return out
	for s: Items.EquipSlot in [Items.EquipSlot.HEAD, Items.EquipSlot.SHOULDERS, Items.EquipSlot.CHEST]:
		var id := look_id_of_item(equipment.get_item(s))
		if id != &"" and id not in out:
			out.append(id)
	return out


## Adds [param ids] to the profile's collection (no save: the caller saves once). Returns the ones that were new.
static func collect(ids: Array[StringName]) -> Array[StringName]:
	var added: Array[StringName] = []
	if not Meta.records_runs():
		return added
	for id in ids:
		if look_from_id(id) != null and Meta.profile.unlock(Profile.KIND_LOOK, id):
			added.append(id)
			if id not in _run_new:
				_run_new.append(id)
	return added


## Wave start (RunState.wave_changed): records what every hero wears right now, one save for the lot. Does nothing in an
## automated run. Returns the new looks.
static func record_worn_now() -> Array[StringName]:
	if not Meta.records_runs():
		return []
	var found: Array[StringName] = []
	for slot in PlayerManager.get_slots():
		var hero := slot.player
		if hero == null or not is_instance_valid(hero):
			continue
		for id in worn_ids(hero.get(&"equipment") as Equipment):
			if id not in found:
				found.append(id)
	var added := collect(found)
	if not added.is_empty():
		Meta.save()
	return added


## The run-end listener ([method Meta.add_run_listener]): the pieces the heroes wear at the end (the report's snapshot). Runs
## inside the dispatch, so the save is Meta's single one. Adds "new_looks" (all of this run) and "looks_collected" to [param result].
static func on_run_end(report: RunReport, p: Profile, result: Dictionary) -> void:
	var found: Array[StringName] = []
	for hero: Dictionary in report.heroes:
		for entry: Dictionary in hero.get("equipped", []):
			var look: Dictionary = entry.get("look", {})
			if look.is_empty():
				continue
			var l := EquipLook.make(int(look.get("slot", 0)) as EquipLook.Slot, int(look.get("armor", 0)), int(look.get("tier", 0)),
					int(look.get("rarity", 0)), StringName(str(look.get("set_id", ""))), StringName(str(look.get("unique_id", ""))))
			var id := look_id(l)
			if id != &"" and id not in found:
				found.append(id)
	collect(found)
	result["new_looks"] = _run_new.duplicate()
	result["looks_collected"] = p.unlocked_ids(Profile.KIND_LOOK).size()


## The looks found in the run so far (this run only; reset when a run starts).
static func run_new_looks() -> Array[StringName]:
	return _run_new.duplicate()


static func _on_run_started() -> void:
	_run_new.clear()


static func _on_wave_changed(_wave: int) -> void:
	record_worn_now()


## Registers the run-end listener on [param meta] (the Meta autoload, at the default priority: after the counters, before the
## achievements, so `wardrobe_150` sees the run's looks) and the wave-start hook on RunState.
static func register(meta: Node) -> void:
	meta.add_run_listener(LISTENER, on_run_end)
	if not _wired:
		_wired = true
		RunState.run_started.connect(_on_run_started)
		RunState.wave_changed.connect(_on_wave_changed)
