class_name GeneralKit
extends RefCounted
## Shared helpers of the general abilities (GDD 6.4: Bandage, Sprint, Engineer's Bomb, War
## Stomp, Spirit Wolf, Berserking). Every class can learn them, so their numbers scale with
## whatever the hero is built around:
##   * physical-style hits ([method weapon_damage]): the main-hand weapon's hit normalised to
##     a [constant NORMALIZED_SWING] s swing (WoW's "normalised weapon damage" – a slow axe and
##     a fast dagger give the same ability damage for the same DPS), times the ability's school
##     multiplier (Versatility + Damage % + school %);
##   * spells ([method spell_damage]): base + primary stat x scale + the BETTER of Attack Power
##     and Spell Power, through CombatMath.proc_damage (so a Warrior's Attack Power counts for
##     a fire bomb as much as a Mage's Spell Power).
## Damage goes out with ProcSystem.deal_raw (source &"ability" / &"pet").

## Weapon hits are normalised to a swing of this many seconds.
const NORMALIZED_SWING := 1.0
## Damage of a normalised hit without an attacking main-hand weapon (+ primary stat + power).
const FALLBACK_DAMAGE := 3.0
const TIME_EPSILON := 0.0001


## The class's primary stat (Strength / Agility / Intellect); Strength without class data.
static func primary_stat(player: Player) -> StringName:
	if player != null and player.class_data != null and player.class_data.primary_stat != &"":
		return player.class_data.primary_stat
	return Stats.STRENGTH


## The better of Attack Power and Spell Power (never below 0).
static func best_power(stats: StatBlock) -> float:
	return maxf(0.0, maxf(stats.get_raw(Stats.ATTACK_POWER), stats.get_raw(Stats.SPELL_POWER)))


## One main-hand hit normalised to a 1 s swing (stat scaling + Attack / Spell Power included),
## times the damage multiplier of [param school]. Before crits and target bonuses.
static func weapon_damage(player: Player, school: StringName = CombatMath.SCHOOL_PHYSICAL) -> float:
	if player == null:
		return CombatMath.MIN_DAMAGE
	var stats := player.stats
	var w := player.main_hand
	var flat := 0.0
	if w != null and w.attacks() and w.cooldown > 0.0:
		flat = CombatMath.weapon_base_damage(w, stats) * NORMALIZED_SWING / w.cooldown
	else:
		flat = FALLBACK_DAMAGE + maxf(0.0, stats.get_raw(primary_stat(player))) + best_power(stats)
	return maxf(CombatMath.MIN_DAMAGE, flat * CombatMath.damage_mult_for(stats, school))


## Spell damage of [param school]: [param base] + primary stat x [param primary_scale] + the
## better of Attack / Spell Power, through CombatMath.proc_damage (Versatility, Damage %,
## school %). Before target bonuses.
static func spell_damage(player: Player, base: float, primary_scale: float, school: StringName) -> float:
	if player == null:
		return 0.0
	var stats := player.stats
	var flat := base + maxf(0.0, stats.get_raw(primary_stat(player))) * primary_scale
	# proc_damage adds the school's own power stat (Attack Power for physical, else Spell
	# Power); top it up to the better of the two.
	var own := Stats.ATTACK_POWER if school == CombatMath.SCHOOL_PHYSICAL or school == &"" else Stats.SPELL_POWER
	flat += maxf(0.0, best_power(stats) - maxf(0.0, stats.get_raw(own))) * CombatMath.PROC_POWER_SCALE
	return CombatMath.proc_damage(flat, school, stats)


## Living enemies whose body touches the circle of [param radius] around [param center] (XZ),
## in group order.
static func enemies_around(tree: SceneTree, center: Vector3, radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if tree == null or radius <= 0.0:
		return out
	for node in EnemyGrid.gather_around(tree, center, radius):
		var e := node as Enemy
		if e == null or e.is_dead() or not e.is_inside_tree():
			continue
		var dx := e.global_position.x - center.x
		var dz := e.global_position.z - center.z
		var reach := radius + e.radius
		if dx * dx + dz * dz <= reach * reach:
			out.append(e)
	return out


## [method enemies_around] the hero.
static func enemies_near(player: Player, radius: float) -> Array[Enemy]:
	if player == null or not player.is_inside_tree():
		return []
	return enemies_around(player.get_tree(), player.global_position, radius)


## Living enemies whose centre lies within [param radius] of [param center] (cluster scoring).
static func cluster_size(tree: SceneTree, center: Vector3, radius: float) -> int:
	var n := 0
	if tree == null:
		return n
	for node in EnemyGrid.gather_around(tree, center, radius):
		var e := node as Enemy
		if e == null or e.is_dead() or not e.is_inside_tree():
			continue
		if flat_distance(e.global_position, center) <= radius:
			n += 1
	return n


## Where an area of [param radius] around [param target] covers the most enemies: the centroid
## of the enemies around it, or the target's own spot when that covers more.
static func cluster_center(target: Node3D, radius: float) -> Vector3:
	if target == null or not target.is_inside_tree():
		return Vector3.ZERO
	var tree := target.get_tree()
	var on_target := Vector3(target.global_position.x, 0.0, target.global_position.z)
	var sum := Vector3.ZERO
	var count := 0
	for node in EnemyGrid.gather_around(tree, on_target, radius):
		var e := node as Enemy
		if e == null or e.is_dead() or not e.is_inside_tree():
			continue
		if flat_distance(e.global_position, on_target) > radius:
			continue
		sum += Vector3(e.global_position.x, 0.0, e.global_position.z)
		count += 1
	if count == 0:
		return on_target
	var centroid := sum / float(count)
	if cluster_size(tree, on_target, radius) > cluster_size(tree, centroid, radius):
		return on_target
	return centroid


## 0..1 HP share of [param player] (1 when unknown).
static func hp_ratio(player: Player) -> float:
	if player == null or player.max_hp() <= 0.0:
		return 1.0
	return clampf(player.hp / player.max_hp(), 0.0, 1.0)


## Living teammates of [param player] (not the hero itself) within [param radius], in group
## order.
static func allies_near(player: Player, radius: float) -> Array[Player]:
	var out: Array[Player] = []
	if player == null or not player.is_inside_tree():
		return out
	var here := player.global_position
	for node in player.get_tree().get_nodes_in_group(&"players"):
		var p := node as Player
		if p == null or p == player or not p.is_alive() or not p.is_inside_tree():
			continue
		if flat_distance(p.global_position, here) <= radius:
			out.append(p)
	return out


## The nearest downed teammate within [param radius] (null = none).
static func downed_ally_near(player: Player, radius: float) -> Player:
	if player == null or not player.is_inside_tree():
		return null
	var here := player.global_position
	var best: Player = null
	var best_d := radius
	for node in player.get_tree().get_nodes_in_group(&"players"):
		var p := node as Player
		if p == null or p == player or not p.downed or not p.is_inside_tree():
			continue
		var d := flat_distance(p.global_position, here)
		if d <= best_d:
			best_d = d
			best = p
	return best


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## True while [param node] can still be used (not freed, not queued for deletion).
static func is_live(node: Node) -> bool:
	return node != null and is_instance_valid(node) and not node.is_queued_for_deletion()
