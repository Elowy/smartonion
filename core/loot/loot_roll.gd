class_name LootRoll
extends RefCounted
## One item's Need / Greed / Pass roll (GDD 10.1).
## Need: only if the class can use it and the backpack has room; Need beats Greed; highest
## 1-100 roll wins, ties re-roll among the tied. Need -> winner's backpack. Greed (no Need) ->
## sold at Items.GREED_SHARE into the shared wallet. All Pass -> the item is disenchanted into
## team Arcane Dust (M6 Enchanter.disenchant_lost_item: Common 1 .. Legendary 16; an Artifact is
## lost as before).
##
## Flow: create(item) -> choose(slot, choice) per player (UNDECIDED counts as Pass) ->
## resolve(rng) -> apply(slots). resolve / apply each work once.
##
## - Single player: the UI shows Take (= Need) / Sell (= Greed) / Leave (= Pass); the roll is
##   still made (nobody else to lose against) so every path is the same code.
## - If the Need winner's backpack filled up between the choice and apply() (e.g. two items of
##   a queue), the item is sold for Greed gold instead of being lost; outcome becomes &"greed".

enum Choice { UNDECIDED, NEED, GREED, PASS }

## Re-roll rounds of a tie before the lowest slot index wins (never reached in practice).
const MAX_TIE_ROUNDS := 50

var item: ItemInstance
var choices: Dictionary[int, Choice] = {}
## Slot index -> the player's last roll (the final round's roll for a tie-break).
var rolls: Dictionary[int, int] = {}
var winner := -1
## &"need", &"greed" or &"pass" after resolve().
var outcome: StringName
## Arcane Dust the item became (outcome &"pass", set by apply(); 0 otherwise or for an Artifact).
var dust := 0
## Every roll in order, including tie-break rounds: {"slot": int, "roll": int, "round": int}
## (round 0 = the first roll) - for the "P2 rolls 87 (Need)" message lines.
var roll_history: Array[Dictionary] = []

var _resolved := false
var _applied := false


static func create(p_item: ItemInstance) -> LootRoll:
	var r := LootRoll.new()
	r.item = p_item
	return r


## Need is allowed only for a class that can use the item and a backpack with room.
func can_need(slot: PlayerSlot) -> bool:
	if slot == null or item == null or not item.can_be_used_by(slot.class_data):
		return false
	var equipment := _equipment_of(slot)
	return equipment != null and equipment.has_space()


## Why Need is greyed out for [param slot] ("" if it is allowed): the item's unusable reason
## ("Cannot use Wand", "Classes: Mage" ...) or "Backpack full".
func need_blocked_reason(slot: PlayerSlot) -> String:
	if slot == null or item == null:
		return "No player"
	var why := item.unusable_reason(slot.class_data)
	if why != "":
		return why
	var equipment := _equipment_of(slot)
	if equipment == null or not equipment.has_space():
		return "Backpack full"
	return ""


func choose(slot_index: int, choice: Choice) -> void:
	if _resolved:
		return
	choices[slot_index] = choice


func choice_of(slot_index: int) -> Choice:
	return choices.get(slot_index, Choice.UNDECIDED)


func all_decided(slot_indices: Array[int]) -> bool:
	for i in slot_indices:
		if choice_of(i) == Choice.UNDECIDED:
			return false
	return true


func is_resolved() -> bool:
	return _resolved


## Undecided players count as Pass. Fills rolls / winner / outcome.
func resolve(rng: RandomNumberGenerator) -> void:
	if _resolved:
		return
	_resolved = true
	rolls.clear()
	roll_history.clear()
	winner = -1
	var needers := _with_choice(Choice.NEED)
	var greeders := _with_choice(Choice.GREED)
	if not needers.is_empty():
		outcome = &"need"
		winner = _roll_off(needers, rng)
	elif not greeders.is_empty():
		outcome = &"greed"
		winner = _roll_off(greeders, rng)
	else:
		outcome = &"pass"


## Applies the outcome: Need -> backpack, Greed -> RunState.add_gold(item.greed_value()),
## Pass (everybody) -> the item's Dust into RunState.arcane_dust ([member dust]).
func apply(slots: Array[PlayerSlot]) -> void:
	if not _resolved or _applied or item == null:
		return
	_applied = true
	match outcome:
		&"need":
			var equipment := _equipment_of(_slot_by_index(slots, winner))
			if equipment != null and equipment.add_to_backpack(item):
				RunState.need_wins_by_player[winner] = RunState.need_wins_by_player.get(winner, 0) + 1
			else:
				# No room any more (or the winner left): sell instead of losing the item.
				outcome = &"greed"
				_sell()
		&"greed":
			_sell()
		&"pass":
			dust = Enchanter.disenchant_lost_item(item)


## What a bot picks: Need if it can use the item, has room and the item is an upgrade, else
## Greed. "Upgrade" is the same test bots equip with (Intermission.bot_equip_upgrades):
## ItemTooltip.upgrade_direction against ItemTooltip.equipped_for_compare – weighted stats
## and weapon DPS, not Item Level (a Warrior Greeds a cloth Intellect robe that would replace
## its plate chest).
static func bot_choice(slot: PlayerSlot, p_item: ItemInstance) -> Choice:
	if slot == null or p_item == null or not p_item.can_be_used_by(slot.class_data):
		return Choice.GREED
	var equipment := _equipment_of(slot)
	if equipment == null or not equipment.has_space() or not equipment.can_equip(p_item):
		return Choice.GREED
	var current := ItemTooltip.equipped_for_compare(p_item, equipment)
	if ItemTooltip.upgrade_direction(p_item, current, slot.class_data, equipment) > 0:
		return Choice.NEED
	return Choice.GREED


# --- Internals ---------------------------------------------------------------

func _sell() -> void:
	var gold := item.greed_value()
	RunState.add_gold(gold)
	RunState.greed_gold += gold


func _with_choice(choice: Choice) -> Array[int]:
	var out: Array[int] = []
	for i in choices:
		if choices[i] == choice:
			out.append(i)
	out.sort()
	return out


## Everybody rolls 1-100; the highest wins, ties re-roll among the tied. Returns the winner.
func _roll_off(contenders: Array[int], rng: RandomNumberGenerator) -> int:
	var pool := contenders.duplicate()
	for round_index in MAX_TIE_ROUNDS:
		var best := 0
		var leaders: Array[int] = []
		for i in pool:
			var roll := rng.randi_range(1, 100)
			rolls[i] = roll
			roll_history.append({"slot": i, "roll": roll, "round": round_index})
			if roll > best:
				best = roll
				leaders = [i]
			elif roll == best:
				leaders.append(i)
		if leaders.size() == 1:
			return leaders[0]
		pool = leaders
	return pool[0]


static func _equipment_of(slot: PlayerSlot) -> Equipment:
	if slot == null:
		return null
	var player := slot.player as Player
	return player.equipment if player != null else null


static func _slot_by_index(slots: Array[PlayerSlot], index: int) -> PlayerSlot:
	for s in slots:
		if s != null and s.index == index:
			return s
	return null
