class_name ShamanWellspringBondTotem
extends TalentEffect
## Bond Totem – the Shaman Wellspring capstone (design_shaman.md 4.4, M8). While a wave runs and the Shaman is
## alive, a Bond Totem (ShamanTotem, element "bond") rises at the Shaman's feet [code]first_at[/code] seconds
## after the wave starts and then every [code]interval[/code] seconds, and stands for [code]duration[/code]
## seconds (ShamanKit.totem_params: Weathered Wood and the set bonus lengthen it). What the totem does is the
## node's own rule (ShamanTotem._step_bond): heroes within [code]radius[/code] m even out their health
## ([code]equalize_pct[/code] % of the gap to the group's average per second) and take
## [code]damage_taken_pct[/code] % less damage.
##
## The Bond Totem is separate from the Totem Rite slot (a Rite cast never replaces it); a new one replaces the
## last one of this script. The timer holds while the Shaman is down (a standing totem keeps working); wave
## start / end and teardown remove the totem. No RNG, passive for bots. Works solo (just the damage reduction).
##
## Params (not rank-scaled; capstone, rank 1): interval, first_at, duration, radius, equalize_pct, tick,
## damage_taken_pct.

const TEXT := "Bond Totem"

## Totems planted so far (tests, UI).
var planted := 0
## The standing Bond Totem (null / freed: none).
var totem: ShamanTotem

var _interval := 25.0
var _first_at := 8.0
var _left := 8.0
var _running := false


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_interval = maxf(0.1, num("interval", 25.0))
	_first_at = maxf(0.0, num("first_at", 8.0))
	_left = _first_at


## Seconds to the next totem (tests, UI).
func time_left() -> float:
	return _left


## The standing totem, or null.
func standing() -> ShamanTotem:
	if totem != null and is_instance_valid(totem) and not totem.dismissed and not totem.is_queued_for_deletion():
		return totem
	return null


func tick(delta: float) -> void:
	if not _running or player == null or not is_instance_valid(player) or not player.is_alive():
		return
	_left -= delta
	if _left > 0.0:
		return
	if _plant():
		_left += _interval
		if _left <= 0.0:
			_left = _interval
	else:
		_left = 0.25  # no arena to plant in right now: try again soon


func begin_wave() -> void:
	_clear()
	_running = true
	_left = _first_at


func end_wave() -> void:
	_clear()
	_running = false
	_left = _first_at


func teardown() -> void:
	_clear()
	_running = false


func describe() -> String:
	var t := standing()
	if t != null:
		return "Bond Totem: %d sec left" % ceili(t.time_left())
	return "Bond Totem: next in %d sec" % ceili(maxf(0.0, _left))


## Plants a Bond Totem at the Shaman's feet (the previous one of this script goes). False without an arena.
func _plant() -> bool:
	if player == null or not player.is_inside_tree():
		return false
	var base: Dictionary = {}
	for key in ["duration", "radius", "equalize_pct", "tick", "damage_taken_pct"]:
		if params.has(key):
			base[key] = params[key]
	var final := ShamanKit.totem_params(player, base)
	var duration := maxf(1.0, float(final.get("duration", 10.0)))
	var t := ShamanTotem.plant(player, &"bond", final, player.global_position, duration, false)
	if not t.is_inside_tree():
		t.free()
		return false
	_clear()
	totem = t
	planted += 1
	Vfx.floating_text(player.self_text_position(1.0), TEXT, ShamanKit.BOND_COLOR, Player.SELF_TEXT_SIZE, 1.0)
	return true


func _clear() -> void:
	if totem != null and is_instance_valid(totem):
		totem.dismiss(true)
	totem = null
