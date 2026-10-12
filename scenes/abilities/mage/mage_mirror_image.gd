class_name MageMirrorImage
extends Node3D
## Mirror Image (Mage Arcane talent, M5 – a Blink modifier, talents_mage.md 1.3 / 4.1): a
## translucent copy of the Mage left where it blinked from. While it lasts it lures the enemies
## around it (taunt, [method Enemy.apply_taunt]: they walk to the image instead of the heroes –
## touching a hero on the way still hurts), and when it fades it bursts for Arcane damage.
##
## [method spawn] by [BlinkEffect] (under the arena's entities, else next to the caster). No
## collision, no HP, it cannot be hit. Lure pulses: on spawn and every [constant PULSE] s, every
## living enemy whose body is within [member radius] (Area Size included) that is not a boss and
## not taunted onto another live target is taunted onto the image for the image's remaining
## time. Fade: [member burst_damage] (computed at spawn, the caster's Arcane spell damage) to
## every enemy within [member burst_radius] through the caster's ProcSystem.deal_raw(...,
## &"ability"), then the node frees itself – the taunts end with it (Enemy.is_taunted checks the
## target). The caster going down does not remove it (it keeps enemies off the downed Mage and
## the reviver); a freed caster frees it without a burst; [method dismiss] (BlinkEffect wave
## start / end) removes it without a burst. Purely deterministic: no RNG.

## Every live image is in this group (tests, debugging).
const GROUP := &"mage_mirror_images"
const PULSE := 0.5
const COLOR := Color(0.88, 0.5, 1.0, 0.4)
const BOB_HEIGHT := 0.06
const BOB_SPEED := 2.6
const SHIMMER_SPEED := 5.0

var caster: Player
## Seconds the image still stands.
var time_left := 3.0
## Lure radius (m, Area Size applied by the caller).
var radius := 4.0
## Arcane damage of the fade burst per enemy (before target bonuses / the caster's multipliers).
var burst_damage := 0.0
var burst_radius := 2.5
## Fade bursts that went off (0 / 1; tests).
var bursts := 0
## Enemies the burst damaged (tests).
var burst_hits := 0
## Taunts applied by the lure pulses (tests).
var taunts := 0

var _pulse_left := 0.0
var _age := 0.0
var _body: Node3D
var _material: StandardMaterial3D
var _gone := false


## Leaves an image of [param p_caster] at [param at] (flattened to the ground) for
## [param duration] seconds and lures at once. Not in the tree (and luring nothing) when there
## is no parent for effects.
static func spawn(p_caster: Player, at: Vector3, duration: float, p_radius: float,
		p_burst_damage: float, p_burst_radius: float) -> MageMirrorImage:
	var image := MageMirrorImage.new()
	image.name = "MirrorImage"
	image.caster = p_caster
	image.time_left = maxf(0.0, duration)
	image.radius = maxf(0.0, p_radius)
	image.burst_damage = maxf(0.0, p_burst_damage)
	image.burst_radius = maxf(0.0, p_burst_radius)
	image.add_to_group(GROUP)
	image._build()
	var parent := WeaponRunner.effects_parent(p_caster)
	if parent == null:
		return image
	parent.add_child(image)
	image.global_position = WeaponRunner.flat(at)
	image._lure()
	image._pulse_left = PULSE
	return image


## True until it faded or was dismissed.
func is_active() -> bool:
	return not _gone and not is_queued_for_deletion()


## Removes the image now without a burst (wave start / end, the caster is leaving).
func dismiss() -> void:
	if _gone:
		return
	_gone = true
	queue_free()


func _physics_process(delta: float) -> void:
	if _gone or is_queued_for_deletion():
		return
	if not is_instance_valid(caster):
		dismiss()
		return
	time_left -= delta
	if time_left <= 0.0:
		_fade()
		return
	_pulse_left -= delta
	if _pulse_left <= 0.0:
		_pulse_left += PULSE
		_lure()


func _process(delta: float) -> void:
	_age += delta
	if _body != null:
		_body.position.y = sin(_age * BOB_SPEED) * BOB_HEIGHT
	if _material != null:
		var fade := clampf(time_left / 0.4, 0.0, 1.0) * clampf(_age / 0.15, 0.0, 1.0)
		_material.albedo_color.a = COLOR.a * fade * (0.8 + 0.2 * sin(_age * SHIMMER_SPEED))


## Taunts the enemies around onto the image (bosses and enemies taunted onto another live
## target are left alone).
func _lure() -> void:
	if not is_inside_tree() or time_left <= 0.0:
		return
	for e in MageSpell.enemies_in(get_tree(), global_position, radius):
		if e.is_boss():
			continue
		if e.is_taunted() and e.taunt_target != self:
			continue
		e.apply_taunt(self, time_left)
		taunts += 1


## The image fades: the Arcane burst, a flash, then it frees itself.
func _fade() -> void:
	_gone = true
	bursts += 1
	if is_inside_tree():
		var here := global_position
		if burst_damage > 0.0 and is_instance_valid(caster) and caster.procs != null:
			for e in MageSpell.enemies_in(get_tree(), here, burst_radius):
				if caster.procs.deal_raw(e, burst_damage, MageSpell.ARCANE, true, &"ability") > 0.0:
					burst_hits += 1
		Vfx.explosion(here + Vector3.UP * 0.4, maxf(0.5, burst_radius), MageSpell.ARCANE_COLOR)
	queue_free()


## A translucent violet onion: a squashed sphere body, a cone hat and a few rising sparkles.
func _build() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_material = (Mats.unshaded(COLOR) as StandardMaterial3D).duplicate() as StandardMaterial3D
	var bulb := MeshInstance3D.new()
	bulb.name = "Bulb"
	bulb.mesh = MeshKit.cached("mage:mirror_bulb", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.42
		s.height = 0.78
		s.radial_segments = 14
		s.rings = 7
		return s)
	bulb.material_override = _material
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.position.y = 0.45
	_body.add_child(bulb)
	var hat := MeshInstance3D.new()
	hat.name = "Hat"
	hat.mesh = MeshKit.cached("mage:mirror_hat", func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.3
		c.height = 0.55
		c.radial_segments = 10
		c.rings = 1
		return c)
	hat.material_override = _material
	hat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hat.position.y = 1.05
	_body.add_child(hat)
	var sparkles := MageFx.trail(MageSpell.ARCANE_COLOR, 0.8)
	sparkles.position.y = 0.5
	sparkles.emission_sphere_radius = 0.35
	_body.add_child(sparkles)
