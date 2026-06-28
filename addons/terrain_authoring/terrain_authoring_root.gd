@tool
extends Node2D

@export_enum("Template", "Map") var authoring_mode := "Template"
@export var template_id := "terrain.template.harbor_mouth"
@export var terrain_map_id := "terrain.map.harbor_mouth"
@export var environment_zone_set_id := "environment.zone_set.harbor_mouth"
@export var facility_layout_id := "facility.layout.harbor_mouth"
@export_file("*.json") var snapshot_path := "res://data/terrain/authoring/editor_snapshot.json"
@export var map_size := Vector2(1024.0, 1024.0)
@export var geometry_epsilon := 0.001

const SEMANTIC_TYPES := [
	"HardLand", "SightBlocker", "DeepWater", "CoastalWater", "ShallowWater",
	"ReefOrSandbar", "NavigationChannel", "VisualOnly", "EnvironmentZone",
	"Minefield", "SafeChannel", "ReferenceOnly", "FacilityInteraction",
]


func load_authoring_data() -> String:
	var source_id := template_id if authoring_mode == "Template" else terrain_map_id
	var arguments := ["--mode", authoring_mode, "--template-id", template_id, "--map-id", terrain_map_id, "--out", _relative_snapshot_path()]
	var execution := _run_python("tools/terrain/build_authoring_snapshot.py", arguments)
	if not execution["ok"]:
		return "加载失败\n%s" % execution["output"]
	var snapshot := _read_json(snapshot_path)
	if snapshot.is_empty():
		return "加载失败：无法读取 %s" % snapshot_path
	_populate_snapshot(snapshot)
	return "已加载 %s\n%s" % [source_id, execution["output"]]


func save_authoring_data() -> String:
	var snapshot := _build_snapshot()
	var file := FileAccess.open(snapshot_path, FileAccess.WRITE)
	if file == null:
		return "保存失败：无法写入 %s" % snapshot_path
	file.store_string(JSON.stringify(snapshot, "  ") + "\n")
	file.close()
	var execution := _run_python("tools/terrain/apply_authoring_snapshot.py", ["--snapshot", _relative_snapshot_path()])
	if not execution["ok"]:
		return "回写失败\n%s" % execution["output"]
	return "已回写正式数据\n%s" % execution["output"]


func add_semantic_polygon(semantic_type: String) -> String:
	if semantic_type not in SEMANTIC_TYPES or semantic_type in ["ReferenceOnly", "FacilityInteraction"]:
		return "不能创建语义：%s" % semantic_type
	var center := map_size * 0.5
	var item := {
		"id": "%s.%s_%02d" % [_active_source_id(), semantic_type.to_snake_case(), _semantic_polygons(self).size() + 1],
		"semantic_type": semantic_type,
		"polygon": [[center.x - 64.0, center.y - 64.0], [center.x - 64.0, center.y + 64.0], [center.x + 64.0, center.y + 64.0], [center.x + 64.0, center.y - 64.0]],
		"metadata": _default_metadata(semantic_type),
	}
	_create_polygon(item)
	return "已创建 %s；请在 2D 视图编辑顶点，并在 Inspector 调整 metadata。" % semantic_type


func add_facility_anchor() -> String:
	if authoring_mode != "Template":
		return "设施挂点应在 Template 模式编辑。"
	var index := _authoring_nodes("FacilityAnchor").size() + 1
	_create_anchor({
		"id": "%s.anchor_%02d" % [template_id, index],
		"position": [map_size.x * 0.5, map_size.y * 0.5],
		"interaction_water_polygon": [[map_size.x * 0.5 - 70.0, map_size.y * 0.5 - 50.0], [map_size.x * 0.5 - 70.0, map_size.y * 0.5 + 50.0], [map_size.x * 0.5 + 70.0, map_size.y * 0.5 + 50.0], [map_size.x * 0.5 + 70.0, map_size.y * 0.5 - 50.0]],
		"metadata": {"heading": 0.0, "shore_obstacle_id": "", "target_shape": {"shape_type": "Circle", "radius": 28.0}},
	})
	return "已创建设施挂点；请设置 shore_obstacle_id 并调整交互水域。"


func add_facility_placement() -> String:
	if authoring_mode != "Map":
		return "设施布局应在 Map 模式编辑。"
	var index := _authoring_nodes("FacilityPlacement").size() + 1
	_create_facility({
		"id": "facility.%s.placement_%02d" % [terrain_map_id.get_slice(".", 2), index],
		"position": [map_size.x * 0.5, map_size.y * 0.5],
		"metadata": {"definition_id": "", "anchor_id": "", "faction_id": "neutral", "operation_state": "Dormant", "requires_all_active": [], "requires_any_active": []},
	})
	return "已创建设施布局节点；位置由 anchor_id 决定，依赖关系在 metadata 中编辑。"


func add_land_instance() -> String:
	if authoring_mode != "Map":
		return "岛屿实例应在 Map 模式摆放。"
	var index := _authoring_nodes("LandInstance").size() + 1
	_create_land_instance({
		"id": "land_instance_%02d" % index,
		"template_id": template_id,
		"texture": _template_texture(template_id),
		"position": [map_size.x * 0.5, map_size.y * 0.5],
		"scale": [1.0, 1.0],
		"rotation_degrees": 0.0,
		"reference_only": false,
	})
	return "已摆放 %s；可在 2D 视图调整位置、缩放和旋转。" % template_id


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if authoring_mode == "Template" and not template_id.begins_with("terrain.template."):
		warnings.append("template_id 必须使用 terrain.template.* 稳定 ID。")
	if authoring_mode == "Map" and not terrain_map_id.begins_with("terrain.map."):
		warnings.append("terrain_map_id 必须使用 terrain.map.* 稳定 ID。")
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		warnings.append("地图尺寸必须为正数。")
	for node in _semantic_polygons(self):
		var semantic_type := str(node.get_meta("semantic_type", ""))
		if semantic_type not in SEMANTIC_TYPES:
			warnings.append("%s 缺少合法 metadata.semantic_type。" % node.name)
		var world_polygon := _root_polygon(node)
		if world_polygon.size() < 3:
			warnings.append("%s 少于 3 个顶点。" % node.name)
			continue
		if _signed_area(world_polygon) >= 0.0:
			warnings.append("%s 顶点必须为顺时针。" % node.name)
		if _self_intersects(world_polygon):
			warnings.append("%s 存在自相交。" % node.name)
		for point in world_polygon:
			if point.x < 0.0 or point.y < 0.0 or point.x > map_size.x or point.y > map_size.y:
				warnings.append("%s 超出地图边界。" % node.name)
				break
		if semantic_type == "EnvironmentZone":
			for field in ["effect_id", "phase", "public_trend"]:
				if str(node.get_meta(field, "")).is_empty():
					warnings.append("%s 缺少环境字段 %s。" % [node.name, field])
	for anchor in _authoring_nodes("FacilityAnchor"):
		if str(anchor.get_meta("shore_obstacle_id", "")).is_empty():
			warnings.append("%s 缺少 shore_obstacle_id。" % anchor.name)
	return warnings


func _populate_snapshot(snapshot: Dictionary) -> void:
	_clear_authoring_children()
	authoring_mode = str(snapshot.get("mode", authoring_mode))
	map_size = _vector2(snapshot.get("map_size", [map_size.x, map_size.y]))
	if authoring_mode == "Template":
		template_id = str(snapshot.get("source_id", template_id))
	else:
		terrain_map_id = str(snapshot.get("source_id", terrain_map_id))
		environment_zone_set_id = str(snapshot.get("environment_zone_set_id", environment_zone_set_id))
		facility_layout_id = str(snapshot.get("facility_layout_id", facility_layout_id))
	for item in snapshot.get("polygons", []):
		_create_polygon(item)
	for item in snapshot.get("anchors", []):
		_create_anchor(item)
	for item in snapshot.get("facilities", []):
		_create_facility(item)
	for item in snapshot.get("instances", []):
		_create_land_instance(item)
	update_configuration_warnings()


func _build_snapshot() -> Dictionary:
	var polygons: Array = []
	for node in _semantic_polygons(self):
		var semantic_type := str(node.get_meta("semantic_type", ""))
		if semantic_type == "FacilityInteraction":
			continue
		polygons.append({
			"id": str(node.get_meta("item_id", node.name)),
			"semantic_type": semantic_type,
			"polygon": _points_array(_root_polygon(node)),
			"metadata": _node_metadata(node),
		})
	var anchors: Array = []
	for marker in _authoring_nodes("FacilityAnchor"):
		var interaction_polygon: Array = []
		for child in marker.get_children():
			if child is Polygon2D and str(child.get_meta("semantic_type", "")) == "FacilityInteraction":
				interaction_polygon = _points_array(_root_polygon(child))
		anchors.append({"id": str(marker.get_meta("item_id", marker.name)), "position": _point_array(to_local(marker.global_position)), "interaction_water_polygon": interaction_polygon, "metadata": _node_metadata(marker)})
	var facilities: Array = []
	for marker in _authoring_nodes("FacilityPlacement"):
		facilities.append({"id": str(marker.get_meta("item_id", marker.name)), "position": _point_array(to_local(marker.global_position)), "metadata": _node_metadata(marker)})
	var instances: Array = []
	for sprite in _authoring_nodes("LandInstance"):
		instances.append({
			"id": str(sprite.get_meta("item_id", sprite.name)),
			"template_id": str(sprite.get_meta("template_id", "")),
			"texture": str(sprite.get_meta("texture_path", "")),
			"position": _point_array(to_local(sprite.global_position)),
			"scale": [sprite.scale.x, sprite.scale.y],
			"rotation_degrees": rad_to_deg(sprite.rotation),
			"reference_only": bool(sprite.get_meta("reference_only", false)),
		})
	return {
		"schema_version": 1,
		"mode": authoring_mode,
		"source_id": _active_source_id(),
		"map_size": [map_size.x, map_size.y],
		"environment_zone_set_id": environment_zone_set_id,
		"facility_layout_id": facility_layout_id,
		"polygons": polygons,
		"anchors": anchors,
		"facilities": facilities,
		"instances": instances,
	}


func _create_polygon(item: Dictionary) -> Polygon2D:
	var semantic_type := str(item.get("semantic_type", "VisualOnly"))
	var node := Polygon2D.new()
	node.name = _safe_name(str(item.get("id", semantic_type)))
	node.polygon = _packed_polygon(item.get("polygon", []))
	node.color = _semantic_color(semantic_type)
	node.set_meta("item_id", str(item.get("id", node.name)))
	node.set_meta("semantic_type", semantic_type)
	for key in item.get("metadata", {}):
		node.set_meta(str(key), item["metadata"][key])
	if bool(item.get("metadata", {}).get("locked", false)):
		node.set_meta("_edit_lock_", true)
	_add_owned(_container_for_semantic(semantic_type), node)
	return node


func _create_anchor(item: Dictionary) -> Marker2D:
	var marker := Marker2D.new()
	marker.name = _safe_name(str(item.get("id", "FacilityAnchor")))
	marker.position = _vector2(item.get("position", [0.0, 0.0]))
	marker.set_meta("authoring_kind", "FacilityAnchor")
	marker.set_meta("item_id", str(item.get("id", marker.name)))
	for key in item.get("metadata", {}):
		marker.set_meta(str(key), item["metadata"][key])
	_add_owned(_container("FacilityAnchors"), marker)
	var interaction := Polygon2D.new()
	interaction.name = "InteractionWater"
	interaction.color = Color(0.25, 0.82, 0.92, 0.26)
	interaction.set_meta("semantic_type", "FacilityInteraction")
	var local_points := PackedVector2Array()
	for raw_point in item.get("interaction_water_polygon", []):
		local_points.append(_vector2(raw_point) - marker.position)
	interaction.polygon = local_points
	_add_owned(marker, interaction)
	return marker


func _create_facility(item: Dictionary) -> Marker2D:
	var marker := Marker2D.new()
	marker.name = _safe_name(str(item.get("id", "FacilityPlacement")))
	marker.position = _vector2(item.get("position", [0.0, 0.0]))
	marker.set_meta("authoring_kind", "FacilityPlacement")
	marker.set_meta("item_id", str(item.get("id", marker.name)))
	for key in item.get("metadata", {}):
		marker.set_meta(str(key), item["metadata"][key])
	_add_owned(_container("FacilityPlacements"), marker)
	return marker


func _create_land_instance(item: Dictionary) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = _safe_name(str(item.get("id", "LandInstance")))
	var texture_path := str(item.get("texture", ""))
	var resource = load(texture_path) if not texture_path.is_empty() else null
	sprite.texture = resource if resource is Texture2D else null
	sprite.position = _vector2(item.get("position", [0.0, 0.0]))
	sprite.scale = _vector2(item.get("scale", [1.0, 1.0]))
	sprite.rotation = deg_to_rad(float(item.get("rotation_degrees", 0.0)))
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.82)
	sprite.z_index = -10
	sprite.set_meta("authoring_kind", "LandInstance")
	sprite.set_meta("item_id", str(item.get("id", sprite.name)))
	sprite.set_meta("template_id", str(item.get("template_id", "")))
	sprite.set_meta("texture_path", texture_path)
	sprite.set_meta("reference_only", bool(item.get("reference_only", false)))
	if bool(item.get("reference_only", false)): sprite.set_meta("_edit_lock_", true)
	_add_owned(_container("LandInstances"), sprite)
	return sprite


func _clear_authoring_children() -> void:
	for container_name in ["LandInstances", "HardLand", "SightBlockers", "ShallowWater", "NavigationChannels", "FacilityAnchors", "FacilityPlacements", "EnvironmentZones", "Minefields", "VisualOnly"]:
		var parent := _container(container_name)
		for child in parent.get_children():
			parent.remove_child(child)
			child.free()


func _container_for_semantic(semantic_type: String) -> Node:
	if semantic_type == "HardLand": return _container("HardLand")
	if semantic_type == "SightBlocker": return _container("SightBlockers")
	if semantic_type in ["DeepWater", "CoastalWater", "ShallowWater", "ReefOrSandbar"]: return _container("ShallowWater")
	if semantic_type == "NavigationChannel": return _container("NavigationChannels")
	if semantic_type == "EnvironmentZone": return _container("EnvironmentZones")
	if semantic_type in ["Minefield", "SafeChannel"]: return _container("Minefields")
	return _container("VisualOnly")


func _container(container_name: String) -> Node:
	var node := get_node_or_null(container_name)
	if node == null:
		node = Node2D.new()
		node.name = container_name
		_add_owned(self, node)
	return node


func _add_owned(parent: Node, child: Node) -> void:
	parent.add_child(child)
	var edited_root := get_tree().edited_scene_root if is_inside_tree() else null
	if edited_root != null:
		child.owner = edited_root


func _semantic_polygons(root: Node) -> Array[Polygon2D]:
	var result: Array[Polygon2D] = []
	for child in root.get_children():
		if child is Polygon2D:
			result.append(child)
		result.append_array(_semantic_polygons(child))
	return result


func _authoring_nodes(kind: String) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node in find_children("*", "Node2D", true, false):
		if str(node.get_meta("authoring_kind", "")) == kind:
			result.append(node)
	return result


func _node_metadata(node: Node) -> Dictionary:
	var result := {}
	for raw_key in node.get_meta_list():
		var key := str(raw_key)
		if key in ["item_id", "semantic_type", "authoring_kind", "_edit_lock_"]:
			continue
		result[key] = _json_value(node.get_meta(raw_key))
	return result


func _json_value(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	if value is PackedVector2Array:
		return _points_array(value)
	if value is Array:
		var array: Array = []
		for item in value: array.append(_json_value(item))
		return array
	if value is Dictionary:
		var dictionary := {}
		for key in value: dictionary[str(key)] = _json_value(value[key])
		return dictionary
	return value


func _root_polygon(node: Polygon2D) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in node.polygon:
		result.append(to_local(node.to_global(point)))
	return result


func _packed_polygon(raw: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in raw: result.append(_vector2(point))
	return result


func _points_array(points: PackedVector2Array) -> Array:
	var result: Array = []
	for point in points: result.append(_point_array(point))
	return result


func _point_array(point: Vector2) -> Array:
	return [snappedf(point.x, geometry_epsilon), snappedf(point.y, geometry_epsilon)]


func _default_metadata(semantic_type: String) -> Dictionary:
	if semantic_type == "HardLand": return {"block_mask": ["ShipMovement", "TorpedoTravel", "ShellTravel", "SurfaceOpticalLineOfSight"], "height_class": "Island"}
	if semantic_type == "SightBlocker": return {"block_mask": ["SurfaceOpticalLineOfSight"], "height_class": "Low"}
	if semantic_type in ["DeepWater", "CoastalWater", "ShallowWater", "ReefOrSandbar", "NavigationChannel"]: return {"priority": 40, "access_tags": ["Surface"], "effect_profile_id": "terrain.effect.%s" % semantic_type.to_lower()}
	if semantic_type == "VisualOnly": return {"asset_semantic": "shore_breaker_overlay", "z_index": 6, "opacity": 0.35}
	if semantic_type == "EnvironmentZone": return {"effect_id": "environment.effect.sea_fog", "position": [0.0, 0.0], "heading": 0.0, "drift_speed": 0.0, "drift_path": [], "intensity": 1.0, "phase": "Stable", "duration": 0.0, "active": true, "public_trend": "Stable"}
	if semantic_type == "Minefield": return {"owner_faction_id": "neutral", "operation_state": "Dormant", "known_by_faction": [], "controller_facility_id": ""}
	if semantic_type == "SafeChannel": return {"minefield_id": "", "order": 1}
	return {}


func _semantic_color(semantic_type: String) -> Color:
	return {
		"HardLand": Color(0.63, 0.34, 0.22, 0.42), "SightBlocker": Color(0.78, 0.34, 0.28, 0.30),
		"ShallowWater": Color(0.25, 0.86, 0.84, 0.25), "ReefOrSandbar": Color(0.92, 0.78, 0.43, 0.30),
		"NavigationChannel": Color(0.30, 0.70, 1.0, 0.26), "EnvironmentZone": Color(0.72, 0.84, 0.88, 0.22),
		"Minefield": Color(0.95, 0.30, 0.22, 0.22), "SafeChannel": Color(0.30, 0.96, 0.68, 0.25),
		"ReferenceOnly": Color(0.42, 0.36, 0.30, 0.18),
	}.get(semantic_type, Color(0.45, 0.78, 0.82, 0.20))


func _run_python(script_path: String, arguments: Array) -> Dictionary:
	var output: Array = []
	var command := PackedStringArray([ProjectSettings.globalize_path("res://%s" % script_path)])
	for argument in arguments: command.append(str(argument))
	var exit_code := OS.execute("python3", command, output, true)
	return {"ok": exit_code == 0, "output": "\n".join(output).strip_edges()}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _template_texture(requested_template_id: String) -> String:
	var document := _read_json("res://data/terrain/terrain_templates.json")
	for definition in document.get("definitions", []):
		if str(definition.get("id", "")) == requested_template_id:
			return str(definition.get("texture", ""))
	return ""


func _relative_snapshot_path() -> String:
	return snapshot_path.trim_prefix("res://")


func _active_source_id() -> String:
	return template_id if authoring_mode == "Template" else terrain_map_id


func _safe_name(value: String) -> String:
	return value.replace(".", "_").replace("-", "_")


func _signed_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index in range(polygon.size()): area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
	return area * 0.5


func _self_intersects(polygon: PackedVector2Array) -> bool:
	for first in range(polygon.size()):
		var first_next := (first + 1) % polygon.size()
		for second in range(first + 1, polygon.size()):
			var second_next := (second + 1) % polygon.size()
			if first_next == second or second_next == first or (first == 0 and second_next == 0): continue
			if Geometry2D.segment_intersects_segment(polygon[first], polygon[first_next], polygon[second], polygon[second_next]) != null: return true
	return false


func _vector2(value: Variant) -> Vector2:
	return value if value is Vector2 else Vector2(float(value[0]), float(value[1]))
