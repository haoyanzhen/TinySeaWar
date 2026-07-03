extends RefCounted

var facilities_by_id: Dictionary = {}
var support_missions: Array = []
var definitions_by_id: Dictionary = {}
var mission_sequence := 0


func configure(layout: Dictionary, anchors: Array, definitions: Array) -> void:
	facilities_by_id.clear()
	support_missions.clear()
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
			"previous_operation_state": operation_state,
			"current_hp": float(definition.get("max_hp", 1.0)),
			"max_hp": float(definition.get("max_hp", 1.0)),
			"interaction": {},
			"suppression_remaining": 0.0,
			"cooldown_remaining": 0.0,
			"charges_remaining": int(definition.get("charges", 0)),
			"mission_charges_remaining": mission_charges,
			"weapon_states": weapon_states,
			"requires_all_active": placement.get("requires_all_active", []).duplicate(),
			"requires_any_active": placement.get("requires_any_active", []).duplicate(),
		}


func start_interaction(facility_id: String, unit: Dictionary, interaction_type: String) -> Dictionary:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	if facility.is_empty() or str(facility.get("life_state", "")) != "Alive":
		return {"accepted": false, "reason_code": "FACILITY_INTERACTION_NOT_ALLOWED"}
	var definition: Dictionary = definition_for(facility_id)
	if interaction_type not in definition.get("interaction_types", []) or not facility.get("interaction", {}).is_empty():
		return {"accepted": false, "reason_code": "FACILITY_INTERACTION_NOT_ALLOWED"}
	if facility["operation_state"] == "Suppressed":
		return {"accepted": false, "reason_code": "FACILITY_SUPPRESSED"}
	if str(unit.get("life_state", "")) != "Alive" or not Geometry2D.is_point_in_polygon(unit["position"], _polygon(facility.get("interaction_water_polygon", []))):
		return {"accepted": false, "reason_code": "FACILITY_OUT_OF_RANGE"}
	var unit_faction := str(unit.get("faction_id", ""))
	match interaction_type:
		"Activate":
			if str(facility.get("operation_state", "")) != "Dormant" or str(facility.get("faction_id", "neutral")) not in ["neutral", unit_faction]:
				return {"accepted": false, "reason_code": "FACILITY_INTERACTION_NOT_ALLOWED"}
		"Seize":
			if "Ownable" not in definition.get("capabilities", []) or not bool(definition.get("seizable", true)) or str(facility.get("faction_id", "neutral")) == unit_faction:
				return {"accepted": false, "reason_code": "FACILITY_INTERACTION_NOT_ALLOWED"}
		"Service":
			if "ServiceProvider" not in definition.get("capabilities", []) or str(facility.get("operation_state", "")) != "Active" or str(facility.get("faction_id", "")) != unit_faction or not _dependencies_active(facility):
				return {"accepted": false, "reason_code": "FACILITY_NOT_ACTIVE"}
	facility["operation_state"] = "Activating" if interaction_type in ["Activate", "Seize"] else facility["operation_state"]
	facility["interaction"] = {
		"unit_id": str(unit["entity_id"]),
		"interaction_type": interaction_type,
		"progress": 0.0,
		"duration": float(definition.get("interaction_duration", 5.0)),
		"faction_id": unit_faction,
		"service_type": str(definition.get("service_profile", {}).get("service_type", "")),
	}
	return {"accepted": true, "event": {"event_type": "FacilityInteractionStarted", "facility_id": facility_id, "unit_id": unit["entity_id"], "interaction_type": interaction_type}}


func cancel_interaction(facility_id: String, unit_id: String) -> Dictionary:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	if facility.is_empty() or str(facility.get("interaction", {}).get("unit_id", "")) != unit_id:
		return {"accepted": false, "reason_code": "FACILITY_INTERACTION_NOT_ALLOWED"}
	var interaction_type := str(facility.get("interaction", {}).get("interaction_type", ""))
	if interaction_type in ["Activate", "Seize"]:
		facility["operation_state"] = str(facility.get("previous_operation_state", "Dormant"))
	facility["interaction"] = {}
	return {"accepted": true, "event": {"event_type": "FacilityInteractionInterrupted", "facility_id": facility_id, "unit_id": unit_id}}


func active_interaction_for_unit(unit_id: String) -> Dictionary:
	for facility_id in _sorted_ids():
		var interaction: Dictionary = facilities_by_id[facility_id].get("interaction", {})
		if str(interaction.get("unit_id", "")) == unit_id:
			var result := interaction.duplicate(true)
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
		if suppression_before > 0.0 and is_zero_approx(float(facility["suppression_remaining"])) and str(facility.get("life_state", "")) == "Alive":
			facility["operation_state"] = str(facility.get("previous_operation_state", "Dormant"))
			events.append({"event_type": "FacilityRecovered", "facility_id": facility_id, "operation_state": facility["operation_state"]})
		var interaction: Dictionary = facility.get("interaction", {})
		if interaction.is_empty():
			continue
		var unit: Dictionary = units_by_id.get(str(interaction.get("unit_id", "")), {})
		if unit.is_empty() or unit.get("life_state") != "Alive" or str(facility.get("life_state", "")) != "Alive" or str(facility.get("operation_state", "")) == "Suppressed" or not Geometry2D.is_point_in_polygon(unit["position"], _polygon(facility.get("interaction_water_polygon", []))):
			var reason_code := "UNIT_UNAVAILABLE" if unit.is_empty() or unit.get("life_state") != "Alive" else ("FACILITY_UNAVAILABLE" if str(facility.get("life_state", "")) != "Alive" or str(facility.get("operation_state", "")) == "Suppressed" else "UNIT_LEFT_INTERACTION_AREA")
			if str(interaction.get("interaction_type", "")) in ["Activate", "Seize"] and str(facility.get("operation_state", "")) == "Activating":
				facility["operation_state"] = str(facility.get("previous_operation_state", "Dormant"))
			facility["interaction"] = {}
			events.append({"event_type": "FacilityInteractionInterrupted", "facility_id": facility_id, "unit_id": interaction.get("unit_id", ""), "reason_code": reason_code})
			continue
		interaction["progress"] = float(interaction.get("progress", 0.0)) + delta
		if float(interaction["progress"]) + 0.001 < float(interaction.get("duration", 1.0)):
			continue
		var interaction_type := str(interaction.get("interaction_type", "Activate"))
		if interaction_type in ["Activate", "Seize"]:
			var old_faction := str(facility.get("faction_id", "neutral"))
			facility["faction_id"] = str(interaction.get("faction_id", old_faction))
			facility["operation_state"] = "Active"
			facility["previous_operation_state"] = "Active"
			if old_faction != str(facility["faction_id"]):
				events.append({"event_type": "FacilityOwnershipChanged", "facility_id": facility_id, "old_faction_id": old_faction, "faction_id": facility["faction_id"]})
			events.append({"event_type": "FacilitySeized" if interaction_type == "Seize" else "FacilityActivated", "facility_id": facility_id, "faction_id": facility["faction_id"]})
		else:
			events.append({
				"event_type": "FacilityServiceCompleted",
				"facility_id": facility_id,
				"unit_id": unit["entity_id"],
				"service_type": interaction.get("service_type", ""),
				"service_profile": definition_for(facility_id).get("service_profile", {}).duplicate(true),
			})
		facility["interaction"] = {}
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
	return events


func apply_damage(facility_id: String, damage: float, source_id: String = "") -> Array:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	if facility.is_empty() or str(facility.get("life_state", "")) != "Alive" or damage <= 0.0:
		return []
	var events: Array = []
	if not facility.get("interaction", {}).is_empty():
		var interrupted_type := str(facility.get("interaction", {}).get("interaction_type", ""))
		events.append({"event_type":"FacilityInteractionInterrupted", "facility_id":facility_id, "unit_id":facility.get("interaction", {}).get("unit_id", ""), "reason_code":"FACILITY_DAMAGED"})
		facility["interaction"] = {}
		if interrupted_type in ["Activate", "Seize"] and str(facility.get("operation_state", "")) == "Activating": facility["operation_state"] = str(facility.get("previous_operation_state", "Dormant"))
	var hp_before := float(facility.get("current_hp", 0.0))
	facility["current_hp"] = maxf(0.0, hp_before - damage)
	events.append({"event_type": "FacilityDamaged", "facility_id": facility_id, "source_id": source_id, "damage": damage, "hp_before": hp_before, "hp_after": facility["current_hp"]})
	if is_zero_approx(float(facility["current_hp"])):
		facility["life_state"] = "Destroyed"
		facility["operation_state"] = "Destroyed"
		facility["interaction"] = {}
		facility["suppression_remaining"] = 0.0
		events.append({"event_type": "FacilityDestroyed", "facility_id": facility_id, "source_id": source_id})
		return events
	var definition := definition_for(facility_id)
	if "Suppressible" in definition.get("capabilities", []) and damage >= float(definition.get("suppression_damage_threshold", INF)):
		events.append_array(suppress(facility_id, float(definition.get("suppression_duration", 0.0)), source_id))
	return events


func suppress(facility_id: String, duration: float, source_id: String = "") -> Array:
	var facility: Dictionary = facilities_by_id.get(facility_id, {})
	if facility.is_empty() or str(facility.get("life_state", "")) != "Alive" or duration <= 0.0:
		return []
	var events: Array = []
	if not facility.get("interaction", {}).is_empty():
		events.append({"event_type":"FacilityInteractionInterrupted", "facility_id":facility_id, "unit_id":facility.get("interaction", {}).get("unit_id", ""), "reason_code":"FACILITY_SUPPRESSED"})
	if str(facility.get("operation_state", "")) != "Suppressed":
		var previous_state := str(facility.get("operation_state", "Dormant"))
		facility["previous_operation_state"] = "Dormant" if previous_state == "Activating" else previous_state
	facility["operation_state"] = "Suppressed"
	facility["suppression_remaining"] = maxf(float(facility.get("suppression_remaining", 0.0)), duration)
	facility["interaction"] = {}
	events.append({"event_type": "FacilitySuppressed", "facility_id": facility_id, "source_id": source_id, "duration": duration})
	return events


func observation_sources(faction_id: String) -> Array:
	var result: Array = []
	for facility_id in _sorted_ids():
		if not is_operational(facility_id): continue
		var facility: Dictionary = facilities_by_id[facility_id]
		var definition := definition_for(facility_id)
		if facility.get("faction_id") != faction_id or "ObservationSource" not in definition.get("capabilities", []): continue
		var observation_position: Vector2 = facility.get("observation_position", facility["position"])
		result.append({"facility_id": facility_id, "position": observation_position, "detection_range": float(definition.get("observation_range", 0.0))})
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
	for dependency_id in facility.get("requires_all_active", []):
		var dependency: Dictionary = facilities_by_id.get(dependency_id, {})
		if str(dependency.get("life_state", "")) != "Alive" or str(dependency.get("operation_state", "")) != "Active": return false
	var any_dependencies: Array = facility.get("requires_any_active", [])
	if not any_dependencies.is_empty():
		for dependency_id in any_dependencies:
			var dependency: Dictionary = facilities_by_id.get(dependency_id, {})
			if str(dependency.get("life_state", "")) == "Alive" and str(dependency.get("operation_state", "")) == "Active": return true
		return false
	return true


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
