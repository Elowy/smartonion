class_name LootDrops
extends RefCounted
## STUB – owned by the "shop-loot" agent. Decides item drops when enemies die (GDD 10.1):
## normal enemies 1.5% (+Fortune), at most 1 + players item drops per wave from normal
## enemies; elites / goblin / boss sources come with M5 / M6. Spawns a LootBag.


## Called by Enemy on death (killer may be null). Rolls and spawns a LootBag if lucky.
static func on_enemy_killed(enemy: Node3D, killer: Node3D) -> void:
	pass
