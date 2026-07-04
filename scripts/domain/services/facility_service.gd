extends RefCounted

var facilities_by_id: Dictionary = {}
var support_missions: Array = []
var mine_deployments: Array = []
var definitions_by_id: Dictionary = {}
var mission_sequence := 0


func configure(layout: Dictionary, anchors: Array, definitions: Array) -> void:
	facilities_by_id.clear()
	support_missions.clear()
	mine_deployments.clear()
	definitions_by_id.clear()
	mission_sequence = 0
	for definition in definitions:
		definitions_by_id[str(definition.get("id", ""))] = definition.duplicate(true)
	var anchors_by_id := {}
	for anchor in anchors:
		anchors_by_id[str(anchor.get("id", ""))] = anchor
	for placement in layout.get("placements", []):
		var definition: Dictionary = definitions_by_id.get(str(placement.get("definition_id", "")), {})
		var anchor: Dictionary = anchors_by_id.get(str(placement.get("anchor_id", "")), {})
		if definition.is_empty() or anchor.is_empty():
			continue
		var mission_charges := {}
		for mission_id in definition.get("support_mission_ids", []):
			mission_charges[str(mission_id)] = int(definitions_by_id.get(str(mission_id), {}).get("charges", 0))
		var weapon_states: Array = []
		for weapon_id in definition.get("weapon_ids", [definition.get("weapon_id", "")]):
			if str(weapon_id).is_empty(): continue
			weapon_states.append({"definition_id": str(weapon_id), "reload_remaining": 0.0, "enabled": true})
		var operation_state := str(placement.get("operation_state", "Dormant"))
		facilities_by_id[str(placement["id"])] = {
			"facility_id": str(placement["id"]),
			"definition_id": str(placement["definition_id"]),
			"display_name": str(definition.get("display_name", placement["id"])),
			"asset_semantic": str(definition.get("asset_semantic", "")),
			"capabilities": definition.get("capabilities", []).duplicate(),
			"faction_id": str(placement.get("faction_id", "neutral")),
			"position": _vector2(anchor.get("position", [0.0, 0.0])),
			"muzzle_position": _vector2(anchor.get("muzzle_position", anchor.get("position", [0.0, 0.0]))),
			"observation_position": _vector2(anchor.get("observation_position", anchor.get("position", [0.0, 0.0]))),
			"heading": float(anchor.get("heading", 0.0)),
			"interaction_water_polygon": anchor.get("interaction_water_polygon", []).duplicate(true),
			"target_shape": anchor.get("target_shape", {}).duplicate(true),
			"shore_obstacle_id": str(anchor.get("shore_obstacle_id", "")),
			"life_state": "Alive",
			"operation_state": operation_state,
			"desired_operation_state": operation_state,
			"current_hp": float(definition.get("max_hp", 1.0)),
			"max_hp": float(definition.get("max_hp", 1.0)),
			"interaction_state": "Idle",
			"control_state": {},
			"service_state": {},
			"last_interruption_reason": "",
			"suppression_remaining": 0.0,
			"suppression_damage_accumulated": 0.0,
			"cooldown_remaining": 0.0,
			"charges_remaining": int(definition.get("charges", 0)),
			"remote_charges_remaining": int(definition.get("remote_command", {}).get("charges", 0)),
			"mission_charges_remaining": mission_charges,
			"weapon_states": weapon_states,
			"requires_all_active": placement.get("requires_all_active", []).duplicate(),
			"requires_any_active": placement.get("requires_any_active", []).duplicate(),
			"dependency_rules": placement.get("dependency_rules", {"requires_matching_faction": true}).duplicate(true),
		}
	for facility_id in _sorted_ids(): _refresh_operation_state(facility_id)


func declare_control(facility_id: String, unit: Dictionary) -> Dictionary:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	if facility.is_empty() or str(facility.get("life_state", "")) != "Alive":
		return {"accepted": false, "reason_code": "FACILITY_CONTROL_NOT_ALLOWED"}
	var definition: Dictionary = definition_for(facility_id)
	if "AreaControl" not in definition.get("operation_modes", []) or not bool(definition.get("area_control", {}).get("enabled", false)) or not bool(definition.get("area_control", {}).get("capturable", false)) or not facility.get("control_state", {}).is_empty():
		return {"accepted": false, "reason_code": "FACILITY_CONTROL_NOT_ALLOWED"}
	if facility["operation_state"] == "Suppressed":
		return {"accepted": false, "reason_code": "FACILITY_SUPPRESSED"}
	if str(unit.get("life_state", "")) != "Alive":
		return {"accepted": false, "reason_code": "UNIT_UNAVAILABLE"}
	var unit_faction := str(unit.get("faction_id", ""))
	if "Ownable" not in definition.get("capabilities", []) or str(facility.get("faction_id", "neutral")) == unit_faction and str(facility.get("operation_state", "")) == "Active":
		return {"accepted": false, "reason_code": "FACILITY_CONTROL_NOT_ALLOWED"}
	var inside := Geometry2D.is_point_in_polygon(unit["position"], _polygon(facility.get("interaction_water_polygon", [])))
	facility["control_state"] = {
		"executor_unit_id": str(unit["entity_id"]),
		"faction_id": unit_faction,
		"progress": 0.0,
		"duration": float(definition.get("area_control", {}).get("duration", 5.0)),
		"entered_area": inside,
	}
	facility["last_interruption_reason"] = ""
	facility["interaction_state"] = "Controlling" if inside else "Idle"
	return {"accepted": true, "event": {"event_type": "FacilityControlDeclared", "facility_id": facility_id, "unit_id": unit["entity_id"], "faction_id": unit_faction}}


func request_service(facility_id: String, unit: Dictionary) -> Dictionary:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	var definition := definition_for(facility_id)
	var profile: Dictionary = definition.get("berthing_service", {})
	if facility.is_empty() or "BerthingService" not in definition.get("operation_modes", []) or not facility.get("service_state", {}).is_empty():
		return {"accepted": false, "reason_code": "FACILITY_SERVICE_NOT_ALLOWED"}
	if not is_operational(facility_id) or str(facility.get("faction_id", "")) != str(unit.get("faction_id", "")):
		return {"accepted": false, "reason_code": "FACILITY_NOT_ACTIVE"}
	if str(unit.get("life_state", "")) != "Alive" or not Geometry2D.is_point_in_polygon(unit["position"], _polygon(facility.get("interaction_water_polygon", []))):
		return {"accepted": false, "reason_code": "FACILITY_OUT_OF_RANGE"}
	if absf(float(unit.get("current_speed", 0.0))) > float(profile.get("max_entry_speed", 0.0)):
		return {"accepted": false, "reason_code": "BERTH_SPEED_TOO_HIGH"}
	var tolerance := deg_to_rad(float(profile.get("heading_tolerance_degrees", 180.0)))
	if absf(wrapf(float(unit.get("heading", 0.0)) - deg_to_rad(float(facility.get("heading", 0.0))), -PI, PI)) > tolerance:
		return {"accepted": false, "reason_code": "BERTH_HEADING_INVALID"}
	facility["service_state"] = {"unit_id": str(unit["entity_id"]), "progress": 0.0, "duration": float(profile.get("duration", 1.0)), "service_type": str(profile.get("service_type", ""))}
	facility["last_interruption_reason"] = ""
	facility["interaction_state"] = str(profile.get("berth_state", "Moored"))
	return {"accepted": true, "event": {"event_type": "FacilityServiceStarted", "facility_id": facility_id, "unit_id": unit["entity_id"], "service_type": profile.get("service_type", "")}}


func cancel_action(facility_id: String, unit_id: String) -> Dictionary:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	if facility.is_empty(): return {"accepted": false, "reason_code": "FACILITY_ACTION_NOT_FOUND"}
	var control: Dictionary = facility.get("control_state", {})
	var service: Dictionary = facility.get("service_state", {})
	if str(control.get("executor_unit_id", "")) != unit_id and str(service.get("unit_id", "")) != unit_id:
		return {"accepted": false, "reason_code": "FACILITY_ACTION_NOT_FOUND"}
	facility["control_state"] = {}
	facility["service_state"] = {}
	facility["interaction_state"] = "Idle"
	return {"accepted": true, "event": {"event_type": "FacilityActionInterrupted", "facility_id": facility_id, "unit_id": unit_id, "reason_code": "CANCELLED"}}


func active_action_for_unit(unit_id: String) -> Dictionary:
	for facility_id in _sorted_ids():
		var control: Dictionary = facilities_by_id[facility_id].get("control_state", {})
		if str(control.get("executor_unit_id", "")) == unit_id:
			var result := control.duplicate(true)
			result["action_type"] = "Control"
			result["facility_id"] = facility_id
			return result
		var service: Dictionary = facilities_by_id[facility_id].get("service_state", {})
		if str(service.get("unit_id", "")) == unit_id:
			var result := service.duplicate(true)
			result["action_type"] = "Service"
			result["facility_id"] = facility_id
			return result
	return {}


func request_support(facility_id: String, mission_id: String, faction_id: String, target_position: Vector2, elapsed_time: float, environment_context: Dictionary = {}) -> Dictionary:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	var definition: Dictionary = definition_for(facility_id)
	var mission: Dictionary = definitions_by_id.get(mission_id, {})
	if facility.is_empty() or mission.is_empty() or "SupportMissionProvider" not in definition.get("capabilities", []) or mission_id not in definition.get("support_mission_ids", []):
		return {"accepted": false, "reason_code": "SUPPORT_MISSION_UNAVAILABLE"}
	if not is_operational(facility_id) or facility.get("faction_id") != faction_id:
		return {"accepted": false, "reason_code": "FACILITY_NOT_ACTIVE"}
	if (facility["position"] as Vector2).distance_to(target_position) > float(mission.get("max_range", INF)):
		return {"accepted": false, "reason_code": "TARGET_OUT_OF_RANGE"}
	if str(environment_context.get("aviation_condition", "Normal")) in mission.get("blocked_aviation_conditions", []):
		return {"accepted": false, "reason_code": "AVIATION_WEATHER_BLOCKED"}
	if float(facility.get("cooldown_remaining", 0.0)) > 0.0:
		return {"accepted": false, "reason_code": "SUPPORT_MISSION_UNAVAILABLE"}
	var mission_charges: Dictionary = facility.get("mission_charges_remaining", {})
	if int(mission_charges.get(mission_id, 0)) <= 0:
		return {"accepted": false, "reason_code": "SUPPORT_MISSION_UNAVAILABLE"}
	mission_charges[mission_id] = int(mission_charges[mission_id]) - 1
	facility["cooldown_remaining"] = float(mission.get("cooldown", 0.0))
	mission_sequence += 1
	var arrival_multiplier := float(environment_context.get("aviation_delay_multiplier", 1.0))
	var mission_state := {
		"mission_id": "mission.%06d" % mission_sequence,
		"definition_id": mission_id,
		"facility_id": facility_id,
		"faction_id": faction_id,
		"target_position": target_position,
		"resolve_at_time": elapsed_time + float(mission.get("arrival_time", 0.0)) * arrival_multiplier,
		"state": "Started",
	}
	support_missions.append(mission_state)
	return {"accepted": true, "event": {"event_type": "SupportMissionStarted", "facility_id": facility_id, "mission_id": mission_state["mission_id"], "definition_id": mission_id, "target_position": target_position}}


func request_mine_deployment(facility_id: String, unit: Dictionary, target_position: Vector2, elapsed_time: float, units_by_id: Dictionary, random_seed: int) -> Dictionary:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	var definition := definition_for(facility_id)
	var rules: Dictionary = definition.get("remote_command", {})
	if facility.is_empty() or str(rules.get("command_type", "")) != "MineDeployment": return {"accepted": false, "reason_code": "MINE_DEPLOYMENT_UNAVAILABLE"}
	if not is_operational(facility_id) or facility.get("faction_id", "") != unit.get("faction_id", ""): return {"accepted": false, "reason_code": "FACILITY_NOT_ACTIVE"}
	if float(facility.get("cooldown_remaining", 0.0)) > 0.0 or int(facility.get("remote_charges_remaining", 0)) <= 0: return {"accepted": false, "reason_code": "MINE_DEPLOYMENT_UNAVAILABLE"}
	if (facility.get("position", Vector2.ZERO) as Vector2).distance_to(target_position) > float(rules.get("control_radius", 0.0)): return {"accepted": false, "reason_code": "TARGET_OUT_OF_RANGE"}
	var half_side := float(rules.get("area_side_length", 0.0)) * 0.5
	for other in units_by_id.values():
		var other_position: Vector2 = other.get("position", Vector2.ZERO)
		if other.get("life_state", "") == "Alive" and other.get("faction_id", "") != unit.get("faction_id", "") and absf(other_position.x - target_position.x) <= half_side and absf(other_position.y - target_position.y) <= half_side:
			return {"accepted": false, "reason_code": "MINE_AREA_CONTAINS_ENEMY"}
	facility["cooldown_remaining"] = float(rules.get("cooldown", 0.0))
	facility["remote_charges_remaining"] = int(facility.get("remote_charges_remaining", 0)) - 1
	mission_sequence += 1
	var task := {"mission_id":"mine_deployment.%06d" % mission_sequence, "facility_id":facility_id, "faction_id":unit.get("faction_id", ""), "target_position":target_position, "resolve_at_time":elapsed_time + float(rules.get("duration", 10.0)), "rules":rules.duplicate(true), "random_seed":random_seed}
	mine_deployments.append(task)
	return {"accepted":true, "event":{"event_type":"MineDeploymentStarted", "facility_id":facility_id, "mission_id":task["mission_id"], "unit_id":unit.get("entity_id", ""), "target_position":target_position, "duration":rules.get("duration", 10.0)}}


func advance(delta: float, elapsed_time: float, units_by_id: Dictionary) -> Array:
	var events: Array = []
	for facility_id in _sorted_ids():
		var facility: Dictionary = facilities_by_id[facility_id]
		facility["cooldown_remaining"] = maxf(0.0, float(facility.get("cooldown_remaining", 0.0)) - delta)
		var definition := definition_for(facility_id)
		if str(facility.get("operation_state", "")) != "Suppressed" or bool(definition.get("reload_during_suppression", false)):
			for weapon_state in facility.get("weapon_states", []):
				weapon_state["reload_remaining"] = maxf(0.0, float(weapon_state.get("reload_remaining", 0.0)) - delta)
		var suppression_before := float(facility.get("suppression_remaining", 0.0))
		facility["suppression_remaining"] = maxf(0.0, suppression_before - delta)
		var recovered := suppression_before > 0.0 and is_zero_approx(float(facility["suppression_remaining"])) and str(facility.get("life_state", "")) == "Alive"
		var state_change := _refresh_operation_state(facility_id)
		if not state_change.is_empty():
			state_change["event_type"] = "FacilityRecovered" if recovered else "FacilityOperationStateChanged"
			events.append(state_change)
		_advance_control(facility_id, facility, delta, units_by_id, events)
		_advance_service(facility_id, facility, delta, units_by_id, events)
	# Dependency owners and states may change later in the deterministic ID pass.
	# A second refresh removes ordering dependence before consumers receive the snapshot.
	for facility_id in _sorted_ids():
		var dependency_change := _refresh_operation_state(facility_id)
		if not dependency_change.is_empty(): events.append(dependency_change)
	var remaining: Array = []
	for mission in support_missions:
		if float(mission.get("resolve_at_time", INF)) > elapsed_time:
			remaining.append(mission)
			continue
		if not is_operational(str(mission.get("facility_id", ""))):
			events.append({"event_type": "SupportMissionCancelled", "mission_id": mission["mission_id"], "definition_id": mission["definition_id"], "facility_id": mission["facility_id"], "reason_code": "FACILITY_NOT_ACTIVE"})
		else:
			events.append({"event_type": "SupportMissionCompleted", "mission_id": mission["mission_id"], "definition_id": mission["definition_id"], "facility_id": mission["facility_id"], "faction_id": mission["faction_id"], "target_position": mission["target_position"]})
	support_missions = remaining
	var remaining_mines: Array = []
	for deployment in mine_deployments:
		if float(deployment.get("resolve_at_time", INF)) > elapsed_time:
			remaining_mines.append(deployment)
			continue
		if not is_operational(str(deployment.get("facility_id", ""))):
			events.append({"event_type":"MineDeploymentCancelled", "facility_id":deployment.get("facility_id", ""), "mission_id":deployment.get("mission_id", ""), "reason_code":"FACILITY_NOT_ACTIVE"})
		else:
			var completed: Dictionary = deployment.duplicate(true)
			completed["event_type"] = "MineDeploymentCompleted"
			events.append(completed)
	mine_deployments = remaining_mines
	return events


func _advance_control(facility_id: String, facility: Dictionary, delta: float, units_by_id: Dictionary, events: Array) -> void:
	var control: Dictionary = facility.get("control_state", {})
	if control.is_empty(): return
	var unit: Dictionary = units_by_id.get(str(control.get("executor_unit_id", "")), {})
	if unit.is_empty() or unit.get("life_state") != "Alive" or str(facility.get("life_state", "")) != "Alive" or str(facility.get("operation_state", "")) == "Suppressed":
		_interrupt_action(facility_id, facility, str(control.get("executor_unit_id", "")), "UNIT_UNAVAILABLE" if unit.is_empty() or unit.get("life_state") != "Alive" else "FACILITY_UNAVAILABLE", events)
		return
	var polygon := _polygon(facility.get("interaction_water_polygon", []))
	var inside := Geometry2D.is_point_in_polygon(unit["position"], polygon)
	if not inside:
		if bool(control.get("entered_area", false)):
			_interrupt_action(facility_id, facility, str(unit.get("entity_id", "")), "UNIT_LEFT_INTERACTION_AREA", events)
		else:
			facility["interaction_state"] = "Idle"
		return
	control["entered_area"] = true
	var contested := false
	for other in units_by_id.values():
		if other.get("life_state") == "Alive" and other.get("faction_id") != control.get("faction_id") and Geometry2D.is_point_in_polygon(other.get("position", Vector2.ZERO), polygon):
			contested = true
			break
	facility["interaction_state"] = "Contested" if contested else "Controlling"
	if contested: return
	control["progress"] = float(control.get("progress", 0.0)) + delta
	if float(control["progress"]) + 0.001 < float(control.get("duration", 1.0)): return
	var old_faction := str(facility.get("faction_id", "neutral"))
	facility["faction_id"] = str(control.get("faction_id", old_faction))
	facility["desired_operation_state"] = "Active"
	var state_change := _refresh_operation_state(facility_id)
	facility["control_state"] = {}
	facility["interaction_state"] = "Idle"
	if old_faction != str(facility["faction_id"]):
		events.append({"event_type": "FacilityOwnershipChanged", "facility_id": facility_id, "old_faction_id": old_faction, "faction_id": facility["faction_id"]})
	if not state_change.is_empty(): events.append(state_change)
	events.append({"event_type": "FacilityControlCompleted", "facility_id": facility_id, "unit_id": unit.get("entity_id", ""), "faction_id": facility["faction_id"]})


func _advance_service(facility_id: String, facility: Dictionary, delta: float, units_by_id: Dictionary, events: Array) -> void:
	var service: Dictionary = facility.get("service_state", {})
	if service.is_empty(): return
	var unit: Dictionary = units_by_id.get(str(service.get("unit_id", "")), {})
	var profile: Dictionary = definition_for(facility_id).get("berthing_service", {})
	var available: bool = not unit.is_empty() and unit.get("life_state") == "Alive" and is_operational(facility_id) and unit.get("faction_id") == facility.get("faction_id")
	var in_berth: bool = available and Geometry2D.is_point_in_polygon(unit.get("position", Vector2.ZERO), _polygon(facility.get("interaction_water_polygon", [])))
	if not in_berth:
		_interrupt_action(facility_id, facility, str(service.get("unit_id", "")), "UNIT_LEFT_INTERACTION_AREA" if available else "FACILITY_UNAVAILABLE", events)
		return
	facility["interaction_state"] = "Servicing"
	service["progress"] = float(service.get("progress", 0.0)) + delta
	if float(service["progress"]) + 0.001 < float(service.get("duration", 1.0)): return
	events.append({"event_type": "FacilityServiceCompleted", "facility_id": facility_id, "unit_id": unit["entity_id"], "service_type": service.get("service_type", ""), "service_rules": profile.duplicate(true)})
	facility["service_state"] = {}
	facility["interaction_state"] = "Idle"


func _interrupt_action(facility_id: String, facility: Dictionary, unit_id: String, reason_code: String, events: Array) -> void:
	facility["control_state"] = {}
	facility["service_state"] = {}
	facility["interaction_state"] = "Interrupted"
	facility["last_interruption_reason"] = reason_code
	events.append({"event_type": "FacilityActionInterrupted", "facility_id": facility_id, "unit_id": unit_id, "reason_code": reason_code})


func apply_damage(facility_id: String, damage: float, source_id: String = "") -> Array:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	if facility.is_empty() or str(facility.get("life_state", "")) != "Alive" or damage <= 0.0:
		return []
	var events: Array = []
	var definition := definition_for(facility_id)
	var disposition: Dictionary = definition.get("combat_disposition", {})
	var action := _facility_action(facility)
	if not action.is_empty(): _interrupt_action(facility_id, facility, str(action.get("unit_id", "")), "FACILITY_DAMAGED", events)
	var hp_before := float(facility.get("current_hp", 0.0))
	var destroyable := bool(disposition.get("destroyable", true))
	var damage_floor := 0.0 if destroyable else float(facility.get("max_hp", 1.0)) * clampf(float(disposition.get("damage_floor_ratio", 0.01)), 0.0, 1.0)
	var hp_after := maxf(damage_floor, hp_before - damage)
	var applied_damage := maxf(0.0, hp_before - hp_after)
	facility["current_hp"] = hp_after
	events.append({"event_type": "FacilityDamaged", "facility_id": facility_id, "source_id": source_id, "damage": applied_damage, "requested_damage": damage, "hp_before": hp_before, "hp_after": hp_after})
	if applied_damage + 0.001 < damage:
		events.append({"event_type": "FacilityDamageLimited", "facility_id": facility_id, "source_id": source_id, "damage_floor": damage_floor, "prevented_damage": damage - applied_damage})
	if destroyable and is_zero_approx(float(facility["current_hp"])):
		facility["life_state"] = "Destroyed"
		facility["operation_state"] = "Disabled"
		facility["control_state"] = {}
		facility["service_state"] = {}
		facility["interaction_state"] = "Interrupted"
		facility["suppression_remaining"] = 0.0
		events.append({"event_type": "FacilityDestroyed", "facility_id": facility_id, "source_id": source_id})
		return events
	if bool(disposition.get("suppressible", false)):
		var threshold := float(definition.get("suppression_damage_threshold", INF))
		facility["suppression_damage_accumulated"] = float(facility.get("suppression_damage_accumulated", 0.0)) + damage
		events.append({"event_type": "FacilitySuppressionAccumulated", "facility_id": facility_id, "source_id": source_id, "accumulated_damage": facility["suppression_damage_accumulated"], "threshold": threshold})
		if threshold > 0.0 and float(facility["suppression_damage_accumulated"]) >= threshold:
			var threshold_count := maxi(1, floori(float(facility["suppression_damage_accumulated"]) / threshold))
			facility["suppression_damage_accumulated"] = fmod(float(facility["suppression_damage_accumulated"]), threshold)
			events.append_array(suppress(facility_id, float(definition.get("suppression_duration", 0.0)) * mini(3, threshold_count), source_id))
	return events


func suppress(facility_id: String, duration: float, source_id: String = "") -> Array:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	if facility.is_empty() or str(facility.get("life_state", "")) != "Alive" or duration <= 0.0:
		return []
	var events: Array = []
	var action := _facility_action(facility)
	if not action.is_empty(): _interrupt_action(facility_id, facility, str(action.get("unit_id", "")), "FACILITY_SUPPRESSED", events)
	facility["operation_state"] = "Suppressed"
	facility["suppression_remaining"] = maxf(float(facility.get("suppression_remaining", 0.0)), duration)
	events.append({"event_type": "FacilitySuppressed", "facility_id": facility_id, "source_id": source_id, "duration": duration})
	return events


func _facility_action(facility: Dictionary) -> Dictionary:
	var control: Dictionary = facility.get("control_state", {})
	if not control.is_empty(): return {"unit_id": control.get("executor_unit_id", "")}
	var service: Dictionary = facility.get("service_state", {})
	if not service.is_empty(): return {"unit_id": service.get("unit_id", "")}
	return {}


func observation_sources(faction_id: String) -> Array:
	var result: Array = []
	for facility_id in _sorted_ids():
		if not is_operational(facility_id): continue
		var facility: Dictionary = facilities_by_id[facility_id]
		var definition := definition_for(facility_id)
		if facility.get("faction_id") != faction_id or "ObservationSource" not in definition.get("capabilities", []): continue
		var observation_position: Vector2 = facility.get("observation_position", facility["position"])
		var rules: Dictionary = definition.get("observation_rules", {})
		result.append({
			"facility_id": facility_id, "position": observation_position,
			"detection_range": float(definition.get("observation_range", 0.0)),
			"contact_type": str(rules.get("contact_type", "Optical")),
			"weather_affected": bool(rules.get("weather_affected", true)),
			"time_affected": bool(rules.get("time_affected", true)),
			"local_visibility_affected": bool(rules.get("local_visibility_affected", true)),
			"line_of_sight_required": bool(rules.get("line_of_sight_required", true)),
		})
	return result


func weapon_platforms() -> Array:
	var result: Array = []
	for facility_id in _sorted_ids():
		if not is_operational(facility_id): continue
		var facility: Dictionary = facilities_by_id[facility_id]
		if "WeaponPlatform" in definition_for(facility_id).get("capabilities", []): result.append(facility)
	return result


func mark_weapon_fired(facility_id: String, weapon_id: String, reload_time: float) -> void:
	for weapon_state in facilities_by_id.get(facility_id, {}).get("weapon_states", []):
		if str(weapon_state.get("definition_id", "")) == weapon_id:
			weapon_state["reload_remaining"] = reload_time


func target_for_damage(facility_id: String) -> Dictionary:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	var definition := definition_for(facility_id)
	if facility.is_empty(): return {}
	return {
		"entity_id": facility_id,
		"position": facility["position"],
		"current_hp": facility["current_hp"],
		"max_hp": facility["max_hp"],
		"status_effects": [],
		"stats": {
			"armor": float(definition.get("armor", 0.0)),
			"armor_thickness": str(definition.get("armor_thickness", "Unarmored")),
			"evasion": 0.0,
		},
	}


func combat_source(facility_id: String) -> Dictionary:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	var definition := definition_for(facility_id)
	if facility.is_empty(): return {}
	return {
		"entity_id": facility_id,
		"position": facility["position"],
		"status_effects": [],
		"stats": {
			"gunnery_power": float(definition.get("gunnery_power", 0.0)),
			"aviation_power": float(definition.get("aviation_power", 0.0)),
			"torpedo_power": 0.0,
			"anti_air_power": 0.0,
		},
	}


func is_operational(facility_id: String) -> bool:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	return not facility.is_empty() and str(facility.get("life_state", "")) == "Alive" and str(facility.get("operation_state", "")) == "Active" and _dependencies_active(facility)


func definition_for(facility_id: String) -> Dictionary:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	return definitions_by_id.get(str(facility.get("definition_id", "")), {})


func mission_definition(mission_id: String) -> Dictionary:
	return definitions_by_id.get(mission_id, {})


func snapshot() -> Dictionary:
	var result := facilities_by_id.duplicate(true)
	for facility_id in result:
		result[facility_id]["service_queue"] = []
		result[facility_id]["dependencies_active"] = _dependencies_active(facilities_by_id[facility_id])
	for mission in support_missions:
		var facility_id := str(mission.get("facility_id", ""))
		if result.has(facility_id): result[facility_id]["service_queue"].append(mission.duplicate(true))
	for deployment in mine_deployments:
		var facility_id := str(deployment.get("facility_id", ""))
		if result.has(facility_id): result[facility_id]["service_queue"].append(deployment.duplicate(true))
	return result


func sources_at(position: Vector2) -> Array:
	var result: Array = []
	for facility_id in _sorted_ids():
		var facility: Dictionary = facilities_by_id[facility_id]
		var polygon := _polygon(facility.get("interaction_water_polygon", []))
		if polygon.size() < 3 or not Geometry2D.is_point_in_polygon(position, polygon): continue
		result.append({"facility_id": facility_id, "effect_id": "facility.interaction_water", "intensity": 1.0, "operation_state": facility.get("operation_state", "Dormant"), "faction_id": facility.get("faction_id", "neutral")})
	return result


func interaction_center(facility_id: String) -> Vector2:
	var raw: Array = facilities_by_id.get(facility_id, {}).get("interaction_water_polygon", [])
	if raw.is_empty(): return Vector2.ZERO
	var center := Vector2.ZERO
	for point in raw: center += _vector2(point)
	return center / float(raw.size())


func _dependencies_active(facility: Dictionary) -> bool:
	var requires_matching_faction := bool(facility.get("dependency_rules", {}).get("requires_matching_faction", true))
	for dependency_id in facility.get("requires_all_active", []):
		var dependency: Dictionary = facilities_by_id.get(dependency_id, {})
		if str(dependency.get("life_state", "")) != "Alive" or str(dependency.get("operation_state", "")) != "Active" or requires_matching_faction and str(dependency.get("faction_id", "")) != str(facility.get("faction_id", "")): return false
	var any_dependencies: Array = facility.get("requires_any_active", [])
	if not any_dependencies.is_empty():
		for dependency_id in any_dependencies:
			var dependency: Dictionary = facilities_by_id.get(dependency_id, {})
			if str(dependency.get("life_state", "")) == "Alive" and str(dependency.get("operation_state", "")) == "Active" and (not requires_matching_faction or str(dependency.get("faction_id", "")) == str(facility.get("faction_id", ""))): return true
		return false
	return true


func _refresh_operation_state(facility_id: String) -> Dictionary:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	if facility.is_empty(): return {}
	var old_state := str(facility.get("operation_state", "Dormant"))
	var new_state := "Dormant"
	if str(facility.get("life_state", "")) != "Alive":
		new_state = "Disabled"
	elif float(facility.get("suppression_remaining", 0.0)) > 0.0:
		new_state = "Suppressed"
	else:
		var desired := str(facility.get("desired_operation_state", "Dormant"))
		if desired != "Active":
			new_state = desired
		elif _dependencies_active(facility):
			new_state = "Active"
		else:
			new_state = "Silent" if bool(definition_for(facility_id).get("combat_disposition", {}).get("silentable", false)) else "Disabled"
	facility["operation_state"] = new_state
	if old_state == new_state: return {}
	return {"event_type":"FacilityOperationStateChanged", "facility_id":facility_id, "old_operation_state":old_state, "operation_state":new_state, "dependencies_active":_dependencies_active(facility)}


func validate_runtime_state(facility_id: String) -> Array[String]:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	if facility.is_empty(): return ["FACILITY_NOT_FOUND"]
	var errors: Array[String] = []
	var operation := str(facility.get("operation_state", ""))
	if operation not in ["Dormant", "Active", "Suppressed", "Silent", "Disabled"]: errors.append("INVALID_OPERATION_STATE")
	if str(facility.get("life_state", "")) == "Destroyed" and operation != "Disabled": errors.append("DESTROYED_NOT_DISABLED")
	if operation == "Active" and not _dependencies_active(facility): errors.append("ACTIVE_WITH_INVALID_DEPENDENCY")
	if operation == "Suppressed" and float(facility.get("suppression_remaining", 0.0)) <= 0.0: errors.append("SUPPRESSED_WITHOUT_DURATION")
	if str(facility.get("interaction_state", "")) not in ["Idle", "Controlling", "Contested", "Moored", "Docked", "Servicing", "Interrupted"]: errors.append("INVALID_INTERACTION_STATE")
	var disposition: Dictionary = definition_for(facility_id).get("combat_disposition", {})
	if not bool(disposition.get("destroyable", true)):
		var floor_hp := float(facility.get("max_hp", 1.0)) * float(disposition.get("damage_floor_ratio", 0.0))
		if float(facility.get("current_hp", 0.0)) + 0.001 < floor_hp: errors.append("HP_BELOW_DAMAGE_FLOOR")
	return errors


func _sorted_ids() -> Array:
	var result: Array = facilities_by_id.keys()
	result.sort()
	return result


func _polygon(raw: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in raw: result.append(_vector2(point))
	return result


func _vector2(value: Variant) -> Vector2:
	return value if value is Vector2 else Vector2(float(value[0]), float(value[1]))
