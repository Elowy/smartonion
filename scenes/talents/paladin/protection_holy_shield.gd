class_name PaladinProtectionHolyShield
extends TalentEffect
## Holy Shield – the Paladin Protection capstone (GDD 7.5, talents_paladin.md §2.3). The "+20%
## Block with a shield" half is the talent's data entry (stats block_chance, requires shield);
## this script is the rest. Every blocked hit ([method on_avoided] &"block", full or partial):
##   1. retaliation – a live Enemy attacker (melee, or the shooter of a blocked projectile, at
##      any distance) takes weapon_pct % weapon damage + sp_scale x Spell Power as Holy damage
##      (PaladinKit.strike_damage, built from the hero's stats: deal_raw(..., target_bonus =
##      true, &"proc"));
##   2. ally shield – the living ally within ally_range m with the lowest HP share (full HP
##      included, never the Paladin; solo: nobody) gets an absorb shield of ally_shield_pct % of
##      their max HP for ally_shield_duration sec on their ProcSystem under the Paladin's key
##      (PaladinKit.buff_key(paladin, "holy_shield")), so repeated blocks top up one entry up to
##      ally_shield_cap_pct % and refresh its timer. Not power- or Healing-scaled (a shield).
## No icd: blocks are already limited by the after-hit invulnerability. Downed heroes do not
## block. Ally shields go with ProcSystem.begin_wave; the script itself only keeps the beam
## throttle (cleared at wave start / end and teardown). Without a shield nothing blocks (the
## shield's 10% + Block from items), so the capstone mostly does nothing for a Tome Paladin.
## No RNG. Passive for bots.
##
## Params (not rank-scaled; capstone, rank 1): weapon_pct, sp_scale, ally_range,
## ally_shield_pct, ally_shield_cap_pct, ally_shield_duration, beam_interval.

const BEAM_COLOR := Color(1.0, 0.93, 0.65)

## Retaliation strikes and ally shields given (tests, UI).
var retaliations := 0
var ally_shields := 0

var _weapon_pct := 60.0
var _sp_scale := 0.5
var _ally_range := 8.0
var _shield_pct := 2.0
var _cap_pct := 8.0
var _duration := 4.0
var _beam_interval := 0.5
var _key: StringName = &""
## Seconds since setup (the beam throttle's clock).
var _clock := 0.0
## Ally instance id -> _clock of the last beam to them.
var _last_beam: Dictionary[int, float] = {}


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_weapon_pct = num("weapon_pct", 60.0)
	_sp_scale = num("sp_scale", 0.5)
	_ally_range = num("ally_range", 8.0)
	_shield_pct = num("ally_shield_pct", 2.0)
	_cap_pct = num("ally_shield_cap_pct", 8.0)
	_duration = num("ally_shield_duration", 4.0)
	_beam_interval = num("beam_interval", 0.5)
	_key = shield_key(p_player)


## The ally shield's ProcSystem source of [param paladin] (one entry per Paladin).
static func shield_key(paladin: Player) -> StringName:
	return PaladinKit.buff_key(paladin, "holy_shield")


func on_avoided(kind: StringName, attacker: Node3D) -> void:
	if kind != &"block" or player == null or not is_instance_valid(player) or not player.is_alive():
		return
	var shown := player.is_inside_tree()
	if shown:
		Vfx.hit_spark(player.get_chest_position(), PaladinKit.HOLY_COLOR)
	var e: Enemy = attacker as Enemy if attacker != null and is_instance_valid(attacker) else null
	if e != null and not e.is_dead() and player.procs != null:
		retaliations += 1
		if e.is_inside_tree():
			Vfx.hit_spark(e.global_position + Vector3.UP * WeaponRunner.DAMAGE_TEXT_HEIGHT * 0.5, PaladinKit.HOLY_COLOR)
		player.procs.deal_raw(e, PaladinKit.strike_damage(player, _weapon_pct, _sp_scale), PaladinKit.SCHOOL, true, &"proc")
	if shown:
		_shield_ally()


func tick(delta: float) -> void:
	_clock += delta


func begin_wave() -> void:
	_last_beam.clear()


func end_wave() -> void:
	_last_beam.clear()


func teardown() -> void:
	_last_beam.clear()


func describe() -> String:
	return "Holy Shield: %d%% block, retaliation and ally shields" % roundi(player.block_chance() if player != null else 0.0)


## The most wounded ally in range gets (or tops up) the Paladin's absorb shield.
func _shield_ally() -> void:
	var ally := PaladinKit.lowest_hero(player.get_tree(), player.global_position, _ally_range, false, player)
	if ally == null or ally.procs == null:
		return
	var cap := ally.max_hp() * _cap_pct / 100.0
	var amount := minf(ally.max_hp() * _shield_pct / 100.0, cap - ally.procs.shield_of(_key))
	if amount <= 0.0:
		return
	ally.procs.add_shield(amount, _duration, _key, player.slot_index())
	ally_shields += 1
	var id := ally.get_instance_id()
	if _clock - float(_last_beam.get(id, -INF)) >= _beam_interval:
		_last_beam[id] = _clock
		ProcVfx.beam(player.get_chest_position(), ally.get_chest_position(), BEAM_COLOR)
