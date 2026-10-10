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
		"enemies":
			await _enemies()
		"weapons":
			await _weapons()
		"arena":
			await _arena_overview()
		_:
			await _gameplay()
	var out := _arg("out", "/tmp/smartonion_showcase.png")
	var err := get_viewport().get_texture().get_image().save_png(out)
	print("showcase: %s -> %s (%s)" % [view, out, error_string(err)])


# --- Views -------------------------------------------------------------------

func _gameplay() -> void:
	var arena := Arena.create()
	add_child(arena)
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
			var a := _rng.randf_range(0.0, TAU)
			var r := _rng.randf_range(4.5, 9.0)
			e.position = center + Vector3(cos(a) * r * 1.4, 0, sin(a) * r)
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
	await _frames(20)
	# Slow time down so the burst is captured mid-flight.
	Engine.time_scale = 0.05
	Vfx.spawn_telegraph(center + Vector3(-6, 0, -4), 1.2, 1.0)
	Vfx.spawn_telegraph(center + Vector3(7, 0, 3), 1.0, 1.0)
	await _frames(3)
	var warrior := onions[0].get_parent() as Node3D
	onions[0].play_attack(false)
	Vfx.slash_arc(warrior.position + Vector3.UP * 0.3, Vector3(-1, 0, 0.3), 2.3, 110.0, Color(1.0, 0.9, 0.6))
	Vfx.explosion(center + Vector3(5, 0.8, -3), 1.6, Color(0.75, 0.4, 1.0))
	Vfx.death_puff(center + Vector3(-4, 0.5, 3), Color(0.9, 0.88, 0.78))
	Vfx.floating_text(center + Vector3(-3.5, 1.2, -1), "12", Color.WHITE)
	Vfx.floating_text(center + Vector3(3.8, 1.2, 0.5), "37", Color(1.0, 0.85, 0.2), 1.5)
	Vfx.floating_text(center + Vector3(0.5, 1.4, -2.5), "Dodge", Color(0.7, 0.88, 1.0), 0.9)
	Vfx.floating_text(center + Vector3(-1.5, 1.2, 3.0), "+3 gold", Color(1.0, 0.82, 0.25), 0.9)
	Vfx.hit_spark(center + Vector3(-3.2, 0.6, -1.5), Color(1, 0.9, 0.5))
	Vfx.pickup_sparkle(center + Vector3(1.5, 0.3, 3.0))
	if not enemies.is_empty():
		enemies[0].flash_hit()
	await _frames(5)
	Engine.time_scale = 1.0


func _live() -> void:
	var count := clampi(int(_arg("players", "4")), 1, 4)
	RunState.start_run(count, int(_arg("seed", "7")))
	var arena := Arena.create()
	add_child(arena)
	var offset := int(_arg("classoff", "0"))
	for i in count:
		PlayerManager.add_bot(Db.class_ids[(i + offset) % Db.class_ids.size()], 11 + i)
	var spawns := arena.get_player_spawn_points(count)
	var i := 0
	for slot in PlayerManager.get_slots():
		var p := Player.create(slot)
		arena.entities.add_child(p)
		p.global_position = spawns[i]
		p.begin_wave()
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


func _arena_overview() -> void:
	var arena := Arena.create()
	add_child(arena)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 300.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 48, 36), Vector3(0, 0, -2))
	cam.make_current()
	await _frames(4)


# --- Helpers -------------------------------------------------------------------

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
