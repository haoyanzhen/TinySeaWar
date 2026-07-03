extends RefCounted

const NODE_CELL_SIZE := 256.0

var _profiles: Array = []


func configure(navigation_definition: Dictionary) -> void:
	_profiles.clear()
	for raw_profile in navigation_definition.get("profiles", []):
		var nodes: Array = raw_profile.get("nodes", [])
		var by_id := {}
		var node_cells := {}
		for node_index in range(nodes.size()):
			var node: Dictionary = nodes[node_index]
			by_id[str(node.get("id", ""))] = node
			var cell := _node_cell(_vector2(node.get("position", [])))
			if not node_cells.has(cell): node_cells[cell] = []
			node_cells[cell].append(node_index)
		_profiles.append({
			"radius": float(raw_profile.get("radius", 0.0)),
			"movement_tags": raw_profile.get("movement_tags", []).duplicate(),
			"nodes": nodes,
			"by_id": by_id,
			"node_cells": node_cells,
		})
	_profiles.sort_custom(func(a, b): return float(a["radius"]) < float(b["radius"]))


func plan_path(terrain_query, navigation_definition: Dictionary, start: Vector2, target: Vector2, radius: float, movement_tags: Array, terrain_context = null) -> Dictionary:
	if terrain_query == null or not terrain_query.is_configured():
		return {"ok": true, "waypoints": [target]}
	if not terrain_query.can_occupy_circle(target, radius, movement_tags):
		var top_region: Dictionary = terrain_query.top_region_at(target)
		var reason := "WATER_DEPTH_NOT_ALLOWED" if str(top_region.get("region_type", "")) in ["ShallowWater", "ReefOrSandbar"] else "TARGET_POSITION_ON_LAND"
		return {"ok": false, "reason_code": reason, "waypoints": []}
	if terrain_query.is_movement_segment_clear(start, target, radius, movement_tags) and _environment_segment_allowed(terrain_context, start, target):
		return {"ok": true, "waypoints": [target]}
	if _profiles.is_empty() and not navigation_definition.is_empty():
		configure(navigation_definition)
	var profile := _select_profile(_profiles, radius, movement_tags)
	if profile.is_empty():
		return {"ok": false, "reason_code": "NO_NAVIGATION_PATH", "waypoints": []}
	var nodes: Array = profile.get("nodes", [])
	var by_id: Dictionary = profile.get("by_id", {})
	var starts := _nearest_visible_nodes(profile, start, radius, movement_tags, terrain_query, terrain_context)
	var goals := _nearest_visible_nodes(profile, target, radius, movement_tags, terrain_query, terrain_context)
	if starts.is_empty() or goals.is_empty():
		return {"ok": false, "reason_code": "NO_NAVIGATION_PATH", "waypoints": []}
	var result := _a_star(by_id, starts, goals, target, terrain_context)
	if result.is_empty():
		return {"ok": false, "reason_code": "NO_NAVIGATION_PATH", "waypoints": []}
	var waypoints: Array = []
	for node_id in result:
		waypoints.append(_vector2(by_id[node_id]["position"]))
	waypoints.append(target)
	return {"ok": true, "waypoints": _smooth(waypoints, start, radius, movement_tags, terrain_query, terrain_context)}


func _select_profile(profiles: Array, radius: float, movement_tags: Array) -> Dictionary:
	var candidates: Array = []
	for profile in profiles:
		if float(profile.get("radius", 0.0)) + 0.001 < radius:
			continue
		var profile_tags: Array = profile.get("movement_tags", [])
		var compatible := true
		if ("ShallowDraft" in profile_tags) != ("ShallowDraft" in movement_tags):
			compatible = false
		if compatible:
			candidates.append(profile)
	candidates.sort_custom(func(a, b): return float(a.get("radius", 0.0)) < float(b.get("radius", 0.0)))
	return {} if candidates.is_empty() else candidates[0]


func _nearest_visible_nodes(profile: Dictionary, position: Vector2, radius: float, movement_tags: Array, terrain_query, terrain_context) -> Array:
	var candidates: Array = []
	var nodes: Array = profile.get("nodes", [])
	var node_cells: Dictionary = profile.get("node_cells", {})
	var center := _node_cell(position)
	var node_indices := {}
	for cell_y in range(center.y - 2, center.y + 3):
		for cell_x in range(center.x - 2, center.x + 3):
			for node_index in node_cells.get(Vector2i(cell_x, cell_y), []): node_indices[int(node_index)] = true
	var sorted_indices: Array = node_indices.keys()
	sorted_indices.sort()
	for node_index in sorted_indices:
		var node: Dictionary = nodes[int(node_index)]
		var node_position := _vector2(node.get("position", []))
		var distance := position.distance_to(node_position)
		if distance > 420.0 or not terrain_query.is_movement_segment_clear(position, node_position, radius, movement_tags) or not _environment_segment_allowed(terrain_context, position, node_position):
			continue
		candidates.append({"id": str(node.get("id", "")), "distance": distance})
	candidates.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]) if not is_equal_approx(float(a["distance"]), float(b["distance"])) else str(a["id"]) < str(b["id"]))
	var result: Array = []
	for index in range(mini(8, candidates.size())):
		result.append(candidates[index]["id"])
	return result


func _node_cell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / NODE_CELL_SIZE), floori(position.y / NODE_CELL_SIZE))


func _a_star(by_id: Dictionary, start_ids: Array, goal_ids: Array, target: Vector2, terrain_context) -> Array:
	var open: Array = []
	var closed := {}
	var came_from := {}
	var cost := {}
	var goals := {}
	for goal_id in goal_ids:
		goals[goal_id] = true
	for start_id in start_ids:
		cost[start_id] = 0.0
		_heap_push(open, {"id": start_id, "score": _vector2(by_id[start_id]["position"]).distance_to(target)})
	while not open.is_empty():
		var current_id: String = str(_heap_pop(open)["id"])
		if closed.has(current_id):
			continue
		closed[current_id] = true
		if goals.has(current_id):
			var path: Array = []
			while came_from.has(current_id):
				path.push_front(current_id)
				current_id = str(came_from[current_id])
			path.push_front(current_id)
			return path
		var current_position := _vector2(by_id[current_id]["position"])
		for neighbor_id in by_id[current_id].get("neighbors", []):
			if not by_id.has(neighbor_id):
				continue
			var neighbor_position := _vector2(by_id[neighbor_id]["position"])
			if not _environment_segment_allowed(terrain_context, current_position, neighbor_position): continue
			var candidate_cost := float(cost[current_id]) + current_position.distance_to(neighbor_position) * _environment_cost_multiplier(terrain_context, current_position, neighbor_position)
			if cost.has(neighbor_id) and candidate_cost >= float(cost[neighbor_id]) - 0.001:
				continue
			cost[neighbor_id] = candidate_cost
			came_from[neighbor_id] = current_id
			_heap_push(open, {"id": neighbor_id, "score": candidate_cost + neighbor_position.distance_to(target)})
	return []


func _heap_push(heap: Array, item: Dictionary) -> void:
	heap.append(item)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if not _heap_less(item, heap[parent]): break
		heap[index] = heap[parent]
		index = parent
	heap[index] = item


func _heap_pop(heap: Array) -> Dictionary:
	var result: Dictionary = heap[0]
	var tail: Dictionary = heap.pop_back()
	if heap.is_empty(): return result
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size(): break
		var right := left + 1
		var child := right if right < heap.size() and _heap_less(heap[right], heap[left]) else left
		if not _heap_less(heap[child], tail): break
		heap[index] = heap[child]
		index = child
	heap[index] = tail
	return result


func _heap_less(a: Dictionary, b: Dictionary) -> bool:
	var score_a := float(a["score"])
	var score_b := float(b["score"])
	return score_a < score_b if not is_equal_approx(score_a, score_b) else str(a["id"]) < str(b["id"])


func _smooth(waypoints: Array, start: Vector2, radius: float, movement_tags: Array, terrain_query, terrain_context) -> Array:
	var result: Array = []
	var anchor := start
	var index := 0
	while index < waypoints.size():
		var furthest := index
		for candidate in range(index, waypoints.size()):
			if terrain_query.is_movement_segment_clear(anchor, waypoints[candidate], radius, movement_tags) and _environment_segment_allowed(terrain_context, anchor, waypoints[candidate]):
				furthest = candidate
		result.append(waypoints[furthest])
		anchor = waypoints[furthest]
		index = furthest + 1
	return result


func _environment_segment_allowed(terrain_context, start: Vector2, end: Vector2) -> bool:
	return terrain_context == null or bool(terrain_context.movement_segment_access(start, end).get("allowed", true))


func _environment_cost_multiplier(terrain_context, start: Vector2, end: Vector2) -> float:
	if terrain_context == null: return 1.0
	var midpoint := start.lerp(end, 0.5)
	var context: Dictionary = terrain_context.context_at(midpoint)
	var direction := (end - start).normalized()
	var current_assist := (context.get("current_vector", Vector2.ZERO) as Vector2).dot(direction) / 100.0
	return 1.0 / maxf(0.25, float(context.get("movement_speed_multiplier", 1.0)) + current_assist)


func _vector2(value: Variant) -> Vector2:
	return value if value is Vector2 else Vector2(float(value[0]), float(value[1]))
