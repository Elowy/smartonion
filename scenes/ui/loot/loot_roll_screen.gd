class_name LootRollScreen
extends Control
## STUB – owned by the "ui-market" agent. Shared-screen WoW-style Need / Greed / Pass roll
## window (GDD 10.1, 12): items one after another; big tooltip in the middle, a 15 s timer
## bar, one chip per player (colour, upgrade arrow, decided tick, then dice / coin / pass icon
## and the 1-100 roll), message log on the right ("P2 rolls 87 (Need) for [Stormcaller]"),
## "Items: 2 / 5". Per player: A = Need (greyed with reason when not allowed), X = Greed,
## B = Pass, Y = Greed all remaining. Choices stay hidden until everyone decided. Bots decide
## with LootRoll.bot_choice. Solo: Take (A) / Sell (X) / Leave (B).

signal finished


static func create() -> LootRollScreen:
	return LootRollScreen.new()


## Starts rolling [param items] for [param slots]; emits finished when all are resolved.
func open(items: Array[ItemInstance], slots: Array[PlayerSlot]) -> void:
	finished.emit.call_deferred()
