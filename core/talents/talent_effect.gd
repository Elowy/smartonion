class_name TalentEffect
extends RefCounted
## Base class of custom talent / set-bonus behaviour (M5): the "script" kind of the bonus
## vocabulary ({"kind": "script", "script": "res://scenes/talents/<class>/<tree>_<name>.gd",
## "params": {...}}). One instance per hero and entry; PlayerBonuses creates it when the talent
## is taken (setup), forwards the Player hooks below and calls teardown() when it is removed
## (undo, reset, the hero is freed). Scripts are named <Class><Tree><Name> and live under
## scenes/talents/<class>/ (talent_vocabulary.md §3.7).
##
## Rules: [member params] are NOT rank-scaled (use [member rank]); no await; all randomness via
## RunState.rng; damage only through player.procs.deal_raw (derived from a weapon hit: from the
## base amount with target_bonus = false – vocabulary §3.6); hot-path hooks (damage_mult,
## damage_taken_mult, crit_forced) must not allocate or scan the tree; teardown() undoes
## everything setup and the hooks added (stat sources, damage_mults keys, death_guards, nodes).

var player: Player
var rank := 1
## As authored in the entry (numbers NOT rank-scaled – use [member rank]).
var params: Dictionary = {}
## The talent id / set bonus id ("<set_id>:<pieces>") this instance belongs to.
var source_id: StringName


## The entry was applied. Subclasses call super() first, then add guards / connect signals.
func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	player = p_player
	rank = p_rank
	params = p_params


## Numeric param [param key] ([param default] when missing or not a number).
func num(key: String, default: float = 0.0) -> float:
	var v: Variant = params.get(key, default)
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else default


## Outgoing damage multiplier for one hit (every hit – hot path). [param source]: &"weapon",
## &"ability", &"dot", &"pet", &"proc"; [param target] may be null.
func damage_mult(_target: Node3D, _school: StringName, _source: StringName) -> float:
	return 1.0


## Incoming damage multiplier (CombatMath.KIND_* [param _kind]; [param _attacker] may be null).
func damage_taken_mult(_kind: StringName, _attacker: Node3D) -> float:
	return 1.0


## True to turn the next weapon crit roll into a crit (weapon hits and kits that ask).
## [param _target] may be null (thrown knives roll at throw time) – answer sensibly for null.
func crit_forced(_target: Node3D) -> bool:
	return false


## Every weapon hit (after the on-hit procs). [param _damage] = the hit's base amount (after
## the crit, before Executioner / Slayer and the outgoing multipliers – vocabulary §3.6);
## [param _first] = the first hit of its attack (the ProcGate hit): roll chances and count
## attacks only when it is true.
func on_hit(_target: Node3D, _damage: float, _is_crit: bool, _first: bool) -> void:
	pass


## The hero killed [param _enemy] (alive heroes only).
func on_kill(_enemy: Node3D) -> void:
	pass


## Damage landed on the hero (after armour, shields and multipliers).
func on_damage_taken(_amount: float, _attacker: Node3D) -> void:
	pass


## One of the hero's abilities was cast from slot [param _slot_index].
func on_cast(_slot_index: int, _ability: AbilityData) -> void:
	pass


## The hero avoided a hit: [param _kind] &"dodge" / &"parry" / &"block" (a block still lets
## part of the hit through). [param _attacker] may be null.
func on_avoided(_kind: StringName, _attacker: Node3D) -> void:
	pass


## Wave start, after the class resources and procs were reset.
func begin_wave() -> void:
	pass


## Wave cleared, before the market: drop temporary looks / auras.
func end_wave() -> void:
	pass


## Every physics tick – also while the hero is downed (check player.is_alive()).
func tick(_delta: float) -> void:
	pass


## Removed (undo, reset) or the hero is freed: undo everything setup / the hooks added.
func teardown() -> void:
	pass


## Optional UI text.
func describe() -> String:
	return ""
