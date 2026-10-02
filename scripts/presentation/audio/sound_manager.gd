extends Node
## Presentation-only pool. No session access and no combat RNG; headless records scheduling only.
const MANIFEST_PATH := "res://data/audio/sfx_manifest.json"
const SETTINGS_PATH := "user://tiny_sea_war_settings.cfg"
var manifest: Dictionary = {}
var preferences := {"Master": 0.8, "Music": 0.7, "Combat": 0.7, "Alerts": 0.8, "UI": 0.7, "Ambience": 0.5, "muted": false, "music_muted": false, "frequent_ui": true}
var streams: Dictionary = {}
var voices: Array = []
var loops: Dictionary = {}
var desired_loops: Dictionary = {}
var log_entries: Array = []
var counters: Dictionary = {}
var cooldowns: Dictionary = {}
var missing: Dictionary = {}
var enabled := true
var device_enabled := false
var session_token := 0
var dense := false
var paused := false
var listener_position := Vector2.ZERO
var selected_id := ""
var duck_until := 0.0
var duck_gain := 0.0
var heavy_ids: Array = ["W03", "W04", "W13b", "W14", "W15a", "W19"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if parsed is Dictionary and parsed.get("schema_version", 0) == 1: manifest = parsed
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for key in preferences:
			var value = cfg.get_value("audio", key, preferences[key])
			if typeof(preferences[key]) == TYPE_BOOL: preferences[key] = bool(value)
			elif value is float or value is int: preferences[key] = clampf(float(value), 0, 1) if is_finite(float(value)) else preferences[key]
	device_enabled = DisplayServer.get_name() != "headless" and AudioServer.get_driver_name() != "Dummy"
	if not device_enabled: return
	for bus in ["Music", "Combat", "Alerts", "UI", "Ambience"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	var limiter := AudioEffectLimiter.new()
	limiter.ceiling_db = -1.0
	AudioServer.add_bus_effect(0, limiter)
	for i in range(int(mix("short_voices", 32))):
		var player := AudioStreamPlayer2D.new()
		player.max_distance = 10000000
		player.attenuation = 0
		add_child(player)
		voices.append({"player":player, "priority":-1, "id":"", "started":0.0})
	apply_preferences()

func mix(key: String, fallback): return manifest.get("mix", {}).get(key, fallback)

func save_preference(key: String, value, path: String = SETTINGS_PATH) -> bool:
	if not preferences.has(key): return false
	preferences[key] = bool(value) if typeof(preferences[key]) == TYPE_BOOL else clampf(float(value), 0, 1)
	apply_preferences()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK and err != ERR_FILE_NOT_FOUND: return false
	for field in preferences: cfg.set_value("audio", field, preferences[field])
	return cfg.save(path) == OK

func apply_preferences() -> void:
	if not device_enabled: return
	for bus in ["Master", "Music", "Combat", "Alerts", "UI", "Ambience"]:
		var index := AudioServer.get_bus_index(bus)
		if index < 0: continue
		AudioServer.set_bus_mute(index, bool(preferences.muted) or (bus == "Music" and bool(preferences.music_muted)) or float(preferences[bus]) <= 0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, float(preferences[bus]))))

func now() -> float: return Time.get_ticks_msec() / 1000.0

func record(id: String, reason: String, owner: String = "") -> void:
	counters[reason] = int(counters.get(reason, 0)) + 1
	log_entries.append({"session":session_token, "id":id, "reason":reason, "owner":owner})
	if log_entries.size() > 512: log_entries.pop_front()

func begin_battle(large: bool) -> void:
	clear_battle()
	session_token += 1
	dense = large
	cooldowns.clear()
	counters.clear()
	log_entries.clear()

func clear_battle(preserve_ui: bool = true) -> void:
	for voice in voices:
		if preserve_ui and voice.player.bus == "UI": continue
		voice.player.stop()
		voice.priority = -1
	for key in loops.keys():
		loops[key].player.stop()
		loops[key].player.queue_free()
	loops.clear()
	desired_loops.clear()
	paused = false
	duck_gain = 0
	duck_until = 0
	dense = false

func stream_for(id: String):
	if streams.has(id): return streams[id]
	var asset: Dictionary = manifest.get("assets", {}).get(id, {})
	var path := str(asset.get("path", ""))
	if not path.begins_with("res://assets/audio/sfx/runtime/") or not ResourceLoader.exists(path):
		if not missing.has(id): record(id, "missing_resource"); missing[id] = true
		return null
	var resource = load(path)
	if not resource is AudioStreamWAV:
		if not missing.has(id): record(id, "invalid_resource"); missing[id] = true
		return null
	if bool(asset.get("loop", false)):
		resource = resource.duplicate()
		resource.loop_mode = AudioStreamWAV.LOOP_FORWARD
		resource.loop_begin = 0
		resource.loop_end = roundi(resource.get_length() * resource.mix_rate)
	streams[id] = resource
	return resource

func play(id: String, owner: String = "", position: Vector2 = Vector2.INF, cooldown: float = -1.0, priority_override: int = -1) -> bool:
	var asset: Dictionary = manifest.get("assets", {}).get(id, {})
	if asset.is_empty(): record(id, "not_adopted", owner); return false
	var bus := str(asset.bus)
	if not enabled or bool(preferences.muted) or float(preferences.Master) <= 0 or float(preferences.get(bus, 0)) <= 0:
		record(id, "muted", owner); return false
	if not bool(preferences.frequent_ui) and bus == "UI" and id != "U05a": record(id, "ui_disabled", owner); return false
	if paused and bus not in ["UI", "Alerts"]: record(id, "paused", owner); return false
	var t := now()
	var key := id + ":" + owner
	var interval := cooldown if cooldown >= 0 else float(mix("dense_aggregate_seconds" if dense else "aggregate_seconds", 0.25))
	if t < float(cooldowns.get(key, -1)): record(id, "merged", owner); return false
	var spatial := not position.is_equal_approx(Vector2.INF)
	var range_limit := float(mix("dense_max_distance" if dense else "max_distance", 1800))
	var distance := position.distance_to(listener_position) if spatial else 0.0
	if spatial and distance > range_limit: record(id, "distant", owner); return false
	var priority := int(asset.priority) if priority_override < 0 else priority_override
	if owner == selected_id: priority += 10
	cooldowns[key] = t + interval
	if not device_enabled:
		record(id, "selected", owner); return true
	var stream = stream_for(id)
	if stream == null: return false
	var reserve := int(mix("reserved_alert_voices", 4))
	var start := 0 if bus in ["Alerts", "UI"] else reserve
	var chosen: Dictionary = {}
	var heavy_count := 0
	for voice in voices:
		if voice.player.playing and voice.id in heavy_ids: heavy_count += 1
	if id in heavy_ids and heavy_count >= int(mix("heavy_voices", 2)): record(id, "heavy_limit", owner); return false
	for i in range(start, voices.size()):
		var voice: Dictionary = voices[i]
		if not voice.player.playing: chosen = voice; break
		if int(voice.priority) < priority and (chosen.is_empty() or int(voice.priority) < int(chosen.priority)): chosen = voice
	if chosen.is_empty(): record(id, "voice_limit", owner); return false
	if chosen.player.playing: record(str(chosen.id), "preempted", owner); chosen.player.stop()
	chosen.id = id
	chosen.priority = priority
	chosen.started = t
	chosen.player.stream = stream
	chosen.player.bus = bus
	chosen.player.global_position = position if spatial else listener_position
	chosen.player.panning_strength = 1.0 if spatial else 0.0
	chosen.player.volume_db = float(asset.gain_db) + (linear_to_db(maxf(0.01, 1.0 - distance / range_limit)) if spatial else 0.0)
	chosen.player.play()
	if priority >= 90: duck_until = t + float(mix("duck_seconds", 1.5))
	record(id, "selected", owner)
	return true

func ui(id: String) -> void: play(id, "local", Vector2.INF, 0.12)

func sync_loops(desired: Dictionary) -> void:
	desired_loops = desired.duplicate(true)
	for key in loops:
		loops[key].target = 0.0
	for key in desired:
		var item: Dictionary = desired[key]
		var id := str(item.id)
		if not manifest.get("assets", {}).has(id) or not bool(manifest.assets[id].loop): continue
		if not loops.has(key):
			if not device_enabled: continue
			var stream = stream_for(id)
			if stream == null: continue
			var bus := str(manifest.assets[id].bus)
			var count := 0
			var retiring := ""
			for existing in loops:
				if loops[existing].player.bus != bus: continue
				count += 1
				if loops[existing].target == 0: retiring = str(existing)
			var capacity := int(mix("ambience_loops" if bus == "Ambience" else "aircraft_loops", 4))
			if count >= capacity:
				if retiring.is_empty(): record(id, "loop_limit", str(key)); continue
				loops[retiring].player.stop(); loops[retiring].player.queue_free(); loops.erase(retiring)
			var player := AudioStreamPlayer2D.new()
			player.stream = stream
			player.bus = str(manifest.assets[id].bus)
			player.max_distance = 10000000
			player.attenuation = 0
			player.volume_db = -80
			add_child(player)
			player.play()
			loops[key] = {"player":player, "id":id, "level":0.0, "target":0.0}
		loops[key].target = float(item.get("level", 1.0)) if enabled else 0.0
		loops[key].player.global_position = item.get("position", listener_position)
		loops[key].player.panning_strength = 1.0 if item.has("position") else 0.0

func _process(delta: float) -> void:
	if not device_enabled: return
	var ducked := now() < duck_until
	var duck_target := float(mix("duck_db", -8)) if ducked else 0.0
	var duck_duration := float(mix("duck_attack_seconds" if ducked else "duck_release_seconds", 0.15 if ducked else 0.5))
	duck_gain = move_toward(duck_gain, duck_target, delta * absf(float(mix("duck_db", -8))) / maxf(0.01, duck_duration))
	for bus in ["Ambience", "Music"]:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), linear_to_db(maxf(0.0001, float(preferences[bus]))) + duck_gain)
	for key in loops.keys():
		var item: Dictionary = loops[key]
		item.player.stream_paused = paused and item.player.bus == "Combat"
		item.level = move_toward(float(item.level), float(item.target), delta / float(mix("loop_fade_seconds", 0.5)))
		item.player.volume_db = float(manifest.assets[item.id].gain_db) + linear_to_db(maxf(0.0001, float(item.level))) + (-12.0 if paused and item.player.bus == "Ambience" else 0.0)
		if item.target == 0 and item.level <= 0:
			item.player.stop(); item.player.queue_free(); loops.erase(key)
