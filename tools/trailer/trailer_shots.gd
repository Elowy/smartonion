class_name TrailerShots
extends RefCounted
## Dev tool (tools/trailer/): the reusable staging recipes of the takes – conditions to wait for ("a hero is in the
## thick of a fight", "the loot roll is open") and the small set pieces (a loot burst, a Legendary in the roll, the
## forge on a panel). Everything goes through the game's public API; nothing changes how the game plays.

const PANEL_CENTERS: Array[Vector2] = [Vector2(304, 214), Vector2(1616, 214), Vector2(304, 868), Vector2(1616, 868)]


# --- Conditions ----------------------------------------------------------------------------------------------------

static func enemies(d: TrailerDirector) -> int:
	return d.get_tree().get_node_count_in_group(&"enemies")


## Enemies within [param radius] metres of [param hero].
static func enemies_near(d: TrailerDirector, hero: Player, radius: float) -> int:
	var n := 0
	for node in d.get_tree().get_nodes_in_group(&"enemies"):
		var e := node as Node3D
		if e != null and e.is_inside_tree() and e.global_position.distance_to(hero.global_position) <= radius:
			n += 1
	return n


## Largest distance between two living heroes (a tight party reads as one fight on the screen).
static func party_spread(d: TrailerDirector) -> float:
	var worst := 0.0
	var list := d.heroes()
	for a in list:
		for b in list:
			if a != b and a.is_alive() and b.is_alive():
				worst = maxf(worst, a.global_position.distance_to(b.global_position))
	return worst


static func in_wave(d: TrailerDirector, wave: int) -> bool:
	return d.main.state == Main.State.WAVE and d.main.wave >= wave


static func in_phase(d: TrailerDirector, phase: Intermission.Phase) -> bool:
	return d.main.state == Main.State.INTERMISSION and d.main.intermission != null and d.main.intermission.phase == phase


static func centroid(d: TrailerDirector) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for p in d.heroes():
		if p.is_alive():
			sum += p.global_position
			n += 1
	return sum / float(n) if n > 0 else Vector3.ZERO


# --- Cuts -----------------------------------------------------------------------------------------------------------

## A close cut on [param hero]: waits (fast-forwarding) until [param min_enemies] enemies are within 6 m, then
## records [param secs] seconds of a camera that settles in on the hero. The HUD is off for it.
static func class_cut(d: TrailerDirector, hero: Player, clip: String, secs: float, yaw: float, min_enemies: int = 4,
		pitch: float = 40.0, dist: float = 7.4) -> void:
	if min_enemies > 0:
		await d.fast_forward_until(func() -> bool: return not is_instance_valid(hero) or enemies_near(d, hero, 6.5) >= min_enemies,
				1.5, 40.0)
	d.hud_visible(false)
	d.cam_free(TrailerDirector.pose(hero.global_position + Vector3(0, 0.5, 0), dist * 1.2, pitch + 8.0, yaw, 38.0))
	d.cam_track(hero, Vector3(0, 0.5, 0), 11.0)
	d.begin_clip(clip)
	d.cam_to(TrailerDirector.pose(Vector3.ZERO, dist, pitch, yaw * -0.4, 38.0), secs, 1.5)
	await d.seconds(secs)
	d.end_clip()


## The camera of a boss shot: free, looking at the middle between the party and the boss (or the boss's rune while it is
## still arriving), so both stay in the picture.
static func boss_camera(d: TrailerDirector, dist: float = 17.0, pitch: float = 46.0, yaw: float = 6.0) -> void:
	d.cam_free(TrailerDirector.pose(centroid(d), dist, pitch, yaw, 40.0))
	d.cam_track_fn(func() -> Vector3:
		var focus := centroid(d)
		var director := d.main.wave_director
		if director != null:
			var boss: Boss = director.boss
			if is_instance_valid(boss) and not boss.is_dead():
				focus = focus.lerp(boss.global_position, 0.55)
			elif float(director.get(&"_boss_arrival_left")) >= 0.0:
				focus = focus.lerp(director.get(&"_boss_arrival_pos") as Vector3, 0.55)
		return focus + Vector3(0, 0.5, 0), 2.2)


# --- Loot -----------------------------------------------------------------------------------------------------------

## Drops a bag of each rarity in [param rarities] in a fan in front of the party (they pop out with their beams).
static func loot_burst(d: TrailerDirector, rng: RandomNumberGenerator, rarities: Array[int], spacing: float = 1.7,
		gap_seconds: float = 0.35) -> void:
	var heroes := d.heroes()
	if heroes.is_empty():
		return
	var centre := centroid(d)
	var n := rarities.size()
	for i in n:
		var hero: Player = heroes[i % heroes.size()]
		var item: ItemInstance
		if rarities[i] >= Items.Rarity.ARTIFACT:
			item = ItemGenerator.generate_artifact(hero.class_data.id, maxi(RunState.wave, 1))
		else:
			item = ItemGenerator.generate(ItemGenerator.Source.LOOT, maxi(RunState.wave, 1), rng,
					{&"rarity": rarities[i], &"usable_by": hero.class_data, &"class_data": hero.class_data})
		if item == null:
			continue
		item.looted = true
		var x := (float(i) - float(n - 1) * 0.5) * spacing
		var at := centre + Vector3(x, 0.0, 3.6 - absf(x) * 0.2)
		LootDrops.drop_item(item, Vector3(at.x, 0.0, at.z))
		await d.seconds(gap_seconds)


## Puts a Legendary and the Artifact of the first hero that has one at the FRONT of the team loot, so the loot roll opens
## with them.
static func queue_big_loot(d: TrailerDirector, rng: RandomNumberGenerator) -> void:
	var wave := maxi(RunState.wave, 1)
	var heroes := d.heroes()
	var front: Array[ItemInstance] = []
	for hero in heroes:
		var item := ItemGenerator.generate(ItemGenerator.Source.LOOT, wave, rng,
				{&"rarity": Items.Rarity.LEGENDARY, &"usable_by": hero.class_data, &"class_data": hero.class_data})
		if item != null:
			item.looted = true
			front.append(item)
			break
	for hero in heroes:
		var artifact := ItemGenerator.generate_artifact(hero.class_data.id, wave)
		if artifact != null:
			artifact.looted = true
			front.append(artifact)
			break
	for i in front.size():
		RunState.team_loot.insert(i, front[i])
	RunState.team_loot_changed.emit()


# --- The break's panels -------------------------------------------------------------------------------------------

## The market opens with the bots idle for [param seconds] (they shop half-way through it).
static func hold_market(d: TrailerDirector, seconds: float) -> void:
	if d.main.intermission != null:
		d.main.intermission.bot_market_time = seconds


## Stages the forge on the panel of [param slot_index]: two Rare weapons of the same base in the backpack, the
## Character tab, the first one selected with its menu open on "Forge". Returns the item the forge would use (null when
## nothing could be staged); [method do_forge] then forges it.
static func stage_forge(d: TrailerDirector, slot_index: int, rng: RandomNumberGenerator) -> ItemInstance:
	var im := d.main.intermission
	if im == null or not im.panels.has(slot_index):
		return null
	var panel: PlayerPanel = im.panels[slot_index]
	var hero := panel.slot.player as Player
	if hero == null or not is_instance_valid(hero):
		return null
	var eq := hero.equipment
	var base: WeaponData = hero.class_data.main_hand
	if base == null:
		return null
	var wave := maxi(RunState.wave, 1)
	var first := ItemGenerator.generate_weapon(base, Items.Rarity.RARE, wave, true, rng)
	var second := ItemGenerator.generate_weapon(base, Items.Rarity.RARE, wave, true, rng)
	if first == null or second == null or not eq.add_to_backpack(first) or not eq.add_to_backpack(second):
		return null
	panel.refresh()
	panel.set_tab(PlayerPanel.CHARACTER_TAB)
	var index := eq.backpack.find(first)
	panel.select_backpack(index)
	panel.open_menu()
	panel.select_menu_entry("Forge")
	return first


## Shows tab [param tab] (PlayerPanel.*_TAB) on the panel of [param slot_index].
static func show_tab(d: TrailerDirector, slot_index: int, tab: int) -> void:
	var im := d.main.intermission
	if im != null and im.panels.has(slot_index):
		(im.panels[slot_index] as PlayerPanel).set_tab(tab)


## Does the forge staged by [method stage_forge] (the panel's own Forge action: the toast, the result selected).
static func do_forge(d: TrailerDirector, slot_index: int, item: ItemInstance) -> void:
	var im := d.main.intermission
	if im == null or not im.panels.has(slot_index) or item == null:
		return
	var panel: PlayerPanel = im.panels[slot_index]
	panel.call(&"_do_forge", item)
