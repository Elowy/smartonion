class_name SoundDef
extends Resource
## One sound (or music track) of the [SoundBank]: the streams it picks from, how loud, how
## often it may play and on which bus. Instances live inside data/audio/sound_bank.tres.

@export var id: StringName
## Variants: one is picked at random per play (never the same twice in a row).
@export var streams: Array[AudioStream] = []
## Base volume (dB) before the caller's offset; the bus volumes (Settings) come on top.
@export_range(-60.0, 12.0, 0.5) var volume_db: float = 0.0
## Base pitch scale, and the random spread around it (+-, as a fraction of the pitch).
@export_range(0.25, 4.0, 0.01) var pitch: float = 1.0
@export_range(0.0, 0.5, 0.01) var pitch_variation: float = 0.06
## At most this many voices of this sound at once (0 = unlimited). Hundreds of hits a second
## in a late four-player wave must not become hundreds of voices.
@export var max_voices: int = 4
## Seconds (real time) that must pass before the same sound plays again.
@export var min_interval: float = 0.04
## When every voice is busy a sound may steal the oldest voice of a LOWER priority.
@export var priority: int = 0
## Audio bus (SFX, UI or Music); Audio.play_ui always plays on UI.
@export var bus: StringName = &"SFX"


## The first variant (music tracks have exactly one stream).
func first_stream() -> AudioStream:
	return streams[0] if not streams.is_empty() else null
