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
	var trajectory_failure_samples: Array = []
	var event_counts := {
		"terrain_collisions":0,
		"route_failures":0,
		"projected_routes":0,
		"trajectory_failures":0,
		"contacts_acquired":0,
		"contacts_lost":0,
		"contact_types_changed":0,
	}
	var route_waypoint_total := 0
	var route_completions := 0
	var astar_usec_samples: Array = []
	var astar_expansion_samples: Array = []
	var trajectory_candidate_count_samples: Array = []
	var trajectory_candidate_rank_samples: Array = []
	var trajectory_valid_candidate_count_samples: Array = []
	var trajectory_candidate_ids := {}
	var selected_prediction_segments := 0
	var committed_prediction_segments := 0
	var normal_single_candidate_plans := 0
	var prediction_reuse_comparisons := 0
	var prediction_same_candidate := 0
	var prediction_reusable_suffixes := 0
	var prediction_position_errors: Array = []
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
			elif str(event.get("event_type", "")) == "TrajectoryPlanFailed":
				event_counts["trajectory_failures"] += 1
				if trajectory_failure_samples.size() < 16:
					var failed_unit: Dictionary = session.state.get("units_by_id", {}).get(str(event.get("unit_id", "")), {})
					var movement: Dictionary = failed_unit.get("movement_state", {})
					trajectory_failure_samples.append({"tick":session.state.get("tick_index", 0), "unit_id":event.get("unit_id", ""), "mode":event.get("mode", ""), "reason_code":event.get("reason_code", ""), "position":str(failed_unit.get("position", Vector2.ZERO)), "heading":failed_unit.get("heading", 0.0), "speed":failed_unit.get("current_speed", 0.0), "movement_mode":movement.get("mode", ""), "target":str(movement.get("target", Vector2.ZERO))})
			elif str(event.get("event_type", "")) == "TrajectoryPlanned":
				var candidate_count := int(event.get("candidate_count", 0))
				trajectory_candidate_count_samples.append(candidate_count)
				trajectory_candidate_rank_samples.append(int(event.get("candidate_rank", 0)))
				trajectory_valid_candidate_count_samples.append(int(event.get("valid_candidate_count", 0)))
				var candidate_key := "%s:%s" % [event.get("mode", ""), event.get("candidate_id", "")]
				trajectory_candidate_ids[candidate_key] = int(trajectory_candidate_ids.get(candidate_key, 0)) + 1
				selected_prediction_segments += int(event.get("predicted_segment_count", 0))
				committed_prediction_segments += mini(int(event.get("predicted_segment_count", 0)), int(event.get("committed_segment_count", 0)))
				if str(event.get("mode", "")) == "NormalNavigation" and candidate_count == 1:
					normal_single_candidate_plans += 1
				if str(event.get("mode", "")) == "NormalNavigation" and not str(event.get("previous_candidate_id", "")).is_empty():
					prediction_reuse_comparisons += 1
					prediction_position_errors.append(float(event.get("prediction_position_error", 0.0)))
					if str(event.get("previous_candidate_id", "")) == str(event.get("candidate_id", "")):
						prediction_same_candidate += 1
					if bool(event.get("prediction_suffix_reusable", false)):
						prediction_reusable_suffixes += 1
			elif str(event.get("event_type", "")) == "ContactAcquired": event_counts["contacts_acquired"] += 1
			elif str(event.get("event_type", "")) == "ContactLost": event_counts["contacts_lost"] += 1
			elif str(event.get("event_type", "")) == "ContactTypeChanged": event_counts["contact_types_changed"] += 1
		executed_ticks += 1
	route_samples.sort_custom(func(a, b): return int(a.get("elapsed_usec", 0)) > int(b.get("elapsed_usec", 0)))
	if route_samples.size() > 8: route_samples.resize(8)
	var profile := session.get_performance_profile()
	var total_segments_simulated: int = int(_count_summary(profile.get("trajectory_segments_simulated_per_tick", [])).get("total", 0))
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
		"tick_breakdown_ms": {
			"setup_environment":_timing_summary(profile.get("tick_setup_environment_usec", [])),
			"command_processing":_timing_summary(profile.get("command_processing_usec", [])),
			"strategic_navigation":_timing_summary(profile.get("strategic_navigation_usec", [])),
			"status_updates":_timing_summary(profile.get("status_updates_usec", [])),
			"local_navigation":_timing_summary(profile.get("navigation_usec", [])),
			"movement":_timing_summary(profile.get("movement_usec", [])),
			"unit_overlap":_timing_summary(profile.get("unit_overlap_usec", [])),
			"projectile_update":_timing_summary(profile.get("projectile_update_usec", [])),
			"observation_detection":_timing_summary(profile.get("observation_detection_usec", [])),
			"ai_memory":_timing_summary(profile.get("ai_memory_usec", [])),
			"ai_decision":_timing_summary(profile.get("ai_decision_usec", [])),
			"combat_actions":_timing_summary(profile.get("combat_actions_usec", [])),
			"facility_mine":_timing_summary(profile.get("facility_mine_usec", [])),
			"settlement_recording":_timing_summary(profile.get("settlement_recording_usec", [])),
			"unclassified":_timing_summary(profile.get("tick_unclassified_usec", [])),
		},
		"tick_detail_ms": {
			"projectile_observation":_timing_summary(profile.get("projectile_observation_usec", [])),
			"mine_observation":_timing_summary(profile.get("mine_observation_usec", [])),
			"unit_detection":_timing_summary(profile.get("unit_detection_usec", [])),
			"ai_group_formation":_timing_summary(profile.get("ai_group_formation_usec", [])),
			"ai_support_planning":_timing_summary(profile.get("ai_support_planning_usec", [])),
			"ai_unit_intents":_timing_summary(profile.get("ai_unit_intents_usec", [])),
			"ai_primary_weapons":_timing_summary(profile.get("ai_primary_weapons_usec", [])),
		},
		"navigation_ms": _timing_summary(profile.get("navigation_usec", [])),
		"movement_ms": _timing_summary(profile.get("movement_usec", [])),
		"ai_decision_ms": _timing_summary(profile.get("ai_decision_usec", [])),
		"normal_plans": _count_summary(profile.get("normal_plans_per_tick", [])),
		"emergency_scans": _count_summary(profile.get("emergency_scans_per_tick", [])),
		"emergency_plans": _count_summary(profile.get("emergency_plans_per_tick", [])),
		"strategic_corridors": _count_summary(profile.get("strategic_corridors_per_tick", [])),
		"trajectory_candidates": _count_summary(profile.get("trajectory_candidates_per_tick", [])),
		"trajectory_failures": _count_summary(profile.get("trajectory_failures_per_tick", [])),
		"trajectory_segments_simulated": _count_summary(profile.get("trajectory_segments_simulated_per_tick", [])),
		"trajectory_candidates_rejected_by_terrain": _count_summary(profile.get("trajectory_candidates_rejected_by_terrain_per_tick", [])),
		"detection_unit_pairs": _count_summary(profile.get("detection_unit_pairs_per_tick", [])),
		"detection_range_passes": _count_summary(profile.get("detection_range_passes_per_tick", [])),
		"detection_los_queries": _count_summary(profile.get("detection_los_queries_per_tick", [])),
		"detection_context_samples": _count_summary(profile.get("detection_context_samples_per_tick", [])),
		"trajectory_motion_expansion_ms":_timing_summary(profile.get("trajectory_motion_expansion_usec", [])),
		"trajectory_terrain_validation_ms":_timing_summary(profile.get("trajectory_terrain_validation_usec", [])),
		"trajectory_environment_access_ms":_timing_summary(profile.get("trajectory_environment_access_usec", [])),
		"trajectory_dynamic_validation_ms":_timing_summary(profile.get("trajectory_dynamic_validation_usec", [])),
		"trajectory_candidate_scoring_ms":_timing_summary(profile.get("trajectory_candidate_scoring_usec", [])),
		"trajectory_candidate_count_distribution":_count_distribution(trajectory_candidate_count_samples),
		"trajectory_candidate_rank_distribution":_count_distribution(trajectory_candidate_rank_samples),
		"trajectory_valid_candidate_count_distribution":_count_distribution(trajectory_valid_candidate_count_samples),
		"trajectory_selected_candidate_ids":trajectory_candidate_ids,
		"normal_single_candidate_plans":normal_single_candidate_plans,
		"selected_prediction_segments":selected_prediction_segments,
		"committed_prediction_segments":committed_prediction_segments,
		"prediction_utilization":{"selected_over_simulated":snappedf(float(selected_prediction_segments) / maxf(1.0, float(total_segments_simulated)), 0.0001), "committed_over_simulated":snappedf(float(committed_prediction_segments) / maxf(1.0, float(total_segments_simulated)), 0.0001)},
		"prediction_reuse":{"comparisons":prediction_reuse_comparisons, "same_candidate":prediction_same_candidate, "reusable_suffixes":prediction_reusable_suffixes, "position_error":_value_summary(prediction_position_errors)},
		"collision_field_ms": _timing_summary(profile.get("collision_field_usec", [])),
		"collision_field_queries": _count_summary(profile.get("collision_field_queries_per_tick", [])),
		"collision_field_cells_visited": _count_summary(profile.get("collision_field_cells_visited_per_tick", [])),
		"collision_field_definitely_clear": _count_summary(profile.get("collision_field_definitely_clear_per_tick", [])),
		"collision_field_exact_fallbacks": _count_summary(profile.get("collision_field_exact_fallbacks_per_tick", [])),
		"collision_field_unavailable_fallbacks": _count_summary(profile.get("collision_field_unavailable_fallbacks_per_tick", [])),
		"collision_field_region_definitely_clear": _count_summary(profile.get("collision_field_region_definitely_clear_per_tick", [])),
		"collision_field_region_exact_fallbacks": _count_summary(profile.get("collision_field_region_exact_fallbacks_per_tick", [])),
		"slowest_routes": route_samples,
		"route_failure_samples": route_failure_samples,
		"route_projection_samples": route_projection_samples,
		"trajectory_failure_samples":trajectory_failure_samples,
	}
	if bool(options.get("compact", false)):
		var compact := {
			"map_level":result["map_level"], "executed_ticks":executed_ticks, "phase":result["phase"], "event_counts":event_counts,
			"waiting_units":result["waiting_units"], "tick_ms":result["tick_ms"], "navigation_ms":result["navigation_ms"],
			"tick_breakdown_ms":result["tick_breakdown_ms"],
			"tick_detail_ms":result["tick_detail_ms"],
			"collision_field_ms":result["collision_field_ms"], "collision_field_queries":result["collision_field_queries"],
			"collision_field_exact_fallbacks":result["collision_field_exact_fallbacks"], "normal_plans":result["normal_plans"],
			"collision_field_region_definitely_clear":result["collision_field_region_definitely_clear"], "collision_field_region_exact_fallbacks":result["collision_field_region_exact_fallbacks"],
			"trajectory_candidates":result["trajectory_candidates"], "trajectory_segments_simulated":result["trajectory_segments_simulated"],
			"trajectory_candidates_rejected_by_terrain":result["trajectory_candidates_rejected_by_terrain"],
			"detection_unit_pairs":result["detection_unit_pairs"], "detection_range_passes":result["detection_range_passes"],
			"detection_los_queries":result["detection_los_queries"], "detection_context_samples":result["detection_context_samples"],
			"trajectory_candidate_count_distribution":result["trajectory_candidate_count_distribution"], "trajectory_candidate_rank_distribution":result["trajectory_candidate_rank_distribution"],
			"trajectory_motion_expansion_ms":result["trajectory_motion_expansion_ms"], "trajectory_terrain_validation_ms":result["trajectory_terrain_validation_ms"], "trajectory_dynamic_validation_ms":result["trajectory_dynamic_validation_ms"], "trajectory_candidate_scoring_ms":result["trajectory_candidate_scoring_ms"],
			"trajectory_selected_candidate_ids":trajectory_candidate_ids, "normal_single_candidate_plans":normal_single_candidate_plans, "prediction_utilization":result["prediction_utilization"], "prediction_reuse":result["prediction_reuse"],
			"trajectory_failure_samples":trajectory_failure_samples,
		}
		print("AI_NAV_PERF_COMPACT_JSON=" + JSON.stringify(compact))
	else:
		print("AI_NAV_PERF_JSON=" + JSON.stringify(result))
	quit(0)


func _parse_options(arguments: Array[String]) -> Dictionary:
	var result := {"level":"level.prototype_3v3", "map_level":"", "seed":20260711, "ticks":400, "gate_spacing":180.0, "attachment_limit":4, "compact":false}
	for argument in arguments:
		if argument.begins_with("--level="): result["level"] = argument.trim_prefix("--level=")
		elif argument.begins_with("--map-level="): result["map_level"] = argument.trim_prefix("--map-level=")
		elif argument.begins_with("--seed="): result["seed"] = int(argument.trim_prefix("--seed="))
		elif argument.begins_with("--ticks="): result["ticks"] = int(argument.trim_prefix("--ticks="))
		elif argument.begins_with("--gate-spacing="): result["gate_spacing"] = float(argument.trim_prefix("--gate-spacing="))
		elif argument.begins_with("--attachment-limit="): result["attachment_limit"] = int(argument.trim_prefix("--attachment-limit="))
		elif argument == "--compact": result["compact"] = true
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


func _value_summary(values: Array) -> Dictionary:
	if values.is_empty(): return {"mean":0.0, "p95":0.0, "p99":0.0, "max":0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values: total += float(value)
	return {"mean":snappedf(total / values.size(), 0.0001), "p95":snappedf(float(sorted[_percentile_index(sorted.size(), 0.95)]), 0.0001), "p99":snappedf(float(sorted[_percentile_index(sorted.size(), 0.99)]), 0.0001), "max":snappedf(float(sorted[-1]), 0.0001)}


func _percentile_index(size: int, percentile: float) -> int:
	return clampi(int(ceil(float(size) * percentile)) - 1, 0, size - 1)
