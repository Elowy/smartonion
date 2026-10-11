extends TalentEffect
## Test helper (not a test file – no test_ prefix): a TalentEffect "script" entry that records
## every hook PlayerBonuses forwards and answers the queries from its params. Used by
## test_bonus_engine.gd / test_talents_bots.gd:
##   {"kind": "script", "script": PATH, "params": {"mult": 1.2, "taken_mult": 0.5, "force_crit": true}}

const PATH := "res://tests/talent_effect_probe.gd"

## Instances set up / torn down since the last [method reset_counts].
static var created := 0
static var torn_down := 0

## Hook names in call order ("setup", "on_hit", ...).
var calls: Array[String] = []
## [target, damage, is_crit, first] per on_hit.
var hits: Array[Array] = []
var ticked := 0.0
var down := false


static func reset_counts() -> void:
	created = 0
	torn_down = 0


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	created += 1
	calls.append("setup")


func damage_mult(_target: Node3D, _school: StringName, _source: StringName) -> float:
	return num("mult", 1.0)


func damage_taken_mult(_kind: StringName, _attacker: Node3D) -> float:
	return num("taken_mult", 1.0)


func crit_forced(_target: Node3D) -> bool:
	return bool(params.get("force_crit", false))


func on_hit(target: Node3D, damage: float, is_crit: bool, first: bool) -> void:
	calls.append("on_hit")
	hits.append([target, damage, is_crit, first])


func on_kill(_enemy: Node3D) -> void:
	calls.append("on_kill")


func on_damage_taken(_amount: float, _attacker: Node3D) -> void:
	calls.append("on_damage_taken")


func on_cast(_slot_index: int, _ability: AbilityData) -> void:
	calls.append("on_cast")


func on_avoided(kind: StringName, _attacker: Node3D) -> void:
	calls.append("on_avoided:" + kind)


func begin_wave() -> void:
	calls.append("begin_wave")


func end_wave() -> void:
	calls.append("end_wave")


func tick(delta: float) -> void:
	ticked += delta


func teardown() -> void:
	torn_down += 1
	down = true
	calls.append("teardown")
