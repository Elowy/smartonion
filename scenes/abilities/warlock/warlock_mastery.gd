class_name WarlockMastery
extends MasteryEffect
## Warlock class hooks (GDD 3.5): Mastery "Demonic Pact" (+% damage of DoTs and pets per
## Mastery point), the permanent Imp pet and the Soul Shard rule of Soulbinder's Sash.
##
## The Imp ([WarlockImp]) is spawned lazily from [method tick] (a physics tick – never while a
## parent is busy setting up children) once the Warlock is in the tree and alive, survives
## waves, hides itself while the Warlock is downed and is freed in [method teardown].
##
## Soul Shards: +1 every ResourceData.gain_per_kills kills (soul_shards.tres: 12), counted by
## ClassResource. Items change the rule through ability_mod on the pseudo ability
## [constant SHARDS_MOD_ID] (Soulbinder's Sash: {"gain_per_kills": 8}); the Warlock's shard
## resource then runs on a private copy of the ResourceData with the modded numbers. Talent
## "resource" entries (Soul Harvest: gain_per_kills_add) stay in ClassResource.bonus and apply
## on top of whichever copy is in place ([method kills_per_shard] reads the effective rule).
##
## Afflictions (M5 talents, pseudo ability [constant AFFLICTIONS_MOD_ID] – talent / item mods
## on [constant AFFLICTION_BASE], read through [method affliction_params]): Curse of Agony
## ("agony_pct" > 0) makes every weapon hit of the Warlock curse its target with Agony –
## agony_pct % of the hit's base amount (Player.last_hit_base, not the dealt amount: the
## derived-damage rule, talent_vocabulary §3.6) as Shadow damage over agony_duration seconds
## (WarlockAfflictions.agonize); Writhe in Agony ("agony_spread") splits a dying host's curse;
## Curse of Exhaustion ("slow") slows every afflicted enemy. Agony is cleared, without
## spreading, at wave start and end.

## Demonic Pact: % more DoT and pet damage per Mastery point.
const PCT_PER_POINT := 2.0
## Pseudo ability id whose ability_mod items change the Soul Shard rule.
const SHARDS_MOD_ID := &"warlock_shards"
const SHARD_RESOURCE := &"soul_shard"
## Pseudo ability id of the affliction numbers (BonusVocabulary.PSEUDO_IDS).
const AFFLICTIONS_MOD_ID := &"warlock_afflictions"
## The affliction numbers before talent / item mods (all neutral: no Agony, no slow).
const AFFLICTION_BASE := {
	## % of each weapon hit's base amount that becomes Agony (0 = no Agony; Curse of Agony).
	"agony_pct": 0.0,
	## Seconds an Agony lasts (a new hit restarts it).
	"agony_duration": 6.0,
	## Enemies a dying host's Agony is split between (Writhe in Agony).
	"agony_spread": 0.0,
	## m (x Area Size) around the corpse the split looks for enemies.
	"agony_spread_radius": 4.0,
	## % slow of every affliction of this Warlock (Curse of Exhaustion).
	"slow": 0.0,
}

var imp: WarlockImp

var _base_shard_data: ResourceData
var _equipment: Equipment
var _bonuses: PlayerBonuses
## affliction_params() result (read-only), dropped when the bonuses / equipment change.
var _affliction_params: Dictionary = {}
var _affliction_slow := 0.0
var _agony_pct := 0.0


## Damage multiplier of Demonic Pact for DoTs and pets (1 + Mastery x 2%).
func pact_mult() -> float:
	return maxf(0.0, 1.0 + mastery() * PCT_PER_POINT / 100.0)


func damage_mult(_target: Node3D, _school: StringName, source: StringName) -> float:
	if source == &"dot" or source == &"pet":
		return pact_mult()
	return 1.0


## Also runs while the Warlock is downed (MasteryEffect.tick): no Imp is summoned then (an
## existing one hides and stops shooting by itself, WarlockImp._physics_process).
func tick(_delta: float) -> void:
	_hook_equipment()
	if player != null and player.is_alive():
		ensure_imp()


## Curse of Agony: a weapon hit of the (living) Warlock curses its target – agony_pct % of the
## hit's base amount (Player.last_hit_base, valid during on_hit_dealt) over agony_duration
## seconds. Every hit counts: pierced / arced enemies and extra attacks too.
func on_hit(target: Node3D, damage: float, _is_crit: bool) -> void:
	if _agony_pct <= 0.0 and _affliction_params.is_empty():
		affliction_params()
	if _agony_pct <= 0.0 or damage <= 0.0 or player == null:
		return
	var e := target as Enemy
	if not WarlockSpell.is_live(e):
		return
	var params := affliction_params()
	var total := maxf(0.0, player.last_hit_base) * _agony_pct / 100.0
	var aff := WarlockAfflictions.of(player)
	if aff == null or total <= 0.0:
		return
	aff.agonize(e, total, float(params["agony_duration"]), roundi(float(params["agony_spread"])),
			WarlockSpell.area(player.stats, float(params["agony_spread_radius"])))


## The affliction numbers: [constant AFFLICTION_BASE] with the talent / item mods of
## [constant AFFLICTIONS_MOD_ID]. Cached (read-only) until the bonuses or the equipment change.
func affliction_params() -> Dictionary:
	_hook_bonuses()
	if not _affliction_params.is_empty():
		return _affliction_params
	var mods: Dictionary = player.ability_mods(AFFLICTIONS_MOD_ID) if player != null else {}
	var out := AbilityRunner.apply_mods(AFFLICTION_BASE, mods)
	out.make_read_only()
	_affliction_params = out
	_affliction_slow = maxf(0.0, float(out.get("slow", 0.0)))
	_agony_pct = maxf(0.0, float(out.get("agony_pct", 0.0)))
	return out


## Curse of Exhaustion: % slow of every affliction (0 = none).
func affliction_slow() -> float:
	affliction_params()
	return _affliction_slow


## Drops the cached affliction numbers (the bonuses or the equipment changed).
func invalidate_affliction_params() -> void:
	_affliction_params = {}
	_affliction_slow = 0.0
	_agony_pct = 0.0


func on_kill(_enemy: Node3D) -> void:
	_hook_equipment()


func begin_wave() -> void:
	_hook_equipment()
	_clear_agony()
	if has_imp():
		imp.begin_wave()


## Wave cleared: no Agony carries over (cleared without spreading).
func end_wave() -> void:
	_clear_agony()


func teardown() -> void:
	if has_imp():
		imp.queue_free()
	imp = null
	if _equipment != null and _equipment.changed.is_connected(refresh_shard_rule):
		_equipment.changed.disconnect(refresh_shard_rule)
	if _equipment != null and _equipment.changed.is_connected(invalidate_affliction_params):
		_equipment.changed.disconnect(invalidate_affliction_params)
	_equipment = null
	if _bonuses != null and _bonuses.changed.is_connected(invalidate_affliction_params):
		_bonuses.changed.disconnect(invalidate_affliction_params)
	_bonuses = null
	invalidate_affliction_params()
	var res := shard_resource()
	if res != null and _base_shard_data != null:
		res.data = _base_shard_data


func describe() -> String:
	return "Ember Pact: +%s%% damage over time and pet damage" % _fmt(mastery() * PCT_PER_POINT)


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


## Kills per Soul Shard right now (12, Soulbinder's Sash: 8; talent "gain_per_kills_add"
## bonuses included – ClassResource.gain_per_kills).
func kills_per_shard() -> int:
	var res := shard_resource()
	return res.gain_per_kills() if res != null and res.data != null else 0


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
	if _equipment != null and _equipment.changed.is_connected(invalidate_affliction_params):
		_equipment.changed.disconnect(invalidate_affliction_params)
	_equipment = player.equipment
	_equipment.changed.connect(refresh_shard_rule)
	_equipment.changed.connect(invalidate_affliction_params)
	invalidate_affliction_params()
	refresh_shard_rule()


## Connects to the player's PlayerBonuses (created after the Mastery): talent / set changes
## drop the cached affliction numbers.
func _hook_bonuses() -> void:
	if player == null or player.bonuses == null or _bonuses == player.bonuses:
		return
	if _bonuses != null and _bonuses.changed.is_connected(invalidate_affliction_params):
		_bonuses.changed.disconnect(invalidate_affliction_params)
	_bonuses = player.bonuses
	_bonuses.changed.connect(invalidate_affliction_params)
	invalidate_affliction_params()


func _clear_agony() -> void:
	var aff := WarlockAfflictions.of(player, false) if player != null else null
	if aff != null:
		aff.clear(WarlockAfflictions.AGONY)


static func _fmt(v: float) -> String:
	return str(int(roundf(v))) if is_equal_approx(v, roundf(v)) else "%.1f" % v
