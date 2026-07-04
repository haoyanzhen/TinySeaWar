extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "radar station configuration loads")
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_harbor_3v3", 3301).get("ok", false), "radar fixture starts")
	var radar_id := "facility.harbor.radar_east"
	var radar: Dictionary = session.facility_service.facilities_by_id[radar_id]
	var definition: Dictionary = session.facility_service.definition_for(radar_id)
	var rules: Dictionary = definition.get("radar_rules", {})
	_check(radar.get("faction_id") == "enemy" and radar.get("operation_state") == "Dormant" and session.facility_service.radar_sources("enemy").is_empty(), "radar starts enemy-owned, dormant, and inactive")
	_check("AreaControl" not in definition.get("operation_modes", []) and rules.get("contact_type") == "Radar" and not bool(rules.get("weather_affected", true)) and not bool(rules.get("line_of_sight_required", true)) and rules.get("contact_accuracy") == "ExactPosition", "radar declares independent non-optical sensor rules")
	var player: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	player["position"] = session.facility_service.interaction_center(radar_id)
	_check(not session.facility_service.declare_control(radar_id, player).get("accepted", false), "surface ships cannot capture the radar station")
	_check(not session.activate_facility_from_scenario(radar_id, "wrong.event").get("accepted", false), "unrelated scenario event cannot activate radar")
	var communication_before: Dictionary = session.facility_service.facilities_by_id["facility.harbor.communication_east"].duplicate(true)
	_check(session.activate_facility_from_scenario(radar_id, "facility.radar.activate").get("accepted", false) and radar.get("operation_state") == "Active" and session.facility_service.radar_sources("enemy").size() == 1, "authored scenario event activates the radar source")
	var communication_after: Dictionary = session.facility_service.facilities_by_id["facility.harbor.communication_east"]
	_check(communication_after.get("faction_id") == communication_before.get("faction_id") and communication_after.get("operation_state") == communication_before.get("operation_state"), "radar activation does not alter other facilities")

	for unit in session.state["units_by_id"].values():
		if unit.get("faction_id") == "enemy": unit["life_state"] = "Sunk"
	var target: Dictionary = session.state["units_by_id"]["unit.player.aurora"]
	var source_position: Vector2 = session.facility_service.radar_sources("enemy")[0]["position"]
	var blocked_point := _find_blocked_point(session, source_position, float(rules.get("detection_range", 1400.0)))
	_check(blocked_point != Vector2.INF, "fixture finds a water target behind island terrain")
	target["position"] = blocked_point
	target["radar_stealth_state"] = "Exposed"
	session.terrain_context_service.configure(session.terrain_query, {"global_environment":{"optical_visibility_multiplier":0.1}, "zones":[{"id":"test.fog", "effect_id":"test.fog.effect", "polygon":_square(blocked_point, 150.0), "position":[0,0], "intensity":1.0}]}, [{"id":"test.fog.effect", "definition_type":"EnvironmentEffect", "priority":60, "stack_rule":"Highest", "context":{"optical_visibility_multiplier":0.1}}])
	session._event_buffer.clear()
	session._update_detection()
	var enemy_contact: Dictionary = session.state["contacts_by_faction"]["enemy"].get(target["entity_id"], {})
	_check(session.state["visible_by_faction"]["enemy"].has(target["entity_id"]) and enemy_contact.get("primary_contact_type") == "Radar" and enemy_contact.get("contact_accuracy") == "ExactPosition" and enemy_contact.get("last_known_position") == blocked_point, "radar detects an exact contact through darkness, fog, and island shadow")
	_check(_event(session._event_buffer, "ContactAcquired").get("primary_contact_type") == "Radar", "contact event records radar provenance")
	_check(not session.state["contacts_by_faction"]["player"].has(target["entity_id"]), "radar contact remains isolated to the owning faction")
	var enemy_snapshot: Dictionary = session.snapshot("enemy", false)
	var player_snapshot: Dictionary = session.snapshot("player", false)
	_check(enemy_snapshot.get("units", {}).get(target["entity_id"], {}).get("primary_contact_type") == "Radar" and enemy_snapshot.get("contacts", {}).has(target["entity_id"]) and not player_snapshot.get("contacts", {}).has(target["entity_id"]), "battle and minimap snapshots expose radar feedback only to its faction")

	target["radar_stealth_state"] = "Stealthed"
	session._update_detection()
	_check(not session.state["visible_by_faction"]["enemy"].has(target["entity_id"]), "explicit radar stealth blocks radar without relying on optical concealment")
	target["radar_stealth_state"] = "Exposed"
	session._update_detection()
	_check(session.state["visible_by_faction"]["enemy"].has(target["entity_id"]), "explicitly removing radar stealth restores contact")

	session.facility_service.suppress(radar_id, 12.0, "test")
	session._update_detection()
	_check(not session.state["visible_by_faction"]["enemy"].has(target["entity_id"]), "suppressed radar produces no contacts")
	session.facility_service.advance(12.1, 12.1, session.state["units_by_id"])
	session._update_detection()
	_check(radar.get("operation_state") == "Active" and session.state["visible_by_faction"]["enemy"].has(target["entity_id"]), "radar recovers to active sensing")
	var destroy_events: Array = session.facility_service.apply_damage(radar_id, 100000.0, "test")
	session._update_detection()
	_check(_has_event(destroy_events, "FacilityDestroyed") and radar.get("operation_state") == "Disabled" and not session.state["visible_by_faction"]["enemy"].has(target["entity_id"]), "destroyed radar is permanently removed from sensing")
	_check(load("res://scripts/presentation/battle/prototype_battle.gd") != null and load("res://scripts/presentation/battle/battle_hud.gd") != null and load("res://scripts/presentation/battle/terrain_debug_overlay.gd") != null, "world, minimap, and debug radar feedback scripts compile")

	if failures.is_empty():
		print("PASS: %d radar station checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d radar station checks" % [failures.size(), checks])
		quit(1)


func _find_blocked_point(session, origin: Vector2, maximum_range: float) -> Vector2:
	for distance in [350.0, 500.0, 700.0, 900.0, 1100.0, 1300.0]:
		if distance > maximum_range: continue
		for index in range(72):
			var candidate: Vector2 = origin + Vector2.RIGHT.rotated(float(index) * TAU / 72.0) * distance
			if not session._inside_map(candidate) or not session.terrain_query.can_occupy_circle(candidate, 20.0, ["Surface", "ShallowDraft"]): continue
			if not session.terrain_query.has_surface_line_of_sight(origin, candidate): return candidate
	return Vector2.INF


func _square(center: Vector2, half: float) -> Array:
	return [[center.x-half, center.y-half], [center.x+half, center.y-half], [center.x+half, center.y+half], [center.x-half, center.y+half]]


func _event(events: Array, event_type: String) -> Dictionary:
	for event in events:
		if event.get("event_type", "") == event_type: return event
	return {}


func _has_event(events: Array, event_type: String) -> bool:
	return not _event(events, event_type).is_empty()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
