class_name ShamanStormweavingElementalSurge
extends TalentEffect
## Elemental Surge – the Shaman Stormweaving capstone (design_shaman.md 4.4, M8). Abilities never crit, so the
## "guaranteed crits" of the old idea became: every [code]interval[/code] seconds the next [code]casts[/code]
## damaging Shaman abilities deal [code]pct[/code] % more damage. The hub is ShamanMastery (grant_empower /
## take_empower): this script only runs the clock; the six damaging abilities consume one charge each through
## ShamanKit.empower and bake the bonus into everything that cast does (jumps, quake ticks, burns, bites, Storm
## Echo). Totem Rite, Soothing Downpour, totems and Gale Strike never consume a charge.
##
## The clock runs while a wave is on and the Shaman is alive: the first grant comes [code]first_at[/code] seconds
## after the wave starts, then every interval; a grant SETS the charges (never adds). Going down puts the clock
## back to first_at (the hub drops the charges itself); wave start / end clear everything. No RNG, passive for
## bots. Floating text "Elemental Surge!".
##
## Params (not rank-scaled; capstone, rank 1): interval, first_at, casts, pct.

const TEXT := "Elemental Surge!"

## Grants so far (tests, UI).
var grants := 0

var _interval := 20.0
var _first_at := 8.0
var _casts := 3
var _pct := 100.0
var _left := 8.0
var _running := false


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_interval = maxf(0.1, num("interval", 20.0))
	_first_at = maxf(0.0, num("first_at", 8.0))
	_casts = maxi(1, roundi(num("casts", 3.0)))
	_pct = maxf(0.0, num("pct", 100.0))
	_left = _first_at


## Seconds to the next grant (tests, UI).
func time_left() -> float:
	return _left


func tick(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not player.is_alive():
		_left = _first_at
		return
	if not _running:
		return
	_left -= delta
	if _left > 0.0:
		return
	_left += _interval
	if _left <= 0.0:
		_left = _interval
	_grant()


func begin_wave() -> void:
	_running = true
	_left = _first_at


func end_wave() -> void:
	_running = false
	_left = _first_at


func teardown() -> void:
	_running = false
	var m := ShamanKit.mastery_of(player) if player != null and is_instance_valid(player) else null
	if m != null:
		m.clear_empower()


func describe() -> String:
	var m := ShamanKit.mastery_of(player) if player != null and is_instance_valid(player) else null
	if m != null and m.empower_charges > 0:
		return "Elemental Surge: %d empowered casts left" % m.empower_charges
	return "Elemental Surge: next in %d sec" % ceili(maxf(0.0, _left))


func _grant() -> void:
	var m := ShamanKit.mastery_of(player)
	if m == null:
		return
	m.grant_empower(_casts, _pct)
	grants += 1
	if player.is_inside_tree():
		Vfx.floating_text(player.self_text_position(1.0), TEXT, ShamanKit.TEXT_COLOR, Player.SELF_TEXT_SIZE, 1.0)
		Vfx.hit_spark(player.get_chest_position(), ShamanKit.LIGHTNING_COLOR)
