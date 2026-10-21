class_name TrailerDirector
extends Node
## Dev tool (tools/trailer/, not part of the game): drives the REAL game ([Main] with bots at the controllers) for
## the trailer. It never changes a gameplay code path – it only uses public members of the game's own nodes (the
## camera rig, the HUD, the heroes' death guards and stat sources, the Intermission's panels) from outside.
##
## A "take" (trailer_takes.gd) is a coroutine that plays one run and cuts it into named clips:
##   - [method fast_forward_until] plays the run at up to 16x with the 3D view off and the screen black (the bots
##     buy gear, level up and clear waves; the black frames are skipped when the clips are cut),
##   - [method begin_clip] / [method end_clip] mark a stretch of frames as one shot ("marks" JSON next to the
##     movie: first frame, frame count, name),
##   - the camera helpers ([method cam_free], [method cam_to], [method cam_track], ...) replace the gameplay
##     camera for close-ups and dollies,
##   - [method hide_hud], [method guard_party], [method buff_party] stage what the shot needs.
## The text cards are NOT drawn here (see trailer_cards.gd): they are composited over the shots in ffmpeg.

## Seconds of game time per rendered frame at normal speed.
const DEFAULT_FPS := 30

## Camera parameter set: look-at point, distance, pitch (degrees above the ground), yaw (degrees around Y, 0 = the
## camera south of the focus looking north like the gameplay camera), vertical FOV.
class CamPose extends RefCounted:
	var look := Vector3.ZERO
	var dist := 24.0
	var pitch := 57.0
	var yaw := 0.0
	var fov := 40.0
	var roll := 0.0
	## Zoom-follow only: how far the look-at point has moved from [member look] to the rig's focus (0..1).
	var blend := 1.0

	func copy() -> CamPose:
		var c := CamPose.new()
		c.look = look
		c.dist = dist
		c.pitch = pitch
		c.yaw = yaw
		c.fov = fov
		c.roll = roll
		c.blend = blend
		return c

	func lerp_to(o: CamPose, t: float) -> CamPose:
		var c := CamPose.new()
		c.look = look.lerp(o.look, t)
		c.dist = lerpf(dist, o.dist, t)
		c.pitch = lerpf(pitch, o.pitch, t)
		c.yaw = lerpf(yaw, o.yaw, t)
		c.fov = lerpf(fov, o.fov, t)
		c.roll = lerpf(roll, o.roll, t)
		c.blend = lerpf(blend, o.blend, t)
		return c

var main: Main
var options: LaunchOptions
var take_name := ""
var marks_path := ""
var fps := DEFAULT_FPS
var exit_code := 0
## Finished clips: {name, start (first frame), frames, take}.
var marks: Array[Dictionary] = []
## --t-name=value command line parameters of the take (see [method param]).
var params: Dictionary = {}
var _clip_name := ""
var _clip_start := 0
var _black := false
var _hud_visible := true
var _hud_forced := false
var _cam_free := false
## Zoom-follow mode: the gameplay rig keeps framing the party and the free camera only stands closer to it
## ([member CamPose.dist] is then a multiplier of the rig's distance).
var _zoom_follow := false
var _pose := CamPose.new()
var _tween_from: CamPose
var _tween_to: CamPose
var _tween_t := 0.0
var _tween_dur := 0.0
var _tween_ease := 1.0
var _track: Node3D
var _track_offset := Vector3.ZERO
var _track_sharp := 0.0
var _track_fn := Callable()
var _frame := 0


func _init() -> void:
	name = "TrailerDirector"
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 200  # after the camera rig (100), so a free camera has the last word


# --- Run ----------------------------------------------------------------------------

func run() -> void:
	var own := {}
	var game_args := PackedStringArray()
	var cli := OS.get_cmdline_user_args()
	for raw in cli:
		var arg := String(raw)
		if arg.begins_with("--take=") or arg.begins_with("--marks=") or arg.begins_with("--fps="):
			own[arg.get_slice("=", 0).trim_prefix("--")] = arg.get_slice("=", 1)
		elif arg.begins_with("--t-"):
			params[arg.get_slice("=", 0).trim_prefix("--t-")] = arg.get_slice("=", 1) if "=" in arg else "1"
		else:
			game_args.append(arg)
	take_name = String(own.get("take", ""))
	marks_path = String(own.get("marks", ""))
	fps = int(own.get("fps", DEFAULT_FPS))
	if not TrailerTakes.has_take(take_name):
		printerr("TRAILER unknown take '%s' (known: %s)" % [take_name, ", ".join(TrailerTakes.names())])
		exit_code = 2
		return
	# The take's own launch flags first, the command line after them (the later flag wins).
	var all_args := PackedStringArray(TrailerTakes.game_args(take_name))
	all_args.append_array(game_args)
	options = LaunchOptions.parse(all_args)
	if not options.unknown.is_empty():
		printerr("TRAILER unknown game arguments: %s" % ", ".join(options.unknown))
		exit_code = 2
		return
	RenderingServer.set_default_clear_color(Color.BLACK)
	if param_bool("preview"):
		get_viewport().scaling_3d_scale = 0.5  # a quick look: the 3D view at half resolution
	# Trailer footage always has the bots' market pacing of --demo, never the smoke harness.
	options.demo = options.view == ""  # (the roll-reel take boots into the lobby: no run yet)
	options.smoke = false
	if not TrailerTakes.is_stage(take_name):
		main = Main.create(options)
		get_tree().root.add_child(main)
	# The music is not recorded: the trailer has its own bed (make_trailer.sh); the game's sounds are.
	var music_bus := AudioServer.get_bus_index(Audio.BUS_MUSIC)
	if music_bus >= 0:
		AudioServer.set_bus_mute(music_bus, true)
	await frames(2)
	say("take '%s' starts: %d players, wave %d, env %s%s" % [take_name, options.players, options.start_wave,
			options.environment, " (stage)" if main == null else ""])
	await TrailerTakes.play(take_name, self)
	if _clip_name != "":
		end_clip()
	_write_marks()
	say("take '%s' done after %d frames" % [take_name, _frame])


## The take parameter --t-<key>=value (default when absent).
func param(key: String, default: Variant) -> Variant:
	if not params.has(key):
		return default
	var raw := String(params[key])
	if default is int:
		return raw.to_int()
	if default is float:
		return raw.to_float()
	if default is bool:
		return raw != "0" and raw != "false"
	return raw


func param_bool(key: String) -> bool:
	return bool(param(key, false))


func say(text: String) -> void:
	print("TRAILER f%05d %s" % [_frame, text])


func _write_marks() -> void:
	if marks_path == "":
		return
	var f := FileAccess.open(marks_path, FileAccess.WRITE)
	if f == null:
		printerr("TRAILER cannot write %s" % marks_path)
		exit_code = 1
		return
	f.store_string(JSON.stringify({"take": take_name, "fps": fps, "total_frames": _frame, "clips": marks}, "\t"))
	f.close()


# --- Waiting ---------------------------------------------------------------------------

## Waits [param n] rendered frames.
func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Waits [param seconds] of game time at normal speed (frames / fps).
func seconds(s: float) -> void:
	await frames(maxi(1, roundi(s * float(fps))))


## Waits until [param cond] is true; false when [param timeout_s] (game seconds at normal speed, rendered frames
## when fast-forwarding) ran out first.
func until(cond: Callable, timeout_s: float = 600.0) -> bool:
	var left := int(timeout_s * float(fps))
	while left > 0:
		if cond.call():
			return true
		await get_tree().process_frame
		left -= 1
	return bool(cond.call())


## Plays on at [param scale]x with the 3D view off and the screen black until [param cond] holds, then back to
## normal speed (the screen stays black until the next [method begin_clip]). The frames in between are black movie
## frames that the cut skips.
func fast_forward_until(cond: Callable, scale: float = 8.0, timeout_s: float = 3600.0) -> bool:
	_set_black(true)
	main._apply_time_scale(scale)
	var ok := await until(cond, timeout_s / maxf(scale, 1.0))
	main._apply_time_scale(1.0)
	return ok


## Plays on at normal speed with the picture on until [param cond] holds (not a clip; marks nothing).
func play_until(cond: Callable, timeout_s: float = 600.0) -> bool:
	_set_black(false)
	return await until(cond, timeout_s)


# --- Clips -----------------------------------------------------------------------------

## Starts the clip [param clip]: the picture is on (3D view and UI) from this frame.
func begin_clip(clip: String) -> void:
	if _clip_name != "":
		end_clip()
	_set_black(false)
	_clip_name = clip
	_clip_start = _frame  # (the frame drawn at the end of this iteration; _process counts it afterwards)
	say("clip '%s' begins (%s)" % [clip, state_text()])


## Ends the current clip after the frames drawn so far; the screen is NOT blacked until [method fast_forward_until].
func end_clip() -> void:
	if _clip_name == "":
		return
	var count := _frame - _clip_start
	marks.append({"name": _clip_name, "start": _clip_start, "frames": count, "take": take_name})
	say("clip '%s' ends: %d frames = %.2f s" % [_clip_name, count, float(count) / float(fps)])
	_clip_name = ""


func _set_black(on: bool) -> void:
	_black = on
	get_viewport().disable_3d = on
	if main != null:
		for c in main.get_children():
			var layer := c as CanvasLayer
			if layer != null:
				layer.visible = not on


## One line about where the run is (logs).
func state_text() -> String:
	if main == null:
		return "no run"
	var alive := 0
	for p in heroes():
		if p.is_alive():
			alive += 1
	return "state %s, wave %d, %d/%d heroes up, %d enemies" % [Main.State.keys()[main.state], main.wave, alive, heroes().size(),
			get_tree().get_node_count_in_group(&"enemies")]


# --- Per frame -------------------------------------------------------------------------

func _process(delta: float) -> void:
	_frame += 1
	if main != null and main.hud != null and is_instance_valid(main.hud) and _hud_forced:
		main.hud.visible = _hud_visible and main.state != Main.State.INTERMISSION
	_update_camera(delta)


# --- Heroes ------------------------------------------------------------------------------

## The run's hero Players (Main.players) that are still valid.
func heroes() -> Array[Player]:
	var out: Array[Player] = []
	if main == null:
		return out
	for p in main.players:
		if is_instance_valid(p):
			out.append(p)
	return out


## The last hero standing cannot be killed (a lethal hit leaves 1 HP): no party wipe ends the run mid-shot. Heroes
## that go down earlier still go down (and get revived by the Grave Tender, as in the game).
func guard_party() -> void:
	for p in heroes():
		if not p.has_meta(&"trailer_guard"):
			p.set_meta(&"trailer_guard", true)
			p.death_guards.append(_last_standing_guard.bind(p))


func _last_standing_guard(p: Player) -> bool:
	for other in heroes():
		if other != p and other.is_alive():
			return false
	return true


## Adds the stat source "trailer" to every hero (stat -> value, e.g. {Stats.STAMINA: 40}): a sturdier / stronger
## party for a shot. Replaces what an earlier call set.
func buff_party(mods: Dictionary) -> void:
	for p in heroes():
		p.stats.set_source(&"trailer", mods)
		p.hp = p.max_hp()


# --- HUD ----------------------------------------------------------------------------------

## Shows or hides the in-run HUD (unit frames, wave plaque, banners) for the shots that follow.
func hud_visible(on: bool) -> void:
	_hud_visible = on
	_hud_forced = true
	if main != null and main.hud != null and is_instance_valid(main.hud):
		main.hud.visible = on


# --- UI zoom --------------------------------------------------------------------------------

## The break screens (market, loot roll) live on the Intermission canvas layer: a transform on it zooms and pans the
## whole UI (the text is re-rendered at the new size, so it stays sharp).
func ui_layer() -> CanvasLayer:
	return main.get_node_or_null("IntermissionLayer") as CanvasLayer if main != null else null


## Zooms the break UI to [param zoom]x with the point [param focus] (design pixels of the 1920 x 1080 canvas) at the
## middle of the screen, over [param duration] seconds (0 = at once). 1.0 puts it back.
func ui_zoom(zoom: float, focus: Vector2 = Vector2(960, 540), duration: float = 0.0, ease_power: float = 2.0) -> void:
	var layer := ui_layer()
	if layer == null:
		return
	var screen := Vector2(960, 540)
	var from_zoom := layer.transform.x.x
	var from_origin := layer.transform.origin
	var to_origin := screen - focus * zoom
	if duration <= 0.0:
		layer.transform = Transform2D(Vector2(zoom, 0), Vector2(0, zoom), to_origin)
		return
	var n := maxi(1, roundi(duration * float(fps)))
	for i in n:
		var t := _smooth(float(i + 1) / float(n), ease_power)
		var s := lerpf(from_zoom, zoom, t)
		layer.transform = Transform2D(Vector2(s, 0), Vector2(0, s), from_origin.lerp(to_origin, t))
		await get_tree().process_frame


# --- Camera ---------------------------------------------------------------------------------

## The camera rig of the running arena.
func rig() -> CameraRig:
	return main.arena.camera if main != null and main.arena != null and is_instance_valid(main.arena) else null


## Takes the camera over from the gameplay CameraRig: [param pose] is where it stands now (null = where the rig is).
func cam_free(pose: CamPose = null) -> void:
	var r := rig()
	if r == null:
		return
	_cam_free = true
	_zoom_follow = false
	r.set_process(false)
	if pose != null:
		_pose = pose.copy()
	else:
		_pose.look = r.focus
		_pose.dist = r.distance
		_pose.pitch = CameraRig.PITCH_DEG
		_pose.yaw = 0.0
		_pose.fov = CameraRig.FOV
	_tween_to = null
	_track = null
	_track_fn = Callable()
	_apply_pose()


## The camera keeps the gameplay rig's framing of the party but stands at [param zoom] times its distance
## (< 1 = closer), at [param pitch] / [param yaw]; tweened over [param duration] seconds.
func cam_zoom(zoom: float, pitch: float = CameraRig.PITCH_DEG, yaw: float = 0.0, duration: float = 0.0,
		ease_power: float = 1.0, fov: float = CameraRig.FOV) -> void:
	var r := rig()
	if r == null:
		return
	if not _zoom_follow:
		if _cam_free and duration > 0.0:
			# From the free camera as it stands: its look-at point glides over to the rig's focus.
			_pose.dist = _pose.dist / maxf(r.distance, 1.0)
			_pose.blend = 0.0
		else:
			_pose = pose(r.focus, 1.0, CameraRig.PITCH_DEG, 0.0, CameraRig.FOV)
		_cam_free = true
		_zoom_follow = true
		r.set_process(true)
		_tween_to = null
		_track = null
		_track_fn = Callable()
	var goal := pose(Vector3.ZERO, zoom, pitch, yaw, fov)
	goal.blend = 1.0
	if duration <= 0.0:
		_pose = goal
		_tween_to = null
	else:
		_tween_from = _pose.copy()
		_tween_to = goal
		_tween_t = 0.0
		_tween_dur = duration
		_tween_ease = ease_power


## Gives the camera back to the gameplay CameraRig.
func cam_game() -> void:
	var r := rig()
	_zoom_follow = false
	_cam_free = false
	_tween_to = null
	_track = null
	_track_fn = Callable()
	if r != null and is_instance_valid(r):
		r.set_process(true)
		r.camera.fov = CameraRig.FOV


## Moves the free camera to [param pose] over [param duration] seconds (0 = at once); [param ease] > 1 eases in and
## out (1 = linear). The look-at point of a pose is replaced by the tracked node while [method cam_track] is on.
func cam_to(pose: CamPose, duration: float = 0.0, ease_power: float = 1.0) -> void:
	if not _cam_free:
		cam_free()
	if duration <= 0.0:
		_pose = pose.copy()
		_tween_to = null
		_apply_pose()
		return
	_tween_from = _pose.copy()
	_tween_to = pose.copy()
	_tween_t = 0.0
	_tween_dur = duration
	_tween_ease = ease_power


## The free camera looks at [param node] (+ [param offset]), following with [param sharpness] (0 = locked on, else
## exponential smoothing per second). [param node] null stops it.
func cam_track(node: Node3D, offset: Vector3 = Vector3(0, 0.6, 0), sharpness: float = 0.0) -> void:
	_track = node
	_track_offset = offset
	_track_sharp = sharpness
	_track_fn = Callable()


## Like [method cam_track] but the look-at point comes from [param fn] (returns a Vector3): a team centroid, a boss...
func cam_track_fn(fn: Callable, sharpness: float = 0.0) -> void:
	_track = null
	_track_fn = fn
	_track_sharp = sharpness


func _update_camera(delta: float) -> void:
	if not _cam_free:
		return
	var step := delta / maxf(Engine.time_scale, 0.01)
	var goal := Vector3.INF
	if _zoom_follow:
		if _track != null and is_instance_valid(_track) and _track.is_inside_tree() and _pose.blend < 1.0:
			_pose.look = _track.global_position + _track_offset
		_update_zoom(step)
		return
	if _track != null and is_instance_valid(_track) and _track.is_inside_tree():
		goal = _track.global_position + _track_offset
	elif _track_fn.is_valid():
		goal = _track_fn.call()
	if goal != Vector3.INF:
		if _track_sharp <= 0.0:
			_pose.look = goal
		else:
			_pose.look = _pose.look.lerp(goal, 1.0 - exp(-_track_sharp * step))
	if _tween_to != null:
		_tween_t = minf(_tween_t + step, _tween_dur)
		var t := _tween_t / _tween_dur
		var e := t if is_equal_approx(_tween_ease, 1.0) else _smooth(t, _tween_ease)
		var keep_look := _pose.look
		var tracking := goal != Vector3.INF
		_pose = _tween_from.lerp_to(_tween_to, e)
		if tracking:
			_pose.look = keep_look
		if _tween_t >= _tween_dur:
			_tween_to = null
	_apply_pose()


func _update_zoom(step: float) -> void:
	var r := rig()
	if r == null:
		return
	if _tween_to != null:
		_tween_t = minf(_tween_t + step, _tween_dur)
		var t := _tween_t / _tween_dur
		_pose = _tween_from.lerp_to(_tween_to, t if is_equal_approx(_tween_ease, 1.0) else _smooth(t, _tween_ease))
		if _tween_t >= _tween_dur:
			_tween_to = null
	var p := _pose.copy()
	p.look = _pose.look.lerp(r.focus, _pose.blend)
	p.dist = r.distance * _pose.dist
	_apply_pose(p)


static func _smooth(t: float, power: float) -> float:
	var a := pow(t, power)
	return a / (a + pow(1.0 - t, power))


func _apply_pose(p: CamPose = null) -> void:
	var r := rig()
	if r == null:
		return
	if p == null:
		p = _pose
	r._apply()  # (keeps the screen shake offsets of the rig's camera)
	var pitch := deg_to_rad(p.pitch)
	var yaw := deg_to_rad(p.yaw)
	var offset := Vector3(0.0, sin(pitch), cos(pitch)) * p.dist
	offset = offset.rotated(Vector3.UP, yaw)
	var cam := r.camera
	cam.fov = p.fov
	var from := p.look + offset
	var basis := Basis.looking_at(p.look - from, Vector3.UP)
	if absf(p.roll) > 0.0001:
		basis = basis * Basis(Vector3.BACK, deg_to_rad(p.roll))
	cam.global_transform = Transform3D(basis, from)


## A pose for the free camera.
static func pose(look: Vector3, dist: float, pitch: float, yaw: float = 0.0, fov: float = 40.0) -> CamPose:
	var p := CamPose.new()
	p.look = look
	p.dist = dist
	p.pitch = pitch
	p.yaw = yaw
	p.fov = fov
	return p
