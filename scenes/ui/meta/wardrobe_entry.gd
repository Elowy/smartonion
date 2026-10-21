class_name WardrobeEntry
extends RefCounted
## One cell of the Wardrobe (M9 WARDROBE): an item look, a cosmetic, or the "no selection" choice ("Worn gear" / "None") of a
## picker row. A plain view model: [WardrobeGrid] draws it, [LookPicker] and [WardrobePage] build and read it.

enum Kind { NONE, LOOK, COSMETIC }

var kind := Kind.LOOK
## The look id or the cosmetic id (&"" for the NONE choice).
var id: StringName = &""
## The slot name of a look (Profile.LOOK_SLOTS) or the cosmetic kind (CosmeticData.KINDS): the row / filter the entry belongs to.
var slot: StringName = &""
var title := ""
## Second line ("Plate · Rare", "Class Level 15 with the Mage").
var detail := ""
## How to get it (shown while locked).
var hint := ""
var owned := true
## Seeds to buy it (0 = not for sale).
var price := 0
var look: EquipLook
var cosmetic: CosmeticData


## The "nothing chosen" entry of a picker row.
static func none(p_slot: StringName, p_title: String) -> WardrobeEntry:
	var e := WardrobeEntry.new()
	e.kind = Kind.NONE
	e.slot = p_slot
	e.title = p_title
	return e


static func for_look(look_id: StringName) -> WardrobeEntry:
	var e := WardrobeEntry.new()
	e.kind = Kind.LOOK
	e.id = look_id
	e.slot = Wardrobe.slot_of(look_id)
	e.look = Wardrobe.look_from_id(look_id)
	e.title = Wardrobe.look_name(look_id)
	e.detail = Wardrobe.look_detail(look_id)
	e.hint = Wardrobe.look_hint(look_id)
	e.owned = Wardrobe.is_collected(look_id)
	return e


static func for_cosmetic(c: CosmeticData) -> WardrobeEntry:
	var e := WardrobeEntry.new()
	e.kind = Kind.COSMETIC
	e.id = c.id
	e.slot = c.kind
	e.cosmetic = c
	e.title = c.display_name
	e.detail = String(c.kind).capitalize()
	e.hint = Wardrobe.cosmetic_source(c.id)
	e.owned = Wardrobe.cosmetic_owned(c.id)
	e.price = c.price
	return e


## The entries of a look slot: every look of the collection (owned or not), or only the collected ones.
static func looks_of(slot_name: StringName, owned_only: bool = false) -> Array[WardrobeEntry]:
	var out: Array[WardrobeEntry] = []
	for id in Wardrobe.look_ids_for_slot(slot_name):
		if owned_only and not Wardrobe.is_collected(id):
			continue
		out.append(for_look(id))
	return out


## The entries of a cosmetic kind (CosmeticData.KINDS).
static func cosmetics_of(cosmetic_kind: StringName, owned_only: bool = false) -> Array[WardrobeEntry]:
	var out: Array[WardrobeEntry] = []
	for c in Wardrobe.cosmetics_of(cosmetic_kind, owned_only):
		out.append(for_cosmetic(c))
	return out
