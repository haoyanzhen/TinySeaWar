extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "repair-berth configuration loads")
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_harbor_3v3", 42016).get("ok", false), "harbor repair-berth fixture starts")
	var facility_id := "facility.harbor.repair_berth_east"
	var facility: Dictionary = session.facility_service.facilities_by_id[facility_id]
	var definition: Dictionary = session.facility_service.definition_for(facility_id)
	var profile: Dictionary = definition["berthing_service"]
	_check(facility.get("faction_id") == "neutral" and facility.get("operation_state") == "Dormant", "repair berth starts neutral and dormant")
	_check(definition.get("area_control", {}).get("capturable", false) and definition.get("combat_disposition", {}).get("suppressible", false) and definition.get("combat_disposition", {}).get("destroyable", false), "repair berth is capturable, suppressible, and destroyable")
	_check(profile.get("berth_state") == "Docked" and profile.get("hold_while_docked") and is_equal_approx(float(profile.get("interrupt_on_heavy_damage_ratio", 0.0)), 0.12), "repair berth declares docking, holding, and heavy-hit rules")

	var unit: Dictionary = session.state["units_by_id"]["unit.player.aurora"]
	_prepare_unit(unit, facility, session.facility_service.interaction_center(facility_id))
	_check(session.facility_service.declare_control(facility_id, unit).get("accepted", false), "player can capture the repair berth from its interaction water")
	session.facility_service.advance(6.1, 6.1, session.state["units_by_id"])
	_check(facility.get("faction_id") == "player" and facility.get("operation_state") == "Active", "capture activates repair for the new owner")

	var enemy: Dictionary = session.state["units_by_id"]["unit.enemy.kirov"]
	_prepare_unit(enemy, facility, unit["position"])
	_check(session.facility_service.request_service(facility_id, enemy).get("reason_code") == "FACILITY_NOT_ACTIVE", "enemy ship cannot request repair from a player berth")
	unit["current_speed"] = float(profile["max_entry_speed"]) + 1.0
	_check(session.facility_service.request_service(facility_id, unit).get("reason_code") == "BERTH_SPEED_TOO_HIGH", "repair rejects excessive entry speed")
	unit["current_speed"] = 0.0
	unit["heading"] = deg_to_rad(float(facility["heading"]) + float(profile["heading_tolerance_degrees"]) + 5.0)
	_check(session.facility_service.request_service(facility_id, unit).get("reason_code") == "BERTH_HEADING_INVALID", "repair rejects an invalid docking heading")
	_prepare_unit(unit, facility, session.facility_service.interaction_center(facility_id))
	var request := session._apply_command({"command_id":"repair.start", "command_type":"RequestFacilityService", "issuer_id":"player", "unit_id":unit["entity_id"], "facility_id":facility_id})
	_check(request.get("accepted", false) and unit.get("movement_state", {}).get("mode") == "Docked" and facility.get("interaction_state") == "Docked", "accepted repair establishes Docked and fixed movement state")
	var dock_position: Vector2 = unit["position"]
	unit["position"] += Vector2(40.0, 0.0)
	unit["current_speed"] = 30.0
	session._update_movement(0.1)
	_check(unit["position"] == dock_position and is_zero_approx(float(unit["current_speed"])), "docked ship is held at its entry position")
	var docking_events: Array = session.facility_service.advance(0.1, 6.2, session.state["units_by_id"])
	_check(_has_event(docking_events, "FacilityDockingCompleted") and is_zero_approx(float(facility.get("service_state", {}).get("progress", -1.0))), "repair timer starts only after Docked transitions to Servicing")

	var second: Dictionary = session.state["units_by_id"]["unit.player.yukikaze"]
	_prepare_unit(second, facility, dock_position)
	_check(session.facility_service.request_service(facility_id, second).get("reason_code") == "FACILITY_SERVICE_NOT_ALLOWED", "single berth rejects a second ship while occupied")
	var move_target := Vector2(2048.0, 1870.0)
	var move := session._apply_command({"command_id":"repair.undock", "command_type":"MoveUnits", "issuer_id":"player", "issuer_type":"Player", "unit_id":unit["entity_id"], "target_position":move_target})
	_check(move.get("accepted", false) and facility.get("service_state", {}).is_empty() and unit.get("movement_state", {}).get("mode") == "PlayerMoveOrder", "accepted movement order undocks and interrupts repair")

	_prepare_unit(unit, facility, dock_position)
	_check(session._apply_command({"command_id":"repair.heavy", "command_type":"RequestFacilityService", "issuer_id":"player", "unit_id":unit["entity_id"], "facility_id":facility_id}).get("accepted", false), "repair can restart after undocking")
	var below_threshold: Dictionary = session.facility_service.interrupt_service_on_unit_damage(unit["entity_id"], unit["max_hp"] * 0.119, unit["max_hp"])
	_check(below_threshold.is_empty() and not facility.get("service_state", {}).is_empty(), "damage below the heavy-hit threshold keeps repair active")
	var heavy_hit: Dictionary = session.facility_service.interrupt_service_on_unit_damage(unit["entity_id"], unit["max_hp"] * 0.12, unit["max_hp"])
	_check(heavy_hit.get("reason_code") == "UNIT_HEAVY_DAMAGE" and facility.get("service_state", {}).is_empty(), "heavy hit interrupts repair and resets progress")

	_prepare_unit(unit, facility, dock_position)
	session._apply_command({"command_id":"repair.suppress", "command_type":"RequestFacilityService", "issuer_id":"player", "unit_id":unit["entity_id"], "facility_id":facility_id})
	var suppression_events: Array = session.facility_service.suppress(facility_id, 3.0, "test")
	_check(_event(suppression_events, "FacilityActionInterrupted").get("reason_code") == "FACILITY_SUPPRESSED", "facility suppression interrupts repair")
	_activate_repair(facility)

	_prepare_unit(unit, facility, dock_position)
	session._apply_command({"command_id":"repair.leave", "command_type":"RequestFacilityService", "issuer_id":"player", "unit_id":unit["entity_id"], "facility_id":facility_id})
	unit["position"] = Vector2.ZERO
	var leave_events: Array = session.facility_service.advance(0.1, 7.0, session.state["units_by_id"])
	_check(_event(leave_events, "FacilityActionInterrupted").get("reason_code") == "UNIT_LEFT_INTERACTION_AREA", "leaving the berth interrupts repair")

	_prepare_unit(unit, facility, dock_position)
	session._apply_command({"command_id":"repair.sink", "command_type":"RequestFacilityService", "issuer_id":"player", "unit_id":unit["entity_id"], "facility_id":facility_id})
	session._event_buffer.clear()
	session._sink_unit(unit, "test")
	_check(_event(session._event_buffer, "FacilityActionInterrupted").get("reason_code") == "UNIT_SUNK", "sinking interrupts repair with an explicit reason")
	unit["life_state"] = "Alive"
	unit["current_hp"] = float(unit["max_hp"]) * 0.70
	_prepare_unit(unit, facility, dock_position)
	var unrelated_before: Dictionary = session.facility_service.facilities_by_id["facility.harbor.communication_east"].duplicate(true)
	session._apply_command({"command_id":"repair.complete", "command_type":"RequestFacilityService", "issuer_id":"player", "unit_id":unit["entity_id"], "facility_id":facility_id})
	session.facility_service.advance(0.1, 8.0, session.state["units_by_id"])
	var completion_events: Array = session.facility_service.advance(9.0, 17.0, session.state["units_by_id"])
	var completion := _event(completion_events, "FacilityServiceCompleted")
	session._handle_facility_event(completion)
	_check(is_equal_approx(float(unit["current_hp"]), float(unit["max_hp"]) * 0.80), "completed repair restores HP without exceeding the per-battle cap")
	var unrelated_after: Dictionary = session.facility_service.facilities_by_id["facility.harbor.communication_east"]
	_check(unrelated_after.get("faction_id") == unrelated_before.get("faction_id") and unrelated_after.get("operation_state") == unrelated_before.get("operation_state") and unrelated_after.get("current_hp") == unrelated_before.get("current_hp"), "repair completion does not alter another facility")

	if failures.is_empty():
		print("PASS: %d repair-berth checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d repair-berth checks" % [failures.size(), checks])
		quit(1)


func _prepare_unit(unit: Dictionary, facility: Dictionary, position: Vector2) -> void:
	unit["position"] = position
	unit["current_speed"] = 0.0
	unit["heading"] = deg_to_rad(float(facility.get("heading", 0.0)))
	unit["movement_state"] = {"mode":"HoldPosition", "target_position":position, "waypoints":[], "waypoint_index":0}


func _activate_repair(facility: Dictionary) -> void:
	facility["life_state"] = "Alive"
	facility["faction_id"] = "player"
	facility["desired_operation_state"] = "Active"
	facility["operation_state"] = "Active"
	facility["suppression_remaining"] = 0.0
	facility["service_state"] = {}
	facility["interaction_state"] = "Idle"


func _event(events: Array, event_type: String) -> Dictionary:
	for event in events:
		if event.get("event_type", "") == event_type: return event
	return {}


func _has_event(events: Array, event_type: String) -> bool:
	return not _event(events, event_type).is_empty()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
