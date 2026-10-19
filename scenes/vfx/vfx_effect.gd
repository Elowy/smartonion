class_name VfxEffect
extends Node3D
## One fire-and-forget effect spawned by [Vfx]. Animates its children in code (no Tweens,
## so tests can step it with _process) and frees itself after [member life] seconds.

## M7b: ENTRANCE (a boss arrives: main = rune, flash = light column, ring) and REMAINS (a boss died:
## flash = the lingering glow, ring).
enum Kind { TEXT, ARC, SPARK, PUFF, EXPLOSION, TELEGRAPH, LEVEL_UP, SPARKLE, RESURRECT, ENTRANCE, REMAINS }

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
## Damage numbers: the shown amount and the merge key (target instance id, 0 = none).
var amount := 0.0
var merge_key := 0
## Seconds since the last (re)pop of a text (a merged hit pops the number again).
var _pop_age := 0.0


## Sets a shader parameter on [param gi]'s own material (VFX parts never share one).
static func param(gi: GeometryInstance3D, name: StringName, value: Variant) -> void:
	var m := gi.material_override as ShaderMaterial if gi != null else null
	if m != null:
		m.set_shader_parameter(name, value)


func _ready() -> void:
	start_pos = position
	_update(0.0)


func _process(delta: float) -> void:
	age += delta
	_pop_age += delta
	_update(clampf(age / maxf(life, 0.001), 0.0, 1.0))
	if age >= life:
		queue_free()


## A merged hit: pop the number again (it keeps rising along its arc).
func repop() -> void:
	_pop_age = 0.0


func _exit_tree() -> void:
	if kind == Kind.SPARK:
		Vfx._spark_alive = maxi(0, Vfx._spark_alive - 1)
	if kind == Kind.TEXT:
		Vfx._text_count = maxi(0, Vfx._text_count - 1)
		if merge_key != 0 and Vfx._merge.get(merge_key) == self:
			Vfx._merge.erase(merge_key)


func _update(t: float) -> void:
	match kind:
		Kind.TEXT:
			_update_text(t)
		Kind.ARC:
			var gi := main as GeometryInstance3D
			if gi != null:
				param(gi, &"arc_progress", smoothstep(0.0, 0.55, t) * 1.25)
				param(gi, &"arc_fade", 1.0 - smoothstep(0.45, 1.0, t))
		Kind.TELEGRAPH:
			_update_telegraph(t)
		Kind.LEVEL_UP:
			if main != null:
				main.scale = Vector3(1.0 + 0.3 * t, 0.3 + 3.4 * smoothstep(0.0, 0.3, t), 1.0 + 0.3 * t)
				param(main as GeometryInstance3D, &"fx_fade", 1.0 - smoothstep(0.45, 1.0, t))
			if flash != null:
				flash.scale = Vector3.ONE * size * lerpf(0.4, 1.3, smoothstep(0.0, 0.2, t))
				param(flash, &"fx_fade", 1.0 - smoothstep(0.1, 0.5, t))
			_update_ring(t, 0.3, 2.6)
		Kind.RESURRECT:
			if main != null:
				# A shaft of light from the sky: snaps wide, then narrows and fades.
				var w := lerpf(0.25, 1.0, smoothstep(0.0, 0.12, t)) * lerpf(1.0, 0.55, smoothstep(0.35, 1.0, t))
				main.scale = Vector3(w, size, w)
				param(main as GeometryInstance3D, &"fx_fade", 1.0 - smoothstep(0.55, 1.0, t))
			if flash != null:
				flash.scale = Vector3.ONE * lerpf(0.3, 0.9, smoothstep(0.0, 0.25, t))
				param(flash, &"fx_fade", 1.0 - smoothstep(0.2, 0.7, t))
			_update_ring(t, 0.4, 2.2)
		Kind.ENTRANCE:
			_update_entrance(t)
		Kind.REMAINS:
			if flash != null:
				# A glow that lingers, breathing, over where the boss fell.
				var breathe := 1.0 + 0.12 * sin(age * 5.0)
				flash.scale = Vector3.ONE * size * lerpf(0.9, 1.5, smoothstep(0.0, 0.5, t)) * breathe
				param(flash, &"fx_fade", 1.0 - smoothstep(0.45, 1.0, t))
			_update_ring(t, size * 0.5, size * 2.4)
		Kind.EXPLOSION:
			if flash != null:
				var e := smoothstep(0.0, Vfx.EXPLOSION_FLASH_TIME, age)
				flash.scale = Vector3.ONE * size * Vfx.EXPLOSION_FLASH_SCALE * lerpf(0.5, 1.0, e)
				param(flash, &"fx_fade", 1.0 - smoothstep(Vfx.EXPLOSION_FLASH_TIME * 0.3, Vfx.EXPLOSION_FLASH_TIME, age))
				flash.visible = age < Vfx.EXPLOSION_FLASH_TIME
			_update_ring(t, size * 0.4, size * 1.25)
		_:
			if flash != null:
				flash.scale = Vector3.ONE * size * lerpf(1.0, 0.3, t)
				param(flash, &"fx_fade", 1.0 - smoothstep(0.05, 0.6, t))
			_update_ring(t, size * 0.3, size * 1.4)


func _update_text(t: float) -> void:
	var label := main as Label3D
	if label == null:
		return
	# WoW scrolling combat text: a quick rise that bends sideways (an arc), not a straight line.
	var rise := 1.0 - pow(1.0 - t, 2.2)
	var side := t * t * (3.0 - 2.0 * t)
	position = start_pos + Vector3(0, 0.95 * rise, 0) + drift * side
	# Pop-in: overshoot then settle (bigger kick for crits); merged hits pop again.
	var p := _pop_age
	var kick := 0.3 if size <= 1.0 else 0.5
	var pop := 1.0
	if p < 0.06:
		pop = lerpf(0.35, 1.0 + kick, p / 0.06)
	elif p < 0.18:
		pop = lerpf(1.0 + kick, 1.0, (p - 0.06) / 0.12)
	main.scale = Vector3.ONE * pop
	var alpha := (1.0 - smoothstep(0.6, 1.0, t)) * color.a
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
	param(gi, &"rune_progress", p)
	param(gi, &"rune_fade", fade * (1.0 + 0.6 * smoothstep(0.85, 1.0, p)))


func _update_entrance(t: float) -> void:
	# The rune flares open and spins while it fades; the light column shoots up, then thins out.
	if main != null:
		var d: float = main.get_meta(&"diameter", 1.0)
		var g := lerpf(0.5, 1.0, 1.0 - pow(1.0 - t, 3.0))
		main.scale = Vector3(g, 1.0, g) * d
		main.rotation.y = age * 1.6
		param(main as GeometryInstance3D, &"rune_progress", 1.0)
		param(main as GeometryInstance3D, &"rune_fade", (1.0 - smoothstep(0.3, 1.0, t)) * 1.5)
	if flash != null:
		var rise := smoothstep(0.0, 0.18, t)
		var w := size * lerpf(1.0, 0.45, smoothstep(0.2, 1.0, t))
		flash.scale = Vector3(w, 0.3 + 4.2 * rise, w)
		param(flash, &"fx_fade", 1.0 - smoothstep(0.25, 0.85, t))
	_update_ring(t, size * 0.5, size * 2.6)


func _update_ring(t: float, from_r: float, to_r: float) -> void:
	if ring == null:
		return
	var d := lerpf(from_r, to_r, 1.0 - pow(1.0 - t, 3.0)) * 2.0
	ring.scale = Vector3(d, 1.0, d)
	var a := (1.0 - t) * color.a * 0.9
	Mats.set_ring(ring, Color(color.r, color.g, color.b, a), 0.8, 0.97, 0.0)
