class_name RogueUtil
extends RefCounted
## Small helpers shared by the Rogue kit (Fan of Knives, Vanish, Deadly Poison, bots).

const COMBO_ID := &"combo_points"
const ENERGY_ID := &"energy"


## Whole Combo Points the player holds (the resource is a float; a Resource Regen bonus can
## leave a fraction on it).
static func combo_points(player: Player) -> int:
	if player == null or player.abilities == null:
		return 0
	var combo := player.abilities.get_resource(COMBO_ID)
	return floori(combo.value + 0.0001) if combo != null else 0


## Living enemies whose centre is within [param radius] metres (XZ) of the player.
static func enemies_within(player: Player, radius: float) -> int:
	if player == null or not player.is_inside_tree():
		return 0
	var center := player.global_position
	var count := 0
	for node in EnemyGrid.gather_around(player.get_tree(), center, radius):
		var e := node as Enemy
		if e == null or e.is_dead():
			continue
		var d := WeaponRunner.flat(e.global_position - center)
		if d.length_squared() <= radius * radius:
			count += 1
	return count
