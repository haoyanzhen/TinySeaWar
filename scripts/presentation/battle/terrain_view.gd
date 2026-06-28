extends Node2D

var asset_catalog
var static_root := Node2D.new()
var zone_root := Node2D.new()
var minefield_root := Node2D.new()
var facility_root := Node2D.new()


func _ready() -> void:
	static_root.name = "StaticTerrain"
	zone_root.name = "EnvironmentZones"
	minefield_root.name = "Minefields"
	facility_root.name = "Facilities"
	add_child(static_root)
	add_child(zone_root)
	add_child(minefield_root)
	add_child(facility_root)


func configure(terrain_map: Dictionary, assets) -> void:
	asset_catalog = assets
	_clear(static_root)
	for region in terrain_map.get("regions", []):
		_create_region(region)
	for visual_region in terrain_map.get("visual_regions", []):
		_create_visual_region(visual_region)
	for instance in terrain_map.get("visual_instances", []):
		_create_land_instance(instance)


func sync_dynamic(environment_zones: Array, facilities: Dictionary, minefields: Dictionary = {}, support_effects: Dictionary = {}) -> void:
	_clear(zone_root)
	_clear(minefield_root)
	_clear(facility_root)
	for zone in environment_zones:
		if bool(zone.get("active", false)):
			_create_environment_zone(zone)
	for effect_id in support_effects:
		_create_support_effect(support_effects[effect_id])
	var minefield_ids: Array = minefields.keys()
	minefield_ids.sort()
	for minefield_id in minefield_ids:
		_create_minefield(minefields[minefield_id])
	var facility_ids: Array = facilities.keys()
	facility_ids.sort()
	for facility_id in facility_ids:
		_create_facility(facilities[facility_id])


func _create_region(region: Dictionary) -> void:
	var region_type := str(region.get("region_type", ""))
	var style: Array = {
		"ShallowWater": ["shallow_water_fill", Color(0.66, 1.0, 0.94, 0.34), -4],
		"ReefOrSandbar": ["reef_sandbar_overlay", Color(1.0, 0.92, 0.68, 0.38), -3],
		"NavigationChannel": ["navigation_channel_overlay", Color(0.65, 0.94, 1.0, 0.25), -2],
	}.get(region_type, [])
	if style.is_empty():
		return
	var polygon := _polygon_node(region.get("polygon", []), style[1], str(style[0]), int(style[2]))
	polygon.name = str(region.get("id", "TerrainRegion"))
	static_root.add_child(polygon)


func _create_visual_region(region: Dictionary) -> void:
	var opacity := clampf(float(region.get("opacity", 0.35)), 0.0, 1.0)
	var polygon := _polygon_node(region.get("polygon", []), Color(1.0, 1.0, 1.0, opacity), str(region.get("asset_semantic", "")), int(region.get("z_index", 6)))
	polygon.name = str(region.get("id", "VisualRegion"))
	static_root.add_child(polygon)


func _create_land_instance(instance: Dictionary) -> void:
	var sprite := Sprite2D.new()
	sprite.name = str(instance.get("id", "Land"))
	var semantic := "%s_runtime" % str(instance.get("asset_id", ""))
	var path: String = asset_catalog.environment_asset_path(semantic) if asset_catalog != null else ""
	if path.is_empty():
		path = str(instance.get("texture", ""))
	sprite.texture = _texture(path)
	sprite.position = _vector2(instance.get("position", []))
	sprite.scale = _vector2(instance.get("scale", [1.0, 1.0]))
	sprite.rotation = deg_to_rad(float(instance.get("rotation_degrees", 0.0)))
	sprite.z_index = 10
	static_root.add_child(sprite)


func _create_environment_zone(zone: Dictionary) -> void:
	var effect_id := str(zone.get("effect_id", ""))
	var styles: Array = {
		"environment.effect.sea_fog": [["", Color(0.82, 0.92, 0.91, 0.06), 2], ["sea_fog_mask", Color(0.84, 0.93, 0.92, 0.28), 3], ["sea_fog_edge_mask", Color(0.82, 0.94, 0.93, 0.18), 4], ["sea_fog_detail_mask", Color(0.9, 0.98, 0.96, 0.12), 5]],
		"environment.effect.rain_squall": [["", Color(0.12, 0.23, 0.29, 0.08), 2], ["rain_squall_mask", Color(0.25, 0.39, 0.45, 0.32), 3], ["rain_squall_edge_mask", Color(0.34, 0.48, 0.53, 0.18), 4]],
		"environment.effect.high_sea": [["high_sea_foam_mask", Color(0.75, 0.94, 0.92, 0.16), 3]],
		"environment.effect.lee_water": [["lee_water_mask", Color(0.38, 0.78, 0.78, 0.10), 3]],
		"environment.effect.moonlit_lane": [["moonlit_lane_mask", Color(0.78, 0.89, 0.82, 0.16), 3]],
		"environment.effect.strong_current": [["strong_current_streak_tile", Color(0.43, 0.85, 0.84, 0.18), 3]],
		"environment.effect.tidal_water": [["active_illumination_mask", Color(0.63, 0.81, 0.72, 0.14), 3]],
	}.get(effect_id, [["", Color(0.5, 0.8, 0.8, 0.12), 3]])
	for index in range(styles.size()):
		var style: Array = styles[index]
		var layer_color: Color = style[1]
		layer_color.a *= clampf(float(zone.get("intensity", 1.0)), 0.0, 1.0)
		var polygon := _polygon_node(zone.get("polygon", []), layer_color, str(style[0]), int(style[2]))
		polygon.name = "%s_Layer_%02d" % [zone.get("id", "EnvironmentZone"), index + 1]
		zone_root.add_child(polygon)
	var outline := Line2D.new()
	outline.name = "%s_Boundary" % zone.get("id", "EnvironmentZone")
	outline.points = _polygon(zone.get("polygon", []))
	outline.closed = true
	outline.width = 1.5
	outline.default_color = Color(0.68, 0.9, 0.9, 0.24)
	outline.antialiased = true
	outline.z_index = 6
	zone_root.add_child(outline)


func _create_support_effect(effect: Dictionary) -> void:
	var center: Vector2 = effect.get("position", Vector2.ZERO)
	var radius := float(effect.get("radius", 0.0))
	if radius <= 0.0: return
	var points := PackedVector2Array()
	for index in range(48):
		points.append(center + Vector2.RIGHT.rotated(TAU * float(index) / 48.0) * radius)
	var polygon := Polygon2D.new()
	polygon.name = str(effect.get("effect_id", "SupportEffect"))
	polygon.polygon = points
	polygon.color = Color(0.42, 0.86, 0.88, 0.08) if effect.get("effect_type", "") == "Reconnaissance" else Color(0.48, 0.72, 0.96, 0.1)
	polygon.z_index = 5
	zone_root.add_child(polygon)
	var outline := Line2D.new()
	outline.points = points
	outline.closed = true
	outline.width = 2.0
	outline.default_color = Color(0.62, 0.94, 0.94, 0.42)
	outline.z_index = 6
	zone_root.add_child(outline)


func _create_minefield(minefield: Dictionary) -> void:
	var polygon := _polygon_node(minefield.get("polygon", []), Color(0.95, 0.25, 0.18, 0.16), "", 4)
	polygon.name = str(minefield.get("definition_id", "Minefield"))
	minefield_root.add_child(polygon)
	for index in range(minefield.get("safe_channels", []).size()):
		var channel := _polygon_node(minefield["safe_channels"][index], Color(0.32, 0.96, 0.72, 0.18), "", 5)
		channel.name = "%s_SafeChannel_%02d" % [polygon.name, index + 1]
		minefield_root.add_child(channel)


func _create_facility(facility: Dictionary) -> void:
	var sprite := Sprite2D.new()
	sprite.name = str(facility.get("facility_id", "Facility"))
	var state := "destroyed" if str(facility.get("life_state", "Alive")) == "Destroyed" else "base"
	var semantic := "facility.%s.%s" % [facility.get("asset_semantic", ""), state]
	var path: String = asset_catalog.environment_asset_path(semantic) if asset_catalog != null else ""
	sprite.texture = _texture(path)
	sprite.position = facility.get("position", Vector2.ZERO)
	sprite.rotation = deg_to_rad(float(facility.get("heading", 0.0)))
	sprite.scale = Vector2.ONE * 0.34
	sprite.modulate = _facility_modulate(str(facility.get("faction_id", "neutral")), str(facility.get("operation_state", "Dormant")))
	sprite.z_index = 20
	facility_root.add_child(sprite)
	var overlay_semantic: String = {
		"Active": "facility.state.active",
		"Suppressed": "facility.state.suppressed",
		"Dormant": "facility.state.offline",
	}.get(str(facility.get("operation_state", "Dormant")), "")
	if overlay_semantic.is_empty():
		return
	var overlay := Sprite2D.new()
	overlay.texture = _texture(asset_catalog.environment_asset_path(overlay_semantic))
	overlay.scale = Vector2.ONE * 0.7
	overlay.z_index = 21
	sprite.add_child(overlay)


func _polygon_node(raw_polygon: Array, color: Color, semantic: String, z: int) -> Polygon2D:
	var node := Polygon2D.new()
	var polygon := PackedVector2Array()
	var uv := PackedVector2Array()
	for raw_point in raw_polygon:
		var point := _vector2(raw_point)
		polygon.append(point)
		uv.append(point * 0.32)
	node.polygon = polygon
	node.uv = uv
	node.color = color
	node.z_index = z
	node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if not semantic.is_empty() and asset_catalog != null:
		node.texture = _texture(asset_catalog.environment_asset_path(semantic))
	return node


func _polygon(raw_polygon: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for raw_point in raw_polygon: result.append(_vector2(raw_point))
	return result


func _facility_modulate(faction_id: String, operation_state: String) -> Color:
	var color := Color.WHITE
	if faction_id == "player": color = Color(0.78, 1.0, 0.94)
	elif faction_id == "enemy": color = Color(1.0, 0.82, 0.78)
	if operation_state == "Dormant": color *= Color(0.72, 0.76, 0.76, 0.85)
	elif operation_state == "Suppressed": color *= Color(0.86, 0.7, 0.48, 0.9)
	return color


func _texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var resource = load(path)
	return resource if resource is Texture2D else null


func _clear(node: Node) -> void:
	for child in node.get_children():
		child.free()


func _vector2(value: Variant) -> Vector2:
	return value if value is Vector2 else Vector2(float(value[0]), float(value[1]))
