extends Node

const UiText = preload("res://scripts/presentation/ui_text.gd")
const ProgressSaveStore = preload("res://scripts/infrastructure/persistence/progress_save_store.gd")
const DEFAULT_LEVEL_ID := "level.prototype_3v3"
const USER_SETTINGS_PATH := "user://tiny_sea_war_settings.cfg"
const USER_PROGRESS_PATH := "user://tiny_sea_war_progress.json"
const CUSTOM_LEVEL_ID := "level.custom_runtime"
const DEFAULT_UNLOCKED_SHIP_IDS := [
	"ship.ward", "ship.gnevny", "ship.argus", "ship.hosho", "ship.hai_shih", "ship.u_47",
]

var selected_level_id := DEFAULT_LEVEL_ID
var current_window_size := Vector2i(1920, 1080)
var unlocked_ship_ids: Array[String] = []
var completed_challenge_level_ids: Array[String] = []
var _progress_document: Dictionary = {}
var _progress_store = ProgressSaveStore.new()


func _ready() -> void:
	unlocked_ship_ids.assign(DEFAULT_UNLOCKED_SHIP_IDS)
	_load_unlocked_ships()
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


func is_ship_unlocked(ship_id: String) -> bool:
	return ship_id in unlocked_ship_ids


func _load_unlocked_ships() -> void:
	var parsed := _progress_store.load_best(USER_PROGRESS_PATH)
	if parsed.is_empty():
		return
	_progress_document = parsed.duplicate(true)
	var loaded: Array[String] = []
	for value in parsed.get("unlocked_ship_ids", []):
		var ship_id := str(value)
		if not DataRegistry.registry.get_definition("ships", ship_id).is_empty() and ship_id not in loaded:
			loaded.append(ship_id)
	unlocked_ship_ids = loaded
	completed_challenge_level_ids.clear()
	for value in parsed.get("completed_challenge_level_ids", []):
		var level_id := str(value)
		if not level_id.is_empty() and level_id not in completed_challenge_level_ids:
			completed_challenge_level_ids.append(level_id)


func record_level_victory(level_id: String) -> bool:
	var ship_unlock_id := ""
	match level_id:
		"level.tutorial.t01": ship_unlock_id = "ship.ward"
		"level.challenge.s01": ship_unlock_id = "ship.anshan"
		_: return false
	if not ship_unlock_id.is_empty() and ship_unlock_id not in unlocked_ship_ids:
		unlocked_ship_ids.append(ship_unlock_id)
	if level_id.begins_with("level.challenge.") and level_id not in completed_challenge_level_ids:
		completed_challenge_level_ids.append(level_id)
	_progress_document["schema_version"] = 1
	_progress_document["profile_id"] = "default"
	_progress_document["unlocked_ship_ids"] = unlocked_ship_ids.duplicate()
	_progress_document["completed_challenge_level_ids"] = completed_challenge_level_ids.duplicate()
	_progress_document["updated_at_utc"] = Time.get_datetime_string_from_system(true)
	var saved := _progress_store.save(USER_PROGRESS_PATH, _progress_document)
	if saved:
		_progress_document = _progress_store.load_best(USER_PROGRESS_PATH)
	return saved


func configure_custom_battle(base_level_id: String, map_level_id: String, ocean_palette: String, player_ship_ids: Array[String]) -> Dictionary:
	var base_level: Dictionary = DataRegistry.registry.get_definition("levels", base_level_id)
	var map_level: Dictionary = DataRegistry.registry.get_definition("levels", map_level_id)
	if base_level.is_empty() or map_level.is_empty():
		return {"ok": false, "error": "CUSTOM_LEVEL_SOURCE_MISSING"}
	var spawn_slots: Array = base_level.get("player_fleet", [])
	if player_ship_ids.size() != spawn_slots.size():
		return {"ok": false, "error": "CUSTOM_FLEET_SIZE_MISMATCH"}
	var custom_level := base_level.duplicate(true)
	custom_level["id"] = CUSTOM_LEVEL_ID
	custom_level["display_name"] = "自定义战斗"
	custom_level["battle_mode"] = "CustomBattle"
	custom_level["map"] = map_level.get("map", {}).duplicate(true)
	custom_level["map"]["ocean_palette"] = ocean_palette
	custom_level.erase("require_equal_fleet_cost")
	var custom_fleet: Array = []
	for index in range(player_ship_ids.size()):
		var ship_id := player_ship_ids[index]
		if not is_ship_unlocked(ship_id) or DataRegistry.registry.get_definition("ships", ship_id).is_empty():
			return {"ok": false, "error": "CUSTOM_SHIP_LOCKED_OR_MISSING", "ship_id": ship_id}
		var slot: Dictionary = spawn_slots[index]
		custom_fleet.append({
			"entity_id": "unit.player.custom.%02d" % (index + 1),
			"ship_id": ship_id,
			"position": slot.get("position", []).duplicate(),
			"heading": float(slot.get("heading", 0.0)),
			"is_flagship": index == 0,
		})
	custom_level["player_fleet"] = custom_fleet
	DataRegistry.registry.definitions.get("levels", {})[CUSTOM_LEVEL_ID] = custom_level
	select_level(CUSTOM_LEVEL_ID)
	return {"ok": true, "level_id": CUSTOM_LEVEL_ID}


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
