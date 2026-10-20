class_name HunterPacklordPackFrenzy
extends TalentEffect
## Pack Frenzy – the Hunter Packlord capstone (design_hunter 4.1): the first time [code]first_at[/code]
## (5) s into a wave, then every [code]interval[/code] (30) s after the previous start, the companion
## goes into a frenzy for [code]duration[/code] (10) s: [code]damage_pct[/code] (+50) % damage and
## [code]haste_pct[/code] (+30) % attack speed. The numbers live on the companion
## ([member HunterCompanion.frenzy_left], [member HunterCompanion.frenzy_damage_pct],
## [member HunterCompanion.frenzy_haste_pct]: its damage and attack interval maths read them, the
## model glows while the frenzy lasts), so Hunt Signal's blow, bleed and splash, the Boar's charge
## and the Owl's bolts all ride the frenzy. The GDD's "cannot be slowed" is dropped (the companion
## cannot be hit or slowed at all); the attack-speed bonus replaces it.
##
## The clock counts from the wave start (begin_wave resets it; it only runs inside a wave, so the
## market never sees a frenzy) and keeps running while the Hunter is down – a frenzy that comes due
## then is simply missed, the next one is still on time. A frenzy in progress ends when the wave ends
## and on teardown. No RNG; passive for bots.
##
## Params (not rank-scaled; capstone, rank 1): interval, duration, damage_pct, haste_pct, first_at.

const TEXT := "Pack Frenzy!"
const TEXT_COLOR := Color(1.0, 0.72, 0.28)

## Frenzies started this wave (tests, UI).
var frenzies := 0

var _interval := 30.0
var _duration := 10.0
var _damage_pct := 50.0
var _haste_pct := 30.0
var _first_at := 5.0
## True from the wave start to the wave end.
var _in_wave := false
## Seconds into the wave and when the next frenzy comes due.
var _clock := 0.0
var _next_at := 5.0


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_interval = maxf(0.5, num("interval", 30.0))
	_duration = maxf(0.0, num("duration", 10.0))
	_damage_pct = num("damage_pct", 50.0)
	_haste_pct = num("haste_pct", 30.0)
	_first_at = maxf(0.0, num("first_at", 5.0))
	_next_at = _first_at


## Seconds until the next frenzy is due (0 once it is due; INF outside a wave).
func time_to_next() -> float:
	return maxf(0.0, _next_at - _clock) if _in_wave else INF


## True while the companion is in the frenzy this script started.
func is_active() -> bool:
	var pet := _pet()
	return pet != null and pet.frenzy_left > 0.0


func tick(delta: float) -> void:
	if not _in_wave or player == null or not is_instance_valid(player):
		return
	_clock += delta
	while _clock >= _next_at:
		_next_at += _interval
		_start_frenzy()


func begin_wave() -> void:
	_clear()
	_in_wave = true
	_clock = 0.0
	_next_at = _first_at
	frenzies = 0


func end_wave() -> void:
	_in_wave = false
	_clear()


func teardown() -> void:
	_in_wave = false
	_clear()


func describe() -> String:
	if is_active():
		return "Pack Frenzy: %s sec left" % TalentData.format_number(snappedf(_pet().frenzy_left, 0.1))
	if _in_wave:
		return "Pack Frenzy in %s sec" % TalentData.format_number(snappedf(time_to_next(), 0.1))
	return "Pack Frenzy: every %s sec" % TalentData.format_number(_interval)


## The companion goes wild (nothing while the Hunter is down or has none out).
func _start_frenzy() -> void:
	if not player.is_alive():
		return
	var pet := _pet()
	if pet == null or pet.is_hidden():
		return
	pet.frenzy_left = _duration
	pet.frenzy_damage_pct = _damage_pct
	pet.frenzy_haste_pct = _haste_pct
	frenzies += 1
	if player.is_inside_tree():
		Vfx.floating_text(player.self_text_position(1.0), TEXT, TEXT_COLOR, Player.SELF_TEXT_SIZE, 1.0)


## Ends the frenzy this script gave the companion.
func _clear() -> void:
	var pet := _pet()
	if pet != null:
		pet.frenzy_left = 0.0
		pet.frenzy_damage_pct = 0.0
		pet.frenzy_haste_pct = 0.0


func _pet() -> HunterCompanion:
	return HunterKit.companion(player) if player != null and is_instance_valid(player) else null
