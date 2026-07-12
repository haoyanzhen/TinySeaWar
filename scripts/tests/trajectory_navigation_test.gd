extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")
const ShipMotionService = preload("res://scripts/domain/services/ship_motion_service.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "configuration registry loads")
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_1v1", 20260711).get("ok", false), "trajectory fixture starts")
	var unit: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	var start: Vector2 = unit["position"]
	var target := start + Vector2(0.0, -500.0)
	session.queue_command({"command_id":"trajectory.move", "command_type":"MoveUnits", "issued_at_tick":0, "issuer_type":"Player", "issuer_id":"player", "unit_id":unit["entity_id"], "target_position":target})
	var saw_plan := false
	for _tick in range(25):
		for event in session.advance_tick(0.1):
			if event.get("event_type", "") == "TrajectoryPlanned" and event.get("unit_id", "") == unit["entity_id"]: saw_plan = true
	_check(saw_plan, "runtime emits a trajectory plan")
	_check(unit["movement_state"].get("corridor_points", []).size() >= 1, "move intent stores a strategic corridor")
	_check(unit["movement_state"].get("waypoints", []).is_empty(), "legacy waypoint trajectory is not populated")
	_check((unit["position"] as Vector2).distance_to(start) > 1.0, "ship moves by executing trajectory controls")
	_check(unit["navigation_state"].get("current_control", {}).has("thrust_ratio"), "runtime stores thrust and turn control")

	var reverse_state := {"position":Vector2.ZERO, "heading":0.0, "speed":10.0, "maximum_speed":20.0, "reverse_speed":5.0, "acceleration":20.0, "braking":40.0, "turn_rate_limit":1.0, "current_vector":Vector2.ZERO}
	for _index in range(10): reverse_state = ShipMotionService.step(reverse_state, {"thrust_ratio":-1.0, "turn_ratio":0.0}, 0.1)
	_check(float(reverse_state["speed"]) < 0.0, "reverse control brakes through zero before moving astern")

	var torpedo_id := "test.hostile.torpedo"
	session.state["projectiles_by_id"][torpedo_id] = {"entity_id":torpedo_id, "definition_id":"projectile.torpedo", "source_weapon_id":"weapon.shimakaze_610_torpedo", "faction_id":"enemy", "position":unit["position"] + Vector2(0.0, -120.0), "heading":PI * 0.5, "speed":85.0, "collision_radius":8.0, "observed_raw_damage":500.0, "remaining_range":500.0, "travelled_distance":0.0}
	session.state["known_projectiles_by_faction"]["player"][torpedo_id] = true
	session._ai_observations_by_faction.clear()
	var threats: Array = session._navigation_high_threats(unit)
	_check(not threats.is_empty(), "known approaching torpedo enters high-threat scan")
	session._update_navigation_plans()
	_check(unit["navigation_state"].get("state", "") == "EmergencyEvasion", "state machine enters emergency evasion")
	_check(int(unit["navigation_state"].get("trajectory_plan", {}).get("candidate_count", 0)) <= 7, "emergency trajectory respects candidate budget")
	session.state["projectiles_by_id"].erase(torpedo_id)
	session.state["known_projectiles_by_faction"]["player"].erase(torpedo_id)
	for _index in range(4):
		session._ai_observations_by_faction.clear()
		session._update_navigation_plans()
	_check(unit["navigation_state"].get("state", "") == "NormalNavigation", "state machine exits after the threat-clear hold")
	var main_attack := {"attack_id":"test.main", "source_unit_id":"unit.enemy.bismarck", "source_weapon_id":"weapon.bismarck_380_ap", "target_position":unit["position"], "impact_radius":60.0, "resolve_at_time":float(session.state["elapsed_time"]) + 1.0}
	var secondary_attack := {"attack_id":"test.secondary", "source_unit_id":"unit.enemy.bismarck", "source_weapon_id":"weapon.bismarck_150_he", "target_position":unit["position"], "impact_radius":60.0, "resolve_at_time":float(session.state["elapsed_time"]) + 1.0}
	unit["current_hp"] = 80.0
	session.state["visible_by_faction"]["player"]["unit.enemy.bismarck"] = true
	_check(session._is_committed_high_threat_attack(unit, main_attack), "large-caliber committed main-gun impact enters the whitelist")
	_check(not session._is_committed_high_threat_attack(unit, secondary_attack), "secondary gun impact stays out of the emergency whitelist")

	if failures.is_empty():
		print("PASS: %d trajectory navigation checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d trajectory navigation checks" % [failures.size(), checks])
		quit(1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
