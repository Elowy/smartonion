class_name WarlockSpell
extends RefCounted
## Shared maths and enemy queries of the Warlock kit (M4 abilities and the M3 core ones).
##
## Spell damage: (damage + Intellect x intellect_scale + Spell Power x spell_power_scale x
## [param sp_seconds]) x (Versatility + Damage % + school %) x "power" (ability Ranks II / IV).
## [param prefix] selects a second set of the same keys in one params dictionary
## ("dot_damage", "dot_intellect_scale" ... for the DoT part of Seed of Corruption).
## Target bonuses, Demonic Pact and the Warlock's outgoing multipliers come on top in
## ProcSystem.deal_raw.

const SHADOW := &"shadow"
const FIRE := &"fire"
## Purple of shadow spells (bolts, beams, markers) and the fel green of demons.
const SHADOW_COLOR := Color(0.66, 0.36, 0.95)
const FEL_COLOR := Color(0.45, 1.0, 0.25)


## Damage of one hit / one second of [param params] for [param stats] (see the class doc).
static func damage(stats: StatBlock, params: Dictionary, school: StringName, prefix: String = "",
		sp_seconds: float = 1.0) -> float:
	var flat := float(params.get(prefix + "damage", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.INTELLECT)) * float(params.get(prefix + "intellect_scale", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.SPELL_POWER)) * float(params.get(prefix + "spell_power_scale", 0.0)) * sp_seconds
	return maxf(CombatMath.MIN_DAMAGE, flat * CombatMath.damage_mult_for(stats, school) * power(params))


## The rank multiplier of damage / heal / shield amounts ("power", 1.0 at Rank I).
static func power(params: Dictionary) -> float:
	var v: Variant = params.get("power", 1.0)
	return maxf(0.0, float(v)) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 1.0


## An area radius after the hero's Area Size.
static func area(stats: StatBlock, radius: float) -> float:
	return maxf(0.1, radius) * CombatMath.area_mult(stats)


static func is_live(e: Variant) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	var enemy := e as Enemy
	return enemy != null and enemy.is_inside_tree() and not enemy.is_dead()


## Living enemies whose body touches the circle at [param center] (XZ), in group order.
static func enemies_in_circle(tree: SceneTree, center: Vector3, radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if tree == null:
		return out
	for node in EnemyGrid.gather_around(tree, center, radius):
		var e := node as Enemy
		if not is_live(e):
			continue
		var reach := radius + e.radius
		if WeaponRunner.flat(e.global_position - center).length_squared() <= reach * reach:
			out.append(e)
	return out


## How many living enemies touch the circle at [param center].
static func count_in_circle(tree: SceneTree, center: Vector3, radius: float) -> int:
	var n := 0
	if tree == null:
		return n
	for node in EnemyGrid.gather_around(tree, center, radius):
		var e := node as Enemy
		if not is_live(e):
			continue
		var reach := radius + e.radius
		if WeaponRunner.flat(e.global_position - center).length_squared() <= reach * reach:
			n += 1
	return n


## Up to [param count] living enemies whose centre is within [param max_range] of
## [param origin] (XZ), nearest first (ties in group order), that pass [param accept]
## (Callable(Enemy) -> bool; an invalid Callable accepts all) and are not in [param exclude].
static func nearest_enemies(tree: SceneTree, origin: Vector3, max_range: float, count: int,
		accept: Callable = Callable(), exclude: Array[Enemy] = []) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if tree == null or count <= 0 or max_range < 0.0:
		return out
	var found: Array[Array] = []
	var range_sq := max_range * max_range
	var order := 0
	for node in EnemyGrid.gather_around(tree, origin, max_range):
		order += 1
		var e := node as Enemy
		if not is_live(e) or e in exclude:
			continue
		var d := WeaponRunner.flat(e.global_position - origin).length_squared()
		if d > range_sq:
			continue
		if accept.is_valid() and not bool(accept.call(e)):
			continue
		found.append([d, order, e])
	if found.size() > 1:
		found.sort_custom(func(a: Array, b: Array) -> bool:
			return float(a[0]) < float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
	for f in found:
		if out.size() >= count:
			break
		out.append(f[2] as Enemy)
	return out


## True when any living enemy within [param max_range] of [param origin] passes
## [param accept] (cheap early-out check for the auto-cast rules).
static func any_enemy(tree: SceneTree, origin: Vector3, max_range: float, accept: Callable) -> bool:
	if tree == null or max_range < 0.0:
		return false
	var range_sq := max_range * max_range
	for node in EnemyGrid.gather_around(tree, origin, max_range):
		var e := node as Enemy
		if not is_live(e):
			continue
		if WeaponRunner.flat(e.global_position - origin).length_squared() > range_sq:
			continue
		if not accept.is_valid() or bool(accept.call(e)):
			return true
	return false


## Height of an enemy's body centre (its model scale counts).
static func body_height(e: Enemy) -> float:
	var s := e.data.model_scale if e != null and e.data != null else 1.0
	return Enemy.BODY_CENTER_HEIGHT * s


## Chest position of an enemy (beams, sparks).
static func chest(e: Node3D) -> Vector3:
	var enemy := e as Enemy
	return e.global_position + Vector3.UP * (body_height(enemy) if enemy != null else Enemy.BODY_CENTER_HEIGHT)
