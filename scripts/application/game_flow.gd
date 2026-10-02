extends Node

signal progress_save_status_changed(state: Dictionary)

const CustomBattleMatcher = preload("res://scripts/application/custom_battle_matcher.gd")
const UiText = preload("res://scripts/presentation/ui_text.gd")
const ProgressSaveStore = preload("res://scripts/infrastructure/persistence/progress_save_store.gd")
const ShipAcquisitionCatalog = preload("res://scripts/infrastructure/data/ship_acquisition_catalog.gd")
const DEFAULT_LEVEL_ID := "level.prototype_3v3"
const USER_SETTINGS_PATH := "user://tiny_sea_war_settings.cfg"
const USER_PROGRESS_PATH := "user://tiny_sea_war_progress.json"
const CUSTOM_LEVEL_ID := "level.custom_runtime"

var selected_level_id := DEFAULT_LEVEL_ID
var current_window_size := Vector2i(1920, 1080)
var menu_preferences := {"cover_id": "hood_harbor", "reduce_motion": false, "auto_view": true}
var menu_return_page := "home"
var skill_cutin_mode := "full"
var unlocked_ship_ids: Array[String] = []
var completed_challenge_level_ids: Array[String] = []
var _custom_level_definition: Dictionary = {}
var _progress_document: Dictionary = {}
var _progress_store = ProgressSaveStore.new()
var _progress_path := USER_PROGRESS_PATH
var _progress_save_status := "Idle"
var _pending_progress_level_ids: Array[String] = []


func _ready() -> void:
	unlocked_ship_ids = ShipAcquisitionCatalog.defaults(ship_acquisition_catalog())
	_load_unlocked_ships()
	var settings := presentation_settings()
	current_window_size = _pair_to_vector(settings.get("window", {}).get("default_size", [1920, 1080]))
	var config := ConfigFile.new()
	if config.load(USER_SETTINGS_PATH) == OK:
		skill_cutin_mode = normalize_skill_cutin_mode(str(config.get_value("battle", "skill_cutin_mode", "full")))
		for key in menu_preferences:
			menu_preferences[key] = config.get_value("menu", key, menu_preferences[key])
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


func ship_acquisition_catalog() -> Dictionary:
	return DataRegistry.registry.get_definition("progress", ShipAcquisitionCatalog.CATALOG_ID)


func ship_acquisition(ship_id: String) -> Dictionary:
	return ShipAcquisitionCatalog.entry(ship_acquisition_catalog(), ship_id)


func ship_acquisition_label(ship_id: String) -> String:
	var acquisition := ship_acquisition(ship_id)
	var category := str(acquisition.get("category", "Pending"))
	if category == "DefaultOwned":
		return "默认拥有"
	if category == "Pending":
		return "待处理 · 暂无获取途径"
	var source := str(acquisition.get("source_level_id", ""))
	var code := source.get_slice(".", 2).to_upper()
	code = code.left(1) + "-" + code.substr(1)
	var label := "%s · %s 首胜" % ["教学奖励" if category == "TutorialReward" else "挑战奖励", code]
	if DataRegistry.registry.get_definition("levels", source).is_empty():
		label += "（关卡尚未开放）"
	return label


func _apply_loaded_progress(parsed: Dictionary) -> void:
	_progress_document = parsed.duplicate(true)
	var loaded := ShipAcquisitionCatalog.defaults(ship_acquisition_catalog())
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


func runtime_level_definition(level_id: String) -> Dictionary:
	if level_id != CUSTOM_LEVEL_ID or _custom_level_definition.is_empty():
		return {}
	return _custom_level_definition.duplicate(true)


func _load_unlocked_ships() -> void:
	var parsed := _progress_store.load_best(_progress_path)
	if parsed.is_empty():
		return
	_apply_loaded_progress(parsed)


func record_level_victory(level_id: String) -> bool:
	var level: Dictionary = DataRegistry.registry.get_definition("levels", level_id)
	if level.is_empty() or str(level.get("battle_mode", "")) not in ["TutorialBattle", "ChallengeBattle"]:
		return false
	var rewards := ShipAcquisitionCatalog.rewards(ship_acquisition_catalog(), level_id)
	# Tutorials without persistent rewards need no save transaction.
	if rewards.is_empty() and not level_id.begins_with("level.challenge."):
		return true
	for ship_id in rewards:
		if ship_id not in unlocked_ship_ids:
			unlocked_ship_ids.append(ship_id)
	if level_id.begins_with("level.challenge.") and level_id not in completed_challenge_level_ids:
		completed_challenge_level_ids.append(level_id)
	_progress_document["schema_version"] = 1
	_progress_document["profile_id"] = "default"
	# Preserve unknown IDs for forward compatibility without making them playable.
	var persisted_ids: Array = _progress_document.get("unlocked_ship_ids", []).duplicate()
	for ship_id in unlocked_ship_ids:
		if ship_id not in persisted_ids:
			persisted_ids.append(ship_id)
	_progress_document["unlocked_ship_ids"] = persisted_ids
	_progress_document["completed_challenge_level_ids"] = completed_challenge_level_ids.duplicate()
	_progress_document["updated_at_utc"] = Time.get_datetime_string_from_system(true)
	if level_id not in _pending_progress_level_ids:
		_pending_progress_level_ids.append(level_id)
	return _save_pending_progress()


func progress_save_state() -> Dictionary:
	var message := ""
	if _progress_save_status == "Saved":
		message = "进度已保存"
	elif _progress_save_status == "Failed":
		message = "进度保存失败。本次奖励已在当前会话保留，请重试保存后再关闭游戏。"
	return {
		"status": _progress_save_status,
		"message": message,
		"can_retry": not _pending_progress_level_ids.is_empty(),
		"pending_level_ids": _pending_progress_level_ids.duplicate(),
	}


func retry_progress_save() -> bool:
	# Retry the accumulated facts, never replay victory/reward application.
	if _pending_progress_level_ids.is_empty():
		return true
	return _save_pending_progress()


func _save_pending_progress() -> bool:
	var saved: bool = _progress_store.save(_progress_path, _progress_document)
	var verified: Dictionary = _progress_store.load_best(_progress_path) if saved else {}
	# A successful write must be readable and contain every fact being committed.
	if saved:
		for field in ["unlocked_ship_ids", "completed_challenge_level_ids"]:
			for fact in _progress_document.get(field, []):
				if fact not in verified.get(field, []):
					saved = false
		saved = saved and not verified.is_empty()
	if saved:
		_progress_document = verified
		_pending_progress_level_ids.clear()
	_progress_save_status = "Saved" if saved else "Failed"
	progress_save_status_changed.emit(progress_save_state())
	return saved


func configure_custom_battle(base_level_id: String, map_level_id: String, ocean_palette: String, player_ship_ids: Array[String], environment_timeline_id: String = "", difficulty: String = "Standard", roster_seed: int = -1, battle_seed: int = -1, preview_only: bool = false) -> Dictionary:
	var base_level: Dictionary = DataRegistry.registry.get_definition("levels", base_level_id)
	var map_level: Dictionary = DataRegistry.registry.get_definition("levels", map_level_id)
	if base_level.is_empty() or map_level.is_empty():
		return {"ok": false, "error": "CUSTOM_LEVEL_SOURCE_MISSING"}
	var base_player_fleet: Array = base_level.get("player_fleet", [])
	if base_level_id not in ["level.prototype_1v1", "level.prototype_3v3", "level.prototype_5v5", "level.prototype_11v11"]:
		return {"ok":false, "error":"CUSTOM_SCALE_INVALID"}
	var unique_players := {}
	for ship_id in player_ship_ids:
		if unique_players.has(ship_id): return {"ok":false, "error":"CUSTOM_DUPLICATE_PLAYER_SHIP"}
		unique_players[ship_id] = true
	var player_spawn_slots := _custom_spawn_slots(map_level, "player")
	var enemy_spawn_slots := _custom_spawn_slots(map_level, "enemy")
	if player_ship_ids.size() != base_player_fleet.size():
		return {"ok": false, "error": "CUSTOM_FLEET_SIZE_MISMATCH"}
	if player_spawn_slots.size() < base_player_fleet.size() or enemy_spawn_slots.size() < base_player_fleet.size():
		return {"ok": false, "error": "CUSTOM_MAP_SPAWN_COUNT_MISMATCH"}
	var custom_level := base_level.duplicate(true)
	custom_level["id"] = CUSTOM_LEVEL_ID
	custom_level["display_name"] = "自定义战斗"
	custom_level["battle_mode"] = "CustomBattle"
	custom_level["map"] = map_level.get("map", {}).duplicate(true)
	custom_level["map"].erase("environment_timeline_id")
	custom_level["map"]["ocean_palette"] = ocean_palette
	if not environment_timeline_id.is_empty():
		var timeline: Dictionary = DataRegistry.registry.get_definition("environment_zones", environment_timeline_id)
		if not DataRegistry.registry.validate_environment_timeline(timeline).is_empty(): return {"ok":false, "error":"INVALID_ENVIRONMENT_TIMELINE"}
		custom_level["map"]["environment_timeline_id"] = environment_timeline_id
		custom_level["map"]["ocean_palette"] = str(timeline.stages[0].ocean_palette)
	if not DataRegistry.registry.validate_environment_map(custom_level["map"]).is_empty(): return {"ok":false, "error":"INVALID_ENVIRONMENT_MAP"}
	custom_level.erase("require_equal_fleet_cost")
	var custom_fleet: Array = []
	for index in range(player_ship_ids.size()):
		var ship_id := player_ship_ids[index]
		if not is_ship_unlocked(ship_id) or DataRegistry.registry.get_definition("ships", ship_id).is_empty():
			return {"ok": false, "error": "CUSTOM_SHIP_LOCKED_OR_MISSING", "ship_id": ship_id}
		var slot: Dictionary = player_spawn_slots[index]
		custom_fleet.append({
			"entity_id": "unit.player.custom.%02d" % (index + 1),
			"ship_id": ship_id,
			"position": slot.get("position", []).duplicate(),
			"heading": float(slot.get("heading", 0.0)),
			"is_flagship": index == 0,
		})
	custom_level["player_fleet"] = custom_fleet
	var matcher = CustomBattleMatcher.new(DataRegistry.registry)
	if not matcher.spawns_legal(player_ship_ids, player_spawn_slots, custom_level["map"]):
		return {"ok":false, "error":"CUSTOM_PLAYER_SPAWN_INVALID"}
	if roster_seed < 0: roster_seed = new_custom_seed()
	if battle_seed < 0: battle_seed = new_custom_seed()
	var matched: Dictionary = matcher.choose(player_ship_ids.size(), matcher.fleet_cost(player_ship_ids), difficulty, enemy_spawn_slots, custom_level["map"], roster_seed)
	if not matched.ok: return matched
	custom_level["enemy_ai_profile_id"] = matched.enemy_ai_profile_id
	var custom_enemy_fleet: Array = []
	for index in range(matched.roster.ship_ids.size()):
		var slot: Dictionary = enemy_spawn_slots[index]
		var ship_id := str(matched.roster.ship_ids[index])
		custom_enemy_fleet.append({"entity_id":"unit.enemy.custom.%02d" % (index + 1), "ship_id":ship_id, "position":slot.position.duplicate(), "heading":float(slot.get("heading", 0.0)), "is_flagship":ship_id == matched.roster.flagship_ship_id})
	custom_level["enemy_fleet"] = custom_enemy_fleet
	custom_level["custom_match"] = {"roster_id":matched.roster.id, "pool_version":matched.pool_version, "roster_seed":roster_seed, "battle_seed":battle_seed, "difficulty":difficulty, "player_cost":matched.player_cost, "enemy_cost":matched.enemy_cost, "lower":matched.lower, "upper":matched.upper, "candidate_count":matched.candidate_count}
	if not preview_only:
		_custom_level_definition = custom_level.duplicate(true)
		select_level(CUSTOM_LEVEL_ID)
	matched["level_id"] = CUSTOM_LEVEL_ID
	matched["level"] = custom_level
	matched["battle_seed"] = battle_seed
	return matched


func new_custom_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, 2147483647)


func _custom_spawn_slots(map_level: Dictionary, faction_id: String) -> Array:
	var map: Dictionary = map_level.get("map", {})
	var terrain_id := str(map.get("terrain_definition_id", ""))
	if terrain_id.is_empty():
		return map_level.get("%s_fleet" % faction_id, []).duplicate(true)
	var terrain: Dictionary = DataRegistry.registry.get_definition("terrain", terrain_id)
	var result: Array = terrain.get("spawn_points", []).filter(func(spawn): return str(spawn.get("faction_id", "")) == faction_id)
	result.sort_custom(func(a, b): return int(str(a.get("id", "")).trim_prefix("%s_" % faction_id)) < int(str(b.get("id", "")).trim_prefix("%s_" % faction_id)))
	return result


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
	config.load(USER_SETTINGS_PATH)
	config.set_value("display", "width", value.x)
	config.set_value("display", "height", value.y)
	return config.save(USER_SETTINGS_PATH) == OK


func save_menu_preference(key: String, value: Variant) -> bool:
	if not menu_preferences.has(key):
		return false
	menu_preferences[key] = value
	var config := ConfigFile.new()
	config.load(USER_SETTINGS_PATH)
	config.set_value("menu", key, value)
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


func normalize_skill_cutin_mode(value: String) -> String:
	return value if value in ["full", "simple", "off"] else "full"


func save_skill_cutin_mode(value: String, path := USER_SETTINGS_PATH) -> bool:
	skill_cutin_mode = normalize_skill_cutin_mode(value)
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK and error != ERR_FILE_NOT_FOUND: return false
	config.set_value("battle", "skill_cutin_mode", skill_cutin_mode)
	return config.save(path) == OK
