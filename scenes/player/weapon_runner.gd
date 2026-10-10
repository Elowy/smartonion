class_name WeaponRunner
extends Node3D
## STUB – owned by the "player" module.
## Auto-attacks with one equipped weapon (GDD 4). Child of a Player.


static func create(weapon: WeaponData, owner_player: Player, off_hand: bool) -> WeaponRunner:
	var w := WeaponRunner.new()
	return w
