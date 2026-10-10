class_name ItemTooltip
extends PanelContainer
## STUB – owned by the "ui-items" agent. WoW-style item tooltip (GDD 12): name in rarity
## colour, "Looted", Item Level, slot + armor type (red if the viewer cannot wear it),
## weapon damage / speed, white stat lines, green enchant lines (EnchantRoll.description()),
## unique effect line, "Classes: X", flavor text, price / sell value, and a comparison block
## against the viewer's equipped item (+green / -red per stat).


static func create() -> ItemTooltip:
	return ItemTooltip.new()


## [param viewer] decides red "cannot use" lines; [param compare] (may be null) is the
## currently equipped item for the comparison block; [param price] > 0 shows a buy price.
func show_item(item: ItemInstance, viewer: ClassData = null, compare: ItemInstance = null, price: int = 0) -> void:
	pass


## Stat differences equipping [param item] instead of [param equipped] would make (by stat id).
static func stat_delta(item: ItemInstance, equipped: ItemInstance) -> Dictionary[StringName, float]:
	return {}


## Simple "is it an upgrade" heuristic used by badges and bots: +1 better, -1 worse, 0 unclear.
static func upgrade_direction(item: ItemInstance, equipped: ItemInstance, viewer: ClassData) -> int:
	return 0
