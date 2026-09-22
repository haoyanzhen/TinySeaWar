extends SceneTree

const DEFAULT_IDS := ["belfast", "illustrious", "upholder", "dingyuan"]
var checks := 0
var errors: Array[String] = []
var loaded_paths := {}

func _init() -> void:
	var ids: Array = Array(OS.get_cmdline_user_args())
	if ids.is_empty():
		ids = DEFAULT_IDS
	var pattern := RegEx.new()
	pattern.compile("^[a-z0-9_]+$")
	for cid in ids:
		if pattern.search(str(cid)) == null:
			errors.append("Invalid character identifier: " + str(cid))
			continue
		var base: String = "res://assets/characters/%s/processed/" % cid
		for category in ["ui", "battle", "anim", "vfx"]:
			if not DirAccess.dir_exists_absolute(base + category):
				# A shared-only VFX package may legitimately have no local VFX directory.
				if category != "vfx":
					errors.append("Missing asset directory: " + base + category)
				continue
			var count := 0
			for filename in DirAccess.get_files_at(base + category):
				if filename.ends_with(".png"):
					count += 1
					_check_texture(base + category + "/" + filename)
			if count == 0 and category != "vfx":
				errors.append("Empty asset directory: " + base + category)
		var configs := {}
		for name in ["meta_bind_points", "anim_config", "vfx_config", "postprocess_manifest"]:
			checks += 1
			var path: String = base + "config/" + cid + "_" + name + ".json"
			if not FileAccess.file_exists(path):
				errors.append("Missing config: " + path)
				continue
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not parsed is Dictionary or parsed.get("character_id") != cid:
				errors.append("Invalid config: " + path)
				continue
			configs[name] = parsed
		var states = configs.get("anim_config", {}).get("states", {})
		if not states is Dictionary:
			errors.append("Invalid animation states: " + str(cid))
		else:
			for state in ["idle", "move", "attack", "hit", "firepower"]:
				var item = states.get(state, {})
				var frames = item.get("frames", []) if item is Dictionary else []
				if not frames is Array or frames.size() != 4:
					errors.append("Expected four frames: %s:%s" % [cid, state])
					continue
				for frame in frames:
					_check_texture(_resource_path(frame))
		var roles = configs.get("vfx_config", {}).get("roles", {})
		if not roles is Dictionary or roles.is_empty():
			errors.append("Missing VFX references: " + str(cid))
		else:
			for role in roles.values():
				_check_texture(_resource_path(role.get("file", "") if role is Dictionary else ""))
		var bound_assets = configs.get("meta_bind_points", {}).get("assets", {})
		if not bound_assets is Dictionary or bound_assets.is_empty():
			errors.append("Missing bound assets: " + str(cid))
		else:
			for asset_name in bound_assets:
				_check_texture(base + "battle/" + str(asset_name))
	print("ART_BATCH_LOAD: characters=%s checks=%d errors=%s" % [ids, checks, errors])
	quit(0 if errors.is_empty() else 1)

func _resource_path(value: Variant) -> String:
	var path := str(value)
	return path if path.begins_with("res://") else "res://" + path

func _check_texture(path: String) -> void:
	if loaded_paths.has(path):
		return
	loaded_paths[path] = true
	checks += 1
	if not path.begins_with("res://assets/") or not path.ends_with(".png") or not FileAccess.file_exists(path):
		errors.append("Missing/invalid texture: " + path)
		return
	var texture = load(path)
	if not texture is Texture2D or texture.get_width() == 0:
		errors.append("Texture failed to load: " + path)
