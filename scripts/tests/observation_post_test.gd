extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "observation post configuration loads")
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_harbor_3v3", 2901).get("ok", false), "observation post fixture starts")
	var facility_id := "facility.harbor.observation_west"
	var facility: Dictionary = session.facility_service.facilities_by_id[facility_id]
	_check(facility.get("faction_id") == "neutral" and facility.get("operation_state") == "Dormant" and session.facility_service.observation_sources("player").is_empty(), "harbor observation post starts neutral, dormant, and inactive")

	var controller: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	var unrelated_before: Dictionary = session.facility_service.facilities_by_id["facility.harbor.communication_east"].duplicate(true)
	controller["position"] = session.facility_service.interaction_center(facility_id)
	_check(session.facility_service.declare_control(facility_id, controller).get("accepted", false), "player declares observation post area control")
	var control_events: Array = session.facility_service.advance(5.1, 5.1, session.state["units_by_id"])
	var sources: Array = session.facility_service.observation_sources("player")
	_check(facility.get("faction_id") == "player" and facility.get("operation_state") == "Active" and _has_event(control_events, "FacilityControlCompleted") and sources.size() == 1 and sources[0].get("contact_type") == "Optical", "control activates a fixed optical source for the new owner")
	var unrelated_after: Dictionary = session.facility_service.facilities_by_id["facility.harbor.communication_east"]
	_check(unrelated_after.get("faction_id") == unrelated_before.get("faction_id") and unrelated_after.get("operation_state") == unrelated_before.get("operation_state"), "observation post ownership does not control unrelated facilities")

	for unit in session.state["units_by_id"].values():
		if unit.get("faction_id") == "player": unit["life_state"] = "Sunk"
	var target: Dictionary = session.state["units_by_id"]["unit.enemy.kirov"]
	target["stats"]["concealment_distance"] = 3000.0
	var source_position: Vector2 = sources[0]["position"]
	var clear_point := _find_point(session, source_position, 850.0, true)
	_check(clear_point != Vector2.INF, "fixture finds a clear optical test point")
	target["position"] = clear_point
	_configure_visibility(session, 1.0)
	_check(session._fleet_detects("player", target), "active post detects a clear in-range target")
	_configure_visibility(session, 0.58)
	_check(not session._fleet_detects("player", target), "weather visibility multiplier limits observation range")
	_configure_visibility(session, 0.72)
	_check(not session._fleet_detects("player", target), "night visibility multiplier limits observation range")
	_configure_fog(session, target["position"])
	_check(not session._fleet_detects("player", target), "local sea fog limits observation range")

	_configure_visibility(session, 1.0)
	var blocked_point := _find_blocked_point(session, source_position)
	_check(blocked_point != Vector2.INF, "fixture finds an island-shadow test point")
	if blocked_point != Vector2.INF:
		target["position"] = blocked_point
		_check(not session._fleet_detects("player", target), "island line of sight blocks the optical post")
	var distant_point := _find_point(session, source_position, 1250.0, true)
	_check(distant_point != Vector2.INF, "fixture finds an out-of-range water point")
	if distant_point != Vector2.INF:
		target["position"] = distant_point
		_check(not session._fleet_detects("player", target), "authored observation distance remains a hard optical limit")

	session.facility_service.suppress(facility_id, 10.0, "test")
	_check(session.facility_service.observation_sources("player").is_empty(), "suppression removes the optical source")
	session.facility_service.advance(10.1, 15.2, session.state["units_by_id"])
	_check(session.facility_service.observation_sources("player").size() == 1, "recovery restores the optical source")
	var destroy_events: Array = session.facility_service.apply_damage(facility_id, 100000.0, "test")
	_check(_has_event(destroy_events, "FacilityDestroyed") and session.facility_service.observation_sources("player").is_empty(), "destruction permanently removes the optical source")

	if failures.is_empty():
		print("PASS: %d observation post checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d observation post checks" % [failures.size(), checks])
		quit(1)


func _configure_visibility(session, multiplier: float) -> void:
	session.terrain_context_service.configure(session.terrain_query, {"global_environment":{"optical_visibility_multiplier":multiplier}, "zones":[]}, [])


func _configure_fog(session, position: Vector2) -> void:
	var half := 120.0
	var polygon := [[position.x-half, position.y-half], [position.x+half, position.y-half], [position.x+half, position.y+half], [position.x-half, position.y+half]]
	session.terrain_context_service.configure(session.terrain_query, {"global_environment":{"optical_visibility_multiplier":1.0}, "zones":[{"id":"test.fog", "effect_id":"test.fog.effect", "polygon":polygon, "position":[0,0], "intensity":1.0}]}, [{"id":"test.fog.effect", "definition_type":"EnvironmentEffect", "priority":60, "stack_rule":"Highest", "context":{"optical_visibility_multiplier":0.62}}])


func _find_point(session, origin: Vector2, distance: float, require_los: bool) -> Vector2:
	for index in range(72):
		var candidate: Vector2 = origin + Vector2.RIGHT.rotated(float(index) * TAU / 72.0) * distance
		if not session._inside_map(candidate) or not session.terrain_query.can_occupy_circle(candidate, 20.0, ["Surface", "ShallowDraft"]): continue
		if require_los and not session.terrain_query.has_surface_line_of_sight(origin, candidate): continue
		return candidate
	return Vector2.INF


func _find_blocked_point(session, origin: Vector2) -> Vector2:
	for distance in [350.0, 500.0, 700.0, 900.0, 1050.0]:
		for index in range(72):
			var candidate: Vector2 = origin + Vector2.RIGHT.rotated(float(index) * TAU / 72.0) * distance
			if not session._inside_map(candidate) or not session.terrain_query.can_occupy_circle(candidate, 20.0, ["Surface", "ShallowDraft"]): continue
			if not session.terrain_query.has_surface_line_of_sight(origin, candidate): return candidate
	return Vector2.INF


func _has_event(events: Array, event_type: String) -> bool:
	for event in events:
		if event.get("event_type", "") == event_type: return true
	return false


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
