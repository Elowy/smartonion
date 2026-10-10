class_name LootDrops
extends RefCounted
## Decides item drops when enemies die (GDD 10.1): normal enemies 1.5% (+Fortune), at most
## 1 + players item drops per wave from normal enemies; elites / goblin / boss sources come
## with M5 / M6. Spawns a LootBag.
##
## Fortune formula (GDD: "Fortune increases the drop chance"): every 10 points of Fortune of
## the killer add 1 percentage point, i.e. chance = 1.5% + Fortune / 1000 (a Lucky Rabbit
## Foot with +8 Fortune: 2.3%). Kills by a non-Player (or nobody) use the base chance.
## The same Fortune is passed to the generator, which shifts the rarity upwards.

const BASE_CHANCE := 0.015
## Chance added per point of Fortune (= +Fortune / 10 percentage points).
const CHANCE_PER_FORTUNE := 0.001


## Item drops one wave may produce from normal enemies: 1 + players.
static func max_drops_per_wave() -> int:
	return 1 + RunState.player_count


## Fortune of [param killer] (0 if it is not a Player).
static func killer_fortune(killer: Node3D) -> float:
	if killer == null or not is_instance_valid(killer):
		return 0.0
	var player := killer as Player
	return maxf(0.0, player.stats.get_stat(Stats.FORTUNE)) if player != null else 0.0


## Drop chance (0..1) of a normal enemy killed by [param killer].
static func drop_chance(killer: Node3D) -> float:
	return clampf(BASE_CHANCE + killer_fortune(killer) * CHANCE_PER_FORTUNE, 0.0, 1.0)


## Called by Enemy on death (killer may be null). Rolls and spawns a LootBag if lucky.
## Returns the bag (null when nothing dropped).
static func on_enemy_killed(enemy: Node3D, killer: Node3D) -> LootBag:
	if enemy == null or not is_instance_valid(enemy):
		return null
	if RunState.loot_drops_this_wave >= max_drops_per_wave():
		return null
	if RunState.rng.randf() >= drop_chance(killer):
		return null
	var at := enemy.global_position if enemy.is_inside_tree() else enemy.position
	return drop_item(generate_item(killer), Vector3(at.x, 0.0, at.z), enemy)


## A new looted item at the current wave (Source.LOOT, killer's Fortune).
static func generate_item(killer: Node3D) -> ItemInstance:
	var wave := maxi(1, RunState.wave)
	var item := ItemGenerator.generate(ItemGenerator.Source.LOOT, wave, RunState.rng,
		{&"fortune": killer_fortune(killer)})
	item.looted = true
	if item.buy_price <= 0:
		item.buy_price = ItemGenerator.price_for(item.rarity, wave)
	return item


## Puts [param item] on the ground at [param world_pos] (counts as a normal-enemy drop for
## the wave cap). The bag goes under Arena.current.entities, else under [param fallback]'s
## parent. Returns null when there is nowhere to put it.
static func drop_item(item: ItemInstance, world_pos: Vector3, fallback: Node = null) -> LootBag:
	var parent := _world_parent(fallback)
	if item == null or parent == null:
		return null
	RunState.loot_drops_this_wave += 1
	var bag := LootBag.create(item)
	var parent_3d := parent as Node3D
	if parent_3d != null and parent_3d.is_inside_tree():
		bag.position = parent_3d.global_transform.affine_inverse() * world_pos
	else:
		bag.position = world_pos
	parent.add_child(bag)
	return bag


static func _world_parent(fallback: Node) -> Node:
	var arena := Arena.current
	if arena != null and is_instance_valid(arena) and is_instance_valid(arena.entities):
		return arena.entities
	if fallback != null and is_instance_valid(fallback):
		return fallback.get_parent()
	return null
