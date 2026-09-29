extends SceneTree
func _init(): call_deferred("run")
func summarize(values: Array) -> Dictionary:
	values.sort()
	var total := 0.0
	for value in values: total += float(value)
	return {"mean":total / max(1, values.size()), "p95":values[int(values.size() * 0.95)], "p99":values[int(values.size() * 0.99)]}
func run():
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920,1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
	viewport.add_child(battle)
	await process_frame
	battle.set_process(false)
	battle._start_battle("level.prototype_11v11")
	var snapshot: Dictionary = battle.session.snapshot("player", true)
	var waves := {}
	for i in range(32):
		var point := Vector2(1550 + (i % 8) * 100, 850 + int(i / 8) * 100)
		waves[str(i)] = {"wave_id":str(i), "source_unit_id":"", "character_id":"enterprise_cv6", "source_weapon_id":"weapon.enterprise_airstrike", "position":point, "target_position":point + Vector2(500,0), "progress":0.5, "phase":"Flying", "faction_id":"player", "remaining":2.0}
	snapshot.aviation = waves
	battle.battle_camera.position = Vector2(1950,1100)
	battle._update_hud()
	var results := {}
	var prior_cpu: Array = []
	var rid := viewport.get_viewport_rid()
	var timing := RenderingServer.has_method("viewport_set_measure_render_time")
	if timing: RenderingServer.call("viewport_set_measure_render_time",rid,true)
	for enabled in [false, true, false, true]:
		battle.effect_director.aviation_enabled = enabled
		var cpu: Array = []
		var frames: Array = []
		var gpu: Array = []
		var render_cpu: Array = []
		var memory: Array = []
		var total_cpu: Array = []
		var previous := Time.get_ticks_usec()
		for frame in range(150):
			snapshot.elapsed_time = frame * 0.016
			var start := Time.get_ticks_usec()
			battle.effect_director.sync_snapshot(snapshot,"","")
			var spent := float(Time.get_ticks_usec() - start) / 1000.0
			await process_frame
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			if frame >= 30:
				cpu.append(spent)
				frames.append(float(now - previous) / 1000.0)
				memory.append(float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0)
				if timing:
					gpu.append(RenderingServer.call("viewport_get_measured_render_time_gpu",rid))
					render_cpu.append(RenderingServer.call("viewport_get_measured_render_time_cpu",rid))
					total_cpu.append(spent + float(render_cpu.back()))
			previous = now
		var label := ("on" if enabled else "off") + str(results.size())
		results[label] = {"sync_cpu_ms":summarize(cpu), "frame_ms":summarize(frames), "memory_mb":summarize(memory), "active_flights":battle.effect_director.aviation_views.size(), "pooled_flights":battle.effect_director.aviation_pool.size()}
		if timing:
			results[label].merge({"gpu_ms":summarize(gpu) if gpu.max() > 0 else null, "render_cpu_ms":summarize(render_cpu), "total_cpu_ms":summarize(total_cpu.duplicate())})
			if enabled and prior_cpu.size() == total_cpu.size():
				var paired: Array = []
				for i in range(total_cpu.size()): paired.append(total_cpu[i] - prior_cpu[i])
				results[label].paired_cpu_increment_ms = summarize(paired)
			if not enabled: prior_cpu = total_cpu.duplicate()
	FileAccess.open("res://reports/aviation/20260929-runtime/performance.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	print("Aviation render pressure: ", JSON.stringify(results))
	battle.effect_director.clear()
	await process_frame
	assert(battle.effect_director.aviation_views.is_empty())
	quit()
