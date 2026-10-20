extends SceneTree
## Trailer renderer entry point (a dev tool, not part of the game): runs ONE "take" – a scripted play session of the
## real game (bots at the controllers) that records its shots with Godot's Movie Maker. See tools/trailer/README.md.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --write-movie take.avi --fixed-fps 30 --resolution 1920x1080 \
##       --path . --rendering-driver opengl3 -s res://tools/trailer/trailer.gd -- --take=coop --marks=take.json
##
## tools/trailer/make_trailer.sh does that for every take and cuts the result together.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Loaded here, not named in this script: a class name would compile the game's scripts before the autoloads exist.
	var director: Node = load("res://tools/trailer/trailer_director.gd").new()
	root.add_child(director)
	await director.call(&"run")
	quit(int(director.get(&"exit_code")))
