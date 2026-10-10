class_name WarlockMastery
extends MasteryEffect
## Warlock class hooks (GDD 3.5): Mastery "Demonic Pact" (+% damage of DoTs and pets per
## Mastery point), the permanent Imp pet and the Soul Shard rule of Soulbinder's Sash.
##
## The Imp ([WarlockImp]) is spawned lazily from [method tick] (a physics tick – never while a
## parent is busy setting up children) once the Warlock is in the tree, survives waves, hides
## itself while the Warlock is downed and is freed in [method teardown].
##
## Soul Shards: +1 every ResourceData.gain_per_kills kills (soul_shards.tres: 12), counted by
## ClassResource. Items change the rule through ability_mod on the pseudo ability
## [constant SHARDS_MOD_ID] (Soulbinder's Sash: {"gain_per_kills": 8}); the Warlock's shard
## resource then runs on a private copy of the ResourceData with the modded numbers.

## Demonic Pact: % more DoT and pet damage per Mastery point.
const PCT_PER_POINT := 2.0
## Pseudo ability id whose ability_mod items change the Soul Shard rule.
const SHARDS_MOD_ID := &"warlock_shards"
const SHARD_RESOURCE := &"soul_shard"

var imp: WarlockImp

var _base_shard_data: ResourceData
var _equipment: Equipment


func setup(p_player: Player) -> void:
	super.setup(p_player)


## Damage multiplier of Demonic Pact for DoTs and pets (1 + Mastery x 2%).
func pact_mult() -> float:
	return maxf(0.0, 1.0 + mastery() * PCT_PER_POINT / 100.0)


func damage_mult(_target: Node3D, _school: StringName, source: StringName) -> float:
	if source == &"dot" or source == &"pet":
		return pact_mult()
	return 1.0


func tick(_delta: float) -> void:
	_hook_equipment()
	ensure_imp()


func on_kill(_enemy: Node3D) -> void:
	_hook_equipment()


func begin_wave() -> void:
	_hook_equipment()
	if has_imp():
		imp.begin_wave()


func teardown() -> void:
	if has_imp():
		imp.queue_free()
	imp = null
	if _equipment != null and _equipment.changed.is_connected(refresh_shard_rule):
		_equipment.changed.disconnect(refresh_shard_rule)
	_equipment = null
	var res := shard_resource()
	if res != null and _base_shard_data != null:
		res.data = _base_shard_data


func describe() -> String:
	return "Demonic Pact: +%s%% damage over time and pet damage" % _fmt(mastery() * PCT_PER_POINT)


func has_imp() -> bool:
	return imp != null and is_instance_valid(imp) and not imp.is_queued_for_deletion()


## Spawns the Imp next to the Warlock when it has none (Warlock in the tree). Returns it.
func ensure_imp() -> WarlockImp:
	if has_imp():
		return imp
	imp = null
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return null
	var spawned := WarlockImp.spawn(player)
	if not spawned.is_inside_tree():
		spawned.free()
		return null
	imp = spawned
	return imp


func shard_resource() -> ClassResource:
	if player == null or player.abilities == null:
		return null
	return player.abilities.get_resource(SHARD_RESOURCE)


## Kills per Soul Shard right now (12, Soulbinder's Sash: 8).
func kills_per_shard() -> int:
	var res := shard_resource()
	return res.data.gain_per_kills if res != null and res.data != null else 0


## Re-reads the shard rule from the equipped items (on equipment.changed). Items may change
## gain_per_kills and gain_per_kills_amount (usual _add / _pct / replace keys).
func refresh_shard_rule() -> void:
	var res := shard_resource()
	if res == null or res.data == null:
		return
	if _base_shard_data == null:
		_base_shard_data = res.data
	var mods: Dictionary = player.ability_mods(SHARDS_MOD_ID) if player != null else {}
	if mods.is_empty():
		res.data = _base_shard_data
		return
	var base := {
		"gain_per_kills": float(_base_shard_data.gain_per_kills),
		"gain_per_kills_amount": _base_shard_data.gain_per_kills_amount,
	}
	var rule := AbilityRunner.apply_mods(base, mods)
	var kills := maxi(1, roundi(float(rule["gain_per_kills"])))
	var amount := float(rule["gain_per_kills_amount"])
	if kills == _base_shard_data.gain_per_kills and is_equal_approx(amount, _base_shard_data.gain_per_kills_amount):
		res.data = _base_shard_data
		return
	if res.data != _base_shard_data and res.data.gain_per_kills == kills \
			and is_equal_approx(res.data.gain_per_kills_amount, amount):
		return
	var data := _base_shard_data.duplicate() as ResourceData
	data.gain_per_kills = kills
	data.gain_per_kills_amount = amount
	res.data = data


## Connects to the player's Equipment (it does not exist yet when setup() runs).
func _hook_equipment() -> void:
	if player == null or player.equipment == null or _equipment == player.equipment:
		return
	if _equipment != null and _equipment.changed.is_connected(refresh_shard_rule):
		_equipment.changed.disconnect(refresh_shard_rule)
	_equipment = player.equipment
	_equipment.changed.connect(refresh_shard_rule)
	refresh_shard_rule()


static func _fmt(v: float) -> String:
	return str(int(roundf(v))) if is_equal_approx(v, roundf(v)) else "%.1f" % v
