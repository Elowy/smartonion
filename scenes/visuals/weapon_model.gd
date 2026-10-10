class_name WeaponModel
extends RefCounted
## STUB – owned by the "visuals" module.


## Builds a small primitive mesh for [param weapon] (by weapon_type, coloured by weapon.color).
## The handle is at the origin, the blade / head points along +Y.
static func build(weapon: WeaponData) -> Node3D:
	return Node3D.new()
