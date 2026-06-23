extends Node2D

const BattleSession = preload("res://scripts/application/battle_session.gd")
const BattleEffectDirector = preload("res://scripts/presentation/battle/battle_effect_director.gd")
const UiText = preload("res://scripts/presentation/ui_text.gd")

const MAIN_MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const FIXED_STEP := 0.1
const CAMERA_SPEED := 900.0
const CAMERA_EDGE_MARGIN := 28.0
const CAMERA_FOLLOW_DAMPING := 7.5
const UI_ASSET_ROOT := "res://assets/ui/export/2x"
const DEFAULT_UNIT_SCALE := 0.28

enum OperationMode { NORMAL, AIMING_PRIMARY, TARGETING_SKILL }

@onready var ocean_surface: Node2D = $OceanSurface
@onready var battle_camera: Camera2D = $BattleCamera
@onready var battle_hud: Control = $HUD/BattleHud

var session
var level_id := "level.prototype_3v3"
var accumulator := 0.0
var selected_unit_id := ""
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
	ocean_surface.set_animation_paused(session.state.get("phase", "") == "Paused")
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
	draw_circle(position, radius + 12.0, Color(0.02, 0.08, 0.12, 0.28))
	_draw_unit_art(unit, color)
	draw_arc(position, radius, 0.0, TAU, 40, Color(0.86, 0.97, 1.0, 0.45), 1.5)
	var heading_vector := Vector2.RIGHT.rotated(float(unit["heading"]))
	draw_line(position, position + heading_vector * (radius + 34.0), Color(1.0, 1.0, 1.0, 0.75), 2.5)
	if unit["entity_id"] == selected_unit_id:
		_draw_icon_centered("ui_marker_selected", position, 0.85, Color.WHITE)
		draw_arc(position, radius + 19.0, 0.0, TAU, 40, Color("#f8ef9a"), 3.0)
	if unit["entity_id"] == focused_target_id:
		_draw_icon_centered("ui_marker_target", position, 0.9, Color.WHITE)
		draw_arc(position, radius + 25.0, 0.0, TAU, 40, Color("#ffb35c"), 3.0)
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
	var scales := _unit_art_scales(visuals, radius)
	var life_state := str(unit.get("life_state", "Alive"))
	var tint := Color(1.0, 1.0, 1.0, 1.0)
	if life_state == "Sunk":
		tint = Color(0.5, 0.58, 0.62, 0.65)
	if visuals.get("rig") != null:
		_draw_texture_centered(visuals["rig"], position, rotation, scales["rig"], tint)
	if visuals.get("body") != null:
		_draw_texture_centered(visuals["body"], position, rotation, scales["body"], tint)
	if visuals.get("rig") == null and visuals.get("body") == null:
		draw_circle(position, radius, fallback_color)


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


func _unit_art_scales(visuals: Dictionary, radius: float) -> Dictionary:
	var body_texture: Texture2D = visuals.get("body", null)
	var rig_texture: Texture2D = visuals.get("rig", null)
	var body_scale := DEFAULT_UNIT_SCALE
	var rig_scale := DEFAULT_UNIT_SCALE
	if body_texture != null:
		var body_target_width := clampf(radius * 3.8, 84.0, 126.0)
		body_scale = body_target_width / maxf(1.0, float(body_texture.get_width()))
	if rig_texture != null:
		var rig_target_width := clampf(radius * 5.0, 108.0, 162.0)
		rig_scale = rig_target_width / maxf(1.0, float(rig_texture.get_width()))
	else:
		rig_scale = body_scale
	return {"body": body_scale, "rig": rig_scale}


func _texture(path: String) -> Texture2D:
	if texture_cache.has(path): return texture_cache[path]
	var resource := load(path)
	texture_cache[path] = resource if resource is Texture2D else null
	return texture_cache[path]


func _draw_operation_overlay() -> void:
	if selected_unit_id.is_empty() or operation_mode == OperationMode.NORMAL: return
	var selected: Dictionary = session.state.get("units_by_id", {}).get(selected_unit_id, {})
	if selected.is_empty(): return
	var cursor := get_global_mouse_position()
	if operation_mode == OperationMode.AIMING_PRIMARY:
		var aim_status: Dictionary = session.get_primary_aim_status(selected_unit_id, cursor)
		var legal: bool = bool(aim_status.get("legal", false))
		var color := Color(0.25, 1.0, 0.55, 0.75) if legal else Color(1.0, 0.25, 0.2, 0.75)
		var range_value := float(aim_status.get("range", 0.0))
		if aim_status.get("control_type", "") == "Direction" and aim_status.get("weapon_type", "") == "Torpedo":
			_draw_torpedo_aim_overlay(selected, cursor, aim_status)
		elif aim_status.get("control_type", "") == "Direction":
			draw_arc(selected["position"], range_value, 0.0, TAU, 96, color, 2.0)
			draw_line(selected["position"], cursor, color, 2.0)
		else:
			draw_arc(selected["position"], range_value, 0.0, TAU, 96, color, 2.0)
			draw_line(selected["position"], cursor, color, 2.0)
			draw_circle(cursor, 42.0, Color(color.r, color.g, color.b, 0.12))
			draw_arc(cursor, 42.0, 0.0, TAU, 36, color, 2.0)
		draw_string(ThemeDB.fallback_font, cursor + Vector2(18.0, -18.0), UiText.reason_name(str(aim_status.get("reason_code", "OK"))), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, color)
	elif operation_mode == OperationMode.TARGETING_SKILL:
		var color := Color(0.45, 0.75, 1.0, 0.75)
		draw_circle(cursor, 48.0, Color(color.r, color.g, color.b, 0.12))
		draw_arc(cursor, 48.0, 0.0, TAU, 36, color, 2.0)
		draw_string(ThemeDB.fallback_font, cursor + Vector2(18.0, -18.0), "技能目标：%s" % UiText.target_type_name(skill_target_type), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, color)


func _draw_torpedo_aim_overlay(selected: Dictionary, cursor: Vector2, aim_status: Dictionary) -> void:
	var origin: Vector2 = selected["position"]
	var maximum_range := float(aim_status.get("range", 0.0))
	var invalid_color := Color(1.0, 0.18, 0.16, 0.075)
	var invalid_edge := Color(1.0, 0.24, 0.2, 0.72)
	var valid_color := Color(0.18, 1.0, 0.48, 0.16)
	var valid_edge := Color(0.28, 1.0, 0.55, 0.86)
	draw_circle(origin, maximum_range, invalid_color)
	draw_arc(origin, maximum_range, 0.0, TAU, 128, invalid_edge, 2.0)
	for arc in aim_status.get("fire_arcs", []):
		var center_angle := float(selected.get("heading", 0.0)) + deg_to_rad(float(arc.get("center", 0.0)))
		var half_angle := deg_to_rad(float(arc.get("degrees", 0.0))) * 0.5
		var minimum_range := float(arc.get("minimum_range", 0.0))
		var arc_range := float(arc.get("range", maximum_range))
		_draw_annular_sector(origin, minimum_range, arc_range, center_angle - half_angle, center_angle + half_angle, valid_color)
		draw_arc(origin, arc_range, center_angle - half_angle, center_angle + half_angle, 36, valid_edge, 2.0)
		draw_line(origin + Vector2.RIGHT.rotated(center_angle - half_angle) * minimum_range, origin + Vector2.RIGHT.rotated(center_angle - half_angle) * arc_range, valid_edge, 1.5)
		draw_line(origin + Vector2.RIGHT.rotated(center_angle + half_angle) * minimum_range, origin + Vector2.RIGHT.rotated(center_angle + half_angle) * arc_range, valid_edge, 1.5)
	var selected_heading := (cursor - origin).angle()
	var selected_range := float(aim_status.get("selected_range", maximum_range))
	var spread_half_angle := deg_to_rad(float(aim_status.get("spread_degrees", 0.0))) * 0.5
	var white := Color(1.0, 1.0, 1.0, 0.95)
	draw_line(origin, origin + Vector2.RIGHT.rotated(selected_heading) * selected_range, white, 2.5)
	draw_line(origin, origin + Vector2.RIGHT.rotated(selected_heading - spread_half_angle) * selected_range, white, 1.5)
	draw_line(origin, origin + Vector2.RIGHT.rotated(selected_heading + spread_half_angle) * selected_range, white, 1.5)
	draw_arc(origin, selected_range, selected_heading - spread_half_angle, selected_heading + spread_half_angle, 16, white, 1.5)


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
			KEY_SPACE:
				if session.state["phase"] == "Paused": session.resume()
				else: session.pause()
			KEY_R: _start_battle(level_id)
			KEY_E: _begin_primary_aim()
			KEY_Q: _switch_selected_ammo()
			KEY_F: _begin_or_cast_skill()
			KEY_V: _toggle_follow_selected()
			KEY_ESCAPE: _cancel_operation_mode()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_camera_zoom(float(camera_settings.get("zoom_step", 1.0)), event.position)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_camera_zoom(1.0 / float(camera_settings.get("zoom_step", 1.0)), event.position)
			return
		var snapshot: Dictionary = session.snapshot("player", false)
		var world_position := get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if operation_mode == OperationMode.AIMING_PRIMARY: _confirm_primary_aim(world_position)
			elif operation_mode == OperationMode.TARGETING_SKILL: _confirm_skill_target(world_position, snapshot)
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
		selected_unit_id = str(slot_data["unit_id"])
		operation_mode = OperationMode.NORMAL
		if camera_mode == "Follow": camera_follow_unit_id = selected_unit_id
		_push_message("已选择 %d 号角色：%s" % [slot, slot_data.get("display_name", selected_unit_id)])
		return
	_push_message("%d 号角色不可用" % slot)


func _select_at(world_position: Vector2, snapshot: Dictionary) -> void:
	var nearest: Dictionary = {}
	var nearest_distance := 48.0
	for unit in snapshot["units"].values():
		var distance := (unit["position"] as Vector2).distance_to(world_position)
		if distance < nearest_distance:
			nearest = unit
			nearest_distance = distance
	if nearest.is_empty(): return
	if nearest["faction_id"] == "player":
		selected_unit_id = nearest["entity_id"]
		if camera_mode == "Follow": camera_follow_unit_id = selected_unit_id
	else:
		focused_target_id = nearest["entity_id"]
		if not selected_unit_id.is_empty(): session.queue_command({"command_id": "ui.focus.%s" % session.state["tick_index"], "command_type": "FocusTarget", "issued_at_tick": session.state["tick_index"], "issuer_id": "player", "unit_id": selected_unit_id, "target_unit_id": focused_target_id})


func _begin_primary_aim() -> void:
	if selected_unit_id.is_empty(): return
	var selected: Dictionary = session.state["units_by_id"].get(selected_unit_id, {})
	if selected.is_empty(): return
	var operation_status: Dictionary = session.get_operation_status(selected_unit_id)
	if not bool(operation_status.get("primary_ready", false)):
		_push_message("E 不可用：%s" % UiText.reason_name(str(operation_status.get("primary_reason", "PRIMARY_WEAPON_UNAVAILABLE"))))
		return
	operation_mode = OperationMode.AIMING_PRIMARY
	_push_message("正在瞄准：%s" % operation_status.get("primary_name", "主要武器"))


func _confirm_primary_aim(world_position: Vector2) -> void:
	if selected_unit_id.is_empty(): return
	var aim_status: Dictionary = session.get_primary_aim_status(selected_unit_id, world_position)
	if not bool(aim_status.get("legal", false)):
		_push_message("主要武器无法发射：%s" % UiText.reason_name(str(aim_status.get("reason_code", "INVALID_TARGET"))))
		return
	session.queue_command({"command_id": "ui.primary.%s" % session.state["tick_index"], "command_type": "FirePrimaryWeapon", "issued_at_tick": session.state["tick_index"], "issuer_id": "player", "unit_id": selected_unit_id, "target_position": world_position})
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
		_push_message("请选择技能目标：%s" % UiText.target_type_name(skill_target_type))


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
	operation_mode = OperationMode.NORMAL
	skill_target_type = ""
	_push_message("已取消当前操作")


func _unit_at(world_position: Vector2, snapshot: Dictionary) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := 48.0
	for unit in snapshot["units"].values():
		var distance := (unit["position"] as Vector2).distance_to(world_position)
		if distance < nearest_distance:
			nearest = unit
			nearest_distance = distance
	return nearest


func _consume_events(events: Array) -> void:
	if effect_director != null:
		effect_director.consume_events(events, session)
	for event in events:
		match event.get("event_type", ""):
			"UnitSunk": _push_message("%s 已沉没" % _unit_display_name(str(event.get("unit_id", ""))))
			"SkillCast": _push_message("%s 释放了 %s" % [_unit_display_name(str(event.get("unit_id", ""))), _skill_display_name(str(event.get("skill_id", "")))])
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
	focused_target_id = ""
	result_character_id = ""
	operation_mode = OperationMode.NORMAL
	skill_target_type = ""
	camera_mode = "Manual"
	camera_follow_unit_id = ""
	recent_messages.clear()
	if effect_director != null:
		effect_director.clear()
	var map_data: Dictionary = session.state.get("map", {})
	current_palette_id = str(map_data.get("ocean_palette", "day_clear"))
	ocean_surface.configure(Vector2(float(map_data.get("width", 4096.0)), float(map_data.get("height", 2304.0))), current_palette_id)
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
	effect_director.sync_snapshot(session.snapshot("player", false), selected_unit_id, focused_target_id)


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
	_update_hud()


func _update_hud() -> void:
	if session == null or session.state.is_empty(): return
	var selected_name := "未选择"
	var selected: Dictionary = session.state.get("units_by_id", {}).get(selected_unit_id, {})
	if not selected.is_empty(): selected_name = str(selected.get("display_name", selected_unit_id))
	var snapshot: Dictionary = session.snapshot("player", false)
	var half_view := _camera_visible_size() * 0.5
	snapshot["camera_rect"] = Rect2(battle_camera.position - half_view, half_view * 2.0)
	snapshot["selected_unit_id"] = selected_unit_id
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
