class_name ItemIcon
extends Control
## STUB – owned by the "ui-items" agent. Square item icon: procedural slot / weapon silhouette
## on a dark slot background with a rarity-coloured border (UiTheme.RARITY_COLORS); empty
## slots show a faint slot silhouette. Optional small corner badges (e.g. "↑" upgrade arrow).

var item: ItemInstance


static func create(p_item: ItemInstance = null, p_size: float = 64.0) -> ItemIcon:
	var icon := ItemIcon.new()
	icon.custom_minimum_size = Vector2(p_size, p_size)
	icon.item = p_item
	return icon


func set_item(p_item: ItemInstance) -> void:
	item = p_item


## Empty slot look for an equipment position (Items.EquipSlot).
func set_empty_slot(equip_slot: int) -> void:
	item = null


## Green ↑ / red ↓ / none badge (loot roll, shop: is it an upgrade for this player).
func set_upgrade_badge(direction: int) -> void:
	pass
