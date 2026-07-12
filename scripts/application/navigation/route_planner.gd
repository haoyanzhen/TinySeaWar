extends RefCounted

const NODE_CELL_SIZE := 256.0
const DEFAULT_GATE_SPACING := 180.0
const DEFAULT_ATTACHMENT_LIMIT := 4

var _profiles: Array = []
var _last_profile := {}
var _profile_astar_expansions := 0
var _profile_astar_environment_usec := 0
var _profile_astar_neighbor_checks := 0
var gate_spacing := DEFAULT_GATE_SPACING
var attachment_limit := DEFAULT_ATTACHMENT_LIMIT


func get_last_profile() -> Dictionary:
	return _last_profile.duplicate(true)


func configure_runtime_parameters(coarse_gate_spacing: float = DEFAULT_GATE_SPACING, visible_attachment_limit: int = DEFAULT_ATTACHMENT_LIMIT) -> void:
	gate_spacing = clampf(coarse_gate_spacing, 80.0, 480.0)
	attachment_limit = clampi(visible_attachment_limit, 2, 12)


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
	var total_started := Time.get_ticks_usec()
	_last_profile = {"target_validation_usec":0, "direct_clear_usec":0, "start_attachment_usec":0, "goal_attachment_usec":0, "astar_usec":0, "smooth_usec":0, "astar_expansions":0, "astar_environment_usec":0, "astar_neighbor_checks":0}
	if terrain_query == null or not terrain_query.is_configured():
		_last_profile["total_usec"] = Time.get_ticks_usec() - total_started
		return {"ok": true, "waypoints": [target]}
	var stage_started := Time.get_ticks_usec()
	var target_occupiable: bool = bool(terrain_query.can_occupy_circle(target, radius, movement_tags))
	_last_profile["target_validation_usec"] = Time.get_ticks_usec() - stage_started
	stage_started = Time.get_ticks_usec()
	var direct_topology_clear: bool = bool(terrain_query.is_segment_clear(start, target, "ShipMovement"))
	if navigation_definition.is_empty(): direct_topology_clear = terrain_query.is_movement_segment_clear(start, target, radius, movement_tags)
	if target_occupiable and direct_topology_clear and _environment_segment_allowed(terrain_context, start, target):
		_last_profile["direct_clear_usec"] = Time.get_ticks_usec() - stage_started
		_last_profile["total_usec"] = Time.get_ticks_usec() - total_started
		return {"ok": true, "waypoints": [target]}
	_last_profile["direct_clear_usec"] = Time.get_ticks_usec() - stage_started
	if _profiles.is_empty() and not navigation_definition.is_empty():
		configure(navigation_definition)
	var profile := _select_profile(_profiles, radius, movement_tags)
	if profile.is_empty():
		return {"ok": false, "reason_code": "NO_NAVIGATION_PATH", "waypoints": []}
	var nodes: Array = profile.get("nodes", [])
	var by_id: Dictionary = profile.get("by_id", {})
	stage_started = Time.get_ticks_usec()
	var starts := _nearest_visible_nodes(profile, start, radius, movement_tags, terrain_query, terrain_context)
	_last_profile["start_attachment_usec"] = Time.get_ticks_usec() - stage_started
	stage_started = Time.get_ticks_usec()
	var goals := _nearest_visible_nodes(profile, target, radius, movement_tags, terrain_query, terrain_context, target_occupiable)
	_last_profile["goal_attachment_usec"] = Time.get_ticks_usec() - stage_started
	if starts.is_empty() or goals.is_empty():
		_last_profile["total_usec"] = Time.get_ticks_usec() - total_started
		return {"ok": false, "reason_code": "NO_NAVIGATION_PATH", "waypoints": []}
	stage_started = Time.get_ticks_usec()
	_profile_astar_expansions = 0
	_profile_astar_environment_usec = 0
	_profile_astar_neighbor_checks = 0
	var result := _a_star(by_id, starts, goals, target, terrain_context)
	_last_profile["astar_usec"] = Time.get_ticks_usec() - stage_started
	_last_profile["astar_expansions"] = _profile_astar_expansions
	_last_profile["astar_environment_usec"] = _profile_astar_environment_usec
	_last_profile["astar_neighbor_checks"] = _profile_astar_neighbor_checks
	if result.is_empty():
		_last_profile["total_usec"] = Time.get_ticks_usec() - total_started
		return {"ok": false, "reason_code": "NO_NAVIGATION_PATH", "waypoints": []}
	var raw_points: Array = []
	for node_id in result:
		raw_points.append(_vector2(by_id[node_id]["position"]))
	if target_occupiable: raw_points.append(target)
	stage_started = Time.get_ticks_usec()
	var gates := _coarse_gates(raw_points, start, radius, terrain_query, terrain_context)
	_last_profile["smooth_usec"] = Time.get_ticks_usec() - stage_started
	_last_profile["raw_waypoint_count"] = raw_points.size()
	_last_profile["smoothed_waypoint_count"] = gates.size()
	_last_profile["total_usec"] = Time.get_ticks_usec() - total_started
	var resolved_target: Vector2 = target if target_occupiable else (gates[-1]["center"] if not gates.is_empty() else target)
	return {"ok": true, "waypoints": gates.map(func(gate): return gate["center"]), "gates":gates, "resolved_target":resolved_target, "target_projected":not target_occupiable}


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


func _nearest_visible_nodes(profile: Dictionary, position: Vector2, radius: float, movement_tags: Array, terrain_query, terrain_context, require_visibility: bool = true) -> Array:
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
		if distance <= 420.0: candidates.append({"id": str(node.get("id", "")), "distance": distance, "position":node_position})
	candidates.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]) if not is_equal_approx(float(a["distance"]), float(b["distance"])) else str(a["id"]) < str(b["id"]))
	var result: Array = []
	for candidate in candidates:
		if require_visibility and (not terrain_query.is_segment_clear(position, candidate["position"], "ShipMovement") or not _environment_segment_allowed(terrain_context, position, candidate["position"])): continue
		result.append(candidate["id"])
		if result.size() >= attachment_limit: break
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
		_profile_astar_expansions += 1
		if goals.has(current_id):
			var path: Array = []
			while came_from.has(current_id):
				path.push_front(current_id)
				current_id = str(came_from[current_id])
			path.push_front(current_id)
			return path
		var current_position := _vector2(by_id[current_id]["position"])
		for neighbor_id in by_id[current_id].get("neighbors", []):
			_profile_astar_neighbor_checks += 1
			if not by_id.has(neighbor_id):
				continue
			var neighbor_position := _vector2(by_id[neighbor_id]["position"])
			var environment_started := Time.get_ticks_usec()
			var environment_allowed := _environment_segment_allowed(terrain_context, current_position, neighbor_position)
			_profile_astar_environment_usec += Time.get_ticks_usec() - environment_started
			if not environment_allowed: continue
			# Strategic search only answers reachability and broad progress. Currents and
			# local speed modifiers belong to the short-horizon dynamics planner; pricing
			# every graph edge through a full terrain context caused most A* cost.
			var candidate_cost := float(cost[current_id]) + current_position.distance_to(neighbor_position)
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


func _coarse_gates(points: Array, start: Vector2, radius: float, terrain_query, terrain_context) -> Array:
	var result: Array = []
	var anchor := start
	var index := 0
	while index < points.size():
		var furthest := index
		for candidate in range(index, points.size()):
			if anchor.distance_to(points[candidate]) > gate_spacing and candidate > index: break
			if terrain_query.is_segment_clear(anchor, points[candidate], "ShipMovement") and _environment_segment_allowed(terrain_context, anchor, points[candidate]): furthest = candidate
		var center: Vector2 = points[furthest]
		result.append({"center":center, "radius":maxf(radius * 2.0, gate_spacing * 0.35)})
		anchor = center
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
