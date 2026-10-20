class_name SoundBank
extends Resource
## All sounds and music tracks of the game (res://data/audio/sound_bank.tres): id -> [SoundDef].
## Content is data: a new sound is one more entry in the .tres, no code. Loaded by the Audio
## autoload.

@export var sounds: Array[SoundDef] = []
@export var music: Array[SoundDef] = []

var _sound_index: Dictionary[StringName, SoundDef] = {}
var _music_index: Dictionary[StringName, SoundDef] = {}
var _indexed := false


## The sound [param id] (null when unknown).
func sound(id: StringName) -> SoundDef:
	_ensure_index()
	return _sound_index.get(id)


## The music track [param id] (null when unknown).
func track(id: StringName) -> SoundDef:
	_ensure_index()
	return _music_index.get(id)


func sound_ids() -> Array[StringName]:
	_ensure_index()
	return _sound_index.keys()


func music_ids() -> Array[StringName]:
	_ensure_index()
	return _music_index.keys()


## Rebuilds the id lookups (after entries were added at run time).
func reindex() -> void:
	_indexed = false
	_ensure_index()


func _ensure_index() -> void:
	if _indexed:
		return
	_indexed = true
	_sound_index.clear()
	_music_index.clear()
	for def in sounds:
		if def != null and def.id != &"":
			_sound_index[def.id] = def
	for def in music:
		if def != null and def.id != &"":
			_music_index[def.id] = def
