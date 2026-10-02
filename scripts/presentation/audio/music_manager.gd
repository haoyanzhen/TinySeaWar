extends Node
## Session music director. Private RNG and clock never touch battle state or random draws.
signal playback_changed
const SETTINGS_PATH := "user://tiny_sea_war_settings.cfg"
const PLAYBACK_MODES := ["sequence", "shuffle", "single"]
var preference_path := SETTINGS_PATH
var playback_mode := "shuffle"
var rotation_mode := "shuffle"
const MANIFEST_PATH := "res://data/audio/music_manifest.json"
var tracks: Dictionary = {}
var queue: Array[String] = []
var current_id := ""
var position := 0.0
var saved_position := 0.0
var title_active := false
var title_paused := false
var repeat_one := false
var scene_fade_seconds := 1.5
var rng := RandomNumberGenerator.new()
var streams: Dictionary = {}
var channels: Array = []
var current_channel := -1
var diagnostics: Array[String] = []
var device_enabled := false
var battle_tracks: Dictionary = {}
var battle_id := ""
var battle_position := 0.0
var battle_state := ""
var last_battle_id := ""
var transition_remaining := 0.0
var battle_paused := false
var duck_gain := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	var battle_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/audio/battle_music_manifest.json"))
	# Reuse the same resource contract without merging battle songs into the title queue.
	var title_data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	configure(battle_data)
	for id in tracks:
		if tracks[id].get("category", "") in ["battle", "victory", "defeat"]:
			battle_tracks[id] = tracks[id]
	configure(title_data)
	load_playback_preferences()
	device_enabled = DisplayServer.get_name() != "headless" and AudioServer.get_driver_name() != "Dummy"
	if device_enabled:
		for i in range(2):
			var player := AudioStreamPlayer.new()
			player.bus = "Music"
			add_child(player)
			player.finished.connect(_on_finished.bind(i))
			channels.append({"player": player, "gain": 0.0, "from": 0.0, "target": 0.0, "elapsed": 0.0, "duration": 0.0})
	set_process(device_enabled)

func configure(data) -> void:
	tracks.clear(); queue.clear(); current_id = ""; position = 0; streams.clear()
	if not data is Dictionary or data.get("schema_version", 0) != 1:
		_note("invalid_manifest"); return
	if not _number(data.get("scene_fade_seconds")) or float(data.scene_fade_seconds) <= 0 or float(data.scene_fade_seconds) > 10:
		_note("invalid_scene_fade_seconds"); return
	scene_fade_seconds = float(data.scene_fade_seconds)
	if not data.get("tracks") is Array:
		_note("invalid_tracks"); return
	for item in data.tracks:
		if not item is Dictionary: _note("invalid_track"); continue
		var id := str(item.get("id", ""))
		var path := str(item.get("path", ""))
		var duration = item.get("duration")
		var valid := not id.is_empty() and not tracks.has(id) and not str(item.get("title", "")).is_empty()
		valid = valid and path.begins_with("res://assets/audio/music/runtime/") and path.ends_with(".ogg") and not ".." in path and ResourceLoader.exists(path)
		valid = valid and _number(duration) and float(duration) > 0
		valid = valid and _number(item.get("loop_start")) and _number(item.get("loop_end"))
		if valid:
			valid = float(item.loop_start) >= 0 and float(item.loop_end) <= float(duration) + 0.1 and float(item.loop_end) > float(item.loop_start)
		valid = valid and item.get("resume_points") is Array
		if valid:
			var last := -1.0
			for point in item.resume_points:
				if not _number(point) or float(point) < 0 or float(point) <= last or float(point) >= float(duration): valid = false; break
				last = float(point)
		if not valid: _note("invalid_track:" + id); continue
		tracks[id] = item.duplicate(true)
	var main := str(data.get("main_theme_id", ""))
	if tracks.has(main):
		current_id = main
		_refill(main, true)
	else:
		_refill("")
		if not queue.is_empty(): current_id = queue.pop_front()

func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _note(message: String) -> void:
	if message not in diagnostics: diagnostics.append(message)

func _refill(exclude: String, cold_start := false) -> void:
	var pool: Array[String] = []
	for id in tracks: pool.append(id)
	pool = _order_rotation(pool, exclude)
	# On cold start the theme already belongs to this round; on later rounds only
	# prevent adjacency, keeping every song in the new round.
	if cold_start:
		pool.erase(exclude)
	elif pool.size() > 1 and pool[0] == exclude:
		var value := pool[0]; pool[0] = pool[1]; pool[1] = value
	queue.assign(pool)

func _next_id() -> String:
	if tracks.is_empty(): return ""
	if queue.is_empty():
		_refill(current_id)
	return queue.pop_front() if not queue.is_empty() else current_id

func enter_title() -> void:
	if title_active: return
	leave_battle()
	title_active = true
	if saved_position > 0 and tracks.has(current_id):
		var resume := -1.0
		for point in tracks[current_id].resume_points:
			if float(point) <= saved_position: resume = float(point)
		if resume >= 0 and saved_position < float(tracks[current_id].duration) - scene_fade_seconds:
			position = resume
		else:
			current_id = _next_id(); position = 0
		saved_position = 0
	_stop_channels()
	_start(current_id, position, scene_fade_seconds)
	playback_changed.emit()

func leave_title() -> void:
	if not title_active: return
	saved_position = position
	title_active = false
	for channel in channels: _fade(channel, 0, scene_fade_seconds)
	playback_changed.emit()

func toggle_pause() -> void:
	title_paused = not title_paused
	for channel in channels:
		if title_active: channel.player.stream_paused = title_paused
	playback_changed.emit()

func _order_rotation(pool: Array[String], after: String) -> Array[String]:
	if rotation_mode == "sequence":
		var ordered: Array[String] = []
		var ids: Array = tracks.keys()
		var start := ids.find(after)
		for offset in range(1, ids.size() + 1):
			var id: String = ids[posmod(start + offset, ids.size())]
			if id in pool: ordered.append(id)
		return ordered
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var value := pool[i]; pool[i] = pool[j]; pool[j] = value
	return pool

func set_playback_mode(mode: String) -> bool:
	if mode not in PLAYBACK_MODES: return false
	if mode != "single" and mode != rotation_mode:
		rotation_mode = mode
		queue = _order_rotation(queue, current_id)
	playback_mode = mode
	repeat_one = mode == "single"
	playback_changed.emit()
	return true

func set_repeat(value: bool) -> void:
	set_playback_mode("single" if value else rotation_mode)

func load_playback_preferences(path: String = "") -> void:
	var config := ConfigFile.new()
	var loaded := config.load(preference_path if path.is_empty() else path)
	var mode = config.get_value("music", "playback_mode", "shuffle") if loaded == OK else "shuffle"
	var rotation = config.get_value("music", "rotation_mode", "shuffle") if loaded == OK else "shuffle"
	set_playback_mode(rotation if rotation is String and rotation in ["sequence", "shuffle"] else "shuffle")
	set_playback_mode(mode if mode is String and mode in PLAYBACK_MODES else "shuffle")

func save_playback_mode(mode: String, path: String = "") -> bool:
	if not set_playback_mode(mode): return false
	var config := ConfigFile.new()
	var destination := preference_path if path.is_empty() else path
	var error := config.load(destination)
	if error != OK and error != ERR_FILE_NOT_FOUND: return false
	config.set_value("music", "playback_mode", playback_mode)
	config.set_value("music", "rotation_mode", rotation_mode)
	return config.save(destination) == OK

func next_track() -> void:
	if not title_active or tracks.is_empty(): return
	current_id = _next_id(); position = 0
	_start(current_id, 0, 0)
	playback_changed.emit()

func _stream(id: String):
	if streams.has(id): return streams[id]
	var track: Dictionary = tracks.get(id, battle_tracks.get(id, {}))
	if track.is_empty(): return null
	var resource = load(track.path)
	if not resource is AudioStreamOggVorbis or absf(resource.get_length() - float(track.duration)) > 0.1:
		_note("invalid_stream:" + id); return null
	resource = resource.duplicate()
	resource.loop = false
	streams[id] = resource
	return resource

func _start(id: String, offset: float, fade: float) -> void:
	if id.is_empty() or not device_enabled: return
	# Try each remaining candidate at most once; corrupt files never trap a page.
	for attempt in range(maxi(1, tracks.size() * 2)):
		var stream = _stream(id)
		if stream != null:
			if fade <= 0: _stop_channels()
			var index := 0 if current_channel < 0 else 1 - current_channel
			var channel: Dictionary = channels[index]
			channel.player.stop()
			channel.player.stream = stream
			channel.gain = 1.0 if fade <= 0 else 0.0
			channel.player.volume_db = 0.0 if fade <= 0 else -80.0
			channel.player.play(offset)
			channel.player.stream_paused = title_paused and title_active
			if current_channel >= 0: _fade(channels[current_channel], 0, fade)
			current_channel = index
			_fade(channel, 1, fade)
			return
		if not title_active: return
		id = _next_id(); current_id = id; position = 0; offset = 0
	_stop_channels()
	current_id = ""

func _fade(channel: Dictionary, target: float, seconds: float) -> void:
	channel.from = channel.gain; channel.target = target
	channel.elapsed = 0.0; channel.duration = seconds

func _stop_channels() -> void:
	for channel in channels:
		channel.player.stop(); channel.gain = 0.0; channel.target = 0.0
	current_channel = -1

func _on_finished(index: int) -> void:
	if not battle_state.is_empty() and transition_remaining <= 0 and index == current_channel: _battle_song_ended()
	if title_active and not title_paused and index == current_channel: _song_ended()

func _song_ended() -> void:
	if repeat_one:
		position = float(tracks[current_id].loop_start)
		_start(current_id, position, 0)
	else: next_track()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	_advance_battle(delta)
	if title_active and not title_paused and tracks.has(current_id):
		if device_enabled and current_channel >= 0:
			position = channels[current_channel].player.get_playback_position()
		else: position += delta
		var end := float(tracks[current_id].loop_end if repeat_one else tracks[current_id].duration)
		if position >= end: _song_ended()
	for channel in channels:
		# Title pause freezes playback; scene exit still releases the voice.
		if title_paused and title_active: continue
		channel.elapsed = minf(channel.duration, channel.elapsed + delta)
		var weight: float = 1.0 if channel.duration <= 0 else channel.elapsed / channel.duration
		channel.gain = lerpf(channel.from, channel.target, weight)
		channel.player.volume_db = linear_to_db(maxf(0.0001, channel.gain * (duck_gain if not battle_state.is_empty() else 1.0)))
		if channel.target == 0 and weight >= 1: channel.player.stop()

func playback_state() -> Dictionary:
	return {"id": current_id, "title": str(tracks.get(current_id, {}).get("title", "音乐暂不可用")),
		"mode": playback_mode, "paused": title_paused, "repeat": repeat_one, "active": title_active, "position": position}


func _exit_tree() -> void:
	_stop_channels()
	for channel in channels: channel.player.stream = null
	streams.clear()

func enter_battle(level_id: String) -> void:
	leave_title()
	battle_paused = false
	duck_gain = 1.0
	var pool: Array[String] = []
	for id in battle_tracks:
		if battle_tracks[id].category == "battle" and id != "battle_finale_distant_decisive_v1" and _battle_available(id): pool.append(id)
	var preferred: Array[String] = []
	if level_id == "level.challenge.l05":
		preferred.assign(["battle_finale_distant_decisive_v1"])
	elif level_id.begins_with("level.tutorial."):
		preferred.assign(["battle_watchful_route_v1", "battle_gentle_companions_v1"])
	preferred = preferred.filter(func(id): return _battle_available(id))
	if not preferred.is_empty(): pool = preferred
	if pool.size() > 1: pool.erase(last_battle_id)
	var id := pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else ""
	last_battle_id = id
	_transition_battle("battle", id, scene_fade_seconds)

func sync_battle(phase: String, result: Dictionary) -> void:
	battle_paused = phase == "Paused"
	if result.is_empty() or battle_state != "battle": return
	var kind: String = preload("res://scripts/presentation/battle/battle_result_presentation.gd").describe(result).get("kind", "Invalid")
	var category := kind.to_lower()
	var id := ""
	for candidate in battle_tracks:
		if battle_tracks[candidate].category == category and _battle_available(candidate): id = candidate; break
	_transition_battle("result", id, 0.75)

func _transition_battle(state: String, id: String, seconds: float) -> void:
	battle_state = state
	battle_id = id
	battle_position = 0.0
	transition_remaining = seconds
	for channel in channels:
		channel.player.stream_paused = false
		_fade(channel, 0, seconds)

func leave_battle() -> void:
	if battle_state.is_empty(): return
	battle_state = ""
	battle_id = ""
	transition_remaining = 0.0
	_stop_channels()

func _advance_battle(delta: float) -> void:
	if battle_state.is_empty(): return
	duck_gain = move_toward(duck_gain, 0.35 if battle_paused and battle_state == "battle" else 1.0, delta * 1.3)
	if transition_remaining > 0:
		transition_remaining = maxf(0, transition_remaining - delta)
		if transition_remaining <= 0:
			_stop_channels()
			_start(battle_id, 0, scene_fade_seconds)
		return
	if battle_id.is_empty(): return
	if device_enabled and current_channel >= 0:
		battle_position = channels[current_channel].player.get_playback_position()
	else: battle_position += delta
	if battle_position >= float(battle_tracks[battle_id].duration): _battle_song_ended()

func _battle_song_ended() -> void:
	if battle_id.is_empty(): return
	if battle_state == "battle":
		battle_position = float(battle_tracks[battle_id].loop_start)
		_start(battle_id, battle_position, 0)
	else:
		# No accepted aftermath loop markers yet: never repeat the result fanfare.
		battle_id = ""
		_stop_channels()

func _battle_available(id: String) -> bool:
	return battle_tracks.has(id) and (not device_enabled or _stream(id) != null)
