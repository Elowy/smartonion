class_name PaladinKit
extends RefCounted
## Shared helpers of the Paladin's abilities (GDD 3.3, 6.4): holy strike damage, heals and
## absorb amounts, enemy / hero queries around a point (XZ, deterministic group order) and the
## per-Paladin key used for named buffs on other heroes.

const SCHOOL := &"holy"
const HOLY_COLOR := Color(1.0, 0.86, 0.4)
## Flat damage of a "weapon" strike when the Paladin holds no weapon (bare fists).
const FALLBACK_DAMAGE := 3.0


## Holy damage of a weapon-based Paladin strike (Hammer of Justice, Avenger's Shield, Divine
## Storm, the Radiant bubble): [param weapon_pct] % of the main hand's flat hit (base damage +
## stat scaling + speed-normalised Attack Power) + [param sp_scale] x Spell Power, times
## Versatility + Damage % + Holy %, times [param power] (ranks II / IV). Target bonuses,
## Mastery and the outgoing multipliers come on top in ProcSystem.deal_raw.
static func strike_damage(player: Player, weapon_pct: float, sp_scale: float, power: float = 1.0) -> float:
	if player == null:
		return CombatMath.MIN_DAMAGE
	var stats := player.stats
	var base := FALLBACK_DAMAGE + maxf(0.0, stats.get_raw(Stats.STRENGTH))
	if player.main_hand != null and player.main_hand.base_damage > 0.0:
		base = CombatMath.weapon_base_damage(player.main_hand, stats)
	var flat := base * weapon_pct / 100.0 + maxf(0.0, stats.get_raw(Stats.SPELL_POWER)) * sp_scale
	return maxf(CombatMath.MIN_DAMAGE, flat * CombatMath.damage_mult_for(stats, SCHOOL)) * maxf(0.0, power)


## A Paladin heal on [param who]: [param flat] + [param max_hp_pct] % of the healed hero's
## max HP + [param sp_scale] x the caster's Spell Power, times [param power].
static func heal_amount(caster: Player, who: Player, flat: float, max_hp_pct: float, sp_scale: float,
		power: float = 1.0) -> float:
	var sp := maxf(0.0, caster.stats.get_raw(Stats.SPELL_POWER)) if caster != null else 0.0
	var max_hp := who.max_hp() if who != null else 0.0
	return maxf(0.0, (flat + max_hp * max_hp_pct / 100.0 + sp * sp_scale) * maxf(0.0, power))


## 0..1 share of max HP (1 for a missing hero).
static func hp_ratio(p: Player) -> float:
	if p == null or p.max_hp() <= 0.0:
		return 1.0
	return clampf(p.hp / p.max_hp(), 0.0, 1.0)


## Alive and below max HP.
static func is_hurt(p: Player) -> bool:
	return p != null and p.is_alive() and p.hp < p.max_hp() - 0.001


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Living heroes in the tree (group order).
static func living_heroes(tree: SceneTree) -> Array[Player]:
	var out: Array[Player] = []
	if tree == null:
		return out
	for node in tree.get_nodes_in_group(&"players"):
		var p := node as Player
		if p != null and p.is_alive() and p.is_inside_tree():
			out.append(p)
	return out


## Living heroes whose centre is within [param radius] of [param center] (group order).
static func living_heroes_around(tree: SceneTree, center: Vector3, radius: float) -> Array[Player]:
	var out: Array[Player] = []
	for p in living_heroes(tree):
		if flat_distance(p.global_position, center) <= radius + 0.001:
			out.append(p)
	return out


## The living hero within [param radius] of [param center] with the lowest HP share (ties: group
## order); [param hurt_only] skips heroes at full HP. Null when there is none.
static func lowest_hero(tree: SceneTree, center: Vector3, radius: float, hurt_only: bool = true,
		exclude: Player = null) -> Player:
	var best: Player = null
	var best_ratio := 2.0
	for p in living_heroes_around(tree, center, radius):
		if p == exclude or (hurt_only and not is_hurt(p)):
			continue
		var r := hp_ratio(p)
		if r < best_ratio:
			best_ratio = r
			best = p
	return best


## Living enemies whose body touches the circle of [param radius] around [param center] (XZ),
## in group order.
static func enemies_around(tree: SceneTree, center: Vector3, radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if tree == null:
		return out
	for node in EnemyGrid.gather_around(tree, center, radius):
		var e := node as Enemy
		if e == null or e.is_dead():
			continue
		var dx := e.global_position.x - center.x
		var dz := e.global_position.z - center.z
		var reach := radius + e.radius
		if dx * dx + dz * dz <= reach * reach:
			out.append(e)
	return out


## Living enemies whose centre is within [param reach] of [param center], nearest first (ties
## in group order); with [param prefer_free] enemies that are not stunned come first.
static func enemies_by_distance(tree: SceneTree, center: Vector3, reach: float, prefer_free: bool = false) -> Array[Enemy]:
	var rows: Array[Array] = []
	if tree == null:
		return []
	var order := 0
	for node in EnemyGrid.gather_around(tree, center, reach):
		var e := node as Enemy
		if e == null or e.is_dead():
			continue
		var d := flat_distance(e.global_position, center)
		if d > reach:
			continue
		var busy := 1 if prefer_free and e.is_stunned() else 0
		rows.append([busy, d, order, e])
		order += 1
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if int(a[0]) != int(b[0]):
			return int(a[0]) < int(b[0])
		if float(a[1]) != float(b[1]):
			return float(a[1]) < float(b[1])
		return int(a[2]) < int(b[2]))
	var out: Array[Enemy] = []
	for row in rows:
		out.append(row[3] as Enemy)
	return out


## Named-buff key of [param paladin] for [param what] ("kings" -> &"kings:paladin0"): one
## per Paladin, so two Paladins' buffs stack and never remove each other's.
static func buff_key(paladin: Player, what: String) -> StringName:
	if paladin != null and paladin.slot != null:
		return StringName("%s:paladin%d" % [what, paladin.slot.index])
	return StringName("%s:paladin_%d" % [what, paladin.get_instance_id() if paladin != null else 0])


## Connects [param callable] to [param signal_ref] once.
static func connect_once(signal_ref: Signal, callable: Callable) -> void:
	if not signal_ref.is_connected(callable):
		signal_ref.connect(callable)
