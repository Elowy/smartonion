extends TestCase
## M7a AUDIO: the sound bank, the bus layout, the Audio autoload (voice limits, minimum intervals,
## unknown ids, music switching) and the guarantee that audio never touches RunState.rng.

const CODE_DIRS: Array[String] = ["res://scenes", "res://core", "res://autoload", "res://data"]
const BUSES: Array[StringName] = [&"Music", &"SFX", &"UI"]
const MUSIC_TRACKS: Array[StringName] = [&"menu", &"combat", &"intermission", &"boss"]


func before_each() -> void:
	Audio.reset()


func after_each() -> void:
	Audio.reset()


# --- Bank and buses ------------------------------------------------------------------------

func test_the_bank_loads_with_sounds_and_the_four_tracks() -> void:
	check(Audio.bank != null, "the bank is loaded")
	check(Audio.bank.sounds.size() >= 40, "the bank has the sounds (%d)" % Audio.bank.sounds.size())
	for track in MUSIC_TRACKS:
		check(Audio.bank.track(track) != null, "music track %s" % track)
	check_eq(Audio.bank.music.size(), MUSIC_TRACKS.size(), "no extra track")
	for id: StringName in [&"hit", &"hit_crit", &"enemy_death", &"hero_hurt", &"level_up", &"gold_pickup",
			&"ui_move", &"ui_confirm", &"ui_back", &"ui_error", &"victory", &"defeat", &"explosion"]:
		check(Audio.bank.sound(id) != null, "sound %s" % id)


func test_every_bank_entry_has_real_streams_and_valid_settings() -> void:
	var seen: Dictionary[StringName, bool] = {}
	for def in Audio.bank.sounds + Audio.bank.music:
		check(def != null, "no null entry")
		if def == null:
			continue
		var tag := String(def.id)
		check(def.id != &"", "an entry without id")
		check(not seen.has(def.id), "%s is unique" % tag)
		seen[def.id] = true
		check(not def.streams.is_empty(), "%s has streams" % tag)
		for stream in def.streams:
			check(stream != null, "%s: a stream is missing" % tag)
			if stream != null:
				check(stream.get_length() > 0.0, "%s: an empty stream" % tag)
		check(def.max_voices >= 0, "%s: max_voices" % tag)
		check(def.min_interval >= 0.0, "%s: min_interval" % tag)
		check(def.volume_db <= 6.0 and def.volume_db > Audio.INAUDIBLE_DB, "%s: volume %s" % [tag, def.volume_db])
		check(def.pitch > 0.0 and def.pitch_variation >= 0.0 and def.pitch_variation < 0.5, "%s: pitch" % tag)
		check(def.bus in BUSES, "%s: bus %s" % [tag, def.bus])


func test_the_bus_layout_has_music_sfx_and_ui_under_master() -> void:
	for bus in BUSES:
		var index := AudioServer.get_bus_index(bus)
		check(index > 0, "bus %s exists" % bus)
		if index > 0:
			check_eq(AudioServer.get_bus_send(index), &"Master", "%s sends to Master" % bus)


func test_music_tracks_loop_and_play_on_the_music_bus() -> void:
	for track in MUSIC_TRACKS:
		var def := Audio.bank.track(track)
		check_eq(def.streams.size(), 1, "%s has one stream" % track)
		check_eq(def.bus, &"Music", "%s plays on Music" % track)
		var stream := def.first_stream() as AudioStreamOggVorbis
		check(stream != null, "%s is an ogg" % track)
		if stream != null:
			check(stream.loop, "%s loops" % track)
			check(stream.get_length() > 20.0, "%s is a real track" % track)


func test_every_sound_id_used_in_the_code_is_in_the_bank() -> void:
	var rx := RegEx.create_from_string("Audio\\.play(?:_ui)?\\(\\s*&\"([A-Za-z0-9_]+)\"")
	var music_rx := RegEx.create_from_string("Audio\\.play_music\\(\\s*&\"([A-Za-z0-9_]+)\"")
	var files: Array[String] = []
	for dir in CODE_DIRS:
		_collect_scripts(dir, files)
	var used := 0
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for m in rx.search_all(text):
			used += 1
			var id := StringName(m.get_string(1))
			check(Audio.bank.sound(id) != null, "%s plays %s, which is not in the bank" % [path, id])
		for m in music_rx.search_all(text):
			var id := StringName(m.get_string(1))
			check(Audio.bank.track(id) != null, "%s plays track %s, which is not in the bank" % [path, id])
	check(used >= 40, "the call sites were found (%d)" % used)


func _collect_scripts(dir: String, out: Array[String]) -> void:
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		_collect_scripts(dir.path_join(sub), out)


# --- Weapon and ability mapping ------------------------------------------------------------

func test_every_weapon_and_ability_maps_to_a_banked_sound() -> void:
	for id in Db.weapons:
		var w: WeaponData = Db.weapons[id]
		if not w.attacks():
			continue
		var sound := AudioIds.swing(w) if w.attack_kind == WeaponData.AttackKind.MELEE_ARC else AudioIds.shot(w)
		check(Audio.bank.sound(sound) != null, "%s -> %s is in the bank" % [id, sound])
	for id in Db.abilities:
		var sound := AudioIds.ability(Db.abilities[id])
		check(Audio.bank.sound(sound) != null, "%s -> %s is in the bank" % [id, sound])
	var schools: Array[StringName] = AudioIds.CAST_SCHOOLS.duplicate()
	schools.append_array([&"physical", &"bogus"] as Array[StringName])
	for school in schools:
		check(Audio.bank.sound(AudioIds.cast_for_school(school)) != null, "cast_for_school %s" % school)


func test_weapon_families_pick_their_sounds() -> void:
	check_eq(AudioIds.swing(Db.weapons[&"dagger"]), &"swing_light", "dagger")
	check_eq(AudioIds.swing(Db.weapons[&"sword"]), &"swing_blade", "sword")
	check_eq(AudioIds.swing(Db.weapons[&"two_hand_sword"]), &"swing_heavy", "two-hand sword")
	check_eq(AudioIds.shot(Db.weapons[&"bow"]), &"shot_bow", "bow")
	check_eq(AudioIds.shot(Db.weapons[&"gun"]), &"shot_gun", "gun")
	check_eq(AudioIds.swing(null), &"swing_blade", "no weapon")


func test_ability_sounds_follow_what_the_ability_does_then_its_school() -> void:
	check_eq(AudioIds.ability(Db.abilities[&"charge"]), &"ability_move", "a movement ability")
	check_eq(AudioIds.ability(Db.abilities[&"fireball"]), &"ability_fire", "a fire spell")
	check_eq(AudioIds.ability(null), &"ability_physical", "no ability")
	var heal := AbilityData.new()
	heal.tags = [&"heal", &"spell"] as Array[StringName]
	heal.school = &"holy"
	check_eq(AudioIds.ability(heal), &"ability_heal", "heal wins over the school")


# --- Playing, throttling, voice limits -----------------------------------------------------

func test_an_unknown_id_is_a_silent_no_op() -> void:
	check(not Audio.play(&"no_such_sound"), "play: false")
	check(not Audio.play_ui(&"no_such_sound"), "play_ui: false")
	check(not Audio.play(&""), "an empty id")
	Audio.play_music(&"no_such_track")
	check_eq(Audio.current_music(), &"", "an unknown track starts nothing")
	check_eq(Audio.unknown_count(), 3, "three unknown calls were counted")
	check_eq(Audio.total_play_count(), 0, "nothing played")
	check_eq(Audio.total_active_voices(), 0, "no voice is busy")


func test_a_known_sound_plays_and_is_counted() -> void:
	Audio.clock_override = 10.0
	check(Audio.play(&"ui_confirm"), "play_ui sound through play")
	check_eq(Audio.play_count(&"ui_confirm"), 1, "counted")
	check_eq(Audio.active_voices(&"ui_confirm"), 1, "one voice sounds")
	Audio.clock_override = 20.0
	check(Audio.play_ui(&"ui_confirm", -6.0), "play_ui with a volume offset")
	check_eq(Audio.play_count(&"ui_confirm"), 2, "counted again")


func test_a_volume_offset_below_hearing_is_not_started() -> void:
	Audio.clock_override = 10.0
	check(not Audio.play(&"hit", -80.0), "-80 dB is silence")
	check_eq(Audio.play_count(&"hit"), 0, "not started")


func test_the_minimum_interval_throttles_a_sound() -> void:
	var gap := Audio.bank.sound(&"hit").min_interval
	check(gap > 0.0, "hit has an interval")
	Audio.clock_override = 100.0
	check(Audio.play(&"hit"), "first hit")
	Audio.clock_override = 100.0 + gap * 0.5
	check(not Audio.play(&"hit"), "too soon")
	check_eq(Audio.rejected_count(&"hit"), 1, "rejected once")
	Audio.clock_override = 100.0 + gap * 1.01
	check(Audio.play(&"hit"), "after the interval")
	check_eq(Audio.play_count(&"hit"), 2, "two played")


func test_the_voice_limit_of_a_sound_holds_under_a_flood() -> void:
	var def := Audio.bank.sound(&"hit")
	var t := 50.0
	var accepted := 0
	for i in 600:
		t += def.min_interval * 1.1
		Audio.clock_override = t
		if Audio.play(&"hit"):
			accepted += 1
		check(Audio.active_voices(&"hit") <= def.max_voices, "never above max_voices")
	check(accepted >= def.max_voices, "the first hits played (%d)" % accepted)
	check(accepted < 600, "the flood was thinned out")
	check(Audio.rejected_count(&"hit") > 0, "the limit rejected hits")
	check(Audio.total_active_voices() <= Audio.VOICES, "the pool never grows")


func test_a_flood_of_every_sound_never_exceeds_the_pool() -> void:
	var ids := Audio.bank.sound_ids()
	var t := 10.0
	for rnd in 40:
		t += 0.2
		Audio.clock_override = t
		for id in ids:
			Audio.play(id)
		check(Audio.total_active_voices() <= Audio.VOICES, "pool size in round %d" % rnd)
	check(Audio.total_play_count() > 0, "sounds played")


func test_a_higher_priority_sound_steals_the_oldest_lower_priority_voice() -> void:
	# Fill the pool with priority-0 sounds (a few ids, each up to its own voice limit).
	var t := 5.0
	for i in 8:
		for def in Audio.bank.sounds:
			if def.priority == 0 and def.max_voices >= 2:
				t += 1.0
				Audio.clock_override = t
				Audio.play(def.id)
	if Audio.total_active_voices() < Audio.VOICES:
		return  # not every voice is busy (short sounds already ended): nothing to steal from
	t += 1.0
	Audio.clock_override = t
	check(Audio.play(&"victory"), "a priority-3 stinger finds a voice even in a full pool")
	check_eq(Audio.active_voices(&"victory"), 1, "it sounds")
	check(Audio.total_active_voices() <= Audio.VOICES, "the pool did not grow")


func test_equal_priority_does_not_steal_from_a_full_pool() -> void:
	var t := 5.0
	for i in 8:
		for def in Audio.bank.sounds:
			if def.priority == 0 and def.max_voices >= 2:
				t += 1.0
				Audio.clock_override = t
				Audio.play(def.id)
	if Audio.total_active_voices() < Audio.VOICES:
		return
	t += 1.0
	Audio.clock_override = t
	var before := Audio.rejected_count(&"hit")
	check(not Audio.play(&"hit"), "a priority-0 sound is dropped when every voice is busy")
	check_eq(Audio.rejected_count(&"hit"), before + 1, "and counted as rejected")


# --- Music -------------------------------------------------------------------------------

func test_play_music_starts_a_track_and_the_same_track_again_does_nothing() -> void:
	Audio.play_music(&"menu", 0.0)
	check_eq(Audio.current_music(), &"menu", "menu plays")
	check_eq(Audio.music_voices_in_use(), 1, "one music voice")
	check_near(Audio.music_gain(&"menu"), 1.0, 0.001, "an instant start (no fade)")
	Audio.play_music(&"menu", 0.0)
	check_eq(Audio.music_voices_in_use(), 1, "the same track again is a no-op")


func test_switching_tracks_crossfades_and_then_frees_the_old_voice() -> void:
	Audio.play_music(&"menu", 0.0)
	Audio.play_music(&"combat", 1.0)
	check_eq(Audio.current_music(), &"combat", "combat is current")
	check_eq(Audio.music_voices_in_use(), 2, "both voices during the fade")
	check_near(Audio.music_gain(&"combat"), 0.0, 0.001, "combat starts silent")
	Audio.advance(0.5)
	check_near(Audio.music_gain(&"combat"), 0.5, 0.01, "combat is half in")
	check_near(Audio.music_gain(&"menu"), 0.5, 0.01, "menu is half out")
	Audio.advance(0.6)
	check_near(Audio.music_gain(&"combat"), 1.0, 0.001, "combat is fully in")
	check_eq(Audio.music_voices_in_use(), 1, "the old voice is released")
	check_near(Audio.music_gain(&"menu"), 0.0, 0.001, "menu is gone")


func test_stop_music_fades_out_and_an_empty_track_stops_too() -> void:
	Audio.play_music(&"intermission", 0.0)
	Audio.stop_music(0.5)
	check_eq(Audio.current_music(), &"", "no current track")
	Audio.advance(0.6)
	check_eq(Audio.music_voices_in_use(), 0, "all voices released")
	Audio.play_music(&"boss", 0.0)
	Audio.play_music(&"", 0.0)
	check_eq(Audio.current_music(), &"", "an empty id stops")
	check_eq(Audio.music_voices_in_use(), 0, "instant stop")


func test_a_track_that_is_fading_out_comes_back_on_the_same_voice() -> void:
	Audio.play_music(&"combat", 0.0)
	Audio.play_music(&"boss", 2.0)
	Audio.advance(0.5)
	var gain := Audio.music_gain(&"combat")
	check(gain > 0.0 and gain < 1.0, "combat is fading out")
	Audio.play_music(&"combat", 1.0)
	check_eq(Audio.current_music(), &"combat", "combat is current again")
	check_eq(Audio.music_voices_in_use(), 2, "no third voice was taken")
	check_near(Audio.music_gain(&"combat"), gain, 0.001, "it continues from where it was")
	Audio.advance(1.5)
	check_near(Audio.music_gain(&"combat"), 1.0, 0.001, "combat is back")
	check_eq(Audio.music_voices_in_use(), 1, "boss is gone")


func test_rapid_track_changes_never_use_more_than_the_music_voices() -> void:
	var tracks: Array[StringName] = [&"menu", &"combat", &"boss", &"intermission", &"menu", &"boss", &"combat"]
	for track in tracks:
		Audio.play_music(track, 1.0)
		Audio.advance(0.1)
		check(Audio.music_voices_in_use() <= Audio.MUSIC_VOICES, "within the music voices")
	check_eq(Audio.current_music(), &"combat", "the last request wins")
	Audio.advance(2.0)
	check_eq(Audio.music_voices_in_use(), 1, "only the last track is left")


func test_music_changed_is_emitted_for_a_new_track_and_for_a_stop() -> void:
	var seen: Array[StringName] = []
	var on_changed := func(track: StringName) -> void: seen.append(track)
	Audio.music_changed.connect(on_changed)
	Audio.play_music(&"menu", 0.0)
	Audio.play_music(&"menu", 0.0)
	Audio.play_music(&"combat", 0.0)
	Audio.stop_music(0.0)
	Audio.stop_music(0.0)
	Audio.music_changed.disconnect(on_changed)
	check_eq(seen, [&"menu", &"combat", &""] as Array[StringName], "one signal per change")


# --- Determinism ---------------------------------------------------------------------------

func test_audio_never_consumes_the_gameplay_rng() -> void:
	RunState.rng.seed = 12345
	RunState.rng.randi()
	var before := RunState.rng.state
	var t := 1.0
	for i in 300:
		t += 0.5
		Audio.clock_override = t
		for id: StringName in [&"hit", &"hit_crit", &"enemy_death", &"ui_move", &"gold_pickup", &"swing_blade"]:
			Audio.play(id)
	Audio.play_music(&"combat", 0.5)
	Audio.advance(0.3)
	Audio.play_music(&"boss", 0.5)
	Audio.stop_music(0.2)
	check(Audio.total_play_count() > 10, "sounds played (%d)" % Audio.total_play_count())
	check_eq(RunState.rng.state, before, "RunState.rng state is untouched")
	var expected := RandomNumberGenerator.new()
	expected.seed = 12345
	expected.randi()
	check_eq(RunState.rng.randi(), expected.randi(), "the next gameplay draw is the one a silent run gets")
