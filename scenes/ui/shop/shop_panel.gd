class_name ShopPanel
extends Control
## STUB – owned by the "ui-market" agent. The shared shop in the middle of the screen
## (GDD 10, 12): a goblin merchant's stall showing Shop.offers as item cards (icon, name in
## rarity colour, price, lock / ping markers, usable-by badges per player), one colour-coded
## cursor per player, reroll vote pips + cost at the top, shared gold. Per player: d-pad /
## stick moves their cursor, A buys (hold A ~1 s if it costs > 50% of the wallet), X locks,
## R3 / Tab pings, Y votes reroll. Shows an ItemTooltip for each player's hovered offer
## (compared with that player's equipped item).

var shop: Shop


static func create(p_shop: Shop) -> ShopPanel:
	var panel := ShopPanel.new()
	panel.shop = p_shop
	return panel


## Rebuilds the offer cards and cursors for the joined slots.
func refresh(slots: Array[PlayerSlot]) -> void:
	pass


## Called every _process frame by the Intermission for a slot whose focus is the shop.
func handle_input(slot: PlayerSlot) -> void:
	pass
