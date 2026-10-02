extends SceneTree
var checks := 0
var failures: Array[String] = []
func _init(): call_deferred("run")
func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message)
func run():
	var music = root.get_node("MusicManager")
	var audio = root.get_node("SoundManager")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-device="): AudioServer.output_device = arg.trim_prefix("--output-device=")
	var previous: Dictionary = audio.preferences.duplicate()
	audio.preferences.muted = false; audio.preferences.music_muted = false
	audio.preferences.UI = 0.7
	audio.preferences.Master = 0.8; audio.preferences.Music = 0.7; audio.apply_preferences()
	check(music.device_enabled and music.channels.size() == 2, "native device has exactly two music voices")
	var record := AudioEffectRecord.new(); AudioServer.add_bus_effect(0, record)
	record.set_recording_active(true)
	music.enter_title(); await create_timer(2).timeout
	check(music.channels[music.current_channel].player.playing and music.position > 1, "native title playing")
	music.toggle_pause(); var frozen: float = music.position
	await create_timer(0.3).timeout
	check(absf(music.position - frozen) < 0.1, "device pause preserves position")
	music.toggle_pause()
	var old: String = music.current_id
	music.next_track(); await create_timer(0.3).timeout
	check(music.current_id != old and music.channels.filter(func(c): return c.player.playing).size() == 1 and music.channels[music.current_channel].gain == 1.0 and music.channels[music.current_channel].player.volume_db == 0.0, "hard cut stops old voice and immediately uses full track gain")
	music.next_track(); music.next_track()
	check(music.channels.filter(func(c): return c.player.playing).size() == 1, "rapid skipping immediately leaves one voice")
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), true)
	check(music.channels[music.current_channel].player.playing, "mute keeps music clock running")
	audio.preferences.music_muted = true; audio.apply_preferences()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("UI")), "music-only mute leaves UI audible")
	audio.preferences.music_muted = false; audio.apply_preferences()
	# Seek near the accepted ending to exercise automatic turnover on the audio device.
	old = music.current_id
	music.channels[music.current_channel].player.seek(float(music.tracks[old].duration) - 0.2)
	await create_timer(0.6).timeout
	check(music.current_id != old, "native end automatically advances queue")
	music.toggle_pause(); music.leave_title(); await create_timer(1.8).timeout
	check(music.channels.all(func(c): return not c.player.playing), "leaving paused title releases both voices")
	music.enter_title(); await create_timer(0.2).timeout
	check(music.title_paused and music.channels[music.current_channel].player.stream_paused, "return respects manual title pause")
	music.toggle_pause(); await create_timer(1.7).timeout
	record.set_recording_active(false)
	var wav := record.get_recording()
	check(wav != null and wav.get_length() > 5, "native mixed audio captured")
	if wav: wav.save_to_wav("res://reports/audio/title_runtime_20261001/device.wav")
	var report := {"checks": checks, "failures": failures, "driver": AudioServer.get_driver_name(), "stream_cache": music.streams.size(), "diagnostics": music.diagnostics}
	FileAccess.open("res://reports/audio/title_runtime_20261001/device.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	music.leave_title(); music._stop_channels()
	for channel in music.channels: channel.player.stream = null
	music.streams.clear()
	audio.preferences = previous; audio.apply_preferences()
	await process_frame
	print("MUSIC_DEVICE %d/%d passed: %s" % [checks - failures.size(), checks, failures])
	quit(0 if failures.is_empty() else 1)
