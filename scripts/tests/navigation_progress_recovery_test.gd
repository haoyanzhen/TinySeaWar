extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")
const NavigationProgress = preload("res://scripts/application/navigation/navigation_progress.gd")

var failures: Array[String] = []
var checks := 0


class PartialRoutePlanner extends RefCounted:
	func plan_path(_query, _definition, start: Vector2, target: Vector2, _radius, _tags, _context) -> Dictionary:
		var partial := start.lerp(target, 0.5)
		return {"ok":true, "waypoints":[partial], "resolved_target":partial}
	func get_last_profile() -> Dictionary:
		return {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_progress()
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "registry loads")
	_test_recovery(registry, "PlayerMoveOrder", Vector2(388.0, 400.0), 0.0)
	_test_recovery(registry, "AssistNavigate", Vector2(388.0, 400.0), PI * 0.5)
	_test_recovery(registry, "AutoNavigate", Vector2(388.0, 400.0), 0.0)
	_test_interruptions(registry)
	_test_no_safe_plan(registry)
	_test_retry_and_contact(registry)
	_test_short_retreat(registry)
	_test_recovery_checkpoint(registry)
	_test_recovery_broker(registry)
	_test_contact_exit(registry)
	if failures.is_empty():
		print("PASS: %d navigation progress and recovery checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: " + failure)
		print("FAILED: %d of %d navigation progress and recovery checks" % [failures.size(), checks])
		quit(1)


func _test_progress() -> void:
	var memory := {}
	for index in range(100):
		NavigationProgress.observe(memory, Vector2(sin(float(index) * 0.2) * 10.0, 0.0), sin(float(index) * 0.2), Vector2(500.0, 0.0), 0.1)
	_check(NavigationProgress.needs_recovery(memory), "oscillation and repeated yaw cannot renew progress forever")
	memory = {}
	for index in range(100):
		NavigationProgress.observe(memory, Vector2.ZERO, 0.0, Vector2(500.0 - index * 2.0, 0.0), 0.1)
	_check(NavigationProgress.needs_recovery(memory), "moving goal and replanning do not manufacture progress")
	memory = {}
	for index in range(100):
		NavigationProgress.observe(memory, Vector2(index * 3.0, 0.0), 0.0, Vector2(500.0, 0.0), 0.1)
	_check(not NavigationProgress.needs_recovery(memory), "monotonic corridor progress remains healthy")
	memory = {}
	for index in range(100):
		NavigationProgress.observe(memory, Vector2(index * 2.0, 0.0), 0.0, Vector2(500.0 + index * 2.0, 0.0), 0.1)
	_check(not NavigationProgress.needs_recovery(memory), "real partial progress survives frequent tactical goal refresh")
	memory = {}
	for index in range(100):
		NavigationProgress.observe(memory, Vector2(index * 0.2, 0.0), 0.0, Vector2(30.0, 0.0), 0.1)
	_check(not NavigationProgress.needs_recovery(memory), "slow final approach remains healthy")
	memory = {}
	for index in range(60):
		NavigationProgress.observe(memory, Vector2.ZERO, PI - index * 0.025, Vector2(500.0, 0.0), 0.1)
	_check(not NavigationProgress.needs_recovery(memory), "productive turning receives bounded grace")
	for index in range(60, 120):
		NavigationProgress.observe(memory, Vector2.ZERO, PI - index * 0.025, Vector2(500.0, 0.0), 0.1)
	_check(NavigationProgress.needs_recovery(memory), "turning alone cannot defer translation indefinitely")
	memory = {}
	for index in range(110):
		NavigationProgress.observe(memory, Vector2.ZERO, PI - index * 0.025, Vector2(500.0, 0.0), 0.1, false, true)
	_check(not NavigationProgress.needs_recovery(memory), "actual turn convergence with a safe advancing control gets bounded execution grace")
	for index in range(110, 200):
		NavigationProgress.observe(memory, Vector2.ZERO, 0.0, Vector2(500.0, 0.0), 0.1, false, true)
	_check(NavigationProgress.needs_recovery(memory), "a repeatedly successful prediction cannot defer a motionless ship forever")
	memory = {}
	for index in range(100):
		NavigationProgress.observe(memory, Vector2.ZERO, 0.0, Vector2(500.0 + index, 0.0), 0.1, false, true)
	_check(NavigationProgress.needs_recovery(memory) and float(memory.get("execution_grace", 0.0)) == 0.0, "target refresh without actual turning cannot earn execution grace")


func _fixture(registry) -> Dictionary:
	var session = BattleSession.new(registry)
	session.create_battle("level.prototype_1v1", 20260928)
	session._full_ai_factions.clear()
	var unit: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	session.state["units_by_id"] = {unit["entity_id"]:unit}
	unit["position"] = Vector2(388.0, 400.0)
	unit["heading"] = 0.0
	unit["stats"]["collision_radius"] = 30.0
	unit["stats"]["speed"] = 50.0
	unit["stats"]["turn_speed"] = 45.0
	unit["movement_state"] = session._new_movement_state("PlayerMoveOrder", Vector2(200.0, 150.0), [Vector2(200.0, 150.0)])
	unit["navigation_state"]["strategic_intent_target"] = Vector2(200.0, 150.0)
	session.state["map"] = {"width":1000.0, "height":800.0}
	session.terrain_query.configure({"id":"terrain.recovery.fixture", "map_size":[1000.0, 800.0], "obstacles":[{"id":"shore", "block_mask":["ShipMovement"], "polygon":[[420.0,250.0],[620.0,250.0],[620.0,550.0],[420.0,550.0]]}], "regions":[]})
	return {"session":session, "unit":unit}


func _step(session) -> void:
	session.state["tick_index"] = int(session.state["tick_index"]) + 1
	session.state["elapsed_time"] = float(session.state["elapsed_time"]) + 0.1
	session._update_navigation_plans()
	session._update_movement(0.1)
	session._resolve_unit_overlap()
	for unit in session.state["units_by_id"].values():
		if unit.get("life_state", "") == "Alive": session._update_navigation_progress(unit, 0.1)


func _test_recovery(registry, mode: String, position: Vector2, heading: float) -> void:
	var fixture := _fixture(registry)
	var session = fixture["session"]
	var unit: Dictionary = fixture["unit"]
	unit["position"] = position
	unit["heading"] = heading
	unit["movement_state"]["mode"] = mode
	for _index in range(90): session._update_navigation_progress(unit, 0.1)
	_check(not unit["navigation_state"]["recovery"].is_empty(), "%s enters shared recovery after no progress" % mode)
	var started := false
	var completed := false
	var collided := false
	var budget_ok := true
	var saw_reverse := false
	for index in range(500):
		_step(session)
		var plan: Dictionary = unit["navigation_state"].get("trajectory_plan", {})
		budget_ok = budget_ok and int(plan.get("candidate_count", 0)) <= 6 and plan.get("predicted_samples", []).size() <= 61
		saw_reverse = saw_reverse or float(unit["current_speed"]) < -5.0
		started = started or not unit["navigation_state"]["recovery"].is_empty()
		collided = collided or unit["navigation_state"].has("last_collision")
		if started and unit["navigation_state"]["recovery"].is_empty():
			completed = true
			break
	_check(completed, "%s actually departs and rejoins within 50 seconds (position=%s recovery=%s)" % [mode, unit["position"], unit["navigation_state"]["recovery"]])
	_check(not collided, "%s does not hit shore while recovering" % mode)
	_check(budget_ok, "%s recovery keeps the six-candidate 60-segment budget" % mode)
	if is_zero_approx(heading): _check(saw_reverse, "%s can use useful reverse speed" % mode)
	var goal := Vector2(200.0, 150.0)
	for _index in range(400): _step(session)
	_check((unit["position"] as Vector2).distance_to(goal) <= 16.0, "%s continues to original goal after recovery (position=%s)" % [mode, unit["position"]])


func _test_interruptions(registry) -> void:
	var fixture := _fixture(registry)
	var session = fixture["session"]
	var unit: Dictionary = fixture["unit"]
	session._start_navigation_recovery(unit, "TEST")
	var recovery: Dictionary = unit["navigation_state"]["recovery"]
	unit["navigation_state"]["state"] = "EmergencyEvasion"
	for _index in range(100): session._update_navigation_progress(unit, 0.1)
	_check(is_zero_approx(float(recovery["elapsed"])), "emergency pauses recovery timeout")
	unit["navigation_state"]["state"] = "NavigationRecovery"
	unit["movement_state"]["mode"] = "AutoNavigate"
	session._submit_navigation_request(unit, unit["position"], Vector2(180.0, 140.0), "Replace", "AutoNavigate", "ai.refresh", 10)
	session._update_navigation_requests()
	_check(unit["navigation_state"]["recovery"] == recovery, "AI route refresh preserves recovery episode")
	session._begin_navigation_intent(unit)
	_check(unit["navigation_state"]["recovery"].is_empty() and unit["navigation_state"]["trajectory_plan"].is_empty(), "explicit player replacement cancels recovery and obsolete control")
	unit["movement_state"] = session._new_movement_state("HoldPosition", unit["position"], [])
	unit["navigation_state"]["route_waiting"] = true
	for _index in range(100): session._update_navigation_progress(unit, 0.1)
	_check(unit["navigation_state"]["recovery"].is_empty(), "waiting for a route does not cause blind reverse")


func _test_no_safe_plan(registry) -> void:
	var fixture := _fixture(registry)
	var session = fixture["session"]
	var unit: Dictionary = fixture["unit"]
	unit["position"] = Vector2(500.0, 400.0)
	unit["navigation_state"]["trajectory_plan"] = {"ok":true, "controls":[{"duration":1.0,"thrust_ratio":1.0,"turn_ratio":0.0}]}
	session._plan_normal_trajectory(unit)
	_check(unit["navigation_state"]["trajectory_plan"].is_empty(), "no safe candidate clears stale successful plan")
	_check(is_zero_approx(float(session._active_trajectory_control(unit["navigation_state"])["thrust_ratio"])), "failed planning never applies unvalidated reverse")


func _test_retry_and_contact(registry) -> void:
	var fixture := _fixture(registry)
	var session = fixture["session"]
	var unit: Dictionary = fixture["unit"]
	unit["navigation_state"]["last_collision"] = {"normal":Vector2.LEFT, "position":unit["position"]}
	session._plan_normal_trajectory(unit)
	_check(not unit["navigation_state"]["recovery"].is_empty(), "actual collision facts trigger recovery without waiting for timeout")
	var first_plan: Dictionary = unit["navigation_state"]["trajectory_plan"].duplicate(true)
	var first_direction: Vector2 = unit["navigation_state"]["recovery"]["direction"]
	session._plan_normal_trajectory(unit)
	_check(first_plan.get("prediction_controls", []) == unit["navigation_state"]["trajectory_plan"].get("prediction_controls", []), "identical state produces deterministic recovery controls")
	for _index in range(85): session._update_navigation_progress(unit, 0.1)
	var recovery: Dictionary = unit["navigation_state"]["recovery"]
	_check(int(recovery["attempts"]) == 2, "failed departure switches strategy after bounded time")
	_check(not (recovery["direction"] as Vector2).is_equal_approx(first_direction), "retry changes departure direction instead of repeating failed control")
	for _index in range(130): session._update_navigation_progress(unit, 0.1)
	_check(bool(unit["navigation_state"]["progress"].get("stuck_reported", false)), "unresolved recovery records explicit timeout")
	_check(not bool(unit["ai_state"]["path_stuck"]), "authored player recovery is not mislabelled AIPathStuck")
	_check((unit["position"] as Vector2).is_equal_approx(Vector2(388.0,400.0)), "retry and timeout never teleport the ship")
	unit["movement_state"]["mode"] = "HoldPosition"
	session._update_navigation_progress(unit, 0.1)
	_check(unit["navigation_state"]["recovery"].is_empty(), "intentional stop cancels recovery")


func _test_short_retreat(registry) -> void:
	var fixture := _fixture(registry)
	var session = fixture["session"]
	var unit: Dictionary = fixture["unit"]
	var terrain: Dictionary = session.terrain_query.terrain_definition.duplicate(true)
	terrain["obstacles"].append({"id":"opposite_bank", "block_mask":["ShipMovement"], "polygon":[[100.0,250.0],[300.0,250.0],[300.0,550.0],[100.0,550.0]]})
	session.terrain_query.configure(terrain)
	session._start_navigation_recovery(unit, "NARROW_WATER")
	session._plan_normal_trajectory(unit)
	var plan: Dictionary = unit["navigation_state"]["trajectory_plan"]
	_check(bool(plan.get("ok", false)), "narrow water has a validated short departure")
	_check(float(plan.get("controls", [{}])[0].get("thrust_ratio", 0.0)) < 0.0, "narrow water actually selects reverse instead of permanent braking")
	_check(plan.get("predicted_samples", []).size() == 61, "short reverse still validates six seconds including braking")
	var legal := true
	for sample in plan.get("predicted_samples", []):
		legal = legal and session.terrain_query.can_occupy_circle(sample["position"], 30.0, ["Surface"])
	_check(legal, "short-retreat samples avoid both banks")
	var recovery: Dictionary = unit["navigation_state"]["recovery"]
	_check(bool(recovery["departure_feasible"]) and session.terrain_query.can_occupy_circle(recovery["escape_goal"], 30.0, ["Surface"]), "escape target itself is reachable water rather than opposite-bank land")


func _test_recovery_checkpoint(registry) -> void:
	var fixture := _fixture(registry)
	var session = fixture["session"]
	var unit: Dictionary = fixture["unit"]
	var origin: Vector2 = unit["position"]
	var goal: Vector2 = session._current_corridor_goal(unit)
	var forward := origin.direction_to(goal)
	session._start_navigation_recovery(unit, "CHECKPOINT")
	var recovery: Dictionary = unit["navigation_state"]["recovery"]
	recovery.merge({"stage":"Rejoin", "rejoin_goal":goal, "rejoin_best_distance":origin.distance_to(goal) + 100.0, "rejoin_progress":0.0}, true)
	unit["position"] = origin - forward * 70.0
	unit["navigation_state"]["trajectory_plan"] = {"ok":true, "predicted_progress":50.0}
	session._update_navigation_progress(unit, 0.1)
	_check(not unit["navigation_state"]["recovery"].is_empty(), "advancing 30 after retreating 100 does not complete recovery")
	_check((recovery["checkpoint_position"] as Vector2).is_equal_approx(origin), "original bottleneck survives rejoin progress")
	unit["position"] = origin + forward * 25.0
	session._update_navigation_progress(unit, 0.1)
	_check(unit["navigation_state"]["recovery"].is_empty(), "real net progress beyond the original bottleneck completes recovery")


func _test_recovery_broker(registry) -> void:
	var fixture := _fixture(registry)
	var session = fixture["session"]
	var unit: Dictionary = fixture["unit"]
	var gate := Vector2(200.0, 150.0)
	var final_goal := Vector2(100.0, 150.0)
	unit["movement_state"] = session._new_movement_state("PlayerWaypointRoute", final_goal, [gate, final_goal])
	unit["navigation_state"]["strategic_intent_target"] = final_goal
	session._start_navigation_recovery(unit, "BROKER")
	for _index in range(165): session._update_navigation_progress(unit, 0.1)
	_check(session.navigation_request_broker.pending_count() == 1, "repeated local failure escalates once through the shared Broker")
	session._update_navigation_requests()
	_check(unit["movement_state"]["corridor_points"].back() == final_goal and unit["movement_state"]["target_position"] == final_goal, "recovery corridor rebuild retains subsequent player waypoints and final target")
	_check(unit["navigation_state"]["strategic_intent_target"] == final_goal, "recovery rebuild does not replace semantic intent with its local gate")
	var retained_points: Array = unit["movement_state"]["corridor_points"].duplicate()
	session.route_planner = PartialRoutePlanner.new()
	session._submit_navigation_request(unit, unit["position"], gate, "Recovery", "PlayerWaypointRoute", "partial.test", 5, final_goal)
	session._update_navigation_requests()
	_check(unit["movement_state"]["corridor_points"] == retained_points, "a projected partial leg is not joined to an unvalidated old suffix")
	session._submit_navigation_request(unit, unit["position"], gate, "Recovery", "PlayerWaypointRoute", "cancel.test", 5)
	unit["movement_state"] = session._new_movement_state("HoldPosition", unit["position"], [])
	session._update_navigation_progress(unit, 0.1)
	session._update_navigation_requests()
	_check(unit["movement_state"]["mode"] == "HoldPosition", "pending recovery result cannot restart an intentionally stopped ship")


func _test_contact_exit(registry) -> void:
	var fixture := _fixture(registry)
	var session = fixture["session"]
	var unit: Dictionary = fixture["unit"]
	unit["position"] = Vector2(390.0, 400.0)
	unit["navigation_state"]["last_collision"] = {"normal":Vector2.LEFT}
	session._start_navigation_recovery(unit, "TERRAIN_CONTACT")
	_check(bool(unit["navigation_state"]["recovery"]["departure_feasible"]), "touching a shoreline still allows a validated outward escape")
	for _index in range(600): _step(session)
	_check((unit["position"] as Vector2).distance_to(Vector2(200.0, 150.0)) <= 16.0, "a ship initially touching shore departs and reaches its retained goal: %s" % unit["position"])


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
