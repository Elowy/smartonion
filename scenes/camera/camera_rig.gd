class_name CameraRig
extends Node3D
## STUB – owned by the "visuals" module.
## Top-down camera (~55-60 degree pitch) that follows the centroid of the living players
## (group &"players") and zooms out so everyone stays on screen; clamped to the arena.

var camera: Camera3D


## Jumps to the target framing immediately (run start).
func snap() -> void:
	pass


## Screen shake, [param strength] ~0.1 (hit) .. 1.0 (boss slam).
func shake(strength: float) -> void:
	pass
