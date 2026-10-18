class_name ArenaHazard
extends EnemyHazard
## Base of the arena environments' ground hazards (M6b, GDD 16.1): [GraspingHands] (Cemetery),
## [BogPool] (Swamp), [LavaEruption] (Volcano), [FallingIcicle] (Ice Cave). An [EnemyHazard] like the
## bosses' circles – group enemy_hazards, the bots read hazard_push, WaveDirector.stop() frees the
## group at the wave end – with no boss behind it ([member EnemyHazard.source] stays null: the hits are
## the arena's) and a [member tally]: the [EnvironmentHazards] director that laid it down and counts
## the hits (SMOKE_RESULT "hazards", tests).
##
## [member damage] is fixed when the hazard is laid down: a multiple of the Skeleton Grunt's contact
## damage at the wave, with the party-size damage factor (EnvironmentHazards.grunt_damage).

## The least WCAG contrast ratio (relative luminance, 1 = identical .. 21 = black on white) a hazard's
## [method marker_color] keeps against every colour of its own environment's floor
## ([method EnvironmentData.floor_colors]): a telegraph a hero cannot see is no telegraph (the Ice Cave's
## pale blue ring vanished on its pale blue snow at 1.1).
const MIN_MARKER_CONTRAST := 2.0

## The director counting this hazard's hits (null = nobody counts).
var tally: EnvironmentHazards


## The WCAG contrast ratio of [param a] and [param b] (sRGB colours): 1 for the same luminance, 21 for
## black on white.
static func contrast_ratio(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear().get_luminance()
	var lb := b.srgb_to_linear().get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## The colour of the outline band that shows where the hazard is ([member EnemyHazard.color] unless the
## hazard marks itself otherwise). It keeps [constant MIN_MARKER_CONTRAST] against the floor of every
## environment that runs the hazard (tests/test_m6b_env.gd pins it).
func marker_color() -> Color:
	return color


## Hurts [param hero] like any ground attack ([method EnemyHazard.hit_hero]) and counts it.
func hit_hero(hero: Player, amount: float) -> void:
	if hero == null or not is_instance_valid(hero) or amount <= 0.0:
		return
	super(hero, amount)
	if tally != null and is_instance_valid(tally):
		tally.record_hero_hit(amount)


## Hurts [param enemy] for [param amount] (nobody gets the kill credit) and counts it. Returns whether
## the enemy died of it.
func hit_enemy(enemy: Enemy, amount: float) -> bool:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_dead() or amount <= 0.0:
		return false
	enemy.take_damage(amount)
	var died := enemy.is_dead()
	if tally != null and is_instance_valid(tally):
		tally.record_enemy_hit(amount, died)
	return died


## The living enemies whose body touches the circle of [member radius] around this node (the grid
## answers; the exact test is on the live positions).
func enemies_in_circle() -> Array[Enemy]:
	var out: Array[Enemy] = []
	if not is_inside_tree():
		return out
	for node in EnemyGrid.gather_around(get_tree(), global_position, radius):
		var e := node as Enemy
		if e == null or not is_instance_valid(e) or e.is_dead():
			continue
		var d := Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z)
		var reach := radius + e.radius * 0.5
		if d.length_squared() <= reach * reach:
			out.append(e)
	return out
