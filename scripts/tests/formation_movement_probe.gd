extends SceneTree

const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Session = preload("res://scripts/application/battle_session.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var registry = Registry.new()
	assert(registry.load_all())
	var results: Array = []
	for scenario in ["gather3", "gather11", "turn3", "harbor3", "follow2"]:
		results.append(probe(registry, scenario))
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(results, "\t"))
	var valid := true
	if "--baseline" not in OS.get_cmdline_user_args():
		for result in results:
			valid = valid and result.arrived == result.count and result.separation < 0.001 and result.events.is_empty()
		print("PASS: five formation transit scenarios" if valid else "FAIL: formation transit scenario")
	quit(0 if valid else 1)

func probe(registry, scenario: String) -> Dictionary:
	var session_type = load("res://artifacts/formation_movement_20260930/battle_session.before.gd") if "--baseline" in OS.get_cmdline_user_args() else Session
	var session = session_type.new(registry)
	session.create_battle("level.prototype_harbor_3v3" if scenario == "harbor3" else ("level.prototype_11v11" if scenario == "gather11" else "level.prototype_3v3"), 8412)
	session._full_ai_factions.clear()
	var moving: Array = []
	var ids: Array = []
	for id in session._sorted_unit_ids():
		var unit: Dictionary = session.state.units_by_id[id]
		if unit.faction_id != "player" or (scenario == "follow2" and moving.size() >= 2):
			unit.life_state = "Sunk"
			continue
		var index := moving.size()
		if scenario != "harbor3": unit.position = Vector2(1000 - (index / 3) * 220, 700 + (index % 3 - 1) * 220)
		if scenario == "follow2":
			unit.position = Vector2(600 + index * 260, 700)
			unit.stats = unit.stats.duplicate(true)
			unit.stats.speed = 60.0 if index == 0 else 20.0
		unit.heading = 0.0
		unit.current_speed = 0.0
		unit.movement_assist_enabled = false
		moving.append(unit)
		ids.append(id)
	var target := Vector2(1500, 600) if scenario != "harbor3" else Vector2(1300, 1728)
	var allocation_started := Time.get_ticks_usec()
	session._apply_command({"command_type":"MoveUnits", "issuer_id":"player", "unit_ids":ids, "target_position":target, "command_id":"probe.initial"})
	var allocation_usec := Time.get_ticks_usec() - allocation_started
	if scenario == "follow2":
		for index in range(moving.size()):
			session._apply_command({"command_type":"MoveUnits", "issuer_id":"player", "unit_id":ids[index], "target_position":Vector2(1600 + index * 260, 700), "command_id":"probe.follow.%d" % index})
	var expected := {}
	for unit in moving: expected[unit.entity_id] = unit.player_route_waypoints[-1] if not unit.player_route_waypoints.is_empty() else Vector2.INF
	var events := {}
	var cpu: Array = []
	var arrived := 0
	var settled_ticks := 0
	var paths := {}
	for id in ids: paths[id] = []
	for tick in range(2400):
		var started := Time.get_ticks_usec()
		session.state.tick_index += 1
		session.state.elapsed_time += 0.1
		if scenario == "turn3" and tick == 180:
			target = Vector2(1300, 1250)
			session._apply_command({"command_type":"MoveUnits", "issuer_id":"player", "unit_ids":ids, "target_position":target, "command_id":"probe.turn"})
			for unit in moving: expected[unit.entity_id] = unit.player_route_waypoints[-1] if not unit.player_route_waypoints.is_empty() else Vector2.INF
		session._update_navigation_requests()
		session._update_navigation_plans()
		session._update_movement(0.1)
		session._resolve_unit_overlap()
		for unit in moving: session._update_navigation_progress(unit, 0.1)
		cpu.append(Time.get_ticks_usec() - started)
		for event in session._event_buffer:
			var name := str(event.event_type)
			if name in ["UnitTerrainCollision", "NavigationCollisionContractViolated", "NavigationRecoveryStarted", "NavigationRequestFailed", "TrajectoryPlanFailed", "NavigationStalled", "NavigationSeparationApplied", "UnitTideAccessRestricted"]:
				events[name] = int(events.get(name, 0)) + 1
		session._event_buffer.clear()
		arrived = 0
		for unit in moving:
			if tick % 10 == 0: paths[unit.entity_id].append([snappedf(unit.position.x, 0.1), snappedf(unit.position.y, 0.1)])
			if unit.movement_state.mode == "HoldPosition" and unit.position.distance_to(expected[unit.entity_id]) <= session.trajectory_planner.arrival_tolerance(float(unit.stats.collision_radius)) + 0.1: arrived += 1
		settled_ticks = settled_ticks + 1 if arrived == moving.size() and (scenario != "turn3" or tick > 180) else 0
		if settled_ticks >= 20: break
	var separation := 0.0
	var endpoints := {}
	for unit in moving:
		separation += float(unit.navigation_state.get("separation_distance", 0.0))
		endpoints[unit.entity_id] = [expected[unit.entity_id].x, expected[unit.entity_id].y]
	var mean := 0.0
	for sample in cpu: mean += float(sample) / cpu.size()
	var common_mean := _mean_prefix(cpu, 200)
	cpu.sort()
	var result := {"scenario":scenario, "allocation_usec":allocation_usec, "arrived":arrived, "count":moving.size(), "seconds":snappedf(session.state.elapsed_time, 0.1), "separation":separation, "events":events, "cpu_mean_usec":mean, "cpu_first_200_mean_usec":common_mean, "cpu_p95_usec":cpu[int(cpu.size() * 0.95)], "endpoints":endpoints, "paths":paths}
	var summary := result.duplicate()
	summary.erase("paths")
	summary.erase("endpoints")
	print(JSON.stringify(summary))
	return result

func _mean_prefix(samples: Array, count: int) -> float:
	var total := 0.0
	for index in range(mini(count, samples.size())): total += float(samples[index])
	return total / maxf(1.0, mini(count, samples.size()))
