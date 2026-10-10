class_name PlayerPanel
extends Control
## STUB – owned by the "ui-items" agent. One player's personal between-wave panel (GDD 12),
## shown in that player's screen corner / quadrant: tabs Character | Trainer | Talents
## (Trainer / Talents disabled until M4 / M5). Character tab = WoW paper doll (armor slots left,
## jewellery + trinkets right, weapons bottom, onion preview + stat list + Avg. Item Level in
## the middle) and the 10-slot backpack. Controller: d-pad / stick moves the selection, A opens
## an action menu (Equip / Unequip / Sell / Trade → Pn / Compare), B closes it, Y toggles the
## comparison tooltip. Sell gives Items.SELL_SHARE of the price to the shared wallet.
## Trade moves a backpack item into a teammate's backpack (needs free space).

signal trade_done(item: ItemInstance, to_slot_index: int)

var slot: PlayerSlot


static func create(p_slot: PlayerSlot) -> PlayerPanel:
	var panel := PlayerPanel.new()
	panel.slot = p_slot
	return panel


## Rebuilds from slot.player.equipment (call when opening and after external changes).
func refresh() -> void:
	pass


## Whether this panel currently receives the player's input (the Intermission routes input
## between the shared shop cursor and this panel; LB / RB switch).
func set_input_focus(focused: bool) -> void:
	pass


## Called every _process frame by the Intermission while this panel has focus.
func handle_input(input: PlayerInput) -> void:
	pass
