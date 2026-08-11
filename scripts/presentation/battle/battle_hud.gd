extends Control

signal return_to_menu_requested
signal restart_requested

const UiText = preload("res://scripts/presentation/ui_text.gd")
const UI_ASSET_ROOT := "res://assets/ui/export/2x"
const PANEL_FILL := Color(0.93, 0.98, 1.0, 0.88)
const PANEL_STROKE := Color(0.48, 0.82, 0.95, 0.62)
const TEXT_DARK := Color("#123443")
const TEXT_SOFT := Color("#5d8793")
const FRIEND_COLOR := Color("#58c7ff")
const ENEMY_COLOR := Color("#ff7d74")

var snapshot := {}
var level_id := ""
var recent_messages: Array[String] = []
var camera_mode := "Manual"
var selected_name := "未选择"
var palette_id := "day_clear"
var operation_status := {}
var operation_mode := "NORMAL"
var player_slots: Array = []
var texture_cache: Dictionary = {}
var return_button: Button
var restart_button: Button


func _ready() -> void:
	_create_result_buttons()


func update_state(new_snapshot: Dictionary, new_level_id: String, messages: Array[String], new_camera_mode: String, new_selected_name: String, new_palette_id: String, new_operation_status: Dictionary = {}, new_operation_mode: String = "NORMAL", new_player_slots: Array = []) -> void:
	snapshot = new_snapshot
	level_id = new_level_id
	recent_messages = messages.duplicate()
	camera_mode = new_camera_mode
	selected_name = new_selected_name
	palette_id = new_palette_id
	operation_status = new_operation_status.duplicate(true)
	operation_mode = new_operation_mode
	player_slots = new_player_slots.duplicate(true)
	_sync_result_buttons()
	queue_redraw()


func _draw() -> void:
	if snapshot.is_empty(): return
	var viewport_size := size
	_draw_top_status(viewport_size)
	_draw_level_objective(viewport_size)
	_draw_fleet_panel(Rect2(Vector2(28.0, 18.0), Vector2(596.0, 142.0)), true)
	_draw_fleet_panel(Rect2(Vector2(viewport_size.x - 624.0, 18.0), Vector2(596.0, 142.0)), false)
	_draw_operation_dock(Rect2(Vector2((viewport_size.x - 900.0) * 0.5, viewport_size.y - 154.0), Vector2(900.0, 128.0)))
	_draw_minimap(Rect2(Vector2(28.0, viewport_size.y - 266.0), Vector2(330.0, 226.0)))
	_draw_log_panel(Rect2(Vector2(viewport_size.x - 380.0, 206.0), Vector2(352.0, 300.0)))
	_draw_selected_panel(Rect2(Vector2(viewport_size.x - 380.0, viewport_size.y - 286.0), Vector2(352.0, 246.0)))
	if snapshot.get("phase", "") == "Paused":
		_draw_pause_panel(viewport_size)
	if not snapshot.get("result", {}).is_empty():
		_draw_result_panel(viewport_size)


func _draw_top_status(viewport_size: Vector2) -> void:
	var panel := Rect2(Vector2((viewport_size.x - 560.0) * 0.5, 18.0), Vector2(560.0, 74.0))
	_draw_panel(panel, "")
	var phase := str(snapshot.get("phase", ""))
	var title := "%s  |  %.1f 秒  |  %s" % [UiText.mode_name(level_id), float(snapshot.get("elapsed_time", 0.0)), UiText.phase_name(phase)]
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(24.0, 32.0), "小小海战", HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 48.0, 22, TEXT_DARK)
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(24.0, 58.0), title, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 48.0, 18, TEXT_SOFT)
	_draw_icon("ui_icon_pause" if phase == "Running" else "ui_icon_continue", Rect2(panel.position + Vector2(panel.size.x - 58.0, 18.0), Vector2(36.0, 36.0)))


func _draw_level_objective(viewport_size: Vector2) -> void:
	var objective: Dictionary = snapshot.get("level_objective", {})
	if objective.is_empty(): return
	var tutorial := bool(objective.get("is_tutorial", false))
	var panel_height := 82.0 if tutorial else 54.0
	var panel := Rect2(Vector2((viewport_size.x - 620.0) * 0.5, 100.0), Vector2(620.0, panel_height))
	_draw_panel(panel, "")
	var status := str(objective.get("status", "Active"))
	var prefix := "教学" if tutorial else "任务"
	var text := "%s · %s：%s" % [prefix, objective.get("title", ""), objective.get("summary", "")]
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(18.0, 34.0), text, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 36.0, 17, TEXT_DARK if status == "Active" else Color("#35c99a"))
	if tutorial:
		var instruction := "当前操作：%s" % objective.get("instruction", "")
		draw_string(ThemeDB.fallback_font, panel.position + Vector2(18.0, 59.0), instruction, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 36.0, 16, Color("#225f73"))
		var limit_text := str(objective.get("ability_limit_text", ""))
		if not limit_text.is_empty():
			draw_string(ThemeDB.fallback_font, panel.position + Vector2(18.0, 78.0), limit_text, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 36.0, 13, TEXT_SOFT)


func _draw_fleet_panel(rect: Rect2, friendly: bool) -> void:
	_draw_panel(rect, "己方舰队" if friendly else "敌方舰队")
	var origin := rect.position + Vector2(16.0, 36.0)
	var cell_size := Vector2(88.0, 44.0)
	var gap := Vector2(8.0, 10.0)
	var entries: Array = _friendly_entries() if friendly else _enemy_entries()
	for index in range(12):
		var col := index % 6
		var row := int(index / 6)
		var cell := Rect2(origin + Vector2(col * (cell_size.x + gap.x), row * (cell_size.y + gap.y)), cell_size)
		var entry: Dictionary = entries[index] if index < entries.size() else {}
		_draw_roster_cell(cell, entry, index + 1, friendly)


func _draw_roster_cell(rect: Rect2, entry: Dictionary, slot_number: int, friendly: bool) -> void:
	var alive := str(entry.get("life_state", "Alive")) != "Sunk"
	var selected := str(entry.get("unit_id", entry.get("entity_id", ""))) == str(snapshot.get("selected_unit_id", ""))
	var base := Color(0.82, 0.94, 0.98, 0.92) if friendly else Color(0.98, 0.86, 0.84, 0.9)
	if entry.is_empty(): base = Color(0.17, 0.27, 0.33, 0.52)
	if selected: base = Color(1.0, 0.94, 0.48, 0.95)
	draw_rect(rect, base, true)
	draw_rect(rect, PANEL_STROKE if not selected else Color("#f8ef9a"), false, 2.0)
	if entry.is_empty():
		_draw_icon("ui_icon_unknown_contact", Rect2(rect.position + Vector2(8.0, 6.0), Vector2(32.0, 32.0)), Color(1.0, 1.0, 1.0, 0.55))
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(47.0, 28.0), "--", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 50.0, 14, TEXT_SOFT)
		return
	var portrait_rect := Rect2(rect.position + Vector2(4.0, 4.0), Vector2(36.0, 36.0))
	_draw_portrait(entry, portrait_rect, Color(1.0, 1.0, 1.0, 1.0 if alive else 0.42))
	var class_icon := _class_icon_name(str(entry.get("ship_class", "")))
	if not class_icon.is_empty():
		_draw_icon(class_icon, Rect2(rect.position + Vector2(rect.size.x - 23.0, 4.0), Vector2(18.0, 18.0)))
	if bool(entry.get("is_flagship", false)):
		_draw_icon("ui_icon_flagship", Rect2(rect.position + Vector2(25.0, 25.0), Vector2(16.0, 16.0)))
	var label := "%d %s" % [int(entry.get("slot", entry.get("operation_slot", slot_number))), _short_name(str(entry.get("display_name", "?")))]
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(45.0, 21.0), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 70.0, 13, TEXT_DARK if alive else TEXT_SOFT)
	_draw_hp_bar(Rect2(rect.position + Vector2(45.0, 29.0), Vector2(rect.size.x - 52.0, 6.0)), float(entry.get("current_hp", 0.0)), float(entry.get("max_hp", 1.0)), friendly)


func _draw_operation_dock(rect: Rect2) -> void:
	_draw_panel(rect, "")
	var title := "选中：%s  |  镜头：%s  |  操作：%s  |  海域：%s" % [selected_name, UiText.camera_mode_name(camera_mode), UiText.operation_mode_name(operation_mode), UiText.palette_name(palette_id)]
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(22.0, 24.0), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 44.0, 17, TEXT_DARK)
	var cards := [
		{"key": "E", "icon": "ui_icon_gunfire", "text": _primary_text(), "ready": bool(operation_status.get("primary_ready", false))},
		{"key": "Q", "icon": "ui_icon_confirm", "text": _ammo_text(), "ready": bool(operation_status.get("q_enabled", false))},
		{"key": "F", "icon": "ui_icon_skill_ready", "text": _skill_text(), "ready": bool(operation_status.get("skill_ready", false))},
		{"key": "G", "icon": "ui_icon_camera_follow", "text": "开始跟随" if camera_mode != "Follow" else "正在跟随", "ready": true},
		{"key": "Z", "icon": "ui_marker_path_endpoint", "text": "结束路径" if operation_mode == "PLACING_ROUTE" else "连续路径", "ready": true},
		{"key": "X", "icon": "ui_icon_auto_move", "text": "自动航行 开" if bool(operation_status.get("movement_assist_enabled", false)) else "自动航行 关", "ready": bool(operation_status.get("movement_assist_enabled", false))},
		{"key": "C", "icon": "ui_icon_auto_weapon", "text": _c_action_text(), "ready": _c_action_ready()},
		{"key": "V", "icon": "ui_icon_gunfire", "text": "主武器 开" if bool(operation_status.get("primary_auto_fire_enabled", false)) else "主武器 关", "ready": bool(operation_status.get("primary_auto_fire_enabled", false))},
	]
	for index in range(cards.size()):
		var column := index % 4
		var row := int(index / 4)
		var card_rect := Rect2(rect.position + Vector2(22.0 + column * 214.0, 38.0 + row * 42.0), Vector2(198.0, 36.0))
		_draw_action_card(card_rect, cards[index])


func _c_action_text() -> String:
	if str(operation_status.get("ship_class", "")) != "Submarine":
		return "副武器 开" if bool(operation_status.get("secondary_auto_fire_enabled", true)) else "副武器 关"
	var transition: Dictionary = operation_status.get("depth_transition", {})
	if bool(transition.get("active", false)):
		return "%s中 %.1fs" % ["上浮" if transition.get("target_depth_state", "") == "Surface" else "下潜", float(transition.get("remaining", 0.0))]
	var oxygen: Dictionary = operation_status.get("oxygen_state", {})
	var target_label := "上浮" if operation_status.get("depth_change_target", "Surface") == "Surface" else "下潜"
	return "%s  氧 %.0f/%.0f" % [target_label, float(oxygen.get("current", 0.0)), float(oxygen.get("maximum", 0.0))]


func _c_action_ready() -> bool:
	if str(operation_status.get("ship_class", "")) != "Submarine":
		return bool(operation_status.get("secondary_auto_fire_enabled", true))
	return bool(operation_status.get("depth_change_available", false))


func _draw_action_card(rect: Rect2, card: Dictionary) -> void:
	var ready := bool(card.get("ready", false))
	draw_rect(rect, Color(0.82, 0.95, 0.98, 0.95) if ready else Color(0.7, 0.78, 0.82, 0.82), true)
	draw_rect(rect, Color("#5ac7df") if ready else Color("#8fa8b1"), false, 1.5)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(10.0, 24.0), str(card.get("key", "")), HORIZONTAL_ALIGNMENT_LEFT, 24.0, 18, TEXT_DARK)
	_draw_icon(str(card.get("icon", "")), Rect2(rect.position + Vector2(34.0, 7.0), Vector2(22.0, 22.0)), Color.WHITE if ready else Color(1.0, 1.0, 1.0, 0.55))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(64.0, 23.0), str(card.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 72.0, 14, TEXT_DARK if ready else TEXT_SOFT)


func _draw_minimap(rect: Rect2) -> void:
	_draw_panel(rect, "战术地图")
	var map_rect := Rect2(rect.position + Vector2(14.0, 36.0), rect.size - Vector2(28.0, 52.0))
	draw_rect(map_rect, Color(0.08, 0.34, 0.46, 0.72), true)
	draw_rect(map_rect, Color(0.84, 0.98, 1.0, 0.52), false, 1.5)
	var map_data: Dictionary = snapshot.get("map", {})
	_draw_minimap_terrain(map_rect, map_data)
	_draw_minimap_environment_zones(map_rect, map_data)
	_draw_minimap_minefields(map_rect, map_data)
	for facility in snapshot.get("facilities", {}).values():
		var facility_position := _minimap_position(facility.get("position", Vector2.ZERO), map_rect, map_data)
		var facility_icon := "ui_marker_facility_%s" % str(facility.get("asset_semantic", ""))
		_draw_icon(facility_icon, Rect2(facility_position - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), Color(1.0, 1.0, 1.0, 0.86))
		if str(facility.get("facility_id", "")) == str(snapshot.get("selected_facility_id", "")): draw_arc(facility_position, 11.0, 0.0, TAU, 20, Color("#f8ef9a"), 2.0)
	for unit in snapshot.get("units", {}).values():
		var friendly := str(unit.get("faction_id", "")) == "player"
		var position := _minimap_position(unit.get("position", Vector2.ZERO), map_rect, map_data)
		var icon_name := _minimap_icon(unit, friendly)
		_draw_icon(icon_name, Rect2(position - Vector2(7.0, 7.0), Vector2(14.0, 14.0)))
	for contact in snapshot.get("contacts", {}).values():
		var contact_position := _minimap_position(contact.get("last_known_position", Vector2.ZERO), map_rect, map_data)
		var contact_color := Color(0.35, 0.9, 1.0, 0.9) if contact.get("primary_contact_type", "") == "Radar" else Color(1.0, 0.72, 0.72, 0.8)
		_draw_icon("ui_icon_unknown_contact", Rect2(contact_position - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), contact_color)
	if snapshot.has("camera_rect"):
		var camera_rect: Rect2 = snapshot["camera_rect"]
		var top_left := _minimap_position(camera_rect.position, map_rect, map_data)
		var bottom_right := _minimap_position(camera_rect.position + camera_rect.size, map_rect, map_data)
		draw_rect(Rect2(top_left, bottom_right - top_left), Color(1.0, 1.0, 1.0, 0.0), false, 1.5)
		_draw_icon("ui_minimap_camera_frame", Rect2(top_left - Vector2(8.0, 8.0), Vector2(16.0, 16.0)), Color(1.0, 1.0, 1.0, 0.8))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(14.0, rect.size.y - 14.0), "A/D/W/S 移动镜头  |  1-0/- 选择角色", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28.0, 13, TEXT_SOFT)


func _draw_minimap_terrain(map_rect: Rect2, map_data: Dictionary) -> void:
	var terrain_id := str(snapshot.get("terrain_map", {}).get("id", ""))
	if terrain_id.is_empty():
		return
	var path := "res://assets/ui/processed/battle/terrain/minimap_%s.png" % terrain_id.replace(".", "_")
	var texture := _texture(path)
	if texture != null:
		draw_texture_rect(texture, map_rect, false, Color(1.0, 1.0, 1.0, 0.9))


func _draw_minimap_environment_zones(map_rect: Rect2, map_data: Dictionary) -> void:
	for zone in snapshot.get("environment_zones", []):
		if not bool(zone.get("active", false)):
			continue
		var points := PackedVector2Array()
		var center := Vector2.ZERO
		for raw_point in zone.get("polygon", []):
			var point: Vector2 = raw_point if raw_point is Vector2 else Vector2(float(raw_point[0]), float(raw_point[1]))
			var minimap_point := _minimap_position(point, map_rect, map_data)
			points.append(minimap_point)
			center += minimap_point
		if points.size() >= 3:
			center /= float(points.size())
			points.append(points[0])
			draw_polyline(points, Color(0.72, 0.9, 0.88, 0.42), 1.0)
			var icon_name := _environment_zone_icon(str(zone.get("effect_id", "")))
			if not icon_name.is_empty():
				_draw_icon(icon_name, Rect2(center - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), Color(1.0, 1.0, 1.0, 0.82))


func _environment_zone_icon(effect_id: String) -> String:
	return {
		"environment.effect.sea_fog": "ui_marker_environment_sea_fog",
		"environment.effect.rain_squall": "ui_marker_environment_rain_squall",
		"environment.effect.high_sea": "ui_marker_environment_high_sea",
		"environment.effect.lee_water": "ui_marker_environment_lee_water",
		"environment.effect.moonlit_lane": "ui_marker_environment_moonlit_lane",
		"environment.effect.strong_current": "ui_marker_environment_strong_current",
		"environment.effect.tidal_water": "ui_marker_environment_tide",
	}.get(effect_id, "")


func _draw_minimap_minefields(map_rect: Rect2, map_data: Dictionary) -> void:
	for minefield in snapshot.get("minefields", {}).values():
		if str(minefield.get("mine_type", "")) == "DeployedMine":
			if str(minefield.get("operation_state", "")) == "Active":
				var mine_position := _minimap_position(minefield.get("position", Vector2.ZERO), map_rect, map_data)
				_draw_icon("ui_marker_minefield_known", Rect2(mine_position - Vector2(5.0, 5.0), Vector2(10.0, 10.0)))
			continue
		var points := PackedVector2Array()
		for raw_point in minefield.get("polygon", []):
			var point: Vector2 = raw_point if raw_point is Vector2 else Vector2(float(raw_point[0]), float(raw_point[1]))
			points.append(_minimap_position(point, map_rect, map_data))
		if points.size() >= 3:
			points.append(points[0])
			draw_polyline(points, Color(1.0, 0.35, 0.28, 0.78), 1.5)
			_draw_icon("ui_marker_minefield_known", Rect2(points[0] - Vector2(6.0, 6.0), Vector2(12.0, 12.0)))
		for safe_channel in minefield.get("safe_channels", []):
			var channel_points := PackedVector2Array()
			for raw_point in safe_channel:
				var channel_point: Vector2 = raw_point if raw_point is Vector2 else Vector2(float(raw_point[0]), float(raw_point[1]))
				channel_points.append(_minimap_position(channel_point, map_rect, map_data))
			if channel_points.size() >= 3:
				channel_points.append(channel_points[0])
				draw_polyline(channel_points, Color(0.38, 1.0, 0.72, 0.78), 1.5)


func _draw_log_panel(rect: Rect2) -> void:
	_draw_panel(rect, "战斗日志")
	var y := rect.position.y + 42.0
	for message in recent_messages:
		_draw_icon("ui_log_contact_enemy" if message.contains("沉没") else "ui_log_last_contact", Rect2(Vector2(rect.position.x + 14.0, y - 17.0), Vector2(18.0, 18.0)))
		draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 40.0, y), message, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 54.0, 15, TEXT_DARK)
		y += 30.0
	if recent_messages.is_empty():
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(18.0, 62.0), "尚无重要战斗事件。", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 15, TEXT_SOFT)


func _draw_selected_panel(rect: Rect2) -> void:
	var facility := _selected_facility()
	if not facility.is_empty():
		_draw_facility_panel(rect, facility)
		return
	_draw_panel(rect, "当前角色")
	var selected := _selected_unit()
	if selected.is_empty():
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(18.0, 64.0), "按 1-9/0/- 或点击地图选择角色。", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 15, TEXT_SOFT)
		return
	_draw_portrait(selected, Rect2(rect.position + Vector2(16.0, 42.0), Vector2(82.0, 82.0)))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(112.0, 62.0), str(selected.get("display_name", "?")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 130.0, 20, TEXT_DARK)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(112.0, 88.0), "%s  编号 %s" % [UiText.ship_class_name(str(selected.get("ship_class", ""))), selected.get("operation_slot", "-")], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 130.0, 15, TEXT_SOFT)
	_draw_hp_bar(Rect2(rect.position + Vector2(112.0, 104.0), Vector2(rect.size.x - 132.0, 10.0)), float(selected.get("current_hp", 0.0)), float(selected.get("max_hp", 1.0)), true)
	var primary := _primary_text()
	var ammo := _ammo_text()
	var skill := _skill_text()
	var control_summary := "航行 %s  |  副武器 %s  |  主武器 %s" % ["开" if bool(operation_status.get("movement_assist_enabled", false)) else "关", "开" if bool(operation_status.get("secondary_auto_fire_enabled", true)) else "关", "开" if bool(operation_status.get("primary_auto_fire_enabled", false)) else "关"]
	if str(operation_status.get("ship_class", "")) == "Submarine":
		var oxygen: Dictionary = operation_status.get("oxygen_state", {})
		var depth_label := "下潜" if operation_status.get("depth_state", "Surface") == "Submerged" else "上浮"
		var transition: Dictionary = operation_status.get("depth_transition", {})
		if bool(transition.get("active", false)): depth_label = "%s中" % ("上浮" if transition.get("target_depth_state", "") == "Surface" else "下潜")
		control_summary = "航行 %s  |  深度 %s  |  氧气 %.0f/%.0f  |  主武器 %s" % ["开" if bool(operation_status.get("movement_assist_enabled", false)) else "关", depth_label, float(oxygen.get("current", 0.0)), float(oxygen.get("maximum", 0.0)), "开" if bool(operation_status.get("primary_auto_fire_enabled", false)) else "关"]
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(18.0, 134.0), control_summary, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 13, TEXT_SOFT)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(18.0, 154.0), "E  %s" % primary, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 15, TEXT_DARK)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(18.0, 178.0), "Q  %s" % ammo, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 15, TEXT_DARK)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(18.0, 202.0), "F  %s" % skill, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 15, TEXT_DARK)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(18.0, 226.0), _skill_description(), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 12, TEXT_SOFT)


func _draw_facility_panel(rect: Rect2, facility: Dictionary) -> void:
	_draw_panel(rect, "设施操作")
	var status: Dictionary = snapshot.get("facility_action_status", {})
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(18.0, 58.0), str(facility.get("display_name", facility.get("facility_id", "?"))), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 20, TEXT_DARK)
	var protection := "可摧毁" if bool(status.get("destroyable", true)) else "不可摧毁·%.0f%%下限" % (float(status.get("damage_floor_ratio", 0.0)) * 100.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(18.0, 82.0), "%s | %s | %s | %s" % [facility.get("faction_id", "neutral"), facility.get("operation_state", "Dormant"), facility.get("interaction_state", "Idle"), protection], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 12, TEXT_SOFT)
	var control_ratio := float(status.get("control_progress_ratio", 0.0))
	var service_ratio := float(status.get("service_progress_ratio", 0.0))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(18.0, 106.0), "控制 %.0f%%  |  服务 %.0f%%  |  泊位 %s" % [control_ratio * 100.0, service_ratio * 100.0, "占用" if not str(status.get("berth_unit_id", "")).is_empty() else "空闲"], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 13, TEXT_DARK)
	var prerequisites := "区域 %s  低速 %s  朝向 %s" % ["✓" if bool(status.get("inside_interaction_water", false)) else "×", "✓" if bool(status.get("berth_speed_ok", false)) else "×", "✓" if bool(status.get("berth_heading_ok", false)) else "×"]
	if float(status.get("mine_control_radius", 0.0)) > 0.0:
		prerequisites = "布雷 %.0f%%  次数 %d  冷却 %.1fs" % [float(status.get("mine_progress_ratio", 0.0)) * 100.0, int(status.get("mine_charges_remaining", 0)), float(status.get("mine_cooldown_remaining", 0.0))]
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(18.0, 130.0), prerequisites, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 13, TEXT_SOFT)
	var interruption := str(status.get("last_interruption_reason", ""))
	var mine_result: Dictionary = status.get("last_mine_deployment_result", {})
	if not mine_result.is_empty():
		interruption = "布雷结果：有效 %d / 失效 %d" % [int(mine_result.get("active_count", 0)), int(mine_result.get("invalid_count", 0))] if mine_result.get("result", "") == "Completed" else "布雷已取消"
	if not interruption.is_empty(): draw_string(ThemeDB.fallback_font, rect.position + Vector2(18.0, 151.0), "上次中断：%s" % interruption, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 12, Color("#a14b4b"))
	var actions := [
		{"key":"H", "icon":"ui_icon_facility_seize", "text":"控制/占领", "ready":status.get("control_ready", false)},
		{"key":"J", "icon":"ui_icon_facility_service_complete", "text":"补给/维修或接近", "ready":status.get("service_ready", false)},
		{"key":"K", "icon":"ui_icon_mission_airstrike", "text":"空袭/⇧巡逻/⌘侦察", "ready":status.get("support_ready", false)},
		{"key":"L", "icon":"ui_marker_minefield_known", "text":"布雷", "ready":status.get("mine_ready", false)},
		{"key":"U", "icon":"ui_icon_facility_service_interrupted", "text":"取消/离泊", "ready":status.get("can_cancel", false)},
	]
	for index in range(actions.size()):
		var column := index % 2
		var row := int(index / 2)
		_draw_action_card(Rect2(rect.position + Vector2(18.0 + column * 158.0, 164.0 + row * 30.0), Vector2(148.0, 26.0)), actions[index])


func _draw_pause_panel(viewport_size: Vector2) -> void:
	var rect := Rect2((viewport_size - Vector2(420.0, 112.0)) * 0.5, Vector2(420.0, 112.0))
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.0, 0.06, 0.1, 0.24), true)
	_draw_panel(rect, "")
	_draw_icon("ui_icon_pause", Rect2(rect.position + Vector2(30.0, 34.0), Vector2(44.0, 44.0)))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(92.0, 60.0), "战斗已暂停", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 120.0, 28, TEXT_DARK)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(92.0, 86.0), "按空格键继续战斗。", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 120.0, 16, TEXT_SOFT)


func _draw_result_panel(viewport_size: Vector2) -> void:
	var rect := Rect2((viewport_size - Vector2(980.0, 620.0)) * 0.5, Vector2(980.0, 620.0))
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.0, 0.06, 0.1, 0.34), true)
	_draw_panel(rect, "")
	var result: Dictionary = snapshot["result"]
	var player_won := str(result.get("winner_faction", "")) == "player"
	var title := "胜利" if player_won else "失败"
	var subtitle := "敌方旗舰已经失去作战能力。" if player_won else "己方旗舰失去作战能力。"
	if str(result.get("reason", "")) == "TIME_LIMIT":
		subtitle = "时间耗尽，按双方剩余总耐久比例判定。"
	elif str(result.get("reason", "")) == "LEVEL_TECHNICAL_LIMIT":
		title = "本局无效"
		subtitle = "达到技术保护上限；本局不判定任务胜负，也不写入进度。"
	var reason_summary := str(result.get("reason_summary", ""))
	if not reason_summary.is_empty(): subtitle = reason_summary
	_draw_result_character(Rect2(rect.position + Vector2(34.0, 28.0), Vector2(400.0, 548.0)))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(470.0, 92.0), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 520.0, 54, TEXT_DARK)
	draw_rect(Rect2(rect.position + Vector2(472.0, 112.0), Vector2(132.0, 5.0)), Color("#70db84") if player_won else Color("#ff9a8c"), true)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(472.0, 156.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 520.0, 22, TEXT_SOFT)
	var duration := _format_duration(float(result.get("elapsed_time", snapshot.get("elapsed_time", 0.0))))
	var rows := [
		"战斗模式：%s" % UiText.mode_name(level_id),
		"战斗时长：%s" % duration,
		"结算类型：%s" % UiText.result_reason_name(str(result.get("reason", ""))),
		"胜利阵营：%s" % UiText.faction_name(str(result.get("winner_faction", ""))),
	]
	if not reason_summary.is_empty(): rows.insert(3, "具体原因：%s" % reason_summary)
	var y := rect.position.y + 228.0
	for row in rows:
		draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 474.0, y), row, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 540.0, 22, TEXT_DARK)
		y += 42.0
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(474.0, 438.0), "复盘提示：留意主要武器待发时间、集火目标和旗舰位置。", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 540.0, 18, TEXT_SOFT)


func _draw_panel(rect: Rect2, title: String) -> void:
	draw_rect(rect, PANEL_FILL, true)
	draw_rect(rect, PANEL_STROKE, false, 2.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 5.0)), Color(0.43, 0.82, 0.96, 0.82), true)
	if not title.is_empty():
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(14.0, 25.0), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28.0, 17, TEXT_DARK)


func _draw_hp_bar(rect: Rect2, current_hp: float, max_hp: float, friendly: bool) -> void:
	var ratio := clampf(current_hp / maxf(1.0, max_hp), 0.0, 1.0)
	draw_rect(rect, Color(0.09, 0.19, 0.24, 0.65), true)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), FRIEND_COLOR if friendly else ENEMY_COLOR, true)


func _draw_portrait(entry: Dictionary, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	var texture := _portrait_texture(entry)
	if texture == null:
		draw_rect(rect, Color(0.16, 0.28, 0.34, 0.74), true)
		return
	_draw_texture_fit(texture, rect, modulate)
	draw_rect(rect, Color(0.86, 0.98, 1.0, 0.56), false, 1.0)


func _draw_icon(icon_name: String, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	var texture := _texture("%s/%s.png" % [UI_ASSET_ROOT, icon_name])
	if texture == null: return
	draw_texture_rect(texture, rect, false, modulate)


func _draw_texture_fit(texture: Texture2D, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	var scale_value := minf(rect.size.x / texture.get_width(), rect.size.y / texture.get_height())
	var draw_size := texture.get_size() * scale_value
	var draw_rect := Rect2(rect.position + (rect.size - draw_size) * 0.5, draw_size)
	draw_texture_rect(texture, draw_rect, false, modulate)


func _friendly_entries() -> Array:
	return player_slots


func _enemy_entries() -> Array:
	var entries: Array = []
	for unit in snapshot.get("units", {}).values():
		if str(unit.get("faction_id", "")) != "enemy": continue
		entries.append(unit)
	entries.sort_custom(func(a, b):
		var slot_a := int(a.get("operation_slot", 999))
		var slot_b := int(b.get("operation_slot", 999))
		return slot_a < slot_b if slot_a != slot_b else str(a.get("display_name", "")) < str(b.get("display_name", ""))
	)
	return entries


func _selected_unit() -> Dictionary:
	var selected_id := str(snapshot.get("selected_unit_id", ""))
	if selected_id.is_empty(): return {}
	return snapshot.get("units", {}).get(selected_id, {})


func _selected_facility() -> Dictionary:
	var selected_id := str(snapshot.get("selected_facility_id", ""))
	if selected_id.is_empty(): return {}
	return snapshot.get("facilities", {}).get(selected_id, {})


func _primary_text() -> String:
	if operation_status.is_empty(): return "不可用"
	var name := str(operation_status.get("primary_name", "主要武器"))
	var reload := float(operation_status.get("primary_reload_remaining", 0.0))
	var mount_status := ""
	if operation_status.get("primary_mount_type", "") == "Torpedo":
		mount_status = " %s/%s 座" % [operation_status.get("primary_mounts_ready", 0), operation_status.get("primary_mounts_total", 0)]
	if bool(operation_status.get("primary_ready", false)): return "%s%s 已就绪" % [name, mount_status]
	return "%s%s %.1f 秒" % [name, mount_status, reload]


func _ammo_text() -> String:
	if operation_status.is_empty() or not bool(operation_status.get("q_enabled", false)): return "不可切换"
	return UiText.ammo_name(str(operation_status.get("selected_ammo", "")))


func _skill_text() -> String:
	if operation_status.is_empty(): return "不可用"
	var skill := DataRegistry.registry.get_definition("skills", str(operation_status.get("skill_id", "")))
	var skill_name := str(skill.get("display_name", "技能"))
	var cooldown := float(operation_status.get("skill_cooldown", 0.0))
	if bool(operation_status.get("skill_ready", false)): return "%s 已就绪" % skill_name
	return "%s %.1f 秒" % [skill_name, cooldown]


func _skill_description() -> String:
	if operation_status.is_empty(): return ""
	var skill := DataRegistry.registry.get_definition("skills", str(operation_status.get("skill_id", "")))
	return str(skill.get("description", skill.get("design_values", "")))


func _short_name(display_name: String) -> String:
	var parts := display_name.split(" ")
	return str(parts[parts.size() - 1]) if parts.size() > 0 else display_name


func _class_icon_name(ship_class: String) -> String:
	match ship_class:
		"Battleship": return "ui_icon_class_battleship"
		"HeavyCruiser": return "ui_icon_class_heavy_cruiser"
		"LightCruiser": return "ui_icon_class_light_cruiser"
		"Destroyer": return "ui_icon_class_destroyer"
		"Submarine": return "ui_icon_class_submarine"
		"Carrier": return "ui_icon_class_carrier"
		_: return ""


func _minimap_icon(unit: Dictionary, friendly: bool) -> String:
	if str(unit.get("ship_class", "")) == "Submarine":
		return "ui_minimap_submarine_player" if friendly else "ui_minimap_submarine_enemy"
	return "ui_minimap_surface_player" if friendly else "ui_minimap_surface_enemy"


func _minimap_position(world_position: Vector2, rect: Rect2, map_data: Dictionary) -> Vector2:
	var map_size := Vector2(float(map_data.get("width", 4096.0)), float(map_data.get("height", 2304.0)))
	return rect.position + Vector2(clampf(world_position.x / maxf(1.0, map_size.x), 0.0, 1.0) * rect.size.x, clampf(world_position.y / maxf(1.0, map_size.y), 0.0, 1.0) * rect.size.y)


func _portrait_texture(entry: Dictionary) -> Texture2D:
	var definition_id := str(entry.get("definition_id", ""))
	if definition_id.is_empty(): return null
	var slug := definition_id.trim_prefix("ship.")
	var asset_root := str(entry.get("asset_root", "res://assets/characters/%s/processed" % slug))
	var small := _texture("%s/ui/%s_ui_portrait_small.png" % [asset_root, slug])
	if small != null: return small
	return _texture("%s/ui/%s_ui_portrait.png" % [asset_root, slug])


func _texture(path: String) -> Texture2D:
	if texture_cache.has(path): return texture_cache[path]
	var resource := load(path)
	texture_cache[path] = resource if resource is Texture2D else null
	return texture_cache[path]


func _create_result_buttons() -> void:
	return_button = Button.new()
	return_button.name = "ReturnToMainButton"
	return_button.text = "返回主界面"
	return_button.size = Vector2(180.0, 48.0)
	return_button.visible = false
	return_button.pressed.connect(func(): return_to_menu_requested.emit())
	add_child(return_button)
	restart_button = Button.new()
	restart_button.name = "RestartBattleButton"
	restart_button.text = "再玩一次"
	restart_button.size = Vector2(180.0, 48.0)
	restart_button.visible = false
	restart_button.pressed.connect(func(): restart_requested.emit())
	add_child(restart_button)


func _sync_result_buttons() -> void:
	if return_button == null or restart_button == null:
		return
	var result_visible: bool = not snapshot.get("result", {}).is_empty()
	return_button.visible = result_visible
	restart_button.visible = result_visible
	if not result_visible:
		return
	var viewport_size := size
	var panel_position := (viewport_size - Vector2(980.0, 620.0)) * 0.5
	return_button.position = panel_position + Vector2(474.0, 516.0)
	restart_button.position = panel_position + Vector2(674.0, 516.0)


func _draw_result_character(rect: Rect2) -> void:
	var character_id := str(snapshot.get("result_character_id", "warspite"))
	var texture := _texture("res://assets/characters/%s/processed/ui/%s_illust_full_alpha.png" % [character_id, character_id])
	if texture == null:
		return
	var scale_value := minf(rect.size.x / texture.get_width(), rect.size.y / texture.get_height())
	var draw_size := texture.get_size() * scale_value
	var draw_rect := Rect2(rect.position + Vector2((rect.size.x - draw_size.x) * 0.5, rect.size.y - draw_size.y), draw_size)
	draw_texture_rect(texture, draw_rect, false, Color(1.0, 1.0, 1.0, 0.96))


func _format_duration(seconds: float) -> String:
	var total_seconds := maxi(0, int(round(seconds)))
	var minutes := int(total_seconds / 60)
	var remainder := total_seconds % 60
	return "%02d:%02d" % [minutes, remainder]
