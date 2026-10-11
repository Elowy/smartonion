class_name WarriorFx
extends Node3D
## Base of the Warrior kit's procedural effects (Thunder Clap, Heroic Leap, Execute, Battle
## Shout, Shield Wall, Ravager): unshaded translucent parts that fade in and out over
## [member life] seconds and then free the node. [member life] <= 0 = until the owning ability
## frees it ([method dismiss] fades it out first). Subclasses build their parts in _ready()
## with [method add_part] and animate them in [method _animate]. Purely visual: _process,
## no gameplay state, no RunState.rng.

## Seconds until the effect frees itself (<= 0: held until dismissed).
var life := 0.5
var fade_in := 0.06
var fade_out := 0.2
var age := 0.0

var _materials: Array[StandardMaterial3D] = []
var _alphas: Array[float] = []
## Seconds of the fade-out after dismiss() (-1 = not dismissed).
var _dismiss_left := -1.0


## An unshaded, translucent, double-sided material (shadowless parts).
static func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	return m


## Adds a faded part: [param mesh] in [param color] (its alpha is the part's full opacity)
## under [param parent] (default: this node).
func add_part(mesh: Mesh, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var m := material(color)
	_materials.append(m)
	_alphas.append(color.a)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else self).add_child(mi)
	return mi


## Lets a held effect ([member life] <= 0) fade out and free itself.
func dismiss() -> void:
	if _dismiss_left < 0.0:
		_dismiss_left = maxf(0.01, fade_out)


func is_dismissed() -> bool:
	return _dismiss_left >= 0.0


## 0..1 progress of a timed effect (0 for a held one).
func progress() -> float:
	return clampf(age / life, 0.0, 1.0) if life > 0.0 else 0.0


## Current opacity factor (fade in, fade out at the end of the life or after dismiss()).
func fade() -> float:
	var f := clampf(age / fade_in, 0.0, 1.0) if fade_in > 0.0 else 1.0
	if life > 0.0 and fade_out > 0.0:
		f = minf(f, clampf((life - age) / fade_out, 0.0, 1.0))
	if _dismiss_left >= 0.0:
		f = minf(f, clampf(_dismiss_left / maxf(0.01, fade_out), 0.0, 1.0))
	return f


func _process(delta: float) -> void:
	age += delta
	if _dismiss_left >= 0.0:
		_dismiss_left -= delta
		if _dismiss_left <= 0.0:
			queue_free()
			return
	if life > 0.0 and age >= life:
		queue_free()
		return
	_animate(delta)
	var f := fade()
	for i in _materials.size():
		_materials[i].albedo_color.a = _alphas[i] * f


## Per-frame animation of a subclass (called before the fade is applied).
func _animate(_delta: float) -> void:
	pass


## Ring mesh (unit outer radius, [param inner] inner radius) on the ground plane.
static func ring_mesh(inner: float, segments: int = 48) -> Mesh:
	var key := "warrior:ring:%d:%d" % [roundi(inner * 100.0), segments]
	return MeshKit.cached(key, func() -> Mesh:
		return MeshKit.new().add_arc(inner, 1.0, 360.0, Transform3D.IDENTITY, Color.WHITE, segments).build())


## Unit disc on the ground plane.
static func disc_mesh() -> Mesh:
	return MeshKit.cached("warrior:disc", func() -> Mesh:
		return MeshKit.new().add_arc(0.0, 1.0, 360.0, Transform3D.IDENTITY, Color.WHITE, 40).build())


## Ground crack: a thin wedge 1 m long pointing along -Z from the origin.
static func crack_mesh() -> Mesh:
	return MeshKit.cached("warrior:crack", func() -> Mesh:
		return MeshKit.new().add_arc(0.0, 1.0, 7.0, Transform3D.IDENTITY, Color.WHITE, 2).build())
