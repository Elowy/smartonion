class_name OnionModel
extends Node3D
## STUB – owned by the "visuals" module.
## Procedural low-poly onion hero in WoW-style armour (GDD 13). Built from primitives.
## Origin is at the feet; total height ~1.3 m; faces -Z by default.


## Builds the model for [param class_data] (onion skin colour, headgear, shoulders,
## accent colour) with a small ring / marker in [param player_color] under the feet.
func setup(class_data: ClassData, player_color: Color) -> void:
	pass


## Shows the weapon models in the hands (null = empty hand).
func set_weapons(main_hand: WeaponData, off_hand: WeaponData) -> void:
	pass


## Smoothly turns the body towards [param direction] (XZ plane).
func set_facing(direction: Vector3) -> void:
	pass


## 0 = idle, 1 = full speed. Drives waddle / bob animation.
func set_moving(speed_ratio: float) -> void:
	pass


## Short swing / thrust animation of one hand.
func play_attack(off_hand: bool) -> void:
	pass


## White flash + squash when damaged.
func flash_hit() -> void:
	pass


## Low HP -> peeled / cracked onion layers (visual HP feedback). [param ratio] = hp / max.
func set_hp_ratio(ratio: float) -> void:
	pass


## Downed: translucent crying onion ghost. false restores the normal look.
func set_downed(downed: bool) -> void:
	pass


## 0..1 revive progress ring shown while a teammate stands next to a downed player.
func set_revive_progress(progress: float) -> void:
	pass
