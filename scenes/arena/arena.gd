class_name Arena
extends Node3D
## STUB – owned by the "visuals" module.
## The battlefield: an Elwynn-like forest clearing (GDD 13). Flat ground on the XZ plane,
## centred on the origin, enclosed by solid walls (collision layer 1 "world").
## Screen-up is -Z. Contains:
##   entities: Node3D  – parent for players, enemies, projectiles, pickups and VFX.
##   camera:   CameraRig

## Playable area size in metres (x = width, y = depth along Z).
const SIZE := Vector2(34.0, 22.0)

static var current: Arena

var entities: Node3D
var camera: CameraRig


static func create() -> Arena:
	var arena := Arena.new()
	return arena


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


## Playable rectangle on the XZ plane (Rect2.position = min x / min z).
func get_bounds() -> Rect2:
	return Rect2(-SIZE / 2.0, SIZE)


## [param count] spawn points near the centre, spread out, one per player.
func get_player_spawn_points(count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in count:
		out.append(Vector3((i - (count - 1) / 2.0) * 2.0, 0.0, 0.0))
	return out


## Random point inside the bounds keeping [param margin] metres from the walls.
func random_point(rng: RandomNumberGenerator, margin: float = 1.5) -> Vector3:
	var b := get_bounds().grow(-margin)
	return Vector3(rng.randf_range(b.position.x, b.end.x), 0.0, rng.randf_range(b.position.y, b.end.y))


## Clamps a world position into the playable area.
func clamp_point(p: Vector3, margin: float = 0.5) -> Vector3:
	var b := get_bounds().grow(-margin)
	return Vector3(clampf(p.x, b.position.x, b.end.x), p.y, clampf(p.z, b.position.y, b.end.y))
