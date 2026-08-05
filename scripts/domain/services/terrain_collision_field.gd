extends RefCounted

const EPSILON := 0.000001

var terrain_definition_id := ""
var navigation_revision := 0
var map_size := Vector2.ZERO
var cell_size := 0.0
var grid_size := Vector2i.ZERO
var occupancy := PackedByteArray()
var distances := PackedByteArray()
var restrictions := PackedByteArray()
var last_minimum_clearance := 0.0
var last_cells_visited := 0
var last_restriction_mask := 0


func configure(metadata: Dictionary, occupancy_bytes: PackedByteArray, distance_bytes: PackedByteArray, restriction_bytes: PackedByteArray) -> bool:
	terrain_definition_id = str(metadata.get("terrain_definition_id", ""))
	navigation_revision = int(metadata.get("navigation_revision", 0))
	map_size = metadata.get("map_size", Vector2.ZERO)
	cell_size = float(metadata.get("cell_size", 0.0))
	grid_size = metadata.get("grid_size", Vector2i.ZERO)
	occupancy = occupancy_bytes
	distances = distance_bytes
	restrictions = restriction_bytes
	return (
		not terrain_definition_id.is_empty()
		and cell_size > 0.0
		and grid_size.x > 0
		and grid_size.y > 0
		and occupancy.size() == int(ceili(float(grid_size.x * grid_size.y) / 8.0))
		and distances.size() == grid_size.x * grid_size.y * 2
		and restrictions.size() == grid_size.x * grid_size.y
	)


func is_configured() -> bool:
	return cell_size > 0.0 and grid_size.x > 0 and grid_size.y > 0 and not distances.is_empty()


func distance_lower_bound_at(position: Vector2) -> float:
	if not is_configured():
		return 0.0
	return float(_distance_at_cell(_cell_for(position)))


func occupied_at(position: Vector2) -> bool:
	if not is_configured():
		return false
	var cell := _cell_for(position)
	if not _inside_grid(cell):
		return true
	var index := cell.y * grid_size.x + cell.x
	return bool(occupancy[index >> 3] & (1 << (index & 7)))


func query_segment(start: Vector2, finish: Vector2, required_clearance: float) -> Dictionary:
	if not is_configured():
		return {"status":"FieldUnavailable", "minimum_clearance":0.0, "field_cells_visited":0}
	var definitely_clear := segment_definitely_clear(start, finish, required_clearance)
	return {
		"status":"DefinitelyClear" if definitely_clear else "NeedsExactCheck",
		"minimum_clearance":last_minimum_clearance,
		"field_cells_visited":last_cells_visited,
		"restriction_mask":last_restriction_mask,
	}


func segment_definitely_clear(start: Vector2, finish: Vector2, required_clearance: float) -> bool:
	last_minimum_clearance = 0.0
	last_cells_visited = 0
	last_restriction_mask = 0
	if not is_configured():
		return false
	var start_cell := _cell_for(start)
	var end_cell := _cell_for(finish)
	if not _inside_grid(start_cell) or not _inside_grid(end_cell):
		return false
	var minimum_clearance := float(_distance_at_cell(start_cell))
	var restriction_mask := _restriction_at_cell(start_cell)
	var cells_visited := 1
	if start_cell != end_cell:
		var grid_start := start / cell_size
		var grid_finish := finish / cell_size
		var current := start_cell
		var step_x := 1 if grid_finish.x > grid_start.x else (-1 if grid_finish.x < grid_start.x else 0)
		var step_y := 1 if grid_finish.y > grid_start.y else (-1 if grid_finish.y < grid_start.y else 0)
		var dx := grid_finish.x - grid_start.x
		var dy := grid_finish.y - grid_start.y
		var t_delta_x := absf(1.0 / dx) if step_x != 0 else INF
		var t_delta_y := absf(1.0 / dy) if step_y != 0 else INF
		var next_x := float(current.x + 1) if step_x > 0 else float(current.x)
		var next_y := float(current.y + 1) if step_y > 0 else float(current.y)
		var t_max_x := (next_x - grid_start.x) / dx if step_x != 0 else INF
		var t_max_y := (next_y - grid_start.y) / dy if step_y != 0 else INF
		while current != end_cell:
			var effective_t_max_x := t_max_x if current.x != end_cell.x else INF
			var effective_t_max_y := t_max_y if current.y != end_cell.y else INF
			if effective_t_max_x < effective_t_max_y - EPSILON:
				current.x += step_x
				t_max_x += t_delta_x
			elif effective_t_max_y < effective_t_max_x - EPSILON:
				current.y += step_y
				t_max_y += t_delta_y
			else:
				var side_x := Vector2i(current.x + step_x, current.y)
				var side_y := Vector2i(current.x, current.y + step_y)
				if _inside_grid(side_x):
					minimum_clearance = minf(minimum_clearance, float(_distance_at_cell(side_x)))
					restriction_mask |= _restriction_at_cell(side_x)
					cells_visited += 1
				if _inside_grid(side_y):
					minimum_clearance = minf(minimum_clearance, float(_distance_at_cell(side_y)))
					restriction_mask |= _restriction_at_cell(side_y)
					cells_visited += 1
				current.x += step_x
				current.y += step_y
				t_max_x += t_delta_x
				t_max_y += t_delta_y
			if _inside_grid(current):
				minimum_clearance = minf(minimum_clearance, float(_distance_at_cell(current)))
				restriction_mask |= _restriction_at_cell(current)
				cells_visited += 1
	last_minimum_clearance = 0.0 if is_inf(minimum_clearance) else minimum_clearance
	last_cells_visited = cells_visited
	last_restriction_mask = restriction_mask
	return minimum_clearance > required_clearance


func query_trajectory_samples(samples: Array, required_clearance: float) -> Dictionary:
	var segment_count := maxi(0, samples.size() - 1)
	var definitely_clear := PackedByteArray()
	definitely_clear.resize(segment_count)
	var minimum_by_segment := PackedFloat32Array()
	minimum_by_segment.resize(segment_count)
	var cells_by_segment := PackedInt32Array()
	cells_by_segment.resize(segment_count)
	var restriction_by_segment := PackedByteArray()
	restriction_by_segment.resize(segment_count)
	var previous_cached_cell := Vector2i(-2147483648, -2147483648)
	var previous_cached_distance := 0.0
	var previous_cached_restriction := 0
	for index in range(segment_count):
		var start: Vector2 = samples[index].get("position", Vector2.ZERO)
		var finish: Vector2 = samples[index + 1].get("position", start)
		if start.is_equal_approx(finish):
			var stationary_cell := _cell_for(start)
			var stationary_clearance := previous_cached_distance if stationary_cell == previous_cached_cell else float(_distance_at_cell(stationary_cell))
			var stationary_restriction := previous_cached_restriction if stationary_cell == previous_cached_cell else _restriction_at_cell(stationary_cell)
			minimum_by_segment[index] = stationary_clearance
			cells_by_segment[index] = 0 if stationary_cell == previous_cached_cell else 1
			definitely_clear[index] = 1 if _inside_grid(stationary_cell) and stationary_clearance > required_clearance else 0
			restriction_by_segment[index] = stationary_restriction
			previous_cached_cell = stationary_cell
			previous_cached_distance = stationary_clearance
			previous_cached_restriction = stationary_restriction
			continue
		var start_cell := _cell_for(start)
		var end_cell := _cell_for(finish)
		if not _inside_grid(start_cell) or not _inside_grid(end_cell):
			previous_cached_cell = end_cell
			previous_cached_distance = 0.0
			previous_cached_restriction = 0
			continue
		var start_clearance := previous_cached_distance if start_cell == previous_cached_cell else float(_distance_at_cell(start_cell))
		var start_restriction := previous_cached_restriction if start_cell == previous_cached_cell else _restriction_at_cell(start_cell)
		if start_cell == end_cell:
			previous_cached_cell = end_cell
			previous_cached_distance = start_clearance
			previous_cached_restriction = start_restriction
			minimum_by_segment[index] = start_clearance
			cells_by_segment[index] = 1
			restriction_by_segment[index] = start_restriction
			definitely_clear[index] = 1 if start_clearance > required_clearance else 0
			continue
		var cell_delta := end_cell - start_cell
		if absi(cell_delta.x) <= 1 and absi(cell_delta.y) <= 1:
			var end_clearance := float(_distance_at_cell(end_cell))
			var minimum_clearance := minf(start_clearance, end_clearance)
			var restriction_mask := start_restriction | _restriction_at_cell(end_cell)
			var cells_visited := 2
			if cell_delta.x != 0 and cell_delta.y != 0:
				var boundary_x := float(start_cell.x + 1) * cell_size if cell_delta.x > 0 else float(start_cell.x) * cell_size
				var boundary_y := float(start_cell.y + 1) * cell_size if cell_delta.y > 0 else float(start_cell.y) * cell_size
				var fraction_x := (boundary_x - start.x) / (finish.x - start.x)
				var fraction_y := (boundary_y - start.y) / (finish.y - start.y)
				if fraction_x <= fraction_y + EPSILON:
					var side_x := Vector2i(end_cell.x, start_cell.y)
					minimum_clearance = minf(minimum_clearance, float(_distance_at_cell(side_x)))
					restriction_mask |= _restriction_at_cell(side_x)
					cells_visited += 1
				if fraction_y <= fraction_x + EPSILON:
					var side_y := Vector2i(start_cell.x, end_cell.y)
					minimum_clearance = minf(minimum_clearance, float(_distance_at_cell(side_y)))
					restriction_mask |= _restriction_at_cell(side_y)
					cells_visited += 1
			minimum_by_segment[index] = minimum_clearance
			cells_by_segment[index] = cells_visited
			restriction_by_segment[index] = restriction_mask
			definitely_clear[index] = 1 if minimum_clearance > required_clearance else 0
			previous_cached_cell = end_cell
			previous_cached_distance = end_clearance
			previous_cached_restriction = _restriction_at_cell(end_cell)
			continue
		definitely_clear[index] = 1 if segment_definitely_clear(start, finish, required_clearance) else 0
		minimum_by_segment[index] = last_minimum_clearance
		cells_by_segment[index] = last_cells_visited
		restriction_by_segment[index] = last_restriction_mask
		previous_cached_cell = end_cell
		previous_cached_distance = float(_distance_at_cell(end_cell)) if _inside_grid(end_cell) else 0.0
		previous_cached_restriction = _restriction_at_cell(end_cell) if _inside_grid(end_cell) else 0
	return {"definitely_clear":definitely_clear, "minimum_by_segment":minimum_by_segment, "cells_by_segment":cells_by_segment, "restriction_by_segment":restriction_by_segment}


func _supercover_cells(start: Vector2, finish: Vector2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var seen := {}
	var grid_start := start / cell_size
	var grid_finish := finish / cell_size
	var current := Vector2i(floori(grid_start.x), floori(grid_start.y))
	var target := Vector2i(floori(grid_finish.x), floori(grid_finish.y))
	var step_x := 1 if grid_finish.x > grid_start.x else (-1 if grid_finish.x < grid_start.x else 0)
	var step_y := 1 if grid_finish.y > grid_start.y else (-1 if grid_finish.y < grid_start.y else 0)
	var dx := grid_finish.x - grid_start.x
	var dy := grid_finish.y - grid_start.y
	var t_delta_x := absf(1.0 / dx) if step_x != 0 else INF
	var t_delta_y := absf(1.0 / dy) if step_y != 0 else INF
	var next_x := float(current.x + 1) if step_x > 0 else float(current.x)
	var next_y := float(current.y + 1) if step_y > 0 else float(current.y)
	var t_max_x := (next_x - grid_start.x) / dx if step_x != 0 else INF
	var t_max_y := (next_y - grid_start.y) / dy if step_y != 0 else INF
	while true:
		_append_cell(result, seen, current)
		if current == target:
			break
		var effective_t_max_x := t_max_x if current.x != target.x else INF
		var effective_t_max_y := t_max_y if current.y != target.y else INF
		if effective_t_max_x < effective_t_max_y - EPSILON:
			current.x += step_x
			t_max_x += t_delta_x
		elif effective_t_max_y < effective_t_max_x - EPSILON:
			current.y += step_y
			t_max_y += t_delta_y
		else:
			_append_cell(result, seen, Vector2i(current.x + step_x, current.y))
			_append_cell(result, seen, Vector2i(current.x, current.y + step_y))
			current.x += step_x
			current.y += step_y
			t_max_x += t_delta_x
			t_max_y += t_delta_y
	return result


func _append_cell(result: Array[Vector2i], seen: Dictionary, cell: Vector2i) -> void:
	if not _inside_grid(cell) or seen.has(cell):
		return
	seen[cell] = true
	result.append(cell)


func _cell_for(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / cell_size), floori(position.y / cell_size))


func _inside_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func _distance_at_cell(cell: Vector2i) -> int:
	if not _inside_grid(cell):
		return 0
	var offset := (cell.y * grid_size.x + cell.x) * 2
	return int(distances[offset]) | (int(distances[offset + 1]) << 8)


func _restriction_at_cell(cell: Vector2i) -> int:
	if not _inside_grid(cell):
		return 0
	return int(restrictions[cell.y * grid_size.x + cell.x])
