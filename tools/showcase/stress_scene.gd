extends Node
## Body of tools/showcase/stress.gd (dev tool, M7b): ~150 enemies on screen, a dozen kills every 6 frames (loot,
## puffs, corpses), 20 hit sparks per frame; prints "STRESS ..." lines with the render draw calls / objects and the
## process time over --frames=N rendered frames after a warm-up. It only uses calls that every version has.

const WARM_UP := 90

var _rng := RandomNumberGenerator.new()


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.get_slice("=", 1)
	return default


func _spawn(arena: Arena, ids: Array[StringName]) -> Enemy:
	var e := Enemy.create(Db.get_enemy(ids[_rng.randi() % ids.size()]), 15)
	arena.entities.add_child(e)
	e.global_position = Vector3(_rng.randf_range(-9.0, 9.0), 0.0, _rng.randf_range(-5.0, 5.0))
	if e.has_method(&"play_spawn_in"):
		e.call(&"play_spawn_in")
	return e


func run() -> void:
	_rng.seed = 5
	RunState.start_run(4, 5)
	var arena := Arena.create()
	add_child(arena)
	var cam := Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	var pitch := deg_to_rad(52.0)
	cam.look_at_from_position(Vector3(0, sin(pitch), cos(pitch)) * 22.0, Vector3.ZERO)
	cam.make_current()
	var ids: Array[StringName] = [&"skeleton_grunt", &"candlekin", &"marsh_gurgler", &"troll_axethrower"]
	var live: Array[Enemy] = []
	var colors: Array = [Color(0.92, 0.86, 0.74), Color(1.0, 0.52, 0.16), Color(0.55, 0.85, 1.0),
		Color(0.78, 0.52, 1.0), Color(1.0, 0.9, 0.45), Color(0.66, 0.36, 0.9), Color(0.5, 0.95, 0.38)]
	# (Static calls through the script object, so the same file runs on a tree whose Vfx has no school argument.)
	var vfx: GDScript = load("res://scenes/vfx/vfx.gd")
	var has_school := false
	for m in vfx.get_script_method_list():
		if m["name"] == "spark_color":
			has_school = true
	for i in 150:
		live.append(_spawn(arena, ids))
	var total := int(_arg("frames", "360"))
	var draws: Array[float] = []
	var objects: Array[float] = []
	var proc_ms: Array[float] = []
	var peak_nodes := 0.0
	for f in WARM_UP + total:
		await get_tree().process_frame
		if f % 6 == 0:
			for k in 12:
				var idx := _rng.randi() % live.size()
				var e: Enemy = live[idx]
				live.remove_at(idx)
				if is_instance_valid(e) and not e.is_dead():
					e.take_damage(1.0e6)
				live.append(_spawn(arena, ids))
		for k in 20:
			var target: Enemy = live[_rng.randi() % live.size()]
			if not is_instance_valid(target):
				continue
			var at := target.global_position + Vector3.UP * 0.6
			var color: Color = colors[_rng.randi() % colors.size()]
			if has_school:
				vfx.callv(&"hit_spark", [at, color, &"", k % 4 == 0])
			else:
				vfx.callv(&"hit_spark", [at, color])
		if f >= WARM_UP:
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
			proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			peak_nodes = maxf(peak_nodes, Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("STRESS frames=%d enemies=%d" % [draws.size(), get_tree().get_nodes_in_group(&"enemies").size()])
	print("STRESS draws   %s" % _stat(draws))
	print("STRESS objects %s" % _stat(objects))
	print("STRESS cpu_ms  %s" % _stat(proc_ms))
	print("STRESS peak nodes %d" % int(peak_nodes))


func _stat(a: Array[float]) -> String:
	if a.is_empty():
		return "n/a"
	var total := 0.0
	var peak := -INF
	for v in a:
		total += v
		peak = maxf(peak, v)
	var sorted := a.duplicate()
	sorted.sort()
	return "avg %.1f  p95 %.1f  max %.1f" % [total / a.size(), sorted[int(sorted.size() * 0.95)], peak]
