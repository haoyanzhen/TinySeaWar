extends RefCounted

const ShipMotionService = preload("res://scripts/domain/services/ship_motion_service.gd")

const NORMAL_INTERVAL := 1.0
const EMERGENCY_INTERVAL := 0.1
const NORMAL_HORIZON := 6.0
const EMERGENCY_HORIZON := 1.2
const NORMAL_CANDIDATE_LIMIT := 6
const EMERGENCY_BASE_LIMIT := 5
const EMERGENCY_TOTAL_LIMIT := 7
const NORMAL_SAMPLE_STEP := 1.5
const EMERGENCY_SAMPLE_STEP := 0.1


func arrival_tolerance(radius: float) -> float:
	return maxf(12.0, radius * 0.5)


func plan_normal(motion_state: Dictionary, goal: Vector2, radius: float, movement_tags: Array, terrain_query, terrain_context, nearby_units: Array = [], final_approach: bool = false) -> Dictionary:
	var desired_direction := goal - (motion_state.get("position", Vector2.ZERO) as Vector2)
	var desired_angle := 0.0 if desired_direction == Vector2.ZERO else wrapf(desired_direction.angle() - float(motion_state.get("heading", 0.0)), -PI, PI)
	var preferred_turn := clampf(desired_angle / maxf(0.01, float(motion_state.get("turn_rate_limit", 0.01)) * NORMAL_HORIZON), -1.0, 1.0)
	var maximum_speed := maxf(0.01, float(motion_state.get("maximum_speed", 0.0)))
	var remaining_distance := maxf(0.0, desired_direction.length() - arrival_tolerance(radius))
	var approach_thrust := clampf(remaining_distance / (maximum_speed * NORMAL_HORIZON), 0.03, 1.0) if remaining_distance > 0.0 else 0.0
	var use_arrival_control := final_approach and desired_direction.length() <= maxf(maximum_speed * 1.5, arrival_tolerance(radius) * 4.0)
	var templates := []
	if use_arrival_control:
		templates = [
			{"thrust_ratio": approach_thrust, "turn_ratio": preferred_turn},
			{"thrust_ratio": 1.0, "turn_ratio": preferred_turn},
			{"thrust_ratio": 0.45, "turn_ratio": preferred_turn},
			{"thrust_ratio": 0.0, "turn_ratio": preferred_turn},
			{"thrust_ratio": approach_thrust, "turn_ratio": clampf(preferred_turn - 0.35, -1.0, 1.0)},
			{"thrust_ratio": approach_thrust, "turn_ratio": clampf(preferred_turn + 0.35, -1.0, 1.0)},
		]
	else:
		templates = [
			{"thrust_ratio": 1.0, "turn_ratio": preferred_turn},
			{"thrust_ratio": 0.75, "turn_ratio": preferred_turn},
			{"thrust_ratio": 0.45, "turn_ratio": preferred_turn},
			{"thrust_ratio": 0.0, "turn_ratio": preferred_turn},
			{"thrust_ratio": 0.75, "turn_ratio": clampf(preferred_turn - 0.35, -1.0, 1.0)},
			{"thrust_ratio": 0.75, "turn_ratio": clampf(preferred_turn + 0.35, -1.0, 1.0)},
		]
	return _select_plan(templates.slice(0, NORMAL_CANDIDATE_LIMIT), motion_state, goal, NORMAL_HORIZON, NORMAL_SAMPLE_STEP, radius, movement_tags, terrain_query, terrain_context, nearby_units, [], false, use_arrival_control)


func plan_emergency(motion_state: Dictionary, threats: Array, radius: float, movement_tags: Array, terrain_query, terrain_context, nearby_units: Array = [], extended: bool = false) -> Dictionary:
	var templates := [
		{"thrust_ratio": 0.5, "turn_ratio": 0.0},
		{"thrust_ratio": 0.5, "turn_ratio": -1.0},
		{"thrust_ratio": 0.5, "turn_ratio": 1.0},
		{"thrust_ratio": 0.0, "turn_ratio": -1.0},
		{"thrust_ratio": 0.0, "turn_ratio": 1.0},
	]
	if extended:
		templates.append({"thrust_ratio": 1.0, "turn_ratio": 0.0})
		templates.append({"thrust_ratio": 0.0, "turn_ratio": 0.0, "allow_controlled_contact": true})
	var limit := EMERGENCY_TOTAL_LIMIT if extended else EMERGENCY_BASE_LIMIT
	return _select_plan(templates.slice(0, limit), motion_state, motion_state.get("position", Vector2.ZERO), EMERGENCY_HORIZON, EMERGENCY_SAMPLE_STEP, radius, movement_tags, terrain_query, terrain_context, nearby_units, threats, true, false)


func _select_plan(templates: Array, initial_state: Dictionary, goal: Vector2, horizon: float, sample_step: float, radius: float, movement_tags: Array, terrain_query, terrain_context, nearby_units: Array, threats: Array, emergency: bool, final_approach: bool) -> Dictionary:
	var candidates: Array = []
	for index in range(templates.size()):
		var control: Dictionary = templates[index]
		var simulation := _simulate(initial_state, control, horizon, sample_step, radius, movement_tags, terrain_query, terrain_context, nearby_units, bool(control.get("allow_controlled_contact", false)))
		if not bool(simulation.get("valid", false)): continue
		var terminal: Vector2 = simulation.get("terminal", initial_state.get("position", Vector2.ZERO))
		var threat_score := _threat_safety(simulation.get("samples", []), terminal, threats, initial_state)
		var progress := 0.0
		var origin: Vector2 = initial_state.get("position", Vector2.ZERO)
		if not emergency:
			progress = origin.distance_to(goal) - terminal.distance_to(goal)
		var continuity := 1.0 - absf(float(control.get("turn_ratio", 0.0))) * 0.15
		var contact_cost := 0.4 if bool(simulation.get("controlled_contact", false)) else 0.0
		var stall_cost := 0.0
		if not emergency and origin.distance_to(goal) > arrival_tolerance(radius) and origin.distance_to(terminal) < 0.5:
			# Holding still is not progress toward an intermediate corridor gate
			# either. Without this penalty a zero-thrust candidate can beat every
			# safe recovery turn and strand an inertial ship indefinitely.
			stall_cost = 1000.0
		var score := threat_score * 10000.0 + progress * 10.0 + continuity - contact_cost - stall_cost
		candidates.append({"control": control, "simulation": simulation, "score": score, "index": index, "threat_safety": threat_score})
	if candidates.is_empty():
		return {"ok": false, "reason_code": "NO_SAFE_TRAJECTORY", "candidate_count": templates.size()}
	candidates.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]) if not is_equal_approx(float(a["score"]), float(b["score"])) else int(a["index"]) < int(b["index"]))
	var best: Dictionary = candidates[0]
	return {
		"ok": true,
		"controls": [{"duration": EMERGENCY_INTERVAL if emergency else NORMAL_INTERVAL, "thrust_ratio": best["control"].get("thrust_ratio", 0.0), "turn_ratio": best["control"].get("turn_ratio", 0.0)}],
		"predicted_samples": best["simulation"].get("samples", []),
		"controlled_contact": best["simulation"].get("controlled_contact", false),
		"threat_safety": best["threat_safety"],
		"candidate_count": templates.size(),
	}


func _simulate(initial_state: Dictionary, control: Dictionary, horizon: float, sample_step: float, radius: float, movement_tags: Array, terrain_query, terrain_context, nearby_units: Array, allow_controlled_contact: bool) -> Dictionary:
	var simulated := initial_state.duplicate(true)
	var samples: Array = [simulated.get("position", Vector2.ZERO)]
	var elapsed := 0.0
	var controlled_contact := false
	while elapsed < horizon - 0.0001:
		var step_delta := minf(sample_step, horizon - elapsed)
		var context: Dictionary = terrain_context.context_at(simulated.get("position", Vector2.ZERO)) if terrain_context != null else {}
		simulated["current_vector"] = context.get("current_vector", simulated.get("current_vector", Vector2.ZERO))
		var previous: Vector2 = simulated.get("position", Vector2.ZERO)
		var next_state := ShipMotionService.step(simulated, control, step_delta)
		var next_position: Vector2 = next_state.get("position", previous)
		var map_width := float(initial_state.get("map_width", 0.0))
		var map_height := float(initial_state.get("map_height", 0.0))
		if map_width > 0.0 and map_height > 0.0 and (next_position.x < radius or next_position.y < radius or next_position.x > map_width - radius or next_position.y > map_height - radius):
			if allow_controlled_contact:
				controlled_contact = true
				break
			return {"valid": false}
		var clear := _segment_clear(previous, next_position, radius, movement_tags, terrain_query, terrain_context)
		if not clear:
			if allow_controlled_contact:
				controlled_contact = true
				break
			return {"valid": false}
		if _dynamic_collision(next_position, radius, nearby_units): return {"valid": false}
		simulated = next_state
		samples.append(next_position)
		elapsed += step_delta
	return {"valid": true, "terminal": simulated.get("position", initial_state.get("position", Vector2.ZERO)), "samples": samples, "controlled_contact": controlled_contact}


func _segment_clear(start: Vector2, finish: Vector2, radius: float, movement_tags: Array, terrain_query, terrain_context) -> bool:
	if terrain_context != null and not bool(terrain_context.movement_segment_access(start, finish).get("allowed", true)): return false
	if terrain_query == null or not terrain_query.is_configured(): return true
	# The strategic corridor already supplies the long-range clearance guarantee and
	# runtime motion still performs an exact swept-circle collision. Candidate
	# sampling only needs a conservative local rejection: centerline crossing plus
	# legal endpoint occupancy. Repeating the exact swept-polygon query for every
	# candidate sample made coastal planning dominate the whole battle tick.
	return terrain_query.is_segment_clear(start, finish, "ShipMovement") and terrain_query.can_occupy_circle(finish, radius, movement_tags)


func _dynamic_collision(position: Vector2, radius: float, nearby_units: Array) -> bool:
	for other in nearby_units:
		if (other.get("position", Vector2.INF) as Vector2).distance_to(position) < radius + float(other.get("radius", 0.0)):
			return true
	return false


func _threat_safety(samples: Array, terminal: Vector2, threats: Array, motion_state: Dictionary) -> float:
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
