extends SceneTree
const Music = preload("res://scripts/presentation/audio/music_manager.gd")
var checks := 0
var failures: Array[String] = []
func _init(): call_deferred("run")
func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message)
func run():
	var music = root.get_node("MusicManager")
	var old_path: String = music.preference_path
	var path := "user://music_modes_test.cfg"
	music.preference_path = path
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "Music", 0.3)
	cfg.set_value("menu", "cover_id", "untouched")
	cfg.save(path)
	music.load_playback_preferences()
	check(music.playback_mode == "shuffle", "old settings default to shuffle")
	music.enter_title(); music.advance(13); music.toggle_pause()
	var current: String = music.current_id
	var position: float = music.position
	check(music.save_playback_mode("sequence"), "sequence persists")
	check(music.current_id == current and music.position == position and music.title_paused, "mode change preserves song, position and pause")
	cfg.load(path)
	check(cfg.get_value("audio", "Music") == 0.3 and cfg.get_value("menu", "cover_id") == "untouched", "mode save preserves audio and menu")
	music.toggle_pause()
	var ids: Array = music.tracks.keys()
	var index := ids.find(current)
	for step in range(20):
		music.advance(float(music.tracks[music.current_id].duration))
		index = (index + 1) % ids.size()
		check(music.current_id == ids[index], "automatic sequence order wraps %d" % step)
	music.advance(7)
	var remaining: Array = music.queue.duplicate()
	check(music.save_playback_mode("single"), "single persists")
	check(music.queue == remaining and music.rotation_mode == "sequence", "single keeps sequence queue and return mode")
	var restart = Music.new()
	restart.preference_path = path
	root.add_child(restart)
	check(restart.playback_mode == "single" and restart.repeat_one and restart.rotation_mode == "sequence", "new manager restores single and underlying sequence")
	check(restart.current_id == "title_fleet_departure_v1", "persisted mode retains cold-start theme")
	restart.enter_title(); restart.advance(80)
	check(restart.current_id == "title_fleet_departure_v1", "persisted single loops on natural ending")
	restart.set_repeat(false)
	check(restart.playback_mode == "sequence", "footer toggle restores underlying sequence")
	restart.next_track()
	check(restart.current_id == ids[1], "restored sequence queue advances")
	restart.queue_free()
	check(music.save_playback_mode("shuffle"), "shuffle persists")
	check(not music.repeat_one and music.rotation_mode == "shuffle", "shuffle resumes rotation")
	var previous_mode: String = music.playback_mode
	check(not music.save_playback_mode("invalid") and music.playback_mode == previous_mode, "invalid mode rejected without mutation")
	cfg.set_value("music", "playback_mode", 123); cfg.set_value("music", "rotation_mode", "invalid"); cfg.save(path)
	music.load_playback_preferences()
	check(music.playback_mode == "shuffle", "malformed preferences safely fall back")
	check(not music.save_playback_mode("sequence", "user://missing-mode-parent/settings.cfg") and music.playback_mode == "sequence", "write failure retains session choice")
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu); menu._show_settings(); await process_frame
	var selector: OptionButton = menu.music_mode_selector
	check(selector.item_count == 3 and selector.get_item_metadata(selector.selected) == "sequence", "settings exposes three synchronized choices")
	var before_song: String = music.current_id
	selector.select(2); selector.item_selected.emit(2)
	check(music.repeat_one and menu.music_repeat.text == "循环：开" and menu.settings_status.text == "播放模式已保存", "settings choice updates footer and feedback")
	cfg.load(path)
	check(cfg.get_value("music", "playback_mode") == "single", "settings choice written to disk")
	menu.music_repeat.pressed.emit()
	check(music.playback_mode == "sequence" and selector.selected == 0, "footer change updates settings selection")
	cfg.load(path)
	check(cfg.get_value("music", "playback_mode") == "sequence", "footer change also persists")
	check(music.current_id == before_song, "both controls preserve current song")
	music.preference_path = "user://missing-mode-parent/settings.cfg"
	selector.select(1); selector.item_selected.emit(1)
	check(music.playback_mode == "shuffle" and menu.settings_status.text.contains("保存失败") and menu.music_label.text.contains("偏好未保存"), "settings reports save failure with mode applied")
	music.preference_path = path
	menu._show_home(); menu._show_settings()
	check(menu.music_mode_selector.selected == 1, "page recreation reflects current mode")
	menu.queue_free(); await process_frame
	music.preference_path = old_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures: push_error(failure)
	print("MUSIC_MODES %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
