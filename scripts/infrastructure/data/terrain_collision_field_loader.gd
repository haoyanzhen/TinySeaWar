extends RefCounted

const TerrainCollisionField = preload("res://scripts/domain/services/terrain_collision_field.gd")

const MAGIC := "TSCF"
const SCHEMA_VERSION := 2
const ALGORITHM_VERSION := 2
const HEADER_SIZE := 110


func load_field(definition: Dictionary, terrain_definition: Dictionary) -> Dictionary:
	if definition.is_empty():
		return _failure("MISSING_COLLISION_FIELD_DEFINITION")
	var path := str(definition.get("path", ""))
	if path.is_empty():
		return _failure("MISSING_COLLISION_FIELD_PATH")
	var raw_file := FileAccess.get_file_as_bytes(path)
	if raw_file.is_empty():
		return _failure("COLLISION_FIELD_UNREADABLE")
	if _sha256(raw_file) != str(definition.get("file_checksum", "")):
		return _failure("COLLISION_FIELD_FILE_CHECKSUM_MISMATCH")
	if raw_file.size() < HEADER_SIZE:
		return _failure("COLLISION_FIELD_TRAILING_OR_TRUNCATED_DATA")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("COLLISION_FIELD_UNREADABLE")
	file.big_endian = false
	if file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return _failure("COLLISION_FIELD_BAD_MAGIC")
	var schema_version := file.get_16()
	var algorithm_version := file.get_16()
	if schema_version != SCHEMA_VERSION or algorithm_version != ALGORITHM_VERSION:
		return _failure("COLLISION_FIELD_UNSUPPORTED_VERSION")
	var grid_width := int(file.get_32())
	var grid_height := int(file.get_32())
	var cell_size := file.get_float()
	var map_size := Vector2(file.get_float(), file.get_float())
	var navigation_revision := int(file.get_32())
	var terrain_id_length := int(file.get_16())
	var source_checksum := file.get_buffer(32).hex_encode()
	var payload_checksum := file.get_buffer(32).hex_encode()
	var occupancy_length := int(file.get_32())
	var distance_length := int(file.get_32())
	var restriction_length := int(file.get_32())
	if terrain_id_length <= 0 or terrain_id_length > 4096 or occupancy_length < 0 or distance_length < 0 or restriction_length < 0:
		return _failure("COLLISION_FIELD_INVALID_LENGTH")
	if grid_width <= 0 or grid_height <= 0 or occupancy_length != int(ceili(float(grid_width * grid_height) / 8.0)) or distance_length != grid_width * grid_height * 2 or restriction_length != grid_width * grid_height:
		return _failure("COLLISION_FIELD_PAYLOAD_SIZE_MISMATCH")
	if HEADER_SIZE + terrain_id_length + occupancy_length + distance_length + restriction_length != raw_file.size():
		return _failure("COLLISION_FIELD_TRAILING_OR_TRUNCATED_DATA")
	var terrain_id := file.get_buffer(terrain_id_length).get_string_from_utf8()
	var occupancy := file.get_buffer(occupancy_length)
	var distances := file.get_buffer(distance_length)
	var restrictions := file.get_buffer(restriction_length)
	if file.get_position() != file.get_length():
		return _failure("COLLISION_FIELD_TRAILING_OR_TRUNCATED_DATA")
	var payload := occupancy.duplicate()
	payload.append_array(distances)
	payload.append_array(restrictions)
	if _sha256(payload) != payload_checksum or payload_checksum != str(definition.get("payload_checksum", "")):
		return _failure("COLLISION_FIELD_PAYLOAD_CHECKSUM_MISMATCH")
	var expected_terrain_id := str(terrain_definition.get("id", ""))
	var expected_map_size := _vector2(terrain_definition.get("map_size", []))
	var expected_source_checksum := source_geometry_checksum(terrain_definition)
	if terrain_id != expected_terrain_id or terrain_id != str(definition.get("terrain_definition_id", "")):
		return _failure("COLLISION_FIELD_TERRAIN_MISMATCH")
	if navigation_revision != int(terrain_definition.get("navigation_revision", 0)) or navigation_revision != int(definition.get("navigation_revision", -1)):
		return _failure("COLLISION_FIELD_REVISION_MISMATCH")
	if not map_size.is_equal_approx(expected_map_size) or not map_size.is_equal_approx(_vector2(definition.get("map_size", []))):
		return _failure("COLLISION_FIELD_MAP_SIZE_MISMATCH")
	if source_checksum != expected_source_checksum or source_checksum != str(definition.get("source_checksum", "")):
		return _failure("COLLISION_FIELD_SOURCE_CHECKSUM_MISMATCH")
	if not is_equal_approx(cell_size, float(definition.get("cell_size", 0.0))):
		return _failure("COLLISION_FIELD_CELL_SIZE_MISMATCH")
	var grid_size := Vector2i(grid_width, grid_height)
	var declared_grid := _vector2i(definition.get("grid_size", []))
	if grid_size != declared_grid:
		return _failure("COLLISION_FIELD_PAYLOAD_SIZE_MISMATCH")
	var field = TerrainCollisionField.new()
	if not field.configure({
		"terrain_definition_id":terrain_id,
		"navigation_revision":navigation_revision,
		"map_size":map_size,
		"cell_size":cell_size,
		"grid_size":grid_size,
	}, occupancy, distances, restrictions):
		return _failure("COLLISION_FIELD_CONFIGURATION_FAILED")
	return {"ok":true, "field":field, "reason_code":"OK"}


func source_geometry_checksum(terrain_definition: Dictionary) -> String:
	var map_size := _vector2(terrain_definition.get("map_size", []))
	var parts: Array[String] = [
		str(terrain_definition.get("id", "")),
		str(int(terrain_definition.get("navigation_revision", 0))),
		"%.3f,%.3f" % [map_size.x, map_size.y],
	]
	var obstacles: Array = []
	for raw_obstacle in terrain_definition.get("obstacles", []):
		if "ShipMovement" in raw_obstacle.get("block_mask", []):
			obstacles.append(raw_obstacle)
	obstacles.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	for raw_obstacle in obstacles:
		var obstacle: Dictionary = raw_obstacle
		parts.append(str(obstacle.get("id", "")))
		var masks: Array = obstacle.get("block_mask", []).duplicate()
		masks.sort()
		var mask_strings: Array[String] = []
		for mask in masks: mask_strings.append(str(mask))
		parts.append(",".join(mask_strings))
		var points: Array[String] = []
		for raw_point in obstacle.get("polygon", []):
			var point := _vector2(raw_point)
			points.append("%.3f,%.3f" % [point.x, point.y])
		parts.append(";".join(points))
	var restricted_regions: Array = terrain_definition.get("regions", []).filter(func(region): return str(region.get("region_type", "")) in ["ShallowWater", "ReefOrSandbar"])
	restricted_regions.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	for raw_region in restricted_regions:
		var region: Dictionary = raw_region
		parts.append(str(region.get("id", "")))
		parts.append(str(region.get("region_type", "")))
		parts.append(str(int(region.get("priority", 0))))
		var points: Array[String] = []
		for raw_point in region.get("polygon", []):
			var point := _vector2(raw_point)
			points.append("%.3f,%.3f" % [point.x, point.y])
		parts.append(";".join(points))
	return _sha256("|".join(parts).to_utf8_buffer())


func _sha256(value: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value)
	return context.finish().hex_encode()


func _vector2(value: Variant) -> Vector2:
	if value is Vector2: return value
	if value is Array and value.size() >= 2: return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _vector2i(value: Variant) -> Vector2i:
	if value is Vector2i: return value
	if value is Array and value.size() >= 2: return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO


func _failure(reason_code: String) -> Dictionary:
	return {"ok":false, "reason_code":reason_code}
