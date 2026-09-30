extends SceneTree

const Session = preload("res://scripts/application/battle_session.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var code := "l01"
	var output := "/tmp/challenge-battle-probe.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--code="): code = argument.trim_prefix("--code=")
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	var registry = root.get_node("DataRegistry").registry
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/simulations/experiments/level_%s_win_rate_20.json" % code))
	var session = Session.new(registry)
	assert(session.create_battle("level.challenge." + code, int(manifest.seed_plan.start)).get("ok", false))
	session.configure_full_ai_factions(["player", "enemy"])
	session.configure_ai_profile(manifest.ai_profile_id)
	session.configure_performance_profiling()
	var windows := {}
	var fires: Array = []
	while session.state.phase == "Running":
		var events: Array = session.advance_tick(0.1)
		for unit in session.state.units_by_id.values():
			if unit.life_state == "Sunk" or unit.stats.get("ship_class", "") != "Carrier": continue
			var condition := str(session.terrain_context_service.context_at(unit.position).get("aviation_condition", "Normal"))
			var id := str(unit.entity_id)
			if not windows.has(id): windows[id] = {"seconds_by_condition":{}, "intervals":[]}
			var entry: Dictionary = windows[id]
			entry.seconds_by_condition[condition] = float(entry.seconds_by_condition.get(condition, 0.0)) + 0.1
			var intervals: Array = entry.intervals
			if intervals.is_empty() or intervals[-1].condition != condition:
				intervals.append({"start":session.state.elapsed_time - 0.1, "end":session.state.elapsed_time, "condition":condition})
			else: intervals[-1].end = session.state.elapsed_time
		for event in events:
			if event.get("event_type") == "WeaponFired":
				var unit: Dictionary = session.state.units_by_id.get(str(event.get("unit_id", "")), {})
				if unit.get("stats", {}).get("ship_class") == "Carrier":
					fires.append({"time":session.state.elapsed_time, "event":event, "source_condition":session.terrain_context_service.context_at(unit.position).get("aviation_condition", "Normal")})
	var profile := {}
	for key in session.get_performance_profile():
		var samples: Array = session.get_performance_profile()[key]
		if samples.is_empty(): continue
		samples.sort()
		profile[key] = {"count":samples.size(), "mean":samples.reduce(func(a,b): return a+b, 0.0)/samples.size(), "p95":samples[mini(samples.size()-1, ceili(samples.size()*.95)-1)], "p99":samples[mini(samples.size()-1, ceili(samples.size()*.99)-1)], "max":samples[-1]}
	var report := {"code":code, "seed":manifest.seed_plan.start, "performance_units":"usec unless key ends in per_tick", "performance":profile, "carrier_source_weather_windows":windows, "carrier_weapon_fires":fires, "statistics":session.get_statistics(), "damage":session.get_all_unit_damage_statistics()}
	var file := FileAccess.open(output, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	print("CHALLENGE_PROBE ", code, " ", output)
	quit()
