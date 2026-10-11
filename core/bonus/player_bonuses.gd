class_name PlayerBonuses
extends RefCounted
## The bonus-effect engine of one hero (M5, architecture §2.1): [code]player.bonuses[/code].
## Turns bonus-vocabulary entries (BonusVocabulary) into game state. Each source replaces its
## whole entry list:
##   player.bonuses.set_effects(PlayerBonuses.SOURCE_TALENTS, player.talents.effects())
##   player.bonuses.set_effects(PlayerBonuses.SOURCE_SETS, SetBonuses.effects_for(player.equipment))
## Player calls the hooks below (hits, kills, damage taken, casts, avoided hits, wave start /
## end, ticks, teardown) and asks the queries on its hot paths (ability_mods_for, damage_mult,
## damage_taken_mult, crit_forced).
##
## P0 stub: set_effects stores the entries per source and emits [signal changed]; every query
## is neutral ({} / 1.0 / false / no scripts) and the hooks do nothing. T-CORE-A implements the
## engine (kinds stats, ability, damage, damage_taken, script, the "requires" conditions, the
## hand-off of resource entries to ClassResource.set_bonus and of proc entries to
## ProcSystem.set_extra_procs).

## The entries changed (and everything derived from them was rebuilt). Player invalidates the
## ability params on it; kits that cache derived numbers re-read them.
signal changed

const SOURCE_TALENTS := &"talents"
const SOURCE_SETS := &"set_bonus"

var player: Player

## Source -> its entries (as given; "rank" / "id" / "label" set by the source).
var _effects: Dictionary[StringName, Array] = {}


static func create(p_player: Player) -> PlayerBonuses:
	var b := PlayerBonuses.new()
	b.player = p_player
	return b


## Replaces every entry of [param source] with [param entries] and rebuilds.
func set_effects(source: StringName, entries: Array[Dictionary]) -> void:
	_effects[source] = entries.duplicate(true)
	changed.emit()


## The entries [param source] last set (a copy; empty when none).
func effects_of(source: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var list: Array = _effects.get(source, [])
	for e: Dictionary in list:
		out.append(e.duplicate(true))
	return out


## Talent / set ability mods for [param ability_id] (merged like item mods, applied after them
## by Player.ability_mods).
func ability_mods_for(_ability_id: StringName) -> Dictionary:
	return {}


## Outgoing damage multiplier of the "damage" entries and scripts (Player.outgoing_damage_mult).
func damage_mult(_target: Node3D, _school: StringName, _source: StringName) -> float:
	return 1.0


## Incoming damage multiplier of the "damage_taken" entries and scripts (Player.take_damage).
func damage_taken_mult(_kind: StringName, _attacker: Node3D) -> float:
	return 1.0


## True when a script forces the next weapon crit on [param _target] (may be null).
func crit_forced(_target: Node3D) -> bool:
	return false


## The live TalentEffect instances (talents and set bonuses).
func scripts() -> Array[TalentEffect]:
	var out: Array[TalentEffect] = []
	return out


## Every weapon hit: [param _damage] = the base amount (architecture §2.1), [param _first] = the
## attack's ProcGate hit.
func on_hit(_target: Node3D, _damage: float, _is_crit: bool, _first: bool) -> void:
	pass


func on_kill(_enemy: Node3D) -> void:
	pass


func on_damage_taken(_amount: float, _attacker: Node3D) -> void:
	pass


func on_cast(_slot_index: int, _ability: AbilityData) -> void:
	pass


## &"dodge" / &"parry" / &"block".
func on_avoided(_kind: StringName, _attacker: Node3D) -> void:
	pass


func begin_wave() -> void:
	pass


func end_wave() -> void:
	pass


func tick(_delta: float) -> void:
	pass


## The hero is leaving: every script tears down.
func teardown() -> void:
	pass
