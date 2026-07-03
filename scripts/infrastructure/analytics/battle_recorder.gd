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
		"result": {},
		"ai_behavior": {
			"mode_switches": 0, "tactic_switches": 0, "target_switches": 0,
			"interrupt_entries": 0, "interrupt_clears": 0, "interrupt_by_type": {},
			"fire_commitments": 0, "skill_commitments": 0,
			"skill_score_total": 0.0, "coordination_score_total": 0.0,
			"task_assignments": 0, "task_clears": 0,
			"route_selections": 0, "route_fallbacks": 0, "route_unavailable": 0, "route_unavailable_by_reason": {}, "route_unavailable_by_unit": {}, "cover_selections": 0, "path_stuck_events": 0,
			"damage_reservations": 0, "effect_reservations": 0, "skill_holds": 0, "skill_holds_by_reason": {},
			"ai_command_rejections": 0, "rejections_by_reason": {},
			"facility_interactions_started": 0, "facility_interactions_completed": 0, "facility_interactions_interrupted": 0,
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
		}


func consume(events: Array, elapsed_time: float) -> void:
	summary["duration"] = elapsed_time
	for event in events:
		match event.get("event_type", ""):
			"MoveOrderAccepted", "FocusTargetChanged": summary["commands"] += 1
			"ContactAcquired":
				if summary["first_detection_time"] < 0.0: summary["first_detection_time"] = elapsed_time
			"WeaponFired":
				if summary["first_fire_time"] < 0.0: summary["first_fire_time"] = elapsed_time
			"SkillCast": summary["skill_casts"] += 1
			"AttackResolved": _record_damage(event.get("damage_result", {}), elapsed_time)
			"UnitSunk":
				if summary["first_sinking_time"] < 0.0: summary["first_sinking_time"] = elapsed_time
			"AIModeChanged": _record_ai_state_change(event, elapsed_time, true)
			"AITacticChanged": _record_ai_state_change(event, elapsed_time, false)
			"AITargetChanged": summary["ai_behavior"]["target_switches"] += 1
			"AIInterruptEntered": _record_counted_type("interrupt_entries", "interrupt_by_type", str(event.get("interrupt", "Unknown")))
			"AIInterruptCleared": summary["ai_behavior"]["interrupt_clears"] += 1
			"AIFireCommitted": summary["ai_behavior"]["fire_commitments"] += 1
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
			"AIPathStuck": summary["ai_behavior"]["path_stuck_events"] += 1
			"AIDamageReserved": summary["ai_behavior"]["damage_reservations"] += 1
			"AIEffectReserved": summary["ai_behavior"]["effect_reservations"] += 1
			"AISkillHeld": _record_counted_type("skill_holds", "skill_holds_by_reason", str(event.get("reason", "UNKNOWN")))
			"CommandRejected":
				if str(event.get("issuer_type", "")) in ["AI", "PlayerAssistAI"]:
					_record_counted_type("ai_command_rejections", "rejections_by_reason", str(event.get("reason_code", "UNKNOWN")))
			"FacilityInteractionStarted": summary["ai_behavior"]["facility_interactions_started"] += 1
			"FacilitySeized", "FacilityActivated", "FacilityServiceCompleted": summary["ai_behavior"]["facility_interactions_completed"] += 1
			"FacilityInteractionInterrupted": summary["ai_behavior"]["facility_interactions_interrupted"] += 1
			"BattleFinished":
				_finalize_ai_dwell(elapsed_time)
				summary["result"] = event.get("result", {}).duplicate(true)


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
	DamageStatistics.record_result(summary["units"], result)


func unit_damage_statistics(unit_id: String) -> Dictionary:
	return DamageStatistics.unit_statistics(summary.get("units", {}), unit_id)


func all_unit_damage_statistics() -> Dictionary:
	return DamageStatistics.all_unit_statistics(summary.get("units", {}))


func unit_damage_for_category(unit_id: String, category: String, include_contribution: bool = false) -> float:
	return DamageStatistics.damage_for_category(summary.get("units", {}), unit_id, category, include_contribution)
