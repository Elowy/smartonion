class_name GameSettings
extends RefCounted
## The player's settings (M7a): audio volumes, video options and a few gameplay-visual toggles, with their
## defaults, clamping / stepping rules and the ConfigFile they are saved in. Pure data: nothing here touches
## the engine (the Settings autoload applies the values to the buses, window and Engine), so tests build
## their own instance with a temp [member path].
##
## File (ConfigFile, [constant PATH]; see [SettingOption.to_file]):
##   [audio]    master_volume=100  music_volume=70  sfx_volume=80  ui_volume=80   (percent, step 10)
##   [video]    window_mode="windowed" | "borderless" | "fullscreen"   vsync=true
##              max_fps="30" | "60" | "120" | "144" | "unlimited"
##   [gameplay] screen_shake="off" | "low" | "full"   damage_numbers=true   show_fps=false
## A missing file, key or a value that is not understood gives the default; nothing here is ever fatal.
##
## None of these values may change a gameplay outcome: shake and damage numbers are drawn only, volumes and
## the window are the player's hardware. Nothing here draws from RunState.rng.

const PATH := "user://settings.cfg"

const MASTER_VOLUME := &"master_volume"
const MUSIC_VOLUME := &"music_volume"
const SFX_VOLUME := &"sfx_volume"
const UI_VOLUME := &"ui_volume"
const WINDOW_MODE := &"window_mode"
const VSYNC := &"vsync"
const MAX_FPS := &"max_fps"
const SCREEN_SHAKE := &"screen_shake"
const DAMAGE_NUMBERS := &"damage_numbers"
const SHOW_FPS := &"show_fps"

## Borderless Fullscreen is the desktop-sized window without borders (DisplayServer WINDOW_MODE_FULLSCREEN),
## Fullscreen the exclusive mode (WINDOW_MODE_EXCLUSIVE_FULLSCREEN).
enum WindowMode { WINDOWED, BORDERLESS, FULLSCREEN }
enum Shake { OFF, LOW, FULL }

const VOLUME_STEP := 10
## The dB of a muted bus (0 %): AudioServer's floor.
const MUTE_DB := -80.0
## The audio bus (default_bus_layout.tres) every volume setting drives; Master is the parent of the others.
const BUS_NAMES: Dictionary[StringName, StringName] = {
	MASTER_VOLUME: &"Master", MUSIC_VOLUME: &"Music", SFX_VOLUME: &"SFX", UI_VOLUME: &"UI",
}
## Camera trauma multiplier of every [enum Shake] level (CameraRig.shake).
const SHAKE_MULTS: Array[float] = [0.0, 0.5, 1.0]
## Frame-rate caps in display order; 0 = unlimited (Engine.max_fps).
const FPS_CAPS: Array[int] = [30, 60, 120, 144, 0]

static var _options: Array[SettingOption] = []

## Where [method load_file] / [method save_file] read and write (tests inject a temp path).
var path := PATH
## Current value of every key (always sanitised, see [method set_value]).
var values: Dictionary[StringName, Variant] = {}


func _init() -> void:
	for o in options():
		values[o.key] = o.default


## Every option in page order (cached; sections Audio, Video, Gameplay).
static func options() -> Array[SettingOption]:
	if _options.is_empty():
		_options = _build_options()
	return _options


## The option for [param key]; null for an unknown key.
static func option(key: StringName) -> SettingOption:
	for o in options():
		if o.key == key:
			return o
	return null


static func _build_options() -> Array[SettingOption]:
	var out: Array[SettingOption] = []
	out.append(SettingOption.percent(MASTER_VOLUME, "Audio", "Master Volume", 100))
	out.append(SettingOption.percent(MUSIC_VOLUME, "Audio", "Music Volume", 70))
	out.append(SettingOption.percent(SFX_VOLUME, "Audio", "Effects Volume", 80))
	out.append(SettingOption.percent(UI_VOLUME, "Audio", "Interface Volume", 80))
	out.append(SettingOption.choice(WINDOW_MODE, "Video", "Window Mode", WindowMode.WINDOWED,
			[WindowMode.WINDOWED, WindowMode.BORDERLESS, WindowMode.FULLSCREEN],
			["windowed", "borderless", "fullscreen"], ["Windowed", "Borderless Fullscreen", "Fullscreen"]))
	out.append(SettingOption.toggle(VSYNC, "Video", "VSync", true))
	out.append(SettingOption.choice(MAX_FPS, "Video", "Max FPS", 0, FPS_CAPS,
			["30", "60", "120", "144", "unlimited"], ["30", "60", "120", "144", "Unlimited"]))
	out.append(SettingOption.choice(SCREEN_SHAKE, "Gameplay", "Screen Shake", Shake.FULL,
			[Shake.OFF, Shake.LOW, Shake.FULL], ["off", "low", "full"], ["Off", "Low", "Full"]))
	out.append(SettingOption.toggle(DAMAGE_NUMBERS, "Gameplay", "Damage Numbers", true))
	out.append(SettingOption.toggle(SHOW_FPS, "Gameplay", "Show FPS", false))
	return out


## dB of a bus at [param percent] of full volume: linear amplitude, so 100 % = 0 dB, 50 % = -6 dB and 0 %
## the floor ([constant MUTE_DB]).
static func volume_to_db(percent: int) -> float:
	if percent <= 0:
		return MUTE_DB
	return maxf(linear_to_db(float(mini(percent, 100)) / 100.0), MUTE_DB)


# --- Values ------------------------------------------------------------------------------

func get_value(key: StringName) -> Variant:
	return values.get(key)


## Sets [param key] to the nearest legal [param value]. True when the stored value changed (false for an
## unknown key).
func set_value(key: StringName, value: Variant) -> bool:
	var o := option(key)
	if o == null:
		return false
	var v: Variant = o.sanitize(value)
	if values[key] == v:
		return false
	values[key] = v
	return true


## Moves [param key] one step ([param direction] < 0 left, > 0 right). True when it changed.
func step_value(key: StringName, direction: int) -> bool:
	var o := option(key)
	if o == null:
		return false
	return set_value(key, o.stepped(values[key], direction))


## The text shown for the current value of [param key].
func value_text(key: StringName) -> String:
	var o := option(key)
	return o.text(values[key]) if o != null else ""


## Every value back to its default. True when anything changed.
func reset_to_defaults() -> bool:
	var changed := false
	for o in options():
		changed = set_value(o.key, o.default) or changed
	return changed


func is_default() -> bool:
	for o in options():
		if values[o.key] != o.default:
			return false
	return true


# --- Typed reads -------------------------------------------------------------------------

func volume_percent(key: StringName) -> int:
	return int(values.get(key, 0))


func window_mode() -> WindowMode:
	return int(values[WINDOW_MODE]) as WindowMode


func vsync_enabled() -> bool:
	return bool(values[VSYNC])


## Frame-rate cap in frames per second; 0 = unlimited.
func max_fps() -> int:
	return int(values[MAX_FPS])


func shake_level() -> Shake:
	return int(values[SCREEN_SHAKE]) as Shake


## 0 / 0.5 / 1: what CameraRig.shake multiplies its trauma by.
func screen_shake_mult() -> float:
	return SHAKE_MULTS[int(values[SCREEN_SHAKE])]


func damage_numbers_enabled() -> bool:
	return bool(values[DAMAGE_NUMBERS])


func show_fps_enabled() -> bool:
	return bool(values[SHOW_FPS])


# --- File --------------------------------------------------------------------------------

## Reads [member path] into the values (defaults for everything it does not hold). OK also when there is no
## file yet; otherwise the Error of an unreadable one (the values stay the defaults).
func load_file() -> Error:
	reset_to_defaults()
	if not FileAccess.file_exists(path):
		return OK
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		return err
	for o in options():
		var section := o.section.to_lower()
		var raw: Variant = cfg.get_value(section, String(o.key)) if cfg.has_section_key(section, String(o.key)) else null
		set_value(o.key, o.from_file(raw))
	return OK


## Writes every value to [member path] (to a temporary file that then replaces it). Returns the Error.
func save_file() -> Error:
	var cfg := ConfigFile.new()
	for o in options():
		cfg.set_value(o.section.to_lower(), String(o.key), o.to_file(values[o.key]))
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		var made := DirAccess.make_dir_recursive_absolute(dir)
		if made != OK:
			return made
	var tmp := path + ".tmp"
	var err := cfg.save(tmp)
	if err != OK:
		return err
	return DirAccess.rename_absolute(tmp, path)
