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
	_run_manual_arrival_case(registry, "unit.player.warspite", false, "Warspite forward 500")
	_run_manual_arrival_case(registry, "unit.player.warspite", true, "Warspite lateral 500")
	_run_manual_arrival_case(registry, "unit.player.shimakaze", false, "Shimakaze forward 500")
	_run_manual_arrival_case(registry, "unit.player.shimakaze", true, "Shimakaze lateral 500")
	_test_manual_intent_precedence(registry)

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


func _run_manual_arrival_case(registry, unit_id: String, lateral: bool, label: String) -> void:
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_3v3", 20260716).get("ok", false), "%s fixture starts" % label)
	session._full_ai_factions.clear()
	for candidate in session.state["units_by_id"].values():
		candidate["movement_state"] = session._new_movement_state("HoldPosition", candidate["position"], [])
		candidate["secondary_auto_fire_enabled"] = false
		candidate["primary_auto_fire_enabled"] = false
		candidate["skill_auto_cast_enabled"] = false
	var unit: Dictionary = session.state["units_by_id"][unit_id]
	var direction := Vector2.RIGHT.rotated(float(unit["heading"]))
	if lateral: direction = direction.rotated(PI * 0.5)
	var target: Vector2 = unit["position"] + direction * 500.0
	var queued := session.queue_command({"command_id":"arrival.%s.%s" % [unit_id, "lateral" if lateral else "forward"], "command_type":"MoveUnits", "issued_at_tick":0, "issuer_type":"Player", "issuer_id":"player", "unit_id":unit_id, "target_position":target})
	_check(bool(queued.get("accepted", false)), "%s command queues" % label)
	var completed := false
	var completion_distance := INF
	var completion_tick := -1
	for tick in range(1200):
		session.advance_tick(0.1)
		if str(unit.get("movement_state", {}).get("mode", "")) not in ["PlayerMoveOrder", "PlayerWaypointRoute"]:
			completed = true
			completion_distance = (unit.get("position", Vector2.ZERO) as Vector2).distance_to(target)
			completion_tick = tick + 1
			break
	var tolerance: float = session.trajectory_planner.arrival_tolerance(float(unit.get("stats", {}).get("collision_radius", 20.0)))
	if completed:
		for _settle_tick in range(20): session.advance_tick(0.1)
	var settled_distance := (unit.get("position", Vector2.ZERO) as Vector2).distance_to(target)
	print("ARRIVAL_CASE label=%s completed=%s ticks=%d arrival_distance=%.3f settled_distance=%.3f tolerance=%.3f" % [label, completed, completion_tick, completion_distance, settled_distance, tolerance])
	_check(completed and completion_distance <= tolerance + 0.01 and settled_distance <= tolerance + 0.01, "%s reaches and settles at the authored target within arrival tolerance (completed=%s arrival_distance=%.2f settled_distance=%.2f tolerance=%.2f position=%s target=%s mode=%s)" % [label, completed, completion_distance, settled_distance, tolerance, unit.get("position", Vector2.ZERO), target, unit.get("movement_state", {}).get("mode", "")])


func _test_manual_intent_precedence(registry) -> void:
	var stale_session = BattleSession.new(registry)
	stale_session.create_battle("level.prototype_1v1", 20260716)
	stale_session._full_ai_factions.clear()
	var stale_unit: Dictionary = stale_session.state["units_by_id"]["unit.player.warspite"]
	var stale_target: Vector2 = stale_unit["position"] + Vector2(300.0, 0.0)
	var manual_target: Vector2 = stale_unit["position"] + Vector2(0.0, -300.0)
	stale_session._submit_navigation_request(stale_unit, stale_unit["position"], stale_target, "Replace", "AssistNavigate", "precedence.stale.assist", 10)
	stale_session.queue_command({"command_id":"precedence.manual", "command_type":"MoveUnits", "issued_at_tick":0, "issuer_type":"Player", "issuer_id":"player", "unit_id":stale_unit["entity_id"], "target_position":manual_target})
	stale_session.advance_tick(0.1)
	stale_session.advance_tick(0.1)
	_check(str(stale_unit["movement_state"].get("mode", "")) == "PlayerMoveOrder" and (stale_unit["movement_state"].get("target_position", Vector2.ZERO) as Vector2).is_equal_approx(manual_target), "latest manual intent cancels a pending assist route")

	var full_ai_session = BattleSession.new(registry)
	full_ai_session.create_battle("level.prototype_1v1", 20260716)
	full_ai_session._full_ai_factions["player"] = true
	var full_ai_unit: Dictionary = full_ai_session.state["units_by_id"]["unit.player.warspite"]
	var full_ai_manual_target: Vector2 = full_ai_unit["position"] + Vector2(0.0, -300.0)
	full_ai_session.queue_command({"command_id":"precedence.full_ai.manual", "command_type":"MoveUnits", "issued_at_tick":0, "issuer_type":"Player", "issuer_id":"player", "unit_id":full_ai_unit["entity_id"], "target_position":full_ai_manual_target})
	for _tick in range(12): full_ai_session.advance_tick(0.1)
	_check(str(full_ai_unit["movement_state"].get("mode", "")) == "PlayerMoveOrder" and (full_ai_unit["movement_state"].get("target_position", Vector2.ZERO) as Vector2).is_equal_approx(full_ai_manual_target), "full player-side AI preserves an active manual route")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
