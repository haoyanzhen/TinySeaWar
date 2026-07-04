extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")
const FacilityService = preload("res://scripts/domain/services/facility_service.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "coastal battery configuration loads")
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_harbor_3v3", 3001).get("ok", false), "coastal battery fixture starts")
	var battery_id := "facility.harbor.battery_west"
	var communication_id := "facility.harbor.communication_east"
	var battery: Dictionary = session.facility_service.facilities_by_id[battery_id]
	var warspite: Dictionary = registry.get_definition("ships", "ship.warspite")
	_check(battery.get("faction_id") == "enemy" and battery.get("operation_state") == "Active" and battery.get("control_policy") == "LockedWhileActive", "harbor enemy battery starts active and interaction-locked")
	_check(is_equal_approx(float(battery.get("max_hp", 0.0)), float(warspite.get("max_hp", -1.0))) and is_equal_approx(float(session.facility_service.definition_for(battery_id).get("armor", 0.0)), float(warspite.get("armor", -1.0))) and session.facility_service.definition_for(battery_id).get("armor_thickness") == warspite.get("armor_thickness"), "battery resolves classic battleship durability and protection reference")
	var player_controller: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	player_controller["position"] = session.facility_service.interaction_center(battery_id)
	_check(not session.facility_service.declare_control(battery_id, player_controller).get("accepted", false), "active enemy battery cannot be seized by ordinary surface interaction")

	var light_target: Dictionary = session.state["units_by_id"]["unit.player.shimakaze"]
	light_target["position"] = Vector2(2200.0, 995.0)
	session.state["visible_by_faction"]["enemy"] = {light_target["entity_id"]:true}
	session._event_buffer.clear()
	session.delayed_attacks.clear()
	session._update_facility_weapons()
	var he_event := _event(session._event_buffer, "FacilityWeaponFired")
	_check(he_event.get("weapon_id") == "weapon.warspite_381_he" and int(he_event.get("shot_count", 0)) == 2 and session.delayed_attacks.size() == 2, "single twin turret fires two HE shells at a light target")
	var he_weapon: Dictionary = registry.get_definition("weapons", "weapon.warspite_381_he")
	_check(is_equal_approx(float(battery["weapon_states"][0]["reload_remaining"]), float(he_weapon["reload_time"])) and is_equal_approx(float(battery["weapon_states"][1]["reload_remaining"]), float(he_weapon["reload_time"])), "AP and HE references share the source weapon reload model")
	for weapon_state in battery["weapon_states"]: weapon_state["reload_remaining"] = 0.0
	light_target["stats"]["armor_thickness"] = "Heavy"
	session._event_buffer.clear()
	session.delayed_attacks.clear()
	session._update_facility_weapons()
	var ap_event := _event(session._event_buffer, "FacilityWeaponFired")
	_check(ap_event.get("weapon_id") == "weapon.warspite_381_ap" and int(ap_event.get("shot_count", 0)) == 2, "battery selects the referenced AP model for a heavy target")

	var damage_events: Array = session.facility_service.apply_damage(battery_id, 100000.0, "test")
	_check(battery.get("life_state") == "Alive" and not _has_event(damage_events, "FacilityDestroyed") and _has_event(damage_events, "FacilityDamageLimited") and _has_event(damage_events, "FacilitySuppressed"), "battery damage produces feedback and suppression without destruction")
	session.facility_service.advance(40.0, 40.0, session.state["units_by_id"])
	var communication: Dictionary = session.facility_service.facilities_by_id[communication_id]
	session.facility_service.suppress(communication_id, 12.0, "test")
	session.facility_service.advance(0.1, 40.1, session.state["units_by_id"])
	_check(battery.get("operation_state") == "Disabled" and not session.facility_service.is_operational(battery_id), "temporary communication suppression pauses the battery without permanent silence")
	session.facility_service.advance(12.1, 52.2, session.state["units_by_id"])
	_check(communication.get("operation_state") == "Active" and battery.get("operation_state") == "Active", "communication recovery reactivates the battery")
	session.facility_service.apply_damage(communication_id, 100000.0, "test")
	session.facility_service.advance(0.1, 52.3, session.state["units_by_id"])
	_check(communication.get("life_state") == "Destroyed" and battery.get("operation_state") == "Silent" and not session.facility_service.is_operational(battery_id), "loss of all authored communication sources permanently silences the battery")
	session._event_buffer.clear()
	session.delayed_attacks.clear()
	session._update_facility_weapons()
	_check(session.delayed_attacks.is_empty(), "silent battery cannot acquire or fire")

	var layout: Dictionary = registry.get_definition("facilities", "facility.layout.harbor_mouth").duplicate(true)
	for placement in layout["placements"]:
		if placement.get("id") == battery_id:
			placement["initial_state_profile"] = "player_dormant"
		if placement.get("id") == communication_id:
			placement["faction_id"] = "player"
	var terrain: Dictionary = registry.get_definition("terrain", "terrain.map.harbor_mouth")
	var friendly_service = FacilityService.new()
	friendly_service.configure(layout, terrain.get("facility_anchors", []), session._resolved_facility_definitions())
	var friendly_battery: Dictionary = friendly_service.facilities_by_id[battery_id]
	var friendly_communication_before: Dictionary = friendly_service.facilities_by_id[communication_id].duplicate(true)
	var friendly_unit: Dictionary = player_controller.duplicate(true)
	friendly_unit["life_state"] = "Alive"
	friendly_unit["faction_id"] = "player"
	friendly_unit["position"] = friendly_service.interaction_center(battery_id)
	_check(friendly_battery.get("faction_id") == "player" and friendly_battery.get("operation_state") == "Dormant" and friendly_service.declare_control(battery_id, friendly_unit).get("accepted", false), "friendly dormant profile accepts owner activation control")
	var friendly_units := {friendly_unit["entity_id"]:friendly_unit}
	friendly_service.advance(6.1, 6.1, friendly_units)
	_check(friendly_battery.get("operation_state") == "Active" and friendly_battery.get("faction_id") == "player", "friendly control activates the battery without changing its owner")
	var friendly_communication_after: Dictionary = friendly_service.facilities_by_id[communication_id]
	_check(friendly_communication_after.get("faction_id") == friendly_communication_before.get("faction_id") and friendly_communication_after.get("operation_state") == friendly_communication_before.get("operation_state"), "battery activation does not control its communication dependency or other facilities")

	if failures.is_empty():
		print("PASS: %d coastal battery checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d coastal battery checks" % [failures.size(), checks])
		quit(1)


func _event(events: Array, event_type: String) -> Dictionary:
	for event in events:
		if event.get("event_type", "") == event_type: return event
	return {}


func _has_event(events: Array, event_type: String) -> bool:
	return not _event(events, event_type).is_empty()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
