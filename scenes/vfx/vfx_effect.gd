class_name VfxEffect
extends Node3D
## One fire-and-forget effect spawned by [Vfx]. Animates its children in code (no Tweens,
## so tests can step it with _process) and frees itself after [member life] seconds.

enum Kind { TEXT, ARC, SPARK, PUFF, EXPLOSION, TELEGRAPH, LEVEL_UP, SPARKLE, RESURRECT }

var kind: Kind = Kind.SPARK
var life := 0.5
var age := 0.0
## Effect-specific size (radius, text scale ...).
var size := 1.0
var color := Color.WHITE
## Main visual (label, arc mesh, rune quad ...), plus optional extras animated by kind.
var main: Node3D
var ring: GeometryInstance3D
var flash: GeometryInstance3D
var start_pos := Vector3.ZERO
var drift := Vector3.ZERO


func _ready() -> void:
	start_pos = position
	_update(0.0)


func _process(delta: float) -> void:
	age += delta
	_update(clampf(age / maxf(life, 0.001), 0.0, 1.0))
	if age >= life:
		queue_free()


func _exit_tree() -> void:
	if kind == Kind.TEXT:
		Vfx._text_count = maxi(0, Vfx._text_count - 1)


func _update(t: float) -> void:
	match kind:
		Kind.TEXT:
			_update_text(t)
		Kind.ARC:
			var gi := main as GeometryInstance3D
			if gi != null:
				gi.set_instance_shader_parameter(&"arc_progress", smoothstep(0.0, 0.55, t) * 1.25)
				gi.set_instance_shader_parameter(&"arc_fade", 1.0 - smoothstep(0.45, 1.0, t))
		Kind.TELEGRAPH:
			_update_telegraph(t)
		Kind.LEVEL_UP:
			if main != null:
				main.scale = Vector3(1.0 + 0.3 * t, 0.3 + 3.4 * smoothstep(0.0, 0.3, t), 1.0 + 0.3 * t)
				(main as GeometryInstance3D).set_instance_shader_parameter(&"fx_fade", 1.0 - smoothstep(0.45, 1.0, t))
			if flash != null:
				flash.scale = Vector3.ONE * size * lerpf(0.4, 1.3, smoothstep(0.0, 0.2, t))
				flash.set_instance_shader_parameter(&"fx_fade", 1.0 - smoothstep(0.1, 0.5, t))
			_update_ring(t, 0.3, 2.6)
		Kind.RESURRECT:
			if main != null:
				# A shaft of light from the sky: snaps wide, then narrows and fades.
				var w := lerpf(0.25, 1.0, smoothstep(0.0, 0.12, t)) * lerpf(1.0, 0.55, smoothstep(0.35, 1.0, t))
				main.scale = Vector3(w, size, w)
				(main as GeometryInstance3D).set_instance_shader_parameter(&"fx_fade", 1.0 - smoothstep(0.55, 1.0, t))
			if flash != null:
				flash.scale = Vector3.ONE * lerpf(0.3, 0.9, smoothstep(0.0, 0.25, t))
				flash.set_instance_shader_parameter(&"fx_fade", 1.0 - smoothstep(0.2, 0.7, t))
			_update_ring(t, 0.4, 2.2)
		Kind.EXPLOSION:
			if flash != null:
				var e := smoothstep(0.0, 0.3, t)
				flash.scale = Vector3.ONE * size * lerpf(0.3, 1.0, e)
				flash.set_instance_shader_parameter(&"fx_fade", 1.0 - smoothstep(0.25, 0.85, t))
			_update_ring(t, size * 0.4, size * 1.25)
		_:
			if flash != null:
				flash.scale = Vector3.ONE * size * lerpf(1.0, 0.3, t)
				flash.set_instance_shader_parameter(&"fx_fade", 1.0 - smoothstep(0.05, 0.6, t))
			_update_ring(t, size * 0.3, size * 1.4)


func _update_text(t: float) -> void:
	var label := main as Label3D
	if label == null:
		return
	var rise := 1.0 - pow(1.0 - t, 2.5)
	position = start_pos + Vector3(0, 1.1 * rise, 0) + drift * rise
	var pop := 1.0
	if t < 0.12:
		pop = lerpf(0.45, 1.3, t / 0.12)
	elif t < 0.3:
		pop = lerpf(1.3, 1.0, (t - 0.12) / 0.18)
	main.scale = Vector3.ONE * pop
	var alpha := 1.0 - smoothstep(0.6, 1.0, t)
	label.modulate.a = alpha
	label.outline_modulate.a = alpha


func _update_telegraph(t: float) -> void:
	var gi := main as GeometryInstance3D
	if gi == null:
		return
	# The rune lives for `size` seconds of warning plus a short fade.
	var warn := maxf(life - 0.15, 0.001)
	var p := clampf(age / warn, 0.0, 1.0)
	var grow := smoothstep(0.0, 0.18, age)
	var fade := 1.0 - smoothstep(warn, life, age)
	main.scale = Vector3(grow, 1.0, grow) * main.get_meta(&"diameter", 1.0)
	main.rotation.y = age * 0.8
	gi.set_instance_shader_parameter(&"rune_progress", p)
	gi.set_instance_shader_parameter(&"rune_fade", fade * (1.0 + 0.6 * smoothstep(0.85, 1.0, p)))


func _update_ring(t: float, from_r: float, to_r: float) -> void:
	if ring == null:
		return
	var d := lerpf(from_r, to_r, 1.0 - pow(1.0 - t, 3.0)) * 2.0
	ring.scale = Vector3(d, 1.0, d)
	var a := (1.0 - t) * color.a * 0.9
	Mats.set_ring(ring, Color(color.r, color.g, color.b, a), 0.8, 0.97, 0.0)
