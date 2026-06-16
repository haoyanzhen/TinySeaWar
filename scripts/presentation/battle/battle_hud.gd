extends Control

var snapshot := {}
var level_id := ""
var recent_messages: Array[String] = []
var camera_mode := "Manual"
var selected_name := "None"
var palette_id := "day_clear"
var operation_status := {}
var operation_mode := "NORMAL"
var player_slots: Array = []


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
	queue_redraw()


func _draw() -> void:
	if snapshot.is_empty(): return
	var viewport_size := size
	draw_rect(Rect2(Vector2.ZERO, Vector2(viewport_size.x, 104.0)), Color(0.025, 0.075, 0.11, 0.9), true)
	draw_rect(Rect2(Vector2(0.0, viewport_size.y - 142.0), Vector2(viewport_size.x, 142.0)), Color(0.025, 0.075, 0.11, 0.92), true)
	var title := "Tiny Sea War - %s  |  %.1fs  |  %s" % [level_id.trim_prefix("level."), float(snapshot.get("elapsed_time", 0.0)), snapshot.get("phase", "")]
	draw_string(ThemeDB.fallback_font, Vector2(64.0, 45.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, Color.WHITE)
	var state_text := "Camera: %s  |  Selected: %s  |  Mode: %s  |  Ocean: %s" % [camera_mode, selected_name, operation_mode, palette_id]
	draw_string(ThemeDB.fallback_font, Vector2(64.0, 79.0), state_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color("#9fd2df"))
	var primary_text := _primary_text()
	var ammo_text := _ammo_text()
	var skill_text := _skill_text()
	var follow_text := "V %s" % ("Following" if camera_mode == "Follow" else "Follow")
	draw_string(ThemeDB.fallback_font, Vector2(64.0, viewport_size.y - 116.0), "%s    %s    %s    %s" % [primary_text, ammo_text, skill_text, follow_text], HORIZONTAL_ALIGNMENT_LEFT, viewport_size.x - 128.0, 18, Color("#bddbe4"))
	var help := "1-9/0/- select slot  E aim primary  Left confirm/select/focus  Right cancel aim or move  F skill  Q ammo  V follow  Esc cancel  Space pause"
	draw_string(ThemeDB.fallback_font, Vector2(64.0, viewport_size.y - 92.0), help, HORIZONTAL_ALIGNMENT_LEFT, viewport_size.x - 128.0, 18, Color("#bddbe4"))
	draw_string(ThemeDB.fallback_font, Vector2(64.0, 102.0), _slot_text(), HORIZONTAL_ALIGNMENT_LEFT, viewport_size.x - 128.0, 16, Color("#8fc4d4"))
	var y := viewport_size.y - 34.0
	for message in recent_messages:
		draw_string(ThemeDB.fallback_font, Vector2(64.0, y), message, HORIZONTAL_ALIGNMENT_LEFT, viewport_size.x - 128.0, 17, Color("#e6edf0"))
		y -= 22.0
	if not snapshot.get("result", {}).is_empty():
		var panel_size := Vector2(700.0, 130.0)
		var panel_position := (viewport_size - panel_size) * 0.5
		var result: Dictionary = snapshot["result"]
		var result_text := "%s wins - %s" % [result.get("winner_faction", "?"), result.get("reason", "")]
		draw_rect(Rect2(panel_position, panel_size), Color(0.02, 0.05, 0.08, 0.94), true)
		draw_string(ThemeDB.fallback_font, panel_position + Vector2(70.0, 80.0), result_text, HORIZONTAL_ALIGNMENT_CENTER, panel_size.x - 140.0, 36, Color.WHITE)


func _primary_text() -> String:
	if operation_status.is_empty(): return "E disabled"
	var name := str(operation_status.get("primary_name", "Primary"))
	var reload := float(operation_status.get("primary_reload_remaining", 0.0))
	if bool(operation_status.get("primary_ready", false)): return "E %s ready" % name
	return "E %s %.1fs" % [name, reload]


func _ammo_text() -> String:
	if operation_status.is_empty() or not bool(operation_status.get("q_enabled", false)): return "Q disabled"
	return "Q %s" % operation_status.get("selected_ammo", "?")


func _skill_text() -> String:
	if operation_status.is_empty(): return "F disabled"
	var cooldown := float(operation_status.get("skill_cooldown", 0.0))
	if bool(operation_status.get("skill_ready", false)): return "F skill ready"
	return "F skill %.1fs" % cooldown


func _slot_text() -> String:
	var parts: Array[String] = []
	for slot in player_slots:
		var name_parts := str(slot.get("display_name", "?")).split(" ")
		var short_name := str(name_parts[name_parts.size() - 1])
		var label := "%s:%s" % [slot.get("slot", "?"), short_name]
		if slot.get("life_state", "") == "Sunk": label += "(Sunk)"
		parts.append(label)
	return "Slots " + "  ".join(parts)
