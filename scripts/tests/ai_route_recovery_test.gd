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
	_check(session.create_battle("level.prototype_harbor_3v3", 20260630).get("ok", false), "harbor route fixture starts")
	var unit: Dictionary = session.state["units_by_id"]["unit.enemy.gnevny"]
	var target: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	session.drain_events()
	session.configure_ai_profile("ai.profile.easy")
	session._best_ai_route_destination(unit, Vector2(1800.0, 1700.0))
	var easy_event := _last_event(session.drain_events(), "AIRouteSelected")
	_check(int(easy_event.get("candidate_count", 0)) == 3, "easy profile evaluates three route candidates")
	session.configure_ai_profile("ai.profile.hard")
	session._ai_route_destination_cache.clear()
	session._best_ai_route_destination(unit, Vector2(1900.0, 1700.0))
	var hard_event := _last_event(session.drain_events(), "AIRouteSelected")
	_check(int(hard_event.get("candidate_budget", 0)) == 7, "hard profile exposes a seven-candidate route budget")
	_check(int(hard_event.get("candidate_count", 0)) >= 1 and int(hard_event.get("candidate_count", 0)) <= 7, "clear direct route can short-circuit the candidate budget")
	var fallback: Dictionary = session._reachable_ai_fallback(unit, Vector2(2048.0, 1160.0))
	_check(bool(fallback.get("ok", false)), "unreachable strategic target produces a local reachable fallback")
	_check(session._local_ai_escape_segment_valid(unit, fallback.get("position", unit["position"])), "local route fallback passes authoritative segment checks")
	var shore_escape := session._shore_escape_waypoint(unit)
	_check(shore_escape != session._map_center(), "shore escape does not target the island-bearing map center")
	_check(shore_escape == unit["position"] or session._local_ai_escape_segment_valid(unit, shore_escape), "shore escape waypoint is locally reachable or safely holds")
	var cover: Dictionary = session._best_ai_cover_position(unit, target)
	_check(not cover.is_empty(), "nearshore AI produces a reachable cover candidate")
	_check(int(cover.get("exit_count", 0)) > 0, "cover candidate keeps a legal exit")
	_check(session.terrain_query.can_occupy_circle(cover.get("position", Vector2.ZERO), float(unit["stats"].get("collision_radius", 20.0)), session._movement_tags(unit)), "cover candidate is legal water for the ship")
	unit["movement_state"] = {"mode":"AutoNavigate", "target_position":Vector2(2100.0, 1500.0), "waypoints":[Vector2(2100.0, 1500.0)], "waypoint_index":0}
	unit["ai_state"]["path_stuck"] = true
	_check(session._update_immediate_survival(unit), "stuck path enters immediate recovery")
	_check(unit["ai_state"]["active_interrupt"] == "PathRecovery", "path recovery has an explicit interrupt reason")
	_check(int(unit["ai_state"]["path_recovery_count"]) == 1 and not bool(unit["ai_state"]["path_stuck"]), "recovery clears the stuck latch and increments telemetry")
	_check(not session.command_queue.is_empty() and session.command_queue.back().get("movement_mode", "") == "ImmediateAvoidance", "path recovery submits a legal avoidance movement")
	var doomed: Dictionary = session.state["units_by_id"]["unit.enemy.anshan"]
	session.command_queue.append({"command_id": "test.stale", "command_type": "MoveUnits", "unit_id": doomed["entity_id"]})
	session._sink_unit(doomed, "test")
	_check(session.command_queue.all(func(command): return str(command.get("unit_id", "")) != str(doomed["entity_id"])), "sinking a unit removes its stale queued commands")
	if failures.is_empty():
		print("PASS: %d AI route, cover and recovery checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d AI route, cover and recovery checks; cover=%s" % [failures.size(), checks, cover])
		quit(1)


func _last_event(events: Array, event_type: String) -> Dictionary:
	var result := {}
	for event in events:
		if event.get("event_type", "") == event_type: result = event
	return result


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
