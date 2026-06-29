class_name AIQuantitativeModel
extends RefCounted

const EPSILON := 0.0001


static func clamp01(value: float) -> float:
	return clampf(value, 0.0, 1.0)


static func score100(value: float) -> float:
	return clampf(value * 100.0, 0.0, 100.0)


static func target_score(values: Dictionary) -> float:
	if not bool(values.get("legal", true)) or not bool(values.get("visible", true)):
		return 0.0
	return score100(
		0.30 * clamp01(float(values.get("mission_value", 0.0)))
		+ 0.20 * clamp01(float(values.get("threat", 0.0)))
		+ 0.17 * clamp01(float(values.get("weapon_fit", 0.0)))
		+ 0.11 * clamp01(float(values.get("range_fit", 0.0)))
		+ 0.09 * clamp01(float(values.get("kill_opportunity", 0.0)))
		+ 0.07 * clamp01(float(values.get("focus_fire", 0.0)))
		+ 0.06 * clamp01(float(values.get("objective_relevance", 0.0)))
		- 0.12 * clamp01(float(values.get("pursuit_cost", 0.0)))
		- 0.10 * clamp01(float(values.get("overkill", 0.0)))
	)


static func torpedo_threat_score(values: Dictionary) -> float:
	if not bool(values.get("visible", false)) or not bool(values.get("approaching", false)):
		return 0.0
	var reaction_horizon := maxf(0.1, float(values.get("reaction_horizon", 6.0)))
	var time_to_cpa := maxf(0.0, float(values.get("time_to_cpa", reaction_horizon)))
	var danger_radius := maxf(1.0, float(values.get("danger_radius", 60.0)))
	var cpa_distance := maxf(0.0, float(values.get("cpa_distance", danger_radius * 2.0)))
	if time_to_cpa > reaction_horizon or cpa_distance > danger_radius * 1.5:
		return 0.0
	var time_pressure := clamp01(1.0 - time_to_cpa / reaction_horizon)
	var miss_pressure := clamp01(1.0 - cpa_distance / danger_radius)
	var damage_pressure := clamp01(float(values.get("expected_damage_ratio", 0.0)))
	var maneuver_pressure := 1.0 - clamp01(float(values.get("maneuver_margin", 0.0)))
	var confidence := clamp01(float(values.get("confidence", 1.0)))
	return score100(confidence * (
		0.35 * time_pressure
		+ 0.30 * miss_pressure
		+ 0.20 * damage_pressure
		+ 0.15 * maneuver_pressure
	))


static func shore_risk_score(values: Dictionary) -> float:
	var clearance_pressure := 1.0 - clamp01(float(values.get("clearance_ratio", 1.0)))
	var future_collision := clamp01(float(values.get("future_collision", 0.0)))
	var turn_pressure := 1.0 - clamp01(float(values.get("turn_room_ratio", 1.0)))
	var current_pressure := clamp01(float(values.get("current_toward_shore", 0.0)))
	return score100(
		0.35 * clearance_pressure
		+ 0.30 * future_collision
		+ 0.20 * turn_pressure
		+ 0.15 * current_pressure
	)


static func cover_score(values: Dictionary) -> float:
	if not bool(values.get("reachable", true)) or int(values.get("exit_count", 1)) <= 0:
		return 0.0
	return score100(
		0.23 * clamp01(float(values.get("shell_block", 0.0)))
		+ 0.18 * clamp01(float(values.get("line_of_sight_break", 0.0)))
		+ 0.16 * clamp01(float(values.get("exit_quality", 0.0)))
		+ 0.15 * clamp01(float(values.get("weapon_access", 0.0)))
		+ 0.12 * clamp01(float(values.get("turn_room", 0.0)))
		+ 0.09 * clamp01(float(values.get("distance_fit", 0.0)))
		+ 0.07 * clamp01(float(values.get("group_support", 0.0)))
		- 0.22 * clamp01(float(values.get("dead_end_risk", 0.0)))
		- 0.16 * clamp01(float(values.get("depth_risk", 0.0)))
	)


static func facility_capture_score(values: Dictionary) -> float:
	if not bool(values.get("known", true)) or not bool(values.get("seizable", true)) or not bool(values.get("path_valid", true)):
		return 0.0
	return score100(
		0.25 * clamp01(float(values.get("facility_value", 0.0)))
		+ 0.17 * clamp01(float(values.get("survival", 0.0)))
		+ 0.15 * clamp01(float(values.get("path_quality", 0.0)))
		+ 0.13 * clamp01(float(values.get("role_fit", 0.0)))
		+ 0.12 * clamp01(float(values.get("ownership_need", 0.0)))
		+ 0.10 * clamp01(float(values.get("followup_value", 0.0)))
		+ 0.08 * clamp01(float(values.get("time_margin", 0.0)))
		- 0.20 * clamp01(float(values.get("contest_pressure", 0.0)))
		- 0.15 * clamp01(float(values.get("assignment_saturation", 0.0)))
	)


static func facility_defense_score(values: Dictionary) -> float:
	if not bool(values.get("known", true)) or not bool(values.get("owned", true)) or not bool(values.get("path_valid", true)):
		return 0.0
	return score100(
		0.27 * clamp01(float(values.get("facility_value", 0.0)))
		+ 0.25 * clamp01(float(values.get("capture_threat", 0.0)))
		+ 0.15 * clamp01(float(values.get("reach_quality", 0.0)))
		+ 0.12 * clamp01(float(values.get("role_fit", 0.0)))
		+ 0.11 * clamp01(float(values.get("ally_need", 0.0)))
		+ 0.10 * clamp01(float(values.get("defensive_position", 0.0)))
		- 0.15 * clamp01(float(values.get("local_disadvantage", 0.0)))
		- 0.10 * clamp01(float(values.get("assignment_saturation", 0.0)))
	)


static func detected_tactic_scores(values: Dictionary) -> Dictionary:
	var local_advantage := clamp01(float(values.get("local_advantage", 0.5)))
	var local_pressure := 1.0 - local_advantage
	var survival_pressure := 1.0 - clamp01(float(values.get("hp_safety", 1.0)))
	var attack := score100(
		0.24 * local_advantage
		+ 0.19 * clamp01(float(values.get("weapon_ready", 0.0)))
		+ 0.16 * clamp01(float(values.get("target_opportunity", 0.0)))
		+ 0.15 * clamp01(float(values.get("skill_attack_value", 0.0)))
		+ 0.14 * clamp01(float(values.get("group_followup", 0.0)))
		+ 0.12 * clamp01(float(values.get("attack_route_quality", 0.0)))
		- 0.15 * clamp01(float(values.get("exposure_risk", 0.0)))
	)
	var defend := score100(
		0.25 * local_pressure
		+ 0.21 * clamp01(float(values.get("objective_defense", 0.0)))
		+ 0.18 * clamp01(float(values.get("cover_quality", 0.0)))
		+ 0.16 * survival_pressure
		+ 0.11 * clamp01(float(values.get("cooldown_need", 0.0)))
		+ 0.09 * clamp01(float(values.get("group_support", 0.0)))
	)
	var kite := score100(
		0.23 * clamp01(float(values.get("range_advantage", 0.0)))
		+ 0.19 * clamp01(float(values.get("speed_advantage", 0.0)))
		+ 0.19 * local_pressure
		+ 0.16 * clamp01(float(values.get("exit_quality", 0.0)))
		+ 0.13 * survival_pressure
		+ 0.10 * clamp01(float(values.get("weapon_cycle_value", 0.0)))
	)
	return {"Attack": attack, "Defend": defend, "Kite": kite}


static func choose_highest(scores: Dictionary) -> Dictionary:
	var selected_id := ""
	var selected_score := -1.0
	var ids: Array = scores.keys()
	ids.sort()
	for score_id in ids:
		var value := float(scores[score_id])
		if value > selected_score + EPSILON:
			selected_id = str(score_id)
			selected_score = value
	return {"id": selected_id, "score": maxf(0.0, selected_score)}


static func mode_scores(values: Dictionary) -> Dictionary:
	var hp_safety := clamp01(float(values.get("hp_safety", 1.0)))
	var low_hp := 1.0 - hp_safety
	var pressure := clamp01(float(values.get("local_pressure", 0.0)))
	var boundary_safety := 1.0 - clamp01(float(values.get("boundary_risk", 0.0)))
	return {
		"DisengageRegroup": score100(0.34 * low_hp + 0.25 * pressure + 0.21 * (1.0 - boundary_safety) + 0.20 * clamp01(float(values.get("exit_quality", 0.0)))),
		"ReconAvoid": score100(0.34 * clamp01(float(values.get("vision_need", 0.0))) + 0.24 * hp_safety + 0.20 * boundary_safety + 0.12 * clamp01(float(values.get("cohesion", 0.0))) + 0.10 * clamp01(float(values.get("recon_route_quality", 0.0)))),
		"VanguardLine": score100(0.28 * clamp01(float(values.get("valid_target", 0.0))) + 0.22 * hp_safety + 0.18 * clamp01(float(values.get("cohesion", 0.0))) + 0.17 * (1.0 - pressure) + 0.15 * clamp01(float(values.get("weapon_ready", 0.0)))),
		"TorpedoFlank": score100(0.26 * clamp01(float(values.get("flank_quality", 0.0))) + 0.22 * clamp01(float(values.get("weapon_ready", 0.0))) + 0.20 * clamp01(float(values.get("high_value_exposed", 0.0))) + 0.14 * hp_safety + 0.10 * boundary_safety + 0.08 * clamp01(float(values.get("group_fixing_target", 0.0)))),
		"GunlineSupport": score100(0.25 * clamp01(float(values.get("valid_target", 0.0))) + 0.21 * clamp01(float(values.get("weapon_ready", 0.0))) + 0.18 * clamp01(float(values.get("cohesion", 0.0))) + 0.14 * boundary_safety + 0.12 * hp_safety + 0.10 * clamp01(float(values.get("firing_lane_quality", 0.0)))),
		"CarrierStandoff": score100(0.25 * (1.0 - pressure) + 0.21 * boundary_safety + 0.18 * hp_safety + 0.14 * clamp01(float(values.get("valid_target", 0.0))) + 0.12 * clamp01(float(values.get("exit_quality", 0.0))) + 0.10 * clamp01(float(values.get("escort_coverage", 0.0)))),
		"EscortScreen": score100(0.28 * clamp01(float(values.get("protectee_threat", 0.0))) + 0.20 * clamp01(float(values.get("intercept_quality", 0.0))) + 0.18 * clamp01(float(values.get("cohesion", 0.0))) + 0.14 * hp_safety + 0.12 * clamp01(float(values.get("defensive_skill_ready", 0.0))) + 0.08 * boundary_safety),
	}


static func attack_window_score(values: Dictionary) -> float:
	if not bool(values.get("visible", true)) or not bool(values.get("weapon_legal", true)) or not bool(values.get("path_clear", true)):
		return 0.0
	return score100(
		0.19 * clamp01(float(values.get("target_value", 0.0)))
		+ 0.16 * clamp01(float(values.get("hit_quality", 0.0)))
		+ 0.14 * clamp01(float(values.get("weapon_ready", 0.0)))
		+ 0.14 * clamp01(float(values.get("expected_damage", 0.0)))
		+ 0.13 * clamp01(float(values.get("skill_synergy", 0.0)))
		+ 0.12 * clamp01(float(values.get("group_sync", 0.0)))
		+ 0.07 * clamp01(float(values.get("kill_opportunity", 0.0)))
		+ 0.05 * clamp01(float(values.get("objective_relevance", 0.0)))
		- 0.12 * clamp01(float(values.get("exposure_risk", 0.0)))
		- 0.10 * clamp01(float(values.get("overkill", 0.0)))
		- 0.08 * clamp01(float(values.get("friendly_risk", 0.0)))
	)


static func fire_threshold(discipline: String, under_threat: bool = false, emergency: bool = false) -> float:
	match discipline:
		"SelfDefense":
			return 48.0 if under_threat else 101.0
		"HoldUntilWindow":
			return 68.0
		"Silent":
			return 72.0 if emergency else 101.0
		_:
			return 54.0


static func should_fire(values: Dictionary, discipline: String, under_threat: bool = false, emergency: bool = false) -> Dictionary:
	var score := attack_window_score(values)
	var threshold := fire_threshold(discipline, under_threat, emergency)
	return {"fire": score >= threshold, "score": score, "threshold": threshold}


static func skill_expected_value(values: Dictionary) -> float:
	if not bool(values.get("legal", true)) or not bool(values.get("ready", true)):
		return 0.0
	return score100(
		0.24 * clamp01(float(values.get("direct_value", 0.0)))
		+ 0.18 * clamp01(float(values.get("coverage_value", 0.0)))
		+ 0.18 * clamp01(float(values.get("attack_synergy", 0.0)))
		+ 0.15 * clamp01(float(values.get("defense_urgency", 0.0)))
		+ 0.13 * clamp01(float(values.get("objective_value", 0.0)))
		+ 0.12 * clamp01(float(values.get("group_followup", 0.0)))
		- 0.17 * clamp01(float(values.get("waste_risk", 0.0)))
		- 0.10 * clamp01(float(values.get("exposure_cost", 0.0)))
	)


static func coordination_score(values: Dictionary) -> float:
	return score100(
		0.28 * clamp01(float(values.get("readiness_alignment", 0.0)))
		+ 0.23 * clamp01(float(values.get("target_window", 0.0)))
		+ 0.19 * clamp01(float(values.get("skill_synergy", 0.0)))
		+ 0.14 * clamp01(float(values.get("crossfire_quality", 0.0)))
		+ 0.10 * clamp01(float(values.get("reservation_fit", 0.0)))
		+ 0.06 * clamp01(float(values.get("objective_timing", 0.0)))
		- 0.20 * clamp01(float(values.get("overkill", 0.0)))
	)


static func route_utility(values: Dictionary) -> float:
	if not bool(values.get("legal", true)):
		return 0.0
	return score100(
		0.24 * clamp01(float(values.get("time_efficiency", 0.0)))
		+ 0.17 * clamp01(float(values.get("depth_safety", 0.0)))
		+ 0.16 * clamp01(float(values.get("threat_safety", 0.0)))
		+ 0.14 * clamp01(float(values.get("exposure_safety", 0.0)))
		+ 0.11 * clamp01(float(values.get("turn_room", 0.0)))
		+ 0.08 * clamp01(float(values.get("congestion_safety", 0.0)))
		+ 0.06 * clamp01(float(values.get("formation_fit", 0.0)))
		+ 0.04 * clamp01(float(values.get("objective_fit", 0.0)))
	)


static func hierarchical_decision(values: Dictionary) -> Dictionary:
	if not bool(values.get("domain_legal", true)):
		return {"layer": "DomainConstraint", "action": "Reject", "score": 100.0}
	var immediate: Dictionary = values.get("immediate_scores", {})
	var immediate_choice := choose_highest(immediate)
	if float(immediate_choice["score"]) >= float(values.get("immediate_threshold", 65.0)):
		return {"layer": "ImmediateSurvival", "action": immediate_choice["id"], "score": immediate_choice["score"]}
	var mission: Dictionary = values.get("mission_scores", {})
	var mission_choice := choose_highest(mission)
	if float(mission_choice["score"]) >= float(values.get("mission_threshold", 60.0)):
		return {"layer": "LevelObjective", "action": mission_choice["id"], "score": mission_choice["score"]}
	var group: Dictionary = values.get("group_scores", {})
	var group_choice := choose_highest(group)
	if float(group_choice["score"]) >= float(values.get("group_threshold", 58.0)):
		return {"layer": "GroupDuty", "action": group_choice["id"], "score": group_choice["score"]}
	var mode_choice := choose_highest(values.get("mode_scores", {}))
	return {"layer": "StrategicMode", "action": mode_choice["id"], "score": mode_choice["score"]}


static func switch_with_hysteresis(values: Dictionary) -> Dictionary:
	var current_id := str(values.get("current_id", ""))
	var candidate_id := str(values.get("candidate_id", ""))
	var confirmations := int(values.get("confirmations", 0))
	if candidate_id.is_empty() or candidate_id == current_id:
		return {"switch": false, "selected_id": current_id, "confirmations": 0, "reason": "NO_BETTER_CANDIDATE"}
	if bool(values.get("emergency", false)) or not bool(values.get("current_legal", true)):
		return {"switch": true, "selected_id": candidate_id, "confirmations": 0, "reason": "EMERGENCY_OR_INVALID"}
	if float(values.get("elapsed_in_current", 0.0)) < float(values.get("minimum_hold", 4.0)):
		return {"switch": false, "selected_id": current_id, "confirmations": 0, "reason": "MINIMUM_HOLD"}
	var current_score := float(values.get("current_score", 0.0))
	var candidate_score := float(values.get("candidate_score", 0.0))
	if candidate_score < float(values.get("enter_threshold", 60.0)) or candidate_score < current_score + float(values.get("switch_margin", 15.0)):
		return {"switch": false, "selected_id": current_id, "confirmations": 0, "reason": "INSUFFICIENT_MARGIN"}
	confirmations += 1
	if confirmations < int(values.get("required_confirmations", 2)):
		return {"switch": false, "selected_id": current_id, "confirmations": confirmations, "reason": "AWAITING_CONFIRMATION"}
	return {"switch": true, "selected_id": candidate_id, "confirmations": 0, "reason": "CONFIRMED"}


static func intercept_point(origin: Vector2, target_position: Vector2, target_velocity: Vector2, projectile_speed: float, maximum_time: float = 12.0) -> Dictionary:
	if projectile_speed <= EPSILON:
		return {"valid": false, "time": 0.0, "position": target_position}
	var relative := target_position - origin
	var a := target_velocity.length_squared() - projectile_speed * projectile_speed
	var b := 2.0 * relative.dot(target_velocity)
	var c := relative.length_squared()
	var time := -1.0
	if absf(a) <= EPSILON:
		if b < -EPSILON:
			time = -c / b
	else:
		var discriminant := b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var root := sqrt(discriminant)
			var first := (-b - root) / (2.0 * a)
			var second := (-b + root) / (2.0 * a)
			for candidate in [first, second]:
				if candidate > EPSILON and (time < 0.0 or candidate < time):
					time = candidate
	if time <= 0.0 or time > maximum_time:
		return {"valid": false, "time": maxf(0.0, time), "position": target_position}
	return {"valid": true, "time": time, "position": target_position + target_velocity * time}
