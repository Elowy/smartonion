class_name Vfx
extends RefCounted
## STUB – owned by the "visuals" module.
## Fire-and-forget effects. Every node created here frees itself.
## Effects are parented to Arena.current.entities when an arena exists, otherwise to the
## current scene. Positions are world positions.


## Floating combat text (damage, "Dodge", "+12 gold" ...). [param size] 1 = normal, crits ~1.5.
static func floating_text(pos: Vector3, text: String, color: Color, size: float = 1.0) -> void:
	pass


## Melee swing arc on the ground plane.
static func slash_arc(pos: Vector3, direction: Vector3, radius: float, arc_degrees: float, color: Color) -> void:
	pass


static func hit_spark(pos: Vector3, color: Color) -> void:
	pass


static func death_puff(pos: Vector3, color: Color, size: float = 1.0) -> void:
	pass


static func explosion(pos: Vector3, radius: float, color: Color) -> void:
	pass


## Red rune circle warning that an enemy will spawn here in [param duration] seconds.
static func spawn_telegraph(pos: Vector3, radius: float, duration: float) -> void:
	pass


static func level_up_burst(pos: Vector3) -> void:
	pass


## Small coin sparkle when loot is collected.
static func pickup_sparkle(pos: Vector3) -> void:
	pass
