class_name LootDrops
extends RefCounted
## Decides item drops when enemies die (GDD 10.1): normal enemies 1.5% (+Fortune), at most
## 1 + players item drops per wave from normal enemies. Spawns a LootBag.
## Guaranteed drops of elites, the Loot Goblin (M5) and bosses (M6) go through
## [method drop_special]: their own generator source, not counted against the cap. M6 adds the
## Artifact roll ([method roll_artifact], GDD 5.5) there and, for every kill, in
## [method on_enemy_killed] after the normal roll: ONE roll per kill (an elite calls it twice,
## a boss once per hero), from wave 10, boss 15% (+ pity) / Loot Goblin 5% / elite 2% / normal
## enemy 0.05% / party size (kills scale with the players), x (1 + the killer's Fortune %); the
## class is one of the team's (80%) or any (20%), at most one Artifact per class per run.
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

## --artifact-chance=X (LaunchOptions.artifact_chance): when >= 0 every Artifact roll uses this
## chance instead of the normal ones (debug / smoke; the wave and class rules still apply).
## -1 = off. Reset to -1 by RunState.start_run and re-applied by Main.start_run;
## [method roll_artifact] reads it.
static var artifact_chance_override := -1.0
## Test hook: when valid, [method roll_artifact] calls it with (source, enemy, killer) and
## returns its LootBag (or null) instead of rolling (the call sites stay observable).
static var artifact_roll_probe := Callable()

## Artifact drops (GDD 5.5): the first wave they can drop on, the chance per kill source and the
## extra chance a boss gains for every boss kill that dropped none (reset by a drop), and the
## share of drops that go to a class that is in the team (the rest: any class).
const ARTIFACT_MIN_WAVE := 10
const ARTIFACT_CHANCE_BOSS := 0.15
const ARTIFACT_CHANCE_GOBLIN := 0.05
const ARTIFACT_CHANCE_ELITE := 0.02
## A normal kill's chance for a SOLO run; [method artifact_chance] divides it by the party size
## (RunState.player_count), because the kills of a wave scale with the players while the
## boss / Loot Goblin / elite counts do not.
const ARTIFACT_CHANCE_NORMAL := 0.0005
const ARTIFACT_PITY_STEP := 0.05
const ARTIFACT_TEAM_CLASS_SHARE := 0.8
## Meta flag on an enemy that already made its Artifact roll (a kill rolls once).
const ARTIFACT_ROLLED_META := &"artifact_rolled"


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


## Called by Enemy on death (killer may be null). Rolls and spawns a LootBag if lucky, then
## makes the Artifact roll ([method roll_artifact], Source.LOOT – for every kill, also those of
## elites, the goblin and bosses, which additionally rolled through [method drop_special]).
## Returns the item bag (null when nothing dropped; the Artifact bag is not returned).
static func on_enemy_killed(enemy: Node3D, killer: Node3D) -> LootBag:
	if enemy == null or not is_instance_valid(enemy):
		return null
	var bag := _roll_normal_drop(enemy, killer)
	roll_artifact(ItemGenerator.Source.LOOT, enemy, killer)
	return bag


## The normal enemies' item drop of [method on_enemy_killed] (the wave cap, the chance roll).
static func _roll_normal_drop(enemy: Node3D, killer: Node3D) -> LootBag:
	if RunState.loot_drops_this_wave >= max_drops_per_wave():
		return null
	if RunState.rng.randf() >= drop_chance(killer):
		return null
	var at := enemy.global_position if enemy.is_inside_tree() else enemy.position
	return drop_item(generate_item(killer), Vector3(at.x, 0.0, at.z), enemy)


## The Artifact roll of a kill (M6 ARTIFACTS, GDD 5.5): [param source] is the generator source
## of the kill (LOOT for a normal enemy, ELITE / GOBLIN / BOSS for the special ones), [param
## enemy] the victim, [param killer] the Player who killed it (or null). Returns the Artifact's
## LootBag (it goes to the team loot like any drop and through the Need / Greed / Pass roll), or
## null when none dropped.
## Rules: only from ARTIFACT_MIN_WAVE; ONE roll per kill – the first call for an enemy rolls
## (later ones, e.g. the LOOT call after an elite's ELITE call or a boss's per-hero
## drop_special calls, are ignored) and uses the highest source of the kill (boss > goblin >
## elite > normal, whatever the call says); no roll once every class that has an Artifact got
## its one; the chance is [method artifact_chance]; a hit picks the class ([method
## pick_artifact_class]), counts it in RunState.artifact_classes / artifacts_dropped, resets the
## boss pity, and spawns the bag where the enemy died. A boss roll that misses adds
## ARTIFACT_PITY_STEP to RunState.artifact_pity.
## RunState.rng is drawn only when a roll is really made (never below wave 10), in this order:
## the chance (randf); on a hit the 80 / 20 pick (randf) and – among more than one class – the
## class (randi_range).
static func roll_artifact(source: ItemGenerator.Source, enemy: Node3D, killer: Node3D) -> LootBag:
	if artifact_roll_probe.is_valid():
		return artifact_roll_probe.call(source, enemy, killer) as LootBag
	if enemy == null or not is_instance_valid(enemy) or RunState.wave < ARTIFACT_MIN_WAVE:
		return null
	if enemy.has_meta(ARTIFACT_ROLLED_META) or artifact_candidates(false).is_empty():
		return null
	var kill_source := kill_artifact_source(enemy, source)
	var chance := artifact_chance(kill_source, killer)
	if chance <= 0.0:
		return null
	enemy.set_meta(ARTIFACT_ROLLED_META, true)
	var hit := RunState.rng.randf() < chance
	if not hit:
		if kill_source == ItemGenerator.Source.BOSS:
			RunState.artifact_pity += ARTIFACT_PITY_STEP
		return null
	var class_id := pick_artifact_class(RunState.rng)
	var item := ItemGenerator.generate_artifact(class_id, RunState.wave)
	if item == null:
		return null
	RunState.artifact_classes.append(class_id)
	RunState.artifacts_dropped += 1
	RunState.artifact_pity = 0.0
	item.looted = true
	var at := enemy.global_position if enemy.is_inside_tree() else enemy.position
	var bag := _place_bag(item, Vector3(at.x, 0.0, at.z), enemy)
	if bag == null:
		RunState.add_team_loot(item)  # nowhere to put a bag (no arena): the team still gets it
	else:
		Vfx.floating_text(Vector3(at.x, 2.4, at.z), "Artifact!", UiTheme.RARITY_COLORS[Items.Rarity.ARTIFACT], 1.6)
	RunState.artifact_dropped.emit(item, ItemGenerator.SOURCE_IDS[kill_source])
	return bag


## The source a kill's Artifact roll counts as: the highest of [param source] and what the
## enemy is (a boss, the Loot Goblin) – BOSS > GOBLIN > ELITE > LOOT (the enum order).
static func kill_artifact_source(enemy: Node3D, source: ItemGenerator.Source) -> ItemGenerator.Source:
	var best := source
	if enemy != null and is_instance_valid(enemy):
		var is_boss := enemy.has_method(&"is_boss") and bool(enemy.call(&"is_boss"))
		if is_boss:
			best = ItemGenerator.Source.BOSS
		elif enemy is LootGoblin and best < ItemGenerator.Source.GOBLIN:
			best = ItemGenerator.Source.GOBLIN
	return best


## Artifact chance (0..1) of one roll for a kill of [param source] by [param killer]: the table
## chance (a boss's plus RunState.artifact_pity; a normal kill's divided by the party size,
## [method normal_chance]) x (1 + the killer's Fortune / 100), or artifact_chance_override when
## it is on. Not the shop.
static func artifact_chance(source: ItemGenerator.Source, killer: Node3D) -> float:
	if artifact_chance_override >= 0.0:
		return clampf(artifact_chance_override, 0.0, 1.0)
	var base := 0.0
	match source:
		ItemGenerator.Source.BOSS:
			base = ARTIFACT_CHANCE_BOSS + RunState.artifact_pity
		ItemGenerator.Source.GOBLIN:
			base = ARTIFACT_CHANCE_GOBLIN
		ItemGenerator.Source.ELITE:
			base = ARTIFACT_CHANCE_ELITE
		ItemGenerator.Source.LOOT:
			base = normal_chance()
	return clampf(base * (1.0 + killer_fortune(killer) / 100.0), 0.0, 1.0)


## The Artifact chance of a normal enemy kill before Fortune: [constant ARTIFACT_CHANCE_NORMAL]
## divided by the party size (RunState.player_count, at least 1) – a bigger party makes
## proportionally more kills, so the expected number of normal-kill Artifacts per run does not
## grow with it.
static func normal_chance() -> float:
	return ARTIFACT_CHANCE_NORMAL / float(maxi(1, RunState.player_count))


## The class ids an Artifact may still drop for: classes that have one and did not get theirs
## yet (RunState.artifact_classes), lobby order; with [param team_only] only the classes the
## joined players play.
static func artifact_candidates(team_only: bool) -> Array[StringName]:
	var team: Array[StringName] = []
	if team_only:
		for c in team_classes():
			team.append(c.id)
	var out: Array[StringName] = []
	for id in Db.artifact_classes():
		if id in RunState.artifact_classes or (team_only and id not in team):
			continue
		out.append(id)
	return out


## The class an Artifact drop is for: ARTIFACT_TEAM_CLASS_SHARE of the drops go to a class in
## the team that has no Artifact yet (when there is none left, to any class that has none), the
## rest to any such class. &"" when every class got its Artifact. Draws a randf and, among more
## than one class, a randi_range from [param rng] (nothing when none is left).
static func pick_artifact_class(rng: RandomNumberGenerator) -> StringName:
	var any := artifact_candidates(false)
	if any.is_empty():
		return &""
	var team := artifact_candidates(true)
	var pool := team if rng.randf() < ARTIFACT_TEAM_CLASS_SHARE and not team.is_empty() else any
	return pool[0] if pool.size() == 1 else pool[rng.randi_range(0, pool.size() - 1)]


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
	var bag := _place_bag(_generate(source, killer), Vector3(at.x, 0.0, at.z), enemy)
	roll_artifact(source, enemy, killer)
	return bag


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
