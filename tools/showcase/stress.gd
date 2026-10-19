extends SceneTree
## Perf stress runner (dev tool, M7b): see stress_scene.gd. Works on any commit, so a base and a new tree can
## be compared:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --fixed-fps 60 --path . --resolution 1280x720 \
##       --rendering-driver opengl3 -s res://tools/showcase/stress.gd -- --frames=360


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node = load("res://tools/showcase/stress_scene.gd").new()
	root.add_child(scene)
	current_scene = scene
	await scene.call(&"run")
	quit()
