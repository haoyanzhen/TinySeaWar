extends SceneTree
var failures: Array = []
var checks := 0
func _init(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value: failures.append(label)
func run():
	var audio = root.get_node("SoundManager")
	check(audio.device_enabled, "native audio device active")
	var previous: Dictionary = audio.preferences.duplicate()
	audio.preferences.muted=false
	audio.preferences.Master=0.8
	audio.apply_preferences()
	var recorder := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0,recorder)
	recorder.set_recording_active(true)
	audio.begin_battle(true)
	audio.listener_position=Vector2.ZERO
	var start := Time.get_ticks_usec()
	for id in audio.manifest.assets: check(audio.stream_for(id) is AudioStreamWAV,id+" native loads")
	var loading_ms := (Time.get_ticks_usec()-start)/1000.0
	audio.sync_loops({"sea":{"id":"E01","level":0.5},"wind":{"id":"E03a","level":0.4},"rain":{"id":"E04b","level":0.4},"coast":{"id":"E06","level":0.3},"wave1":{"id":"A02","position":Vector2(120,0),"level":0.25},"wave2":{"id":"A02","position":Vector2(-120,0),"level":0.25}})
	await create_timer(0.6).timeout
	check(audio.loops.size()==6,"four ambience plus two aircraft loops")
	var max_active := 0
	var play_times: Array = []
	for burst in range(6):
		var t := Time.get_ticks_usec()
		for i in range(36): audio.play("W01","ship.%d" % i,Vector2((i%5)*30,0),0)
		audio.play("W14","torpedo",Vector2.ZERO,0)
		audio.play("W14","torpedo2",Vector2.ZERO,0)
		audio.play("W14","torpedo3",Vector2.ZERO,0)
		audio.play("N06","flagship",Vector2.INF,0)
		audio.play("S04","submarine",Vector2.INF,0)
		play_times.append((Time.get_ticks_usec()-t)/1000.0)
		var active: int = audio.voices.filter(func(v): return v.player.playing).size()
		max_active=maxi(max_active,active)
		check(active<=32,"bounded short pool burst %d" % burst)
		check(audio.voices.any(func(v):return v.id=="N06" and v.player.playing),"critical alert retained burst %d" % burst)
		check(audio.voices.any(func(v):return v.id=="S04" and v.player.playing),"oxygen alert retained burst %d" % burst)
		await create_timer(0.35).timeout
	check(int(audio.counters.get("voice_limit",0))>0 and int(audio.counters.get("heavy_limit",0))>0,"dense voice and explosion limits exercised")
	audio.sync_loops({"rough":{"id":"E02b","level":0.5},"strong":{"id":"E03b","level":0.4},"rain2":{"id":"E04a","level":0.4},"coast":{"id":"E06","level":0.3}})
	check(audio.loops.size()<=6,"weather changes respect total loop capacity while fading")
	audio.paused=true
	await create_timer(0.6).timeout
	check(audio.loops.values().all(func(v):return v.player.bus=="Ambience" or v.player.stream_paused),"pause freezes aircraft")
	audio.paused=false
	audio.sync_loops({})
	await create_timer(0.7).timeout
	check(audio.loops.is_empty(),"loop fade releases players")
	recorder.set_recording_active(false)
	var recorded := recorder.get_recording()
	check(recorded != null and recorded.get_length()>3,"real mixed audio captured")
	if recorded != null: recorded.save_to_wav("res://reports/audio/runtime_20261001/dense_mix.wav")
	var summary := {"checks":checks,"failures":failures,"driver":AudioServer.get_driver_name(),"load_60_ms":loading_ms,"max_short_voices":max_active,"burst_schedule_ms":play_times,"counters":audio.counters.duplicate(),"stream_cache":audio.streams.size(),"recorded_seconds":recorded.get_length() if recorded else 0}
	FileAccess.open("res://reports/audio/runtime_20261001/device.json",FileAccess.WRITE).store_string(JSON.stringify(summary,"\t"))
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	audio.clear_battle()
	check(audio.voices.all(func(v):return not v.player.playing) and audio.loops.is_empty(),"scene cleanup stops every voice")
	audio.preferences=previous; audio.apply_preferences()
	summary.checks = checks; summary.failures = failures
	FileAccess.open("res://reports/audio/runtime_20261001/device.json",FileAccess.WRITE).store_string(JSON.stringify(summary,"\t"))
	print("SOUND_DEVICE checks=%d failures=%s" % [checks,failures])
	quit(0 if failures.is_empty() else 1)
