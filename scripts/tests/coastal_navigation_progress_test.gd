extends SceneTree

const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Session = preload("res://scripts/application/battle_session.gd")
var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = Registry.new()
	_check(registry.load_all(), "registry loads")
	for heading in [0.0, PI]: _case(registry, "cape", "hood", heading)
	_case(registry, "cape", "shimakaze", PI)
	_case(registry, "bay", "shimakaze", 0.0)
	_case(registry, "narrow", "warspite", PI)
	_case(registry, "narrow", "warspite", PI, true)
	_case(registry, "straight", "hood", 0.0, false, Vector2(-3,0), 0.8)
	_case(registry, "straight", "hood", 0.0, false, Vector2(0,2), 1.0)
	if failures.is_empty():
		print("PASS: %d coastal progress checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: " + failure)
		quit(1)


func _case(registry, map_id: String, ship: String, heading: float, force_recovery: bool = false, current: Vector2 = Vector2.ZERO, speed_multiplier: float = 1.0) -> void:
	var session = Session.new(registry)
	session.create_battle("level.prototype_11v11" if ship == "hood" else "level.prototype_3v3", 20260928)
	var unit: Dictionary = session.state["units_by_id"]["unit.player." + ship]
	session.state["units_by_id"] = {unit["entity_id"]:unit}
	session._full_ai_factions.clear()
	unit["movement_assist_enabled"] = false
	unit["current_speed"] = 0.0
	unit["heading"] = heading
	var polygons: Array
	var points: Array
	match map_id:
		"straight":
			polygons = [[[0,800],[2400,800],[2400,1600],[0,1600]]]
			unit["position"] = Vector2(400,750)
			points = [Vector2(2000,750)]
		"cape":
			polygons = [[[0,800],[1000,800],[1000,550],[1400,550],[1400,800],[2400,800],[2400,1600],[0,1600]]]
			unit["position"] = Vector2(700,750)
			points = [Vector2(880,640),Vector2(960,480),Vector2(1200,480),Vector2(1440,480),Vector2(1600,640),Vector2(1700,750)]
		"bay":
			polygons = [[[500,400],[700,400],[700,1100],[1300,1100],[1300,400],[1500,400],[1500,1300],[500,1300]]]
			unit["position"] = Vector2(1000,1000)
			points = [Vector2(1200,800),Vector2(1200,560),Vector2(1280,320),Vector2(1520,320),Vector2(1680,480),Vector2(1800,600)]
		_:
			polygons = [[[0,0],[2400,0],[2400,740],[0,740]],[[0,850],[2400,850],[2400,1600],[0,1600]]]
			unit["position"] = Vector2(400,795)
			points = [Vector2(2000,795)]
	var obstacles: Array = []
	for index in range(polygons.size()):
		obstacles.append({"id":"bank.%d" % index, "block_mask":["ShipMovement"], "polygon":polygons[index]})
	var terrain := {"id":"terrain.coastal.progress", "map_size":[2400,1600], "obstacles":obstacles, "regions":[]}
	session.terrain_query.configure(terrain)
	session.terrain_context_service.configure(session.terrain_query, {}, [], "")
	if current != Vector2.ZERO:
		var effect := {"id":"current", "definition_type":"EnvironmentEffect", "stack_rule":"VectorAdd", "context":{"current_strength":current.length(), "movement_speed_multiplier":speed_multiplier}}
		var zone := {"id":"water", "effect_id":"current", "heading":rad_to_deg(current.angle()), "polygon":[[0,0],[2400,0],[2400,1600],[0,1600]]}
		session.terrain_context_service.configure(session.terrain_query, {"zones":[zone]}, [effect], "")
		_check((session.terrain_context_service.context_at(unit["position"])["current_vector"] as Vector2).distance_to(current) < 0.001, "current fixture uses real environment composition")
	session.state["terrain_map"] = terrain
	session.state["map"] = {"width":2400.0,"height":1600.0}
	var goal: Vector2 = points.back()
	unit["movement_state"] = session._new_movement_state("AutoNavigate", goal, points)
	unit["navigation_state"]["strategic_intent_target"] = goal
	for gate in unit["movement_state"]["corridor_gates"]: gate["radius"] = 63.0
	var previous: Vector2 = unit["position"]
	var corridor_legal := true
	for point: Vector2 in points:
		corridor_legal = corridor_legal and session.terrain_query.is_navigation_segment_clear(previous, point, float(unit["stats"]["collision_radius"]), session._movement_tags(unit))
		previous = point
	var label := "%s/%s/%.0f/recovery=%s/current=%s" % [map_id,ship,rad_to_deg(heading),force_recovery,current]
	_check(corridor_legal, label + " fixture corridor is continuously legal")
	if force_recovery:
		session._start_navigation_recovery(unit, "DOUBLE_BANK_REGRESSION")
		var recovery: Dictionary = unit["navigation_state"]["recovery"]
		_check(bool(recovery["departure_feasible"]) and session.terrain_query.can_occupy_circle(recovery["escape_goal"], float(unit["stats"]["collision_radius"]), session._movement_tags(unit)), label + " selects an exit inside the waterway")
	var arrived := false
	var collisions := 0
	var timeouts := 0
	var recoveries := 0
	var budget_ok := true
	for tick in range(1800):
		session._event_buffer = []
		session.state["tick_index"] = tick + 1
		session.state["elapsed_time"] = (tick + 1) * 0.1
		session._update_navigation_requests()
		session._update_navigation_plans()
		session._update_movement(0.1)
		var plan: Dictionary = unit["navigation_state"].get("trajectory_plan", {})
		budget_ok = budget_ok and int(plan.get("candidate_count", 0)) <= 6 and plan.get("predicted_samples", []).size() <= 61
		for event in session._event_buffer:
			if event["event_type"] in ["UnitTerrainCollision", "NavigationCollisionContractViolated"]: collisions += 1
			if event["event_type"] == "NavigationStalled": timeouts += 1
			if event["event_type"] == "NavigationRecoveryStarted": recoveries += 1
		if (unit["position"] as Vector2).distance_to(goal) <= session.trajectory_planner.arrival_tolerance(float(unit["stats"]["collision_radius"])):
			arrived = true
			break
	print("COAST_CASE %s arrived=%s seconds=%.1f collisions=%d recoveries=%d timeouts=%d" % [label,arrived,session.state["elapsed_time"],collisions,recoveries,timeouts])
	_check(arrived, label + " arrives within 180 seconds")
	_check(collisions == 0, label + " never hits land")
	_check(budget_ok, label + " retains six-candidate / six-second budget")
	if not force_recovery: _check(recoveries == 0 and timeouts == 0, label + " advances without unnecessary recovery")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
