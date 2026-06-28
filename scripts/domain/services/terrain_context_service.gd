extends RefCounted

var terrain_query
var global_environment: Dictionary = {}
var zones: Array = []
var effects_by_id: Dictionary = {}
var definitions_by_id: Dictionary = {}
var global_elapsed := 0.0
var tide_phase_index := 0
var tide_initial_phase_index := 0


func configure(query, zone_set: Dictionary, effects: Array, ocean_palette_id: String = "") -> void:
	terrain_query = query
	effects_by_id.clear()
	definitions_by_id.clear()
	for effect in effects:
		var definition_id := str(effect.get("id", ""))
		definitions_by_id[definition_id] = effect.duplicate(true)
		if str(effect.get("definition_type", "")) == "EnvironmentEffect":
			effects_by_id[definition_id] = effect.duplicate(true)
	global_environment = _compose_global_environment(zone_set.get("global_environment", {}), ocean_palette_id)
	global_elapsed = 0.0
	var tide: Dictionary = global_environment.get("tide", {})
	var phases: Array = tide.get("phases", [])
	tide_initial_phase_index = maxi(0, phases.find(str(tide.get("initial_phase", phases[0] if not phases.is_empty() else "Stable"))))
	tide_phase_index = tide_initial_phase_index
	zones.clear()
	for raw_zone in zone_set.get("zones", []):
		var zone: Dictionary = raw_zone.duplicate(true)
		zone["position"] = _vector2(zone.get("position", [0.0, 0.0]))
		zone["initial_position"] = zone["position"]
		zone["path_distance"] = 0.0
		zone["remaining_time"] = float(zone.get("duration", 0.0))
		zone["active"] = bool(zone.get("active", true))
		zone["base_polygon"] = zone.get("polygon", []).duplicate(true)
		zones.append(zone)
	zones.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))


func advance(delta: float) -> Array:
	var events: Array = []
	global_elapsed += delta
	var tide: Dictionary = global_environment.get("tide", {})
	var phases: Array = tide.get("phases", [])
	var phase_duration := float(tide.get("phase_duration", 0.0))
	if not phases.is_empty() and phase_duration > 0.0:
		var next_phase_index := (tide_initial_phase_index + int(floor(global_elapsed / phase_duration))) % phases.size()
		if next_phase_index != tide_phase_index:
			tide_phase_index = next_phase_index
			events.append({"event_type": "EnvironmentForecastChanged", "tide_phase": phases[tide_phase_index], "forecast_revision": int(floor(global_elapsed / phase_duration))})
	for zone in zones:
		if not bool(zone.get("active", false)):
			continue
		var speed := float(zone.get("drift_speed", 0.0))
		if speed > 0.0:
			var drift_path: Array = zone.get("drift_path", [])
			if drift_path.size() >= 2:
				zone["path_distance"] = float(zone.get("path_distance", 0.0)) + speed * delta
				zone["position"] = (zone["initial_position"] as Vector2) + _sample_path(drift_path, float(zone["path_distance"]))
			else:
				zone["position"] = (zone["position"] as Vector2) + Vector2.RIGHT.rotated(deg_to_rad(float(zone.get("heading", 0.0)))) * speed * delta
		var remaining := float(zone.get("remaining_time", 0.0))
		if remaining > 0.0:
			zone["remaining_time"] = maxf(0.0, remaining - delta)
			if float(zone["remaining_time"]) <= 0.0:
				zone["active"] = false
				zone["phase"] = "Dissipated"
				events.append({"event_type": "EnvironmentZoneChanged", "zone_id": zone.get("id", ""), "phase": "Dissipated", "active": false})
	return events


func context_at(position: Vector2) -> Dictionary:
	var context := {
		"water_regions": terrain_query.regions_at(position) if terrain_query != null else [],
		"current_vector": Vector2.ZERO,
		"sea_state": int(global_environment.get("base_sea_state", 0)),
		"optical_visibility_multiplier": float(global_environment.get("optical_visibility_multiplier", 1.0)),
		"aviation_condition": str(global_environment.get("aviation_condition", "Normal")),
		"aviation_delay_multiplier": float(global_environment.get("aviation_delay_multiplier", 1.0)),
		"weapon_accuracy_modifier": float(global_environment.get("weapon_accuracy_modifier", 0.0)),
		"movement_speed_multiplier": float(global_environment.get("movement_speed_multiplier", 1.0)),
		"tide_controls_access": false,
		"tide_phase": _tide_phase(),
		"tide_access_state": "Open",
		"effect_sources": global_environment.get("condition_sources", []).duplicate(true),
	}
	var selected_by_effect := {}
	var vector_zones: Array = []
	for zone in zones:
		if not bool(zone.get("active", false)) or not _zone_contains(zone, position):
			continue
		var effect: Dictionary = effects_by_id.get(str(zone.get("effect_id", "")), {})
		var effect_id := str(effect.get("id", ""))
		if effect_id.is_empty():
			continue
		var rule := str(effect.get("stack_rule", "Highest"))
		if rule == "VectorAdd":
			vector_zones.append({"zone": zone, "effect": effect})
			continue
		var previous: Dictionary = selected_by_effect.get(effect_id, {})
		if previous.is_empty() or float(zone.get("intensity", 1.0)) > float(previous["zone"].get("intensity", 1.0)):
			selected_by_effect[effect_id] = {"zone": zone, "effect": effect}
	var applications: Array = selected_by_effect.values()
	applications.append_array(vector_zones)
	applications.sort_custom(func(a, b):
		var priority_a := int(a["effect"].get("priority", 0))
		var priority_b := int(b["effect"].get("priority", 0))
		return priority_a < priority_b if priority_a != priority_b else str(a["zone"].get("id", "")) < str(b["zone"].get("id", "")))
	for application in applications:
		var zone: Dictionary = application["zone"]
		var effect: Dictionary = application["effect"]
		var effect_id := str(effect.get("id", ""))
		var intensity := float(zone.get("intensity", 1.0))
		var values: Dictionary = effect.get("context", {})
		if values.has("optical_visibility_multiplier"):
			var optical_value := lerpf(1.0, float(values["optical_visibility_multiplier"]), intensity)
			context["optical_visibility_multiplier"] = clampf(
				float(context["optical_visibility_multiplier"]) * optical_value,
				float(global_environment.get("minimum_optical_visibility_multiplier", 0.45)),
				1.25,
			)
		if values.has("sea_state"):
			var base_sea_state := float(global_environment.get("base_sea_state", 0))
			context["sea_state"] = maxi(int(context["sea_state"]), roundi(lerpf(base_sea_state, float(values["sea_state"]), intensity)))
		if values.has("sea_state_delta"):
			context["sea_state"] = maxi(0, int(context["sea_state"]) + roundi(float(values["sea_state_delta"]) * intensity))
		if values.has("current_strength"):
			context["current_vector"] = (context["current_vector"] as Vector2) + Vector2.RIGHT.rotated(deg_to_rad(float(zone.get("heading", 0.0)))) * float(values["current_strength"]) * intensity
		if values.has("aviation_condition"):
			context["aviation_condition"] = _more_severe_aviation_condition(str(context["aviation_condition"]), str(values["aviation_condition"]))
		if values.has("aviation_delay_multiplier"):
			context["aviation_delay_multiplier"] = float(context["aviation_delay_multiplier"]) * lerpf(1.0, float(values["aviation_delay_multiplier"]), intensity)
		if values.has("weapon_accuracy_modifier"):
			context["weapon_accuracy_modifier"] = float(context["weapon_accuracy_modifier"]) + float(values["weapon_accuracy_modifier"]) * intensity
		if values.has("movement_speed_multiplier"):
			context["movement_speed_multiplier"] = float(context["movement_speed_multiplier"]) * lerpf(1.0, float(values["movement_speed_multiplier"]), intensity)
		if values.has("tide_controls_access"):
			context["tide_controls_access"] = bool(values["tide_controls_access"])
		context["effect_sources"].append({"zone_id": zone.get("id", ""), "effect_id": effect_id, "intensity": intensity})
	_apply_sea_state_rule(context)
	if bool(context["tide_controls_access"]):
		var tide: Dictionary = global_environment.get("tide", {})
		context["tide_access_state"] = "Open" if str(context["tide_phase"]) in tide.get("open_phases", ["Flood", "High"]) else "Restricted"
	return context


func movement_segment_access(start: Vector2, end: Vector2) -> Dictionary:
	var allowed_start_zones := _restricted_tide_zone_ids_at(start)
	var distance := start.distance_to(end)
	var steps := maxi(1, ceili(distance / 4.0))
	for index in range(1, steps + 1):
		var fraction := float(index) / float(steps)
		var current_zones := _restricted_tide_zone_ids_at(start.lerp(end, fraction))
		for zone_id in allowed_start_zones.duplicate():
			if zone_id not in current_zones: allowed_start_zones.erase(zone_id)
		for zone_id in current_zones:
			if zone_id not in allowed_start_zones:
				return {"allowed": false, "reason_code": "TIDE_ACCESS_RESTRICTED", "zone_id": zone_id, "fraction": fraction}
	return {"allowed": true, "reason_code": "OK", "fraction": 1.0}


func zone_center_for_effect(effect_id: String) -> Vector2:
	for zone in zones:
		if bool(zone.get("active", false)) and str(zone.get("effect_id", "")) == effect_id:
			var polygon := _world_polygon(zone)
			if polygon.is_empty(): return Vector2.ZERO
			var center := Vector2.ZERO
			for point in polygon: center += point
			return center / float(polygon.size())
	return Vector2.ZERO


func global_snapshot() -> Dictionary:
	var result := global_environment.duplicate(true)
	result["tide_phase"] = _tide_phase()
	result["elapsed"] = global_elapsed
	return result


func snapshot() -> Array:
	var result: Array = []
	for zone in zones:
		var copy: Dictionary = zone.duplicate(true)
		copy["polygon"] = _world_polygon(zone)
		copy.erase("base_polygon")
		copy.erase("initial_position")
		copy.erase("path_distance")
		result.append(copy)
	return result


func _zone_contains(zone: Dictionary, position: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(position, _world_polygon(zone))


func _world_polygon(zone: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	var offset: Vector2 = zone.get("position", Vector2.ZERO)
	for point in zone.get("base_polygon", []):
		result.append(_vector2(point) + offset)
	return result


func _sample_path(raw_path: Array, distance: float) -> Vector2:
	var remaining := maxf(0.0, distance)
	var previous := _vector2(raw_path[0])
	for index in range(1, raw_path.size()):
		var current := _vector2(raw_path[index])
		var segment_length := previous.distance_to(current)
		if segment_length > 0.0 and remaining <= segment_length:
			return previous.lerp(current, remaining / segment_length)
		remaining -= segment_length
		previous = current
	return previous


func _restricted_tide_zone_ids_at(position: Vector2) -> Array:
	var result: Array = []
	for zone in zones:
		if not bool(zone.get("active", false)) or not _zone_contains(zone, position): continue
		var effect: Dictionary = effects_by_id.get(str(zone.get("effect_id", "")), {})
		if not bool(effect.get("context", {}).get("tide_controls_access", false)): continue
		var tide: Dictionary = global_environment.get("tide", {})
		if _tide_phase() not in tide.get("open_phases", ["Flood", "High"]): result.append(str(zone.get("id", "")))
	result.sort()
	return result


func _tide_phase() -> String:
	var tide: Dictionary = global_environment.get("tide", {})
	var phases: Array = tide.get("phases", [])
	return str(phases[tide_phase_index]) if not phases.is_empty() else str(tide.get("initial_phase", "Stable"))


func _apply_sea_state_rule(context: Dictionary) -> void:
	var selected: Dictionary = {}
	for rule in global_environment.get("sea_state_rules", []):
		if int(context["sea_state"]) < int(rule.get("minimum_sea_state", 0)): continue
		if selected.is_empty() or int(rule.get("minimum_sea_state", 0)) > int(selected.get("minimum_sea_state", 0)):
			selected = rule
	if selected.is_empty(): return
	context["movement_speed_multiplier"] = float(context["movement_speed_multiplier"]) * float(selected.get("movement_speed_multiplier", 1.0))
	context["weapon_accuracy_modifier"] = float(context["weapon_accuracy_modifier"]) + float(selected.get("weapon_accuracy_modifier", 0.0))
	context["aviation_delay_multiplier"] = float(context["aviation_delay_multiplier"]) * float(selected.get("aviation_delay_multiplier", 1.0))
	if selected.has("aviation_condition"):
		context["aviation_condition"] = _more_severe_aviation_condition(str(context["aviation_condition"]), str(selected["aviation_condition"]))


func _compose_global_environment(authored_environment: Dictionary, ocean_palette_id: String) -> Dictionary:
	var result: Dictionary = authored_environment.duplicate(true)
	if ocean_palette_id.is_empty():
		return result
	var aliases: Dictionary = definitions_by_id.get("environment.condition_aliases.ocean", {}).get("aliases", {})
	var canonical_palette_id := str(aliases.get(ocean_palette_id, ocean_palette_id))
	var parts := canonical_palette_id.split("_")
	if parts.size() != 2:
		return result
	var weather_id := "environment.weather.%s" % parts[0]
	var time_id := "environment.time.%s" % parts[1]
	var weather_profile: Dictionary = definitions_by_id.get(weather_id, {})
	var time_profile: Dictionary = definitions_by_id.get(time_id, {})
	if weather_profile.is_empty() or time_profile.is_empty():
		return result
	var weather_context: Dictionary = weather_profile.get("context", {})
	var time_context: Dictionary = time_profile.get("context", {})
	var condition_rules: Dictionary = definitions_by_id.get("environment.condition_rules.ocean", {})
	result["ocean_palette"] = ocean_palette_id
	result["canonical_ocean_palette"] = canonical_palette_id
	result["weather"] = str(weather_profile.get("weather", parts[0]))
	result["time_of_day"] = str(time_profile.get("time_of_day", parts[1]))
	result["base_sea_state"] = int(weather_context.get("base_sea_state", result.get("base_sea_state", 0)))
	result["optical_visibility_multiplier"] = clampf(
		float(weather_context.get("optical_visibility_multiplier", 1.0)) * float(time_context.get("optical_visibility_multiplier", 1.0)),
		float(condition_rules.get("minimum_optical_visibility_multiplier", 0.45)),
		1.25,
	)
	result["minimum_optical_visibility_multiplier"] = float(condition_rules.get("minimum_optical_visibility_multiplier", 0.45))
	result["weapon_accuracy_modifier"] = float(weather_context.get("weapon_accuracy_modifier", 0.0)) + float(time_context.get("weapon_accuracy_modifier", 0.0))
	result["aviation_delay_multiplier"] = float(weather_context.get("aviation_delay_multiplier", 1.0)) * float(time_context.get("aviation_delay_multiplier", 1.0))
	result["aviation_condition"] = _more_severe_aviation_condition(str(weather_context.get("aviation_condition", "Normal")), str(time_context.get("aviation_condition", "Normal")))
	result["movement_speed_multiplier"] = float(weather_context.get("movement_speed_multiplier", 1.0)) * float(time_context.get("movement_speed_multiplier", 1.0))
	if result.get("sea_state_rules", []).is_empty():
		result["sea_state_rules"] = condition_rules.get("sea_state_rules", []).duplicate(true)
	result["condition_sources"] = [
		{"scope": "GlobalWeather", "effect_id": weather_id, "intensity": 1.0},
		{"scope": "GlobalTime", "effect_id": time_id, "intensity": 1.0},
	]
	return result


func _more_severe_aviation_condition(first: String, second: String) -> String:
	var rank := {"Normal": 0, "Restricted": 1, "Severe": 2, "Grounded": 3}
	return second if int(rank.get(second, 0)) > int(rank.get(first, 0)) else first


func _vector2(value: Variant) -> Vector2:
	return value if value is Vector2 else Vector2(float(value[0]), float(value[1]))
