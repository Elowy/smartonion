class_name Shop
extends RefCounted
## STUB – owned by the "shop-loot" agent. The shared shop (GDD 10): one goblin stall for the
## whole team, offers = 2 + 2 x players (4 / 6 / 8 / 10), at least 1-2 offers each player's
## class can use, shared wallet, locks, pings ("P2 wants"), reroll only when EVERY joined
## player voted; locked and pinged offers survive a reroll; max Epic.

signal changed

class Offer:
	var item: ItemInstance
	var price := 0
	var sold := false
	## Slot index that locked it, -1 = not locked.
	var locked_by := -1
	## Slot indices that pinged it ("P2 wants").
	var pinged_by: Array[int] = []

var offers: Array[Offer] = []
## Slot index -> voted for a reroll this round.
var reroll_votes: Dictionary[int, bool] = {}
var rerolls_this_round := 0
var wave := 1


static func offer_count(players: int) -> int:
	return 2 + 2 * clampi(players, 1, 4)


## New round after a wave: keeps locked offers, fills the rest, clears votes and pings.
func open_round(p_wave: int, slots: Array[PlayerSlot], rng: RandomNumberGenerator) -> void:
	pass


## Cost of the next reroll: wave x 2 + 2, +2 for every reroll already done this round.
func reroll_cost() -> int:
	return wave * 2 + 2 + 2 * rerolls_this_round


## Buys offer [param index] for [param slot] (shared wallet, item into that player's backpack).
func buy(index: int, slot: PlayerSlot) -> bool:
	return false


func toggle_lock(index: int, slot_index: int) -> void:
	pass


func toggle_ping(index: int, slot_index: int) -> void:
	pass


## Toggles [param slot_index]'s reroll vote; rerolls (and returns true) once every index in
## [param joined] voted and the wallet can pay.
func vote_reroll(slot_index: int, joined: Array[int], rng: RandomNumberGenerator) -> bool:
	return false
