extends RefCounted

const DamageStatistics = preload("res://scripts/infrastructure/analytics/damage_statistics.gd")

var summary := {}
var _ai_runtime := {}


func reset(battle_id: String, seed_value: int) -> void:
	_ai_runtime.clear()
	summary = {
		"battle_id": battle_id,
		"seed": seed_value,
		"duration": 0.0,
		"first_detection_time": -1.0,
		"first_fire_time": -1.0,
		"first_hit_time": -1.0,
		"first_sinking_time": -1.0,
		"commands": 0,
		"skill_casts": 0,
		"units": {},
		"non_ship_damage": {},
		"result": {},
		"submarine_ai": {},
		"ai_behavior": {
			"mode_switches": 0, "tactic_switches": 0, "target_switches": 0,
			"interrupt_entries": 0, "interrupt_clears": 0, "interrupt_by_type": {},
			"fire_commitments": 0, "skill_commitments": 0,
			"skill_score_total": 0.0, "coordination_score_total": 0.0,
			"task_assignments": 0, "task_clears": 0,
			"route_selections": 0, "route_fallbacks": 0, "route_unavailable": 0, "route_unavailable_by_reason": {}, "route_unavailable_by_unit": {}, "cover_selections": 0, "path_stuck_events": 0, "path_stuck_by_unit": {}, "path_stuck_details": [],
			"damage_reservations": 0, "effect_reservations": 0, "skill_holds": 0, "skill_holds_by_reason": {},
			"ai_command_rejections": 0, "rejections_by_reason": {},
			"facility_interactions_started": 0, "facility_interactions_completed": 0, "facility_interactions_interrupted": 0,
			"passive_duration_seconds": 0.0, "engagement_pressure_triggers": 0,
			"engagement_response_time_total": 0.0, "engagement_response_count": 0,
			"long_idle_events": 0,
			"mode_dwell_seconds": {}, "tactic_dwell_seconds": {},
		},
	}


func register_units(units_by_id: Dictionary) -> void:
	for unit_id in units_by_id:
		var unit: Dictionary = units_by_id[unit_id]
		DamageStatistics.ensure_unit(summary["units"], str(unit_id), {
			"definition_id": unit.get("definition_id", ""),
			"display_name": unit.get("display_name", ""),
			"faction_id": unit.get("faction_id", ""),
		})
		_ai_runtime[str(unit_id)] = {
			"mode_id": str(unit.get("ai_state", {}).get("mode_id", "")), "mode_since": 0.0,
			"tactic_id": str(unit.get("ai_state", {}).get("tactic_id", "")), "tactic_since": 0.0,
			"is_submarine": str(unit.get("stats", {}).get("ship_class", "")) == "Submarine",
			"submarine_cycle_phases": [],
			"submarine_cycle_fires": 0,
		}
		if str(unit.get("stats", {}).get("ship_class", "")) == "Submarine":
			summary["submarine_ai"][str(unit_id)] = _new_submarine_ai_entry(unit)


func _new_submarine_ai_entry(unit: Dictionary) -> Dictionary:
	return {
		"definition_id": unit.get("definition_id", ""),
		"display_name": unit.get("display_name", ""),
		"faction_id": unit.get("faction_id", ""),
		"decision_samples": 0,
		"visible_target_samples": 0,
		"ready_weapon_samples": 0,
		"legal_solution_samples": 0,
		"scored_window_samples": 0,
		"window_score_total": 0.0,
		"window_score_max": 0.0,
		"window_threshold_total": 0.0,
		"friendly_risk_ignored_samples": 0,
		"friendly_risk_observed_samples": 0,
		"friendly_risk_observed_max": 0.0,
		"opportunity_forced_samples": 0,
		"outcomes_by_reason": {},
		"rejections_by_reason": {},
		"fire_commitments": 0,
		"weapon_fires": 0,
		"fires_by_phase": {},
		"first_fire_tick": -1,
		"first_fire_time": -1.0,
		"first_fire_weapon_state_instance_id": "",
		"first_fire_phase": "",
		"selected_weapon_instances": {},
		"command_rejections_by_reason": {},
		"opportunities_observed": 0,
		"opportunities_expired": 0,
		"opportunity_expiry_reasons": {},
		"attack_run_timeouts": 0,
		"phase_transitions": {},
		"phase_reasons": {},
		"phase_dwell_seconds": {},
		"depth_dwell_seconds": {},
		"depth_changes": 0,
		"forced_surfaces": 0,
		"depth_requests": 0,
		"depth_requests_by_target": {},
		"depth_changes_by_target": {},
		"depth_request_holds_by_reason": {},
		"oxygen_dwell_seconds": {"0_25": 0.0, "25_50": 0.0, "50_75": 0.0, "75_100": 0.0},
		"oxygen_min_ratio": 1.0,
		"oxygen_max_ratio": 0.0,
		"normal_full_cycles": 0,
		"submerged_launch_cycles": 0,
		"incomplete_attack_cycles": 0,
		"recovery_self_defense_fires": 0,
		"cycle_examples": [],
		"zero_fire_classification": "SUBMARINE_NO_FIRE_DECISIONS",
	}


func sample_submarines(units_by_id: Dictionary, delta: float) -> void:
	for unit_id in summary.get("submarine_ai", {}):
		var unit: Dictionary = units_by_id.get(unit_id, {})
		if unit.is_empty() or unit.get("life_state", "") != "Alive": continue
		var entry: Dictionary = summary["submarine_ai"][unit_id]
		var phase := str(unit.get("ai_state", {}).get("submarine_combat_phase", "Unknown"))
		entry["phase_dwell_seconds"][phase] = float(entry["phase_dwell_seconds"].get(phase, 0.0)) + delta
		var depth_state := str(unit.get("depth_state", "Unknown"))
		entry["depth_dwell_seconds"][depth_state] = float(entry["depth_dwell_seconds"].get(depth_state, 0.0)) + delta
		var oxygen: Dictionary = unit.get("oxygen_state", {})
		var maximum := maxf(1.0, float(oxygen.get("maximum", unit.get("stats", {}).get("max_oxygen", 1.0))))
		var ratio := clampf(float(oxygen.get("current", maximum)) / maximum, 0.0, 1.0)
		var oxygen_bucket := "0_25" if ratio < 0.25 else ("25_50" if ratio < 0.5 else ("50_75" if ratio < 0.75 else "75_100"))
		entry["oxygen_dwell_seconds"][oxygen_bucket] = float(entry["oxygen_dwell_seconds"].get(oxygen_bucket, 0.0)) + delta
		entry["oxygen_min_ratio"] = minf(float(entry.get("oxygen_min_ratio", 1.0)), ratio)
		entry["oxygen_max_ratio"] = maxf(float(entry.get("oxygen_max_ratio", 0.0)), ratio)


func consume(events: Array, elapsed_time: float) -> void:
	summary["duration"] = elapsed_time
	for event in events:
		match event.get("event_type", ""):
			"MoveOrderAccepted", "FocusTargetChanged": summary["commands"] += 1
			"ContactAcquired":
				if summary["first_detection_time"] < 0.0: summary["first_detection_time"] = elapsed_time
			"WeaponFired":
				if summary["first_fire_time"] < 0.0: summary["first_fire_time"] = elapsed_time
				_record_submarine_weapon_fired(event, elapsed_time)
			"SkillCast": summary["skill_casts"] += 1
			"AttackResolved": _record_damage(event.get("damage_result", {}), elapsed_time)
			"UnitSunk":
				if summary["first_sinking_time"] < 0.0: summary["first_sinking_time"] = elapsed_time
			"AIModeChanged": _record_ai_state_change(event, elapsed_time, true)
			"AITacticChanged": _record_ai_state_change(event, elapsed_time, false)
			"AITargetChanged": summary["ai_behavior"]["target_switches"] += 1
			"AIInterruptEntered": _record_counted_type("interrupt_entries", "interrupt_by_type", str(event.get("interrupt", "Unknown")))
			"AIInterruptCleared": summary["ai_behavior"]["interrupt_clears"] += 1
			"AIFireCommitted":
				summary["ai_behavior"]["fire_commitments"] += 1
				_record_submarine_fire_commitment(event)
			"AISubmarineFireDecisionSample": _record_submarine_fire_decision(event)
			"AISubmarinePhaseChanged": _record_submarine_phase_change(event)
			"AISubmarineAttackRunTimedOut": _record_submarine_counter(event, "attack_run_timeouts")
			"AITorpedoOpportunityObserved": _record_submarine_counter(event, "opportunities_observed")
			"AITorpedoOpportunityExpired": _record_submarine_opportunity_expired(event)
			"AIDepthRequestCommitted": _record_submarine_depth_target(event, "depth_requests", "depth_requests_by_target")
			"AIDepthRequestHeld": _record_submarine_reason(event, "depth_request_holds_by_reason", "reason")
			"SubmarineDepthChanged": _record_submarine_depth_target(event, "depth_changes", "depth_changes_by_target")
			"SubmarineForcedSurface": _record_submarine_counter(event, "forced_surfaces")
			"AISkillCommitted":
				summary["ai_behavior"]["skill_commitments"] += 1
				summary["ai_behavior"]["skill_score_total"] += float(event.get("score", 0.0))
				summary["ai_behavior"]["coordination_score_total"] += float(event.get("coordination_score", 0.0))
			"AILevelTaskChanged":
				if str(event.get("level_task", "")).is_empty(): summary["ai_behavior"]["task_clears"] += 1
				else: summary["ai_behavior"]["task_assignments"] += 1
			"AIRouteSelected": summary["ai_behavior"]["route_selections"] += 1
			"AIRouteFallbackSelected": summary["ai_behavior"]["route_fallbacks"] += 1
			"AIRouteUnavailable":
				_record_counted_type("route_unavailable", "route_unavailable_by_reason", str(event.get("reason_code", "UNKNOWN")))
				var route_unit_id := str(event.get("unit_id", "UNKNOWN"))
				summary["ai_behavior"]["route_unavailable_by_unit"][route_unit_id] = int(summary["ai_behavior"]["route_unavailable_by_unit"].get(route_unit_id, 0)) + 1
			"AICoverSelected": summary["ai_behavior"]["cover_selections"] += 1
			"AIPathStuck":
				summary["ai_behavior"]["path_stuck_events"] += 1
				var stuck_unit_id := str(event.get("unit_id", "UNKNOWN"))
				summary["ai_behavior"]["path_stuck_by_unit"][stuck_unit_id] = int(summary["ai_behavior"]["path_stuck_by_unit"].get(stuck_unit_id, 0)) + 1
				summary["ai_behavior"]["path_stuck_details"].append({
					"unit_id":stuck_unit_id,
					"elapsed_time":elapsed_time,
					"position":event.get("position", Vector2.ZERO),
					"target_position":event.get("target_position", Vector2.ZERO),
				})
			"AIDamageReserved": summary["ai_behavior"]["damage_reservations"] += 1
			"AIEffectReserved": summary["ai_behavior"]["effect_reservations"] += 1
			"AISkillHeld": _record_counted_type("skill_holds", "skill_holds_by_reason", str(event.get("reason", "UNKNOWN")))
			"CommandRejected":
				if str(event.get("issuer_type", "")) in ["AI", "PlayerAssistAI"]:
					_record_counted_type("ai_command_rejections", "rejections_by_reason", str(event.get("reason_code", "UNKNOWN")))
					_record_submarine_reason(event, "command_rejections_by_reason", "reason_code")
			"FacilityControlDeclared", "FacilityServiceStarted": summary["ai_behavior"]["facility_interactions_started"] += 1
			"FacilityControlCompleted", "FacilityServiceCompleted": summary["ai_behavior"]["facility_interactions_completed"] += 1
			"FacilityActionInterrupted": summary["ai_behavior"]["facility_interactions_interrupted"] += 1
			"AIEngagementPressureTriggered": summary["ai_behavior"]["engagement_pressure_triggers"] += 1
			"AIEngagementPressureSample": summary["ai_behavior"]["passive_duration_seconds"] += float(event.get("duration", 0.0))
			"AIEngagementPressureResolved":
				summary["ai_behavior"]["engagement_response_count"] += 1
				summary["ai_behavior"]["engagement_response_time_total"] += float(event.get("response_time", 0.0))
			"AILongIdleDetected": summary["ai_behavior"]["long_idle_events"] += 1
			"BattleFinished":
				_finalize_ai_dwell(elapsed_time)
				_finalize_open_submarine_cycles()
				summary["result"] = event.get("result", {}).duplicate(true)
	_refresh_submarine_zero_fire_classifications()


func _record_submarine_fire_decision(event: Dictionary) -> void:
	var entry := _submarine_entry_for_event(event)
	if entry.is_empty(): return
	entry["decision_samples"] += 1
	if bool(event.get("visible_target", false)): entry["visible_target_samples"] += 1
	if int(event.get("ready_weapon_count", 0)) > 0: entry["ready_weapon_samples"] += 1
	if int(event.get("legal_candidate_count", 0)) > 0: entry["legal_solution_samples"] += 1
	if bool(event.get("opportunity_forced", false)): entry["opportunity_forced_samples"] += 1
	_increment_map(entry["outcomes_by_reason"], str(event.get("outcome_reason", "UNKNOWN")))
	_merge_count_map(entry["rejections_by_reason"], event.get("rejections_by_reason", {}))
	var selected_instance_id := str(event.get("selected_weapon_state_instance_id", ""))
	if not selected_instance_id.is_empty():
		_increment_map(entry["selected_weapon_instances"], selected_instance_id)
		entry["scored_window_samples"] += 1
		entry["window_score_total"] += float(event.get("window_score", 0.0))
		entry["window_score_max"] = maxf(float(entry.get("window_score_max", 0.0)), float(event.get("window_score", 0.0)))
		entry["window_threshold_total"] += float(event.get("window_threshold", 0.0))
		if bool(event.get("friendly_risk_ignored", false)): entry["friendly_risk_ignored_samples"] += 1
		var observed_friendly_risk := float(event.get("observed_friendly_risk", 0.0))
		if observed_friendly_risk > 0.0: entry["friendly_risk_observed_samples"] += 1
		entry["friendly_risk_observed_max"] = maxf(float(entry.get("friendly_risk_observed_max", 0.0)), observed_friendly_risk)


func _record_submarine_fire_commitment(event: Dictionary) -> void:
	var entry := _submarine_entry_for_event(event)
	if entry.is_empty(): return
	entry["fire_commitments"] += 1


func _record_submarine_weapon_fired(event: Dictionary, elapsed_time: float) -> void:
	var entry := _submarine_entry_for_event(event)
	if entry.is_empty(): return
	entry["weapon_fires"] += 1
	var phase := str(event.get("submarine_phase", "Unknown"))
	_increment_map(entry["fires_by_phase"], phase)
	if int(entry.get("first_fire_tick", -1)) < 0:
		entry["first_fire_tick"] = int(event.get("tick_index", -1))
		entry["first_fire_time"] = elapsed_time
		entry["first_fire_weapon_state_instance_id"] = str(event.get("weapon_state_instance_id", ""))
		entry["first_fire_phase"] = phase
	if phase == "RecoverOxygen": entry["recovery_self_defense_fires"] += 1
	var runtime: Dictionary = _ai_runtime.get(str(event.get("unit_id", "")), {})
	if not runtime.get("submarine_cycle_phases", []).is_empty():
		runtime["submarine_cycle_fires"] = int(runtime.get("submarine_cycle_fires", 0)) + 1
		_ai_runtime[str(event.get("unit_id", ""))] = runtime


func _record_submarine_phase_change(event: Dictionary) -> void:
	var entry := _submarine_entry_for_event(event)
	if entry.is_empty(): return
	var old_phase := str(event.get("old_phase", "Unknown"))
	var new_phase := str(event.get("new_phase", "Unknown"))
	_increment_map(entry["phase_transitions"], "%s->%s" % [old_phase, new_phase])
	_increment_map(entry["phase_reasons"], str(event.get("reason", "UNKNOWN")))
	var unit_id := str(event.get("unit_id", ""))
	var runtime: Dictionary = _ai_runtime.get(unit_id, {})
	var phases: Array = runtime.get("submarine_cycle_phases", [])
	if old_phase == "Search" and new_phase == "Approach":
		phases = ["Search", "Approach"]
		runtime["submarine_cycle_fires"] = 0
	elif not phases.is_empty() and str(phases.back()) != new_phase:
		phases.append(new_phase)
	runtime["submarine_cycle_phases"] = phases
	_ai_runtime[unit_id] = runtime
	if new_phase == "Search" and not phases.is_empty():
		_finalize_submarine_cycle(unit_id, entry)


func _finalize_submarine_cycle(unit_id: String, entry: Dictionary) -> void:
	var runtime: Dictionary = _ai_runtime.get(unit_id, {})
	var phases: Array = runtime.get("submarine_cycle_phases", [])
	var fires := int(runtime.get("submarine_cycle_fires", 0))
	var normal_cycle := _contains_ordered_phases(phases, ["Search", "Approach", "SurfaceForAttack", "AttackRun", "BreakContact", "RecoverOxygen", "Search"])
	var submerged_cycle := not normal_cycle and _contains_ordered_phases(phases, ["Search", "Approach", "AttackRun", "BreakContact", "RecoverOxygen", "Search"])
	if fires > 0 and normal_cycle:
		entry["normal_full_cycles"] += 1
	elif fires > 0 and submerged_cycle:
		entry["submerged_launch_cycles"] += 1
	else:
		entry["incomplete_attack_cycles"] += 1
	if entry["cycle_examples"].size() < 6:
		entry["cycle_examples"].append({"phases": "->".join(phases), "fires": fires})
	runtime["submarine_cycle_phases"] = []
	runtime["submarine_cycle_fires"] = 0
	_ai_runtime[unit_id] = runtime


func _contains_ordered_phases(phases: Array, required: Array) -> bool:
	var required_index := 0
	for phase in phases:
		if required_index < required.size() and str(phase) == str(required[required_index]):
			required_index += 1
	return required_index == required.size()


func _finalize_open_submarine_cycles() -> void:
	for unit_id in _ai_runtime:
		var runtime: Dictionary = _ai_runtime[unit_id]
		if bool(runtime.get("is_submarine", false)) and not runtime.get("submarine_cycle_phases", []).is_empty():
			_finalize_submarine_cycle(str(unit_id), summary["submarine_ai"][unit_id])


func _record_submarine_counter(event: Dictionary, key: String) -> void:
	var entry := _submarine_entry_for_event(event)
	if not entry.is_empty(): entry[key] = int(entry.get(key, 0)) + 1


func _record_submarine_depth_target(event: Dictionary, total_key: String, map_key: String) -> void:
	var entry := _submarine_entry_for_event(event)
	if entry.is_empty(): return
	entry[total_key] = int(entry.get(total_key, 0)) + 1
	_increment_map(entry[map_key], str(event.get("target_depth_state", "Unknown")))


func _record_submarine_reason(event: Dictionary, map_key: String, event_reason_key: String) -> void:
	var entry := _submarine_entry_for_event(event)
	if entry.is_empty(): return
	_increment_map(entry[map_key], str(event.get(event_reason_key, "UNKNOWN")))


func _record_submarine_opportunity_expired(event: Dictionary) -> void:
	var entry := _submarine_entry_for_event(event)
	if entry.is_empty(): return
	entry["opportunities_expired"] += 1
	_increment_map(entry["opportunity_expiry_reasons"], str(event.get("reason", "UNKNOWN")))


func _submarine_entry_for_event(event: Dictionary) -> Dictionary:
	return summary.get("submarine_ai", {}).get(str(event.get("unit_id", "")), {})


func _increment_map(counts: Dictionary, key: String, amount: int = 1) -> void:
	counts[key] = int(counts.get(key, 0)) + amount


func _merge_count_map(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		target[key] = int(target.get(key, 0)) + int(source[key])


func _refresh_submarine_zero_fire_classifications() -> void:
	for entry in summary.get("submarine_ai", {}).values():
		if int(entry.get("weapon_fires", 0)) > 0:
			entry["zero_fire_classification"] = "FIRED"
		elif int(entry.get("decision_samples", 0)) <= 0:
			entry["zero_fire_classification"] = "SUBMARINE_NO_FIRE_DECISIONS"
		elif int(entry.get("visible_target_samples", 0)) <= 0:
			entry["zero_fire_classification"] = "SUBMARINE_NO_VISIBLE_TARGET"
		elif int(entry.get("ready_weapon_samples", 0)) <= 0:
			entry["zero_fire_classification"] = "SUBMARINE_NO_READY_WEAPON"
		elif int(entry.get("legal_solution_samples", 0)) <= 0:
			entry["zero_fire_classification"] = "SUBMARINE_NO_LEGAL_SOLUTION"
		elif int(entry.get("legal_solution_samples", 0)) >= 5:
			entry["zero_fire_classification"] = "SUBMARINE_ELIGIBLE_WINDOW_NO_FIRE"
		elif int(entry.get("fire_commitments", 0)) > 0:
			entry["zero_fire_classification"] = "SUBMARINE_COMMITTED_WITHOUT_FIRE"
		elif int(entry.get("outcomes_by_reason", {}).get("SUB_ATTACK_HELD_DISCIPLINE", 0)) > 0:
			entry["zero_fire_classification"] = "SUBMARINE_DISCIPLINE_HELD"
		else:
			entry["zero_fire_classification"] = "SUBMARINE_ZERO_FIRE_UNCLASSIFIED"


func _record_ai_state_change(event: Dictionary, elapsed_time: float, is_mode: bool) -> void:
	var unit_id := str(event.get("unit_id", ""))
	var runtime: Dictionary = _ai_runtime.get(unit_id, {})
	var id_key := "mode_id" if is_mode else "tactic_id"
	var since_key := "mode_since" if is_mode else "tactic_since"
	var dwell_key := "mode_dwell_seconds" if is_mode else "tactic_dwell_seconds"
	var switch_key := "mode_switches" if is_mode else "tactic_switches"
	var old_id := str(runtime.get(id_key, event.get("old_mode_id" if is_mode else "old_tactic_id", "")))
	if not old_id.is_empty():
		summary["ai_behavior"][dwell_key][old_id] = float(summary["ai_behavior"][dwell_key].get(old_id, 0.0)) + maxf(0.0, elapsed_time - float(runtime.get(since_key, 0.0)))
	runtime[id_key] = str(event.get("new_mode_id" if is_mode else "new_tactic_id", ""))
	runtime[since_key] = elapsed_time
	_ai_runtime[unit_id] = runtime
	summary["ai_behavior"][switch_key] += 1


func _record_counted_type(total_key: String, map_key: String, type_id: String) -> void:
	summary["ai_behavior"][total_key] += 1
	summary["ai_behavior"][map_key][type_id] = int(summary["ai_behavior"][map_key].get(type_id, 0)) + 1


func _finalize_ai_dwell(elapsed_time: float) -> void:
	for runtime in _ai_runtime.values():
		for prefix in ["mode", "tactic"]:
			var state_id := str(runtime.get("%s_id" % prefix, ""))
			if state_id.is_empty(): continue
			var dwell_key := "%s_dwell_seconds" % prefix
			summary["ai_behavior"][dwell_key][state_id] = float(summary["ai_behavior"][dwell_key].get(state_id, 0.0)) + maxf(0.0, elapsed_time - float(runtime.get("%s_since" % prefix, 0.0)))


func _record_damage(result: Dictionary, elapsed_time: float) -> void:
	var source_id := str(result.get("source_unit_id", ""))
	if bool(result.get("hit", false)) and not source_id.is_empty():
		if summary["first_hit_time"] < 0.0: summary["first_hit_time"] = elapsed_time
	DamageStatistics.record_result(summary["units"], summary["non_ship_damage"], result)


func unit_damage_statistics(unit_id: String) -> Dictionary:
	return DamageStatistics.unit_statistics(summary.get("units", {}), unit_id)


func all_unit_damage_statistics() -> Dictionary:
	return DamageStatistics.all_unit_statistics(summary.get("units", {}))


func non_ship_damage_statistics(source_id: String) -> Dictionary:
	return DamageStatistics.non_ship_statistics(summary.get("non_ship_damage", {}), source_id)


func all_non_ship_damage_statistics() -> Dictionary:
	return DamageStatistics.all_non_ship_statistics(summary.get("non_ship_damage", {}))


func unit_damage_for_category(unit_id: String, category: String, include_contribution: bool = false) -> float:
	return DamageStatistics.damage_for_category(summary.get("units", {}), unit_id, category, include_contribution)
