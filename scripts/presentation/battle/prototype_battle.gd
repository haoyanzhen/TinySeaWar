extends Node2D

const BattleSession = preload("res://scripts/application/battle_session.gd")
const BattleEffectDirector = preload("res://scripts/presentation/battle/battle_effect_director.gd")
const UiText = preload("res://scripts/presentation/ui_text.gd")
const CollisionGeometryService = preload("res://scripts/domain/services/collision_geometry_service.gd")
const GunDispersionService = preload("res://scripts/domain/services/gun_dispersion_service.gd")

const MAIN_MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const FIXED_STEP := 0.1
const CAMERA_SPEED := 900.0
const CAMERA_EDGE_MARGIN := 28.0
const CAMERA_FOLLOW_DAMPING := 7.5
const UI_ASSET_ROOT := "res://assets/ui/export/2x"
const DEFAULT_UNIT_SCALE := 0.28
const RANGE_AVAILABLE_FILL := Color(0.18, 1.0, 0.48, 0.13)
const RANGE_AVAILABLE_EDGE := Color(0.28, 1.0, 0.55, 0.86)
const RANGE_FULL_SALVO_FILL := Color(0.02, 0.38, 0.14, 0.30)
const RANGE_FULL_SALVO_EDGE := Color(0.08, 0.62, 0.24, 0.95)
const RANGE_UNAVAILABLE_FILL := Color(1.0, 0.18, 0.16, 0.075)
const RANGE_UNAVAILABLE_EDGE := Color(1.0, 0.24, 0.2, 0.72)
const RANGE_SELECTION_WHITE := Color(1.0, 1.0, 1.0, 0.95)
const DEFAULT_AREA_TARGET_RADIUS := 48.0
const MAIN_GUN_SCOPE_HALF_WIDTH_PX := 220.0
const MAIN_GUN_SCOPE_HALF_HEIGHT_PX := 110.0
const MAIN_GUN_SCOPE_TICK_SPACING_PX := 16.0
const MAIN_GUN_SCOPE_CONFIRM_MS := 100
const MAIN_GUN_SCOPE_LINE := Color(0.86, 0.98, 1.0, 0.42)
const MAIN_GUN_SCOPE_MAJOR := Color(0.94, 1.0, 1.0, 0.56)
const MAIN_GUN_SCOPE_CENTER := Color(1.0, 0.79, 0.34, 0.72)
const MAIN_GUN_SCOPE_INVALID := Color(1.0, 0.44, 0.50, 0.76)
const MAIN_GUN_SCOPE_SHADOW := Color(0.03, 0.16, 0.20, 0.28)
const MAIN_GUN_DISPERSION := Color(0.88, 0.98, 1.0, 0.26)

enum OperationMode { NORMAL, AIMING_PRIMARY, TARGETING_SKILL, PLACING_ROUTE }

@onready var ocean_surface: Node2D = $OceanSurface
@onready var weather_overlay: Node2D = $WeatherOverlay
@onready var terrain_view: Node2D = $TerrainView
@onready var terrain_debug_overlay: Node2D = $TerrainDebugOverlay
@onready var battle_camera: Camera2D = $BattleCamera
@onready var battle_hud: Control = $HUD/BattleHud

var session
var level_id := "level.prototype_3v3"
var accumulator := 0.0
var selected_unit_id := ""
var selected_facility_id := ""
var focused_target_id := ""
var recent_messages: Array[String] = []
var camera_mode := "Manual"
var camera_follow_unit_id := ""
var camera_settings: Dictionary = {}
var camera_zoom_min := 1.0
var camera_zoom_max := 1.0
var operation_mode := OperationMode.NORMAL
var skill_target_type := ""
var current_palette_id := "cloudy"
var palette_override := ""
var texture_cache: Dictionary = {}
var unit_visual_cache: Dictionary = {}
var result_character_id := ""
var unit_layer: Node2D
var projectile_layer: Node2D
var vfx_layer: Node2D
var effect_director
var gun_scope_confirmation_position := Vector2.ZERO
var gun_scope_confirmation_started_msec := 0
var gun_scope_confirmation_until_msec := 0


func _ready() -> void:
	_ensure_camera_input_actions()
	camera_settings = DataRegistry.registry.get_definition("settings", "settings.presentation").get("camera", {})
	_create_presentation_layers()
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		level_id = str(flow.selected_level_id)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--level="): level_id = argument.trim_prefix("--level=")
		elif argument.begins_with("--palette="): palette_override = argument.trim_prefix("--palette=")
	battle_hud.return_to_menu_requested.connect(_return_to_main_menu)
	battle_hud.restart_requested.connect(_restart_battle)
	effect_director = BattleEffectDirector.new()
	add_child(effect_director)
	effect_director.setup(unit_layer, projectile_layer, vfx_layer)
	_start_battle(level_id)
	if not palette_override.is_empty(): _set_ocean_palette(palette_override)


func _process(delta: float) -> void:
	if session == null: return
	accumulator += minf(delta, 0.25)
	while accumulator >= FIXED_STEP:
		accumulator -= FIXED_STEP
		var events: Array = session.advance_tick(FIXED_STEP)
		_consume_events(events)
	_update_camera(delta)
	var paused: bool = session.state.get("phase", "") == "Paused"
	ocean_surface.set_animation_paused(paused)
	weather_overlay.set_animation_paused(paused)
	_sync_visuals()
	_update_hud()
	queue_redraw()


func _draw() -> void:
	if session == null or session.state.is_empty(): return
	var snapshot: Dictionary = session.snapshot("player", false)
	_draw_map_boundary(snapshot)
	for contact in snapshot["contacts"].values():
		var ghost_position: Vector2 = contact["last_known_position"]
		_draw_icon_centered("ui_icon_unknown_contact", ghost_position, 0.55, Color(1.0, 0.55, 0.6, 0.65))
		draw_arc(ghost_position, 33.0, 0.0, TAU, 28, Color(1.0, 0.55, 0.6, 0.55), 2.0)
	_draw_operation_overlay()


func _create_presentation_layers() -> void:
	projectile_layer = Node2D.new()
	projectile_layer.name = "ProjectileLayer"
	unit_layer = Node2D.new()
	unit_layer.name = "UnitLayer"
	vfx_layer = Node2D.new()
	vfx_layer.name = "VfxLayer"
	add_child(projectile_layer)
	add_child(unit_layer)
	add_child(vfx_layer)


func _draw_map_boundary(snapshot: Dictionary) -> void:
	var source: Dictionary = snapshot.get("map", {})
	var size := Vector2(float(source.get("width", 4096.0)), float(source.get("height", 2304.0)))
	draw_rect(Rect2(Vector2.ZERO, size), Color("#72bed1"), false, 4.0)


func _draw_unit(unit: Dictionary) -> void:
	var position: Vector2 = unit["position"]
	var friendly: bool = unit["faction_id"] == "player"
	var life_state := str(unit["life_state"])
	var color := Color("#63c7ff") if friendly else Color("#ff6b6b")
	if life_state == "Sunk": color = Color("#6c7780")
	var radius := float(unit.get("collision_radius", 22.0))
	var collision_half_extents := CollisionGeometryService.half_extents(unit)
	var heading := float(unit["heading"])
	draw_colored_polygon(_world_ellipse_points(position, collision_half_extents + Vector2(12.0, 12.0), heading), Color(0.02, 0.08, 0.12, 0.28))
	_draw_unit_art(unit, color)
	draw_polyline(_world_ellipse_points(position, collision_half_extents, heading, true), Color(0.86, 0.97, 1.0, 0.58), 1.5, true)
	var heading_vector := Vector2.RIGHT.rotated(heading)
	draw_line(position, position + heading_vector * (collision_half_extents.x + 34.0), Color(1.0, 1.0, 1.0, 0.75), 2.5)
	if unit["entity_id"] == selected_unit_id:
		_draw_icon_centered("ui_marker_selected", position, 0.85, Color.WHITE)
		draw_polyline(_world_ellipse_points(position, collision_half_extents + Vector2(19.0, 19.0), heading, true), Color("#f8ef9a"), 3.0, true)
	if unit["entity_id"] == focused_target_id:
		_draw_icon_centered("ui_marker_target", position, 0.9, Color.WHITE)
		draw_polyline(_world_ellipse_points(position, collision_half_extents + Vector2(25.0, 25.0), heading, true), Color("#ffb35c"), 3.0, true)
	if bool(unit["is_flagship"]):
		_draw_icon_centered("ui_marker_flagship", position + Vector2(0.0, -radius - 34.0), 0.42, Color.WHITE)
	var hp_ratio := float(unit["current_hp"]) / maxf(1.0, float(unit["max_hp"]))
	var bar_width := maxf(68.0, radius * 3.2)
	draw_rect(Rect2(position + Vector2(-bar_width * 0.5, -radius - 28.0), Vector2(bar_width, 7.0)), Color("#202931"), true)
	draw_rect(Rect2(position + Vector2(-bar_width * 0.5, -radius - 28.0), Vector2(bar_width * hp_ratio, 7.0)), Color("#70db84") if friendly else Color("#ff9a8c"), true)
	var label := ("[旗舰] " if unit["is_flagship"] else "") + str(unit["display_name"])
	draw_string(ThemeDB.fallback_font, position + Vector2(-72.0, radius + 36.0), label, HORIZONTAL_ALIGNMENT_CENTER, 144.0, 18, Color.WHITE)


func _draw_unit_art(unit: Dictionary, fallback_color: Color) -> void:
	var visuals := _unit_visuals(unit)
	var position: Vector2 = unit["position"]
	var rotation := float(unit["heading"])
	var radius := float(unit.get("collision_radius", 22.0))
	var scales := _unit_art_scales(visuals, unit)
	var life_state := str(unit.get("life_state", "Alive"))
	var tint := Color(1.0, 1.0, 1.0, 1.0)
	if life_state == "Sunk":
		tint = Color(0.5, 0.58, 0.62, 0.65)
	if visuals.get("rig") != null:
		_draw_texture_centered(visuals["rig"], position, rotation, scales["rig"], tint)
	if visuals.get("body") != null:
		_draw_texture_centered(visuals["body"], position, rotation, scales["body"], tint)
	if visuals.get("rig") == null and visuals.get("body") == null:
		draw_colored_polygon(_world_ellipse_points(position, CollisionGeometryService.half_extents(unit), rotation), fallback_color)


func _draw_projectile(projectile: Dictionary) -> void:
	var position: Vector2 = projectile.get("position", Vector2.ZERO)
	var velocity: Vector2 = projectile.get("velocity", Vector2.ZERO)
	var heading := velocity.angle() if velocity.length_squared() > 0.01 else 0.0
	draw_line(position - Vector2.RIGHT.rotated(heading) * 18.0, position, Color(1.0, 0.92, 0.45, 0.6), 2.0)
	_draw_icon_centered("ui_icon_gunfire", position, 0.24, Color(1.0, 0.94, 0.6, 0.85))


func _draw_icon_centered(icon_name: String, position: Vector2, scale_value: float = 1.0, modulate: Color = Color.WHITE) -> void:
	var texture := _texture("%s/%s.png" % [UI_ASSET_ROOT, icon_name])
	if texture == null: return
	_draw_texture_centered(texture, position, 0.0, scale_value, modulate)


func _draw_texture_centered(texture: Texture2D, position: Vector2, rotation: float, scale_value: float, modulate: Color = Color.WHITE) -> void:
	draw_set_transform(position, rotation, Vector2(scale_value, scale_value))
	draw_texture(texture, -texture.get_size() * 0.5, modulate)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _unit_visuals(unit: Dictionary) -> Dictionary:
	var definition_id := str(unit.get("definition_id", ""))
	if unit_visual_cache.has(definition_id): return unit_visual_cache[definition_id]
	var slug := definition_id.trim_prefix("ship.")
	var asset_root := str(unit.get("asset_root", "res://assets/characters/%s/processed" % slug))
	var visuals := {
		"rig": _texture("%s/battle/%s_battle_rig_base.png" % [asset_root, slug]),
		"body": _texture("%s/battle/%s_battle_body_r.png" % [asset_root, slug]),
	}
	unit_visual_cache[definition_id] = visuals
	return visuals


func _unit_art_scales(visuals: Dictionary, unit: Dictionary) -> Dictionary:
	var radius := float(unit.get("collision_radius", 22.0))
	var collision_half_extents := CollisionGeometryService.half_extents(unit)
	var body_texture: Texture2D = visuals.get("body", null)
	var rig_texture: Texture2D = visuals.get("rig", null)
	var body_scale := DEFAULT_UNIT_SCALE
	var rig_scale := DEFAULT_UNIT_SCALE
	if body_texture != null:
		var body_target_width := clampf(radius * 3.8, 84.0, 126.0)
		body_scale = body_target_width / maxf(1.0, float(body_texture.get_width()))
	if rig_texture != null:
		var rig_target_width := collision_half_extents.x * 2.0
		rig_scale = rig_target_width / maxf(1.0, float(rig_texture.get_width()))
	else:
		rig_scale = body_scale
	return {"body": body_scale, "rig": rig_scale}


func _world_ellipse_points(center: Vector2, extents: Vector2, heading: float, close: bool = false) -> PackedVector2Array:
	var points := PackedVector2Array()
	var segment_count := 64
	for index in range(segment_count + (1 if close else 0)):
		var angle := TAU * float(index % segment_count) / float(segment_count)
		points.append(center + Vector2(cos(angle) * extents.x, sin(angle) * extents.y).rotated(heading))
	return points


func _texture(path: String) -> Texture2D:
	if texture_cache.has(path): return texture_cache[path]
	var resource := load(path)
	texture_cache[path] = resource if resource is Texture2D else null
	return texture_cache[path]


func _draw_operation_overlay() -> void:
	_draw_gun_scope_confirmation()
	if selected_unit_id.is_empty(): return
	var selected: Dictionary = session.state.get("units_by_id", {}).get(selected_unit_id, {})
	if selected.is_empty(): return
	_draw_selected_route(selected)
	if operation_mode == OperationMode.NORMAL or operation_mode == OperationMode.PLACING_ROUTE: return
	var cursor := get_global_mouse_position()
	if operation_mode == OperationMode.AIMING_PRIMARY:
		var aim_status: Dictionary = session.get_primary_aim_status(selected_unit_id, cursor)
		var reason_offset := Vector2(18.0, -18.0)
		if aim_status.get("control_type", "") == "Direction":
			_draw_directional_aim_overlay(selected, cursor, aim_status)
		elif aim_status.get("weapon_type", "") == "Gun":
			_draw_gun_aim_overlay(selected, cursor, aim_status)
			reason_offset = Vector2(18.0, MAIN_GUN_SCOPE_HALF_HEIGHT_PX + 28.0) * _scope_world_per_pixel()
		else:
			_draw_area_target_overlay(selected, cursor, aim_status, float(aim_status.get("impact_radius", DEFAULT_AREA_TARGET_RADIUS)))
		_draw_aim_reason_label(cursor, str(aim_status.get("reason_code", "OK")), bool(aim_status.get("legal", false)), reason_offset)
	elif operation_mode == OperationMode.TARGETING_SKILL:
		_draw_skill_target_overlay(selected, cursor)


func _draw_selected_route(selected: Dictionary) -> void:
	var movement: Dictionary = selected.get("movement_state", {})
	if str(movement.get("mode", "")) not in ["PlayerMoveOrder", "PlayerWaypointRoute"] and operation_mode != OperationMode.PLACING_ROUTE:
		return
	var points := PackedVector2Array([selected.get("position", Vector2.ZERO)])
	var waypoints: Array = movement.get("waypoints", [])
	for index in range(int(movement.get("waypoint_index", 0)), waypoints.size()):
		points.append(waypoints[index])
	if points.size() >= 2:
		draw_polyline(points, Color(0.38, 0.92, 1.0, 0.84), 3.0, true)
	for point_index in range(1, points.size()):
		draw_circle(points[point_index], 8.0, Color(0.05, 0.22, 0.28, 0.86))
		draw_arc(points[point_index], 10.0, 0.0, TAU, 24, Color(0.58, 0.98, 1.0, 0.96), 2.0)


func _draw_torpedo_aim_overlay(selected: Dictionary, cursor: Vector2, aim_status: Dictionary) -> void:
	_draw_directional_aim_overlay(selected, cursor, aim_status)


func _draw_directional_aim_overlay(selected: Dictionary, cursor: Vector2, aim_status: Dictionary) -> void:
	var origin: Vector2 = selected["position"]
	var maximum_range := float(aim_status.get("range", 0.0))
	draw_circle(origin, maximum_range, RANGE_UNAVAILABLE_FILL)
	draw_arc(origin, maximum_range, 0.0, TAU, 128, RANGE_UNAVAILABLE_EDGE, 2.0)
	for arc in aim_status.get("fire_arcs", []):
		var center_angle := float(selected.get("heading", 0.0)) + deg_to_rad(float(arc.get("center", 0.0)))
		var half_angle := deg_to_rad(float(arc.get("degrees", 0.0))) * 0.5
		var minimum_range := 0.0
		var arc_range := float(arc.get("range", maximum_range))
		_draw_annular_sector(origin, minimum_range, arc_range, center_angle - half_angle, center_angle + half_angle, RANGE_AVAILABLE_FILL)
		draw_arc(origin, arc_range, center_angle - half_angle, center_angle + half_angle, 36, RANGE_AVAILABLE_EDGE, 2.0)
		draw_line(origin + Vector2.RIGHT.rotated(center_angle - half_angle) * minimum_range, origin + Vector2.RIGHT.rotated(center_angle - half_angle) * arc_range, RANGE_AVAILABLE_EDGE, 1.5)
		draw_line(origin + Vector2.RIGHT.rotated(center_angle + half_angle) * minimum_range, origin + Vector2.RIGHT.rotated(center_angle + half_angle) * arc_range, RANGE_AVAILABLE_EDGE, 1.5)
	var selected_heading := (cursor - origin).angle()
	var selected_range := float(aim_status.get("selected_range", maximum_range))
	var spread_half_angle := deg_to_rad(float(aim_status.get("spread_degrees", 0.0))) * 0.5
	draw_line(origin, origin + Vector2.RIGHT.rotated(selected_heading) * selected_range, RANGE_SELECTION_WHITE, 2.5)
	if spread_half_angle > 0.0:
		draw_line(origin, origin + Vector2.RIGHT.rotated(selected_heading - spread_half_angle) * selected_range, RANGE_SELECTION_WHITE, 1.5)
		draw_line(origin, origin + Vector2.RIGHT.rotated(selected_heading + spread_half_angle) * selected_range, RANGE_SELECTION_WHITE, 1.5)
		draw_arc(origin, selected_range, selected_heading - spread_half_angle, selected_heading + spread_half_angle, 16, RANGE_SELECTION_WHITE, 1.5)


func _draw_gun_aim_overlay(selected: Dictionary, cursor: Vector2, aim_status: Dictionary) -> void:
	var origin: Vector2 = selected["position"]
	var maximum_range := float(aim_status.get("range", 0.0))
	draw_circle(origin, maximum_range, RANGE_UNAVAILABLE_FILL)
	draw_arc(origin, maximum_range, 0.0, TAU, 128, RANGE_UNAVAILABLE_EDGE, 2.0)
	_draw_fire_arc_sectors(selected, aim_status.get("fire_arcs", []), maximum_range, RANGE_AVAILABLE_FILL, RANGE_AVAILABLE_EDGE)
	_draw_fire_arc_sectors(selected, aim_status.get("full_salvo_fire_arcs", []), maximum_range, RANGE_FULL_SALVO_FILL, RANGE_FULL_SALVO_EDGE)
	var target_radius := float(aim_status.get("impact_radius", DEFAULT_AREA_TARGET_RADIUS))
	_draw_gun_bearing_line(origin, cursor, target_radius)
	_draw_main_gun_dispersion(cursor, origin, float(aim_status.get("spread_degrees", 0.0)))
	_draw_main_gun_scope(cursor, bool(aim_status.get("legal", false)))


func _draw_gun_bearing_line(origin: Vector2, cursor: Vector2, target_radius: float) -> void:
	var distance := origin.distance_to(cursor)
	if distance <= target_radius:
		return
	var direction := (cursor - origin) / distance
	var line_end := cursor - direction * target_radius * 1.2
	var pixel := _scope_world_per_pixel()
	var dash_length := 10.0 * pixel
	var gap_length := 8.0 * pixel
	var drawn := 0.0
	var line_length := origin.distance_to(line_end)
	while drawn < line_length:
		var segment_end := minf(drawn + dash_length, line_length)
		draw_line(origin + direction * drawn, origin + direction * segment_end, Color(0.90, 0.98, 1.0, 0.22), pixel, true)
		drawn += dash_length + gap_length


func _draw_main_gun_dispersion(center: Vector2, origin: Vector2, spread_degrees: float) -> void:
	var radii := _main_gun_dispersion_radii(origin.distance_to(center), spread_degrees)
	var firing_angle := (center - origin).angle()
	var cross_axis_rotation := firing_angle + PI * 0.5
	var segment_count := 72
	var pixel := _scope_world_per_pixel()
	for segment in range(segment_count):
		if segment % 6 >= 3:
			continue
		var start_angle := TAU * float(segment) / float(segment_count)
		var end_angle := TAU * float(segment + 1) / float(segment_count)
		var start_point := center + Vector2(cos(start_angle) * radii.x, sin(start_angle) * radii.y).rotated(cross_axis_rotation)
		var end_point := center + Vector2(cos(end_angle) * radii.x, sin(end_angle) * radii.y).rotated(cross_axis_rotation)
		draw_line(start_point, end_point, MAIN_GUN_DISPERSION, pixel, true)


func _main_gun_dispersion_radii(distance: float, spread_degrees: float) -> Vector2:
	var settings: Dictionary = DataRegistry.registry.get_definition("settings", "settings.combat").get("gun_dispersion", {})
	return GunDispersionService.sigmas(
		distance,
		spread_degrees,
		float(settings.get("sigma_scale", 0.5684105110424833)),
		float(settings.get("longitudinal_sigma_ratio", 0.5)),
	)


func _draw_main_gun_scope(center: Vector2, legal: bool, scale_multiplier: float = 1.0, alpha_multiplier: float = 1.0) -> void:
	var pixel := _scope_world_per_pixel() * scale_multiplier
	var half_width := MAIN_GUN_SCOPE_HALF_WIDTH_PX * pixel
	var half_height := MAIN_GUN_SCOPE_HALF_HEIGHT_PX * pixel
	var axis_color := _scope_color(MAIN_GUN_SCOPE_LINE, alpha_multiplier)
	var major_color := _scope_color(MAIN_GUN_SCOPE_MAJOR, alpha_multiplier)
	var status_color := _scope_color(MAIN_GUN_SCOPE_CENTER if legal else MAIN_GUN_SCOPE_INVALID, alpha_multiplier)
	_draw_scope_line(center - Vector2(half_width, 0.0), center + Vector2(half_width, 0.0), axis_color, pixel)
	_draw_scope_line(center - Vector2(0.0, half_height), center + Vector2(0.0, half_height), axis_color, pixel)
	_draw_scope_ticks(center, true, int(floor(MAIN_GUN_SCOPE_HALF_WIDTH_PX / MAIN_GUN_SCOPE_TICK_SPACING_PX)), pixel, axis_color, major_color, status_color, legal)
	_draw_scope_ticks(center, false, int(floor(MAIN_GUN_SCOPE_HALF_HEIGHT_PX / MAIN_GUN_SCOPE_TICK_SPACING_PX)), pixel, axis_color, major_color, status_color, legal)
	var end_cap := 14.0 * pixel
	var terminal_color := major_color if legal else status_color
	_draw_scope_line(center + Vector2(-half_width, -end_cap * 0.5), center + Vector2(-half_width, end_cap * 0.5), terminal_color, pixel)
	_draw_scope_line(center + Vector2(half_width, -end_cap * 0.5), center + Vector2(half_width, end_cap * 0.5), terminal_color, pixel)
	_draw_scope_line(center + Vector2(-end_cap * 0.5, -half_height), center + Vector2(end_cap * 0.5, -half_height), terminal_color, pixel)
	_draw_scope_line(center + Vector2(-end_cap * 0.5, half_height), center + Vector2(end_cap * 0.5, half_height), terminal_color, pixel)
	draw_circle(center, 2.4 * pixel, status_color, true, -1.0, true)


func _draw_scope_ticks(center: Vector2, horizontal_axis: bool, tick_count: int, pixel: float, axis_color: Color, major_color: Color, status_color: Color, legal: bool) -> void:
	for index in range(-tick_count, tick_count + 1):
		if index == 0:
			continue
		var absolute_index := absi(index)
		var tick_length_px := 5.0
		var tick_color := axis_color
		if absolute_index % 8 == 0:
			tick_length_px = 14.0
			tick_color = major_color
		elif absolute_index % 4 == 0:
			tick_length_px = 9.0
			tick_color = major_color
		if not legal and absolute_index == tick_count:
			tick_color = status_color
		var offset := float(index) * MAIN_GUN_SCOPE_TICK_SPACING_PX * pixel
		var half_tick := tick_length_px * pixel * 0.5
		if horizontal_axis:
			_draw_scope_line(center + Vector2(offset, -half_tick), center + Vector2(offset, half_tick), tick_color, pixel)
		else:
			_draw_scope_line(center + Vector2(-half_tick, offset), center + Vector2(half_tick, offset), tick_color, pixel)


func _draw_scope_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var shadow_offset := Vector2.ONE * width * 0.75
	draw_line(from + shadow_offset, to + shadow_offset, _scope_color(MAIN_GUN_SCOPE_SHADOW, color.a / maxf(MAIN_GUN_SCOPE_LINE.a, 0.01)), width * 1.6, true)
	draw_line(from, to, color, width, true)


func _scope_world_per_pixel() -> float:
	return 1.0 / maxf(battle_camera.zoom.x, 0.01)


func _scope_color(color: Color, alpha_multiplier: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(color.a * alpha_multiplier, 0.0, 1.0))


func _draw_gun_scope_confirmation() -> void:
	var now := Time.get_ticks_msec()
	if now >= gun_scope_confirmation_until_msec or gun_scope_confirmation_until_msec <= gun_scope_confirmation_started_msec:
		return
	var progress := clampf(float(now - gun_scope_confirmation_started_msec) / float(MAIN_GUN_SCOPE_CONFIRM_MS), 0.0, 1.0)
	_draw_main_gun_scope(gun_scope_confirmation_position, true, lerpf(1.0, 0.92, progress), 1.0 - progress)


func _draw_fire_arc_sectors(selected: Dictionary, arcs: Array, maximum_range: float, fill_color: Color, edge_color: Color) -> void:
	var origin: Vector2 = selected["position"]
	for arc in arcs:
		var center_angle := float(selected.get("heading", 0.0)) + deg_to_rad(float(arc.get("center", 0.0)))
		var half_angle := deg_to_rad(float(arc.get("degrees", 0.0))) * 0.5
		var minimum_range := float(arc.get("minimum_range", 0.0))
		var arc_range := float(arc.get("range", maximum_range))
		_draw_annular_sector(origin, minimum_range, arc_range, center_angle - half_angle, center_angle + half_angle, fill_color)
		draw_arc(origin, arc_range, center_angle - half_angle, center_angle + half_angle, 36, edge_color, 2.0)
		draw_line(origin + Vector2.RIGHT.rotated(center_angle - half_angle) * minimum_range, origin + Vector2.RIGHT.rotated(center_angle - half_angle) * arc_range, edge_color, 1.5)
		draw_line(origin + Vector2.RIGHT.rotated(center_angle + half_angle) * minimum_range, origin + Vector2.RIGHT.rotated(center_angle + half_angle) * arc_range, edge_color, 1.5)


func _draw_area_target_overlay(selected: Dictionary, cursor: Vector2, aim_status: Dictionary, target_radius: float) -> void:
	var origin: Vector2 = selected["position"]
	_draw_range_overlay(origin, float(aim_status.get("minimum_range", 0.0)), float(aim_status.get("range", 0.0)))
	draw_line(origin, cursor, RANGE_SELECTION_WHITE, 2.0)
	draw_circle(cursor, target_radius, Color(1.0, 1.0, 1.0, 0.10))
	draw_arc(cursor, target_radius, 0.0, TAU, 48, RANGE_SELECTION_WHITE, 2.0)


func _draw_skill_target_overlay(selected: Dictionary, cursor: Vector2) -> void:
	var skill: Dictionary = DataRegistry.registry.get_definition("skills", str(selected.get("skill_state", {}).get("definition_id", "")))
	var cast_range := float(skill.get("cast_range", 0.0))
	var legal := cast_range <= 0.0 or (selected["position"] as Vector2).distance_to(cursor) <= cast_range
	_draw_range_overlay(selected["position"], 0.0, cast_range)
	draw_line(selected["position"], cursor, RANGE_SELECTION_WHITE, 1.8)
	if skill_target_type == "Enemy":
		draw_arc(cursor, 34.0, 0.0, TAU, 36, RANGE_SELECTION_WHITE, 2.0)
	else:
		var effect_radius := float(skill.get("effect_radius", DEFAULT_AREA_TARGET_RADIUS))
		draw_circle(cursor, effect_radius, Color(1.0, 1.0, 1.0, 0.10))
		draw_arc(cursor, effect_radius, 0.0, TAU, 48, RANGE_SELECTION_WHITE, 2.0)
	var label := "技能目标：%s" % UiText.target_type_name(skill_target_type)
	if not legal:
		label = "%s / %s" % [label, UiText.reason_name("TARGET_OUT_OF_RANGE")]
	draw_string(ThemeDB.fallback_font, cursor + Vector2(18.0, -18.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, RANGE_SELECTION_WHITE if legal else RANGE_UNAVAILABLE_EDGE)


func _draw_range_overlay(origin: Vector2, minimum_range: float, maximum_range: float) -> void:
	if maximum_range > 0.0:
		draw_circle(origin, maximum_range, RANGE_AVAILABLE_FILL)
		draw_arc(origin, maximum_range, 0.0, TAU, 128, RANGE_AVAILABLE_EDGE, 2.0)
	if minimum_range > 0.0:
		draw_circle(origin, minimum_range, RANGE_UNAVAILABLE_FILL)
		draw_arc(origin, minimum_range, 0.0, TAU, 64, RANGE_UNAVAILABLE_EDGE, 2.0)


func _draw_aim_reason_label(cursor: Vector2, reason_code: String, legal: bool, offset: Vector2 = Vector2(18.0, -18.0)) -> void:
	draw_string(ThemeDB.fallback_font, cursor + offset, UiText.reason_name(reason_code), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, RANGE_SELECTION_WHITE if legal else RANGE_UNAVAILABLE_EDGE)


func _draw_annular_sector(center: Vector2, inner_radius: float, outer_radius: float, start_angle: float, end_angle: float, color: Color) -> void:
	if outer_radius <= 0.0 or end_angle <= start_angle: return
	var segment_count := maxi(8, int(ceil(rad_to_deg(end_angle - start_angle) / 4.0)))
	var points := PackedVector2Array()
	for segment in range(segment_count + 1):
		var ratio := float(segment) / float(segment_count)
		points.append(center + Vector2.RIGHT.rotated(lerpf(start_angle, end_angle, ratio)) * outer_radius)
	if inner_radius <= 0.0:
		points.append(center)
	else:
		for segment in range(segment_count, -1, -1):
			var ratio := float(segment) / float(segment_count)
			points.append(center + Vector2.RIGHT.rotated(lerpf(start_angle, end_angle, ratio)) * inner_radius)
	draw_colored_polygon(points, color)


func _unhandled_input(event: InputEvent) -> void:
	if session == null: return
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := _slot_for_key(event.keycode)
		if slot > 0:
			_select_slot(slot)
			return
		match event.keycode:
			KEY_F9:
				terrain_debug_overlay.visible = not terrain_debug_overlay.visible
				terrain_debug_overlay.queue_redraw()
				_sync_visuals()
				_update_hud()
			KEY_SPACE:
				if session.state["phase"] == "Paused": session.resume()
				else: session.pause()
			KEY_R: _start_battle(level_id)
			KEY_E: _begin_primary_aim()
			KEY_Q: _switch_selected_ammo()
			KEY_F: _begin_or_cast_skill()
			KEY_Z: _toggle_route_placement()
			KEY_X: _toggle_control_state("movement_assist_enabled", "自动航行", event.alt_pressed or event.meta_pressed)
			KEY_C: _toggle_control_state("secondary_auto_fire_enabled", "副武器自动开火", event.alt_pressed or event.meta_pressed)
			KEY_V: _toggle_control_state("primary_auto_fire_enabled", "主武器自动开火", event.alt_pressed or event.meta_pressed)
			KEY_G: _toggle_follow_selected()
			KEY_H: _queue_facility_control()
			KEY_J: _queue_facility_service_or_approach()
			KEY_K: _queue_facility_support(event.shift_pressed, event.meta_pressed or event.ctrl_pressed)
			KEY_L: _queue_facility_mine()
			KEY_BACKSPACE, KEY_U: _queue_facility_cancel()
			KEY_ESCAPE: _cancel_operation_mode()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_camera_zoom(float(camera_settings.get("zoom_step", 1.0)), event.position)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_camera_zoom(1.0 / float(camera_settings.get("zoom_step", 1.0)), event.position)
			return
		var snapshot: Dictionary = session.snapshot("player", false)
		if event.button_index == MOUSE_BUTTON_LEFT and operation_mode == OperationMode.NORMAL:
			var minimap_facility: Dictionary = _minimap_facility_at(event.position, snapshot)
			if not minimap_facility.is_empty():
				selected_facility_id = str(minimap_facility.get("facility_id", ""))
				_push_message("已选择设施：%s" % minimap_facility.get("display_name", selected_facility_id))
				return
		var world_position := get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if operation_mode == OperationMode.AIMING_PRIMARY: _confirm_primary_aim(world_position)
			elif operation_mode == OperationMode.TARGETING_SKILL: _confirm_skill_target(world_position, snapshot)
			elif operation_mode == OperationMode.PLACING_ROUTE: _append_route_waypoint(world_position)
			else: _select_at(world_position, snapshot)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if operation_mode == OperationMode.AIMING_PRIMARY:
				_cancel_operation_mode()
			elif operation_mode == OperationMode.NORMAL and not selected_unit_id.is_empty():
				session.queue_command({"command_id": "ui.move.%s" % session.state["tick_index"], "command_type": "MoveUnits", "issued_at_tick": session.state["tick_index"], "issuer_id": "player", "unit_id": selected_unit_id, "target_position": world_position})


func _update_camera(delta: float) -> void:
	var input_direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if input_direction.length_squared() > 0.0:
		camera_mode = "Manual"
		camera_follow_unit_id = ""
		battle_camera.position += input_direction.normalized() * CAMERA_SPEED * delta / maxf(battle_camera.zoom.x, 0.01)
	elif camera_mode == "Follow":
		var target: Dictionary = session.state.get("units_by_id", {}).get(camera_follow_unit_id, {})
		if target.is_empty() or target.get("life_state", "") != "Alive" or target.get("faction_id", "") != "player":
			camera_mode = "Manual"
			camera_follow_unit_id = ""
		else:
			var weight := 1.0 - exp(-CAMERA_FOLLOW_DAMPING * delta)
			battle_camera.position = battle_camera.position.lerp(target["position"], weight)
	_clamp_camera_to_map()


func _adjust_camera_zoom(multiplier: float, screen_position: Vector2) -> void:
	var old_zoom := battle_camera.zoom.x
	var new_zoom := clampf(old_zoom * multiplier, camera_zoom_min, camera_zoom_max)
	if is_equal_approx(old_zoom, new_zoom):
		return
	var screen_offset := screen_position - get_viewport_rect().size * 0.5
	var anchor_world := battle_camera.position + screen_offset / old_zoom
	battle_camera.zoom = Vector2.ONE * new_zoom
	battle_camera.position = anchor_world - screen_offset / new_zoom
	_clamp_camera_to_map()
	_update_hud()


func _configure_camera_zoom(map_data: Dictionary) -> void:
	var viewport_size := get_viewport_rect().size
	var map_size := Vector2(float(map_data.get("width", 4096.0)), float(map_data.get("height", 2304.0)))
	var min_visible_size := _pair_to_vector(camera_settings.get("min_visible_size", []))
	var max_visible_fraction := float(camera_settings.get("max_map_visible_fraction", 0.0))
	if min_visible_size.x <= 0.0 or min_visible_size.y <= 0.0 or max_visible_fraction <= 0.0:
		push_error("Camera zoom settings are missing or invalid")
		camera_zoom_min = 1.0
		camera_zoom_max = 1.0
		battle_camera.zoom = Vector2.ONE
		return
	camera_zoom_min = maxf(
		viewport_size.x / (map_size.x * max_visible_fraction),
		viewport_size.y / (map_size.y * max_visible_fraction)
	)
	camera_zoom_max = minf(
		viewport_size.x / min_visible_size.x,
		viewport_size.y / min_visible_size.y
	)
	camera_zoom_max = maxf(camera_zoom_max, camera_zoom_min)
	var default_zoom := clampf(float(camera_settings.get("default_zoom", 1.0)), camera_zoom_min, camera_zoom_max)
	battle_camera.zoom = Vector2.ONE * default_zoom


func _camera_visible_size() -> Vector2:
	return get_viewport_rect().size / maxf(battle_camera.zoom.x, 0.01)


func _pair_to_vector(value: Array) -> Vector2:
	if value.size() != 2:
		return Vector2.ZERO
	return Vector2(float(value[0]), float(value[1]))


func _ensure_camera_input_actions() -> void:
	var bindings := {
		"camera_left": KEY_A,
		"camera_right": KEY_D,
		"camera_up": KEY_W,
		"camera_down": KEY_S,
	}
	for action in bindings:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var has_key := false
		for existing_event in InputMap.action_get_events(action):
			if existing_event is InputEventKey and existing_event.physical_keycode == bindings[action]:
				has_key = true
				break
		if has_key: continue
		var key_event := InputEventKey.new()
		key_event.physical_keycode = bindings[action]
		InputMap.action_add_event(action, key_event)


func _clamp_camera_to_map() -> void:
	if session == null or session.state.is_empty(): return
	var source: Dictionary = session.state.get("map", {})
	var map_size := Vector2(float(source.get("width", 4096.0)), float(source.get("height", 2304.0)))
	var half_view := _camera_visible_size() * 0.5
	var minimum := half_view + Vector2.ONE * CAMERA_EDGE_MARGIN
	var maximum := map_size - half_view - Vector2.ONE * CAMERA_EDGE_MARGIN
	if maximum.x < minimum.x:
		minimum.x = map_size.x * 0.5
		maximum.x = minimum.x
	if maximum.y < minimum.y:
		minimum.y = map_size.y * 0.5
		maximum.y = minimum.y
	battle_camera.position = battle_camera.position.clamp(minimum, maximum)


func _toggle_follow_selected() -> void:
	if selected_unit_id.is_empty(): return
	var selected: Dictionary = session.state.get("units_by_id", {}).get(selected_unit_id, {})
	if selected.is_empty() or selected.get("faction_id", "") != "player": return
	if selected.get("life_state", "") != "Alive":
		_push_message("V 不可用：%s" % UiText.reason_name("UNIT_SUNK"))
		return
	if camera_mode == "Follow" and camera_follow_unit_id == selected_unit_id:
		camera_mode = "Manual"
		camera_follow_unit_id = ""
	else:
		camera_mode = "Follow"
		camera_follow_unit_id = selected_unit_id
		_clamp_camera_to_map()


func _slot_for_key(keycode: int) -> int:
	match keycode:
		KEY_1: return 1
		KEY_2: return 2
		KEY_3: return 3
		KEY_4: return 4
		KEY_5: return 5
		KEY_6: return 6
		KEY_7: return 7
		KEY_8: return 8
		KEY_9: return 9
		KEY_0: return 10
		KEY_MINUS: return 11
		_: return 0


func _select_slot(slot: int) -> void:
	for slot_data in session.get_player_slots():
		if int(slot_data["slot"]) != slot: continue
		if operation_mode == OperationMode.AIMING_PRIMARY:
			_queue_primary_auto_suspend(false)
		selected_unit_id = str(slot_data["unit_id"])
		operation_mode = OperationMode.NORMAL
		if camera_mode == "Follow": camera_follow_unit_id = selected_unit_id
		_push_message("已选择 %d 号角色：%s" % [slot, slot_data.get("display_name", selected_unit_id)])
		return
	_push_message("%d 号角色不可用" % slot)


func _select_at(world_position: Vector2, snapshot: Dictionary) -> void:
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for unit in snapshot["units"].values():
		var distance := CollisionGeometryService.normalized_distance(world_position, unit["position"], float(unit["heading"]), CollisionGeometryService.half_extents(unit), 8.0)
		if distance <= 1.0 and distance < nearest_distance:
			nearest = unit
			nearest_distance = distance
	if nearest.is_empty():
		var facility: Dictionary = _facility_at(world_position, snapshot)
		if not facility.is_empty():
			selected_facility_id = str(facility.get("facility_id", ""))
			_push_message("已选择设施：%s" % facility.get("display_name", selected_facility_id))
		return
	if nearest["faction_id"] == "player":
		selected_unit_id = nearest["entity_id"]
		if camera_mode == "Follow": camera_follow_unit_id = selected_unit_id
	else:
		focused_target_id = nearest["entity_id"]
		if not selected_unit_id.is_empty(): session.queue_command({"command_id": "ui.focus.%s" % session.state["tick_index"], "command_type": "FocusTarget", "issued_at_tick": session.state["tick_index"], "issuer_id": "player", "unit_id": selected_unit_id, "target_unit_id": focused_target_id})


func _facility_at(world_position: Vector2, snapshot: Dictionary) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := 54.0
	for facility in snapshot.get("facilities", {}).values():
		var distance := world_position.distance_to(facility.get("position", Vector2.ZERO))
		if distance <= nearest_distance:
			nearest = facility
			nearest_distance = distance
	return nearest


func _minimap_facility_at(screen_position: Vector2, snapshot: Dictionary) -> Dictionary:
	var outer := Rect2(Vector2(28.0, get_viewport_rect().size.y - 266.0), Vector2(330.0, 226.0))
	var map_rect := Rect2(outer.position + Vector2(14.0, 36.0), outer.size - Vector2(28.0, 52.0))
	if not map_rect.has_point(screen_position): return {}
	var map_data: Dictionary = snapshot.get("map", {})
	var world: Vector2 = Vector2((screen_position.x - map_rect.position.x) / map_rect.size.x * float(map_data.get("width", 1.0)), (screen_position.y - map_rect.position.y) / map_rect.size.y * float(map_data.get("height", 1.0)))
	var scale: Vector2 = Vector2(float(map_data.get("width", 1.0)) / map_rect.size.x, float(map_data.get("height", 1.0)) / map_rect.size.y)
	var candidate: Dictionary = _facility_at(world, {"facilities": snapshot.get("facilities", {})})
	if candidate.is_empty() or (candidate.get("position", Vector2.ZERO) as Vector2).distance_to(world) > 12.0 * maxf(scale.x, scale.y): return {}
	return candidate


func _queue_facility_control() -> void:
	_queue_facility_command("DeclareFacilityControl")


func _queue_facility_service_or_approach() -> void:
	if selected_unit_id.is_empty() or selected_facility_id.is_empty(): return
	var status: Dictionary = session.get_facility_action_status(selected_unit_id, selected_facility_id)
	_queue_facility_command("RequestFacilityService" if bool(status.get("service_ready", false)) else "ApproachFacility")


func _queue_facility_support(patrol: bool = false, recon: bool = false) -> void:
	if selected_unit_id.is_empty() or selected_facility_id.is_empty(): return
	var mission_id := "support_mission.air_recon" if recon else ("support_mission.fighter_patrol" if patrol else "support_mission.airstrike")
	session.queue_command({"command_id":"ui.facility.support.%s" % session.state["tick_index"], "command_type":"RequestSupportMission", "issued_at_tick":session.state["tick_index"], "issuer_id":"player", "unit_id":selected_unit_id, "facility_id":selected_facility_id, "mission_definition_id":mission_id, "target_position":get_global_mouse_position()})


func _queue_facility_mine() -> void:
	_queue_facility_command("RequestMineDeployment", {"target_position": get_global_mouse_position()})


func _queue_facility_cancel() -> void:
	_queue_facility_command("CancelFacilityAction")


func _queue_facility_command(command_type: String, extra: Dictionary = {}) -> void:
	if selected_unit_id.is_empty() or selected_facility_id.is_empty(): return
	var command: Dictionary = {"command_id":"ui.facility.%s.%s" % [command_type, session.state["tick_index"]], "command_type":command_type, "issued_at_tick":session.state["tick_index"], "issuer_id":"player", "unit_id":selected_unit_id, "facility_id":selected_facility_id}
	command.merge(extra, true)
	session.queue_command(command)


func _begin_primary_aim() -> void:
	if selected_unit_id.is_empty(): return
	if operation_mode == OperationMode.AIMING_PRIMARY:
		_cancel_operation_mode()
		return
	if operation_mode != OperationMode.NORMAL:
		_cancel_operation_mode()
	var selected: Dictionary = session.state["units_by_id"].get(selected_unit_id, {})
	if selected.is_empty(): return
	var operation_status: Dictionary = session.get_operation_status(selected_unit_id)
	if not bool(operation_status.get("primary_ready", false)):
		_push_message("E 不可用：%s" % UiText.reason_name(str(operation_status.get("primary_reason", "PRIMARY_WEAPON_UNAVAILABLE"))))
		return
	operation_mode = OperationMode.AIMING_PRIMARY
	_queue_primary_auto_suspend(true)
	_push_message("正在瞄准：%s" % operation_status.get("primary_name", "主要武器"))


func _confirm_primary_aim(world_position: Vector2) -> void:
	if selected_unit_id.is_empty(): return
	var aim_status: Dictionary = session.get_primary_aim_status(selected_unit_id, world_position)
	if not bool(aim_status.get("legal", false)):
		_push_message("主要武器无法发射：%s" % UiText.reason_name(str(aim_status.get("reason_code", "INVALID_TARGET"))))
		return
	if aim_status.get("weapon_type", "") == "Gun":
		gun_scope_confirmation_position = world_position
		gun_scope_confirmation_started_msec = Time.get_ticks_msec()
		gun_scope_confirmation_until_msec = gun_scope_confirmation_started_msec + MAIN_GUN_SCOPE_CONFIRM_MS
	session.queue_command({"command_id": "ui.primary.%s" % session.state["tick_index"], "command_type": "FirePrimaryWeapon", "issued_at_tick": session.state["tick_index"], "issuer_id": "player", "unit_id": selected_unit_id, "target_position": world_position})
	_queue_primary_auto_suspend(false)
	operation_mode = OperationMode.NORMAL


func _switch_selected_ammo() -> void:
	if selected_unit_id.is_empty(): return
	var operation_status: Dictionary = session.get_operation_status(selected_unit_id)
	if not bool(operation_status.get("q_enabled", false)):
		_push_message("Q 不可用：%s" % UiText.reason_name("AMMO_SWITCH_DISABLED"))
		return
	session.queue_command({"command_id": "ui.ammo.%s" % session.state["tick_index"], "command_type": "SwitchAmmo", "issued_at_tick": session.state["tick_index"], "issuer_id": "player", "unit_id": selected_unit_id})


func _begin_or_cast_skill() -> void:
	if selected_unit_id.is_empty(): return
	if operation_mode != OperationMode.NORMAL:
		_cancel_operation_mode()
	var selected: Dictionary = session.state["units_by_id"].get(selected_unit_id, {})
	if selected.is_empty(): return
	var operation_status: Dictionary = session.get_operation_status(selected_unit_id)
	if not bool(operation_status.get("skill_ready", false)):
		_push_message("F 不可用：%s" % UiText.reason_name("SKILL_ON_COOLDOWN"))
		return
	var skill: Dictionary = DataRegistry.registry.get_definition("skills", str(selected["skill_state"]["definition_id"]))
	skill_target_type = str(skill.get("target_type", "Self"))
	if skill_target_type == "Self":
		_queue_skill_command({"type": "Self"})
	else:
		operation_mode = OperationMode.TARGETING_SKILL
		_push_message("%s：%s；请选择%s" % [skill.get("display_name", "技能"), skill.get("description", ""), UiText.target_type_name(skill_target_type)])


func _confirm_skill_target(world_position: Vector2, snapshot: Dictionary) -> void:
	if selected_unit_id.is_empty(): return
	if skill_target_type == "Area":
		_queue_skill_command({"type": "Position", "position": world_position})
		operation_mode = OperationMode.NORMAL
		return
	var clicked := _unit_at(world_position, snapshot)
	if clicked.is_empty() or clicked.get("faction_id", "") == "player":
		_push_message("技能无法释放：%s" % UiText.reason_name("INVALID_TARGET_TYPE"))
		return
	_queue_skill_command({"type": "Entity", "entity_id": clicked["entity_id"]})
	operation_mode = OperationMode.NORMAL


func _queue_skill_command(target_ref: Dictionary) -> void:
	session.queue_command({"command_id": "ui.skill.%s" % session.state["tick_index"], "command_type": "CastSkill", "issued_at_tick": session.state["tick_index"], "issuer_id": "player", "unit_id": selected_unit_id, "target_ref": target_ref})


func _cancel_operation_mode() -> void:
	if operation_mode == OperationMode.NORMAL: return
	if operation_mode == OperationMode.AIMING_PRIMARY:
		_queue_primary_auto_suspend(false)
	operation_mode = OperationMode.NORMAL
	skill_target_type = ""
	_push_message("已取消当前操作")


func _toggle_route_placement() -> void:
	if selected_unit_id.is_empty(): return
	if operation_mode == OperationMode.PLACING_ROUTE:
		operation_mode = OperationMode.NORMAL
		_push_message("路径布置结束")
		return
	if operation_mode != OperationMode.NORMAL:
		_cancel_operation_mode()
	operation_mode = OperationMode.PLACING_ROUTE
	_push_message("路径布置：左键连续添加途径点，Z 或 Esc 结束")


func _append_route_waypoint(world_position: Vector2) -> void:
	if selected_unit_id.is_empty(): return
	session.queue_command({
		"command_id": "ui.waypoint.%s.%s" % [session.state["tick_index"], Time.get_ticks_msec()],
		"command_type": "AppendMoveWaypoint",
		"issued_at_tick": session.state["tick_index"],
		"issuer_id": "player",
		"unit_id": selected_unit_id,
		"target_position": world_position,
	})


func _toggle_control_state(control_field: String, display_name: String, fleet_scope: bool) -> void:
	if selected_unit_id.is_empty(): return
	var unit_ids: Array = []
	if fleet_scope:
		for slot_data in session.get_player_slots():
			var fleet_unit_id := str(slot_data["unit_id"])
			var fleet_unit: Dictionary = session.state.get("units_by_id", {}).get(fleet_unit_id, {})
			if fleet_unit.get("life_state", "") == "Alive":
				unit_ids.append(fleet_unit_id)
	else:
		unit_ids = [selected_unit_id]
	unit_ids.sort()
	var enable := false
	for unit_id in unit_ids:
		var unit: Dictionary = session.state.get("units_by_id", {}).get(unit_id, {})
		if not bool(unit.get(control_field, false)):
			enable = true
			break
	var command := {
		"command_id": "ui.control.%s.%s" % [control_field, session.state["tick_index"]],
		"command_type": "SetUnitControlState",
		"issued_at_tick": session.state["tick_index"],
		"issuer_id": "player",
		"unit_ids": unit_ids,
	}
	command[control_field] = enable
	session.queue_command(command)
	_push_message("%s%s：%s" % ["全舰 " if fleet_scope else "", display_name, "开启" if enable else "关闭"])


func _queue_primary_auto_suspend(suspended: bool) -> void:
	if selected_unit_id.is_empty(): return
	session.queue_command({
		"command_id": "ui.control.primary_suspend.%s.%s" % [session.state["tick_index"], int(suspended)],
		"command_type": "SetUnitControlState",
		"issued_at_tick": session.state["tick_index"],
		"issuer_id": "player",
		"unit_id": selected_unit_id,
		"primary_auto_fire_suspended": suspended,
	})


func _unit_at(world_position: Vector2, snapshot: Dictionary) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for unit in snapshot["units"].values():
		var distance := CollisionGeometryService.normalized_distance(world_position, unit["position"], float(unit["heading"]), CollisionGeometryService.half_extents(unit), 8.0)
		if distance <= 1.0 and distance < nearest_distance:
			nearest = unit
			nearest_distance = distance
	return nearest


func _consume_events(events: Array) -> void:
	if effect_director != null:
		effect_director.consume_events(events, session)
	terrain_debug_overlay.record_events(events)
	for event in events:
		match event.get("event_type", ""):
			"UnitSunk": _push_message("%s 已沉没" % _unit_display_name(str(event.get("unit_id", ""))))
			"SkillCast": _push_message("%s 释放了 %s" % [_unit_display_name(str(event.get("unit_id", ""))), _skill_display_name(str(event.get("skill_id", "")))])
			"MineTriggered": _push_message("%s 触发水雷，受到 %.0f 伤害" % [_unit_display_name(str(event.get("unit_id", ""))), float(event.get("damage", 0.0))])
			"FacilitySuppressed": _push_message("岸基设施已被压制")
			"FacilityRecovered": _push_message("岸基设施恢复运行")
			"FacilityDestroyed": _push_message("岸基设施已被摧毁")
			"UnitServiced": _push_message("%s 完成%s" % [_unit_display_name(str(event.get("unit_id", ""))), "维修" if event.get("service_type", "") == "Repair" else "补给"])
			"SupportMissionResolved": _push_message("岸基航空支援已抵达")
			"BattleFinished":
				result_character_id = _random_player_character_id()
				_push_message("战斗结束，胜利阵营：%s" % UiText.faction_name(str(event.get("result", {}).get("winner_faction", ""))))


func _unit_display_name(unit_id: String) -> String:
	var unit: Dictionary = session.state.get("units_by_id", {}).get(unit_id, {})
	return str(unit.get("display_name", "未知单位"))


func _skill_display_name(skill_id: String) -> String:
	var skill: Dictionary = DataRegistry.registry.get_definition("skills", skill_id)
	return str(skill.get("display_name", "未知技能"))


func _push_message(message: String) -> void:
	recent_messages.push_front(message)
	if recent_messages.size() > 5: recent_messages.resize(5)


func _start_battle(new_level_id: String) -> void:
	session = BattleSession.new(DataRegistry.registry)
	var result: Dictionary = session.create_battle(new_level_id, 20260614)
	if not result.get("ok", false):
		push_error("Battle creation failed: %s" % result.get("errors", []))
		return
	accumulator = 0.0
	selected_unit_id = ""
	selected_facility_id = ""
	focused_target_id = ""
	result_character_id = ""
	operation_mode = OperationMode.NORMAL
	skill_target_type = ""
	gun_scope_confirmation_started_msec = 0
	gun_scope_confirmation_until_msec = 0
	camera_mode = "Manual"
	camera_follow_unit_id = ""
	recent_messages.clear()
	if effect_director != null:
		effect_director.clear()
	var map_data: Dictionary = session.state.get("map", {})
	current_palette_id = str(map_data.get("ocean_palette", "day_clear"))
	var map_size := Vector2(float(map_data.get("width", 4096.0)), float(map_data.get("height", 2304.0)))
	ocean_surface.configure(map_size, current_palette_id)
	weather_overlay.configure(map_size, current_palette_id)
	terrain_view.configure(session.state.get("terrain_map", {}), DataRegistry.assets)
	terrain_debug_overlay.configure(session.state.get("terrain_map", {}), session.terrain_query.debug_spatial_cells())
	_configure_camera_limits(map_data)
	_configure_camera_zoom(map_data)
	_select_slot(1)
	battle_camera.position = _player_fleet_center()
	battle_camera.reset_smoothing()
	_clamp_camera_to_map()
	_update_hud()
	_sync_visuals()
	queue_redraw()


func _sync_visuals() -> void:
	if effect_director == null or session == null or session.state.is_empty():
		return
	var snapshot: Dictionary = session.snapshot("player", terrain_debug_overlay.visible)
	effect_director.sync_snapshot(snapshot, selected_unit_id, focused_target_id)
	terrain_view.sync_dynamic(snapshot.get("environment_zones", []), snapshot.get("facilities", {}), snapshot.get("minefields", {}), snapshot.get("support_effects", {}))
	terrain_debug_overlay.sync_runtime(snapshot.get("terrain_contexts", {}), snapshot.get("facilities", {}), selected_unit_id)


func _configure_camera_limits(map_data: Dictionary) -> void:
	battle_camera.limit_left = 0
	battle_camera.limit_top = 0
	battle_camera.limit_right = int(float(map_data.get("width", 4096.0)))
	battle_camera.limit_bottom = int(float(map_data.get("height", 2304.0)))


func _player_fleet_center() -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for unit in session.state.get("units_by_id", {}).values():
		if unit.get("faction_id", "") != "player" or unit.get("life_state", "") != "Alive": continue
		total += unit["position"]
		count += 1
	return total / float(maxi(count, 1))


func _set_ocean_palette(palette_id: String) -> void:
	current_palette_id = palette_id
	ocean_surface.set_palette(palette_id)
	weather_overlay.set_palette(palette_id)
	_update_hud()


func _update_hud() -> void:
	if session == null or session.state.is_empty(): return
	var selected_name := "未选择"
	var selected: Dictionary = session.state.get("units_by_id", {}).get(selected_unit_id, {})
	if not selected.is_empty(): selected_name = str(selected.get("display_name", selected_unit_id))
	var snapshot: Dictionary = session.snapshot("player", terrain_debug_overlay.visible)
	var half_view := _camera_visible_size() * 0.5
	snapshot["camera_rect"] = Rect2(battle_camera.position - half_view, half_view * 2.0)
	snapshot["selected_unit_id"] = selected_unit_id
	snapshot["selected_facility_id"] = selected_facility_id
	snapshot["facility_action_status"] = session.get_facility_action_status(selected_unit_id, selected_facility_id) if not selected_unit_id.is_empty() and not selected_facility_id.is_empty() else {}
	snapshot["focused_target_id"] = focused_target_id
	if not snapshot.get("result", {}).is_empty():
		if result_character_id.is_empty():
			result_character_id = _random_player_character_id()
		snapshot["result_character_id"] = result_character_id
	battle_hud.update_state(snapshot, level_id, recent_messages, camera_mode, selected_name, current_palette_id, session.get_operation_status(selected_unit_id), _operation_mode_name(), session.get_player_slots())


func _operation_mode_name() -> String:
	match operation_mode:
		OperationMode.AIMING_PRIMARY: return "AIMING_PRIMARY"
		OperationMode.TARGETING_SKILL: return "TARGETING_SKILL"
		OperationMode.PLACING_ROUTE: return "PLACING_ROUTE"
		_: return "NORMAL"


func _random_player_character_id() -> String:
	var candidates: Array[String] = []
	for unit in session.state.get("units_by_id", {}).values():
		if str(unit.get("faction_id", "")) != "player": continue
		var slug := str(unit.get("definition_id", "")).trim_prefix("ship.")
		if not slug.is_empty(): candidates.append(slug)
	if candidates.is_empty(): return "warspite"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _restart_battle() -> void:
	_start_battle(level_id)


func _return_to_main_menu() -> void:
	var error := get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	if error != OK:
		push_error("Could not return to main menu: %s" % error)
