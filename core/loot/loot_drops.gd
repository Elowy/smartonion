class_name LootDrops
extends RefCounted
## Decides item drops when enemies die (GDD 10.1): normal enemies 1.5% (+Fortune), at most
## 1 + players item drops per wave from normal enemies. Spawns a LootBag.
## Guaranteed drops of elites, the Loot Goblin (M5) and bosses (M6) go through
## [method drop_special]: their own generator source, not counted against the cap. M6 adds the
## Artifact roll there (and the normal enemies' one in on_enemy_killed).
## Every generated drop passes the party's classes (&"team_classes", [method team_classes]) so
## class-bound content (tier set pieces) is rolled for a class that is playing.
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


## The joined players' classes, each once, in slot order (slots without a class are skipped).
static func team_classes() -> Array[ClassData]:
	var out: Array[ClassData] = []
	for s in PlayerManager.get_slots():
		if s.class_data != null and s.class_data not in out:
			out.append(s.class_data)
	return out


## A new looted item at the current wave (Source.LOOT, killer's Fortune).
static func generate_item(killer: Node3D) -> ItemInstance:
	return _generate(ItemGenerator.Source.LOOT, killer)


## A guaranteed drop of an elite / the Loot Goblin / a boss ([param source] ELITE / GOBLIN /
## BOSS – the generator's rarity rules for it), with [param killer]'s Fortune, at
## [param enemy]'s position. Unlike normal drops it is not counted in
## RunState.loot_drops_this_wave (the cap stays for normal enemies). Returns the bag (null when
## there is nowhere to put it).
static func drop_special(source: ItemGenerator.Source, enemy: Node3D, killer: Node3D) -> LootBag:
	if enemy == null or not is_instance_valid(enemy):
		return null
	var at := enemy.global_position if enemy.is_inside_tree() else enemy.position
	return _place_bag(_generate(source, killer), Vector3(at.x, 0.0, at.z), enemy)


## A looted item of [param source] at the current wave (killer's Fortune, the team's classes).
static func _generate(source: ItemGenerator.Source, killer: Node3D) -> ItemInstance:
	var wave := maxi(1, RunState.wave)
	var item := ItemGenerator.generate(source, wave, RunState.rng,
		{&"fortune": killer_fortune(killer), &"team_classes": team_classes()})
	item.looted = true
	if item.buy_price <= 0:
		item.buy_price = ItemGenerator.price_for(item.rarity, wave)
	return item


## Puts [param item] on the ground at [param world_pos] (counts as a normal-enemy drop for
## the wave cap). The bag goes under Arena.current.entities, else under [param fallback]'s
## parent. Returns null when there is nowhere to put it.
static func drop_item(item: ItemInstance, world_pos: Vector3, fallback: Node = null) -> LootBag:
	var bag := _place_bag(item, world_pos, fallback)
	if bag != null:
		RunState.loot_drops_this_wave += 1
	return bag


## A LootBag with [param item] at [param world_pos] (see [method drop_item]; not counted).
static func _place_bag(item: ItemInstance, world_pos: Vector3, fallback: Node) -> LootBag:
	var parent := _world_parent(fallback)
	if item == null or parent == null:
		return null
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
