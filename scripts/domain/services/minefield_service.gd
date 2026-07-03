extends RefCounted

const EPSILON := 0.001

var minefields_by_id: Dictionary = {}


func configure(definitions: Array, terrain_definition_id: String) -> void:
	minefields_by_id.clear()
	for definition in definitions:
		if str(definition.get("definition_type", "")) != "MinefieldDefinition":
			continue
		if str(definition.get("terrain_definition_id", "")) != terrain_definition_id:
			continue
		minefields_by_id[str(definition["id"])] = {
			"definition_id": str(definition["id"]),
			"display_name": str(definition.get("display_name", definition["id"])),
			"polygon": definition.get("polygon", []).duplicate(true),
			"safe_channels": definition.get("safe_channels", []).duplicate(true),
			"owner_faction_id": str(definition.get("owner_faction_id", "neutral")),
			"operation_state": str(definition.get("operation_state", "Dormant")),
			"known_by_faction": definition.get("known_by_faction", []).duplicate(),
			"controller_facility_id": str(definition.get("controller_facility_id", "")),
			"damage": float(definition.get("damage", 0.0)),
			"triggered_unit_ids": [],
			"controller_rules": definition.get("controller_rules", {}).duplicate(true),
			"_polygon": _polygon(definition.get("polygon", [])),
			"_safe_channel_polygons": _polygons(definition.get("safe_channels", [])),
		}


func sync_controllers(facilities: Dictionary) -> Array:
	var events: Array = []
	for minefield_id in _sorted_ids():
		var minefield: Dictionary = minefields_by_id[minefield_id]
		var controller_id := str(minefield.get("controller_facility_id", ""))
		if controller_id.is_empty():
			continue
		var controller: Dictionary = facilities.get(controller_id, {})
		if controller.is_empty():
			continue
		var old_state := str(minefield.get("operation_state", "Dormant"))
		var old_owner := str(minefield.get("owner_faction_id", "neutral"))
		var controller_alive := str(controller.get("life_state", "Alive")) == "Alive"
		var controller_state := str(controller.get("operation_state", "Dormant"))
		if not controller_alive:
			minefield["operation_state"] = str(minefield.get("controller_rules", {}).get("on_destroyed", "Disabled"))
		elif controller_state == "Suppressed":
			minefield["operation_state"] = str(minefield.get("controller_rules", {}).get("on_suppressed", "Dormant"))
		elif controller_state == "Active":
			minefield["operation_state"] = str(minefield.get("controller_rules", {}).get("on_active", "Active"))
			var controller_owner := str(controller.get("faction_id", old_owner))
			if controller_owner != "neutral":
				minefield["owner_faction_id"] = controller_owner
				_add_knowledge(minefield, controller_owner)
		if old_state != str(minefield["operation_state"]) or old_owner != str(minefield["owner_faction_id"]):
			events.append({
				"event_type": "MineFieldStateChanged",
				"minefield_id": minefield_id,
				"operation_state": minefield["operation_state"],
				"owner_faction_id": minefield["owner_faction_id"],
			})
	return events


func resolve_unit_motion(unit: Dictionary, start: Vector2, end: Vector2) -> Dictionary:
	if str(unit.get("life_state", "")) != "Alive":
		return {"triggered": false}
	var best := {"triggered": false, "fraction": 1.0}
	for minefield_id in _sorted_ids():
		var minefield: Dictionary = minefields_by_id[minefield_id]
		if str(minefield.get("operation_state", "")) != "Active":
			continue
		if str(minefield.get("owner_faction_id", "neutral")) == str(unit.get("faction_id", "")):
			continue
		if str(unit.get("entity_id", "")) in minefield.get("triggered_unit_ids", []):
			continue
		var fraction := _first_unsafe_fraction(start, end, minefield)
		if fraction < 0.0 or fraction > float(best.get("fraction", 1.0)) + EPSILON:
			continue
		if is_equal_approx(fraction, float(best.get("fraction", 1.0))) and minefield_id > str(best.get("minefield_id", "")):
			continue
		best = {
			"triggered": true,
			"fraction": fraction,
			"position": start.lerp(end, fraction),
			"minefield_id": minefield_id,
			"damage": float(minefield.get("damage", 0.0)),
		}
	if not bool(best.get("triggered", false)):
		return best
	var triggered_field: Dictionary = minefields_by_id[str(best["minefield_id"])]
	triggered_field["triggered_unit_ids"].append(str(unit.get("entity_id", "")))
	_add_knowledge(triggered_field, str(unit.get("faction_id", "")))
	return best


func avoidance_waypoint(faction_id: String, start: Vector2, target: Vector2) -> Vector2:
	for minefield_id in _sorted_ids():
		var minefield: Dictionary = minefields_by_id[minefield_id]
		if faction_id not in minefield.get("known_by_faction", []):
			continue
		if str(minefield.get("operation_state", "")) != "Active" or _first_unsafe_fraction(start, target, minefield) < 0.0:
			continue
		var channels: Array = minefield.get("safe_channels", [])
		if channels.is_empty():
			return start
		return _polygon_center(channels[0])
	return target


func snapshot() -> Dictionary:
	var result := minefields_by_id.duplicate(true)
	for minefield in result.values():
		minefield.erase("_polygon")
		minefield.erase("_safe_channel_polygons")
	return result


func _first_unsafe_fraction(start: Vector2, end: Vector2, minefield: Dictionary) -> float:
	if _unsafe_at(start, minefield):
		return 0.0
	var fractions: Array[float] = [0.0, 1.0]
	_append_polygon_intersections(fractions, start, end, minefield.get("_polygon", PackedVector2Array()))
	for channel_polygon in minefield.get("_safe_channel_polygons", []):
		_append_polygon_intersections(fractions, start, end, channel_polygon)
	fractions.sort()
	for index in range(fractions.size() - 1):
		var low := fractions[index]
		var high := fractions[index + 1]
		if high - low <= EPSILON: continue
		if _unsafe_at(start.lerp(end, (low + high) * 0.5), minefield):
			return low
	return -1.0


func _unsafe_at(position: Vector2, minefield: Dictionary) -> bool:
	if not Geometry2D.is_point_in_polygon(position, minefield.get("_polygon", PackedVector2Array())):
		return false
	for safe_channel in minefield.get("_safe_channel_polygons", []):
		if Geometry2D.is_point_in_polygon(position, safe_channel):
			return false
	return true


func _append_polygon_intersections(fractions: Array[float], start: Vector2, end: Vector2, polygon: PackedVector2Array) -> void:
	var displacement := end - start
	var length_squared := displacement.length_squared()
	if length_squared <= EPSILON: return
	for index in range(polygon.size()):
		var hit = Geometry2D.segment_intersects_segment(start, end, polygon[index], polygon[(index + 1) % polygon.size()])
		if hit == null: continue
		var fraction := clampf(((hit as Vector2) - start).dot(displacement) / length_squared, 0.0, 1.0)
		if fraction not in fractions: fractions.append(fraction)


func _add_knowledge(minefield: Dictionary, faction_id: String) -> void:
	if faction_id.is_empty() or faction_id == "neutral":
		return
	if faction_id not in minefield.get("known_by_faction", []):
		minefield["known_by_faction"].append(faction_id)
		minefield["known_by_faction"].sort()


func _polygon_center(raw: Array) -> Vector2:
	if raw.is_empty():
		return Vector2.ZERO
	var center := Vector2.ZERO
	for point in raw:
		center += _vector2(point)
	return center / float(raw.size())


func _sorted_ids() -> Array:
	var result: Array = minefields_by_id.keys()
	result.sort()
	return result


func _polygon(raw: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in raw:
		result.append(_vector2(point))
	return result


func _polygons(raw_polygons: Array) -> Array:
	var result: Array = []
	for raw in raw_polygons: result.append(_polygon(raw))
	return result


func _vector2(value: Variant) -> Vector2:
	return value if value is Vector2 else Vector2(float(value[0]), float(value[1]))
