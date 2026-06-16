extends Control

var snapshot := {}
var level_id := ""
var recent_messages: Array[String] = []
var camera_mode := "Manual"
var selected_name := "None"
var palette_id := "day_clear"


func update_state(new_snapshot: Dictionary, new_level_id: String, messages: Array[String], new_camera_mode: String, new_selected_name: String, new_palette_id: String) -> void:
	snapshot = new_snapshot
	level_id = new_level_id
	recent_messages = messages.duplicate()
	camera_mode = new_camera_mode
	selected_name = new_selected_name
	palette_id = new_palette_id
	queue_redraw()


func _draw() -> void:
	if snapshot.is_empty(): return
	var viewport_size := size
	draw_rect(Rect2(Vector2.ZERO, Vector2(viewport_size.x, 104.0)), Color(0.025, 0.075, 0.11, 0.9), true)
	draw_rect(Rect2(Vector2(0.0, viewport_size.y - 142.0), Vector2(viewport_size.x, 142.0)), Color(0.025, 0.075, 0.11, 0.92), true)
	var title := "Tiny Sea War - %s  |  %.1fs  |  %s" % [level_id.trim_prefix("level."), float(snapshot.get("elapsed_time", 0.0)), snapshot.get("phase", "")]
	draw_string(ThemeDB.fallback_font, Vector2(64.0, 45.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, Color.WHITE)
	var state_text := "Camera: %s  |  Selected: %s  |  Ocean: %s" % [camera_mode, selected_name, palette_id]
	draw_string(ThemeDB.fallback_font, Vector2(64.0, 79.0), state_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color("#9fd2df"))
	var help := "WASD move camera  F follow selected  Left select  Right move  Q skill  Space pause  7/8/9 ocean  1/3 level"
	draw_string(ThemeDB.fallback_font, Vector2(64.0, viewport_size.y - 92.0), help, HORIZONTAL_ALIGNMENT_LEFT, viewport_size.x - 128.0, 18, Color("#bddbe4"))
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
