class_name RunPerf
extends RefCounted
## Frame-time statistics of a run, grouped by the number of living enemies (smoke / demo
## logs). Fed by PhysicsClock (per physics tick) and by Main once per frame (engine monitor).
##
## - step: one whole physics tick (node _physics_process + physics server step), measured
##   between the starts of consecutive ticks of the same frame.
## - script: the node _physics_process part only.
## - monitor: Performance.TIME_PHYSICS_PROCESS, i.e. the slowest tick of the last second
##   (Godot refreshes it once per second), sampled every frame.

## Enemy-count bucket size.
const BUCKET := 10
## Samples with at least this share of the peak enemy count count as "at peak".
const PEAK_SHARE := 0.8

enum Kind { STEP, SCRIPT, MONITOR }

var peak_enemies := 0
var step_ms_max := 0.0

## Kind -> [count, sum]
var _total: Dictionary[int, Vector2] = {}
## Kind -> bucket index -> [count, sum]
var _buckets: Dictionary[int, Dictionary] = {}


func sample(kind: Kind, enemies: int, ms: float) -> void:
	peak_enemies = maxi(peak_enemies, enemies)
	if kind == Kind.STEP:
		step_ms_max = maxf(step_ms_max, ms)
	_total[kind] = _total.get(kind, Vector2.ZERO) + Vector2(1.0, ms)
	if not _buckets.has(kind):
		_buckets[kind] = {}
	var b := enemies / BUCKET
	var per: Dictionary = _buckets[kind]
	per[b] = per.get(b, Vector2.ZERO) + Vector2(1.0, ms)


func count(kind: Kind) -> int:
	return int(_total.get(kind, Vector2.ZERO).x)


func average(kind: Kind) -> float:
	var t: Vector2 = _total.get(kind, Vector2.ZERO)
	return t.y / t.x if t.x > 0.0 else 0.0


## Average over the samples taken with >= PEAK_SHARE of the peak enemy count.
func average_at_peak(kind: Kind) -> float:
	var acc := Vector2.ZERO
	var threshold := float(peak_enemies) * PEAK_SHARE
	var per: Dictionary = _buckets.get(kind, {})
	for b: int in per:
		if float((b + 1) * BUCKET) > threshold:
			acc += per[b]
	return acc.y / acc.x if acc.x > 0.0 else 0.0


func to_dict() -> Dictionary:
	return {
		"peak_enemies": peak_enemies,
		"physics_ms_avg": snappedf(average(Kind.STEP), 0.001),
		"physics_ms_at_peak": snappedf(average_at_peak(Kind.STEP), 0.001),
		"physics_ms_max": snappedf(step_ms_max, 0.01),
		"script_ms_at_peak": snappedf(average_at_peak(Kind.SCRIPT), 0.001),
		"monitor_physics_ms_at_peak": snappedf(average_at_peak(Kind.MONITOR), 0.01),
	}


func summary() -> String:
	return "peak %d enemies; physics tick avg %.2f ms, at peak %.2f ms (scripts %.2f), max %.2f; TIME_PHYSICS_PROCESS at peak %.2f ms" % [
		peak_enemies, average(Kind.STEP), average_at_peak(Kind.STEP), average_at_peak(Kind.SCRIPT),
		step_ms_max, average_at_peak(Kind.MONITOR)]
