extends SceneTree
const Music = preload("res://scripts/presentation/audio/music_manager.gd")
var checks := 0
var failures: Array[String] = []
func _init(): call_deferred("run")
func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message)
func run():
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Music.MANIFEST_PATH))
	var music = root.get_node("MusicManager")
	var previous_path: String = music.preference_path
	music.preference_path = "user://music_runtime_settings_test.cfg"
	music.set_playback_mode("shuffle")
	check(music.tracks.size() == 5 and music.diagnostics.is_empty(), "five valid runtime tracks")
	check(music.current_id == data.main_theme_id, "cold start prefers theme")
	check(music.channels.is_empty() and music.streams.is_empty(), "headless has no audio players or stream loading")
	for id in music.tracks:
		var track: Dictionary = music.tracks[id]
		var resource = load(track.path)
		check(resource is AudioStreamOggVorbis and absf(resource.get_length() - float(track.duration)) < 0.1, "engine decodes " + id)
		check(FileAccess.get_sha256(track.path) == track.sha256, "encoded hash " + id)
		check(FileAccess.get_sha256("res://assets/audio/music/source/" + id + "/source.wav") == track.source_sha256, "source preserved " + id)
	music.enter_title()
	var start_id: String = music.current_id
	var length: float = music.tracks[start_id].duration
	music.advance(length - 0.1)
	check(music.current_id == start_id, "natural rotation plays full song without early fade")
	music.advance(0.1)
	check(music.current_id != start_id and music.position == 0, "rotation cuts at full song end")
	# Restore a fresh first round for the existing ten-round queue acceptance.
	music.configure(data)
	for round_index in range(10):
		var seen: Array[String] = []
		for index in range(5):
			check(music.current_id not in seen, "no repeated song in round %d" % round_index)
			seen.append(music.current_id)
			var previous: String = music.current_id
			music.next_track()
			check(music.current_id != previous, "adjacent rounds do not repeat")
	music.advance(12)
	var frozen: float = music.position
	music.toggle_pause(); music.advance(90)
	check(music.position == frozen, "manual pause freezes title clock")
	music.next_track()
	check(music.title_paused and music.position == 0, "next song preserves pause")
	music.toggle_pause(); music.set_repeat(true)
	var repeated: String = music.current_id
	var remaining: Array = music.queue.duplicate()
	for cycle in range(3):
		music.advance(float(music.tracks[repeated].duration))
		check(music.current_id == repeated and music.queue == remaining, "single repeat preserves queue")
	music.set_repeat(false); music.advance(float(music.tracks[repeated].duration))
	check(music.current_id != repeated, "disabling repeat continues existing queue")
	music.advance(20); music.leave_title()
	var exit_id: String = music.current_id
	var exit_position: float = music.position
	music.advance(200)
	check(not music.title_active and music.position == exit_position, "battle suspension freezes playlist")
	music.enter_title()
	check(music.current_id != exit_id and music.position == 0, "unmarked phrase resumes next queued song")
	var marked: String = music.current_id
	music.tracks[marked].resume_points = [0.0, 8.0, 16.0]
	music.advance(19); music.leave_title(); music.enter_title()
	check(music.current_id == marked and music.position == 16, "verified phrase marker resumes same song")
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu); await process_frame
	var menu_id: String = music.current_id
	var menu_queue: Array = music.queue.duplicate()
	for action in ["_show_tutorial", "_show_challenge", "_show_custom", "_show_help", "_show_settings", "_show_home"]:
		menu.call(action)
		check(music.current_id == menu_id and music.queue == menu_queue, "page continuity " + action)
	menu._switch_cover(1, false); menu.set_viewing(true); menu.set_viewing(false)
	check(music.current_id == menu_id, "cover/view continuity")
	menu.music_pause.pressed.emit()
	check(music.title_paused and menu.music_pause.text == "播放", "pause control updates label")
	menu.music_next.pressed.emit()
	check(music.current_id != menu_id and music.title_paused, "next control keeps pause")
	menu.music_repeat.pressed.emit()
	check(music.repeat_one and menu.music_repeat.text == "循环：开", "repeat control updates label")
	menu._show_settings()
	check(menu.find_child("AudioMusic", true, false) is HSlider, "music volume setting exists")
	menu.queue_free(); await process_frame
	check(not music.title_active, "scene cleanup suspends title")
	var local = Music.new(); root.add_child(local)
	var broken: Dictionary = data.duplicate(true)
	broken.tracks[0].path = "res://assets/audio/music/runtime/missing.ogg"
	broken.tracks[1].duration = -1
	broken.tracks[2].resume_points = [40, 20]
	broken.tracks[3].loop_end = INF
	local.configure(broken)
	check(local.tracks.size() == 1, "bad path, duration, markers and loop skipped")
	local.enter_title(); local.advance(100)
	check(local.current_id == broken.tracks[4].id, "one usable song repeats")
	local.configure({"schema_version": 2}); local.enter_title(); local.advance(100)
	check(local.current_id.is_empty(), "exhausted manifest remains quiet")
	local.configure(data)
	local.title_active = false
	# Dummy driver verifies the actual player handoff; it makes no claim about sound output.
	for i in range(2):
		var player := AudioStreamPlayer.new()
		local.add_child(player)
		local.channels.append({"player":player, "gain":0.0, "from":0.0, "target":0.0, "elapsed":0.0, "duration":0.0})
	local.device_enabled = true
	local.enter_title()
	local.next_track()
	check(local.channels.filter(func(c): return c.player.playing).size() == 1, "hard cut stops prior player immediately")
	check(local.channels[local.current_channel].gain == 1 and local.channels[local.current_channel].player.volume_db == 0, "new song starts at full track gain without fade")
	local.toggle_pause(); local.next_track()
	check(local.channels[local.current_channel].player.stream_paused and local.channels[local.current_channel].gain == 1, "paused hard cut prepares full gain but remains paused")
	local.toggle_pause(); local.set_repeat(true)
	var loop_id: String = local.current_id
	local._song_ended()
	check(local.current_id == loop_id and local.channels.filter(func(c): return c.player.playing).size() == 1 and local.channels[local.current_channel].gain == 1, "single repeat hard cuts without overlapping voices")
	local.queue_free()
	# Music uses its own RNG, never the global draws used by other systems.
	seed(9021); var expected := randi(); seed(9021)
	music.rng.randomize(); music.configure(data); music.enter_title()
	for index in range(12): music.next_track()
	check(randi() == expected, "playlist RNG isolated")
	var audio = root.get_node("SoundManager")
	var previous: Dictionary = audio.preferences.duplicate()
	var config := ConfigFile.new(); config.set_value("menu", "cover_id", "test-preserved")
	config.save("user://music_settings_test.cfg")
	check(audio.save_preference("Music", 0.35, "user://music_settings_test.cfg"), "music volume persists")
	check(audio.save_preference("music_muted", true, "user://music_settings_test.cfg"), "independent mute persists")
	config.load("user://music_settings_test.cfg")
	check(config.get_value("menu", "cover_id") == "test-preserved" and config.get_value("audio", "music_muted"), "saving preserves other settings")
	check(not audio.save_preference("Music", 0.4, "user://missing-parent/settings.cfg") and audio.preferences.Music == 0.4, "save failure retains session volume")
	audio.preferences = previous; audio.apply_preferences()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://music_settings_test.cfg"))
	music.preference_path = previous_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://music_runtime_settings_test.cfg"))
	for failure in failures: push_error(failure)
	print("MUSIC_RUNTIME %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
