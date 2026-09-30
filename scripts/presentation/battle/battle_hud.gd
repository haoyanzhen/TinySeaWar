extends Control

signal skill_cutin_mode_changed(mode: String)

signal return_to_menu_requested
signal restart_requested
signal resume_requested
signal pending_cancel_requested(command_id: String)
signal unit_pressed(unit_id: String, additive: bool)
signal action_pressed(key: String)
signal retry_save_requested

const Kit = preload("res://scripts/presentation/ui_theme.gd")
const UiText = preload("res://scripts/presentation/ui_text.gd")
const PANEL_FILL := Color("#f7fcff")
const PANEL_STROKE := Color(0.48, 0.82, 0.95, 0.62)
const TEXT_DARK := Color("#123443")
const TEXT_SOFT := Color("#597986")
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
var skill_cutin_selector: OptionButton
var skill_cutin_save_hint: Label
var pause_panel: PanelContainer
var pending_rows: VBoxContainer
var pending_signature := ""
var pause_confirmation: ConfirmationDialog
var pause_confirmation_action := ""
var interaction_controls: Array[Control] = []
var retry_save_button: Button
var mission_detail_button: Button
var mission_details_open := false
var objective_panel: PanelContainer
var objective_label: Label
var objective_scroll: ScrollContainer
var skin_cache: Dictionary = {}
var pause_button: Button
var weather_button: Button
var weather_details: PanelContainer
var weather_details_label: Label


func battle_rect() -> Rect2:
	return Rect2(Vector2(24.0, 144.0), Vector2(size.x - 424.0, size.y - 324.0))


func minimap_rect() -> Rect2:
	return Rect2(Vector2(size.x - 376.0, 414.0), Vector2(352.0, 238.0))


func operation_rect() -> Rect2:
	return Rect2(Vector2(364.0, size.y - 154.0), Vector2(battle_rect().end.x - 364.0, 136.0))


func roster_rect(friendly: bool) -> Rect2:
	return Rect2(Vector2(24.0 if friendly else size.x - 624.0, 12.0), Vector2(600.0, 120.0))


func roster_cell_rect(index: int, friendly: bool) -> Rect2:
	return Rect2(roster_rect(friendly).position + Vector2(12.0 + (index % 6) * 96.0, 26.0 + int(index / 6) * 46.0), Vector2(88.0, 42.0))


func action_rect(index: int) -> Rect2:
	var dock := operation_rect()
	var width := (dock.size.x - 56.0) / 4.0
	return Rect2(dock.position + Vector2(16.0 + (index % 4) * (width + 8.0), 30.0 + int(index / 4) * 49.0), Vector2(width, 44.0))


func _draw_frame() -> void:
	var sea := battle_rect()
	var paper := Color("#eaf2f5")
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, sea.position.y)), paper)
	draw_rect(Rect2(Vector2(0, sea.end.y), Vector2(size.x, size.y - sea.end.y)), paper)
	draw_rect(Rect2(Vector2(0, sea.position.y), Vector2(sea.position.x, sea.size.y)), paper)
	draw_rect(Rect2(Vector2(sea.end.x, sea.position.y), Vector2(size.x - sea.end.x, sea.size.y)), paper)
	draw_rect(sea.grow(3.0), Color("#ffffff"), false, 4.0)
	draw_rect(sea.grow(1.0), Color("#658b9b"), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(30, size.y - 164), "WASD 视角 / T 全选 / 滚轮缩放 / Space 暂停", HORIZONTAL_ALIGNMENT_LEFT, 400, 14, TEXT_SOFT)


func _ready() -> void:
	_create_hud_theme()
	_create_result_buttons()
	_create_pause_controls()
	_create_interaction_controls()
	_create_weather_controls()


func _create_hud_theme() -> void:
	theme = Kit.make_theme()
	theme.default_font_size = 16
	theme.set_stylebox("panel", "PanelContainer", Kit.panel(Kit.PAPER, 14, 12))


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
	_sync_pause_controls()
	_sync_interaction_controls()
	_sync_weather_controls()
	queue_redraw()


func _draw() -> void:
	if snapshot.is_empty(): return
	var viewport_size := size
	_draw_frame()
	_draw_top_status(viewport_size)
	_draw_level_objective(viewport_size)
	_draw_fleet_panel(roster_rect(true), true)
	_draw_fleet_panel(roster_rect(false), false)
	_draw_operation_dock(operation_rect())
	_draw_minimap(minimap_rect())
	var intelligence := Rect2(Vector2(size.x - 376.0, 668.0), Vector2(352.0, size.y - 692.0))
	if _selected_facility().is_empty(): _draw_log_panel(intelligence)
	else: _draw_facility_panel(intelligence, _selected_facility())
	_draw_selected_summary(Rect2(Vector2(24.0, size.y - 154.0), Vector2(324.0, 136.0)))
	var feedback: Dictionary = snapshot.get("command_feedback", {})
	if not feedback.is_empty():
		var feedback_rect := Rect2(Vector2(operation_rect().position.x, size.y - 180.0), Vector2(900.0, 28.0))
		draw_rect(feedback_rect, Color(0.06, 0.15, 0.2, 0.88))
		draw_string(ThemeDB.fallback_font, feedback_rect.position + Vector2(12.0, 20.0), str(feedback.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, 876.0, 16, Color("#ffe1a0"))
	if not snapshot.get("result", {}).is_empty():
		_draw_result_panel(viewport_size)


func _draw_top_status(viewport_size: Vector2) -> void:
	var panel := Rect2(Vector2((viewport_size.x - 540.0) * 0.5, 14.0), Vector2(540.0, 116.0))
	var phase := str(snapshot.get("phase", ""))
	_draw_icon("ui_icon_menu_intro", Rect2(panel.position + Vector2(12, 14), Vector2(58, 58)))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(84, 34), "小小海战  /  作战指挥", HORIZONTAL_ALIGNMENT_LEFT, 370, 21, TEXT_DARK)
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(84, 62), UiText.mode_name(level_id), HORIZONTAL_ALIGNMENT_LEFT, 340, 16, TEXT_SOFT)
	draw_line(panel.position + Vector2(84, 76), panel.position + Vector2(450, 76), Color("#c2d8df"), 1.0)
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(84, 104), _format_duration(float(snapshot.get("elapsed_time", 0.0))), HORIZONTAL_ALIGNMENT_LEFT, 125, 24, TEXT_DARK)
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(222, 102), UiText.phase_name(phase) + "  ·  Space 暂停 / 继续", HORIZONTAL_ALIGNMENT_LEFT, 300, 14, TEXT_SOFT)


func _draw_level_objective(_viewport_size: Vector2) -> void:
	if snapshot.get("phase", "") == "Paused": return
	_draw_panel(Rect2(Vector2(size.x - 376.0, 144.0), Vector2(352, 258)), "作战任务")


func _draw_fleet_panel(rect: Rect2, friendly: bool) -> void:
	var entries: Array = _friendly_entries() if friendly else _enemy_entries()
	var color := FRIEND_COLOR if friendly else ENEMY_COLOR
	draw_circle(rect.position + Vector2(16, 12), 3.0, color)
	var heading := "我方编队" if friendly else "敌方接触"
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(28, 17), heading, HORIZONTAL_ALIGNMENT_LEFT, 180, 16, TEXT_DARK)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(196, 17), "数字键选舰 · Shift 多选" if friendly else "仅显示已知情报", HORIZONTAL_ALIGNMENT_LEFT, 340, 13, TEXT_SOFT)
	for index in range(12):
		var entry: Dictionary = entries[index] if index < entries.size() else {}
		_draw_roster_cell(roster_cell_rect(index, friendly), entry, index + 1, friendly)


func _draw_roster_cell(rect: Rect2, entry: Dictionary, slot_number: int, friendly: bool) -> void:
	if entry.is_empty():
		# Empty roster space is not an undiscovered enemy contact.
		_draw_round_rect(rect.grow(-2.0), Color("#e1ebef"), 6)
		draw_line(rect.get_center() - Vector2(6, 0), rect.get_center() + Vector2(6, 0), Color("#b1c8d2"), 1.0)
		return
	var alive := str(entry.get("life_state", "Alive")) != "Sunk"
	var selected: bool = str(entry.get("unit_id", entry.get("entity_id", ""))) in snapshot.get("selected_unit_ids", [snapshot.get("selected_unit_id", "")])
	_draw_round_rect(rect, Color("#fff3d6") if selected else Color("#f7fcff"), 7)
	var portrait_rect := Rect2(rect.position + Vector2(2, 0), Vector2(40, 42))
	var frame := "ui_frame_portrait_player" if friendly else "ui_frame_portrait_enemy"
	if selected: frame = "ui_frame_portrait_selected"
	if not alive: frame = "ui_frame_portrait_sunk"
	_draw_skin(frame, portrait_rect, 0)
	_draw_portrait(entry, portrait_rect.grow(-7.0), Color.WHITE if alive else Color(1, 1, 1, 0.4))
	var label := (str(slot_number) if slot_number < 10 else ("0" if slot_number == 10 else "-")) if friendly else "敌"
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(47, 18), label, HORIZONTAL_ALIGNMENT_LEFT, 18, 13, TEXT_DARK)
	_draw_icon(_class_icon_name(str(entry.get("ship_class", ""))), Rect2(rect.position + Vector2(67, 4), Vector2(18, 18)))
	if bool(entry.get("is_flagship", false)):
		_draw_icon("ui_icon_flagship", Rect2(rect.position + Vector2(26, 22), Vector2(18, 18)))
	_draw_hp_bar(Rect2(rect.position + Vector2(46, 27), Vector2(36, 7)), float(entry.get("current_hp", 0)), float(entry.get("max_hp", 1)), friendly)


func _draw_selected_summary(rect: Rect2) -> void:
	_draw_panel(rect, "")
	var selected := _selected_unit()
	_draw_skin("ui_frame_portrait_selected", Rect2(rect.position + Vector2(12, 12), Vector2(92, 108)), 0)
	_draw_portrait(selected, Rect2(rect.position + Vector2(28, 28), Vector2(60, 72)))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(116, 29), "当前指挥  /  %d 艘已选" % snapshot.get("selected_unit_ids", []).size(), HORIZONTAL_ALIGNMENT_LEFT, 192, 13, TEXT_SOFT)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(116, 57), selected_name, HORIZONTAL_ALIGNMENT_LEFT, 190, 22, TEXT_DARK)
	_draw_hp_bar(Rect2(rect.position + Vector2(116, 70), Vector2(186, 10)), float(selected.get("current_hp", 0)), float(selected.get("max_hp", 1)), true)
	var status := "%s  ·  %s" % [UiText.ship_class_name(str(selected.get("ship_class", ""))), "跟随中" if camera_mode == "Follow" else "自由视角"]
	if str(operation_status.get("ship_class", "")) == "Submarine": status = _c_action_text()
	var missions: Array = snapshot.get("aviation", {}).values().filter(func(wave): return wave.get("source_unit_id", "") == snapshot.get("selected_unit_id", "") and wave.get("phase", "") != "Completed")
	if not missions.is_empty():
		status = "航空 %d 队 · %s %.1fs" % [missions.size(), "准备" if missions[0].get("phase", "") == "Scheduled" else "在途", float(missions[0].get("remaining", 0))]
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(116, 104), status, HORIZONTAL_ALIGNMENT_LEFT, 188, 13, TEXT_SOFT)


func _draw_operation_dock(rect: Rect2) -> void:
	_draw_panel(rect, "")
	var title := "舰船指令  /  %s   ·   指令作用于全部 %d 艘已选舰" % [UiText.operation_mode_name(operation_mode), snapshot.get("selected_unit_ids", []).size()]
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(20.0, 21.0), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 44.0, 14, TEXT_SOFT)
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
		var statuses: Array = operation_status.get("selection_statuses", [])
		if statuses.size() > 1:
			var key: String = cards[index]["key"]
			var ready_field := str({"E":"primary_ready", "Q":"q_enabled", "F":"skill_ready"}.get(key, ""))
			if not ready_field.is_empty():
				var count := statuses.filter(func(status): return bool(status.get(ready_field, false))).size()
				cards[index]["text"] = "%s %d/%d" % [{"E":"武器就绪", "Q":"切换弹药", "F":"技能就绪"}[key], count, statuses.size()]
				cards[index]["ready"] = count > 0
			elif key in ["X", "V"]:
				var field := "movement_assist_enabled" if key == "X" else "primary_auto_fire_enabled"
				var applicable := statuses.filter(func(status): return key == "X" or not str(status.get("primary_group_id", "")).is_empty())
				var count := applicable.filter(func(status): return bool(status.get(field, false))).size()
				cards[index]["text"] = "%s %d/%d开" % ["航行" if key == "X" else "主武器", count, applicable.size()]
				cards[index]["ready"] = count > 0
			elif key == "C":
				cards[index]["text"] = "副武器 / 潜艇深度"
				cards[index]["ready"] = true
		_draw_action_card(action_rect(index), cards[index])


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
	_draw_skin("ui_button_menu_primary_default" if ready else "ui_button_menu_secondary_disabled", rect, 12)
	_draw_round_rect(Rect2(rect.position + Vector2(8, 9), Vector2(26, 26)), Color("#edf7fa"), 5)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(15, 28), str(card.get("key", "")), HORIZONTAL_ALIGNMENT_LEFT, 20, 16, TEXT_DARK)
	_draw_icon(str(card.get("icon", "")), Rect2(rect.position + Vector2(39, 9), Vector2(26, 26)), Color.WHITE if ready else Color(1, 1, 1, 0.65))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(73, 28), str(card.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 90, 14, TEXT_DARK)


func _draw_minimap(rect: Rect2) -> void:
	_draw_panel(rect, "战术地图")
	var map_rect := Rect2(rect.position + Vector2(14.0, 36.0), rect.size - Vector2(28.0, 68.0))
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
	for wave in snapshot.get("aviation", {}).values():
		if wave.get("phase", "") in ["Scheduled", "Completed"]: continue
		var point := _minimap_position(wave.get("position", Vector2.ZERO), map_rect, map_data)
		var direction := Vector2.RIGHT.rotated(float(wave.get("heading", 0)))
		var friendly: bool = wave.get("faction_id", "") == "player"
		draw_line(point - direction * 4, point + direction * 5, Color("#a5f3ef") if friendly else Color("#ffac83"), 2.0)
		_draw_icon("ui_minimap_aircraft_player" if friendly else "ui_minimap_aircraft_enemy", Rect2(point - Vector2(5, 5), Vector2(10, 10)))
	for contact in snapshot.get("contacts", {}).values():
		var contact_position := _minimap_position(contact.get("last_known_position", Vector2.ZERO), map_rect, map_data)
		var contact_color := Color(0.35, 0.9, 1.0, 0.9) if contact.get("primary_contact_type", "") == "Radar" else Color(1.0, 0.72, 0.72, 0.8)
		_draw_icon("ui_icon_unknown_contact", Rect2(contact_position - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), contact_color)
	if snapshot.has("camera_rect"):
		var camera_rect: Rect2 = snapshot["camera_rect"]
		var top_left := _minimap_position(camera_rect.position, map_rect, map_data)
		var bottom_right := _minimap_position(camera_rect.position + camera_rect.size, map_rect, map_data)
		draw_rect(Rect2(top_left, bottom_right - top_left), Color(1.0, 1.0, 1.0, 0.85), false, 1.5)
		_draw_icon("ui_minimap_camera_frame", Rect2(top_left - Vector2(8.0, 8.0), Vector2(16.0, 16.0)), Color(1.0, 1.0, 1.0, 0.8))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(14.0, rect.size.y - 14.0), "WASD 移动镜头  |  T 全选己方舰队", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28.0, 13, TEXT_SOFT)


func _draw_minimap_terrain(map_rect: Rect2, map_data: Dictionary) -> void:
	var terrain_id := str(snapshot.get("terrain_map", {}).get("id", ""))
	if terrain_id.is_empty():
		return
	var path := DataRegistry.assets.minimap_asset_path(terrain_id)
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
	var y := rect.position.y + 64.0
	for message in recent_messages.slice(maxi(0, recent_messages.size() - maxi(1, int((rect.size.y - 60.0) / 36.0)))):
		_draw_icon("ui_log_contact_enemy" if message.contains("沉没") else "ui_log_last_contact", Rect2(Vector2(rect.position.x + 14.0, y - 17.0), Vector2(18.0, 18.0)))
		draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 40.0, y), message, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 54.0, 15, TEXT_DARK)
		y += 36.0
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
	# Kept as an empty compatibility hook; actual controls leave the sea interactive.
	pass


func _create_pause_controls() -> void:
	pause_panel = PanelContainer.new()
	pause_panel.name = "TacticalPauseToolbar"
	pause_panel.position = Vector2(28.0, 174.0)
	pause_panel.custom_minimum_size = Vector2(330.0, 0.0)
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(pause_panel)
	var column := VBoxContainer.new()
	pause_panel.add_child(column)
	var title := Label.new()
	title.text = "战术暂停 · 指令恢复后执行"
	column.add_child(title)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	for action in ["继续", "重新开始", "退出战斗"]:
		var button := Button.new()
		button.text = action
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(104.0, 34.0)
		button.pressed.connect(_pause_action.bind(action))
		buttons.add_child(button)
	skill_cutin_selector = OptionButton.new()
	skill_cutin_selector.name = "SkillCutinMode"
	skill_cutin_selector.focus_mode = Control.FOCUS_NONE
	for label in ["技能立绘：完整", "技能立绘：简化", "技能立绘：关闭"]: skill_cutin_selector.add_item(label)
	skill_cutin_selector.select(["full", "simple", "off"].find(GameFlow.skill_cutin_mode))
	skill_cutin_selector.item_selected.connect(func(index):
		var value: String = ["full", "simple", "off"][index]
		var saved := GameFlow.save_skill_cutin_mode(value)
		skill_cutin_save_hint.text = "" if saved else "设置未保存，本次会话仍生效；请重新选择以重试"
		skill_cutin_save_hint.visible = not saved
		skill_cutin_mode_changed.emit(value))
	column.add_child(skill_cutin_selector)
	skill_cutin_save_hint = Label.new()
	skill_cutin_save_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skill_cutin_save_hint.add_theme_font_size_override("font_size", 12)
	skill_cutin_save_hint.custom_minimum_size.x = 280.0
	skill_cutin_save_hint.hide()
	column.add_child(skill_cutin_save_hint)
	var hint := Label.new()
	hint.text = "可继续操作 · 待执行计划可逐条撤销"
	column.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(310.0, 32.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	pending_rows = VBoxContainer.new()
	pending_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pending_rows)
	pause_confirmation = ConfirmationDialog.new()
	pause_confirmation.title = "确认离开当前战斗"
	pause_confirmation.ok_button_text = "确认"
	pause_confirmation.cancel_button_text = "取消"
	pause_confirmation.confirmed.connect(func():
		if pause_confirmation_action == "重新开始": restart_requested.emit()
		else: return_to_menu_requested.emit())
	add_child(pause_confirmation)


func _pause_action(action: String) -> void:
	if action == "继续":
		resume_requested.emit()
		return
	pause_confirmation_action = action
	pause_confirmation.dialog_text = "%s？当前对局和待执行指令将丢弃。" % action
	pause_confirmation.popup_centered(Vector2i(410, 130))


func _sync_pause_controls() -> void:
	if pause_panel == null: return
	var was_visible := pause_panel.visible
	pause_panel.visible = snapshot.get("phase", "") == "Paused"
	if pause_panel.visible and not was_visible:
		pause_panel.modulate.a = 0.3
		create_tween().tween_property(pause_panel, "modulate:a", 1.0, 0.01 if bool(GameFlow.menu_preferences.get("reduce_motion", false)) else 0.18)
	if not pause_panel.visible:
		pause_confirmation.hide()
		return
	var pending: Array = snapshot.get("pending_player_commands", []).filter(func(command): return command.get("command_type", "") != "RecordTutorialAction" and not command.has("primary_auto_fire_suspended"))
	var signature := str(pending)
	if signature == pending_signature: return
	pending_signature = signature
	for child in pending_rows.get_children():
		pending_rows.remove_child(child)
		child.queue_free()
	if pending.is_empty():
		var empty := Label.new()
		empty.text = "暂无待执行指令"
		pending_rows.add_child(empty)
	for command in pending:
		var row := HBoxContainer.new()
		pending_rows.add_child(row)
		var label := Label.new()
		var unit: Dictionary = snapshot.get("units", {}).get(str(command.get("unit_id", "")), {})
		label.text = "%s · %s" % [str(unit.get("display_name", "编队")), _pending_command_text(command)]
		label.tooltip_text = label.text
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.x = 210.0
		row.add_child(label)
		var cancel := Button.new()
		cancel.text = "撤销"
		cancel.focus_mode = Control.FOCUS_NONE
		cancel.pressed.connect(func(): pending_cancel_requested.emit(str(command.get("command_id", ""))))
		row.add_child(cancel)


func _pending_command_text(command: Dictionary) -> String:
	var text := preload("res://scripts/presentation/battle/player_command_feedback.gd").command_name(str(command.get("command_type", "")))
	for field in ["movement_assist_enabled", "secondary_auto_fire_enabled", "primary_auto_fire_enabled"]:
		if command.has(field):
			var label: String = {"movement_assist_enabled": "航行辅助", "secondary_auto_fire_enabled": "副武器自动", "primary_auto_fire_enabled": "主武器自动"}[field]
			return "%s%s" % [label, "开" if bool(command[field]) else "关"]
	if command.has("target_depth_state"):
		return "上浮" if command["target_depth_state"] == "Surface" else "下潜"
	if command.has("target_position") and typeof(command["target_position"]) == TYPE_VECTOR2:
		var point: Vector2 = command["target_position"]
		return "%s (%d, %d)" % [text, point.x, point.y]
	return text


func _draw_result_panel(viewport_size: Vector2) -> void:
	var rect := Rect2((viewport_size - Vector2(980.0, 620.0)) * 0.5, Vector2(980.0, 620.0))
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.0, 0.06, 0.1, 0.34), true)
	_draw_panel(rect, "")
	var result: Dictionary = snapshot["result"]
	var result_view := preload("res://scripts/presentation/battle/battle_result_presentation.gd").describe(result)
	var title := str(result_view.get("title", "本局无效"))
	var subtitle := str(result_view.get("subtitle", ""))
	var reason_summary := str(result.get("reason_summary", ""))
	_draw_result_character(Rect2(rect.position + Vector2(34.0, 28.0), Vector2(400.0, 548.0)))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(470.0, 92.0), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 520.0, 54, TEXT_DARK)
	draw_rect(Rect2(rect.position + Vector2(472.0, 112.0), Vector2(132.0, 5.0)), result_view.get("color", TEXT_SOFT), true)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(472.0, 156.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 520.0, 22, TEXT_SOFT)
	var duration := _format_duration(float(result.get("elapsed_time", snapshot.get("elapsed_time", 0.0))))
	var rows := [
		"战斗模式：%s" % UiText.mode_name(level_id),
		"战斗时长：%s" % duration,
		"结算类型：%s" % UiText.result_reason_name(str(result.get("reason", ""))),
		"获胜方：%s" % ("无（平局）" if result_view.get("kind") == "Draw" else ("不适用（无效）" if result_view.get("kind") == "Invalid" else UiText.faction_name(str(result.get("winner_faction", ""))))),
	]
	if not reason_summary.is_empty(): rows.insert(3, "具体原因：%s" % reason_summary)
	var y := rect.position.y + 228.0
	for row in rows:
		draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 474.0, y), row, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 540.0, 22, TEXT_DARK)
		y += 42.0
	var save: Dictionary = snapshot.get("progress_save_state", {})
	var save_failed := str(save.get("status", "")) == "Failed"
	var save_text := "进度未保存；奖励暂留本会话，请重试后再退出。" if save_failed else str(save.get("message", ""))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(474.0, 464.0), save_text, HORIZONTAL_ALIGNMENT_LEFT, 480.0, 16, Color("#a04e32") if save_failed else TEXT_SOFT)


func _skin_style(asset_key: String, margin: int = 24) -> StyleBoxTexture:
	var cache_key := "%s:%d" % [asset_key, margin]
	if skin_cache.has(cache_key): return skin_cache[cache_key]
	var texture := _texture(DataRegistry.assets.ui_asset_path(asset_key))
	if texture == null: return null
	var style := StyleBoxTexture.new()
	style.texture = texture
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, margin)
		style.set_content_margin(side, 16)
	skin_cache[cache_key] = style
	return style


func _draw_skin(asset_key: String, rect: Rect2, margin: int = 24) -> void:
	var style := _skin_style(asset_key, margin)
	if style != null: draw_style_box(style, rect)
	else: _draw_round_rect(rect, PANEL_FILL, 10)


func _draw_round_rect(rect: Rect2, color: Color, radius: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)


func _draw_panel(rect: Rect2, title: String) -> void:
	if not skin_cache.has("shared_panel"):
		skin_cache["shared_panel"] = Kit.panel(Kit.PAPER, 12, 12)
	draw_style_box(skin_cache["shared_panel"], rect)
	if not title.is_empty():
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(20, 30), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40, 17, TEXT_DARK)


func _draw_hp_bar(rect: Rect2, current_hp: float, max_hp: float, _friendly: bool) -> void:
	var ratio := clampf(current_hp / maxf(1, max_hp), 0, 1)
	_draw_skin("ui_bar_track_empty", rect, 4)
	if ratio <= 0: return
	var key := "ui_bar_hp_healthy" if ratio > 0.5 else ("ui_bar_hp_warning" if ratio > 0.25 else "ui_bar_hp_critical")
	var texture := _texture(DataRegistry.assets.ui_asset_path(key))
	if texture != null:
		draw_texture_rect_region(texture, Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), Rect2(Vector2.ZERO, Vector2(texture.get_width() * ratio, texture.get_height())))
	else: draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), FRIEND_COLOR)


func _draw_portrait(entry: Dictionary, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	var texture := _portrait_texture(entry)
	if texture == null:
		draw_rect(rect, Color(0.16, 0.28, 0.34, 0.74), true)
		return
	_draw_texture_fit(texture, rect, modulate)


func _draw_icon(icon_name: String, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	var texture := _texture(DataRegistry.assets.ui_asset_path(icon_name, "2x"))
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
	var small := _texture(DataRegistry.assets.character_ui_asset_path(slug, "ui_portrait_small"))
	if small != null: return small
	return _texture(DataRegistry.assets.character_ui_asset_path(slug, "ui_portrait"))


func _texture(path: String) -> Texture2D:
	if path.is_empty(): return null
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
	var texture := _texture(DataRegistry.assets.character_ui_asset_path(character_id, "illust_full_alpha"))
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


func _make_hit_button() -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	var clear := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", clear)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.4, 0.85, 1.0, 0.13)
	hover.set_corner_radius_all(8)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("disabled", clear)
	add_child(button)
	interaction_controls.append(button)
	return button


func _create_interaction_controls() -> void:
	pause_button = Button.new()
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.tooltip_text = "暂停 / 继续 · Space"
	pause_button.expand_icon = true
	pause_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	pause_button.add_theme_stylebox_override("hover", _skin_style("ui_button_small_hover", 12))
	pause_button.pressed.connect(func(): action_pressed.emit("SPACE"))
	add_child(pause_button)
	# Transparent real controls preserve the existing art while owning GUI input.
	for index in range(24):
		var button := _make_hit_button()
		button.name = "RosterHit%d" % index
		button.pressed.connect(_roster_pressed.bind(index))
	for key in ["E", "Q", "F", "G", "Z", "X", "C", "V"]:
		var button := _make_hit_button()
		button.name = "ActionHit%s" % key
		button.tooltip_text = "%s · %s" % [key, "跟随主焦点舰" if key == "G" else "对全部选中舰执行；逐舰检查条件"]
		button.pressed.connect(func(): action_pressed.emit(key))
	retry_save_button = Button.new()
	retry_save_button.text = "重试保存"
	retry_save_button.focus_mode = Control.FOCUS_NONE
	retry_save_button.pressed.connect(func(): retry_save_requested.emit())
	add_child(retry_save_button)
	mission_detail_button = Button.new()
	mission_detail_button.text = "任务详情"
	mission_detail_button.focus_mode = Control.FOCUS_NONE
	mission_detail_button.pressed.connect(func(): mission_details_open = not mission_details_open; queue_redraw())
	objective_panel = PanelContainer.new()
	objective_panel.name = "ObjectivePanel"
	objective_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxEmpty.new()
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	objective_panel.add_theme_stylebox_override("panel", style)
	objective_scroll = ScrollContainer.new()
	objective_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(objective_scroll)
	objective_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective_scroll.add_child(objective_panel)
	var column := VBoxContainer.new()
	objective_panel.add_child(column)
	objective_label = Label.new()
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.add_theme_color_override("font_color", TEXT_DARK)
	objective_label.add_theme_font_size_override("font_size", 17)
	objective_label.add_theme_constant_override("line_spacing", 8)
	column.add_child(objective_label)
	column.add_child(mission_detail_button)


func _roster_pressed(index: int) -> void:
	var entries: Array = _friendly_entries() if index < 12 else _enemy_entries()
	var slot := index % 12
	if slot >= entries.size(): return
	var entry: Dictionary = entries[slot]
	unit_pressed.emit(str(entry.get("unit_id", entry.get("entity_id", ""))), Input.is_key_pressed(KEY_SHIFT))


func _sync_interaction_controls() -> void:
	var active: bool = snapshot.get("result", {}).is_empty()
	pause_button.visible = active
	pause_button.position = Vector2((size.x - 540.0) * 0.5 + 466.0, 30.0)
	pause_button.size = Vector2(48, 48)
	pause_button.icon = _texture(DataRegistry.assets.ui_asset_path("ui_icon_continue" if snapshot.get("phase", "") == "Paused" else "ui_icon_pause", "2x"))
	for index in range(interaction_controls.size()):
		var button := interaction_controls[index]
		button.visible = active
		if index < 24:
			var slot := index % 12
			var cell := roster_cell_rect(slot, index < 12)
			button.position = cell.position
			button.size = cell.size
			var entries := _friendly_entries() if index < 12 else _enemy_entries()
			button.disabled = slot >= entries.size()
			button.tooltip_text = str(entries[slot].get("display_name", "未知")) if slot < entries.size() else "空槽"
		else:
			var slot := index - 24
			button.position = action_rect(slot).position
			button.size = action_rect(slot).size
			if slot == 0: button.tooltip_text = _primary_text()
			elif slot == 2: button.tooltip_text = _skill_text() + "\n" + _skill_description()
	var save: Dictionary = snapshot.get("progress_save_state", {})
	retry_save_button.visible = not active and bool(save.get("can_retry", false))
	retry_save_button.position = (size - Vector2(980.0, 620.0)) * 0.5 + Vector2(474.0, 476.0)
	retry_save_button.size = Vector2(150.0, 32.0)
	mission_detail_button.visible = active and not snapshot.get("level_objective", {}).get("mission_steps", []).is_empty()
	objective_panel.visible = active
	objective_scroll.visible = objective_panel.visible and snapshot.get("phase", "") != "Paused"
	objective_scroll.position = Vector2(size.x - 372.0, 180.0)
	objective_scroll.size = Vector2(344.0, 216.0)
	objective_panel.custom_minimum_size.x = 330.0
	pause_panel.position = Vector2(size.x - 376.0, 144.0)
	pause_panel.size = Vector2(352.0, 258.0)
	var objective: Dictionary = snapshot.get("level_objective", {})
	var lines: Array[String] = ["%s：%s" % [objective.get("title", "任务"), objective.get("summary", "")]]
	if bool(objective.get("is_tutorial", false)):
		lines.append("当前操作：%s" % objective.get("instruction", ""))
		if not str(objective.get("ability_limit_text", "")).is_empty(): lines.append(str(objective["ability_limit_text"]))
	else:
		var steps: Array = objective.get("mission_steps", [])
		var completed: int = steps.filter(func(step): return bool(step.get("completed", false))).size()
		lines.append("目标 %d/%d" % [completed, steps.size()])
		if mission_details_open:
			for step in steps: lines.append(("✓ " if bool(step.get("completed", false)) else "○ ") + str(step.get("label", "")))
			for line in objective.get("protection_lines", []): lines.append(str(line))
			for field in ["reinforcement_hint", "optional_mastery"]:
				if not str(objective.get(field, "")).is_empty(): lines.append(str(objective[field]))
	if objective.is_empty():
		lines = ["作战指引", "击沉敌方旗舰，保护己方旗舰。", "", "选择舰船，右键下达移动指令。", "按 Space 暂停，可规划下一步。"]
	objective_label.text = "\n".join(lines)
	mission_detail_button.text = "收起任务详情" if mission_details_open else "任务详情 · 保护 / 增援 / 精通"


func _create_weather_controls() -> void:
	weather_button = Button.new()
	weather_button.flat = true
	for style in ["normal", "hover", "pressed", "focus", "disabled"]:
		weather_button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	weather_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weather_button.add_theme_font_size_override("font_size", 14)
	weather_button.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(weather_button)
	weather_details = PanelContainer.new()
	weather_details.mouse_filter = Control.MOUSE_FILTER_STOP
	weather_details.custom_minimum_size = Vector2(500, 300)
	weather_details.size = Vector2(500, 300)
	weather_details.resized.connect(func(): weather_details.position = battle_rect().get_center() - weather_details.size * 0.5)
	add_child(weather_details)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 12)
	weather_details.add_child(column)
	weather_details_label = Label.new()
	weather_details_label.custom_minimum_size.x = 460
	weather_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	weather_details_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(weather_details_label)
	var close := Button.new()
	close.name = "Close"
	close.text = "关闭"
	close.custom_minimum_size.y = 34
	column.add_child(close)
	close.pressed.connect(func(): weather_details.hide())
	weather_details.hide()
	weather_button.pressed.connect(func(): weather_details.visible = not weather_details.visible)


func _sync_weather_controls() -> void:
	if weather_button == null: return
	weather_button.visible = snapshot.get("command_feedback", {}).is_empty()
	var environment: Dictionary = snapshot.get("global_environment", {})
	var effects: Dictionary = environment.get("global_effects", {})
	weather_button.position = Vector2(380, size.y - 178)
	weather_button.size = Vector2(maxf(100, battle_rect().end.x - 384), 24)
	weather_button.text = "%s / 海况%d · 详情" % [UiText.palette_name(str(environment.get("canonical_ocean_palette", palette_id))), int(effects.get("sea_state", 0))]
	var forecast: Dictionary = environment.get("forecast", {})
	if not forecast.is_empty():
		weather_button.text += "  |  %d秒后 %s" % [ceili(float(forecast.get("remaining_seconds", 0))), UiText.palette_name(str(forecast.get("ocean_palette", "")))]
	var aviation := {"Normal":"正常", "Restricted":"受限", "Severe":"恶劣（常规航空攻击禁飞）", "Grounded":"禁飞"}
	var details := "%s\n全局条件（未叠加局部区域）\n\n光学倍率：%.2f    航速倍率：%.2f\n命中修正：%+.2f    鱼雷散布倍率：%.2f\n航空延迟倍率：%.3f\n航空条件：%s\n\n局部环境可能进一步修正上述效果。" % [UiText.palette_name(str(environment.get("canonical_ocean_palette", palette_id))), float(effects.get("optical_visibility_multiplier", 1)), float(effects.get("movement_speed_multiplier", 1)), float(effects.get("weapon_accuracy_modifier", 0)), float(effects.get("torpedo_sigma_multiplier", 1)), float(effects.get("aviation_delay_multiplier", 1)), str(aviation.get(str(effects.get("aviation_condition", "Normal")), "未知"))]
	weather_button.tooltip_text = details
	weather_details_label.text = details
	weather_details.position = battle_rect().get_center() - weather_details.size * 0.5
