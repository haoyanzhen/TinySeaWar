extends Node2D

var terrain_map: Dictionary = {}
var contexts: Dictionary = {}
var facilities: Dictionary = {}
var contacts: Dictionary = {}
var selected_unit_id := ""
var recent_hits: Array = []
var spatial_cells: Dictionary = {}


func configure(definition: Dictionary, domain_spatial_cells: Dictionary = {}) -> void:
	terrain_map = definition.duplicate(true)
	spatial_cells = domain_spatial_cells.duplicate(true)
	queue_redraw()


func sync_runtime(unit_contexts: Dictionary, facility_states: Dictionary, selected_id: String, contact_states: Dictionary = {}) -> void:
	contexts = unit_contexts.duplicate(true)
	facilities = facility_states.duplicate(true)
	selected_unit_id = selected_id
	contacts = contact_states.duplicate(true)
	queue_redraw()


func record_events(events: Array) -> void:
	for event in events:
		if str(event.get("event_type", "")) not in ["UnitTerrainCollision", "ProjectileBlockedByTerrain", "ShellBlockedByTerrain"]:
			continue
		recent_hits.push_front(event.duplicate(true))
	if recent_hits.size() > 16:
		recent_hits.resize(16)
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var map_size := _vector2(terrain_map.get("map_size", [0.0, 0.0]))
	for cell in spatial_cells:
		var cell_rect := Rect2(Vector2(cell.x, cell.y) * 256.0, Vector2.ONE * 256.0)
		draw_rect(cell_rect, Color(0.35, 0.78, 0.82, 0.055), true)
		draw_rect(cell_rect, Color(0.35, 0.78, 0.82, 0.24), false, 1.0)
		draw_string(ThemeDB.fallback_font, cell_rect.position + Vector2(8.0, 18.0), "%d" % spatial_cells[cell].size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.58, 0.9, 0.92, 0.72))
	for obstacle in terrain_map.get("obstacles", []):
		var polygon := _polygon(obstacle.get("polygon", []))
		for index in range(polygon.size()):
			var a := polygon[index]
			var b := polygon[(index + 1) % polygon.size()]
			draw_line(a, b, Color(1.0, 0.35, 0.3, 0.9), 2.0)
			if index % 8 == 0:
				var midpoint := a.lerp(b, 0.5)
				var edge := (b - a).normalized()
				draw_line(midpoint, midpoint + Vector2(-edge.y, edge.x) * 18.0, Color(1.0, 0.8, 0.28, 0.85), 2.0)
	for hit in recent_hits:
		var position: Vector2 = hit.get("position", Vector2.ZERO)
		var normal: Vector2 = hit.get("normal", Vector2.ZERO)
		draw_circle(position, 8.0, Color(1.0, 0.78, 0.18, 0.9))
		draw_line(position, position + normal * 42.0, Color(1.0, 0.95, 0.5, 0.95), 3.0)
	for contact in contacts.values():
		if contact.get("primary_contact_type", "") != "Radar": continue
		var contact_position: Vector2 = contact.get("last_known_position", Vector2.ZERO)
		draw_circle(contact_position, 16.0, Color(0.25, 0.9, 1.0, 0.22))
		draw_arc(contact_position, 20.0, 0.0, TAU, 20, Color(0.35, 0.9, 1.0, 0.9), 2.0)
		draw_string(ThemeDB.fallback_font, contact_position + Vector2(24.0, -8.0), "Radar | %s" % contact.get("contact_accuracy", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.95, 1.0))
	if contexts.has(selected_unit_id):
		var context: Dictionary = contexts[selected_unit_id]
		var unit_position: Vector2 = context.get("position", Vector2.ZERO)
		var current: Vector2 = context.get("current_vector", Vector2.ZERO)
		if current.length_squared() > 0.01:
			draw_line(unit_position, unit_position + current * 8.0, Color(0.35, 1.0, 0.9, 0.9), 4.0)
		var context_y := 0.0
		for source in context.get("effect_sources", []):
			draw_string(ThemeDB.fallback_font, unit_position + Vector2(30.0, -26.0 + context_y), "%s  %.2f" % [source.get("effect_id", ""), source.get("intensity", 0.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
			context_y += 17.0
		var water_regions: Array = context.get("water_regions", [])
		var water_type := str(water_regions[0].get("region_type", "DeepWater")) if not water_regions.is_empty() else "DeepWater"
		draw_string(ThemeDB.fallback_font, unit_position + Vector2(30.0, -44.0), "water=%s current=%.1f sea=%d optical=%.2f air=%s tide=%s" % [water_type, current.length(), context.get("sea_state", 0), context.get("optical_visibility_multiplier", 1.0), context.get("aviation_condition", "Normal"), context.get("tide_controls_access", false)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.9, 0.55))
	for facility in facilities.values():
		var source_position: Vector2 = facility.get("position", Vector2.ZERO)
		for dependency_id in facility.get("requires_all_active", []):
			if facilities.has(dependency_id):
				var dependency_position: Vector2 = facilities[dependency_id].get("position", Vector2.ZERO)
				draw_line(source_position, dependency_position, Color(1.0, 0.78, 0.28, 0.55), 2.0)
				draw_circle(source_position.lerp(dependency_position, 0.5), 4.0, Color(1.0, 0.88, 0.48, 0.85))
		for dependency_id in facility.get("requires_any_active", []):
			if facilities.has(dependency_id):
				var dependency_position: Vector2 = facilities[dependency_id].get("position", Vector2.ZERO)
				draw_dashed_line(source_position, dependency_position, Color(0.45, 0.9, 1.0, 0.55), 2.0, 10.0)
	for facility in facilities.values():
		var facility_position: Vector2 = facility.get("position", Vector2.ZERO)
		var facility_label := "%s | %s | %s | cd %.1f" % [facility.get("display_name", facility.get("facility_id", "")), facility.get("faction_id", ""), facility.get("operation_state", ""), facility.get("cooldown_remaining", 0.0)]
		draw_string(ThemeDB.fallback_font, facility_position + Vector2(22.0, -18.0), facility_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.84, 0.45))
		var interaction_label := str(facility.get("interaction_state", "Idle"))
		var dependency_names := PackedStringArray()
		for dependency_id in facility.get("requires_all_active", []):
			dependency_names.append(str(dependency_id))
		for dependency_id in facility.get("requires_any_active", []):
			dependency_names.append("any:%s" % dependency_id)
		var dependencies_label := "none" if dependency_names.is_empty() else ",".join(dependency_names)
		var detail_label := "int=%s sup=%.1f svc=%d deps=%s" % [interaction_label, facility.get("suppression_remaining", 0.0), facility.get("service_queue", []).size(), dependencies_label]
		draw_string(ThemeDB.fallback_font, facility_position + Vector2(22.0, -2.0), detail_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.82, 0.94, 1.0))
	var label_position := Vector2(24, 42)
	draw_string(ThemeDB.fallback_font, label_position, "Terrain debug: %d obstacles | %d index cells | %d facilities | %d hits" % [terrain_map.get("obstacles", []).size(), spatial_cells.size(), facilities.size(), recent_hits.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.95, 0.65))


func _polygon(raw: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in raw:
		result.append(_vector2(point))
	return result


func _vector2(value: Variant) -> Vector2:
	return value if value is Vector2 else Vector2(float(value[0]), float(value[1]))
