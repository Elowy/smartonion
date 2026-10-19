extends SceneTree
## Art showcase runner for the "visuals" module (a dev tool, not part of the game).
## Builds one view with [code]showcase_scene.gd[/code], waits, saves a PNG and quits.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##       -s res://tools/showcase/showcase.gd -- --view=gameplay --out=/tmp/showcase.png
##
## Views (--view=...):
##   gameplay  Arena + the 5 class onions with their starting weapons, enemies of every
##             style and a burst of VFX, through the gameplay CameraRig (default).
##   live      A real run: bot Players + WaveDirector. --wave=N --players=1..4 --t=seconds
##   onions    Close line-up of the classes. --state=hurt|downed|walk|attack --back=1
##   enemies   Enemy line-up. --state=walk|windup|stun|hit
##   weapons   Every weapon model.
##   arena     High overview of the arena and its decoration.
##   revive    Resurrection visuals: cast bar, channel beam, resurrect column.
##   fx        M7b combat juice, --phase=spawn|death|impacts|loot|boss|banner (add the engine flag
##             --fixed-fps 60 before --path so an effect's age after N frames is exact).
## Common: --out=path.png  --seed=N


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node = load("res://tools/showcase/showcase_scene.gd").new()
	root.add_child(scene)
	current_scene = scene
	await scene.call(&"run")
	quit()
