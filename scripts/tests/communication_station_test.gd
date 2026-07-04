extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "communication and handover configuration loads")
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_harbor_3v3", 3401).get("ok", false), "communication fixture starts")
	var communication_id := "facility.harbor.communication_east"
	var battery_id := "facility.harbor.battery_west"
	var airfield_id := "facility.harbor.airfield_east"
	var radar_id := "facility.harbor.radar_east"
	var communication: Dictionary = session.facility_service.facilities_by_id[communication_id]
	var battery: Dictionary = session.facility_service.facilities_by_id[battery_id]
	var airfield: Dictionary = session.facility_service.facilities_by_id[airfield_id]
	var radar: Dictionary = session.facility_service.facilities_by_id[radar_id]
	var unrelated_before: Dictionary = session.facility_service.facilities_by_id["facility.harbor.observation_west"].duplicate(true)
	_check(communication.get("faction_id") == "enemy" and communication.get("operation_state") == "Active" and session.facility_service.definition_for(communication_id).get("area_control", {}).get("capturable", false), "communication station starts enemy-active and capturable")
	_check(communication_id in battery.get("requires_any_active", []) and communication_id in airfield.get("requires_any_active", []) and communication_id not in radar.get("requires_any_active", []), "only explicitly declared facilities consume the communication chain")

	session.facility_service.suppress(communication_id, 12.0, "test")
	session.facility_service.advance(0.1, 0.1, session.state["units_by_id"])
	_check(communication.get("operation_state") == "Suppressed" and battery.get("operation_state") == "Disabled" and airfield.get("operation_state") == "Disabled" and radar.get("operation_state") == "Dormant", "temporary relay suppression disables only declared dependents")
	session.facility_service.advance(12.1, 12.2, session.state["units_by_id"])
	_check(communication.get("operation_state") == "Active" and battery.get("operation_state") == "Active" and airfield.get("operation_state") == "Active", "relay recovery restores same-faction dependents")

	var player: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	player["position"] = session.facility_service.interaction_center(communication_id)
	_check(session.facility_service.declare_control(communication_id, player).get("accepted", false), "player can contest the communication station")
	var capture_events: Array = session.facility_service.advance(6.1, 18.3, session.state["units_by_id"])
	_check(_has_event(capture_events, "FacilityControlCompleted") and communication.get("faction_id") == "player", "area control transfers only communication ownership")
	_check(battery.get("faction_id") == "enemy" and airfield.get("faction_id") == "enemy" and radar.get("faction_id") == "enemy" and battery.get("operation_state") == "Silent" and airfield.get("operation_state") == "Silent", "ordinary relay capture does not transfer dependents and breaks the old faction chain")
	_check(not session.handover_facility_system_from_scenario("harbor.defense_system_handover", "enemy").get("accepted", false), "explicit handover requires control by the receiving faction")
	var handover: Dictionary = session.handover_facility_system_from_scenario("harbor.defense_system_handover", "player")
	_check(handover.get("accepted", false) and _has_event(handover.get("events", []), "FacilitySystemHandedOver"), "authored scenario event performs explicit defense-system handover")
	_check(battery.get("faction_id") == "player" and airfield.get("faction_id") == "player" and radar.get("faction_id") == "player" and battery.get("operation_state") == "Active" and airfield.get("operation_state") == "Active" and radar.get("operation_state") == "Dormant", "explicit rule transfers only listed members and recomputes each desired state")
	var unrelated_after: Dictionary = session.facility_service.facilities_by_id["facility.harbor.observation_west"]
	_check(unrelated_after.get("faction_id") == unrelated_before.get("faction_id") and unrelated_after.get("operation_state") == unrelated_before.get("operation_state"), "system handover leaves unlisted facilities unchanged")

	session.facility_service.suppress(communication_id, 12.0, "test")
	session.facility_service.advance(0.1, 18.4, session.state["units_by_id"])
	_check(battery.get("operation_state") == "Disabled" and airfield.get("operation_state") == "Disabled", "new owner uses the same temporary communication dependency rules")
	session.facility_service.advance(12.1, 30.5, session.state["units_by_id"])
	_check(battery.get("operation_state") == "Active" and airfield.get("operation_state") == "Active", "new-owner communication recovery is recomputed")
	var destroy_events: Array = session.facility_service.apply_damage(communication_id, 100000.0, "test")
	session.facility_service.advance(0.1, 30.6, session.state["units_by_id"])
	_check(_has_event(destroy_events, "FacilityDestroyed") and communication.get("operation_state") == "Disabled", "destroyed communication source is permanently removed")
	_check(battery.get("operation_state") == "Silent" and airfield.get("operation_state") == "Silent" and radar.get("operation_state") == "Dormant", "permanent relay loss silences declared consumers without affecting undeclared radar")

	if failures.is_empty():
		print("PASS: %d communication station checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d communication station checks" % [failures.size(), checks])
		quit(1)


func _has_event(events: Array, event_type: String) -> bool:
	for event in events:
		if event.get("event_type", "") == event_type: return true
	return false


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
