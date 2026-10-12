class_name WarlockVfx
extends Node3D
## Fire-and-forget looks of the Warlock's M4 spells that [Vfx] has no helper for: a ground
## shock wave (a ring that races out to a radius and fades – Fear, Torment, seed bursts,
## the Infernal's landing and slams) with optional rising wisps. Parented like [Vfx] effects
## (Arena entities, else the current scene) and freed after [member life] seconds.
## Purely visual: no gameplay state, no RunState.rng (fixed wisp layout). The ring owns its
## material (Mats.ring); the wisps share a cached mesh and glow material.

const WAVE_TIME := 0.45
const WISPS := 8
## Unstable Affliction's burst: ring life and fel crackles.
const UNSTABLE_TIME := 0.3
const UNSTABLE_CRACKLES := 3

static var _wisp_mesh: Mesh

var radius := 3.0
var life := WAVE_TIME
var color := Color(0.6, 0.3, 0.95)
var age := 0.0
## Ring width as a share of the radius at the end of the wave.
var band := 0.18
var _ring: MeshInstance3D
var _wisps: Node3D


## Dark purple wave of Fear around [param center].
static func fear_wave(center: Vector3, p_radius: float) -> void:
	_spawn(center, p_radius, Color(0.5, 0.2, 0.85, 0.9), 0.5, 0.25, true)


## Seed of Corruption bursting at [param center] (purple flash, fel ring).
static func seed_burst(center: Vector3, p_radius: float) -> void:
	Vfx.explosion(center + Vector3.UP * 0.5, p_radius, WarlockSpell.SHADOW_COLOR)
	_spawn(center, p_radius, Color(0.5, 1.0, 0.3, 0.85), 0.35, 0.16, true)


## Unstable Affliction (M5 Affliction capstone) bursting at [param center]: a fast
## purple-black ring with a few green fel crackles. One per burst, no per-victim effects.
static func unstable_burst(center: Vector3, p_radius: float) -> void:
	_spawn(center, p_radius, Color(0.6, 0.3, 0.95, 0.9), UNSTABLE_TIME, 0.22, false)
	for i in UNSTABLE_CRACKLES:
		var a := TAU * float(i) / float(UNSTABLE_CRACKLES)
		var at := Vector3(center.x + cos(a) * p_radius * 0.45, Vfx.GROUND_Y + 0.6, center.z + sin(a) * p_radius * 0.45)
		Vfx.hit_spark(at, WarlockSpell.FEL_COLOR)


## The Voidwalker's Torment: a deep blue pulse.
static func torment_wave(center: Vector3, p_radius: float) -> void:
	_spawn(center, p_radius, Color(0.35, 0.45, 1.0, 0.85), 0.5, 0.2, true)


## The Infernal landing / slamming: fel fire and dust.
static func infernal_slam(center: Vector3, p_radius: float, big: bool = false) -> void:
	if big:
		Vfx.explosion(center + Vector3.UP * 0.4, p_radius, WarlockSpell.FEL_COLOR)
	_spawn(center, p_radius, Color(0.55, 1.0, 0.25, 0.9), 0.4 if big else 0.28, 0.2, big)


static func _spawn(center: Vector3, p_radius: float, p_color: Color, p_life: float, p_band: float,
		with_wisps: bool) -> void:
	var parent := Vfx.effect_parent()
	if parent == null or not parent.is_inside_tree():
		return
	var fx := WarlockVfx.new()
	fx.name = "WarlockWave"
	fx.radius = maxf(0.3, p_radius)
	fx.color = p_color
	fx.life = p_life
	fx.band = p_band
	fx._build(with_wisps)
	parent.add_child(fx)
	fx.global_position = Vector3(center.x, Vfx.GROUND_Y + 0.03, center.z)


func _build(with_wisps: bool) -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = MeshKit.cached("warlock:ground_quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)
	_ring.material_override = Mats.ring()
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	if with_wisps:
		if _wisp_mesh == null:
			var m := SphereMesh.new()
			m.radius = 0.09
			m.height = 0.18
			m.radial_segments = 8
			m.rings = 4
			_wisp_mesh = m
		_wisps = Node3D.new()
		_wisps.name = "Wisps"
		add_child(_wisps)
		var mat := Mats.glow(Color(color.r, color.g, color.b, 1.0), 2.4)
		for i in WISPS:
			var w := MeshInstance3D.new()
			w.mesh = _wisp_mesh
			w.material_override = mat
			w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_wisps.add_child(w)
	_update()


func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	_update()


func _update() -> void:
	var t := clampf(age / life, 0.0, 1.0)
	var grow := 1.0 - pow(1.0 - t, 3.0)
	var r := maxf(0.05, radius * grow)
	var fade := 1.0 - t * t
	_ring.scale = Vector3(r * 2.0, 1.0, r * 2.0)
	var inner := clampf(1.0 - band * radius / r, 0.0, 0.97)
	Mats.set_ring(_ring, Color(color, color.a * fade), inner, 1.0, 0.12 * fade)
	if _wisps != null:
		for i in _wisps.get_child_count():
			var w := _wisps.get_child(i) as Node3D
			var a := TAU * float(i) / float(WISPS) + t * 1.2
			w.position = Vector3(cos(a) * r * 0.9, 0.15 + 1.1 * t * (0.6 + 0.4 * float(i % 3) / 2.0), sin(a) * r * 0.9)
			w.scale = Vector3.ONE * maxf(0.05, fade)
