extends RefCounted

var terrain_query
var global_environment: Dictionary = {}
var zones: Array = []
var motion_zone_indices: PackedInt32Array = PackedInt32Array()
var tide_zone_indices: PackedInt32Array = PackedInt32Array()
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
		zone["base_polygon_packed"] = _packed_polygon(zone["base_polygon"])
		zone["local_bounds"] = _polygon_bounds(zone["base_polygon_packed"])
		zones.append(zone)
	zones.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	var motion_indices: Array[int] = []
	tide_zone_indices.clear()
	var motion_effect_counts := {}
	for zone_index in range(zones.size()):
		var effect: Dictionary = effects_by_id.get(str(zones[zone_index].get("effect_id", "")), {})
		var values: Dictionary = effect.get("context", {})
		if values.has("current_strength") or values.has("movement_speed_multiplier") or values.has("sea_state") or values.has("sea_state_delta"):
			zones[zone_index]["motion_effect_id"] = str(effect.get("id", ""))
			zones[zone_index]["motion_priority"] = int(effect.get("priority", 0))
			zones[zone_index]["motion_stack_rule"] = str(effect.get("stack_rule", "Highest"))
			zones[zone_index]["motion_values"] = values
			zones[zone_index]["motion_current_vector"] = Vector2.RIGHT.rotated(deg_to_rad(float(zones[zone_index].get("heading", 0.0)))) * float(values.get("current_strength", 0.0)) * float(zones[zone_index].get("intensity", 1.0))
			motion_indices.append(zone_index)
			var effect_id := str(effect.get("id", ""))
			if str(effect.get("stack_rule", "Highest")) != "VectorAdd":
				motion_effect_counts[effect_id] = int(motion_effect_counts.get(effect_id, 0)) + 1
		if bool(values.get("tide_controls_access", false)):
			tide_zone_indices.append(zone_index)
	motion_indices.sort_custom(func(a, b):
		var priority_a := int(zones[a].get("motion_priority", 0))
		var priority_b := int(zones[b].get("motion_priority", 0))
		return priority_a < priority_b if priority_a != priority_b else str(zones[a].get("id", "")) < str(zones[b].get("id", "")))
	motion_zone_indices = PackedInt32Array(motion_indices)
	for zone_index in motion_zone_indices:
		var effect_id := str(zones[int(zone_index)].get("motion_effect_id", ""))
		zones[int(zone_index)]["motion_requires_selection"] = int(motion_effect_counts.get(effect_id, 0)) > 1


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
		"wind_speed": float(global_environment.get("wind_speed", 0.0)),
		"wind_heading": float(global_environment.get("wind_heading", 0.0)),
		"torpedo_sigma_multiplier": 1.0,
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
		if values.has("wind_speed"):
			context["wind_speed"] = maxf(float(context["wind_speed"]), lerpf(float(context["wind_speed"]), float(values["wind_speed"]), intensity))
		if values.has("wind_speed_add"):
			context["wind_speed"] = maxf(0.0, float(context["wind_speed"]) + float(values["wind_speed_add"]) * intensity)
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
	_apply_torpedo_sigma_multiplier(context)
	if bool(context["tide_controls_access"]):
		var tide: Dictionary = global_environment.get("tide", {})
		context["tide_access_state"] = "Open" if str(context["tide_phase"]) in tide.get("open_phases", ["Flood", "High"]) else "Restricted"
	return context


func motion_context_at(position: Vector2) -> Dictionary:
	# Trajectory prediction needs only the movement inputs. Avoid constructing
	# optical/aviation/source payloads and querying visual water-region facts for
	# every fixed-tick candidate sample.
	var context := {
		"current_vector":Vector2.ZERO,
		"movement_speed_multiplier":float(global_environment.get("movement_speed_multiplier", 1.0)),
		"sea_state":int(global_environment.get("base_sea_state", 0)),
	}
	var selected_by_effect := {}
	var matched_indices: Array[int] = []
	for zone_index in motion_zone_indices:
		var zone: Dictionary = zones[int(zone_index)]
		if not bool(zone.get("active", false)) or not _zone_contains(zone, position): continue
		matched_indices.append(int(zone_index))
		if bool(zone.get("motion_requires_selection", false)):
			var effect_id := str(zone.get("motion_effect_id", ""))
			var previous_index := int(selected_by_effect.get(effect_id, -1))
			if previous_index < 0 or float(zone.get("intensity", 1.0)) > float(zones[previous_index].get("intensity", 1.0)):
				selected_by_effect[effect_id] = int(zone_index)
	for zone_index in matched_indices:
		var zone: Dictionary = zones[zone_index]
		if bool(zone.get("motion_requires_selection", false)) and int(selected_by_effect.get(str(zone.get("motion_effect_id", "")), -1)) != zone_index:
			continue
		var values: Dictionary = zone.get("motion_values", {})
		var intensity := float(zone.get("intensity", 1.0))
		if values.has("current_strength"):
			context["current_vector"] = (context["current_vector"] as Vector2) + (zone.get("motion_current_vector", Vector2.ZERO) as Vector2)
		if values.has("movement_speed_multiplier"):
			context["movement_speed_multiplier"] = float(context["movement_speed_multiplier"]) * lerpf(1.0, float(values["movement_speed_multiplier"]), intensity)
		if values.has("sea_state"):
			context["sea_state"] = maxi(int(context["sea_state"]), roundi(lerpf(float(global_environment.get("base_sea_state", 0)), float(values["sea_state"]), intensity)))
		if values.has("sea_state_delta"):
			context["sea_state"] = maxi(0, int(context["sea_state"]) + roundi(float(values["sea_state_delta"]) * intensity))
	var selected_sea_rule: Dictionary = {}
	for rule in global_environment.get("sea_state_rules", []):
		if int(context["sea_state"]) < int(rule.get("minimum_sea_state", 0)): continue
		if selected_sea_rule.is_empty() or int(rule.get("minimum_sea_state", 0)) > int(selected_sea_rule.get("minimum_sea_state", 0)):
			selected_sea_rule = rule
	if not selected_sea_rule.is_empty():
		context["movement_speed_multiplier"] = float(context["movement_speed_multiplier"]) * float(selected_sea_rule.get("movement_speed_multiplier", 1.0))
	return context


func motion_context_varies_spatially() -> bool:
	# The initial motion state already contains the current global movement
	# context. Only active local movement zones require resampling along every
	# predicted fixed-Tick position.
	for zone_index in motion_zone_indices:
		if bool(zones[int(zone_index)].get("active", false)):
			return true
	return false


func prediction_motion_context_varies(position: Vector2, base_maximum_speed: float, horizon: float, initial_speed: float = 0.0) -> bool:
	if horizon <= 0.0:
		return false
	var maximum_speed_multiplier := maxf(0.0, float(global_environment.get("movement_speed_multiplier", 1.0)))
	var maximum_current_speed := 0.0
	for zone_index in motion_zone_indices:
		var zone: Dictionary = zones[int(zone_index)]
		if not bool(zone.get("active", false)): continue
		var values: Dictionary = zone.get("motion_values", {})
		if values.has("movement_speed_multiplier"):
			maximum_speed_multiplier *= maxf(1.0, lerpf(1.0, float(values["movement_speed_multiplier"]), float(zone.get("intensity", 1.0))))
		maximum_current_speed += (zone.get("motion_current_vector", Vector2.ZERO) as Vector2).length()
	var maximum_sea_multiplier := 1.0
	for rule in global_environment.get("sea_state_rules", []):
		maximum_sea_multiplier = maxf(maximum_sea_multiplier, float(rule.get("movement_speed_multiplier", 1.0)))
	# Include existing momentum: a unit can enter prediction above its current
	# context's speed cap and only decelerate toward the requested speed.
	var reachable_speed := maxf(maxf(0.0, base_maximum_speed) * maximum_speed_multiplier * maximum_sea_multiplier, maxf(0.0, initial_speed))
	var reachable_radius := (reachable_speed + maximum_current_speed) * horizon
	for zone_index in motion_zone_indices:
		var zone: Dictionary = zones[int(zone_index)]
		if not bool(zone.get("active", false)): continue
		if _distance_to_zone_boundary(zone, position) <= reachable_radius + 0.001:
			return true
	return false


func _distance_to_zone_boundary(zone: Dictionary, position: Vector2) -> float:
	var local_position := position - (zone.get("position", Vector2.ZERO) as Vector2)
	var polygon: PackedVector2Array = zone.get("base_polygon_packed", PackedVector2Array())
	if polygon.size() < 2: return INF
	var result := INF
	for index in range(polygon.size()):
		var closest := Geometry2D.get_closest_point_to_segment(local_position, polygon[index], polygon[(index + 1) % polygon.size()])
		result = minf(result, local_position.distance_to(closest))
	return result


func movement_segment_access(start: Vector2, end: Vector2) -> Dictionary:
	if not _tide_access_restricted():
		return {"allowed": true, "reason_code": "OK", "fraction": 1.0}
	for zone_index in tide_zone_indices:
		var zone: Dictionary = zones[int(zone_index)]
		if not _is_restricted_tide_zone(zone): continue
		var polygon: PackedVector2Array = zone.get("base_polygon_packed", PackedVector2Array())
		var offset: Vector2 = zone.get("position", Vector2.ZERO)
		var local_start := start - offset
		var local_end := end - offset
		var starts_inside := Geometry2D.is_point_in_polygon(local_start, polygon)
		var ends_inside := Geometry2D.is_point_in_polygon(local_end, polygon)
		if not starts_inside and ends_inside:
			return {"allowed": false, "reason_code": "TIDE_ACCESS_RESTRICTED", "zone_id": zone.get("id", ""), "fraction": _first_polygon_intersection_fraction(local_start, local_end, polygon)}
		if starts_inside: continue
		var entry_fraction := _first_polygon_intersection_fraction(local_start, local_end, polygon)
		if entry_fraction >= 0.0:
			return {"allowed": false, "reason_code": "TIDE_ACCESS_RESTRICTED", "zone_id": zone.get("id", ""), "fraction": entry_fraction}
	return {"allowed": true, "reason_code": "OK", "fraction": 1.0}


func movement_trajectory_access(samples: Array, sample_limit: int = -1) -> Dictionary:
	var limit := samples.size() if sample_limit < 0 else mini(sample_limit, samples.size())
	if limit <= 1 or not _tide_access_restricted():
		return {"allowed":true, "reason_code":"OK", "fraction":1.0, "segments_validated":maxi(0, limit - 1)}
	for segment_index in range(limit - 1):
		var start: Vector2 = samples[segment_index].get("position", Vector2.ZERO)
		var finish: Vector2 = samples[segment_index + 1].get("position", start)
		var access := movement_segment_access(start, finish)
		if not bool(access.get("allowed", true)):
			access["first_hit_segment"] = segment_index
			access["segments_validated"] = segment_index + 1
			return access
	return {"allowed":true, "reason_code":"OK", "fraction":1.0, "segments_validated":limit - 1}


func _tide_access_restricted() -> bool:
	if tide_zone_indices.is_empty():
		return false
	var tide: Dictionary = global_environment.get("tide", {})
	return str(_tide_phase()) not in tide.get("open_phases", ["Flood", "High"])


func _is_restricted_tide_zone(zone: Dictionary) -> bool:
	if not bool(zone.get("active", false)): return false
	var effect: Dictionary = effects_by_id.get(str(zone.get("effect_id", "")), {})
	if not bool(effect.get("context", {}).get("tide_controls_access", false)): return false
	var tide: Dictionary = global_environment.get("tide", {})
	return str(_tide_phase()) not in tide.get("open_phases", ["Flood", "High"])


func _first_polygon_intersection_fraction(start: Vector2, end: Vector2, polygon: PackedVector2Array) -> float:
	var best := INF
	var displacement := end - start
	var length_squared := displacement.length_squared()
	if length_squared <= 0.000001: return -1.0
	for index in range(polygon.size()):
		var hit = Geometry2D.segment_intersects_segment(start, end, polygon[index], polygon[(index + 1) % polygon.size()])
		if hit == null: continue
		best = minf(best, clampf(((hit as Vector2) - start).dot(displacement) / length_squared, 0.0, 1.0))
	return -1.0 if is_inf(best) else best


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
	var local_position := position - (zone.get("position", Vector2.ZERO) as Vector2)
	var bounds: Rect2 = zone.get("local_bounds", Rect2())
	if local_position.x < bounds.position.x or local_position.y < bounds.position.y or local_position.x > bounds.end.x or local_position.y > bounds.end.y:
		return false
	return Geometry2D.is_point_in_polygon(local_position, zone.get("base_polygon_packed", PackedVector2Array()))


func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty(): return Rect2()
	var minimum := polygon[0]
	var maximum := polygon[0]
	for point in polygon:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)


func _world_polygon(zone: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	var offset: Vector2 = zone.get("position", Vector2.ZERO)
	for point in zone.get("base_polygon_packed", PackedVector2Array()):
		result.append(point + offset)
	return result


func _packed_polygon(raw: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in raw: result.append(_vector2(point))
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


func _apply_torpedo_sigma_multiplier(context: Dictionary) -> void:
	var reference_sea_state := float(global_environment.get("torpedo_sigma_reference_sea_state", 1.0))
	var sea_state_step := float(global_environment.get("torpedo_sigma_sea_state_step", 0.35))
	var wind_threshold := float(global_environment.get("torpedo_sigma_wind_threshold", 4.0))
	var wind_step := float(global_environment.get("torpedo_sigma_wind_step", 0.06))
	var maximum := float(global_environment.get("torpedo_sigma_multiplier_max", 3.0))
	var multiplier := 1.0
	multiplier += maxf(0.0, float(context.get("sea_state", 0.0)) - reference_sea_state) * sea_state_step
	multiplier += maxf(0.0, float(context.get("wind_speed", 0.0)) - wind_threshold) * wind_step
	context["torpedo_sigma_multiplier"] = clampf(multiplier, 1.0, maximum)


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
	result["wind_speed"] = maxf(float(result.get("wind_speed", 0.0)), float(weather_context.get("wind_speed", 0.0)))
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
	for field in ["torpedo_sigma_reference_sea_state", "torpedo_sigma_sea_state_step", "torpedo_sigma_wind_threshold", "torpedo_sigma_wind_step", "torpedo_sigma_multiplier_max"]:
		result[field] = float(condition_rules.get(field, result.get(field, 0.0)))
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
