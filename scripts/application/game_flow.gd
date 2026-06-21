extends Node

const UiText = preload("res://scripts/presentation/ui_text.gd")
const DEFAULT_LEVEL_ID := "level.prototype_3v3"
const USER_SETTINGS_PATH := "user://tiny_sea_war_settings.cfg"

var selected_level_id := DEFAULT_LEVEL_ID
var current_window_size := Vector2i(1920, 1080)


func _ready() -> void:
	var settings := presentation_settings()
	current_window_size = _pair_to_vector(settings.get("window", {}).get("default_size", [1920, 1080]))
	var config := ConfigFile.new()
	if config.load(USER_SETTINGS_PATH) == OK:
		var saved_size := Vector2i(
			int(config.get_value("display", "width", current_window_size.x)),
			int(config.get_value("display", "height", current_window_size.y))
		)
		if is_window_size_option(saved_size):
			current_window_size = saved_size
	_apply_window_size_to_display(current_window_size)


func select_level(level_id: String) -> void:
	selected_level_id = level_id if not level_id.is_empty() else DEFAULT_LEVEL_ID


func selected_mode_label() -> String:
	return UiText.mode_name(selected_level_id)


func presentation_settings() -> Dictionary:
	return DataRegistry.registry.get_definition("settings", "settings.presentation")


func window_size_options() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for value in presentation_settings().get("window", {}).get("size_options", []):
		result.append(_pair_to_vector(value))
	return result


func logical_viewport_size() -> Vector2i:
	return _pair_to_vector(presentation_settings().get("window", {}).get("logical_size", []))


func is_window_size_option(value: Vector2i) -> bool:
	return value in window_size_options()


func apply_window_size(value: Vector2i) -> bool:
	if not is_window_size_option(value):
		return false
	current_window_size = value
	_apply_window_size_to_display(value)
	var config := ConfigFile.new()
	config.set_value("display", "width", value.x)
	config.set_value("display", "height", value.y)
	return config.save(USER_SETTINGS_PATH) == OK


func _apply_window_size_to_display(value: Vector2i) -> void:
	_configure_content_scaling()
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(value)
	var usable_rect := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var centered_position := usable_rect.position + (usable_rect.size - value) / 2
	DisplayServer.window_set_position(centered_position)


func _configure_content_scaling() -> void:
	var logical_size := logical_viewport_size()
	if logical_size.x <= 0 or logical_size.y <= 0:
		push_error("Logical viewport size is missing or invalid")
		return
	var root_window := get_tree().root
	root_window.content_scale_size = logical_size
	root_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP


func _pair_to_vector(value: Array) -> Vector2i:
	if value.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(value[0]), int(value[1]))
