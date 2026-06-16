extends RefCounted

const CHARACTER_ROOT := "res://assets/characters"
const UI_MANIFEST_PATH := "res://assets/ui/qa/ui_asset_manifest.json"

const CHARACTER_CONFIG_SUFFIXES := {
	"anim": "_anim_config.json",
	"vfx": "_vfx_config.json",
	"bind_points": "_meta_bind_points.json",
	"postprocess": "_postprocess_manifest.json",
}

const UI_SEMANTIC_PREFIXES := {
	"ui_panel_": "ui.panel.",
	"ui_button_": "ui.button.",
	"ui_frame_portrait_": "ui.frame_portrait.",
	"ui_icon_": "ui.icon.",
	"ui_marker_": "ui.marker.",
	"ui_minimap_": "ui.minimap.",
	"ui_log_": "ui.log.",
	"ui_result_": "ui.result.",
	"ui_bar_": "ui.bar.",
	"ui_ring_": "ui.ring.",
	"ui_badge_": "ui.badge.",
}

var characters := {}
var ui_assets := {}
var ui_aliases := {}
var errors: Array[String] = []


func load_all() -> bool:
	characters.clear()
	ui_assets.clear()
	ui_aliases.clear()
	errors.clear()
	_load_characters()
	_load_ui_assets()
	return errors.is_empty()


func has_character(character_id: String) -> bool:
	return characters.has(character_id)


func character(character_id: String) -> Dictionary:
	return characters.get(character_id, {}).duplicate(true)


func animation_state(character_id: String, state_name: String) -> Dictionary:
	var data: Dictionary = characters.get(character_id, {})
	var anim: Dictionary = data.get("configs", {}).get("anim", {})
	return anim.get("states", {}).get(state_name, {}).duplicate(true)


func vfx_role(character_id: String, role_name: String) -> Dictionary:
	var data: Dictionary = characters.get(character_id, {})
	var vfx: Dictionary = data.get("configs", {}).get("vfx", {})
	return vfx.get("roles", {}).get(role_name, {}).duplicate(true)


func bind_points(character_id: String, asset_name: String) -> Dictionary:
	var data: Dictionary = characters.get(character_id, {})
	var bindings: Dictionary = data.get("configs", {}).get("bind_points", {})
	return bindings.get("assets", {}).get(asset_name, {}).duplicate(true)


func battle_asset_path(character_id: String, semantic_name: String) -> String:
	var data: Dictionary = characters.get(character_id, {})
	return str(data.get("battle_assets", {}).get(semantic_name, ""))


func ui_asset_path(asset_key: String, scale := "processed") -> String:
	var asset: Dictionary = ui_asset(asset_key)
	if asset.is_empty():
		return ""
	if scale == "processed":
		return str(asset.get("output", ""))
	for path in asset.get("exports", []):
		var path_text := str(path)
		if path_text.contains("/%s/" % scale):
			return path_text
	return ""


func ui_asset(asset_key: String) -> Dictionary:
	var canonical := str(ui_aliases.get(asset_key, asset_key))
	return ui_assets.get(canonical, {}).duplicate(true)


func _load_characters() -> void:
	var directory := DirAccess.open(CHARACTER_ROOT)
	if directory == null:
		errors.append("Missing character asset directory: %s" % CHARACTER_ROOT)
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir() and not entry.begins_with(".") and entry != "qa":
			_load_character(entry)
		entry = directory.get_next()
	directory.list_dir_end()


func _load_character(character_id: String) -> void:
	var root := "%s/%s/processed" % [CHARACTER_ROOT, character_id]
	var configs := {}
	for config_name in CHARACTER_CONFIG_SUFFIXES:
		var path := "%s/config/%s%s" % [root, character_id, CHARACTER_CONFIG_SUFFIXES[config_name]]
		var parsed := _read_json(path)
		if parsed.is_empty():
			errors.append("Missing or invalid %s config for %s" % [config_name, character_id])
		else:
			configs[config_name] = _normalize_paths(parsed)
	characters[character_id] = {
		"id": character_id,
		"root": root,
		"configs": configs,
		"battle_assets": _scan_named_assets("%s/battle" % root, "%s_battle_" % character_id),
		"ui_assets": _scan_named_assets("%s/ui" % root, "%s_" % character_id),
		"anim_assets": _scan_named_assets("%s/anim" % root, "%s_anim_" % character_id),
		"vfx_assets": _scan_named_assets("%s/vfx" % root, "%s_vfx_" % character_id),
	}


func _scan_named_assets(directory_path: String, prefix: String) -> Dictionary:
	var result := {}
	var directory := DirAccess.open(directory_path)
	if directory == null:
		errors.append("Missing runtime asset directory: %s" % directory_path)
		return result
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".png"):
			var semantic := file_name.get_basename()
			if semantic.begins_with(prefix):
				semantic = semantic.trim_prefix(prefix)
			result[semantic] = "%s/%s" % [directory_path, file_name]
		file_name = directory.get_next()
	directory.list_dir_end()
	return result


func _load_ui_assets() -> void:
	var manifest := _read_json(UI_MANIFEST_PATH)
	if manifest.is_empty():
		errors.append("Missing or invalid UI asset manifest: %s" % UI_MANIFEST_PATH)
		return
	var assets: Array = manifest.get("assets", [])
	for raw_asset in assets:
		if typeof(raw_asset) != TYPE_DICTIONARY:
			errors.append("Non-object UI asset in manifest")
			continue
		var asset: Dictionary = _normalize_paths(raw_asset)
		var name := str(asset.get("name", ""))
		if name.is_empty():
			errors.append("UI asset without name")
			continue
		if ui_assets.has(name):
			errors.append("Duplicate UI asset name: %s" % name)
			continue
		ui_assets[name] = asset
		ui_aliases[name] = name
		ui_aliases[_ui_semantic_key(name)] = name


func _ui_semantic_key(asset_name: String) -> String:
	for prefix in UI_SEMANTIC_PREFIXES:
		if asset_name.begins_with(prefix):
			return "%s%s" % [UI_SEMANTIC_PREFIXES[prefix], asset_name.trim_prefix(prefix)]
	return asset_name


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _normalize_paths(value):
	if typeof(value) == TYPE_DICTIONARY:
		var result := {}
		for key in value:
			result[key] = _normalize_paths(value[key])
		return result
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item in value:
			result.append(_normalize_paths(item))
		return result
	if typeof(value) == TYPE_STRING:
		return _to_res_path(value)
	return value


func _to_res_path(value: String) -> String:
	if value.begins_with("res://") or value.begins_with("user://"):
		return value
	if value.begins_with("assets/") or value.begins_with("data/"):
		return "res://%s" % value
	return value
