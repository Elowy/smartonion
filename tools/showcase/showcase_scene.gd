extends Node
## Builds the views of tools/showcase/showcase.gd (see there for usage). Dev tool only.

const CLOSE_FOV := 30.0

var _rng := RandomNumberGenerator.new()


func run() -> void:
	_rng.seed = int(_arg("seed", "5"))
	var view := _arg("view", "gameplay")
	match view:
		"live":
			await _live()
		"onions":
			await _onions()
		"hunter":
			await _hunter()
		"equip":
			await _equip()
		"sets":
			await _sets()
		"equip_game":
			await _equip_game()
		"enemies":
			await _enemies()
		"weapons":
			await _weapons()
		"arena":
			await _arena_overview()
		"revive":
			await _revive()
		"fx":
			await _fx()
		_:
			await _gameplay()
	var out := _arg("out", "/tmp/smartonion_showcase.png")
	var image: Image = null
	if DisplayServer.get_name() != "headless":
		image = get_viewport().get_texture().get_image()
	if image == null:
		printerr("showcase: nothing rendered – run with a display (xvfb-run) and --rendering-driver opengl3")
		return
	var err := image.save_png(out)
	print("showcase: %s -> %s (%s)" % [view, out, error_string(err)])


# --- Views -------------------------------------------------------------------

func _gameplay() -> void:
	var arena := _make_arena()
	add_child(arena)
	_enter_dungeon_if_asked(arena)
	var center := Vector3(float(_arg("x", "0")), 0.0, float(_arg("z", "0")))
	var spots: Array[Vector3] = [Vector3(-2.2, 0, 0.6), Vector3(-0.6, 0, -1.2), Vector3(1.2, 0, 0.2),
		Vector3(2.6, 0, -1.0), Vector3(0.4, 0, 1.8)]
	var onions: Array[OnionModel] = []
	for i in Db.class_ids.size():
		var cd := Db.get_class_data(Db.class_ids[i])
		var holder := Node3D.new()
		holder.name = "Hero%d" % i
		holder.add_to_group(&"players")
		arena.entities.add_child(holder)
		holder.position = center + spots[i % spots.size()]
		var m := OnionModel.new()
		holder.add_child(m)
		m.setup(cd, PlayerManager.PLAYER_COLORS[i % PlayerManager.PLAYER_COLORS.size()])
		m.set_tag("P%d" % (i % PlayerManager.PLAYER_COLORS.size() + 1))
		m.set_weapons(cd.main_hand, cd.off_hand)
		m.set_facing(Vector3(_rng.randf_range(-1.0, 1.0), 0, _rng.randf_range(-0.2, 1.0)))
		m.set_moving(0.7)
		onions.append(m)
	var counts := {&"skeleton_grunt": 7, &"candlekin": 10, &"marsh_gurgler": 5, &"troll_axethrower": 3}
	var enemies: Array[EnemyModel] = []
	for id: StringName in counts:
		var data := Db.get_enemy(id)
		if data == null:
			continue
		for n in int(counts[id]):
			var e := EnemyModel.new()
			arena.entities.add_child(e)
			e.setup(data)
			e.position = _free_spot(arena, center, enemies)
			e.set_facing(center - e.position)
			e.set_moving(_rng.randf_range(0.5, 1.0))
			if _rng.randf() < 0.12:
				e.set_stunned(true)
			enemies.append(e)
	if _arg("state", "") == "states":
		onions[1].set_downed(true)
		onions[1].set_revive_progress(0.45)
		onions[0].set_hp_ratio(0.3)
	arena.camera.snap()
	_force_camera_distance(arena)
	_env_hazards(arena, center, false)
	await _frames(20)
	# Slow time down so the burst is captured mid-flight.
	Engine.time_scale = 0.05
	_env_hazards(arena, center, true)
	Vfx.spawn_telegraph(center + Vector3(-6, 0, -4), 1.2, 1.0)
	Vfx.spawn_telegraph(center + Vector3(7, 0, 3), 1.0, 1.0)
	await _frames(3)
	var warrior := onions[0].get_parent() as Node3D
	onions[0].play_attack(false)
	Vfx.slash_arc(warrior.position + Vector3.UP * 0.3, Vector3(-1, 0, 0.3), 2.3, 110.0, Color(1.0, 0.9, 0.6))
	Vfx.explosion(center + Vector3(5, 0.8, -3), 1.6, Color(0.75, 0.4, 1.0))
	Vfx.death_puff(center + Vector3(-4, 0.5, 3), Color(0.9, 0.88, 0.78))
	# Damage numbers as the game shows them (small translucent hits, bigger crits) and a
	# hero's own number beside its head.
	WeaponRunner.show_damage_number(center + Vector3(-3.5, 1.2, -1), 12.0, false)
	WeaponRunner.show_damage_number(center + Vector3(-5.0, 1.2, 1.5), 6.0, false)
	WeaponRunner.show_damage_number(center + Vector3(3.8, 1.2, 0.5), 37.0, true)
	Vfx.floating_text(center + spots[0] + Vector3(Player.SELF_TEXT_SIDE, Player.SELF_TEXT_HEIGHT, 0), "2",
		Player.DAMAGE_TEXT_COLOR, Player.SELF_TEXT_SIZE, 1.0)
	Vfx.floating_text(center + Vector3(0.5, 1.4, -2.5), "Dodge", Player.DODGE_TEXT_COLOR, Player.SELF_TEXT_SIZE)
	Vfx.hit_spark(center + Vector3(-3.2, 0.6, -1.5), Color(1, 0.9, 0.5))
	Vfx.pickup_sparkle(center + Vector3(1.5, 0.3, 3.0))
	# In-flight projectiles: a troll's axe (enemy: red-orange halo) and a fel bolt (hero).
	_projectile(arena, Projectile.TEAM_ENEMIES, &"axe", Projectile.default_color(&"axe"),
		center + Vector3(-4.5, 1.0, -2.6), Vector3(1, 0, 0.55))
	_projectile(arena, Projectile.TEAM_PLAYERS, &"fireball", Color(0.4, 0.9, 0.25).lightened(0.25),
		center + Vector3(2.4, 0.7, 2.6), Vector3(1, 0, 0.3))
	if not enemies.is_empty():
		enemies[0].flash_hit()
	# Floating texts past their pop-in, so they show at their real size.
	for c in arena.entities.get_children():
		var fx := c as VfxEffect
		if fx != null and fx.kind == VfxEffect.Kind.TEXT:
			fx._process(0.2)
	await _frames(5)
	Engine.time_scale = 1.0


func _live() -> void:
	var count := clampi(int(_arg("players", "4")), 1, 4)
	RunState.start_run(count, int(_arg("seed", "7")))
	var arena := Arena.create()
	add_child(arena)
	var offset := int(_arg("classoff", "0"))
	# --geared=N (0..4): every hero wears a tier III Head / Shoulders / Chest suit of that rarity.
	var geared := int(_arg("geared", "-1"))
	for i in count:
		PlayerManager.add_bot(Db.class_ids[(i + offset) % Db.class_ids.size()], 11 + i)
	var spawns := arena.get_player_spawn_points(count)
	var i := 0
	for slot in PlayerManager.get_slots():
		var p := Player.create(slot)
		arena.entities.add_child(p)
		p.global_position = spawns[i]
		p.begin_wave()
		if geared >= 0:
			_wear_suit(p, geared)
		i += 1
	var director := WaveDirector.create(arena)
	add_child(director)
	director.start_wave(int(_arg("wave", "5")))
	arena.camera.snap()
	Engine.time_scale = float(_arg("ts", "4"))
	var target := float(_arg("t", "8"))
	var elapsed := 0.0
	while elapsed < target:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	Engine.time_scale = 1.0
	await _frames(3)
	print("showcase: %d enemies alive" % get_tree().get_nodes_in_group(&"enemies").size())


## Puts a tier III suit of [param rarity] (armour type of the class) on [param p] through its Equipment.
func _wear_suit(p: Player, rarity: int) -> void:
	for slot_type: Items.SlotType in [Items.SlotType.HEAD, Items.SlotType.SHOULDERS, Items.SlotType.CHEST]:
		var item := ItemInstance.new()
		item.display_name = "Showcase piece"
		item.slot_type = slot_type
		item.armor_type = p.class_data.armor_type
		item.rarity = rarity
		item.wave = 17
		item.item_level = Items.item_level(17, rarity, false)
		p.equipment.equip(item)


func _onions() -> void:
	var stage := _studio()
	var ids := Db.class_ids
	var state := _arg("state", "")
	var back := _arg("back", "0") == "1"
	for i in ids.size():
		var cd := Db.get_class_data(ids[i])
		var m := OnionModel.new()
		stage.add_child(m)
		m.setup(cd, PlayerManager.PLAYER_COLORS[i % PlayerManager.PLAYER_COLORS.size()])
		if _arg("tags", "0") == "1":
			m.set_tag("P%d" % (i % PlayerManager.PLAYER_COLORS.size() + 1))
		m.set_weapons(cd.main_hand, cd.off_hand)
		m.position = Vector3((i - (ids.size() - 1) * 0.5) * 1.6, 0, 0)
		m.set_facing(Vector3(0, 0, -1) if back else Vector3(0, 0, 1))
		match state:
			"hurt": m.set_hp_ratio(0.15)
			"downed":
				m.set_downed(true)
				m.set_revive_progress(0.6)
			"walk": m.set_moving(1.0)
			"attack": m.play_attack(false)
	_close_camera(stage, Vector3(0, 0.6, 0), 9.0, 22.0)
	await _frames(4 if state == "attack" else 20)


## The Hunter (M8) close up with the three companions: --back=1 shows the quiver, --state=play_dead the
## tipped-over pose, --state=frenzy the amber ring, --state=attack the lunge, --dist=N zooms.
func _hunter() -> void:
	var stage := _studio()
	var cd := Db.get_class_data(&"hunter")
	var back := _arg("back", "0") == "1"
	var state := _arg("state", "")
	var facing := Vector3(0, 0, -1) if back else Vector3(0, 0, 1)
	var m := OnionModel.new()
	stage.add_child(m)
	m.setup(cd, PlayerManager.PLAYER_COLORS[0])
	m.set_weapons(cd.main_hand, cd.off_hand)
	m.position = Vector3(-1.5, 0, 0)
	m.set_facing(facing)
	if state == "play_dead":
		m.set_play_dead(true)
	var kinds: Array[StringName] = [&"wolf", &"boar", &"owl"]
	for i in kinds.size():
		var c := HunterCompanionModel.new()
		c.kind = kinds[i]
		stage.add_child(c)
		c.position = Vector3(0.0 + 1.35 * i, 0, 0)
		c.set_facing(facing)
		match state:
			"attack": c.play_attack()
			"frenzy": c.set_frenzy(true)
			"walk": c.set_moving(1.0)
	_close_camera(stage, Vector3(0.6, 0.7, 0), 7.5, 22.0)
	await _frames(40 if state == "play_dead" else 20)


## Worn armour (GDD 13): armour types x material tiers (--axis=tier, default) or rarities of one
## armour type (--axis=rarity --armor=0..3 --tier=0..2). --rarity=N sets the rarity of the grid,
## --back=1 turns the heroes away, --state=hurt|downed.
func _equip() -> void:
	var stage := _studio()
	var axis := _arg("axis", "tier")
	var rarity := int(_arg("rarity", "2"))
	var back := _arg("back", "0") == "1"
	var armors: Array[int] = [ClassData.ArmorType.CLOTH, ClassData.ArmorType.LEATHER, ClassData.ArmorType.MAIL,
		ClassData.ArmorType.PLATE]
	var class_ids: Array[StringName] = [&"mage", &"rogue", &"warrior", &"paladin"]
	var rows := armors.size()
	var cols := 3
	if axis == "rarity" or _arg("armor", "") != "":
		var armor := int(_arg("armor", "3"))
		var default_class: StringName = class_ids[armor]
		rows = 1
		cols = 5 if axis == "rarity" else 3
		armors = [armor]
		class_ids = [StringName(_arg("class", String(default_class)))]
	var only_tier := int(_arg("tier", "-1"))
	if axis != "rarity" and only_tier >= 0:
		cols = 1
	for r in rows:
		for c in cols:
			var tier := (c if only_tier < 0 else only_tier) if axis != "rarity" else int(_arg("tier", "2"))
			var rar := rarity if axis != "rarity" else c
			var cd := Db.get_class_data(class_ids[r])
			var m := OnionModel.new()
			stage.add_child(m)
			m.setup(cd, PlayerManager.PLAYER_COLORS[(r * cols + c) % PlayerManager.PLAYER_COLORS.size()])
			m.set_weapons(cd.main_hand, cd.off_hand)
			m.set_looks(EquipLook.make(EquipLook.Slot.HEAD, armors[r], tier, rar),
				EquipLook.make(EquipLook.Slot.SHOULDERS, armors[r], tier, rar),
				EquipLook.make(EquipLook.Slot.CHEST, armors[r], tier, rar))
			m.position = Vector3((c - (cols - 1) * 0.5) * 1.7, 0, (r - (rows - 1) * 0.5) * 1.9)
			m.set_facing(Vector3(0, 0, -1) if back else Vector3(0, 0, 1))
			match _arg("state", ""):
				"hurt": m.set_hp_ratio(0.15)
				"downed":
					m.set_downed(true)
					m.set_revive_progress(0.6)
	_close_camera(stage, Vector3(0, 0.6, 0), 8.0 + rows * 3.0, 40.0 if rows > 1 else 22.0)
	await _frames(20)


## The five class tier sets worn complete on their classes, next to the starter look (--back=1).
func _sets() -> void:
	var stage := _studio()
	var ids: Array[StringName] = [&"warrior", &"mage", &"paladin", &"rogue", &"warlock"]
	var back := _arg("back", "0") == "1"
	var rarity := int(_arg("rarity", "3"))
	for r in 2:
		for i in ids.size():
			var cd := Db.get_class_data(ids[i])
			var m := OnionModel.new()
			stage.add_child(m)
			m.setup(cd, PlayerManager.PLAYER_COLORS[i % PlayerManager.PLAYER_COLORS.size()])
			m.set_weapons(cd.main_hand, cd.off_hand)
			if r == 0:
				var set_data := Db.set_for_class(ids[i])
				var sid: StringName = set_data.id if set_data != null else &""
				m.set_looks(EquipLook.make(EquipLook.Slot.HEAD, cd.armor_type, 1, rarity, sid),
					EquipLook.make(EquipLook.Slot.SHOULDERS, cd.armor_type, 1, rarity, sid),
					EquipLook.make(EquipLook.Slot.CHEST, cd.armor_type, 1, rarity, sid))
			m.position = Vector3((i - (ids.size() - 1) * 0.5) * 1.7, 0, (r - 0.5) * 2.1)
			m.set_facing(Vector3(0, 0, -1) if back else Vector3(0, 0, 1))
	_close_camera(stage, Vector3(0, 0.6, 0), 12.0, 38.0)
	await _frames(20)


## The gameplay camera (CameraRig) on a few geared heroes: how the armour reads in play.
## --facing=north|south, --tier=0..2, --rarity=N, --sets=1 (class set kits), --starter=1 (no gear).
func _equip_game() -> void:
	var arena := Arena.create()
	add_child(arena)
	var tier := int(_arg("tier", "1"))
	var rarity := int(_arg("rarity", "3"))
	var north := _arg("facing", "south") == "north"
	var ids: Array[StringName] = [&"warrior", &"mage", &"paladin", &"rogue", &"warlock"]
	var spots: Array[Vector3] = [Vector3(-2.6, 0, 0.6), Vector3(-1.3, 0, -0.6), Vector3(0, 0, 0.7), Vector3(1.3, 0, -0.6),
		Vector3(2.6, 0, 0.6)]
	for i in ids.size():
		var cd := Db.get_class_data(ids[i])
		var holder := Node3D.new()
		holder.add_to_group(&"players")
		arena.entities.add_child(holder)
		holder.position = spots[i]
		var m := OnionModel.new()
		holder.add_child(m)
		m.setup(cd, PlayerManager.PLAYER_COLORS[i % PlayerManager.PLAYER_COLORS.size()])
		m.set_tag("P%d" % (i + 1))
		m.set_weapons(cd.main_hand, cd.off_hand)
		var set_data := Db.set_for_class(ids[i]) if _arg("sets", "0") == "1" else null
		var set_id: StringName = set_data.id if set_data != null else &""
		if _arg("starter", "0") != "1":
			m.set_looks(EquipLook.make(EquipLook.Slot.HEAD, cd.armor_type, tier, rarity, set_id),
				EquipLook.make(EquipLook.Slot.SHOULDERS, cd.armor_type, tier, rarity, set_id),
				EquipLook.make(EquipLook.Slot.CHEST, cd.armor_type, tier, rarity, set_id))
		m.set_facing(Vector3(0, 0, -1) if north else Vector3(0.3, 0, 1))
		m.set_moving(0.0)
	arena.camera.snap()
	await _frames(30)


func _enemies() -> void:
	var stage := _studio()
	var ids: Array[StringName] = [&"skeleton_grunt", &"candlekin", &"marsh_gurgler", &"troll_axethrower"]
	var state := _arg("state", "")
	for i in ids.size():
		var data := Db.get_enemy(ids[i])
		if data == null:
			continue
		var m := EnemyModel.new()
		stage.add_child(m)
		m.setup(data)
		m.position = Vector3((i - 1.5) * 1.7, 0, 0)
		m.set_facing(Vector3(0, 0, 1))
		match state:
			"walk": m.set_moving(1.0)
			"windup": m.play_windup()
			"stun": m.set_stunned(true)
			"hit": m.flash_hit()
	_close_camera(stage, Vector3(0, 0.7, 0), 8.0, 16.0)
	await _frames(8)


func _weapons() -> void:
	var stage := _studio()
	var i := 0
	var ids := Db.weapons.keys()
	ids.sort()
	for id: StringName in ids:
		var w := WeaponModel.build(Db.get_weapon(id))
		stage.add_child(w)
		w.position = Vector3((i - (ids.size() - 1) * 0.5) * 0.75, 0.6, 0)
		w.rotation_degrees = Vector3(0, 180, -60 if id == &"gun" else 0)
		i += 1
	_close_camera(stage, Vector3(0, 0.75, 0), 9.0, 12.0)
	await _frames(4)


## Revive scene through the gameplay camera: a paladin channels a resurrection on a
## downed mage (cast bar + beam), a resurrect column and a level-up burst next to them.
func _revive() -> void:
	var arena := Arena.create()
	add_child(arena)
	var ids: Array[StringName] = [&"paladin", &"mage", &"warrior", &"rogue"]
	var spots: Array[Vector3] = [Vector3(-0.8, 0, 0.4), Vector3(0.8, 0, -0.3), Vector3(3.5, 0, 0.5), Vector3(-3.5, 0, -0.5)]
	var models: Array[OnionModel] = []
	for i in ids.size():
		var holder := Node3D.new()
		holder.add_to_group(&"players")
		arena.entities.add_child(holder)
		holder.position = spots[i]
		var cd := Db.get_class_data(ids[i])
		var m := OnionModel.new()
		holder.add_child(m)
		m.setup(cd, PlayerManager.PLAYER_COLORS[i])
		m.set_tag("P%d" % (i + 1))
		m.set_weapons(cd.main_hand, cd.off_hand)
		models.append(m)
	models[1].set_downed(true)
	models[1].set_revive_progress(0.55, PlayerManager.PLAYER_COLORS[0], 2.2)
	models[0].set_facing(spots[1] - spots[0])
	models[0].set_channel_target(models[1])
	models[2].set_facing(Vector3(0, 0, 1))
	models[3].set_facing(Vector3(0, 0, 1))
	arena.camera.snap()
	await _frames(12)
	Engine.time_scale = 0.1
	Vfx.resurrect_column(Vector3(4.0, 0, -3.5))
	Vfx.level_up_burst(Vector3(-4.0, 0, -3.0))
	await _frames(4)
	Engine.time_scale = 1.0


func _arena_overview() -> void:
	var arena := _make_arena()
	add_child(arena)
	_enter_dungeon_if_asked(arena)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 300.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 48, 36), Vector3(0, 0, -2))
	cam.make_current()
	await _frames(int(_arg("frames", "4")))


# --- M7b combat juice (VIS-FX) ---------------------------------------------------------------------
# --view=fx --phase=spawn|death|impacts|loot|boss|banner  (run with the engine flag --fixed-fps 60 so an
# effect's age after N frames is exact). Each phase poses its things at different stages of their
# animation so one picture shows the whole motion.

func _fx() -> void:
	var phase := _arg("phase", "impacts")
	Vfx.frame_override = 1000
	match phase:
		"spawn":
			await _fx_spawn()
		"death":
			await _fx_death()
		"loot":
			await _fx_loot()
		"boss":
			await _fx_boss()
		"banner":
			await _fx_banner()
		_:
			await _fx_impacts()


## An arena with a close camera aimed at [param at].
func _fx_arena(at: Vector3, dist: float, pitch_deg: float) -> Arena:
	var arena := Arena.create()
	add_child(arena)
	var cam := Camera3D.new()
	cam.fov = CLOSE_FOV
	add_child(cam)
	var p := deg_to_rad(float(_arg("pitch", str(pitch_deg))))
	var d := float(_arg("dist", str(dist)))
	cam.look_at_from_position(at + Vector3(0, sin(p), cos(p)) * d, at)
	cam.make_current()
	return arena


func _fx_model(arena: Arena, id: StringName, pos: Vector3) -> EnemyModel:
	var m: EnemyModel
	var boss := Db.get_boss(id)
	if boss != null:
		m = BossModel.new()
		arena.entities.add_child(m)
		m.setup(boss)
	else:
		m = EnemyModel.new()
		arena.entities.add_child(m)
		m.setup(Db.get_enemy(id))
	m.position = pos
	m.set_facing(Vector3(0.0, 0.0, 1.0))
	return m


func _fx_spawn() -> void:
	var arena := _fx_arena(Vector3(0, 0.5, 0), 12.0, 34.0)
	var ids: Array[StringName] = [&"skeleton_grunt", &"candlekin", &"marsh_gurgler", &"troll_axethrower",
		&"plague_ghoul", &"cultist_acolyte", &"flesh_golem", &"skeleton_grunt", &"candlekin", &"skeleton_grunt"]
	var n := ids.size()
	for i in n:
		var m := _fx_model(arena, ids[i], Vector3((float(i) - float(n - 1) * 0.5) * 1.55, 0.0, 0.0))
		m.play_spawn(EnemyModel.SPAWN_TIME)
		m._process(EnemyModel.SPAWN_TIME * (float(i) + 0.4) / float(n))
		m.set_process(false)
	await _frames(6)


func _fx_death() -> void:
	var arena := _fx_arena(Vector3(0, 0.3, 0), 11.0, 36.0)
	var ids: Array[StringName] = [&"skeleton_grunt", &"skeleton_grunt", &"marsh_gurgler", &"troll_axethrower",
		&"plague_ghoul", &"cultist_acolyte", &"candlekin", &"skeleton_grunt"]
	var ages: Array[float] = [0.02, 0.07, 0.13, 0.2, 0.3, 0.42, 0.5, 0.57]
	var n := ids.size()
	for i in n:
		var pos := Vector3((float(i) - float(n - 1) * 0.5) * 1.6, 0.0, 1.6)
		var m := _fx_model(arena, ids[i], pos)
		var c := EnemyCorpse.spawn(m, pos, EnemyCorpse.Tier.NORMAL, Vector3(1.0, 0.0, -0.5))
		if c != null:
			c._process(ages[i])
			c.set_process(false)
		Vfx.frame_override += 1
		m.queue_free()
	# An elite (a big flash in its affix colour) and a boss (longer, keeps its glow) in the back row.
	var elite := _fx_model(arena, &"skeleton_grunt", Vector3(-3.5, 0.0, -2.2))
	elite.scale = Vector3.ONE * EliteAffixes.MODEL_SCALE
	var ec := EnemyCorpse.spawn(elite, Vector3(-3.5, 0.0, -2.2), EnemyCorpse.Tier.ELITE, Vector3(1, 0, 0.3), EliteAffixes.COLORS[EliteAffixes.ENRAGED])
	ec._process(0.1)
	ec.set_process(false)
	var boss := _fx_model(arena, &"lich_commander_morvain", Vector3(2.5, 0.0, -2.6))
	var bc := EnemyCorpse.spawn(boss, Vector3(2.5, 0.0, -2.6), EnemyCorpse.Tier.BOSS, Vector3(-1, 0, 0.4))
	bc._process(0.55)
	bc.set_process(false)
	Vfx.boss_remains(Vector3(2.5, 0.0, -2.6), boss.data.color, 1.0)
	elite.queue_free()
	boss.queue_free()
	Vfx.death_puff(Vector3(-5.4, 0.5, -2.2), Color(0.9, 0.88, 0.78), 1.3)
	await _frames(8)


func _fx_impacts() -> void:
	var stage := _studio()
	var schools: Array[StringName] = [&"physical", &"fire", &"frost", &"arcane", &"holy", &"shadow", &"nature"]
	for row in 2:
		for i in schools.size():
			Vfx.frame_override += 1
			var pos := Vector3((float(i) - 3.0) * 1.35, 0.55, 0.9 - float(row) * 1.7)
			Vfx.hit_spark(pos, Color(0.95, 0.85, 0.7), schools[i], row == 1)
	_close_camera(stage, Vector3(0, 0.5, -0.3), 13.0, 38.0)
	await _frames(int(_arg("frames", "7")))


func _fx_loot() -> void:
	var arena := _fx_arena(Vector3(0, 0.3, 0), 9.0, 38.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# Gold / XP pickups mid-pop (ages spread over the toss and the bounce).
	for i in 9:
		var p := Pickup.drop(arena.entities, 3 if i % 3 != 2 else 0, 2 if i % 3 == 2 else 0,
				Vector3((float(i) - 4.0) * 0.9, 0.0, 1.9))
		p.set_physics_process(false)
		p._process(Pickup.POP_TIME * (float(i) + 0.5) / 9.0)
		p.set_process(false)
	# Loot bags of rising rarity, tossed to different heights.
	var rarities := [Items.Rarity.RARE, Items.Rarity.EPIC, Items.Rarity.LEGENDARY, Items.Rarity.ARTIFACT]
	for i in rarities.size():
		var item := ItemInstance.new()
		item.rarity = rarities[i]
		var bag := LootDrops.drop_item(item, Vector3((float(i) - 1.5) * 1.8, 0.0, -0.4))
		bag.set_physics_process(false)
		bag._process(LootBag.HOP_TIME * (0.18 + 0.22 * float(i)))
		bag.set_process(false)
	# Pickups pulled by a player to the left: streaks pointing back along the flight.
	for i in 6:
		var p := Pickup.create(2 if i % 2 == 0 else 0, 0 if i % 2 == 0 else 2)
		arena.entities.add_child(p)
		p.position = Vector3(-1.0 + float(i) * 0.9, 0.0, -2.6 - float(i % 3) * 0.35)
		p.set_physics_process(false)
		p._start_trail()
		p.speed = 10.0 + 3.0 * float(i)
		if p._trail != null:
			p._trail.visible = true
			Vfx.aim_streak(p._trail, Vector3(-1.0, 0.0, 0.25).normalized(), clampf(p.speed * Pickup.TRAIL_SECONDS, 0.25, 1.2),
					Pickup.TRAIL_WIDTH)
		p.set_process(false)
	await _frames(4)


func _fx_boss() -> void:
	var arena := _fx_arena(Vector3(0, 1.0, 0), 13.0, 36.0)
	var boss_data := Db.get_boss(&"vorthalax")
	var pos := Vector3(0, 0, 0)
	var m := _fx_model(arena, &"vorthalax", pos)
	m.play_spawn(EnemyModel.SPAWN_TIME_BOSS)
	m._process(EnemyModel.SPAWN_TIME_BOSS * float(_arg("rise", "0.55")))
	m.set_process(false)
	Vfx.boss_entrance(pos, maxf(boss_data.radius * 1.6, 1.2), boss_data.color)
	# The effect (and its dust particles) run for real: --frames=N at the fixed 60 fps = N / 60 s of age.
	await _frames(int(_arg("frames", "20")))


func _fx_banner() -> void:
	var arena := Arena.create()
	add_child(arena)
	arena.camera.snap()
	var hud := Hud.create()
	add_child(hud)
	await _frames(3)
	hud.show_banner(Db.get_boss(&"vorthalax").intro_text(), UiTheme.RED, [], true)
	await _frames(int(_arg("frames", "5")))


# --- Helpers -------------------------------------------------------------------

## The arena of --env=<id> (an id of Db.environments; default: the forest clearing).
func _make_arena() -> Arena:
	var env := Db.get_environment(StringName(_arg("env", ""))) if _arg("env", "") != "" else null
	return Arena.create(env)


## --hazards=1: the environment's ground hazard on the scene: the swamp's bog pools right away
## ([param telegraphs] false), the other environments' telegraphs half filled (true).
func _env_hazards(arena: Arena, center: Vector3, telegraphs: bool) -> void:
	if _arg("hazards", "0") != "1" or arena.in_dungeon_layout:
		return
	match arena.environment.hazard_id:
		&"bog_pools":
			if not telegraphs:
				BogPool.spawn(arena.entities, center + Vector3(-5.5, 0, 2.5), 2.3, 30.0, 15.0, 0)
				BogPool.spawn(arena.entities, center + Vector3(6.0, 0, -3.0), 2.3, 30.0, 15.0, 1)
		&"grasping_hands":
			if telegraphs:
				GraspingHands.spawn(arena.entities, center + Vector3(-1.0, 0, -4.0), 1.5, 1.0, 1.0, 1.2).age = 0.6
		&"lava_vents":
			if telegraphs:
				LavaEruption.spawn(arena.entities, EnvironmentHazards.LAVA_VENT_POINTS[2], 2.0, 1.0, 1.0).age = 0.6
		&"falling_icicles":
			if telegraphs:
				FallingIcicle.spawn(arena.entities, center + Vector3(-1.0, 0, -4.0), 1.2, 1.0, 1.0, 30.0, 1.5).age = 0.6


## --dungeon=1: swaps the arena's scenery for the dungeon room (the run's palette: --env).
func _enter_dungeon_if_asked(arena: Arena) -> void:
	if _arg("dungeon", "0") == "1":
		arena.enter_dungeon_layout(arena.environment)
		# The Defend room's brazier, a little north of the heroes.
		var brazier := DungeonBrazier.create(100.0)
		arena.entities.add_child(brazier)
		brazier.position = Vector3(0.0, 0.0, -3.2)


## --dist=N: holds the gameplay camera at N metres (19.5 = closest, 36 = the farthest zoom-out).
func _force_camera_distance(arena: Arena) -> void:
	if _arg("dist", "") == "":
		return
	arena.camera.distance = float(_arg("dist", "24"))
	arena.camera.set_process(false)
	arena.camera.call(&"_apply")

## A projectile frozen in flight (no physics: it only shows its look).
func _projectile(arena: Arena, team: int, style: StringName, color: Color, at: Vector3, dir: Vector3) -> void:
	var p := Projectile.create(team, 1.0, false, dir, 0.0, 100.0, 0, 0.0, null, style, color)
	p.set_physics_process(false)
	arena.entities.add_child(p)
	p.global_position = at


## A random point 4.5-9 m around [param center], inside the arena, not on another enemy.
func _free_spot(arena: Arena, center: Vector3, others: Array[EnemyModel]) -> Vector3:
	var p := center
	for attempt in 30:
		var a := _rng.randf_range(0.0, TAU)
		var r := _rng.randf_range(4.5, 9.0)
		p = center + Vector3(cos(a) * r * 1.4, 0, sin(a) * r)
		var free := arena.is_inside(p, 1.0)
		for o in others:
			if o.position.distance_to(p) < 1.3:
				free = false
				break
		if free:
			return p
	return p


## Neutral lit stage for close-ups (same light direction as the arena).
func _studio() -> Node3D:
	var stage := Node3D.new()
	stage.name = "Studio"
	add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.56, 0.74, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.66, 0.8)
	env.ambient_light_energy = 0.62
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -128, 0)
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = 0.92
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	ground.material_override = Mats.toon_plain(Color(0.36, 0.56, 0.24))
	stage.add_child(ground)
	return stage


func _close_camera(stage: Node3D, at: Vector3, dist: float, pitch_deg: float) -> void:
	var cam := Camera3D.new()
	cam.fov = CLOSE_FOV
	stage.add_child(cam)
	var p := deg_to_rad(float(_arg("pitch", str(pitch_deg))))
	var d := float(_arg("dist", str(dist)))
	cam.look_at_from_position(at + Vector3(0, sin(p), cos(p)) * d, at)
	cam.make_current()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.get_slice("=", 1)
	return default
