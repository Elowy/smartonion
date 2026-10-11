class_name MageSpell
extends RefCounted
## Shared rules of the Mage's spells (GDD 3.2, 6.4): spell damage with the rank's "power",
## exact enemy circles over [EnemyGrid] (group order, so every pick is deterministic), the
## nearest / toughest / random target picks (random = the given RNG, RunState.rng in play),
## freezing (stun + [MageFrozen] ice) and bookkeeping of the nodes a spell leaves behind.

const FIRE := &"fire"
const FROST := &"frost"
const ARCANE := &"arcane"
const FIRE_COLOR := Color(1.0, 0.48, 0.12)
const FROST_COLOR := Color(0.6, 0.86, 1.0)
const ARCANE_COLOR := Color(0.88, 0.5, 1.0)


## Damage of one spell hit: ([param base] + [param int_scale] x Intellect +
## [param sp_scale] x Spell Power) x (Versatility + Damage % + [param school] %), at least
## CombatMath.MIN_DAMAGE, x [param power] (ranks II / IV). With [param sp_scale] 1 this is
## CombatMath.proc_damage; many-hit spells (Arcane Missiles, burning ground) take less Spell
## Power per hit. Target bonuses, Mastery and the owner's outgoing multipliers are applied
## later by ProcSystem.deal_raw.
static func spell_damage(stats: StatBlock, base: float, int_scale: float, school: StringName,
		power: float = 1.0, sp_scale: float = CombatMath.PROC_POWER_SCALE) -> float:
	var flat := base + int_scale * maxf(0.0, stats.get_raw(Stats.INTELLECT))
	if flat <= 0.0 or power <= 0.0:
		return 0.0
	flat += sp_scale * maxf(0.0, stats.get_raw(Stats.SPELL_POWER))
	return maxf(CombatMath.MIN_DAMAGE, flat * CombatMath.damage_mult_for(stats, school)) * power


## [method spell_damage] from the params "<prefix>damage", "<prefix>int_scaling" and
## "<prefix>sp_scaling" (default 1) of [param ctx], scaled by its "power".
static func damage_from(ctx: AbilityContext, school: StringName, prefix: String = "") -> float:
	if ctx.player == null:
		return 0.0
	return spell_damage(ctx.player.stats, ctx.num(prefix + "damage"), ctx.num(prefix + "int_scaling"),
			school, ctx.num("power", 1.0), ctx.num(prefix + "sp_scaling", CombatMath.PROC_POWER_SCALE))


static func is_live(e: Variant) -> bool:
	if not is_instance_valid(e):
		return false
	var enemy := e as Enemy
	return enemy != null and enemy.is_inside_tree() and not enemy.is_dead()


## Living enemies in the circle at [param center] (XZ), in group order. [param bodies]: an
## enemy counts when its body touches the circle, else its centre must be inside.
static func enemies_in(tree: SceneTree, center: Vector3, radius: float, bodies: bool = true) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if tree == null or radius <= 0.0:
		return out
	for node in EnemyGrid.gather_around(tree, center, radius):
		var e := node as Enemy
		if e == null or not e.is_inside_tree() or e.is_dead():
			continue
		var reach := radius + (e.radius if bodies else 0.0)
		var dx := e.global_position.x - center.x
		var dz := e.global_position.z - center.z
		if dx * dx + dz * dz <= reach * reach:
			out.append(e)
	return out


## Up to [param count] living enemies whose centre is within [param reach] of
## [param center], nearest first (equal distances in group order).
static func nearest_enemies(tree: SceneTree, center: Vector3, reach: float, count: int) -> Array[Enemy]:
	var pool := enemies_in(tree, center, reach, false)
	var out: Array[Enemy] = []
	while out.size() < count and not pool.is_empty():
		var best := 0
		var best_d := INF
		for i in pool.size():
			var d := _flat_dist_sq(pool[i].global_position, center)
			if d < best_d:
				best_d = d
				best = i
		out.append(pool[best])
		pool.remove_at(best)
	return out


## The living enemy with the most HP whose centre is within [param reach] (ties: the
## nearer one, then group order). Null when there is none.
static func toughest_enemy(tree: SceneTree, center: Vector3, reach: float) -> Enemy:
	var best: Enemy = null
	var best_hp := -INF
	var best_d := INF
	for e in enemies_in(tree, center, reach, false):
		var d := _flat_dist_sq(e.global_position, center)
		if e.hp > best_hp + 0.0001 or (absf(e.hp - best_hp) <= 0.0001 and d < best_d):
			best = e
			best_hp = e.hp
			best_d = d
	return best


## A random living enemy whose centre is within [param reach] ([param rng]: RunState.rng in
## play). Null when there is none; draws nothing then.
static func random_enemy(tree: SceneTree, center: Vector3, reach: float, rng: RandomNumberGenerator) -> Enemy:
	var pool := enemies_in(tree, center, reach, false)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


## Freezes [param e] for [param duration] seconds (a stun; stun resistance shortens it) and
## shows the ice ([MageFrozen], child of the enemy). Returns the ice, null when the enemy
## shrugged the freeze off. [param shatter_damage] > 0: the ice bursts when it melts; the ice
## of one cast shares [param group] (each enemy takes that cast's shatter once).
static func freeze(e: Enemy, caster: Player, duration: float, shatter_damage: float = 0.0,
		shatter_radius: float = 1.5, group: MageFrozen.ShatterGroup = null) -> MageFrozen:
	if not is_live(e) or duration <= 0.0:
		return null
	e.apply_stun(duration)
	# Real enemies report the stun they got (0 = immune); test doubles have no data.
	var life := e.stun_left if e.stun_left > 0.0 else (duration if e.data == null else 0.0)
	if life <= 0.0:
		return null
	return MageFrozen.apply(e, caster, life, shatter_damage, shatter_radius, group)


## Area multiplier of [param player] (Area Size %).
static func area_mult(player: Player) -> float:
	return CombatMath.area_mult(player.stats) if player != null else 1.0


## Drops freed / finished nodes from [param nodes].
static func prune(nodes: Array[Node3D]) -> void:
	for i in range(nodes.size() - 1, -1, -1):
		# Check validity on the element itself: a freed node must not be copied to a typed var.
		if not is_instance_valid(nodes[i]) or nodes[i].is_queued_for_deletion() or not nodes[i].is_inside_tree():
			nodes.remove_at(i)


## Frees every node in [param nodes] (wave end, forget) and empties the list.
static func free_all(nodes: Array[Node3D]) -> void:
	for i in nodes.size():
		if is_instance_valid(nodes[i]) and not nodes[i].is_queued_for_deletion():
			nodes[i].queue_free()
	nodes.clear()


static func _flat_dist_sq(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz
