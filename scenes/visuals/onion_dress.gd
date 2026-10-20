class_name OnionDress
extends RefCounted
## What a hero wears for show on top of (or instead of) its gear (M9 WARDROBE, design_m9 section 7): a look per visible armour
## slot that replaces the worn item's model, and a Tabard, a Hat variant, a Glow and a Dye. Purely cosmetic: OnionModel.set_dress
## takes it, OnionModel keeps the worn looks apart and rebuilds its gear when [method key] changes.
##
##  - [member looks]: EquipLook per [enum EquipLook.Slot] (null = show the worn item; the class starter piece shows when the slot
##    is empty as well). Any armour type, any slot piece: it is a transmog, not an item;
##  - [member tabard]: a cloth overlay on the chest (over a worn chest piece too); [member glow]: an unshaded ring of light;
##    [member hat]: replaces the Head piece (look, item or starter) with the Hat variant; [member dye] tints the Tabard and the Glow.
## The key is the parallel of EquipLook.key() for the cosmetics: "" for an empty dress (so a model without one keeps its old key).

var looks: Array[EquipLook] = [null, null, null]
var tabard: CosmeticData
var hat: CosmeticData
var glow: CosmeticData
var dye: CosmeticData


## The dress of a hero's selections: [param look_ids] ({slot name: look id}, Profile.LOOK_SLOTS) and [param cosmetic_ids]
## ({"tabard" | "hat" | "glow" | "dye": CosmeticData id}). An id that does not resolve is skipped.
static func from_ids(look_ids: Dictionary, cosmetic_ids: Dictionary) -> OnionDress:
	var d := OnionDress.new()
	for slot: Variant in look_ids:
		var look := Wardrobe.look_from_id(StringName(str(look_ids[slot])))
		if look != null and Wardrobe.slot_name(look.slot) == StringName(str(slot)):
			d.looks[look.slot] = look
	d.tabard = _pick(cosmetic_ids, CosmeticData.KIND_TABARD)
	d.hat = _pick(cosmetic_ids, CosmeticData.KIND_HAT)
	d.glow = _pick(cosmetic_ids, CosmeticData.KIND_GLOW)
	d.dye = _pick(cosmetic_ids, CosmeticData.KIND_DYE)
	return d


static func _pick(cosmetic_ids: Dictionary, kind: StringName) -> CosmeticData:
	var c := Db.get_cosmetic(StringName(str(cosmetic_ids.get(kind, ""))))
	return c if c != null and c.kind == kind else null


## The dress of [param slot]'s own selections.
static func for_slot(slot: PlayerSlot) -> OnionDress:
	return from_ids(slot.looks, slot.cosmetics) if slot != null else OnionDress.new()


## Nothing to show: the model is exactly the base game's.
func is_empty() -> bool:
	return looks[0] == null and looks[1] == null and looks[2] == null and not has_cosmetics()


func has_cosmetics() -> bool:
	return tabard != null or hat != null or glow != null


## The override look of an [enum EquipLook.Slot] (null = none).
func look_for(slot: int) -> EquipLook:
	return looks[slot] if slot >= 0 and slot < looks.size() else null


## The tint a Dye paints (alpha 0 = no dye).
func dye_color() -> Color:
	return dye.color if dye != null else Color(0, 0, 0, 0)


## Change-detection key of the cosmetics ("" = none). The look overrides are part of the model's own looks key.
func key() -> String:
	if not has_cosmetics():
		return ""
	return "%s|%s|%s|%s" % [_id(tabard), _id(hat), _id(glow), _id(dye)]


static func _id(c: CosmeticData) -> String:
	return String(c.id) if c != null else "-"
