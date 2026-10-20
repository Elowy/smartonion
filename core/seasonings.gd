class_name Seasonings
extends RefCounted
## The Seasoning rules (M9, design_m9 §3): which Seasonings a hero carries into a run, how they become a bonus
## source, how many slots a class has, and the lobby's pick / toggle logic (the picker UI is SeasoningPicker).
##
## A Seasoning is owned when the main profile owns it (Meta.is_unlocked(&"seasoning", id): the dev and max
## profiles of the automated runs own everything). A hero carries the first [method slot_count] owned Seasonings of
## its own class that its slot lists ([member PlayerSlot.seasonings], from the lobby picker, the profile's
## remembered loadout or --seasonings); [method apply] hands them to the hero's PlayerBonuses as the source
## [constant SOURCE] when the hero is created (Player.create). Nothing happens without a selection, so a run with
## the dev profile is bit-identical to a base run.

## The PlayerBonuses source of the picked Seasonings.
const SOURCE := &"seasoning"
## Seasoning slots a hero can have at most.
const MAX_SLOTS := 3
## Class Level that opens slot 1 / 2 / 3 (design_m9 §1.2).
const SLOT_LEVELS: Array[int] = [3, 10, 20]
## An equipped Seasoning's ability is this many times as likely on a level-up card while the hero has not learned
## it (weights only: the hand draws exactly the same random numbers).
const CARD_WEIGHT_MULT := 3.0

## [method toggle] results.
const RESULT_ADDED := &"added"
const RESULT_REMOVED := &"removed"
## Not owned (locked), not a Seasoning of the slot's class, or every slot is taken.
const RESULT_LOCKED := &"locked"
const RESULT_INVALID := &"invalid"
const RESULT_FULL := &"full"


# --- Slots ----------------------------------------------------------------------------------------------

## The Seasoning slots of [param class_id] for the current profile. The LEVELS package owns the real rule: when
## [code]Meta.seasoning_slots(class_id)[/code] exists it answers (this function then only clamps it); until it
## lands [method fallback_slot_count] does. Once it has landed the fallback and this indirection can be deleted
## (callers: Seasonings.resolve, SeasoningPicker, LobbyCard, tests).
static func slot_count(class_id: StringName) -> int:
	if Meta.has_method(&"seasoning_slots"):
		return clampi(int(Meta.call(&"seasoning_slots", class_id)), 0, MAX_SLOTS)
	return fallback_slot_count(class_id)


## The local stand-in for Meta.seasoning_slots: all slots for a profile with everything unlocked (the dev and max
## profiles), else the design's levels ([constant SLOT_LEVELS]) against the profile's Class Level.
static func fallback_slot_count(class_id: StringName) -> int:
	if Meta.profile == null or Meta.profile.all_unlocked:
		return MAX_SLOTS
	return slots_for_level(Meta.class_level(class_id))


## Slots a class of [param level] has: 1 from Class Level 3, 2 from 10, 3 from 20.
static func slots_for_level(level: int) -> int:
	var n := 0
	for need in SLOT_LEVELS:
		if level >= need:
			n += 1
	return n


# --- What a hero carries --------------------------------------------------------------------------------

## True when the main profile owns [param s] (always for the dev and max profiles).
static func owned(s: SeasoningData) -> bool:
	return s != null and Meta.is_unlocked(Profile.KIND_SEASONING, s.id, s.class_id)


## The Seasonings [param ids] name that [param class_id] can carry: known ids of that class, each once, owned,
## in the order given, at most [method slot_count] of them (an unknown, foreign or locked id is skipped, not counted).
static func resolve(class_id: StringName, ids: Array) -> Array[SeasoningData]:
	var out: Array[SeasoningData] = []
	var limit := slot_count(class_id)
	for raw: Variant in ids:
		if out.size() >= limit:
			break
		var s := Db.get_seasoning(StringName(str(raw)))
		if s == null or s.class_id != class_id or s in out or not owned(s):
			continue
		out.append(s)
	return out


static func ids_of(list: Array[SeasoningData]) -> Array[StringName]:
	var out: Array[StringName] = []
	for s in list:
		out.append(s.id)
	return out


## The BonusVocabulary entries of [param list] (copies, tagged with the Seasoning's id and name like a talent's).
static func effects_for(list: Array[SeasoningData]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in list:
		for e in s.entries:
			var entry: Dictionary = e.duplicate(true)
			entry["id"] = String(s.id)
			entry["label"] = s.display_name
			out.append(entry)
	return out


## Applies the Seasonings of [param player] (its [member Player.seasonings], as the slot gave them): keeps the ones
## it can carry ([method resolve]) and sets them as the bonus source [constant SOURCE]. Nothing is touched when
## there are none.
static func apply(player: Player) -> void:
	if player == null or player.class_data == null:
		return
	var list := resolve(player.class_data.id, player.seasonings)
	player.seasonings = ids_of(list)
	if list.is_empty() or player.bonuses == null:
		return
	player.bonuses.set_effects(SOURCE, effects_for(list))


## The multiplier of [param ability_id]'s level-up card weight for [param player] (LevelUpDeck): [constant
## CARD_WEIGHT_MULT] when one of the hero's Seasonings changes that ability, else 1.
static func card_weight_mult(player: Player, ability_id: StringName) -> float:
	if player == null:
		return 1.0
	for id in player.seasonings:
		var s := Db.get_seasoning(id)
		if s != null and s.ability == ability_id:
			return CARD_WEIGHT_MULT
	return 1.0


# --- The lobby's selection ------------------------------------------------------------------------------

## Puts [param id] on [param slot] or takes it off (the picker's A button). Returns one of the RESULT_ constants;
## a change is remembered for the slot's class (Meta.remember_loadout) and saved, so the choice follows the class
## through class changes and into the next session.
static func toggle(slot: PlayerSlot, id: StringName) -> StringName:
	if slot == null or slot.class_data == null:
		return RESULT_INVALID
	if id in slot.seasonings:
		slot.seasonings.erase(id)
		_remember(slot)
		return RESULT_REMOVED
	var s := Db.get_seasoning(id)
	if s == null or s.class_id != slot.class_data.id:
		return RESULT_INVALID
	if not owned(s):
		return RESULT_LOCKED
	if slot.seasonings.size() >= slot_count(s.class_id):
		return RESULT_FULL
	slot.seasonings.append(id)
	_remember(slot)
	return RESULT_ADDED


## Drops from [param slot] what its class cannot carry (after a class change: another class's Seasonings, locked
## ones, more than the slots allow).
static func prune(slot: PlayerSlot) -> void:
	if slot == null or slot.class_data == null:
		return
	slot.seasonings = ids_of(resolve(slot.class_data.id, slot.seasonings))


static func _remember(slot: PlayerSlot) -> void:
	Meta.remember_loadout(slot)
	Meta.save()
