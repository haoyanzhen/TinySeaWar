extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "supply point configuration loads")
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_harbor_3v3", 3101).get("ok", false), "supply point fixture starts")
	var facility_id := "facility.harbor.supply_west"
	var supply: Dictionary = session.facility_service.facilities_by_id[facility_id]
	var unrelated_before: Dictionary = session.facility_service.facilities_by_id["facility.harbor.communication_east"].duplicate(true)
	_check(supply.get("faction_id") == "neutral" and supply.get("operation_state") == "Dormant", "supply point starts neutral and dormant")
	var player: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	var ally: Dictionary = session.state["units_by_id"]["unit.player.yukikaze"]
	var enemy: Dictionary = session.state["units_by_id"]["unit.enemy.anshan"]
	var center: Vector2 = session.facility_service.interaction_center(facility_id)
	player["position"] = center
	_check(session.facility_service.declare_control(facility_id, player).get("accepted", false), "player starts area control")
	var control_events: Array = session.facility_service.advance(5.1, 5.1, session.state["units_by_id"])
	_check(_has_event(control_events, "FacilityControlCompleted") and supply.get("faction_id") == "player" and supply.get("operation_state") == "Active", "area control acquires and activates supply")

	enemy["position"] = center
	enemy["current_speed"] = 0.0
	_check(session.facility_service.request_service(facility_id, enemy).get("reason_code") == "FACILITY_NOT_ACTIVE", "enemy ship cannot use player supply")
	player["current_speed"] = 30.0
	_check(session.facility_service.request_service(facility_id, player).get("reason_code") == "BERTH_SPEED_TOO_HIGH", "high-speed pass cannot start supply")
	player["current_speed"] = 0.0
	var first_service: Dictionary = session.facility_service.request_service(facility_id, player)
	_check(first_service.get("accepted", false) and supply.get("interaction_state") == "Moored", "low-speed friendly ship occupies the authored berth")
	ally["position"] = center
	ally["current_speed"] = 0.0
	_check(session.facility_service.request_service(facility_id, ally).get("reason_code") == "FACILITY_SERVICE_NOT_ALLOWED", "occupied single berth rejects a second ship")
	player["position"] = center + Vector2(500.0, 0.0)
	var leave_events: Array = session.facility_service.advance(0.1, 5.2, session.state["units_by_id"])
	_check(_has_event(leave_events, "FacilityActionInterrupted") and supply.get("service_state", {}).is_empty() and supply.get("last_interruption_reason") == "UNIT_LEFT_INTERACTION_AREA", "leaving the berth interrupts and resets service")

	player["position"] = center
	player["current_speed"] = 0.0
	_check(session.facility_service.request_service(facility_id, player).get("accepted", false), "ship can restart after an interrupted service")
	session.facility_service.advance(2.0, 7.2, session.state["units_by_id"])
	var damage_events: Array = session.facility_service.apply_damage(facility_id, 1.0, "test")
	_check(_has_event(damage_events, "FacilityActionInterrupted") and supply.get("service_state", {}).is_empty() and supply.get("last_interruption_reason") == "FACILITY_DAMAGED", "facility damage interrupts and resets partial service")

	player["position"] = center
	player["current_speed"] = 0.0
	for weapon_state in player["weapon_states"]: weapon_state["reload_remaining"] = 9.0
	player["skill_state"]["cooldown_remaining"] = 20.0
	_check(session.facility_service.request_service(facility_id, player).get("accepted", false), "friendly ship starts final supply service")
	var completion_events: Array = session.facility_service.advance(7.1, 14.3, session.state["units_by_id"])
	for event in completion_events: session._handle_facility_event(event)
	var all_ready := true
	for weapon_state in player["weapon_states"]:
		if not is_zero_approx(float(weapon_state.get("reload_remaining", -1.0))): all_ready = false
	_check(_has_event(completion_events, "FacilityServiceCompleted") and all_ready and is_equal_approx(float(player["skill_state"]["cooldown_remaining"]), 8.0) and _has_event(session._event_buffer, "UnitServiced"), "completion restores reloads and shortens skill cooldown by twelve seconds")

	session.facility_service.suppress(facility_id, 10.0, "test")
	_check(session.facility_service.request_service(facility_id, player).get("reason_code") == "FACILITY_NOT_ACTIVE", "suppressed supply refuses new service")
	var unrelated_after: Dictionary = session.facility_service.facilities_by_id["facility.harbor.communication_east"]
	_check(unrelated_after.get("faction_id") == unrelated_before.get("faction_id") and unrelated_after.get("operation_state") == unrelated_before.get("operation_state") and is_equal_approx(float(unrelated_after.get("current_hp", 0.0)), float(unrelated_before.get("current_hp", -1.0))), "supply control and service do not alter other facilities")
	var destroy_events: Array = session.facility_service.apply_damage(facility_id, 100000.0, "test")
	_check(_has_event(destroy_events, "FacilityDestroyed") and supply.get("life_state") == "Destroyed" and supply.get("operation_state") == "Disabled", "supply remains suppressible and destroyable")

	if failures.is_empty():
		print("PASS: %d supply point checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d supply point checks" % [failures.size(), checks])
		quit(1)


func _has_event(events: Array, event_type: String) -> bool:
	for event in events:
		if event.get("event_type", "") == event_type: return true
	return false


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
