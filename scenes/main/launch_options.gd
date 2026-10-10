class_name LaunchOptions
extends RefCounted
## The game's command line (everything after "--", see OS.get_cmdline_user_args()).
## Parsed once by Main; see docs/ARCHITECTURE.md "Command line".
##
##   --smoke              4 bots, menus skipped, time scale 4, plays --waves=N waves, prints
##                        "SMOKE_RESULT {json}" and quits (exit 1 on errors / defeat / stall)
##   --demo               bots at normal speed, endless (for screenshots / attract mode)
##   --players=N          bot count (1..4, default 4)
##   --waves=N            smoke: waves to play (default 3)
##   --start-wave=N       first wave of the run (1..25)
##   --seed=N             RunState / bot seed
##   --screenshot=PATH    saves a PNG after --shot-time seconds of game time, then quits
##   --shot-time=S        seconds after the run starts (after boot for menu / lobby views)
##   --view=NAME          dev: reach a screen for a screenshot – menu, lobby, game,
##                        intermission, game_over, victory, pause
##   --view-time=S        when the view is forced (default: shot time - 3 s)
##   --allow-defeat       smoke: a full party wipe ends the run (default: revive and go on)
##   --time-scale=X       overrides the time scale (smoke default 4)

const DEFAULT_BOTS := 4
const DEFAULT_SMOKE_WAVES := 3
const SMOKE_TIME_SCALE := 4.0
## Smoke runs are seeded (deterministic content rolls) unless --seed is given.
const SMOKE_SEED := 1
const DEFAULT_SHOT_TIME := 8.0
## Views that need a running game (bots are added and a run starts right away).
const RUN_VIEWS: Array[String] = ["game", "intermission", "game_over", "victory", "pause"]
const VIEWS: Array[String] = ["menu", "lobby", "game", "intermission", "game_over", "victory", "pause"]

var smoke := false
var demo := false
var players := DEFAULT_BOTS
var waves := DEFAULT_SMOKE_WAVES
var start_wave := 1
## -1 = random.
var seed_value := -1
var screenshot_path := ""
var shot_time := DEFAULT_SHOT_TIME
var view := ""
## < 0 = derived from shot_time (see [method effective_view_time]).
var view_time := -1.0
var allow_defeat := false
## <= 0 = mode default (smoke 4, otherwise 1).
var time_scale := 0.0
## Arguments that were not understood (reported once by Main).
var unknown: Array[String] = []


static func parse(args: PackedStringArray) -> LaunchOptions:
	var o := LaunchOptions.new()
	for raw in args:
		var arg := String(raw)
		var key := arg
		var value := ""
		var eq := arg.find("=")
		if eq >= 0:
			key = arg.substr(0, eq)
			value = arg.substr(eq + 1)
		match key:
			"--smoke":
				o.smoke = true
			"--demo":
				o.demo = true
			"--players":
				o.players = clampi(value.to_int(), 1, PlayerManager.MAX_PLAYERS)
			"--waves":
				o.waves = maxi(1, value.to_int())
			"--start-wave":
				o.start_wave = clampi(value.to_int(), 1, RunState.TOTAL_WAVES)
			"--seed":
				o.seed_value = maxi(0, value.to_int())
			"--screenshot":
				o.screenshot_path = value
			"--shot-time":
				o.shot_time = maxf(0.0, value.to_float())
			"--view":
				if value in VIEWS:
					o.view = value
				else:
					o.unknown.append(arg)
			"--view-time":
				o.view_time = maxf(0.0, value.to_float())
			"--allow-defeat":
				o.allow_defeat = true
			"--time-scale":
				o.time_scale = clampf(value.to_float(), 0.05, 16.0)
			_:
				# The unit test runner shares the command line; ignore its flags.
				if not key.begins_with("--filter"):
					o.unknown.append(arg)
	return o


## True when the game plays itself (no menus, bot players).
func starts_run() -> bool:
	return smoke or demo or view in RUN_VIEWS


## Bots join automatically (run views, or the lobby view to fill the cards).
func uses_bots() -> bool:
	return starts_run() or view == "lobby"


## The screen Main boots into: &"menu", &"lobby" or &"run".
func boot_state() -> StringName:
	if starts_run():
		return &"run"
	if view == "lobby":
		return &"lobby"
	return &"menu"


## Last wave a smoke run plays (start_wave + waves - 1, at most RunState.TOTAL_WAVES).
func last_wave() -> int:
	return clampi(start_wave + waves - 1, start_wave, RunState.TOTAL_WAVES)


## Screens stay open for a screenshot (the auto-continue of bots is ignored).
func holds_screens() -> bool:
	return view in ["intermission", "game_over", "victory", "pause"]


## Game time (seconds after the run starts) at which the --view state is forced.
func effective_view_time() -> float:
	if view_time >= 0.0:
		return view_time
	return maxf(0.0, shot_time - 3.0)


## Engine.time_scale for this launch.
func effective_time_scale() -> float:
	if time_scale > 0.0:
		return time_scale
	return SMOKE_TIME_SCALE if smoke else 1.0


## Seed for RunState.start_run (-1 = random).
func run_seed() -> int:
	if seed_value >= 0:
		return seed_value
	return SMOKE_SEED if smoke else -1
