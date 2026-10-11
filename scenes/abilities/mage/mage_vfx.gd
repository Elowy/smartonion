class_name MageVfx
extends RefCounted
## Small effects of the Mage kit (Blink flashes, Ignite spark). Fire-and-forget, built on
## [Vfx] / [ProcVfx]; they do nothing without a parent for effects (unit tests).

const ARCANE_COLOR := Color(0.78, 0.52, 1.0)
const FIRE_COLOR := Color(1.0, 0.52, 0.16)
const CHEST := Vector3.UP * 0.7


## Arcane flash where the hero vanishes, a bigger one where it arrives and a beam between.
static func blink(from: Vector3, to: Vector3) -> void:
	Vfx.explosion(from + Vector3.UP * 0.5, 1.0, ARCANE_COLOR)
	Vfx.explosion(to + Vector3.UP * 0.5, 1.4, ARCANE_COLOR)
	ProcVfx.beam(from + CHEST, to + CHEST, ARCANE_COLOR)
	Vfx.hit_spark(to + CHEST, ARCANE_COLOR.lerp(Color.WHITE, 0.4))


## A burst of embers when Ignite sets [param pos] (body centre) alight.
static func ignite(pos: Vector3) -> void:
	Vfx.hit_spark(pos, FIRE_COLOR)
