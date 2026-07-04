extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "airfield and mission configuration loads")
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_harbor_3v3", 3201).get("ok", false), "airfield fixture starts")
	var airfield_id := "facility.harbor.airfield_east"
	var communication_id := "facility.harbor.communication_east"
	var airfield: Dictionary = session.facility_service.facilities_by_id[airfield_id]
	var definition: Dictionary = session.facility_service.definition_for(airfield_id)
	_check(airfield.get("faction_id") == "enemy" and airfield.get("operation_state") == "Active" and "RemoteCommand" in definition.get("operation_modes", []) and "AreaControl" not in definition.get("operation_modes", []), "airfield starts enemy-active with only remote mission entry")
	var surface_unit: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	surface_unit["position"] = session.facility_service.interaction_center(airfield_id)
	_check(not session.facility_service.declare_control(airfield_id, surface_unit).get("accepted", false), "surface ships cannot capture the airfield")
	_check(is_equal_approx(float(airfield.get("max_hp", 0.0)), 2600.0) and is_equal_approx(float(definition.get("suppression_damage_threshold", 0.0)), 140.0) and is_equal_approx(float(definition.get("suppression_duration", 0.0)), 15.0), "airfield exposes authored durability and suppression rules")

	var target_position: Vector2 = session.state["units_by_id"]["unit.player.aurora"]["position"]
	var recon_request: Dictionary = session.facility_service.request_support(airfield_id, "support_mission.air_recon", "enemy", target_position, 0.0, {})
	_check(recon_request.get("accepted", false) and recon_request.get("event", {}).get("mission_state") == "Preparing", "recon mission enters Preparing through remote command")
	var recon_launch: Array = session.facility_service.advance(2.1, 2.1, session.state["units_by_id"])
	_check(_has_event(recon_launch, "SupportMissionLaunched"), "prepared recon mission transitions to EnRoute")
	var recon_complete: Array = session.facility_service.advance(4.0, 6.1, session.state["units_by_id"])
	for event in recon_complete: session._handle_facility_event(event)
	_check(_has_event(recon_complete, "SupportMissionCompleted") and _has_support_effect(session, "Reconnaissance"), "recon mission completes into an observation effect")

	airfield["cooldown_remaining"] = 0.0
	var patrol_cancel_request: Dictionary = session.facility_service.request_support(airfield_id, "support_mission.fighter_patrol", "enemy", target_position, 7.0, {})
	_check(patrol_cancel_request.get("accepted", false), "fighter patrol can be prepared")
	session.facility_service.suppress(airfield_id, 15.0, "test")
	var preparing_cancel: Array = session.facility_service.advance(0.1, 7.1, session.state["units_by_id"])
	_check(_has_event(preparing_cancel, "SupportMissionCancelled") and _event(preparing_cancel, "SupportMissionCancelled").get("mission_state") == "Preparing", "airfield suppression cancels a mission before launch")
	var damage_events: Array = session.facility_service.apply_damage(airfield_id, 100000.0, "test")
	var expected_floor := float(airfield.get("max_hp", 0.0)) * 0.1
	_check(airfield.get("life_state") == "Alive" and is_equal_approx(float(airfield.get("current_hp", 0.0)), expected_floor) and _has_event(damage_events, "FacilityDamageLimited") and not _has_event(damage_events, "FacilityDestroyed"), "airfield damage is floor-limited and only extends suppression")
	session.facility_service.advance(45.1, 52.2, session.state["units_by_id"])
	_check(airfield.get("operation_state") == "Active", "airfield recovers when suppression expires and communication remains valid")

	airfield["cooldown_remaining"] = 0.0
	var patrol_request: Dictionary = session.facility_service.request_support(airfield_id, "support_mission.fighter_patrol", "enemy", target_position, 53.0, {})
	_check(patrol_request.get("accepted", false), "fighter patrol starts after recovery")
	var patrol_launch: Array = session.facility_service.advance(2.1, 55.1, session.state["units_by_id"])
	_check(_has_event(patrol_launch, "SupportMissionLaunched"), "fighter patrol leaves the airfield")
	session.facility_service.suppress(airfield_id, 15.0, "test")
	var patrol_complete: Array = session.facility_service.advance(6.0, 61.1, session.state["units_by_id"])
	for event in patrol_complete: session._handle_facility_event(event)
	_check(_has_event(patrol_complete, "SupportMissionCompleted") and _has_support_effect(session, "FighterPatrol"), "en-route fighter patrol continues after airfield suppression")
	session.facility_service.advance(15.1, 76.2, session.state["units_by_id"])

	airfield["cooldown_remaining"] = 0.0
	var strike_request: Dictionary = session.facility_service.request_support(airfield_id, "support_mission.airstrike", "enemy", target_position, 77.0, {})
	_check(strike_request.get("accepted", false), "airstrike mission starts")
	var strike_launch: Array = session.facility_service.advance(2.1, 79.1, session.state["units_by_id"])
	_check(_has_event(strike_launch, "SupportMissionLaunched"), "airstrike reaches EnRoute before communication loss")
	var communication_damage: Array = session.facility_service.apply_damage(communication_id, 100000.0, "test")
	session.facility_service.advance(0.1, 79.2, session.state["units_by_id"])
	_check(_has_event(communication_damage, "FacilityDestroyed") and airfield.get("operation_state") == "Silent", "loss of all communication sources silences the airfield")
	var silent_request: Dictionary = session.facility_service.request_support(airfield_id, "support_mission.air_recon", "enemy", target_position, 79.2, {})
	_check(silent_request.get("reason_code") == "FACILITY_NOT_ACTIVE", "silent airfield rejects new missions")
	var strike_complete: Array = session.facility_service.advance(7.9, 87.1, session.state["units_by_id"])
	session._event_buffer.clear()
	for event in strike_complete: session._handle_facility_event(event)
	_check(_has_event(strike_complete, "SupportMissionCompleted") and _count_event(session._event_buffer, "AttackResolved") == 3 and _has_event(session._event_buffer, "SupportMissionResolved"), "en-route airstrike continues after communication silence and resolves three salvos")

	if failures.is_empty():
		print("PASS: %d airfield mission checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d airfield mission checks" % [failures.size(), checks])
		quit(1)


func _has_support_effect(session, effect_type: String) -> bool:
	for effect in session.state.get("support_effects_by_id", {}).values():
		if effect.get("effect_type", "") == effect_type: return true
	return false


func _event(events: Array, event_type: String) -> Dictionary:
	for event in events:
		if event.get("event_type", "") == event_type: return event
	return {}


func _has_event(events: Array, event_type: String) -> bool:
	return not _event(events, event_type).is_empty()


func _count_event(events: Array, event_type: String) -> int:
	var count := 0
	for event in events:
		if event.get("event_type", "") == event_type: count += 1
	return count


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
