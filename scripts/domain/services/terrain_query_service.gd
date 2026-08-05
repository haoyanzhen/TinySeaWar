extends RefCounted

const EPSILON := 0.001
const SPATIAL_CELL_SIZE := 256.0

var terrain_definition: Dictionary = {}
var map_size := Vector2.ZERO
var obstacles: Array = []
var regions: Array = []
var obstacle_cells: Dictionary = {}
var region_cells: Dictionary = {}
var collision_field = null
var _collision_field_diagnostics := {}


func configure(definition: Dictionary, configured_collision_field = null) -> void:
	terrain_definition = definition.duplicate(true)
	map_size = _vector2(definition.get("map_size", [0.0, 0.0]))
	collision_field = configured_collision_field
	obstacles = definition.get("obstacles", []).duplicate(true)
	for obstacle in obstacles:
		obstacle["_polygon"] = _polygon(obstacle.get("polygon", []))
	obstacles.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	regions = definition.get("regions", []).duplicate(true)
	for region in regions:
		region["_polygon"] = _polygon(region.get("polygon", []))
	regions.sort_custom(func(a, b):
		var priority_a := int(a.get("priority", 0))
		var priority_b := int(b.get("priority", 0))
		return priority_a > priority_b if priority_a != priority_b else str(a.get("id", "")) < str(b.get("id", "")))
	_build_spatial_index()
	reset_collision_field_diagnostics()


func is_configured() -> bool:
	return not terrain_definition.is_empty()


func first_segment_hit(start: Vector2, end: Vector2, block_mask: String, sweep_radius: float = 0.0) -> Dictionary:
	var best := _first_map_boundary_hit(start, end, maxf(0.0, sweep_radius)) if block_mask == "ShipMovement" else _miss(end, block_mask, start.distance_to(end))
	var displacement := end - start
	for obstacle in _obstacles_in_bounds(start, end, maxf(0.0, sweep_radius)):
		if block_mask not in obstacle.get("block_mask", []):
			continue
		var polygon: PackedVector2Array = obstacle.get("_polygon", PackedVector2Array())
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
	return str(validate_movement_segment(start, end, radius, movement_tags).get("status", "Collides")) in ["DefinitelyClear", "ExactClear"]


func validate_movement_segment(start: Vector2, end: Vector2, radius: float, movement_tags: Array = [], navigation_margin: float = 0.0, departure_normal: Vector2 = Vector2.ZERO) -> Dictionary:
	var required_clearance := maxf(0.0, radius + navigation_margin)
	var field_result := {"status":"FieldUnavailable", "minimum_clearance":0.0, "field_cells_visited":0}
	_collision_field_diagnostics["collision_field_queries"] = int(_collision_field_diagnostics.get("collision_field_queries", 0)) + 1
	if collision_field != null and collision_field.is_configured():
		var field_started_usec := Time.get_ticks_usec()
		field_result = collision_field.query_segment(start, end, required_clearance)
		_collision_field_diagnostics["collision_field_usec"] = int(_collision_field_diagnostics.get("collision_field_usec", 0)) + Time.get_ticks_usec() - field_started_usec
	else:
		_collision_field_diagnostics["collision_field_unavailable_fallbacks"] = int(_collision_field_diagnostics.get("collision_field_unavailable_fallbacks", 0)) + 1
	_collision_field_diagnostics["collision_field_cells_visited"] = int(_collision_field_diagnostics.get("collision_field_cells_visited", 0)) + int(field_result.get("field_cells_visited", 0))
	var region_fraction := _first_illegal_region_fraction(start, end, movement_tags)
	if region_fraction >= 0.0:
		var region_hit_position := start.lerp(end, region_fraction)
		return {
			"status":"Collides", "first_hit_fraction":region_fraction,
			"minimum_clearance":float(field_result.get("minimum_clearance", 0.0)),
			"field_cells_visited":int(field_result.get("field_cells_visited", 0)),
			"exact_segment_checks":0,
			"hit":{"hit":true, "obstacle_id":"water_access", "position":region_hit_position, "normal":Vector2.ZERO, "fraction":region_fraction},
		}
	if str(field_result.get("status", "FieldUnavailable")) == "DefinitelyClear":
		_collision_field_diagnostics["collision_field_definitely_clear"] = int(_collision_field_diagnostics.get("collision_field_definitely_clear", 0)) + 1
		return {
			"status":"DefinitelyClear",
			"minimum_clearance":float(field_result.get("minimum_clearance", 0.0)),
			"field_cells_visited":int(field_result.get("field_cells_visited", 0)),
			"exact_segment_checks":0,
		}
	_collision_field_diagnostics["collision_field_exact_fallbacks"] = int(_collision_field_diagnostics.get("collision_field_exact_fallbacks", 0)) + 1
	var exact_clearance := radius if start.is_equal_approx(end) else required_clearance
	var hit := first_segment_hit(start, end, "ShipMovement", exact_clearance)
	var effective_departure_normal := departure_normal
	var soft_margin_departure := false
	if bool(hit.get("hit", false)) and float(hit.get("fraction", 1.0)) <= EPSILON and effective_departure_normal.length_squared() <= EPSILON and navigation_margin > EPSILON:
		var actual_clearance_hit := first_segment_hit(start, start, "ShipMovement", radius)
		if not bool(actual_clearance_hit.get("hit", false)):
			effective_departure_normal = hit.get("normal", Vector2.ZERO)
			soft_margin_departure = true
	if bool(hit.get("hit", false)) and float(hit.get("fraction", 1.0)) <= EPSILON and effective_departure_normal.length_squared() > EPSILON:
		var hit_normal: Vector2 = hit.get("normal", Vector2.ZERO)
		var displacement := end - start
		if displacement.dot(effective_departure_normal) > EPSILON and hit_normal.dot(effective_departure_normal) > 0.25 and displacement.length() > EPSILON:
			var departure_fraction := clampf(maxf(navigation_margin, EPSILON * 4.0) / displacement.length(), 0.01, 0.25)
			var departure_hit := first_segment_hit(start, end, "ShipMovement", radius) if soft_margin_departure else first_segment_hit(start.lerp(end, departure_fraction), end, "ShipMovement", required_clearance)
			if not bool(departure_hit.get("hit", false)):
				hit = departure_hit
	return {
		"status":"Collides" if bool(hit.get("hit", false)) else "ExactClear",
		"first_hit_fraction":float(hit.get("fraction", 1.0)),
		"minimum_clearance":float(field_result.get("minimum_clearance", required_clearance)),
		"field_cells_visited":int(field_result.get("field_cells_visited", 0)),
		"exact_segment_checks":1,
		"hit":hit,
	}


func validate_movement_trajectory(samples: Array, radius: float, movement_tags: Array = [], navigation_margin: float = 0.0, departure_normal: Vector2 = Vector2.ZERO) -> Dictionary:
	var segment_count := maxi(0, samples.size() - 1)
	if segment_count == 0:
		return {"status":"ExactClear", "minimum_clearance":0.0, "field_cells_visited":0, "exact_segment_checks":0, "segments_validated":0}
	var required_clearance := maxf(0.0, radius + navigation_margin)
	var definitely_clear := PackedByteArray()
	definitely_clear.resize(segment_count)
	var minimum_by_segment := PackedFloat32Array()
	minimum_by_segment.resize(segment_count)
	var cells_by_segment := PackedInt32Array()
	cells_by_segment.resize(segment_count)
	var field_available: bool = collision_field != null and collision_field.is_configured()
	_collision_field_diagnostics["collision_field_queries"] = int(_collision_field_diagnostics.get("collision_field_queries", 0)) + segment_count
	if field_available:
		var field_started_usec := Time.get_ticks_usec()
		var batch_result: Dictionary = collision_field.query_trajectory_samples(samples, required_clearance)
		definitely_clear = batch_result.get("definitely_clear", definitely_clear)
		minimum_by_segment = batch_result.get("minimum_by_segment", minimum_by_segment)
		cells_by_segment = batch_result.get("cells_by_segment", cells_by_segment)
		_collision_field_diagnostics["collision_field_usec"] = int(_collision_field_diagnostics.get("collision_field_usec", 0)) + Time.get_ticks_usec() - field_started_usec
	else:
		_collision_field_diagnostics["collision_field_unavailable_fallbacks"] = int(_collision_field_diagnostics.get("collision_field_unavailable_fallbacks", 0)) + segment_count
	var minimum_clearance := INF
	var total_cells := 0
	var exact_checks := 0
	for index in range(segment_count):
		var start: Vector2 = samples[index].get("position", Vector2.ZERO)
		var finish: Vector2 = samples[index + 1].get("position", start)
		minimum_clearance = minf(minimum_clearance, float(minimum_by_segment[index]))
		total_cells += int(cells_by_segment[index])
		_collision_field_diagnostics["collision_field_cells_visited"] = int(_collision_field_diagnostics.get("collision_field_cells_visited", 0)) + int(cells_by_segment[index])
		var region_fraction := _first_illegal_region_fraction(start, finish, movement_tags)
		if region_fraction >= 0.0:
			var region_position := start.lerp(finish, region_fraction)
			return {"status":"Collides", "first_hit_segment":index, "first_hit_fraction":region_fraction, "minimum_clearance":0.0 if is_inf(minimum_clearance) else minimum_clearance, "field_cells_visited":total_cells, "exact_segment_checks":exact_checks, "segments_validated":index + 1, "hit":{"hit":true, "obstacle_id":"water_access", "position":region_position, "normal":Vector2.ZERO, "fraction":region_fraction}}
		if bool(definitely_clear[index]):
			_collision_field_diagnostics["collision_field_definitely_clear"] = int(_collision_field_diagnostics.get("collision_field_definitely_clear", 0)) + 1
			continue
		_collision_field_diagnostics["collision_field_exact_fallbacks"] = int(_collision_field_diagnostics.get("collision_field_exact_fallbacks", 0)) + 1
		exact_checks += 1
		var exact_clearance := radius if start.is_equal_approx(finish) else required_clearance
		var hit := first_segment_hit(start, finish, "ShipMovement", exact_clearance)
		var effective_departure_normal := departure_normal
		var soft_margin_departure := false
		if bool(hit.get("hit", false)) and float(hit.get("fraction", 1.0)) <= EPSILON and effective_departure_normal.length_squared() <= EPSILON and navigation_margin > EPSILON:
			var actual_clearance_hit := first_segment_hit(start, start, "ShipMovement", radius)
			if not bool(actual_clearance_hit.get("hit", false)):
				effective_departure_normal = hit.get("normal", Vector2.ZERO)
				soft_margin_departure = true
		if bool(hit.get("hit", false)) and float(hit.get("fraction", 1.0)) <= EPSILON and effective_departure_normal.length_squared() > EPSILON:
			var hit_normal: Vector2 = hit.get("normal", Vector2.ZERO)
			var displacement := finish - start
			if displacement.dot(effective_departure_normal) > EPSILON and hit_normal.dot(effective_departure_normal) > 0.25 and displacement.length() > EPSILON:
				var departure_fraction := clampf(maxf(navigation_margin, EPSILON * 4.0) / displacement.length(), 0.01, 0.25)
				var departure_hit := first_segment_hit(start, finish, "ShipMovement", radius) if soft_margin_departure else first_segment_hit(start.lerp(finish, departure_fraction), finish, "ShipMovement", required_clearance)
				if not bool(departure_hit.get("hit", false)): hit = departure_hit
		if bool(hit.get("hit", false)):
			return {"status":"Collides", "first_hit_segment":index, "first_hit_fraction":hit.get("fraction", 1.0), "minimum_clearance":0.0 if is_inf(minimum_clearance) else minimum_clearance, "field_cells_visited":total_cells, "exact_segment_checks":exact_checks, "segments_validated":index + 1, "hit":hit}
	return {"status":"DefinitelyClear" if exact_checks == 0 else "ExactClear", "minimum_clearance":0.0 if is_inf(minimum_clearance) else minimum_clearance, "field_cells_visited":total_cells, "exact_segment_checks":exact_checks, "segments_validated":segment_count}


func collision_field_available() -> bool:
	return collision_field != null and collision_field.is_configured()


func reset_collision_field_diagnostics() -> void:
	_collision_field_diagnostics = {
		"collision_field_usec":0,
		"collision_field_queries":0,
		"collision_field_cells_visited":0,
		"collision_field_definitely_clear":0,
		"collision_field_exact_fallbacks":0,
		"collision_field_unavailable_fallbacks":0,
	}


func collision_field_diagnostics() -> Dictionary:
	return _collision_field_diagnostics.duplicate(true)


func is_navigation_segment_clear(start: Vector2, end: Vector2, radius: float, movement_tags: Array = []) -> bool:
	if not _circle_inside_map(start, radius) or not _circle_inside_map(end, radius):
		return false
	if bool(first_segment_hit(start, end, "ShipMovement", radius).get("hit", false)):
		return false
	var fractions: Array[float] = [0.0, 1.0]
	for region in _regions_in_bounds(start, end):
		var polygon: PackedVector2Array = region.get("_polygon", PackedVector2Array())
		for index in range(polygon.size()):
			var fraction := _segment_intersection_fraction(start, end, polygon[index], polygon[(index + 1) % polygon.size()])
			if fraction >= 0.0:
				fractions.append(fraction)
	fractions.sort()
	var samples: Array[float] = []
	for fraction in fractions:
		if samples.is_empty() or absf(float(samples[-1]) - fraction) > EPSILON:
			samples.append(fraction)
	if not _movement_allowed_at(start, movement_tags) or not _movement_allowed_at(end, movement_tags):
		return false
	for sample_index in range(samples.size() - 1):
		var midpoint := (samples[sample_index] + samples[sample_index + 1]) * 0.5
		if not _movement_allowed_at(start.lerp(end, midpoint), movement_tags):
			return false
	return true


func can_occupy_circle(center: Vector2, radius: float, movement_tags: Array = []) -> bool:
	if not _circle_inside_map(center, radius):
		return false
	for obstacle in _obstacles_in_bounds(center, center, maxf(0.0, radius)):
		if "ShipMovement" not in obstacle.get("block_mask", []):
			continue
		var polygon: PackedVector2Array = obstacle.get("_polygon", PackedVector2Array())
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
	for region_index in region_cells.get(_cell_for(position), []):
		var region: Dictionary = regions[int(region_index)]
		if _point_in_polygon(position, region.get("_polygon", PackedVector2Array())):
			var copy := region.duplicate(false)
			copy.erase("_polygon")
			result.append(copy)
	return result


func top_region_at(position: Vector2) -> Dictionary:
	var region := _top_region_internal(position)
	if region.is_empty(): return {}
	var copy := region.duplicate(false)
	copy.erase("_polygon")
	return copy


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
	region_cells.clear()
	for obstacle_index in range(obstacles.size()):
		var polygon: PackedVector2Array = obstacles[obstacle_index].get("_polygon", PackedVector2Array())
		if polygon.is_empty(): continue
		var bounds := _polygon_bounds(polygon)
		var min_cell := _cell_for(bounds.position)
		var max_cell := _cell_for(bounds.position + bounds.size)
		for cell_y in range(min_cell.y, max_cell.y + 1):
			for cell_x in range(min_cell.x, max_cell.x + 1):
				var cell := Vector2i(cell_x, cell_y)
				if not _polygon_intersects_cell(polygon, cell): continue
				if not obstacle_cells.has(cell): obstacle_cells[cell] = []
				obstacle_cells[cell].append(obstacle_index)
	for region_index in range(regions.size()):
		var polygon: PackedVector2Array = regions[region_index].get("_polygon", PackedVector2Array())
		if polygon.is_empty(): continue
		var bounds := _polygon_bounds(polygon)
		var min_cell := _cell_for(bounds.position)
		var max_cell := _cell_for(bounds.position + bounds.size)
		for cell_y in range(min_cell.y, max_cell.y + 1):
			for cell_x in range(min_cell.x, max_cell.x + 1):
				var cell := Vector2i(cell_x, cell_y)
				if not _polygon_intersects_cell(polygon, cell): continue
				if not region_cells.has(cell): region_cells[cell] = []
				region_cells[cell].append(region_index)


func _polygon_intersects_cell(polygon: PackedVector2Array, cell: Vector2i) -> bool:
	var minimum := Vector2(cell) * SPATIAL_CELL_SIZE
	var maximum := minimum + Vector2.ONE * SPATIAL_CELL_SIZE
	for point in polygon:
		if point.x >= minimum.x - EPSILON and point.x <= maximum.x + EPSILON and point.y >= minimum.y - EPSILON and point.y <= maximum.y + EPSILON:
			return true
	var corners := PackedVector2Array([minimum, Vector2(maximum.x, minimum.y), maximum, Vector2(minimum.x, maximum.y)])
	if _point_in_polygon((minimum + maximum) * 0.5, polygon):
		return true
	for index in range(polygon.size()):
		var start := polygon[index]
		var finish := polygon[(index + 1) % polygon.size()]
		for side_index in range(4):
			if _segment_intersection_fraction(start, finish, corners[side_index], corners[(side_index + 1) % 4]) >= 0.0:
				return true
	return false


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


func _regions_in_bounds(start: Vector2, end: Vector2) -> Array:
	if region_cells.is_empty(): return regions
	var minimum := Vector2(minf(start.x, end.x), minf(start.y, end.y))
	var maximum := Vector2(maxf(start.x, end.x), maxf(start.y, end.y))
	var min_cell := _cell_for(minimum)
	var max_cell := _cell_for(maximum)
	var indices := {}
	for cell_y in range(min_cell.y, max_cell.y + 1):
		for cell_x in range(min_cell.x, max_cell.x + 1):
			for region_index in region_cells.get(Vector2i(cell_x, cell_y), []):
				indices[int(region_index)] = true
	var sorted_indices: Array = indices.keys()
	sorted_indices.sort()
	var result: Array = []
	for region_index in sorted_indices: result.append(regions[int(region_index)])
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


func _circle_inside_map(center: Vector2, radius: float) -> bool:
	return (
		center.x - radius >= 0.0
		and center.y - radius >= 0.0
		and center.x + radius <= map_size.x
		and center.y + radius <= map_size.y
	)


func _movement_allowed_at(position: Vector2, movement_tags: Array) -> bool:
	var top_region := _top_region_internal(position)
	if top_region.is_empty():
		return true
	match str(top_region.get("region_type", "DeepWater")):
		"ShallowWater": return "ShallowDraft" in movement_tags
		"ReefOrSandbar": return "ReefCapable" in movement_tags
		_: return true


func _top_region_internal(position: Vector2) -> Dictionary:
	for region_index in region_cells.get(_cell_for(position), []):
		var region: Dictionary = regions[int(region_index)]
		if _point_in_polygon(position, region.get("_polygon", PackedVector2Array())):
			return region
	return {}


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


func _first_illegal_region_fraction(start: Vector2, end: Vector2, movement_tags: Array) -> float:
	if not _segment_may_enter_illegal_region(start, end, movement_tags):
		return -1.0
	if not _movement_allowed_at(start, movement_tags):
		return 0.0
	var distance := start.distance_to(end)
	if distance <= EPSILON:
		return -1.0
	var steps := maxi(1, ceili(distance / 4.0))
	var previous_fraction := 0.0
	for index in range(1, steps + 1):
		var fraction := float(index) / float(steps)
		if _movement_allowed_at(start.lerp(end, fraction), movement_tags):
			previous_fraction = fraction
			continue
		var low := previous_fraction
		var high := fraction
		for _iteration in range(16):
			var middle := (low + high) * 0.5
			if _movement_allowed_at(start.lerp(end, middle), movement_tags): low = middle
			else: high = middle
		return high
	return -1.0


func _segment_may_enter_illegal_region(start: Vector2, end: Vector2, movement_tags: Array) -> bool:
	var permits_shallow := "ShallowDraft" in movement_tags
	var permits_reef := "ReefCapable" in movement_tags
	var min_cell := _cell_for(Vector2(minf(start.x, end.x), minf(start.y, end.y)))
	var max_cell := _cell_for(Vector2(maxf(start.x, end.x), maxf(start.y, end.y)))
	for cell_y in range(min_cell.y, max_cell.y + 1):
		for cell_x in range(min_cell.x, max_cell.x + 1):
			for region_index in region_cells.get(Vector2i(cell_x, cell_y), []):
				var region_type := str(regions[int(region_index)].get("region_type", "DeepWater"))
				if (region_type == "ShallowWater" and not permits_shallow) or (region_type == "ReefOrSandbar" and not permits_reef):
					return true
	return false


func _first_map_boundary_hit(start: Vector2, end: Vector2, radius: float) -> Dictionary:
	var displacement := end - start
	var distance := displacement.length()
	var minimum := Vector2(radius, radius)
	var maximum := map_size - Vector2(radius, radius)
	if map_size.x <= radius * 2.0 or map_size.y <= radius * 2.0:
		return {"hit":true, "obstacle_id":"map_boundary.invalid", "position":start, "normal":Vector2.ZERO, "fraction":0.0, "distance":0.0, "block_mask":"ShipMovement"}
	if start.x < minimum.x - EPSILON:
		return {"hit":true, "obstacle_id":"map_boundary.left", "position":start, "normal":Vector2.RIGHT, "fraction":0.0, "distance":0.0, "block_mask":"ShipMovement"}
	if start.x > maximum.x + EPSILON:
		return {"hit":true, "obstacle_id":"map_boundary.right", "position":start, "normal":Vector2.LEFT, "fraction":0.0, "distance":0.0, "block_mask":"ShipMovement"}
	if start.y < minimum.y - EPSILON:
		return {"hit":true, "obstacle_id":"map_boundary.top", "position":start, "normal":Vector2.DOWN, "fraction":0.0, "distance":0.0, "block_mask":"ShipMovement"}
	if start.y > maximum.y + EPSILON:
		return {"hit":true, "obstacle_id":"map_boundary.bottom", "position":start, "normal":Vector2.UP, "fraction":0.0, "distance":0.0, "block_mask":"ShipMovement"}
	var candidates: Array = []
	if displacement.x < -EPSILON:
		candidates.append({"fraction":(minimum.x - start.x) / displacement.x, "id":"map_boundary.left", "normal":Vector2.RIGHT})
	elif displacement.x > EPSILON:
		candidates.append({"fraction":(maximum.x - start.x) / displacement.x, "id":"map_boundary.right", "normal":Vector2.LEFT})
	if displacement.y < -EPSILON:
		candidates.append({"fraction":(minimum.y - start.y) / displacement.y, "id":"map_boundary.top", "normal":Vector2.DOWN})
	elif displacement.y > EPSILON:
		candidates.append({"fraction":(maximum.y - start.y) / displacement.y, "id":"map_boundary.bottom", "normal":Vector2.UP})
	candidates.sort_custom(func(a, b):
		return float(a.get("fraction", INF)) < float(b.get("fraction", INF)) if not is_equal_approx(float(a.get("fraction", INF)), float(b.get("fraction", INF))) else str(a.get("id", "")) < str(b.get("id", "")))
	for candidate in candidates:
		var fraction := float(candidate.get("fraction", INF))
		if fraction < -EPSILON or fraction > 1.0 + EPSILON:
			continue
		var position := start + displacement * clampf(fraction, 0.0, 1.0)
		if position.x < minimum.x - EPSILON or position.x > maximum.x + EPSILON or position.y < minimum.y - EPSILON or position.y > maximum.y + EPSILON:
			continue
		# Reaching the boundary while still inside is legal. It becomes a hit only
		# when the requested endpoint continues outside the safe center rectangle.
		if end.x >= minimum.x - EPSILON and end.x <= maximum.x + EPSILON and end.y >= minimum.y - EPSILON and end.y <= maximum.y + EPSILON:
			continue
		var resolved_fraction := clampf(fraction, 0.0, 1.0)
		return {
			"hit":true, "obstacle_id":candidate.get("id", "map_boundary"),
			"position":position, "normal":candidate.get("normal", Vector2.ZERO),
			"fraction":resolved_fraction, "distance":distance * resolved_fraction,
			"block_mask":"ShipMovement",
		}
	return _miss(end, "ShipMovement", distance)


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
	var fraction_epsilon := EPSILON / maxf(displacement.length(), EPSILON)
	if length > EPSILON:
		var tangent := edge / length
		var normal := Vector2(-tangent.y, tangent.x)
		var normal_velocity := displacement.dot(normal)
		if absf(normal_velocity) > EPSILON:
			for raw_side in [-radius, radius]:
				var side := float(raw_side)
				var fraction: float = (side - (start - a).dot(normal)) / normal_velocity
				if fraction < -fraction_epsilon or fraction > 1.0 + fraction_epsilon:
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
	var fraction_epsilon := EPSILON / maxf(displacement.length(), EPSILON)
	for fraction in [(-b - root) / (2.0 * a), (-b + root) / (2.0 * a)]:
		if fraction >= -fraction_epsilon and fraction <= 1.0 + fraction_epsilon:
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
	var t_epsilon := EPSILON / maxf(r.length(), EPSILON)
	var u_epsilon := EPSILON / maxf(s.length(), EPSILON)
	return clampf(t, 0.0, 1.0) if t >= -t_epsilon and t <= 1.0 + t_epsilon and u >= -u_epsilon and u <= 1.0 + u_epsilon else -1.0


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
