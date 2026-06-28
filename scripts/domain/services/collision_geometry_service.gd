extends RefCounted


static func half_extents(definition: Dictionary) -> Vector2:
	var value = definition.get("collision_half_extents", [])
	if value is Vector2 and value.x > 0.0 and value.y > 0.0:
		return value
	if value is Array and value.size() == 2 and float(value[0]) > 0.0 and float(value[1]) > 0.0:
		return Vector2(float(value[0]), float(value[1]))
	var radius := maxf(1.0, float(definition.get("collision_radius", 20.0)))
	return Vector2(radius, radius)


static func point_in_expanded_ellipse(point: Vector2, center: Vector2, heading: float, extents: Vector2, padding: float = 0.0) -> bool:
	return normalized_distance(point, center, heading, extents, padding) <= 1.0


static func normalized_distance(point: Vector2, center: Vector2, heading: float, extents: Vector2, padding: float = 0.0) -> float:
	var local := (point - center).rotated(-heading)
	var expanded := Vector2(maxf(0.001, extents.x + padding), maxf(0.001, extents.y + padding))
	return sqrt((local.x * local.x) / (expanded.x * expanded.x) + (local.y * local.y) / (expanded.y * expanded.y))


static func segment_expanded_ellipse_fraction(start: Vector2, end: Vector2, center: Vector2, heading: float, extents: Vector2, padding: float = 0.0) -> float:
	var expanded := Vector2(maxf(0.001, extents.x + padding), maxf(0.001, extents.y + padding))
	var local_start := (start - center).rotated(-heading) / expanded
	var local_end := (end - center).rotated(-heading) / expanded
	return _segment_unit_circle_fraction(local_start, local_end)


static func radial_extent(extents: Vector2, heading: float, world_direction: Vector2) -> float:
	if world_direction.length_squared() <= 0.000001:
		return minf(extents.x, extents.y)
	var local_direction := world_direction.normalized().rotated(-heading)
	var denominator := (local_direction.x * local_direction.x) / maxf(0.001, extents.x * extents.x)
	denominator += (local_direction.y * local_direction.y) / maxf(0.001, extents.y * extents.y)
	return 1.0 / sqrt(maxf(0.000001, denominator))


static func separation_distance(first_extents: Vector2, first_heading: float, second_extents: Vector2, second_heading: float, center_direction: Vector2) -> float:
	if center_direction.length_squared() <= 0.000001:
		return minf(first_extents.x, first_extents.y) + minf(second_extents.x, second_extents.y)
	return radial_extent(first_extents, first_heading, center_direction) + radial_extent(second_extents, second_heading, -center_direction)


static func _segment_unit_circle_fraction(start: Vector2, end: Vector2) -> float:
	var displacement := end - start
	var a := displacement.length_squared()
	if a <= 0.000001:
		return 0.0 if start.length_squared() <= 1.0 else -1.0
	var c := start.length_squared() - 1.0
	if c <= 0.0:
		return 0.0
	var b := 2.0 * start.dot(displacement)
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var fraction := (-b - sqrt(discriminant)) / (2.0 * a)
	return fraction if fraction >= 0.0 and fraction <= 1.0 else -1.0
