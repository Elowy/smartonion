class_name LootRoll
extends RefCounted
## STUB – owned by the "shop-loot" agent. One item's Need / Greed / Pass roll (GDD 10.1).
## Need: only if the class can use it and the backpack has room; Need beats Greed; highest
## 1-100 roll wins, ties re-roll among the tied. Need -> winner's backpack. Greed (no Need) ->
## sold at Items.GREED_SHARE into the shared wallet. All Pass -> item is lost.

enum Choice { UNDECIDED, NEED, GREED, PASS }

var item: ItemInstance
var choices: Dictionary[int, Choice] = {}
var rolls: Dictionary[int, int] = {}
var winner := -1
## &"need", &"greed" or &"pass" after resolve().
var outcome: StringName


static func create(p_item: ItemInstance) -> LootRoll:
	var r := LootRoll.new()
	r.item = p_item
	return r


func can_need(slot: PlayerSlot) -> bool:
	return false


func choose(slot_index: int, choice: Choice) -> void:
	pass


func all_decided(slot_indices: Array[int]) -> bool:
	return false


## Undecided players count as Pass. Fills rolls / winner / outcome.
func resolve(rng: RandomNumberGenerator) -> void:
	pass


## Applies the outcome: Need -> backpack, Greed -> RunState.add_gold(item.greed_value()).
func apply(slots: Array[PlayerSlot]) -> void:
	pass


## What a bot picks: Need if it can use the item and it is an upgrade, else Greed.
static func bot_choice(slot: PlayerSlot, p_item: ItemInstance) -> Choice:
	return Choice.GREED
