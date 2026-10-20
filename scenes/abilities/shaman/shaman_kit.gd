class_name ShamanKit
extends RefCounted
## Shared helpers of the Shaman's kit (M8, design_shaman.md): spell / weapon-strike / heal maths, the
## "empower" hook of Elemental Surge, the Storm Echo strike, the data the Artifact reads from the last
## Forking Bolt, and the enemy / hero queries around a point (XZ, deterministic group order). The
## talent scripts under scenes/talents/shaman/ and the Artifact property use the same helpers.
##
## Spell damage = (damage + Intellect x intellect_scale + Spell Power x spell_power_scale x seconds) x
## (Versatility + Damage % + school %) x "power" (ability Ranks II / IV). Target bonuses, the Mastery
## and the outgoing multipliers come on top in ProcSystem.deal_raw. The Spell Power part is "per
## second": a repeating effect passes its tick length as [code]sp_seconds[/code].

const NATURE := &"nature"
const FIRE := &"fire"
const SURGE_ID := &"surge"
## Pseudo ability ids of the class's non-ability numbers (BonusVocabulary.PSEUDO_IDS).
const TOTEMS_MOD_ID := &"shaman_totems"
const ECHO_MOD_ID := &"shaman_echo"
## Flat damage of a "weapon" strike when the Shaman holds no weapon (bare fists).
const FALLBACK_DAMAGE := 3.0
## Light blue of lightning, orange of fire and the element colours of the totems.
const LIGHTNING_COLOR := Color(0.62, 0.84, 1.0)
const FIRE_COLOR := Color(1.0, 0.5, 0.15)
const WATER_COLOR := Color(0.3, 0.6, 1.0)
const EARTH_COLOR := Color(0.65, 0.5, 0.3)
const AIR_COLOR := Color(0.8, 0.95, 1.0)
const BOND_COLOR := Color(0.85, 0.75, 1.0)
const STORM_COLOR := Color(0.55, 0.8, 1.0)
const ELEMENT_COLORS: Dictionary[StringName, Color] = {
	&"fire": FIRE_COLOR, &"water": WATER_COLOR, &"earth": EARTH_COLOR, &"air": AIR_COLOR,
	&"bond": BOND_COLOR, &"storm": STORM_COLOR,
}
## Spirit wolves: a teal ghost.
const WOLF_COLOR := Color(0.45, 0.92, 0.86, 0.74)
const TEXT_COLOR := Color(0.55, 0.85, 1.0)


# --- Maths -------------------------------------------------------------------------------------

## Damage of one hit / one second of [param params] for [param stats] (see the class doc). At least
## CombatMath.MIN_DAMAGE.
static func spell_damage(stats: StatBlock, params: Dictionary, school: StringName, sp_seconds: float = 1.0) -> float:
	var flat := float(params.get("damage", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.INTELLECT)) * float(params.get("intellect_scale", 0.0)) \
			+ maxf(0.0, stats.get_raw(Stats.SPELL_POWER)) * float(params.get("spell_power_scale", 0.0)) * sp_seconds
	return maxf(CombatMath.MIN_DAMAGE, flat * CombatMath.damage_mult_for(stats, school)) * power(params)


## The rank multiplier of damage / heal amounts ("power", 1.0 at Rank I).
static func power(params: Dictionary) -> float:
	var v: Variant = params.get("power", 1.0)
	return maxf(0.0, float(v)) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 1.0


## Damage of a weapon-based Shaman strike (Magma Lash): [param weapon_pct] % of the main hand's flat
## hit (base + stat scaling + speed-normalised Attack / Spell Power) + [param sp_scale] x Spell Power,
## times Versatility + Damage % + school %, times [param power]. The formula of PaladinKit.strike_damage
## with a free school (Fire for the Magma Lash).
static func weapon_strike(player: Player, weapon_pct: float, sp_scale: float, power_mult: float = 1.0,
		school: StringName = FIRE) -> float:
	if player == null:
		return CombatMath.MIN_DAMAGE
	var stats := player.stats
	var base := FALLBACK_DAMAGE + maxf(0.0, stats.get_raw(Stats.INTELLECT))
	if player.main_hand != null and player.main_hand.base_damage > 0.0:
		base = CombatMath.weapon_base_damage(player.main_hand, stats)
	var flat := base * weapon_pct / 100.0 + maxf(0.0, stats.get_raw(Stats.SPELL_POWER)) * sp_scale
	return maxf(CombatMath.MIN_DAMAGE, flat * CombatMath.damage_mult_for(stats, school)) * maxf(0.0, power_mult)


## A Shaman heal on [param who]: [param flat] + [param max_hp_pct] % of the healed hero's Max HP +
## [param sp_scale] x the caster's Spell Power, times [param power_mult], times the caster's Healing Done.
static func heal_amount(caster: Player, who: Player, flat: float, max_hp_pct: float, sp_scale: float,
		power_mult: float = 1.0) -> float:
	var sp := maxf(0.0, caster.stats.get_raw(Stats.SPELL_POWER)) if caster != null else 0.0
	var max_hp := who.max_hp() if who != null else 0.0
	return maxf(0.0, (flat + max_hp * max_hp_pct / 100.0 + sp * sp_scale) * maxf(0.0, power_mult)) \
			* healing_mult(caster)


## 1 + Healing Done / 100 of [param caster] (negative values count as 0; 1 for null).
static func healing_mult(caster: Player) -> float:
	if caster == null:
		return 1.0
	return 1.0 + maxf(0.0, caster.stats.get_raw(Stats.HEALING_DONE)) / 100.0


## The totem numbers of [param player]: [param base] (a Totem Rite params dictionary, rank / spec /
## item mods of the ability already in) with the mods of the pseudo ability [constant TOTEMS_MOD_ID]
## (talents, the set bonus, items) on top: "duration_pct", "power_pct", "earth_slow_add" ...
static func totem_params(player: Player, base: Dictionary) -> Dictionary:
	var mods: Dictionary = player.ability_mods(TOTEMS_MOD_ID) if player != null else {}
	return AbilityRunner.apply_mods(base, mods) if not mods.is_empty() else base.duplicate(true)


# --- Mastery hooks ------------------------------------------------------------------------------

static func mastery_of(player: Player) -> ShamanMastery:
	if player == null or player.abilities == null:
		return null
	return player.abilities.mastery as ShamanMastery


## Elemental Surge: the damage multiplier of the cast that calls this (1.0 without a charge); every
## damaging Shaman ability calls it exactly once at the top of its cast and multiplies ALL the
## damage of that cast with the result (jumps, quake ticks, burns, bites, Storm Echo).
static func empower(player: Player) -> float:
	var m := mastery_of(player)
	return m.take_empower() if m != null else 1.0


## The Shaman's Surge pool (null without one).
static func surge(player: Player) -> ClassResource:
	if player == null or player.abilities == null:
		return null
	return player.abilities.get_resource(SURGE_ID)


## +[param amount] Surge (Resource Regen counts like for any gain).
static func add_surge(player: Player, amount: float) -> void:
	var res := surge(player)
	if res != null and amount > 0.0:
		res.add(amount)


## One direct hit of a Shaman ability: deal_raw as &"ability" (kill credit, damage meter, Mastery and
## talent multipliers) and - when [param echo] - the Storm Echo roll ([method ShamanMastery.roll_echo]).
## [param amount] is the amount before the outgoing multipliers. Returns the damage dealt.
static func strike(player: Player, enemy: Enemy, amount: float, school: StringName, echo: bool = true) -> float:
	if player == null or player.procs == null or not is_live(enemy):
		return 0.0
	var dealt := player.procs.deal_raw(enemy, amount, school, true, &"ability")
	if echo and dealt > 0.0:
		var m := mastery_of(player)
		if m != null:
			m.roll_echo(enemy, amount, school)
	return dealt


## The last Forking Bolt of [param player]: {"point": where it first struck, "damage": the first hit's
## amount before the multipliers, Elemental Surge baked in} (the Thunderpost Artifact reads it). Empty
## until a bolt was cast.
static func last_fork(player: Player) -> Dictionary:
	var m := mastery_of(player)
	return m.last_fork.duplicate() if m != null else {}


static func set_last_fork(player: Player, point: Vector3, damage: float) -> void:
	var m := mastery_of(player)
	if m != null:
		m.last_fork = {"point": point, "damage": damage}


# --- Queries ------------------------------------------------------------------------------------

static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func is_live(e: Variant) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	var enemy := e as Enemy
	return enemy != null and enemy.is_inside_tree() and not enemy.is_dead()


## Chest height of an enemy (beams, sparks).
static func chest(e: Node3D) -> Vector3:
	var enemy := e as Enemy
	var scale_mult := enemy.data.model_scale if enemy != null and enemy.data != null else 1.0
	return e.global_position + Vector3.UP * Enemy.BODY_CENTER_HEIGHT * scale_mult


## Living enemies whose body touches the circle at [param center] (XZ), in group order.
static func enemies_around(tree: SceneTree, center: Vector3, radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if tree == null or radius < 0.0:
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
static func count_around(tree: SceneTree, center: Vector3, radius: float) -> int:
	return enemies_around(tree, center, radius).size()


## Up to [param count] living enemies whose centre is within [param max_range] of [param origin] (XZ),
## nearest first (ties in group order), that are not in [param exclude].
static func nearest_enemies(tree: SceneTree, origin: Vector3, max_range: float, count: int,
		exclude: Array[Enemy] = []) -> Array[Enemy]:
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
		found.append([d, order, e])
	if found.size() > 1:
		found.sort_custom(func(a: Array, b: Array) -> bool:
			return float(a[0]) < float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
	for f in found:
		if out.size() >= count:
			break
		out.append(f[2] as Enemy)
	return out


## True when a living enemy within [param max_range] of [param origin] passes [param accept]
## (Callable(Enemy) -> bool; invalid = any).
static func any_enemy(tree: SceneTree, origin: Vector3, max_range: float, accept: Callable = Callable()) -> bool:
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
static func heroes_around(tree: SceneTree, center: Vector3, radius: float) -> Array[Player]:
	var out: Array[Player] = []
	for p in living_heroes(tree):
		if flat_distance(p.global_position, center) <= radius + 0.001:
			out.append(p)
	return out


## 0..1 share of max HP (1 for a missing hero).
static func hp_ratio(p: Player) -> float:
	if p == null or p.max_hp() <= 0.0:
		return 1.0
	return clampf(p.hp / p.max_hp(), 0.0, 1.0)


## Alive and below max HP.
static func is_hurt(p: Player) -> bool:
	return p != null and p.is_alive() and p.hp < p.max_hp() - 0.001


## The living hero within [param radius] of [param center] with the lowest HP share (ties: the nearest to
## [param center], then group order); [param hurt_only] skips heroes at full HP; [param exclude] is left
## out (null: the caster counts too). Null when there is none.
static func lowest_hero(tree: SceneTree, center: Vector3, radius: float, hurt_only: bool = true,
		exclude: Player = null) -> Player:
	var best: Player = null
	var best_ratio := 2.0
	var best_dist := INF
	for p in heroes_around(tree, center, radius):
		if p == exclude or (hurt_only and not is_hurt(p)):
			continue
		var r := hp_ratio(p)
		var d := flat_distance(p.global_position, center)
		if r < best_ratio - 0.0001 or (absf(r - best_ratio) <= 0.0001 and d < best_dist):
			best_ratio = r
			best_dist = d
			best = p
	return best


## Pushes [param e] away from [param from] like a weapon knockback of [param strength] (12 ~ 3 m; the
## enemy's knockback resistance applies).
static func knock_back(e: Enemy, from: Vector3, strength: float) -> void:
	if not is_live(e) or strength <= 0.0:
		return
	var away := Vector3(e.global_position.x - from.x, 0.0, e.global_position.z - from.z)
	if away.length_squared() < 0.0001:
		away = Vector3.RIGHT
	var resist := clampf(e.data.knockback_resist, 0.0, 1.0) if e.data != null else 0.0
	var push := away.normalized() * strength * Enemy.KNOCKBACK_VELOCITY_PER_UNIT * (1.0 - resist)
	e.knockback_velocity = (e.knockback_velocity + push).limit_length(Enemy.MAX_KNOCKBACK_SPEED)


## The slot index of [param p] for stat-source keys ("totem_air:0"); the instance id without a slot.
static func slot_key(p: Player) -> String:
	if p != null and p.slot != null:
		return str(p.slot.index)
	return "i%d" % (p.get_instance_id() if p != null else 0)
