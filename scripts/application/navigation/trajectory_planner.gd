extends RefCounted

const ShipMotionService = preload("res://scripts/domain/services/ship_motion_service.gd")

const NORMAL_INTERVAL := 1.0
const EMERGENCY_INTERVAL := 0.1
const NORMAL_HORIZON := 6.0
const EMERGENCY_HORIZON := 1.2
const NORMAL_CANDIDATE_LIMIT := 6
const EMERGENCY_BASE_LIMIT := 5
const EMERGENCY_TOTAL_LIMIT := 7
const FIXED_TICK_DELTA := 0.1
const NAVIGATION_MARGIN := 4.0
const CLEARANCE_COMFORT_BAND := 96.0

var diagnostics_enabled := false
var _diagnostics := {}


func configure_diagnostics(enabled: bool) -> void:
	diagnostics_enabled = enabled
	reset_diagnostics()


func reset_diagnostics() -> void:
	_diagnostics = {"motion_expansion_usec":0, "terrain_validation_usec":0, "environment_access_usec":0, "dynamic_validation_usec":0, "candidate_scoring_usec":0}


func diagnostics() -> Dictionary:
	return _diagnostics.duplicate(true)


func _record_diagnostic(key: String, started_usec: int) -> void:
	if diagnostics_enabled:
		_diagnostics[key] = int(_diagnostics.get(key, 0)) + Time.get_ticks_usec() - started_usec


func arrival_tolerance(radius: float) -> float:
	return maxf(12.0, radius * 0.5)


func plan_normal(motion_state: Dictionary, goal: Vector2, radius: float, movement_tags: Array, terrain_query, terrain_context, nearby_units: Array = [], final_approach: bool = false, next_goals: Array = [], prioritize_direct_player_motion: bool = false) -> Dictionary:
	var desired_direction := goal - (motion_state.get("position", Vector2.ZERO) as Vector2)
	var desired_angle := 0.0 if desired_direction == Vector2.ZERO else wrapf(desired_direction.angle() - float(motion_state.get("heading", 0.0)), -PI, PI)
	var preferred_turn := clampf(desired_angle / maxf(0.01, float(motion_state.get("turn_rate_limit", 0.01)) * NORMAL_HORIZON), -1.0, 1.0)
	var maximum_speed := maxf(0.01, float(motion_state.get("maximum_speed", 0.0)))
	var remaining_distance := maxf(0.0, desired_direction.length() - arrival_tolerance(radius))
	var approach_thrust := clampf(remaining_distance / (maximum_speed * NORMAL_HORIZON), 0.03, 1.0) if remaining_distance > 0.0 else 0.0
	var use_arrival_control := final_approach and desired_direction.length() <= maxf(maximum_speed * 1.5, arrival_tolerance(radius) * 4.0)
	var templates: Array = []
	if use_arrival_control:
		templates = [
			_constant_template(approach_thrust, preferred_turn, "arrival"),
			_constant_template(1.0, preferred_turn, "arrival_full"),
			_constant_template(0.45, preferred_turn, "arrival_slow"),
			_constant_template(0.0, preferred_turn, "arrival_brake"),
			_constant_template(approach_thrust, clampf(preferred_turn - 0.35, -1.0, 1.0), "arrival_left"),
			_constant_template(approach_thrust, clampf(preferred_turn + 0.35, -1.0, 1.0), "arrival_right"),
		]
	elif prioritize_direct_player_motion:
		# A player-authored point means "get there quickly". The primary template
		# keeps full propulsion, applies the maximum useful rudder until aligned,
		# and then commits to full-speed straight travel. Safety filtering may still
		# select a slower/wider alternative near land.
		templates = [
			{"controls":_turn_then_straight_controls(desired_angle, float(motion_state.get("turn_rate_limit", 0.0)), 1.0), "tag":"player_fast_direct"},
			{"controls":_turn_then_straight_controls(desired_angle, float(motion_state.get("turn_rate_limit", 0.0)), 0.75), "tag":"player_cruise_direct"},
			{"controls":_turn_then_straight_controls(desired_angle, float(motion_state.get("turn_rate_limit", 0.0)), 0.45), "tag":"player_slow_direct"},
			_constant_template(0.0, signf(desired_angle), "player_brake_turn"),
			_constant_template(1.0, clampf(signf(desired_angle) * 0.65, -1.0, 1.0), "player_wide_turn"),
			_constant_template(0.0, 0.0, "player_hold"),
		]
	else:
		templates = [
			_constant_template(1.0, preferred_turn, "cruise"),
			_constant_template(0.75, preferred_turn, "cruise_reduced"),
			_constant_template(0.45, preferred_turn, "slow_turn"),
			_constant_template(0.0, preferred_turn, "brake_turn"),
			_constant_template(0.75, clampf(preferred_turn - 0.35, -1.0, 1.0), "outer_left"),
			_constant_template(0.75, clampf(preferred_turn + 0.35, -1.0, 1.0), "outer_right"),
		]
	var recovery: Dictionary = motion_state.get("collision_recovery", {})
	var recovery_normal: Vector2 = recovery.get("normal", Vector2.ZERO)
	if recovery_normal.length_squared() > 0.001:
		var escape_angle := wrapf(recovery_normal.angle() - float(motion_state.get("heading", 0.0)), -PI, PI)
		var recovery_turn := signf(escape_angle)
		var recovery_templates: Array = [
			_constant_template(-0.25, recovery_turn, "collision_reverse_departure"),
			_constant_template(0.0, recovery_turn, "collision_brake_turn"),
			_constant_template(0.45, recovery_turn, "collision_forward_departure"),
		]
		recovery_templates.append_array(templates)
		templates = recovery_templates
	return _select_plan(templates.slice(0, NORMAL_CANDIDATE_LIMIT), motion_state, goal, NORMAL_HORIZON, radius, movement_tags, terrain_query, terrain_context, nearby_units, [], false, use_arrival_control, next_goals, prioritize_direct_player_motion)


func plan_emergency(motion_state: Dictionary, threats: Array, radius: float, movement_tags: Array, terrain_query, terrain_context, nearby_units: Array = [], extended: bool = false) -> Dictionary:
	var templates: Array = [
		_constant_template(0.5, 0.0, "emergency_forward"),
		_constant_template(0.5, -1.0, "emergency_left"),
		_constant_template(0.5, 1.0, "emergency_right"),
		_constant_template(0.0, -1.0, "emergency_brake_left"),
		_constant_template(0.0, 1.0, "emergency_brake_right"),
	]
	if extended:
		templates.append(_constant_template(1.0, 0.0, "emergency_full"))
		var contact := _constant_template(0.0, 0.0, "emergency_contact")
		contact["allow_controlled_contact"] = true
		templates.append(contact)
	var limit := EMERGENCY_TOTAL_LIMIT if extended else EMERGENCY_BASE_LIMIT
	return _select_plan(templates.slice(0, limit), motion_state, motion_state.get("position", Vector2.ZERO), EMERGENCY_HORIZON, radius, movement_tags, terrain_query, terrain_context, nearby_units, threats, true, false, [], false)


func _select_plan(templates: Array, initial_state: Dictionary, goal: Vector2, horizon: float, radius: float, movement_tags: Array, terrain_query, terrain_context, nearby_units: Array, threats: Array, emergency: bool, final_approach: bool, next_goals: Array, prioritize_direct_player_motion: bool) -> Dictionary:
	var candidates: Array = []
	var rejected_by_terrain := 0
	var segments_simulated := 0
	var evaluated_candidates := 0
	var context_sampler := Callable()
	if terrain_context != null:
		var context_varies: bool = not terrain_context.has_method("motion_context_varies_spatially") or bool(terrain_context.motion_context_varies_spatially())
		if context_varies and terrain_context.has_method("prediction_motion_context_varies"):
			context_varies = terrain_context.prediction_motion_context_varies(
				initial_state.get("position", Vector2.ZERO),
				float(initial_state.get("base_maximum_speed", initial_state.get("maximum_speed", 0.0))),
				horizon,
				absf(float(initial_state.get("speed", 0.0))),
			)
		if context_varies:
			context_sampler = Callable(terrain_context, "motion_context_at")
	for index in range(templates.size()):
		var template: Dictionary = templates[index]
		evaluated_candidates += 1
		var controls: Array = template.get("controls", [])
		var simulation := _simulate(initial_state, controls, horizon, radius, movement_tags, terrain_query, terrain_context, context_sampler, nearby_units, bool(template.get("allow_controlled_contact", false)))
		segments_simulated += int(simulation.get("segments_simulated", 0))
		if not bool(simulation.get("valid", false)):
			if str(simulation.get("reason_code", "")) == "TERRAIN_COLLISION": rejected_by_terrain += 1
			continue
		var scoring_started_usec := Time.get_ticks_usec() if diagnostics_enabled else 0
		var terminal_state: Dictionary = simulation.get("terminal_state", initial_state)
		var terminal: Vector2 = terminal_state.get("position", initial_state.get("position", Vector2.ZERO))
		var threat_score := _threat_safety(simulation.get("samples", []), terminal, threats, initial_state)
		var progress := 0.0
		var origin: Vector2 = initial_state.get("position", Vector2.ZERO)
		if not emergency:
			progress = origin.distance_to(goal) - terminal.distance_to(goal)
		var first_control: Dictionary = controls[0] if not controls.is_empty() else {}
		var previous_control: Dictionary = initial_state.get("previous_control", {})
		var turn_change := absf(float(first_control.get("turn_ratio", 0.0)) - float(previous_control.get("turn_ratio", 0.0)))
		var thrust_change := absf(float(first_control.get("thrust_ratio", 0.0)) - float(previous_control.get("thrust_ratio", 0.0)))
		var continuity := 1.0 - turn_change * 0.12 - thrust_change * 0.06
		var contact_cost := 0.4 if bool(simulation.get("controlled_contact", false)) else 0.0
		var stall_cost := 0.0
		if not emergency and origin.distance_to(goal) > arrival_tolerance(radius) and origin.distance_to(terminal) < 0.5:
			stall_cost = 1000.0
		var required_clearance := radius + NAVIGATION_MARGIN
		var minimum_clearance := float(simulation.get("minimum_clearance", required_clearance + CLEARANCE_COMFORT_BAND))
		var clearance_score := clampf((minimum_clearance - required_clearance) / CLEARANCE_COMFORT_BAND, 0.0, 1.0)
		var speed_ratio := absf(float(terminal_state.get("speed", 0.0))) / maxf(0.01, float(initial_state.get("maximum_speed", 0.0)))
		var comfort_clearance := required_clearance + CLEARANCE_COMFORT_BAND
		var near_shore_speed_cost := speed_ratio * speed_ratio * clampf((comfort_clearance - minimum_clearance) / comfort_clearance, 0.0, 1.0)
		var next_gate_alignment := _next_gate_alignment(terminal_state, next_goals)
		var direct_bonus := 80.0 if prioritize_direct_player_motion and str(template.get("tag", "")) == "player_fast_direct" else 0.0
		var recovery_tag := str(template.get("tag", ""))
		var recovery_bonus := 3000.0 if recovery_tag == "collision_reverse_departure" else (1800.0 if recovery_tag == "collision_forward_departure" else 0.0)
		var score := threat_score * 10000.0 + progress * 10.0 + clearance_score * 30.0 + next_gate_alignment * 80.0 + continuity + direct_bonus + recovery_bonus - near_shore_speed_cost * 600.0 - contact_cost - stall_cost
		candidates.append({"template":template, "simulation":simulation, "score":score, "index":index, "threat_safety":threat_score})
		_record_diagnostic("candidate_scoring_usec", scoring_started_usec)
		# Templates are ordered from the fastest intent-preserving control toward
		# slower/wider fallbacks. Once one has generous whole-trajectory clearance,
		# evaluating lower-priority controls adds CPU cost without adding safety.
		if not emergency and not final_approach and threats.is_empty() and minimum_clearance >= comfort_clearance and recovery_tag in ["cruise", "cruise_reduced", "slow_turn", "player_fast_direct", "player_cruise_direct", "player_slow_direct"]:
			break
	if candidates.is_empty():
		return {"ok":false, "reason_code":"NO_SAFE_TRAJECTORY", "candidate_count":evaluated_candidates, "segments_simulated":segments_simulated, "candidates_rejected_by_terrain":rejected_by_terrain}
	candidates.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]) if not is_equal_approx(float(a["score"]), float(b["score"])) else int(a["index"]) < int(b["index"]))
	var best: Dictionary = candidates[0]
	var best_template: Dictionary = best["template"]
	var best_simulation: Dictionary = best["simulation"]
	var commit_duration := EMERGENCY_INTERVAL if emergency else NORMAL_INTERVAL
	return {
		"ok":true,
		"controls":_controls_for_commit(best_template.get("controls", []), commit_duration),
		"prediction_controls":best_template.get("controls", []).duplicate(true),
		"predicted_samples":best_simulation.get("samples", []),
		"controlled_contact":best_simulation.get("controlled_contact", false),
		"threat_safety":best["threat_safety"],
		"candidate_count":evaluated_candidates,
		"candidate_id":str(best_template.get("tag", best["index"])),
		"candidate_rank":int(best["index"]) + 1,
		"valid_candidate_count":candidates.size(),
		"minimum_clearance":best_simulation.get("minimum_clearance", 0.0),
		"segments_simulated":segments_simulated,
		"candidates_rejected_by_terrain":rejected_by_terrain,
	}


func _simulate(initial_state: Dictionary, controls: Array, horizon: float, radius: float, movement_tags: Array, terrain_query, terrain_context, context_sampler: Callable, nearby_units: Array, allow_controlled_contact: bool) -> Dictionary:
	var motion_started_usec := Time.get_ticks_usec() if diagnostics_enabled else 0
	var samples := ShipMotionService.simulate_control_sequence(initial_state, controls, FIXED_TICK_DELTA, horizon, context_sampler)
	_record_diagnostic("motion_expansion_usec", motion_started_usec)
	if samples.is_empty():
		return {"valid":false, "reason_code":"EMPTY_SIMULATION", "segments_simulated":0}
	var controlled_contact := false
	var minimum_clearance := INF
	var exact_segment_checks := 0
	var field_cells_visited := 0
	var recovery: Dictionary = initial_state.get("collision_recovery", {})
	var recovery_normal: Vector2 = recovery.get("normal", Vector2.ZERO)
	var navigation_margin := 0.0 if recovery_normal.length_squared() > 0.001 else NAVIGATION_MARGIN
	var sample_limit := samples.size()
	if terrain_query != null and terrain_query.is_configured():
		var terrain_started_usec := Time.get_ticks_usec() if diagnostics_enabled else 0
		var trajectory_terrain: Dictionary = terrain_query.validate_movement_trajectory(samples, radius, movement_tags, navigation_margin, recovery_normal)
		_record_diagnostic("terrain_validation_usec", terrain_started_usec)
		minimum_clearance = float(trajectory_terrain.get("minimum_clearance", 0.0))
		exact_segment_checks = int(trajectory_terrain.get("exact_segment_checks", 0))
		field_cells_visited = int(trajectory_terrain.get("field_cells_visited", 0))
		if str(trajectory_terrain.get("status", "Collides")) == "Collides":
			if allow_controlled_contact:
				controlled_contact = true
				sample_limit = clampi(int(trajectory_terrain.get("first_hit_segment", 0)) + 1, 1, samples.size())
			else:
				return {"valid":false, "reason_code":"TERRAIN_COLLISION", "segments_simulated":int(trajectory_terrain.get("segments_validated", 0)), "exact_segment_checks":exact_segment_checks, "field_cells_visited":field_cells_visited}
	if terrain_context != null:
		var environment_started_usec := Time.get_ticks_usec() if diagnostics_enabled else 0
		var trajectory_access: Dictionary = terrain_context.movement_trajectory_access(samples, sample_limit)
		_record_diagnostic("environment_access_usec", environment_started_usec)
		if not bool(trajectory_access.get("allowed", true)):
			if allow_controlled_contact:
				controlled_contact = true
				sample_limit = clampi(int(trajectory_access.get("first_hit_segment", 0)) + 1, 1, sample_limit)
			else:
				return {"valid":false, "reason_code":"TERRAIN_COLLISION", "segments_simulated":int(trajectory_access.get("segments_validated", 0)), "exact_segment_checks":exact_segment_checks, "field_cells_visited":field_cells_visited}
	var dynamic_started_usec := Time.get_ticks_usec() if diagnostics_enabled else 0
	for index in range(1, sample_limit):
		var previous: Vector2 = samples[index - 1].get("position", Vector2.ZERO)
		var next_position: Vector2 = samples[index].get("position", previous)
		var map_width := float(initial_state.get("map_width", 0.0))
		var map_height := float(initial_state.get("map_height", 0.0))
		if (terrain_query == null or not terrain_query.is_configured()) and map_width > 0.0 and map_height > 0.0 and (next_position.x < radius + navigation_margin or next_position.y < radius + navigation_margin or next_position.x > map_width - radius - navigation_margin or next_position.y > map_height - radius - navigation_margin):
			if allow_controlled_contact:
				controlled_contact = true
				sample_limit = index
				break
			return {"valid":false, "reason_code":"TERRAIN_COLLISION", "segments_simulated":index}
		if not nearby_units.is_empty() and _dynamic_collision(next_position, radius, nearby_units):
			_record_diagnostic("dynamic_validation_usec", dynamic_started_usec)
			return {"valid":false, "reason_code":"DYNAMIC_COLLISION", "segments_simulated":index}
	_record_diagnostic("dynamic_validation_usec", dynamic_started_usec)
	var accepted_samples: Array = samples if sample_limit == samples.size() else samples.slice(0, sample_limit)
	var terminal_state: Dictionary = accepted_samples[-1]
	if is_inf(minimum_clearance): minimum_clearance = radius + NAVIGATION_MARGIN + CLEARANCE_COMFORT_BAND
	return {
		"valid":true,
		"terminal_state":terminal_state,
		"samples":accepted_samples,
		"controlled_contact":controlled_contact,
		"minimum_clearance":minimum_clearance,
		"segments_simulated":maxi(0, accepted_samples.size() - 1),
		"exact_segment_checks":exact_segment_checks,
		"field_cells_visited":field_cells_visited,
	}


func _constant_template(thrust_ratio: float, turn_ratio: float, tag: String) -> Dictionary:
	return {"controls":[{"duration":NORMAL_HORIZON, "thrust_ratio":thrust_ratio, "turn_ratio":turn_ratio}], "tag":tag}


func _turn_then_straight_controls(desired_angle: float, turn_rate_limit: float, thrust_ratio: float) -> Array:
	if absf(desired_angle) <= 0.0001 or turn_rate_limit <= 0.0001:
		return [{"duration":NORMAL_HORIZON, "thrust_ratio":thrust_ratio, "turn_ratio":0.0}]
	var direction := signf(desired_angle)
	var useful_turn_time := minf(NORMAL_HORIZON, absf(desired_angle) / turn_rate_limit)
	var full_ticks := floori(useful_turn_time / FIXED_TICK_DELTA + 0.000001)
	var remainder := useful_turn_time - float(full_ticks) * FIXED_TICK_DELTA
	var controls: Array = []
	if full_ticks > 0:
		controls.append({"duration":float(full_ticks) * FIXED_TICK_DELTA, "thrust_ratio":thrust_ratio, "turn_ratio":direction})
	if remainder > 0.0001:
		controls.append({"duration":FIXED_TICK_DELTA, "thrust_ratio":thrust_ratio, "turn_ratio":direction * clampf(remainder / FIXED_TICK_DELTA, 0.0, 1.0)})
	var committed := 0.0
	for control in controls: committed += float(control.get("duration", 0.0))
	if committed < NORMAL_INTERVAL - 0.0001:
		controls.append({"duration":NORMAL_HORIZON, "thrust_ratio":thrust_ratio, "turn_ratio":0.0})
	else:
		# The future straight segment is still part of the prediction; the next
		# rolling plan may replace it from the real state after one second.
		controls.append({"duration":NORMAL_HORIZON, "thrust_ratio":thrust_ratio, "turn_ratio":0.0})
	return controls


func _controls_for_commit(controls: Array, duration: float) -> Array:
	var result: Array = []
	var remaining := duration
	for raw_control in controls:
		if remaining <= 0.0001: break
		var control: Dictionary = raw_control
		var clipped := control.duplicate(true)
		var control_duration := minf(remaining, maxf(FIXED_TICK_DELTA, float(control.get("duration", remaining))))
		clipped["duration"] = control_duration
		result.append(clipped)
		remaining -= control_duration
	if remaining > 0.0001:
		var fallback: Dictionary = controls[-1].duplicate(true) if not controls.is_empty() else {"thrust_ratio":0.0, "turn_ratio":0.0}
		fallback["duration"] = remaining
		result.append(fallback)
	return result


func _next_gate_alignment(terminal_state: Dictionary, next_goals: Array) -> float:
	if next_goals.is_empty(): return 0.0
	var terminal_position: Vector2 = terminal_state.get("position", Vector2.ZERO)
	var next_goal: Vector2 = next_goals[0]
	var direction := next_goal - terminal_position
	if direction.length_squared() <= 0.001: return 1.0
	return 1.0 - absf(angle_difference(float(terminal_state.get("heading", 0.0)), direction.angle())) / PI


func _dynamic_collision(position: Vector2, radius: float, nearby_units: Array) -> bool:
	for other in nearby_units:
		var combined_radius := radius + float(other.get("radius", 0.0))
		if (other.get("position", Vector2.INF) as Vector2).distance_squared_to(position) < combined_radius * combined_radius:
			return true
	return false


func _threat_safety(samples: Array, terminal: Vector2, threats: Array, _motion_state: Dictionary) -> float:
	if threats.is_empty(): return 1.0
	var result := 1.0
	for threat in threats:
		var safety := 1.0
		match str(threat.get("kind", "")):
			"Torpedo":
				var origin: Vector2 = threat.get("position", Vector2.ZERO)
				var velocity: Vector2 = threat.get("velocity", Vector2.ZERO)
				var horizon := float(threat.get("horizon", 6.0))
				var end := origin + velocity * horizon
				var closest := Geometry2D.get_closest_point_to_segment(terminal, origin, end)
				safety = clampf(terminal.distance_to(closest) / maxf(1.0, float(threat.get("danger_radius", 80.0))), 0.0, 1.0)
			"Area":
				safety = clampf(terminal.distance_to(threat.get("position", Vector2.ZERO)) / maxf(1.0, float(threat.get("radius", 80.0))), 0.0, 1.0)
		result = minf(result, safety)
	return result
