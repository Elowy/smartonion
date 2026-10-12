class_name WarlockEmbers
extends Node
## Conflagrate's burning ground (M5, Warlock Destruction capstone): a child of a Rain of Fire
## [AbilityArea] whose duration WarlockRainOfFire extended by "ember_duration". When the rain
## part ends ([member rain_left] runs out) it switches its parent area once ([method ignite]):
## damage_per_tick x [member share], slow_pct at least [member slow], no longer following the
## Warlock (Walking Inferno: the ground keeps burning where the rain ended), meta
## [constant META] (WarlockRainOfFire.wants_auto_cast treats the circle as finished, so bots
## rain again instead of waiting for the embers), and the ember look ([WarlockEmberVfx]).
## Freed with the area (the wave end frees every &"ability_areas" node). No RNG.

const META := &"embers"
## Timers within this of zero count as run out (float steps of 1/60 s).
const EPSILON := 0.0001

## Seconds of rain left before the ground starts to burn.
var rain_left := 4.0
## The rain part's length (s): the area burns for its duration minus this.
var rain_duration := 4.0
## Share of the rain's tick damage while burning (0..1).
var share := 0.4
## % slow while burning (the stronger of this and the rain's own slow).
var slow := 30.0
## The area burns (the switch happened).
var burning := false


## Embers that take over after [param p_rain_duration] seconds at [param share_pct] % of the tick
## damage and [param slow_pct] % slow.
static func create(p_rain_duration: float, share_pct: float, slow_pct: float) -> WarlockEmbers:
	var e := WarlockEmbers.new()
	e.name = "Embers"
	e.rain_duration = maxf(0.0, p_rain_duration)
	e.rain_left = e.rain_duration
	e.share = maxf(0.0, share_pct) / 100.0
	e.slow = clampf(slow_pct, 0.0, 90.0)
	return e


func _physics_process(delta: float) -> void:
	if burning:
		return
	rain_left -= delta
	if rain_left <= EPSILON:
		ignite()


## The rain is over: the circle becomes burning ground (once).
func ignite() -> void:
	if burning:
		return
	burning = true
	rain_left = 0.0
	set_physics_process(false)
	var area := get_parent() as AbilityArea
	if area == null:
		return
	area.damage_per_tick *= share
	area.slow_pct = maxf(area.slow_pct, slow)
	area.follow = null
	area.set_meta(META, true)
	if area.is_inside_tree():
		area.add_child(WarlockEmberVfx.create(area.radius, maxf(0.1, area.duration - rain_duration)))
