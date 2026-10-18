class_name EventTag
extends Label3D
## The name tag of a mid-wave event object (the chest's, the totem's, the cart's; M6b EVENTS): a fixed-size
## billboard [Label3D] ([method EventFx.label]) that keeps itself on screen and out from under the HUD, like
## the Loot Goblin's tag ([method LootGoblin.keep_tag_on_screen]): it sits at [member home] above the object
## while it fits inside the part of the screen the HUD leaves free ([method CameraRig.get_safe_screen_rect]);
## near the edge of that area – or with the object beyond it, e.g. in a screen corner under a unit frame – it
## slides along the edge at the same depth ([method LootGoblin.clamp_tag_in]), pointing towards the object.
## Visual only: every rendered frame, no gameplay state, no rng.

## The tag's own place (local to its parent): where it sits whenever it fits.
var home := Vector3.ZERO


func _process(_delta: float) -> void:
	keep_on_screen()


## Moves the tag inside the free part of the screen of the current camera, LootGoblin.TAG_SCREEN_PAD px
## from its edges (or leaves it at [member home] when it fits / no perspective camera looks at it).
func keep_on_screen() -> void:
	var parent := get_parent() as Node3D
	if parent == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	var anchor := parent.global_transform * home
	if cam == null or cam.projection != Camera3D.PROJECTION_PERSPECTIVE or cam.is_position_behind(anchor):
		position = home
		return
	var view := cam.get_viewport().get_visible_rect()
	var rig := cam.get_parent() as CameraRig
	var area := rig.get_safe_screen_rect() if rig != null else view
	var screen := cam.unproject_position(anchor)
	var size := LootGoblin.label_screen_size(self, view.size.y, cam.fov)
	var clamped := LootGoblin.clamp_tag_in(screen, size, area, LootGoblin.TAG_SCREEN_PAD)
	if clamped.is_equal_approx(screen):
		position = home
		return
	var depth := -(cam.global_transform.affine_inverse() * anchor).z
	global_position = cam.project_position(clamped, depth)
