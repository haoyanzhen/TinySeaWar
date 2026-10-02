extends RefCounted
## Supplement the visual filter with own, public task summaries. Never forward raw tasks.
var own_missions: Dictionary = {}

func events(raw: Array, view: Dictionary, focus: String, tasks: Array = []) -> Array:
	# Ownership is captured from the actual own task, not guessed from a facility
	# which may have changed sides later in the same tick. Retain IDs for cancellation.
	for task in tasks:
		if task.get("faction_id", "") == "player": own_missions[str(task.get("mission_id", ""))] = true
	var result: Array = []
	for event in raw:
		var type := str(event.get("event_type", ""))
		if type.begins_with("SupportMission") and type in ["SupportMissionStarted", "SupportMissionLaunched", "SupportMissionCompleted", "SupportMissionCancelled"]:
			var facility: Dictionary = view.get("facilities", {}).get(str(event.get("facility_id", "")), {})
			if facility.is_empty(): continue
			var mission_id := str(event.get("mission_id", ""))
			if event.has("faction_id"):
				if event.faction_id != "player": continue
			elif not own_missions.has(mission_id): continue
			if type in ["SupportMissionCompleted", "SupportMissionCancelled"]: own_missions.erase(mission_id)
			result.append({"event_type":"Audio"+type,"event_id":event.get("event_id", ""),"tick_index":event.get("tick_index", 0),"mission_id":event.get("mission_id", ""),"position":facility.get("position", Vector2.INF)})
		elif type == "EnvironmentZoneChanged" and event.get("phase", "") == "Dissipated":
			var unit: Dictionary = view.get("units", {}).get(focus, {})
			if unit.get("faction_id", "") != "player": continue
			for zone in view.get("environment_zones", []):
				if zone.get("id", "") != event.get("zone_id", ""): continue
				var pair = zone.get("position", Vector2.INF)
				var position: Vector2 = pair if pair is Vector2 else Vector2(float(pair[0]),float(pair[1]))
				var polygon := PackedVector2Array()
				for point in zone.get("polygon", []): polygon.append(point if point is Vector2 else Vector2(float(point[0]),float(point[1])))
				if (polygon.size() >= 3 and Geometry2D.is_point_in_polygon(unit.position, polygon)) or (position.distance_to(unit.position) <= float(zone.get("radius", 0))):
					result.append({"event_type":"AudioEnvironmentDissipated","event_id":event.get("event_id", ""),"tick_index":event.get("tick_index", 0)})
	return result
