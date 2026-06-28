extends RefCounted

const EPSILON := 0.001
const SPATIAL_CELL_SIZE := 256.0

var terrain_definition: Dictionary = {}
var map_size := Vector2.ZERO
var obstacles: Array = []
var regions: Array = []
var obstacle_cells: Dictionary = {}


func configure(definition: Dictionary) -> void:
	terrain_definition = definition.duplicate(true)
	map_size = _vector2(definition.get("map_size", [0.0, 0.0]))
	obstacles = definition.get("obstacles", []).duplicate(true)
	obstacles.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	regions = definition.get("regions", []).duplicate(true)
	regions.sort_custom(func(a, b):
		var priority_a := int(a.get("priority", 0))
		var priority_b := int(b.get("priority", 0))
		return priority_a > priority_b if priority_a != priority_b else str(a.get("id", "")) < str(b.get("id", "")))
	_build_spatial_index()


func is_configured() -> bool:
	return not terrain_definition.is_empty()


func first_segment_hit(start: Vector2, end: Vector2, block_mask: String, sweep_radius: float = 0.0) -> Dictionary:
	var best := _miss(end, block_mask, start.distance_to(end))
	var displacement := end - start
	for obstacle in _obstacles_in_bounds(start, end, maxf(0.0, sweep_radius)):
		if block_mask not in obstacle.get("block_mask", []):
			continue
		var polygon := _polygon(obstacle.get("polygon", []))
		var fraction := _sweep_polygon_fraction(start, displacement, maxf(0.0, sweep_radius), polygon)
		if fraction < 0.0 or fraction > float(best["fraction"]) + EPSILON:
			continue
		if is_equal_approx(fraction, float(best["fraction"])) and str(obstacle.get("id", "")) > str(best.get("obstacle_id", "")):
			continue
		var position := start + displacement * fraction
		best = {
			"hit": true,
			"obstacle_id": str(obstacle.get("id", "")),
			"position": position,
			"normal": _polygon_normal_at(position, polygon),
			"fraction": fraction,
			"distance": start.distance_to(position),
			"block_mask": block_mask,
		}
	return best


func is_segment_clear(start: Vector2, end: Vector2, block_mask: String, sweep_radius: float = 0.0) -> bool:
	return not bool(first_segment_hit(start, end, block_mask, sweep_radius).get("hit", false))


func is_movement_segment_clear(start: Vector2, end: Vector2, radius: float, movement_tags: Array = []) -> bool:
	return not bool(first_segment_hit(start, end, "ShipMovement", radius).get("hit", false)) and _first_illegal_movement_fraction(start, end, radius, movement_tags) < 0.0


func can_occupy_circle(center: Vector2, radius: float, movement_tags: Array = []) -> bool:
	if center.x - radius < 0.0 or center.y - radius < 0.0 or center.x + radius > map_size.x or center.y + radius > map_size.y:
		return false
	for obstacle in _obstacles_in_bounds(center, center, maxf(0.0, radius)):
		if "ShipMovement" not in obstacle.get("block_mask", []):
			continue
		var polygon := _polygon(obstacle.get("polygon", []))
		if _point_in_polygon(center, polygon):
			return false
		for index in range(polygon.size()):
			if _distance_to_segment(center, polygon[index], polygon[(index + 1) % polygon.size()]) <= radius + EPSILON:
				return false
	var top_region := top_region_at(center)
	if top_region.is_empty():
		return true
	match str(top_region.get("region_type", "DeepWater")):
		"ShallowWater": return "ShallowDraft" in movement_tags
		"ReefOrSandbar": return "ReefCapable" in movement_tags
		_: return true


func resolve_circle_motion(start: Vector2, displacement: Vector2, radius: float, movement_tags: Array = []) -> Dictionary:
	if displacement.length_squared() <= EPSILON * EPSILON:
		return {"position": start, "collided": false, "hit": _miss(start, "ShipMovement", 0.0)}
	var first_hit := first_segment_hit(start, start + displacement, "ShipMovement", radius)
	var water_fraction := _first_illegal_movement_fraction(start, start + displacement, radius, movement_tags)
	if water_fraction >= 0.0 and (not bool(first_hit.get("hit", false)) or water_fraction <= float(first_hit.get("fraction", 1.0)) + EPSILON):
		var safe_fraction := maxf(0.0, water_fraction - EPSILON / maxf(displacement.length(), EPSILON))
		var safe_position := start + displacement * safe_fraction
		return {"position": safe_position, "collided": true, "hit": {"hit": true, "obstacle_id": "water_access", "position": safe_position, "normal": Vector2.ZERO, "fraction": water_fraction, "distance": displacement.length() * water_fraction, "block_mask": "ShipMovement"}}
	if not bool(first_hit.get("hit", false)):
		var desired := start + displacement
		if can_occupy_circle(desired, radius, movement_tags):
			return {"position": desired, "collided": false, "hit": first_hit}
		return {"position": start, "collided": true, "hit": {"hit": true, "obstacle_id": "water_access", "position": start, "normal": Vector2.ZERO, "fraction": 0.0, "distance": 0.0, "block_mask": "ShipMovement"}}
	var safe_fraction := maxf(0.0, float(first_hit["fraction"]) - EPSILON / maxf(displacement.length(), EPSILON))
	var safe_position := start + displacement * safe_fraction
	var remaining := displacement * (1.0 - safe_fraction)
	var normal: Vector2 = first_hit.get("normal", Vector2.ZERO)
	var tangent_motion := remaining - normal * remaining.dot(normal)
	if tangent_motion.length_squared() > EPSILON * EPSILON:
		var slide_hit := first_segment_hit(safe_position, safe_position + tangent_motion, "ShipMovement", radius)
		var slide_fraction := maxf(0.0, float(slide_hit.get("fraction", 1.0)) - EPSILON / maxf(tangent_motion.length(), EPSILON)) if bool(slide_hit.get("hit", false)) else 1.0
		var slide_water_fraction := _first_illegal_movement_fraction(safe_position, safe_position + tangent_motion, radius, movement_tags)
		if slide_water_fraction >= 0.0:
			slide_fraction = minf(slide_fraction, maxf(0.0, slide_water_fraction - EPSILON / maxf(tangent_motion.length(), EPSILON)))
		var slide_position := safe_position + tangent_motion * slide_fraction
		if can_occupy_circle(slide_position, radius, movement_tags):
			safe_position = slide_position
	return {"position": safe_position, "collided": true, "hit": first_hit}


func regions_at(position: Vector2) -> Array:
	var result: Array = []
	for region in regions:
		if _point_in_polygon(position, _polygon(region.get("polygon", []))):
			result.append(region.duplicate(true))
	return result


func top_region_at(position: Vector2) -> Dictionary:
	var matches := regions_at(position)
	return {} if matches.is_empty() else matches[0]


func movement_cost_at(position: Vector2, movement_tags: Array = []) -> float:
	var region := top_region_at(position)
	match str(region.get("region_type", "DeepWater")):
		"NavigationChannel": return 0.82
		"CoastalWater": return 1.08
		"ShallowWater": return 1.22 if "ShallowDraft" in movement_tags else INF
		"ReefOrSandbar": return 1.4 if "ReefCapable" in movement_tags else INF
		_: return 1.0


func has_surface_line_of_sight(observer: Vector2, target: Vector2) -> bool:
	return is_segment_clear(observer, target, "SurfaceOpticalLineOfSight")


func debug_spatial_cells() -> Dictionary:
	return obstacle_cells.duplicate(true)


func _build_spatial_index() -> void:
	obstacle_cells.clear()
	for obstacle_index in range(obstacles.size()):
		var polygon := _polygon(obstacles[obstacle_index].get("polygon", []))
		if polygon.is_empty(): continue
		var bounds := _polygon_bounds(polygon)
		var min_cell := _cell_for(bounds.position)
		var max_cell := _cell_for(bounds.position + bounds.size)
		for cell_y in range(min_cell.y, max_cell.y + 1):
			for cell_x in range(min_cell.x, max_cell.x + 1):
				var cell := Vector2i(cell_x, cell_y)
				if not obstacle_cells.has(cell): obstacle_cells[cell] = []
				obstacle_cells[cell].append(obstacle_index)


func _obstacles_in_bounds(start: Vector2, end: Vector2, padding: float) -> Array:
	if obstacle_cells.is_empty(): return obstacles
	var minimum := Vector2(minf(start.x, end.x), minf(start.y, end.y)) - Vector2.ONE * padding
	var maximum := Vector2(maxf(start.x, end.x), maxf(start.y, end.y)) + Vector2.ONE * padding
	var min_cell := _cell_for(minimum)
	var max_cell := _cell_for(maximum)
	var indices := {}
	for cell_y in range(min_cell.y, max_cell.y + 1):
		for cell_x in range(min_cell.x, max_cell.x + 1):
			for obstacle_index in obstacle_cells.get(Vector2i(cell_x, cell_y), []):
				indices[int(obstacle_index)] = true
	var sorted_indices: Array = indices.keys()
	sorted_indices.sort()
	var result: Array = []
	for obstacle_index in sorted_indices: result.append(obstacles[int(obstacle_index)])
	return result


func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	var minimum := polygon[0]
	var maximum := polygon[0]
	for point in polygon:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)


func _cell_for(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / SPATIAL_CELL_SIZE), floori(point.y / SPATIAL_CELL_SIZE))


func _first_illegal_movement_fraction(start: Vector2, end: Vector2, radius: float, movement_tags: Array) -> float:
	if not can_occupy_circle(start, radius, movement_tags): return 0.0
	var distance := start.distance_to(end)
	if distance <= EPSILON: return -1.0
	var step_length := maxf(4.0, radius * 0.25)
	var steps := maxi(1, ceili(distance / step_length))
	var previous_fraction := 0.0
	for index in range(1, steps + 1):
		var fraction := float(index) / float(steps)
		if can_occupy_circle(start.lerp(end, fraction), radius, movement_tags):
			previous_fraction = fraction
			continue
		var low := previous_fraction
		var high := fraction
		for iteration in range(16):
			var middle := (low + high) * 0.5
			if can_occupy_circle(start.lerp(end, middle), radius, movement_tags): low = middle
			else: high = middle
		return high
	return -1.0


func _sweep_polygon_fraction(start: Vector2, displacement: Vector2, radius: float, polygon: PackedVector2Array) -> float:
	if polygon.size() < 3:
		return -1.0
	if _point_in_polygon(start, polygon):
		return 0.0
	var best := INF
	for index in range(polygon.size()):
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		var fraction := _moving_point_segment_fraction(start, displacement, a, b, radius)
		if fraction >= 0.0:
			best = minf(best, fraction)
	return -1.0 if is_inf(best) else best


func _moving_point_segment_fraction(start: Vector2, displacement: Vector2, a: Vector2, b: Vector2, radius: float) -> float:
	if radius <= EPSILON:
		return _segment_intersection_fraction(start, start + displacement, a, b)
	if _distance_to_segment(start, a, b) <= radius + EPSILON:
		return 0.0
	var best := INF
	var edge := b - a
	var length := edge.length()
	if length > EPSILON:
		var tangent := edge / length
		var normal := Vector2(-tangent.y, tangent.x)
		var normal_velocity := displacement.dot(normal)
		if absf(normal_velocity) > EPSILON:
			for raw_side in [-radius, radius]:
				var side := float(raw_side)
				var fraction: float = (side - (start - a).dot(normal)) / normal_velocity
				if fraction < -EPSILON or fraction > 1.0 + EPSILON:
					continue
				var along: float = (start + displacement * fraction - a).dot(tangent)
				if along >= -EPSILON and along <= length + EPSILON:
					best = minf(best, clampf(fraction, 0.0, 1.0))
	for endpoint in [a, b]:
		var fraction := _ray_circle_fraction(start, displacement, endpoint, radius)
		if fraction >= 0.0:
			best = minf(best, fraction)
	return -1.0 if is_inf(best) else best


func _ray_circle_fraction(start: Vector2, displacement: Vector2, center: Vector2, radius: float) -> float:
	var relative := start - center
	var a := displacement.length_squared()
	if a <= EPSILON:
		return -1.0
	var b := 2.0 * relative.dot(displacement)
	var c := relative.length_squared() - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var root := sqrt(discriminant)
	for fraction in [(-b - root) / (2.0 * a), (-b + root) / (2.0 * a)]:
		if fraction >= -EPSILON and fraction <= 1.0 + EPSILON:
			return clampf(fraction, 0.0, 1.0)
	return -1.0


func _segment_intersection_fraction(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	var r := b - a
	var s := d - c
	var denominator := r.cross(s)
	if absf(denominator) <= EPSILON:
		return -1.0
	var t := (c - a).cross(s) / denominator
	var u := (c - a).cross(r) / denominator
	return clampf(t, 0.0, 1.0) if t >= -EPSILON and t <= 1.0 + EPSILON and u >= -EPSILON and u <= 1.0 + EPSILON else -1.0


func _polygon_normal_at(point: Vector2, polygon: PackedVector2Array) -> Vector2:
	var best_distance := INF
	var best_normal := Vector2.ZERO
	for index in range(polygon.size()):
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		var closest := _closest_point(point, a, b)
		var distance := point.distance_to(closest)
		if distance >= best_distance:
			continue
		best_distance = distance
		var normal := (point - closest).normalized()
		if normal.length_squared() <= EPSILON:
			var edge := (b - a).normalized()
			normal = Vector2(-edge.y, edge.x)
		best_normal = normal
	return best_normal


func _point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	var inside := false
	for index in range(polygon.size()):
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		if _distance_to_segment(point, a, b) <= EPSILON:
			return true
		if (a.y > point.y) == (b.y > point.y):
			continue
		var intersection_x := a.x + (point.y - a.y) * (b.x - a.x) / (b.y - a.y)
		if intersection_x >= point.x:
			inside = not inside
	return inside


func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	return point.distance_to(_closest_point(point, a, b))


func _closest_point(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var edge := b - a
	var denominator := edge.length_squared()
	if denominator <= EPSILON:
		return a
	return a + edge * clampf((point - a).dot(edge) / denominator, 0.0, 1.0)


func _polygon(raw: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in raw:
		result.append(_vector2(point))
	return result


func _vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _miss(position: Vector2, block_mask: String, distance: float) -> Dictionary:
	return {"hit": false, "obstacle_id": "", "position": position, "normal": Vector2.ZERO, "fraction": 1.0, "distance": distance, "block_mask": block_mask}
