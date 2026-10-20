class_name LaunchOptions
extends RefCounted
## The game's command line (everything after "--", see OS.get_cmdline_user_args()).
## Parsed once by Main; see docs/ARCHITECTURE.md "Command line".
##
##   --smoke              4 bots, menus skipped, time scale 4, plays --waves=N waves, prints
##                        "SMOKE_RESULT {json}" and quits (exit 1 on errors / defeat / stall, and on
##                        an unknown argument: the result is "bad_args", the arguments in "unknown_args")
##   --demo               bots at normal speed, endless (for screenshots / attract mode)
##   --players=N          bot count (1..4, default 4)
##   --classes=a,b,...    bot classes in join order (cycled; default: Db.class_ids); an id that is no
##                        class is an unknown argument ("bad_args" in a smoke run)
##   --companion=ID       M8: the companion every bot of a class with companion choices takes (an id
##                        of Db.companion_ids(), e.g. wolf; default: the class's first choice); an
##                        unknown id is an unknown argument
##   --alt-weapon[=0|1]   M9 LEVELS test hook: every bot starts with its class's alternative starting weapon (Class Level 12;
##                        the profile must have it unlocked – the dev profile of the automated runs has everything)
##   --waves=N            smoke: waves to play (default 3)
##   --start-wave=N       first wave of the run (1..25; endless: 1..99)
##   --seed=N             RunState / bot seed
##   --screenshot=PATH    saves a PNG after --shot-time seconds of game time, then quits
##   --shot-time=S        seconds after the run starts (after boot for menu / lobby views)
##   --view=NAME          dev: reach a screen for a screenshot – menu, settings, credits and patch (the main
##                        menu's pages; patch = The Onion Patch, --patch-tab picks its tab), lobby, roll (the "Rolling the arena..." screen, --env picks the
##                        card it lands on), game, intermission, game_over, victory, pause
##   --patch-tab=NAME     dev: the tab --view=patch opens on – classes, seasonings, heirlooms, achievements, wardrobe
##   --loadout-tab=NAME   dev: --view=lobby opens the Loadout of the second player (the first without one) on that tab –
##                        seasonings, heirloom, look (screenshots)
##   --view-time=S        when the view is forced (default: shot time - 3 s)
##   --allow-defeat       smoke: a full party wipe ends the run (default: revive and go on)
##   --time-scale=X       overrides the time scale (smoke default 4)
##   --goblin-chance=X    M5 test hook: Loot Goblin chance per eligible wave (0..1,
##                        GoblinSpawner.chance_override; default: the normal chance)
##   --elite-mult=X       M5 test hook: multiplies the elites per wave (EliteAffixes.rate_mult)
##   --start-level=N      M5 test hook: team level at run start (talent points from 10;
##                        RunState.set_start_level, before the heroes spawn)
##   --panel-tab=NAME     dev: P1's panel opens on that tab when the market opens – talents,
##                        trainer, character, enchanter (PlayerPanel.debug_start_tab, screenshots;
##                        a locked tab would stay closed)
##   --boss-hp=X          M6 smoke / debug hook: multiplies every boss's HP (BossData.hp_mult;
##                        default 1)
##   --artifact-chance=X  M6 debug hook: overrides the Artifact drop chance of every roll (0..1,
##                        LootDrops.artifact_chance_override; default: off, the normal chances)
##   --end-page=NAME      dev: the page the end screen opens on with --view=game_over / victory –
##                        summary (default), meter (the Damage Meter) or leaderboard (the M6b board;
##                        screenshots)
##   --save-card          dev: the end screen saves the run card (user://cards/run_<date>.png) as
##                        soon as --view forces it, prints "CARD <path>" and keeps going (screenshots)
##   --mode=NAME          M6b: the run mode – normal (default) or endless (RunState.mode; the lobby's
##                        mode select overrides it for human runs)
##   --hardcore           M6b: a hardcore run (RunState.hardcore: no Spirit Healer)
##   --env=ID             M6b: forces the arena environment (an id of Db.environments, e.g.
##                        forest_ruin) instead of the roll
##   --event=ID           M6b debug hook: every eligible wave gets that mid-wave event (guarded_chest,
##                        defend_totem, goblin_caravan – or chest, totem, caravan; RunState.event_override)
##   --shrine-chance=X    M6b debug hook: the chance of a shrine at every break (0..1;
##                        RunState.shrine_chance_override; default: the normal chance)
##   --dungeon[=1]        M6b debug hook: the dungeon portal opens after the next wave
##                        (RunState.dungeon_forced; --dungeon=0 = off)
##   --leaderboard=PATH   M6b dev / test hook: the leaderboard file (Leaderboard.path_override; "user://x.json"
##                        or a file path). Unlike the player's own file, a smoke / demo / --view run
##                        writes it (Main.writes_leaderboard), so the end screen's board can be checked
##   --difficulty=ID      M9: the run's difficulty tier – normal (default), pungent or tear_jerker (an id of
##                        Db.difficulties; RunState.difficulty). A human session's lobby selector overrides it and is
##                        capped by the heroes' unlocked tiers; an automated run (dev profile) plays any tier. An unknown
##                        id is an unknown argument (a smoke run reports "bad_args")
##   --profile=KIND       M9: the meta profile (Meta.configure): dev (everything unlocked, no raw-power bonus, nothing
##                        saved – the default of every automated run), fresh (a new player) or max (every class at
##                        the top level, everything unlocked). Without --profile-path nothing is read or written
##   --profile-path=FILE  M9 dev / test hook: reads and saves the meta profile in FILE instead of the player's
##                        user://profile.json (the only way an automated run touches a profile). With --profile=fresh
##                        or max that profile is the starting point; --profile=dev has no file
##   --seasonings=a,b,c   M9: the Seasonings the bots carry (ids of Db.seasonings, e.g. ssn_smoked_paprika): every bot
##                        takes the ones of its own class, in the order given (a smoke run with the dev profile owns
##                        them all; a real profile must own them). An unknown id, an id of a class no bot plays, a
##                        repeated id or more than Seasonings.MAX_SLOTS of one class is an unknown argument
##   --heirloom=ID        M9 PATCH: every hero starts with this Heirloom equipped (an id of Db.heirlooms, e.g.
##                        heir_sprout_cap), instead of what the profile remembers for the class (a smoke run with
##                        the dev profile owns them all at rank 1; --profile=max at rank 5; a real profile must own
##                        it). An unknown id is an unknown argument

const DEFAULT_BOTS := 4
const DEFAULT_SMOKE_WAVES := 3
const SMOKE_TIME_SCALE := 4.0
## Smoke runs are seeded (deterministic content rolls) unless --seed is given.
const SMOKE_SEED := 1
const DEFAULT_SHOT_TIME := 8.0
## --patch-tab / --loadout-tab values (the lower-case tab names of OnionPatchPage / LoadoutScreen).
const PATCH_TABS: Array[String] = ["classes", "seasonings", "heirlooms", "achievements", "wardrobe"]
const LOADOUT_TABS: Array[String] = ["seasonings", "heirloom", "look"]
## Views that need a running game (bots are added and a run starts right away).
const RUN_VIEWS: Array[String] = ["game", "intermission", "game_over", "victory", "pause"]
const VIEWS: Array[String] = ["menu", "settings", "credits", "patch", "lobby", "roll", "game", "intermission", "game_over", "victory", "pause"]
## --panel-tab values (PlayerPanel.TAB_IDS).
const PANEL_TABS: Array[String] = ["character", "trainer", "talents", "enchanter"]
## --start-level ceiling (far beyond a full run).
const MAX_START_LEVEL := 99
## --start-wave ceiling of the endless mode (far beyond what the bots survive).
const MAX_ENDLESS_START_WAVE := 99
## --boss-hp range (a boss with ~0 HP or an unkillable one is no test).
const MIN_BOSS_HP_MULT := 0.01
const MAX_BOSS_HP_MULT := 100.0
## Values that switch a boolean flag (--hardcore=0, --dungeon=No ...) off, compared lower-cased. A bare
## switch, or any other value, switches it on.
const FLAG_OFF_VALUES: Array[String] = ["0", "false", "no", "off"]

var smoke := false
var demo := false
var players := DEFAULT_BOTS
## Bot class ids from --classes (empty = cycle through Db.class_ids).
var classes: Array[StringName] = []
## The companion id of --companion (&"" = each bot takes its class's first choice).
var companion: StringName = &""
## --alt-weapon: the bots take the alternative starting weapon of their class.
var alt_weapon := false
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
## < 0 = the normal Loot Goblin chance.
var goblin_chance := -1.0
var elite_mult := 1.0
var start_level := 1
## "" = the panels open on the Character tab.
var panel_tab := ""
## Boss HP multiplier (--boss-hp), 1 = the normal HP.
var boss_hp := 1.0
## < 0 = off (the normal Artifact chances); else the chance of every Artifact roll.
var artifact_chance := -1.0
## --patch-tab / --loadout-tab (M9 PATCH, screenshots): "" = the default tab.
var patch_tab := ""
var loadout_tab := ""
## "" = the end screen opens on the Summary page (--end-page; GameOverScreen.PAGE_IDS).
var end_page := ""
## --save-card: the forced end screen saves the run card right away.
var save_card := false
## The run mode (--mode; RunState.MODES) and the hardcore flag (--hardcore) of the next run.
var mode: StringName = RunState.MODE_NORMAL
var hardcore := false
## "" = the environment is rolled; else the forced id (--env, validated against Db.environments).
var environment: StringName = &""
## "" = events roll normally; else the forced event (--event, EventSpawner.EVENT_IDS).
var event: StringName = &""
## < 0 = the normal shrine chance; else the chance at every break (--shrine-chance).
var shrine_chance := -1.0
## --dungeon: the portal opens after the next wave.
var dungeon := false
## "" = the player's own leaderboard file (smoke / demo / view runs do not write it); else the file of
## --leaderboard, which every run writes.
var leaderboard_path := ""
## The difficulty tier of --difficulty (a Difficulty id; the lobby's selector changes it for the next run).
var difficulty: StringName = &"normal"
## The meta profile of --profile (Meta.PROFILE_KINDS; &"" = the default of the session) and the file of
## --profile-path ("" = none).
var profile_kind: StringName = &""
var profile_path := ""
## The Seasonings of --seasonings, in the order given (the bots take the ones of their class).
var seasonings: Array[StringName] = []
## The Heirloom of --heirloom (&"" = none: the heroes take what their slot has).
var heirloom: StringName = &""
## Arguments that were not understood, an invalid value included (reported once by Main; a smoke run
## reports "bad_args" with them, see Main.smoke_outcome).
var unknown: Array[String] = []


## A boolean flag's value: on, unless it is one of FLAG_OFF_VALUES (case-insensitive).
static func _flag_on(value: String) -> bool:
	return not (value.to_lower() in FLAG_OFF_VALUES)


static func parse(args: PackedStringArray) -> LaunchOptions:
	var o := LaunchOptions.new()
	var seasonings_arg := ""
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
			"--classes":
				var bad := false
				for part in value.split(",", false):
					var id := StringName(part.strip_edges())
					if Db.get_class_data(id) == null:
						bad = true
					o.classes.append(id)
				if bad:
					o.unknown.append(arg)
			"--companion":
				if StringName(value) in Db.companion_ids():
					o.companion = StringName(value)
				else:
					o.unknown.append(arg)
			"--alt-weapon":
				o.alt_weapon = _flag_on(value)
			"--waves":
				o.waves = maxi(1, value.to_int())
			"--start-wave":
				o.start_wave = maxi(1, value.to_int())  # (clamped to the mode's length below)
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
			"--goblin-chance":
				o.goblin_chance = clampf(value.to_float(), 0.0, 1.0)
			"--elite-mult":
				o.elite_mult = maxf(0.0, value.to_float())
			"--start-level":
				o.start_level = clampi(value.to_int(), RunState.START_LEVEL, MAX_START_LEVEL)
			"--panel-tab":
				if value in PANEL_TABS:
					o.panel_tab = value
				else:
					o.unknown.append(arg)
			"--boss-hp":
				o.boss_hp = clampf(value.to_float(), MIN_BOSS_HP_MULT, MAX_BOSS_HP_MULT)
			"--artifact-chance":
				o.artifact_chance = clampf(value.to_float(), 0.0, 1.0)
			"--end-page":
				if value in GameOverScreen.PAGE_IDS:
					o.end_page = value
				else:
					o.unknown.append(arg)
			"--patch-tab":
				if value in PATCH_TABS:
					o.patch_tab = value
				else:
					o.unknown.append(arg)
			"--loadout-tab":
				if value in LOADOUT_TABS:
					o.loadout_tab = value
				else:
					o.unknown.append(arg)
			"--save-card":
				o.save_card = true
			"--mode":
				if StringName(value) in RunState.MODES:
					o.mode = StringName(value)
				else:
					o.unknown.append(arg)
			"--hardcore":
				o.hardcore = _flag_on(value)
			"--env":
				if Db.get_environment(StringName(value)) != null:
					o.environment = StringName(value)
				else:
					o.unknown.append(arg)
			"--event":
				var event_id := EventSpawner.parse_id(value)
				if event_id != &"":
					o.event = event_id
				else:
					o.unknown.append(arg)
			"--shrine-chance":
				if value.is_valid_float():
					o.shrine_chance = clampf(value.to_float(), 0.0, 1.0)
				else:
					o.unknown.append(arg)  # (not a number: unset, the normal chance)
			"--dungeon":
				o.dungeon = _flag_on(value)
			"--leaderboard":
				if value != "":
					o.leaderboard_path = value
				else:
					o.unknown.append(arg)
			"--difficulty":
				if Db.difficulties.has(StringName(value)):
					o.difficulty = StringName(value)
				else:
					o.unknown.append(arg)
			"--profile":
				if StringName(value) in Meta.PROFILE_KINDS:
					o.profile_kind = StringName(value)
				else:
					o.unknown.append(arg)
			"--profile-path":
				if value != "":
					o.profile_path = value
				else:
					o.unknown.append(arg)
			"--seasonings":
				seasonings_arg = arg
				for part in value.split(",", false):
					o.seasonings.append(StringName(part.strip_edges()))
			"--heirloom":
				if Db.heirlooms.has(StringName(value)):
					o.heirloom = StringName(value)
				else:
					o.unknown.append(arg)
			_:
				# The unit test runner shares the command line; ignore its flags.
				if not key.begins_with("--filter"):
					o.unknown.append(arg)
	o.start_wave = o.clamp_wave(o.start_wave)
	if seasonings_arg != "":
		var problem := o.seasonings_problem()
		if problem != "":
			o.unknown.append("%s (%s)" % [seasonings_arg, problem])
			o.seasonings.clear()
	if o.profile_kind == Meta.PROFILE_DEV and o.profile_path != "":
		o.unknown.append("--profile=dev with --profile-path=%s (the dev profile never touches a file)" % o.profile_path)
	return o


## The class ids of the bots a launch with --players / --classes adds, in join order (Main._add_bots: --classes
## cycled, else every class the profile has unlocked).
func bot_classes() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in classes:
		if Db.get_class_data(id) != null:
			ids.append(id)
	if ids.is_empty():
		ids = Meta.unlocked_class_ids()
	var out: Array[StringName] = []
	if ids.is_empty():
		return out
	for i in players:
		out.append(ids[i % ids.size()])
	return out


## What is wrong with --seasonings ("" = fine): an unknown id, a repeated one, one whose class no bot plays, or more
## ids of a class than it has slots (Seasonings.MAX_SLOTS).
func seasonings_problem() -> String:
	var party := bot_classes()
	var per_class: Dictionary[StringName, int] = {}
	var seen: Array[StringName] = []
	for id in seasonings:
		var s := Db.get_seasoning(id)
		if s == null:
			return "unknown Seasoning '%s'" % id
		if id in seen:
			return "'%s' is listed twice" % id
		seen.append(id)
		if s.class_id not in party:
			return "no bot plays the %s, '%s' would do nothing" % [s.class_id, id]
		per_class[s.class_id] = int(per_class.get(s.class_id, 0)) + 1
		if per_class[s.class_id] > Seasonings.MAX_SLOTS:
			return "more than %d Seasonings for the %s" % [Seasonings.MAX_SLOTS, s.class_id]
	return ""


## The --seasonings of [param class_id], in the order given.
func seasonings_for(class_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in seasonings:
		var s := Db.get_seasoning(id)
		if s != null and s.class_id == class_id:
			out.append(id)
	return out


## A scripted launch (--smoke, --demo, --view, --screenshot): not the player's session, so it never reads or
## writes their files (settings, leaderboard) and never changes their window (Settings.is_automated_run).
func is_automated() -> bool:
	return smoke or demo or view != "" or screenshot_path != ""


## True when the game plays itself (no menus, bot players).
func starts_run() -> bool:
	return smoke or demo or view in RUN_VIEWS


## Bots join automatically (run views, or the lobby view to fill the cards).
func uses_bots() -> bool:
	return starts_run() or view == "lobby" or view == "roll"


## The screen Main boots into: &"menu", &"lobby" or &"run".
func boot_state() -> StringName:
	if starts_run():
		return &"run"
	if view == "lobby" or view == "roll":
		return &"lobby"
	return &"menu"


## [param w] as a wave number of this launch's mode: 1 .. 25 (normal), 1 .. MAX_ENDLESS_START_WAVE
## (endless).
func clamp_wave(w: int) -> int:
	var total := RunState.waves_for_mode(mode)
	return clampi(w, 1, total if total > 0 else MAX_ENDLESS_START_WAVE)


## Last wave a smoke run plays (start_wave + waves - 1, at most the mode's last wave).
func last_wave() -> int:
	return maxi(start_wave, clamp_wave(start_wave + waves - 1))


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
