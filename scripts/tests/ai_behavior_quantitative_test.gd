extends SceneTree

const AIModel = preload("res://scripts/application/ai/ai_quantitative_model.gd")

var failures: Array[String] = []
var checks := 0
var scenario_results: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_immediate_survival()
	_test_objective_tasks()
	_test_detected_tactics()
	_test_strategic_modes()
	_test_predictive_attack_and_fire_control()
	_test_skill_and_group_coordination()
	_test_nearshore_cover_and_routes()
	_test_hierarchical_priority()
	_test_switch_hysteresis()
	_test_target_selection_and_information_fairness()
	_test_player_assist_policy()
	for result in scenario_results:
		print(result)
	if failures.is_empty():
		print("PASS: %d AI quantitative checks across %d scenario groups" % [checks, 11])
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d AI quantitative checks" % [failures.size(), checks])
		quit(1)


func _test_immediate_survival() -> void:
	var imminent := AIModel.torpedo_threat_score({
		"visible": true, "approaching": true, "reaction_horizon": 6.0,
		"time_to_cpa": 1.0, "danger_radius": 60.0, "cpa_distance": 10.0,
		"expected_damage_ratio": 0.8, "maneuver_margin": 0.2,
	})
	var harmless := AIModel.torpedo_threat_score({
		"visible": true, "approaching": true, "reaction_horizon": 6.0,
		"time_to_cpa": 3.0, "danger_radius": 60.0, "cpa_distance": 88.0,
		"expected_damage_ratio": 0.1, "maneuver_margin": 1.0,
	})
	var hidden := AIModel.torpedo_threat_score({"visible": false, "approaching": true, "time_to_cpa": 0.5, "cpa_distance": 0.0})
	var shore := AIModel.shore_risk_score({"clearance_ratio": 0.12, "future_collision": 1.0, "turn_room_ratio": 0.15, "current_toward_shore": 0.8})
	_check(imminent >= 65.0, "imminent visible torpedo triggers survival interrupt")
	_check(harmless < 35.0, "wide torpedo pass does not cause excessive evasion")
	_check(is_zero_approx(hidden), "unseen torpedo cannot influence normal AI")
	_check(shore >= 75.0, "near-shore projected collision triggers shore escape")
	_record("survival", {"torpedo_imminent": imminent, "torpedo_wide_pass": harmless, "shore_risk": shore})


func _test_objective_tasks() -> void:
	var safe_capture := AIModel.facility_capture_score({
		"facility_value": 0.95, "survival": 0.9, "path_quality": 0.9,
		"role_fit": 0.9, "ownership_need": 1.0, "followup_value": 0.8,
		"time_margin": 0.8, "contest_pressure": 0.1, "assignment_saturation": 0.0,
	})
	var contested_capture := AIModel.facility_capture_score({
		"facility_value": 0.8, "survival": 0.3, "path_quality": 0.5,
		"role_fit": 0.7, "ownership_need": 0.8, "followup_value": 0.5,
		"time_margin": 0.3, "contest_pressure": 1.0, "assignment_saturation": 0.8,
	})
	var defense := AIModel.facility_defense_score({
		"facility_value": 1.0, "capture_threat": 1.0, "reach_quality": 0.9,
		"role_fit": 0.85, "ally_need": 0.9, "defensive_position": 0.9,
		"local_disadvantage": 0.2, "assignment_saturation": 0.0,
	})
	_check(safe_capture >= 75.0, "safe high-value facility is worth capturing")
	_check(contested_capture < 50.0, "isolated contested capture is rejected")
	_check(defense >= 75.0, "threatened high-value owned facility triggers defense")
	_record("objective", {"safe_capture": safe_capture, "contested_capture": contested_capture, "facility_defense": defense})


func _test_detected_tactics() -> void:
	var favorable := AIModel.detected_tactic_scores({
		"local_advantage": 0.9, "hp_safety": 0.9, "weapon_ready": 1.0,
		"target_opportunity": 0.9, "skill_attack_value": 0.8, "group_followup": 0.9,
		"attack_route_quality": 0.9, "exposure_risk": 0.2,
		"range_advantage": 0.2, "speed_advantage": 0.2, "exit_quality": 0.5,
	})
	var outgunned := AIModel.detected_tactic_scores({
		"local_advantage": 0.15, "hp_safety": 0.35, "weapon_ready": 0.4,
		"target_opportunity": 0.3, "skill_attack_value": 0.2, "group_followup": 0.2,
		"attack_route_quality": 0.3, "exposure_risk": 0.9,
		"range_advantage": 0.9, "speed_advantage": 0.9, "exit_quality": 0.95,
		"weapon_cycle_value": 0.8,
	})
	var holding := AIModel.detected_tactic_scores({
		"local_advantage": 0.4, "hp_safety": 0.8, "weapon_ready": 0.3,
		"target_opportunity": 0.3, "objective_defense": 1.0, "cover_quality": 0.95,
		"cooldown_need": 0.7, "group_support": 0.9,
		"range_advantage": 0.1, "speed_advantage": 0.1, "exit_quality": 0.3,
	})
	_check(AIModel.choose_highest(favorable)["id"] == "Attack", "detected unit attacks with local advantage and a weapon window")
	_check(AIModel.choose_highest(outgunned)["id"] == "Kite", "detected fast ranged unit kites when outgunned")
	_check(AIModel.choose_highest(holding)["id"] == "Defend", "detected defender holds cover around a critical objective")
	_record("detected_tactics", {"favorable": favorable, "outgunned": outgunned, "holding": holding})


func _test_strategic_modes() -> void:
	var recon := AIModel.mode_scores({"hp_safety": 0.9, "vision_need": 1.0, "boundary_risk": 0.0, "cohesion": 0.8, "recon_route_quality": 0.9})
	var flank := AIModel.mode_scores({"hp_safety": 0.85, "local_pressure": 0.2, "weapon_ready": 1.0, "flank_quality": 1.0, "high_value_exposed": 1.0, "group_fixing_target": 0.9, "boundary_risk": 0.1})
	var disengage := AIModel.mode_scores({"hp_safety": 0.05, "local_pressure": 1.0, "boundary_risk": 0.9, "exit_quality": 0.9})
	var escort := AIModel.mode_scores({"hp_safety": 0.8, "protectee_threat": 1.0, "intercept_quality": 0.95, "cohesion": 0.9, "defensive_skill_ready": 1.0})
	_check(AIModel.choose_highest(recon)["id"] == "ReconAvoid", "vision gap selects recon-avoid mode")
	_check(AIModel.choose_highest(flank)["id"] == "TorpedoFlank", "ready torpedo unit exploits a fixed high-value target")
	_check(AIModel.choose_highest(disengage)["id"] == "DisengageRegroup", "critical survival pressure selects disengage")
	_check(AIModel.choose_highest(escort)["id"] == "EscortScreen", "protectee threat selects escort screen")
	_record("modes", {"recon": AIModel.choose_highest(recon), "flank": AIModel.choose_highest(flank), "disengage": AIModel.choose_highest(disengage), "escort": AIModel.choose_highest(escort)})


func _test_predictive_attack_and_fire_control() -> void:
	var intercept := AIModel.intercept_point(Vector2.ZERO, Vector2(300.0, 0.0), Vector2(0.0, 30.0), 120.0)
	_check(bool(intercept["valid"]), "predictive attack finds a legal constant-velocity intercept")
	_check((intercept["position"] as Vector2).y > 70.0, "intercept leads the moving target instead of aiming at current position")
	var base_window := {
		"target_value": 0.85, "hit_quality": 0.75, "weapon_ready": 1.0,
		"expected_damage": 0.75, "skill_synergy": 0.0, "group_sync": 0.5,
		"kill_opportunity": 0.5, "objective_relevance": 0.5, "exposure_risk": 0.35,
		"overkill": 0.1, "friendly_risk": 0.0,
	}
	var without_skill := AIModel.should_fire(base_window, "HoldUntilWindow")
	var combo_window := base_window.duplicate(true)
	combo_window["skill_synergy"] = 1.0
	combo_window["group_sync"] = 0.9
	var with_skill := AIModel.should_fire(combo_window, "HoldUntilWindow")
	var silent := AIModel.should_fire(combo_window, "Silent")
	var emergency_silent := AIModel.should_fire(combo_window, "Silent", true, true)
	_check(not bool(without_skill["fire"]) and bool(with_skill["fire"]), "expected skill and group gain opens a held attack window")
	_check(not bool(silent["fire"]), "silent discipline preserves concealment outside emergency")
	_check(bool(emergency_silent["fire"]), "silent discipline permits a high-value emergency self-defense shot")
	_record("fire_control", {"intercept_time": intercept["time"], "without_skill": without_skill, "with_skill": with_skill, "silent": silent, "emergency_silent": emergency_silent})


func _test_skill_and_group_coordination() -> void:
	var wasteful := AIModel.skill_expected_value({
		"direct_value": 0.3, "coverage_value": 0.2, "attack_synergy": 0.1,
		"defense_urgency": 0.0, "objective_value": 0.2, "group_followup": 0.1,
		"waste_risk": 0.9, "exposure_cost": 0.4,
	})
	var coordinated := AIModel.skill_expected_value({
		"direct_value": 0.8, "coverage_value": 0.9, "attack_synergy": 1.0,
		"defense_urgency": 0.2, "objective_value": 0.8, "group_followup": 1.0,
		"waste_risk": 0.05, "exposure_cost": 0.1,
	})
	var group_window := AIModel.coordination_score({
		"readiness_alignment": 0.95, "target_window": 0.9, "skill_synergy": 1.0,
		"crossfire_quality": 0.85, "reservation_fit": 0.9, "objective_timing": 0.8,
		"overkill": 0.1,
	})
	var overkill_window := AIModel.coordination_score({
		"readiness_alignment": 0.8, "target_window": 0.8, "skill_synergy": 0.7,
		"crossfire_quality": 0.7, "reservation_fit": 0.1, "objective_timing": 0.5,
		"overkill": 1.0,
	})
	_check(wasteful < 40.0, "low-yield skill is held")
	_check(coordinated >= 70.0, "high-yield coordinated skill is released")
	_check(group_window >= 75.0, "aligned weapons and skills create a coordinated attack")
	_check(overkill_window < group_window - 20.0, "overkill reservation suppresses redundant group fire")
	_record("coordination", {"wasteful_skill": wasteful, "coordinated_skill": coordinated, "group_window": group_window, "overkill_window": overkill_window})


func _test_nearshore_cover_and_routes() -> void:
	var usable_cover := AIModel.cover_score({
		"shell_block": 1.0, "line_of_sight_break": 0.9, "exit_quality": 0.85,
		"weapon_access": 0.75, "turn_room": 0.9, "distance_fit": 0.8,
		"group_support": 0.7, "exit_count": 2,
	})
	var trap_cover := AIModel.cover_score({
		"shell_block": 1.0, "line_of_sight_break": 1.0, "exit_quality": 0.1,
		"weapon_access": 0.2, "turn_room": 0.1, "distance_fit": 0.6,
		"dead_end_risk": 1.0, "depth_risk": 0.8, "exit_count": 1,
	})
	var direct_route := AIModel.route_utility({
		"time_efficiency": 1.0, "depth_safety": 0.8, "threat_safety": 0.1,
		"exposure_safety": 0.2, "turn_room": 0.8, "congestion_safety": 0.8,
		"formation_fit": 0.5, "objective_fit": 0.8,
	})
	var covered_route := AIModel.route_utility({
		"time_efficiency": 0.65, "depth_safety": 1.0, "threat_safety": 0.95,
		"exposure_safety": 0.9, "turn_room": 0.85, "congestion_safety": 0.8,
		"formation_fit": 0.8, "objective_fit": 0.8,
	})
	var broadside_flank := AIModel.flank_quality({
		"bearing_from_target": PI * 0.5, "target_heading": 0.0,
		"crossfire_angle": PI * 0.5, "distance_fit": 0.9, "exit_quality": 0.8,
	})
	var bow_attack := AIModel.flank_quality({
		"bearing_from_target": 0.0, "target_heading": 0.0,
		"crossfire_angle": 0.0, "distance_fit": 0.9, "exit_quality": 0.8,
	})
	var clear_lane := AIModel.firing_lane_quality({
		"weapon_legal": true, "path_clear": true, "arc_quality": 0.9,
		"range_fit": 0.85, "friendly_risk": 0.0, "sustain_quality": 0.8,
	})
	var blocked_lane := AIModel.firing_lane_quality({
		"weapon_legal": true, "path_clear": false, "arc_quality": 1.0,
		"range_fit": 1.0, "friendly_risk": 0.0, "sustain_quality": 1.0,
	})
	_check(usable_cover >= 70.0, "reachable multi-exit shore cover is usable")
	_check(trap_cover < 35.0, "dead-end shallow cover is rejected")
	_check(covered_route > direct_route + 15.0, "safer covered route beats a shorter exposed route")
	_check(broadside_flank > bow_attack + 40.0, "real target aspect and crossfire geometry favor a broadside flank over a bow chase")
	_check(clear_lane >= 80.0 and is_zero_approx(blocked_lane), "firing-lane quality rewards a clear sustainable arc and hard-rejects blocked shell paths")
	_record("nearshore", {"usable_cover": usable_cover, "trap_cover": trap_cover, "direct_route": direct_route, "covered_route": covered_route, "broadside_flank": broadside_flank, "bow_attack": bow_attack, "clear_lane": clear_lane, "blocked_lane": blocked_lane})


func _test_hierarchical_priority() -> void:
	var emergency := AIModel.hierarchical_decision({
		"immediate_scores": {"TorpedoEvasion": 86.0},
		"mission_scores": {"CaptureFacility": 92.0},
		"group_scores": {"EscortFlagship": 80.0},
		"mode_scores": {"TorpedoFlank": 90.0},
	})
	var mission := AIModel.hierarchical_decision({
		"immediate_scores": {"TorpedoEvasion": 20.0},
		"mission_scores": {"DefendFacility": 82.0},
		"group_scores": {"FocusFire": 78.0},
		"mode_scores": {"FlagshipRaid": 90.0},
	})
	var group := AIModel.hierarchical_decision({
		"immediate_scores": {}, "mission_scores": {"Patrol": 30.0},
		"group_scores": {"EscortFlagship": 72.0}, "mode_scores": {"GunlineSupport": 85.0},
	})
	_check(emergency["layer"] == "ImmediateSurvival" and emergency["action"] == "TorpedoEvasion", "survival interrupt overrides objective and mode")
	_check(mission["layer"] == "LevelObjective" and mission["action"] == "DefendFacility", "critical objective overrides group focus and raid mode")
	_check(group["layer"] == "GroupDuty" and group["action"] == "EscortFlagship", "group duty overrides normal strategic mode")
	_record("hierarchy", {"emergency": emergency, "mission": mission, "group": group})


func _test_switch_hysteresis() -> void:
	var held := AIModel.switch_with_hysteresis({
		"current_id": "ReconAvoid", "candidate_id": "TorpedoFlank",
		"current_score": 45.0, "candidate_score": 82.0,
		"elapsed_in_current": 2.0, "minimum_hold": 4.0,
	})
	var first_confirmation := AIModel.switch_with_hysteresis({
		"current_id": "ReconAvoid", "candidate_id": "TorpedoFlank",
		"previous_candidate_id": "",
		"current_score": 45.0, "candidate_score": 82.0,
		"elapsed_in_current": 5.0, "confirmations": 0,
	})
	var confirmed := AIModel.switch_with_hysteresis({
		"current_id": "ReconAvoid", "candidate_id": "TorpedoFlank",
		"previous_candidate_id": "TorpedoFlank",
		"current_score": 44.0, "candidate_score": 84.0,
		"elapsed_in_current": 5.5, "confirmations": first_confirmation["confirmations"],
	})
	var emergency := AIModel.switch_with_hysteresis({
		"current_id": "TorpedoFlank", "candidate_id": "DisengageRegroup",
		"current_score": 80.0, "candidate_score": 72.0,
		"elapsed_in_current": 0.5, "emergency": true,
	})
	var changed_candidate := AIModel.switch_with_hysteresis({
		"current_id": "ReconAvoid", "candidate_id": "GunlineSupport",
		"previous_candidate_id": "TorpedoFlank",
		"current_score": 40.0, "candidate_score": 82.0,
		"elapsed_in_current": 6.0, "confirmations": first_confirmation["confirmations"],
	})
	_check(not bool(held["switch"]) and held["reason"] == "MINIMUM_HOLD", "mode remains stable during minimum hold")
	_check(not bool(first_confirmation["switch"]) and int(first_confirmation["confirmations"]) == 1, "single score spike cannot switch mode")
	_check(bool(confirmed["switch"]) and confirmed["selected_id"] == "TorpedoFlank", "two consecutive confirmations switch to the better mode")
	_check(bool(emergency["switch"]) and emergency["selected_id"] == "DisengageRegroup", "emergency survival bypasses mode hold and margin")
	_check(not bool(changed_candidate["switch"]) and int(changed_candidate["confirmations"]) == 1, "changing the winning candidate resets consecutive mode confirmation")
	_record("hysteresis", {"held": held, "first": first_confirmation, "confirmed": confirmed, "emergency": emergency, "changed_candidate": changed_candidate})


func _test_target_selection_and_information_fairness() -> void:
	var flagship := AIModel.target_score({
		"mission_value": 1.0, "threat": 0.5, "weapon_fit": 0.9, "range_fit": 0.8,
		"kill_opportunity": 0.4, "focus_fire": 0.8, "objective_relevance": 1.0,
		"pursuit_cost": 0.2, "overkill": 0.1,
	})
	var overreserved := AIModel.target_score({
		"mission_value": 1.0, "threat": 0.5, "weapon_fit": 0.9, "range_fit": 0.8,
		"kill_opportunity": 0.9, "focus_fire": 1.0, "objective_relevance": 1.0,
		"pursuit_cost": 0.2, "overkill": 1.0,
	})
	var alternate := AIModel.target_score({
		"mission_value": 0.75, "threat": 0.9, "weapon_fit": 0.9, "range_fit": 0.9,
		"kill_opportunity": 0.5, "focus_fire": 0.4, "objective_relevance": 0.8,
		"pursuit_cost": 0.1, "overkill": 0.0,
	})
	var hidden := AIModel.target_score({"visible": false, "mission_value": 1.0, "threat": 1.0, "weapon_fit": 1.0})
	_check(flagship >= 70.0, "unreserved flagship remains a high-value target")
	_check(alternate > overreserved, "overkill reservation redirects later attackers to a useful alternate")
	_check(is_zero_approx(hidden), "hidden real-time enemy state cannot enter attack scoring")
	_record("targets", {"flagship": flagship, "overreserved": overreserved, "alternate": alternate, "hidden": hidden})


func _test_player_assist_policy() -> void:
	var defaults := AIModel.player_control_defaults()
	_check(not bool(defaults["movement_assist_enabled"]), "player movement assist defaults off")
	_check(bool(defaults["secondary_auto_fire_enabled"]), "player secondary auto fire defaults on")
	_check(not bool(defaults["primary_auto_fire_enabled"]) and not bool(defaults["skill_auto_cast_enabled"]), "player primary and skill automation default off")

	var local_target := {
		"immediate_threat": 0.8, "weapon_fit": 0.9, "range_fit": 0.75,
		"kill_opportunity": 0.4, "turn_cost": 0.2,
	}
	var polluted_target := local_target.duplicate(true)
	polluted_target.merge({"mission_value": 1.0, "flagship_value": 1.0, "facility_value": 1.0, "weather_advantage": 1.0}, true)
	var target_score := AIModel.player_assist_target_score(local_target)
	_check(is_equal_approx(target_score, AIModel.player_assist_target_score(polluted_target)), "player assist target ignores mission, flagship, facility, and weather strategy")

	var local_tactic := {
		"local_advantage": 0.85, "hp_safety": 0.9, "weapon_ready": 1.0,
		"target_opportunity": 0.9, "movement_safety": 0.9, "exposure_risk": 0.2,
		"position_safety": 0.8, "range_advantage": 0.2, "speed_advantage": 0.2,
		"exit_quality": 0.5, "weapon_cycle_value": 0.7,
	}
	var polluted_tactic := local_tactic.duplicate(true)
	polluted_tactic.merge({"objective_defense": 1.0, "group_followup": 1.0, "skill_attack_value": 1.0, "weather_advantage": 1.0}, true)
	var local_scores := AIModel.player_assist_detected_tactic_scores(local_tactic)
	_check(local_scores == AIModel.player_assist_detected_tactic_scores(polluted_tactic), "player assist tactic ignores objective, group, skill, and weather inputs")

	var held := AIModel.player_assist_decision({
		"movement_assist_enabled": false, "visible_contact": true,
		"local_tactic": local_tactic, "mission_scores": {"CaptureFacility": 100.0},
		"group_scores": {"EscortFlagship": 100.0}, "mode_scores": {"TorpedoFlank": 100.0},
	})
	var emergency := AIModel.player_assist_decision({
		"movement_assist_enabled": false, "visible_contact": true,
		"immediate_scores": {"TorpedoEvasion": 84.0}, "local_tactic": local_tactic,
	})
	var route := AIModel.player_assist_decision({
		"movement_assist_enabled": true, "visible_contact": true,
		"has_player_route": true, "local_tactic": local_tactic,
	})
	var assisted := AIModel.player_assist_decision({
		"movement_assist_enabled": true, "visible_contact": true, "local_tactic": local_tactic,
	})
	var no_contact := AIModel.player_assist_decision({
		"movement_assist_enabled": true, "visible_contact": false,
		"mission_scores": {"CaptureFacility": 100.0}, "weather_advantage": 1.0,
	})
	_check(held["action"] == "HoldPosition", "disabled player movement assist ignores full-AI strategic inputs")
	_check(emergency["layer"] == "ImmediateSurvival" and emergency["action"] == "TorpedoEvasion", "player ship still performs minimum survival action with X off")
	_check(route["layer"] == "PlayerRoute", "player waypoints override ordinary assist movement")
	_check(assisted["layer"] == "DetectedTactic" and assisted["action"] == "Attack", "enabled player movement assist uses local detected tactic")
	_check(no_contact["action"] == "HoldPosition", "player assist does not patrol for objectives or weather without visible contact")

	var primary_window := {
		"target_value": 0.9, "hit_quality": 0.85, "weapon_ready": 1.0,
		"expected_damage": 0.8, "kill_opportunity": 0.6, "position_safety": 0.9,
		"exposure_risk": 0.2, "friendly_risk": 0.0,
	}
	var default_execution := AIModel.player_assist_execution(defaults, primary_window)
	var enabled_control := defaults.duplicate(true)
	enabled_control["primary_auto_fire_enabled"] = true
	enabled_control["skill_auto_cast_enabled"] = true
	var enabled_execution := AIModel.player_assist_execution(enabled_control, primary_window)
	_check(bool(default_execution["secondary_auto_fire"]) and not bool(default_execution["primary_auto_fire"]), "default player execution automates only secondary weapons")
	_check(bool(enabled_execution["primary_auto_fire"]), "V-enabled player assist fires a high-quality legal primary window")
	_check(not bool(default_execution["skill_auto_cast"]) and not bool(enabled_execution["skill_auto_cast"]), "player assist never enables automatic skills")
	_check(AIModel.fleet_toggle_target([true, false, true]), "mixed fleet toggle resolves to all enabled")
	_check(not AIModel.fleet_toggle_target([true, true, true]), "fully enabled fleet toggle resolves to all disabled")
	_record("player_assist", {
		"target_score": target_score, "tactic": AIModel.choose_highest(local_scores),
		"held": held, "emergency": emergency, "route": route, "assisted": assisted, "no_contact": no_contact,
		"default_execution": default_execution, "enabled_execution": enabled_execution,
	})


func _record(name: String, values: Dictionary) -> void:
	scenario_results.append("AI_SCENARIO %s %s" % [name, JSON.stringify(values)])


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
