class_name TrailerTakes
extends RefCounted
## The takes of the trailer (dev tool, see trailer_director.gd): every take is one play session of the real game,
## cut into named clips by the director. make_trailer.sh renders each take once and edits the clips together.

const TAKES := {
	&"probe": {"args": ["--players=4", "--classes=warrior,mage,paladin,rogue", "--env=swamp", "--seed=3", "--start-wave=1"]},
	## Cold open: the party in its tier sets on wave 7 of the forest ruin, a dolly from a hero's face to the arena.
	&"intro": {"args": ["--players=4", "--classes=warrior,mage,paladin,rogue", "--env=forest_ruin", "--seed=12", "--start-wave=11",
		"--start-level=12"]},
	## The co-op chaos and the class cuts (party A, the volcano, wave 12 with the heroes in their tier sets).
	&"classes_a": {"args": ["--players=4", "--classes=warrior,mage,hunter,shaman", "--companion=wolf", "--env=volcano", "--seed=3",
		"--start-wave=12", "--start-level=18"]},
	## The long run (party B, the cemetery): the dungeon, Morvain, the break screens, the class cuts, the climax and
	## Vor'thalax. --t-dungeon-wave=N --t-boss-wave=N --t-speed=X rehearse it on a short run (--start-wave=N).
	&"main": {"args": ["--players=4", "--classes=paladin,rogue,warlock,hunter", "--companion=wolf", "--env=cemetery", "--seed=4"]},
	## The arena roll reel and a quick look at every arena (a run per arena).
	&"arenas": {"args": ["--players=4", "--classes=warrior,mage,paladin,rogue", "--seed=6", "--view=lobby", "--env=ice_cave"]},
	## Glamour shots in the studio: the seven class tier sets, the Artifact close-up.
	&"sets": {"stage": true, "args": []},
	## The end card's hero.
	&"endcard": {"stage": true, "args": []},
	## Scouting the break screens: plays wave --t-wave, then records the break for --t-secs.
	&"scout_im": {"args": ["--players=4", "--classes=paladin,rogue,warlock,hunter", "--env=cemetery", "--seed=4", "--start-wave=8",
		"--start-level=14", "--panel-tab=talents"]},
	## Scouting: --t-wave=N --t-secs=S --t-dist=D --t-pitch=P --t-preview ...
	&"scout": {"args": ["--players=4", "--classes=warrior,mage,paladin,rogue", "--env=swamp", "--seed=3"]},
}


## A take without the game: it builds its own scene (a studio) under the director.
static func is_stage(take: String) -> bool:
	return bool(TAKES[StringName(take)].get("stage", false))


static func has_take(take: String) -> bool:
	return StringName(take) in TAKES


static func names() -> Array[String]:
	var out: Array[String] = []
	for k: StringName in TAKES:
		out.append(String(k))
	return out


static func game_args(take: String) -> PackedStringArray:
	return PackedStringArray(TAKES[StringName(take)]["args"])


static func play(take: String, d: TrailerDirector) -> void:
	match take:
		"probe":
			await _probe(d)
		"scout":
			await _scout(d)
		"intro":
			await _intro(d)
		"scout_im":
			await _scout_im(d)
		"classes_a":
			await _classes_a(d)
		"main":
			await _main(d)
		"arenas":
			await _arenas(d)
		"sets":
			await _sets(d)
		"endcard":
			await _endcard(d)


static func _probe(d: TrailerDirector) -> void:
	d.guard_party()
	await d.fast_forward_until(func() -> bool: return d.main.state == Main.State.WAVE and d.main.wave >= 6, 8.0)
	d.begin_clip("probe")
	await d.seconds(4.0)
	d.end_clip()


## Scouting: plays to wave --t-wave, then records --t-secs seconds with the camera at --t-dist / --t-pitch.
static func _scout(d: TrailerDirector) -> void:
	d.guard_party()
	var wave: int = d.param("wave", 8)
	await d.fast_forward_until(func() -> bool: return d.main.state == Main.State.WAVE and d.main.wave >= wave, 8.0)
	if d.param_bool("nohud"):
		d.hud_visible(false)
	var dist: float = d.param("dist", 0.0)
	if dist > 0.0:
		d.cam_free()
		d.cam_track_fn(func() -> Vector3: return _centroid(d), 2.0)
		d.cam_to(TrailerDirector.pose(_centroid(d), dist, d.param("pitch", 57.0), d.param("yaw", 0.0)))
	d.begin_clip("scout_w%d" % wave)
	await d.seconds(d.param("secs", 8.0))
	d.end_clip()


## The mean position of the living heroes.
static func _centroid(d: TrailerDirector) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for p in d.heroes():
		if p.is_alive():
			sum += p.global_position
			n += 1
	return sum / float(n) if n > 0 else Vector3.ZERO


## The number of enemies on the field.
static func _enemies(d: TrailerDirector) -> int:
	return d.get_tree().get_node_count_in_group(&"enemies")


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# --- Takes ---------------------------------------------------------------------------------------------------------

## Cold open: a dolly from the warrior's face (low, close) back to the gameplay view of the whole party fighting.
static func _intro(d: TrailerDirector) -> void:
	d.guard_party()
	var rng := _rng(5)
	for p in d.heroes():
		TrailerGear.dress(p, 16, rng)
	d.buff_party({Stats.STAMINA: 60.0, Stats.DAMAGE_PCT: 40.0})
	d.hud_visible(false)
	await d.fast_forward_until(func() -> bool: return _enemies(d) >= 14, 2.0, 60.0)
	var hero: Player = d.heroes()[0]
	d.cam_free(TrailerDirector.pose(hero.global_position + Vector3(0, 0.75, 0), 4.6, 17.0, -32.0, 34.0))
	d.cam_track(hero, Vector3(0, 0.75, 0), 0.0)
	d.begin_clip("intro")
	await d.seconds(2.0)
	d.cam_zoom(0.6, 52.0, 6.0, 4.6, 2.0)
	await d.seconds(5.4)
	d.end_clip()


## Scouting the break: records from the wave's end for --t-secs.
static func _scout_im(d: TrailerDirector) -> void:
	d.guard_party()
	var rng := _rng(5)
	for p in d.heroes():
		TrailerGear.dress(p, 12, rng)
	await d.fast_forward_until(func() -> bool: return d.main.state == Main.State.INTERMISSION, 8.0)
	d.begin_clip("im")
	var t := 0.0
	var last := -1
	var zoomed := false
	var secs: float = d.param("secs", 20.0)
	while t < secs:
		await d.seconds(0.5)
		t += 0.5
		var ph := d.main.intermission.phase
		if ph == Intermission.Phase.MARKET and not zoomed and d.param_bool("uizoom"):
			zoomed = true
			var layer: CanvasLayer = d.main.get_node("IntermissionLayer")
			var sc := 2.2
			var center := Vector2(300, 215)
			layer.transform = Transform2D(Vector2(sc, 0), Vector2(0, sc), center * (1.0 - sc))
		if ph != last:
			d.say("intermission phase %s" % Intermission.Phase.keys()[ph])
			last = ph
	d.end_clip()


## The seven class tier sets in a line-up (a slow orbit), then the Artifact close-up.
static func _sets(d: TrailerDirector) -> void:
	var stage := TrailerStage.create(StringName(d.param("env", "ice_cave")))
	d.add_child(stage)
	var rarity: int = d.param("rarity", 4)
	var ids: Array[StringName] = [&"warlock", &"rogue", &"warrior", &"paladin", &"mage", &"hunter", &"shaman"]
	var models: Array[OnionModel] = []
	var spacing := 1.26
	for i in ids.size():
		var f := float(i) - 3.0
		var pos := Vector3(f * spacing, 0.0, 1.4 - absf(f) * 0.5)
		var yaw := -f * 11.0
		models.append(stage.add_hero(ids[i], pos, yaw, rarity, i))
	var wolf := HunterCompanionModel.new()
	wolf.kind = &"wolf"
	stage.arena.entities.add_child(wolf)
	wolf.position = Vector3(2.0 * spacing + 0.1, 0.0, 1.4 - 2.0 * 0.5 + 1.0)
	wolf.set_facing(Vector3(-0.3, 0, 1))
	await d.frames(3)
	var look := Vector3(0, 0.7, 0.5)
	stage.aim(look, 10.8, 8.0, -22.0, 30.0)
	d.begin_clip("sets")
	var secs: float = d.param("secs", 3.6)
	var frames := roundi(secs * float(d.fps))
	for n in frames:
		var t := float(n) / float(frames)
		stage.aim(look, lerpf(11.4, 9.4, t), lerpf(7.0, 11.0, t), lerpf(-22.0, 20.0, t), 30.0)
		if n % 24 == 6:
			models[(n / 24 * 3 + 1) % models.size()].play_attack(false)
		await d.frames(1)
	d.end_clip()
	# The Hunter with the three companions (Wolf, Boar, Owl).
	for m in models:
		m.queue_free()
	wolf.queue_free()
	await d.frames(2)
	var hunter := stage.add_hero(&"hunter", Vector3(-2.2, 0, 0.2), 14.0, rarity, 5)
	var pets: Array[HunterCompanionModel] = []
	var kinds: Array[StringName] = [&"wolf", &"boar", &"owl"]
	for i in kinds.size():
		var pet := HunterCompanionModel.new()
		pet.kind = kinds[i]
		stage.arena.entities.add_child(pet)
		pet.position = Vector3(-0.35 + 1.4 * float(i), 0.0, 0.0)
		pet.set_facing(Vector3(-0.15 + 0.1 * float(i), 0, 1))
		pets.append(pet)
	await d.frames(3)
	var pet_look := Vector3(0.45, 0.8, 0.0)
	stage.aim(pet_look, 7.4, 11.0, -24.0, 30.0)
	d.begin_clip("hunter_pets")
	var pet_frames := roundi(float(d.param("pet-secs", 3.0)) * float(d.fps))
	for n in pet_frames:
		var t := float(n) / float(pet_frames)
		stage.aim(pet_look, lerpf(7.6, 6.4, t), lerpf(10.0, 13.0, t), lerpf(-24.0, 16.0, t), 30.0)
		if n == 18:
			pets[0].play_attack()
		if n == 34:
			pets[1].play_attack()
		if n == 52:
			hunter.play_attack(false)
		await d.frames(1)
	d.end_clip()


## The hero of the end card: the warrior in its set, a slow push-in at dusk.
static func _endcard(d: TrailerDirector) -> void:
	var stage := TrailerStage.create(StringName(d.param("env", "volcano")))
	d.add_child(stage)
	var m := stage.add_hero(&"warrior", Vector3(0, 0, 0), 12.0, 4, 0)
	await d.frames(3)
	d.begin_clip("endcard")
	var frames := roundi(float(d.param("secs", 6.0)) * float(d.fps))
	for n in frames:
		var t := float(n) / float(frames)
		stage.aim(Vector3(0, 1.15, 0), lerpf(6.8, 5.8, t), lerpf(9.0, 13.0, t), lerpf(-16.0, 8.0, t), 30.0)
		if n == 40:
			m.play_attack(false)
		await d.frames(1)
	d.end_clip()


## Co-op chaos with the HUD, then a cut to each hero in turn (class cuts without the HUD).
static func _classes_a(d: TrailerDirector) -> void:
	d.guard_party()
	var rng := _rng(7)
	for p in d.heroes():
		TrailerGear.dress(p, 20, rng, Items.Rarity.EPIC)
	d.buff_party({Stats.STAMINA: 40.0})
	await d.fast_forward_until(func() -> bool:
			return TrailerShots.enemies(d) >= 18 and TrailerShots.party_spread(d) < 11.0, 2.0, 150.0)
	d.hud_visible(true)
	d.cam_zoom(0.72, 55.0, 0.0)
	d.begin_clip("coop")
	await d.seconds(6.5)
	d.end_clip()
	var heroes := d.heroes()
	var yaws: Array[float] = [-18.0, 16.0, -12.0, 20.0]
	for i in heroes.size():
		await TrailerShots.class_cut(d, heroes[i], "cls_%s" % heroes[i].class_data.id, 2.2, yaws[i % yaws.size()], 4)


# --- The long run -----------------------------------------------------------------------------------------------------

## Fast-forward to [param cond]; logs and returns false when it timed out.
static func _skip(d: TrailerDirector, what: String, cond: Callable, speed: float, timeout_s: float = 1200.0) -> bool:
	var ok := await d.fast_forward_until(cond, speed, timeout_s)
	if not ok:
		d.say("TIMEOUT waiting for %s (%s)" % [what, d.state_text()])
	return ok


static func _boss_of(d: TrailerDirector) -> Boss:
	var director := d.main.wave_director
	if director == null:
		return null
	var boss: Boss = director.boss
	return boss if is_instance_valid(boss) else null


## The party plays the whole run; the clips are cut where the game has something to show (see the take's header).
static func _main(d: TrailerDirector) -> void:
	d.guard_party()
	var rng := _rng(21)
	var speed: float = d.param("speed", 10.0)
	var dungeon_wave: int = d.param("dungeon-wave", 9)
	var boss_wave: int = d.param("boss-wave", 10)
	var cut_wave: int = d.param("cut-wave", 13)
	var climax_wave: int = d.param("climax-wave", 24)
	var final_wave: int = d.param("final-wave", 25)
	var do_dungeon := not d.param_bool("no-dungeon")
	var do_boss1 := not d.param_bool("no-boss1")
	var do_cut := not d.param_bool("no-cut")
	var do_climax := not d.param_bool("no-climax")
	var do_final := not d.param_bool("no-final")
	if d.param_bool("dress"):
		for p in d.heroes():
			TrailerGear.dress(p, 18, rng)

	# --- The dungeon after the break of [dungeon_wave]: portal vote, the Defend room, the Warden, the reward roll.
	if do_dungeon:
		await _skip(d, "dungeon wave", func() -> bool: return TrailerShots.in_wave(d, dungeon_wave), speed)
		await _skip(d, "its break", func() -> bool: return d.main.state == Main.State.INTERMISSION, speed)
		if await _skip(d, "portal vote", func() -> bool: return TrailerShots.in_phase(d, Intermission.Phase.PORTAL), 3.0, 200.0):
			d.begin_clip("dungeon_portal")
			await d.seconds(3.4)
			d.end_clip()
		var defend_ready := func() -> bool:
			var dg := d.main.dungeon
			return dg != null and dg.room == Dungeon.Room.DEFEND and dg.phase == Dungeon.Phase.ROOM \
					and TrailerShots.enemies(d) >= 6
		if await _skip(d, "the Defend room", defend_ready, 3.0, 600.0):
			d.hud_visible(true)
			d.cam_zoom(0.72, 50.0, 0.0)
			d.begin_clip("dungeon_room")
			await d.seconds(4.0)
			d.end_clip()
		var warden_ready := func() -> bool:
			var dg := d.main.dungeon
			return dg != null and dg.room == Dungeon.Room.WARDEN and is_instance_valid(dg.warden) \
					and dg.warden.is_inside_tree()
		if await _skip(d, "the Warden", warden_ready, 3.0, 600.0):
			TrailerShots.boss_camera(d, 13.0, 48.0, 5.0)
			d.begin_clip("dungeon_warden")
			await d.seconds(5.0)
			d.end_clip()
		await _skip(d, "the dungeon's end", func() -> bool: return d.main.dungeon == null and d.main.state == Main.State.INTERMISSION, 4.0, 900.0)
		if await _skip(d, "the reward roll", func() -> bool: return TrailerShots.in_phase(d, Intermission.Phase.LOOT), 3.0, 60.0):
			d.begin_clip("loot_roll_epics")
			await d.seconds(6.0)
			d.end_clip()

	# --- Morvain (the boss wave).
	d.hud_visible(true)
	if do_boss1:
		await _skip(d, "the boss wave", func() -> bool: return TrailerShots.in_wave(d, boss_wave), 3.0)
		TrailerShots.boss_camera(d)
		d.begin_clip("boss1_intro")
		await d.seconds(6.0)
		d.end_clip()
		if await _skip(d, "mid-fight", func() -> bool:
				var b := _boss_of(d)
				return b != null and (b.hp_ratio() < 0.62 or b.age() > 16.0), 3.0, 400.0):
			d.begin_clip("boss1_fight")
			await d.seconds(5.0)
			d.end_clip()
		await _skip(d, "the wave's end", func() -> bool: return d.main.state != Main.State.WAVE, 3.0, 400.0)
		TrailerShots.queue_big_loot(d, rng)

		# --- The break after the boss: loot roll with a Legendary and an Artifact, level-up cards, the market.
		if await _skip(d, "the loot roll", func() -> bool: return TrailerShots.in_phase(d, Intermission.Phase.LOOT), 3.0, 60.0):
			TrailerShots.hold_market(d, 15.0)
			d.begin_clip("loot_roll")
			await d.seconds(6.4)
			d.end_clip()
		if await d.until(func() -> bool: return TrailerShots.in_phase(d, Intermission.Phase.LEVEL_UP), 8.0):
			d.begin_clip("levelup")
			await d.seconds(3.2)
			d.end_clip()
		if await _skip(d, "the market", func() -> bool: return TrailerShots.in_phase(d, Intermission.Phase.MARKET), 3.0, 120.0):
			await _market_clip(d, rng)

	# --- Waves around [cut_wave]: a loot burst and a close cut on every hero.
	if do_cut:
		await _skip(d, "the cut wave", func() -> bool: return TrailerShots.in_wave(d, cut_wave), speed)
		await _skip(d, "a busy, tight fight", func() -> bool: return TrailerShots.enemies(d) >= 14 and TrailerShots.party_spread(d) < 12.0,
				2.0, 120.0)
		d.hud_visible(true)
		d.cam_zoom(0.62, 42.0, 0.0)
		d.begin_clip("loot_drops")
		await TrailerShots.loot_burst(d, rng, [Items.Rarity.RARE, Items.Rarity.EPIC, Items.Rarity.LEGENDARY, Items.Rarity.ARTIFACT])
		await d.seconds(3.4)
		d.end_clip()
		var yaws: Array[float] = [-16.0, 18.0, -14.0, 20.0]
		var heroes := d.heroes()
		for i in heroes.size():
			await TrailerShots.class_cut(d, heroes[i], "cls_%s" % heroes[i].class_data.id, 2.3, yaws[i % yaws.size()])

	# --- The climax: the densest fight of the late waves.
	if do_climax:
		d.hud_visible(true)
		d.cam_zoom(0.7, 55.0, 0.0)
		await _skip(d, "the climax wave", func() -> bool: return TrailerShots.in_wave(d, climax_wave), speed)
		await _skip(d, "a dense fight", func() -> bool: return TrailerShots.enemies(d) >= int(d.param("climax-enemies", 60)), 2.0, 150.0)
		d.begin_clip("climax")
		await d.seconds(10.0)
		d.end_clip()

	# --- Vor'thalax.
	if do_final:
		await _skip(d, "the final wave", func() -> bool: return TrailerShots.in_wave(d, final_wave), 3.0)
		TrailerShots.boss_camera(d)
		d.begin_clip("boss2_intro")
		await d.seconds(6.0)
		d.end_clip()
		if await _skip(d, "mid-fight", func() -> bool:
				var b := _boss_of(d)
				return b != null and (b.hp_ratio() < 0.7 or b.age() > 18.0), 3.0, 600.0):
			d.begin_clip("boss2_fight")
			await d.seconds(5.0)
			d.end_clip()


## The market of the break after the boss (held open): the forge on P4's panel, then P1's talent tree as the bots spend
## their points. One long clip; the edit takes what it needs.
static func _market_clip(d: TrailerDirector, rng: RandomNumberGenerator) -> void:
	d.begin_clip("market")
	await d.seconds(2.4)
	var forged := TrailerShots.stage_forge(d, 3, rng)
	await d.ui_zoom(2.5, TrailerShots.PANEL_CENTERS[3], 1.0)
	await d.seconds(1.4)
	TrailerShots.do_forge(d, 3, forged)
	await d.seconds(2.0)
	await d.ui_zoom(1.0, Vector2(960, 540), 0.9)
	await d.seconds(0.4)
	TrailerShots.show_tab(d, 0, PlayerPanel.TALENTS_TAB)
	await d.ui_zoom(2.5, TrailerShots.PANEL_CENTERS[0], 1.0)
	await d.seconds(3.6)
	await d.ui_zoom(1.0, Vector2(960, 540), 0.9)
	await d.seconds(1.0)
	d.end_clip()


# --- Arenas -------------------------------------------------------------------------------------------------------

## "Rolling the arena..." (the lobby with the party, the reel landing on --env), then one short run per arena with a
## sweeping camera: forest ruin, swamp, ice cave, cemetery, volcano.
static func _arenas(d: TrailerDirector) -> void:
	await d.seconds(0.8)
	d.begin_clip("lobby")
	await d.seconds(2.6)
	d.end_clip()
	d.main.begin_roll()
	d.begin_clip("roll")
	await d.seconds(4.3)
	d.end_clip()
	var rng := _rng(9)
	var envs: Array[StringName] = [&"forest_ruin", &"swamp", &"ice_cave", &"cemetery", &"volcano"]
	for i in envs.size():
		d.cam_game()
		d.main.options.environment = envs[i]
		d.main.options.start_wave = 8
		d.main.options.view = ""
		d.main.options.demo = true
		d.main.start_run()
		await d.frames(2)
		d.guard_party()
		for p in d.heroes():
			TrailerGear.dress(p, 16, rng)
		d.buff_party({Stats.STAMINA: 40.0, Stats.DAMAGE_PCT: 20.0})
		d.hud_visible(false)
		await _skip(d, "a fight in %s" % envs[i], func() -> bool: return TrailerShots.enemies(d) >= 14, 1.5, 60.0)
		var flip := 1.0 if i % 2 == 0 else -1.0
		d.cam_free(TrailerDirector.pose(TrailerShots.centroid(d), 15.0, 30.0, -34.0 * flip, 42.0))
		d.cam_track_fn(func() -> Vector3: return TrailerShots.centroid(d) + Vector3(0, 0.6, 0), 3.0)
		d.begin_clip("env_%s" % envs[i])
		d.cam_to(TrailerDirector.pose(Vector3.ZERO, 12.0, 36.0, 22.0 * flip, 42.0), 2.6, 1.4)
		await d.seconds(2.6)
		d.end_clip()
