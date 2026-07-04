extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "configuration registry loads")
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_harbor_3v3", 20260630).get("ok", false), "harbor AI fixture starts")
	session.state["visible_by_faction"]["enemy"] = {}
	session._ai_observations_by_faction.clear()
	var assigned: Array[String] = []
	var capture_plans := 0
	for unit_id in ["unit.enemy.gnevny", "unit.enemy.anshan", "unit.enemy.ning_hai"]:
		var unit: Dictionary = session.state["units_by_id"][unit_id]
		var plan: Dictionary = session._ai_facility_plan(unit, true)
		if not plan.is_empty():
			capture_plans += 1
			assigned.append(str(unit.get("ai_state", {}).get("task_target_ref", {}).get("facility_id", "")))
	_check(capture_plans == 1, "objective saturation assigns one capture runner while the group remains available")
	_check(assigned.size() == 1 and not assigned[0].is_empty(), "capture runner retains a concrete facility target")
	var runner: Dictionary = {}
	for unit_id in ["unit.enemy.gnevny", "unit.enemy.anshan", "unit.enemy.ning_hai"]:
		var candidate: Dictionary = session.state["units_by_id"][unit_id]
		if str(candidate.get("ai_state", {}).get("level_task", "")) == "CaptureFacility":
			runner = candidate
			break
	var runner_facility_id := str(runner.get("ai_state", {}).get("task_target_ref", {}).get("facility_id", ""))
	var runner_facility: Dictionary = session.state["facilities_by_id"].get(runner_facility_id, {})
	if not runner.is_empty() and not runner_facility.is_empty():
		runner["position"] = session.facility_service.interaction_center(runner_facility_id)
		runner["movement_state"] = {"mode": "AutoNavigate", "target_position": runner["position"] + Vector2(300.0, 0.0), "waypoints": [runner["position"] + Vector2(300.0, 0.0)], "waypoint_index": 0}
		runner["current_speed"] = 50.0
		var movement_before: Dictionary = runner["movement_state"].duplicate(true)
		var speed_before := float(runner["current_speed"])
		var position_before: Vector2 = runner["position"]
		var start_result: Dictionary = session._apply_command({"command_id": "test.facility.start", "command_type": "StartFacilityInteraction", "issuer_id": "enemy", "issuer_type": "AI", "unit_id": runner["entity_id"], "facility_id": runner_facility_id, "interaction_type": "Seize"})
		_check(bool(start_result.get("accepted", false)), "capture runner can start its assigned facility interaction")
		_check(runner["movement_state"] == movement_before and is_equal_approx(float(runner["current_speed"]), speed_before), "ordinary facility work preserves navigation and speed")
		session._update_movement(0.5)
		_check((runner["position"] as Vector2).distance_to(position_before) > 1.0, "ordinary facility work does not hold station or cancel propulsion")
		for index in range(20):
			session._update_movement(0.5)
		var interaction_events: Array = session.facility_service.advance(0.5, 0.5, session.state["units_by_id"])
		_check(_has_event(interaction_events, "FacilityInteractionInterrupted") and session.facility_service.active_interaction_for_unit(str(runner["entity_id"])).is_empty(), "leaving the interaction water interrupts ordinary facility work")
		session._ai_observations_by_faction.clear()
		session._ai_objective_plan_cache.clear()
		var active_plan: Dictionary = session._ai_facility_plan(runner, true)
		_check(bool(active_plan.get("hold_interaction", false)) and not active_plan.has("interaction_type"), "active facility interaction is held without duplicate start commands")
	var defender: Dictionary = session.state["units_by_id"]["unit.enemy.gnevny"]
	var battery: Dictionary = session.state["facilities_by_id"]["facility.harbor.battery_west"]
	var intruder: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	intruder["position"] = battery["position"]
	session.state["visible_by_faction"]["enemy"] = {intruder["entity_id"]: true}
	for unit_id in ["unit.enemy.gnevny", "unit.enemy.anshan", "unit.enemy.ning_hai"]:
		session._clear_ai_facility_task(session.state["units_by_id"][unit_id])
	session._ai_observations_by_faction.clear()
	session._ai_local_power_cache.clear()
	var defense: Dictionary = session._ai_facility_plan(defender, false)
	_check(str(defense.get("task_type", "")) == "DefendFacility", "visible pressure creates a quantified defense task")
	_check(float(defense.get("score", 0.0)) >= 60.0, "facility defense meets the designed override threshold")
	_check(str(defender["ai_state"].get("objective_role", "")) == "ApproachIntercept", "fast destroyer receives approach-intercept duty")
	var fake_battleship := defender.duplicate(true)
	fake_battleship["stats"]["ship_class"] = "Battleship"
	_check(session._facility_defense_role(fake_battleship) == "FireSupport", "capital ship maps to facility fire-support duty")
	var fake_cruiser := defender.duplicate(true)
	fake_cruiser["stats"]["ship_class"] = "HeavyCruiser"
	_check(session._facility_defense_role(fake_cruiser) == "InnerGuard", "heavy cruiser maps to inner-guard duty")
	intruder["position"] = Vector2(99999.0, 99999.0)
	session._ai_observations_by_faction.clear()
	session._ai_local_power_cache.clear()
	var cleared: Dictionary = session._ai_facility_plan(defender, false)
	_check(cleared.is_empty() and str(defender["ai_state"].get("level_task", "")).is_empty(), "obsolete defense task is cleared when pressure disappears")
	if failures.is_empty():
		print("PASS: %d AI facility task checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d AI facility task checks; assigned=%s" % [failures.size(), checks, assigned])
		quit(1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _has_event(events: Array, event_type: String) -> bool:
	for event in events:
		if str(event.get("event_type", "")) == event_type:
			return true
	return false
