extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "facility state definitions load")
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_harbor_3v3", 2801).get("ok", false), "harbor lifecycle fixture starts")
	var service = session.facility_service
	var battery_id := "facility.harbor.battery_west"
	var communication_id := "facility.harbor.communication_east"
	var battery: Dictionary = service.facilities_by_id[battery_id]
	var communication: Dictionary = service.facilities_by_id[communication_id]
	_check(battery.get("life_state") == "Alive" and battery.get("faction_id") == "enemy" and battery.get("operation_state") == "Active" and battery.get("interaction_state") == "Idle", "life, ownership, operation, and interaction states are independent")

	communication["faction_id"] = "player"
	var mismatch_events: Array = service.advance(0.1, 0.1, session.state["units_by_id"])
	_check(battery.get("operation_state") == "Silent" and not service.is_operational(battery_id) and _has_event(mismatch_events, "FacilityOperationStateChanged"), "cross-faction dependency silences the dependent facility")
	communication["faction_id"] = "enemy"
	var restored_events: Array = service.advance(0.1, 0.2, session.state["units_by_id"])
	_check(battery.get("operation_state") == "Active" and service.is_operational(battery_id) and _has_event(restored_events, "FacilityOperationStateChanged"), "valid same-faction dependency restores the desired operation state")
	service.suppress(communication_id, 12.0, "test")
	service.advance(0.1, 0.3, session.state["units_by_id"])
	var dependency_recovery_events: Array = service.advance(12.1, 12.4, session.state["units_by_id"])
	_check(communication.get("operation_state") == "Active" and battery.get("operation_state") == "Active" and _has_event(dependency_recovery_events, "FacilityRecovered"), "dependency recovery refreshes dependent facilities in the same advance call")

	var first_hit: Array = service.apply_damage(battery_id, 60.0, "test")
	var second_hit: Array = service.apply_damage(battery_id, 60.0, "test")
	_check(not _has_event(first_hit, "FacilitySuppressed") and _has_event(first_hit, "FacilitySuppressionAccumulated") and _has_event(second_hit, "FacilitySuppressed"), "sub-threshold hits accumulate into suppression")
	var recovery_events: Array = service.advance(12.1, 24.5, session.state["units_by_id"])
	_check(battery.get("operation_state") == "Active" and _has_event(recovery_events, "FacilityRecovered"), "suppression recovery rechecks desired state and dependencies")

	var floor_events: Array = service.apply_damage(battery_id, 100000.0, "test")
	var expected_floor := float(battery.get("max_hp", 0.0)) * 0.1
	_check(battery.get("life_state") == "Alive" and is_equal_approx(float(battery.get("current_hp", 0.0)), expected_floor) and _has_event(floor_events, "FacilityDamageLimited") and not _has_event(floor_events, "FacilityDestroyed"), "non-destroyable facility clamps damage and emits feedback")
	_check(service.validate_runtime_state(battery_id).is_empty(), "valid non-destroyable suppressed state passes runtime combination validation")
	var attacker: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	session._event_buffer.clear()
	session._resolve_facility_attack({"attack_id":"facility.floor.test", "source_unit_id":attacker["entity_id"], "source_weapon_id":"weapon.warspite_381_he", "target_facility_id":battery_id, "target_position":battery["position"], "origin":attacker["position"], "accuracy_modifier":0.0}, attacker, true)
	var attack_event: Dictionary = _event(session._event_buffer, "AttackResolved")
	_check(not bool(attack_event.get("damage_result", {}).get("caused_sinking", true)) and is_zero_approx(float(attack_event.get("damage_result", {}).get("final_damage", -1.0))) and bool(attack_event.get("damage_result", {}).get("facility_damage_limited", false)), "shared attack result reports the actual floor-limited facility outcome")

	var observation_id := "facility.harbor.observation_west"
	var destroyed_events: Array = service.apply_damage(observation_id, 100000.0, "test")
	var observation: Dictionary = service.facilities_by_id[observation_id]
	_check(observation.get("life_state") == "Destroyed" and observation.get("operation_state") == "Disabled" and _has_event(destroyed_events, "FacilityDestroyed"), "destroyable facility separates destroyed life from disabled operation")
	observation["operation_state"] = "Active"
	_check("DESTROYED_NOT_DISABLED" in service.validate_runtime_state(observation_id), "invalid destroyed-active combination is rejected")

	var bad_definition: Dictionary = registry.get_definition("facilities", "facility.coastal_battery").duplicate(true)
	bad_definition["combat_disposition"]["damage_floor_ratio"] = 0.0
	registry.errors.clear()
	registry._validate_facility_definition(bad_definition)
	_check(not registry.errors.is_empty(), "definition validation rejects a non-destroyable facility without a damage floor")

	if failures.is_empty():
		print("PASS: %d facility state lifecycle checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d facility state lifecycle checks" % [failures.size(), checks])
		quit(1)


func _has_event(events: Array, event_type: String) -> bool:
	for event in events:
		if event.get("event_type", "") == event_type: return true
	return false


func _event(events: Array, event_type: String) -> Dictionary:
	for event in events:
		if event.get("event_type", "") == event_type: return event
	return {}


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
