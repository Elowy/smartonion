extends Node
## Autoload "Audio": every sound and music track of the game (M7a).
##
## - [method play] gameplay sounds (SFX bus), [method play_ui] menu sounds (UI bus),
##   [method play_music] / [method stop_music] looping tracks with a crossfade (Music bus).
##   Ids and their streams, volumes and limits are data: data/audio/sound_bank.tres ([SoundBank]).
## - The game is a shared screen for up to four players, so every sound is plain 2D (non-positional)
##   on a small pool of [AudioStreamPlayer]s. A late four-player wave lands hundreds of hits a
##   second: each sound has a voice limit ([member SoundDef.max_voices]) and a minimum re-trigger
##   interval ([member SoundDef.min_interval]), and the pool never grows. A sound that is
##   throttled, over its limit or without a free voice is simply dropped (counted in
##   [method rejected_count]).
## - An unknown id or a missing stream is a silent no-op (no error): a typo in a call site must not
##   break a run. tests/test_m7_audio.gd checks every id used in the code against the bank.
## - Never touches RunState.rng: the variant and pitch variation come from this node's own
##   [RandomNumberGenerator], so seeded smoke runs stay bit-identical.
## - process_mode is ALWAYS: menus click and the music fades while the tree is paused.
## - Works headless (Godot's dummy audio driver): nothing is audible but every counter works.

## A music track started (or [code]&""[/code] after [method stop_music]).
signal music_changed(track: StringName)

const BANK_PATH := "res://data/audio/sound_bank.tres"
const BUS_SFX := &"SFX"
const BUS_UI := &"UI"
const BUS_MUSIC := &"Music"
## Pooled voices of the SFX / UI players (all sounds share them).
const VOICES := 24
## Music players: the playing track, the one fading out and a spare for quick switches.
const MUSIC_VOICES := 3
const DEFAULT_FADE := 1.0
## Faded-out volume (dB) and the volume below which a sound is not even started.
const SILENT_DB := -80.0
const INAUDIBLE_DB := -60.0

var bank: SoundBank
## Tests: a value >= 0 replaces the real clock (seconds), so the minimum intervals are testable.
var clock_override := -1.0

var _rng := RandomNumberGenerator.new()
var _players: Array[AudioStreamPlayer] = []
var _voice_id: Array[StringName] = []
var _voice_started: Array[float] = []
var _voice_priority: Array[int] = []
var _last_play: Dictionary[StringName, float] = {}
var _last_variant: Dictionary[StringName, int] = {}
var _counts: Dictionary[StringName, int] = {}
var _rejected: Dictionary[StringName, int] = {}
var _unknown := 0
var _music: Array[MusicVoice] = []
var _music_current: StringName = &""


## One music player with its fade state.
class MusicVoice extends RefCounted:
	var player: AudioStreamPlayer
	var id: StringName = &""
	## Fade factor 0..1 (linear amplitude), moving towards [member target].
	var gain := 0.0
	var target := 0.0
	## Fade speed in gain per second.
	var rate := 1.0
	var base_db := 0.0

	func is_active() -> bool:
		return id != &"" and target > 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	load_bank()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		p.bus = BUS_SFX
		add_child(p)
		_players.append(p)
		_voice_id.append(&"")
		_voice_started.append(0.0)
		_voice_priority.append(0)
	for i in MUSIC_VOICES:
		var mv := MusicVoice.new()
		mv.player = AudioStreamPlayer.new()
		mv.player.name = "Music%d" % i
		mv.player.bus = BUS_MUSIC
		add_child(mv.player)
		_music.append(mv)


func _process(delta: float) -> void:
	# Fades run in real time: a smoke run at time scale 4 must not cut them short.
	advance(delta / maxf(Engine.time_scale, 0.01))


# --- Bank ------------------------------------------------------------------------------

## Loads the sound bank (an empty one when the file is missing: everything is then a no-op).
func load_bank(path: String = BANK_PATH) -> bool:
	bank = null
	if ResourceLoader.exists(path):
		bank = load(path) as SoundBank
	if bank == null:
		bank = SoundBank.new()
		return false
	return true


# --- Sounds ----------------------------------------------------------------------------

## Plays the gameplay sound [param id] on its bus (SFX unless the bank says otherwise);
## [param volume_db_offset] is added to the bank's volume. Returns false when the sound is unknown,
## throttled, over its voice limit or without a free voice.
func play(id: StringName, volume_db_offset: float = 0.0) -> bool:
	return _play_sound(id, volume_db_offset, &"")


## Plays the menu sound [param id] on the UI bus.
func play_ui(id: StringName, volume_db_offset: float = 0.0) -> bool:
	return _play_sound(id, volume_db_offset, BUS_UI)


func _play_sound(id: StringName, volume_db_offset: float, bus_override: StringName) -> bool:
	var def: SoundDef = bank.sound(id) if bank != null else null
	if def == null or def.streams.is_empty():
		_unknown += 1
		return false
	var now := _now()
	if now - float(_last_play.get(id, -1000.0)) < def.min_interval:
		_reject(id)
		return false
	if def.max_voices > 0 and active_voices(id) >= def.max_voices:
		_reject(id)
		return false
	var volume := def.volume_db + volume_db_offset
	if volume <= INAUDIBLE_DB:
		return false
	var voice := _acquire_voice(def.priority)
	if voice < 0:
		_reject(id)
		return false
	var stream := def.streams[_pick_variant(id, def.streams.size())]
	if stream == null:
		return false
	var p := _players[voice]
	p.stream = stream
	p.bus = bus_override if bus_override != &"" else def.bus
	p.volume_db = volume
	p.pitch_scale = maxf(0.1, def.pitch * (1.0 + _rng.randf_range(-def.pitch_variation, def.pitch_variation)))
	p.play()
	_voice_id[voice] = id
	_voice_started[voice] = now
	_voice_priority[voice] = def.priority
	_last_play[id] = now
	_counts[id] = int(_counts.get(id, 0)) + 1
	return true


## A free voice, else the oldest one of a strictly lower priority (stopped); -1 when none.
func _acquire_voice(priority: int) -> int:
	var steal := -1
	for i in _players.size():
		if not _players[i].playing:
			return i
		if _voice_priority[i] < priority and (steal < 0 or _voice_started[i] < _voice_started[steal]):
			steal = i
	if steal >= 0:
		_players[steal].stop()
	return steal


## A random variant index that is not the one played last (when there is a choice).
func _pick_variant(id: StringName, count: int) -> int:
	if count <= 1:
		return 0
	var pick := _rng.randi_range(0, count - 2)
	if pick >= int(_last_variant.get(id, -1)):
		pick += 1
	_last_variant[id] = pick
	return pick


func _reject(id: StringName) -> void:
	_rejected[id] = int(_rejected.get(id, 0)) + 1


func _now() -> float:
	return clock_override if clock_override >= 0.0 else Time.get_ticks_usec() / 1000000.0


## Voices of [param id] that are sounding right now.
func active_voices(id: StringName) -> int:
	var n := 0
	for i in _players.size():
		if _voice_id[i] == id and _players[i].playing:
			n += 1
	return n


## Sounds that are sounding right now (all ids).
func total_active_voices() -> int:
	var n := 0
	for p in _players:
		if p.playing:
			n += 1
	return n


# --- Counters (tests / debugging) ----------------------------------------------------------

## How often [param id] was really started since the last [method reset].
func play_count(id: StringName) -> int:
	return int(_counts.get(id, 0))


## How often [param id] was dropped by its interval, voice limit or an empty pool.
func rejected_count(id: StringName) -> int:
	return int(_rejected.get(id, 0))


## Calls with an unknown id (or no stream) since the last [method reset].
func unknown_count() -> int:
	return _unknown


func total_play_count() -> int:
	var n := 0
	for id in _counts:
		n += int(_counts[id])
	return n


## Stops everything and clears the counters and timers (tests).
func reset() -> void:
	for i in _players.size():
		_players[i].stop()
		_voice_id[i] = &""
	for mv in _music:
		mv.player.stop()
		mv.id = &""
		mv.gain = 0.0
		mv.target = 0.0
	_music_current = &""
	_last_play.clear()
	_last_variant.clear()
	_counts.clear()
	_rejected.clear()
	_unknown = 0
	clock_override = -1.0


# --- Music -----------------------------------------------------------------------------

## Starts the looping track [param track] with a [param fade] second crossfade (the playing track
## fades out). The same track again does nothing; an unknown track leaves the music as it is.
## An empty id stops the music.
func play_music(track: StringName, fade: float = DEFAULT_FADE) -> void:
	if track == &"":
		stop_music(fade)
		return
	var def: SoundDef = bank.track(track) if bank != null else null
	if def == null or def.first_stream() == null:
		return
	for mv in _music:
		if mv.id == track and mv.target > 0.0:
			return
	for mv in _music:
		if mv.is_active():
			_fade(mv, 0.0, fade)
	# A track that is still fading out comes back from where it is.
	var voice: MusicVoice = null
	for mv in _music:
		if mv.id == track:
			voice = mv
	if voice == null:
		voice = _free_music_voice()
		voice.id = track
		voice.base_db = def.volume_db
		voice.gain = 0.0
		voice.player.stream = def.first_stream()
		voice.player.bus = def.bus
		voice.player.pitch_scale = def.pitch
		voice.player.volume_db = SILENT_DB
		voice.player.play()
	_fade(voice, 1.0, fade)
	_music_current = track
	music_changed.emit(track)


## Fades the music out ([param fade] seconds) and stops it.
func stop_music(fade: float = DEFAULT_FADE) -> void:
	for mv in _music:
		if mv.is_active():
			_fade(mv, 0.0, fade)
	if _music_current != &"":
		_music_current = &""
		music_changed.emit(&"")


## The track that plays (or fades in) now; [code]&""[/code] when there is none.
func current_music() -> StringName:
	return _music_current


## Fade factor (0..1) of [param track]'s voice; 0 when it is not playing.
func music_gain(track: StringName) -> float:
	for mv in _music:
		if mv.id == track:
			return mv.gain
	return 0.0


## Music voices that hold a track right now (playing or fading out).
func music_voices_in_use() -> int:
	var n := 0
	for mv in _music:
		if mv.id != &"":
			n += 1
	return n


func _fade(mv: MusicVoice, to: float, seconds: float) -> void:
	mv.target = to
	if seconds <= 0.0:
		mv.gain = to
		_apply_music_voice(mv)
	else:
		mv.rate = 1.0 / seconds


## An unused music voice, else the quietest one (cut off; it was fading out).
func _free_music_voice() -> MusicVoice:
	var quiet: MusicVoice = null
	for mv in _music:
		if mv.id == &"":
			return mv
		if mv.target <= 0.0 and (quiet == null or mv.gain < quiet.gain):
			quiet = mv
	if quiet == null:
		quiet = _music[0]
	quiet.player.stop()
	quiet.id = &""
	return quiet


## Moves the fades on by [param delta] seconds (real time; _process calls it, tests call it too).
func advance(delta: float) -> void:
	for mv in _music:
		if mv.id == &"":
			continue
		if mv.gain != mv.target:
			mv.gain = move_toward(mv.gain, mv.target, mv.rate * delta)
		_apply_music_voice(mv)


func _apply_music_voice(mv: MusicVoice) -> void:
	if mv.id == &"":
		return
	if mv.gain <= 0.0 and mv.target <= 0.0:
		mv.player.stop()
		mv.id = &""
		return
	mv.player.volume_db = SILENT_DB if mv.gain <= 0.0 else maxf(SILENT_DB, mv.base_db + linear_to_db(mv.gain))
