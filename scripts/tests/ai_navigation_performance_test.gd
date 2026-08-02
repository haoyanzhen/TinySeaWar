extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	var registry = ConfigRegistry.new()
	if not registry.load_all():
		push_error("Unable to load configuration registry")
		quit(1)
		return
	var effective_level_id := str(options["level"])
	if not str(options["map_level"]).is_empty():
		effective_level_id = _install_map_variant(registry, effective_level_id, str(options["map_level"]))
		if effective_level_id.is_empty():
			push_error("Unable to configure mapped performance battle")
			quit(1)
			return
	var session = BattleSession.new(registry)
	var creation := session.create_battle(effective_level_id, int(options["seed"]))
	if not bool(creation.get("ok", false)):
		push_error("Unable to create battle: %s" % creation.get("errors", []))
		quit(1)
		return
	session.configure_full_ai_factions(["player", "enemy"])
	session.route_planner.configure_runtime_parameters(float(options["gate_spacing"]), int(options["attachment_limit"]))
	session.configure_performance_profiling(true)
	var requested_ticks: int = int(options["ticks"])
	var executed_ticks := 0
	var route_samples: Array = []
	var route_failure_samples: Array = []
	var route_projection_samples: Array = []
	var event_counts := {"terrain_collisions":0, "route_failures":0, "projected_routes":0, "trajectory_failures":0}
	var route_waypoint_total := 0
	var route_completions := 0
	var astar_usec_samples: Array = []
	var astar_expansion_samples: Array = []
	while executed_ticks < requested_ticks and session.state.get("phase", "") == "Running":
		for event in session.advance_tick(0.1):
			if str(event.get("event_type", "")) in ["NavigationRequestCompleted", "NavigationRequestFailed"]:
				route_samples.append({"event_type":event.get("event_type", ""), "unit_id":event.get("unit_id", ""), "command_id":event.get("command_id", ""), "start":str(event.get("start", Vector2.ZERO)), "target":str(event.get("target", Vector2.ZERO)), "elapsed_usec":event.get("elapsed_usec", 0), "route_profile":event.get("route_profile", {})})
			if str(event.get("event_type", "")) == "NavigationRequestCompleted":
				route_completions += 1
				route_waypoint_total += int(event.get("waypoint_count", 0))
				astar_usec_samples.append(int(event.get("route_profile", {}).get("astar_usec", 0)))
				astar_expansion_samples.append(int(event.get("route_profile", {}).get("astar_expansions", 0)))
				if bool(event.get("target_projected", false)):
					event_counts["projected_routes"] += 1
					route_projection_samples.append({"unit_id":event.get("unit_id", ""), "target":str(event.get("target", Vector2.ZERO)), "resolved_target":str(event.get("resolved_target", Vector2.ZERO)), "route_profile":event.get("route_profile", {})})
			elif str(event.get("event_type", "")) == "NavigationRequestFailed":
				event_counts["route_failures"] += 1
				route_failure_samples.append({"unit_id":event.get("unit_id", ""), "reason_code":event.get("reason_code", ""), "start":str(event.get("start", Vector2.ZERO)), "target":str(event.get("target", Vector2.ZERO)), "route_profile":event.get("route_profile", {})})
			elif str(event.get("event_type", "")) == "UnitTerrainCollision": event_counts["terrain_collisions"] += 1
			elif str(event.get("event_type", "")) == "TrajectoryPlanFailed": event_counts["trajectory_failures"] += 1
		executed_ticks += 1
	route_samples.sort_custom(func(a, b): return int(a.get("elapsed_usec", 0)) > int(b.get("elapsed_usec", 0)))
	if route_samples.size() > 8: route_samples.resize(8)
	var profile := session.get_performance_profile()
	var result := {
		"level": effective_level_id,
		"source_level": options["level"],
		"map_level": options["map_level"],
		"seed": options["seed"],
		"requested_ticks": requested_ticks,
		"executed_ticks": executed_ticks,
		"unit_count": session.state.get("units_by_id", {}).size(),
		"gate_spacing": options["gate_spacing"],
		"attachment_limit": options["attachment_limit"],
		"event_counts": event_counts,
		"average_route_waypoints": snappedf(float(route_waypoint_total) / maxf(1.0, float(route_completions)), 0.01),
		"astar_ms": _timing_summary(astar_usec_samples),
		"astar_expansions": _count_distribution(astar_expansion_samples),
		"waiting_units": session.state.get("units_by_id", {}).values().filter(func(unit): return bool(unit.get("navigation_state", {}).get("route_waiting", false))).size(),
		"phase": session.state.get("phase", ""),
		"tick_ms": _timing_summary(profile.get("tick_total_usec", [])),
		"navigation_ms": _timing_summary(profile.get("navigation_usec", [])),
		"movement_ms": _timing_summary(profile.get("movement_usec", [])),
		"ai_decision_ms": _timing_summary(profile.get("ai_decision_usec", [])),
		"normal_plans": _count_summary(profile.get("normal_plans_per_tick", [])),
		"emergency_scans": _count_summary(profile.get("emergency_scans_per_tick", [])),
		"emergency_plans": _count_summary(profile.get("emergency_plans_per_tick", [])),
		"strategic_corridors": _count_summary(profile.get("strategic_corridors_per_tick", [])),
		"trajectory_candidates": _count_summary(profile.get("trajectory_candidates_per_tick", [])),
		"trajectory_failures": _count_summary(profile.get("trajectory_failures_per_tick", [])),
		"slowest_routes": route_samples,
		"route_failure_samples": route_failure_samples,
		"route_projection_samples": route_projection_samples,
	}
	print("AI_NAV_PERF_JSON=" + JSON.stringify(result))
	quit(0)


func _parse_options(arguments: Array[String]) -> Dictionary:
	var result := {"level":"level.prototype_3v3", "map_level":"", "seed":20260711, "ticks":400, "gate_spacing":180.0, "attachment_limit":4}
	for argument in arguments:
		if argument.begins_with("--level="): result["level"] = argument.trim_prefix("--level=")
		elif argument.begins_with("--map-level="): result["map_level"] = argument.trim_prefix("--map-level=")
		elif argument.begins_with("--seed="): result["seed"] = int(argument.trim_prefix("--seed="))
		elif argument.begins_with("--ticks="): result["ticks"] = int(argument.trim_prefix("--ticks="))
		elif argument.begins_with("--gate-spacing="): result["gate_spacing"] = float(argument.trim_prefix("--gate-spacing="))
		elif argument.begins_with("--attachment-limit="): result["attachment_limit"] = int(argument.trim_prefix("--attachment-limit="))
	return result


func _install_map_variant(registry, base_level_id: String, map_level_id: String) -> String:
	var base_level: Dictionary = registry.get_definition("levels", base_level_id)
	var map_level: Dictionary = registry.get_definition("levels", map_level_id)
	if base_level.is_empty() or map_level.is_empty():
		return ""
	var terrain_id := str(map_level.get("map", {}).get("terrain_definition_id", ""))
	var terrain: Dictionary = registry.get_definition("terrain", terrain_id)
	if terrain.is_empty():
		return ""
	var runtime_level := base_level.duplicate(true)
	var runtime_level_id := "level.performance_runtime"
	runtime_level["id"] = runtime_level_id
	runtime_level["display_name"] = "Mapped navigation performance fixture"
	runtime_level["map"] = map_level.get("map", {}).duplicate(true)
	runtime_level.erase("require_equal_fleet_cost")
	for faction_id in ["player", "enemy"]:
		var slots: Array = terrain.get("spawn_points", []).filter(func(spawn): return str(spawn.get("faction_id", "")) == faction_id)
		slots.sort_custom(func(a, b): return int(str(a.get("id", "")).trim_prefix("%s_" % faction_id)) < int(str(b.get("id", "")).trim_prefix("%s_" % faction_id)))
		var fleet: Array = runtime_level.get("%s_fleet" % faction_id, [])
		if slots.size() < fleet.size():
			return ""
		for index in range(fleet.size()):
			fleet[index]["position"] = slots[index].get("position", []).duplicate()
			fleet[index]["heading"] = float(slots[index].get("heading", 0.0))
	registry.definitions.get("levels", {})[runtime_level_id] = runtime_level
	return runtime_level_id


func _timing_summary(values: Array) -> Dictionary:
	if values.is_empty(): return {"mean":0.0, "p50":0.0, "p95":0.0, "p99":0.0, "max":0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values: total += float(value)
	return {
		"mean": snappedf(total / float(values.size()) / 1000.0, 0.001),
		"p50": snappedf(float(sorted[_percentile_index(sorted.size(), 0.50)]) / 1000.0, 0.001),
		"p95": snappedf(float(sorted[_percentile_index(sorted.size(), 0.95)]) / 1000.0, 0.001),
		"p99": snappedf(float(sorted[_percentile_index(sorted.size(), 0.99)]) / 1000.0, 0.001),
		"max": snappedf(float(sorted[-1]) / 1000.0, 0.001),
	}


func _count_summary(values: Array) -> Dictionary:
	var total := 0
	var maximum := 0
	for value in values:
		total += int(value)
		maximum = maxi(maximum, int(value))
	return {"total":total, "max_per_tick":maximum}


func _count_distribution(values: Array) -> Dictionary:
	if values.is_empty(): return {"mean":0.0, "p95":0, "p99":0, "max":0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values: total += float(value)
	return {"mean":snappedf(total / values.size(), 0.01), "p95":int(sorted[_percentile_index(sorted.size(), 0.95)]), "p99":int(sorted[_percentile_index(sorted.size(), 0.99)]), "max":int(sorted[-1])}


func _percentile_index(size: int, percentile: float) -> int:
	return clampi(int(ceil(float(size) * percentile)) - 1, 0, size - 1)
